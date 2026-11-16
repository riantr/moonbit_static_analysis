// 0598: the tabulation algorithm -- the deck's step 3, and the answer it gives.
//
// THE DECK. `CFL-Reachability and IFDS` (Yue Li, Nanjing University, 2021).
// This file pins the deck's CHAPTER 5's third step: the tabulation on the
// exploded supergraph (p.135-150), and the answer it gives.
//
// AND THE GRAPH IS THE SAME ONE `ifds_test.mbt` BUILDS, because the point of
// the increment is a COMPARISON: the tabulated facts and the traditional
// analysis's facts are two readings of the same transfer functions, and a
// comparison needs one graph, not two.

///|
/// The exploded supergraph of the five-node graph, with the glue edge.
fn ifds_tab_graph() -> (@flow.Cfg, @flow.Exploded) {
  let cfg = ifds_reach_graph()
  let gen = @flow.reaching_gen(cfg)
  let kill = @flow.reaching_kill(cfg)
  let x = @flow.ifds_explode(cfg, gen, kill, true)
  (cfg, x)
}

///|
/// The exploded supergraph of the five-node graph, WITHOUT the glue edge.
fn ifds_tab_graph_noglue() -> (@flow.Cfg, @flow.Exploded) {
  let cfg = ifds_reach_graph()
  let gen = @flow.reaching_gen(cfg)
  let kill = @flow.reaching_kill(cfg)
  let x = @flow.ifds_explode(cfg, gen, kill, false)
  (cfg, x)
}

///|
test "0598: the tabulation finds the realizable paths from <main, 0> -- p.139-140" {
  // AND THE DECK'S THEOREM IS THE ROW: "Let n be a program point, data fact d
  // in MRPn, iff there is a realizable path in G# from <smain, 0> to <n, d>."
  let (cfg, x) = ifds_tab_graph()
  let t = @flow.ifds_tabulate(x, cfg.entry)
  // AND THE ZERO FACT IS AT EVERY NODE THE WALK REACHED, because the glue edge
  // carries it -- that is what the glue edge is FOR.
  let mut v = 0
  while v < cfg.kinds.length() {
    assert_eq(t.states[v].contains(@flow.ifds_zero()), true)
    v = v + 1
  }
  // AND THE DEFINITIONS ARE THE ONES THE PROGRAM HAS.
  assert_eq(@flow.def_set_text(@flow.ifds_defs_at(t.states[0])), "")
  assert_eq(@flow.def_set_text(@flow.ifds_defs_at(t.states[1])), "")
  assert_eq(@flow.def_set_text(@flow.ifds_defs_at(t.states[2])), "x@1")
  assert_eq(@flow.def_set_text(@flow.ifds_defs_at(t.states[3])), "x@2")
  assert_eq(@flow.def_set_text(@flow.ifds_defs_at(t.states[4])), "x@2,y@3")
}

///|
test "0598: the tabulation REPRODUCES the analysis this tree already computes -- p.139-140" {
  // AND THIS IS THE MEASUREMENT THE INCREMENT EXISTS FOR: the traditional
  // analysis solves a fixed-point equation over sets, and the tabulation walks
  // a graph. Two readings of the same transfer functions, and they have to
  // AGREE -- node by node, fact by fact.
  let (cfg, x) = ifds_tab_graph()
  let t = @flow.ifds_tabulate(x, cfg.entry)
  let outs = @flow.reaching_out(cfg)
  let ins = @flow.reaching_in(cfg, outs)
  let mut v = 0
  while v < cfg.kinds.length() {
    assert_eq(
      @flow.def_set_text(@flow.ifds_defs_at(t.states[v])),
      @flow.def_set_text(ins[v]),
    )
    v = v + 1
  }
}

///|
test "0598: WITHOUT the glue edge, the tabulation's answer is EMPTY -- p.92-96" {
  // AND THIS IS THE DECK'S CLAIM, MEASURED ON THE ANSWER AND NOT ON A
  // COMMENT. p.95: without the edge 0->0 "the representation relation for each
  // edge cannot be connected or 'pasted' together ... Thus IFDS cannot produce
  // correct solutions via such disconnected representation relations."
  let (cfg, x) = ifds_tab_graph_noglue()
  let t = @flow.ifds_tabulate(x, cfg.entry)
  // AND THE START NODE CARRIES THE ZERO FACT AND NOTHING ELSE, and every other
  // node carries NOTHING AT ALL -- not even the zero fact.
  assert_eq(@flow.def_set_text(t.states[0]), "0")
  let mut v = 1
  while v < cfg.kinds.length() {
    assert_eq(@flow.def_set_text(t.states[v]), "")
    v = v + 1
  }
  // AND SO THE COMPARISON WITH THE TRADITIONAL ANALYSIS IS NOT "the same
  // answer" BUT "NO ANSWER": the tabulation found zero definitions, and the
  // traditional analysis found three.
  let outs = @flow.reaching_out(cfg)
  let ins = @flow.reaching_in(cfg, outs)
  assert_eq(@flow.def_set_text(ins[4]), "x@2,y@3")
}

///|
test "0598: the deck's own bound, p.141, beside the work the walk did" {
  // AND p.141 PRINTS THE BOUND: O(ED3). And the deck itself says on p.142-143
  // that it does NOT cover the whole algorithm -- so what is compared with the
  // bound here is the intraprocedural walk's measured work, and the coverage
  // is printed beside it.
  let (cfg, x) = ifds_tab_graph()
  let t = @flow.ifds_tabulate(x, cfg.entry)
  // E IS THE EDGES OF THE EXPLODED SUPERGRAPH AND D IS THE FACTS -- the three
  // definitions plus the zero fact -- so the bound is 14 * 4^3 = 896.
  assert_eq(@flow.ifds_tabulate_bound(x), 896)
  // AND THE WALK FOLLOWED EIGHT OF THE FOURTEEN EDGES, and the six it did NOT
  // follow all tell one story: their SOURCE pair was never reached. Three of
  // them leave the ENTRY node with a definition as their source, and no
  // definition reaches the entry -- the walk starts at the entry's ZERO fact.
  // Two more leave node 1, whose definitions never arrived there either. And
  // the sixth is the edge that would carry x@1 past the node that kills it.
  //
  // AND THE FIRST DRAFT OF THIS ROW SAID TEN. The measurement is what the
  // count is, and the count is what the walk did.
  assert_eq(t.visited, 8)
  assert_eq(x.edges.length(), 14)
}

///|
test "0598: the tabulation's answer, printed, is the answer the reader reads -- p.140" {
  // AND THE DECK'S PICTURE TURNS THE WHITE CIRCLES BLUE -- so a readable
  // rendering of the tabulation is part of what the increment delivers.
  let (cfg, x) = ifds_tab_graph()
  let t = @flow.ifds_tabulate(x, cfg.entry)
  let text = @flow.ifds_tabulate_text(t)
  assert_eq(text.contains("2:0,x@1"), true)
  assert_eq(text.contains("4:0,x@2,y@3"), true)
}
