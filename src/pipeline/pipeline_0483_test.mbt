//| Tests for 0483 -- a PACKAGE-QUALIFIED HOLDER must be READ *AND* RESOLVED.
//|
//| WHY THIS FILE WAS REWRITTEN TWICE, because both versions were wrong in an instructive way.
//!
//| THE FIRST VERSION asserted that `b.repr()` on a foreign type is not reported as an
//! undefined name. It passed -- VACUOUSLY. A method call resolves through the type's interface
//! table, and that table is empty for a type from another package, so the structural lens never
//! had a candidate and reported nothing either way. Mutations M1 and M4 both survived it.
//!
//| THE SECOND VERSION asserted the same claim through the pipeline, which changed the LENS and
//! not the question. Also vacuous, for the same reason.
//!
//| WHAT ACTUALLY ANSWERS IT: the harvest itself. `collect_declared_names` is `pub` and returns
//! an `IfaceSymTab`, so the question "does the harvest carry the whole qualified name" can be
//! ASKED instead of inferred from whether a finding appeared somewhere downstream. Those rows
//! are in `parser_0483_test.mbt`, next to the fold they are about.
//!
//| What is left here is the direction that must not move. The parser is a SUBSET analyser and
//! 0483 made it read more, not judge more; the corpus number that matters is `actionable`,
//! and `moon check` compiles every line these fixtures imitate.

///|
/// A PACKAGE-QUALIFIED HOLDER READS AND PRODUCES NO ACTIONABLE FINDING. The `Struct`/`Buf`
/// declarations here are deliberately local: a cross-package type has no visible FIELDS without
/// a generated `.mbti` (settle 0483 C2 first draft, REJECT 4028), and a fixture that trips over
/// field visibility is measuring the fixture.
test "0483: a package-qualified foreign declaration is not actionable" {
  let r = @pipeline.run(
    "///|\nstruct Buf {\n  x : Int\n}\n\nfn @other.Buf::repr(b : @other.Buf) -> Int = \"%identity\"\n",
    "q.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(r.first_error_line, 0)
  assert_eq(count_family_in(r, "UndefinedName", @core.LStructural), 0)
}

///|
/// AND AN UNRESOLVED FREE CALL IS STILL REPORTED, so the rows above are not passing because
/// the structural lens has been switched off.
///
/// A FREE name and not a method: an unknown METHOD on a type with no interface entry produces
/// no finding at all, which is the same mechanism that made the first two drafts of the harvest
/// row vacuous. A row that silently counts 0 proves nothing -- it would pass on a pipeline that
/// reported nothing ever.
test "0483: an undefined free call is still reported" {
  let r = @pipeline.run(
    "///|\nstruct Buf {\n  x : Int\n}\n\nfn @other.Buf::repr(b : @other.Buf) -> Int = \"%identity\"\n\nfn use_it(b : @other.Buf) -> Int {\n  no_such_function()\n}\n",
    "q.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(r.first_error_line, 0)
  assert_true(count_family_in(r, "UndefinedName", @core.LStructural) > 0)
}
