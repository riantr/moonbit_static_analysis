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
/// An UNBRACED suberror is a different grammar (`suberror E`) and must
/// keep working. If the new lookahead misread it as braced, the skip would
/// swallow the rest of the file and this function would vanish from the module.
///
/// The fixture was `suberror Timeout of String` until 0.4.30, and that is not a
/// suberror header — `moon check` rejects it with `[3002]`, as it does
/// `suberror E(T)` and `suberror E(x : T)`
/// (`_verify/settle_0463b_bodyless_grammar.ps1`, 7/7). A control written on a
/// grammar that does not exist is worse than no control: it is what let two
/// comments in `parser.mbt` document `of` as real. The real unbraced form is
/// `suberror E` and that is what this uses now.
///
/// The observable is unaffected by the 0.4.30 body-less harvest, which adds the
/// suberror's OWN name (`Timeout`) to `enum_ctors` and no function name — so a
/// swallowed `after_it` is still undefined and still counted.
test "0416: an UNBRACED suberror still parses and the file continues" {
  let r = @pipeline.run(
    "suberror Timeout\nfn after_it() -> Int {\n  1\n}\nfn caller() -> Int {\n  after_it()\n}\n",
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
/// C — a call qualified on a BUILTIN TYPE.
///
/// `Array::make(total, Byte::default())` is one real line from riantr/
/// moonbit_labeler 0.2.13. At 0.4.16 one of its two callees was reported as an
/// undefined function, and the test then said so — attributing it to an
/// unfixed rule and to "whack-a-mole with no termination".
///
/// BOTH CLAIMS WERE WRONG, and this test is here because 0.4.17 had to say so
/// where the wrong reasoning was still standing.
///
/// The whack-a-mole reading was wrong because a call that reports returns
/// ABottom and SUPPRESSES the enclosing call, so a nested chain reports only
/// its innermost name. Adding `Byte::default` did not reveal an endless list —
/// it lifted a mask, and the family terminates once the callees are known.
///
/// The "unfixed rule" reading was wrong because the probe that could not
/// reproduce it never called the function whose body contained the line. This
/// lens analyzes only bodies REACHED from a top-level statement; the real
/// file calls `PixelBuffer::new` at line 1379.
///
/// The fix is data, not a rule: `@core.builtin_method_names()`. The control
/// that settles the choice is the `Array::mkae` case in the 0.4.17 file.
test "0416: a builtin-type qualified call resolves through the ambient table" {
  let r = @pipeline.run(
    "fn build(total : Int) -> Array[Byte] {\n  Array::make(total, Byte::default())\n}\nlet top = build(4)\n",
    "x.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "UndefinedName"), 0)
}

///|
/// The NEGATIVE CONTROL for the reachability claim above, and the control for
/// the mask: both callees unknown, the inner one nested. Reporting the inner
/// name and hiding the outer is what 0.4.16 shipped. With `Byte::default`
/// known, the outer one has to appear — fixing an over-report can RAISE the
/// count on a file, and this is that case rather than a regression.
test "0416: a known inner callee no longer masks the outer unknown" {
  let r = @pipeline.run(
    "fn build() -> Int {\n  ZzMissing::nope(4, Byte::default())\n}\nlet top = build()\n",
    "x.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "UndefinedName"), 1)
}

///|
/// THE FALSIFIED CLAIM, corrected in place.
///
/// This test used to read "a KNOWN GAP — an unresolvable qualified call is
/// silent", and asserted `Nope::also_missing()` produced nothing. It did
/// produce nothing, but not for the stated reason. The fixture was
/// `fn f() -> Int { Nope::also_missing() }` with `f` never called, so the
/// behavioral lens never visited the body — the same probe defect as the test
/// above. The claimed "mirror image" of 0.4.14–0.4.16 (qualified names
/// over-reported, then under-reported) does not exist: with the body reached,
/// the qualified name is reported like any other.
///
/// The reason the original fixture stayed silent is worth keeping, because it
/// is two independent silences that look like one. The behavioral lens needs
/// the body reached, and the TYPE lens does not report a `::` name as a type
/// reference at all. Drop the call and only the second silence remains.
test "0416: an unreached body is silent, and reaching it reports the name" {
  let unreached = @pipeline.run(
    "fn f() -> Int {\n  Nope::also_missing()\n}\n",
    "x.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(unreached, "UndefinedName"), 0)
  // Same source, one line added: the body is now reached from a top-level
  // statement, and the very same callee is reported.
  let reached = @pipeline.run(
    "fn f() -> Int {\n  Nope::also_missing()\n}\nlet top = f()\n",
    "x.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_true(count_family(reached, "UndefinedName") > 0)
  // The plain-name case is reported EITHER WAY, because the type lens sees a
  // bare unknown name in a signature position whether or not the body runs.
  // Without this the pair above could pass because nothing ran at all.
  let plain = @pipeline.run(
    "fn f() -> Int {\n  totally_undefined_fn()\n}\n",
    "x.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_true(count_family(plain, "UndefinedName") > 0)
}
