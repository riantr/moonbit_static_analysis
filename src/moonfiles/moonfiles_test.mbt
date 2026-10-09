// Black-box invariant tests for the toolchain file kinds (.mbt.md / .mbti /
// .mbtp) — see EXTENSIONS.md for the taxonomy these tests encode.

///|
test "literate .mbt.md: fences analyzed with real line numbers" {
  let md = "# Title\n\nIntro prose.\n\n```mbt check\nfn ok_fn() -> int {\n  1\n}\n```\n\nMore prose.\n\n```mbt check\nfn broken() -> int {\n  missing(1)\n}\n```\n"
  let r = @moonfiles.literate(md, "doc.mbt.md")
  // first block is clean; the second block reports the undefined name
  assert_eq(r.reports.length(), 1)
  // the finding lands on the .md file's REAL line: the second fence opens
  // at line 13, so `missing(1)` (its line 2) is file line 15
  assert_eq(r.reports[0].span.start.line, 15)
  assert_eq(r.reports[0].family.name(), "UndefinedName")
  // both blocks contribute their inferred signature, in block order
  assert_eq(r.sigs.length(), 2)
  assert_eq(r.sigs[0], "ok_fn() -> int")
}

///|
test "literate .mbt.md: non-moonbit fences skipped" {
  let md = "```json\n{\"not\": \"code\"}\n```\n\n```mbt check\nfn f() -> int {\n  2\n}\n```\n"
  let r = @moonfiles.literate(md, "doc.mbt.md")
  assert_eq(r.reports.length(), 0)
  assert_eq(r.sigs.length(), 1)
}

///|
test "literate .mbt.md: blocks are independent (no cross-block bindings)" {
  let md = "```mbt check\nfn helper() -> int {\n  1\n}\n```\n\n```mbt check\nfn caller() -> int {\n  helper()\n}\n```\n"
  let r = @moonfiles.literate(md, "doc.mbt.md")
  // `helper` is not visible in the second block: one UndefinedName finding
  assert_eq(r.reports.length(), 1)
  assert_eq(r.reports[0].family.name(), "UndefinedName")
}

///|
test "iface .mbti: well-formed file has no findings" {
  let src = "// Generated using `moon info`, DON'T EDIT IT\npackage \"riantr/demo\"\n\n// Values\npub fn pos(Int, Int) -> Pos\n\n// Types and methods\npub(all) struct Pos {\n  line : Int\n} derive(Eq)\npub fn Pos::shift(Self, Int) -> Pos\n"
  let reports = @moonfiles.iface(src, "demo.mbti")
  assert_eq(reports.length(), 0)
}

///|
test "iface .mbti: duplicate signature reported" {
  let src = "package \"d\"\npub fn f(Int) -> Int\npub fn f(Int) -> Int\n"
  let reports = @moonfiles.iface(src, "d.mbti")
  assert_eq(reports.length(), 1)
  assert_eq(reports[0].family.name(), "ParseError")
  assert_true(reports[0].message.contains("duplicate signature 'f'"))
  assert_eq(reports[0].span.start.line, 3)
}

///|
test "iface .mbti: unknown type reference reported" {
  let src = "package \"d\"\npub fn f(Mystery) -> Int\n"
  let reports = @moonfiles.iface(src, "d.mbti")
  assert_eq(reports.length(), 1)
  assert_true(reports[0].message.contains("unknown type 'Mystery'"))
}

///|
test "iface .mbti: malformed line reported" {
  let src = "package \"d\"\npub fn f(Int) -> Int\nf(  \n"
  let reports = @moonfiles.iface(src, "d.mbti")
  assert_eq(reports.length(), 1)
  assert_true(reports[0].message.contains("malformed interface line"))
  assert_eq(reports[0].span.start.line, 3)
}

///|
/// Every shape below is copied from interfaces `moon info` actually emits (the
/// async/io and async/internal/gzip_internal ones). The audit used to report
/// each of these lines as "malformed interface line" or as an unknown type —
/// i.e. it flagged every real generated interface.
test "iface .mbti: real 'moon info' output produces no findings" {
  let src = "// Generated using `moon info`, DON'T EDIT IT\npackage \"moonbitlang/async/io\"\n\nimport {\n  \"moonbitlang/core/debug\",\n}\n\n// Values\npub fn pipe() -> (PipeRead, PipeWrite)\n\n// Errors\npub suberror PipeClosed derive(ToJson, @debug.Debug)\n#deprecated\npub impl Show for PipeClosed\n\npub(all) suberror ReaderClosed derive(ToJson, @debug.Debug)\n#deprecated\npub impl Show for ReaderClosed\n\n// Types and methods\ntype BufferedWriter[W]\npub fn[W] BufferedWriter::capacity(Self[W]) -> Int\npub async fn[W : Writer] BufferedWriter::flush(Self[W]) -> Unit\npub impl[W : Writer] Writer for BufferedWriter[W]\n\npub(all) enum Encoding {\n  UTF8\n}\n\ntype MemoryReader\n#callsite(autofill(loc))\npub fn MemoryReader::MemoryReader(async (&Writer) -> Unit, loc~ : SourceLoc) -> Self\npub async fn MemoryReader::read_some(Self) -> String?\npub fn MemoryReader::drop(Self, Int) -> Int\npub impl Reader for MemoryReader\n\ntype PipeRead\ntype PipeWrite\ntrait Writer\ntrait Data\npub impl Data for String\npub fn &Data::text(Self) -> String raise\n\npub const HEADER_SIZE : Int = 10\npub const STAT_FILE_SIZE : UInt = 0x0020\n\n// Type aliases\npub type Fd = Int\n"
  let reports = @moonfiles.iface(src, "io.mbti")
  assert_eq(reports.length(), 0)
}

///

///|
test "iface .mbti: labeled and optional parameters name types, not labels" {
  // `input_offset?` is a parameter name and `Int` is its type. Splitting the
  // parameter list on bare commas used to yield "input_offset? : Int" as an
  // unknown type.
  let src = "type Decoder\npub fn Decoder::write(Self, Bytes, FixedArray[Byte], input_offset? : Int, output_offset? : Int) -> (Int, Int) raise\n"
  let reports = @moonfiles.iface(src, "d.mbti")
  assert_eq(reports.length(), 0)
}

///

///|

///|
/// Declaration-body types are resolved. `Constr(a, label~ : T)` is BOTH a
/// constructor and a `label : Type` pair, so the constructor shape is tested
/// first and the contents are comma-split before each segment is read; hoisting
/// the `:` split instead reports the labeled parameter's NAME as a type, which
/// was measured at 7 false positives over the 89 real interfaces.
test "iface .mbti: types inside a declaration body are resolved" {
  // an unknown payload type inside an enum body IS caught
  let payload = @moonfiles.iface(
    "package \"d\"\npub(all) enum E {\n  Other(Ghost)\n}\n", "d.mbti",
  )
  assert_eq(payload.length(), 1)
  assert_true(payload[0].message.contains("unknown type 'Ghost'"))
  // so is an unknown struct field type
  let field = @moonfiles.iface(
    "package \"d\"\npub(all) struct S {\n  line : Phantom\n}\n", "d.mbti",
  )
  assert_eq(field.length(), 1)
  assert_true(field[0].message.contains("unknown type 'Phantom'"))
}

///|
/// The negative controls for the body scan — the shapes that look like types
/// and are not. All three appear verbatim in real `moon info` output.
test "iface .mbti: labeled params, derives and builtins are not body types" {
  // `context~ : String` — the NAME is not a type
  let labeled = @moonfiles.iface(
    "package \"d\"\npub(all) suberror OSError {\n  OSError(Int, context~ : String)\n}\n",
    "d.mbti",
  )
  assert_eq(labeled.length(), 0)
  // three labeled params in one constructor
  let multi = @moonfiles.iface(
    "package \"d\"\npub(all) enum R {\n  Exp(initial~ : Int, factor~ : Double, maximum~ : Int)\n}\n",
    "d.mbti",
  )
  assert_eq(multi.length(), 0)
  // derive(...) names TRAITS, not types
  let derived = @moonfiles.iface(
    "package \"d\"\npub(all) enum E {\n  A\n} derive(Eq, @debug.Debug)\n", "d.mbti",
  )
  assert_eq(derived.length(), 0)
  // UInt16 is a real MoonBit type (the toolchain's own utils.mbt uses it)
  let builtin = @moonfiles.iface(
    "package \"d\"\npub(all) enum E {\n  Other(UInt16)\n}\n", "d.mbti",
  )
  assert_eq(builtin.length(), 0)
}

///

///|
test "iface .mbti: a genuinely unknown type is still caught" {
  let src = "package \"d\"\npub fn f(Mystery) -> Int\n"
  let reports = @moonfiles.iface(src, "d.mbti")
  assert_eq(reports.length(), 1)
  assert_true(reports[0].message.contains("unknown type 'Mystery'"))
}

///

///|
test "iface .mbti: a generic fn binds its own type parameter, but not a ghost" {
  let src = "package \"d\"\npub fn[W] Boxed::new(W, Ghost) -> Self\n"
  let reports = @moonfiles.iface(src, "d.mbti")
  assert_eq(reports.length(), 1)
  assert_true(reports[0].message.contains("unknown type 'Ghost'"))
}

///
/// The same shape as the test above but for `impl`. Before the fix, the
/// scanner called `leading_bracket` on a body that still started with
/// `impl[`, so `bound_params` saw an empty string and the type parameters
/// A, B, C, ... were reported as unknown types in their own signature.
/// Caught on moonbitlang/core 0.1.20260920, where 15 generic impls in
/// `tuple/pkg.generated.mbti` produced 135 false positives — 2+3+...+16,
/// the sum of every impl's parameter arity.

///|
test "iface .mbti: a generic impl binds its own type parameters, but not a ghost" {
  // The target is `(A, Ghost)` — A is bound, Ghost is not. The test pins
  // that exactly one report fires, naming Ghost, and that the bound
  // parameters are NOT reported (which was the regression).
  let src = "package \"d\"\npub impl[A, B] Show for (A, Ghost)\n"
  let reports = @moonfiles.iface(src, "d.mbti")
  assert_eq(reports.length(), 1)
  assert_true(reports[0].message.contains("unknown type 'Ghost'"))
  for rep in reports {
    assert_false(rep.message.contains("unknown type 'A'"))
    assert_false(rep.message.contains("unknown type 'B'"))
  }
}

///
/// The exact shape moonbitlang/core emits: `pub impl[A : Default, B : Default]
/// Default for (A, B)`. Without the fix this line emits 2 reports; with the
/// fix, 0 (A and B are bound parameters; Default is builtin; the `(A, B)`
/// tuple refers to types already on the same line's bound list).

///|
test "iface .mbti: real generic impl with bounds has no findings" {
  let src = "package \"d\"\npub impl[A : Default, B : Default] Default for (A, B)\n"
  let reports = @moonfiles.iface(src, "d.mbti")
  // A, B are bound; Default is the bound type, which is a trait that the
  // analyzer does not require to be declared; the target tuple (A, B)
  // refers to types on the same line's bound list. Before the fix, this
  // line emitted 2 reports: unknown type 'A', unknown type 'B'.
  assert_eq(reports.length(), 0)
}

///
/// High-arity impl, the shape moonbitlang/core's `tuple` package uses 15
/// times. Before the fix, the 16-parameter impl emitted 16 false-positive
/// `unknown type` reports (one per parameter). After the fix, it emits 0.

///|
test "iface .mbti: a 16-parameter impl has no findings" {
  let src = "package \"d\"\npub impl[A : Default, B : Default, C : Default, D : Default, E : Default, F : Default, G : Default, H : Default, I : Default, J : Default, K : Default, L : Default, M : Default, N : Default, O : Default, P : Default] Default for (A, B, C, D, E, F, G, H, I, J, K, L, M, N, O, P)\n"
  let reports = @moonfiles.iface(src, "d.mbti")
  assert_eq(reports.length(), 0)
}

///

///|

///|

///|
/// The remaining shapes real generated interfaces use: value declarations
/// (`pub let`), re-exports (`pub using @pkg {type T as U}`), the `noraise`
/// error modifier, and the ArrayView / ReadOnlyArray builtin constructors.
test "iface .mbti: let declarations, using re-exports and noraise are understood" {
  let src = "package \"a\"\n\nimport {\n  \"a/types\",\n}\n\n// Values\npub let current_process : UInt\n\npub let platform : @types.Platform\n\npub async fn Cond::wait(Self) -> Unit noraise\npub async fn Cond::drop(Self) -> Unit cancel\npub async fn Cond::join(Self) -> Unit noraise cancel\npub fn take(ArrayView[Int], ReadOnlyArray[Byte]) -> Int\n\n// Type aliases\npub using @types {type Platform}\npub using @cond_var {type Cond as CondVar}\npub using @aqueue {type Queue}\n"
  let reports = @moonfiles.iface(src, "env_util.mbti")
  assert_eq(reports.length(), 0)
}

///

///|

///|

///|
/// The fence info string decides whether a block is code at all, and the
/// toolchain — not the doc wording — is the authority. Measured by putting an
/// unbound call in every candidate fence and asking `moon check` which ones it
/// complained about: a second word of `check` or `test` is what makes a block
/// live. A bare `mbt` is a DISPLAY fence, exactly like a bare `moonbit`.
///
/// Analysing a display-only block turned the one real .mbt.md in the workspace
/// into 31 findings, all of them false. The bare-`mbt` case was the same disease
/// one level up: the earlier version analysed blocks the toolchain never builds.
test "literate .mbt.md: only check/test fences are code, bare mbt is display" {
  let md = "```mbt nocheck\nfn skipped_nocheck() -> int {\n  missing_nocheck(1)\n}\n```\n\n```moonbit\nfn skipped_display() -> int {\n  missing_display(1)\n}\n```\n\n```mbt\nfn skipped_bare_mbt() -> int {\n  missing_bare_mbt(1)\n}\n```\n\n```mbt check\nfn doc_tested() -> int {\n  2\n}\n```\n\n```mbt test\nfn test_fenced() -> int {\n  3\n}\n```\n\n```moonbit check\nfn moonbit_checked() -> int {\n  4\n}\n```\n"
  let r = @moonfiles.literate(md, "doc.mbt.md")
  // the three display-only blocks contribute nothing, not even their names
  assert_eq(r.reports.length(), 0)
  // only the three live fences are analyzed
  assert_eq(r.sigs.length(), 3)
  assert_eq(r.sigs[0], "doc_tested() -> int")
  assert_eq(r.sigs[1], "test_fenced() -> int")
  assert_eq(r.sigs[2], "moonbit_checked() -> int")
}

///|

///|
/// The classification itself, spelled out, so a regression in one spelling does
/// not have to be rediscovered by running the toolchain again.
test "fence_mode: the full measured table" {
  // compiled
  assert_eq(@moonfiles.fence_mode("```mbt check"), Some(@moonfiles.FTest))
  assert_eq(@moonfiles.fence_mode("```mbt test"), Some(@moonfiles.FTest))
  assert_eq(@moonfiles.fence_mode("```moonbit check"), Some(@moonfiles.FTest))
  assert_eq(@moonfiles.fence_mode("```moonbit test"), Some(@moonfiles.FTest))
  // extra words are ignored, extra whitespace is fine
  assert_eq(@moonfiles.fence_mode("```mbt check extra"), Some(@moonfiles.FTest))
  assert_eq(@moonfiles.fence_mode("```mbt  check"), Some(@moonfiles.FTest))
  // display-only
  assert_eq(@moonfiles.fence_mode("```mbt"), Some(@moonfiles.FDisplay))
  assert_eq(@moonfiles.fence_mode("```moonbit"), Some(@moonfiles.FDisplay))
  assert_eq(@moonfiles.fence_mode("```mbt nocheck"), Some(@moonfiles.FNoCheck))
  assert_eq(
    @moonfiles.fence_mode("```moonbit nocheck"),
    Some(@moonfiles.FNoCheck),
  )
  // not a MoonBit fence at all
  assert_eq(@moonfiles.fence_mode("```json"), None)
  assert_eq(@moonfiles.fence_mode("```"), None)
  // the second word is case-sensitive: `mbt Check` is NOT compiled
  assert_false(@moonfiles.fence_mode("```mbt Check") == Some(@moonfiles.FTest))
  // no space means it is not a recognised word
  assert_false(@moonfiles.fence_mode("```mbtcheck") == Some(@moonfiles.FTest))
}

///|

///|
/// The shipped sample is the demo the CLI prints, so its fence mix is part of
/// the contract: 1 live fence, 3 display-only. The bare `mbt` block in it used
/// to be described as "a compiled block" in a comment AND counted as one in
/// the CLI's header string — both were wrong, and nothing pinned the numbers,
/// so they survived a release. The census is now computed, and this pins it.
test "fence_census: the shipped sample has 1 live fence and 3 display-only" {
  let (live, display) = @moonfiles.fence_census(@samples.literate_md)
  assert_eq(live, 1)
  assert_eq(display, 3)
}

///|
/// And the census must agree with what actually gets analysed.
test "the shipped sample yields exactly one analysed block, the mbt check one" {
  let blocks = @moonfiles.moonbit_fences(@samples.literate_md)
  assert_eq(blocks.length(), 1)
  let r = @moonfiles.literate(@samples.literate_md, "demo.mbt.md")
  // the one live fence carries the deliberate defect, and nothing else does
  assert_eq(r.reports.length(), 1)
  assert_true(r.reports[0].message.contains("vanish"))
  // `twice` lives in the bare-`mbt` block, which is display-only, so it must
  // NOT reach the signature table — that is the regression this pins
  assert_eq(r.sigs.length(), 1)
  assert_eq(r.sigs[0], "shrug() -> int")
}

///|

///|

///|
/// A compiled block that leaves the subset is reported ONCE. The subset lexer
/// has no keyword table, so `async fn main` used to parse `async` as a
/// variable — "undefined variable 'async'" — then cascade hundreds of
/// "unexpected token" behind it. Measured over the 12 real .mbt.md documents
/// in this workspace that was 2335 findings; now 89, all of them this one
/// message.
test "literate .mbt.md: a block outside the subset is reported once, not cascaded" {
  let md = "```mbt check\nasync fn main {\n  let xs = [1, 2]\n  debug(xs)\n}\n```\n"
  let r = @moonfiles.literate(md, "doc.mbt.md")
  assert_eq(r.reports.length(), 1)
  assert_eq(r.reports[0].family.name(), "ParseError")
  assert_true(
    r.reports[0].message.contains("outside the analyzer's MoonBit subset"),
  )
  // named after the word that put the block out of reach, and it does not
  // pretend the word was an undefined variable
  assert_true(r.reports[0].message.contains("'async'"))
  assert_false(r.reports[0].message.contains("undefined"))
  // nothing was analyzed, so nothing is claimed
  assert_eq(r.sigs.length(), 0)
  // the report lands on the .md file's real line, the one holding `async fn`
  assert_eq(r.reports[0].span.start.line, 2)
}

///

///|
/// A `test { .. }` block is a document-test entry, not a definition the
/// subset can read: same one-line treatment.
test "literate .mbt.md: a test block is reported once" {
  let md = "```mbt check\ntest \"forty two\" {\n  inspect(40 + 2, content=\"42\")\n}\n```\n"
  let r = @moonfiles.literate(md, "doc.mbt.md")
  assert_eq(r.reports.length(), 1)
  assert_true(r.reports[0].message.contains("'test'"))
  assert_eq(r.sigs.length(), 0)
}

///

///|
/// A compiled block that stays inside the subset is still fully analyzed — the
/// short-circuit must not swallow the blocks it is meant to leave alone.
test "literate .mbt.md: an in-subset compiled block is still analyzed" {
  let md = "```mbt check\nfn twice(n: int) -> int {\n  n * 2\n}\nprint(twice(21))\n```\n"
  let r = @moonfiles.literate(md, "doc.mbt.md")
  // the block was analyzed, not short-circuited: no exclusion finding, and the
  // definition reached the signature table
  assert_eq(r.reports.length(), 0)
  assert_eq(r.sigs.length(), 1)
  assert_true(r.sigs[0].has_prefix("twice(int) -> "))
}

///

///|
test "proof .mbtp: clean file has no findings" {
  let src = "///|\npredicate is_error(s : Severity) {\n  match s {\n    Error => true\n    _ => false\n  }\n}\n\n///|\nlemma one_zero() where {\n  proof_ensure: LStructural.rank() == 0,\n} {}\n"
  let reports = @moonfiles.proof(src, "core_proof.mbtp")
  assert_eq(reports.length(), 0)
}

///|
test "proof .mbtp: banned forms reported" {
  // string constant in a body
  let s1 = "predicate p(x : T) {\n  x.tag() == \"bad\"\n}\n"
  let r1 = @moonfiles.proof(s1, "p.mbtp")
  assert_eq(r1.length(), 1)
  assert_true(r1[0].message.contains("string constant"))
  // '!' outside '!='
  let s2 = "predicate q(x : T) {\n  !x.bad()\n}\n"
  let r2 = @moonfiles.proof(s2, "p.mbtp")
  assert_eq(r2.length(), 1)
  assert_true(r2[0].message.contains("banned form '!'"))
  // biconditional
  let s3 = "predicate r(x : T) {\n  x.ok() ↔ x.good()\n}\n"
  let r3 = @moonfiles.proof(s3, "p.mbtp")
  assert_eq(r3.length(), 1)
  assert_true(r3[0].message.contains("banned form '↔'"))
  // cross-package call
  let s4 = "predicate s(x : T) {\n  @json.is_obj(x)\n}\n"
  let r4 = @moonfiles.proof(s4, "p.mbtp")
  assert_eq(r4.length(), 1)
  assert_true(r4[0].message.contains("cross-package call"))
}

///|

///|
/// The negative controls for the proof lint. The four rules each have a
/// triggering test; without these, a rule could fire on every line it merely
/// resembles and the suite would still be green. Probed all nine cases
/// (4 triggers + 5 negatives) against the bridge: 9/9 behaved as documented.
///
///   !=  must not trip the '!'  rule
///   ->  must not trip the '↔'  rule
///   a predicate body must not be mistaken for a lemma (no proof_ensure to find)
///   a clean body must stay silent
test "proof .mbtp: legal forms are not mistaken for banned ones" {
  // '!=' contains '!' but is an equality operator, not a negation
  let ne = @moonfiles.proof(
    "predicate p(x : T) {\n  x.a() != x.b()\n}\n", "p.mbtp",
  )
  assert_eq(ne.length(), 0)
  // '->' is the one-directional implication, not the biconditional
  let arrow = @moonfiles.proof(
    "predicate q(a : T, b : T) {\n  a -> b\n}\n", "p.mbtp",
  )
  assert_eq(arrow.length(), 0)
  // a predicate has no proof_ensure to discharge, so the lemma rule must not
  // fire on it
  let pred = @moonfiles.proof("predicate r(x : T) {\n  x.ok()\n}\n", "p.mbtp")
  assert_eq(pred.length(), 0)
  // a real lemma that does discharge stays silent too
  let good = @moonfiles.proof(
    "///|\nlemma one_zero() where {\n  proof_ensure: LStructural.rank() == 0,\n} {}\n",
    "p.mbtp",
  )
  assert_eq(good.length(), 0)
}

///

///|
test "proof .mbtp: lemma without proof_ensure reported" {
  let src = "lemma empty() where {\n} {}\n"
  let reports = @moonfiles.proof(src, "p.mbtp")
  assert_eq(reports.length(), 1)
  assert_true(reports[0].message.contains("lemma without proof_ensure"))
}

// --- collect_iface_names: the type/value name extractor ------------------
//
// `collect_iface_names` reuses the same `parse_iface` as `iface`, so a
// `.mbti` that one accepts the other must accept too. The contract being
// pinned here: declared types go in `types`, value signatures and `const`
// declarations go in `values`, builtin / external / bound-parameter names
// do NOT go in either (they are not user-visible names we need to suppress
// false positives for, since the type lens already has them or treats them
// as TUnknown).

///|
test ".mbti: collect_iface_names separates types and values" {
  let src = "pub struct Command { name : String }\npub fn new_cmd() -> Command {\n  Command::{ name: \"\" }\n}\npub const VERSION : Int = 1\n"
  let tab = @moonfiles.collect_iface_names(src)
  assert_true(tab.has_type("Command"))
  assert_true(tab.has_value("new_cmd"))
  assert_true(tab.has_value("VERSION"))
  // builtins are not added (they are resolved another way)
  assert_false(tab.has_type("Int"))
  assert_false(tab.has_type("String"))
}

///|
test ".mbti: collect_iface_names handles impl with bounds" {
  // The 0.4.2 commit already fixed the impl-handler bug; the regression
  // check here is that the bound type parameters A, B, ... end up
  // nowhere in the symtab (they are local to the impl signature, not
  // declarations the rest of the package can name).
  let src = "pub impl[X : Show] Show for X with output(self : X) -> String {\n  \"\"\n}\n"
  let tab = @moonfiles.collect_iface_names(src)
  // X is a bound parameter, NOT a declared type
  assert_false(tab.has_type("X"))
  assert_false(tab.has_type("Show"))
}

///|
test ".mbti: collect_iface_names handles type alias and re-export" {
  let src = "pub type Fd = Int\npub using @other { type T as RenamedT }\n"
  let tab = @moonfiles.collect_iface_names(src)
  assert_true(tab.has_type("Fd"))
  // the re-exported name enters the symtab
  assert_true(tab.has_type("RenamedT"))
}

///|
/// The 0.4.4 defect this pins: a `.mbti` declares names BARE and a use site
/// spells the same name QUALIFIED, so an exact-match table made the whole
/// cross-file feature a silent no-op for cross-package references — the only
/// kind MoonBit code actually contains. Measured before the fix:
/// `has_value("@core.IfaceSymTab::empty")` answered `false` while
/// `has_value("IfaceSymTab::empty")` answered `true`.
test ".mbti: collect_iface_names resolves the @pkg.-qualified spelling" {
  let src = "pub fn IfaceSymTab::empty() -> Self\npub struct Walker { x : Int }\n"
  let tab = @moonfiles.collect_iface_names(src)
  // the declaration spelling
  assert_true(tab.has_value("IfaceSymTab::empty"))
  assert_true(tab.has_type("Walker"))
  // the use-site spelling — this is what the analyzer's EName carries
  assert_true(tab.has_value("@core.IfaceSymTab::empty"))
  assert_true(tab.has_type("@core.Walker"))
  // and a module-coordinate qualifier, which is what a dependency's use
  // site looks like
  assert_true(tab.has_value("@riantr/other.IfaceSymTab::empty"))
}

///|
/// Negative control for the test above, and the one that keeps the qualifier
/// rule from becoming "ignore everything that starts with `@`": stripping
/// the qualifier must not manufacture a hit. `@core.Missing` has no bare
/// form in the table and must stay absent.
test ".mbti: an unqualified miss does not become a hit by stripping" {
  let tab = @moonfiles.collect_iface_names("pub fn present() -> Self\n")
  assert_true(tab.has_value("present"))
  assert_true(tab.has_value("@anywhere.present"))
  assert_false(tab.has_value("@anywhere.absent"))
  assert_false(tab.has_value("absent"))
  // a bare `@` with no `.` is not a qualified name and stays a miss
  assert_false(tab.has_value("@present"))
  assert_false(tab.has_value("@"))
}

///|
test "unqualified leaves a bare name alone" {
  assert_eq(@core.unqualified("IfaceSymTab::empty"), "IfaceSymTab::empty")
  assert_eq(@core.unqualified("Int"), "Int")
  // `@foo` has no `.` — there is nothing to strip, so it comes back whole
  assert_eq(@core.unqualified("@foo"), "@foo")
  assert_eq(@core.unqualified(""), "")
  // the qualifier ends at the FIRST `.`; module coordinates are written
  // `author/module`, so they contain `/` and never a second `.`, which is
  // what makes the first one the right boundary
  assert_eq(@core.unqualified("@core.IfaceSymTab::empty"), "IfaceSymTab::empty")
  assert_eq(@core.unqualified("@riantr/other.Foo"), "Foo")
  assert_eq(@core.unqualified("@a.b.c.Name"), "b.c.Name")
}

///|
/// The end-to-end form of the 0.4.4 defect, and the test whose ABSENCE let it
/// ship. `pipeline_test.mbt` covers this same suppression, but it builds its
/// tables by hand — writing `"@core.IfaceSymTab::empty"` straight into
/// `values` — so it passed no matter what the collector actually produced.
/// The shipping table comes from a `.mbti`, and a `.mbti` writes the name
/// bare. Only a test that feeds a real `.mbti` through the real collector can
/// see the two spellings disagree, and this package is where it can be
/// written: `pipeline` cannot import `moonfiles` (that is a cycle, since
/// `moonfiles` calls `pipeline`), so the pairing test has to live here.
test ".mbti end-to-end: a collected table silences the qualified call" {
  let mbti = "pub fn IfaceSymTab::empty() -> Self\n"
  let tab = @moonfiles.collect_iface_names(mbti)
  let r = @pipeline.run("@core.IfaceSymTab::empty()\n", "x.mbt", tab)
  assert_eq(r.reports.length(), 0)
}

///|
/// The negative control for the test above, and the one that stops it from
/// passing for the wrong reason: if the pipeline had stopped consulting the
/// table altogether, "no reports" would be trivially true. A name the same
/// `.mbti` does not declare must still be reported.
test ".mbti end-to-end: a collected table still reports an undeclared name" {
  let mbti = "pub fn IfaceSymTab::empty() -> Self\n"
  let tab = @moonfiles.collect_iface_names(mbti)
  let r = @pipeline.run("@core.NotDeclared::gone()\n", "x.mbt", tab)
  let mut hits = 0
  for rep in r.reports {
    if rep.family.name() == "UndefinedName" {
      hits += 1
    }
  }
  assert_true(hits > 0)
}

///|
/// A `const`'s DEFAULT VALUE is an expression, not a type. `label_type`
/// splits the line on the first `:` and hands back `Byte = b'\xFF'` as the
/// type, so the identifiers in the value were collected as type references.
/// Measured on 0.4.5 against moonbitlang/core: `byte/pkg.generated.mbti`,
/// generated by `moon info` and accepted by `moon check` with 0 errors,
/// reported `unknown type 'b'` twice plus `unknown type 'xFF'` and
/// `unknown type 'x00'`.
test ".mbti: a const default value is not scanned for type references" {
  let src = "pub const MAX_VALUE : Byte = b'\\xFF'\npub const MIN_VALUE : Byte = b'\\x00'\npub const HEADER : String = \"hello\"\n"
  let reports = @moonfiles.iface(src, "x.mbti")
  assert_eq(reports.length(), 0)
}

///|
/// The same rule with the shapes that would break a naive cut at the first
/// `=`: a default whose own `=` is nested (`Map(capacity=8)`), a tuple type, a
/// negative number, and an `==` comparison. `String` and `Int` are builtins
/// here, so "no reports" means the values contributed no type references.
test ".mbti: nested, tuple and comparison defaults are not scanned either" {
  let src = "pub const A_TABLE : Map[String, Int] = Map(capacity=8)\npub const A_PAIR : (Int, Int) = (1, 2)\npub const NEG : Int = -1\npub const EQ_TEST : Int = 1 == 1\n"
  assert_eq(@moonfiles.iface(src, "x.mbti").length(), 0)
}

///|
/// ...and the negative control: the type on the LEFT of the `=` is still
/// checked, so this is not "stop looking at const lines".
test ".mbti: a const's declared type is still checked" {
  let src = "pub const FLAG : NoSuchType = 1\n"
  let reports = @moonfiles.iface(src, "x.mbti")
  assert_eq(reports.length(), 1)
  assert_true(reports[0].message.contains("NoSuchType"))
}
