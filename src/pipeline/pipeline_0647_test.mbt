//| pipeline_0647_test.mbt -- THE RINGS THE INTERPRETER NEVER DREW: a mutual
//| recursion, a self-loop beside one, a three-node ring, and the return type
//| a cut converges on.
//|
//| WHY THESE ROWS ARE HERE. 0541 built the call-context ledger and pinned it
//| against ONE recursive shape: a function that calls ITSELF with the same
//| abstract argument (`fn r(n : Int) -> Int { r(n) }`). That row is a SELF-loop.
//| Everything the ledger says about recursion was therefore read off a
//| one-function ring, and the shapes between the extremes were not measured:
//|
//|   - a MUTUAL recursion (`a` calls `b`, `b` calls `a`);
//|   - a SELF-loop living BESIDE a mutual cycle in the same program;
//|   - a ring of THREE functions;
//|   - a mutual cycle entered from TWO call strings;
//|   - an edge leaving the cycle.
//|
//| THE FIRST GAP IS THE ONE THAT MATTERS MOST, because `cuts` ALONE CANNOT TELL
//| A SELF-LOOP FROM A MUTUAL CYCLE. Both are one cut. The ledger distinguishes
//| them, but by `exec` and `sig`, and nothing published that fact: the row
//| below that claims "one cut" would be equally true of a program with one
//| function in it. A reader who had only the self-loop row could not have
//| written it.
//|
//| EVERY NUMBER BELOW IS COUNTED BY HAND, from the program text, and then
//| asserted -- and every one of them was MEASURED first, by a probe that
//| printed the ledger, so that the hand count and the machine count had to
//| agree before either was published.
//|
//| ONE THING IS DELIBERATELY NOT ASSERTED: the ORDER of `r.sigs`. The list is
//| built by `summarize_sigs` and sorted, but the sort is over a list of
//| strings whose comparison this increment did not pin down, and an assertion
//| about that order would be a statement about the engine's ordering rather
//| than about the program. The rows below ask whether a signature is PRESENT.
//|
//| AND THE NUMBERS ARE ABOUT THE REPORT PASS. 0541 settled that the dry pass
//| is not counted: the ledger is fed by the report pass alone, so an
//| implementation that forgot the flag would report exactly TWICE these
//| figures -- which is why these are equalities and not bounds.

///|
/// A MUTUAL RECURSION IS TWO SIGNATURES AND ONE CUT.
///
///     fn a(n : Int) -> Int { b(n) }
///     fn b(n : Int) -> Int { a(n) }
///     let z = a(1)
///
/// The walk: `a(1)` is a new signature, so `a`'s body runs (one execution).
/// Its body calls `b(1)`, a second new signature, so `b`'s body runs (two
/// executions). `b`'s body calls `a(1)` -- and `a(int)` is ALREADY IN PROGRESS,
/// so this arrival is CUT: the body does not run a third time.
///
/// So the counts are: TWO executions, TWO signatures, TWO call strings, and
/// ONE cut. The cut is the arrival of `a` inside `b`; the two executions are
/// `a` and `b`.
test "0647: a mutual recursion is TWO signatures and ONE cut" {
  let src = "fn a(n : Int) -> Int {\n  b(n)\n}\nfn b(n : Int) -> Int {\n  a(n)\n}\nlet z = a(1)\n"
  let r = @pipeline.run_tracked(src, "u.mbt", empty_iface(), false)
  assert_eq(r.ctx.exec, 2)
  assert_eq(r.ctx.sig, 2)
  assert_eq(r.ctx.context, 2)
  assert_eq(r.ctx.shared, 0)
  // ONE cut -- the ring closes once, at the third arrival.
  assert_eq(r.ctx.cuts, 1)
  // AND THE RING IS TWO FRAMES DEEP: `a` at depth 1 (the module frame), `b` at
  // depth 2 (module frame + `a`). The cut does not add a frame -- it returns
  // before the ledger is written.
  assert_eq(r.ctx.depth, 2)
  // AND BOTH SIGNATURES ARE IN THE SUMMARY.
  assert_eq(r.sigs.length(), 2)
  assert_true(r.sigs.contains("a(int) -> int"))
  assert_true(r.sigs.contains("b(int) -> int"))
}

///|
/// THE CONTROL, and it is the shape 0541 already pinned -- run again here so
/// the two rows sit side by side.
///
///     fn r(n : Int) -> Int { r(n) }
///     let z = r(1)
///
/// One execution, one signature, one call string, one cut, depth 1.
///
/// COMPARE IT WITH THE ROW ABOVE. The `cuts` are EQUAL -- one each -- so a
/// ledger that reported only `cuts` would describe a self-loop and a mutual
/// recursion with the same words. What tells them apart is `exec` and `sig`:
/// ONE against TWO. That is the fact this increment pins, and it is why
/// "the analysis cut once" is not a statement about the shape of the
/// recursion.
test "0647 control: a self-recursion is ONE signature, and the same ONE cut" {
  let src = "fn r(n : Int) -> Int {\n  r(n)\n}\nlet z = r(1)\n"
  let r = @pipeline.run_tracked(src, "u.mbt", empty_iface(), false)
  assert_eq(r.ctx.exec, 1)
  assert_eq(r.ctx.sig, 1)
  assert_eq(r.ctx.context, 1)
  assert_eq(r.ctx.cuts, 1)
  assert_eq(r.ctx.depth, 1)
  assert_eq(r.sigs.length(), 1)
  assert_true(r.sigs.contains("r(int) -> int"))
}

///|
/// THE CUT CONVERGES ON THE DECLARED RETURN TYPE, and this is the only place
/// `cycle_ret` is observable.
///
///     fn a(n : Int) -> Int { b(n) }
///     fn b(n : Int) -> Int { a(n) }
///
/// The arrival of `a` inside `b` returns the PARTIAL for `a(int)`. There is no
/// partial yet, so the analysis writes one: `def.cycle_ret`. With a declared
/// return type, `cycle_ret` is `AType("int")` -- so the partial is "int", and
/// the value that comes back around the ring is "int".
///
/// WITHOUT A DECLARED RETURN TYPE the partial is `AAny` -- the honest answer,
/// because a body with no annotation says only that it returns Unit, and a
/// concrete name would be a claim. So the ring converges on "Any".
///
/// The next row is the control that makes this row mean something.
test "0647: a mutual recursion converges on the declared return type" {
  let declared = "fn a(n : Int) -> Int {\n  b(n)\n}\nfn b(n : Int) -> Int {\n  a(n)\n}\nlet z = a(1)\n"
  let r1 = @pipeline.run_tracked(declared, "u.mbt", empty_iface(), false)
  assert_true(r1.sigs.contains("a(int) -> int"))
  assert_true(r1.sigs.contains("b(int) -> int"))
  // AND WITHOUT THE ANNOTATION THE RING CONVERGES ON "Any".
  let undeclared = "fn a(n : Int) {\n  b(n)\n}\nfn b(n : Int) {\n  a(n)\n}\nlet z = a(1)\n"
  let r2 = @pipeline.run_tracked(undeclared, "u.mbt", empty_iface(), false)
  assert_true(r2.sigs.contains("a(int) -> Any"))
  assert_true(r2.sigs.contains("b(int) -> Any"))
  // AND THE LEDGER IS THE SAME IN BOTH CASES: the cut happens once either way.
  // The return type is a property of the PARTIAL, not of the termination.
  assert_eq(r1.ctx.cuts, r2.ctx.cuts)
}

///|
/// THE CONTROL FOR THE ROW ABOVE, and it is the SAME MISSING ANNOTATION on a
/// function that does NOT recurse.
///
///     fn g(n : Int) { n }
///     let z = g(1)
///
/// Without a declared return type and without recursion, the summary says
/// "int" -- because the body's value was reached, and it was an `int`.
///
/// SO "Any" IN THE ROW ABOVE IS NOT "THE ANNOTATION WAS MISSING". It is the
/// CUT: the recursive body never produced a value of its own, so the only
/// thing the ring could converge on was the partial -- and with no declared
/// type the partial is "Any". A row that asserted only "no annotation gives
/// Any" would be asserting the opposite of the truth.
test "0647 control: a missing return annotation alone does NOT make it Any" {
  let src = "fn g(n : Int) {\n  n\n}\nlet z = g(1)\n"
  let r = @pipeline.run_tracked(src, "u.mbt", empty_iface(), false)
  assert_eq(r.sigs.length(), 1)
  assert_true(r.sigs.contains("g(int) -> int"))
  assert_false(r.sigs.contains("g(int) -> Any"))
}

///|
/// A SELF-LOOP BESIDE A MUTUAL CYCLE: TWO CUTS, and neither ring swallows
/// the other.
///
///     fn s(n : Int) -> Int { s(n) }      <- the self-loop
///     fn a(n : Int) -> Int { b(n) }
///     fn b(n : Int) -> Int { a(n) }      <- the mutual cycle
///     let z = s(1)
///     let w = a(1)
///
/// Two rings, two cuts, and the ledger counts them separately: three
/// executions (s, a, b), three signatures, three call strings.
///
/// The point of the row is that TWO INDEPENDENT CYCLES IN ONE PROGRAM ARE TWO
/// CUTS. An analysis that kept one "have we recursed" bit for the whole
/// program would cut the second ring without cutting the first, or vice
/// versa; and an analysis that cut once PER PROGRAM would report one.
test "0647: a self-loop beside a mutual cycle is TWO cuts" {
  let src = "fn s(n : Int) -> Int {\n  s(n)\n}\nfn a(n : Int) -> Int {\n  b(n)\n}\nfn b(n : Int) -> Int {\n  a(n)\n}\nlet z = s(1)\nlet w = a(1)\n"
  let r = @pipeline.run_tracked(src, "u.mbt", empty_iface(), false)
  assert_eq(r.ctx.exec, 3)
  assert_eq(r.ctx.sig, 3)
  assert_eq(r.ctx.context, 3)
  assert_eq(r.ctx.shared, 0)
  // ONE CUT PER RING.
  assert_eq(r.ctx.cuts, 2)
  assert_eq(r.ctx.depth, 2)
}

///|
/// A RING OF THREE IS ONE CUT, not three.
///
///     fn a(n : Int) -> Int { b(n) }
///     fn b(n : Int) -> Int { c(n) }
///     fn c(n : Int) -> Int { a(n) }
///     let z = a(1)
///
/// Three bodies run (a, b, c) and the FOURTH arrival -- `a` inside `c` -- is
/// the cut. The ring is closed once, at the point where the walk comes back
/// to the signature that is already in progress.
///
/// THE DEPTH IS THE POINT OF THIS ROW: THREE. The self-loop reached depth 1
/// and the mutual cycle reached depth 2; a three-function ring reaches depth
/// 3, because the third body runs inside the second, which runs inside the
/// first. A ring of any length terminates the same way -- at the return to the
/// signature already in progress -- and the depth is what grows with it.
test "0647: a three-function ring is ONE cut, and it is THREE deep" {
  let src = "fn a(n : Int) -> Int {\n  b(n)\n}\nfn b(n : Int) -> Int {\n  c(n)\n}\nfn c(n : Int) -> Int {\n  a(n)\n}\nlet z = a(1)\n"
  let r = @pipeline.run_tracked(src, "u.mbt", empty_iface(), false)
  assert_eq(r.ctx.exec, 3)
  assert_eq(r.ctx.sig, 3)
  assert_eq(r.ctx.context, 3)
  assert_eq(r.ctx.cuts, 1)
  assert_eq(r.ctx.depth, 3)
  assert_eq(r.sigs.length(), 3)
}

///|
/// A MUTUAL CYCLE ENTERED FROM TWO CALL STRINGS IS CUT TWICE.
///
///     fn a(n : Int) -> Int { b(n) }
///     fn b(n : Int) -> Int { a(n) }
///     fn h1() -> Int { a(3) }
///     fn h2() -> Int { a(3) }
///     let p = h1()
///     let q = h2()
///
/// `h1` and `h2` are different call strings, so the cycle is entered twice.
/// The first entry runs `a` and `b` and is cut at the third arrival; the
/// second entry runs them AGAIN -- the in-progress set is per SIGNATURE, not
/// per call string, so the ring is closed again rather than reused -- and is
/// cut again.
///
/// Six executions over four signatures, and the two that are shared (`a` and
/// `b`, each reached from two different call strings) are exactly the ones
/// `shared` counts. This is the row 0541 could not write: its `shared` row
/// had a leaf function reached from two callers, not a cycle reached from two
/// callers.
test "0647: a mutual cycle entered from two call strings is cut TWICE" {
  let src = "fn a(n : Int) -> Int {\n  b(n)\n}\nfn b(n : Int) -> Int {\n  a(n)\n}\nfn h1() -> Int {\n  a(3)\n}\nfn h2() -> Int {\n  a(3)\n}\nlet p = h1()\nlet q = h2()\n"
  let r = @pipeline.run_tracked(src, "u.mbt", empty_iface(), false)
  assert_eq(r.ctx.exec, 6)
  assert_eq(r.ctx.sig, 4)
  assert_eq(r.ctx.context, 6)
  // AND THE TWO SIGNATURES OF THE RING ARE THE TWO SHARED ONES.
  assert_eq(r.ctx.shared, 2)
  assert_eq(r.ctx.cuts, 2)
  assert_eq(r.ctx.depth, 3)
}

///|
/// AN EDGE LEAVING THE CYCLE IS NOT SWALLOWED BY IT.
///
///     fn g(x : Int) -> Int { x * 2 }
///     fn a(n : Int) -> Int { b(n) }
///     fn b(n : Int) -> Int { a(n) }
///     fn h(n : Int) -> Int { g(n) + a(n) }
///     let z = h(1)
///
/// `h` calls `g` and calls `a`; `g` is not part of the ring and must be
/// executed like any other callee. Four bodies run (h, g, a, b), four
/// signatures, and ONE cut -- the ring's.
///
/// The depth is THREE, and this is the number that would be wrong if the
/// cycle were treated as a unit: `h` at depth 1, `g` and `a` at depth 2, `b`
/// at depth 3. A callee of the ring (`g`) sits at depth 2 -- the same depth as
/// `a`, the member of the ring -- so the ring does not add a frame of its own.
test "0647: an edge leaving the cycle is not swallowed by it" {
  let src = "fn g(x : Int) -> Int {\n  x * 2\n}\nfn a(n : Int) -> Int {\n  b(n)\n}\nfn b(n : Int) -> Int {\n  a(n)\n}\nfn h(n : Int) -> Int {\n  g(n) + a(n)\n}\nlet z = h(1)\n"
  let r = @pipeline.run_tracked(src, "u.mbt", empty_iface(), false)
  assert_eq(r.ctx.exec, 4)
  assert_eq(r.ctx.sig, 4)
  assert_eq(r.ctx.context, 4)
  assert_eq(r.ctx.shared, 0)
  assert_eq(r.ctx.cuts, 1)
  assert_eq(r.ctx.depth, 3)
  assert_true(r.sigs.contains("g(int) -> int"))
  assert_true(r.sigs.contains("h(int) -> int"))
}

///|
/// THE TYPE LAYER'S ANSWER TO "IS THIS TYPE RECURSIVE", MEASURED AT THE LEVEL
/// WHERE A FINDING WOULD APPEAR.
///
///     enum Tree { Leaf, Node(Tree, Tree) }     <- recursive
///     enum Color { Red, Green }                <- not recursive
///
/// Both programs produce ONE report, and the reports are IDENTICAL -- same
/// family, same message. There is no finding about the recursive type, and
/// there is no finding about the plain one either.
///
/// THIS ROW IS THE POINT OF THE WHOLE INCREMENT'S THIRD HALF. A program whose
/// type is recursive and a program whose type is not produce the same output,
/// so "the analyzer reported nothing about the recursive type" CANNOT be read
/// as "the analyzer checked and the type is not recursive". It can only be
/// read as "the analyzer does not read type definitions" -- which is a
/// statement about the analyzer, and the reason the recursive-type check is
/// an INCREMENT TO COME rather than a row to write.
test "0647: a recursive type and a plain type produce the SAME report" {
  let recursive = "enum Tree {\n  Leaf\n  Node(Tree, Tree)\n}\nfn f(t : Tree) -> Int {\n  t\n}\n"
  let plain = "enum Color {\n  Red\n  Green\n}\nfn f(c : Color) -> Int {\n  c\n}\n"
  let r1 = @pipeline.run(recursive, "u.mbt", empty_iface())
  let r2 = @pipeline.run(plain, "u.mbt", empty_iface())
  // ONE REPORT EACH, and the reports are the same report.
  assert_eq(r1.reports.length(), 1)
  assert_eq(r2.reports.length(), 1)
  assert_eq(reports_text_0647(r1.reports), reports_text_0647(r2.reports))
  // AND THE ONE REPORT IS THE SUBSET EXCLUSION -- not a type finding.
  assert_eq(r1.reports[0].family.id(), "MSA-001")
  assert_true(r1.reports[0].message.contains("outside the analyzed subset"))
}

///|
/// The reports of one program, rendered so that two programs can be compared.
fn reports_text_0647(rs : Array[@report.Report]) -> String {
  let out : Array[String] = []
  for rep in rs {
    out.push("\{rep.family.id()}: \{rep.message}")
  }
  out.sort()
  out.join(" | ")
}
