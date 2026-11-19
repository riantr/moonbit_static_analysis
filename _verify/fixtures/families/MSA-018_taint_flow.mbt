// family: MSA-018
//
// shape: a tainted value reaching a sensitive argument.
//
// AND THE TWO NAMES THE SWEEP NEEDS ARE DECLARED HERE, because the
// sweep reads them from THIS file: a name written down twice is a name
// that will disagree with itself.
//
// taint-source: qa0613_taint_source
// taint-sink: qa0613_taint_sink:0
fn qa0613_taint_source() -> String {
  "x"
}
fn qa0613_taint_sink(s_0613 : String) -> Unit {
  println(s_0613)
}
fn qa0613_taint_flow() -> Unit {
  let qa0613_v = qa0613_taint_source()
  qa0613_taint_sink(qa0613_v)
}
qa0613_taint_flow()
