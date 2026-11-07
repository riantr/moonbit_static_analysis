// The shapes the emitter has to get right, parsed for real.
//
// These live beside the emitter because the emitter -- not the framework -- owns
// the decision of which stores are claims: a `let` is FUnusedLocal's business, a
// store to an undeclared name is UndefinedName's, and a store inside a
// conditional whose variable the tail expression reads is NOT dead.

///|
/// The unread regions the frontend declared, for a source.
///
/// The emitter takes them as an argument because a FUNCTION's hole list is a
/// fact about the parse, not about the graph: the parse knows which regions it
/// declined to read, and the graph only knows the statements it converted.
fn unread_of(src : String) -> Array[@core.Span] {
  let out : Array[@core.Span] = []
  let p = @parser.parse(src)
  for r in p.reports {
    if r.family == @core.FParse &&
      r.message.contains("outside the analyzed subset") {
      out.push(r.span)
    }
  }
  out
}

///|
fn dead_of(src : String) -> Array[@report.Report] {
  @pipeline.dead_stores(@parser.parse(src).tree.body, unread_of(src))
}

///|
test "0528: a store in an if whose variable the tail reads is not dead" {
  let src = "fn f(c: bool) -> int {\n  let mut e = 0\n  if c {\n    e = 1\n  }\n  e + 1\n}\n"
  let reps = dead_of(src)
  assert_eq(reps.length(), 0)
}

///|
test "0528: the first of two stores to one name is dead, the last is live" {
  // `e = 1` is overwritten by `e = 2` before anything reads it; `e = 2` is the
  // value the tail reads. Exactly ONE dead store, and it is the FIRST.
  let src = "fn f() -> int {\n  let mut e = 0\n  e = 1\n  e = 2\n  e\n}\n"
  let reps = dead_of(src)
  assert_eq(reps.length(), 1)
  assert_true(reps[0].message.contains("'e'"))
}

///|
test "0528: a store to an undeclared name is not a dead store" {
  // `z` has no `let`; UndefinedName owns that line, and the emitter declines.
  let src = "fn f(x: int) -> int {\n  z = x * 2\n  return z\n}\n"
  let reps = dead_of(src)
  assert_eq(reps.length(), 0)
}

///|
test "0528: a function containing a nested fn is not analysed" {
  // The nested body's reads are not in this graph, so a store here cannot be
  // judged. Measured behaviour of `skipped`: the emitter declines the function.
  let src = "fn f() -> int {\n  let mut e = 0\n  fn g() -> int {\n    e + 1\n  }\n  e = 2\n  g()\n}\n"
  let reps = dead_of(src)
  assert_eq(reps.length(), 0)
}

///|
/// 0542. THE SAME RULE, ONE LEVEL UP: a function containing a region the
/// frontend did not analyse is not analysed either.
///
/// The region here is an `if` used as a VALUE, whose body reads the very
/// variable the store writes. MEASURED, this reported
/// `the value stored in 'v' is read on no path` on moonbit_image 0.3.7
/// `fim.mbt:353`, where `v` is read by `if v < 0.0 { 0.0 } else { v }` on the
/// next line.
///
/// The control is the same program with the `if` written as a STATEMENT, which
/// the frontend reads, and which must still report the dead store -- so the
/// rule cannot pass by silencing every dead store.
test "0542: a function holding an unread region is not analysed" {
  let hidden = "fn f() -> int {\n  let mut v = 1\n  let w = if v > 0 { 2 } else { 3 }\n  v = 4\n  w\n}\n"
  let reps = dead_of(hidden)
  assert_eq(reps.length(), 0)
  // the control: the same shape with a STATEMENT, which the frontend reads
  let shown = "fn f() -> int {\n  let mut v = 1\n  var w = 0\n  if v > 0 {\n    w = 2\n  } else {\n    w = 3\n  }\n  v = 4\n  w\n}\n"
  let reps2 = dead_of(shown)
  assert_eq(reps2.length(), 1)
  assert_true(reps2[0].message.contains("'v'"))
}

///|
/// 0542. THE SAME RULE FOR A LAMBDA'S BODY, and for a `try` expression.
///
/// The async case is the second one, and 0532 attributed it to `guard` -- which
/// is wrong: `guard` is modelled (`Parser::parse_guard` produces an `SIf` with
/// an empty then branch), and a probe with a `guard` and no `try` reports
/// NOTHING. The three-function probe that separates them is in NARRATIVE 0542;
/// the short version is that `try + if`, `try + guard` and `try + no read at
/// all` all report, so the `try` REGION is the cause.
test "0542: a lambda body and a try body are holes too" {
  let lam = "fn f() -> int {\n  let mut c = 1\n  let g = fn(x: int) -> int {\n    c + x\n  }\n  c = 2\n  g(1)\n}\n"
  assert_eq(dead_of(lam).length(), 0)
  let tryr = "fn f() -> int {\n  let mut c = 1\n  try\n    work()\n  c = 2\n  1\n}\nfn work() -> int {\n  1\n}\n"
  assert_eq(dead_of(tryr).length(), 0)
}

///|
/// 0542. THE INDEX OF A PLACE-STORE IS A READ.
///
/// `out[bi] = ...` evaluates `bi` to know which element it writes, so the
/// statement READS `bi`. The node used to carry only the base name, and the
/// store to `bi` on the line above looked like a value nobody reads.
///
/// MEASURED, moonbit_labeler 0.2.13 `component_blackbox_test.mbt:721`.
test "0542: the index of a place-store is a read" {
  let src = "fn f() -> int {\n  let mut bi = 0\n  let out = [0, 0, 0]\n  out[bi] = 1\n  bi = bi + 1\n  out[bi] = 2\n  out[0]\n}\n"
  let reps = dead_of(src)
  // the store to `bi` is read by the next line's index
  assert_eq(reps.length(), 0)
}

///|
/// 0542. AND THE CONTROL: without an index read, the store IS dead.
///
/// A rule that counted every name as read would pass the row above for the
/// wrong reason, so the row below pins that the family still speaks.
test "0542: a store nothing reads is still reported" {
  let src = "fn f() -> int {\n  let mut bi = 0\n  let out = [0, 0, 0]\n  out[0] = 1\n  bi = bi + 1\n  out[0]\n}\n"
  let reps = dead_of(src)
  assert_eq(reps.length(), 1)
  assert_true(reps[0].message.contains("'bi'"))
}
