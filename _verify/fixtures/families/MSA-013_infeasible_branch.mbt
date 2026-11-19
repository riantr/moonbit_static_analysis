// family: MSA-013
//
// shape: a branch that can never run, because the outer test contradicts
// the inner one.
fn qa0613_f(x_0613 : Int) -> Unit {
  if x_0613 > 5 {
    if x_0613 < 3 {
      println("never")
    }
  }
}
qa0613_f(1)
