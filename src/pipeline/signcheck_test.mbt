// The deck's two applications, on the deck's own example.
//
// THE EXAMPLE IS THE DECK'S. `Introduction` (Yue Li, Nanjing University)
// p.56-58 prints one program and asks for the sign of every variable in it:
//
//     x = 10;  y = -1;  z = 0;
//     a = x + y;   -> ⊤   (+ ⊕ - = ⊤, the deck's own row)
//     b = z / y;   -> O   (O / - = O, the deck's own row)
//     c = a / b;   -> ⊥   (T / O = ⊥ -- THE DIVISION BY ZERO)
//     p = arr[y];  -> the index is -: THE NEGATIVE INDEX
//     q = arr[a];  -> the index is ⊤: nothing to say
//
// so the example's answer is TWO findings, in two different families, and the
// third subscript is the CONTROL: an index the analysis cannot pin down is
// not reported, and a reader who cannot see that in the same program cannot
// tell a rule from a coincidence.
//
// THE TOOLCHAIN IS THE ORACLE, AND IT SAYS NOTHING. Measured against
// `moon check` on a probe holding all five shapes -- `1 / 0`, `10 / y`,
// `arr[-1]`, `arr[0 - 1]`, `arr[0]` -- the compiler exits 0. So a finding here
// is not a duplicate of the compiler's: it is the only thing in the toolchain
// that says it.

///|
/// The unread regions the frontend declared, for a source.
fn unread_of_sign(src : String) -> Array[@core.Span] {
  let out : Array[@core.Span] = []
  let p = @parser.parse(src)
  for r in p.reports {
    if r.family == @core.FParse &&
      r.message.contains("outside the analyzed subset") {
      out.push(r.span)
    }
  }
  out
}

///|
fn sign_of(src : String) -> Array[@report.Report] {
  @pipeline.sign_findings(@parser.parse(src).tree.body, unread_of_sign(src))
}

///|
fn count0571(reps : Array[@report.Report], f : @core.Family) -> Int32 {
  let mut n = 0
  for r in reps {
    if r.family == f {
      n = n + 1
    }
  }
  n
}

///|
/// The line the family fired on, or 0.
fn line_of(reps : Array[@report.Report], f : @core.Family) -> Int32 {
  for r in reps {
    if r.family == f {
      return r.span.start.line
    }
  }
  0
}

///|
/// THE DECK'S EXAMPLE, END TO END.
test "0571: the deck's example reports the division by zero and the negative index" {
  let src = "fn f() -> int {\n" +
    "  let arr = [1, 2, 3]\n" +
    "  let x = 10\n" +
    "  let y = -1\n" +
    "  let z = 0\n" +
    "  let a = x + y\n" +
    "  let b = z / y\n" +
    "  let c = a / b\n" +
    "  let p = arr[y]\n" +
    "  let q = arr[a]\n" +
    "  c + p + q\n" +
    "}\n"
  let reps = sign_of(src)
  // EXACTLY TWO, and they are the two the deck's slide names.
  assert_eq(count0571(reps, @core.FDivisionByZero), 1)
  assert_eq(count0571(reps, @core.FNegativeIndex), 1)
  assert_eq(reps.length(), 2)
  // ON THE LINES THEY CLAIM: `let c = a / b` is line 8 and `let p = arr[y]`
  // is line 9. The subscript on line 10 -- `arr[a]`, whose index is unknown --
  // is NOT reported, and that is the control the whole family rests on.
  assert_eq(line_of(reps, @core.FDivisionByZero), 8)
  assert_eq(line_of(reps, @core.FNegativeIndex), 9)
  // AND THE MESSAGES NAME THE OPERAND they are about.
  for r in reps {
    if r.family == @core.FDivisionByZero {
      assert_true(r.message.contains("'b'"))
    }
    if r.family == @core.FNegativeIndex {
      assert_true(r.message.contains("'y'"))
    }
  }
}

///|
/// THE CONTROL FOR THE WHOLE FAMILY: an operand whose sign the analysis
/// cannot pin down is not reported.
test "0571: an unknown divisor and an unknown index are not reported" {
  let src = "fn f(x: int, y: int, arr: array) -> int {\n  let d = x / y\n  let p = arr[y]\n  d + p\n}\n"
  let reps = sign_of(src)
  assert_eq(reps.length(), 0)
}

///|
/// A LITERAL zero divisor, and a literal negative index: the two shapes the
/// compiler does not catch.
test "0571: a literal zero divisor and a literal negative index are reported" {
  let src = "fn f(arr: array) -> int {\n  let d = 10 / 0\n  let p = arr[-1]\n  d + p\n}\n"
  let reps = sign_of(src)
  assert_eq(count0571(reps, @core.FDivisionByZero), 1)
  assert_eq(count0571(reps, @core.FNegativeIndex), 1)
  assert_eq(line_of(reps, @core.FDivisionByZero), 2)
  assert_eq(line_of(reps, @core.FNegativeIndex), 3)
}

///|
/// THE JOIN IS WHAT MAKES THE "ONLY ON ONE PATH" CASE SILENT. A divisor that
/// is zero on one path and not on the other is joined to UNKNOWN, and an
/// unknown divisor is not a finding -- because the division does not fail on
/// the other path, and a finding that says "this division fails" must be true
/// on every path.
test "0571: a divisor that is zero on one path only is not reported" {
  let src = "fn f(c: bool) -> int {\n" +
    "  let mut d = 0\n" +
    "  if c {\n" +
    "    d = 1\n" +
    "  }\n" +
    "  let q = 10 / d\n" +
    "  q\n" +
    "}\n"
  assert_eq(sign_of(src).length(), 0)
}

///|
/// The other half of the same rule: a divisor that is zero on EVERY path IS
/// reported, so the join does not silence the family into uselessness.
test "0571: a divisor that is zero on every path is reported" {
  let src = "fn f(c: bool) -> int {\n" +
    "  let mut d = 0\n" +
    "  if c {\n" +
    "    d = 0\n" +
    "  }\n" +
    "  let q = 10 / d\n" +
    "  q\n" +
    "}\n"
  let reps = sign_of(src)
  assert_eq(count0571(reps, @core.FDivisionByZero), 1)
  assert_eq(line_of(reps, @core.FDivisionByZero), 6)
}

///|
/// THE REMAINDER FAILS THE SAME WAY. The deck names the division; `%` is the
/// same runtime failure, and the claim is the same one.
test "0571: a remainder by zero is reported under the same claim" {
  let src = "fn f() -> int {\n  let r = 10 % 0\n  r\n}\n"
  let reps = sign_of(src)
  assert_eq(count0571(reps, @core.FDivisionByZero), 1)
  assert_eq(line_of(reps, @core.FDivisionByZero), 2)
}

///|
/// A COMPUTED divisor: `d - d` is zero, and the sign domain cannot see it
/// (`+ ⊕ -` is unknown), so it is NOT reported. This is the imprecision the
/// domain accepts, and it is in the SAFE direction: the division is not
/// reported, rather than reported wrongly.
test "0571: a computed zero divisor is not reported, and that is the safe direction" {
  let src = "fn f(d: int) -> int {\n  let q = 10 / (d - d)\n  q\n}\n"
  assert_eq(sign_of(src).length(), 0)
}

///|
/// BUT A SIGN THE DOMAIN CAN SEE IS REPORTED: `0 - 1` is negative, and a
/// negative index is out of bounds.
test "0571: an index the domain can compute is reported" {
  let src = "fn f(arr: array) -> int {\n  let p = arr[0 - 1]\n  p\n}\n"
  let reps = sign_of(src)
  assert_eq(count0571(reps, @core.FNegativeIndex), 1)
  assert_eq(line_of(reps, @core.FNegativeIndex), 2)
}

///|
/// THE FUNCTION-LEVEL GUARDS ARE THE DEAD-STORE FAMILY'S. A region the
/// frontend did not read is a path the analysis never had, so the function is
/// not analysed -- and the CONTROL proves the rule is not just silence: the
/// same program with the region written as a STATEMENT reports.
test "0571: a function holding an unread region is not analysed" {
  let hidden = "fn f() -> int {\n  let w = if true { 2 } else { 3 }\n  let q = 10 / 0\n  w + q\n}\n"
  assert_eq(sign_of(hidden).length(), 0)
  let shown = "fn f() -> int {\n  var w = 0\n  if true {\n    w = 2\n  } else {\n    w = 3\n  }\n  let q = 10 / 0\n  w + q\n}\n"
  let reps = sign_of(shown)
  assert_eq(count0571(reps, @core.FDivisionByZero), 1)
}

///|
/// AND THE GRAPH'S OWN LIMIT: a block used as a VALUE holds statements the
/// graph never turned into nodes, so a name such a block assigns would still
/// carry its old value -- and the family declines the whole function rather
/// than report against a state that can be stale.
test "0571: a function holding a block used as a value is not analysed" {
  let src = "fn f() -> int {\n" +
    "  let mut d = 0\n" +
    "  let w = { d = 5; 1 }\n" +
    "  let q = 10 / d\n" +
    "  w + q\n" +
    "}\n"
  assert_eq(sign_of(src).length(), 0)
}

///|
/// THE FLOAT GUARD, and the measurement behind it.
///
/// Settled against the toolchain: `1 / 0` and `1 % 0` raise a RuntimeError,
/// while `1.0 / 0` is Infinity and `1.0 % 0` is NaN. A float division by zero
/// is IEEE arithmetic, not a crash, so the family must not claim it is one.
/// The divisor is an integer literal zero and the NUMERATOR decides the
/// operation's type, so the guard is on the numerator.
test "0571: a float division by zero is not reported, and an integer one is" {
  let flt = "fn f() -> int {\n  let r = 1.0 % 0\n  0\n}\n"
  assert_eq(sign_of(flt).length(), 0)
  let flt2 = "fn f() -> int {\n  let r = 1.0 / 0\n  0\n}\n"
  assert_eq(sign_of(flt2).length(), 0)
  let int = "fn f() -> int {\n  let r = 1 % 0\n  0\n}\n"
  let reps = sign_of(int)
  assert_eq(count0571(reps, @core.FDivisionByZero), 1)
  assert_eq(line_of(reps, @core.FDivisionByZero), 2)
}

///|
/// THE PREDICATE. The claim is about an OPERAND, and the operand is named
/// when it is a name: a checker can re-ask the one question the analyzer
/// answered.
test "0571: the predicate names the operand the finding is about" {
  let src = "fn f() -> int {\n  let d = 0\n  let q = 10 / d\n  q\n}\n"
  let reps = sign_of(src)
  assert_eq(reps.length(), 1)
  let p = reps[0].predicate()
  assert_true(p is Some(_))
  match p {
    Some(pr) => assert_eq(pr.check, "divisor_definitely_zero")
    None => ()
  }
}
