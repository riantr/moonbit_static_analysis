//| Tests for 0494 -- the four shapes that stopped the async corpus at 415/419.
//
//| MEASURED, the four unreadable files and the reader that stopped each:
//!
//!   async 0.22.4 src/http/request.mbt:59      "expected ')'"
//!       `re"^" + (re".*" as host) + ...` and the `=~` that consumes it. TWO
//!       constructs, not one: the REGEX LITERAL and the MATCH OPERATOR.
//!
//!   async 0.22.4 src/http/utils.mbt:23        "expected '{'"
//!       `for x = value, i = len - 1; i >= 0; x = x / base, i = i - 1 { .. }`
//!       -- the UPDATE clause is a LIST of assignments. The INITIALIZER could
//!       already be a list (settled at 0472); the update could not.
//!
//!   async 0.22.4 src/fs/watch_kqueue.mbt:240  "expected binding name"
//!       `let { identity, .. } = self.watched[fd]` -- the SHORTHAND struct
//!       pattern in a `let` position. The braced pattern reader existed (0485)
//!       but read the KEYED spelling `{ "cmd": [cmd], .. }`.
//!
//!   async 0.22.4 src/fs/watch_windows.mbt:320 "unexpected token `.`"
//!       `for i in path.length()>..0 { .. break path[:i] .. } nobreak { "" }`
//!       -- the DESCENDING range and a `break` that CARRIES A VALUE.
//
//| Settled before implementing, not after -- `_verify/settle_0494_parse_backlog.ps1`,
//! 22 rows / 10 controls that REJECT. TWO OF MY OWN EXPECTATIONS WERE WRONG and the
//| toolchain was right in both: `break path[:i]` is only legal when the path is a
//| StringView (the corpus's `path` is one), and `re"[0-9]+"` is a perfectly good
//| regex rather than the broken canary I had written it as.
//
//| WHY EVERY ROW HERE ASSERTS THE NODE AND NOT `first_error`: "it parses" is
//| satisfied by a reader that swallowed the construct whole. The 0485 file says
//| the same thing about its own rows, and the shape assertion is what sees the
//| difference between a reader that binds and a reader that consumes.

///|
/// THE REGEX MATCH, `host =~ re"^a"`. The row asserts the OPERATOR and the
/// LITERAL: a reader that read `=~` as an assignment, or the literal as a
/// string, would satisfy "it parses".
test "0494: the regex match is an operator and the literal is a regex" {
  let r = @parser.parse(
    "fn f(host : String) -> Bool {\n  if host =~ re\"^a\" {\n    true\n  } else {\n    false\n  }\n}\n",
  )
  assert_eq(r.first_error, 0)
  match r.tree.body[0].kind {
    @ast.SFunc(_, _, _, body, _) =>
      match body[0].kind {
        @ast.SIf(cond, _, _, _) =>
          match cond.kind {
            @ast.EBin(@ast.OpMatch, _, rhs) =>
              match rhs.kind {
                @ast.ERegex(_) => ()
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
/// THE CAPTURE, `re"..." as name`. The name is BOUND, and the row says so by
/// looking at the node: a reader that consumed the name and dropped it would
/// satisfy "it parses" -- and that is exactly what it did before this
/// increment, which is how `port_str` came to be reported `undefined name` at
/// its use ten lines later.
test "0494: a regex capture binds the name it names" {
  let r = @parser.parse(
    "fn f(s : String) -> Bool {\n  if s =~ (re\"^a\" as cap) {\n    true\n  } else {\n    false\n  }\n}\n",
  )
  assert_eq(r.first_error, 0)
  match r.tree.body[0].kind {
    @ast.SFunc(_, _, _, body, _) =>
      match body[0].kind {
        @ast.SIf(cond, _, _, _) =>
          match cond.kind {
            @ast.EBin(@ast.OpMatch, _, rhs) =>
              match rhs.kind {
                @ast.EAsBind(_, name) => assert_eq(name, "cap")
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
/// `re` ALONE IS A NAME. The toolchain REJECTs it used as a value
/// (`_verify/settle_0494_parse_backlog.ps1`, row `a7`), and a reader that
/// turned every `re` into a literal would swallow the identifier.
test "0494: a bare `re` is a name and not a regex literal" {
  let r = @parser.parse("fn f() -> Int {\n  re\n}\n")
  assert_eq(r.first_error, 0)
  match r.tree.body[0].kind {
    @ast.SFunc(_, _, _, body, _) =>
      match body[0].kind {
        @ast.STail(e) =>
          match e.kind {
            @ast.EName(n) => assert_eq(n, "re")
            _ => assert_true(false)
          }
        _ => assert_true(false)
      }
    _ => assert_true(false)
  }
}

///|
/// THE UPDATE LIST. `for x = value, i = len - 1; i >= 0; x = x / base, i = i - 1`
/// -- `async 0.22.4 src/http/utils.mbt:23`. The row asserts that BOTH updates
/// reached the loop body: a reader that took one and left the comma behind
/// would satisfy "it parses".
test "0494: a comma-separated update list reaches the loop body" {
  let r = @parser.parse(
    "fn f(value : Int, base : Int, len : Int) -> Unit {\n  for x = value, i = len - 1; i >= 0; x = x / base, i = i - 1 {\n    ignore(x)\n  }\n}\n",
  )
  assert_eq(r.first_error, 0)
  match r.tree.body[0].kind {
    @ast.SFunc(_, _, _, body, _) =>
      match body[0].kind {
        @ast.SBlock(stmts) => {
          // <init x2> + the SWhile the desugaring produces, as 0472 measured.
          assert_eq(stmts.length(), 3)
          match stmts[2].kind {
            // the body statement + the two updates
            @ast.SWhile(_, loop_body) => assert_eq(loop_body.length(), 3)
            _ => assert_true(false)
          }
        }
        _ => assert_true(false)
      }
    _ => assert_true(false)
  }
}

///|
/// ONE update still works -- the shape that was never broken, and the control
/// on the row above: if the list reader swallowed the comma in the SINGLE
/// case too, this row would go red.
test "0494: a single update still reaches the loop body" {
  let r = @parser.parse(
    "fn f(len : Int) -> Unit {\n  for i = 0; i < len; i = i + 1 {\n    ignore(i)\n  }\n}\n",
  )
  assert_eq(r.first_error, 0)
  match r.tree.body[0].kind {
    @ast.SFunc(_, _, _, body, _) =>
      match body[0].kind {
        @ast.SBlock(stmts) =>
          match stmts[1].kind {
            @ast.SWhile(_, loop_body) => assert_eq(loop_body.length(), 2)
            _ => assert_true(false)
          }
        _ => assert_true(false)
      }
    _ => assert_true(false)
  }
}

///|
/// THE SHORTHAND STRUCT PATTERN. `let { identity, .. } = x` --
/// `async 0.22.4 src/fs/watch_kqueue.mbt:240`. The row asserts the NAME it
/// binds, because a reader that consumed the pattern and bound nothing would
/// satisfy "it parses" -- and the name would then be reported undefined at
/// its use.
test "0494: a shorthand struct pattern binds the field it names" {
  let r = @parser.parse(
    "fn f(x : J) -> Unit {\n  let { identity, .. } = x\n  ignore(identity)\n}\n",
  )
  assert_eq(r.first_error, 0)
  match r.tree.body[0].kind {
    @ast.SFunc(_, _, _, body, _) =>
      match body[0].kind {
        @ast.SLetDestruct(names, _) => {
          assert_eq(names.length(), 1)
          assert_eq(names[0], "identity")
        }
        _ => assert_true(false)
      }
    _ => assert_true(false)
  }
}

///|
/// THE KEYED SPELLING IS STILL REFUSED, and this is the row that keeps it so.
/// `let { "cmd": [cmd], .. } = x` is a program the toolchain REJECTs -- 0011,
/// "a `let` pattern must be irrefutable" (settle row `c3`) -- and 0485 pinned
/// that refusal on purpose. The shorthand reader must not have taken it over:
//! the two spellings are told apart, and the keyed one still reports.
//
//| It is the same claim 0485 made, restated beside the row that says the
//| SHORTHAND is read. Between them they say what the reader does: this one
//| says what it must NOT do.
test "0494: the keyed let pattern is still refused" {
  let r = @parser.parse(
    "fn f(x : J) -> Unit {\n  let { \"cmd\": [cmd], .. } = x\n  ignore(cmd)\n}\n",
  )
  assert_true(r.first_error > 0)
}

///|
/// THE DESCENDING RANGE. `for i in path.length()>..0` --
/// `async 0.22.4 src/fs/watch_windows.mbt:320`. The row asserts the RANGE node:
/// a reader that read `>` as a comparison would satisfy "it parses" and be
/// wrong about the shape.
test "0494: a descending range is a range and not a comparison" {
  let r = @parser.parse(
    "fn f(n : Int) -> Unit {\n  for i in n>..0 {\n    ignore(i)\n  }\n}\n",
  )
  assert_eq(r.first_error, 0)
  match r.tree.body[0].kind {
    @ast.SFunc(_, _, _, body, _) =>
      match body[0].kind {
        @ast.SFor(_, _, seq, _) =>
          match seq.kind {
            @ast.ERange(_, _) => ()
            _ => assert_true(false)
          }
        _ => assert_true(false)
      }
    _ => assert_true(false)
  }
}

///|
/// A BARE `..` IS STILL NOT A RANGE. The toolchain REJECTs it and names the
/// two real forms in its own hint (settle row `d3`), so the reader must not
/// have started accepting it.
test "0494: a bare `..` is still not a range" {
  let r = @parser.parse(
    "fn f(n : Int) -> Unit {\n  for i in n..0 {\n    ignore(i)\n  }\n}\n",
  )
  assert_true(r.first_error > 0)
}

///|
/// A `break` MAY CARRY A VALUE. `break path[:i]` --
/// `async 0.22.4 src/fs/watch_windows.mbt:322`. The row asserts that the
/// value is IN THE TREE and that the break is still there: a reader that
/// dropped the value would satisfy "it parses" and lose the name the value
/// reads.
test "0494: a break may carry a value and the value is read" {
  let r = @parser.parse(
    "fn f(path : StringView) -> StringView {\n  for i in path.length()>..0 {\n    break path[:i]\n  } nobreak {\n    \"\"\n  }\n}\n",
  )
  assert_eq(r.first_error, 0)
  match r.tree.body[0].kind {
    @ast.SFunc(_, _, _, body, _) =>
      match body[0].kind {
        @ast.SNoBreak(loop_stmt, _) =>
          match loop_stmt.kind {
            @ast.SFor(_, _, _, lbody) =>
              match lbody[0].kind {
                @ast.SBlock(vals) => {
                  // the break itself + the value it carries
                  assert_eq(vals.length(), 2)
                  match vals[0].kind {
                    @ast.SBreak => ()
                    _ => assert_true(false)
                  }
                }
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
/// A BARE `break` IS STILL A BARE BREAK -- the control on the row above. The
/// valued form wraps the break in a block, so a reader that wrapped EVERY
/// break would satisfy the valued row and change this one.
test "0494: a bare break is still a bare break" {
  let r = @parser.parse(
    "fn f(n : Int) -> Int {\n  for i in n..<10 {\n    break\n  }\n  0\n}\n",
  )
  assert_eq(r.first_error, 0)
  match r.tree.body[0].kind {
    @ast.SFunc(_, _, _, body, _) =>
      match body[0].kind {
        @ast.SFor(_, _, _, lbody) =>
          match lbody[0].kind {
            @ast.SBreak => ()
            _ => assert_true(false)
          }
        _ => assert_true(false)
      }
    _ => assert_true(false)
  }
}
