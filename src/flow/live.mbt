// Live variables analysis (book §5.4), over the CFG from `cfg.mbt`.
//
// WHAT IT ANSWERS, IN THE ONE DIRECTION THAT IS TRUSTWORTHY. A variable is LIVE
// at a program point if some execution reads its value later without writing it
// first. The book's framing is the one that matters for a bug-finding tool: this
// analysis is conservative in the direction where "NOT live" can be trusted and
// "live" is the safe but useless answer. So a store whose target is not live
// after it is a store whose value nobody reads -- and that is a finding only as
// far as the graph models the reads.
//
// IT IS A BACKWARD, MAY ANALYSIS (§5.8), AND IT REUSES THE FORWARD SOLVER.
// That is not a trick, it is the definition: a backward analysis defines its
// JOIN over SUCCESSORS, so passing `cfg.succ` where `solve_round_robin` expects
// the join-neighbours computes the backward fixed point with no second solver.
// `solve_round_robin` never inspects which array it was given; it joins over
// whatever neighbours it is handed. Making that explicit here is cheaper than a
// second near-identical loop, and a reader who wonders whether the reuse is sound
// can read this paragraph and the solver's own note about before/after indexing.
//
// THE TRANSFER IS THE CLASSICAL ONE:
//
//     in(v) = ( out(v) \ defs(v) ) ∪ uses(v)
//     out(v) = ⊔_{s ∈ succ(v)} in(s)
//
// with `bot` = the empty set at the exit, which is what makes the answer "dead"
// at the end of a function.

///|
/// The set lattice: a set of names, ordered by inclusion, joined by union.
///
/// WHY `bot` IS A THUNK. Every solver seeds one element per node, and a shared
/// mutable seed would be one set for the whole graph -- the bug `pred_of` shipped
/// for one compile in this same package. `bot` therefore builds a fresh map each
/// time it is called.
pub fn name_set_lattice() -> Lattice[Map[String, Bool]] {
  {
    bot: fn() { name_set_empty() },
    join: fn(a, b) { name_set_union(a, b) },
    eq: fn(a, b) { name_set_eq(a, b) },
  }
}

///|
pub fn name_set_empty() -> Map[String, Bool] {
  let m : Map[String, Bool] = Map([])
  m
}

///|
/// The left-biased union; the right side is copied in so the arguments are not
/// mutated. Callers in the fixed point pass the joined value on, and a join that
/// wrote into its input would make the solver's `eq` comparison meaningless.
pub fn name_set_union(
  a : Map[String, Bool],
  b : Map[String, Bool],
) -> Map[String, Bool] {
  let out = name_set_empty()
  for k, _ in a {
    out.set(k, true)
  }
  for k, _ in b {
    out.set(k, true)
  }
  out
}

///|
pub fn name_set_eq(a : Map[String, Bool], b : Map[String, Bool]) -> Bool {
  let mut same = true
  for k, _ in a {
    if b.contains(k) == false {
      same = false
    }
  }
  for k, _ in b {
    if a.contains(k) == false {
      same = false
    }
  }
  same
}

///|
/// The names an expression READS.
///
/// OVER-APPROXIMATES ON PURPOSE, and only where the alternative is worse. A
/// comprehension's own bindings and a match arm's pattern names are collected
/// even though they are locally bound, because dropping a read makes a variable
/// look dead and turning a live variable into a "dead store" is a false
/// positive; keeping a read makes it look live, which is the safe direction the
/// family's `assumption` states.
pub fn names_of_expr(out : Map[String, Bool], e : @ast.Expr) -> Unit {
  match e.kind {
    @ast.EInt(_) | @ast.EFloat(_) | @ast.EBool(_) | @ast.ERegex(_) => ()
    @ast.EBigInt(_) => ()
    // A STRING INTERPOLATION READS ITS NAMES, and this arm used to answer ().
    //
    // The parser already hands the names over: `EStr(_, refs)` carries the
    // identifiers written inside `\{...}` (see `@ast.EStr`), precisely so a lens
    // can see a read that the raw payload hides. The structural walk consulted
    // it; this function dropped it, so `let mut s = "a"; if c { s = "b" };
    // "\{s}"` had NO read of `s` and `MSA-015` reported the initializer as a
    // dead store.
    //
    // MEASURED, this tree's own `src/sa/main.mbt:622` (`ctx_line`'s `per_sig`):
    // one high-confidence `DeadStore` on code that reads the variable two lines
    // later, in the interpolation that ends the function. The minimal fixture is
    // the three lines above; the same shape with a tail expression instead of an
    // interpolation reports nothing, which is what localized it.
    //
    // It is also the arm the paragraph above forbids: dropping a read makes a
    // variable look dead, and this is the false positive it predicted.
    @ast.EStr(_, refs) =>
      for n in refs {
        out.set(n, true)
      }
    @ast.EName(n) => out.set(n, true)
    @ast.EList(xs) | @ast.ETuple(xs) => names_of_exprs(out, xs)
    @ast.EUnary(_, a) | @ast.ECast(a) | @ast.EAsBind(a, _) =>
      names_of_expr(out, a)
    @ast.ETupleField(a, _) => names_of_expr(out, a)
    @ast.EIs(a, _) => names_of_expr(out, a)
    @ast.EBin(_, a, b) | @ast.EIndex(a, b) | @ast.ERange(a, b) => {
      names_of_expr(out, a)
      names_of_expr(out, b)
    }
    @ast.EField(a, _) => names_of_expr(out, a)
    @ast.ECall(n, args, _) => {
      out.set(n, true)
      names_of_exprs(out, args)
    }
    @ast.EMethodCall(a, _, args, _) | @ast.EDotDot(a, _, args, _) => {
      names_of_expr(out, a)
      names_of_exprs(out, args)
    }
    // NOTE: `guard` is a RESERVED WORD in MoonBit, so the comprehension's
    // filter binds as `grd`. That is the third reserved word to bite this tree
    // (`local`, `unreachable`, now `guard`), which is why the name is spelled
    // out here rather than quietly abbreviated.
    @ast.EComp(_, iters, grd, body) => {
      names_of_exprs(out, iters)
      match grd {
        Some(g) => names_of_expr(out, g)
        None => ()
      }
      names_of_expr(out, body)
    }
    @ast.EStruct(_, fields) =>
      // `for _, fe in fields` does NOT destructure a tuple element in this
      // toolchain: it binds the whole pair. The let-pattern below does.
      for pair in fields {
        let (_, fe) = pair
        names_of_expr(out, fe)
      }
    @ast.EBlock(stmts) => names_of_stmts(out, stmts)
    @ast.ECatch(a, arms) | @ast.ENoRaise(a, arms) => {
      names_of_expr(out, a)
      for arm in arms {
        names_of_stmts(out, arm.body)
      }
    }
    @ast.EMatch(a, arms) => {
      names_of_expr(out, a)
      for arm in arms {
        match arm.cond {
          Some(c) => names_of_expr(out, c)
          None => ()
        }
        for r in arm.reads {
          out.set(r, true)
        }
        names_of_stmts(out, arm.body)
      }
    }
  }
}

///|
fn names_of_exprs(out : Map[String, Bool], xs : Array[@ast.Expr]) -> Unit {
  for x in xs {
    names_of_expr(out, x)
  }
}

///|
fn names_of_stmts(out : Map[String, Bool], ss : Array[@ast.Stmt]) -> Unit {
  for s in ss {
    names_of_stmt(out, s)
  }
}

///|
/// The names a STATEMENT reads, including the statements inside its blocks.
/// Used for the expressions a node's payload does not expose directly (a block
/// body, a match arm).
fn names_of_stmt(out : Map[String, Bool], s : @ast.Stmt) -> Unit {
  match s.kind {
    @ast.SExpr(e) | @ast.STail(e) => names_of_expr(out, e)
    @ast.SLet(_, _, e) => names_of_expr(out, e)
    @ast.SLetDestruct(_, e) => names_of_expr(out, e)
    @ast.SAssign(l, r) => {
      names_of_expr(out, l)
      names_of_expr(out, r)
    }
    @ast.SIf(c, then_b, elifs, else_b) => {
      names_of_expr(out, c)
      names_of_stmts(out, then_b)
      for ei in elifs {
        names_of_expr(out, ei.cond)
        names_of_stmts(out, ei.body)
      }
      match else_b {
        Some(b) => names_of_stmts(out, b)
        None => ()
      }
    }
    @ast.SWhile(c, b) | @ast.SFor(_, _, c, b) => {
      names_of_expr(out, c)
      names_of_stmts(out, b)
    }
    @ast.SForUpdate(b) => names_of_stmts(out, b)
    @ast.SBlock(b)
    | @ast.SLocalFunc(_, _, _, b, _)
    | @ast.SFunc(_, _, _, b, _) => names_of_stmts(out, b)
    @ast.SNoBreak(s1, b) => {
      names_of_stmt(out, s1)
      names_of_stmts(out, b)
    }
    @ast.SReturn(e) | @ast.SRaise(e) =>
      match e {
        Some(x) => names_of_expr(out, x)
        None => ()
      }
    @ast.SBreak(es) | @ast.SContinue(es) => names_of_exprs(out, es)
  }
}

///|
/// The names a node WRITES, which the transfer removes from the live set.
///
/// A store to a PLACE (`x.f = e`, `xs[i] = e`) names its base, because that is
/// the name whose value the write can change. It does NOT kill the base's
/// liveness: the base still has to be live for the store to be well-defined, and
/// killing it would make the NEXT statement's write look dead. So only a plain
/// assignment to a name kills that name.
pub fn node_defs(kind : NodeKind) -> Map[String, Bool] {
  let out = name_set_empty()
  match kind {
    Assign(x, _) | Store(x, _) => out.set(x, true)
    AssignMulti(names, _) =>
      for n in names {
        out.set(n, true)
      }
    _ => ()
  }
  out
}

///|
/// The names a node READS.
pub fn node_uses(kind : NodeKind) -> Map[String, Bool] {
  let out = name_set_empty()
  match kind {
    Assign(_, e) | Store(_, e) | AssignMulti(_, e) | Eval(e) | Test(e) =>
      names_of_expr(out, e)
    // A write THROUGH a place reads its base: you need `x` to store into `x.f`,
    // and the base is not redefined by it. It also reads whatever the right-hand
    // side mentions.
    //
    // AND IT READS THE INDEX. `out[bi] = e` evaluates `bi` to know which
    // element it writes, so `bi` is read by the statement -- and a use set that
    // omitted it made the store to `bi` on the line above look dead. MEASURED,
    // moonbit_labeler 0.2.13 `component_blackbox_test.mbt:721`.
    //
    // The TARGET EXPRESSION carries the base AND the index, so reading the
    // target's names covers both and cannot forget the second one.
    PlaceStore(target, e) => {
      names_of_expr(out, target)
      names_of_expr(out, e)
    }
    Entry | Exit | Stop => ()
  }
  out
}

///|
/// `live_in[v]`: the set of names live BEFORE node `v`.
///
/// THE ENTRY NODE IS INCLUDED IN THE ANSWER, and it is not a curiosity: a
/// parameter that the entry node's first statement never reads is the case a
/// `UnusedParam`-style check wants, and it falls out of the same fixed point.
///
/// The transfer closes over the graph's node kinds, so the returned array is
/// exactly the size of `cfg.kinds` and index-compatible with it.
pub fn live_in(cfg : Cfg) -> Array[Map[String, Bool]] {
  let lat = name_set_lattice()
  let defs : Array[Map[String, Bool]] = []
  let uses : Array[Map[String, Bool]] = []
  let mut v = 0
  while v < cfg.kinds.length() {
    defs.push(node_defs(cfg.kinds[v]))
    uses.push(node_uses(cfg.kinds[v]))
    v = v + 1
  }
  // BACKWARD: the join-neighbours of a node are its SUCCESSORS (§5.8).
  let transfer : (Int32, Map[String, Bool]) -> Map[String, Bool] = fn(
    node,
    out,
  ) {
    let next = name_set_empty()
    for k, _ in out {
      if defs[node].contains(k) == false {
        next.set(k, true)
      }
    }
    for k, _ in uses[node] {
      next.set(k, true)
    }
    next
  }
  solve_round_robin(lat, cfg.kinds.length(), cfg.succ, transfer)
}

///|
/// `live_out[v]`: the names live AFTER node `v`, which is the set a DEAD-STORE
/// question is actually asked about.
///
/// THE DISTINCTION IS NOT COSMETIC. `live_in[v]` already has `v`'s own
/// definitions removed, so `x` absent from `live_in` at an `x = e` node proves
/// nothing -- it is absent by construction. What decides whether the store's
/// value is ever read is `live_out[v]`, the union of its successors' in-sets. A
/// caller that asked the other question would report every assignment whose
/// right-hand side mentions its own target, and it would be wrong in the
/// direction that looks most convincing.
pub fn live_out(
  cfg : Cfg,
  live : Array[Map[String, Bool]],
) -> Array[Map[String, Bool]] {
  let lat = name_set_lattice()
  let out : Array[Map[String, Bool]] = []
  let mut v = 0
  while v < cfg.kinds.length() {
    out.push(join_of_nodes(lat, live, cfg.succ[v]))
    v = v + 1
  }
  out
}
