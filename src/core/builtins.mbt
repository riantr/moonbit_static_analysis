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
pub fn ambient_names() -> Array[String] {
  [
    // --- read out of <toolchain>/lib/core/builtin/pkg.generated.mbti ---
    // types
    "Array", "ArrayView", "ArgsLoc", "Bool", "Byte", "Bytes", "BytesView", "Char",
    "Double", "Failure", "FixedArray", "Hasher", "Int", "Int64", "Iter", "Iter2",
    "Json", "Map", "MutArrayView", "Option", "ReadOnlyArray", "Result", "SourceLoc",
    "String", "StringBuilder", "StringView", "UInt", "UInt16", "UInt64", "UninitializedArray",
    "Unit",
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
  ]
}
