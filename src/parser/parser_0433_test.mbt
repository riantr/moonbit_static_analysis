///|
/// A `match` whose SUBJECT starts on the NEXT LINE.
///
/// Settled with the toolchain: `_verify/grammar_probe.ps1` cases
/// `match_subject_next_line_stmt` and `match_subject_next_line_let` are
/// MOON-OK / SELF-OK, beside `match_one_line_control`. The companion case
/// `match_brace_on_its_own_line` records the spelling the toolchain REJECTS,
/// because the parser comment asserts it and an assertion in prose that no case
/// exercises is the defect the 0.4.30 doc audit found.
///
/// wzzc-dev/moui 0.1.12 writes the next-line form throughout --
/// `views/form/form_field.mbt:42`, `runtime/scroll_to_key.mbt:30`,
/// `runtime/runtime_events.mbt:358` -- and it was the largest single blocker
/// left at 0.4.30: 13 files, `unexpected token `>``, the arrow of the first
/// arm.
///
/// These are PARSE-level claims only. "The subject's reads are still visible"
/// is a downstream question and lives in `src/pipeline/pipeline_0433_test.mbt`,
/// where the walker can answer it; `pipeline` imports `parser`, so a parser
/// test cannot reach the walker at all.
///
/// Note what is NOT asserted here: `reports.length() == 0`. The arms are
/// outside the subset, so the standard notice is present, and a zero-report
/// assertion would be asserting a silent swallow -- it would pass on a parser
/// that consumed the whole match and said nothing.
test "0433: a match subject on the next line parses and still says so" {
  let r = @parser.parse(
    "fn sub(x : Int) -> Int { x }\nfn caller(c : Int) -> Int {\n  match\n    sub(c) {\n    1 => 2\n    _ => 3\n  }\n}\n",
  )
  assert_eq(r.first_error, 0)
  assert_eq(r.reports.length(), 1)
  assert_eq(
    r.reports[0].message,
    "match expression is outside the analyzed subset; it was read but not analysed",
  )
}

///|
/// CONTROL -- the same `match` on one line. If this went red, the two-line
/// failures would have been about something else entirely.
test "0433 control: a match subject on the same line is still read" {
  let r = @parser.parse(
    "fn sub(x : Int) -> Int { x }\nfn caller(c : Int) -> Int {\n  match sub(c) {\n    1 => 2\n    _ => 3\n  }\n}\n",
  )
  assert_eq(r.first_error, 0)
  assert_eq(r.reports.length(), 1)
  assert_eq(
    r.reports[0].message,
    "match expression is outside the analyzed subset; it was read but not analysed",
  )
}

///|
/// The same form in `let` position, which is where moui also writes it. The
/// fix is one `skip_seps` in `parse_atom`, so BOTH positions share it -- this
/// test is what makes the shared claim checkable rather than asserted.
test "0433: a match subject on the next line parses in let position too" {
  let r = @parser.parse(
    "fn sub(x : Int) -> Int { x }\nfn caller(c : Int) -> Int {\n  let v = match\n    sub(c) {\n    1 => 2\n    _ => 3\n  }\n  v\n}\n",
  )
  assert_eq(r.first_error, 0)
  assert_eq(r.reports.length(), 1)
}

///|
/// `defer { ... }` -- a statement whose body runs at scope exit.
///
/// 130 of the 1950 `defer` lines in the six corpora are this shape; proton
/// 0.3.4 `command/command.mbt:145` is `defer { scoped.registration_closed =
/// true }`.
///
/// `tree.body[1]`, not `[0]`: every source here declares its helper first and
/// the function under test second. Indexing `[0]` silently asserts on the
/// helper -- a one-statement function that passes or fails for reasons that have
/// nothing to do with `defer`. Four of this file's tests were wrong that way
/// before the index was corrected.
test "0433: defer followed by a block is one statement" {
  let r = @parser.parse(
    "fn g() -> Unit { () }\nfn f() -> Unit {\n  defer {\n    g()\n  }\n  g()\n}\n",
  )
  assert_eq(r.first_error, 0)
  assert_eq(r.reports.length(), 0)
  // Two statements -- the `defer` and the trailing call -- not three.
  match r.tree.body[1].kind {
    @ast.SFunc(_, _, _, body, _) => assert_eq(body.length(), 2)
    _ => assert_true(false)
  }
}

///|
/// `defer <expr>` -- 1534 of the 1950 lines, so the shape the arm MOSTLY has to
/// get right. proton 0.3.4 `facade_cookie.mbt:57` is `defer self.remove(
/// request_id)`.
///
/// The assertion is that the deferred CALL is in the tree with its argument
/// intact. A body that was read and dropped, or read with its argument
/// consumed, fails here -- and `first_error == 0` alone would pass on both,
/// which is why this test reaches into the AST at all.
test "0433: defer followed by an expression reads the whole call" {
  let r = @parser.parse(
    "fn sink(id : Int) -> Unit { ignore(id) }\nfn f(request_id : Int) -> Unit {\n  defer sink(request_id)\n  sink(0)\n}\n",
  )
  assert_eq(r.first_error, 0)
  assert_eq(r.reports.length(), 0)
  match r.tree.body[1].kind {
    @ast.SFunc(_, _, _, body, _) => {
      assert_eq(body.length(), 2)
      match body[0].kind {
        @ast.STail(e) =>
          match e.kind {
            @ast.ECall(name, args, _) => {
              assert_eq(name, "sink")
              assert_eq(args.length(), 1)
              match args[0].kind {
                @ast.EName(n) => assert_eq(n, "request_id")
                _ => assert_true(false)
              }
            }
            _ => assert_true(false)
          }
        _ => assert_true(false)
      }
    }
    _ => assert_true(false)
  }
}

///|
/// A `defer` block that ran on into the next statement would fuse them, so the
/// two arms of the fix are not separable by accident. This is the cost of the
/// block form: it consumes a brace-delimited body, and the cursor must land on
/// the statement AFTER it.
test "0433: a defer block does not swallow the statement after it" {
  let r = @parser.parse(
    "fn g(x : Int) -> Unit { ignore(x) }\nfn f(a : Int) -> Unit {\n  defer {\n    g(a)\n  }\n  g(a + 1)\n}\n",
  )
  assert_eq(r.first_error, 0)
  assert_eq(r.reports.length(), 0)
  match r.tree.body[1].kind {
    @ast.SFunc(_, _, _, body, _) => assert_eq(body.length(), 2)
    _ => assert_true(false)
  }
}

///|
/// `defer (expr catch { _ => () })` -- 18 of the 1950 lines, proton 0.3.4
/// `facade_bridge.mbt:584`. The `catch` block is consumed by the postfix `catch`
/// arm via `skip_braces`, so the outer parens must still close for the rest of
/// the statement to land. Included because an arm that handled the bare call
/// would still mis-handle this one, and the probe case
/// `defer_expr_catch_stmt` settles it as MOON-OK.
test "0433: a parenthesised defer with a trailing catch parses" {
  let r = @parser.parse(
    "fn cancel() -> Unit raise E { raise Boom(1) }\nfn f() -> Unit raise E {\n  defer (cancel() catch { _ => () })\n  cancel() catch { _ => () }\n}\n",
  )
  assert_eq(r.first_error, 0)
  match r.tree.body[1].kind {
    @ast.SFunc(_, _, _, body, _) => assert_eq(body.length(), 2)
    _ => assert_true(false)
  }
}

///|
/// A KNOWN LIMITATION, pinned so it cannot be rediscovered as a new bug.
///
///     defer {
///       return   // legal in MoonBit: it returns at scope exit
///     }
///
/// The body is walked as an ordinary statement list, so a `return` inside a
/// `defer` reads as a return from the ENCLOSING function, where it would
/// actually run later at scope exit. `SBlock` was already the node the bare
/// `{ ... }` statement produced and already flowed through walk / types / infer
/// / interp, which is why no downstream code needed teaching -- and that same
/// reuse is exactly why the flattening exists.
///
/// Pinned as DOCUMENTED, not fixed: no lens has a use for the difference yet,
/// and a separate `SDefer` node would have to be taught to all four. If a lens
/// ever needs to answer "does this return escape the defer?", this is where it
/// lands.
test "0433 KNOWN LIMIT: a return inside a defer reads as returning from the function" {
  let r = @parser.parse(
    "fn g() -> Unit { () }\nfn f() -> Int {\n  defer {\n    return 1\n  }\n  2\n}\n",
  )
  // Parses clean. The claim above is about the SEMANTICS, not the parse: the
  // `return` is an ordinary statement inside an SBlock, so the value lens sees
  // a function whose `defer` returns 1 and whose tail is 2 -- with no way to
  // tell that the 1 arrives later than the 2.
  assert_eq(r.first_error, 0)
  assert_eq(r.reports.length(), 0)
}
