// report_0508_test.mbt -- the DEMOTION: a low-confidence finding is a NOTICE.
//
// 0508. The confidence axis shipped in 0507 with three values, and the analyzer
// REPORTED them. What it did not do is ACT on them, and the clause of the
// transfer that was still open is the one bandit implements as `Issue.filter`:
//
//   bandit/core/issue.py:79-106  -- an issue carries a severity AND a
//   confidence, and `Issue.filter` (:147-167) needs BOTH to clear the
//   thresholds.
//
// So the second axis was in the model but not in the filter. A `low`-confidence
// finding -- the one family that reasons from a NAME alone, `UndefinedName` --
// was rendered `error:` and counted as actionable, which says "the analyzer
// checked this and it is wrong" about a finding the analyzer explicitly says
// it could not check.
//
// THE RULE, IN ONE LINE. A finding is a NOTICE iff the analyzer does not stand
// behind it: a declared scope limit (`undecided`) or a low-confidence finding
// (`low`). Everything the analyzer stands behind keeps its family's severity.
//
// IT IS A DEMOTION, NOT A HIDE. The finding is still rendered, still counted,
// and still carries its family, its stable id and its confidence. What changes
// is the label and the counts: a low-confidence finding is `notice:` and it is
// counted in `notices` rather than in `actionable`.
//
// THE TWO QUESTIONS ARE TOLD APART BY MECHANISM, NOT BY THE CONFIDENCE.
// `is_notice` asks two of them -- the scope-limit question (the family AND the
// marker) and the low-confidence question (the family alone) -- and
// `confidence` answers one. `confidence` therefore asks the SCOPE-LIMIT
// question and never asks `is_notice`: a pair of mutually recursive predicates
// is a pair that can both be wrong in a way nothing notices.
//
// => 判据: AN AXIS THAT NOTHING ACTS ON IS A COLUMN. The confidence was on
//    every finding, in the rendering and in the JSON record, and it changed no
//    decision: the actionable count was the same number it would have been if
//    the axis had never been built. The axis earns its place the moment
//    something is decided with it.

///|
fn mk0508(family : @core.Family, message : String) -> @report.Report {
  @report.Report::{
    family,
    lenses: [@core.LStructural],
    message,
    span: @core.span_at(1, 1, 1),
    vst: [],
  }
}

///|
/// A low-confidence finding is a NOTICE, and that is the whole change.
test "demotion: a low-confidence finding is a notice" {
  let r = mk0508(@core.FUndefinedName, "undefined variable 'x'")
  assert_true(r.confidence() == @core.Low)
  assert_true(r.is_notice())
  assert_eq(r.severity_label(), "notice")
}

///|
/// IT IS NOT HIDDEN. The rendered line still carries the message, the family
/// name, the family's stable id and the confidence -- so a reader who wants
/// the finding can find it, and a machine can still filter on the family.
test "demotion: the demoted finding is still rendered in full" {
  let r = mk0508(@core.FUndefinedName, "undefined variable 'x'")
  let line = r.render()
  assert_true(line.contains(" - notice: "))
  assert_true(line.contains("undefined variable 'x'"))
  assert_true(line.contains("(UndefinedName)"))
  assert_true(line.contains("MSA-002"))
  assert_true(line.contains("low"))
}

///|
/// The family severity the demotion takes away from the label is not lost: it
/// is a property of the family, and the family is still on the line.
test "demotion: the family's own severity is untouched" {
  // `assert_eq` is not usable on a `Severity`: it has no `Debug` impl, and the
  // comparison is the claim anyway.
  assert_true(@core.FUndefinedName.severity() == @core.Error)
  assert_true(@core.FArgType.severity() == @core.Error)
  assert_true(@core.FUnusedLocal.severity() == @core.Warning)
}

///|
/// A finding the analyzer STANDS BEHIND keeps its family's severity and stays
/// actionable. The demotion is not a blanket softening.
test "demotion: a high-confidence finding keeps its severity" {
  let r = mk0508(
    @core.FArgType,
    "argument 1 to 'f' has incompatible type 'Int'",
  )
  assert_true(r.confidence() == @core.High)
  assert_true(!r.is_notice())
  assert_eq(r.severity_label(), "error")
}

///|
/// A declared scope limit is still a notice and still `undecided`. The
/// demotion did not touch the other kind.
test "demotion: a scope limit is still undecided and still a notice" {
  let r = mk0508(
    @core.FParse,
    "match expression is outside the analyzed subset; it was read but not analysed",
  )
  assert_true(r.is_declared_scope_limit())
  assert_true(r.is_notice())
  assert_true(r.confidence() == @core.Undecided)
  assert_eq(r.severity_label(), "notice")
}

///|
/// THE TWO QUESTIONS ARE DIFFERENT QUESTIONS, and the file proves it from both
/// sides. A genuine `FParse` defect -- the family, but NOT the marker -- is
/// not a scope limit, and it is not low-confidence either, so it is neither
/// kind of notice and it keeps its severity.
test "demotion: the scope-limit question and the low-confidence question differ" {
  let r = mk0508(@core.FParse, "unterminated string literal")
  assert_true(!r.is_declared_scope_limit())
  assert_true(r.confidence() == @core.High)
  assert_true(!r.is_notice())
  assert_eq(r.severity_label(), "error")
}

///|
/// And from the other side: a low-confidence finding is NOT a scope limit. It
/// is a notice because of its confidence, and it says so -- the two questions
/// have different answers on the same finding.
test "demotion: a low-confidence finding is not a scope limit" {
  let r = mk0508(@core.FUndefinedName, "no visible binding for 'x'")
  assert_true(!r.is_declared_scope_limit())
  assert_true(r.is_notice())
}

///|
/// The three confidence values map onto the three positions of the filter:
/// `high` clears it, `low` does not clear it and is demoted, `undecided` never
/// reached it. That mapping is what the whole axis is for.
test "demotion: the filter has exactly three positions" {
  let high = mk0508(
    @core.FArgType,
    "argument 1 to 'f' has incompatible type 'Int'",
  )
  let low = mk0508(@core.FUndefinedName, "undefined variable 'x'")
  let undecided = mk0508(
    @core.FParse,
    "match expression is outside the analyzed subset; it was read but not analysed",
  )
  assert_true(high.is_notice() == false)
  assert_true(low.is_notice() == true)
  assert_true(undecided.is_notice() == true)
  // and the two notices are told apart by the confidence, not by the label
  assert_eq(high.severity_label(), "error")
  assert_eq(low.severity_label(), "notice")
  assert_eq(undecided.severity_label(), "notice")
  assert_true(low.confidence() != undecided.confidence())
}
