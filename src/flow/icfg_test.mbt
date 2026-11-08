// 0546: the interprocedural graph's own shape.
//
// THE DECK'S PROGRAM, BUILT AS `@flow.IFn` VALUES. `Interprocedural Analysis`
// (Tian Tan, Nanjing University, 2021) p.78 prints one program and then uses it
// for every figure in its fourth section:
//
//     static void main() { int a, b, c;
//       a = 6;  b = addOne(a);  c = b - 3;  b = ten();  c = a * b; }
//     static int addOne(int x) { int y = x + 1; return y; }
//     static int ten() { return 10; }
//
// THE FIXTURES ARE BUILT FROM AST VALUES RATHER THAN PARSED, because this package
// imports `ast` and nothing else on purpose (see `flow_cfg_test.mbt`: `--deny-warn`
// counts a test-only import as an error, measured rather than assumed). So the
// source above appears here as the statements it parses to, and the deck's
// numbers are asserted against those.

///|
/// `let name = e`
fn cp_let(name : String, e : @ast.Expr) -> @ast.Stmt {
  { span: @flow.no_span(), kind: @ast.SLet(name, "", e), }
}

///|
/// `name = e`
fn cp_assign(name : String, e : @ast.Expr) -> @ast.Stmt {
  { span: @flow.no_span(), kind: @ast.SAssign(ex(name), e), }
}

///|
/// `return e`
fn cp_ret(e : @ast.Expr) -> @ast.Stmt {
  { span: @flow.no_span(), kind: @ast.SReturn(Some(e)), }
}

///|
/// `f(args)`
fn cp_call(f : String, args : Array[@ast.Expr]) -> @ast.Expr {
  { span: @flow.no_span(), kind: @ast.ECall(f, args, []), }
}

///|
/// `a + b`
fn cp_add(a : @ast.Expr, b : @ast.Expr) -> @ast.Expr {
  { span: @flow.no_span(), kind: @ast.EBin(@ast.OpAdd, a, b), }
}

///|
/// `a - b`
fn cp_sub(a : @ast.Expr, b : @ast.Expr) -> @ast.Expr {
  { span: @flow.no_span(), kind: @ast.EBin(@ast.OpSub, a, b), }
}

///|
/// `a * b`
fn cp_mul(a : @ast.Expr, b : @ast.Expr) -> @ast.Expr {
  { span: @flow.no_span(), kind: @ast.EBin(@ast.OpMul, a, b), }
}

///|
/// The three functions of the deck's program, in the order the deck prints them:
/// `main` is 0, `addOne` is 1, `ten` is 2.
fn deck_program() -> Array[@flow.IFn] {
  [
    {
      name: "main",
      params: [],
      body: [
        cp_let("a", int_e(6)),
        cp_let("b", cp_call("addOne", [ex("a")])),
        cp_let("c", cp_sub(ex("b"), int_e(3))),
        cp_assign("b", cp_call("ten", [])),
        cp_assign("c", cp_mul(ex("a"), ex("b"))),
      ],
    },
    {
      name: "addOne",
      params: ["x"],
      body: [cp_let("y", cp_add(ex("x"), int_e(1))), cp_ret(ex("y"))],
    },
    { name: "ten", params: [], body: [cp_ret(int_e(10))], },
  ]
}

///|
/// The flat index of the `nth` node in function `f` that writes `name`, COUNTED IN
/// SOURCE ORDER.
///
/// NODE INDICES ARE ALLOCATION ORDER AND THAT IS THE REVERSE OF SOURCE ORDER:
/// `cfg_of` builds a statement list back to front (`build_seq`), so the last
/// statement of a body has the LOWEST index. A helper that counted in node order
/// would answer the deck's `c = b - 3` when the test asked for `c = a * b`, and
/// the two failures this helper produced the first time it was written are the
/// reason the reversal is here rather than at every call site.
fn cp_store_node(
  g : @flow.Icfg,
  f : Int32,
  name : String,
  nth : Int32,
) -> Int32 {
  let hits : Array[Int32] = []
  let mut v = 0
  while v < g.kinds.length() {
    if g.fn_of[v] == f {
      let hit = match g.kinds[v] {
        @flow.Assign(x, _) => x == name
        @flow.Store(x, _) => x == name
        _ => false
      }
      if hit {
        hits.push(v)
      }
    }
    v = v + 1
  }
  hits[hits.length() - 1 - nth]
}

///|
/// The flat index of the `nth` call site in function `f`, in SOURCE order for the
/// same reason.
fn cp_call_node(g : @flow.Icfg, f : Int32, nth : Int32) -> Int32 {
  let hits : Array[Int32] = []
  let mut i = 0
  while i < g.call_sites.length() {
    if g.call_sites[i].caller == f {
      hits.push(g.call_sites[i].node)
    }
    i = i + 1
  }
  hits[hits.length() - 1 - nth]
}

///|
/// The node a call site's call-to-return edge goes to -- the deck's RETURN SITE.
fn cp_return_site(g : @flow.Icfg, call : Int32) -> Int32 {
  let mut k = 0
  let mut found = -1
  while k < g.succ[call].length() {
    match g.labels[call][k] {
      @flow.CallToReturn(_) => found = g.succ[call][k]
      _ => ()
    }
    k = k + 1
  }
  found
}

///|
/// How many edges of a given shape leave `v`? The label vocabulary is what a
/// reader of a dump reads, so the counts are pinned rather than the labels
/// alone.
fn cp_count_label(g : @flow.Icfg, v : Int32, want : Int32) -> Int32 {
  let mut k = 0
  let mut n = 0
  while k < g.succ[v].length() {
    let hit = match g.labels[v][k] {
      @flow.Normal => want == 0
      @flow.CallToReturn(_) => want == 1
      @flow.Call(_, _) => want == 2
      @flow.Ret(_, _) => want == 3
    }
    if hit {
      n = n + 1
    }
    k = k + 1
  }
  n
}

// ---------------------------------------------------------------------------
// A -- the graph the deck draws (p.77-81)
// ---------------------------------------------------------------------------

///|
/// TWO CALL SITES IN `main`, AND EACH PUTS THREE EDGE KINDS ON THE GRAPH.
///
/// The counts are the assertion, because "the ICFG is CFGs plus call and return
/// edges" is a sentence about edges and nothing else. A call node has NO ordinary
/// successor -- p.81: "such edges (from call site to return site) are called
/// call-to-return edges" -- so `Normal` must be ZERO out of it.
test "0546: a call site has a call edge, a call-to-return edge and no normal edge" {
  let g = @flow.icfg_of(deck_program())
  assert_eq(g.unresolved, 0)
  assert_eq(g.call_sites.length(), 2)
  let c0 = cp_call_node(g, 0, 0)
  let c1 = cp_call_node(g, 0, 1)
  assert_true(c0 >= 0)
  assert_true(c1 >= 0)
  // call-to-return + call, and nothing else
  assert_eq(cp_count_label(g, c0, 0), 0)
  assert_eq(cp_count_label(g, c0, 1), 1)
  assert_eq(cp_count_label(g, c0, 2), 1)
  assert_eq(cp_count_label(g, c1, 0), 0)
  assert_eq(cp_count_label(g, c1, 1), 1)
  assert_eq(cp_count_label(g, c1, 2), 1)
}

///|
/// THE RETURN EDGE LEAVES FROM THE VALUE NODE, NOT FROM `Exit`.
///
/// `cfg.mbt` gives `return e` the shape `Eval(e) -> Stop`, and `Stop` has no
/// successors, so a body that ends in `return` never reaches its own `Exit`.
/// Both callees here are of that shape, which is why each contributes exactly one
/// return edge and why `fallthrough` is false for them: a graph that claimed a
/// return edge out of an unreachable `Exit` would be claiming an edge no path can
/// take.
test "0546: the return edge leaves the value node, and neither callee falls through" {
  let g = @flow.icfg_of(deck_program())
  assert_false(g.fallthrough[1])
  assert_false(g.fallthrough[2])
  assert_eq(g.declined[1], false)
  assert_eq(g.declined[2], false)
  let c0 = cp_call_node(g, 0, 0)
  let site = cp_return_site(g, c0)
  // exactly two edges arrive at the first return site: the call-to-return one and
  // the return edge from addOne's `return y`
  assert_eq(g.pred[site].length(), 2)
}

///|
/// `pred` IS DERIVED FROM `succ`, AND IT STILL IS AFTER THE INTERPROCEDURAL EDGES
/// ARE ADDED. `pred_of`'s own docstring says it is public because "a graph that a
/// caller assembles (an interprocedural one, in a later increment) needs the same
/// derivation" -- this row is that sentence's check.
test "0546: pred is the exact inverse of succ on the interprocedural graph" {
  let g = @flow.icfg_of(deck_program())
  let mut v = 0
  while v < g.succ.length() {
    let mut k = 0
    while k < g.succ[v].length() {
      let s = g.succ[v][k]
      assert_true(g.pred[s].contains(v))
      k = k + 1
    }
    v = v + 1
  }
  // every label array is index-parallel with its succ array
  let mut u = 0
  while u < g.labels.length() {
    assert_eq(g.labels[u].length(), g.succ[u].length())
    u = u + 1
  }
}

///|
/// A CALL TO A NAME THAT IS NOT DECLARED IS COUNTED, NOT CONNECTED.
///
/// The deck's call graph is built from a worklist over methods that EXIST; a name
/// with no declaration is a call this graph cannot resolve, and connecting it to
/// nothing while saying nothing is how an analysis ends up claiming precision it
/// does not have.
test "0546: an unresolved callee is counted and gets no interprocedural edge" {
  let fns : Array[@flow.IFn] = [
    {
      name: "main",
      params: [],
      body: [
        cp_let("b", cp_call("nowhere", [])),
        cp_assign("b", cp_add(ex("b"), int_e(1))),
      ],
    },
  ]
  let g = @flow.icfg_of(fns)
  assert_eq(g.unresolved, 1)
  assert_eq(g.call_sites.length(), 0)
  // the call node keeps its ORDINARY edge, because there is no return site to
  // name and no callee to call
  let c = cp_store_node(g, 0, "b", 0)
  assert_eq(cp_count_label(g, c, 0), 1)
}

///|
/// A CALLEE THAT RAISES WITH A PAYLOAD IS DECLINED, because `cfg.mbt` gives
/// `return e` and `raise e` the same shape and this graph cannot tell them apart.
/// The decline is a COUNT on the graph, not a silent assumption.
test "0546: a callee that raises with a payload is declined" {
  let fns : Array[@flow.IFn] = [
    { name: "main", params: [], body: [cp_let("b", cp_call("boom", []))], },
    {
      name: "boom",
      params: [],
      body: [{ span: @flow.no_span(), kind: @ast.SRaise(Some(ex("x"))), }],
    },
  ]
  let g = @flow.icfg_of(fns)
  assert_eq(g.declined[1], true)
  // the call is still connected -- the value it returns is what is declined -- so
  // the return edge carries Ret(None, ...) rather than a returned expression
  assert_eq(g.call_sites.length(), 1)
  let c = cp_call_node(g, 0, 0)
  assert_eq(cp_count_label(g, c, 2), 1)
}
