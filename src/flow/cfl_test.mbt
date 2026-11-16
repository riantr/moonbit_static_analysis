// 0600: CFL-REACHABILITY -- the realizable-path language, and what it says
// about the tree's OWN supergraph.
//
// THE DECK. `CFL-Reachability and IFDS` (Yue Li, Nanjing University, 2021),
// p.24-42 is "CFL-Reachability", and its concrete instance is the
// "Partially Balanced-Parenthesis Problem via CFL" of p.27-39.
//
// AND THE EXPECTED NUMBERS ARE MEASURED, NOT GUESSED: every number below was
// printed by the code that asserts it before it was written down here.
//
// AND THE FIXTURE IS THREE FUNCTIONS, AND WHY:
//
//   fn leaf()   -> Int { return 7 }
//   fn caller() -> Int { let a = leaf(); return a }
//   fn top()    -> Int { let b = caller(); let c = leaf(); return b }
//
// `leaf` IS CALLED FROM TWO PLACES. That is the whole point of the fixture:
// a function called from two places has ONE value exit and TWO return edges,
// so the tree's supergraph holds a path that enters the callee through one
// call and leaves through the other's return edge. The deck's p.24 definition
// says such a path does not connect its two nodes, and the measurement below
// says how many of the graph's own connections that costs.

///|
fn cfl_span(line : Int32) -> @core.Span {
  { start: @core.pos(line, 1), end: @core.pos(line, 1), }
}

///|
fn cfl_int(i : Int32) -> @ast.Expr {
  { span: cfl_span(0), kind: @ast.EInt(i), }
}

///|
fn cfl_name(n : String) -> @ast.Expr {
  { span: cfl_span(0), kind: @ast.EName(n), }
}

///|
fn cfl_call(name : String) -> @ast.Expr {
  { span: cfl_span(0), kind: @ast.ECall(name, [], []), }
}

///|
fn cfl_let(line : Int32, x : String, e : @ast.Expr) -> @ast.Stmt {
  { span: cfl_span(line), kind: @ast.SLet(x, "", e), }
}

///|
fn cfl_ret(line : Int32, e : @ast.Expr) -> @ast.Stmt {
  { span: cfl_span(line), kind: @ast.SReturn(Some(e)), }
}

///|
fn cfl_fn(name : String, body : Array[@ast.Stmt]) -> @flow.IFn {
  { name, params: [], body, }
}

///|
/// THE FIXTURE, on the tree's own interprocedural graph.
fn cfl_program() -> @flow.Icfg {
  let leaf = cfl_fn("leaf", [cfl_ret(1, cfl_int(7))])
  let caller = cfl_fn("caller", [
    cfl_let(2, "a", cfl_call("leaf")),
    cfl_ret(3, cfl_name("a")),
  ])
  let top = cfl_fn("top", [
    cfl_let(4, "b", cfl_call("caller")),
    cfl_let(5, "c", cfl_call("leaf")),
    cfl_ret(6, cfl_name("b")),
  ])
  @flow.icfg_of([leaf, caller, top])
}

///|
/// THE LABELS OF THE WHOLE SUPERGRAPH, as `node:label,label`.
fn cfl_labels_text(g : @flow.Icfg) -> String {
  let all : Array[String] = []
  let mut v = 0
  while v < g.succ.length() {
    let labs : Array[String] = []
    let mut k = 0
    while k < g.succ[v].length() {
      labs.push(@flow.cfl_sym_text(@flow.cfl_edge_symbol(g, v, k)))
      k = k + 1
    }
    all.push(v.to_string() + ":" + labs.join(","))
    v = v + 1
  }
  all.join(" ")
}

///|
/// THE DECK'S OWN PATH of p.29, built from its letters:
///
///   (1 (2 e )2 )1 (3
///
/// AND IT IS REALIZABLE, and the reason it is worth a row is that it is NOT
/// BALANCED: the `(3` at the end is never closed. p.27 says so in the deck's
/// own words -- "Every right parenthesis ')i' is balanced by a preceding left
/// parenthesis '(i', but the converse needs not hold" -- and a recogniser
/// that required a balanced word would reject this slide's own example.
test "0600: the deck's own path is realizable although it is not balanced (p.29)" {
  let word = [
    @flow.Open(1),
    @flow.Open(2),
    @flow.E,
    @flow.Close(2),
    @flow.Close(1),
    @flow.Open(3),
  ]
  assert_eq(@flow.cfl_word_text(word), "(1 (2 e )2 )1 (3")
  assert_eq(@flow.cfl_word_realizable(word), true)
}

///|
/// THE DECK'S FIRST MEMBERSHIP ROW, p.41:
///
///   e(1eee)1e in L(realizable)
test "0600: p.41's word is in L(realizable)" {
  let word = [
    @flow.E,
    @flow.Open(1),
    @flow.E,
    @flow.E,
    @flow.E,
    @flow.Close(1),
    @flow.E,
  ]
  assert_eq(@flow.cfl_word_text(word), "e (1 e e e )1 e")
  assert_eq(@flow.cfl_word_realizable(word), true)
}

///|
/// THE DECK'S SECOND MEMBERSHIP ROW, p.42:
///
///   e(1eee)1e(2eee)1 not in L(realizable)
///
/// AND THE WORD IS THE SLIDE'S OWN, spelled the way the slide spells it --
/// `e(1eee)1e` then `e(2eee)1` -- and the printer writes it with the labels
/// separated by spaces.
///
/// AND THE REASON IS WORTH NAMING, because it is not "a closing parenthesis
/// with no opening one" -- there are two opening ones. The final `)1` closes
/// the `(2` that is still open, and the `(1` was closed long ago.
test "0600: p.42's word is NOT in L(realizable)" {
  let word = [
    @flow.E,
    @flow.Open(1),
    @flow.E,
    @flow.E,
    @flow.E,
    @flow.Close(1),
    @flow.E,
    @flow.Open(2),
    @flow.E,
    @flow.E,
    @flow.E,
    @flow.Close(1),
  ]
  assert_eq(@flow.cfl_word_text(word), "e (1 e e e )1 e (2 e e e )1")
  assert_eq(@flow.cfl_word_realizable(word), false)
}

///|
/// THE DECK'S OWN DERIVATION, p.39, spelled the way the slide spells it:
///
///   e e (1 (2 e e e )2 )1 (3 (4 e
///
/// AND IT IS REALIZABLE, and that is the deck's point: the word ends with an
/// OPENED `(3` and an OPENED `(4` that are never closed, and the grammar's
/// `realizable -> (i realizable` puts exactly that at the front of a
/// realizable word. A recogniser that required the word to be balanced would
/// reject the deck's own derivation.
test "0600: p.39's derivation word is realizable" {
  let word = [
    @flow.E,
    @flow.E,
    @flow.Open(1),
    @flow.Open(2),
    @flow.E,
    @flow.E,
    @flow.E,
    @flow.Close(2),
    @flow.Close(1),
    @flow.Open(3),
    @flow.Open(4),
    @flow.E,
  ]
  assert_eq(@flow.cfl_word_text(word), "e e (1 (2 e e e )2 )1 (3 (4 e")
  assert_eq(@flow.cfl_word_realizable(word), true)
}

///|
/// THE TWO DIRECTIONS OF p.27's SENTENCE, measured apart:
///
///   * an opening parenthesis need NOT be closed -- `(1 (2` is realizable;
///   * a closing one that closes the WRONG one is not -- `(1 (2 )1` is not.
test "0600: p.27's two directions, measured apart" {
  assert_eq(@flow.cfl_word_realizable([@flow.Open(1), @flow.Open(2)]), true)
  assert_eq(
    @flow.cfl_word_realizable([@flow.Open(1), @flow.Open(2), @flow.Close(1)]),
    false,
  )
}

///|
/// THE TREE'S OWN SUPERGRAPH, LABELLED BY THE DECK'S p.27 RULE.
///
/// AND THE LINE THAT MATTERS IS `1:e,)0,)1`: node 1 is `leaf`'s value exit and
/// it carries TWO return edges, because `leaf` is called from two places. The
/// graph has one exit and two returns, and that is what makes the witness
/// below possible.
test "0600: the tree's own supergraph, labelled by p.27's rule" {
  let g = cfl_program()
  assert_eq(g.kinds.length(), 15)
  assert_eq(g.call_sites.length(), 3)
  assert_eq(
    cfl_labels_text(g),
    "0: 1:e,)0,)1 2: 3:e 4: 5:e,)2 6: 7:e,(0 8:e 9: 10:e 11: 12:e,(1 13:e,(2 14:e",
  )
}

///|
/// THE WITNESS: A PATH IN THE TREE'S OWN SUPERGRAPH THAT IS NOT A CALL
/// SEQUENCE.
///
/// AND THE WORD IS `e e (1 e )0`, and reading it: the path takes `leaf`
/// through call site 1 -- the `(1` -- and leaves through the return edge of
/// call site 0 -- the `)0`. The stack holds one open parenthesis when the
/// `)0` arrives, and it holds site 1, so the `)0` closes the wrong one.
///
/// AND THE PROGRAM'S ENTRY IS DERIVED, NOT ASSUMED: `top` is the function no
/// call reaches, so it is the one the deck's single entry node stands for.
test "0600: the tree's own supergraph holds a path that is not a call sequence" {
  let g = cfl_program()
  let entry = @flow.cfl_program_entry(g)
  assert_eq(entry, 14)
  let r = @flow.cfl_search_from(g, entry, 200000)
  assert_eq(r.found, true)
  assert_eq(r.bounded, false)
  assert_eq(@flow.cfl_word_text(r.word), "e (2 e (0 e )1")
  // THE STACK AT THE OFFENDING EDGE: two open parentheses, and the top is
  // site 0 -- so the `)1` closes the wrong one.
  assert_eq(r.stack.length(), 2)
  assert_eq(r.stack[0], 2)
  assert_eq(r.stack[1], 0)
  // AND THE WORD IS NOT IN THE LANGUAGE, which is the whole claim.
  assert_eq(@flow.cfl_word_realizable(r.word), false)
  assert_eq(r.states, 15)
}

///|
/// THE MEASUREMENT: HOW MANY OF THE GRAPH'S OWN CONNECTIONS THE DECK'S
/// DEFINITION KEEPS.
///
/// AND THE THREE NUMBERS ARE `(ordinary, realizable, excluded)`, and the
/// third is the difference -- because a realizable path IS a path, so the
/// language can only DROP connections. 25 of the graph's 82 own connections
/// are dropped, and every one of them is a connection that exists in the
/// graph and is not a call sequence.
test "0600: the deck's definition drops 25 of the graph's 82 connections" {
  let g = cfl_program()
  let counts = @flow.cfl_pair_counts(g, 200000)
  assert_eq(counts.0, 82)
  assert_eq(counts.1, 57)
  assert_eq(counts.2, 25)
  // AND THE THIRD NUMBER IS THE DIFFERENCE, not a third opinion.
  assert_eq(counts.2, counts.0 - counts.1)
}
