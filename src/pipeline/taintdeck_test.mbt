// 0588: THE DECK'S CHAPTER 2, MEASURED ON ITS OWN EXAMPLE.
//
// THE DECK'S CHAPTER 2 (p.38-43) is CONFIDENTIALITY AND INTEGRITY, and the
// integrity slide carries the shape the whole chapter is about:
//
//     x = readInput();   // untrusted
//     cmd = "..." + x;
//     execute(cmd);      // critical (trusted)
//
// and p.41 names what that shape is: "Injection errors (#1 cause of
// vulnerabilities in 2013-2019) -- Command injection, SQL injection, XSS
// attacks".
//
// THE ANSWER IS MEASURED AND NOT ASSUMED, AND IT IS TWO ROWS. The first program
// is the deck's; the second is the deck's with the CONCATENATION removed. The
// first reports NOTHING. The second reports the flow.
//
// THE REASON IS THE POINTER ANALYSIS'S EXPRESSION MODEL, and it is the tree's
// own sentence: "ANYTHING ELSE IS EMPTY, AND THAT IS THE SOUND DIRECTION: this
// is a may-analysis, so a value the analysis does not model contributes no
// objects rather than an invented one" (`src/flow/pta.mbt`). A concatenation is
// a value the pointer analysis does not model -- it allocates a NEW string --
// so the tainted datum never enters `cmd`'s points-to set, and the deck's sink
// rule (p.76) has nothing to find.
//
// AND IT IS ALSO THE DECK'S OWN RULE TABLE. p.75 lists four rules -- New,
// Assign, Store, Load -- and none of them is a rule for a concatenation. The
// taint analysis is the pointer analysis plus a seed (0586), so it answers
// exactly what those four rules answer.
//
// SO THIS IS A BOUNDARY AND NOT AN OMISSION, and it is PINNED rather than
// promised: a boundary written down in prose is a promise, and a boundary
// written down in a TEST is a fact the next increment has to argue with.

///|
/// THE DECK'S INTEGRITY EXAMPLE (p.40), in MoonBit, with the deck's own line
/// numbers -- the source call on line 2 and the sink on line 4.
///
///     2    let x = read_input()     -- the deck's `x = readInput()`
///     3    let cmd = "..." + x      -- the deck's `cmd = "..." + x`
///     4    execute(cmd)             -- the deck's `execute(cmd)`
fn tdeck_concat_source() -> String {
  let lines = [
    "fn main {", "  let x = read_input()", "  let cmd = \"...\" + x", "  execute(cmd)",
    "}",
  ]
  lines.join("\n") + "\n"
}

///|
/// THE SAME PROGRAM WITH THE CONCATENATION REMOVED, and it is the CONTROL: the
/// two programs differ by ONE EXPRESSION, so the difference between the two
/// answers is that expression and nothing else.
fn tdeck_direct_source() -> String {
  let lines = ["fn main {", "  let x = read_input()", "  execute(x)", "}"]
  lines.join("\n") + "\n"
}

///|
/// The deck's specification, read off its own slide (p.40): the SOURCE is the
/// function whose result is untrusted, and the SINK is the call whose argument
/// must not receive it.
fn tdeck_spec() -> @flow.TaintSpec {
  let spec = @flow.taint_spec_empty()
  @flow.taint_spec_source(spec, "read_input")
  @flow.taint_spec_sink(spec, "execute", 0)
  spec
}

///|
/// THE SAME DERIVED VALUE, IN ITS OTHER SYNTACTIC FORM: an INTERPOLATION.
///
/// `let cmd = "prefix \{x}"` is not a concatenation in the AST -- the parser
/// reads it as a string literal that REFERENCES a name -- and it is measured
/// the same way, because the pointer analysis models neither: a string with an
/// interpolation has no objects in it, for the same reason a concatenation has
/// none.
fn tdeck_interp_source() -> String {
  let lines = [
    "fn main {", "  let x = read_input()", "  let cmd = \"prefix \\{x}\"", "  execute(cmd)",
    "}",
  ]
  lines.join("\n") + "\n"
}

///|
/// The module body of a source, parsed.
fn tdeck_body(src : String) -> Array[@ast.Stmt] {
  @parser.parse(src).tree.body
}

///|
/// THE DECK'S CHAPTER-2 EXAMPLE IS NOT REPORTED, and that is the measurement.
///
/// THE ROW IS HERE and not in a comment because a boundary written down in
/// prose is a promise, and the next increment has to be able to ARGUE WITH IT:
/// if a later increment closes this boundary, this row goes red and says so.
test "0588: the deck's chapter-2 example is not reported -- the concatenation is a value the analysis does not model" {
  let rs = @pipeline.taint_findings(
    tdeck_body(tdeck_concat_source()),
    [],
    tdeck_spec(),
  )
  assert_eq(rs.length(), 0)
}

///|
/// AND THE INTERPOLATION FORM IS NOT REPORTED EITHER, which is the other half
/// of the shape: a string that REFERENCES the tainted name is a value the
/// analysis does not model for the same reason a concatenation is not.
test "0588: the interpolation form is not reported either -- a string that references the tainted name is a value the analysis does not model" {
  let rs = @pipeline.taint_findings(
    tdeck_body(tdeck_interp_source()),
    [],
    tdeck_spec(),
  )
  assert_eq(rs.length(), 0)
}

///|
/// AND THE CONTROL: THE SAME PROGRAM WITHOUT THE CONCATENATION IS REPORTED.
///
/// This row is the one that makes the row above mean something. Without it, a
/// zero would say only that the specification did not match the program; with
/// it, the zero says the CONCATENATION is what the analysis does not follow.
test "0588: the same program without the concatenation IS reported, so the concatenation is the whole difference" {
  let rs = @pipeline.taint_findings(
    tdeck_body(tdeck_direct_source()),
    [],
    tdeck_spec(),
  )
  assert_eq(rs.length(), 1)
  assert_eq(rs[0].family.name(), "TaintFlow")
  assert_eq(
    rs[0].message,
    "the sensitive argument 0 of 'execute' may receive tainted data from 'read_input'",
  )
  assert_eq(rs[0].span.start.line, 3)
}
