// Tests for the 0.4.22 annotation reader.
//
// `ann_to_ty` is the one function that decides whether a written type means
// anything at all to the type lens, and it is a total function over strings it
// has never seen: anything unrecognised becomes Unknown, and Unknown silences
// every check downstream of it. That failure is invisible in the findings —
// it looks exactly like a file with no problems.
//
// So the tests here are not only "X reads as Y". Each one has a reverse
// control, because mapping a new annotation onto an existing `Ty` is only
// correct if the two are interchangeable; mapping it onto Unknown is always
// SAFE and always WRONG, and nothing in the output distinguishes them except a
// count that is expected to be non-zero.
// `ty_is` is the `Eq`-without-`Debug` comparison helper declared in
// types_test.mbt. Test files in a package share ONE top-level namespace, so it
// is used rather than redeclared — which is also why the earlier version of
// this comment, claiming the opposite, was wrong.

///|
/// 0.1.20261012 renamed the default integer type to `Int32`. Settled against
/// `moon check` on that version: an `Int` value is accepted by an `Int32`
/// parameter and an `Int32` value is accepted by an `Int` parameter, in BOTH
/// directions. A synonym, not a subtype — which is what makes folding it into
/// `TInt` correct rather than merely convenient.
test "0422: ann_to_ty reads Int32 as Int" {
  assert_true(ty_is(@types.ann_to_ty("Int32"), @types.TInt))
}

///|
/// The pre-existing spellings must keep working, and this is the regression
/// control for the arm above: an edit that added `Int32` by replacing the line
/// rather than extending it would break `Int` and this catches it.
test "0422: ann_to_ty still reads the older integer spellings" {
  assert_true(ty_is(@types.ann_to_ty("Int"), @types.TInt))
  assert_true(ty_is(@types.ann_to_ty("int"), @types.TInt))
}

///|
/// THE DECISION, pinned in the direction that matters. `Int64` and `UInt` are
/// deliberately NOT mapped to `TInt`. Settled against `moon check`: passing a
/// `UInt` to an `Int` parameter is an Expr Type Mismatch, and so is the reverse,
/// and so is `Int64` against either. Folding them onto `TInt` would silence
/// this reader on exactly the mismatches the toolchain reports.
///

///|
/// They therefore read as Unknown, which is the honest answer: the tool does
/// not model them. This test is here so that adding them later is a deliberate
/// act — a new `Ty` variant plus assignability rules — rather than a one-line
/// edit that quietly deletes a real check.
///

///|
/// Corpus weight for whoever does that work: 122 `: Int64` and 23 `: UInt`
/// annotations across proton + async + moui.
test "0422: ann_to_ty does NOT fold Int64 or UInt into Int" {
  assert_true(!ty_is(@types.ann_to_ty("Int64"), @types.TInt))
  assert_true(!ty_is(@types.ann_to_ty("UInt"), @types.TInt))
}
