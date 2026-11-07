// The graph's own invariants, tested on payload-free nodes.
//
// WHY NOT A PARSED PROGRAM HERE. This package imports `ast` and nothing else,
// on purpose: the framework is below the frontend, and `--deny-warn` in this
// toolchain treats a test-only import as an ERROR (`unused_package`), which was
// measured rather than assumed. So the tests here cover what needs no AST -- the
// graph's inverse-edge invariant and the dump -- while the BUILDER's tests
// belong to the package that owns the parse-to-graph path (`pipeline`), which
// already imports the parser and drives this one from increment 2 onward. That
// split is recorded rather than glossed: `build_one` has no test in this
// package, and this comment is where a reader finds that out.

///|
/// A three-node straight line: entry -> stop -> exit. All three kinds carry no
/// payload, so the test needs no expression and therefore no `core` span.
fn line() -> @flow.Cfg {
  let succ : Array[Array[Int32]] = [[1], [2], []]
  {
    kinds: [@flow.Entry, @flow.Stop, @flow.Exit],
    succ,
    pred: @flow.pred_of(succ),
    entry: 0,
    exit: 2,
    skipped: 0,
  }
}

///|
test "flow/0526: pred is the exact inverse of succ" {
  let g = line()
  assert_eq(g.pred[0].length(), 0)
  assert_eq(g.pred[1], [0])
  assert_eq(g.pred[2], [1])
}

///|
/// A node with TWO predecessors gets both, in the order the edges were added.
/// Live variables (§5.4) walks `pred` backwards and a dropped edge there is a
/// missed read, so the merge case is pinned separately from the chain.
test "flow/0526: pred collects every incoming edge of a merge node" {
  let succ : Array[Array[Int32]] = [[1, 2], [3], [3], []]
  let pred = @flow.pred_of(succ)
  assert_eq(pred[3], [1, 2])
}

///|
test "flow/0526: the dump counts nodes and names the entry and the exit" {
  let g = line()
  let d = g.dump()
  assert_true(d.has_prefix("cfg: 3 nodes, entry=0, exit=2"))
  // `skipped` only appears when it is non-zero, so a clean graph's dump does
  // not carry a "skipped=0" that a reader would have to interpret. The count
  // itself is the assertion here; the formatting of the line is pinned by
  // `skipped=1` in the increment that adds a skipped statement.
  assert_eq(g.skipped, 0)
}

///|
/// The label vocabulary, pinned: it is what a reader of a dump reads.
test "flow/0526: kind_label names the three payload-free kinds" {
  let g = line()
  assert_true(g.kind_label(0) == "entry")
  assert_true(g.kind_label(1) == "stop")
  assert_true(g.kind_label(2) == "exit")
}
