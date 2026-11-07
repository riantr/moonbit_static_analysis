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
  /// `x = e` -- from `SLet` and from `SAssign` whose target has a base name.
  Assign(String, @ast.Expr)
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
      // `x.f = e` and `xs[i] = e` are assignments to a PLACE, not to a local;
      // `assigned_base` names the local they go through, so the graph can say
      // which name an analysis has to invalidate. A target with no base name is
      // evaluated for effect instead of being pretended into an assignment.
      match lhs.assigned_base() {
        Some(x) => {
          let n = b.add(Assign(x, rhs), s.span)
          b.link(n, [next])
          n
        }
        None => {
          let n = b.add(Eval(rhs), s.span)
          b.link(n, [next])
          n
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
    @ast.SReturn(_) | @ast.SRaise(_) | @ast.SBreak(_) | @ast.SContinue(_) => {
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
    AssignMulti(names, _) => "assign-multi \{names.length()} names"
    Eval(_) => "eval"
    Test(_) => "test"
    Stop => "stop"
  }
}
