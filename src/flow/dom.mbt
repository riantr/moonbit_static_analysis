// 0553: DOMINATORS -- the map the deck's SSA needs, and the deck never prints.
//
// THE REFERENCE IS THE SAME ATTACHMENT 0551 AND 0552 READ: Yue Li,
// `Intermediate Representation`, Nanjing University, Fall 2026. Section five is
// STATIC SINGLE ASSIGNMENT, and it is the last section of the deck this tree
// has not built.
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
//
// AND THE DECK NEVER SAYS HOW A MERGE IS FOUND. It says a phi-function
// "select[s] the values at MERGE NODES", and the drawing draws a merge node as
// a node with two INCOMING edges. A drawing is not an algorithm, and the two
// are not the same question:
//
//   * "WHICH NODES HAVE TWO INCOMING EDGES" is the picture's question, and it
//     is a question about the GRAPH.
//   * "WHERE MUST TWO DEFINITIONS OF ONE VARIABLE MEET" is the SSA question,
//     and it is a question about DEFINITIONS.
//
// THE TWO DISAGREE, and the deck's own program is the witness (p.46, p.57):
// its block B2 holds `z = x * y` and its block B4 holds `a = q`; the block B4
// has two incoming edges, but `a` is defined only in B4, so B4 needs no
// phi-function for `a` -- while `z`, defined in B2, DOES need one there,
// because the other way into B4 never defines `z`. The answer to "where a phi
// is needed" is the DOMINANCE FRONTIER, and this file computes it.
//
// THE ALGORITHM IS THE CLASSIC ONE, and it is written out here because the
// project's rule is that a step that is not written down is a step nobody can
// check:
//
//   1. REVERSE POSTORDER of the reachable blocks, from the entry.
//   2. The IMMEDIATE DOMINATOR of every block, by the fixed point of
//      "the idom of a block is the nearest common dominator of its
//      predecessors", walked in reverse postorder until it stops changing.
//   3. The DOMINANCE FRONTIER of a block: the blocks its definitions reach
//      along one path but not along all of them.
//
// AND EVERY NUMBER HERE IS MEASURED, NOT ASSERTED: `ssa_test.mbt` checks the
// tree and the frontiers against hand-computed ones, on the deck's own program
// and on a program with a loop.

///|
/// The dominator tree of a block graph.
///
/// A BLOCK A DOMINATES A BLOCK B when every path from the entry to B goes
/// through A. The IMMEDIATE dominator of B is the dominator of B that is
/// closest to B, and the immediate dominators form a TREE rooted at the entry.
///
/// THE TREE IS WHAT SSA NEEDS, and this is the whole reason it is here: a
/// definition in block D reaches a use in block U only when D dominates U. So
/// the renaming walk can be a walk OF THE TREE: when the walk leaves a
/// subtree, the definitions made inside that subtree are no longer live, and
/// they can be popped off the stack in one step.
pub(all) struct Dom {
  /// The immediate dominator of each block; -1 for a block the program cannot
  /// reach.
  idom : Array[Int32]
  /// The reachable blocks, in REVERSE POSTORDER.
  ///
  /// THE ORDER IS NOT COSMETIC: the fixed point below is walked in this order,
  /// and the nearest common dominator of two blocks is decided by the
  /// positions in it.
  rpo : Array[Int32]
  /// The position of each block in `rpo`; -1 for an unreachable block.
  rpo_num : Array[Int32]
  /// The children of each block in the dominator tree.
  children : Array[Array[Int32]]
}

///|
/// The dominator tree of a block graph.
///
/// THE ENTRY IS THE ROOT, and a block the program cannot reach has no
/// dominator at all -- it is not "dominated by nothing", it is not part of the
/// tree, and `idom` says so with -1. A block that is unreachable is also
/// unreachable for SSA: no definition can reach a use in it, so there is
/// nothing there to rename.
pub fn dominators(bb : Bb) -> Dom {
  let n = bb.blocks.length()
  let rpo = reverse_postorder(bb)
  let rpo_num : Array[Int32] = Array::make(n, -1)
  let mut i = 0
  while i < rpo.length() {
    rpo_num[rpo[i]] = i
    i = i + 1
  }
  let idom = compute_idom(bb, rpo, rpo_num)
  // THE TREE, and it is built from `idom` rather than computed again: two
  // derivations of "the children of a dominator" are two things that can
  // disagree, and this one is free.
  let children : Array[Array[Int32]] = []
  let mut c = 0
  while c < n {
    children.push([])
    c = c + 1
  }
  let mut b = 0
  while b < n {
    // The entry is its own idom and is the root, so it is not its own child.
    if rpo_num[b] >= 0 && idom[b] != b {
      children[idom[b]].push(b)
    }
    b = b + 1
  }
  { idom, rpo, rpo_num, children, }
}

///|
/// The dominance frontier of every block.
///
/// THE FRONTIER OF A BLOCK B IS THE SET OF BLOCKS THAT B DOMINATES ON ONE
/// PATH BUT NOT ON ALL OF THEM -- the blocks where a definition made in B has
/// to be MERGED with a definition made somewhere else. That is exactly where
/// the deck's phi-function goes, so the frontier is the deck's "merge nodes",
/// computed rather than drawn.
///
/// THE STANDARD FORM IS USED, AND IT IS THE FORM THAT MAKES THE PHI COUNT
/// MINIMAL: for every successor S of B, and every predecessor P of S, walk up
/// the dominator tree from P until the immediate dominator of S, and every
/// block walked over has S in its frontier.
pub fn dominance_frontiers(bb : Bb, dom : Dom) -> Array[Array[Int32]] {
  let n = bb.blocks.length()
  // ONE FRESH ARRAY PER BLOCK, for the reason `pred_of` gives: `Array::make`
  // with an array value fills every slot with the SAME reference.
  let df : Array[Array[Int32]] = []
  let mut i = 0
  while i < n {
    df.push([])
    i = i + 1
  }
  let mut b = 0
  while b < n {
    if dom.rpo_num[b] >= 0 {
      let mut si = 0
      while si < bb.succ[b].length() {
        let s = bb.succ[b][si]
        let mut pi = 0
        while pi < bb.pred[s].length() {
          let p = bb.pred[s][pi]
          if dom.rpo_num[p] >= 0 {
            // UP THE TREE FROM P, until the immediate dominator of S. The walk
            // stops there and not before: a block above S's immediate
            // dominator dominates S itself, so it is not in S's frontier.
            let mut x = p
            while x != dom.idom[s] {
              if df[x].contains(s) == false {
                df[x].push(s)
              }
              x = dom.idom[x]
            }
          }
          pi = pi + 1
        }
        si = si + 1
      }
    }
    b = b + 1
  }
  df
}

///|
/// The reachable blocks, in REVERSE POSTORDER.
///
/// IT IS AN ITERATIVE DFS, and not a recursive one, because the graph can be
/// as deep as the program is long and a recursive walk over a deep program is
/// a stack overflow in the middle of a measurement.
fn reverse_postorder(bb : Bb) -> Array[Int32] {
  let n = bb.blocks.length()
  let post : Array[Int32] = []
  if bb.entry < 0 || bb.entry >= n {
    return post
  }
  let visited = Array::make(n, false)
  // The next successor to visit of each block: the DFS's own stack frames.
  let next : Array[Int32] = Array::make(n, 0)
  visited[bb.entry] = true
  let stack : Array[Int32] = [bb.entry]
  while stack.length() > 0 {
    let b = stack[stack.length() - 1]
    let i = next[b]
    if i < bb.succ[b].length() {
      next[b] = i + 1
      let s = bb.succ[b][i]
      if visited[s] == false {
        visited[s] = true
        stack.push(s)
      }
    } else {
      post.push(b)
      stack.pop() |> ignore
    }
  }
  // REVERSED, because a postorder visit ends a block's descendants first and
  // the dominator algorithm wants the other order.
  let rpo : Array[Int32] = []
  let mut k = post.length() - 1
  while k >= 0 {
    rpo.push(post[k])
    k = k - 1
  }
  rpo
}

///|
/// The immediate dominator of every block.
///
/// THE FIXED POINT, walked in reverse postorder: the immediate dominator of a
/// block is the nearest common dominator of its predecessors, and the
/// predecessors that come LATER in the order are not known yet -- so the
/// predecessors that have no idom yet are left out, and the whole thing is
/// repeated until it stops changing.
fn compute_idom(
  bb : Bb,
  rpo : Array[Int32],
  rpo_num : Array[Int32],
) -> Array[Int32] {
  let n = bb.blocks.length()
  let idom : Array[Int32] = Array::make(n, -1)
  if rpo.length() == 0 {
    return idom
  }
  idom[bb.entry] = bb.entry
  let mut changed = true
  while changed {
    changed = false
    let mut i = 0
    while i < rpo.length() {
      let b = rpo[i]
      if b != bb.entry {
        let mut new_idom = -1
        let mut k = 0
        while k < bb.pred[b].length() {
          let p = bb.pred[b][k]
          // A predecessor with no idom yet is either unreachable or not
          // visited yet, and in both cases it says nothing about this block.
          if idom[p] != -1 {
            if new_idom == -1 {
              new_idom = p
            } else {
              new_idom = intersect(p, new_idom, idom, rpo_num)
            }
          }
          k = k + 1
        }
        if new_idom != -1 && idom[b] != new_idom {
          idom[b] = new_idom
          changed = true
        }
      }
      i = i + 1
    }
  }
  idom
}

///|
/// The nearest common dominator of two blocks.
///
/// IT WALKS BOTH CHAINS UP THE TREE, always moving the one that is FURTHER
/// FROM THE ENTRY, and they meet at the nearest common dominator. The
/// comparison is on the reverse-postorder positions, because the tree is
/// ordered by them.
fn intersect(
  a : Int32,
  b : Int32,
  idom : Array[Int32],
  rpo_num : Array[Int32],
) -> Int32 {
  let mut x = a
  let mut y = b
  while x != y {
    while rpo_num[x] > rpo_num[y] {
      x = idom[x]
    }
    while rpo_num[y] > rpo_num[x] {
      y = idom[y]
    }
  }
  x
}
