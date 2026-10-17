//| Tests for 0475 -- a BINDER head followed by C-style clauses: `for p in ps; len = 0 { .. }`.
//|
//| WHY. 0473 replaced `is_c_style_for`'s delimiter test with "is the head a binder?", which
//| made this head route CORRECTLY -- to `parse_for_stmt`'s binder branch -- and that branch
//| stopped at the `;`. The error moved from `expected ';'` to `expected 'in'` and the five
//| corpus sites stayed unread. Moving an error is not removing it, so `parser_0473_test.mbt`
//| pinned the failure as a FAILING test and this increment inverted that pin.
//|
//| THE GRAMMAR IS NOT THE C-STYLE ONE. This is the part a "just reuse the list reader" fix
//| gets wrong, so the settle asked the toolchain rather than the four corpus sites.
//| `_verify/settle_0475_binder_clauses.ps1`, 2 controls and 9 rows, GATE OK:
//!
//!   for p in ps; len = 0 { .. }                 ACCEPT   legal MoonBit
//!   the declaration is readable in the body     ACCEPT
//!   for p in ps; len = 0; n = 1 { .. }          REJECT(4106) a second `;`-clause is STEPS
//!   for p in ps; len = 0; len > 0 { .. }        REJECT(3002) no condition after a binder head
//!   for p in ps; n = p.length() { .. }          REJECT(4021) the binder is NOT in scope here
//!   for p in ps; len = 0 { .. } ignore(len)     REJECT(4021) it does NOT outlive the loop
//!   for k, v in m; n = 0 { .. }                 ACCEPT   two binders compose
//!
//! => NO NEW NODE, and the two REJECT(4021) rows are what say so. The declaration cannot see
//! the binder, so it is evaluated OUTSIDE the binder's scope, and hoisting it BEFORE the loop
//! is correct by construction rather than by argument. It does not outlive the loop either --
//| the same scoping 0470 measured for the C-style init clause -- so `c_for_init`'s existing
//| conversion is reusable unchanged. The desugar is the shape `parse_c_for` already builds.
//|
//| => 判据: the settle's first draft assumed the C-style VARIABLE-LENGTH list carried across
//| the binder head, and two of its three claims flipped and it aborted. 4106 volunteered the
//| sentence that settled it. A claim that flips should be read for the compiler's complaint:
//| that complaint is usually the part of the language nobody had written down.

///|
/// THE SHAPE, and it is a row about the TREE rather than about parsing. "It parses" would be
/// satisfied by a reader that consumed the tokens and threw the loop away, which is the
/// failure mode this project keeps paying for. What has to hold is that the declaration is a
/// SEPARATE statement in front of the loop, not folded into the loop body -- that is what
/// models "the binder is not in scope for it".
test "0475: a binder head with a declaration desugars to SBlock[SLet, SFor]" {
  let r = @parser.parse(
    "///|\nfn f(ps : Array[String]) -> Unit {\n  for p in ps; len = 0 {\n    ignore(len)\n    ignore(p)\n  }\n}\n",
  )
  assert_eq(r.first_error, 0)
  match r.tree.body[0].kind {
    @ast.SFunc(_, _, _, body, _) =>
      match body[0].kind {
        @ast.SBlock(stmts) => {
          assert_eq(stmts.length(), 2)
          match (stmts[0].kind, stmts[1].kind) {
            (@ast.SLet("len", _, _), @ast.SFor("p", _, _, _)) => ()
            _ => assert_true(false)
          }
        }
        _ => assert_true(false)
      }
    _ => assert_true(false)
  }
}

///|
/// THE CONTROL, and it is the row that matters most: the COMMON case must stay a bare `SFor`.
/// Wrapping every binder head in an `SBlock` would satisfy the row above while changing the
/// node for hundreds of loops, and `stmts[1]` above would still be the SFor -- so only this
/// control distinguishes "added a wrapper where there is one" from "added a wrapper
/// everywhere".
test "0475 control: a plain binder head is still a bare SFor, with no wrapper" {
  let r = @parser.parse(
    "///|\nfn f(xs : Array[Int]) -> Unit {\n  for x in xs {\n    ignore(x)\n  }\n}\n",
  )
  assert_eq(r.first_error, 0)
  match r.tree.body[0].kind {
    @ast.SFunc(_, _, _, body, _) =>
      match body[0].kind {
        @ast.SFor("x", _, _, _) => ()
        _ => assert_true(false)
      }
    _ => assert_true(false)
  }
}

///|
/// AND THE DECLARATION IS SCOPED LIKE 0470's, which is the claim that makes `c_for_init`
/// reusable rather than duplicated. It sits in the block, so it is visible to the body; the
/// settle's REJECT(4021) says it is NOT visible after the loop, and that half is the toolchain
/// holding the analyzer to a scope the tree here cannot express on its own -- it is recorded
/// rather than asserted, so this row pins only the half the tree decides.
test "0475: the declaration is a binding the body can read, and it is not the loop binder" {
  let r = @parser.parse(
    "///|\nfn f(ps : Array[String]) -> Unit {\n  for p in ps; len = 0 {\n    ignore(len)\n    ignore(p)\n  }\n}\n",
  )
  assert_eq(r.first_error, 0)
  match r.tree.body[0].kind {
    @ast.SFunc(_, _, _, body, _) =>
      match body[0].kind {
        @ast.SBlock(stmts) =>
          match stmts[0].kind {
            // A DECLARATION, not an assignment: 0470's conversion, reached through the same
            // `c_for_init`, is what makes the binding scoped rather than a rebinding.
            @ast.SLet("len", _, value) =>
              match value.kind {
                @ast.EInt(0) => ()
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
/// TWO BINDERS PLUS A CLAUSE, which is unix.mbt:66 and windows.mbt:57 and the row where the
/// multi-binder desugar and the declaration meet. The declaration goes in front of the WHOLE
/// loop, not inside the desugared `$pair` body -- it is scoped to the loop, not to a binder.
test "0475: a two-binder head with a declaration puts the declaration before the loop" {
  let r = @parser.parse(
    "///|\nfn f(m : Map[String, String]) -> Unit {\n  for k, v in m; n = 0 {\n    ignore(k)\n    ignore(v)\n  }\n}\n",
  )
  assert_eq(r.first_error, 0)
  match r.tree.body[0].kind {
    @ast.SFunc(_, _, _, body, _) =>
      match body[0].kind {
        @ast.SBlock(stmts) => {
          assert_eq(stmts.length(), 2)
          match (stmts[0].kind, stmts[1].kind) {
            (@ast.SLet("n", _, _), @ast.SFor("$pair", _, _, _)) => ()
            _ => assert_true(false)
          }
        }
        _ => assert_true(false)
      }
    _ => assert_true(false)
  }
}

///|
/// AND THE ROW THAT KEEPS THE GRAMMAR FROM SLIDING BACK INTO THE C-STYLE LIST. A condition
/// after a binder head is REJECT(3002) by the toolchain, so the analyzer must refuse it too.
/// This is the one negative row here, and it earns its place: the obvious "simplification" is
/// to hand the tail to `c_for_inits` and walk the same variable-length list, which would
/// ACCEPT a header the compiler refuses -- a new false negative against the toolchain, in the
/// direction this project has never taken.
test "0475: a condition after a binder head is refused, as the toolchain refuses it" {
  let r = @parser.parse(
    "///|\nfn f(ps : Array[String]) -> Unit {\n  for p in ps; len = 0; len > 0 {\n    ignore(p)\n  }\n}\n",
  )
  assert_true(r.first_error != 0)
}

///|
/// THE OTHER HALF OF THE SAME SLIDE, and the sharper one: a SECOND declaration clause is not
/// a second clause of the initialization block. The toolchain reads it as for-loop STEPS and
/// answers REJECT(4106) -- "Unknown binder n in the for-loop steps" -- which is a SEMANTIC
/// error, meaning the text parsed and was then refused. Steps are a real part of this grammar
/// that this increment does not model; they are recorded as a known limit rather than guessed
/// at, so this row pins the limit instead of hiding it.
test "0475: a second declaration clause is not a second initialization clause" {
  let r = @parser.parse(
    "///|\nfn f(ps : Array[String]) -> Unit {\n  for p in ps; len = 0; n = 1 {\n    ignore(p)\n  }\n}\n",
  )
  assert_true(r.first_error != 0)
}

///|
/// `nobreak` ON A MULTI-BINDER HEAD, which the path did not call and 0475 exposed. Reading
/// `for acc, v in args; n = 0 { .. } nobreak { .. }` put three `undefined name 'nobreak'`
/// and one `undefined name 'acc'` into async/src/process/{unix,windows}.mbt as ACTIONABLE
/// findings on code `moon check` compiles. The keyword was left on the cursor and re-read as
/// an ordinary expression, and `acc` was then reported out of scope in a block that had
/// stopped being the loop's body.
///
/// STATEMENT position, not expression position, and the reason is worth stating: a loop
/// EXPRESSION goes through `parse_loop_as_expr`, which discards the statement and yields the
/// opaque `EBigInt`, so an expression-position fixture could not see this node at all -- it
/// would have passed whether or not `nobreak` was consumed.
///
/// The row asserts the SHAPE rather than the absence of a message, because "no
/// `undefined name`" is satisfied by a reader that stops early. `SNoBreak` is the only node
/// that can carry this, and its first child must be the `SBlock` -- which is what says the
/// `nobreak` attached to the whole loop INCLUDING the declaration.
test "0475: nobreak attaches to a multi-binder head that carries a declaration" {
  let r = @parser.parse(
    "///|\nfn f(args : Array[(String, Int)]) -> Unit {\n  for acc, v in args; n = 0 {\n    ignore(acc)\n  } nobreak {\n    ignore(n)\n  }\n}\n",
  )
  assert_eq(r.first_error, 0)
  match r.tree.body[0].kind {
    @ast.SFunc(_, _, _, body, _) =>
      match body[0].kind {
        @ast.SNoBreak(inner, _) =>
          match inner.kind {
            @ast.SBlock(stmts) => {
              assert_eq(stmts.length(), 2)
              match (stmts[0].kind, stmts[1].kind) {
                (@ast.SLet("n", _, _), @ast.SFor("$pair", _, _, _)) => ()
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
/// AND THE CONTROL, which is the row that says the keyword is CONSUMED rather than merely
/// unreported. The discriminator is the STATEMENT COUNT. With `nobreak` left on the cursor
/// the reader takes `nobreak { .. }` as an ordinary expression plus a block and the tail is
/// swallowed, so the body is longer than two statements; with it consumed, the loop and its
/// `nobreak` are exactly ONE statement and the tail is the second. Asserting the shape of the
/// tail instead would have tested how this AST spells a trailing expression, which is a
/// different question and not one this increment changes.
test "0475 control: the statement after a multi-binder loop with nobreak is still read" {
  let r = @parser.parse(
    "///|\nfn f(args : Array[(String, Int)]) -> Int {\n  for acc, v in args; n = 0 {\n    ignore(acc)\n  } nobreak {\n    ignore(n)\n  }\n  ignore(probe_0475_tail)\n}\n",
  )
  assert_eq(r.first_error, 0)
  match r.tree.body[0].kind {
    @ast.SFunc(_, _, _, body, _) => assert_eq(body.length(), 2)
    _ => assert_true(false)
  }
}

///|
/// AND THE CORPUS SHAPE, in EXPRESSION position, because that is reader.mbt:176 and it is
/// the shape the increment exists for. `parse_loop_as_expr` discards the statement, so the
/// assertion here is only that the header is READ -- the tree assertions above are the ones
/// that say it is read correctly.
test "0475: the corpus loop-expression shape is read" {
  let r = @parser.parse(
    "///|\nfn f(ps : Array[String]) -> Int {\n  let total = for p in ps; len = 0 {\n    continue len + p.length()\n  } nobreak {\n    len\n  }\n  total\n}\n",
  )
  assert_eq(r.first_error, 0)
}
