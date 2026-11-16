// 0597: THE EXPLODED SUPERGRAPH -- and the glue edge that makes it work.
//
// THE DECK. `CFL-Reachability and IFDS` (Yue Li, Nanjing University, 2021),
// 174 pages. This file covers its CHAPTER 4 (p.58-81, the SUPERGRAPH and the
// FLOW FUNCTIONS) and the first half of its CHAPTER 5 (p.83-97, the
// EXPLODED SUPERGRAPH and the GLUE EDGE).
//
// THE DECK'S THREE STEPS (p.52-56), which are the shape of everything here:
//
//   1. Build a supergraph G* for P and define flow functions for edges in G*
//      based on Q
//   2. Build exploded supergraph G# for P by transforming flow functions to
//      representation relations (graphs)
//   3. Q can be solved as graph reachability problems (find out MRP solutions)
//      via applying Tabulation algorithm on G#
//
// AND THE THEOREM THAT MAKES STEP 3 AN ANSWER (p.55-56):
//
//   Let n be a program point, data fact d in MRPn, iff there is a REALIZABLE
//   PATH in G# from <smain, 0> to <n, d>.
//
// STEP 3 IS 0598. THIS FILE IS STEPS 1 AND 2.
//
// ------------------------------------------------------------------ the audit ---
//
// CHAPTER 4 IS ALREADY HERE, and the tree's own code says so. The supergraph
// G* of p.58-65 is:
//
//   • G* consists of a collection of flow graphs G1, G2, ... (one for each
//     procedure)                                       -- the tree's `Icfg`
//   • Each flowgraph Gp has a unique start node sp, and a unique exit node ep
//                                                   -- the tree's `Cfg.entry`/`exit`
//   • A procedure call is represented by a call node Callp, and a return-site
//     node Retp                                   -- the tree's `CallSite`
//   • G* has THREE edges for each procedure call:
//       - an intraprocedural call-to-return-site edge from Callp to Retp
//       - an interprocedural call-to-start edge from Callp to sp
//       - an interprocedural exit-to-return-site edge from ep to Retp
//
// AND `src/flow/icfg.mbt` BUILDS EXACTLY THAT -- `EdgeKind::CallToReturn`,
// `EdgeKind::Call` and `EdgeKind::Ret` -- so chapter 4 is a MEASUREMENT and not
// a second implementation. `ifds_supergraph_text` below prints the measurement
// rather than asserting it, because a supergraph that quietly grew a fourth
// edge kind would change what chapter 5 means.
//
// WHAT WAS ABSENT, AND IS THIS FILE: THE REPRESENTATION RELATIONS AND THE
// EXPLODED SUPERGRAPH. There was no way to ask this tree for the exploded
// supergraph, because there was no way to ask it for a flow function as a
// GRAPH.
//
// ---------------------------------------------------------------- the facts ----
//
// A DATA FACT is what the analysis tracks: here a DEFINITION, the tree's own
// `name@node` key from `reaching.mbt`. The ZERO FACT -- the deck's `0` -- is
// the special one, and it is what the glue edge is about.
//
// THE ZERO FACT IS NOT A DEFINITION, and it is not one of the facts the
// analysis concludes about. It is the "no input yet" carrier, and it exists
// because an IFDS flow function may have a CONSTANT PART: `lambda S.{a}` (the
// deck's own example, p.85) says "a holds at p REGARDLESS of the input S".
// Such a function has no input fact to hang its output on, so the output hangs
// on the zero fact instead, and the zero fact is what travels the path.
//
// ---------------------------------------------------------------- the rules ---
//
// THE FLOW FUNCTION IS ON THE NODE, and the deck allows it: p.47 says the path
// function "is a composition of flow functions for all edges (sometimes nodes)
// on p". Node functions are the right choice for REACHING DEFINITIONS, whose
// transfer the deck states over a BLOCK (p.48):
//
//   OUT[B] = gen_B U (IN[B] - kill_B)
//
// ------------------------------------------------------- the deck's formula ---
//
// p.84 states the representation relation of a flow function f EXACTLY:
//
//   Rf = { (0,0) } U { (0,y) | y in f(EMPTY) } U { (x,y) | y not in f(EMPTY)
//                     and y in f({x}) }
//
// and `ifds_reach_rel` below IS that formula, applied to the tree's own
// transfer. Reading it off the transfer:
//
//   f(EMPTY)   = gen_B                     the constant part
//   f({x})     = gen_B U ({x} - kill_B)
//
// so the three clauses are:
//
//   (0,0)      for every node -- THE GLUE EDGE
//   (0,g)      for every g in gen_B        the constant part
//   (x,x)      for every x not in gen_B and not in kill_B   the fact survives
//
// AND THE THIRD CLAUSE EXCLUDES THE GENERATED FACTS, and that is the deck's
// formula and not a choice: a fact in f(EMPTY) is already carried by the
// (0,y) clause, so it gets no (x,x) pair of its own. The deck's own examples
// on p.85-87 show it: `lambda S.{a}` has the edges 0->0, 0->a and b->b -- and
// NOT a->a.
//
// ---------------------------------------------------------------- the glue ----
//
// AND HERE IS WHY THE GLUE EDGE 0 -> 0 IS NEEDED (p.92-96). The deck's
// argument, in its own words:
//
//   lambda S.{a} says a holds at p regardless of input S; however, without
//   edge 0->0, the representation relation for each edge cannot be connected
//   or "pasted" together, like flow functions cannot be composed together in
//   traditional data flow analysis.
//
// THE (0,0) PAIR IS THE FIRST CLAUSE OF Rf ITSELF, and that is what makes the
// "pasting" work: the (0,0) pair is the edge that carries the ZERO FACT from
// one relation to the next, so the next relation's constant part has a zero
// fact to fire on.
//
// AND THE FIRST DRAFT OF THIS FILE HAD IT WRONG, and the measurement is what
// found it. It kept (0,0) OUT of the relation and put a 0->0 SELF-LOOP at
// every node instead -- and a self-loop carries the zero fact NOWHERE. The
// exploded supergraph that built was DISCONNECTED: MEASURED, the reachable
// set from the start pair <entry, 0> was <entry, 0> and nothing else, because
// no edge left it. That is not a refinement of the deck's claim, it is the
// deck's FAILURE CASE, and it was sitting in the code that was supposed to
// demonstrate the opposite.
//
// SO THE GLUE EDGE IS A PARAMETER, because a measurement that cannot turn the
// thing off cannot measure it, and the switch is on the RELATION -- because
// the deck's (0,0) is a clause of Rf and not an edge added beside it.
//
// THE MEASUREMENT IS IN 0598, and it is a difference in the ANSWER and not in a
// comment: with the glue edge the tabulation reproduces the analysis this tree
// already computes, and without it the tabulation stops dead.

///|
/// The ZERO FACT: the deck's `0` (p.84, p.95).
///
/// AND IT IS NOT A DEFINITION, and it can never collide with one: a
/// definition's key is `name@node`, so it always carries an `@`, and `@` is
/// not a character a MoonBit identifier contains.
pub fn ifds_zero() -> String {
  "0"
}

///|
/// One pair of a REPRESENTATION RELATION: the fact `from` becomes the fact
/// `to` under the flow function.
pub(all) struct RelEdge {
  /// The fact the flow function takes.
  from : String
  /// The fact the flow function produces.
  to : String
}

///|
/// A flow function AS A GRAPH: its representation relation.
///
/// AND THIS IS THE WHOLE OF STEP 2. The deck's p.53 says the exploded
/// supergraph is built "by transforming flow functions to representation
/// relations (graphs)", and this is the transformed thing: the same function,
/// written down as pairs instead of applied to a set.
pub(all) struct FlowRel {
  /// The pairs.
  rel : Array[RelEdge]
}

///|
/// The empty relation.
pub fn ifds_rel_empty() -> FlowRel {
  { rel: [], }
}

///|
/// The relation's pairs, printed in a stable order, for a test that wants to
/// read the relation rather than count it.
pub fn ifds_rel_text(r : FlowRel) -> String {
  let parts : Array[String] = []
  for e in r.rel {
    parts.push(e.from + "->" + e.to)
  }
  parts.sort()
  parts.join(",")
}

///|
/// One edge of the EXPLODED SUPERGRAPH: from the node-fact pair
/// `(from_node, from_fact)` to the node-fact pair `(to_node, to_fact)`.
pub(all) struct ExplodeEdge {
  from_node : Int32
  from_fact : String
  to_node : Int32
  to_fact : String
}

///|
/// The EXPLODED SUPERGRAPH G#.
///
/// AND THE GLUE EDGES ARE AMONG `edges`, because they ARE edges of G#: the
/// deck's (0,0) is a clause of the representation relation, so it becomes an
/// edge of the exploded graph like every other pair. `ifds_glue_edges` picks
/// them out again, so a caller can count them without the graph carrying them
/// twice.
pub(all) struct Exploded {
  /// The supergraph's node count.
  nodes : Int32
  /// Every edge of the exploded supergraph, the glue edges included.
  edges : Array[ExplodeEdge]
  /// How many facts (definitions) the analysis knows, the zero fact excluded.
  facts : Int32
}

///|
/// THE FACT UNIVERSE: every definition the program makes.
///
/// AND IT IS THE UNIVERSE AND NOT JUST THE ONES STILL ALIVE, because the
/// relation's "survives" half has to say which facts SURVIVE a node, and that
/// is a statement about the whole universe.
pub fn ifds_definitions(gen : Array[DefSet]) -> Array[String] {
  let out : Array[String] = []
  for g in gen {
    for k, _ in g {
      if out.contains(k) == false {
        out.push(k)
      }
    }
  }
  out.sort()
  out
}

///|
/// THE REPRESENTATION RELATION of the node's flow function, for reaching
/// definitions -- the deck's p.84 formula, applied to the tree's own transfer.
///
/// AND IT IS THE DECK'S FORMULA AND NOT A REWORDING OF IT:
///
///   Rf = { (0,0) } U { (0,y) | y in f(EMPTY) } U { (x,y) | y not in f(EMPTY)
///                       and y in f({x}) }
///
/// which for `OUT[B] = gen_B U (IN[B] - kill_B)` is three kinds of pair:
///
///   (0 -> 0)   at every node                       THE GLUE EDGE
///   (0 -> g)   for every g in gen[B]              the constant part
///   (x -> x)   for every x not in gen[B] and not in kill[B]   the fact survives
///
/// AND `glue` SWITCHES THE FIRST CLAUSE OFF, because the deck's p.92-96 is a
/// claim ABOUT that clause: without it "the representation relation for each
/// edge cannot be connected or 'pasted' together". A measurement needs both
/// sides, and the switch is on the relation because that is where the deck
/// puts the (0,0).
pub fn ifds_reach_rel(
  gen : Array[DefSet],
  kill : Array[DefSet],
  node : Int32,
  facts : Array[String],
  glue : Bool,
) -> FlowRel {
  let rel : Array[RelEdge] = []
  // THE FIRST CLAUSE: THE GLUE EDGE. It is what carries the zero fact from one
  // relation to the next, and it is why the relations can be pasted together.
  if glue {
    rel.push({ from: ifds_zero(), to: ifds_zero(), })
  }
  // THE CONSTANT PART. This is the deck's `lambda S.{a}` (p.85): the fact
  // holds afterwards whatever the input was, so it hangs on the zero fact.
  for g, _ in gen[node] {
    rel.push({ from: ifds_zero(), to: g, })
  }
  // AND THE FACTS THAT SURVIVE THE NODE. The deck's third clause says
  // `y not in f(EMPTY)`, so a fact the node GENERATES gets no (x,x) pair of
  // its own -- it is already carried by the constant part.
  for f in facts {
    if kill[node].contains(f) == false && gen[node].contains(f) == false {
      rel.push({ from: f, to: f, })
    }
  }
  { rel, }
}

///|
/// BUILD THE EXPLODED SUPERGRAPH of one procedure's flow graph.
///
/// AND `glue` IS A PARAMETER and not a constant, because the deck's p.92-96
/// is a claim ABOUT the glue edge: the measurement needs a supergraph without
/// it, and a measurement that cannot turn the thing off cannot measure it.
///
/// AND THE RELATION'S PAIRS BECOME THE EDGES: the node's flow function is
/// applied to each of its outgoing edges, so a pair (x -> y) of the node's
/// relation is the edge (node, x) -> (successor, y) -- which is exactly the
/// "pasting" the deck's p.95 talks about.
pub fn ifds_explode(
  cfg : Cfg,
  gen : Array[DefSet],
  kill : Array[DefSet],
  glue : Bool,
) -> Exploded {
  let facts = ifds_definitions(gen)
  let edges : Array[ExplodeEdge] = []
  let mut v = 0
  while v < cfg.kinds.length() {
    let rel = ifds_reach_rel(gen, kill, v, facts, glue)
    for s in cfg.succ[v] {
      for e in rel.rel {
        edges.push({
          from_node: v,
          from_fact: e.from,
          to_node: s,
          to_fact: e.to,
        })
      }
    }
    v = v + 1
  }
  { nodes: cfg.kinds.length(), edges, facts: facts.length(), }
}

///|
/// THE GLUE EDGES of an exploded supergraph -- the (0,0) pairs, picked back
/// out of the graph.
///
/// AND THEY ARE COUNTED HERE AND NOT STORED TWICE, because the glue edge is an
/// edge of G# like any other and a second field holding the same edges would
/// be the same fact written down twice.
pub fn ifds_glue_edges(x : Exploded) -> Array[ExplodeEdge] {
  let out : Array[ExplodeEdge] = []
  for e in x.edges {
    if e.from_fact == ifds_zero() && e.to_fact == ifds_zero() {
      out.push(e)
    }
  }
  out
}

///|
/// The exploded supergraph's edges, printed in a stable order, for a test
/// that wants to READ the construction rather than count it.
pub fn ifds_exploded_text(x : Exploded) -> String {
  let parts : Array[String] = []
  for e in x.edges {
    parts.push(
      e.from_node.to_string() +
      ":" +
      e.from_fact +
      "->" +
      e.to_node.to_string() +
      ":" +
      e.to_fact,
    )
  }
  parts.sort()
  parts.join(" ")
}

///|
/// THE SUPERGRAPH MEASUREMENT: the deck's THREE edges for each procedure call
/// (p.63-65), counted over the tree's own `Icfg`.
///
/// AND IT IS A MEASUREMENT AND NOT AN ASSERTION, because the three edges are
/// what chapter 5's construction is built on: a supergraph that had grown a
/// fourth edge kind would change what an exploded supergraph MEANS, and the
/// only way to know is to count.
pub fn ifds_supergraph_text(g : Icfg) -> String {
  let mut n_to_ret = 0
  let mut n_call = 0
  let mut n_c2r = 0
  let mut v = 0
  while v < g.labels.length() {
    for lab in g.labels[v] {
      match lab {
        CallToReturn(_) => n_c2r = n_c2r + 1
        Call(_, _) => n_call = n_call + 1
        Ret(_, _) => n_to_ret = n_to_ret + 1
        Normal => ()
      }
    }
    v = v + 1
  }
  "call sites=" +
  g.call_sites.length().to_string() +
  "  CallToReturn=" +
  n_c2r.to_string() +
  "  Call=" +
  n_call.to_string() +
  "  Ret=" +
  n_to_ret.to_string()
}

///|
/// The deck's supergraph, node by node: one line per call site, saying which
/// of the three edges the tree's `Icfg` actually carries.
///
/// AND A CALL SITE IS REPORTED WITH ITS THREE EDGES OR WITH WHAT IS MISSING,
/// because a per-call-site answer is what a reader can check and a total is
/// only what a counter can check.
pub fn ifds_supergraph_calls(g : Icfg) -> Array[String] {
  let out : Array[String] = []
  for cs in g.call_sites {
    let mut has_c2r = false
    let mut has_call = false
    for lab in g.labels[cs.node] {
      match lab {
        CallToReturn(_) => has_c2r = true
        Call(_, _) => has_call = true
        Ret(_, _) => ()
        Normal => ()
      }
    }
    // THE THIRD EDGE LEAVES THE CALLEE, not the call node, so it is NOT here:
    // the deck's "interprocedural exit-to-return-site edge from ep of the
    // called procedure to Retp" (p.65) starts at the callee's exit. It is
    // measured by `ifds_supergraph_returns`.
    // AND THE SEPARATOR IS A `+` AND NOT A SPACE, because "CallToReturn"
    // CONTAINS the substring "Ret": a space-separated list would make a test
    // for "Ret" match the first edge, and the test would be measuring the
    // wrong thing without looking wrong.
    //
    // AND THE `if`s ARE STATEMENTS AND NOT EXPRESSIONS, and that is the house
    // rule rather than a style choice: an `if` used as a VALUE is outside the
    // analysed subset, so the analyzer reports it -- and the self-scan's
    // `if expression` row went 100 -> 102 with this file, which is how the
    // two were found. A false positive is FIXED and never pinned, so the
    // conditionals are statements here.
    let mut bits = ""
    if has_c2r {
      bits = bits + "CallToReturn"
    } else {
      bits = bits + "NO-CallToReturn"
    }
    if has_call {
      bits = bits + "+Call"
    } else {
      bits = bits + "+NO-Call"
    }
    out.push("call@" + cs.node.to_string() + " -> " + bits)
  }
  out
}

///|
/// The deck's THIRD edge per procedure call -- the interprocedural
/// exit-to-return-site edge (p.65) -- one line per edge, saying where it
/// leaves from and where it arrives.
///
/// AND IT IS COUNTED SEPARATELY and not folded into the call site's line,
/// because it is a different edge in a different place: it leaves the CALLEE'S
/// EXIT and arrives at the CALL'S RETURN SITE, so a reader who looks for it
/// on the call node will not find it and should not conclude it is missing.
pub fn ifds_supergraph_returns(g : Icfg) -> Array[String] {
  let out : Array[String] = []
  let mut v = 0
  while v < g.labels.length() {
    let mut s = 0
    while s < g.succ[v].length() {
      match g.labels[v][s] {
        Ret(_, _) =>
          out.push("Ret " + v.to_string() + " -> " + g.succ[v][s].to_string())
        _ => ()
      }
      s = s + 1
    }
    v = v + 1
  }
  out
}
