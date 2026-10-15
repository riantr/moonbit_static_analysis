//| Tests for 0.4.41: a QUOTED key in a brace literal is a MAP literal, and this
//| parser had no production for one.
//
//| THE DEFECT. Three of the twelve files moui 0.1.12 still cannot finish reading
//| cut at a `{`:
//!
//!     (
//!       {
//!         "schemaVersion": envelope.schema_version,
//!       } : Json).stringify()
//!
//! Those keys are QUOTED. A quoted key is not a struct-literal field name, so the
//! braces here are a MAP literal -- and `parse_struct_fields` reported
//! `expected a struct literal field here`, which set the file's `first_error` and
//! marked it NOTPARSE.
//!
//| WHAT MADE THIS LOOK LIKE SOMETHING ELSE. Nine fixtures said this construct
//! parses, and they were all right -- about a different form. The SAME increment's
//! settle had already measured `{ "schemaVersion": 1, .. } : Json` as REJECT(4014)
//! against a struct, which is the toolchain correctly saying that a quoted key is
//! not a field name. Every fixture written after that switched to unquoted keys,
//! and unquoted keys are a STRUCT LITERAL, which this parser has always read. Nine
//! green results about the wrong language form.
//!
//| So the first test below is deliberately the one the old fixtures would have
//! written, with UNQUOTED keys, and it asserts the struct reading still holds. The
//! two forms cannot be merged -- `moon check` accepts `{ a: 1 }` against a struct
//! and REFUSES it against a Map while accepting `{ "a": 1 }` there -- and that pair
//! is the whole constraint on the fix.

///|
/// `parse_failures` is NOT redefined here: it lives in `pipeline_0450_test`'s
/// package-mate and is reused, because a second copy of "exclude the declared scope
/// limits" is a second copy that can drift. A duplicate toplevel is a `[4051]`
/// build error, which is at least loud; the risk being avoided is the quiet one --
/// the two copies disagreeing about which messages are scope limits.
///
/// Parse FAILURES, excluding the DECLARED SCOPE LIMITS. Both share the ParseError
/// family with real read failures, so counting the family counts a deliberate and
/// correct notice as a defect. The exclusion is the pipeline's own rule
/// (`pipeline.mbt:143`), not a list of the notices this file happened to meet.

///|
/// THE SHAPE, verbatim apart from the target type, which is a stand-in for moui's
/// `Json`: `{"a": 1}` as `Map[String, Int]` is ACCEPTed by `moon check`
/// (`_verify/settle_0452_quoted_key_map.ps1`), and the same spelling against a
/// struct is REJECT(4014) -- which is the measurement that told the earlier
/// fixtures they were writing a different form.
test "0452: a quoted-key brace literal is read as a map literal" {
  let r = @pipeline.run(
    "///|\npub struct Json {\n  raw : Int\n}\n\n///|\nfn Json::stringify(self : Json) -> Int {\n  self.raw\n}\n\n///|\npub fn Holder::dump(self : Holder) -> Int {\n  let e = self.take()\n  (\n    {\n      \"schemaVersion\": e,\n    } : Map[String, Int]).stringify()\n}\n\n///|\npub struct Holder {\n  a : Int\n}\n\n///|\nfn Holder::take(self : Holder) -> Int {\n  self.a\n}\n",
    "host_transport.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(parse_failures(r), 0)
}

///|
/// AND THE MAP LITERAL IS ACTUALLY READ, not merely stepped over. A fix that
/// skipped the braces would satisfy the test above and leave the rest of the file
/// unread, which is the failure this whole increment exists to stop.
///
/// IT IS IN A `let` INITIALIZER, and that is not styling. A bare `{ .. }` in
/// STATEMENT position is a BLOCK and always was -- `parse_stmt` reads a leading
/// `{` as a block, so a map literal only reaches this production in expression
/// position. Three fixtures here failed their first run for exactly that reason,
/// and the fix is to place the braces where the corpus places them.
/// `count_family(r, "ParseError")` is then 1: the one `pub struct` skip notice.
test "0452: the map literal's values are read, not stepped over" {
  let r = @pipeline.run(
    "///|\npub fn Holder::dump(self : Holder) -> Map[String, Int] {\n  let e = self.take()\n  let m = {\n    \"schemaVersion\": e,\n  }\n  m\n}\n\n///|\npub struct Holder {\n  a : Int\n}\n\n///|\nfn Holder::take(self : Holder) -> Int {\n  self.a\n}\n",
    "values.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(parse_failures(r), 0)
  // One `pub struct` in the fixture, one declared-scope-limit notice about it.
  assert_eq(count_family(r, "ParseError"), 1)
  // And `e` is USED. It is bound by `let e = self.take()` and read as the
  // literal's value, so a fix that consumed the value without analysing it would
  // leave `e` dead and report it here. That is the assertion that distinguishes
  // "the braces were read" from "the braces were stepped over", which the two
  // counts above cannot: a stepped-over literal produces neither a parse error
  // nor a lost notice.
  assert_eq(count_family(r, "UnusedLocal"), 0)
}

///|
/// THE CONSTRAINT ON THE FIX, and the test that makes it binding: the UNQUOTED
/// spelling is a STRUCT LITERAL and must keep being read as one. A fix that
/// accepted any brace followed by a colon, or that routed both forms through the
/// map path, passes the first test and fails this one.
test "0452: an unquoted key is still a struct literal field" {
  let r = @pipeline.run(
    "///|\npub fn Holder::make(a : Int) -> Holder {\n  { a: a }\n}\n\n///|\npub struct Holder {\n  a : Int\n}\n",
    "struct_literal.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(parse_failures(r), 0)
}

///|
/// Whether any ParseError-family report carries `needle`. Named apart from the
/// other helpers in this package so it cannot collide with them.
///
/// ADDED AFTER A GATE CAUGHT IT. This test used to assert `parse_failures == 2`
/// and M2 -- making the colon optional -- SURVIVED it, because `{ "a" }` still
/// fails under M2, just with `expected '}'` where the test expected `expected ':'`.
/// A COUNT cannot tell two different complaints apart, so it kept passing while the
/// property it was written for was gone.
///
/// The message is the assertion. Not `>= 1` either: that would pass just as
/// happily if the recovery stopped working entirely, which is the opposite of what
/// this test is for.
fn reports_containing(r : @pipeline.PipelineResult, needle : String) -> Bool {
  for rep in r.reports {
    if rep.family.name() == "ParseError" && rep.message.contains(needle) {
      return true
    }
  }
  false
}

///|
/// A QUOTED KEY REQUIRES A COLON, because the shorthand has no meaning: there is
/// no field named by a string, and `{ "a" }` is code the toolchain rejects. If the
/// fix had accepted a bare string as a field, this fixture would parse and it must
/// not.
test "0452: a quoted key without a colon is reported as a missing colon" {
  let r = @pipeline.run(
    "///|\nfn probe() -> Map[String, Int] {\n  let m = { \"a\" }\n  m\n}\n",
    "no_colon.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(reports_containing(r, "expected ':'"), true)
}

///|
/// AND A GENUINELY MALFORMED LITERAL STILL COSTS ONLY ITS OWN BLOCK. The recovery
/// path matters more than the accept path: a parse error that moves `first_error`
/// truncates the file, and truncating the file is what turned one unreadable
/// construct into several unreadable files over and over in this repository.
///
/// The failing literal is followed by two more declarations, and the test asserts
/// the file's own structure survived -- `probe` is still called at the end.
test "0452: a malformed map literal does not cost the rest of the file" {
  let r = @pipeline.run(
    "///|\nfn probe() -> Int {\n  let m = { 1 }\n  2\n}\n\n///|\nfn after_one() -> Int {\n  3\n}\nafter_one()\n",
    "recovery.mbt",
    @core.IfaceSymTab::empty(),
  )
  // The literal is reported...
  assert_eq(parse_failures(r), 1)
  // ... and nothing after it was reported as an undefined name, which is what
  // truncation would have produced.
  assert_eq(count_family(r, "UndefinedName"), 0)
}
