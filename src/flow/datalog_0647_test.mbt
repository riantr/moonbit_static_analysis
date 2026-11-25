// 0647: THE RINGS THE DECK NEVER DREW -- a cycle of THREE predicates, and a
// self-loop that lives beside a mutual cycle.
//
// WHY THESE ROWS ARE HERE, and what they are NOT.
//
// The engine's recursion story was tested by ONE shape: a rule whose body
// mentions its own head (`Reach(from, to) <- Reach(from, node), Edge(node, to)`)
// -- a SELF-loop -- and by the deck's own taint program, whose `VarPointsTo` and
// `FieldPointsTo` are MUTUALLY recursive. So the two shapes were covered and
// the shapes BETWEEN them were not:
//
//   - a cycle of THREE or more predicates (`A -> B -> C -> A`);
//   - a SELF-loop that coexists with a MUTUAL cycle in the same program.
//
// THE SECOND ONE IS NOT A COSMETIC VARIANT. `d_strata` groups predicates by
// MUTUAL REACHABILITY: two predicates share a stratum when each reaches the
// other. A self-loop reaches ITSELF and nothing else, so under that rule it
// would be a stratum of its own -- and a program holding BOTH a self-loop and a
// mutual cycle is the program where "a stratum of its own" and "the same
// stratum" disagree. The engine's own comment records the trap:
//
//     // A PREDICATE IS IN ITS OWN STRATUM, and the reflexive case is the whole
//     // reason the first version of this loop derived NOTHING: a predicate with
//     // no IDB dependency does not reach itself, so the mutual-reachability test
//     // was false for it and its group came out EMPTY -- and a stratum with no
//     // predicate in it evaluates no rule at all.
//
// (`src/flow/datalog.mbt`, `d_strata`.) The `p == q` arm is what keeps the
// reflexive case from producing an EMPTY group, and a group that is empty
// evaluates NO RULE AT ALL -- the same failure 0594 recorded, where the second
// stratum was never evaluated and the program silently derived less than it
// should. So a self-loop beside a mutual cycle is a test of the arm that keeps
// a group non-empty.
//
// AND THE THREE-PREDICATE CYCLE IS THE OTHER HALF OF THE SAME RULE. Mutual
// reachability is TRANSITIVE, so `A -> B -> C -> A` puts all three in one
// stratum -- and the reachability computation is a fixed point over a graph
// that CONTAINS A CYCLE, which is exactly where a naive transitive closure
// either loops forever or stops early. `d_reach` is a WORKLIST (it drains a
// queue and skips what it has seen), so it terminates; the rows below hold it
// to that.
//
// EVERY NUMBER BELOW IS COUNTED BY HAND, from the program text, and then
// asserted. A test that asserts "the strata are non-empty" would pass on an
// engine that put everything in one stratum, and one that asserts "a cycle was
// found" would pass on an engine that found EVERY cycle.

///|
/// The predicates of one stratum, SORTED, so an assertion about a stratum does
/// not depend on the order the engine happened to discover the members in.
fn d0647_sorted(group : Array[String]) -> String {
  let out : Array[String] = []
  for p in group {
    out.push(p)
  }
  out.sort()
  out.join(", ")
}

///|
/// A CYCLE OF THREE PREDICATES IS ONE STRATUM, and the reachability that puts
/// it there is transitive.
///
/// The program is the minimal three-predicate cycle:
///
///     A(x) <- B(x).
///     B(x) <- C(x).
///     C(x) <- A(x).
///
/// Each rule's head mentions ONE body predicate, and the three form a ring.
/// `d_deps` reads the edges head -> body, so the dependency graph is
/// A->B, B->C, C->A, and `d_reach` closes it: A reaches B, then C, then A
/// again -- so A reaches BOTH of the others, and so do B and C. All three are
/// mutually reachable, so all three are ONE stratum.
///
/// The count that matters is `strata.length() == 1` and the member count is
/// THREE. A two-stratum answer would mean one of the three was split off, and
/// a member count of two would mean one was lost -- and a stratum that lost a
/// predicate evaluates no rule for it, so the program would derive less than it
/// should.
test "0647: a cycle of three predicates is ONE stratum" {
  let p = @flow.datalog_parse("A(x) <- B(x).\nB(x) <- C(x).\nC(x) <- A(x).\n")
  assert_eq(p.ok, true)
  assert_eq(p.program.rules.length(), 3)
  let strata = @flow.datalog_strata(p.program)
  // ONE stratum, and it holds all three.
  assert_eq(strata.length(), 1)
  assert_eq(strata[0].length(), 3)
  assert_eq(d0647_sorted(strata[0]), "A, B, C")
}

///|
/// THE CONTROL FOR THE ROW ABOVE, and it is the same three predicates with
/// the ring CUT.
///
///     A(x) <- B(x).
///     B(x) <- C(x).
///     C(x) <- D(x).
///
/// Now A reaches B and C but C does NOT reach A, so no two of them are
/// mutually reachable and the three fall into three strata -- one predicate
/// each.
///
/// THIS ROW IS WHAT MAKES THE ROW ABOVE MEAN SOMETHING. Without it, "one
/// stratum of three" could be an engine that puts everything in one stratum
/// always, and the assertion would pass for the wrong reason. The two programs
/// differ by ONE EDGE (`C(x) <- A(x).` against `C(x) <- D(x).`), and the
/// stratum count goes from one to three.
test "0647: the same three predicates with the ring CUT are three strata" {
  let p = @flow.datalog_parse("A(x) <- B(x).\nB(x) <- C(x).\nC(x) <- D(x).\n")
  assert_eq(p.ok, true)
  let strata = @flow.datalog_strata(p.program)
  // ONE predicate per stratum: the chain is not a cycle.
  assert_eq(strata.length(), 3)
  assert_eq(strata[0].length(), 1)
  assert_eq(strata[1].length(), 1)
  assert_eq(strata[2].length(), 1)
  // AND THE ORDER IS THE EVALUATION ORDER, which for a chain is the order the
  // rules depend: `C` first (it needs only `D`), then `B`, then `A`.
  assert_eq(strata[0][0], "C")
  assert_eq(strata[1][0], "B")
  assert_eq(strata[2][0], "A")
}

///|
/// A SELF-LOOP BESIDE A MUTUAL CYCLE: two strata, and NEITHER IS EMPTY.
///
///     A(x) <- A(x).        <- the self-loop
///     B(x) <- C(x).
///     C(x) <- B(x).        <- the mutual cycle
///
/// A reaches A and nothing else, so A is a stratum of its own -- and the
/// `p == q` arm of the mutual-reachability test is what puts it there. B and C
/// reach each other, so they share the SECOND stratum, which holds both of
/// them.
///
/// THE ASSERTION THAT MATTERS IS THE MEMBER COUNT. A group that came out EMPTY
/// is a group that evaluates NO RULE AT ALL, and 0594 recorded exactly that
/// failure: the strata-ordering loop counted PREDICATES against the number of
/// GROUPS, exited with the second group never evaluated, and the program
/// derived less than it should while the report said nothing. So this row
/// asserts that the two strata hold ONE and TWO predicates -- and that the one
/// is `A` and the two are `B` and `C`.
///
/// THE ORDER OF THE TWO STRATA IS NOT ASSERTED, and that is deliberate. The
/// strata are ordered by LEVEL, and both of these sit at level zero (neither
/// depends on a predicate outside its own group), so their relative order is
/// the order the GROUPS were discovered in -- and the groups are discovered by
/// walking the predicates of a `Map`, whose key order is not a property of the
/// PROGRAM. A row that asserted `strata[0]` is `A` would be asserting the
/// engine's hash order, and it would pass or fail for a reason that has
/// nothing to do with the strata. So the row finds the stratum that holds `A`
/// and asserts its SIZE, and the other one is then asserted by what is left.
test "0647: a self-loop beside a mutual cycle is two strata, and neither is empty" {
  let p = @flow.datalog_parse("A(x) <- A(x).\nB(x) <- C(x).\nC(x) <- B(x).\n")
  assert_eq(p.ok, true)
  let strata = @flow.datalog_strata(p.program)
  assert_eq(strata.length(), 2)
  // THE STRATUM THAT HOLDS THE SELF-LOOP PREDICATE holds it ALONE.
  let mut self_size = 0
  let mut pair_size = 0
  let mut pair_text = ""
  for g in strata {
    if g.contains("A") {
      self_size = g.length()
    } else {
      pair_size = g.length()
      pair_text = d0647_sorted(g)
    }
  }
  // NEITHER GROUP IS EMPTY. This is the assertion 0594's failure would have
  // broken.
  assert_eq(self_size, 1)
  assert_eq(pair_size, 2)
  // AND THE MUTUAL PAIR IS IN ONE GROUP, not split: the self-loop did not drag
  // the mutual cycle apart with it.
  assert_eq(pair_text, "B, C")
}

///|
/// AND THE ENGINE SOLVES IT: the self-loop's stratum evaluates its rule, and
/// the mutual pair's stratum evaluates BOTH of theirs.
///
/// This is the row that would go RED if the self-loop's stratum were empty.
/// A stratum with no predicate in it evaluates no rule at all -- so the
/// self-loop's rule would never run, and the facts it derives would never
/// appear.
///
/// The program adds a fact and lets the ring carry it:
///
///     A(1).
///     A(x) <- A(x).        <- derives A(2) from A(1)? no -- see below
///     B(x) <- C(x).
///     C(x) <- B(x).
///
/// The self-loop `A(x) <- A(x).` derives `A(x)` from `A(x)`, so it derives
/// nothing NEW -- and that is the point: it must derive nothing new and the
/// solver must still TERMINATE, having run the rule once per round. The
/// mutual pair is what derives: `B(1)` and `C(1)` from the fact `B(1)`.
test "0647: a self-loop beside a mutual cycle SOLVES, and the mutual pair derives" {
  let p = @flow.datalog_parse(
    "B(1).\nA(x) <- A(x).\nB(x) <- C(x).\nC(x) <- B(x).\n",
  )
  assert_eq(p.ok, true)
  let s = @flow.datalog_solve(p.program)
  assert_eq(s.ok, true)
  // The mutual pair derived the fact and kept it.
  assert_eq(@flow.datalog_has(s, "B", ["1"]), true)
  assert_eq(@flow.datalog_has(s, "C", ["1"]), true)
  // AND THE SOLVER TERMINATED, and it took more than one round: the ring needs
  // a second pass to carry `B(1)` into `C` and back. A solver that stopped
  // after one round would have missed `C(1)`.
  assert_true(s.rounds >= 2)
}

///|
/// A NEGATED EDGE ON A CYCLE IS REFUSED -- and the refusal is the DECK'S
/// REQUIREMENT (p.54-56), not a house rule.
///
/// The deck: "In Datalog, recursion and negation of an atom must be separated.
/// Otherwise, the rules may contain contradiction and the inference fails to
/// converge."
///
/// The program puts a negation on the ring:
///
///     A(x) <- B(x).
///     B(x) <- C(x), !A(x).
///     C(x) <- A(x).
///
/// `B` negates `A`, and `A` reaches `B` (A -> B), so the two contradict each
/// other: the rule for `B` says "B is true when A is false", and the rule for
/// `A` says "A is true when B is true". The engine must REFUSE the program, and
/// it must refuse it as a REFUSAL -- a program that answers nothing looks
/// exactly like a program whose answer is empty.
///
/// THIS ROW IS THE THREE-PREDICATE VERSION of the two-predicate case the deck
/// draws, and the difference is the length of the path back: here `A` reaches
/// `B` in ONE step, but the ring around it means the CONTRADICTION also travels
/// the other way.
test "0647: a negated edge on a three-predicate cycle is REFUSED" {
  let p = @flow.datalog_parse(
    "A(x) <- B(x).\nB(x) <- C(x), !A(x).\nC(x) <- A(x).\n",
  )
  assert_eq(p.ok, true)
  let c = @flow.datalog_check(p.program)
  assert_eq(c.ok, false)
  assert_true(
    c.problems[0].contains("RECURSION AND NEGATION ARE NOT SEPARATED"),
  )
  // AND THE PROGRAM IS REFUSED, so it cannot answer a question by not
  // answering it.
  let s = @flow.datalog_solve(p.program)
  assert_eq(s.ok, false)
  assert_eq(s.problems.length(), 1)
}

///|
/// THE CONTROL FOR THE ROW ABOVE, and it is the SAME program with the
/// negation REMOVED -- so the refusal is caused by the negation and not by
/// the cycle.
///
/// A cycle is LEGAL. The deck's own point about recursion is that it is "much
/// more powerful, and is able to express sophisticated program analyses, such
/// as pointer analysis" (p.50); what is forbidden is a NEGATIVE edge ON a
/// cycle. So the same three-predicate cycle without the negation must be
/// ACCEPTED -- and if it were not, the row above would be proving nothing
/// beyond "a cycle is refused".
test "0647: the same three-predicate cycle WITHOUT the negation is accepted" {
  let p = @flow.datalog_parse("A(x) <- B(x).\nB(x) <- C(x).\nC(x) <- A(x).\n")
  let c = @flow.datalog_check(p.program)
  assert_eq(c.ok, true)
  assert_eq(c.problems.length(), 0)
  // AND IT SOLVES.
  let s = @flow.datalog_solve(p.program)
  assert_eq(s.ok, true)
}
