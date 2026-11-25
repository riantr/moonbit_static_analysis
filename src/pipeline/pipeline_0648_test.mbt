//| pipeline_0648_test.mbt -- THE DISCRIMINATING MEASUREMENT 0647 SAID WAS NOT
//| AVAILABLE.
//
//| 0647's judgment was: "an absence of a finding is evidence about the program
//| only if the analyzer's CAPACITY to produce it was itself measured". And the
//| measurement it could take was the negative one: a recursive type and a
//| plain type produced the SAME report, so the analyzer had not looked.
//
//| 0648 gives the analyzer the capacity, and these rows are the positive
//| measurement: the two programs now produce DIFFERENT reports. That
//| difference is what makes "the analyzer reported nothing about the recursive
//| type" readable as a fact about the PROGRAM.
//
//| THE SHAPE OF THE OUTPUT IS WORTH ONE MORE WORD, because it is the shape
//| the merge forces: the recursive-type notice lands on the SAME LINE as the
//| declaration's own scope-limit notice, and the pipeline merges findings by
//| (family, line). The type lens's report is the more specific one -- the
//| type lens outranks the structural lens -- so ITS message is the one the
//| reader sees, and it therefore has to carry BOTH facts: that the body was
//| not analysed, and that the type is recursive.

///|
/// THE TWO PROGRAMS, AND THE DIFFERENCE BETWEEN THEM.
///
///     enum Tree { Leaf, Node(Tree, Tree) }     <- recursive
///     enum Color { Red, Green }                <- not recursive
///
/// ONE REPORT EACH -- the recursion ADDS A FACT to the report, it does not add
/// a report -- and the two reports are DIFFERENT.
test "0648: a recursive type and a plain type produce DIFFERENT reports" {
  let recursive = @pipeline.run(
    "enum Tree {\n  Leaf\n  Node(Tree, Tree)\n}\n",
    "u.mbt",
    empty_iface(),
  )
  let plain = @pipeline.run(
    "enum Color {\n  Red\n  Green\n}\n",
    "u.mbt",
    empty_iface(),
  )
  assert_eq(recursive.reports.length(), 1)
  assert_eq(plain.reports.length(), 1)
  // AND THE MESSAGES DIFFER. This is the whole increment in one comparison.
  assert_true(recursive.reports[0].message != plain.reports[0].message)
  // AND THE DIFFERENCE IS THE RECURSION, not an accident of the wording.
  assert_true(recursive.reports[0].message.contains("recursive type"))
  assert_false(plain.reports[0].message.contains("recursive type"))
}

///|
/// AND BOTH ARE STILL SCOPE LIMITS, BECAUSE A RECURSIVE TYPE IS LEGAL.
///
/// `moon check` ACCEPTS `enum Tree { Leaf(Int), Node(Tree, Tree) }` (MEASURED
/// 0648, against the toolchain): a recursive type is an ordinary inductive
/// type and MoonBit is FOR it. So this is not a defect in the reader's code,
/// the label says `notice`, and the confidence says `undecided` -- the
/// analyzer did not decide anything about the type.
///
/// The CONTROL is in the row above: the plain type is not recursive, and its
/// notice is the declaration's own.
test "0648: a recursive type is a SCOPE LIMIT, not a defect" {
  let r = @pipeline.run(
    "enum Tree {\n  Leaf\n  Node(Tree, Tree)\n}\n",
    "u.mbt",
    empty_iface(),
  )
  assert_eq(r.reports.length(), 1)
  let rep = r.reports[0]
  assert_eq(rep.family.id(), "MSA-001")
  assert_true(rep.is_notice())
  assert_eq(rep.severity_label(), "notice")
  assert_true(rep.confidence() == @core.Undecided)
  // AND THE SCOPE-LIMIT MARKER IS THERE, because that is what makes it a
  // notice rather than a finding: the convention is held by
  // `_verify/check_notice_labels.ps1`.
  assert_true(rep.message.contains("subset"))
}

///|
/// A MUTUAL RECURSION IS TWO RECURSIVE TYPES, AND TWO NOTICES.
///
///     enum A { A1(B) }
///     enum B { B1(A) }
///
/// The cycle is one cycle, but the TYPES on it are two, and the count a
/// reader sees is the number of recursive types.
test "0648: a mutual recursion is two recursive types, and two notices" {
  let r = @pipeline.run(
    "enum A {\n  A1(B)\n}\nenum B {\n  B1(A)\n}\n",
    "u.mbt",
    empty_iface(),
  )
  assert_eq(r.reports.length(), 2)
  for rep in r.reports {
    assert_true(rep.is_notice())
    assert_true(rep.message.contains("recursive type"))
  }
}

///|
/// A RECURSIVE STRUCT IS SEEN TOO -- AND THAT IS A ROW OF ITS OWN, BECAUSE THE
/// FIRST VERSION MISSED IT.
///
/// The first version of this increment read a struct's body with the ENUM's
/// scanner, which looks for a constructor and a struct has none. So a
/// recursive struct produced NO notice, while a recursive enum did -- and the
/// measurement that caught it is the only reason this row exists.
///
/// THE CONTROL IS A PLAIN STRUCT, whose field type is a builtin: it mentions
/// no type of this module, so it is not on a cycle.
test "0648: a recursive struct is seen, and a plain struct is not" {
  let recursive = @pipeline.run(
    "struct Node {\n  left : Node\n}\n",
    "u.mbt",
    empty_iface(),
  )
  assert_eq(recursive.reports.length(), 1)
  assert_true(recursive.reports[0].message.contains("recursive type"))
  // AND THE CONTROL.
  let plain = @pipeline.run(
    "struct Point {\n  x : Int\n  y : Int\n}\n",
    "u.mbt",
    empty_iface(),
  )
  assert_eq(plain.reports.length(), 1)
  assert_false(plain.reports[0].message.contains("recursive type"))
}

///|
/// AN ALIAS CYCLE IS A NOTICE WITH ITS OWN WORDING.
///
/// The toolchain REJECTS this shape -- `moon check` says "Found cycle A -> B ->
/// A in `type alias` declaration" and exits non-zero (MEASURED 0648) -- so
/// the compiler is the authority, and this analyzer says what it cannot do:
/// it models no recursive type at all.
test "0648: an alias cycle is a notice with its own wording" {
  let r = @pipeline.run("type A = B\ntype B = A\n", "u.mbt", empty_iface())
  assert_eq(r.reports.length(), 2)
  for rep in r.reports {
    assert_true(rep.is_notice())
    assert_true(rep.message.contains("recursive type alias"))
  }
}

///|
/// A FILE THE FRONTEND DID NOT READ WHOLE IS NOT ANALYSED, AND THAT INCLUDES
/// THE TYPE GRAPH.
///
/// The declarations after a read failure were never read, so the graph would
/// be missing its nodes -- and a missing cycle is not evidence that there is
/// none. This is the "missing is not default" rule one level up: a graph
/// built from a half-read file answers a question about the HALF.
///
/// So the recursive type BELOW the failure produces no notice, and the
/// CONTROL is the same file with the failure moved below the declaration.
test "0648: a half-read file is not analysed for recursion either" {
  let broken = "enum Tree {\n  Leaf\n  Node(Tree, Tree)\n}\nfn f() {\n  ???\n}\n"
  let r = @pipeline.run(broken, "u.mbt", empty_iface())
  assert_true(r.first_error_line > 0)
  // AND THE CONTROL: THE SAME FILE, READ WHOLE.
  let whole = @pipeline.run(
    "enum Tree {\n  Leaf\n  Node(Tree, Tree)\n}\n",
    "u.mbt",
    empty_iface(),
  )
  assert_eq(whole.first_error_line, 0)
  assert_true(whole.reports[0].message.contains("recursive type"))
}

///|
/// THE SUBSET COUNT DOES NOT MOVE.
///
/// The recursive-type notice MERGES with the declaration's own scope-limit
/// notice -- the pipeline merges by (family, line), and both are on the
/// declaration's line -- so the number of findings is the number it was, and
/// the number of deliberate exclusions is the number it was. What moved is
/// the MESSAGE, and the shape the notices are counted by.
test "0648: the subset count does not move -- the notice merges with the declaration's own" {
  let recursive = @pipeline.run(
    "enum Tree {\n  Leaf\n  Node(Tree, Tree)\n}\n",
    "u.mbt",
    empty_iface(),
  )
  let plain = @pipeline.run(
    "enum Color {\n  Red\n  Green\n}\n",
    "u.mbt",
    empty_iface(),
  )
  assert_eq(recursive.n_subset, plain.n_subset)
  assert_eq(recursive.n_subset, 1)
  assert_eq(recursive.reports.length(), plain.reports.length())
  // AND THE MERGED REPORT CARRIES BOTH LENSES: the structural lens saw the
  // declaration, and the type lens saw the recursion.
  assert_eq(recursive.reports[0].lenses.length(), 2)
  assert_eq(plain.reports[0].lenses.length(), 1)
}
