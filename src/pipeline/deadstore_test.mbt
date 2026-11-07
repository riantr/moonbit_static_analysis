// The shapes the emitter has to get right, parsed for real.
//
// These live beside the emitter because the emitter -- not the framework -- owns
// the decision of which stores are claims: a `let` is FUnusedLocal's business, a
// store to an undeclared name is UndefinedName's, and a store inside a
// conditional whose variable the tail expression reads is NOT dead.

///|
test "0528: a store in an if whose variable the tail reads is not dead" {
  let src = "fn f(c: bool) -> int {\n  let mut e = 0\n  if c {\n    e = 1\n  }\n  e + 1\n}\n"
  let reps = @pipeline.dead_stores(@parser.parse(src).tree.body)
  assert_eq(reps.length(), 0)
}

///|
test "0528: the first of two stores to one name is dead, the last is live" {
  // `e = 1` is overwritten by `e = 2` before anything reads it; `e = 2` is the
  // value the tail reads. Exactly ONE dead store, and it is the FIRST.
  let src = "fn f() -> int {\n  let mut e = 0\n  e = 1\n  e = 2\n  e\n}\n"
  let reps = @pipeline.dead_stores(@parser.parse(src).tree.body)
  assert_eq(reps.length(), 1)
  assert_true(reps[0].message.contains("'e'"))
}

///|
test "0528: a store to an undeclared name is not a dead store" {
  // `z` has no `let`; UndefinedName owns that line, and the emitter declines.
  let src = "fn f(x: int) -> int {\n  z = x * 2\n  return z\n}\n"
  let reps = @pipeline.dead_stores(@parser.parse(src).tree.body)
  assert_eq(reps.length(), 0)
}

///|
test "0528: a function containing a nested fn is not analysed" {
  // The nested body's reads are not in this graph, so a store here cannot be
  // judged. Measured behaviour of `skipped`: the emitter declines the function.
  let src = "fn f() -> int {\n  let mut e = 0\n  fn g() -> int {\n    e + 1\n  }\n  e = 2\n  g()\n}\n"
  let reps = @pipeline.dead_stores(@parser.parse(src).tree.body)
  assert_eq(reps.length(), 0)
}
