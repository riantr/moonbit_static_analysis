// 0600: CFL-REACHABILITY -- the realizable-path language, and what this
// tree's own supergraph does to it.
//
// THE DECK. `CFL-Reachability and IFDS` (Yue Li, Nanjing University, 2021).
// Its p.24-42 is "CFL-Reachability", and its concrete instance is the
// "Partially Balanced-Parenthesis Problem via CFL" of p.27-39.
//
// AND THE DECK'S DEFINITION, p.24:
//
//   A path is considered to connect two nodes A and B, or B is reachable
//   from A, only if the concatenation of the labels on the edges of the path
//   is a word in a specified context-free language.
//
// AND THE DECK'S LABELLING, p.27, verbatim:
//
//   Every right parenthesis ")i" is balanced by a preceding left parenthesis
//   "(i", but the converse needs not hold
//   For each call site i, label its call edge "(i" and return edge ")i"
//   Label all other edges with symbol "e"
//
// AND THE GRAMMAR, p.34-38:
//
//   realizable -> matched realizable
//               -> (i realizable
//               -> eps
//
//   matched   -> (i matched )i
//               -> e
//               -> eps
//               -> matched matched
//
// AND THE DECK'S TWO MEMBERSHIP ROWS, p.41-42:
//
//   e(1eee)1e          in L(realizable)
//   e(1eee)1e(2eee)1   not in L(realizable)
//
// AND THE DECK'S OWN PATH, p.29, which is realizable:
//
//   (1 (2 e )2 )1 (3
//
// WHY THIS IS A MEASUREMENT AND NOT A DESCRIPTION. This tree's supergraph
// (`icfg.mbt`) already has call edges, return edges and call-to-return edges,
// so the deck's labelling rule is a rule about edges THIS TREE ALREADY HAS.
// The question is then not "can this be implemented" but "what does the rule
// say about the paths that are already there", and the answer is measurable
// on the tree's own graph.
//
// AND THE ANSWER IS NOT "all of them". A function called from two places has
// ONE exit and TWO return edges, so a path may enter the callee through one
// call and leave through the other's return edge. The word of that path has
// a `)i` that no `(i` on the path matches, so it is NOT in L(realizable) --
// and the deck's p.24 definition says such a path does not connect the two
// nodes. The search below finds that witness on the tree's own graph.
//
// AND THIS IS WHERE 0599 AND 0600 MEET. The tree's supergraph is the
// DISTRIBUTIVE one: it has the call-to-return edge, which is what
// distributivity buys. The CFL formulation does not need that edge, and the
// price of having it is visible here -- the supergraph holds paths that are
// not call sequences, and the CFL definition is what excludes them.

///|
/// ONE EDGE'S LABEL, in the deck's own alphabet.
///
/// AND THE SITE IS CARRIED, not just the shape, because the grammar's rule
/// `matched -> (i matched )i` MATCHES THE SITE: the `)i` closes the `(i`, and
/// a label that only said "a closing parenthesis" could not tell a match from
/// a mismatch. That is the whole content of the deck's p.27 sentence.
pub(all) enum CflSym {
  /// The deck's `e`: every edge that is neither a call edge nor a return edge.
  E
  /// The deck's `(i`: the call edge of call site `i`.
  Open(Int32)
  /// The deck's `)i`: the return edge of call site `i`.
  Close(Int32)
}

///|
/// THE RECOGNISER FOR `L(realizable)`, as a stack.
///
/// AND THE STACK IS THE DERIVATION. A word is realizable iff no `)i` in it
/// fails to close the innermost unmatched `(i`:
///
///   * a `)i` with an EMPTY stack is a closing parenthesis with no opening
///     one, which p.27 forbids outright;
///   * a `)i` whose site is not the top of the stack closes the wrong
///     parenthesis, which the grammar's `matched -> (i matched )i` forbids;
///   * and whatever is LEFT on the stack at the end is fine, because
///     `realizable -> (i realizable` puts an unmatched opening parenthesis
///     at the front of a realizable word. That is p.27's "the converse needs
///     not hold": an opening parenthesis need not be closed, but a closing one
///     must be.
///
/// AND THE ALTERNATIVE WOULD BE A PARSER FOR THE GRAMMAR, and a parser is a
/// second implementation of the same language. The stack IS the grammar,
/// read left to right.
pub fn cfl_word_realizable(word : Array[CflSym]) -> Bool {
  let stack : Array[Int32] = []
  for sym in word {
    match sym {
      E => ()
      Open(i) => stack.push(i)
      Close(i) => {
        if stack.length() == 0 {
          return false
        }
        let top = stack[stack.length() - 1]
        if top != i {
          return false
        }
        let _ = stack.pop()
      }
    }
  }
  true
}

///|
/// ONE LABEL, in the deck's own spelling.
pub fn cfl_sym_text(sym : CflSym) -> String {
  match sym {
    E => "e"
    Open(i) => "(" + i.to_string()
    Close(i) => ")" + i.to_string()
  }
}

///|
/// A WORD, in the deck's own spelling, with the labels separated by spaces
/// so that a word can be read off a slide.
pub fn cfl_word_text(word : Array[CflSym]) -> String {
  let parts : Array[String] = []
  for sym in word {
    parts.push(cfl_sym_text(sym))
  }
  parts.join(" ")
}

///|
/// THE CALL SITE A CALL EDGE LEAVES, as the deck's `i`.
///
/// AND THE INDEX IS THE INDEX INTO THE GRAPH'S OWN CALL-SITE LIST, so the
/// `i` of one edge and the `i` of its partner are the same number because
/// they come from the same place -- not because two functions agreed on a
/// naming convention.
fn cfl_call_site_at(g : Icfg, v : Int32) -> Int32 {
  let mut i = 0
  while i < g.call_sites.length() {
    if g.call_sites[i].node == v {
      return i
    }
    i = i + 1
  }
  -1
}

///|
/// THE CALL SITE A RETURN EDGE BELONGS TO.
///
/// AND A RETURN EDGE IS FOUND BY ITS TARGET, because the edge leaves the
/// CALLEE's exit and lands in the CALLER's return site, and the return site
/// is what identifies the call. A callee called from two places has two
/// return edges from the SAME exit node, and they are told apart by where
/// they land.
fn cfl_return_site_at(g : Icfg, v : Int32, w : Int32) -> Int32 {
  let mut i = 0
  while i < g.call_sites.length() {
    let cs = g.call_sites[i]
    if cs.callee == g.fn_of[v] &&
      g.succ[cs.node].length() > 0 &&
      g.succ[cs.node][0] == w {
      return i
    }
    i = i + 1
  }
  -1
}

///|
/// THE LABEL OF THE `k`-th EDGE LEAVING `v`, by the deck's p.27 rule.
///
/// AND AN EDGE THAT CANNOT BE LABELLED IS `e`, which is the sound direction:
/// an unlabelled edge is treated as an ordinary one, so it can never close a
/// parenthesis it did not open.
pub fn cfl_edge_symbol(g : Icfg, v : Int32, k : Int32) -> CflSym {
  match g.labels[v][k] {
    Call(_, _) => {
      let i = cfl_call_site_at(g, v)
      if i < 0 {
        E
      } else {
        Open(i)
      }
    }
    Ret(_, _) => {
      let w = g.succ[v][k]
      let i = cfl_return_site_at(g, v, w)
      if i < 0 {
        E
      } else {
        Close(i)
      }
    }
    _ => E
  }
}

///|
/// THE WORD OF A PATH, given the edges it takes.
///
/// AND THE PATH IS A LIST OF EDGES, not a list of nodes, because a graph can
/// have SEVERAL edges between the same two nodes and the label belongs to the
/// edge. A path given as nodes would have to guess which edge each step took.
pub fn cfl_path_word(g : Icfg, edges : Array[(Int32, Int32)]) -> Array[CflSym] {
  let out : Array[CflSym] = []
  for e in edges {
    out.push(cfl_edge_symbol(g, e.0, e.1))
  }
  out
}

///|
/// WHAT THE SEARCH FOUND.
pub(all) struct CflSearch {
  /// Is this node reachable from some function's entry by a REALIZABLE path?
  reachable : Array[Bool]
  /// The number of (node, stack) states explored.
  states : Int32
  /// Did the search stop at its bound? True means "the numbers below are a
  /// LOWER bound", and a lower bound that already found a witness is a
  /// witness.
  bounded : Bool
  /// Was a path whose word is NOT in L(realizable) found?
  found : Bool
  /// The edges of that path, as (node, edge index) pairs, up to and including
  /// the offending one.
  path : Array[(Int32, Int32)]
  /// The word of that path.
  word : Array[CflSym]
  /// The stack just before the offending edge.
  stack : Array[Int32]
}

///|
/// THE PROGRAM'S ENTRY, AS THE GRAPH SAYS IT.
///
/// AND IT IS DERIVED, NOT ASSUMED. The tree's interprocedural graph has one
/// entry PER FUNCTION, and the deck's supergraph has ONE entry (the `0` of
/// p.166). The node that plays the deck's role is the function NO CALL
/// REACHES -- the one every program starts in, because nothing calls it.
///
/// AND WHEN THERE IS NO SUCH FUNCTION the fallback is the first function's
/// entry, and the fallback is NAMED rather than hidden: a program whose
/// functions all call each other has no entry the deck's sense.
pub fn cfl_program_entry(g : Icfg) -> Int32 {
  let called : Map[Int32, Bool] = Map([])
  let mut i = 0
  while i < g.call_sites.length() {
    called.set(g.call_sites[i].callee, true)
    i = i + 1
  }
  let mut f = 0
  while f < g.entry_of.length() {
    if !called.contains(f) {
      return g.entry_of[f]
    }
    f = f + 1
  }
  g.entry_of[0]
}

///|
/// THE NODES AN ORDINARY PATH REACHES FROM `start`.
///
/// AND THIS IS THE COMPARISON the deck's p.24 definition makes: a path
/// connects two nodes only if its word is in the language, so the set of
/// nodes an ordinary path reaches and the set a REALIZABLE path reaches are
/// two different sets, and the difference is what the definition excludes.
pub fn cfl_ordinary_from(g : Icfg, start : Int32) -> Array[Bool] {
  let seen : Array[Bool] = []
  let mut i = 0
  while i < g.kinds.length() {
    seen.push(false)
    i = i + 1
  }
  let work : Array[Int32] = [start]
  let mut k = 0
  while k < work.length() {
    let v = work[k]
    k = k + 1
    if v < 0 || v >= seen.length() || seen[v] {
      continue
    }
    seen[v] = true
    let mut e = 0
    while e < g.succ[v].length() {
      work.push(g.succ[v][e])
      e = e + 1
    }
  }
  seen
}

///|
/// THE SEARCH: the nodes reachable by a realizable path, and the first path
/// that is NOT one.
///
/// AND IT IS THE DECK'S DEFINITION, EXECUTED. A state is a node together with
/// the stack of unmatched opening parentheses, and a state is reached only by
/// edges the language accepts -- so the reachable set is exactly the set of
/// nodes the deck's p.24 definition connects to the start.
///
/// AND THE WITNESS IS THE POINT. The search does NOT stop at the first
/// mismatch; it RECORDS it and keeps going, because the question is not "is
/// there a bad path" but "what does the tree's own graph contain".
///
/// AND THE BOUND IS HONEST. The state space is (node, stack), and the stack
/// grows with every call edge, so the search can be exponential. The bound
/// says so in the result rather than silently truncating.
pub fn cfl_search_from(g : Icfg, start : Int32, limit : Int32) -> CflSearch {
  let reachable : Array[Bool] = []
  let mut i = 0
  while i < g.kinds.length() {
    reachable.push(false)
    i = i + 1
  }
  let visited : Map[String, Bool] = Map([])
  let parent : Map[String, String] = Map([])
  let via : Map[String, Int32] = Map([])
  let work : Array[(Int32, Array[Int32])] = [(start, [])]
  let mut states = 0
  let mut found = false
  let mut bounded = false
  let mut out_path : Array[(Int32, Int32)] = []
  let mut out_word : Array[CflSym] = []
  let mut out_stack : Array[Int32] = []
  while work.length() > 0 {
    let item = match work.pop() {
      Some(x) => x
      None => break
    }
    let v = item.0
    let stack = item.1
    let key = cfl_state_key(v, stack)
    if visited.contains(key) {
      continue
    }
    visited.set(key, true)
    states = states + 1
    if states > limit {
      bounded = true
      break
    }
    let mut k = 0
    while k < g.succ[v].length() {
      let sym = cfl_edge_symbol(g, v, k)
      let w = g.succ[v][k]
      match sym {
        E => {
          let next = stack.copy()
          cfl_push_state(work, parent, via, w, next, v, stack, k)
        }
        Open(site) => {
          let next = stack.copy()
          next.push(site)
          cfl_push_state(work, parent, via, w, next, v, stack, k)
        }
        Close(site) => {
          if stack.length() == 0 || stack[stack.length() - 1] != site {
            // THE WITNESS: a closing parenthesis that closes nothing, or the
            // wrong thing. The word up to here is NOT in L(realizable).
            //
            // AND ONLY THE FIRST WITNESS IS KEPT. The search carries on -- the
            // question is not "is there a bad path" but "what does the tree's
            // own graph contain" -- but a result that changed with the search
            // order would be a result with no order at all.
            if !found {
              found = true
              out_path = cfl_chain(parent, via, key)
              out_path.push((v, k))
              out_word = cfl_path_word(g, out_path)
              out_stack = stack.copy()
            }
            k = g.succ[v].length()
            continue
          }
          let next : Array[Int32] = []
          let mut s = 0
          while s < stack.length() - 1 {
            next.push(stack[s])
            s = s + 1
          }
          cfl_push_state(work, parent, via, w, next, v, stack, k)
        }
      }
      k = k + 1
    }
  }
  // THE REACHABLE SET: every node some realized state stands on.
  for key, _ in visited {
    let at = cfl_node_of_key(key)
    if at >= 0 && at < reachable.length() {
      reachable[at] = true
    }
  }
  {
    reachable,
    states,
    bounded,
    found,
    path: out_path,
    word: out_word,
    stack: out_stack,
  }
}

///|
/// PUT A STATE ON THE WORKLIST, AND RECORD HOW IT WAS REACHED.
///
/// AND THE PARENT AND THE EDGE ARE RECORDED HERE, at the moment the state is
/// created, because a path that cannot be rebuilt is not a witness: the
/// witness has to be the path the search actually took.
fn cfl_push_state(
  work : Array[(Int32, Array[Int32])],
  parent : Map[String, String],
  via : Map[String, Int32],
  node : Int32,
  stack : Array[Int32],
  from : Int32,
  from_stack : Array[Int32],
  edge : Int32,
) -> Unit {
  let key = cfl_state_key(node, stack)
  if !parent.contains(key) {
    parent.set(key, cfl_state_key(from, from_stack))
    via.set(key, edge)
  }
  work.push((node, stack))
}

///|
/// THE CONNECTIONS THE DECK'S DEFINITION KEEPS AND THE ONES IT DROPS.
///
/// AND THE MEASUREMENT IS AT THE PAIR LEVEL, because the deck's p.24 speaks
/// about PAIRS: "A path is considered to connect two nodes A and B". So the
/// question is how many of the graph's own connections -- the ordered pairs
/// an ordinary path connects -- survive the language test.
///
/// AND THE THREE NUMBERS ARE `(ordinary, realizable, excluded)`, and the
/// third is the difference, because a realizable path IS a path: the
/// language can only DROP connections, never add them. A run where the third
/// number is not `ordinary - realizable` would mean the two searches
/// disagreed about the graph itself, which is a bug in the measurement.
pub fn cfl_pair_counts(g : Icfg, limit : Int32) -> (Int32, Int32, Int32) {
  let mut ordinary = 0
  let mut realizable = 0
  let mut excluded = 0
  let mut u = 0
  while u < g.kinds.length() {
    let ord = cfl_ordinary_from(g, u)
    let cfl = cfl_search_from(g, u, limit).reachable
    let mut v = 0
    while v < g.kinds.length() {
      if ord[v] {
        ordinary = ordinary + 1
        if cfl[v] {
          realizable = realizable + 1
        } else {
          excluded = excluded + 1
        }
      }
      v = v + 1
    }
    u = u + 1
  }
  (ordinary, realizable, excluded)
}

///|
/// A state's key: the node, and the stack below it.
fn cfl_state_key(v : Int32, stack : Array[Int32]) -> String {
  let parts : Array[String] = []
  for s in stack {
    parts.push(s.to_string())
  }
  v.to_string() + "|" + parts.join(",")
}

///|
/// The node a state key names.
fn cfl_node_of_key(key : String) -> Int32 {
  let mut i = 0
  let mut n = 0
  while i < key.length() {
    let c = key[i]
    if c == '|' {
      break
    }
    n = n * 10 + (c.to_int() - '0'.to_int())
    i = i + 1
  }
  n
}

///|
/// THE PATH TO A STATE, rebuilt from the parent links, as the edges it took.
///
/// AND THE EDGES ARE THE `via` OF EACH STATE, so the edge that reached a
/// state is the edge that state was reached BY -- not a guess at which edge
/// between two nodes was meant.
///
/// AND THE NODE IN THE PAIR IS THE NODE THE EDGE LEAVES, which is the
/// PARENT's node: `via[K]` is the edge taken at the parent of `K` to reach
/// `K`. Pairing it with `K`'s own node would ask the graph for an edge index
/// at a node that does not have it.
fn cfl_chain(
  parent : Map[String, String],
  via : Map[String, Int32],
  key : String,
) -> Array[(Int32, Int32)] {
  let rev : Array[(Int32, Int32)] = []
  let mut cur = key
  let mut steps = 0
  while steps < 10000 {
    match parent.get(cur) {
      Some(p) => {
        let edge = match via.get(cur) {
          Some(e) => e
          None => 0
        }
        rev.push((cfl_node_of_key(p), edge))
        cur = p
        steps = steps + 1
      }
      None => break
    }
  }
  let out : Array[(Int32, Int32)] = []
  let mut i = rev.length() - 1
  while i >= 0 {
    out.push(rev[i])
    i = i - 1
  }
  out
}
