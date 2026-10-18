//| Tests for 0470, the C-style `for` INIT CLAUSE -- a DECLARATION the parser read as an
//| assignment.
//|
//| The C-style `for` desugars to `SBlock([<init>, SWhile(cond, body + update)])`, so the
//| init clause is an ordinary statement inside a block. It has no `let` keyword, so the
//| ordinary statement reader had nothing to go on and built an `SAssign`.
//!
//| That is the wrong node twice over: the clause DECLARES rather than assigns, and the
//! name does not outlive the loop. The settle (`_verify/settle_0470_c_for_init.ps1`,
//! 6 rows, 2 of them controls) establishes both against the toolchain, and the RECORDed
//| row is the sharp one -- an enclosing `let x : Int`, then `for x = 0; ..`, then
//! `ignore(x)` after the loop ACCEPTs. The clause SHADOWS the enclosing binding and the
//! enclosing binding survives. An assignment would have collided or overwritten; only a
//! declaration both shadows and ends.
//!
//! The observable cost was moonbit_labeler 0.2.13 app_moui/rasterizer.mbt:1218, the last
//! `actionable` on any pinned corpus:
//!
//!     argument 2 to 'blend_pixel' has incompatible type 'float'; expected 'int'
//!
//! `Infer::assign_check` REPORTS a mismatch but does not rebind, so the `x : Double`
//! leaked from the enclosing body survived and the loop's own `x` never replaced it.
//! Three-way bisect located it: the same file with a plain `let x : Int = xs` in place of
//! the header is CLEAN, and with no inner `x` at all it is CLEAN.
//!
//! => 判据: a function that is never reached cannot be caught by a test suite. The first
//! version of `c_for_init` unwrapped an `EBin` out of the right-hand side and matched
//! nothing -- because `EBin` is what the COMPOUND branch produces, while the plain `=`
//! branch stores the value DIRECTLY. It returned every statement UNCHANGED, and
//! `moon check --deny-warn` was 0 while all 857 tests stayed green and the corpus finding
//! it was written to clear stayed. A green suite and a blue checker were both reporting a
//! function that did nothing, which is only visible if some row asserts the node KIND.
//!
//! Corpus reach, measured on all six pinned corpora after the change: labeler
//! actionable 1 -> 0, total 801 -> 800. moui 4225, image 230, async 1971, proton 2189 and
//! contract 34 are BYTE-IDENTICAL to the pins -- five of six unchanged is the control that
//! makes the sixth meaningful. A parser change that moved a number everywhere would be a
//! different parser change.

///|
/// THE ROW THAT SAYS IT IS A DECLARATION. Asserting only that the header parses is
/// satisfied by `SAssign` just as well as by `SLet`, so this asserts the KIND.
test "0470: a C-style for init clause is built as SLet, not SAssign" {
  let r = @parser.parse(
    "///|\nfn f(n : Int) -> Unit {\n  for i = 0; i < n; i = i + 1 {\n    ignore(i)\n  }\n}\n",
  )
  assert_eq(r.first_error, 0)
  match r.tree.body[0].kind {
    @ast.SFunc(_, _, _, body, _) =>
      match body[0].kind {
        @ast.SBlock(stmts) => {
          assert_eq(stmts.length(), 2)
          match stmts[0].kind {
            @ast.SLet(name, tyann, init) => {
              assert_eq(name, "i")
              assert_eq(tyann, "")
              match init.kind {
                @ast.EInt(v) => assert_eq(v, 0)
                _ => assert_true(false)
              }
            }
            _ => assert_true(false)
          }
        }
        _ => assert_true(false)
      }
    _ => assert_true(false)
  }
}

///|
/// THE ROW THAT KILLS THE BROKEN VERSION ON ITS OWN. The value is stored DIRECTLY.
/// The first `c_for_init` assumed `parse_stmt` wrapped the whole `name = value` in one
/// `EBin` and unwrapped it -- so this row would have matched nothing and the suite would
/// have gone green with the function inert. Asserting the VALUE is present in the SLet at
/// all is what separates "converted" from "handed back untouched".
test "0470: the init clause's value is the SLet value, not a wrapper" {
  let r = @parser.parse(
    "///|\nfn f() -> Unit {\n  for i = 0; i < 9; i = i + 1 {\n    ignore(i)\n  }\n}\n",
  )
  assert_eq(r.first_error, 0)
  match r.tree.body[0].kind {
    @ast.SFunc(_, _, _, body, _) =>
      match body[0].kind {
        @ast.SBlock(stmts) =>
          // `SAssign` and `SLet` both carry two fields; only the KIND tells them apart.
          // A row that counted statements here could not see the conversion at all.
          match stmts[0].kind {
            @ast.SLet(name, _, init) => {
              assert_eq(name, "i")
              match init.kind {
                @ast.EInt(v) => assert_eq(v, 0)
                _ => assert_true(false)
              }
            }
            _ => assert_true(false)
          }
        _ => assert_true(false)
      }
    _ => assert_true(false)
  }
}

///|
/// AND THE ROW THAT PROVES THE TOKEN DECIDES, NOT THE NODE SHAPE. `for i = j + 1;` is a
/// plain `=` whose value is legitimately an `EBin`, so any test written on the shape of
/// the right-hand side -- unwrap the `EBin` and you have a declaration -- is wrong in both
/// directions: it converts this correctly by accident and the compound-assignment form
/// below incorrectly. `TName(_)` followed by `TAssign` is the only reading that separates
/// them, and the value stays wrapped because it really is one.
test "0470: a plain `=` whose value is an EBin is still a declaration, value intact" {
  let r = @parser.parse(
    "///|\nfn f(j : Int) -> Unit {\n  for i = j + 1; i < 9; i = i + 1 {\n    ignore(i)\n  }\n}\n",
  )
  assert_eq(r.first_error, 0)
  match r.tree.body[0].kind {
    @ast.SFunc(_, _, _, body, _) =>
      match body[0].kind {
        @ast.SBlock(stmts) =>
          match stmts[0].kind {
            @ast.SLet("i", _, init) =>
              match init.kind {
                @ast.EBin(_, _, _) => ()
                _ => assert_true(false)
              }
            _ => assert_true(false)
          }
        _ => assert_true(false)
      }
    _ => assert_true(false)
  }
}

///|
/// THE CONVERSION DOES NOT LEAK TO THE UPDATE CLAUSE. `x += 1` is an ASSIGNMENT and stays
/// one -- it is read by the ordinary statement reader, not by `c_for_init`. The compound
/// branch produces `SAssign(x, EBin(OpAdd, x, 1))`, so the EBin wrapper IS the correct
/// shape here and must survive: a `c_for_init` that matched on `SAssign` without the token
/// test would have rewritten this clause's structure instead of the header's.
test "0470: a compound update clause stays an SAssign with its EBin wrapper" {
  let r = @parser.parse(
    "///|\nfn f(n : Int) -> Unit {\n  for x = 0; x < n; x += 1 {\n    ignore(x)\n  }\n}\n",
  )
  assert_eq(r.first_error, 0)
  match r.tree.body[0].kind {
    @ast.SFunc(_, _, _, body, _) =>
      match body[0].kind {
        @ast.SBlock(stmts) =>
          match stmts[1].kind {
            @ast.SWhile(_, loop_body) =>
              // the update is appended after the body, so it is the LAST statement
              match loop_body[loop_body.length() - 1].kind {
                @ast.SAssign(target, rhs) =>
                  match (target.kind, rhs.kind) {
                    (@ast.EName(n), @ast.EBin(_, _, _)) => assert_eq(n, "x")
                    _ => assert_true(false)
                  }
                _ => assert_true(false)
              }
            _ => assert_true(false)
          }
        _ => assert_true(false)
      }
    _ => assert_true(false)
  }
}

///|
/// THE BINDER FORM IS UNTOUCHED. `for i in xs` has no init clause and must still be an
/// `SFor`, not a block. `is_c_style_for` decides the two by which of `;` and `{` arrives
/// first at depth 0; if this row ever fails, the discriminator this increment relies on is
/// no longer separating them.
test "0470: the binder form of `for` is still SFor, not a desugared block" {
  let r = @parser.parse(
    "///|\nfn f(xs : Array[Int]) -> Unit {\n  for i in xs {\n    ignore(i)\n  }\n}\n",
  )
  assert_eq(r.first_error, 0)
  match r.tree.body[0].kind {
    @ast.SFunc(_, _, _, body, _) =>
      match body[0].kind {
        @ast.SFor(name, _, _, _) => assert_eq(name, "i")
        _ => assert_true(false)
      }
    _ => assert_true(false)
  }
}

///|
/// AND THE CONTROL FOR THE ROW ABOVE: the binder form and the C-style form really are
/// different trees, so "still SFor" is a claim about discrimination rather than about every
/// `for` looking the same.
test "0470: the two for forms are distinguishable in the tree" {
  let a = @parser.parse(
    "///|\nfn f(xs : Array[Int]) -> Unit {\n  for i in xs {\n    ignore(i)\n  }\n}\n",
  )
  let b = @parser.parse(
    "///|\nfn f(n : Int) -> Unit {\n  for i = 0; i < n; i = i + 1 {\n    ignore(i)\n  }\n}\n",
  )
  match (a.tree.body[0].kind, b.tree.body[0].kind) {
    (@ast.SFunc(_, _, _, ab, _), @ast.SFunc(_, _, _, bb, _)) =>
      assert_true(ab[0].kind != bb[0].kind)
    _ => assert_true(false)
  }
}

//|
// THREE FIXTURES THIS FILE DELIBERATELY DOES NOT ASSERT, each measured rather than argued.
// They are recorded here because the row was written, ran, and was WRONG -- and why it was
// wrong is the interesting part. Asserting any of them would pin something unsettled.
//
// 1. A C-style `for` header with the initializer on the line AFTER the `for`:
//
//        for
//          i = 0;
//          i < n;
//          i = i + 1
//        { .. }
//
//    `moon check` REJECTs this [3002, 4021] -- RE-MEASURED at 0482 as
//    `_verify/settle_0482_for_header_no_semicolons.ps1` row `C4_for_alone_on_its_line`,
//    which was added for exactly this reason. The analyzer also refuses to parse it, and
//    `parser_0482_test.mbt` pins that as a negative control after 0482 made the clause
//    chain positional and permissive -- so the two AGREE, and a row asserting
//    `first_error == 0` would have been asserting that the analyzer accepts code the
//    toolchain rejects. That is why `c_for_init` steps over separators before it
//    discriminates: the step is DEFENSIVE, and this comment is the reason it is not dead.
//
//    THE REASON WAS WRONG UNTIL 0482, and the correction matters. `mutate_0470.ps1` gave
//    this same justification as "the lexer emits no whitespace token between `for` and its
//    first name". That is false -- `TNewline` is emitted there like everywhere else, which
//    is why this step exists. The real reason is the one above: MoonBit requires the head on
//    the `for` line. Believing the old sentence would have been actively unhelpful in 0482,
//    whose first draft gated the newline-separated header on `at_sep()` and did not fire
//    because `parse_is` had already consumed the newline.
//
// 2. `for let i = 0; i < n; i = i + 1` -- the settle's claim 2 says the toolchain REJECTs
//    [4015]. The parser ACCEPTS it: the clause reads as an ordinary `SLet` statement and
//    the restriction is a grammar rule the parser does not model. The parser is therefore
//    MORE PERMISSIVE here, so this is a MISSED error and not a false positive -- a
//    different kind of gap, and not one this increment may claim to close. The toolchain
//    half of the claim is asserted, and gated, in the settle script.
//
// 3. `for ; n > 0 {` -- an empty init clause with a two-clause header. `moon check`
//    ACCEPTs it; the analyzer reports a parse error, because `parse_c_for` ends with an
//    unconditional `expect(TSemi)` after the condition while MoonBit makes the third clause
//    optional. Pre-existing and untouched here: the `if !self.at(TSemi)` guard that skips
//    an empty init is unchanged, so neither branch of it runs. Recorded, not asserted in
//    either direction -- a row pinning the gap would make it permanent, and a row pinning
//    the fix would claim an increment that did not happen.
