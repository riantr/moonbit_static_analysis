// 0599: THE DISTRIBUTIVITY BOUNDARY -- the deck's two questions, measured on
// the two analyses this tree already has.
//
// THE DECK. `CFL-Reachability and IFDS` (Yue Li, Nanjing University, 2021),
// CHAPTER 6 (p.155-172) is "Understanding the Distributivity of IFDS". Its two
// questions are on p.156-157:
//
//   Can we do constant propagation using IFDS?
//   Can we do pointer analysis using IFDS?
//
// AND ITS RULE, p.162, verbatim:
//
//   Given a statement S, besides S itself, if we need to consider multiple
//   input data facts to create correct outputs, then the analysis is not
//   distributive and should not be expressed in IFDS.
//
// AND ITS ALGEBRA, p.158: `F(x ^ y) = F(x) ^ F(y)`.
//
// AND THE TWO HALVES ARE MEASURED THE SAME WAY, because a distributivity claim
// checked two different ways is two claims. The test is: the output on the
// whole state, against the join of the outputs each fact produces alone.
//
// AND THIS IS NOT THE TREE'S "CONFLUENCE" ROW. `cprop_intra_test.mbt` pins
// the OTHER deck's confluence -- `F(X meet Y) != F(X) meet F(Y)`, over the
// LATTICE's meet, which is a statement about the lattice. What is measured
// here is the distributivity over the DATA FACTS, which is a statement about
// the transfer: whether it needs more than one fact at a time. Two different
// questions, two different rows, and neither borrows the other's name.
//
// AND THE EXPECTED STRINGS ARE MEASURED, NOT GUESSED: every number below was
// printed by the code that asserts it before it was written down here.

///|
fn dist_span(line : Int32) -> @core.Span {
  { start: @core.pos(line, 1), end: @core.pos(line, 1), }
}

///|
fn dist_name(n : String) -> @ast.Expr {
  { span: dist_span(0), kind: @ast.EName(n), }
}

///|
fn dist_name_at(line : Int32, n : String) -> @ast.Expr {
  { span: dist_span(line), kind: @ast.EName(n), }
}

///|
fn dist_int(i : Int32) -> @ast.Expr {
  { span: dist_span(0), kind: @ast.EInt(i), }
}

///|
fn dist_new(line : Int32, ty : String) -> @ast.Expr {
  { span: dist_span(line), kind: @ast.EStruct(ty, []), }
}

///|
fn dist_bin(op : @ast.BOp, a : @ast.Expr, b : @ast.Expr) -> @ast.Expr {
  { span: dist_span(0), kind: @ast.EBin(op, a, b), }
}

///|
fn dist_field(b : @ast.Expr, f : String) -> @ast.Expr {
  { span: dist_span(0), kind: @ast.EField(b, f), }
}

///|
fn dist_let(line : Int32, x : String, e : @ast.Expr) -> @ast.Stmt {
  { span: dist_span(line), kind: @ast.SLet(x, "", e), }
}

///|
fn dist_store(line : Int32, lhs : @ast.Expr, rhs : @ast.Expr) -> @ast.Stmt {
  { span: dist_span(line), kind: @ast.SAssign(lhs, rhs), }
}

///|
/// A state, from the pairs the test names.
fn dist_state(pairs : Array[(String, @flow.Cpv)]) -> @flow.State {
  let lat = @flow.cprop_lattice()
  let st = (lat.bot)()
  let mut out = st
  for p in pairs {
    out = @flow.cprop_set(out, p.0, p.1)
  }
  out
}

///|
/// THE DECK'S POINTER PROGRAM of p.165-172, with its second statement given
/// by the caller so that one row can change ONE line of it:
///
///   x = new T
///   y = x
///   x.f = x
///   z = y.f
fn dist_deck_body(second : @ast.Expr) -> Array[@ast.Stmt] {
  [
    dist_let(1, "x", dist_new(1, "T")),
    dist_let(2, "y", second),
    dist_store(3, dist_field(dist_name_at(3, "x"), "f"), dist_name_at(3, "x")),
    dist_let(4, "z", dist_field(dist_name_at(4, "y"), "f")),
  ]
}

///|
/// THE DECK'S OWN EXAMPLE, p.158-159: `z = x + y`, and the sentence "z's
/// value depends on both y's and x's".
///
/// AND THE VERDICT IS THE DECK'S: the node reads TWO facts, and the value it
/// defines is not the join of the values the two facts produce alone -- so
/// the statement "needs to consider multiple input data facts to create
/// correct outputs", and p.162's rule says the analysis is not distributive
/// at that node.
///
/// AND THE `one=` NUMBER IS `⊥` AND NOT `NAC`, and that is worth saying: with
/// only `x` known, `x + y` is not "not a constant", it is "nothing has been
/// computed yet". `⊥` absorbs, which is the tree's own rule (cprop.mbt's
/// header), and the two are different answers.
test "0599: the deck's `z = x + y` is not distributive (p.158-163)" {
  let kinds = [
    @flow.Assign("z", dist_bin(@ast.OpAdd, dist_name("x"), dist_name("y"))),
  ]
  let st = dist_state([("x", @flow.C(2)), ("y", @flow.C(3))])
  assert_eq(
    @flow.cprop_distribution_report(kinds, 0, st),
    "reads=2 z:all=5 one=⊥ distributes=false",
  )
  assert_eq(@flow.cprop_distributes(kinds, 0, st), false)
}

///|
/// THE DECK'S OWN HARDER QUESTION, p.164: "think about whether we could do
/// linear constant propagation, e.g., y = 2x + 3, or copy constant
/// propagation, e.g., x = 2, y = x, using IFDS-style analysis?"
///
/// AND THE ANSWER FOR COPY CONSTANT PROPAGATION IS YES, and it is measured
/// rather than asserted: the statement reads ONE fact, so the output with
/// that fact alone IS the output, and p.162's rule has nothing to object to.
///
/// AND THIS IS THE ROW THAT MAKES THE OTHER ROW MEAN SOMETHING: a test whose
/// verdict is always "not distributive" would be measuring nothing.
test "0599: the deck's copy constant propagation IS distributive (p.164)" {
  let kinds = [@flow.Assign("y", dist_name("x"))]
  let st = dist_state([("x", @flow.C(2))])
  assert_eq(
    @flow.cprop_distribution_report(kinds, 0, st),
    "reads=1 y:all=2 one=2 distributes=true",
  )
  assert_eq(@flow.cprop_distributes(kinds, 0, st), true)
}

///|
/// THE OTHER HALF OF p.164: LINEAR constant propagation, `y = 2x + 3`.
///
/// AND IT IS DISTRIBUTIVE FOR THE SAME REASON AND NOT FOR A DIFFERENT ONE: the
/// statement reads ONE fact, `x`. The multiplication and the addition are
/// INSIDE the transfer, and a transfer may use one fact as hard as it likes.
test "0599: the deck's linear constant propagation IS distributive (p.164)" {
  let kinds = [
    @flow.Assign(
      "y",
      dist_bin(
        @ast.OpAdd,
        dist_bin(@ast.OpMul, dist_int(2), dist_name("x")),
        dist_int(3),
      ),
    ),
  ]
  let st = dist_state([("x", @flow.C(3))])
  assert_eq(
    @flow.cprop_distribution_report(kinds, 0, st),
    "reads=1 y:all=9 one=9 distributes=true",
  )
  assert_eq(@flow.cprop_distributes(kinds, 0, st), true)
}

///|
/// THE BOUNDARY OF p.162's RULE, stated so that the rule is not mistaken for
/// "every statement is non-distributive".
///
/// AND IT IS NOT A DODGE: the deck's rule is about a statement that "need[s]
/// to consider multiple input data facts to CREATE CORRECT OUTPUTS", and a
/// statement that reads no fact cannot need two. `z = 5` reads nothing and
/// defines 5, and the output is the same with one fact or with none.
test "0599: a statement that reads no fact is distributive (p.162's boundary)" {
  let kinds = [@flow.Assign("z", dist_int(5))]
  let st = dist_state([("x", @flow.C(2))])
  assert_eq(
    @flow.cprop_distribution_report(kinds, 0, st),
    "reads=0 z:all=5 one=5 distributes=true",
  )
  assert_eq(@flow.cprop_distributes(kinds, 0, st), true)
}

///|
/// THE DECK'S POINTER PROGRAM of p.165-172, and the answer p.171 states:
///
///   z and y.f should have pointed to object [new T]
///
/// AND THE OBJECT IS `o1` IN THIS TREE'S NAMING, because the tree names an
/// object by its allocation site's LINE (the deck's own convention, p.98's
/// `i : x = new T()` with `i` the statement label) and the allocation is on
/// line 1.
///
/// AND THE DECK'S `y.f` IS THE HEAP CELL `o1.f` HERE, and the reason is worth
/// saying: `y.f` is a PLACE, and the place `y.f` denotes is the field cell
/// of the object `y` points to. `y` points to `o1`, so the place is `o1.f`.
test "0599: the deck's pointer program answers p.171 (z and y.f -> new T)" {
  let g = @flow.cfg_of(dist_deck_body(dist_name_at(2, "x")))
  let pt = @flow.pta_run([g])[0]
  assert_eq(@flow.pta_text(pt), "x -> {o1}; y -> {o1}; z -> {o1}; o1.f -> {o1}")
  assert_eq(@flow.pta_points_to_text(pt, "z"), "z -> {o1}")
  assert_eq(@flow.pta_points_to_text(pt, "o1.f"), "o1.f -> {o1}")
}

///|
/// THE DECK'S CONCLUSION, p.172, AS AN EXECUTABLE QUESTION:
///
///   If we want to obtain alias information in IFDS, say alias(x,y), to
///   produce correct outputs, we need to consider multiple input data facts,
///   x and y, which cannot be done in standard IFDS as flow functions handle
///   input facts independently (one fact per time).
///
/// AND THE MEASUREMENT: the relation holds on the whole state and on NO
/// one-fact state, so it cannot be produced one fact at a time. `facts=4` is
/// the four (pointer, object) pairs the state holds -- `x`, `y`, `z` and the
/// cell `o1.f` -- and the relation is false in every one-fact state because
/// no single pair carries both `x` and `y`.
///
/// AND THE CONTROL IS IN THE SAME ROW, because a test that only ever says
/// "false" is not measuring the question: `alias(x,x)` IS a one-fact fact, and
/// the same function says so on the same state.
test "0599: alias(x,y) needs two facts; alias(x,x) does not (p.172)" {
  let g = @flow.cfg_of(dist_deck_body(dist_name_at(2, "x")))
  let pt = @flow.pta_run([g])[0]
  assert_eq(
    @flow.pta_alias_distribution_report(pt, "x", "y"),
    "alias(x,y)=true facts=4 one=false distributes=false",
  )
  assert_eq(@flow.pta_alias_distributes(pt, "x", "y"), false)
  assert_eq(
    @flow.pta_alias_distribution_report(pt, "x", "x"),
    "alias(x,x)=true facts=4 one=true distributes=true",
  )
  assert_eq(@flow.pta_alias_distributes(pt, "x", "x"), true)
}

///|
/// THE DECK'S p.171 SENTENCE, AS AN EXECUTABLE QUESTION: the load `z = y.f`
/// produces the right answer only when it is given MORE THAN ONE FACT.
///
/// AND THE TWO FACTS ARE THE ONES THE DECK NAMES: the fact about `y`, and
/// the fact about the cell `o1.f` -- and the cell exists because `x` pointed
/// to `o1` when the store happened. Drop either and the load produces
/// nothing, which is why the join of the one-fact outputs (`one={}`) is not
/// the output (`{o1}`).
test "0599: the load `z = y.f` needs more than one fact (p.171)" {
  let g = @flow.cfg_of(dist_deck_body(dist_name_at(2, "x")))
  let pt = @flow.pta_run([g])[0]
  assert_eq(
    @flow.pta_load_distribution_report(pt, "y", "f"),
    "load(y.f)={o1} facts=4 one={} distributes=false",
  )
  assert_eq(@flow.pta_load_distributes(pt, "y", "f"), false)
}

///|
/// THE DECK'S CONCLUSION, AS A DIFFERENTIAL: the answer at `z` TRACKS THE
/// ALIAS RELATION, and the two programs differ in ONE LINE.
///
/// AND THE LINE IS LINE 2. `y = x` becomes `y = new U`, so `y` points to a
/// second object, `o2`, and `alias(x,y)` is false. The cell `o1.f` still
/// holds `o1` -- the store did not change -- but `y.f` is the cell of the
/// object `y` points to, and that cell is empty, so `z` points to nothing.
///
/// AND THIS IS THE MEASUREMENT OF p.172'S CLAUSE: "we need alias information
/// to produce correct outputs". The output is right exactly when the alias
/// relation holds, and the relation is a fact about TWO variables.
test "0599: the answer at z tracks the alias relation (p.171-172)" {
  let g = @flow.cfg_of(dist_deck_body(dist_name_at(2, "x")))
  let pt = @flow.pta_run([g])[0]
  assert_eq(@flow.pta_alias(pt, "x", "y"), true)
  assert_eq(@flow.pta_of(pt, "z").length(), 1)
  let g2 = @flow.cfg_of(dist_deck_body(dist_new(2, "U")))
  let pt2 = @flow.pta_run([g2])[0]
  assert_eq(@flow.pta_text(pt2), "x -> {o1}; y -> {o2}; o1.f -> {o1}")
  assert_eq(@flow.pta_alias(pt2, "x", "y"), false)
  assert_eq(@flow.pta_of(pt2, "z").length(), 0)
}
