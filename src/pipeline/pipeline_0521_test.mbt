// pipeline_0521_test.mbt -- the ADEQUACY DENOMINATOR, at the level of the
// pipeline result.
//
// 0521. `n_unchecked` was printed for eight releases with no scale: "12 calls
// were not checked" is reassuring on a tree with 20,000 call sites and damning
// on one with 20, and the output could not tell the reader which. The fix is a
// denominator (`n_calls`) and a numerator (`n_checked`).
//
// THE HARD PART IS NOT ADDING TWO COUNTERS, and these tests are mostly about
// it. A call in a block's TAIL position is typed twice -- once when the walk
// types the block's statements, once as the block's tail, where the hint is
// needed to check the returned value. Counted naively, every tail call lands in
// the denominator twice and nowhere in the numerator, so the reported adequacy
// would depend on WHERE a program's calls happened to sit rather than on how
// many of them the lens verified.
//
// The counters are therefore gated on `Infer::mark_site`, which recognises the
// second visit of one node by its span. These tests pin the site counts and,
// in the first one, the visit/site gap that motivated the gate.

///|
/// THE REGRESSION GUARD for the whole increment: `{ f() }` has ONE call site.
///
/// Measured 2026-11-07, before the gate, on this exact source: `n_calls` was 2.
/// The body is a single-expression block, so `f()` is both the block's only
/// statement and its tail, and the type lens types it in both passes. A count
/// of 1 here is the whole difference between "the share of call sites this lens
/// verified" and "the share of visits it happened to verify".
test "a call in a block's tail is ONE site, not two" {
  let src = "fn f() -> Unit {\n}\n\nfn main() -> Unit {\n  f()\n}\n"
  let r = @pipeline.run(src, "u.mbt", empty_iface())
  assert_eq(r.n_calls, 1)
  assert_eq(r.n_checked, 1)
}

///|
/// And two calls are two sites, with the tail one still counted once. The
/// second `f()` sits in tail position and is typed twice; the first is an
/// ordinary statement and is typed once. A visit-based count would say 3.
test "two calls are two sites even when one of them is the tail" {
  let src = "fn f() -> Unit {\n}\n\nfn main() -> Unit {\n  f()\n  f()\n}\n"
  let r = @pipeline.run(src, "u.mbt", empty_iface())
  assert_eq(r.n_calls, 2)
  assert_eq(r.n_checked, 2)
}

///|
/// A callee the lens could not resolve is a SITE it visited and did NOT verify.
/// `ignore` is not in the builtins the type lens carries a signature for, so
/// the call is counted in the denominator and in neither the checked nor the
/// unchecked numerator -- it is the third class, and `n_calls - n_checked` is
/// where it shows up.
test "a call to a name with no binding is a site that was not verified" {
  let src = "fn main() -> Unit {\n  let x = 1\n  ignore(x)\n}\n"
  let r = @pipeline.run(src, "u.mbt", empty_iface())
  assert_eq(r.n_calls, 1)
  assert_eq(r.n_checked, 0)
  // It is NOT counted as unchecked either: `unchecked` is the type lens saying
  // "this call is real and I never read its signature", and a name with no
  // binding is a different claim, made by UndefinedName.
  assert_eq(r.n_unchecked, 0)
}

///|
/// THE TWO BASES ARE DIFFERENT, and this fixture is where they visibly diverge.
///
/// `helper` is known only by NAME from another package's `.mbti`, so the call
/// is real and its signature was never read: `n_unchecked` counts it. `ignore`
/// has no binding at all: `n_calls` counts it without any numerator.
///
/// Measured 2026-11-07: n_calls=2, n_checked=0, n_unchecked=1. `n_calls` is
/// SITE-based and `n_unchecked` is VISIT-based (0507's counter, kept for the
/// reason its own doc gives), so `n_calls - n_checked - n_unchecked` is NOT the
/// count of the third class -- it is a subtraction between two different units.
test "a name-only callee is unchecked; an unresolved callee is neither" {
  let tab = @core.IfaceSymTab::empty()
  tab.add_value("helper")
  let src = "fn main() -> Unit {\n  let x = helper(1)\n  ignore(x)\n}\n"
  let r = @pipeline.run(src, "u.mbt", tab)
  assert_eq(r.n_calls, 2)
  assert_eq(r.n_checked, 0)
  assert_eq(r.n_unchecked, 1)
}

///|
/// A METHOD call is a site the lens reached and could not verify: it has the
/// method's name and not its parameter list. `s.length()` and `ignore(n)` are
/// two sites, and neither was checked.
///
/// The zero has to be distinguishable from "this analyzer does not count call
/// sites at all", which is why `n_calls` is asserted as well as `n_checked`.
test "a method call is a site the lens could not verify" {
  let src = "fn main() -> Unit {\n  let s = \"abc\"\n  let n = s.length()\n  ignore(n)\n}\n"
  let r = @pipeline.run(src, "u.mbt", empty_iface())
  assert_eq(r.n_calls, 2)
  assert_eq(r.n_checked, 0)
  assert_eq(r.n_unchecked, 1)
}

///|
/// An unresolved call is still ONE site, even when it is the only call and
/// nothing about it could be verified. The scan renders that as a 0.0% share
/// and NOT as `n/a`: there was a call site, and it was not checked, which is a
/// different statement from "there was nothing to check".
test "an unresolved call is still one site" {
  let src = "fn main() -> Unit {\n  let x = 1\n  let y = x + 1\n  ignore(y - 2)\n}\n"
  let r = @pipeline.run(src, "u.mbt", empty_iface())
  assert_eq(r.n_calls, 1)
  assert_eq(r.n_checked, 0)
}

///|
/// And the actual empty case: a body with no call at all reports 0 sites, so
/// the scan's `n/a` is reached from a real measurement rather than from a
/// counter that never ran.
test "a body with no call at all reports zero sites" {
  let src = "fn main() -> Unit {\n  let x = 1\n  let y = x + 1\n}\n"
  let r = @pipeline.run(src, "u.mbt", empty_iface())
  assert_eq(r.n_calls, 0)
  assert_eq(r.n_checked, 0)
}
