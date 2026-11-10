// 0551: basic blocks, pinned to the deck's printed leaders, blocks and CFG.
//
// THE REFERENCE IS A NEW LECTURE: Yue Li, `Intermediate Representation`, Nanjing
// University, Fall 2026 -- the same series as the `Interprocedural Analysis` deck
// 0546 read. Its "The X You Need To Understand" (p.95) names two of its sections
// as the executable questions, and BOTH have a printed worked example:
//
//   * "How to build basic blocks on top of IR"
//   * "How to construct control flow graphs on top of BBs?"
//
// THE EXAMPLE IS TWELVE INSTRUCTIONS, printed from p.46 to p.71:
//
//     (1) x = input          (7) a = q            (11) goto (3)
//     (2) y = x - 1          (8) b = x + a        (12) return
//     (3) z = x * y          (9) c = 2a - b
//     (4) if z < x goto (7)  (10) if p == q goto (12)
//     (5) p = x / y          (6) q = p + y
//
// with the LEADERS printed at p.68 and the BLOCKS printed at p.71:
//
//   Leaders: (1), (3), (5), (7), (11), (12)
//   B1 {(1),(2)}   B2 {(3),(4)}   B3 {(5),(6)}
//   B4 {(7),(8),(9),(10)}   B5 {(11)}   B6 {(12)}
//
// and the CFG over those blocks drawn at p.93.
//
// WHY THE EXPECTATIONS ARE THE DECK'S AND NOT THIS TREE'S. A test that asserted
// only "the blocks partition the graph" would pass for a layer that computes
// the WRONG blocks, and this tree has shipped a layer like that: the first
// draft of `bb_of` recorded a block only for its LEADERS, so the edges of
// every other node were dropped, and the graph still had the right number of
// blocks and the right leaders. The rows below therefore name the deck's
// leaders, the deck's blocks and the deck's edges, one by one.
//
// WHY THE FIRST FIXTURE IS HAND-BUILT AND THE SECOND IS NOT. The deck's program
// is THREE-ADDRESS CODE: a flat list of instructions with explicit `goto`s.
// This tree has no IR, and its CFG is a graph of STATEMENTS, so two of the
// deck's instructions have no MoonBit statement to come from -- the
// unconditional `goto (3)` and the `return` that leaves the program. The first
// fixture therefore builds the graph by hand, IN THE SHAPE `cfg_of` PRODUCES:
// nodes allocated BACK TO FRONT, so the block layer's source order is exercised
// rather than assumed. The second fixture is built by `cfg_of` itself, because
// a layer that only works on hand-built graphs has not been shown to work.
//
// AND THE PAYLOAD OF A NODE IS NEVER READ BY THE BLOCK LAYER, so the fixtures
// give each node the name the deck's instruction assigns or tests rather than
// reconstructing the arithmetic. A block is a run of instructions and a
// branch is a branch; what the arithmetic is does not change either.

///|
/// The deck's twelve instructions as a graph, in the shape `cfg_of` builds.
///
/// THE NODE INDICES RUN BACKWARDS, like `cfg_of`'s: the Exit is node 0, the
/// instructions are nodes 12 down to 1 for instructions (1) up to (12), and the
/// Entry is node 13. So the node of instruction `k` is `13 - k`.
///
/// THE UNCONDITIONAL `goto (3)` IS A `Test` WITH ONE SUCCESSOR. This tree's CFG
/// has one branch kind and it always splits, so a jump that does not split is
/// encoded as a branch with a single successor. The block layer decides what a
/// branch is BY KIND, and this is the fixture that proves the decision has to
/// be by kind: a successor-count test would call (11) a non-branch, and B5
/// would swallow the instruction after it.
fn bb_deck_graph() -> @flow.Cfg {
  let kinds : Array[@flow.NodeKind] = [
    @flow.Exit,
    @flow.Stop, // (12) return
    @flow.Test(p_name_at(11, 1, "goto")), // (11) goto (3)
    @flow.Test(p_name_at(10, 1, "p")), // (10) if p == q goto (12)
    @flow.Assign("c", p_name("a")), // (9) c = 2a - b
    @flow.Assign("b", p_name("x")), // (8) b = x + a
    @flow.Assign("a", p_name("q")), // (7) a = q
    @flow.Assign("q", p_name("p")), // (6) q = p + y
    @flow.Assign("p", p_name("x")), // (5) p = x / y
    @flow.Test(p_name_at(4, 1, "z")), // (4) if z < x goto (7)
    @flow.Assign("z", p_name("x")), // (3) z = x * y
    @flow.Assign("y", p_name("x")), // (2) y = x - 1
    @flow.Assign("x", p_call("input")), // (1) x = input
    @flow.Entry,
  ]
  let succ : Array[Array[Int32]] = [
    [], // (0) Exit
    [0], // (1) (12) return -> Exit
    [10], // (2) (11) goto (3)
    [1, 2], // (3) (10) if p == q goto (12), else (11)
    [3], // (4) (9)
    [4], // (5) (8)
    [5], // (6) (7)
    [6], // (7) (6)
    [7], // (8) (5)
    [6, 8], // (9) (4) if z < x goto (7), else (5)
    [9], // (10) (3)
    [10], // (11) (2)
    [11], // (12) (1)
    [12], // (13) Entry
  ]
  // The position of a node is the position of the instruction it is, so the
  // source order of the graph is the order of the deck's instructions.
  let spans : Array[@core.Span] = [
    @flow.no_span(), // (0) Exit
    p_span(12), // (1) (12)
    p_span(11), // (2) (11)
    p_span(10), // (3) (10)
    p_span(9), // (4) (9)
    p_span(8), // (5) (8)
    p_span(7), // (6) (7)
    p_span(6), // (7) (6)
    p_span(5), // (8) (5)
    p_span(4), // (9) (4)
    p_span(3), // (10) (3)
    p_span(2), // (11) (2)
    p_span(1), // (12) (1)
    @flow.no_span(), // (13) Entry
  ]
  {
    kinds,
    spans,
    succ,
    pred: @flow.pred_of(succ),
    entry: 13,
    exit: 0,
    skipped: 0,
  }
}

///|
/// The instruction number of a node in the deck fixture: the line of its span.
fn bb_node_line(g : @flow.Cfg, node : Int32) -> Int32 {
  g.spans[node].start.line
}

///|
/// A block of the deck fixture, written as its instruction numbers.
fn bb_block_lines(g : @flow.Cfg, bb : @flow.Bb, b : Int32) -> String {
  let mut out = ""
  let mut k = 0
  while k < bb.blocks[b].length() {
    if k > 0 {
      out = out + ","
    }
    out = out + "\{bb_node_line(g, bb.blocks[b][k])}"
    k = k + 1
  }
  out
}

///|
/// The leaders of a graph: the first instruction of each block, in source order.
fn bb_leaders(g : @flow.Cfg, bb : @flow.Bb) -> String {
  let mut out = ""
  let mut b = 0
  while b < bb.blocks.length() {
    if b > 0 {
      out = out + ","
    }
    out = out + "\{bb_node_line(g, bb.blocks[b][0])}"
    b = b + 1
  }
  out
}

///|
/// The edges of a block graph, written as `Bi->Bj` with the block numbers one
/// based, so the text reads like the deck's drawing.
fn bb_edges(bb : @flow.Bb) -> String {
  let mut out = ""
  let mut b = 0
  while b < bb.succ.length() {
    let mut k = 0
    while k < bb.succ[b].length() {
      if out != "" {
        out = out + ", "
      }
      out = out + "B\{b + 1}->B\{bb.succ[b][k] + 1}"
      k = k + 1
    }
    b = b + 1
  }
  out
}

// ---------------------------------------------------------------------------
// A -- the deck's printed answers
// ---------------------------------------------------------------------------

///|
/// THE LEADERS, AS p.68 PRINTS THEM: (1), (3), (5), (7), (11), (12).
///
/// THE ROW IS WORTH ITS OWN PLACE BECAUSE THE LEADERS ARE WHAT EVERYTHING ELSE
/// FOLLOWS FROM. A block is "a leader and all its subsequent instructions until
/// the next leader" (p.55), so a layer that finds the wrong leaders finds the
/// wrong blocks, and the blocks are the thing the next two rows check.
test "0551: the leaders are the deck's leaders (p.68)" {
  let g = bb_deck_graph()
  let bb = @flow.bb_of(g)
  assert_eq(bb_leaders(g, bb), "1,3,5,7,11,12")
}

///|
/// THE BLOCKS, AS p.71 PRINTS THEM: B1 {(1),(2)} B2 {(3),(4)} B3 {(5),(6)}
/// B4 {(7),(8),(9),(10)} B5 {(11)} B6 {(12)}.
///
/// AND THE ORDER INSIDE A BLOCK IS THE SOURCE ORDER, which the fixture makes
/// possible to get wrong: the graph's node indices run backwards, so a block
/// listed by node index would read "2,1" where the deck reads "(1),(2)".
test "0551: the blocks are the deck's blocks (p.71)" {
  let g = bb_deck_graph()
  let bb = @flow.bb_of(g)
  assert_eq(bb.blocks.length(), 6)
  assert_eq(bb_block_lines(g, bb, 0), "1,2")
  assert_eq(bb_block_lines(g, bb, 1), "3,4")
  assert_eq(bb_block_lines(g, bb, 2), "5,6")
  assert_eq(bb_block_lines(g, bb, 3), "7,8,9,10")
  assert_eq(bb_block_lines(g, bb, 4), "11")
  assert_eq(bb_block_lines(g, bb, 5), "12")
}

///|
/// THE CFG OVER THE BLOCKS, AS p.93 DRAWS IT.
///
/// THE EDGES ARE p.80's RULE, and the drawing is the check: B2 has two
/// successors because (4) is a branch whose two sides are (5) and (7); B4 has
/// two successors because (10) is a branch whose two sides are (11) and (12);
/// and B5 goes BACK to B2, because (11) is the jump to (3).
test "0551: the CFG over the blocks is the deck's CFG (p.93)" {
  let g = bb_deck_graph()
  let bb = @flow.bb_of(g)
  assert_eq(
    bb_edges(bb),
    "B1->B2, B2->B3, B2->B4, B3->B4, B4->B5, B4->B6, B5->B2",
  )
}

///|
/// THE ENTRY AND THE EXIT, AS p.91 PRINTS THEM.
///
/// THE ENTRY IS THE BLOCK HOLDING THE FIRST INSTRUCTION, and the exit is the
/// block holding the `return` -- (12), which is B6. The lecture says of these
/// two nodes that they "do not correspond to executable IR" (p.91), so they are
/// NOT blocks and are not in the block list; they are the entry and the exits.
test "0551: the entry block holds the first instruction and the exit block holds the return (p.91)" {
  let g = bb_deck_graph()
  let bb = @flow.bb_of(g)
  assert_eq(bb.entry, 0)
  assert_eq(bb_block_lines(g, bb, bb.entry), "1,2")
  assert_eq(bb.exits.length(), 1)
  assert_eq(bb.exits[0], 5)
  assert_eq(bb_block_lines(g, bb, bb.exits[0]), "12")
}

///|
/// THE BLOCKS PARTITION THE EXECUTABLE NODES.
///
/// EVERY EXECUTABLE NODE IS IN EXACTLY ONE BLOCK. This is the row that catches
/// the defect the first draft of `bb_of` had: it recorded a block only for the
/// LEADERS, so a node in the middle of a block had no block at all, and the
/// graph still had the right number of blocks and the right leaders.
test "0551: the blocks partition the executable nodes" {
  let g = bb_deck_graph()
  let bb = @flow.bb_of(g)
  let seen : Map[Int32, Int32] = Map([])
  let mut counted = 0
  let mut b = 0
  while b < bb.blocks.length() {
    let mut k = 0
    while k < bb.blocks[b].length() {
      let n = bb.blocks[b][k]
      assert_false(seen.contains(n))
      seen.set(n, b)
      counted = counted + 1
      k = k + 1
    }
    b = b + 1
  }
  // Every node except the synthetic Entry and Exit is executable, so the two
  // of them are the whole difference between the node count and the block count.
  assert_eq(counted, g.kinds.length() - 2)
  assert_eq(seen.length(), counted)
}

// ---------------------------------------------------------------------------
// B -- the same layer on a graph this tree actually builds
// ---------------------------------------------------------------------------

///|
/// THE SAME SHAPE, BUILT BY `cfg_of`.
///
/// A loop with a merge, a branch inside the loop, a branch inside that, and a
/// `return`:
///
///      1  let x = input
///      2  let y = sub
///      3  while cond {
///      4    let z = mul
///      5    if test {
///      6      let a = q
///      7      let b = a
///      8      let c = b
///      9      if eq {
///     10        return
///     11      }
///     12    }
///     13  }
///
/// THE POSITIONS ARE THE POINT. `cfg_of` gives a branch node the position of
/// its CONDITION, so the conditions sit at the columns a reader would expect
/// (the `while` at (3,7), the `if` at (5,4), the inner `if` at (9,6)) and the
/// block layer's source order is the order a person would read.
fn bb_real_body() -> Array[@ast.Stmt] {
  [
    p_let(1, "x", p_call("input")),
    p_let(2, "y", p_call("sub")),
    p_while(3, p_name_at(3, 7, "cond"), [
      p_let(4, "z", p_call("mul")),
      p_if(5, p_name_at(5, 4, "test"), [
        p_let(6, "a", p_name("q")),
        p_let(7, "b", p_name("a")),
        p_let(8, "c", p_name("b")),
        p_if(9, p_name_at(9, 6, "eq"), [p_return(10)]),
      ]),
    ]),
  ]
}

///|
/// THE BLOCKS OF A REAL GRAPH.
///
/// FIVE BLOCKS, and each of them is a run of instructions with no branch inside
/// it. They are named the way `bb_edges` prints them -- one based, so B1 is
/// the first block:
///
///   B1 {1,2}        the two statements before the loop
///   B2 {3}          the loop's condition
///   B3 {4,5}        the loop body up to the branch
///   B4 {6,7,8,9}    the taken side of the branch, up to the inner branch
///   B5 {10}         the `return`
///
/// AND THE MERGE IS B2. The loop's body comes back to it from three places --
/// the `if`'s else side, the inner `if`'s else side, and the last statement of
/// the body -- so it has more than one predecessor, and more than one
/// predecessor is a leader.
test "0551: on a real cfg_of graph the blocks are the runs of instructions between the branches" {
  let g = @flow.cfg_of(bb_real_body())
  let bb = @flow.bb_of(g)
  assert_eq(bb.blocks.length(), 5)
  // B1: the statements before the loop. B2: the loop's condition.
  assert_eq(bb_block_lines(g, bb, 0), "1,2")
  assert_eq(bb_block_lines(g, bb, 1), "3")
  assert_eq(bb_block_lines(g, bb, 2), "4,5")
  assert_eq(bb_block_lines(g, bb, 3), "6,7,8,9")
  assert_eq(bb_block_lines(g, bb, 4), "10")
}

///|
/// THE EDGES OF A REAL GRAPH, AND THE EXIT.
///
/// B3 has two successors: the `if` inside the loop has two sides, and the else
/// side goes back to the loop's condition. B4 has two as well, and one of them
/// is the `return`.
///
/// AND THERE ARE TWO EXITS, which is the deck's point about the Exit node
/// being reachable from "any BB containing an instruction that could be the
/// last instruction of IR": B2 is the loop's condition, and the loop can end
/// with the condition false, and B5 is the `return`.
test "0551: a real graph has two exits -- the loop's condition and the return" {
  let g = @flow.cfg_of(bb_real_body())
  let bb = @flow.bb_of(g)
  assert_eq(bb_edges(bb), "B1->B2, B2->B3, B3->B2, B3->B4, B4->B2, B4->B5")
  assert_eq(bb.entry, 0)
  assert_eq(bb.exits.length(), 2)
  assert_eq(bb.exits[0], 1)
  assert_eq(bb.exits[1], 4)
}

///|
/// THE BLOCK GRAPH RUNS ON THE TREE'S OWN SOLVER AND ANSWERS THE SAME WAY THE
/// NODE GRAPH DOES.
///
/// THE ROW IS THE POINT OF THE WHOLE LAYER. The block graph has the same shape
/// as the node graph -- a count, a successor relation, a predecessor relation --
/// so `solve_round_robin` runs on it with no new solver, and the analysis
/// that runs on it is the SAME reachability analysis that runs on the node
/// graph. The two must agree: a node is reachable exactly when the block it
/// is in is reachable.
///
/// AND THIS ROW IS ALSO THE NEGATIVE CONTROL FOR THE MISSING-BLOCK DEFECT. If
/// a node in the middle of a block had no block, the node graph and the block
/// graph would disagree about reachability, and this row would go red.
test "0551: the block graph runs on the existing solver and agrees with the node graph" {
  let g = @flow.cfg_of(bb_real_body())
  let bb = @flow.bb_of(g)
  let node_states = @flow.solve_round_robin(bits(), g.kinds.length(), g.pred, fn(
    v : Int32,
    x : Int32,
  ) -> Int32 {
    if v == g.entry {
      x | 1
    } else {
      x
    }
  })
  let block_states = @flow.solve_round_robin(
    bits(),
    bb.blocks.length(),
    bb.pred,
    fn(b : Int32, x : Int32) -> Int32 { if b == bb.entry { x | 1 } else { x } },
  )
  let mut b = 0
  while b < bb.blocks.length() {
    let block_reachable = (block_states[b] & 1) == 1
    let mut k = 0
    while k < bb.blocks[b].length() {
      let n = bb.blocks[b][k]
      assert_eq((node_states[n] & 1) == 1, block_reachable)
      k = k + 1
    }
    b = b + 1
  }
}

///|
/// `pred` IS THE EXACT INVERSE OF `succ` ON THE BLOCK GRAPH.
///
/// IT IS DERIVED, NEVER MAINTAINED BY HAND: `bb_of` builds `succ` and calls the
/// same `pred_of` the node graph uses. A block graph whose `pred` disagreed
/// with its `succ` would make every analysis that reads predecessors -- the
/// solvers above among them -- read a graph that is not the one the blocks
/// describe.
test "0551: pred is the exact inverse of succ on the block graph" {
  let g = @flow.cfg_of(bb_real_body())
  let bb = @flow.bb_of(g)
  let mut b = 0
  while b < bb.succ.length() {
    let mut k = 0
    while k < bb.succ[b].length() {
      let s = bb.succ[b][k]
      assert_true(bb.pred[s].contains(b))
      k = k + 1
    }
    b = b + 1
  }
  // And the other way round: every predecessor edge is a successor edge.
  let mut p = 0
  while p < bb.pred.length() {
    let mut k = 0
    while k < bb.pred[p].length() {
      assert_true(bb.succ[bb.pred[p][k]].contains(p))
      k = k + 1
    }
    p = p + 1
  }
}

///|
/// A GRAPH THE BUILDER DID NOT CONVERT FAITHFULLY SAYS SO.
///
/// `cfg_of` turns a `break` into a `Stop` and does NOT add the edge the break
/// should add, so the loop's exit is unreachable FROM the break. A block graph
/// built on that graph inherits the gap, so the count is carried through
/// `Bb.skipped` and a caller that wants to make a claim checks it -- the way
/// `dead_stores` declines a function rather than report on a graph it knows is
/// missing an edge.
test "0551: a graph with a break carries the count of what it did not convert" {
  let g = @flow.cfg_of([
    p_while(1, p_name_at(1, 7, "cond"), [p_let(2, "a", p_name("q")), p_break(3)]),
  ])
  let bb = @flow.bb_of(g)
  assert_eq(g.skipped, 1)
  assert_eq(bb.skipped, 1)
}
