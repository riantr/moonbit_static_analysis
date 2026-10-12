// Tests for the 0.4.24 fix: `raise` as an EXPRESSION.
//
// This is the THIRD position the `raise` clause appears in, after the signature
// annotation (0.4.23) and a function type's return annotation (also 0.4.23).
// The other two were the annotation ON A FUNCTION; this one is the statement
// that actually performs the raising.
//
// Measured cost of not having it, and this is the number that redirected the
// work: the 0.4.23 scan was asked to classify every `UndefinedName` in the six
// corpora, on the theory that the noise was enum/suberror/derive constructors
// being outside the analyzed subset. That theory was wrong about which bucket
// was biggest. Of roughly 70 `UndefinedName` findings, **65 were the literal
// name `raise`** -- 56 in moonbit-community/proton 0.3.4 alone. The
// constructor names were a real but small tail (7 or so).
//
// `raise` was read as an ordinary identifier and the error constructor as a
// call on it, so every raise statement reported `undefined name 'raise'` --
// a confident false positive about code that compiles. The construct itself:
// 585 sites across 54 files of proton, 427 / 90 of async, 180 / 16 of
// moonbit_image, 15 / 9 of moonbit_labeler, 6 / 1 of proton_contract.
//
// Settled against `moon check` on 0.1.20261012, all zero errors: the bare
// form, the payload form, the form inside a `guard ... else` block, the form as
// a tail expression, and the form under a `-> T!` signature.
//
// `SRaise` rather than `SReturn` because three lenses read a return wrongly
// here -- infer would join the error CONSTRUCTOR's type into what the function
// returns, interp would push a value `raise` never produces. See the node's own
// doc comment.

// ---------------------------------------------------------------------------
// A — the sharp one: the name `raise` is not a variable
// ---------------------------------------------------------------------------

///| Count findings whose MESSAGE names a given identifier. `count_family` is

///| the wrong tool here on purpose: every one of these findings is family

///| `UndefinedName`, so a family count cannot tell "no undefined `raise`" from

///| "no undefined names at all", and the second would still pass if the fix had

///|
/// simply suppressed the lens.
fn count_named(r : @pipeline.PipelineResult, ident : String) -> Int32 {
  let mut n = 0
  let needle = "'" + ident + "'"
  for rep in r.reports {
    if rep.family.name() == "UndefinedName" && rep.message.contains(needle) {
      n += 1
    }
  }
  n
}

///| THE CORPUS SHAPE. `moonbit-community/proton` 0.3.4

///| `facade_app_metadata.mbt:82` reads

///|

///|     guard config.package_config() is Some(package_config) else {

///|       raise MissingPackageMetadata

///|     }

///|

///| and the finding was `undefined name 'raise'` at 82:5.
///

///| The assertion is on the NAME, not on the count, because the error

///| constructor beside it is reported by a different mechanism (a suberror

///| declaration outside the subset) and this test has no business pinning

///| that. `suberror` is declared so the fixture is well-formed MoonBit; its

///|
/// one ParseError notice is accounted for exactly.
test "0424: raise as a statement is not an undefined name" {
  let r = @pipeline.run(
    "suberror E {\n  E(Int)\n}\nfn f(g : Int?) -> Int raise E {\n  guard g is Some(v) else {\n    raise E(0)\n  }\n  return v\n}\nlet x = f(1)\n",
    "raise_stmt.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_named(r, "undefined name 'raise'"), 0)
}

///| The corpus is not one shape. All five settled forms in one file, so a

///| regression in any one of them desynchronises the rest and shows up as a

///|
/// non-zero count rather than as a silently missing function.
test "0424: every settled raise-expression form parses" {
  let r = @pipeline.run(
    "suberror E {\n  E(Int)\n}\nfn bare() -> Int raise E {\n  raise E\n  return 1\n}\nfn payload(n : Int) -> Int raise E {\n  raise E(n)\n  return 2\n}\nfn bangs(n : Int) -> Int! {\n  raise E(n)\n  return 3\n}\nfn tailed(n : Int) -> Int raise E {\n  if n > 0 {\n    raise E(n)\n  }\n  return 4\n}\n",
    "raise_forms.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_named(r, "undefined name 'raise'"), 0)
  for n in ["bare", "payload", "bangs", "tailed"] {
    assert_true(r.sigs.iter().any(fn(s) { (s : String).has_prefix(n + "(") }))
  }
}

// ---------------------------------------------------------------------------
// B — the controls. What a raise must STILL do, and must still NOT do
// ---------------------------------------------------------------------------

///| A RAISE DIVERGES, and this is the fixture that says so. If `SRaise` were

///| modelled as "an expression statement that happens to mention an error",

///| the statement after it would look reachable and this would report zero.
///

///| Counterpart: the same file with a bare `return` instead must report the same

///| thing -- so this test cannot pass merely because the lens reports dead code

///|
/// after any terminator.
test "0424: a raise terminates the frame like a return (and the control agrees)" {
  let with_raise = @pipeline.run(
    "suberror E {\n  E(Int)\n}\nfn f() -> Int raise E {\n  raise E\n  return 1\n}\nlet x = f()\n",
    "raise_terminates.mbt",
    @core.IfaceSymTab::empty(),
  )
  let with_return = @pipeline.run(
    "fn f() -> Int {\n  return\n  return 1\n}\nlet x = f()\n",
    "return_terminates.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(with_raise, "Unreachable"), 1)
  assert_eq(count_family(with_return, "Unreachable"), 1)
}

///| THE PAYLOAD IS STILL ANALYSED. `raise` must not become the one place in the

///| language where a real defect goes silent, so a call to an undefined

///| function inside the error value still has to be found.
///

///| The subtlety this pins: the two undefined names (`E`, the callee, and

///| `nosuchfunction`, inside its argument) land on the SAME line, and

///| `merge_findings` groups by `(merge family, line)`, so exactly ONE

///| `UndefinedName` comes back. Asserting 2 here would be asserting a merge

///| rule that does not exist. The control below puts the same two names on two

///|
/// lines and expects 2, which is what proves the merge -- and not a silently
///: swallowed argument -- is what collapsed them.
test "0424: a defect inside a raise payload is still reported" {
  let r = @pipeline.run(
    "suberror E {\n  E(Int)\n}\nfn f() -> Int raise E {\n  raise E(nosuchfunction())\n  return 1\n}\nlet x = f()\n",
    "raise_payload_defect.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "UndefinedName"), 1)
}

///| THE CONTROL FOR THE MERGE CLAIM ABOVE: the same two undefined names on two

///| different lines must come back as TWO findings. If this ever returned 1,

///| then the single finding in the previous test would be the argument being

///|
/// swallowed rather than two names sharing a line.
test "0424: two undefined names on two lines stay two findings (control)" {
  let r = @pipeline.run(
    "suberror E {\n  E(Int)\n}\nfn f() -> Int raise E {\n  let x = nosuchfunction()\n  raise E(nosuchother())\n  return 1\n}\nlet x = f()\n",
    "two_lines.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "UndefinedName"), 2)
}

///| THE RETURN TYPE DOES NOT BECOME THE RAISE PAYLOAD, which is the thing

///| `SReturn(Some(e))` would have caused: `Infer::scan_returns` joins a

///| RETURNED expression's type into the inferred return type, so modelling a

///| raise as a return of the error would make `f` look like it returns `E`.
///

///| What actually renders here is `Union{}` -- bottom -- and that is correct

///| rather than a defect: `raise E(1)` terminates the frame, so the `return 1`

///| after it is unreachable and the function has no normal exit carrying a

///| value. The discriminator is what does NOT appear: the error type never does.

///| The control below is the same function with the raise deleted, which does

///|
/// reach its return and does render `int`.
test "0424: the raise payload's type does not become the return type" {
  let r = @pipeline.run(
    "suberror E {\n  E(Int)\n}\nfn f() -> Int raise E {\n  raise E(1)\n  return 1\n}\nlet x = f()\n",
    "raise_no_return_join.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(r.sigs.length(), 1)
  assert_eq(r.sigs[0], "f() -> Union{}")
}

///| THE CONTROL for the test above: same signature, no raise statement, so the

///| return is reachable and the type is `int`. Without it the previous test

///| could pass for the wrong reason -- a signature renderer that always printed

///|
/// bottom would satisfy it.
test "0424: without the raise statement the return type is reachable (control)" {
  let r = @pipeline.run(
    "fn f() -> Int {\n  return 1\n}\nlet x = f()\n",
    "no_raise_return.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(r.sigs.length(), 1)
  assert_eq(r.sigs[0], "f() -> int")
}

///| `raise` IS NOT A KEYWORD YOU CAN SHADOW OR CALL. The clause is matched by

///| NAME (`at_name("raise")`), so a program that legitimately binds a value

///|
/// called something that merely starts with the same letters must be
///: unaffected -- and, more to the point, a function actually named `raise`
///: must not be silently reinterpreted as the statement form.
test "0424: a name that merely starts with raise is still an ordinary call" {
  let r = @pipeline.run(
    "fn raiser() -> Int {\n  return 1\n}\nfn f() -> Int {\n  raiser()\n  return raiser()\n}\nlet x = f()\n",
    "raise_prefix.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "ParseError"), 0)
  assert_eq(count_family(r, "UndefinedName"), 0)
  assert_eq(r.sigs.length(), 2)
}

// ---------------------------------------------------------------------------
// C -- the three fixtures that had to exist because mutations M2, M4 and M7
//     survived the first version of this file. Each is here for a reason that
//     is written down; none of them is a "more coverage" test.
// ---------------------------------------------------------------------------

///| M2 -- "the payload is never parsed, it is always `SRaise(None)`" -- SURVIVED

///| the obvious tests, and the reason is worth recording because it is a trap.

///| When the payload is simply left at the cursor it does not disappear: it

///| becomes the next STATEMENT. `raise E(nosuchfunction())` then parses as

///| `SRaise(None)` followed by the expression statement `E(nosuchfunction())`,

///| and the same two undefined names still turn up on the same line and still

///| merge into one. Every count-based assertion in this file passes either way.
///

///| What actually differs is WHICH LENS found them. The behaviour lens does not

///| evaluate a raise payload -- see the `SRaise` arm in `interp`: everything

///| after a terminator is dead, so evaluating a discarded expression could only

///| perturb the abstract value stack. An orphaned payload IS evaluated. So with

///| the payload attached the name is structural-only; with it orphaned the

///| behaviour lens reaches it too and the same finding gains a lens.
///

///| That makes this the test that pins "the payload belongs to the raise and is

///|
/// not executed", which is a real design claim rather than an implementation
///: detail.
test "0424: the raise payload belongs to the raise and is not executed (M2)" {
  let r = @pipeline.run(
    "suberror E {\n  E(Int)\n}\nfn f() -> Int raise E {\n  raise E(nosuchfunction())\n  return 1\n}\nlet x = f()\n",
    "raise_payload_lens.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family_in(r, "UndefinedName", @core.LStructural), 1)
  assert_eq(count_family_in(r, "UndefinedName", @core.LBehavior), 0)
}

///| M4 -- "the type lens stops type-checking the raise payload" -- also SURVIVED

///| the first version, for a second reason: every payload in this file up to

///| here was a call to an UNKNOWN name (`E`), and a call to an unknown function

///| has no signature to check its arguments against, so `ty_of` returns early

///| and the payload is never really looked at.
///

///| The payload has to be an expression the type lens checks on its own.

///| `raise 1 + "a"` is settled valid MoonBit and `int + str` is an

///|
/// `OperatorMismatch` -- and unlike a name lookup, a binary operator cannot be
///: skipped for want of a signature.
test "0424: a type error inside a raise payload is reported (M4)" {
  let r = @pipeline.run(
    "suberror E {\n  E(Int)\n}\nfn f() -> Int raise E {\n  raise 1 + \"a\"\n  return 1\n}\nlet x = f()\n",
    "raise_payload_type.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family_in(r, "OperatorMismatch", @core.LType), 1)
}

///| M7 -- "a bare `raise` with nothing after it no longer stops" -- SURVIVED too,

///| and simply because NO FIXTURE IN THE FILE HAD A BARE `raise`. The function

///| named `bare` above writes `raise E`, which HAS a payload. The guard this

///| protects is for the payload-less form, and that form is settled valid in

///| three positions (`moon check`, zero errors each): alone in a body, at the

///| end of a body followed by more statements, and closing a nested block with

///| no semicolon.
///

///| The assertion is that these parse CLEANLY. With the guard gone the reader

///|
/// goes on to parse whatever follows the `raise` as its error value, and in
///: the block case that is the closing brace of the enclosing block.
test "0424: a bare raise with no payload parses cleanly (M7)" {
  let alone = @pipeline.run(
    "suberror E {\n  E(Int)\n}\nfn f() -> Int raise E {\n  raise\n}\nlet x = f()\n",
    "bare_raise.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(alone, "ParseError"), 1)
  let in_block = @pipeline.run(
    "suberror E {\n  E(Int)\n}\nfn f() -> Int raise E {\n  if true {\n    raise\n  }\n  return 1\n}\nlet x = f()\n",
    "bare_raise_block.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(in_block, "ParseError"), 1)
}

///| M2, SECOND ATTEMPT. The lens split above did not separate them either, and

///| the reason is the same trap seen from the other side: with the payload

///| orphaned it becomes the statement AFTER a terminating `SRaise(None)`, so

///| the behaviour lens never executes it either -- `exec_block` sees the frame

///| already dead and reports it unreachable instead. Both shapes give exactly

///| one `Unreachable` from exactly one lens.
///

///| What is left is WHERE it is reported. With the payload attached to the

///| raise, the dead statement is `return 1` on line 6. With the payload

///| orphaned, the dead statement is the payload itself, still on line 5. Same

///| count, same family, same lens -- different line, and the line is the whole

///| claim: "the payload belongs to the raise" is exactly the statement that

///| line 5 is NOT the unreachable one.
///

///|
/// Counting could never have caught this. Asserting on the anchor is what makes
///: the mutation killable.
test "0424: the unreachable statement is the one after the raise, not the payload (M2)" {
  let r = @pipeline.run(
    "suberror E {\n  E(Int)\n}\nfn f() -> Int raise E {\n  raise E(nosuchfunction())\n  return 1\n}\nlet x = f()\n",
    "raise_payload_anchor.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "Unreachable"), 1)
  // line 6 is `return 1`; line 5 is `raise E(nosuchfunction())`
  assert_eq(first_line_of(r, "Unreachable"), 6)
}

///|
/// The line of the FIRST report in a family, 0 when the family is absent.
fn first_line_of(r : @pipeline.PipelineResult, name : String) -> Int32 {
  let mut out = 0
  for rep in r.reports {
    if rep.family.name() == name && out == 0 {
      out = rep.span.start.line
    }
  }
  out
}
