// family: MSA-002
//
// shape: a name that does not resolve.
//
// AND THIS FAMILY IS REPORTED AT LOW CONFIDENCE, so 0508 renders it a
// NOTICE and it is NOT an actionable finding. It is in the census as
// `low=1`, and the census is the table -- not the finding count -- so it
// counts here exactly as the other seventeen do.
fn qa0613_g() -> Int {
  return qa0613_missing + 1
}
qa0613_g()
