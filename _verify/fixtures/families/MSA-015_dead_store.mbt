// family: MSA-015
//
// shape: a binding written twice with nothing reading it in between. It
// produces TWO findings, and the census counts both -- a family that
// fires twice is still a family that fires.
fn qa0613_f() -> Int {
  let mut qa0613_e = 0
  qa0613_e = 1
  qa0613_e = 2
  qa0613_e
}
qa0613_f()
