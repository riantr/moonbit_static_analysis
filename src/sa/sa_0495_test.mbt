// test: the per-file PRINT cap, and the reason it is a cap and not a filter.
//
// The cap was a module-level constant with no way to change it, and on one
// corpus file it hid every defect the file had: the file carries 212
// findings, 174 of them notices, and the first forty printed are all notices,
// so the thirty-eight defects behind them were never shown. The file's own
// header said `defects=38` and the reader saw none of them.
//
// Two properties are pinned here, and they are different properties:
//
//   1. THE CAP IS A PRINTING LIMIT, NOT AN ANALYSIS LIMIT. `show_plan` decides
//      how many findings are PRINTED; it never changes how many there are.
//      The SUMMARY counts come from `aggregate` over every finding, so a scan
//      with a high cap and a scan with the default report the same numbers.
//      That is the property that makes the override safe to ship.
//   2. THE BOUNDARY IS EXACT. A file with exactly `cap` findings prints all
//      of them and says nothing about there being more; a file with `cap + 1`
//      prints `cap` of them and says there is one more. Off-by-one here is
//      the difference between "everything was shown" and "something was
//      hidden", which is exactly the failure the flag exists to remove.

///|
/// The default cap is what the CLI uses when the flag is absent. It is pinned
/// because the flag's whole justification is "the default hid something": a
/// default that silently changed would make that sentence untrue.
test "show_plan: the default cap is 40 and is the number the CLI starts from" {
  assert_eq(@sa.default_findings_shown_per_file, 40)
}

///|
/// A file with FEWER findings than the cap prints all of them and claims
/// nothing is missing.
test "show_plan: under the cap prints everything and reports no remainder" {
  let (shown, more) = @sa.show_plan(12, 40)
  assert_eq(shown, 12)
  assert_false(more)
}

///|
/// A file with EXACTLY the cap is not truncated: the cap is "show up to N",
/// so N findings are N findings and there is no remainder to announce.
test "show_plan: exactly the cap is not a truncation" {
  let (shown, more) = @sa.show_plan(40, 40)
  assert_eq(shown, 40)
  assert_false(more)
}

///|
/// One past the cap IS a truncation, and the remainder is announced.
test "show_plan: one past the cap truncates and announces the remainder" {
  let (shown, more) = @sa.show_plan(41, 40)
  assert_eq(shown, 40)
  assert_true(more)
}

///|
/// The case that started all this: 212 findings under the default cap print
/// 40 of them and the other 172 are announced as unshown. With the cap
/// raised, all 212 print and nothing is withheld. The FINDINGS are the same
/// 212 in both cases -- the cap moves the printing, never the analysis.
test "show_plan: 212 findings -- 40 shown by default, all 212 when the cap is raised" {
  let (shown_default, more_default) = @sa.show_plan(212, 40)
  assert_eq(shown_default, 40)
  assert_true(more_default)
  let (shown_all, more_all) = @sa.show_plan(212, 1000)
  assert_eq(shown_all, 212)
  assert_false(more_all)
}

///|
/// A cap of zero shows nothing and says everything is hidden. This is the
/// honest shape of "print nothing": the file is still counted.
test "show_plan: a cap of zero shows nothing and still announces the remainder" {
  let (shown, more) = @sa.show_plan(212, 0)
  assert_eq(shown, 0)
  assert_true(more)
}

///|
/// A NEGATIVE cap is clamped to zero rather than asked for a range of negative
/// length. The reader asked for "everything" or "nothing"; "less than
/// nothing" is a typo, and a typo must not become a crash.
test "show_plan: a negative cap is clamped to zero, not passed through" {
  let (shown, more) = @sa.show_plan(212, -5)
  assert_eq(shown, 0)
  assert_true(more)
}

///|
/// An empty file has nothing to show and nothing to announce, whatever the
/// cap is.
test "show_plan: an empty file shows nothing under any cap" {
  let (shown, more) = @sa.show_plan(0, 40)
  assert_eq(shown, 0)
  assert_false(more)
  let (shown2, more2) = @sa.show_plan(0, 0)
  assert_eq(shown2, 0)
  assert_false(more2)
}
