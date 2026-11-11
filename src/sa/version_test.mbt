// version_test.mbt: the newest version is the newest BY ITS NUMBERS.
//
// THE CASE THAT BROKE IT, MEASURED. These are the directory names the real
// fetches left behind on this machine, in the order `readdir` returned them:
//
//   .repos/riantr/moonbit_static_analysis/  ->  0.3.4 0.3.5 0.4.27 0.4.45 0.4.5 0.4.7
//
// The old resolver took the LAST entry, so it chose 0.4.7 and analysed a
// thirty-eight-release-old package while reporting that it had analysed the
// newest one. Only the numbers say 0.4.45.

///|
test "0554: the newest version is the newest by its numbers, not by the readdir order" {
  let on_disk = ["0.3.4", "0.3.5", "0.4.27", "0.4.45", "0.4.5", "0.4.7"]
  assert_eq(@sa.newest_version(on_disk), "0.4.45")
}

///|
test "0554: a lexicographic maximum would have been wrong too" {
  // "0.4.9" sorts ABOVE "0.4.45" as a string, and 9 is BELOW 45 as a number.
  // So a resolver that compared the spellings would pick the wrong one here
  // as well -- which is why the comparison is on the numbers.
  assert_eq(@sa.newest_version(["0.4.9", "0.4.45"]), "0.4.45")
  assert_eq(@sa.newest_version(["0.4.45", "0.4.9"]), "0.4.45")
}

///|
test "0554: more components make a newer version" {
  assert_eq(@sa.newest_version(["0.4", "0.4.5"]), "0.4.5")
  assert_eq(@sa.newest_version(["0.4.45", "0.4.5"]), "0.4.45")
  assert_eq(@sa.newest_version(["0.1.3", "0.1.2", "0.1.10"]), "0.1.10")
}

///|
test "0554: one version is the newest version" {
  assert_eq(@sa.newest_version(["0.1.3"]), "0.1.3")
}

///|
test "0554: an empty list has no newest version" {
  assert_eq(@sa.newest_version([]), "")
}

///|
test "0554: a name that is not a version loses to every version" {
  assert_eq(@sa.newest_version(["latest", "0.4.45"]), "0.4.45")
  assert_eq(@sa.newest_version(["0.4.45", "latest"]), "0.4.45")
}
