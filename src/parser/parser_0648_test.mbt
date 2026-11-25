//| parser_0648_test.mbt -- THE FRONTEND READS TYPE DEFINITIONS. 0647 recorded
//| that it did not, and named the three things that were missing; this file is
//| the first of the three.
//
//| WHAT 0647 MEASURED: `ast::Module` had a `body` and an `imports` and nothing
//| else, so a declaration had nowhere to live. The frontend SKIPPED `struct` /
//| `enum` / `type` / `suberror` at the token level, and what survived of an
//| `enum` was its constructor NAMES. The RECURSION lives in the payload --
//| `Node(Tree, Tree)` names the type being declared -- and the payload was
//| thrown away with the rest of the body.
//
//| SO THE FRONTEND COULD NOT TELL A RECURSIVE TYPE FROM A PLAIN ONE, and the
//| rows here are the ones that make the difference visible: the DECLARATION is
//| in the tree now, and its payload is in it.
//
//| THE RULES THE READER FOLLOWS, and each of them is a rule about what a NAME
//| in a non-type position would do to the type graph:
//
//|   * a CONSTRUCTOR is a value, and a field NAME is a binding. Neither is a
//|     reference to a type, and reading either as one would invent an edge --
//|     `enum A { B }` beside `enum B { .. }` would become a cycle A -> B that
//|     the program does not have.
//|   * a QUALIFIED path (`@core.Size`) is a type of ANOTHER package. Its head
//|     is a package name; reading it would invent an edge to a local type that
//|     happens to share the spelling.
//|   * a BUILTIN (`Int`) is not a node of this module's type graph.
//
//| The last one is enforced by the GRAPH, not by the reader: the reader reports
//| what it saw, and the graph keeps only the names this module declares.

///|
/// `TypeKind` derives `Eq` but not `Debug`, and `assert_eq` needs `Debug` to
/// print the failure -- so the comparison is written out.
fn kind_is_0648(a : @ast.TypeKind, b : @ast.TypeKind) -> Bool {
  a == b
}

///|
/// AN ENUM'S PAYLOAD IS READ, AND THE RECURSION IS IN IT.
///
///     enum Tree {
///       Leaf(Int)
///       Node(Tree, Tree)
///     }
///
/// The declaration is in the tree, and its refs are the TYPES it mentions. The
/// payload names `Tree` twice and the reader records it ONCE -- a graph edge
/// is a relation, not a count, and a repeated mention is the same edge.
///
/// THE READER REPORTS WHAT IT SAW, so `Int` is in the list: the reader does not
/// decide what is a node of the type graph, and `Int` is not a type of THIS
/// module. The graph is what drops it (`src/types/typegraph_0648_test.mbt`
/// pins that filter), and this row pins the reader.
test "0648: an enum's payload is read, and the recursion is in it" {
  let r = @parser.parse("enum Tree {\n  Leaf(Int)\n  Node(Tree, Tree)\n}\n")
  assert_eq(r.first_error, 0)
  assert_eq(r.tree.types.length(), 1)
  let d = r.tree.types[0]
  assert_eq(d.name, "Tree")
  assert_true(kind_is_0648(d.kind, @ast.TEnum))
  assert_eq(d.refs.length(), 2)
  assert_eq(d.refs[0], "Int")
  assert_eq(d.refs[1], "Tree")
}

///|
/// THE CONTROL: A PLAIN ENUM MENTIONS NO TYPE AT ALL.
///
///     enum Color {
///       Red
///       Green
///     }
///
/// `Int` is not here either -- it is a builtin, and the reader reports what it
/// SAW while the graph keeps only the names this module declares. The row
/// below therefore asserts the reader's own output, and the graph's filter is
/// pinned in `src/types/typegraph_0648_test.mbt`.
test "0648 control: a plain enum mentions no type, and a builtin is seen but is not a node" {
  let r = @parser.parse("enum Color {\n  Red\n  Green\n}\n")
  assert_eq(r.tree.types.length(), 1)
  let d = r.tree.types[0]
  assert_eq(d.name, "Color")
  assert_true(kind_is_0648(d.kind, @ast.TEnum))
  assert_eq(d.refs.length(), 0)
  let with_builtin = @parser.parse("enum Wrap {\n  W(Int)\n}\n")
  assert_eq(with_builtin.tree.types[0].refs.length(), 1)
  assert_eq(with_builtin.tree.types[0].refs[0], "Int")
}

///|
/// A STRUCT'S FIELD TYPES ARE READ -- AND THAT IS A DIFFERENT READER.
///
///     struct Node {
///       left : Node
///       right : Node
///     }
///
/// A struct's body is `name : Type`, and an enum's is `Ctor(Type)`. They were
/// read by the SAME scanner in the first version of this increment, and the
/// enum's scanner finds NOTHING in a struct -- it looks for a constructor and
/// a struct has none. The measurement that caught it: a recursive struct
/// produced no notice at all, while a recursive enum did.
test "0648: a struct's field types are read, and the recursion is in them" {
  let r = @parser.parse("struct Node {\n  left : Node\n  right : Node\n}\n")
  assert_eq(r.first_error, 0)
  assert_eq(r.tree.types.length(), 1)
  let d = r.tree.types[0]
  assert_eq(d.name, "Node")
  assert_true(kind_is_0648(d.kind, @ast.TStruct))
  assert_eq(d.refs.length(), 1)
  assert_eq(d.refs[0], "Node")
  // AND THE COMMA-SEPARATED FORM READS THE SAME WAY.
  let comma = @parser.parse("struct Node { left : Node, right : Node }\n")
  assert_eq(comma.tree.types.length(), 1)
  assert_eq(comma.tree.types[0].refs.length(), 1)
  assert_eq(comma.tree.types[0].refs[0], "Node")
}

///|
/// A FIELD NAME IS NOT A TYPE, AND A CONSTRUCTOR NAME IS NOT EITHER.
///
/// This is the row that keeps the graph honest. `enum A { B }` beside
/// `enum B { X }` is legal MoonBit, and reading the constructor `B` as a
/// reference to the type `B` would make it a cycle -- a cycle the program does
/// not have, and a finding about it would be a false positive.
///
/// The same holds for a field whose NAME spells a type: `struct S { Tree : Int }`
/// mentions no type at all.
test "0648: a constructor name and a field name are not type references" {
  let ctor = @parser.parse("enum A {\n  B\n}\nenum B {\n  X\n}\n")
  assert_eq(ctor.tree.types.length(), 2)
  assert_eq(ctor.tree.types[0].refs.length(), 0)
  assert_eq(ctor.tree.types[1].refs.length(), 0)
  let field = @parser.parse("struct S {\n  Tree : Int\n}\n")
  assert_eq(field.tree.types.length(), 1)
  assert_eq(field.tree.types[0].refs.length(), 1)
  assert_eq(field.tree.types[0].refs[0], "Int")
}

///|
/// AN ALIAS'S RIGHT-HAND SIDE IS ITS REFERENCE.
///
///     type Alias = Tree
///
/// The alias has NO BODY, and the exclusion notice for it says so with the
/// UNBRACED wording -- "type declaration is outside the analyzed subset",
/// without the "its body was not analyzed" that a braced declaration gets.
/// The reference is still read: it is the right-hand side, and it is on the
/// same line.
test "0648: an alias's right-hand side is its reference, and an alias with no `=` has none" {
  let r = @parser.parse("type Alias = Tree\n")
  assert_eq(r.first_error, 0)
  assert_eq(r.tree.types.length(), 1)
  assert_eq(r.tree.types[0].name, "Alias")
  assert_true(kind_is_0648(r.tree.types[0].kind, @ast.TAlias))
  assert_eq(r.tree.types[0].refs.length(), 1)
  assert_eq(r.tree.types[0].refs[0], "Tree")
  // AND AN OPAQUE DECLARATION (`type Shape`, no `=`) MENTIONS NOTHING.
  let opaque_decl = @parser.parse("type Shape\n")
  assert_eq(opaque_decl.tree.types.length(), 1)
  assert_eq(opaque_decl.tree.types[0].refs.length(), 0)
}

///|
/// A SUBERROR IS AN ENUM WITH A DIFFERENT NAME, AND ITS PAYLOAD IS READ.
///
///     suberror E {
///       Wrap(E)
///     }
///
/// The payload of a suberror is a type list, exactly as an enum's is, and the
/// recursion lives there too.
test "0648: a suberror's payload is read" {
  let r = @parser.parse("suberror E {\n  Wrap(E)\n}\n")
  assert_eq(r.first_error, 0)
  assert_eq(r.tree.types.length(), 1)
  assert_eq(r.tree.types[0].name, "E")
  assert_true(kind_is_0648(r.tree.types[0].kind, @ast.TSuberror))
  assert_eq(r.tree.types[0].refs.length(), 1)
  assert_eq(r.tree.types[0].refs[0], "E")
}

///|
/// A TUPLE STRUCT'S FIELDS ARE TYPES TOO.
///
///     struct Pair(Tree, Tree)
///
/// This is the shape with no braces, so it is read on the line rather than in
/// a body -- and its fields can be recursive in exactly the way a braced
/// struct's are.
test "0648: a tuple struct's fields are read" {
  let r = @parser.parse("struct Pair(Tree, Tree)\n")
  assert_eq(r.first_error, 0)
  assert_eq(r.tree.types.length(), 1)
  assert_eq(r.tree.types[0].name, "Pair")
  assert_true(kind_is_0648(r.tree.types[0].kind, @ast.TStruct))
  assert_eq(r.tree.types[0].refs.length(), 1)
  assert_eq(r.tree.types[0].refs[0], "Tree")
}

///|
/// A CONTAINER'S ARGUMENT IS A TYPE OF THIS MODULE, AND A QUALIFIED PATH IS
/// NOT.
///
///     enum E {
///       V(Array[Tree])
///       W(@core.Size)
///     }
///
/// `Array[Tree]` mentions `Tree`, and that is a real edge: a container of a
/// recursive type is a recursive type. The reader also reports the container's
/// OWN HEAD, `Array`, because the reader reports what it SAW -- and `Array` is
/// not a type of this module, so the graph drops it. `@core.Size` mentions a
/// type of ANOTHER package, and its head is a package name -- recording the
/// head would invent an edge to a local type that happens to share the
/// spelling.
///
/// THE MEMBER NAME AFTER THE PAYLOAD IS NOT A TYPE, and the row below is where
/// that is pinned: `W` is a CONSTRUCTOR. The first version of the scanner
/// counted every kind of bracket together, so a `]` inside a `(...)` never
/// cancelled its `[` and the scan ran to the end of the file -- which made the
/// reader report `W` as a type reference and would have invented an edge
/// `E -> W` for a constructor. MEASURED 0648.
test "0648: a container's argument is read, and a qualified path is not" {
  let r = @parser.parse("enum E {\n  V(Array[Tree])\n  W(@core.Size)\n}\n")
  assert_eq(r.tree.types.length(), 1)
  let refs = r.tree.types[0].refs
  assert_eq(refs.length(), 2)
  assert_eq(refs[0], "Tree")
  assert_eq(refs[1], "Array")
}

///|
/// THE DECLARATIONS ARE IN SOURCE ORDER, and the parser still reports what it
/// did not analyse.
///
/// The ORDER is a property of the program, and it is what makes a reader's
/// "the third declaration is the recursive one" true. And the SCOPE-LIMIT
/// NOTICE is still there, unchanged: reading a declaration is not analysing
/// one, and the analyzer still models neither a constructor's shape nor a
/// struct's fields.
test "0648: the declarations are in source order, and the exclusion still stands" {
  let r = @parser.parse(
    "enum A {\n  X\n}\n\nstruct B {\n  n : Int\n}\n\ntype C = Int\n",
  )
  assert_eq(r.tree.types.length(), 3)
  assert_eq(r.tree.types[0].name, "A")
  assert_eq(r.tree.types[1].name, "B")
  assert_eq(r.tree.types[2].name, "C")
  // AND THE EXCLUSIONS ARE STILL RECORDED, ONE PER DECLARATION.
  assert_eq(r.skips.length(), 3)
  assert_eq(r.reports.length(), 3)
  for rep in r.reports {
    assert_true(rep.is_notice())
    assert_true(rep.message.contains("outside the analyzed subset"))
  }
}
