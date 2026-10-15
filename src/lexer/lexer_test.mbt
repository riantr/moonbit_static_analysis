///|
/// Lexer-level tests for the block-string closer.
///
/// EVERY expectation below is the toolchain's own VALUE, measured by
/// `_verify/settle_0446_block_string.ps1` running each shape through `moon run`
/// and printing the variable. That is the only instrument that works here:
/// `moon check` ACCEPTS every shape of this construct, so acceptance cannot
/// distinguish one rule from another -- it says only "this lexes".
///
/// WHAT THESE TESTS USED TO ASSERT, and why it moved. The rule they pinned was
/// "the closer is a `#|` with only whitespace BEFORE it on its line", and it
/// listed `#|AAA\n#|BBB trailing -> "AAA\nBBB trailing"` among its measurements.
/// That is false: the trailing text is CONTENT and the string carries on. Under
/// the old rule EVERY line-leading `#|` closed, so markers paired as
/// opener/closer alternately, and an ODD count ran to end of input and was
/// reported "unterminated" -- a finding the toolchain does not make, on valid
/// MoonBit. proton 0.3.4 `facade_types.mbt` is written that way, and three
/// findings in three other files came from that file being cut at line 246 while
/// the enum declaring the names they used sat at 589.
///
/// The VALUE moved too. Segments are trimmed and joined by a single SPACE, never
/// by newlines: "AAA\nBBB" was never the string, under either rule.
///

///|
/// THE CLOSER, and the one shape this is really about: a `#|` whose REST OF LINE
/// IS BLANK. It contributes an empty final segment, which is why every closed
/// value ends in a space and no end-of-input one does.
test "block string: a bare #| closes and contributes an empty segment" {
  let (toks, _, reports) = @lexer.lex("let s = #|AAA\n#|BBB\n#|\n")
  assert_eq(reports.length(), 0)
  let mut v = "<none>"
  for t in toks {
    match t {
      TStr(s, _) => if s.contains("AAA") { v = s }
      _ => ()
    }
  }
  assert_eq(v, "AAA BBB ")
}

///|
/// THE CASE THE OLD RULE GOT WRONG. Trailing text makes the `#|` a CONTENT LINE,
/// not a closer, and the string runs on to the next one. The old expectation
/// here was "AAA\nBBB trailing" -- that is the claim this section exists to
/// correct, and `trailing` in the settle is the measurement that corrects it.
test "block string: a #| with text after it is a content line" {
  let (toks, _, reports) = @lexer.lex("let s = #|AAA\n#|BBB trailing\n#|\n")
  assert_eq(reports.length(), 0)
  let mut v = "<none>"
  for t in toks {
    match t {
      TStr(s, _) => if s.contains("AAA") { v = s }
      _ => ()
    }
  }
  assert_eq(v, "AAA BBB trailing ")
}

///|
/// A line whose first NON-BLANK character is not `#|` ENDS the block, and the
/// toolchain does not call that unterminated: in `#|abc` / `plain` / `#|`,
/// `plain` comes back as an unbound identifier (4021), so it is CODE, and the
/// trailing `#|` is a second string expression (4139).
///
/// This is also the shape the old tests used by accident -- their `  1` tail was
/// never string content, it was code -- which is why their expected values
/// contained text that had no business being inside the string at all.
test "block string: a non-blank line without #| ends the block, as code" {
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
  assert_eq(v, "AAA BBB")
}

///|
/// A BLANK line does NOT end it. Measured: `#|abc` / <blank> / `#|def` / `#|`
/// is "abc def ", and so is the same shape with a whitespace-only line. Without
/// this, the rule above would fire on every blank line inside a block.
test "block string: a blank line inside the block does not end it" {
  let (toks, _, reports) = @lexer.lex("let s = #|abc\n\n  \n#|def\n#|\n")
  assert_eq(reports.length(), 0)
  let mut v = "<none>"
  for t in toks {
    match t {
      TStr(s, _) => if s.contains("abc") { v = s }
      _ => ()
    }
  }
  assert_eq(v, "abc def ")
}

///|
/// THE CLOSER MAY BE INDENTED, and this test exists because it was MISSING.
///
/// Seven tests were written for this construct in 0.4.36 and every one of them put
/// the closer at column 0 -- because they were written by copying each other. Gate
/// 0446's M2 tightens the closer to column 0 and only ONE test in the suite went
/// red: an unrelated block-string test that had happened to indent its markers.
/// The rule was therefore pinned by accident, and an accident is not a guard.
///
/// The toolchain is unambiguous here (`blank_closer` in the settle), and so is the
/// old header it replaces, which claimed the indented closer worked while getting
/// everything else about the rule wrong. Indentation of the closer is the one part
/// of that header that was RIGHT.
test "block string: an indented #| still closes" {
  let (toks, _, reports) = @lexer.lex("let s =\n  #|abc\n  #|def\n  #|\n")
  assert_eq(reports.length(), 0)
  let mut v = "<none>"
  for t in toks {
    match t {
      TStr(s, _) => if s.contains("abc") { v = s }
      _ => ()
    }
  }
  assert_eq(v, "abc def ")
}

///|
/// AND WITH TRAILING BLANKS AFTER THE MARKER, which is the case that says "rest of
/// line is blank" rather than "rest of line is empty".
test "block string: a #| followed only by blanks still closes" {
  let (toks, _, reports) = @lexer.lex("let s =\n  #|abc\n  #|def\n  #|   \n")
  assert_eq(reports.length(), 0)
  let mut v = "<none>"
  for t in toks {
    match t {
      TStr(s, _) => if s.contains("abc") { v = s }
      _ => ()
    }
  }
  assert_eq(v, "abc def ")
}

///|
/// The `\n` after the closing `#|` belongs to the code, not to the string, and
/// the lines after it keep counting from where the block ended.
test "block string value and line counter" {
  let (toks, spans, reports) = @lexer.lex(
    "fn f() -> int {\n  let s = #|AAA\n#|\n  1\n}\n",
  )
  assert_eq(reports.length(), 0)
  let mut v = "<none>"
  for t in toks {
    match t {
      TStr(s, _) => if s.contains("AAA") { v = s }
      _ => ()
    }
  }
  assert_eq(v, "AAA ")
  assert_eq(spans.length(), toks.length())
}

///|
/// End of input closes the block too -- the toolchain tolerates it and the value
/// carries no trailing empty segment -- but the file is STILL reported, because
/// whatever followed the last `#|` was never lexed, so every span past it would
/// be wrong. That report is this test's whole subject.
test "a block string with no closer is reported, and spans stay consistent" {
  let (toks, spans, reports) = @lexer.lex("let s = #|AAA\n")
  assert_eq(reports.length(), 1)
  assert_true(reports[0].message.contains("unterminated block string"))
  assert_eq(spans.length(), toks.length())
}

///|
/// A mid-line `#|` is ordinary content. Measured: `#|one #|two` / `#|three` is
/// "one #|two three" -- joined by a space, because the `#|three` line is a
/// content segment and no closer ever arrives.
test "a mid-line #| is content" {
  let (toks, _, _) = @lexer.lex("let s = #|one #|two\n#|three\n")
  let mut v = ""
  for t in toks {
    match t {
      TStr(s, _) => v = s
      _ => ()
    }
  }
  assert_eq(v, "one #|two three")
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
fn kind_at(s : String, i~ : Int32 = 0) -> String {
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
fn int_value(s : String) -> Int32 {
  let (toks, _, _) = @lexer.lex(s)
  match toks[0] {
    TInt(v) => v
    _ => -1
  }
}

///|
fn name_at(s : String, i : Int32) -> String {
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
fn count_names(s : String) -> Int32 {
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
fn count_question(s : String) -> Int32 {
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
fn count_range(s : String) -> Int32 {
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
fn count_dots(s : String) -> Int32 {
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
fn str_at(s : String, i : Int32) -> String {
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
