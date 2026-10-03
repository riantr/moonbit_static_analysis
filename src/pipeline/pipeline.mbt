// pipeline: the assembly itself. Runs the three lenses in order and merges
// their findings:
//   1. parse      (frontend, structural)
//   2. walk       (lens 1:  binding tables + structural findings)
//   3. types      (lens 2: symbols/signatures + type findings,
//                  declarations taken from lens 1's tables)
//   4. interp     (lens 3: abstract execution + behavior findings,
//                  method table taken from lens 2's signatures)
//   5. merge      families sharing a merge_group at the same span become one
//                  finding with the union of lenses — an unresolvable name is
//                  one defect seen by all lenses, not three reports.

///|
pub(all) struct PipelineResult {
  /// merged findings, sorted by position
  reports : Array[@report.Report]
  /// signatures observed by the behavioral lens (`f(::int) -> int`)
  sigs : Array[String]
  /// per-lens finding counts BEFORE the merge — the merge is lossless:
  /// the lens attribution survives inside each report
  n_structural : Int
  n_type : Int
  n_behavior : Int
}

///|
fn lens_count(lens : @core.Lens, r : @report.Report) -> Int {
  if r.lenses.contains(lens) {
    1
  } else {
    0
  }
}

///|
/// Run the full pipeline over MLang source.
pub fn run(src : String, file : String) -> PipelineResult {
  let parsed = @parser.parse(src)
  let all : Array[@report.Report] = []
  // parse findings are already tagged structural
  for r in parsed.reports {
    all.push(r)
  }
  let wr = @walk.walk_module(parsed.tree, file)
  for r in wr.findings {
    all.push(r)
  }
  let tr = @types.infer_full(parsed.tree, wr)
  for r in tr.findings {
    all.push(r)
  }
  let ir = @interp.analyze_module(parsed.tree, tr, wr, file)
  for r in ir {
    all.push(r)
  }
  let sigs = @interp.analyzed_sigs(parsed.tree, tr, wr, file)
  let merged = merge_findings(all)
  let mut n1 = 0
  let mut n2 = 0
  let mut n3 = 0
  for r in all {
    n1 += lens_count(@core.LStructural, r)
    n2 += lens_count(@core.LType, r)
    n3 += lens_count(@core.LBehavior, r)
  }
  PipelineResult::{
    reports: merged,
    sigs,
    n_structural: n1,
    n_type: n2,
    n_behavior: n3,
  }
}

///|
fn merge_key(r : @report.Report) -> String {
  // (merge family, line): echoes of ONE defect that lenses localize at
  // different columns of the same line (the type lens pins the argument,
  // the behavior lens pins the call) still collapse into a single finding
  "\{r.family.merge_group()}@\{r.span.start.line}"
}

///|
pub fn merge_findings(all : Array[@report.Report]) -> Array[@report.Report] {
  // group by (merge family, line)
  let groups : Map[String, Array[@report.Report]] = Map([])
  for r in all {
    let k = merge_key(r)
    match groups.get(k) {
      Some(g) => g.push(r)
      None => groups.set(k, [r])
    }
  }
  let out : Array[@report.Report] = []
  for _, g in groups {
    out.push(merge_group(g))
  }
  out.sort_by(fn(a : @report.Report, b : @report.Report) {
    if a.span.start.line != b.span.start.line {
      a.span.start.line - b.span.start.line
    } else {
      a.span.start.col - b.span.start.col
    }
  })
  out
}

///|
/// One merged finding: union of lenses, representative = the most specific
/// lens's report (behavior > type > structural), families unified under the
/// representative's family.
pub fn merge_group(g : Array[@report.Report]) -> @report.Report {
  let lenses : Array[@core.Lens] = []
  for r in g {
    for l in r.lenses {
      if !lenses.contains(l) {
        lenses.push(l)
      }
    }
  }
  lenses.sort_by(fn(a : @core.Lens, b : @core.Lens) { a.rank() - b.rank() })
  // representative: highest-rank lens
  let mut rep = g[0]
  for r in g {
    if rep_lens_rank(r) > rep_lens_rank(rep) {
      rep = r
    }
  }
  // the pipeline rewrites the family: merged arg-type echoes present as
  // MethodError (the behavioral phrasing is the most specific)
  @report.Report::{
    family: rep.family,
    lenses,
    message: rep.message,
    span: rep.span,
    vst: rep.vst,
  }
}

///|
fn rep_lens_rank(r : @report.Report) -> Int {
  let mut best = 0
  for l in r.lenses {
    if l.rank() > best {
      best = l.rank()
    }
  }
  best
}

///|
/// Full text rendering: findings + inferred signatures + lens statistics.
pub fn render_result(r : PipelineResult) -> String {
  let buf = StringBuilder()
  if r.reports.length() == 0 {
    buf.write_string("No issues found, finished checking\n")
  } else {
    for rep in r.reports {
      buf.write_string(rep.render())
    }
  }
  buf.write_string(
    "Summary: \{r.reports.length()} finding(s) (before merge: structural \{r.n_structural}, type \{r.n_type}, behavior \{r.n_behavior})\n",
  )
  if r.sigs.length() > 0 {
    buf.write_string("Inferred signatures:\n")
    for s in r.sigs {
      buf.write_string("  \{s}\n")
    }
  }
  buf.to_string()
}
