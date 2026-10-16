//| Tests for 0470 at the PIPELINE level -- "the analyzer no longer manufactures a type
//| error" rather than "the parser built a different node".
//!
//| The rows in `parser_0470_test.mbt` assert the tree. These assert the FINDING, because
//! "the node was built correctly" and "the analyzer said the right thing about it" are
//! different claims and either one alone leaves the other untested.
//!
//! The fixture is moonbit_labeler 0.2.13 app_moui/rasterizer.mbt, reduced to its shape:
//!
//!     fn blend_pixel(buf : ..., x : Int, y : Int, ..) -> Unit   -- param 2 is Int
//!
//!     let x : Double = ..          // line 1196, inside an enclosing `for` body
//|     for x = xs; x <= xe; x = x + 1 {
//!       blend_pixel(buf, x, y, color, opacity)   // line 1218
//!     }
//!
//! which reported
//!
//!     argument 2 to 'blend_pixel' has incompatible type 'float'; expected 'int'
//!
//| -- the last `actionable` finding on any pinned corpus.
//!
//! The mechanism is `Infer::assign_check`, which REPORTS a mismatch but does NOT rebind.
//! While the init clause was an `SAssign`, the loop's `x` never became a binding at all,
//! so the `x : Double` from the enclosing body survived and the argument was checked
//! against it. A plain `let x : Int = xs` in the same position is CLEAN, and a `for`
//! header with no enclosing `x` is CLEAN -- that three-way bisect is what located it.
//!
//! => 判据: the corpus number moved from actionable=1 to actionable=0 and FIVE OTHER
//| CORPORA ARE BYTE-IDENTICAL. A parser change that moved every number everywhere would
//! be a different parser change, and one that moved nothing would have cleared nothing.
//! Both directions have to hold or the single moved number means nothing.

///|
/// THE DEFECT, AS IT WAS: the loop's own binding never replaced the leaked `x : Double`,
/// so the call was checked against the wrong declaration and reported a mismatch on code
/// `moon check` compiles.
test "0470: a C-style for init clause rebinds the name for the loop body" {
  let r = @pipeline.run(
    "///|\nfn blend_pixel(buf : Int, x : Int) -> Unit {\n  ignore(buf)\n  ignore(x)\n}\n///|\nfn f(xs : Int) -> Unit {\n  let x : Double = 1.0\n  ignore(x)\n  for x = xs; x < 4; x = x + 1 {\n    blend_pixel(0, x)\n  }\n}\n",
    "cfordecl.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "ArgTypeMismatch"), 0)
}

///|
/// THE CONTROL THAT GIVES THAT ROW ITS MEANING. The identical file with an ordinary `let`
/// instead of the `for` header is clean too -- that is the bisect's (A) arm, and it is
/// what proves the `for` header was the whole difference rather than the leaked `Double`
/// being harmless. If this row went red, the fixture was not exercising the increment.
test "0470: the same file with a plain `let` is also clean (bisect arm A)" {
  let r = @pipeline.run(
    "///|\nfn blend_pixel(buf : Int, x : Int) -> Unit {\n  ignore(buf)\n  ignore(x)\n}\n///|\nfn f(xs : Int) -> Unit {\n  let x : Double = 1.0\n  ignore(x)\n  {\n    let x : Int = xs\n    blend_pixel(0, x)\n  }\n}\n",
    "cforlet.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "ArgTypeMismatch"), 0)
}

///|
/// AND THE OTHER BISECT ARM: with NO enclosing `x` at all the `for` header was clean even
/// before 0470. That is what makes the leaked `Double` the necessary ingredient rather
/// than merely a present one -- an assignment and a declaration differ only when there is
/// something to collide with, so a fixture without the collision cannot tell them apart.
test "0470: the for header alone, with no enclosing x, is clean (bisect arm C)" {
  let r = @pipeline.run(
    "///|\nfn blend_pixel(buf : Int, x : Int) -> Unit {\n  ignore(buf)\n  ignore(x)\n}\n///|\nfn f(xs : Int) -> Unit {\n  for x = xs; x < 4; x = x + 1 {\n    blend_pixel(0, x)\n  }\n}\n",
    "cforalone.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "ArgTypeMismatch"), 0)
}

///|
/// AND THE ROW THAT PROVES THE LENS IS STILL LOOKING. A genuine `Double` where an `Int`
/// is required must STILL be reported. If this went to zero, the three rows above would
/// pass because `ArgTypeMismatch` had stopped firing -- the classic way a fixture
/// change turns three green rows into proof of nothing. The Double here is the loop
/// variable itself, so the only difference from row 1 is the value's type.
test "0470: a genuine mismatch on a for-bound name is still reported" {
  let r = @pipeline.run(
    "///|\nfn blend_pixel(buf : Int, x : Int) -> Unit {\n  ignore(buf)\n  ignore(x)\n}\n///|\nfn f() -> Unit {\n  for x = 1.0; x < 4.0; x = x + 1.0 {\n    blend_pixel(0, x)\n  }\n}\n",
    "cforreal.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "ArgTypeMismatch"), 1)
}

///|
/// THE LOOP BOUND IS AN INT INSIDE THE LOOP EVEN THOUGH A DOUBLE IS BOUND OUTSIDE. This
/// is the claim the increment makes, stated as an assertion rather than as an absence:
/// 0470 does not stop reporting the mismatch, it stops the OUTER binding from surviving
/// into the loop.
test "0470: the loop body sees the init clause's binding, not the outer one" {
  let r = @pipeline.run(
    "///|\nfn want_int(x : Int) -> Unit {\n  ignore(x)\n}\n///|\nfn f(xs : Int) -> Unit {\n  let x : Double = 1.0\n  ignore(x)\n  for x = xs; x < 4; x = x + 1 {\n    want_int(x)\n  }\n}\n",
    "cforinner.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "ArgTypeMismatch"), 0)
}
