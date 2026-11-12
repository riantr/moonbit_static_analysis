// 0547: pointer analysis, pinned to the deck's own printed tables.
//
// THE NUMBERS ARE THE SLIDES', NOT THE IMPLEMENTATION'S. `Pointer Analysis` (Tian
// Tan, Nanjing University, 2021) works small programs through the analysis and
// prints every points-to set:
//
//   p.57-69  ONE four-statement program, TWO answers:
//
//              1 c = new C();
//              2 c.f = "x";
//              3 s = c.f;
//              4 c.f = "y";
//
//            flow-sensitive (p.61-64)     c -> {o1}   o1.f -> {"y"}   s -> {"x"}
//            flow-insensitive (p.68)      c -> {o1}   o1.f -> {"x","y"}
//                                                      s -> {"x","y"}
//            and p.69 labels that second `s` a FALSE POSITIVE.
//
//   p.28-29  `p = new C(); q = p; x = new X(); y = new Y();`
//            -> p and q are aliases, x and y are not.
//
//   p.45-47  `for (...) { a = new A(); }` with the allocation on LINE 2
//            -> one abstract object, named o2.
//
//   p.77     `1 x = new A(); 2 y = x; ... 4 z = new T();`
//            -> x -> {o1}, y -> {o1}, z -> {o4}.
//
//   p.86     `array[0] = "x"; array[1] = "y"; s = array[0];`
//            -> in the deck's perspective `array.arr` holds both, so s gets both.
//
// TWO OF THOSE TABLES ARE ABOUT NAMING, AND THEY ARE WHY THE OBJECT NAMES ARE
// ASSERTED AND NOT NORMALISED. p.45-47 prints `o2` for a site on line 2 and p.77
// prints `o4` for a site on line 4, so the deck names an object by its allocation
// site's STATEMENT LABEL -- the line number -- and not by its order of appearance.
// A test that renamed `o1, o2, ...` in order would have accepted the first version
// of `pta_site_names`, which ranked sites sequentially and would have printed `o2`
// for p.77's `z`. The names below are the deck's; where a name could be produced
// either way, the fixture adds a line gap so only the deck's rule fits.
//
// EVERY GRAPH HERE COMES FROM `cfg_of`, NOT FROM A HAND-BUILT NODE LIST. That is
// deliberate: `cfg_of` allocates nodes BACK TO FRONT, so a test that hand-built
// nodes in source order would never exercise the ordering trap that
// `pta_source_order` exists to undo.
//
// THE EXPECTED STRINGS ARE IN SHORTLEX ORDER, NOT ALPHABETICAL. `Array::sort` uses
// `Compare for String`, documented in `core/builtin/string.mbt:408` as "shortlex
// order by their charcodes" -- LENGTH first, code units only as the tie-break. So
// `c` and `s` print BEFORE `o1.f`, which would sort between them alphabetically.
// The first draft of these rows read each slide left to right, expected the deck's
// own order, and failed; the failures are what proved the rule.

///|
fn p_span_at(line : Int32, col : Int32) -> @core.Span {
  { start: @core.pos(line, col), end: @core.pos(line, col), }
}

///|
fn p_span(line : Int32) -> @core.Span {
  p_span_at(line, 1)
}

///|
fn p_name(n : String) -> @ast.Expr {
  p_name_at(0, 1, n)
}

///|
/// A name AT A POSITION.
///
/// IT EXISTS BECAUSE A CFG NODE'S POSITION IS NOT ALWAYS THE STATEMENT'S. `cfg_of`
/// gives a branch node the position of its CONDITION, not of the `if`, so a
/// fixture whose conditions sit at line 0 -- which is what `p_name` produces --
/// would put the branch node BEFORE the statements around it in source order.
fn p_name_at(line : Int32, col : Int32, n : String) -> @ast.Expr {
  { span: p_span_at(line, col), kind: @ast.EName(n), }
}

///|
/// A binary expression at a position.
fn p_bin_at(
  line : Int32,
  col : Int32,
  op : @ast.BOp,
  lhs : @ast.Expr,
  rhs : @ast.Expr,
) -> @ast.Expr {
  { span: p_span_at(line, col), kind: @ast.EBin(op, lhs, rhs), }
}

///|
/// A unary expression at a position.
fn p_unary_at(
  line : Int32,
  col : Int32,
  u : @ast.UOp,
  e : @ast.Expr,
) -> @ast.Expr {
  { span: p_span_at(line, col), kind: @ast.EUnary(u, e), }
}

///|
fn p_return(line : Int32) -> @ast.Stmt {
  { span: p_span(line), kind: @ast.SReturn(None), }
}

///|
fn p_break(line : Int32) -> @ast.Stmt {
  { span: p_span(line), kind: @ast.SBreak([]), }
}

///|
fn p_raise(line : Int32) -> @ast.Stmt {
  { span: p_span(line), kind: @ast.SRaise(None), }
}

///|
fn p_int(i : Int32) -> @ast.Expr {
  { span: p_span(0), kind: @ast.EInt(i), }
}

///|
fn p_str(v : String) -> @ast.Expr {
  { span: p_span(0), kind: @ast.EStr(v, []), }
}

///|
fn p_field(b : @ast.Expr, f : String) -> @ast.Expr {
  { span: p_span(0), kind: @ast.EField(b, f), }
}

///|
fn p_index(b : @ast.Expr, i : @ast.Expr) -> @ast.Expr {
  { span: p_span(0), kind: @ast.EIndex(b, i), }
}

///|
fn p_struct(ty : String) -> @ast.Expr {
  { span: p_span(0), kind: @ast.EStruct(ty, []), }
}

///|
fn p_call(f : String) -> @ast.Expr {
  { span: p_span(0), kind: @ast.ECall(f, [], []), }
}

///|
fn p_let_at(line : Int32, col : Int32, x : String, e : @ast.Expr) -> @ast.Stmt {
  { span: p_span_at(line, col), kind: @ast.SLet(x, "", e), }
}

///|
fn p_let(line : Int32, x : String, e : @ast.Expr) -> @ast.Stmt {
  p_let_at(line, 1, x, e)
}

///|
fn p_assign_at(
  line : Int32,
  col : Int32,
  lhs : @ast.Expr,
  rhs : @ast.Expr,
) -> @ast.Stmt {
  { span: p_span_at(line, col), kind: @ast.SAssign(lhs, rhs), }
}

///|
fn p_assign(line : Int32, lhs : @ast.Expr, rhs : @ast.Expr) -> @ast.Stmt {
  p_assign_at(line, 1, lhs, rhs)
}

///|
fn p_while(
  line : Int32,
  cond : @ast.Expr,
  body : Array[@ast.Stmt],
) -> @ast.Stmt {
  { span: p_span(line), kind: @ast.SWhile(cond, body), }
}

///|
fn p_if(line : Int32, cond : @ast.Expr, body : Array[@ast.Stmt]) -> @ast.Stmt {
  { span: p_span(line), kind: @ast.SIf(cond, body, [], None), }
}

///|
/// The index of the node whose span starts on `line`; -1 when there is none.
fn first_node_at(g : @flow.Cfg, line : Int32) -> Int32 {
  let mut i = 0
  let mut found = -1
  while i < g.spans.length() {
    if found < 0 && g.spans[i].start.line == line {
      found = i
    }
    i = i + 1
  }
  found
}

///|
/// The lone points-to map of a one-function program, as text.
fn pta_one_text(g : @flow.Cfg) -> String {
  @flow.pta_text(@flow.pta_run([g])[0])
}

///|
/// The deck's four-statement program from p.57, built as statements.
fn pta_p57_body() -> Array[@ast.Stmt] {
  [
    p_let(1, "c", p_struct("C")),
    p_assign(2, p_field(p_name("c"), "f"), p_str("x")),
    p_let(3, "s", p_field(p_name("c"), "f")),
    p_assign(4, p_field(p_name("c"), "f"), p_str("y")),
  ]
}

///|
test "0547: flow-insensitively, `s` holds both strings -- p.68, and p.69's false positive" {
  let g = @flow.cfg_of(pta_p57_body())
  // p.68's right-hand column, and p.69 prints "false positive" next to it: the
  // load at line 3 runs BEFORE the store at line 4, so `s` really only ever holds
  // "x". A flow-insensitive map cannot see that and keeps both.
  assert_eq(
    pta_one_text(g),
    "c -> {o1}; s -> {\"x\",\"y\"}; o1.f -> {\"x\",\"y\"}",
  )
}

///|
test "0547: flow-sensitively on the same program, `s` holds only \"x\" -- p.61-64" {
  let g = @flow.cfg_of(pta_p57_body())
  // p.63-64's left-hand column, which is the last flow-sensitive table printed:
  // c -> {o1}, o1.f -> {"y"}, s -> {"x"}.
  assert_eq(
    @flow.pta_text(@flow.pta_run_ordered(g)),
    "c -> {o1}; s -> {\"x\"}; o1.f -> {\"y\"}",
  )
}

///|
test "0547: the two readings of one program disagree on exactly one pointer" {
  let g = @flow.cfg_of(pta_p57_body())
  let weak = @flow.pta_run([g])[0]
  let strong = @flow.pta_run_ordered(g)
  // `c` is the same in both: one allocation site, one object, and the store at
  // line 4 writes a FIELD of it rather than rebinding the name.
  assert_eq(@flow.pta_of(weak, "c").length(), 1)
  assert_eq(@flow.pta_of(strong, "c").length(), 1)
  // `s` is where the deck's false positive lives: two objects when read
  // flow-insensitively, one when read flow-sensitively.
  assert_eq(@flow.pta_of(weak, "s").length(), 2)
  assert_eq(@flow.pta_of(strong, "s").length(), 1)
  // And `s` does NOT alias `c`, in either arm -- the deck's example is about a
  // String variable, and the load copies the field's VALUE, not the object.
  assert_eq(@flow.pta_alias(weak, "c", "s"), false)
  assert_eq(@flow.pta_alias(strong, "c", "s"), false)
}

///|
test "0547: an object is named by its allocation site's line, not by its order (p.45-47, p.77)" {
  // p.77's program, with the deck's own line numbers. `z` is on LINE 4 and the
  // deck prints o4; ranking sites in order of appearance would print o2.
  //
  // THE EXPECTED STRING BELOW IS THE DECK'S WHOLE-PROGRAM COLUMN. p.74 and p.77
  // print exactly these three points-to sets for this program -- `x -> {o1}`,
  // `y -> {o1}`, `z -> {o4}` -- and p.72-77 give the OTHER analysis scope as a
  // strict SUBSET of it: p.76's demand-driven column prints only `z -> {o4}`,
  // because the site of interest there is line 5 (`z.bar()`) and only `z` can
  // affect it.
  //
  // THIS TREE DOES NOT BUILD THE DEMAND-DRIVEN READING, and the reason is the
  // deck's, not the tree's. p.72 defines that scope with "the pointers that may
  // affect specific sites of interest" and never says WHAT MAKES A POINTER
  // AFFECT A SITE, which is the whole content of a demand-driven analysis --
  // compare the flow-sensitivity factor, which gave a definition AND two printed
  // tables (p.61-64 against p.68) and could therefore be built and pinned. Its
  // client, p.75-76's "call graph construction", is the section this attachment
  // does not contain. And p.77's "Chosen in this course" is on whole-program. So
  // the row pins the whole-program reading, and the boundary is stated here
  // rather than in a row that could not fail. NARRATIVE.md, 0558, has the
  // comparison and the measurement behind it.
  let g = @flow.cfg_of([
    p_let(1, "x", p_struct("A")),
    p_let(2, "y", p_name("x")),
    p_let(4, "z", p_struct("T")),
  ])
  assert_eq(pta_one_text(g), "x -> {o1}; y -> {o1}; z -> {o4}")
}

///|
test "0547: one abstract object per allocation site, even inside a loop (p.45-47)" {
  // The debt's own loop example: `for (...) { a = new A(); }` with the allocation
  // on line 2. Three dynamic objects on three iterations collapse to `o2`, and the
  // collapse is what bounds the object set -- so the equality below is a claim
  // about TERMINATION as much as about precision.
  let g = @flow.cfg_of([
    p_while(1, p_name("cond"), [p_let(2, "a", p_struct("A"))]),
  ])
  assert_eq(pta_one_text(g), "a -> {o2}")
  let pt = @flow.pta_run([g])[0]
  assert_eq(@flow.pta_of(pt, "a").length(), 1)
}

///|
test "0547: flow-insensitivity is order-independent -- the statements are a set (p.55)" {
  let forward = @flow.cfg_of(pta_p57_body())
  let body = pta_p57_body()
  let reversed : Array[@ast.Stmt] = [body[3], body[2], body[1], body[0]]
  let backward = @flow.cfg_of(reversed)
  // The two graphs have DIFFERENT node orders and DIFFERENT edges -- line 4 now
  // runs first -- and the same answer, because the answer never looked at an edge.
  // The node indices move with the body array, which is the only thing that
  // changed: in the forward body line 4 gets the lower index, in the reversed body
  // line 4 gets the higher one. The spans are untouched, so the object keeps the
  // deck's name and the answer is the deck's.
  assert_eq(first_node_at(forward, 4) < first_node_at(forward, 1), true)
  assert_eq(first_node_at(backward, 4) > first_node_at(backward, 1), true)
  assert_eq(pta_one_text(forward), pta_one_text(backward))
  // The ordered arm is invariant too, for the OPPOSITE reason: it re-derives
  // source order from the spans, so the body's array order cannot reach it.
  assert_eq(
    @flow.pta_text(@flow.pta_run_ordered(forward)),
    @flow.pta_text(@flow.pta_run_ordered(backward)),
  )
}

///|
test "0547: cfg_of allocates nodes back to front, which is why source order is re-derived" {
  let g = @flow.cfg_of(pta_p57_body())
  let l1 = first_node_at(g, 1)
  let l4 = first_node_at(g, 4)
  // The trap, measured rather than remembered: the line-1 node has the HIGHER
  // index. Reading `kinds[0], kinds[1], ...` reads this body backwards, so the
  // ordered arm's answer depends on `pta_source_order` and not on `cfg_of`.
  assert_eq(l1 > l4, true)
  // The consequence: reading in node order would load `s` AFTER the store it must
  // not see. `pta_run_ordered` gives s = {"x"} precisely because it does not.
  assert_eq(
    @flow.pta_text(@flow.pta_run_ordered(g)),
    "c -> {o1}; s -> {\"x\"}; o1.f -> {\"y\"}",
  )
}

///|
test "0547: alias information is derived from points-to (p.28-29)" {
  // `p = new C(); q = p; x = new X(); y = new Y();` -- the deck's alias example.
  let g = @flow.cfg_of([
    p_let(1, "p", p_struct("C")),
    p_let(2, "q", p_name("p")),
    p_let(3, "x", p_struct("X")),
    p_let(4, "y", p_struct("Y")),
  ])
  let pt = @flow.pta_run([g])[0]
  // The table first: the deck's three objects, named by their lines.
  assert_eq(@flow.pta_text(pt), "p -> {o1}; q -> {o1}; x -> {o3}; y -> {o4}")
  // Then the two verdicts p.29 prints.
  assert_eq(@flow.pta_alias(pt, "p", "q"), true)
  assert_eq(@flow.pta_alias(pt, "x", "y"), false)
  // And the pair that must not alias just because both are objects.
  assert_eq(@flow.pta_alias(pt, "p", "x"), false)
}

///|
test "0547: array element writes collapse onto one field `arr` (p.86)" {
  // p.86's own table: `array[0] = "x"; array[1] = "y"; s = array[0];` becomes
  // `array.arr = "x"; array.arr = "y"; s = array.arr;` -- so the load cannot tell
  // which element it reads and takes both.
  //
  // THE FIXTURE USES A STRUCT LITERAL AS THE ARRAY'S ALLOCATION SITE, because
  // `new String[10]` has no spelling here that produces an allocation node. That is
  // a limitation of the fixture, not a claim about MoonBit arrays: the rule under
  // test is "an index write goes to the single field `arr` of the base object",
  // and it needs only SOME object for the base.
  let g = @flow.cfg_of([
    p_let(1, "array", p_struct("C")),
    p_assign(2, p_index(p_name("array"), p_int(0)), p_str("x")),
    p_assign(3, p_index(p_name("array"), p_int(1)), p_str("y")),
    p_let(4, "s", p_index(p_name("array"), p_int(0))),
  ])
  assert_eq(
    pta_one_text(g),
    "s -> {\"x\",\"y\"}; array -> {o1}; o1.arr -> {\"x\",\"y\"}",
  )
}

///|
test "0547: two functions keep their same-named locals apart" {
  // A pointer's key is a variable name, so ONE shared map would make `p` in the
  // first function and `p` in the second the same pointer and report them as
  // aliases. `pta_run` returns one map per function instead, and that is what this
  // row measures.
  let g1 = @flow.cfg_of([
    p_let(1, "p", p_struct("C")),
    p_let(2, "s1", p_name("p")),
  ])
  let g2 = @flow.cfg_of([
    p_let(10, "p", p_struct("D")),
    p_let(11, "s2", p_name("p")),
  ])
  let maps = @flow.pta_run([g1, g2])
  assert_eq(maps.length(), 2)
  assert_eq(@flow.pta_text(maps[0]), "p -> {o1}; s1 -> {o1}")
  assert_eq(@flow.pta_text(maps[1]), "p -> {o10}; s2 -> {o10}")
  // Neither map contains the other's local, which is the claim in one line.
  assert_eq(@flow.pta_of(maps[0], "s2").length(), 0)
  assert_eq(@flow.pta_of(maps[1], "s1").length(), 0)
}

///|
test "0547: a call's result contributes no objects (p.90-91, out of this attachment)" {
  // Method calls are the deck's fifth statement kind and are NOT in this
  // attachment -- it ends inside the Rules section. So the answer for a call's
  // result must be "nothing known", not an invented object: fewer facts, never
  // false ones.
  let g = @flow.cfg_of([
    p_let(1, "r", p_call("make")),
    p_assign(2, p_field(p_name("r"), "f"), p_str("x")),
  ])
  assert_eq(pta_one_text(g), "")
}

///|
test "0547: an interpolated string is not a constant object" {
  // p.59 puts a plain literal inside a points-to set, so a literal is an object.
  // `"\{v}"` is not one: its value depends on a name read inside the braces, and
  // this analysis has no value for names that are not pointers. Empty is the sound
  // direction; a key invented from the interpolation text would be a claim.
  let plain : @ast.Expr = { span: p_span(0), kind: @ast.EStr("x", []), }
  let interp : @ast.Expr = { span: p_span(0), kind: @ast.EStr("x", ["v"]), }
  let g = @flow.cfg_of([p_let(1, "a", plain), p_let(2, "b", interp)])
  assert_eq(pta_one_text(g), "a -> {\"x\"}")
}

///|
test "0547: two allocation sites on one line are disambiguated, and the fallback is this tree's" {
  // No slide prints two allocation sites on one line, so this numbering is THIS
  // TREE'S invention rather than the deck's: the first site on a line keeps
  // `o<line>`, later ones become `o<line>_<k>` in source-column order. Asserted so
  // that the invention is visible and cannot drift unnoticed.
  let g = @flow.cfg_of([
    p_let_at(1, 1, "a", p_struct("A")),
    p_let_at(1, 20, "b", p_struct("B")),
  ])
  assert_eq(pta_one_text(g), "a -> {o1}; b -> {o1_2}")
}

///|
fn p_method_call(
  recv : @ast.Expr,
  name : String,
  args : Array[@ast.Expr],
) -> @ast.Expr {
  { span: p_span(0), kind: @ast.EMethodCall(recv, name, args, []), }
}

///|
test "0561: the deck's introductory example, in the form this attachment can compute (p.19-26)" {
  // p.19-26 is the deck's FIRST worked example, and it is a five-slide derivation:
  //
  //   p.20   a -> new A          x -> new B              (the New rule, twice)
  //   p.22   this -> new A       b -> new B              (a method body's receiver and parameter)
  //   p.23   new A.b -> new B                            (the Store rule, inside `setB`)
  //   p.24   y                                            (the variable, still with no value)
  //   p.25   y -> new B                                  (the Load rule, out of `getB`)
  //
  // THREE OF THOSE FIVE STEPS ARE THE METHOD BODY, and the method body is the deck's
  // section 4 ("Pointer Analysis with Method Calls"), which this attachment DEFERS:
  // p.94's contents lists it, the file carries only section 1, and p.96 says of the
  // fifth statement kind "Will come back to this in pointer analysis with method
  // calls". So the deck's p.22, p.23 and p.25 facts are not derivable from here --
  // the same boundary that leaves context-sensitivity and demand-driven unbuilt.
  //
  // WHAT IS DERIVABLE IS THE FIELD FORM of the same program, and it is the deck's
  // own two rules with the method indirection removed:
  //
  //   1  A a = new A();      -> o1 in pt(a)        (p.98 New)
  //   2  B x = new B();      -> o2 in pt(x)        (p.98 New)
  //   3  a.b = x;            -> o2 in pt(o1.b)      (p.98 Store)
  //   4  B y = a.b;          -> o2 in pt(y)        (p.98 Load)
  //
  // and p.23's `new A.b -> new B` and p.25's `y -> new B` are exactly the last two
  // lines of it. The object is named by its allocation site's LINE, so `a`'s object
  // is `o1` and the field pointer is `o1.b` -- the deck's `new A.b` under this
  // tree's naming.
  let g = @flow.cfg_of([
    p_let(1, "a", p_struct("A")),
    p_let(2, "x", p_struct("B")),
    p_assign(3, p_field(p_name("a"), "b"), p_name("x")),
    p_let(4, "y", p_field(p_name("a"), "b")),
  ])
  assert_eq(pta_one_text(g), "a -> {o1}; x -> {o2}; y -> {o2}; o1.b -> {o2}")
}

///|
test "0561: the deck's introductory example AS WRITTEN stops at the two allocations (p.19-26)" {
  // The deck's program, with the method calls the deck actually writes:
  //
  //   1  A a = new A();
  //   2  B x = new B();
  //   3  a.setB(x);
  //   4  B y = a.getB();
  //
  // The answer is the deck's p.20 row and NOTHING ELSE, and that is the honest
  // answer rather than a shortfall: the three facts p.22, p.23 and p.25 add all
  // come from the bodies of `setB` and `getB`, which are the deferred section 4.
  // A call contributes no objects -- the row that already pins that -- and a
  // method call's receiver is not a field WRITE either, so `o1.b` stays unknown.
  //
  // SO THIS ROW IS THE BOUNDARY, PINNED AS A POSITIVE FACT: the two allocations are
  // named and nothing else is. It can fail -- if the analysis ever started
  // inventing a field store for a method call, or an object for a call's result,
  // this row would go red.
  let g = @flow.cfg_of([
    p_let(1, "a", p_struct("A")),
    p_let(2, "x", p_struct("B")),
    {
      span: p_span(3),
      kind: @ast.SExpr(p_method_call(p_name("a"), "setB", [p_name("x")])),
    },
    p_let(4, "y", p_method_call(p_name("a"), "getB", [])),
  ])
  assert_eq(pta_one_text(g), "a -> {o1}; x -> {o2}")
}
