//| 0490: the toolchain RE-SPELLED two builtin TYPE NAMES, and the .mbti
//| frontend did not follow.
//|
//| THE CONTEXT. The toolchain CHANGED THE CANONICAL SPELLING of the two
//| unsuffixed integer types on 0.1.20261012: `Int` is now `Int32`, `UInt` is
//| now `UInt32`. `Int16` and `UInt16` were not changed -- it is the UNSUFFIXED
//| names only, which is what makes it a change of spelling rather than a
//| widening.
//|
//| The type did NOT change, and the official wording is the authority -- from
//| MoonBit's own Language Fundamentals page:
//|
//|     Int and UInt remain accepted as aliases of Int32 and UInt32.
//|     The formatter uses the explicit-width names Int32 and UInt32.
//|
//| (https://docs.moonbitlang.com/en/latest/language/fundamentals.html) The
//| repository already had this settled in 0.4.22 -- `src/types/types_0422_test.mbt`
//| says "0.1.20261012 renamed the default integer type to `Int32`" -- and that
//| is the version this change landed in. 0.1.20261016 is the version that
//| started REWRITING this repository's own `src/*/pkg.generated.mbti`, which is
//| what put the stale `Int` spelling in front of the analyzer's self-scan and
//| turned the defect into a red gate.
//|
//| The interfaces the new toolchain generates say `Int32`, and the `.mbti`
//| frontend resolves a signature's type names against the ambient list, and
//| that list carried `Int` and not `Int32`. So every interface it generates
//| reported `unknown type 'Int32' in interface signature` -- 37 findings on the
//| analyzer's OWN `src/*/pkg.generated.mbti` files.
//|
//| BOTH SPELLINGS ARE KEPT, and the reason is that the type did not change:
//| `moon check` accepts `let x : Int32 = 1` and `let x : Int = 1`, and accepts
//| either in either position. Settled with the toolchain, not inferred --
//| `_verify/settle_0490_int32.ps1`, one package per row, with a control module
//| that must be rejected.

///|
/// A `.mbti` WHOSE SIGNATURES USE THE NEW SPELLING HAS NO FINDINGS.
///
/// This is the shape the new toolchain emits, and the shape the analyzer's own
/// regenerated interfaces have.
test "0490: a .mbti that names the integer types under the new spelling has no findings" {
  let src = "// Generated using `moon info`, DON'T EDIT IT\npackage \"riantr/demo\"\n\n// Values\npub fn pos(Int32, UInt32) -> Pos\n\n// Types and methods\npub(all) struct Pos {\n  line : Int32\n} derive(Eq)\npub fn Pos::shift(Self, Int32) -> Pos\n"
  let reports = @moonfiles.iface(src, "demo.mbti", @core.IfaceSymTab::empty())
  assert_eq(reports.length(), 0)
}

///|
/// THE OLD SPELLINGS STILL RESOLVE, in the same file, because they are the
/// same type and users have them in their files until they format them.
test "0490: a .mbti that names the old integer spellings still has no findings" {
  let src = "// Generated using `moon info`, DON'T EDIT IT\npackage \"riantr/demo\"\n\n// Values\npub fn pos(Int, UInt) -> Pos\n\n// Types and methods\npub(all) struct Pos {\n  line : Int\n} derive(Eq)\npub fn Pos::shift(Self, Int) -> Pos\n"
  let reports = @moonfiles.iface(src, "demo.mbti", @core.IfaceSymTab::empty())
  assert_eq(reports.length(), 0)
}

///|
/// THE CONTROL FOR THE TWO ROWS ABOVE. A type that does not exist is still
/// reported, and the fix is a NAME in the ambient list, not a rule that stopped
/// resolving types -- which would have silenced this row along with the two
/// above.
test "0490: a .mbti naming a type that does not exist is still reported" {
  let src = "package \"d\"\npub fn pos(Int32, Mystery) -> Int32\n"
  let reports = @moonfiles.iface(src, "d.mbti", @core.IfaceSymTab::empty())
  assert_eq(reports.length(), 1)
  assert_true(reports[0].message.contains("unknown type 'Mystery'"))
}
