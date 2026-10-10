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
test "top level: extern fn is modelled, with a real signature and an empty body" {
  // It used to be skipped as an unmodelled form. That was right while it WAS
  // unmodelled, but skipping loses the NAME, and every call site of an extern
  // function then read as an unbound name. The signature is real (so the type
  // lens can check calls); the body is empty because the implementation lives
  // in another language.
  let r = @parser.parse(
    "pub extern \"js\" fn f(x : int) -> int = \"0\"\nfn g() -> int {\n  f(1)\n}\n",
  )
  assert_eq(r.reports.length(), 0)
  assert_eq(r.tree.body.length(), 2)
  // f is a real top-level function binding, g is the one that calls it.
  let ff = top_level_fns(r.tree)
  assert_true(ff.contains("f"))
  assert_true(ff.contains("g"))
}

///|
test "extern fn with no ABI string and no return annotation" {
  // Both are optional in real code; neither may cost a parse error.
  let r = @parser.parse("extern \"c\" fn native_exit(code : int)\n")
  assert_eq(r.reports.length(), 0)
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
  // Zero findings: the attribute is consumed AND the extern is modelled. This
  // test used to assert one 'extern is outside the subset' notice, which was
  // the contract at the time; the notice is gone because the form is now read.
  assert_eq(r.reports.length(), 0)
  let ff = top_level_fns(r.tree)
  assert_true(ff.contains("load"))
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
/// A method call is a node of its own, and the receiver stays an expression.
///
/// This test used to assert the OPPOSITE — that `a.b(1)` was reported as
/// "only named functions can be called". That limitation is gone, and the old
/// comment explained why it was hard: deciding whether `b` is a method or a
/// plain field needs type information the single-file frontend does not have.
/// The fix does not need that answer. `EMethodCall` keeps the receiver and the
/// name side by side and NO lens resolves the name, so the question never has
/// to be answered — a field read, a method call, and an unknown method are all
/// representable, and the ones the analyzer cannot judge stay silent.
///
/// The receiver matters: flattening `a.b(1)` into a name would hide the read of
/// `a`, and then a binding that exists only to be written to would look unused.
/// That is asserted below, not just the shape.
test "a method call parses into its own node, receiver included" {
  let r = @parser.parse("fn f() -> int {\n  a.b(1)\n  0\n}\n")
  assert_eq(r.reports.length(), 0)
  let found = find_method_calls(r.tree)
  assert_eq(found.length(), 1)
  assert_eq(found[0], ("b", "a"))
}

///|
/// The negative control for the one above. `a.b` with NO parentheses is a field
/// read, not a call, and must not become a method call — otherwise every field
/// access would drag an empty argument list through all three lenses.
test "a field read with no parentheses is still a field read" {
  let r = @parser.parse("fn f() -> int {\n  let x = a.b\n  0\n}\n")
  assert_eq(r.reports.length(), 0)
  assert_eq(find_method_calls(r.tree).length(), 0)
}

///|
/// Chained calls are method calls all the way down, and each link keeps its own
/// receiver: `a.b().c()` is `EMethodCall(EMethodCall(a, b, []), c, [])`. The
/// inner one is a receiver, so if the walk ever stopped evaluating receivers it
/// would be the inner link that loses `a`.
test "a chained method call nests, and each link keeps its receiver" {
  let r = @parser.parse("fn f() -> int {\n  a.b().c()\n  0\n}\n")
  assert_eq(r.reports.length(), 0)
  assert_eq(find_method_calls(r.tree).length(), 2)
}

///|
/// Names of every top-level `fn` in a module, in source order. The instrument
/// that says "this declaration was read as a function", which is exactly what
/// the extern form has to earn: skipping it produced no name, and a call to an
/// unnamed function reads as an unbound name.
fn top_level_fns(m : @ast.Module) -> Array[String] {
  let out : Array[String] = []
  for s in m.body {
    match s.kind {
      @ast.SFunc(n, _, _, _, _) => out.push(n)
      _ => ()
    }
  }
  out
}

///|
/// Collect `(method, receiver-root)` for every method call in a module, in
/// source order. Written here rather than exposed from the parser because it is
/// a test instrument; the parser has no reason to offer it.
fn find_method_calls(m : @ast.Module) -> Array[(String, String)] {
  let out : Array[(String, String)] = []
  fn root(e : @ast.Expr) -> String {
    match e.kind {
      @ast.EName(n) => n
      @ast.EField(b, _) => root(b)
      @ast.EMethodCall(b, _, _) => root(b)
      _ => "?"
    }
  }
  fn ex(e : @ast.Expr) -> Unit {
    match e.kind {
      @ast.EMethodCall(b, name, args) => {
        out.push((name, root(b)))
        ex(b)
        for a in args {
          ex(a)
        }
      }
      @ast.EList(xs) =>
        for x in xs {
          ex(x)
        }
      @ast.EUnary(_, a) => ex(a)
      @ast.EBin(_, a, b) => {
        ex(a)
        ex(b)
      }
      @ast.ECall(_, args) =>
        for a in args {
          ex(a)
        }
      @ast.EField(b, _) => ex(b)
      @ast.EIndex(b, i) => {
        ex(b)
        ex(i)
      }
      @ast.EComp(_, sources, body) => {
        for s in sources {
          ex(s)
        }
        ex(body)
      }
      _ => ()
    }
  }
  fn st(stmts : Array[@ast.Stmt]) -> Unit {
    for s in stmts {
      match s.kind {
        @ast.SExpr(e) => ex(e)
        @ast.SLet(_, _, e) => ex(e)
        @ast.SAssign(a, b) => {
          ex(a)
          ex(b)
        }
        @ast.SIf(c, t, elseifs, el) => {
          ex(c)
          st(t)
          for ei in elseifs {
            ex(ei.cond)
            st(ei.body)
          }
          match el {
            Some(b) => st(b)
            None => ()
          }
        }
        @ast.SWhile(c, b) => {
          ex(c)
          st(b)
        }
        @ast.SFor(_, _, s, b) => {
          ex(s)
          st(b)
        }
        @ast.SFunc(_, _, _, body, _) => st(body)
        @ast.SReturn(e) =>
          match e {
            Some(x) => ex(x)
            None => ()
          }
        _ => ()
      }
    }
  }
  st(m.body)
  out
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
/// A destructuring pattern, which moonbitlang/core uses in
/// `sorted_map/debug.mbt`, `hashmap/debug.mbt`, `immut/hashmap/debug.mbt`
/// and `hashmap/json.mbt`. The comma belongs to the PATTERN, before `in`.
test "a destructuring comprehension pattern parses clean" {
  let t = @parser.parse(
    "fn f(self : Array[(Int, Int)]) -> Array[String] {\n  [ for k, v in self => \"k\" ]\n}\n",
  )
  assert_eq(t.first_error, 0)
  assert_eq(t.reports.length(), 0)
}

///|
/// A comprehension has exactly ONE generator. Two earlier versions of this
/// file chased a multi-generator form that does not exist — one accepted
/// `[ for x in a, y in b => … ]` and a test pinned it as clean. Probed with
/// `moon check` (canary-verified):
///   [ for x in a, for y in b => x + y ]   E3002 unexpected token `,`
///   [ for x in a, y in b => x + y ]       E3002 unexpected token `,`
/// Accepting it was worse than ignoring it: the second iterable was read and
/// the first silently DROPPED, so the comprehension analysed a different
/// expression than the source contained. Both spellings are now reported.
test "a second generator is reported, not silently reinterpreted" {
  let a = @parser.parse(
    "fn f(a : Array[Int], b : Array[Int]) -> Array[Int] {\n  [ for x in a, for y in b => x + y ]\n}\n",
  )
  assert_true(a.reports.length() > 0)
  let b = @parser.parse(
    "fn f(a : Array[Int], b : Array[Int]) -> Array[Int] {\n  [ for x in a, y in b => x + y ]\n}\n",
  )
  assert_true(b.reports.length() > 0)
  // ...while the single generator that DOES exist still parses clean, and
  // the destructuring comma (which comes before `in`) is unaffected
  let ok = @parser.parse(
    "fn f(a : Array[Int]) -> Array[Int] {\n  [ for x in a => x ]\n}\n",
  )
  assert_eq(ok.reports.length(), 0)
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

///|
/// Operator of a binary expression, as its source symbol. `BOp` derives Eq
/// but not Show, so tests compare operators through `symbol()`.
fn bin_op(e : @ast.Expr) -> String {
  match e.kind {
    @ast.EBin(op, _, _) => op.symbol()
    _ => "?"
  }
}

///|
/// The constructs the 0.4.8 self-scan exposed. The 0.4.7 self-scan of this
/// module's own source parsed 20 of 46 files; every construct below stopped a
/// real file at its first parse error, so each now has a pin. The last test
/// is the negative control: the subset has no ternary, and in a call's
/// argument list one breaks at the `)` the parser expects — the shape the
/// self-scan actually met.
test "a struct literal with a type path parses as EStruct with its fields" {
  let r = @parser.parse("fn f() -> Int {\n  let p = Pos::{ line: 1 }\n  0\n}\n")
  assert_eq(r.reports.length(), 0)
  match r.tree.body[0].kind {
    @ast.SFunc(_, _, _, body, _) =>
      match body[0].kind {
        @ast.SLet(name, ann, init) => {
          assert_eq(name, "p")
          assert_eq(ann, "")
          match init.kind {
            @ast.EStruct(path, fields) => {
              assert_eq(path, "Pos")
              assert_eq(fields.length(), 1)
              match fields[0] {
                (fname, fval) => {
                  assert_eq(fname, "line")
                  match fval.kind {
                    @ast.EInt(n) => assert_eq(n, 1)
                    _ => assert_true(false)
                  }
                }
              }
            }
            _ => assert_true(false)
          }
        }
        _ => assert_true(false)
      }
    _ => assert_true(false)
  }
}

///|
test "an anonymous struct literal parses with an empty path" {
  let r = @parser.parse("fn f() -> Int {\n  let s = { a: 1, b }\n  0\n}\n")
  assert_eq(r.reports.length(), 0)
  match r.tree.body[0].kind {
    @ast.SFunc(_, _, _, body, _) =>
      match body[0].kind {
        @ast.SLet(_, _, init) =>
          match init.kind {
            @ast.EStruct(path, fields) => {
              assert_eq(path, "")
              assert_eq(fields.length(), 2)
              match fields[0] {
                (n1, v1) => {
                  assert_eq(n1, "a")
                  match v1.kind {
                    @ast.EInt(n) => assert_eq(n, 1)
                    _ => assert_true(false)
                  }
                }
              }
              match fields[1] {
                (n2, v2) => {
                  assert_eq(n2, "b")
                  match v2.kind {
                    @ast.EName(v) => assert_eq(v, "b")
                    _ => assert_true(false)
                  }
                }
              }
            }
            _ => assert_true(false)
          }
        _ => assert_true(false)
      }
    _ => assert_true(false)
  }
}

///|
test "tuples parse: two elements, unit, and one-with-trailing-comma" {
  let r = @parser.parse(
    "fn f() -> Int {\n  let t = (1, 2)\n  let u = ()\n  let s = (1,)\n  0\n}\n",
  )
  assert_eq(r.reports.length(), 0)
  match r.tree.body[0].kind {
    @ast.SFunc(_, _, _, body, _) => {
      match body[0].kind {
        @ast.SLet(_, _, init) =>
          match init.kind {
            @ast.ETuple(elems) => assert_eq(elems.length(), 2)
            _ => assert_true(false)
          }
        _ => assert_true(false)
      }
      match body[1].kind {
        @ast.SLet(_, _, init) =>
          match init.kind {
            @ast.ETuple(elems) => assert_eq(elems.length(), 0)
            _ => assert_true(false)
          }
        _ => assert_true(false)
      }
      match body[2].kind {
        @ast.SLet(_, _, init) =>
          match init.kind {
            @ast.ETuple(elems) => assert_eq(elems.length(), 1)
            _ => assert_true(false)
          }
        _ => assert_true(false)
      }
    }
    _ => assert_true(false)
  }
}

///|
test "parenthesized grouping keeps precedence and never becomes a tuple" {
  let r = @parser.parse("fn f() -> Int {\n  (1 + 2) * 3\n}\n")
  assert_eq(r.reports.length(), 0)
  match r.tree.body[0].kind {
    @ast.SFunc(_, _, _, body, _) =>
      match body[0].kind {
        @ast.SExpr(e) => {
          assert_eq(bin_op(e), "*")
          match e.kind {
            @ast.EBin(_, lhs, rhs) => {
              assert_eq(bin_op(lhs), "+")
              match rhs.kind {
                @ast.EInt(n) => assert_eq(n, 3)
                _ => assert_true(false)
              }
            }
            _ => assert_true(false)
          }
        }
        _ => assert_true(false)
      }
    _ => assert_true(false)
  }
}

///|
test "an exclusive range parses as one ERange in loop and let positions" {
  let r = @parser.parse(
    "fn f(n : Int) -> Int {\n  for i in 1..<n {\n    let y = i\n  }\n  let r = a..<b\n  0\n}\n",
  )
  assert_eq(r.reports.length(), 0)
  match r.tree.body[0].kind {
    @ast.SFunc(_, _, _, body, _) => {
      match body[0].kind {
        @ast.SFor(v, _, seq, _) => {
          assert_eq(v, "i")
          match seq.kind {
            @ast.ERange(lo, hi) => {
              match lo.kind {
                @ast.EInt(n) => assert_eq(n, 1)
                _ => assert_true(false)
              }
              match hi.kind {
                @ast.EName(x) => assert_eq(x, "n")
                _ => assert_true(false)
              }
            }
            _ => assert_true(false)
          }
        }
        _ => assert_true(false)
      }
      match body[1].kind {
        @ast.SLet(_, _, init) =>
          match init.kind {
            @ast.ERange(lo, hi) => {
              match lo.kind {
                @ast.EName(x) => assert_eq(x, "a")
                _ => assert_true(false)
              }
              match hi.kind {
                @ast.EName(x) => assert_eq(x, "b")
                _ => assert_true(false)
              }
            }
            _ => assert_true(false)
          }
        _ => assert_true(false)
      }
    }
    _ => assert_true(false)
  }
}

///|
test "a mutable binding parses as the same SLet shape" {
  let r = @parser.parse("fn f() -> Int {\n  let mut x = 1\n  x\n}\n")
  assert_eq(r.reports.length(), 0)
  match r.tree.body[0].kind {
    @ast.SFunc(_, _, _, body, _) =>
      match body[0].kind {
        @ast.SLet(name, ann, init) => {
          assert_eq(name, "x")
          assert_eq(ann, "")
          match init.kind {
            @ast.EInt(n) => assert_eq(n, 1)
            _ => assert_true(false)
          }
        }
        _ => assert_true(false)
      }
    _ => assert_true(false)
  }
}

///|
test "a tuple destructuring let binds each name flat" {
  let r = @parser.parse("fn f(pair) -> Int {\n  let (a, b) = pair\n  a\n}\n")
  assert_eq(r.reports.length(), 0)
  match r.tree.body[0].kind {
    @ast.SFunc(_, _, _, body, _) =>
      match body[0].kind {
        @ast.SLetDestruct(names, init) => {
          assert_eq(names.length(), 2)
          assert_eq(names[0], "a")
          assert_eq(names[1], "b")
          match init.kind {
            @ast.EName(x) => assert_eq(x, "pair")
            _ => assert_true(false)
          }
        }
        _ => assert_true(false)
      }
    _ => assert_true(false)
  }
}

///|
test "a named function inside a block is its own statement kind" {
  let r = @parser.parse(
    "fn outer() -> Int {\n  fn go(k : Int) -> Int {\n    k\n  }\n  go(1)\n}\n",
  )
  assert_eq(r.reports.length(), 0)
  match r.tree.body[0].kind {
    @ast.SFunc(_, _, _, body, _) => {
      match body[0].kind {
        @ast.SLocalFunc(name, params, ret, fnbody, _) => {
          assert_eq(name, "go")
          assert_eq(ret, "Int")
          assert_eq(params.length(), 1)
          assert_eq(params[0].name, "k")
          assert_eq(params[0].tyann, "Int")
          assert_eq(fnbody.length(), 1)
        }
        _ => assert_true(false)
      }
      match body[1].kind {
        @ast.SExpr(e) =>
          match e.kind {
            @ast.ECall(callee, args) => {
              assert_eq(callee, "go")
              assert_eq(args.length(), 1)
            }
            _ => assert_true(false)
          }
        _ => assert_true(false)
      }
    }
    _ => assert_true(false)
  }
}

///|
test "optional and defaulted parameters parse with their annotations kept" {
  let a = @parser.parse("fn f(x? : Int) -> Int {\n  x\n}\n")
  assert_eq(a.reports.length(), 0)
  let b = @parser.parse("fn g(y : Int = 2) -> Int {\n  y\n}\n")
  assert_eq(b.reports.length(), 0)
  let c = @parser.parse("fn h(p : Int, q? : String = \"s\") -> Int {\n  p\n}\n")
  assert_eq(c.reports.length(), 0)
  match a.tree.body[0].kind {
    @ast.SFunc(_, params, _, _, _) => {
      assert_eq(params[0].name, "x")
      assert_eq(params[0].tyann, "Int")
    }
    _ => assert_true(false)
  }
  match b.tree.body[0].kind {
    @ast.SFunc(_, params, _, _, _) => {
      assert_eq(params[0].name, "y")
      assert_eq(params[0].tyann, "Int")
    }
    _ => assert_true(false)
  }
  match c.tree.body[0].kind {
    @ast.SFunc(_, params, _, _, _) => {
      assert_eq(params[1].name, "q")
      assert_eq(params[1].tyann, "String")
    }
    _ => assert_true(false)
  }
}

///|
test "an optional type annotation folds into the annotation string" {
  let a = @parser.parse("fn f() -> Int {\n  let x : Int? = none\n  0\n}\n")
  assert_eq(a.reports.length(), 0)
  let b = @parser.parse("fn g() -> Int? {\n  none\n}\n")
  assert_eq(b.reports.length(), 0)
  match a.tree.body[0].kind {
    @ast.SFunc(_, _, _, body, _) =>
      match body[0].kind {
        @ast.SLet(name, ann, _) => {
          assert_eq(name, "x")
          assert_eq(ann, "Int?")
        }
        _ => assert_true(false)
      }
    _ => assert_true(false)
  }
  match b.tree.body[0].kind {
    @ast.SFunc(_, _, ret, _, _) => assert_eq(ret, "Int?")
    _ => assert_true(false)
  }
}

///|
test "a match expression is skipped whole and yields its scrutinee" {
  let r = @parser.parse(
    "fn f(e) -> Int {\n  let v = match e { Some(x) => x, None => 0 }\n  v\n}\n",
  )
  assert_eq(r.reports.length(), 1)
  assert_true(r.reports[0].message.contains("match expression"))
  assert_eq(r.skips.length(), 1)
  assert_eq(r.first_error, 0)
  match r.tree.body[0].kind {
    @ast.SFunc(_, _, _, body, _) => {
      assert_eq(body.length(), 2)
      match body[0].kind {
        @ast.SLet(_, _, init) =>
          match init.kind {
            @ast.EName(x) => assert_eq(x, "e")
            _ => assert_true(false)
          }
        _ => assert_true(false)
      }
    }
    _ => assert_true(false)
  }
}

///|
test "an anonymous function literal is skipped and its call still parses" {
  let r = @parser.parse(
    "fn f(arr) -> Int {\n  arr.iter(fn(x) {\n    x + 1\n  })\n  0\n}\n",
  )
  assert_eq(r.reports.length(), 1)
  assert_true(r.reports[0].message.contains("anonymous function"))
  assert_eq(r.skips.length(), 1)
  assert_eq(r.first_error, 0)
  match r.tree.body[0].kind {
    @ast.SFunc(_, _, _, body, _) => {
      assert_eq(body.length(), 2)
      match body[0].kind {
        @ast.SExpr(e) =>
          match e.kind {
            @ast.EMethodCall(recv, name, args) => {
              match recv.kind {
                @ast.EName(x) => assert_eq(x, "arr")
                _ => assert_true(false)
              }
              assert_eq(name, "iter")
              assert_eq(args.length(), 1)
              match args[0].kind {
                @ast.EBigInt => assert_true(true)
                _ => assert_true(false)
              }
            }
            _ => assert_true(false)
          }
        _ => assert_true(false)
      }
    }
    _ => assert_true(false)
  }
}

///|
test "a paren-less main parses with empty params and empty return" {
  let r = @parser.parse("fn main {\n  println(\"x\")\n}\n")
  assert_eq(r.reports.length(), 0)
  match r.tree.body[0].kind {
    @ast.SFunc(name, params, ret, body, _) => {
      assert_eq(name, "main")
      assert_eq(params.length(), 0)
      assert_eq(ret, "")
      assert_eq(body.length(), 1)
    }
    _ => assert_true(false)
  }
}

///|
test "an else-if chain parses as one SIf with its else-if list" {
  let r = @parser.parse(
    "fn f(a, b) -> Int {\n  if a {\n    1\n  } else if b {\n    2\n  } else {\n    3\n  }\n}\n",
  )
  assert_eq(r.reports.length(), 0)
  match r.tree.body[0].kind {
    @ast.SFunc(_, _, _, body, _) =>
      match body[0].kind {
        @ast.SIf(cond, then, elseifs, els) => {
          match cond.kind {
            @ast.EName(x) => assert_eq(x, "a")
            _ => assert_true(false)
          }
          assert_eq(then.length(), 1)
          assert_eq(elseifs.length(), 1)
          match elseifs[0].cond.kind {
            @ast.EName(x) => assert_eq(x, "b")
            _ => assert_true(false)
          }
          assert_eq(elseifs[0].body.length(), 1)
          match els {
            Some(b) => assert_eq(b.length(), 1)
            None => assert_true(false)
          }
        }
        _ => assert_true(false)
      }
    _ => assert_true(false)
  }
}

///|
test "a ternary in call-argument position is still outside the subset" {
  let r = @parser.parse("fn f(a, b, c : Int) -> Int {\n  g(a ? b : c)\n}\n")
  assert_true(r.reports.length() > 0)
  assert_true(r.first_error > 0)
}
