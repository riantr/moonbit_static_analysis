//| Tests for 0503 -- the `?` marker on a raise clause.
//
//! The parser read the `?` in the FUNCTION-TYPE position and not in the RETURN position, so
//! `fn f() -> Int raise? { 1 }` -- a program the toolchain accepts -- died at the `?`. The
//! reach was 162 return-position sites in 31 files, ALL of them in moonbitlang/core
//! 0.1.20260920+7d59c7ec9, and zero in the other six corpora and zero in this analyzer's
//! own source.
//!
//! THE RULE IS NOT "A `?` AFTER ANY CLAUSE". It is "A `?` AFTER A BARE `raise`", and the
//! settle (`_verify/settle_0503_raise_q.ps1`, 24 rows, compiler as oracle) CORRECTED the
//! premise of the first draft, which had assumed any clause would do:
//!
//!     -> Int raise?              ACCEPTED   the bare raise, marked optional
//!     -> Int raise MyErr?        REJECTED   4032 + 3002 -- a typed raise has no
//!                                            optional form
//!     -> Int raise + nocancel?   REJECTED   3002 "unexpected token `?`"
//!     -> Int noraise?            REJECTED   an optional marker on "does not raise"
//!     -> Int nocancel?           REJECTED
//!     -> Int! ?                  REJECTED   the short form has no optional form
//!
//! => 判据: a reader that accepted the `?` after ANY clause would read programs the
//! toolchain refuses. So the REJECT rows below are not decoration -- they are what says
//! the fix's SCOPE is a fact rather than a guess, and each one of them is a row a
//! too-liberal implementation would fail.
//!
//! AND THE `?` IN THE FUNCTION-TYPE POSITION DOES TWO JOBS, which is why the first
//! draft of this increment broke fourteen existing tests. `(Int) -> Int raise?` is the
//! optional-raise marker and `((Int) -> Int)?` is the NULLABLE marker on a parenthesised
//! group, and the second one has no clause in front of it at all. So the rule is asked
//! about the CLAUSE and not about the `?`, and the nullable group is pinned below.
//!
//! THE `?` IS CONSUMED, NOT RECORDED. The return annotation string stays "Int" and not
//! "Int?", because `ann_to_ty` maps a WHOLE string and "Int?" is not one of its spellings:
//! `ann_to_ty("Int")` is TInt and `ann_to_ty("Int?")` is Unknown. The two rows below that
//! pin the difference are the nullable `?` (which IS recorded) and the effect `?` (which is
//! not) -- and the pair is what stops a later reader from "tidying" one of them into the
//! other.

///|
/// THE TARGET SHAPE: a `raise?` on a return annotation. This is the form the toolchain
/// accepts and the analyzer used to refuse.
test "0503: a return annotation may carry `raise?`" {
  let r = @parser.parse("fn f() -> Int raise? {\n  1\n}\n")
  assert_eq(r.first_error, 0)
}

///|
/// A FUNCTION LITERAL, which is a THIRD position and not a variant of the first: the
/// literal's tail is read by `parse_fn_literal`, which is a different function with its
/// own reader. 0471's rows are the precedent -- the same construct spelled three ways is
/// three places to forget it.
test "0503: a function literal may carry `raise?`" {
  let r = @parser.parse(
    "fn f() -> Unit {\n  let m = fn(c : Char) -> Int raise? {\n    1\n  }\n  ignore(m)\n}\n",
  )
  assert_eq(r.first_error, 0)
}

///|
/// THE FUNCTION-TYPE POSITION, which the parser already read. It is here as the CONTROL
/// for the fix: if this row were red, the premise of the whole increment would be wrong.
test "0503: a function type may carry `raise?`" {
  let r = @parser.parse("fn f(g : (Int) -> Int raise?) -> Int {\n  0\n}\n")
  assert_eq(r.first_error, 0)
}

///|
/// THE CORPUS SHAPE, on a type this package owns: a `pub` method whose PARAMETER carries
/// a function type with `raise?` AND whose RETURN annotation carries `raise?`. This is
/// the shape 31 core files are written in, and it is the only row that exercises BOTH
/// positions in one declaration.
test "0503: the corpus shape carries `raise?` in both positions" {
  let r = @parser.parse(
    "pub struct Box[T] {\n  v: T\n}\n\npub fn[T] Box::each(self : Box[T], f : (T) -> Unit raise?) -> Unit raise? {\n  f(self.v)\n}\n",
  )
  assert_eq(r.first_error, 0)
}

///|
/// THE `?` ON A JOINED CLAUSE (`raise + nocancel`), which the toolchain REJECTS with
/// 3002. This is the row that separates "the clause ends here" from "the clause is a
/// bare raise": the two differ by ONE token, and the `+` is that token.
test "0503: the `?` on a joined effect clause is still a parse error" {
  let r = @parser.parse("fn f() -> Int raise + nocancel? {\n  1\n}\n")
  assert_true(r.first_error > 0)
}

///|
/// THE `?` ON A `noraise`, which the toolchain REJECTS. An optional marker on "does not
/// raise" says the opposite of what it looks like, so this is the row where a liberal
/// reader would be most wrong.
test "0503: the `?` on a `noraise` is still a parse error" {
  let r = @parser.parse("fn f() -> Int noraise? {\n  1\n}\n")
  assert_true(r.first_error > 0)
}

///|
/// THE `?` ON A `nocancel`, which the toolchain REJECTS.
test "0503: the `?` on a `nocancel` is still a parse error" {
  let r = @parser.parse("fn f() -> Int nocancel? {\n  1\n}\n")
  assert_true(r.first_error > 0)
}

///|
/// THE `?` AFTER THE SHORT `!` FORM, which the toolchain REJECTS. `!` is a token of its
/// own and not a `raise` with a spelling, so the bare-raise rule excludes it
/// STRUCTURALLY -- the same way `! + nocancel` is excluded from the joined grammar.
test "0503: the `?` after the short `!` form is still a parse error" {
  let r = @parser.parse("fn f() -> Int! ? {\n  1\n}\n")
  assert_true(r.first_error > 0)
}

///|
/// THE SAME FOUR SPELLINGS IN THE FUNCTION-TYPE POSITION, which is where the old reader
/// was TOO WIDE: it took the `?` after ANY clause, so it accepted four programs the
/// toolchain rejects (settle rows n_ft_noraise_q .. q_ft_joined_q, 3002 each). These
/// rows are what says the narrowing reached that position too.
test "0503: a function type may not carry `raise?` on a `noraise`" {
  let r = @parser.parse("fn f(g : (Int) -> Int noraise?) -> Int {\n  0\n}\n")
  assert_true(r.first_error > 0)
}

///|
test "0503: a function type may not carry `raise?` on a `nocancel`" {
  let r = @parser.parse("fn f(g : (Int) -> Int nocancel?) -> Int {\n  0\n}\n")
  assert_true(r.first_error > 0)
}

///|
test "0503: a function type may not carry `raise?` after the short `!` form" {
  let r = @parser.parse("fn f(g : (Int) -> Int! ?) -> Int {\n  0\n}\n")
  assert_true(r.first_error > 0)
}

///|
test "0503: a function type may not carry `raise?` on a joined clause" {
  let r = @parser.parse(
    "fn f(g : (Int) -> Int raise + nocancel?) -> Int {\n  0\n}\n",
  )
  assert_true(r.first_error > 0)
}

///|
/// THE SAME FOUR SPELLINGS IN THE FUNCTION-LITERAL POSITION, which is the third site
/// and the one the first draft of the fix would have left behind. A function literal
/// reads its tail in its own function, so a rule applied at the other two sites says
/// nothing about this one.
test "0503: a function literal may not carry `raise?` on a `noraise`" {
  let r = @parser.parse(
    "fn f() -> Unit {\n  let m = fn(c : Char) -> Int noraise? {\n    1\n  }\n  ignore(m)\n}\n",
  )
  assert_true(r.first_error > 0)
}

///|
test "0503: a function literal may not carry `raise?` on a `nocancel`" {
  let r = @parser.parse(
    "fn f() -> Unit {\n  let m = fn(c : Char) -> Int nocancel? {\n    1\n  }\n  ignore(m)\n}\n",
  )
  assert_true(r.first_error > 0)
}

///|
test "0503: a function literal may not carry `raise?` after the short `!` form" {
  let r = @parser.parse(
    "fn f() -> Unit {\n  let m = fn(c : Char) -> Int! ? {\n    1\n  }\n  ignore(m)\n}\n",
  )
  assert_true(r.first_error > 0)
}

///|
test "0503: a function literal may not carry `raise?` on a joined clause" {
  let r = @parser.parse(
    "fn f() -> Unit {\n  let m = fn(c : Char) -> Int raise + nocancel? {\n    1\n  }\n  ignore(m)\n}\n",
  )
  assert_true(r.first_error > 0)
}

///|
/// THE NULLABLE GROUP, and this is the row the first draft of the fix broke. The `?`
/// here has NO clause in front of it -- it is the NULLABLE marker on a parenthesised
/// function type, not an optional raise -- and a rule that said "a `?` is only legal
/// after a bare raise" would have taken it away along with the four illegal spellings
/// above. The rendered annotation is asserted because "it parses" cannot tell this row
/// from one where the `?` was swallowed by something else.
test "0503: a parenthesised function type is still optional (control)" {
  let r = @parser.parse("fn f(g : ((Int) -> Int)?) -> Int {\n  0\n}\n")
  assert_eq(r.first_error, 0)
  match r.tree.body[0].kind {
    @ast.SFunc(_, params, _, _, _) =>
      assert_eq(params[0].tyann, "((Int) -> Int)?")
    _ => assert_true(false)
  }
}

///|
/// THE NULLABLE RETURN TYPE IS STILL RECORDED, and this is the CONTROL for the row two
/// below it. `-> Int?` is a different `?` from `-> Int raise?`: one is part of the TYPE
/// and one is part of the EFFECT CLAUSE, and a reader that treated them alike would take
/// the nullable marker off the type.
test "0503: a nullable return type is unchanged (control)" {
  let r = @parser.parse("fn f() -> Int? {\n  Some(1)\n}\n")
  assert_eq(r.first_error, 0)
  match r.tree.body[0].kind {
    @ast.SFunc(_, _, retann, _, _) => assert_eq(retann, "Int?")
    _ => assert_true(false)
  }
}

///|
/// THE EFFECT `?` IS NOT RECORDED, and this is the row that says so. The annotation
/// string stays "Int" -- not "Int?", because `ann_to_ty` maps a WHOLE string and "Int?"
/// is not one of its spellings: `ann_to_ty("Int")` is TInt and `ann_to_ty("Int?")` is
/// Unknown, so recording the effect marker would make the declared return type
/// UNKNOWN. Consuming it is what makes the file readable; recording it is a separate
/// decision, and this is not that decision.
test "0503: the effect `?` is consumed, not recorded in the return annotation" {
  let r = @parser.parse("fn f() -> Int raise? {\n  1\n}\n")
  assert_eq(r.first_error, 0)
  match r.tree.body[0].kind {
    @ast.SFunc(_, _, retann, _, _) => assert_eq(retann, "Int")
    _ => assert_true(false)
  }
}

///|
/// THE ALREADY-SUPPORTED SPELLINGS, all three, as regression guards. A fix that taught
/// the reader the optional marker could easily have cost it one of these -- and the
/// corpus carries all three, so a regression here would be a corpus regression.
test "0503: a plain `raise` return annotation is unchanged (control)" {
  let r = @parser.parse("fn f() -> Int raise {\n  1\n}\n")
  assert_eq(r.first_error, 0)
}

///|
test "0503: a typed `raise` return annotation is unchanged (control)" {
  let r = @parser.parse(
    "priv suberror MyErr\nfn f() -> Int raise MyErr {\n  1\n}\n",
  )
  assert_eq(r.first_error, 0)
}

///|
test "0503: the short `!` form is unchanged (control)" {
  let r = @parser.parse("fn f() -> Int! {\n  1\n}\n")
  assert_eq(r.first_error, 0)
}

///|
/// A `raise?` FUNCTION IS CALLED PLAINLY. The toolchain rejects `g!()` ("unexpected
/// `f!(..)`, you may expect `f(..)`"), so a reader that expected the `!` at the call site
/// would be wrong here. This is the settle's row L.
test "0503: a `raise?` function is called without a marker" {
  let r = @parser.parse(
    "fn g() -> Int raise? {\n  1\n}\n\nfn h() -> Int {\n  g()\n}\n",
  )
  assert_eq(r.first_error, 0)
}

///|
/// A MEASURED DIVERGENCE, PINNED ON PURPOSE, and this is a TRIPWIRE rather than a
/// claim that the behaviour is right.
///
/// The toolchain REJECTS `-> Int raise MyErr?` (settle row b_ret_raise_typed_q: 4032 +
/// 3002) -- a raise that names an error type has no optional form. This analyzer
/// ACCEPTS it, and it did so before 0503 as well: the `?` is taken by the type reader as
/// the NULLABLE MARKER on the error type, so it never reaches the optional-raise rule at
/// all. The clause is `raise MyErr?` and the error type is `MyErr?`.
///
/// The row is here so that the divergence is a FACT in this repository rather than a
/// surprise: a reader who assumes the analyzer refuses this shape would be wrong, and the
/// four REJECT rows above would look like they covered it. The fix belongs in
/// `parse_raise_effect` -- which reports nothing about the type it reads -- and that
/// function is pinned by gates 0466 and 0487, so it is a separate increment.
test "0503: a typed raise with a `?` is read as a nullable error type (measured divergence)" {
  let r = @parser.parse(
    "priv suberror MyErr\nfn f() -> Int raise MyErr? {\n  1\n}\n",
  )
  assert_eq(r.first_error, 0)
}
