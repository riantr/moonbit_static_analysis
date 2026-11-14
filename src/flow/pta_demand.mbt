// 0575: THE DEMAND-DRIVEN SCOPE -- deck 8_PTA p.72-77.
//
// THE DECK. `Pointer Analysis` (Tian Tan, Nanjing University, 2021) spends p.72-77
// on the FOURTH of its four factors, and this is the factor the deck's own table
// (p.78) marks as NOT CHOSEN:
//
//   p.72   "Analysis Scope: Which parts of program should be analyzed?"
//          WHOLE-PROGRAM    "Compute points-to information for all pointers in
//                            the program"   /  "Provide information for all
//                            possible clients"
//          DEMAND-DRIVEN    "Only compute points-to information for the pointers
//                            that may affect specific sites of interest (on
//                            demand)"  /  "Provide information for specific
//                            clients"
//   p.73-77 THE EXAMPLE, and the two printed columns:
//
//          1 x = new A();
//          2 y = x;
//          3 …
//          4 z = new T();
//          5 z.bar();
//
//          p.74 (the whole-program column)   x -> {o1}   y -> {o1}   z -> {o4}
//          p.76 (the demand-driven column)                 z -> {o4}
//
//          p.75 says WHY the scope is a factor at all: "Client: call graph
//          construction", "Site of interest: line 5", "What points-to information
//          do we need". The client's question is about ONE pointer -- the
//          receiver at line 5 -- and the whole-program answer computes three.
//
//   p.77   "Chosen in this course" -- the mark is on the WHOLE-PROGRAM column.
//
// SO THE COURSE'S CHOICE IS WHAT `pta.mbt` ALREADY DOES, and this module builds
// the other column. The two columns are the SAME program with the SAME rules
// and the SAME object naming, and they differ in ONE thing: how much is
// computed. The difference is a PRINTED TABLE the deck gives, so it can be
// pinned.
//
// WHAT "ON DEMAND" MEANS HERE, AND WHY IT IS NOT A SLICE.
//
// The deck's definition is "the pointers that may affect specific sites of
// interest". The word that does the work is AFFECT: a pointer affects a site if
// a value can flow from it to that site. That is a question about the RULES, and
// this module answers it by running the rules BACKWARD from the demand -- "which
// statements write this pointer, and what do they read?" -- and then evaluating
// only the pointers that answer came back with.
//
// SO THE DEMAND IS A WORK LIST OF (FUNCTION, POINTER) PAIRS, and the value of
// each demanded pair is computed from the pairs it reads. The rules are the SAME
// RULES the whole-program analysis uses, read in the other direction:
//
//   the pointer `x` is written by   x = e         -> the source is `e`
//                             by    x.f = e       -> the source is `e`, for each
//                                                     object `x` may point to
//                             by    x = new T()   -> the object of that site
//                             and   `x` is a PARAMETER -> the caller's argument
//
// The last one is the interprocedural part, and it is what the deck's CLIENT
// needs: a call graph is built from the receiver at a call site, and that
// receiver is often a parameter, whose value lives in the caller.
//
// THE ANSWER IS A MAP OF THE DEMANDED POINTERS ONLY, which is what makes the
// two columns comparable: p.76's column is one line long because only `z` was
// demanded, and this module's map is one line long for the same reason.
//
// WHAT IS NOT MODELLED.
//
//   * A CALL'S RESULT IS NOT A SOURCE. `z.bar()`'s result is unknown to this
//     analysis, exactly as it is to `pta.mbt` -- deck 8's file withholds the
//     call rule (p.96) -- so a pointer that is only ever written by a call has
//     NO value here. The direction is the tree's: a value the analysis does not
//     model contributes nothing rather than an invented object.
//   * THE DEMAND DOES NOT CROSS A CALL FORWARD. A callee's result is not
//     demanded, because the deck's site of interest is a RECEIVER, and a
//     receiver is a pointer that already exists. What crosses the call boundary
//     is the PARAMETER case above.

///|
/// A CLIENT'S QUESTION: the pointer at a site of interest.
///
/// THE POINTER IS THE RECEIVER of the call at that site, which is what the
/// deck's client needs (p.75: "Client: call graph construction", "Site of
/// interest: line 5", "What points-to information do we need").
pub(all) struct PtaDemandQuery {
  /// The function the site of interest is in.
  fn_name : String
  /// The pointer the client asks about.
  pointer : String
}

///|
/// What one demand-driven run produced.
pub(all) struct PtaDemandResult {
  /// The demanded pointers OF THE CLIENT'S FUNCTION -- the deck's p.76 column.
  points_to : Pta
  /// Every demanded (function, pointer) pair's value, keyed `dm_key`.
  values : Map[String, Map[String, Bool]]
  /// The demanded (function, pointer) pairs, keyed `dm_key`.
  demanded : Map[String, Bool]
  /// The number of demand steps.
  steps : Int32
}

///|
/// The key of a demand: the function's NAME and the pointer's name.
fn dm_key(fname : String, ptr : String) -> String {
  fname + "|" + ptr
}

///|
/// The state of one demand-driven run.
priv struct DemandState {
  /// The functions, and their CFGs, PARALLEL to each other.
  fns : Array[CgFn]
  cfgs : Array[Cfg]
  /// The allocation sites' names, keyed "fi:node".
  sites : Map[String, String]
  /// The function's name -> its index.
  index_of : Map[String, Int32]
  /// (function, pointer) -> the objects it may point to.
  values : Map[String, Map[String, Bool]]
  /// The demanded (function, pointer) pairs.
  demanded : Map[String, Bool]
  /// (function, pointer) -> the pairs that READ it.
  watchers : Map[String, Array[String]]
  /// The work list of pairs to (re)compute.
  worklist : Array[String]
  /// The callee's name -> the call sites that reach it.
  callers : Map[String, Array[DmCall]]
  /// The number of demand steps.
  mut steps : Int32
}

///|
/// One call site, as the demand needs it: the CALLER and the ARGUMENTS.
priv struct DmCall {
  /// The caller's index.
  caller : Int32
  /// The arguments.
  args : Array[@ast.Expr]
}

///|
/// The single-object set.
fn dm_one(obj : String) -> Map[String, Bool] {
  let out : Map[String, Bool] = Map([])
  out.set(obj, true)
  out
}

///|
/// Record that a reader WATCHES a key.
fn dm_watch(st : DemandState, key : String, reader : String) -> Unit {
  match st.watchers.get(key) {
    Some(xs) => if !xs.contains(reader) { xs.push(reader) }
    None => {
      let xs : Array[String] = [reader]
      st.watchers.set(key, xs)
    }
  }
}

///|
/// The value of a pointer, AND the registration of the demand for it.
///
/// THE VALUE IS THE CURRENT ONE, which may be EMPTY: a pointer that has just
/// been demanded has not been computed yet, and the work list will compute it.
fn dm_pts(
  st : DemandState,
  reader : String,
  fname : String,
  ptr : String,
) -> Map[String, Bool] {
  let ck = dm_key(fname, ptr)
  dm_watch(st, ck, reader)
  match st.values.get(ck) {
    Some(v) => v
    None => {
      let v : Map[String, Bool] = Map([])
      st.values.set(ck, v)
      st.demanded.set(ck, true)
      st.worklist.push(ck)
      v
    }
  }
}

///|
/// The objects an expression may evaluate to, under the DEMAND.
///
/// THE READS ARE DEMANDS: asking for the value of `x.f` demands `x` AND, for
/// each object `x` may point to, the field pointer `o.f`. Asking for a field's
/// value is what makes the object that holds it demanded, which is the whole
/// shape of "the pointers that may affect this one".
fn dm_expr(
  st : DemandState,
  reader : String,
  fi : Int32,
  e : @ast.Expr,
) -> Map[String, Bool] {
  match e.kind {
    @ast.EName(x) => dm_pts(st, reader, st.fns[fi].name, x)
    @ast.EField(b, f) => {
      let base = dm_expr(st, reader, fi, b)
      let mut out : Map[String, Bool] = Map([])
      for o, _ in base {
        let v = dm_pts(st, reader, st.fns[fi].name, o + "." + f)
        out = name_set_union(out, v)
      }
      out
    }
    // p.86: indexes are ignored; the whole array is one field.
    @ast.EIndex(b, _) => {
      let base = dm_expr(st, reader, fi, b)
      let mut out : Map[String, Bool] = Map([])
      for o, _ in base {
        let v = dm_pts(st, reader, st.fns[fi].name, o + ".arr")
        out = name_set_union(out, v)
      }
      out
    }
    // p.59 puts a literal inside a points-to set, so a literal is an object.
    @ast.EStr(v, refs) =>
      if refs.length() == 0 {
        dm_one("\"" + v + "\"")
      } else {
        name_set_empty()
      }
    _ => name_set_empty()
  }
}

///|
/// The object's name of the allocation site at one node.
fn dm_site(st : DemandState, fi : Int32, v : Int32) -> String {
  match st.sites.get(fi.to_string() + ":" + v.to_string()) {
    Some(k) => k
    None => ""
  }
}

///|
/// The FIELD a pointer names -- the part after its last dot, or "" when the
/// pointer is not a field pointer.
///
/// IT IS WHAT MAKES THE DEMAND PRECISE ABOUT FIELDS: a store into `o.f` cannot
/// write `o.g`, so a demand for `o.g` does not have to look at the stores into
/// `o.f`.
fn dm_field_of(ptr : String) -> String {
  if !ptr.contains(".") {
    return ""
  }
  let parts = ptr.split(".").map(fn(x) { x.to_owned() }).to_array()
  if parts.length() == 0 {
    ""
  } else {
    parts[parts.length() - 1]
  }
}

///|
/// The value of a PARAMETER, which lives in the CALLER's argument.
///
/// THE DEMAND CROSSES THE CALL BOUNDARY HERE, and only here: a parameter's
/// value is the argument at the call site that reached it. The callers are the
/// ones the CALL GRAPH found (deck 7's `resolve_call`), so a call the tree
/// cannot resolve contributes nothing -- the same counted boundary the call
/// graph itself carries.
fn dm_param_source(
  st : DemandState,
  reader : String,
  fi : Int32,
  ptr : String,
) -> Map[String, Bool] {
  let mut out : Map[String, Bool] = Map([])
  let mut i = 0
  while i < st.fns[fi].params.length() {
    if st.fns[fi].params[i].name == ptr {
      match st.callers.get(st.fns[fi].name) {
        Some(cs) => {
          let mut k = 0
          while k < cs.length() {
            if i < cs[k].args.length() {
              let v = dm_expr(st, reader, cs[k].caller, cs[k].args[i])
              out = name_set_union(out, v)
            }
            k = k + 1
          }
        }
        None => ()
      }
    }
    i = i + 1
  }
  out
}

///|
/// Recompute the value of one demanded pointer; true when it GREW.
///
/// THE RULES ARE THE SAME FOUR, READ BACKWARD. Every statement that WRITES the
/// pointer contributes its source, and the source is itself a demand.
fn dm_recompute(st : DemandState, fi : Int32, ptr : String) -> Bool {
  let ck = dm_key(st.fns[fi].name, ptr)
  let mut result : Map[String, Bool] = Map([])
  let g = st.cfgs[fi]
  let want_field = dm_field_of(ptr)
  let mut v = 0
  while v < g.kinds.length() {
    let kind = g.kinds[v]
    match kind {
      Assign(x, e) =>
        if x == ptr {
          result = name_set_union(result, dm_write(st, ck, fi, v, e, ptr))
        }
      Store(x, e) =>
        if x == ptr {
          result = name_set_union(result, dm_write(st, ck, fi, v, e, ptr))
        }
      PlaceStore(target, e) =>
        match target.kind {
          @ast.EField(b, fld) =>
            if want_field == "" || want_field == fld {
              let base = dm_expr(st, ck, fi, b)
              for o, _ in base {
                if ptr == o + "." + fld {
                  result = name_set_union(result, dm_expr(st, ck, fi, e))
                }
              }
            }
          @ast.EIndex(b, _) =>
            if want_field == "" || want_field == "arr" {
              let base = dm_expr(st, ck, fi, b)
              for o, _ in base {
                if ptr == o + ".arr" {
                  result = name_set_union(result, dm_expr(st, ck, fi, e))
                }
              }
            }
          _ => ()
        }
      _ => ()
    }
    v = v + 1
  }
  // THE PARAMETER CASE: the value lives in the caller's argument.
  result = name_set_union(result, dm_param_source(st, ck, fi, ptr))
  let grew = match st.values.get(ck) {
    Some(o) => name_set_subtract(result, o).length() > 0
    None => result.length() > 0
  }
  st.values.set(ck, result)
  grew
}

///|
/// The source of a write, which is an ALLOCATION when the right-hand side is
/// one and the expression itself otherwise.
///
/// THE ALLOCATION CASE IS `pta.mbt`'s: a `T::{...}` allocates, and its
/// initialisers are STORES into the fresh object -- so a demand for `o.f` finds
/// them here, exactly as the whole-program analysis does.
fn dm_write(
  st : DemandState,
  reader : String,
  fi : Int32,
  v : Int32,
  e : @ast.Expr,
  ptr : String,
) -> Map[String, Bool] {
  let mut out : Map[String, Bool] = Map([])
  match e.kind {
    @ast.EStruct(_, inits) => {
      let obj = dm_site(st, fi, v)
      out = name_set_union(out, dm_one(obj))
      for pair in inits {
        let (fld, ie) = pair
        if ptr == obj + "." + fld {
          out = name_set_union(out, dm_expr(st, reader, fi, ie))
        }
      }
    }
    _ => out = name_set_union(out, dm_expr(st, reader, fi, e))
  }
  out
}

///|
/// THE DEMAND-DRIVEN ANALYSIS.
///
/// The answer is a map of the DEMANDED pointers only, and the whole-program
/// answer for the same pointer is the same set -- the scope changes how much is
/// computed, never what is true. Both are pinned by the test.
pub fn pta_demand_run(
  fns : Array[CgFn],
  tab : TraitTable,
  query : PtaDemandQuery,
) -> PtaDemandResult {
  let cfgs : Array[Cfg] = []
  let mut i = 0
  while i < fns.length() {
    cfgs.push(cfg_of(fns[i].body))
    i = i + 1
  }
  let index_of : Map[String, Int32] = Map([])
  i = 0
  while i < fns.length() {
    if !index_of.contains(fns[i].name) {
      index_of.set(fns[i].name, i)
    }
    i = i + 1
  }
  let st = {
    fns,
    cfgs,
    sites: pta_site_names(cfgs),
    index_of,
    values: Map([]),
    demanded: Map([]),
    watchers: Map([]),
    worklist: [],
    callers: Map([]),
    steps: 0,
  }
  // THE CALLERS of every function: the call sites that reach it.
  i = 0
  while i < fns.length() {
    let csites = cs_sites_of(cfgs[i])
    let declared = declared_types(fns[i])
    let mut s = 0
    while s < csites.length() {
      let targets = resolve_call(csites[s].call, declared, tab)
      let mut t = 0
      while t < targets.length() {
        match st.callers.get(targets[t]) {
          Some(xs) => xs.push({ caller: i, args: csites[s].call.args, })
          None => {
            let xs : Array[DmCall] = [{ caller: i, args: csites[s].call.args, }]
            st.callers.set(targets[t], xs)
          }
        }
        t = t + 1
      }
      s = s + 1
    }
    i = i + 1
  }
  // THE DEMAND ITSELF.
  match index_of.get(query.fn_name) {
    None => ()
    Some(_) => {
      let ck = dm_key(query.fn_name, query.pointer)
      ignore(dm_pts(st, ck, query.fn_name, query.pointer))
    }
  }
  // THE WORK LIST, until every demanded pointer has stopped growing.
  let mut head = 0
  while head < st.worklist.length() {
    let ck = st.worklist[head]
    head = head + 1
    let (fname, ptr) = dm_split(ck)
    match st.index_of.get(fname) {
      None => ()
      Some(fi) => {
        st.steps = st.steps + 1
        if dm_recompute(st, fi, ptr) {
          match st.watchers.get(ck) {
            Some(ws) => {
              let mut w = 0
              while w < ws.length() {
                st.worklist.push(ws[w])
                w = w + 1
              }
            }
            None => ()
          }
        }
      }
    }
  }
  // THE ANSWER: the demanded pointers of the CLIENT'S function.
  let points_to : Pta = Map([])
  for ck, _ in st.demanded {
    let (fname, ptr) = dm_split(ck)
    if fname == query.fn_name {
      match st.values.get(ck) {
        Some(v) => points_to.set(ptr, v)
        None => ()
      }
    }
  }
  { points_to, values: st.values, demanded: st.demanded, steps: st.steps, }
}

///|
/// The key of a demand's two halves again.
fn dm_split(key : String) -> (String, String) {
  match key.split_once("|") {
    Some((before, after)) => (before.to_owned(), after.to_owned())
    None => (key, "")
  }
}

///|
/// The RECEIVER at a call site -- the deck's "site of interest" (p.75).
///
/// THE LINE IS THE DECK'S LOCATOR: p.75 says "Site of interest: line 5", and
/// the site of interest in the deck's own program is the call `z.bar()`. What
/// the client needs is the RECEIVER, and the receiver of that call is `z`.
///
/// A call whose receiver is not a plain NAME has no receiver this tree can
/// name, so the site is not a site of interest this module can answer, and it
/// answers `None` rather than a guess.
pub fn pta_demand_site(
  fns : Array[CgFn],
  fn_name : String,
  line : Int32,
) -> PtaDemandQuery? {
  let mut i = 0
  while i < fns.length() {
    if fns[i].name == fn_name {
      let g = cfg_of(fns[i].body)
      let csites = cs_sites_of(g)
      let mut s = 0
      while s < csites.length() {
        if csites[s].line == line && csites[s].call.receiver != "" {
          return Some({ fn_name, pointer: csites[s].call.receiver, })
        }
        s = s + 1
      }
    }
    i = i + 1
  }
  None
}
