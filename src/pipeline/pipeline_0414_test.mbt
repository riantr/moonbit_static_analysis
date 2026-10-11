// Tests for the 0.4.14 fixes, all of them found by running the analyzer on
// four published modules that pyroduct never exercised.
//
//   A  `/` is integer division in MoonBit (`7 / 2` is 3). The analyzer typed
//      it TFloat, which produced 14 false AssignTypeMismatch findings on
//      riantr/moonbit_doubleML.
//   B  Exponent-notation float literals (`1.0e-12`) were lexed as the float
//      `1.0` followed by the name `e` — 14 `undefined name 'e'` findings.
//   D  `0.0F` (float32 literal) was lexed as `0.0` plus the name `F` — 28
//      `undefined name 'F'` findings on riantr/snn_mbt, the single largest
//      bucket found.
//   E  The value of EVERY float literal lost its fraction, because the lexer
//      sliced to a bound captured before the fraction was consumed: `1.5`
//      folded to 1. That one produced no findings at all — it made the
//      analyzer quietly wrong about every float in every file it ever read.
//
// E is the reason these tests read VALUES and TOKEN COUNTS rather than kinds.
// The pre-existing float tests asserted only "the token kind is float", which a
// truncated value satisfies perfectly.

///|
/// A — Int/Int is Int. The two shapes doubleML actually trips over: an
/// annotated local and an `Array[Int]` element, both fed by `u / v`.
test "0414: Int/Int is integer division, not a float" {
  let a = @pipeline.run(
    "fn f(u : Int, v : Int) -> Int {\n  let h : Int = u / v\n  h\n}\n",
    "x.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family_in(a, "AssignTypeMismatch", @core.LType), 0)
  let b = @pipeline.run(
    "fn f(u : Int, v : Int, xs : Array[Int], i : Int) -> Int {\n  xs[i] = u / v\n  0\n}\n",
    "x.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family_in(b, "AssignTypeMismatch", @core.LType), 0)
}

///|
/// The NEGATIVE CONTROL for A. If the division arm simply stopped reporting
/// everything, A would pass. A Float divisor really does produce a float, and
/// feeding that to an `Int` really is an error — so this must still be caught.
test "0414: a Float divisor still yields a float, and that is still an error" {
  let a = @pipeline.run(
    "fn f(u : Int, v : Float) -> Int {\n  let h : Int = u / v\n  h\n}\n",
    "x.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family_in(a, "AssignTypeMismatch", @core.LType), 1)
}

///|
/// There is deliberately NO test here for constant-folded division.
///
/// The first draft of this file had one, named "integer division folds to a
/// value", asserting that `let n = 6 / 4; if n == 1` produced no StateCheck
/// finding. Mutation proved it worthless: reverting the fold entirely — and
/// reverting the interpreter's division result type — left the suite green,
/// and a differential scan over 933 files on four corpora produced
/// byte-identical reports. The test passed because the analyzer says nothing
/// either way, so it was not testing folding; it was testing that folding is
/// unobservable. A test whose name claims more than its assertions deliver is
/// worse than no test at all, so it was deleted and the finding is recorded in
/// `walk.mbt` / `interp.mbt` instead.
///

///|
/// B — an exponent literal is one token. Before the fix, `1.0e-12` produced the
/// float `1.0` and then the name `e`, and the name had no binding.
test "0414: an exponent literal does not produce an undefined name" {
  let r = @pipeline.run(
    "fn f(x : Double, y : Double) -> Bool {\n  (x - y).abs() < 1.0e-12\n}\n",
    "x.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(r.first_error_line, 0)
  assert_eq(count_family_in(r, "UndefinedName", @core.LStructural), 0)
  assert_eq(count_family_in(r, "UndefinedName", @core.LType), 0)
}

///|
/// D — `0.0F` is one token, and must not produce an undefined name.
test "0414: an F-suffixed float literal does not produce an undefined name" {
  let r = @pipeline.run(
    "fn f() -> Float {\n  let mut acc = 0.0F\n  let d = 1.0F\n  acc = acc + d\n  acc\n}\n",
    "x.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(r.first_error_line, 0)
  assert_eq(count_family_in(r, "UndefinedName", @core.LStructural), 0)
  assert_eq(count_family_in(r, "UndefinedName", @core.LType), 0)
}

///|
/// E — the value of a float literal. Kept here as well as in the lexer unit
/// tests because this is the one whose absence produces NO finding: an analyzer
/// that folds `0.25` to 0 is wrong about every float and reports nothing. It is
/// pinned indirectly — a literal that truncates cannot equal the threshold it
/// is compared against, so the comparison must not read as a live `==`.
test "0414: a float literal keeps its fractional value" {
  let r = @pipeline.run(
    "fn f(x : Double) -> Bool {\n  x < 0.25\n}\n",
    "x.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(r.first_error_line, 0)
  assert_eq(count_family(r, "UndefinedName"), 0)
  assert_eq(count_family(r, "AssignTypeMismatch"), 0)
  // And a constant-comparison that only makes sense with a real fraction: a
  // truncated `0.25` reads as `0`, which would make `== 0.25` permanently
  // false and could be read as a dead branch.
  let dead = @pipeline.run(
    "fn f(x : Double) -> Int {\n  let c = 0.25\n  if c == 0.25 {\n    1\n  } else {\n    2\n  }\n}\n",
    "x.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(dead.first_error_line, 0)
  assert_eq(count_family_in(dead, "StateCheck", @core.LStructural), 0)
}

///|
/// The benign control that must SURVIVE everything above: code that was
/// already clean stays clean. If these started reporting, the fixes would be
/// over-broad rather than merely wrong-narrow.
test "0414: ordinary arithmetic on annotated locals stays clean" {
  let r = @pipeline.run(
    "fn f(u : Int, v : Int, xs : Array[Int], i : Int) -> Int {\n  let a : Int = u + v\n  let c : Int = u % v\n  xs[i] = u * v\n  a + c\n}\n",
    "x.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(r.first_error_line, 0)
  assert_eq(count_family_in(r, "AssignTypeMismatch", @core.LType), 0)
  assert_eq(count_family(r, "UndefinedName"), 0)
}
