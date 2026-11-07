// Dead stores (MSA-015), over the liveness answer from `@flow`.
//
// WHAT THIS IS NOT. It is not `FUnusedLocal`. That family is syntactic and
// whole-function: the binding is never read anywhere. This one is about ONE
// write: the binding may be read on other paths, and this store's value is still
// dead because every way out of here writes the name again before any read. The
// two claims are different, and a reader who is handed the wrong one is told the
// binding is useless when only this write was.
//
// THE ONE GUARD THAT MATTERS, AND WHY IT IS `skipped`. The CFG counts the
// statements it did not convert (`Cfg.skipped`): a nested function body, whose
// reads of the enclosing locals this graph does not model. Liveness decides a
// store is dead by looking at the paths that leave it, so a read that is not in
// the graph is a path it did not see -- and reporting on that basis would be a
// false positive in the family's own terms. So a function that contains a
// skipped statement is NOT analysed, and the family says so in `excluded`
// instead of guessing.
//
// Functions declared at module level are analysed one at a time, which is why
// this is intraprocedural: an interprocedural answer is increment 4's job
// (book §8.1), not a thing to fake here.

///|
/// One report per store whose value no path reads.
pub fn dead_stores(body : Array[@ast.Stmt]) -> Array[@report.Report] {
  let out : Array[@report.Report] = []
  for s in body {
    match s.kind {
      @ast.SFunc(_, params, _, fbody, _) => one_body(params, fbody, out)
      @ast.SLocalFunc(_, params, _, fbody, _) => one_body(params, fbody, out)
      _ => ()
    }
  }
  out
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
      _ => ()
    }
    v = v + 1
  }
}
