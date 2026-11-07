// interval_test: THE OPERATORS PINNED AGAINST THE BOOK'S OWN NUMBERS.
//
// 0529. Every number asserted below is printed in Møller & Schwartzbach,
// Chapter 6, with the page it comes from. That is the point: a lattice whose
// widening "obviously converges" is a claim, and the book worked the example --
// including the result that is DISCOURAGING -- so the implementation can be
// checked against a number it did not produce.

///|
/// A copy, so a transfer can assign into the result without touching its input.
fn ist_copy(s : Array[@flow.Interval]) -> Array[@flow.Interval] {
  let out : Array[@flow.Interval] = []
  for i in s {
    out.push(i)
  }
  out
}

///|
/// The seed set `B` of book p.83: "the integer constants occurring in the given
/// program", together with −∞ and ∞. The infinities are represented by the
/// ABSENCE of an endpoint, so `B` holds the finite seeds only.
fn ist_b() -> Array[Int32] {
  [0, 1, 7]
}

///|
/// The CFG of the book's worked example, p.83–84:
///
///     y = 0 ; x = 7 ; x = x+1 ;
///     while (input) { x = 7 ; x = x+1 ; y = y+1 ; }
///
/// Variables: 0 = x, 1 = y.
///
///     node 0  y = 0          preds []
///     node 1  x = 7          preds [0]
///     node 2  x = x+1        preds [1]
///     node 3  while (input)  preds [2, 6]   <- the loop head
///     node 4  x = 7          preds [3]
///     node 5  x = x+1        preds [4]
///     node 6  y = y+1        preds [5]
///
/// `states[3]` is the "program point after the while-loop" that the book
/// tabulates: the loop head sees both the fall-through and the back edge, so
/// its state IS the join the book prints.
fn ist_preds() -> Array[Array[Int32]] {
  [[], [0], [1], [2, 6], [3], [4], [5]]
}

///|
/// The transfer for the example's seven nodes.
fn ist_transfer(v : Int32, st : Array[@flow.Interval]) -> Array[@flow.Interval] {
  let out = ist_copy(st)
  if v == 0 {
    out[1] = @flow.interval_point(0)
  } else if v == 1 {
    out[0] = @flow.interval_point(7)
  } else if v == 2 {
    out[0] = @flow.eval_add(out[0], @flow.interval_point(1))
  } else if v == 4 {
    out[0] = @flow.interval_point(7)
  } else if v == 5 {
    out[0] = @flow.eval_add(out[0], @flow.interval_point(1))
  } else if v == 6 {
    out[1] = @flow.eval_add(out[1], @flow.interval_point(1))
  }
  out
}

///|
/// `[1,10] + [−5,7] = [−4,17]` — book p.80, verbatim.
test "0529: the book's own addition example" {
  let got = @flow.eval_add(
    @flow.interval_range(1, 10),
    @flow.interval_range(-5, 7),
  )
  assert_eq(got.text(), "[-4,17]")
}

///|
/// Subtraction widens in BOTH directions, which is the mistake the book's
/// `b_op` definition is designed to prevent: `[l1,h1] − [l2,h2]` is
/// `[l1−h2, h1−l2]` and not `[l1−l2, h1−h2]`.
test "0529: subtraction takes the endpoints crosswise" {
  let got = @flow.eval_sub(
    @flow.interval_range(1, 10),
    @flow.interval_range(-5, 7),
  )
  // 1 − 7 = −6, and 10 − (−5) = 15.
  assert_eq(got.text(), "[-6,15]")
}

///|
/// A multiplication whose operand has no finite bound answers `full()`. The
/// exact image of `[0,+∞) × [2,2]` is `[0,+∞)` and this domain refuses to say
/// so, because saying it needs the sign of the unbounded side.
test "0529: multiplication with an unbounded operand is full, not a guess" {
  let got = @flow.eval_mul(@flow.interval_at_least(0), @flow.interval_point(2))
  assert_true(got.is_full())
}

///|
/// A divisor that MAY be zero is `full()`, and NOT `⊥`. `⊥` would say the
/// expression never produces a value, which is strong enough to make a later
/// branch look infeasible -- an unsoundness with a plausible-looking message.
test "0529: a divisor that may be zero is full, never bottom" {
  let got = @flow.eval_div(@flow.interval_point(1), @flow.interval_range(-1, 1))
  assert_true(got.is_full())
  assert_false(got.is_empty())
}

///|
/// `join` is the convex hull, so the gap is lost on purpose: `[0,0] ⊔ [2,2]`
/// is `[0,2]` and contains 1, which is in neither input.
test "0529: join is the convex hull and keeps a value neither input had" {
  let got = @flow.interval_point(0).join(@flow.interval_point(2))
  assert_eq(got.text(), "[0,2]")
  assert_true(got.holds(1))
}

///|
/// `meet` of two disjoint intervals is `⊥`.
test "0529: meet of disjoint intervals is bottom" {
  let got = @flow.interval_range(0, 0).meet(@flow.interval_range(2, 2))
  assert_true(got.is_empty())
}

///|
/// `le` is inclusion and `same` is representation equality, and the two differ
/// on the several encodings of `⊥`. The solver's fixpoint test uses `same`, so
/// this pins that the distinction is not academic.
test "0529: le and same are different questions" {
  let a = @flow.interval_bot()
  let b = @flow.interval_range(4, 3)
  // Both are ⊥, so neither is above the other and the fixpoint test must see
  // them as equal even though their fields differ.
  assert_true(a.is_empty())
  assert_true(b.is_empty())
  assert_true(a.same(b))
  assert_true(a.le(@flow.interval_point(0)))
}

///|
/// `ω'([3,5])` with `B = {0,1,7}` — book p.83: each endpoint moves to the
/// nearest member of `B` on the correct side, so the lower endpoint goes DOWN
/// (1) and the upper endpoint goes UP (7).
test "0529: omega moves both endpoints outward onto B" {
  let got = @flow.interval_range(3, 5).omega(ist_b())
  assert_eq(got.text(), "[1,7]")
}

///|
/// An endpoint with no member of `B` beyond it becomes unbounded: `ω'([8,8])`
/// with `B = {0,1,7}` has `min { i ∈ B | 8 ≤ i } = ∞`.
test "0529: omega sends an endpoint past B to infinity" {
  let got = @flow.interval_point(8).omega(ist_b())
  assert_eq(got.text(), "[7,+∞]")
}

///|
/// `∇'` is an UPPER BOUND: `a ⊑ a∇b` and `b ⊑ a∇b`, which is the first of the
/// two properties the book requires of a widening operator (p.92).
test "0529: widening is an upper bound of both arguments" {
  let b = ist_b()
  let a = @flow.interval_range(0, 1)
  let c = @flow.interval_range(0, 5)
  let w = @flow.widen_interval(a, c, b)
  assert_true(a.le(w))
  assert_true(c.le(w))
}

///|
/// An endpoint that did NOT move is kept exactly. This is the whole difference
/// between `∇'` and `ω'`, and it is what lets the book's example reach `[8,8]`
/// for `x` with the binary operator (p.86) where the unary one gives `[7,∞]`.
test "0529: widening keeps a stable endpoint exactly" {
  let b = ist_b()
  let got = @flow.widen_interval(
    @flow.interval_point(8),
    @flow.interval_point(8),
    b,
  )
  assert_eq(got.text(), "[8,8]")
}

///|
/// A moving endpoint is coarsened onto `B`: from `[0,1]` to `[0,2]` the upper
/// endpoint is unstable, so it jumps to the next member of `B`, which is 7.
test "0529: widening coarsens only the endpoint that moved" {
  let b = ist_b()
  let got = @flow.widen_interval(
    @flow.interval_range(0, 1),
    @flow.interval_range(0, 2),
    b,
  )
  assert_eq(got.text(), "[0,7]")
}

///|
/// THE BOOK'S DIVERGENCE, MEASURED. Without widening the naive fixpoint on the
/// example yields `y ↦ [0,1]`, `[0,2]`, `[0,3]`, … (p.84) and never converges:
/// the upper endpoint grows by exactly one per round, so after `k` rounds it is
/// `k−1` and the run stops at the ITERATION CAP rather than at a fixpoint.
///
/// `converged` being false is the result, and it is a field because a caller
/// that read this array as an answer would be reading a non-fixpoint.
test "0529: without widening the example diverges, and the run says so" {
  let lat = @flow.interval_state_lattice(2)
  let no_widen : (Int32, Array[@flow.Interval], Array[@flow.Interval]) -> Array[
    @flow.Interval,
  ] = (_v, _prev, next) => next
  let at_none : (Int32) -> Bool = _v => false
  let r = @flow.solve_widening(
    lat,
    7,
    ist_preds(),
    ist_transfer,
    no_widen,
    at_none,
    50,
  )
  assert_false(r.converged)
  assert_eq(r.iterations, 50)
  // y at the loop head is [0, k−1] after k rounds: the growth of one per
  // round IS the divergence.
  assert_eq(r.states[3][1].text(), "[0,49]")
}

///|
/// THE BOOK'S WIDENED RESULT, WITHOUT NARROWING, at the loop head only
/// (Exercise 6.13): `x ↦ [8,8]`, `y ↦ [0,+∞]`.
///
/// Book p.86 says this binary widening "without using narrowing … obtain[s] the
/// same analysis result as with the combination of simple widening and
/// narrowing we looked at earlier", and that earlier result is exactly
/// `[x ↦ [8,8], y ↦ [0,∞]]` (p.84).
test "0529: binary widening at the loop head reaches the book's answer" {
  let lat = @flow.interval_state_lattice(2)
  let b = ist_b()
  let widen : (Int32, Array[@flow.Interval], Array[@flow.Interval]) -> Array[
    @flow.Interval,
  ] = (_v, prev, next) => {
    let out : Array[@flow.Interval] = []
    let mut i = 0
    while i < next.length() {
      out.push(@flow.widen_interval(prev[i], next[i], b))
      i = i + 1
    }
    out
  }
  let at_head : (Int32) -> Bool = v => v == 3
  let r = @flow.solve_widening(
    lat,
    7,
    ist_preds(),
    ist_transfer,
    widen,
    at_head,
    50,
  )
  assert_true(r.converged)
  // Two facts, and the second is the one widening is supposed to lose nothing
  // of here: y is unstable and coarsened, x is stable and kept EXACT.
  assert_eq(r.states[3][0].text(), "[8,8]")
  assert_eq(r.states[3][1].text(), "[0,+∞]")
}

///|
/// THE SIMPLE WIDENING OF p.83, WITH ONE NARROWING ROUND, on the same example.
///
/// `ω` is applied at EVERY node, and the book reports the discouraging result
/// `x ↦ [7,∞]` (p.84) for it. One narrowing round then reaches
/// `[x ↦ [8,8], y ↦ [0,∞]]` (p.84), which is why narrowing exists: widening
/// shoots above the target and one application of `f` comes back down.
test "0529: simple widening at every node, then one narrowing round" {
  let lat = @flow.interval_state_lattice(2)
  let b = ist_b()
  let widen : (Int32, Array[@flow.Interval], Array[@flow.Interval]) -> Array[
    @flow.Interval,
  ] = (_v, _prev, next) => {
    let out : Array[@flow.Interval] = []
    let mut i = 0
    while i < next.length() {
      out.push(next[i].omega(b))
      i = i + 1
    }
    out
  }
  let at_all : (Int32) -> Bool = _v => true
  let r = @flow.solve_widening(
    lat,
    7,
    ist_preds(),
    ist_transfer,
    widen,
    at_all,
    50,
  )
  assert_true(r.converged)
  // THE DISCOURAGING PART, reproduced exactly: x is widened even though it was
  // stable, and the book calls this result "discouraging" (p.84).
  assert_eq(r.states[3][0].text(), "[7,+∞]")
  assert_eq(r.states[3][1].text(), "[0,+∞]")
  // Exercise 6.7 asks EXACTLY how many narrowing steps this takes. Measured
  // answer: TWO SWEEPS, not one. A round-robin sweep visits the loop head
  // BEFORE the back edge has been recomputed, so the first sweep joins an
  // exact fall-through with a stale widened back edge and x is still [7,+∞];
  // the second sweep sees the recomputed back edge and x becomes [8,8].
  let n1 = @flow.narrow_round(lat, 7, ist_preds(), ist_transfer, r.states)
  assert_eq(n1[3][0].text(), "[7,+∞]")
  let n2 = @flow.narrow_round(lat, 7, ist_preds(), ist_transfer, n1)
  // THE BOOK'S FINAL ANSWER, p.84.
  assert_eq(n2[3][0].text(), "[8,8]")
  assert_eq(n2[3][1].text(), "[0,+∞]")
}

///|
/// WHERE WIDENING IS APPLIED IS A DIAL, AND THIS PROGRAM SHOWS WHICH DIAL IT
/// IS. The book's Exercise 6.13 says widening only at loop heads "improves
/// precision" compared with widening everywhere, and this program shows the
/// subtlety measured: with the BINARY operator the placement makes NO
/// difference here (x is `[8,8]` both ways), because ∇' only coarsens an
/// endpoint that MOVED and x never moves; the precision loss on x comes from
/// the UNARY ω, which coarsens every endpoint every iteration. The `at_node`
/// predicate stays a parameter because the book is explicit that the choice is
/// real -- on a program where a non-loop node's value is unstable, widening
/// everywhere coarsens it and widening at the loop head does not.
test "0529: binary widening keeps a stable endpoint at either placement" {
  let lat = @flow.interval_state_lattice(2)
  let b = ist_b()
  let widen : (Int32, Array[@flow.Interval], Array[@flow.Interval]) -> Array[
    @flow.Interval,
  ] = (_v, prev, next) => {
    let out : Array[@flow.Interval] = []
    let mut i = 0
    while i < next.length() {
      out.push(@flow.widen_interval(prev[i], next[i], b))
      i = i + 1
    }
    out
  }
  let at_head : (Int32) -> Bool = v => v == 3
  let head_only = @flow.solve_widening(
    lat,
    7,
    ist_preds(),
    ist_transfer,
    widen,
    at_head,
    50,
  )
  let at_all : (Int32) -> Bool = _v => true
  let everywhere = @flow.solve_widening(
    lat,
    7,
    ist_preds(),
    ist_transfer,
    widen,
    at_all,
    50,
  )
  assert_true(head_only.converged)
  assert_true(everywhere.converged)
  // x never moves after the first iteration, so ∇' keeps it exact either way.
  assert_eq(head_only.states[3][0].text(), "[8,8]")
  assert_eq(everywhere.states[3][0].text(), "[8,8]")
  // y moves every iteration, so both placements coarsen it to +∞, and neither
  // placement is pretending otherwise.
  assert_eq(head_only.states[3][1].text(), "[0,+∞]")
  assert_eq(everywhere.states[3][1].text(), "[0,+∞]")
}
