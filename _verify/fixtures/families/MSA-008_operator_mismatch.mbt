// family: MSA-008
//
// shape: THE TYPE LENS ALONE, for the same reason as MSA-007. `!` on a
// known Int is a type error and nothing else: the behavioral lens has no
// opinion about it, so there is no echo to merge with and this family is
// the one that survives.
fn qa0613_probe(n_0613 : Int) -> Bool {
  !n_0613
}
qa0613_probe(1)
