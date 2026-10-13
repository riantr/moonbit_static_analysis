///|
/// A lambda as a PARAMETER DEFAULT: `sync? : T = (...) => ...`.
///
/// Settled with the toolchain, not inferred: `_verify/grammar_probe.ps1`, one
/// form per package with a deliberately broken canary alongside, both 0 errors
/// from `moon check`.
///
///   fn maker(sync? : (Int, Int) -> Unit = (_w, _m,) => (),) -> Int { 1 }
///   fn maker2(sync? : (Int) -> Unit = (_w) => ()) -> Int { 1 }
///
/// Before the fix: SELF-FAIL, `expected ')'` -- on BOTH the single-line and the
/// multi-line default.
///
/// The control below matters as much as the tests above it. A function-typed
/// parameter with NO default already parsed, so this is not about function
/// types at all; had the control been absent, the obvious wrong conclusion
/// ("function-typed parameters are unsupported") would have looked confirmed.
test "0431: a single-line lambda default parses" {
  let r = @parser.parse(
    "fn maker2(sync? : (Int) -> Unit = (_w) => ()) -> Int { 1 }\n",
  )
  assert_eq(r.first_error, 0)
  assert_eq(r.reports.length(), 1)
  assert_eq(
    r.reports[0].message,
    "short lambda is outside the analyzed subset; it was read but not analysed",
  )
}

///|
/// WHAT "PARSES" MEANS HERE, because the obvious assertion is the wrong one.
///
/// `reports.length() == 0` is NOT the contract, and an early draft of this file
/// asserted it. The lambda BODY is still skipped, so the fix emits the standard
/// "short lambda is outside the analyzed subset" notice -- one report, and
/// `first_error` stays 0 because `note_skip` deliberately does not move the
/// trusted-region boundary (see its definition).
///
/// The distinction is the whole point: `first_error == 0` means the rest of the
/// file's findings are still evidence, while the notice says what was not
/// analysed. Asserting zero reports would have "passed" only by swallowing the
/// lambda SILENTLY, which is the behaviour this project treats as the worse
/// failure. The remaining tests assert the report is this notice specifically.
///
/// Returns a verdict rather than asserting, because `assert_eq` raises and a
/// bare helper in a test file may not raise (E4122). The caller does the
/// asserting, so a failure still names the test that caught it.
fn only_lambda_notices(r : @parser.ParseResult) -> Bool {
  if r.reports.length() == 0 {
    return false
  }
  for rep in r.reports {
    if rep.message !=
      "short lambda is outside the analyzed subset; it was read but not analysed" {
      return false
    }
  }
  return true
}

///|
/// The multi-line spelling, which is what wzzc-dev/moui 0.1.12 actually writes
/// (`backend/windows/windows_backend.mbt:125-131` and three sibling backends):
/// the lambda's parameter list is split across lines and closed with `) => (),`
/// on its own line.
test "0431: a multi-line lambda default parses" {
  let r = @parser.parse(
    "fn maker(\n  sync? : (Int, Int) -> Unit = (\n    _w,\n    _m,\n  ) => (),\n) -> Int { 1 }\n",
  )
  assert_eq(r.first_error, 0)
  assert_true(only_lambda_notices(r))
}

///|
/// A BRACE-bodied default, the third spelling in the corpus
/// (`services/platform_services.mbt:186`): `notify? : T = _request => { ... }`.
/// It needs `skip_braces` rather than the comma boundary, and a wrong skip there
/// would swallow the rest of the parameter list.
test "0431: a brace-bodied lambda default parses and does not eat the params" {
  let r = @parser.parse(
    "fn notify_svc(\n  tag? : Int = 0,\n  notify? : (Int) -> Unit = _request => {\n    tag\n  },\n  tail? : Int = 7,\n) -> Int { tail }\n",
  )
  assert_eq(r.first_error, 0)
  assert_true(only_lambda_notices(r))
  // The parameter AFTER the lambda default must still be present. A skip that
  // ran past it would leave `tail` unparsed and this count short.
  match r.tree.body[0].kind {
    @ast.SFunc(_, params, _, _, _) => assert_eq(params.length(), 3)
    _ => ()
  }
}

///|
/// CONTROL. The same signature with no default at all. If this one ever goes
/// red, the defect is in function-TYPE parsing and the three tests above are
/// measuring the wrong thing.
test "0431 control: a function-typed parameter with no default already parsed" {
  let r = @parser.parse("fn taker(cb : (Int) -> Unit) -> Int { 1 }\n")
  assert_eq(r.first_error, 0)
  assert_eq(r.reports.length(), 0)
}

///|
/// CONTROL. An ordinary non-lambda default, which the `parse_expr` path already
/// handled. It guards the else-branch: a fix that sent ordinary defaults down
/// the lambda path would show up here.
test "0431 control: an ordinary default value still parses" {
  let r = @parser.parse("fn sized(n? : Int = 7) -> Int { n }\n")
  assert_eq(r.first_error, 0)
  assert_eq(r.reports.length(), 0)
}
