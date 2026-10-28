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
let max_files : Int32 = 20000

///|
let progress_every : Int32 = 500

///|
/// Per-file findings shown before the scan stops printing them for that file.
/// A file the frontend understood is a file whose findings are worth reading;
/// a hundred of them is still noise, and the file is named either way.
///
/// This is the DEFAULT, and it is a default rather than a constant because the
/// cap was hiding the findings that matter. MEASURED, riantr/moonbit_labeler
/// 0.2.13, `extensions/labeler/labeler.mbt`: the file carries 212 findings,
/// 174 of them notices, and the first forty printed are ALL notices -- so the
/// thirty-eight defects behind them were never shown. The file's own header
/// said `defects=38` and the reader saw none of them. A cap that hides the
/// defects is not a cap, it is a blindfold.
///
/// `--findings-shown-per-file N` overrides it. The SUMMARY counts are
/// unaffected either way: they come from `aggregate` over EVERY finding, and
/// the cap is a PRINTING limit, never an analysis limit.
pub let default_findings_shown_per_file : Int32 = 40

///|
/// How many of a file's findings are printed, and whether the file had more
/// than that to say. Pure, so the cap's boundary can be pinned by a test
/// without running a scan.
///
/// The cap is clamped at zero: a negative one would ask for a range of
/// negative length, and the reader asked for "everything" or "nothing", never
/// for less than nothing.
pub fn show_plan(n : Int32, cap : Int32) -> (Int32, Bool) {
  let c = if cap < 0 { 0 } else { cap }
  let shown = if n < c { n } else { c }
  (shown, shown < n)
}

///|
/// Is this region one of the ones that can hide a finding?
///
/// 0506. The membership test is EXACT -- the span is compared, not a line
/// number and not a message. A region's identity is where it is, and two
/// exclusions on the same line are two different regions.
///
/// It is `pub` so that this rule is pinned by this package's own tests: it is
/// the one place where a region is decided to be a hiding region, and a rule
/// that quietly loosened would put a notice in the wrong set without changing
/// any count.
pub fn is_hiding(sp : @core.Span, hiding : Array[@core.Span]) -> Bool {
  for h in hiding {
    if h == sp {
      return true
    }
  }
  false
}

///|
/// Split a file's findings into the ones that deserve a line of the reader's
/// screen and the ones that do not.
///
/// 0506. A notice is worth a line only when it can HIDE a finding -- that is,
/// only when its region lies inside some function's extent, which is the
/// geometry `@walk.hiding_spans` computes and `Verdict::hiding` carries. A
/// notice outside every function's extent hides nothing: it is the analyzer
/// saying "I did not read this declaration", and there is nothing the reader
/// can do about it beyond knowing the count.
///
/// MEASURED on the pinned core corpus: 10,096 notices, of which 8,952 hide
/// nothing and 1,144 can hide something. The OLD rendering -- the per-file cap
/// as it ships -- was 9,128 lines of output to say 28 things, and with the cap
/// lifted, so that every one of the 10,096 notices is on a line of its own, it
/// is 11,223. (The renderer puts a blank line after each finding, so `wc -l`
/// counts the same two outputs as 17,128 and 21,348.)
///
/// The rule is a POSITION and not a wording, and that is not a preference: the
/// same "if expression is outside the analyzed subset" notice is printed when
/// it sits inside a function and aggregated when it sits at module top level,
/// because only the first is in a function's hole list.
///
/// It is `pub` so that the split is pinned by this package's own tests, and
/// so that a reader of the output can ask the same question the renderer
/// asked.
pub fn split_findings(
  findings : Array[@report.Report],
  hiding : Array[@core.Span],
) -> (Array[@report.Report], Array[@report.Report]) {
  let printed : Array[@report.Report] = []
  let aggregated : Array[@report.Report] = []
  for r in findings {
    if !r.is_notice() {
      printed.push(r)
    } else if is_hiding(r.span, hiding) {
      printed.push(r)
    } else {
      aggregated.push(r)
    }
  }
  (printed, aggregated)
}

///|
/// The findings to PRINT for one file, and the notices to COUNT for it.
///
/// 0506. `--show-notices` is the WHOLE per-line list, which is the default's
/// opposite: the default prints a notice only when it can hide a finding, and
/// the flag prints every notice. The flag exists so that the complete list
/// stays reachable -- every measurement that reads it needs it, and a reader
/// looking for a specific construct wants it -- and so that a tool that
/// printed 19,551 notice lines has a way to print them.
///
/// The flag changes no count: the SUMMARY's numbers are the same either way,
/// and the aggregate table is not printed at all in this mode, because every
/// notice is already on a line of its own and the table would be a second
/// count of the same facts.
///
/// It is `pub` so that the rule is pinned: a flag that quietly started
/// aggregating anyway would take the complete list away from every
/// measurement that reads it.
pub fn partition_findings(
  findings : Array[@report.Report],
  hiding : Array[@core.Span],
  show_notices : Bool,
) -> (Array[@report.Report], Array[@report.Report]) {
  if show_notices {
    (findings, [])
  } else {
    split_findings(findings, hiding)
  }
}

///|
/// The `NOTICES` table: the TOTAL line and one row per shape -- or NOTHING,
/// when there is nothing to say.
///
/// 0506. The TOTAL line reconciles the two halves -- the notices printed per
/// line and the notices aggregated -- against the tree's notice count, so a
/// reader (and a gate) can check that nothing was dropped on the way: the
/// rows plus the printed notices are the SUMMARY's `notices`.
///
/// The rows are `key=value` so that a gate can parse them without knowing
/// the shape names, and the TOTAL line carries `notices=`, `printed=` and
/// `aggregated=` for the same reason.
///
/// THE TABLE IS NOT SHOWN TWICE. With `--show-notices` every notice is
/// already on a line of its own, and the table would be a second count of
/// the same facts. And a tree with no notices has nothing to say about
/// notices.
///
/// It is `pub` so that the table is pinned by this package's own tests: a
/// table that stopped reconciling would still print, and the reader would
/// have no way to tell.
pub fn notice_lines(
  total : Int32,
  printed : Int32,
  aggregated : Array[@report.Report],
  show_notices : Bool,
) -> Array[String] {
  let out : Array[String] = []
  if show_notices || total <= 0 {
    return out
  }
  out.push(
    "NOTICES\tTOTAL\tnotices=\{total}\tprinted=\{printed}\taggregated=\{aggregated.length()}\t\{printed} of them can hide a finding; the other \{aggregated.length()} cannot, and are counted by shape below",
  )
  for pair in count_by_shape(aggregated) {
    let (msg, c) = pair
    out.push("NOTICES\tcount=\{c}\t\{msg}")
  }
  out
}

///|
/// The aggregated notices, counted BY SHAPE, and the number of them.
///
/// The shape is the whole message, because the message is what says which
/// construct was not read -- "test declaration", "if expression" -- and a
/// breakdown that lost that would not tell the reader what the analyzer
/// skipped.
///
/// It is `pub` so that the shape is pinned: a breakdown that silently started
/// counting something else would still add up to the right total.
pub fn count_by_shape(
  notices : Array[@report.Report],
) -> Array[(String, Int32)] {
  let counts : Map[String, Int32] = Map([])
  for r in notices {
    let c = match counts.get(r.message) {
      Some(n) => n + 1
      None => 1
    }
    counts.set(r.message, c)
  }
  let out : Array[(String, Int32)] = []
  for k, c in counts {
    out.push((k, c))
  }
  out.sort_by(fn(a : (String, Int32), b : (String, Int32)) {
    if a.1 != b.1 {
      b.1 - a.1
    } else {
      0
    }
  })
  out
}

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
  total : Int32
  /// How many of `findings` are "this declaration form is not analysed"
  /// notices rather than defects. Zero when the file is not understood.
  notices : Int32
  /// Line of the first genuine read failure, or 0 when the whole file was
  /// understood. `findings` holds only what happens BEFORE it; everything from
  /// that line on is counted in `unreliable` and not shown.
  region_line : Int32
  /// Findings at or after `region_line` — derived from an already-wrong tree, so
  /// reported only as a count, never as results.
  unreliable : Int32
  /// The subset-exclusion regions that lie inside some function's extent: the
  /// notices that CAN hide a finding. See `@walk.hiding_spans`.
  ///
  /// 0506. Carried from the walk, because the walk owns the geometry: a
  /// renderer that decided this on its own would be a second opinion about
  /// which regions are in a function, and the two would drift.
  hiding : Array[@core.Span]
  /// 0507. The calls the type lens could NOT check in this file: a call to a
  /// name known only from another package's `.mbti`, a method call, and a
  /// `..` chain link.
  ///
  /// THIS IS WHAT MAKES `CLEAN` HONEST. A file with no findings and 400
  /// unchecked calls is not a file with nothing wrong in it -- it is a file
  /// this analyzer could not check, and before 0507 the two printed the same
  /// word.
  n_unchecked : Int32
}

///|
/// Numbers that go onto the SUMMARY line. Computed in one place so the
/// printed identity has a single source of truth and a unit test can pin it.
pub struct Summary {
  parsed_files : Int32
  partial_files : Int32
  /// Pre-boundary defects: findings in parsed files, plus findings before the
  /// first parse error in partial files. Subtracting `notices` from
  /// `findings.length()` per file is the conversion from "things the analyzer
  /// has to say" to "things you should look at".
  actionable : Int32
  /// Pre-boundary notices: "this declaration form is outside the analysed
  /// subset" findings. Not a defect, but a real signal about coverage.
  notices : Int32
  /// Post-boundary findings across every file. The "noisy tail" the
  /// trusted-region split hides.
  unreliable : Int32
  /// Post-boundary findings in partial files whose pre-boundary finding count
  /// is zero. A subset of `unreliable` (every withheld finding is also
  /// unreliable) reported separately because "this many findings are in files
  /// the analyzer found nothing trustworthy in" is a useful number on its own.
  /// NOT part of the SUMMARY sum.
  withheld : Int32
  /// Pre-boundary + post-boundary. Equals `actionable + notices + unreliable`.
  total : Int32
  /// 0507. The calls the type lens could not check, over every file.
  ///
  /// NOT PART OF THE SUM, and it must not be: an unchecked call is not a
  /// finding, and adding it to `total` would break the identity the SUMMARY
  /// prints. It is printed BESIDE the sum because it is the number that says
  /// how much of the program the type lens did not read -- which is the
  /// difference between "there is nothing wrong here" and "there is nothing
  /// wrong here that I was able to check".
  n_unchecked : Int32
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
  let mut n_unchecked = 0
  for v in verdicts {
    let n = v.findings.length()
    total += v.total
    unreliable += v.unreliable
    n_unchecked += v.n_unchecked
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
    n_unchecked,
  }
}

///|
/// The NOTPARSE tallies, as a pure function over the verdicts: every partial
/// file's reason is counted, whatever its pre-boundary findings were, and up
/// to three example paths are kept per reason. Extracted from the scan loop
/// because the loop's 0.4.7 shape tallied a reason ONLY when the file had no
/// pre-boundary findings — a file with findings above its first parse error
/// is exactly as blind after that boundary, but its reason never reached the
/// count. Public for the same reason `aggregate` is: the counting rules are
/// part of what the output claims, and `sa_test.mbt` pins them.
pub fn tally_partial_reasons(
  verdicts : Array[Verdict],
) -> (Map[String, Int32], Map[String, Array[String]]) {
  let reasons : Map[String, Int32] = Map([])
  let examples : Map[String, Array[String]] = Map([])
  for v in verdicts {
    if !v.parsed {
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
  (reasons, examples)
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
///
/// `findings_shown_per_file` is how many findings are PRINTED per file. It is
/// a printing limit and nothing else: the counts in the SUMMARY come from
/// every finding, so raising it reveals findings that were already counted
/// and changes no number in the summary. The default is
/// `default_findings_shown_per_file`.
///
/// 0506. `show_notices` is the WHOLE per-line list of notices, which is the
/// default's opposite. By default a notice is printed only when it can hide a
/// finding -- when its region lies inside some function's extent -- and the
/// rest are counted by shape in the `NOTICES` table. `show_notices` prints
/// every notice per line, which is what the tool did before 0506 and what
/// every measurement that reads the rendered list needs.
pub async fn scan(
  target : String,
  excludes : Array[String],
  extern_iface_dirs : Array[String],
  auto_fetch_deps : Bool,
  mmd_out : String,
  per_function : Bool,
  findings_shown_per_file : Int32,
  show_notices : Bool,
  profile : Profile,
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
  // Per-package tables, built once. `union` returns a fresh table rather than
  // merging in place: merging into `iface_tab` itself would hand every
  // package's private names to every other package.
  let priv_tabs = collect_private_symtabs(files)
  let file_tabs : Map[String, @core.IfaceSymTab] = Map([])
  let mut priv_names = 0
  for d, t in priv_tabs {
    priv_names += t.n_types() + t.n_values()
    file_tabs.set(d, @core.IfaceSymTab::union(iface_tab, t))
  }
  // Stated rather than silent, for the reason the dot-directory count above is:
  // a table missing names it never looked for is indistinguishable from a
  // target that has none.
  if priv_tabs.length() > 0 {
    println(
      "PRIVTAB\tpackages=\{priv_tabs.length()}\tnames=\{priv_names}\t(package-private top-level names, sibling files only)",
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
  let kind_files : Map[String, Int32] = Map([])
  let kind_parsed : Map[String, Int32] = Map([])
  let kind_defects : Map[String, Int32] = Map([])
  let kind_notices : Map[String, Int32] = Map([])
  let kinds : Array[String] = [".mbt", ".mbti", ".mbtp", ".mbt.md", ".mbtx"]
  // 0506. The notices that hide nothing, collected across the whole tree and
  // printed ONCE, by shape, at the end. They are collected rather than counted
  // here so the table can be a breakdown and not a second total: the per-file
  // `notices=N` is already the file's count, and this is what the tree adds up
  // to.
  let aggregated_notices : Array[@report.Report] = []
  let mut printed_notice_count = 0
  for f in files {
    // a directory with no `.mbt` of its own — a lone `.mbti`, a script — falls
    // back to the shared table, which is exactly what every file used before
    // packages were separated
    let tab = match file_tabs.get(dir_of(f)) {
      Some(t) => t
      None => iface_tab
    }
    let v = analyze(f, tab, per_function, profile)
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
        // 0507. `unchecked` says how many calls the type lens could NOT check
        // in this file. It is printed on the CLEAN line too, because a clean
        // file whose calls went unchecked is the case the word "clean" used
        // to hide: there was nothing to report, and nothing had been checked
        // either. The count is a disclosure, not a finding, and it is NOT part
        // of the SUMMARY's sum.
        println("CLEAN\t\{v.kind}\tunchecked=\{v.n_unchecked}\t\{v.path}")
      } else {
        println(
          "FOUND\t\{v.kind}\tdefects=\{n - v.notices}\tnotices=\{v.notices}\tunchecked=\{v.n_unchecked}\t\{v.path}",
        )
        // 0506. The printed set is the defects plus the notices that can HIDE
        // something; the rest are counted. The per-file `notices=N` above is
        // unchanged either way -- it is the file's notice count, and the count
        // is not the problem, the VOLUME of lines about it was.
        let (printed, aggregated) = partition_findings(
          v.findings,
          v.hiding,
          show_notices,
        )
        for r in aggregated {
          aggregated_notices.push(r)
        }
        for r in printed {
          if r.is_notice() {
            printed_notice_count += 1
          }
        }
        let (shown, more) = show_plan(printed.length(), findings_shown_per_file)
        for i in 0..<shown {
          println(printed[i].render())
        }
        if more {
          println("...  \{printed.length() - shown} more in this file")
        }
      }
    } else {
      // Partly understood: report what was read up to the first real failure
      // and say plainly how much came after it and is therefore not evidence.
      // The reason tally lives in `tally_partial_reasons`, which counts EVERY
      // partial file — one with pre-boundary findings is as blind after its
      // boundary as one without.
      let n = v.findings.length()
      if n > 0 {
        println(
          "PARTIAL\t\{v.kind}\tdefects=\{n - v.notices}\tnotices=\{v.notices}\tunchecked=\{v.n_unchecked}\tread up to line \{v.region_line}, \{v.unreliable} after it not shown\t\{v.path}",
        )
        let (printed, aggregated) = partition_findings(
          v.findings,
          v.hiding,
          show_notices,
        )
        for r in aggregated {
          aggregated_notices.push(r)
        }
        for r in printed {
          if r.is_notice() {
            printed_notice_count += 1
          }
        }
        let (shown, more) = show_plan(printed.length(), findings_shown_per_file)
        for i in 0..<shown {
          println(printed[i].render())
        }
        if more {
          println(
            "...  \{printed.length() - shown} more before the boundary in this file",
          )
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
  // 0506. The notices that hide nothing, printed ONCE for the whole tree, by
  // shape. The TABLE is the aggregate's whole output: the count per shape is
  // what a reader wants ("the analyzer did not read 6,148 test blocks"), and
  // the per-line version of the same fact was 6,148 lines.
  //
  // Whether the table is shown at all, and what its TOTAL line says, are
  // `notice_lines`' decisions -- they are pure, and they are pinned by this
  // package's own tests. The TOTAL line reconciles the two halves -- the
  // notices printed per line and the notices aggregated here -- against the
  // SUMMARY's `notices`, so a reader (and a gate) can check that nothing was
  // dropped on the way.
  let total_notices = s.notices
  // THE TABLE IS BOUND BEFORE THE LOOP, and that is not a style choice.
  //
  // `moon fmt` splits a long `for` header across lines -- `for` alone on one
  // line, the iterator clause on the next -- and the frontend does not READ
  // that shape: the parser bumps `for` and asks for the loop variable at once
  // (`expect_name("loop variable")`), so the newline in between is the wrong
  // token. MEASURED, with the toolchain as the oracle: `moon check` ACCEPTS
  //
  //     for
  //       x in xs {
  //
  // and this analyzer reports the file PARTIAL with "expected loop variable".
  // Writing that shape would have left the analyzer unable to read its own
  // source, and the self-scan stage of the release gate would have failed on
  // `files != parsed`. The bound variable keeps the header on one line.
  //
  // THIS IS NOT 0482's SETTLED REJECTION. 0482 settled the C-STYLE head on
  // the line after the `for` -- `for` / `i = 0;` / ... -- and the toolchain
  // REJECTS that shape, so the analyzer's rejection there is correct. The
  // shape here is the MOONBIT-STYLE binder head, `for` / `x in xs {`, and
  // the toolchain accepts it. The gap is real and it is NOT fixed here: it
  // is a parser increment of its own, and it is written up in NARRATIVE.md
  // with its measurement.
  let table = notice_lines(
    total_notices, printed_notice_count, aggregated_notices, show_notices,
  )
  for line in table {
    println(line)
  }
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
  // Unparsed files are counted by reason rather than listed. One line per file
  // would replace thousands of findings with thousands of lines and teach the
  // reader to scroll past the section that matters. `tally_partial_reasons`
  // counts every partial file, whatever its pre-boundary findings were.
  let (reasons, examples) = tally_partial_reasons(verdicts)
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
    "SUMMARY\tfiles=\{files.length()}\tparsed=\{s.parsed_files}\tactionable=\{s.actionable}\tnotices=\{s.notices}\tunreliable=\{s.unreliable}\twithheld=\{s.withheld}\tunchecked=\{s.n_unchecked}\ttotal=\{s.total}\t(actionable+notices+unreliable = total; withheld ⊆ unreliable; unchecked calls are not findings)",
  )
  if !complete {
    println(
      "NOTE\tthis tree exceeded the \{max_files}-file cap; the counts above cover only what was walked",
    )
  }
  if mmd_out != "" {
    emit_mmd(mmd_out, verdicts, s, target, root, findings_shown_per_file)
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
  findings_shown_per_file : Int32,
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
///
/// **`pub` was a workaround for a gap that 0.4.12 closed, and is kept as a
/// deliberate choice, not as an oversight.** It was added in 0.4.10 because the
/// analyzer resolved a cross-file name ONLY through a `.mbti`, where a
/// package-private `fn` appears in none (`moon info` does not list it), so the
/// 0.4.9 self-scan reported `no visible binding for 'is_coordinate'` and
/// `'split_coord'` on `provenance.mbt` — on code `moon check` accepts. Since
/// 0.4.12 the analyzer reads sibling `.mbt` files too, so the workaround is no
/// longer *needed*; it is left in place because these are genuinely part of this
/// package's surface (the provenance entry points call them) and un-`pub`ing
/// them now would change the published API for no measured gain. If you are
/// about to "tidy" this back to a private `fn`, that is the change to argue
/// about — not a cleanup.
pub fn is_coordinate(t : String) -> Bool {
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
/// `pub` for the reason given on `is_coordinate`: `provenance.mbt` names this
/// from another file, and a package-private function is in no `.mbti`, so the
/// analyzer cannot see the binding that is right there.
///
/// This split matters more than it looks. The fetch target and the `.repos`
/// path are built from DIFFERENT strings: fetching `author/module` lands in
/// `.repos/author/module/<version>/`. An earlier version of this file stripped
/// only `@latest` and kept a pinned version in the name, so
/// `...@0.3.1` was looked up at `.repos/author/module@0.3.1`, which never
/// exists — `@latest` worked only because stripping it was the same operation
/// that produced the right path. Any pinned target silently found nothing.
pub fn split_coord(t : String) -> (String, String) {
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
/// The findings a file contributes, after the PROFILE and after the `nosec`.
///
/// 0507. THE ORDER IS THE POINT, and it is the order the two features have to
/// be composed in:
///
///   1. the PROFILE, which removes whole families the reader does not want;
///   2. the `nosec`, which removes individual findings on individual lines;
///   3. the STALE-SUPPRESSION findings, which are produced LAST so that a
///      blanket `// nosec` cannot silence the warning about its own
///      staleness.
///
/// The stale findings are produced against the PROFILED list, so a `nosec`
/// that names a family the profile already removed is reported as stale: it
/// is not doing anything for the reader either, and saying so is the truth.
///
/// The result is what the TRUSTED-REGION SPLIT then works on, so `total`,
/// `unreliable` and `notices` all describe the same set of findings.
fn filtered_reports(
  raw : Array[@report.Report],
  src : String,
  profile : Profile,
) -> Array[@report.Report] {
  let filtered = apply_profile(raw, profile)
  let mut nosecs : Array[Nosec] = []
  if profile.honor_nosec {
    nosecs = parse_nosec(src)
  }
  let (kept, stale) = apply_nosec(filtered, nosecs)
  let all : Array[@report.Report] = []
  for r in kept {
    all.push(r)
  }
  for r in stale {
    all.push(r)
  }
  all
}

///|
async fn analyze(
  p : String,
  extern_iface : @core.IfaceSymTab,
  per_function : Bool,
  profile : Profile,
) -> Verdict {
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
      let rs = filtered_reports(
        @moonfiles.iface(src, n, extern_iface),
        src,
        profile,
      )
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
        hiding: [],
        n_unchecked: 0,
      }
    }
    ".mbtp" => {
      let rs = filtered_reports(@moonfiles.proof(src, n), src, profile)
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
        hiding: [],
        n_unchecked: 0,
      }
    }
    ".mbt.md" => {
      let r = @moonfiles.literate(src, n)
      let reports = filtered_reports(r.reports, src, profile)
      let total = reports.length()
      // Same trusted-region split as `.mbt`: n_parse already excludes the
      // deliberate fence skips, so a document whose only complaint is "this
      // fence was not analysed" is still a document that was read, and a
      // document that hits a real failure keeps everything before it.
      let cut = r.first_error_line
      let reliable : Array[@report.Report] = []
      let mut notices = 0
      for rep in reports {
        if cut > 0 && rep.span.start.line >= cut {
          continue
        }
        reliable.push(rep)
        if rep.is_notice() {
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
        hiding: r.hiding,
        n_unchecked: 0,
      }
    }
    _ => {
      // The behavioral lens's ENTRY POINT. The module entry executes a
      // function body only if something calls it from a top-level statement,
      // so on a library module it never executes one at all. The per-function
      // entry analyzes every function as if it were the program's entry.
      let r = if per_function {
        @pipeline.run_functions(src, n, extern_iface)
      } else {
        @pipeline.run(src, n, extern_iface)
      }
      let reports = filtered_reports(r.reports, src, profile)
      let total = reports.length()
      // The trusted region: everything before the first genuine read failure.
      //
      // A genuine read failure cannot survive this cut: a real failure on that
      // line would itself have set first_error_line to it. So the notices
      // counted below are counted by the SHARED predicate
      // (`@report.is_notice`), not by a second opinion about the family --
      // the renderer, this counter and the mermaid drawing must not be able to
      // disagree about what a notice is.
      let cut = r.first_error_line
      let reliable : Array[@report.Report] = []
      let mut notices = 0
      for rep in reports {
        if cut > 0 && rep.span.start.line >= cut {
          continue
        }
        reliable.push(rep)
        if rep.is_notice() {
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
        hiding: r.hiding,
        n_unchecked: r.n_unchecked,
      }
    }
  }
}

///|
fn get_or_zero(m : Map[String, Int32], k : String) -> Int32 {
  match m.get(k) {
    Some(x) => x
    None => 0
  }
}

///|
fn bump(m : Map[String, Int32], k : String) -> Int32 {
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

///|
/// The parent directory of a path, accepting EITHER separator. A target named
/// on the command line arrives with whatever the shell produced, and the file
/// list mixes both: this file builds child paths as `dir + "/" + entry` while a
/// user-typed Windows path keeps its backslashes. A package is a directory, so
/// this is the key the per-package symbol tables are filed under — and getting
/// it wrong is silent, because a wrong key just yields no table.
///
/// `pub` only so `sa_test.mbt` can pin the separator handling: a private `fn`
/// is invisible to another file in the same package, and the `.mbti` this
/// analyzer itself analyses would report it exactly the way it reported
/// `is_coordinate` in 0.4.10. Do not make this private again.
///
/// `"."` for a bare file name, and `"/"` when the separator is the very first
/// character, so a root-level path does not become empty.
pub fn dir_of(path : String) -> String {
  let chars = path.to_array()
  let mut cut = -1
  let mut i = chars.length() - 1
  while i >= 0 {
    if chars[i] == '/' || chars[i] == '\\' {
      cut = i
      break
    }
    i -= 1
  }
  if cut < 0 {
    "."
  } else if cut == 0 {
    "/"
  } else {
    let mut out = ""
    let mut j = 0
    while j < cut {
      out = out + chars[j].to_string()
      j += 1
    }
    out
  }
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
fn ok_segment(chars : Array[Char], from : Int32, to : Int32) -> Bool {
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
) -> (@core.IfaceSymTab, Int32) {
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

///|
/// One symbol table per package DIRECTORY, holding the top-level names the
/// `.mbt` files in it declare — including the private ones a `.mbti` omits.
///
/// `collect_iface_symtabs` above cannot do this job: a generated interface
/// carries `pub` items alone, so every package-private top-level name was
/// invisible and each call to one was reported as `no visible binding`. On
/// riantr/pyroduct 0.1.29 that was 26 of 31 actionable findings, every one a
/// private top-level `fn` in the same directory as its caller.
///
/// Files come from the already-collected `files` list rather than a second
/// directory walk, and the table is filed by `dir_of` so a package sees only
/// its OWN files. Sibling-only visibility is the language rule — a package is
/// a directory — and a global table instead would let one package's private
/// names silence a real finding in another.
///
/// The analyzed file is IN its own table: it is part of its package, so a
/// top-level `const` it declares is a real binding even when the structural
/// walk does not register that declaration form itself.
async fn collect_private_symtabs(
  files : Array[String],
) -> Map[String, @core.IfaceSymTab] {
  let out : Map[String, @core.IfaceSymTab] = Map([])
  for f in files {
    if !f.has_suffix(".mbt") {
      continue
    }
    let data = @fs.read_file(f) catch { _ => continue }
    let text = data.text() catch { _ => continue }
    if text == "" {
      continue
    }
    let sub = @parser.collect_declared_names(text)
    let d = dir_of(f)
    match out.get(d) {
      Some(t) => {
        let _ = t.merge(sub)
      }
      None => out.set(d, sub)
    }
  }
  // 0502. A TYPE'S METHOD MAY BE CALLED UNQUALIFIED, inside the package that
  // declares the type -- so the METHOD SEGMENT of every `Type::method` this
  // package declares is recorded as a value of this package's table.
  //
  // IT IS PACKAGE-LOCAL ON PURPOSE. This table is filed by DIRECTORY and
  // unioned only into the files of that same directory (see the note above
  // `collect_private_symtabs`), so a method of a type in package A cannot
  // silence a name in package B. Doing it in the SHARED cross-file table
  // would let every method name in the world resolve everywhere, which is not
  // the language's rule and would trade six false positives for an unknown
  // number of false negatives.
  //
  // => 判据: the rule the toolchain applies is "a method of a type you can
  // see", and the table this writes into is exactly the set of names one
  // package can see.
  for _, t in out {
    add_method_segments(t)
  }
  out
}

///|
/// The METHOD SEGMENTS of a symbol table's qualified names: `Vector::makei`
/// contributes `makei`.
///
/// 0502. A TYPE'S METHOD MAY BE CALLED UNQUALIFIED, inside the package that
/// declares the type -- so the METHOD SEGMENT of every `Type::method` a
/// package declares is recorded as a value of that package's table.
///
/// MEASURED: moonbitlang/core `immut/vector/vector.mbt:68` declares
/// `pub fn[A] Vector::makei(..)` and `immut/vector/invariants_wbtest.mbt`
/// calls `makei(..)` at lines 227, 229, 230, 354, 363 and 366. The toolchain
/// accepts every one of them -- the whole `moonbitlang/core` package checks
/// with ONE error and it is not this name -- and the analyzer reported all
/// six as `no visible binding for 'makei'`.
///
/// ONLY THE SEGMENT AFTER THE LAST `::`, and only for a name that actually
/// carries one: a table holds `Type::method` for a method and `name` for
/// anything else, and `path_tail` of a name with no `::` is the empty string.
///
/// THE DUPLICATES ARE DROPPED, because the table is a set of names and two
/// types may declare a method of the same name.
pub fn method_segments(tab : @core.IfaceSymTab) -> Array[String] {
  let segs : Array[String] = []
  for k, _ in tab.all_values() {
    if k.contains("::") {
      let seg = @core.path_tail(k)
      if seg != "" && seg != k && !segs.contains(seg) {
        segs.push(seg)
      }
    }
  }
  segs
}

///|
/// Record every method segment of this table as a VALUE of this table.
///
/// THE SEGMENTS ARE COLLECTED FIRST: adding to the table while iterating it
/// would be iterating a map that the loop is changing.
///
/// A method is a FUNCTION, so the value is recorded with `is_const` false --
/// `src/types/infer.mbt` types a const as `TUnknown` and a function as
/// `TUnknownFn`, and a method is callable.
pub fn add_method_segments(tab : @core.IfaceSymTab) -> Unit {
  for seg in method_segments(tab) {
    tab.add_value(seg)
  }
}
