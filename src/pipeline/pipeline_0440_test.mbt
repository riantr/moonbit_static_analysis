///|
/// 0440, the finding-level half: a name in the interface table RESOLVES, and a
/// name in neither the table nor the source still does not.
///

///|
/// WHY THIS IS A SEPARATE FILE, and the split is not cosmetic. The harvester
/// lives in `@moonfiles`, and this package cannot import it: `@moonfiles`
/// already calls `@pipeline.run` (`moonfiles.mbt:342`), so an import back would
/// close a cycle — `IfaceSymTab`'s own doc says an import cycle is not allowed
/// for exactly this kind of shared shape.
///
/// So the two layers are pinned where each one actually is:
///   * `moonfiles_0440_test.mbt` — `collect_iface_names` harvests a braced
///     `suberror` body's members. THE DEFECT WAS HERE: one predicate,
///     `in_ctor_body = matched == "enum " && d > 0`, discarded them.
///   * this file — given that name in the table, the walker's refusal to report
///     it. THE CONSEQUENCE is here, and it is the layer a user is affected at:
///     a harvested name that nothing consults would fix nothing.
///
/// `Walker::resolve` consults `extern_iface.has_value(name)`, and `sa/main.mbt`
/// hands the scanner's interface table to every file in the package. That chain
/// is what turns one predicate into 58 fewer findings, and neither half above
/// measures the chain on its own.
///

///|
/// WHY THE NEGATIVE CONTROLS ARE NOT OPTIONAL. Every positive here is a
/// `count_family(..., "UndefinedName") == 0`, and a run where the family had
/// been switched off would produce every one of them — the trap M6 in gate 0439
/// exists to close, reached from the other direction. `Ghost` is in neither the
/// table nor the source, so it must still be reported; if it ever stops being
/// reported, "no more UndefinedName" has stopped meaning anything.

///|
/// THE MEASURED SHAPE, proton `pkg.generated.mbti:68` and a caller in another
/// file. Before the fix, `InvalidSetting` was reported as having no visible
/// binding — one of 58 such findings, and 7 of them that name.
test "0440: a value in the interface table resolves instead of being undefined" {
  let tab = @core.IfaceSymTab::empty()
  tab.values.set("InvalidSetting", true)
  let r = @pipeline.run(
    "fn check(v : Int) -> Int {\n  raise InvalidSetting(name=\"x\")\n  v\n}\n", "known.mbt",
    tab,
  )
  assert_eq(r.first_error_line, 0)
  assert_eq(count_family(r, "UndefinedName"), 0)
}

///|
/// THE NEGATIVE CONTROL: a name in neither the table nor the source.
test "0440 control: a name from nowhere is still reported undefined" {
  let tab = @core.IfaceSymTab::empty()
  tab.values.set("InvalidSetting", true)
  let r = @pipeline.run(
    "fn check(v : Int) -> Int {\n  raise Ghost(name=\"x\")\n  v\n}\n", "ghost.mbt",
    tab,
  )
  assert_eq(r.first_error_line, 0)
  assert_eq(count_family(r, "UndefinedName"), 1)
}

///|
/// AND THE EMPTY-TABLE CONTROL, which is the sharpest one. With no table at
/// all, the same name must be reported — that is what the corpus looked like
/// before the harvest fix, and it is also what a table that silently failed to
/// LOAD would look like afterwards. This is the difference between "the name is
/// now harvested" and "the table is now consulted for everything", which are
/// different claims about different code.
test "0440 control: with an empty table the same name is undefined again" {
  let r = @pipeline.run(
    "fn check(v : Int) -> Int {\n  raise InvalidSetting(name=\"x\")\n  v\n}\n",
    "empty.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(r.first_error_line, 0)
  assert_eq(count_family(r, "UndefinedName"), 1)
}

///|
/// THE CONVERSE, which is what a too-BROAD harvest would cost. A payload TYPE
/// accidentally harvested as a value silences a real finding, and silence is
/// the quiet direction — the one nobody files a bug about until a type error
/// ships. `moonfiles_0440_test.mbt` asserts the harvester does not emit `name`;
/// this asserts that the consequence of that NOT being emitted is preserved.
///
/// The first draft put `name` in the table and then ran a source mentioning
/// BOTH `name` and `InvalidSetting` — so the count stayed at 1 for a reason that
/// had nothing to do with `name`, and the test was measuring the wrong name.
/// Only `name` appears in this source.
test "0440 control: harvesting a payload type as a value would silence this" {
  let src = "fn check(v : Int) -> Int {\n  println(name)\n  v\n}\n"
  let tab = @core.IfaceSymTab::empty()
  tab.values.set("name", true)
  let r = @pipeline.run(src, "payload.mbt", tab)
  assert_eq(r.first_error_line, 0)
  assert_eq(count_family(r, "UndefinedName"), 0)
  // ...and with the table empty it is reported. The PAIR is the point: it shows
  // the table is what changed the verdict, in either direction.
  let empty = @pipeline.run(src, "payload.mbt", @core.IfaceSymTab::empty())
  assert_eq(count_family(empty, "UndefinedName"), 1)
}
