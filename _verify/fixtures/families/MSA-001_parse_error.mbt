// family: MSA-001
//
// THIS FAMILY CAN ONLY EVER BE A NOTICE in the census, and that is the
// shape a census row needs. A file that fails to parse has its findings
// WITHHELD -- the SUMMARY's `unreliable=` and `withheld=` counters carry
// that, and a withheld finding contributes NO row to the census at all.
// So the half of this family that a census can see is the other half: a
// DECLARED SCOPE LIMIT -- a construct the analyzer read and did not
// analyse. A `test` declaration is one.
// shape: a `test` declaration, whose body the analyzer does not analyse.
test "MSA-001 scope limit" {
  let x = 1
  x
}
