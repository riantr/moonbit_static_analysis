//| parser_0647_test.mbt -- THE TYPE LAYER'S RECURSION, WHICH IS NOT A FEATURE
//| THAT WAS NEVER TESTED. IT IS A CAPABILITY THAT DOES NOT EXIST.
//|
//| THE AUDIT QUESTION WAS: "is a recursive type detected?" The answer measured
//| here is NO, and -- this is the part that matters -- the answer is NO for a
//| reason that no test can turn into a yes by writing a different fixture.
//|
//| THE FRONTEND DOES NOT READ TYPE DEFINITIONS. `ast::Module` has a `body` and
//| an `imports` and nothing else (`src/ast/ast.mbt:821-829`): there is no
//| node for an `enum`, no node for a `struct`, no node for a `type` alias. The
//| parser SKIPS those declarations at the token level (`skip_decl_braced`,
//| `src/parser/parser.mbt:1097`), and what survives of an `enum` is its
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
//| asserted "no recursive-type finding was produced" would be satisfied by an
//| analyzer that cannot see type definitions AT ALL -- which is the truth
//| here, and is exactly why such an assertion proves nothing on its own. The
//| discriminating observation is that the recursive program and the plain one
//| are INDISTINGUISHABLE to the frontend: same notice, same report count, and
//| -- the sharpest one -- NOTHING IN THE TREE.
//|
//| THE MESSAGE IS NOT SPELLED OUT IN A LITERAL HERE. A test that compares a
//| literal with a literal proves only that a literal agrees with a literal.
//| What is asserted instead is that the notice's CLAIM is true: the parser
//| says the declaration's body was not analysed, and the claim is checked
//| against the TREE -- the declaration left no node in it. That is 0500's
//| invariant read the other way round.

///|
/// A RECURSIVE TYPE LEAVES NO NODE IN THE TREE.
///
///     enum Tree {
///       Leaf
///       Node(Tree, Tree)      <- recursive: the payload names the type
///     }
///
/// The file is READ (`first_error` is 0), the exclusion is RECORDED (one
/// report, one skip), and the enum leaves NOTHING behind: the tree's body is
/// empty. A later layer cannot detect a recursive type that left no node to
/// be detected in -- and this row is what makes that sentence a measurement
/// rather than an argument.
test "0647: a recursive type leaves NO node in the tree" {
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
  // AND THE CLAIM THE NOTICE MAKES IS TRUE AGAINST THE TREE: the declaration
  // is not in it. This is the assertion that is about the recursion -- and it
  // is an assertion about ABSENCE, so it needs the control in the next row.
  assert_eq(r.tree.body.length(), 0)
}

///|
/// THE CONTROL, and it is a PLAIN TYPE -- not a recursive one.
///
///     enum Color {
///       Red
///       Green
///     }
///
/// EVERY OBSERVATION IS THE SAME: one report, one skip, and NO NODE IN THE
/// TREE. The frontend cannot tell a recursive type from a plain one, because
/// it reads neither.
///
/// SO THE ROW ABOVE CANNOT BE READ AS "the analyzer checked and found no
/// recursion". It has to be read as "the analyzer never looked". A reader who
/// took the absence of a recursive-type finding as a fact about the program
/// would be reporting the shape of the analyzer as a property of the code.
test "0647 control: a plain type leaves NO node either -- the two are identical" {
  let recursive = @parser.parse("enum Tree {\n  Leaf\n  Node(Tree, Tree)\n}\n")
  let plain = @parser.parse("enum Color {\n  Red\n  Green\n}\n")
  assert_eq(recursive.first_error, plain.first_error)
  assert_eq(recursive.reports.length(), plain.reports.length())
  assert_eq(recursive.skips.length(), plain.skips.length())
  // AND THE NOTICE IS THE SAME NOTICE -- the recursive one is not called out.
  assert_eq(recursive.skips[0], plain.skips[0])
  // AND NEITHER LEAVES A NODE.
  assert_eq(recursive.tree.body.length(), 0)
  assert_eq(plain.tree.body.length(), 0)
}

///|
/// THE RECURSION IS IN THE PAYLOAD, AND THE PAYLOAD IS WHAT THE HARVEST
/// DROPS.
///
/// The harvest keeps the NAMES at the top level of the enum body -- `Leaf` and
/// `Node` -- because a name lookup needs them and nothing more. The payload
/// `(Tree, Tree)` is nested, and the nested names are not harvested: `Tree` is
/// the type being declared, and it is the ONLY place the recursion appears.
///
/// So the rows below nail the boundary exactly: the constructor NAMES are
/// there, and the constructor's PAYLOAD is not. A future increment that wants
/// to detect recursive types has to change THAT -- the harvest -- and not the
/// notice, which is already correct about what was not analysed.
test "0647: the constructor NAMES are harvested, and the recursive PAYLOAD is not" {
  let r = @parser.parse("enum Tree {\n  Leaf\n  Node(Tree, Tree)\n}\n")
  assert_eq(r.enum_ctors.length(), 2)
  assert_true(r.enum_ctors.contains("Leaf"))
  assert_true(r.enum_ctors.contains("Node"))
  // AND THE TYPE BEING DECLARED IS NOT AMONG THEM: the payload was dropped,
  // and the payload is where the recursion was.
  assert_false(r.enum_ctors.contains("Tree"))
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
/// no node in the tree -- and the recursion (`next : S`) is in the body, which
/// is the part that was not read.
///
/// AND A TYPE ALIAS IS EXCLUDED TOO, with the UNBRACED wording, because an
/// alias has no body to analyse: `type Tree = Tree` says "the body was not
/// analysed" about a declaration that has no body, so the message would be a
/// claim about a body that does not exist. The parser already corrected that
/// (the `derive` correction, `src/parser/parser.mbt:211-230`), and the
/// alias is covered by the same branch.
test "0647: a recursive struct and a recursive alias are excluded, and leave no node" {
  let s = @parser.parse("struct S {\n  next : S\n}\n")
  assert_eq(s.first_error, 0)
  assert_eq(s.reports.length(), 1)
  assert_eq(s.skips.length(), 1)
  assert_eq(s.tree.body.length(), 0)
  // AND A STRUCT HARVES NO CONSTRUCTORS -- it has none.
  assert_eq(s.enum_ctors.length(), 0)
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
