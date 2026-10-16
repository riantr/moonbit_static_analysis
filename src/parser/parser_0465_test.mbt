//| Tests for the `..` CHAIN LINK (`recv..name(args)`), 0465.
//
//| The grammar is SETTLED against the toolchain, not read off the symbol:
//| `_verify/settle_0465_dotdot_chain.ps1`, 14 rows, all controls held. The three
//| rows that matter here are
//!
//!     S::new()..get().v   ACCEPT        <- `get` returns Int, and this is S.v
//!     S::new().get().v    REJECT(4028)  <- the `.` spelling of the same expression
//!     ..two(1)            REJECT(4080)  <- wrong arity, so the args really bind
//!
//! so `recv..name(args)` CALLS `name`, DISCARDS its result, and EVALUATES TO `recv`.
//! It is a distinct node rather than an `EMethodCall` spelling because the type and
//! the value both come from the receiver, and every one of the 33 corpus files that
//! write it would be parsed and typed wrongly otherwise.
//|
//| All 180 corpus sites are consistent with BOTH readings, so none of them can
//| settle this: real code only chains methods that RETURN the receiver. The
//| discriminating fixture has to chain a method that changes the type on purpose.

//||

///|
/// The corpus shape, at `moonbitlang/async 0.22.4 src/http/send.mbt:333-337`:
///
///     let content_length = self
///       ..write(path)
///       ..write(b" HTTP/1.1\r\n")
///       ..write(self.headers)
///       .send_headers(extra_headers)
///
/// Asserting `first_error == 0` is NOT the test -- a silently dropped chain parses
/// clean, which is the 0432 lesson. What is asserted is the NODE: an `EDotDot` per
/// `..` link, a real `EName` receiver, and the arguments present.
test "0465: the corpus shape builds one EDotDot per `..` link, on the real receiver" {
  let r = @parser.parse(
    "fn f(self : Int, path : String, head : String) -> Int {\n  let n = self\n    ..write(path)\n    ..write(head)\n    .write(head)\n  n\n}\n",
  )
  assert_eq(r.first_error, 0)
  match r.tree.body[0].kind {
    @ast.SFunc(_, _, _, body, _) =>
      match body[0].kind {
        @ast.SLet(name, _, init) => {
          assert_eq(name, "n")
          match init.kind {
            // The final `.write` is an ordinary method call. If it came out as
            // EDotDot instead, the new branch would be stealing the single-dot case.
            @ast.EMethodCall(base, meth, args, _) => {
              assert_eq(meth, "write")
              assert_eq(args.length(), 1)
              match base.kind {
                @ast.EDotDot(recv, m2, args2, _) => {
                  assert_eq(m2, "write")
                  assert_eq(args2.length(), 1)
                  // Two `..` links, so the receiver of the outer one is the inner
                  // one -- and the inner one's receiver must be the `self` the let
                  // bound, not a placeholder. A statement-level chain can only
                  // offer EBigInt; the let form is the one that keeps the name.
                  match recv.kind {
                    @ast.EDotDot(recv2, m3, _, _) => {
                      assert_eq(m3, "write")
                      match recv2.kind {
                        @ast.EName(_) => ()
                        _ => assert_true(false)
                      }
                    }
                    _ => assert_true(false)
                  }
                }
                _ => assert_true(false)
              }
            }
            _ => assert_true(false)
          }
        }
        _ => assert_true(false)
      }
    _ => assert_true(false)
  }
}

//|

///|
/// THE FIRST ARGUMENT SURVIVES, and this row exists because of a bug that
/// `moon check --deny-warn` could not see.
///
/// `Parser::expect` BUMPS on success. The arm was written with an extra `bump()`
/// after `expect(TLParen, ..)`, which consumed the first ARGUMENT: `..write(path)`
/// went on to parse from the token after `path`. The tree stayed well typed --
/// `EDotDot(EName("self"), "write", [], [])` is a legal node -- so the compiler was
/// silent and `moon test` was green. The four fixture files that use a parameter
/// ONLY as a `..` argument then reported `parameter may not be used`.
///
/// => 判据: "it compiles" is not a statement about the tree. A dropped argument
/// produces a smaller, still well-typed tree, so the only control that catches it
/// is one that counts what the node carries.
test "0465: the first `..` argument is not dropped" {
  let r = @parser.parse(
    "fn f(self : Int, a : Int, b : Int) -> Int {\n  let n = self\n    ..write(a, b)\n  n\n}\n",
  )
  assert_eq(r.first_error, 0)
  match r.tree.body[0].kind {
    @ast.SFunc(_, _, _, body, _) =>
      match body[0].kind {
        @ast.SLet(_, _, init) =>
          match init.kind {
            @ast.EDotDot(_, _, args, _) => {
              assert_eq(args.length(), 2)
              match args[0].kind {
                @ast.EName(n0) => assert_eq(n0, "a")
                _ => assert_true(false)
              }
              match args[1].kind {
                @ast.EName(n1) => assert_eq(n1, "b")
                _ => assert_true(false)
              }
            }
            _ => assert_true(false)
          }
        _ => assert_true(false)
      }
    _ => assert_true(false)
  }
}

//|

///|
/// The INLINE form, 65 sites across 29 corpus files
/// (`examples/http_file_server/main.mbt:44`), which a "the next line is dot-led"
/// search does not see at all.
test "0465: the inline form `recv..m(a).m(b)` parses" {
  let r = @parser.parse(
    "fn f(out : Int, a : Int, b : Int) -> Int {\n  let n = out..write(a).write(b)\n  n\n}\n",
  )
  assert_eq(r.first_error, 0)
  match r.tree.body[0].kind {
    @ast.SFunc(_, _, _, body, _) =>
      match body[0].kind {
        @ast.SLet(_, _, init) =>
          match init.kind {
            @ast.EMethodCall(base, meth, _, _) => {
              assert_eq(meth, "write")
              match base.kind {
                @ast.EDotDot(recv, _, _, _) =>
                  match recv.kind {
                    @ast.EName(_) => ()
                    _ => assert_true(false)
                  }
                _ => assert_true(false)
              }
            }
            _ => assert_true(false)
          }
        _ => assert_true(false)
      }
    _ => assert_true(false)
  }
}

//|

///|
/// `..name` with NO argument list is REJECTED by the toolchain -- settle row
/// `dd_bare_name`, 4014/3002 -- so a parenthesised production is the grammar rather
/// than a shortcut, and the parser reports at the missing `(`.
///
/// The control beside it is the same expression with the parens, which must not
/// report. Without that control this row would also pass on a parser that rejected
/// every `..` form.
test "0465: a bare `..name` reports, and the parenthesised form beside it does not" {
  let bare = @parser.parse(
    "fn f(self : Int) -> Int {\n  let n = self\n    ..bump\n  n\n}\n",
  )
  assert_true(bare.first_error > 0)
  let ok = @parser.parse(
    "fn f(self : Int) -> Int {\n  let n = self\n    ..bump()\n  n\n}\n",
  )
  assert_eq(ok.first_error, 0)
}

//|

///|
/// THE CONTROL THE WHOLE INCREMENT RESTS ON: a single-dot chain is still an
/// `EMethodCall` with an `EField`-free receiver, exactly as before 0465. If the new
/// branch matched one TDot too many this row is what notices.
test "0465: a single-dot chain is untouched by the `..` arm" {
  let r = @parser.parse(
    "fn f(self : Int, a : Int) -> Int {\n  let n = self\n    .write(a)\n  n\n}\n",
  )
  assert_eq(r.first_error, 0)
  match r.tree.body[0].kind {
    @ast.SFunc(_, _, _, body, _) =>
      match body[0].kind {
        @ast.SLet(_, _, init) =>
          match init.kind {
            @ast.EMethodCall(_, meth, args, _) => {
              assert_eq(meth, "write")
              assert_eq(args.length(), 1)
            }
            _ => assert_true(false)
          }
        _ => assert_true(false)
      }
    _ => assert_true(false)
  }
}

//|

///|
/// AND THE STRUCT-UPDATE SPREAD IS STILL A STRUCT FIELD. `{ ..base, f: v }` and
/// `recv..m(x)` are two constructs that share a spelling; the discriminator lives
/// inside the struct-literal parser at `parse_struct_fields`, and this row is what
/// stops a future "just handle `..` once" refactor from breaking the 106 moui sites.
test "0465: the struct-update spread is still a struct field, not a chain link" {
  let r = @parser.parse(
    "fn f(base : Int, v : Int) -> Int {\n  let s = { ..base, v }\n  s\n}\n",
  )
  assert_eq(r.first_error, 0)
  match r.tree.body[0].kind {
    @ast.SFunc(_, _, _, body, _) =>
      match body[0].kind {
        @ast.SLet(_, _, init) =>
          match init.kind {
            @ast.EStruct(_, fields) => {
              assert_eq(fields.length(), 2)
              // The base keeps an EMPTY name and a live expression. Both are
              // load-bearing: the name is what stops `..base` resolving `base`
              // as a binding, and the expression is what stops `{ ..self }`
              // reporting `self` as an unused parameter.
              assert_eq(fields[0].0, "")
              match fields[0].1.kind {
                @ast.EName(_) => ()
                _ => assert_true(false)
              }
            }
            _ => assert_true(false)
          }
        _ => assert_true(false)
      }
    _ => assert_true(false)
  }
}
