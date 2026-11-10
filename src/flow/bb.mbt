// 0551: BASIC BLOCKS -- the deck's leaders, the deck's blocks, and the deck's CFG
// on top of them.
//
// THE REFERENCE IS A NEW LECTURE: Yue Li, `Intermediate Representation`, Nanjing
// University, Fall 2026. It is the same series as the `Interprocedural Analysis`
// deck 0546 read, and it fills the layer that deck assumed: 0546's ICFG is
// built on "named function CFGs", and the CFG it used was this package's
// statement-level graph. THIS lecture says what sits UNDER a CFG.
//
// WHAT THE LECTURE PRINTS, AND WHAT IT PRINTS FOR THE FIRST TIME IN A SERIES
// THAT HAS PRINTED EVERY ANSWER SO FAR. The lecture's contents (p.3) are
//
//   1. Compilers and Static Analyzers
//   2. AST vs. IR
//   3. IR: Three-Address Code (3AC)
//   4. 3AC in Real Static Analyzer: Tai-e
//   5. Static Single Assignment (SSA)
//   6. Basic Blocks (BB)
//   7. Control Flow Graphs (CFG)
//
// and its "The X You Need To Understand" (p.95) names two of them as the
// executable questions:
//
//   * "How to build basic blocks on top of IR"
//   * "How to construct control flow graphs on top of BBs?"
//
// BOTH ARE ANSWERED IN THE LECTURE WITH A PRINTED WORKED EXAMPLE, and the
// example is the same twelve instructions from p.46 to p.71:
//
//     (1) x = input          (7) a = q            (11) goto (3)
//     (2) y = x - 1          (8) b = x + a        (12) return
//     (3) z = x * y          (9) c = 2a - b
//     (4) if z < x goto (7)  (10) if p == q goto (12)
//     (5) p = x / y          (6) q = p + y
//
// with the LEADERS printed (p.68) and the BLOCKS printed (p.71):
//
//   Leaders: (1), (3), (5), (7), (11), (12)
//   B1 {(1),(2)}   B2 {(3),(4)}   B3 {(5),(6)}
//   B4 {(7),(8),(9),(10)}   B5 {(11)}   B6 {(12)}
//
// and the CFG over those blocks drawn at p.93.
//
// THE ALGORITHM, AS PRINTED (p.55). Two steps:
//
//   (1) Determine the leaders in P
//       * The first instruction in P is a leader
//       * Any target instruction of a conditional or unconditional jump is a leader
//       * Any instruction that immediately follows a conditional or unconditional
//         jump is a leader
//   (2) Build BBs for P
//       * A BB consists of a leader and all its subsequent instructions until
//         the next leader
//
// AND THE CFG OVER THE BLOCKS (p.80):
//
//   * The nodes of CFG are basic blocks
//   * There is an edge from block A to block B if and only if
//       - There is a conditional or unconditional jump from the end of A to the
//         beginning of B
//       - B immediately follows A in the original order of instructions and A
//         does not end in an unconditional jump
//
// plus the two synthetic nodes (p.91): "Usually we add two nodes, Entry and Exit.
// They do not correspond to executable IR. An edge from Entry to the BB containing
// the first instruction of IR. An edge to Exit from any BB containing an
// instruction that could be the last instruction of IR."
//
// THE ONE TRANSLATION THIS FILE MAKES, AND WHY IT IS EXACT. The lecture states
// the rules over THREE-ADDRESS CODE -- a linear sequence of instructions with
// explicit `goto`s. This tree has no IR: its graph is the CFG, and a CFG node is
// one STATEMENT. So the rules have to be read in the CFG's terms, and the
// reading is:
//
//   L1  "the first instruction in P is a leader"
//         -> the first EXECUTABLE node in source order.
//   L2  "any target instruction of a conditional or unconditional jump is a leader"
//   L3  "any instruction that immediately follows a conditional or unconditional
//        jump is a leader"
//         -> together: a node is a leader when it has MORE THAN ONE predecessor
//            (a merge: at least one predecessor reaches it by a jump, and only
//            one predecessor can reach it by falling through), or when its ONE
//            predecessor is a BRANCH -- in which case the node is either that
//            branch's jump target (L2) or the instruction right after it (L3).
//            A node with NO predecessor is unreachable code, and the lecture's
//            L3 makes the instruction after a jump a leader whether or not it is
//            reachable, so unreachable code starts a block too.
//
// THE TRANSLATION IS NOT A GUESS, AND THE PROOF IS THE LECTURE'S OWN EXAMPLE:
// `bb_test.mbt` builds the twelve instructions as a graph and gets the printed
// leaders and the printed blocks back. If the reading were wrong, the leaders
// would not be (1),(3),(5),(7),(11),(12).
//
// WHAT THE LECTURE'S THREE JUMP KINDS BECOME HERE. The lecture's IR has a
// conditional jump (`if e goto L`), an unconditional jump (`goto L`) and a
// terminator (`return`). This tree's CFG has ONE branch kind -- `Test`, whose
// `succ[0]` is taken when the condition holds and `succ[1]` when it does not --
// and `Stop`, which has no successors at all because control LEAVES through it.
// So:
//
//   * a conditional jump is a `Test` with two successors, exactly as `cfg_of`
//     builds it for an `if`;
//   * an unconditional jump is a `Test` with ONE successor, which is what a
//     branch that does not split looks like in a graph whose only branch kind
//     splits;
//   * a terminator is a `Stop`.
//
// AND THE LECTURE'S EXIT NODE IS NOT THIS TREE'S EXIT NODE. The lecture's Exit
// is reached from "any BB containing an instruction that could be the last
// instruction of IR", and a `return` IS such an instruction. This tree's `Stop`
// has NO successor, so a function that ends in `return` leaves the graph
// through the `Stop` and never reaches the `Exit` node -- `cfg.mbt` records that
// a function whose Exit is reachable is a "fallthrough", and `icfg.mbt` declines
// it. The consequence for this file is stated in its own words where it matters:
// `exits` are the blocks from which control LEAVES THE FUNCTION, which is the
// lecture's question, and a `Stop` is a way of leaving.
//
// WHAT IS NOT HERE, AND IT IS THE LECTURE'S OWN DIVISION OF THE MATERIAL. The
// lecture has four sections this file does not touch:
//
//   * 3AC ITSELF (sections 3 and 4) -- a linear instruction form with
//     compiler-generated temporaries. This tree has no IR and no lowering, and
//     building one is an increment of its own with its own audit.
//   * SSA (section 5) -- the lecture's phi-functions, the define-and-use pairs,
//     and "flow-insensitive analysis gains partial precision of flow-sensitive
//     analysis via SSA" (p.36). SSA is defined ON a basic-block CFG, so the
//     blocks have to exist first; this increment is that first half.
//   * TAI-E (section 4) -- a real analyzer's IR and architecture, in pictures.
//
// AND THE BREAK/CONTINUE GAP IS CARRIED, NOT PAPERED OVER. `cfg.mbt` counts a
// `break` or a `continue` as `skipped` and does NOT add the edge it should add,
// so the loop's exit is unreachable FROM the break. A block CFG built on that
// graph inherits the gap, so `skipped` is carried here and a caller that wants
// to make a claim has to check it -- exactly as `dead_stores` does.

///|
/// The basic blocks of a graph, and the CFG over them.
///
/// THE SHAPE MIRRORS `Cfg` SO THAT THE SAME SOLVERS RUN ON IT. `solve_round_robin`
/// and `solve_propagation` take a node count, a neighbour relation and a
/// transfer indexed by node, and the analyses that use them index by CFG node.
/// A block graph with a different shape would need its own solver, and a second
/// solver is a second thing to be wrong.
///
/// THE ENTRY AND THE EXIT ARE NOT BLOCKS. The lecture says of them (p.91) that
/// they "do not correspond to executable IR", and a list of basic blocks that
/// contained them would not be a list of basic blocks. So `blocks` holds the
/// lecture's BBs, `entry` is the block the program starts in, and `exits` are
/// the blocks the program can end in -- which is the lecture's question ("any BB
/// containing an instruction that could be the last instruction of IR"), and
/// there can be more than one of them.
pub(all) struct Bb {
  /// The nodes of each block, in SOURCE order.
  ///
  /// THE ORDER IS THE SOURCE ORDER AND NOT THE NODE INDEX ORDER, because a CFG's
  /// node indices are ALLOCATION order (back to front -- see `cfg.mbt`), and a
  /// block whose nodes are listed backwards is not a block.
  blocks : Array[Array[Int32]]
  /// Which block a node belongs to.
  block_of : Map[Int32, Int32]
  /// The block CFG: the successors of each block.
  succ : Array[Array[Int32]]
  /// The predecessors of each block, derived from `succ` and never maintained
  /// by hand -- `pred_of` is the same derivation the CFG uses, for the same
  /// reason.
  pred : Array[Array[Int32]]
  /// The block the program starts in: the one containing the first instruction.
  /// -1 when the graph has no executable node at all.
  entry : Int32
  /// The blocks the program can end in.
  exits : Array[Int32]
  /// The graph's own `skipped`, carried so a caller can DECLINE rather than
  /// guess. See the header: a `break` or a `continue` is counted here because
  /// the edge it should add is not in the graph.
  skipped : Int32
}

///|
/// The basic blocks of a graph.
///
/// THE THREE STEPS, in the lecture's order: the leaders (p.55 step 1), the
/// blocks (p.55 step 2), and the edges between the blocks (p.80).
pub fn bb_of(g : Cfg) -> Bb {
  let order = bb_executable_order(g)
  let blocks : Array[Array[Int32]] = []
  let block_of : Map[Int32, Int32] = Map([])
  let mut cur : Array[Int32] = []
  let mut v = 0
  while v < order.length() {
    let n = order[v]
    if v == 0 || bb_is_leader(g, n) {
      if cur.length() > 0 {
        blocks.push(cur)
      }
      cur = [n]
    } else {
      cur.push(n)
    }
    // EVERY NODE GETS ITS BLOCK, and not only the leaders. The first draft set
    // `block_of` in the leader branch only, and the block edges are then built
    // by asking `block_of` about every node -- so a node in the middle of a
    // block had no block, and its edge was dropped. The graph still had the
    // right SHAPE (the right number of blocks, the right leaders) and was
    // missing edges, which is the kind of defect a block-count assertion does
    // not catch. `blocks.length()` is the index of the block being built,
    // because the previous block has already been pushed.
    block_of.set(n, blocks.length())
    v = v + 1
  }
  if cur.length() > 0 {
    blocks.push(cur)
  }
  let succ = bb_block_succ(g, blocks, block_of)
  let pred = pred_of(succ)
  {
    blocks,
    block_of,
    succ,
    pred,
    entry: bb_entry(g, block_of),
    exits: bb_exits(g, blocks),
    skipped: g.skipped,
  }
}

///|
/// The executable nodes of a graph, in SOURCE order.
///
/// THE ENTRY AND THE EXIT ARE NOT IN IT, for the reason the header gives: the
/// lecture's Entry and Exit "do not correspond to executable IR" (p.91), and a
/// block is made of instructions.
fn bb_executable_order(g : Cfg) -> Array[Int32] {
  let out : Array[Int32] = []
  for n in g.source_order() {
    match g.kinds[n] {
      Entry => ()
      Exit => ()
      _ => out.push(n)
    }
  }
  out
}

///|
/// Is this node a BRANCH -- a node control can take two ways out of?
///
/// IT IS THE KIND AND NOT THE SUCCESSOR COUNT, and the reason is the fixture
/// the deck's example needs: the lecture's `goto (3)` is an UNCONDITIONAL jump,
/// and this tree's CFG has no unconditional-jump kind, so it is encoded as a
/// `Test` with ONE successor. A count-based test would call that node a
/// non-branch, and the block it ends would be wrong.
///
/// A real `cfg_of` graph never produces a `Test` with one successor: `Test` is
/// the branch condition and always has two.
fn bb_is_branch(g : Cfg, v : Int32) -> Bool {
  match g.kinds[v] {
    Test(_) => true
    _ => false
  }
}

///|
/// Is this node a LEADER -- the start of a basic block?
///
/// THE LECTURE'S THREE RULES, in the CFG's terms. See the header for the
/// translation and why it is exact.
///
///   L1  the first instruction in P is a leader
//   L2  any target instruction of a conditional or unconditional jump is a leader
//   L3  any instruction that immediately follows a conditional or unconditional
//       jump is a leader

///|
/// L2 AND L3 TOGETHER ARE: "a node whose ONLY predecessor is a branch, or a
/// node with more than one predecessor, or a node with no predecessor at all".
/// The middle case is the merge: at least one of two predecessors reaches it by
/// a jump, because only ONE predecessor can reach a node by falling through.
/// The last case is unreachable code, which L3 makes a leader whether or not it
/// is reachable.
fn bb_is_leader(g : Cfg, v : Int32) -> Bool {
  let ps = g.pred[v]
  if ps.length() == 0 {
    // Unreachable code: the instruction after a jump, which the lecture makes a
    // leader (L3) whether or not it can be reached.
    return true
  }
  if ps.length() > 1 {
    // A merge point: at least one predecessor reaches it by a jump (L2).
    return true
  }
  // Exactly one predecessor. It is a leader iff that predecessor is a branch --
  // then this node is either its jump target (L2) or the instruction right
  // after it (L3). A non-branch predecessor only FALLS THROUGH to it, and the
  // lecture does not make such an instruction a leader.
  bb_is_branch(g, ps[0])
}

///|
/// The successors of each block.
///
/// THE LECTURE'S RULE (p.80) is "there is a conditional or unconditional jump
/// from the end of A to the beginning of B, or B immediately follows A in the
/// original order of instructions and A does not end in an unconditional jump".
/// ON A CFG BOTH OF THOSE ARE EDGES, so the rule is: an edge between two blocks
/// is an edge between their blocks. The CFG already carries the fall-through
/// (the `succ[1]` of a branch, and the single successor of a non-branch), so
/// nothing has to be re-derived from the instruction order.
///
/// THE ENTRY AND THE EXIT EDGES ARE NOT BLOCK EDGES, and they are handled by
/// `bb_entry` and `bb_exits` instead: the lecture's Entry and Exit are CFG
/// nodes, not blocks.
fn bb_block_succ(
  g : Cfg,
  blocks : Array[Array[Int32]],
  block_of : Map[Int32, Int32],
) -> Array[Array[Int32]] {
  let succ : Array[Array[Int32]] = []
  let mut i = 0
  while i < blocks.length() {
    succ.push([])
    i = i + 1
  }
  let mut v = 0
  while v < g.kinds.length() {
    match g.kinds[v] {
      Entry => ()
      Exit => ()
      _ => {
        let from = match block_of.get(v) {
          Some(b) => b
          None => {
            v = v + 1
            continue
          }
        }
        let mut k = 0
        while k < g.succ[v].length() {
          let to = g.succ[v][k]
          match g.kinds[to] {
            Exit => ()
            _ =>
              match block_of.get(to) {
                Some(b) =>
                  if b != from && succ[from].contains(b) == false {
                    succ[from].push(b)
                  }
                None => ()
              }
          }
          k = k + 1
        }
      }
    }
    v = v + 1
  }
  // THE SUCCESSORS ARE IN SOURCE ORDER, and the reason is that a block's
  // successors have no "taken" and "not taken" sides any more -- a block edge
  // is just an edge -- so the order carries no meaning, and an order that
  // carries no meaning should not be an accident of which node the loop
  // happened to visit first. Block indices ARE source order, so sorting by
  // index sorts by source position, and the deck's own drawing (p.93) lists
  // B2's edges as B3 then B4 -- the order the sort produces.
  let mut b = 0
  while b < succ.length() {
    succ[b].sort()
    b = b + 1
  }
  succ
}

///|
/// The block the program starts in: the one containing the first instruction.
///
/// IT IS FOUND THROUGH THE GRAPH'S OWN ENTRY EDGE and not by taking the first
/// block, because the first block in SOURCE order and the block control enters
/// at are the same thing only when the graph has no unreachable code before the
/// entry -- and a graph with unreachable code has both.
fn bb_entry(g : Cfg, block_of : Map[Int32, Int32]) -> Int32 {
  let mut k = 0
  while k < g.succ[g.entry].length() {
    let to = g.succ[g.entry][k]
    match block_of.get(to) {
      Some(b) => return b
      None => ()
    }
    k = k + 1
  }
  -1
}

///|
/// The blocks the program can end in.
///
/// THE LECTURE'S RULE (p.91) is "an edge to Exit from any BB containing an
/// instruction that could be the last instruction of IR". TWO KINDS OF NODE
/// ARE SUCH AN INSTRUCTION, and the lecture's wording is "CONTAINING", so every
/// node of the block is looked at rather than only its last:
///
///   * a node with an edge to this tree's `Exit` node -- that is the fall-out
///     of the end of the function;
///   * a `Stop` -- the lecture's `return`. This tree's CFG ends a `return`
///     with a `Stop` that has NO edge to `Exit`, because control LEAVES
///     through it. Counting it is what stops the block CFG from claiming that
///     a function ending in `return` never ends.
///
/// AND THE `Stop` FROM A `break` IS COUNTED TOO, WHICH IS WRONG, AND THE
/// COUNT THAT SAYS SO IS CARRIED. `cfg.mbt` turns a `break` and a `continue`
/// into a `Stop` as well, and a `break` does NOT leave the function -- it
/// leaves the loop. The graph does not say which `Stop` is which, so this
/// function cannot tell them apart, and it counts both. `skipped` IS THE
/// SIGNAL: `cfg_of` counts every `break` and `continue` it did not convert
/// faithfully, and `Bb` carries that count so a caller that wants to make a
/// claim checks it first -- the way `dead_stores` declines a whole function
/// rather than report on a graph it knows is missing an edge.
fn bb_exits(g : Cfg, blocks : Array[Array[Int32]]) -> Array[Int32] {
  let out : Array[Int32] = []
  let mut b = 0
  while b < blocks.length() {
    let mut leaves = false
    let mut i = 0
    while i < blocks[b].length() {
      let n = blocks[b][i]
      let mut k = 0
      while k < g.succ[n].length() {
        let to = g.succ[n][k]
        match g.kinds[to] {
          Exit => leaves = true
          _ => ()
        }
        k = k + 1
      }
      // A `Stop` IS A WAY TO LEAVE, and it is tested BY KIND and not by "has no
      // successors": an empty successor list is also the shape of a node the
      // builder never finished, and a `Stop` is a decision, not a gap.
      match g.kinds[n] {
        Stop => leaves = true
        _ => ()
      }
      i = i + 1
    }
    if leaves {
      out.push(b)
    }
    b = b + 1
  }
  out
}

///|
/// A readable dump of the blocks, for tests and for a human checking the graph
/// by eye.
///
/// THE DUMP IS NOT DECORATION: the alternative to reading a graph is trusting a
/// comment about a graph, and this tree has been burned by exactly that before.
pub fn Bb::dump(self : Bb) -> String {
  let mut out = "bb: \{self.blocks.length()} blocks"
  if self.skipped > 0 {
    out = out + ", skipped=\{self.skipped}"
  }
  out = out + "\n"
  let mut b = 0
  while b < self.blocks.length() {
    out = out + "  B\{b}  "
    let mut k = 0
    while k < self.blocks[b].length() {
      if k > 0 {
        out = out + ","
      }
      out = out + "\{self.blocks[b][k]}"
      k = k + 1
    }
    if self.succ[b].length() > 0 {
      out = out + "  -> "
      let mut j = 0
      while j < self.succ[b].length() {
        if j > 0 {
          out = out + ", "
        }
        out = out + "B\{self.succ[b][j]}"
        j = j + 1
      }
    }
    out = out + "\n"
    b = b + 1
  }
  out
}
