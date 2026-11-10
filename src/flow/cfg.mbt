// The control-flow graph (book §2.5, and the substrate chapters 5-8 assume).
//
// WHAT THIS REPLACES AND WHY IT HAD TO BE REPLACED. Every pass in this tree so
// far has been a recursive walk over the AST, and a walk can answer "what does
// this node look like" and cannot answer "what reaches this node". The two
// places where that limit is already recorded in shipped code are the loop case
// in `guardfacts` (a fact is dropped for every name the body assigns, because a
// fact proved before a loop is not a fact after one iteration) and the type
// lens's same-file rule for call signatures. Both need a graph plus a fixed
// point, so the graph comes first.
//
// WHAT IS MODELLED, AND WHAT IS NOT. This is a CFG for ONE FUNCTION BODY:
//
//     Entry -> (body) -> Exit
//     let/assign                      Assign / AssignMulti
//     expression statements           Eval
//     if / else if / else             Test with TWO successors (true, false)
//     while / for / for-update        Test whose true-edge re-enters the body
//     return / raise / break / continue   Stop
//
// THE EXCLUSIONS ARE NAMED RATHER THAN SILENT, because a CFG that quietly drops
// edges is worse than no CFG: every analysis built on it would be sound-looking
// and wrong. `Cfg.skipped` counts the statements this builder did NOT convert,
// and the two real ones are:
//
//   break / continue   modelled as `Stop`. The edge they should add -- to the
//                      loop's exit and to its head -- is not added, so a
//                      `break` inside a loop makes the loop's exit look
//                      unreachable from the break. Analyses built on this must
//                      not claim precision about breaks until that is fixed.
//   nested functions   `SFunc` / `SLocalFunc` are SEPARATE bodies. They are
//                      counted in `skipped` here and each one gets its own CFG,
//                      which is what an interprocedural analysis needs anyway.
//
// EVERY NODE CARRIES A SOURCE POSITION. That is not decoration: a finding has to
// name a line and a column, and an analysis that computes "this store is dead"
// and cannot say WHERE has computed something no reader can act on. It is also
// what makes `@core` a real dependency of this package rather than a test-only
// one -- see the note in `flow/moon.pkg` and 0527's account of the constraint
// that `--deny-warn` puts on test-only imports.

///|
/// What a CFG node does. The payload is the source expression, not a copy of it,
/// so a transfer function can read the AST without a side table.
pub(all) enum NodeKind {
  Entry
  Exit
  /// `let x = e` -- a DECLARATION. Its "never read" is `FUnusedLocal`'s claim.
  Assign(String, @ast.Expr)
  /// `x = e` -- a STORE to a name that already exists.
  ///
  /// WHY THIS IS A SEPARATE KIND FROM `Assign`. A dead store is a claim about ONE
  /// write; a `let` whose value is never read is a different claim about a
  /// binding, and this tree already has a family for it (`FUnusedLocal`). One
  /// kind for both would force the liveness pass either to report one line under
  /// two families or to choose between them in prose, and prose is where that
  /// distinction would be lost.
  Store(String, @ast.Expr)
  /// `x.f = e` / `xs[i] = e` -- a store THROUGH a place.
  ///
  /// THE TARGET IS CARRIED, NOT JUST ITS BASE NAME, and the reason is a
  /// measured false positive. The node used to carry the base name only, so
  /// `out[bi] = ...` had a use set of `{out}` -- the INDEX `bi` was nowhere in
  /// it, and a store to `bi` on the line above looked like a value nobody
  /// reads. MEASURED, moonbit_labeler 0.2.13 `component_blackbox_test.mbt:721`:
  ///
  ///     out[bi] = (a << 2) | (b >> 4)
  ///     bi = bi + 1
  ///     out[bi] = ((b & 0xF) << 4) | (c >> 2)
  ///
  /// reported `the value stored in 'bi' is read on no path` on a line whose
  /// value is read on the very next one. The base of a place-store is a use
  /// (see below), and the INDEX is a use too -- it is an expression that has
  /// to be evaluated to know which element is written.
  ///
  /// THE BASE OF A PLACE-STORE IS A USE, NOT A DEFINITION, and getting that
  /// backwards is not a small error. `assigned_base()` reports the same name for
  /// `x = e` and for `x.f = e`, so treating both as a redefinition of `x` says
  /// the reference `x` was overwritten when only a field of what it points at
  /// was. Measured: 56 of the 162 dead-store findings on this repository's own
  /// source were `self`, every one of them a `self.field = ...` -- a systematic
  /// false positive caused by exactly this conflation, found by aggregating the
  /// findings by name before believing them.
  PlaceStore(@ast.Expr, @ast.Expr)
  /// `let (a, b) = e` -- binds several names at once.
  AssignMulti(Array[String], @ast.Expr)
  /// An expression evaluated for its effect (a call, a `match`, a block).
  Eval(@ast.Expr)
  /// A branch condition. `succ[0]` is taken when it holds, `succ[1]` when not.
  Test(@ast.Expr)
  /// Control leaves this graph: `return`, `raise`, `break`, `continue`.
  Stop
}

///|
/// A control-flow graph over one function body.
///
/// NODE INDICES ARE ALLOCATION ORDER, NOT SOURCE ORDER. The builder walks a
/// statement list back to front because a statement's successor must be known
/// before the statement can be linked, so `kinds[0]` is usually the exit node.
/// Nothing depends on the order -- `succ`/`pred` carry the structure and `spans`
/// carries the position -- but a reader of a dump should not expect index order
/// to read like the source.
pub(all) struct Cfg {
  kinds : Array[NodeKind]
  /// The source position of each node, index-parallel with `kinds`.
  ///
  /// A synthesis node (the entry, the exit, a `for-update` loop head) has no
  /// statement of its own, so it carries the position of whatever construct
  /// created it -- an empty position only for the synthetic entry/exit pair,
  /// whose line 0 is a sentinel rather than a claim about the source.
  spans : Array[@core.Span]
  succ : Array[Array[Int32]]
  pred : Array[Array[Int32]]
  entry : Int32
  exit : Int32
  /// Statements this builder did not convert into nodes. A non-zero value is a
  /// statement about the graph's precision, and it is carried rather than
  /// dropped so that a caller can decline to make a claim.
  skipped : Int32
}

///|
/// The position a synthetic node carries when it has no statement of its own.
pub fn no_span() -> @core.Span {
  { start: @core.pos(0, 0), end: @core.pos(0, 0), }
}

///|
/// Strict order over a `(line, column)` pair: true when the FIRST comes AFTER
/// the second.
///
/// IT IS PUBLIC, AND IT IS HERE, because two analyses now ask "which of these two
/// positions is later in the source" -- the pointer analysis's site ranking and
/// the basic-block layer's block order -- and two implementations of that
/// question is one more than can stay in agreement. The project's rule is that
/// an operation used twice lives in ONE place: `live.mbt` says it for the set
/// operations, and this is the same rule for the position order.
pub fn source_after(l1 : Int32, c1 : Int32, l2 : Int32, c2 : Int32) -> Bool {
  if l1 != l2 {
    return l1 > l2
  }
  c1 > c2
}

///|
/// The nodes of a graph in SOURCE order -- by (line, column), with the node
/// index only as a tie-break.
///
/// WHY IT LIVES HERE AND NOT IN THE ANALYSIS THAT FIRST NEEDED IT. The pointer
/// analysis (0547) needed it, and wrote it there; the basic-block layer (0551)
/// needs it too, and a second copy would be two definitions of "the source
/// order of a graph" -- and two definitions of an order is how two parts of an
/// analyzer start to disagree about which statement came first. The order is a
/// property of the GRAPH, so it belongs beside the graph.
///
/// THE TIE-BREAK IS THE NODE INDEX, and it is not arbitrary: a `return e`
/// produces TWO nodes with the SAME span (`cfg.mbt:313-326` -- the `Eval` that
/// carries the read and the `Stop` that ends the flow), and the `Eval` is
/// allocated first, so the index puts the read BEFORE the terminator. A
/// tie-break on anything else would be able to put the terminator first, and a
/// block whose nodes are in the wrong order is not a block.
pub fn Cfg::source_order(self : Cfg) -> Array[Int32] {
  let order : Array[Int32] = []
  let mut v = 0
  while v < self.kinds.length() {
    order.push(v)
    v = v + 1
  }
  // Insertion sort into SOURCE order. The graph is small and the sort is not
  // the point; the point is that the ORDER is defined once.
  //
  // THE COMPARISON IS `prev` AFTER `cur`, and the first draft of this function
  // asked the opposite question -- "is `cur` after `prev`?" -- which sorts
  // DESCENDING. The pointer analysis's own suite caught it: four rows that
  // read a statement's state in source order came back with the states of the
  // wrong statements. The sort had the right SHAPE (a permutation of the
  // nodes, so every node was present exactly once) and the wrong DIRECTION,
  // which is the kind of defect a "the order contains every node" assertion
  // cannot see.
  let mut a = 1
  while a < order.length() {
    let cur = order[a]
    let mut b = a - 1
    let mut placed = false
    while b >= 0 && !placed {
      let prev = order[b]
      if self.node_after(prev, cur) {
        order[b + 1] = prev
        b = b - 1
      } else {
        placed = true
      }
    }
    order[b + 1] = cur
    a = a + 1
  }
  order
}

///|
/// True when node `a` comes AFTER node `b` in the source.
fn Cfg::node_after(self : Cfg, a : Int32, b : Int32) -> Bool {
  let la = self.spans[a].start.line
  let lb = self.spans[b].start.line
  let ca = self.spans[a].start.col
  let cb = self.spans[b].start.col
  if source_after(la, ca, lb, cb) {
    return true
  }
  if la != lb || ca != cb {
    return false
  }
  a > b
}

///|
/// The mutable half of the builder: the arrays that are filled in as the
/// recursion unwinds. `pred` is derived at the end from `succ`, so it cannot
/// disagree with it.
priv struct Builder {
  kinds : Array[NodeKind]
  spans : Array[@core.Span]
  succ : Array[Array[Int32]]
  mut skipped : Int32
}

///|
fn Builder::add(self : Builder, kind : NodeKind, span : @core.Span) -> Int32 {
  self.kinds.push(kind)
  self.spans.push(span)
  self.succ.push([])
  self.kinds.length() - 1
}

///|
fn Builder::link(self : Builder, from : Int32, to : Array[Int32]) -> Unit {
  self.succ[from] = to
}

///|
/// Build the CFG of one function body.
pub fn cfg_of(body : Array[@ast.Stmt]) -> Cfg {
  let b = { kinds: [], spans: [], succ: [], skipped: 0, }
  let exit = b.add(Exit, no_span())
  let body_entry = build_seq(b, body, exit)
  let entry = b.add(Entry, no_span())
  b.link(entry, [body_entry])
  let pred = pred_of(b.succ)
  {
    kinds: b.kinds,
    spans: b.spans,
    succ: b.succ,
    pred,
    entry,
    exit,
    skipped: b.skipped,
  }
}

///|
/// `pred` is derived from `succ`, never maintained by hand: two structures that
/// can disagree will disagree.
///
/// PUBLIC because a graph that a caller assembles (an interprocedural one, in a
/// later increment) needs the same derivation, and two implementations of "the
/// inverse of succ" is one more than can stay in agreement.
pub fn pred_of(succ : Array[Array[Int32]]) -> Array[Array[Int32]] {
  // ONE FRESH ARRAY PER NODE, and this is not a style choice: `Array::make(n, [])`
  // fills every slot with the SAME array reference, so every push lands in one
  // shared list and `pred` stops being the inverse of `succ`. Measured here --
  // the first version of this function did exactly that and the merge-node test
  // read `[0, 0, 1, 2]` where it expected `[1, 2]`.
  let pred : Array[Array[Int32]] = []
  let mut i = 0
  while i < succ.length() {
    pred.push([])
    i = i + 1
  }
  let mut v = 0
  while v < succ.length() {
    let mut k = 0
    while k < succ[v].length() {
      let s = succ[v][k]
      pred[s].push(v)
      k = k + 1
    }
    v = v + 1
  }
  pred
}

///|
/// The entry node of a statement sequence whose continuation is `next`.
///
/// Iterating BACK TO FRONT is what makes a single pass possible: `next` is
/// known when each statement is linked, so no separate patching phase is needed
/// and a statement cannot end up with a stale successor.
fn build_seq(b : Builder, stmts : Array[@ast.Stmt], next : Int32) -> Int32 {
  let mut cur = next
  let mut i = stmts.length() - 1
  while i >= 0 {
    cur = build_one(b, stmts[i], cur)
    i = i - 1
  }
  cur
}

///|
/// One statement, whose continuation is `next`. Returns the node control enters
/// at.
fn build_one(b : Builder, s : @ast.Stmt, next : Int32) -> Int32 {
  match s.kind {
    @ast.SExpr(e) => {
      let n = b.add(Eval(e), s.span)
      b.link(n, [next])
      n
    }
    @ast.STail(e) => {
      let n = b.add(Eval(e), s.span)
      b.link(n, [next])
      n
    }
    @ast.SLet(x, _, e) => {
      let n = b.add(Assign(x, e), s.span)
      b.link(n, [next])
      n
    }
    @ast.SLetDestruct(names, e) => {
      let n = b.add(AssignMulti(names, e), s.span)
      b.link(n, [next])
      n
    }
    @ast.SAssign(lhs, rhs) =>
      // A plain `x = e` is a redefinition of the NAME; anything else is a write
      // THROUGH a place, and `assigned_base()` gives the same name for both.
      match lhs.kind {
        @ast.EName(x) => {
          let n = b.add(Store(x, rhs), s.span)
          b.link(n, [next])
          n
        }
        _ =>
          match lhs.assigned_base() {
            Some(_) => {
              let n = b.add(PlaceStore(lhs, rhs), s.span)
              b.link(n, [next])
              n
            }
            None => {
              let n = b.add(Eval(rhs), s.span)
              b.link(n, [next])
              n
            }
          }
      }
    @ast.SIf(cond, then_body, elifs, else_body) => {
      // The branch node's position is the CONDITION's: a reader looking at
      // "line N" wants the test they wrote, not the `if` keyword's line.
      let n = b.add(Test(cond), cond.span)
      let then_entry = build_seq(b, then_body, next)
      let else_entry = build_else(b, elifs, 0, else_body, next)
      b.link(n, [then_entry, else_entry])
      n
    }
    @ast.SWhile(cond, body) => {
      let n = b.add(Test(cond), cond.span)
      let body_entry = build_seq(b, body, n)
      b.link(n, [body_entry, next])
      n
    }
    @ast.SFor(_, _, cond, body) => {
      let n = b.add(Test(cond), cond.span)
      let body_entry = build_seq(b, body, n)
      b.link(n, [body_entry, next])
      n
    }
    @ast.SForUpdate(body) => {
      let n = b.add(Entry, s.span)
      let body_entry = build_seq(b, body, n)
      b.link(n, [body_entry, next])
      n
    }
    @ast.SBlock(inner) => build_seq(b, inner, next)
    @ast.SNoBreak(inner, body) => {
      let after_inner = build_one(b, inner, next)
      build_seq(b, body, after_inner)
    }
    @ast.SReturn(e) | @ast.SRaise(e) =>
      // THE EXPRESSION IS A READ, AND DISCARDING IT WAS A MEASURED FALSE
      // POSITIVE CLASS. This arm used to be `SReturn(_) | SRaise(_)` producing
      // one `Stop` node, so `return x` contributed NO use of `x` -- and a store
      // whose only reader was the return therefore looked dead. Measured in
      // 0530: `return (byte_pos, bp, result)` in moonbit_image's `gif.mbt` read
      // as three dead stores on consecutive lines, and `if flag { x = 7;
      // return x }` read as one on a two-line fixture.
      //
      // `STail` above already models the same thing the same way: the
      // expression becomes an `Eval` node so its names are USES, and then
      // control stops. A `return` with no expression adds only the `Stop`.
      match e {
        Some(x) => {
          let ev = b.add(Eval(x), s.span)
          let stop = b.add(Stop, s.span)
          b.link(ev, [stop])
          b.link(stop, [])
          // THE `Eval` NODE IS WHAT THIS ARM RETURNS, not the `Stop`. The value
          // here is the ENTRY of this statement: `build_seq` links the PREVIOUS
          // statement to whatever this returns, so returning the `Stop` left the
          // `Eval` with no predecessor and the read it carries unreachable --
          // the fix was written that way first and the finding survived,
          // unchanged, which is how the mistake was found.
          ev
        }
        None => {
          let stop = b.add(Stop, s.span)
          b.link(stop, [])
          stop
        }
      }
    // COUNTED AS SKIPPED, and that is not a naming shortcut. `break` and
    // `continue` become `Stop`, which is a node -- but the edge each should add
    // (to the loop's exit, and to its head) is NOT added, so the loop exit is
    // unreachable FROM the break. A liveness pass reading that graph sees a path
    // that ends early, and a store before a `break` whose value is read after
    // the loop then looks dead. Since `skipped` is exactly "the statements this
    // graph did not faithfully convert", the honest thing is to count them here
    // and let a claim be declined instead of guessed.
    @ast.SBreak(_) | @ast.SContinue(_) => {
      b.skipped = b.skipped + 1
      let n = b.add(Stop, s.span)
      b.link(n, [])
      n
    }
    @ast.SFunc(_, _, _, _, _) | @ast.SLocalFunc(_, _, _, _, _) => {
      // A separate body with its own CFG; counted so the omission is visible.
      b.skipped = b.skipped + 1
      next
    }
  }
}

///|
/// The `else` half of a chain: `else if` clauses become nested `Test` nodes in
/// source order, and a chain with no `else` falls through to `next`.
fn build_else(
  b : Builder,
  elifs : Array[@ast.ElseIf],
  i : Int32,
  else_body : Array[@ast.Stmt]?,
  next : Int32,
) -> Int32 {
  if i >= elifs.length() {
    match else_body {
      Some(ss) => build_seq(b, ss, next)
      None => next
    }
  } else {
    let clause = elifs[i]
    let n = b.add(Test(clause.cond), clause.cond.span)
    let body_entry = build_seq(b, clause.body, next)
    let rest = build_else(b, elifs, i + 1, else_body, next)
    b.link(n, [body_entry, rest])
    n
  }
}

///|
/// A readable dump, for tests and for a human checking the graph by eye.
///
/// The dump is not decoration: the alternative to reading a graph is trusting a
/// comment about a graph, and this tree has been burned by exactly that before.
pub fn Cfg::dump(self : Cfg) -> String {
  let mut out = "cfg: \{self.kinds.length()} nodes, entry=\{self.entry}, exit=\{self.exit}"
  if self.skipped > 0 {
    out = out + ", skipped=\{self.skipped}"
  }
  out = out + "\n"
  let mut v = 0
  while v < self.kinds.length() {
    out = out + "  \{v}  \{self.kind_label(v)}"
    if self.succ[v].length() > 0 {
      out = out + "  -> "
      let mut k = 0
      while k < self.succ[v].length() {
        if k > 0 {
          out = out + ", "
        }
        out = out + "\{self.succ[v][k]}"
        k = k + 1
      }
    }
    out = out + "\n"
    v = v + 1
  }
  out
}

///|
/// A node's kind with its payload reduced to its source form, so a dump line is
/// readable without the AST at hand.
pub fn Cfg::kind_label(self : Cfg, v : Int32) -> String {
  match self.kinds[v] {
    Entry => "entry"
    Exit => "exit"
    Assign(x, _) => "assign \{x}"
    Store(x, _) => "store \{x}"
    PlaceStore(t, _) =>
      // The base name, for a readable label. `assigned_base()` is the same
      // function the builder used to decide there IS a base.
      match t.assigned_base() {
        Some(x) => "place-store \{x}"
        None => "place-store"
      }
    AssignMulti(names, _) => "assign-multi \{names.length()} names"
    Eval(_) => "eval"
    Test(_) => "test"
    Stop => "stop"
  }
}
