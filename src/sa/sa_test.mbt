// test: the SUMMARY-line identity. One regression in 0.4.0 (`+withheld` was
// added to the printed sum on top of `unreliable`) slipped past 88/88
// because no test pinned the arithmetic. The 0.4.0 round shipped a printed
// identity that read as a fact but did not hold. The downstream reader of
// this output caught it by parsing the printed numbers and asserting the
// sum; the fix is to pin the same identity in this package's own tests so
// the regression cannot return.

///|
/// Build a dummy Report. Aggregate only reads `family` (to set the notice
/// count) and `lenses.length()`; nothing else is touched by the math.
fn mk_report(family : @core.Family) -> @report.Report {
  @report.Report::{
    family,
    lenses: [@core.LStructural],
    message: "",
    span: { start: { line: 0, col: 0, }, end: { line: 0, col: 0, }, },
    vst: [],
  }
}

///|
/// One parsed file with 2 findings (1 defect, 1 notice). The findings array
/// has length 2 so the per-file `actionable + notices` is the expected 1+1.
fn v_parsed() -> @sa.Verdict {
  @sa.Verdict::{
    path: "a.mbt",
    kind: ".mbt",
    findings: [mk_report(@core.FUndefinedName), mk_report(@core.FParse)],
    parsed: true,
    reason: "",
    total: 2,
    notices: 1,
    region_line: 0,
    unreliable: 0,
  }
}

///|
/// Partial file: 1 pre-boundary defect, 0 notices, 5 post-boundary findings.
/// `findings` has length 1 to make the pre-boundary contribution 1 defect /
/// 0 notices (the per-file `(n - notices) = 1 - 0 = 1` and `notices = 0`),
/// which lands entirely in the pre-boundary totals. The 5 post-boundary
/// findings go into `unreliable`, not `withheld` — `withheld` is reserved
/// for partial files whose pre-boundary count is zero (see v_partial_empty).
fn v_partial_with_findings() -> @sa.Verdict {
  @sa.Verdict::{
    path: "b.mbt",
    kind: ".mbt",
    findings: [mk_report(@core.FUndefinedName)],
    parsed: false,
    reason: "first read failure at line 10",
    total: 6,
    notices: 0,
    region_line: 10,
    unreliable: 5,
  }
}

///|
/// Partial file: nothing trustworthy above the boundary, 4 findings all
/// after it. This is the case the 0.4.0 bug cared about: these 4 are
/// counted in BOTH `unreliable` (per-file line in `aggregate`) AND
/// `withheld` (the partial-with-zero-findings branch), and the printed
/// identity then added them together. With the fix, withheld is reported
/// separately and not in the sum.
fn v_partial_empty() -> @sa.Verdict {
  @sa.Verdict::{
    path: "c.mbt",
    kind: ".mbt",
    findings: [],
    parsed: false,
    reason: "first read failure at line 1",
    total: 4,
    notices: 0,
    region_line: 1,
    unreliable: 4,
  }
}

///|
test "SUMMARY identity: actionable + notices + unreliable == total" {
  // Construct three files whose numbers were chosen so the 0.4.0 identity
  // (actionable+notices+unreliable+withheld == total) would have failed:
  //   1 + 1 + 5 + 4 + 4 = 15  (with the bug, "total" printed would be 15)
  //   1 + 1 + 5 + 4     = 11  (the actual total, 0.4.0 printed 15 anyway)
  let vs : Array[@sa.Verdict] = [
    v_parsed(),
    v_partial_with_findings(),
    v_partial_empty(),
  ]
  let s = @sa.aggregate(vs)
  assert_eq(s.parsed_files, 1)
  assert_eq(s.partial_files, 2)
  // Pre-boundary: 1 parsed file (1 defect, 1 notice) + 1 partial-with-findings
  // (1 defect, 0 notices) = 2 actionable, 1 notice.
  assert_eq(s.actionable, 2)
  assert_eq(s.notices, 1)
  // Post-boundary: 5 + 4 = 9.
  assert_eq(s.unreliable, 9)
  // Withheld is a subset of unreliable: only the empty-partial contributes
  // its 4 post-boundary findings.
  assert_eq(s.withheld, 4)
  // total = 2 + 6 + 4 (sum of v.total) = 12. Also = 2 + 1 + 9 (the
  // identity).
  assert_eq(s.total, 12)
  assert_eq(s.actionable + s.notices + s.unreliable, s.total)
  // The identity the 0.4.0 line wrongly asserted (must NOT hold):
  assert_eq(
    s.actionable + s.notices + s.unreliable + s.withheld == s.total,
    false,
  )
}

///|
test "SUMMARY identity: withheld is always a subset of unreliable" {
  // withheld is the post-boundary count of partial files whose pre-boundary
  // finding count is zero. It can never exceed unreliable, because every
  // withheld finding is also unreliable.
  let vs : Array[@sa.Verdict] = [
    v_parsed(),
    v_partial_with_findings(),
    v_partial_empty(),
  ]
  let s = @sa.aggregate(vs)
  assert_true(s.withheld <= s.unreliable)
  // If no file is partial-with-zero-findings, withheld is 0.
  let s2 = @sa.aggregate([v_parsed(), v_partial_with_findings()])
  assert_eq(s2.withheld, 0)
  assert_eq(s2.unreliable, 5)
  // Only the empty-partial case contributes, and then withheld == unreliable.
  let s3 = @sa.aggregate([v_partial_empty()])
  assert_eq(s3.withheld, s3.unreliable)
  assert_eq(s3.total, s3.unreliable)
  // The reverse: a parsed file alone contributes nothing to either side.
  let s4 = @sa.aggregate([v_parsed()])
  assert_eq(s4.withheld, 0)
  assert_eq(s4.unreliable, 0)
  assert_eq(s4.total, 2)
}

///|
test "SUMMARY identity: an empty input gives all zeros" {
  let s = @sa.aggregate([])
  assert_eq(s.parsed_files, 0)
  assert_eq(s.partial_files, 0)
  assert_eq(s.actionable, 0)
  assert_eq(s.notices, 0)
  assert_eq(s.unreliable, 0)
  assert_eq(s.withheld, 0)
  assert_eq(s.total, 0)
  // Identity holds trivially.
  assert_eq(s.actionable + s.notices + s.unreliable, s.total)
}
