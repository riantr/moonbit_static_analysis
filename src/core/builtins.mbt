// ambient: the names a `.mbt` file can use WITHOUT importing anything.
//
// Why this file exists
// --------------------
// Three lenses each need to answer "is this name bound?" for a file they are
// reading, and each of them used to carry its own private answer. The `.mbt`
// binding walk carried three names (`print`, `len`, `abs`) and NO type names,
// so ordinary code reported
//
//     let m : Map[String, Int] = Map([])
//                          ^^^^^ no visible binding for 'Map'
//
// which is not a defect in the code being analysed, it is a gap in the table.
// The `.mbti` frontend carried a different, larger list. Two lists, one of
// them three entries long, is how the same name came to be an error in one
// frontend and legal in the other. This is the one list.
//
// Provenance
// ----------
// The first block below was read out of the toolchain's own generated
// interface for the ambient package,
//
//     <toolchain>/lib/core/builtin/pkg.generated.mbti
//
// which is the public surface every package gets for free. Only lines that
// start at column 0 were read, because the indented lines in that file are
// members inside `impl` blocks, and treating `write_string` or `hash_combine`
// as a top-level free function is exactly the kind of guess that turns a
// precise linter into a silent one.
//
// `Some`, `None`, `Ok` and `Err` are declared in no package at all — they are
// compiler constructors. `len`, `abs`, `max`, `min` and `print` are compiler
// special forms, not `pub fn`s, so they are in none of the toolchain files
// either. They belong here on the same grounds: they are ambient, and a scan
// of this analyzer's own source reported `Some` more often than any other
// single name.
//
// `Nil`, `Error`, `Set`, `UInt8`, `Int16` and `Float` are carried over from
// the `.mbti` frontend's private list, which had them and this walk did not.
// They are not all in the ambient interface today. They are kept because the
// next section explains why an extra name is the cheap mistake here and a
// missing one is not.
//
// The `Type::method` form lives in `builtin_methods.mbt`, generated from the
// same toolchain tree rather than hand-maintained, for the same reason the
// bare list was ever read out of an interface in the first place: a name
// invented here is a false alarm, and a name missed here is noise.
//
// Direction of the error
// ----------------------
// Every use of this list SUPPRESSES a "no visible binding" finding. It can
// therefore only ever cost a missed report, never invent a false alarm — the
// safe direction for a check whose job is to point at real defects. That is
// why the list is deliberately generous with names a given project may have
// to import: a missing name is noise the user learns to ignore, and once a
// linter is ignored it is reporting nothing at all. The mirror-image list —
// everything the analyzer would have to model precisely to be worth having —
// is the type lens's inference tables, which is where it belongs.

///|
/// Every name a `.mbt` file may use without an import, in one flat list.
///
/// Flat on purpose. The AST cannot tell a type reference from a value
/// reference by position — the type annotation lives in `SLet.ann`, not in
/// the expression tree — and MoonBit itself does not separate them at the
/// name level either: `Map([])` is a call whose callee is a type name. The
/// consumer that needs to tell them apart (`types`, which wants a `Ty`) keeps
/// its own richer structure and uses this list only to know that a name is
/// not an error.
///
/// The bare names above are followed by `builtin_method_names()`, so the
/// returned list also carries the `Type::method` form. The `.mbti` frontend
/// skips any type text containing `::` before consulting this list, so the
/// extra entries cost it nothing but a slightly longer array; the three
/// `.mbt` lenses only ever ask whether a name is a member.
pub fn ambient_names() -> Array[String] {
  let bare = [
    // --- read out of <toolchain>/lib/core/builtin/pkg.generated.mbti ---
    // types
    "Array", "ArrayView", "ArgsLoc", "Bool", "Byte", "Bytes", "BytesView", "Char",
    "Double", "Failure", "FixedArray", "Hasher", "Int", "Int64", "Iter", "Iter2",
    "Json", "Map", "MutArrayView", "Option", "ReadOnlyArray", "Result", "SourceLoc",
    "String", "StringBuilder", "StringView", "UInt", "UInt16", "UInt64", "UninitializedArray",
    "Unit",
    // --- not in `core/builtin`'s interface, but ambient all the same ---
    //
    // `Ref` is declared by `moonbitlang/core/ref` and reaches every package the
    // way `Repr` does: `core/prelude` re-exports it, and `prelude` is in
    // implicit scope. So the rule this list already follows — a name in
    // implicit scope belongs here even when `core/builtin`'s interface does
    // not mention it — applies to it exactly as it did to `Repr`. Missing it
    // reported `undefined function 'Ref'` on 6 lines of
    // wzzc-dev/moui 0.1.12 `backend/web/web_async_services.mbt`, on
    // `let r : Ref[Int] = Ref(1)`, which `moon check` accepts.
    //
    // Settled with the toolchain, not inferred: a probe using `Ref(1)`, `Ref[Int]`
    // and `.val` produces no type error, while the same file with a name that
    // cannot exist produces two. The one error the clean probe still printed is
    // `Unexpected main function in the non-main package`, which is about the
    // probe's own package layout and says nothing about `Ref`.
     "Ref",
    // Two more builtin TYPE names, settled the same way (0.4.18). Both were
    // reported on lines `moon check` accepts:
    //   `unknown type 'FuncRef' in interface signature` —
    //     wzzc-dev/moui 0.1.12 `services/pkg.generated.mbti:355`
    //   `no visible binding for 'Buffer'` —
    //     wzzc-dev/moui 0.1.12 `core/view_state_slot_test.mbt:16`
    //
    // The settle probe declared `f : FuncRef[(Int) -> Int]` and `b : Buffer`
    // with trivial bodies. Its ONLY diagnostics were `Warning (unused_value)`
    // on the parameters and a `Show`-trait error on the `println` — nothing
    // about resolving either annotation, so both names are ambient builtins
    // reachable with no import. `Buffer` is additionally confirmed by
    // `Type @moonbitlang/core/buffer.Buffer has no method new`: the type
    // resolved and only the method name was wrong.
     "Buffer", "FuncRef",
    // functions
     "abort", "assert_false", "assert_true", "compare", "debug_assert", "eprintln",
    "fail", "hash", "ignore", "inspect", "not", "null", "op_notequal", "panic", "physical_equal",
    "println",
    // --- compiler constructors, declared in no package ---
     "Some", "None", "Ok", "Err",
    // --- compiler special forms, declared as no ordinary function ---
     "len", "abs", "max", "min", "print",
    // --- the rest of the assertion family ---
     "assert", "assert_eq", "assert_ne", "debug_assert_eq", "debug_assert_ne", "debug_assert_true",
    "debug_assert_false",
    // --- carried over from the .mbti frontend's private list ---
     "Nil", "Error", "Set", "UInt8", "Int16", "Float",
    // The METHODS of these types are NOT listed here one by one — they live in
    // `builtin_methods.mbt`, generated from the toolchain's own interfaces, and
    // merged in below. That file's header records why they were worth a
    // generated table: 0.4.16 had a NOTE here claiming the behavioral lens
    // "skips any call qualified on an ambient type name", which was FALSE —
    // that rule was written and reverted in the same release, and the claim
    // outlived it. riantr/moonbit_labeler 0.2.13 `rasterizer.mbt:74` was the
    // finding that proved it: `Array::make(total, Byte::default())`, reported
    // as `undefined function 'Array::make'` on code `moon check` accepts.
    //
    // An earlier diagnosis of that finding — the one this NOTE replaced — read
    // the two callees as whack-a-mole: adding `Byte::default` to the list
    // merely exposed `Array::make` beside it, so no fix could ever end. That
    // reading was wrong twice over. Only ONE of the two was ever reported, and
    // a call that reports returns ABottom, which SUPPRESSES the enclosing
    // call — so a nested chain reports its innermost name and hides the rest.
    // The "next one revealed" is the mask lifting, not an endless list; the
    // family terminates when the callees are known.
    //
    // --- from `moonbitlang/core/debug`, NOT from core/builtin ---
    //
    // The sections above are read out of `core/builtin`'s interface, which is
    // where they were all measured from until this one. `Repr` is not there: it
    // is a CONSTRUCTOR of the `Repr` enum in `core/debug`
    // (`pub fn[T : Debug] Repr::Repr(T) -> Self`), and MoonBit puts `core` in
    // implicit scope, so a `.mbt` file can call `Repr(x)` with no import and no
    // declaration anywhere.
    //
    // Measured on riantr/pyroduct 0.1.29: 16 `no visible binding for 'Repr'`
    // findings, every one a call that `moon check` accepts. Settled with the
    // toolchain rather than by inference — one probe file calling `Repr(1)` and
    // `ZzNoSuchName123(2)` in the same interpolation, and `moon check` flagged
    // only the second.
     "Repr",
  ]
  for n in builtin_method_names() {
    bare.push(n)
  }
  bare
}
