// 0580: the INTERPROCEDURAL pointer analysis, with the call graph built ON THE FLY
// -- deck 9-10 p.114-125.
//
// THE DECK'S OWN EXAMPLE IS p.126-152, and this file pins it:
//
//     1 class A {
//     2 static void main() {
//     3   A a = new A();
//     4   A b = new B();
//     5   A c = b.foo(a);
//     6 }
//     7 A foo(A x) { ... }
//     8 }
//     9 class B extends A {
//     10  A foo(A y) {
//     11    A r = new A();
//     12    return r;
//     13  }
//     14 }
//
// AND THE EXAMPLE IS BUILT TO MAKE ONE POINT: `A b = new B()` DECLARES `b` as an
// `A` and ALLOCATES a `B`. So the dispatch on the receiver's DECLARED type and the
// dispatch on the receiver's OBJECT disagree, and the deck's answer is the object
// one -- the call goes to B.foo. The deck's own dispatch is `Dispatch(o_i, k)`.
//
// SO BOTH READINGS ARE BUILT AND COMPARED, and the difference is the measurement:
// the call graph this module builds on the fly says `main -> B::foo`, and the graph
// `callgraph.mbt` builds BEFORE the analysis says `main -> A::foo`.
//
// THE FIXTURES ARE HAND-BUILT ASTs, like every other row in this package's
// pointer-analysis tests, and for the same reason `pta_test.mbt` gives: the CFG is
// built by `cfg_of`, which allocates its nodes BACK TO FRONT, so a hand-built node
// list would not exercise the ordering the analysis reads.
//
// AND THE OBJECTS ARE NAMED THE DECK'S WAY -- by their allocation site's line --
// so `o1` is the `A` of line 1 and `o2` is the `B` of line 2.

///|
fn pi_name(x : String) -> @ast.Expr {
  { span: @flow.no_span(), kind: @ast.EName(x), }
}

///|
fn pi_struct(ty : String) -> @ast.Expr {
  { span: @flow.no_span(), kind: @ast.EStruct(ty, []), }
}

///|
fn pi_method(recv : String, m : String, args : Array[@ast.Expr]) -> @ast.Expr {
  { span: @flow.no_span(), kind: @ast.EMethodCall(pi_name(recv), m, args, []), }
}

///|
fn pi_call(f : String, args : Array[@ast.Expr]) -> @ast.Expr {
  { span: @flow.no_span(), kind: @ast.ECall(f, args, []), }
}

///|
/// A span ON A LINE, because the line is what the analysis reads: an allocation
/// site is named by the line of its statement.
fn pi_span(line : Int32) -> @core.Span {
  { start: @core.pos(line, 1), end: @core.pos(line, 1), }
}

///|
fn pi_let(line : Int32, x : String, e : @ast.Expr) -> @ast.Stmt {
  { span: pi_span(line), kind: @ast.SLet(x, "", e), }
}

///|
/// A `let` WITH ITS ANNOTATION, because the receiver's DECLARED type is what the
/// declared-type dispatch resolves through -- and the deck's example is built on
/// the difference between the two.
fn pi_let_ann(
  line : Int32,
  x : String,
  ann : String,
  e : @ast.Expr,
) -> @ast.Stmt {
  { span: pi_span(line), kind: @ast.SLet(x, ann, e), }
}

///|
fn pi_tail(line : Int32, e : @ast.Expr) -> @ast.Stmt {
  { span: pi_span(line), kind: @ast.STail(e), }
}

///|
fn pi_param(name : String, ann : String) -> @ast.Param {
  { name, tyann: ann, omittable: false, span: @flow.no_span(), }
}

///|
fn pi_fn(
  name : String,
  params : Array[@ast.Param],
  body : Array[@ast.Stmt],
) -> @flow.CgFn {
  { name, params, body, }
}

///|
/// The types the deck's example declares: `A` and `B`.
fn pi_types() -> @flow.TraitTable {
  @flow.collect_trait_table("struct A { }\nstruct B { }\n")
}

///|
/// The deck's p.126-152 program, as the tree sees it.
///
/// `b` is DECLARED as an `A` and ALLOCATES a `B` -- that is the deck's line 4, and
/// it is the whole point of the example.
fn pi_deck_program() -> Array[@flow.CgFn] {
  [
    pi_fn("main", [], [
      pi_let_ann(1, "a", "A", pi_struct("A")),
      pi_let_ann(2, "b", "A", pi_struct("B")),
      pi_let(3, "c", pi_method("b", "foo", [pi_name("a")])),
    ]),
  ]
}

///|
/// The interprocedural program: a call to a top-level function, so the CALL RULE
/// is fully visible -- the argument reaches the callee's parameter, the callee's
/// result reaches the caller's left-hand side -- and a function nobody calls, so
/// the "reachable world" (p.115: "Only reachable methods and statements are
/// analyzed") is visible too.
fn pi_inter_program() -> Array[@flow.CgFn] {
  [
    pi_fn("main", [], [
      pi_let(1, "x", pi_struct("A")),
      pi_let(2, "y", pi_call("id", [pi_name("x")])),
    ]),
    pi_fn("id", [pi_param("n", "A")], [
      pi_let(3, "r", pi_struct("A")),
      pi_tail(4, pi_name("r")),
    ]),
    pi_fn("unreached", [], [pi_let(5, "z", pi_struct("A"))]),
  ]
}

///|
test "0580: the dispatch is on the receiver's OBJECT, and that changes the graph" {
  // The deck's own example (p.126): `A b = new B(); b.foo(a);`
  //
  // THE CALL GRAPH BUILT ON THE FLY resolves the call on the OBJECT, and the
  // object is a `B` -- so the call goes to B.foo.
  let fns = pi_deck_program()
  let res = @flow.pta_inter_run("main", fns, pi_types())
  assert_eq(@flow.pta_inter_cg_text(res), "main -> B::foo")
  // AND THE GRAPH BUILT BEFORE THE ANALYSIS resolves it on the DECLARED type,
  // and the declared type is an `A` -- so that graph says A.foo.
  //
  // THE TWO DISAGREE, and the deck's answer is the object's.
  let cg = @flow.build_call_graph("main", fns, pi_types())
  let cg_lines : Array[String] = []
  for e in cg.edges {
    cg_lines.push(e.caller + " -> " + e.callee)
  }
  cg_lines.sort()
  assert_eq(cg_lines.join("; "), "main -> A::foo")
}

///|
test "0580: the reachable world is the one the analysis reached (p.115)" {
  // The deck's p.115: "Only reachable methods and statements are analyzed".
  // `unreached` is never called, so it is not in the reachable world and its
  // allocation never enters the work list.
  let fns = pi_inter_program()
  let res = @flow.pta_inter_run("main", fns, pi_types())
  assert_eq(res.reachable.join(", "), "main, id")
  let pts = @flow.pta_inter_text(res)
  assert_true(pts.contains("unreached|z") == false)
  // And the statements that WERE analyzed are the reachable ones -- counted in
  // this tree's own unit, which is the CFG node the analysis reads.
  let want = @flow.cfg_of(fns[0].body).source_order().length() +
    @flow.cfg_of(fns[1].body).source_order().length()
  assert_eq(res.analyzed, want)
}

///|
test "0580: the call rule crosses the call boundary (p.121-124)" {
  // The deck's Call rule, as PFG edges (p.121): "a1 -> m_p1" and "r <- m_ret".
  let fns = pi_inter_program()
  let res = @flow.pta_inter_run("main", fns, pi_types())
  assert_eq(
    @flow.pta_inter_text(res),
    "id|n -> {o1}; id|r -> {o3}; main|x -> {o1}; main|y -> {o3}; id|result -> {o3}",
  )
  assert_eq(
    @flow.pfg_text(res.graph),
    "main|x -> id|n; id|r -> id|result; id|result -> main|y",
  )
  assert_eq(@flow.pta_inter_cg_text(res), "main -> id")
}

///|
test "0580: the deck's output is TWO things (p.125)" {
  // "Algorithms Output: Points-to Relations (pt), Call Graph (CG)".
  let fns = pi_deck_program()
  let res = @flow.pta_inter_run("main", fns, pi_types())
  // The points-to relations: the two objects, and the receiver that reached the
  // callee's `this` (the deck's p.122: "Pass receiver object to this variable").
  //
  // THE ORDER IS SHORTLEX -- length first -- like every other printed table in
  // this tree, so "B::foo|this -> {o2}" is LAST because it is the longest.
  assert_eq(
    @flow.pta_inter_text(res),
    "main|a -> {o1}; main|b -> {o2}; B::foo|this -> {o2}",
  ) // The call graph.
  assert_eq(@flow.pta_inter_cg_text(res), "main -> B::foo")
  // AND THE BOUNDARY, COUNTED: this tree's AST has no method bodies, so B::foo
  // is an edge and not a source of statements.
  assert_eq(res.no_body, 1)
}

///|
test "0580: the on-the-fly graph and the separately built one AGREE when they can" {
  // On a program whose only call names its callee, the two readings must agree --
  // a second reading that disagrees with the first on everything would be a
  // second CLAIM, not a second measurement.
  let fns = pi_inter_program()
  let res = @flow.pta_inter_run("main", fns, pi_types())
  let cg = @flow.build_call_graph("main", fns, pi_types())
  let cg_lines : Array[String] = []
  for e in cg.edges {
    cg_lines.push(e.caller + " -> " + e.callee)
  }
  cg_lines.sort()
  assert_eq(@flow.pta_inter_cg_text(res), cg_lines.join("; "))
  assert_eq(res.reachable.join(", "), cg.reachable.join(", "))
}

///|
test "0580: the differential propagation is the deck's, over the reachable world" {
  // The deck's §3 (p.58-65): the delta is what is propagated, and an empty delta
  // does nothing.  The counts are the deck's discipline made a number.
  let fns = pi_deck_program()
  let res = @flow.pta_inter_run("main", fns, pi_types())
  assert_true(res.propagated > 0)
  // And the trace is reproducible: the same program, the same steps.
  let again = @flow.pta_inter_run("main", fns, pi_types())
  assert_eq(res.propagated, again.propagated)
  assert_eq(res.skipped, again.skipped)
  assert_eq(@flow.pta_inter_text(res), @flow.pta_inter_text(again))
}
