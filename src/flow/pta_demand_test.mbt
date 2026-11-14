// 0575: the DEMAND-DRIVEN scope, pinned to the deck's own two columns.
//
// THE DECK. `Pointer Analysis` (Tian Tan, Nanjing University, 2021) p.72-77:
//
//   p.72   "Analysis Scope: Which parts of program should be analyzed?"
//          WHOLE-PROGRAM    "Compute points-to information for all pointers in
//                            the program"
//          DEMAND-DRIVEN    "Only compute points-to information for the pointers
//                            that may affect specific sites of interest (on
//                            demand)"
//   p.73-77 THE PROGRAM AND ITS TWO COLUMNS:
//
//          1 x = new A();
//          2 y = x;
//          3 …
//          4 z = new T();
//          5 z.bar();
//
//          p.74 (whole-program)   x -> {o1}   y -> {o1}   z -> {o4}
//          p.76 (demand-driven)                 z -> {o4}
//
//          p.75 names the client and the site: "Client: call graph
//          construction", "Site of interest: line 5".
//
// THE TWO COLUMNS ARE THE SAME PROGRAM, THE SAME RULES AND THE SAME OBJECT
// NAMING. They differ in ONE thing: how much is computed. The demand-driven
// column is ONE LINE LONG because only `z` was demanded -- and `z` is the
// receiver at the site of interest, which is what the client asks about.
//
// SO THE SCOPE CHANGES HOW MUCH IS COMPUTED AND NEVER WHAT IS TRUE. The last
// row below is the soundness statement: the demand-driven answer for the
// demanded pointer is the SAME SET the whole-program answer gives.

///|
fn dm_name(x : String) -> @ast.Expr {
  { span: @flow.no_span(), kind: @ast.EName(x), }
}

///|
fn dm_struct(ty : String) -> @ast.Expr {
  { span: @flow.no_span(), kind: @ast.EStruct(ty, []), }
}

///|
fn dm_call(f : String, args : Array[@ast.Expr]) -> @ast.Expr {
  { span: @flow.no_span(), kind: @ast.ECall(f, args, []), }
}

///|
fn dm_method(recv : String, m : String) -> @ast.Expr {
  { span: @flow.no_span(), kind: @ast.EMethodCall(dm_name(recv), m, [], []), }
}

///|
/// A span ON A LINE: an allocation site is named by the line of its statement
/// (deck 8 p.45-47, p.77), so the deck's `o1` and `o4` need the deck's lines.
fn dm_span(line : Int32) -> @core.Span {
  { start: @core.pos(line, 1), end: @core.pos(line, 1), }
}

///|
fn dm_let(line : Int32, x : String, e : @ast.Expr) -> @ast.Stmt {
  { span: dm_span(line), kind: @ast.SLet(x, "", e), }
}

///|
fn dm_tail(e : @ast.Expr) -> @ast.Stmt {
  { span: @flow.no_span(), kind: @ast.STail(e), }
}

///|
fn dm_param(name : String, ann : String) -> @ast.Param {
  { name, tyann: ann, omittable: false, span: @flow.no_span(), }
}

///|
fn dm_fn(
  name : String,
  params : Array[@ast.Param],
  body : Array[@ast.Stmt],
) -> @flow.CgFn {
  { name, params, body, }
}

///|
/// The deck's p.73-77 program, with the deck's own line numbers.
fn dm_deck_program() -> Array[@flow.CgFn] {
  [
    dm_fn("main", [], [
      dm_let(1, "x", dm_struct("A")),
      dm_let(2, "y", dm_name("x")),
      dm_let(4, "z", dm_struct("T")),
      dm_let(5, "i", dm_method("z", "bar")),
    ]),
  ]
}

///|
/// The whole-program answer for a program: one map per function.
fn dm_whole(fns : Array[@flow.CgFn]) -> Array[@flow.Pta] {
  let cfgs : Array[@flow.Cfg] = []
  let mut i = 0
  while i < fns.length() {
    cfgs.push(@flow.cfg_of(fns[i].body))
    i = i + 1
  }
  @flow.pta_run(cfgs)
}

///|
/// The demand-driven answer for one pointer.
fn dm_run(
  fns : Array[@flow.CgFn],
  fname : String,
  ptr : String,
) -> @flow.PtaDemandResult {
  @flow.pta_demand_run(fns, @flow.TraitTable::empty(), {
    fn_name: fname,
    pointer: ptr,
  })
}

///|
/// THE DECK'S p.76 COLUMN: the demanded pointer, and nothing else.
test "0575: the demand-driven column is one line long -- deck 8 p.76 against p.74" {
  let fns = dm_deck_program()
  let res = dm_run(fns, "main", "z")
  // THE WHOLE-PROGRAM COLUMN, p.74: THREE pointers.
  let whole = dm_whole(fns)[0]
  assert_eq(@flow.pta_text(whole), "x -> {o1}; y -> {o1}; z -> {o4}")
  // AND THE DEMAND-DRIVEN COLUMN, p.76: ONE.
  assert_eq(@flow.pta_text(res.points_to), "z -> {o4}")
}

///|
/// THE SCOPE CHANGES HOW MUCH IS COMPUTED AND NEVER WHAT IS TRUE: the demanded
/// pointer's SET is the same in both columns.
test "0575: the demanded pointer's answer is the same in both scopes" {
  let fns = dm_deck_program()
  let res = dm_run(fns, "main", "z")
  let whole = dm_whole(fns)[0]
  let demanded = @flow.pta_of(res.points_to, "z")
  let everything = @flow.pta_of(whole, "z")
  assert_true(demanded.length() == 1)
  assert_true(demanded.length() == everything.length())
  assert_true(demanded.contains("o4"))
  assert_true(everything.contains("o4"))
}

///|
/// ONLY THE DEMANDED POINTER WAS DEMANDED. `x` and `y` are not in the answer
/// because nothing the client asked for can be reached through them -- that is
/// the deck's p.72 definition, "the pointers that may affect specific sites of
/// interest", made countable.
test "0575: only the affected pointer was computed" {
  let fns = dm_deck_program()
  let res = dm_run(fns, "main", "z")
  // ONE PAIR WAS DEMANDED: the client's own pointer.
  assert_true(res.demanded.length() == 1)
  assert_true(res.demanded.contains("main|z"))
}

///|
/// THE SITE OF INTEREST IS FOUND BY ITS LINE, which is how the deck names it
/// (p.75: "Site of interest: line 5"), and the pointer at that site is the
/// RECEIVER of the call.
test "0575: the site of interest is the receiver at the deck's line 5" {
  let fns = dm_deck_program()
  let q = @flow.pta_demand_site(fns, "main", 5)
  assert_true(q is Some(_))
  match q {
    Some(site) => {
      assert_true(site.fn_name == "main")
      assert_true(site.pointer == "z")
    }
    None => ()
  }
  // AND A LINE WITH NO CALL SITE IS NOT A SITE OF INTEREST.
  assert_true(@flow.pta_demand_site(fns, "main", 3) is None)
}

///|
/// THE DEMAND CROSSES THE CALL BOUNDARY, in the one direction the deck's
/// client needs: a PARAMETER's value is the ARGUMENT at the call site that
/// reached it.
///
/// The fixture is a caller and a callee, and the question is about the
/// CALLEE's parameter -- which lives in the caller.
test "0575: a demanded parameter's value comes from the caller's argument" {
  let fns = [
    dm_fn("main", [], [
      dm_let(1, "x", dm_struct("A")),
      dm_let(2, "y", dm_call("id", [dm_name("x")])),
    ]),
    dm_fn("id", [dm_param("n", "A")], [dm_tail(dm_name("n"))]),
  ]
  let res = dm_run(fns, "id", "n")
  // THE PARAMETER HOLDS THE CALLER'S ARGUMENT'S OBJECT.
  let v = res.values.get("id|n").unwrap_or(@flow.name_set_empty())
  assert_true(v.length() == 1)
  assert_true(v.contains("o1"))
  // AND THE CALLER'S ARGUMENT WAS DEMANDED TOO -- the demand travelled.
  assert_true(res.demanded.contains("main|x"))
  assert_true(res.demanded.length() == 2)
}

///|
/// A POINTER THAT ONLY A CALL WRITES HAS NO VALUE HERE, and that is the
/// tree's direction and not a claim about the program: a value the analysis
/// does not model contributes nothing rather than an invented object.
test "0575: a pointer written only by a call has no value in this scope" {
  let fns = [
    dm_fn("main", [], [
      dm_let(1, "x", dm_struct("A")),
      dm_let(2, "y", dm_call("id", [dm_name("x")])),
    ]),
    dm_fn("id", [dm_param("n", "A")], [dm_tail(dm_name("n"))]),
  ]
  let res = dm_run(fns, "main", "y")
  // `y` IS THE RESULT OF A CALL, and this analysis does not model a call's
  // result -- so the demand for `y` reaches nothing.
  let v = res.values.get("main|y").unwrap_or(@flow.name_set_empty())
  assert_true(v.length() == 0)
}

///|
/// THE DEMAND IS A WORK LIST, and the run says how many steps it took. The
/// count is not a claim about the program; it is the SIZE OF THE COMPUTATION,
/// which is the whole point of the scope.
test "0575: the demand is counted, and it is smaller than the program" {
  let fns = dm_deck_program()
  let res = dm_run(fns, "main", "z")
  assert_true(res.steps > 0)
  // THE DEMANDED PAIRS ARE FEWER THAN THE POINTERS THE PROGRAM HAS.
  let whole = dm_whole(fns)[0]
  let mut pointers = 0
  for k, _ in whole {
    if @flow.pta_of(whole, k).length() > 0 {
      pointers = pointers + 1
    }
  }
  assert_true(res.demanded.length() < pointers)
}
