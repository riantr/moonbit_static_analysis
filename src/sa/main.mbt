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
pub async fn scan(target : String) -> Unit {
  let root = locate(target)
  if root == "" {
    println("ERROR\tcannot locate source for target: \{target}")
    return
  }
  println("TARGET\t\{target}\t\{root}")
  let files : Array[String] = []
  collect(root, files)
  println("SCANNED\t\{files.length()} files under \{root}")
  let mut total = 0
  for f in files {
    let n = analyze(f)
    total += n
    println("\{kind_of(f)}\t\{n}\t\{f}")
  }
  println("SUMMARY\tfiles=\{files.length()}\tfindings=\{total}")
}

///|
/// Resolve a target to a directory holding its source. A coordinate is
/// fetched; a path is used as-is. Returns "" when nothing can be found.
async fn locate(target : String) -> String {
  if is_coordinate(target) {
    // `moon fetch` takes the bare module and resolves @latest itself; passing
    // "@latest" through fails with "unexpected character 'l' while parsing
    // major version number".
    let spec = strip_latest(target)
    let _ = @process.run("moon", ["fetch", spec])
    let base = ".repos/" + spec
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
/// Drop a trailing `@latest`. A coordinate carries at most one `@`, so stopping
/// at the first one is enough — and avoids slicing, which this dialect lacks.
fn strip_latest(t : String) -> String {
  if !t.has_suffix("@latest") {
    return t
  }
  let mut out = ""
  for c in t {
    if c == '@' {
      break
    }
    out = out + c.to_string()
  }
  out
}

///|
async fn is_dir(p : String) -> Bool {
  let d = @fs.opendir(p) catch { _ => return false }
  ignore(d)
  true
}

///|
async fn collect(dir : String, out : Array[String]) -> Unit {
  let entries = @fs.readdir(dir) catch { _ => return }
  for e in entries {
    // Skip build output, vendored registry sources (.mooncakes, .repos) and
    // every other dot-directory: none of them are the target's own source, and
    // walking them inflates the count with a dependency's code.
    if e == "_build" || e.has_prefix(".") {
      continue
    }
    let p = dir + "/" + e
    if is_dir(p) {
      collect(p, out)
    } else if wanted(p) {
      out.push(p)
    }
  }
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
