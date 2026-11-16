// 0598: THE TABULATION ALGORITHM -- the deck's step 3, and the answer it gives.
//
// THE DECK. `CFL-Reachability and IFDS` (Yue Li, Nanjing University, 2021).
// p.52-56 gives the three steps, and this file is the THIRD:
//
//   3. Q can be solved as graph reachability problems (find out MRP solutions)
//      via applying Tabulation algorithm on G#
//
// AND p.139-140 states what the algorithm DOES, in its own words:
//
//   Given an exploded supergraph G#, Tabulation algorithm determines the MRP
//   solution by finding out all realizable paths starting from <smain, 0>
//
//   Let n be a program point, data fact d in MRPn, iff there is a realizable
//   path in G# from <smain, 0> to <n, d>. (then d's white circle turns to blue)
//
// AND p.141 gives the cost: O(ED3). p.142-143 says the deck does NOT cover the
// whole algorithm -- "No time to cover the whole algorithm. But we will
// introduce its core working mechanism by a simple example" -- and p.144-150
// are that example, over the call/return structure (SP, eP, CallP, RetP).
//
// SO THIS FILE IS THE INTRAPROCEDURAL TABULATION: the reachability over the
// exploded supergraph, which is what "finding out all realizable paths
// starting from <smain, 0>" means when the supergraph is one flow graph.
//
// AND THE MEASUREMENT IS THE POINT OF THE INCREMENT, and it has two sides:
//
//   1. THE TABULATION REPRODUCES THE ANALYSIS THIS TREE ALREADY COMPUTES.
//      `reaching_out` / `reaching_in` are the traditional reaching-definitions
//      analysis, and the tabulated facts at every node must EQUAL them -- node
//      by node, fact by fact. That is not a tautology: the traditional
//      analysis solves a fixed-point equation over sets, and the tabulation
//      walks a graph. Two readings of the same transfer functions.
//
//   2. WITHOUT THE GLUE EDGE, THE ANSWER IS EMPTY. The deck's p.92-96 says
//      that without the edge 0->0 "the representation relation for each edge
//      cannot be connected or 'pasted' together ... Thus IFDS cannot produce
//      correct solutions via such disconnected representation relations." That
//      is a claim about the ANSWER, and 0597 built the graph that makes it
//      measurable.

///|
/// The result of a tabulation: the facts reachable at every node, and how
/// much walking it took.
pub(all) struct Tabulation {
  /// The reachable facts at every node of the exploded supergraph.
  states : Array[DefSet]
  /// The number of exploded edges the walk followed.
  visited : Int32
}

///|
/// The TABULATION: the facts reachable at every node of the exploded
/// supergraph, starting from `<start, 0>`.
///
/// AND THE ZERO FACT IS IN THE ANSWER, because it is a fact of the exploded
/// supergraph like any other: the deck's own picture has a `0` at every node
/// it reaches. The zero fact is also what carries the constant parts, so a
/// tabulation that dropped it would not be the tabulation.
///
/// AND THE FACTS ARE `DefSet` -- the tree's own set of definitions -- and not
/// a new carrier, because the answer has to be comparable with
/// `reaching_in`'s and a second set type would be a second thing to keep in
/// step.
///
/// AND THE WORKLIST IS TWO ARRAYS AND NOT A STRING, because the pair
/// `(node, fact)` is a PAIR and encoding it into a string and splitting it
/// again would be a second representation of a thing the tree already has two
/// fields for.
pub fn ifds_tabulate(x : Exploded, start : Int32) -> Tabulation {
  let states : Array[DefSet] = []
  let mut i = 0
  while i < x.nodes {
    states.push(name_set_empty())
    i = i + 1
  }
  if start < 0 || start >= x.nodes {
    return { states, visited: 0, }
  }
  states[start].set(ifds_zero(), true)
  let work_node : Array[Int32] = [start]
  let work_fact : Array[String] = [ifds_zero()]
  let mut head = 0
  let mut visited = 0
  while head < work_node.length() {
    let node = work_node[head]
    let fact = work_fact[head]
    head = head + 1
    for e in x.edges {
      if e.from_node == node && e.from_fact == fact {
        visited = visited + 1
        if states[e.to_node].contains(e.to_fact) == false {
          states[e.to_node].set(e.to_fact, true)
          work_node.push(e.to_node)
          work_fact.push(e.to_fact)
        }
      }
    }
  }
  { states, visited, }
}

///|
/// The tabulation's facts at one node, WITHOUT the zero fact -- which is the
/// set a reader compares with the traditional analysis's `IN[n]`.
///
/// AND THE ZERO FACT IS DROPPED AND NOT FORGOTTEN, because it is the carrier
/// and not a fact about the program: `IN[n]` of the reaching-definitions
/// analysis holds DEFINITIONS, and a comparison that included the carrier
/// would be comparing two different things.
pub fn ifds_defs_at(st : DefSet) -> DefSet {
  let out = name_set_empty()
  for k, _ in st {
    if k != ifds_zero() {
      out.set(k, true)
    }
  }
  out
}

///|
/// The tabulation's answer, printed in a stable order, for a test that wants
/// to READ it rather than count it.
pub fn ifds_tabulate_text(t : Tabulation) -> String {
  let parts : Array[String] = []
  let mut i = 0
  while i < t.states.length() {
    parts.push(i.to_string() + ":" + def_set_text(t.states[i]))
    i = i + 1
  }
  parts.join(" ")
}

///|
/// THE DECK'S OWN BOUND, p.141: the tabulation costs O(E*D^3).
///
/// AND E IS THE NUMBER OF EDGES OF THE EXPLODED SUPERGRAPH and D is the
/// number of facts the analysis knows -- the definitions plus the zero fact.
/// The bound is a claim about a WHOLE ALGORITHM, and the deck itself says it
/// does not cover the whole algorithm (p.142-143), so what is compared with it
/// here is the intraprocedural walk's MEASURED work, with the coverage beside
/// it: a bound with no coverage is a number about nothing.
pub fn ifds_tabulate_bound(x : Exploded) -> Int32 {
  let facts = x.facts + 1
  x.edges.length() * facts * facts * facts
}
