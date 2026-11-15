// 0593: THE DECK'S POINTER RULES, RUN, AND COMPARED WITH `pta_run`.
//
// THE COMPARISON IS THE POINT. The deck's claim (p.16) is that the declarative form is
// "Succinct / Readable (logic-based specification) / Easy to implement" -- that the
// RULES are the specification. So the rules are written out, run, and their answer is
// compared with the answer `pta_run` gives on the same program.
//
// AND THE COMPARISON CAN DISAGREE, and when it does the disagreement is REPORTED and
// NAMED. A comparison that can only say "yes" is not a comparison, and the house rule
// is that a red row that names its cause beats a green row that measured nothing.

///|
/// The deck's p.28-29 program: `p = new C(); q = p; x = new X(); y = new Y();`.
/// The deck's own answer (p.28-29): p and q are ALIASES, x and y are NOT.
///
/// THE LINE NUMBERS ARE THE DECK'S, and they matter: `pta_site_names` names an object
/// by its allocation site's LINE (p.45-47, p.77), so `p` on line 1 is `o1` and `x` on
/// line 3 is `o3`.
fn dl_p28_body() -> Array[@ast.Stmt] {
  [
    p_let(1, "p", p_struct("C")),
    p_let(2, "q", p_name("p")),
    p_let(3, "x", p_struct("X")),
    p_let(4, "y", p_struct("Y")),
  ]
}

///|
/// The deck's p.57 program, whose field holds a STRING: `c.f = "x"`.
///
/// IT IS THE PROGRAM THAT MAKES THE DIFFERENCE VISIBLE, and it is here for that
/// reason: `pta_run`'s field cell holds the VALUE (`o1.f -> {"x"}`), and the deck's
/// `FieldPointsTo` holds the POINTERS a field points at. A string is not a pointer, so
/// the deck's rules have nothing to put in the field relation.
fn dl_p57_body() -> Array[@ast.Stmt] {
  [
    p_let(1, "c", p_struct("C")),
    p_assign(2, p_field(p_name("c"), "f"), p_str("x")),
    p_let(3, "s", p_field(p_name("c"), "f")),
  ]
}

///|
/// A program whose field holds a POINTER, so the two readings' field relations are
/// about the same thing and can be compared directly.
///
/// The deck's p.70 rule is `FieldPointsTo(oi, f, oj) <- Store(x, f, y),
/// VarPointsTo(x, oi), VarPointsTo(y, oj)`, so it puts the STORED VALUE's points-to
/// set into the field relation -- which is a pointer when the stored value is one.
fn dl_ptr_field_body() -> Array[@ast.Stmt] {
  [
    p_let(1, "c", p_struct("C")),
    p_let(2, "x", p_struct("X")),
    p_assign(3, p_field(p_name("c"), "f"), p_name("x")),
    p_let(4, "y", p_field(p_name("c"), "f")),
  ]
}

///|
test "0593: the deck's rules are TEXT, and they come back verbatim -- p.70" {
  let text = @flow.dl_pointer_rules_text()
  let p = @flow.datalog_parse(text)
  assert_eq(p.ok, true)
  assert_eq(p.program.rules.length(), 4)
  assert_eq(@flow.datalog_program_text(p.program), text)
  // AND THEY ARE SAFE, which the deck's rule safety (p.51-53) requires.
  assert_eq(@flow.datalog_check(p.program).ok, true)
}

///|
test "0593: the facts are the deck's own relations -- p.65, p.70" {
  let g = @flow.cfg_of(dl_p28_body())
  let f = @flow.dl_facts_of([g], 0)
  // THREE allocations, and the first version of this row said TWO: the p.28-29
  // program allocates p, x AND y, and only `q` is a copy. The measurement corrected
  // the expectation, and the row now says three.
  assert_eq(f.new.length(), 3)
  // THE OBJECT NAMES ARE THE DECK'S, and they come from `pta_site_names` -- the
  // same naming `pta_run` uses, or the two answers would not be comparable.
  assert_eq(@flow.dl_has_fact(f.new, "New", ["p", "o1"]), true)
  assert_eq(@flow.dl_has_fact(f.new, "New", ["x", "o3"]), true)
  assert_eq(@flow.dl_has_fact(f.new, "New", ["y", "o4"]), true)
  // `Assign(q, p)`: the deck's Assign relation, with the NAME on the right.
  assert_eq(f.assign.length(), 1)
  assert_eq(@flow.dl_fact_text(f.assign[0]), "Assign(q, p)")
  // AND THE FACTS COME OUT IN REVERSE SOURCE ORDER, and that is not a defect: the
  // facts are read from the CFG's NODES, and `cfg_of` allocates those back to front
  // (the same trap `pta_source_order` exists to undo). So the facts are compared as
  // a SET and not by position.
  assert_eq(@flow.dl_fact_text(f.new[0]), "New(y, o4)")
}

///|
test "0593: the deck's p.28-29 program, deduced by the deck's rules -- p.28-29" {
  let g = @flow.cfg_of(dl_p28_body())
  let a = @flow.dl_pointer_answer([g], 0)
  assert_eq(a.ok, true)
  // p and q ALIAS, x and y do not -- and the Datalog reading says so on its own.
  assert_eq(@flow.dl_has_tuple(a.vpt, ["p", "o1"]), true)
  assert_eq(@flow.dl_has_tuple(a.vpt, ["q", "o1"]), true)
  assert_eq(@flow.dl_has_tuple(a.vpt, ["x", "o3"]), true)
  assert_eq(@flow.dl_has_tuple(a.vpt, ["y", "o4"]), true)
  // AND IT IS EXACTLY FOUR TUPLES, so the row also says the Datalog reading does
  // not derive MORE than the imperative one -- an extra tuple would be an extra
  // conclusion the rules do not license.
  assert_eq(a.vpt.length(), 4)
}

///|
test "0593: the Datalog reading and `pta_run` AGREE on the pointer relation -- p.28-29" {
  let g = @flow.cfg_of(dl_p28_body())
  assert_eq(@flow.dl_pointer_agrees([g], 0), true)
}

///|
test "0593: the four rules are the deck's FOUR statement kinds -- p.70" {
  // p.70 puts a table beside the rules: New, Assign, Store, Load. So a program
  // with all four kinds produces facts in all four relations.
  let g = @flow.cfg_of(dl_ptr_field_body())
  let f = @flow.dl_facts_of([g], 0)
  assert_eq(f.new.length(), 2)
  assert_eq(f.assign.length(), 0)
  assert_eq(f.store.length(), 1)
  assert_eq(f.load.length(), 1)
  assert_eq(@flow.dl_fact_text(f.store[0]), "Store(c, f, x)")
  assert_eq(@flow.dl_fact_text(f.load[0]), "Load(y, c, f)")
}

///|
test "0593: a field that holds a POINTER agrees in both readings -- p.70" {
  let g = @flow.cfg_of(dl_ptr_field_body())
  let a = @flow.dl_pointer_answer([g], 0)
  // `c.f = x` with x -> {o2}: the deck's rule puts the STORED VALUE's points-to set
  // into the field relation, so `FieldPointsTo(o1, f, o2)`.
  assert_eq(@flow.dl_has_tuple(a.field, ["o1", "f", "o2"]), true)
  // AND `y = c.f` reads it back, so y -> {o2}.
  assert_eq(@flow.dl_has_tuple(a.vpt, ["y", "o2"]), true)
  // AND THE POINTER RELATIONS AGREE, because both readings hold the same pointers.
  assert_eq(@flow.dl_pointer_agrees([g], 0), true)
}

///|
test "0593: the field relation holds POINTERS and the field cell holds VALUES -- p.59, p.70" {
  // THE DIFFERENCE, MEASURED AND NAMED.
  //
  // `pta_run`'s field cell holds the VALUE a field contains: p.59 puts `"x"` inside
  // a points-to set, so `o1.f` holds `{"x"}`. The deck's `FieldPointsTo` holds the
  // POINTERS a field points at, and a string is not a pointer -- so the deck's
  // rules have nothing to put there.
  let g = @flow.cfg_of(dl_p57_body())
  let a = @flow.dl_pointer_answer([g], 0)
  // THE DECK'S FIELD RELATION IS EMPTY, and that is the honest answer for a field
  // that holds a string.
  assert_eq(a.field.length(), 0)
  // AND `pta_run`'s FIELD CELL IS NOT: it holds the value.
  let pt = @flow.pta_run([g])[0]
  let cell = @flow.pta_of(pt, "o1.f")
  assert_eq(cell.length(), 1)
  assert_eq(@flow.pta_of(pt, "s").length(), 1)
  // AND SO THE TWO READINGS DISAGREE ON THE POINTER RELATION TOO, because `s` is a
  // POINTER in `pta_run` and holds the value while the deck's rules derive nothing
  // for it. The disagreement is reported rather than normalised away.
  assert_eq(@flow.dl_pointer_agrees([g], 0), false)
}

///|
test "0593: the comparison PRINTS both answers, because a boolean is not a comparison" {
  let g = @flow.cfg_of(dl_p28_body())
  let text = @flow.dl_compare_text([g], 0)
  // Both readings are named, and the Datalog reading's four tuples are all there.
  assert_eq(text.contains("VarPointsTo (the deck's rules):"), true)
  assert_eq(text.contains("VarPointsTo (pta_run):"), true)
  assert_eq(text.contains("FieldPointsTo (the deck's rules):"), true)
  assert_eq(text.contains("p -> {o1}"), true)
  assert_eq(text.contains("q -> {o1}"), true)
}
