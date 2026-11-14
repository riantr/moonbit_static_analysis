// 0579: the pointer flow graph, pinned to deck 9-10's own picture (p.24-25, drawn
// step by step through p.33) and to its own worked example (p.74-91).
//
// THE FIXTURES ARE THE DECK'S. `Pointer Analysis -- Flow and Dispatch` (Tian Tan,
// Nanjing University, 2021) prints a pointer flow graph on p.24-25 and then runs its
// own algorithm over a seven-line program on p.74-91, and this file pins BOTH: the
// graph's edges as the deck DRAWS them, and the deck's final tables.
//
// THE DECK'S DRAWING, MEASURED. The graph on p.24-25 is built up one statement at a
// time over p.25-33, and p.33 is the completed picture: five nodes (`b`, `a`, `d`,
// `c`, `e` as red variable circles, `o_i.f` as a blue instance-field circle) and
// FIVE arrows, numbered by the statement that creates each one --
//
//     (1) b -> a        from `a = b`
//     (2) a -> o_i.f    from `c.f = a`
//     (3) c -> d        from `d = c`
//     (4) d -> o_i.f    from `c.f = d`
//     (5) o_i.f -> e    from `e = d.f`
//
// THE EXPECTED TABLES ARE IN SHORTLEX ORDER, like `pta_text`'s, because the
// toolchain's `Compare for String` is shortlex (length first, code units as the
// tie-break). So a reader should compare the ENTRIES and not their order.
//
// EVERY GRAPH HERE COMES FROM `cfg_of`, NEVER FROM A HAND-BUILT NODE LIST, for the
// reason `pta_test.mbt` states: `cfg_of` allocates nodes BACK TO FRONT, so a test
// that hand-built nodes in source order would never exercise that trap.
//
// AND THE OBJECTS ARE NAMED BY THEIR ALLOCATION SITE'S LINE, which is the deck's own
// naming and the tree's: the deck's example allocates on lines 1 and 3, and it calls
// those objects `o1` and `o3`.

///|
fn pf_span(line : Int32) -> @core.Span {
  { start: @core.pos(line, 1), end: @core.pos(line, 1), }
}

///|
fn pf_name(n : String) -> @ast.Expr {
  { span: pf_span(0), kind: @ast.EName(n), }
}

///|
fn pf_struct(ty : String) -> @ast.Expr {
  { span: pf_span(0), kind: @ast.EStruct(ty, []), }
}

///|
fn pf_field(b : @ast.Expr, f : String) -> @ast.Expr {
  { span: pf_span(0), kind: @ast.EField(b, f), }
}

///|
fn pf_int(i : Int32) -> @ast.Expr {
  { span: pf_span(0), kind: @ast.EInt(i), }
}

///|
fn pf_let(line : Int32, x : String, e : @ast.Expr) -> @ast.Stmt {
  { span: pf_span(line), kind: @ast.SLet(x, "", e), }
}

///|
fn pf_assign(line : Int32, lhs : @ast.Expr, rhs : @ast.Expr) -> @ast.Stmt {
  { span: pf_span(line), kind: @ast.SAssign(lhs, rhs), }
}

///|
/// The deck's p.81-92 program:
///
///     1 b = new C();
///     2 a = b;
///     3 c = new C();
///     4 c.f = a;
///     5 d = c;
///     6 c.f = d;
///     7 e = d.f;
///
/// AND ITS ANSWER, the deck's own (p.90-91): `pt(o3.f) = {o1,o3}` and `pt(e) = {o1,o3}`.
fn pf_deck_example() -> @flow.Cfg {
  @flow.cfg_of([
    pf_let(1, "b", pf_struct("C")),
    pf_let(2, "a", pf_name("b")),
    pf_let(3, "c", pf_struct("C")),
    pf_assign(4, pf_field(pf_name("c"), "f"), pf_name("a")),
    pf_let(5, "d", pf_name("c")),
    pf_assign(6, pf_field(pf_name("c"), "f"), pf_name("d")),
    pf_assign(7, pf_name("e"), pf_field(pf_name("d"), "f")),
  ])
}

///|
/// The deck's p.24-25 PFG picture, made concrete by giving `c` an object:
///
///     a = b;    (1)
///     c.f = a;  (2)
///     d = c;    (3)
///     c.f = d;  (4)
///     e = d.f;  (5)
///
/// with the deck's own annotation "(o_i in pts(c), o_i in pts(d))" -- one object, in
/// both `c` and `d`, because `d = c`.  The deck draws that object as `o_i`; this tree
/// names every object after its allocation line, and the picture's `c` is allocated
/// on line 1, so the same node is `o1` here and `o_i.f` there.
fn pf_deck_picture() -> @flow.Cfg {
  @flow.cfg_of([
    pf_let(1, "c", pf_struct("C")),
    pf_let(2, "a", pf_name("b")),
    pf_assign(3, pf_field(pf_name("c"), "f"), pf_name("a")),
    pf_let(4, "d", pf_name("c")),
    pf_assign(5, pf_field(pf_name("c"), "f"), pf_name("d")),
    pf_assign(6, pf_name("e"), pf_field(pf_name("d"), "f")),
  ])
}

///|
/// A cycle, so the differential propagation has something to SKIP:
///
///     1 x = new C();
///     2 y = x;
///     3 z = y;
///     4 y = z;
///
/// The fourth statement puts `o1` back into `y`, which already has it -- and the
/// deck's insight (p.59) is that re-propagating it would be redundant.
fn pf_cycle() -> @flow.Cfg {
  @flow.cfg_of([
    pf_let(1, "x", pf_struct("C")),
    pf_let(2, "y", pf_name("x")),
    pf_let(3, "z", pf_name("y")),
    pf_assign(4, pf_name("y"), pf_name("z")),
  ])
}

///|
test "0579: the pointer flow graph is the deck's picture, edge for edge (p.24-33)" {
  // The deck's four rules, as edges (p.23):
  //   Assign x = y        ->  y -> x
  //   Store  x.f = y      ->  y -> o_i.f   for each o_i in pts(x)
  //   Load   y = x.f      ->  o_i.f -> y   for each o_i in pts(x)
  // and New has NO edge, because the object is fresh.
  //
  // And the deck's p.33 picture has exactly FIVE arrows -- (1) b->a, (2) a->o_i.f,
  // (3) c->d, (4) d->o_i.f, (5) o_i.f->e.  Not six: there is no store into `e`.
  let g = pf_deck_picture()
  let sites = @flow.pta_site_names([g])
  let res = @flow.pfg_solve(g, sites)
  assert_eq(
    @flow.pfg_text(res.graph),
    "b -> a; c -> d; a -> o1.f; d -> o1.f; o1.f -> e",
  )
}

///|
test "0579: the deck's own example reaches the deck's own tables (p.81-92)" {
  // The deck's final state, printed on p.90-91: `o3.f` holds {o1,o3} and `e` holds
  // {o1,o3}.  The other four are the deck's too: b and a hold o1, c and d hold o3.
  let g = pf_deck_example()
  let sites = @flow.pta_site_names([g])
  let res = @flow.pfg_solve(g, sites)
  assert_eq(
    @flow.pfg_pts_text(res),
    "a -> {o1}; b -> {o1}; c -> {o3}; d -> {o3}; e -> {o1,o3}; o3.f -> {o1,o3}",
  )
}

///|
test "0579: the two readings AGREE -- the pointer flow graph and the CFG rules" {
  // `pta.mbt` computes the same fixed point over the CONTROL-flow graph and this
  // module computes it over the POINTER-flow graph.  A second reading that is never
  // compared with the first is a second CLAIM, so the comparison is the test.
  let g = pf_deck_example()
  let sites = @flow.pta_site_names([g])
  let pfg = @flow.pfg_solve(g, sites)
  let cgf = @flow.pta_run([g])[0]
  assert_eq(@flow.pfg_pts_text(pfg), @flow.pta_text(cgf))
}

///|
test "0579: the worklist is the deck's own trace, step for step (p.74-91)" {
  // The deck walks its example slide by slide, and each slide names the entry it is
  // processing: `b` (p.74), `c` (p.76), `a` (p.81), `d` (p.83), `o3.f` with {o1}
  // (p.88), `o3.f` with {o3} (p.89), and `e` with {o1} then {o3} (p.90).  That is
  // EIGHT steps, in that order -- and the order is the deck's, because p.75 prints
  // the worklist as `[<c,{o3}>, <a,{o1}>]` with `b` still at the head, so the
  // worklist is a QUEUE.
  let g = pf_deck_example()
  let sites = @flow.pta_site_names([g])
  let res = @flow.pfg_solve(g, sites)
  assert_eq(
    @flow.pfg_trace_text(res),
    "b, {o1}; c, {o3}; a, {o1}; d, {o3}; o3.f, {o1}; o3.f, {o3}; e, {o1}; e, {o3}",
  )
  assert_eq(res.propagated, 8)
}

///|
test "0579: the differential propagation skips the redundant steps (p.58-65)" {
  // The deck's insight: "existing points-to information in pts(n) have already been
  // propagated to n's successors, and no need to be propagated again".  So a step
  // whose delta is empty does NOTHING -- and the count of such steps is what makes
  // the claim a number.
  //
  // The deck's own program needs NO redundant step: every one of its eight steps
  // carries something new.  A cycle needs one, and the cycle's second visit to `y`
  // is the step that does nothing.
  let g = pf_deck_example()
  let sites = @flow.pta_site_names([g])
  let res = @flow.pfg_solve(g, sites)
  assert_eq(res.propagated, 8)
  assert_eq(res.skipped, 0)
  let c = pf_cycle()
  let cres = @flow.pfg_solve(c, @flow.pta_site_names([c]))
  assert_eq(cres.propagated, 4)
  assert_eq(cres.skipped, 1)
  assert_eq(@flow.pfg_trace_text(cres), "x, {o1}; y, {o1}; z, {o1}; y, {o1}")
  // And the counts are reproducible: the same program, the same number of steps.
  let again = @flow.pfg_solve(g, sites)
  assert_eq(res.propagated, again.propagated)
  assert_eq(res.skipped, again.skipped)
}

///|
test "0579: a store whose right-hand side is not a name is COUNTED, not hidden" {
  // The deck's rule table is written in VARIABLES.  `x.f = 3` has no PFG edge,
  // because an expression is not a pointer the graph can have a node for, and the
  // boundary is counted rather than silently dropped.
  let g = @flow.cfg_of([
    pf_let(1, "c", pf_struct("C")),
    pf_assign(2, pf_field(pf_name("c"), "f"), pf_int(3)),
  ])
  let sites = @flow.pta_site_names([g])
  let res = @flow.pfg_solve(g, sites)
  assert_eq(res.expr_stores, 1)
  // And the deck's program has none.
  let g2 = pf_deck_example()
  let res2 = @flow.pfg_solve(g2, @flow.pta_site_names([g2]))
  assert_eq(res2.expr_stores, 0)
}

///|
test "0579: the graph's edges are added when a NEW OBJECT arrives (p.67-68)" {
  // The deck's p.67 heading: "New points-to information may introduce new PFG edges".
  // So the edge `o3.f -> e` cannot exist before `o3` reaches `d` -- and the deck's
  // AddEdge is idempotent, so adding it twice is not adding it twice.
  let g = pf_deck_example()
  let sites = @flow.pta_site_names([g])
  let res = @flow.pfg_solve(g, sites)
  let graph = res.graph
  assert_eq(@flow.pfg_add_edge(graph, "o3.f", "e"), false)
  assert_eq(@flow.pfg_add_edge(graph, "e", "o3.f"), true)
}
