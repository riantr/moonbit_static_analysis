// 0586: THE TAINT LAYER -- the security deck's fourth chapter, on the pointer
// analysis this tree already has.
//
// THE DECK. `Static Analysis for Security` (Tian Tan, Nanjing University),
// p.64-85. Chapter 4 is "Taint Analysis", and p.70 is the slide that decides
// how this file is built:
//
//     Taint and Pointer Analysis, Together
//
// The deck treats tainted data as OBJECTS (p.71-72: "Tainted data t_i, t_j in
// T subset O"), treats a source as an ALLOCATION SITE, and propagates taint
// with the pointer analysis's OWN rules (p.75). So the taint analysis here is
// NOT a second pointer analysis: it is the pointer analysis this tree already
// has (0547), with one extra object per source call site.
//
// THE SEED IS THE WHOLE DIFFERENCE. The deck's source rule (p.74) reads
//
//     Call | l: r = x.k(a1,...,an) | l -> m in CG ; m in Sources => t_l in pt(r)
//
// and the deck's own worked example (p.79-85) prints the tainted datum INSIDE
// the points-to set of the variable the source call was bound to:
//
//     Variable | Object
//     pw       | o11, t3
//
// So a tainted datum is an OBJECT named after its call site, and it starts in
// the points-to set of the call's result. Everything after that is the deck's
// four rules -- New, Assign, Store, Load -- which `pta.mbt` already implements,
// in ONE place, and which this file CALLS rather than copies.
//
// THE OUTPUT IS THE DECK'S TRIPLE. p.73 defines it and p.84 prints it:
//
//     Output = a set of tuples of source and sink calls,
//              (i, j, k) = tainted data from call site i may flow to the
//                          k-th argument of call site j
//
// and the deck's example ends with
//
//     TaintFlows: { <3, 7, 0> }
//
// THREE THINGS ARE ADDED AND FOUR ARE NOT.
//
//   ADDED      the SOURCE rule (p.74) -- one tainted object per source call
//              site, seeded into the result's points-to set.
//   ADDED      the SINK rule (p.76) -- <j, l, i> in TaintFlows when the sink's
//              i-th argument holds a tainted object.
//   ADDED      the `..` chain link, which CALLS a method and evaluates to the
//              RECEIVER, so its value is not the callee's value and it cannot
//              be a source.
//
//   NOT ADDED  the deck's CALL rule (p.75) ACROSS method bodies: the pointer
//              analysis this tree has is one map PER FUNCTION -- `pta.mbt`
//              states that as its own restriction -- so a source in one
//              function and a sink in another are not connected. That is the
//              SAME boundary the pointer analysis already has, not a new one.
//   NOT ADDED  the deck's rule that a call's RETURN VALUE is an object: the
//              pointer analysis does not model what a call returns, so the
//              tainted datum reaches a VARIABLE only when the source call IS
//              the right-hand side of the assignment.
//   NOT ADDED  the deck's IMPLICIT flows (p.47-58) -- a branch on tainted data,
//              a termination channel, a timing channel, an exception channel.
//              The deck itself says (p.61-62) "Explicit flows generally carry
//              more information than covert channels, so we focus on explicit
//              flows", so the boundary is the deck's own.
//   NOT ADDED  the deck's SECURITY LEVELS (p.25-28) and the NONINTERFERENCE
//              property (p.29-36). A level is a LATTICE element and a policy
//              is an ORDER on it; this file's label is a single bit, and the
//              deck's noninterference is a RELATIONAL property over two runs
//              of the program, which no may-analysis answers.
//
// THE WHOLE ANALYSIS IS INTRAPROCEDURAL, and that is the tree's existing
// shape rather than a new restriction: one points-to map per function, the
// allocation-site heap, context-insensitive, flow-insensitive.

///|
/// The deck's SOURCES and SINKS (p.73).
///
/// THEY ARE PARAMETERS, NOT A LIST BUILT INTO THIS FILE, and the reason is the
/// deck's own example: its source is `getPassword()` and its sink is
/// `log(String)` -- two functions of the program under analysis, and neither
/// one is a name any toolchain defines. A taint analysis that carried its own
/// list of source names would answer a different question than the deck's,
/// and the question it answers ("does untrusted data reach this sink?") would
/// be a guess about the analysed project rather than a fact about it.
pub(all) struct TaintSpec {
  /// The deck's Sources: the functions whose RESULT is tainted data.
  ///
  /// A call to one of these is what the deck's source rule (p.74) reads.
  sources : Map[String, Bool]
  /// The deck's Sinks: a function name and the indices of its SENSITIVE
  /// arguments.
  ///
  /// The deck writes a sink as a PAIR (p.73: "Sinks = a set of sink methods
  /// with sensitive arguments"; p.77: `<log(String), 0>`), and the pair is the
  /// method and the ARGUMENT INDEX -- which is why this is a map from a name
  /// to a LIST of indices and not to one index: a sink may have more than one
  /// sensitive argument.
  sinks : Map[String, Array[Int32]]
}

///|
/// One of the deck's triples (p.73), and the deck's own example of one
/// (p.84): `<3, 7, 0>`.
///
/// THE THREE NUMBERS ARE (source call site, sink call site, argument index),
/// and a call site is identified by its LINE -- the same identity this tree's
/// object names use (`o<line>` for an allocation site, `t<line>` for a tainted
/// datum).
pub(all) struct TaintFlow {
  /// The line of the SOURCE call site -- the deck's `i`.
  src_line : Int32
  /// The SOURCE FUNCTION's name -- the callee of the source call.
  ///
  /// 0587. It is here because a REPORT has to say it: the deck's triple is
  /// three call SITES, and a reader wants to know WHICH FUNCTION produced the
  /// data, not only which line it was produced on.
  src_name : String
  /// The line of the SINK call site -- the deck's `j`.
  sink_line : Int32
  /// The SINK FUNCTION's name -- the callee of the sink call.
  ///
  /// 0587. The finding sits AT the sink, so the sink is the name the report
  /// leads with.
  sink_name : String
  /// The index of the SENSITIVE argument -- the deck's `k`.
  arg : Int32
  /// The sink call's own position, so a report can point at the call and not
  /// only at its line.
  sink_span : @core.Span
}

///|
/// What the analysis produced.
pub(all) struct TaintResult {
  /// One points-to map per function, with the tainted objects IN it -- the
  /// deck's own tables (p.79-83) are printed from these.
  pts : Array[Pta]
  /// The deck's TaintFlows (p.84).
  flows : Array[TaintFlow]
}

///|
/// The empty specification: no sources, no sinks, and therefore no flows.
pub fn taint_spec_empty() -> TaintSpec {
  { sources: Map([]), sinks: Map([]), }
}

///|
/// Add a SOURCE: a function whose result is tainted data.
///
/// THE SPECIFICATION IS CHANGED IN PLACE, and it is changed in place because
/// the two sets it holds are MAPS, and a map is a reference: the caller's
/// specification is the one this function writes to. That is why the two
/// builders below return Unit rather than a new specification -- returning a
/// new one would promise a value semantics the type does not have.
///
/// THE NAME IS THE WHOLE MATCH. A MoonBit call is `ECall` with the callee's
/// name as written, so `get_password()` is matched by `get_password` and a
/// qualified `Net::read()` is matched by `Net::read`. A METHOD call
/// (`x.write(v)`) is matched by the METHOD's name, `write` -- the receiver's
/// type is not part of the match, because the AST does not carry it and the
/// type lens's answer to it is a different question.
pub fn taint_spec_source(spec : TaintSpec, name : String) -> Unit {
  let sources = spec.sources
  sources.set(name, true)
}

///|
/// Add a SINK: a function and the index of one of its SENSITIVE arguments.
///
/// The index is the argument's POSITION, counted from zero, and it is the
/// deck's own (p.76: "t_j in pt(a_i)", p.77: `<log(String), 0>`). A second
/// index for the same function is added to the list rather than replacing the
/// first: a sink with two sensitive arguments has two of them.
pub fn taint_spec_sink(spec : TaintSpec, name : String, arg : Int32) -> Unit {
  let sinks = spec.sinks
  let cur = match sinks.get(name) {
    Some(a) => a
    None => []
  }
  if cur.contains(arg) == false {
    cur.push(arg)
    cur.sort()
    sinks.set(name, cur)
  }
}

///|
/// Add a SINK written as TEXT: a function name and an argument index, separated
/// by a colon -- "log:0".
///
/// THE TEXT FORM IS THE CLI'S AND THE WIRE'S, and it is parsed HERE so that
/// both spell it the same way: the CLI's `--taint-sink log:0` and the JSON
/// bridge's `"taint_sinks": ["log:0"]` are ONE format and not two.
///
/// IT RETURNS FALSE FOR A TEXT IT DOES NOT UNDERSTAND, and it says so rather
/// than guessing: a sink whose index was silently dropped would scan the
/// program and report nothing, which looks exactly like a clean program.
pub fn taint_spec_sink_text(spec : TaintSpec, text : String) -> Bool {
  let mut name = ""
  let mut idx = ""
  let mut k = 0
  for part in text.split(":") {
    let p = part.trim().to_owned()
    if k == 0 {
      name = p
    } else if k == 1 {
      idx = p
    } else {
      return false
    }
    k = k + 1
  }
  if name == "" || idx == "" {
    return false
  }
  let mut n = 0
  for ch in idx {
    if !ch.is_ascii_digit() {
      return false
    }
    n = n * 10 + (ch.to_int() - '0'.to_int())
  }
  taint_spec_sink(spec, name, n)
  true
}

///|
/// THE ANALYSIS: the pointer analysis's own rules, over a map seeded with one
/// tainted object per source call site, and the deck's sink rule on top.
///
/// THE SEED IS APPLIED BEFORE THE SWEEP, because the sweep only ever JOINS
/// (`pta.mbt`: "every conclusion is joined into the pointer's set and nothing
/// is ever removed"), so a tainted datum seeded into a variable's set is
/// still there after the fixpoint -- and the fixpoint is what carries it
/// along the deck's Assign, Store and Load rules.
pub fn taint_analyze(cfgs : Array[Cfg], spec : TaintSpec) -> TaintResult {
  let sites = pta_site_names(cfgs)
  let pts : Array[Pta] = []
  let flows : Array[TaintFlow] = []
  let mut fi = 0
  while fi < cfgs.length() {
    let g = cfgs[fi]
    // 0587. A GRAPH THAT LOST A STATEMENT IS NOT ANALYSED, and the reason is a
    // SANITIZER. The taint analysis is a MAY analysis, so a statement it never
    // read cannot CREATE a flow -- but it can DESTROY one: a `pw = scrub(pw)`
    // the graph did not turn into nodes leaves the tainted datum in `pw`, and
    // the flow this file reports would be one the program does not have. So a
    // function whose graph lost a statement is not analysed at all, and its
    // map is EMPTY rather than missing, so the index of every map is still the
    // index of its function.
    if g.skipped > 0 {
      pts.push(pta_empty())
      fi = fi + 1
      continue
    }
    let sources = source_sites(g, spec)
    // THE SOURCE RULE (p.74): `t_l in pt(r)`. The tainted datum is an object
    // named after its call site, and it goes into the points-to set of the
    // name the call's result was bound to.
    let pt = pta_empty()
    for s in sources {
      for name, _ in node_defs(g.kinds[s.node]) {
        let one = Map([])
        one.set(s.obj, true)
        let _ = pta_join(pt, name, one)
      }
    }
    // THE DECK'S FOUR RULES, in the tree's ONE place. `pta_sweep` is the
    // pointer analysis's own sweep -- the same function `pta_run` calls, over
    // the same maps, with the same rules.
    let mut changed = true
    while changed {
      changed = pta_sweep(cfgs, sites, pt, pt, fi)
    }
    pts.push(pt)
    collect_flows(g, pt, spec, sources, flows)
    fi = fi + 1
  }
  { pts, flows, }
}

///|
/// One source call site: the node it is, the line it is named after, and the
/// tainted object it creates.
priv struct SourceSite {
  node : Int32
  line : Int32
  obj : String
  /// The SOURCE FUNCTION's name -- the callee the source rule matched on.
  callee : String
}

///|
/// THE SOURCE CALL SITES OF ONE FUNCTION.
///
/// A source call site is a call that IS the statement's own expression -- the
/// deck's shape (p.74): `l: r = x.k(a1,...,an)`. A call NESTED inside another
/// expression is not one, because the tree's pointer analysis does not model
/// what a call returns, so a nested call's value has nowhere to be seeded.
///
/// THE NAMES ARE THE DECK'S, AND THE COLLISION RULE IS THE POINTER ANALYSIS'S.
/// The deck names the tainted datum after its call site (`t3`), and this tree
/// names an object after the LINE of its site (`o3`), so the tainted datum is
/// `t<line>`; two source calls on ONE line have no page behind them, and they
/// become `t<line>` and `t<line>_2` -- the same fallback `pta_site_names`
/// uses, and for the same reason.
fn source_sites(g : Cfg, spec : TaintSpec) -> Array[SourceSite] {
  let out : Array[SourceSite] = []
  let mut prev_line = -1
  let mut k = 0
  for v in g.source_order() {
    let e = match node_expr(g.kinds[v]) {
      Some(x) => x
      None => continue
    }
    let call = match call_of(e) {
      Some(c) => c
      None => continue
    }
    let (callee, _, yields) = call
    // A `..` chain link calls a method and evaluates to the RECEIVER, so its
    // value is not the callee's value: it cannot be a source.
    if yields == false || spec.sources.contains(callee) == false {
      continue
    }
    let line = g.spans[v].start.line
    if line == prev_line {
      k = k + 1
    } else {
      prev_line = line
      k = 1
    }
    // A `match` AND NOT AN `if` USED AS A VALUE. The `if` expression is outside
    // the analysed subset -- the frontend reads past it and says so -- and a
    // region the frontend does not read is a region the analyzer's own audit
    // does not see either. 0552 fixed exactly this shape in the 3AC layer, and
    // the fix was the same: make the branch a STATEMENT, so the code sits in
    // a region the audit does read.
    let obj = match k {
      1 => "t" + line.to_string()
      _ => "t" + line.to_string() + "_" + k.to_string()
    }
    out.push({ node: v, line, obj, callee, })
  }
  out
}

///|
/// THE SINK RULE (p.76), and the deck's TaintFlows.
///
///     Call | l: r = x.k(a1,...,an) | l -> m in CG ; <m, i> in Sinks ;
///           t_j in pt(a_i) => <j, l, i> in TaintFlows
///
/// so a flow is a triple, and the triple's first number is the SOURCE call
/// site -- the line the tainted datum was created on.
fn collect_flows(
  g : Cfg,
  pt : Pta,
  spec : TaintSpec,
  sources : Array[SourceSite],
  flows : Array[TaintFlow],
) -> Unit {
  // The tainted objects and the SITE each was created at. Every tainted object
  // in the map came from one of this function's source sites, so this map is
  // the whole answer to "which line is this tainted datum from" -- and to
  // "which function produced it", which is the half a REPORT needs.
  //
  // THE LOOKUP IS BY THE OBJECT'S NAME, not by its line: two source calls on
  // one line are `t3` and `t3_2`, and the names are what tell them apart.
  let tainted_sites : Map[String, SourceSite] = Map([])
  for s in sources {
    tainted_sites.set(s.obj, s)
  }
  for v in g.source_order() {
    let e = match node_expr(g.kinds[v]) {
      Some(x) => x
      None => continue
    }
    let call = match call_of(e) {
      Some(c) => c
      None => continue
    }
    let (callee, args, _) = call
    let idxs = match spec.sinks.get(callee) {
      Some(i) => i
      None => continue
    }
    for i in idxs {
      if i < 0 || i >= args.length() {
        // A sensitive argument the call does not have. The sink is named, the
        // argument is not there, and there is nothing to flow.
        continue
      }
      let arg = args[i]
      // THE ARGUMENT'S OWN POINTS-TO SET: the deck's `t_j in pt(a_i)`. This
      // is the case the deck's worked example exercises -- `s` holds the
      // tainted datum, and `log(s)` reads it.
      for obj, _ in pta_of_expr(pt, pt, arg) {
        match tainted_sites.get(obj) {
          Some(s) =>
            add_flow(flows, {
              src_line: s.line,
              src_name: s.callee,
              sink_line: g.spans[v].start.line,
              sink_name: callee,
              arg: i,
              sink_span: g.spans[v],
            })
          None => ()
        }
      }
      // THE ARGUMENT IS ITSELF A SOURCE CALL: `log(get_password())`. The
      // tainted datum is the call's own, and it never reaches a variable --
      // the pointer analysis does not model what a call returns -- so it is
      // read here rather than looked up.
      let inner = match call_of(arg) {
        Some(c) => c
        None => continue
      }
      let (icallee, _, iyields) = inner
      if iyields && spec.sources.contains(icallee) {
        add_flow(flows, {
          src_line: arg.span.start.line,
          src_name: icallee,
          sink_line: g.spans[v].start.line,
          sink_name: callee,
          arg: i,
          sink_span: g.spans[v],
        })
      }
    }
  }
}

///|
/// Add a flow, unless the same triple is already there.
///
/// TWO SOURCE CALLS ON ONE LINE have the same call site by this tree's
/// identity -- the LINE -- and so they would produce the same triple twice.
/// The deck's triple is a SET (p.73: "a set of tuples"), and a set has no
/// duplicates.
fn add_flow(flows : Array[TaintFlow], f : TaintFlow) -> Unit {
  for g in flows {
    if g.src_line == f.src_line && g.sink_line == f.sink_line && g.arg == f.arg {
      return
    }
  }
  flows.push(f)
}

///|
/// The expression a node EVALUATES, if it evaluates one.
///
/// THIS IS NOT A SECOND ANSWER TO "what does this node do" -- it is a
/// projection of the node kind onto the one field the taint rules read, and
/// the node kinds themselves are read directly (the enum is matched, not
/// inspected through a `.kind`).
fn node_expr(kind : NodeKind) -> @ast.Expr? {
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
/// THE CALL AN EXPRESSION MAKES: its callee's name, its arguments, and
/// whether the call's OWN result is the expression's value.
///
/// THE THIRD FIELD IS THE ONE THAT MATTERS FOR A SOURCE. `recv..name(args)`
/// CALLS `name` and evaluates to the RECEIVER -- the tree settled that
/// against the toolchain in `_verify/settle_0465_dotdot_chain.ps1` -- so its
/// value is not the callee's value and it cannot be a source. It can still be
/// a SINK: the arguments are passed either way.
fn call_of(e : @ast.Expr) -> (String, Array[@ast.Expr], Bool)? {
  match e.kind {
    @ast.ECall(f, args, _) => Some((f, args, true))
    @ast.EMethodCall(_, m, args, _) => Some((m, args, true))
    @ast.EDotDot(_, m, args, _) => Some((m, args, false))
    _ => None
  }
}

///|
/// A dump of the analysis: the points-to tables (with the tainted objects in
/// them) and then the flows, so a test can assert the deck's own tables as
/// text.
pub fn taint_text(r : TaintResult) -> String {
  let parts : Array[String] = []
  for pt in r.pts {
    let t = pta_text(pt)
    if t != "" {
      parts.push(t)
    }
  }
  for f in r.flows {
    parts.push(
      "flow <" +
      f.src_line.to_string() +
      ", " +
      f.sink_line.to_string() +
      ", " +
      f.arg.to_string() +
      ">",
    )
  }
  parts.join("; ")
}
