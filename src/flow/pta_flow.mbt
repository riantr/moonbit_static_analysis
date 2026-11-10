// 0550: FLOW-SENSITIVE POINTS-TO -- a map of points-to relations AT EACH PROGRAM
// LOCATION, and the first transfer in this package that REPLACES a fact.
//
// THE REFERENCE IS THE SAME 104-PAGE ATTACHMENT 0547 READ: Tian Tan, `Pointer
// Analysis`, Nanjing University, 2021. That increment took the deck's RULE SYSTEM
// -- the domain of p.97 and the four rules of p.98 -- and built the reading the
// deck's course chose: flow-INsensitive, which p.70 marks "Chosen in this course".
//
// WHAT THE DECK STILL PRINTS AND THIS TREE STILL DID NOT COMPUTE. The deck spends
// fifteen slides on the other half of the flow-sensitivity factor (p.55-70). Its
// two columns are:
//
//     flow-sensitive     "Maintain a map of points-to relations at each program
//                         location"
//     flow-insensitive   "Maintain one map of points-to relations for the whole
//                         program"
//
// and then it runs ONE program through both:
//
//     1 c = new C();
//     2 c.f = "x";
//     3 s = c.f;
//     4 c.f = "y";
//
//     p.64   flow-sensitive     c -> {o1}   o1.f -> {"y"}      s -> {"x"}
//     p.68   flow-insensitive   c -> {o1}   o1.f -> {"x","y"}   s -> {"x","y"}
//     p.69   and the word "false positive" printed next to the flow-insensitive `s`
//
// The false positive is the deck's OWN verdict and not a criticism added here: the
// load at line 3 runs BEFORE the store at line 4, so `s` can only ever hold "x". A
// map that does not know where it is cannot see that, and keeps "y" as well.
//
// WHAT 0547 HAD, AND WHY IT WAS NOT THIS. `pta_run_ordered` answers the same
// question for a STRAIGHT-LINE body, and its own test pins p.64 exactly. It is a
// CONTROL, and 0547's own "WHAT THIS DOES NOT DO" says why it is not the analysis:
// it re-derives source order from the spans and walks the statements once, so it
// cannot answer the question on a body with a branch or a loop. A flow-sensitive
// analysis that only works when the program is straight is not the analysis the
// deck describes.
//
// SO THIS IS THAT ANALYSIS, ON THE FRAMEWORK THIS PACKAGE ALREADY HAS: the graph
// (`cfg.mbt`), the lattice (`lattice.mbt`), the solver (`worklist.mbt`). p.55's
// "a map of points-to relations at each program location" IS a lattice whose
// elements are points-to maps, and the deck's flow-sensitive reading IS a transfer
// that REPLACES a pointer's set instead of joining into it.
//
// THE TRANSFER IS THE FIRST ONE HERE THAT IS NOT A JOIN. Every other transfer in
// this package only ever ADDS facts -- live variables, intervals, available
// expressions, and the flow-insensitive points-to arm of p.98 -- and that is what
// lets the framework's solvers be plain ascending-chain iterations. This one
// removes: after `c.f = "y"` the field holds "y" and not "x" as well. It is still
// MONOTONE, because the transfer replaces ONE key and copies the rest, so the
// ascending chain still works and the laws the solvers depend on still hold. But it
// is a different kind of object from the four rules of p.98, and the difference is
// exactly the word on p.55.
//
// WHY A STRONG UPDATE IS SOUND HERE, WHICH IS NOT TRUE OF A STRONG UPDATE IN
// GENERAL. The usual condition on a strong update is that the variable being
// overwritten is not aliased, because otherwise the old value survives somewhere
// else and dropping it loses a fact. Two properties of the deck's own DOMAIN make
// that condition unnecessary here, and both come from p.97:
//
//     Pointer = V UNION (O x F)
//
// 1. A VARIABLE'S OLD BINDING IS PRIVATE TO THE VARIABLE. `x = e` rebinds the
//    NAME `x`; it does not change any object. Another pointer `y` that pointed at
//    the same object still points at it and its own set is untouched. The only
//    thing the strong update drops is `x`'s own previous binding, which the
//    assignment has just replaced.
//
// 2. A FIELD POINTER IS NAMED BY ITS OBJECT, NOT BY THE VARIABLE THAT REACHES IT.
//    `a.f` and `b.f` are the SAME pointer when `a` and `b` point at the same
//    object, because the key is `o.f`. A store through `a` is therefore visible
//    through `b`, which is what makes the strong update of a FIELD sound: there is
//    exactly one pointer per (object, field) pair, so nothing else can be holding
//    a different opinion about that field.
//
// p.97's domain is therefore not bookkeeping here -- it is what makes the strong
// update sound, and `pta_flow_test.mbt` pins the second property as a control.
//
// WHAT IS NOT MODELLED, NAMED RATHER THAN LEFT TO BE DISCOVERED.
//
//   * CALLS. p.88's fifth statement kind is still the one this attachment withholds
//     (p.96 defers it to a section the file does not contain), so a call
//     contributes no objects and binds nothing. That is also what makes the strong
//     update of a variable sound inside a body: no callee can observe a binding
//     this analysis does not pass.
//   * A METHOD'S RECEIVER. `self` is a parameter like any other and nothing binds
//     it to the object a call would pass. The deck's own p.21-25 table shows `this`
//     in the points-to relation, and that table is about a method CALL.
//   * `array[i]` IS ONE FIELD `arr` (p.86), so two writes into one array are
//     indistinguishable. That is the deck's own instruction, and flow sensitivity
//     does not refine it: the two writes are at DIFFERENT locations and the deck
//     collapses them anyway.
//   * A STATEMENT THE GRAPH DID NOT CONVERT. `Cfg.skipped` counts them, and a
//     skipped statement is a read this analysis cannot see -- so a caller that
//     wants a claim about a function has to check `skipped == 0` first, exactly as
//     `dead_stores` does for the dead-store family.

///|
/// The points-to map lattice: the elements are points-to maps, ordered key by key
/// and joined by the union of the object sets.
///
/// THE CANONICAL FORM IS PART OF THE ORDER. A key is present in a map exactly
/// when its object set is not empty, so the carrier has ONE representation per
/// points-to relation and `eq` is a real equality rather than an equality up to
/// representation. Without that, a state that says "x points to nothing" and one
/// that says "x is not in the map" would compare unequal, and the solver would keep
/// re-queueing a node whose state had not really changed.
pub fn pta_map_lattice() -> Lattice[Pta] {
  {
    bot: fn() { pta_empty() },
    join: fn(a, b) { pta_map_union(a, b) },
    eq: fn(a, b) { pta_map_eq(a, b) },
  }
}

///|
/// A deep copy of one object set.
fn pta_set_copy(s : Map[String, Bool]) -> Map[String, Bool] {
  let out = name_set_empty()
  for o, _ in s {
    out.set(o, true)
  }
  out
}

///|
/// A deep copy of a points-to map.
///
/// THE COPY IS THE SOLVER'S CONTRACT, NOT DEFENSIVENESS. `Lattice`'s header
/// records the bug this package shipped once: a shared mutable seed is one element
/// for the whole graph, which is why `bot` is a thunk. The same argument applies to
/// the transfer: the solver keeps `before[v]` and compares the transfer's output
/// with it, so a transfer that wrote into its input would change the state the
/// solver is holding and make that comparison meaningless -- and the comparison is
/// what tells the solver to stop.
fn pta_map_copy(pt : Pta) -> Pta {
  let out : Pta = Map([])
  for k, s in pt {
    out.set(k, pta_set_copy(s))
  }
  out
}

///|
/// The join of two points-to maps: key by key, the union of the object sets.
///
/// NEITHER ARGUMENT IS MUTATED. `name_set_union`'s own comment says why: the
/// solver passes a joined value on, and a join that wrote into its input would make
/// the solver's `eq` comparison meaningless.
fn pta_map_union(a : Pta, b : Pta) -> Pta {
  let out : Pta = Map([])
  for k, s in a {
    out.set(k, pta_set_copy(s))
  }
  for k, s in b {
    let cur = match out.get(k) {
      Some(x) => x
      None => name_set_empty()
    }
    out.set(k, name_set_union(cur, s))
  }
  out
}

///|
/// Map equality: the same keys, with the same objects under each.
fn pta_map_eq(a : Pta, b : Pta) -> Bool {
  if a.length() != b.length() {
    return false
  }
  for k, s in a {
    match b.get(k) {
      None => return false
      Some(t) => if name_set_eq(s, t) == false { return false }
    }
  }
  true
}

///|
/// Put a pointer's set, in the canonical form: a key is present exactly when its
/// set is not empty, and the map owns the set it is given.
fn pta_map_put(pt : Pta, key : String, objs : Map[String, Bool]) -> Unit {
  if objs.length() == 0 {
    pt.remove(key)
  } else {
    pt.set(key, pta_set_copy(objs))
  }
}

///|
/// The deck's rules at one node, with STRONG updates: the written pointer's set is
/// REPLACED by the new value instead of joined into it.
///
/// THE RIGHT-HAND SIDE IS READ IN THE INCOMING STATE. `x = x` and `x.f = x` both
/// read the value `x` had BEFORE the statement, which is why this function takes
/// `pt` (the incoming map) and not `out` (the map it is building). An allocation's
/// initialisers are read the same way: `A::{ b: v }` stores `v` into the fresh
/// object, and `v` is whatever it was before the allocation.
fn pta_fs_step(
  g : Cfg,
  sites : Map[String, String],
  v : Int32,
  pt : Pta,
) -> Pta {
  let out = pta_map_copy(pt)
  let kind = g.kinds[v]
  match pta_alloc_of(kind) {
    Some(inits) => {
      // New: the object is the site's own name (p.45-47, p.77), and the name now
      // points at it and at nothing else.
      let obj = pta_site_of(sites, 0, v)
      pta_map_put(out, pta_bound_name(kind), pta_one(obj))
      // ... and the initialisers are stores into that object -- 0547's extension,
      // and the deck's Store rule with the fresh object as the target.
      for pair in inits {
        let (fld, e) = pair
        pta_map_put(out, obj + "." + fld, pta_of_expr(pt, e))
      }
    }
    None =>
      match kind {
        // Assign, and the load form of it: `s = c.f` is the deck's Load rule, and
        // `pta_of_expr` answers the right-hand side either way.
        Assign(x, e) => pta_map_put(out, x, pta_of_expr(pt, e))
        Store(x, e) => pta_map_put(out, x, pta_of_expr(pt, e))
        // Store THROUGH a place: `x.f = y` is the deck's Store rule.
        PlaceStore(target, e) => {
          let src = pta_of_expr(pt, e)
          match target.kind {
            @ast.EField(b, fld) =>
              for o, _ in pta_of_expr(pt, b) {
                pta_map_put(out, o + "." + fld, src)
              }
            // p.86: indexes are ignored; the whole array is one field.
            @ast.EIndex(b, _) =>
              for o, _ in pta_of_expr(pt, b) {
                pta_map_put(out, o + ".arr", src)
              }
            _ => ()
          }
        }
        // A read is not a write: `Test`, `Eval`, `AssignMulti`, `Entry`, `Exit` and
        // `Stop` leave the map as it was.
        _ => ()
      }
  }
  out
}

///|
/// The transfer function, as this package's solvers take it: (node, state) -> state.
///
/// IT IS PUBLIC so that a test can run the OTHER solver over the same transfer and
/// compare. The book says the two solvers compute the same least fixed point, and
/// `pta_flow_test.mbt` checks that on this lattice instead of taking it on trust.
pub fn pta_fs_transfer_of(g : Cfg) -> (Int32, Pta) -> Pta {
  let sites = pta_site_names([g])
  fn(v, pt) { pta_fs_step(g, sites, v, pt) }
}

///|
/// The flow-sensitive analysis: the state AFTER each node.
///
/// p.55's "a map of points-to relations at each program location" IS this array:
/// the index is the node, the value is the map at that node. The node order is
/// `cfg_of`'s own -- back to front -- so a reader has to use the SPANS to find the
/// node they mean, which is the same trap `pta_source_order` exists to undo.
pub fn pta_run_flow_sensitive(g : Cfg) -> Array[Pta] {
  let tr = pta_fs_transfer_of(g)
  let before = solve_propagation(
    pta_map_lattice(),
    g.kinds.length(),
    g.succ,
    tr,
  )
  states_after(g.kinds.length(), before, tr)
}
