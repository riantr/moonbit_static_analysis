// predicate: A FINDING AS A MACHINE-CHECKABLE ASSERTION.
//
// 0523. A finding is a claim -- "this name has no visible binding", "this local
// is never read". Until now the claim existed only as PROSE: a rendered line, or
// a `message` string in the JSON. A consumer that wanted to act on it had to
// parse English, so the only machine-readable part of a finding was its family
// and its line, and the evidence inside the claim was lost at the boundary.
//
// A predicate is that evidence, restated in a form a program can switch on:
// a stable `check` name plus the arguments the check needs. It is NOT a second
// analyzer. It says WHICH question the analyzer answered and WHICH name it
// answered it about, so a reader can re-ask that one question by hand or by
// script and get the same answer -- which is the difference between "the tool
// said so" and "this is checkable".
//
// WHERE IT IS NOT MEANINGFUL, THERE IS NO PREDICATE (`None`), and each absence
// is a decision rather than an omission:
//
//   ParseError        a declared scope limit is a statement about what the
//                     analyzer READ. There is no property of the program to
//                     restate, and inventing a check would turn "I did not look"
//                     into "I looked and found nothing".
//   AssignTypeMismatch / ArgTypeMismatch / OperatorMismatch / MethodError /
//   NonBooleanCond    the claim is a RELATION BETWEEN TYPES. To check it a
//                     consumer would have to reimplement the type model, and a
//                     second incomplete type system that disagrees with the
//                     first is worse than no assertion at all.
//
// The check ids are ALLOCATED and NEVER RENAMED, for the same reason the family
// ids are: a consumer switches on them.
//
// THE NAME IS READ OUT OF THE MESSAGE, and that is a deliberate liability with a
// guard. Deriving it here keeps the predicate in ONE place instead of thirty
// construction sites that could each forget it, and a finding whose message has
// no quoted name yields NO predicate -- absence rather than a guess. The
// liability is that renaming a message would silently drop predicates, so
// `report_0523_test.mbt` pins every check against the REAL message text: change
// a message and the test goes red rather than the JSON going quiet.

///|
/// What a consumer can check, and about what.
pub(all) struct Predicate {
  /// The question, as a stable id. Never renamed.
  check : String
  /// Its arguments, in a fixed order per check, as (key, value) pairs so the
  /// JSON is self-describing and a checker can read them by name rather than by
  /// position.
  params : Array[(String, String)]
}

///|
/// The first single-quoted run in `text`, or `None`.
///
/// Every Name-shaped family in this repository quotes its subject -- `no visible
/// binding for 'x'`, `parameter 'p' changed by assignment` -- which is what makes
/// one extractor enough. `None` on anything unquoted, so a message that stops
/// quoting its subject loses its predicate instead of reporting an empty name,
/// and an empty name is the one value a checker cannot tell from a real one.
fn quoted(text : String) -> String? {
  let mut buf = StringBuilder()
  let mut inside = false
  for c in text {
    if c == '\'' {
      if inside {
        return Some(buf.to_string())
      }
      inside = true
      buf = StringBuilder()
    } else if inside {
      buf.write_char(c)
    }
  }
  None
}

///|
/// The assertion this finding makes, when it makes one a machine could check.
pub fn Report::predicate(self : Report) -> Predicate? {
  let line = "\{self.span.start.line}"
  let col = "\{self.span.start.col}"
  let subject = match quoted(self.message) {
    Some(n) => n
    None => ""
  }
  // A name-based check with no name is not a weaker assertion, it is an
  // assertion about nothing. Refuse it here rather than let a consumer read
  // `name: ""` and test the empty string against the source.
  let named = subject != ""
  match self.family {
    @core.FUndefinedName =>
      if named {
        Some({
          check: "no_visible_binding",
          params: [("name", subject), ("line", line), ("col", col)],
        })
      } else {
        None
      }
    @core.FUnusedLocal =>
      if named {
        Some({
          check: "local_never_read",
          params: [("name", subject), ("line", line), ("col", col)],
        })
      } else {
        None
      }
    @core.FUnusedParam =>
      if named {
        Some({
          check: "param_never_read",
          params: [("name", subject), ("line", line), ("col", col)],
        })
      } else {
        None
      }
    @core.FParamChanged =>
      if named {
        Some({
          check: "param_reassigned",
          params: [("name", subject), ("line", line), ("col", col)],
        })
      } else {
        None
      }
    // 0522's two families: the evidence is the binding whose path condition is
    // empty (or already implies the test), so the check is about that name.
    @core.FInfeasibleBranch =>
      if named {
        Some({
          check: "path_domain_empty",
          params: [("name", subject), ("line", line), ("col", col)],
        })
      } else {
        None
      }
    @core.FRedundantGuard =>
      if named {
        Some({
          check: "guard_already_forced",
          params: [("name", subject), ("line", line), ("col", col)],
        })
      } else {
        None
      }
    // The claim is about POSITION, not about a name: "a statement at this line
    // follows one whose flow had already left the block". A checker reads the
    // line and the control flow above it, so the line is the argument.
    @core.FUnreachable =>
      Some({ check: "after_flow_exit", params: [("line", line), ("col", col)], })
    // A stale suppression asserts that NO finding of a given family sits on a
    // given line. The line is the whole claim, so that is the whole predicate.
    @core.FStaleNosec =>
      Some({
        check: "suppression_matches_no_finding",
        params: [("line", line)],
      })
    // Deliberate absences; see the file header for why each one is a decision.
    // FParse is a scope limit, and the five type families need the type model.
    @core.FParse
    | @core.FAssignType
    | @core.FArgType
    | @core.FOpMismatch
    | @core.FMethodError
    | @core.FCondBool => None
  }
}

///|
/// Render a predicate for the text report. Kept beside the projection rather
/// than in the renderer so the two cannot describe different assertions.
pub fn Predicate::render(self : Predicate) -> String {
  let parts : Array[String] = []
  for p in self.params {
    parts.push("\{p.0}=\{p.1}")
  }
  "\{self.check}(\{parts.join(", ")})"
}
