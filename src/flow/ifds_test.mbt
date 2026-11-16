// 0597: the exploded supergraph, and the glue edge that makes it work.
//
// THE DECK. `CFL-Reachability and IFDS` (Yue Li, Nanjing University, 2021).
// This file pins its CHAPTER 4 (p.58-81, the supergraph and the flow
// functions) and the first half of its CHAPTER 5 (p.83-97, the exploded
// supergraph and the glue edge).
//
// WHY HAND-BUILT AND NOT PARSED: the same reason `reaching_test.mbt` gives.
// This package does not depend on the PARSER on purpose, so a test builds an
// `Expr` without reaching for the parser -- which is what the toolchain's
// `--deny-warn` treatment of a test-only import forces.
//
// AND THE FLOW FUNCTIONS ARE THE TREE'S OWN: `reaching_gen` and `reaching_kill`
// are called here, not re-implemented, because the whole claim of the next
// increment is that the exploded supergraph and the traditional analysis are
// TWO READINGS OF THE SAME TRANSFER FUNCTIONS.

///|
/// `let name = e`
fn ifds_let(name : String, e : @ast.Expr) -> @ast.Stmt {
  { span: @flow.no_span(), kind: @ast.SLet(name, "", e), }
}

///|
/// `f(args)`
fn ifds_call(f : String, args : Array[@ast.Expr]) -> @ast.Expr {
  { span: @flow.no_span(), kind: @ast.ECall(f, args, []), }
}

///|
/// `return e`
fn ifds_ret(e : @ast.Expr) -> @ast.Stmt {
  { span: @flow.no_span(), kind: @ast.SReturn(Some(e)), }
}

///|
/// A graph with the given nodes and the given successors.
fn ifds_graph(
  kinds : Array[@flow.NodeKind],
  succs : Array[Array[Int32]],
) -> @flow.Cfg {
  let spans : Array[@core.Span] = []
  let mut i = 0
  while i < kinds.length() {
    spans.push(@flow.no_span())
    i = i + 1
  }
  {
    kinds,
    spans,
    succ: succs,
    pred: @flow.pred_of(succs),
    entry: 0,
    exit: kinds.length() - 1,
    skipped: 0,
  }
}

///|
/// THE GRAPH THE RELATIONS ARE READ OVER: five nodes, and two definitions of
/// `x` and one of `y`.
///
///     0  entry
///     1  x = 1        generates x@1
///     2  x = 2        generates x@2, KILLS x@1
///     3  y = 3        generates y@3
///     4  exit
fn ifds_reach_graph() -> @flow.Cfg {
  ifds_graph(
    [
      @flow.Entry,
      @flow.Assign("x", int_e(1)),
      @flow.Assign("x", int_e(2)),
      @flow.Assign("y", int_e(3)),
      @flow.Exit,
    ],
    [[1], [2], [3], [4], []],
  )
}

///|
/// A program with ONE call, so the supergraph has the deck's three edges.
fn ifds_call_program() -> Array[@flow.IFn] {
  [
    {
      name: "main",
      params: [],
      body: [ifds_let("a", int_e(1)), ifds_let("b", ifds_call("f", [ex("a")]))],
    },
    {
      name: "f",
      params: ["p"],
      body: [ifds_let("c", ex("p")), ifds_ret(ex("c"))],
    },
  ]
}

///|
test "0597: the tree's supergraph carries the deck's THREE edges per call -- p.58-65" {
  // AND THE THREE EDGES ARE MEASURED, not asserted: the deck's p.63-65 says
  //   - an intraprocedural call-to-return-site edge from Callp to Retp
  //   - an interprocedural call-to-start edge from Callp to sp
  //   - an interprocedural exit-to-return-site edge from ep to Retp
  // and `src/flow/icfg.mbt` builds exactly those three. This row is the
  // MEASUREMENT that chapter 4 is already here, and it is a measurement
  // because a supergraph that had grown a fourth edge kind would change what
  // chapter 5 means.
  let g = @flow.icfg_of(ifds_call_program())
  let text = @flow.ifds_supergraph_text(g)
  assert_eq(text.contains("call sites=1"), true)
  // THE TWO EDGES THAT LEAVE THE CALL NODE.
  assert_eq(text.contains("CallToReturn=1"), true)
  assert_eq(text.contains("Call=1"), true)
  // AND THE THIRD, WHICH LEAVES THE CALLEE'S EXIT.
  assert_eq(text.contains("Ret=1"), true)
}

///|
test "0597: the call node carries the call-to-return and the call edge -- p.63-64" {
  let g = @flow.icfg_of(ifds_call_program())
  let calls = @flow.ifds_supergraph_calls(g)
  assert_eq(calls.length(), 1)
  assert_eq(calls[0].contains("CallToReturn"), true)
  // AND THE SECOND EDGE, with the separator in front of it, so the test says
  // WHICH edge it means: "CallToReturn" CONTAINS the substring "Ret", so a
  // test that looked for "Ret" in a space-separated list would have matched
  // the FIRST edge and been measuring the wrong thing.
  assert_eq(calls[0].contains("+Call"), true)
  // AND NOT THE RETURN EDGE, because that edge does not leave the call node --
  // it leaves the CALLEE's exit and arrives at the call's return site.
  assert_eq(calls[0].contains("+Ret"), false)
}

///|
test "0597: the return edge leaves the CALLEE's exit -- p.65" {
  // AND IT IS COUNTED SEPARATELY and not folded into the call site's line,
  // because a reader who looks for it on the call node will not find it and
  // should not conclude that it is missing.
  let g = @flow.icfg_of(ifds_call_program())
  let rets = @flow.ifds_supergraph_returns(g)
  assert_eq(rets.length(), 1)
  assert_eq(rets[0].contains("Ret "), true)
}

///|
test "0597: the representation relation is the deck's FORMULA -- p.84" {
  // THE DECK'S FORMULA, verbatim:
  //
  //   Rf = { (0,0) } U { (0,y) | y in f(EMPTY) } U { (x,y) | y not in f(EMPTY)
  //                       and y in f({x}) }
  //
  // and for the tree's transfer OUT[B] = gen_B U (IN[B] - kill_B) that is
  //
  //   (0 -> 0)   at every node                      THE GLUE EDGE
  //   (0 -> g)   for every g in gen[B]              the constant part
  //   (x -> x)   for every x not in gen[B] and not in kill[B]
  let cfg = ifds_reach_graph()
  let gen = @flow.reaching_gen(cfg)
  let kill = @flow.reaching_kill(cfg)
  let facts = @flow.ifds_definitions(gen)
  // THE FACT UNIVERSE IS THE DEFINITIONS THE PROGRAM MAKES.
  assert_eq(facts.length(), 3)
  // AND THE RELATION OF THE NODE THAT GENERATES x@1.
  let rel = @flow.ifds_reach_rel(gen, kill, 1, facts, true)
  let text = @flow.ifds_rel_text(rel)
  // THE FIRST CLAUSE IS THERE -- the glue edge.
  assert_eq(text.contains("0->0"), true)
  // THE CONSTANT PART HANGS ON THE ZERO FACT -- the deck's `lambda S.{a}`.
  assert_eq(text.contains("0->x@1"), true)
  // AND THE FACT THAT SURVIVES THE NODE.
  assert_eq(text.contains("y@3->y@3"), true)
  // AND THE GENERATED FACT GETS NO (x,x) PAIR OF ITS OWN, because the deck's
  // third clause says `y not in f(EMPTY)` -- a fact the node generates is
  // already carried by the constant part. This is the deck's own example on
  // p.85: `lambda S.{a}` has the edges 0->0, 0->a and b->b, and NOT a->a.
  assert_eq(text.contains("x@1->x@1"), false)
  // AND THE OTHER DEFINITION OF x IS NOT THERE, because node 2 kills it -- and
  // the kill is over the WHOLE FUNCTION, not over the block (p.46).
  assert_eq(text.contains("x@2"), false)
}

///|
test "0597: the KILL is honoured by the relation, not only by the solver -- p.46, p.48" {
  let cfg = ifds_reach_graph()
  let gen = @flow.reaching_gen(cfg)
  let kill = @flow.reaching_kill(cfg)
  let facts = @flow.ifds_definitions(gen)
  // NODE 2 GENERATES x@2 AND KILLS x@1, so its relation keeps x@2 out of the
  // survivors and brings it in as the constant part instead.
  let rel = @flow.ifds_reach_rel(gen, kill, 2, facts, true)
  let text = @flow.ifds_rel_text(rel)
  assert_eq(text.contains("0->x@2"), true)
  assert_eq(text.contains("x@1"), false)
  // AND THE FACT THAT SURVIVES THE KILL SURVIVES THE NODE.
  assert_eq(text.contains("y@3->y@3"), true)
  // AND A NODE THAT DEFINES NOTHING KILLS NOTHING, so every fact survives it.
  let entry = @flow.ifds_reach_rel(gen, kill, 0, facts, true)
  let etext = @flow.ifds_rel_text(entry)
  assert_eq(etext.contains("x@1->x@1"), true)
  assert_eq(etext.contains("x@2->x@2"), true)
  assert_eq(etext.contains("y@3->y@3"), true)
  // AND THE ENTRY GENERATES NOTHING, so its relation has no constant part.
  assert_eq(etext.contains("0->x"), false)
}

///|
test "0597: the glue edge is the relation's FIRST CLAUSE -- p.84, p.96" {
  // THE DECK'S (0,0) IS A CLAUSE OF Rf AND NOT AN EDGE ADDED BESIDE IT, so
  // the switch is on the RELATION -- and that is where the deck puts it.
  let cfg = ifds_reach_graph()
  let gen = @flow.reaching_gen(cfg)
  let kill = @flow.reaching_kill(cfg)
  let facts = @flow.ifds_definitions(gen)
  let glue_on = @flow.ifds_rel_text(
    @flow.ifds_reach_rel(gen, kill, 1, facts, true),
  )
  let glue_off = @flow.ifds_rel_text(
    @flow.ifds_reach_rel(gen, kill, 1, facts, false),
  )
  assert_eq(glue_on.contains("0->0"), true)
  assert_eq(glue_off.contains("0->0"), false)
  // AND THE REST OF THE RELATION IS THE SAME ON BOTH SIDES: the glue edge is
  // ONE clause and not a different relation.
  assert_eq(glue_on.contains("0->x@1"), true)
  assert_eq(glue_off.contains("0->x@1"), true)
  assert_eq(glue_on.contains("y@3->y@3"), true)
  assert_eq(glue_off.contains("y@3->y@3"), true)
}

///|
test "0597: WITHOUT the glue edge, NO EDGE LEAVES THE START PAIR -- p.95" {
  // AND THIS IS THE DECK'S FAILURE CASE, MEASURED. The deck says that without
  // the edge 0->0 "the representation relation for each edge cannot be
  // connected or 'pasted' together ... Thus IFDS cannot produce correct
  // solutions via such disconnected representation relations."
  //
  // AND THE MEASUREMENT IS LOCAL AND SHARP: the start pair is (entry, 0), and
  // without the glue edge NOTHING LEAVES IT. The exploded supergraph is not
  // wrong in some subtle way -- it is DISCONNECTED.
  let cfg = ifds_reach_graph()
  let gen = @flow.reaching_gen(cfg)
  let kill = @flow.reaching_kill(cfg)
  let without = @flow.ifds_explode(cfg, gen, kill, false)
  let mut leaving = 0
  for e in without.edges {
    if e.from_node == 0 && e.from_fact == @flow.ifds_zero() {
      leaving = leaving + 1
    }
  }
  assert_eq(leaving, 0)
}

///|
test "0597: WITH the glue edge, the zero fact CROSSES every edge -- p.95" {
  // AND THE SAME GRAPH WITH THE GLUE EDGE CONNECTS: the (0,0) pair is the edge
  // that carries the zero fact from one relation to the next, so the next
  // relation's constant part has a zero fact to fire on. That is what "pasted
  // together" means.
  let cfg = ifds_reach_graph()
  let gen = @flow.reaching_gen(cfg)
  let kill = @flow.reaching_kill(cfg)
  let glue_on = @flow.ifds_explode(cfg, gen, kill, true)
  // AND THE GLUE EDGES ARE COUNTED OUT OF THE GRAPH, not stored beside it.
  let glue = @flow.ifds_glue_edges(glue_on)
  // ONE PER OUTGOING EDGE OF THE FOUR NODES THAT HAVE ONE -- the exit node
  // has none, so there are FOUR and not FIVE.
  assert_eq(glue.length(), 4)
  // AND EVERY GLUE EDGE IS THE ZERO FACT, FROM ONE NODE TO THE NEXT.
  for e in glue {
    assert_eq(e.from_fact, @flow.ifds_zero())
    assert_eq(e.to_fact, @flow.ifds_zero())
    assert_eq(e.from_node + 1, e.to_node)
  }
  // AND THE START PAIR HAS AN EDGE LEAVING IT.
  let mut leaving = 0
  for e in glue_on.edges {
    if e.from_node == 0 && e.from_fact == @flow.ifds_zero() {
      leaving = leaving + 1
    }
  }
  assert_eq(leaving, 1)
}

///|
test "0597: the exploded supergraph's EDGES are the relation's pairs, one per successor -- p.53" {
  // AND THE COUNT IS THE DECK'S: the exploded supergraph's edges are the
  // representation relation's pairs, one edge per (pair, successor).
  let cfg = ifds_reach_graph()
  let gen = @flow.reaching_gen(cfg)
  let kill = @flow.reaching_kill(cfg)
  let x = @flow.ifds_explode(cfg, gen, kill, true)
  // NODE 1'S RELATION HAS THREE PAIRS -- the glue edge, the constant part and
  // the one survivor -- AND ONE SUCCESSOR, SO THREE EDGES.
  let mut n = 0
  for e in x.edges {
    if e.from_node == 1 {
      n = n + 1
    }
  }
  assert_eq(n, 3)
  // AND THE TEXT OF THE EXPLODED GRAPH SHOWS A NODE-FACT PAIR ON EACH SIDE.
  let text = @flow.ifds_exploded_text(x)
  assert_eq(text.contains("1:0->2:0"), true)
  assert_eq(text.contains("1:0->2:x@1"), true)
}

///|
test "0597: the exploded supergraph's edge COUNT, with and without the glue -- p.84" {
  // AND THE COUNT IS THE ARITHMETIC, WRITTEN OUT. Each node contributes its
  // relation's pairs times its successors:
  //
  //   node 0  entry   glue + 3 survivors,           1 successor  ->  4 with / 3 without
  //   node 1  x = 1   glue + constant + 1 survivor,  1 successor  ->  3 with / 2 without
  //   node 2  x = 2   glue + constant + 1 survivor,  1 successor  ->  3 with / 2 without
  //   node 3  y = 3   glue + constant + 2 survivors, 1 successor  ->  4 with / 3 without
  //   node 4  exit    glue + 3 survivors,            0 successors ->  0 with / 0 without
  //
  //                                                total  14 with / 10 without
  let cfg = ifds_reach_graph()
  let gen = @flow.reaching_gen(cfg)
  let kill = @flow.reaching_kill(cfg)
  assert_eq(@flow.ifds_explode(cfg, gen, kill, true).edges.length(), 14)
  assert_eq(@flow.ifds_explode(cfg, gen, kill, false).edges.length(), 10)
}

///|
test "0597: the zero fact is NOT a definition, and cannot collide with one -- p.95" {
  // A DEFINITION'S KEY IS `name@node`, so it always carries an `@`, and the
  // zero fact does not. Two facts that can be confused are two facts that can
  // be reported wrongly.
  let cfg = ifds_reach_graph()
  let gen = @flow.reaching_gen(cfg)
  let facts = @flow.ifds_definitions(gen)
  for f in facts {
    assert_eq(f.contains("@"), true)
    assert_eq(f == @flow.ifds_zero(), false)
  }
  assert_eq(@flow.ifds_zero() == "0", true)
}
