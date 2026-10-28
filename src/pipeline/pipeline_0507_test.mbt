// pipeline_0507_test.mbt -- the UNCHECKED-CALL DISCLOSURE, at the level of the
// pipeline result.
//
// 0507. The analyzer checks a call's arity and its argument types ONLY when it
// has read the callee's signature. A `.mbti` gives a name and never a
// parameter list, a method's signature is not in the source at all, and a `..`
// chain link is a method call wearing different syntax.
//
// Until 0507 it said NOTHING about any of them, so "I could not check this"
// and "there is nothing to report" were the same output. A file with no
// findings and four hundred unchecked calls printed exactly like a clean file,
// and a reader of the output had no way to tell the two apart.
//
// The count travels with the pipeline result so the SCAN can disclose it. It
// is NOT a finding count and it is NOT part of the SUMMARY's sum -- an
// unchecked call is not a defect.
//
// These three tests pin the three cases: a call whose signature the lens never
// saw, a call to a name it knows only by NAME, and a file with nothing to
// check at all.

///|
/// A METHOD call. The analyzer has the method's name and not its parameter
/// list, so the call's arguments went unverified -- the same reason the
/// name-only case below does.
test "the type lens discloses a method call it could not check" {
  let src = "fn main() -> Unit {\n  let s = \"abc\"\n  let n = s.length()\n  ignore(n)\n}\n"
  let r = @pipeline.run(src, "u.mbt", empty_iface())
  assert_eq(r.n_unchecked, 1)
}

///|
/// A call to a name known only by NAME. The `.mbti` of another package declares
/// the name AND its parameters -- the parser reads the parameter list
/// (`src/moonfiles/moonfiles.mbt:917-931`) and the cross-file symbol table is
/// what drops it -- so the analyzer resolves the name, types the result as
/// unknown, and checks neither the arity nor the argument types -- deliberately,
/// because asserting something about a signature it never read is the one claim
/// this lens cannot make. Measured 2026-10-28; see the 0508 block of
/// `_verify/NARRATIVE.md`.
///
/// The name is NOT reported as undefined either: it IS a name, and the
/// binding exists. The two facts are different, and the disclosure is what
/// tells them apart.
test "the type lens discloses a call to a name it knows only by NAME" {
  let tab = @core.IfaceSymTab::empty()
  tab.add_value("helper")
  let src = "fn main() -> Unit {\n  let x = helper(1)\n  ignore(x)\n}\n"
  let r = @pipeline.run(src, "u.mbt", tab)
  assert_eq(r.n_unchecked, 1)
  assert_eq(r.reports.length(), 0)
}

///|
/// And a file with nothing to check says ZERO. The number has to be there in
/// both cases, or "no unchecked calls" would be indistinguishable from "this
/// analyzer does not count them" -- which is the silence 0507 exists to end.
test "a file with nothing to check discloses zero unchecked calls" {
  let src = "fn main() -> Unit {\n  let x = 1\n  ignore(x)\n}\n"
  let r = @pipeline.run(src, "u.mbt", empty_iface())
  assert_eq(r.n_unchecked, 0)
}
