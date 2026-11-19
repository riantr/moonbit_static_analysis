// family: MSA-007
//
// shape: THE TYPE LENS ALONE, and the shape is the whole point of this
// file. MSA-007 shares the `arg-type` merge group with MSA-008 and
// MSA-009, and a merged finding keeps the family of the HIGHEST-RANKED
// lens -- behavior beats type beats structural. So the call must sit in a
// function NOTHING CALLS: then the behavioral lens never executes the
// body, there is no echo to merge with, and the type lens's own family
// survives. Put the same call in a function that IS called and the family
// that survives is MSA-009, not this one.
//
// THERE IS NO `--lens` FLAG. This is a property of the FIXTURE.
fn qa0613_g(a : Int) -> Int {
  a
}
fn qa0613_never_called() -> Int {
  qa0613_g("s")
}
