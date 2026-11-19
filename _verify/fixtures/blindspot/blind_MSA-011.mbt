// family: MSA-011
//
// THE BLIND SPOT. The defect above is the same defect the family's own
// fixture carries -- the only difference is that here it sits inside a
// `test` body, and a `test` body is OUTSIDE the analyzed subset.
//
// So this file reports NOTHING actionable. It reports one notice -- the
// test declaration -- and that notice is the analyzer saying that it did
// not read this, which is TRUE and is the point.
//
// shape: the defect, wrapped in a `test` declaration.
test "blind spot MSA-011" {
fn qa0613_f(x_0613 : Int) -> Int {
  return x_0613
  println(x_0613)
}
}
