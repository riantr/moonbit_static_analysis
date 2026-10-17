//| Tests for 0474 -- a loop in EXPRESSION position is routed to the WRONG reader.
//|
//| THE DEFECT. `parse_atom` matches on `self.bump()`, so the loop keyword is consumed as
//| the match SCRUTINEE. `parse_loop_as_expr` then re-tested `at_name("while")` to choose
//| between `parse_while_stmt` and `parse_for_stmt` -- against a cursor that had already
//| moved past the keyword. The re-test is false for EVERY loop expression, so they all went
//| to `parse_for_stmt`, which bumped the token after the keyword as if it were `for`.
//!
//| Isolated by a temporary trace, added and then reverted:
//!
//!     TRACE atom enter    p=13 cur=`while`
//!     TRACE atom dispatch p=14 cur=`a`
//!     TRACE as_expr       p=14 cur=`a` at_while=false
//!
//! Measured trigger, one fixture per row:
//!
//!     while a { 1 }        parsed   (nothing after the keyword to misread)
//!     while a > 0 { 1 }    `unexpected token `>``
//!     while a + 0 { 1 }    `unexpected token `+``
//!     while 1 < 2 { 1 }    `unexpected token `<``
//!     while g(a) > 0 { 1 } parsed   (a CALL head survives the misroute)
//!     all of the above in STATEMENT position: parsed
//!
//! The call-head row is the reason this went undiagnosed for so long, and the `if`-branch
//! row is the reason it could have stayed undiagnosed: `if a { while a > 0 { 1 } } else { 2 }`
//! parses too, because the `if` arm SKIPS the branch whole. An `if` branch is not evidence
//! about anything inside it, and a call head is not evidence that the head is handled.
//!
//! The fix restores the cursor before dispatching, so every downstream reader sees exactly
//! the state its own comments describe. Settled in `_verify/settle_0474_loop_expr.ps1`:
//! 7 gated rows, 2 controls, all ACCEPT.

///|
/// THE HEAD THAT BROKE, and the whole point of the increment.
test "0474: a while expression whose head carries an operator is read" {
  let r = @parser.parse(
    "///|\nfn f(a : Int) -> Unit {\n  let k : Unit = while a > 0 {\n    ignore(1)\n  }\n  ignore(k)\n}\n",
  )
  assert_eq(r.first_error, 0)
}

///|
/// THE LITERAL HEAD, which is a SEPARATE claim. It failed with `unexpected token `<``, a
/// different message from the `>` row, and the NOTPARSE message tally is what ranks the
/// remaining work -- so one defect counted under two messages would send the next
/// increment after a shape that does not exist.
test "0474: a while expression with a literal head is read" {
  let r = @parser.parse(
    "///|\nfn f() -> Unit {\n  let k : Unit = while 1 < 2 {\n    ignore(1)\n  }\n  ignore(k)\n}\n",
  )
  assert_eq(r.first_error, 0)
}

///|
/// THE CALL HEAD, and it is a CONTROL even though it passed before the fix: a fixture set
/// containing only the failing rows would never have shown that the trigger is the
/// MISROUTE rather than the operator. If a future edit breaks the call head too, this row
/// is what says so.
test "0474 control: a while expression with a call head is still read" {
  let r = @parser.parse(
    "///|\nfn g(a : Int) -> Int { a }\n\nfn f(a : Int) -> Unit {\n  let k : Unit = while g(a) > 0 {\n    ignore(1)\n  }\n  ignore(k)\n}\n",
  )
  assert_eq(r.first_error, 0)
}

///|
/// `for` IN EXPRESSION POSITION, binder header. This is the shape `settle_0472` already
/// established as legal MoonBit, and the one the analyzer had never read.
test "0474: a for expression with a binder header is read" {
  let r = @parser.parse(
    "///|\nfn f(xs : Array[Int]) -> Unit {\n  let k : Unit = for x in xs {\n    ignore(x)\n  }\n  ignore(k)\n}\n",
  )
  assert_eq(r.first_error, 0)
}

///|
/// AND THE C-STYLE HEADER, which routes through `is_c_style_for` and `parse_c_for` rather
/// than the binder reader. A fix that repaired only the binder path would pass the row
/// above and leave this one broken.
test "0474: a for expression with a C-style header is read" {
  let r = @parser.parse(
    "///|\nfn f(n : Int) -> Unit {\n  let k : Unit = for i = 0; i < n; i = i + 1 {\n    ignore(i)\n  }\n  ignore(k)\n}\n",
  )
  assert_eq(r.first_error, 0)
}

///|
/// THE STATEMENT-POSITION CONTROLS. Expression position is the thing being repaired, and a
/// repair that quietly broke statement position would trade one class of unreadable file
/// for another -- a corpus number alone would not show it, because both positions lose the
/// same files at the same rate.
test "0474 control: the same loops in statement position are still read" {
  let a = @parser.parse(
    "///|\nfn f(a : Int) -> Int {\n  while a > 0 {\n    ignore(1)\n  }\n  0\n}\n",
  )
  assert_eq(a.first_error, 0)
  let b = @parser.parse(
    "///|\nfn f(xs : Array[Int]) -> Int {\n  for x in xs {\n    ignore(x)\n  }\n  0\n}\n",
  )
  assert_eq(b.first_error, 0)
}

///|
/// THE SHAPE OF A LOOP EXPRESSION, which is the row a "does it parse" assertion cannot be.
///
/// `mutate_0474` M3 steps the cursor FORWARD in the `for` arm instead of restoring it. For
/// `for x in xs { .. }` that does not fail, and the reason is worth stating precisely: the
/// binder scan then starts past the `in`, so `is_c_style_for` returns true and `parse_c_for`
/// reads `xs` as a C-style initializer, producing a perfectly well-formed `SBlock`+`SWhile`
/// -- a wrong tree that `parse_loop_as_expr` then throws away. Every `first_error == 0` row
/// in this file stayed green under it, and so did the `body.length()` row.
///
/// That is the worst shape a mutation can have -- it does not crash, it does not error, and
/// it is WRONG -- so the row below looks at the node instead. M3 is declared SURVIVED in the
/// gate, and PROVED rather than assumed: 924/924 green AND the async corpus byte-identical
/// (parsed 396, notices 1728, unreliable 203, withheld 31, total 1931), with the 20 blocked
/// files identical name for name. Nothing observable moves, so no row here can kill it.
///
/// A loop expression yields the opaque `EBigInt` placeholder and nothing else, because the
/// subset has no loop-valued expression. That is the claim worth pinning, and it is what
/// distinguishes a loop expression from a loop.
test "0474: a loop expression binds the opaque placeholder, not a loop-derived value" {
  let r = @parser.parse(
    "///|\nfn f(xs : Array[Int]) -> Unit {\n  let k : Unit = for x in xs {\n    ignore(x)\n  }\n  ignore(k)\n}\n",
  )
  assert_eq(r.first_error, 0)
  match r.tree.body[0].kind {
    @ast.SFunc(_, _, _, body, _) =>
      match body[0].kind {
        @ast.SLet("k", _, value) =>
          match value.kind {
            @ast.EBigInt => ()
            _ => assert_true(false)
          }
        _ => assert_true(false)
      }
    _ => assert_true(false)
  }
}

///|
/// AND THE STATEMENT AFTER THE LOOP IS STILL REACHED, which is the other half: the row
/// above says the loop produced the right value, this one says the loop consumed EXACTLY
/// itself. `first_error` cannot see a cursor left a token off, and a file that parses with
/// a token silently dropped is the shape of loss this whole project is built to avoid.
test "0474: the statement after a loop expression is still read" {
  let r = @parser.parse(
    "///|\nfn f(xs : Array[Int]) -> Unit {\n  let k : Unit = for x in xs {\n    ignore(x)\n  }\n  ignore(k)\n}\n",
  )
  assert_eq(r.first_error, 0)
  match r.tree.body[0].kind {
    @ast.SFunc(_, _, _, body, _) => assert_eq(body.length(), 2)
    _ => assert_true(false)
  }
}
