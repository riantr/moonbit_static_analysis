// 0546: the INTERPROCEDURAL CONTROL-FLOW GRAPH.
//
// WHY THIS FILE EXISTS. `cfg.mbt` builds a graph for ONE function body, and it
// says so in its first paragraph. Every edge in it is a normal edge inside that
// body, `Entry` is that body's entry, `Exit` is that body's exit, and a call is
// not an edge at all -- it is an `ECall` sitting inside the payload of an
// `Assign` or an `Eval` node, with no node of its own and no connection to the
// body it names. The consequence is measurable and it is the whole reason the
// deck has a section on this: with only that graph, the answer for anything
// flowing through a call is "unknown", which is safe and is what p.5-9 of the
// deck calls the SOURCE OF IMPRECISION.
//
// The deck (Tian Tan, `Interprocedural Analysis`, Nanjing University, 2021)
// gives the structure in one line at p.77:
//
//     ICFG = CFGs + call & return edges
//
// and the two new edge kinds at p.75-76:
//
//     call edges    from call sites to the ENTRY nodes of their callees
//     return edges  from EXIT nodes of the callees to the statements following
//                   their call sites (the RETURN SITES)
//
// plus a third kind that p.81 names and that is easy to leave out:
//
//     call-to-return edges   from a call site to its own return site
//
// THE THIRD KIND IS NOT AN OPTIMISATION DETAIL, AND THE DECK SPENDS EIGHT SLIDES
// ON WHY (p.97-104). Without it, the caller's local dataflow -- `a=6` in the
// deck's example -- has to travel INTO the callee and back out to reach the
// statement after the call, which is exactly what p.98 calls "very inefficient".
// With it, the caller's state reaches the return site directly, and the return
// edge contributes ONLY the returned value. The two contributions are joined at
// the return site, and they are complementary rather than conflicting -- which
// works in this package because an absent name in the state map is the lattice's
// bottom, so "the return edge knows `b`" and "the call-to-return edge knows
// `a` and `c`" join into a state that knows all three.
//
// WHAT THIS FILE DOES NOT MODEL, NAMED RATHER THAN LEFT TO BE DISCOVERED:
//
//   * METHOD CALLS. `x.foo()` is `EMethodCall`, whose target depends on the
//     receiver's type. The deck spends its whole second section on the call
//     graphs that resolve those (CHA and its successors) and this tree has none
//     of them, so a method call is NOT a call site here. That is the same
//     fail-toward-silence trade `interp.mbt` already makes for `EMethodCall`.
//   * A CALL INSIDE A LARGER EXPRESSION. `c = 1 + f(x)` has a call, and the
//     node holding it assigns a value that is not the call's result. A call site
//     here is a node whose payload IS a call -- `b = f(a)` or `f(a)` as a
//     statement -- so the node/edge split of the deck's transfer functions has
//     an unambiguous subject.
//   * `raise`. Both `return e` and `raise e` become `Eval(e) -> Stop` in
//     `cfg.mbt`, so a graph alone cannot tell them apart. A function that raises
//     with a payload anywhere in its body is therefore DECLINED
//     (`Icfg.declined`): its calls contribute "value unknown" instead of a
//     returned value. The deck has no exception edges either, so this is a
//     declared boundary rather than a gap that was overlooked.
//   * A FUNCTION WHOSE `Exit` IS REACHABLE. Its value is its tail expression,
//     which `cfg.mbt` evaluates in an `Eval` node but does not connect to the
//     exit, so the returned value is not recoverable from the graph. Such a
//     function is declined in the same way (`Icfg.fallthrough`), which is the
//     conservative direction: the call's left-hand side becomes "not a
//     constant" instead of a constant this file cannot justify.
//
// EVERY DECLINE IS A COUNT, NOT A SILENCE. `unresolved`, `declined` and
// `fallthrough` are carried on the graph so a caller can say how much of the
// program it is entitled to a claim about -- the same contract as `Cfg.skipped`,
// and for the same reason.

///|
/// One function as the ICFG needs it: a name, its parameter names in order, and
/// the body `cfg.mbt` converts.
///
/// THE PARAMETER NAMES ARE PART OF THE INPUT and not derivable from the graph,
/// because the call edge's transfer has to bind them positionally to the call
/// site's actual arguments (deck p.87: "call edge transfer: pass argument
/// values"). The graph holds `Entry` and nothing about what it takes.
pub(all) struct IFn {
  name : String
  params : Array[String]
  body : Array[@ast.Stmt]
}

///|
/// What an edge is FOR, which is the thing the intraprocedural framework has no
/// way to say.
///
/// EACH VARIANT CARRIES THE DATA ITS TRANSFER NEEDS. That is deliberate: the
/// edge transfer is a function of the edge, and a solver that had to look the
/// edge's meaning up in a side table would put the meaning somewhere the solver
/// cannot see. The deck's six rules (p.105) then read as six matches, and three of
/// them -- the kill, the argument values, the returned value -- could not have been
/// written anywhere else.
pub(all) enum EdgeKind {
  /// An ordinary control-flow edge inside one body. Transfer: identity.
  Normal
  /// Call site -> its own return site. Transfer: KILL the value of the call
  /// site's left-hand side (deck p.103) and keep everything else.
  ///
  /// THE KILL IS THE WHOLE POINT. `b = ten()` after `b = addOne(a)` leaves the
  /// old value of `b` sitting in the state; if this edge carries it to the
  /// return site, the return edge's value `10` is joined with the stale `7` and
  /// the answer is "not a constant" -- p.102's `a=6,b=NAC,c=4`, marked
  /// "Imprecise!". With the kill it is `a=6,b=10,c=4` and then `c=60`, p.104,
  /// marked "Precise!".
  CallToReturn(String?)
  /// Call site -> the callee's entry. Transfer: pass the ARGUMENT VALUES, and
  /// nothing else -- the callee's parameters become the arguments' values and
  /// every other name is absent, which is the restriction that stops the
  /// caller's locals leaking into the callee (deck p.98's stated inefficiency).
  Call(Array[@ast.Expr], Array[String])
  /// A callee's exit -> the call site's return site. Transfer: the RETURNED
  /// value, assigned to the call site's left-hand side. `Some(e)` is a recovered
  /// return expression; `None` means "this function's value is not modelled",
  /// and the transfer must answer "not a constant" rather than nothing.
  Ret(@ast.Expr?, String?)
}

///|
/// A call site the graph resolved, kept for tests and for a caller that wants to
/// say which calls it connected.
pub(all) struct CallSite {
  caller : Int32
  /// Flat node index of the call site.
  node : Int32
  callee : Int32
  lhs : String?
}

///|
/// The interprocedural graph: the union of a set of per-function CFGs plus the
/// call, return and call-to-return edges between them.
///
/// NODE INDICES ARE FLAT AND STABLE. Function `f` owns the contiguous range
/// starting at its base offset, `fn_of` maps a flat index back to `f`, and
/// `entry_of` / `exit_of` give the flat index of each function's own entry and
/// exit. Everything else -- `kinds`, `spans`, `succ`, `labels` -- is index-
/// parallel with `fn_of`, so a transfer function can be written once over the
/// flat space and never has to know which body it is standing in.
pub(all) struct Icfg {
  kinds : Array[NodeKind]
  spans : Array[@core.Span]
  succ : Array[Array[Int32]]
  /// Parallel to `succ`, same shape.
  labels : Array[Array[EdgeKind]]
  pred : Array[Array[Int32]]
  fn_of : Array[Int32]
  entry_of : Array[Int32]
  exit_of : Array[Int32]
  /// Per function: is its `Exit` reachable from its `Entry`? If so its returned
  /// value is a tail expression this graph cannot recover, and its calls are
  /// declined.
  fallthrough : Array[Bool]
  /// Per function: does its body raise with a payload anywhere? If so `return`
  /// and `raise` cannot be told apart and its calls are declined.
  declined : Array[Bool]
  call_sites : Array[CallSite]
  /// Call sites whose callee is not in the table.
  unresolved : Int32
  /// Sum of the per-function `Cfg.skipped` counts.
  skipped : Int32
}

///|
/// The shape of a call site, as far as `NodeKind` can express it.
pub struct CallShape {
  callee : String
  args : Array[@ast.Expr]
  lhs : String?
}

///|
/// Is this node a call site, and if so what does it call?
///
/// ONLY A PAYLOAD THAT IS ITSELF A CALL COUNTS. See the header's SECOND
/// exclusion: a call buried in a larger expression is not a site this graph can give a
/// node/edge split to.
pub fn call_shape(kind : NodeKind) -> CallShape? {
  match kind {
    Assign(x, e) =>
      match e.kind {
        @ast.ECall(name, args, _) => Some({ callee: name, args, lhs: Some(x), })
        _ => None
      }
    Store(x, e) =>
      match e.kind {
        @ast.ECall(name, args, _) => Some({ callee: name, args, lhs: Some(x), })
        _ => None
      }
    Eval(e) =>
      match e.kind {
        @ast.ECall(name, args, _) => Some({ callee: name, args, lhs: None, })
        _ => None
      }
    _ => None
  }
}

///|
/// Does this statement sequence raise with a payload anywhere inside it?
///
/// The walk descends STATEMENTS only. A lambda's body is a separate function with
/// its own graph (`cfg.mbt` counts it as skipped here and builds it there), so a
/// `raise` inside a lambda is not this function's raise.
fn raises_with_payload(stmts : Array[@ast.Stmt]) -> Bool {
  let mut i = 0
  while i < stmts.length() {
    if raises_in_one(stmts[i]) {
      return true
    }
    i = i + 1
  }
  false
}

///|
fn raises_in_one(s : @ast.Stmt) -> Bool {
  match s.kind {
    @ast.SRaise(Some(_)) => true
    @ast.SIf(_, then_body, elifs, else_body) => {
      if raises_with_payload(then_body) {
        return true
      }
      let mut i = 0
      while i < elifs.length() {
        if raises_with_payload(elifs[i].body) {
          return true
        }
        i = i + 1
      }
      match else_body {
        Some(ss) => raises_with_payload(ss)
        None => false
      }
    }
    @ast.SWhile(_, body) | @ast.SFor(_, _, _, body) | @ast.SForUpdate(body) =>
      raises_with_payload(body)
    @ast.SBlock(inner) => raises_with_payload(inner)
    @ast.SNoBreak(inner, body) =>
      raises_in_one(inner) || raises_with_payload(body)
    _ => false
  }
}

///|
/// Is `target` reachable from `from` over `succ`?
///
/// Used for one question only -- whether a function can fall out of its own
/// `Exit` -- and written as a plain worklist so that the answer does not depend
/// on the shape of the graph.
fn reaches(succ : Array[Array[Int32]], from : Int32, target : Int32) -> Bool {
  let seen : Array[Bool] = Array::make(succ.length(), false)
  let queue : Array[Int32] = [from]
  seen[from] = true
  let mut head = 0
  while head < queue.length() {
    let v = queue[head]
    head = head + 1
    if v == target {
      return true
    }
    let mut k = 0
    while k < succ[v].length() {
      let s = succ[v][k]
      if seen[s] == false {
        seen[s] = true
        queue.push(s)
      }
      k = k + 1
    }
  }
  false
}

///|
/// Build the interprocedural graph for a set of functions.
///
/// ONE PASS OVER EACH BODY, THEN ONE PASS OVER THE CALL SITES. The per-function
/// graphs are built first and laid out end to end, so every node's flat index is
/// known before any interprocedural edge is added; then each resolved call site
/// contributes exactly the three edge kinds the deck names -- one `Call` to the
/// callee's entry, one `Ret` per way the callee can leave, and the call-to-return
/// edge that REPLACES the call node's original normal edge (a call site has no
/// ordinary successor: p.81's "such edges are called call-to-return edges").
pub fn icfg_of(fns : Array[IFn]) -> Icfg {
  let cfgs : Array[Cfg] = []
  let entry_of : Array[Int32] = []
  let exit_of : Array[Int32] = []
  let base : Array[Int32] = []
  let kinds : Array[NodeKind] = []
  let spans : Array[@core.Span] = []
  let succ : Array[Array[Int32]] = []
  let labels : Array[Array[EdgeKind]] = []
  let fn_of : Array[Int32] = []
  let fallthrough : Array[Bool] = []
  let declined : Array[Bool] = []
  let mut skipped = 0
  // 1. Lay the bodies out end to end.
  let mut f = 0
  while f < fns.length() {
    let g = cfg_of(fns[f].body)
    base.push(kinds.length())
    entry_of.push(base[f] + g.entry)
    exit_of.push(base[f] + g.exit)
    fallthrough.push(reaches(g.succ, g.entry, g.exit))
    declined.push(raises_with_payload(fns[f].body))
    skipped = skipped + g.skipped
    let mut v = 0
    while v < g.kinds.length() {
      kinds.push(g.kinds[v])
      spans.push(g.spans[v])
      let ss : Array[Int32] = []
      let ls : Array[EdgeKind] = []
      let mut k = 0
      while k < g.succ[v].length() {
        ss.push(base[f] + g.succ[v][k])
        ls.push(Normal)
        k = k + 1
      }
      succ.push(ss)
      labels.push(ls)
      fn_of.push(f)
      v = v + 1
    }
    cfgs.push(g)
    f = f + 1
  }
  // 2. Named lookup: a call site names a function, and a name that is declared
  //    twice is ambiguous rather than "the first one" -- the same rule
  //    `interp.mbt` already applies, where a duplicate name sets an `ambiguous`
  //    flag on the entry rather than letting the first declaration win.
  let by_name : Map[String, Int32] = Map([])
  let ambiguous : Map[String, Bool] = Map([])
  let mut i = 0
  while i < fns.length() {
    if by_name.contains(fns[i].name) {
      ambiguous.set(fns[i].name, true)
    } else {
      by_name.set(fns[i].name, i)
    }
    i = i + 1
  }
  // 3. Interprocedural edges, one call site at a time.
  let call_sites : Array[CallSite] = []
  let mut unresolved = 0
  let mut caller = 0
  while caller < fns.length() {
    let g = cfgs[caller]
    let mut v = 0
    while v < g.kinds.length() {
      let shape = call_shape(g.kinds[v])
      match shape {
        Some(cs) => {
          let target = by_name.get(cs.callee)
          // A call site must have EXACTLY ONE ordinary successor: that node is
          // the return site (deck p.76: "the statements following their call
          // site"). A site whose control flow is not that simple is not
          // connected rather than connected to a guess.
          let flat = base[caller] + v
          let simple = g.succ[v].length() == 1
          match target {
            Some(callee) =>
              if !ambiguous.contains(cs.callee) && simple && callee != caller {
                let ret_site = base[caller] + g.succ[v][0]
                // the call node's own ordinary edge becomes the call-to-return one
                labels[flat][0] = CallToReturn(cs.lhs)
                succ[flat].push(entry_of[callee])
                labels[flat].push(Call(cs.args, fns[callee].params))
                // Every way the callee can leave contributes the returned value.
                let cg = cfgs[callee]
                let declined_callee = declined[callee]
                let mut w = 0
                while w < cg.kinds.length() {
                  if is_value_exit(cg, w) {
                    let payload = if declined_callee {
                      None
                    } else {
                      value_exit_expr(cg, w)
                    }
                    succ[base[callee] + w].push(ret_site)
                    labels[base[callee] + w].push(Ret(payload, cs.lhs))
                  }
                  w = w + 1
                }
                if fallthrough[callee] {
                  succ[exit_of[callee]].push(ret_site)
                  labels[exit_of[callee]].push(Ret(None, cs.lhs))
                }
                call_sites.push({ caller, node: flat, callee, lhs: cs.lhs, })
              } else {
                unresolved = unresolved + 1
              }
            None => unresolved = unresolved + 1
          }
        }
        None => ()
      }
      v = v + 1
    }
    caller = caller + 1
  }
  {
    kinds,
    spans,
    succ,
    labels,
    pred: pred_of(succ),
    fn_of,
    entry_of,
    exit_of,
    fallthrough,
    declined,
    call_sites,
    unresolved,
    skipped,
  }
}

///|
/// Is node `w` a way out of its function that carries a value?
///
/// The shape `cfg.mbt` gives a `return e` is `Eval(e) -> Stop`, with the `Stop`
/// having no successors -- so the `Eval` node is where the value is, and it is
/// the node a return edge leaves from. `return` with no expression adds only the
/// `Stop`, which is not a value exit and is covered by the fall-through rule.
fn is_value_exit(g : Cfg, w : Int32) -> Bool {
  match g.kinds[w] {
    Eval(_) =>
      if g.succ[w].length() == 1 {
        match g.kinds[g.succ[w][0]] {
          Stop => true
          _ => false
        }
      } else {
        false
      }
    _ => false
  }
}

///|
/// The expression a value exit returns.
fn value_exit_expr(g : Cfg, w : Int32) -> @ast.Expr? {
  match g.kinds[w] {
    Eval(e) => Some(e)
    _ => None
  }
}
