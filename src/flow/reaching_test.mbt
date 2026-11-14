// 0572: the reaching-definitions analysis, pinned to the deck's own tables.
//
// THE NUMBERS ARE THE SLIDES', NOT THE IMPLEMENTATION'S. `Data Flow Analysis
// -- Applications` (Yue Li, Nanjing University) prints two worked examples and
// this file asserts both:
//
//   p.48   the GENERATE/KILL table of a four-block program, block by block
//   p.65   the eight-definition program, with its bit-vector iteration
//
// WHY HAND-BUILT AND NOT PARSED: the same reason `flow_live_test.mbt` gives.
// This package does not depend on the PARSER, so a test builds an `Expr`
// without reaching for the parser -- which is what the toolchain's
// `--deny-warn` treatment of test-only imports forces (0526, 0527). The
// graphs below are small on purpose: a data-flow test should fail on the
// ANALYSIS, not on a fifteen-statement fixture whose shape nobody re-derives.

///|
/// An expression that READS one name without needing an operator table: a list
/// literal of one element.
fn rd(n : String) -> @ast.Expr {
  {
    span: @flow.no_span(),
    kind: @ast.EList([{ span: @flow.no_span(), kind: @ast.EName(n), }]),
  }
}

///|
/// A literal.
fn lit(i : Int32) -> @ast.Expr {
  { span: @flow.no_span(), kind: @ast.EInt(i), }
}

///|
/// A graph with the given nodes and the given successors.
fn reaching_graph(
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
/// The union of the sets of two nodes -- the deck's BLOCK-level `gen_B` and
/// `kill_B`, which are the union over the block's statements.
fn union_of(sets : Array[@flow.DefSet], nodes : Array[Int32]) -> @flow.DefSet {
  let out = @flow.name_set_empty()
  for n in nodes {
    for k, _ in sets[n] {
      out.set(k, true)
    }
  }
  out
}

///|
/// THE DECK'S p.48 EXAMPLE, block for block.
///
/// The slide draws four blocks over seven definitions:
///
///   B1   d1: i = m-1   d2: j = n   d3: a = u1
///   B2   d4: i = i+1   d5: j = j-1
///   B3   d6: a = u2
///   B4   d7: i = u3
///
/// and prints, for each block, the definitions it generates and the ones it
/// kills:
///
///   gen_B1 = {d1,d2,d3}   kill_B1 = {d4,d5,d6,d7}
///   gen_B2 = {d4,d5}       kill_B2 = {d1,d2,d7}
///   gen_B3 = {d6}          kill_B3 = {d3}
///   gen_B4 = {d7}          kill_B4 = {d1,d4}
///
/// and the shape: B1 -> B2 -> {B3, B4}, B3 -> B4, B4 -> Exit, and B4 -> B1.
fn deck_p48() -> @flow.Cfg {
  reaching_graph(
    [
      @flow.Entry,
      @flow.Assign("i", rd("m")), // d1
      @flow.Assign("j", rd("n")), // d2
      @flow.Assign("a", rd("u1")), // d3
      @flow.Assign("i", rd("i")), // d4
      @flow.Assign("j", rd("j")), // d5
      @flow.Assign("a", rd("u2")), // d6
      @flow.Assign("i", rd("u3")), // d7
      @flow.Exit,
    ],
    [
      [1], // Entry -> B1
      [2], // B1
      [3], // B1
      [4], // B1 -> B2
      [5], // B2
      [6, 7], // B2 -> {B3, B4}
      [7], // B3 -> B4
      [8, 1], // B4 -> Exit, and B4 -> B1
      [], // Exit
    ],
  )
}

///|
test "0572: the deck's p.48 gen and kill, block by block" {
  let g = deck_p48()
  let gen = @flow.reaching_gen(g)
  let kill = @flow.reaching_kill(g)
  // THE STATEMENT LEVEL: each statement generates its own definition and kills
  // the other definitions of the same variable.
  assert_true(gen[1].contains("i@1"))
  assert_true(kill[1].contains("i@4"))
  assert_true(kill[1].contains("i@7"))
  assert_true(gen[2].contains("j@2"))
  assert_true(kill[2].contains("j@5"))
  assert_true(gen[3].contains("a@3"))
  assert_true(kill[3].contains("a@6"))
  assert_true(gen[4].contains("i@4"))
  assert_true(kill[4].contains("i@1"))
  assert_true(kill[4].contains("i@7"))
  assert_true(gen[5].contains("j@5"))
  assert_true(kill[5].contains("j@2"))
  assert_true(gen[6].contains("a@6"))
  assert_true(kill[6].contains("a@3"))
  assert_true(gen[7].contains("i@7"))
  assert_true(kill[7].contains("i@1"))
  assert_true(kill[7].contains("i@4"))
  // A definition of a variable nobody else defines kills nothing: `m` in the
  // deck's other example is such a variable, and here `a` is defined twice.
  assert_false(kill[1].contains("j@2"))

  // THE BLOCK LEVEL, which is what the slide prints. The block's gen is the
  // union of its statements' gens and its kill is the union of their kills.
  assert_true(union_of(gen, [1, 2, 3]).contains("i@1"))
  assert_true(union_of(gen, [1, 2, 3]).contains("j@2"))
  assert_true(union_of(gen, [1, 2, 3]).contains("a@3"))
  let kill_b1 = union_of(kill, [1, 2, 3])
  assert_true(kill_b1.contains("i@4"))
  assert_true(kill_b1.contains("i@7"))
  assert_true(kill_b1.contains("j@5"))
  assert_true(kill_b1.contains("a@6"))
  let kill_b2 = union_of(kill, [4, 5])
  assert_true(kill_b2.contains("i@1"))
  assert_true(kill_b2.contains("i@7"))
  assert_true(kill_b2.contains("j@2"))
  let kill_b3 = union_of(kill, [6])
  assert_true(kill_b3.contains("a@3"))
  assert_false(kill_b3.contains("i@4"))
  let kill_b4 = union_of(kill, [7])
  assert_true(kill_b4.contains("i@1"))
  assert_true(kill_b4.contains("i@4"))
  assert_false(kill_b4.contains("j@5"))
}

///|
test "0572: what reaches what -- the deck's definition, measured" {
  let g = deck_p48()
  let out = @flow.reaching_out(g)
  let ins = @flow.reaching_in(g, out)
  // `i = i + 1` (d4) READS `i`, and the definition that reaches it is d1: the
  // path from d1 to d4 kills nothing that defines `i`.
  assert_true(ins[4].contains("i@1"))
  assert_false(ins[4].contains("i@4"))
  assert_false(ins[4].contains("i@7"))
  // `j = j - 1` (d5) reads `j`, and d2 is the definition that reaches it.
  assert_true(ins[5].contains("j@2"))
  assert_false(ins[5].contains("j@5"))
  // `i = u3` (d7) does not read `i`, and the definition of `i` that reaches it
  // is d4 -- d1 was killed by d4 and d7 is the node's own definition, which is
  // not in its own IN-set.
  assert_true(ins[7].contains("i@4"))
  assert_false(ins[7].contains("i@1"))
  assert_false(ins[7].contains("i@7"))
  // THE BACK EDGE: B4 -> B1 carries d7 back to the top of the loop, so d7
  // reaches d1 -- and d1's own definition does NOT, because d7 KILLS it on
  // the way around. That is the whole point of a kill: the definition made
  // at a node reaches the nodes AFTER it, and a definition that is killed
  // on every path back does not come round again.
  assert_true(ins[1].contains("i@7"))
  assert_false(ins[1].contains("i@1"))
  // A definition that is killed on the way does not reach: `a` is defined by
  // d3 and d6, and at d4 the definition of `a` that reaches it is d3, because
  // d6 is downstream of d4 on one path and behind it on the other.
  assert_true(ins[4].contains("a@3"))
  assert_false(ins[4].contains("a@6"))
}

///|
test "0572: the use-def chain names the write a read observes" {
  let g = deck_p48()
  let out = @flow.reaching_out(g)
  let ins = @flow.reaching_in(g, out)
  let ud = @flow.reaching_use_defs(g, ins)
  // `i = i + 1` observes d1, and ONLY d1.
  assert_true(ud[4].contains("i@1"))
  assert_false(ud[4].contains("i@4"))
  // `j = j - 1` observes d2.
  assert_true(ud[5].contains("j@2"))
  // `a = u2` reads nothing, so the chain for it is empty.
  assert_true(ud[6].length() == 0)
  // `i = u3` reads nothing either, even though it DEFINES `i`: the definition
  // a node makes is not a read of it.
  assert_true(ud[7].length() == 0)
}

///|
test "0572: the deck's p.65 program -- eight definitions, statement by statement" {
  // the slide's program, in the order the slide numbers it:
  //   D1: x = p + 1   D2: y = q + 2   D3: m = k     D4: y = q - 1
  //   D5: x = 4       D6: z = 5       D7: x = m - 3 D8: z = 2p
  let g = reaching_graph(
    [
      @flow.Entry,
      @flow.Assign("x", rd("p")), // D1
      @flow.Assign("y", rd("q")), // D2
      @flow.Assign("m", rd("k")), // D3
      @flow.Assign("y", rd("q")), // D4
      @flow.Assign("x", lit(4)), // D5
      @flow.Assign("z", lit(5)), // D6
      @flow.Assign("x", rd("m")), // D7
      @flow.Assign("z", rd("p")), // D8
      @flow.Exit,
    ],
    [[1], [2], [3], [4], [5], [6], [7], [8], [9], []],
  )
  let gen = @flow.reaching_gen(g)
  let kill = @flow.reaching_kill(g)
  // EVERY STATEMENT GENERATES EXACTLY ONE DEFINITION, and it is the one the
  // slide numbers: D1 defines `x`, D3 defines `m`, and so on.
  assert_true(gen[1].contains("x@1"))
  assert_true(gen[3].contains("m@3"))
  assert_true(gen[8].contains("z@8"))
  // D1 kills D5 and D7 -- the other two definitions of `x`.
  assert_true(kill[1].contains("x@5"))
  assert_true(kill[1].contains("x@7"))
  assert_false(kill[1].contains("y@2"))
  // D2 and D4 are the two definitions of `y`, so each kills the other.
  assert_true(kill[2].contains("y@4"))
  assert_true(kill[4].contains("y@2"))
  // D3 defines `m` and nothing else defines it, so it kills nothing.
  assert_true(kill[3].length() == 0)
  // D6 and D8 are the two definitions of `z`.
  assert_true(kill[6].contains("z@8"))
  assert_true(kill[8].contains("z@6"))
  // D5 kills D1 and D7; D7 kills D1 and D5.
  assert_true(kill[5].contains("x@1"))
  assert_true(kill[5].contains("x@7"))
  assert_true(kill[7].contains("x@1"))
  assert_true(kill[7].contains("x@5"))
  // AND THE ITERATION: the last definition of a variable kills the earlier
  // ones on the way, so at D8 the only definition of `x` that reaches it is
  // D7, and the only definition of `y` is D4.
  let out = @flow.reaching_out(g)
  let ins = @flow.reaching_in(g, out)
  assert_true(ins[8].contains("x@7"))
  assert_false(ins[8].contains("x@1"))
  assert_false(ins[8].contains("x@5"))
  assert_true(ins[8].contains("y@4"))
  assert_false(ins[8].contains("y@2"))
  assert_true(ins[8].contains("m@3"))
}

///|
test "0572: the lattice of the sets -- the four laws, over the whole carrier" {
  let lat = @flow.def_set_lattice()
  let a = @flow.name_set_empty()
  a.set("x@1", true)
  a.set("y@2", true)
  let b = @flow.name_set_empty()
  b.set("y@2", true)
  b.set("z@3", true)
  let bot = (lat.bot)()
  // THE BOTTOM IS THE EMPTY SET and it is an identity for the join.
  assert_true((lat.join)(bot, a) == a)
  assert_true((lat.join)(a, bot) == a)
  // THE JOIN IS A UNION: commutative, associative and idempotent.
  assert_true((lat.join)(a, b) == (lat.join)(b, a))
  let c = @flow.name_set_empty()
  c.set("w@4", true)
  assert_true(
    (lat.join)((lat.join)(a, b), c) == (lat.join)(a, (lat.join)(b, c)),
  )
  assert_true((lat.join)(a, a) == a)
  // AND THE EQUALITY IS EQUALITY: two sets with the same members are equal,
  // and a set with one more member is not.
  assert_true((lat.eq)(a, a))
  assert_false((lat.eq)(a, b))
  // THE ORDER IS INCLUSION, and the join is the least upper bound: it
  // contains both, and neither of them contains it.
  assert_true((lat.join)(a, b).contains("x@1"))
  assert_true((lat.join)(a, b).contains("z@3"))
  assert_false(a.contains("z@3"))
  assert_false(b.contains("x@1"))
}

///|
test "0572: the deck's p.46 rule -- a definition is killed by the NEXT write, not by a read" {
  // `x = 1` then `y = x` then `x = 2`: the READ of x does not kill the
  // definition, so the definition of x still reaches the second write -- and
  // the second write kills it.
  let g = reaching_graph(
    [
      @flow.Entry,
      @flow.Assign("x", lit(1)),
      @flow.Assign("y", rd("x")),
      @flow.Assign("x", lit(2)),
      @flow.Exit,
    ],
    [[1], [2], [3], [4], []],
  )
  let out = @flow.reaching_out(g)
  let ins = @flow.reaching_in(g, out)
  // The read of `x` observes the first definition.
  assert_true(ins[2].contains("x@1"))
  // A KILL TAKES EFFECT AFTER THE NODE, so the old definition of `x` still
  // REACHES the write that kills it -- and the node's own definition is not
  // in its own IN-set.
  assert_true(ins[3].contains("x@1"))
  assert_false(ins[3].contains("x@3"))
  // And past the write, the old definition is gone and the new one is there.
  assert_true(out[3].contains("x@3"))
  assert_false(out[3].contains("x@1"))
}
