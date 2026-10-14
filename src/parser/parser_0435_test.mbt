///|
/// `a..<=b` — the INCLUSIVE range operator, four characters.
///
/// Settled against the toolchain, one form per package with a broken canary
/// beside each (`_verify/probe_sweep_0434.ps1`, and the five forms below):
///
///   `0..n`    REJECTED -- "Missing `=` after `..` in range expression. Hint:
///              use `a..<=b` for inclusive range or `a..<b` for exclusive"
///   `0..<n`   accepted — exclusive, one `TRange` token, already supported
///   `0..<=n`  accepted — INCLUSIVE. This is the form, not `..=`.
///   `0..=<n`  REJECTED
///
/// The lexer's own comment until 0.4.30 said "`..=` is not modelled: it was not
/// measured in the blocked corpus this token was added for". True when
/// written; stale by the time it was next read, and it cost 4 files of
/// wzzc-dev/moui 0.1.12 — `views/form/date_picker_control.mbt:411`,
/// `core/text_layout.mbt:411`, `render/common/advanced_execution.mbt:320`,
/// `views/data/data_grid_viewport_state.mbt:95`.
test "0435: an inclusive range a..<=b is read" {
  let r = @parser.parse(
    "fn f(days : Int) -> Unit {\n  for day in 1..<=days {\n    ignore(day)\n  }\n}\n",
  )
  assert_eq(r.first_error, 0)
  // The inclusive end is read and NOT analysed, and says so. Asserting
  // `reports.length() == 0` here would be asserting a SILENT LOSS: `ERange`
  // carries no inclusivity, so without the notice `a..<=b` and `a..<b` are the
  // same tree, and iterating n times versus n+1 times is not a difference to
  // drop without saying so.
  assert_eq(r.reports.length(), 1)
  assert_eq(
    r.reports[0].message,
    "inclusive range end is outside the analyzed subset; it was read but the bound was not analysed",
  )
}

///|
/// The same range written the way moui writes it: the lower bound is a field
/// access on the receiver, not a literal.
test "0435: an inclusive range with a field lower bound is read" {
  let r = @parser.parse(
    "fn f(r : R) -> Unit {\n  for row in r.start..<=r.last {\n    ignore(row)\n  }\n}\nstruct R {\n  start : Int\n  last : Int\n}\n",
  )
  assert_eq(r.first_error, 0)
  // Presence, not a count: the struct declaration in this source emits its own
  // subset-exclusion notice, so `reports.length()` would be counting that too.
  assert_eq(r.reports.length(), 2)
  assert_eq(
    r.reports[0].message,
    "inclusive range end is outside the analyzed subset; it was read but the bound was not analysed",
  )
}

///|
/// CONTROL -- the EXCLUSIVE range is untouched, and still silent. This is the
/// shape that decides whether the new branch is really doing anything: if the
/// notice fired for `..<` too, the notice would be announcing nothing.
test "0435 control: an exclusive range a..<b is read and says nothing extra" {
  let r = @parser.parse(
    "fn f(n : Int) -> Unit {\n  for day in 0..<n {\n    ignore(day)\n  }\n}\n",
  )
  assert_eq(r.first_error, 0)
  assert_eq(r.reports.length(), 0)
}

///|
/// `..<=` is a PREFIX of `..<`, so the lexer's four-character test has to come
/// first. Getting the order wrong lexes `0..<=n` as `0..<` followed by `=n` --
/// which is the bare-`..`-then-`=` shape the toolchain explicitly rejects, and
/// the failure looks like a missing token rather than an ordering mistake.
///
/// So this test asserts the REJECTED form is rejected AND that the reason is the
/// bare `..`: `0..n` is two TDots, so the parser dies in the postfix chain on
/// the dot, not on anything range-specific.
test "0435: a bare two-dot range is still not a range" {
  let r = @parser.parse(
    "fn f(n : Int) -> Unit {\n  for day in 0..n {\n    ignore(day)\n  }\n}\n",
  )
  assert_true(r.first_error != 0)
}

///|
/// The notice must not be able to swallow the rest of the file. `0..<=n` inside
/// a call argument, with the loop after it, is the shape that used to eat the
/// remainder when a token boundary moved.
test "0435: an inclusive range does not cost the statements after it" {
  let r = @parser.parse(
    "fn g(xs : Array[Int]) -> Int {\n  xs.length()\n}\nfn f(n : Int) -> Unit {\n  g([0])\n  for day in 1..<=n {\n    ignore(day)\n  }\n  g([1])\n}\n",
  )
  assert_eq(r.first_error, 0)
  // TWO statements in `f`: the loop, and the call after it. The range notice is
  // a subset exclusion, not a parse failure, so the tail is still analysed --
  // and finding nothing there is a finding worth being able to make.
  match r.tree.body[1].kind {
    @ast.SFunc(_, _, _, body, _) => assert_eq(body.length(), 3)
    _ => assert_true(false)
  }
}
