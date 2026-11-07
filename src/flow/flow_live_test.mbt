// Live variables, tested on hand-built graphs.
//
// WHY HAND-BUILT AND NOT PARSED. The package now carries source positions on
// every node, so `@core` is a real dependency and a test can build an `Expr`
// without reaching for the parser -- which is what the toolchain's
// `--deny-warn` treatment of test-only imports forces (measured; see 0526 and
// 0527). The graphs below are small on purpose: a liveness test should fail on
// the ANALYSIS, not on a fifteen-statement fixture whose shape nobody re-derives.

///|
fn ex(n : String) -> @ast.Expr {
  { span: @flow.no_span(), kind: @ast.EName(n), }
}

///|
/// An expression that READS one name without needing an operator table: a list
/// literal of one element. Using `EBin` here would pin a `BOp` constructor this
/// test has no opinion about.
fn reads(n : String) -> @ast.Expr {
  { span: @flow.no_span(), kind: @ast.EList([ex(n)]), }
}

///|
fn int_e(i : Int32) -> @ast.Expr {
  { span: @flow.no_span(), kind: @ast.EInt(i), }
}

///|
/// A graph over the given nodes in a straight line, with an entry at 0 and an
/// exit last.
fn chain(kinds : Array[@flow.NodeKind]) -> @flow.Cfg {
  let n = kinds.length()
  let succ : Array[Array[Int32]] = []
  let spans : Array[@core.Span] = []
  let mut i = 0
  while i < n {
    spans.push(@flow.no_span())
    if i + 1 < n {
      succ.push([i + 1])
    } else {
      succ.push([])
    }
    i = i + 1
  }
  {
    kinds,
    spans,
    succ,
    pred: @flow.pred_of(succ),
    entry: 0,
    exit: n - 1,
    skipped: 0,
  }
}

///|
test "flow/0527: a store nobody reads is not live after itself" {
  // entry -> z = 1 -> y = [x] -> exit
  let g = chain([
    @flow.Entry,
    @flow.Assign("z", int_e(1)),
    @flow.Assign("y", reads("x")),
    @flow.Exit,
  ])
  let ins = @flow.live_in(g)
  let outs = @flow.live_out(g, ins)
  // `x` is live before the statement that reads it.
  assert_true(ins[2].contains("x"))
  // `z` is NOT live after its own store: nothing downstream mentions it.
  assert_false(outs[1].contains("z"))
  // And the store's own in-set cannot answer the question, because the transfer
  // removes the definition: this is the distinction `live_out` exists for.
  assert_false(ins[1].contains("z"))
}

///|
test "flow/0527: a store whose value IS read stays live" {
  // entry -> x = 1 -> y = [x] -> exit
  let g = chain([
    @flow.Entry,
    @flow.Assign("x", int_e(1)),
    @flow.Assign("y", reads("x")),
    @flow.Exit,
  ])
  let outs = @flow.live_out(g, @flow.live_in(g))
  assert_true(outs[1].contains("x"))
  // `y` is stored and never read, so THAT one is dead in the same program --
  // a liveness answer that called everything live would be useless, not safe.
  assert_false(outs[2].contains("y"))
}

///|
/// The entry node carries the names the body reads before defining them, which
/// is where a parameter's liveness comes from.
test "flow/0527: the entry node reports a name read before it is defined" {
  let g = chain([
    @flow.Entry,
    @flow.Assign("x", reads("p")),
    @flow.Assign("q", int_e(0)),
    @flow.Exit,
  ])
  let ins = @flow.live_in(g)
  assert_true(ins[0].contains("p"))
  assert_false(ins[0].contains("q"))
}

///|
/// A back edge makes a value live around the loop: the store's value is read by
/// the NEXT iteration, so it is live after the store even though the reading
/// statement comes earlier in the source.
test "flow/0527: a back edge keeps a store live" {
  // 0 entry -> 1 test -> 2 store(n) -> 3 read(n) -> 1 (back edge)
  //                       \-> 4 exit
  let kinds : Array[@flow.NodeKind] = [
    @flow.Entry,
    @flow.Test(reads("c")),
    @flow.Assign("n", int_e(1)),
    @flow.Assign("y", reads("n")),
    @flow.Exit,
  ]
  let succ : Array[Array[Int32]] = [[1], [2, 4], [3], [1], []]
  let spans : Array[@core.Span] = [
    @flow.no_span(),
    @flow.no_span(),
    @flow.no_span(),
    @flow.no_span(),
    @flow.no_span(),
  ]
  let g : @flow.Cfg = {
    kinds,
    spans,
    succ,
    pred: @flow.pred_of(succ),
    entry: 0,
    exit: 4,
    skipped: 0,
  }
  let outs = @flow.live_out(g, @flow.live_in(g))
  // node 2 stores `n`; the read at node 3 is reachable from it, so it is live.
  assert_true(outs[2].contains("n"))
}

///|
/// `node_defs` / `node_uses` are the transfer's two halves and are pinned
/// separately, because a transfer that swapped them would still look plausible.
test "flow/0527: defs and uses are named per node kind" {
  let d = @flow.node_defs(@flow.Assign("x", reads("y")))
  assert_true(d.contains("x"))
  assert_false(d.contains("y"))
  let u = @flow.node_uses(@flow.Assign("x", reads("y")))
  assert_true(u.contains("y"))
  assert_false(u.contains("x"))
  // A place-store kills only its base name, and an expression node kills nothing.
  assert_false(@flow.node_defs(@flow.Eval(reads("y"))).contains("y"))
}
