// guardfacts: BOUNDED SYMBOLIC EXECUTION over the guards of one function.
//
// 0522. Two of the twelve families reason about FLOW (`Unreachable` -- a
// statement after a `return`) and none reasoned about VALUES, so a branch that
// no input can reach because the guards on the way to it contradict each other
// was invisible. That is the deck's INFEASIBLE PATH (p.20, p.22): every
// statement on it is individually reachable, and no single input executes the
// path. Its domain is written `D[P]` (p.54), and an infeasible path is one
// where `D[P] = { }`.
//
// THIS IS BOUNDED, AND THE BOUND IS THE POINT. A fact is only recorded when a
// guard compares an IMMUTABLE local name against an INTEGER LITERAL --
// `x > 5`, `n == 3`, `7 >= i`. Everything else (a call's result, an index, a
// sum, a field, a float, a string, a name only compared to another name) is
// UNDECIDED: no fact, no finding, no silence that reads as a verdict. Feasibility
// in general is undecidable (p.20: "in general, unsolvable; in practice,
// intractable"), so the tool claims exactly the fragment it can decide and says
// so in the family's own contract.
//
// THE THREE OUTCOMES, and only the first two are findings:
//
//   contradictory  the accumulated facts over some name intersect the new
//                  guard to the EMPTY interval -> the branch's D[P] is empty
//                  -> `InfeasibleBranch` (MSA-013).
//   implied        the new guard adds nothing to what is already known about
//                  every name it constrains -> the test cannot take the other
//                  way -> `RedundantGuard` (MSA-014).
//   undecided      everything else. Nothing is reported, and the family's
//                  `excluded` contract names this case so a reader is not left
//                  to read silence as "the branch is reachable".
//
// SOUNDNESS RESTS ON THREE RULES, each of which is implemented rather than
// assumed: a name loses ALL of its facts as soon as it is assigned, a binding
// that is re-declared loses them too, and a loop body is entered with the facts
// of every name assigned anywhere inside it REMOVED -- a fact proved before a
// loop is not a fact after one iteration.
//
// WHAT IT DOES NOT DO: it does not prove a branch reachable. `undecided` is not
// `feasible`, and no message here says otherwise.

///|
/// One integer constraint on one name, with the line it came from so the
/// finding can quote the path condition instead of asserting it.
priv struct C {
  name : String
  op : @ast.BOp
  value : Int32
  line : Int32
}

///|
/// An interval, with EXPLICIT absence of each bound rather than the extreme
/// `Int32` values. A sentinel would make `Int32::min_value() - 1` a wrap and the
/// emptiness test would then be about arithmetic overflow rather than about the
/// constraints.
priv struct Ival {
  has_lo : Bool
  lo : Int32
  lo_incl : Bool
  has_hi : Bool
  hi : Int32
  hi_incl : Bool
}

///|
fn ival_full() -> Ival {
  {
    has_lo: false,
    lo: 0,
    lo_incl: false,
    has_hi: false,
    hi: 0,
    hi_incl: false,
  }
}

///|
/// Is there NO integer this interval allows? An interval with both bounds
/// present and crossing is empty, and so is a point interval open at either end.
fn Ival::is_empty(self : Ival) -> Bool {
  if !(self.has_lo && self.has_hi) {
    return false
  }
  if self.lo > self.hi {
    return true
  }
  if self.lo == self.hi && !(self.lo_incl && self.hi_incl) {
    return true
  }
  false
}

///|
/// The intersection: the tighter lower bound wins, and on a tie the EXCLUSIVE one
/// does, because `x > 5` allows strictly less than `x >= 5`.
fn Ival::inter(self : Ival, other : Ival) -> Ival {
  let mut has_lo = self.has_lo
  let mut lo = self.lo
  let mut lo_incl = self.lo_incl
  if other.has_lo {
    if !has_lo || other.lo > lo || (other.lo == lo && !other.lo_incl) {
      has_lo = true
      lo = other.lo
      lo_incl = other.lo_incl
    }
  }
  let mut has_hi = self.has_hi
  let mut hi = self.hi
  let mut hi_incl = self.hi_incl
  if other.has_hi {
    if !has_hi || other.hi < hi || (other.hi == hi && !other.hi_incl) {
      has_hi = true
      hi = other.hi
      hi_incl = other.hi_incl
    }
  }
  { has_lo, lo, lo_incl, has_hi, hi, hi_incl, }
}

///|
/// Do the two intervals allow exactly the same integers? Used for "the guard
/// changed nothing", which is the definition of an implied test.
fn Ival::same(self : Ival, other : Ival) -> Bool {
  if self.has_lo != other.has_lo || self.has_hi != other.has_hi {
    return false
  }
  if self.has_lo && (!(self.lo == other.lo) || self.lo_incl != other.lo_incl) {
    return false
  }
  if self.has_hi && (!(self.hi == other.hi) || self.hi_incl != other.hi_incl) {
    return false
  }
  true
}

///|
/// The interval ONE comparison allows. `!=` deliberately returns the full
/// interval: "not equal to 5" is not an interval, and pretending it is one would
/// be the kind of approximation that reports a branch as unreachable when it is
/// reachable.
fn C::ival(self : C) -> Ival {
  match self.op {
    @ast.OpLt =>
      {
        has_lo: false,
        lo: 0,
        lo_incl: false,
        has_hi: true,
        hi: self.value,
        hi_incl: false,
      }
    @ast.OpLe =>
      {
        has_lo: false,
        lo: 0,
        lo_incl: false,
        has_hi: true,
        hi: self.value,
        hi_incl: true,
      }
    @ast.OpGt =>
      {
        has_lo: true,
        lo: self.value,
        lo_incl: false,
        has_hi: false,
        hi: 0,
        hi_incl: false,
      }
    @ast.OpGe =>
      {
        has_lo: true,
        lo: self.value,
        lo_incl: true,
        has_hi: false,
        hi: 0,
        hi_incl: false,
      }
    @ast.OpEq =>
      {
        has_lo: true,
        lo: self.value,
        lo_incl: true,
        has_hi: true,
        hi: self.value,
        hi_incl: true,
      }
    _ => ival_full()
  }
}

///|
/// The constraint spelled the way the deck writes a path condition: `x > 5`.
fn C::text(self : C) -> String {
  "\{self.name} \{self.op.symbol()} \{self.value}"
}

///|
/// A fact set: one constraint list per name. The lists are kept rather than
/// folded to an interval because the FINDING has to quote the guards that
/// produced the empty domain -- an interval alone cannot say which two lines
/// disagree, and a claim nobody can check is not a finding.
type Facts = Map[String, Array[C]]

///|
fn facts_get(f : Facts, name : String) -> Array[C] {
  match f.get(name) {
    Some(cs) => cs
    None => []
  }
}

///|
fn facts_add(f : Facts, c : C) -> Unit {
  let cs = facts_get(f, c.name)
  let out : Array[C] = []
  for old in cs {
    out.push(old)
  }
  out.push(c)
  f.set(c.name, out)
}

///|
/// Every integer some constraint in `cs` allows.
fn ival_of(cs : Array[C]) -> Ival {
  let mut acc = ival_full()
  for c in cs {
    acc = acc.inter(c.ival())
  }
  acc
}

///|
/// Drop every fact about a name. Called on assignment and on re-declaration: a
/// fact about what a name USED to denote is not a fact about what it denotes now.
fn facts_drop(f : Facts, name : String) -> Unit {
  f.set(name, [])
}

///|
/// A copy, because the two arms of one `if` must not see each other's facts. A
/// shared map would make the else-branch inherit what the then-branch proved --
/// the one bug that turns this analysis into a generator of false findings.
fn facts_clone(f : Facts) -> Facts {
  let out : Facts = Map([])
  for k, v in f {
    let cs : Array[C] = []
    for c in v {
      cs.push(c)
    }
    out.set(k, cs)
  }
  out
}

///|
/// The name a comparison constrains, if it constrains exactly one and the other
/// side is an integer literal. The literal may be on either side -- `3 < x` is
/// `x > 3` -- so the operator is FLIPPED for the mirrored shape rather than the
/// fact being dropped.
fn cmp_fact(e : @ast.Expr) -> C? {
  match e.kind {
    @ast.EBin(op, a, b) =>
      match (a.kind, b.kind) {
        (@ast.EName(n), @ast.EInt(k)) =>
          match cmp_flip(op, false) {
            Some(o) =>
              Some({ name: n, op: o, value: k, line: e.span.start.line, })
            None => None
          }
        (@ast.EInt(k), @ast.EName(n)) =>
          match cmp_flip(op, true) {
            Some(o) =>
              Some({ name: n, op: o, value: k, line: e.span.start.line, })
            None => None
          }
        _ => None
      }
    _ => None
  }
}

///|
/// The comparison operator, mirrored when the literal is on the left. Returns
/// `None` for an operator that is not a comparison, which is what keeps `+` and
/// `&&` out of the fact model.
fn cmp_flip(op : @ast.BOp, flip : Bool) -> @ast.BOp? {
  match op {
    @ast.OpEq => Some(@ast.OpEq)
    @ast.OpLt => Some(if flip { @ast.OpGt } else { @ast.OpLt })
    @ast.OpLe => Some(if flip { @ast.OpGe } else { @ast.OpLe })
    @ast.OpGt => Some(if flip { @ast.OpLt } else { @ast.OpGt })
    @ast.OpGe => Some(if flip { @ast.OpLe } else { @ast.OpGe })
    _ => None
  }
}

///|
/// The constraint that holds when `e` is FALSE. A comparison negates to its
/// mirror, and De Morgan turns a conjunction into the disjunction that has no
/// interval -- so the answer is "no facts", never a guessed one.
fn negated_fact(e : @ast.Expr) -> C? {
  match e.kind {
    @ast.EBin(op, a, b) =>
      match (a.kind, b.kind) {
        (@ast.EName(n), @ast.EInt(k)) =>
          match neg_flip(op, false) {
            Some(o) =>
              Some({ name: n, op: o, value: k, line: e.span.start.line, })
            None => None
          }
        (@ast.EInt(k), @ast.EName(n)) =>
          match neg_flip(op, true) {
            Some(o) =>
              Some({ name: n, op: o, value: k, line: e.span.start.line, })
            None => None
          }
        _ => None
      }
    _ => None
  }
}

///|
fn neg_flip(op : @ast.BOp, flip : Bool) -> @ast.BOp? {
  match op {
    @ast.OpEq => None
    @ast.OpLt => Some(if flip { @ast.OpGe } else { @ast.OpGe })
    @ast.OpLe => Some(if flip { @ast.OpGt } else { @ast.OpGt })
    @ast.OpGt => Some(if flip { @ast.OpLe } else { @ast.OpLe })
    @ast.OpGe => Some(if flip { @ast.OpLt } else { @ast.OpLt })
    _ => None
  }
}

///|
/// Every constraint a guard ASSERTS, following `&&` on both sides. A disjunction
/// asserts nothing definite, so it contributes nothing.
fn facts_of(e : @ast.Expr, out : Array[C]) -> Unit {
  match e.kind {
    @ast.EBin(@ast.OpAnd, a, b) => {
      facts_of(a, out)
      facts_of(b, out)
    }
    _ =>
      match cmp_fact(e) {
        Some(c) => out.push(c)
        None => ()
      }
  }
}

///|
/// Every constraint that holds when the guard is FALSE. `&&` under negation
/// becomes a disjunction, which asserts nothing; `||` under negation becomes a
/// conjunction, which does.
fn negated_facts_of(e : @ast.Expr, out : Array[C]) -> Unit {
  match e.kind {
    @ast.EBin(@ast.OpOr, a, b) => {
      negated_facts_of(a, out)
      negated_facts_of(b, out)
    }
    _ =>
      match negated_fact(e) {
        Some(c) => out.push(c)
        None => ()
      }
  }
}

///|
/// The names a statement assigns anywhere inside it, including nested blocks and
/// loop bodies. Used to invalidate a fact set before a loop body, where the
/// number of iterations is unknown.
fn assigned_names(stmts : Array[@ast.Stmt], out : Array[String]) -> Unit {
  for s in stmts {
    match s.kind {
      @ast.SAssign(lhs, _) => expr_names(lhs, out)
      @ast.SLet(n, _, _) => out.push(n)
      @ast.SLetDestruct(ns, _) =>
        for n in ns {
          out.push(n)
        }
      @ast.SBlock(body) => assigned_names(body, out)
      @ast.SNoBreak(inner, body) => {
        assigned_names([inner], out)
        assigned_names(body, out)
      }
      @ast.SIf(_, then_, elifs, else_) => {
        assigned_names(then_, out)
        for ei in elifs {
          assigned_names(ei.body, out)
        }
        match else_ {
          Some(b) => assigned_names(b, out)
          None => ()
        }
      }
      @ast.SWhile(_, body) => assigned_names(body, out)
      @ast.SFor(_, _, _, body) => assigned_names(body, out)
      @ast.SForUpdate(body) => assigned_names(body, out)
      @ast.SLocalFunc(_, _, _, body, _) => assigned_names(body, out)
      @ast.SFunc(_, _, _, body, _) => assigned_names(body, out)
      _ => ()
    }
  }
}

///|
/// Every name mentioned anywhere in an expression. Deliberately over-approximate:
/// dropping one fact too many costs a finding, keeping one fact too many costs a
/// FALSE finding, and the two are not the same price.
fn expr_names(e : @ast.Expr, out : Array[String]) -> Unit {
  match e.kind {
    @ast.EName(n) => out.push(n)
    @ast.EField(b, _) => expr_names(b, out)
    @ast.EIndex(b, i) => {
      expr_names(b, out)
      expr_names(i, out)
    }
    @ast.EUnary(_, a) => expr_names(a, out)
    @ast.EBin(_, a, b) => {
      expr_names(a, out)
      expr_names(b, out)
    }
    @ast.ECall(_, args, _) =>
      for a in args {
        expr_names(a, out)
      }
    @ast.EMethodCall(base, _, args, _) => {
      expr_names(base, out)
      for a in args {
        expr_names(a, out)
      }
    }
    @ast.EDotDot(base, _, args, _) => {
      expr_names(base, out)
      for a in args {
        expr_names(a, out)
      }
    }
    @ast.EList(xs) | @ast.ETuple(xs) =>
      for x in xs {
        expr_names(x, out)
      }
    _ => ()
  }
}

///|
/// The analysis state for one function. `reports` accumulates; `facts` is passed
/// by value at each branch because each path owns its own condition.
priv struct Ctx {
  reports : Array[@report.Report]
  vst : Array[@core.Frame]
}

///|
fn Ctx::report(
  self : Ctx,
  family : @core.Family,
  msg : String,
  sp : @core.Span,
) -> Unit {
  self.reports.push(@report.Report::{
    family,
    lenses: [@core.LStructural],
    message: msg,
    span: sp,
    vst: self.vst,
  })
}

///|
/// Check a guard against the facts on the way to it, report what is justified,
/// and return the fact set that holds in its THEN body.
///
/// The three outcomes are decided here and nowhere else, so the reported
/// classification and the fact set handed to the body cannot disagree.
fn enter_guard(ctx : Ctx, facts : Facts, cond : @ast.Expr) -> Facts {
  let added : Array[C] = []
  facts_of(cond, added)
  if added.length() == 0 {
    // No fact from this guard. Not a finding and not a silence: undecided,
    // which the family's `excluded` contract names.
    let copy = facts_clone(facts)
    return copy
  }
  // (1) CONTRADICTION: does any name's accumulated facts plus this guard leave
  // no integer at all?
  let mut clash : Array[C] = []
  let mut clash_name = ""
  for c in added {
    let before = facts_get(facts, c.name)
    let after = ival_of(before).inter(c.ival())
    if after.is_empty() {
      clash = before
      clash_name = c.name
      break
    }
  }
  if clash_name != "" {
    let path = render_condition(clash, clash_name)
    ctx.report(
      @core.FInfeasibleBranch,
      "this branch can never run: D[P] = { } because \{path} contradicts \{render_guard(added, clash_name)}",
      cond.span,
    )
  }
  // (2) IMPLIED: does the guard change anything for any name it constrains? If
  // not, the test decides nothing and the ELSE arm has an empty domain.
  let mut implied = true
  for c in added {
    let before = ival_of(facts_get(facts, c.name))
    if before.is_empty() {
      // The path was already contradictory; that is (1)'s finding, and calling
      // it redundant as well would report one defect twice.
      implied = false
    } else if !before.inter(c.ival()).same(before) {
      implied = false
    }
  }
  if implied && clash_name == "" {
    ctx.report(
      @core.FRedundantGuard,
      "this test decides nothing: D[P] = \{render_guard(added, "")} already holds on the way here, so the other branch has an empty domain",
      cond.span,
    )
  }
  let body = facts_clone(facts)
  for c in added {
    facts_add(body, c)
  }
  body
}

///|
/// Render the constraints on one name as a path condition. Names are printed
/// with the values they were compared to, never as "something contradicts".
fn render_condition(cs : Array[C], name : String) -> String {
  let parts : Array[String] = []
  for c in cs {
    if c.name == name {
      parts.push("\{c.text()} (line \{c.line})")
    }
  }
  if parts.length() == 0 {
    "\{name} is unconstrained"
  } else {
    parts.join(" and ")
  }
}

///|
fn render_guard(cs : Array[C], only : String) -> String {
  let parts : Array[String] = []
  for c in cs {
    if only == "" || c.name == only {
      parts.push(c.text())
    }
  }
  "\{parts.join(" and ")}"
}

///|
/// Walk a block. `facts` is the path condition on entry; it is never mutated,
/// so a caller's set survives two sibling branches unchanged.
fn walk_stmts(ctx : Ctx, stmts : Array[@ast.Stmt], facts : Facts) -> Unit {
  let mut cur = facts
  for s in stmts {
    match s.kind {
      @ast.SIf(cond, then_, elifs, else_) => {
        let then_facts = enter_guard(ctx, cur, cond)
        walk_stmts(ctx, then_, then_facts)
        // The negative condition, accumulated: the path to `else if` i has
        // passed every guard before it, each on its FALSE side.
        let neg : Array[C] = []
        negated_facts_of(cond, neg)
        let neg_facts = facts_clone(cur)
        for c in neg {
          facts_add(neg_facts, c)
        }
        for ei in elifs {
          let elif_then = enter_guard(ctx, neg_facts, ei.cond)
          walk_stmts(ctx, ei.body, elif_then)
          let more : Array[C] = []
          negated_facts_of(ei.cond, more)
          for c in more {
            facts_add(neg_facts, c)
          }
        }
        match else_ {
          Some(b) => walk_stmts(ctx, b, neg_facts)
          None => ()
        }
      }
      @ast.SBlock(body) => walk_stmts(ctx, body, cur)
      @ast.SNoBreak(inner, body) => {
        walk_stmts(ctx, [inner], cur)
        walk_stmts(ctx, body, cur)
      }
      @ast.SLet(n, _, _) => {
        // Re-declaration: the name denotes something new, so no fact survives.
        let next = facts_clone(cur)
        facts_drop(next, n)
        cur = next
      }
      @ast.SLetDestruct(ns, _) => {
        let next = facts_clone(cur)
        for n in ns {
          facts_drop(next, n)
        }
        cur = next
      }
      @ast.SAssign(lhs, _) => {
        let names : Array[String] = []
        expr_names(lhs, names)
        let next = facts_clone(cur)
        for n in names {
          facts_drop(next, n)
        }
        cur = next
      }
      @ast.SWhile(_, body) => {
        cur = walk_loop(ctx, body, cur)
      }
      @ast.SFor(_, _, _, body) => {
        cur = walk_loop(ctx, body, cur)
      }
      @ast.SForUpdate(body) => {
        cur = walk_loop(ctx, body, cur)
      }
      @ast.SLocalFunc(_, _, _, body, _) =>
        // A local function is analysed as its own program: the facts of the
        // enclosing body are not facts about its parameters.
        walk_stmts(ctx, body, Map([]))
      @ast.SFunc(_, _, _, body, _) => walk_stmts(ctx, body, Map([]))
      _ => ()
    }
  }
}

///|
/// A loop body runs an unknown number of times, so a fact proved OUTSIDE it does
/// not survive one iteration for any name the body assigns. Those names lose
/// their facts before the body is entered; proving the body's own guards is then
/// still sound, which is the most this model can honestly claim.
///
/// THE SAME REMOVAL IS RETURNED, and that is not a convenience: the loop runs
/// zero or more times, so what holds AFTER it excludes every name it may have
/// assigned. Returning the pre-loop set unchanged was a real bug -- measured by
/// the 0522 test `a fact does not survive a loop body that assigns the name`,
/// which reported a contradictory branch that is in fact reachable.
fn walk_loop(ctx : Ctx, body : Array[@ast.Stmt], facts : Facts) -> Facts {
  let assigned : Array[String] = []
  assigned_names(body, assigned)
  let entry = facts_clone(facts)
  for n in assigned {
    facts_drop(entry, n)
  }
  walk_stmts(ctx, body, entry)
  entry
}

///|
/// The entry point: every function in a module body, analysed on its own.
///
/// Top-level statements are NOT analysed. A fact at module scope would have to
/// survive an unknown execution order between files, and the module view of the
/// behavioral lens already documents what happens when one file's entry state is
/// assumed to be another's.
pub fn guard_facts(body : Array[@ast.Stmt]) -> Array[@report.Report] {
  let ctx : Ctx = { reports: [], vst: [], }
  for s in body {
    match s.kind {
      @ast.SFunc(_, _, _, fbody, _) => walk_stmts(ctx, fbody, Map([]))
      @ast.SLocalFunc(_, _, _, fbody, _) => walk_stmts(ctx, fbody, Map([]))
      _ => ()
    }
  }
  ctx.reports
}
