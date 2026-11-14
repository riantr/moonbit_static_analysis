// 0579: THE POINTER FLOW GRAPH -- the data structure deck 9-10 puts at the centre
// of its second and third sections, and the DIFFERENTIAL PROPAGATION of its §3.
//
// THE DECK'S OWN CONTENTS (p.3-4) are:
//
//     1. Pointer Analysis: Rules                            p.5-13
//     2. How to Implement Pointer Analysis                  p.15-41
//     3. Pointer Analysis: Algorithms                       p.43-93
//     4. Pointer Analysis in the Presence of Method Calls  p.95-153
//
// AND §2's OWN SUMMARY IS TWO LINES (p.38):
//
//     1. Build pointer flow graph (PFG)
//     2. Propagate points-to information on PFG
//
// THE PFG ITSELF (p.20): "Pointer flow graph of a program is a directed graph that
// expresses how objects flow among the pointers in the program."  A NODE IS A POINTER:
// a VARIABLE ("x") or an INSTANCE FIELD ("o1.f") -- the deck's p.24-25 legend names
// both kinds, and it draws them differently on purpose (a red circle for the variable
// node, a blue circle for the instance field node).
//
// AND THE EDGES ARE THE RULES' EDGES (p.23, and again p.49-50 and p.67-68).  One
// edge per rule consequence, and the direction is the direction the INFORMATION
// flows:
//
//     New    i: x = new T()      N/A          (the object is fresh; no edge)
//     Assign x = y               x <- y       (so y -> x)
//     Store  x.f = y             o_i.f <- y   (so y -> o_i.f, for each o_i in pts(x))
//     Load   y = x.f             y <- o_i.f   (so o_i.f -> y, for each o_i in pts(x))
//
// THE STORE AND LOAD EDGES DEPEND ON THE POINTS-TO SETS, and that is not an
// inconvenience in the deck -- it is WHY the edges are added DURING the propagation:
// p.58-66 and p.67-68 add them when a new object arrives at a variable, and p.67's
// own heading says "New points-to information may introduce new PFG edges".
//
// WHY THIS IS A SECOND READING AND NOT A REWRITE. `pta.mbt` computes the same fixed
// point over the CONTROL-flow graph, rule by rule; this module computes it over the
// POINTER-flow graph, edge by edge. The rules do not change -- the SHAPE does. And a
// second reading that is never compared with the first is a second CLAIM, so a test
// requires the two to AGREE on the deck's own program (p.81-92), and a second test
// requires the deck's own final tables (p.90-91).
//
// THE DIFFERENTIAL PROPAGATION (p.58-65) IS THE POINT OF THE WORKLIST:
//
//     "Differential propagation is employed to avoid propagation and processing of
//      redundant points-to information"
//     "existing points-to information in pts(n) have already been propagated to
//      n's successors, and no need to be propagated again"
//
// so at every step the set that is propagated is the DELTA -- `pts - pt(n)` -- and a
// step whose delta is empty does NOTHING at all. This module COUNTS the worklist
// entries it takes off, so "no redundant propagation" is a number here and not a
// promise.
//
// AND THE DELTA-ONLY READING IS THE DECK'S, MEASURED FROM THE DECK'S OWN TRACE --
// not from the summary slide, which is ambiguous. The summary (p.43-45) prints BOTH
// `Propagate(n, Δ)` AND `Propagate(n, pts)`, and then inlines the body of
// `Propagate(n, pts)` (p.57 defines it: "pt(n) ∪= pts; foreach n -> s ∈ PFG do add
// ⟨s, pts⟩ to WL"), so on that slide the two are the same operation twice. The deck's
// own WORKED TRACE decides it: p.75 prints the worklist as `[⟨c, {o3}⟩, ⟨a, {o1}⟩]`
// while `⟨b, {o1}⟩` is being processed, and p.88 prints `[⟨o3.f, {o3}⟩, ⟨e, {o1}⟩]`.
// A worklist that carried the whole set as well as the delta would hold THREE
// entries at p.75 -- `⟨c,{o3}⟩, ⟨a,{o1}⟩, ⟨a,{o1}⟩` -- and it holds TWO. So the
// deck propagates the DELTA and only the delta, and that is what this module does.
//
// THE BOUNDARY, WHICH IS COUNTED AND NOT HIDDEN. The deck's rule table is written in
// VARIABLES: `x = y`, `x.f = y`, `y = x.f`. This tree's AST can also hold an
// EXPRESSION on either side, and an expression is not a pointer the PFG can have a
// node for. A store whose right-hand side is not a plain name is therefore NOT a PFG
// edge, and the number of such stores is COUNTED. The deck's own program (p.81-92)
// has none.

///|
/// A POINTER FLOW GRAPH: nodes are pointers, edges say where the information flows.
pub(all) struct Pfg {
  /// node -> the nodes it flows TO.
  succ : Map[String, Array[String]]
  /// node -> the nodes that flow INTO it.
  pred : Map[String, Array[String]]
}

///|
/// The empty graph.
pub fn pfg_new() -> Pfg {
  Pfg::{ succ: Map([]), pred: Map([]), }
}

///|
/// A one-element set.
fn pfg_set_one(x : String) -> Map[String, Bool] {
  let out = name_set_empty()
  out.set(x, true)
  out
}

///|
/// The deck's AddEdge (p.50, p.68): "if s -> t is not in PFG then add s -> t to PFG".
///
/// TRUE when the edge was NEW. The deck's second half -- "if pts(s) is not empty then
/// add t, pts(s) to WL" -- is the WORKLIST's business and lives in the solver, because
/// an edge added without a points-to set has nothing to carry.
pub fn pfg_add_edge(g : Pfg, from : String, to : String) -> Bool {
  let out = match g.succ.get(from) {
    Some(v) => v
    None => []
  }
  for _, e in out {
    if e == to {
      return false
    }
  }
  out.push(to)
  g.succ.set(from, out)
  let back = match g.pred.get(to) {
    Some(v) => v
    None => []
  }
  back.push(from)
  g.pred.set(to, back)
  true
}

///|
/// The successors of a node; empty when it has none.
pub fn pfg_succ(g : Pfg, node : String) -> Array[String] {
  match g.succ.get(node) {
    Some(v) => v
    None => []
  }
}

///|
/// The graph, drawn: one line per edge, in the toolchain's shortlex order.
///
/// THE ORDER IS THE STDLIB'S, for the reason `pta_text` gives: "a dump whose only job
/// is to be asserted against would then carry a second, private idea of what 'sorted'
/// means". So a reader should compare the ENTRIES and not their order.
pub fn pfg_text(g : Pfg) -> String {
  let lines : Array[String] = []
  for from, _ in g.succ {
    for _, to in pfg_succ(g, from) {
      lines.push(from + " -> " + to)
    }
  }
  lines.sort()
  lines.join("; ")
}

///|
/// The RESULT of the deck's Solve: the graph, the points-to sets, the counts that
/// make the differential propagation measurable, and the deck's own TRACE.
pub(all) struct PfgResult {
  /// the graph, with the edges the deck's rules add.
  graph : Pfg
  /// node -> the objects it may point to.
  pts : Map[String, Map[String, Bool]]
  /// how many (node, points-to set) pairs were taken OFF the work list.
  propagated : Int32
  /// how many of those steps had an EMPTY delta, and did nothing.
  skipped : Int32
  /// the stores whose right-hand side is not a plain name -- the boundary above.
  expr_stores : Int32
  /// the worklist entries, in the order they were taken off -- the deck's own trace
  /// (p.74-91), which this module reproduces entry for entry.
  trace : Array[String]
}

///|
/// One worklist entry, in the deck's own notation (p.75: `⟨c, {o3}⟩`).
fn pfg_entry_text(node : String, pts : Map[String, Bool]) -> String {
  let objs : Array[String] = []
  for o, _ in pts {
    objs.push(o)
  }
  objs.sort()
  node + ", {" + objs.join(",") + "}"
}

///|
/// The trace, one line per step: "b, {o1}; c, {o3}; ...".
pub fn pfg_trace_text(res : PfgResult) -> String {
  res.trace.join("; ")
}

///|
/// The points-to sets of a result, printed the way the deck prints `pt(n)` (p.90-91).
pub fn pfg_pts_text(res : PfgResult) -> String {
  pfg_pts_map_text(res.pts)
}

///|
/// A points-to MAP, printed the way the deck prints `pt(n)` (p.90-91).
///
/// IT IS THE ONE FORMATTER, because 0580's interprocedural reading prints its
/// relations the same way and a second formatter would be a second idea of what
/// the deck's `pt(n)` looks like.
pub fn pfg_pts_map_text(pts : Map[String, Map[String, Bool]]) -> String {
  let keys : Array[String] = []
  for k, _ in pts {
    let s = match pts.get(k) {
      Some(v) => v
      None => name_set_empty()
    }
    if s.length() > 0 {
      keys.push(k)
    }
  }
  keys.sort()
  let parts : Array[String] = []
  for k in keys {
    let objs : Array[String] = []
    let s = match pts.get(k) {
      Some(v) => v
      None => name_set_empty()
    }
    for o, _ in s {
      objs.push(o)
    }
    objs.sort()
    parts.push(k + " -> {" + objs.join(",") + "}")
  }
  parts.join("; ")
}

///|
/// The deck's `x = y` statements, as (y, x) pairs -- the ASSIGN edges (p.47).
fn pfg_assign_edges(g : Cfg) -> Array[(String, String)] {
  let out : Array[(String, String)] = []
  for v in g.source_order() {
    match g.kinds[v] {
      Assign(x, e) =>
        match e.kind {
          @ast.EName(y) => out.push((y, x))
          _ => ()
        }
      Store(x, e) =>
        match e.kind {
          @ast.EName(y) => out.push((y, x))
          _ => ()
        }
      AssignMulti(names, e) =>
        match e.kind {
          @ast.EName(y) =>
            for n in names {
              out.push((y, n))
            }
          _ => ()
        }
      _ => ()
    }
  }
  out
}

///|
/// The deck's `x.f = y` statements, as (x, f, y) triples -- the STORE edges.
fn pfg_stores(g : Cfg) -> Array[(String, String, String)] {
  let out : Array[(String, String, String)] = []
  for v in g.source_order() {
    match g.kinds[v] {
      PlaceStore(target, e) =>
        match target.kind {
          @ast.EField(b, fld) =>
            match b.kind {
              @ast.EName(x) =>
                match e.kind {
                  @ast.EName(y) => out.push((x, fld, y))
                  _ => ()
                }
              _ => ()
            }
          _ => ()
        }
      _ => ()
    }
  }
  out
}

///|
/// The deck's `y = x.f` statements, as (x, f, y) triples -- the LOAD edges.
fn pfg_loads(g : Cfg) -> Array[(String, String, String)] {
  let out : Array[(String, String, String)] = []
  for v in g.source_order() {
    match g.kinds[v] {
      Assign(y, e) | Store(y, e) =>
        match e.kind {
          @ast.EField(b, fld) =>
            match b.kind {
              @ast.EName(x) => out.push((x, fld, y))
              _ => ()
            }
          _ => ()
        }
      _ => ()
    }
  }
  out
}

///|
/// The deck's `x.f = <expression>` statements -- the ones with NO PFG edge, because
/// an expression is not a pointer the graph can have a node for. COUNTED, not hidden.
fn pfg_expr_stores(g : Cfg) -> Int32 {
  let mut n = 0
  for v in g.source_order() {
    match g.kinds[v] {
      PlaceStore(target, e) =>
        match target.kind {
          @ast.EField(b, _) =>
            match b.kind {
              @ast.EName(_) =>
                match e.kind {
                  @ast.EName(_) => ()
                  _ => n = n + 1
                }
              _ => ()
            }
          _ => ()
        }
      _ => ()
    }
  }
  n
}

///|
/// The deck's Solve(SS) for ONE method (p.47, p.67-68, p.74-91), over the PFG.
///
/// THE ALGORITHM IS THE DECK'S, LINE BY LINE (p.55-57 gives `Propagate` and
/// `AddEdge`; p.66-68 give the four rules; p.74-91 walk the deck's own example):
///
///     WL = [], PFG = {}
///     foreach i: x = new T() in SS do add x, {o_i} to WL
///     foreach x = y in SS do AddEdge(y, x)
///     while WL is not empty do
///        remove n, pts from WL
///        Delta = pts - pt(n)
///        Propagate(n, Delta)
///        if n represents a variable x then
///           foreach o_i in Delta do
///              foreach x.f = y in SS do AddEdge(y, o_i.f)
///              foreach y = x.f in SS do AddEdge(o_i.f, y)
///
/// AND `Propagate(n, pts)` (p.57) IS
///
///     if pts is not empty then
///        pt(n) ∪= pts
///        foreach n -> s in PFG do add s, pts to WL
///
/// WITH `pts` REPLACED BY THE DELTA -- which is the deck's §3 (p.58-65), and which
/// the deck's own worklist trace (p.75, p.88) confirms: those slides print TWO
/// entries where a delta-and-whole-set worklist would print three. See the header.
///
/// AND THE WORKLIST IS A QUEUE, because the deck says "remove n, pts from WL" without
/// saying which end -- and the deck's own trace decides it: p.75 shows `⟨c, {o3}⟩`
/// still at the HEAD with `⟨a, {o1}⟩` behind it, so the worklist is a QUEUE. The
/// fixed point does not depend on the order; the TRACE does.
///
/// AND THE STATEMENTS ARE READ IN SOURCE ORDER, because the deck's `∈ SS` means the
/// statement list as it was written.  This tree's `cfg_of` allocates nodes BACK TO
/// FRONT, so the node index is not the source order, and `Cfg::source_order` is the
/// one place that knows the difference.
pub fn pfg_solve(g : Cfg, sites : Map[String, String]) -> PfgResult {
  let graph = pfg_new()
  let pt : Map[String, Map[String, Bool]] = Map([])
  let wl : Array[(String, Map[String, Bool])] = []
  let trace : Array[String] = []
  let mut head = 0
  let mut propagated = 0
  let mut skipped = 0

  // --- the deck's INITIALIZATION (p.47, p.55) -------------------------------
  // New: every allocation site puts its object into the variable it binds.
  //
  // THE STATEMENTS ARE TAKEN IN SOURCE ORDER, and that is not a detail: the deck
  // says "foreach i: x = new T() ∈ SS do add x, {o_i} to WL", and SS is the
  // statement list in the order it was written, so the worklist is seeded in that
  // order.  This tree's `cfg_of` allocates its nodes BACK TO FRONT (`cfg.mbt` says
  // so: "kinds[0] is usually the exit node"), so the node index is NOT the source
  // order -- and seeding the worklist in node order would put the deck's `c` before
  // its `b` and produce a different trace for the same program.
  for v in g.source_order() {
    if pta_alloc_of(g.kinds[v]) is Some(_) {
      let obj = pta_site_of(sites, 0, v)
      wl.push((pta_bound_name(g.kinds[v]), pfg_set_one(obj)))
    }
  }
  // Assign: the static edges.
  for pair in pfg_assign_edges(g) {
    let _ = pfg_add_edge(graph, pair.0, pair.1)
  }
  let stores = pfg_stores(g)
  let loads = pfg_loads(g)
  let expr_stores = pfg_expr_stores(g)

  // --- the deck's LOOP (p.47, p.74-91) --------------------------------------
  while head < wl.length() {
    let node = wl[head].0
    let pts = wl[head].1
    head = head + 1
    propagated = propagated + 1
    trace.push(pfg_entry_text(node, pts))
    let cur = match pt.get(node) {
      Some(v) => v
      None => name_set_empty()
    }
    // Delta = pts - pt(n).  AN EMPTY DELTA DOES NOTHING AT ALL, and that is the
    // deck's differential propagation (p.58-65).
    let delta = name_set_subtract(pts, cur)
    if delta.length() == 0 {
      skipped = skipped + 1
      continue
    }
    // Propagate(n, Delta): pt(n) |= Delta, and the DELTA goes to n's successors.
    pt.set(node, name_set_union(cur, delta))
    for _, s in pfg_succ(graph, node) {
      wl.push((s, delta))
    }
    // The dynamic edges: a new object at a variable can create new edges.
    for o, _ in delta {
      for triple in stores {
        if triple.0 == node {
          let fld = o + "." + triple.1
          if pfg_add_edge(graph, triple.2, fld) {
            let src = match pt.get(triple.2) {
              Some(v) => v
              None => name_set_empty()
            }
            if src.length() > 0 {
              wl.push((fld, src))
            }
          }
        }
      }
      for triple in loads {
        if triple.0 == node {
          let fld = o + "." + triple.1
          if pfg_add_edge(graph, fld, triple.2) {
            let src = match pt.get(fld) {
              Some(v) => v
              None => name_set_empty()
            }
            if src.length() > 0 {
              wl.push((triple.2, src))
            }
          }
        }
      }
    }
  }
  PfgResult::{ graph, pts: pt, propagated, skipped, expr_stores, trace, }
}
