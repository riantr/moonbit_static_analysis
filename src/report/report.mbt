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
pub fn Report::render(self : Report) -> String {
  let buf = StringBuilder()
  let sev = match self.family.severity() {
    @core.Error => "error"
    @core.Warning => "warning"
    @core.Hint => "hint"
  }
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
