///|
/// A QUALIFIED constructor in an `is` pattern: `is St::Shutdown`.
///
/// The framing this started from was wrong, and the correction is the content of
/// the increment. The standing backlog called it "`is` pattern in EXPRESSION
/// position", on the reading that `parse_is` was not reached. It is reached, at
/// the right precedence tier, and had been since before the corpus grew. What is
/// missing is inside `parse_is_pattern`: the lexer has no `TColonColon`, `::` is
/// two `TColon` tokens, and the pattern reader bumped the head name and returned
/// without consuming them. The surviving `:` walked back up through `parse_cmp`
/// and landed in `parse_atom`'s catch-all, which is why the scanner's reason
/// string was ``unexpected token `:` `` on a line whose `:` is a PATH MARKER.
///
/// Settled with the toolchain, one form per package with a broken canary beside
/// it (`_verify/probe_sweep_0434.ps1`, re-run at 0.4.30 with the canary firing):
///
///   `if self is St::Shutdown { 1 } else { 2 }`  0 errors -- MOON-OK
///   `status() is St::Presented`                 0 errors -- MOON-OK
///   `fn canary( { let = 1 }`                    REJECTED, as it must be
///
/// and both SELF-FAILed before this fix with ``unexpected token `:` ``.
///
/// Measured on wzzc-dev/moui 0.1.12: 5 files, all of the `Type::Ctor` shape --
/// `views/form/file_import.mbt:86`, `render/common/gpu_render_worker.mbt:114`,
/// `views/presentation.mbt:475`, `render/renderer_session.mbt:167`,
/// `backend/common/host_modal/host_modal_session.mbt:107`.
///

///|
/// WHAT THESE TESTS ASSERT, AND WHY NOT A REPORT COUNT. The obvious assertion is
/// `count_family(r, "UndefinedName") == 0` on a source that uses the payload
/// binding, and it is VACUOUS here: `@parser.parse` returns `ParseResult`, whose
/// `reports` carry PARSE findings and subset exclusions. The three lenses run in
/// `@pipeline`, so `FUndefinedName` can never appear in a `ParseResult` no matter
/// what the tree says. That assertion was written, and its control -- the same
/// body with the binding never introduced, expecting one undefined name -- came
/// back `0 != 1` and gave the game away.
///
/// So the observable is the TREE: `EIs` carries `Array[String]` of bindings, and
/// that array is exactly what `parse_is_pattern` produced. A dropped binding is
/// visible there; a swallowed pattern is visible as a `first_error`; a fix that
/// reads the pattern but loses the payload is visible as `[]`.
///

///|
/// A SECOND FACT these tests had to be written around, found the same way: an
/// `enum` declaration is NOT a member of `Module.body`. Parsing `enum St { .. }`
/// plus one `fn` gives `body.length() == 1`, and `body[1]` throws. The enum is
/// harvested for its constructors and announced as a subset exclusion ("enum
/// declaration is outside the analyzed subset; its body was not analyzed") --
/// which is also why "this source says nothing extra" cannot be asserted as
/// `reports.length() == 0`. The last test below compares the QUALIFIED form
/// against the UNQUALIFIED one instead, which is the control that was wanted.

///|
/// The `if`-condition shape: 3 of the 5 files.
test "0436: a qualified constructor is read in an if condition" {
  let r = @parser.parse(
    "enum St {\n  Shutdown\n  Busy\n}\nfn f(self : St) -> Int {\n  if self is St::Shutdown {\n    1\n  } else {\n    2\n  }\n}\n",
  )
  assert_eq(r.first_error, 0)
  match r.tree.body[0].kind {
    @ast.SFunc(_, _, _, body, _) =>
      match body[0].kind {
        @ast.SIf(cond, then_b, _, else_b) => {
          // The condition is an `is` TEST, not a call and not a field access --
          // this is the assertion that the pattern reached `parse_is_pattern`.
          match cond.kind {
            @ast.EIs(_, binds) => assert_eq(binds.length(), 0)
            _ => assert_true(false)
          }
          assert_eq(then_b.length(), 1)
          // The `else` has to still be there. A `::` loop that consumed one
          // segment too many would leave the condition parsed and the arm gone.
          match else_b {
            Some(es) => assert_eq(es.length(), 1)
            None => assert_true(false)
          }
        }
        _ => assert_true(false)
      }
    _ => assert_true(false)
  }
}

///|
/// The BARE-expression shape: 2 of the 5 files -- `is` with no `if` around it,
/// which the reason string made look like a different construct entirely.
test "0436: a qualified constructor is read as a bare expression" {
  let r = @parser.parse(
    "enum St {\n  Presented\n  Closed\n}\nfn status() -> St {\n  St::Presented\n}\nfn g() -> Int {\n  1\n}\nfn f() -> Bool {\n  let ok = status() is St::Presented\n  if ok {\n    g()\n    true\n  } else {\n    false\n  }\n}\n",
  )
  assert_eq(r.first_error, 0)
  // The enum is not in `Module.body`, so `body[2]` is `fn f`: `body[1]` is `fn g`,
  // whose body is the literal `1`.
  match r.tree.body[2].kind {
    @ast.SFunc(_, _, _, body, _) =>
      match body[0].kind {
        @ast.SLet(_, _, v) =>
          match v.kind {
            @ast.EIs(_, binds) => assert_eq(binds.length(), 0)
            _ => assert_true(false)
          }
        _ => assert_true(false)
      }
    _ => assert_true(false)
  }
}

///|
/// THE ASSERTION THIS INCREMENT EXISTS FOR. Consuming the path tail BEFORE the
/// payload test is what lets a QUALIFIED constructor with a payload take the
/// existing paren branch and bind its argument. Read the tail after the payload
/// test instead and `x` is dropped -- same `first_error`, same `EIs`, empty
/// bindings -- which is the failure mode no parse-error assertion can see.
test "0436: a qualified constructor with a payload binds its argument" {
  let r = @parser.parse(
    "enum St {\n  Some(Int)\n  None\n}\nfn f(self : St) -> Int {\n  if self is St::Some(x) {\n    x\n  } else {\n    0\n  }\n}\n",
  )
  assert_eq(r.first_error, 0)
  match r.tree.body[0].kind {
    @ast.SFunc(_, _, _, body, _) =>
      match body[0].kind {
        @ast.SIf(cond, _, _, _) =>
          match cond.kind {
            @ast.EIs(_, binds) => {
              assert_eq(binds.length(), 1)
              assert_eq(binds[0], "x")
            }
            _ => assert_true(false)
          }
        _ => assert_true(false)
      }
    _ => assert_true(false)
  }
}

///|
/// CONTROL for the test above, and the reason it can be believed. The SAME
/// qualified path with NO payload binds nothing: so the binding in the previous
/// test came from the payload and not from the path tail being consumed, which is
/// the only way `is St::Some(x)` and `is St::None` could otherwise be
/// indistinguishable.
test "0436 control: a qualified constructor without a payload binds nothing" {
  let r = @parser.parse(
    "enum St {\n  Some(Int)\n  None\n}\nfn f(self : St) -> Int {\n  if self is St::None {\n    0\n  } else {\n    1\n  }\n}\n",
  )
  assert_eq(r.first_error, 0)
  match r.tree.body[0].kind {
    @ast.SFunc(_, _, _, body, _) =>
      match body[0].kind {
        @ast.SIf(cond, _, _, _) =>
          match cond.kind {
            @ast.EIs(_, binds) => assert_eq(binds.length(), 0)
            _ => assert_true(false)
          }
        _ => assert_true(false)
      }
    _ => assert_true(false)
  }
}

///|
/// CONTROL: the UNQUALIFIED payload still binds, unchanged by the path loop.
test "0436 control: an unqualified constructor with a payload still binds" {
  let r = @parser.parse(
    "enum St {\n  Some(Int)\n  None\n}\nfn f(self : St) -> Int {\n  if self is Some(x) {\n    x\n  } else {\n    0\n  }\n}\n",
  )
  assert_eq(r.first_error, 0)
  match r.tree.body[0].kind {
    @ast.SFunc(_, _, _, body, _) =>
      match body[0].kind {
        @ast.SIf(cond, _, _, _) =>
          match cond.kind {
            @ast.EIs(_, binds) => {
              assert_eq(binds.length(), 1)
              assert_eq(binds[0], "x")
            }
            _ => assert_true(false)
          }
        _ => assert_true(false)
      }
    _ => assert_true(false)
  }
}

///|
/// CONTROL: a TUPLE pattern is a different branch of `parse_is_pattern` and must
/// be unaffected -- it returns before the path loop is ever reached.
test "0436 control: a tuple pattern still binds each member" {
  let r = @parser.parse(
    "enum St {\n  Pair(Int, Int)\n  None\n}\nfn f(self : St) -> Int {\n  if self is Pair(a, b) {\n    a + b\n  } else {\n    0\n  }\n}\n",
  )
  assert_eq(r.first_error, 0)
  match r.tree.body[0].kind {
    @ast.SFunc(_, _, _, body, _) =>
      match body[0].kind {
        @ast.SIf(cond, _, _, _) =>
          match cond.kind {
            @ast.EIs(_, binds) => {
              assert_eq(binds.length(), 2)
              assert_eq(binds[0], "a")
              assert_eq(binds[1], "b")
            }
            _ => assert_true(false)
          }
        _ => assert_true(false)
      }
    _ => assert_true(false)
  }
}

///|
/// CONTROL, and the one that replaces "this source says nothing extra". The
/// qualified form must produce EXACTLY what the unqualified form already produced
/// -- same parse outcome, same report count. This source emits one report, the
/// enum's own subset exclusion, and both spellings must emit exactly that one; a
/// `::` loop that swallowed or duplicated something would move the count.
///
/// Comparing the two forms is what makes this a control rather than a constant:
/// the number 1 is the enum's, and it is checked on both sides at once.
test "0436 control: the qualified form says exactly what the unqualified one does" {
  let qual = @parser.parse(
    "enum St {\n  Shutdown\n  Busy\n}\nfn f(self : St) -> Int {\n  if self is St::Shutdown {\n    1\n  } else {\n    2\n  }\n}\n",
  )
  let unqual = @parser.parse(
    "enum St {\n  Shutdown\n  Busy\n}\nfn f(self : St) -> Int {\n  if self is Shutdown {\n    1\n  } else {\n    2\n  }\n}\n",
  )
  assert_eq(qual.first_error, 0)
  assert_eq(unqual.first_error, 0)
  assert_eq(qual.reports.length(), unqual.reports.length())
  assert_eq(qual.skips.length(), unqual.skips.length())
}

///|
/// KNOWN LIMIT, PINNED -- a PACKAGE-qualified pattern head. `is @pkg.Type::Ctor`
/// does NOT parse today: `parse_is_pattern` reads a `TName` head, and this head
/// starts with `@`, so `peek_name()` is "", the reader returns without consuming
/// anything, and the cascade ends the file. On the `if` shape that is 6 parse
/// errors and the statements after the `let` are lost.
///
/// 48 sites corpus-wide (`moonbit-community/sqlite3 0.2.3 async_test.mbt:5` is
/// `statement.step_async() is @sqlite3.StepResult::Done(..)`, and the payload
/// attaches there too), 32 of them in wzzc-dev/moui across 16 files.
///
/// SITES ARE NOT FILES, and the difference is the whole content of this note.
/// Scanning each of those 16 files ALONE (`_verify/pkg_head_impact.ps1`) gives
/// `parsed=1/1` for 15 of them and `parsed=0/1` for exactly ONE:
/// `backend/macos/macos_services.mbt`. The other 15 are `_test.mbt` /
/// `_wbtest.mbt` files whose site sits inside a `test` block, and the frontend
/// skips those whole -- which is why the construct has been invisible this long.
///
/// So the coverage value of fixing this is ONE file today and SIXTEEN the day
/// test blocks are analysed. Ranking it by its 32 sites would have put a
/// one-file fix above a six-file one, which is the third time this round that
/// particular mistake was available.
///
/// IT WAS ALSO INVISIBLE TO THE RANKING TOOL, and that is worth recording.
/// Cross-referencing "files with an `@pkg` is-head" against `blockers.ps1`'s
/// blocked list gives OVERLAP 0 -- the construct appears to cost nothing --
/// because `macos_services.mbt` is one of the four blocked files that print no
/// `PARTIAL` line at all, having zero findings before its boundary.
/// `blockers.ps1` says so in its own header ("a lower bound on the blocked set,
/// not the whole of it"), and this landed exactly there. ⇒ 判据: a lower bound
/// that agrees with "no problem" is not evidence of no problem; cross-referencing
/// two lists only tells you about the part both can see.
///
/// Pinned rather than fixed so the next round inherits a measured number, a
/// failing test, and a script that produces the number. Asserting the CURRENT
/// failure is the honest form: implementing the `@`-head turns this red.
test "0436 KNOWN LIMIT: a package-qualified is pattern head does not parse yet" {
  let r = @parser.parse(
    "enum StepResult {\n  Done(Int)\n  Busy\n}\nfn f(self : StepResult) -> Int {\n  if self is @sqlite3.StepResult::Done(..) {\n    1\n  } else {\n    0\n  }\n}\n",
  )
  assert_true(r.first_error != 0)
}

///|
/// CONTROL for the limit above: the same pattern with the `@sqlite3.` prefix
/// REMOVED must parse. If this one failed too, the 48 sites would be about the
/// payload `Done(..)` rather than about the package prefix, and the note above
/// would be pointing at the wrong thing.
test "0436 control: the same pattern without the package prefix parses" {
  let r = @parser.parse(
    "enum StepResult {\n  Done(Int)\n  Busy\n}\nfn f(self : StepResult) -> Int {\n  if self is StepResult::Done(..) {\n    1\n  } else {\n    0\n  }\n}\n",
  )
  assert_eq(r.first_error, 0)
}

///|
/// The qualified path must not be able to eat the file. `g()` after the `if` is
/// the statement that disappears if the path tail consumed one token too many,
/// and `first_error` stays 0 while it happens.
test "0436: a qualified constructor does not cost the statements after it" {
  let r = @parser.parse(
    "enum St {\n  Shutdown\n  Busy\n}\nfn g() -> Int {\n  7\n}\nfn f(self : St) -> Int {\n  if self is St::Shutdown {\n    1\n  } else {\n    2\n  }\n  g()\n}\n",
  )
  assert_eq(r.first_error, 0)
  // The enum is not in `body`, so `body[1]` is `fn f`.
  match r.tree.body[1].kind {
    @ast.SFunc(_, _, _, body, _) => assert_eq(body.length(), 2)
    _ => assert_true(false)
  }
}
