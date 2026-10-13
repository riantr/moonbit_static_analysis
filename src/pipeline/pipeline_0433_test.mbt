// Tests for 0.4.30: a `match` subject on the next line, and `defer` as a
// statement.
//
// WHY THESE LIVE HERE AND NOT IN `src/parser`. Both fixes are parse-level, and
// both have parse-level tests in `src/parser/parser_0433_test.mbt`. What the
// parser cannot answer is whether the READS inside these constructs are still
// visible downstream. `pipeline` imports `parser`, so this is the level at
// which the claim is answerable at all.
//
// THE TWO CLAIMS ARE MEASURED BY DIFFERENT MEANS, and the difference is not a
// style choice -- the obvious assertion for the first one is VACUOUS:
//
//   * `defer` -- `parameter 'x' may not be used` is live here. Measured:
//     `fn f(request_id : Int, dead : Int)` with `defer { sink(request_id) }`
//     reports exactly `dead`. So "the deferred body is read" is observable as
//     "the parameter read only inside it is not reported unused".
//
//   * `match` -- that same assertion proves NOTHING. `note_skip` records the
//     match's span as an unread region, `pipeline` passes those spans to the
//     walker, and the walker SKIPS the whole frame audit for any function with
//     an unread region (walk.mbt:602 and the surrounding comment). So a
//     `match` makes UnusedParam go silent for its entire function: a first
//     draft asserted `count_family(r, "UnusedParam") == 0` for a `match` whose
//     subject was skipped, and its control -- the same source with one extra
//     unread parameter -- ALSO returned 0. The positive test was passing
//     because the family had been switched off, not because the read worked.
//
//     The observable that does work is the subject's own resolution:
//     `match\n  missing(c) {` reports `no visible binding for 'missing'`,
//     because the subject is read. If the subject were skipped, that name
//     would never be resolved and the report would not exist. Measured, not
//     inferred.

///|
/// Does any report carry this message? Used where the NAME matters, not just
/// the family: a `count_family(..., "UndefinedName") == 1` would also pass if
/// the one report were about some other undefined name, which is the
/// distinction between "the subject was read" and "something was undefined".
fn has_report(r : @pipeline.PipelineResult, msg : String) -> Bool {
  for rep in r.reports {
    if rep.message.contains(msg) {
      return true
    }
  }
  false
}

///|
/// A `match` subject on the next line is READ: an unknown name in it is
/// resolved and reported. This is the assertion that survived the control
/// above -- it is what a skipped subject cannot produce.
test "0433: a match subject on the next line is read, not skipped" {
  let r = @pipeline.run(
    "fn sub(x : Int) -> Int { x }\nfn caller(c : Int) -> Int {\n  match\n    missing(c) {\n    1 => 2\n    _ => 3\n  }\n}\n",
    "x.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(r.first_error_line, 0)
  assert_eq(count_family(r, "UndefinedName"), 1)
  assert_true(has_report(r, "no visible binding for 'missing'"))
}

///|
/// CONTROL -- the same `match` with the subject on the SAME LINE. If this went
/// red, the two-line failures would have been about something else entirely.
/// And note what it does NOT assert: anything about `UnusedParam`, which a
/// `match` silences for its whole function by design.
test "0433 control: a match subject on the same line is read too" {
  let r = @pipeline.run(
    "fn sub(x : Int) -> Int { x }\nfn caller(c : Int) -> Int {\n  match missing(c) {\n    1 => 2\n    _ => 3\n  }\n}\n",
    "x.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(r.first_error_line, 0)
  assert_eq(count_family(r, "UndefinedName"), 1)
  assert_true(has_report(r, "no visible binding for 'missing'"))
}

///|
/// `defer <expr>` -- the shape that is 1534 of the 1950 `defer` lines in the
/// six corpora. `request_id` is read ONLY by the deferred call.
test "0433: a deferred call keeps its reads visible" {
  let r = @pipeline.run(
    "fn sink(id : Int) -> Unit { ignore(id) }\nfn f(request_id : Int) -> Unit {\n  defer sink(request_id)\n  sink(0)\n}\n",
    "x.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(r.first_error_line, 0)
  assert_eq(count_family(r, "UnusedParam"), 0)
}

///|
/// `defer { ... }` -- 130 of the 1950 lines. The block body is walked as an
/// ordinary statement list, so a read inside it is a read.
test "0433: a deferred block keeps its reads visible" {
  let r = @pipeline.run(
    "fn sink(id : Int) -> Unit { ignore(id) }\nfn f(request_id : Int) -> Unit {\n  defer {\n    sink(request_id)\n  }\n  sink(0)\n}\n",
    "x.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(r.first_error_line, 0)
  assert_eq(count_family(r, "UnusedParam"), 0)
}

///|
/// THE control for the whole `defer` arm, and the one that lives HERE rather
/// than at parse level for a measured reason.
///
/// A first draft of this test sat in `src/parser/parser_0433_test.mbt`, named
/// "the defer keyword is not read as an ordinary name", and asserted
/// `first_error == 0` and `reports.length() == 0`. Gate 0433's M3 -- switching
/// the arm off -- did NOT turn it red. It was vacuous: with the arm off,
/// `defer g()` still PARSES, because `defer` is read as an ordinary
/// identifier, and the resulting `no visible binding for 'defer'` is produced
/// by the walker, not the parser. The parse-level assertions were true with the
/// arm and true without it.
///
/// `KILLED` on M3 named three other tests and the gate refused the claim. So
/// the control moved here, where the difference is observable: with the arm the
/// source has zero findings, without it there is an UndefinedName for `defer`.
/// Measured both ways before writing the assertion.
test "0433 control: the defer keyword is not reported as an ordinary name" {
  let r = @pipeline.run(
    "fn g() -> Unit { () }\nfn f() -> Unit {\n  defer g()\n  g()\n}\n",
    "x.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(r.first_error_line, 0)
  assert_eq(count_family(r, "UndefinedName"), 0)
  // Spelled out as well as counted: a total of zero would also be satisfied by
  // a family that had stopped firing, and the COUNT is the load-bearing half.
  assert_false(has_report(r, "'defer'"))
}

///|
/// CONTROL for the two `defer` read-visibility tests above. `dead` is read
/// nowhere. If both arms were really "the keyword is recognised and its body is
/// DROPPED", every positive test would still pass -- `request_id` would look
/// unused and be correctly reported -- and only this control would notice, by
/// expecting 1 and getting 0.
test "0433 control: a parameter read by nothing is still reported unused beside a defer" {
  let r = @pipeline.run(
    "fn sink(id : Int) -> Unit { ignore(id) }\nfn f(request_id : Int, dead : Int) -> Unit {\n  defer {\n    sink(request_id)\n  }\n  sink(0)\n}\n",
    "x.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(r.first_error_line, 0)
  // Exactly one: `dead`. `request_id` is read inside the deferred block.
  assert_eq(count_family(r, "UnusedParam"), 1)
}

///|
/// KNOWN LIMIT, pinned where the 0433 defer arm made it reachable.
///
///     defer (cancel() catch { _ => ignore(marker) })
///
/// proton 0.3.4 `facade_bridge.mbt:584` and 17 other lines in the six
/// corpora. The postfix `catch` arm consumes its block with `skip_braces`, so
/// a read that happens ONLY inside a `catch` block -- here `marker` -- is
/// invisible, and the parameter is reported unused.
///
/// The SAME limitation, for the same reason, already applies to a bare
/// `x() catch { ... }` outside a `defer`; it is pinned as a documented limit in
/// `src/parser/parser_0432_test.mbt` rather than suppressed, because
/// suppression would mean treating every function containing a `catch` as
/// having all its parameters read -- trading one false positive for an
/// unbounded number of missed true ones.
///
/// Asserted here as a FACT rather than as the behaviour we want: the count is
/// 1, which is the defect. If this ever goes to 0 the limitation was fixed
/// properly and this test should be replaced, not deleted.
test "0433 KNOWN LIMIT: a parameter read only inside a deferred catch block is not seen" {
  let r = @pipeline.run(
    "fn cancel() -> Unit raise E { raise Boom(1) }\nfn f(marker : Int) -> Unit raise E {\n  defer (cancel() catch { _ => ignore(marker) })\n  cancel() catch { _ => () }\n}\n",
    "x.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(r.first_error_line, 0)
  // The defect: `marker` is read, and reported unused anyway.
  assert_eq(count_family(r, "UnusedParam"), 1)
}
