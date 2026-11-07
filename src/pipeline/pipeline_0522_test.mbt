// pipeline_0522_test.mbt -- BOUNDED SYMBOLIC EXECUTION over guards, pinned at
// the pipeline level.
//
// 0522. The pass reads only guards that compare an IMMUTABLE local against an
// INTEGER LITERAL, and it makes exactly three decisions: a guard the facts
// contradict (its D[P] is empty -- InfeasibleBranch), a guard the facts already
// imply (RedundantGuard), and everything else, which is UNDECIDED and reports
// nothing. These tests pin all three, plus the two rules that make the first
// two sound: facts die on assignment, and facts do not survive a loop body that
// assigns the name.

///|
/// Count the findings of one family.
fn count0522(rs : Array[@report.Report], f : @core.Family) -> Int32 {
  let mut n = 0
  for r in rs {
    if r.family == f {
      n += 1
    }
  }
  n
}

///|
/// THE contradiction case: `x > 5` then `x < 3`. No integer is both, so the
/// inner branch's domain is empty and the finding says so with the two lines
/// that disagree -- the same claim the deck writes `D[P] = { }`.
test "a contradictory guard is reported with its empty domain" {
  let src = "fn f(x : Int) -> Unit {\n  if x > 5 {\n    if x < 3 {\n      println(\"never\")\n    }\n  }\n}\n"
  let r = @pipeline.run(src, "u.mbt", empty_iface())
  assert_eq(count0522(r.reports, @core.FInfeasibleBranch), 1)
  assert_eq(count0522(r.reports, @core.FRedundantGuard), 0)
  // and the message carries the justification, not just the verdict
  let mut said = false
  for rep in r.reports {
    if rep.family == @core.FInfeasibleBranch {
      said = rep.message.contains("D[P] = { }") &&
        rep.message.contains("x > 5") &&
        rep.message.contains("x < 3")
    }
  }
  assert_true(said)
}

///|
/// THE implied case: `x > 10` already forces `x > 5`, so the inner test cannot
/// take its else arm. Same fragment, opposite direction, different family --
/// one id per property, which is why this is not a second InfeasibleBranch.
test "a guard the facts imply is a redundant test" {
  let src = "fn f(x : Int) -> Unit {\n  if x > 10 {\n    if x > 5 {\n      println(\"yes\")\n    }\n  }\n}\n"
  let r = @pipeline.run(src, "u.mbt", empty_iface())
  assert_eq(count0522(r.reports, @core.FRedundantGuard), 1)
  assert_eq(count0522(r.reports, @core.FInfeasibleBranch), 0)
}

///|
/// Two DIFFERENT names are not the same constraint. `y < 3` says nothing about
/// `x`, so the guard is undecided and NOTHING is reported -- the silence here is
/// the family contract's `excluded` clause in action, and pinning it is what
/// keeps a future change from turning undecided into a finding.
test "guards over different names are undecided, not reported" {
  let src = "fn f(x : Int, y : Int) -> Unit {\n  if x > 5 {\n    if y < 3 {\n      println(\"ok\")\n    }\n  }\n}\n"
  let r = @pipeline.run(src, "u.mbt", empty_iface())
  assert_eq(count0522(r.reports, @core.FInfeasibleBranch), 0)
  assert_eq(count0522(r.reports, @core.FRedundantGuard), 0)
}

///|
/// SOUNDNESS RULE 1: a fact dies on assignment. `x > 5` is true on entry to the
/// outer body, but `x = 0` makes it false before the inner test, so reporting
/// the inner guard here would be a FALSE finding -- the one failure mode this
/// analysis must never have.
test "a fact does not survive an assignment to the name" {
  let src = "fn f(x : Int) -> Unit {\n  if x > 5 {\n    x = 0\n    if x > 5 {\n      println(\"no\")\n    }\n  }\n}\n"
  let r = @pipeline.run(src, "u.mbt", empty_iface())
  assert_eq(count0522(r.reports, @core.FInfeasibleBranch), 0)
  assert_eq(count0522(r.reports, @core.FRedundantGuard), 0)
}

///|
/// SOUNDNESS RULE 2: a fact does not survive a loop that assigns the name. The
/// body runs an unknown number of times, so `x > 5` proved before `while` says
/// nothing about the second iteration.
test "a fact does not survive a loop body that assigns the name" {
  let src = "fn f(x : Int) -> Unit {\n  if x > 5 {\n    while x > 5 {\n      x = x - 1\n    }\n    if x < 3 {\n      println(\"maybe\")\n    }\n  }\n}\n"
  let r = @pipeline.run(src, "u.mbt", empty_iface())
  assert_eq(count0522(r.reports, @core.FInfeasibleBranch), 0)
  assert_eq(count0522(r.reports, @core.FRedundantGuard), 0)
}

///|
/// And the intervals DO survive a loop that does not touch the name: `n` is
/// still `n` after a loop over `i`, so `n > 10` then `n < 3` is still empty.
/// The invalidation is by name, not by scope -- the sound rule, not the
/// convenient one.
test "a loop over a different name leaves the fact intact" {
  let src = "fn f(n : Int) -> Unit {\n  if n > 10 {\n    for i in [1, 2] {\n      println(i)\n    }\n    if n < 3 {\n      println(\"never\")\n    }\n  }\n}\n"
  let r = @pipeline.run(src, "u.mbt", empty_iface())
  assert_eq(count0522(r.reports, @core.FInfeasibleBranch), 1)
}
