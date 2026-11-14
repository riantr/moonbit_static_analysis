// The fixed-point solvers.
//
// TWO SOLVERS, AND THE SECOND ONE IS THE TEST OF THE FIRST. Moller &
// Schwartzbach give four algorithms that all compute the same least fixed point
// (naive, round-robin, chaotic iteration, work-list) and they say so as a
// theorem. A theorem is not a test, so both solvers that this package ships are
// run against each other in `flow_worklist_test.mbt` on the same graph: if they
// ever disagree, one of them is wrong and the suite says so.
//
// THE ONE THING THAT DIFFERS, AND IT IS EASY TO GET WRONG. The two solvers
// index the same array with different meanings, which the book states on page 77
// and which matters the moment a caller tries to compare their outputs:
//
//   solve_round_robin    state[v] is the abstract state AFTER node v
//                        (the `[[v]]` of chapters 4-6, where the JOIN of a
//                        node reads its PREDECESSORS' after-states)
//   solve_propagation    state[v] is the abstract state BEFORE node v, and the
//                        transfer function's output is pushed to v's SUCCESSORS
//
// So `after(v)` under the propagation solver is `transfer(v, before[v])`, not
// `before[v]`. `states_after` below is that conversion, written once rather
// than re-derived by each caller.

///|
/// The round-robin solver (book §5.3).
///
/// `state[v]` is the abstract state AFTER `v`; a node's input is the JOIN of its
/// predecessors' after-states, and an entry node with no predecessors therefore
/// receives `bot` -- which is what an entry node must receive.
///
/// TERMINATION IS THE LATTICE'S JOB. Each sweep can only move a node UP the
/// lattice, so this returns for any lattice of finite height. An analysis with
/// an infinite-height lattice (intervals, §6.1) must widen, or this loop runs
/// forever -- which is exactly what the book says and why widening is a
/// separate increment rather than a detail of this one.
pub fn[T] solve_round_robin(
  lat : Lattice[T],
  n : Int32,
  preds : Array[Array[Int32]],
  transfer : (Int32, T) -> T,
) -> Array[T] {
  // One fresh element per node -- see the `bot`-as-thunk note on Lattice.
  let after : Array[T] = []
  let mut i = 0
  while i < n {
    after.push((lat.bot)())
    i = i + 1
  }
  let mut changed = true
  while changed {
    changed = false
    let mut v = 0
    while v < n {
      let y = transfer(v, join_of_nodes(lat, after, preds[v]))
      if (lat.eq)(after[v], y) == false {
        after[v] = y
        changed = true
      }
      v = v + 1
    }
  }
  after
}

///|
/// The propagation work-list solver (book §5.10).
///
/// `state[v]` is the abstract state BEFORE `v`. A node's transfer output is
/// pushed to its successors and joined there, which is why the book prefers
/// this variant for interprocedural analysis: a function entry node can have
/// many predecessors, and pushing avoids recomputing a large JOIN.
///
/// THE WORK LIST IS A SET, NOT A QUEUE. `pending[v]` says "v is in the list",
/// and a node is only re-added when the value it would read actually changed.
/// Implemented as repeated sweeps over the set so that no array-removal
/// primitive is needed; the sweep order is irrelevant to the result, which is
/// the point of chaotic iteration (§5.3).
pub fn[T] solve_propagation(
  lat : Lattice[T],
  n : Int32,
  succ : Array[Array[Int32]],
  transfer : (Int32, T) -> T,
) -> Array[T] {
  // One fresh element per node -- see the `bot`-as-thunk note on Lattice.
  let before : Array[T] = []
  let mut j = 0
  while j < n {
    before.push((lat.bot)())
    j = j + 1
  }
  let pending : Array[Bool] = Array::make(n, false)
  let mut v = 0
  while v < n {
    pending[v] = true
    v = v + 1
  }
  let mut any = true
  while any {
    any = false
    let mut i = 0
    while i < n {
      if pending[i] {
        pending[i] = false
        let y = transfer(i, before[i])
        let mut k = 0
        while k < succ[i].length() {
          let s = succ[i][k]
          let z = (lat.join)(before[s], y)
          if (lat.eq)(before[s], z) == false {
            before[s] = z
            if pending[s] == false {
              pending[s] = true
              any = true
            }
          }
          k = k + 1
        }
      }
      i = i + 1
    }
  }
  before
}

///|
/// The propagation solver's output, converted to the `[[v]]` convention the
/// round-robin solver returns: the abstract state AFTER each node.
///
/// This exists so that "the two solvers agree" is one comparison in a test
/// instead of a comment about an indexing convention, which is the kind of
/// comment that is right until someone edits one of the two loops.
pub fn[T] states_after(
  n : Int32,
  before : Array[T],
  transfer : (Int32, T) -> T,
) -> Array[T] {
  let after : Array[T] = []
  let mut i = 0
  while i < n {
    after.push(transfer(i, before[i]))
    i = i + 1
  }
  after
}

///|
/// The propagation solver WITH EDGE TRANSFERS -- the third solver, and the first
/// one this package has that can express a framework the second cannot.
///
/// WHY IT HAD TO EXIST (0546). The first two solvers take ONE function of
/// `(node, state)`. That is the intraprocedural framework exactly, and it is one
/// term short of the interprocedural one: Tian Tan's deck draws the difference
/// as a table row -- "Transfer functions: node transfer" for the intraprocedural
/// framework, "node transfer + EDGE transfer" for the interprocedural one
/// (`Interprocedural Analysis`, Nanjing University, 2021, p.85) -- and no amount
/// of cleverness inside a `(node, state) -> state` function can express a rule
/// that depends on WHICH EDGE the state is travelling along. The specific rule
/// that cannot be expressed is the one the deck's own worked example turns on
/// (p.103): the value of a call's left-hand side must be KILLED on the
/// call-to-return edge and supplied by the return edge, and those are two
/// different edges out of the SAME node carrying the SAME input state.
///
/// THE LABEL IS THE API. `labels[i][k]` describes the edge `succ[i][k]`, and it
/// is an unconstrained type parameter rather than a fixed edge type so that this
/// solver stays a statement about lattices and not about control-flow graphs:
/// this package's ICFG passes an `EdgeKind` that carries the data the transfer
/// needs (the actual arguments of a call, the returned expression, the name to
/// kill), and a test can pass an `Int` and prove the loop in isolation.
///
/// THE CONVENTION IS `solve_propagation`'s, DELIBERATELY: `state[v]` is the
/// abstract state BEFORE `v`, and the node's output is pushed along each edge
/// after that edge's own transfer. Keeping one index convention across the two
/// propagation solvers is what makes "the edge version reduces to the plain one
/// when every edge transfer is the identity" a comparison a test can state in a
/// line instead of a comment -- and `icfg_test.mbt` states it.
pub fn[T, L] solve_edges(
  lat : Lattice[T],
  n : Int32,
  succ : Array[Array[Int32]],
  labels : Array[Array[L]],
  node_transfer : (Int32, T) -> T,
  edge_transfer : (L, Int32, Int32, T) -> T,
) -> Array[T] {
  // One fresh element per node -- see the `bot`-as-thunk note on Lattice.
  let before : Array[T] = []
  let mut j = 0
  while j < n {
    before.push((lat.bot)())
    j = j + 1
  }
  let pending : Array[Bool] = Array::make(n, false)
  let mut v = 0
  while v < n {
    pending[v] = true
    v = v + 1
  }
  let mut any = true
  while any {
    any = false
    let mut i = 0
    while i < n {
      if pending[i] {
        pending[i] = false
        let y = node_transfer(i, before[i])
        let mut k = 0
        while k < succ[i].length() {
          let s = succ[i][k]
          let z = (lat.join)(before[s], edge_transfer(labels[i][k], i, s, y))
          if (lat.eq)(before[s], z) == false {
            before[s] = z
            if pending[s] == false {
              pending[s] = true
              any = true
            }
          }
          k = k + 1
        }
      }
      i = i + 1
    }
  }
  before
}

///|
/// The FORWARD WORK-LIST solver -- deck 5-6 §11, p.258.
///
/// THE DECK'S OWN WORDS: "Worklist Algorithm, an optimization of Iterative
/// Algorithm" (p.256). The algorithm it optimizes is the one on p.257:
///
///     OUT[entry] = ∅
///     for each basic block B: OUT[B] = ∅
///     while changes to any OUT occur:
///         for each basic block B:
///             IN[B]  = ⊔ over the predecessors P of B of OUT[P]
///             OUT[B] = gen_B ∪ (IN[B] - kill_B)
///
/// and the optimization is the work list of p.258: a block is put back on the
/// list only when its OUT changed, and the slide names why in one line -- "OUT
/// will not change if IN does not change" (p.259).
///
/// WHY THIS IS A THIRD SHAPE AND NOT A NEW SPELLING OF THE FIRST. This package
/// already ships `solve_round_robin`, whose state is the abstract state AFTER a
/// node and whose input is the join of the predecessors' after-states -- the same
/// equation system as this one, evaluated in a different ORDER. It also ships
/// `solve_edges`, which is that one plus the edge transfers 7_Inter's p.105
/// needs, and `solve_propagation`, which IS a work list but keeps the state
/// BEFORE a node and PUSHES the transfer's output along the edges. The deck's
/// §11 is the forward work list with the after-state, and it is the third SHAPE
/// of solver this package has: the state is `OUT[B]`, the input is read back
/// from the predecessors, and a block is revisited only when its OUT moved.
///
/// IT COMPUTES THE SAME LEAST FIXED POINT, and `flow_worklist_test.mbt`'s
/// doctrine applies to it as to the others: one solver is the test of the
/// next. `cprop_intra_test.mbt` pins this one against `solve_round_robin` on the
/// deck's own graph.
///
/// THE WORK LIST IS A SET, NOT A QUEUE, for the reason `solve_propagation` gives:
/// `pending[v]` says "v is on the list", and the order the list is drained in
/// does not change the answer, which is the point of chaotic iteration.
pub fn[T] solve_worklist(
  lat : Lattice[T],
  n : Int32,
  preds : Array[Array[Int32]],
  succs : Array[Array[Int32]],
  transfer : (Int32, T) -> T,
) -> Array[T] {
  // OUT[B] = ⊥ for every block, and the work list starts with all of them.
  let out : Array[T] = []
  let mut i = 0
  while i < n {
    out.push((lat.bot)())
    i = i + 1
  }
  let pending : Array[Bool] = Array::make(n, true)
  let mut any = true
  while any {
    any = false
    let mut v = 0
    while v < n {
      if pending[v] {
        pending[v] = false
        // IN[B] = ⊔ over the predecessors' OUT, and OUT[B] = F(IN[B]).
        let y = transfer(v, join_of_nodes(lat, out, preds[v]))
        if (lat.eq)(out[v], y) == false {
          out[v] = y
          // THE OPTIMIZATION: the OUT moved, so every successor has to look at
          // the new value. A block whose OUT did not move is NOT put back on the
          // list, because "OUT will not change if IN does not change".
          let mut k = 0
          while k < succs[v].length() {
            let s = succs[v][k]
            if pending[s] == false {
              pending[s] = true
              any = true
            }
            k = k + 1
          }
        }
      }
      v = v + 1
    }
  }
  out
}
