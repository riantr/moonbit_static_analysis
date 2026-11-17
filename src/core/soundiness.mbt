// 0602: SOUNDINESS -- the deck's three-way verdict, DERIVED per family.
//
// THE DECK. `Soundiness` (Yue Li and Tian Tan, Nanjing University, 2021 Fall,
// 68 pages), p.14:
//
//   A soundy analysis aims to capture all dynamic behaviors with certain hard
//   language features unsoundly handled within reason
//   A sound analysis requires to capture all dynamic behaviors
//   An unsound analysis deliberately ignores certain behaviors in its design
//   for better efficiency, precision or accessibility
//
// and p.13:
//
//   A soundy analysis typically means that the analysis is mostly sound, with
//   well-identified unsound treatments to hard/specific language features
//
// AND p.10 IS THE COMPLAINT THIS INCREMENT ANSWERS:
//
//   Treatments to hard language features are usually omitted or only mentioned
//   in an off-hand manner in some impl/eval parts in papers
//
//   Then claiming soundness in papers may mislead readers: for experts, it is
//   still hard for them to interpret the analysis results (how sound, fast,
//   precise is the analysis) without a clear explanation about how they treat
//   those important and hard language features
//
// SO THE TREE SAYS WHAT THE DECK SAYS IS MISSING: EVERY unsound treatment it
// has, NAMED, with the CAUSE that decides the verdict -- and a verdict DERIVED
// from that cause rather than asserted per family.
//
// THE DECK'S THREE WORDS ARE NOT THREE OPINIONS, and the difference between
// them is the CAUSE of the gap:
//
//   Sound       the family excludes nothing: it covers every behaviour it can
//               reach.
//   Soundy      the gap is caused by a HARD LANGUAGE FEATURE the analyzer
//               cannot model -- an unknown type, an unread region, a construct
//               outside the declared subset, a callee whose signature was never
//               read. The deck's p.13 calls this a "well-identified unsound
//               treatment to a hard/specific language feature", and the gap is
//               DISCLOSED, so the family is soundy rather than unsound.
//   Unsound     the gap is a DELIBERATE choice -- for efficiency, precision or
//               accessibility. The deck's p.14: "deliberately ignores certain
//               behaviors in its design for better efficiency, precision or
//               accessibility".
//
// A FAMILY WITH BOTH IS UNSOUND, because one deliberate gap is enough: the
// reader has to know about it, and a family that hides it behind a hard
// feature is the case the deck's p.10 is about.
//
// AND THE VERDICT IS NOT TYPED PER FAMILY. Each family declares its
// EXCLUSIONS, and the verdict is computed from their causes. A verdict written
// out by hand is a third table to keep right, and this tree has already been
// bitten by a hand-written table that rotted (`Family::id`).

///|
/// THE VERDICT, in the deck's three words.
#derive(Eq)
pub(all) enum Soundiness {
  /// The analysis requires to capture all dynamic behaviors: no exclusion.
  Sound
  /// The analysis is mostly sound, with well-identified unsound treatments to
  /// hard/specific language features.
  Soundy
  /// The analysis deliberately ignores certain behaviors in its design for
  /// better efficiency, precision or accessibility.
  Unsound
}

///|
/// The deck's three words, as one word each.
pub fn Soundiness::name(self : Soundiness) -> String {
  match self {
    Sound => "sound"
    Soundy => "soundy"
    Unsound => "unsound"
  }
}

///|
/// WHY a family excludes what it excludes. This is the whole of the deck's
/// p.14: the three verdicts differ by the CAUSE of the gap, not by how big it
/// is.
#derive(Eq)
pub(all) enum ExclusionCause {
  /// A HARD LANGUAGE FEATURE the analyzer cannot model: an unknown type, an
  /// unread region, a construct outside the declared subset, a callee whose
  /// signature was never read, or a question that is undecidable in general.
  HardFeature
  /// A DELIBERATE choice, for efficiency, precision or accessibility.
  Deliberate
}

///|
/// The cause, as one word.
pub fn ExclusionCause::name(self : ExclusionCause) -> String {
  match self {
    HardFeature => "hard feature"
    Deliberate => "deliberate"
  }
}

///|
/// ONE exclusion of ONE family: a stable id, the cause that decides the
/// verdict, and the words in the family's own contract that the exclusion is.
///
/// AND THE `text` IS A QUOTE, not a paraphrase, and the roster gate checks
/// that it really is a quote: the id is the name a reader cites, and the text
/// is the proof that the exclusion is the family's own and not a second list
/// that drifted away from the contract.
pub(all) struct Exclusion {
  /// The stable id. Never renumbered, like a family id: a reader cites it.
  id : String
  /// The cause, which decides the family's verdict.
  cause : ExclusionCause
  /// The words in the family's `excluded` contract that this exclusion is.
  text : String
}

///|
/// EVERY exclusion of this family, with the cause of each.
///
/// AND THE ORDER IS THE CONTRACT'S ORDER, so the reader can read the list
/// against the family's `excluded` text and see the same exclusions in the
/// same sequence.
pub fn Family::exclusions(self : Family) -> Array[Exclusion] {
  match self {
    FParse =>
      [
        Exclusion::{
          id: "X-PARSE-SUBSET",
          cause: HardFeature,
          text: "nothing about the skipped construct's meaning",
        },
      ]
    FUndefinedName =>
      [
        Exclusion::{
          id: "X-NAME-EXTERNAL-BINDING",
          cause: HardFeature,
          text: "names a dependency or a macro could bind",
        },
      ]
    FUnusedLocal =>
      [
        Exclusion::{
          id: "X-LOCAL-UNREAD-REGION",
          cause: HardFeature,
          text: "reads inside a region the parser cut in half",
        },
      ]
    FUnusedParam =>
      [
        Exclusion::{
          id: "X-PARAM-UNREAD-REGION",
          cause: HardFeature,
          text: "any read in a function whose text contains an unread region",
        },
      ]
    FParamChanged =>
      [
        Exclusion::{
          id: "X-PARAMCHANGED-UNREAD-REGION",
          cause: HardFeature,
          text: "an unread region silences it",
        },
      ]
    FAssignType =>
      [
        Exclusion::{
          id: "X-ASSIGN-REBIND-JOIN",
          cause: HardFeature,
          text: "unannotated rebinding, which widens with a join",
        },
        Exclusion::{
          id: "X-ASSIGN-FIELD-TARGET",
          cause: HardFeature,
          text: "field assignment targets, which are unchecked",
        },
      ]
    FArgType =>
      [
        Exclusion::{
          id: "X-ARG-TYPE-NO-SIGNATURE",
          cause: HardFeature,
          text: "calls to a callee with no visible signature",
        },
        Exclusion::{
          id: "X-ARG-TYPE-NAMED-ARITY",
          cause: Deliberate,
          text: "named-call arity",
        },
      ]
    FOpMismatch =>
      [
        Exclusion::{
          id: "X-OP-UNKNOWN-TYPE",
          cause: HardFeature,
          text: "unknown operand types",
        },
        Exclusion::{
          id: "X-OP-PIPE-EXEMPT",
          cause: Deliberate,
          text: "the pipe operator and regex-match operands are exempt",
        },
      ]
    FMethodError =>
      [
        Exclusion::{
          id: "X-METHOD-PERFILE-TABLE",
          cause: HardFeature,
          text: "a call outside the per-file method table",
        },
      ]
    FCondBool =>
      [
        Exclusion::{
          id: "X-COND-UNKNOWN-OR-FOLDED",
          cause: HardFeature,
          text: "constant-folded conditions and unknown types",
        },
      ]
    FUnreachable =>
      [
        Exclusion::{
          id: "X-UNREACH-PATH-FEASIBILITY",
          cause: HardFeature,
          text: "path feasibility, which needs semantics and is undecidable in general",
        },
      ]
    FStaleNosec =>
      [
        Exclusion::{
          id: "X-NOSEC-REALITY",
          cause: Deliberate,
          text: "whether the suppressed finding was real",
        },
      ]
    FInfeasibleBranch =>
      [
        Exclusion::{
          id: "X-INFEASIBLE-UNDECIDABLE",
          cause: HardFeature,
          text: "undecidable in general, so a branch this model cannot decide is counted UNDECIDED",
        },
      ]
    FRedundantGuard =>
      [
        Exclusion::{
          id: "X-REDUNDANT-MUTATED-OPERAND",
          cause: HardFeature,
          text: "a test whose operand was mutated after the binding carries no fact",
        },
      ]
    FDeadStore =>
      [
        Exclusion::{
          id: "X-DEADSTORE-UNMODELLED-READ",
          cause: HardFeature,
          text: "reads this graph does not model",
        },
      ]
    FDivisionByZero =>
      [
        Exclusion::{
          id: "X-DIVZERO-UNKNOWN-SIGN",
          cause: HardFeature,
          text: "a divisor whose sign the analysis could NOT pin down is not reported",
        },
      ]
    FNegativeIndex =>
      [
        Exclusion::{
          id: "X-NEGIDX-UNKNOWN-SIGN",
          cause: HardFeature,
          text: "an index whose sign the analysis could NOT pin down is not reported",
        },
      ]
    FTaintFlow =>
      [
        Exclusion::{
          id: "X-TAINT-IMPLICIT-FLOWS",
          cause: HardFeature,
          text: "a branch on tainted data, a termination channel, a timing channel and an exception channel are NOT analysed",
        },
      ]
  }
}

///|
/// THE VERDICT FOR THIS FAMILY, DERIVED from its exclusions' causes.
///
/// AND THE DERIVATION IS THE WHOLE POINT. A verdict written out by hand would
/// be a third table, and a hand-written table is a table that rots: a family
/// whose exclusion changed cause would keep its old verdict, and nothing would
/// say so. Here the verdict CANNOT disagree with the causes, because it is
/// computed from them.
pub fn Family::soundiness(self : Family) -> Soundiness {
  let ex = self.exclusions()
  if ex.length() == 0 {
    return Sound
  }
  for e in ex {
    if e.cause == Deliberate {
      return Unsound
    }
  }
  Soundy
}

///|
/// EVERY exclusion in the roster, as one array, so a reader can count the
/// treatments and cite them without walking the families one at a time.
pub fn all_exclusions() -> Array[Exclusion] {
  let out : Array[Exclusion] = []
  for f in all_families() {
    for e in f.exclusions() {
      out.push(e)
    }
  }
  out
}

///|
/// THE COUNTS, as `(sound, soundy, unsound)` -- the number of FAMILIES in each
/// class, measured over the roster rather than asserted.
pub fn soundiness_counts() -> (Int32, Int32, Int32) {
  let mut sound = 0
  let mut soundy = 0
  let mut unsound = 0
  for f in all_families() {
    match f.soundiness() {
      Sound => sound += 1
      Soundy => soundy += 1
      Unsound => unsound += 1
    }
  }
  (sound, soundy, unsound)
}

///|
/// THE VERDICT FOR THE WHOLE ANALYSIS, which is the worst verdict any family
/// carries: one deliberately ignored behaviour is enough, because the reader
/// has to know about it.
pub fn soundiness_verdict() -> Soundiness {
  for f in all_families() {
    if f.soundiness() == Unsound {
      return Unsound
    }
  }
  for f in all_families() {
    if f.soundiness() == Soundy {
      return Soundy
    }
  }
  Sound
}

///|
/// THE UNSOUND TREATMENTS, and nothing else: every exclusion whose cause is
/// DELIBERATE, across the whole roster.
///
/// AND THIS IS THE LIST THE DECK'S p.10 SAYS IS MISSING FROM PAPERS. It is
/// small, it is named, and each entry says what the analyzer chose not to do.
pub fn unsound_treatments() -> Array[Exclusion] {
  let out : Array[Exclusion] = []
  for e in all_exclusions() {
    if e.cause == Deliberate {
      out.push(e)
    }
  }
  out
}

///|
/// THE ROSTER, as `--explain-all` prints it: every family with its verdict,
/// and every exclusion with its cause.
pub fn soundiness_roster() -> String {
  let mut s = "soundiness, per family -- the deck's three-way verdict, derived from the cause of each exclusion\n\n"
  for f in all_families() {
    let ex = f.exclusions()
    let n = ex.length()
    s = s + "  \{f.id()}  \{f.name()}  --  \{f.soundiness().name()}"
    s = s + "  (\{n} exclusion\{if n == 1 { "" } else { "s" }})\n"
    for e in ex {
      s = s + "      \{e.id}  \{e.cause.name()}  --  \{e.text}\n"
    }
  }
  s = s + "\n"
  let (sound, soundy, unsound) = soundiness_counts()
  s = s + "  families: sound=\{sound}  soundy=\{soundy}  unsound=\{unsound}\n"
  s = s + "  the analysis as a whole: \{soundiness_verdict().name()}\n"
  let un = unsound_treatments()
  s = s + "  deliberate (unsound) treatments: \{un.length()}\n"
  for e in un {
    s = s + "      \{e.id}  \{e.text}\n"
  }
  s
}

///|
/// ONE family's soundiness, as `--explain` prints it: the verdict, and the
/// exclusions that decided it.
pub fn soundiness_family(f : Family) -> String {
  let mut s = "  soundiness  \{f.soundiness().name()}\n"
  for e in f.exclusions() {
    s = s + "  exclusion   \{e.id}  \{e.cause.name()}  --  \{e.text}\n"
  }
  s
}
