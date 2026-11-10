// 0552: THREE-ADDRESS CODE -- the deck's own INPUT to CFG construction.
//
// THE REFERENCE IS THE SAME ATTACHMENT 0551 READ: Yue Li, `Intermediate
// Representation`, Nanjing University, Fall 2026. 0551 built the basic blocks
// and the CFG over them, and it had to TRANSLATE the deck's rules, because the
// deck states them over three-address code and this tree has no IR. THIS FILE
// IS THE MISSING HALF.
//
// THE DECK'S OWN PIPELINE, AT p.39-42:
//
//     "Control Flow Analysis
//      Input: 3AC of P
//      Output: CFG of P"
//     and p.41 adds: "The node in CFG can be an individual 3-address
//     instruction, or (usually) a Basic Block (BB)."
//
// So the deck's CFG is built FROM a 3AC list, and the deck's basic-block rules
// (p.55) are stated over that list. With this file, the deck's rules apply to
// the deck's own representation and need no translation at all -- and 0551's
// translation can be CHECKED against them instead of being trusted.
//
// WHAT THE DECK PRINTS, AND IT PRINTS ALL OF IT.
//
//   p.14  "There is at most one operator on the right side of an instruction."
//         with the worked lowering:
//             c = a + b + 3      t1 = a + b
//                             c = t1 + 3
//   p.15  "Why called 3-address?"
//   p.16  "Each 3AC contains at most 3 addresses"
//   p.17  "Address can be one of the following:
//            * Name: a, b, c
//            * Constant: 3
//            * Compiler-generated temporary: t1"
//   p.19  "Some Common 3AC Forms":
//            x = y
//            x = uop y
//            x = y bop z
//            goto L
//            if x goto L
//            if x rop y goto L"
//
// AND THE DECK'S OWN PROGRAM (p.46, p.57) IS A 3AC LIST, so it can be put in
// this representation and the deck's rules can be run on it unchanged.
//
// THREE KINDS OF ADDRESS AND NO MORE, because p.17 names exactly three. A
// constant is carried as its PRINTED FORM, because the deck's IR is UNTYPED
// (p.13 calls the IR "compact and uniform"), and a typed constant would be a
// fourth kind of thing the deck does not have.
//
// AND THE FORMS BEYOND THE DECK'S SIX ARE NAMED AS EXTENSIONS, because they are
// extensions. The deck's list has no CALL and no RAISE, and the deck's own
// program needs neither (`x = input` is written there as a COPY from the
// address `input`, because the deck's IR has no call form at all). MoonBit has
// both, so this tree has both, and each one says in its own comment that the
// deck does not have it.

///|
/// An address: the deck's three kinds, and no more (p.17).
///
/// Name is "a, b, c"; Constant is "3"; Temp is a compiler-generated temporary
/// "t1". The temporary's NUMBER is its identity, and the numbering starts at 1
/// because the deck's own example numbers its temporary `t1` and not `t0`.
pub(all) enum Addr {
  Name(String)
  Const(String)
  Temp(Int32)
}

///|
/// An instruction in three-address form.
///
/// THE DECK'S SIX FORMS (p.19) ARE THE FIRST SIX ARMS, IN THE DECK'S ORDER, and
/// each one carries the deck's own spelling in its comment:
///
///     x = y                Copy
///     x = uop y            UnOp
///     x = y bop z          BinOp
///     goto L               Goto
///     if x goto L          IfGoto
///     if x rop y goto L    IfRelGoto
///
/// AND `Ret` IS NOT AN EXTENSION: the deck's own program has `(12) return`, so
/// the terminator is one of the deck's instructions even though p.19's list does
/// not name it. `Call` and `Raise` ARE extensions, and they say so.
pub(all) enum IrInst {
  /// `x = y` -- the deck's first form.
  Copy(Addr, Addr)
  /// `x = uop y` -- the deck's second form. `uop` is a unary operation: minus,
  /// negation, casting (p.19).
  UnOp(Addr, @ast.UOp, Addr)
  /// `x = y bop z` -- the deck's third form. `bop` is a binary arithmetic or
  /// logical operation (p.19).
  BinOp(Addr, @ast.BOp, Addr, Addr)
  /// `goto L` -- the deck's fourth form: an unconditional jump.
  Goto(Int32)
  /// `if x goto L` -- the deck's fifth form: a conditional jump on an ADDRESS.
  IfGoto(Addr, Int32)
  /// `if x rop y goto L` -- the deck's sixth form. `rop` is a relational
  /// operator: ">, <, ==, >=, <=, etc." (p.19).
  IfRelGoto(Addr, @ast.BOp, Addr, Int32)
  /// `return` -- the deck's own instruction (12). NOT one of p.19's six, but
  /// the deck's program uses it, so it is the deck's.
  Ret
  /// `raise` -- AN EXTENSION. The deck's IR has no raise form, because the
  /// deck's IR is arithmetic; MoonBit has one, and it ends the function the way
  /// a `return` does.
  Raise
  /// `x = f(a, b)` -- AN EXTENSION. The deck's six forms have no CALL at all,
  /// which is why the deck's own program writes `x = input` as a COPY from the
  /// address `input`. The destination is `None` for a call whose value nobody
  /// reads.
  Call(Addr?, String, Array[Addr])
}

///|
/// A three-address program: a list of instructions, a label table, and a count
/// of what this lowering did not convert.
///
/// THE LABELS ARE RESOLVED TO INSTRUCTION INDICES, so a jump target is an
/// index and not a name. The lecture's rules (p.55) are about POSITIONS in a
/// sequence of instructions, and a label that has to be looked up is a label
/// that can be looked up wrongly.
pub(all) struct Ir {
  /// The instructions, in order.
  insts : Array[IrInst]
  /// Label id -> the index of the instruction the label names.
  labels : Map[Int32, Int32]
  /// Statements this lowering did not convert.
  ///
  /// IT IS THE SAME CONTRACT `cfg_of` HAS, and for the same reason: a graph
  /// that quietly drops a statement is worse than no graph, because every
  /// analysis built on it would be sound-looking and wrong. A caller that wants
  /// to make a claim checks `skipped == 0` first.
  skipped : Int32
}

///|
/// The mutable half of the lowering: the counters and the stacks.
///
/// THE BREAK AND CONTINUE STACKS ARE HERE BECAUSE A LOOP'S EXIT AND ITS HEAD
/// ARE LABELS, and a `break` inside two nested loops has to jump to the INNER
/// one's exit. The deck's IR has no `break` -- it has `goto L` -- so this is
/// where the two representations meet.
priv struct Lower {
  mut temps : Int32
  mut labels : Int32
  labels_at : Map[Int32, Int32]
  breaks : Array[Int32]
  continues : Array[Int32]
  mut skipped : Int32
}

///|
/// Lower a statement list into three-address code.
///
/// THE ENTRY POINT IS THE FUNCTION BODY, because a 3AC program is a FUNCTION's
/// instructions -- the deck's p.39 says "Input: 3AC of P", and P is a program,
/// and this tree's unit of program is one function body.
pub fn lower_body(body : Array[@ast.Stmt]) -> Ir {
  let ctx = {
    temps: 0,
    labels: 0,
    labels_at: Map([]),
    breaks: [],
    continues: [],
    skipped: 0,
  }
  let out : Array[IrInst] = []
  lower_stmts(ctx, out, body)
  { insts: out, labels: ctx.labels_at, skipped: ctx.skipped, }
}

///|
/// Lower a list of statements into `out`.
fn lower_stmts(
  ctx : Lower,
  out : Array[IrInst],
  stmts : Array[@ast.Stmt],
) -> Unit {
  let mut i = 0
  while i < stmts.length() {
    lower_stmt(ctx, out, stmts[i])
    i = i + 1
  }
}

///|
/// Lower one statement.
fn lower_stmt(ctx : Lower, out : Array[IrInst], s : @ast.Stmt) -> Unit {
  match s.kind {
    @ast.SLet(x, _, e) => lower_into(ctx, out, Name(x), e)
    @ast.SAssign(lhs, rhs) =>
      // A store to a NAME is a copy-or-compute into that name; a store THROUGH
      // a place (`x.f = e`, `xs[i] = e`) needs an address computation the
      // deck's IR does not have, so it is DECLINED rather than approximated.
      match lhs.kind {
        @ast.EName(x) => lower_into(ctx, out, Name(x), rhs)
        _ => ctx.skipped = ctx.skipped + 1
      }
    @ast.SExpr(e) => {
      // The value goes nowhere, so it goes into a temporary nobody reads. The
      // deck's IR has no "expression statement" form, and a call whose result
      // is discarded still has to be CALLED.
      let t = ctx.temps + 1
      ctx.temps = t
      lower_into(ctx, out, Temp(t), e)
    }
    @ast.SIf(cond, then_body, elifs, else_body) =>
      lower_if(ctx, out, cond, then_body, elifs, 0, else_body)
    @ast.SWhile(cond, body) => lower_while(ctx, out, cond, body)
    @ast.SReturn(e) => {
      match e {
        Some(x) => {
          // The VALUE is kept, in a temporary: MoonBit's `return` carries one
          // and dropping it would lose a use of every name in it.
          let t = ctx.temps + 1
          ctx.temps = t
          lower_into(ctx, out, Temp(t), x)
        }
        None => ()
      }
      out.push(Ret)
    }
    @ast.SRaise(e) => {
      match e {
        Some(x) => {
          let t = ctx.temps + 1
          ctx.temps = t
          lower_into(ctx, out, Temp(t), x)
        }
        None => ()
      }
      out.push(Raise)
    }
    @ast.SBreak(_) =>
      if ctx.breaks.length() > 0 {
        out.push(Goto(ctx.breaks[ctx.breaks.length() - 1]))
      } else {
        // A `break` with no loop around it is not a jump this lowering can
        // make, so it is declined rather than turned into a jump to nowhere.
        ctx.skipped = ctx.skipped + 1
      }
    @ast.SContinue(_) =>
      if ctx.continues.length() > 0 {
        out.push(Goto(ctx.continues[ctx.continues.length() - 1]))
      } else {
        ctx.skipped = ctx.skipped + 1
      }
    @ast.SBlock(inner) => lower_stmts(ctx, out, inner)
    // THE ONES THIS LOWERING DOES NOT CONVERT, and they are COUNTED rather
    // than dropped: a nested function is a separate body, a destructuring let
    // binds several names at once, a `for` has an update clause, and a `tail`
    // is a body whose value is the function's.
    @ast.SFunc(_, _, _, _, _) | @ast.SLocalFunc(_, _, _, _, _) =>
      ctx.skipped = ctx.skipped + 1
    @ast.SLetDestruct(_, _) | @ast.STail(_) | @ast.SNoBreak(_, _) =>
      ctx.skipped = ctx.skipped + 1
    @ast.SFor(_, _, _, _) | @ast.SForUpdate(_) => ctx.skipped = ctx.skipped + 1
  }
}

///|
/// Lower an `if` -- with its `else if` chain and its `else`.
///
/// THE SHAPE IS THE DECK'S SHAPE, and the deck's program is what shows it: a
/// conditional jump whose TAKEN side is the label, and the not-taken side
/// FALLS THROUGH to the next instruction. So the lowering emits
///
///     if <cond> goto L_then
///     goto L_next
///     L_then: <the then body>
///     goto L_end
///     L_next: <the else body, or the next else-if>
///     L_end:
///
/// and `L_next` is the label the deck's program uses when the not-taken path
/// has to jump anyway -- which is exactly what the deck's `(10) if p == q goto
/// (12)` followed by `(11) goto (3)` is.
fn lower_if(
  ctx : Lower,
  out : Array[IrInst],
  cond : @ast.Expr,
  then_body : Array[@ast.Stmt],
  elifs : Array[@ast.ElseIf],
  elif_at : Int32,
  else_body : Array[@ast.Stmt]?,
) -> Unit {
  let l_then = ctx.labels + 1
  ctx.labels = l_then
  let l_next = ctx.labels + 1
  ctx.labels = l_next
  let l_end = ctx.labels + 1
  ctx.labels = l_end
  lower_branch(ctx, out, cond, l_then)
  out.push(Goto(l_next))
  ctx.labels_at.set(l_then, out.length())
  lower_stmts(ctx, out, then_body)
  out.push(Goto(l_end))
  ctx.labels_at.set(l_next, out.length())
  if elif_at < elifs.length() {
    lower_if(
      ctx,
      out,
      elifs[elif_at].cond,
      elifs[elif_at].body,
      elifs,
      elif_at + 1,
      else_body,
    )
  } else {
    match else_body {
      Some(b) => lower_stmts(ctx, out, b)
      None => ()
    }
  }
  ctx.labels_at.set(l_end, out.length())
}

///|
/// Lower a `while`.
///
/// THE LOOP'S HEAD IS A LABEL AND ITS BACK EDGE IS THE DECK'S UNCONDITIONAL
/// JUMP, so the lowering is
///
///     L_cond: if <cond> goto L_body
///             goto L_end
///     L_body: <the body>
///             goto L_cond
///     L_end:
///
/// and that `goto L_cond` is the deck's own `(11) goto (3)`: an unconditional
/// jump back to the top of a loop. The deck's program has no loop header TEST
/// because its IR is flat, and this is the same shape.
fn lower_while(
  ctx : Lower,
  out : Array[IrInst],
  cond : @ast.Expr,
  body : Array[@ast.Stmt],
) -> Unit {
  let l_cond = ctx.labels + 1
  ctx.labels = l_cond
  let l_body = ctx.labels + 1
  ctx.labels = l_body
  let l_end = ctx.labels + 1
  ctx.labels = l_end
  ctx.labels_at.set(l_cond, out.length())
  lower_branch(ctx, out, cond, l_body)
  out.push(Goto(l_end))
  ctx.labels_at.set(l_body, out.length())
  ctx.breaks.push(l_end)
  ctx.continues.push(l_cond)
  lower_stmts(ctx, out, body)
  ctx.breaks.pop() |> ignore
  ctx.continues.pop() |> ignore
  out.push(Goto(l_cond))
  ctx.labels_at.set(l_end, out.length())
}

///|
/// Emit the conditional jump for a condition, in whichever of the deck's two
/// conditional forms fits.
///
/// A RELATIONAL condition is the deck's `if x rop y goto L` -- and the two
/// operands are addresses, so a nested operand goes into a temporary first.
/// Anything else is a BOOLEAN in an address, which is the deck's `if x goto L`.
fn lower_branch(
  ctx : Lower,
  out : Array[IrInst],
  cond : @ast.Expr,
  target : Int32,
) -> Unit {
  match cond.kind {
    @ast.EBin(op, l, r) => {
      let a = lower_operand(ctx, out, l)
      let b = lower_operand(ctx, out, r)
      out.push(IfRelGoto(a, op, b, target))
    }
    _ =>
      // A condition that is ALREADY an address -- a name, a constant -- is the
      // deck's `if x goto L` with no instruction in front of it. Anything else
      // has to be computed, so it goes into a temporary and the temporary is
      // what the jump tests.
      match simple_addr(cond) {
        Some(a) => out.push(IfGoto(a, target))
        None => {
          let t = ctx.temps + 1
          ctx.temps = t
          lower_into(ctx, out, Temp(t), cond)
          out.push(IfGoto(Temp(t), target))
        }
      }
  }
}

///|
/// The address of an expression, as an OPERAND of a relational jump.
///
/// A name or a constant IS an address and costs no instruction. Anything else
/// has to be computed, so it goes into a temporary and the temporary is the
/// address.
fn lower_operand(ctx : Lower, out : Array[IrInst], e : @ast.Expr) -> Addr {
  match simple_addr(e) {
    Some(a) => a
    None => {
      let t = ctx.temps + 1
      ctx.temps = t
      lower_into(ctx, out, Temp(t), e)
      Temp(t)
    }
  }
}

///|
/// The address of an expression that is ALREADY an address: a name or a
/// constant. `None` when the expression has to be COMPUTED.
fn simple_addr(e : @ast.Expr) -> Addr? {
  match e.kind {
    @ast.EName(n) => Some(Name(n))
    @ast.EInt(i) => Some(Const(i.to_string()))
    @ast.EBool(b) => Some(Const(bool_const(b)))
    _ => None
  }
}

///|
/// Lower an expression so that its value ends up in `dst`.
///
/// THIS IS WHERE p.14's RULE IS ENFORCED, and the enforcement is structural
/// rather than checked afterwards: an instruction's right-hand side holds at
/// most ONE operator, so an operator nested inside another operator cannot be
/// the same instruction's right-hand side -- it has to be its own instruction,
/// and its own instruction's result is a temporary.
///
/// THAT IS THE DECK'S OWN EXAMPLE (p.14):
///
///     c = a + b + 3        t1 = a + b
///                      c = t1 + 3
///
/// and `c = a + b + 3` is `EBin(Add, EBin(Add, a, b), 3)`, so the inner `a + b`
/// goes into a temporary and the outer instruction is `c = t1 + 3`.
fn lower_into(
  ctx : Lower,
  out : Array[IrInst],
  dst : Addr,
  e : @ast.Expr,
) -> Unit {
  match e.kind {
    @ast.EName(n) => out.push(Copy(dst, Name(n)))
    @ast.EInt(i) => out.push(Copy(dst, Const(i.to_string())))
    @ast.EBool(b) => out.push(Copy(dst, Const(bool_const(b))))
    @ast.EUnary(u, inner) => {
      let a = lower_operand(ctx, out, inner)
      out.push(UnOp(dst, u, a))
    }
    @ast.EBin(op, l, r) => {
      let a = lower_operand(ctx, out, l)
      let b = lower_operand(ctx, out, r)
      out.push(BinOp(dst, op, a, b))
    }
    @ast.ECall(f, args, _) => {
      let arg_addrs : Array[Addr] = []
      let mut i = 0
      while i < args.length() {
        arg_addrs.push(lower_operand(ctx, out, args[i]))
        i = i + 1
      }
      out.push(Call(Some(dst), f, arg_addrs))
    }
    // THE ONES THIS LOWERING DOES NOT CONVERT. A field or an index is an
    // ADDRESS COMPUTATION, and the deck's IR has no address arithmetic at all
    // (p.13 calls the IR "compact and uniform"); a tuple, a list, a struct, a
    // match and a catch are all forms the deck's six do not have.
    _ => ctx.skipped = ctx.skipped + 1
  }
}

///|
/// Is this instruction a JUMP -- a conditional or an unconditional one?
///
/// THE DECK'S PHRASE IS "a conditional or unconditional jump" (p.55), and it
/// appears in two of the deck's rules: L2 (a jump's target is a leader) and L3
/// (the instruction after a jump is a leader). So "is a jump" is one question
/// with one answer, and it is asked in both places.
pub fn IrInst::is_jump(self : IrInst) -> Bool {
  match self {
    Goto(_) => true
    IfGoto(_, _) => true
    IfRelGoto(_, _, _, _) => true
    _ => false
  }
}

///|
/// The label this instruction jumps to, when it is a jump.
pub fn IrInst::jump_label(self : IrInst) -> Int32? {
  match self {
    Goto(l) => Some(l)
    IfGoto(_, l) => Some(l)
    IfRelGoto(_, _, _, l) => Some(l)
    _ => None
  }
}

///|
/// Is this an UNCONDITIONAL jump?
///
/// p.80's fall-through clause says "A does not end in an unconditional jump",
/// and that word is doing real work: a conditional jump still falls through to
/// the next block, and an unconditional one does not. The deck's own program
/// has both -- `(4) if z < x goto (7)` and `(11) goto (3)` -- and B5 has no
/// edge to B6 for exactly this reason.
pub fn IrInst::is_uncond_jump(self : IrInst) -> Bool {
  match self {
    Goto(_) => true
    _ => false
  }
}

///|
/// Does this instruction END the function?
///
/// A `return` and a `raise` both end it: the first returns, the second
/// propagates out. p.91's "an instruction that could be the last instruction of
/// IR" is this, plus the program's last instruction when control can fall off
/// the end of it.
pub fn IrInst::is_terminator(self : IrInst) -> Bool {
  match self {
    Ret => true
    Raise => true
    _ => false
  }
}

///|
/// Every address this instruction MENTIONS -- the destination and the
/// operands -- and a LABEL IS NOT ONE.
///
/// p.17 names exactly three kinds of address -- Name, Constant, Temporary --
/// and a label is none of them: p.19 lists `L: a label to represent a program
/// location` separately from the addresses. So `goto L` has NO address in it,
/// `if x goto L` has one, and `if x rop y goto L` has two.
///
/// AND p.16's "Each 3AC contains at most 3 addresses" IS A COUNT OF THIS, and
/// it is where the name "3-address" comes from: the binary form mentions
/// exactly three -- the destination and the two operands -- and the OPERATOR
/// IS NOT AN ADDRESS.
pub fn IrInst::addresses(self : IrInst) -> Array[Addr] {
  let out : Array[Addr] = []
  match self {
    Copy(d, s) => {
      out.push(d)
      out.push(s)
    }
    UnOp(d, _, s) => {
      out.push(d)
      out.push(s)
    }
    BinOp(d, _, l, r) => {
      out.push(d)
      out.push(l)
      out.push(r)
    }
    IfGoto(c, _) => out.push(c)
    IfRelGoto(l, _, r, _) => {
      out.push(l)
      out.push(r)
    }
    Call(d, _, args) => {
      match d {
        Some(x) => out.push(x)
        None => ()
      }
      let mut i = 0
      while i < args.length() {
        out.push(args[i])
        i = i + 1
      }
    }
    Goto(_) => ()
    Ret => ()
    Raise => ()
  }
  out
}

///|
/// The addresses this instruction READS -- its operands, without its
/// destination.
///
/// THE DESTINATION IS NOT A READ, and a check that forgets that is a check
/// that reports every definition as a use of itself. This is the difference
/// between "defined before it is used" and "defined before it is used BY
/// SOMETHING ELSE".
pub fn IrInst::reads(self : IrInst) -> Array[Addr] {
  let out : Array[Addr] = []
  match self {
    Copy(_, s) => out.push(s)
    UnOp(_, _, s) => out.push(s)
    BinOp(_, _, l, r) => {
      out.push(l)
      out.push(r)
    }
    IfGoto(c, _) => out.push(c)
    IfRelGoto(l, _, r, _) => {
      out.push(l)
      out.push(r)
    }
    Call(_, _, args) => {
      let mut i = 0
      while i < args.length() {
        out.push(args[i])
        i = i + 1
      }
    }
    Goto(_) => ()
    Ret => ()
    Raise => ()
  }
  out
}

///|
/// The address this instruction DEFINES, when it defines one.
pub fn IrInst::defines(self : IrInst) -> Addr? {
  match self {
    Copy(d, _) => Some(d)
    UnOp(d, _, _) => Some(d)
    BinOp(d, _, _, _) => Some(d)
    Call(Some(d), _, _) => Some(d)
    _ => None
  }
}

///|
/// A boolean constant, as its printed form.
///
/// IT IS ONE FUNCTION BECAUSE IT IS TWO USES, and the project's rule is that an
/// operation used twice lives in ONE place. The first draft of this file wrote
/// `if b { "true" } else { "false" }` at both places, and the own-source notice
/// count said so: the `if expression` notice is a scope limit about an `if`
/// used as a VALUE, so a second copy of the expression is a second notice.
fn bool_const(b : Bool) -> String {
  if b {
    "true"
  } else {
    "false"
  }
}

///|
/// The address, as the deck prints it.
pub fn Addr::text(self : Addr) -> String {
  match self {
    Name(n) => n
    Const(c) => c
    Temp(t) => "t\{t}"
  }
}

///|
/// The instruction, as the deck prints it.
pub fn IrInst::text(self : IrInst) -> String {
  match self {
    Copy(d, s) => "\{d.text()} = \{s.text()}"
    UnOp(d, u, s) => "\{d.text()} = \{uop_text(u)} \{s.text()}"
    BinOp(d, op, l, r) => "\{d.text()} = \{l.text()} \{op.symbol()} \{r.text()}"
    Goto(l) => "goto L\{l}"
    IfGoto(c, l) => "if \{c.text()} goto L\{l}"
    IfRelGoto(l, op, r, lab) =>
      "if \{l.text()} \{op.symbol()} \{r.text()} goto L\{lab}"
    Ret => "return"
    Raise => "raise"
    Call(d, f, args) => {
      let mut s = ""
      match d {
        Some(x) => s = x.text() + " = "
        None => ()
      }
      s = s + f + "("
      let mut i = 0
      while i < args.length() {
        if i > 0 {
          s = s + ", "
        }
        s = s + args[i].text()
        i = i + 1
      }
      s + ")"
    }
  }
}

///|
/// The deck's `uop`: a unary operation, minus or negation (p.19).
fn uop_text(u : @ast.UOp) -> String {
  match u {
    @ast.UNeg => "-"
    @ast.UNot => "!"
  }
}

///|
/// The whole program, one instruction per line, as the deck prints it.
///
/// IT IS FOR READING, and the reading is the point: a graph that is wrong is
/// much easier to see as text than as an array of indices.
pub fn Ir::dump(self : Ir) -> String {
  let mut out = ""
  let mut i = 0
  while i < self.insts.length() {
    out = out + "\{i}: \{self.insts[i].text()}\n"
    i = i + 1
  }
  out
}
