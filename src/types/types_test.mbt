// Tests for the written-annotation reader. This file did not exist until
// 0.4.13, and its absence is why a real regression survived a full release:
// `ann_to_ty` is what tells the subscript check whether a base is a list, and
// nothing asserted that `Array[T]` — the spelling MoonBit actually uses —
// produced a list at all.

///|
/// `Ty` derives `Eq` but not `Debug`, and `assert_eq` needs `Debug` to print
/// the failure — so the comparison is written out. A test that cannot print
/// what it compared fails with a bare "false", which is the same as no test.
fn ty_is(a : @types.Ty, b : @types.Ty) -> Bool {
  a == b
}

///|
test "ann_to_ty: the primitives, capitalised as MoonBit spells them" {
  assert_true(ty_is(@types.ann_to_ty("Int"), @types.TInt))
  assert_true(ty_is(@types.ann_to_ty("Bool"), @types.TBool))
  assert_true(ty_is(@types.ann_to_ty("Float"), @types.TFloat))
  assert_true(ty_is(@types.ann_to_ty("Double"), @types.TFloat))
  assert_true(ty_is(@types.ann_to_ty("String"), @types.TStr))
  assert_true(ty_is(@types.ann_to_ty("Unit"), @types.TNone))
}

///|
/// `Array[T]` is the spelling real MoonBit uses. It MUST reach the lens as a
/// list: the subscript check is gated on the base being one, so an `Array`
/// that read as Unknown silences every real list-index error on a parameter.
test "ann_to_ty: Array[T] is a list, and its element type is kept" {
  assert_true(
    ty_is(@types.ann_to_ty("Array[String]"), @types.TList(@types.TStr)),
  )
  assert_true(ty_is(@types.ann_to_ty("Array[Int]"), @types.TList(@types.TInt)))
  assert_true(
    ty_is(@types.ann_to_ty("Array[Double]"), @types.TList(@types.TFloat)),
  )
}

///|
/// Nested containers, because the bracket group is rendered recursively and a
/// one-level reader would silently truncate `Array[Array[Int]]`.
test "ann_to_ty: a nested Array keeps both levels" {
  assert_true(
    ty_is(
      @types.ann_to_ty("Array[Array[Int]]"),
      @types.TList(@types.TList(@types.TInt)),
    ),
  )
}

///|
/// The negative control that makes the `Array[` case non-vacuous: a name that
/// merely STARTS with `Array` is not a list, and `Map` — indexed by its KEY —
/// must stay Unknown, since that is what keeps a map subscript from being
/// called a type error.
test "ann_to_ty: Map stays Unknown and a near-miss name is not a list" {
  assert_true(ty_is(@types.ann_to_ty("Map[String, Int]"), @types.TUnknown))
  assert_true(ty_is(@types.ann_to_ty("Array"), @types.TUnknown))
  assert_true(ty_is(@types.ann_to_ty("Arrayx[Int]"), @types.TUnknown))
  assert_true(ty_is(@types.ann_to_ty(""), @types.TUnknown))
  assert_true(ty_is(@types.ann_to_ty("Whatever"), @types.TUnknown))
}

///|
/// The `[T]` spelling is kept for hand-written samples and `.mbti` text. It is
/// NOT valid MoonBit as a written annotation — `fn f(x : [String])` is a parse
/// error in the toolchain — so this asserts the reader's tolerance, not a
/// language rule.
///
/// `[]` is deliberately NOT a list: the guard requires at least one character
/// of element type, so a degenerate bracket pair cannot claim to be a list. That
/// is unchanged from before 0.4.13, and it is asserted here so a later
/// "simplification" of the guard is visible as a failing test rather than as a
/// new finding shape.
test "ann_to_ty: the bracket spelling is still a list, but a bare [] is not" {
  assert_true(ty_is(@types.ann_to_ty("[String]"), @types.TList(@types.TStr)))
  assert_true(
    ty_is(
      @types.ann_to_ty("[Array[Int]]"),
      @types.TList(@types.TList(@types.TInt)),
    ),
  )
  assert_true(ty_is(@types.ann_to_ty("[]"), @types.TUnknown))
}

///|
/// An element this reader does not know must not poison the container: the
/// list is still a list, with an unknown element. That is what lets
/// `Array[SomeExternalType]` be indexed by int without inventing an element.
test "ann_to_ty: an unknown element still yields a list" {
  assert_true(
    ty_is(@types.ann_to_ty("Array[Nonesuch]"), @types.TList(@types.TUnknown)),
  )
}
