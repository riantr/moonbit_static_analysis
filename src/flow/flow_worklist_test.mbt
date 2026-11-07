// The two solvers, run against each other.
//
// THE ORACLE IS THE BOOK'S OWN THEOREM. Moller & Schwartzbach prove that every
// fixed-point algorithm in chapters 4.4 and 5.3 computes the same least fixed
// point (Exercise 5.41 asks the reader to prove it for the propagation variant
// specifically). This file turns that into an executable check: the same graph,
// the same lattice, the same transfer function, two independent implementations,
// and one comparison. A disagreement is a bug in one of them, and it fails here
// rather than showing up as a wrong finding three increments later.
//
// WHY A BITMASK LATTICE. `Int` with bitwise-or is a genuinely complete lattice
// of finite height (`bot` = 0), so the test needs no analysis to be sound: it is
// checking the SOLVER, and a solver bug must not be able to hide behind an
// analysis bug. Reachability is the cheapest such lattice and it is also the
// first real client (a fact that reaches a node either does or does not).

///|
/// The test lattice: an `Int` read as a set of facts, ordered by inclusion.
fn bits() -> @flow.Lattice[Int32] {
  { bot: fn() { 0 }, join: fn(a, b) { a | b }, eq: fn(a, b) { a == b }, }
}

///|
/// A graph with a diamond and a back edge, which is the smallest shape that
/// exercises every case the solvers have to get right:
///
///     0 entry -> 1 test -> 2 body -> 3 latch -> 1   (the back edge)
///                  \-> 4 exit
///
/// `1` receives the JOIN of two different predecessors (`0` and `3`), which is
/// the case a single-pass walk cannot compute and the reason a fixed point is
/// needed at all.
fn diamond_preds() -> Array[Array[Int32]] {
  [[], [0, 3], [1], [2], [1]]
}

///|
fn diamond_succ() -> Array[Array[Int32]] {
  [[1], [2, 4], [3], [1], []]
}

///|
/// Node 0 generates fact 1; node 2 generates fact 2; everything else is
/// identity. The facts then have to travel around the back edge on their own.
fn diamond_transfer() -> (Int32, Int32) -> Int32 {
  fn(v, x) {
    match v {
      0 => 1
      2 => x | 2
      _ => x
    }
  }
}

///|
test "flow/0526: both solvers compute the same least fixed point" {
  let lat = bits()
  let transfer = diamond_transfer()
  let n = 5
  let rr = @flow.solve_round_robin(lat, n, diamond_preds(), transfer)
  let before = @flow.solve_propagation(lat, n, diamond_succ(), transfer)
  let prop = @flow.states_after(n, before, transfer)
  let mut v = 0
  while v < n {
    assert_eq(prop[v], rr[v])
    v = v + 1
  }
}

///|
/// The value itself, not just the agreement. Both facts have to reach the exit:
/// fact 1 comes straight from the entry, and fact 2 comes around the loop and
/// then has to survive the JOIN at node 1. If the solver ignored the back edge
/// the exit would read 1 instead of 3, and an agreement test alone would not
/// notice that both solvers were wrong in the same way.
test "flow/0526: the back edge carries a fact to the exit" {
  let lat = bits()
  let rr = @flow.solve_round_robin(lat, 5, diamond_preds(), diamond_transfer())
  assert_eq(rr[0], 1)
  assert_eq(rr[1], 3)
  assert_eq(rr[2], 3)
  assert_eq(rr[3], 3)
  assert_eq(rr[4], 3)
}

///|
/// An entry node has no predecessors, so it reads `bot` -- the book's Exercise
/// 5.1(a), and the reason `join_all` of an empty set is `bot` rather than an
/// error. Getting this wrong makes every entry node's transfer run on junk.
test "flow/0526: an entry node reads bot, not the top of the lattice" {
  let lat = bits()
  let seen = @flow.join_of_nodes(lat, [0, 0, 0], [])
  assert_eq(seen, 0)
}

///|
/// `join_all` over an empty array is `bot`; over a set it is the union.
test "flow/0526: join_all is bot on nothing and the union otherwise" {
  let lat = bits()
  assert_eq(@flow.join_all(lat, []), 0)
  assert_eq(@flow.join_all(lat, [1, 2, 4]), 7)
}
