// report_0523_test.mbt -- A FINDING AS A MACHINE-CHECKABLE ASSERTION.
//
// 0523. `Report::predicate` reads the subject out of the finding's MESSAGE, which
// is a liability by construction: rename a message and the JSON silently stops
// carrying a predicate. These tests pay that liability off by pinning every check
// against the REAL message text the emitter produces, so a message edit goes RED
// here instead of going quiet in the wire format.
//
// The texts below are copied from the construction sites, not invented:
//   no visible binding for 'x'          src/walk/walk.mbt:393
//   undefined name 'n'                  src/types/infer.mbt:286
//   local variable 'v' ...              src/walk/walk.mbt:683
//   parameter 'p' may not be used       src/walk/walk.mbt:672
//   parameter 'q' changed ...           src/walk/walk.mbt:663
//   this branch can never run: 'x' ...  src/walk/guardfacts.mbt (0522)
//   this test decides nothing: 'x' ...  src/walk/guardfacts.mbt (0522)

///|
/// A report with a family, a message and a position: everything the projection
/// reads.
fn mk0523(fam : @core.Family, msg : String, line : Int32) -> @report.Report {
  @report.Report::{
    family: fam,
    lenses: [@core.LStructural],
    message: msg,
    span: { start: { line, col: 3, }, end: { line, col: 9, }, },
    vst: [],
  }
}

///|
/// One argument of a predicate, read by name.
fn arg0523(p : @report.Predicate, key : String) -> String {
  for pair in p.params {
    if pair.0 == key {
      return pair.1
    }
  }
  ""
}

///|
/// The FIRST NAME-SHAPED CHECK. Both spellings of the undefined-name claim --
/// the structural `no visible binding for` and the type lens's `undefined name`
/// -- carry the SAME check id, because they assert the same thing about the same
/// name. Two spellings, one assertion: that is what the check id is for.
test "0523: undefined name carries its name under one check id" {
  let a = mk0523(@core.FUndefinedName, "no visible binding for 'helper'", 7)
  match a.predicate() {
    Some(p) => {
      assert_eq(p.check, "no_visible_binding")
      assert_eq(arg0523(p, "name"), "helper")
      assert_eq(arg0523(p, "line"), "7")
      assert_eq(arg0523(p, "col"), "3")
    }
    None => fail("the structural undefined-name finding must be checkable")
  }
  let b = mk0523(@core.FUndefinedName, "undefined name 'n'", 2)
  match b.predicate() {
    Some(p) => {
      assert_eq(p.check, "no_visible_binding")
      assert_eq(arg0523(p, "name"), "n")
    }
    None => fail("the type lens's undefined-name finding must be checkable")
  }
}

///|
/// THE THREE NAME-SHAPED UNUSED FAMILIES, each with its own check id: they are
/// different questions (a local, a parameter, a rebound parameter) and a
/// consumer that switches on one must not be handed another.
test "0523: the unused families each carry their own check" {
  let unread = mk0523(
    @core.FUnusedLocal,
    "local variable 'v' assigned but may not be used",
    11,
  )
  match unread.predicate() {
    Some(p) => {
      assert_eq(p.check, "local_never_read")
      assert_eq(arg0523(p, "name"), "v")
    }
    None => fail("an unread local must be checkable")
  }
  let param = mk0523(@core.FUnusedParam, "parameter 'p' may not be used", 4)
  match param.predicate() {
    Some(p) => {
      assert_eq(p.check, "param_never_read")
      assert_eq(arg0523(p, "name"), "p")
    }
    None => fail("an unread parameter must be checkable")
  }
  let changed = mk0523(
    @core.FParamChanged,
    "parameter 'q' changed by assignment",
    5,
  )
  match changed.predicate() {
    Some(p) => {
      assert_eq(p.check, "param_reassigned")
      assert_eq(arg0523(p, "name"), "q")
    }
    None => fail("a rebound parameter must be checkable")
  }
}

///|
/// 0522's TWO FAMILIES carry their subject too, so the empty-domain claim can be
/// checked by finding the binding and reading the guards the message names.
test "0523: the constraint families carry their subject" {
  let empty = mk0523(
    @core.FInfeasibleBranch,
    "this branch can never run: 'x' has an empty domain, D[P] = { }, because x > 5 (line 2) contradicts x < 3",
    3,
  )
  match empty.predicate() {
    Some(p) => {
      assert_eq(p.check, "path_domain_empty")
      assert_eq(arg0523(p, "name"), "x")
      assert_eq(arg0523(p, "line"), "3")
    }
    None => fail("an empty-domain finding must be checkable")
  }
  let implied = mk0523(
    @core.FRedundantGuard,
    "this test decides nothing: 'n' already satisfies n > 5 on the way here, so the other branch has an empty domain",
    8,
  )
  match implied.predicate() {
    Some(p) => {
      assert_eq(p.check, "guard_already_forced")
      assert_eq(arg0523(p, "name"), "n")
    }
    None => fail("a redundant-guard finding must be checkable")
  }
}

///|
/// THE POSITION-SHAPED CHECKS. `Unreachable` quotes a keyword rather than a name
/// (`statement after 'return'`) and `StaleNosec`'s whole claim IS its line, so
/// neither may be given a name argument -- a consumer that read one would be
/// reading the keyword `return` as an identifier.
test "0523: unreachable and stale-nosec are position-shaped, not name-shaped" {
  let un = mk0523(
    @core.FUnreachable,
    "statement after 'return' is unreachable",
    19,
  )
  match un.predicate() {
    Some(p) => {
      assert_eq(p.check, "after_flow_exit")
      assert_eq(arg0523(p, "line"), "19")
      assert_eq(arg0523(p, "name"), "")
    }
    None => fail("an unreachable statement must be checkable by position")
  }
  let stale = mk0523(@core.FStaleNosec, "no finding of MSA-002 here", 30)
  match stale.predicate() {
    Some(p) => {
      assert_eq(p.check, "suppression_matches_no_finding")
      assert_eq(arg0523(p, "line"), "30")
      assert_eq(p.params.length(), 1)
    }
    None => fail("a stale suppression must be checkable by line")
  }
}

///|
/// THE DELIBERATE ABSENCES. A parse finding is a statement about what the
/// analyzer READ, and a type family's claim is a relation a consumer would have
/// to reimplement the type model to check. Both return NO predicate, and the
/// absence is what tells a consumer "do not treat this as a re-checkable claim".
test "0523: a scope limit and a type claim have no predicate" {
  assert_true(
    mk0523(@core.FParse, "struct body is outside the analyzed subset", 3).predicate()
    is None,
  )
  assert_true(
    mk0523(@core.FArgType, "'String' is not assignable to 'Int'", 3).predicate()
    is None,
  )
  assert_true(
    mk0523(@core.FOpMismatch, "operand of '!' must be bool", 3).predicate()
    is None,
  )
}

///|
/// THE FAIL-SAFE. A name-shaped family whose message has lost its quotes must
/// yield NO predicate. The alternative -- a predicate whose `name` is the empty
/// string -- is the one value a checker cannot distinguish from a real name, and
/// it would be checked against the source as if it meant something.
test "0523: a name-shaped family with no quoted subject refuses a predicate" {
  let bare = mk0523(@core.FUndefinedName, "undefined name", 6)
  assert_true(bare.predicate() is None)
  let half = mk0523(
    @core.FUnusedLocal,
    "local variable 'v assigned but may not",
    6,
  )
  assert_true(half.predicate() is None)
}

///|
/// And the rendered form agrees with the projection, because the two are built
/// from one value rather than two derivations.
test "0523: the rendered predicate shows the check and its arguments" {
  let r = mk0523(
    @core.FUnusedLocal,
    "local variable 'v' assigned but may not be used",
    11,
  )
  match r.predicate() {
    Some(p) => {
      let text = p.render()
      assert_true(text.has_prefix("local_never_read("))
      assert_true(text.contains("name=v"))
      assert_true(text.contains("line=11"))
    }
    None => fail("expected a predicate to render")
  }
}
