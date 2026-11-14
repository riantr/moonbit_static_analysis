// 0571: THE SIGN DOMAIN -- the lecture's own worked example, as an analysis.
//
// THE DECK. `Introduction` (Yue Li, Nanjing University), p.45-58. The p.45
// slide is titled "Static Analysis -- An Example", and it names TWO
// APPLICATIONS and ONE ANALYSIS:
//
//     Determine the sign (+, -, or 0) of all the variables of a given program.
//       - To check divided by zero error
//       - To check negative array indices
//
// so the analysis and the two checks are ONE slide's worth of material. This
// file is the analysis; `src/pipeline/signcheck.mbt` is the two checks.
//
// WHY A DOMAIN OF ITS OWN, WHEN THIS PACKAGE ALREADY HAS CONSTANT PROPAGATION
// AND INTERVALS. The deck's domain is NOT constant propagation: it cannot say
// what a value IS, only what its SIGN is, and that is exactly what the two
// applications need -- "is the divisor zero" and "is the index negative" are
// questions about the SIGN, and a constant-propagation lattice answers them
// only when the value happens to be a literal constant. `cprop.mbt` cannot say
// "this divisor is `0`" about a divisor that is `x - x`, and it cannot say
// "this index is negative" at all, because it has no notion of negative.
//
// THE DOMAIN IS THE DECK'S, not a convenient one. p.48 prints the abstract
// domain as four boxes -- `+`, `O`, `unknown`, `undefined` -- and p.46-47 show
// the concrete values each abstracts to:
//
//     v = 1            -> +
//     v = -1           -> -
//     v = 0            -> O
//     v = e ? 1 : -1   -> unknown   (two signs, so the sign is not determined)
//     v = w / 0        -> undefined (w is unknown and the divisor is zero)
//     v = 1000         -> +
//
// THE ORDER IS THEREFORE: `undefined` (⊥) at the bottom, the three concrete
// signs in the middle -- pairwise INCOMPARABLE, because a value that is
// sometimes `+` and sometimes `-` is not "more `+`" than anything -- and
// `unknown` (⊤) at the top. The deck's own transfer table is the evidence for
// the middle layer: `+ + - = ⊤` is a JOIN, and the join of two incomparable
// elements is the top.
//
// THE TRANSFER FUNCTIONS ARE THE DECK'S TABLE, ROW BY ROW. p.54 prints four
// rows of addition and four of division; p.56 prints the fifth division row:
//
//     addition            division
//     +  +  +  = +        +  /  +  = +
//     -  +  -  = -        -  /  -  = +
//     O  +  O  = O        T  /  O  = ⊥
//     +  +  -  = T        +  /  -  = -
//                          O  /  -  = O
//
// The table is transcribed, not paraphrased, and `sign_test.mbt` asserts every
// row of it. The rows the deck DOES NOT print -- subtraction, multiplication,
// the remainder -- are derived from the same two principles (the result's sign
// is determined when the operands determine it, and unknown otherwise) and are
// marked as such in the code below, because a reader who cannot tell the
// deck's rows from the derived ones is reading a table that lies.
//
// WHAT THE DOMAIN IS GOOD FOR, AND WHAT IT IS NOT. The sign of a value is a
// MUST answer: "the divisor is zero" means the divisor is zero on EVERY path
// that reaches the division. The lattice's top is therefore not a failure but
// the normal answer for a value the analysis cannot pin down, and every
// question this domain is asked is asked in the direction where the top means
// "no finding". That direction is why the domain is USED for these two
// applications and not for others.

///|
/// One abstract value: the SIGN of an integer.
///
/// `SBot` is the deck's `undefined` and `STop` its `unknown`; the three
/// middle values are the three concrete signs.
#derive(Eq)
pub(all) enum Sign {
  /// ⊥ -- "undefined": the value does not exist.
  ///
  /// THE DECK USES THIS FOR A DIVISION BY ZERO (`T / O = ⊥`, p.56): the
  /// expression has no value because the program fails before it can have one.
  /// It is also the bottom of the lattice, so a name that has no value yet is
  /// `SBot` -- the same convention `cprop.mbt` uses for `Undef`, and for the
  /// same reason: ONE representation of "no information", not two.
  SBot
  /// O -- the value is zero.
  SZero
  /// + -- the value is strictly positive.
  SPos
  /// - -- the value is strictly negative.
  SNeg
  /// ⊤ -- "unknown": the value is one of several signs.
  STop
}

///|
/// The abstract value's own name, for a message that has to say WHICH sign.
pub fn Sign::sign_name(self : Sign) -> String {
  match self {
    SBot => "undefined"
    SZero => "zero"
    SPos => "positive"
    SNeg => "negative"
    STop => "unknown"
  }
}

///|
/// The LATTICE JOIN: the least upper bound of two signs.
///
/// THE ORDER IS THE DECK'S, so the join has three cases and no others:
///
///   * `⊥` is the bottom, so `⊥ ⊔ x = x` -- a name with no value yet does not
///     make the value unknown;
///   * `⊤` is the top, so `x ⊔ ⊤ = ⊤`;
///   * the three concrete signs are INCOMPARABLE, so two DIFFERENT ones join
///     to `⊤`. `+ ⊔ - = ⊤` is the deck's own `+ + - = T` row (p.54).
///
/// THE `⊥ ⊔ x = x` CASE IS THE ONE THAT NEEDS AN ASSUMPTION, and the
/// assumption is the language's, not this file's: MoonBit requires a local to
/// be initialised at its declaration, and a declaration dominates every use of
/// the name, so a name is never "no value on one path, a value on another".
/// The case that remains is a name that has NOT BEEN DECLARED YET, and a use
/// of such a name is answered as `STop` (unknown) rather than as its stale
/// value -- see `sign_of_expr`.
pub fn sign_join(a : Sign, b : Sign) -> Sign {
  if a == b {
    return a
  }
  if a == STop || b == STop {
    return STop
  }
  if a == SBot {
    return b
  }
  if b == SBot {
    return a
  }
  STop
}

///|
/// The lattice ORDER: `a ⊑ b` -- "a is at least as precise as b".
///
/// `⊥` is below everything and `⊤` is above everything, and two DIFFERENT
/// concrete signs are incomparable. This is the order `sign_join` is the least
/// upper bound in, and `sign_test.mbt` checks the pair on every carrier
/// element.
pub fn sign_leq(a : Sign, b : Sign) -> Bool {
  if a == b {
    return true
  }
  if b == STop {
    return true
  }
  if a == SBot {
    return true
  }
  false
}

///|
/// The sign lattice, as the framework wants it.
///
/// THE CARRIER IS FINITE -- five elements -- so this lattice's laws CAN be
/// enumerated by trying every pair, which is what `laws_test.mbt` does for the
/// other two finite lattices in this package and what `sign_test.mbt` does for
/// this one.
pub fn sign_lattice() -> Lattice[Sign] {
  {
    bot: fn() { SBot },
    join: fn(a, b) { sign_join(a, b) },
    eq: fn(a, b) { a == b },
  }
}

///|
/// The NEGATION of a sign: `x - y` is `x + (-y)`.
pub fn sign_negate(s : Sign) -> Sign {
  match s {
    SPos => SNeg
    SNeg => SPos
    SZero => SZero
    STop => STop
    SBot => SBot
  }
}

///|
/// ADDITION -- the deck's table (p.54, p.56), row by row.
///
///     +  +  +  = +
///     -  +  -  = -
///     O  +  O  = O
///     +  +  -  = T
///
/// WHICH IS: the sum's sign is determined exactly when the two operands have
/// the SAME sign, and unknown otherwise. `+ ⊕ O = T` is not printed on the
/// slide, and it is right that it is not: the sum of a positive number and a
/// zero is either zero or positive, so its sign is not determined.
pub fn sign_add(a : Sign, b : Sign) -> Sign {
  if a == SBot || b == SBot {
    return SBot
  }
  if a == STop || b == STop {
    return STop
  }
  if a == b {
    return a
  }
  STop
}

///|
/// SUBTRACTION -- NOT a row of the deck's table, and derived from the deck's
/// two principles.
///
/// `x - y` is `x + (-y)`, with TWO refinements the derivation needs: `x - 0`
/// is `x`, so a zero right-hand side does not blur the left-hand side's sign;
/// and `0 - y` is `-y`, so a zero left-hand side gives the right-hand side's
/// sign the other way round. Both are facts about the OPERATION, and both
/// matter: `0 - 1` is definitely negative, and a negative index is out of
/// bounds.
pub fn sign_sub(a : Sign, b : Sign) -> Sign {
  if b == SZero {
    return a
  }
  if a == SZero {
    return sign_negate(b)
  }
  sign_add(a, sign_negate(b))
}

///|
/// MULTIPLICATION -- NOT a row of the deck's table, and derived.
///
/// The product's sign is determined when both operands are: equal signs give
/// `+`, opposite signs give `-`. A zero factor gives zero whatever the other
/// factor is -- `0 * unknown = 0` is a fact, not an imprecision, because the
/// product is zero however much the other factor varies.
pub fn sign_mul(a : Sign, b : Sign) -> Sign {
  if a == SBot || b == SBot {
    return SBot
  }
  if a == SZero || b == SZero {
    return SZero
  }
  if a == STop || b == STop {
    return STop
  }
  if a == b {
    SPos
  } else {
    SNeg
  }
}

///|
/// DIVISION -- the deck's table (p.54, p.56), row by row.
///
///     +  /  +  = +
///     -  /  -  = +
///     T  /  O  = ⊥
///     +  /  -  = -
///     O  /  -  = O
///
/// THE `T / O = ⊥` ROW IS THE DECK'S DIVISION-BY-ZERO ROW, and it is the one
/// the first application is built on: a divisor that is zero makes the
/// expression have NO value, because the program fails before it can have one.
/// A divisor that is zero and a numerator that is KNOWN gives the same `⊥` --
/// the deck prints only the `⊤ / O` row because it is the one its worked
/// example needs, and `+ / O` is the same fact with a narrower numerator.
pub fn sign_div(a : Sign, b : Sign) -> Sign {
  if b == SZero {
    return SBot
  }
  if a == SBot || b == SBot {
    return SBot
  }
  if a == SZero {
    return SZero
  }
  if a == STop || b == STop {
    return STop
  }
  if a == b {
    SPos
  } else {
    SNeg
  }
}

///|
/// The REMAINDER's sign -- NOT a row of the deck's table.
///
/// `a % b` has the sign of `a` in every language whose remainder follows the
/// dividend, and that is a fact about the OPERATOR, not about the deck. It is
/// left as `STop` here rather than asserted: this package has no operator
/// semantics table to settle it against, and a sign the analysis cannot
/// justify is a sign it must not report.
pub fn sign_mod(_a : Sign, b : Sign) -> Sign {
  if b == SZero {
    return SBot
  }
  STop
}

///|
/// A state: the sign of every name the analysis knows.
///
/// AN ABSENT NAME IS `⊥` -- "no value yet" -- and that is the same convention
/// `cprop.mbt` uses for `Undef`, and for the same reason: ONE representation
/// of "no information", not two. The difference from constant propagation is
/// in the READ, not the representation: a read of a name with no value is
/// answered `STop` (unknown), because a name that has no value yet is a
/// parameter or an outer binding, and either of those can be anything.
pub type SignState = Map[String, Sign]

///|
/// The empty state: no name has a value.
pub fn sign_state_empty() -> SignState {
  Map([])
}

///|
/// The state with `x` set to `v`, as a FRESH map.
///
/// Setting the bottom REMOVES the key rather than storing it, so that "no
/// value" has exactly one representation -- the same rule `cprop_set` states
/// for `Undef`, and for the same reason: two representations of one fact is a
/// fact that can disagree with itself.
pub fn sign_state_set(st : SignState, x : String, v : Sign) -> SignState {
  let out : SignState = Map([])
  for k, u in st {
    if k != x {
      out.set(k, u)
    }
  }
  match v {
    SBot => ()
    _ => out.set(x, v)
  }
  out
}

///|
/// The state join: pointwise, over the union of the two name sets.
pub fn sign_state_join(a : SignState, b : SignState) -> SignState {
  let out : SignState = Map([])
  for k, u in a {
    let w = match b.get(k) {
      Some(x) => x
      None => SBot
    }
    out.set(k, sign_join(u, w))
  }
  for k, u in b {
    if a.contains(k) == false {
      out.set(k, u)
    }
  }
  out
}

///|
/// State equality, by name set and by value.
pub fn sign_state_eq(a : SignState, b : SignState) -> Bool {
  let mut same = true
  for k, _ in a {
    if b.contains(k) == false {
      same = false
    }
  }
  for k, _ in b {
    if a.contains(k) == false {
      same = false
    }
  }
  if same {
    for k, u in a {
      match b.get(k) {
        Some(v) => if u != v { same = false }
        None => ()
      }
    }
  }
  same
}

///|
/// The state lattice: a map of names to signs, joined pointwise.
pub fn sign_state_lattice() -> Lattice[SignState] {
  {
    bot: fn() { sign_state_empty() },
    join: fn(a, b) { sign_state_join(a, b) },
    eq: fn(a, b) { sign_state_eq(a, b) },
  }
}

///|
/// THE SIGN OF AN EXPRESSION, in a state.
///
/// EVERY UNKNOWN SHAPE IS `STop`, and that is the whole safety argument of
/// this file: the two applications ask "is this definitely zero" and "is this
/// definitely negative", so a shape the analysis cannot pin down must answer
/// `STop`, and `STop` answers "no" to both questions.
///
/// THE READ OF A NAME WITH NO VALUE IS `SBot` -- "no value" -- AND THAT IS THE
/// MONOTONICITY THE FIXED POINT NEEDS. The state's order is the deck's, so
/// `SBot` is the BOTTOM and `STop` is the TOP; a read that answered `STop`
/// would map the smallest input to the largest output, and the iteration
/// could never rise out of it. MEASURED, the bug that says so: with the read
/// answering `STop`, the first sweep of a straight-line function computed
/// `b = z / y` with `z` not yet assigned -- so `z` read as unknown, `b` read
/// as unknown, and the state carried that unknown FOREVER, because the
/// solver JOINS each new value into the old one and a join with the top is
/// the top. The division by zero the deck's own example contains was then
/// never reported.
///
/// SO A NAME WITH NO VALUE READS AS NO VALUE, and the names whose value the
/// analysis genuinely cannot know -- the ones the CALLER or the MODULE
/// chooses -- are seeded as `STop` at the entry instead. `sign_transfer` takes
/// them as an argument for exactly this reason.
pub fn sign_of_expr(e : @ast.Expr, st : SignState) -> Sign {
  match e.kind {
    @ast.EInt(n) => if n > 0 { SPos } else if n < 0 { SNeg } else { SZero }
    // A literal too big for an Int32: the parser keeps no value for it, so the
    // sign is not available either. `STop`, not a guess.
    @ast.EBigInt => STop
    @ast.EName(n) =>
      match st.get(n) {
        Some(s) => s
        None => SBot
      }
    @ast.EUnary(@ast.UNeg, a) => sign_negate(sign_of_expr(a, st))
    @ast.EUnary(@ast.UNot, _) => STop
    @ast.EBin(op, a, b) => {
      let sa = sign_of_expr(a, st)
      let sb = sign_of_expr(b, st)
      match op {
        @ast.OpAdd => sign_add(sa, sb)
        @ast.OpSub => sign_sub(sa, sb)
        @ast.OpMul => sign_mul(sa, sb)
        @ast.OpDiv => sign_div(sa, sb)
        @ast.OpMod => sign_mod(sa, sb)
        // Every other operator produces a Bool, a bit pattern or a pipe, and
        // none of them is an integer whose sign this domain can speak about.
        _ => STop
      }
    }
    // A subscript's VALUE is the element's, and this domain says nothing about
    // element types -- but the INDEX is what the second application asks about,
    // and the index is read by the caller of `sign_of_expr`, not here.
    @ast.EIndex(_, _) => STop
    _ => STop
  }
}

///|
/// The sign TRANSFER FUNCTION: what a node does to the state.
///
/// A node that ASSIGNS a name gives that name the sign of the expression; a
/// node that only READS leaves the state alone. A `PlaceStore` (`x.f = e`,
/// `xs[i] = e`) READS its base and its index and writes through them, so it
/// defines no name -- the same rule `node_defs` states for liveness, and for
/// the same reason: a field is not the name.
pub fn sign_transfer(
  g : Cfg,
  unknown : Array[String],
) -> (Int32, SignState) -> SignState {
  fn(node, st) {
    let mut out = st
    match g.kinds[node] {
      // THE ENTRY SEEDS THE NAMES WHOSE VALUE THE ANALYSIS CANNOT KNOW. A
      // parameter is chosen by the caller and a module-level binding by the
      // module, and neither is known here, so both are UNKNOWN -- which is a
      // different fact from "no value", and the difference is what keeps the
      // transfer monotone.
      Entry =>
        for x in unknown {
          out = sign_state_set(out, x, STop)
        }
      Assign(x, e) => out = sign_state_set(out, x, sign_of_expr(e, st))
      Store(x, e) => out = sign_state_set(out, x, sign_of_expr(e, st))
      AssignMulti(names, e) => out = sign_assign_multi(names, e, st)
      _ => ()
    }
    out
  }
}

///|
/// The state after a DESTRUCTURING assignment.
///
/// A tuple's elements each carry their own sign, and the tuple's own sign is
/// not a sign at all -- so `let (a, b) = (1, -1)` gives `a` the sign of `1` and
/// `b` the sign of `-1`, rather than giving both of them "unknown".
///
/// Anything else -- a call, a tuple of unknown values -- gives every name the
/// expression's sign, which for such an expression is `STop`: imprecise, and
/// in the safe direction.
fn sign_assign_multi(
  names : Array[String],
  e : @ast.Expr,
  st : SignState,
) -> SignState {
  let mut out = st
  match e.kind {
    @ast.ETuple(xs) =>
      for i in 0..<names.length() {
        if i < xs.length() {
          out = sign_state_set(out, names[i], sign_of_expr(xs[i], st))
        }
      }
    _ =>
      for n in names {
        out = sign_state_set(out, n, sign_of_expr(e, st))
      }
  }
  out
}

///|
/// The fixed point: `before[v]` is the sign state BEFORE node `v`.
///
/// A FORWARD analysis, so the join-neighbours of a node are its PREDECESSORS
/// and the solver's convention is the propagation one (`state[v]` is the state
/// BEFORE `v`). The entry node has no predecessors, so its state is the empty
/// state -- every name has no value, and a read of one is answered `STop`.
///
/// THE ENTRY STATE IS NOT "EVERY NAME IS UNKNOWN" AND THAT IS THE POINT. The
/// empty state says "no name has a value YET" -- so a local is without a value
/// until its declaration assigns it -- and the names the CALLER or the MODULE
/// chooses are seeded as unknown by the entry's transfer, because they DO have
/// a value and the analysis does not know it.
pub fn sign_before(g : Cfg, unknown : Array[String]) -> Array[SignState] {
  solve_propagation(
    sign_state_lattice(),
    g.kinds.length(),
    g.succ,
    sign_transfer(g, unknown),
  )
}
