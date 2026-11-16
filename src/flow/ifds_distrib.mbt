// 0599: THE DISTRIBUTIVITY BOUNDARY -- where IFDS stops, measured on the
// analyses this tree already has.
//
// THE DECK. `CFL-Reachability and IFDS` (Yue Li, Nanjing University, 2021),
// CHAPTER 6 (p.155-172) is "Understanding the Distributivity of IFDS". Its two
// questions are on p.156-157:
//
//   Can we do constant propagation using IFDS?
//   Can we do pointer analysis using IFDS?
//
// AND THE DECK'S DEFINITION, p.158:
//
//   Distributivity
//   F(x ^ y) = F(x) ^ F(y)
//
// with the constant-propagation example `z = x + y` and the sentence "z's
// value depends on both y's and x's".
//
// AND THE DECK'S RULE, p.162, verbatim:
//
//   Given a statement S, besides S itself, if we need to consider multiple
//   input data facts to create correct outputs, then the analysis is not
//   distributive and should not be expressed in IFDS.
//
//   In IFDS, each data fact (circle) and its propagation (edges) could be
//   handled independently, and doing so will not affect the correctness of
//   the final results.
//
// AND p.160 states the question the rule answers:
//
//   Each flow function in IFDS handles one input data fact per time.
//   Each representation relation indicates "if x exists, then ...", "if y
//   exists then ..." But when we need "if both x and y exist", how to draw the
//   representation relation?
//
// AND p.161 gives constant propagation's own answer:
//
//   For constant propagation, we cannot define F if we only know x's (or y's)
//   value
//
// AND THE DECK ASKS ITS OWN HARDER QUESTION, p.164, and it is the one this
// increment answers with a measurement rather than a summary:
//
//   Regardless of the infinite domain issue, think about whether we could do
//   linear constant propagation, e.g., y = 2x + 3, or copy constant
//   propagation, e.g., x = 2, y = x, using IFDS-style analysis?
//
// AND THE POINTER-ANALYSIS CLAIM, p.171-172, on the program
//
//   x = new T
//   y = x
//   x.f = x
//   z = y.f
//
//   z and y.f should have pointed to object [new T]. However, flow function's
//   input data facts lack of the alias information, alias(x,y), alias(x.f,y.f),
//   and we need alias information to produce correct outputs.
//
//   Note: If we want to obtain alias information in IFDS, say alias(x,y), to
//   produce correct outputs, we need to consider multiple input data facts, x
//   and y, which cannot be done in standard IFDS as flow functions handle
//   input facts independently (one fact per time). Thus pointer analysis is
//   non-distributive.
//
// AND THIS TREE HAS BOTH ANALYSES -- `cprop.mbt` and `pta.mbt` -- so the
// boundary is a MEASUREMENT and not a description.
//
// THE TEST IS THE DECK'S OWN ALGEBRA, IN BOTH HALVES. The deck's rule is
//
//   F(x ^ y) = F(x) ^ F(y)
//
// so the question is not "does the transfer read two names" but "is the output
// the join of the outputs each fact produces alone". THAT IS WHAT IS MEASURED
// HERE, and the two halves are measured the SAME WAY, because a distributivity
// claim that is checked two different ways is two claims.
//
// AND THE FACTS ARE THE ANALYSIS'S OWN. For constant propagation a fact is a
// (name, value) pair; for pointer analysis a fact is a (pointer, object) pair,
// because a pointer with two objects carries two of them. The tree's own
// `cprop` state and its own `pta` map are the states the test runs on: this is
// not a new analysis, it is the distributivity test applied to the two
// analyses that already exist.

///|
/// THE WHOLE-STATE OUTPUT AND THE JOIN OF THE ONE-FACT OUTPUTS, for one node.
///
/// AND IT RETURNS BOTH, because a verdict and a report that compute them
/// separately are two answers waiting to disagree: the report prints numbers
/// and the verdict compares them, and the two must be the same numbers.
fn cprop_whole_and_apart(
  kinds : Array[NodeKind],
  node : Int32,
  st : State,
) -> (State, State) {
  let lat = cprop_lattice()
  let f = cprop_node_transfer(kinds)
  let reads = node_uses(kinds[node])
  let defs = node_defs(kinds[node])
  let whole = f(node, st)
  // A STATEMENT THAT READS NO FACT CANNOT NEED TWO, and a statement that
  // DEFINES NO FACT CREATES NO OUTPUT. Both are the deck's rule applied to
  // its own wording ("to create correct outputs"), not a way of dodging the
  // measurement: the deck's example `z = x + y` reads two and defines one, so
  // it is inside the tested subset and nothing is dodged.
  if reads.length() == 0 || defs.length() == 0 {
    return (whole, whole)
  }
  let mut apart = (lat.bot)()
  for name, _ in reads {
    // THE ONE-FACT STATE: the state with the OTHER READ FACTS dropped.
    //
    // AND ONLY THE READ FACTS ARE DROPPED. The state may carry names this
    // node does not read, and dropping them would change the state without
    // changing the question. The facts the transfer CONSUMES are the ones
    // under test.
    let mut one = st
    for other, _ in reads {
      if other != name {
        one = cprop_kill(one, other)
      }
    }
    apart = (lat.join)(apart, f(node, one))
  }
  (whole, apart)
}

///|
/// THE DISTRIBUTIVITY TEST for constant propagation: does this node's output
/// need more than one input fact?
///
/// AND THE ANSWER IS THE DECK'S ALGEBRA, evaluated on the tree's own
/// transfer: `F(x ^ y)` against `F(x) ^ F(y)`. When they differ, the node
/// needed more than one fact, and the deck's p.162 rule says the analysis is
/// not distributive at that node.
pub fn cprop_distributes(
  kinds : Array[NodeKind],
  node : Int32,
  st : State,
) -> Bool {
  let (whole, apart) = cprop_whole_and_apart(kinds, node, st)
  let defs = node_defs(kinds[node])
  for d, _ in defs {
    if cprop_get(whole, d) != cprop_get(apart, d) {
      return false
    }
  }
  true
}

///|
/// THE DISTRIBUTIVITY TEST, printed, for a test that wants to READ the answer
/// rather than take it on trust.
///
/// AND IT PRINTS THE NUMBERS THE VERDICT IS MADE OF: the value the node
/// defines when it is given every fact, the value it gives when it is given
/// one fact at a time, and the number of facts it read.
pub fn cprop_distribution_report(
  kinds : Array[NodeKind],
  node : Int32,
  st : State,
) -> String {
  let (whole, apart) = cprop_whole_and_apart(kinds, node, st)
  let reads = node_uses(kinds[node])
  let defs = node_defs(kinds[node])
  let mut out = "reads=" + reads.length().to_string()
  for name, _ in defs {
    out = out + " " + name + ":all=" + cpv_text(cprop_get(whole, name))
    out = out + " one=" + cpv_text(cprop_get(apart, name))
  }
  out = out + " distributes=" + cprop_distributes(kinds, node, st).to_string()
  out
}

///|
/// THE FACTS OF A POINTS-TO STATE, ONE AT A TIME.
///
/// AND A FACT IS A (POINTER, OBJECT) PAIR and not a pointer: the deck's data
/// facts are the dots on p.166, and a pointer with two objects carries two of
/// them.
fn pta_fact_states(pt : Pta) -> Array[Pta] {
  let out : Array[Pta] = []
  for ptr, objs in pt {
    for obj, _ in objs {
      let inner : Map[String, Bool] = Map([])
      inner.set(obj, true)
      let one : Pta = Map([])
      one.set(ptr, inner)
      out.push(one)
    }
  }
  out
}

///|
/// THE ALIAS RELATION AS A DERIVED FACT, AND WHETHER IT NEEDS TWO FACTS.
///
/// AND THIS IS THE DECK'S p.172 SENTENCE AS AN EXECUTABLE QUESTION. The deck
/// says that to obtain alias information in IFDS "we need to consider multiple
/// input data facts, x and y". So the question is: can the relation be
/// produced from ONE fact? And the relation is the tree's own
/// `pta_alias`, which is the deck's p.29 rule -- two pointers alias when their
/// points-to sets intersect.
///
/// AND THE ANSWER IS MEASURED, NOT ASSUMED: the relation is computed on the
/// whole state and again on each one-fact state, and the two are compared. A
/// relation that holds on the whole state and on no one-fact state is a fact
/// about TWO variables, which is the deck's conclusion.
pub fn pta_alias_distributes(pt : Pta, a : String, b : String) -> Bool {
  let whole = pta_alias(pt, a, b)
  let mut apart = false
  for one in pta_fact_states(pt) {
    if pta_alias(one, a, b) {
      apart = true
    }
  }
  whole == apart
}

///|
/// THE ALIAS RELATION'S DISTRIBUTIVITY, printed.
pub fn pta_alias_distribution_report(
  pt : Pta,
  a : String,
  b : String,
) -> String {
  let whole = pta_alias(pt, a, b)
  let facts = pta_fact_states(pt)
  let mut apart = false
  for one in facts {
    if pta_alias(one, a, b) {
      apart = true
    }
  }
  let mut out = "alias(" + a + "," + b + ")=" + whole.to_string()
  out = out + " facts=" + facts.length().to_string()
  out = out + " one=" + apart.to_string()
  out = out + " distributes=" + (whole == apart).to_string()
  out
}

///|
/// THE LOAD OF A FIELD, AS A TRANSFER OVER THE FACTS.
///
/// AND THE FRAME MAP AND THE HEAP ARE THE SAME MAP, because that is what
/// `pta_run` hands its fixpoint: one map per function, holding both the
/// variables and the field cells. The load `z = y.f` reads the cell `o.f` of
/// every object `y` may point to.
fn pta_load_value(pt : Pta, base : String, field : String) -> Map[String, Bool] {
  let b : @ast.Expr = { span: no_span(), kind: @ast.EName(base), }
  let e : @ast.Expr = { span: no_span(), kind: @ast.EField(b, field), }
  pta_of_expr(pt, pt, e)
}

///|
/// THE LOAD'S DISTRIBUTIVITY: does `z = y.f` need more than one input fact?
///
/// AND THIS IS THE DECK'S p.171 SENTENCE AS AN EXECUTABLE QUESTION: "z and
/// y.f should have pointed to object [new T]. However, flow function's input
/// data facts lack of the alias information ... and we need alias information
/// to produce correct outputs."
///
/// AND THE MEASUREMENT IS THE SAME ALGEBRA AS THE CONSTANT-PROPAGATION HALF:
/// the output on the whole state against the join of the outputs each fact
/// produces alone.
pub fn pta_load_distributes(pt : Pta, base : String, field : String) -> Bool {
  let whole = pta_load_value(pt, base, field)
  let apart : Map[String, Bool] = Map([])
  for one in pta_fact_states(pt) {
    for o, _ in pta_load_value(one, base, field) {
      apart.set(o, true)
    }
  }
  name_set_eq(whole, apart)
}

///|
/// THE LOAD'S DISTRIBUTIVITY, printed.
pub fn pta_load_distribution_report(
  pt : Pta,
  base : String,
  field : String,
) -> String {
  let whole = pta_load_value(pt, base, field)
  let facts = pta_fact_states(pt)
  let apart : Map[String, Bool] = Map([])
  for one in facts {
    for o, _ in pta_load_value(one, base, field) {
      apart.set(o, true)
    }
  }
  let mut out = "load(" + base + "." + field + ")=" + pta_objs_text(whole)
  out = out + " facts=" + facts.length().to_string()
  out = out + " one=" + pta_objs_text(apart)
  out = out + " distributes=" + name_set_eq(whole, apart).to_string()
  out
}

///|
/// A set of objects, as `{o1,o2}`, in the order the tree's own `pta_text`
/// prints them.
fn pta_objs_text(objs : Map[String, Bool]) -> String {
  let names : Array[String] = []
  for o, _ in objs {
    names.push(o)
  }
  names.sort()
  "{" + names.join(",") + "}"
}

///|
/// ONE POINTER'S POINTS-TO SET, as text, in the same spelling as
/// `pta_text`'s own rows.
pub fn pta_points_to_text(pt : Pta, key : String) -> String {
  key + " -> " + pta_objs_text(pta_of(pt, key))
}
