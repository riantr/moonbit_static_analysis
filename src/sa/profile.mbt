// profile: the two USER-FACING filters of 0507 -- the family profile and the
// `nosec` suppression -- and the rules they are checked against.
//
// Both of them are stated in STABLE FAMILY IDS (`MSA-007`), never in family
// names. A name is a second, hand-maintained vocabulary: five of the original
// eleven names are not the tag with its `F` removed, and renaming one changes
// the output silently, so a suppression written against a name breaks with no
// warning at all. An id is allocated and never renumbered, so a suppression
// written today names the same family in every version after it.
//
// 0507. BOTH FILTERS ARE OFF BY DEFAULT. The profile is empty -- every family
// is reported -- and `nosec` is honoured only when the reader asks for it.
// A tool that silently stops reporting a finding because of a comment in the
// ANALYSED source is a tool whose output cannot be trusted without reading
// that source first, and that is a much bigger change than the feature is
// worth. The policy question -- should a `nosec` be honoured by default? --
// stays open, and this increment does not decide it by accident.

///|
/// A family PROFILE: which families the reader wants to hear about.
///
/// 0507. A profile is a statement about which findings a user TRUSTS, and it
/// is stated in ids rather than names for the reason in the file header. It
/// is the second half of transfer 2: the ids are what makes a profile
/// checkable, and the checking is what makes an id worth having.
pub(all) struct Profile {
  /// The family ids to report. EMPTY means "report every family" -- a filter
  /// with nothing in it filters nothing, and an empty include set must not be
  /// read as "report nothing".
  include_ids : Array[String]
  /// The family ids to drop. Applied AFTER the include set.
  exclude_ids : Array[String]
  /// Whether `// nosec` comments are honoured.
  honor_nosec : Bool
}

///|
/// The profile every scan runs with unless the reader asks for another one.
pub fn default_profile() -> Profile {
  Profile::{ include_ids: [], exclude_ids: [], honor_nosec: false, }
}

///|
/// Check a profile against the family roster.
///
/// 0507. TWO RULES, and they are the two bandit has
/// (`bandit/core/extension_loader.py:86-100`):
///
///   * an id that names NO family is a WARNING, not an error. The reader asked
///     for a family this version does not have -- one added in a later
///     release, or a typo -- and the scan still runs, because the reader
///     asked for a scan. The warning says exactly what was not understood: a
///     profile that silently ignored an id would read as "that family has no
///     findings", which is a very different claim from "that family is not
///     this version's".
///   * an id that is BOTH included and excluded is an ERROR. The two rules
///     contradict each other and no reading of the profile satisfies both, so
///     the scan must not run at all. Which one won would depend on the order
///     of two `if`s, and a reader who asked for both cannot be told the
///     answer.
///
/// The return is (warnings, error). An empty error means the profile is
/// usable.
pub fn validate_profile(
  include_ids : Array[String],
  exclude_ids : Array[String],
) -> (Array[String], String) {
  let warnings : Array[String] = []
  let roster = family_ids()
  for id in include_ids {
    if @core.family_by_id(id) is None {
      warnings.push(
        "unknown family id in --families: " +
        id +
        " (the roster is " +
        roster.join(", ") +
        ")",
      )
    }
  }
  for id in exclude_ids {
    if @core.family_by_id(id) is None {
      warnings.push(
        "unknown family id in --exclude-families: " +
        id +
        " (the roster is " +
        roster.join(", ") +
        ")",
      )
    }
  }
  let overlap : Array[String] = []
  for id in include_ids {
    if exclude_ids.contains(id) {
      overlap.push(id)
    }
  }
  if overlap.length() > 0 {
    return (
      warnings,
      "the profile includes and excludes the same family id: " +
      overlap.join(", "),
    )
  }
  (warnings, "")
}

///|
/// Every family id in the roster, in order.
///
/// DERIVED from `family_by_id` rather than written out again: the probe goes
/// from `MSA-001` upwards until the contiguous run ends, so the roster cannot
/// drift from the table it comes from. The contiguity is not an assumption --
/// `_verify/check_family_roster.ps1` asserts it against the source, and a
/// gap in the ids would be a number that was skipped and never used.
pub fn family_ids() -> Array[String] {
  let out : Array[String] = []
  let mut n = 1
  while n <= 999 {
    let id = "MSA-" + pad3(n)
    if @core.family_by_id(id) is None {
      break
    }
    out.push(id)
    n += 1
  }
  out
}

///|
fn pad3(n : Int32) -> String {
  if n < 10 {
    "00\{n}"
  } else if n < 100 {
    "0\{n}"
  } else {
    "\{n}"
  }
}

///|
/// Does this profile keep a family?
///
/// 0507. The include set is applied FIRST and the exclude set SECOND, and the
/// order is not a preference: an id in both is an ERROR (see
/// `validate_profile`), so the two sets never meet here and the order cannot
/// change the answer.
pub fn profile_keeps(f : @core.Family, profile : Profile) -> Bool {
  let id = f.id()
  if profile.include_ids.length() > 0 && !profile.include_ids.contains(id) {
    return false
  }
  if profile.exclude_ids.contains(id) {
    return false
  }
  true
}

///|
/// The findings a profile keeps.
///
/// 0507. The filter is by FAMILY ID, and it is applied to the WHOLE report
/// list -- before the trusted-region split, not after it -- so that `total`,
/// `unreliable` and `notices` all describe the SAME set of findings. A filter
/// applied after the split would leave `total` counting findings the reader
/// can never see, and the SUMMARY's identity would stop adding up.
pub fn apply_profile(
  reports : Array[@report.Report],
  profile : Profile,
) -> Array[@report.Report] {
  let kept : Array[@report.Report] = []
  for r in reports {
    if profile_keeps(r.family, profile) {
      kept.push(r)
    }
  }
  kept
}

///|
/// One `// nosec` comment: where it is, and what it silences.
///
/// 0507. A nosec is a POSITION and a SET OF FAMILIES. The position is the
/// line the comment is on; the families are the ids it names, and an empty
/// set means "every family" -- the blanket form.
pub(all) struct Nosec {
  /// The line the comment is on. A nosec suppresses findings ON THAT LINE.
  line : Int32
  /// True for a blanket `// nosec`: it silences every family on the line.
  blanket : Bool
  /// The family ids it names. Empty for a blanket.
  ids : Array[String]
}

///|
/// Does this nosec cover a family?
pub fn Nosec::covers_family(self : Nosec, f : @core.Family) -> Bool {
  if self.blanket {
    return true
  }
  self.ids.contains(f.id())
}

///|
/// The `nosec` comments in a source file.
///
/// 0507. The syntax is a COMMENT, and the comment has to BE a nosec comment:
///
///     // nosec              -- blanket: every family on this line
///     // nosec MSA-007      -- one family
///     // nosec MSA-007 MSA-002
///
/// The comment must START with `nosec`. A comment that merely MENTIONS the
/// word -- "this is not a nosec comment" -- is not one, because a suppression
/// that can be switched on by mentioning the word is a suppression that gets
/// switched on by accident.
///
/// THE LAST `//` ON THE LINE IS THE COMMENT. A `//` inside a string literal
/// comes first, so taking the last one finds the real comment in the common
/// case: `let s = "http://x" // nosec` reads the `nosec`, and `let s =
/// "// nosec"` does not (the text after the last `//` is ` nosec"`, and the
/// quote means the token after `nosec` is not a separator, so it is not a
/// nosec comment).
pub fn parse_nosec(src : String) -> Array[Nosec] {
  let out : Array[Nosec] = []
  let mut line_no = 0
  for raw in src.split("\n") {
    line_no += 1
    let line = raw.to_owned()
    let parts = line.split("//").to_array()
    if parts.length() < 2 {
      continue
    }
    let comment = parts[parts.length() - 1].trim().to_owned()
    let toks = split_tokens(comment)
    if toks.length() == 0 {
      continue
    }
    // The marker may carry a colon -- `// nosec: MSA-007` -- and the colon
    // belongs to the marker, not to an id.
    let mut marker = toks[0]
    if marker.has_suffix(":") {
      marker = marker[0:marker.length() - 1].to_owned()
    }
    if marker != "nosec" {
      continue
    }
    if toks.length() == 1 {
      out.push(Nosec::{ line: line_no, blanket: true, ids: [], })
      continue
    }
    let ids : Array[String] = []
    for i in 1..<toks.length() {
      ids.push(toks[i])
    }
    out.push(Nosec::{ line: line_no, blanket: false, ids, })
  }
  out
}

///|
/// Split a comment into tokens on spaces, tabs and commas.
fn split_tokens(s : String) -> Array[String] {
  let out : Array[String] = []
  for part in s.split(" ") {
    let p = part.to_owned()
    for tabbed in p.split("\t") {
      let t2 = tabbed.to_owned()
      for piece in t2.split(",") {
        let t = piece.trim().to_owned()
        if t != "" {
          out.push(t)
        }
      }
    }
  }
  out
}

///|
/// Apply the `nosec` comments to a file's findings.
///
/// 0507. Returns the findings that SURVIVE and the stale-suppression findings
/// -- the `nosec` comments that suppressed NOTHING.
///
/// ORDER MATTERS, and it is the order that makes the warning possible: the
/// suppressions are applied FIRST and the stale findings are produced AFTER.
/// A blanket `// nosec` therefore cannot suppress the warning about its own
/// staleness, which would make the warning disappear exactly when it is the
/// one thing the reader needs.
///
/// "SUPPRESSED NOTHING" IS MEASURED AGAINST THE REPORT AS IT WOULD BE
/// PRINTED: a family the profile already removed does not count as a match,
/// because a `nosec` that names an excluded family is not doing anything for
/// the reader either.
pub fn apply_nosec(
  reports : Array[@report.Report],
  nosecs : Array[Nosec],
) -> (Array[@report.Report], Array[@report.Report]) {
  let kept : Array[@report.Report] = []
  let stale : Array[@report.Report] = []
  if nosecs.length() == 0 {
    for r in reports {
      kept.push(r)
    }
    return (kept, stale)
  }
  for r in reports {
    let mut covered = false
    for n in nosecs {
      if n.line == r.span.start.line && n.covers_family(r.family) {
        covered = true
      }
    }
    if !covered {
      kept.push(r)
    }
  }
  for n in nosecs {
    let mut hit = false
    for r in reports {
      if n.line == r.span.start.line && n.covers_family(r.family) {
        hit = true
      }
    }
    if !hit {
      stale.push(stale_report(n))
    }
  }
  (kept, stale)
}

///|
/// The finding that says a `nosec` suppressed nothing.
///
/// 0507. It is a finding of its own family -- `StaleNosec`, `MSA-012` -- and
/// not a warning printed to stderr, because a suppression that has gone stale
/// is a fact about the SOURCE, and the source is what the tool analyses. It
/// carries NO lens: no lens produced it, and the rendered bracket says so
/// with `-` rather than pretending a lens saw it.
fn stale_report(n : Nosec) -> @report.Report {
  @report.Report::{
    family: @core.FStaleNosec,
    lenses: [],
    message: n.stale_message(),
    span: @core.Span::{
      start: @core.pos(n.line, 1),
      end: @core.pos(n.line, 1),
    },
    vst: [],
  }
}

///|
/// Why this nosec suppressed nothing.
pub fn Nosec::stale_message(self : Nosec) -> String {
  if self.blanket {
    return "this `// nosec` comment suppressed nothing: no finding was reported on this line"
  }
  let names = self.ids.join(", ")
  let unknown : Array[String] = []
  for id in self.ids {
    if @core.family_by_id(id) is None {
      unknown.push(id)
    }
  }
  if unknown.length() == 1 {
    return "this `// nosec " +
      names +
      "` comment suppressed nothing: " +
      unknown[0] +
      " is not a family id"
  }
  if unknown.length() > 1 {
    return "this `// nosec " +
      names +
      "` comment suppressed nothing: " +
      unknown.join(", ") +
      " are not family ids"
  }
  "this `// nosec " +
  names +
  "` comment suppressed nothing: no finding of that family was reported on this line"
}
