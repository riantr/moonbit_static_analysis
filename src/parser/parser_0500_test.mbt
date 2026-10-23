// parser_0500_test.mbt -- the parser's own deliberate exclusion is a notice.
//
// This is the END-TO-END shape of the fix: the message is the one the parser
// really emits for a `match`, produced by `note_skip`, and the predicate is
// asked about the report the parser really built. Spelling the message out in
// the test instead would prove only that a literal agrees with a literal.

///|
fn fparse_reports(reports : Array[@report.Report]) -> Array[@report.Report] {
  let out : Array[@report.Report] = []
  for rep in reports {
    if rep.family == @core.FParse {
      out.push(rep)
    }
  }
  out
}

///|
/// A `match` is read but not analysed. That is a declared scope limit, so it
/// is a notice -- and it is rendered `notice:`, not `error:`.
test "the match exclusion the parser really emits is a notice" {
  let r = @parser.parse(
    "fn f(x : Int) -> Int {\n  match x {\n    0 => 1\n    _ => 2\n  }\n}\n",
  )
  let fps = fparse_reports(r.reports)
  assert_true(fps.length() > 0)
  for rep in fps {
    assert_true(rep.is_notice())
    assert_eq(rep.severity_label(), "notice")
    assert_true(rep.render().contains(" - notice: "))
    assert_false(rep.render().contains(" - error: "))
  }
}

///|
/// The parser also records its deliberate skips in `skips`, and the pipeline
/// uses that list to tell a skip from a read failure. The two answers must
/// agree: a report that the parser lists as a skip is a notice, and a report
/// it does not is not.
test "the parser's own skip list and the notice predicate agree" {
  let r = @parser.parse(
    "fn f(x : Int) -> Int {\n  match x {\n    0 => 1\n    _ => 2\n  }\n}\n",
  )
  assert_true(r.skips.length() > 0)
  for rep in fparse_reports(r.reports) {
    let listed = r.skips.contains(rep.message)
    assert_eq(listed, rep.is_notice())
  }
}

///|
/// A genuine read failure is not a notice. The parser's `err()` is the other
/// producer of FParse, and it reports something wrong with the file.
test "a genuine read failure is NOT a notice" {
  let r = @parser.parse("fn f( {\n")
  let fps = fparse_reports(r.reports)
  assert_true(fps.length() > 0)
  for rep in fps {
    assert_false(rep.is_notice())
    assert_eq(rep.severity_label(), "error")
  }
}
