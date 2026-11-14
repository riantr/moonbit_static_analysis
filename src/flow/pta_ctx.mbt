// 0575: POINTER ANALYSIS WITH CONTEXTS -- deck 8_PTA p.49-53, and the lecture
// that answers it.
//
// THE DECK. `Pointer Analysis` (Tian Tan, Nanjing University, 2021) spends p.49-53
// on ONE of its four factors:
//
//   p.49   "How to model calling contexts?"
//          CONTEXT-SENSITIVE    "Distinguish different calling contexts of a
//                               method"  /  "Analyze each method multiple times,
//                               once for each context"
//          CONTEXT-INSENSITIVE  "Merge all calling contexts of a method"  /
//                               "Analyze each method once"
//   p.53   "We start with this" -- THE MARK IS ON THE CONTEXT-INSENSITIVE COLUMN,
//          and the slide's own note says "Very useful technique / Significantly
//          improve precision / More details in later lectures".
//
// So the factor is a CHOICE, and the course's choice is the one this tree already
// implements: one map per function (`pta.mbt`'s header, which reads the deck's
// p.55 and the deck's p.96 together). What is MISSING is the other column -- the
// analysis that analyses a method ONCE PER CALLING CONTEXT.
//
// THE CLIENT, AND IT IS A SEPARATE DECK. The "later lectures" p.53 points at are
// `Pointer Analysis -- Context Sensitivity (I)` (Tian Tan, 2021), 178 pages, and
// it is the deck that DEFINES the machinery:
//
//   p.60-66  THE RULES, PARAMETERISED BY A CONTEXT `c`. Every rule of deck 8's
//            p.97-98 is the same rule with a context in front of it:
//              New    c: o_i in pt(c: x)
//              Assign c: o_i in pt(c: y)  ->  c: o_i in pt(c: x)
//              Store  c: o_i in pt(c: x), c: o_j in pt(c: y)
//                      ->  c: o_j in pt(c: o_i.f)
//              Load   c: o_i in pt(c: x), c: o_j in pt(c: o_i.f)
//                      ->  c: o_j in pt(c: y)
//   p.67-71  THE CALL RULE -- the one deck 8 p.96 says it withholds ("will come
//            back to this in pointer analysis with method calls"):
//              "l: r = x.k(a1,...,an)"
//              "c: o_i in pt(c: x), m = Dispatch o_i, k, c' = Select(c, l, c: o_i)"
//              "c': o_u in pt(c': a_j)   ->  c': o_v in pt(c': m.p_j)"
//              "c:  o_i in pt(c': m.t)   ->  c:  o_u in pt(c: r)"
//            and the two definitions that matter:
//              "Dispatch o_i, k: resolves the virtual dispatch of k on o_i to a
//               target method (based on type of o_i)"
//              "Select(c, l, c': o_i): selects context for target method m, based
//               on the information available at call site l"
//   p.99-115 THE CONTEXT ABSTRACTION FUNCTIONS -- the three variants and the
//            k-limiting:
//              p.100     OBJECT SENSITIVITY: "Select(c, l, c': o_i)" -- the
//                        receiver object, "with heap context"
//              p.102     CONTEXT INSENSITIVITY: "Select _, _, _ = [ ]", and the
//                        slide says it "Can be seen as a special case of context
//                        sensitivity"
//              p.103     CALL-SITE SENSITIVITY: "Select(c, l, _) = [l_1, ..., l_k]"
//                        -- "Each context consists of a list of call sites (call
//                        chain)"; "At a method call, append the call site to the
//                        caller context as callee context"; "Also called
//                        call-string sensitivity, or k-CFA"; cited to Olin
//                        Shivers, 1991
//              p.110-111 k-LIMITING: "set an upper bound for length of contexts,
//                        denoted by k"; "For call-site sensitivity, each context
//                        consists of the last k call sites of the call chains";
//                        "In practice, k is a small number"
//              p.112-115 1-CFA: "Select _, l, _ = [ l ]", over the worked example
//                        of p.104-115.
//
// THE EXAMPLE BOTH DECKS SHARE. 11-12 p.3-6 is the whole reason the factor
// exists:
//
//     void main() {
//       Number n1, n2, x, y;
//       n1 = new One();     // o1
//       n2 = new Two();     // o2
//       x = id(n1);
//       y = id(n2);
//       int i = x.get();
//     }
//     Number id(Number n) { return n; }
//
// p.5 asks for the CONSTANT PROPAGATION answer for `i` and p.6 asks for the
// CONTEXT INSENSITIVITY answer for `x.get()`. The slides are built one line at a
// time, so the deck's TEXT does not carry the answers -- they are the lecturer's
// to give. What the example DOES fix is the SHAPE of the difference: under
// context insensitivity `id` is analysed ONCE, so its parameter `n` holds BOTH
// objects, so `x` holds both, so `x.get()` may dispatch to `One::get` AND
// `Two::get`. Under context sensitivity `id` is analysed TWICE -- once per call
// site -- so `x` holds only `o1`.
//
// THIS MODULE MEASURES THAT DIFFERENCE. It builds the context-sensitive
// analysis and pins the two answers side by side. The numbers are the deck's
// SHAPE, not this tree's opinion: the objects are named the way deck 8 names
// them (by their allocation site's line) and the contexts are printed the way
// 11-12 prints them (by their call sites' lines).
//
// WHAT IS MODELLED, AND WHAT IS NOT.
//
//   * THE FOUR RULES ARE NOT REWRITTEN HERE. They are `pta.mbt`'s, reached through
//     `pta_sweep`, once per (function, context): a CONTEXT IS A DIFFERENT MAP,
//     not a different set of rules. One rule, one place.
//   * THE CALL RULE IS NEW, because deck 8's own file does not contain it (p.96)
//     and this one does. It is the deck's, in the deck's terms: the arguments
//     flow to the parameters, and the result flows back to the caller.
//   * A FUNCTION'S RESULT IS A POINTER the deck's rules do not name. `pta.mbt`
//     models a body, and a body's `return`/`tail` expression has nowhere to go
//     in a map that belongs to one function. Here the result is a pseudo-variable
//     of the CALLEE'S OWN MAP, named `result`, and the call rule moves its
//     objects to the caller's left-hand side.
//   * A METHOD BODY IS NOT IN THIS TREE'S AST (the parser reads past `impl`,
//     `trait`, `struct` and `enum` declarations whole -- `src/parser/parser.mbt`
//     204-210), so a target like `A::foo` is an EDGE AND NOT A STATE: the
//     analysis cannot analyse a body it does not have. Such a target is COUNTED
//     (`no_body`), never silently skipped, and the same count `callgraph.mbt`
//     makes.
//   * THE DISPATCH IS THE CALL GRAPH'S. `resolve_call` (deck 7's CHA, p.33-39)
//     answers "which methods can this call reach" from the receiver's DECLARED
//     TYPE. The deck 11-12 p.68-71 dispatch is by the receiver's TYPE, which
//     the pointer analysis knows and the call graph does not; using the call
//     graph's answer here is the conservative direction (more targets, a
//     bigger points-to set) and it keeps ONE dispatch in the tree.
//
// THE THREE CONTEXT ABSTRACTIONS ARE ALL BUILT, because the deck names all three
// and a factor that can only be set one way is not a factor.

///|
/// A CONTEXT: the call chain's call-site labels, printed the way 11-12 prints
/// them -- "3", "3,9". The EMPTY context is the empty string.
///
/// THE LABEL OF A CALL SITE IS ITS LINE, which is the label the deck itself uses:
/// p.104-115 label the three call sites 3, 9 and 15, and p.103's `l_1, ..., l_k`
/// are those labels. A label is the line, and where ONE LINE carries more than
/// one call site the label becomes "line:column" for all of them, so two calls on
/// one line do not silently share a context.
pub type PtaContext = String

///|
/// The CONTEXT ABSTRACTION FUNCTION -- the deck's `Select` (11-12 p.67-71,
/// p.99-115).
///
/// THE THREE VARIANTS ARE THE DECK'S OWN (p.99 prints the list: "Call-site
/// sensitivity / Object sensitivity / Type sensitivity"), except that TYPE
/// sensitivity is not built here: a type context needs the receiver's TYPE, and
/// this tree's type lens publishes only the module frame (`src/types/infer.mbt`
/// 1202-1215), so a local's type is not available to an analysis in this
/// package. The two that ARE built are the two the deck gives a FORMULA for.
pub(all) enum CtxSelect {
  /// p.102: "Select _, _, _ = [ ]" -- every calling context is merged, and the
  /// slide says this "Can be seen as a special case of context sensitivity".
  Insensitive
  /// p.103 and p.112: the last `k` call sites of the call chain -- k-CFA, the
  /// deck's "call-string sensitivity" (Shivers 1991). `k` = 1 is 1-CFA.
  CallSite(Int32)
  /// p.100: the RECEIVER'S OBJECT, with a heap context. The callee's context is
  /// the receiver's allocation site, and the CALL STRING IS DROPPED: the deck's
  /// p.100 slide keeps the caller context AND adds the heap context, and an
  /// unbounded call string does not terminate (p.110-111's k-limiting), so the
  /// heap context is kept at k = 1 and the call string at k = 0.
  Object
}

///|
/// One interprocedural edge of the context-sensitive analysis.
///
/// THE EDGES ARE DISTINCT: the work list visits a state more than once, and
/// the edge it takes out of that state is the same edge every time.
#derive(Eq)
pub(all) struct PtaCtxEdge {
  /// The caller's function.
  caller_fn : String
  /// The context the caller was analysed under.
  caller_ctx : PtaContext
  /// The call site's label.
  site : String
  /// The callee's function.
  callee_fn : String
  /// The context the callee is analysed under.
  callee_ctx : PtaContext
}

///|
/// What one context-sensitive run produced.
pub(all) struct PtaCtxResult {
  /// (function, context) -> points-to map. The key is `pta_ctx_key`.
  states : Map[String, Pta]
  /// function -> the contexts it was analysed under, in the order they appeared.
  contexts : Map[String, Array[String]]
  /// the interprocedural edges, one per (call site, target, context).
  edges : Array[PtaCtxEdge]
  /// the call sites that resolved to NO target at all.
  ///
  /// COUNTED PER (CALLER, CONTEXT, CALL SITE), because the work list visits a
  /// state more than once and a call site that resolves to nothing resolves to
  /// nothing every time.
  unresolved : Int32
  /// the call sites that resolved to a target THIS TREE HAS NO BODY FOR.
  ///
  /// COUNTED PER (CALLER, CONTEXT, CALL SITE, TARGET), for the same reason.
  no_body : Int32
  /// the number of (function, context) states.
  state_count : Int32
}

///|
/// The key of a state: the function's name and the context, joined.
pub fn pta_ctx_key(fname : String, ctx : PtaContext) -> String {
  fname + "|" + ctx
}

///|
/// The state key's two halves again.
///
/// THE SPLIT IS ON THE FIRST "|", and a function's name is the part before it.
/// `String::split_once` is the stdlib's own split, so the separator is written
/// once and the two halves are COPIED out of the view the stdlib hands back --
/// a view would keep the whole key alive.
fn pta_ctx_split(key : String) -> (String, PtaContext) {
  match key.split_once("|") {
    Some((before, after)) => (before.to_owned(), after.to_owned())
    None => (key, "")
  }
}

///|
/// The labels of a context, in order.
///
/// THE CONTEXT IS A COMMA-SEPARATED LIST of call-site labels, and the deck
/// prints it as a list (11-12 p.105-107: "Context: [3]", "Context: [3,9]"), so
/// this tree prints it the same way with a comma between the labels.
fn cs_items(ctx : PtaContext) -> Array[String] {
  if ctx == "" {
    []
  } else {
    ctx.split(",").map(fn(x) { x.to_owned() }).to_array()
  }
}

///|
/// The last `k` call sites of the call chain `ctx` followed by `site`.
///
/// THIS IS THE DECK'S FORMULA: p.115 prints "Select(c, l, _) = [l_{n-k+1}, ...,
/// l_n] where c = [l_1, ..., l_n]" and p.112 prints the k = 1 case as "Select _,
/// l, _ = [ l ]". So the CALL SITE IS APPENDED and then the chain is TRUNCATED to
/// its last k labels -- the truncation is p.111's k-limiting, and it is what
/// makes the analysis terminate.
fn cs_push(ctx : PtaContext, site : String, k : Int32) -> PtaContext {
  let items = cs_items(ctx)
  items.push(site)
  let out : Array[String] = []
  let mut i = items.length() - k
  if i < 0 {
    i = 0
  }
  while i < items.length() {
    out.push(items[i])
    i = i + 1
  }
  out.join(",")
}

///|
/// `Select(c, l, c')` -- the deck's context abstraction function (11-12 p.67-71).
///
/// `recv` is the RECEIVER'S POINTS-TO SET, which the object-sensitive variant
/// needs and the other two ignore. It is empty for a call with no receiver, and
/// for the object-sensitive variant an empty receiver set means the call has no
/// heap context to give, so the CALLER'S CONTEXT is inherited instead -- the
/// same fallback the call-site variant uses.
fn cs_select(
  sel : CtxSelect,
  caller_ctx : PtaContext,
  site : String,
  recv : Map[String, Bool],
) -> Array[PtaContext] {
  match sel {
    Insensitive => [""]
    CallSite(k) => [cs_push(caller_ctx, site, k)]
    Object => {
      let out : Array[PtaContext] = []
      for o, _ in recv {
        out.push(o)
      }
      if out.length() == 0 {
        out.push(caller_ctx)
      }
      out
    }
  }
}

///|
/// Record that a function was analysed under a context.
fn cs_add_context(
  contexts : Map[String, Array[String]],
  fname : String,
  ctx : PtaContext,
) -> Unit {
  match contexts.get(fname) {
    Some(xs) => if !xs.contains(ctx) { xs.push(ctx) }
    None => {
      let xs : Array[String] = [ctx]
      contexts.set(fname, xs)
    }
  }
}

///|
/// Record that a caller state watches a callee state.
fn cs_add_caller(
  callers_of : Map[String, Array[String]],
  callee_key : String,
  caller_key : String,
) -> Unit {
  match callers_of.get(callee_key) {
    Some(xs) => if !xs.contains(caller_key) { xs.push(caller_key) }
    None => {
      let xs : Array[String] = [caller_key]
      callers_of.set(callee_key, xs)
    }
  }
}

///|
/// The RETURN EXPRESSIONS of a function -- the value a call receives.
///
/// A MoonBit function returns its TAIL EXPRESSION (`{ n }`) or an explicit
/// `return e`; both are a value that leaves the body, and the deck's call rule
/// needs it as a pointer. The CFG does not keep it: `cfg_of` turns a return
/// into an `Eval` node plus a `Stop`, because for every OTHER lens the returned
/// value is only a READ. So it is read from the AST here.
fn cs_result_exprs(f : CgFn) -> Array[@ast.Expr] {
  let out : Array[@ast.Expr] = []
  cs_result_of_list(f.body, out)
  out
}

///|
/// The return expressions of a statement list.
fn cs_result_of_list(stmts : Array[@ast.Stmt], out : Array[@ast.Expr]) -> Unit {
  let mut i = 0
  while i < stmts.length() {
    cs_result_of_stmt(stmts[i], out)
    i = i + 1
  }
}

///|
/// The return expressions of ONE statement, and of the bodies it holds.
fn cs_result_of_stmt(s : @ast.Stmt, out : Array[@ast.Expr]) -> Unit {
  match s.kind {
    @ast.SReturn(Some(e)) => out.push(e)
    @ast.STail(e) => out.push(e)
    @ast.SIf(_, then_body, elifs, else_body) => {
      cs_result_of_list(then_body, out)
      let mut j = 0
      while j < elifs.length() {
        cs_result_of_list(elifs[j].body, out)
        j = j + 1
      }
      match else_body {
        Some(b) => cs_result_of_list(b, out)
        None => ()
      }
    }
    @ast.SWhile(_, body) => cs_result_of_list(body, out)
    @ast.SFor(_, _, _, body) => cs_result_of_list(body, out)
    @ast.SBlock(inner) => cs_result_of_list(inner, out)
    @ast.SNoBreak(inner, body) => {
      cs_result_of_stmt(inner, out)
      cs_result_of_list(body, out)
    }
    @ast.SForUpdate(body) => cs_result_of_list(body, out)
    _ => ()
  }
}

///|
/// One call site of a function, with the LABEL a context is made of.
pub(all) struct CsSite {
  /// The call itself.
  call : CgCall
  /// The call site's label -- the line, or "line:column" when one line carries
  /// more than one call site.
  label : String
  /// The line the call site is on. The deck names a site of interest by its
  /// line (p.75: "Site of interest: line 5"), so the line is kept as a number
  /// and not only as the label's text.
  line : Int32
}

///|
/// The call sites of one function, in the order the CFG numbers them, each with
/// its label.
///
/// THE LABEL IS THE LINE, and the deck's labels ARE lines: 11-12 p.104-115 call
/// the three call sites 3, 9 and 15. A line that carries TWO call sites gets
/// "line:column" for both of them, because one context per call site is the
/// whole point of the call-site abstraction and two calls that share a line
/// would otherwise share a context.
fn cs_sites_of(g : Cfg) -> Array[CsSite] {
  let out : Array[CsSite] = []
  let counts : Map[String, Int32] = Map([])
  let mut v = 0
  while v < g.kinds.length() {
    match cg_node_call(g.kinds[v]) {
      Some(_) => {
        let line = g.spans[v].start.line.to_string()
        match counts.get(line) {
          Some(n) => counts.set(line, n + 1)
          None => counts.set(line, 1)
        }
      }
      None => ()
    }
    v = v + 1
  }
  v = 0
  while v < g.kinds.length() {
    match cg_node_call(g.kinds[v]) {
      Some(c) => {
        let line = g.spans[v].start.line.to_string()
        let label = match counts.get(line) {
          Some(n) =>
            if n > 1 {
              line + ":" + g.spans[v].start.col.to_string()
            } else {
              line
            }
          None => line
        }
        out.push({ call: c, label, line: g.spans[v].start.line, })
      }
      None => ()
    }
    v = v + 1
  }
  out
}

///|
/// Record an edge, unless it is already there.
fn cs_add_edge(edges : Array[PtaCtxEdge], edge : PtaCtxEdge) -> Unit {
  if !edges.contains(edge) {
    edges.push(edge)
  }
}

///|
/// THE CONTEXT-SENSITIVE POINTER ANALYSIS.
///
/// THE FOUR RULES COME FROM `pta_sweep` -- `pta.mbt`'s own rules, applied to the
/// map of ONE (function, context). The call rule is this module's, and it is
/// 11-12 p.67-71's:
///
///     the ARGUMENTS flow to the callee's PARAMETERS,
///     the callee's RESULT flows to the caller's LEFT-HAND SIDE.
///
/// The contexts are chosen by `cs_select`, and the run ENDS when every state has
/// stopped growing.
///
/// THE WORK LIST IS OVER STATES, NOT OVER STATEMENTS. 11-12 p.88's `Solve`
/// works over the pointer flow graph's statements; here the same fixpoint is run
/// over (function, context) states, because a context is what makes a
/// statement's meaning different. The fixpoint is the same shape -- sets only
/// grow, the object set is finite (allocation-site abstraction, deck 8 p.44-47),
/// and the context set is finite (k-limited, p.110-111) -- so the run stops.
pub fn pta_ctx_run(
  fns : Array[CgFn],
  tab : TraitTable,
  main : String,
  sel : CtxSelect,
) -> PtaCtxResult {
  // The CFG of every function, PARALLEL to `fns`.
  let cfgs : Array[Cfg] = []
  let mut i = 0
  while i < fns.length() {
    cfgs.push(cfg_of(fns[i].body))
    i = i + 1
  }
  let sites = pta_site_names(cfgs)
  // function name -> index in `fns`.
  let index_of : Map[String, Int32] = Map([])
  i = 0
  while i < fns.length() {
    if !index_of.contains(fns[i].name) {
      index_of.set(fns[i].name, i)
    }
    i = i + 1
  }
  let states : Map[String, Pta] = Map([])
  let contexts : Map[String, Array[String]] = Map([])
  // The (caller, context, call site, target) combinations already COUNTED, so
  // that a state the work list visits twice is not counted twice.
  let counted : Map[String, Bool] = Map([])
  let callers_of : Map[String, Array[String]] = Map([])
  let edges : Array[PtaCtxEdge] = []
  let wl : Array[String] = []
  let mut unresolved = 0
  let mut no_body = 0
  match index_of.get(main) {
    None => ()
    Some(_) => {
      let k = pta_ctx_key(main, "")
      states.set(k, pta_empty())
      cs_add_context(contexts, main, "")
      wl.push(k)
    }
  }
  let mut head = 0
  while head < wl.length() {
    let key = wl[head]
    head = head + 1
    let (fname, ctx) = pta_ctx_split(key)
    let fi = match index_of.get(fname) {
      Some(x) => x
      None => continue
    }
    let pt = match states.get(key) {
      Some(p) => p
      None => continue
    }
    // 1. THE FOUR RULES, on this state's own map.
    let mut changed = pta_sweep(cfgs, sites, pt, fi)
    // 2. THE FUNCTION'S RESULT, which is a pointer of this state's map.
    let mut res = name_set_empty()
    for e in cs_result_exprs(fns[fi]) {
      res = name_set_union(res, pta_of_expr(pt, e))
    }
    if pta_join(pt, "result", res) {
      changed = true
    }
    // 3. THE CALLS.
    let csites = cs_sites_of(cfgs[fi])
    let declared = declared_types(fns[fi])
    let mut s = 0
    while s < csites.length() {
      let site = csites[s]
      let targets = resolve_call(site.call, declared, tab)
      if targets.length() == 0 {
        // A CALL SITE THAT RESOLVES TO NOTHING. Counted once per (caller,
        // context, call site): the work list visits a state more than once,
        // and a call that resolves to nothing resolves to nothing every
        // time.
        let ck = fname + "|" + ctx + "|" + site.label + "|<none>"
        if !counted.contains(ck) {
          counted.set(ck, true)
          unresolved = unresolved + 1
        }
        s = s + 1
        continue
      }
      let recv = if site.call.receiver != "" {
        pta_of(pt, site.call.receiver)
      } else {
        name_set_empty()
      }
      let cctxs = cs_select(sel, ctx, site.label, recv)
      let mut t = 0
      while t < targets.length() {
        let callee = targets[t]
        let ti = index_of.get(callee)
        if ti is None {
          // A TARGET THIS TREE HAS NO BODY FOR. Counted, never skipped
          // silently: the deck's method bodies are not in this tree's AST.
          // The CONTEXT and the EDGE are still recorded: the context is a
          // fact about the CALL, and it is the only place the
          // object-sensitive variant can be seen when the target is a method.
          let ck = fname + "|" + ctx + "|" + site.label + "|" + callee
          if !counted.contains(ck) {
            counted.set(ck, true)
            no_body = no_body + 1
          }
        }
        let mut c = 0
        while c < cctxs.length() {
          let cctx = cctxs[c]
          cs_add_context(contexts, callee, cctx)
          cs_add_edge(edges, {
            caller_fn: fname,
            caller_ctx: ctx,
            site: site.label,
            callee_fn: callee,
            callee_ctx: cctx,
          })
          match ti {
            None => ()
            Some(ti) => {
              let ckey = pta_ctx_key(callee, cctx)
              let cpt = match states.get(ckey) {
                Some(p) => p
                None => {
                  // A NEW STATE MUST BE VISITED, and not only when it grows:
                  // a callee whose body changes nothing -- a body with no
                  // allocation in it -- is still a body with CALLS in it, and
                  // those calls are how the next context is found. Queueing
                  // only on a CHANGE is what made the deck's call chain
                  // (11-12 p.104-115) stop after its first link.
                  let p = pta_empty()
                  states.set(ckey, p)
                  wl.push(ckey)
                  p
                }
              }
              let mut cchanged = false
              // THE ARGUMENTS -> THE PARAMETERS.
              let mut a = 0
              while a < site.call.args.length() && a < fns[ti].params.length() {
                let objs = pta_of_expr(pt, site.call.args[a])
                if pta_join(cpt, fns[ti].params[a].name, objs) {
                  cchanged = true
                }
                a = a + 1
              }
              // THE RESULT -> THE CALLER'S LEFT-HAND SIDE.
              if site.call.lhs != "" {
                if pta_join(pt, site.call.lhs, pta_of(cpt, "result")) {
                  changed = true
                }
              }
              cs_add_caller(callers_of, ckey, key)
              if cchanged {
                // THE CALLEE GREW, so the callee is re-visited and so are the
                // callers that read its result.
                wl.push(ckey)
                match callers_of.get(ckey) {
                  Some(ws) => {
                    let mut w = 0
                    while w < ws.length() {
                      wl.push(ws[w])
                      w = w + 1
                    }
                  }
                  None => ()
                }
              }
            }
          }
          c = c + 1
        }
        t = t + 1
      }
      s = s + 1
    }
    if changed {
      // THIS STATE GREW, so it is re-visited: its own rules may now reach
      // further, and its arguments may now say more.
      wl.push(key)
    }
  }
  {
    states,
    contexts,
    edges,
    unresolved,
    no_body,
    state_count: states.length(),
  }
}

///|
/// The points-to map of ONE (function, context), as text.
///
/// THE FORMAT IS `pta_text`'s, so the two analyses can be compared by their
/// printed tables -- which is how the deck compares them (p.61-64 against p.68).
pub fn pta_ctx_text(
  res : PtaCtxResult,
  fname : String,
  ctx : PtaContext,
) -> String {
  match res.states.get(pta_ctx_key(fname, ctx)) {
    Some(pt) => pta_text(pt)
    None => ""
  }
}

///|
/// The points-to set of ONE pointer in ONE (function, context).
pub fn pta_ctx_of(
  res : PtaCtxResult,
  fname : String,
  ctx : PtaContext,
  ptr : String,
) -> Map[String, Bool] {
  match res.states.get(pta_ctx_key(fname, ctx)) {
    Some(pt) => pta_of(pt, ptr)
    None => name_set_empty()
  }
}

///|
/// The contexts a function was analysed under, as the deck prints them.
pub fn pta_ctx_contexts(res : PtaCtxResult, fname : String) -> Array[String] {
  match res.contexts.get(fname) {
    Some(xs) => xs
    None => []
  }
}
