// family: MSA-015
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
test "blind spot MSA-015" {
fn qa0613_f() -> Int {
  let mut qa0613_e = 0
  qa0613_e = 1
  qa0613_e = 2
  qa0613_e
}
}
