// Tests for 0.4.29: `expr as &Trait` is a trait-object CAST, and the parser had
// no production for it.
//
// THE DEFECT. `as` is a MoonBit keyword (it is already in the lexer's
// `is_moonbit_keyword` list) but nothing in the expression grammar consumed it.
// The postfix loop broke on it, the statement reader took the leftover `as` as
// the start of the next expression, and the binding walk resolved it as an
// ordinary identifier. The result was `undefined name 'as'` — a name that never
// existed, reported as actionable, on a program `moon check` accepts with zero
// errors.
//
// SETTLED AGAINST THE COMPILER, not assumed. `_verify/settle_0428_cast.ps1`
// compiles three forms of the construct and requires two negatives to be
// rejected: `b as &Sink`, `Box::{ n: 2 } as &Sink` and `Box::{ ..o, n: 9 } as
// &Sink` all ACCEPT, while a bare `b as` and a non-trait `b as Box` are both
// REJECTED. `moon check` spells the rule out: "`Int` is not a trait object type,
// it cannot be used on the right hand side of `as`." So `as` is an operator the
// parser must accept, and only the right-hand side is constrained.
//
// MEASURED POPULATION: exactly ONE occurrence in the six corpora —
// wzzc-dev/moui `runtime/view_tree.mbt:69:38`
//
//     RuntimeViewAdapter::{ view, emit } as &RuntimeViewNode
//
// counted by the analyzer's own output (`_verify/measure_0428_as.ps1`), not by a
// matcher. One site is small, but it was moui's ONLY actionable finding, so
// this fix takes that corpus to zero actionable.
//
// WHAT THE FIX DOES NOT DO. It does not check that the right-hand side is a
// trait. `IfaceSymTab` keeps no trait/struct distinction, so such a check would
// report every cast to a struct type. The target type is read and discarded;
// `ECast` holds the operand alone. See the node's doc for the full argument.

///|
/// THE DEFECT. A cast on a parameter. Before the fix this produced
/// `undefined name 'as'` at the `as`.
///
/// The two counters are the package's own `count_named` (`pipeline_0424_test.mbt`)
/// and `count_family` (`pipeline_test.mbt`). `count_named` counts by MESSAGE, not
/// by family, and that is the whole point: every finding in these fixtures is
/// family `UndefinedName`, so a family count cannot tell "no undefined `as`" from
/// "no undefined names at all" — and the second would still pass if the fix had
/// simply muted the lens. Counting the message names the token, which is the
/// thing under test.
test "0429: a cast is not reported as an undefined name" {
  let r = @pipeline.run(
    "fn to_sink(b : Box) -> &Sink {\n  b as &Sink\n}\nfn main {\n  let _ = to_sink\n}\n",
    "cast_ident.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_named(r, "as"), 0)
}

///|
/// THE CORPUS SHAPE, byte for byte in form: a struct literal on the left, not a
/// bare identifier. This is the one form moui actually writes, and it is a
/// different token sequence — a `::`-fold, a brace group, then `as`.
test "0429: a cast of a struct literal is not reported as an undefined name" {
  let r = @pipeline.run(
    "fn to_sink() -> &Sink {\n  Box::{ n: 2 } as &Sink\n}\nfn main {\n  let _ = to_sink\n}\n",
    "cast_literal.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_named(r, "as"), 0)
}

///|
/// THE THIRD SETTLED FORM — the struct UPDATE (`..old`), which is a third token
/// sequence again and is the one most likely to desynchronise the postfix loop.
test "0429: a cast of a struct update is not reported as an undefined name" {
  let r = @pipeline.run(
    "fn bump(o : Box) -> &Sink {\n  Box::{ ..o, n: 9 } as &Sink\n}\nfn main {\n  let _ = bump\n}\n",
    "cast_update.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_named(r, "as"), 0)
}

///|
/// THE ANTI-REGRESSION THIS FILE EXISTS FOR. The fix removes one false positive
/// and must not introduce another. `b` is read by exactly one thing — the cast —
/// so if `walk`'s `ECast` arm did not walk its operand, `b` would be reported
/// unused. Trading a false positive for a false positive is not a fix.
///
/// This is the `EComp` lesson in its exact form: the half that is not walked is
/// the half that vanishes.
test "0429: a parameter read only inside a cast is not reported unused" {
  let r = @pipeline.run(
    "fn to_sink(b : Box) -> &Sink {\n  b as &Sink\n}\nfn main {\n  let _ = to_sink\n}\n",
    "cast_reads_operand.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "UnusedParam"), 0)
}

///|
/// THE CONTROL FOR THE TEST ABOVE, and it must expect the OPPOSITE number. Same
/// shape, one thing changed: the parameter is genuinely never read. If this ever
/// reports 0, the test above has stopped meaning anything — "no unused finding"
/// would then be true of the program shape rather than of the cast.
test "0429: control -- a parameter read by nothing at all is still unused" {
  let r = @pipeline.run(
    "fn to_sink(b : Box) -> &Sink {\n  1\n}\nfn main {\n  let _ = to_sink\n}\n",
    "no_cast_reads_nothing.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "UnusedParam"), 1)
}

///|
/// THE CONTROL FOR THE FIRST TEST. A name that genuinely does not exist must
/// still be reported, or the fix could have been "stop resolving names after a
/// cast" — which would silence real defects everywhere casts are written.
test "0429: control -- a genuinely undefined name is still reported" {
  let r = @pipeline.run(
    "fn to_sink(b : Box) -> &Sink {\n  nosuchname as &Sink\n}\nfn main {\n  let _ = to_sink\n}\n",
    "cast_of_missing.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_named(r, "nosuchname"), 1)
}

///|
/// THE PARSE MUST STAY IN STEP AFTER THE CAST. A node that consumes `as` and
/// the type but then mis-tracks the cursor would report the RIGHT answer here
/// while silently truncating the rest of the function. The read after the cast
/// is what makes that visible: it is only analysed if the parser is still
/// positioned correctly.
test "0429: statements after a cast are still analyzed" {
  let r = @pipeline.run(
    "fn to_sink(b : Box) -> &Sink {\n  let s = b as &Sink\n  nosuchname\n  s\n}\nfn main {\n  let _ = to_sink\n}\n",
    "cast_then_more.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_named(r, "nosuchname"), 1)
}

///|
/// A CAST MAY BE CHAINED, and the chain must keep going: `(b as &Sink).fire()`
/// is a method call on a cast result. If `ECast` ended the postfix loop rather
/// than continuing it, the `fire()` would be left unconsumed and reported. The
/// assertion is that no name is invented, and the `nosuchname` argument makes
/// sure the argument list was actually parsed rather than skipped.
test "0429: a cast result can be used as a receiver" {
  let r = @pipeline.run(
    "fn go(b : Box) -> Unit {\n  (b as &Sink).fire(nosuchname)\n}\nfn main {\n  let _ = go\n}\n",
    "cast_receiver.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_named(r, "as"), 0)
  assert_eq(count_named(r, "nosuchname"), 1)
}

///|
/// THE BASE IS STILL TYPED INSIDE A CAST. `ECast` returns `TUnknown` for the
/// cast RESULT, and it would be easy to read that as "the operand is not
/// examined". It is: `infer`'s arm calls `ty_of` on the operand precisely so a
/// wrong name or a wrong argument type inside it is still found. `take(1)` puts
/// an `Int` where `Bool` is declared, and that finding must survive the cast.
///
/// This is the fixture that kills the "just return TUnknown" mutation. Without
/// it, dropping the `ty_of` call loses real checking and every other test in
/// this file still passes.
test "0429: a type error inside a cast operand is still reported" {
  let r = @pipeline.run(
    "fn take(x : Bool) -> Bool {\n  x\n}\nfn go(b : Box) -> &Sink {\n  take(1) as &Sink\n}\nfn main {\n  let _ = go\n}\n",
    "cast_operand_type_error.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "ArgTypeMismatch"), 1)
}

///|
/// A PATTERN BOUND BY AN `is` TEST INSIDE A CAST IS STILL BOUND.
///
/// This fixture was written to pin the interpreter's `eval` of the cast operand,
/// and it does NOT. Three attempts failed, each for a reason worth recording:
///
///   1. `MethodError` inside the operand — there is none. `1.nomethod()` reports
///      nothing, and the one finding a probe counted was a WARNING
///      (`UnusedParam`) that a grep for `error:` had filtered out.
///   2. The same idea in a function that is never CALLED. `Interp::run_top`
///      skips `SFunc` outright (interp.mbt:389), so nothing in that body ran.
///   3. The same idea in `fn main` — which `run_top` also skips, being an
///      `SFunc` like any other.
///
/// What the fixture actually pins is the STRUCTURAL lens: `walk` must reach
/// through the cast to the `EIs` inside it and bind `t`, or `t` would be
/// reported as an undefined name. That is real and worth a guard, but it is
/// `walk`'s guarantee, not `interp`'s. Whether `interp` evaluates a cast operand
/// is answered by `_verify/probe_0429_m4.ps1`, which finds no observable
/// difference either way.
test "0429: a pattern bound by an is-test inside a cast stays bound" {
  let r = @pipeline.run(
    "fn main {\n  let x = 1\n  let c = (x is TName(t)) as &Sink\n  let _ = t\n  let _ = c\n}\n",
    "cast_operand_is_binding.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_named(r, "t"), 0)
}

///|
/// THE CONTROL FOR THE TEST ABOVE, and it differs from it by ONE token. Same
/// `fn main`, same cast, same `is` test — and one extra read of `zz`, which
/// nothing binds. If this ever reported 0, the fixture above would be measuring
/// nothing: the two programs would agree about `t` for a reason that has nothing
/// to do with the cast.
///
/// It also records something the first attempt got wrong: `zz` is reported by
/// the STRUCTURAL lens as `undefined name`, not by the interpreter as
/// `undefined variable`. The two share a family and a span, so the merged stream
/// shows one of them and the other is invisible — which is precisely why the
/// interpreter's view of a cast operand cannot be pinned from the outside.
test "0429: control -- an unbound name in the same program is still reported" {
  let r = @pipeline.run(
    "fn main {\n  let x = 1\n  let c = (x is TName(t)) as &Sink\n  let _ = t\n  let _ = zz\n  let _ = c\n}\n",
    "cast_operand_is_binding_control.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_named(r, "zz"), 1)
  assert_eq(count_named(r, "t"), 0)
}

///|
/// THE NEGATIVE, PINNED. `b as` with nothing after it is rejected by `moon
/// check` (the settle gate asserts this), and the analyzer must not silently
/// accept it either: `type_annotation` reaches `expect_name` and says where the
/// type should have been. A parser that consumed `as` and shrugged would make
/// invalid input look valid — the mirror image of the defect this file fixes.
test "0429: a cast with no target type reports where the type should be" {
  let r = @pipeline.run(
    "fn to_sink(b : Box) -> &Sink {\n  b as\n}\nfn main {\n  let _ = to_sink\n}\n",
    "cast_no_target.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_named(r, "as"), 0)
  let mut parse_errs = 0
  for rep in r.reports {
    if rep.family.name() == "ParseError" && rep.message.contains("type name") {
      parse_errs += 1
    }
  }
  assert_eq(parse_errs, 1)
}
