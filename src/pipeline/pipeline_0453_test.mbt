//| Tests for 0.4.42: an anonymous ASYNC function literal in expression position,
//|| which this parser had no production for.
//|
//| THE DEFECT. After 0452 (the quoted-key map literal) moui 0.1.12 still could not
//| finish reading 9 files, grouped by the reason the parser gave:
//!
//!     4x  expected ')'      <- this one
//!     3x  unexpected token `,`
//!     1x  unexpected end of line
//!     1x  unexpected token `:`
//!
//| `expected ')'` is a complaint about the ARGUMENT of a call, not about the
//! parenthesis -- the parser is downstream of the real failure. Three of the four
//! are the same construct, at moui 0.1.12
//! `backend/macos/macos_app_runtime.mbt:24`, `backend/linux/linux_app_runtime.mbt:22`
//! and `backend/windows/windows_backend.mbt`:
//!
//!     launch_async=Some(async fn(request, frame_interval_ms) {
//!       ..
//!     }),
//!
//| `parse_atom` had an arm for `TName("fn")` and none for `async`, so `async` was
//! read as an ordinary name and the argument never started. The short-lambda named
//! argument on the line ABOVE it parses fine, which is why those files are PARTIAL
//! at line 23-24 rather than unparsed at zero -- which is also why the label
//! `expected ')'` sent the first reading towards brackets.
//!
//| THE CONSTRAINT ON THE FIX, settled against the toolchain
//! (`_verify/settle_0453_async_fn_expr.ps1`, 6/6 with a positive control):
//!
//!     Some(fn(a) { .. })        ACCEPT   <- already read, identical shape
//!     Some(async fn(a) { .. })  ACCEPT
//!     the corpus declaration    ACCEPT   <- short lambda + this, together
//!     ignore(async)             REJECT(3002) "unexpected token `)`, you may
//!                                         expect `fn`"
//!     async work()              REJECT(3002)
//!
//! The last two are why the arm is written as an `if` on the following `fn` rather
//! than as "`async` starts a function". In the toolchain `async` is bound to `fn`
//! and to nothing else: there is no `async call` production and no value named
//! `async`. So an unconditional consumption would be UNTESTED rather than correct,
//! and the guard is what turns that measurement into a production. The fifth test
//! is the one that keeps the guard honest from the other side.

///|
/// THE CORPUS DECLARATION, verbatim in shape. The callee is generic on purpose:
/// three earlier attempts at this fixture failed on MY type annotation rather than
/// on the syntax under test (`-> Int` gave 4118 "error type is mismatched",
/// `-> Error!Int` gave 4127 "Type Int is not an error type", `-> raise Int` gave
/// 3002 "unexpected token `raise`"). The toolchain kept answering a question about
/// TYPING, and this is a question about whether the SYNTAX is legal.
test "0453: an async fn literal is read as a named argument's value" {
  let r = @pipeline.run(
    "///|\nfn[A, B] build(launch~ : A, launch_async~ : B) -> Unit {\n  ignore(launch)\n  ignore(launch_async)\n}\n\n///|\nfn probe() -> Unit {\n  build(\n    launch=(a : Int, b : Int) => a + b,\n    launch_async=Some(async fn(request : Int, frame_interval_ms : Int) {\n      request + frame_interval_ms\n    }),\n  )\n}\n",
    "macos_app_runtime.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(parse_failures(r), 0)
}

///|
/// AND THE BODY IS READ, not stepped over. This is the assertion that separates a
/// real fix from one that merely consumed the tokens.
///
/// GETTING HERE TOOK TWO FAILED DISCRIMINATORS, and both failures are worth the
/// space, because they are the same mistake twice and it is the easy one to make.
///
///   1st: `UnusedParam == 0` on the literal's own parameters, reasoning that a body
///   stepped over would leave them unread. Gate M3 SURVIVED it, 616/616 green.
///   `parse_fn_literal` does `let _ = self.parse_param_list()`: the parameters are
///   parsed and DISCARDED, so they were never in the binding table and
///   `UnusedParam` had nothing to report either way. Structurally incapable.
///
///   2nd: `UndefinedName == 1` for a bad call INSIDE the body. That also cannot
///   work, and for the deeper reason: `parse_block` returns its statements and
///   `parse_fn_literal` throws them away, so nothing inside a function literal's
///   body reaches a lens AT ALL. Asserting it reaches 1 asserted a property this
///   analyzer does not have -- for a plain `fn` literal either.
///
/// WHAT IS OBSERVABLE is what reading the body DISCOVERS: `parse_block` announces
/// the declarations it declines to analyse, via `note_skip`, and those notices are
/// pushed onto the parser, not into the discarded tree. A `match` inside the body
/// is therefore reported by a body that was read and missed by one that was
/// skipped. That is the third signal and the first one that can move.
///
/// IT IS ASSERTED BY MESSAGE, not by count, and the count was tried first. Every
/// function literal already emits one ParseError of its own ("anonymous function
/// literal is outside the analyzed subset"), so the clean fixture sits at 1 and
/// the excluded one at 2 -- a difference of 1 carried by an absolute number that
/// means nothing on its own. A count also cannot tell the literal's own notice from
/// the body's, which is the thing being measured.
///
/// 0502. THE EXCLUDED CONSTRUCT IS AN `if` EXPRESSION NOW, and it used to be a
/// `match`. A `match`'s arms are read, so a `match` inside the body is no longer
/// anything to announce -- and a row that asserted "the match is announced" would
/// have been asserting a message the parser does not emit. The mechanism under
/// test is unchanged: a body that was READ announces what it read and declined,
/// and a body that was SKIPPED does not.
test "0453: a construct inside an async literal's body is still announced" {
  let r = @pipeline.run(
    "///|\nfn probe() -> Unit {\n  let f = Some(async fn(a) {\n    let _ = if a > 0 {\n      1\n    } else {\n      2\n    }\n  })\n  ignore(f)\n}\n",
    "body.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(parse_failures(r), 0)
  assert_eq(reports_containing(r, "if expression"), true)
}

///|
/// AND THE CONTROL, or the test above would pass a parser that announced one
/// `if` no matter what the body held. The same literal with an ordinary
/// expression body announces nothing.
test "0453: a clean async literal body announces nothing" {
  let r = @pipeline.run(
    "///|\nfn probe() -> Unit {\n  let f = Some(async fn(request, interval) {\n    request + interval\n  })\n  ignore(f)\n}\n",
    "body_clean.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(parse_failures(r), 0)
  assert_eq(reports_containing(r, "if expression"), false)
}

///|
/// AND THE STREAM STAYS IN STEP ACROSS THE LITERAL. A declaration follows it and
/// contains its own undefined name; if the literal consumed the wrong number of
/// tokens, everything after it would be unread and the count would be 0.
///
/// The expected value is 1, not 0: a zero here is what a truncation looks like,
/// and an assertion of 0 cannot tell "analysed and clean" from "never read".
test "0453: what follows an async fn literal is still analysed" {
  let r = @pipeline.run(
    "///|\nfn probe() -> Unit {\n  let f = Some(async fn(a) { a })\n  ignore(f)\n}\n\n///|\nfn after_one() -> Int {\n  missing_name_here\n}\nafter_one()\n",
    "after.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(parse_failures(r), 0)
  assert_eq(count_family(r, "UndefinedName"), 1)
}

///|
/// THE REGRESSION CONTROL. The plain `fn` form is what this parser has always
/// read, in the identical position. It is asserted here so that a fix which
/// rewrote the `fn` arm -- rather than adding beside it -- has somewhere to fail.
test "0453: a plain fn literal in the same position still parses" {
  let r = @pipeline.run(
    "///|\nfn[A, B] build(launch_async~ : B) -> Unit {\n  ignore(launch_async)\n}\n\n///|\nfn probe() -> Unit {\n  build(launch_async=fn(request : Int) { request })\n}\n",
    "plain_fn.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(parse_failures(r), 0)
}

///|
/// A NESTED `async fn NAME(..) { .. }` IS A DECLARATION, NOT A LITERAL, and the
/// first version of this increment got that wrong in a way only a corpus caught.
///
/// A function literal is ANONYMOUS, so `async fn` followed by a NAME is always a
/// nested function declaration. `parse_block`'s own discriminator
/// (`at_name("fn") && name_at(p+1) != ""`, the 0450 fix) is false when the cursor
/// is on `async`, so the declaration falls THROUGH to the new `async` arm -- and an
/// `fn`-only guard consumed `async`, read `log(s) { .. }` as an anonymous literal,
/// and never declared the function.
///
/// MEASURED on `riantr/moonbit_labeler@0.2.13`, which is written with exactly that
/// shape inside function bodies (`extensions/labeler/labeler.mbt:1166`, `:1686`
/// both `async fn log(s : String) {`):
///
///     withheld   134 -> 136      two files that had parsed became PARTIAL
///     unreliable 309 -> 366
///
/// `moonbitlang/async` moved the same way (unreliable 1189 -> 1652). So the guard
/// has two halves -- `fn` must follow, AND a name must NOT -- and the second half
/// exists because of a measurement.
///
/// NOT CAUGHT BY THE 0453 MUTATION GATE, and that is the honest note: no 0453
/// fixture contains a nested async declaration, and a gate cannot see a corpus it
/// was not given. The corpus is the instrument here, and it is why `parsed=` and
/// `withheld` are pinned for all six rather than only the one being worked on.
test "0453: a nested async fn with a name is a declaration, not a literal" {
  let r = @pipeline.run(
    "///|\nfn outer() -> Int {\n  async fn log(s : String) -> Unit {\n    ignore(s)\n  }\n  1\n}\n",
    "nested_async_decl.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(parse_failures(r), 0)
  // AND IT IS NOT ANNOUNCED AS ONE. `parse_failures == 0` is not enough here: the
  // middle arm of the parser hands the declaration back, and a middle arm that
  // instead announced itself would produce a notice -- not a failure -- so the file
  // would still parse and this first assertion would still pass. The false notice
  // is the actual regression, so it is asserted by message.
  assert_eq(reports_containing(r, "async without a following `fn`"), false)
}

///|
/// AND THE GUARD IS BINDING FROM THE OTHER SIDE. `async` with no `fn` after it is
/// rejected by the toolchain (settle row `async_as_plain_value`, REJECT(3002)), so
/// no valid program reaches the `else`. The arm still has to behave: reading
/// `async` as a NAME would let the structural lens file `undefined name 'async'`
/// against code the toolchain already refuses -- a confident finding about a
/// construct that does not exist.
///
/// The notice is asserted by MESSAGE. A count would pass just as happily if the
/// notice stopped firing, which is the opposite of what this test is for.
test "0453: async without a following fn is read past, not bound as a name" {
  let r = @pipeline.run(
    "///|\nfn probe() -> Int {\n  ignore(async)\n  0\n}\n",
    "bare_async.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(reports_containing(r, "async without a following `fn`"), true)
  assert_eq(count_family(r, "UndefinedName"), 0)
}
