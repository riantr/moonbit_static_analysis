// pipeline_0524_test.mbt -- THE MSA-011 AUDIT against the V&V deck's three-way
// distinction (p.22):
//
//   unreachable code  never executed at all
//   dead code         "executed, but irrelevant" -- `X := X+1; X := 7; X := X+Y`
//   infeasible path   D[P] = { } -- every statement individually reachable, no
//                     input executes the path (p.20, p.57)
//
// BEFORE THIS AUDIT the family's claim was one sentence -- "a statement follows
// one whose flow has already left the block" -- and the deck's three cases were
// not separated anywhere: MSA-011 covered the first, MSA-013 (0522) covers the
// third, and the second was covered by NOBODY, which is the kind of gap a reader
// fills with an optimistic assumption. These tests pin which is which, and they
// pin ONE measured defect rather than hiding it.

///|
/// Count findings of one family by its stable id.
fn count0524(rs : Array[@report.Report], id : String) -> Int32 {
  let mut n = 0
  for r in rs {
    if r.family.id() == id {
      n += 1
    }
  }
  n
}

///|
/// THE SOUND CASE, and the control for the test below: an UNCONDITIONAL
/// `return` in the block itself makes everything after it unreachable. No input
/// can reach line 3, so no semantics is needed and the claim is high confidence.
test "0524: a statement after an unconditional return is unreachable" {
  let src = "fn f() -> Int {\n  return 1\n  return 2\n}\nlet x = f()\n"
  let r = @pipeline.run(src, "u.mbt", empty_iface())
  assert_eq(count0524(r.reports, "MSA-011"), 1)
  // and it is anchored on line 3, the statement that cannot run
  let mut line = 0
  for rep in r.reports {
    if rep.family.id() == "MSA-011" {
      line = rep.span.start.line
    }
  }
  assert_eq(line, 3)
}

///|
/// THE MEASURED DEFECT. This is a FALSE FINDING and it is pinned as one.
///
///     fn f(c : Bool) -> Int { if c { return 1 } ; return 2 }
///     let x = f(true)
///
/// `f(false)` returns 2, so line 5 is reachable. The behavioral lens executed `f`
/// with `c` bound to the CALL SITE's `true`, took the then-branch, and found the
/// flow already `FReturn` at `return 2`.
///
/// THIS TEST ASSERTS THE WRONG ANSWER ON PURPOSE. It is the audit's record: the
/// over-report exists, it is anchored on a line the next caller runs, and the
/// family's `excluded` contract now says so. WHEN THIS GOES RED, the defect has
/// been fixed -- delete this test, update NARRATIVE 0524, and remove the
/// `excluded` clause that names it. A defect that is only described in prose is
/// a defect nobody notices being fixed or re-introduced.
test "0524: a caller's argument can make MSA-011 over-report (KNOWN false positive)" {
  let src = "fn f(c : Bool) -> Int {\n  if c {\n    return 1\n  }\n  return 2\n}\nlet x = f(true)\n"
  let r = @pipeline.run(src, "u.mbt", empty_iface())
  assert_eq(count0524(r.reports, "MSA-011"), 1)
}

///|
/// THE SECOND CASE IS NOBODY'S. "Dead code" in the deck's sense -- executed, but
/// its result is overwritten before any read -- is reported by no family:
///
///     fn g() -> Int { let mut x = 1 ; x = 7 ; x + 1 }
///
/// The first value of `x` is dead. `UnusedLocal` does not fire, because `x` IS
/// read; `Unreachable` does not fire, because every statement runs. Pinning the
/// ZERO is what stops a future reader from assuming one of the twelve families
/// covers it.
test "0524: dead code, in the deck's sense, is reported by no family" {
  let src = "fn g() -> Int {\n  let mut x = 1\n  x = 7\n  x + 1\n}\nlet y = g()\n"
  let r = @pipeline.run(src, "u.mbt", empty_iface())
  assert_eq(r.reports.length(), 0)
}

///|
/// THE VOCABULARY. Three different situations, three different sentences, and
/// none of the three may borrow another's word:
///
///   MSA-011 says "unreachable code"      and must not say dead / infeasible
///   MSA-013 says "empty domain, D[P]"    and must not say unreachable code
///
/// A reader who is told "unreachable" when the tool means "infeasible" has been
/// told the statement is not in the compiled program, which is a different and
/// stronger claim.
test "0524: the three cases do not share vocabulary" {
  let unreach = @pipeline.run(
    "fn f() -> Int {\n  return 1\n  return 2\n}\nlet x = f()\n",
    "u.mbt",
    empty_iface(),
  )
  let infeasible = @pipeline.run(
    "fn h(x : Int) -> Unit {\n  if x > 5 {\n    if x < 3 {\n      println(\"never\")\n    }\n  }\n}\n",
    "u.mbt",
    empty_iface(),
  )
  for rep in unreach.reports {
    if rep.family.id() == "MSA-011" {
      assert_false(rep.message.contains("dead"))
      assert_false(rep.message.contains("infeasible"))
      assert_false(rep.message.contains("D[P]"))
    }
  }
  for rep in infeasible.reports {
    if rep.family.id() == "MSA-013" {
      assert_false(rep.message.contains("unreachable"))
      assert_true(rep.message.contains("D[P]"))
    }
  }
}
