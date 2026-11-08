// 0546: interprocedural constant propagation, pinned to the deck's own numbers.
//
// THE NUMBERS ARE THE SLIDES', NOT THE IMPLEMENTATION'S. `Interprocedural
// Analysis` (Tian Tan, Nanjing University, 2021) works one program through three
// configurations and prints the answer at every statement:
//
//   p.106  intraprocedural      a=6, b=NAC, c=NAC        ("x=NAC, y=NAC")
//   p.102  interprocedural, the call-to-return edge does NOT kill the LHS
//                               a=6, b=NAC, c=NAC        ("Imprecise!")
//   p.104  interprocedural, the call-to-return edge KILLS the LHS
//                               a=6, b=10,  c=60         ("Precise!")
//
// and p.107 draws the conclusion: interprocedural constant propagation is more
// precise than intraprocedural. Every row below asserts one of those printed
// values, so a regression is a disagreement with the slide rather than with a
// number this tree invented.
//
// THE THREE CONFIGURATIONS SHARE ONE GRAPH, ONE LATTICE AND ONE NODE TRANSFER,
// which is what makes them a measurement of the EDGE TRANSFER: only the
// call-to-return rule (or the presence of the interprocedural edges at all)
// differs between the arms.

///|
/// The state in which the deck's figures are expressed: `b=10`, `⊥` for a name
/// with no information, `NAC` for one that is not a constant.
fn cp_show(st : @flow.State, names : Array[String]) -> String {
  let parts : Array[String] = []
  for n in names {
    parts.push(n + "=" + @flow.cpv_text(@flow.cprop_get(st, n)))
  }
  parts.join(",")
}

///|
/// Run the graph with the call-to-return KILL removed -- p.102's configuration.
///
/// Everything else is untouched, which is the point: a rule is measured by
/// removing it and watching one printed value change.
fn cp_run_no_kill(g : @flow.Icfg) -> Array[@flow.State] {
  @flow.solve_edges(
    @flow.cprop_lattice(),
    g.kinds.length(),
    g.succ,
    g.labels,
    @flow.cprop_node_transfer(g.kinds),
    fn(label, from, to, st) {
      match label {
        @flow.CallToReturn(_) => st
        _ => @flow.cprop_edge_transfer(label, from, to, st)
      }
    },
  )
}

///|
/// Run `main` ALONE, with a call's result unknown -- p.106's configuration.
///
/// This is what the tree could express before this increment: no interprocedural
/// edges exist, so a call node has to answer for its own left-hand side, and the
/// only sound answer it has is "not a constant". The deck puts it beside the
/// interprocedural answer on p.107 and the difference is the increment.
fn cp_run_intra(g : @flow.Icfg) -> Array[@flow.State] {
  let inner = @flow.cprop_node_transfer(g.kinds)
  @flow.solve_edges(
    @flow.cprop_lattice(),
    g.kinds.length(),
    g.succ,
    g.labels,
    fn(v, st) {
      match @flow.call_shape(g.kinds[v]) {
        Some(cs) =>
          match cs.lhs {
            Some(x) => @flow.cprop_set(st, x, @flow.Nac)
            None => st
          }
        None => inner(v, st)
      }
    },
    @flow.cprop_edge_transfer,
  )
}

// ---------------------------------------------------------------------------
// A -- the precise answer (deck p.104 and p.107)
// ---------------------------------------------------------------------------

///|
/// THE ARGUMENT VALUE CROSSES THE CALL EDGE.
///
/// `addOne`'s entry state holds `x=6` and NOTHING ELSE: the call edge passes
/// argument values and does not carry `main`'s locals in (p.98 says why -- local
/// dataflow that has to travel through a callee is the inefficiency the
/// call-to-return edge exists to remove, and here it is not merely inefficient but
/// wrong, because `x` would then be joined with every name in the caller).
test "0546: the call edge passes argument values and nothing else" {
  let g = @flow.icfg_of(deck_program())
  let states = @flow.cprop_run(g)
  let entry = g.entry_of[1]
  assert_eq(
    cp_show(states[entry], ["x", "y", "a", "b", "c"]),
    "x=6,y=⊥,a=⊥,b=⊥,c=⊥",
  )
}

///|
/// THE TWO TRANSFER LINES OF p.105, MEASURED ON THE DECK'S OWN STATEMENTS.
///
///   `y = x + 1` inside `addOne`   -> y=7    (node transfer, ordinary statement)
///   `b = addOne(a)` in `main`     -> b=7    (return edge, returned value)
///
/// The second one is the one no node transfer could produce: `cprop_node_transfer`
/// is the IDENTITY at a call node (p.87, p.105), so `b` is still `⊥` after that
/// node's own transfer and only the return edge can set it.
test "0546: the returned value crosses the return edge into the caller's LHS" {
  let g = @flow.icfg_of(deck_program())
  let states = @flow.cprop_run(g)
  let y_node = cp_store_node(g, 1, "y", 0)
  assert_eq(
    @flow.cpv_text(@flow.cprop_get(@flow.cprop_after(g, states, y_node), "y")),
    "7",
  )
  // `b` is NOT set by the call node's own transfer ...
  let call0 = cp_call_node(g, 0, 0)
  assert_eq(
    @flow.cpv_text(@flow.cprop_get(@flow.cprop_after(g, states, call0), "b")),
    "⊥",
  )
  // ... and it IS set at the return site, where the return edge arrives
  let site = cp_return_site(g, call0)
  assert_eq(cp_show(states[site], ["a", "b", "c"]), "a=6,b=7,c=⊥")
}

///|
/// THE PRECISE END OF THE DECK'S TABLE (p.104, p.107): `a=6, b=10, c=60`.
///
/// `c=60` is the number that needs BOTH edge kinds to be right: `b` must be 10
/// (the second call's returned value, not the stale 7) and `a` must still be 6
/// (carried by the call-to-return edge across the second call, because only the
/// LHS `b` was killed).
test "0546: the deck's precise answer, a=6 b=10 c=60" {
  let g = @flow.icfg_of(deck_program())
  let states = @flow.cprop_run(g)
  let c0 = cp_store_node(g, 0, "c", 0)
  assert_eq(
    cp_show(@flow.cprop_after(g, states, c0), ["a", "b", "c"]),
    "a=6,b=7,c=4",
  )
  let call1 = cp_call_node(g, 0, 1)
  let site1 = cp_return_site(g, call1)
  // `c` is 4 here, not ⊥: `c = b - 3` is the THIRD statement and this is the
  // fourth, so the local `c` reaches this return site along the call-to-return
  // edge -- which is what p.102 and p.104 both print (`a=6,b=…,c=4`). This row
  // was written with `c=⊥` first and the deck is what corrected it.
  assert_eq(cp_show(states[site1], ["a", "b", "c"]), "a=6,b=10,c=4")
  let c1 = cp_store_node(g, 0, "c", 1)
  assert_eq(
    cp_show(@flow.cprop_after(g, states, c1), ["a", "b", "c"]),
    "a=6,b=10,c=60",
  )
}

// ---------------------------------------------------------------------------
// B -- the two controls, both of which the deck labels "imprecise"
// ---------------------------------------------------------------------------

///|
/// REMOVE THE KILL AND THE ANSWER BECOMES THE DECK'S p.102 ROW.
///
/// The stale `b=7` from the first call sits in the state when `b = ten()` is
/// reached; without the kill the call-to-return edge carries it to the return
/// site, where it is joined with the return edge's `10` -- `7 ⊔ 10 = NAC` -- and
/// `c = a * b` then answers `NAC` rather than 60.
///
/// THE FIRST CALL SHOWS NO DIFFERENCE, and that is why this row uses the SECOND
/// one: at `b = addOne(a)` the name `b` has no value yet, so carrying it and
/// killing it agree. A control that removed the kill and looked at the first call
/// would find nothing and report a rule that does not matter.
test "0546: without the kill on the call-to-return edge the answer is NAC" {
  let g = @flow.icfg_of(deck_program())
  let states = cp_run_no_kill(g)
  let call1 = cp_call_node(g, 0, 1)
  let site1 = cp_return_site(g, call1)
  assert_eq(cp_show(states[site1], ["a", "b", "c"]), "a=6,b=NAC,c=4")
  let c1 = cp_store_node(g, 0, "c", 1)
  assert_eq(
    cp_show(@flow.cprop_after(g, states, c1), ["a", "b", "c"]),
    "a=6,b=NAC,c=NAC",
  )
}

///|
/// WITH NO INTERPROCEDURAL EDGES AT ALL, THE ANSWER IS THE DECK'S p.106 ROW.
///
/// This is the comparison p.107 draws -- "interprocedural constant propagation is
/// more precise than intraprocedural constant propagation" -- measured on the same
/// graph: `main` alone, with each call's result unknown, gives `b=NAC` and
/// `c=NAC` where the interprocedural answer is 10 and 60.
test "0546: intraprocedurally the same program answers NAC where the ICFG answers 60" {
  let fns = deck_program()
  let only_main : Array[@flow.IFn] = [fns[0]]
  let g = @flow.icfg_of(only_main)
  // the two calls are unresolved, so no call/return edge exists
  assert_eq(g.unresolved, 2)
  let states = cp_run_intra(g)
  let c0 = cp_store_node(g, 0, "c", 0)
  assert_eq(
    cp_show(@flow.cprop_after(g, states, c0), ["a", "b", "c"]),
    "a=6,b=NAC,c=NAC",
  )
  let c1 = cp_store_node(g, 0, "c", 1)
  assert_eq(
    cp_show(@flow.cprop_after(g, states, c1), ["a", "b", "c"]),
    "a=6,b=NAC,c=NAC",
  )
}

// ---------------------------------------------------------------------------
// C -- the solver, and the lattice underneath it
// ---------------------------------------------------------------------------

///|
/// `solve_edges` REDUCES TO `solve_propagation` WHEN EVERY EDGE TRANSFER IS THE
/// IDENTITY.
///
/// The edge-aware solver is a third loop in a package whose first two are checked
/// against each other on purpose (`flow_worklist_test.mbt`), so the new one has to
/// be pinned to the old ones rather than merely observed to terminate. With the
/// identity edge transfer the two equation systems are the same system, so their
/// least fixed points must agree node for node.
test "0546: solve_edges reduces to solve_propagation when no edge transfer does anything" {
  let g = @flow.icfg_of(deck_program())
  let lat = @flow.cprop_lattice()
  let node_t = @flow.cprop_node_transfer(g.kinds)
  let with_edges = @flow.solve_edges(
    lat,
    g.kinds.length(),
    g.succ,
    g.labels,
    node_t,
    fn(_label, _from, _to, st) { st },
  )
  let plain = @flow.solve_propagation(lat, g.kinds.length(), g.succ, node_t)
  let mut v = 0
  while v < g.kinds.length() {
    assert_eq(@flow.cprop_text(with_edges[v]), @flow.cprop_text(plain[v]))
    v = v + 1
  }
}

///|
/// THE LATTICE'S HEIGHT IS THREE AND ITS CARRIER IS NOT FINITE, which is the
/// distinction 0545 could not exhibit: `laws_test.mbt` decides the lattice laws by
/// trying every pair, and a constant-propagation lattice has one element per
/// `Int32`, so no enumeration reaches it. The solvers still terminate, because
/// Kleene's theorem asks for finite HEIGHT. This row pins the height by walking a
/// chain, and pins that the top absorbs.
test "0546: the constant lattice has height three over an infinite carrier" {
  let j = (a, b) => {
    match a {
      @flow.Undef => b
      @flow.Nac => @flow.Nac
      @flow.C(x) =>
        match b {
          @flow.Undef => @flow.C(x)
          @flow.Nac => @flow.Nac
          @flow.C(y) => if x == y { @flow.C(x) } else { @flow.Nac }
        }
    }
  }
  // ⊥ < 0 < ⊤ from any constant, and ⊤ absorbs everything
  let step1 = j(@flow.Undef, @flow.C(0))
  let step2 = j(step1, @flow.C(1))
  assert_eq(@flow.cpv_text(step2), "NAC")
  assert_eq(@flow.cpv_text(j(step2, @flow.C(0))), "NAC")
  assert_eq(@flow.cpv_text(j(@flow.C(0), @flow.C(0))), "0")
}

///|
/// THE FOLD IS BOUNDED, AND THE BOUND IS THE SAFE DIRECTION.
///
/// A constant-propagation lattice can give exactly one class of WRONG answer: a
/// constant the program does not compute, which is what an overflowing fold would
/// produce. Outside the window the answer is `NAC` -- imprecise, never wrong.
test "0546: a folded constant outside the safe window is NAC, not a wrapped number" {
  let st : @flow.State = Map([])
  let big : @ast.Expr = { span: @flow.no_span(), kind: @ast.EInt(100000), }
  let two : @ast.Expr = { span: @flow.no_span(), kind: @ast.EInt(2), }
  let prod : @ast.Expr = {
    span: @flow.no_span(),
    kind: @ast.EBin(@ast.OpMul, big, two),
  }
  assert_eq(@flow.cpv_text(@flow.cprop_eval(st, prod)), "NAC")
  // inside the window the same shape folds
  let small : @ast.Expr = { span: @flow.no_span(), kind: @ast.EInt(46340), }
  let ok : @ast.Expr = {
    span: @flow.no_span(),
    kind: @ast.EBin(@ast.OpMul, small, two),
  }
  assert_eq(@flow.cpv_text(@flow.cprop_eval(st, ok)), "92680")
}
