// test: the PACKAGE-LOCAL METHOD TABLE, and the rule that fills it.
//
// 0502. Reading a match's arms brought back fourteen findings across the seven
// pinned corpora, and SIX of them were false positives. One of the six was the
// same shape six times: a type's METHOD called UNQUALIFIED inside the package
// that declares the type.
//
//     moonbitlang/core  immut/vector/vector.mbt:68
//         pub fn[A] Vector::makei(..) -> ..
//     moonbitlang/core  immut/vector/invariants_wbtest.mbt:354,363,366
//         makei(..)
//
// The toolchain accepts every one of them -- the whole `moonbitlang/core`
// package checks with ONE error and it is not this name -- and the analyzer
// reported all six as `no visible binding for 'makei'`.
//
// WHY IT WAS A FALSE POSITIVE. The harvest keeps the QUALIFIED name, because
// that is how the declaration is written: `Vector::makei`. The table therefore
// held the qualified name, the call site spelled the bare one, and the bare
// one was in no table at all.
//
// THE RULE IS PACKAGE-LOCAL, and that is the part that has to be pinned: the
// table is filed by DIRECTORY and unioned only into the files of that same
// directory, so a method of a type in package A cannot silence a name in
// package B. A global table would let every method name in the world resolve
// everywhere -- six false positives traded for an unknown number of false
// negatives.
//
// => 判据: a name the toolchain resolves is not a finding. The question is
// never "is the name in the table" but "does the toolchain accept it", and
// the answer here was measured with the compiler as the oracle.

///|
/// The segment is the name AFTER the last `::` -- `Vector::makei` gives
/// `makei`, and not `Vector`.
test "0502: a method segment is the name after the last ::" {
  let t = @core.IfaceSymTab::empty()
  t.add_value("Vector::makei")
  let segs = @sa.method_segments(t)
  assert_eq(segs.length(), 1)
  assert_true(segs.contains("makei"))
  assert_false(segs.contains("Vector"))
}

///|
/// A name with no `::` is not a method and contributes nothing. The table
/// holds ordinary top-level names too, and a rule that turned every one of
/// them into a segment would add a name for each.
test "0502: a name with no :: contributes no segment" {
  let t = @core.IfaceSymTab::empty()
  t.add_value("plain_name")
  let segs = @sa.method_segments(t)
  assert_eq(segs.length(), 0)
}

///|
/// AND THE CONTROL for the rule above: one qualified name and one plain name
/// together, and only the qualified one contributes.
test "0502: only a qualified name contributes a segment" {
  let t = @core.IfaceSymTab::empty()
  t.add_value("plain_name")
  t.add_value("Vector::makei")
  let segs = @sa.method_segments(t)
  assert_eq(segs.length(), 1)
  assert_true(segs.contains("makei"))
}

///|
/// THE POINT OF THE RULE: after the segments are recorded, the BARE name
/// resolves. Before it, it did not -- and that is what produced the six false
/// positives.
test "0502: a method is recorded under its bare name" {
  let t = @core.IfaceSymTab::empty()
  t.add_value("Vector::makei")
  assert_false(t.has_value("makei"))
  @sa.add_method_segments(t)
  assert_true(t.has_value("makei"))
}

///|
/// A METHOD IS A FUNCTION, so the value carries `is_const` FALSE.
/// `src/types/infer.mbt` types a const as `TUnknown` and a function as
/// `TUnknownFn`, and a method is callable -- recording it as a const would
/// make every unqualified method call a type error.
test "0502: a method is recorded as a function, not a constant" {
  let t = @core.IfaceSymTab::empty()
  t.add_value("Vector::makei")
  @sa.add_method_segments(t)
  assert_false(t.is_const("makei"))
}

///|
/// TWO TYPES MAY DECLARE A METHOD OF THE SAME NAME, and the table is a set of
/// names -- so the segment appears once.
test "0502: two types may declare a method of the same name" {
  let t = @core.IfaceSymTab::empty()
  t.add_value("Vector::makei")
  t.add_value("List::makei")
  let segs = @sa.method_segments(t)
  assert_eq(segs.length(), 1)
  @sa.add_method_segments(t)
  assert_true(t.has_value("makei"))
}
