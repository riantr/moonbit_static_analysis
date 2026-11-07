// sa_0521_test.mbt -- the ADEQUACY BLOCK, as a pure function.
//
// 0521. Every number in `metrics_lines` is derived from `verdicts` and the
// `Summary`, and nothing is re-measured. That is a claim about the code, so it
// is pinned here: the block cannot disagree with the SUMMARY line beside it
// because both read the same aggregation, and the identity between them is
// asserted rather than intended.

///|
/// A parsed verdict with the given findings and call counters. Everything else
/// is the benign value, because `metrics_lines` reads only these.
fn mk_v0521(
  findings : Array[@report.Report],
  calls : Int32,
  checked : Int32,
) -> @sa.Verdict {
  @sa.Verdict::{
    path: "a.mbt",
    kind: ".mbt",
    findings,
    parsed: true,
    reason: "",
    total: findings.length(),
    notices: @sa.count_notices(findings),
    region_line: 0,
    unreliable: 0,
    hiding: [],
    n_unchecked: 0,
    n_calls: calls,
    n_checked: checked,
  }
}

///|
/// A report the analyzer calls a DECLARED SCOPE LIMIT: the `FParse` family plus
/// the subset marker in the message. Its confidence is `undecided`, which is
/// the column the METRICS table reports as the scope-limit count.
fn mk_scope_limit0521() -> @report.Report {
  @report.Report::{
    family: @core.FParse,
    lenses: [@core.LStructural],
    message: "struct body is outside the analyzed subset",
    span: { start: { line: 0, col: 0, }, end: { line: 0, col: 0, }, },
    vst: [],
  }
}

///|
/// The first line of the block that starts with `pre`, or "" when there is
/// none. A missing line is the failure a caller wants to see, not an index
/// panic.
fn line_with0521(lines : Array[String], pre : String) -> String {
  let mut out = ""
  for l in lines {
    if l.has_prefix(pre) {
      out = l
    }
  }
  out
}

///|
/// How many rows start with `pre`. The family rows must appear once per family
/// that spoke and never twice, so counting is the assertion.
fn count_rows0521(lines : Array[String], pre : String) -> Int32 {
  let mut n = 0
  for l in lines {
    if l.has_prefix(pre) {
      n += 1
    }
  }
  n
}

///|
/// The call counters AGGREGATE across files, which is the only way the scan's
/// tree-wide share can be a ratio of two tree-wide numbers. Two files, 3 of 7
/// checked: the block reports the sums and the share between them.
test "the call counters sum across files" {
  let vs = [mk_v0521([], 3, 2), mk_v0521([], 4, 1)]
  let s = @sa.aggregate(vs)
  assert_eq(s.n_calls, 7)
  assert_eq(s.n_checked, 3)
  let line = line_with0521(@sa.metrics_lines(vs, s, 2), "METRICS\tcalls")
  assert_true(line.contains("sites=7"))
  assert_true(line.contains("checked=3"))
  assert_true(line.contains("not-verified=4"))
}

///|
/// 3 of 7 is 42.857...%, printed as 42.8 by TRUNCATION. Truncation rather than
/// rounding is the safe direction for a coverage figure: 42.8 never overstates
/// what the analyzer checked, and a reader who rounds it back up lands on the
/// true value rather than above it.
test "the checked share truncates rather than rounding up" {
  let vs = [mk_v0521([], 7, 3)]
  let s = @sa.aggregate(vs)
  let line = line_with0521(@sa.metrics_lines(vs, s, 1), "METRICS\tcalls")
  assert_true(line.contains("checked-share=42.8%"))
}

///|
/// "0 of 0" is NOT 0%. A tree with no call site has no adequacy figure at all,
/// and printing zero would read as "checked nothing" on a file that had nothing
/// to check.
test "no call site reports n/a, not a percentage" {
  let vs = [mk_v0521([], 0, 0)]
  let s = @sa.aggregate(vs)
  let line = line_with0521(@sa.metrics_lines(vs, s, 1), "METRICS\tcalls")
  assert_true(line.contains("checked-share=n/a"))
}

///|
/// THE IDENTITY. `high + low + undecided` is the count of findings the block
/// saw, and it must equal `actionable + notices` from the SUMMARY line above it
/// -- the two are different descriptions of one set, so a disagreement would be
/// a tool reporting one number in two places and meaning two things.
test "the confidence totals equal actionable plus notices" {
  let findings : Array[@report.Report] = [
    mk_report(@core.FUndefinedName),
    mk_report(@core.FOpMismatch),
    mk_scope_limit0521(),
  ]
  let vs = [mk_v0521(findings, 0, 0)]
  let s = @sa.aggregate(vs)
  let line = line_with0521(@sa.metrics_lines(vs, s, 1), "METRICS\tfindings")
  // one high (OpMismatch), one low (UndefinedName), one undecided (scope limit)
  assert_true(line.contains("total=3"))
  assert_true(line.contains("high=1"))
  assert_true(line.contains("low=1"))
  assert_true(line.contains("undecided=1"))
  assert_eq(s.actionable + s.notices, 3)
}

///|
/// The `undecided` column IS the scope-limit count, so the block is a
/// breakdown of a number the SUMMARY already prints rather than a new total
/// that could disagree with it.
test "the undecided column is the scope-limit count" {
  let findings : Array[@report.Report] = [
    mk_scope_limit0521(),
    mk_scope_limit0521(),
    mk_report(@core.FOpMismatch),
  ]
  let vs = [mk_v0521(findings, 0, 0)]
  let s = @sa.aggregate(vs)
  let lines = @sa.metrics_lines(vs, s, 1)
  let line = line_with0521(lines, "METRICS\tfindings")
  assert_true(line.contains("undecided=2"))
  // and the two scope limits are exactly the `notices` the SUMMARY counts
  assert_eq(s.notices, 2)
}

///|
/// A family that did not speak gets NO row, and a family that did gets exactly
/// one. Without that, a twelve-row table would be printed for every tree and
/// eleven of the rows would say `total=0` -- a table whose length is fixed is a
/// table a reader stops reading.
test "only the families that spoke get a row" {
  let findings : Array[@report.Report] = [
    mk_report(@core.FOpMismatch),
    mk_report(@core.FOpMismatch),
  ]
  let vs = [mk_v0521(findings, 0, 0)]
  let s = @sa.aggregate(vs)
  let lines = @sa.metrics_lines(vs, s, 1)
  // exactly one family row
  assert_eq(count_rows0521(lines, "METRICS\tfamily"), 1)
  // and it is the one that spoke, with its severity and its count
  let row = line_with0521(lines, "METRICS\tfamily")
  assert_true(row.contains("MSA-008"))
  assert_true(row.contains("severity=error"))
  assert_true(row.contains("total=2"))
}

///|
/// The read line is the same ratio the PARSED line prints, from the same two
/// numbers, so a reader who checks one against the other always agrees. `n_files`
/// is the tree the scan claimed to walk, not the number of verdicts, so a file
/// that produced no verdict still counts against coverage.
test "the read line counts against the tree, not the verdicts" {
  let vs = [mk_v0521([], 0, 0)]
  let s = @sa.aggregate(vs)
  // one verdict, but the scan says it walked four files
  let line = line_with0521(@sa.metrics_lines(vs, s, 4), "METRICS\tread")
  assert_true(line.contains("files=4"))
  assert_true(line.contains("parsed=1"))
  assert_true(line.contains("understood=25.0%"))
}
