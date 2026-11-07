// 0520: the family CONTRACT, from the core side.
//
// The compile-time half is the exhaustive `match` in `Family::property`,
// `Family::assumption` and `Family::excluded`: MoonBit refuses to build a
// family that has no arm. These are the runtime half -- that the arms carry
// real text rather than a placeholder, and that `@core.all_families()` really is the
// whole enum. `check_family_roster.ps1` reads the same two facts out of the
// source; a test and a gate that agree are worth more than either alone,
// because this one runs on every target and that one reads the text.

///|
/// 0520. Every family declares all three parts, and none of them is a label.
///
/// The floor of 15 characters is low on purpose: it is not a style rule. It is
/// the difference between "n/a" and a sentence, and the gate applies the same
/// floor to the source text.
test "0520: every family declares a real property, assumption and excluded" {
  let fams = @core.all_families()
  assert_eq(fams.length(), 12)
  for f in fams {
    assert_true(f.property().length() >= 15)
    assert_true(f.assumption().length() >= 15)
    assert_true(f.excluded().length() >= 15)
  }
}

///|
/// 0520. `@core.all_families()` is the enum, each id round-trips, and no id repeats.
///
/// A roster that lists a family twice, or lists one whose id does not resolve,
/// would make `--explain-all` lie about what the tool can report.
test "0520: all_families is the whole enum, with no repeat and no dangling id" {
  let fams = @core.all_families()
  let mut i = 0
  while i < fams.length() {
    assert_true(@core.family_by_id(fams[i].id()) == Some(fams[i]))
    let mut j = i + 1
    while j < fams.length() {
      assert_true(fams[i].id() != fams[j].id())
      j = j + 1
    }
    i = i + 1
  }
}

///|
/// 0520. The three parts are DIFFERENT from each other for every family.
///
/// A table filled by copying the property into the assumption would satisfy a
/// non-empty check and tell a reader nothing. This is the cheap version of the
/// question "is the assumption actually an assumption".
test "0520: the three parts of a contract are not the same sentence" {
  for f in @core.all_families() {
    assert_true(f.property() != f.assumption())
    assert_true(f.property() != f.excluded())
    assert_true(f.assumption() != f.excluded())
  }
}
