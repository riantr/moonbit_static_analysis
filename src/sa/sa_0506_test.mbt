// test: which notices get a LINE of the reader's screen, and which are counted.
//
// 0506. The analyzer rendered a notice for every construct it reads past, and
// on the pinned core corpus that was 10,096 notices: the OLD rendering -- the
// per-file cap as it ships -- was 9,128 lines of output to say 28 things, and
// with the cap lifted, so that every notice is on a line of its own, it is
// 11,223. 0506 prints only the notices that can HIDE a
// finding and counts the rest by shape.
//
// The rule is a POSITION -- the notice's region lies inside some function's
// extent -- and not a wording. That is the whole point of this file: the SAME
// message is printed in one position and aggregated in another, so a rule
// keyed on the wording would be wrong about one of them.
//
// The geometry itself is pinned in `src/walk/walk_0506_test.mbt`, where the
// extents live. What is pinned HERE is the consequence: which set a notice
// lands in, and that the two sets add up to the notices there are.
//
// THE HIDING LIST HOLDS REGIONS, NOT EXTENTS. `@walk.hiding_spans` returns the
// unread regions that lie inside some function's extent -- the regions
// themselves -- so a notice is in the printed set when its OWN span is one of
// them. The spans are the same value because the frontend records a region
// and its notice at the same place.

///|
/// A notice: an FParse whose message carries the scope-limit marker.
fn mk_notice(msg : String, line : Int32) -> @report.Report {
  @report.Report::{
    family: @core.FParse,
    lenses: [@core.LStructural],
    message: msg,
    span: { start: @core.pos(line, 1), end: @core.pos(line, 2), },
    vst: [],
  }
}

///|
/// A defect: a real finding, not a scope limit.
fn mk_defect(line : Int32) -> @report.Report {
  @report.Report::{
    family: @core.FUndefinedName,
    lenses: [@core.LStructural],
    message: "no visible binding for 'x'",
    span: { start: @core.pos(line, 1), end: @core.pos(line, 2), },
    vst: [],
  }
}

///|
/// The message the `if` expression exclusion carries. Used by more than one
/// row below on purpose: the same message has to be able to land in either
/// set.
fn if_msg() -> String {
  "if expression is outside the analyzed subset; it was read but not analysed"
}

///|
/// The message the `test` declaration exclusion carries.
fn test_msg() -> String {
  "test declaration is outside the analyzed subset; its body was not analyzed"
}

///|
/// A DEFECT is printed, whatever it is. The aggregation is about notices: a
/// defect is the one thing the reader came for, and dropping one would hide
/// the very finding the tool exists to report.
test "0506: a defect is printed, never aggregated" {
  let (printed, aggregated) = @sa.split_findings([mk_defect(3)], [])
  assert_eq(printed.length(), 1)
  assert_eq(aggregated.length(), 0)
}

///|
/// A notice whose region IS a hiding region can hide a finding, so it is
/// printed per line.
test "0506: a notice inside a function's extent is printed per line" {
  let n = mk_notice(if_msg(), 12)
  let hiding : Array[@core.Span] = [n.span]
  let (printed, aggregated) = @sa.split_findings([n], hiding)
  assert_eq(printed.length(), 1)
  assert_eq(aggregated.length(), 0)
}

///|
/// A notice whose region is NOT a hiding region is in no function's hole
/// list, so it hides nothing, and it is counted instead of printed.
test "0506: a notice outside every function's extent is aggregated" {
  let n = mk_notice(if_msg(), 30)
  let other = mk_notice(test_msg(), 12)
  let hiding : Array[@core.Span] = [other.span]
  let (printed, aggregated) = @sa.split_findings([n], hiding)
  assert_eq(printed.length(), 0)
  assert_eq(aggregated.length(), 1)
}

///|
/// THE SHARP CONTROL. The SAME message, in two positions, in one list: one
/// printed, one aggregated. A rule keyed on the message would put both in the
/// same set, and it would be wrong about one of them. This is the row that
/// says the classification is a position and not a wording.
test "0506: the SAME message is printed inside a function and aggregated outside it" {
  let inside = mk_notice(if_msg(), 12)
  let outside = mk_notice(if_msg(), 30)
  let hiding : Array[@core.Span] = [inside.span]
  let (printed, aggregated) = @sa.split_findings([inside, outside], hiding)
  assert_eq(printed.length(), 1)
  assert_eq(aggregated.length(), 1)
  assert_true(printed[0].span == inside.span)
  assert_true(aggregated[0].span == outside.span)
}

///|
/// AND THE CONTROL FOR THE CONTROL: a DIFFERENT message in the SAME position
/// as the one above is treated the same way. The split does not read the
/// message at all.
test "0506: a different message in the same position is treated the same way" {
  let test_decl = mk_notice(test_msg(), 30)
  let if_expr = mk_notice(if_msg(), 12)
  let hiding : Array[@core.Span] = [if_expr.span]
  let (printed, aggregated) = @sa.split_findings([test_decl, if_expr], hiding)
  assert_eq(printed.length(), 1)
  assert_eq(aggregated.length(), 1)
  assert_eq(printed[0].message, if_msg())
}

///|
/// THE MEMBERSHIP TEST IS EXACT. A region's identity is where it is, and two
/// exclusions on the same line are two DIFFERENT regions. A test that compared
/// line numbers would put both of them in the same set, and it would be
/// wrong about one of them.
test "0506: two exclusions on the same line are two different regions" {
  let one = @core.span_at(12, 1, 4)
  let other = @core.span_at(12, 7, 2)
  assert_true(@sa.is_hiding(one, [one]))
  assert_false(@sa.is_hiding(other, [one]))
}

///|
/// The aggregate counts by SHAPE, and the shape is the whole message -- the
/// message is what says which construct was not read, so a breakdown that
/// lost it would not tell the reader what the analyzer skipped.
test "0506: the aggregate counts by shape" {
  let rows = @sa.count_by_shape([
    mk_notice(if_msg(), 1),
    mk_notice(if_msg(), 2),
    mk_notice(test_msg(), 3),
  ])
  assert_eq(rows.length(), 2)
  assert_eq(rows[0].0, if_msg())
  assert_eq(rows[0].1, 2)
  assert_eq(rows[1].1, 1)
}

///|
/// And it is sorted, biggest first: the reader's eye goes to the shape that
/// accounts for the most.
test "0506: the aggregate is sorted, biggest first" {
  let rows = @sa.count_by_shape([
    mk_notice(test_msg(), 1),
    mk_notice(if_msg(), 2),
    mk_notice(test_msg(), 3),
    mk_notice(test_msg(), 4),
  ])
  assert_eq(rows.length(), 2)
  assert_eq(rows[0].0, test_msg())
  assert_eq(rows[0].1, 3)
  assert_eq(rows[1].0, if_msg())
  assert_eq(rows[1].1, 1)
}

///|
/// THE TWO SETS ADD UP. A notice is either printed or counted, and never
/// both and never neither -- which is what makes the `NOTICES` table's
/// reconciliation possible: the rows plus the printed notices are the
// SUMMARY's notice count.
test "0506: the printed set and the aggregated set add up to the notices" {
  let defect = mk_defect(1)
  let inside = mk_notice(if_msg(), 12)
  let outside = mk_notice(if_msg(), 30)
  let other = mk_notice(test_msg(), 40)
  let all = [defect, inside, outside, other]
  let hiding : Array[@core.Span] = [inside.span]
  let (printed, aggregated) = @sa.split_findings(all, hiding)
  assert_eq(printed.length() + aggregated.length(), all.length())
  // One defect and one hiding notice are printed; two notices that hide
  // nothing are aggregated.
  assert_eq(printed.length(), 2)
  assert_eq(aggregated.length(), 2)
}

///|
/// `--show-notices` PRINTS EVERY NOTICE and aggregates nothing. The flag is
/// the whole per-line list, and it exists so that the complete list stays
/// reachable for every measurement that reads it.
test "0506: --show-notices prints every notice and aggregates nothing" {
  let inside = mk_notice(if_msg(), 12)
  let outside = mk_notice(if_msg(), 30)
  let hiding : Array[@core.Span] = [inside.span]
  let (printed, aggregated) = @sa.partition_findings(
    [inside, outside],
    hiding,
    true,
  )
  assert_eq(printed.length(), 2)
  assert_eq(aggregated.length(), 0)
}

///|
/// AND THE DEFAULT IS THE SPLIT, with the same inputs: the flag is the only
/// difference between the two renderings, so the flag changing the split is
/// what makes it worth having.
test "0506: the default splits the same findings the flag prints whole" {
  let inside = mk_notice(if_msg(), 12)
  let outside = mk_notice(if_msg(), 30)
  let hiding : Array[@core.Span] = [inside.span]
  let (printed, aggregated) = @sa.partition_findings(
    [inside, outside],
    hiding,
    false,
  )
  assert_eq(printed.length(), 1)
  assert_eq(aggregated.length(), 1)
}

///|
/// THE TABLE'S TOTAL LINE RECONCILES: it carries the tree's notice count, the
/// number printed per line and the number aggregated, and the last two add up
/// to the first. A reader -- and a gate -- can check that nothing was dropped
/// on the way.
test "0506: the NOTICES table's TOTAL line reconciles" {
  let lines = @sa.notice_lines(5, 2, [mk_notice(test_msg(), 1)], false)
  assert_eq(lines.length(), 2)
  let total = lines[0]
  assert_true(total.has_prefix("NOTICES\tTOTAL\t"))
  assert_true(total.contains("notices=5"))
  assert_true(total.contains("printed=2"))
  assert_true(total.contains("aggregated=1"))
}

///|
/// AND THE ROWS ADD UP TO THE AGGREGATED COUNT: one row per shape, and the
/// rows' counts sum to the number the TOTAL line says was aggregated.
test "0506: the NOTICES table's rows add up to the aggregated count" {
  let agg = [
    mk_notice(test_msg(), 1),
    mk_notice(test_msg(), 2),
    mk_notice(if_msg(), 3),
  ]
  let lines = @sa.notice_lines(5, 2, agg, false)
  // One TOTAL line and one row per shape.
  assert_eq(lines.length(), 3)
  // The rows are `key=value`, so a gate can read them without knowing the
  // shape names.
  assert_true(lines[1].has_prefix("NOTICES\tcount=2\t"))
  assert_true(lines[1].contains(test_msg()))
  assert_true(lines[2].has_prefix("NOTICES\tcount=1\t"))
  assert_true(lines[2].contains(if_msg()))
}

///|
/// THE TABLE IS NOT SHOWN TWICE. With `--show-notices` every notice is
/// already on a line of its own, and the table would be a second count of
/// the same facts.
test "0506: --show-notices prints no table" {
  let agg = [mk_notice(test_msg(), 1)]
  assert_eq(@sa.notice_lines(5, 2, agg, true).length(), 0)
}

///|
/// AND A TREE WITH NO NOTICES HAS NOTHING TO SAY ABOUT NOTICES.
test "0506: a tree with no notices prints no table" {
  assert_eq(@sa.notice_lines(0, 0, [], false).length(), 0)
}

///|
/// AND A TREE WHOSE EVERY NOTICE CAN HIDE A FINDING still gets its TOTAL
/// line, with no rows: "notices=1144, printed=1144, aggregated=0" tells the
/// reader how many notices there were and that all of them were printed.
test "0506: a tree with nothing to aggregate still prints its TOTAL line" {
  let lines = @sa.notice_lines(1144, 1144, [], false)
  assert_eq(lines.length(), 1)
  assert_true(lines[0].contains("notices=1144"))
  assert_true(lines[0].contains("printed=1144"))
  assert_true(lines[0].contains("aggregated=0"))
}
