// flow: AVAILABLE EXPRESSIONS -- the deck's THIRD application, and the first
// MUST analysis in this tree.
//
// WHY THIS FILE EXISTS. The framework in `lattice.mbt` / `worklist.mbt` was
// written for may analyses and says so in its own vocabulary: a `Lattice`
// supplies `bot`, `join` and `eq`, both solvers seed every node with `bot`, and
// every step moves a node UP by joining. Live variables (0527) is may-and-
// backward and the interval domain (0529) is a may-style widening over the same
// ascending chain, so nothing in the tree had ever needed the other direction.
//
// Available expressions is the other direction, and it is the deck's own third
// application (Yue Li, Nanjing University, `Data Flow Analysis -- Applications`,
// part III; the two the tree already has are part I, reaching definitions, in
// the sense that `MSA-002` covers the same ground, and part II, live variables,
// which is 0527):
//
//     IN[B]  = ∩ over P a predecessor of B of OUT[P]
//     OUT[B] = gen_B ∪ (IN[B] - kill_B)
//
// A MUST analysis: the meet is INTERSECTION and the safe direction is
// UNDER-approximation (the deck's p.12: "may analysis: safe=over, must
// analysis: safe=under"). `x + y` is available at a point only if it was
// computed on EVERY path to that point with neither operand written since.
//
// THE DUALITY, AND WHY THE EXISTING SOLVER IS THE RIGHT ONE. A must analysis
// over (⊤, ∩) IS a may analysis over the same carrier ordered the OTHER WAY:
// reverse the order and ⊤ becomes the bottom, ∩ becomes the join, and the
// ascending chain of the solver becomes the descending chain of the must
// solution. So this file does not need a second solver, and it does not get one
// -- a second solver is a second place for the fixed point to be wrong. It
// passes `solve_round_robin` a lattice whose `bot` is ⊤ (the whole universe)
// and whose `join` is ∩, and the solver reaches the GREATEST fixed point of the
// original order, which is exactly the safe must solution.
//
// THAT IS A REAL ARGUMENT AND IT IS ALSO A TRAP, which is why two tests pin
// both of its halves:
//
//   * seeding with ⊥ (the empty set) instead of ⊤ makes NOTHING ever available,
//     because the intersection of empty sets is empty. The analysis silently
//     finds nothing, which reads exactly like "this code has no redundancy";
//   * omitting the entry special case below makes EVERYTHING available at the
//     entry's successors, because the entry node has no predecessors and its
//     input is therefore the lattice's `bot` -- now ⊤. Every expression in the
//     program is then "already available" at the first statement that computes
//     it, which is a claim about a computation that has not happened yet.
//
// The two mistakes are opposite and both are silent. `avail_test.mbt` measures
// both on one program.
//
// WHAT IS NOT COVERED, AND IT IS THE DECK'S OWN LIST (p.38, "Issues Not
// Covered"): METHOD CALLS AND ALIASES. The tracked universe is therefore
// restricted to arithmetic over ATOMS -- a name or an integer/boolean literal --
// which is what makes aliasing unable to invalidate a tracked fact: a
// `xs[i] = e` writes an element, and no tracked expression mentions an element,
// a field or a call result. `EFloat` is excluded as well, and for a different
// reason: rendering `1.0` and `1.00` to the same key would claim two different
// computations are the same one.

///|
/// One tracked expression: its canonical key, and the names it reads.
///
/// The KEY is the identity, so two occurrences of the same computation produce
/// the same string by construction. The NAMES are carried rather than re-derived
/// because the kill rule is "every tracked expression that mentions a name this
/// node defines", and a rule that re-parsed the key to find its operands would
/// be a second parser for a format this file invented.
pub(all) struct AvailExpr {
  key : String
  names : Map[String, Bool]
}

///|
/// A name or a literal, rendered canonically -- or `None` if the expression is
/// not one of those.
fn atom_text(e : @ast.Expr) -> String? {
  match e.kind {
    @ast.EName(n) => Some(n)
    @ast.EInt(i) => Some(i.to_string())
    @ast.EBool(b) => if b { Some("true") } else { Some("false") }
    _ => None
  }
}

///|
fn uop_symbol(op : @ast.UOp) -> String {
  match op {
    @ast.UNeg => "-"
    @ast.UNot => "!"
  }
}

///|
/// The canonical key of a TRACKED expression, or `None`.
///
/// ONE LEVEL, ON PURPOSE. An operand must be an atom, so `(a + b) + c` is not
/// tracked as a whole and `a + b` inside it still is. That keeps every key's
/// operand set exactly two names or literals, which is what makes the kill rule
/// a set-membership test instead of a walk.
pub fn avail_key(e : @ast.Expr) -> String? {
  match e.kind {
    @ast.EBin(op, a, b) =>
      match (atom_text(a), atom_text(b)) {
        (Some(x), Some(y)) => Some("\{x} \{op.symbol()} \{y}")
        _ => None
      }
    @ast.EUnary(op, a) =>
      match atom_text(a) {
        Some(x) => Some("\{uop_symbol(op)}\{x}")
        None => None
      }
    _ => None
  }
}

///|
/// The names a tracked expression reads. Only `EName` operands are names; a
/// literal contributes none, which is what lets `1 + 2` be available for the
/// whole program once computed.
fn avail_names(e : @ast.Expr) -> Map[String, Bool] {
  let out = name_set_empty()
  match e.kind {
    @ast.EBin(_, a, b) => {
      push_name(out, a)
      push_name(out, b)
    }
    @ast.EUnary(_, a) => push_name(out, a)
    _ => ()
  }
  out
}

///|
fn push_name(out : Map[String, Bool], e : @ast.Expr) -> Unit {
  match e.kind {
    @ast.EName(n) => out.set(n, true)
    _ => ()
  }
}

///|
/// Every tracked expression among the sub-expressions of `e`, appended to `out`.
///
/// THE DESCENT STOPS AT A TRACKED EXPRESSION, because a tracked expression's
/// operands are atoms by construction and there is nothing below it to find.
///
/// AN INCOMPLETE DESCENT IS SAFE HERE, and the reason is the must direction
/// itself: a missed `gen` means the analysis claims FEWER available expressions
/// than there are, which under-approximates -- and under-approximation is what
/// the deck says is safe for a must analysis. The opposite mistake is the one
/// that would be unsound: a missed KILL. Kills do not come from this function
/// at all; they come from `node_defs`, which is a complete answer to "which
/// names does this node define".
fn collect_avail(e : @ast.Expr, out : Array[AvailExpr]) -> Unit {
  match avail_key(e) {
    Some(k) => out.push({ key: k, names: avail_names(e), })
    None =>
      match e.kind {
        @ast.EInt(_) | @ast.EFloat(_) | @ast.EBool(_) => ()
        @ast.ERegex(_) | @ast.EBigInt(_) => ()
        @ast.EName(_) => ()
        @ast.EStr(_, _) => ()
        @ast.EList(xs) | @ast.ETuple(xs) => collect_avail_exprs(xs, out)
        @ast.EUnary(_, a) | @ast.ECast(a) | @ast.EAsBind(a, _) =>
          collect_avail(a, out)
        @ast.ETupleField(a, _) | @ast.EField(a, _) | @ast.EIs(a, _) =>
          collect_avail(a, out)
        @ast.EBin(_, a, b) | @ast.EIndex(a, b) | @ast.ERange(a, b) => {
          collect_avail(a, out)
          collect_avail(b, out)
        }
        @ast.ECall(_, args, _) => collect_avail_exprs(args, out)
        @ast.EMethodCall(a, _, args, _) | @ast.EDotDot(a, _, args, _) => {
          collect_avail(a, out)
          collect_avail_exprs(args, out)
        }
        @ast.EComp(_, iters, grd, body) => {
          collect_avail_exprs(iters, out)
          match grd {
            Some(g) => collect_avail(g, out)
            None => ()
          }
          collect_avail(body, out)
        }
        @ast.EStruct(_, fields) =>
          for pair in fields {
            let (_, fe) = pair
            collect_avail(fe, out)
          }
        @ast.EBlock(stmts) => collect_avail_stmts(stmts, out)
        @ast.ECatch(a, arms) | @ast.ENoRaise(a, arms) => {
          collect_avail(a, out)
          for arm in arms {
            // The arm's GUARD, for the reason the match arm's guard is
            // collected: it is an expression, and an expression can carry an
            // available expression inside it.
            match arm.cond {
              Some(c) => collect_avail(c, out)
              None => ()
            }
            collect_avail_stmts(arm.body, out)
          }
        }
        @ast.EMatch(a, arms) => {
          collect_avail(a, out)
          for arm in arms {
            match arm.cond {
              Some(c) => collect_avail(c, out)
              None => ()
            }
            collect_avail_stmts(arm.body, out)
          }
        }
      }
  }
}

///|
fn collect_avail_exprs(xs : Array[@ast.Expr], out : Array[AvailExpr]) -> Unit {
  for x in xs {
    collect_avail(x, out)
  }
}

///|
fn collect_avail_stmts(ss : Array[@ast.Stmt], out : Array[AvailExpr]) -> Unit {
  for s in ss {
    match s.kind {
      @ast.SExpr(e) | @ast.STail(e) | @ast.SLet(_, _, e) =>
        collect_avail(e, out)
      @ast.SLetDestruct(_, e) => collect_avail(e, out)
      @ast.SAssign(l, r) => {
        collect_avail(l, out)
        collect_avail(r, out)
      }
      @ast.SIf(c, tb, elifs, eb) => {
        collect_avail(c, out)
        collect_avail_stmts(tb, out)
        for ei in elifs {
          collect_avail(ei.cond, out)
          collect_avail_stmts(ei.body, out)
        }
        match eb {
          Some(b) => collect_avail_stmts(b, out)
          None => ()
        }
      }
      @ast.SWhile(c, b) | @ast.SFor(_, _, c, b) => {
        collect_avail(c, out)
        collect_avail_stmts(b, out)
      }
      @ast.SForUpdate(b) => collect_avail_stmts(b, out)
      @ast.SReturn(e) | @ast.SRaise(e) =>
        match e {
          Some(x) => collect_avail(x, out)
          None => ()
        }
      @ast.SBreak(es) | @ast.SContinue(es) => collect_avail_exprs(es, out)
      _ => ()
    }
  }
}

///|
/// The expressions a NODE evaluates, in the order the node mentions them.
///
/// A node's `gen` is exactly this list, filtered to the universe by
/// `collect_avail`'s own descent.
pub fn avail_evals(cfg : Cfg, v : Int32) -> Array[AvailExpr] {
  let out : Array[AvailExpr] = []
  match cfg.kinds[v] {
    Assign(_, e) | Store(_, e) | AssignMulti(_, e) | Eval(e) | Test(e) =>
      collect_avail(e, out)
    // THE TARGET OF A PLACE-STORE IS EVALUATED TOO, and 0542 made the CFG carry
    // it for exactly this reason: `out[bi] = e` reads `bi`.
    PlaceStore(t, e) => {
      collect_avail(t, out)
      collect_avail(e, out)
    }
    Entry | Exit | Stop => ()
  }
  out
}

///|
/// The universe of tracked expressions in this graph, as a set of keys.
///
/// IT IS ALSO THE IDENTITY ELEMENT OF THE MEET, and that is not a coincidence:
/// the intersection of no sets is "everything", so the same object is both the
/// top of the order and the accumulator's starting value. Two callers need it --
/// `avail_after`'s lattice and `avail_in`'s -- and they must agree, which is why
/// it is computed once here rather than twice in place.
///
/// THE SECOND TRAP LIVES HERE. `join_of_nodes` seeds its accumulator with the
/// lattice's `bot` and then folds every element in. For the dual lattice that
/// means the accumulator starts at ⊤, which is right; but `avail_in` builds its
/// OWN lattice for the join, and seeding THAT one with the empty set makes every
/// intersection empty -- the meet of anything with ∅ is ∅. The analysis then
/// reports nothing at all, which is the same silent failure as ⊥-seeding the
/// solver, reached through a different door. MEASURED: this is how the first
/// version of this file behaved, and the three positive rows of `avail_test.mbt`
/// were what caught it.
pub fn avail_universe(cfg : Cfg) -> Map[String, Bool] {
  let out = name_set_empty()
  let mut v = 0
  while v < cfg.kinds.length() {
    for a in avail_evals(cfg, v) {
      out.set(a.key, true)
    }
    v = v + 1
  }
  out
}

///|
/// `avail_after[v]`: the set of tracked expressions available AFTER node `v`,
/// as keys.
///
/// THE ENTRY'S OUTPUT IS EMPTY, AND IT IS NOT A DEFAULT. Nothing has been
/// computed before the program starts, so ⊤ at the entry would make the first
/// statement of the program redundant against a computation that never
/// happened. The textbook writes this as `OUT[entry] = ∅` and seeds every OTHER
/// node with ⊤; the round-robin solver seeds everything with the lattice's
/// `bot`, which for a must analysis is ⊤, so the entry is the one node that has
/// to be special-cased -- and `avail_test.mbt` pins both the special case and
/// its absence.

///|
/// The DUAL LATTICE, as a value: `bot` is ⊤ (the whole universe) and `join` is
/// ∩, so the solver's ascending chain is the must solution's descending chain.
///
/// ONE CONSTRUCTION SITE, AND THAT IS THE POINT. Before 0545 this lattice was
/// built TWICE -- once here and once inside `avail_in` for the join -- and the
/// two copies disagreed: `avail_in` seeded its fold with the empty set, whose
/// intersection with anything is empty, so a node with ONE predecessor read ∅.
/// That was the third silent failure mode of this analysis, found by three
/// positive tests going quiet. A single factory makes the disagreement
/// unwritable rather than merely fixed.
pub fn avail_lattice(
  universe : Map[String, Bool],
) -> Lattice[Map[String, Bool]] {
  {
    // ⊤, not ∅: see the note on `avail_universe`. This is both the solver's
    // seed and the identity element of ∩ for `join_of_nodes`.
    bot: fn() {
      let s = name_set_empty()
      for key, _ in universe {
        s.set(key, true)
      }
      s
    },
    join: fn(a, b) { name_set_inter(a, b) },
    eq: fn(a, b) { name_set_eq(a, b) },
  }
}

///|
/// The available-expressions transfer function, as a VALUE.
///
/// WHY IT IS EXTRACTED: same reason as `live_transfer`. The two solvers promise
/// termination and the LEAST fixed point, and both promises rest on this
/// function being MONOTONE (Yue Li, `Data Flow Analysis -- Foundations`, p.115
/// and p.118). A closure that exists only inside `avail_after`'s body can be
/// observed through its fixed point and through nothing else, so the property
/// could not be tested -- and for the MUST direction it is the property that
/// says the answer never grows back, which is what makes the answer safe.
///
/// The work it needs is per-graph and is built here rather than passed in, so
/// that a caller (and a test) gets the function by naming the graph.
pub fn avail_transfer(
  cfg : Cfg,
) -> (Int32, Map[String, Bool]) -> Map[String, Bool] {
  let n = cfg.kinds.length()
  // THE REVERSE INDEX the kill rule needs: name -> the keys that mention it.
  let keys_of_name : Map[String, Map[String, Bool]] = Map([])
  let mut scan = 0
  while scan < n {
    for a in avail_evals(cfg, scan) {
      for nm, _ in a.names {
        let slot = match keys_of_name.get(nm) {
          Some(s) => s
          None => name_set_empty()
        }
        slot.set(a.key, true)
        keys_of_name.set(nm, slot)
      }
    }
    scan = scan + 1
  }
  // Per node: the keys it generates, and the keys it kills. A kill is "every
  // tracked expression that mentions a name this node defines", and the names
  // come from `node_defs` -- the complete answer, which is what the must
  // direction requires.
  let gens : Array[Map[String, Bool]] = []
  let kills : Array[Map[String, Bool]] = []
  let mut i = 0
  while i < n {
    let g = name_set_empty()
    for a in avail_evals(cfg, i) {
      g.set(a.key, true)
    }
    gens.push(g)
    let k = name_set_empty()
    for nm, _ in node_defs(cfg.kinds[i]) {
      match keys_of_name.get(nm) {
        Some(ks) =>
          for key, _ in ks {
            k.set(key, true)
          }
        None => ()
      }
    }
    kills.push(k)
    i = i + 1
  }
  let entry = cfg.entry
  fn(node, input) {
    if node == entry {
      // Nothing is available before the program starts.
      name_set_empty()
    } else {
      match cfg.kinds[node] {
        // An exit or a `Stop` (a break/continue edge the builder could not
        // model) passes the state through: it computes nothing and defines
        // nothing.
        Exit | Stop => input
        _ => {
          let next = name_set_subtract(input, kills[node])
          for key, _ in gens[node] {
            next.set(key, true)
          }
          next
        }
      }
    }
  }
}

///|
pub fn avail_after(cfg : Cfg) -> Array[Map[String, Bool]] {
  solve_round_robin(
    avail_lattice(avail_universe(cfg)),
    cfg.kinds.length(),
    cfg.pred,
    avail_transfer(cfg),
  )
}

///|
/// `avail_in[v]`: the set of tracked expressions available BEFORE node `v`.
///
/// This is the set a "is this recomputation redundant" question is asked about,
/// and the entry reads ∅ by the same argument `avail_after` gives.
pub fn avail_in(
  cfg : Cfg,
  after : Array[Map[String, Bool]],
) -> Array[Map[String, Bool]] {
  // THE SAME LATTICE `avail_after` SEEDS THE SOLVER WITH. Its `bot` is ⊤, which
  // is what `join_of_nodes` needs as the identity element of ∩ -- and building a
  // second one here, with an empty `bot`, is the mistake 0544 shipped for one
  // compile (see `avail_lattice`).
  let lat = avail_lattice(avail_universe(cfg))
  let out : Array[Map[String, Bool]] = []
  let mut v = 0
  while v < cfg.kinds.length() {
    if v == cfg.entry {
      out.push(name_set_empty())
    } else {
      out.push(join_of_nodes(lat, after, cfg.pred[v]))
    }
    v = v + 1
  }
  out
}

///|
/// One redundant recomputation: the node, and the key it recomputes.
pub(all) struct Redundant {
  node : Int32
  key : String
}

///|
/// The nodes whose evaluation recomputes an expression that is ALREADY AVAILABLE
/// there.
///
/// THE SECOND CONDITION IS NOT DECORATION. `key ∉ kill(v)` is what keeps
/// `x = x + 1` out of this list: the expression mentions `x` and the node
/// defines `x`, so the value the node computes is not the value that was
/// available before it, and calling it redundant would be wrong in the loudest
/// possible way -- the store is the only thing keeping `x` up to date.
///
/// A node is reported ONCE, naming the first expression it recomputes, because a
/// reader fixes a line rather than a set.
pub fn avail_redundant(cfg : Cfg) -> Array[Redundant] {
  let out : Array[Redundant] = []
  let after = avail_after(cfg)
  let before = avail_in(cfg, after)
  let mut v = 0
  while v < cfg.kinds.length() {
    let killed = node_defs(cfg.kinds[v])
    let mut reported = false
    for a in avail_evals(cfg, v) {
      // `killed` is the set of names the node defines; a tracked expression is
      // killed by this node exactly when it mentions one of them.
      let mut invalidated = false
      for nm, _ in a.names {
        if killed.contains(nm) {
          invalidated = true
        }
      }
      if invalidated == false && before[v].contains(a.key) && reported == false {
        out.push({ node: v, key: a.key, })
        reported = true
      }
    }
    v = v + 1
  }
  out
}
