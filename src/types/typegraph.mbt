// typegraph: the TYPE GRAPH of one module -- the types it declares and the
// edges between them -- and the CYCLES in it.
//
// 0648. THE THIRD OF THE THREE THINGS a recursive type needs, and the one
// that was missing for the longest.
//
// The frontend used to read NO type definition at all: `struct`, `enum`,
// `type` and `suberror` were skipped at the token level, and what survived of
// an `enum` was its constructor NAMES. The RECURSION of a type lives in its
// PAYLOAD -- `Node(Tree, Tree)` names the type being declared -- and the
// payload is exactly what the harvest threw away. So the analyzer could not
// tell a recursive type from a plain one, and "the analyzer reported nothing
// about the recursive type" could not be read as "the analyzer checked, and
// the type is not recursive". It could only be read as "the analyzer does
// not read type definitions at all", which is a statement about the ANALYZER.
//
// This file is the type lens's answer: it takes the declarations the
// frontend READ (`ast::TypeDecl`), builds the graph over them, and says
// whether the graph has a cycle.
//
// AN EDGE IS A MENTION, not an inclusion. `A -> B` says that A's declaration
// NAMES the type B. The graph is over NAMES because that is what a
// declaration gives -- `Node(Tree, Tree)` names `Tree` -- and because a name
// that is not declared in this module is not a node of this graph: it is a
// builtin (`Int`), or a type of another package (`@core.Size`), and neither
// can be part of a cycle among THIS module's types.

///|
/// The TYPE GRAPH of one module.
pub(all) struct TypeGraph {
  /// The declarations the frontend read, in source order.
  decls : Array[@ast.TypeDecl]
  /// The edges, as `(from, to)`: `from`'s declaration names the type `to`.
  /// Both ends are types declared in this module.
  edges : Array[(String, String)]
}

///|
/// A CYCLE in the type graph.
///
/// The path is the way round and the LAST name is the FIRST one again:
/// `A -> B -> A`, which is the shape the toolchain prints for an alias cycle
/// ("Found cycle A -> B -> A in `type alias` declaration", MEASURED 0648).
pub(all) struct TypeCycle {
  path : Array[String]
}

///|
/// Build the graph from the declarations the frontend read.
///
/// THE EDGE FILTER, and why it is not "every name the declaration mentions":
/// a name that is not DECLARED in this module is not a node of this graph.
/// Without that filter every builtin in every payload would be a node, and
/// the graph would be a graph of builtins -- which has no cycles, but for a
/// reason that has nothing to do with the program's types.
///
/// A SELF-EDGE IS KEPT. `A -> A` is the recursion, and dropping it would
/// drop the most common shape of all.
pub fn build_type_graph(decls : Array[@ast.TypeDecl]) -> TypeGraph {
  let declared : Array[String] = []
  for d in decls {
    if !declared.contains(d.name) {
      declared.push(d.name)
    }
  }
  let edges : Array[(String, String)] = []
  for d in decls {
    for r in d.refs {
      if declared.contains(r) && !has_edge(edges, d.name, r) {
        edges.push((d.name, r))
      }
    }
  }
  TypeGraph::{ decls, edges, }
}

///|
fn has_edge(
  edges : Array[(String, String)],
  from : String,
  to : String,
) -> Bool {
  for e in edges {
    if e.0 == from && e.1 == to {
      return true
    }
  }
  false
}

///|
/// The CYCLES in the graph.
///
/// ONE CYCLE, ONCE. A three-node ring is ONE cycle and not three: the ring
/// is closed by the back edge that reaches a node already on the path, and
/// the walk that closed it has already visited the other two -- so the next
/// walk over them finds nothing. Two cycles that SHARE a node are two
/// cycles, and both are reported.
///
/// THE PATH IS THE ONE THE WALK TOOK, and it is a path and not the only
/// path: a graph with two ways round the same ring has two cycles, and
/// reporting one of them is not a claim about the other.
pub fn type_cycles(g : TypeGraph) -> Array[TypeCycle] {
  let adj : Map[String, Array[String]] = Map([])
  // 0648. THE EDGE IS TAKEN APART HERE, and not in the loop's own PATTERN:
  // `for (a, b) in g.edges` is a tuple-paren pattern, and the frontend does
  // not MODEL it -- `expect_name("loop variable")` wants a NAME where the `(` is
  // -- so a file written that way is reported PARTIAL with "expected loop
  // variable" (the parser's own comment says so, and MEASURED on this tree:
  // the self-scan read this file up to this line and no further, and the
  // release gate's self-scan stage failed on `files != parsed`).
  //
  // An analyzer that cannot read its own source is an analyzer that cannot be
  // checked against its own source, so the shape here is the one the frontend
  // reads: a plain binder, and the tuple's two halves taken by FIELD.
  for e in g.edges {
    let a = e.0
    let b = e.1
    match adj.get(a) {
      Some(v) => v.push(b)
      None => adj.set(a, [b])
    }
  }
  let done : Map[String, Bool] = Map([])
  let path : Array[String] = []
  let found : Array[TypeCycle] = []
  for d in g.decls {
    if !done.contains(d.name) {
      walk_cycles(d.name, adj, done, path, found)
    }
  }
  found
}

///|
/// The depth-first walk, with the CURRENT PATH carried down.
///
/// The path is COPIED at each level rather than pushed and popped, because
/// the array is shared with the caller and a truncation would be a mutation
/// the caller could see. The cost is a copy per node, and a module's type
/// graph is small: the copy is O(depth) and the walk is O(nodes).
fn walk_cycles(
  node : String,
  adj : Map[String, Array[String]],
  done : Map[String, Bool],
  path : Array[String],
  found : Array[TypeCycle],
) -> Unit {
  let here = path.copy()
  here.push(node)
  let nexts = match adj.get(node) {
    Some(v) => v
    None => []
  }
  for next in nexts {
    if here.contains(next) {
      found.push(cycle_on(here, next))
    } else if !done.contains(next) {
      walk_cycles(next, adj, done, here, found)
    }
  }
  done.set(node, true)
}

///|
/// The cycle that closes at `at`: the tail of the path from `at` onwards, and
/// `at` once more to close it.
fn cycle_on(path : Array[String], at : String) -> TypeCycle {
  let out : Array[String] = []
  let mut started = false
  for p in path {
    if p == at {
      started = true
    }
    if started {
      out.push(p)
    }
  }
  out.push(at)
  TypeCycle::{ path: out, }
}

///|
/// The DECLARATIONS that lie on a cycle, in source order.
///
/// ONE NOTICE PER DECLARATION, and not one per cycle: a mutual recursion
/// `A -> B -> A` puts BOTH declarations on the cycle, and both of them are
/// types the analyzer does not model. The count a reader sees is therefore
/// the number of RECURSIVE TYPES, which is the fact worth having.
pub fn recursive_types(g : TypeGraph) -> Array[@ast.TypeDecl] {
  let names : Array[String] = []
  for c in type_cycles(g) {
    for n in c.path {
      if !names.contains(n) {
        names.push(n)
      }
    }
  }
  let out : Array[@ast.TypeDecl] = []
  for d in g.decls {
    if names.contains(d.name) {
      out.push(d)
    }
  }
  out
}

///|
/// The SCOPE-LIMIT notices for the recursive types of one module.
///
/// WHY A NOTICE AND NOT A FINDING. A recursive type is LEGAL MoonBit:
/// `enum Tree { Leaf(Int), Node(Tree, Tree) }` is what MoonBit is for, and
/// `moon check` accepts it (MEASURED 0648, against the toolchain). So a
/// finding would be a false positive about the reader's code.
///
/// WHAT THE ANALYZER ACTUALLY CANNOT DO is model the type: it has no
/// representation for a recursive shape, so it checks nothing about the code
/// that uses one. That is a DECLARED SCOPE LIMIT, and it is what a notice
/// says. The message carries the word `subset` because that is the marker
/// the notice machinery is held to (`_verify/check_notice_labels.ps1`).
///
/// THE ALIAS CASE IS THE SAME NOTICE, and that is deliberate. A cycle among
/// type ALIASES is a cycle the toolchain rejects outright -- `moon check`
/// says "Found cycle A -> B -> A in `type alias` declaration" and exits
/// non-zero (MEASURED 0648) -- so the compiler is the authority there and
/// this analyzer's notice is never the reader's first signal. Reporting it
/// as a defect would mean a new family for a shape the compiler has already
/// rejected, and the family roster stays at eighteen.
///
/// THE MERGE. This notice lands on the SAME LINE as the declaration's own
/// scope-limit notice ("enum declaration is outside the analyzed subset; its
/// body was not analyzed"), and the pipeline merges findings by
/// (family, line). The type lens's report is the more specific one -- the
/// type lens outranks the structural lens -- so ITS message is the one the
/// reader sees, and the message therefore has to carry BOTH facts.
pub fn recursive_type_notices(g : TypeGraph) -> Array[@report.Report] {
  let out : Array[@report.Report] = []
  for d in recursive_types(g) {
    let msg = match d.kind {
      TAlias =>
        "recursive type alias declaration is outside the analyzed subset; the type lens does not model recursive type aliases"
      _ =>
        "recursive type declaration is outside the analyzed subset; its body was not analyzed and the type lens does not model recursive types"
    }
    out.push(@report.Report::{
      family: @core.FParse,
      lenses: [@core.LType],
      message: msg,
      span: d.span,
      vst: [],
    })
  }
  out
}
