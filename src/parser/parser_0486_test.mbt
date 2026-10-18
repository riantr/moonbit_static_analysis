//| Tests for 0486 -- a `+`-JOINED EFFECT clause, `-> T noraise + nocancel`.
//
//| THE DEFECT. `parse_raise_effect` consumed `noraise` and returned, leaving `+ nocancel` to be
//| read as code. It is the boundary line of `src/internal/coroutine/async_primitive.mbt:16`, a
//| file that read ZERO lines, and of `internal/coroutine/coroutine.mbt:100`.
//
//| MEASURED against this analyzer's own parser, before the fix:
//
//|     fn f() -> Unit noraise                    first_error = 0   <- already works
//|     fn f() -> Unit noraise + nocancel         first_error = 1   <- HERE
//|     async fn[T] g(cb : ...) -> T noraise + nocancel = "%async.suspend"
//|                                              first_error = 1
//|     fn f() -> Unit (noraise + nocancel)      first_error = 1
//
//| *** THE PAIR IS MATCHED, NOT LOOPED, AND THE SETTLE IS THE ONLY REASON. ***
//| `_verify/settle_0486_append_nextline_and_effects.ps1`, 13 rows / 5 controls, GATE OK:
//
//|   ACCEPT      `fn f() -> Unit noraise + nocancel { () }`
//|   REJECT(3002) `fn f() -> Unit raise + noraise { () }`
//|                 "unexpected token `noraise`, you may expect `nocancel`"
//|   REJECT(4074) `fn f() noraise + nocancel { () }`   -- the combined effect needs an annotation
//
//| So `+` DOES join two effects, but not any two. A `while at_name(anything)` loop would read
//! `raise + noraise`, which the compiler refuses -- a MISSED error, the liberal direction this
//! reader has never once taken. Two words is the grammar; a loop would be a guess.
//|
//| *** 0487 FALSIFIED ONE CLAUSE IN THIS FILE, AND IT IS CORRECTED HERE RATHER THAN ONLY IN ITS
//! OWN GATE. *** The row "the single-effect spellings are unaffected" used to carry the note "the
//! toolchain licenses `noraise + nocancel`, not `nocancel + noraise`". Settle 0487 row B1 settled
//! `nocancel + noraise` ACCEPT, so that was wrong: the order is symmetric. The assertion itself
//! was only ever about the SINGLE-effect spellings and still holds; the claim in its comment did
//! not. `mutate_0487` M4 now KILLS the `was_noraise` test that this gate declared unobservable.
//
//| ONE FIX COVERS THREE CALL SITES (parser.mbt:1633, :2127, :5875) -- the signature, a function
//| type and a parameter position all route here, so there is one grammar and one reader.

///|
/// The corpus shape: `async`, a TYPE-PARAMETER list, a callback parameter, the combined effect,
/// and the foreign-function body. Four things at once, which is why it is the first row -- a
/// reader that handles the simple spelling and drops this one would still look right.
test "0486: the corpus shape reads whole" {
  let r = @parser.parse(
    "///|\nasync fn[T] async_suspend(cb : ((T) -> Unit) -> Unit) -> T noraise + nocancel = \"%async.suspend\"\n",
  )
  assert_eq(r.first_error, 0)
}

///|
/// The plain form, and the row that pins WHERE the `+` is consumed -- after `noraise` and before
/// the body's `{`. If the two extra tokens were taken after the brace, the file would still parse
/// and this row would still pass, so the body is checked below by a NAME it introduces.
test "0486: a combined effect clause reads before the body" {
  let r = @parser.parse("///|\nfn f() -> Unit noraise + nocancel {\n  1\n}\n")
  assert_eq(r.first_error, 0)
}

///|
/// THE BODY IS REACHED, which is the non-vacuous half of the row above.
///
/// `first_error == 0` is satisfiable by a reader that consumed the clause and then swallowed the
/// brace, the body and the closing brace as part of the type annotation -- the file parses, and
/// every statement after it is wrong. So this asserts that a name the body binds is still a
/// function in the tree. That is the same argument 0482's M3 and 0485's rows rest on.
test "0486: the body after a combined effect is still read" {
  let r = @parser.parse(
    "///|\nfn f() -> Unit noraise + nocancel {\n  helper()\n}\n\nfn helper() -> Unit {\n  ()\n}\n",
  )
  assert_eq(r.first_error, 0)
  match r.tree.body[0].kind {
    @ast.SFunc(name, _, _, stmts, _) => {
      assert_eq(name, "f")
      assert_eq(stmts.length(), 1)
    }
    _ => assert_true(false)
  }
}

///|
/// THE GUARD: `raise + noraise` IS NOT READ.
///
/// The toolchain refuses it (3002), and a reader that looped over effect names would swallow it --
/// which is the liberal direction, and invisible in every corpus number because accepting an
/// illegal program removes no blocker. This row exists so the choice is pinned rather than
/// incidental: someone generalising the clause to `+ any effect` turns this red.
test "0486: the rejected pair is not read" {
  let r = @parser.parse("///|\nfn f() -> Unit raise + noraise {\n  ()\n}\n")
  assert_true(r.first_error > 0)
}

///|
/// THE OTHER HALF OF THE SAME GUARD, and the row M2 needed.
///
/// The row above uses `raise + noraise`, which the `noraise`-FIRST test blocks before the operand's
/// NAME is ever examined -- so it pins half the guard and cannot see the other half. Mutation M2
/// generalised the operand to "any name" and SURVIVED, and the reason was this missing row rather
/// than a wrong reader.
///
/// `_verify/settle_0486_append_nextline_and_effects.ps1` rows A5/A6 settle the half nobody had
/// asked: `noraise + raise` REJECTs 3002 and `noraise + whatever` REJECTs 3002. So the narrow
/// guard IS load-bearing, and a reader that looped would accept a program the compiler refuses.
test "0486: an arbitrary effect after the + is not read" {
  assert_true(
    @parser.parse("///|\nfn f() -> Unit noraise + whatever {\n  ()\n}\n").first_error >
    0,
  )
  assert_true(
    @parser.parse("///|\nfn f() -> Unit noraise + raise {\n  ()\n}\n").first_error >
    0,
  )
}

///|
/// THE SINGLE-EFFECT SPELLINGS STILL WORK, in both orders, so the pair did not cost the single
/// word. `nocancel` leads here rather than `noraise`, which is the arm the fix must NOT extend.
test "0486: the single-effect spellings are unaffected" {
  assert_eq(
    @parser.parse("///|\nfn f() -> Unit noraise {\n  ()\n}\n").first_error,
    0,
  )
  assert_eq(
    @parser.parse("///|\nfn f() -> Unit nocancel {\n  ()\n}\n").first_error,
    0,
  )
}

///|
/// AND `-> T raise E` STILL CARRIES ITS ERROR TYPE, which is the sibling this reader shares a
/// slot with. The combined-effect branch returns before that code, so this is the row that would
/// catch the two arms interfering.
test "0486: a raise effect still carries its error type" {
  let r = @parser.parse(
    "///|\nfn f() -> Unit raise MyErr {\n  ()\n}\n\nsuberror MyErr\n",
  )
  assert_eq(r.first_error, 0)
}
