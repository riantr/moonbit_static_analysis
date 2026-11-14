// 0573: THE INTRAPROCEDURAL CONSTANT PROPAGATION -- deck 5-6 §10 -- and the
// WORK-LIST ALGORITHM -- deck 5-6 §11.
//
// THE DECK. `Data Flow Analysis -- Foundations` (Yue Li, Nanjing University) is 262
// pages, and its contents name §10 "Constant Propagation" (p.226-255) and §11
// "Worklist Algorithm" (p.256-260). The other deck in the same pair -- 7_Inter --
// uses constant propagation as its interprocedural running example, and 0546 built
// THAT one: the lattice, the evaluator, the six rules of p.105 and the edge
// transfers. What was missing is the frame the §10 deck asks for -- the analysis
// over a function's OWN control-flow graph, with the meet at a path confluence --
// and the §11 solver, which is not the one this package ships.
//
// THE MEET, p.236-238, in the deck's own notation:
//
//     NAC  ⊓ v = NAC
//     UNDEF ⊓ v = v
//     c    ⊓ c  = c
//     c1   ⊓ c2 = NAC      (c1 ≠ c2)
//
// IT IS THE STANDARD CONSTANT-PROPAGATION JOIN, and the deck's diagram draws it
// with the arrow pointing the way the MEET coarsens a value -- so `UNDEF` sits at
// the top of the drawing and `NAC` at the bottom, which is the reverse of the
// usual way a lattice is drawn. The four rules above are the whole operator, and
// they are `cpv_join` in `cprop.mbt`, unchanged since 0546. They are NOT
// re-implemented here: a second copy of the meet is how two definitions of "the
// value of a name" start to disagree, which is 0545's lesson about the set
// operations.
//
// THE TRANSFER, p.240-245:
//
//     F: OUT[s] = gen ∪ (IN[s] - {(x, _)})
//
//     s: x = c;          // c is a constant      gen = {(x, c)}
//     s: x = y;                                 gen = {(x, val(y))}
//     s: x = y op z;                            gen = {(x, f(y,z))}
//
//     f(y,z) = val(y) op val(z)   if val(y) and val(z) are constants
//             = NAC               if val(y) or val(z) is NAC
//             = UNDEF             otherwise
//
// and "if s is not an assignment statement, F is the identity function".
//
// THAT IS `cprop_eval` AND `cprop_set` IN `cprop.mbt`, already: the evaluator
// answers `val(y)` for a name, the constant for a literal, the fold for an
// operator, and `NAC` for everything the model does not cover (a call, a field, an
// index); and `cprop_set` is the kill-and-generate of the deck's formula. So this
// increment adds the FRAME -- the CFG, the meet at the confluence, the fixed point
// -- and not a second value domain.
//
// THE ONE PLACE THE TWO DECKS DISAGREE IS NAMED, because it is the whole reason
// this file exists. 7_Inter's p.105 says the node transfer at a CALL node is the
// IDENTITY -- "leave the handling of the LHS variable to edge transfer" (p.87) --
// because the interprocedural framework has an edge that carries the returned
// value. The intraprocedural framework has no such edge, so a call's result is
// simply not a constant, and `NAC` is the answer. The two rules are the same
// rules; they differ at one node kind, and the difference is the difference
// between the two decks.
//
// WHAT THIS FILE DOES NOT DO. It emits no finding, and that is 0546's precedent
// rather than an omission: the class a constant propagation speaks -- "this
// condition's outcome is known" -- is already spoken by MSA-013 InfeasibleBranch
// and MSA-014 RedundantGuard, and the measurement that says so is in the
// NARRATIVE chapter that carries this file. Adding a second family for a class
// another family already owns is how a tool ends up reporting the same line twice.

///|
/// The INTRAPROCEDURAL node transfer -- deck 5-6 §10's `F`.
///
/// THE DIFFERENCE FROM `cprop_node_transfer` IS ONE NODE KIND, and it is the
/// call: 7_Inter answers the identity there (its edge carries the value), and
/// §10 answers `NAC` (there is no edge, and a call's result is not a constant).
/// Here the call is answered by `cprop_eval`, which answers `NAC` for every
/// expression shape it does not model -- a call among them.
pub fn cprop_intra_transfer(kinds : Array[NodeKind]) -> (Int32, State) -> State {
  fn(v, st) { cprop_assign(st, kinds[v]) }
}

///|
/// `OUT[v]`: the value of every name AFTER node `v`.
///
/// A FORWARD analysis over the function's own control-flow graph, so the
/// neighbours the meet runs over are the PREDECESSORS, and the solver is the
/// deck's §11 work list.
pub fn cprop_intra_run(cfg : Cfg) -> Array[State] {
  solve_worklist(
    cprop_lattice(),
    cfg.kinds.length(),
    cfg.pred,
    cfg.succ,
    cprop_intra_transfer(cfg.kinds),
  )
}

///|
/// `IN[v]`: the value of every name BEFORE node `v`.
///
/// THIS IS WHERE THE MEET HAPPENS, and the deck is explicit about it (p.238):
/// "At each path confluence PC, we should apply 'meet' for all variables in the
/// incoming data-flow values at that PC". So this is the join of the
/// predecessors' OUT states, pointwise, with `cpv_join` as the operator.
pub fn cprop_intra_in(cfg : Cfg, outs : Array[State]) -> Array[State] {
  let lat = cprop_lattice()
  let ins : Array[State] = []
  let mut v = 0
  while v < cfg.kinds.length() {
    ins.push(join_of_nodes(lat, outs, cfg.pred[v]))
    v = v + 1
  }
  ins
}

///|
/// A branch whose condition's VALUE IS A KNOWN CONSTANT.
///
/// THIS IS THE CLASS THE ANALYSIS COULD SPEAK, and it is NOT a family: see the
/// header. The class is "the outcome of this test is decided before the program
/// runs", and MSA-013 InfeasibleBranch and MSA-014 RedundantGuard already own
/// it. What this type is for is the MEASUREMENT -- a caller can ask the analysis
/// which branches are decided and compare the answer with what the two families
/// report, and the comparison is a number rather than an opinion.
pub(all) struct ConstBranch {
  /// The node the condition is read at.
  node : Int32
  /// The constant the condition evaluates to.
  value : Int32
}

///|
/// The branches the analysis can decide: the `Test` nodes whose condition
/// evaluates to a constant in the state BEFORE the test.
pub fn cprop_const_branches(
  cfg : Cfg,
  ins : Array[State],
) -> Array[ConstBranch] {
  let out : Array[ConstBranch] = []
  let mut v = 0
  while v < cfg.kinds.length() {
    match cfg.kinds[v] {
      Test(e) =>
        match cprop_eval(ins[v], e) {
          C(n) => out.push({ node: v, value: n, })
          _ => ()
        }
      _ => ()
    }
    v = v + 1
  }
  out
}

///|
/// The lattice's ORDER: `a ≤ b` when `a` is a coarser value than `b`.
///
/// THE DIRECTION IS THE ONE THE ANALYSIS USES. `Undef` is the bottom -- "no
/// value here yet" -- and `Nac` is the top -- "this is not a constant" -- and the
/// deck's p.238 table is the join of this order, not its meet: `UNDEF ⊓ v = v`
/// says the bottom is the IDENTITY of the deck's operator, and `NAC ⊓ v = NAC`
/// says the top absorbs. So the deck's `⊓` is this lattice's JOIN, and the
/// order is the ordinary one.
///
/// IT IS PUBLIC BECAUSE THE DECK ASKS FOR MONOTONICITY (p.254: "Show our
/// constant propagation analysis is monotonic"), and a claim about monotonicity
/// cannot be tested without the order it is a claim about.
pub fn cpv_leq(a : Cpv, b : Cpv) -> Bool {
  match a {
    Undef => true
    Nac => b == Nac
    C(x) =>
      match b {
        Undef => false
        Nac => true
        C(y) => x == y
      }
  }
}

///|
/// Is one state no more precise than another, pointwise?
///
/// THE POINTWISE ORDER, and the join of two states is above both of them: this
/// is what makes "the analysis is monotone" a statement about the lattice rather
/// than about a shape.
pub fn cprop_state_leq(a : State, b : State) -> Bool {
  for k, v in a {
    let u = cprop_get(b, k)
    if cpv_leq(v, u) == false {
      return false
    }
  }
  true
}
