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
test "package sources carry no imports" {
  let r = @parser.parse("fn f() -> int {\n  1\n}\n")
  assert_eq(r.reports.length(), 0)
  assert_eq(r.tree.imports.length(), 0)
}
