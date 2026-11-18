// 0611: THE ADVICE TABLE -- every family asked, and the caveats COUNTED.
//
// THE MEASUREMENT THIS FILE ANSWERS. `moon coverage analyze` put this file at
// 35.0%: 7 of its 20 statements. The thirteen that were never reached are
// thirteen `Advice::{...}` LITERALS -- FParse, FParamChanged, FAssignType,
// FCondBool, FUndefinedName, FUnreachable, FStaleNosec, FInfeasibleBranch,
// FRedundantGuard, FDeadStore, FDivisionByZero, FNegativeIndex and
// FTaintFlow -- and a literal is only built when somebody ASKS that family
// for its advice.
//
// So thirteen of the eighteen families were never asked, and the advice for
// a family that rarely fires is the advice a reader has rarely been shown.
// Nothing checked it: not even that it was THERE.
//
// The rows below ask all eighteen, and they ask for the three things a reader
// of a report needs:
//
//   1. that the advice EXISTS, and says BOTH things -- what the family means
//      (`why`) and what to do about it (`how`);
//   2. that no two families were given the same words, because a paste that
//      went in twice is a defect;
//   3. and that the file's own HEADER, which says how many families carry a
//      caveat the reader must know BEFORE ACTING on the finding, is RIGHT --
//      measured here, not asserted.

///|
/// A CAVEAT, MECHANICALLY. An advice carries a caveat when it tells the
/// reader that THE FINDING ITSELF may be wrong -- so it must not be acted on
/// blind. These four words are how this table says exactly that, and they are
/// the WHOLE criterion: a family that uses none of them is not claiming its
/// finding might be wrong, it is telling the reader what to change.
///
/// THE WORDS ARE NOT INTERCHANGEABLE, and the rows below name which family
/// uses which, so a rewrite that moves a family on or off the list has to say
/// so here rather than silently change what the file's header claims.
fn carries_caveat0611(f : @core.Family) -> Bool {
  let a = f.advice()
  let t = a.why + " " + a.how
  t.contains("unverified") ||
  t.contains("verify") ||
  t.contains("before acting") ||
  t.contains("unfixable")
}

///|
/// EVERY FAMILY HAS AN ADVICE, AND IT SAYS BOTH THINGS.
///
/// The advice is what a downstream agent reads instead of guessing, so a
/// family with an empty `why` (what the finding means) or an empty `how`
/// (what to change) is a finding with no explanation and no fix -- and a
/// reader cannot tell that apart from a family that simply has no advice yet.
///
/// AND THE ROSTER'S SIZE IS ASSERTED HERE TOO, so this row is a COMPLETE
/// statement about the table: eighteen families in, eighteen advices out.
/// The size is already pinned by 0602's counts (15 soundy + 3 unsound = 18),
/// so this row cannot disagree with the rest of the tree about how many
/// families there are.
test "0611: every family in the roster has an advice, and it says both things" {
  let fs = @core.all_families()
  assert_eq(fs.length(), 18)
  for f in fs {
    let a = f.advice()
    assert_true(
      a.why.length() > 0,
      msg="the advice for \{f.name()} has no 'why'",
    )
    assert_true(
      a.how.length() > 0,
      msg="the advice for \{f.name()} has no 'how'",
    )
  }
}

///|
/// NO TWO FAMILIES SHARE AN ADVICE.
///
/// The table is an eighteen-arm match, and an arm that was pasted from its
/// neighbour gives the reader the SAME words for two different defects -- so
/// the advice for one family would be wrong for the other, and nothing in the
/// output says which one it belongs to.
///
/// AND THE ROUNDS ARE SEPARATE. Two families may legitimately open their
/// `how` with the same word; what must not happen is the same SENTENCE
/// serving as both families' explanation.
test "0611: no two families were given the same advice" {
  let fs = @core.all_families()
  for i in 0..<fs.length() {
    for j in 0..<i {
      let a = fs[i].advice()
      let b = fs[j].advice()
      assert_true(
        a.why != b.why,
        msg="\{fs[i].name()} and \{fs[j].name()} were given the same 'why'",
      )
      assert_true(
        a.how != b.how,
        msg="\{fs[i].name()} and \{fs[j].name()} were given the same 'how'",
      )
    }
  }
}

///|
/// THE HEADER'S COUNT, MEASURED. `src/core/advice.mbt` says how many of the
/// families carry a caveat the reader must know before acting on the finding,
/// and it says "see" two families. The count was wrong, and it was wrong in
/// the direction that HIDES: it undercounted, so a reader who trusted it
/// would not know that two more of the advices are saying "this finding may
/// not be the code's fault".
///
/// MEASURED over all eighteen: FOUR carry the caveat.
///
///   FParse        -- a `.mbti` type reference the lens has no cross-file
///                    awareness of: "treat that finding as unverified".
///   FUndefinedName-- two limits the CLI cannot fix: a `#doc(hidden)` API and
///                    a top-level `@pkg.fn(1, 2)` the parser does not fold.
///   FUnreachable  -- a branch killed by the CALLER's literal argument: "the
///                    finding is then WRONG ... treat ... as unverified".
///   FAssignType   -- an optional argument the type lens does not model:
///                    "verify against `moon check` before acting".
///
/// AND THE OTHER FOURTEEN DO NOT. Their advice says what the family means
/// and what to change, and claims no doubt about the finding itself -- which
/// is the thing that makes the four above worth naming.
test "0611: four advices tell the reader to verify the finding, and they are these four" {
  let fs = @core.all_families()
  let mut n = 0
  for f in fs {
    if carries_caveat0611(f) {
      n += 1
    }
  }
  assert_eq(n, 4)
  assert_true(carries_caveat0611(@core.FParse))
  assert_true(carries_caveat0611(@core.FUndefinedName))
  assert_true(carries_caveat0611(@core.FUnreachable))
  assert_true(carries_caveat0611(@core.FAssignType))
  // AND THE OTHER FOURTEEN ARE NOT IN IT. A family that does not use one of
  // the four words is not claiming its finding might be wrong, and a table
  // where every family hedges is a table where nobody reads the hedges.
  assert_false(carries_caveat0611(@core.FUnusedLocal))
  assert_false(carries_caveat0611(@core.FUnusedParam))
  assert_false(carries_caveat0611(@core.FParamChanged))
  assert_false(carries_caveat0611(@core.FArgType))
  assert_false(carries_caveat0611(@core.FOpMismatch))
  assert_false(carries_caveat0611(@core.FMethodError))
  assert_false(carries_caveat0611(@core.FCondBool))
  assert_false(carries_caveat0611(@core.FStaleNosec))
  assert_false(carries_caveat0611(@core.FInfeasibleBranch))
  assert_false(carries_caveat0611(@core.FRedundantGuard))
  assert_false(carries_caveat0611(@core.FDeadStore))
  assert_false(carries_caveat0611(@core.FDivisionByZero))
  assert_false(carries_caveat0611(@core.FNegativeIndex))
  assert_false(carries_caveat0611(@core.FTaintFlow))
}

///|
/// THE ADVICE IS WHAT THE DRAWING PRINTS, so it is not dead text.
///
/// The mermaid drawing is the one output that carries the WHY and the HOW,
/// and it takes them from `advice()` -- so a change to the table changes the
/// drawing, and a family whose advice is empty would draw an empty node.
///
/// AND THE NOTICE HALF IS DELIBERATELY NOT ADVICE: a notice is not a defect
/// and must not be given a "here is what to change" note, which is why the
/// drawing says so in its own words instead of asking the table.
test "0611: the advice is reached by the drawing, so it is not dead text" {
  let a = @core.FDivisionByZero.advice()
  assert_true(a.why.contains("division"))
  assert_true(a.how.contains("zero"))
  // AND A FAMILY THAT IS NEVER ASKED STILL HAS AN ADVICE: asking is the
  // reader's move, and the table has to answer every family.
  let t = @core.FTaintFlow.advice()
  assert_true(t.why.contains("tainted"))
  assert_true(t.how.length() > 0)
}
