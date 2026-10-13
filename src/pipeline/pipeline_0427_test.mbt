// Tests for 0.4.27: a PARENTHESISED FUNCTION TYPE in return position is not a tuple.
//
// THE DEFECT. `fn f() -> (() -> Int) { ... }` is ordinary MoonBit. The analyzer
// read the annotation as a ONE-ELEMENT TUPLE: `return_annotation`'s tuple arm
// consumes to the first `)` not preceded by a comma, and in `(() -> Int)` that
// is the paren closing the EMPTY parameter list -- so the annotation ended at
// `()` and `-> Int)` was left in the token stream. `parse_block` then looked for
// `{`, found `->`, and said `expected '{'`. One bad annotation then killed the
// rest of the file, and the message named a brace that was never the problem.
//
// The pre-existing test only recognised the UNPARENTHESISED spelling
// (`-> (Int) -> String`, where the `->` follows the matching `)`). The
// parenthesised spelling puts the `->` INSIDE, so it fell into the tuple arm.
// 0.4.27 accepts either: one nesting-tracking scan sets `arrow_inside` when a
// `->` is reached before the depth returns to zero.
//
// EVERY FIXTURE BELOW IS SETTLED VALID AND PROVEN CLEAN BY THE ANALYZER.
// `_verify/settle_probe_0427.ps1` runs each source through BOTH `moon check` and
// the analyzer and only calls a case usable when both agree; its negative control
// has to be rejected by both or the whole run is void. Getting to that state took
// four corrections, all recorded below, because every one of them produced
// fixtures that would have passed for the wrong reason:
//
//   - MoonBit lambdas use BRACES: `fn() { 1 }`. `fn() => 1` and `fn _ => 1` are
//     parse errors ("unexpected token `=>`, you may expect `{`"). The first draft
//     used `fn { ... }`, which is not a lambda at all.
//   - An UPPERCASE top-level name is a TYPE. `fn G() -> Int` dies with
//     "unexpected token `(`, you may expect `::`". All helpers here are lowercase.
//   - A fixture whose body returns the wrong type is rejected with 4014, and a
//     `main` that discards a non-Unit value with 4139. Both are correct compiler
//     behaviour and both make a fixture that proves nothing.
//   - The bodies return a NAMED helper (`return g`), not a lambda literal,
//     because the analyzer reports its own pre-existing "lambda is outside the
//     analyzed subset" notice. A literal made every fixture here fail on an
//     unrelated limitation while looking like a 0.4.27 regression.
//
// ---------------------------------------------------------------------------
// A -- the false positive this removes
// ---------------------------------------------------------------------------

///|
/// THE SHAPE ITSELF. Before the fix this reported `expected '{'` and cascaded
/// through the rest of the file.
///
/// `return g` and not `return 1`: the annotation says the function returns
/// `() -> Int`, and returning the integer is a 4014 the compiler is right to
/// report. The helper is a zero-argument function of exactly that type.
test "0427: a parenthesised function type return is not a one-element tuple" {
  let r = @pipeline.run(
    "fn g() -> Int {\n  1\n}\nfn f() -> (() -> Int) {\n  return g\n}\nlet x = f()\n",
    "retfn_plain.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "ParseError"), 0)
}

///|
/// WITH A PARAMETER, so the group being scanned over is not empty. The ancestor
/// of this test looked only at the three tokens `(`, `)`, `->`, which is the
/// shape of `() -> T` and nothing else -- `(Int) -> String` has `Int` between the
/// brackets, so that fixture missed and failed with four parse errors of its own.
/// Real annotations have a parameter.
test "0427: a parameterised parenthesised function type parses" {
  let r = @pipeline.run(
    "fn g1(_n : Int) -> String {\n  \"a\"\n}\nfn f() -> ((Int) -> String) {\n  return g1\n}\nlet x = f()\n",
    "retfn_paren.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "ParseError"), 0)
}

///|
/// THE SCAN MUST NOT STOP AT THE INNER `)`. Here the function type's OWN result
/// is a tuple, so the group closes two parens before its own and carries a comma
/// at depth 1 that a naive tuple reader would treat as the end of the annotation.
/// This is the fixture that says the nesting counter is counting and that "has a
/// comma" is not the discriminator.
test "0427: a function type returning a tuple is read whole" {
  let r = @pipeline.run(
    "fn g2(_s : String) -> (Int, Int) {\n  (1, 2)\n}\nfn f() -> ((String) -> (Int, Int)) {\n  return g2\n}\nlet x = f()\n",
    "retfn_nested.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "ParseError"), 0)
}

///|
/// `?` IS THE SPELLING THE CORPUS USES, and no fixture above has it. All 24
/// affected sites in moui are written `-> (() -> Unit)?`. If the fix consumed the
/// `?` along with the annotation, this is where it shows.
test "0427: an optional parenthesised function type parses" {
  let r = @pipeline.run(
    "fn g() -> Int {\n  1\n}\nfn f() -> (() -> Int)? {\n  return Some(g)\n}\nlet x = f()\n",
    "retfn_opt.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "ParseError"), 0)
}

///|
/// THE MULTI-LINE SPELLING, with a qualified name -- the literal shape of the
/// three moui files that go from PARTIAL to fully parsed. It is also the shape a
/// measurement regex is most likely to miss: see measure_0427_retfn.ps1, whose
/// first two versions both reported this construct absent from a corpus holding
/// nine files of it.
///
/// The ONE ParseError asserted here is the `struct` declaration notice, which
/// every file declaring a struct carries and which has nothing to do with the
/// return annotation. Asserted exactly rather than waved past, because a test
/// that said `>= 1` here could not distinguish "the struct notice" from "the
/// annotation broke too".
test "0427: a multi-line signature ending in a parenthesised function type parses" {
  let r = @pipeline.run(
    "struct M {\n  x : Int\n}\nfn gu() -> Unit {\n  ()\n}\npub fn M::start(\n  self : M,\n  done : (Int) -> Unit,\n) -> (() -> Unit)? {\n  return Some(gu)\n}\nlet y = M::start\n",
    "retfn_multiline.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "ParseError"), 1)
}

///|
/// THE `raise` CLAUSE IS NOT PART OF THE ARROW SCAN. `-> (() -> Int raise E)` has
/// an arrow inside the parens AND an effect after the type. Had `arrow_inside`
/// been computed by scanning past the matching `)` it would have swallowed the
/// `raise E` and `parse_raise_effect` would never have seen it.
///
/// The compiler proves the annotation is read correctly here by quoting it back
/// verbatim in the settle run: `wanted : () -> Int raise E`. The single
/// ParseError is the suberror notice, carried by every suberror fixture.
test "0427: the arrow scan does not swallow a raise effect" {
  let r = @pipeline.run(
    "suberror E {\n  E(Int)\n}\nfn g() -> Int raise E {\n  1\n}\nfn f() -> (() -> Int raise E) {\n  return g\n}\nlet x = f()\n",
    "retfn_raise.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "ParseError"), 1)
}

///|
/// THE RESULT IS A FUNCTION, NOT A TUPLE -- the same question the tuple fixture
/// below answers "Tuple" to.
///
/// `contains` rather than an indexed compare on purpose. `analyzed_sigs` ends in
/// `out.sort()`, yet this fixture's two signatures come back as
/// `["g() -> int", "f() -> Function"]`, which is not the alphabetical order that
/// `sort()` would produce and IS the order they appear in the source. I did not
/// chase down which of those two it is, so the test does not encode either: what
/// this fixture is for is the VALUE, and pinning a position would make it fail
/// for a reason that has nothing to do with the return annotation. If the order
/// is later found to be a real defect, that is a separate finding with its own
/// fixture.
test "0427: the parenthesised function type reports a function, not a tuple" {
  let r = @pipeline.run(
    "fn g() -> Int {\n  1\n}\nfn f() -> (() -> Int) {\n  return g\n}\nlet x = f()\n",
    "retfn_plain_sig.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(r.sigs.length(), 2)
  assert_true(r.sigs.contains("f() -> Function"))
}

// ---------------------------------------------------------------------------
// B -- the look-alikes, which must not move
// ---------------------------------------------------------------------------

///|
/// CONTROL FOR THE WHOLE RELEASE: a genuine tuple return still reads as a tuple.
/// There are 179 of these across the six corpora (measure_0427_retfn.ps1), so an
/// over-broad `arrow_inside` would trade one break for another across a
/// hundred-plus sites.
///
/// This and the fixture above answer the same question -- function or tuple? --
/// with OPPOSITE expectations. That is what makes it a control: a change that
/// answered "tuple" to both would pass the first and fail this.
test "0427: a genuine tuple return is still a tuple" {
  let r = @pipeline.run(
    "fn f() -> (Int, String) {\n  return (1, \"a\")\n}\nlet x = f()\n",
    "ret_tuple_plain.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "ParseError"), 0)
  assert_eq(r.sigs.length(), 1)
  assert_eq(r.sigs[0], "f() -> Tuple")
}

///|
/// A TUPLE WHOSE ELEMENTS ARE FUNCTION TYPES -- the harder look-alike, because
/// this one DOES contain arrows at depth 1, and a scan that asks "is there a `->`
/// anywhere inside the group" would capture it. The discriminator has to be
/// whether the arrow is the one that makes the GROUP a function type.
test "0427: a tuple of function types is still a tuple" {
  let r = @pipeline.run(
    "fn g() -> Int {\n  1\n}\nfn g1(_n : Int) -> String {\n  \"a\"\n}\nfn f() -> (() -> Int, (Int) -> String) {\n  return (g, g1)\n}\nlet x = f()\n",
    "ret_tuple_fn.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "ParseError"), 0)
}

///|
/// `-> (Int)` HAS NO COMMA AND NO ARROW -- the near miss on both sides, and the
/// reason the parser counts tokens rather than characters. Six of these exist in
/// the corpora. Small blast radius, but exactly what a cruder implementation of
/// this fix would break.
test "0427: a parenthesised scalar return is still the scalar" {
  let r = @pipeline.run(
    "fn f() -> (Int) {\n  return 1\n}\nlet x = f()\n",
    "ret_paren_scalar.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "ParseError"), 0)
  assert_eq(r.sigs.length(), 1)
  assert_eq(r.sigs[0], "f() -> int")
}

///|
/// THE UNPARENTHESISED SPELLING IS THE PRE-EXISTING PATH. The condition reads as
/// if `is_fn` were the new behaviour and `arrow_inside` the old guard, so this
/// pins that the `is_fn` arm is still reached for the shape it was written for.
test "0427: control -- an unparenthesised function type still parses" {
  let r = @pipeline.run(
    "fn g1(_n : Int) -> String {\n  \"a\"\n}\nfn f() -> (Int) -> String {\n  return g1\n}\nlet x = f()\n",
    "retfn_unparen.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "ParseError"), 0)
}

// ---------------------------------------------------------------------------
// C -- negative control: the fix must not make the return annotation optional
// ---------------------------------------------------------------------------

///|
/// THE DECLARED-TYPE PATH: the only place the return ANNOTATION string is
/// observable at all.
///
/// Everywhere else, `sigs` comes from the abstract-execution call cache, so the
/// annotation is never consulted. `declared_ret: ann_to_ty(f.retann)`
/// (infer.mbt:726) is the one consumer, and it is only read on a cache MISS --
/// that is, for a function no top-level statement reaches. Every other fixture in
/// this file calls its function, so without this one the declared path has no
/// fixture at all.
///
/// The value asserted is what the tuple arm produces. The tuple arm returns an
/// EMPTY annotation (`return ""`, parser.mbt:1272) and `ann_to_ty("")` is
/// `TUnknown`, so a never-called parenthesised scalar is reported `Any` rather
/// than `int`. Pre-existing behaviour of the tuple arm; 0.4.27 does not change
/// it.
///
/// AND IT DOES NOT KILL M4, which was the hope when it was written. Reading the
/// same path from the other side: the function-type arm returns `"(Int)"`, and
/// `ann_to_ty("(Int)")` is ALSO `TUnknown` -- the string carries parentheses no
/// arm of `ann_to_ty` strips. That is why M4 survives, and the proof is in
/// mutate_0427.ps1. This fixture stays because the path deserves a fixture, not
/// because it changed a verdict.
test "0427: a never-called parenthesised scalar reports the declared type" {
  let r = @pipeline.run(
    "fn f() -> (Int) {\n  return 1\n}\n",
    "ret_paren_scalar_uncalled.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(r.sigs.length(), 1)
  assert_eq(r.sigs[0], "f() -> Any")
}

///|
/// `-> {` IS A REAL SYNTAX ERROR ("unexpected token `{`, you may expect return
/// type annotation`, plus 4041), and it is the single most likely way to get this
/// fix wrong: if the annotation parser ever decided that "no annotation I
/// recognise" meant "there is none here", this would parse cleanly and silently
/// stop checking return types.
///
/// Settled as genuinely broken by the same script that settled the shapes above
/// as genuinely valid, and rejected by the ANALYZER too -- so the green fixtures
/// in A are not passing because the harness reports everything clean.
///
/// `>= 1` is the honest form: the question is "is it still reported at all", and
/// pinning an exact count would make the test brittle against the cascade shape
/// without making it stronger on that question.
test "0427: `-> {` is still a parse error" {
  let r = @pipeline.run(
    "fn f() -> {\n  return 1\n}\nlet x = f()\n",
    "ret_arrow_nothing.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_true(count_family(r, "ParseError") >= 1)
}
