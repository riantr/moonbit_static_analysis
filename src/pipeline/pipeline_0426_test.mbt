// Tests for 0.4.26: a function's TAIL EXPRESSION is its return value.
//
// Found by tracing rather than by a corpus delta, and the delta is zero: across
// six corpora and 12,428 files, nothing observable moves. The defect is real and
// it is a false positive about code that compiles, but its blast radius is
// bounded by the interpreter's rule that a body is only analysed when REACHED
// from a top-level statement -- which is why 305 eligible corpus functions
// produce zero findings.
//
// THE DEFECT. A tail expression parsed as an `SExpr`, and `SExpr` discards its
// value:
//
//     Interp::exec_stmt   SExpr(e) => { let _ = self.eval(e, env) }
//     Interp::analyze_fn  let ret = join_vals(self.ret_vals)
//     join_vals           if vals.length() == 0 { return AType("None") }
//
// so `ret_vals` stayed empty, `join_vals` answered `None`, that `None` went into
// the call cache, and CALLERS inherited it. 0.4.26 adds the AST node `STail`,
// which `parse_block` only produces for a FUNCTION body -- `fn_body` is the flag,
// and it exists because the same block parser reads loop bodies, `if` arms and
// bare blocks, where a trailing expression is an ordinary discarded statement.
//
// SETTLED before any of this was written: twelve tail-expression shapes,
// including `fn f() -> Int { 1 }`, `fn f() -> Int { let x = 1  x }`,
// `fn f(n : Int) -> Int { if n > 0 { 1 } else { 2 } }` and
// `fn f() -> Int raise E { if n > 0 { raise E(n) }  1 }` -- all zero errors from
// `moon check`. The construct is ordinary MoonBit; real code is full of it.

// ---------------------------------------------------------------------------
// A -- the false positive this removes
// ---------------------------------------------------------------------------

///|
/// THE REPRODUCER, and the shape that has no `return` anywhere in it.
///
/// `f() + 1` in `g` used to read `no method matching +(None, int)`: the caller
/// inherited `f`'s empty return value and the analyzer then reported a missing
/// method on it. That is a confident false positive about a program `moon check`
/// accepts with zero errors, so it belongs in the false-positive column, not in
/// "real defect".
///
/// The CONTROL is the same file with `return 1` in `f` instead of the bare `1`.
/// It was already silent, and it has to stay silent -- otherwise "0 findings"
/// here would mean nothing, because it would also hold if the fix had broken
/// calls entirely.
test "0426: a caller's arithmetic on a tail-expression function is not a missing method" {
  let r = @pipeline.run(
    "fn f() -> Int {\n  1\n}\nfn g() -> Int {\n  f() + 1\n}\nlet x = g()\n",
    "tail_arith.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "MethodError"), 0)
  assert_eq(count_family(r, "OperatorMismatch"), 0)
}

///|
/// THE SAME SHAPE WITH AN EXPLICIT RETURN, unchanged by this release.
test "0426: control -- an explicit return is still a returned value" {
  let r = @pipeline.run(
    "fn f() -> Int {\n  return 1\n}\nfn g() -> Int {\n  f() + 1\n}\nlet x = g()\n",
    "ret_arith.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "MethodError"), 0)
  assert_eq(count_family(r, "OperatorMismatch"), 0)
}

///|
/// IT SURVIVES THE HOP. The wrong value went into the CALL CACHE, so a caller
/// of a caller was poisoned just the same; one level is not enough to catch a
/// leak that is stored rather than returned.
test "0426: the tail value survives two levels of callers" {
  let r = @pipeline.run(
    "fn f() -> Int {\n  1\n}\nfn g() -> Int {\n  f()\n}\nfn h() -> Int {\n  g() + 2\n}\nlet x = h()\n",
    "tail_two_hops.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "MethodError"), 0)
}

///|
/// A TAIL EXPRESSION IS EVALUATED, not skipped. This is the opposite of the
/// `raise` operand, which is walked but deliberately NOT evaluated because
/// everything after it is dead code. Here the expression IS the return value, so
/// a defect inside it is a real defect and must still be reported. Without this
/// test, a "fix" that simply stopped evaluating tail expressions would pass
/// every other test in this file.
test "0426: a defect inside a tail expression is still reported" {
  let r = @pipeline.run(
    "fn f() -> Int {\n  nosuchfunction()\n}\nlet x = f()\n",
    "tail_defect_inside.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "UndefinedName"), 1)
}

// ---------------------------------------------------------------------------
// B -- the signature the analyzer reports about itself
// ---------------------------------------------------------------------------

///|
/// THE OUTPUT IS A CLAIM ABOUT UNDERSTANDING, so a wrong one is a defect even
/// when no finding fires. `fn f() -> Int { 1 }` used to print `f() -> None`,
/// and that string was read by nothing else in the pipeline -- it is a statement
/// the tool makes about a file it has just read.
test "0426: a tail-expression function reports its real return type" {
  let r = @pipeline.run(
    "fn f() -> Int {\n  1\n}\nlet x = f()\n",
    "tail_sig_int.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(r.sigs.length(), 1)
  assert_eq(r.sigs[0], "f() -> int")
}

///|
/// NOT ONLY INTEGERS -- one element type is one fixture, not proof.
test "0426: a string tail reports str, not None" {
  let r = @pipeline.run(
    "fn f() -> String {\n  \"a\"\n}\nlet x = f()\n",
    "tail_sig_str.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(r.sigs.length(), 1)
  assert_eq(r.sigs[0], "f() -> str")
}

///|
/// IT IS THE LAST STATEMENT, not "some expression in the body". The tail here
/// is a NAME, and its value comes from the binding -- so this also pins that the
/// node carries the expression that was evaluated, not a flag.
test "0426: the tail is the last statement, not any expression statement" {
  let r = @pipeline.run(
    "fn f() -> Int {\n  let x = 1\n  x\n}\nlet y = f()\n",
    "tail_after_stmt.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(r.sigs.length(), 1)
  assert_eq(r.sigs[0], "f() -> int")
}

// ---------------------------------------------------------------------------
// C -- the paths that were ALREADY right, kept honest
// ---------------------------------------------------------------------------

///|
/// THE EXPLICIT-RETURN CONTROL. It said `int` before this release and must say
/// `int` after; a change here would mean the tail path fixed itself by breaking
/// the ordinary one.
test "0426: control -- an explicit return still reports int" {
  let r = @pipeline.run(
    "fn f() -> Int {\n  return 1\n}\nlet x = f()\n",
    "ret_sig.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(r.sigs.length(), 1)
  assert_eq(r.sigs[0], "f() -> int")
}

///|
/// THE NEVER-CALLED PATH. A function no top-level statement reaches never runs
/// its body, so the reported type comes from the DECLARATION instead. That path
/// was always right, and it is the one that made this easy to miss: testing
/// `fn f() -> Int { 1 }` on its own shows the correct answer.
test "0426: control -- a never-called function reports its declared type" {
  let r = @pipeline.run(
    "fn f() -> Int {\n  1\n}\n",
    "uncalled_sig.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(r.sigs.length(), 1)
  assert_eq(r.sigs[0], "f() -> int")
}

///|
/// `()` IS UNIT, AND IT WAS RIGHT BY ACCIDENT BEFORE.
///
/// `fn f() -> Unit { () }` reported `None` before this release -- for the wrong
/// reason (an empty `ret_vals`), but with the right answer. The obvious fix then
/// made it worse: an empty `ETuple` evaluated to `Tuple`, so the function began
/// contradicting its own annotation. Both lenses now say Unit for `()`, and this
/// is the fixture that catches it.
test "0426: a Unit tail expression is Unit, not Tuple" {
  let r = @pipeline.run(
    "fn f() -> Unit {\n  ()\n}\nlet x = f()\n",
    "unit_tail.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(r.sigs.length(), 1)
  assert_eq(r.sigs[0], "f() -> None")
  assert_eq(count_family(r, "AssignTypeMismatch"), 0)
}

///|
/// A REAL TUPLE IS STILL A TUPLE -- the control for the arm above. If `()` were
/// "fixed" by answering `Tuple` for every tuple, this fixture's `let t = (1, 2)`
/// is where it would show, and its tail `7` still has to be the reported type.
test "0426: a two-element tuple literal does not become Unit" {
  let r = @pipeline.run(
    "fn f() -> Int {\n  let t = (1, 2)\n  7\n}\nlet x = f()\n",
    "tuple_still_tuple.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(r.sigs.length(), 1)
  assert_eq(r.sigs[0], "f() -> int")
}

///|
/// `fn_body` IS A FLAG, AND A LOOP BODY IS NOT A FUNCTION BODY.
///
/// If `parse_block` had been handed `true` for loop bodies too, the `while`'s
/// trailing expression would become a second return value and the join would
/// widen: Unit against `int` is a union, so the reported type would change from
/// `int` to a union of both. That is the only observable difference, which is why
/// the fixture uses a Unit call for the loop body and an `int` for the tail.
///
/// THE LOOP BODY IS A CALL, NOT A LITERAL, and that was settled rather than
/// chosen: the first version of this fixture used `while s == "a" { "b" }` and
/// real `moon check` rejects it with
///
///     4139  This expression has type String, its value cannot be
///           implicitly ignored
///
/// because a loop body's trailing expression is DISCARDED, and only Unit may be
/// discarded silently. A fixture the compiler rejects is not a fixture.
///
/// The parameter is written out in the expectation on purpose. `f(str) -> int`
/// says two things at once -- the declared parameter survived, and the return is
/// `int` alone -- where `f() -> int` would have been satisfied by a rendering
/// bug in the parameter half of the signature.
///
/// `noop() -> None` is asserted alongside it, and it is the control that the
/// helper's OWN tail is the unit value: `noop`'s body is `()`, so the empty-tuple
/// arm is what makes that string right. The order is `analyzed_sigs`' own
/// `out.sort()` -- `f` precedes `noop` -- asserted rather than assumed.
test "0426: a trailing expression in a loop body is not the function's value" {
  let r = @pipeline.run(
    "fn noop() -> Unit {\n  ()\n}\nfn f(s : String) -> Int {\n  while s == \"a\" {\n    noop()\n  }\n  7\n}\nlet x = f(\"a\")\n",
    "loop_body_not_tail.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(r.sigs.length(), 2)
  assert_eq(r.sigs[0], "f(str) -> int")
  assert_eq(r.sigs[1], "noop() -> None")
}

// ---------------------------------------------------------------------------
// D — the two boundaries of "which statement", settled rather than assumed
// ---------------------------------------------------------------------------

///|
/// ONLY THE LAST ONE. `noop()` is a perfectly good expression statement one
/// line earlier, and if the parser tagged every `SExpr` in a function body this
/// would become its tail too: `ret_vals` would hold Unit AND `7`, and the join
/// would widen away from `int`.
///
/// This is the fixture that separates the two halves of the parser's condition.
/// Dropping `at(TRBrace)` -- so position stops mattering -- kills this one;
/// dropping `fn_body` -- so the block's role stops mattering -- is killed by the
/// loop-body fixture above. Neither mutation is visible to the other test, which
/// is why both exist.
test "0426: an expression statement earlier in the body is not the tail" {
  let r = @pipeline.run(
    "fn noop() -> Unit {\n  ()\n}\nfn f() -> Int {\n  noop()\n  7\n}\nlet x = f()\n",
    "earlier_expr_not_tail.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(r.sigs.length(), 2)
  assert_eq(r.sigs[0], "f() -> int")
  assert_eq(r.sigs[1], "noop() -> None")
}

///|
/// A REAL TUPLE IS STILL A TUPLE WHEN IT IS THE VALUE -- the control for the
/// empty-tuple arm, and the one the earlier "does not become Unit" fixture could
/// not reach.
///
/// That fixture binds the tuple to a local and returns something else, so the
/// tuple's own value never reaches `ret_vals` and the arm is never read. Here the
/// tuple IS the tail, so `AType("Tuple")` versus `AType("None")` is the whole
/// difference. `fn f() -> (Int, Int) { (1, 2) }` is settled valid: zero real
/// errors from `moon check`.
test "0426: a tuple tail is a tuple, not Unit" {
  let r = @pipeline.run(
    "fn f() -> (Int, Int) {\n  (1, 2)\n}\nlet x = f()\n",
    "tuple_tail.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(r.sigs.length(), 1)
  assert_eq(r.sigs[0], "f() -> Tuple")
}
