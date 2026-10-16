//| Tests for 0.4.30: the pipe operators, and `errdefer`.
//|
//| TWO INCREMENTS, and the second one is only here because of the first.
//!
//! 0464 THE PIPE. Ranking async's PARTIAL files by their FIRST blocker -- not by
//! the scanner's grouped message tally, which covers several constructs under one
//! string -- put `<|` on top with 11 files and `|>` with 2. The lexer had `<<`,
//! `<=`, `..<`, `<..` and `>>`; it had no `<|`, so `f <| x` lexed as `f`, `<`,
//! `|`, `x` and the parser reported the `|`. That is the "unexpected token `|`"
//! message -- 22 sites -- which names neither the operator nor the problem.
//!
//! 0464b `errdefer`. This one was NOT in the ranking at all. `src/socket/udp.mbt`
//! was blocked earlier at a `|>` on line 548, so its three `errdefer` lines had
//! never been read; teaching the pipe unblocked the file and they surfaced as
//! `undefined name 'errdefer'`. `actionable` went 0 -> 3 against code `moon check`
//! compiles.
//!
//! => 判据: a false positive nobody can reach is not a false positive that does not
//! exist. It is a finding whose file has not been read yet, and the only way to
//! tell the two apart is to unblock the corpus and look. The reachability here was
//! legitimate, so the GAP it uncovered is fixed -- giving the reach back would
//! mean refusing to read correct code.

///|
/// AND THE PARSER HALF: the corpus shape, which is the one that actually blocked.
/// A call piped into a LAMBDA. `Promise::from_async(abort_signal~) <| () => { .. }`
/// is `src/js_async/readable_stream.mbt:167` and 10 of its 11 files.
///
/// The lambda's BODY is deliberately not analysed -- every lambda site in this
/// parser skips its body, because the parameters are not bound and parsing it
/// would report each of them as undefined. What this row asserts is that the
/// pipe and both of its operands are read, and that nothing is reported.
///
/// The token-level rows live in `src/lexer/lexer_0464_test.mbt`: this package
/// cannot import the lexer, and a test that reaches across a package boundary to
/// assert a token is a test of the wrong thing.
test "0464: the corpus shape -- a call piped into a lambda -- parses" {
  let r = @pipeline.run(
    "///|\nfn make(p : Int) -> Int {\n  p\n}\n\n///|\nfn probe(p : Int) -> Int {\n  make(p) <| () => { 1 }\n}\n",
    "pipe.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "UndefinedName"), 0)
  // ONE ParseError, and it is the lambda notice -- not `ParseError == 0`.
  //
  // A skipped lambda is reported as a structural exclusion, so a fixture that
  // contains one cannot assert zero ParseErrors; this file's 0460 neighbours made
  // exactly that mistake with a suberror declaration and had to be rewritten for
  // the same reason. Asserting the COUNT and then the MESSAGE is what keeps the
  // row honest: a pipe defect that produced some other ParseError would still be
  // caught here rather than hiding behind "there is one".
  assert_eq(count_family(r, "ParseError"), 1)
  let mut saw_lambda_notice = false
  for rep in r.reports {
    if rep.family.name() == "ParseError" && rep.message.contains("short lambda") {
      saw_lambda_notice = true
    }
  }
  assert_true(saw_lambda_notice)
}

///|
/// AND `|>` THE OTHER DIRECTION, which is its mirror and not a synonym:
/// `x |> f` applies `f` to `x`.
test "0464: |> pipes a value into a function" {
  let r = @pipeline.run(
    "///|\nfn make(n : Int) -> Int {\n  n\n}\n\n///|\nfn probe(p : Int) -> Int {\n  p |> make\n}\n",
    "pipe_gt.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "UndefinedName"), 0)
  assert_eq(count_family(r, "ParseError"), 0)
}

///|
/// AND THE PRECEDENCE, which is why the pipe sits at its own tier rather than in
/// the arithmetic ladder. The settle arranged both readings to give different
/// numbers, because a case where they agree settles nothing:
///
///     `2 * 3 |> inc`   ACCEPT   ->  the LEFT operand is `(2 * 3)`
///     `2 |> inc * 3`   REJECT   ->  the RIGHT operand is `inc * 3`
///
/// WHAT THIS ROW ACTUALLY ASSERTS, stated precisely because it is weaker than the
/// row above it suggests: it asserts the program PARSES, not that the tree has
/// the settled shape. Binding the right operand one rung too tightly leaves
/// `2 * 3 |> inc` untouched and still parses -- and mutation M5 in
/// `_verify/mutate_0464.ps1` survives this row for that reason.
///
/// It survives for a property of the TYPE MAP rather than for want of a test:
/// `OpPipe` resolves to `TUnknown`, and an unknown operand makes every binary
/// result `TUnknown` too, so both trees bottom out identically and no lens can
/// tell them apart. The tree does differ; nothing in the pipeline reads it. If the
/// pipe ever gets a known result type, M5 goes red and this row should start
/// asserting the shape it was written for.
test "0464: the pipe binds looser than multiplication on its left" {
  let r = @pipeline.run(
    "///|\nfn inc(n : Int) -> Int {\n  n + 1\n}\n\n///|\nfn probe() -> Int {\n  2 * 3 |> inc\n}\n",
    "pipe_prec.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "ParseError"), 0)
}

///|
/// AND IT IS LEFT-ASSOCIATIVE, so a chain needs no parentheses. The corpus writes
/// these stacked, one per line.
test "0464: a pipe chain is left-associative" {
  let r = @pipeline.run(
    "///|\nfn inc(n : Int) -> Int {\n  n + 1\n}\n\n///|\nfn probe() -> Int {\n  1 |> inc |> inc\n}\n",
    "pipe_chain.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "ParseError"), 0)
}

///|
/// 0464b -- `errdefer` IS A STATEMENT, not an identifier.
///
/// Three of these were reported as `undefined name 'errdefer'` in
/// `async 0.22.4 src/socket/udp.mbt:49,220,265` the moment the pipe unblocked the
/// file. 33 sites across 18 async files and 2 in proton.
test "0464b: errdefer is a statement, not an undefined name" {
  let r = @pipeline.run(
    "///|\nfn probe(io : Int) -> Int {\n  errdefer io\n  1\n}\n",
    "errdefer.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "UndefinedName"), 0)
  assert_eq(count_family(r, "ParseError"), 0)
}

///|
/// AND ITS BLOCK FORM, which is the same grammar `defer` already had. Reading the
/// argument rather than skipping it is deliberate: a skipped action would turn
/// every variable it mentions into a false `FUnusedBinding`, which is the failure
/// this parser has been bitten by before.
test "0464b: errdefer with a block body parses" {
  let r = @pipeline.run(
    "///|\nfn probe(io : Int) -> Int {\n  errdefer {\n    io\n  }\n  1\n}\n",
    "errdefer_block.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "ParseError"), 0)
}

///|
/// AND THE CONTROL: `defer` still works, and `errdefer` did not take its branch.
/// The two are adjacent arms reading the same tokens one name apart, and a branch
/// that matched on a prefix would silently swallow every `defer` in the corpus.
test "0464b: defer is untouched (control)" {
  let r = @pipeline.run(
    "///|\nfn probe(io : Int) -> Int {\n  defer io\n  1\n}\n",
    "defer_ctl.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "UndefinedName"), 0)
  assert_eq(count_family(r, "ParseError"), 0)
}
