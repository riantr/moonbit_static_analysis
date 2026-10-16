//| Tests for 0471 -- the tail between an anonymous `fn`'s `)` and its body.
//!
//| `parse_fn_literal` went from `parse_param_list()` straight to `parse_block()`, so a
//! literal carrying `-> Type` or `raise`/`noraise` left the cursor on the tail token and
//! `parse_block` -- looking for `{` -- reported `expected '{'`. A complaint about a brace
//! that was never the problem, the same shape as the declared-`fn` `-> T raise E` clause
//! whose absence once cost 24.5% of wzzc-dev/moui's 608 files.
//!
//! THE POSITION WAS RULED OUT BY MEASUREMENT, because the obvious reading is wrong in both
//! directions:
//!
//!     let h = fn(x : Int) { x }          ACCEPTED
//!     g(fn(x) { x })                     ACCEPTED
//!     let h = fn(x : Int) -> Int { x }   PARSE ERROR
//!     g(fn(x) -> Int { x })              PARSE ERROR
//!
//! so the variable is the RETURN ANNOTATION, not where the literal sits. Had the first
//! draft's fixture used a call argument, the increment would have been filed as "literals
//! work as arguments but not as values", which is a different defect with a different fix.
//!
//! Corpus reach, per-FILE first blocker, on the tree at 0470: labeler 33 -> 35 parsed
//! (app_moui/canvas_view.mbt:350, component_blackbox_test.mbt:662), proton 122 -> 131.
//! proton's `unreliable` fell 544 -> 187 and its `withheld` 35 -> 6; labeler's fell
//! 89 -> 55. `actionable` stayed 0 on both. moui 4225, image 230, async 1971 and contract
//! 34 are BYTE-IDENTICAL -- four unchanged against two moved is the control.
//!
//! The grammar is settled in `_verify/settle_0471_fn_literal_tail.ps1`: 9 rows, two of them
//! controls.
//!
//! => 判据: this file asserts the TREE, `pipeline_0471_test.mbt` asserts what the ANALYZER
//! SAID. "the file parses" and "the file is still read CORRECTLY" are different claims, and
//! only the second one can see a tail consumed with the wrong extent -- which would swallow
//! the token after the literal, improve every corpus count, and leave the analyzer no
//! longer seeing the code that follows.
//!
//! `first_error == 0` is the whole assertion in most rows below, and that is weak on purpose:
//! it is the FORM of these fixtures that matters, and the rows that would catch a
//! wrong-extent read are in the pipeline file because only a lens can see one.

///|
/// THE CORPUS SHAPE, verbatim from moonbit_labeler 0.2.13 app_moui/canvas_view.mbt:350.
test "0471: a literal with a return annotation parses" {
  let r = @parser.parse(
    "///|\nfn f() -> Unit {\n  let m = fn(c : Char) -> Int {\n    1\n  }\n  ignore(m)\n}\n",
  )
  assert_eq(r.first_error, 0)
}

///|
/// THE `raise E` TAIL, with the error NAMED. Five proton files carry this, and the name
/// after the clause is what `parse_raise_effect` has to stop at.
test "0471: a literal with `raise E` parses" {
  let r = @parser.parse(
    "///|\nfn f() -> Unit {\n  let m = fn(c : Char) raise E {\n    1\n  }\n  ignore(m)\n}\n",
  )
  assert_eq(r.first_error, 0)
}

///|
/// BOTH TAILS TOGETHER, in the order the declared-`fn` path reads them: `-> T raise E`.
/// This is the shape at `proton/updater/channel.mbt` and `proton/updater/install.mbt`, and
/// reading either alone is not enough to place the cursor correctly for the other.
test "0471: a literal with `-> T raise E` parses" {
  let r = @parser.parse(
    "///|\nfn f() -> Unit {\n  let m = fn(c : Char) -> Int raise E {\n    1\n  }\n  ignore(m)\n}\n",
  )
  assert_eq(r.first_error, 0)
}

///|
/// `noraise` takes the SAME SLOT as `raise` and neither carries an error type, which is
/// why `parse_raise_effect` keeps them in separate arms. It arrives as a `TName` like any
/// other identifier, so a literal carrying one is where a name-reading mistake would look
/// like a tail-reading one.
test "0471: a literal with `noraise` parses" {
  let r = @parser.parse(
    "///|\nfn f() -> Unit {\n  let m = fn(c : Char) noraise {\n    1\n  }\n  ignore(m)\n}\n",
  )
  assert_eq(r.first_error, 0)
}

///|
/// THE BRACKETED RETURN ANNOTATION. `return_annotation` has to consume `Array[Int]` whole
/// rather than stopping at the identifier, and settle_0427_retfn already found the
/// function-type spelling ending early -- at the `)` of an EMPTY parameter list, leaving
/// `-> Int)` in the stream.
test "0471: a literal with a bracketed return annotation parses" {
  let r = @parser.parse(
    "///|\nfn f() -> Unit {\n  let m = fn(c : Char) -> Array[Int] {\n    [1]\n  }\n  ignore(m)\n}\n",
  )
  assert_eq(r.first_error, 0)
}

///|
/// `async fn` WITH A TAIL. The keyword sits in front of the same production and enters the
/// same `parse_fn_literal` once consumed, so the two cannot differ -- and if they do, it is
/// because one arm reaches this function and the other does not.
test "0471: an async literal with a tail parses" {
  let r = @parser.parse(
    "///|\nfn f() -> Unit {\n  let m = async fn(c : Char) -> Unit {\n    ignore(c)\n  }\n  ignore(m)\n}\n",
  )
  assert_eq(r.first_error, 0)
}

///|
/// A LITERAL IN ARGUMENT POSITION WITH A TAIL, which is the proton shape and the position
/// that already worked WITHOUT a tail. Both positions are asserted because the measurement
/// that located the bug found them failing identically -- so a fixture using only one of
/// them would not have caught the regression.
test "0471: a tailed literal as a call argument parses" {
  let r = @parser.parse(
    "///|\nfn g(m : (Char) -> Int) -> Unit {\n  ignore(m('a'))\n}\n///|\nfn f() -> Unit {\n  g(fn(c : Char) -> Int { 1 })\n}\n",
  )
  assert_eq(r.first_error, 0)
}

///|
/// AND THE UNTAILED LITERAL STILL PARSES. Without this row, a fix that made `parse_fn_literal`
/// CONSUME a tail unconditionally would pass every row above and break the form that already
/// worked -- the mirror of the vacuous-row failure from 0470, where four zero-rows passed
/// against a family name that does not exist.
test "0471: an untailed literal still parses" {
  let r = @parser.parse(
    "///|\nfn f() -> Unit {\n  let m = fn(c : Char) {\n    1\n  }\n  ignore(m)\n}\n",
  )
  assert_eq(r.first_error, 0)
}

///|
/// A GENERIC LITERAL, whose `[T]` sits BETWEEN `fn` and its parameter list. `parse_fn_literal`
/// calls `skip_indexed()` before `parse_param_list()` for exactly this, and the new tail
/// reading sits AFTER both -- so this row is what says the tail change did not move the
/// bracketed one.
test "0471: a generic literal with a tail parses" {
  let r = @parser.parse(
    "///|\nfn f() -> Unit {\n  let m = fn[T](c : T) -> T {\n    c\n  }\n  ignore(m)\n}\n",
  )
  assert_eq(r.first_error, 0)
}
