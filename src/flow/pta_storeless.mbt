// 0576: THE STORELESS HEAP ABSTRACTION -- 8_PTA's cell H2.
//
// THE DECK NAMES IT AND DOES NOT DEFINE IT. `Pointer Analysis` (Tian Tan, Nanjing
// University, 2021) prints its Key Factors table on p.34-38, and re-prints it at
// p.48, p.54, p.71 and as the final summary on p.78:
//
//     Heap abstraction    How to model heap memory?      Allocation-site | Storeless
//
// and its own heap-abstraction section is p.39-43, which leads to p.44-47's
// "Allocation-Site Abstraction" -- the one the course chose. MEASURED over the
// deck's 104 pages: "storeless" appears on NINE of them, and every one of the nine
// is the TABLE or the final summary. The deck NAMES the cell and never develops
// it, so this cell is the last empty one in the deck's four-factor table.
//
// THE DECK NAMES ITS OWN CLIENT. p.42-43 carry one citation, on both pages:
//
//     Vini Kanvar, Uday P. Khedker, "Heap Abstractions for Static Analysis".
//     ACM CSUR 2016
//
// THAT SURVEY IS THE DEFINITION OF THE CELL, and the model is the survey's own
// (p.6-7):
//
//     "We classify the heap models as storeless, store based, and hybrid."
//     "Storeless model. The storeless model (originally proposed by Jonkers)
//      views the heap as a collection of access paths. An access path consists
//      of a pointer variable which is followed by a sequence of fields of a
//      structure. The desired properties of both a concrete and an abstract heap
//      memory are stored as relations on access paths. The storeless model does
//      not explicate the memory locations or objects corresponding to these
//      access paths. Given V as the set of root variables and F as the set of
//      field variable names, the set of access paths is defined as V x F*."
//
// SO THE DOMAIN HERE IS THE SURVEY'S: an access path is a ROOT VARIABLE followed
// by a sequence of FIELDS, and the heap is a relation ON THOSE PATHS. The tree's
// allocation-site model is the OTHER model in the survey's taxonomy (p.6): a
// store-based model, where the heap is a graph of locations and the objects are
// named by their allocation sites.
//
// WHAT IS THE SURVEY'S AND WHAT IS THIS TREE'S, STATED SEPARATELY BECAUSE THEY
// ARE DIFFERENT CLAIMS:
//
//   * THE MODEL -- what the heap IS -- is the survey's: access paths, not
//     objects, and the survey's own sentence that the model "does not explicate
//     the memory locations or objects corresponding to these access paths".
//   * THE SUMMARIZATION -- how the model is BOUNDED -- is the survey's: the
//     k-limiting predicate (p.12) and the self-loop mechanism (p.9), both
//     quoted below.
//   * THE ALGORITHM -- how it is COMPUTED -- is THIS TREE'S, and the survey
//     says why that is the right division of labour: its own abstract (p.1)
//     says "our interest lies in the abstractions and not in the algorithms that
//     construct them". So the four rules are `pta.mbt`'s, carried over to the
//     access-path domain, and NOT a second implementation of somebody else's
//     unification procedure.
//
// THE FOUR RULES ARE THE TREE'S OWN, OVER A DIFFERENT DOMAIN. A context is a
// different MAP (0575); a heap abstraction is a different SET OF PATHS. The
// rules do not change:
//
//     New     x = new T()      the fresh location is named by the path rooted
//                               at x -- there is no allocation site in this
//                               model, because the survey classifies "allocation
//                               site" as a SUMMARIZATION (p.11 section 2), and
//                               this cell is the model WITHOUT it
//     Assign  x = y             x may reach what y may reach
//     Store   x.f = y           for each path p x may reach, p.f may reach what
//                               y may reach
//     Load    y = x.f           y may reach what p.f may reach, for each path p
//                               x may reach
//
// THE k-LIMITING IS WHAT MAKES THE MODEL FINITE, and the survey is explicit
// about why it is needed: the access-path set is "V x F*", so "the number of
// access paths is potentially infinite and the length of each access path is
// unbounded" (p.7). The predicate is p.12's -- "k-limiting predicate: Is the
// heap location at most k indirections from a root variable?" -- and the
// mechanism is p.9's:
//
//     "For k = 2, heap nodes beyond two indirections are not stored. A self
//      loop is created on the second indirection (node corresponding to x.f.f)
//      to over-approximate this information. This stores spurious aliases for
//      access paths with more than k = 2 indirections (for example, x.f.f.f and
//      y are spuriously marked as aliases at Out6)."
//
// THE SPURIOUS ALIAS IS A CONSEQUENCE OF THE SUMMARIZATION, NOT A BUG, and it is
// the survey's own example, so a test pins it: at the bound, a location beyond
// it is merged into the location at the bound, and the merge is visible as an
// alias that the unbounded model does not report.
//
// A CUT IS COUNTED, NOT HIDDEN. The summarization loses information, and the
// number of times it lost information is in the result.

///|
/// The points-to relation over access paths: a POINTER to the set of PATHS it
/// may reach.
///
/// THE KEY IS A POINTER AND THE VALUE IS A PATH, and that is the whole difference
/// from the allocation-site model. There, the key is a variable or an
/// object-field ("o1.f") and the value is a set of OBJECTS named by their
/// allocation site ("o1"). Here the key is a variable or an access path
/// ("x.f") and the value is a set of PATHS named by their root ("x", "x.f").
pub type SsPts = Map[String, Map[String, Bool]]

///|
/// The depth of an access path: the number of indirections from its root.
///
/// `x` has depth 0, `x.f` has depth 1, `x.f.g` has depth 2. It is the number the
/// survey's k-limiting predicate asks about (p.12), and it is counted by
/// SEGMENTS: the paths are built by `ss_extend` and nowhere else, so a field
/// name containing a dot cannot occur.
pub fn ss_depth(path : String) -> Int32 {
  path.split(".").to_array().length() - 1
}

///|
/// The root of an access path: the variable it is rooted at.
pub fn ss_root(path : String) -> String {
  path.split(".").to_array()[0].to_owned()
}

///|
/// Extend an access path by one field, UNDER THE k-LIMITING SUMMARIZATION.
///
/// THE CUT IS THE SURVEY'S SELF LOOP (p.9): an extension past the bound does not
/// create a new path, because "heap nodes beyond two indirections are not
/// stored" and "a self loop is created on the second indirection". So the
/// location at the bound stands for itself, and the extension is CUT.
///
/// THE SECOND RETURN VALUE IS WHETHER THE EXTENSION WAS CUT, because a
/// summarization that loses information silently is a summarization that cannot
/// be talked about. The caller COUNTS the cuts.
pub fn ss_extend(path : String, field : String, k : Int32) -> (String, Bool) {
  if ss_depth(path) >= k {
    (path, true)
  } else {
    (path + "." + field, false)
  }
}

///|
/// The empty path set.
pub fn ss_set_empty() -> Map[String, Bool] {
  name_set_empty()
}

///|
/// A one-path set.
pub fn ss_set_one(path : String) -> Map[String, Bool] {
  let out : Map[String, Bool] = Map([])
  out.set(path, true)
  out
}

///|
/// The paths a pointer may reach; empty when it has none.
pub fn ss_of(pts : SsPts, key : String) -> Map[String, Bool] {
  match pts.get(key) {
    Some(s) => s
    None => name_set_empty()
  }
}

///|
/// Join a set of paths into a pointer's set. TRUE when the set grew.
///
/// WEAKLY, like the allocation-site model's join: every conclusion is joined in
/// and nothing is ever removed, because the analysis is flow-INSENSITIVE (deck
/// p.55) and one map per function is the whole state.
pub fn ss_join(pts : SsPts, key : String, add : Map[String, Bool]) -> Bool {
  if add.length() == 0 {
    return false
  }
  let cur = ss_of(pts, key)
  if name_set_subtract(add, cur).length() == 0 {
    return false
  }
  pts.set(key, name_set_union(cur, add))
  true
}

///|
/// MAY two access paths denote the same location?
///
/// EQUAL PATHS DO. And under the k-limiting summarization a path DEEPER than the
/// bound is merged into the location at the bound -- the survey's self loop
/// (p.9) -- so a deeper path may denote the same location as its prefix. That
/// merge is where the survey's SPURIOUS ALIASES come from, and this predicate is
/// where they are visible.
pub fn ss_same(p : String, q : String, k : Int32) -> Bool {
  if p == q {
    return true
  }
  if ss_depth(q) > k && q.has_prefix(p + ".") {
    return true
  }
  if ss_depth(p) > k && p.has_prefix(q + ".") {
    return true
  }
  false
}

///|
/// Alias information DERIVED from the reach relation, the way deck p.29 derives
/// it from points-to: two pointers alias when they may reach the same location.
///
/// THE k IS A PARAMETER and not a field of the relation, because the relation
/// does not know the bound: the bound is a property of the SUMMARIZATION, and
/// two runs with different bounds are two readings of the same model.
pub fn ss_alias(pts : SsPts, a : String, b : String, k : Int32) -> Bool {
  let right = ss_of(pts, b)
  for p, _ in ss_of(pts, a) {
    for q, _ in right {
      if ss_same(p, q, k) {
        return true
      }
    }
  }
  false
}

///|
/// MAY the pointer `a` reach the location the NAMED PATH denotes?
///
/// THIS IS THE SURVEY'S SPURIOUS-ALIAS QUESTION, which is about a path and not
/// about two pointers: the survey's own example is "x.f.f.f and y are spuriously
/// marked as aliases at Out6" (p.9), and `x.f.f.f` is a PATH. So the question is
/// asked in that shape here.
pub fn ss_alias_at(pts : SsPts, a : String, path : String, k : Int32) -> Bool {
  for p, _ in ss_of(pts, a) {
    if ss_same(p, path, k) {
      return true
    }
  }
  false
}

///|
/// The state one function's storeless analysis carries.
///
/// THE CUT COUNTER IS AN ARRAY, and the reason is a language fact rather than a
/// style choice: a `Map` and an `Array` are REFERENCE types, so a counter in an
/// array is SHARED by every copy of the struct that holds it, while a `mut`
/// field of a struct is not shared through a by-value parameter. The counter has
/// to be bumped from the bottom of the expression walk, so it has to be shared.
priv struct SsState {
  /// The points-to relation over access paths.
  pts : SsPts
  /// The k-limiting bound: the survey's predicate is about a location "at most k
  /// indirections from a root variable" (p.12).
  k : Int32
  /// The extensions the summarization CUT, keyed by the site.
  ///
  /// IT IS A SET AND NOT A COUNTER, and the reason is the fixed point: the rules
  /// are applied once per SWEEP until nothing changes, so a counter would report
  /// the number of SWEEPS a cut appeared in rather than the number of cuts in the
  /// program. A set of sites is a property of the PROGRAM and the bound.
  cuts : Map[String, Bool]
}

///|
/// What one storeless run produced.
pub(all) struct SsResult {
  /// One relation per function, the same shape the allocation-site model has
  /// (`pta_run`).
  states : Array[SsPts]
  /// The number of extensions the summarization cut, over the whole run.
  cuts : Int32
}

///|
/// The paths an expression may reach.
///
/// A LITERAL IS NOT IN THIS DOMAIN. The survey's access paths are "V x F*" (p.7)
/// -- a ROOT VARIABLE followed by fields -- and a string literal is neither a
/// root variable nor a field of one. So a literal contributes NOTHING here,
/// while the allocation-site model DOES put literals in a points-to set (deck
/// p.59 prints `o1.f -> {"x"}`). That is a difference BETWEEN THE MODELS and it
/// is stated rather than smoothed over: it is the sound direction for a
/// may-analysis, and it is why the two models' alias answers are compared on
/// programs that do not read literals.
fn ss_of_expr(st : SsState, e : @ast.Expr) -> Map[String, Bool] {
  match e.kind {
    @ast.EName(x) => ss_of(st.pts, x)
    @ast.EField(b, f) => ss_field_pts(st, ss_of_expr(st, b), f)
    // Deck p.86: indexes are ignored; the whole array is one field.
    @ast.EIndex(b, _) => ss_field_pts(st, ss_of_expr(st, b), "arr")
    _ => name_set_empty()
  }
}

///|
/// The paths `base.f` reaches, for every path in `base` -- the extension of
/// each path by one field, under the summarization.
fn ss_field_pts(
  st : SsState,
  base : Map[String, Bool],
  f : String,
) -> Map[String, Bool] {
  let out : Map[String, Bool] = Map([])
  for p, _ in base {
    let (ext, cut) = ss_extend(p, f, st.k)
    if cut {
      ss_mark_cut(st, "load:" + p + "." + f)
    }
    for q, _ in ss_of(st.pts, ext) {
      out.set(q, true)
    }
  }
  out
}

///|
/// Record that an extension was CUT, keyed by the site it happened at.
fn ss_mark_cut(st : SsState, site : String) -> Unit {
  st.cuts.set(site, true)
}

///|
/// Apply the four rules at one node, WEAKLY: every conclusion is joined into
/// the pointer's set and nothing is ever removed.
///
/// THE NEW RULE NAMES THE FRESH LOCATION BY THE PATH ROOTED AT THE VARIABLE,
/// and not by an allocation site. That is the difference between the two models
/// and it is the survey's: "allocation site" is a SUMMARIZATION (p.11 section 2)
/// and this cell is the model WITHOUT it. A tree that named the fresh location
/// "o1" here would be the allocation-site model wearing the storeless model's
/// clothes.
fn ss_step(st : SsState, cfgs : Array[Cfg], fi : Int32, v : Int32) -> Bool {
  let kind = cfgs[fi].kinds[v]
  let mut changed = false
  match pta_alloc_of(kind) {
    Some(inits) => {
      // New, plus the initialisers-as-stores extension the tree already makes.
      let name = pta_bound_name(kind)
      if ss_join(st.pts, name, ss_set_one(name)) {
        changed = true
      }
      for pair in inits {
        let (fld, e) = pair
        let (dest, cut) = ss_extend(name, fld, st.k)
        if cut {
          ss_mark_cut(st, fi.to_string() + ":" + name + "." + fld)
        }
        if ss_join(st.pts, dest, ss_of_expr(st, e)) {
          changed = true
        }
      }
    }
    None =>
      match kind {
        Assign(x, e) =>
          if ss_join(st.pts, x, ss_of_expr(st, e)) {
            changed = true
          }
        Store(x, e) =>
          if ss_join(st.pts, x, ss_of_expr(st, e)) {
            changed = true
          }
        // Store THROUGH a field: `x.f = y` is the deck's Store rule, and the
        // path it writes is the EXTENSION of every path x may reach.
        PlaceStore(target, e) =>
          match target.kind {
            @ast.EField(b, fld) => {
              let dest = ss_of_expr(st, b)
              let src = ss_of_expr(st, e)
              for p, _ in dest {
                let (d, cut) = ss_extend(p, fld, st.k)
                if cut {
                  ss_mark_cut(st, fi.to_string() + ":" + p + "." + fld)
                }
                if ss_join(st.pts, d, src) {
                  changed = true
                }
              }
            }
            @ast.EIndex(b, _) => {
              let dest = ss_of_expr(st, b)
              let src = ss_of_expr(st, e)
              for p, _ in dest {
                let (d, cut) = ss_extend(p, "arr", st.k)
                if cut {
                  ss_mark_cut(st, fi.to_string() + ":" + p + ".arr")
                }
                if ss_join(st.pts, d, src) {
                  changed = true
                }
              }
            }
            _ => ()
          }
        _ => ()
      }
  }
  changed
}

///|
/// ONE SWEEP of the four rules over ONE function's relation.
///
/// THE RULES LIVE HERE AND NOWHERE ELSE, the same contract `pta_sweep` has: a
/// sweep is ONE PASS over the function's nodes, and the fixed point is the
/// caller's loop.
fn ss_sweep(st : SsState, cfgs : Array[Cfg], fi : Int32) -> Bool {
  let mut changed = false
  let mut v = 0
  while v < cfgs[fi].kinds.length() {
    if ss_step(st, cfgs, fi, v) {
      changed = true
    }
    v = v + 1
  }
  changed
}

///|
/// The whole-program flow-insensitive fixpoint over the access-path domain:
/// ONE RELATION PER FUNCTION, many sweeps.
///
/// THE SHAPE IS `pta_run`'s, and for `pta_run`'s reason: a pointer's key is a
/// NAME, so one shared relation would make `p` in one function and `p` in another
/// the same pointer, and `ss_alias` would report an alias between two locals
/// that cannot alias.
pub fn ss_run(cfgs : Array[Cfg], k : Int32) -> SsResult {
  let states : Array[SsPts] = []
  let cuts : Map[String, Bool] = Map([])
  let mut fi = 0
  while fi < cfgs.length() {
    let st = SsState::{ pts: Map([]), k, cuts, }
    let mut changed = true
    while changed {
      changed = ss_sweep(st, cfgs, fi)
    }
    states.push(st.pts)
    fi = fi + 1
  }
  { states, cuts: cuts.length(), }
}

///|
/// A dump of the relation, one line per pointer, so a test can assert a table
/// as text.
///
/// THE ORDER IS SHORTLEX, like `pta_text`'s, and for the same reason: the
/// toolchain's `Compare for String` is shortlex (length first), so a reader
/// comparing this dump with another should match the ENTRIES, not their order.
pub fn ss_text(pts : SsPts) -> String {
  let keys : Array[String] = []
  for k, _ in pts {
    if ss_of(pts, k).length() > 0 {
      keys.push(k)
    }
  }
  keys.sort()
  let parts : Array[String] = []
  for k in keys {
    let paths : Array[String] = []
    for p, _ in ss_of(pts, k) {
      paths.push(p)
    }
    paths.sort()
    parts.push(k + " -> {" + paths.join(",") + "}")
  }
  parts.join("; ")
}

///|
/// The DEEPEST path the relation holds, over its keys and its values.
///
/// IT IS A MEASUREMENT OF THE MODEL AND NOT OF THE PROGRAM, and it is what says
/// how much of the summarization the rule system can exercise. The keys are the
/// POINTERS -- a variable, or a field pointer -- and the values are the LOCATIONS
/// they may reach. So this number is "how deep does a pointer name get, and how
/// deep does a location get", and the second half is the one that says whether
/// the k-limiting can ever cut a VALUE.
pub fn ss_deepest(pts : SsPts) -> Int32 {
  let mut deepest = 0
  for k, _ in pts {
    let d = ss_depth(k)
    if d > deepest {
      deepest = d
    }
    for p, _ in ss_of(pts, k) {
      let d2 = ss_depth(p)
      if d2 > deepest {
        deepest = d2
      }
    }
  }
  deepest
}

///|
/// The deepest path among the VALUES only -- the locations the pointers reach.
///
/// THIS IS THE NUMBER THAT SAYS WHETHER THE k-LIMITING CAN CUT A VALUE, and in
/// this rule system it is ZERO, for a reason worth stating: a value is always
/// the ROOT of the location it names, because the New rule names the fresh
/// location by the path rooted at the variable. So the paths deeper than a root
/// are the FIELD-POINTER NAMES, and a name is not a value.
pub fn ss_value_deepest(pts : SsPts) -> Int32 {
  let mut deepest = 0
  for k, _ in pts {
    for p, _ in ss_of(pts, k) {
      let d = ss_depth(p)
      if d > deepest {
        deepest = d
      }
    }
  }
  deepest
}

///|
/// THE TWO HEAP ABSTRACTIONS SIDE BY SIDE: how many alias verdicts they agree
/// on, and how many they do not.
///
/// THIS IS A MEASUREMENT AND NOT A THEOREM. The two models answer the SAME
/// QUESTION -- "may these two pointers reach the same location?" -- in
/// different vocabularies, and the survey's own taxonomy says they are two
/// different models of the same heap (p.6). Whether they AGREE is a fact about
/// the program, and the answer is counted here rather than asserted.
///
/// THE NAMES ARE VARIABLES, because the alias question is asked about variables
/// in both models; a field pointer is named differently in each ("o1.f" against
/// "x.f") and comparing those would compare the two NAMINGS rather than the two
/// answers.
pub fn ss_agree(
  ss : SsPts,
  sb : Pta,
  names : Array[String],
  k : Int32,
) -> (Int32, Int32) {
  let mut same = 0
  let mut differ = 0
  let mut i = 0
  while i < names.length() {
    let mut j = i + 1
    while j < names.length() {
      let a = ss_alias(ss, names[i], names[j], k)
      let b = pta_alias(sb, names[i], names[j])
      if a == b {
        same = same + 1
      } else {
        differ = differ + 1
      }
      j = j + 1
    }
    i = i + 1
  }
  (same, differ)
}
