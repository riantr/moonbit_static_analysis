// Tests for the 0.4.23 fix: the `raise` effect annotation on a function
// signature.
//
// Corpus: wzzc-dev/moui 0.1.12. 149 of its 608 files carry `-> T raise E` or
// the short `-> T!`, and before this change EVERY ONE of them failed to parse
// at all -- not partially, completely -- because the parser met the `raise`
// token, did not recognise it, and reported "expected '{'" at the body. That is
// 24.5% of the corpus, and it is the single largest parse blocker found so far.
//
// Settled against `moon check` on 0.1.20261012 before anything was written.
// All three forms are valid:
//
//     fn f(b : Bool) -> String raise { ... }        bare, no error type named
//     fn f(b : Bool) -> String raise IntError { ... } named
//     fn f(b : Bool) -> String! { ... }              short form
//
// `moonbitlang/core/error/error_test.mbt` uses the bare form, which is why the
// bare case is a corpus-shaped fixture rather than a shape invented here.
//
// The effect TYPE is deliberately not recorded. Nothing in walk / types /
// infer / interp reads one, and adding a field to `SFunc` for a check that does
// not exist would ripple through all four plus the `.mbti`. Consuming the clause
// is what makes a file readable; storing it is a separate decision.
//
// So the assertions here are about PARSING, not about effects: the type lens
// still infers `-> None` for `fn bare(b : Bool) -> String raise`, because
// `String` is read as the return annotation and the effect contributes nothing.
// Pinning that here is what stops a future change from silently starting to
// claim it understands error effects.

// ---------------------------------------------------------------------------
// A — the three forms parse, and the rest of the file is analysed
// ---------------------------------------------------------------------------

///| THE SHARP ONE, and the shape the corpus is full of. `moonbit_image

///| bmp.mbt:26` reads

///|

///|   pub fn decode_bmp(data : Bytes) -> Image raise Failure {
///

///| and produced `expected '{'` there. Before the fix this fixture reported a

///| ParseError and nothing else -- the function body was never read, so the

///|
/// names inside it were invisible.
test "0423: a named raise effect parses and the body is analysed" {
  let r = @pipeline.run(
    "fn f(b : Bool) -> Int raise IntError {\n  if b {\n    1\n  } else {\n    0\n  }\n}\nlet x = f(true)\n",
    "raise_named.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(r.n_parse, 0)
  assert_eq(count_family(r, "ParseError"), 0)
}

///| AND THE CONTROL THAT MAKES THE ABOVE NON-VACUOUS: the body really is

///| analysed, so a name inside it that does not exist must be reported. Without

///| this, "zero ParseErrors" would also be what a parser produces when it stops

///| at the signature and analyses nothing -- which is precisely the old

///|
/// behaviour.
test "0423: the body after a raise effect is still analysed (control)" {
  let r = @pipeline.run(
    "fn f(b : Bool) -> Int raise IntError {\n  if b {\n    1\n  } else {\n    0\n  }\n  zzz_inside(f)\n}\nlet x = f(true)\n",
    "raise_named_body.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "ParseError"), 0)
  assert_eq(count_family(r, "UndefinedName"), 1)
}

// ---------------------------------------------------------------------------

///| THE BARE FORM, which is the one the toolchain's own source uses

///| (`core/error/error_test.mbt`: `fn f(b : Bool) -> String raise {`). It is

///| the easy one to get wrong in the other direction: the reader must NOT go on

///| to parse a type annotation here, because the next token is the body's `{`

///|
/// and consuming it would swallow the whole block.
test "0423: a bare raise effect parses and leaves the body brace alone" {
  let r = @pipeline.run(
    "fn f(b : Bool) -> String raise {\n  if b {\n    \"ok\"\n  } else {\n    \"no\"\n  }\n}\nlet x = f(true)\n",
    "raise_bare.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(r.n_parse, 0)
  assert_eq(count_family(r, "ParseError"), 0)
  assert_eq(count_family(r, "UndefinedName"), 0)
}

// ---------------------------------------------------------------------------

///| THE SHORT FORM, `-> T!`. This one is subtle for a reason that is not

///| obvious from the syntax: `!` is ALSO the boolean NOT operator, and the

///| lexer produces the same `TBang` token for both. Only position tells them

///| apart -- this runs immediately after a return annotation, never where an

///| operand is expected. A reader that scanned for `TBang` anywhere would

///|
/// misread every `!x` in the corpus.
test "0423: the short raise form parses, and ! still negates" {
  let r = @pipeline.run(
    "fn f(b : Bool) -> Int! {\n  if b {\n    1\n  } else {\n    0\n  }\n}\nlet y = !true\nlet x = f(y)\n",
    "raise_short.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(r.n_parse, 0)
  assert_eq(count_family(r, "ParseError"), 0)
}

// ---------------------------------------------------------------------------

///| THE CONTROL ON THE `!` AMBIGUITY, as its own test. `!` used as the NOT

///| operator must not be swallowed as a raise effect. This is what would break

///|
/// first if the clause were detected by token rather than by position.
test "0423: ! as the NOT operator is not read as a raise effect (control)" {
  let r = @pipeline.run(
    "fn g(b : Bool) -> Bool {\n  !b\n}\nlet v = g(true)\n",
    "bang_not.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(r.n_parse, 0)
  assert_eq(count_family(r, "ParseError"), 0)
}

// ---------------------------------------------------------------------------
// B — all three forms together, plus a no-effect control
// ---------------------------------------------------------------------------

///| THE WHOLE FIX IN ONE FIXTURE, which is the shape the 0.4.23 gate asserts

///| on. All three forms plus a control with no effect at all, each called, so

///| a parse failure in any one of them would desynchronise the rest and show up

///| as a non-zero count.
///

///|

///| The four `let` bindings also give the test something to check besides parse

///| errors: all four functions must be visible as inferred signatures. Before

///|
/// the fix, the first `raise` stopped the file and none of the four existed.
test "0423: all three raise forms parse alongside a no-effect control" {
  let r = @pipeline.run(
    "suberror IntError {\n  IntError(Int)\n}\nfn bare(b : Bool) -> String raise {\n  \"ok\"\n}\nfn named(b : Bool) -> String raise IntError {\n  \"ok\"\n}\nfn short(b : Bool) -> String! {\n  \"ok\"\n}\nfn plain(b : Bool) -> String {\n  \"ok\"\n}\nlet r1 = bare(true)\nlet r2 = named(true)\nlet r3 = short(true)\nlet r4 = plain(true)\n",
    "raise_all.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "ParseError"), 1) // the `suberror` declaration only
  let names = ["bare", "named", "short", "plain"]
  for n in names {
    assert_true(r.sigs.iter().any(fn(s) { (s : String).has_prefix(n + "(") }))
  }
}

// ---------------------------------------------------------------------------

///| THE NAMED EFFECT TYPE IS CONSUMED, NOT MISREAD AS PART OF THE RETURN

///| ANNOTATION. `-> Int raise IntError` must leave the return type as `Int`;

///| if the reader ran on past `raise` and swallowed `IntError` as part of the

///| type, the signature would come out differently and the body would be

///| entered at the wrong offset. Asserted on the rendered signature so the test

///| fails on the value, not on a count.
///

///| `IntError` is deliberately chosen to start with `Int`: it is the trap case.

///| If the effect type were taken as the return type the rendering would be

///| `IntError`, not `Int`, so the equality below actually discriminates.
///

///| The body uses an explicit `return`. That is a control, not a stylistic

///| choice: a tail-expression body renders the return type as `None` today

///| (`fn f() -> Int { 1 }` yields `f() -> None` with or without `raise`), so a

///| tail body would make this assertion fail for a reason that has nothing to

///| do with the effect annotation. That defect is tracked separately; pinning

///|
/// it here would only re-test it on every release.
test "0423: the effect type does not leak into the return annotation" {
  let r = @pipeline.run(
    "fn f() -> Int raise IntError {\n  return 1\n}\nlet x = f()\n",
    "raise_leak.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "ParseError"), 0)
  assert_eq(r.sigs.length(), 1)
  assert_eq(r.sigs[0], "f() -> int")
}

// ---------------------------------------------------------------------------
// C — the same clause in TYPE position: a function type may carry its own
//     raise effect. Same rule, same reader; reading it in signature position
//     only leaves a program that dies on the next callback-typed parameter.
// ---------------------------------------------------------------------------

///| A FUNCTION TYPE CARRIES THE CLAUSE TOO. All three forms again, but in type

///| position, which is a different call site inside the parser (`fn_type_annotation`

///| rather than `parse_fn_signature`) reached from a parameter annotation.
///

///| Measured cost of leaving this out: `() -> ... raise` appears in 29 files of

///| wzzc-dev/moui 0.1.12 and 33 of moonbit-community. Each of those reported

///| `expected ')'` and lost the rest of the file.
///

///|
/// Settled valid, all with zero errors from `moon check` on 0.1.20261012.
test "0423: a function type carries the raise clause in type position" {
  let r = @pipeline.run(
    "suberror E {\n  E(Int)\n}\nfn bare(g : () -> Int raise) -> Int {\n  return 1\n}\nfn named(g : () -> Int raise E) -> Int {\n  return 2\n}\nfn short(g : () -> Int!) -> Int {\n  return 3\n}\n",
    "fnptr_raise.mbt",
    @core.IfaceSymTab::empty(),
  )
  // only the `suberror` declaration, which is outside the analyzed subset
  assert_eq(count_family(r, "ParseError"), 1)
  // all three functions must exist: before this they desynchronised at the first
  // one and the other two were never parsed at all
  for n in ["bare", "named", "short"] {
    assert_true(r.sigs.iter().any(fn(s) { (s : String).has_prefix(n + "(") }))
  }
}

///| THE OPTIONAL AND COMMA CONTROLS, together, because both are places a bare

///| `raise` in type position can swallow a token that does not belong to it.

///|

///| `(() -> Int raise)?` puts a `)` then a `?` after the clause, and

///| `(g : () -> Int raise, h : Int)` puts a `)` then a `,`. If the reader treats

///| either of those as the start of an error type it consumes the rest of the

///| parameter list and the signature is read wrong -- a SILENT misparse, which

///| is why this is a test rather than a code comment.
///

///|
/// Settled valid, zero errors from `moon check`.
test "0423: a bare raise in type position stops before ) and ," {
  let r = @pipeline.run(
    "suberror E {\n  E(Int)\n}\nfn opt(g : (() -> Int raise)?, h : Int) -> Int {\n  return h\n}\n",
    "fnptr_raise_stop.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "ParseError"), 1)
  // The rendered signature carries BOTH parameters. If `,` were eaten as an
  // error type, `h` would vanish and this would read `opt(Any) -> int`.
  assert_eq(r.sigs.length(), 1)
  assert_eq(r.sigs[0], "opt(Any, int) -> int")
}

///| AN INDEXED EFFECT TYPE, `raise E[Int]`. Settled valid, zero errors.

///|

///| This is the only thing that can see `skip_indexed()`: without it the `[Int]`

///|
/// is left at the cursor and the reader then reports `expected '{'` at the body.
test "0423: an indexed effect type is consumed whole" {
  let r = @pipeline.run(
    "suberror E {\n  E(Int)\n}\nfn f() -> Int raise E[Int] {\n  return 1\n}\nlet x = f()\n",
    "raise_indexed.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "ParseError"), 1)
  assert_eq(r.sigs.length(), 1)
  assert_eq(r.sigs[0], "f() -> int")
}

///| THE CONTROL FOR THE CLAUSE ITSELF IN TYPE POSITION: a function type with

///| no effect at all must be read exactly as it was before this change. Without

///| this, a reader that consumed too much in the raise case could still be

///|
/// wrong here and the two would cancel out in the tests above.
test "0423: a function type with no effect is unaffected (control)" {
  let r = @pipeline.run(
    "fn plain(g : () -> Int) -> Int {\n  return 1\n}\nfn optp(g : (() -> Int)?) -> Int {\n  return 2\n}\n",
    "fnptr_control.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "ParseError"), 0)
  assert_eq(r.sigs.length(), 2)
}

// ---------------------------------------------------------------------------
// D — a second, separate defect fixed in the same release: `guard!`
// ---------------------------------------------------------------------------

///| `guard!` IS `guard`, WITH A BANG, and the lexer does not join them.
///

///| `parse_guard` bumped the name `guard` and went straight to the condition, so

///| the `!` fell through to the expression reader and became a boolean NOT

///| applied to the condition. That is a false positive stated confidently:

///| `moonbitlang/async` 0.22.4 `src/internal/fd_util/pipe.mbt:31` reads

///| `guard! fds is [r, w]` and was reported as

///| "operand of '!' must be bool, got '[int]'".
///

///| This surfaced only once the clause above made those files readable, which is

///| worth stating plainly: the defect was always there, the raise fix merely

///|
/// stopped hiding it.
test "0423: guard! is read as guard, not as NOT applied to the condition" {
  let r = @pipeline.run(
    "fn pipe(fds : Array[Int]) -> Int {\n  guard! fds is [r, _]\n  return r\n}\nlet x = pipe([1, 2])\n",
    "guard_bang.mbt",
    @core.IfaceSymTab::empty(),
  )
  // The whole point: NOT one OperatorMismatch. Before the fix this reports
  // "operand of '!' must be bool, got '[int]'".
  assert_eq(count_family(r, "OperatorMismatch"), 0)
  assert_eq(count_family(r, "ParseError"), 0)
}

///| THE BARE `guard` CONTROL, because the fix must not have cost the sibling

///| form anything: `guard cond else { ... }` still parses, and the `else` block

///| is still read. Settled: both forms are valid MoonBit and appear throughout

///|
/// moonbitlang/async.
test "0423: bare guard still parses and still reads its else block (control)" {
  let r = @pipeline.run(
    "fn f(n : Int) -> Int {\n  guard n > 0 else { return 0 }\n  return n\n}\nlet x = f(1)\n",
    "guard_bare.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "ParseError"), 0)
  assert_eq(r.sigs.length(), 1)
  assert_eq(r.sigs[0], "f(int) -> int")
}

///| `!` AS AN ACTUAL NOT OPERATOR, still one. The third user of the `TBang`

///| token in one file: the raise short form, the guard bang, and real boolean

///| negation. If any of the three were dispatched by scanning for the token

///|
/// instead of by position, this is the fixture that would break.
test "0423: ! is still the boolean NOT operator (control)" {
  let r = @pipeline.run(
    "fn g(b : Bool) -> Bool {\n  !b\n}\nlet v = g(true)\n",
    "bang_not_control.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "OperatorMismatch"), 0)
  assert_eq(count_family(r, "ParseError"), 0)
}
