// 0552: THREE-ADDRESS CODE -- the deck's own input to CFG construction.
//
// THE EXPECTATIONS ARE THE DECK'S, AND THE DECK IS `Intermediate Representation`
// (Yue Li, Nanjing University, Fall 2026) -- the attachment 0551 read. THIS
// increment adds the layer the deck says the CFG is built FROM (p.39-42) and
// applies the deck's own basic-block rules to it verbatim, so that 0551's
// TRANSLATION of those rules can be checked instead of trusted.
//
// WHAT IS PINNED HERE, AND WHERE IT IS PRINTED:
//
//   p.14   "There is at most one operator on the right side of an instruction",
//          with the worked lowering `c = a + b + 3` -> `t1 = a + b; c = t1 + 3`
//   p.16   "Each 3AC contains at most 3 addresses"
//   p.17   "Address can be one of the following: Name, Constant, Temporary"
//   p.19   the six common forms
//   p.55   the leaders and the blocks
//   p.68   "Leaders: (1), (3), (5), (7), (11), (12)"
//   p.71   the six blocks
//   p.93   the CFG over those blocks
//
// AND THE LAST GROUP IS THE POINT OF THE INCREMENT: the deck's twelve
// instructions are put in three-address form and the deck's rules are run on
// them, and the SAME program is put in this tree's statement graph and 0551's
// translated rules are run on THAT -- and the two must agree. 0551 asserted
// that its translation was faithful; THIS CHECKS it.
//
// TWO THINGS ABOUT THE DECK'S OWN PROGRAM, AND BOTH ARE RECORDED RATHER THAN
// PAPERED OVER:
//
//   * `(9) c = 2a - b` puts TWO operators on the right side of one instruction,
//     which p.14's rule forbids, and `2a` is not one of p.17's three address
//     kinds. The deck's example is therefore PSEUDO-3AC -- and the deck's
//     printed blocks are the blocks of the pseudo-3AC list, not of a list that
//     obeys p.14. The fixture below keeps the deck's TEXT, so the printed
//     blocks are the printed blocks, and the row that says so is a row.
//   * p.19's list is "Some Common 3AC Forms", and the deck's own program uses
//     `return`, which is not among the six. So `Ret` is the deck's, and `Call`
//     and `Raise` are this tree's extensions and say so.

///|
/// The deck's twelve instructions, in three-address form (p.46, p.57).
///
/// THE LABELS ARE THE DECK'S OWN NUMBERS: `goto (3)` is a jump to label 3,
/// which is the instruction `(3)`. So the label ids ARE the instruction numbers
/// and the dump prints the deck's own text.
fn ir_deck_program() -> @flow.Ir {
  let insts : Array[@flow.IrInst] = [
    @flow.Copy(@flow.Name("x"), @flow.Name("input")), // (1) x = input
    @flow.BinOp(@flow.Name("y"), @ast.OpSub, @flow.Name("x"), @flow.Const("1")), // (2) y = x - 1
    @flow.BinOp(@flow.Name("z"), @ast.OpMul, @flow.Name("x"), @flow.Name("y")), // (3) z = x * y
    @flow.IfRelGoto(@flow.Name("z"), @ast.OpLt, @flow.Name("x"), 7), // (4)
    @flow.BinOp(@flow.Name("p"), @ast.OpDiv, @flow.Name("x"), @flow.Name("y")), // (5) p = x / y
    @flow.BinOp(@flow.Name("q"), @ast.OpAdd, @flow.Name("p"), @flow.Name("y")), // (6) q = p + y
    @flow.Copy(@flow.Name("a"), @flow.Name("q")), // (7) a = q
    @flow.BinOp(@flow.Name("b"), @ast.OpAdd, @flow.Name("x"), @flow.Name("a")), // (8) b = x + a
    // (9) c = 2a - b. THE DECK'S OWN TEXT, and it is not valid 3AC: `2a` is
    // neither a Name nor a Constant nor a Temporary (p.17), and the right-hand
    // side has two operators where p.14 allows one. The block algorithm never
    // reads an operand, so the shape does not matter here -- and the printed
    // blocks ARE the blocks of the deck's list.
    @flow.BinOp(@flow.Name("c"), @ast.OpSub, @flow.Name("2a"), @flow.Name("b")),
    @flow.IfRelGoto(@flow.Name("p"), @ast.OpEq, @flow.Name("q"), 12), // (10)
    @flow.Goto(3), // (11) goto (3)
    @flow.Ret, // (12) return
  ]
  let labels : Map[Int32, Int32] = Map([])
  labels.set(3, 2)
  labels.set(7, 6)
  labels.set(12, 11)
  { insts, labels, skipped: 0, }
}

///|
/// The leaders of a three-address program, written as the deck writes them:
/// the instruction's NUMBER, one based.
fn ir_leader_text(bb : @flow.Bb) -> String {
  let mut out = ""
  let mut b = 0
  while b < bb.blocks.length() {
    if b > 0 {
      out = out + ","
    }
    out = out + "\{bb.blocks[b][0] + 1}"
    b = b + 1
  }
  out
}

///|
/// The size of each block, as text: "2,2,2,4,1,1".
fn ir_size_text(bb : @flow.Bb) -> String {
  let mut out = ""
  let mut b = 0
  while b < bb.blocks.length() {
    if b > 0 {
      out = out + ","
    }
    out = out + "\{bb.blocks[b].length()}"
    b = b + 1
  }
  out
}

// ---------------------------------------------------------------------------
// A -- the lowering, and the deck's rules about the form of an instruction
// ---------------------------------------------------------------------------

///|
/// THE DECK'S OWN LOWERING EXAMPLE (p.14), and it is the sharpest row in this
/// file: `c = a + b + 3` has TWO operators on its right-hand side, and p.14
/// says "There is at most one operator on the right side of an instruction",
/// so the inner `a + b` has to be its own instruction and its result has to be
/// a temporary.
///
///     c = a + b + 3      t1 = a + b
///                    c = t1 + 3
///
/// THE EXPECTATION IS THE DECK'S TEXT, both instructions, in the deck's order.
test "0552: `c = a + b + 3` lowers to the deck's two instructions (p.14)" {
  let ir = @flow.lower_body([
    p_assign(
      1,
      p_name("c"),
      p_bin_at(
        1,
        9,
        @ast.OpAdd,
        p_bin_at(1, 5, @ast.OpAdd, p_name("a"), p_name("b")),
        p_int(3),
      ),
    ),
  ])
  assert_eq(ir.insts.length(), 2)
  assert_eq(ir.insts[0].text(), "t1 = a + b")
  assert_eq(ir.insts[1].text(), "c = t1 + 3")
}

///|
/// p.16's "Each 3AC contains at most 3 addresses", and p.15's question -- "Why
/// called 3-address?" -- is answered by it.
///
/// THE BINARY FORM HAS EXACTLY THREE, which is where the name comes from: the
/// destination, the two operands, and the OPERATOR IS NOT AN ADDRESS. The
/// label of a jump is not an address either (p.17 names three kinds and a
/// label is not one of them), so `goto L` has none.
test "0552: every instruction carries at most three addresses, and the binary form exactly three (p.16)" {
  let ir = @flow.lower_body([
    p_assign(
      1,
      p_name("c"),
      p_bin_at(
        1,
        9,
        @ast.OpAdd,
        p_bin_at(1, 5, @ast.OpAdd, p_name("a"), p_name("b")),
        p_int(3),
      ),
    ),
    p_let(2, "d", p_name("a")),
    p_if(3, p_bin_at(3, 4, @ast.OpLt, p_name("a"), p_name("b")), [
      p_let(4, "e", p_name("a")),
    ]),
  ])
  let mut i = 0
  let mut saw_binary = false
  while i < ir.insts.length() {
    let n = ir.insts[i].addresses().length()
    assert_true(n <= 3)
    match ir.insts[i] {
      @flow.BinOp(_, _, _, _) => {
        assert_eq(n, 3)
        saw_binary = true
      }
      _ => ()
    }
    i = i + 1
  }
  assert_true(saw_binary)
}

///|
/// p.17's ADDRESS TAXONOMY, checked over a whole program rather than asserted
/// in a comment: "Name: a, b, c; Constant: 3; Compiler-generated temporary:
/// t1".
///
/// AND A TEMPORARY'S NUMBER IS ITS IDENTITY, so it starts at 1 -- the deck's
/// own example numbers its temporary `t1` and not `t0`.
test "0552: every address is a Name, a Constant or a Temporary (p.17)" {
  let ir = @flow.lower_body([
    p_assign(
      1,
      p_name("c"),
      p_bin_at(
        1,
        9,
        @ast.OpAdd,
        p_bin_at(1, 5, @ast.OpAdd, p_name("a"), p_name("b")),
        p_int(3),
      ),
    ),
    p_let(2, "d", p_name("a")),
  ])
  let mut i = 0
  while i < ir.insts.length() {
    let addrs = ir.insts[i].addresses()
    let mut k = 0
    while k < addrs.length() {
      match addrs[k] {
        @flow.Name(_) => ()
        @flow.Const(c) => assert_true(c != "")
        @flow.Temp(t) => assert_true(t >= 1)
      }
      k = k + 1
    }
    i = i + 1
  }
}

///|
/// EVERY TEMPORARY IS DEFINED BEFORE IT IS USED, and this is p.31's second
/// rule -- "Give each definition a fresh name; Propagate fresh name to
/// subsequent uses" -- stated as a property that can be checked over a whole
/// program instead of a comment.
///
/// A NAME is not tracked, because a name is a variable of the surrounding
/// function or a global and this lowering does not know where it came from.
test "0552: every temporary is defined before it is used (p.31)" {
  let ir = @flow.lower_body([
    p_assign(
      1,
      p_name("c"),
      p_bin_at(
        1,
        9,
        @ast.OpAdd,
        p_bin_at(1, 5, @ast.OpAdd, p_name("a"), p_name("b")),
        p_int(3),
      ),
    ),
    p_let(2, "d", p_bin_at(2, 5, @ast.OpMul, p_name("c"), p_name("a"))),
  ])
  let defined : Map[Int32, Bool] = Map([])
  let mut i = 0
  while i < ir.insts.length() {
    // THE ADDRESSES IT READS, and not the addresses it mentions: the
    // destination is what this instruction DEFINES, and a check that reads it
    // as a use reports every definition as a use of itself.
    let read = ir.insts[i].reads()
    let mut k = 0
    while k < read.length() {
      match read[k] {
        @flow.Temp(t) => assert_true(defined.contains(t))
        _ => ()
      }
      k = k + 1
    }
    match ir.insts[i].defines() {
      Some(d) =>
        match d {
          @flow.Temp(t) => {
            // AND A TEMPORARY IS DEFINED ONCE: p.31's "Every variable has
            // exactly one definition".
            assert_false(defined.contains(t))
            defined.set(t, true)
          }
          _ => ()
        }
      None => ()
    }
    i = i + 1
  }
}

///|
/// THE SIX COMMON FORMS (p.19), and each one is produced by a construct:
///
///     x = y                a copy
///     x = uop y            a unary operation
///     x = y bop z          a binary operation
///     goto L               an unconditional jump
///     if x goto L          a conditional jump on a boolean
///     if x rop y goto L    a conditional jump on a relation
///
/// AND THE TWO EXTENSIONS SAY SO: a CALL, because the deck's IR has no call
/// form at all -- which is why the deck's own program writes `x = input` as a
/// COPY from the address `input` -- and a RAISE, because MoonBit has one.
test "0552: the six common forms are the ones the lowering produces (p.19)" {
  let ir = @flow.lower_body([
    p_assign(1, p_name("x"), p_name("y")), // x = y
    p_assign(2, p_name("x"), p_unary_at(2, 5, @ast.UNeg, p_name("y"))), // x = uop y
    p_assign(
      3,
      p_name("x"),
      p_bin_at(3, 5, @ast.OpAdd, p_name("y"), p_name("z")),
    ), // x = y bop z
    p_if(4, p_name("flag"), [p_let(5, "w", p_name("x"))]), // if x goto L
    p_if(6, p_bin_at(6, 4, @ast.OpLt, p_name("y"), p_name("z")), [
      p_let(7, "v", p_name("x")),
    ]), // if x rop y goto L
    p_while(8, p_name("cond"), [p_let(9, "u", p_name("x"))]), // goto L
    p_let(10, "r", p_call("make")), // a call -- an extension
    p_raise(11), // a raise -- an extension
  ])
  let forms : Array[String] = []
  let mut i = 0
  while i < ir.insts.length() {
    match ir.insts[i] {
      @flow.Copy(_, _) => forms.push("copy")
      @flow.UnOp(_, _, _) => forms.push("unop")
      @flow.BinOp(_, _, _, _) => forms.push("binop")
      @flow.Goto(_) => forms.push("goto")
      @flow.IfGoto(_, _) => forms.push("if")
      @flow.IfRelGoto(_, _, _, _) => forms.push("ifrel")
      @flow.Call(_, _, _) => forms.push("call")
      @flow.Raise => forms.push("raise")
      @flow.Ret => forms.push("ret")
    }
    i = i + 1
  }
  assert_true(forms.contains("copy"))
  assert_true(forms.contains("unop"))
  assert_true(forms.contains("binop"))
  assert_true(forms.contains("goto"))
  assert_true(forms.contains("if"))
  assert_true(forms.contains("ifrel"))
  assert_true(forms.contains("call"))
  assert_true(forms.contains("raise"))
}

///|
/// A STATEMENT THE LOWERING DID NOT CONVERT IS COUNTED, AND NOT DROPPED.
///
/// `cfg_of` has the same contract for the same reason: a graph that quietly
/// drops a statement is worse than no graph, because every analysis built on it
/// would be sound-looking and wrong. A caller that wants to make a claim about
/// a function checks `skipped == 0` first.
test "0552: a statement the lowering does not convert is counted, not dropped" {
  let ir = @flow.lower_body([
    p_let(1, "a", p_name("x")),
    p_let(2, "b", p_name("y")),
  ])
  assert_eq(ir.skipped, 0)
  // A field store needs an address computation the deck's IR does not have.
  let ir2 = @flow.lower_body([
    p_assign(1, p_field(p_name("o"), "f"), p_str("x")),
  ])
  assert_eq(ir2.skipped, 1)
}

// ---------------------------------------------------------------------------
// B -- the deck's own program, and the deck's own rules on it
// ---------------------------------------------------------------------------

///|
/// THE LEADERS, AS p.68 PRINTS THEM: "(1), (3), (5), (7), (11), (12)".
///
/// AND THE DECK PRINTS HOW IT GOT THEM, on p.64 and p.67, and this row is
/// those two slides:
///
///   p.64  the jump targets:        (3), (7), (12)
///   p.67  the instructions after a jump: (5), (11), (12)
///   p.68  the first instruction:    (1)
///
/// so the six leaders are the union of the three, and the union is what p.68
/// prints.
test "0552: the deck's twelve instructions give the deck's leaders (p.68)" {
  let ir = ir_deck_program()
  let bb = @flow.ir_bb(ir)
  assert_eq(ir_leader_text(bb), "1,3,5,7,11,12")
}

///|
/// THE BLOCKS, AS p.71 PRINTS THEM:
///
///     B1 {(1),(2)}   B2 {(3),(4)}   B3 {(5),(6)}
///     B4 {(7),(8),(9),(10)}   B5 {(11)}   B6 {(12)}
test "0552: the deck's twelve instructions give the deck's blocks (p.71)" {
  let ir = ir_deck_program()
  let bb = @flow.ir_bb(ir)
  assert_eq(bb.blocks.length(), 6)
  assert_eq(ir_size_text(bb), "2,2,2,4,1,1")
}

///|
/// THE CFG OVER THE BLOCKS, AS p.93 DRAWS IT.
///
/// THE SEVEN EDGES ARE p.80's RULE, and two of them are the rule's two
/// clauses doing different work:
///
///   * B5 has NO edge to B6, because B5 ends in the UNCONDITIONAL jump
///     `goto (3)` and p.80's fall-through clause needs "A does not end in an
///     unconditional jump";
///   * B4 has BOTH an edge to B5 and an edge to B6, because it ends in a
///     CONDITIONAL jump and a conditional jump still falls through.
test "0552: the deck's twelve instructions give the deck's CFG (p.93)" {
  let ir = ir_deck_program()
  let bb = @flow.ir_bb(ir)
  assert_eq(
    bb_edges(bb),
    "B1->B2, B2->B3, B2->B4, B3->B4, B4->B5, B4->B6, B5->B2",
  )
}

///|
/// THE ENTRY AND THE EXIT, AS p.91 PRINTS THEM.
///
/// THE EXIT IS THE BLOCK HOLDING THE `return`, and it is the ONLY exit: the
/// deck's program ends in a terminator, so control cannot fall off the end of
/// it anywhere else. And B5 -- the block holding `goto (3)` -- is NOT an exit,
/// because a jump goes somewhere instead of ending the program.
test "0552: the deck's program has one exit, the block holding the return (p.91)" {
  let ir = ir_deck_program()
  let bb = @flow.ir_bb(ir)
  assert_eq(bb.entry, 0)
  assert_eq(bb.exits.length(), 1)
  assert_eq(bb.exits[0], 5)
}

// ---------------------------------------------------------------------------
// C -- the differential check against 0551's translation
// ---------------------------------------------------------------------------

///|
/// THE TWO PATHS AGREE, AND THIS IS THE ROW THAT MAKES 0551's TRANSLATION A
/// CHECKED CLAIM INSTEAD OF AN ASSERTED ONE.
///
/// 0551 built the blocks from this tree's STATEMENT graph, and it had to
/// TRANSLATE the deck's rules, because the deck states them over three-address
/// code. The translation said, in the CFG's words, that a node is a leader
/// when it has more than one predecessor, or one predecessor that is a branch,
/// or none at all. The deck's own words are "the first instruction", "a jump
/// target", and "the instruction after a jump".
///
/// THOSE ARE TWO VOCABULARIES FOR ONE ALGORITHM, and this row runs both of them
/// on the DECK'S OWN PROGRAM and requires the same answer: the same blocks, the
/// same edges, the same entry and the same exits.
///
/// AND IT IS THE SAME SHAPE AS `flow_worklist_test.mbt` RUNNING THE TWO SOLVERS
/// AGAINST EACH OTHER. Two implementations of one thing, compared, is a check;
/// one implementation asserted to be right is a comment.
test "0552: the 3AC path and the statement path agree on the deck's program" {
  let ir = ir_deck_program()
  let by_ir = @flow.ir_bb(ir)
  let by_cfg = @flow.bb_of(bb_deck_graph())
  assert_eq(ir_leader_text(by_ir), bb_leaders(bb_deck_graph(), by_cfg))
  assert_eq(ir_size_text(by_ir), ir_size_text(by_cfg))
  assert_eq(bb_edges(by_ir), bb_edges(by_cfg))
  assert_eq(by_ir.entry, by_cfg.entry)
  assert_eq(by_ir.exits.length(), by_cfg.exits.length())
  assert_eq(by_ir.exits[0], by_cfg.exits[0])
}

///|
/// AND THE DECK'S PROGRAM IS PSEUDO-3AC, WHICH IS WHY THE FIXTURE KEEPS ITS
/// TEXT.
///
/// `(9) c = 2a - b` puts TWO operators on the right-hand side of one
/// instruction, and p.14 says "There is at most one operator on the right side
/// of an instruction". And `2a` is not one of p.17's three address kinds --
/// Name, Constant, Temporary -- so it is not a Name and not a Constant.
///
/// THE DECK'S PRINTED BLOCKS ARE THE BLOCKS OF THE DECK'S OWN LIST, so the
/// fixture keeps `2a` as it is. A strict 3AC would have to split it into
/// `t1 = 2 * a; c = t1 - b`, and the block would then hold FIVE instructions
/// where the deck prints four.
///
/// This row is that fact, stated where it can be checked: the fixture's
/// instruction (9) has an operand that is not one of the deck's three address
/// kinds, and the deck's own printed blocks are the blocks of the list as the
/// deck wrote it.
test "0552: the deck's own example is pseudo-3AC, and the fixture keeps its text" {
  let ir = ir_deck_program()
  // The deck's instruction (9) is index 8.
  assert_eq(ir.insts[8].text(), "c = 2a - b")
  // Its operand `2a` is carried as a Name, because the deck's address taxonomy
  // has no other kind that could hold it -- and the taxonomy is the deck's.
  let addrs = ir.insts[8].addresses()
  assert_eq(addrs.length(), 3)
  assert_eq(addrs[1].text(), "2a")
  // And the blocks are still the deck's printed ones, four instructions in B4.
  let bb = @flow.ir_bb(ir)
  assert_eq(bb.blocks[3].length(), 4)
}
