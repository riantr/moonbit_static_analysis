// report: the report layer of the unified finding model. Report carries the
// lens list and virtual stack (Array fields), so it lives apart from the
// pure lens/family/span kernel in src/core — the kernel is proof-enabled
// (moon prove lowers it to Why3), and the experimental proof lowering is
// limited to packages without Array-carrying structs. Everything here is
// plain runtime code: rendering, snapshotting, summary counts.

///|
/// One pipeline finding: family + the lens(es) that saw it + message +
/// span + owned virtual stack. merge_findings unifies echoes of the same
/// defect into a single Report whose lens list is the union.
pub(all) struct Report {
  family : @core.Family
  lenses : Array[@core.Lens]
  message : String
  span : @core.Span
  vst : Array[@core.Frame]
}

///|
fn lens_tag(lenses : Array[@core.Lens]) -> String {
  let sorted = lenses.copy()
  sorted.sort_by(fn(a : @core.Lens, b : @core.Lens) {
    if a.rank() < b.rank() {
      -1
    } else if a.rank() > b.rank() {
      1
    } else {
      0
    }
  })
  let names : Array[String] = []
  for l in sorted {
    if !names.contains(l.name()) {
      names.push(l.name())
    }
  }
  if names.length() == 0 {
    // A finding no lens produced -- the stale-suppression finding of 0507 --
    // carries no lens at all. An empty bracket would read as a rendering
    // accident, so the tag says so.
    return "-"
  }
  names.join("+")
}

///|
/// Is this report a NOTICE -- a finding the analyzer does NOT STAND BEHIND --
/// rather than a defect in the code that was analysed?
///
/// ONE definition, and every caller must use it. The rendered label, the
/// SUMMARY's `actionable` count and the mermaid drawing all answer the same
/// question, and a second copy of the question somewhere else is how a diagram
/// ends up drawing a defect as a notice while the number beside it says the
/// opposite.
///
/// TWO KINDS OF NOTICE, AND `confidence` IS WHAT TELLS THEM APART:
///
///   * a DECLARED SCOPE LIMIT -- "this construct is outside the analyzed
///     subset; it was read but not analysed" -- is the analyzer saying it could
///     not DECIDE at all. Its confidence is `undecided`.
///   * a LOW-CONFIDENCE finding -- the analyzer decided, but on less than it
///     would like: the family reasons from a NAME alone. Its confidence is
///     `low`.
///
/// 0508. The second kind was NOT a notice before, and it is the answer to the
/// question bandit answers with `Issue.filter`: an issue carries a severity AND
/// a confidence, and a finding the analyzer is not sure about does not clear
/// the actionable threshold. IT IS DEMOTED, NOT HIDDEN. The finding is still
/// rendered, still counted, and still carries its family, its stable id and
/// its confidence -- so a reader sees it and a machine sees it. What changes is
/// the LABEL and the counts: a low-confidence finding is rendered `notice:`,
/// and it is counted in `notices` rather than in `actionable`.
///
/// WHY IT IS NOT `family == FParse`. FParse is ONE family carrying TWO
/// meanings: a deliberate exclusion ("match expression is outside the analyzed
/// subset; it was read but not analysed") and a genuine defect (an
/// unterminated string literal, a malformed interface line, a read failure).
/// The two arrive from different producers -- `Parser::note_skip` and
/// `moonfiles`' subset skip on one side, the lexer's eight malformed-literal
/// reports, `moonfiles`' eight malformed-interface reports and the parser's
/// `err()` on the other -- and only the first kind is the analyzer's own
/// declared limit.
///
/// MEASURED (2026-10-30), with the per-file printing cap lifted so the count
/// is the whole finding set and not the first 40 of each file: across the
/// seven corpora and this repository's own source, 23,331 rendered ParseError
/// lines, EVERY ONE of them a deliberate exclusion, and not one of the
/// seventeen genuine-defect producers carrying the marker. On today's corpora
/// the two predicates therefore agree NUMERICALLY -- which is why this change
/// moves no count -- but only one of them is right, and the wrong one is the
/// one that called a scope limit an `error:`.
pub fn Report::is_notice(self : Report) -> Bool {
  self.is_declared_scope_limit() || self.confidence() == @core.Low
}

///|
/// Is this report a DECLARED SCOPE LIMIT -- the analyzer saying it could not
/// DECIDE AT ALL?
///
/// The narrower question, kept apart from `is_notice` because the two say
/// DIFFERENT things: a scope limit is `undecided` (the analyzer read nothing
/// it could judge), and a low-confidence finding is `low` (the analyzer judged,
/// on less than it would like). Both are notices; only the first is a scope
/// limit.
///
/// It is `pub` because the SOURCE convention it holds in place is checked
/// against the source by `_verify/check_notice_labels.ps1`: every producer of
/// an `FParse` report is told apart by MECHANISM there, never by its text, so
/// the marker and the mechanism cannot drift apart.
pub fn Report::is_declared_scope_limit(self : Report) -> Bool {
  self.family == @core.FParse && is_scope_limit(self.message)
}

///|
/// The label this report is rendered with: `error`, `warning`, `hint`, or
/// `notice`.
///
/// A notice gets its OWN label rather than borrowing `error`. Borrowing it is
/// what made a declared scope limit read as a defect in the reader's code --
/// and a reader who sees `error:` on "match expression is outside the analyzed
/// subset" has been told their code is wrong when the analyzer is the one that
/// did not read it.
///
/// `Family::severity()` is untouched by this: it is the SEVERITY of the family
/// (FParse is an error-severity family, and `severity_taxonomy_holds` in
/// `src/core/core_proof.mbtp` proves it), and it is not what decides whether a
/// finding is actionable. The actionability question is `is_notice`, and the
/// count that answers it is `v.notices`.
///
/// 0508. A LOW-CONFIDENCE FINDING IS DEMOTED HERE TOO, and the family severity
/// it loses is not lost: the rendered bracket still carries the family name,
/// the family's stable id and the confidence, and the family's own severity is
/// a documented property of the family (`Family::severity`). What the label
/// says is WHICH AXIS THE FILTER ACTED ON -- a finding the analyzer stands
/// behind keeps its severity, and a finding it does not is a `notice:`.
pub fn Report::severity_label(self : Report) -> String {
  if self.is_notice() {
    return "notice"
  }
  match self.family.severity() {
    @core.Error => "error"
    @core.Warning => "warning"
    @core.Hint => "hint"
  }
}

///|
/// The marker a declared scope limit carries.
///
/// Every deliberate exclusion message says the construct is outside a SUBSET of
/// what the analyzer reads -- "outside the analyzed subset" in the program
/// frontend, "outside the analyzer's MoonBit subset" in the literate frontend.
/// No genuine-defect message contains the word: the lexer's are about
/// malformed literals and escapes, `moonfiles`' are about malformed interface
/// text, and the parser's read failures are token-level reasons.
///
/// => the marker is a CONVENTION, so it is held in place by
///    `_verify/check_notice_labels.ps1`, which reads every FParse construction
///    site in `src/` and checks that it agrees with this predicate. A new
///    exclusion message that stops carrying the marker fails the gate instead
///    of quietly going back to being an `error:`.
fn is_scope_limit(message : String) -> Bool {
  message.contains("subset")
}

///|
/// The confidence of this finding: how much the lens CHECKED when it produced
/// it.
///
/// 0507. ONE definition, and every consumer uses it -- the rendered line, the
/// JSON record, and the per-confidence counts. A second copy of the question
/// somewhere else is how a diagram ends up drawing a defect as a notice while
/// the number beside it says the opposite.
///
/// THE RULE, and it is the 0505 plan's three situations exactly:
///
///   * a scope limit -- "this construct is outside the analyzed subset" -- is
///     the lens saying it could not DECIDE. `undecided`.
///   * a finding whose family reasons from a NAME alone is `low`. The only one
///     is `UndefinedName`: the analyzer found no binding for the name, and the
///     binding it could not find may be in a file, or in a package, it was
///     never given -- or, for the state-machine audit, in a machine the caller
///     never gave. A reader who is told this is told the truth about it.
///   * everything else had the declaration, the signature or the type in front
///     of the lens, and is `high`.
///
/// 0508. THE `low` CASE IS THE ONE THE FILTER ACTS ON. `bandit` filters an
/// issue by its severity AND its confidence, and a finding the analyzer is not
/// sure about does not clear the threshold. The threshold here is
/// `Report::is_notice`: a `low` finding is demoted to a `notice:` and is
/// counted as a notice, so it is not in the `actionable` count -- and it is
/// NOT HIDDEN, because the demotion changes the label and the counts and
/// nothing else.
///
/// THE SCOPE LIMIT IS TOLD FROM THE LOW FINDING BY MECHANISM, NOT BY THE
/// CONFIDENCE. `is_notice` asks two questions and `confidence` answers one:
/// the scope-limit question is the family AND the marker, and the
/// low-confidence question is the family alone. So `confidence` asks the
/// SCOPE-LIMIT question (`is_declared_scope_limit`), and never asks
/// `is_notice` -- the two would otherwise be each other's answer, and a pair
/// of mutually recursive predicates is a pair that can both be wrong in a way
/// nothing notices.
///
/// COMPUTED, NOT A FIELD. A field would have to be filled in at every one of
/// the thirty-odd places a Report is constructed, and a missed one would be a
/// finding with the wrong confidence and no way to notice. A function has one
/// definition and cannot drift.
pub fn Report::confidence(self : Report) -> @core.Confidence {
  if self.is_declared_scope_limit() {
    return @core.Undecided
  }
  if self.family == @core.FUndefinedName {
    return @core.Low
  }
  @core.High
}

///|
pub fn Report::render(self : Report) -> String {
  let buf = StringBuilder()
  let sev = self.severity_label()
  // The bracket carries the finding's METADATA: the lenses that saw it, the
  // family's STABLE id, and the confidence. The family NAME stays in the
  // parentheses alone, because that is the spelling a consumer has been
  // reading for a dozen releases and the name is still the name.
  //
  // The id and the confidence are in the bracket rather than in the
  // parentheses ON PURPOSE: the parentheses are the family, and every gate
  // that reads a finding line compares that field against a family name. The
  // bracket was already the metadata slot, and putting the two new fields
  // there keeps every family comparison in the repository working unchanged.
  let meta = lens_tag(self.lenses) +
    ", " +
    self.family.id() +
    ", " +
    self.confidence().name()
  buf.write_string(
    "\{self.span.start.line}:\{self.span.start.col} - \{sev}: \{self.message} (\{self.family.name()}) [\{meta}]\n",
  )
  for fr in self.vst {
    buf.write_string("  in \{fr.func} at \{fr.file}:\{fr.line}\n")
  }
  buf.to_string()
}

///|
pub fn render_reports(reports : Array[Report]) -> String {
  if reports.length() == 0 {
    return "No issues found, finished checking"
  }
  let buf = StringBuilder()
  for r in reports {
    buf.write_string(r.render())
  }
  buf.write_string("Summary: \{reports.length()} finding(s) found\n")
  buf.to_string()
}
