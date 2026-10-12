// Tests for the 0.4.21 fixes.
//
// Corpus: wzzc-dev/moui 0.1.12, carried from 0.4.20. Files understood
// 436 -> 481 (71.7% -> 79.1%), withheld 1078 -> 242, unreliable 3025 -> 1711,
// "unexpected token" 163 -> 113, actionable 10 -> 8.
//
//   A  `guard COND else { ... }` was read as an identifier
//   B  a named argument whose value is a lambda ended the argument list
//   C  `is` did not continue an expression across a newline
//   D  an `is` pattern bound only its FIRST name, and only at depth 1
//
// Other corpora, same measurement (0.4.20 -> 0.4.21):
//   moonbit_labeler  parsed 23 -> 24, actionable 3 -> 0
//   async            parsed 206 (flat), actionable 29 -> 17
//   moonbit_image    unchanged (1 parsed)
//   proton           parsed 71 -> 72, actionable 44 -> 45 — the two findings
//                    that disappear are `undefined name 'guard'` in
//                    facade_page.mbt and preferences.mbt, and the three that
//                    appear are all in ONE newly-readable file, main.mbt
//
// Every fixture below is a corpus line, cut to its shape and renamed where a
// name would otherwise be undefined. The sources are cited per test.
//
// One fixture caveat, measured rather than guessed: a function-typed PARAMETER
// that is then CALLED reports `undefined function` — `let f = inc` then `f(1)`
// does it with no lambda anywhere in the file. That is a separate pre-existing
// limitation, so no fixture here calls one; the callee takes the lambda
// parameter and reads a different one.

// ---------------------------------------------------------------------------
// A — `guard COND else { ... }`
// ---------------------------------------------------------------------------

///| THE SHARP ONE. `guard` is not in the lexer's keyword list, so it was read

///| as an ordinary IDENTIFIER and reported as an undefined name — measured on

///| `render/renderer_session.mbt:301`:

///|

///|   guard self.image_decoder is Some(decoder) else { return }

///|

///| The binding is the point. A guard's condition is walked FIRST, so the

///| `is` pattern binds in the current frame exactly where the rest of the

///|
/// block looks for it, and `decoder` below must resolve.
test "0421: guard binds its condition's is-pattern (control)" {
  let r = @pipeline.run(
    "fn f(d : Int?) -> Int {\n  guard d is Some(decoder) else { return 0 }\n  decoder + 1\n}\nlet r = f(Some(1))\n",
    "guard_bind.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "UndefinedName"), 0)
  assert_eq(count_family(r, "UnusedLocal"), 0)
}

// ---------------------------------------------------------------------------

///| THE CONTROL THAT MAKES THE ABOVE SHARP. A guard whose `else` body is

///| analyzed like any other block: `zzz_else` is genuinely undefined, so

///| exactly one UndefinedName must appear. If the guard swallowed the whole

///| statement, this would be 0 — and so would every count in the test above,

///| because a statement that is never analyzed cannot produce a finding. That

///|
/// is exactly how 0.4.18's M1 passed.
test "0421: a guard's else body is still analyzed" {
  let r = @pipeline.run(
    "fn f(d : Int?) -> Int {\n  guard d is Some(decoder) else { zzz_else(decoder) }\n  decoder + 1\n}\nlet r = f(Some(1))\n",
    "guard_else.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "UndefinedName"), 1)
}

// ---------------------------------------------------------------------------

///| The corpus shape with a block `else`, `renderer_session.mbt:204`:

///| `guard self.take_image_request(completion.token()) is Some(source) else {`

///| `return ...Stale }`. The else is a BLOCK here, not a single call, and the

///|
/// name bound in the condition is what the following statements read.
test "0421: a guard with a braced else body parses and binds" {
  let r = @pipeline.run(
    "fn f(t : Int?) -> Int {\n  guard t is Some(source) else {\n    return 0\n  }\n  source + 1\n}\nlet r = f(Some(1))\n",
    "guard_block.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(r.n_parse, 0)
  assert_eq(count_family(r, "UndefinedName"), 0)
  assert_eq(count_family(r, "UnusedLocal"), 0)
}

// ---------------------------------------------------------------------------
// B — a named argument whose value is a lambda
// ---------------------------------------------------------------------------

///| THE SHARP ONE. `core/view_modifier_node.mbt:15` and `:16`:
///

///|   children=node => [node.child],

///|   event=(node, context) => (node.modifier.event)(context),
///

///| The value is a lambda, not a call or a bare name. This is the shape that

///| was most expensive: 79 files stopped being readable when it was fixed,

///| because the argument list was abandoned at the `=>` and everything after

///| was re-read. `n_parse == 0` is the assertion that matters — before the fix

///| the file parsed with NO error into a tree whose every name after that

///| point was wrong, so the file-level counts looked fine while the findings

///| did not.
///

///| The SECOND named argument is the load-bearing part of the fixture: it sits

///| after the lambda, so it resolves only if the token stream stayed in step

///|
/// through the `=>`.
test "0421: a named argument whose value is a lambda parses" {
  let r = @pipeline.run(
    "fn use_it(event : (Int) -> Int, size : Int) -> Int {\n  size\n}\nfn build(node : Int, context : Int) -> Int {\n  use_it(event=(node, context) => node + context, size=node)\n}\nlet r = build(1, 2)\n",
    "named_lambda.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(r.n_parse, 0)
  assert_eq(count_family(r, "UndefinedName"), 0)
}

// ---------------------------------------------------------------------------

///| THE CONTROL, and the one that makes the test above non-vacuous. A lambda

///| head that swallowed the REST of the function body would leave both counts

///| in the test above green — nothing failed, the file just stopped being

///| analyzed. `zzz_after` is undefined and `context` is a real parameter, so

///|
/// exactly one UndefinedName must appear and the parameter must resolve.
test "0421: the statement after a named-argument lambda is still analyzed" {
  let r = @pipeline.run(
    "fn use_it(event : (Int) -> Int) -> Int {\n  1\n}\nfn build(node : Int, context : Int) -> Int {\n  use_it(event=(node, context) => node + context)\n  zzz_after(node) + context\n}\nlet r = build(1, 2)\n",
    "named_lambda_after.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "UndefinedName"), 1)
}

// ---------------------------------------------------------------------------

///| TWO lambdas in one call, plus a third argument after them. Corpus:

///| `Program::new(init=() => ..., update=(model, message) => ..., view~, ...)`

///| at `core/program.mbt:208`. This is the shape that breaks a skipper which

///| stops at the FIRST `=>`: the second lambda has to be recognised as a head

///|
/// too, and then the argument list has to be resumed.
test "0421: two named-argument lambdas in one call parse" {
  let r = @pipeline.run(
    "fn use_it(a : (Int) -> Int, b : (Int) -> Int, size : Int) -> Int {\n  size\n}\nfn build(node : Int, context : Int) -> Int {\n  use_it(a=(x) => x + node, b=(y) => y + context, size=node)\n}\nlet r = build(1, 2)\n",
    "named_lambda_two.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(r.n_parse, 0)
  assert_eq(count_family(r, "UndefinedName"), 0)
}

// ---------------------------------------------------------------------------

///| The single bare-name form, `children=node => [node.child]` at

///| `core/view_modifier_node.mbt:15` and `view=_model => abort(...)` at

///| `core/program_command_test.mbt:20`. One bare name is a DIFFERENT token shape

///| from `(node, context)` and a different arm of `at_lambda_head`, so it needs

///|
/// its own fixture.
test "0421: a single-parameter named-argument lambda parses" {
  let r = @pipeline.run(
    "fn build(children : (Int) -> Array[Int], size : Int) -> Int {\n  size\n}\nfn build2(node : Int) -> Int {\n  build(children=_node => [node], size=node)\n}\nlet r = build2(1)\n",
    "named_lambda_one.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(r.n_parse, 0)
  assert_eq(count_family(r, "UndefinedName"), 0)
}

// ---------------------------------------------------------------------------

///| The TYPED parameter, `(node : Int) => ...` — the third arm of

///| `at_lambda_head`, which has to consume a whole TYPE ANNOTATION between the

///| name and the `=>`. Without that arm the scanner meets the annotation's `:`

///| and gives up on the head, so the lambda is read as a call and the rest of

///|
/// the argument list is re-read.
test "0421: a typed-parameter named-argument lambda parses" {
  let r = @pipeline.run(
    "fn use_it(event : (Int) -> Int, size : Int) -> Int {\n  size\n}\nfn build(node : Int, context : Int) -> Int {\n  use_it(event=(node : Int) => node + context, size=node)\n}\nlet r = build(1, 2)\n",
    "named_lambda_typed.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(r.n_parse, 0)
  assert_eq(count_family(r, "UndefinedName"), 0)
}

// ---------------------------------------------------------------------------
// C — `is` continues an expression across a newline
// ---------------------------------------------------------------------------

///| THE SHARP ONE, and the nastiest failure mode in this project. Corpus,

///| `backend/common/embedded/embedded_runtime_backend.mbt:227`:
///

///|   guard (self.frame, self.image, self.host_bridge)

///|     is (Some(frame_state), Some(image_state), Some(host_bridge)) &&

///|     !self.disposed else {

///|

///| Before the fix the line break ended the expression, `is` was read as an

///| ordinary identifier, and the file parsed WITHOUT an error into a tree in

///| which every name after that point was wrong — 15 findings, none of them

///| reported as unreliable because nothing had failed. So `n_parse == 0` alone

///| proves nothing here; the assertion that carries weight is that the names

///|
/// AFTER the continuation resolve.
test "0421: is continues an expression across a newline" {
  let r = @pipeline.run(
    "fn f(a : Int?, b : Int?, disposed : Bool) -> Int {\n  guard (a, b)\n    is (Some(frame_state), Some(image_state)) &&\n    !disposed else {\n    return 0\n  }\n  frame_state + image_state\n}\nlet r = f(Some(1), Some(2), false)\n",
    "is_newline.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "UndefinedName"), 0)
  assert_eq(count_family(r, "UnusedLocal"), 0)
}

// ---------------------------------------------------------------------------

///| THE CONTROL, and the one that is easy to get wrong in the dangerous

///| direction. Only `TNewline` is skipped at the continuation, NOT `skip_seps`,

///| because that also eats `;` and a semicolon is STRUCTURAL in a C-style `for`.

///|
/// Using `skip_seps` here broke this test when it was written.
test "0421: a C-style for loop with semicolons still parses (control)" {
  let r = @pipeline.run(
    "fn f() -> Int {\n  let mut total = 0\n  for i = 0; i < 3; i = i + 1 {\n    total = total + i\n  }\n  total\n}\nlet r = f\n",
    "cfor.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(r.n_parse, 0)
  assert_eq(count_family(r, "UndefinedName"), 0)
}

// ---------------------------------------------------------------------------

///| And the semicolon clauses must still be ANALYZED, not merely consumed: the

///| `n_parse == 0` above is green either way, because a swallowed for-loop does

///| not fail. `zzz_in_for` is undefined, so exactly one UndefinedName must be

///|
/// reported from inside the loop body.
test "0421: a C-style for body is still analyzed (control)" {
  let r = @pipeline.run(
    "fn f() -> Int {\n  let mut total = 0\n  for i = 0; i < 3; i = i + 1 {\n    total = total + zzz_in_for(i)\n  }\n  total\n}\nlet r = f\n",
    "cfor_body.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "UndefinedName"), 1)
}

// ---------------------------------------------------------------------------
// D — an `is` pattern binds every name, at every depth
// ---------------------------------------------------------------------------

///| THE SHARP ONE for this cycle's headline change. Corpus,

///| `embedded_runtime_backend.mbt:228`:
///

///|   is (Some(frame_state), Some(image_state), Some(host_bridge)) &&
///

///| A tuple pattern introduced THREE bindings. `parse_is_pattern` returned a

///| single `String` and the tuple branch returned only the first name it found,

///| so `image_state` and `host_bridge` were dropped: each reported as an

///| undefined name at its use, and the first binding reported as unused

///| because the statement it belonged to had desynchronised. `EIs` now carries

///|
/// `Array[String]` and every consumer binds each element.
test "0421: an is-tuple-pattern binds every name in the group" {
  let r = @pipeline.run(
    "fn f(a : Int?, b : Int?, c : Int?) -> Int {\n  if (a, b, c) is (Some(frame_state), Some(image_state), Some(host_bridge)) {\n    frame_state + image_state + host_bridge\n  } else {\n    0\n  }\n}\nlet r = f(Some(1), Some(2), Some(3))\n",
    "is_tuple3.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "UndefinedName"), 0)
  assert_eq(count_family(r, "UnusedLocal"), 0)
}

// ---------------------------------------------------------------------------

///| The finding that was actually on the corpus file, with the `guard` and the

///| newline continuation from sections A and C composed on top. The corpus had

///|
/// 7 UndefinedName here; this fixture is the shape that produced them.
test "0421: the corpus guard + newline + tuple shape is clean" {
  let r = @pipeline.run(
    "fn f(triple : (Int?, Int?, Int?), disposed : Bool) -> Int {\n  guard triple.0\n    is (Some(frame_state), Some(image_state), Some(host_bridge)) &&\n    !disposed else {\n    return 0\n  }\n  frame_state + image_state + host_bridge\n}\nlet r = f((Some(1), Some(2), Some(3)), false)\n",
    "is_tuple_guard.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "UndefinedName"), 0)
  assert_eq(count_family(r, "UnusedLocal"), 0)
}

// ---------------------------------------------------------------------------

///| THE DEPTH-2 SHAPE, which was a second bug hiding behind the first.

///| `guard ... is Some(Os(error))` at `moui .../macos/event_loop_wbtest.mbt:6`

///| and `.../session_transport.mbt:375`, settled against `moon check`: the

///| pattern binds `error` and `error + 1` is accepted MoonBit. The old reader

///| only looked at depth 1, so `Os` was read as the binding name, `error` fell

///|
/// through, and every use of it reported `undefined variable`.
test "0421: an is-pattern binds a name nested one constructor deep" {
  let r = @pipeline.run(
    "fn f(a : Int?) -> Int {\n  if a is Some(Os(error)) {\n    error + 1\n  } else {\n    0\n  }\n}\nlet r = f(Some(1))\n",
    "is_depth2.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "UndefinedName"), 0)
  assert_eq(count_family(r, "UnusedLocal"), 0)
}

// ---------------------------------------------------------------------------

///| Depth 3, `is Some(DragLeft(Some(event_position)))` at

///| `.../macos/event_wbtest.mbt:25`, also settled against `moon check`. Both

///| nested constructors are followed by `(` and so bind nothing; only the

///| innermost bare name binds. If the reader treated `Some` or `DragLeft` as a

///|
/// binding it would invent two locals and report them unused.
test "0421: an is-pattern binds a name nested two constructors deep" {
  let r = @pipeline.run(
    "fn f(a : Int?) -> Int {\n  if a is Some(DragLeft(Some(event_position))) {\n    event_position + 1\n  } else {\n    0\n  }\n}\nlet r = f(Some(1))\n",
    "is_depth3.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "UndefinedName"), 0)
  assert_eq(count_family(r, "UnusedLocal"), 0)
}

// ---------------------------------------------------------------------------

///| THE CONTROL on the qualified-path rule, and it is the direction that could

///| have made things WORSE: removing the depth restriction means every segment

///| of `@core.Role::Checkbox` now passes the "not followed by `(`" test, and

///| binding them would report three unused locals where one was reported

///| before. `@` is a name sigil and `::` is two `TColon` tokens, so a segment

///| is recognised by its `.` neighbours and by the first `:` ending the

///|
/// collection. Eighteen such patterns exist in the corpus.
test "0421: a qualified path in a pattern binds nothing (control)" {
  let r = @pipeline.run(
    "fn f(info : Int?) -> Int {\n  if info is Some(@core.Role::Checkbox) {\n    1\n  } else {\n    0\n  }\n}\nlet r = f(Some(1))\n",
    "is_qualified.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "UnusedLocal"), 0)
  assert_eq(count_family(r, "UndefinedName"), 0)
}

// ---------------------------------------------------------------------------

///| THE CONTROL that a pattern that binds nothing still binds nothing:

///| `Some(_)` and a bare `Some(true)` introduce no name, so `_` must not be

///| reported undefined and `true` must not be invented as a local. The keyword

///| arm is pinned from 0.4.19; the underscore arm is what the multi-binding

///|
/// loop could plausibly have broken.
test "0421: an is-pattern binds nothing for _ and literals (control)" {
  let r = @pipeline.run(
    "fn f(a : Int?, b : Bool?) -> Int {\n  if (a, b) is (Some(_), Some(true)) {\n    1\n  } else {\n    0\n  }\n}\nlet r = f(Some(1), Some(true))\n",
    "is_tuple_nobind.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "UndefinedName"), 0)
  assert_eq(count_family(r, "UnusedLocal"), 0)
}

// ---------------------------------------------------------------------------

///| `Some(Some(x))` with no payload in between: only `x` binds, and `x` is

///| used. This is the simplest form of the nested case and the one a reader

///|
/// that stopped at the first name would fail.
test "0421: a nested constructor with no payload binds only the inner name" {
  let r = @pipeline.run(
    "fn f(a : (Int, Int)?) -> Int {\n  if a is Some(Some(x)) {\n    x + 1\n  } else {\n    0\n  }\n}\nlet r = f(Some((1, 2)))\n",
    "is_nested.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "UndefinedName"), 0)
  assert_eq(count_family(r, "UnusedLocal"), 0)
}

// ---------------------------------------------------------------------------

///| THE OR-PATTERN CONTROL, and the one that caught a regression inside this

///| very change. `proton internal/bridge_admission_test/main.mbt:93` is

///|

///|   runtime.prepare_bridge_request(request, window) is (Gone | PageUnavailable)
///

///| That `(` is a GROUPING paren around an or-pattern, not a tuple payload, so

///| `Gone` and `PageUnavailable` are CONSTRUCTORS and bind nothing. Reading

///| them as bindings reported two unused locals that do not exist — and one of

///| the two is newly introduced, because the old reader stopped after the

///| first name and so only ever bound `Gone`. The tuple branch therefore

///|
/// collects at `depth >= 2`, where a real tuple's bindings live (`Some(a)`).
test "0421: an or-pattern's constructors bind nothing (control)" {
  let r = @pipeline.run(
    "fn f(state : Int) -> Int {\n  if state is (Gone | PageUnavailable) {\n    1\n  } else {\n    0\n  }\n}\nlet r = f(1)\n",
    "is_or.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "UnusedLocal"), 0)
  assert_eq(count_family(r, "UndefinedName"), 0)
}
