// family: MSA-017
//
// shape: a subscript whose index is definitely negative.
fn qa0613_f() -> Int {
  let qa0613_a = [1, 2, 3]
  let qa0613_p = qa0613_a[0 - 1]
  qa0613_p
}
qa0613_f()
