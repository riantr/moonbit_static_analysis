// The sign domain's own laws, and the deck's transfer table.
//
// THE DECK'S TABLE IS PINNED ROW BY ROW. `Introduction` (Yue Li, Nanjing
// University) prints it on p.54 and p.56, and every row is asserted here --
// including the rows the deck does NOT print, which are marked as derived, so
// a reader can tell the two apart.
//
// WHY THE EXAMPLE IS NOT HERE. The worked example (p.56) needs a PARSED
// program, and this package imports `ast` and nothing else on purpose: the
// framework is below the frontend, and `--deny-warn` treats a test-only import
// as an error (`unused_package`). So the example is pinned in the package that
// owns the parse-to-graph path -- `src/pipeline/signcheck_test.mbt` -- and what
// is pinned HERE is the table the example's answer comes from.

///|
/// Every element of the domain, for the laws that enumerate every pair.
fn all_signs() -> Array[@flow.Sign] {
  [@flow.SBot, @flow.SZero, @flow.SPos, @flow.SNeg, @flow.STop]
}

///|
/// The deck's ADDITION table (p.54, p.56), row by row.
test "0571: the deck's addition table, row by row" {
  assert_true(@flow.sign_add(@flow.SPos, @flow.SPos) == @flow.SPos)
  assert_true(@flow.sign_add(@flow.SNeg, @flow.SNeg) == @flow.SNeg)
  assert_true(@flow.sign_add(@flow.SZero, @flow.SZero) == @flow.SZero)
  assert_true(@flow.sign_add(@flow.SPos, @flow.SNeg) == @flow.STop)
  // The deck prints the two orders of the conflicting row as one, and the
  // other order is the same fact: a sum is commutative.
  assert_true(@flow.sign_add(@flow.SNeg, @flow.SPos) == @flow.STop)
  // DERIVED, and the derivation is the deck's own rule: the sum's sign is
  // determined exactly when the two operands have the SAME sign. `+ + O` is
  // not printed on the slide, and it is right that it is not -- the sum of a
  // positive number and a zero is either zero or positive.
  assert_true(@flow.sign_add(@flow.SPos, @flow.SZero) == @flow.STop)
  assert_true(@flow.sign_add(@flow.SZero, @flow.SZero) == @flow.SZero)
  // The bottom and the top survive both operands: an undefined value makes
  // the sum undefined, and an unknown one makes it unknown.
  assert_true(@flow.sign_add(@flow.SBot, @flow.SPos) == @flow.SBot)
  assert_true(@flow.sign_add(@flow.STop, @flow.SPos) == @flow.STop)
}

///|
/// The deck's DIVISION table (p.54, p.56), row by row.
test "0571: the deck's division table, row by row" {
  assert_true(@flow.sign_div(@flow.SPos, @flow.SPos) == @flow.SPos)
  assert_true(@flow.sign_div(@flow.SNeg, @flow.SNeg) == @flow.SPos)
  // `T / O = ⊥` -- the deck's division-by-zero row.
  assert_true(@flow.sign_div(@flow.STop, @flow.SZero) == @flow.SBot)
  assert_true(@flow.sign_div(@flow.SPos, @flow.SNeg) == @flow.SNeg)
  assert_true(@flow.sign_div(@flow.SZero, @flow.SNeg) == @flow.SZero)
  // DERIVED, and it is the row the first application rests on: a divisor that
  // is zero makes the expression have NO value, whatever the numerator is,
  // because the program fails before it can have one.
  assert_true(@flow.sign_div(@flow.SPos, @flow.SZero) == @flow.SBot)
  assert_true(@flow.sign_div(@flow.SNeg, @flow.SZero) == @flow.SBot)
  assert_true(@flow.sign_div(@flow.SZero, @flow.SZero) == @flow.SBot)
  // A zero numerator over a NON-zero divisor is zero, and an unknown operand
  // over a known-nonzero divisor is unknown.
  assert_true(@flow.sign_div(@flow.SZero, @flow.SPos) == @flow.SZero)
  assert_true(@flow.sign_div(@flow.STop, @flow.SPos) == @flow.STop)
}

///|
/// DERIVED ROWS: the multiplication and the subtraction, which the deck's table
/// does not print (its "… …" on p.56).
test "0571: the multiplication and the subtraction, derived" {
  // The product's sign is determined when both operands are.
  assert_true(@flow.sign_mul(@flow.SPos, @flow.SPos) == @flow.SPos)
  assert_true(@flow.sign_mul(@flow.SNeg, @flow.SNeg) == @flow.SPos)
  assert_true(@flow.sign_mul(@flow.SPos, @flow.SNeg) == @flow.SNeg)
  // A zero factor gives zero whatever the other factor is: `0 * unknown = 0`
  // is a FACT, not an imprecision, because the product is zero however much
  // the other factor varies.
  assert_true(@flow.sign_mul(@flow.SZero, @flow.STop) == @flow.SZero)
  assert_true(@flow.sign_mul(@flow.STop, @flow.SZero) == @flow.SZero)
  assert_true(@flow.sign_mul(@flow.STop, @flow.SPos) == @flow.STop)
  // `x - 0` is `x`, which is the one refinement the derivation needs: a zero
  // right-hand side does not blur the left-hand side's sign.
  assert_true(@flow.sign_sub(@flow.SPos, @flow.SZero) == @flow.SPos)
  assert_true(@flow.sign_sub(@flow.SNeg, @flow.SZero) == @flow.SNeg)
  // Otherwise the subtraction is an addition of the negated right-hand side.
  assert_true(@flow.sign_sub(@flow.SPos, @flow.SNeg) == @flow.SPos)
  assert_true(@flow.sign_sub(@flow.SNeg, @flow.SPos) == @flow.SNeg)
  assert_true(@flow.sign_sub(@flow.SPos, @flow.SPos) == @flow.STop)
}

///|
/// THE LATTICE LAWS, over the whole carrier.
///
/// The carrier is finite -- five elements -- so every law is decided by
/// trying every pair, which is the same argument `laws_test.mbt` makes for the
/// other two finite lattices in this package.
test "0571: the sign domain is a lattice" {
  let xs = all_signs()
  let mut i = 0
  while i < xs.length() {
    let mut j = 0
    while j < xs.length() {
      let a = xs[i]
      let b = xs[j]
      // COMMUTATIVE.
      assert_true(@flow.sign_join(a, b) == @flow.sign_join(b, a))
      // IDEMPOTENT.
      assert_true(@flow.sign_join(a, a) == a)
      // THE BOTTOM IS A BOTTOM.
      assert_true(@flow.sign_join(@flow.SBot, a) == a)
      // THE JOIN IS AN UPPER BOUND of both.
      assert_true(@flow.sign_leq(a, @flow.sign_join(a, b)))
      assert_true(@flow.sign_leq(b, @flow.sign_join(a, b)))
      let mut k = 0
      while k < xs.length() {
        let c = xs[k]
        // ASSOCIATIVE.
        assert_true(
          @flow.sign_join(@flow.sign_join(a, b), c) ==
          @flow.sign_join(a, @flow.sign_join(b, c)),
        )
        k = k + 1
      }
      j = j + 1
    }
    i = i + 1
  }
}

///|
/// The ORDER the join is the least upper bound in, stated directly: the bottom
/// is below everything, the top is above everything, and two DIFFERENT
/// concrete signs are incomparable.
test "0571: the order is the deck's: bottom, three incomparable signs, top" {
  assert_true(@flow.sign_leq(@flow.SBot, @flow.SZero))
  assert_true(@flow.sign_leq(@flow.SBot, @flow.SPos))
  assert_true(@flow.sign_leq(@flow.SBot, @flow.SNeg))
  assert_true(@flow.sign_leq(@flow.SZero, @flow.STop))
  assert_true(@flow.sign_leq(@flow.SPos, @flow.STop))
  assert_true(@flow.sign_leq(@flow.SNeg, @flow.STop))
  assert_false(@flow.sign_leq(@flow.SZero, @flow.SPos))
  assert_false(@flow.sign_leq(@flow.SPos, @flow.SNeg))
  assert_false(@flow.sign_leq(@flow.STop, @flow.SZero))
}

///|
/// THE STATE LATTICE: a map of names to signs, joined pointwise.
test "0571: the state join is pointwise, and a missing name is the bottom" {
  let a : @flow.SignState = Map([("x", @flow.SPos)])
  let b : @flow.SignState = Map([("x", @flow.SNeg), ("y", @flow.SZero)])
  let j = @flow.sign_state_join(a, b)
  // x is positive on one path and negative on the other: the sign is not
  // determined, so the join is unknown.
  assert_true(j.get("x") == Some(@flow.STop))
  // y is on one path only, and the other path's value for it is the BOTTOM --
  // so the join takes the one value there is.
  assert_true(j.get("y") == Some(@flow.SZero))
  // The join is commutative, as the lattice says.
  let j2 = @flow.sign_state_join(b, a)
  assert_true(j2.get("x") == Some(@flow.STop))
  assert_true(j2.get("y") == Some(@flow.SZero))
  assert_true(@flow.sign_state_eq(j, j2))
}

///|
/// THE STATE'S CONVENTION: setting the bottom REMOVES the name, so "no value"
/// has exactly one representation -- the same rule `cprop_set` states for
/// `Undef`.
test "0571: a name with no value is absent, not present-and-bottom" {
  let st = @flow.sign_state_set(Map([]), "x", @flow.SPos)
  assert_true(st.get("x") == Some(@flow.SPos))
  let st2 = @flow.sign_state_set(st, "x", @flow.SBot)
  assert_true(st2.get("x") == None)
  assert_true(st2.contains("x") == false)
}
