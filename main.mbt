///|
/// Parse a non-negative count. `None` when the text is not one.
///
/// The flag is REFUSED rather than silently taken as zero: a scan that printed
/// nothing because the flag was mistyped would look exactly like a clean file,
/// which is the failure mode the cap itself exists to stop.
fn parse_count(s : String) -> Int32? {
  // Seven digits is the ceiling: the cap is a PRINTING limit, and a number
  // that large is a typo rather than a request.
  if s.length() == 0 || s.length() > 7 {
    return None
  }
  let mut n = 0
  for ch in s {
    if !ch.is_ascii_digit() {
      return None
    }
    n = n * 10 + (ch.to_int() - '0'.to_int())
  }
  Some(n)
}

///|
async fn main {
  let args = @env.args()
  // NOTE: this cannot exit non-zero. MoonBit exposes no process-exit entry point
  // in the packages available here (no `sys` package; moonbitlang/async has only
  // `Output::exit_code`, which reads a finished process). So a target that
  // cannot be located prints ERROR and still exits 0 — a caller must read the
  // output, not the exit code. Recorded as a known limitation.
  //
  // Usage:
  //   moonx riantr/moonbit_static_analysis@latest <target> [--exclude <dir>]...
  //                                          [--extern-iface-dir <dir>]...
  //                                          [--no-auto-fetch-deps]
  //                                          [--show-notices]
  //                                          [--findings-shown-per-file N]
  //   <target>                registry coordinate (author/module[@version]) or a path
  //   --exclude               a directory name to skip, repeatable
  //   --extern-iface-dir      a directory to scan for `.mbti` files whose declared
  //                           types/values are treated as valid in every .mbt file
  //                           under analysis. Repeatable. The natural target is
  //                           `.repos/` after `moon fetch` of the dependencies you
  //                           want indexed. The target's own tree is always indexed.
  //   --no-auto-fetch-deps    by default the analyzer reads the target's
  //                           `moon.mod` and `moon fetch`es each direct import.
  //                           Pass this to skip the auto-fetch.
  //   --mmd <path>            ALSO write the scan as a mermaid `stateDiagram-v2`
  //                           to `<path>`, and print `MMD<TAB><path>` on the
  //                           last line. Opt-in on purpose: stdout stays the
  //                           authoritative text report, and a diagram may be a
  //                           deliberate subset (see `mermaid_states`' file cap),
  //                           so it is never the only output.
  //   --mmd-auto              Same, but pick the name and write it to the
  //                           working directory -- and the name is the SAME
  //                           one `scan_artifact_name` builds:
  //                           `<package>_<version>_<moonbit>_<stamp>.mmd`, with
  //                           `unknown` for anything it could not determine.
  //                           Never inside the analysed tree: this
  //                           module only ever READS the target's files.
  //   --per-function          Enter the BEHAVIORAL lens at each FUNCTION rather
  //                           than at the module. By default a function body is
  //                           executed only if something calls it from a
  //                           top-level statement, so on a library module the
  //                           behavioral lens never executes a body at all. This
  //                           flag analyzes every function as if it were the
  //                           program's entry point, with its parameters bound
  //                           to fresh abstract values of their declared types.
  //   --show-notices          Print EVERY notice per line, not only the ones
  //                           that can hide a finding. By default a notice is
  //                           printed only when it sits inside a function's
  //                           extent -- that is, when a conclusion may have
  //                           been withheld because of it -- and the rest are
  //                           counted by shape in the `NOTICES` table. This flag
  //                           restores the whole per-line list, which is what
  //                           the tool printed before 0506 and what a reader
  //                           wants when they are looking for a specific
  //                           construct. It changes no count: the SUMMARY's
  //                           numbers are the same either way.
  //   --findings-shown-per-file N
  //                           How many findings are PRINTED per file (default 40).
  //                           This is a PRINTING limit: the SUMMARY counts come
  //                           from every finding, so raising it reveals findings
  //                           that were already counted and changes no summary
  //                           number. It exists because the default cap hid the
  //                           defects on one file -- the first forty findings were
  //                           all notices and the thirty-eight defects behind them
  //                           were never printed.
  let mut target = ""
  let excludes : Array[String] = []
  let extern_iface_dirs : Array[String] = []
  let mut auto_fetch_deps = true
  // "" = off; "@" = on with an auto-named file in the working directory;
  // anything else = on, writing exactly here.
  let mut mmd_out = ""
  let mut per_function = false
  let mut show_notices = false
  let mut findings_shown_per_file = @sa.default_findings_shown_per_file
  let mut i = 1
  while i < args.length() {
    let a = args[i]
    if a == "--exclude" {
      if i + 1 >= args.length() {
        println("ERROR\t--exclude needs a directory name")
        return
      }
      i += 1
      excludes.push(args[i])
    } else if a == "--extern-iface-dir" {
      if i + 1 >= args.length() {
        println("ERROR\t--extern-iface-dir needs a directory name")
        return
      }
      i += 1
      extern_iface_dirs.push(args[i])
    } else if a == "--findings-shown-per-file" {
      if i + 1 >= args.length() {
        println("ERROR\t--findings-shown-per-file needs a count")
        return
      }
      i += 1
      // A count that is not a number is refused rather than silently taken as
      // zero: a scan that printed nothing because the flag was mistyped would
      // look exactly like a clean file.
      match parse_count(args[i]) {
        Some(v) => findings_shown_per_file = v
        None => {
          println(
            "ERROR\t--findings-shown-per-file needs a count, got '\{args[i]}'",
          )
          return
        }
      }
    } else if a == "--mmd" {
      // The path is REQUIRED here, and that is a decision rather than an
      // omission. An optional value would be ambiguous: in
      // `<target> --mmd <path>` the bare word after `--mmd` could equally be
      // the path (this reading) or a second, unexpected target (the other).
      // There is no way to tell them apart, and guessing wrong fails with
      // "unexpected extra argument" — so the value is mandatory and
      // `--mmd-auto` is the separate spelling for "pick the name for me".
      if i + 1 >= args.length() {
        println(
          "ERROR\t--mmd needs a path, or use --mmd-auto for the default name",
        )
        return
      }
      i += 1
      mmd_out = args[i]
    } else if a == "--mmd-auto" {
      mmd_out = "@"
    } else if a == "--per-function" {
      per_function = true
    } else if a == "--show-notices" {
      show_notices = true
    } else if a == "--no-auto-fetch-deps" {
      auto_fetch_deps = false
    } else if target == "" {
      target = a
    } else {
      println("ERROR\tunexpected extra argument: \{a}")
      return
    }
    i += 1
  }
  if target == "" {
    target = "."
  }
  @sa.scan(
    target, excludes, extern_iface_dirs, auto_fetch_deps, mmd_out, per_function,
    findings_shown_per_file, show_notices,
  )
}
