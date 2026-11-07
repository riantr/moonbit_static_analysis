// 0520: `--explain`, from the CLI side.
//
// The data lives in `src/core` and the roster gate reads it out of the source;
// what is left here is that the text the flag actually PRINTS is the contract,
// and that a wrong id is answered with an error rather than with silence.

///|
/// 0520. One family's contract prints the three labelled parts.
test "0520: --explain MSA-007 prints the three labelled parts" {
  let t = @sa.explain_id_value("MSA-007")
  assert_true(t.contains("MSA-007"))
  assert_true(t.contains("property"))
  assert_true(t.contains("assumption"))
  assert_true(t.contains("excluded"))
  assert_true(
    t.contains("an argument's type is not assignable to the callee's parameter"),
  )
}

///|
/// 0520. An id that names no family is an ERROR, never silence.
///
/// `family_by_id` returns `None` for exactly this reason: an id that names
/// nothing is a typo, and a typo answered with an empty page looks like "no
/// such problem".
test "0520: an unknown id is an error line, not an empty page" {
  let t = @sa.explain_id_value("MSA-999")
  assert_true(t.contains("ERROR"))
  assert_true(t.contains("MSA-999"))
}

///|
/// 0520. The roster lists every family, and only real ones.
///
/// The roster is derived from `all_families()`, so the two cannot disagree --
/// but this pins that the PRINTED page carries every id, which is the thing a
/// reader actually sees.
test "0520: the roster prints every family id" {
  let t = @sa.explain_roster()
  for f in @core.all_families() {
    assert_true(t.contains(f.id()))
  }
}
