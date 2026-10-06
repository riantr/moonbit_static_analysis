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
  //   <target>  registry coordinate (author/module[@version]) or a path
  //   --exclude a directory name to skip, repeatable; matches any path segment
  let mut target = ""
  let excludes : Array[String] = []
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
  @sa.scan(target, excludes)
}
