// 0553: STATIC SINGLE ASSIGNMENT -- the deck's fifth section, and the last
// section of the deck this tree had not built.
//
// THE REFERENCE IS THE SAME ATTACHMENT 0551 AND 0552 READ: Yue Li,
// `Intermediate Representation`, Nanjing University, Fall 2026.
//
// WHAT THE DECK PRINTS, AND IT PRINTS ALL OF IT:
//
//   p.31/32  "Static Single Assignment (SSA)"
//            "All assignments in SSA are to variables with distinct names"
//            - "Give each definition a fresh name"
//            - "Propagate fresh name to subsequent uses"
//            - "Every variable has exactly one definition"
//            and the page footer prints the arrow: 3AC -> SSA
//   p.33     "What if a variable use is at control flow merges?"
//            with the drawing: `if e` forks to `x0 = 0` and `x1 = 1`, the two
//            meet at one node holding `y = x + 7`, and the `x` is circled
//   p.34     the same drawing, on the right: the merge node holds
//            `x2 = ∅(x0,x1)` above `y = x2 + 7`, and the deck says
//            - "A special merge operator, ∅ (called phi-function), is introduced
//               to select the values at merge nodes"
//            - "∅(x0,x1) has the value x0 if the control flow passes through the
//               true part of the conditional and the value x1 otherwise"
//   p.36/37  "Why SSA?" and "Why not SSA?", and the second list is three claims
//            with NO NUMBER IN ANY OF THEM:
//            - "SSA may introduce too many variables and phi-functions"
//            - "May introduce inefficiency problem when translating to machine
//               code (due to copy operations)"
//            - "May help deliver some simpler analyses, e.g., flow-insensitive
//               analysis gains partial precision of flow-sensitive analysis
//               via SSA"
//
// THIS FILE IS THE LAYER THE DECK'S ARROW POINTS AT: 3AC -> SSA. 0552 built
// the 3AC and 0551 built the CFG over it, so the arrow now has both ends.
//
// THREE DECISIONS, AND EACH ONE IS THE DECK'S OR IT IS MEASURED:
//
//   1. THE SUBSCRIPT. The deck's drawing (p.34) prints `x0`, `x1` and `x2`
//      with the digit AS A SUBSCRIPT -- smaller and below the baseline -- while
//      the PDF's text layer writes the plain digits. The text layer and the
//      drawing disagree about the same glyph, so the drawing is what this
//      prints: `x₀`, `x₁`, `x₂`.
//
//   2. THE BARE NAME. The deck's drawing prints `y = x₂ + 7` and NOT
//      `y₀ = x₂ + 7`, so a variable with exactly ONE definition keeps its
//      bare name. Only a variable with more than one definition is numbered.
//      (The deck's `x` has three: `x₀`, `x₁` and the phi `x₂`.)
//
//   3. THE NUMBERING. The deck's `x₀` is the definition in the TRUE part and
//      `x₁` the one in the ELSE part, and the phi is `x₂` -- the LAST. So the
//      definitions are numbered in SOURCE ORDER and the merge operator is
//      numbered after every definition of its variable. That is also the order
//      the deck's own drawing reads in, and it is the order the phi operands
//      are in: "∅(x0,x1) has the value x0 if the control flow passes through
//      the true part of the conditional and the value x1 otherwise" -- so the
//      operand order is the PREDECESSOR ORDER, and the true part comes first
//      because the true part is lower in the source.
//
// AND ONE THING THE DECK DOES NOT HAVE: a phi operand can be UNDEFINED. When
// one path into a merge defines the variable and the other does not, the
// merged value has no name on that path. The deck's own program does this
// (p.46, p.57): its block B4 has two incoming edges, `z` is defined only in
// B2, and the path through B3 never defines `z`. So an operand can be `⊥`,
// and the count of those is part of the cost -- it is the deck's "too many
// phi-functions" made concrete.

///|
/// An address in SSA form.
///
/// IT IS A DIFFERENT TYPE FROM `Addr` ON PURPOSE. p.17 names exactly three
/// kinds of address -- Name, Constant, Temporary -- and that taxonomy is
/// about the 3AC form; the SSA form is a different IR and it has a different
/// kind of thing in it: a NAME WITH A VERSION. Making it a fourth arm of
/// `Addr` would have broken p.17's own pin in `ir_test.mbt`.
///
/// THE VERSION IS -1 FOR TWO CASES, and both print as the bare name: a
/// variable the program only READS (a parameter -- its definition is outside
/// the program), and the single definition of a variable that has only one
/// (the deck's `y`).
pub(all) enum SsaAddr {
  /// A variable, with its version.
  Var(String, Int32)
  /// A constant, carried as its printed form.
  Const(String)
  /// A compiler-generated temporary.
  ///
  /// TEMPORARIES ARE NOT RENAMED, and they do not need to be: the lowering
  /// gives every temporary its own number, so a temporary already has exactly
  /// one definition. That is p.31's rule satisfied before SSA starts.
  Temp(Int32)
}

///|
/// An instruction in SSA form.
///
/// IT MIRRORS `IrInst`, one arm for one arm, and it ADDS ONE: `Phi`, the
/// deck's merge operator. The arms are in the deck's order and the deck's
/// six are the first six.
pub(all) enum SsaInst {
  /// `x = y`
  Copy(SsaAddr, SsaAddr)
  /// `x = uop y`
  UnOp(SsaAddr, @ast.UOp, SsaAddr)
  /// `x = y bop z`
  BinOp(SsaAddr, @ast.BOp, SsaAddr, SsaAddr)
  /// `goto L`
  Goto(Int32)
  /// `if x goto L`
  IfGoto(SsaAddr, Int32)
  /// `if x rop y goto L`
  IfRelGoto(SsaAddr, @ast.BOp, SsaAddr, Int32)
  /// `return`
  Ret
  /// `raise`
  Raise
  /// `x = f(a, b)`
  Call(SsaAddr?, String, Array[SsaAddr])
  /// `x₂ = ∅(x₀, x₁)` -- the deck's merge operator (p.34).
  ///
  /// THE OPERANDS ARE IN PREDECESSOR ORDER, and the deck says what that order
  /// means: "∅(x0,x1) has the value x0 if the control flow passes through the
  /// true part of the conditional and the value x1 otherwise". An operand is
  /// `None` when no definition reaches that predecessor -- the merge has no
  /// value on that path, and the deck's IR has nothing to print for it.
  Phi(SsaAddr, Array[SsaAddr?])
}

///|
/// What the SSA form COST the program.
///
/// THE DECK'S "Why not SSA" (p.37) IS THREE CLAIMS WITH NO NUMBER IN THEM,
/// and this struct is the three numbers. It is a measurement, not an opinion:
/// every field is counted while the form is built.
///
/// THE FIELDS ARE PUBLIC because the number is the deliverable: a caller in
/// another package -- the tree driver in `src/sa` measures a whole tree of
/// them -- has to be able to ADD them up, and a private field is a field
/// nobody outside can read.
pub struct SsaCost {
  /// The number of blocks.
  blocks : Int32
  /// The number of instructions, the phis included.
  instructions : Int32
  /// The number of DISTINCT variables the program defines.
  ///
  /// THIS IS THE "before" NUMBER of the deck's first claim: the variables the
  /// 3AC program has.
  variables : Int32
  /// The number of SSA versions: one per definition, the phis included.
  ///
  /// THIS IS THE "after" NUMBER, and `versions - variables` is how many
  /// variables SSA ADDED.
  versions : Int32
  /// The number of phi-functions.
  phis : Int32
  /// The number of phi operands with no definition on that path.
  undef_operands : Int32
  /// The number of copies a phi-elimination would insert.
  ///
  /// ONE COPY PER INCOMING EDGE of every phi, which is the naive lowering:
  /// each predecessor writes the merged value into the old name. The deck's
  /// second claim is about "copy operations", and this is the count of them.
  copies : Int32
  /// The number of blocks the program cannot reach.
  unreachable_blocks : Int32
  /// The number of uses with no live definition.
  undef_uses : Int32
}

///|
/// The SSA form of a three-address program.
pub(all) struct SsaIr {
  /// The instructions, with the phis at the top of their blocks.
  insts : Array[SsaInst]
  /// The labels, remapped to the NEW instruction indices.
  ///
  /// THE PHIS PUSH THE INSTRUCTIONS ALONG, so a label that named an
  /// instruction before names a different one now. A label map that was not
  /// remapped would send every jump to the wrong instruction, and the wrong
  /// instruction is a jump that lands in the middle of a block.
  labels : Map[Int32, Int32]
  /// What the form cost.
  cost : SsaCost
}

///|
/// The SSA form of a three-address program.
///
/// IT IS BUILT OVER THE 3AC PATH, and that is the deck's own path: the deck's
/// CFG is built from 3AC (p.39-42), the deck's SSA is defined over that CFG
/// (p.33-34), and this tree's 3AC and CFG are 0552's and 0551's.
///
/// THE FORM IS NOT CLAIMED FOR CODE THE PROGRAM CANNOT REACH: a block the
/// program cannot reach has no definition reaching it, so its uses have no
/// version to resolve to. Those blocks are renamed with bare names and
/// COUNTED, in `cost.unreachable` -- a form that quietly pretended to cover
/// them would be a form that could not be checked.
pub fn ssa_of(ir : Ir) -> SsaIr {
  let bb = ir_bb(ir)
  let dom = dominators(bb)
  let df = dominance_frontiers(bb, dom)
  let s = new_ssa(ir, bb, dom, df)
  collect_defs(s)
  place_phis(s)
  prepare(s)
  assign_versions(s)
  rename(s)
  finish(s)
}

///|
/// The cost of the SSA form, without the form.
///
/// IT IS THE SAME MEASUREMENT `ssa_of` MAKES, and it is a separate entry point
/// because the deck's "Why not SSA" is a question about the COST and not
/// about the program: a caller that wants to know what SSA would cost does
/// not need the renamed program to answer it.
pub fn ssa_cost(ir : Ir) -> SsaCost {
  ssa_of(ir).cost
}

///|
/// Does the program satisfy the deck's three rules?
///
/// THE DECK'S RULES (p.31/32) ARE THREE SENTENCES, and two of them are
/// CHECKABLE on a program:
///
///   * "Every variable has exactly one definition" -- every definition of a
///     variable must carry a DIFFERENT version of it. `unique` says so.
///   * "Propagate fresh name to subsequent uses" -- every use of a variable
///     the program defines must name a version some definition produces.
///     `resolved` says so.
///
/// A use of a variable the program NEVER DEFINES is not a failure: that
/// variable is a PARAMETER, and its definition is outside the program. That
/// is the difference between "a use with no definition" and "a use with no
/// definition IN THIS PROGRAM", and a check that does not make it reports
/// every parameter of every function as a defect.
pub(all) struct SsaCheck {
  /// Every definition of a variable carries a distinct version of it.
  unique : Bool
  /// Every use of a variable the program defines names a defined version.
  resolved : Bool
  /// The number of uses that name no defined version.
  dangling : Int32
}

///|
/// Check the deck's rules against an SSA program.
pub fn ssa_check(ssa : SsaIr) -> SsaCheck {
  // THE DEFINED VERSIONS, per variable.
  let defined : Map[String, Array[Int32]] = Map([])
  let mut i = 0
  while i < ssa.insts.length() {
    match ssa_defines(ssa.insts[i]) {
      Some(SsaAddr::Var(n, v)) =>
        match defined.get(n) {
          Some(list) => list.push(v)
          None => defined.set(n, [v])
        }
      _ => ()
    }
    i = i + 1
  }
  // THE UNIQUENESS: no version twice.
  let mut unique = true
  let mut d = 0
  while d < ssa.insts.length() {
    match ssa_defines(ssa.insts[d]) {
      Some(SsaAddr::Var(n, v)) =>
        match defined.get(n) {
          Some(list) => {
            let mut count = 0
            let mut q = 0
            while q < list.length() {
              if list[q] == v {
                count = count + 1
              }
              q = q + 1
            }
            if count > 1 {
              unique = false
            }
          }
          None => ()
        }
      _ => ()
    }
    d = d + 1
  }
  // THE RESOLUTION: every use names a version some definition produces.
  let mut resolved = true
  let mut dangling = 0
  let mut u = 0
  while u < ssa.insts.length() {
    let uses = ssa_reads(ssa.insts[u])
    let mut k = 0
    while k < uses.length() {
      match uses[k] {
        SsaAddr::Var(n, v) =>
          // A variable the program never defines is a parameter.
          match defined.get(n) {
            Some(list) =>
              if list.contains(v) == false {
                resolved = false
                dangling = dangling + 1
              }
            None => ()
          }
        _ => ()
      }
      k = k + 1
    }
    u = u + 1
  }
  { unique, resolved, dangling, }
}

///|
/// The state of one SSA construction.
///
/// IT IS A STRUCT AND NOT A SET OF FUNCTIONS WITH A DOZEN ARGUMENTS, because
/// the construction has five pieces of state that all of its steps need, and
/// five arguments that always travel together is a tuple waiting for a name.
priv struct Ssa {
  ir : Ir
  bb : Bb
  dom : Dom
  df : Array[Array[Int32]]
  /// The variables the program defines, in the order they are first defined.
  vars : Array[String]
  /// The instruction indices that define each variable, ascending.
  defs : Map[String, Array[Int32]]
  /// The version of each definition, by instruction index.
  def_version : Map[Int32, Int32]
  /// The blocks that carry a phi for each variable, ascending.
  phis : Map[String, Array[Int32]]
  /// The version of each phi, by block and then by the phi's index in it.
  phi_version_of : Array[Array[Int32]]
  /// The number of versions of each variable: its definitions and its phis.
  versions : Map[String, Int32]
  /// The live versions of each variable, as a stack.
  live : Map[String, Array[Int32]]
  /// The pushes to undo when a subtree of the dominator tree is left.
  trail : Array[String]
  /// The variables with a phi at each block.
  phi_vars : Array[Array[String]]
  /// The phi operands: block, then phi, then the operand of each reachable
  /// predecessor.
  ops : Array[Array[Array[SsaAddr?]]]
  /// The reachable predecessors of each block, ascending.
  reach_preds : Array[Array[Int32]]
  /// The output index of the first element of each block.
  out_start : Array[Int32]
  /// The output instructions of each block: the phis first, then the block's.
  out : Array[Array[SsaInst]]
  mut undef_uses : Int32
}

///|
/// A fresh construction.
fn new_ssa(ir : Ir, bb : Bb, dom : Dom, df : Array[Array[Int32]]) -> Ssa {
  let n = bb.blocks.length()
  let phi_vars : Array[Array[String]] = []
  let ops : Array[Array[Array[SsaAddr?]]] = []
  let reach_preds : Array[Array[Int32]] = []
  let out : Array[Array[SsaInst]] = []
  let phi_version_of : Array[Array[Int32]] = []
  let out_start : Array[Int32] = Array::make(n, 0)
  let mut i = 0
  while i < n {
    // ONE FRESH ARRAY PER BLOCK, for the reason `pred_of` gives.
    phi_vars.push([])
    ops.push([])
    reach_preds.push([])
    out.push([])
    phi_version_of.push([])
    i = i + 1
  }
  {
    ir,
    bb,
    dom,
    df,
    vars: [],
    defs: Map([]),
    def_version: Map([]),
    phis: Map([]),
    phi_version_of,
    versions: Map([]),
    live: Map([]),
    trail: [],
    phi_vars,
    ops,
    reach_preds,
    out_start,
    out,
    undef_uses: 0,
  }
}

///|
/// Collect the definitions of every variable.
///
/// THE DEFINITIONS ARE COLLECTED IN SOURCE ORDER, and the order is what the
/// numbering is built on -- but not on its own: a phi-function is a
/// definition too, and it comes BEFORE the definitions of its own block, so
/// the numbering is settled later, by `assign_versions`.
fn collect_defs(s : Ssa) -> Unit {
  let mut b = 0
  while b < s.bb.blocks.length() {
    let mut k = 0
    while k < s.bb.blocks[b].length() {
      let i = s.bb.blocks[b][k]
      match s.ir.insts[i].defines() {
        Some(Name(n)) =>
          match s.defs.get(n) {
            Some(list) => list.push(i)
            None => {
              s.defs.set(n, [i])
              s.vars.push(n)
            }
          }
        _ => ()
      }
      k = k + 1
    }
    b = b + 1
  }
}

///|
/// Place the phi-functions.
///
/// THE CLASSIC ALGORITHM, AND IT IS THE ONE THAT MINIMISES THE PHIS: for
/// every variable, walk the DOMINANCE FRONTIERS of the blocks that define it,
/// and put a phi wherever the frontier says two definitions of that variable
/// can meet. The frontier is walked to a FIXED POINT, because a phi is itself
/// a definition, and a definition has a frontier of its own.
///
/// AND THE FRONTIER IS THE RIGHT ANSWER TO THE DECK'S QUESTION, WHICH IS
/// WHY `dom.mbt` EXISTS: the deck's merge node is a node with two incoming
/// edges, and the frontier is not that -- it is the set of nodes where the
/// DEFINITIONS of one variable meet. On the deck's own program the two
/// differ, and the difference is three phi-functions against zero.
fn place_phis(s : Ssa) -> Unit {
  let mut vi = 0
  while vi < s.vars.length() {
    let n = s.vars[vi]
    let def_blocks = blocks_of_defs(s, n)
    let work : Array[Int32] = def_blocks
    let placed : Array[Int32] = []
    while work.length() > 0 {
      let x = work[work.length() - 1]
      work.pop() |> ignore
      let mut d = 0
      while d < s.df[x].length() {
        let y = s.df[x][d]
        if placed.contains(y) == false {
          placed.push(y)
          // A phi is a definition, so its own frontier has to be walked too --
          // unless the block already defines the variable.
          if def_blocks.contains(y) == false {
            work.push(y)
          }
        }
        d = d + 1
      }
    }
    placed.sort()
    s.phis.set(n, placed)
    let def_count = match s.defs.get(n) {
      Some(list) => list.length()
      None => 0
    }
    s.versions.set(n, def_count + placed.length())
    vi = vi + 1
  }
}

///|
/// The blocks a variable is defined in, ascending.
fn blocks_of_defs(s : Ssa, n : String) -> Array[Int32] {
  let out : Array[Int32] = []
  let list = match s.defs.get(n) {
    Some(l) => l
    None => return out
  }
  let mut i = 0
  while i < list.length() {
    match s.bb.block_of.get(list[i]) {
      Some(b) => if out.contains(b) == false { out.push(b) }
      None => ()
    }
    i = i + 1
  }
  out
}

///|
/// Prepare the blocks: the reachable predecessors, the phis and their slots.
fn prepare(s : Ssa) -> Unit {
  let mut b = 0
  while b < s.bb.blocks.length() {
    let rp : Array[Int32] = []
    let mut k = 0
    while k < s.bb.pred[b].length() {
      let p = s.bb.pred[b][k]
      // A predecessor the program cannot reach carries no value into the
      // merge, so it gets no operand.
      if s.dom.rpo_num[p] >= 0 {
        rp.push(p)
      }
      k = k + 1
    }
    s.reach_preds[b] = rp
    b = b + 1
  }
  let mut vi = 0
  while vi < s.vars.length() {
    let n = s.vars[vi]
    let blocks = match s.phis.get(n) {
      Some(l) => l
      None => []
    }
    let mut i = 0
    while i < blocks.length() {
      let b = blocks[i]
      s.phi_vars[b].push(n)
      let slots : Array[SsaAddr?] = Array::make(s.reach_preds[b].length(), None)
      s.ops[b].push(slots)
      s.phi_version_of[b].push(0)
      i = i + 1
    }
    vi = vi + 1
  }
  // THE OUTPUT LAYOUT: the index each block starts at, once its phis and its
  // instructions are in. The numbering of the versions is settled in this
  // order, because a version's number is its place in the PROGRAM -- a phi
  // comes before the definitions of its own block, and a number that ignored
  // that would name a version before the version it merges.
  let mut acc = 0
  let mut ob = 0
  while ob < s.bb.blocks.length() {
    s.out_start[ob] = acc
    acc = acc + s.phi_vars[ob].length() + s.bb.blocks[ob].length()
    ob = ob + 1
  }
}

///|
/// One definition site of a variable: a definition in the program, or a
/// phi-function.
///
/// IT IS A SITE AND NOT A VERSION because the version is not known until all
/// the sites are known: a site's number is its PLACE IN THE PROGRAM among the
/// sites of its own variable.
priv struct Site {
  /// The place of the site in the output program.
  out : Int32
  /// The instruction that defines the variable, or -1 for a phi.
  inst : Int32
  /// The block that carries the phi, or -1 for a definition.
  block : Int32
}

///|
/// Give every definition of every variable its version.
///
/// THE VERSION IS THE SITE'S PLACE AMONG THE SITES OF ITS OWN VARIABLE, and
/// the places are counted in the OUTPUT PROGRAM -- not in the source. That is
/// the difference between a number and a wrong number: a phi-function is
/// printed at the TOP of its block, before the definitions of that block, so
/// in a loop the phi of a variable that the block redefines comes FIRST:
///
///     z₀ = ∅(⊥,z₁)
///     z₁ = x * y
///
/// and the back edge names `z₁`, the value of the PREVIOUS iteration. A
/// numbering by source order would have called the phi `z₁` and the
/// definition `z₀`, and the program would have used `z₁` before anything
/// defined it.
///
/// AND A VARIABLE WITH EXACTLY ONE VERSION KEEPS ITS BARE NAME, because that
/// is the deck's drawing: `y = x₂ + 7`, and not `y₀ = x₂ + 7`.
fn assign_versions(s : Ssa) -> Unit {
  let mut vi = 0
  while vi < s.vars.length() {
    let n = s.vars[vi]
    let sites : Array[Site] = []
    // THE DEFINITIONS.
    let defs = match s.defs.get(n) {
      Some(d) => d
      None => []
    }
    let mut i = 0
    while i < defs.length() {
      let idx = defs[i]
      match s.bb.block_of.get(idx) {
        Some(b) => {
          let p = position_in_block(s, idx)
          sites.push({
            out: s.out_start[b] + s.phi_vars[b].length() + p,
            inst: idx,
            block: -1,
          })
        }
        None => ()
      }
      i = i + 1
    }
    // THE PHIS.
    let phis = match s.phis.get(n) {
      Some(p) => p
      None => []
    }
    let mut k = 0
    while k < phis.length() {
      let b = phis[k]
      let pi = index_of_name(s.phi_vars[b], n)
      sites.push({ out: s.out_start[b] + pi, inst: -1, block: b, })
      k = k + 1
    }
    // THE RANKS.
    let total = sites.length()
    let mut a = 0
    while a < total {
      let mut rank = 0
      let mut c = 0
      while c < total {
        if sites[c].out < sites[a].out {
          rank = rank + 1
        }
        c = c + 1
      }
      // THE VERSION IS -1 WHEN THE VARIABLE HAS EXACTLY ONE VERSION, and the
      // `if` is a STATEMENT and not a value: an `if` used as a value is
      // outside the analysed subset, so the analyzer never sees the reads
      // inside it and reports the locals as unread. That is the 0552 lesson,
      // and the own-source scan says so (the `if expression` notice count
      // moves with it).
      let mut v = rank
      if total <= 1 {
        v = -1
      }
      if sites[a].inst >= 0 {
        s.def_version.set(sites[a].inst, v)
      } else {
        let pi = index_of_name(s.phi_vars[sites[a].block], n)
        s.phi_version_of[sites[a].block][pi] = v
      }
      a = a + 1
    }
    vi = vi + 1
  }
}

///|
/// The position of an instruction inside its block.
fn position_in_block(s : Ssa, idx : Int32) -> Int32 {
  match s.bb.block_of.get(idx) {
    Some(b) => {
      let mut k = 0
      while k < s.bb.blocks[b].length() {
        if s.bb.blocks[b][k] == idx {
          return k
        }
        k = k + 1
      }
      0
    }
    None => 0
  }
}

///|
/// Rename the program.
fn rename(s : Ssa) -> Unit {
  // THE UNREACHABLE BLOCKS FIRST, and they are renamed with bare names: no
  // definition reaches them, so there is no version to give them.
  let mut b = 0
  while b < s.bb.blocks.length() {
    if s.dom.rpo_num[b] < 0 {
      let mut k = 0
      while k < s.bb.blocks[b].length() {
        s.out[b].push(rewrite_dead(s.ir.insts[s.bb.blocks[b][k]]))
        k = k + 1
      }
    }
    b = b + 1
  }
  if s.bb.entry >= 0 {
    rename_block(s, s.bb.entry)
  }
}

///|
/// Rename one block, and then the subtree below it.
///
/// THE WALK IS A WALK OF THE DOMINATOR TREE, and that is what makes it
/// correct: a definition in a block is live in that block and in every block
/// the block dominates, so the versions pushed here are popped when the walk
/// leaves the subtree.
fn rename_block(s : Ssa, b : Int32) -> Unit {
  let mark = s.trail.length()
  // THE PHIS, at the top of the block, before anything else: they are the
  // block's own definitions, and the deck's drawing puts them above the
  // instruction that uses them.
  let mut k = 0
  while k < s.phi_vars[b].length() {
    let n = s.phi_vars[b][k]
    let v = phi_version(s, n, b)
    push_version(s, n, v)
    s.out[b].push(SsaInst::Phi(SsaAddr::Var(n, v), s.ops[b][k]))
    k = k + 1
  }
  // THE INSTRUCTIONS, in source order.
  let mut i = 0
  while i < s.bb.blocks[b].length() {
    let idx = s.bb.blocks[b][i]
    s.out[b].push(rewrite_inst(s, idx, s.ir.insts[idx]))
    i = i + 1
  }
  // THE OPERANDS OF THE SUCCESSORS' PHIS: what this block's version of the
  // variable is, on the edge to that successor.
  let mut si = 0
  while si < s.bb.succ[b].length() {
    let sb = s.bb.succ[b][si]
    let mut k = 0
    while k < s.phi_vars[sb].length() {
      let n = s.phi_vars[sb][k]
      let slot = index_of(s.reach_preds[sb], b)
      if slot >= 0 {
        s.ops[sb][k][slot] = live_version(s, n)
      }
      k = k + 1
    }
    si = si + 1
  }
  // THE CHILDREN of the dominator tree.
  let mut ci = 0
  while ci < s.dom.children[b].length() {
    rename_block(s, s.dom.children[b][ci])
    ci = ci + 1
  }
  unwind(s, mark)
}

///|
/// Rewrite one instruction into its SSA form.
fn rewrite_inst(s : Ssa, idx : Int32, inst : IrInst) -> SsaInst {
  match inst {
    Copy(d, src) => SsaInst::Copy(rewrite_def(s, idx, d), rewrite_use(s, src))
    UnOp(d, u, src) =>
      SsaInst::UnOp(rewrite_def(s, idx, d), u, rewrite_use(s, src))
    BinOp(d, op, l, r) =>
      SsaInst::BinOp(
        rewrite_def(s, idx, d),
        op,
        rewrite_use(s, l),
        rewrite_use(s, r),
      )
    Goto(l) => SsaInst::Goto(l)
    IfGoto(c, l) => SsaInst::IfGoto(rewrite_use(s, c), l)
    IfRelGoto(l, op, r, lab) =>
      SsaInst::IfRelGoto(rewrite_use(s, l), op, rewrite_use(s, r), lab)
    Ret => SsaInst::Ret
    Raise => SsaInst::Raise
    Call(d, f, args) => {
      let new_args : Array[SsaAddr] = []
      let mut i = 0
      while i < args.length() {
        new_args.push(rewrite_use(s, args[i]))
        i = i + 1
      }
      let new_dst = match d {
        Some(x) => Some(rewrite_def(s, idx, x))
        None => None
      }
      SsaInst::Call(new_dst, f, new_args)
    }
  }
}

///|
/// Rewrite an instruction of a block the program cannot reach.
///
/// ITS NAMES ARE BARE, and that is not an approximation: no definition
/// reaches the block, so no version of anything is live there. The count of
/// these blocks is in the cost.
fn rewrite_dead(inst : IrInst) -> SsaInst {
  match inst {
    Copy(d, src) => SsaInst::Copy(dead_addr(d), dead_addr(src))
    UnOp(d, u, src) => SsaInst::UnOp(dead_addr(d), u, dead_addr(src))
    BinOp(d, op, l, r) =>
      SsaInst::BinOp(dead_addr(d), op, dead_addr(l), dead_addr(r))
    Goto(l) => SsaInst::Goto(l)
    IfGoto(c, l) => SsaInst::IfGoto(dead_addr(c), l)
    IfRelGoto(l, op, r, lab) =>
      SsaInst::IfRelGoto(dead_addr(l), op, dead_addr(r), lab)
    Ret => SsaInst::Ret
    Raise => SsaInst::Raise
    Call(d, f, args) => {
      let new_args : Array[SsaAddr] = []
      let mut i = 0
      while i < args.length() {
        new_args.push(dead_addr(args[i]))
        i = i + 1
      }
      let new_dst = match d {
        Some(x) => Some(dead_addr(x))
        None => None
      }
      SsaInst::Call(new_dst, f, new_args)
    }
  }
}

///|
/// An address of a block the program cannot reach.
fn dead_addr(a : Addr) -> SsaAddr {
  match a {
    Name(n) => SsaAddr::Var(n, -1)
    Const(c) => SsaAddr::Const(c)
    Temp(t) => SsaAddr::Temp(t)
  }
}

///|
/// Rewrite a USE of an address into the version that is live there.
///
/// A USE WITH NO LIVE VERSION IS COUNTED, and it is printed as the bare name:
/// it is a use of a variable the program never defines -- a PARAMETER -- and
/// the definition of a parameter is outside the program.
fn rewrite_use(s : Ssa, a : Addr) -> SsaAddr {
  match a {
    Name(n) =>
      match live_version(s, n) {
        Some(v) => v
        None => {
          s.undef_uses = s.undef_uses + 1
          SsaAddr::Var(n, -1)
        }
      }
    Const(c) => SsaAddr::Const(c)
    Temp(t) => SsaAddr::Temp(t)
  }
}

///|
/// Rewrite a DEFINITION of an address into its fresh name.
///
/// THE FRESH NAME IS THE VERSION, and the version was settled by
/// `assign_versions`: the place of the definition among the definitions of
/// its variable, in the program.
fn rewrite_def(s : Ssa, idx : Int32, a : Addr) -> SsaAddr {
  match a {
    Name(n) => {
      let v = match s.def_version.get(idx) {
        Some(x) => x
        None => -1
      }
      push_version(s, n, v)
      SsaAddr::Var(n, v)
    }
    Const(c) => SsaAddr::Const(c)
    Temp(t) => SsaAddr::Temp(t)
  }
}

///|
/// The version of a phi-function.
fn phi_version(s : Ssa, n : String, b : Int32) -> Int32 {
  let pi = index_of_name(s.phi_vars[b], n)
  if pi < 0 {
    return -1
  }
  s.phi_version_of[b][pi]
}

///|
/// Push a version onto a variable's stack.
fn push_version(s : Ssa, n : String, v : Int32) -> Unit {
  match s.live.get(n) {
    Some(stack) => stack.push(v)
    None => s.live.set(n, [v])
  }
  s.trail.push(n)
}

///|
/// The version of a variable that is live now, if any.
fn live_version(s : Ssa, n : String) -> SsaAddr? {
  match s.live.get(n) {
    Some(stack) =>
      if stack.length() > 0 {
        Some(SsaAddr::Var(n, stack[stack.length() - 1]))
      } else {
        None
      }
    None => None
  }
}

///|
/// Undo the pushes made since a mark.
///
/// THE MARK IS THE TRAIL'S LENGTH, and the trail is what makes the undo
/// exact: it records which variable each push was for, so the pops come off
/// the right stacks.
fn unwind(s : Ssa, mark : Int32) -> Unit {
  while s.trail.length() > mark {
    let n = s.trail[s.trail.length() - 1]
    s.trail.pop() |> ignore
    match s.live.get(n) {
      Some(stack) => stack.pop() |> ignore
      None => ()
    }
  }
}

///|
/// The position of a value in a list of names, or -1.
fn index_of_name(list : Array[String], v : String) -> Int32 {
  let mut i = 0
  while i < list.length() {
    if list[i] == v {
      return i
    }
    i = i + 1
  }
  -1
}

///|
/// The position of a value in a list, or -1.
fn index_of(list : Array[Int32], v : Int32) -> Int32 {
  let mut i = 0
  while i < list.length() {
    if list[i] == v {
      return i
    }
    i = i + 1
  }
  -1
}

///|
/// Assemble the program and count what it cost.
fn finish(s : Ssa) -> SsaIr {
  let insts : Array[SsaInst] = []
  let mut b = 0
  while b < s.bb.blocks.length() {
    let mut k = 0
    while k < s.out[b].length() {
      insts.push(s.out[b][k])
      k = k + 1
    }
    b = b + 1
  }
  // THE NEW INDEX OF EVERY INSTRUCTION, and the labels are remapped through
  // it: a label names an instruction, and the phis have pushed the
  // instructions along.
  let new_index : Map[Int32, Int32] = Map([])
  let mut ib = 0
  while ib < s.bb.blocks.length() {
    let mut k = 0
    while k < s.bb.blocks[ib].length() {
      new_index.set(
        s.bb.blocks[ib][k],
        s.out_start[ib] + s.phi_vars[ib].length() + k,
      )
      k = k + 1
    }
    ib = ib + 1
  }
  let labels : Map[Int32, Int32] = Map([])
  s.ir.labels.each(fn(l, t) {
    match new_index.get(t) {
      Some(v) => labels.set(l, v)
      None => labels.set(l, t)
    }
  })
  // THE COST.
  let mut versions = 0
  let mut phis = 0
  let mut undef_operands = 0
  let mut copies = 0
  let mut dead_blocks = 0
  let mut vi = 0
  while vi < s.vars.length() {
    let n = s.vars[vi]
    let v = match s.versions.get(n) {
      Some(x) => x
      None => 0
    }
    versions = versions + v
    phis = phis + s.phi_vars_at(n).length()
    vi = vi + 1
  }
  let mut pb = 0
  while pb < s.bb.blocks.length() {
    let mut k = 0
    while k < s.phi_vars[pb].length() {
      let slots = s.ops[pb][k]
      copies = copies + slots.length()
      let mut q = 0
      while q < slots.length() {
        match slots[q] {
          Some(_) => ()
          None => undef_operands = undef_operands + 1
        }
        q = q + 1
      }
      k = k + 1
    }
    if s.dom.rpo_num[pb] < 0 {
      dead_blocks = dead_blocks + 1
    }
    pb = pb + 1
  }
  let cost = {
    blocks: s.bb.blocks.length(),
    instructions: insts.length(),
    variables: s.vars.length(),
    versions,
    phis,
    undef_operands,
    copies,
    unreachable_blocks: dead_blocks,
    undef_uses: s.undef_uses,
  }
  { insts, labels, cost, }
}

///|
/// The number of blocks that carry a phi for a variable.
fn Ssa::phi_vars_at(self : Ssa, n : String) -> Array[Int32] {
  match self.phis.get(n) {
    Some(l) => l
    None => []
  }
}

///|
/// The address this instruction DEFINES, when it defines one.
fn ssa_defines(inst : SsaInst) -> SsaAddr? {
  match inst {
    Copy(d, _) => Some(d)
    UnOp(d, _, _) => Some(d)
    BinOp(d, _, _, _) => Some(d)
    Call(Some(d), _, _) => Some(d)
    Phi(d, _) => Some(d)
    _ => None
  }
}

///|
/// The addresses this instruction READS.
fn ssa_reads(inst : SsaInst) -> Array[SsaAddr] {
  let out : Array[SsaAddr] = []
  match inst {
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
    Phi(_, ops) => {
      let mut i = 0
      while i < ops.length() {
        match ops[i] {
          Some(a) => out.push(a)
          None => ()
        }
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
/// The address, as the deck prints it.
pub fn SsaAddr::text(self : SsaAddr) -> String {
  match self {
    Var(n, v) => {
      let mut out = n
      if v >= 0 {
        out = out + subscript(v)
      }
      out
    }
    Const(c) => c
    Temp(t) => "t\{t}"
  }
}

///|
/// The instruction, as the deck prints it.
pub fn SsaInst::text(self : SsaInst) -> String {
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
    Phi(d, ops) => {
      // THE DECK'S MERGE OPERATOR, and its spelling is the deck's: `∅(x₀,x₁)`
      // -- no space after the comma.
      let mut s = "\{d.text()} = ∅("
      let mut i = 0
      while i < ops.length() {
        if i > 0 {
          s = s + ","
        }
        match ops[i] {
          Some(a) => s = s + a.text()
          None => s = s + "⊥"
        }
        i = i + 1
      }
      s + ")"
    }
  }
}

///|
/// The whole program, one instruction per line, as the deck prints it.
pub fn SsaIr::dump(self : SsaIr) -> String {
  let mut out = ""
  let mut i = 0
  while i < self.insts.length() {
    out = out + "\{i}: \{self.insts[i].text()}\n"
    i = i + 1
  }
  out
}

///|
/// A number, in the deck's SUBSCRIPT form.
///
/// THE DECK'S DRAWING PRINTS THE DIGIT BELOW THE BASELINE, and its text layer
/// does not -- the two disagree about the same glyph, so the drawing is what
/// this prints. THE DIGITS ARE THE UNICODE SUBSCRIPT ONES, so a version of
/// ten is `₁₀` and not `10`: the number is always written in full, so it
/// cannot be read as two versions.
fn subscript(n : Int32) -> String {
  let digits = [
    "₀", "₁", "₂", "₃", "₄", "₅", "₆", "₇", "₈", "₉",
  ]
  if n < 0 {
    return ""
  }
  if n == 0 {
    return digits[0]
  }
  let parts : Array[String] = []
  let mut v = n
  while v > 0 {
    parts.push(digits[v % 10])
    v = v / 10
  }
  let mut out = ""
  let mut i = parts.length() - 1
  while i >= 0 {
    out = out + parts[i]
    i = i - 1
  }
  out
}
