///|
/// Lexer-level tests for the block-string closer.
///
/// The closer rule was measured against the toolchain rather than assumed,
/// because the previous rule (`|#`) appears in no real code and so reported
/// "unterminated block string" on anything containing a block string.
///
/// Note what these tests are NOT: they are not a response to a self-scan
/// complaint about src/samples/samples.mbt. That file's marker count was 107,
/// odd, when this rule was written, so its last block really did run to end of
/// input and the report was true at the time; the file has since gained one
/// marker and parses clean. The rule was wrong on the five measured counts
/// below, not because of that report.
///
/// Measured with `moon run`:
///   #|AAA\n#|BBB          -> "AAA\nBBB"           closed, rest of line is content
///   #|AAA\n  #|BBB       -> "AAA\nBBB"           the closer may be indented
///   #|AAA\n#|BBB trailing -> "AAA\nBBB trailing"
///   #|one #|two\n#|three   -> "one #|two\nthree"  a mid-line `#|` is content
///   #|AAA\n|#BBB           -> not closed          `|#` is content
///   #|AAA\n#|BBB\nCCC      -> "AAA\nBBB", and CCC is then parsed as CODE

///|
test "block string closes on a line-leading #| and ends at that line" {
  let (toks, _, reports) = @lexer.lex(
    "fn f() -> int {\n  let s = #|AAA\n#|BBB\n  1\n}\n",
  )
  assert_eq(reports.length(), 0)
  let mut v = "<none>"
  for t in toks {
    match t {
      TStr(s, _) => if s.contains("AAA") { v = s }
      _ => ()
    }
  }
  assert_eq(v, "AAA\nBBB")
}

///|
/// The `\n` after the closing `#|` belongs to the code, not to the string, and
/// the lines after it keep counting from where the block ended.
test "block string value and line counter" {
  let (toks, spans, reports) = @lexer.lex(
    "fn f() -> int {\n  let s = #|AAA\nBB\n#|\n  1\n}\n",
  )
  assert_eq(reports.length(), 0)
  let mut v = "<none>"
  for t in toks {
    match t {
      TStr(s, _) => if s.contains("AAA") { v = s }
      _ => ()
    }
  }
  assert_eq(v, "AAA\nBB\n")
  assert_eq(spans.length(), toks.length())
}

///|
/// `|#` does not close, so the block runs to end of input and is reported.
test "|# does not close a block string" {
  let (_, _, reports) = @lexer.lex("fn f() -> int {\n  let s = #|AAA\n  1\n}\n")
  assert_eq(reports.length(), 1)
  assert_true(reports[0].message.contains("unterminated block string"))
}

///|
/// A mid-line `#|` is ordinary content; only a line-leading one closes.
test "a mid-line #| does not close" {
  let (toks, _, _) = @lexer.lex("let s = #|one #|two\n#|three\n")
  let mut v = ""
  for t in toks {
    match t {
      TStr(s, _) => v = s
      _ => ()
    }
  }
  assert_eq(v, "one #|two\nthree")
}

// --- integer literals -------------------------------------------------------
//
// Every form below was compiled by this toolchain before it was written into
// the lexer. What they protect is not "hex works" but a specific failure: when
// the lexer does not know a form, it splits it into a number plus NAMES, and
// every one of those names is then reported as an unbound binding. That is how
// 54 of the 55 false positives a core scan gained from teaching the parser
// method calls turned out to exist.

///|
/// A `Tok` can be neither compared nor printed: it carries a `Double`, which
/// is not `Eq` or `Debug`, so the enum implements neither trait. Each test
/// therefore reads the one field it is about, and `kind_at` NAMES the
/// constructor when the SHAPE is the thing under test.
fn kind_at(s : String, i? : Int = 0) -> String {
  let (toks, _, _) = @lexer.lex(s)
  match toks[i] {
    TInt(_) => "int"
    TBigInt => "bigint"
    TFloat(_) => "float"
    TName(_) => "name"
    TDot => "dot"
    _ => "other"
  }
}

///|
/// The value of the first token, or -1 when it is not an integer carrying one.
fn int_value(s : String) -> Int {
  let (toks, _, _) = @lexer.lex(s)
  match toks[0] {
    TInt(v) => v
    _ => -1
  }
}

///|
fn name_at(s : String, i : Int) -> String {
  let (toks, _, _) = @lexer.lex(s)
  match toks[i] {
    TName(n) => n
    _ => "<not a name>"
  }
}

///|
/// How many NAME tokens the source produces. This is the invariant that
/// matters: a literal the lexer does not understand does not fail, it SPLITS,
/// and every fragment it leaves behind is then reported as an unbound binding.
/// Token counts are deliberately not asserted 鈥?they are an implementation
/// detail, and a whitespace change would make the test lie about the bug.
fn count_names(s : String) -> Int {
  let (toks, _, _) = @lexer.lex(s)
  let mut n = 0
  for t in toks {
    match t {
      TName(_) => n += 1
      _ => ()
    }
  }
  n
}

///|
test "hex, binary and octal all carry their value" {
  assert_eq(int_value("0xFF"), 255)
  assert_eq(int_value("0b1010"), 10)
  assert_eq(int_value("0o17"), 15)
  assert_eq(int_value("1_000_000"), 1000000)
  assert_eq(int_value("0x1F_"), 31)
  assert_eq(int_value("0X10"), 16)
}

///|
/// The base prefix needs a digit of that base IMMEDIATELY after it. The
/// toolchain agrees: `0x_1F` does not compile, and reading the `_` as the first
/// digit would accept a literal the compiler rejects. A leading `0` followed
/// by a variable named `x` is the other side of the same rule 鈥?the variable
/// must survive, which it does not if `0x` is taken as a prefix.
test "a base prefix needs a digit immediately after it" {
  assert_eq(count_names("0x1F_"), 0)
  // `0x_1F` is not hex: it is the number 0 and the name x_1F, which is the
  // same reading the compiler's rejection implies.
  assert_eq(kind_at("0x_1F"), "int")
  assert_eq(int_value("0x_1F"), 0)
  assert_eq(count_names("0 x"), 1)
  assert_eq(name_at("0 x", 1), "x")
}

///|
/// The bound is fixed, not the target's `Int`, so the same source gives the
/// same answer on wasm and on js. Past it the literal still lexes 鈥?it just
/// carries no value, which is what stops a dead branch being folded on a
/// number the analyzer could not read.
test "a literal past the bound carries no value but still lexes" {
  assert_eq(kind_at("0x8000_0000"), "bigint")
  assert_eq(kind_at("99999999999999"), "bigint")
  // Past the bound is not a licence to split. Two names: `let` and `x`.
  assert_eq(count_names("let x = 0x8000_0000\n"), 2)
}

///|
test "the L, U and UL suffixes are consumed, not read as names" {
  assert_eq(kind_at("0x1000L"), "bigint")
  assert_eq(kind_at("1U"), "bigint")
  assert_eq(kind_at("0xffffffffUL"), "bigint")
  // This is the exact shape that used to yield `no visible binding for 'UL'`.
  assert_eq(count_names("0xffffffffUL\n"), 0)
  let (_, spans, _) = @lexer.lex("0xffffffffUL\n")
  // 12 characters from column 1, so the span ends at column 13 鈥?the suffix
  // is inside the token, not trailing past it.
  assert_eq(spans[0].end.col, 13)
}

///|
/// And the other way: a real hex literal must NOT leak a name. `0x8000` is
/// 32768, comfortably INSIDE the bound, so this also pins that an in-range hex
/// literal is a plain integer with a value rather than a valueless one.
test "a real hex literal leaks no name" {
  assert_eq(count_names("0x8000\n"), 0)
  assert_eq(kind_at("0x8000"), "int")
  assert_eq(int_value("0x8000"), 32768)
}

///|
/// A `.` after a digit is a decimal point only when a fraction digit follows.
/// The toolchain rejects `1.to_string()`, so this is a guard against reading
/// a stray `.` as a float rather than a claim that the form is valid.
test "a dot that is not followed by a digit does not make a float" {
  assert_eq(kind_at("1.x"), "int")
  assert_eq(count_names("1.x"), 1)
}

///|
test "a float still lexes as a float" {
  assert_eq(kind_at("3.5"), "float")
  assert_eq(kind_at("0.25"), "float")
  assert_eq(kind_at("1_000.5"), "float")
  assert_eq(count_names("3.5\n"), 0)
}

// --- the `?`, `..<` and char-literal tokens ---------------------------------
//
// Same failure class as the integer literals above: a token the lexer does
// not know does not fail, it SPLITS into names that are then reported as
// unbound bindings. `T?`, `x? : T`, `a..<b` and char literals are real
// MoonBit, so each must lex as its own token.

///|
fn count_question(s : String) -> Int {
  let (toks, _, _) = @lexer.lex(s)
  let mut n = 0
  for t in toks {
    match t {
      TQuestion => n += 1
      _ => ()
    }
  }
  n
}

///|
fn count_range(s : String) -> Int {
  let (toks, _, _) = @lexer.lex(s)
  let mut n = 0
  for t in toks {
    match t {
      TRange => n += 1
      _ => ()
    }
  }
  n
}

///|
fn count_dots(s : String) -> Int {
  let (toks, _, _) = @lexer.lex(s)
  let mut n = 0
  for t in toks {
    match t {
      TDot => n += 1
      _ => ()
    }
  }
  n
}

///|
/// The string payload of token `i`, or a sentinel when it is not a string.
fn str_at(s : String, i : Int) -> String {
  let (toks, _, _) = @lexer.lex(s)
  match toks[i] {
    TStr(v, _) => v
    _ => "<not a str>"
  }
}

///|
test "the question mark lexes as one token in both annotation positions" {
  assert_eq(count_question("?"), 1)
  assert_eq(count_question("let x : Int? = none\n"), 1)
  assert_eq(count_question("fn f(x? : Int) -> Int {\n  x\n}\n"), 1)
  // and it is not invented where none was written
  assert_eq(count_question("let x = 1\n"), 0)
}

///|
test "an exclusive range is one token, its siblings are dot pairs" {
  assert_eq(count_range("a ..< b\n"), 1)
  assert_eq(count_dots("a ..< b\n"), 0)
  // `..` and `..=` are not modelled: they stay two dots each
  assert_eq(count_range("a..b\n"), 0)
  assert_eq(count_dots("a..b\n"), 2)
  assert_eq(count_range("a ..= b\n"), 0)
  assert_eq(count_dots("a ..= b\n"), 2)
}

///|
test "a char literal is a string holding one character" {
  assert_eq(str_at("'x'", 0), "x")
  // the escapes map to the character they name
  assert_eq(str_at("'\\n'", 0), "\n")
  assert_eq(str_at("'\\t'", 0), "\t")
  assert_eq(str_at("'\\r'", 0), "\r")
  // any other escaped character maps to ITSELF, which is what keeps `'\''`
  // and `'\\'` from producing an empty payload or eating the closer
  assert_eq(str_at("'\\''", 0), "'")
  assert_eq(str_at("'\\\\'", 0), "\\")
}

///|
test "a char literal holding two characters is reported but still emitted" {
  let (toks, _, reports) = @lexer.lex("'ab'\n")
  assert_eq(reports.length(), 1)
  assert_true(
    reports[0].message.contains(
      "character literal must hold exactly one character",
    ),
  )
  // the payload still reaches the parser as a string, so the parser sees the
  // same token stream it would have seen without the rule
  let mut v = "<none>"
  for t in toks {
    match t {
      TStr(s, _) => v = s
      _ => ()
    }
  }
  assert_eq(v, "ab")
  // and it carries NO interpolated names: a character literal has no `\{...}`
  // to read, so the second field must be empty rather than defaulted to
  // something that would resolve names that are not there
  for t in toks {
    match t {
      TStr(_, names) => assert_eq(names.length(), 0)
      _ => ()
    }
  }
}

///|
test "an unterminated char literal is reported and does not swallow the newline" {
  let (toks, spans, reports) = @lexer.lex("'x\ny\n")
  assert_eq(reports.length(), 1)
  assert_true(reports[0].message.contains("unterminated character literal"))
  // the newline is NOT consumed by the literal: two newlines are still
  // emitted, and the name after the first sits on line 2. A swallowed
  // newline would shift every statement after the literal onto one line.
  let mut found = false
  let mut newlines = 0
  for i in 0..<toks.length() {
    match toks[i] {
      TName(n) =>
        if n == "y" {
          found = true
          assert_eq(spans[i].start.line, 2)
        }
      TNewline => newlines += 1
      _ => ()
    }
  }
  assert_true(found)
  assert_eq(newlines, 2)
}
