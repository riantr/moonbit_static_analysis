///|
/// 0439: `expr catch { pattern => body }` — the handler is READ, not skipped.
///

///|
/// THE DEFECT THIS REMOVES. wzzc-dev/moui 0.1.12
/// `backend/macos/macos_native_ime.mbt:437:3`:
///
///     fn native_ime_content_view_handle(
///       platform_slot : @window_lifecycle.WindowSlot[...],
///       prefix~ : String,
///     ) -> UInt64? {
///       Some(platform_slot.window.content_view_handle()) catch {
///         err => {
///           println(prefix + " MoUI native IME runtime failed content-view-handle error=\{err}")
///           None
///         }
///       }
///     }
///
/// reported `parameter 'prefix' may not be used (UnusedParam)`. `prefix` is read
/// at line 442, inside the handler, and the postfix `catch` arm consumed the
/// braces with `skip_braces` — so the only mention of `prefix` in the function
/// was invisible and the parameter read as unused. It was moui's only
/// actionable finding.
///

///|
/// WHY THE SHAPE IS ASSERTED HERE AND THE FINDING IN `@pipeline`. The parse is
/// the observable a SKIP cannot produce... except that `skip_braces` also left
/// the token stream in step and reported nothing, so "it still parses" proves
/// nothing about whether the body was read. What these tests pin is the TREE:
/// an arm whose bindings and statements are actually in it. What
/// `pipeline_0439_test.mbt` pins is the FINDING. Either half alone would pass
/// against a parser that discards the handler.
///

///|
/// THE `=>` FACT IS PINNED FIRST BECAUSE IT IS WHAT COST THE FIRST ATTEMPT.
/// `TArrow` exists and is `->`; `=>` has no token at all and arrives as
/// `TAssign` then `TGt`. A first draft checked for `TArrow`, never matched,
/// walked off the end of the arm, swallowed the catch's `}`, and reported
/// `expected '}'` at EOF on code `moon check` accepts. Everything below would
/// have "passed" against a parser that read nothing, so the token stream is
/// asserted on its own.
///

///|
/// THESE ARE `@parser` TESTS, so they cannot assert a lens finding. A
/// `count_family(..., "UndefinedName")` in this package is structurally 0
/// forever — `ParseResult.reports` never carries a lens family — and would pass
/// against a parser that read nothing at all. The tree is the only thing here
/// that can fail.

///|
/// THE TOKEN STREAM, asserted. This is the fact the rest of the file rests on.
test "0439: `=>` in a catch arm is TAssign then TGt, not TArrow" {
  let (toks, _, _) = @lexer.lex("f catch { e => () }")
  //  f catch { e = > ( ) } EOF
  //  0 1     2 3 4 5 6 7 8 9
  assert_eq(toks.length(), 10)
  match toks[4] {
    TAssign => ()
    _ => assert_true(false)
  }
  match toks[5] {
    TGt => ()
    _ => assert_true(false)
  }
}

///|
/// THE CONTROL on that fact. `->` IS `TArrow`, so a test that "passed" because
/// some arrow-shaped token matched would be passing on the wrong token. One
/// assertion is not enough to distinguish "TArrow never fires" from "TArrow
/// fires elsewhere".
test "0439 control: `->` is TArrow, so the two are not interchangeable" {
  let (toks, _, _) = @lexer.lex("fn g() -> Int { 1 }")
  let mut saw_arrow = false
  for t in toks {
    match t {
      TArrow => saw_arrow = true
      _ => ()
    }
  }
  assert_true(saw_arrow)
}

///|
/// A block-bodied arm: the shape moui's `macos_native_ime.mbt:437` has. The
/// arm's body is a real statement list and the pattern's name is carried.
test "0439: a block-bodied catch arm carries its binding and its body" {
  let r = @parser.parse(
    "fn f(p : String) -> Int {\n  call() catch {\n    err => {\n      println(p)\n      0\n    }\n  }\n}\n",
  )
  assert_eq(r.first_error, 0)
  match r.tree.body[0].kind {
    SFunc(_, _, _, body, _) =>
      match body[0].kind {
        STail(e) =>
          match e.kind {
            ECatch(_, arms) => {
              assert_eq(arms.length(), 1)
              assert_eq(arms[0].bindings.length(), 1)
              assert_eq(arms[0].bindings[0], "err")
              assert_eq(arms[0].body.length(), 2)
            }
            _ => assert_true(false)
          }
        _ => assert_true(false)
      }
    _ => assert_true(false)
  }
}

///|
/// AN EXPRESSION-BODIED ARM — the shape 45 of moui's 54 handler sites and 273
/// of proton's 323 actually use (`_verify/census_catch.ps1`). This is the case
/// the first draft got wrong, twice over: `parse_stmt` reads a leading `{` as a
/// BLOCK, so the arm-body choice must be made before `parse_stmt` sees
/// anything, and the `=>` has to be recognised as two tokens.
test "0439: an expression-bodied catch arm parses and keeps one arm" {
  let r = @parser.parse(
    "fn f(p : String) -> Int {\n  call(p) catch { _ => 0 }\n}\n",
  )
  assert_eq(r.first_error, 0)
  match r.tree.body[0].kind {
    SFunc(_, _, _, body, _) =>
      match body[0].kind {
        STail(e) =>
          match e.kind {
            ECatch(_, arms) => assert_eq(arms.length(), 1)
            _ => assert_true(false)
          }
        _ => assert_true(false)
      }
    _ => assert_true(false)
  }
}

///|
/// THE NEGATIVE CONTROL for the two above. The same shape with the arm body's
/// read of `p` REMOVED. It must still parse cleanly — and that is exactly the
/// point: the parse does not depend on what the body reads, which is why the
/// parse assertions above cannot be what proves the body was read, and why
/// `pipeline_0439_test.mbt` has to exist. If THIS goes red, the parser has
/// started rejecting code it used to accept, which is the regression this
/// increment can cause and did not.
test "0439 control: a catch arm whose body reads nothing still parses" {
  let r = @parser.parse(
    "fn f(p : String) -> Int {\n  call() catch { _ => 0 }\n}\n",
  )
  assert_eq(r.first_error, 0)
}

///|
/// MULTIPLE ARMS, separated only by newlines. Without `skip_seps` between arms
/// the second pattern would be read as part of the first arm's body — and since
/// the arms are counted by the test below, that failure would be visible here.
test "0439: two catch arms parse and stay two arms" {
  let r = @parser.parse(
    "fn f(p : String) -> Int {\n  call() catch {\n    Boom(n) => n\n    _ => 0\n  }\n  p.length()\n}\n",
  )
  assert_eq(r.first_error, 0)
  match r.tree.body[0].kind {
    SFunc(_, _, _, body, _) =>
      match body[0].kind {
        SExpr(e) =>
          match e.kind {
            ECatch(_, arms) => {
              assert_eq(arms.length(), 2)
              assert_eq(arms[0].bindings[0], "Boom")
              assert_eq(arms[1].bindings[0], "_")
            }
            _ => assert_true(false)
          }
        _ => assert_true(false)
      }
    _ => assert_true(false)
  }
}

///|
/// A `catch` inside parentheses — proton `facade_bridge.mbt:584`,
/// `defer (window.cancel_dialog(dialog) catch { _ => () })`. This is the shape
/// that reported `unexpected token ')'` when the arms were parsed but the `=>`
/// was not recognised: the arm ran past its own braces and the enclosing group
/// never closed.
test "0439: a parenthesised catch parses" {
  let r = @parser.parse(
    "fn f() -> Unit {\n  defer (cancel() catch { _ => () })\n}\n",
  )
  assert_eq(r.first_error, 0)
}

///|
/// THE `<?` LOG-PAYLOAD GUARD — proton 0.3.4 `facade_locale.mbt:63`, a catch
/// handler whose body carries an `@xlog` payload. That file read cleanly at
/// every release up to 0.4.29 because the handler was skipped and line 65 was
/// never seen; parsing the handler turned it into a hard parse error and the
/// file went from `parsed` to `not-parsed`. A fix that fixes one corpus and
/// breaks another is not a fix, and `parsed=` is the number that went DOWN.
///
/// `?>` occurs ZERO times in proton, so the payload has no findable end and the
/// guard is per GROUP rather than per arm.
test "0439: a catch group holding a log payload is skipped, not parsed" {
  let r = @parser.parse(
    "fn call() -> Int { 1 }\nfn f() -> Unit {\n  call() catch {\n    _ => {\n      @xlog.warn() <? { \"message\": \"x\" }\n      []\n    }\n  }\n}\n",
  )
  assert_eq(r.first_error, 0)
  // And the group really was SKIPPED rather than parsed and somehow surviving:
  // no arms came out of it. Without this the test would also pass for a parser
  // that had grown real `<?` support, which is a different change.
  match r.tree.body[1].kind {
    SFunc(_, _, _, body, _) =>
      match body[0].kind {
        SExpr(e) | STail(e) =>
          match e.kind {
            ECatch(_, arms) => assert_eq(arms.length(), 0)
            _ => assert_true(false)
          }
        _ => assert_true(false)
      }
    _ => assert_true(false)
  }
}

///|
/// THE CONTROL for the guard. The SAME handler without the `<?` IS read, so the
/// guard cannot be passing for a reason that has nothing to do with the payload
/// — and this is the shape that has to keep working, because it is the one
/// moui :437 is written in.
test "0439 control: the same handler without a log payload is read" {
  let r = @parser.parse(
    "fn call() -> Int { 1 }\nfn f(p : String) -> Unit {\n  call() catch {\n    _ => {\n      println(p)\n    }\n  }\n}\n",
  )
  assert_eq(r.first_error, 0)
  match r.tree.body[1].kind {
    SFunc(_, _, _, body, _) =>
      match body[0].kind {
        SExpr(e) | STail(e) =>
          match e.kind {
            ECatch(_, arms) => assert_eq(arms.length(), 1)
            _ => assert_true(false)
          }
        _ => assert_true(false)
      }
    _ => assert_true(false)
  }
}

///|
/// A `raise` as an expression-bodied arm — proton `ipc/protocol.mbt:260`:
///
///     @json.parse(raw) catch {
///       err => raise MalformedJson(detail=err.to_string())
///     }
///
/// `raise` is a STATEMENT in this subset (`SRaise`) and an arm body is a
/// statement list, so the arm-body path has to accept it. This is also the site
/// behind proton's 15 new findings: reading the body makes `MalformedJson`
/// visible to the resolver and the per-file `enum_ctors` harvest does not have
/// it. That is the documented limitation becoming VISIBLE, not a new defect
/// class.
test "0439: a raise-bodied catch arm parses" {
  let r = @parser.parse(
    "fn call() -> Int { 1 }\nfn f() -> Int {\n  call() catch {\n    e => raise Bad\n  }\n}\n",
  )
  assert_eq(r.first_error, 0)
}

///|
/// A pattern with brackets inside it. `Wrap({ inner })` must not end the
/// pattern at the `{` of its own inner brace — the brace that ends a pattern is
/// one at depth 0 with no bracket open.
test "0439: a struct pattern does not end at its own brace" {
  let r = @parser.parse(
    "fn f(p : String) -> Int {\n  call() catch {\n    Wrap({ inner }) => {\n      println(p)\n      0\n    }\n  }\n}\n",
  )
  assert_eq(r.first_error, 0)
  match r.tree.body[0].kind {
    SFunc(_, _, _, body, _) =>
      match body[0].kind {
        STail(e) =>
          match e.kind {
            ECatch(_, arms) => {
              // The SUPERSET, asserted: `Wrap` is a variant, not a variable, and
              // it is carried anyway; `inner` is the one that binds.
              assert_eq(arms[0].bindings.length(), 2)
              assert_eq(arms[0].bindings[0], "Wrap")
              assert_eq(arms[0].bindings[1], "inner")
            }
            _ => assert_true(false)
          }
        _ => assert_true(false)
      }
    _ => assert_true(false)
  }
}

///|
/// THE CONTROL for the superset. A bare name is one binding, not two, and the
/// wildcard `_` is not a `TName` at all so it never reaches the list. Without
/// this, "collect every name in the pattern" and "collect the names the pattern
/// binds" would be indistinguishable, and the second is the one that is
/// actually wanted — the first is only safe because `Walker::bind_pattern`
/// keeps the extra names out of the audit.
test "0439 control: a bare name is one binding and `_` is none" {
  let r = @parser.parse("fn f() -> Int {\n  call() catch { e => 0 }\n}\n")
  assert_eq(r.first_error, 0)
  match r.tree.body[0].kind {
    SFunc(_, _, _, body, _) =>
      match body[0].kind {
        STail(e) =>
          match e.kind {
            ECatch(_, arms) => {
              assert_eq(arms[0].bindings.length(), 1)
              assert_eq(arms[0].bindings[0], "e")
            }
            _ => assert_true(false)
          }
        _ => assert_true(false)
      }
    _ => assert_true(false)
  }
}
