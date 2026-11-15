// 0595: THE DECK'S FIRST CHAPTER, MEASURED -- and its last two pages.
//
// THE FIVE QUESTIONS, and the fact that the answer is NOT "the declarative form has
// no implementation details". It has FEWER: FOUR of the deck's FIVE are closed and
// ONE is still open -- and the one it keeps is the deck's own "Hash set or bit
// vector?".

///|
test "0595: the deck's FIVE implementation-detail questions are the deck's own words -- p.10-12" {
  // AND IT IS FIVE, and the count is the deck's: the list GROWS across p.10, p.11
  // and p.12, and by p.12 it has five bullets. The first draft of this increment
  // had four, and the four it had were the four on p.11 -- the fifth bullet,
  // "How to connect PFG nodes and pointers?", is on p.12 and was missed.
  let qs = @flow.dl_questions()
  assert_eq(qs.length(), 5)
  assert_eq(@flow.dl_question_text(qs[0]), "How to implement worklist?")
  assert_eq(@flow.dl_question_text(qs[1]), "Array list or linked list?")
  assert_eq(
    @flow.dl_question_text(qs[2]),
    "Which worklist entry should be processed first?",
  )
  assert_eq(
    @flow.dl_question_text(qs[3]),
    "How to implement points-to set (pt)? Hash set or bit vector?",
  )
  assert_eq(
    @flow.dl_question_text(qs[4]),
    "How to connect PFG nodes and pointers?",
  )
}

///|
test "0595: the worklist, its shape and the POINTER FLOW GRAPH are GONE -- p.10-12, p.15-16" {
  // The deck's answer to the imperative form's questions is the declarative form,
  // and the worklist goes with it: there is no queue, so there is no queue's shape.
  assert_eq(@flow.dl_answer_of(@flow.DlWorklist).name(), "DlGone")
  assert_eq(@flow.dl_answer_of(@flow.DlWorklistShape).name(), "DlGone")
  // AND THE POINTER FLOW GRAPH GOES WITH IT: there is no PFG whose nodes have to
  // be connected, because the RULES connect the facts directly
  // (`VarPointsTo(x, o) <- Assign(x, y), VarPointsTo(y, o).`).
  //
  // AND THIS TREE HAS BOTH FORMS: the imperative side is `pta_run`, which does
  // build a PFG, and the declarative side is the deck's own rules.
  assert_eq(@flow.dl_answer_of(@flow.DlConnect).name(), "DlGone")
}

///|
test "0595: the ORDER question SURVIVES as the strata -- p.10, p.92" {
  // AND THIS IS THE HONEST PART. "Which worklist entry should be processed first?"
  // does not GO AWAY: the declarative form replaces it with "which STRATUM first",
  // and that is the same question wearing a different hat -- and the deck's own
  // p.92 cons line names it: "Cannot fully control performance".
  //
  // AND THIS TREE PAID FOR IT. 0594 found the strata-ordering loop counting
  // PREDICATES against GROUPS, and a program with three IDB predicates in two
  // strata lost its second stratum entirely -- so the deck's question is not
  // academic, it is a question an implementation can get wrong.
  assert_eq(
    @flow.dl_answer_of(@flow.DlWorklistOrder).name(),
    "DlBySpecification",
  )
  // AND THE ENGINE'S ORDER IS PUBLIC, so the question can be ASKED of it.
  let parsed = @flow.datalog_parse(
    "VarPointsTo(x, o) <- New(x, o).\n" +
    "VarPointsTo(y, oj) <- Load(y, x, f), VarPointsTo(x, oi), FieldPointsTo(oi, f, oj).\n" +
    "FieldPointsTo(oi, f, oj) <- Store(x, f, y), VarPointsTo(x, oi), VarPointsTo(y, oj).\n" +
    "TaintFlow(j, l, i) <- CallGraph(l, m), Sink(m, i), Argument(l, i, ai), VarPointsTo(ai, t), Taint(j, t).",
  )
  let strata = @flow.datalog_strata(parsed.program)
  assert_eq(strata.length(), 2)
}

///|
test "0595: the points-to set is NOT gone -- and it is a HASH SET -- p.11" {
  // The deck asks "How to implement points-to set (pt)? Hash set or bit vector?".
  // The declarative form answers the question about WHAT the set IS -- it holds
  // tuples -- and does NOT answer the question about HOW it is stored: this
  // tree's engine stores them in a HASH SET of tuple keys, which is the very
  // "hash set" the deck's question asks about.
  assert_eq(@flow.dl_answer_of(@flow.DlPointSet).name(), "DlByDataStructure")
  //
  // AND THE SET IS MEASURED HERE, not asserted: a relation's membership is a
  // LOOKUP, so adding a tuple that is already there changes nothing.
  let r = @flow.drel_empty()
  assert_eq(@flow.drel_add(r, ["ab", "c"]), true)
  assert_eq(@flow.drel_add(r, ["ab", "c"]), false)
  assert_eq(@flow.drel_has(r, ["ab", "c"]), true)
  assert_eq(@flow.drel_has(r, ["ab"]), false)
}

///|
test "0595: the tuple key is length-prefixed, so two tuples cannot share it -- p.11" {
  // AND THIS IS THE ROW THAT MAKES THE HASH SET SAFE, and it is a measurable
  // property and not a claim about the implementation: the key of a tuple is its
  // terms LENGTH-PREFIXED, so `["ab", "c"]` and `["a", "bc"]` are TWO tuples even
  // though their terms concatenate to the same text.
  //
  // A key that was the plain concatenation would put both in one bucket and the
  // set would answer "yes" to a tuple it never held.
  let r = @flow.drel_empty()
  assert_eq(@flow.drel_add(r, ["ab", "c"]), true)
  assert_eq(@flow.drel_add(r, ["a", "bc"]), true)
  assert_eq(@flow.drel_has(r, ["ab", "c"]), true)
  assert_eq(@flow.drel_has(r, ["a", "bc"]), true)
  // AND THE RELATION HOLDS BOTH, which is what "two tuples" means.
  assert_eq(r.tuples.length(), 2)
}

///|
test "0595: FOUR of the deck's FIVE questions are closed and ONE is still open -- p.10-12" {
  // AND THIS IS THE MEASUREMENT OF THE DECK'S FIRST CHAPTER. The imperative form
  // prints FIVE questions and answers none of them; the declarative form closes
  // FOUR and leaves ONE.
  let open = @flow.dl_open_questions()
  assert_eq(open.length(), 1)
  assert_eq(
    @flow.dl_question_text(open[0]),
    "How to implement points-to set (pt)? Hash set or bit vector?",
  )
}

///|
test "0595: the deck's p.92 is THREE pros and TWO cons -- p.92" {
  let claims = @flow.dl_claims()
  assert_eq(claims.length(), 5)
  assert_eq(@flow.dl_pros().length(), 3)
  assert_eq(@flow.dl_cons().length(), 2)
  // THE PROS, in the deck's order.
  assert_eq(@flow.dl_pros()[0].text, "Succinct and readable")
  assert_eq(@flow.dl_pros()[1].text, "Easy to implement")
  assert_eq(
    @flow.dl_pros()[2].text,
    "Benefit from off-the-shelf optimized Datalog engines",
  )
  // AND THE CONS, in the deck's order and with the deck's own words.
  assert_eq(
    @flow.dl_cons()[0].text,
    "Restricted expressiveness, i.e., it is impossible or inconvenient to express some logics",
  )
  assert_eq(@flow.dl_cons()[1].text, "Cannot fully control performance")
}

///|
test "0595: ONE of the deck's pros does NOT hold for this tree -- p.92" {
  // "Benefit from off-the-shelf optimized Datalog engines" is a claim about an
  // engine, and THIS TREE HAS ITS OWN and uses no off-the-shelf one. The claim is
  // therefore NOT TRUE HERE, and it is reported as not true rather than left
  // implied by silence: a pros list that is a list of advantages is a list of
  // advantages of SOMEONE ELSE's engine.
  //
  // AND THE PRICE IS MEASURED, not asserted: 0594 found a strata-ordering bug in
  // this tree's own engine that cost a whole stratum, which is what owning the
  // engine costs.
  let claims = @flow.dl_claims()
  let mut off_the_shelf = false
  for c in claims {
    if c.text == "Benefit from off-the-shelf optimized Datalog engines" {
      off_the_shelf = true
      assert_eq(c.holds, false)
    }
  }
  assert_eq(off_the_shelf, true)
}

///|
test "0595: the two refusals ARE the deck's 'restricted expressiveness' -- p.51-56, p.92" {
  // The deck's p.92 cons says "Restricted expressiveness, i.e., it is impossible or
  // inconvenient to express some logics". THIS TREE MEASURES that restriction, and
  // it measures it as two REFUSALS rather than as a vague limit: an unsafe rule
  // (p.51-53) and a recursion-and-negation conflict (p.54-56) are both refused, and
  // a refusal says WHICH rule and WHY.
  //
  // AND THE FIRST DRAFT OF THIS ROW WAS WRONG, and the measurement is what caught
  // it: it used "Adult(person) <- Age(person, age), age >= 18." and expected a
  // refusal. THAT RULE IS SAFE -- every variable appears in the non-negated
  // relational atom `Age(person, age)` -- so the check was right and the
  // expectation was wrong. The deck's own two UNSAFE examples are the ones on
  // p.51-52, and they are the ones measured here.
  //
  // AND 0592 OWNS THE UNSAFE-RULE REFUSAL; this row MEASURES THE COUNT for p.92's
  // claim, which is a claim about how MANY things are refused and not about one of
  // them.
  let unsafe_rule = @flow.datalog_parse("A(x) <- B(y), x > y.\n")
  let c1 = @flow.datalog_check(unsafe_rule.program)
  assert_eq(c1.ok, false)
  assert_eq(c1.problems[0].contains("UNSAFE RULE"), true)
  // AND THE REFUSAL NAMES THE VARIABLE, because "unsafe" without a name does not
  // say WHICH variable.
  assert_eq(c1.problems[0].contains("x"), true)
  let conflicting = @flow.datalog_parse("A(x) <- B(x), !A(x).\nB(x) <- A(x).")
  let c2 = @flow.datalog_check(conflicting.program)
  assert_eq(c2.ok, false)
  assert_eq(
    c2.problems[0].contains("RECURSION AND NEGATION ARE NOT SEPARATED"),
    true,
  )
}

///|
test "0595: the deck's SIX rules are six lines of text, and they round-trip -- p.70, p.91" {
  // THE "Succinct and readable" PRO, measured: the deck's pointer rules are FOUR
  // lines and its taint rules are TWO, and each set round-trips through the
  // reader and back out as the deck's own text.
  let pointer = @flow.dl_pointer_rules_text()
  let taint = @flow.dl_taint_rules_text()
  assert_eq(pointer.split("\n").to_array().length(), 4)
  assert_eq(taint.split("\n").to_array().length(), 2)
  assert_eq(
    @flow.datalog_program_text(@flow.datalog_parse(pointer).program),
    pointer,
  )
  assert_eq(
    @flow.datalog_program_text(@flow.datalog_parse(taint).program),
    taint,
  )
}

///|
test "0595: the deck's p.93 is THREE things, and each names the increment that did it -- p.93" {
  // The deck's own table of contents names what the lecture is FOR, and each of
  // the three has its own increment and its own measured pins.
  let things = @flow.dl_things()
  assert_eq(things.length(), 3)
  assert_eq(things[0].text, "Datalog language")
  assert_eq(things[0].increment, "0592")
  assert_eq(things[1].text, "How to implement pointer analysis via Datalog")
  assert_eq(things[1].increment, "0593")
  assert_eq(things[2].text, "How to implement taint analysis via Datalog")
  assert_eq(things[2].increment, "0594")
}
