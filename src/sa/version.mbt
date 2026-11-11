// version.mbt: which of the versions in a directory is the newest.
//
// THE DEFECT THIS FILE EXISTS FOR. `locate` resolved a bare coordinate to a
// directory by taking the LAST entry of `readdir` and calling it "the newest".
// `readdir` returns the order the entries sit in the directory, which is
// neither numeric nor alphabetical -- it is whatever order the filesystem
// hands them over. MEASURED on the directories the real fetches left behind
// on this machine:
//
//   .repos/riantr/moonbit_static_analysis/  ->  0.3.4 0.3.5 0.4.27 0.4.45 0.4.5 0.4.7
//
// The last entry is 0.4.7. So `moonx riantr/moonbit_static_analysis@latest
// riantr/moonbit_static_analysis@latest` fetched 0.4.45 and then ANALYSED
// 0.4.7 -- thirty-eight releases behind, and a different codebase.
//
// A lexicographic maximum would have been just as wrong: "0.4.9" sorts ABOVE
// "0.4.45" as a string, and 9 is BELOW 45 as a number. The numbers have to be
// compared AS NUMBERS, and that is what this file does.
//
// The defect was invisible to every gate in this tree, because no gate ever
// resolved a coordinate to a directory: the gates scan PATHS. It was found by
// running the published analyzer the way the README says to run it.

///|
/// The newest of `names`, compared by the numbers in the version and not by
/// its spelling. Returns "" when the list is empty.
///
/// A name that is not a version at all loses to every version: it contributes
/// -1 to the comparison, so a stray directory inside `.repos` cannot win.
pub fn newest_version(names : Array[String]) -> String {
  let mut best = ""
  for name in names {
    if best == "" {
      best = name
      continue
    }
    if version_gt(name, best) {
      best = name
    }
  }
  best
}

///|
/// True when version `a` is NEWER than version `b`.
///
/// The components are compared one at a time, as numbers. When one version
/// carries more components than the other, the longer one is newer: 0.4.5 is
/// newer than 0.4, and 0.4.45 is newer than 0.4.
fn version_gt(a : String, b : String) -> Bool {
  let pa = version_parts(a)
  let pb = version_parts(b)
  let mut i = 0
  while i < pa.length() && i < pb.length() {
    let x = pa[i]
    let y = pb[i]
    if x != y {
      return x > y
    }
    i = i + 1
  }
  pa.length() > pb.length()
}

///|
/// The numeric components of a version string, in order. A component that
/// carries something other than digits contributes -1.
///
/// `0.4.45` is [0, 4, 45]; `0.4` is [0, 4]; `latest` is [-1].
///
/// Every read of a local here sits at STATEMENT level on purpose: an `if` in
/// EXPRESSION position is outside the subset this analyzer analyses, so a read
/// hidden in one is invisible to the analyzer's own audit -- and this tree
/// audits itself.
fn version_parts(v : String) -> Array[Int32] {
  let parts : Array[Int32] = []
  let mut cur = 0
  let mut named = false
  for c in v {
    if c == '.' {
      parts.push(cur)
      cur = 0
      named = false
      continue
    }
    let d = c.to_int() - '0'.to_int()
    if d < 0 || d > 9 {
      named = true
      cur = -1
      continue
    }
    if named {
      continue
    }
    cur = cur * 10 + d
  }
  parts.push(cur)
  parts
}
