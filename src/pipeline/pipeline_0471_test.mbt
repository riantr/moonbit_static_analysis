//| Tests for 0471 at the PIPELINE level -- "the analyzer still SEES what follows the literal"
//! rather than "the parser built something legal".
//!
//| The rows in `parser_0471_test.mbt` assert the TREE. These assert the FINDING, because
//! "the tail was read" and "the token stream is still in step afterwards" are different
//! claims, and the second one is the one this increment could plausibly have broken.
//!
//| THE FAILURE MODE THIS FILE EXISTS FOR. `parse_fn_literal` now reads `-> T` and then
//! `raise E` before the body. A tail read with the WRONG EXTENT -- one token too few, or the
//! annotation's brackets not skipped -- leaves the cursor inside or past the literal. The
//! file then parses, `parsed` goes UP on every affected corpus, every SUMMARY line looks
//! like progress, and the analyzer has quietly stopped reading the code after the literal.
//! Nothing in the corpus numbers can see that. Only a name placed AFTER the literal, looked
//! for by a later lens, can.
//!
//! => 判据: a fix that makes files readable has to be checked for what it stops reading. The
//! parse rows cannot see it, and neither can the six pinned corpora -- so the row that
//! matters here places its probe on the far side of the change.

///|
/// THE ROW THE INCREMENT TURNS ON. `zq_missing_after` sits on the line AFTER a literal
/// carrying `-> Int`. If the tail were consumed with the wrong extent it would go with the
/// tail, and this row would go green by the analyzer having stopped looking.
test "0471: a name after a tailed literal is still reported undefined" {
  let r = @pipeline.run(
    "///|\nfn f() -> Unit {\n  let m = fn(c : Char) -> Int { 1 }\n  ignore(m)\n  ignore(zq_missing_after)\n}\n",
    "tailafter.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "UndefinedName"), 1)
}

///|
/// THE SAME ROW WITH A `raise` TAIL, because `raise E` consumes a NAME after it and
/// `parse_raise_effect` has to stop at the right one. `zq_missing_raise` is a suberror name
/// that exists nowhere in the file, so the clause must not have swallowed it.
test "0471: a name after a raising literal is still reported undefined" {
  let r = @pipeline.run(
    "///|\nfn f() -> Unit {\n  let m = fn(c : Char) raise ZqNoSuchError { 1 }\n  ignore(m)\n  ignore(zq_missing_raise)\n}\n",
    "tailraise.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "UndefinedName"), 1)
}

///|
/// AND WITH BOTH TAILS, `-> Int raise ZqNoSuchError`, which is the proton shape and the only
/// one where BOTH readers have to stop in the right place for the probe to survive.
test "0471: a name after a `-> T raise E` literal is still reported undefined" {
  let r = @pipeline.run(
    "///|\nfn f() -> Unit {\n  let m = fn(c : Char) -> Int raise ZqNoSuchError { 1 }\n  ignore(m)\n  ignore(zq_missing_both)\n}\n",
    "tailboth.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "UndefinedName"), 1)
}

///|
/// THE CONTROL THAT GIVES THOSE THREE ROWS THEIR MEANING: the identical probe on the far
/// side of an UNTAILED literal, which is the form that already worked. If this row were
/// zero, the rows above would be passing because the analyzer cannot see past ANY literal
/// rather than because the tail reading is correct.
test "0471: the same probe after an untailed literal is still reported" {
  let r = @pipeline.run(
    "///|\nfn f() -> Unit {\n  let m = fn(c : Char) { 1 }\n  ignore(m)\n  ignore(zq_missing_ctrl)\n}\n",
    "tailctrl.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "UndefinedName"), 1)
}

///|
/// AND THE ROW THAT PINS THE EXCLUSION. A literal is still outside the analyzed subset, and
/// the analyzer still SAYS so -- `parse_fn_literal` yields `EBigInt` and records a ParseError
/// skip. Asserting `== 1` is STRONGER than asserting nothing: it says the literal is still
/// deliberately skipped rather than silently analysed as though it were read. The next row
/// has no literal at all and asserts zero; the contrast is the point.
/// This is the same discipline as 0469's rows, which all assert `ParseError == 1`.
test "0471: a tailed literal still records its analysed-subset exclusion" {
  let r = @pipeline.run(
    "///|\nfn f() -> Unit {\n  let m = fn(c : Char) -> Int { 1 }\n  ignore(m)\n}\n",
    "tailskip.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "ParseError"), 1)
}

///|
/// THE CONTRAST. No literal, no exclusion. Without this the row above cannot distinguish
/// "the literal is announced" from "this file always produces one ParseError".
test "0471: a file with no literal records no exclusion" {
  let r = @pipeline.run(
    "///|\nfn f() -> Int {\n  1\n}\n",
    "tailnoskip.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "ParseError"), 0)
}

///|
/// THE INCREMENT MUST NOT INTRODUCE FALSE POSITIVES. proton's `actionable` was 0 before this
/// change and had to stay 0 while nine more of its files became readable -- more files read
/// means more chances to invent a finding, and a parser change that clears a blocker while
/// manufacturing a mismatch would be a trade nobody should accept quietly.
test "0471: a tailed literal introduces no argument-type findings" {
  let r = @pipeline.run(
    "///|\nfn g(m : (Char) -> Int, n : Int) -> Unit {\n  ignore(m('a'))\n  ignore(n)\n}\n///|\nfn f() -> Unit {\n  g(fn(c : Char) -> Int { 1 }, 0)\n}\n",
    "tailnoargs.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "ArgTypeMismatch"), 0)
}

///|
/// AND THE CONTROL FOR THAT: a genuine mismatch on the SAME call is still reported, so the
/// row above is not passing because the call stopped being checked.
/// `g(fn(c : Char) -> Char { c }, "not an int")` -- the second argument is the error.
/// The probe is deliberately a SIBLING argument rather than the literal's own return type,
/// because the literal yields `EBigInt` and is therefore deliberately opaque; see the next
/// row.
test "0471: a genuine mismatch beside a tailed literal is still reported" {
  let r = @pipeline.run(
    "///|\nfn g(m : (Char) -> Int, n : Int) -> Unit {\n  ignore(m('a'))\n  ignore(n)\n}\n///|\nfn f() -> Unit {\n  g(fn(c : Char) -> Char { c }, \"not an int\")\n}\n",
    "tailsibling.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "ArgTypeMismatch"), 1)
}

///|
/// THE LITERAL'S OWN RETURN TYPE IS NOT TYPE-CHECKED, AND THAT IS BY DESIGN rather than a
/// gap introduced here. `parse_fn_literal` yields `EBigInt` because the subset has no
/// closure node, so the literal is opaque to the type lens whatever its annotation says.
/// The first draft of this file asserted `ArgTypeMismatch == 1` for
/// `g(fn(c : Char) -> Char { c })` and it came back 0 -- which is CORRECT, and the fixture
/// was wrong about what the analyzer claims to know.
/// => 判据: asserting a finding the analyzer never made is not a strong row, it is a false
/// one that happens to be written in the test rather than the product. `-> T` is read to
/// keep the token stream in step; nothing reads it.
test "0471: a tailed literal's own return type is deliberately not checked" {
  let r = @pipeline.run(
    "///|\nfn g(m : (Char) -> Int) -> Unit {\n  ignore(m('a'))\n}\n///|\nfn f() -> Unit {\n  g(fn(c : Char) -> Char { c })\n}\n",
    "tailopaque.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "ArgTypeMismatch"), 0)
}
