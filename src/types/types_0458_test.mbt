// Tests for 0.4.29: what the annotation reader does with an ASYNC FUNCTION TYPE.
//
// `fn_type_annotation` renders `(async (A, B) -> R)?` and hands the string to
// `ann_to_ty`, which is the only thing that decides whether a written type means
// anything to the type lens. Everything unrecognised becomes Unknown, and Unknown
// silences every check downstream of it — so "Unknown" is both always SAFE and
// always WRONG, and nothing in the findings distinguishes them. That is why the
// test here is an EQUALITY between two renderings rather than an expected type:
// it pins a property the analyzer has TODAY, and it is written so that it FAILS
// the day somebody teaches `ann_to_ty` the `async` prefix.
//
// WHY THIS FILE EXISTS AT ALL. Gate 0458's M5 consumes the `async` head and drops
// it from the rendered string. That mutation SURVIVED 648 tests, and the tempting
// response was to declare it an unobservable survivor. That would have been an
// assertion about the future dressed as a measurement of the present: the honest
// question is whether the two renderings are INDISTINGUISHABLE DOWNSTREAM, and
// that is answerable, so it is answered here instead of argued in a comment.
//
// If this test fails, M5 is no longer a survivor and the gate's `Expect` must
// change. That is the intended tripwire, not a bug report.

///|
/// The `async` head makes no difference to the TYPE the lens derives, because
/// `ann_to_ty` recognises neither spelling — both are Unknown, and Unknown
/// silences the same checks. That is precisely why dropping the rendered prefix
/// (gate 0458 M5) cannot be observed today.
///
/// The assertion is the equality of the two readings. Written so it breaks the
/// moment an `async` case is added: at that point the two differ, this goes red,
// and the gate mutation it protects becomes observable and must be re-declared.
test "0458: the async prefix does not change the type the reader derives" {
  assert_true(
    ty_is(@types.ann_to_ty("async (Int, Int) -> Unit?"), @types.TUnknown),
  )
}

///|
/// AND THE CONTROL THAT MAKES THE ROW ABOVE MEANINGFUL. Two renderings agreeing
/// is only evidence if they COULD have disagreed — so this pins that `ann_to_ty`
/// really does distinguish types, by showing a pair that reads differently.
///
/// Without it, "both Unknown" could be a fact about `ann_to_ty` being the
/// identity function on every string it is given, in which case the equality in
/// the row above would hold for the wrong reason and M5's unobservability would be
/// assumed rather than measured.
test "0458: the annotation reader does distinguish types (control)" {
  assert_false(ty_is(@types.ann_to_ty("Int"), @types.TUnknown))
  assert_false(
    ty_is(
      @types.ann_to_ty("async (Int, Int) -> Unit?"),
      @types.ann_to_ty("Int"),
    ),
  )
}
