// 0545: the laws the solvers depend on, checked by ENUMERATION.
//
// WHY THIS FILE EXISTS. `src/flow/lattice.mbt` states the framework's contract
// and then says the hard part is not checkable:
//
//     `join` MUST be an upper bound and MUST be associative and commutative for
//     the solvers to return the least fixed point; `eq` MUST be the equality
//     that agrees with the lattice order. Neither is checkable at this level.
//
// The first half is true -- a `Lattice` is three closures and nothing about them
// can be checked generically. The second half is not, for the lattices this file
// names: their carriers are SETS OF NAMES and SETS OF EXPRESSION KEYS over a
// fixed universe, so over `{a,b,c}` the enumeration below has eight elements,
// a pair space of 64 and a triple space of 512, and every one of those laws is
// decided by trying all of them. That is what this file does.
//
// AND THE BOUNDARY IS STATED RATHER THAN GLOSSED, BECAUSE A BLANKET "EVERY
// LATTICE IN THE PACKAGE" WOULD BE FALSE -- and this tree's own 0529 record says
// so outright: `interval_state_lattice(n)` is the interval domain, whose carrier
// is `[l,h]` over N = Z + {-inf, +inf} (book p.79), and 0529's section is titled
// AN INFINITE-HEIGHT LATTICE because the chain `[0,0] < [0,1] < [0,2]` never
// ends (p.80). That is why that increment needed WIDENING (p.93) instead of
// Kleene iteration, whose theorem assumes finite height (p.47, restated p.82).
// Its laws are not enumerated here and cannot be: what this file checks is the
// two lattices that `live.mbt` and `avail.mbt` solve over.
//
// The property that matters most is not on that list, and the deck devotes a
// section to it (Yue Li, `Data Flow Analysis -- Foundations`; the slides are
// p.115 and p.118-119):
//
//     "OUT never shrinks ... it is about monotonicity"
//     f is monotone if for all x, y in L,  x <= y  implies  f(x) <= f(y)
//
// Both solvers' promises -- that the iteration TERMINATES, and that what it
// reaches is the LEAST fixed point rather than merely a fixed point -- are
// theorems ABOUT A MONOTONE f. Until 0545 nothing measured it for any of this
// package's transfer functions, because each of them existed only as a closure
// inside the body of the function that solved with it. `live_transfer` and
// `avail_transfer` are extracted so the property has a name to call.
//
// AND THE TWO DIRECTIONS ARE BOTH HERE. Live variables is may-and-backward over
// (bottom = empty, join = union); available expressions is must-and-forward over
// (bottom = the whole universe, join = intersection), which is the same carrier
// ordered the other way. The deck's section 8 is titled "May/Must Analysis, A
// Lattice View", and the first test below is that view: the same laws, the same
// enumeration, two orders, and the meet of one is the join of the other by De
// Morgan.
//
// WHY THE HELPERS RETURN A STRING. `assert_eq` carries an error type in this
// toolchain, so it can only be called from a function that declares one; a
// helper that asserted would have to be `raise`-typed, and every call site would
// have to propagate. The helpers here return "" for "no violation" and a
// description of the FIRST violation otherwise, which keeps the assertion at the
// test and keeps the failing pair in the message.

///|
/// `a` is a subset of `b` -- the order of the may lattice.
fn subset_of(a : Map[String, Bool], b : Map[String, Bool]) -> Bool {
  for k, _ in a {
    if b.contains(k) == false {
      return false
    }
  }
  true
}

///|
/// `a` is a SUPERSET of `b` -- the order of the must lattice, i.e. the may order
/// read backwards. The dual of a lattice is the same carrier with this order.
fn superset_of(a : Map[String, Bool], b : Map[String, Bool]) -> Bool {
  subset_of(b, a)
}

///|
/// Every subset of `keys`, in mask order.
fn powerset_of(keys : Array[String]) -> Array[Map[String, Bool]] {
  let out : Array[Map[String, Bool]] = []
  let k = keys.length()
  let total = 1 << k
  let mut mask = 0
  while mask < total {
    let m : Map[String, Bool] = Map([])
    let mut i = 0
    while i < k {
      if ((mask >> i) & 1) == 1 {
        m.set(keys[i], true)
      }
      i = i + 1
    }
    out.push(m)
    mask = mask + 1
  }
  out
}

///|
fn keys_of_set(s : Map[String, Bool]) -> Array[String] {
  let out : Array[String] = []
  for k, _ in s {
    out.push(k)
  }
  out
}

///|
/// `{a,b,c}` -- so that a violation names the pair that caused it.
fn show(s : Map[String, Bool]) -> String {
  let ks = keys_of_set(s)
  ks.sort()
  "{" + ks.join(",") + "}"
}

///|
/// The complement of `a` in `uni`. The De Morgan check below needs it, and it is
/// written here rather than as a package function because no analysis wants it:
/// a must analysis does not complement its carrier, it reads the same carrier
/// backwards.
fn complement_in(
  a : Map[String, Bool],
  uni : Map[String, Bool],
) -> Map[String, Bool] {
  let out : Map[String, Bool] = Map([])
  for k, _ in uni {
    if a.contains(k) == false {
      out.set(k, true)
    }
  }
  out
}

///|
/// THE FIVE LAWS, over an enumerated carrier. Returns "" when they all hold.
///
/// `order` is passed rather than derived from `eq`, because that is the point:
/// `eq` says "the same element", `order` says "no larger than", and the pair has
/// to agree. A `join` that is an upper bound but not the LEAST one computes
/// something else, and the least-upper-bound law is the only one that catches
/// it -- "is an upper bound" alone cannot, because the top of the lattice is one
/// too.
fn laws_violation(
  lat : @flow.Lattice[Map[String, Bool]],
  order : (Map[String, Bool], Map[String, Bool]) -> Bool,
  elems : Array[Map[String, Bool]],
) -> String {
  for a in elems {
    if (lat.eq)((lat.join)(a, a), a) == false {
      return "not idempotent at " + show(a)
    }
    if (lat.eq)((lat.join)((lat.bot)(), a), a) == false {
      return "the bottom is not the identity of the join at " + show(a)
    }
    for b in elems {
      let jab = (lat.join)(a, b)
      if (lat.eq)(jab, (lat.join)(b, a)) == false {
        return "not commutative at " + show(a) + " and " + show(b)
      }
      if order(a, jab) == false {
        return "the join is not an upper bound of its LEFT operand at " +
          show(a) +
          " and " +
          show(b)
      }
      if order(b, jab) == false {
        return "the join is not an upper bound of its RIGHT operand at " +
          show(a) +
          " and " +
          show(b)
      }
      let both = order(a, b) && order(b, a)
      if (both == (lat.eq)(a, b)) == false {
        return "eq and order disagree at " + show(a) + " and " + show(b)
      }
      for c in elems {
        if (lat.eq)((lat.join)(jab, c), (lat.join)(a, (lat.join)(b, c))) ==
          false {
          return "not associative at " +
            show(a) +
            ", " +
            show(b) +
            ", " +
            show(c)
        }
        if order(a, c) && order(b, c) && order(jab, c) == false {
          return "the join is not the LEAST upper bound at " +
            show(a) +
            " and " +
            show(b) +
            " (the witness is " +
            show(c) +
            ")"
        }
      }
    }
  }
  ""
}

///|
/// MONOTONICITY, over an enumerated carrier. Returns "" when it holds.
///
/// Every pair is tried for every node of the graph, because a transfer function
/// is a FAMILY indexed by node rather than one function -- the deck's framework
/// is a triple of a direction, a lattice and a family `F` (p.104) -- and a family
/// is monotone when each of its members is.
fn monotone_violation(
  step : (Int32, Map[String, Bool]) -> Map[String, Bool],
  order : (Map[String, Bool], Map[String, Bool]) -> Bool,
  elems : Array[Map[String, Bool]],
  n : Int32,
) -> String {
  let mut v = 0
  while v < n {
    for x in elems {
      for y in elems {
        if order(x, y) && order(step(v, x), step(v, y)) == false {
          return "node \{v} is not monotone: " +
            show(x) +
            " <= " +
            show(y) +
            " but the outputs are the wrong way round"
        }
      }
    }
    v = v + 1
  }
  ""
}

///|
/// A transfer function that also RECORDS what it returned, so the chain the
/// solver walks can be inspected afterwards. The solvers expose the FIXED POINT
/// and not the sequence that reached it, and p.115's sentence ("OUT never
/// shrinks") is about the sequence.
fn recording(
  step : (Int32, Map[String, Bool]) -> Map[String, Bool],
  log : Array[(Int32, Map[String, Bool])],
) -> (Int32, Map[String, Bool]) -> Map[String, Bool] {
  fn(v, s) {
    let out = step(v, s)
    log.push((v, out))
    out
  }
}

///|
/// THE CHAIN MOVES ONE WAY. `order` here reads "the next value is above the
/// previous one", so a may analysis passes `subset_of` and a must analysis
/// passes `superset_of`.
fn chain_violation(
  log : Array[(Int32, Map[String, Bool])],
  order : (Map[String, Bool], Map[String, Bool]) -> Bool,
  n : Int32,
) -> String {
  let mut v = 0
  while v < n {
    let mut prev : Map[String, Bool]? = None
    for entry in log {
      let (node, val) = entry
      if node == v {
        match prev {
          Some(p) =>
            if order(p, val) == false {
              return "node \{v} moved the wrong way: " +
                show(p) +
                " then " +
                show(val)
            }
          None => ()
        }
        prev = Some(val)
      }
    }
    v = v + 1
  }
  ""
}

///|
/// A graph that mentions three names and computes `a + 1`, so both analyses have
/// something to do: `a` and `b` are read, `c` is written, and the
/// available-expressions universe holds `a + 1`.
fn laws_fixture() -> @flow.Cfg {
  graph(
    [
      @flow.Entry,
      @flow.Assign("a", int_e(1)),
      @flow.Test(ex("b")),
      @flow.Assign("c", plus("a", 1)),
      @flow.Exit,
    ],
    [[1], [2], [3, 4], [4], []],
  )
}

///|
/// The per-node definitions and uses of a graph, in node order -- the two arrays
/// `live_transfer` is built from.
fn defs_and_uses(
  cfg : @flow.Cfg,
) -> (Array[Map[String, Bool]], Array[Map[String, Bool]]) {
  let defs : Array[Map[String, Bool]] = []
  let uses : Array[Map[String, Bool]] = []
  let mut v = 0
  while v < cfg.kinds.length() {
    defs.push(@flow.node_defs(cfg.kinds[v]))
    uses.push(@flow.node_uses(cfg.kinds[v]))
    v = v + 1
  }
  (defs, uses)
}

// ---------------------------------------------------------------------------
// A -- the lattice laws, and the two lattices are duals
// ---------------------------------------------------------------------------

///|
/// THE SAME LAWS HOLD FOR BOTH ORDERS, which is the algebraic content of the
/// deck's "May/Must Analysis, A Lattice View": the may lattice is (empty, union)
/// over inclusion, the must lattice is (universe, intersection) over the SAME
/// carrier read backwards, and neither is a special case of the other -- they
/// are one structure.
///
/// `avail_lattice` is the object `avail_after` seeds the solver with, so
/// checking it here is what makes "the solver computes the must solution" a
/// claim about a lattice that satisfies the laws rather than a claim about a
/// lattice nobody looked at.
test "0545: the join laws hold in both directions, and the two are duals" {
  let names = ["a", "b", "c"]
  let elems = powerset_of(names)
  // THE MAY LATTICE: bottom is the empty set, join is union, order is inclusion.
  let may = @flow.name_set_lattice()
  assert_eq(laws_violation(may, subset_of, elems), "")
  // THE MUST LATTICE: bottom is the WHOLE set, join is intersection, order is
  // superset. Same carrier, same laws, other order.
  let uni : Map[String, Bool] = Map([])
  for n in names {
    uni.set(n, true)
  }
  let must = @flow.avail_lattice(uni)
  assert_eq(laws_violation(must, superset_of, elems), "")
  // DE MORGAN: the meet is the join of the complements. That identity is what
  // says `name_set_inter` and `name_set_union` are two directions of ONE
  // operation rather than two operations that happen to share a carrier.
  for a in elems {
    for b in elems {
      let lhs = @flow.name_set_inter(a, b)
      let rhs = complement_in(
        @flow.name_set_union(complement_in(a, uni), complement_in(b, uni)),
        uni,
      )
      assert_eq(show(lhs), show(rhs))
    }
  }
}

///|
/// AND THE DUAL'S BOTTOM IS NOT THE MAY LATTICE'S BOTTOM. If it were, the test
/// above would pass on one object twice and the duality would be a coincidence
/// of empty sets. The two differ whenever the program mentions anything at all.
test "0545: the must lattice's bottom is the universe, not the empty set" {
  let uni : Map[String, Bool] = Map([])
  for n in ["a", "b"] {
    uni.set(n, true)
  }
  let must = @flow.avail_lattice(uni)
  assert_eq(show((must.bot)()), "{a,b}")
  // and on the same carrier the may lattice's bottom is empty
  let may = @flow.name_set_lattice()
  assert_eq(show((may.bot)()), "{}")
}

// ---------------------------------------------------------------------------
// B -- monotonicity: the precondition of both solvers
// ---------------------------------------------------------------------------

///|
/// LIVE VARIABLES IS MONOTONE, and it has to be: the solver ascends from the
/// empty set by union, and it stops because a monotone function over a finite
/// lattice cannot keep producing new values. `x ⊆ y implies step(x) ⊆ step(y)`,
/// for every node, over all eight subsets of {a,b,c}.
test "0545: the live-variables transfer is monotone" {
  let cfg = laws_fixture()
  let (defs, uses) = defs_and_uses(cfg)
  assert_eq(
    monotone_violation(
      @flow.live_transfer(defs, uses),
      subset_of,
      powerset_of(["a", "b", "c"]),
      cfg.kinds.length(),
    ),
    "",
  )
}

///|
/// AVAILABLE EXPRESSIONS IS MONOTONE IN ITS OWN ORDER -- `x ⊇ y implies
/// step(x) ⊇ step(y)` -- and the ORDER IS THE POINT, although not in the way
/// the FIRST DRAFT of this comment put it. That draft said that read with the
/// may order this function is NOT monotone, and the claim is false:
/// `gen ∪ (S - kill)` is monotone in BOTH orders, which the BOTH-ORDERS row
/// below measures. Monotonicity is therefore not what distinguishes the two
/// readings; what the order decides is WHICH fixed point the seed reaches.
/// 0544's "the same solver, the dual reading" is a statement about the LATTICE
/// and not about the code: the same three closures, one reversed order, and a
/// different theorem applies to the ascent.
///
/// The carrier is the set of EXPRESSION KEYS the graph can compute, taken from
/// `avail_universe`, so the enumeration covers the states the analysis actually
/// has rather than names it never uses.
test "0545: the available-expressions transfer is monotone in the dual order" {
  let cfg = laws_fixture()
  let elems = powerset_of(keys_of_set(@flow.avail_universe(cfg)))
  // The fixture computes `a + 1`, so the universe is not empty and the
  // enumeration is not the two-element lattice a vacuous check would use.
  assert_true(elems.length() > 1)
  assert_eq(
    monotone_violation(
      @flow.avail_transfer(cfg),
      superset_of,
      elems,
      cfg.kinds.length(),
    ),
    "",
  )
}

///|
/// THE ORDER DOES NOT DECIDE MONOTONICITY, AND THAT IS WORTH PINNING BECAUSE IT
/// IS THE OPPOSITE OF WHAT THIS FILE FIRST ASSUMED.
///
/// The first version of the row below asserted that this transfer is NOT
/// monotone under the may order, and the assertion FAILED: `gen ∪ (S - kill)` is
/// monotone under both, because subtracting a fixed set and unioning a fixed set
/// are both monotone in inclusion. MEASURED, and it is the test that said so.
///
/// So monotonicity is not what distinguishes the two readings, and a file that
/// claimed it did would be a file that had never tried. What the ORDER decides
/// is WHICH fixed point the solver reaches from its seed: Kleene's theorem gives
/// the LEAST fixed point above the bottom, so seeding from the empty set gives
/// the least solution of the inclusion order and seeding from the universe gives
/// its greatest -- which is the least solution of the dual order, and that is
/// the safe answer for a must analysis. The chain direction, measured in the
/// last test, is that sentence.
test "0545: the transfer is monotone in BOTH orders, so the order picks the fixed point" {
  let cfg = laws_fixture()
  let elems = powerset_of(keys_of_set(@flow.avail_universe(cfg)))
  assert_true(elems.length() > 1)
  // monotone read one way ...
  assert_eq(
    monotone_violation(
      @flow.avail_transfer(cfg),
      superset_of,
      elems,
      cfg.kinds.length(),
    ),
    "",
  )
  // ... and monotone read the other way, which the first draft of this row
  // asserted it was not
  assert_eq(
    monotone_violation(
      @flow.avail_transfer(cfg),
      subset_of,
      elems,
      cfg.kinds.length(),
    ),
    "",
  )
}

// ---------------------------------------------------------------------------
// C -- the chain direction, which is p.115's sentence
// ---------------------------------------------------------------------------

///|
/// "OUT NEVER SHRINKS" -- AND THE MUST SIDE IS THE OTHER WAY ROUND.
///
/// Both solvers run the same loop, so both produce a sequence per node, and the
/// two sequences move in OPPOSITE directions along the two orders: a may
/// analysis only ever gains facts, a must analysis only ever loses them. That is
/// what makes the may answer an over-approximation of what happens and the must
/// answer an under-approximation of what is true, and it is measured here rather
/// than asserted in a comment.
test "0545: the may chain only grows and the must chain only shrinks" {
  let cfg = laws_fixture()
  let n = cfg.kinds.length()
  let (defs, uses) = defs_and_uses(cfg)
  // MAY: live variables, ascending by union, so each value is a SUPERSET of the
  // one before it.
  let may_log : Array[(Int32, Map[String, Bool])] = []
  let _ = @flow.solve_round_robin(
    @flow.name_set_lattice(),
    n,
    cfg.succ,
    recording(@flow.live_transfer(defs, uses), may_log),
  )
  assert_true(may_log.length() > 0)
  // The chain ascends in inclusion: each value is a SUPERSET of the one before,
  // which is `subset_of(previous, next)`.
  assert_eq(chain_violation(may_log, subset_of, n), "")
  // MUST: available expressions, descending by intersection, so each value is a
  // SUBSET of the one before it -- `superset_of(previous, next)`.
  let must_log : Array[(Int32, Map[String, Bool])] = []
  let _ = @flow.solve_round_robin(
    @flow.avail_lattice(@flow.avail_universe(cfg)),
    n,
    cfg.pred,
    recording(@flow.avail_transfer(cfg), must_log),
  )
  assert_true(must_log.length() > 0)
  assert_eq(chain_violation(must_log, superset_of, n), "")
}
