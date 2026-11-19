// family: MSA-014
//
// shape: a guard that decides nothing, because the outer test already
// implies the inner one.
fn qa0613_f(x_0613 : Int) -> Unit {
  if x_0613 > 10 {
    if x_0613 > 5 {
      println("yes")
    }
  }
}
qa0613_f(1)
