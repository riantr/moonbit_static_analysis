// 0573: the intraprocedural constant propagation -- deck 5-6 §10 -- and the
// work-list algorithm -- deck 5-6 §11 -- pinned to the deck's own numbers.
//
// THE NUMBERS ARE THE SLIDES', NOT THE IMPLEMENTATION'S. `Data Flow Analysis --
// Foundations` (Yue Li, Nanjing University) prints a lattice (p.236-238), a
// transfer function (p.240-245), a worked graph with two answers (p.249-252) and
// a task -- "Show our constant propagation analysis is monotonic" (p.254). Every
// row below asserts one of those.
//
// WHY HAND-BUILT AND NOT PARSED: the same reason `reaching_test.mbt` gives. This
// package does not depend on the PARSER, so a test builds an `Expr` without
// reaching for it; the one frontend dependency it has is the LEXER, and
// `callgraph.mbt` says why.

///|
/// A literal.
fn ci_lit(i : Int32) -> @ast.Expr {
  { span: @flow.no_span(), kind: @ast.EInt(i), }
}

///|
/// A name.
fn ci_name(x : String) -> @ast.Expr {
  { span: @flow.no_span(), kind: @ast.EName(x), }
}

///|
/// `a + b`.
fn ci_add(a : @ast.Expr, b : @ast.Expr) -> @ast.Expr {
  { span: @flow.no_span(), kind: @ast.EBin(@ast.OpAdd, a, b), }
}

///|
/// A graph with the given nodes and the given successors.
fn ci_graph(
  kinds : Array[@flow.NodeKind],
  succs : Array[Array[Int32]],
) -> @flow.Cfg {
  let spans : Array[@core.Span] = []
  let mut i = 0
  while i < kinds.length() {
    spans.push(@flow.no_span())
    i = i + 1
  }
  {
    kinds,
    spans,
    succ: succs,
    pred: @flow.pred_of(succs),
    entry: 0,
    exit: kinds.length() - 1,
    skipped: 0,
  }
}

///|
/// The state in which the deck's figures are expressed.
fn ci_show(st : @flow.State, names : Array[String]) -> String {
  let parts : Array[String] = []
  for n in names {
    parts.push(n + "=" + @flow.cpv_text(@flow.cprop_get(st, n)))
  }
  parts.join(",")
}

///|
/// THE DECK'S p.249 GRAPH, with its own node numbers:
///
///     Entry
///       |    \
///      v      v
///     X        Y          X: a = 1; b = 9      Y: a = 9; b = 1
///      \      /
///       v    v
///        Z                 Z: c = a + b
///        |
///        v
///      Exit
fn ci_deck_graph() -> @flow.Cfg {
  ci_graph(
    [
      @flow.Entry,
      @flow.Assign("a", ci_lit(1)), // X, first statement
      @flow.Assign("b", ci_lit(9)), // X, second statement
      @flow.Assign("a", ci_lit(9)), // Y, first statement
      @flow.Assign("b", ci_lit(1)), // Y, second statement
      @flow.Assign("c", ci_add(ci_name("a"), ci_name("b"))), // Z
      @flow.Exit,
    ],
    [
      [1, 3], // Entry -> X, Entry -> Y
      [2], // X
      [5], // X -> Z
      [4], // Y
      [5], // Y -> Z
      [6], // Z -> Exit
      [], // Exit
    ],
  )
}

// ---------------------------------------------------------------------------
// A -- the meet, p.236-238
// ---------------------------------------------------------------------------

///|
/// THE DECK'S MEET TABLE, asserted through the SHIPPED LATTICE.
///
/// The four rules of p.238 are the whole operator:
///
///     NAC  ⊓ v = NAC
///     UNDEF ⊓ v = v
///     c    ⊓ c  = c
///     c1   ⊓ c2 = NAC      (c1 ≠ c2)
///
/// THE MEET IS OBSERVED THROUGH A STATE, and that is how the analysis uses it:
/// the lattice is over states, a state's value for a name is the deck's `val(x)`,
/// and a name with no entry at all is the deck's `UNDEF`. So each rule is a
/// statement about what a join of two states does to one name.
///
/// The join is read off the lattice rather than written out again here: a second
/// copy of the meet in a test is a second definition of "the value of a name",
/// and 0545's lesson is that those two copies disagree.
test "0573: the deck's meet table -- NAC absorbs, UNDEF is the identity" {
  let lat = @flow.cprop_lattice()
  let none : @flow.State = Map([])
  let one : @flow.State = Map([])
  one.set("x", @flow.C(1))
  let two : @flow.State = Map([])
  two.set("x", @flow.C(2))
  let nac : @flow.State = Map([])
  nac.set("x", @flow.Nac)
  // UNDEF ⊓ v = v -- a name with no value does not change the join.
  assert_eq(ci_show((lat.join)(none, one), ["x"]), "x=1")
  assert_eq(ci_show((lat.join)(one, none), ["x"]), "x=1")
  // NAC ⊓ v = NAC -- the top absorbs.
  assert_eq(ci_show((lat.join)(nac, one), ["x"]), "x=NAC")
  assert_eq(ci_show((lat.join)(one, nac), ["x"]), "x=NAC")
  // c ⊓ c = c
  assert_eq(ci_show((lat.join)(one, one), ["x"]), "x=1")
  // c1 ⊓ c2 = NAC
  assert_eq(ci_show((lat.join)(one, two), ["x"]), "x=NAC")
}

// ---------------------------------------------------------------------------
// B -- the transfer, p.240-245
// ---------------------------------------------------------------------------

///|
/// THE DECK'S THREE GEN RULES, and the identity for everything else.
///
///     s: x = c;            gen = {(x, c)}
///     s: x = y;            gen = {(x, val(y))}
///     s: x = y op z;       gen = {(x, f(y,z))}
///     (if s is not an assignment statement, F is the identity function)
///
/// The evaluator is the deck's `f` and `val` and the setter is the deck's
/// `gen ∪ (IN - {(x,_)})`, and the two are read here rather than reimplemented.
test "0573: the deck's gen rules -- a constant, a name, and a fold" {
  let st : @flow.State = Map([])
  st.set("y", @flow.C(4))
  st.set("z", @flow.C(6))
  // `x = c` -- the value of the expression is the constant.
  assert_eq(@flow.cpv_text(@flow.cprop_eval(st, ci_lit(7))), "7")
  // `x = y` -- the value of the expression is the value of the name.
  assert_eq(@flow.cpv_text(@flow.cprop_eval(st, ci_name("y"))), "4")
  // `x = y op z` -- the value is the fold of the two values.
  assert_eq(
    @flow.cpv_text(@flow.cprop_eval(st, ci_add(ci_name("y"), ci_name("z")))),
    "10",
  )
  // AND THE ASSIGNMENT SETS THE NAME, which is the other half of the rule:
  // `gen ∪ (IN - {(x,_)})` REPLACES the name's old value.
  let kinds = [@flow.Assign("x", ci_lit(7))]
  let t = @flow.cprop_intra_transfer(kinds)
  let after = t(0, st)
  assert_eq(ci_show(after, ["x", "y"]), "x=7,y=4")
  // A name that is not assigned keeps its old value, and a node that is not an
  // assignment changes nothing at all.
  let kinds2 = [@flow.Eval(ci_lit(7))]
  let t2 = @flow.cprop_intra_transfer(kinds2)
  assert_eq(ci_show(t2(0, st), ["x", "y"]), "x=⊥,y=4")
}

///|
/// A CALL'S RESULT IS NOT A CONSTANT, and that is the difference between the two
/// decks.
///
/// 7_Inter's p.105 makes the node transfer at a call node the IDENTITY, because
/// the interprocedural framework has an edge that carries the returned value.
/// The intraprocedural framework has no such edge, so the value is simply not
/// known -- and `NAC` is the answer.
test "0573: a call's result is NAC, where the interprocedural rule is the identity" {
  let call : @ast.Expr = {
    span: @flow.no_span(),
    kind: @ast.ECall("f", [], []),
  }
  let kinds = [@flow.Assign("x", call)]
  let t = @flow.cprop_intra_transfer(kinds)
  let st : @flow.State = Map([])
  assert_eq(ci_show(t(0, st), ["x"]), "x=NAC")
}

// ---------------------------------------------------------------------------
// C -- the confluence and the nondistributivity, p.238 and p.249-252
// ---------------------------------------------------------------------------

///|
/// THE MEET AT THE PATH CONFLUENCE, and the deck's TWO ANSWERS.
///
/// p.238: "At each path confluence PC, we should apply 'meet' for all variables
/// in the incoming data-flow values at that PC". At Z the two predecessors carry
/// `a=1, b=9` and `a=9, b=1`, so the meet gives `a=NAC, b=NAC` -- and the
/// analysis, which transforms AFTER the meet, answers `c=NAC`.
///
/// p.251-252 print the other order as well:
///
///     F(X ⊓ Y)          = {(a, NAC), (b, NAC), (c, NAC)}
///     F(X) ⊓ F(Y)       = {(a, NAC), (b, NAC), (c, 10)}
///     F(X ⊓ Y) ≠ F(X) ⊓ F(Y)
///
/// so the analysis is IMPRECISE at the join: the sum 1+9 and the sum 9+1 are
/// both 10, but the meet has already thrown the constants away.
test "0573: the deck's confluence -- F(X meet Y) is not F(X) meet F(Y)" {
  let g = ci_deck_graph()
  let outs = @flow.cprop_intra_run(g)
  let ins = @flow.cprop_intra_in(g, outs)
  // THE MEET AT THE CONFLUENCE: the two branches' values do not agree, so both
  // names are NAC there.
  assert_eq(ci_show(ins[5], ["a", "b"]), "a=NAC,b=NAC")
  // THE ANALYSIS'S ANSWER, which is the deck's F(X ⊓ Y).
  assert_eq(ci_show(outs[5], ["a", "b", "c"]), "a=NAC,b=NAC,c=NAC")
  // AND THE OTHER ORDER, which the deck prints as F(X) ⊓ F(Y): each branch is
  // transformed FIRST, and then the two answers are met.
  let t = @flow.cprop_intra_transfer(g.kinds)
  let fx = t(5, outs[2])
  let fy = t(5, outs[4])
  assert_eq(ci_show(fx, ["a", "b", "c"]), "a=1,b=9,c=10")
  assert_eq(ci_show(fy, ["a", "b", "c"]), "a=9,b=1,c=10")
  let lat = @flow.cprop_lattice()
  let met = (lat.join)(fx, fy)
  assert_eq(ci_show(met, ["a", "b", "c"]), "a=NAC,b=NAC,c=10")
  // AND THE TWO ARE NOT THE SAME, which is the deck's last line: constant
  // propagation is not distributive.
  assert_true(
    ci_show(met, ["a", "b", "c"]) != ci_show(outs[5], ["a", "b", "c"]),
  )
}

// ---------------------------------------------------------------------------
// D -- monotonicity, p.254
// ---------------------------------------------------------------------------

///|
/// THE DECK'S LAST TASK: "Show our constant propagation analysis is monotonic".
///
/// THE ORDER IS THE LATTICE'S, and the claim is the ordinary one: if the input
/// state is no more precise than another, the output state is too. The rows
/// walk the order up one name at a time -- `b` goes from a constant to `NAC`,
/// then `a` does -- and the output follows.
test "0573: the transfer is monotone in the lattice's order" {
  let kinds = [@flow.Assign("c", ci_add(ci_name("a"), ci_name("b")))]
  let t = @flow.cprop_intra_transfer(kinds)
  let sharp : @flow.State = Map([("a", @flow.C(1)), ("b", @flow.C(2))])
  let blunt : @flow.State = Map([("a", @flow.C(1)), ("b", @flow.Nac)])
  let blunter : @flow.State = Map([("a", @flow.Nac), ("b", @flow.Nac)])
  // THE ORDER: the sharper state is below the blunter ones.
  assert_true(@flow.cprop_state_leq(sharp, blunt))
  assert_true(@flow.cprop_state_leq(blunt, blunter))
  assert_true(@flow.cprop_state_leq(sharp, blunter))
  assert_false(@flow.cprop_state_leq(blunter, blunt))
  // AND THE TRANSFER FOLLOWS IT: a coarser input gives a coarser output.
  let fs = t(0, sharp)
  let fb = t(0, blunt)
  let fbb = t(0, blunter)
  assert_eq(ci_show(fs, ["c"]), "c=3")
  assert_eq(ci_show(fb, ["c"]), "c=NAC")
  assert_eq(ci_show(fbb, ["c"]), "c=NAC")
  assert_true(@flow.cprop_state_leq(fs, fb))
  assert_true(@flow.cprop_state_leq(fb, fbb))
  assert_true(@flow.cprop_state_leq(fs, fbb))
}

// ---------------------------------------------------------------------------
// E -- the work list, p.256-260
// ---------------------------------------------------------------------------

///|
/// THE WORK LIST AND THE ROUND-ROBIN SOLVER AGREE, NODE FOR NODE.
///
/// The deck calls the work list "an optimization of Iterative Algorithm"
/// (p.256), which is a claim that the two compute the SAME fixed point and
/// differ only in how much work they do. A claim like that is a theorem until
/// it is a comparison, and this package's own doctrine is that one solver is
/// the test of the next.
test "0573: the deck's work list and the round-robin solver agree node for node" {
  let g = ci_deck_graph()
  let wl = @flow.cprop_intra_run(g)
  let rr = @flow.solve_round_robin(
    @flow.cprop_lattice(),
    g.kinds.length(),
    g.pred,
    @flow.cprop_intra_transfer(g.kinds),
  )
  let mut v = 0
  while v < g.kinds.length() {
    assert_eq(@flow.cprop_text(wl[v]), @flow.cprop_text(rr[v]))
    v = v + 1
  }
}

///|
/// THE WORK LIST REVISITS A BLOCK ONLY WHEN ITS OUT MOVED, and that is what
/// makes it an optimization rather than a different algorithm.
///
/// The block `Z` has two predecessors, and the first sweep reaches it with the
/// FIRST branch's value already in place -- so the second branch's arrival is
/// what moves it. The point of the row is the SHAPE of the answer: the state
/// that arrives at Z is the MEET of the two branches, which is what the
/// confluence row above asserts, and it is the meet rather than the last
/// branch's value because the work list JOINS the incoming states instead of
/// overwriting them.
test "0573: the work list joins the incoming states rather than overwriting them" {
  let g = ci_deck_graph()
  let outs = @flow.cprop_intra_run(g)
  // If the work list had overwritten, `a` would be 9 or 1 -- the LAST branch's
  // value. It is NAC, which is the meet.
  assert_eq(ci_show(outs[5], ["a"]), "a=NAC")
  // and the two branches' own states are untouched by the join.
  assert_eq(ci_show(outs[2], ["a", "b"]), "a=1,b=9")
  assert_eq(ci_show(outs[4], ["a", "b"]), "a=9,b=1")
}
