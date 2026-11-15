// 0595: THE DECK'S FIRST CHAPTER, MEASURED -- and the deck's last two pages.
//
// THE DECK'S REMAINING CELLS after 0592, 0593 and 0594 are three, and all three are
// BOUNDARIES AND MEASUREMENTS rather than cells to build:
//
//   CHAPTER 1, THE MOTIVATION (p.5-16). The deck's complaint is that the imperative
//   form has implementation details it does not print, and the declarative form has
//   none. p.10-12 prints the imperative `Solve(main)` with a worklist and asks FIVE
//   questions -- the list grows across the three pages, and by p.12 it has five
//   bullets:
//
//     • How to implement worklist?
//     • Array list or linked list?
//     • Which worklist entry should be processed first?
//     • How to implement points-to set (pt)? Hash set or bit vector?
//     • How to connect PFG nodes and pointers?
//
//   and p.15-16 answers with the declarative form and three words: "Succinct /
//   Readable (logic-based specification) / Easy to implement".
//
//   THE LAST TWO PAGES (p.92). Three pros and two cons, and each one is a claim
//   about a Datalog ENGINE -- so each is checked against this tree's engine.
//
//   THE LAST PAGE (p.93). "The X You Need To Understand in This Lecture" -- three
//   things, and each has its own increment.
//
// SO THIS INCREMENT ANSWERS THE FIVE QUESTIONS BY MEASUREMENT, and the answer is
// NOT "the declarative form has no implementation details". It has FEWER: four of
// the five are closed and ONE is still the implementer's -- and the one it keeps is
// the deck's own "Hash set or bit vector?".

///|
/// The deck's FIVE implementation-detail questions (p.10-12), and what this tree's
/// declarative engine does about each.
///
/// IT IS A ROW AND NOT A PROSE ANSWER because a boundary written down in prose is a
/// promise, and a boundary written down in a TEST is a fact the next increment has
/// to argue with.
#derive(Eq)
pub(all) enum DlQuestion {
  /// "How to implement worklist?" (p.10).
  DlWorklist
  /// "Array list or linked list?" (p.10).
  DlWorklistShape
  /// "Which worklist entry should be processed first?" (p.10).
  DlWorklistOrder
  /// "How to implement points-to set (pt)? Hash set or bit vector?" (p.11).
  DlPointSet
  /// "How to connect PFG nodes and pointers?" (p.12).
  DlConnect
}

///|
/// How the declarative form ANSWERS one of the deck's questions, and the answer is
/// one of three things.
#derive(Eq)
pub(all) enum DlQuestionAnswer {
  /// The thing the question is about IS NOT THERE in the declarative form, so
  /// there is nothing to choose.
  DlGone
  /// The thing IS there, and its shape is decided by the PROGRAM -- by the rules
  /// and by the strata -- and not by the implementer.
  DlBySpecification
  /// The thing IS there, and the IMPLEMENTER still chooses its representation,
  /// and so the question is not closed.
  DlByDataStructure
}

///|
/// What this tree's engine does about the deck's question.
///
/// AND THE ANSWER ABOUT THE WORKLIST ORDER IS NOT "GONE", because it is not: the
/// declarative form replaces "which worklist entry first" with "which STRATUM
/// first", and that is the same question wearing a different hat -- and 0594 found
/// the cost of getting it wrong, in this tree's own engine.
pub fn dl_answer_of(q : DlQuestion) -> DlQuestionAnswer {
  match q {
    // THE WORKLIST IS GONE, and the fixpoint is a `while changed` loop over the
    // strata: there is no queue, no entry to remove and no order to choose.
    DlWorklist => DlGone
    // AND WITH THE WORKLIST ITS SHAPE GOES TOO: "array list or linked list" is a
    // question about a data structure that is not there.
    DlWorklistShape => DlGone
    // AND THE ORDER SURVIVES AS THE STRATA, which is the deck's own p.92 cons line
    // -- "Cannot fully control performance" -- and 0594 is what it cost this tree.
    DlWorklistOrder => DlBySpecification
    // AND THE POINTS-TO SET IS NOT GONE: the specification says the set HOLDS
    // TUPLES and the engine stores them in a HASH SET of tuple keys -- which is
    // the very "hash set or bit vector" the deck's question asks about. The
    // declarative form answers the question about WHAT the set is; it does not
    // answer the question about HOW it is stored.
    DlPointSet => DlByDataStructure
    // AND THE POINTER FLOW GRAPH IS GONE TOO: there is no PFG whose nodes have to
    // be connected, because the rules connect the facts directly
    // (`VarPointsTo(x, o) <- Assign(x, y), VarPointsTo(y, o).`). The imperative
    // side of THIS tree still builds one -- that is what `pta_run` is -- and the
    // declarative side does not need it.
    DlConnect => DlGone
  }
}

///|
/// The answer's own NAME, so a caller can compare it without an `impl Debug`.
///
/// AND IT IS THE HOUSE PATTERN: `Family` has one, and the tests here compare
/// names rather than enum values, because `assert_eq` needs a `Debug` and a
/// family name is what a reader wants to see anyway.
pub fn DlQuestionAnswer::name(self : DlQuestionAnswer) -> String {
  match self {
    DlGone => "DlGone"
    DlBySpecification => "DlBySpecification"
    DlByDataStructure => "DlByDataStructure"
  }
}

///|
/// The deck's five questions, in the deck's order.
pub fn dl_questions() -> Array[DlQuestion] {
  [DlWorklist, DlWorklistShape, DlWorklistOrder, DlPointSet, DlConnect]
}

///|
/// The deck's question as text, so a test can assert the deck's own WORDS and not a
/// paraphrase of them.
pub fn dl_question_text(q : DlQuestion) -> String {
  match q {
    DlWorklist => "How to implement worklist?"
    DlWorklistShape => "Array list or linked list?"
    DlWorklistOrder => "Which worklist entry should be processed first?"
    DlPointSet => "How to implement points-to set (pt)? Hash set or bit vector?"
    DlConnect => "How to connect PFG nodes and pointers?"
  }
}

///|
/// The answer as text, for the same reason.
pub fn dl_answer_text(a : DlQuestionAnswer) -> String {
  match a {
    DlGone => "gone: the declarative form has no such thing to choose"
    DlBySpecification =>
      "answered by the program: the strata decide, and the implementer cannot"
    DlByDataStructure => "answered by a data structure, and so not closed"
  }
}

///|
/// The questions that are STILL OPEN -- the ones the implementer still owns.
///
/// AND THIS IS THE MEASUREMENT OF THE DECK'S FIRST CHAPTER: the imperative form
/// prints FIVE questions and answers none of them (p.10-12), and the declarative
/// form closes FOUR of them and leaves ONE. The one it leaves is the points-to
/// set's representation, and the deck's own question names the two options: "Hash
/// set or bit vector?".
pub fn dl_open_questions() -> Array[DlQuestion] {
  let out = []
  for q in dl_questions() {
    if dl_answer_of(q) == DlByDataStructure {
      out.push(q)
    }
  }
  out
}

///|
/// The deck's p.92: a PRO or a CON.
#derive(Eq)
pub(all) enum DlClaimKind {
  DlPros
  DlCons
}

///|
/// The deck's THREE PROS AND TWO CONS (p.92), and what this tree's engine says about
/// each.
///
/// IT IS A ROW AND NOT PROSE for the reason the five questions are: each is a claim
/// about an engine, and a claim about an engine is checked by running the engine.
pub(all) struct DlClaim {
  /// The claim's own words, as p.92 prints them.
  text : String
  /// Whether p.92 lists it as a pro or as a con.
  kind : DlClaimKind
  /// Whether this tree's engine has the property the claim names.
  holds : Bool
  /// Why, in one line.
  why : String
}

///|
/// The deck's p.92, checked against this tree's engine.
///
/// THE PROS ARE THREE and the CONS ARE TWO, and the counts are part of the claim:
/// p.92's own list is what this increment measures against, and `dl_pros` and
/// `dl_cons` are the counts as facts rather than as a sentence.
pub fn dl_claims() -> Array[DlClaim] {
  [
    {
      text: "Succinct and readable",
      kind: DlPros,
      holds: true,
      why: "the deck's six rules are six lines of text, and they round-trip verbatim",
    },
    {
      text: "Easy to implement",
      kind: DlPros,
      holds: true,
      why: "the declarative form closes FOUR of the deck's FIVE questions and leaves ONE",
    },
    {
      text: "Benefit from off-the-shelf optimized Datalog engines",
      kind: DlPros,
      holds: false,
      why: "this tree has its OWN engine, and 0594 is what owning one cost: a strata-ordering bug that lost a whole stratum",
    },
    {
      text: "Restricted expressiveness, i.e., it is impossible or inconvenient to express some logics",
      kind: DlCons,
      holds: true,
      why: "an unsafe rule and a recursion-and-negation conflict are both REFUSED",
    },
    {
      text: "Cannot fully control performance",
      kind: DlCons,
      holds: true,
      why: "the evaluation order is the STRATA's, and the engine cannot choose it",
    },
  ]
}

///|
/// The deck's p.92 PROS, and their count.
pub fn dl_pros() -> Array[DlClaim] {
  let out = []
  for c in dl_claims() {
    if c.kind == DlPros {
      out.push(c)
    }
  }
  out
}

///|
/// The deck's p.92 CONS, and their count.
pub fn dl_cons() -> Array[DlClaim] {
  let out = []
  for c in dl_claims() {
    if c.kind == DlCons {
      out.push(c)
    }
  }
  out
}

///|
/// One of the deck's THREE THINGS (p.93), and the increment that did it.
pub(all) struct DlThing {
  /// The deck's own words.
  text : String
  /// The increment that built it.
  increment : String
}

///|
/// The deck's p.93: "The X You Need To Understand in This Lecture" -- THREE things.
///
/// AND THE COUNT IS A FACT AND NOT A SENTENCE: this is the list the deck says the
/// lecture is FOR, and every entry names the increment that answered it, so a
/// future increment can see at a glance whether an entry is still open.
pub fn dl_things() -> Array[DlThing] {
  [
    { text: "Datalog language", increment: "0592", },
    {
      text: "How to implement pointer analysis via Datalog",
      increment: "0593",
    },
    { text: "How to implement taint analysis via Datalog", increment: "0594", },
  ]
}
