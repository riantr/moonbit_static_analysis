//| Tests for 0.4.38: two shapes the parser did not read, and one it read wrong.
//
//| DEFECT A -- the EXTERNAL `fn` binding, `= "module" "symbol"`. A `fn` whose body
//| lives in another language is DECLARED, not defined:
//
//|     fn web_begin_create_string() -> Int = "window_web" "begin_create_string"
//
//| The parser finished the signature, found `=` where it wanted `{`, and reported
//| `expected '{'` -- which is the parser naming a token that was never the
//| problem. That report is the file's `first_error`, which truncates the trusted
//| region and marks the file NOTPARSE: everything after the declaration went
//| unread, including whatever else the file declares.
//
//| SETTLED WITH THE TOOLCHAIN first, in `_verify/settle_0449_ffi_decl.ps1`,
//| 7/7 with BOTH negative controls firing. All three shapes are ACCEPTed by
//| `moon check`: no parameters, a single-line parameter list, and the multi-line
//| one. So these files are unread on legal MoonBit, not on a mistake.
//
//| MEASURED COST, on wzzc-dev/moui 0.1.12: FOUR of the seventeen files the
//| truncation ranking reports (`_verify/diagnose_moui_truncations.ps1`), the
//| largest single shape there. `backend/web/accessibility.mbt` cut at line 370
//| hides 7 further lines; `web_host.mbt` at 382 hides 80.
//
//| DEFECT B -- the TUPLE STRUCT `struct Name(T)`. `skip_decl_braced` scans forward
//| for the `{` that opens a body; a tuple struct has none, so the scan ran on and
//| took the NEXT declaration's brace. Settled in `_verify/settle_0449b_tuple_struct.ps1`,
//| 8/8 with three negative controls firing.
//
//| ONE THING THIS FILE GOT WRONG FIRST, and the correction is the reason several
//| assertions below name a family the obvious reading would not have chosen. The
//| name-registration in `parse_external_binding` was believed to suppress
//| `undefined function` at a call site -- the mutation gate said so in prose, and
//| it is false. `extern_fns` is consumed at exactly one place, `walk.mbt:1170`,
//| and what it suppresses there is `audit_frame`, which is where `UnusedParam`,
//| `UnusedLocal` and `ParamChanged` come from. Measured: dropping the
//| registration leaves `undefined function` untouched and takes a header-only
//| external fn from zero findings to `UnusedParam = 1`.
//|
//| The second thing: a header-only declaration is precisely why that matters. The
//| body is not in this file, so every parameter of an external fn is trivially
//| unused, and without the registration the fix would have traded four unread
//| files for a false positive on each one.

///|
/// THE SHAPE, and the fix's whole claim: this parses.
test "0449: an external fn binding parses instead of expecting a body" {
  let r = @pipeline.run(
    "///|\nfn web_begin_create_string() -> Int = \"window_web\" \"begin_create_string\"\n",
    "web_host.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "ParseError"), 0)
}

///|
/// THE NAME BINDS, AND THE UNREAD BODY IS NOT AUDITED. Two claims, one fixture,
/// because they share the mechanism and only together they are the whole fix.
///
/// The header-only `SFunc` has an EMPTY body that was never read, so its two
/// parameters are unused for a reason the file does not contain. `extern_fns`
/// keeps `audit_frame` from running on it. Without the registration this is
/// `UnusedParam = 1` -- measured, not predicted.
///
/// The call is here so the first claim is pinned too: a name the file declares
/// is not an undefined name. This half is the one that was ALREADY passing for
/// the wrong reason (a same-file call resolves through the analyzer's own
/// top-level declaration table), so it is not what kills the mutation; the
/// `UnusedParam` line is.
test "0449: an external fn is not audited for a body that was never read" {
  let r = @pipeline.run(
    "///|\nfn ffi_params(alpha : Int, beta : Int) -> Unit = \"mod_a\" \"sym_a\"\n\n///|\nfn probe() -> Int {\n  ffi_params(0, 0)\n  1\n}\nprobe()\n",
    "ffi_params.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "ParseError"), 0)
  assert_eq(count_family(r, "UndefinedName"), 0)
  assert_eq(count_family(r, "UnusedParam"), 0)
}

///|
/// THE CONTROL THAT GIVES THE PRECEDING LINE ITS MEANING, and the reason it is
/// not optional: `UnusedParam == 0` is only a claim if the family can be
/// reported at all. An ordinary fn with the same two unused parameters must
/// still produce it -- otherwise the assertion above would be satisfied by the
/// family being off, which is the shape of a guard that measures nothing.
test "0449: an ordinary fn with the same unused parameters is still audited" {
  let r = @pipeline.run(
    "///|\nfn ord_params(alpha : Int, beta : Int) -> Unit {\n  ()\n}\n",
    "ord_params.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "UnusedParam"), 1)
}

///|
/// THE TWO-STRING FORM, WHICH IS WHAT THE CORPUS ACTUALLY WRITES.
///
/// This was written as the control against the obvious wrong implementation --
/// "an implementation that took ONE string leaves the second behind, so this
/// file still fails". THAT CLAIM IS FALSE and was measured rather than assumed:
/// with one string consumed, findings are identical to consuming both, across
/// nine fixtures -- an external binding followed by a `fn`, a `let`, a braced
/// struct, a tuple struct, a second external binding, no blank line, and two
/// control fixtures. A leftover string literal is a well-formed top-level
/// expression statement that the analyzer silently accepts, so it neither
/// reports, truncates, nor swallows what follows.
///
/// So the one-string implementation is recorded as a declared SURVIVED in
/// `_verify/mutate_0449.ps1` (M2), and what this test actually pins is the shape
/// itself: the real two-string binding is one declaration, not a declaration and
/// a stray literal.
test "0449: both strings of an external binding parse as one declaration" {
  let r = @pipeline.run(
    "///|\nfn web_sync_semantics_host(\n  raw_id : Int,\n  canvas_id : Int,\n  json : Int,\n) -> Unit = \"window_web\" \"sync_semantics\"\n",
    "accessibility.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "ParseError"), 0)
}

///|
/// THE SHAPE THAT IS NOT AN EXTERNAL BINDING must still be reported. A `fn` with
/// a real body is untouched, and a genuinely malformed one still says so: if the
/// new branch swallowed any `=` in signature position, this is what would notice.
test "0449: an ordinary fn with a body is unaffected" {
  let r = @pipeline.run(
    "///|\nfn add(x : Int) -> Int {\n  x + 1\n}\n\n///|\nfn probe() -> Int {\n  add(1)\n}\nprobe()\n",
    "ordinary.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "ParseError"), 0)
  assert_eq(count_family(r, "UndefinedName"), 0)
}

///|
/// THE `extern` FORM IS NOT REGRESSED. `parse_extern_fn` used to consume one
/// string inline; it now shares `parse_external_binding`, which is the fix for
/// the drift rather than a second copy of the rule. This is the shape that
/// inline block was written for, and it is the one that would break if the shared
/// helper were written only for the two-string case.
test "0449: extern C with a one-string binding still parses" {
  let r = @pipeline.run(
    "///|\nextern \"c\" fn native_exit(code : Int) -> Int = \"exit\"\n\n///|\nfn probe() -> Int {\n  native_exit(0)\n}\nprobe()\n",
    "native.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "ParseError"), 0)
  assert_eq(count_family(r, "UndefinedName"), 0)
}

///|
/// THE FALSE POSITIVES THIS SECOND HALF REMOVES. A tuple struct has no body,
/// and the braced skipper was scanning forward for the `{` that opens one -- so it
/// took the NEXT declaration's brace. In moonbitlang/async 0.22.4
/// `src/process/cancellation.mbt` that brace belongs to an `if`, and the `let` and
/// the `if` vanished with it:
///
///     undefined variable 'else'
///     undefined variable 'SIGTERM'
///
/// Two false positives on correct code, blamed on a declaration nobody was
/// complaining about. This fixture is the corpus shape, kept for provenance.
///
/// THREE HYPOTHESES FALSIFIED before the real one, because each looked like the
/// cause: the `is` pattern (clean alone), a qualified receiver (clean), and a
/// cross-package `@pkg.field` receiver (clean, scanned against the REAL extern
/// interfaces). All three probes varied the `if`; the cause was not in the `if`.
test "0449: a tuple struct does not swallow the declaration after it" {
  let r = @pipeline.run(
    "///|\npub(all) struct CancellationHandler(async (Int) -> Unit)\n\n///|\nlet v = if true {\n  1\n} else {\n  2\n}\n",
    "cancellation.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "UndefinedName"), 0)
}

///|
/// THE BOUNDARY OF THE DEFECT, and it is narrower than the test above suggests.
///
/// `skip_decl_braced` breaks at a top-level `fn` (`parser.mbt:802`) precisely so
/// that a bodiless declaration -- `pub impl Eq for T`, whose methods live in a
/// separate block -- cannot swallow the rest of the file. A tuple struct inherits
/// that sentinel for free, so a tuple struct followed by a FUNCTION is not
/// affected at all, and the test below stays green under M5 and M6.
///
/// THIS TEST THEREFORE KILLS NOTHING, and is here to say where the damage stops
/// rather than to be evidence for it. It was written first as the mutation's
/// named test on the reasoning that the scan would take `probe`'s own brace; the
/// gate's rule 6 refused that claim and named the test that actually went red
/// instead. The reason is the `fn` sentinel above, and the reason THAT matters is
/// the shape the corpus writes: in `cancellation.mbt` the declaration after the
/// tuple struct is a `let ... = if ...`, with no `fn` between, so the scan runs on
/// to the `if`'s brace. A guard for this defect has to be built on a `let`.
test "0449: the tuple-struct swallow stops at a following fn" {
  let r = @pipeline.run(
    "///|\npub(all) struct CancellationHandler(async (Int) -> Unit)\n\n///|\nfn probe() -> Int {\n  let dead = 7\n  1\n}\nprobe()\n",
    "cancellation.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "UnusedLocal"), 1)
}

///|
/// THE CONTROL FOR THE PRECEDING TEST, and the reason it can be believed. A
/// BRACED struct followed by the same function was already clean before this
/// change, because the skipper finds a `{` belonging to the struct. If the
/// discrimination took a braced struct, this goes red -- which is the direction
/// that trades two false positives for a cascade, since a braced struct's fields
/// would each be parsed as a top-level statement.
///
/// TWO FIELDS IS LOAD-BEARING, and one field does not do it. Measured against
/// the M4 mutation (every struct treated as a tuple struct):
///
///     one field  -> ParseError 2, UndefinedName ABSENT   the named test stayed green
///     two fields -> ParseError 3, UndefinedName 1        the named test goes red
///
/// With a single field the leftover line is absorbed by the stray `}` and no name
/// is ever reported, so the original fixture asserted nothing about the mutation
/// it was written for. It also asserts `UnusedLocal = 1`, which pins that the
/// function after the struct is reached either way.
test "0449: an ordinary braced struct still skips its body whole" {
  let r = @pipeline.run(
    "///|\npub struct Holder {\n  alpha : Int\n  beta : Int\n}\n\n///|\nfn probe() -> Int {\n  let dead = 7\n  1\n}\nprobe()\n",
    "holder.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "UndefinedName"), 0)
  assert_eq(count_family(r, "UnusedLocal"), 1)
}

///|
/// AND A REAL FINDING IS STILL A REAL FINDING. The whole point of registering the
/// name is to silence a specific, correct silence -- not to quiet the lens. A
/// call to something that exists nowhere must still be reported, and this is the
/// control that says the registration did not become a blanket suppression.
test "0449: registering an external name does not silence a missing one" {
  let r = @pipeline.run(
    "///|\nfn web_begin_create_string() -> Int = \"window_web\" \"begin_create_string\"\n\n///|\nfn probe() -> Int {\n  ZzMissing::nope()\n}\nprobe()\n",
    "web_host.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "UndefinedName"), 1)
}
