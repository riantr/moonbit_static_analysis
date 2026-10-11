// Tests for the 0.4.16 fixes.
//
//   A  A cross-file CONSTANT was typed as a FUNCTION. The `.mbti` reader
//      already told `pub const X : T` from `pub fn f(...) -> T` — it matched a
//      different prefix for each — and then discarded the difference, because
//      both produced a bare name. So `3.0F * hz` on a `const hz` from another
//      package was reported as `unsupported operand types for '*': 'float' and
//      'fn hz (signature not read)'`.
//   B  A BRACED suberror was routed to the line skipper, so its body was left
//      to be parsed as an expression block and every payload type inside it
//      was reported undefined (`String`, four times, on riantr/moonbit_image).
//   C  `Byte::default` is a real builtin and was not on the ambient list.

///|
/// A — a cross-file constant is a value, not a function.
///
/// The table is built here by hand so the test does not depend on a fixture on
/// disk; `@core.IfaceSymTab` is what a `.mbti` scan produces.
fn const_tab() -> @core.IfaceSymTab {
  let t = @core.IfaceSymTab::empty()
  t.values.set("hz", true) // true = is_const
  t.values.set("format_it", false)
  t
}

///|
test "0416: a cross-file CONSTANT is not typed as a function" {
  let r = @pipeline.run(
    "fn f() -> Float {\n  3.0 * hz\n}\n",
    "x.mbt",
    const_tab(),
  )
  assert_eq(count_family_in(r, "OperatorMismatch", @core.LType), 0)
}

///|
/// The NEGATIVE CONTROL for A. A cross-file FUNCTION must still be typed as
/// `TUnknownFn`, not demoted to `TUnknown` alongside the constant: the
/// distinction is what keeps the call handler from running arity checks against
/// an invented signature. If the flag were ignored for functions too, `hz`
/// above would pass for the wrong reason.
test "0416: a cross-file FUNCTION still types as unknown-signature" {
  let r = @pipeline.run(
    "fn f() -> Int {\n  format_it(1, 2, 3)\n}\n",
    "x.mbt",
    const_tab(),
  )
  // Unknown signature, so the arity must NOT be checked: zero findings.
  assert_eq(count_family(r, "FArgType"), 0)
}

///|
/// `is_const` on the table itself: the flag is `false` for a name that is not a
/// value at all, so a caller that forgets to gate on `has_value` gets `false`
/// rather than a crash or a silent true.
test "0416: is_const answers false for a non-value" {
  let t = const_tab()
  assert_true(t.is_const("hz"))
  assert_false(t.is_const("format_it"))
  assert_false(t.is_const("never_heard_of_it"))
}

///|
/// B — a braced suberror's body must not be parsed as expressions.
test "0416: a braced suberror body is skipped whole" {
  let r = @pipeline.run(
    "pub suberror DecodeError {\n  UnsupportedFormat(String)\n  TruncatedData(String)\n}\n",
    "x.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "UndefinedName"), 0)
}

///|
/// The NEGATIVE CONTROL for B, and the one that keeps the shape test honest.
/// The UNBRACED suberror is a different grammar (`suberror E of T`) and must
/// keep working. If the new lookahead misread it as braced, the skip would
/// swallow the rest of the file and this function would vanish from the module.
test "0416: an UNBRACED suberror still parses and the file continues" {
  let r = @pipeline.run(
    "suberror Timeout of String\nfn after_it() -> Int {\n  1\n}\nfn caller() -> Int {\n  after_it()\n}\n",
    "x.mbt",
    @core.IfaceSymTab::empty(),
  )
  // Zero parse complaints is the observable: if the new lookahead had misread
  // the unbraced header as braced, the skip would run past the end of the file
  // and the file would stop being understood cleanly.
  assert_eq(r.n_parse, 0)
  assert_eq(r.first_error_line, 0)
  // And the function AFTER the declaration is still there to be called, so a
  // swallow would show up as an undefined name rather than as silence.
  assert_eq(count_family(r, "UndefinedName"), 0)
}

///|
/// C — a call qualified on a BUILTIN TYPE. NOT FIXED in 0.4.16, and this test
/// says so rather than pretending otherwise.
///
/// `Array::make(total, Byte::default())` is one real line from
/// riantr/moonbit_labeler 0.2.13, and the analyzer reports one of its two
/// callees as an undefined function. A rule ("a call qualified on an ambient
/// type is a builtin method") was written for it, and then REVERTED: two of its
/// mutations survived and it changed nothing in a hand-built probe, complete or
/// deliberately partial. Whatever emits those findings is not that code path.
///
/// The test therefore pins what is actually true — the plain-name control —
/// and names the open question, rather than asserting a silence that arrived
/// for an undemonstrable reason.
test "0416: KNOWN GAP - builtin-type qualified calls are unresolved, not fixed" {
  // The plain undefined name IS reported, so the analyzer is looking.
  let plain = @pipeline.run(
    "fn f() -> Int {\n  totally_undefined_fn()\n}\n",
    "x.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_true(count_family(plain, "UndefinedName") > 0)
  // And a call qualified on a non-builtin head is already silent — the mirror
  // of the over-reporting 0.4.14-0.4.16 removed. Qualified names swung from
  // over-reported to under-reported, and neither end is right yet.
  let qualified = @pipeline.run(
    "fn f() -> Int {\n  nope::also_missing()\n}\n",
    "x.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(qualified, "UndefinedName"), 0)
}

///|
/// A KNOWN GAP, pinned so it cannot be forgotten: an unresolvable qualified
/// call is not reported at all.
///
/// This test asserts the CURRENT behaviour, which is silence. It is written
/// this way deliberately — the alternative would be to assert a finding that
/// does not exist yet, which turns the suite red and blocks every release for
/// a gap nobody has scoped. `Nope::also_missing()` is real code with a real
/// undefined callee, and the analyzer says nothing.
///
/// It is the mirror image of the false positives 0.4.14–0.4.16 spent three
/// releases removing: qualified names were over-reported, and the fix for that
/// left them under-reported. The honest direction for a later version is to
/// report an unresolvable qualified call — but that needs the callee's receiver
/// to be distinguished from a package alias first, which is not done here.
test "0416: KNOWN GAP - an unresolvable qualified call is silent" {
  let r = @pipeline.run(
    "fn f() -> Int {\n  Nope::also_missing()\n}\n",
    "x.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "UndefinedName"), 0)
  // The plain-name case beside it IS reported, so the silence above is specific
  // to the qualified form and not the check simply not running.
  let plain = @pipeline.run(
    "fn f() -> Int {\n  totally_undefined_fn()\n}\n",
    "x.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_true(count_family(plain, "UndefinedName") > 0)
}
