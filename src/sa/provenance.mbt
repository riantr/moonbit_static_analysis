// provenance: what was scanned, at which version, and when — carried in the
// artifact's NAME, not only in its body.
//
// A scan result is a claim about a specific tree at a specific moment. Two
// scans of "the same target" a week apart are different artifacts, and a file
// called `scan.mmd` cannot say which it is. So the name carries all three
// facts: `<target-slug>-<version>_<UTC stamp>.mmd`.
//
// Two decisions, both measured rather than assumed:
//
//   - The clock. `moonbitlang/async::now()` is milliseconds since epoch, and
//     that was checked against wall time rather than read off a doc comment: a
//     wasm run returned 1791522911114 against a wall clock of
//     1791522910008 measured ~1.1 s earlier, which is exactly the delay
//     between the two calls. `Int` is 32-bit on wasm32 and cannot hold an
//     epoch millisecond, so every step below stays in `Int64`.
//   - The timezone. There is no timezone database available here, so the stamp
//     is UTC and says so with a trailing `Z`. A local-time stamp would need
//     one and would be wrong by an hour twice a year.
//
// A name never silently omits what it could not determine. An unknown version
// or an unavailable clock is written as the literal token `unknown` rather
// than dropped, because a name that quietly lacks the version is
// indistinguishable from one where the version was `0`.

///|
/// Where a scan came from and when. `version` and `scanned_at` are `""` when
/// they could not be determined — see `scan_artifact_name`, which renders that
/// as `unknown` rather than omitting the segment.
pub(all) struct ScanProvenance {
  /// Exactly what the caller asked for: a coordinate, or a path.
  target : String
  /// The target's own version. From the coordinate's `@version` when there is
  /// one, otherwise from the target's `moon.mod`.
  version : String
  /// `stamp_utc` of the moment the scan ran, or `""` for no clock.
  scanned_at : String
}

///|
/// A one-line human summary, for a log or a commit message.
pub fn ScanProvenance::describe(self : ScanProvenance) -> String {
  "target=" +
  self.target +
  " version=" +
  or_unknown(self.version) +
  " scanned_at=" +
  or_unknown(self.scanned_at)
}

///|
/// An empty provenance field renders as `unknown`, never as nothing. Used by
/// both the document header and the artifact name, so the two can never
/// disagree about what "missing" looks like.
pub fn prov_or_unknown(s : String) -> String {
  or_unknown(s)
}

///|
fn or_unknown(s : String) -> String {
  if s == "" {
    "unknown"
  } else {
    s
  }
}

///|
/// The version a `moon.mod` (or the older `moon.mod.json`) declares.
///
/// Returns `""` when the file declares none. Both spellings are accepted
/// because both exist in the wild: `moon.mod.json` carries a deprecation
/// notice telling you to migrate to `moon.mod`, so trees in the field have
/// each or the other, and a scanner that only understood one would report a
/// version-less target for half of them.
///
/// The key must be the WHOLE first token of the line, so a `min_version` or
/// any future `*_version` field cannot be mistaken for it.
pub fn moon_mod_version(src : String) -> String {
  for raw in src.split("\n") {
    let line = raw.split("//").to_array()[0].trim().to_owned()
    if line.has_prefix("version") {
      let v = first_quoted_after(line, "version")
      if v != "" {
        return v
      }
    } else if line.has_prefix("\"version\"") {
      let v = first_quoted_after(line, "\"version\"")
      if v != "" {
        return v
      }
    }
  }
  ""
}

///|
/// The first double-quoted substring after `key` on a line.
fn first_quoted_after(line : String, key : String) -> String {
  let parts = line.split(key).to_array()
  if parts.length() < 2 {
    return ""
  }
  let quoted = parts[1].split("\"").to_array()
  if quoted.length() < 2 {
    ""
  } else {
    quoted[1].to_owned()
  }
}

///|
/// Epoch milliseconds to a UTC stamp: `YYYYMMDDTHHMMSSZ`.
///
/// Compact on purpose — this goes in a filename, and the colons a readable
/// timestamp would want are illegal in a path on Windows. The civil date is
/// computed with Howard Hinnant's `civil_from_days`; it is pinned in the tests
/// against dates whose answer is not in dispute (1970-01-01, a leap day, the
/// epoch year boundary) rather than trusted.
pub fn stamp_utc(ms : Int64) -> String {
  if ms < 0L {
    // Before the epoch. Rendering it as a date would imply a scan that
    // happened before any computer did.
    return "unknown"
  }
  let day_ms = 86400000L
  let days = ms / day_ms
  let sec = ms % day_ms / 1000L
  let (y, mo, d) = civil_from_days(days.to_int())
  pad4(y) +
  pad2(mo) +
  pad2(d) +
  "T" +
  pad2(sec.to_int() / 3600) +
  pad2(sec.to_int() / 60 % 60) +
  pad2(sec.to_int() % 60) +
  "Z"
}

///|
/// Days since 1970-01-01 to a proleptic Gregorian `(year, month, day)`.
///
/// Hinnant's `civil_from_days`: the era is 400 years because that is exactly
/// how often the leap-year rule repeats, so the leap correction is a single
/// division rather than a search. The shift by 719468 days puts the era
/// boundary on 0000-03-01, which is where the rule starts repeating.
fn civil_from_days(days : Int) -> (Int, Int, Int) {
  let z = days + 719468
  let era = z / 146097
  let doe = z - era * 146097
  let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
  let y = yoe + era * 400
  let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
  let mp = (5 * doy + 2) / 153
  let d = doy - (153 * mp + 2) / 5 + 1
  let mo = if mp < 10 { mp + 3 } else { mp - 9 }
  let yy = if mo <= 2 { y + 1 } else { y }
  (yy, mo, d)
}

///|
fn pad2(n : Int) -> String {
  if n < 10 {
    "0" + n.to_string()
  } else {
    n.to_string()
  }
}

///|
fn pad4(n : Int) -> String {
  if n < 10 {
    "000" + n.to_string()
  } else if n < 100 {
    "00" + n.to_string()
  } else if n < 1000 {
    "0" + n.to_string()
  } else {
    n.to_string()
  }
}

///|
/// The filename for a scan artifact: `<label>-<version>_<stamp>.mmd`.
///
/// `label` is the thing a human browsing a folder of scans would recognise.
/// For a coordinate that is the module name; for a path it is the resolved
/// directory name, NOT the string the caller passed. The two differ in exactly
/// the case that matters — scanning `.` would otherwise produce an artifact
/// called `_.mmd`. Pass `root = ""` to fall back to the target text.
///
/// The label is slugged because `< > : " / \ | ? *` are illegal in a Windows
/// path and a coordinate is full of `/`. An inline `@version` on a coordinate
/// is dropped because the version is already its own segment; keeping it would
/// print it twice.
///
/// A missing version or stamp becomes the literal `unknown`. Dropping the
/// segment instead would produce a name that looks complete and is not.
pub fn scan_artifact_name(p : ScanProvenance, root : String) -> String {
  let stem = if is_coordinate(p.target) {
    let (mod, _) = split_coord(p.target)
    mod
  } else {
    let leaf = resolve_label(root)
    if leaf == "" {
      p.target
    } else {
      leaf
    }
  }
  slug(stem) +
  "-" +
  slug(or_unknown(p.version)) +
  "_" +
  slug(or_unknown(p.scanned_at)) +
  ".mmd"
}

///|
/// A human-recognisable name for the directory that was scanned.
///
/// The trap is the most ordinary invocation there is: `scan .`. `locate` hands
/// back the path as the caller wrote it, so the last segment of `.` is `.`, and
/// an artifact named `_.mmd` tells nobody anything. `.` and `..` name a
/// POSITION, not a thing, so they are resolved against the working directory —
/// `env::current_dir`, which is available on wasm and was checked there rather
/// than assumed.
///
/// The label is best-effort by design. It is a convenience for a human
/// browsing a folder; the document header carries the exact target string, and
/// that is the authoritative record.
fn resolve_label(root : String) -> String {
  if root == "" {
    return ""
  }
  // Walk the path the way a filesystem would: `.` contributes nothing, `..`
  // pops what came before it. Reassigned (not just appended), hence `mut`.
  let mut tail : Array[String] = []
  let mut ups = 0
  for s in path_segments(root) {
    if s == "." {
      continue
    }
    if s == ".." {
      if tail.length() > 0 {
        let shorter : Array[String] = []
        for k in 0..<(tail.length() - 1) {
          shorter.push(tail[k])
        }
        tail = shorter
      } else {
        // Nothing left to pop: the `..` escapes the given path and can only be
        // resolved against the working directory.
        ups = ups + 1
      }
      continue
    }
    tail.push(s)
  }
  if tail.length() > 0 {
    return tail[tail.length() - 1]
  }
  match @env.current_dir() {
    Some(cwd) => {
      let base = path_segments(cwd)
      let keep = if base.length() > ups { base.length() - ups } else { 0 }
      if keep == 0 {
        ""
      } else {
        base[keep - 1]
      }
    }
    None => ""
  }
}

///|
/// Split a path on both separators, dropping empty segments.
fn path_segments(p : String) -> Array[String] {
  let segs = []
  for part in p.split("/").to_array() {
    for s in part.to_owned().split("\\").to_array() {
      if s != "" {
        segs.push(s.to_owned())
      }
    }
  }
  segs
}

///|
/// Reduce to `[A-Za-z0-9._+-]`, replacing everything else with `-`. `+` is
/// kept because MoonBit build versions contain one
/// (`0.1.20260920+7d59c7ec9`) and it is legal in a path on every platform.
fn slug(s : String) -> String {
  let buf = StringBuilder()
  let mut last_dash = false
  for c in s {
    let ok = (c >= 'a' && c <= 'z') ||
      (c >= 'A' && c <= 'Z') ||
      (c >= '0' && c <= '9') ||
      c == '.' ||
      c == '-' ||
      c == '_' ||
      c == '+'
    if ok {
      buf.write_char(c)
      last_dash = false
    } else if !last_dash {
      // Collapse a run so `..\\_mbcore` becomes `..-mbcore`, not `..-_-mbcore`.
      buf.write_char('-')
      last_dash = true
    }
  }
  let out = buf.to_string()
  if out == "" {
    return "target"
  }
  // A stem beginning with `.` is a DOTFILE on Linux and macOS: `ls` will not
  // list it, and an artifact whose whole purpose is to be found again later
  // is worth marking rather than hiding. Slicing the first CHARACTER is safe
  // here because the stem is ASCII by construction — everything else was
  // replaced with `-` by the loop above.
  if out[0:1].to_owned() == "." {
    "_" + out
  } else {
    out
  }
}

///|
/// Collect the provenance for a target whose source has already been located
/// at `root`.
///
/// The version comes from the coordinate when the caller named one, and
/// otherwise from the target's own `moon.mod` — a bare path still declares a
/// version, and it is the one thing that distinguishes today's tree from
/// last week's. A missing or unreadable `moon.mod` is normal, not an error, so
/// it is read quietly and reported as `""`.
pub async fn provenance_for(target : String, root : String) -> ScanProvenance {
  let version = if is_coordinate(target) {
    let (_, ver) = split_coord(target)
    ver
  } else {
    // `moon.mod` first, `moon.mod.json` second. The two are alternative
    // spellings of the same fact, so exactly one is taken — reading both and
    // concatenating would print two versions for one target.
    let a = moon_mod_version(read_quietly(join_path(root, "moon.mod")))
    if a != "" {
      a
    } else {
      moon_mod_version(read_quietly(join_path(root, "moon.mod.json")))
    }
  }
  ScanProvenance::{ target, version, scanned_at: stamp_utc(@async.now()), }
}

///|
fn join_path(root : String, leaf : String) -> String {
  if root == "" {
    return leaf
  }
  // No indexing: string slicing is by BYTE and a path may hold a multi-byte
  // character, so the last character is taken by iteration instead.
  let mut last = '/'
  for c in root {
    last = c
  }
  if last == '/' || last == '\\' {
    root + leaf
  } else {
    root + "/" + leaf
  }
}

///|
/// Read a file, or return `""`. Unlike `read_or` this does not print: a tree
/// with no `moon.mod` is a normal thing to scan, not a file that failed.
async fn read_quietly(p : String) -> String {
  let data = @fs.read_file(p) catch { _ => return "" }
  data.text() catch {
    _ => return ""
  }
}
