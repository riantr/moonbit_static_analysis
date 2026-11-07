// Available expressions, tested on hand-built graphs.
//
// WHY HAND-BUILT. Same reason as `flow_live_test.mbt`: `flow` does not depend on
// the parser, and a test that reached for one would need a test-only import,
// which `--deny-warn` treats as an error in this toolchain.
//
// `ex`, `int_e` and `chain` are NOT redefined here: test files in one package
// share a namespace, so they already exist in `flow_live_test.mbt` and a second
// definition is a compile error rather than a local helper.

///|
/// `a + n`, the arithmetic shape the tracked universe is made of.
fn plus(a : String, n : Int32) -> @ast.Expr {
  { span: @flow.no_span(), kind: @ast.EBin(@ast.OpAdd, ex(a), int_e(n)), }
}

///|
/// A graph with explicit edges, entry 0 and exit last.
fn graph(
  kinds : Array[@flow.NodeKind],
  succ : Array[Array[Int32]],
) -> @flow.Cfg {
  let spans : Array[@core.Span] = []
  for _ in kinds {
    spans.push(@flow.no_span())
  }
  {
    kinds,
    spans,
    succ,
    pred: @flow.pred_of(succ),
    entry: 0,
    exit: kinds.length() - 1,
    skipped: 0,
  }
}

// ---------------------------------------------------------------------------
// A — the three answers a must analysis has to get right
// ---------------------------------------------------------------------------

///|
/// THE FIRST COMPUTATION IS NOT REDUNDANT AND THE SECOND ONE IS.
///
/// This single row pins BOTH ways the analysis can be silently wrong, which is
/// why it is written as one row rather than two:
///
///   * SEEDED WITH ⊥ instead of ⊤, nothing is ever available -- the intersection
///     of empty sets is empty -- so the SECOND occurrence would not be reported
///     either, and the row goes red on its first assertion;
///   * WITHOUT the entry special case, the entry node has no predecessors, its
///     input is the lattice's `bot` (now ⊤), and every expression in the program
///     is "already available" at the first statement that computes it -- so the
///     FIRST occurrence would be reported, and the row goes red on its second.
///
/// The two failure modes are opposite and neither is visible from the outside:
/// one finds nothing, the other finds everything.
test "0544: the first computation is live and the second is redundant" {
  let g = chain([
    @flow.Entry,
    @flow.Assign("a", int_e(1)),
    @flow.Assign("b", plus("a", 1)),
    @flow.Assign("c", plus("a", 1)),
    @flow.Exit,
  ])
  let rs = @flow.avail_redundant(g)
  assert_eq(rs.length(), 1)
  // the SECOND one, i.e. the node computing `c`, not the one computing `b`
  assert_eq(rs[0].node, 3)
  assert_eq(rs[0].key, "a + 1")
}

///|
/// A WRITE TO AN OPERAND KILLS THE EXPRESSION. `a` is reassigned between the two
/// computations of `a + 1`, so the second one is a different value and must not
/// be reported.
///
/// This is the `(IN − kill)` half of `OUT = gen ∪ (IN − kill)`; without it the
/// analysis would claim a value is available across a redefinition, which is the
/// classic unsound mistake for this analysis and produces a finding on perfectly
/// ordinary code.
test "0543/0544: a write to an operand kills the expression" {
  let g = chain([
    @flow.Entry,
    @flow.Assign("a", int_e(1)),
    @flow.Assign("b", plus("a", 1)),
    @flow.Assign("a", int_e(2)),
    @flow.Assign("c", plus("a", 1)),
    @flow.Exit,
  ])
  assert_eq(@flow.avail_redundant(g).length(), 0)
}

///|
/// `x = x + 1` IS NOT A REDUNDANT RECOMPUTATION even when `x + 1` was available
/// before it, because the node DEFINES `x`.
///
/// The condition that keeps it out is `key ∉ kill(v)` in `avail_redundant`, and
/// it is the one place where "available before" and "recomputed here" are not
/// enough: the store is precisely what makes the new value different.
test "0544: a store that redefines an operand is not redundant" {
  let g = chain([
    @flow.Entry,
    @flow.Assign("x", int_e(1)),
    @flow.Assign("b", plus("x", 1)),
    @flow.Assign("x", plus("x", 1)),
    @flow.Exit,
  ])
  assert_eq(@flow.avail_redundant(g).length(), 0)
}

// ---------------------------------------------------------------------------
// B — the MUST direction: one path without the computation is enough
// ---------------------------------------------------------------------------

///|
/// A DIAMOND WHERE ONLY ONE SIDE COMPUTES IT IS NOT AVAILABLE AT THE JOIN.
///
/// `IN[join] = OUT[left] ∩ OUT[right]`, and the right side never computed
/// `a + 1`, so the intersection is empty and the join's own computation is live.
/// A may analysis would report it; this one must not.
test "0544: an expression computed on one branch only is not available at the join" {
  let g = graph(
    [
      @flow.Entry,
      @flow.Test(ex("c")),
      @flow.Assign("b", plus("a", 1)),
      @flow.Assign("b", int_e(0)),
      @flow.Assign("d", plus("a", 1)),
      @flow.Exit,
    ],
    [[1], [2, 3], [4], [4], [5], []],
  )
  assert_eq(@flow.avail_redundant(g).length(), 0)
}

///|
/// AND ITS CONTROL: the SAME diamond with the computation on BOTH sides IS
/// available at the join, so the join's copy is redundant.
///
/// The two rows differ in one statement and give opposite answers, which is what
/// makes the previous row a measurement of the meet rather than a fixture that
/// happened to be quiet.
test "0544: an expression computed on both branches is available at the join" {
  let g = graph(
    [
      @flow.Entry,
      @flow.Test(ex("c")),
      @flow.Assign("b", plus("a", 1)),
      @flow.Assign("b", plus("a", 1)),
      @flow.Assign("d", plus("a", 1)),
      @flow.Exit,
    ],
    [[1], [2, 3], [4], [4], [5], []],
  )
  let rs = @flow.avail_redundant(g)
  assert_eq(rs.length(), 1)
  assert_eq(rs[0].node, 4)
}

///|
/// A LOOP HEAD READS THE MEET OF ITS PREDECESSORS, and the back edge is one of
/// them. With no computation before the loop, the FIRST iteration reaches the
/// body without having computed `a + 1`, so the body's copy is live.
test "0544: a loop body's computation is live when nothing computed it first" {
  let g = graph(
    [
      @flow.Entry,
      @flow.Test(ex("c")),
      @flow.Assign("b", plus("a", 1)),
      @flow.Exit,
    ],
    [[1], [2, 3], [1], []],
  )
  assert_eq(@flow.avail_redundant(g).length(), 0)
}

///|
/// THE CONTROL: with a PREHEADER that computes it, both paths into the loop head
/// carry it -- the entry edge and the back edge -- so the body's copy IS
/// redundant. This is the same pair as the diamond above, one level up, and it
/// pins that the meet is taken over predecessors rather than over the entry path
/// alone.
test "0544: a loop body's computation is redundant when a preheader computed it" {
  let g = graph(
    [
      @flow.Entry,
      @flow.Assign("z", plus("a", 1)),
      @flow.Test(ex("c")),
      @flow.Assign("b", plus("a", 1)),
      @flow.Exit,
    ],
    [[1], [2], [3, 4], [2], []],
  )
  let rs = @flow.avail_redundant(g)
  assert_eq(rs.length(), 1)
  assert_eq(rs[0].node, 3)
}

// ---------------------------------------------------------------------------
// C — the universe is bounded on purpose
// ---------------------------------------------------------------------------

///|
/// A CALL IS NOT IN THE UNIVERSE, and neither is its result. `f(a) + f(a)` is
/// two calls; this deck's own scope note (p.38, "Issues Not Covered") excludes
/// method calls, and an analysis that folded two calls into one would be
/// claiming a pure function in a language that does not have that annotation.
test "0544: a call is not a tracked expression" {
  let call : @ast.Expr = {
    span: @flow.no_span(),
    kind: @ast.ECall("f", [ex("a")], []),
  }
  assert_eq(@flow.avail_key(call), None)
  let g = chain([
    @flow.Entry,
    @flow.Assign("p", call),
    @flow.Assign("q", call),
    @flow.Exit,
  ])
  assert_eq(@flow.avail_redundant(g).length(), 0)
}

///|
/// TWO ATOM OPERANDS MAKE A KEY, and the key names the operator, so `a + 1` and
/// `a - 1` are different expressions rather than the same one.
test "0544: keys name the operator and are canonical" {
  let add = plus("a", 1)
  let sub : @ast.Expr = {
    span: @flow.no_span(),
    kind: @ast.EBin(@ast.OpSub, ex("a"), int_e(1)),
  }
  assert_true(@flow.avail_key(add) == Some("a + 1"))
  assert_true(@flow.avail_key(sub) == Some("a - 1"))
  // a non-atom operand is not in the universe
  let nested : @ast.Expr = {
    span: @flow.no_span(),
    kind: @ast.EBin(@ast.OpAdd, add, ex("b")),
  }
  assert_eq(@flow.avail_key(nested), None)
}
