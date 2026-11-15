// 0594: THE DECK'S TAINT RULES, RUN, AND COMPARED WITH `taint_analyze`.
//
// THE DECK'S THIRD THING TO UNDERSTAND (p.93) is "How to implement taint analysis via
// Datalog", and its chapter is TWO PAGES (p.90-91). The model is:
//
//   EDB predicates
//   - Source(m: M)      source methods
//   - Sink(m: M, i: N)  sink methods
//   - Taint(l: S, t: T) associates each call site to the tainted data from the call
//     site
//   IDB predicate
//   - TaintFlow(sr: S, sn: S, i: N) detected taint flows; TaintFlow(sr, sn, i) denotes
//     that tainted data from source call sr may flow to the i-th argument of sink
//     call sn
//
// AND THE TWO RULES (p.91):
//
//     VarPointsTo(r, t) <-
//     CallGraph(l, m),
//     Source(m),
//     CallReturn(l, r),
//     Taint(l, t).
//     TaintFlow(j, l, i) <-
//     CallGraph(l, m),
//     Sink(m, i),
//     Argument(l, i, ai),
//     VarPointsTo(ai, t),
//     Taint(j, t).
//
// AND THE TABLE BESIDE THEM (p.91) IS THE CONTRACT: a CALL `l: r = x.k(a1,...,an)` is
// a source when `l->m in CG` and `m in SS` and `t_l in ptr(r)`, and it is a sink when
// `l->m in CG` and `m, i in Sinks` and `t_j in ptr(a_i)` and `j, l, i in TaintFlows`.
//
// SO THIS INCREMENT IS THE SAME SHAPE AS 0593, and for the same reason: the deck's rules
// are RUN and their answer is COMPARED with the answer this tree's own taint analysis
// gives on the same program.
//
// THE COMPARISON HAS A BOUNDARY AND IT IS MEASURED, not assumed. The deck's rules are
// about CALL SITES -- `CallGraph`, `CallReturn`, `Argument` -- and this tree's taint
// analysis is about a SOURCE FUNCTION and a SINK FUNCTION with an argument INDEX
// (`--taint-source <fn>`, `--taint-sink <fn>:<idx>`). The deck's `Source(m)` is a
// METHOD and the tree's source is a FUNCTION, and the deck's `Taint(l, t)` says WHICH
// CALL SITE carries the tainted datum while the tree's source rule seeds the datum into
// the variable the call's result was bound to. Those are two different specifications
// of the same question, and this increment measures where they agree and where they do
// not, and NAMES the difference rather than papering over it.

///|
/// The facts of a program for the taint reading: the deck's EDB relations.
pub(all) struct DlTaintFacts {
  /// `Source(m)` -- a source method.
  source : Array[DFact]
  /// `Sink(m, i)` -- a sink method and the index of its sensitive argument.
  sink : Array[DFact]
  /// `Taint(l, t)` -- the call site `l` carries the tainted datum `t`.
  taint : Array[DFact]
  /// `CallGraph(l, m)` -- the call site `l` calls the method `m`.
  callgraph : Array[DFact]
  /// `CallReturn(l, r)` -- the call site `l` binds its result to `r`.
  callreturn : Array[DFact]
  /// `Argument(l, i, ai)` -- the i-th argument of the call site `l` is `ai`.
  argument : Array[DFact]
}

///|
/// The empty set of taint facts.
pub fn dl_taint_facts_empty() -> DlTaintFacts {
  {
    source: [],
    sink: [],
    taint: [],
    callgraph: [],
    callreturn: [],
    argument: [],
  }
}

///|
/// The DECK'S TWO TAINT RULES (p.91), as text, in the deck's own order and words.
///
/// IT IS TEXT AND NOT A BUILT PROGRAM, for the reason 0593 gave: the deck's claim is
/// about a READABLE SPECIFICATION.
pub fn dl_taint_rules_text() -> String {
  "VarPointsTo(r, t) <- CallGraph(l, m), Source(m), CallReturn(l, r), Taint(l, t).\n" +
  "TaintFlow(j, l, i) <- CallGraph(l, m), Sink(m, i), Argument(l, i, ai), VarPointsTo(ai, t), Taint(j, t)."
}

///|
/// The Datalog program for the taint reading: the deck's two rules, the program's
/// facts, AND the pointer rules 0593 established -- because the deck's own text says
/// "On top of pointer analysis" (p.90) and the taint rule READS `VarPointsTo`.
///
/// AND THE POINTER RULES ARE THE SAME TEXT 0593 uses, and not a second copy: a second
/// copy of the deck's rules is a second definition of them, and two definitions of one
/// thing is one more than can stay in agreement.
pub fn dl_taint_program(facts : DlTaintFacts, pointers : DlFacts) -> DProgram {
  let pointer = datalog_parse(dl_pointer_rules_text())
  let taint = datalog_parse(dl_taint_rules_text())
  let prog = dprog()
  // THE POINTER FACTS GO IN TOO, and that is the deck's own sentence: the taint
  // chapter is "On top of pointer analysis" (p.90). The taint rule READS
  // `VarPointsTo(ai, t)`, so without the pointer relations there is nothing for it
  // to read and every flow is empty -- which is what the first version of this
  // increment did, and the measurement is what caught it.
  //
  // AND THE POINTER FACTS COME FROM 0593's EXTRACTOR and not from a second one: the
  // same relations, read the same way, or the two readings would be comparing
  // different programs.
  for f in pointers.new {
    prog.facts.push(f)
  }
  for f in pointers.assign {
    prog.facts.push(f)
  }
  for f in pointers.store {
    prog.facts.push(f)
  }
  for f in pointers.load {
    prog.facts.push(f)
  }
  for f in facts.source {
    prog.facts.push(f)
  }
  for f in facts.sink {
    prog.facts.push(f)
  }
  for f in facts.taint {
    prog.facts.push(f)
  }
  for f in facts.callgraph {
    prog.facts.push(f)
  }
  for f in facts.callreturn {
    prog.facts.push(f)
  }
  for f in facts.argument {
    prog.facts.push(f)
  }
  for r in pointer.program.rules {
    prog.rules.push(r)
  }
  for r in taint.program.rules {
    prog.rules.push(r)
  }
  prog
}

///|
/// The taint reading's ANSWER.
pub(all) struct DlTaintAnswer {
  ok : Bool
  /// `TaintFlow(j, l, i)` -- the tuples.
  flow : Array[Array[String]]
  /// `VarPointsTo` -- the tuples, because the taint rule derives into it.
  vpt : Array[Array[String]]
  /// The number of rounds the fixpoint took.
  rounds : Int32
}

///|
/// The taint reading's answer: the flow relation, the pointer relation the taint rule
/// derives into, and the number of rounds the fixpoint took.
pub fn dl_taint_answer(
  facts : DlTaintFacts,
  pointers : DlFacts,
) -> DlTaintAnswer {
  let prog = dl_taint_program(facts, pointers)
  let s = datalog_solve(prog)
  let out = { ok: s.ok, flow: [], vpt: [], rounds: s.rounds, }
  if s.ok == false {
    return out
  }
  for t in datalog_tuples(s, "TaintFlow") {
    out.flow.push(t)
  }
  for t in datalog_tuples(s, "VarPointsTo") {
    out.vpt.push(t)
  }
  out
}

///|
/// The facts of ONE function, in the deck's taint relations.
///
/// THE CALL SITE IS THE LINE, and that is the tree's own identity for a call site --
/// the tainted datum is named `t<line>` (`taint.mbt`) and the object is named
/// `o<line>` (`pta_site_names`), so a call site is a line everywhere in this tree. The
/// deck's `l` is a call site too, so `l` is the line, and the two answers can be
/// compared.
///
/// AND THE SOURCE AND SINK ARE THE TREE'S OWN SPECIFICATION, read from the same
/// `TaintSpec` `taint_analyze` reads -- so the two readings are asked the SAME
/// question and the difference between their answers is a difference between the two
/// SPECIFICATIONS and not between two different questions.
pub fn dl_taint_facts_of(
  cfgs : Array[Cfg],
  fi : Int32,
  spec : TaintSpec,
) -> DlTaintFacts {
  let facts = dl_taint_facts_empty()
  let g = cfgs[fi]
  // The SOURCE relations: the deck's `Source(m)` is a METHOD, and this tree's source
  // is a FUNCTION. One fact per source name.
  let srcnames : Array[String] = []
  for k in spec.sources.keys() {
    srcnames.push(k)
  }
  for name in srcnames {
    facts.source.push(dfact("Source", [name]))
  }
  // The SINK relations: `Sink(m, i)` -- one fact per (sink, sensitive argument).
  let sinknames : Array[String] = []
  for k in spec.sinks.keys() {
    sinknames.push(k)
  }
  for name in sinknames {
    let idxs = spec.sinks.get(name).unwrap_or([])
    for i in idxs {
      facts.sink.push(dfact("Sink", [name, i.to_string()]))
    }
  }
  // The CALL SITES: the calls the graph holds, each with its callee, its arguments
  // and -- when it binds its result -- the name it binds it to.
  for v in g.source_order() {
    let e = match dl_node_expr(g.kinds[v]) {
      Some(x) => x
      None => continue
    }
    let call = match dl_call_of(e) {
      Some(c) => c
      None => continue
    }
    let (callee, args, yields) = call
    if yields == false {
      // A `..` chain link evaluates to the RECEIVER, so it is not a call whose
      // result is a value.
      continue
    }
    let site = g.spans[v].start.line.to_string()
    facts.callgraph.push(dfact("CallGraph", [site, callee]))
    // `CallReturn(l, r)`: the deck's `r` is the name the result is bound to.
    //
    // THE DESTRUCTURING IS IN THE BODY AND NOT IN THE LOOP HEAD, and that is the
    // tree's own convention (`pta.mbt`: "for pair in inits { let (fld, e) = pair").
    // The reason is MEASURED: a tuple pattern in the loop HEAD is a construct the
    // analyzer's own frontend reads past, so the file came out PARTIAL -- "read up
    // to line 242, 2 after it not shown" -- and an unreadable file is a file whose
    // findings nobody can trust.
    for pair in dl_node_defs(g.kinds[v]) {
      let (name, _) = pair
      facts.callreturn.push(dfact("CallReturn", [site, name]))
    }
    // `Argument(l, i, ai)`: the deck's `a_i` is the ARGUMENT ITSELF, and the tree's
    // pointer analysis models a name, so only a NAME is an argument the rules can
    // read.
    let mut i = 0
    for arg in args {
      match arg.kind {
        @ast.EName(an) =>
          facts.argument.push(dfact("Argument", [site, i.to_string(), an]))
        _ => ()
      }
      i = i + 1
    }
    // `Taint(l, t)`: the call site carries the tainted datum. The datum is named
    // after the call site's LINE -- the tree's own `t<line>` -- and the deck's rule
    // pairs the call site with the datum it carries.
    if spec.sources.contains(callee) {
      facts.taint.push(dfact("Taint", [site, "t" + site]))
    }
  }
  facts
}

///|
/// The expression a node holds, if it holds one.
fn dl_node_expr(kind : NodeKind) -> @ast.Expr? {
  match kind {
    Assign(_, e) => Some(e)
    Store(_, e) => Some(e)
    PlaceStore(_, e) => Some(e)
    AssignMulti(_, e) => Some(e)
    Eval(e) => Some(e)
    _ => None
  }
}

///|
/// The names a node DEFINES.
fn dl_node_defs(kind : NodeKind) -> Array[(String, @ast.Expr)] {
  match kind {
    Assign(x, e) => [(x, e)]
    Store(x, e) => [(x, e)]
    _ => []
  }
}

///|
/// The call an expression makes, if it is one.
///
/// IT IS `taint.mbt`'s OWN QUESTION and it is asked here rather than imported,
/// because that function is private to its file -- and the two would be two answers
/// to "is this expression a call". A call that yields its RECEIVER (a `..` chain
/// link) is reported with `yields = false`, so a caller can refuse it.
fn dl_call_of(e : @ast.Expr) -> (String, Array[@ast.Expr], Bool)? {
  match e.kind {
    @ast.ECall(f, args, _) => Some((f, args, true))
    @ast.EMethodCall(_, m, args, _) => Some((m, args, true))
    @ast.EDotDot(_, m, args, _) => Some((m, args, false))
    _ => None
  }
}

///|
/// The COMPARISON, and it compares the two readings' FLOWS.
///
/// THE DECK'S TRIPLE IS `(sr, sn, i)` -- source call site, sink call site, argument
/// index -- and this tree's `TaintFlow` is `(src_line, sink_line, arg)`. Those are the
/// same three numbers with the same meanings, so the two sets are compared as sets of
/// triples.
pub fn dl_taint_agrees(cfgs : Array[Cfg], fi : Int32, spec : TaintSpec) -> Bool {
  let a = dl_taint_answer(
    dl_taint_facts_of(cfgs, fi, spec),
    dl_facts_of(cfgs, fi),
  )
  let r = taint_analyze(cfgs, spec)
  let mine : Array[Array[String]] = []
  for f in r.flows {
    mine.push([
      f.src_line.to_string(),
      f.sink_line.to_string(),
      f.arg.to_string(),
    ])
  }
  dl_same_triples(a.flow, mine)
}

///|
/// Whether two sets of triples are EQUAL, order included in neither.
fn dl_same_triples(a : Array[Array[String]], b : Array[Array[String]]) -> Bool {
  if a.length() != b.length() {
    return false
  }
  for x in a {
    let mut found = false
    for y in b {
      if dl_same_triple(x, y) {
        found = true
        break
      }
    }
    if found == false {
      return false
    }
  }
  true
}

///|
/// Whether two triples are equal.
fn dl_same_triple(a : Array[String], b : Array[String]) -> Bool {
  if a.length() != b.length() {
    return false
  }
  let mut i = 0
  while i < a.length() {
    if a[i] != b[i] {
      return false
    }
    i = i + 1
  }
  true
}

///|
/// The two readings' FLOWS side by side, as text, so a difference is visible rather
/// than inferred.
pub fn dl_taint_compare_text(
  cfgs : Array[Cfg],
  fi : Int32,
  spec : TaintSpec,
) -> String {
  let a = dl_taint_answer(
    dl_taint_facts_of(cfgs, fi, spec),
    dl_facts_of(cfgs, fi),
  )
  let r = taint_analyze(cfgs, spec)
  let mut out = "TaintFlow (the deck's rules):\n"
  for t in a.flow {
    out = out + "  (" + t[0] + ", " + t[1] + ", " + t[2] + ")\n"
  }
  out = out + "TaintFlows (taint_analyze):\n"
  for f in r.flows {
    out = out +
      "  (" +
      f.src_line.to_string() +
      ", " +
      f.sink_line.to_string() +
      ", " +
      f.arg.to_string() +
      ")\n"
  }
  out
}
