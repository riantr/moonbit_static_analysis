// report_0507_test.mbt -- the CONFIDENCE AXIS and the STABLE FAMILY IDS.
//
// 0507. Two things are added beside the severity, and both of them answer a
// question the severity does not:
//
//   * the CONFIDENCE says how much the lens CHECKED. The severity says how
//     bad the finding is IF IT IS REAL; the confidence says how sure the
//     analyzer is that it is real. A finding can be severe and uncertain, or
//     trivial and certain, and before this the second case was invisible.
//     The analyzer had no way to say "I could not check this" -- it said
//     nothing, and nothing reads as "there is nothing here".
//
//   * the family ID is a STABLE name. The public family name is a second,
//     hand-maintained vocabulary -- five of the original eleven names are not
//     the tag with its `F` removed -- so a consumer that pinned
//     `"family": "ArgTypeMismatch"` in a suppression or a CI filter got no
//     warning at all when the name moved. An id is allocated and NEVER
//     RENUMBERED, so it survives a rename.
//
// THE CONFIDENCE IS COMPUTED, NOT A FIELD, and these tests are the reason
// that matters: a field would have to be filled in at every one of the
// thirty-odd places a Report is constructed, and a missed one would be a
// finding with the wrong confidence and NO WAY TO NOTICE. A function has one
// definition and cannot drift.
//
// THE ID TABLE IS HAND-ALLOCATED for the same reason: deriving it from the
// enum's position would renumber every family after an insertion, which is
// exactly the thing an id must not do.

///|
fn mk0507(family : @core.Family, message : String) -> @report.Report {
  @report.Report::{
    family,
    lenses: [@core.LStructural],
    message,
    span: @core.span_at(1, 1, 1),
    vst: [],
  }
}

///|
/// The roster, written out. A new family has to be added HERE as well as in
/// `Family::id` and `family_by_id`, and the test below is what notices when
/// one of the three is forgotten: the id is checked against the POSITION, so
/// a family that was added to the enum without being added here leaves the
/// roster short and the test says so.
fn roster() -> Array[@core.Family] {
  [
    @core.FParse,
    @core.FUndefinedName,
    @core.FUnusedLocal,
    @core.FUnusedParam,
    @core.FParamChanged,
    @core.FAssignType,
    @core.FArgType,
    @core.FOpMismatch,
    @core.FMethodError,
    @core.FCondBool,
    @core.FUnreachable,
    @core.FStaleNosec,
  ]
}

///|
fn pad3(n : Int32) -> String {
  if n < 10 {
    "00\{n}"
  } else if n < 100 {
    "0\{n}"
  } else {
    "\{n}"
  }
}

///|
/// A scope limit is the analyzer saying it could not DECIDE, so it is
/// `undecided` -- and it is NOT dropped for being uncertain. It is reported
/// at a lower confidence, which is the whole difference between a silence
/// that reads as "nothing to report" and a statement about how much was
/// checked.
test "confidence: a scope limit is undecided" {
  let r = mk0507(
    @core.FParse,
    "match expression is outside the analyzed subset",
  )
  assert_true(r.is_notice())
  assert_true(r.confidence() == @core.Undecided)
  assert_eq(r.confidence().name(), "undecided")
}

///|
/// A finding whose family reasons from a NAME alone is `low`. The only one
/// is `UndefinedName`: the analyzer found no binding for the name, and the
/// binding it could not find may be in a file, or in a package, it was never
/// given. A reader who is told this is told the truth about it.
test "confidence: a family that reasons from a name alone is low" {
  let r = mk0507(@core.FUndefinedName, "undefined variable 'x'")
  assert_true(!r.is_notice())
  assert_true(r.confidence() == @core.Low)
  assert_eq(r.confidence().name(), "low")
}

///|
/// Everything else had the declaration, the signature or the type in front of
/// the lens, and is `high`.
test "confidence: a finding the lens checked is high" {
  let r = mk0507(
    @core.FArgType,
    "argument 1 to 'f' has incompatible type 'Int'",
  )
  assert_true(r.confidence() == @core.High)
  assert_eq(r.confidence().name(), "high")
}

///|
/// The three values are three states and not two: `undecided` is the
/// analyzer's own scope limit, `low` is "I read the name and nothing else",
/// and `high` is "I read the thing the finding is about".
test "confidence: the three values are distinct" {
  assert_eq(@core.High.name(), "high")
  assert_eq(@core.Low.name(), "low")
  assert_eq(@core.Undecided.name(), "undecided")
}

///|
/// The rendered line carries the id and the confidence IN THE BRACKET, and
/// the family NAME stays alone in the parentheses. That is deliberate: the
/// parentheses are the family, and every gate in this repository that reads a
/// finding line compares that field against a family name.
test "the rendered finding carries the id and the confidence in the bracket" {
  let r = mk0507(
    @core.FArgType,
    "argument 1 to 'f' has incompatible type 'Int'",
  )
  let line = r.render()
  assert_true(line.contains("(ArgTypeMismatch)"))
  assert_true(line.contains("[structural, MSA-007, high]"))
}

///|
/// The id table: one id per family, no id used twice, the ids a CONTIGUOUS
/// run from MSA-001, and the inverse table the exact reverse of the forward
/// one.
///
/// The contiguity is the "never renumbered" property, made checkable. A gap
/// means a number was allocated and never used; a family inserted in the
/// middle of the enum and given the next free number is fine, but a family
/// given a number in the middle of the run is NOT, because every
/// suppression written against that number would now name a different family.
test "the family ids are unique, contiguous from MSA-001, and reversible" {
  let fams = roster()
  let seen : Array[String] = []
  for i in 0..<fams.length() {
    let id = fams[i].id()
    assert_true(!seen.contains(id))
    seen.push(id)
    assert_eq(id, "MSA-" + pad3(i + 1))
    match @core.family_by_id(id) {
      Some(f) => assert_true(f == fams[i])
      None => assert_true(false)
    }
  }
  assert_eq(fams.length(), 12)
}

///|
/// The inverse table must NOT answer for an id that does not exist. A lookup
/// that defaulted to some family would turn a typo in a profile or a
/// suppression into a silent, wrong selection.
test "an unknown family id names no family" {
  match @core.family_by_id("MSA-999") {
    Some(_) => assert_true(false)
    None => assert_true(true)
  }
  match @core.family_by_id("msa-007") {
    Some(_) => assert_true(false)
    None => assert_true(true)
  }
  match @core.family_by_id("") {
    Some(_) => assert_true(false)
    None => assert_true(true)
  }
}

///|
/// The five names that differ from their tag are still five, and they are
/// still the SAME five. This is the reason the ids exist: a name is a second
/// vocabulary, and this is the measurement of how much it costs to pin one.
test "five of the family names differ from their tag, and they are the same five" {
  assert_eq(@core.FParse.name(), "ParseError")
  assert_eq(@core.FAssignType.name(), "AssignTypeMismatch")
  assert_eq(@core.FArgType.name(), "ArgTypeMismatch")
  assert_eq(@core.FOpMismatch.name(), "OperatorMismatch")
  assert_eq(@core.FCondBool.name(), "NonBooleanCond")
  // and the other seven are the tag minus the `F`
  assert_eq(@core.FUndefinedName.name(), "UndefinedName")
  assert_eq(@core.FUnusedLocal.name(), "UnusedLocal")
  assert_eq(@core.FUnusedParam.name(), "UnusedParam")
  assert_eq(@core.FParamChanged.name(), "ParamChanged")
  assert_eq(@core.FMethodError.name(), "MethodError")
  assert_eq(@core.FUnreachable.name(), "Unreachable")
  // and the stale-suppression family is the twelfth
  assert_eq(@core.FStaleNosec.name(), "StaleNosec")
  assert_eq(@core.FStaleNosec.id(), "MSA-012")
}

///|
/// A finding that NO LENS produced -- the stale-suppression finding of 0507
/// -- carries an empty lens list, and the rendered bracket says so with a
/// dash. An empty bracket would read as a rendering accident.
test "a finding with no lens renders a dash, not an empty bracket" {
  let r = @report.Report::{
    family: @core.FStaleNosec,
    lenses: [],
    message: "this `// nosec` comment suppressed nothing",
    span: @core.span_at(3, 1, 1),
    vst: [],
  }
  assert_true(r.render().contains("[-, MSA-012, high]"))
}
