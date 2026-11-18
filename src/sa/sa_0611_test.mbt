// 0611: THE RENDERER'S PUBLIC SURFACE -- the parts `moon test` had never
// reached, and the one defect that came out of reaching them.
//
// THE MEASUREMENT THIS FILE ANSWERS. `moon coverage analyze` put
// `src/sa/main.mbt` at 38.1%: 242 uncovered lines. Two hundred and thirty
// four of them are inside an `async fn` -- `scan`, `analyze`, `collect`,
// `locate`, `emit_mmd`, `collect_iface_symtabs`, `collect_private_symtabs`,
// `fetch_moon_mod_imports`, `read_or`, `is_dir`, `run_exit_code` -- or
// behind a private `fn` only those call.
//
// AND THAT PART IS NOT A PRODUCT DEFECT, it is a HARNESS FACT, and it was
// MEASURED rather than assumed:
//
//   * `moon test` cannot call an async function. A test body that calls one
//     fails to COMPILE: "cannot call async function in non-async function",
//     error 4149. There is no `async` test form either -- `test "x" async
//     {` is a parse error ("unexpected token `async`, you may expect `{`"),
//     and `async test "x" {` does not parse at all.
//   * so `scan` -- the public entry point, the thing `moonx
//     riantr/moonbit_static_analysis@latest <target>` runs -- is not
//     reachable from the test harness, and the release gate is what covers
//     it. That is the same shape as the five packages that have no test file
//     of their own: the harness cannot see them, so their coverage number
//     says nothing about their quality.
//
// WHAT IS LEFT IS WHAT A TEST CAN REACH, and it is not nothing: eight
// uncovered lines sit in functions that are PUBLIC and SYNCHRONOUS --
// `count_by_shape`'s tie branch, the severity spelling the adequacy table
// prints, the agreement share, the per-signature figure, the closing brace
// of a `moon.mod` import block, and the coordinate segment rules.
//
// AND FOLLOWING THE LAST ONE FOUND A DEFECT: a `moon.mod` whose import block
// is written on ONE LINE is valid syntax -- MEASURED against the toolchain's
// own parser, which reads `import { "pkg" }` and complains about the VERSION
// rather than about the syntax -- and this reader MISSED it, silently, so the
// dependency was never fetched and the scan went on as if its types were
// present. That is the 0.4.3 failure mode this function was rewritten to
// end, and the row below is its pin.

///|
/// A report for a given family with a given message. `count_by_shape`
/// counts by the WHOLE message -- the shape is the message, because the
/// message says which construct was not read -- and the adequacy table reads
/// the family, so the fixture carries both.
fn mk_notice0611(msg : String) -> @report.Report {
  mk_report0611(@core.FParse, msg)
}

///|
/// A report for a given family. The message is a plain sentence rather than
/// one of the scope-limit shapes, so the report is a finding and not a
/// notice -- which is what the severity rows are about.
fn mk_report0611(family : @core.Family, msg : String) -> @report.Report {
  @report.Report::{
    family,
    lenses: [@core.LStructural],
    message: msg,
    span: { start: { line: 0, col: 0, }, end: { line: 0, col: 0, }, },
    vst: [],
  }
}

///|
/// A parsed verdict carrying the given findings and the given call counters.
/// `metrics_lines` reads the findings, the counters and the Summary, and
/// nothing else.
fn mk_v0611(
  findings : Array[@report.Report],
  calls : Int32,
  checked : Int32,
  sig_available : Int32,
  arity_agrees : Int32,
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
    n_sig_available: sig_available,
    n_arity_agrees: arity_agrees,
  }
}

///|
/// The first line of the block that starts with `pre`, or "" when there is
/// none. A missing line is the failure a caller wants to see, not an index
/// panic.
fn line_with0611(lines : Array[String], pre : String) -> String {
  let mut out = ""
  for l in lines {
    if l.has_prefix(pre) {
      out = l
    }
  }
  out
}

///|
/// THE TIE IN THE SHAPE TABLE. The comparator has a branch for two shapes
/// with the SAME count, and it returns 0 and lets the sort decide -- and
/// nothing took that branch, so it was never covered and never behaved.
///
/// AND THE ORDER DOES NOT MOVE. The rows come out of a `Map`, and the same
/// input produces the same iteration order every time, so a reader who sees
/// the table twice sees the same table. A table that reshuffled between runs
/// could not be diffed against yesterday's, and the whole point of counting
/// notices by shape is that two runs are comparable.
test "0611: two shapes with the same count are both present, and the order does not move" {
  let a = "if expression is outside the analyzed subset"
  let b = "test declaration is outside the analyzed subset"
  let rows = @sa.count_by_shape([mk_notice0611(a), mk_notice0611(b)])
  assert_eq(rows.length(), 2)
  assert_eq(rows[0].1, 1)
  assert_eq(rows[1].1, 1)
  let again = @sa.count_by_shape([mk_notice0611(a), mk_notice0611(b)])
  assert_eq(again.length(), 2)
  assert_eq(rows[0].0, again[0].0)
  assert_eq(rows[1].0, again[1].0)
}

///|
/// The line of the block that starts with `pre` AND mentions `id`, or "" when
/// there is none. The block prints one row per family that spoke, so a row
/// has to be found by its family rather than by its position.
fn row_for0611(lines : Array[String], pre : String, id : String) -> String {
  let mut out = ""
  for l in lines {
    if l.has_prefix(pre) && l.contains(id) {
      out = l
    }
  }
  out
}

///|
/// THE ADEQUACY TABLE PRINTS THE FAMILY'S OWN SEVERITY, not the label the
/// renderer prints.
///
/// `Report::severity_label` folds in the notice demotion, so a demoted
/// finding prints `notice`; the adequacy table is about the FAMILY, and a
/// family that is a warning is a warning there whatever a particular finding
/// of it was demoted to.
///
/// AND THE SPELLING IS THE FAMILY'S, in words: `warning`, not `Warning` and
/// not `notice`. The table is read by a person and by a gate, and a gate
/// that has to strip a capital letter is a gate that will eventually fail
/// to.
///
/// AND THE SEVERITY IS THE FAMILY'S OWN: `FUnusedLocal` is a warning and
/// `FUndefinedName` is an error, and the table says so -- one row each, in
/// the roster's order.
test "0611: the adequacy table spells the family's own severity" {
  let vs = [
    mk_v0611([mk_report0611(@core.FUnusedLocal, "x")], 0, 0, 0, 0),
    mk_v0611([mk_report0611(@core.FUndefinedName, "y")], 0, 0, 0, 0),
  ]
  let s = @sa.aggregate(vs)
  let lines = @sa.metrics_lines(vs, s, 2)
  let warn = row_for0611(lines, "METRICS\tfamily\t", "MSA-003")
  assert_true(warn.contains("UnusedLocal"))
  assert_true(warn.contains("severity=warning"))
  assert_false(warn.contains("severity=notice"))
  let err = row_for0611(lines, "METRICS\tfamily\t", "MSA-002")
  assert_true(err.contains("UndefinedName"))
  assert_true(err.contains("severity=error"))
}

///|
/// THE AGREEMENT SHARE IS A PERCENTAGE WHEN THERE IS SOMETHING TO AGREE
/// WITH, AND "n/a" WHEN THERE IS NOT.
///
/// Three of four declared arities agree is 75.0%, and the figure is a COUNT
/// of how much of the analyzer's own silence is removable -- not a check, and
/// the line says so. And a tree with no unchecked call that had a declared
/// signature has no agreement figure at all: "0 of 0" would read as "none of
/// them would have been right", which is not what zero means here.
test "0611: the agreement share is a percentage, or n/a when there is none" {
  let none = [mk_v0611([], 0, 0, 0, 0)]
  let s0 = @sa.aggregate(none)
  let l0 = line_with0611(@sa.metrics_lines(none, s0, 1), "METRICS\tiface-sig")
  assert_true(l0.contains("agree-share=n/a"))
  let some = [mk_v0611([], 0, 0, 4, 3)]
  let s1 = @sa.aggregate(some)
  let l1 = line_with0611(@sa.metrics_lines(some, s1, 1), "METRICS\tiface-sig")
  assert_true(l1.contains("available=4"))
  assert_true(l1.contains("agrees=3"))
  assert_true(l1.contains("agree-share=75.0%"))
}

///|
/// THE PER-EXECUTION FIGURE IS "n/a" WHEN NO SIGNATURE WAS EXECUTED, AND A
/// RATE WHEN ONE WAS.
///
/// "0 of 0" is not a ratio: a scan that executed no body has no
/// per-execution figure, and printing zero would read as "the strategy is
/// free" rather than "this tree never entered a function".
///
/// AND THE RATE IS TRUNCATED, not rounded: four executions over two
/// signatures is exactly 2.00, and a figure that never overstates the cost
/// is the safe direction to truncate in.
test "0611: the per-signature figure is n/a without a signature, and a rate with one" {
  let empty = @core.CtxLedger::zero()
  let l0 = @sa.ctx_line(empty)
  assert_true(l0.contains("n/a (no signature was executed)"))
  let ran = @core.CtxLedger::{
    exec: 4,
    sig: 2,
    context: 3,
    shared: 1,
    cuts: 0,
    depth: 5,
  }
  let l1 = @sa.ctx_line(ran)
  assert_true(l1.contains("2.00 executions/signature"))
  assert_true(l1.contains("executions=4"))
  assert_true(l1.contains("signatures=2"))
}

///|
/// A `moon.mod` MAY CLOSE ITS IMPORT BLOCK ON THE SAME LINE as the last
/// coordinate, and the coordinate must still be read.
///
/// The shape is `import {` on one line and the coordinate and the brace on
/// the next, and the reader has to see the coordinate either way: a
/// dependency that is not fetched is a dependency whose types are not in the
/// table, and the scan then reports as if they were.
test "0611: an import block that closes on the coordinate's line is still read" {
  let got = @sa.parse_moon_mod_imports("import {\n  \"a/b\" }\n")
  assert_eq(got.length(), 1)
  assert_eq(got[0], "a/b")
}

///|
/// AND THE WHOLE BLOCK IS ONE LINE, which is valid `moon.mod` syntax.
///
/// MEASURED against the toolchain's OWN parser: handed
/// `import { "moonbitlang/core/error" }` it reports "moon.mod only supports
/// versioned registry dependencies in `import`, found
/// `moonbitlang/core/error`" -- the same complaint the multi-line form gets,
/// which is to say the SYNTAX was read and the COORDINATE was extracted. It
/// is the syntax, not a curiosity.
///
/// AND THE COST OF MISSING IT IS THE 0.4.3 COST: the dependency is not
/// fetched, nothing says so, and the scan continues as if the dependency's
/// types were in the table.
test "0611: an import block written on one line is read" {
  let got = @sa.parse_moon_mod_imports("import { \"a/b\" }\n")
  assert_eq(got.length(), 1)
  assert_eq(got[0], "a/b")
}

///|
/// AND THE MULTI-LINE FORM STILL IS, because the fix for the one-line form
/// must not cost the shape every hand-written `moon.mod` uses.
test "0611: the multi-line import block is still read" {
  let got = @sa.parse_moon_mod_imports(
    "name = \"a/b\"\n\nimport {\n  \"c/d\",\n  \"e/f\",\n}\n",
  )
  assert_eq(got.length(), 2)
  assert_eq(got[0], "c/d")
  assert_eq(got[1], "e/f")
}

///|
/// A COORDINATE SEGMENT THAT IS A SINGLE DOT IS NOT A COORDINATE.
///
/// `a/./b` has three segments and two of them are real, so a segment count
/// alone would accept it -- but the registry's own rule is a path, and a
/// path segment of `.` is the current directory, not a module name. The
/// reader walks the segments by hand so that both facts are visible in the
/// code rather than in a probe.
test "0611: a coordinate segment that is a single dot is not a coordinate" {
  assert_false(@sa.is_module_coord("a/./b"))
  assert_false(@sa.is_module_coord("./a"))
  // AND THE LAST SEGMENT IS CHECKED TOO. The reader walks the segments by
  // hand, so a bad segment in the MIDDLE and a bad segment at the END are
  // two different checks -- and a trailing `.` is the one a path-shaped
  // coordinate ends with.
  assert_false(@sa.is_module_coord("a/b/."))
  // AND THE SHAPES THAT ARE COORDINATES STILL ARE.
  assert_true(@sa.is_module_coord("a/b"))
  assert_true(@sa.is_module_coord("a/b/c"))
}
