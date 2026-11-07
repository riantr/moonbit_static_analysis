// interval: THE INTERVAL DOMAIN, WITH WIDENING AND NARROWING.
//
// 0529. Increment 3 of the book plan (§6.1, §6.2). A monotone framework needs
// a lattice of FINITE height for the solvers in 0526 to terminate (Kleene's
// theorem needs it, book p.47 and p.82). The interval lattice has INFINITE
// height -- [0,0] ⊑ [0,1] ⊑ [0,2] ⊑ ... (book p.80) -- so the solvers this
// package already ships may never converge on it, and Chapter 6's answer is a
// WIDENING operator, with NARROWING to recover the precision widening throws
// away.
//
// THE LATTICE IS THE BOOK'S, and the representation is the one thing that had
// to be chosen rather than copied. Book p.79:
//
//     Interval = lift({ [l,h] | l,h ∈ N ∧ l ≤ h })      N = Z ∪ {−∞, +∞}
//
// so `⊥` is a member DISTINCT from every interval, and the endpoints range over
// integers EXTENDED with the infinities. Both facts are encoded in the fields
// rather than in sentinel values:
//
//     has_lo / has_hi   whether that endpoint is FINITE at all
//     lo / hi           meaningful only when the flag is set
//     EMPTY             has_lo && has_hi && lo > hi  -- i.e. ⊥
//
// A sentinel (`Int32::min_value()` for −∞) would make the arithmetic wrap and
// would turn every emptiness test into a question about overflow instead of
// about the program. guardfacts made the same choice for the same reason.
//
// WHAT IS SOUND HERE IS NOT OBVIOUS, SO IT IS NAMED. Every operator below
// OVER-approximates: `eval` returns an interval CONTAINING every concrete
// result, `join` is the convex hull (which loses gaps -- [0,0] ⊔ [2,2] is
// [0,2]), and every operator whose exact image would not be convex or would
// need an unbounded endpoint returns `full()`. Losing precision is allowed;
// losing a value is not.

///|
/// One interval, with the endpoints' finiteness kept separate from their
/// values. See the representation note at the top of this file.
pub(all) struct Interval {
  has_lo : Bool
  lo : Int32
  has_hi : Bool
  hi : Int32
}

///|
/// `⊥` -- no value at all. Distinct from `full()`, which is every value.
///
/// Encoded as `lo > hi` with both endpoints set, which is the standard reading
/// of an empty interval and keeps `is_empty` a single comparison.
pub fn interval_bot() -> Interval {
  { has_lo: true, lo: 1, has_hi: true, hi: 0, }
}

///|
/// `[−∞, +∞]` -- the top of the lattice.
pub fn interval_full() -> Interval {
  { has_lo: false, lo: 0, has_hi: false, hi: 0, }
}

///|
/// `[i, i]`.
pub fn interval_point(i : Int32) -> Interval {
  { has_lo: true, lo: i, has_hi: true, hi: i, }
}

///|
/// `[lo, hi]`, or `⊥` when the range is already empty.
pub fn interval_range(lo : Int32, hi : Int32) -> Interval {
  { has_lo: true, lo, has_hi: true, hi, }
}

///|
/// `[n, +∞)`.
pub fn interval_at_least(n : Int32) -> Interval {
  { has_lo: true, lo: n, has_hi: false, hi: 0, }
}

///|
/// `(−∞, n]`.
pub fn interval_at_most(n : Int32) -> Interval {
  { has_lo: false, lo: 0, has_hi: true, hi: n, }
}

///|
/// Is this `⊥`?
pub fn Interval::is_empty(self : Interval) -> Bool {
  self.has_lo && self.has_hi && self.lo > self.hi
}

///|
/// Is this `[−∞, +∞]`?
pub fn Interval::is_full(self : Interval) -> Bool {
  !self.has_lo && !self.has_hi
}

///|
/// Is `i` in this interval? `⊥` contains nothing.
pub fn Interval::holds(self : Interval, i : Int32) -> Bool {
  if self.is_empty() {
    return false
  }
  (if self.has_lo { self.lo <= i } else { true }) &&
  (if self.has_hi { i <= self.hi } else { true })
}

///|
/// `a ⊑ b` -- INCLUSION, which is the book's order (p.79):
/// `[l1,h1] ⊑ [l2,h2] ⟺ l2 ≤ l1 ∧ h1 ≤ h2`. `⊥` is below everything.
pub fn Interval::le(self : Interval, other : Interval) -> Bool {
  if self.is_empty() {
    return true
  }
  if other.is_empty() {
    return false
  }
  lo_val_le(other, self) && hi_val_le(self, other)
}

///|
/// Two intervals are the same. Used by the solver's fixpoint test, so it must
/// be EQUALITY OF REPRESENTATIONS and not `le` in both directions: `⊥` has
/// many encodings of "empty" and a fixpoint test that accepted any of them
/// could stop before writing the first one.
pub fn Interval::same(self : Interval, other : Interval) -> Bool {
  if self.is_empty() && other.is_empty() {
    return true
  }
  self.has_lo == other.has_lo &&
  self.has_hi == other.has_hi &&
  (if self.has_lo { self.lo == other.lo } else { true }) &&
  (if self.has_hi { self.hi == other.hi } else { true })
}

///|
/// `a ⊔ b` -- the least interval CONTAINING both, which is the convex hull.
///
/// This is where precision is deliberately spent: `[0,0] ⊔ [2,2]` is `[0,2]`,
/// and the value `1` is in the answer although it is in neither input. An
/// interval domain cannot represent a union with a gap, and pretending it can
/// by keeping two intervals would be a different (finite, more expensive)
/// domain.
pub fn Interval::join(self : Interval, other : Interval) -> Interval {
  if self.is_empty() {
    return other
  }
  if other.is_empty() {
    return self
  }
  let lo = join_lo(self, other)
  let hi = join_hi(self, other)
  { has_lo: lo.0, lo: lo.1, has_hi: hi.0, hi: hi.1, }
}

///|
/// `a ⊓ b` -- the intersection: `⊥` when they share no value.
pub fn Interval::meet(self : Interval, other : Interval) -> Interval {
  if self.is_empty() || other.is_empty() {
    return interval_bot()
  }
  let lo = meet_lo(self, other)
  let hi = meet_hi(self, other)
  { has_lo: lo.0, lo: lo.1, has_hi: hi.0, hi: hi.1, }
}

///|
/// The lower endpoint of a hull: a MISSING endpoint is `−∞`, which absorbs.
fn join_lo(a : Interval, b : Interval) -> (Bool, Int32) {
  if !a.has_lo || !b.has_lo {
    (false, 0)
  } else if a.lo <= b.lo {
    (true, a.lo)
  } else {
    (true, b.lo)
  }
}

///|
/// The upper endpoint of a hull: a MISSING endpoint is `+∞`, which absorbs.
fn join_hi(a : Interval, b : Interval) -> (Bool, Int32) {
  if !a.has_hi || !b.has_hi {
    (false, 0)
  } else if a.hi <= b.hi {
    (true, b.hi)
  } else {
    (true, a.hi)
  }
}

///|
/// The lower endpoint of an intersection: `−∞` loses to a finite bound.
fn meet_lo(a : Interval, b : Interval) -> (Bool, Int32) {
  if !a.has_lo {
    (b.has_lo, b.lo)
  } else if !b.has_lo {
    (true, a.lo)
  } else if a.lo <= b.lo {
    (true, b.lo)
  } else {
    (true, a.lo)
  }
}

///|
/// The upper endpoint of an intersection: `+∞` loses to a finite bound.
fn meet_hi(a : Interval, b : Interval) -> (Bool, Int32) {
  if !a.has_hi {
    (b.has_hi, b.hi)
  } else if !b.has_hi {
    (true, a.hi)
  } else if a.hi <= b.hi {
    (true, a.hi)
  } else {
    (true, b.hi)
  }
}

///|
/// `a.lo ≤ b.lo`, with a MISSING endpoint read as `−∞`, which is below
/// everything. Widening compares endpoints this way, so the sentinel has to
/// live in exactly one place.
fn lo_val_le(a : Interval, b : Interval) -> Bool {
  if !a.has_lo {
    true
  } else if !b.has_lo {
    false
  } else {
    a.lo <= b.lo
  }
}

///|
/// `a.hi ≤ b.hi`, with a MISSING endpoint read as `+∞`, which is above
/// everything.
fn hi_val_le(a : Interval, b : Interval) -> Bool {
  if !a.has_hi {
    !b.has_hi
  } else if !b.has_hi {
    true
  } else {
    a.hi <= b.hi
  }
}

///|
/// A rendering that always says ⊥, ∞ and the inclusive bounds, so a failing
/// test prints the interval rather than asserting one.
pub fn Interval::text(self : Interval) -> String {
  if self.is_empty() {
    return "⊥"
  }
  let l = if self.has_lo { self.lo.to_string() } else { "−∞" }
  let h = if self.has_hi { self.hi.to_string() } else { "+∞" }
  "[" + l + "," + h + "]"
}

// ---------------------------------------------------------------------------
// abstract evaluation (book p.80)
// ---------------------------------------------------------------------------
//
// eval(σ, X)      = σ(X)
// eval(σ, I)      = [I, I]
// eval(σ, input)  = [−∞, +∞]
// eval(σ, E1 op E2) = b_op(eval(σ,E1), eval(σ,E2))
//
// and b_op is defined through the SET of concrete results:
//
//     D = { x op y | x ∈ [l1,h1], y ∈ [l2,h2], x op y is defined }
//     b_op = ⊥ if D = ∅ else [min D, max D]
//
// Implemented below only for the arithmetic operators. A comparison's result
// is not an interval of integers in this analysis' use, and `OpMod` would need
// a sign analysis of its own; both answer `None`, and a caller that gets `None`
// must fall back to `full()` -- never to `⊥`, which would claim the expression
// has no value.

///|
/// `[l1,h1] + [l2,h2] = [l1+l2, h1+h2]` -- the book's own example is
/// `[1,10] + [−5,7] = [−4,17]` (p.80).
pub fn eval_add(a : Interval, b : Interval) -> Interval {
  if a.is_empty() || b.is_empty() {
    return interval_bot()
  }
  let lo = if a.has_lo && b.has_lo { (true, a.lo + b.lo) } else { (false, 0) }
  let hi = if a.has_hi && b.has_hi { (true, a.hi + b.hi) } else { (false, 0) }
  { has_lo: lo.0, lo: lo.1, has_hi: hi.0, hi: hi.1, }
}

///|
/// `[l1,h1] − [l2,h2] = [l1−h2, h1−l2]`.
pub fn eval_sub(a : Interval, b : Interval) -> Interval {
  if a.is_empty() || b.is_empty() {
    return interval_bot()
  }
  let lo = if a.has_lo && b.has_hi { (true, a.lo - b.hi) } else { (false, 0) }
  let hi = if a.has_hi && b.has_lo { (true, a.hi - b.lo) } else { (false, 0) }
  { has_lo: lo.0, lo: lo.1, has_hi: hi.0, hi: hi.1, }
}

///|
/// `[l1,h1] × [l2,h2]` -- the min and max of the four corner products.
///
/// AN UNBOUNDED OPERAND ANSWERS `full()`. The exact image of `[0,+∞) × 0` is
/// `0`, but every product rule that produces it needs the SIGN of the unbounded
/// side, and a sign is not in this domain. `full()` is the only answer that is
/// sound for all four sign combinations, and being less precise than the exact
/// image is allowed where being more precise would be a guess.
pub fn eval_mul(a : Interval, b : Interval) -> Interval {
  if a.is_empty() || b.is_empty() {
    return interval_bot()
  }
  if !(a.has_lo && a.has_hi && b.has_lo && b.has_hi) {
    return interval_full()
  }
  let p1 = a.lo * b.lo
  let p2 = a.lo * b.hi
  let p3 = a.hi * b.lo
  let p4 = a.hi * b.hi
  interval_range(
    min_i32(min_i32(p1, p2), min_i32(p3, p4)),
    max_i32(max_i32(p1, p2), max_i32(p3, p4)),
  )
}

///|
/// `[l1,h1] / [l2,h2]` -- the four corner quotients, and `full()` whenever the
/// divisor MAY be zero.
///
/// A DIVISOR THAT CONTAINS ZERO IS NOT AN EMPTY IMAGE. `[1,1] / [−1,1]` is
/// `{−1, 1}` in the concrete semantics with division-by-zero simply not
/// happening, and `⊥` would claim the expression never produces a value -- a
/// claim strong enough to make a later branch look infeasible. Truncating
/// integer division is non-monotone at the corners, which the book only hints
/// at ("x op y is defined"); answering `full()` there is the sound reading.
pub fn eval_div(a : Interval, b : Interval) -> Interval {
  if a.is_empty() || b.is_empty() {
    return interval_bot()
  }
  if !(a.has_lo && a.has_hi && b.has_lo && b.has_hi) {
    return interval_full()
  }
  if b.lo <= 0 && 0 <= b.hi {
    return interval_full()
  }
  let q1 = a.lo / b.lo
  let q2 = a.lo / b.hi
  let q3 = a.hi / b.lo
  let q4 = a.hi / b.hi
  interval_range(
    min_i32(min_i32(q1, q2), min_i32(q3, q4)),
    max_i32(max_i32(q1, q2), max_i32(q3, q4)),
  )
}

///|
/// The abstract operator for an AST binary operator, or `None` when this domain
/// does not model it. See the note above: a caller must read `None` as
/// `full()`, not as `⊥`.
pub fn eval_arith(op : @ast.BOp, a : Interval, b : Interval) -> Interval? {
  match op {
    @ast.OpAdd => Some(eval_add(a, b))
    @ast.OpSub => Some(eval_sub(a, b))
    @ast.OpMul => Some(eval_mul(a, b))
    @ast.OpDiv => Some(eval_div(a, b))
    _ => None
  }
}

///|
fn min_i32(a : Int32, b : Int32) -> Int32 {
  if a <= b {
    a
  } else {
    b
  }
}

///|
fn max_i32(a : Int32, b : Int32) -> Int32 {
  if a <= b {
    b
  } else {
    a
  }
}

// ---------------------------------------------------------------------------
// widening (book §6.2)
// ---------------------------------------------------------------------------
//
// Both operators are parameterised by `B`, "a finite set of integers together
// with −∞ and ∞" (p.82). The infinities are NOT stored in `B`: a missing
// endpoint already means an infinity, so `B` holds only the finite seeds and a
// lookup that finds nothing answers "unbounded". That keeps one representation
// of ∞ instead of two.

///|
/// `max { i ∈ B | i ≤ x }`, or `None` when no member of `B` is at most `x` --
/// which means the answer is `−∞`.
fn b_floor(b : Array[Int32], x : Int32) -> Int32? {
  let mut best : Int32? = None
  for i in b {
    if i <= x {
      match best {
        Some(cur) => if i > cur { best = Some(i) }
        None => best = Some(i)
      }
    }
  }
  best
}

///|
/// `min { i ∈ B | x ≤ i }`, or `None` when no member of `B` is at least `x` --
/// which means the answer is `+∞`.
fn b_ceil(b : Array[Int32], x : Int32) -> Int32? {
  let mut best : Int32? = None
  for i in b {
    if x <= i {
      match best {
        Some(cur) => if i < cur { best = Some(i) }
        None => best = Some(i)
      }
    }
  }
  best
}

///|
/// The SIMPLE widening `ω'` of book p.83:
///
///     ω'([l,h]) = [ max { i ∈ B | i ≤ l },  min { i ∈ B | h ≤ i } ]
///     ω'(⊥)     = ⊥
///
/// It moves EVERY endpoint onto `B`, whether or not it was the endpoint that
/// was moving, which is why the book calls it "sometimes unnecessarily
/// aggressive" (p.84) and why `widen_interval` exists beside it.
pub fn Interval::omega(self : Interval, b : Array[Int32]) -> Interval {
  if self.is_empty() {
    return interval_bot()
  }
  let lo = if self.has_lo {
    match b_floor(b, self.lo) {
      Some(i) => (true, i)
      None => (false, 0)
    }
  } else {
    (false, 0)
  }
  let hi = if self.has_hi {
    match b_ceil(b, self.hi) {
      Some(i) => (true, i)
      None => (false, 0)
    }
  } else {
    (false, 0)
  }
  { has_lo: lo.0, lo: lo.1, has_hi: hi.0, hi: hi.1, }
}

///|
/// The TRADITIONAL binary widening `∇'` of book p.93–94:
///
///     ⊥ ∇' y            = y
///     x ∇' ⊥            = x
///     [l1,h1] ∇' [l2,h2] = [l3, h3]
///     l3 = l1                    if l1 ≤ l2
///          max { i ∈ B | i ≤ l2 }  otherwise
///     h3 = h1                    if h2 ≤ h1
///          min { i ∈ B | h2 ≤ i }  otherwise
///
/// IT ONLY COARSENS AN ENDPOINT THAT MOVED. An endpoint that is stable between
/// iterations cannot be the reason the sequence diverges, so it is kept exactly
/// -- which is the whole difference from `omega`, and the reason the book's own
/// example reaches `x ↦ [8,8]` with this operator and `x ↦ [7,∞]` with the
/// other (p.84 vs p.86).
///
/// The two required properties are tested rather than asserted: it is an UPPER
/// BOUND (`a ⊑ a∇b` and `b ⊑ a∇b`), and it is EXTENSIVE in the sense that
/// matters -- iterating it over a growing sequence reaches a fixpoint.
pub fn widen_interval(
  prev : Interval,
  next : Interval,
  b : Array[Int32],
) -> Interval {
  if prev.is_empty() {
    return next
  }
  if next.is_empty() {
    return prev
  }
  let lo = if lo_val_le(prev, next) {
    (prev.has_lo, prev.lo)
  } else if !next.has_lo {
    (false, 0)
  } else {
    match b_floor(b, next.lo) {
      Some(i) => (true, i)
      None => (false, 0)
    }
  }
  let hi = if hi_val_le(next, prev) {
    (prev.has_hi, prev.hi)
  } else if !next.has_hi {
    (false, 0)
  } else {
    match b_ceil(b, next.hi) {
      Some(i) => (true, i)
      None => (false, 0)
    }
  }
  { has_lo: lo.0, lo: lo.1, has_hi: hi.0, hi: hi.1, }
}

// ---------------------------------------------------------------------------
// abstract states, and the widening fixpoint (book p.93)
// ---------------------------------------------------------------------------
//
// An abstract state is `Var → Interval`, held as an array indexed by a
// variable id so that join/equality are index-parallel and the iteration order
// of a map cannot leak into a test result.

///|
/// The `⊥` state for `n` variables: every variable is `⊥`, i.e. unreachable.
pub fn interval_state_bot(n : Int32) -> Array[Interval] {
  let s : Array[Interval] = []
  let mut i = 0
  while i < n {
    s.push(interval_bot())
    i = i + 1
  }
  s
}

///|
/// Pointwise `⊔`, over the shorter length if the two disagree -- which would be
/// a bug in the caller, and answering with a shorter array makes it visible
/// instead of silently truncating a longer one.
pub fn interval_state_join(
  a : Array[Interval],
  b : Array[Interval],
) -> Array[Interval] {
  let out : Array[Interval] = []
  let n = min_i32(a.length(), b.length())
  let mut i = 0
  while i < n {
    out.push(a[i].join(b[i]))
    i = i + 1
  }
  out
}

///|
/// Pointwise equality.
pub fn interval_state_same(a : Array[Interval], b : Array[Interval]) -> Bool {
  if a.length() != b.length() {
    return false
  }
  let mut i = 0
  while i < a.length() {
    if !a[i].same(b[i]) {
      return false
    }
    i = i + 1
  }
  true
}

///|
/// The `Lattice` instance the 0526 solvers want, for `n` variables.
pub fn interval_state_lattice(n : Int32) -> Lattice[Array[Interval]] {
  {
    bot: () => interval_state_bot(n),
    join: (a, b) => interval_state_join(a, b),
    eq: (a, b) => interval_state_same(a, b),
  }
}

///|
/// The outcome of a widening fixpoint. `converged` is a FIELD and not an
/// assumption: with a correct widening the sequence must reach a fixpoint, so a
/// result that stopped at the iteration cap is not a fixpoint and must not be
/// read as one. The cap exists because this tree would rather report its own
/// bound than hang.
pub(all) struct WidenResult[T] {
  states : Array[T]
  iterations : Int32
  converged : Bool
}

///|
/// `NaiveFixedPointAlgorithmWithWidening` (book p.93):
///
///     x := ⊥
///     repeat  t := x ; x := x ∇ f(x)  until  x = t
///
/// `f` is one round-robin sweep of the monotone framework -- the same transfer
/// and the same JOIN the 0526 solver uses -- so the widening is a change of ONE
/// operator, which is exactly the book's claim that "the other fixed-point
/// algorithms can be extended with this form of widening in a similar manner"
/// (p.93).
///
/// `widen : (node, prev, next) -> T` receives the PREVIOUS iteration's value,
/// because `∇` is binary: it needs what the endpoint was to decide whether it
/// moved. `at_node` says where to widen at all -- widening only at loop heads
/// is Exercise 6.13 and is more precise, so the choice is the caller's and is
/// visible in the signature rather than buried in this loop.
///
/// `transfer` and `widen` MUST NOT MUTATE their arguments. `prev` is a snapshot
/// of the array slots from the start of the sweep; an operator that wrote into
/// it would compare an endpoint against itself and never widen.
pub fn[T] solve_widening(
  lat : Lattice[T],
  n : Int32,
  preds : Array[Array[Int32]],
  transfer : (Int32, T) -> T,
  widen : (Int32, T, T) -> T,
  at_node : (Int32) -> Bool,
  max_iters : Int32,
) -> WidenResult[T] {
  let states : Array[T] = []
  let mut i = 0
  while i < n {
    states.push((lat.bot)())
    i = i + 1
  }
  let mut iters = 0
  let mut converged = false
  while iters < max_iters {
    iters = iters + 1
    // The previous iteration's values, by reference. Every write below
    // REPLACES a slot, so these references stay the old values -- see the
    // no-mutation contract above.
    let prev : Array[T] = []
    let mut p = 0
    while p < n {
      prev.push(states[p])
      p = p + 1
    }
    let mut changed = false
    let mut v = 0
    while v < n {
      let y = transfer(v, join_of_nodes(lat, states, preds[v]))
      let z = if at_node(v) { widen(v, prev[v], y) } else { y }
      if !(lat.eq)(states[v], z) {
        states[v] = z
        changed = true
      }
      v = v + 1
    }
    if !changed {
      converged = true
      break
    }
  }
  { states, iterations: iters, converged, }
}

///|
/// ONE NARROWING ROUND (book p.83): recompute `f` on the widened result.
///
/// `fω` is a safe upper bound of the least fixpoint, and `f(fω) ⊑ fω` while
/// still being a safe approximation, so applying `f` once improves the answer
/// without losing soundness. The book notes the decreasing sequence is NOT
/// guaranteed to converge in general (Exercise 6.8), which is why this is a
/// bounded NUMBER OF ROUNDS the caller asks for and not a loop to a fixpoint.
///
/// ONE CALL IS ONE SWEEP IN NODE ORDER, AND THAT IS NOT THE SAME AS `f(fω)`.
/// `f` is a function of the WHOLE state vector; a round-robin sweep visits the
/// node indices in order and therefore reads some nodes' PREVIOUS values. On
/// the book's own example (p.84) the difference is measurable: one sweep
/// leaves `x` at `[7,+∞]` because the loop head is visited before the back edge
/// is recomputed, and the SECOND sweep reaches the book's `[8,8]`. Exercise 6.7
/// asks how many narrowing steps are needed; the answer is a property of the
/// visit ORDER, so this function does one sweep and the caller counts.
pub fn[T] narrow_round(
  lat : Lattice[T],
  n : Int32,
  preds : Array[Array[Int32]],
  transfer : (Int32, T) -> T,
  states : Array[T],
) -> Array[T] {
  let out : Array[T] = []
  let mut i = 0
  while i < n {
    out.push(states[i])
    i = i + 1
  }
  let mut v = 0
  while v < n {
    out[v] = transfer(v, join_of_nodes(lat, out, preds[v]))
    v = v + 1
  }
  out
}
