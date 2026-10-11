// Tests for the 0.4.15 fixes: the three largest remaining classes of false
// positive after 0.4.14, all found by scanning four published modules.
//
//   A  `==` / `!=` between two Bools is legal in MoonBit. The type lens
//      rejected it — 2 findings on riantr/moonbit_doubleML 0.139.0.
//   B  A UNIT enum variant (`Layer::ReLU`, `LayerGrad::Empty`) read as a value
//      was reported undefined, while the PAYLOAD variant beside it in the same
//      enum resolved — 4 findings on riantr/snn_mbt 0.155.0.
//   C  A parameter of an `extern "C"` function was reported unused, because the
//      body is in another language and was never read — 6 findings on
//      riantr/snn_mbt 0.155.0.
//
// Each fix was settled with a toolchain probe BEFORE a line changed. The
// negative controls matter more than the fixes: two of the three could have
// been "fixed" by muting the whole rule, which is what the controls rule out.

///|
/// A — equality between two Bools.
test "0415: Bool == Bool and Bool != Bool are legal" {
  let a = @pipeline.run(
    "fn f(x : Bool, y : Bool) -> Bool {\n  x == y\n}\n",
    "x.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family_in(a, "OperatorMismatch", @core.LType), 0)
  let b = @pipeline.run(
    "fn f(x : Bool, y : Bool) -> Bool {\n  x != y\n}\n",
    "x.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family_in(b, "OperatorMismatch", @core.LType), 0)
}

///|
/// The NEGATIVE CONTROL for A, and the one that keeps the fix honest: the fix
/// extends EQUALITY, not comparison. `x < y` on Bools has no meaning in
/// MoonBit and must still be reported. A fix that accepted any two operands for
/// `==`, `<` and `>` alike would pass the test above and fail here.
test "0415: ORDERING two Bools is still an error" {
  let a = @pipeline.run(
    "fn f(x : Bool, y : Bool) -> Bool {\n  x < y\n}\n",
    "x.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family_in(a, "OperatorMismatch", @core.LType), 1)
}

///|
/// B — a unit enum variant read as a value. The payload variant in the same
/// file already resolved before this fix, which is what made the gap so easy
/// to misread as "the enum was not harvested at all".
test "0415: a UNIT enum variant resolves; a PAYLOAD one already did" {
  let unit = @pipeline.run(
    "enum Colour {\n  Red\n  Green\n}\nfn f() -> Colour {\n  Colour::Green\n}\n",
    "x.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family_in(unit, "UndefinedName", @core.LStructural), 0)
  assert_eq(count_family_in(unit, "UndefinedName", @core.LType), 0)
  // The payload variant is the control for "the fix did not simply switch the
  // whole qualified-path lookup off".
  let payload = @pipeline.run(
    "enum Box {\n  Empty\n  Filled(Int)\n}\nfn f() -> Box {\n  Box::Filled(1)\n}\n",
    "x.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family_in(payload, "UndefinedName", @core.LStructural), 0)
}

///|
/// The NEGATIVE CONTROL for B, and the dangerous one. The fix resolves a
/// qualified path whose TAIL is a known name. A variant that was never
/// declared has no such tail, so it must still be reported — otherwise every
/// typo'd enum path in every codebase would go silent.
test "0415: a qualified path whose tail is NOT declared is still an error" {
  let a = @pipeline.run(
    "enum Colour {\n  Red\n}\nfn f() -> Colour {\n  Colour::Purple\n}\n",
    "x.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_true(count_family_in(a, "UndefinedName", @core.LStructural) > 0)
}

///|
/// C — an `extern "C"` parameter is part of the foreign ABI, not a binding
/// this analyzer may judge unread.
test "0415: an extern C parameter is not reported unused" {
  let a = @pipeline.run(
    "extern \"C\" fn expf(x : Float) -> Float = \"expf\"\n",
    "x.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(a, "UnusedParam"), 0)
}

///|
/// The NEGATIVE CONTROL for C. A normal function with an unread parameter must
/// still be reported — INCLUDING one with a completely empty body, which was
/// measured against the compiler: `fn p7(z : Float) -> Float { }` warns, so
/// "the body is empty" is not an available proxy for "this is extern".
test "0415: a normal unused parameter is still reported, empty body or not" {
  let with_body = @pipeline.run(
    "fn f(y : Float) -> Float {\n  1.0\n}\n",
    "x.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(with_body, "UnusedParam"), 1)
  let empty_body = @pipeline.run(
    "fn f(z : Float) -> Float {\n  1.0\n}\n",
    "x.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(empty_body, "UnusedParam"), 1)
}

///|
/// `@core.path_tail` on its own. It is the whole of fix B, so its edges are
/// pinned directly rather than only through the pipeline.
test "0415: path_tail returns the last segment, or empty when unqualified" {
  assert_eq(@core.path_tail("Layer::ReLU"), "ReLU")
  assert_eq(@core.path_tail("A::B::C"), "C")
  assert_eq(@core.path_tail("plain"), "")
  assert_eq(@core.path_tail(""), "")
  // A single `:` is not a path separator and must not be treated as one.
  assert_eq(@core.path_tail("a:b"), "")
}
