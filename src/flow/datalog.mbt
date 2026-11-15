// 0592: THE DATALOG ENGINE -- the deck's language, and the fixpoint that runs it.
//
// THE DECK. `Datalog-Based Program Analysis` (Tian Tan, Nanjing University, 2021),
// 93 pages, four chapters: 1. Motivation, 2. Introduction to Datalog, 3. Pointer
// Analysis via Datalog, 4. Taint Analysis via Datalog.
//
// ITS OWN TABLE OF CONTENTS (p.93) says what the lecture is FOR:
//
//     The X You Need To Understand in This Lecture
//     - Datalog language
//     - How to implement pointer analysis via Datalog
//     - How to implement taint analysis via Datalog
//
// and THIS INCREMENT IS THE FIRST OF THE THREE: the language, and the engine that
// runs it. The other two are 0593 and 0594.
//
// WHY AN ENGINE AND NOT A SECOND POINTER ANALYSIS. The deck's argument (p.8-16) is
// that the SAME analysis has two forms -- an imperative one with a worklist, and a
// declarative one with rules -- and that the declarative one is "Succinct / Readable
// (logic-based specification) / Easy to implement" (p.16). So the Datalog reading
// of the pointer analysis is NOT a second implementation to be maintained: it is a
// MEASUREMENT of the deck's claim that the two forms agree. This file is the
// engine; 0593 writes the deck's own rules in it and compares the answer with the
// one `pta_run` already gives.
//
// THE LANGUAGE, AS THE DECK DEFINES IT, and each cell is a row in this file's
// tests:
//
//   p.21-22   a predicate is a TABLE; a fact asserts that a TUPLE belongs to it
//   p.23-29   an ATOM is `P(X1,...,Xn)`; it is true when P contains the tuple
//   p.30-31   a RULE is `H <- B1,...,Bn.`; the head is true if the body is
//   p.34      the interpretation: every combination of the variables' values that
//             makes all the subgoals true makes the head true too
//   p.40      a Datalog program is FACTS + RULES
//   p.42-43   EDB = the relations given a priori; IDB = the ones the rules infer.
//             The head can only be IDB; a subgoal can be EDB or IDB
//   p.44-45   logical OR: several rules with the same head, or the `;` operator,
//             whose precedence is LOWER than `,`
//   p.46-47   NEGATION: `!B(...)` reads as "not B(...)"
//   p.48-49   RECURSION: an IDB predicate may be deduced from itself
//   p.51-53   RULE SAFETY: every variable must appear in at least one
//             NON-NEGATED RELATIONAL atom, and only safe rules are allowed
//   p.54-56   recursion and negation of an atom must be SEPARATED, or the rules
//             contradict each other and the inference does not converge
//   p.57-59   the engine deduces facts until no new fact can be deduced;
//             MONOTONICITY (facts are never deleted) and TERMINATION (the IDB's
//             possible values are finite, by rule safety)
//
// THE TWO REFUSALS ARE REFUSALS AND NOT SILENT DROPS, because a dropped rule
// would leave a program that runs and answers nothing -- which looks exactly like
// a program whose answer is empty.

///|
/// A term of an atom: a VARIABLE (bound by the rule) or a CONSTANT (a value).
///
/// WHY A TERM CARRIES ITS KIND AND IS NOT A STRING. The deck's own syntax cannot
/// tell them apart: its pointer-analysis facts are `New(b, o1)` (p.65) and its
/// rules are `VarPointsTo(x, o) <- New(x, o).` (p.70), and in BOTH the object
/// name `o1` and the variable `x` are bare identifiers. The difference is the
/// CONTEXT -- a fact's terms are all values, a rule's bare terms are all
/// variables -- and a representation that keeps the kind explicit is the only one
/// that survives both without a convention nobody can check.
pub(all) enum DTerm {
  DVar(String)
  DConst(String)
}

///|
/// An atom: either a RELATIONAL atom `P(X1,...,Xn)` (p.23) or an ARITHMETIC one
/// `X op Y` (p.29, "In addition to relational atoms, Datalog also has arithmetic
/// atoms").
pub(all) enum DAtom {
  DRel(String, Array[DTerm])
  DCmp(DTerm, String, DTerm)
}

///|
/// A subgoal of a rule's body: an atom, and whether it is NEGATED (p.46).
pub(all) struct DGoal {
  atom : DAtom
  negated : Bool
}

///|
/// A rule: a head, and a body of ALTERNATIVES. One alternative is a plain
/// conjunction; two or more are the deck's logical OR (p.44-45), whose `;` has a
/// LOWER precedence than the `,` -- so `H <- A, (B;C)` is "A and (B or C)".
pub(all) struct DRule {
  head : DAtom
  body : Array[Array[DGoal]]
}

///|
/// A fact: a tuple that belongs to a relation (p.22). Every term is a value.
pub(all) struct DFact {
  pred : String
  args : Array[String]
}

///|
/// A Datalog program: FACTS + RULES (p.40).
pub(all) struct DProgram {
  facts : Array[DFact]
  rules : Array[DRule]
}

///|
/// A relation: the tuples of one predicate, with their keys so that membership is
/// a lookup and not a scan.
pub(all) struct DRelation {
  tuples : Array[Array[String]]
  keys : Map[String, Bool]
}

///|
/// The empty relation.
pub fn drel_empty() -> DRelation {
  { tuples: [], keys: Map([]), }
}

///|
/// The canonical key of a tuple: each term length-prefixed, so the encoding is
/// injective and two different tuples can never share a key.
fn dtuple_key(t : Array[String]) -> String {
  let mut out = ""
  for term in t {
    out = out + term.length().to_string() + ":" + term
  }
  out
}

///|
/// Does the relation contain this tuple?
pub fn drel_has(r : DRelation, t : Array[String]) -> Bool {
  r.keys.contains(dtuple_key(t))
}

///|
/// Add a tuple to the relation; true when it was NOT there before.
///
/// THE RETURN VALUE IS THE WHOLE POINT: the fixpoint loop needs to know whether
/// anything changed, and a relation that grew is the only thing that can stop it.
pub fn drel_add(r : DRelation, t : Array[String]) -> Bool {
  let k = dtuple_key(t)
  if r.keys.contains(k) {
    return false
  }
  r.keys.set(k, true)
  r.tuples.push(t)
  true
}

///|
/// The relation of one predicate, creating it when it is not there yet.
fn drel_of(rels : Map[String, DRelation], pred : String) -> DRelation {
  match rels.get(pred) {
    Some(r) => r
    None => {
      let r = drel_empty()
      rels.set(pred, r)
      r
    }
  }
}

///|
/// A variable term.
pub fn dvar(name : String) -> DTerm {
  DVar(name)
}

///|
/// A constant term.
pub fn dconst(name : String) -> DTerm {
  DConst(name)
}

///|
/// A relational atom.
pub fn drel(pred : String, args : Array[DTerm]) -> DAtom {
  DRel(pred, args)
}

///|
/// An arithmetic atom `l op r`.
pub fn dcmp(l : DTerm, op : String, r : DTerm) -> DAtom {
  DCmp(l, op, r)
}

///|
/// A positive subgoal.
pub fn dgoal(atom : DAtom) -> DGoal {
  { atom, negated: false, }
}

///|
/// A NEGATED subgoal (p.46).
pub fn dgoal_neg(atom : DAtom) -> DGoal {
  { atom, negated: true, }
}

///|
/// A rule whose body is one conjunction.
pub fn drule(head : DAtom, body : Array[DGoal]) -> DRule {
  { head, body: [body], }
}

///|
/// A rule whose body is a DISJUNCTION of conjunctions (p.44-45).
pub fn drule_disj(head : DAtom, alts : Array[Array[DGoal]]) -> DRule {
  { head, body: alts, }
}

///|
/// A fact.
pub fn dfact(pred : String, args : Array[String]) -> DFact {
  { pred, args, }
}

///|
/// An empty program.
pub fn dprog() -> DProgram {
  { facts: [], rules: [], }
}

///|
/// The predicate of an atom; `""` for an arithmetic one, which has none.
fn datom_pred(a : DAtom) -> String {
  match a {
    DRel(p, _) => p
    DCmp(_, _, _) => ""
  }
}

///|
/// Every variable an atom mentions.
fn datom_vars(a : DAtom, out : Array[String]) -> Unit {
  match a {
    DRel(_, args) =>
      for t in args {
        match t {
          DVar(v) => if out.contains(v) == false { out.push(v) }
          DConst(_) => ()
        }
      }
    DCmp(l, _, r) => {
      match l {
        DVar(v) => if out.contains(v) == false { out.push(v) }
        DConst(_) => ()
      }
      match r {
        DVar(v) => if out.contains(v) == false { out.push(v) }
        DConst(_) => ()
      }
    }
  }
}

///|
/// The variables of a rule: the head's and the body's.
fn drule_vars(r : DRule) -> Array[String] {
  let out : Array[String] = []
  datom_vars(r.head, out)
  for alt in r.body {
    for g in alt {
      datom_vars(g.atom, out)
    }
  }
  out
}

///|
/// The variables of a rule that appear in at least one NON-NEGATED RELATIONAL
/// atom of its body.
///
/// THIS IS THE DECK'S DEFINITION OF SAFETY (p.53): "A rule is safe if every
/// variable appears in at least one non-negated relational atom". Note what it
/// EXCLUDES: a variable that appears only in an ARITHMETIC atom does not count,
/// and a variable that appears only in a NEGATED atom does not count. Both
/// exclusions are the deck's own examples (p.51-52), and both are unsafe because
/// "infinite values of x can satisfy the rule, which makes A an infinite
/// relation".
fn drule_bound_vars(r : DRule) -> Array[String] {
  let out : Array[String] = []
  for alt in r.body {
    for g in alt {
      if g.negated {
        continue
      }
      match g.atom {
        DRel(_, _) => datom_vars(g.atom, out)
        DCmp(_, _, _) => ()
      }
    }
  }
  out
}

///|
/// Is the rule SAFE (p.53)?
pub fn drule_safe(r : DRule) -> Bool {
  let all = drule_vars(r)
  let bound = drule_bound_vars(r)
  for v in all {
    if bound.contains(v) == false {
      return false
    }
  }
  true
}

///|
/// The result of checking a program: the problems, and whether there are none.
pub(all) struct DCheck {
  ok : Bool
  problems : Array[String]
}

///|
/// The result of running a program: the relations, the rounds it took, and the
/// problems that stopped it.
pub(all) struct DSolve {
  ok : Bool
  problems : Array[String]
  rels : Map[String, DRelation]
  rounds : Int32
}

///|
/// The keys of a set, as an ARRAY.
///
/// `Map::keys()` returns an ITERATOR, and an iterator has no `sort` and no
/// `contains` -- and this file needs both (the strata are ordered by level, and
/// a predicate is looked up by name). So the keys are collected once, here,
/// rather than at each of the four places that want them.
fn dkeys(m : Map[String, Bool]) -> Array[String] {
  let out : Array[String] = []
  for k in m.keys() {
    out.push(k)
  }
  out
}

///|
/// The predicates that some rule's HEAD mentions: the IDB (p.43).
fn d_idb(prog : DProgram) -> Map[String, Bool] {
  let out : Map[String, Bool] = Map([])
  for r in prog.rules {
    let p = datom_pred(r.head)
    if p != "" {
      out.set(p, true)
    }
  }
  out
}

///|
/// The dependency edges of the program: a rule's head depends on every predicate
/// its body mentions -- positively or negatively, because a NEGATED dependency is
/// a dependency all the same (p.46, and p.56's separation requirement).
fn d_deps(
  prog : DProgram,
  idb : Map[String, Bool],
) -> Map[String, Array[String]] {
  let out : Map[String, Array[String]] = Map([])
  for r in prog.rules {
    let hp = datom_pred(r.head)
    if hp == "" {
      continue
    }
    let mut deps : Array[String] = []
    match out.get(hp) {
      Some(d) => deps = d
      None => ()
    }
    for alt in r.body {
      for g in alt {
        match g.atom {
          DRel(p, _) =>
            if idb.contains(p) && deps.contains(p) == false {
              deps.push(p)
            }
          DCmp(_, _, _) => ()
        }
      }
    }
    out.set(hp, deps)
  }
  out
}

///|
/// The keys of a map whose values are arrays.
fn darray_keys(m : Map[String, Array[String]]) -> Array[String] {
  let out : Array[String] = []
  for k in m.keys() {
    out.push(k)
  }
  out
}

///|
/// The transitive closure of the dependency graph: `reach[a]` is every predicate
/// `a` depends on, directly or through others.
fn d_reach(deps : Map[String, Array[String]]) -> Map[String, Map[String, Bool]] {
  let out : Map[String, Map[String, Bool]] = Map([])
  for a in darray_keys(deps) {
    let seen : Map[String, Bool] = Map([])
    let mut queue : Array[String] = []
    match deps.get(a) {
      Some(ds) =>
        for d in ds {
          queue.push(d)
        }
      None => ()
    }
    while queue.length() > 0 {
      let cur = queue[0]
      let rest : Array[String] = []
      for i in 1..<queue.length() {
        rest.push(queue[i])
      }
      queue = rest
      if seen.contains(cur) {
        continue
      }
      seen.set(cur, true)
      match deps.get(cur) {
        Some(ds) =>
          for d in ds {
            if seen.contains(d) == false {
              queue.push(d)
            }
          }
        None => ()
      }
    }
    out.set(a, seen)
  }
  out
}

///|
/// CHECK THE PROGRAM, and the two checks are the deck's own requirements.
///
/// The first is RULE SAFETY (p.51-53): "In Datalog, only safe rules are
/// allowed". The second is the SEPARATION of recursion and negation (p.54-56):
/// "In Datalog, recursion and negation of an atom must be separated. Otherwise,
/// the rules may contain contradiction and the inference fails to converge."
///
/// THE SECOND CHECK IS NOT "A RULE MAY NOT BE RECURSIVE". Recursion is the whole
/// point of p.48-49 -- the transitive closure is a recursive rule and the deck
/// calls it "much more powerful, and is able to express sophisticated program
/// analyses, such as pointer analysis" (p.50). What is forbidden is a NEGATIVE
/// edge that lies ON A CYCLE, because then the rule contradicts itself: p.55
/// walks the deck's own example through it and gets "If A(1) is false, then A(1)
/// is true. If A(1) is true, A(1) should not be true."
pub fn datalog_check(prog : DProgram) -> DCheck {
  let problems : Array[String] = []
  for r in prog.rules {
    if drule_safe(r) == false {
      let unbound : Array[String] = []
      let all = drule_vars(r)
      let bound = drule_bound_vars(r)
      for v in all {
        if bound.contains(v) == false {
          unbound.push(v)
        }
      }
      problems.push(
        "UNSAFE RULE: the variable(s) " +
        unbound.join(", ") +
        " appear in no non-negated relational atom, so the rule is not safe",
      )
    }
  }
  let idb = d_idb(prog)
  let deps = d_deps(prog, idb)
  let reach = d_reach(deps)
  for r in prog.rules {
    let hp = datom_pred(r.head)
    if hp == "" {
      continue
    }
    for alt in r.body {
      for g in alt {
        if g.negated == false {
          continue
        }
        match g.atom {
          DRel(p, _) => {
            let back = match reach.get(p) {
              Some(s) => s
              None => Map([])
            }
            if back.contains(hp) {
              problems.push(
                "RECURSION AND NEGATION ARE NOT SEPARATED: the rule for '" +
                hp +
                "' negates '" +
                p +
                "', and '" +
                p +
                "' depends on '" +
                hp +
                "', so the two contradict each other and the inference does not converge",
              )
            }
          }
          DCmp(_, _, _) => ()
        }
      }
    }
  }
  { ok: problems.length() == 0, problems, }
}

///|
/// The value of a term under a binding; `None` when a variable is unbound.
fn dterm_value(t : DTerm, bind : Map[String, String]) -> String? {
  match t {
    DConst(c) => Some(c)
    DVar(v) => bind.get(v)
  }
}

///|
/// Compare two NUMERIC strings as numbers rather than as text, because the
/// deck's own example compares `age >= 18` and a text comparison would put "9"
/// above "18".
fn dnum_cmp(a : String, b : String) -> Int32 {
  let mut sa = a
  let mut sb = b
  let neg_a = sa.has_prefix("-")
  let neg_b = sb.has_prefix("-")
  if neg_a {
    sa = sa[1:].to_owned()
  }
  if neg_b {
    sb = sb[1:].to_owned()
  }
  let ta = dnum_digits(sa)
  let tb = dnum_digits(sb)
  let mag = dnum_mag_cmp(ta, tb)
  if neg_a && neg_b {
    return -mag
  }
  if neg_a {
    return -1
  }
  if neg_b {
    return 1
  }
  mag
}

///|
/// Strip the leading zeros of a digit string.
fn dnum_digits(s : String) -> String {
  let mut out = ""
  let mut i = 0
  while i < s.length() {
    if s[i] != '0' {
      break
    }
    i = i + 1
  }
  if i >= s.length() {
    return "0"
  }
  out = s[i:].to_owned()
  out
}

///|
/// Compare two digit strings by LENGTH first and then by their digits, which is
/// the numeric order.
fn dnum_mag_cmp(a : String, b : String) -> Int32 {
  if a.length() != b.length() {
    if a.length() < b.length() {
      return -1
    }
    return 1
  }
  let mut i = 0
  while i < a.length() {
    let ca = a[i]
    let cb = b[i]
    if ca != cb {
      if ca < cb {
        return -1
      }
      return 1
    }
    i = i + 1
  }
  0
}

///|
/// Does the comparison hold? The operator is one of `<`, `<=`, `>`, `>=`, `=`,
/// `!=` (p.51 uses `x > y`).
fn dcmp_holds(
  l : DTerm,
  op : String,
  r : DTerm,
  bind : Map[String, String],
) -> Bool {
  let lv = dterm_value(l, bind)
  let rv = dterm_value(r, bind)
  match (lv, rv) {
    (Some(a), Some(b)) => {
      let c = dnum_cmp(a, b)
      if op == "<" {
        return c < 0
      }
      if op == "<=" {
        return c <= 0
      }
      if op == ">" {
        return c > 0
      }
      if op == ">=" {
        return c >= 0
      }
      if op == "=" || op == "==" {
        return c == 0
      }
      if op == "!=" {
        return c != 0
      }
      false
    }
    _ => false
  }
}

///|
/// A COPY of a binding.
///
/// AND THIS FUNCTION IS NOT A REFACTORING. MoonBit's `Map` is MUTABLE IN PLACE,
/// so `let out = bind` ALIASES the binding and every extension of it writes
/// into the SAME map. The first version of this file did that, and the symptom
/// was that a relation derived exactly ONE tuple where the deck's example
/// derives three: the second tuple's variables were already bound to the first
/// one's values, so the equality check rejected it. A join that binds variables
/// needs a fresh binding per candidate, and this is where it gets one.
fn dbind_copy(bind : Map[String, String]) -> Map[String, String] {
  let out : Map[String, String] = Map([])
  for k in bind.keys() {
    match bind.get(k) {
      Some(v) => out.set(k, v)
      None => ()
    }
  }
  out
}

///|
/// Bind a relation's arguments against a tuple under a binding; `None` when the
/// tuple does not match.
fn dbind_args(
  args : Array[DTerm],
  t : Array[String],
  bind : Map[String, String],
) -> Map[String, String]? {
  if args.length() != t.length() {
    return None
  }
  let out = dbind_copy(bind)
  let mut i = 0
  while i < args.length() {
    match args[i] {
      DConst(c) => if c != t[i] { return None }
      DVar(v) =>
        match out.get(v) {
          Some(bound) => if bound != t[i] { return None }
          None => out.set(v, t[i])
        }
    }
    i = i + 1
  }
  Some(out)
}

///|
/// Does the relation hold a tuple that MATCHES the atom under the binding? This
/// is the negated subgoal's test (p.46): "not B(...)" is true when there is no
/// such tuple.
fn d_has_match(
  r : DRelation,
  args : Array[DTerm],
  bind : Map[String, String],
) -> Bool {
  for t in r.tuples {
    let mut ok = true
    let mut i = 0
    while i < args.length() && i < t.length() {
      match args[i] {
        DConst(c) => if c != t[i] { ok = false }
        DVar(v) =>
          match bind.get(v) {
            Some(bound) => if bound != t[i] { ok = false }
            None => ()
          }
      }
      i = i + 1
    }
    if ok {
      return true
    }
  }
  false
}

///|
/// The bindings that satisfy one conjunction of subgoals.
fn d_solve_conj(
  goals : Array[DGoal],
  rels : Map[String, DRelation],
) -> Array[Map[String, String]] {
  let mut binds : Array[Map[String, String]] = [Map([])]
  for g in goals {
    let next : Array[Map[String, String]] = []
    for bind in binds {
      match g.atom {
        DRel(p, args) => {
          let rel = drel_of(rels, p)
          if g.negated {
            // THE NEGATED GOAL MULTIPLIES NOTHING: it only REFUSES the bindings
            // for which a matching tuple exists.
            if d_has_match(rel, args, bind) == false {
              next.push(bind)
            }
          } else {
            for t in rel.tuples {
              match dbind_args(args, t, bind) {
                Some(nb) => next.push(nb)
                None => ()
              }
            }
          }
        }
        DCmp(l, op, r) => if dcmp_holds(l, op, r, bind) { next.push(bind) }
      }
    }
    binds = next
    if binds.length() == 0 {
      break
    }
  }
  binds
}

///|
/// The head's tuple under a binding.
fn d_head_tuple(head : DAtom, bind : Map[String, String]) -> Array[String]? {
  match head {
    DRel(_, args) => {
      let out : Array[String] = []
      for a in args {
        match dterm_value(a, bind) {
          Some(v) => out.push(v)
          None => return None
        }
      }
      Some(out)
    }
    DCmp(_, _, _) => None
  }
}

///|
/// The STRATA of the program: the groups of mutually recursive predicates, in
/// the order they can be evaluated.
///
/// A predicate and another are in the same stratum when each depends on the
/// other; a stratum depends on every stratum it mentions, so it is evaluated
/// after those are final. This is the standard stratification, and it is what
/// makes the negation sound: a negated subgoal always reads a relation that is
/// already final, because the check in `datalog_check` refuses a negated edge
/// that lies on a cycle.
fn d_strata(prog : DProgram, idb : Map[String, Bool]) -> Array[Array[String]] {
  let deps = d_deps(prog, idb)
  let reach = d_reach(deps)
  let preds = dkeys(idb)
  // the groups: mutually reachable predicates
  let groups : Array[Array[String]] = []
  let placed : Map[String, Bool] = Map([])
  for p in preds {
    if placed.contains(p) {
      continue
    }
    let group : Array[String] = []
    for q in preds {
      if placed.contains(q) {
        continue
      }
      let pq = match reach.get(p) {
        Some(s) => s
        None => Map([])
      }
      let qp = match reach.get(q) {
        Some(s) => s
        None => Map([])
      }
      // A PREDICATE IS IN ITS OWN STRATUM, and the reflexive case is the whole
      // reason the first version of this loop derived NOTHING: a predicate with
      // no IDB dependency does not reach itself, so the mutual-reachability test
      // was false for it and its group came out EMPTY -- and a stratum with no
      // predicate in it evaluates no rule at all. A predicate joins another only
      // when each reaches the other.
      // A `match` AND NOT AN `if`, and the reason is the 0552 precedent: an `if`
      // used as a VALUE is outside the analysed subset, so a binding that is read
      // only inside one is a binding the analyzer believes is unused -- and the
      // false positive lands on the very variables this test is about.
      let same = match p == q {
        true => true
        false => pq.contains(q) && qp.contains(p)
      }
      if same {
        group.push(q)
        placed.set(q, true)
      }
    }
    groups.push(group)
  }
  // the order: a group goes after every group it depends on
  let levels : Map[String, Int32] = Map([])
  for g in groups {
    for p in g {
      levels.set(p, 0)
    }
  }
  let mut changed = true
  let mut passes = 0
  while changed && passes < 64 {
    changed = false
    passes = passes + 1
    for g in groups {
      let mut lvl = 0
      for p in g {
        match deps.get(p) {
          Some(ds) =>
            for d in ds {
              if g.contains(d) {
                continue
              }
              match levels.get(d) {
                Some(l) => if l + 1 > lvl { lvl = l + 1 }
                None => ()
              }
            }
          None => ()
        }
      }
      for p in g {
        let cur = match levels.get(p) {
          Some(l) => l
          None => 0
        }
        if lvl > cur {
          levels.set(p, lvl)
          changed = true
        }
      }
    }
  }
  // sort the groups by their level
  let ordered : Array[Array[String]] = []
  let used : Map[String, Bool] = Map([])
  let mut lvl = 0
  let mut guard2 = 0
  while used.length() < groups.length() && guard2 < 64 {
    guard2 = guard2 + 1
    for g in groups {
      let mut gl = 0
      for p in g {
        let l = match levels.get(p) {
          Some(x) => x
          None => 0
        }
        if l > gl {
          gl = l
        }
      }
      if gl == lvl {
        let fresh : Array[String] = []
        for p in g {
          if used.contains(p) == false {
            fresh.push(p)
            used.set(p, true)
          }
        }
        if fresh.length() > 0 {
          ordered.push(fresh)
        }
      }
    }
    lvl = lvl + 1
  }
  ordered
}

///|
/// RUN THE PROGRAM: deduce facts until no new fact can be deduced (p.57).
///
/// THE LOOP IS THE DECK'S, and the deck gives its two guarantees (p.58-59):
/// MONOTONICITY ("facts cannot be deleted") and TERMINATION ("A Datalog program
/// always terminates as 1) Datalog is monotone 2) Possible values of IDB
/// predicates are finite (rule safety)"). The first is why the loop can only
/// ever add; the second is why it stops. `rounds` counts the passes, and a
/// program that needs a second round is a RECURSIVE one -- the deck's own
/// transitive closure (p.49) needs more than one.
pub fn datalog_solve(prog : DProgram) -> DSolve {
  let check = datalog_check(prog)
  if check.ok == false {
    return { ok: false, problems: check.problems, rels: Map([]), rounds: 0, }
  }
  let rels : Map[String, DRelation] = Map([])
  for f in prog.facts {
    let rel = drel_of(rels, f.pred)
    let _ = drel_add(rel, f.args)
  }
  let idb = d_idb(prog)
  let strata = d_strata(prog, idb)
  let mut rounds : Int32 = 0
  for stratum in strata {
    let mut changed = true
    let mut passes = 0
    while changed && passes < 10000 {
      changed = false
      passes = passes + 1
      rounds = rounds + 1
      for r in prog.rules {
        let hp = datom_pred(r.head)
        if stratum.contains(hp) == false {
          continue
        }
        for alt in r.body {
          let binds = d_solve_conj(alt, rels)
          for bind in binds {
            match d_head_tuple(r.head, bind) {
              Some(t) => {
                let rel = drel_of(rels, hp)
                if drel_add(rel, t) {
                  changed = true
                }
              }
              None => ()
            }
          }
        }
      }
    }
  }
  { ok: true, problems: [], rels, rounds, }
}

///|
/// The predicates of the relations of a solved program, as an array.
fn drel_keys(m : Map[String, DRelation]) -> Array[String] {
  let out : Array[String] = []
  for k in m.keys() {
    out.push(k)
  }
  out
}

///|
/// The tuples of one relation, as text: `P(a, b)`.
///
/// THE ORDER IS THE DISPLAY TEXT'S, and not the canonical key's. The key is
/// length-prefixed so that two different tuples can never share it, and that
/// makes it sort by LENGTH FIRST -- which would print `Age(Abao, 31)` before
/// `Age(Xiaoming, 18)` and read like a mistake. The key is for MEMBERSHIP and
/// the text is for READING, and this function sorts the text.
fn d_relation_text(pred : String, r : DRelation) -> String {
  let out : Array[String] = []
  for t in r.tuples {
    out.push(pred + "(" + t.join(", ") + ")")
  }
  out.sort()
  out.join("; ")
}

///|
/// The relations of a solved program, one line per predicate, sorted.
pub fn datalog_text(s : DSolve) -> String {
  if s.ok == false {
    return "REFUSED: " + s.problems.join(" | ")
  }
  let preds = drel_keys(s.rels)
  preds.sort()
  let lines : Array[String] = []
  for p in preds {
    match s.rels.get(p) {
      Some(r) => if r.tuples.length() > 0 { lines.push(d_relation_text(p, r)) }
      None => ()
    }
  }
  lines.join("\n")
}

///|
/// The tuples of one relation of a solved program.
pub fn datalog_tuples(s : DSolve, pred : String) -> Array[Array[String]] {
  match s.rels.get(pred) {
    Some(r) => r.tuples
    None => []
  }
}

///|
/// Does the solved program hold this tuple in this relation?
pub fn datalog_has(s : DSolve, pred : String, args : Array[String]) -> Bool {
  match s.rels.get(pred) {
    Some(r) => drel_has(r, args)
    None => false
  }
}
