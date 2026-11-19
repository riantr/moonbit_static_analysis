// sa_0616_test.mbt -- the SPLIT of the unverified call sites, as a pure function.
//
// 0616. `n_calls - n_checked` was ONE number for FIVE different reasons, and
// the sentence beside it named TWO of them -- the two that REPORT. The other
// three are SILENT, and they are the majority, so a reader of the published
// remainder could not tell which part of it was which.
//
// The five counters are the only way to know, and they have to be CHECKED
// rather than trusted:
//   - the row has to carry all five, or a reason has gone missing;
//   - the row's own `sum` has to be the arithmetic sum of the five, or the row
//     is printing something other than what it says;
//   - the row's `not-verified` has to be the remainder the `calls` row prints,
//     or the five do not add up to the thing they split.
//
// AND THE SENTENCE IS PINNED TOO. The `calls` row used to say "not-verified =
// callee not callable, or name unresolved", and it was wrong. A row that
// carries the five reasons must say so.

///|
/// A verdict with the given call counters and split. `metrics_lines` reads
/// only these.
fn mk_v0616(
  calls : Int32,
  checked : Int32,
  sig_unknown : Int32,
  not_callable : Int32,
  unresolved : Int32,
  method_call : Int32,
  dotdot_call : Int32,
) -> @sa.Verdict {
  @sa.Verdict::{
    path: "a.mbt",
    kind: ".mbt",
    findings: [],
    parsed: true,
    reason: "",
    total: 0,
    notices: 0,
    region_line: 0,
    unreliable: 0,
    hiding: [],
    n_unchecked: 0,
    n_calls: calls,
    n_checked: checked,
    n_sig_available: 0,
    n_arity_agrees: 0,
    n_unknown_fn: sig_unknown,
    n_not_callable: not_callable,
    n_unresolved: unresolved,
    n_method_call: method_call,
    n_dotdot_call: dotdot_call,
  }
}

///|
/// The row that starts with `pre`. The LAST one, so a row that shadows
/// another cannot hide behind it.
fn row0616(lines : Array[String], pre : String) -> String {
  let mut out = ""
  for l in lines {
    if l.has_prefix(pre) {
      out = l
    }
  }
  out
}

///|
/// Whether the row carries `key=value` as a WHOLE field.
///
/// THE TAB AFTER THE VALUE IS PART OF THE TEST. Without it, `sum=4` would be
/// found inside `not-verified=4`, and a row that printed the wrong field
/// would pass. The tab makes the match a field match.
///
/// AND THE ROW IS NOT PARSED BACK INTO NUMBERS. The toolchain has no
/// `String::parse_int` for this -- the function is `@string.parse_int`, it
/// takes a `StringView`, it RAISES, and reaching it would mean adding an
/// import to this package for one test helper. So the EXPECTATION is computed
/// here, from the same inputs the verdict was built from, and the row is
/// checked against it. That is the stronger form of the assertion anyway: the
/// row has to agree with the arithmetic, not with a second reading of itself.
fn has_field0616(row : String, key : String, value : Int32) -> Bool {
  row.contains(key + "=" + value.to_string() + "\t")
}

///|
/// THE ROW EXISTS, AND IT NAMES ALL FIVE. A reason that went missing is the
/// exact defect this increment exists to fix, so the row's own field list is
/// the assertion.
test "0616: the unverified-split row names all five reasons" {
  let vs = [mk_v0616(7, 3, 1, 1, 1, 1, 0)]
  let s = @sa.aggregate(vs)
  let row = row0616(@sa.metrics_lines(vs, s, 1), "METRICS\tunverified-split")
  assert_true(row != "")
  assert_true(row.contains("sig-unknown="))
  assert_true(row.contains("not-callable="))
  assert_true(row.contains("unresolved="))
  assert_true(row.contains("method="))
  assert_true(row.contains("dotdot="))
}

///|
/// THE SUM IS THE SUM. The row prints a `sum` field, and it has to be the
/// arithmetic sum of the five -- otherwise the row is printing a number that
/// is not the sum of the numbers beside it.
test "0616: the split row's sum is the sum of the five reasons" {
  let vs = [mk_v0616(7, 3, 1, 1, 1, 1, 0)]
  let s = @sa.aggregate(vs)
  let row = row0616(@sa.metrics_lines(vs, s, 1), "METRICS\tunverified-split")
  let expected = 1 + 1 + 1 + 1 + 0
  assert_true(has_field0616(row, "sum", expected))
  // AND EACH OF THE FIVE, at the value it was given. A row that printed the
  // right sum over the wrong five would pass the line above.
  assert_true(has_field0616(row, "sig-unknown", 1))
  assert_true(has_field0616(row, "not-callable", 1))
  assert_true(has_field0616(row, "unresolved", 1))
  assert_true(has_field0616(row, "method", 1))
  assert_true(has_field0616(row, "dotdot", 0))
}

///|
/// AND THE SUM IS THE REMAINDER. This is the identity that makes the row
/// check itself: the five reasons have to add up to the very number they
/// split, or the split is of something else.
test "0616: the split row's sum is the remainder the calls row prints" {
  let vs = [mk_v0616(7, 3, 1, 1, 1, 1, 0)]
  let s = @sa.aggregate(vs)
  let lines = @sa.metrics_lines(vs, s, 1)
  let split = row0616(lines, "METRICS\tunverified-split")
  let calls = row0616(lines, "METRICS\tcalls")
  assert_true(has_field0616(split, "sum", 7 - 3))
  assert_true(has_field0616(calls, "not-verified", 7 - 3))
}

///|
/// THE SENTENCE, CORRECTED. The `calls` row used to claim the remainder was
/// two classes, and it was wrong: there are five. A row that carries the five
/// reasons and does not say so is the old defect wearing a new row.
test "0616: the calls row no longer claims the remainder is two classes" {
  let vs = [mk_v0616(7, 3, 1, 1, 1, 1, 0)]
  let s = @sa.aggregate(vs)
  let calls = row0616(@sa.metrics_lines(vs, s, 1), "METRICS\tcalls")
  assert_true(calls.contains("FIVE reasons"))
  assert_true(!calls.contains("callee not callable, or name unresolved"))
}

///|
/// THE TWO THAT REPORT ARE NAMED AS THE TWO THAT REPORT. The row says so in
/// its own text, and a reader who has to work that out from five numbers is
/// the reader this increment is for.
test "0616: the split row says which of the five reasons report" {
  let vs = [mk_v0616(7, 3, 1, 1, 1, 1, 0)]
  let s = @sa.aggregate(vs)
  let row = row0616(@sa.metrics_lines(vs, s, 1), "METRICS\tunverified-split")
  assert_true(row.contains("REPORT"))
  assert_true(row.contains("SILENT"))
}

///|
/// A TREE WITH NO CALL SITE. The remainder is zero and so is the split, and
/// the row has to say zero -- not "n/a", and not nothing.
test "0616: a tree with no call site splits to zero" {
  let vs = [mk_v0616(0, 0, 0, 0, 0, 0, 0)]
  let s = @sa.aggregate(vs)
  let row = row0616(@sa.metrics_lines(vs, s, 1), "METRICS\tunverified-split")
  assert_true(has_field0616(row, "sum", 0))
  assert_true(has_field0616(row, "not-verified", 0))
}
