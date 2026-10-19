//| 0490: the toolchain RENAMED two builtin types, and the .mbti frontend did
//| not follow.
//|
//| THE CONTEXT. The toolchain was upgraded 0.1.20261012 -> 0.1.20261016 in the
//| middle of the 0490 release gate, by another process on the same machine. The
//| new toolchain RENAMED the two unsuffixed integer types: `Int` is now
//| `Int32`, `UInt` is now `UInt32`. `Int16` and `UInt16` were not renamed --
//| the change is of the UNSUFFIXED names only, which is what makes it a rename
//| rather than a widening.
//|
//| The interfaces the new toolchain generates say so, and the `.mbti` frontend
//| reported every one of them: 37 findings on the analyzer's OWN
//| `src/*/pkg.generated.mbti` files, all of them the same line --
//|
//|     unknown type 'Int32' in interface signature
//|
//| The frontend resolves a signature's type names against the ambient list,
//| and that list carried `Int` and not `Int32`. The type lens already knew the
//| two are one type (`ann_to_ty` maps `"Int" | "Int32" | "int"` to `TInt`), so
//| the interface lens was the odd one out.
//|
//| BOTH SPELLINGS ARE KEPT, and the reason is that they are the SAME type:
//| `moon check` accepts `let x : Int32 = 1` and `let x : Int = 1`, and accepts
//| either in either position. `moon fmt` rewrites `Int` into `Int32`, so the
//| new spelling is the toolchain's own canonical form and the old one is what
//| a user has in their file until they format it. Settled with the toolchain
//| -- `_verify/settle_0490_int32.ps1`, one package per row, with a control
//| module that must be rejected.

///|
/// A `.mbti` WHOSE SIGNATURES USE THE RENAMED TYPES HAS NO FINDINGS.
///
/// This is the shape the new toolchain emits, and the shape the analyzer's own
/// regenerated interfaces have.
test "0490: a .mbti that names the renamed integer types has no findings" {
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
