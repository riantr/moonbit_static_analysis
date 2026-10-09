// test: provenance — the version and the timestamp a scan artifact is named
// and headed with.
//
// The date arithmetic is the part that can be quietly wrong: a stamp that is
// off by a day still LOOKS like a timestamp, and nothing downstream would ever
// notice. So `stamp_utc` is pinned against dates whose answers are not in
// dispute — the epoch itself, a leap day, a year boundary, a month boundary,
// and the exact instant measured off a real wasm run — rather than trusted.
//
// The naming is pinned for the other reason: a name that quietly drops the
// version it failed to find reads exactly like a name where the version was
// `0`, so "unknown" must be explicit.

///|
fn p(name : String, version : String, stamp : String) -> @sa.ScanProvenance {
  @sa.ScanProvenance::{ target: name, version, scanned_at: stamp, }
}

///|
test "the epoch itself" {
  // 1970-01-01T00:00:00Z is the definition, so a wrong answer here is a wrong
  // algorithm rather than a wrong constant.
  assert_eq(@sa.stamp_utc(0L), "19700101T000000Z")
}

///|
test "a leap day" {
  // 2024-02-29T12:34:56Z. 2024 is a leap year under the 400-year rule.
  assert_eq(@sa.stamp_utc(1709210096000L), "20240229T123456Z")
}

///|
test "a year boundary and a month boundary" {
  assert_eq(@sa.stamp_utc(1704067199000L), "20231231T235959Z")
  assert_eq(@sa.stamp_utc(1704067200000L), "20240101T000000Z")
  assert_eq(@sa.stamp_utc(1704067500000L), "20240101T000500Z")
}

///|
test "the instant a real wasm run reported" {
  // Measured, not invented: `moonbitlang/async::now()` returned
  // 1791522911114 on a wasm run whose wall clock was 2026-10-09 05:15 UTC.
  assert_eq(@sa.stamp_utc(1791522911114L), "20261009T051511Z")
}

///|
test "the century leap rule, in both directions" {
  // The rule is the one a naive `y / 4` implementation gets wrong, and it is
  // what the 400-year era arithmetic exists to get right. 2000 IS a leap year
  // (divisible by 400); 2100 is NOT (divisible by 100, not by 400).
  assert_eq(@sa.stamp_utc(946684800000L), "20000101T000000Z")
  // 2100-03-01 is 47541 days after the epoch; 2100-02-28 is the day before it,
  // and that day exists at all only because 2100 is not a leap year.
  assert_eq(@sa.stamp_utc(4107542400000L), "21000301T000000Z")
  assert_eq(@sa.stamp_utc(4107542400000L - 86400000L), "21000228T000000Z")
}

///|
test "a time before the epoch is refused rather than dated" {
  // 1900-01-01 is a real date this algorithm CAN compute, and `stamp_utc`
  // still refuses it: a scan that claims to have run before the epoch is a
  // clock that is wrong, and printing a confident date would hide that.
  assert_eq(@sa.stamp_utc(-1L), "unknown")
  assert_eq(@sa.stamp_utc(-2208988800000L), "unknown")
}

///|
test "every field of a stamp is fixed width" {
  // A filename with a variable-width field does not sort chronologically, and
  // the whole reason the stamp is in the name is so a directory of scans sorts
  // by time.
  let s = @sa.stamp_utc(1L)
  assert_eq(s.length(), 16)
  assert_eq(s[0:4].to_owned(), "1970")
  assert_eq(s[8:9].to_owned(), "T")
  assert_eq(s[15:16].to_owned(), "Z")
}

///|
test "a moon.mod version is read" {
  let src = "// module: someone/thing\nname = \"someone/thing\"\n\nversion = \"1.2.3\"\n"
  assert_eq(@sa.moon_mod_version(src), "1.2.3")
}

///|
test "a moon.mod.json version is read too" {
  // Both spellings exist in the field: moon.mod.json carries a deprecation
  // notice pointing at moon.mod, so trees have one or the other and a scanner
  // that understood only one would call half of them version-less.
  let src = "{\n  \"name\": \"someone/thing\",\n  \"version\": \"4.5.6\",\n  \"source\": \"src\"\n}\n"
  assert_eq(@sa.moon_mod_version(src), "4.5.6")
}

///|
test "a build version with a plus sign survives" {
  // The real shape of a moonbitlang/core version.
  assert_eq(
    @sa.moon_mod_version(
      "name = \"moonbitlang/core\"\nversion = \"0.1.20260920+7d59c7ec9\"\n",
    ),
    "0.1.20260920+7d59c7ec9",
  )
}

///|
test "a commented-out version is not a version" {
  assert_eq(
    @sa.moon_mod_version("// version = \"9.9.9\"\nname = \"x/y\"\n"),
    "",
  )
}

///|
test "a different version-shaped key is not the version" {
  // `min_version` must not be read as `version`: the whole test of this
  // function is whether the key is the WHOLE first token of the line.
  assert_eq(@sa.moon_mod_version("min_version = \"1.0\"\nname = \"x/y\"\n"), "")
}

///|
test "a tree with no version yields an empty one" {
  assert_eq(@sa.moon_mod_version("name = \"x/y\"\nsource = \"src\"\n"), "")
}

///|
test "a coordinate is named by its module" {
  assert_eq(
    @sa.scan_artifact_name(
      p("moonbitlang/core", "0.1.20260920+7d59c7ec9", "20261009T051511Z"),
      "",
    ),
    "moonbitlang-core-0.1.20260920+7d59c7ec9_20261009T051511Z.mmd",
  )
}

///|
test "a coordinate's inline version is not printed twice" {
  // The target string may already carry `@version`. Printing it in the label
  // AND as the version segment would make the name say it twice.
  assert_eq(
    @sa.scan_artifact_name(
      p("moonbitlang/core@0.4.4", "0.4.4", "20261009T051511Z"),
      "",
    ),
    "moonbitlang-core-0.4.4_20261009T051511Z.mmd",
  )
}

///|
test "a path is named by its RESOLVED directory, not by what was typed" {
  // Scanning `.` is the most ordinary invocation there is. Naming the
  // artifact after the string the caller passed would produce `_.mmd`, so `.`
  // and `..` are resolved against the working directory instead.
  assert_eq(
    @sa.scan_artifact_name(
      p(".", "0.4.4", "20261009T052045Z"),
      "D:/work/deepseek/moonbit_static_analysis",
    ),
    "moonbit_static_analysis-0.4.4_20261009T052045Z.mmd",
  )
  // A trailing separator and a redundant `.` change nothing.
  assert_eq(
    @sa.scan_artifact_name(p("./tree/", "1.0", "20261009T052045Z"), "./tree/"),
    "tree-1.0_20261009T052045Z.mmd",
  )
  // A `..` inside the path pops the segment before it, the way a filesystem
  // does — `a/b/..` IS `a`, so naming the artifact `b` would be wrong. This
  // one was wrong in the first implementation and the test caught it.
  assert_eq(
    @sa.scan_artifact_name(
      p("x", "1.0", "20261009T052045Z"),
      "D:/work/deepseek/moonbit_static_analysis/..",
    ),
    "deepseek-1.0_20261009T052045Z.mmd",
  )
}

///|
test "a Windows path becomes a legal filename" {
  // `< > : " / \ | ? *` are illegal in a Windows path and a coordinate is
  // full of `/`, so this is not cosmetic. The `_` inside the segment is
  // LEGAL in a filename and is kept.
  let name = @sa.scan_artifact_name(
    p("..\\_mbcore", "0.1.20260920", "20261009T051511Z"),
    "..\\_mbcore",
  )
  assert_eq(name, "_mbcore-0.1.20260920_20261009T051511Z.mmd")
  for c in name {
    assert_true(
      c != '/' &&
      c != '\\' &&
      c != ':' &&
      c != '*' &&
      c != '?' &&
      c != '"' &&
      c != '<' &&
      c != '>' &&
      c != '|',
    )
  }
}

///|
test "a name is never a dotfile" {
  // A name starting with `.` is invisible to `ls` on Linux and macOS, and an
  // artifact nobody can list is not an artifact anybody will find again.
  let name = @sa.scan_artifact_name(
    p(".hidden", "1.0", "20261009T051511Z"),
    ".hidden",
  )
  assert_false(name.has_prefix("."))
  assert_eq(name, "_.hidden-1.0_20261009T051511Z.mmd")
}

///|
test "a name that could not determine a version says unknown" {
  // Dropping the segment would produce `tree_20261009T051511Z.mmd`, which is
  // indistinguishable from a name where the version WAS determined. The target
  // is path-shaped on purpose: `some/tree` is a valid COORDINATE and takes the
  // coordinate branch, which is a different test.
  assert_eq(
    @sa.scan_artifact_name(p("..\\tree", "", "20261009T051511Z"), "..\\tree"),
    "tree-unknown_20261009T051511Z.mmd",
  )
  assert_eq(
    @sa.scan_artifact_name(p("..\\tree", "1.0", ""), "..\\tree"),
    "tree-1.0_unknown.mmd",
  )
}

///|
test "an empty target still yields a usable name" {
  assert_eq(
    @sa.scan_artifact_name(p("", "1.0", "20261009T051511Z"), ""),
    "target-1.0_20261009T051511Z.mmd",
  )
}

///|
test "describe states every field, with unknown where missing" {
  assert_eq(
    @sa.ScanProvenance::describe(p("a/b", "1.0", "20261009T051511Z")),
    "target=a/b version=1.0 scanned_at=20261009T051511Z",
  )
  assert_true(
    @sa.ScanProvenance::describe(p("a/b", "", "")).contains("version=unknown"),
  )
}

///|
test "the name builder is shown failing on what it must catch" {
  // Without this the slug could rot into returning the label unchanged and
  // every test above would still pass on a target with no illegal character.
  let name = @sa.scan_artifact_name(
    p("a/b:c*d?e\"f<g>h|i", "1.0", "20261009T051511Z"),
    "",
  )
  assert_false(name.contains("/"))
  assert_false(name.contains(":"))
  assert_false(name.contains("*"))
  assert_false(name.contains("?"))
  assert_false(name.contains("\""))
  assert_false(name.contains("<"))
  assert_false(name.contains(">"))
  assert_false(name.contains("|"))
}
