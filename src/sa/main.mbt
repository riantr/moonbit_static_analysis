///|
/// Cross-project static analysis.
///
///   moonx riantr/moonbit_static_analysis@latest <target>
///
/// `<target>` is either a registry coordinate (`author/module`, optionally
/// `@version` or `@latest`) or a filesystem path. A coordinate is materialised
/// with `moon fetch` into `.repos/`, then walked. Nothing about the analysed
/// project is required or modified — this module only ever READS its files,
/// and the dependency runs one-way: analyzer -> registry -> target source.
///
/// Three toolchain facts this is written around:
///   - there is no `.await` postfix in MoonBit; an `async fn` body calls other
///     async functions directly. `await` is a reserved word, not an operator.
///   - file IO and subprocesses come from `moonbitlang/async`, not from core,
///     and both work on the wasm backend that `moonx` uses.
///   - no `t[..n]` slicing: `..` is a parse error. Substrings are built by
///     iterating characters.

///|
/// Public entry point. `target` is a registry coordinate or a path; the
/// module's root package forwards the CLI argument here, which is what makes
/// `moonx riantr/moonbit_static_analysis@latest <target>` work without naming
/// a package (an unpinned `moonx <module>` needs a root executable — otherwise
/// it looks for a prebuilt wasm asset that mooncakes does not have).

///|
/// Ceiling on files per scan, and how often the walk reports progress. Both are
/// stated rather than silent: a scan that quietly stops at an arbitrary point
/// is indistinguishable from a complete one.
let max_files : Int = 20000

///|
let progress_every : Int = 500

///|
/// Per-file findings shown before the scan stops printing them for that file.
/// A file the frontend understood is a file whose findings are worth reading;
/// a hundred of them is still noise, and the file is named either way.
let findings_shown_per_file : Int = 40

///|
/// What the scan can honestly say about one file.
///
/// `parsed` carries the whole weight. On a file the frontend did not understand,
/// every other number here measures the analyzer's blindness rather than the
/// code: an unparsed `struct` body turns its fields into undefined names and its
/// `*` into operator mismatches. Those are silenced by position, since the
/// boundary drops everything from the first failure on. The families whose
/// verdict is about a whole FUNCTION (`UnusedLocal`, `UnusedParam`,
/// `ParamChanged`) cannot be silenced that way -- they are reported at the
/// declaration, which is before the failure -- so the structural walk drops them
/// for the one function the failure could have truncated. Measured on this
/// repository's own source: 11 actionable findings, all 11 false, now 0.
pub(all) struct Verdict {
  path : String
  kind : String
  /// findings worth reading. Always empty when `parsed` is false.
  findings : Array[@report.Report]
  /// did the frontend understand the whole file
  parsed : Bool
  /// why not, when it did not
  reason : String
  /// every finding the file produced: pre-boundary (trustworthy) plus
  /// post-boundary (rejected). `unreliable` is the post-boundary count; the two
  /// are kept separate so the SUMMARY can assert that nothing was dropped
  /// silently and so the size of the "rejected" region is visible.
  total : Int
  /// How many of `findings` are "this declaration form is not analysed"
  /// notices rather than defects. Zero when the file is not understood.
  notices : Int
  /// Line of the first genuine read failure, or 0 when the whole file was
  /// understood. `findings` holds only what happens BEFORE it; everything from
  /// that line on is counted in `unreliable` and not shown.
  region_line : Int
  /// Findings at or after `region_line` — derived from an already-wrong tree, so
  /// reported only as a count, never as results.
  unreliable : Int
}

///|
/// Numbers that go onto the SUMMARY line. Computed in one place so the
/// printed identity has a single source of truth and a unit test can pin it.
pub struct Summary {
  parsed_files : Int
  partial_files : Int
  /// Pre-boundary defects: findings in parsed files, plus findings before the
  /// first parse error in partial files. Subtracting `notices` from
  /// `findings.length()` per file is the conversion from "things the analyzer
  /// has to say" to "things you should look at".
  actionable : Int
  /// Pre-boundary notices: "this declaration form is outside the analysed
  /// subset" findings. Not a defect, but a real signal about coverage.
  notices : Int
  /// Post-boundary findings across every file. The "noisy tail" the
  /// trusted-region split hides.
  unreliable : Int
  /// Post-boundary findings in partial files whose pre-boundary finding count
  /// is zero. A subset of `unreliable` (every withheld finding is also
  /// unreliable) reported separately because "this many findings are in files
  /// the analyzer found nothing trustworthy in" is a useful number on its own.
  /// NOT part of the SUMMARY sum.
  withheld : Int
  /// Pre-boundary + post-boundary. Equals `actionable + notices + unreliable`.
  total : Int
}

///|
/// Pure aggregation of per-file verdicts into SUMMARY-line numbers. The
/// inline loop in `scan` used to do this, and the 0.4.0 release shipped a
/// category error: `withheld` (a subset of `unreliable`) was added to the
/// printed sum on top of `unreliable`. `aggregate` does the math once, and
/// `sa_test.mbt` pins the identity to actual numbers so this cannot regress
/// without the test going red.
pub fn aggregate(verdicts : Array[Verdict]) -> Summary {
  let mut parsed_files = 0
  let mut partial_files = 0
  let mut actionable = 0
  let mut notices = 0
  let mut unreliable = 0
  let mut withheld = 0
  let mut total = 0
  for v in verdicts {
    let n = v.findings.length()
    total += v.total
    unreliable += v.unreliable
    // Per-file contribution to the pre-boundary totals. When n == 0 and the
    // file is partial, v.notices is 0 (notices are a count within findings),
    // so the addition below is a no-op and does not skew the totals.
    notices += v.notices
    actionable += n - v.notices
    if v.parsed {
      parsed_files += 1
    } else {
      partial_files += 1
      if n == 0 {
        // The "every finding is post-boundary" subgroup. The same number is
        // already in `unreliable`; we record it here without adding it to
        // `total`. Asserted in the test.
        withheld += v.unreliable
      }
    }
  }
  Summary::{
    parsed_files,
    partial_files,
    actionable,
    notices,
    unreliable,
    withheld,
    total,
  }
}

///|
/// Public entry point. `target` is a registry coordinate or a path; the
/// module's root package forwards the CLI arguments here, which is what makes
/// `moonx riantr/moonbit_static_analysis@latest <target>` work without naming
/// a package (an unpinned `moonx <module>` needs a root executable — otherwise
/// it looks for a prebuilt wasm asset that mooncakes does not have).
///
/// `excludes` names directory entries to skip. It exists because a dot-directory
/// rule cannot catch everything: a project may keep vendored registry snapshots
/// under an ordinary name, and on one such tree those snapshots were 1020 files
/// and 126,687 findings — 88% of everything the scan reported, none of it the
/// target's own code.
///
/// `extern_iface_dirs` are additional directories to scan for `.mbti` files
/// whose declared type and value names should be treated as valid bindings
/// even when they live outside the file under analysis. The classic case is
/// a dependency: a `.mbt` file that uses `Command` (defined in `@argparse`)
/// would otherwise be reported as `undefined name 'Command'`. The simplest
/// way to provide argparse's `.mbti` is to `moon fetch moonbitlang/argparse`
/// separately and pass `.repos` here; auto-fetching the target's own
/// `moon.mod` imports is on by default and can be turned off with
/// `auto_fetch_deps = false`.
pub async fn scan(
  target : String,
  excludes : Array[String],
  extern_iface_dirs : Array[String],
  auto_fetch_deps : Bool,
  mmd_out : String,
) -> Unit {
  let root = locate(target)
  if root == "" {
    println("ERROR\tcannot locate source for target: \{target}")
    return
  }
  if excludes.length() > 0 {
    println("EXCLUDE\t\{excludes.join(" ")}")
  }
  println("TARGET\t\{target}\t\{root}")
  let files : Array[String] = []
  let complete = collect(root, files, excludes)
  if complete {
    println("SCANNED\t\{files.length()} files under \{root}")
  }
  // Build the cross-file symbol table BEFORE iterating files: a single
  // walk over the target's tree + the user's extern dirs is cheaper than
  // re-walking per file, and the table is immutable from here on.
  if auto_fetch_deps {
    fetch_moon_mod_imports(root)
  }
  let iface_dirs : Array[String] = [root]
  for d in extern_iface_dirs {
    iface_dirs.push(d)
  }
  let (iface_tab, skipped_dot) = collect_iface_symtabs(iface_dirs)
  if iface_tab.n_types() + iface_tab.n_values() > 0 {
    println(
      "IFACE\ttypes=\{iface_tab.n_types()}\tvalues=\{iface_tab.n_values()}\t(dirs=\{iface_dirs.length()})",
    )
  }
  if skipped_dot > 0 {
    println(
      "IFACE\t\{skipped_dot} dot-directories under the target were NOT read for interface names (they hold a dependency's code); pass --extern-iface-dir <that path> to index them",
    )
  }
  // Verdicts collected in the loop, then handed to `aggregate` at the end so
  // the SUMMARY-line math has a single source of truth and a unit-testable
  // shape. Computing it inline is what produced the `+withheld` double-count
  // in 0.4.0: `withheld` is a subset of `unreliable`, and adding it to the
  // sum on top of `unreliable` is a category error that the printed identity
  // then asserted as a fact.
  let verdicts : Array[Verdict] = []
  // Per-kind totals, so the split this project is built around is visible in the
  // output instead of being a claim in the README. `.mbti` / `.mbtp` / `.mbt.md`
  // are audited properly and show a high parsed ratio; `.mbt` is a subset and
  // shows a low one. A user can now see that in one place instead of having to
  // take the word for it.
  let kind_files : Map[String, Int] = Map([])
  let kind_parsed : Map[String, Int] = Map([])
  let kind_defects : Map[String, Int] = Map([])
  let kind_notices : Map[String, Int] = Map([])
  let kinds : Array[String] = [".mbt", ".mbti", ".mbtp", ".mbt.md", ".mbtx"]
  // Unparsed files are counted by reason rather than listed. One line per file
  // would replace thousands of findings with thousands of lines and teach the
  // reader to scroll past the section that matters.
  let reasons : Map[String, Int] = Map([])
  let examples : Map[String, Array[String]] = Map([])
  for f in files {
    let v = analyze(f, iface_tab)
    verdicts.push(v)
    kind_files.set(v.kind, bump(kind_files, v.kind))
    let d = v.findings.length() - v.notices
    kind_defects.set(v.kind, get_or_zero(kind_defects, v.kind) + d)
    kind_notices.set(v.kind, get_or_zero(kind_notices, v.kind) + v.notices)
    if v.parsed {
      kind_parsed.set(v.kind, bump(kind_parsed, v.kind))
      let n = v.findings.length()
      // A subset notice ("this declaration form is not analysed") is not a
      // defect in the reader's code. Counting it as one made the self-scan
      // report `actionable=92` when the true defect count was 0, which is worse
      // than reporting nothing: it reads as "this tool found 92 problems here".
      if n == 0 {
        println("CLEAN\t\{v.kind}\t\{v.path}")
      } else {
        println(
          "FOUND\t\{v.kind}\tdefects=\{n - v.notices}\tnotices=\{v.notices}\t\{v.path}",
        )
        let shown = if n < findings_shown_per_file {
          n
        } else {
          findings_shown_per_file
        }
        for i in 0..<shown {
          println(v.findings[i].render())
        }
        if shown < n {
          println("...  \{n - shown} more in this file")
        }
      }
    } else {
      // Partly understood: report what was read up to the first real failure
      // and say plainly how much came after it and is therefore not evidence.
      let n = v.findings.length()
      if n > 0 {
        println(
          "PARTIAL\t\{v.kind}\tdefects=\{n - v.notices}\tnotices=\{v.notices}\tread up to line \{v.region_line}, \{v.unreliable} after it not shown\t\{v.path}",
        )
        let shown = if n < findings_shown_per_file {
          n
        } else {
          findings_shown_per_file
        }
        for i in 0..<shown {
          println(v.findings[i].render())
        }
        if shown < n {
          println("...  \{n - shown} more before the boundary in this file")
        }
      } else {
        let r = if v.reason == "" { "unspecified" } else { v.reason }
        let c = match reasons.get(r) {
          Some(x) => x + 1
          None => 1
        }
        reasons.set(r, c)
        let ex = match examples.get(r) {
          Some(a) => a
          None => []
        }
        if ex.length() < 3 {
          ex.push(v.path)
          examples.set(r, ex)
        }
      }
    }
  }
  // The SUMMARY numbers come from `aggregate`, a pure function over the
  // collected verdicts, so the math has a single source of truth and a test
  // can pin the printed identity. The identity itself:
  //
  //   total        = sum(v.total) over every file
  //               = (sum of pre-boundary findings over every file)
  //               + (sum of post-boundary findings over every file)
  //               = (actionable + notices) + unreliable
  //
  // `withheld` is a SUBSET of `unreliable`: it is the post-boundary count of
  // the partial files whose pre-boundary finding count is zero. The reason it
  // exists as a separate number is operational ("how many findings are in
  // files the analyzer found nothing trustworthy in"), not arithmetical; it
  // is intentionally not part of the sum, and adding it on top of
  // `unreliable` would double-count. Asserted in the test `sa_test.mbt`.
  let s = aggregate(verdicts)
  let pct = if files.length() == 0 {
    0
  } else {
    s.parsed_files * 1000 / files.length()
  }
  println(
    "PARSED\t\{s.parsed_files}/\{files.length()} files understood (\{pct / 10}.\{pct % 10}%); \{s.partial_files} more read only up to their first parse error",
  )
  for k in kinds {
    let nf = get_or_zero(kind_files, k)
    if nf > 0 {
      println(
        "BYKIND\t\{k}\tfiles=\{nf}\tparsed=\{get_or_zero(kind_parsed, k)}\tdefects=\{get_or_zero(kind_defects, k)}\tnotices=\{get_or_zero(kind_notices, k)}",
      )
    }
  }
  let unreadable = files.length() - s.parsed_files
  if unreadable > 0 {
    println(
      "NOTPARSE\t\{unreadable} files, \{s.withheld} finding(s) withheld — they measure what this analyzer does not understand, not what your code does",
    )
    for r, c in reasons {
      println("  \{c}x  \{r}")
      let ex = match examples.get(r) {
        Some(a) => a
        None => []
      }
      for p in ex {
        println("      e.g. \{p}")
      }
    }
  }
  println(
    "SUMMARY\tfiles=\{files.length()}\tparsed=\{s.parsed_files}\tactionable=\{s.actionable}\tnotices=\{s.notices}\tunreliable=\{s.unreliable}\twithheld=\{s.withheld}\ttotal=\{s.total}\t(actionable+notices+unreliable = total; withheld ⊆ unreliable)",
  )
  if !complete {
    println(
      "NOTE\tthis tree exceeded the \{max_files}-file cap; the counts above cover only what was walked",
    )
  }
  if mmd_out != "" {
    emit_mmd(mmd_out, verdicts, s, target, root)
  }
}

///|
/// Write the scan as a mermaid diagram, if the user asked for one.
///
/// Opt-in, and stdout above is untouched either way: the text report is the
/// authoritative output, and the drawing is lossy BY CONSTRUCTION —
/// `mermaid_states` ranks files by actionable count and stops at its own cap,
/// saying so in a `%% THIS DRAWING IS A SUBSET` comment. A tool that made the
/// picture the only output would hide that.
///
/// The default lands in the WORKING DIRECTORY, never inside the analysed tree.
/// This module's stated invariant is that it only ever reads the target's
/// files; dropping an artifact into someone's source repository would break a
/// promise the docs make and would dirty a tree the user may not own.
///
/// The provenance — target, version, TOOLCHAIN, stamp — comes from the same
/// `provenance_for` every other caller uses, so the filename and the document
/// header cannot disagree about what a scan was.
///
/// An earlier version of this function assembled its own provenance and left
/// `scanned_at` empty, on the belief that no clock was reachable because
/// `moonbitlang/async`'s `event_loop` sits under `internal`. That was wrong:
/// `moonbitlang/async` re-exports it publicly as `pub using @event_loop {now}`,
/// and `provenance_for` had been calling it since 0.4.5. The symptom was a file
/// named `..._unknown.mmd` on a scan whose header knew perfectly well when it
/// ran. Both the workaround and its stated reason are gone.
///
/// A failure to write is reported and then swallowed, like every other I/O
/// failure here: there is no non-zero exit available (see the root `main.mbt`),
/// so the best this can do is say what went wrong.
async fn emit_mmd(
  dest : String,
  verdicts : Array[Verdict],
  s : Summary,
  target : String,
  root : String,
) -> Unit {
  let prov = provenance_for(target, root)
  let text = mermaid_states(
    verdicts, s, prov, findings_shown_per_file, max_files,
  )
  let path = if dest == "@" { scan_artifact_name(prov, root) } else { dest }
  @fs.write_file(path, text) catch {
    _ => {
      println("ERROR\t--mmd: cannot write \{path}")
      return
    }
  }
  println("MMD\t\{path}")
}

///|
/// Resolve a target to a directory holding its source. A coordinate is
/// fetched; a path is used as-is. Returns "" when nothing can be found.
async fn locate(target : String) -> String {
  if is_coordinate(target) {
    let (mod, ver) = split_coord(target)
    if mod == "" {
      return ""
    }
    // `moon fetch` resolves a BARE module to the newest version itself, and
    // rejects an explicit `@latest` ("unexpected character 'l' while parsing
    // major version number"), so only a real version is passed through.
    let spec = if ver == "" { mod } else { mod + "@" + ver }
    let _ = @process.run("moon", ["fetch", spec])
    let base = ".repos/" + mod
    if ver != "" {
      // pinned: that exact directory, not "whatever is newest on disk"
      let pinned = base + "/" + ver
      let _ = @fs.readdir(pinned) catch { _ => return "" }
      return pinned
    }
    let versions = @fs.readdir(base) catch { _ => return "" }
    if versions.length() == 0 {
      return ""
    }
    return base + "/" + versions[versions.length() - 1]
  }
  let _ = @fs.readdir(target) catch { _ => return "" }
  target
}

///|
/// A coordinate looks like `author/module`. Anything path-shaped (leading `.`
/// or `/`, a drive colon, a backslash) is treated as a path instead.
fn is_coordinate(t : String) -> Bool {
  if t.has_prefix(".") ||
    t.has_prefix("/") ||
    t.contains(":") ||
    t.contains("\\") {
    false
  } else {
    t.contains("/")
  }
}

///|
/// Split `author/module[@version]` into its two parts. The version comes back
/// as "" when absent OR when it is `latest`, because `moon fetch` resolves a
/// bare module to the newest one itself.
///
/// This split matters more than it looks. The fetch target and the `.repos`
/// path are built from DIFFERENT strings: fetching `author/module` lands in
/// `.repos/author/module/<version>/`. An earlier version of this file stripped
/// only `@latest` and kept a pinned version in the name, so
/// `...@0.3.1` was looked up at `.repos/author/module@0.3.1`, which never
/// exists — `@latest` worked only because stripping it was the same operation
/// that produced the right path. Any pinned target silently found nothing.
fn split_coord(t : String) -> (String, String) {
  let mut mod = ""
  let mut ver = ""
  let mut seen_at = false
  for c in t {
    if c == '@' {
      seen_at = true
      continue
    }
    if seen_at {
      ver = ver + c.to_string()
    } else {
      mod = mod + c.to_string()
    }
  }
  if ver == "latest" {
    ver = ""
  }
  (mod, ver)
}

///|
async fn is_dir(p : String) -> Bool {
  let d = @fs.opendir(p) catch { _ => return false }
  ignore(d)
  true
}

///|
/// Walk `root` iteratively with an explicit stack and collect the analysable
/// files. Returns false when the cap was hit and the walk stopped early.
///
/// This used to recurse, one coroutine frame per directory level. An explicit
/// stack removes the coroutine-frame-per-level cost and makes it affordable to
/// report progress and to stop at a stated ceiling.
///
/// Progress is keyed on directories processed *as well as* on analysable files,
/// and that second key is not decoration. Measured on a 20-project tree (2460
/// analysable files out of 42k files total): with the file count as the only
/// key, the first `WALKING` line took 15 minutes to appear and was the only one
/// printed — the walk was still silent when it was stopped. Keying on files
/// alone cannot work, because the stretches that take the time are exactly the
/// ones containing nothing analysable: `moon_openblas/vendor` holds 19483
/// vendored files and `ML/CI` another 10572, and neither contributes a single
/// `.mbt`. The directory counter moves in every directory, analysable or not.
async fn collect(
  root : String,
  out : Array[String],
  excludes : Array[String],
) -> Bool {
  let stack : Array[String] = [root]
  let mut seen_dirs = 0
  let mut last_files = 0
  let mut last_dirs = 0
  while stack.length() > 0 {
    let dir = match stack.pop() {
      Some(d) => d
      None => break
    }
    let entries = @fs.readdir(dir) catch { _ => continue }
    for e in entries {
      // Skip build output, vendored registry sources (.mooncakes, .repos) and
      // every other dot-directory: none of them are the target's own source, and
      // walking them inflates the count with a dependency's code.
      //
      // A dot rule cannot catch everything. `excludes` is the caller's way to
      // name directories that hold a copy of somebody else's code under an
      // ordinary name.
      if e == "_build" || e.has_prefix(".") || excludes.contains(e) {
        continue
      }
      let p = dir + "/" + e
      if is_dir(p) {
        stack.push(p)
      } else if wanted(p) {
        if out.length() >= max_files {
          println(
            "CAP\tstopped at \{max_files} files; some of this tree was NOT analysed",
          )
          return false
        }
        out.push(p)
      }
    }
    seen_dirs = seen_dirs + 1
    if out.length() - last_files >= progress_every ||
      seen_dirs - last_dirs >= progress_every {
      last_files = out.length()
      last_dirs = seen_dirs
      println(
        "WALKING\tdirs=\{seen_dirs}\tfiles=\{out.length()} so far under \{root}",
      )
    }
  }
  true
}

///|
fn wanted(p : String) -> Bool {
  let n = base_of(p)
  let s = suffix_of(p)
  n.has_suffix(".mbt.md") ||
  s == "mbt" ||
  s == "mbti" ||
  s == "mbtp" ||
  s == "mbtx"
}

///|
fn kind_of(p : String) -> String {
  let s = suffix_of(p)
  let n = base_of(p)
  if s == "mbti" {
    ".mbti"
  } else if s == "mbtp" {
    ".mbtp"
  } else if n.has_suffix(".mbt.md") {
    ".mbt.md"
  } else if s == "mbtx" {
    ".mbtx"
  } else {
    ".mbt"
  }
}

///|
async fn analyze(p : String, extern_iface : @core.IfaceSymTab) -> Verdict {
  let src = read_or(p)
  let n = base_of(p)
  let k = kind_of(p)
  match k {
    // `.mbti` and `.mbtp` are audited in their own right, and there FParse means
    // "this file has a defect", not "I could not read it" — malformed interface
    // lines, duplicate signatures, unknown type references, string constants in
    // a logic body. Suppressing those would delete the entire product.
    //
    // The `.mbti` audit ends its type chain at the module-wide interface
    // table: a generated interface references the traits and errors OTHER
    // packages declare (`&Show`, `raise SnapshotError`), so `extern_iface`
    // resolves them before anything is reported.
    //
    // Both frontends are line-based and produce no cascade, so the whole file is
    // trusted: region_line 0, nothing withheld.
    ".mbti" => {
      let rs = @moonfiles.iface(src, n, extern_iface)
      Verdict::{
        path: p,
        kind: k,
        findings: rs,
        parsed: true,
        reason: "",
        total: rs.length(),
        notices: 0,
        region_line: 0,
        unreliable: 0,
      }
    }
    ".mbtp" => {
      let rs = @moonfiles.proof(src, n)
      Verdict::{
        path: p,
        kind: k,
        findings: rs,
        parsed: true,
        reason: "",
        total: rs.length(),
        notices: 0,
        region_line: 0,
        unreliable: 0,
      }
    }
    ".mbt.md" => {
      let r = @moonfiles.literate(src, n)
      let total = r.reports.length()
      // Same trusted-region split as `.mbt`: n_parse already excludes the
      // deliberate fence skips, so a document whose only complaint is "this
      // fence was not analysed" is still a document that was read, and a
      // document that hits a real failure keeps everything before it.
      let cut = r.first_error_line
      let reliable : Array[@report.Report] = []
      let mut notices = 0
      for rep in r.reports {
        if cut > 0 && rep.span.start.line >= cut {
          continue
        }
        reliable.push(rep)
        if rep.family == @core.FParse {
          notices += 1
        }
      }
      Verdict::{
        path: p,
        kind: k,
        findings: reliable,
        parsed: cut == 0,
        reason: if cut == 0 {
          ""
        } else {
          r.parse_reason
        },
        total,
        notices,
        region_line: cut,
        unreliable: total - reliable.length(),
      }
    }
    _ => {
      let r = @pipeline.run(src, n, extern_iface)
      let total = r.reports.length()
      // The trusted region: everything before the first genuine read failure.
      //
      // Inside it, `FParse` can only mean a deliberate exclusion -- a real
      // failure on that line would itself have set first_error_line to it. So
      // the defect/notice split needs no string matching here.
      let cut = r.first_error_line
      let reliable : Array[@report.Report] = []
      let mut notices = 0
      for rep in r.reports {
        if cut > 0 && rep.span.start.line >= cut {
          continue
        }
        reliable.push(rep)
        if rep.family == @core.FParse {
          notices += 1
        }
      }
      Verdict::{
        path: p,
        kind: k,
        findings: reliable,
        parsed: cut == 0,
        reason: if cut == 0 {
          ""
        } else {
          r.parse_reason
        },
        total,
        notices,
        region_line: cut,
        unreliable: total - reliable.length(),
      }
    }
  }
}

///|
fn get_or_zero(m : Map[String, Int], k : String) -> Int {
  match m.get(k) {
    Some(x) => x
    None => 0
  }
}

///|
fn bump(m : Map[String, Int], k : String) -> Int {
  let n = match m.get(k) {
    Some(x) => x
    None => 0
  }
  n + 1
}

///|
async fn read_or(p : String) -> String {
  let data = @fs.read_file(p) catch {
    err => {
      println("SKIP\t\{p}\tunreadable: \{err}")
      return ""
    }
  }
  data.text() catch {
    _ => return ""
  }
}

///|
fn suffix_of(path : String) -> String {
  let mut tail = ""
  let mut after_dot = false
  for c in path {
    if c == '/' || c == '\\' {
      tail = ""
      after_dot = false
    } else if c == '.' {
      after_dot = true
      tail = ""
    } else if after_dot {
      tail = tail + c.to_string()
    }
  }
  tail
}

///|
fn base_of(path : String) -> String {
  let mut out = ""
  for c in path {
    if c == '/' || c == '\\' {
      out = ""
    } else {
      out = out + c.to_string()
    }
  }
  out
}

// ============================================================================
// Cross-file type symbol resolution (.mbti as a type source for .mbt analysis)
// ============================================================================
//
// When a `.mbt` file under analysis uses a name that is not declared in the
// file itself, the structural walk would fire FUndefinedName. The fix is to
// consult the `.mbti` files of OTHER packages and modules before reporting:
// if `Command` is a struct in `@argparse` and argparse's `.mbti` is in the
// table, the structural walk stays quiet.
//
// Two ways to populate the table:
//   - the user passes `--extern-iface-dir <dir>` (or several) and we walk
//     them for `.mbti` files; the natural target is `.repos/` after
//     `moon fetch` of the dependencies you want indexed.
//   - by default we also try to auto-fetch the direct imports of the
//     target's own `moon.mod` — `import { "moonbitlang/argparse" }` and
//     friends — and then the second pass picks them up from `.repos/`
//     too. Turn this off with `--no-auto-fetch-deps`.
//
// `collect_iface_symtabs` is a pure directory walk + read + parse; it does
// not shell out. `fetch_moon_mod_imports` is the only subprocess point.

///|
/// Read the target's `moon.mod`, find every `import { "author/pkg" }` line,
/// and `moon fetch` each one. Best-effort: a failure is logged at INFO level
/// and skipped (the rest of the scan continues without that dep's types).
/// Transitive deps are NOT followed — the user can fetch them by hand if a
/// .mbti they wrote is not enough.
async fn fetch_moon_mod_imports(root : String) -> Unit {
  let mod_path = root + "/moon.mod"
  let text = read_or(mod_path)
  if text == "" {
    return
  }
  let imports = parse_moon_mod_imports(text)
  if imports.length() == 0 {
    return
  }
  println("FETCH\t\{imports.length()} import(s) from moon.mod")
  let mut failed = 0
  for coord in imports {
    // Each failure is named. The 0.4.3 version ran the same loop with the
    // result discarded, so a coordinate that could not be fetched produced
    // no line at all here — only moon's own stderr — and the scan went on
    // as if the dependency's types were present.
    let ok = @process.run("moon", ["fetch", coord]) catch { _ => 0 }
    if ok != 0 {
      failed += 1
      println("FETCH\tcould not fetch \{coord}")
    }
  }
  println(
    "FETCH\tdeposited under .repos/ — pass --extern-iface-dir .repos to index their interface names",
  )
  if failed > 0 {
    println(
      "FETCH\t\{failed} of \{imports.length()} import(s) not fetched; their types are NOT in the table below",
    )
  }
}

///|
/// Find every `"author/pkg"` string inside `import { ... }` blocks.
///
/// This used to scan for the bare 7-char text `import ` anywhere in the file
/// and then read quoted strings until the next `}`. Two bugs came out of that,
/// both measured on this module's own `moon.mod` (self-scan, 0.4.3):
///
///   1. It matched the word `import ` inside a COMMENT. This module's
///      moon.mod says "we never import them." in its header, which opened a
///      phantom import block; the quoted strings after it — the module's own
///      `name = "riantr/moonbit_static_analysis"` and
///      `repository = "https://github.com/..."` — were then read as
///      dependencies. The scan announced "4 import(s) from moon.mod" for a
///      file that declares exactly 1, and tried to fetch the module itself.
///   2. It accepted any quoted string containing a `/`, so the `https://`
///      repository URL became a coordinate and `moon fetch` failed twice with
///      "path contains an invalid component".
///
/// The fix is to scan line by line and skip `//` comments, and to accept
/// only a coordinate that looks like `author/module` — no scheme, no empty
/// segments. A `moon.mod` also allows a trailing `@version`, which is part
/// of the coordinate and is kept.
pub fn parse_moon_mod_imports(src : String) -> Array[String] {
  let out : Array[String] = []
  let mut in_import = false
  for raw in src.split("\n") {
    // Strip a `//` comment. moon.mod has no block comments and no string
    // escapes that would hide a `//`, so the first one starts the comment.
    let line = match raw.split_once("//") {
      Some((head, _)) => head
      None => raw
    }
    let t = line.trim()
    if t == "" {
      continue
    }
    // `import {` opens; `import` alone also opens (the `{` is on the next
    // line in some hand-written files); `}` closes.
    if t == "}" || t == "};" || t == "}," {
      in_import = false
      continue
    }
    if !in_import {
      if t == "import" ||
        t == "import{" ||
        t.has_prefix("import {") ||
        t.has_prefix("import{") {
        in_import = true
      }
      continue
    }
    // inside the block: take each quoted string, and only if it is a
    // coordinate rather than a URL or some other value. `split` yields
    // StringViews, so the candidate is reified before it is compared or
    // stored — the same reason `moonfiles` has `view_str`.
    for part in t.split("\"") {
      let q = reify(part)
      if is_module_coord(q) && !out.contains(q) {
        out.push(q)
      }
    }
    if t.has_suffix("}") {
      in_import = false
    }
  }
  out
}

///|
/// StringView -> String, by iterating characters. `split` returns views and
/// the rest of this file works in `String`.
fn reify(v : StringView) -> String {
  let buf = StringBuilder()
  for c in v {
    buf.write_char(c)
  }
  buf.to_string()
}

///|
/// True for `author/module` with an optional `@version` suffix — the shape
/// `moon fetch` accepts. Deliberately strict: a URL (`https://…`), a bare
/// `README.md`, and an empty or single-segment string are all rejected, so a
/// quoted value that is not a coordinate cannot be mistaken for one.
pub fn is_module_coord(s : String) -> Bool {
  if s == "" || s.contains("://") || s.has_prefix(".") {
    return false
  }
  // split off `@version`
  let base = match s.split_once("@") {
    Some((b, _)) => reify(b)
    None => s
  }
  if base == "" {
    return false
  }
  // Split by hand rather than with `String::split`. Measured on this
  // toolchain (probe, src/sa): `split` DOES keep the empty segments —
  // `"a//b"` yields three parts, the middle one empty — but
  // `split(...).length()` returns 0 for every input, so a segment-count
  // check written against it is a guard that never fires. Walking the
  // characters makes both facts visible in the code instead of in a probe.
  //
  // The registry requires `<author>/<module_name>`, so TWO segments is the
  // floor; a package inside a module adds more (`moonbitlang/core/error`).
  // Measured against `moon fetch`: one segment is rejected outright with
  // "must be in the form of <author>/<module_name>", while two or more
  // reach the registry lookup.
  let chars = base.to_array()
  let n = chars.length()
  let mut segs = 0
  let mut start = 0
  let mut i = 0
  while i < n {
    if chars[i] == '/' {
      if !ok_segment(chars, start, i) {
        return false
      }
      segs += 1
      start = i + 1
    }
    i += 1
  }
  // the segment after the final '/'; `start == n` means a trailing '/'
  if !ok_segment(chars, start, n) {
    return false
  }
  segs += 1
  segs >= 2
}

///|
/// One `/`-separated segment in [from, to): non-empty, and not `.` or `..`.
fn ok_segment(chars : Array[Char], from : Int, to : Int) -> Bool {
  if to <= from {
    return false
  }
  if to - from == 1 && chars[from] == '.' {
    return false
  }
  if to - from == 2 && chars[from] == '.' && chars[from + 1] == '.' {
    return false
  }
  true
}

///|
/// Walk a list of directories, read every `.mbti` file found, and merge
/// their declared type and value names into one `IfaceSymTab`.
///
/// The first root is the target itself, where the dot-directory skip is
/// right: `.repos`, `.mooncakes` and `.git` are a dependency's code, not the
/// target's. Every LATER root is a directory the user named on the command
/// line, and naming `.repos` is exactly how one points the analyzer at
/// fetched dependencies — so the dot rule is dropped for them. Measured on
/// 0.4.3: `--extern-iface-dir .repos` found the interfaces (a dot root is
/// read directly, its own name is never tested), but a dot-directory NESTED
/// inside a passed root was silently skipped — the walk found 1 type where
/// the directory held 4, and said nothing about the other 3.
///
/// Skipped dot-directories are now counted and reported, because a symtab
/// missing types it silently looked at is the same failure mode as a parser
/// that silently gives up: the reader cannot tell "nothing there" from
/// "never looked".
async fn collect_iface_symtabs(
  roots : Array[String],
) -> (@core.IfaceSymTab, Int) {
  let tab = @core.IfaceSymTab::empty()
  let mut skipped_dot = 0
  for ri, root in roots {
    // the target is roots[0]; anything else was named by the user
    let user_named = ri > 0
    let stack : Array[String] = [root]
    while stack.length() > 0 {
      let dir = match stack.pop() {
        Some(d) => d
        None => break
      }
      let entries = @fs.readdir(dir) catch { _ => continue }
      for e in entries {
        if e == "_build" {
          continue
        }
        if !user_named && e.has_prefix(".") {
          continue
        }
        let p = dir + "/" + e
        if is_dir(p) {
          if !user_named && e.has_prefix(".") {
            skipped_dot += 1
            continue
          }
          stack.push(p)
        } else if e.has_suffix(".mbti") {
          let data = @fs.read_file(p) catch { _ => continue }
          let text = data.text() catch { _ => continue }
          let sub = @moonfiles.collect_iface_names(text)
          let _ = tab.merge(sub)
        }
      }
    }
  }
  (tab, skipped_dot)
}
