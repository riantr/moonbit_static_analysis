// 0572: THE REACHING-DEFINITIONS ANALYSIS -- the third of the deck's three
// applications.
//
// THE DECK. `Data Flow Analysis -- Applications` (Yue Li, Nanjing University),
// p.37-137 teaches three applications: reaching definitions, live variables and
// available expressions. The other two are here -- `live.mbt` and `avail.mbt`
// -- and both of them SPEAK (MSA-015 and MSA-014), so the trio was two thirds
// of a whole before this file.
//
// THE DEFINITION, p.39, verbatim:
//
//   A definition d at program point p reaches a point q if there is a path
//   from p to q such that d is not "killed" along that path.
//
// THE GENERATE AND KILL, p.46, verbatim:
//
//   This statement "generates" a definition D of variable v and "kills" all
//   the other definitions in the program that define variable v, while leaving
//   the remaining incoming definitions unaffected.
//
// THE TRANSFER, p.48:
//
//   OUT[B] = gen_B U (IN[B] - kill_B)
//
// IT IS A MAY ANALYSIS AND A FORWARD ONE, so the join over the neighbours is a
// UNION and the neighbours are the PREDECESSORS. The solver in `worklist.mbt`
// knows neither of those: it joins over whatever neighbours it is handed, and
// `live.mbt` uses the very same solver with the SUCCESSORS for the backward
// direction. So the forward analysis here is the backward one with the other
// array -- which is what `live.mbt`'s header already explains.
//
// WHAT A DEFINITION IS. The deck's definition is "a statement that assigns a
// value to v" (p.40), so a definition is a PAIR -- the variable and the
// statement -- and the sets carry it as the key `name@node`. The node index is
// what makes two definitions of the SAME variable two different definitions,
// which is the whole point of the analysis: `x = 1` and `x = 2` are two
// definitions, and only the one that is not killed can reach a given point.
//
// WHAT A DEFINITION IS NOT. A WRITE THROUGH A PLACE (`x.f = e`, `xs[i] = e`)
// is not a definition of the variable `x`: the deck's rule is stated over
// VARIABLES (p.40), and a field is not the variable. This is the same rule
// `node_defs` states for liveness, and for the same reason.
//
// THE SET OPERATIONS ARE NOT REWRITTEN HERE. The carrier is a set of keys and
// the lattice is a powerset, so the three operations -- the empty set, the
// union and the equality -- are exactly the three `live.mbt` already
// defines over `Map[String, Bool]`. They are reused rather than copied,
// because 0545's own lesson was that a second copy of the same three
// operations is how two definitions of "the set of names" start to disagree.

///|
/// A set of definitions, keyed by `name@node`.
///
/// THE KEY IS A STRING rather than a pair because the carrier has to be
/// `Map[String, Bool]` for the set operations this package already has, and
/// because a variable name cannot contain `@` in MoonBit -- so the key splits
/// unambiguously, and a lookup by variable is a prefix test.
pub type DefSet = Map[String, Bool]

///|
/// The key of the definition a node makes of a variable.
pub fn def_key(name : String, node : Int32) -> String {
  name + "@" + node.to_string()
}

///|
/// The lattice over the sets of definitions: the empty set at the bottom, the
/// union as the join, and equality as equality.
///
/// THE EMPTY SET IS THE BOTTOM because it is the set of definitions that reach
/// nothing, and the deck's own iteration starts every block at the empty set
/// (p.6: "OUT[B] = ∅").
pub fn def_set_lattice() -> Lattice[DefSet] {
  {
    bot: fn() { name_set_empty() },
    join: fn(a, b) { name_set_union(a, b) },
    eq: fn(a, b) { name_set_eq(a, b) },
  }
}

///|
/// A set of definitions, printed in a stable order, for a test that wants to
/// read the answer rather than count it.
pub fn def_set_text(st : DefSet) -> String {
  let ks : Array[String] = []
  for k, _ in st {
    ks.push(k)
  }
  ks.sort()
  ks.join(",")
}

///|
/// The definitions a node GENERATES: the deck's `gen_B`.
///
/// A `let` and a re-assignment are both definitions of the variable, because
/// the deck's rule is "a statement that assigns a value to v" (p.40) and the
/// language has no separate kind for the two -- the tree's CFG does, as
/// `Assign` and `Store`, and both are definitions here. A destructuring
/// assignment defines every name it binds.
pub fn reaching_gen(cfg : Cfg) -> Array[DefSet] {
  let out : Array[DefSet] = []
  let mut v = 0
  while v < cfg.kinds.length() {
    let g = name_set_empty()
    match cfg.kinds[v] {
      Assign(x, _) => g.set(def_key(x, v), true)
      Store(x, _) => g.set(def_key(x, v), true)
      AssignMulti(names, _) =>
        for nm in names {
          g.set(def_key(nm, v), true)
        }
      _ => ()
    }
    out.push(g)
    v = v + 1
  }
  out
}

///|
/// The definitions a node KILLS: the deck's `kill_B`.
///
/// THE RULE IS OVER THE WHOLE FUNCTION, not over the block: the deck says the
/// statement "kills all the other definitions IN THE PROGRAM that define
/// variable v" (p.46), and for an intraprocedural analysis the program is the
/// function. So the universe is every node that defines the variable, and a
/// node kills all of them but its own.
///
/// THE CONSEQUENCE IS WORTH NAMING, because it is what makes the analysis
/// precise: the definitions of `x` that are killed by `x = 1` are the
/// definitions made by every OTHER `x = ...` in the function, and a definition
/// that is killed on one path but not another still reaches.
pub fn reaching_kill(cfg : Cfg) -> Array[DefSet] {
  // THE UNIVERSE: for every variable, the nodes that define it. `node_defs`
  // is this package's own answer to "the names a node defines", and the
  // deck's kill rule is stated over those names.
  let defs_of : Map[String, Array[Int32]] = Map([])
  let mut v = 0
  while v < cfg.kinds.length() {
    for name, _ in node_defs(cfg.kinds[v]) {
      let slot = match defs_of.get(name) {
        Some(s) => s
        None => []
      }
      slot.push(v)
      defs_of.set(name, slot)
    }
    v = v + 1
  }
  let out : Array[DefSet] = []
  let mut i = 0
  while i < cfg.kinds.length() {
    let k = name_set_empty()
    for name, _ in node_defs(cfg.kinds[i]) {
      match defs_of.get(name) {
        Some(nodes) =>
          for m in nodes {
            if m != i {
              k.set(def_key(name, m), true)
            }
          }
        None => ()
      }
    }
    out.push(k)
    i = i + 1
  }
  out
}

///|
/// The transfer function, as a VALUE.
///
/// WHY IT IS EXTRACTED: same reason as `live_transfer` and `avail_transfer`.
/// The solver promises termination and the LEAST fixed point, and both
/// promises rest on this function being MONOTONE (Yue Li, `Data Flow Analysis
/// -- Foundations`, p.115 and p.118). A closure that exists only inside
/// `reaching_out`'s body can be observed through its fixed point and through
/// nothing else, so the property could not be tested.
///
/// IT TAKES THE TWO ARRAYS AS PARAMETERS rather than building them itself,
/// which is the shape `cprop_node_transfer` has: the work that is per-graph
/// is built once, by the caller, and the transfer is the part the solver
/// calls. A parameter that is read only inside the closure it returns is
/// invisible to the lint with the region suppression off -- the mechanism
/// `_verify/release.ps1`'s pin table names for `live_transfer`,
/// `cprop_node_transfer` and `sign_transfer` -- and the pin follows the
/// measurement.
pub fn reaching_transfer(
  gen : Array[DefSet],
  kill : Array[DefSet],
) -> (Int32, DefSet) -> DefSet {
  fn(node, st) {
    let out = name_set_empty()
    for k, _ in st {
      if kill[node].contains(k) == false {
        out.set(k, true)
      }
    }
    for k, _ in gen[node] {
      out.set(k, true)
    }
    out
  }
}

///|
/// `OUT[v]`: the definitions that reach the point AFTER node `v`.
///
/// A FORWARD analysis, so the join-neighbours are the PREDECESSORS, and the
/// solver's convention is the round-robin one -- `state[v]` is the state after
/// `v` -- so the array this returns IS the `OUT` of the deck's notation.
pub fn reaching_out(cfg : Cfg) -> Array[DefSet] {
  solve_round_robin(
    def_set_lattice(),
    cfg.kinds.length(),
    cfg.pred,
    reaching_transfer(reaching_gen(cfg), reaching_kill(cfg)),
  )
}

///|
/// `IN[v]`: the definitions that reach the point BEFORE node `v`.
///
/// THE DISTINCTION IS NOT COSMETIC, and it is the same one `live_out` exists
/// for: a read of `x` in `x = x + 1` sees the OLD `x`, so the question is
/// asked of the state BEFORE the node, not after it.
pub fn reaching_in(cfg : Cfg, out : Array[DefSet]) -> Array[DefSet] {
  let lat = def_set_lattice()
  let ins : Array[DefSet] = []
  let mut v = 0
  while v < cfg.kinds.length() {
    ins.push(join_of_nodes(lat, out, cfg.pred[v]))
    v = v + 1
  }
  ins
}

///|
/// The USE-DEF CHAIN: for every node, the definitions that reach the names it
/// READS.
///
/// THIS IS THE ANALYSIS'S PAYOFF, and it is the thing the other two
/// applications do not give. Liveness says whether a value is ever read;
/// availability says whether an expression was already computed. The use-def
/// chain says WHICH WRITE a read observes, and it is the answer a reader asks
/// when a value is not what they expected.
///
/// A definition reaches a READ when it is in the node's IN-set and it defines
/// the name the read mentions. The read of a name in an assignment's
/// right-hand side is the read of the value BEFORE the assignment -- which is
/// why the IN-set is the state this asks of, and not the OUT-set.
pub fn reaching_use_defs(
  cfg : Cfg,
  ins : Array[DefSet],
) -> Array[Array[String]] {
  let out : Array[Array[String]] = []
  let mut v = 0
  while v < cfg.kinds.length() {
    let mine : Array[String] = []
    for name, _ in node_uses(cfg.kinds[v]) {
      let prefix = name + "@"
      for key, _ in ins[v] {
        if key.has_prefix(prefix) {
          mine.push(key)
        }
      }
    }
    out.push(mine)
    v = v + 1
  }
  out
}
