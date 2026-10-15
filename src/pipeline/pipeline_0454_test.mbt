//| Tests for 0.4.43: `label?=value` in a call argument -- the member the shorthand
//|| family was missing.
//|
//| THE DEFECT. After 0453 moui 0.1.12 could not finish reading 6 files, and the
//| largest by-reason bucket was `unexpected token `,``. Three of them were one
//| construct -- `views/popover/sheet.mbt:25`, plus
//| `backend/host_text_field_test_helper_test.mbt:31` and
//| `backend/common/input/text_field_test_helper_test.mbt:31`, which are the same
//| helper written twice:
//!
//!     let normal = @views.new_control_state_style(
//!       foreground=@core.Color::black(),
//!       border?=normal_border,
//!       radius=0.0,
//!     )
//!
//| The complaint named a COMMA, which is three tokens from the cause. `parse_call_args`
//| handles two shorthands, both AFTER the argument is parsed: `f(x~)` at the `TTilde`
//| test and `f(x?)` at the `TQuestion` test. Neither is followed by an `=`. So for
//! `border?=normal_border`:
//!
//!   1. `peek_name()` is `border`; bumped; the test is `self.at(TAssign)` -- FALSE,
//!      because the next token is `?`.
//!   2. `p` is restored, `border` is read as a plain positional name.
//!   3. The `TQuestion` shorthand consumes the `?` as if the argument ENDED.
//!   4. The loop tests for a comma, finds the `=` that step 1 skipped over, BREAKS.
//!
//| THE CONSTRAINT ON THE FIX, and it is the whole reason this is not a one-line
//| desugaring. Settled in `_verify/settle_0454_label_qmark_eq.ps1`, 9/9 with a
//| positive control:
//!
//!     border?=v   against  border? : Int   ACCEPT
//!     border?=v   against  border~ : Int   REJECT(4141) "this form of application
//!                                            is invalid for argument border~,
//                                            because it is not declared with
//!                                            border? : _"
//!
//! So the `?` CARRIES MEANING. A `name? : T` parameter has type `T?` -- which the
//! settle measured as REJECT(4014) "wanted Int?" when the value was a bare `7` --
//| and a fix that dropped the `?` and emitted `border=normal_border` would read
//! illegal code as legal, in the one direction a validator cannot afford.
//
//| The label recorded is the BARE name, beside the `TQuestion` shorthand's, because
//| the type lens maps arguments to parameters by label and both spellings name the
//| same parameter.

///|
/// THE CORPUS CALL, verbatim in shape. One call mixing all FOUR argument spellings --
/// `~`, `?`, `?=value`, and a labelled `=` -- which is what
/// `views/popover/sheet.mbt:21-29` writes. The mix is the point: a fixture that
/// exercised `?=` alone would not be the same measurement, because the bug is an
/// interaction with the `TQuestion` shorthand that sits further down the loop.
test "0454: a call mixing ~, ?, ?= and = arguments parses" {
  let r = @pipeline.run(
    "///|\nfn[Msg] shell(\n  content~ : Int,\n  mode? : Int = 0,\n  theme? : Int,\n  background? : Int,\n  shadow~ : Int,\n) -> Unit {\n  ignore(content)\n  ignore(mode)\n  ignore(theme)\n  ignore(background)\n  ignore(shadow)\n}\n\n///|\nfn[Msg] probe(content : Int, mode : Int, theme : Int?, shadow : Int) -> Unit {\n  let background_brush : Int? = Some(2)\n  shell(\n    content~,\n    mode~,\n    theme?,\n    background?=background_brush,\n    shadow~,\n  )\n}\n",
    "sheet.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(parse_failures(r), 0)
}

///|
/// AND THE VALUE IS READ, not consumed and dropped. This is the assertion that
/// separates a real fix from one that only skips the right number of tokens.
///
/// The discriminator is a LOCAL used only as the `?=` value: read, it is live; read
/// past, it is bound and never read, and the walk reports `unused local`. The same
/// convention 0452's M3 and 0453's M3 use, for the same reason -- a fix that steps
/// over the value produces neither a parse error nor a lost notice, and every count
/// about failures would still be satisfied.
test "0454: the value after ?= is analysed, not stepped over" {
  let r = @pipeline.run(
    "///|\nfn probe() -> Unit {\n  let normal_border = 1\n  sink(border?=normal_border)\n}\n",
    "value.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(parse_failures(r), 0)
  assert_eq(count_family(r, "UnusedLocal"), 0)
}

///|
/// THE THREE SIBLINGS STILL PARSE, and this is the regression control. `x~` and
/// `x?` are handled by the tests further down the loop, and the fix sits between the
/// name test and the `TAssign` test -- so a fix written carelessly there can swallow
/// one of them. `x?` in particular is the sibling most at risk: it is the same `?`
/// token, and the only thing separating it is what follows.
test "0454: the x~ and x? shorthands still parse" {
  let r1 = @pipeline.run(
    "///|\nfn sink(border~ : Int) -> Unit {\n  ignore(border)\n}\n\n///|\nfn probe() -> Unit {\n  let border = 1\n  sink(border~)\n}\n",
    "tilde.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(parse_failures(r1), 0)
  let r2 = @pipeline.run(
    "///|\nfn sink(border? : Int) -> Unit {\n  ignore(border)\n}\n\n///|\nfn probe() -> Unit {\n  let border : Int? = Some(1)\n  sink(border?)\n}\n",
    "question.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(parse_failures(r2), 0)
}

///|
/// AND THE LOOKAHEAD IS BOUNDED. `?` in argument position is either the END of an
/// argument (`x?`) or the start of `?=`; it never prefixes an expression. The settle
/// measured `border?v` as REJECT(3002) "unexpected token id, you may expect `,` or
/// `)`".
///
/// So a `?` followed by a NAME is not this construct, and the fix must fall through
/// to the shorthand that ends the argument rather than treat the name as a value.
/// If the lookahead were widened to "a `?` means `?=value`", this fixture would parse
/// -- reading code the toolchain rejects.
test "0454: a question mark followed by a name is not ?=" {
  let r = @pipeline.run(
    "///|\nfn probe() -> Unit {\n  sink(border?v)\n}\n",
    "qmark_then_name.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_true(parse_failures(r) >= 1)
}

///|
/// AND A GENUINELY MALFORMED ONE STILL COSTS ONLY ITS OWN ARGUMENT. The recovery
/// path matters more than the accept path: a parse error that moves `first_error`
/// truncates the file, and truncating the file is what turned one unreadable
/// construct into several unreadable files over and over in this repository.
///
/// `border?=` with no value is REJECT(3002) in the toolchain, and this asserts the
/// parser does not silently accept it either -- followed by two more declarations
/// whose names must still resolve.
test "0454: a malformed ?= does not cost the rest of the file" {
  let r = @pipeline.run(
    "///|\nfn probe() -> Unit {\n  sink(border?=)\n  sink(ok=1)\n}\n\n///|\nfn after_one() -> Int {\n  3\n}\nafter_one()\n",
    "recovery.mbt",
    @core.IfaceSymTab::empty(),
  )
  // The malformed argument is reported...
  assert_true(parse_failures(r) >= 1)
  // ... and nothing after it was reported as an undefined name, which is what
  // truncation would have produced.
  assert_eq(count_family(r, "UndefinedName"), 0)
}
