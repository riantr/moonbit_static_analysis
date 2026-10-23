// lexer_0500_test.mbt -- the lexer's own ParseError is a genuine defect, not a
// notice.
//
// The lexer's eight malformed-literal reports share the FParse family with the
// analyzer's deliberate exclusions, and they are the opposite of one: an
// unterminated literal is something wrong with the file, not a limit of what
// this analyzer reads. The label it gets decides whether a reader is told
// their code is broken.
//
// The message is taken from the lexer's OWN output here, not from a literal in
// the test: a test that spells out the message it expects proves that the
// test agrees with itself, not that the tool agrees with the test.

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
/// An unterminated string literal is the analyzer's failure to read the file,
/// not a declared scope limit.
test "an unterminated string literal is a defect, not a notice" {
  let (_, _, reports) = @lexer.lex("fn f() {\n  let s = \"unterminated\n}\n")
  let fps = fparse_reports(reports)
  assert_true(fps.length() > 0)
  for rep in fps {
    assert_false(rep.is_notice())
    assert_eq(rep.severity_label(), "error")
    assert_true(rep.render().contains(" - error: "))
  }
}

///|
/// The control: a source the lexer reads cleanly produces no FParse at all, so
/// the assertion above is about a report the lexer really made and not about a
/// vacuously empty list.
test "a clean source produces no parse error at all" {
  let (_, _, reports) = @lexer.lex("fn f() -> Int {\n  1\n}\n")
  assert_eq(fparse_reports(reports).length(), 0)
}
