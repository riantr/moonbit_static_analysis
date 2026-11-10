// 0552: THE DECK'S CFG, BUILT FROM THREE-ADDRESS CODE -- and built from it
// VERBATIM.
//
// 0551 built the basic blocks and the CFG over them from this tree's STATEMENT
// graph, and it had to TRANSLATE the deck's rules, because the deck states
// them over three-address code. THIS FILE applies them to the deck's own
// representation, with no translation at all, so that the translation can be
// CHECKED instead of trusted.
//
// THE RULES, AS p.55 PRINTS THEM:
//
//   INPUT : A sequence of three-address instructions of P
//   OUTPUT: A list of basic blocks of P
//   METHOD : (1) Determine the leaders in P
//            * The first instruction in P is a leader
//            * Any target instruction of a conditional or unconditional jump is
//              a leader
//            * Any instruction that immediately follows a conditional or
//              unconditional jump is a leader
//           (2) Build BBs for P
//            * A BB consists of a leader and all its subsequent instructions
//              until the next leader
//
// AND p.80's edge rule, over the BLOCKS:
//
//   * There is an edge from block A to block B if and only if
//       - There is a conditional or unconditional jump from the end of A to the
//         beginning of B
//       - B immediately follows A in the original order of instructions and A
//         does not end in an unconditional jump
//
// AND p.91's two synthetic nodes:
//
//   * An edge from Entry to the BB containing the first instruction of IR
//   * An edge to Exit from any BB containing an instruction that could be the
//     last instruction of IR
//
// THIS IS THE SAME SHAPE AS 0551's `Bb`, and it is THE SAME TYPE, on purpose.
// The block graph is one thing with one definition: two structures that could
// disagree about what a block is is two definitions of "a block". So the 3AC
// path PRODUCES a `Bb` rather than a look-alike, and the two paths are compared
// against each other in `ir_test.mbt` -- which is the same shape as
// `flow_worklist_test.mbt` running the two solvers against each other.
//
// AND THE COMPARISON IS THE POINT OF THE INCREMENT. 0551's translation said, in
// the CFG's words, that a node is a leader when it has more than one
// predecessor, or one predecessor that is a branch, or none at all. The deck's
// own words are "the first instruction", "a jump target", and "the instruction
// after a jump". Those are two vocabularies for one algorithm, and the test
// runs both on the deck's own program and requires them to agree.

///|
/// The basic blocks of a three-address program, and the CFG over them.
///
/// THE RETURNED VALUE IS A `Bb`, the same type 0551's statement-level path
/// returns, and the reason is the project's own rule: an operation used twice
/// lives in one place, and "the block graph" is one operation with two inputs.
pub fn ir_bb(ir : Ir) -> Bb {
  let leaders = ir_leaders(ir)
  let blocks = ir_blocks(ir, leaders)
  let block_of = ir_block_of(blocks)
  let succ = ir_block_succ(ir, blocks, block_of)
  {
    blocks,
    block_of,
    succ,
    pred: pred_of(succ),
    entry: ir_entry(ir, block_of),
    exits: ir_exits(ir, blocks),
    skipped: ir.skipped,
  }
}

///|
/// The leaders of a three-address program, as p.55 step 1 prints them.
///
/// THE THREE RULES ARE APPLIED TO THE INSTRUCTION LIST, and each one is the
/// deck's own sentence:
///
///   L1  "The first instruction in P is a leader"
///   L2  "Any target instruction of a conditional or unconditional jump is a
///        leader"
///   L3  "Any instruction that immediately follows a conditional or unconditional
///        jump is a leader"
///
/// L2 IS THE ONE THAT NEEDS A LOOKUP, and the lookup is done ONCE, before the
/// walk: the set of instruction indices that some jump targets. Doing it per
/// instruction would be a scan per instruction, and a scan that returns a
/// different answer for the same target would be a bug that looks like a
/// property of the program.
fn ir_leaders(ir : Ir) -> Array[Int32] {
  let targets : Map[Int32, Bool] = Map([])
  let mut i = 0
  while i < ir.insts.length() {
    match ir.insts[i].jump_label() {
      Some(l) =>
        match ir.labels.get(l) {
          Some(t) => targets.set(t, true)
          None => ()
        }
      None => ()
    }
    i = i + 1
  }
  let leaders : Array[Int32] = []
  let mut k = 0
  while k < ir.insts.length() {
    let mut leader = k == 0
    if leader == false && targets.contains(k) {
      leader = true
    }
    if leader == false && k > 0 && ir.insts[k - 1].is_jump() {
      leader = true
    }
    if leader {
      leaders.push(k)
    }
    k = k + 1
  }
  leaders
}

///|
/// The blocks of a three-address program, as p.55 step 2 prints them.
///
/// "A BB consists of a leader and all its subsequent instructions until the
/// next leader" -- and "subsequent" means in the INSTRUCTION ORDER, which is
/// the order the list is in.
///
/// THE END OF A BLOCK IS A STATEMENT AND NOT AN EXPRESSION, and that is not a
/// style choice: an `if` used as a VALUE is outside the analysed subset, so
/// a read inside one is invisible to the frame audit -- and the audit then
/// reports `parameter 'ir' may not be used` for a parameter that is read on
/// the very next line. The own-source scan said so (0552), and the fix is
/// here rather than in the number: with the `if` a statement, the read of
/// `ir` sits in a region the audit does read, and the false positive is gone
/// rather than re-pinned.
fn ir_blocks(ir : Ir, leaders : Array[Int32]) -> Array[Array[Int32]] {
  let blocks : Array[Array[Int32]] = []
  let mut li = 0
  while li < leaders.length() {
    let start = leaders[li]
    let mut stop = ir.insts.length()
    if li + 1 < leaders.length() {
      stop = leaders[li + 1]
    }
    let blk : Array[Int32] = []
    let mut i = start
    while i < stop {
      blk.push(i)
      i = i + 1
    }
    blocks.push(blk)
    li = li + 1
  }
  blocks
}

///|
/// Which block each instruction belongs to.
fn ir_block_of(blocks : Array[Array[Int32]]) -> Map[Int32, Int32] {
  let block_of : Map[Int32, Int32] = Map([])
  let mut b = 0
  while b < blocks.length() {
    let mut k = 0
    while k < blocks[b].length() {
      block_of.set(blocks[b][k], b)
      k = k + 1
    }
    b = b + 1
  }
  block_of
}

///|
/// The edges between the blocks, as p.80 prints the rule.
///
/// THE TWO CLAUSES ARE THE DECK'S, in the deck's words:
///
///   * "There is a conditional or unconditional jump from the end of A to the
///      beginning of B" -- and only the END of A can jump, because a jump ends
///      its block: the instruction after a jump is a leader (p.55's L3).
///   * "B immediately follows A in the original order of instructions and A
///      does not end in an UNCONDITIONAL jump" -- so a CONDITIONAL jump still
///      falls through, and an unconditional one does not. That is the
///      difference between the deck's `(4) if z < x goto (7)` and its
///      `(11) goto (3)`, and it is why B5 has no edge to B6.
///
/// AND THE SUCCESSORS ARE IN SOURCE ORDER, for the reason 0551's `bb.mbt` gives:
/// a block edge has no "taken" and "not taken" sides any more -- it is just an
/// edge -- and an order that carries no meaning should not be an accident of
/// which instruction the walk happened to visit first.
fn ir_block_succ(
  ir : Ir,
  blocks : Array[Array[Int32]],
  block_of : Map[Int32, Int32],
) -> Array[Array[Int32]] {
  let succ : Array[Array[Int32]] = []
  let mut i = 0
  while i < blocks.length() {
    succ.push([])
    i = i + 1
  }
  let mut b = 0
  while b < blocks.length() {
    let last = blocks[b][blocks[b].length() - 1]
    // The jump out of the end of A.
    match ir.insts[last].jump_label() {
      Some(l) =>
        match ir.labels.get(l) {
          Some(t) =>
            match block_of.get(t) {
              Some(tb) =>
                if tb != b && succ[b].contains(tb) == false {
                  succ[b].push(tb)
                }
              None => ()
            }
          None => ()
        }
      None => ()
    }
    // The fall-through to the block that immediately follows.
    if b + 1 < blocks.length() && ir.insts[last].is_uncond_jump() == false {
      if succ[b].contains(b + 1) == false {
        succ[b].push(b + 1)
      }
    }
    b = b + 1
  }
  let mut s = 0
  while s < succ.length() {
    succ[s].sort()
    s = s + 1
  }
  succ
}

///|
/// The block the program starts in: the one containing the first instruction.
///
/// IT IS THE BLOCK OF INSTRUCTION ZERO and not "the first block", for the same
/// reason 0551 uses the graph's own entry edge: with unreachable code there
/// are two "first" things, and the program's first instruction is the one the
/// program starts with.
fn ir_entry(ir : Ir, block_of : Map[Int32, Int32]) -> Int32 {
  if ir.insts.length() == 0 {
    return -1
  }
  match block_of.get(0) {
    Some(b) => b
    None => -1
  }
}

///|
/// The blocks the program can end in.
///
/// p.91: "An edge to Exit from any BB containing an instruction that could be
/// the last instruction of IR". TWO KINDS OF INSTRUCTION COULD BE THE LAST:
///
///   * a TERMINATOR -- a `return` or a `raise` ends the function;
///   * the program's LAST INSTRUCTION, when control can FALL OFF THE END of it.
///     An unconditional jump as the last instruction does not fall off, so that
///     block is not an exit.
fn ir_exits(ir : Ir, blocks : Array[Array[Int32]]) -> Array[Int32] {
  let out : Array[Int32] = []
  let mut b = 0
  while b < blocks.length() {
    let mut leaves = false
    let mut k = 0
    while k < blocks[b].length() {
      if ir.insts[blocks[b][k]].is_terminator() {
        leaves = true
      }
      k = k + 1
    }
    // The last instruction of the whole program falls off the end -- unless it
    // is an unconditional jump, which goes somewhere instead.
    if ir.insts.length() > 0 {
      let last = ir.insts.length() - 1
      if blocks[b].contains(last) && ir.insts[last].is_uncond_jump() == false {
        leaves = true
      }
    }
    if leaves {
      out.push(b)
    }
    b = b + 1
  }
  out
}
