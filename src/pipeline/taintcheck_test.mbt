// 0587: the taint finding, pinned to the deck's own example -- the PROGRAM
// parsed, not hand-built.
//
// THE SAME PROGRAM IS IN `src/flow/taint_test.mbt`, and the two are pinned to
// each other on purpose. The flow package does not import the parser (the
// framework stays below it), so its fixture is a hand-built AST; this one is
// real MoonBit source, read by the real frontend. If the parser built a
// different tree than the fixture assumes -- a call that is not an `ECall`, a
// `let` that is not an `Assign` -- the two answers would disagree, and the
// disagreement would be a fact about the ANALYZER rather than about the
// program.
//
// THE PROGRAM IS THE DECK'S (p.77), in MoonBit, with THE DECK'S OWN LINE
// NUMBERS: line 3 is the source call and line 7 is the sink, and the line
// numbers are the deck's IDENTIFIERS -- the deck's triple `<3, 7, 0>` is three
// call SITES.
//
// THE HELPER NAMES CARRY A PREFIX, because two test files in one package must
// not share a helper name, and this package holds a good many of them.

///|
/// THE DECK'S PROGRAM (p.77), in MoonBit, with the deck's own line numbers.
///
///     2    let x = A::{ f: "" }        -- the deck's `A x = new A()`
///     3    let pw = get_password()     -- the deck's `String pw = getPassword()`
///     4    let y = x                   -- the deck's `A y = x`
///     5    x.f = pw                    -- the deck's `x.f = pw`
///     6    let s = y.f                 -- the deck's `String s = y.f`
///     7    log(s)                      -- the deck's `log(s)`
fn tchk_deck_source() -> String {
  let lines = [
    "fn main {", "  let x = A::{ f: \"\" }", "  let pw = get_password()", "  let y = x",
    "  x.f = pw", "  let s = y.f", "  log(s)", "}",
  ]
  lines.join("\n") + "\n"
}

///|
/// The module body of a source, parsed.
fn tchk_body(src : String) -> Array[@ast.Stmt] {
  @parser.parse(src).tree.body
}

///|
/// THE DECK'S SPECIFICATION (p.77): Sources = { getPassword() } and
/// Sinks = { <log(String), 0> }.
fn tchk_deck_spec() -> @flow.TaintSpec {
  let spec = @flow.taint_spec_empty()
  @flow.taint_spec_source(spec, "get_password")
  @flow.taint_spec_sink(spec, "log", 0)
  spec
}

///|
test "0587: the deck's example, parsed: the sink is reported, with its source and its argument" {
  let rs = @pipeline.taint_findings(
    tchk_body(tchk_deck_source()),
    [],
    tchk_deck_spec(),
  )
  assert_eq(rs.length(), 1)
  assert_eq(rs[0].family.name(), "TaintFlow")
  assert_eq(
    rs[0].message,
    "the sensitive argument 0 of 'log' may receive tainted data from 'get_password'",
  )
  // THE SINK'S LINE, and it is line 7 -- the deck's own `log(s)`.
  assert_eq(rs[0].span.start.line, 7)
}

///|
test "0587: the same program with no sources produces no findings" {
  let spec = @flow.taint_spec_empty()
  @flow.taint_spec_sink(spec, "log", 0)
  let rs = @pipeline.taint_findings(tchk_body(tchk_deck_source()), [], spec)
  assert_eq(rs.length(), 0)
}

///|
test "0587: the same program with no sinks produces no findings" {
  let spec = @flow.taint_spec_empty()
  @flow.taint_spec_source(spec, "get_password")
  let rs = @pipeline.taint_findings(tchk_body(tchk_deck_source()), [], spec)
  assert_eq(rs.length(), 0)
}

///|
test "0587: a tainted value that never reaches a sink produces no findings" {
  let lines = ["fn main {", "  let pw = get_password()", "  let y = pw", "}"]
  let rs = @pipeline.taint_findings(
    tchk_body(lines.join("\n") + "\n"),
    [],
    tchk_deck_spec(),
  )
  assert_eq(rs.length(), 0)
}

///|
test "0587: two sources reaching two sinks are two findings, one at each sink" {
  let lines = [
    "fn main {", "  let a = get_password()", "  let b = read_token()", "  log(a)",
    "  log(b)", "}",
  ]
  let spec = @flow.taint_spec_empty()
  @flow.taint_spec_source(spec, "get_password")
  @flow.taint_spec_source(spec, "read_token")
  @flow.taint_spec_sink(spec, "log", 0)
  let rs = @pipeline.taint_findings(
    tchk_body(lines.join("\n") + "\n"),
    [],
    spec,
  )
  // TWO sink calls, on two lines, and therefore TWO findings.
  assert_eq(rs.length(), 2)
  assert_eq(rs[0].span.start.line, 4)
  assert_eq(
    rs[0].message,
    "the sensitive argument 0 of 'log' may receive tainted data from 'get_password'",
  )
  assert_eq(rs[1].span.start.line, 5)
  assert_eq(
    rs[1].message,
    "the sensitive argument 0 of 'log' may receive tainted data from 'read_token'",
  )
}

///|
test "0587: two sources reaching ONE sink call are one finding that names both" {
  // BOTH tainted data reach the same field, and the field reaches the sink.
  // The pipeline's merge -- one finding per family per LINE -- would collapse
  // the two flows into one finding with ONE of the two messages, so the group
  // names both and the report does not lose one.
  let lines = [
    "fn main {", "  let x = A::{ f: \"\" }", "  let a = get_password()", "  let b = read_token()",
    "  x.f = a", "  x.f = b", "  log(x.f)", "}",
  ]
  let spec = @flow.taint_spec_empty()
  @flow.taint_spec_source(spec, "get_password")
  @flow.taint_spec_source(spec, "read_token")
  @flow.taint_spec_sink(spec, "log", 0)
  let rs = @pipeline.taint_findings(
    tchk_body(lines.join("\n") + "\n"),
    [],
    spec,
  )
  assert_eq(rs.length(), 1)
  assert_eq(
    rs[0].message,
    "the sensitive argument 0 of 'log' may receive tainted data from 'read_token' or 'get_password'",
  )
}

///|
test "0587: a sink with two sensitive arguments names both of them" {
  let lines = ["fn main {", "  let pw = get_password()", "  log(pw, pw)", "}"]
  let spec = @flow.taint_spec_empty()
  @flow.taint_spec_source(spec, "get_password")
  @flow.taint_spec_sink(spec, "log", 0)
  @flow.taint_spec_sink(spec, "log", 1)
  let rs = @pipeline.taint_findings(
    tchk_body(lines.join("\n") + "\n"),
    [],
    spec,
  )
  // ONE sink call, and therefore ONE finding -- and it names both arguments,
  // because the merge would have kept only one of the two messages.
  assert_eq(rs.length(), 1)
  assert_eq(
    rs[0].message,
    "the sensitive arguments 0 and 1 of 'log' may receive tainted data from 'get_password'",
  )
}

///|
test "0587: the finding carries a checkable predicate" {
  let rs = @pipeline.taint_findings(
    tchk_body(tchk_deck_source()),
    [],
    tchk_deck_spec(),
  )
  assert_eq(rs.length(), 1)
  match rs[0].predicate() {
    Some(p) => {
      assert_eq(p.check, "taint_reaches_sink")
      assert_eq(
        p.render(),
        "taint_reaches_sink(sink=log, source=get_password, arg=0, line=7, col=3)",
      )
    }
    None => assert_true(false)
  }
}

///|
/// The AST helpers for the ONE case the parser cannot produce: TWO sink calls
/// on ONE line.
///
/// MOONBIT PUTS ONE STATEMENT ON A LINE, so a parsed program cannot carry two
/// sink calls on one line -- and the pipeline's merge collapses a family to one
/// finding per LINE, so that case is the one where a finding could lose a
/// sink. The AST is built by hand here so that the case is pinned rather than
/// assumed away.
fn tchk_span(line : Int32, col : Int32) -> @core.Span {
  @core.span_at(line, col, 1)
}

///|
fn tchk_name(line : Int32, n : String) -> @ast.Expr {
  { span: tchk_span(line, 3), kind: @ast.EName(n), }
}

///|
fn tchk_call(line : Int32, f : String, args : Array[@ast.Expr]) -> @ast.Expr {
  { span: tchk_span(line, 3), kind: @ast.ECall(f, args, []), }
}

///|
fn tchk_stmt(line : Int32, col : Int32, e : @ast.Expr) -> @ast.Stmt {
  { span: tchk_span(line, col), kind: @ast.SExpr(e), }
}

///|
/// The FUNCTION the module body carries, because `taint_findings` reads the
/// MODULE's body and a bare list of statements is not a module.
fn tchk_main(body : Array[@ast.Stmt]) -> @ast.Stmt {
  {
    span: @core.span_at(1, 1, 1),
    kind: @ast.SFunc("main", [], "", body, @core.span_at(1, 1, 1)),
  }
}

///|
fn tchk_let(line : Int32, x : String, e : @ast.Expr) -> @ast.Stmt {
  { span: tchk_span(line, 3), kind: @ast.SLet(x, "", e), }
}

///|
test "0587: two sink calls on ONE line are ONE call site, and the finding names the first of them" {
  // THE CALL SITE IS THE LINE, and that is this tree's own identity: a tainted
  // datum is named after its call site's line (`t3`), an allocation after its
  // site's line (`o3`), and the deck's triple is (source call site, sink call
  // site, argument index). Two sink calls on ONE line are therefore ONE call
  // site, and the deck's set of triples has one entry for them.
  //
  // THE TWO CALLS ARE AT DIFFERENT COLUMNS so that the SOURCE ORDER is
  // unambiguous: the graph's order is by (line, column), and with equal
  // columns the order would be the node index -- which the builder allocates
  // from the LAST statement backwards.
  let body = [
    tchk_main([
      tchk_let(2, "a", tchk_call(2, "get_password", [])),
      tchk_stmt(3, 3, tchk_call(3, "log", [tchk_name(3, "a")])),
      tchk_stmt(3, 10, tchk_call(3, "audit", [tchk_name(3, "a")])),
    ]),
  ]
  let spec = @flow.taint_spec_empty()
  @flow.taint_spec_source(spec, "get_password")
  @flow.taint_spec_sink(spec, "log", 0)
  @flow.taint_spec_sink(spec, "audit", 0)
  let rs = @pipeline.taint_findings(body, [], spec)
  // ONE call site, and therefore ONE triple and ONE finding.
  assert_eq(rs.length(), 1)
  assert_eq(
    rs[0].message,
    "the sensitive argument 0 of 'log' may receive tainted data from 'get_password'",
  )
  // AND THE PREDICATE READS THE SINK OUT OF ITS OWN HALF OF THE MESSAGE.
  match rs[0].predicate() {
    Some(p) => {
      assert_eq(p.check, "taint_reaches_sink")
      assert_eq(
        p.render(),
        "taint_reaches_sink(sink=log, source=get_password, arg=0, line=3, col=3)",
      )
    }
    None => assert_true(false)
  }
}

///|
test "0587: a function the frontend did not read whole is not analysed" {
  // The region is the frontend's own, and the geometry is the walk's: the
  // unread span is INSIDE the function's extent.
  let body = tchk_body(tchk_deck_source())
  let unread = [@core.span_at(6, 3, 2)]
  let rs = @pipeline.taint_findings(body, unread, tchk_deck_spec())
  assert_eq(rs.length(), 0)
}
