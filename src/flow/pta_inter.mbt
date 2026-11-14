// 0580: THE INTERPROCEDURAL POINTER ANALYSIS, AND THE CALL GRAPH BUILT ON THE FLY.
//
// THE DECK'S OWN CLAIM (p.114-115) is that the two analyses are MUTUALLY DEPENDENT:
//
//     "Inter-procedural pointer analysis requires call graph construction"   (p.114)
//     "Run together with call graph construction"                            (p.115)
//     "Call graph forms a 'reachable world'"                                 (p.115)
//
// AND ITS ALGORITHM (p.116-125) is THREE PIECES, and this module has all three:
//
//     Solve(main)          WL=[], PFG={}, S={}, RM={}, CG={};  AddReachable(main);
//                          then the loop, with ProcessCall(x, o_i) inside it
//     AddReachable(m)      THE REACHABLE WORLD: m's statements join S, m's
//                          allocations join the work list, m's assignments become
//                          the static PFG edges
//     ProcessCall(x, o_i)  THE CALL RULE: m = Dispatch(o_i, k); the receiver goes
//                          to m's `this`; the call graph edge l -> m is added; the
//                          ARGUMENTS go to the PARAMETERS (a_j -> m_pj) and the
//                          RESULT comes back (m_ret -> r)
//
// AND THE OUTPUT IS TWO THINGS (p.125): "Points-to Relations (pt)" AND "Call Graph
// (CG)". This module returns both, and the call graph is the one the analysis BUILT
// -- not one that was built before it.
//
// WHAT IS DIFFERENT FROM `callgraph.mbt`'s OWN GRAPH, and it is the deck's point:
//
//   * the GRAPH is built DURING the pointer analysis, so a method is in it because
//     the analysis REACHED it, and the reachable world grows as the analysis
//     discovers objects;
//   * the DISPATCH is on the RECEIVER'S OBJECT -- the deck's Dispatch(o_i, k) --
//     and not on the receiver's DECLARED type.
//
// THE SECOND POINT IS THE DECK'S OWN EXAMPLE'S SUBJECT. p.126 prints
//
//     1 class A {
//     2 static void main() {
//     3   A a = new A();
//     4   A b = new B();
//     5   A c = b.foo(a);
//     6 }
//     7 A foo(A x) { ... }
//     8 }
//     9 class B extends A {
//     10  A foo(A y) {
//     11    A r = new A();
//     12    return r;
//     13  }
//     14 }
//
// and `A b = new B()` DECLARES `b` as an `A` and ALLOCATES a `B`. So the
// declared-type dispatch and the object dispatch DISAGREE, and the deck's answer is
// the object one: the call goes to B.foo. Both readings are built here, and the
// difference between them is measured.
//
// THE BOUNDARY, WHICH IS COUNTED AND NOT HIDDEN. This tree's AST has no method
// bodies: the parser reads past `impl`, `trait`, `struct` and `enum` declarations
// whole (`callgraph.mbt` says so). So a METHOD target is an edge and not a source of
// statements, and the number of such targets is counted. The deck's `m.ret`, the
// method's return value, is a node of a method this tree cannot read, so the RESULT
// edge points at a node nothing writes to -- the edge is the deck's, and the empty
// node is the truth about this tree.
//
// AND ONE EXTENSION, WHICH IS THIS TREE'S AND NOT THE DECK'S. The deck's
// ProcessCall(x, o_i) is driven by a RECEIVER OBJECT, so every call in the deck's
// languages has one. This tree's functions are TOP-LEVEL, and a call to one of them
// has no receiver -- so a call with no receiver is processed ONCE, when its caller
// becomes reachable. The rule is the same rule; only the trigger differs.

///|
/// The PFG node of a VARIABLE: "<method>|<variable>".
///
/// THE METHOD IS PART OF THE NAME, because the deck's PFG is ONE graph over the
/// whole reachable world (p.116: one PFG, one S, one RM) and two methods may both
/// have a variable called `x`. The deck's languages give a method its own scope,
/// so the deck never has to say it; this tree has to.
fn pi_var(fname : String, v : String) -> String {
  fname + "|" + v
}

///|
/// The PFG node of an INSTANCE FIELD: "<object>.<field>" -- the deck's own `o_i.f`,
/// and the node the deck's picture draws in BLUE (p.24-25).
fn pi_field(obj : String, f : String) -> String {
  obj + "." + f
}

///|
/// One event of the work list.
///
/// THE POINTER EVENT is the deck's WL entry (p.46: "each worklist entry n, pts is a
/// pair of pointer n and points-to set pts"). THE CALL EVENT is this tree's
/// extension: the deck's ProcessCall is a procedure the loop CALLS, and a call
/// that has no receiver object has nothing to be called with.
priv enum InterEvent {
  /// The node, and the points-to set to propagate to it.
  Ptr(String, Map[String, Bool])
  /// The caller, the index of the call site among the caller's sites, and the
  /// receiver OBJECT ("" when the call has no receiver).
  Call(String, Int32, String)
}

///|
/// The READ-ONLY inputs of the analysis.
priv struct InterCtx {
  fns : Array[CgFn]
  cfgs : Array[Cfg]
  sites : Map[String, String]
  index_of : Map[String, Int32]
  tab : TraitTable
  obj_types : Map[String, String]
  /// method -> its call sites, cached.
  sites_of : Map[String, Array[CgCall]]
}

///|
/// The state the analysis grows. EVERY FIELD IS A REFERENCE, so a helper that
/// takes the state mutates the caller's state -- which is why the counters are
/// returned by the helpers instead of being fields here.
priv struct InterState {
  /// The reachable methods, in the order they were reached: the deck's RM.
  rm : Array[String]
  rm_set : Map[String, Bool]
  /// The call graph, built on the fly: the deck's CG.
  edges : Array[CgEdge]
  edge_set : Map[String, Bool]
  /// The pointer flow graph.
  graph : Pfg
  /// The work list.
  wl : Array[InterEvent]
  /// The points-to relations.
  pt : Map[String, Map[String, Bool]]
  /// The work list's pointer events, in order.
  trace : Array[String]
}

///|
/// The TYPE of every object this program's allocation sites create.
///
/// THE OBJECT'S TYPE IS WHAT THE DISPATCH RESOLVES ON, and it is here because the
/// allocation site knows it: the allocation's type is the `EStruct`'s name.
fn pi_object_types(
  cfgs : Array[Cfg],
  sites : Map[String, String],
) -> Map[String, String] {
  let out : Map[String, String] = Map([])
  let mut fi = 0
  while fi < cfgs.length() {
    let g = cfgs[fi]
    let mut v = 0
    while v < g.kinds.length() {
      match pta_alloc_of(g.kinds[v]) {
        Some(_) =>
          out.set(pta_site_of(sites, fi, v), pta_alloc_type(g.kinds[v]))
        None => ()
      }
      v = v + 1
    }
    fi = fi + 1
  }
  out
}

///|
/// The call sites of a method, cached.
fn pi_sites_of(ctx : InterCtx, m : String) -> Array[CgCall] {
  match ctx.sites_of.get(m) {
    Some(ss) => ss
    None => {
      let ss = match ctx.index_of.get(m) {
        Some(fi) => call_sites_of(ctx.fns[fi])
        None => []
      }
      ctx.sites_of.set(m, ss)
      ss
    }
  }
}

///|
/// The deck's `Dispatch(o_i, k)` -- the method a call on the OBJECT `o` reaches.
///
/// THE OBJECT, NOT THE RECEIVER'S DECLARED TYPE, and that is the deck's own
/// example's subject (p.126: `A b = new B()`).
///
/// THE DISPATCH ITSELF IS THE TREE'S OWN (`resolve_call`), run on the object's
/// type: a second implementation of "which method does this call reach" would be a
/// second definition of dispatch, and the deck's two would then disagree.

///|
/// The deck's AddEdge (p.68, p.119) IN FULL -- and the second half is the half
/// that makes it work:
///
///     AddEdge(s, t)
///     if s -> t is not in PFG then
///        add s -> t to PFG
///        if pts(s) is not empty then
///           add t, pts(s) to WL
///
/// THE SECOND HALF IS NOT AN OPTIMISATION. An edge added after its source has
/// already been propagated carries nothing, so the objects the source holds would
/// never reach the target -- and the CALL RULE is exactly that case: the edge
/// "a_j -> m_pj" is added when the call graph edge is new, which is AFTER the
/// argument was propagated. Without this half the callee's parameter would stay
/// empty while the argument held everything.
///
/// TRUE when the edge was new.
fn pi_add_edge(st : InterState, from : String, to : String) -> Bool {
  if pfg_add_edge(st.graph, from, to) {
    let src = match st.pt.get(from) {
      Some(v) => v
      None => name_set_empty()
    }
    if src.length() > 0 {
      st.wl.push(InterEvent::Ptr(to, src))
    }
    true
  } else {
    false
  }
}

///|
fn pi_dispatch(ctx : InterCtx, site : CgCall, obj : String) -> Array[String] {
  match site.kind {
    Static => [site.name]
    Special => [site.name]
    Virtual => {
      if obj == "" {
        return []
      }
      let otype = match ctx.obj_types.get(obj) {
        Some(t) => t
        None => return []
      }
      let declared : Map[String, String] = Map([])
      declared.set(site.receiver, otype)
      resolve_call(site, declared, ctx.tab)
    }
  }
}

///|
/// The deck's AddReachable(m) (p.116-119): expand the "reachable world".
///
///     if m is not in RM then
///        add m to RM
///        S = S union SS_m
///        foreach i: x = new T() in SS_m do add x, {o_i} to WL
///        foreach x = y in SS_m do AddEdge(y, x)
///
/// THE RETURN IS ALSO ADDED, because the deck's call rule needs the callee's
/// result (p.121: `o_v in pt(m.ret)`) and this tree's name for it is the method's
/// "result" node -- the same name `pta_ctx.mbt` uses.
///
/// THE CALLS WITH NO RECEIVER ARE QUEUED HERE, because the deck's ProcessCall is
/// driven by a receiver object and a call to a top-level function has none.
fn pi_add_reachable(ctx : InterCtx, st : InterState, m : String) -> Int32 {
  if st.rm_set.contains(m) {
    return 0
  }
  st.rm_set.set(m, true)
  st.rm.push(m)
  let fi = match ctx.index_of.get(m) {
    Some(x) => x
    None => return 0
  }
  let g = ctx.cfgs[fi]
  let mut n = 0
  // THE NEW STATEMENTS, and the allocations among them.
  for v in g.source_order() {
    n = n + 1
    match pta_alloc_of(g.kinds[v]) {
      Some(_) => {
        let obj = pta_site_of(ctx.sites, fi, v)
        let bound = pta_bound_name(g.kinds[v])
        st.wl.push(InterEvent::Ptr(pi_var(m, bound), pfg_set_one(obj)))
      }
      None => ()
    }
  }
  // THE STATIC EDGES.
  for pair in pfg_assign_edges(g) {
    let _ = pi_add_edge(st, pi_var(m, pair.0), pi_var(m, pair.1))
  }
  // THE RESULT.
  for e in cs_result_exprs(ctx.fns[fi]) {
    match e.kind {
      @ast.EName(v) => {
        let _ = pi_add_edge(st, pi_var(m, v), pi_var(m, "result"))
      }
      _ => ()
    }
  }
  // THE CALLS WITH NO RECEIVER.
  let sites = pi_sites_of(ctx, m)
  let mut s = 0
  while s < sites.length() {
    if sites[s].kind != Virtual {
      st.wl.push(InterEvent::Call(m, s, ""))
    }
    s = s + 1
  }
  n
}

///|
/// The deck's ProcessCall(x, o_i) (p.116, p.121-124).
///
///     foreach l: r = x.k(a1,...,an) in S do
///        m = Dispatch(o_i, k)
///        add m_this, {o_i} to WL
///        if l -> m is not in CG then
///           add l -> m to CG
///           AddReachable(m)
///           foreach parameter p_i of m do AddEdge(a_i, p_i)
///           AddEdge(m_ret, r)
///
/// IT RETURNS THE COUNTS IT PRODUCED -- (no_body, unresolved, analyzed) -- because
/// the state a helper grows is a set of references and the counters are not.
fn pi_process_call(
  ctx : InterCtx,
  st : InterState,
  caller : String,
  site : CgCall,
  obj : String,
) -> (Int32, Int32, Int32) {
  let targets = pi_dispatch(ctx, site, obj)
  if targets.length() == 0 {
    // A CALL THAT REACHES NOTHING. Counted once per (caller, site, object).
    return (0, 1, 0)
  }
  let mut no_body = 0
  let mut analyzed = 0
  let mut t = 0
  while t < targets.length() {
    let callee = targets[t]
    // THE RECEIVER: the deck's "add m_this, {o_i} to WL" (p.122).
    if obj != "" {
      st.wl.push(InterEvent::Ptr(pi_var(callee, "this"), pfg_set_one(obj)))
    }
    // THE CALL GRAPH EDGE.
    let key = caller + "|" + callee
    if !st.edge_set.contains(key) {
      st.edge_set.set(key, true)
      st.edges.push({ caller, callee, })
      // THE REACHABLE WORLD.
      analyzed = analyzed + pi_add_reachable(ctx, st, callee)
      // THE PARAMETERS: the deck's "AddEdge(a_i, p_i)".
      match ctx.index_of.get(callee) {
        Some(cfi) => {
          let params = ctx.fns[cfi].params
          let mut a = 0
          while a < site.args.length() && a < params.length() {
            match site.args[a].kind {
              @ast.EName(v) => {
                let _ = pi_add_edge(
                  st,
                  pi_var(caller, v),
                  pi_var(callee, params[a].name),
                )
              }
              _ => ()
            }
            a = a + 1
          }
        }
        None =>
          // A TARGET THIS TREE HAS NO BODY FOR. The deck's method bodies are not
          // in this tree's AST, so its parameters cannot be named.
          no_body = no_body + 1
      }
      // THE RESULT: the deck's "AddEdge(m_ret, r)".
      if site.lhs != "" {
        let _ = pi_add_edge(
          st,
          pi_var(callee, "result"),
          pi_var(caller, site.lhs),
        )
      }
    }
    t = t + 1
  }
  (no_body, 0, analyzed)
}

///|
/// One pointer event of the work list: the deck's loop body over a pointer.
///
/// IT RETURNS (propagated, skipped, no_body, unresolved, analyzed).
fn pi_pointer_event(
  ctx : InterCtx,
  st : InterState,
  node : String,
  pts : Map[String, Bool],
) -> (Int32, Int32, Int32, Int32, Int32) {
  let cur = match st.pt.get(node) {
    Some(v) => v
    None => name_set_empty()
  }
  // Delta = pts - pt(n). AN EMPTY DELTA DOES NOTHING AT ALL: the deck's
  // differential propagation (p.58-65).
  let delta = name_set_subtract(pts, cur)
  if delta.length() == 0 {
    return (1, 1, 0, 0, 0)
  }
  // Propagate(n, Delta): pt(n) |= Delta, and the DELTA goes to n's successors.
  st.pt.set(node, name_set_union(cur, delta))
  for _, s in pfg_succ(st.graph, node) {
    st.wl.push(InterEvent::Ptr(s, delta))
  }
  // THE VARIABLE RULES, and only for a VARIABLE node.
  let (fname, vname) = pta_ctx_split(node)
  if vname == "" {
    return (1, 0, 0, 0, 0)
  }
  let fi = match ctx.index_of.get(fname) {
    Some(x) => x
    None => return (1, 0, 0, 0, 0)
  }
  let g = ctx.cfgs[fi]
  // THE STORE AND LOAD EDGES, for each NEW object at the variable.
  for o, _ in delta {
    for triple in pfg_stores(g) {
      if triple.0 == vname {
        let _ = pi_add_edge(st, pi_var(fname, triple.2), pi_field(o, triple.1))
      }
    }
    for triple in pfg_loads(g) {
      if triple.0 == vname {
        let _ = pi_add_edge(st, pi_field(o, triple.1), pi_var(fname, triple.2))
      }
    }
  }
  // THE CALLS: the deck's ProcessCall(x, o_i), once per receiver object.
  let sites = pi_sites_of(ctx, fname)
  let mut s = 0
  while s < sites.length() {
    if sites[s].kind == Virtual && sites[s].receiver == vname {
      for o, _ in delta {
        st.wl.push(InterEvent::Call(fname, s, o))
      }
    }
    s = s + 1
  }
  (1, 0, 0, 0, 0)
}

///|
/// What one interprocedural run produced.
pub(all) struct PtaInterResult {
  /// The pointer flow graph over the reachable world.
  graph : Pfg
  /// The points-to relations: node -> the objects it may point to.
  pts : Map[String, Map[String, Bool]]
  /// The call graph, BUILT ON THE FLY.
  edges : Array[CgEdge]
  /// The reachable methods, in the order they were reached: the deck's RM.
  reachable : Array[String]
  /// The work list's pointer events, in order.
  trace : Array[String]
  /// how many work list entries were taken OFF the list.
  propagated : Int32
  /// how many of those had an EMPTY delta, and did nothing.
  skipped : Int32
  /// the call targets this tree has NO BODY for.
  no_body : Int32
  /// the calls that reached no target at all.
  unresolved : Int32
  /// the statements of the reachable methods that were analyzed: the deck's |S|.
  analyzed : Int32
}

///|
/// The INTERPROCEDURAL POINTER ANALYSIS, with the call graph built on the fly.
///
/// THE DECK'S Solve(main) (p.116, p.125), over the pointer flow graph of 0579 and
/// with the delta discipline of the deck's §3.
pub fn pta_inter_run(
  main : String,
  fns : Array[CgFn],
  tab : TraitTable,
) -> PtaInterResult {
  let cfgs : Array[Cfg] = []
  let mut i = 0
  while i < fns.length() {
    cfgs.push(cfg_of(fns[i].body))
    i = i + 1
  }
  let sites = pta_site_names(cfgs)
  let index_of : Map[String, Int32] = Map([])
  i = 0
  while i < fns.length() {
    if !index_of.contains(fns[i].name) {
      index_of.set(fns[i].name, i)
    }
    i = i + 1
  }
  let ctx : InterCtx = {
    fns,
    cfgs,
    sites,
    index_of,
    tab,
    obj_types: pi_object_types(cfgs, sites),
    sites_of: Map([]),
  }
  let st : InterState = {
    rm: [],
    rm_set: Map([]),
    edges: [],
    edge_set: Map([]),
    graph: pfg_new(),
    wl: [],
    pt: Map([]),
    trace: [],
  }
  let mut propagated = 0
  let mut skipped = 0
  let mut no_body = 0
  let mut unresolved = 0
  let mut analyzed = 0
  // THE ENTRY: AddReachable(main).
  analyzed = analyzed + pi_add_reachable(ctx, st, main)
  let mut head = 0
  while head < st.wl.length() {
    let ev = st.wl[head]
    head = head + 1
    let (p, s, nb, un, a) = match ev {
      InterEvent::Ptr(node, pts) => {
        st.trace.push(pi_entry_text(node, pts))
        pi_pointer_event(ctx, st, node, pts)
      }
      InterEvent::Call(caller, si, obj) => {
        let sites = pi_sites_of(ctx, caller)
        if si >= sites.length() {
          (0, 0, 0, 0, 0)
        } else {
          let (nb, un, a) = pi_process_call(ctx, st, caller, sites[si], obj)
          (0, 0, nb, un, a)
        }
      }
    }
    propagated = propagated + p
    skipped = skipped + s
    no_body = no_body + nb
    unresolved = unresolved + un
    analyzed = analyzed + a
  }
  {
    graph: st.graph,
    pts: st.pt,
    edges: st.edges,
    reachable: st.rm,
    trace: st.trace,
    propagated,
    skipped,
    no_body,
    unresolved,
    analyzed,
  }
}

///|
/// One worklist entry, in the deck's own notation (p.75: `<c, {o3}>`).
fn pi_entry_text(node : String, pts : Map[String, Bool]) -> String {
  let objs : Array[String] = []
  for o, _ in pts {
    objs.push(o)
  }
  objs.sort()
  node + ", {" + objs.join(",") + "}"
}

///|
/// The points-to relations, printed the way `pta_text` prints them.
pub fn pta_inter_text(res : PtaInterResult) -> String {
  pfg_pts_map_text(res.pts)
}

///|
/// The call graph, printed one edge per line.
pub fn pta_inter_cg_text(res : PtaInterResult) -> String {
  let lines : Array[String] = []
  for e in res.edges {
    lines.push(e.caller + " -> " + e.callee)
  }
  lines.sort()
  lines.join("; ")
}
