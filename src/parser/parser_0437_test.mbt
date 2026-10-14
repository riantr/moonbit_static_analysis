///|
/// `(expr : Type)` -- an ascription inside parentheses.
///
/// The re-rank put this first at 6 blocked moui files, and the backlog had it
/// THIRD at three. It was third because the scanner's reason string for these
/// files is `expected ')'`, which reads like a tuple or a function type; joining
/// each reason back to its blocking source line (`_verify/blockers.ps1`) shows
/// all six are the same shape --
///
///   `(code - ('0' : Int)).to_uint64()`            3 files
///   `(ToJson::to_json(metadata) : Json)`          1
///   `(ToJson::to_json(evidence) : Json)`           1
///   `(@views.empty() : @core.View[Unit])`          1
///
/// The grouping branch of `parse_atom`'s `TLParen` arm parsed the inner
/// expression and then demanded `)`. Settled one form per package with a broken
/// canary beside each (`_verify/probe_sweep_0434.ps1`, canary firing):
///
///   `('0' : Int)`          MOON-OK   <- the only legal form
///   `let y = 1 : Int`      MOON-BAD  (no parentheses: rejected)
///   `(1 : Int, 2)`         MOON-BAD  (ascription on a tuple element: rejected)
///
/// So there is deliberately no bare-form branch and no tuple-element branch.
/// Those are not omissions; both are syntax the toolchain refuses.
///

///|
/// WHAT THESE TESTS ASSERT, AND WHY IT IS THE TREE. The tempting guard is
/// `assert_eq(count_family(r, "ArgTypeMismatch"), 0)` on a source whose ascription
/// type disagrees with its value. That is VACUOUS here: `@parser.parse` returns
/// `ParseResult`, whose reports carry parse findings and subset exclusions. The
/// three lenses run in `@pipeline`, so no `Ty`-derived family can ever appear in
/// a `ParseResult` no matter what the tree says. The control that catches this --
/// the same source with the ascription REMOVED, which should report one -- comes
/// back `0`, and that is how the first draft of these tests was found to be
/// asserting nothing.
///
/// The observable is the tree instead: a grouping paren yields `e` itself, so an
/// ascription must leave the SAME node it would have produced without the
/// annotation. Anything else -- a wrapper node, a swallowed operand, a lost tail
/// -- is visible there. `EInt`/`EBin` are asserted directly for that reason.
///

///|
/// A third fact the fixtures are written around, found the same way as in 0436:
/// an `enum` declaration is NOT a member of `Module.body`, and it emits its own
/// subset-exclusion notice. Neither test that needs a type declares one.

///|
/// THE SHAPE, verbatim from `host_transport.mbt:63`. The ascription is nested
/// inside a subtraction inside a grouping paren, and a method chain hangs off the
/// result -- so this one fixture exercises the paren, the nesting, AND the tail.
test "0437: an ascription inside parentheses is read" {
  let r = @parser.parse(
    "fn f(code : Int) -> UInt64 {\n  (code - ('0' : Int)).to_uint64()\n}\n",
  )
  assert_eq(r.first_error, 0)
}

///|
/// The decisive assertion: the ascription leaves the tree it would have produced
/// WITHOUT it. A grouping paren yields its inner expression itself, so
/// `(code - ('0' : Int))` must be exactly `EBin(Sub, code, '0')` -- no wrapper
/// node, no annotation carried along. A fix that silently wrapped the operand in
/// a new node would satisfy `first_error == 0` and fail here.

///|
/// Describes the tree of `(code - '0')`: a subtraction whose left operand is the
/// name `code` and whose right operand is still a literal. Shared by the ascribed
/// and the bare fixture so the two assertions cannot drift apart, which is the
/// whole point of the comparison.
///
/// RETURNS A MESSAGE rather than asserting, and that is not style. `assert_true`
/// and `assert_eq` are error-raising, so a plain helper that calls them needs an
/// error type in its own signature and cannot be called from a `test` body at
/// all. The helper returns "" for success and the reason otherwise; the test
/// body raises.
///
/// A function body's trailing expression is `STail`, not `SExpr` and not
/// `SReturn`. Found by the assertion failing with "not an STail"
/// after two wrong guesses in a row; the three facts about a fixture that are
/// worth knowing are: an `enum` is not in `Module.body`, a tail is `STail`, and
/// `with` is a keyword you cannot use as a local name.
fn describe_sub_of_code(v : @ast.Expr) -> String {
  match v.kind {
    @ast.EBin(op, l, r) =>
      match op {
        @ast.OpSub =>
          match l.kind {
            @ast.EName(n) =>
              if n == "code" {
                // The right operand must STILL BE THE LITERAL `'0'`. An
                // ascription that wrapped the operand in a new node would leave
                // `first_error == 0` and fail exactly here.
                //
                // It is an `EStr`, not an `EInt`, and that is correct: `'0'` is a
                // Char and the lexer produces character literals as string
                // tokens. The first draft asserted `EInt` and failed with
                // "right operand is not the literal" -- the assertion was wrong
                // about MoonBit, not the parser about the ascription.
                match r.kind {
                  @ast.EStr(s, _) =>
                    if s == "0" {
                      ""
                    } else {
                      "the literal is not '0'"
                    }
                  _ => "the right operand is not a literal"
                }
              } else {
                "left operand is not 'code'"
              }
            _ => "left operand is not a name"
          }
        _ => "the operator is not subtraction"
      }
    _ => "the expression is not a binary operation"
  }
}

///|
/// The decisive assertion: the ascription leaves the tree it would have produced
/// WITHOUT it. A grouping paren yields its inner expression itself, so
/// `(code - ('0' : Int))` must be exactly `EBin(Sub, code, '0')` -- no wrapper
/// node, no annotation carried along. A fix that silently wrapped the operand in
/// a new node would satisfy `first_error == 0` and fail here.
test "0437: an ascription leaves the same tree the bare expression makes" {
  let ascribed = @parser.parse(
    "fn f(code : Int) -> Int {\n  (code - ('0' : Int))\n}\n",
  )
  let bare = @parser.parse("fn f(code : Int) -> Int {\n  code - '0'\n}\n")
  assert_eq(ascribed.first_error, 0)
  assert_eq(bare.first_error, 0)
  let mut said = ""
  match ascribed.tree.body[0].kind {
    @ast.SFunc(_, _, _, body, _) =>
      match body[0].kind {
        @ast.STail(v) => said = describe_sub_of_code(v)
        _ => said = "the ascribed tail is not an STail"
      }
    _ => said = "no SFunc at the top level"
  }
  if said != "" {
    fail("ascribed: " + said)
  }
  // THE CONTROL. Identical source with the `: Int` removed must produce the
  // identical statement -- that is what makes the assertion above a statement
  // about the ascription rather than a restatement of the fixture.
  said = ""
  match bare.tree.body[0].kind {
    @ast.SFunc(_, _, _, body, _) =>
      match body[0].kind {
        @ast.STail(v) => said = describe_sub_of_code(v)
        _ => said = "the bare tail is not an STail"
      }
    _ => said = "no SFunc at the top level"
  }
  if said != "" {
    fail("bare: " + said)
  }
}

///|
/// A QUALIFIED type ascription on a CALL result, then a method chain on it --
/// `document_metadata.mbt:25`. The interesting part is the tail: `.stringify()`
/// must still be in the tree, which is the thing a fix that stopped early at the
/// `:` would cost.
test "0437: a qualified-type ascription keeps the call and the chain after it" {
  let r = @parser.parse(
    "fn g(x : Int) -> Int {\n  x\n}\nfn f() -> Int {\n  let n = (g(1) : @core.View[Unit])\n  ignore(n)\n  7\n}\n",
  )
  assert_eq(r.first_error, 0)
  // `body[0]` is `fn g`, so `fn f` is `body[1]`. The `ignore` and the trailing
  // `7` are the tail that has to survive.
  match r.tree.body[1].kind {
    @ast.SFunc(_, _, _, body, _) => assert_eq(body.length(), 3)
    _ => assert_true(false)
  }
}

///|
/// CONTROL, and the one that decides whether the new branch is narrow enough. A
/// plain grouping paren `(e)` has no `:` and must be completely untouched: same
/// tree, and no notice invented for a construct that never had one.
///
/// Compared rather than counted, because this source emits notices of its own
/// and a bare `reports.length()` would be asserting whichever those happen to be.
test "0437 control: a grouping paren without an ascription is unchanged" {
  let plain = @parser.parse("fn f(code : Int) -> Int {\n  (code - '0')\n}\n")
  let ascribed = @parser.parse(
    "fn f(code : Int) -> Int {\n  (code - ('0' : Int))\n}\n",
  )
  assert_eq(plain.first_error, 0)
  assert_eq(ascribed.first_error, 0)
  assert_eq(plain.reports.length(), ascribed.reports.length())
  assert_eq(plain.skips.length(), ascribed.skips.length())
}

///|
/// CONTROL: a `:` that is NOT an ascription, in the two places it legally
/// appears, must be unaffected. These are the constructs the new branch could
/// plausibly have disturbed -- a struct-literal field and a `let` annotation --
/// and both are inside or beside the paren grammar the edit touched.
///
/// The source is deliberately one statement per LINE: two struct fields on one
/// line collapse to a single finding (the merge key is `(merge_group, line)`),
/// which would make an expected-2 assertion count 1.
test "0437 control: a struct field and a let annotation are unaffected" {
  let r = @parser.parse(
    "struct P {\n  x : Int\n  y : Int\n}\nfn f() -> Int {\n  let p : P = { x: 1, y: 2 }\n  p.x + p.y\n}\n",
  )
  assert_eq(r.first_error, 0)
}

///|
/// CONTROL for the SCOPE, both directions, and they are the reason the two
/// branches were left out rather than written defensively: `moon check` rejects
/// both forms, so a frontend that ACCEPTED them would be reading things the
/// toolchain does not.
///
///   `let y = 1 : Int`   MOON-BAD
///   `(1 : Int, 2)`      MOON-BAD
///
/// Asserting they still fail is what proves the branch did not widen by accident
/// while fixing the third form.
test "0437 control: the two forms the toolchain rejects are still rejected" {
  let bare = @parser.parse("fn f() -> Int {\n  let y = 1 : Int\n  y\n}\n")
  assert_true(bare.first_error != 0)
  let tuple = @parser.parse("fn f() -> Int {\n  let p = (1 : Int, 2)\n  1\n}\n")
  assert_true(tuple.first_error != 0)
}

///|
/// The CANARY for this fix, in the only sense the word can be used here: a `)`
/// with nothing opening it. If the new branch ever accepted a missing `(` too,
/// this is the source that would notice, and it is the one input where "just
/// consume a `:` and carry on" would do real damage.
test "0437: a stray closing paren is still a parse error" {
  let r = @parser.parse(
    "fn f() -> Int {\n  let y = 1 : Int\n  y\n}\nfn g() -> Int {\n  )\n  1\n}\n",
  )
  assert_true(r.first_error != 0)
}
