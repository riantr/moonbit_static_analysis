// `--explain`: a family's CONTRACT, at the command line.
//
// WHY THIS EXISTS. The analyzer's families are DETECTORS by default: an id, a
// severity, a confidence. That is enough to filter and to suppress, and it is
// not enough to know what the tool just told you. The distinction is the
// classical one between detecting a shape and VERIFYING a property: an
// assertion is only meaningful relative to a specification of intent, and a
// specification the reader cannot see is not one.
//
// So every family carries three parts, and none of them is decoration:
//
//   property    what it asserts, in one line
//   assumption  the condition under which that assertion is SOUND -- what must
//               be true of the program for the finding to mean what it says
//   excluded    what it deliberately does NOT cover, so that a clean scan is
//               not read as a stronger claim than it is
//
// THE CONTRACT IS DATA, NOT PROSE IN A DOCUMENT. It lives in `src/core` beside
// the id, so `--explain` cannot drift from the families the analyzer actually
// emits; `check_family_roster.ps1` requires a non-empty value for every family,
// which is what stops "we will document it later" from shipping.

///|
/// One family's contract, labelled, as `--explain MSA-0NN` prints it.
///
/// The three labels are printed even when a part is a sentence, because a
/// reader comparing two families is comparing the same three slots.
pub fn explain_family(f : @core.Family) -> String {
  let mut s = "\{f.id()}  \{f.name()}\n"
  s = s + "\n  property    \{f.property()}\n"
  s = s + "\n  assumption  \{f.assumption()}\n"
  s = s + "\n  excluded    \{f.excluded()}\n"
  s
}

///|
/// The roster: every family, with the property it asserts.
///
/// This is the page a reader wants FIRST -- "what can this tool tell me at
/// all" -- and it is derived from `@core.all_families()`, so it cannot list a
/// family the analyzer does not have.
pub fn explain_roster() -> String {
  let mut s = "families: id, name, and the property each one asserts\n\n"
  for f in @core.all_families() {
    s = s + "  \{f.id()}  \{f.name()}  --  \{f.property()}\n"
  }
  s = s +
    "\n--explain MSA-0NN prints one family's full contract: what it asserts, the assumption under which that is sound, and what it does not cover.\n"
  s
}

///|
/// `--explain <id>`: one family's contract. An id that names no family is an
/// ERROR rather than an empty page, for the same reason `family_by_id` returns
/// `None` rather than defaulting to some family -- an id that names nothing is
/// a typo, and a typo answered with silence looks like "no such problem".
pub fn explain_id_value(id : String) -> String {
  match @core.family_by_id(id) {
    Some(f) => explain_family(f)
    None => "ERROR\tno family with id '\{id}'; --explain-all lists the ids"
  }
}
