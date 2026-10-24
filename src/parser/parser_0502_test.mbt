///|
/// 0502: A `match`'s ARMS ARE PARSED, NOT SKIPPED.
///
/// The rule these rows hold is one sentence: the arms of a `match` are real
/// code, and this frontend now reads them.
///
/// Before this increment the arms were consumed whole by `skip_braces`, which
/// left a HOLE in the frame of the enclosing function -- and a hole silenced
/// `UnusedLocal` and `UnusedParam` for that whole function. Measured with the
/// hole removed and nothing else changed: 1098 findings appear across the seven
/// pinned corpora and this repository's own source. Reading the arms is what
/// makes those findings true instead of invented.
///
/// => 判据: a row that asserts a count is a claim about the count. When the
/// mechanism changes, the claim changes with it -- and the row is rewritten to
/// assert the opposite, not edited until it passes.

///|
/// The arms of the first `match` in a parsed module, or an EMPTY list.
///
/// An empty list is the answer for a match that was skipped, so a row can say
/// "the arms were read" by saying how many there are.
fn first_match_arms(m : @ast.Module) -> Array[@ast.MatchArm] {
  for s in m.body {
    match s.kind {
      @ast.SFunc(_, _, _, body, _) =>
        for st in body {
          match st.kind {
            @ast.STail(e) =>
              match e.kind {
                @ast.EMatch(_, arms) => return arms
                _ => ()
              }
            @ast.SLet(_, _, init) =>
              match init.kind {
                @ast.EMatch(_, arms) => return arms
                _ => ()
              }
            _ => ()
          }
        }
      _ => ()
    }
  }
  []
}

///|
/// THE ARMS ARE IN THE TREE, and there is NO NOTICE. Both halves matter: the
/// arms prove the construct was read, and the absence of the notice proves the
/// parser stopped ANNOUNCING a limitation it no longer has. The notice's claim
/// -- "read but not analysed" -- was true when the arms were skipped and is
/// false now.
test "0502: a match's arms are parsed and it is not a skip" {
  let r = @parser.parse(
    "fn f(e : Int) -> Int {\n  match e {\n    1 => 2\n    _ => 3\n  }\n}\n",
  )
  assert_eq(r.first_error, 0)
  assert_eq(r.reports.length(), 0)
  assert_eq(r.skips.length(), 0)
  assert_eq(first_match_arms(r.tree).length(), 2)
}

///|
/// A CONSTRUCTOR PATTERN'S NAMES ARE CARRIED, and the pattern reader returns a
/// SUPERSET: `Some(x)` yields both `Some` and `x`, because `Some` is a
/// constructor and not a variable. The superset is safe in the only direction
/// that matters -- a name that binds when it should not costs silence, and a
/// name that fails to bind costs a false `no visible binding` -- so the
/// assertion is that `x` is AMONG the bindings.
test "0502: a constructor pattern's names are carried" {
  let r = @parser.parse(
    "fn f(e : Int) -> Int {\n  match e {\n    Some(x) => x\n    _ => 0\n  }\n}\n",
  )
  assert_eq(r.first_error, 0)
  let arms = first_match_arms(r.tree)
  assert_eq(arms.length(), 2)
  assert_true(arms[0].bindings.contains("x"))
}

///|
/// A STRUCT PATTERN, and this is the row the catch reader could not have
/// passed. `Point { x, y }` has a `{` in it, and `Parser::parse_catch_pattern`
/// -- the reader a `catch` arm uses -- STOPS at a `{` that opens at depth zero.
/// It would have carried `Point` and lost `x` and `y`, and the arm body would
/// then read two names that were never bound, on code `moon check` accepts.
///
/// So the match reader tracks braces as well as brackets, and this row is what
/// says it does.
test "0502: a struct pattern's names are all carried" {
  let r = @parser.parse(
    "fn f(e : Int) -> Int {\n  match e {\n    Point { x, y } => x + y\n    _ => 0\n  }\n}\n",
  )
  assert_eq(r.first_error, 0)
  let arms = first_match_arms(r.tree)
  assert_eq(arms.length(), 2)
  assert_true(arms[0].bindings.contains("x"))
  assert_true(arms[0].bindings.contains("y"))
}

///|
/// A TUPLE PATTERN, which is the shape the corpus writes most: `(a, b) => ...`.
/// The commas inside the parens must not be mistaken for the comma that
/// SEPARATES the arms -- and the reader stops at the `=>`, so it never sees the
/// separator at all.
test "0502: a tuple pattern's names are carried and the arms stay separate" {
  let r = @parser.parse(
    "fn f(e : Int) -> Int {\n  match e {\n    (a, b) => a + b\n    _ => 0\n  }\n}\n",
  )
  assert_eq(r.first_error, 0)
  let arms = first_match_arms(r.tree)
  assert_eq(arms.length(), 2)
  assert_true(arms[0].bindings.contains("a"))
  assert_true(arms[0].bindings.contains("b"))
}

///|
/// AN ARM BODY IS A STATEMENT LIST, in both of the shapes it can take. A block
/// body (`=> { ... }`) is a list of statements, and a single-statement body
/// (`=> 0`) is a list of one. A reader that modelled only the block form would
/// have modelled the rare one -- the corpus census for `catch` says the
/// single-statement form is the COMMON one, 45 of 54 handler sites in moui and
/// 273 of 323 in proton.
test "0502: an arm body is a statement list, in either shape" {
  let blockForm = @parser.parse(
    "fn f(e : Int) -> Int {\n  match e {\n    1 => { let q = 1; q }\n    _ => 0\n  }\n}\n",
  )
  assert_eq(blockForm.first_error, 0)
  let a1 = first_match_arms(blockForm.tree)
  assert_eq(a1.length(), 2)
  assert_eq(a1[0].body.length(), 2)
  assert_eq(a1[1].body.length(), 1)

  let singleForm = @parser.parse(
    "fn f(e : Int) -> Int {\n  match e {\n    1 => 2\n    _ => 0\n  }\n}\n",
  )
  assert_eq(singleForm.first_error, 0)
  let a2 = first_match_arms(singleForm.tree)
  assert_eq(a2.length(), 2)
  assert_eq(a2[0].body.length(), 1)
}

///|
/// A NESTED MATCH inside an arm body, which is the shape the corpus is full
/// of -- `let x = match candidate { ... }` followed by another `match` whose
/// arm reads `x`. A reader that stopped at the first `=>` would have read the
/// inner match's arms as part of the outer arm's body, and the whole file
/// after it would have been misparsed.
test "0502: a match nested in an arm body is parsed as its own match" {
  let r = @parser.parse(
    "fn f(e : Int) -> Int {\n  match e {\n    1 => match e {\n      2 => 3\n      _ => 4\n    }\n    _ => 0\n  }\n}\n",
  )
  assert_eq(r.first_error, 0)
  assert_eq(r.reports.length(), 0)
  let arms = first_match_arms(r.tree)
  assert_eq(arms.length(), 2)
  // The OUTER arm's body is the inner match -- one statement, and it is a
  // match, not a number.
  assert_eq(arms[0].body.length(), 1)
}

///|
/// AN `as` BINDING, which is the spelling MoonBit uses for "bind this whole
/// pattern to a name": `Some(v) as whole => ...`. The reader is a superset, so
/// `whole` is carried among the bindings -- and `as` is carried too, which is
/// harmless: a name that binds when it should not costs silence.
test "0502: an as-binding's name is carried" {
  let r = @parser.parse(
    "fn f(e : Int) -> Int {\n  match e {\n    Some(v) as whole => whole\n    _ => 0\n  }\n}\n",
  )
  assert_eq(r.first_error, 0)
  let arms = first_match_arms(r.tree)
  assert_eq(arms.length(), 2)
  assert_true(arms[0].bindings.contains("whole"))
}
