// sa_0508_test.mbt -- the DEMOTION, in the place where a notice is COUNTED.
//
// 0506 decided which notices get a LINE of the reader's screen and which are
// counted by shape. 0508 changed WHAT A NOTICE IS -- a low-confidence finding
// joined the scope limits -- and that change lands on this file's decision
// first.
//
// The decision 0506 made was sound for the notice it knew about. A scope limit
// is a SHAPE: the same message repeated across a file, so counting it by shape
// loses nothing. A LOW-CONFIDENCE finding is not a shape: it is a NAME, at a
// LINE. Aggregating it into a shape table would take the name and the place
// away -- which is HIDING it, and the demotion was chosen over hiding it for
// exactly that reason.
//
// So the two kinds of notice are told apart by what they ARE, and the split
// asks the scope-limit question to decide it.
//
// => 判据: A DEMOTION THAT CHANGES WHAT THE TOOL REPORTS IS NOT A DEMOTION.
//    The first implementation of this increment used `!r.is_notice()` here,
//    and the demoted finding was therefore aggregated with the scope limits --
//    and the 0505 and 0507 settles, whose rows claim that the analyzer REPORTS
//    an undefined name, went red. Those rows are the house's own record of
//    what the analyzer says, and a demotion that changes what it says is not a
//    demotion.

///|
/// A low-confidence finding: the family that reasons from a NAME alone.
fn mk_low(line : Int32) -> @report.Report {
  @report.Report::{
    family: @core.FUndefinedName,
    lenses: [@core.LStructural],
    message: "undefined variable 'x'",
    span: { start: @core.pos(line, 1), end: @core.pos(line, 2), },
    vst: [],
  }
}

///|
/// A finding the analyzer STANDS BEHIND: the declaration was in front of the
/// lens, so it keeps its family's severity.
fn mk_solid(line : Int32) -> @report.Report {
  @report.Report::{
    family: @core.FArgType,
    lenses: [@core.LStructural],
    message: "argument 1 to 'f' has incompatible type 'Int'",
    span: { start: @core.pos(line, 1), end: @core.pos(line, 2), },
    vst: [],
  }
}

///|
/// A declared scope limit: the family AND the marker, so the analyzer is
/// saying it could not decide at all.
fn mk_limit(line : Int32) -> @report.Report {
  @report.Report::{
    family: @core.FParse,
    lenses: [@core.LStructural],
    message: "if expression is outside the analyzed subset; it was read but not analysed",
    span: { start: @core.pos(line, 1), end: @core.pos(line, 2), },
    vst: [],
  }
}

///|
/// THE DEMOTED FINDING IS PRINTED. It is not a defect any more, but it is
/// still a finding, and it names a place -- so it gets a line of its own.
test "demotion: a demoted finding is printed, never aggregated" {
  let (printed, aggregated) = @sa.split_findings([mk_low(3)], [])
  assert_eq(printed.length(), 1)
  assert_eq(aggregated.length(), 0)
}

///|
/// AND THE 0506 RULE STILL HOLDS FOR THE OTHER KIND. A scope limit outside
/// every function's extent hides nothing, so it is counted by shape -- exactly
/// as it was before 0508.
test "demotion: a scope limit outside every function's extent is still aggregated" {
  let (printed, aggregated) = @sa.split_findings([mk_limit(30)], [])
  assert_eq(printed.length(), 0)
  assert_eq(aggregated.length(), 1)
}

///|
/// THE TWO KINDS ARE TOLD APART BY THE SPLIT, and one row each side of it: the
/// demoted finding is printed and the scope limit is aggregated, in the SAME
/// list, with the same (empty) hiding list. A rule that keyed on "is it a
/// notice" would put both in the same set.
test "demotion: the demoted finding and the scope limit are told apart by the split" {
  let low = mk_low(3)
  let limit = mk_limit(30)
  let (printed, aggregated) = @sa.split_findings([low, limit], [])
  assert_eq(printed.length(), 1)
  assert_eq(aggregated.length(), 1)
  assert_true(printed[0].span == low.span)
  assert_true(aggregated[0].span == limit.span)
}

///|
/// THE COUNT SEES THE DEMOTED FINDING. A demoted finding leaves the
/// `actionable` count and enters the `notices` count, and the count is what
/// the SUMMARY's identity is built on -- so if the count did not see it, the
/// SUMMARY would not add up.
test "demotion: the notice count is the demoted findings too" {
  assert_eq(@sa.count_notices([mk_low(1), mk_solid(2)]), 1)
}

///|
/// AND A SET OF DEMOTED FINDINGS IS COUNTED IN FULL. The demotion changes the
/// LABEL and the bucket, not the visibility: every one of them is still
/// counted, because a finding that is counted as nothing is a finding that is
/// hidden.
test "demotion: every demoted finding is counted" {
  assert_eq(@sa.count_notices([mk_low(1), mk_low(2), mk_low(3)]), 3)
}
