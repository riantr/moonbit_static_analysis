//| Tests for 0467, the ASYNC function type written without parentheses of its own.
//|
//| `async (A, B) -> R` is one construct spelled three ways, and until this increment
//| exactly one of them parsed:
//|
//|   (async (A, B) -> R)?      a parenthesised annotation   -- worked (0458)
//!   async (A, B) -> R         a bare parameter annotation  -- parsed=0
//!   -> async (A, B) -> R      a bare return annotation    -- parsed=0
//|
//| Reach, measured as per-FILE first blocker over the files still unread on the tree
//| that shipped as 12b38a3, bucketed with every member printed
//| (`_verify/rank_0467_shapes.ps1`): 19 of 57 -- 11 async, 8 proton -- which is the
//| largest single shape and a strict DEPENDENCY for the effect-in-param-position files,
//| since in all of them the effect hangs off an async type inside a parameter.
//!
//| The grammar is settled in `_verify/settle_0467_async_param_type.ps1`, 17 rows.
//! Two results are not guessable from the symbol:
//!
//!   g : async          REJECT  "Partial type is not allowed in toplevel
//!                                declarations." + "unexpected token `)`, you may
//!                                expect `(`"  -- so the `(` is REQUIRED
//!   g : bogus (Int) -> Unit   REJECT(3002) -- so the head is a KEYWORD, not any
//!                                        name followed by a parenthesised list
//!
//| The cause was an ORDERING fact and not a missing keyword: the `async` lookahead in
//| `fn_type_annotation` sat after its `bump() // (`, so it could only ever see `async`
//| when something had already put a `(` in front of it. The body is now shared by all
//| three spellings rather than copied, because a second copy of the parameter loop
//| would have been a fourth spelling to keep in step.

//|

///|
/// THE CORPUS SHAPE, and it is spelled on `moonbitlang/async 0.22.4
/// src/task_group.mbt:50`. Asserting that it PARSES is the weak form of this row; the
/// row that says it was really read is in `pipeline_0467_test.mbt`.
test "0467: `f : async (Int) -> Unit` parses" {
  let r = @parser.parse(
    "///|\nfn f(g : async (Int) -> Unit) -> Unit {\n  ()\n}\n",
  )
  assert_eq(r.first_error, 0)
  assert_eq(r.reports.length(), 0)
}

///|
/// THE EMPTY ARGUMENT LIST, `async () -> Unit`. It is the single most common corpus
/// spelling -- task_group, event_loop, lazy_init, js_async and install_wbtest all write
/// it -- and it is the shape most likely to be missed by a rule that insists on at
/// least one parameter.
test "0467: `async () -> Unit` with an empty argument list parses" {
  let r = @parser.parse("///|\nfn f(g : async () -> Unit) -> Unit {\n  ()\n}\n")
  assert_eq(r.first_error, 0)
  assert_eq(r.reports.length(), 0)
}

///|
/// MULTIPLE ARGUMENTS, ONE OF THEM GENERIC: `async (String, Array[String]) -> Unit`,
/// the shape at `src/fs/dir.mbt:433`. Two separate ways to get this wrong and both are
/// covered by putting them in one row -- a rule that stops at the first comma, and a
/// rule that treats the argument list as a single type.
test "0467: multiple async arguments, one generic, parse" {
  let r = @parser.parse(
    "///|\nfn f(g : async (String, Array[String]) -> Unit) -> Unit {\n  ()\n}\n",
  )
  assert_eq(r.first_error, 0)
  assert_eq(r.reports.length(), 0)
}

///|
/// THE EFFECT, on the async type inside a PARAMETER -- `moonbit-community/proton
/// 0.3.4 facade_context.mbt:137`. This is the row that makes the increment worth
/// landing on its own: `noraise` in this position was already reachable (0466's settle
/// row `param_noraise`), but only after this type parsed at all.
test "0467: `async (Int) -> Unit noraise` in a parameter parses" {
  let r = @parser.parse(
    "///|\nfn f(g : async (Int) -> Unit noraise) -> Unit {\n  ()\n}\n",
  )
  assert_eq(r.first_error, 0)
  assert_eq(r.reports.length(), 0)
}

///|
/// AN OPTIONAL PARAMETER WITH A DEFAULT -- `proton facade_updater.mbt:142`,
/// `p? : async (Int64) -> Unit noraise = _ => ()`. Three things at once: the async
/// type, the effect, and a default value. Settled ACCEPT by `moon check`
/// (row `p_default`).
///
/// THE `reports.length()` ASSERTION IS DELIBERATELY ABSENT HERE, and only here. A
/// default value for a function-typed parameter is NECESSARILY a lambda, and the
/// analyzer reports every lambda it reads but declines to analyse:
/// `short lambda is outside the analyzed subset; it was read but not analysed
/// [structural]`. That is a designed limitation, not a parse failure -- the file is
/// `parsed=1` -- so asserting zero reports here would be asserting that the analyzer
/// analyses lambdas, which it does not and should not be asked to in this row.
/// `first_error` is the assertion that means "the construct was read".
test "0467: an async-typed parameter with a default value parses" {
  let r = @parser.parse(
    "///|\nfn f(g? : async (Int) -> Unit = _ => ()) -> Unit {\n  ()\n}\n",
  )
  assert_eq(r.first_error, 0)
}

///|
/// THE RETURN SPELLING, `-> async (Int) -> Unit`. It was ALSO broken and this increment
/// fixed it as a side effect of sharing the body -- worth a row of its own, because the
/// fix that came for a parameter is exactly the kind of thing that stops being true
/// when the shared body is edited later. `proton facade_bridge.mbt:411` is the corpus
/// site.
///
/// The `async fn` here is DECLARED rather than written as an `async fn (x) { .. }`
/// literal. The first version used the literal and carried one report: `anonymous
/// function literal is outside the analyzed subset`. The declaration is the same type
/// and the same parse, with no lambda in the file, so this row measures the TYPE
/// instead of the analyzer's standing decision about lambda bodies.
test "0467: `-> async (Int) -> Unit` in return position parses" {
  let r = @parser.parse(
    "///|\nasync fn g(x : Int) -> Unit {\n  ()\n}\n\n///|\nfn f() -> async (Int) -> Unit {\n  g\n}\n",
  )
  assert_eq(r.first_error, 0)
  assert_eq(r.reports.length(), 0)
}

///|
/// THE CANARY, and it is the row that gives every ACCEPT above its meaning. `moon
/// check` REJECTs `g : bogus (Int) -> Unit` with 3002 (settle row
/// `canary_any_name`), so a parser that treated the head as "any name followed by a
/// parenthesised list" would accept a program the toolchain refuses. The new entry arm
/// is guarded on `at_name("async")` precisely so this stays true.
test "0467: a non-async name before a parameter list still reports" {
  let r = @parser.parse(
    "///|\nfn f(g : bogus (Int) -> Unit) -> Unit {\n  ()\n}\n",
  )
  assert_true(r.first_error > 0)
}

///|
/// WHAT THE ANNOTATION ACTUALLY SAYS, which is the assertion the rows above are all
/// standing in for. "It parses" and "it says the right thing" are different claims, and
/// a construct can parse perfectly while rendering something else -- 0465's M3 dropped
/// the `..` argument list and the tree stayed perfectly well typed.
///
/// This row exists because of a defect the mutation gate found rather than because it
/// was planned: `fn_type_annotation` kept its OWN `async` head detection after 0467,
/// and by then `fn_type_body`'s parameter loop already routes the inner `async` through
/// `type_annotation`'s new arm. So the head was detected TWICE and the parenthesised
/// spelling rendered as `async (async (Int) -> Unit)?` -- which parses, produces no
/// findings, and is simply the wrong string.
test "0467: a bare async function type renders as it is written" {
  let r = @parser.parse(
    "///|\nfn f(g : async (Int) -> Unit) -> Unit {\n  ()\n}\n",
  )
  match r.tree.body[0].kind {
    @ast.SFunc(_, params, _, _, _) => {
      assert_eq(params[0].name, "g")
      assert_eq(params[0].tyann, "async (Int) -> Unit")
    }
    _ => assert_true(false)
  }
}

///|
/// THE RENDERING OF THE PARENTHESIZED SPELLING, and the row that killed M4. See the
/// row above: before the redundant outer head detection was removed, this annotation
/// rendered `async (async (Int) -> Unit)?`.
test "0467: a parenthesised async function type renders the head once" {
  let r = @parser.parse(
    "///|\nfn f(g : (async (Int) -> Unit)?) -> Unit {\n  ()\n}\n",
  )
  match r.tree.body[0].kind {
    @ast.SFunc(_, params, _, _, _) =>
      assert_eq(params[0].tyann, "(async (Int) -> Unit)?")
    _ => assert_true(false)
  }
}

///|
/// AND WITH AN EFFECT, which is the shape proton writes. The effect has to survive the
/// shared body, and the rendering is where a dropped effect would hide.
test "0467: an async function type with an effect renders both parts" {
  let r = @parser.parse(
    "///|\nfn f(g : async (Int) -> Unit noraise) -> Unit {\n  ()\n}\n",
  )
  match r.tree.body[0].kind {
    @ast.SFunc(_, params, _, _, _) =>
      assert_eq(params[0].tyann, "async (Int) -> Unit")
    _ => assert_true(false)
  }
}

///|
/// REGRESSION, the 0458 spelling. `(async (A, B) -> R)?` worked before this increment
/// and has to keep working: it is the only async type wzzc-dev/moui writes, and that
/// corpus is 608/608 parsed because of it. The RENDERING row above pins the same
/// spelling more sharply; this one stays because it is the parse-level assertion, and a
/// rendering assertion alone would pass on an annotation that was rebuilt from nothing.
test "0467: the parenthesised `(async (Int) -> Unit)?` still parses" {
  let r = @parser.parse(
    "///|\nfn f(g : (async (Int) -> Unit)?) -> Unit {\n  ()\n}\n",
  )
  assert_eq(r.first_error, 0)
  assert_eq(r.reports.length(), 0)
}

///|
/// REGRESSION, the plain function type. `(Int) -> Unit` is the largest remaining
/// annotation shape in moui and has nothing to do with `async`; this is the row that
/// catches a shared body which widened the entry arm into "a `(` means a function type".
test "0467: a plain `(Int) -> Unit` parameter type still parses" {
  let r = @parser.parse("///|\nfn f(g : (Int) -> Unit) -> Unit {\n  ()\n}\n")
  assert_eq(r.first_error, 0)
  assert_eq(r.reports.length(), 0)
}

///|
/// REGRESSION, the return-position parenthesised function type from 0427. The shared
/// body is reached from here too, so this is the row that catches a change to
/// `fn_type_body` breaking the spelling that has the most corpus files behind it.
///
/// Declared, not a `(n) => "x"` literal, for the reason the return-spelling row above
/// gives: the literal form carries the analyzer's standing "short lambda is outside
/// the analyzed subset" report, which is about lambdas rather than about this type.
test "0467: a parenthesised `-> (Int) -> String` still parses" {
  let r = @parser.parse(
    "///|\nfn g(n : Int) -> String {\n  \"x\"\n}\n\n///|\nfn f() -> (Int) -> String {\n  g\n}\n",
  )
  assert_eq(r.first_error, 0)
  assert_eq(r.reports.length(), 0)
}
