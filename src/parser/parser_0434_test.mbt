///|
/// An ARROW LAMBDA in expression position.
///
/// Settled with the toolchain: `_verify/probe_sweep_0434.ps1` cases
/// `lam_arg_paren1`, `lam_arg_paren2`, `lam_arg_block`, `lam_let_paren1`,
/// `lam_let_paren2`, `lam_bare_single_param` and `lam_explicit_param_type` --
/// all MOON-OK / SELF-FAIL before this change, all MOON-OK / SELF-OK after,
/// each in its own package beside a broken canary.
///
/// This was the LARGEST single cause behind moui's blocked files and I had it
/// wrong for several increments: the reason strings said "unexpected token
/// `:`" and "expected `)`", and I ranked those rows as if they were about
/// `is` patterns and function types. They were about lambdas. The distinction
/// that mattered: `at_arrow_lambda` (bare `x =>`) ran on a POSITIONAL call
/// argument, `at_lambda_head` (all spellings) ran only after a NAMED `name =`,
/// and nothing checked either from a `let` right-hand side. So `g(a => a)`
/// worked and `g((a) => a)` and `let h = (a, b) => a + b` did not.
///
/// The test that matters asserts the body was SKIPPED and the parse stayed in
/// step -- the statement after the lambda is still a statement. A lambda body
/// consumed too much would parse the file and mis-attribute everything after
/// it, which no `first_error == 0` can see.
test "0434: a parenthesised arrow lambda is read in let position" {
  let r = @parser.parse(
    "fn g(cb : (Int, Int) -> Int) -> Int {\n  cb(1, 2)\n}\nfn f() -> Int {\n  let h = (a, b) => a + b\n  h(1, 2)\n}\n",
  )
  assert_eq(r.first_error, 0)
  assert_eq(r.reports.length(), 1)
  assert_eq(
    r.reports[0].message,
    "short lambda is outside the analyzed subset; it was read but not analysed",
  )
  // TWO statements in `f`, not one folded expression and not three.
  match r.tree.body[1].kind {
    @ast.SFunc(_, _, _, body, _) => assert_eq(body.length(), 2)
    _ => assert_true(false)
  }
}

///|
/// The same lambda as a POSITIONAL call argument. This is the spelling that
/// `at_arrow_lambda` could never reach because it matches only a bare name,
/// and it is what most of moui writes:
///   zone.on_file_drop((paths, _point) => on_drop(paths))
test "0434: a parenthesised arrow lambda is read as a positional argument" {
  let r = @parser.parse(
    "fn g(cb : (Int) -> Int) -> Int {\n  cb(1)\n}\nfn f() -> Int {\n  g((a) => a + 1)\n}\n",
  )
  assert_eq(r.first_error, 0)
  assert_eq(r.reports.length(), 1)
}

///|
/// Is any report carrying this message? Used where the NOTICE matters rather
/// than the count: a source with a type declaration in it emits its own
/// "outside the analyzed subset" notice, so `reports.length()` cannot be
/// compared against 1 without also counting somebody else's declaration.
fn has_notice(r : @parser.ParseResult, msg : String) -> Bool {
  for rep in r.reports {
    if rep.message.contains(msg) {
      return true
    }
  }
  false
}

///|
/// A TYPED parameter in the lambda head -- moui `views/layout/layout_flow.mbt:83`
/// writes `let static_children = (_node : Flow) => children`.
test "0434: an arrow lambda with an explicitly typed parameter is read" {
  let r = @parser.parse(
    "enum Flow {\n  Leaf\n}\nfn take(cb : (Flow) -> Int) -> Int {\n  cb(Flow::Leaf)\n}\nfn f() -> Int {\n  let children = 7\n  let static_children = (_node : Flow) => children\n  take(static_children)\n}\n",
  )
  assert_eq(r.first_error, 0)
  assert_true(has_notice(r, "short lambda is outside the analyzed subset"))
}

///|
/// A BRACE body, skipped balanced. moui's `(_descriptor, run) => { ... }` and
/// `let start = dispatch => { ... }` are both this shape.
test "0434: a brace-bodied arrow lambda is skipped whole" {
  let r = @parser.parse(
    "fn g(cb : (Int) -> Int) -> Int {\n  cb(1)\n}\nfn f() -> Int {\n  g((a) => {\n    a + 1\n  })\n}\n",
  )
  assert_eq(r.first_error, 0)
  assert_eq(r.reports.length(), 1)
}

///|
/// REGRESSION, and the reason this file exists in two halves.
///
///     fn T::empty() -> T {
///       T::{}
///     }
///     fn is_const(self : T) -> Bool {
///       match self.values {
///         true => true
///       }
///     }
///
/// Putting the lambda branch in `parse_expr` put `at_lambda_head` in front of
/// every expression, and that arm treats a `:` as the start of a parameter's
/// type annotation -- which `::` also begins. It then scanned forward to the
/// next `=`, and `=>` is `TAssign` + `TGt`. So `T::{}` plus any later `=>` read
/// as ONE enormous lambda head: the parser ate the struct literal, the function
/// between them, and the match, and the file died with `expected type name`.
///
/// Measured on this repo's own `src/core/core.mbt`, where `T::{}` in
/// `IfaceSymTab::empty()` sits 60 lines before `match self.values.get(name) {`.
/// The self-scan caught it (`69/71 files`, where it had been `71/71`); the
/// 551-test suite did NOT, because no test had a `::` expression and a `=>` in
/// the same file.
///
/// So the two shapes are asserted TOGETHER, deliberately. Either one alone
/// passes on the broken parser.
test "0434 REGRESSION: a :: expression followed by a => arm is not one lambda" {
  let r = @parser.parse(
    "struct T {\n  values : Bool\n}\nfn T::empty() -> T {\n  T::{}\n}\nfn is_const(self : T) -> Bool {\n  match self.values {\n    true => true\n    false => false\n  }\n}\n",
  )
  assert_eq(r.first_error, 0)
  // Two top-level declarations survived, so nothing in between was eaten.
  assert_eq(r.tree.body.length(), 2)
}

///|
/// CONTROL for the regression above: the same file WITHOUT the `=>` arm. If
/// this went red, the regression test would be passing for the wrong reason --
/// about `T::{}` alone rather than about the `::`-then-`=>` pairing.
test "0434 control: a :: expression with no => anywhere in the file still parses" {
  let r = @parser.parse(
    "struct T {\n  values : Bool\n}\nfn T::empty() -> T {\n  T::{}\n}\nfn is_const(self : T) -> Bool {\n  self.values\n}\n",
  )
  assert_eq(r.first_error, 0)
  // Two top-level declarations, so the `T::{}` did not eat what followed.
  assert_eq(r.tree.body.length(), 2)
}

///|
/// A comprehension's OWN `=>` is spelled exactly like a lambda's, and it is not
/// a lambda. Putting the branch in `parse_expr` broke five comprehension tests
/// on the first run -- `[ for x in self => x + 1 ]` read its own iterable `a`
/// as a bare-parameter lambda.
///
/// All THREE call sites that can be followed by that `=>` are pinned here: the
/// iterable, the guard, and the body. Asserting only the body would leave the
/// other two free to regress, and they fail differently -- the guard's, for
/// instance, dies on the arrow rather than on the iterable.
test "0434: a comprehension's arrow is not read as a lambda" {
  let r = @parser.parse(
    "fn f(self : Array[Int]) -> Array[Int] {\n  [ for x in self => x + 1 ]\n}\n",
  )
  assert_eq(r.first_error, 0)
  assert_eq(r.reports.length(), 0)
}

///|
/// The same, with a GUARD, which is moonbitlang/core's spelling and sits
/// between the iterable and the arrow.
test "0434: a guarded comprehension's arrow is not read as a lambda" {
  let r = @parser.parse(
    "fn f(a : Array[Int]) -> Array[Int] {\n  [ for x in a if x > 0 => x ]\n}\n",
  )
  assert_eq(r.first_error, 0)
  assert_eq(r.reports.length(), 0)
}

///|
/// CONTROL for the two above: a real lambda in the same position still reads.
/// Without it, "no reports" would be satisfied by a parser that ignored every
/// `=>` it saw.
test "0434 control: a real lambda argument is still read" {
  let r = @parser.parse(
    "fn g(cb : (Int) -> Int) -> Int {\n  cb(1)\n}\nfn f() -> Int {\n  g((a) => a)\n}\n",
  )
  assert_eq(r.first_error, 0)
  assert_eq(r.reports.length(), 1)
  assert_eq(
    r.reports[0].message,
    "short lambda is outside the analyzed subset; it was read but not analysed",
  )
}

///|
/// CONTROL for the two `::` tests above, and the last one in this file: a
/// plain `let` whose value is a call, with a newline in the middle of the call's
/// arguments. This is the shape `skip_lambda_body` exists to get right, and the
/// one an over-eager body skip would swallow -- a depth-0 newline is a stop, so
/// without bracket depth this would truncate at the `g(` line and the `h(1, 2)`
/// after it would land inside the lambda.
///
/// Three drafts of a KNOWN LIMIT test sat here first, each asserting that a
/// body continuing onto the next line is truncated. None of them described
/// anything real: the lexer already suppresses a newline that follows an infix
/// operator, and bracket depth covers a call or chain that opens on one line
/// and closes on the next. All three shapes measure `PARSED 1/1`. They were
/// removed rather than weakened, because a documented limitation that no
/// measurement supports is worse than no documentation -- it would send the
/// next person looking for a defect that is not there.
test "0434: a newline inside a lambda body's call does not truncate it" {
  let r = @parser.parse(
    "fn g(a : Int, b : Int) -> Int {\n  a\n}\nfn f() -> Int {\n  let h = (a, b) => g(\n    a,\n    b,\n  )\n  h(1, 2)\n}\n",
  )
  assert_eq(r.first_error, 0)
  // TWO statements: the `let` and the call. Had the body been cut at the
  // newline, `h(1, 2)` would have been swallowed into it and there would be one.
  match r.tree.body[1].kind {
    @ast.SFunc(_, _, _, body, _) => assert_eq(body.length(), 2)
    _ => assert_true(false)
  }
}
