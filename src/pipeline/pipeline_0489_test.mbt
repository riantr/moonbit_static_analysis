//| Direction 2: the PER-FUNCTION ENTRY for the behavioral lens.
//
//| WHY THIS FILE EXISTS. The behavioral lens enters at the MODULE: `Interp::
//| run_top` skips `SFunc` items, so a function body is executed only if
//| something CALLS it from a top-level statement. A library module does not
//| call its own functions at top level, so on every pinned corpus the lens
//| executed ZERO function bodies: moui 4152 findings, proton 1062, async 1820
//| -- all of them tagged `structural`, and not one tagged `behavior`.
//
//| MEASURED, the gap was the ENTRY and nothing else. The same defect, in the
//| same body, three ways:
//
//|   top     -- a top-level statement        -> [type+behavior]
//|   incall  -- in a function CALLED at top  -> [type+behavior]
//|   uncall  -- in a function NEVER called   -> [type]   <- behavior GONE
//|
//| for every defect kind tried.
//
//| `Unreachable` is the family to pin with, because it is the one NO OTHER
//| LENS SEES: the structural and type lenses both walk the body and find
//| nothing there, so a merged report carrying `behavior` is unambiguous
//| evidence that the behavioral lens -- and only it -- executed the body.

///|
/// The module entry never executes an uncalled body; the per-function entry
/// does. The same source, two entries, one finding.
test "the per-function entry analyses a body the module entry never executes" {
  let src = "fn g() -> Unit {\n  return\n  let y = 1\n  ()\n}\n"
  let modview = @pipeline.run(src, "x.mbt", @core.IfaceSymTab::empty())
  let perfn = @pipeline.run_functions(src, "x.mbt", @core.IfaceSymTab::empty())
  // The module entry sees nothing, and that is the point: the body is never
  // executed because nothing calls it from a top-level statement.
  assert_eq(count_family_in(modview, "Unreachable", @core.LBehavior), 0)
  // The per-function entry enters AT the function, so the body runs.
  assert_eq(count_family_in(perfn, "Unreachable", @core.LBehavior), 1)
}

///|
/// The module entry must still analyse a body it IS called into. Without this
/// row the first one would also pass if the module entry had stopped working
/// entirely -- a green test that would mean the opposite of what it says.
test "the module entry still analyses a body it is called into" {
  let src = "fn g() -> Unit {\n  return\n  let y = 1\n  ()\n}\n\ng()\n"
  let modview = @pipeline.run(src, "x.mbt", @core.IfaceSymTab::empty())
  assert_eq(count_family_in(modview, "Unreachable", @core.LBehavior), 1)
}

///|
/// The two views differ in ONE thing: where the behavioral lens enters. The
/// structural and type lenses do not read the interpreter at all, so their
/// counts must be IDENTICAL between the two views. A difference here would
/// mean the entry point had leaked into another lens.
test "the two views agree on the structural and type lenses" {
  let src = "fn g() -> Unit {\n  return\n  let y = 1\n  ()\n}\n\nfn h(n : Int) -> Int {\n  let z = n + 1\n  z\n}\n"
  let modview = @pipeline.run(src, "x.mbt", @core.IfaceSymTab::empty())
  let perfn = @pipeline.run_functions(src, "x.mbt", @core.IfaceSymTab::empty())
  assert_eq(perfn.n_structural, modview.n_structural)
  assert_eq(perfn.n_type, modview.n_type)
}

///|
/// AN ENUM CONSTRUCTOR IS NOT AN UNDEFINED VARIABLE.
///
/// This is the false positive the per-function entry surfaced on the first
/// corpus it touched: `proton_contract 0.3.4 contract.mbt:261`,
///
///     ContractRoute::{ scope: Application, name, }
///
/// reported `undefined variable 'Application'` -- an ERROR, on code `moon
/// check` accepts. `Application` is a constructor of the `ContractScope`
/// enum, whose BRACED body this frontend SKIPS, so the name arrives in
/// `ParseResult::enum_ctors` -- the list the structural and type lenses both
/// receive and the behavioral lens never did.
///
/// The defect was in the LENS, not in the entry: the entry only made it
/// visible. The enum body is skipped, so the constructor names are the ONLY
/// place these names exist.
test "an enum constructor read is not an undefined variable" {
  let src = "pub enum E {\n  A\n  B\n}\n\nfn f() -> Unit {\n  let x = A\n  ()\n}\n"
  let perfn = @pipeline.run_functions(src, "x.mbt", @core.IfaceSymTab::empty())
  assert_eq(count_family(perfn, "UndefinedName"), 0)
  assert_eq(count_family_in(perfn, "UndefinedName", @core.LBehavior), 0)
}

///|
/// An UNANNOTATED parameter must not manufacture a finding.
///
/// The fresh value for a parameter is derived from its DECLARED type, and an
/// unannotated parameter has no declared type -- so the lens must assume
/// "some value we know nothing about" and report nothing. A concrete type
/// would be a CLAIM about a value the analyzer has not seen, and a false
/// claim produces a finding on correct code.
test "an unannotated parameter does not manufacture a behavior finding" {
  let src = "fn f(x) -> Unit {\n  if x {\n    return\n  }\n  ()\n}\n"
  let perfn = @pipeline.run_functions(src, "x.mbt", @core.IfaceSymTab::empty())
  assert_eq(count_family_in(perfn, "NonBooleanCond", @core.LBehavior), 0)
}

///|
/// A DECLARED parameter type is what the fresh value is built from, so a
/// declared `Int` used as a condition is a real defect and the per-function
/// entry says so. Without this row the row above would also pass if the
/// fresh value were always `AAny` -- i.e. if the declared type were ignored
/// entirely.
test "a declared parameter type reaches the behavior lens" {
  let src = "fn f(n : Int) -> Unit {\n  if n {\n    return\n  }\n  ()\n}\n"
  let perfn = @pipeline.run_functions(src, "x.mbt", @core.IfaceSymTab::empty())
  assert_eq(count_family_in(perfn, "NonBooleanCond", @core.LBehavior), 1)
}

///|
/// A QUALIFIED CONSTRUCTOR READ IS NOT AN UNDEFINED VARIABLE.
///
/// `E::A` is a constructor of the enum `E`. The harvest binds `A` but not the
/// whole path -- which is exactly the rule the STRUCTURAL lens already uses
/// (`walk.mbt`'s `tail_bound`: "a qualified path whose TAIL is bound is a
/// real name"). This lens had no such rule, so it reported
/// `undefined variable 'E::A'` while the structural lens stayed silent on
/// the same line.
///
/// MEASURED, the class was large: the per-function view reported 200+ of
/// these on moui 0.1.12 alone.
test "a qualified constructor read is not an undefined variable" {
  let src = "pub enum E {\n  A\n  B\n}\n\nfn f() -> Unit {\n  let x = E::A\n  ()\n}\n"
  let perfn = @pipeline.run_functions(src, "x.mbt", @core.IfaceSymTab::empty())
  assert_eq(count_family(perfn, "UndefinedName"), 0)
}

///|
/// THE CONTROL FOR THE ROW ABOVE, and it is a control rather than a
/// restatement: a qualified name whose TAIL is NOT bound is still reported.
/// `ZzMissing::nope` is the shape the repository already pins
/// (`pipeline_0417_test.mbt`), and a tail rule that silenced every qualified
/// name would pass the row above and fail this one.
test "a qualified name whose tail is not bound is still reported" {
  let src = "fn f() -> Unit {\n  ZzMissing::nope()\n  ()\n}\n"
  let perfn = @pipeline.run_functions(src, "x.mbt", @core.IfaceSymTab::empty())
  assert_eq(count_family_in(perfn, "UndefinedName", @core.LBehavior), 1)
}

///|
/// A CALL TO A FUNCTION-TYPED PARAMETER IS NOT AN UNDEFINED FUNCTION.
///
/// `cb` is bound: it is a parameter, the walk sees it, and the type lens types
/// it. This lens dispatched calls only through the top-level method table,
/// so calling a callback parameter was `undefined function 'cb'` -- an ERROR,
/// on code `moon check` accepts, and a finding the structural lens
/// contradicted.
test "a call to a function-typed parameter is not an undefined function" {
  let src = "fn f(cb : () -> Unit) -> Unit {\n  cb()\n  ()\n}\n"
  let perfn = @pipeline.run_functions(src, "x.mbt", @core.IfaceSymTab::empty())
  assert_eq(count_family(perfn, "UndefinedName"), 0)
}

///|
/// THE CONTROL FOR THE ROW ABOVE: a call to a name that is NOT bound anywhere
/// is still reported. A rule that silenced every call the method table did
/// not know would pass the row above and fail this one.
test "a call to an unbound name is still reported" {
  let src = "fn f() -> Unit {\n  no_such_function()\n  ()\n}\n"
  let perfn = @pipeline.run_functions(src, "x.mbt", @core.IfaceSymTab::empty())
  assert_eq(count_family_in(perfn, "UndefinedName", @core.LBehavior), 1)
}
