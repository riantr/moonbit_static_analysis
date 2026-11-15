// 0593: THE DECK'S POINTER-ANALYSIS RULES, RUN, AND COMPARED WITH `pta_run`.
//
// THE DECK'S OWN CLAIM. p.15-16 gives the pointer analysis in Datalog and says of it:
// "Succinct / Readable (logic-based specification) / Easy to implement" (p.16). The claim
// is not that Datalog is faster -- it is that THE RULES ARE THE SPECIFICATION, and a
// specification you can read is one you can check.
//
// SO THIS INCREMENT IS A MEASUREMENT OF THAT CLAIM and not a second pointer analysis.
// The deck's four rules (p.70) are written out, the program's statements become the
// deck's own EDB relations, the rules are RUN in the engine 0592 built, and the answer
// is compared with the answer `pta_run` gives on the same program.
//
// ONE FACT, ONE PLACE. The Datalog engine computes the DECK'S rules; `src/flow/pta.mbt`
// computes this tree's answer. Neither is derived from the other, and the comparison is
// what turns the deck's claim into a fact about this tree.
//
// THE FOUR RULES (p.70), IN THE DECK'S OWN ORDER AND ITS OWN WORDS:
//
//     VarPointsTo(x, o) <-
//     New(x, o).
//     VarPointsTo(x, o) <-
//     Assign(x, y),
//     VarPointsTo(y, o).
//     FieldPointsTo(oi, f, oj) <-
//     Store(x, f, y),
//     VarPointsTo(x, oi),
//     VarPointsTo(y, oj).
//     VarPointsTo(y, oj) <-
//     Load(y, x, f),
//     VarPointsTo(x, oi),
//     FieldPointsTo(oi, f, oj).
//
// AND THE TABLE THE DECK PUTS BESIDE THEM (p.70) IS THE CONTRACT: New, Assign, Store
// and Load are the four STATEMENT KINDS the rules are written over.
//
// THE TWO READINGS HOLD DIFFERENT THINGS IN THEIR FIELD RELATION, and that is the
// interesting part of the comparison rather than a nuisance in it:
//
//   `VarPointsTo(x, o)`    holds OBJECTS -- what a pointer may point to.
//   `FieldPointsTo(oi, f, oj)` holds OBJECTS TOO: the deck's p.70 rule puts the
//                           stored VALUE's points-to set into the field relation, so
//                           a field holds what it POINTS AT.
//
// AND `pta_run`'s FIELD CELL holds the VALUES: `pta_of_expr` returns the literal as
// printed for a string (p.59 puts `"x"` inside a points-to set), so `o1.f` holds
// `{"x","y"}` -- what a field CONTAINS. So the two readings AGREE on the pointer
// relation and DIFFER on the field relation, and the difference is a NAMED one: the
// deck's field relation is the POINTERS a field holds, and this tree's field cell is
// the VALUES a field holds. That is a fact about the two SPECIFICATIONS and not an
// error in either, and the comparison reports it as a difference rather than hiding it
// behind a normalisation.

///|
/// The facts of a program, in the deck's own relations (p.65, p.70).
///
/// WHY A SEPARATE STRUCT AND NOT A DProgram. The FACTS come from the program and the
/// RULES come from the deck, and they are two different things that meet at the solve.
/// A struct that carried both would make it possible to build a program whose facts
/// were the deck's rules, and then the comparison would be comparing a program with
/// itself.
pub(all) struct DlFacts {
  /// `New(x, o)` -- an allocation site (p.65).
  new : Array[DFact]
  /// `Assign(x, y)` -- `x = y`.
  assign : Array[DFact]
  /// `Store(x, f, y)` -- `x.f = y`.
  store : Array[DFact]
  /// `Load(y, x, f)` -- `y = x.f`.
  load : Array[DFact]
}

///|
/// The empty set of facts.
pub fn dl_facts_empty() -> DlFacts {
  { new: [], assign: [], store: [], load: [], }
}

///|
/// The facts of ONE function's CFG, in the deck's relations.
///
/// THE OBJECT NAMES ARE THE DECK'S, and they come from `pta_site_names` -- the same
/// function that names the objects for `pta_run`. That is the house rule "one fact, one
/// place": if the Datalog reading named its objects on its own, the two answers would
/// not be comparable, and a comparison that cannot be compared is not a comparison.
pub fn dl_facts_of(cfgs : Array[Cfg], fi : Int32) -> DlFacts {
  let sites = pta_site_names(cfgs)
  let facts = dl_facts_empty()
  let g = cfgs[fi]
  let mut v = 0
  while v < g.kinds.length() {
    let kind = g.kinds[v]
    match kind {
      Assign(x, e) =>
        match pta_alloc_of(kind) {
          // `New(x, o)`: the allocation site's own object name.
          Some(_) => {
            let obj = pta_site_of(sites, fi, v)
            facts.new.push(dfact("New", [x, obj]))
          }
          None =>
            match e.kind {
              // `Assign(x, y)`: the deck's rule is about a NAME, so the right-hand
              // side has to be a NAME. Anything else is not an assignment the deck's
              // rule covers, and inventing a fact for it would be inventing a
              // conclusion.
              @ast.EName(y) => facts.assign.push(dfact("Assign", [x, y]))
              // `Load(y, x, f)`: `y = x.f` is the deck's LOAD, and it is a DISTINCT
              // kind from Assign -- the deck's p.70 table lists them separately.
              @ast.EField(b, fld) =>
                match b.kind {
                  @ast.EName(bx) => facts.load.push(dfact("Load", [x, bx, fld]))
                  _ => ()
                }
              _ => ()
            }
        }
      Store(x, e) =>
        match pta_alloc_of(kind) {
          Some(_) => {
            let obj = pta_site_of(sites, fi, v)
            facts.new.push(dfact("New", [x, obj]))
          }
          None =>
            match e.kind {
              @ast.EName(y) => facts.assign.push(dfact("Assign", [x, y]))
              _ => ()
            }
        }
      PlaceStore(target, e) =>
        // `Store(x, f, y)`: the deck's rule is a store THROUGH A FIELD.
        match target.kind {
          @ast.EField(b, fld) =>
            match b.kind {
              @ast.EName(x) =>
                match e.kind {
                  @ast.EName(y) => facts.store.push(dfact("Store", [x, fld, y]))
                  _ => ()
                }
              _ => ()
            }
          _ => ()
        }
      _ => ()
    }
    v = v + 1
  }
  facts
}

///|
/// The DECK'S FOUR RULES (p.70), as text, in the deck's own order and its own words.
///
/// IT IS TEXT AND NOT A BUILT PROGRAM, because the deck's claim is about a READABLE
/// SPECIFICATION. A rule built in code is the imperative form wearing a hat; a rule
/// that is TEXT can be read, printed, and compared with the slide. The reader 0592
/// built reads this, and the round trip back out is a pinned row.
pub fn dl_pointer_rules_text() -> String {
  "VarPointsTo(x, o) <- New(x, o).\n" +
  "VarPointsTo(x, o) <- Assign(x, y), VarPointsTo(y, o).\n" +
  "FieldPointsTo(oi, f, oj) <- Store(x, f, y), VarPointsTo(x, oi), VarPointsTo(y, oj).\n" +
  "VarPointsTo(y, oj) <- Load(y, x, f), VarPointsTo(x, oi), FieldPointsTo(oi, f, oj)."
}

///|
/// The Datalog program for ONE function: the deck's four rules and the program's
/// facts.
///
/// AND THE FACTS ARE ADDED AS FACTS AND NOT AS RULES, because that is the difference
/// between EDB and IDB (p.42-43): the program's statements are GIVEN and the rules
/// DERIVE.
pub fn dl_pointer_program(cfgs : Array[Cfg], fi : Int32) -> DProgram {
  let parsed = datalog_parse(dl_pointer_rules_text())
  let facts = dl_facts_of(cfgs, fi)
  let prog = dprog()
  for f in facts.new {
    prog.facts.push(f)
  }
  for f in facts.assign {
    prog.facts.push(f)
  }
  for f in facts.store {
    prog.facts.push(f)
  }
  for f in facts.load {
    prog.facts.push(f)
  }
  for r in parsed.program.rules {
    prog.rules.push(r)
  }
  prog
}

///|
/// The Datalog reading's ANSWER.
pub(all) struct DlAnswer {
  ok : Bool
  /// `VarPointsTo(x, o)` -- the tuples.
  vpt : Array[Array[String]]
  /// `FieldPointsTo(oi, f, oj)` -- the tuples.
  field : Array[Array[String]]
  /// The number of rounds the fixpoint took.
  rounds : Int32
}

///|
/// The Datalog reading's answer: the pointer relation, the field relation, and the
/// number of rounds the fixpoint took.
pub fn dl_pointer_answer(cfgs : Array[Cfg], fi : Int32) -> DlAnswer {
  let prog = dl_pointer_program(cfgs, fi)
  let s = datalog_solve(prog)
  let out = { ok: s.ok, vpt: [], field: [], rounds: s.rounds, }
  if s.ok == false {
    return out
  }
  for t in datalog_tuples(s, "VarPointsTo") {
    out.vpt.push(t)
  }
  for t in datalog_tuples(s, "FieldPointsTo") {
    out.field.push(t)
  }
  out
}

///|
/// The COMPARISON, and it is a COMPARISON and not a NORMALISATION.
///
/// `pta_run`'s POINTERS are the entries of its map whose key is a plain name, and the
/// Datalog reading's pointers are its `VarPointsTo` tuples -- so the two sets are
/// compared as sets of `(name, object)` pairs. The answer is whether they AGREE, and
/// the disagreement is reported with the tuples that differ, because a comparison that
/// can only say "yes" is not a comparison.
pub fn dl_pointer_agrees(cfgs : Array[Cfg], fi : Int32) -> Bool {
  let a = dl_pointer_answer(cfgs, fi)
  let pt = pta_run(cfgs)[fi]
  dl_same_pairs(a.vpt, dl_pta_pointer_pairs(pt))
}

///|
/// `pta_run`'s POINTER entries, as `(name, object)` pairs.
///
/// A FIELD CELL IS NOT A POINTER ENTRY: the key `o1.f` is a place and not a variable,
/// and the deck's relation for it is `FieldPointsTo` and not `VarPointsTo`. So the
/// field cells are left out of the pointer comparison and compared on their own terms.
///
/// AND THE MAP IS ITERATED, NOT INDEXED: `Pta` is `Map[String, Map[String, Bool]]`,
/// and `Map::keys()` returns an ITER and not an array, so the keys are collected into
/// an array first and the sets are compared without an order.
fn dl_pta_pointer_pairs(pt : Pta) -> Array[Array[String]] {
  let out : Array[Array[String]] = []
  let names : Array[String] = []
  for k in pt.keys() {
    names.push(k)
  }
  for name in names {
    // A field cell's key carries a `.`, and the deck's relation for it is
    // `FieldPointsTo` and not `VarPointsTo`.
    if name.contains(".") {
      continue
    }
    let objs = pta_of(pt, name)
    let objnames : Array[String] = []
    for o in objs.keys() {
      objnames.push(o)
    }
    for o in objnames {
      out.push([name, o])
    }
  }
  out
}

///|
/// Whether two sets of pairs are EQUAL, order included in neither.
fn dl_same_pairs(a : Array[Array[String]], b : Array[Array[String]]) -> Bool {
  if a.length() != b.length() {
    return false
  }
  for x in a {
    let mut found = false
    for y in b {
      if x.length() == y.length() && x[0] == y[0] && x[1] == y[1] {
        found = true
        break
      }
    }
    if found == false {
      return false
    }
  }
  true
}

///|
/// Whether the answer holds a tuple -- of ANY arity, because the deck's relations
/// have two and three columns (`VarPointsTo` and `FieldPointsTo`).
pub fn dl_has_tuple(
  tuples : Array[Array[String]],
  want : Array[String],
) -> Bool {
  for t in tuples {
    if t.length() != want.length() {
      continue
    }
    let mut same = true
    let mut i = 0
    while i < t.length() {
      if t[i] != want[i] {
        same = false
        break
      }
      i = i + 1
    }
    if same {
      return true
    }
  }
  false
}

///|
/// A fact as text, `P(a, b)`, so a test can assert the deck's own notation.
pub fn dl_fact_text(f : DFact) -> String {
  f.pred + "(" + f.args.join(", ") + ")"
}

///|
/// Whether a set of facts holds the tuple `P(a, b)`.
///
/// IT IS A SEPARATE FUNCTION and not `dl_has_tuple` applied to the facts' arguments,
/// because a fact carries its PREDICATE as well as its arguments -- and the predicate
/// is what distinguishes `New(p, o1)` from an `Assign(p, o1)` that happens to have the
/// same two arguments.
pub fn dl_has_fact(
  facts : Array[DFact],
  pred : String,
  args : Array[String],
) -> Bool {
  for f in facts {
    if f.pred != pred || f.args.length() != args.length() {
      continue
    }
    let mut same = true
    let mut i = 0
    while i < args.length() {
      if f.args[i] != args[i] {
        same = false
        break
      }
      i = i + 1
    }
    if same {
      return true
    }
  }
  false
}

///|
/// The two readings SIDE BY SIDE, as text, so a difference is visible rather than
/// inferred.
///
/// THE HEADER NAMES THE TWO RELATIONS and the rows are the tuples, because a
/// comparison that prints both answers is a thing a reader can check and a comparison
/// that prints a boolean is a thing they have to take on trust.
pub fn dl_compare_text(cfgs : Array[Cfg], fi : Int32) -> String {
  let a = dl_pointer_answer(cfgs, fi)
  let pt = pta_run(cfgs)[fi]
  let mut out = "VarPointsTo (the deck's rules):\n"
  for t in a.vpt {
    out = out + "  " + t[0] + " -> {" + t[1] + "}\n"
  }
  out = out + "VarPointsTo (pta_run):\n"
  for pair in dl_pta_pointer_pairs(pt) {
    out = out + "  " + pair[0] + " -> {" + pair[1] + "}\n"
  }
  out = out + "FieldPointsTo (the deck's rules):\n"
  for t in a.field {
    out = out + "  " + t[0] + "." + t[1] + " -> {" + t[2] + "}\n"
  }
  out = out + "the field cells (pta_run):\n"
  let names : Array[String] = []
  for k in pt.keys() {
    names.push(k)
  }
  for name in names {
    if name.contains(".") == false {
      continue
    }
    let objs = pta_of(pt, name)
    let objnames : Array[String] = []
    for o in objs.keys() {
      objnames.push(o)
    }
    out = out + "  " + name + " -> {" + objnames.join(",") + "}\n"
  }
  out
}
