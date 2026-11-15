// 0594: THE DECK'S TAINT RULES, RUN, AND COMPARED WITH `taint_analyze`.
//
// THE COMPARISON IS THE POINT, and it is the same shape as 0593's: the deck's rules
// are run, and their answer is compared with the answer this tree's own taint analysis
// gives on the SAME program.
//
// AND THE PROGRAM IS THE SECURITY DECK'S OWN SEVEN-STATEMENT EXAMPLE (p.77), because
// it is a program whose taint answer is already printed on a slide -- p.84's
// `TaintFlows: { <3, 7, 0> }` -- and a comparison against a printed answer is a
// comparison with something a reader can check.

///|
/// The deck's two taint rules, read back verbatim -- p.91.
test "0594: the deck's OWN taint rules are READ and WRITTEN BACK -- p.91" {
  let text = @flow.dl_taint_rules_text()
  let p = @flow.datalog_parse(text)
  assert_eq(p.ok, true)
  assert_eq(p.program.rules.length(), 2)
  assert_eq(@flow.datalog_program_text(p.program), text)
  // AND THEY ARE SAFE, which the deck's rule safety (p.51-53) requires: every
  // variable in the head appears in a non-negated relational atom.
  assert_eq(@flow.datalog_check(p.program).ok, true)
}

///|
test "0594: the facts are the deck's own relations -- p.90-91" {
  let facts = @flow.dl_taint_facts_of(tn_deck_cfgs(), 0, tn_deck_spec())
  // `Source(get_password)`: the deck's `Source(m)`.
  assert_eq(facts.source.length(), 1)
  assert_eq(@flow.dl_fact_text(facts.source[0]), "Source(get_password)")
  // `Sink(log, 0)`: the deck's `Sink(m, i)`, with the sensitive argument's index.
  assert_eq(facts.sink.length(), 1)
  assert_eq(@flow.dl_fact_text(facts.sink[0]), "Sink(log, 0)")
  // `Taint(3, t3)`: the call site on line 3 carries the datum named after its line.
  assert_eq(facts.taint.length(), 1)
  assert_eq(@flow.dl_fact_text(facts.taint[0]), "Taint(3, t3)")
}

///|
test "0594: the call graph facts are the deck's own relations -- p.90-91" {
  let facts = @flow.dl_taint_facts_of(tn_deck_cfgs(), 0, tn_deck_spec())
  // `CallGraph(3, get_password)` and `CallGraph(7, log)`: the call sites are LINES,
  // and the line is this tree's own identity for a call site -- the tainted datum is
  // `t<line>` and the object is `o<line>`, so a call site is a line everywhere here.
  assert_eq(
    @flow.dl_has_fact(facts.callgraph, "CallGraph", ["3", "get_password"]),
    true,
  )
  assert_eq(@flow.dl_has_fact(facts.callgraph, "CallGraph", ["7", "log"]), true)
  // `CallReturn(3, pw)`: the name the call's result is bound to.
  assert_eq(
    @flow.dl_has_fact(facts.callreturn, "CallReturn", ["3", "pw"]),
    true,
  )
  // `Argument(7, 0, s)`: the sink's sensitive argument.
  assert_eq(
    @flow.dl_has_fact(facts.argument, "Argument", ["7", "0", "s"]),
    true,
  )
}

///|
test "0594: the deck's rules find the deck's OWN triple -- p.84, p.91" {
  let facts = @flow.dl_taint_facts_of(tn_deck_cfgs(), 0, tn_deck_spec())
  let a = @flow.dl_taint_answer(facts, @flow.dl_facts_of(tn_deck_cfgs(), 0))
  assert_eq(a.ok, true)
  // The deck's p.84 triple is <3, 7, 0>: source call site 3, sink call site 7,
  // argument 0. The Datalog reading derives exactly that.
  assert_eq(a.flow.length(), 1)
  assert_eq(@flow.dl_has_tuple(a.flow, ["3", "7", "0"]), true)
}

///|
test "0594: the Datalog reading and `taint_analyze` AGREE on the deck's triple -- p.84" {
  assert_eq(@flow.dl_taint_agrees(tn_deck_cfgs(), 0, tn_deck_spec()), true)
}

///|
test "0594: the comparison PRINTS both answers, because a boolean is not a comparison" {
  let text = @flow.dl_taint_compare_text(tn_deck_cfgs(), 0, tn_deck_spec())
  assert_eq(text.contains("TaintFlow (the deck's rules):"), true)
  assert_eq(text.contains("TaintFlows (taint_analyze):"), true)
  // The deck's triple is printed in BOTH halves, and it is the deck's own triple.
  assert_eq(text.contains("(3, 7, 0)"), true)
}

///|
test "0594: a program with NO sink derives NO flow -- the rules do not invent one" {
  // THE CONTROL: the same program with the sink removed differs by ONE call, so
  // the zero says the sink is what the flow needs.
  let facts = @flow.dl_taint_facts_of(
    [@flow.cfg_of(tn_deck_main())],
    0,
    (fn() {
      let spec = @flow.taint_spec_empty()
      @flow.taint_spec_source(spec, "get_password")
      spec
    })(),
  )
  let a = @flow.dl_taint_answer(facts, @flow.dl_facts_of(tn_deck_cfgs(), 0))
  assert_eq(a.flow.length(), 0)
}
