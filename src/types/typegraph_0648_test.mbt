//| typegraph_0648_test.mbt -- THE TYPE GRAPH, AND THE CYCLES IN IT.
//
//| 0647 named three things a recursive type needed and this tree did not have:
//| a node for a type declaration, a parser that READS the declaration instead
//| of skipping it, and a type-lens pass that builds the type graph and asks
//| whether it has a cycle. The first two are in `src/ast/ast.mbt` and
//| `src/parser/parser.mbt`; this file is the third.
//
//| THE GRAPH IS OVER NAMES, and the name is not the point: the point is that
// an EDGE is a MENTION. `Node(Tree, Tree)` mentions `Tree`, and that mention
// is the recursion. So the reader reports what it saw and the graph keeps
// only the names THIS MODULE DECLARES -- a builtin (`Int`) and a type of
// another package (`@core.Size`) are not nodes of this module's types.
//
//| THE CYCLES ARE FOUND BY A WALK, and the rows below are the shapes the
// 0647 chapter listed as untested on the other side of the tree: a self-loop,
// a mutual cycle, and a ring of three.

///|
/// A DECLARATION, built by hand so that the graph's own behaviour is measured
/// and not the parser's.
fn decl_0648(
  name : String,
  kind : @ast.TypeKind,
  refs : Array[String],
) -> @ast.TypeDecl {
  @ast.TypeDecl::{ name, kind, refs, span: @core.zero_span(), }
}

///|
/// `TypeKind` derives `Eq` but not `Debug`, and `assert_eq` needs `Debug` to
/// print the failure -- so the comparison is written out. A test that cannot
/// print what it compared fails with a bare "false", which is the same as no
/// test.
fn kind_is(a : @ast.TypeKind, b : @ast.TypeKind) -> Bool {
  a == b
}

///|
/// THE EDGES ARE THE MENTIONS, AND A BUILTIN IS NOT A NODE.
///
/// The graph keeps only the names this module declares, so `Int` -- which the
/// reader did see -- is not an edge. Without that filter every builtin in
/// every payload would be a node, and the graph would be a graph of builtins.
test "0648: the graph keeps only this module's types" {
  let g = @types.build_type_graph([
    decl_0648("Tree", @ast.TEnum, ["Tree", "Int"]),
    decl_0648("Color", @ast.TEnum, ["Int"]),
  ])
  assert_eq(g.decls.length(), 2)
  // ONE EDGE: Tree -> Tree. `Int` is a builtin and is not a node.
  assert_eq(g.edges.length(), 1)
  assert_eq(g.edges[0].0, "Tree")
  assert_eq(g.edges[0].1, "Tree")
}

///|
/// A SELF-LOOP IS ONE CYCLE, AND ITS PATH IS THE WAY ROUND.
///
/// The path is `A -> A`: the node, and the node again. It is the shape the
/// toolchain prints for an alias cycle ("Found cycle A -> A in `type alias`
/// declaration", MEASURED 0648 against `moon check`).
test "0648: a self-loop is one cycle, and its path is A -> A" {
  let g = @types.build_type_graph([decl_0648("Tree", @ast.TEnum, ["Tree"])])
  let cycles = @types.type_cycles(g)
  assert_eq(cycles.length(), 1)
  assert_eq(cycles[0].path.length(), 2)
  assert_eq(cycles[0].path[0], "Tree")
  assert_eq(cycles[0].path[1], "Tree")
}

///|
/// A MUTUAL CYCLE IS ONE CYCLE, NOT TWO.
///
/// `A -> B -> A` is ONE cycle: the walk that closes it has already visited
/// both nodes, so the second walk over them finds nothing. Two cycles that
/// SHARE a node are two cycles, and the row below says so.
test "0648: a mutual cycle is one cycle, and two cycles sharing a node are two" {
  let mutual = @types.build_type_graph([
    decl_0648("A", @ast.TEnum, ["B"]),
    decl_0648("B", @ast.TEnum, ["A"]),
  ])
  let cycles = @types.type_cycles(mutual)
  assert_eq(cycles.length(), 1)
  assert_eq(cycles[0].path.length(), 3)
  assert_eq(cycles[0].path[0], "A")
  assert_eq(cycles[0].path[1], "B")
  assert_eq(cycles[0].path[2], "A")
  // AND TWO CYCLES THAT SHARE A NODE ARE TWO.
  let two = @types.build_type_graph([
    decl_0648("A", @ast.TEnum, ["B", "C"]),
    decl_0648("B", @ast.TEnum, ["A"]),
    decl_0648("C", @ast.TEnum, ["A"]),
  ])
  assert_eq(@types.type_cycles(two).length(), 2)
}

///|
/// A RING OF THREE IS ONE CYCLE, AND THE CONTROL IS THE SAME RING CUT.
///
/// "One stratum of three" would also be true of an engine that puts
/// everything in one group, so the control is the same three declarations
/// with the ring cut -- and then there are NO cycles at all.
test "0648: a ring of three is one cycle, and the cut ring is none" {
  let ring = @types.build_type_graph([
    decl_0648("A", @ast.TEnum, ["B"]),
    decl_0648("B", @ast.TEnum, ["C"]),
    decl_0648("C", @ast.TEnum, ["A"]),
  ])
  let cycles = @types.type_cycles(ring)
  assert_eq(cycles.length(), 1)
  assert_eq(cycles[0].path.length(), 4)
  assert_eq(cycles[0].path[0], "A")
  assert_eq(cycles[0].path[3], "A")
  // AND THE CONTROL: THE SAME THREE, WITH THE RING CUT.
  let cut = @types.build_type_graph([
    decl_0648("A", @ast.TEnum, ["B"]),
    decl_0648("B", @ast.TEnum, []),
    decl_0648("C", @ast.TEnum, ["A"]),
  ])
  assert_eq(@types.type_cycles(cut).length(), 0)
}

///|
/// THE DECLARATIONS ON A CYCLE, AND ONE NOTICE EACH.
///
/// A mutual recursion `A -> B -> A` puts BOTH declarations on the cycle, and
/// both of them are types the analyzer does not model. So the count a reader
/// sees is the number of RECURSIVE TYPES -- which is the fact worth having --
/// and not the number of cycles.
test "0648: one notice per recursive declaration, and none for a plain type" {
  let g = @types.build_type_graph([
    decl_0648("A", @ast.TEnum, ["B"]),
    decl_0648("B", @ast.TEnum, ["A"]),
    decl_0648("Color", @ast.TEnum, ["Int"]),
  ])
  let recursive = @types.recursive_types(g)
  assert_eq(recursive.length(), 2)
  assert_eq(recursive[0].name, "A")
  assert_eq(recursive[1].name, "B")
  // AND THE KIND COMES WITH THEM: a cycle among ALIASES is a different shape
  // from a cycle among data declarations, and the graph keeps the difference.
  assert_true(kind_is(recursive[0].kind, @ast.TEnum))
  assert_true(kind_is(recursive[1].kind, @ast.TEnum))
  // AND THE NOTICES.
  let notices = @types.recursive_type_notices(g)
  assert_eq(notices.length(), 2)
  for n in notices {
    assert_true(n.is_notice())
    assert_eq(n.severity_label(), "notice")
    assert_true(n.message.contains("outside the analyzed subset"))
    // AND THE LENS IS THE TYPE LENS: this is a type-layer fact.
    assert_eq(n.lenses.length(), 1)
    assert_true(n.lenses[0] == @core.LType)
  }
}

///|
/// AN ALIAS CYCLE GETS ITS OWN WORDING, AND IT IS A NOTICE TOO.
///
/// A cycle among type ALIASES is a cycle the TOOLCHAIN rejects outright:
/// `moon check` says "Found cycle A -> B -> A in `type alias` declaration" and
/// exits non-zero (MEASURED 0648). So the compiler is the authority there,
/// and this analyzer says what it cannot do -- it models no recursive type at
/// all -- rather than claiming a defect of its own.
test "0648: an alias cycle gets its own wording, and it is still a notice" {
  let g = @types.build_type_graph([
    decl_0648("A", @ast.TAlias, ["B"]),
    decl_0648("B", @ast.TAlias, ["A"]),
  ])
  let notices = @types.recursive_type_notices(g)
  assert_eq(notices.length(), 2)
  for n in notices {
    assert_true(n.is_notice())
    assert_true(n.message.contains("recursive type alias"))
    assert_true(n.message.contains("outside the analyzed subset"))
  }
}
