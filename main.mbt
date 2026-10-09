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
  //   --mmd-auto              Same, but pick the name —
  //                           `<label>-<version>_<stamp>.mmd` in the working
  //                           directory. Never inside the analysed tree: this
  //                           module only ever READS the target's files.
  let mut target = ""
  let excludes : Array[String] = []
  let extern_iface_dirs : Array[String] = []
  let mut auto_fetch_deps = true
  // "" = off; "@" = on with an auto-named file in the working directory;
  // anything else = on, writing exactly here.
  let mut mmd_out = ""
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
  @sa.scan(target, excludes, extern_iface_dirs, auto_fetch_deps, mmd_out)
}
