///|
/// Numbers, read as VALUES rather than as token kinds.
///
/// Every one of these exists because the lexer previously sliced a float
/// literal to its integer part: `slice(start, int_part)` where `int_part` was
/// captured BEFORE the fraction was consumed. So `1.5` folded to 1, `0.25` to
/// 0, `3.14159` to 3. Every pre-existing float test only checked that the token
/// KIND was `float`, which is true of a truncated value too — the whole class
/// of bug was invisible to the suite.
fn fval(s : String) -> Double {
  let (toks, _, _) = @lexer.lex(s)
  match toks[0] {
    TFloat(v) => v
    _ => -1.0e9
  }
}

///|
fn kind(s : String) -> String {
  let (toks, _, _) = @lexer.lex(s)
  match toks[0] {
    TInt(_) => "int"
    TBigInt => "bigint"
    TFloat(_) => "float"
    TName(n) => "name:" + n
    TDot => "dot"
    _ => "other"
  }
}

///|
/// Token count EXCLUDING the `TEOF` that `lex` always appends. Measured, not
/// assumed: the first version of this file forgot the EOF and every count came
/// out one high, which reads exactly like a lexer that refuses to merge tokens.
fn ntok(s : String) -> Int32 {
  let (toks, _, _) = @lexer.lex(s)
  let mut n = toks.length()
  match toks[n - 1] {
    TEOF => n -= 1
    _ => ()
  }
  n
}

///|
test "float VALUE: a fraction survives, it is not truncated to the integer part" {
  assert_true(fval("1.5") > 1.49 && fval("1.5") < 1.51)
  assert_true(fval("0.25") > 0.24 && fval("0.25") < 0.26)
  assert_true(fval("3.14159") > 3.14 && fval("3.14159") < 3.15)
  assert_true(fval("2.0") > 1.99 && fval("2.0") < 2.01)
}

///|
/// NEGATIVE CONTROL for the test above. If the helper could not read a float at
/// all it would return the sentinel `-1.0e9`, which would make the assertions
/// pass for the WRONG reason. These pin the sentinel as unreachable.
test "float helper sentinel is not mistaken for a real value" {
  assert_true(fval("nope") < -1.0e8)
  // And a genuine sentinel-valued input is distinguishable by kind.
  assert_true(kind("nope") == "name:nope")
}

///|
/// NEGATIVE CONTROL for integer values: reading only the KIND would let a
/// lexer that folds every integer to 0 pass. This pins real magnitude.
test "int VALUE: magnitude survives" {
  let (toks, _, _) = @lexer.lex("1234")
  match toks[0] {
    TInt(v) => assert_true(v == 1234)
    _ => assert_true(false)
  }
  let (t2, _, _) = @lexer.lex("7")
  match t2[0] {
    TInt(v) => assert_true(v == 7)
    _ => assert_true(false)
  }
}

///|
/// Exponent notation is part of the literal. Before this, `1.0e-12` lexed as
/// the float `1.0` followed by the NAME `e`, which is what produced 13
/// `undefined name 'e'` findings on riantr/moonbit_doubleML.
test "exponent literal is ONE token, not a float plus a name" {
  assert_true(ntok("1.0e-12") == 1)
  assert_true(kind("1.0e-12") == "float")
  assert_true(fval("1.0e-12") > 0.0 && fval("1.0e-12") < 1.0e-10)
}

///|
/// A signed exponent and an integer-mantissa exponent, both of which appear in
/// real code (`1.0e-300` was the `undefined name 'e300'` finding).
test "signed and integer-mantissa exponents" {
  assert_true(ntok("1.0e-300") == 1)
  assert_true(fval("1.0e-300") > 0.0 && fval("1.0e-300") < 1.0e-299)
  assert_true(ntok("2e8") == 1)
  assert_true(fval("2e8") > 1.9e8 && fval("2e8") < 2.1e8)
  assert_true(ntok("1.5E+3") == 1)
  assert_true(fval("1.5E+3") > 1499.0 && fval("1.5E+3") < 1501.0)
}

///|
/// NEGATIVE CONTROL for the exponent rule. An `e` NOT followed by digits is an
/// identifier, and the literal must stop before it. Without this, a lexer that
/// swallowed any trailing `e` would pass every test above.
test "an `e` with no digits after it is NOT part of the literal" {
  assert_true(ntok("1.0echo") == 2)
  assert_true(kind("1.0echo") == "float")
  // Field access on a float: `1.0.exp` style must not eat the name.
  assert_true(ntok("1.0e") == 2)
}

///|
/// `0.0F` is a float32 literal (28 `undefined name 'F'` findings on
/// riantr/snn_mbt came from this being lexed as `0.0` plus the name `F`).
test "F-suffixed float literal is ONE token" {
  assert_true(ntok("0.0F") == 1)
  assert_true(kind("0.0F") == "float")
  assert_true(fval("0.0F") > -0.001 && fval("0.0F") < 0.001)
  assert_true(ntok("1.5F") == 1)
  assert_true(fval("1.5F") > 1.49 && fval("1.5F") < 1.51)
}

///|
/// The suffix works inside a list literal, which is where snn_mbt uses it
/// (`let mut frac = 0.0F`, `[1.0F, 2.0F]`).
test "F suffix inside a list literal" {
  let (toks, _, _) = @lexer.lex("[1.0F, 2.0F]")
  let mut floats = 0
  let mut names = 0
  for t in toks {
    match t {
      TFloat(_) => floats += 1
      TName(_) => names += 1
      _ => ()
    }
  }
  assert_true(floats == 2)
  assert_true(names == 0)
}

///|
/// NEGATIVE CONTROL for the F suffix: `7F` is a PARSE ERROR in MoonBit (verified
/// with `moon run`), so the lexer must NOT consume the `F` off a bare integer.
/// If it did, `7F` would silently read as the number 7 and this fails.
test "F is NOT consumed off a bare integer literal" {
  assert_true(ntok("7F") == 2)
  assert_true(kind("7F") == "int")
}

///|
/// Underscores inside a float literal, and the field-access guard that must
/// still work now that the slice bound moved.
test "separators in floats, and `1.to_string()` is not a float" {
  assert_true(ntok("1_000.5") == 1)
  assert_true(fval("1_000.5") > 1000.4 && fval("1_000.5") < 1000.6)
  // A `.` not followed by a digit is field access, so the literal is `1`.
  assert_true(ntok("1.to_string()") > 1)
  assert_true(kind("0.foo") == "int")
}
