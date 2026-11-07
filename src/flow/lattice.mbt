// flow: the dataflow half of the analyzer.
//
// WHY THIS PACKAGE EXISTS. Until now every pass in this tree was a RECURSIVE
// FUNCTION OVER THE AST: `walk` descends and reports, `guardfacts` carries a
// fact set down a block and drops it at a loop, `infer` annotates expressions.
// That shape can express "look at this node in isolation" and it cannot express
// "the answer at this point is the JOIN of the answers at its predecessors,
// and that system of equations has a least solution".
//
// The five families this tree already has were built without one, and the
// places where it shows are recorded rather than hidden: `guardfacts` throws
// away every fact about a name a loop body assigns (a fact proved before a loop
// is not a fact after one iteration), and the type lens checks a call's
// arguments only when the callee is declared in the same file. Both of those
// are the same missing object -- a control-flow graph with a fixed point over a
// lattice -- and this package is that object, built to the classical
// formulation (Moller & Schwartzbach, `Static Program Analysis`, chapters 2.5,
// 4.4, 5.1-5.3, 5.10).
//
// THE CONTRACT OF THE PACKAGE, in one paragraph: a `Lattice` supplies a bottom,
// a least upper bound and equality; a transfer function maps (node, input) to
// output; and `solve_round_robin` / `solve_propagation` both compute the least
// fixed point of the resulting equation system. Both solvers are here ON
// PURPOSE, because the book proves they must agree (Exercise 5.41) and a proof
// in a paper is not a test in this tree: `flow_worklist_test.mbt` runs them
// against each other on the same graph, and a disagreement is a failure.

///|
/// A complete lattice, as the framework actually needs it.
///
/// WHY THREE OPERATIONS AND NOT A TRAIT. This toolchain's idiom in this tree is
/// plain values and plain functions (there is no trait in `src/` today), and a
/// solver that demanded one would force every analysis to be a type before it
/// could be a value. Three closures are enough to state the fixed-point
/// theorem: `bot` seeds the ascending chain, `join` is the least upper bound
/// that makes the chain ascend, and `eq` is what "the chain stopped" means.
///
/// `join` MUST be an upper bound and MUST be associative and commutative for
/// the solvers to return the least fixed point; `eq` MUST be the equality that
/// agrees with the lattice order. Neither is checkable at this level, so each
/// analysis documents its own lattice and `flow_worklist_test.mbt` pins the
/// laws on a concrete one.
///
/// WHY `bot` IS A THUNK AND NOT A VALUE. Every solver seeds one slot per node
/// with `bot`. If `bot` is a value and the element is MUTABLE -- a set, a map,
/// an array, which is what live variables and interval states are made of --
/// then every slot holds THE SAME object and the first join writes into all of
/// them at once. That is not hypothetical: `pred_of` in this package shipped
/// that bug for one compile, and the merge-node test caught it (`[0, 0, 1, 2]`
/// where `[1, 2]` was expected). A thunk makes a fresh element unavoidable.
pub(all) struct Lattice[T] {
  bot : () -> T
  join : (T, T) -> T
  eq : (T, T) -> Bool
}

///|
/// The least upper bound of a whole set, starting from `bot`.
///
/// An empty set joins to `bot`, which is the lattice's unit for `join` -- the
/// entry node of a function has no predecessors and its abstract state is
/// therefore `bot`, exactly as the book's Exercise 5.1(a) says it must be.
pub fn[T] join_all(lat : Lattice[T], xs : Array[T]) -> T {
  let mut acc = (lat.bot)()
  let mut i = 0
  while i < xs.length() {
    acc = (lat.join)(acc, xs[i])
    i = i + 1
  }
  acc
}

///|
/// `join_all` over a set of node indices, reading each node's current value.
///
/// This is the `JOIN(v) = ⊔_{w ∈ pred(v)} [[w]]` of the book, written once so
/// that every analysis spells it the same way.
pub fn[T] join_of_nodes(
  lat : Lattice[T],
  state : Array[T],
  nodes : Array[Int32],
) -> T {
  let mut acc = (lat.bot)()
  let mut i = 0
  while i < nodes.length() {
    acc = (lat.join)(acc, state[nodes[i]])
    i = i + 1
  }
  acc
}
