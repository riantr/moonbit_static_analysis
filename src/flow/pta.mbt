// 0547: POINTER ANALYSIS -- which objects can a pointer point to?
//
// THE REFERENCE IS TWO DECKS IN ONE FILE, AND THE SECOND IS ONLY ONE SECTION DEEP.
// This attachment is 104 pages of `Pointer Analysis` from Nanjing University:
//
//   p.1-92    the 2021 lecture by Tian Tan. Its own contents (p.3) lists four
//             sections: 1 Motivation, 2 Introduction to Pointer Analysis, 3 Key
//             Factors of Pointer Analysis, 4 Concerned Statements. Section 4 is
//             p.79-91: what is analysed (p.80-81), pointers in Java (p.82-87), and
//             the FIVE pointer-affecting statements (p.88).
//   p.93-104  a SECOND deck, titled `Foundations (I)` and dated 2020 (p.93). Its
//             own contents (p.94) lists four sections: 1 Rules, 2 How to
//             Implement Pointer Analysis, 3 Algorithms, 4 With Method Calls --
//             and THIS ATTACHMENT CONTAINS ONLY SECTION 1 (p.96-104, ending on
//             the summary table).
//
// So what is implementable from this file is the RULE SYSTEM, not an algorithm
// and not method calls. That is not a gap in the reading; it is what the file
// holds.
//
// THE DECK'S OWN MATH. The domain and the rules are p.97-98:
//
//     Variables   x, y in V          Fields  f, g in F
//     Objects     o_i, o_j in O      Instance fields  o_i.f in O x F
//     Pointers    Pointer = V UNION (O x F)
//     Points-to   pt : Pointer -> P(O)
//
// and four rules, each an implication from premises to a conclusion:
//
//     New     i : x = new T()                 o_i in pt(x)
//     Assign  x = y            o_i in pt(y)   o_i in pt(x)
//     Store   x.f = y          o_i in pt(x), o_j in pt(y)   o_j in pt(o_i.f)
//     Load    y = x.f          o_i in pt(x), o_j in pt(o_i.f)   o_j in pt(y)
//
// The fifth statement kind, `Call` (p.88), is the one the deck withholds here:
// p.96 says of it "will come back to this in pointer analysis with method calls",
// and that section is not in the file.
//
// THE CONFIGURATION IS THE DECK'S, NOT A CHOICE MADE HERE, and it is stitched
// together from FOUR slides rather than read off one. p.48/p.54/p.78 print the
// factor table -- four factors, two alternatives each -- and mark NOTHING; the
// course's choice is marked on the individual factor slides:
//
//     factor              alternative taken        marked on
//     heap abstraction    allocation-site          p.44 "the most commonly-used
//                                                  heap abstraction" (p.45-47
//                                                  is the worked loop example)
//     context sensitivity context-insensitive      p.53 "We start with this"
//     flow sensitivity    flow-insensitive         p.70 "Chosen in this course"
//     analysis scope      whole-program            p.77 "Chosen in this course"
//
// Allocation-site abstraction is what makes the object set finite (p.47: "the
// number of allocation sites in a program is bounded, thus the abstract objects
// must be finite"), which is what makes the fixpoint below terminate. Each factor
// is load-bearing and is named again where it shows up.
//
// AND THIS IS THE FIRST ANALYSIS IN THE PACKAGE THAT IS NOT A GRAPH PROBLEM. The
// three solvers in `worklist.mbt` all take a control-flow graph: a node index
// space, a successor relation, and a transfer indexed by node. Pointer analysis
// does not have that shape. Flow-insensitivity (p.55) means the program is "a set
// of unordered statements", so the CFG's EDGES ARE NOISE; what the analysis
// iterates over is a set of CONSTRAINTS whose edges, in the classic formulation,
// run between POINTERS rather than between program points. So `pta_run` is a
// plain fixpoint over the statement list: it reads the CFGs (they are how this
// tree reaches the statements, and reusing them keeps ONE frontend path) and then
// ignores every successor array in them.
//
// THE ORDERED ARM IS A CONTROL, NOT A SECOND ANALYSIS. The deck spends p.57-69
// contrasting the two readings on one four-statement program and prints BOTH
// answers, marking the flow-insensitive `s` a false positive (p.69).
// `pta_run_ordered` exists so that contrast is a test rather than a claim, and it
// is restricted to STRAIGHT-LINE code: a flow-sensitive field analysis needs
// per-program-point state, which is a different object from the one global map
// the flow-insensitive arm maintains.
//
// WHAT IS MODELLED BESIDE THE DECK'S FOUR RULES. Only ONE of the three items below
// is an extension of this tree's own invention; the other two are forced by the
// deck's own text, and the difference is stated per item because "extension" and
// "requirement" are not the same claim:
//
//   * `new T()` IS A STRUCT LITERAL `T::{ ... }`, AND ITS INITIALISERS ARE
//     STORES. THE EXTENSION. The deck's `new T()` allocates and stops;
//     `A::{ b: v }` allocates and immediately writes `b`. Ignoring that would make
//     the commonest MoonBit construction invisible, so each initialiser becomes a
//     store into the fresh abstract object. Stated as an extension, not folded into
//     p.98's table.
//   * `array[i]` IS ONE FIELD `arr` (p.86). NOT AN EXTENSION -- the deck's own
//     instruction, and the deck itself lists an array element as a pointer (p.85).
//     Indexes are ignored and the whole array is an object with a single field.
//   * A STRING LITERAL IS AN OBJECT. NOT AN EXTENSION EITHER, and the least
//     optional of the three: p.59 prints `o1.f -> {"x"}` and p.61 prints
//     `s -> {"x"}`, so in the deck's own tables a literal sits INSIDE a points-to
//     set. Without this the p.57 program has no answer at all. An un-interpolated
//     literal becomes a constant abstract object keyed by its printed text;
//     interpolated ones are not constants -- their value depends on the names read
//     inside the braces -- and contribute nothing, the sound direction.
//
// WHAT IS NOT MODELLED, NAMED RATHER THAN LEFT TO BE DISCOVERED.
//
//   * Calls (`r = x.k(a, ...)`) are the FIFTH statement kind on p.88, spelled out
//     as static / special / virtual calls on p.90-91, and then explicitly set
//     aside: p.96 says "will come back to this in pointer analysis with method
//     calls", a section this attachment does not contain. So no interprocedural
//     edge is drawn and nothing is passed into or out of a call: a call's result is
//     a value this analysis knows nothing about. That is the sound direction for a
//     may-analysis (we claim fewer points-to facts, never false ones), and it is
//     why `pta_run` hands back ONE MAP PER FUNCTION rather than one map for all of
//     them -- see its own comment, where a shared map is shown to invent an alias
//     between two unrelated locals.
//   * Numeric, float, and bool literals are NOT objects, even though a string
//     literal is. Nothing in this attachment puts a number in a points-to set, and
//     a rule added because it looks symmetric with a rule that is on the page is a
//     rule with no page behind it. The cost is precision, not soundness.

///|
/// The points-to map: a pointer key to the set of objects it may point to.
///
/// The key is a variable NAME for `x`, and `o1.f` for an instance field -- the
/// two halves of the deck's `Pointer = V UNION (O x F)` (p.97). Object keys are
/// `o1`, `o2`, ... named the way the deck names them -- by the allocation site's
/// own statement label; see `pta_site_names`.
pub type Pta = Map[String, Map[String, Bool]]

///|
/// The empty points-to map: every pointer with no entry points to nothing.
pub fn pta_empty() -> Pta {
  Map([])
}

///|
fn pta_one(obj : String) -> Map[String, Bool] {
  let out : Map[String, Bool] = Map([])
  out.set(obj, true)
  out
}

///|
/// The points-to set of a pointer, empty when it has none.
pub fn pta_of(pt : Pta, key : String) -> Map[String, Bool] {
  match pt.get(key) {
    Some(s) => s
    None => name_set_empty()
  }
}

///|
/// Add one object to a pointer's set; true when anything changed.
fn pta_add(pt : Pta, key : String, obj : String) -> Bool {
  let cur = pta_of(pt, key)
  if cur.contains(obj) {
    return false
  }
  pt.set(key, name_set_union(cur, pta_one(obj)))
  true
}

///|
/// Add a set to a pointer's set; true when anything changed.
///
/// TERMINATION LIVES IN THIS SIGNATURE. Sets only ever grow, and the object set is
/// finite because allocation-site abstraction collapses every concrete object
/// allocated by one site into one abstract object (p.44-47). Without that
/// abstraction a loop that allocates could produce unboundedly many objects and
/// this loop would not stop -- which is what p.40 says the abstraction is for.
pub fn pta_join(pt : Pta, key : String, add : Map[String, Bool]) -> Bool {
  if add.length() == 0 {
    return false
  }
  let cur = pta_of(pt, key)
  if name_set_subtract(add, cur).length() == 0 {
    return false
  }
  pt.set(key, name_set_union(cur, add))
  true
}

///|
/// The field pointers `o.f` for every `o` in `base` -- the deck's `o_i.f`,
/// computed for all candidates at once because a may-analysis keeps them all.
fn pta_field_pts(
  pt : Pta,
  base : Map[String, Bool],
  f : String,
) -> Map[String, Bool] {
  let out : Map[String, Bool] = Map([])
  for o, _ in base {
    for obj, _ in pta_of(pt, o + "." + f) {
      out.set(obj, true)
    }
  }
  out
}

///|
/// The points-to set of an expression.
///
/// ANYTHING ELSE IS EMPTY, AND THAT IS THE SOUND DIRECTION: this is a may-analysis
/// (p.17), so a value the analysis does not model contributes no objects rather
/// than an invented one.
pub fn pta_of_expr(pt : Pta, e : @ast.Expr) -> Map[String, Bool] {
  match e.kind {
    @ast.EName(x) => pta_of(pt, x)
    @ast.EField(b, f) => pta_field_pts(pt, pta_of_expr(pt, b), f)
    // p.86: indexes are ignored; the whole array is one field.
    @ast.EIndex(b, _) => pta_field_pts(pt, pta_of_expr(pt, b), "arr")
    // The header's third bullet: p.59 puts `"x"` inside a points-to set, so a
    // literal is an object. The key is the literal as PRINTED, quotes included,
    // because that is the text the deck's own table shows.
    @ast.EStr(v, refs) =>
      if refs.length() == 0 {
        pta_one("\"" + v + "\"")
      } else {
        name_set_empty()
      }
    _ => name_set_empty()
  }
}

///|
/// The initialisers of an allocation site, if this node is one.
///
/// NO CONSTRUCTED TYPE IS KEPT, AND THAT IS THE ABSTRACTION TALKING. Allocation
/// -site abstraction (p.44) identifies an abstract object by the SITE that made
/// it, not by what it is: two `A::{...}` expressions at two lines are two objects,
/// and one object carries no more type information than its line does. Carrying a
/// `ty` nobody reads would be a field the analysis pretends to use.
///
/// `let x = T::{...}` and `x = T::{...}` both allocate -- a declaration and a
/// re-assignment each produce a fresh object. No other kind can be a site, because
/// a call that happens to return a fresh object is exactly what this analysis does
/// not model.
///
/// 0576: this is PUBLIC for the same reason `pta_bound_name` is -- the storeless
/// model asks the same AST question and must not answer it a second time.
pub fn pta_alloc_of(kind : NodeKind) -> Array[(String, @ast.Expr)]? {
  let e = match kind {
    Assign(_, e) => e
    Store(_, e) => e
    _ => return None
  }
  match e.kind {
    @ast.EStruct(_, inits) => Some(inits)
    _ => None
  }
}

///|
/// The object key of an allocation site; `""` when the site was not ranked, which
/// cannot happen because `pta_site_names` names exactly the nodes this reads.
fn pta_site_of(sites : Map[String, String], fi : Int32, node : Int32) -> String {
  match sites.get(fi.to_string() + ":" + node.to_string()) {
    Some(k) => k
    None => ""
  }
}

///|
/// Strict order over a `(line, column, tie-break, tie-break)` key: true when the
/// FIRST tuple comes after the second.
///
/// WRITTEN AS A FUNCTION BECAUSE THE FIRST VERSION OF THIS SORT WAS BACKWARDS. The
/// comparison was spelled `cur > prev` inside a loop that shifts while the
/// comparison holds, which sorts DESCENDING -- it would have ranked the deck's
/// four-statement program `o4, o3, o2, o1` and every object name in every test
/// would have been wrong. Sorting by "is the element already in the list after the
/// one I am inserting" is the version that cannot be written wrong, because the
/// shifted element is the first argument.
fn pta_after(
  l1 : Int32,
  c1 : Int32,
  t1 : Int32,
  i1 : Int32,
  l2 : Int32,
  c2 : Int32,
  t2 : Int32,
  i2 : Int32,
) -> Bool {
  // THE `(line, column)` PART IS NOT RE-DERIVED HERE: `source_after` owns it,
  // and it is the same comparison the basic-block layer uses (0551), because
  // two definitions of "which position is later" is one more than can stay in
  // agreement.
  if source_after(l1, c1, l2, c2) {
    return true
  }
  if l1 != l2 || c1 != c2 {
    return false
  }
  if t1 != t2 {
    return t1 > t2
  }
  i1 > i2
}

///|
/// Give every allocation site the deck's own object name.
///
/// THE NAME IS THE STATEMENT'S LABEL, AND IN EVERY PRINTED TABLE THAT LABEL IS THE
/// LINE NUMBER. p.98 writes the New rule as `i : x = new T()  =>  o_i in pt(x)`,
/// and the labels in the deck's examples are line numbers:
///
///     p.45-47   the loop body's `a = new A()` is on LINE 2  ->  the object is o2
///     p.57      `c = new C()` is on LINE 1                  ->  o1
///     p.77      `x = new A()` line 1 and `z = new T()` line 4 -> o1 and o4
///
/// SO RANKING SITES `o1, o2, ...` IN ORDER OF APPEARANCE WOULD BE WRONG -- this
/// file was written that way first, and it reproduces the p.57 table by luck (one
/// site, line 1) while printing `o2` for p.77's `z` and `o1` for p.45-47's `a`,
/// both of which the deck prints differently. Measured against the slides, not
/// assumed.
///
/// TWO SITES ON ONE LINE HAVE NO PAGE BEHIND THEM, and the fallback is named as
/// this tree's invention rather than presented as the deck's: the first site on a
/// line keeps `o<line>` and each later one on the same line becomes
/// `o<line>_<k>`, numbered in source-column order. A hand-built graph whose spans
/// are all line 0 therefore collapses onto `o0`, `o0_2`, ... which is how that
/// trap announces itself instead of silently aliasing two objects.
///
/// 0575: this is PUBLIC because the context-sensitive and the demand-driven
/// pointer analyses need the SAME naming -- an object named `o4` in one
/// analysis and `o7` in the other would make the two columns incomparable, and
/// the deck compares them.
pub fn pta_site_names(cfgs : Array[Cfg]) -> Map[String, String] {
  let fi_of : Array[Int32] = []
  let node_of : Array[Int32] = []
  let line_of : Array[Int32] = []
  let col_of : Array[Int32] = []
  let mut fi = 0
  while fi < cfgs.length() {
    let g = cfgs[fi]
    let mut v = 0
    while v < g.kinds.length() {
      if pta_alloc_of(g.kinds[v]) is Some(_) {
        fi_of.push(fi)
        node_of.push(v)
        line_of.push(g.spans[v].start.line)
        col_of.push(g.spans[v].start.col)
      }
      v = v + 1
    }
    fi = fi + 1
  }
  let order : Array[Int32] = []
  let mut i = 0
  while i < fi_of.length() {
    order.push(i)
    i = i + 1
  }
  // Insertion sort into SOURCE order. It is needed for the collision numbering
  // above, not for the object names themselves.
  let mut a = 1
  while a < order.length() {
    let cur = order[a]
    let mut b = a - 1
    let mut placed = false
    while b >= 0 && !placed {
      let prev = order[b]
      if pta_after(
          line_of[prev],
          col_of[prev],
          fi_of[prev],
          node_of[prev],
          line_of[cur],
          col_of[cur],
          fi_of[cur],
          node_of[cur],
        ) {
        order[b + 1] = prev
        b = b - 1
      } else {
        placed = true
      }
    }
    order[b + 1] = cur
    a = a + 1
  }
  let sites : Map[String, String] = Map([])
  let mut prev_line = -1
  let mut k = 0
  let mut r = 0
  while r < order.length() {
    let idx = order[r]
    let line = line_of[idx]
    if line == prev_line {
      k = k + 1
    } else {
      prev_line = line
      k = 1
    }
    let key = fi_of[idx].to_string() + ":" + node_of[idx].to_string()
    if k == 1 {
      sites.set(key, "o" + line.to_string())
    } else {
      sites.set(key, "o" + line.to_string() + "_" + k.to_string())
    }
    r = r + 1
  }
  sites
}

///|
/// The name a node binds, for a node `pta_alloc_of` accepted. Only `Assign` and
/// `Store` can be accepted, so the fallback is unreachable; it is written because
/// this tree's exhaustiveness checking does not know that.
///
/// 0576: this is PUBLIC because the storeless model asks the SAME AST question --
/// "is this node an allocation, and what does it bind?" -- and a second answer to
/// it would be a second definition of what an allocation site is.
pub fn pta_bound_name(kind : NodeKind) -> String {
  match kind {
    Assign(x, _) => x
    Store(x, _) => x
    _ => ""
  }
}

///|
/// Apply the deck's four rules at one node, WEAKLY: every conclusion is joined
/// into the pointer's set and nothing is ever removed. That is what
/// flow-insensitivity means (p.55): one map for the whole program, so a later
/// statement can never take back what an earlier one established.
fn pta_step(
  cfgs : Array[Cfg],
  sites : Map[String, String],
  pt : Pta,
  fi : Int32,
  v : Int32,
) -> Bool {
  let kind = cfgs[fi].kinds[v]
  let mut changed = false
  match pta_alloc_of(kind) {
    // New, plus the initialisers-as-stores extension.
    Some(inits) => {
      let obj = pta_site_of(sites, fi, v)
      if pta_add(pt, pta_bound_name(kind), obj) {
        changed = true
      }
      for pair in inits {
        let (fld, e) = pair
        if pta_join(pt, obj + "." + fld, pta_of_expr(pt, e)) {
          changed = true
        }
      }
    }
    None =>
      match kind {
        // Assign, and the load form of it: `s = c.f` is the deck's Load rule, and
        // `pta_of_expr` is what answers the right-hand side either way. It returns
        // empty for anything that is not a pointer expression, which is the sound
        // direction.
        Assign(x, e) =>
          if pta_join(pt, x, pta_of_expr(pt, e)) {
            changed = true
          }
        Store(x, e) => if pta_join(pt, x, pta_of_expr(pt, e)) { changed = true }
        // Store THROUGH a field: `x.f = y` is the deck's Store rule.
        PlaceStore(target, e) =>
          match target.kind {
            @ast.EField(b, fld) => {
              let dest = pta_of_expr(pt, b)
              let src = pta_of_expr(pt, e)
              for o, _ in dest {
                if pta_join(pt, o + "." + fld, src) {
                  changed = true
                }
              }
            }
            @ast.EIndex(b, _) => {
              let dest = pta_of_expr(pt, b)
              let src = pta_of_expr(pt, e)
              for o, _ in dest {
                if pta_join(pt, o + ".arr", src) {
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
/// ONE SWEEP OF THE DECK'S FOUR RULES over ONE function's points-to map.
///
/// THE RULES LIVE HERE AND NOWHERE ELSE. `pta_run` is this function called in a
/// loop until it stops changing; the context-sensitive pointer analysis (0575)
/// calls it too, once per (function, context), because a CONTEXT IS A DIFFERENT
/// MAP and not a different set of rules. One rule, one place -- and the two
/// analyses can then be compared, which is what deck 8's p.74 and p.76 do.
///
/// A sweep is ONE PASS over the function's nodes. The fixed point is the
/// caller's loop, and it terminates because `pta_step` only ever joins.
pub fn pta_sweep(
  cfgs : Array[Cfg],
  sites : Map[String, String],
  pt : Pta,
  fi : Int32,
) -> Bool {
  let mut changed = false
  let mut v = 0
  while v < cfgs[fi].kinds.length() {
    if pta_step(cfgs, sites, pt, fi, v) {
      changed = true
    }
    v = v + 1
  }
  changed
}

///|
/// The whole-program flow-insensitive fixpoint: ONE MAP PER FUNCTION, many sweeps.
///
/// WHY THE MAPS ARE PER FUNCTION AND NOT ONE MAP FOR EVERYTHING. The 2021 deck says
/// "one map of points-to relations for the whole program" (p.55), and copying that
/// literally would be a bug here: a pointer's key is a variable NAME, so one shared
/// map makes `p` in one function and `p` in another the SAME pointer, and
/// `pta_alias` then reports an alias between two locals that cannot alias. That is
/// a false positive by construction, of exactly the kind this tree treats as a
/// defect rather than as the cost of a may-analysis.
///
/// THE RESTRICTION IS THE DECK'S OWN, STATED ON ITS OWN SLIDE. p.96 introduces the
/// rules with "First focus on these statements (suppose the program has just one
/// method)" -- the rule system being implemented here is defined for one method, and
/// the cross-method version is the section on method calls that this attachment does
/// not contain. So "one map per function" is not a simplification of the deck's
/// whole-program map; it is the deck's map, taken once per method, which is the only
/// form the rules as printed can be given when nothing connects two bodies.
///
/// ONE MAP PER FUNCTION, MANY SWEEPS. Because `pta_step` only ever joins, a sweep
/// that changes nothing proves the map is a fixed point of all four rules at once --
/// which is why the CFGs' edge structure does not appear anywhere below.
pub fn pta_run(cfgs : Array[Cfg]) -> Array[Pta] {
  let sites = pta_site_names(cfgs)
  let out : Array[Pta] = []
  let mut fi = 0
  while fi < cfgs.length() {
    let pt = pta_empty()
    let mut changed = true
    while changed {
      changed = pta_sweep(cfgs, sites, pt, fi)
    }
    out.push(pt)
    fi = fi + 1
  }
  out
}

///|
/// The nodes of one graph in SOURCE order -- by (line, column), with the node
/// index only as a tie-break.
///
/// THIS IS THE ORDERED ARM'S ONE HARD PART, and it is hard for a reason worth
/// recording: a CFG's node indices are ALLOCATION order, which `cfg_of` produces
/// by building statement lists back to front, so reading `kinds[0], kinds[1], ...`
/// reads the body backwards. A flow-sensitive reading of a straight-line body has
/// to re-derive source order from the spans.
///
/// THE ORDER IS NOT DERIVED HERE ANY MORE (0551). It was, and the basic-block
/// layer needed the same thing, and two definitions of "the source order of a
/// graph" is one more than can stay in agreement -- so the order now lives with
/// the graph, in `Cfg::source_order`, and this function is gone.
fn pta_source_order(g : Cfg) -> Array[Int32] {
  g.source_order()
}

///|
/// The ORDERED (flow-sensitive) reading, for a STRAIGHT-LINE body.
///
/// WHY THIS EXISTS AT ALL: the deck prints two different answers for one program
/// (p.61 against p.68) and labels the flow-insensitive `s` a false positive
/// (p.69). A comment claiming that would be a claim; this arm plus the test that
/// compares it with `pta_run` is the measurement.
///
/// THE DIFFERENCE IS ONE WORD: STRONG INSTEAD OF WEAK. When a statement writes a
/// pointer, the ordered reading REPLACES its set instead of joining into it, so a
/// store that happens later cannot reach a load that happened earlier. That is
/// only sound for a body with no branches, which is the boundary this function
/// declares: it is given one `Cfg` whose control flow is a straight line, and it
/// reads the nodes in source order.
pub fn pta_run_ordered(g : Cfg) -> Pta {
  let sites = pta_site_names([g])
  let pt = pta_empty()
  let order = pta_source_order(g)
  for v in order {
    let kind = g.kinds[v]
    match pta_alloc_of(kind) {
      Some(inits) => {
        let obj = pta_site_of(sites, 0, v)
        // STRONG: the fresh object is the whole answer for this name here.
        pt.set(pta_bound_name(kind), pta_one(obj))
        for pair in inits {
          let (fld, e) = pair
          pt.set(obj + "." + fld, pta_of_expr(pt, e))
        }
      }
      None =>
        match kind {
          Assign(x, e) => pt.set(x, pta_of_expr(pt, e))
          Store(x, e) => pt.set(x, pta_of_expr(pt, e))
          PlaceStore(target, e) =>
            match target.kind {
              @ast.EField(b, fld) => {
                let dest = pta_of_expr(pt, b)
                let src = pta_of_expr(pt, e)
                for o, _ in dest {
                  pt.set(o + "." + fld, src)
                }
              }
              @ast.EIndex(b, _) => {
                let dest = pta_of_expr(pt, b)
                let src = pta_of_expr(pt, e)
                for o, _ in dest {
                  pt.set(o + ".arr", src)
                }
              }
              _ => ()
            }
          _ => ()
        }
    }
  }
  pt
}

///|
/// Alias information DERIVED from points-to (deck p.29): two pointers alias when
/// their points-to sets intersect. The deck is explicit that alias analysis is a
/// different question with the same answer available from this one, which is why
/// there is no separate alias pass here.
pub fn pta_alias(pt : Pta, a : String, b : String) -> Bool {
  name_set_inter(pta_of(pt, a), pta_of(pt, b)).length() > 0
}

///|
/// A dump of the map, one line per pointer, so a test can assert the deck's table
/// values as text.
///
/// THE ORDER IS SHORTLEX, NOT ALPHABETICAL, and that is a fact about the toolchain
/// rather than about this function. `Array::sort` uses `Compare for String`, which
/// `core/builtin/string.mbt:408-428` defines and documents as "shortlex order by
/// their charcodes": LENGTH first, code units only as the tie-break. So `c` and `s`
/// come out before `o1.f`, and a reader comparing this dump with the deck's tables
/// should match the ENTRIES, not their order -- the first version of the tests in
/// `pta_test.mbt` expected `c; o1.f; s`, having read each slide left to right, and
/// was wrong in the way the stdlib says it must be. Measured rather than assumed:
/// `["aa","b"].sort()` gives `["b","aa"]`.
///
/// An alphabetical comparator could be hand-written, but a dump whose only job is to
/// be asserted against would then carry a second, private idea of what "sorted"
/// means -- one more place a disagreement with the stdlib could hide.
pub fn pta_text(pt : Pta) -> String {
  let keys : Array[String] = []
  for k, _ in pt {
    if pta_of(pt, k).length() > 0 {
      keys.push(k)
    }
  }
  keys.sort()
  let parts : Array[String] = []
  for k in keys {
    let objs : Array[String] = []
    for o, _ in pta_of(pt, k) {
      objs.push(o)
    }
    objs.sort()
    parts.push(k + " -> {" + objs.join(",") + "}")
  }
  parts.join("; ")
}
