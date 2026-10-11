// Tests for the 0.4.13 fixes: the last five actionable findings on
// riantr/pyroduct 0.1.29, plus the three collateral changes that making the
// type lens read `Array[T]` forced.
//
// Five findings, three shapes, each settled with a toolchain probe before a
// line of analyzer changed. pyroduct actionable 5 -> 0. The number that matters
// more than the 0 is that the two REAL list-index errors this check used to
// catch are still caught — see "subscript" below.

///|
/// THE control for the subscript fix. A `Map` is indexed by its KEY, so a
/// `String` index on it is correct code, and reporting it as "list indices must
/// be int" put an `error:`-severity finding on a file `moon check` accepts.
/// Measured: 2 of the 5 (pyroduct `src/paths.mbt`, `color[u] = 1` and
/// `color[u] = 2` with `color : Map[String, Int]`).
test "subscript: a Map indexed by its key is not a list-index error" {
  let r = @pipeline.run(
    "fn h(m : Map[String, Int]) -> Int {\n  m[\"k\"]\n}\n",
    "x.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(r.first_error_line, 0)
  assert_eq(count_family_in(r, "OperatorMismatch", @core.LType), 0)
}

///|
/// The direction that matters most. Narrowing a check's precondition is only
/// legitimate if the cases it USED to catch are still caught — and at the moment
/// of writing they were NOT, because `Array[T]` did not read as a list and the
/// gate could never fire. Both of these are `moon check` "Expr Type Mismatch".
test "subscript: a real Array indexed by a String IS still an error" {
  let a = @pipeline.run(
    "fn h(xs : Array[String]) -> String {\n  xs[\"k\"]\n}\n",
    "x.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(a.first_error_line, 0)
  assert_eq(count_family_in(a, "OperatorMismatch", @core.LType), 1)
  let b = @pipeline.run(
    "fn h(xs : Array[Int]) -> Int {\n  xs[\"k\"]\n}\n",
    "x.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family_in(b, "OperatorMismatch", @core.LType), 1)
}

///|
/// The other half of "still caught": an int index on a list is fine and must
/// stay silent. A gate that fired on every subscript would pass the test above.
test "subscript: an int index on a list reports nothing" {
  let r = @pipeline.run(
    "fn h(xs : Array[String]) -> String {\n  xs[0]\n}\n",
    "x.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family_in(r, "OperatorMismatch", @core.LType), 0)
  assert_eq(r.first_error_line, 0)
}

///|
/// `Array[T]` must reach the lens as a list, and the bracket group must survive
/// the parser — `type_annotation` used to DISCARD it via `skip_indexed`, so
/// `Array[String]` arrived as bare `"Array"`. Two real errors went silent when
/// the subscript check was gated on a TList that nothing produced. This is the
/// test that would have caught that.
test "subscript: the Array argument survives parsing, nested too" {
  let ok = @pipeline.run(
    "fn h(xs : Array[Array[Int]]) -> Int {\n  xs[0][0]\n}\n",
    "x.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(ok.first_error_line, 0)
  assert_eq(count_family_in(ok, "OperatorMismatch", @core.LType), 0)
  let bad = @pipeline.run(
    "fn h(xs : Array[Array[Int]]) -> Int {\n  xs[\"k\"]\n}\n",
    "x.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family_in(bad, "OperatorMismatch", @core.LType), 1)
}

///|
/// `[T]` is NOT valid MoonBit in a `.mbt` signature — `fn h(xs : [String])` is
/// a parse error in the toolchain, so this form never reaches `ann_to_ty` from
/// a source file and an end-to-end assertion here would be asserting something
/// unreachable. The reader still accepts it as tolerance for `.mbti` text and
/// hand-written samples, and THAT is asserted at the unit level in
/// `src/types/types_test.mbt` ("the bracket spelling is still a list").
///
/// What this pins instead is the reachable half: a valid `Array` spelling is
/// read as a list end to end, on both a parameter and a `let`.
test "subscript: the Array spelling is read as a list on a param and a let" {
  let param = @pipeline.run(
    "fn h(xs : Array[String]) -> String {\n  let _ = xs\n  xs[\"k\"]\n}\n",
    "x.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(param.first_error_line, 0)
  assert_eq(count_family_in(param, "OperatorMismatch", @core.LType), 1)
  let loc = @pipeline.run(
    "fn h() -> String {\n  let xs : Array[String] = [\"a\"]\n  xs[\"k\"]\n}\n",
    "x.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(loc.first_error_line, 0)
  assert_eq(count_family_in(loc, "OperatorMismatch", @core.LType), 1)
}

///|
/// An empty literal carries no element type, so it must not produce a
/// mismatch: `let mut xs : Array[String] = []` is the ordinary way to start
/// such a list, and it is correct code. Reaching `Array[T]` at all — the parser
/// used to DISCARD the `[...]` — made this a live false positive: 3 on this
/// repo's own source and 50 on pyroproduct.
///
/// The mechanism is `ty_assignable` recursing into `TList`, so
/// `TList(TUnknown)` is assignable to `TList(TStr)`. An earlier version of the
/// fix ALSO made the empty literal adopt its hint; that branch was measured to
/// be UNOBSERVABLE — muting it left the finding stream byte-identical on both
/// corpora (496 and 528 findings) and no test could kill it — so it was
/// removed. A guard no test can fail and no corpus can distinguish is untested
/// code that looks like a decision.
///
/// The `mut` is load-bearing, and that was its own lesson: written as a plain
/// `let` this test passed even with the assignability fix REMOVED, because a
/// plain `let` is an `SLet` and never runs the assignment check at all — so the
/// test proved nothing while looking as though it did. Every real finding was on
/// a `let mut`, which binds and then assigns.
test "an empty list literal does not mismatch its annotated element type" {
  let r = @pipeline.run(
    "fn h() -> Unit {\n  let mut xs : Array[String] = []\n  let _ = xs\n}\n",
    "x.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(r.first_error_line, 0)
  assert_eq(count_family(r, "AssignTypeMismatch"), 0)
}

///|
/// The negative control for the rule above: a NON-empty literal of the wrong
/// element type is a real mismatch and must still report. Without this, "an
/// empty list adopts the hint" and "no assignment check ever runs" are
/// indistinguishable from outside.
test "a non-empty list of the wrong element type still reports" {
  let r = @pipeline.run(
    "fn h() -> Unit {\n  let xs : Array[String] = [1]\n  let _ = xs\n}\n",
    "x.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(r.first_error_line, 0)
  assert_eq(count_family(r, "AssignTypeMismatch"), 1)
}

///|
/// `TList(TUnknown)` must be assignable to `TList(TStr)`, because the lattice
/// already says an Unknown is assignable to anything — and a list holding an
/// unknown element must not defeat that rule one level down.
test "ty_assignable: an unknown element is assignable to any element" {
  assert_true(
    @types.ty_assignable(
      @types.TList(@types.TUnknown),
      @types.TList(@types.TStr),
    ),
  )
  assert_true(
    @types.ty_assignable(@types.TList(@types.TInt), @types.TList(@types.TInt)),
  )
  assert_false(
    @types.ty_assignable(@types.TList(@types.TInt), @types.TList(@types.TStr)),
  )
  assert_false(@types.ty_assignable(@types.TInt, @types.TList(@types.TStr)))
}

///|
/// `self` is a CONVENTIONAL PARAMETER NAME, not a keyword. Listing it as one
/// meant `\{self.designation()}` recorded no read, so a parameter read only
/// inside an interpolation was reported as never used — measured at pyroduct
/// `src/slot.mbt` 127:24, while the SAME read outside an interpolation was
/// already silent. Both directions are pinned here, because the bug was
/// precisely that the two paths disagreed with each other.
test "a parameter read only inside an interpolation counts as used" {
  let inside = @pipeline.run(
    "pub fn Slot::q(self : Slot) -> String {\n  \"\\{self.tag}\"\n}\n",
    "x.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(inside, "UnusedParam"), 0)
  let outside = @pipeline.run(
    "pub fn Slot::q(self : Slot) -> String {\n  let a = self.tag\n  a\n}\n",
    "x.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(outside, "UnusedParam"), 0)
}

///|
/// The control for the `self` fix: dropping it from the keyword list must not
/// turn an interpolation reference into an UNDEFINED name, and a parameter that
/// really is never touched must still be reported.
test "self: an unknown inside an interpolation is still undefined" {
  let r = @pipeline.run(
    "pub fn q(self : Slot) -> String {\n  \"\\{nosuchname}\"\n}\n",
    "x.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "UndefinedName"), 1)
  let unused = @pipeline.run(
    "pub fn q(self : Slot) -> String {\n  let a = 1\n  \"\\{a}\"\n}\n",
    "x.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(unused, "UnusedParam"), 1)
}

///|
/// The bare `_` keeps working alongside the prefix, and `_` is still exempt.
test "the bare underscore binder is still exempt" {
  let lc = @pipeline.run(
    "fn g() -> Unit {\n  let _ = 1\n}\n",
    "x.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(lc, "UnusedLocal"), 0)
  let param = @pipeline.run(
    "fn g(_ : Int) -> Bool {\n  false\n}\n",
    "x.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(param, "UnusedParam"), 0)
}

///|
/// A `_`-PREFIXED name is the language's own discard convention. Probe: with
/// `_f` / `_classes` / `_ok3` and a non-underscore `plain` control in ONE file,
/// `moon check` warns on `plain` and on nothing else. Measured: 2 of the 5
/// (pyroduct `_classes` in `src/algebra.mbt`, `_f` in `audit/mbti.mbt`).
test "an underscore-prefixed unused binding or parameter is exempt" {
  let lc = @pipeline.run(
    "fn refine() -> (Int, Int) {\n  (1, 2)\n}\n\nfn f() -> Bool {\n  let (count, _classes) = refine()\n  count == 1\n}\n",
    "x.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(lc, "UnusedLocal"), 0)
  let param = @pipeline.run(
    "fn g(_f : Int) -> Bool {\n  false\n}\n",
    "x.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(param, "UnusedParam"), 0)
}

///|
/// The control that makes the exemption non-vacuous. Exempting every name, or
/// exempting on something other than the prefix, would pass the test above.
test "a non-underscore unused binding and parameter are still reported" {
  let lc = @pipeline.run(
    "fn f() -> Int {\n  let dead = 1\n  let live = 2\n  live\n}\n",
    "x.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(lc, "UnusedLocal"), 1)
  let param = @pipeline.run(
    "fn g(plain : Int) -> Bool {\n  false\n}\n",
    "x.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(param, "UnusedParam"), 1)
}

///|
/// `FParamChanged` is a different question from "was it read", so the discard
/// exemption must not silence it: an underscore-prefixed parameter that is
/// ASSIGNED is still being mutated.
test "an underscore-prefixed parameter changed by assignment still reports" {
  let r = @pipeline.run(
    "fn g(_f : Int) -> Int {\n  _f = 1\n  _f\n}\n",
    "x.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "ParamChanged"), 1)
}
