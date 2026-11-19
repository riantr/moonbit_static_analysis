// family: MSA-003
//
// shape: a local binding that is written and never read.
fn qa0613_f() -> Int {
  let qa0613_z = 1
  return 2
}
qa0613_f()
