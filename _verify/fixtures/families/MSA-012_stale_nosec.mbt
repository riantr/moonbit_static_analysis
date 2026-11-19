// family: MSA-012
//
// shape: a suppression that suppresses NOTHING -- the comment names a
// line that carries no finding. That is the only shape this family has.
//
// AND IT IS ONLY VISIBLE WHEN THE ANALYZER HONOURS SUPPRESSIONS, so the
// sweep runs with that flag on: without it the analyzer never reads the
// comment and there is nothing that could be stale about it. The word
// itself is spelled out in this paragraph rather than written, because a
// header that quoted it would be read as a suppression of MSA-012 on the
// header's own line -- and a suppression that suppresses nothing is
// exactly the finding this file is supposed to produce.
fn qa0613_f() -> Int {
  // nosec
  let qa0613_ok = 1
  qa0613_ok
}
qa0613_f()
