// 0550: the tests for the flow-sensitive points-to analysis.
//
// THE EXPECTATIONS ARE THE DECK'S PRINTED TABLES, NOT THIS TREE'S PREVIOUS ANSWERS.
// p.64 is the flow-sensitive table for the four-statement program on p.57, p.68 is
// the flow-insensitive table for the SAME program, and p.69 prints the word "false
// positive" next to the flow-insensitive `s`. A test that asserted only "the two
// analyses disagree" would pass for the wrong reason -- these assert both tables.
//
// THE GRAPHS COME FROM `cfg_of`, NEVER FROM A HAND-BUILT NODE LIST, because
// `cfg_of` allocates nodes BACK TO FRONT and a test that built them in source order
// would never exercise the ordering trap that `pta_source_order` exists to undo.
//
// THE EXPECTED STRINGS ARE IN SHORTLEX ORDER, NOT ALPHABETICAL, for the reason
// `pta_test.mbt` records: `Array::sort` orders strings by LENGTH first.

///|
fn pf_span_at(line : Int32, col : Int32) -> @core.Span {
  { start: @core.pos(line, col), end: @core.pos(line, col), }
}

///|
fn pf_span(line : Int32) -> @core.Span {
  pf_span_at(line, 1)
}

///|
fn pf_name(n : String) -> @ast.Expr {
  { span: pf_span(0), kind: @ast.EName(n), }
}

///|
fn pf_str(v : String) -> @ast.Expr {
  { span: pf_span(0), kind: @ast.EStr(v, []), }
}

///|
fn pf_field(b : @ast.Expr, f : String) -> @ast.Expr {
  { span: pf_span(0), kind: @ast.EField(b, f), }
}

///|
fn pf_struct(ty : String) -> @ast.Expr {
  { span: pf_span(0), kind: @ast.EStruct(ty, []), }
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
fn pf_if(line : Int32, cond : @ast.Expr, body : Array[@ast.Stmt]) -> @ast.Stmt {
  { span: pf_span(line), kind: @ast.SIf(cond, body, [], None), }
}

///|
fn pf_while(
  line : Int32,
  cond : @ast.Expr,
  body : Array[@ast.Stmt],
) -> @ast.Stmt {
  { span: pf_span(line), kind: @ast.SWhile(cond, body), }
}

///|
/// The index of the node whose span starts on `line`; -1 when there is none.
fn pf_node_at(g : @flow.Cfg, line : Int32) -> Int32 {
  let mut i = 0
  let mut found = -1
  while i < g.spans.length() {
    if found < 0 && g.spans[i].start.line == line {
      found = i
    }
    i = i + 1
  }
  found
}

///|
/// The deck's four-statement program from p.57, built as statements.
fn pf_p57_body() -> Array[@ast.Stmt] {
  [
    pf_let(1, "c", pf_struct("C")),
    pf_assign(2, pf_field(pf_name("c"), "f"), pf_str("x")),
    pf_let(3, "s", pf_field(pf_name("c"), "f")),
    pf_assign(4, pf_field(pf_name("c"), "f"), pf_str("y")),
  ]
}

///|
/// The state after the node on `line`, as text.
fn pf_after_text(g : @flow.Cfg, line : Int32) -> String {
  @flow.pta_text(@flow.pta_run_flow_sensitive(g)[pf_node_at(g, line)])
}

///|
/// The state after the EXIT node of the graph, as text.
///
/// THE EXIT NODE IS LOOKED UP, NOT GUESSED. The first version of this helper took
/// the LAST INDEX of the state array, and every row that used it failed with an
/// empty string -- because `cfg_of` allocates nodes BACK TO FRONT, so the last
/// index is the ENTRY, whose state is the empty map. The graph carries `exit` for
/// this, and this is the same trap `pta_source_order` exists to undo.
fn pf_last_text(g : @flow.Cfg) -> String {
  let after = @flow.pta_run_flow_sensitive(g)
  @flow.pta_text(after[g.exit])
}

///|
/// The subset of `objs` selected by the bits of `mask`.
fn pf_subset(objs : Array[String], mask : Int32) -> Array[String] {
  let out : Array[String] = []
  let mut i = 0
  while i < objs.length() {
    if (mask & (1 << i)) != 0 {
      out.push(objs[i])
    }
    i = i + 1
  }
  out
}

///|
/// A points-to map from (pointer, objects) pairs.
fn pf_pts(pairs : Array[(String, Array[String])]) -> @flow.Pta {
  let out : @flow.Pta = Map([])
  for pair in pairs {
    let (k, objs) = pair
    let s : Map[String, Bool] = Map([])
    for o in objs {
      s.set(o, true)
    }
    out.set(k, s)
  }
  out
}

///|
/// Every points-to map over two pointers and two objects: 4 x 4 = 16.
fn pf_law_maps() -> Array[@flow.Pta] {
  let objs = ["o1", "o2"]
  let out : Array[@flow.Pta] = []
  let mut i = 0
  while i < 4 {
    let mut j = 0
    while j < 4 {
      out.push(pf_pts([("p", pf_subset(objs, i)), ("q", pf_subset(objs, j))]))
      j = j + 1
    }
    i = i + 1
  }
  out
}

///|
/// `a` is a subset of `b` -- the order of the points-to map lattice.
fn pf_pts_subset(a : @flow.Pta, b : @flow.Pta) -> Bool {
  for k, s in a {
    match b.get(k) {
      None => return false
      Some(t) =>
        for o, _ in s {
          if t.contains(o) == false {
            return false
          }
        }
    }
  }
  true
}

///|
/// The flow-sensitive analysis, computed with the ROUND-ROBIN solver, so that the
/// two solvers can be compared on this lattice.
fn pf_round_robin(g : @flow.Cfg) -> Array[@flow.Pta] {
  let tr = @flow.pta_fs_transfer_of(g)
  @flow.solve_round_robin(@flow.pta_map_lattice(), g.kinds.length(), g.pred, tr)
}

///|
test "0550: the map at each location is the deck's p.61-64 table" {
  let g = @flow.cfg_of(pf_p57_body())
  // p.61 prints the state after the load: c -> {o1}, o1.f -> {"x"}, s -> {"x"}.
  // p.62 is the same, p.63 adds the store at line 4 and p.64 is the final table:
  // c -> {o1}, o1.f -> {"y"}, s -> {"x"}.
  assert_eq(pf_after_text(g, 1), "c -> {o1}")
  assert_eq(pf_after_text(g, 2), "c -> {o1}; o1.f -> {\"x\"}")
  assert_eq(pf_after_text(g, 3), "c -> {o1}; s -> {\"x\"}; o1.f -> {\"x\"}")
  assert_eq(pf_after_text(g, 4), "c -> {o1}; s -> {\"x\"}; o1.f -> {\"y\"}")
}

///|
test "0550: the flow-sensitive reading is the deck's p.64 and the flow-insensitive one is p.68" {
  let g = @flow.cfg_of(pf_p57_body())
  // p.64, the flow-sensitive table.
  assert_eq(pf_last_text(g), "c -> {o1}; s -> {\"x\"}; o1.f -> {\"y\"}")
  // p.68, the flow-insensitive table for the SAME program.
  assert_eq(
    @flow.pta_text(@flow.pta_run([g])[0]),
    "c -> {o1}; s -> {\"x\",\"y\"}; o1.f -> {\"x\",\"y\"}",
  )
  // p.69 prints "false positive" next to the flow-insensitive `s`: the load at line
  // 3 runs BEFORE the store at line 4, so `s` can only ever hold "x".
  let weak = @flow.pta_run([g])[0]
  let fs = @flow.pta_run_flow_sensitive(g)
  assert_eq(@flow.pta_of(weak, "s").length(), 2)
  assert_eq(@flow.pta_of(fs[pf_node_at(g, 4)], "s").length(), 1)
}

///|
test "0550: the general analysis and the straight-line control agree on the deck's program" {
  // Two different implementations of the same question: one walks the statements
  // once in source order, the other is a fixed point over the graph. They have to
  // give the same answer on the program the deck prints, or one of them is wrong.
  let g = @flow.cfg_of(pf_p57_body())
  assert_eq(pf_last_text(g), @flow.pta_text(@flow.pta_run_ordered(g)))
}

///|
test "0550: a branch is where the straight-line control stops and the analysis does not" {
  // 1 a = new A(); 2 a.f = "x"; 3 if cond { 4 s = a.f } 6 a.f = "y";
  //
  // The load at line 4 runs BEFORE the store at line 6 on the branch that takes it,
  // so `s` holds "x" -- and the flow-insensitive map cannot see that, because it
  // does not know where it is. This is the deck's p.69 verdict on a program with
  // control flow in it, which is the case the straight-line control cannot run.
  let g = @flow.cfg_of([
    pf_let(1, "a", pf_struct("A")),
    pf_assign(2, pf_field(pf_name("a"), "f"), pf_str("x")),
    pf_if(3, pf_name("cond"), [pf_let(4, "s", pf_field(pf_name("a"), "f"))]),
    pf_assign(6, pf_field(pf_name("a"), "f"), pf_str("y")),
  ])
  assert_eq(pf_last_text(g), "a -> {o1}; s -> {\"x\"}; o1.f -> {\"y\"}")
  assert_eq(
    @flow.pta_text(@flow.pta_run([g])[0]),
    "a -> {o1}; s -> {\"x\",\"y\"}; o1.f -> {\"x\",\"y\"}",
  )
}

///|
test "0550: a field pointer is named by its OBJECT, so a store through one alias is seen by the other" {
  // 1 a = new A(); 2 b = a; 3 a.f = "x"; 4 s = b.f;
  //
  // `a.f` and `b.f` are the SAME pointer, because the key is `o1.f` and not `a.f`
  // (p.97's domain). This is the property that makes the strong update of a field
  // sound: there is exactly one pointer per (object, field) pair, so the store
  // through `a` cannot be lost by the name `b`.
  let g = @flow.cfg_of([
    pf_let(1, "a", pf_struct("A")),
    pf_let(2, "b", pf_name("a")),
    pf_assign(3, pf_field(pf_name("a"), "f"), pf_str("x")),
    pf_let(4, "s", pf_field(pf_name("b"), "f")),
  ])
  assert_eq(
    pf_last_text(g),
    "a -> {o1}; b -> {o1}; s -> {\"x\"}; o1.f -> {\"x\"}",
  )
}

///|
test "0550: a loop converges, and its head keeps what entered it" {
  // 1 x = new A(); 2 while cond { 3 x = new B() }
  //
  // The loop may run zero times or many, so `x` at the exit is BOTH objects: the
  // one from line 1 and the one from line 3. The head's own map is the join of the
  // state that entered the loop and the state the body sent back, and the fixpoint
  // has to reach it rather than oscillate -- the strong update inside the body
  // REPLACES the name, so the body always says {o3} and the head is what keeps
  // both.
  let g = @flow.cfg_of([
    pf_let(1, "x", pf_struct("A")),
    pf_while(2, pf_name("cond"), [pf_assign(3, pf_name("x"), pf_struct("B"))]),
  ])
  assert_eq(pf_last_text(g), "x -> {o1,o3}")
}

///|
test "0550: the two solvers agree on the points-to map" {
  // The book says the two solvers compute the same least fixed point, and this
  // package does not take that on trust anywhere else either.
  let g = @flow.cfg_of(pf_p57_body())
  let rr = pf_round_robin(g)
  let fs = @flow.pta_run_flow_sensitive(g)
  assert_eq(rr.length(), fs.length())
  let mut i = 0
  while i < rr.length() {
    assert_eq(@flow.pta_text(rr[i]), @flow.pta_text(fs[i]))
    i = i + 1
  }
}

///|
test "0550: the flow-sensitive answer never names an object the flow-insensitive one does not" {
  // The precision claim has a soundness side: a more precise answer may be SMALLER,
  // but it may never contain an object the other reading does not have. Every
  // object the flow-sensitive map holds was put there by one of the deck's four
  // rules, so the flow-insensitive map -- which applies the same rules weakly --
  // holds it too.
  let g = @flow.cfg_of(pf_p57_body())
  let weak = @flow.pta_run([g])[0]
  let fs = @flow.pta_run_flow_sensitive(g)
  let mut i = 0
  while i < fs.length() {
    for k, s in fs[i] {
      let w = @flow.pta_of(weak, k)
      for o, _ in s {
        assert_true(w.contains(o))
      }
    }
    i = i + 1
  }
}

///|
test "0550: the points-to map lattice is a lattice" {
  let lat = @flow.pta_map_lattice()
  let elems = pf_law_maps()
  let bot = (lat.bot)()
  let mut i = 0
  while i < elems.length() {
    let x = elems[i]
    // The bottom is below everything, and joining with it changes nothing.
    assert_true(pf_pts_subset(bot, x))
    assert_true((lat.eq)((lat.join)(bot, x), x))
    let mut j = 0
    while j < elems.length() {
      let y = elems[j]
      let jxy = (lat.join)(x, y)
      let jyx = (lat.join)(y, x)
      // The join is an upper bound of both, and it does not care which way round.
      assert_true(pf_pts_subset(x, jxy))
      assert_true(pf_pts_subset(y, jxy))
      assert_true((lat.eq)(jxy, jyx))
      // It is idempotent, and `eq` agrees with the order.
      assert_true((lat.eq)((lat.join)(x, x), x))
      if pf_pts_subset(x, y) && pf_pts_subset(y, x) {
        assert_true((lat.eq)(x, y))
      }
      j = j + 1
    }
    i = i + 1
  }
}

///|
test "0550: the strong-update transfer is monotone, which is what the solver needs" {
  // The solver's fixed-point theorem needs the transfer to be monotone, and this
  // transfer is the first one in this package that REPLACES a fact instead of
  // adding one -- so the law is checked here rather than assumed for the new kind
  // of transfer. `x <= y implies step(x) <= step(y)`, for every node, over all
  // sixteen points-to maps.
  let g = @flow.cfg_of(pf_p57_body())
  let tr = @flow.pta_fs_transfer_of(g)
  let elems = pf_law_maps()
  let mut i = 0
  while i < elems.length() {
    let x = elems[i]
    let mut j = 0
    while j < elems.length() {
      let y = elems[j]
      if pf_pts_subset(x, y) {
        let mut v = 0
        while v < g.kinds.length() {
          assert_true(pf_pts_subset(tr(v, x), tr(v, y)))
          v = v + 1
        }
      }
      j = j + 1
    }
    i = i + 1
  }
}
