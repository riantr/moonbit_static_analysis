//| Tests for 0482 -- a clause separator is a `;` OR A LINE BREAK.
//|
//| THE DEFECT. `parse_c_for` gated the condition and the update behind one `if
//! self.at(TSemi)`. A header with no semicolon therefore skipped the ENTIRE clause chain,
//! and the cursor -- sitting on the condition -- was handed to `parse_block`, which
//| reported `expected '{'`. `bmp.mbt:117-119` is that program:
//|
//|     for i = 0
//|         i < num_colors && i * 4 + palette_offset + 3 < self.data.length()
//!         i = i + 1 {
//!
//! and it was the last file moonbit_image 0.3.7 could not read (17/18).
//!
//| THE BOUNDARY LINE IS THE RECEIPT. `region_line` was 118, the CONDITION token, not the
//| `for` at 117. That says the head was read and only the separator was missing -- so the
//! fix belongs to the gate and not to the head. Same shape as 0481, whose
//! `unexpected token ':'` landed on `self : RuntimeEvent` eight tokens before the defect:
//| a reported token is a claim about where the reader STOPPED.
//!
//| => 判据: "IT PARSES" IS NOT THE ASSERTION HERE. The old reader could be made to consume
//! these tokens and still leave the condition as the constant `true` that an absent
//! condition desugars to -- which is exactly what it did. Every row below therefore reads
//! the DESUGARING: which `SLet` names exist, what the condition actually is, and whether the
//! update landed at the END of the loop body where `parse_c_for` puts it. A reader that
// throws the loop away passes `first_error == 0` and fails everything else.
//!
//! Settled in `_verify/settle_0482_for_header_no_semicolons.ps1`, 12 rows / 3 controls.
//! The rows that decide what the reader must NOT accept are RECORDED there, and the one
//! the reader does over-accept is asserted at the bottom of this file rather than left in
//! prose -- 0470 recorded the `for let` item in prose only because it had no measured
//! toolchain row to point at.

///|
/// THE CORPUS SHAPE. `moon check` ACCEPTs it (settle C1) and before 0482 the analyzer
/// reported `expected '{'` at line 118.
///
/// The condition is `i < n`, so the top of the expression tree must be `OpLt` -- and NOT
/// `EBool(true)`, which is what the unfixed reader left behind after skipping the chain.
/// The update clause is appended to the END of the loop body, so its being there is what
/// says the third clause was read and not mistaken for the first statement of the body.
test "0482: a newline-separated for header desugars to SLet + SWhile with its condition read" {
  let r = @parser.parse(
    "///|\nfn f(n : Int) -> Unit {\n  for i = 0\n      i < n\n      i = i + 1 {\n    ignore(i)\n  }\n}\n",
  )
  assert_eq(r.first_error, 0)
  match r.tree.body[0].kind {
    @ast.SFunc(_, _, _, body, _) =>
      match body[0].kind {
        @ast.SBlock(stmts) => {
          assert_eq(stmts.length(), 2)
          match (stmts[0].kind, stmts[1].kind) {
            (@ast.SLet("i", _, _), @ast.SWhile(cond, loop_body)) => {
              match cond.kind {
                @ast.EBin(@ast.OpLt, _, _) => ()
                _ => assert_true(false)
              }
              // The body statement, then the update clause.
              assert_eq(loop_body.length(), 2)
              // 0495: the update clause is its own statement, so the
              // interpreter can tell it from a statement that FOLLOWS a
              // `continue` -- the first is reached, the second is not. The
              // clause's being there is still what says the third clause was
              // read and not mistaken for the first statement of the body.
              match loop_body[1].kind {
                @ast.SForUpdate(updates) => {
                  assert_eq(updates.length(), 1)
                  match updates[0].kind {
                    @ast.SAssign(_, _) => ()
                    _ => assert_true(false)
                  }
                }
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
/// TWO CLAUSES AND NO UPDATE (settle C2). The neighbour of C1 rather than C1 again, and the
/// first thing a fix can get wrong: a reader that requires all THREE clauses before it will
/// read a condition passes the row above and stops dead here.
///
/// The loop body is one statement and no update is appended, so its length is the whole
/// assertion -- an implementation that read the condition and then went looking for an
/// update that is not there would either report an error or push a statement anyway.
test "0482: a newline-separated header with two clauses reads its condition and has no update" {
  let r = @parser.parse(
    "///|\nfn f(n : Int) -> Unit {\n  for i = 0\n      i < n {\n    ignore(i)\n  }\n}\n",
  )
  assert_eq(r.first_error, 0)
  match r.tree.body[0].kind {
    @ast.SFunc(_, _, _, body, _) =>
      match body[0].kind {
        @ast.SBlock(stmts) =>
          match (stmts[0].kind, stmts[1].kind) {
            (@ast.SLet("i", _, _), @ast.SWhile(cond, loop_body)) => {
              match cond.kind {
                @ast.EBin(@ast.OpLt, _, _) => ()
                _ => assert_true(false)
              }
              assert_eq(loop_body.length(), 1)
            }
            _ => assert_true(false)
          }
        _ => assert_true(false)
      }
    _ => assert_true(false)
  }
}

///|
/// THE CORPUS CONDITION ITSELF (settle C3): `&&` and `<` chained, with `<` applied to a
/// call result, one clause over two comparisons. `at_sep` treats every `TNewline` as a
/// boundary, so this is also the row that says a boundary INSIDE a clause is not a clause
/// edge -- a reader that looked for the next separator by line rather than by grammar would
/// cut this condition in half and read the tail as the update.
///
/// `OpAnd` at the top is what says the whole chain stayed one expression.
test "0482: a newline-separated header keeps a chained condition as one expression" {
  let r = @parser.parse(
    "///|\nfn f(d : Array[Int], num_colors : Int, off : Int) -> Unit {\n  for i = 0\n      i < num_colors && i * 4 + off + 3 < d.length()\n      i = i + 1 {\n    ignore(i)\n  }\n}\n",
  )
  assert_eq(r.first_error, 0)
  match r.tree.body[0].kind {
    @ast.SFunc(_, _, _, body, _) =>
      match body[0].kind {
        @ast.SBlock(stmts) =>
          match (stmts[0].kind, stmts[1].kind) {
            (@ast.SLet("i", _, _), @ast.SWhile(cond, loop_body)) => {
              match cond.kind {
                @ast.EBin(@ast.OpAnd, _, _) => ()
                _ => assert_true(false)
              }
              assert_eq(loop_body.length(), 2)
            }
            _ => assert_true(false)
          }
        _ => assert_true(false)
      }
    _ => assert_true(false)
  }
}

///|
/// THE CONTROL: THE SAME HEADER WITH SEMICOLONS. 0482 widens which token counts as a
/// separator, and the cheapest way to widen one is to make the other stop working. This row
/// is the one that catches it, and it is here rather than inferred from the settle because a
/// corpus number cannot tell "the `;` form broke" from "the newline form started working".
///
/// The assertion is deliberately the SAME desugaring as the first row, one `SLet`, an `OpLt`
/// condition, and an update at the end of the body. Two spellings producing two identical
/// trees is the claim; anything weaker would let one of them regress silently.
test "0482: a semicolon-separated for header is unchanged by 0482" {
  let r = @parser.parse(
    "///|\nfn f(n : Int) -> Unit {\n  for i = 0; i < n; i = i + 1 {\n    ignore(i)\n  }\n}\n",
  )
  assert_eq(r.first_error, 0)
  match r.tree.body[0].kind {
    @ast.SFunc(_, _, _, body, _) =>
      match body[0].kind {
        @ast.SBlock(stmts) => {
          assert_eq(stmts.length(), 2)
          match (stmts[0].kind, stmts[1].kind) {
            (@ast.SLet("i", _, _), @ast.SWhile(cond, loop_body)) => {
              match cond.kind {
                @ast.EBin(@ast.OpLt, _, _) => ()
                _ => assert_true(false)
              }
              assert_eq(loop_body.length(), 2)
              // 0495: the update clause is its own statement -- see the row
              // above for why.
              match loop_body[1].kind {
                @ast.SForUpdate(updates) => {
                  assert_eq(updates.length(), 1)
                  match updates[0].kind {
                    @ast.SAssign(_, _) => ()
                    _ => assert_true(false)
                  }
                }
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
/// THE OTHER CONTROL: A HEAD WITH NO SEPARATOR AT ALL. `for n = step() { .. }` has neither
/// a `;` nor a newline before its brace, and 0473 settled it ACCEPT. This is the shape
/// 0482 puts at the most risk -- the gate is now `at_sep`, which is true for two tokens
/// instead of one -- so the row that would catch a reader which started demanding a
/// separator it never needed lives next to the change that could introduce the demand.
///
/// `EBool(true)` is the assertion, not an incidental detail: an absent condition desugars
/// to the constant true, and that is the SAME tree the unfixed 0482 reader produced for the
/// newline header. Pinning it here is what stops that coincidence from hiding a regression.
test "0482: a for head with no separator at all still desugars to SWhile(true)" {
  // 0473's fixture VERBATIM, `let kind =` and all, so this row and that one are looking at
  // the same tree rather than at two shapes that happen to look alike. A first draft of this
  // row took the fixture from `settle_0482`'s C1 instead of from the test file, which put
  // the loop inside an `SLet`'s initialiser, and the row failed for a reason that had
  // nothing to do with the separator.
  let r = @parser.parse(
    "///|\nfn f() -> Unit {\n  for n = step() {\n    break n + 1\n  }\n}\n\nfn step() -> Int { 1 }\n",
  )
  assert_eq(r.first_error, 0)
  match r.tree.body[0].kind {
    @ast.SFunc(_, _, _, body, _) =>
      match body[0].kind {
        @ast.SBlock(stmts) => {
          assert_eq(stmts.length(), 2)
          match (stmts[0].kind, stmts[1].kind) {
            (@ast.SLet("n", _, _), @ast.SWhile(cond, _)) =>
              match cond.kind {
                @ast.EBool(true) => ()
                _ => assert_true(false)
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
/// THE NEGATIVE CONTROL, and the one that keeps the row above honest. `moon check` REJECTs
/// this with [3002, 4021] — settle C4, the `parser_0470_test.mbt` fixture 1 — because
/// MoonBit requires the head on the `for` line.
///
/// 0482 made the clause chain POSITIONAL and permissive, and the obvious way to over-apply
/// that is to read any header that looks clause-ish. This row says it does not: the analyzer
/// still refuses exactly the program the compiler refuses, so the two AGREE and neither is
/// reporting on code the other accepts. Without it, the row above could be a one-off
/// accident rather than a boundary.
///
/// The assertion is `!= 0` rather than a message. Which token the reader stops ON is a claim
/// about where it stopped — 0481's `unexpected token ':'` named `self : RuntimeEvent` and was
/// eight tokens from the defect — and pinning the message here would pin that accident.
test "0482: a head on the line after the `for` is still refused, as the toolchain refuses it" {
  let r = @parser.parse(
    "///|\nfn f(n : Int) -> Unit {\n  for\n    i = 0;\n    i < n;\n    i = i + 1\n  {\n    ignore(i)\n  }\n}\n",
  )
  assert_true(r.first_error != 0)
}

///|
/// A MISSED ERROR, ASSERTED RATHER THAN LEFT IN PROSE. `moon check` REJECTs this with
/// [3002] (settle `record_all_on_one_line`, re-measured by this increment): the newline is
/// what makes the header legal, and on one line there is none.
///
/// The analyzer reads it anyway, because `at_sep` cannot tell "a line break I skipped" from
/// "a token that happened to follow" without also tracking column positions, and the
/// analysis had not settled whether a wrapped `for i = 0;\n  i < n;` header would be caught
/// by the same rule. A guard built on that guess would risk a FALSE error on legal code,
/// which is the worse direction, so the gap is stated instead.
///
/// => 判据: this row asserts a program the COMPILER REFUSES is read. It is here because the
/// alternative -- a comment -- does not fail when the behaviour changes, so the next
/// increment to tighten `at_sep` would silently contradict a note. A test that goes red on
/// the day the gap closes is worth a sentence of reader's guilt.
/// 0470 recorded the same species for `for let i = 0;` in prose only, because it had no
/// measured toolchain row; there is one here, so the bar is different.
test "0482: MISSED ERROR, the one-line no-separator header is read but moon check rejects it" {
  let r = @parser.parse(
    "///|\nfn f(n : Int) -> Unit {\n  for i = 0 i < n i = i + 1 {\n    ignore(i)\n  }\n}\n",
  )
  // `moon check`: REJECT(3002). Settle row `record_all_on_one_line`.
  assert_eq(r.first_error, 0)
  match r.tree.body[0].kind {
    @ast.SFunc(_, _, _, body, _) =>
      match body[0].kind {
        @ast.SBlock(stmts) =>
          match (stmts[0].kind, stmts[1].kind) {
            (@ast.SLet("i", _, _), @ast.SWhile(_, loop_body)) =>
              assert_eq(loop_body.length(), 2)
            _ => assert_true(false)
          }
        _ => assert_true(false)
      }
    _ => assert_true(false)
  }
}
