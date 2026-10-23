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
  names.join("+")
}

///|
/// Is this report a NOTICE -- a declared scope limit of this analyzer -- rather
/// than a defect in the code that was analysed?
///
/// ONE definition, and every caller must use it. The rendered label, the
/// SUMMARY's `actionable` count and the mermaid drawing all answer the same
/// question, and a second copy of the question somewhere else is how a diagram
/// ends up drawing a defect as a notice while the number beside it says the
/// opposite.
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
pub fn Report::render(self : Report) -> String {
  let buf = StringBuilder()
  let sev = self.severity_label()
  buf.write_string(
    "\{self.span.start.line}:\{self.span.start.col} - \{sev}: \{self.message} (\{self.family.name()}) [\{lens_tag(self.lenses)}]\n",
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
