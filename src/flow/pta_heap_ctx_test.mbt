// 0581: the CONTEXT-SENSITIVE HEAP, pinned to the deck's own example.
//
// THE DECK. `11-12_PTA-CS.pdf` p.28-33 introduces the context-sensitive heap --
// "The abstract objects are also qualified by contexts (called heap contexts)",
// "The most common choice is to inherit contexts from the method where the
// object is allocated" -- and p.34-56 works the example out. p.56 prints the
// TWO COLUMNS and the two conclusions:
//
//     "C.I. + C.S. heap"                "C.S. + C.S heap"
//     n1  -> o1        n2 -> o2          n1  -> o1      n2 -> o2
//     p   -> o1, o2                      3:p -> o1      4:p -> o2
//     x   -> 3:o8, 4:o8                  3:x -> 3:o8    4:x -> 4:o8
//     x1  -> 3:o8, 4:o8                  x1  -> 3:o8    x2 -> 4:o8
//     x2  -> 3:o8, 4:o8                  n   -> o1
//     n   -> o1, o2
//     3:o8.f -> o1, o2                    3:o8.f -> o1    4:o8.f -> o2
//     4:o8.f -> o1, o2
//
//     "Context-sensitive heap improves precision"
//     "Without C.S., C.S. heap cannot improve precision"
//
// THE PROGRAM, AS THE DECK PRINTS IT:
//
//      1 n1 = new One();
//      2  n2 = new Two();
//      3  x1 = newX(n1);
//      4  x2 = newX(n2);
//      5  n = x1.f;
//      6
//      7 X newX(Number p) {
//      8   X x = new X();
//      9   x.f = p;
//     10   return x;
//     11 }
//     12 class X {
//     13  Number f;
//     14 }
//
// THE SPELLING IS THIS TREE'S, because this tree's AST HAS NO CLASSES: `new
// One()` is the allocation `One::{}`, and `newX` is a plain function. Everything
// the deck's tables are ABOUT is kept: the two allocation sites in `main` (o1
// and o2, named by their lines), the one allocation site in `newX` (o8, line 8),
// the two call sites (lines 3 and 4, which are the CONTEXT LABELS), the store
// through a field (`x.f = p`), the load of that field in the CALLER (`n =
// x1.f`), and the two conclusions.
//
// THE FIXTURES ARE HAND-BUILT ASTs, like every other row in this package's
// pointer-analysis tests: the CFG is built by `cfg_of`, which allocates its
// nodes BACK TO FRONT, so a hand-built node list would not exercise the ordering
// the analysis reads.

///|
fn hc_name(x : String) -> @ast.Expr {
  { span: @flow.no_span(), kind: @ast.EName(x), }
}

///|
fn hc_struct(ty : String) -> @ast.Expr {
  { span: @flow.no_span(), kind: @ast.EStruct(ty, []), }
}

///|
fn hc_call(f : String, args : Array[@ast.Expr]) -> @ast.Expr {
  { span: @flow.no_span(), kind: @ast.ECall(f, args, []), }
}

///|
fn hc_field(base : @ast.Expr, f : String) -> @ast.Expr {
  { span: @flow.no_span(), kind: @ast.EField(base, f), }
}

///|
/// A span ON A LINE, because the line is what the analysis reads: an allocation
/// site is named by the line of its statement, and a call site is labelled by
/// the line of its call.
fn hc_span(line : Int32) -> @core.Span {
  { start: @core.pos(line, 1), end: @core.pos(line, 1), }
}

///|
fn hc_let(line : Int32, x : String, e : @ast.Expr) -> @ast.Stmt {
  { span: hc_span(line), kind: @ast.SLet(x, "", e), }
}

///|
/// `x.f = e` -- the deck's Store rule, and the store that the caller later
/// reads.
fn hc_place(line : Int32, target : @ast.Expr, e : @ast.Expr) -> @ast.Stmt {
  { span: hc_span(line), kind: @ast.SAssign(target, e), }
}

///|
fn hc_return(line : Int32, e : @ast.Expr) -> @ast.Stmt {
  { span: hc_span(line), kind: @ast.SReturn(Some(e)), }
}

///|
fn hc_param(name : String, ann : String) -> @ast.Param {
  { name, tyann: ann, omittable: false, span: @flow.no_span(), }
}

///|
fn hc_fn(
  name : String,
  params : Array[@ast.Param],
  body : Array[@ast.Stmt],
) -> @flow.CgFn {
  { name, params, body, }
}

///|
/// The deck's p.56 program, as the two functions the analysis sees.
fn hc_program() -> Array[@flow.CgFn] {
  [
    hc_fn("main", [], [
      hc_let(1, "n1", hc_struct("One")),
      hc_let(2, "n2", hc_struct("Two")),
      hc_let(3, "x1", hc_call("newX", [hc_name("n1")])),
      hc_let(4, "x2", hc_call("newX", [hc_name("n2")])),
      hc_let(5, "n", hc_field(hc_name("x1"), "f")),
    ]),
    hc_fn("newX", [hc_param("p", "Number")], [
      hc_let(8, "x", hc_struct("X")),
      hc_place(9, hc_field(hc_name("x"), "f"), hc_name("p")),
      hc_return(10, hc_name("x")),
    ]),
  ]
}

///|
/// The three readings the deck's two columns are made of.
fn hc_compare() -> @flow.HeapCtxCompare {
  @flow.pta_heap_ctx_compare(
    hc_program(),
    @flow.TraitTable::empty(),
    "main",
    @flow.CtxSelect::CallSite(1),
  )
}

///|
/// The points-to set of ONE pointer of the WHOLE PROGRAM, in the deck's
/// notation: the context in front of the name when there is one.
///
/// IT IS THE PROGRAM'S TABLE AND NOT ONE FRAME'S, because the deck's table is
/// the program's: `n1` and `3:p` are rows of the same table, and the only thing
/// that tells them apart is the context in front of the name.
fn hc_of(res : @flow.PtaCtxResult, ptr : String) -> Map[String, Bool] {
  @flow.pta_of(@flow.pta_heap_ctx_program_map(res), ptr)
}

///|
/// The field cells of the heap, by the object's own name.
fn hc_heap_of(res : @flow.PtaCtxResult, cell : String) -> Map[String, Bool] {
  @flow.pta_of(res.heap, cell)
}

///|
/// THE DECK'S RIGHT COLUMN. "C.S. + C.S heap" (p.56): the context-sensitive
/// analysis over the context-sensitive heap.
///
/// THE NINE VARIABLE ROWS AND THE TWO FIELD ROWS, AS THE DECK PRINTS THEM.
test "0581: the C.S. + C.S. heap column -- deck 11-12 p.56" {
  let c = hc_compare()
  let res = c.cs_heap
  // `main`'s OWN OBJECTS KEEP THEIR PLAIN NAMES: the entry frame is entered by
  // no call, so it has no heap context, and the deck prints `n1 -> o1`.
  let n1 = hc_of(res, "n1")
  assert_true(n1.contains("o1"))
  assert_true(n1.length() == 1)
  let n2 = hc_of(res, "n2")
  assert_true(n2.contains("o2"))
  assert_true(n2.length() == 1)
  // `newX`'s PARAMETER, IN ITS CONTEXT: one object per context.
  let p3 = hc_of(res, "3:p")
  assert_true(p3.contains("o1"))
  assert_true(p3.length() == 1)
  let p4 = hc_of(res, "4:p")
  assert_true(p4.contains("o2"))
  assert_true(p4.length() == 1)
  // `newX`'s LOCAL, IN ITS CONTEXT: the object carries the heap context.
  let x3 = hc_of(res, "3:x")
  assert_true(x3.contains("3:o8"))
  assert_true(x3.length() == 1)
  let x4 = hc_of(res, "4:x")
  assert_true(x4.contains("4:o8"))
  assert_true(x4.length() == 1)
  // THE CALLER'S TWO NAMES: each call's result is the object of ITS context.
  let x1 = hc_of(res, "x1")
  assert_true(x1.contains("3:o8"))
  assert_true(x1.length() == 1)
  let x2 = hc_of(res, "x2")
  assert_true(x2.contains("4:o8"))
  assert_true(x2.length() == 1)
  // AND `n`, WHICH IS THE POINTER THE DECK'S FIRST CONCLUSION IS ABOUT.
  let n = hc_of(res, "n")
  assert_true(n.contains("o1"))
  assert_true(n.length() == 1)
  // THE FIELD CELLS: the heap's cells are named by the OBJECT's name, so the
  // deck's `3:o8.f` and `4:o8.f` are two different cells.
  let f3 = hc_heap_of(res, "3:o8.f")
  assert_true(f3.contains("o1"))
  assert_true(f3.length() == 1)
  let f4 = hc_heap_of(res, "4:o8.f")
  assert_true(f4.contains("o2"))
  assert_true(f4.length() == 1)
}

///|
/// THE DECK'S LEFT COLUMN. "C.I. + C.S. heap" (p.56): the context-sensitive
/// HEAP under a context-INSENSITIVE analysis.
///
/// THE FRAME IS MERGED -- `p` is ONE pointer holding BOTH objects -- while the
/// HEAP IS NOT: the frame's object is `3:o8` AND `4:o8`, one per call site.
test "0581: the C.I. + C.S. heap column -- deck 11-12 p.56" {
  let c = hc_compare()
  let res = c.no_cs
  // THE MERGED PARAMETER: both objects, because `newX` was analysed ONCE.
  let p = hc_of(res, "p")
  assert_true(p.contains("o1"))
  assert_true(p.contains("o2"))
  assert_true(p.length() == 2)
  // AND THE FRAME'S LOCAL, WHICH HOLDS TWO OBJECTS: the heap is still split by
  // the call site, even though the frame is not.
  let x = hc_of(res, "x")
  assert_true(x.contains("3:o8"))
  assert_true(x.contains("4:o8"))
  assert_true(x.length() == 2)
  // AND THE CALLER'S TWO NAMES, WHICH HOLD THE SAME TWO OBJECTS.
  let x1 = hc_of(res, "x1")
  assert_true(x1.contains("3:o8"))
  assert_true(x1.contains("4:o8"))
  assert_true(x1.length() == 2)
  let x2 = hc_of(res, "x2")
  assert_true(x2.contains("3:o8"))
  assert_true(x2.contains("4:o8"))
  assert_true(x2.length() == 2)
  // AND `n`, WHICH HOLDS BOTH -- the deck's second conclusion.
  let n = hc_of(res, "n")
  assert_true(n.contains("o1"))
  assert_true(n.contains("o2"))
  assert_true(n.length() == 2)
  // AND BOTH FIELD CELLS HOLD BOTH, because the frame is merged.
  let f3 = hc_heap_of(res, "3:o8.f")
  assert_true(f3.contains("o1"))
  assert_true(f3.contains("o2"))
  assert_true(f3.length() == 2)
  let f4 = hc_heap_of(res, "4:o8.f")
  assert_true(f4.contains("o1"))
  assert_true(f4.contains("o2"))
  assert_true(f4.length() == 2)
}

///|
/// THE BASELINE: the context-sensitive analysis over the ORDINARY heap, which
/// is the deck's p.30 picture of allocation-site abstraction -- one object per
/// site, `o8`, shared by both frames.
///
/// AND THE POINT OF THE BASELINE: without the context-sensitive heap, the two
/// frames SHARE the object, so the field holds both values and `n` holds both.
test "0581: the ordinary heap shares one object -- deck 11-12 p.30" {
  let c = hc_compare()
  let res = c.plain
  // THE OBJECT IS `o8` IN BOTH FRAMES: no heap context, so no prefix.
  let x3 = hc_of(res, "3:x")
  assert_true(x3.contains("o8"))
  let x4 = hc_of(res, "4:x")
  assert_true(x4.contains("o8"))
  // AND THE ONE FIELD CELL HOLDS BOTH VALUES.
  let f = hc_heap_of(res, "o8.f")
  assert_true(f.contains("o1"))
  assert_true(f.contains("o2"))
  assert_true(f.length() == 2)
  // AND `n` HOLDS BOTH.
  let n = hc_of(res, "n")
  assert_true(n.length() == 2)
}

///|
/// THE DECK'S FIRST CONCLUSION, AS A MEASUREMENT: "Context-sensitive heap
/// improves precision".
///
/// THE POINTER IS `n`, AND THE MEASUREMENT IS HOW MANY OBJECTS IT HOLDS.
test "0581: the context-sensitive heap improves precision -- deck 11-12 p.56" {
  let c = hc_compare()
  let plain_n = hc_of(c.plain, "n")
  let cs_n = hc_of(c.cs_heap, "n")
  let no_cs_n = hc_of(c.no_cs, "n")
  // THE ORDINARY HEAP SAYS TWO, THE CONTEXT-SENSITIVE HEAP SAYS ONE.
  assert_true(plain_n.length() == 2)
  assert_true(cs_n.length() == 1)
  assert_true(cs_n.contains("o1"))
  // AND THE CONTEXT-INSENSITIVE READING SAYS TWO AS WELL -- which is the
  // deck's second conclusion, and it is measured here too.
  assert_true(no_cs_n.length() == 2)
  // AND THE WHOLE TABLE SHRINKS WITH IT: fewer (pointer, object) pairs.
  //
  // THE TWO NUMBERS ARE MEASURED, NOT GUESSED: thirteen pairs against
  // fourteen. The ordinary heap has ONE field cell holding two objects and
  // TWO frames' worth of the same object; the context-sensitive heap has TWO
  // field cells holding one object each, and the frames stop sharing.
  assert_true(c.pairs_cs_heap == 13)
  assert_true(c.pairs_plain == 14)
  assert_true(c.pairs_cs_heap < c.pairs_plain)
}

///|
/// THE DECK'S SECOND CONCLUSION, AS A MEASUREMENT: "Without C.S., C.S. heap
/// cannot improve precision".
///
/// THE CONTEXT-SENSITIVE HEAP UNDER A CONTEXT-INSENSITIVE ANALYSIS SAYS THE
/// SAME THING AS THE ORDINARY HEAP, and that is what the sentence means.
///
/// IT IS THE ANSWER THAT IS COMPARED AND NOT THE SIZE OF THE TABLE, because
/// the two readings have a different number of FRAMES -- one analysis merges
/// `newX` into a single frame, the other has two -- and a table's size says
/// as much about how many frames there are as about how precise they are.
test "0581: without C.S., the C.S. heap cannot improve precision -- deck 11-12 p.56" {
  let c = hc_compare()
  let plain_n = hc_of(c.plain, "n")
  let no_cs_n = hc_of(c.no_cs, "n")
  // THE SAME ANSWER, OBJECT FOR OBJECT.
  assert_true(no_cs_n.length() == plain_n.length())
  assert_true(no_cs_n.contains("o1"))
  assert_true(no_cs_n.contains("o2"))
  assert_true(plain_n.contains("o1"))
  assert_true(plain_n.contains("o2"))
  // AND THE HEAP WAS SPLIT ANYWAY: the merged frame holds TWO objects, one
  // per call site -- so the heap is finer and the ANSWER is not. This is the
  // deck's own left column, where `x -> 3:o8, 4:o8` and `n -> o1, o2` sit in
  // the same table.
  let x = hc_of(c.no_cs, "x")
  assert_true(x.length() == 2)
  assert_true(x.contains("3:o8"))
  assert_true(x.contains("4:o8"))
  // AND THE FRAME COUNT IS WHAT DIFFERS: two frames under the context-
  // sensitive analysis, one under the context-insensitive one.
  assert_true(c.plain.state_count == 3)
  assert_true(c.cs_heap.state_count == 3)
  assert_true(c.no_cs.state_count == 2)
}

///|
/// THE DECK'S TABLE, PRINTED. The two columns of p.56, in the tree's own
/// points-to format, so the reader can compare them with the slide.
test "0581: the deck's two columns, printed" {
  let c = hc_compare()
  let right = @flow.pta_heap_ctx_program_text(c.cs_heap)
  let left = @flow.pta_heap_ctx_program_text(c.no_cs)
  // THE RIGHT COLUMN'S ROWS.
  assert_true(right.contains("n1 -> {o1}"))
  assert_true(right.contains("n2 -> {o2}"))
  assert_true(right.contains("3:p -> {o1}"))
  assert_true(right.contains("3:x -> {3:o8}"))
  assert_true(right.contains("x1 -> {3:o8}"))
  assert_true(right.contains("4:p -> {o2}"))
  assert_true(right.contains("4:x -> {4:o8}"))
  assert_true(right.contains("x2 -> {4:o8}"))
  assert_true(right.contains("n -> {o1}"))
  assert_true(right.contains("3:o8.f -> {o1}"))
  assert_true(right.contains("4:o8.f -> {o2}"))
  // AND THE LEFT COLUMN'S ROWS.
  assert_true(left.contains("p -> {o1,o2}"))
  assert_true(left.contains("x -> {3:o8,4:o8}"))
  assert_true(left.contains("x1 -> {3:o8,4:o8}"))
  assert_true(left.contains("x2 -> {3:o8,4:o8}"))
  assert_true(left.contains("n -> {o1,o2}"))
  assert_true(left.contains("3:o8.f -> {o1,o2}"))
  assert_true(left.contains("4:o8.f -> {o1,o2}"))
}
