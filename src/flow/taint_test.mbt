// 0586: the taint layer, pinned to the security deck's own worked example.
//
// THE DECK. `Static Analysis for Security` (Tian Tan, Nanjing University),
// p.77-85. The example is a SEVEN-STATEMENT program, and the deck walks it
// one slide at a time, printing the points-to table after each step:
//
//     p.77   the program, with Sources = { getPassword() } and
//            Sinks = { <log(String), 0> }
//     p.79   after line 3:   x -> o2        pw -> o11, t3
//     p.81   after line 4:   y -> o2
//     p.82   after line 5:   o2.f -> o11, t3
//     p.83   after line 6:   s  -> o11, t3
//     p.84   after line 7:   TaintFlows: { <3, 7, 0> }
//
// THE DECK'S PROGRAM IS JAVA, so the fixture here is its MoonBit translation
// with THE DECK'S OWN LINE NUMBERS -- line 2 is the allocation, line 3 is the
// source call, line 7 is the sink. The line numbers are not decoration: they
// are the deck's IDENTIFIERS. The deck names an object after its allocation
// site's line (`o2`, `o11`) and a tainted datum after its call site's line
// (`t3`), and the triple it prints is three call sites -- so a fixture whose
// lines did not match would be testing a different program.
//
// ONE DIFFERENCE FROM THE DECK'S TABLES, AND IT IS MEASURED, NOT ASSUMED.
//
// The deck's `o11` is the object the source call RETURNED -- `new String(...)`
// on line 11, inside `getPassword`. This tree's pointer analysis does not
// model what a call returns (`pta.mbt`: "a call that happens to return a fresh
// object is exactly what this analysis does not model"), so there is no `o11`
// here and `pw` points to the tainted datum ALONE. The MoonBit translation
// fills the field instead of leaving it null, so `o2.f` also holds the field's
// initial value -- the empty string, which the pointer analysis treats as an
// object (p.59: "a literal is an object").
//
// The DECK'S ANSWER IS THE SAME. `TaintFlows: { <3, 7, 0> }` is what this
// analysis produces, and the rows below pin it.
//
// THE AST IS BUILT BY HAND, and not parsed, because `src/flow` does not import
// the parser -- the framework stays below it (`src/flow/moon.pkg`). The parser
// is exercised on the SAME program by `src/pipeline/taintcheck_test.mbt`, so
// the hand-built tree and the parsed tree are pinned to each other.

///|
fn tn_span(line : Int32) -> @core.Span {
  { start: @core.pos(line, 1), end: @core.pos(line, 1), }
}

///|
fn tn_name(line : Int32, n : String) -> @ast.Expr {
  { span: tn_span(line), kind: @ast.EName(n), }
}

///|
fn tn_str(line : Int32, v : String) -> @ast.Expr {
  { span: tn_span(line), kind: @ast.EStr(v, []), }
}

///|
fn tn_call(line : Int32, f : String, args : Array[@ast.Expr]) -> @ast.Expr {
  { span: tn_span(line), kind: @ast.ECall(f, args, []), }
}

///|
fn tn_method(line : Int32, recv : @ast.Expr, m : String) -> @ast.Expr {
  { span: tn_span(line), kind: @ast.EMethodCall(recv, m, [], []), }
}

///|
fn tn_dotdot(line : Int32, recv : @ast.Expr, m : String) -> @ast.Expr {
  { span: tn_span(line), kind: @ast.EDotDot(recv, m, [], []), }
}

///|
fn tn_struct(
  line : Int32,
  ty : String,
  fields : Array[(String, @ast.Expr)],
) -> @ast.Expr {
  { span: tn_span(line), kind: @ast.EStruct(ty, fields), }
}

///|
fn tn_field(line : Int32, b : @ast.Expr, f : String) -> @ast.Expr {
  { span: tn_span(line), kind: @ast.EField(b, f), }
}

///|
fn tn_let(line : Int32, x : String, e : @ast.Expr) -> @ast.Stmt {
  { span: tn_span(line), kind: @ast.SLet(x, "", e), }
}

///|
fn tn_assign(line : Int32, lhs : @ast.Expr, rhs : @ast.Expr) -> @ast.Stmt {
  { span: tn_span(line), kind: @ast.SAssign(lhs, rhs), }
}

///|
fn tn_expr(line : Int32, e : @ast.Expr) -> @ast.Stmt {
  { span: tn_span(line), kind: @ast.SExpr(e), }
}

///|
fn tn_set(xs : Array[String]) -> Map[String, Bool] {
  let m = Map([])
  for x in xs {
    m.set(x, true)
  }
  m
}

///|
/// THE DECK'S `main` (p.77, lines 1-8), in MoonBit, with the deck's lines.
///
///     2    let x = A::{ f: "" }        -- the deck's `A x = new A()`
///     3    let pw = get_password()     -- the deck's `String pw = getPassword()`
///     4    let y = x                   -- the deck's `A y = x`
///     5    x.f = pw                    -- the deck's `x.f = pw`
///     6    let s = y.f                 -- the deck's `String s = y.f`
///     7    log(s)                      -- the deck's `log(s)`
fn tn_deck_main() -> Array[@ast.Stmt] {
  [
    tn_let(2, "x", tn_struct(2, "A", [("f", tn_str(2, ""))])),
    tn_let(3, "pw", tn_call(3, "get_password", [])),
    tn_let(4, "y", tn_name(4, "x")),
    tn_assign(5, tn_field(5, tn_name(5, "x"), "f"), tn_name(5, "pw")),
    tn_let(6, "s", tn_field(6, tn_name(6, "y"), "f")),
    tn_expr(7, tn_call(7, "log", [tn_name(7, "s")])),
  ]
}

///|
/// THE DECK'S `getPassword` (p.77, lines 9-12).
fn tn_deck_get_password() -> Array[@ast.Stmt] {
  [
    tn_let(10, "secret", tn_str(10, "s3cret")),
    tn_expr(11, tn_name(11, "secret")),
  ]
}

///|
/// THE DECK'S SPECIFICATION (p.77): Sources = { getPassword() } and
/// Sinks = { <log(String), 0> }.
fn tn_deck_spec() -> @flow.TaintSpec {
  let spec = @flow.taint_spec_empty()
  @flow.taint_spec_source(spec, "get_password")
  @flow.taint_spec_sink(spec, "log", 0)
  spec
}

///|
/// The deck's program, as the two graphs the analysis runs over.
fn tn_deck_cfgs() -> Array[@flow.Cfg] {
  [@flow.cfg_of(tn_deck_main()), @flow.cfg_of(tn_deck_get_password())]
}

///|
test "0586: the deck's example: the tainted datum is t3 and the allocation is o2" {
  let r = @flow.taint_analyze(tn_deck_cfgs(), tn_deck_spec())
  let pt = r.pts[0]
  // p.79: `x -> o2`. The allocation site is on line 2, and the object is named
  // after its site's line -- the deck's own naming (p.45-47, p.77).
  assert_true(@flow.name_set_eq(@flow.pta_of(pt, "x"), tn_set(["o2"])))
  // p.79: `pw -> o11, t3`. THE `o11` IS NOT HERE -- the object the source call
  // returned is not modelled -- so the tainted datum is ALONE. That is the
  // measured difference from the deck's table, and the row that pins it.
  assert_true(@flow.name_set_eq(@flow.pta_of(pt, "pw"), tn_set(["t3"])))
}

///|
test "0586: the deck's example: the copy on line 4 shares the allocation" {
  let r = @flow.taint_analyze(tn_deck_cfgs(), tn_deck_spec())
  let pt = r.pts[0]
  // p.81: `y -> o2`. The deck's Assign rule, and the tree's own.
  assert_true(@flow.name_set_eq(@flow.pta_of(pt, "y"), tn_set(["o2"])))
}

///|
test "0586: the deck's example: the store on line 5 and the load on line 6 carry the tainted datum" {
  let r = @flow.taint_analyze(tn_deck_cfgs(), tn_deck_spec())
  let pt = r.pts[0]
  // p.82: `o2.f -> o11, t3`. The deck's Store rule -- and the field also holds
  // its initial value, the empty string, which the pointer analysis treats as
  // an object (p.59).
  let field = @flow.pta_of(pt, "o2.f")
  assert_true(field.contains("t3"))
  assert_eq(field.length(), 2)
  // p.83: `s -> o11, t3`. The deck's Load rule.
  let s = @flow.pta_of(pt, "s")
  assert_true(s.contains("t3"))
  assert_eq(s.length(), 2)
}

///|
test "0586: the deck's answer: TaintFlows is { <3, 7, 0> }" {
  let r = @flow.taint_analyze(tn_deck_cfgs(), tn_deck_spec())
  // p.84. The triple is (source call site, sink call site, argument index),
  // and every one of the three is the deck's own.
  assert_eq(r.flows.length(), 1)
  assert_eq(r.flows[0].src_line, 3)
  assert_eq(r.flows[0].sink_line, 7)
  assert_eq(r.flows[0].arg, 0)
}

///|
test "0586: the deck's tables, as the dump the analysis prints" {
  let r = @flow.taint_analyze(tn_deck_cfgs(), tn_deck_spec())
  // The dump covers BOTH functions, and the helper's own map is in it:
  // `secret -> {"s3cret"}` is the deck's `getPassword` body, and it holds no
  // tainted datum -- the tainted datum is the CALL's, and it lives in the
  // caller's map.
  assert_eq(
    @flow.taint_text(r),
    "s -> {\"\",t3}; x -> {o2}; y -> {o2}; pw -> {t3}; o2.f -> {\"\",t3}; " +
    "secret -> {\"s3cret\"}; flow <3, 7, 0>",
  )
}

///|
test "0586: the other function's map carries no tainted datum -- the analysis is intraprocedural" {
  let r = @flow.taint_analyze(tn_deck_cfgs(), tn_deck_spec())
  // `getPassword`'s own body holds the secret, and the tainted datum is the
  // CALL's, in the CALLER. The pointer analysis has one map per function, so
  // the two maps do not meet.
  let helper = r.pts[1]
  let tainted = @flow.pta_of(helper, "secret")
  assert_eq(tainted.contains("t3"), false)
  // And the deck's own example needs nothing from the helper: the flow is
  // already there.
  assert_eq(r.flows.length(), 1)
}

///|
test "0586: a source call that IS the sink's argument is a flow, with no variable between" {
  // `log(get_password())` -- the tainted datum never reaches a variable,
  // because the pointer analysis does not model what a call returns.
  let g = @flow.cfg_of([
    tn_expr(3, tn_call(3, "log", [tn_call(3, "get_password", [])])),
  ])
  let r = @flow.taint_analyze([g], tn_deck_spec())
  assert_eq(r.flows.length(), 1)
  assert_eq(r.flows[0].src_line, 3)
  assert_eq(r.flows[0].sink_line, 3)
  assert_eq(r.flows[0].arg, 0)
}

///|
test "0586: a function that is not a source produces no flow" {
  let g = @flow.cfg_of([
    tn_let(3, "pw", tn_call(3, "get_other", [])),
    tn_expr(7, tn_call(7, "log", [tn_name(7, "pw")])),
  ])
  let r = @flow.taint_analyze([g], tn_deck_spec())
  assert_eq(r.flows.length(), 0)
}

///|
test "0586: a sink whose sensitive argument it does not have produces no flow" {
  // The spec says `log`'s argument 0 is sensitive, and this call has none.
  let g = @flow.cfg_of([tn_expr(7, tn_call(7, "log", []))])
  let r = @flow.taint_analyze([g], tn_deck_spec())
  assert_eq(r.flows.length(), 0)
}

///|
test "0586: a sink with two sensitive arguments reports both" {
  let spec = @flow.taint_spec_empty()
  @flow.taint_spec_source(spec, "get_password")
  @flow.taint_spec_sink(spec, "log", 0)
  @flow.taint_spec_sink(spec, "log", 1)
  let g = @flow.cfg_of([
    tn_let(3, "pw", tn_call(3, "get_password", [])),
    tn_expr(7, tn_call(7, "log", [tn_name(7, "pw"), tn_name(7, "pw")])),
  ])
  let r = @flow.taint_analyze([g], spec)
  assert_eq(r.flows.length(), 2)
  assert_eq(r.flows[0].arg, 0)
  assert_eq(r.flows[1].arg, 1)
}

///|
test "0586: the same index twice is one argument, not two flows" {
  let spec = @flow.taint_spec_empty()
  @flow.taint_spec_source(spec, "get_password")
  @flow.taint_spec_sink(spec, "log", 0)
  @flow.taint_spec_sink(spec, "log", 0)
  let g = @flow.cfg_of([
    tn_let(3, "pw", tn_call(3, "get_password", [])),
    tn_expr(7, tn_call(7, "log", [tn_name(7, "pw")])),
  ])
  let r = @flow.taint_analyze([g], spec)
  assert_eq(r.flows.length(), 1)
}

///|
test "0586: a `..` chain link is not a source: it evaluates to the receiver" {
  // `recv..name(args)` CALLS `name` and evaluates to the RECEIVER, so its
  // value is not the callee's value. A tainted datum cannot be created there.
  let g = @flow.cfg_of([
    tn_let(3, "pw", tn_dotdot(3, tn_name(3, "conn"), "get_password")),
  ])
  let r = @flow.taint_analyze([g], tn_deck_spec())
  assert_eq(r.flows.length(), 0)
  let tainted = @flow.pta_of(r.pts[0], "pw")
  assert_eq(tainted.contains("t3"), false)
}

///|
test "0586: a method call is a sink by its method's name" {
  let g = @flow.cfg_of([
    tn_let(3, "pw", tn_call(3, "get_password", [])),
    tn_expr(7, tn_method(7, tn_name(7, "logger"), "log")),
  ])
  // The method call has NO arguments, so the sensitive argument 0 is not
  // there -- and that is the row that says a method sink is matched at all.
  let spec = @flow.taint_spec_empty()
  @flow.taint_spec_source(spec, "get_password")
  @flow.taint_spec_sink(spec, "log", 0)
  let r = @flow.taint_analyze([g], spec)
  assert_eq(r.flows.length(), 0)
}

///|
test "0586: an empty specification produces no flows" {
  let r = @flow.taint_analyze(tn_deck_cfgs(), @flow.taint_spec_empty())
  assert_eq(r.flows.length(), 0)
}
