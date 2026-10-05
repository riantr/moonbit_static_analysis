// Black-box invariant tests for the toolchain file kinds (.mbt.md / .mbti /
// .mbtp) — see EXTENSIONS.md for the taxonomy these tests encode.

///|
test "literate .mbt.md: fences analyzed with real line numbers" {
  let md = "# Title\n\nIntro prose.\n\n```moonbit\nfn ok_fn() -> int {\n  1\n}\n```\n\nMore prose.\n\n```moonbit\nfn broken() -> int {\n  missing(1)\n}\n```\n"
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
  let md = "```json\n{\"not\": \"code\"}\n```\n\n```moonbit\nfn f() -> int {\n  2\n}\n```\n"
  let r = @moonfiles.literate(md, "doc.mbt.md")
  assert_eq(r.reports.length(), 0)
  assert_eq(r.sigs.length(), 1)
}

///|
test "literate .mbt.md: blocks are independent (no cross-block bindings)" {
  let md = "```moonbit\nfn helper() -> int {\n  1\n}\n```\n\n```moonbit\nfn caller() -> int {\n  helper()\n}\n```\n"
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
  let src =
    "// Generated using `moon info`, DON'T EDIT IT\npackage \"moonbitlang/async/io\"\n\nimport {\n  \"moonbitlang/core/debug\",\n}\n\n// Values\npub fn pipe() -> (PipeRead, PipeWrite)\n\n// Errors\npub suberror PipeClosed derive(ToJson, @debug.Debug)\n#deprecated\npub impl Show for PipeClosed\n\npub(all) suberror ReaderClosed derive(ToJson, @debug.Debug)\n#deprecated\npub impl Show for ReaderClosed\n\n// Types and methods\ntype BufferedWriter[W]\npub fn[W] BufferedWriter::capacity(Self[W]) -> Int\npub async fn[W : Writer] BufferedWriter::flush(Self[W]) -> Unit\npub impl[W : Writer] Writer for BufferedWriter[W]\n\npub(all) enum Encoding {\n  UTF8\n}\n\ntype MemoryReader\n#callsite(autofill(loc))\npub fn MemoryReader::MemoryReader(async (&Writer) -> Unit, loc~ : SourceLoc) -> Self\npub async fn MemoryReader::read_some(Self) -> String?\npub fn MemoryReader::drop(Self, Int) -> Int\npub impl Reader for MemoryReader\n\ntype PipeRead\ntype PipeWrite\ntrait Writer\ntrait Data\npub impl Data for String\npub fn &Data::text(Self) -> String raise\n\npub const HEADER_SIZE : Int = 10\npub const STAT_FILE_SIZE : UInt = 0x0020\n\n// Type aliases\npub type Fd = Int\n"
  let reports = @moonfiles.iface(src, "io.mbti")
  assert_eq(reports.length(), 0)
}

///
///|
test "iface .mbti: labeled and optional parameters name types, not labels" {
  // `input_offset?` is a parameter name and `Int` is its type. Splitting the
  // parameter list on bare commas used to yield "input_offset? : Int" as an
  // unknown type.
  let src =
    "type Decoder\npub fn Decoder::write(Self, Bytes, FixedArray[Byte], input_offset? : Int, output_offset? : Int) -> (Int, Int) raise\n"
  let reports = @moonfiles.iface(src, "d.mbti")
  assert_eq(reports.length(), 0)
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
///|
///|
///|
/// The remaining shapes real generated interfaces use: value declarations
/// (`pub let`), re-exports (`pub using @pkg {type T as U}`), the `noraise`
/// error modifier, and the ArrayView / ReadOnlyArray builtin constructors.
test "iface .mbti: let declarations, using re-exports and noraise are understood" {
  let src =
    "package \"a\"\n\nimport {\n  \"a/types\",\n}\n\n// Values\npub let current_process : UInt\n\npub let platform : @types.Platform\n\npub async fn Cond::wait(Self) -> Unit noraise\npub async fn Cond::drop(Self) -> Unit cancel\npub async fn Cond::join(Self) -> Unit noraise cancel\npub fn take(ArrayView[Int], ReadOnlyArray[Byte]) -> Int\n\n// Type aliases\npub using @types {type Platform}\npub using @cond_var {type Cond as CondVar}\npub using @aqueue {type Queue}\n"
  let reports = @moonfiles.iface(src, "env_util.mbti")
  assert_eq(reports.length(), 0)
}

///
///|
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
test "proof .mbtp: lemma without proof_ensure reported" {
  let src = "lemma empty() where {\n} {}\n"
  let reports = @moonfiles.proof(src, "p.mbtp")
  assert_eq(reports.length(), 1)
  assert_true(reports[0].message.contains("lemma without proof_ensure"))
}
