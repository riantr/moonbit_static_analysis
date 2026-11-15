// 0592: THE DATALOG ENGINE'S TESTS -- the deck's language, cell by cell.
//
// THE DECK. `Datalog-Based Program Analysis` (Tian Tan, Nanjing University, 2021),
// p.18-59 is the language, and every cell of it is a row here. The numbers are
// the SLIDES': the deck's own tables, its own examples and its own verdicts.
//
// THE HOUSE STYLE OF THESE TESTS is the tree's: every row names the slide it
// pins, and a row that measures nothing is not a row. The engine's public API
// is qualified with `@flow.` because a test file sees its own package's
// `pub fn`s only when they are qualified.

///|
/// The tuples of one relation, as `P(a, b)` lines.
fn dtest_rel(s : @flow.DSolve, pred : String) -> String {
  let out : Array[String] = []
  for t in @flow.datalog_tuples(s, pred) {
    out.push(pred + "(" + t.join(", ") + ")")
  }
  out.sort()
  out.join("; ")
}

///|
/// The body of a rule, as text: everything after the arrow.
fn dtest_body_of(r : @flow.DRule) -> String {
  let full = @flow.datalog_rule_text(r)
  let mut i = 0
  while i < full.length() {
    if full[i] == '<' && i + 1 < full.length() && full[i + 1] == '-' {
      return full[i + 2:].to_owned()
    }
    i = i + 1
  }
  ""
}

///|
/// The deck's `Age` table (p.21-22): four people and their ages.
fn dtest_age_facts() -> String {
  "Age(\"Xiaoming\", 18).\nAge(\"Xiaohong\", 23).\nAge(\"Alan\", 16).\nAge(\"Abao\", 31).\n"
}

///|
/// The deck's `Adult` rule (p.32), with its ARITHMETIC atom.
fn dtest_adult_rule() -> String {
  "Adult(person) <- Age(person, age), age >= 18.\n"
}

///|
test "0592: a predicate is a table, and a fact is a tuple in it -- p.21-22" {
  let p = @flow.datalog_parse(dtest_age_facts())
  assert_eq(p.ok, true)
  assert_eq(p.program.facts.length(), 4)
  // The deck's own reading (p.22): a fact asserts that a tuple belongs to a
  // relation.
  assert_eq(
    @flow.datalog_has(@flow.datalog_solve(p.program), "Age", ["Xiaoming", "18"]),
    true,
  )
  assert_eq(
    @flow.datalog_has(@flow.datalog_solve(p.program), "Age", ["Abao", "23"]),
    false,
  )
}

///|
test "0592: the deck's own example, deduced -- p.32-40" {
  // THE DECK'S FINAL TABLE (p.40): the Adult relation holds Xiaoming,
  // Xiaohong and Abao. Alan is 16 and is NOT an adult.
  let p = @flow.datalog_parse(dtest_age_facts() + dtest_adult_rule())
  assert_eq(p.ok, true)
  let s = @flow.datalog_solve(p.program)
  assert_eq(s.ok, true)
  assert_eq(
    dtest_rel(s, "Adult"),
    "Adult(Abao); Adult(Xiaohong); Adult(Xiaoming)",
  )
  assert_eq(@flow.datalog_has(s, "Adult", ["Alan"]), false)
}

///|
test "0592: the arithmetic atom compares as a NUMBER and not as text -- p.29, p.32" {
  // `age >= 18` has to put 9 BELOW 18, and a text comparison would put "9"
  // ABOVE "18" because '9' is the larger character. This is the deck's own
  // example with a ninth grader in it.
  let p = @flow.datalog_parse(
    "Age(\"Alan\", 9).\nAge(\"Xiaoming\", 18).\n" + dtest_adult_rule(),
  )
  let s = @flow.datalog_solve(p.program)
  assert_eq(dtest_rel(s, "Adult"), "Adult(Xiaoming)")
}

///|
test "0592: the rule is safe, because every variable is bound by a relational atom -- p.51-53" {
  let p = @flow.datalog_parse(dtest_age_facts() + dtest_adult_rule())
  assert_eq(@flow.datalog_check(p.program).ok, true)
}

///|
test "0592: an UNSAFE rule is REFUSED, and the two ways of being unsafe are p.51-52" {
  // "For both rules, infinite values of x can satisfy the rule, which makes A
  // an infinite relation" (p.52). The first rule binds `x` only in an
  // ARITHMETIC atom; the second binds it only in a NEGATED one.
  let r1 = @flow.datalog_parse("A(x) <- B(y), x > y.\n")
  assert_eq(r1.ok, true)
  let c1 = @flow.datalog_check(r1.program)
  assert_eq(c1.ok, false)
  assert_eq(c1.problems.length(), 1)
  assert_eq(c1.problems[0].contains("UNSAFE RULE"), true)

  let r2 = @flow.datalog_parse("A(x) <- B(y), !C(x, y).\n")
  assert_eq(r2.ok, true)
  let c2 = @flow.datalog_check(r2.program)
  assert_eq(c2.ok, false)
  assert_eq(c2.problems[0].contains("UNSAFE RULE"), true)
  // And the reason names the variable, because "unsafe" without a name does not
  // say WHICH variable.
  assert_eq(c2.problems[0].contains("x"), true)
}

///|
test "0592: an unsafe program is REFUSED and answers nothing -- p.53" {
  // "In Datalog, only safe rules are allowed." The refusal is a REFUSAL and not
  // a silent drop: a dropped rule would leave a program that runs and answers
  // nothing, which looks exactly like a program whose answer is empty.
  let p = @flow.datalog_parse("B(y).\nA(x) <- B(y), x > y.\n")
  let s = @flow.datalog_solve(p.program)
  assert_eq(s.ok, false)
  assert_eq(s.problems.length(), 1)
  assert_eq(@flow.datalog_text(s).contains("REFUSED"), true)
}

///|
test "0592: negation reads as 'not B(...)' -- p.46-47" {
  // The deck's own example (p.47): the students who need a make-up exam.
  let p = @flow.datalog_parse(
    "Student(\"Xiaoming\").\nStudent(\"Xiaohong\").\nStudent(\"Alan\").\nStudent(\"Abao\").\n" +
    "PassedStd(\"Xiaoming\").\nPassedStd(\"Alan\").\n" +
    "MakeupExamStd(student) <- Student(student), !PassedStd(student).\n",
  )
  assert_eq(p.ok, true)
  let s = @flow.datalog_solve(p.program)
  assert_eq(s.ok, true)
  assert_eq(
    dtest_rel(s, "MakeupExamStd"),
    "MakeupExamStd(Abao); MakeupExamStd(Xiaohong)",
  )
}

///|
test "0592: logical or, both of the deck's ways -- p.44-45" {
  // The deck's two ways to say the same thing: several rules with the same head,
  // and the `;` operator.
  let facts = "Hobby(\"Xiaoming\", \"cooking\").\nHobby(\"Xiaoming\", \"singing\").\n" +
    "Hobby(\"Xiaohong\", \"jogging\").\nHobby(\"Abao\", \"sleeping\").\n" +
    "Hobby(\"Alan\", \"swimming\").\n"
  let by_rules = @flow.datalog_parse(
    facts +
    "SportFan(person) <- Hobby(person, \"jogging\").\nSportFan(person) <- Hobby(person, \"swimming\").\n",
  )
  let by_semi = @flow.datalog_parse(
    facts +
    "SportFan(person) <- Hobby(person, \"jogging\"); Hobby(person, \"swimming\").\n",
  )
  assert_eq(by_rules.ok, true)
  assert_eq(by_semi.ok, true)
  let a = @flow.datalog_solve(by_rules.program)
  let b = @flow.datalog_solve(by_semi.program)
  assert_eq(dtest_rel(a, "SportFan"), "SportFan(Alan); SportFan(Xiaohong)")
  assert_eq(dtest_rel(a, "SportFan"), dtest_rel(b, "SportFan"))
}

///|
test "0592: `;` has a LOWER precedence than `,` -- p.45" {
  // "The precedence of `;` (or) is lower than `,` (and), so disjunctions may be
  // enclosed by parentheses, e.g., H <- A,(B;C)."
  let p = @flow.datalog_parse(
    "A(1).\nB(1).\nC(1).\nH(x) <- A(x), (B(x); C(x)).\n",
  )
  assert_eq(p.ok, true)
  let s = @flow.datalog_solve(p.program)
  assert_eq(dtest_rel(s, "H"), "H(1)")
  // AND THE GROUPING MATTERS: without the parentheses the same three facts
  // would mean "A and B" OR "C", which is a different relation.
  let q = @flow.datalog_parse(
    "A(1).\nB(1).\nC(1).\nH(x) <- A(x), B(x); C(x).\n",
  )
  assert_eq(q.ok, true)
  let t = @flow.datalog_solve(q.program)
  assert_eq(dtest_rel(t, "H"), "H(1)")
}

///|
test "0592: recursion reaches the transitive closure -- p.48-49" {
  // The deck's own example: "we can compute the reachability information (i.e.,
  // transitive closure) of a graph with recursive rules".
  let p = @flow.datalog_parse(
    "Edge(a, b).\nEdge(b, c).\nEdge(c, d).\n" +
    "Reach(from, to) <- Edge(from, to).\n" +
    "Reach(from, to) <- Reach(from, node), Edge(node, to).\n",
  )
  assert_eq(p.ok, true)
  let s = @flow.datalog_solve(p.program)
  assert_eq(s.ok, true)
  assert_eq(
    dtest_rel(s, "Reach"),
    "Reach(a, b); Reach(a, c); Reach(a, d); Reach(b, c); Reach(b, d); Reach(c, d)",
  )
  // AND IT TOOK MORE THAN ONE ROUND, because a recursive rule needs the
  // fixpoint to run again: that is the deck's "until no new facts can be
  // deduced" (p.57) and the reason `rounds` is worth recording.
  assert_eq(s.rounds > 1, true)
}

///|
test "0592: recursion and negation must be SEPARATED -- p.54-56" {
  // The deck's own example. "The rule is contradictory and makes no sense ...
  // the rules may contain contradiction and the inference fails to converge."
  let p = @flow.datalog_parse("B(1).\nA(x) <- B(x), !A(x).\n")
  assert_eq(p.ok, true)
  let c = @flow.datalog_check(p.program)
  assert_eq(c.ok, false)
  assert_eq(
    c.problems[0].contains("RECURSION AND NEGATION ARE NOT SEPARATED"),
    true,
  )
  // AND THE PROGRAM IS REFUSED, so it cannot answer a question by not
  // answering it.
  let s = @flow.datalog_solve(p.program)
  assert_eq(s.ok, false)
  assert_eq(s.problems.length(), 1)
}

///|
test "0592: a NEGATED predicate that is not recursive is fine -- p.47, p.56" {
  // The separation is between recursion and negation -- NOT a ban on negation.
  // The deck's make-up-exam rule negates `PassedStd` and is perfectly legal,
  // because `PassedStd` is not defined by a rule at all.
  let p = @flow.datalog_parse(
    "Student(1).\nPassedStd(2).\nMakeupExamStd(student) <- Student(student), !PassedStd(student).\n",
  )
  assert_eq(@flow.datalog_check(p.program).ok, true)
  let s = @flow.datalog_solve(p.program)
  assert_eq(dtest_rel(s, "MakeupExamStd"), "MakeupExamStd(1)")
}

///|
test "0592: the engine is MONOTONE and TERMINATES -- p.57-59" {
  // "Datalog is monotone as facts cannot be deleted" (p.58) and "A Datalog
  // program always terminates as 1) Datalog is monotone 2) Possible values of
  // IDB predicates are finite (rule safety)" (p.59).
  //
  // THE CHECK IS THE ROUND COUNT: a program that has stopped adding facts
  // stops, and the count is bounded by the size of what it derived.
  let p = @flow.datalog_parse(
    "Edge(a, b).\nEdge(b, c).\n" +
    "Reach(from, to) <- Edge(from, to).\n" +
    "Reach(from, to) <- Reach(from, node), Edge(node, to).\n",
  )
  let s = @flow.datalog_solve(p.program)
  assert_eq(s.ok, true)
  // MEASURED: TWO rounds, and the second one is the one that stops. The first
  // derives Reach(a, b) and Reach(b, c) from the two edges; the second finds
  // nothing new and the loop ends -- which is the deck's "until no new facts
  // can be deduced" (p.57). A count of ONE would mean the loop never asked
  // again, and the count is what makes "the fixpoint was reached" a fact.
  assert_eq(s.rounds, 2)
}

///|
test "0592: the deck's MULTI-HEAD shorthand is three rules with one body -- p.15" {
  // p.15 writes one head over three lines with ONE body. The reader expands
  // it, because that is what it means.
  let p = @flow.datalog_parse(
    "VarPointsTo(this, o),\nReachable(m),\nCallGraph(l, m) <-\nVCall(l, x, k),\n" +
    "VarPointsTo(x, o),\nDispatch(o, k, m),\nThisVar(m, this).\n",
  )
  assert_eq(p.ok, true)
  assert_eq(p.program.rules.length(), 3)
  // And all three carry the SAME body -- the heads differ, and the body is
  // what the deck's slide says the three rules share.
  let body0 = dtest_body_of(p.program.rules[0])
  let body1 = dtest_body_of(p.program.rules[1])
  let body2 = dtest_body_of(p.program.rules[2])
  assert_eq(body0, body1)
  assert_eq(body1, body2)
  assert_eq(body0.contains("Dispatch(o, k, m)"), true)
}

///|
test "0592: the deck's OWN pointer-analysis rules are READ and WRITTEN BACK -- p.70" {
  // The deck's four rules for the pointer analysis (p.70), in the deck's own
  // notation and in the deck's own order.
  let text = "VarPointsTo(x, o) <- New(x, o).\n" +
    "VarPointsTo(x, o) <- Assign(x, y), VarPointsTo(y, o).\n" +
    "FieldPointsTo(oi, f, oj) <- Store(x, f, y), VarPointsTo(x, oi), VarPointsTo(y, oj).\n" +
    "VarPointsTo(y, oj) <- Load(y, x, f), VarPointsTo(x, oi), FieldPointsTo(oi, f, oj)."
  let p = @flow.datalog_parse(text)
  assert_eq(p.ok, true)
  assert_eq(p.program.rules.length(), 4)
  assert_eq(p.program.facts.length(), 0)
  // AND THE ROUND TRIP: what the reader produced, written back, is the deck's
  // own text. That is the claim the deck's whole argument rests on -- that the
  // rules are a READABLE specification.
  assert_eq(@flow.datalog_program_text(p.program), text)
}

///|
test "0592: the deck's OWN taint rules are READ too -- p.91" {
  let text = "VarPointsTo(r, t) <- CallGraph(l, m), Source(m), CallReturn(l, r), Taint(l, t).\n" +
    "TaintFlow(j, l, i) <- CallGraph(l, m), Sink(m, i), Argument(l, i, ai), VarPointsTo(ai, t), Taint(j, t)."
  let p = @flow.datalog_parse(text)
  assert_eq(p.ok, true)
  assert_eq(@flow.datalog_program_text(p.program), text)
  // AND THEY ARE SAFE, which is not obvious: `TaintFlow`'s head holds `j`, `l`
  // and `i`, and every one of them appears in a non-negated relational atom.
  assert_eq(@flow.datalog_check(p.program).ok, true)
}

///|
test "0592: a program that cannot be READ is REFUSED, with the position -- p.40" {
  let p = @flow.datalog_parse("Adult(person) <- Age(person, age), age >= 18\n")
  assert_eq(p.ok, false)
  assert_eq(p.error.contains("'.'"), true)
  // AND THE PROGRAM IS EMPTY, so a reader that only looked at the facts would
  // see an empty program rather than a broken one.
  assert_eq(p.program.rules.length(), 0)
  assert_eq(p.program.facts.length(), 0)
}

///|
test "0592: a COMMENT is part of the language, because the deck's rules carry them" {
  let p = @flow.datalog_parse(
    "// the deck's rule\nAdult(person) <- Age(person, age), age >= 18.\n",
  )
  assert_eq(p.ok, true)
  assert_eq(p.program.rules.length(), 1)
}

///|
test "0592: an EDB relation is an INPUT and an IDB relation is an OUTPUT -- p.42-43" {
  // "The head can only be IDB; Bi can be EDB or IDB" (p.43). So a rule whose
  // head is also a FACT's predicate is legal -- the relation starts as input
  // and grows.
  let p = @flow.datalog_parse(
    "Edge(a, b).\nEdge(b, c).\nReach(from, to) <- Edge(from, to).\n",
  )
  let s = @flow.datalog_solve(p.program)
  assert_eq(dtest_rel(s, "Edge"), "Edge(a, b); Edge(b, c)")
  // The rule derives Reach for EVERY tuple of Edge, and Edge has two.
  assert_eq(dtest_rel(s, "Reach"), "Reach(a, b); Reach(b, c)")
}

///|
test "0592: a rule's terms are VARIABLES and a fact's terms are VALUES" {
  // The deck's facts are `New(b, o1)` (p.65) and its rules are
  // `VarPointsTo(x, o) <- New(x, o).` (p.70), and in BOTH the object name and
  // the variable are bare identifiers. The reading is CONTEXTUAL, and this row
  // is what says so.
  let p = @flow.datalog_parse("New(b, o1).\nVarPointsTo(x, o) <- New(x, o).\n")
  assert_eq(p.ok, true)
  // The fact's terms are values.
  assert_eq(
    @flow.datalog_has(@flow.datalog_solve(p.program), "New", ["b", "o1"]),
    true,
  )
  // The rule's terms are variables, so the rule derives `VarPointsTo(b, o1)`.
  let s = @flow.datalog_solve(p.program)
  assert_eq(dtest_rel(s, "VarPointsTo"), "VarPointsTo(b, o1)")
}
