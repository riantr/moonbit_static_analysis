// Black-box tests for the `.mbtx` script-form import block (see
// EXTENSIONS.md). The authoritative entry grammar, from the script-mode docs,
// is a quoted path with two optional TRAILING modifiers in a fixed order:
//   "path"
//   "path" @alias
//   "path" *
//   "path" @alias *
// Entries are recorded into Module.imports, not resolved; a repeated path is
// a parse-class defect.

///

///|
test "import block: quoted specs recorded, body still parsed" {
  let r = @parser.parse(
    "import {\n  \"moonbitlang/core\",\n  \"riantr/x/src/lib\" @lib,\n}\nfn f() -> int {\n  1\n}\n",
  )
  assert_eq(r.reports.length(), 0)
  assert_eq(r.tree.imports.length(), 2)
  assert_eq(r.tree.imports[0].path(), "moonbitlang/core")
  assert_eq(r.tree.imports[1].path(), "riantr/x/src/lib")
  // the alias is kept, not swallowed with the path
  assert_eq(r.tree.imports[0].alias_name(), "")
  assert_eq(r.tree.imports[1].alias_name(), "lib")
  assert_false(r.tree.imports[0].is_star())
  assert_false(r.tree.imports[1].is_star())
  // the body parses after the block
  assert_eq(r.tree.body.length(), 1)
}

///

///|
test "import block: '*' is a trailing modifier, not an entry" {
  // the docs' own example: "moonbitlang/core/queue" @q *
  let r = @parser.parse(
    "import {\n  \"moonbitlang/core/queue\" @q *,\n}\nfn f() -> int {\n  1\n}\n",
  )
  assert_eq(r.reports.length(), 0)
  assert_eq(r.tree.imports.length(), 1)
  // the path survives the star — recording just "*" would lose it
  assert_eq(r.tree.imports[0].path(), "moonbitlang/core/queue")
  assert_true(r.tree.imports[0].is_star())
  assert_eq(r.tree.imports[0].alias_name(), "q")
}

///

///|
test "import block: '*' without an alias" {
  let r = @parser.parse(
    "import {\n  \"moonbitlang/core\" *,\n}\nfn f() -> int {\n  1\n}\n",
  )
  assert_eq(r.reports.length(), 0)
  assert_eq(r.tree.imports.length(), 1)
  assert_eq(r.tree.imports[0].path(), "moonbitlang/core")
  assert_true(r.tree.imports[0].is_star())
  assert_eq(r.tree.imports[0].alias_name(), "")
}

///

///|
test "import block: canonical rendering round-trips the written form" {
  let r = @parser.parse(
    "import {\n  \"a/b\",\n  \"c/d\" @e,\n  \"f/g\" *,\n  \"h/i\" @j *,\n}\nfn f() -> int {\n  1\n}\n",
  )
  assert_eq(r.reports.length(), 0)
  assert_eq(r.tree.imports.length(), 4)
  assert_eq(r.tree.imports[0].render(), "a/b")
  assert_eq(r.tree.imports[1].render(), "c/d @e")
  assert_eq(r.tree.imports[2].render(), "f/g *")
  assert_eq(r.tree.imports[3].render(), "h/i @j *")
}

///

///|
test "import block: '@version' inside a path is not an alias" {
  // script-mode docs: import paths may carry @version after the module name
  let r = @parser.parse(
    "import {\n  \"moonbitlang/async@0.20.2/fs\",\n  \"moonbitlang/async@0.20.2\",\n}\nfn f() -> int {\n  1\n}\n",
  )
  assert_eq(r.reports.length(), 0)
  assert_eq(r.tree.imports.length(), 2)
  assert_eq(r.tree.imports[0].path(), "moonbitlang/async@0.20.2/fs")
  assert_eq(r.tree.imports[0].alias_name(), "")
  assert_eq(r.tree.imports[1].alias_name(), "")
}

///

///|
test "import block: a trailing entry may omit its comma (docs' own shape)" {
  // the script-mode docs' first example, verbatim
  let r = @parser.parse(
    "import {\n  \"moonbitlang/core/list\" @ls\n}\nfn f() -> int {\n  1\n}\n",
  )
  assert_eq(r.reports.length(), 0)
  assert_eq(r.tree.imports.length(), 1)
  assert_eq(r.tree.imports[0].render(), "moonbitlang/core/list @ls")
}

///

///|
test "import block: a missing comma between entries is rejected" {
  // entries are comma-separated; the lexer always ends a line after a string
  // literal, so `"a/b"` then `"c/d"` is a real missing comma, not a wrap
  let r = @parser.parse(
    "import {\n  \"a/b\"\n  \"c/d\",\n}\nfn f() -> int {\n  1\n}\n",
  )
  assert_eq(r.tree.imports.length(), 1)
  assert_eq(r.tree.imports[0].render(), "a/b")
  assert_true(r.reports.length() >= 1)
  assert_true(r.reports[0].message.contains("'}'"))
}

///

///|
test "import block: duplicate path reported once, modifiers do not excuse it" {
  let r = @parser.parse(
    "import {\n  \"moonbitlang/core\",\n  \"moonbitlang/core\",\n  \"moonbitlang/core\" *,\n}\nfn f() -> int {\n  1\n}\n",
  )
  // the first is kept; the 2nd and 3rd are each reported
  assert_eq(r.tree.imports.length(), 1)
  assert_eq(r.reports.length(), 2)
  assert_true(r.reports[0].message.contains("duplicate import"))
  // the report lands on the duplicate's own line
  assert_eq(r.reports[0].span.start.line, 3)
}

///

///|
test "import block: duplicates across separate blocks are caught too" {
  let r = @parser.parse(
    "import {\n  \"a/b\",\n}\nimport {\n  \"a/b\",\n}\nfn f() -> int {\n  1\n}\n",
  )
  assert_eq(r.tree.imports.length(), 1)
  assert_eq(r.reports.length(), 1)
  assert_true(r.reports[0].message.contains("duplicate import"))
}

///

///|
test "import block: a bare '*' entry is malformed" {
  // '*' only ever trails a quoted path — it is not an entry of its own
  let r = @parser.parse("import {\n  *,\n}\nfn f() -> int {\n  1\n}\n")
  assert_eq(r.tree.imports.length(), 0)
  assert_true(r.reports.length() >= 1)
  assert_true(r.reports[0].message.contains("quoted package path"))
}

///

///|
test "import block: modifiers out of order ('*' before '@alias') is rejected" {
  let r = @parser.parse(
    "import {\n  \"a/b\" * @x,\n}\nfn f() -> int {\n  1\n}\n",
  )
  // the star still binds to its path; the trailing '@x' is left dangling
  assert_eq(r.tree.imports.length(), 1)
  assert_true(r.tree.imports[0].is_star())
  assert_true(r.reports.length() >= 1)
}

///

///|
test "import block: junk entry rejected with FParse" {
  let r = @parser.parse("import {\n  42,\n}\nfn f() -> int {\n  1\n}\n")
  assert_eq(r.reports.length(), 1)
  assert_eq(r.reports[0].family.name(), "ParseError")
  assert_true(r.reports[0].message.contains("quoted package path"))
}

///

///|
test "import without a '{' block rejected" {
  let r = @parser.parse("import foo\nfn f() -> int {\n  1\n}\n")
  assert_eq(r.reports.length(), 1)
  assert_true(r.reports[0].message.contains("'{' block"))
}

///

///|

///|
/// The script-mode docs' own example, verbatim. The docs call this one out
/// specifically: "The package alias remains available, so the example can use
/// both `Queue` and `@q.Queue`" — alias and import-all together on one entry.
/// The body uses `async`, which is outside the subset by design, so only the
/// import block is asserted here.
test "import block: the docs' alias+import-all example, verbatim" {
  let src = "import {\n  \"moonbitlang/core/queue\" @q *\n}\n"
  let r = @parser.parse(src)
  assert_eq(r.reports.length(), 0)
  assert_eq(r.tree.imports.length(), 1)
  assert_eq(r.tree.imports[0].render(), "moonbitlang/core/queue @q *")
  assert_true(r.tree.imports[0].is_star())
  assert_eq(r.tree.imports[0].alias_name(), "q")
}

///

///|
/// The other two documented shapes: an `@alias`-only entry with no trailing
/// comma (the last entry may omit it), and versioned import paths where the
/// `@version` sits inside the quotes and must not be read as an alias.
test "import block: the docs' other two examples, verbatim" {
  let r1 = @parser.parse("import {\n  \"moonbitlang/core/list\" @ls\n}\n")
  assert_eq(r1.reports.length(), 0)
  assert_eq(r1.tree.imports[0].render(), "moonbitlang/core/list @ls")
  assert_false(r1.tree.imports[0].is_star())
  let r2 = @parser.parse(
    "import {\n  \"moonbitlang/async@0.20.2/fs\",\n  \"moonbitlang/async@0.20.2\",\n}\n",
  )
  assert_eq(r2.reports.length(), 0)
  assert_eq(r2.tree.imports.length(), 2)
  // the @version is part of the quoted path, not an alias
  assert_eq(r2.tree.imports[0].path(), "moonbitlang/async@0.20.2/fs")
  assert_eq(r2.tree.imports[0].alias_name(), "")
  assert_eq(r2.tree.imports[1].alias_name(), "")
}

///

///|
test "package sources carry no imports" {
  let r = @parser.parse("fn f() -> int {\n  1\n}\n")
  assert_eq(r.reports.length(), 0)
  assert_eq(r.tree.imports.length(), 0)
}

// --- qualified return types (`-> @pkg.T`) --------------------------------
//
// Found by scanning `moonbitlang/pdf2md@0.1.1`, where `pdf2md_command` returns
// `@argparse.Command`. The lexer emits `@pkg` as a single TName and `T` as
// another, with `TDot` between; the parser used to consume only the head and
// stop at the dot, so every such signature triggered "unexpected token" and
// withheld every finding in the file. Verified by both isolated probes and a
// real scan of the package — withheld dropped 64 → 56 → 0 across the two
// parser fixes that this commit ships.

///|
test "return type: a qualified `@pkg.T` is one type, not two" {
  let r = @parser.parse("fn f() -> @argparse.Command {\n  1\n}\n")
  assert_eq(r.reports.length(), 0)
  assert_eq(r.tree.body.length(), 1)
  // The qualified name is the third slot of the SFunc tuple: name, params,
  // return type, body, span.
  match r.tree.body[0].kind {
    SFunc(_, _, ret, _, _) => assert_eq(ret, "@argparse.Command")
    _ => fail("expected SFunc")
  }
}

///|
test "return type: a chained `@pkg.T.U` keeps the whole chain" {
  let r = @parser.parse("fn f() -> @pkg.T.U {\n  1\n}\n")
  assert_eq(r.reports.length(), 0)
  match r.tree.body[0].kind {
    SFunc(_, _, ret, _, _) => assert_eq(ret, "@pkg.T.U")
    _ => fail("expected SFunc")
  }
}

///|
test "return type: a generic `@pkg.T[Int]` keeps the brackets (head name only)" {
  // The brackets are consumed by skip_indexed; only the head name is
  // returned. The type lens treats `@pkg.T` and `@pkg` identically (both
  // Unknown), so losing the brackets is the documented compromise.
  let r = @parser.parse("fn f() -> @pkg.T[Int] {\n  1\n}\n")
  assert_eq(r.reports.length(), 0)
  match r.tree.body[0].kind {
    SFunc(_, _, ret, _, _) => assert_eq(ret, "@pkg.T")
    _ => fail("expected SFunc")
  }
}

// --- named arguments in calls (`Foo(name=x)`) -----------------------------
//
// Same scan: `moonbitlang/pdf2md@0.1.1`'s `pdf2md_command` body calls
// `Command("pdf2md", about=..., positionals=[...])`. The call-arg loop only
// knew how to parse positional expressions, so the `=` of `about=...` ended
// the parse and withheld the whole file. `Foo(name=x)` and friends now parse;
// a bare `Foo(name)` (no `=`) must NOT be treated as a named arg, or it
// would steal the name from `parse_expr` and break `Foo(name)(...)` /
// `Foo(name).bar` and similar shapes that don't have an `=` after the name.

///|
test "call arg: a named arg `name = value` parses" {
  let r = @parser.parse("fn f() -> int {\n  Foo(name=1)\n}\n")
  assert_eq(r.reports.length(), 0)
}

///|
test "call arg: positional and named args can mix" {
  let r = @parser.parse("fn f() -> int {\n  Foo(1, name=2)\n}\n")
  assert_eq(r.reports.length(), 0)
}

///|
test "call arg: a bare `Foo(name)` is still a single positional arg" {
  // If `name` (with no `=`) were misread as a named-arg label, the parser
  // would steal the name and try to find `=` afterwards, failing at `)`.
  // This is the regression guard: pin that `Foo(name)` stays a positional.
  let r = @parser.parse("fn f() -> int {\n  Foo(name)\n}\n")
  assert_eq(r.reports.length(), 0)
}

///|
test "call arg: a method call after a positional name still parses" {
  // `Foo(name).bar` — the `(name)` is a positional call; the `.bar` is a
  // postfix field access. If the named-arg path swallowed `Foo` we would
  // mis-parse the chain.
  let r = @parser.parse("fn f() -> int {\n  Foo(name).bar\n}\n")
  assert_eq(r.reports.length(), 0)
}

// --- top-level modifiers and out-of-subset declarations -------------------
//
// Found by running this analyzer over real MoonBit code (pyroduct's audit
// package): `pub fn` is how almost every real file opens, and the top-level
// dispatch only recognised a bare `fn`. So `pub` fell through to the statement
// parser, became "undefined variable 'pub'", and the rest of the declaration
// cascaded. Measured on 3 real files, that class alone was the single most
// common false positive.

///|
test "top level: a visibility modifier is not an expression" {
  let r = @parser.parse("pub fn f() -> int {\n  1\n}\n")
  assert_eq(r.reports.length(), 0)
  assert_eq(r.tree.body.length(), 1)
}

///|
test "top level: pub(all) and pub async still parse as functions" {
  let r = @parser.parse("pub(all) async fn f() -> int {\n  1\n}\n")
  assert_eq(r.reports.length(), 0)
  assert_eq(r.tree.body.length(), 1)
}

///|
test "top level: extern is a declaration form, not a modifier" {
  // `pub extern "js" fn f(..) = "raw"` has a raw-string body, not a MoonBit
  // block, so it is not a function the frontend can model. One finding, and the
  // function after it still parses.
  let r = @parser.parse(
    "pub extern \"js\" fn f() -> int = \"0\"\nfn g() -> int {\n  1\n}\n",
  )
  assert_eq(r.reports.length(), 1)
  assert_true(r.reports[0].message.contains("extern"))
  assert_eq(r.tree.body.length(), 1)
}

///|
test "top level: an unmodelled brace declaration is ONE finding, not a cascade" {
  // The field lines used to each become their own UndefinedName plus a
  // ParseError echo, and were then counted as dead top-level statements.
  let r = @parser.parse(
    "pub struct Point {\n  x : int\n  y : int\n}\nfn f() -> int {\n  1\n}\n",
  )
  assert_eq(r.reports.length(), 1)
  assert_true(r.reports[0].message.contains("struct"))
  // the function after the declaration is still parsed
  assert_eq(r.tree.body.length(), 1)
}

///|
test "top level: an enum body is consumed whole" {
  let r = @parser.parse(
    "enum Color {\n  Red\n  Green\n}\nfn f() -> int {\n  1\n}\n",
  )
  assert_eq(r.reports.length(), 1)
  assert_eq(r.tree.body.length(), 1)
}

///|
test "top level: line-terminated declarations are one finding each" {
  let r = @parser.parse(
    "pub type Id = int\npub const K : int = 10\nfn f() -> int {\n  1\n}\n",
  )
  assert_eq(r.reports.length(), 2)
  assert_eq(r.tree.body.length(), 1)
}

///|
test "top level: a body-less impl does not swallow the rest of the file" {
  // `pub impl Eq for T` with its methods in a separate impl block has no body
  // brace. The skip must stop at the `fn` instead of eating the file — the
  // sentinel is that a top-level `fn` cannot legally sit inside a declaration.
  let r = @parser.parse("pub impl Eq for T\nfn f() -> int {\n  1\n}\n")
  assert_eq(r.tree.body.length(), 1)
}

///|
test "top level: a function after an unmodelled declaration is still parsed" {
  // The skip must not blind the pipeline: the function below a skipped struct
  // has to reach the body, or the structural inspection would never see it.
  // (That a defect INSIDE it is still reported is a pipeline property and is
  // pinned in pipeline_test — the parser emits no UndefinedName of its own.)
  let r = @parser.parse(
    "struct P {\n  x : int\n}\nfn f() -> int {\n  missing(1)\n}\n",
  )
  assert_eq(r.reports.length(), 1)
  assert_true(r.reports[0].message.contains("struct"))
  assert_eq(r.tree.body.length(), 1)
}

///|
/// A `test "name" { ... }` block is a declaration form, not a statement. Left to
/// `parse_stmt` the body was parsed as ordinary code and produced a cascade --
/// 25 ParseErrors on one test file in moonbit_linalg_gpu, against 3 from the
/// block's single skip.
test "a test block is skipped whole, and the file after it still parses" {
  let r = @parser.parse(
    "test \"default: returns non-zero\" {\n  match x {\n    A => 1\n  }\n}\nfn f() -> int {\n  1\n}\n",
  )
  assert_eq(r.reports.length(), 1)
  assert_true(r.reports[0].message.contains("test"))
  // the function after the test block still reaches the body
  assert_eq(r.tree.body.length(), 1)
}

///|
/// Attributes are consumed by the lexer and emit no token, so what follows them
/// is classified on its own merits. Before this, `#cfg(target="native")` in
/// front of an `extern` produced "unexpected character '#'" and everything on
/// the line after it cascaded.
test "an attribute is consumed, and the declaration after it is named" {
  let r = @parser.parse(
    "#cfg(target=\"native\")\nextern \"libloading\" fn load(p : string) -> int\n",
  )
  assert_eq(r.reports.length(), 1)
  assert_true(r.reports[0].message.contains("extern"))
}

///|
/// `#[derive(Eq)]` and a bare `#deprecated`, and a function before and after,
/// so the attribute branch cannot be eating code.
test "brackets and bare attributes are consumed" {
  let r = @parser.parse(
    "#deprecated\nfn a() -> int {\n  1\n}\n#[derive(Eq)]\nstruct P {\n  x : int\n}\nfn b() -> int {\n  2\n}\n",
  )
  // one finding: the struct, which was going to be reported anyway
  assert_eq(r.reports.length(), 1)
  assert_true(r.reports[0].message.contains("struct"))
  assert_eq(r.tree.body.length(), 2)
}

///|
/// The attribute's argument list can itself contain brackets and parens, and can
/// span lines.
test "an attribute argument list is consumed whole" {
  let r = @parser.parse(
    "#cfg(target=[\n  \"a\",\n  \"b\",\n])(all)\nfn a() -> int {\n  1\n}\n",
  )
  assert_eq(r.reports.length(), 0)
  assert_eq(r.tree.body.length(), 1)
}

///|
/// Qualified path calls of ANY segment count. The `.` branch in
/// `parse_postfix` turns `@pkg.Type` into `EField(EName("@pkg"), "Type")`
/// before the `::` branch ever runs, so a path with two or more segments used
/// to arrive at a `match` that only accepted `EName` and fell through to
/// `break` — leaving `::method()` unconsumed and cascading four parse errors
/// for a shape the toolchain compiles. Measured on 0.4.3 against
/// `moonbitlang/pdf2md@0.1.1`'s argparse-derived call shape:
/// `Foo(name=@argparse.ValueRange::single())` = 4 errors, `A.B::m()` = 2,
/// while the single-segment `A::m()` parsed clean. The `::` is an
/// unambiguous path marker, so the whole chain folds back into one name.
test "a two-segment path call parses: A.B::m()" {
  assert_eq(@parser.parse("A.B::m()\n").reports.length(), 0)
  assert_eq(@parser.parse("@p.A.B::m()\n").reports.length(), 0)
}

///|
/// The case the fix was written for: a qualified path call as the VALUE of a
/// named argument. Both halves are needed — `=` handling came in 0.4.3, the
/// multi-segment path here.
test "a named arg may hold a multi-segment path call" {
  assert_eq(@parser.parse("Foo(name=@pkg.T::m())\n").reports.length(), 0)
  assert_eq(@parser.parse("Foo(@pkg.T::m())\n").reports.length(), 0)
  assert_eq(@parser.parse("Foo(@p.T::m(), 2)\n").reports.length(), 0)
}

///|
/// A path reference (no call) and a path call followed by field access, which
/// are the two shapes adjacent to the fixed one.
test "multi-segment paths work as references and as receivers" {
  assert_eq(@parser.parse("let x = A.B::m\n").reports.length(), 0)
  assert_eq(@parser.parse("let x = @p.T::m().f\n").reports.length(), 0)
  assert_eq(@parser.parse("let x = [@p.T::m()]\n").reports.length(), 0)
  assert_eq(@parser.parse("let x = 1 + A.B::m()\n").reports.length(), 0)
}

///|
/// The negative control for the folding: `::` must NOT be accepted after a
/// call result. `dotted()` returns "" for an ECall (a call result has no
/// name to extend), so `@p.T::m()::n()` stays a read failure — one reported,
/// not silently absorbed into a plausible-looking name. Pinning this matters
/// because the naive fix (accept any `::`) would swallow it.
test "'::' after a call result is still a read failure" {
  let r = @parser.parse("@p.T::m()::n()\n")
  assert_true(r.reports.length() > 0)
  assert_true(r.first_error > 0)
}

///|
/// Calling a struct field (`a.b(1)`) is a separate, deliberate limitation:
/// deciding whether `b` is a method or a plain field needs type information
/// the single-file frontend does not have. Pinning it here so the `::` fix is
/// not later mistaken for having solved it.
test "calling a field is still reported, not silently accepted" {
  let r = @parser.parse("a.b(1)\n")
  assert_eq(r.reports.length(), 1)
  assert_true(r.reports[0].message.contains("only named functions"))
}

///|
/// A list comprehension read as a plain element list runs off the end of the
/// list and hands the statement parser `self => ...`, which — because the
/// lexer maps `'='` to `TAssign` and has no `=>` token — is an assignment to
/// `self`. Measured on 0.4.4: one line of valid MoonBit produced BOTH
/// "parameter 'self' changed by assignment" and "parameter 'self' may not be
/// used" on the same token. Neither is true, and they contradict each other.
test "a list comprehension is read as a comprehension, not an assignment" {
  let r = @parser.parse(
    "fn f(self : Array[Int]) -> Array[Int] {\n  [ for x in self => x + 1 ]\n}\n",
  )
  // fully read: `first_error` is 0 only when nothing failed to parse
  assert_eq(r.first_error, 0)
  assert_eq(r.reports.length(), 0)
}

///|
/// The two shapes an earlier version got backwards. It asserted that
/// `[ for x in a { ... } ]` parses clean and that a guard goes after the
/// body; the toolchain says the opposite of both — the block body needs its
/// `=>` first, and the guard comes before it. Kept as an explicit pair so the
/// two directions cannot drift apart again.
test "the invalid sibling shapes are reported, the valid ones are not" {
  // invalid: `{` without `=>`
  let brace_first = @parser.parse(
    "fn f(a : Array[Int]) -> Array[Int] {\n  [ for x in a { x + 1 } ]\n}\n",
  )
  assert_true(brace_first.reports.length() > 0)
  // valid: `=> {`
  let arrow_first = @parser.parse(
    "fn f(a : Array[Int]) -> Array[Int] {\n  [ for x in a => { x + 1 } ]\n}\n",
  )
  assert_eq(arrow_first.reports.length(), 0)
  // invalid: guard after the body
  let guard_after = @parser.parse(
    "fn f(a : Array[Int]) -> Array[Int] {\n  [ for x in a => x if x > 0 ]\n}\n",
  )
  assert_true(guard_after.reports.length() > 0)
  // valid: guard before the body
  let guard_before = @parser.parse(
    "fn f(a : Array[Int]) -> Array[Int] {\n  [ for x in a if x > 0 => x ]\n}\n",
  )
  assert_eq(guard_before.reports.length(), 0)
}

///|
/// A destructuring pattern and a second generator, both of which 0.4.5 got
/// wrong. `for` is written ONCE in MoonBit and each following generator
/// repeats only its pattern and iterable — a first implementation that
/// accepted only a comma-then-`for` missed the form entirely. The corpus
/// sources: `sorted_map/debug.mbt`, `hashmap/debug.mbt`,
/// `immut/hashmap/debug.mbt` and `hashmap/json.mbt` in moonbitlang/core.
test "a destructuring pattern and a second generator both parse clean" {
  let t = @parser.parse(
    "fn f(self : Array[(Int, Int)]) -> Array[String] {\n  [ for k, v in self => \"k\" ]\n}\n",
  )
  assert_eq(t.first_error, 0)
  assert_eq(t.reports.length(), 0)
  let g = @parser.parse(
    "fn f(a : Array[Int], b : Array[Int]) -> Array[Int] {\n  [ for x in a, y in b => x + y ]\n}\n",
  )
  assert_eq(g.first_error, 0)
  assert_eq(g.reports.length(), 0)
}

///|
/// The block body and the guard, in the positions the toolchain actually
/// puts them. Probed one form per file with `moon check` (a directory without
/// a `moon.pkg` answers "no work to do" and exits 0 — a false green):
///   `[ for x in a if x > 0 => x ]`   0 errors
///   `[ for x in a => x if x > 0 ]`   E3002 unexpected token `if`
///   `[ for x in a => { stmts } ]`    0 errors
///   `[ for x in a { stmts } ]`       E3002 unexpected token `{`
/// An earlier version of this file asserted the OPPOSITE of all four, on the
/// strength of a probe whose error line was read as the other form.
test "block-bodied and guarded comprehensions parse clean in the real shapes" {
  let r = @parser.parse(
    "fn f(a : Array[Int]) -> Array[Int] {\n  [ for x in a => {\n    let y = x + 1\n    y\n  } ]\n}\n",
  )
  assert_eq(r.first_error, 0)
  assert_eq(r.reports.length(), 0)
  let g = @parser.parse(
    "fn f(a : Array[Int]) -> Array[Int] {\n  [ for x in a if x > 0 => x ]\n}\n",
  )
  assert_eq(g.first_error, 0)
  assert_eq(g.reports.length(), 0)
}

///|
/// ...and the guard really is before the arrow: a post-body `if` is what
/// `moon check` rejects, so this is the one direction that must NOT parse.
test "a guard after the body is reported, as the toolchain rejects it" {
  let bad = @parser.parse(
    "fn f(a : Array[Int]) -> Array[Int] {\n  [ for x in a => x if x > 0 ]\n}\n",
  )
  assert_true(bad.reports.length() > 0)
}

///|
/// A comprehension still yields a list. The change is that it is now its own
/// node instead of a mangled `EList`, so `EList` must not have grown to
/// absorb it — a plain `[1, 2]` keeps two elements.
test "a plain list literal is still a plain list literal" {
  let r = @parser.parse("[1, 2]\n")
  assert_eq(r.reports.length(), 0)
  match r.tree.body[0].kind {
    @ast.SExpr(e) =>
      match e.kind {
        @ast.EList(items) => assert_eq(items.length(), 2)
        _ => assert_true(false)
      }
    _ => assert_true(false)
  }
}
