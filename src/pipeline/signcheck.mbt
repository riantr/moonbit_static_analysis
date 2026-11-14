// 0571: THE DECK'S TWO APPLICATIONS -- division by zero, and negative
// indices.
//
// THE DECK. `Introduction` (Yue Li, Nanjing University), p.45. The slide is
// "Static Analysis -- An Example", and its two bullets are the two things this
// file exists to report:
//
//     To check divided by zero error
//     To check negative array indices
//
// and the analysis that decides both is on the same slide: "Determine the sign
// (+, -, or 0) of all the variables of a given program". The sign domain and
// the deck's transfer table are `src/flow/sign.mbt`; this file asks the two
// questions of that domain's answer.
//
// THE ORACLE. The TOOLCHAIN CATCHES NEITHER SHAPE. Measured against
// `moon check` on a probe holding all five shapes -- `1 / 0`, `10 / y`,
// `arr[-1]`, `arr[0 - 1]`, `arr[0]` -- the compiler exits 0 and says nothing
// about either of them (only `unused_value` and `struct_never_constructed`).
// So a finding here is NOT a duplicate of what the compiler already says: it
// is the only thing in the toolchain that says it.
//
// THE TWO CLAIMS ARE SEPARATE FAMILIES, because they are separate claims
// about separate operands. `MSA-016` is about the DIVISOR; `MSA-017` is about
// the INDEX. One line can carry both -- `a / b[0]` -- and a reader who had one
// family for both would have to guess which operand the finding was about.
//
// THE DIRECTION OF EVERY QUESTION IS "DEFINITELY". The sign domain's top is
// "unknown", so a divisor whose sign is unknown is NOT reported: the tool
// says "this division MAY divide by zero" only when it can say "this division
// DOES divide by zero". That is the only safe direction for a claim about a
// crash, and it is why the same domain can be used for an index (which may be
// out of bounds) and for a divisor (which will crash).
//
// THE FUNCTION-LEVEL GUARDS ARE THE DEAD-STORE FAMILY'S, and they are the
// same guards for the same reason. A statement the GRAPH did not convert is a
// path the graph cannot see, and a region the FRONTEND did not read is a path
// the analysis never had. Both make a claim about a whole function unsafe,
// so both make this family decline the whole function rather than report
// inside it.

///|
/// The findings of both applications, over one module's function bodies.
///
/// `unread` is the frontend's list of regions it chose not to analyse; a
/// function whose extent contains one of them is not analysed by this family.
pub fn sign_findings(
  body : Array[@ast.Stmt],
  unread : Array[@core.Span],
) -> Array[@report.Report] {
  let out : Array[@report.Report] = []
  for s in body {
    match s.kind {
      @ast.SFunc(_, _, _, fbody, extent) =>
        if !has_hole(extent, unread) {
          one_sign_body(fbody, out)
        }
      @ast.SLocalFunc(_, _, _, fbody, extent) =>
        if !has_hole(extent, unread) {
          one_sign_body(fbody, out)
        }
      _ => ()
    }
  }
  out
}

///|
/// One function body.
fn one_sign_body(fbody : Array[@ast.Stmt], out : Array[@report.Report]) -> Unit {
  let g = @flow.cfg_of(fbody)
  // A statement the graph did not convert is a path it cannot see. Decline
  // rather than report: "the divisor is zero" is a claim about every path
  // that reaches the division, and a missing edge can falsify it.
  if g.skipped > 0 {
    return
  }
  let befores = @flow.sign_before(g, unknown_names(g))
  // The findings are collected into a LOCAL array first, because a function
  // that holds a region the GRAPH does not model is not analysed at all -- see
  // `check_expr`'s block case.
  let mine : Array[@report.Report] = []
  let mut holed = false
  let mut v = 0
  while v < g.kinds.length() {
    match g.kinds[v] {
      @flow.Assign(_, e) | @flow.Store(_, e) | @flow.AssignMulti(_, e) =>
        if check_expr(e, befores[v], mine) {
          holed = true
        }
      @flow.Eval(e) | @flow.Test(e) =>
        if check_expr(e, befores[v], mine) {
          holed = true
        }
      @flow.PlaceStore(target, e) => {
        if check_expr(target, befores[v], mine) {
          holed = true
        }
        if check_expr(e, befores[v], mine) {
          holed = true
        }
      }
      _ => ()
    }
    v = v + 1
  }
  if holed == false {
    for r in mine {
      out.push(r)
    }
  }
}

///|
/// THE NAMES WHOSE VALUE THE ANALYSIS CANNOT KNOW.
///
/// A name the function READS but never ASSIGNS is chosen by somebody else: a
/// parameter is chosen by the caller and a module-level binding by the module.
/// Neither is known here, so both are UNKNOWN -- which is a different fact
/// from "no value", and the difference is what keeps the transfer monotone
/// (see `sign_of_expr`).
///
/// The sets are the GRAPH's own: `node_uses` is the definition of a read the
/// liveness pass already uses, and `node_defs` the definition of a write. A
/// second walk here would be a second definition of the same thing, and the
/// two would drift apart.
fn unknown_names(g : @flow.Cfg) -> Array[String] {
  let defs : Map[String, Bool] = Map([])
  let uses : Map[String, Bool] = Map([])
  for k in g.kinds {
    for n in @flow.node_defs(k).keys() {
      defs.set(n, true)
    }
    for n in @flow.node_uses(k).keys() {
      uses.set(n, true)
    }
  }
  let out : Array[String] = []
  for n in uses.keys() {
    if defs.contains(n) == false {
      out.push(n)
    }
  }
  out
}

///|
/// Walk one expression, and report what the two applications find in it.
///
/// RETURNS TRUE WHEN IT REACHED A REGION THE GRAPH DOES NOT MODEL, and that
/// return value is not a detail: a block used as a VALUE (`let x = { .. }`)
/// holds STATEMENTS, and the control-flow graph does not turn them into nodes.
/// A name such a block assigns would still carry its old value in the state
/// this analysis reads, so a division after the block would be judged against
/// a value the block has already replaced -- a FALSE POSITIVE. So a function
/// holding one is not analysed at all, and the family says so in `excluded`
/// rather than guessing.
///
/// The `try`, `catch` and `match` arms are holes for the same reason: their
/// bodies are statements. In practice the frontend never reads them (each is a
/// declared subset exclusion), so the function is already excluded by the
/// unread-region rule; returning true here is the belt to that pair of braces.
fn check_expr(
  e : @ast.Expr,
  st : @flow.SignState,
  out : Array[@report.Report],
) -> Bool {
  match e.kind {
    @ast.EBin(op, a, b) => {
      // THE FIRST APPLICATION. `/` and `%` are the two operators that fail on a
      // zero divisor; the deck names the division, and the remainder fails the
      // same way at run time, so it is reported under the same claim.
      if op == @ast.OpDiv || op == @ast.OpMod {
        if @flow.sign_of_expr(b, st) == @flow.SZero && float_expr(a) == false {
          out.push(@report.Report::{
            family: @core.FDivisionByZero,
            lenses: [@core.LStructural],
            message: divisor_message(b),
            span: b.span,
            vst: [],
          })
        }
      }
      let ha = check_expr(a, st, out)
      let hb = check_expr(b, st, out)
      ha || hb
    }
    @ast.EIndex(base, idx) => {
      // THE SECOND APPLICATION. The index of a subscript: a negative index is
      // out of bounds, in every container this language has.
      if @flow.sign_of_expr(idx, st) == @flow.SNeg {
        out.push(@report.Report::{
          family: @core.FNegativeIndex,
          lenses: [@core.LStructural],
          message: index_message(idx),
          span: idx.span,
          vst: [],
        })
      }
      let hb1 = check_expr(base, st, out)
      let hb2 = check_expr(idx, st, out)
      hb1 || hb2
    }
    @ast.EList(xs) | @ast.ETuple(xs) => check_exprs(xs, st, out)
    @ast.EUnary(_, a) => check_expr(a, st, out)
    @ast.EAsBind(a, _) => check_expr(a, st, out)
    @ast.ETupleField(a, _) => check_expr(a, st, out)
    @ast.EIs(a, _) => check_expr(a, st, out)
    @ast.ECast(a) => check_expr(a, st, out)
    @ast.EField(a, _) => check_expr(a, st, out)
    @ast.ECall(_, args, _) => check_exprs(args, st, out)
    @ast.EMethodCall(a, _, args, _) => {
      let h1 = check_expr(a, st, out)
      let h2 = check_exprs(args, st, out)
      h1 || h2
    }
    @ast.EDotDot(a, _, args, _) => {
      let h1 = check_expr(a, st, out)
      let h2 = check_exprs(args, st, out)
      h1 || h2
    }
    @ast.ERange(a, b) => {
      let h1 = check_expr(a, st, out)
      let h2 = check_expr(b, st, out)
      h1 || h2
    }
    @ast.EComp(_, iters, grd, body) => {
      let h1 = check_exprs(iters, st, out)
      let h2 = match grd {
        Some(g) => check_expr(g, st, out)
        None => false
      }
      let h3 = check_expr(body, st, out)
      h1 || h2 || h3
    }
    @ast.EStruct(_, fields) => {
      let mut holed = false
      for pair in fields {
        if check_expr(pair.1, st, out) {
          holed = true
        }
      }
      holed
    }
    @ast.ECatch(a, arms) | @ast.ENoRaise(a, arms) => {
      // The arms' BODIES are statements the graph does not model, so the
      // function is not analysed. The arms' GUARDS are expressions, and they
      // are still walked -- but the function's findings are discarded anyway,
      // because this arm reports a hole.
      let _ = check_expr(a, st, out)
      for arm in arms {
        match arm.cond {
          Some(c) => {
            let _ = check_expr(c, st, out)
          }
          None => ()
        }
      }
      true
    }
    @ast.EMatch(a, arms) => {
      let _ = check_expr(a, st, out)
      for arm in arms {
        match arm.cond {
          Some(c) => {
            let _ = check_expr(c, st, out)
          }
          None => ()
        }
      }
      true
    }
    // A block used as a value: its statements are not graph nodes.
    @ast.EBlock(_) => true
    // A literal, a name, a float, a string, a regex: nothing to walk.
    _ => false
  }
}

///|
fn check_exprs(
  xs : Array[@ast.Expr],
  st : @flow.SignState,
  out : Array[@report.Report],
) -> Bool {
  let mut holed = false
  for x in xs {
    if check_expr(x, st, out) {
      holed = true
    }
  }
  holed
}

///|
/// IS THIS EXPRESSION A FLOAT? And the answer is "yes" only where the SOURCE
/// SAYS SO.
///
/// THE MEASUREMENT THAT MAKES THIS A GUARD AND NOT A NICETY. Settled against
/// the toolchain on a five-case probe (`moon test --target wasm`):
///
///     1 / 0     -> RuntimeError: divide by zero      <- a CRASH
///     1 % 0     -> RuntimeError: remainder by zero   <- a CRASH
///     1.0 / 0   -> Infinity                         <- NOT a crash
///     1.0 / 0.0 -> Infinity                         <- NOT a crash
///     1.0 % 0   -> NaN                              <- NOT a crash
///
/// and `moon check` accepts all five, so the compiler catches neither the
/// crash nor the non-crash. A float division by zero is IEEE arithmetic, not a
/// failure, so a family that claims "this division fails at run time" must not
/// fire on one -- and the deck's claim is about the DIVISOR, so the guard
/// belongs on the NUMERATOR, whose type decides the operation's type.
///
/// WHAT THE SOURCE CAN PROVE, and what it cannot: a float LITERAL is a float,
/// and an operator over a float is a float (which is the type lens's own rule
/// -- `binop_result` maps float against int to float). A NAME is NOT decidable
/// here: the type lens publishes the types of the MODULE's names and not of a
/// function's locals, so a float-valued local cannot be told from an
/// integer-valued one without a second type system, and a second type system
/// that disagrees with the first is worse than no answer at all. The family's
/// `excluded` states the residual, and the corpus measurement says the
/// residual is empty in analysed code.
fn float_expr(e : @ast.Expr) -> Bool {
  match e.kind {
    @ast.EFloat(_) => true
    @ast.EUnary(_, a) => float_expr(a)
    @ast.EBin(_, a, b) => float_expr(a) || float_expr(b)
    _ => false
  }
}

///|
/// The message for a division whose divisor is definitely zero.
///
/// THE SUBJECT IS QUOTED WHEN IT IS A NAME, and the predicate reader takes the
/// first quoted run, so a finding about a named divisor carries the name and a
/// finding about a computed one carries no name at all -- which is the honest
/// outcome: there is no name to check.
fn divisor_message(b : @ast.Expr) -> String {
  match b.kind {
    @ast.EName(n) =>
      "the divisor '\{n}' is definitely zero: this division fails at run time"
    _ => "the divisor is definitely zero: this division fails at run time"
  }
}

///|
/// The message for a subscript whose index is definitely negative.
fn index_message(idx : @ast.Expr) -> String {
  match idx.kind {
    @ast.EName(n) =>
      "the index '\{n}' is definitely negative: this subscript is out of bounds at run time"
    _ =>
      "the index is definitely negative: this subscript is out of bounds at run time"
  }
}
