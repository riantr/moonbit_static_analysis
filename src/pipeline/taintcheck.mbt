// 0587: THE TAINT FINDING -- the deck's TaintFlows, as a report.
//
// THE DECK. `Static Analysis for Security` (Tian Tan, Nanjing University),
// p.73-85. The deck's OUTPUT is a set of triples -- "(i, j, k) = tainted data
// from call site i may flow to the k-th argument of call site j" -- and p.84
// prints the deck's own answer to its own example:
//
//     TaintFlows: { <3, 7, 0> }
//
// A triple is a fact about a PROGRAM, and this file is where it becomes a fact
// about a LINE: the sink call is what the reader has to look at, and the
// finding says where the data came from.
//
// THE ANALYSIS IS THE TREE'S, and this file adds no rules: `src/flow/taint.mbt`
// is the deck's source rule, the deck's four pointer-analysis rules and the
// deck's sink rule, and it is called here. What this file owns is the REPORT:
// which function bodies are analysed, what the finding says, and where it
// sits.
//
// THE GUARDS ARE THE PIPELINE'S, and they are the same three the other
// function-level families use:
//
//   * a file the frontend did not read WHOLE is not analysed at all
//     (`first_error == 0`), because a fact read from a broken tree is a fact
//     about the analyzer's damage;
//   * a function whose extent contains a region the frontend DECLINED to read
//     is not analysed (`has_hole`), because that region might have read the
//     binding the flow runs through;
//   * a function whose control-flow graph LOST a statement is not analysed
//     (`skipped > 0`), because the statement it lost may have been a
//     SANITIZER -- a `pw = scrub(pw)` the analysis never read would leave the
//     tainted datum in `pw`, and the flow reported here would be a false
//     positive.
//
// THE THIRD GUARD IS THE ONE THAT MAKES THE CLAIM HONEST, and it is worth
// saying why it is not optional: the taint analysis is a MAY analysis, so
// everything it reports is "this MAY happen". A skipped statement cannot
// CREATE a flow, but it can destroy a SANITIZER, and a sanitizer that the
// analysis did not see is a flow the analysis believes in and the program does
// not have. The guard lives in `src/flow/taint.mbt`, beside the graph it is
// about, and this file inherits it.
//
// ONE FINDING PER SINK CALL SITE, and not one per triple. The merge in the
// pipeline collapses a family to one finding per LINE, so a sink with two
// sensitive arguments would lose one of them -- and two sources reaching one
// sink would lose one of THEM. So the flows are GROUPED by the sink's call site
// here, and the message names every argument and every source the group covers.
// The merge then has nothing to collapse, and the report keeps the whole fact.
//
// A CALL SITE IS THE LINE AND THE NAME, and not the line alone: two sink calls
// on one line are two call sites, and one message may not put one sink's
// argument together with another sink's.

///|
/// The taint findings of one module, over the functions the pipeline may
/// analyse.
///
/// `unread` is the frontend's list of regions it chose not to analyse, and a
/// function whose extent contains one of them is not analysed by this family.
pub fn taint_findings(
  body : Array[@ast.Stmt],
  unread : Array[@core.Span],
  spec : @flow.TaintSpec,
) -> Array[@report.Report] {
  let out : Array[@report.Report] = []
  let cfgs : Array[@flow.Cfg] = []
  for s in body {
    match s.kind {
      @ast.SFunc(_, _, _, fbody, extent) =>
        if !has_hole(extent, unread) {
          cfgs.push(@flow.cfg_of(fbody))
        }
      @ast.SLocalFunc(_, _, _, fbody, extent) =>
        if !has_hole(extent, unread) {
          cfgs.push(@flow.cfg_of(fbody))
        }
      _ => ()
    }
  }
  if cfgs.length() == 0 {
    return out
  }
  let r = @flow.taint_analyze(cfgs, spec)
  // THE GROUPING, and the reason for it is the merge's key: the pipeline
  // collapses a family to one finding per LINE, so two flows at one sink call
  // would become one finding with one of the two messages. The group keeps
  // both, and the message names both.
  //
  // THE GROUP IS A CALL SITE AND NOT A LINE, and a call site here is the line
  // AND THE NAME. The line alone is not enough: two sink calls on one line are
  // two call sites, and grouping them by the line alone would put one sink's
  // argument together with another sink's -- a message that says "the sensitive
  // arguments 0 and 1 of 'log' or 'audit'" when log's argument 0 and audit's
  // argument 1 are the two that actually carry the data.
  let groups : Map[String, Array[@flow.TaintFlow]] = Map([])
  let order : Array[String] = []
  for f in r.flows {
    let k = f.sink_line.to_string() + "|" + f.sink_name
    match groups.get(k) {
      Some(g) => g.push(f)
      None => {
        groups.set(k, [f])
        order.push(k)
      }
    }
  }
  for k in order {
    let g = match groups.get(k) {
      Some(x) => x
      None => continue
    }
    out.push(@report.Report::{
      family: @core.FTaintFlow,
      lenses: [@core.LStructural],
      message: taint_message(g),
      span: g[0].sink_span,
      vst: [],
    })
  }
  out
}

///|
/// THE MESSAGE, and it names the sink, the arguments and the sources.
///
/// THE SINK COMES FIRST because the finding is AT the sink: the reader opens
/// the line the finding is on, and the first name they meet is the call that
/// receives the data. The predicate reads the quoted runs BEFORE "may receive"
/// for the sink and the ones after it for the sources, so the two lists cannot
/// be confused for each other -- see `src/report/predicate.mbt`.
///
/// THE SINK IS ONE, because a group is one CALL SITE: every flow in the group
/// is a flow into the same call.
///
/// THE ARGUMENTS ARE SORTED AS NUMBERS, not as text: a sink with ten
/// sensitive arguments has "10" as well as "2", and "10" sorts before "2" as
/// a string.
///
/// THE SOURCES ARE SORTED BY THE STDLIB, and the stdlib's order for strings is
/// SHORTLEX -- the LENGTH first and the code units only as the tie-break. The
/// tree has already measured that (`src/flow/pta.mbt`: `["aa","b"].sort()`
/// gives `["b","aa"]`), and this tree does not hand-write a second comparator
/// beside it: one more place a disagreement with the stdlib could hide.
fn taint_message(g : Array[@flow.TaintFlow]) -> String {
  let sink = g[0].sink_name
  let arg_idx : Array[Int32] = []
  let srcs : Array[String] = []
  for f in g {
    if arg_idx.contains(f.arg) == false {
      arg_idx.push(f.arg)
    }
    if srcs.contains(f.src_name) == false {
      srcs.push(f.src_name)
    }
  }
  arg_idx.sort()
  srcs.sort()
  let args : Array[String] = []
  for i in arg_idx {
    args.push(i.to_string())
  }
  "the sensitive argument\{plural(args)} \{arg_list(args)} of '\{sink}' may receive tainted data from \{name_list(srcs)}"
}

///|
/// The plural "s", for the argument list.
fn plural(xs : Array[String]) -> String {
  if xs.length() > 1 {
    "s"
  } else {
    ""
  }
}

///|
/// The argument list, as the reader would write it: "0", "0 and 1".
fn arg_list(xs : Array[String]) -> String {
  let mut out = ""
  let mut i = 0
  while i < xs.length() {
    if i > 0 {
      if i == xs.length() - 1 {
        out = out + " and "
      } else {
        out = out + ", "
      }
    }
    out = out + xs[i]
    i = i + 1
  }
  out
}

///|
/// The source list, as the reader would write it: "'a'", "'a' or 'b'".
fn name_list(xs : Array[String]) -> String {
  let mut out = ""
  let mut i = 0
  while i < xs.length() {
    if i > 0 {
      if i == xs.length() - 1 {
        out = out + " or "
      } else {
        out = out + ", "
      }
    }
    out = out + "'" + xs[i] + "'"
    i = i + 1
  }
  out
}
