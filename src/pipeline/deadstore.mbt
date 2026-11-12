// Dead stores (MSA-015), over the liveness answer from `@flow`.
//
// WHAT THIS IS NOT. It is not `FUnusedLocal`. That family is syntactic and
// whole-function: the binding is never read anywhere. This one is about ONE
// write: the binding may be read on other paths, and this store's value is still
// dead because every way out of here writes the name again before any read. The
// two claims are different, and a reader who is handed the wrong one is told the
// binding is useless when only this write was.
//
// 0565. AND A DECLARATION IS A WRITE TOO. The rule above is about ONE write, and
// `let mut x = 0` is one: the value 0 is written into `x`. It used to be
// INVISIBLE here, because the graph keeps a declaration and a re-assignment
// apart (`Assign` vs `Store`, src/flow/cfg.mbt:324 and :339) -- and the reason
// the graph keeps them apart was an assumption this increment MEASURED to be
// false. "A `let` whose value is never read" and "a binding that is never read"
// are NOT the same claim: a binding can be read LATER and its INITIALIZER's
// value still be dead, and then `FUnusedLocal` does not fire (its claim is
// "never read anywhere") and this family did not fire either (a declaration was
// not a `Store`), so the value was reported by NOBODY.
//
// THE SECOND HALF OF THE RULE IS WHAT KEEPS THE TWO FAMILIES APART. A
// declaration whose name is never read anywhere is `FUnusedLocal`'s finding, and
// reporting it here too would put two families on one line for one fact. So a
// declaration is reported here only when its name IS read somewhere: the
// binding is used, and the VALUE it was initialised with is not.
//
// MEASURED, the shape the course's own first example has (the lecture's p.40-43:
// `if (input) x = 1; else x = 0` -- in the only shape MoonBit allows for it,
// `let mut x = 0` before the two branches):
//
//     let mut x = 0
//     if input { x = 1 } else { x = 0 }
//     x
//
// reported NOTHING before this increment. It reports ONE finding now, and it is
// on the DECLARATION: the two branch stores are not dead, because on each path
// the value the branch wrote IS the one the tail reads.
//
// THE TWO GUARDS THAT MATTER, AND WHY THEY ARE BOTH `skipped`-SHAPED.
//
// 1. THE CFG counts the statements it did not convert (`Cfg.skipped`): a nested
//    function body, whose reads of the enclosing locals this graph does not
//    model. Liveness decides a store is dead by looking at the paths that leave
//    it, so a read that is not in the graph is a path it did not see -- and
//    reporting on that basis would be a false positive in the family's own
//    terms. So a function that contains a skipped statement is NOT analysed, and
//    the family says so in `excluded` instead of guessing.
//
// 2. A REGION THE FRONTEND DID NOT ANALYSE, inside the function. This is the
//    same rule as (1) applied to the shapes that were overlooked because they
//    live in an EXPRESSION rather than in a statement: an `if` used as a value,
//    an anonymous function literal, a `try` expression. Each of them is a body
//    whose reads of the enclosing locals this graph does not model, and each of
//    them leaves a hole in the function that contains it.
//
//    MEASURED, the hole cost this family eight findings across the corpora,
//    and every one of them was a store whose value IS read:
//
//      moonbit_image 0.3.7      fim.mbt:353      the read is in `if v < 0.0`
//      moonbitlang/core          trig.mbt:166     the read is in `if odd {..}`
//      moonbitlang/core          double_exact_test.mbt:97   the read is in
//                                                             `if p < -1022`
//      wzzc-dev/moui 0.1.12      core/text_layout.mbt:375/390/393
//                                                         the read is in
//                                                         `if last_soft_break >..`
//      wzzc-dev/moui 0.1.12      views/presentation.mbt:728
//                                                         the read is in a lambda
//      moonbitlang/async 0.22.4  internal/event_loop/network.mbt:35
//                                                         the read is in a `try`
//
//    0532 ATTRIBUTED THE ASYNC ONE TO `guard`, and that was wrong: `guard` IS
//    modelled -- `Parser::parse_guard` produces an `SIf` with an empty then
//    branch -- and a probe with a `guard` and no `try` reports NOTHING. The
//    probe that separates them is three functions differing in one word:
//
//      try + `if`      -> the finding appears
//      try + `guard`   -> the finding appears
//      try + no read   -> the finding appears (and it is a TRUE positive)
//
//    so the `try` region is the cause, and `guard` is not in this at all.
//
//    THE RULE IS NOT INVENTED HERE. `walk.truncated_fn` already applies exactly
//    this geometry to a family's whole-function conclusion -- "a skip is not a
//    read failure... it still leaves a hole inside whatever function encloses
//    it" -- and the hole was simply invisible to a family whose graph stopped
//    at the statement level.
//
// Functions declared at module level are analysed one at a time, which is why
// this is intraprocedural: an interprocedural answer is increment 4's job
// (book §8.1), not a thing to fake here.

///|
/// One report per store whose value no path reads.
///
/// `unread` is the frontend's list of regions it chose not to analyse (the
/// pipeline computes it from the parse notices). A function whose extent
/// contains one of them is not analysed by this family, for the reason the
/// header gives.
pub fn dead_stores(
  body : Array[@ast.Stmt],
  unread : Array[@core.Span],
) -> Array[@report.Report] {
  let out : Array[@report.Report] = []
  for s in body {
    match s.kind {
      @ast.SFunc(_, params, _, fbody, extent) =>
        if !has_hole(extent, unread) {
          one_body(params, fbody, out)
        }
      @ast.SLocalFunc(_, params, _, fbody, extent) =>
        if !has_hole(extent, unread) {
          one_body(params, fbody, out)
        }
      _ => ()
    }
  }
  out
}

///|
/// Does this function's extent contain a region the frontend did not analyse?
///
/// THE GEOMETRY IS THE WALK'S, not a second one. `walk.span_in_extent` asks
/// "is this region inside that function", and the walk already asks it of every
/// function for `truncated_fn`; a second spelling of the same geometry is how
/// two parts of the analyzer come to disagree about which regions hide a
/// finding.
fn has_hole(extent : @core.Span, unread : Array[@core.Span]) -> Bool {
  for u in unread {
    if @walk.span_in_extent(u, extent) {
      return true
    }
  }
  false
}

///|
/// The names a function DECLARES: its parameters and every `let` / destructuring
/// `let` anywhere in its body.
///
/// WHY THE EMITTER NEEDS THIS. An assignment to a name that is declared NOWHERE
/// is `FUndefinedName`'s claim, and a dead store on it would be a second report
/// for one line under a family that says something weaker. Measured: the first
/// version of this emitter turned `pipeline_test`'s structural fixture from 3
/// findings into 5, and the two extra were exactly that -- `z = x * 2` where `z`
/// has no `let`. A dead store is a claim about a declared BINDING; this set is
/// what makes the claim say what it means.
fn declared(stmts : Array[@ast.Stmt], out : Map[String, Bool]) -> Unit {
  for s in stmts {
    match s.kind {
      @ast.SLet(n, _, _) => out.set(n, true)
      @ast.SLetDestruct(ns, _) =>
        for n in ns {
          out.set(n, true)
        }
      @ast.SBlock(b) | @ast.SForUpdate(b) => declared(b, out)
      @ast.SWhile(_, b) | @ast.SFor(_, _, _, b) => declared(b, out)
      @ast.SIf(_, t, elifs, e) => {
        declared(t, out)
        for ei in elifs {
          declared(ei.body, out)
        }
        match e {
          Some(b) => declared(b, out)
          None => ()
        }
      }
      @ast.SNoBreak(inner, b) => {
        let one : Array[@ast.Stmt] = [inner]
        declared(one, out)
        declared(b, out)
      }
      // A nested function's bindings are its own scope, not this one's.
      _ => ()
    }
  }
}

///|
/// The names this function READS, over the graph's own node kinds.
///
/// WHY IT IS THE GRAPH'S ANSWER AND NOT A SECOND WALK. The declaration rule
/// below has to AGREE with `FUnusedLocal` about what a read is -- the second
/// half of that rule exists so the two families cannot report one line -- and
/// `node_uses` is the definition of a read the liveness pass already uses. A
/// second walk here would be a second definition of the same thing, and the two
/// would drift apart.
///
/// WHY IT IS THE WHOLE FUNCTION AND NOT "AFTER THE DECLARATION". A name cannot
/// be read before the `let` that binds it -- that is a use of no visible binding
/// and `FUndefinedName` owns it -- so "read somewhere in this function" and
/// "read somewhere after this declaration" are the same set of names for a name
/// this function declares.
fn read_names(g : @flow.Cfg) -> Map[String, Bool] {
  let out : Map[String, Bool] = Map([])
  for k in g.kinds {
    for name in @flow.node_uses(k).keys() {
      out.set(name, true)
    }
  }
  out
}

///|
fn one_body(
  params : Array[@ast.Param],
  fbody : Array[@ast.Stmt],
  out : Array[@report.Report],
) -> Unit {
  let g = @flow.cfg_of(fbody)
  // A statement the graph did not convert is a path it cannot see. Decline
  // rather than report: "dead" is the claim, and a missing edge can falsify it.
  if g.skipped > 0 {
    return
  }
  let mine : Map[String, Bool] = Map([])
  for p in params {
    mine.set(p.name, true)
  }
  declared(fbody, mine)
  let ins = @flow.live_in(g)
  let outs = @flow.live_out(g, ins)
  let reads = read_names(g)
  let mut v = 0
  while v < g.kinds.length() {
    match g.kinds[v] {
      @flow.Store(x, _) =>
        if outs[v].contains(x) == false && mine.contains(x) {
          out.push(@report.Report::{
            family: @core.FDeadStore,
            lenses: [@core.LStructural],
            message: "the value stored in '\{x}' is read on no path before the name is written again",
            span: g.spans[v],
            vst: [],
          })
        }
      // 0565. THE DECLARATION. The same claim, one write earlier: the value the
      // initialiser put into the name is read on no path before the name is
      // written again. The second half -- the name is read SOMEWHERE -- is what
      // keeps this off the lines `FUnusedLocal` owns.
      @flow.Assign(x, _) =>
        if outs[v].contains(x) == false && mine.contains(x) && reads.contains(x) {
          out.push(@report.Report::{
            family: @core.FDeadStore,
            lenses: [@core.LStructural],
            message: "the value bound to '\{x}' is read on no path before the name is written again",
            span: g.spans[v],
            vst: [],
          })
        }
      _ => ()
    }
    v = v + 1
  }
}
