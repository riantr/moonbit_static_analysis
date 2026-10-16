///|
/// A PACKAGE-qualified `is` pattern head: `is @pkg.Type::Ctor`.
///
/// WHY THIS EXISTS. `parse_is_pattern` read a `TName` head and then looped on `::`.
/// `@pkg` lexes as ONE `TName` with the `@` INSIDE the name string (lexer.mbt:361),
/// so the reader consumed `@pkg`, then met a `.` where the loop wanted a `:`, left
/// `qualified` false, and returned with `.Type::Ctor` still in the token stream. The
/// `::` finally reached `parse_atom`'s catch-all, which is why the scanner said
/// ``unexpected token `:` `` on a line whose `:` is a path marker.
///
/// The KNOWN LIMIT this replaces had recorded the mechanism WRONG -- it said
/// `peek_name()` returns `""` for an `@` head and the reader consumes nothing. It
/// does not. Both stories predict the same symptom and a different repair, and the
/// disagreement between the prediction (``unexpected token @``) and the measurement
/// (``unexpected token `:` ``) is what located the real one. A label carried
/// forward until it is measured is a label, not a fact.
///
/// The fix is four tokens: when the head starts with `@` and the next token is `.`,
/// consume the `.Type` segment so the existing `::` loop can do its job.
///
/// Settled against the toolchain BEFORE implementing --
/// `_verify/settle_0456_at_is_head.ps1`, 9/9, with the canary REJECTing and the
/// package boundary REJECTing so that the four ACCEPTs are discriminating.
/// `is @pkg.Type::Ctor` is legal MoonBit; the payload `..` is legal over a LABELED
/// payload and rejected over a positional one, which is a compiler rule and not this
/// parser's business.
///
/// Corpus: moui 0.1.12 parsed 606 -> 607, and `backend/macos/macos_services.mbt`
/// parses whole for the first time. 48 sites corpus-wide, 32 in moui across 16
/// files; `_verify/pkg_head_impact.ps1` is the file-by-file probe that produced the
/// "one file blocked" number.

///|
/// THE CONSTRUCT. This is the row the mutation gate names.
test "0456: a package-qualified is pattern head parses" {
  let r = @parser.parse(
    "enum StepResult {\n  Done\n  Busy\n}\nfn f(self : StepResult) -> Int {\n  if self is @sqlite3.StepResult::Done {\n    1\n  } else {\n    2\n  }\n}\n",
  )
  assert_eq(r.first_error, 0)
}

///|
/// THE ONE THAT MATTERS MOST, and the failure mode a parse-error assertion cannot
/// see. Before the fix `first_error` was already non-zero, so a test that only
/// checked "did it error" was satisfied by a file that stopped early. `g()` after
/// the `if` is the statement that disappears when the head reader leaves tokens in
/// the stream.
test "0456: the package-qualified head costs no statement after it" {
  let r = @parser.parse(
    "enum St {\n  Shutdown\n  Busy\n}\nfn g() -> Int {\n  7\n}\nfn f(self : St) -> Int {\n  if self is @svc.St::Shutdown {\n    1\n  } else {\n    2\n  }\n  g()\n}\n",
  )
  assert_eq(r.first_error, 0)
  // The enum is not in `body`, so `body[1]` is `fn f`.
  match r.tree.body[1].kind {
    @ast.SFunc(_, _, _, body, _) => assert_eq(body.length(), 2)
    _ => assert_true(false)
  }
}

///|
/// A PACKAGE-QUALIFIED HEAD NAMES A CONSTRUCTOR, not a binding, so it must not
/// introduce one. This is the same distinction the 0444 settle settled for a bare
/// lowercase head, and getting it wrong here would invent a variable in scope that
/// the source never declared.
test "0456: a package-qualified head introduces no bindings" {
  let r = @parser.parse(
    "enum St {\n  Shutdown\n  Busy\n}\nfn f(self : St) -> Int {\n  if self is @svc.St::Shutdown {\n    1\n  } else {\n    2\n  }\n}\n",
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
/// THE PAYLOAD STILL BINDS. The fix consumes `.Type` so the existing `::` loop and
/// the existing payload branch can both run; reading the tail first and dropping
/// everything after it would satisfy every parse-error assertion above while losing
/// `r` -- which is exactly the failure the 0436 payload test was written to catch.
test "0456: a package-qualified constructor with a payload still binds" {
  let r = @parser.parse(
    "enum St {\n  Some(Int)\n  None\n}\nfn f(self : St) -> Int {\n  if self is @svc.St::Some(r) {\n    r\n  } else {\n    0\n  }\n}\n",
  )
  assert_eq(r.first_error, 0)
  match r.tree.body[0].kind {
    @ast.SFunc(_, _, _, body, _) =>
      match body[0].kind {
        @ast.SIf(cond, _, _, _) =>
          match cond.kind {
            @ast.EIs(_, binds) => assert_eq(binds.length(), 1)
            _ => assert_true(false)
          }
        _ => assert_true(false)
      }
    _ => assert_true(false)
  }
}

///|
/// CONTROL. The qualified form must say exactly what the unqualified one already
/// said -- same parse outcome, same report count, same skip count. Comparing the two
/// forms is what makes this a control rather than a constant: a head reader that
/// swallowed or duplicated a token would move the counts even with `first_error`
/// still 0.
test "0456 control: the qualified form says exactly what the unqualified one does" {
  let qual = @parser.parse(
    "enum St {\n  Shutdown\n  Busy\n}\nfn f(self : St) -> Int {\n  if self is @svc.St::Shutdown {\n    1\n  } else {\n    2\n  }\n}\n",
  )
  let unqual = @parser.parse(
    "enum St {\n  Shutdown\n  Busy\n}\nfn f(self : St) -> Int {\n  if self is St::Shutdown {\n    1\n  } else {\n    2\n  }\n}\n",
  )
  assert_eq(qual.first_error, 0)
  assert_eq(unqual.first_error, 0)
  assert_eq(qual.reports.length(), unqual.reports.length())
  assert_eq(qual.skips.length(), unqual.skips.length())
}

///|
/// CONTROL ON THE FIX ITSELF. The `.Type` segment is consumed only when the next
/// token really is a `.`. An `@pkg.Ctor` head -- qualified, but with no type segment
/// -- must be untouched, or the new branch would consume a payload paren as if it
/// were a path segment and silently drop it.
test "0456 control: an at-qualified head with no type segment is untouched" {
  let r = @parser.parse(
    "enum St {\n  Shutdown\n  Busy\n}\nfn f(self : St) -> Int {\n  if self is @svc.Shutdown {\n    1\n  } else {\n    2\n  }\n}\n",
  )
  assert_eq(r.first_error, 0)
  match r.tree.body[0].kind {
    @ast.SFunc(_, _, _, body, _) =>
      match body[0].kind {
        @ast.SIf(cond, then_b, _, else_b) => {
          match cond.kind {
            @ast.EIs(_, binds) => assert_eq(binds.length(), 0)
            _ => assert_true(false)
          }
          assert_eq(then_b.length(), 1)
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
/// THE CORPUS SHAPE, verbatim in structure. `macos_services.mbt:405-406` writes
///
///     let in_menu_bar = menu.placement
///       is @services.ApplicationMenuPlacement::MenuBar
///
/// with the `is` on the FOLLOWING line. 0455 measured that line-continuation
/// questions are the ones that hide, so this row is not decorative: a head reader
/// that assumed the head begins on the `is` line would pass every other row here.
test "0456: the corpus shape, with the head on the line after the subject" {
  let r = @parser.parse(
    "enum Placement {\n  MenuBar\n  Dock\n}\nfn f(menu : Int) -> Bool {\n  let in_menu_bar = menu\n    is @services.Placement::MenuBar\n  in_menu_bar\n}\n",
  )
  assert_eq(r.first_error, 0)
  match r.tree.body[0].kind {
    @ast.SFunc(_, _, _, body, _) => assert_eq(body.length(), 2)
    _ => assert_true(false)
  }
}
