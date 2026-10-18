//| Tests for 0487 -- the FULL `+`-joined effect clause, `-> T <effect> + <effect>`.
//
//| WHY 0487 EXISTS. Gate 0486 shipped ONE spelling, `noraise + nocancel`, and declared the rest an
//| unobservable survivor: "no legal MoonBit pair starts with a bare `nocancel`". Settle 0487
//| (`_verify/settle_0487_combined_effect_order.ps1`, 21 rows / 6 controls, GATE OK) found that
//| reasoning TRUE AND INCOMPLETE -- three more pairs are legal, and one of them has `nocancel`
//| FIRST:
//
//|     ACCEPT   -> T noraise + nocancel       <- 0486's spelling, still the only one in any corpus
//|     ACCEPT   -> T raise + nocancel         <- 0486's DECLARED SURVIVOR
//|     ACCEPT   -> T raise MyErr + nocancel
//|     ACCEPT   -> T nocancel + noraise       <- 0486 REFUSED THIS LEGAL PROGRAM
//|     ACCEPT   -> T nocancel + raise
//|     ACCEPT   -> T nocancel + raise MyErr
//|
//|     REJECT 3002  -> T ! + nocancel
//|     REJECT 3002  -> T noraise + raise MyErr
//|     REJECT 3002  -> T raise MyErr + raise MyErr2
//|     REJECT 3002  -> T noraise + nocancel + noraise
//|     REJECT 4074  fn f() noraise + nocancel { () }
//
//| => THE GRAMMAR IS: EXACTLY TWO EFFECTS, EXACTLY ONE OF WHICH IS `nocancel`, THE OTHER BEING
//| `noraise` OR `raise [E]`, IN EITHER ORDER.
//
//| So 0486's M4 -- the `was_noraise` test, a mutation that SURVIVED as "unobservable" -- is
//| OBSERVABLE from here on, and `mutate_0487` KILLS it. A declared survivor that later becomes
//| killable is the expected shape of the workflow, not a mistake in the earlier verdict: it was
//| unobservable given the corpus of legal programs known AT THAT TIME.
//|
//| AND THE ARITY BELONGS TO THE ORDER, NOT TO THE WORD. `raise` alone takes an optional `E`, and
//| that `E` is legal ONLY when `raise` is the SECOND effect. Both directions of getting this wrong
//| are SILENT -- reading `noraise + raise MyErr` accepts a program the compiler refuses, and
//| skipping the type in `nocancel + raise MyErr` leaves `MyErr` to be parsed as code.

///|
/// The corpus shape, unchanged by 0487: `async`, a type-parameter list, a callback parameter, the
/// combined effect and a foreign-function body. Five things at once, so it is the regression row
/// that says the wider grammar did not cost the only shape any pinned corpus actually writes.
test "0487: the corpus shape still reads whole" {
  let r = @parser.parse(
    "///|\nasync fn[T] async_suspend(cb : ((T) -> Unit) -> Unit) -> T noraise + nocancel = \"%async.suspend\"\n",
  )
  assert_eq(r.first_error, 0)
}

///|
/// 0486'S OWN SPELLING, re-asserted because the guard that read it was rewritten. `left_was_nocancel`
/// is a new predicate and `noraise + nocancel` is the case where it is FALSE, so this row is the one
/// that would catch the flag being passed the wrong way round.
test "0487: noraise + nocancel still reads" {
  assert_eq(
    @parser.parse("///|\nfn f() -> Unit noraise + nocancel {\n  ()\n}\n").first_error,
    0,
  )
}

///|
/// 0486'S DECLARED SURVIVOR, now read. The `raise` arm returned before the `+` was ever reached,
/// and the join had to be added on BOTH sides of the type: `+` is not a type head, so the bare form
/// lands at the `type_head` guard while `raise E + nocancel` can only be seen AFTER the type is read.
test "0487: raise + nocancel reads, bare and with an error type" {
  assert_eq(
    @parser.parse("///|\nfn f() -> Unit raise + nocancel {\n  ()\n}\n").first_error,
    0,
  )
  assert_eq(
    @parser.parse(
      "///|\nfn f() -> Unit raise MyErr + nocancel {\n  ()\n}\n\nsuberror MyErr\n",
    ).first_error,
    0,
  )
}

///|
/// THE ROW THAT KILLS 0486'S SURVIVOR. `nocancel + noraise` is ACCEPT, so 0486's reader was not
/// merely unobservable on this shape -- it was refusing a legal program. The reader refuses it no
/// more, and the mutation that drops the `left_was_nocancel` distinction now turns this red, which
/// is what `mutate_0487` M4 measures.
test "0487: nocancel + noraise reads" {
  assert_eq(
    @parser.parse("///|\nfn f() -> Unit nocancel + noraise {\n  ()\n}\n").first_error,
    0,
  )
}

///|
/// AND `nocancel + raise`, both bare and typed -- the second half of the symmetric order.
test "0487: nocancel + raise reads, bare and with an error type" {
  assert_eq(
    @parser.parse("///|\nfn f() -> Unit nocancel + raise {\n  ()\n}\n").first_error,
    0,
  )
  assert_eq(
    @parser.parse(
      "///|\nfn f() -> Unit nocancel + raise MyErr {\n  ()\n}\n\nsuberror MyErr\n",
    ).first_error,
    0,
  )
}

///|
/// THE BODY IS REACHED after the longest spelling. `first_error == 0` is satisfiable by a reader
/// that consumed the clause and then swallowed the brace, the body and the closing brace as part
/// of a type annotation -- the file parses and every statement after it is wrong. So this asserts
/// the body is still a body. It is the non-vacuous half of the row above, and the only one of these
/// rows that would notice an error type eaten as code.
test "0487: the body after a typed second effect is still read" {
  let r = @parser.parse(
    "///|\nfn f() -> Unit nocancel + raise MyErr {\n  helper()\n}\n\nfn helper() -> Unit {\n  ()\n}\n\nsuberror MyErr\n",
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
/// `!` DOES NOT PAIR. It is `TBang` while the other three are `TName`, so a name guard excludes it
/// STRUCTURALLY -- there is no canary row in the guard keeping it out. That is worth pinning here
/// anyway, because it is the reason the row is free: someone widening the guard to "the next token
/// is an effect" instead of "the next NAME is an effect" would break it, and the toolchain refuses
/// `! + nocancel` with 3002.
test "0487: the bang form does not pair" {
  assert_true(
    @parser.parse("///|\nfn f() -> Unit ! + nocancel {\n  ()\n}\n").first_error >
    0,
  )
  assert_true(
    @parser.parse("///|\nfn f() -> Unit nocancel + ! {\n  ()\n}\n").first_error >
    0,
  )
}

///|
/// THE ORDER IS A RULE, NOT A LIST, and this is the row that says so: `noraise + raise MyErr` is
/// REJECT 3002 while `nocancel + raise MyErr` is ACCEPT, and the ONLY difference is which word came
/// first.
///
/// THE UNTYPED AND THE TYPED FORM ARE ASSERTED TOGETHER ON PURPOSE. A reader that gave `raise` the
/// same arity in both positions would read the TYPED one, and would leave the UNTYPED one still
/// unread because the `MyErr` is never reached in that case. So the typed assertion ALONE does not
/// pin the order -- it passes on a reader whose arity is wrong and whose join is right. The
/// untyped assertion is what catches the join being widened, and it is the assertion
/// `mutate_0487` M2 kills.
test "0487: the error type belongs to the order, not the word" {
  assert_true(
    @parser.parse("///|\nfn f() -> Unit noraise + raise {\n  ()\n}\n").first_error >
    0,
  )
  assert_true(
    @parser.parse(
      "///|\nfn f() -> Unit noraise + raise MyErr {\n  ()\n}\n\nsuberror MyErr\n",
    ).first_error >
    0,
  )
}

///|
/// EXACTLY TWO, NEVER A CHAIN. `noraise + nocancel + noraise` is REJECT 3002, so the clause is a
/// PAIR and not a list -- which is why the join is matched once rather than looped. A loop would
/// read the third effect, and reading an illegal program removes no blocker from any corpus, so
/// this row is the only thing standing between the two designs.
test "0487: a third effect is not read" {
  assert_true(
    @parser.parse(
      "///|\nfn f() -> Unit noraise + nocancel + noraise {\n  ()\n}\n",
    ).first_error >
    0,
  )
}

///|
/// THE SINGLE-EFFECT SPELLINGS ARE UNAFFECTED, all four of them, because the clause shares a slot
/// with each: `!`, `noraise`, `nocancel` and `raise` each take the whole arm this change rewrote.
test "0487: the single-effect spellings are unaffected" {
  assert_eq(
    @parser.parse("///|\nfn f() -> Unit noraise {\n  ()\n}\n").first_error,
    0,
  )
  assert_eq(
    @parser.parse("///|\nfn f() -> Unit nocancel {\n  ()\n}\n").first_error,
    0,
  )
  assert_eq(@parser.parse("///|\nfn f() -> Unit ! {\n  ()\n}\n").first_error, 0)
  assert_eq(
    @parser.parse("///|\nfn f() -> Unit raise {\n  ()\n}\n").first_error,
    0,
  )
}

///|
/// AND `-> T raise E` STILL CARRIES ITS ERROR TYPE on its own, which is the path the new
/// `eat_joined_effect` call at the end of the `raise` arm sits next to. Without this row, a
/// reader that called the join unconditionally and then returned would pass every combined row
/// above while breaking the ordinary typed effect.
test "0487: a bare raise effect still carries its error type" {
  let r = @parser.parse(
    "///|\nfn f() -> Unit raise MyErr {\n  ()\n}\n\nsuberror MyErr\n",
  )
  assert_eq(r.first_error, 0)
}
