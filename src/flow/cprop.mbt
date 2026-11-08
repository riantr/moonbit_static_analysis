// 0546: interprocedural constant propagation, as the deck states it.
//
// THE FRAMEWORK IS THE DECK'S, AND THE VALUE DOMAIN IS THE DECK'S. Tian Tan's
// `Interprocedural Analysis` (Nanjing University, 2021) uses constant
// propagation as its running example, and p.105 collects the whole analysis in
// SIX rules -- two about nodes and four about edges:
//
//     Node transfer
//       call nodes:    identity
//       other nodes:   same as intraprocedural constant propagation
//     Edge transfer
//       normal edges:            identity
//       call-to-return edges:    kill the value of the LHS variable of the call
//                                site, propagate values of other local variables
//       call edges:              pass argument values
//       return edges:            pass return values
//
// THREE OF THOSE SIX ARE RULES THAT NO NODE TRANSFER CAN EXPRESS -- the kill on
// the call-to-return edge, the argument values on the call edge, and the returned
// value on the return edge -- because each of them describes what happens ALONG
// AN EDGE, and out of one call node the same input state travels along two edges
// that must be transformed differently. That is the reason `worklist.mbt` grew
// `solve_edges` in this increment. The fourth edge rule (identity on ordinary
// edges) IS expressible as a node transfer, and is the reason this file's node
// transfer is written as one: the two solvers agree when it is the only one left,
// which `icfg_test.mbt` pins.
//
// THE VALUE DOMAIN IS THE USUAL FLAT ONE: `⊥` (no information yet), a constant,
// and `⊤` ("not a constant", the deck's `NAC`). Its carrier is INFINITE -- one
// constant per `Int32` -- and its HEIGHT is three. That combination is worth
// naming next to 0545: the enumeration in `laws_test.mbt` decides the lattice
// laws by trying every pair, which is only possible on a FINITE carrier, so it
// cannot reach this lattice; and the solvers still terminate, because Kleene's
// argument needs finite HEIGHT, not a finite carrier. Those are two different
// finiteness conditions and this package now contains a lattice that has the
// second without the first.
//
// THE CONSTANT FOLD IS BOUNDED ON PURPOSE. Folding is only attempted when both
// operands are inside +/-46340, a window in which `+`, `-` and `*` cannot
// overflow `Int32`; anything outside it answers `NAC`. A fold that overflowed
// would report a constant the program never computes, which is the one wrong
// answer that a constant-propagation lattice can give -- `NAC` is merely
// imprecise, and imprecision is the safe direction here.
//
// WHAT THIS FILE DOES NOT DO, AND WHY. It emits no finding and it analyses no
// corpus: it is the framework and its transfers, measured against the worked
// example the deck prints. Whether a "this call has a constant result" family
// should speak is a separate question with its own audit -- the last time a
// family started speaking on the corpora it produced nine findings whose classes
// had to be read one at a time (0542).

///|
/// A constant-propagation value: `⊥`, a constant, or `⊤`.
///
/// `Undef` is BOTH "no path has reached here yet" and "this name has no value on
/// this path", which is the standard reading of `⊥` in this analysis.
#derive(Eq)
pub(all) enum Cpv {
  Undef
  C(Int32)
  Nac
}

///|
/// A state: a value for every name that has one. An ABSENT name is `Undef`,
/// which is what makes the three edge transfers compose: the return edge
/// contributes `{b -> 10}` and the call-to-return edge contributes everything
/// but `b`, and their join is the whole state.
pub type State = Map[String, Cpv]

///|
/// The value of `x`, whose absence means `⊥`.
pub fn cprop_get(st : State, x : String) -> Cpv {
  match st.get(x) {
    Some(v) => v
    None => Undef
  }
}

///|
/// The state with `x` set to `v`, as a fresh map. Setting the bottom REMOVES the
/// key rather than storing it: one representation of "no information", not two.
pub fn cprop_set(st : State, x : String, v : Cpv) -> State {
  let out : State = Map([])
  for k, u in st {
    if k != x {
      out.set(k, u)
    }
  }
  match v {
    Undef => ()
    _ => out.set(x, v)
  }
  out
}

///|
/// The state with `x` removed -- deck p.103's "kill the value of the LHS variable
/// of the call site".
pub fn cprop_kill(st : State, x : String) -> State {
  let out : State = Map([])
  for k, u in st {
    if k != x {
      out.set(k, u)
    }
  }
  out
}

///|
fn cpv_join(a : Cpv, b : Cpv) -> Cpv {
  match a {
    Undef => b
    Nac => Nac
    C(x) =>
      match b {
        Undef => C(x)
        Nac => Nac
        C(y) => if x == y { C(x) } else { Nac }
      }
  }
}

///|
/// The lattice over `State`. `⊥` is the empty map, `⊔` is pointwise, and equality
/// is pointwise with an absent name read as `⊥`.
pub fn cprop_lattice() -> Lattice[State] {
  {
    bot: () => (Map([]) : State),
    join: (a, b) => {
      let out : State = Map([])
      for k, v in a {
        out.set(k, v)
      }
      for k, v in b {
        let j = match out.get(k) {
          Some(u) => cpv_join(u, v)
          None => cpv_join(Undef, v)
        }
        match j {
          Undef => ()
          _ => out.set(k, j)
        }
      }
      out
    },
    eq: (a, b) => {
      if a.length() != b.length() {
        return false
      }
      for k, v in a {
        let u = match b.get(k) {
          Some(u) => u
          None => return false
        }
        if u != v {
          return false
        }
      }
      true
    },
  }
}

///|
/// The deck's own notation, so a failing row quotes the slide it came from:
/// `⊥`, `NAC`, and the number.
pub fn cpv_text(v : Cpv) -> String {
  match v {
    Undef => "⊥"
    Nac => "NAC"
    C(n) => n.to_string()
  }
}

///|
/// A state as `a=6,b=7`, in NAME order so that two equal states print equally.
pub fn cprop_text(st : State) -> String {
  let ks : Array[String] = []
  for k, _ in st {
    ks.push(k)
  }
  ks.sort()
  let parts : Array[String] = []
  for k in ks {
    parts.push(k + "=" + cpv_text(cprop_get(st, k)))
  }
  parts.join(",")
}

///|
/// The window inside which `+`, `-` and `*` on `Int32` cannot overflow. See the
/// header; the exact number is the largest `n` with `n * n` representable.
const FOLD_LIMIT : Int32 = 46340

///|
fn fits(n : Int32) -> Bool {
  n <= FOLD_LIMIT && n >= -FOLD_LIMIT
}

///|
/// The value of an expression in a state.
///
/// `⊥` ABSORBS, AND THAT IS NOT A DETAIL OF STYLE. The solver seeds every node
/// with `⊥` and moves it up, so the FIRST sweep evaluates every expression on a
/// `⊥` input; a transfer that answered `⊤` for a `⊥` operand would write the TOP
/// of the lattice on that first sweep, and the join can never take it back down.
/// MEASURED, in this file's first version: `y = x + 1` was evaluated with
/// `x = ⊥` (the callee's entry had not been reached yet), answered `NAC`, and the
/// `NAC` propagated into `b = addOne(a)` -- the deck's p.104 `b=10` came out
/// `b=NAC` while every other number in the table was right. The edge log named
/// the witness: the same edge was transferred twice, first with `in={y=NAC}` and
/// then with `in={x=6,y=7}`, and the first one had already poisoned the join.
///
/// ONLY THE SHAPES A CONSTANT CAN SURVIVE ARE MODELLED, and everything else --
/// a call's result, a field, an index, a comparison -- answers `NAC`. That is the
/// safe direction: `NAC` costs precision and never claims a value the program
/// does not compute.
pub fn cprop_eval(st : State, e : @ast.Expr) -> Cpv {
  match e.kind {
    @ast.EInt(n) => C(n)
    @ast.EName(x) => cprop_get(st, x)
    @ast.EBin(op, a, b) => {
      let va = cprop_eval(st, a)
      let vb = cprop_eval(st, b)
      match va {
        // ⊥ absorbs: nothing has been computed here yet, so neither has this.
        Undef => Undef
        Nac => Nac
        C(x) =>
          match vb {
            Undef => Undef
            Nac => Nac
            C(y) => cprop_fold(op, x, y)
          }
      }
    }
    _ => Nac
  }
}

///|
fn cprop_fold(op : @ast.BOp, x : Int32, y : Int32) -> Cpv {
  if !fits(x) || !fits(y) {
    return Nac
  }
  match op {
    @ast.OpAdd => C(x + y)
    @ast.OpSub => C(x - y)
    @ast.OpMul => C(x * y)
    // Division and the rest are deliberately outside the window: `x / 0` is not
    // a wart to patch but a shape this analysis does not model.
    _ => Nac
  }
}

///|
/// The node transfer of p.105.
///
/// THE FIRST LINE IS THE ONE THAT LOOKS LIKE AN OMISSION AND IS NOT: at a call
/// node the transfer is the IDENTITY, so `b = ten()` does not set `b` to anything
/// here. The deck gives the reason on p.87 -- "leave the handling of the LHS
/// variable (return value) to edge transfer" -- and it is the reason the two-edge
/// split is possible at all: if the node assigned `b`, there would be one answer
/// instead of two, and killing the stale value would be impossible.
pub fn cprop_node_transfer(kinds : Array[NodeKind]) -> (Int32, State) -> State {
  fn(v, st) {
    let kind = kinds[v]
    match call_shape(kind) {
      // a call node: identity, whatever its left-hand side says
      Some(_) => st
      None =>
        match kind {
          Assign(x, e) => cprop_set(st, x, cprop_eval(st, e))
          Store(x, e) => cprop_set(st, x, cprop_eval(st, e))
          // A destructuring let binds several names to parts of one value, and
          // this analysis has no way to say which part is which.
          AssignMulti(names, _) => {
            let out = st
            let mut i = 0
            let mut acc = out
            while i < names.length() {
              acc = cprop_set(acc, names[i], Nac)
              i = i + 1
            }
            acc
          }
          _ => st
        }
    }
  }
}

///|
/// The edge transfers of p.105, all four in one match.
///
/// THE ARGUMENTS ARE `(label, from, to, state)`, and `from`/`to` are unused by
/// every rule the deck states -- they are in the signature because an edge
/// transfer that needs to know its endpoints is the next increment's problem, not
/// this one's, and a signature that has to grow is a signature every caller has
/// to be edited for.
pub fn cprop_edge_transfer(
  label : EdgeKind,
  from : Int32,
  to : Int32,
  st : State,
) -> State {
  let _ = from
  let _ = to
  match label {
    Normal => st
    // KILL, DO NOT CARRY. This is p.103's boxed rule and the difference between
    // `a=6,b=NAC,c=4` and `a=6,b=10,c=4`.
    CallToReturn(lhs) =>
      match lhs {
        Some(x) => cprop_kill(st, x)
        None => st
      }
    // PASS THE ARGUMENT VALUES AND NOTHING ELSE. The output holds the callee's
    // parameters and no other name, which is the restriction that keeps the
    // caller's locals out of the callee.
    Call(args, params) => {
      let out : State = Map([])
      let mut i = 0
      while i < args.length() && i < params.length() {
        let v = cprop_eval(st, args[i])
        match v {
          Undef => ()
          _ => out.set(params[i], v)
        }
        i = i + 1
      }
      out
    }
    // PASS THE RETURNED VALUE, to the caller's left-hand side only.
    Ret(expr, lhs) =>
      match lhs {
        None => (Map([]) : State)
        Some(x) => {
          let v = match expr {
            Some(e) => cprop_eval(st, e)
            // "this function's value is not modelled" is `NAC`, not `UNDEF`:
            // `UNDEF` would let a return value from another exit win the join,
            // which is the unsound direction.
            None => Nac
          }
          cprop_set(Map([]), x, v)
        }
      }
  }
}

///|
/// The fixed point of the interprocedural framework: `state[v]` is the state
/// BEFORE node `v`, for the flat node space of `g`.
pub fn cprop_run(g : Icfg) -> Array[State] {
  solve_edges(
    cprop_lattice(),
    g.kinds.length(),
    g.succ,
    g.labels,
    cprop_node_transfer(g.kinds),
    cprop_edge_transfer,
  )
}

///|
/// The state AFTER node `v`, which is what a reader of a dump wants to see next
/// to the statement.
///
/// THE TRANSFER IS BOUND TO A NAME BEFORE IT IS APPLIED, and that is not style:
/// this tree's own analyzer reported `only named functions and methods can be
/// called` on the line that applied the result of a call, and the self-scan
/// counted the file as PARTIAL (`unreliable=1`). The frontend refuses a call
/// whose callee is not a name or a method, so a curried application has to be
/// written as two steps.
pub fn cprop_after(g : Icfg, states : Array[State], v : Int32) -> State {
  let t = cprop_node_transfer(g.kinds)
  t(v, states[v])
}
