//| parser_0647_test.mbt -- THE TYPE LAYER'S RECURSION, WHICH IS NOT A FEATURE
//| THAT WAS NEVER TESTED. IT IS A CAPABILITY THAT DOES NOT EXIST.
//|
//| 0648 READ THIS FILE AGAIN, AND THE ROWS BELOW ARE PARTLY INVERTED. The text
//| is kept as the record of what 0647 measured, and the rows that assert it
//| say so -- the tree now carries the declarations, and the recursion is
//| visible there.
//|
//| THE AUDIT QUESTION WAS: "is a recursive type detected?" The answer measured
//| here is NO, and -- this is the part that matters -- the answer is NO for a
//| reason that no test can turn into a yes by writing a different fixture.
//|
//| THE FRONTEND DID NOT READ TYPE DEFINITIONS. `ast::Module` had a `body` and
//| an `imports` and nothing else (`src/ast/ast.mbt:821-829`): there was no
//| node for an `enum`, no node for a `struct`, no node for a `type` alias. The
//| parser SKIPPED those declarations at the token level (`skip_decl_braced`,
//| `src/parser/parser.mbt:1097`), and what survived of an `enum` was its
//| CONSTRUCTOR NAMES -- harvested by name, with the payloads discarded
//| (`harvest_ctors`, `src/parser/parser.mbt:1261`).
//|
//| AND THE RECURSION LIVES IN THE PAYLOAD. `Node(Tree, Tree)` is recursive
//| because the payload names the type being declared; the NAME `Node` says
//| nothing about it. So the one piece of the declaration that would say "this
//| type is recursive" is exactly the piece the harvest throws away.
//|
//| WHICH IS WHY THESE ROWS ARE PAIRS, and why the SECOND half of each pair is
//| a NON-recursive program that must produce the SAME OBSERVATION. A test that
//| asserted "no recursive-type finding was produced" would have been satisfied
//| by an analyzer that cannot see type definitions AT ALL -- which was the
//| truth here, and is exactly why such an assertion proved nothing on its own.
//| The discriminating observation was that the recursive program and the plain
//| one were INDISTINGUISHABLE to the frontend: same notice, same report count,
//| and -- the sharpest one -- NOTHING IN THE TREE.
//|
//| 0648 GAVE THE TREE THE NODE. `ast::Module` has a `types` field now, the
//| parser READS the declarations into it, and the payload is in it. The pairs
//| below therefore ask a DIFFERENT question -- do the two DECLARATIONS differ
//| -- and the answer is YES. The type lens's side of the same measurement is
//| in `src/pipeline/pipeline_0648_test.mbt`.
//|
//| THE MESSAGE IS NOT SPELLED OUT IN A LITERAL HERE. A test that compares a
//| literal with a literal proves only that a literal agrees with a literal.
//| What is asserted instead is that the notice's CLAIM is true: the parser
//| says the declaration's body was not analysed, and the claim is checked
//| against the TREE -- the declaration left no node in the body. That is
//| 0500's invariant read the other way round.

///|
/// A RECURSIVE TYPE LEAVES NO NODE IN THE TREE'S BODY.
///
///     enum Tree {
///       Leaf
///       Node(Tree, Tree)      <- recursive: the payload names the type
///     }
///
/// The file is READ (`first_error` is 0), the exclusion is RECORDED (one
/// report, one skip), and the enum leaves NOTHING in the BODY: the body's
/// statements are the module's statements, and a declaration is not one.
///
/// 0648 CHANGED THE SECOND HALF OF THIS ROW. The frontend now READS type
/// declarations -- that was the capability 0647 recorded as missing -- so the
/// tree carries the declaration in `tree.types`, and the recursion is visible
/// there. What did NOT change is the BODY: a declaration is still not a
/// statement, and the exclusion is still recorded exactly once.
///
/// So the row below asserts both halves: the body is empty, AND the
/// declaration is now in `tree.types`. The first half is what 0647 measured;
/// the second is what 0648 added.
test "0648: a recursive type leaves no node in the BODY, and 0648 gave it one in `types`" {
  let r = @parser.parse("enum Tree {\n  Leaf\n  Node(Tree, Tree)\n}\n")
  // THE FILE WAS READ. The exclusion is a subset exclusion, not a read
  // failure -- and the distinction is the one 0500 settled.
  assert_eq(r.first_error, 0)
  assert_eq(r.reports.length(), 1)
  assert_eq(r.skips.length(), 1)
  // AND THE NOTICE SAYS SO, AND THE SKIP LIST AND THE REPORT AGREE.
  let fps = fparse_reports(r.reports)
  assert_eq(fps.length(), 1)
  for rep in fps {
    assert_true(rep.is_notice())
    assert_eq(rep.severity_label(), "notice")
    assert_true(r.skips.contains(rep.message))
  }
  // AND THE BODY IS STILL EMPTY: a declaration is not a statement.
  assert_eq(r.tree.body.length(), 0)
  // AND THE DECLARATION IS NOW IN THE TREE. This is the half 0647 measured as
  // MISSING, and it is the first half of what 0648 built: the node the
  // declaration used to leave behind.
  assert_eq(r.tree.types.length(), 1)
  assert_eq(r.tree.types[0].name, "Tree")
  // AND THE PAYLOAD IS IN IT -- the recursion, which the harvest used to
  // throw away with the rest of the body.
  assert_eq(r.tree.types[0].refs.length(), 1)
  assert_eq(r.tree.types[0].refs[0], "Tree")
}

///|
/// THE CONTROL, and it is a PLAIN TYPE -- not a recursive one.
///
///     enum Color {
///       Red
///       Green
///     }
///
/// 0647 MEASURED THAT EVERY OBSERVATION WAS THE SAME: one report, one skip,
/// and no node in the tree. That measurement was the point -- "the analyzer
/// reported nothing about the recursive type" could not be read as "the
/// analyzer checked, and the type is not recursive", because the analyzer had
/// not checked.
///
/// 0648 CHANGED THE HALF THAT MATTERS. The parser's OWN output is still the
/// same report and the same skip -- the recursion fact is the TYPE LENS's,
/// and the parser still skips the body it does not analyse -- but the tree
/// now carries the declaration, and the two declarations are NOT the same:
/// the recursive one mentions itself in its payload and the plain one does
/// not.
///
/// SO THE ROW BELOW IS A DIFFERENT QUESTION FROM THE 0647 ONE. It asks whether
/// the two DECLARATIONS differ in the tree, and the answer is yes.
test "0648 control: the two declarations differ in the tree, and the payload is the difference" {
  let recursive = @parser.parse("enum Tree {\n  Leaf\n  Node(Tree, Tree)\n}\n")
  let plain = @parser.parse("enum Color {\n  Red\n  Green\n}\n")
  // THE PARSER'S OWN OUTPUT IS UNCHANGED: the same report, the same skip.
  assert_eq(recursive.first_error, plain.first_error)
  assert_eq(recursive.reports.length(), plain.reports.length())
  assert_eq(recursive.skips.length(), plain.skips.length())
  assert_eq(recursive.skips[0], plain.skips[0])
  // AND NEITHER LEAVES A NODE IN THE BODY.
  assert_eq(recursive.tree.body.length(), 0)
  assert_eq(plain.tree.body.length(), 0)
  // BUT THE DECLARATIONS DIFFER: both are in the tree now, and only the
  // recursive one mentions a type.
  assert_eq(recursive.tree.types.length(), 1)
  assert_eq(plain.tree.types.length(), 1)
  assert_eq(recursive.tree.types[0].name, "Tree")
  assert_eq(plain.tree.types[0].name, "Color")
  assert_eq(recursive.tree.types[0].refs.length(), 1)
  assert_eq(plain.tree.types[0].refs.length(), 0)
}

///|
/// THE RECURSION IS IN THE PAYLOAD, AND THE HARVEST DROPS IT.
///
/// The harvest keeps the NAMES at the top level of the enum body -- `Leaf` and
/// `Node` -- because a name lookup needs them and nothing more. The payload
/// `(Tree, Tree)` is nested, and the nested names are not harvested: `Tree` is
/// the type being declared, and it is the ONLY place the recursion appears.
///
/// So the rows below nail the boundary exactly: the constructor NAMES are
/// there, and the constructor's PAYLOAD is not.
///
/// 0648 DID NOT CHANGE THE HARVEST. It read the declaration ALONGSIDE it, and
/// the payload is in `tree.types` -- which is why the row below still holds,
/// and why the 0648 rows can see the recursion at all.
test "0647: the constructor NAMES are harvested, and the recursive PAYLOAD is not" {
  let r = @parser.parse("enum Tree {\n  Leaf\n  Node(Tree, Tree)\n}\n")
  assert_eq(r.enum_ctors.length(), 2)
  assert_true(r.enum_ctors.contains("Leaf"))
  assert_true(r.enum_ctors.contains("Node"))
  // AND THE TYPE BEING DECLARED IS NOT AMONG THEM: the harvest dropped the
  // payload, and the payload is where the recursion was.
  assert_false(r.enum_ctors.contains("Tree"))
  // AND 0648 PUT IT SOMEWHERE ELSE, WHICH IS THE POINT OF NOT CHANGING THE
  // HARVEST: the payload is in the declaration, not in the name table.
  assert_eq(r.tree.types[0].refs[0], "Tree")
}

///|
/// A RECURSIVE STRUCT IS EXCLUDED THE SAME WAY, AND HARVES NOTHING.
///
///     struct S {
///       next : S        <- recursive
///     }
///
/// A struct is not an enum, so the constructor harvest does not apply to it and
/// no name comes out at all. The exclusion is the same shape -- a notice, and
/// no node in the BODY -- and the recursion (`next : S`) is in the body.
///
/// 0648 READ THAT BODY, so the struct's field type is in `tree.types` now --
/// and the struct's recursion is visible to the type lens, which is what the
/// first measurement of 0648 showed was missing: the struct was read with the
/// ENUM's scanner, which looks for constructors, and a struct has none.
///
/// AND A TYPE ALIAS IS EXCLUDED TOO, with the UNBRACED wording, because an
/// alias has no body to analyse: `type Tree = Tree` says "the body was not
/// analysed" about a declaration that has no body, so the message would be a
/// claim about a body that does not exist. The parser already corrected that
/// (the `derive` correction, `src/parser/parser.mbt:211-230`), and the
/// alias is covered by the same branch.
test "0648: a recursive struct and a recursive alias are excluded, and their recursion is READ" {
  let s = @parser.parse("struct S {\n  next : S\n}\n")
  assert_eq(s.first_error, 0)
  assert_eq(s.reports.length(), 1)
  assert_eq(s.skips.length(), 1)
  assert_eq(s.tree.body.length(), 0)
  // AND A STRUCT HARVES NO CONSTRUCTORS -- it has none.
  assert_eq(s.enum_ctors.length(), 0)
  // AND ITS FIELD TYPE IS READ -- the recursion, in the field this time.
  assert_eq(s.tree.types.length(), 1)
  assert_eq(s.tree.types[0].name, "S")
  assert_eq(s.tree.types[0].refs.length(), 1)
  assert_eq(s.tree.types[0].refs[0], "S")
  // AND THE ALIAS.
  let t = @parser.parse("type Tree = Tree\n")
  assert_eq(t.first_error, 0)
  assert_eq(t.reports.length(), 1)
  assert_eq(t.skips.length(), 1)
  assert_eq(t.tree.body.length(), 0)
  // AND THE TWO EXCLUSIONS DIFFER IN THEIR WORDING -- the alias has no body,
  // so it does not claim one was left unread.
  assert_true(s.skips[0] != t.skips[0])
}
