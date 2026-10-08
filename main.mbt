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
  let mut target = ""
  let excludes : Array[String] = []
  let extern_iface_dirs : Array[String] = []
  let mut auto_fetch_deps = true
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
  @sa.scan(target, excludes, extern_iface_dirs, auto_fetch_deps)
}
