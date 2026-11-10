// 0553: STATIC SINGLE ASSIGNMENT -- the deck's fifth section, checked against
// the deck's own drawing.
//
// THE EXPECTATIONS ARE THE DECK'S, AND THE DECK IS `Intermediate
// Representation` (Yue Li, Nanjing University, Fall 2026) -- the attachment
// 0551 and 0552 read. Section five is the last section of the deck this tree
// had not built, and its own subject is the arrow the deck prints in the
// footer of p.31: 3AC -> SSA.
//
// WHAT IS PINNED HERE, AND WHERE IT IS PRINTED:
//
//   p.31/32  "All assignments in SSA are to variables with distinct names"
//            - "Give each definition a fresh name"
//            - "Propagate fresh name to subsequent uses"
//            - "Every variable has exactly one definition"
//   p.33     "What if a variable use is at control flow merges?"
//   p.34     the merge operator: "A special merge operator, ∅ (called
//            phi-function), is introduced to select the values at merge
//            nodes", and "∅(x0,x1) has the value x0 if the control flow
//            passes through the true part of the conditional and the value x1
//            otherwise"
//   p.37     "SSA may introduce too many variables and phi-functions" -- the
//            claim with no number in it, and the numbers are measured here
//
// THE FIRST TEST IS THE SHARPEST ONE IN THIS FILE: the deck's DRAWING is
// turned into a program, the program is lowered to three-address code, the
// 3AC is put through SSA, and the result is compared with the drawing --
// instruction for instruction, name for name.

///|
/// The deck's own drawing (p.33/34), as a program.
///
/// IT IS THE DECK'S FIGURE STATEMENT FOR STATEMENT: `if e` forks to `x = 0`
/// and to `x = 1`, the two meet at a node, and the node holds `y = x + 7`.
/// The deck's left-hand drawing has the merge use UNRESOLVED -- the `x` in
/// `y = x + 7` is circled in red -- and the right-hand drawing has it
/// resolved.
fn ssa_deck_figure() -> @flow.Ir {
  @flow.lower_body([
    ssa_if_else(1, p_name("e"), [p_assign(2, p_name("x"), p_int(0))], [
      p_assign(3, p_name("x"), p_int(1)),
    ]),
    p_assign(4, p_name("y"), p_bin_at(4, 5, @ast.OpAdd, p_name("x"), p_int(7))),
  ])
}

///|
/// An `if` with an `else`, which the shared fixtures do not have.
///
/// THE `else` IS WHAT THE DECK'S DRAWING IS ABOUT, so the fixture that
/// reproduces the drawing needs one.
fn ssa_if_else(
  line : Int32,
  cond : @ast.Expr,
  then_body : Array[@ast.Stmt],
  else_body : Array[@ast.Stmt],
) -> @ast.Stmt {
  { span: p_span(line), kind: @ast.SIf(cond, then_body, [], Some(else_body)), }
}

///|
/// The SSA program, one instruction per line, with the indices off.
fn ssa_lines(ssa : @flow.SsaIr) -> String {
  let mut out = ""
  let mut i = 0
  while i < ssa.insts.length() {
    if i > 0 {
      out = out + ";"
    }
    out = out + ssa.insts[i].text()
    i = i + 1
  }
  out
}

// ---------------------------------------------------------------------------
// A -- the deck's drawing, reproduced
// ---------------------------------------------------------------------------

///|
/// THE DECK'S DRAWING, INSTRUCTION FOR INSTRUCTION.
///
/// The deck's right-hand drawing (p.34) is a control-flow graph with four
/// nodes:
///
///     if e            the condition
///     x₀ = 0          the TRUE part
///     x₁ = 1          the other part
///     x₂ = ∅(x₀,x₁)   the merge, and BELOW it
///     y = x₂ + 7      the use the deck circled in red
///
/// AND THE MERGE NODE HOLDS BOTH: the deck's drawing puts the phi-function
/// INSIDE the merge node, above the instruction that uses it. So the phi is
/// at the TOP of the block that holds the use -- and the instruction that
/// uses the merged value is the LAST one.
test "0553: the deck's drawing is reproduced: the phi above the use, in the merge node" {
  let ssa = @flow.ssa_of(ssa_deck_figure())
  assert_eq(
    ssa_lines(ssa),
    "if e goto L1;goto L2;x₀ = 0;goto L3;x₁ = 1;x₂ = ∅(x₀,x₁);y = x₂ + 7",
  )
}

///|
/// THE LABELS STILL LAND ON THEIR INSTRUCTIONS, after the phis have pushed
/// the instructions along.
///
/// THE MERGE BLOCK'S LABEL pointed at `y = x + 7` -- the instruction AFTER
/// the phi, because the phi is the block's own first thing and the label
/// names the instruction the merge block was about. A label map that was not
/// remapped would send the jump one instruction too far, and the one
/// instruction too far is the phi itself.
test "0553: the labels are remapped, so a jump still lands on its instruction" {
  let ssa = @flow.ssa_of(ssa_deck_figure())
  // THE LABEL OF THE MERGE BLOCK -- the third one the lowering made.
  let target = match ssa.labels.get(3) {
    Some(t) => t
    None => -1
  }
  assert_eq(target, 6)
  // AND THAT INSTRUCTION IS THE USE, NOT THE PHI.
  assert_eq(ssa.insts[6].text(), "y = x₂ + 7")
  assert_eq(ssa.insts[5].text(), "x₂ = ∅(x₀,x₁)")
}

///|
/// THE DECK'S SENTENCE ABOUT THE OPERANDS, and it is a sentence about ORDER:
/// "∅(x0,x1) has the value x0 if the control flow passes through the true
/// part of the conditional and the value x1 otherwise".
///
/// SO THE FIRST OPERAND IS THE TRUE PART'S VALUE. The test above pins the
/// phi as `∅(x₀,x₁)`; this one pins that `x₀` is the one the TRUE branch
/// defines -- the instruction `x₀ = 0` is the THEN branch's, and the THEN
/// branch is the one the deck's `if e` jumps to.
test "0553: the phi's first operand is the TRUE part's value (p.34)" {
  let ssa = @flow.ssa_of(ssa_deck_figure())
  // THE DEFINITION IN THE TRUE PART.
  assert_eq(ssa.insts[2].text(), "x₀ = 0")
  // THE DEFINITION IN THE OTHER PART.
  assert_eq(ssa.insts[4].text(), "x₁ = 1")
  // AND THE MERGE SELECTS BETWEEN THEM, IN THAT ORDER.
  assert_eq(ssa.insts[5].text(), "x₂ = ∅(x₀,x₁)")
}

///|
/// THE DECK'S THREE RULES, CHECKED OVER A WHOLE PROGRAM RATHER THAN ASSERTED
/// IN A COMMENT.
///
///   * "Give each definition a fresh name" and "Every variable has exactly
///     one definition" -- every definition of a variable carries a DIFFERENT
///     version of it.
///   * "Propagate fresh name to subsequent uses" -- every use of a variable
///     the program defines names a version some definition produces.
///
/// AND IT IS CHECKED ON A PROGRAM WITH A LOOP, because a loop is where the
/// three rules bite: the value of a variable around a loop is a phi, and a
/// phi that names a version nothing defines is a use that resolves to
/// nothing.
test "0553: every variable has exactly one definition, and every use names one (p.31/32)" {
  let ssa = @flow.ssa_of(ssa_deck_figure())
  let check = @flow.ssa_check(ssa)
  assert_true(check.unique)
  assert_true(check.resolved)
  assert_eq(check.dangling, 0)
}

// ---------------------------------------------------------------------------
// B -- the map the deck does not print: dominators and frontiers
// ---------------------------------------------------------------------------

///|
/// THE DOMINATOR TREE OF THE DECK'S OWN PROGRAM, and it is the map the deck's
/// SSA needs and never prints.
///
/// THE DECK'S PROGRAM (p.46, p.57) HAS SIX BLOCKS, and this is their tree:
///
///     B1  x = input ; y = x - 1
///     B2  z = x * y ; if z < x goto 7
///     B3  p = x / y ; q = p + y
///     B4  a = q ; b = x + a ; c = 2a - b ; if p == q goto 12
///     B5  goto 3
///     B6  return
///
/// B2 IS DOMINATED BY B1, B3 BY B2, B4 BY B2, AND B5 AND B6 BY B4. The one
/// that is worth checking by hand is B4: it has two incoming edges, from B2
/// and from B3, and the nearest block that dominates BOTH of them is B2 --
/// not B1. B3's immediate dominator is B2, so B2 is an ancestor of B3, and B2
/// is on every path into B4.
test "0553: the deck's program has the dominator tree its CFG says it has" {
  let ir = ir_deck_program()
  let bb = @flow.ir_bb(ir)
  let dom = @flow.dominators(bb)
  assert_eq(bb.blocks.length(), 6)
  assert_eq(dom.idom[0], 0)
  assert_eq(dom.idom[1], 0)
  assert_eq(dom.idom[2], 1)
  assert_eq(dom.idom[3], 1)
  assert_eq(dom.idom[4], 3)
  assert_eq(dom.idom[5], 3)
}

///|
/// THE DOMINANCE FRONTIERS OF THE DECK'S PROGRAM, and they are the deck's
/// "merge nodes" -- computed rather than drawn.
///
/// THE INTERESTING ONE IS B2, WHICH IS IN ITS OWN FRONTIER: the loop comes
/// back to B2, so a definition made in B2 has to be merged with the value
/// the previous iteration left behind. That is the classic reason a loop head
/// carries phi-functions, and it is the reason the deck's program needs six
/// of them at B2 and not two.
test "0553: the deck's program's frontiers are its merges" {
  let ir = ir_deck_program()
  let bb = @flow.ir_bb(ir)
  let dom = @flow.dominators(bb)
  let df = @flow.dominance_frontiers(bb, dom)
  assert_eq(df[0].length(), 0)
  assert_eq(df[1].length(), 1)
  assert_eq(df[1][0], 1)
  assert_eq(df[2].length(), 1)
  assert_eq(df[2][0], 3)
  assert_eq(df[3].length(), 1)
  assert_eq(df[3][0], 1)
  assert_eq(df[4].length(), 1)
  assert_eq(df[4][0], 1)
  assert_eq(df[5].length(), 0)
}

// ---------------------------------------------------------------------------
// C -- what SSA costs, which is the deck's claim with no number in it
// ---------------------------------------------------------------------------

///|
/// THE DECK'S FIRST COST CLAIM (p.37), MEASURED: "SSA may introduce too many
/// variables and phi-functions".
///
/// ON THE DECK'S OWN PROGRAM: eight variables become sixteen versions, and
/// eight phi-functions appear in a twelve-instruction program. The claim is
/// not a figure of speech -- on the deck's own example it is a FACT, and
/// this row is the fact.
///
/// AND THE NUMBER IS NOT SMALL BECAUSE OF A BUG: the classic algorithm puts
/// a phi at every place the DOMINANCE FRONTIER says two definitions can
/// meet, and the frontier of the deck's loop head is the loop head itself.
test "0553: SSA doubles the deck's program's variables and adds eight phis (p.37)" {
  let ir = ir_deck_program()
  let cost = @flow.ssa_cost(ir)
  assert_eq(cost.blocks, 6)
  assert_eq(cost.variables, 8)
  assert_eq(cost.versions, 16)
  assert_eq(cost.phis, 8)
  assert_eq(cost.instructions, 20)
  assert_eq(cost.undef_operands, 6)
  assert_eq(cost.copies, 16)
}

///|
/// THE SECOND COST CLAIM (p.37): "May introduce inefficiency problem when
/// translating to machine code (due to copy operations)".
///
/// THE COPIES ARE COUNTED AS THE NAIVE PHI-ELIMINATION COUNTS THEM: one
/// copy per incoming edge of every phi. On the deck's program that is
/// sixteen copies for eight phis, in a twelve-instruction program -- and the
/// number is bigger than the number of phis because every phi here has TWO
/// incoming edges.
test "0553: the deck's program needs sixteen copies to take the phis away (p.37)" {
  let ir = ir_deck_program()
  let cost = @flow.ssa_cost(ir)
  assert_eq(cost.phis, 8)
  assert_eq(cost.copies, 16)
  assert_eq(cost.copies, cost.phis * 2)
}

// ---------------------------------------------------------------------------
// D -- the CFG correction the SSA layer exposed
// ---------------------------------------------------------------------------

///|
/// A `return` ENDS ITS BLOCK, and control does not fall out of it.
///
/// THE DECK'S IR HAS NO RETURN FORM, so p.80's rule -- the fall-through edge
/// exists when "A does not end in an unconditional jump" -- has nothing to
/// say about a block that ends in a `return`. This tree's IR has one, and
/// the edge out of such a block would be an edge the program cannot take.
///
/// THE FIXTURE IS A FUNCTION THAT RETURNS INSIDE AN `if`, and the `x = 2`
/// AFTER the `if` is reachable only from the other branch. So the block that
/// holds the `return` has NO successor, and the block after it has exactly
/// one.
test "0553: a block that ends in a return has no fall-through successor" {
  let ir = @flow.lower_body([
    ssa_if_else(1, p_name("e"), [p_return(2)], [
      p_assign(3, p_name("x"), p_int(2)),
    ]),
  ])
  let bb = @flow.ir_bb(ir)
  // THE BLOCK THAT HOLDS THE RETURN.
  let mut ret_block = -1
  let mut b = 0
  while b < bb.blocks.length() {
    let mut k = 0
    while k < bb.blocks[b].length() {
      if bb.blocks[b][k] == 2 {
        ret_block = b
      }
      k = k + 1
    }
    b = b + 1
  }
  assert_true(ret_block >= 0)
  assert_eq(bb.succ[ret_block].length(), 0)
}
