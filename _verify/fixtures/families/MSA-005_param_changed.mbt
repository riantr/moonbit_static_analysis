// family: MSA-005
//
// shape: a parameter that is assigned to, so the caller's value is lost.
fn qa0613_f(_p_0613 : Int) -> Int {
  _p_0613 = 1
  _p_0613
}
qa0613_f(1)
