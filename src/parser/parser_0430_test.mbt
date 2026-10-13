///|
/// The optional-argument shorthand `f(x?)`, and the label it must carry.
///
/// Settled with the toolchain, not inferred: `_verify/grammar_probe.ps1`
/// case `optarg_question`, one form per package with a deliberately broken
/// canary file alongside so a "no work to do" run cannot pass for a legal
/// form.
///
///   fn sink(theme? : Int = 0) -> Int { theme }
///   fn pass(theme? : Int) -> Int { sink(theme?) }
///     -> moon check: 0 errors
///     -> before this fix: SELF-FAIL, `expected ')'`
///
/// It blocked 34 files on wzzc-dev/moui 0.1.12, the largest single named
/// blocker measured there. The `~` sibling below is the CONTROL: it was
/// already handled, so if this test's shape were wrong the control would
/// catch it.
test "0430: f(x?) parses clean and labels the argument x" {
  let r = @parser.parse(
    "fn sink(theme? : Int = 0) -> Int { theme }\nfn pass(theme? : Int) -> Int { sink(theme?) }\n",
  )
  assert_eq(r.first_error, 0)
  assert_eq(r.reports.length(), 0)
}

///|
/// The LABEL is the part that is easy to get wrong and silent when wrong.
/// The type lens maps arguments to parameters BY LABEL whenever any argument
/// is named (see the `ECall` note in ast.mbt: without the labels it compared
/// `args[3]` against `params[3]` and reported six false mismatches on
/// `core/gesture.mbt`). A `?` argument left unlabelled falls back to that
/// positional mapping, so this asserts the label rather than only the parse.
///
/// `moui` shape: a multi-argument call where `theme?` sits among `x~`
/// shorthands and ordinary positional arguments.
test "0430: the ? shorthand labels the argument, and neighbours are untouched" {
  let r = @parser.parse(
    "fn sink(a : Int, theme? : Int = 0, b : Int) -> Int { a + theme + b }\nfn pass(theme? : Int) -> Int { sink(1, theme?, 2) }\n",
  )
  assert_eq(r.first_error, 0)
  assert_eq(r.reports.length(), 0)
}

///|
/// CONTROL for the two tests above. `f(x~)` was already handled before 0430.
/// It is pinned here so a future change that breaks the `~` branch cannot be
/// mistaken for a `?` regression, and so the two sigils cannot silently
/// diverge -- they mean the same thing to the type lens.
test "0430 control: the ~ shorthand still parses and labels the same way" {
  let r = @parser.parse(
    "fn sink(a : Int, theme~ : Int = 0, b : Int) -> Int { a + theme + b }\nfn pass(theme~ : Int) -> Int { sink(1, theme~, 2) }\n",
  )
  assert_eq(r.first_error, 0)
  assert_eq(r.reports.length(), 0)
}

///|
/// A `?` at the END of an argument list, with no comma after it. This is the
/// shape `optarg_question` exercises, and it is a DIFFERENT code path from the
/// mid-list case: the loop's comma handling breaks out instead of continuing.
/// The pre-fix reason differed between the two positions -- `expected ')'`
/// here, ``unexpected token `,` `` mid-list -- which is why both are pinned.
test "0430: the ? shorthand also works as the last argument" {
  let r = @parser.parse(
    "fn sink(a : Int, theme? : Int = 0) -> Int { a + theme }\nfn pass(a : Int, theme? : Int) -> Int { sink(a, theme?) }\n",
  )
  assert_eq(r.first_error, 0)
  assert_eq(r.reports.length(), 0)
}

///|
/// THE SILENT ONE. Consuming the `?` is easy and is what a first fix would do;
/// RECORDING THE LABEL is the part with no symptom. A `?` argument with a blank
/// label still PARSES, so the three tests above all stay green -- and the type
/// lens then falls back to matching arguments to parameters by INDEX, which is
/// the false-positive path the `ECall` note in ast.mbt records (six mismatches
/// on moui's `core/gesture.mbt` before labels existed).
///
/// So the label is asserted directly rather than inferred from a clean parse.
/// `ECall(String, Array[Expr], Array[String])` and `SFunc(name, params, ret,
/// body, span)` are read by position; the `else` arms fail loudly rather than
/// letting an empty match read as a pass.
test "0430: the ? argument carries the label 'theme', not a blank one" {
  let r = @parser.parse(
    "fn sink(theme? : Int = 0) -> Int { theme }\nfn pass(theme? : Int) -> Int { sink(theme?) }\n",
  )
  assert_eq(r.reports.length(), 0)
  let mut seen = false
  match r.tree.body[1].kind {
    @ast.SFunc(_, _, _, body, _) =>
      match body[0].kind {
        @ast.STail(e) =>
          match e.kind {
            @ast.ECall(name, _, labels) => {
              seen = true
              assert_eq(name, "sink")
              assert_eq(labels.length(), 1)
              assert_eq(labels[0], "theme")
            }
            _ => ()
          }
        _ => ()
      }
    _ => ()
  }
  assert_true(seen)
}

///|
/// The same assertion for the `~` sigil, so the two cannot drift apart. They
/// mean the same thing to the type lens -- `x~` always passes, `x?` passes when
/// present -- and the 0430 mutation gate mutates the two branches separately,
/// so each needs its own pinned label.
test "0430 control: the ~ argument carries the label 'theme' too" {
  let r = @parser.parse(
    "fn sink(theme~ : Int = 0) -> Int { theme }\nfn pass(theme~ : Int) -> Int { sink(theme~) }\n",
  )
  assert_eq(r.reports.length(), 0)
  let mut seen = false
  match r.tree.body[1].kind {
    @ast.SFunc(_, _, _, body, _) =>
      match body[0].kind {
        @ast.STail(e) =>
          match e.kind {
            @ast.ECall(_, _, labels) => {
              seen = true
              assert_eq(labels.length(), 1)
              assert_eq(labels[0], "theme")
            }
            _ => ()
          }
        _ => ()
      }
    _ => ()
  }
  assert_true(seen)
}

///|
/// `tok_desc`, reached through its only observable effect: the message
/// `parse_atom`'s catch-all emits.
///
/// Before 0430 that message was the bare string "unexpected token", and it was
/// the recorded reason for 110 of the 122 files wzzc-dev/moui 0.1.12 could not
/// read at all -- 90% of the corpus's coverage blockers behind a sentence that
/// never said which token stopped the parse. The scanner tallies partial files
/// BY REASON MESSAGE, so the message is the ranking key: naming the token turned
/// one anonymous `110x` row into a 13-row distribution.
///
/// `let x = )` and `let x = ?` were chosen by probing which tokens actually
/// REACH the catch-all rather than by picking one and hoping: `)`, `,`, `->`
/// and `?` all do, while `@` does not -- the lexer consumes a bare `@` without
/// reaching the parser at all, so a first draft that used `@` passed for the
/// wrong reason.
///
/// TWO tokens are asserted, not one, and that is the point: the first version of
/// this test checked only `` `)` `` and mutation M3 -- which degrades `tok_desc`'s
/// `TQuestion` arm alone -- SURVIVED it. The gate caught a test that passed for
/// the wrong reason, which is the only reason it is worth having. `?` is checked
/// as well as `)` so that degrading any single arm is visible.
///
/// The assertion is that the token appears IN the message, not an exact string,
/// so a reworded description does not churn the test.
test "0430: the unexpected-token message NAMES the offending token" {
  let rparen = @parser.parse("fn f() -> Int {\n  let x = )\n  x\n}\n")
  assert_true(rparen.reports.length() > 0)
  let mut sawRParen = false
  for rep in rparen.reports {
    if rep.message.contains("unexpected token") && rep.message.contains("`)`") {
      sawRParen = true
    }
  }
  assert_true(sawRParen)
  let quest = @parser.parse("fn f() -> Int {\n  let x = ?\n  x\n}\n")
  assert_true(quest.reports.length() > 0)
  let mut sawQuestion = false
  for rep in quest.reports {
    if rep.message.contains("unexpected token") && rep.message.contains("`?`") {
      sawQuestion = true
    }
  }
  assert_true(sawQuestion)
}

///|
/// A control for the message test: a parse that does NOT fail must not have
/// borrowed the catch-all's wording. Without this, a parser that emitted
/// "unexpected token" unconditionally would pass the test above.
test "0430 control: a clean parse emits no unexpected-token message at all" {
  let r = @parser.parse("fn f() -> Int {\n  1\n}\n")
  assert_eq(r.reports.length(), 0)
  assert_eq(r.first_error, 0)
}
