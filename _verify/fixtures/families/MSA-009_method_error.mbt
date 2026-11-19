// family: MSA-009
//
// shape: a call whose argument does not match the callee's signature,
// IN A FUNCTION THAT IS CALLED -- so this one is seen by the behavioral
// lens too, and it is the highest-ranked lens, so this is the family
// that survives the `arg-type` merge. MSA-007 and MSA-008 are the two
// that need the type lens alone; this is the one that does not.
fn qa0613_f(x_0613 : Int) -> Int {
  x_0613
}
fn qa0613_c() -> Int {
  qa0613_f(true)
}
qa0613_c()
