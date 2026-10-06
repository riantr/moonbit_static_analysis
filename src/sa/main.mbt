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
pub async fn scan(target : String) -> Unit {
  let root = locate(target)
  if root == "" {
    println("ERROR\tcannot locate source for target: \{target}")
    return
  }
  println("TARGET\t\{target}\t\{root}")
  let files : Array[String] = []
  let complete = collect(root, files)
  if complete {
    println("SCANNED\t\{files.length()} files under \{root}")
  }
  let mut total = 0
  for f in files {
    let n = analyze(f)
    total += n
    println("\{kind_of(f)}\t\{n}\t\{f}")
  }
  println("SUMMARY\tfiles=\{files.length()}\tfindings=\{total}")
  if !complete {
    println(
      "NOTE\tthis tree exceeded the \{max_files}-file cap; the counts above cover only what was walked",
    )
  }
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
async fn collect(root : String, out : Array[String]) -> Bool {
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
      if e == "_build" || e.has_prefix(".") {
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
async fn analyze(p : String) -> Int {
  let src = read_or(p)
  let n = base_of(p)
  match kind_of(p) {
    ".mbti" => @moonfiles.iface(src, n).length()
    ".mbtp" => @moonfiles.proof(src, n).length()
    ".mbt.md" => @moonfiles.literate(src, n).reports.length()
    _ => @pipeline.run(src, n).reports.length()
  }
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
