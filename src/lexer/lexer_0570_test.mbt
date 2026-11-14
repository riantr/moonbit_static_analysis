// test: the 0570 lexer rows -- a HEX FLOAT is ONE literal, and a PACKAGE PATH
// is ONE name.
//
// BOTH ARE THE SAME FAILURE SHAPE, and the shape is the one this project has
// measured again and again: a literal the lexer does not know does not FAIL, it
// SPLITS, and every fragment it leaves behind is then reported as an unbound
// binding.
//
//   0x1.0p54            ->  int 0x1, a field access, and the NAME `p54`
//                          ->  `undefined variable 'p54'`
//   @encoding/utf8      ->  the name `@encoding`, a division, and the NAME
//                          `utf8`
//                          ->  `undefined variable 'utf8'`
//
// The first was measured on moonbitlang/core `math/log_double_nonjs.mbt:131`
// and `:216` and on twelve more sites that the 0.4.46 census had DEMOTED
// rather than fixed. The second was measured on the same corpus's
// `archive/zip/writer.mbt:194` and `archive/zip/stream_writer.mbt:149`.
//
// The VALUES in this file were printed by the toolchain itself (moon
// 0.1.20261104, 940aa18), one form per package, and they are the numbers the
// analyzer has to agree with -- not numbers derived from the algorithm that
// reads them, which would only prove the algorithm agrees with itself.

///|
/// The kind of the first token: "int", "float", "bigint", "name" or "other".
fn kind0570(s : String) -> String {
  let (toks, _, _) = @lexer.lex(s)
  match toks[0] {
    TInt(_) => "int"
    TBigInt => "bigint"
    TFloat(_) => "float"
    TName(_) => "name"
    _ => "other"
  }
}

///|
/// The value of the first token when it is a float, and -1.0 otherwise.
fn float0570(s : String) -> Double {
  let (toks, _, _) = @lexer.lex(s)
  match toks[0] {
    TFloat(f) => f
    _ => -1.0
  }
}

///|
/// How many NAME tokens the source produces. This is the invariant that
/// matters: a literal the lexer does not understand leaves fragments behind,
/// and every fragment is then reported as an unbound binding.
fn names0570(s : String) -> Int32 {
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
/// The text of the n-th NAME token, or "" when there is no such token.
fn name0570(s : String, i : Int32) -> String {
  let (toks, _, _) = @lexer.lex(s)
  let mut n = 0
  for t in toks {
    match t {
      TName(x) => {
        if n == i {
          return x
        }
        n += 1
      }
      _ => ()
    }
  }
  ""
}

///|
/// A HEX FLOAT IS ONE LITERAL. The value is the one the toolchain printed for
/// `let a = 0x1.0p54` -- 18014398509481984, which is 2^54 -- and the name count
/// is the invariant: before the fix the literal left `p54` behind.
test "0570: a hex float is one literal and leaks no name" {
  assert_eq(kind0570("0x1.0p54"), "float")
  assert_eq(names0570("0x1.0p54\n"), 0)
  assert_eq(float0570("0x1.0p54"), 18014398509481984.0)
}

///|
/// THE OTHER FORMS, each with the value the toolchain printed beside it. The
/// `0x1.8` row is the one that fixes the BOUNDARY: the `p` exponent is
/// OPTIONAL, so a hex fraction alone is already a float.
test "0570: every hex float form carries the value the toolchain printed" {
  assert_eq(float0570("0x1.8p0"), 1.5)
  assert_eq(float0570("0x1.0p-2"), 0.25)
  assert_eq(float0570("0x0.8p1"), 1.0)
  assert_eq(float0570("0x1.0p+0"), 1.0)
  assert_eq(float0570("0x1.0p1023"), 8.98846567431158e+307)
  assert_eq(float0570("0x1.0p-1022"), 2.2250738585072014e-308)
  // The `p` exponent is optional: the toolchain accepts `0x1.8` and prints 1.5.
  assert_eq(float0570("0x1.8"), 1.5)
}

///|
/// THE FOURTEEN-DIGIT MANTISSA, and it is here because it is the case that a
/// single accumulation gets WRONG. `0x1.71547652b82fep+0` is fourteen hex
/// digits -- fifty-six bits -- and a Double holds fifty-three. The value the
/// toolchain printed is 1.4426950408889634, which is the natural log of two to
/// the last bit; an analyzer that folded the mantissa into one Double would be
/// one unit in the last place away, and the difference would be invisible in
/// every finding and present in every number.
test "0570: a hex float wider than a double's mantissa still carries the toolchain's value" {
  assert_eq(float0570("0x1.71547652b82fep+0"), 1.4426950408889634)
}

///|
/// THE CORPUS'S OWN LITERALS, and this is the row that says the fix is worth
/// having. Every one of these is a hex float in
/// `moonbitlang/core 0.1.20261105+65efd5b93`, and every value here was printed
/// by the toolchain for that literal -- the analyzer has to agree with the
/// compiler on the NUMBER, not merely on the shape.
///
/// The widest of them is `0x3.243F6A8885A308CA8A54` -- twenty-one hex digits,
/// eighty-four bits -- and it is the value of pi. It is also the one that a
/// single accumulation gets wrong, and the one the corpus would have carried
/// a wrong number for.
///
///     0x3.243F6A8885A308CA8A54   math/deprecated.mbt:18   3.141592653589793
///     0x1.aa5aa5df25984p-5       math/log.mbt              0.05204517742929496
///     0x1.71547652b82fep+0       math/exp.mbt              1.4426950408889634
///     0x1.c6af84b912394p-5       math/exp.mbt              0.05550361559341535
///     0x1.62e42fefa39efp-1       math/log.mbt              0.6931471805599453
///     0x1.633ce8fb9f87dp9        math/hyperbolic_test.mbt  710.4758600739439
///     0x1.0p-700                 math/hypot.mbt            1.90109156629516e-211
///     0x1.0p700                  math/hypot.mbt            5.260135901548374e+210
///     0x1.8p+52                  math/exp.mbt              6755399441055744
///     0x1.62e42ep6               math/exp.mbt              88.72283172607422
///     0x1.9fe368p6               math/exp.mbt              103.97207641601562
///     0x1.0p24                   math/algebraic.mbt        16777216
///     0x1.0p97                   math/exp.mbt              1.5845632502852868e+29
///     0x1.0p-95                  math/exp.mbt              2.524354896707238e-29
///     0x1.ebfce50fac4f3p-3       math/exp.mbt              0.2402284522445722
///     0x1.62e42ff0c52d6p-1       math/exp.mbt              0.6931471806916203
test "0570: the corpus's own hex floats carry the toolchain's numbers" {
  assert_eq(float0570("0x3.243F6A8885A308CA8A54"), 3.141592653589793)
  assert_eq(float0570("0x1.aa5aa5df25984p-5"), 0.05204517742929496)
  assert_eq(float0570("0x1.71547652b82fep+0"), 1.4426950408889634)
  assert_eq(float0570("0x1.c6af84b912394p-5"), 0.05550361559341535)
  assert_eq(float0570("0x1.62e42fefa39efp-1"), 0.6931471805599453)
  assert_eq(float0570("0x1.633ce8fb9f87dp9"), 710.4758600739439)
  assert_eq(float0570("0x1.0p-700"), 1.90109156629516e-211)
  assert_eq(float0570("0x1.0p700"), 5.260135901548374e+210)
  assert_eq(float0570("0x1.8p+52"), 6755399441055744.0)
  assert_eq(float0570("0x1.62e42ep6"), 88.72283172607422)
  assert_eq(float0570("0x1.9fe368p6"), 103.97207641601562)
  assert_eq(float0570("0x1.0p24"), 16777216.0)
  assert_eq(float0570("0x1.0p97"), 1.5845632502852868e+29)
  assert_eq(float0570("0x1.0p-95"), 2.524354896707238e-29)
  assert_eq(float0570("0x1.ebfce50fac4f3p-3"), 0.2402284522445722)
  assert_eq(float0570("0x1.62e42ff0c52d6p-1"), 0.6931471806916203)
}

///|
/// THE BOUNDARY THE TOOLCHAIN DRAWS, and it is not the analyzer's to move:
/// `0x1p3` is REJECTED by the compiler ("Parse error, unexpected token id
/// (lowercase start)"), because the FRACTION is what makes a hex literal a
/// float. So the analyzer reads it as the integer `0x1` and the name `p3` --
/// which is honest, because the file does not compile, and which is exactly
/// what the analyzer read before the fix.
///
/// The negative control beside it: a hex integer followed by a FIELD ACCESS is
/// still an integer and a field access. `t` is not a hex digit, so the `0x1.`
/// in `0x1.to_string()` is not a fraction -- and the analyzer must not swallow
/// the dot.
test "0570: a hex integer is not a hex float, and a field access is not a fraction" {
  assert_eq(kind0570("0x1p3"), "int")
  assert_eq(names0570("0x1p3\n"), 1)
  assert_eq(name0570("0x1p3\n", 0), "p3")
  assert_eq(kind0570("0x1.to_string()"), "int")
  assert_eq(names0570("0x1.to_string()\n"), 1)
  assert_eq(name0570("0x1.to_string()\n", 0), "to_string")
}

///|
/// A PACKAGE PATH IS ONE NAME. The toolchain's own error says so: a probe
/// package with `let a = @encoding/utf8.encode("x")` reports "Cannot use
/// @encoding/utf8: package encoding/utf8 is not imported." -- it names the
/// WHOLE path, so the whole path is the qualifier.
///
/// Before the fix the analyzer read `@encoding` as a name, `/` as a division
/// and `utf8` as a NAME, and reported `undefined variable 'utf8'` on
/// moonbitlang/core `archive/zip/writer.mbt:194`.
test "0570: a package path is one name" {
  assert_eq(name0570("@encoding/utf8.encode(\"x\")\n", 0), "@encoding/utf8")
  // Two names: the path and the member. The member is a member, and the
  // analyzer has always known the difference.
  assert_eq(names0570("@encoding/utf8.encode(\"x\")\n"), 2)
  assert_eq(name0570("@encoding/utf8.encode(\"x\")\n", 1), "encode")
}

///|
/// THE PATH IS NOT UNBOUNDED, and the boundary is the toolchain's: a `/` after
/// an `@`-name is a PATH SEPARATOR, and the toolchain refuses to divide by a
/// package -- `@encoding / 2` is a parse error ("unexpected token infix 3,
/// you may expect `.` id"). So the analyzer consumes `/` and the segment that
/// follows it, and only when the segment starts with a letter: a `/` followed
/// by a digit is not a path, and the analyzer leaves it as an operator.
test "0570: a slash that does not start a path segment is not part of a path" {
  assert_eq(name0570("@encoding/2\n", 0), "@encoding")
  assert_eq(names0570("@encoding/2\n"), 1)
  // And a plain alias is still a plain alias.
  assert_eq(name0570("@core\n", 0), "@core")
}

///|
/// THE CONTROL: an ordinary division is still a division, and an ordinary
/// name is still a name. If the path rule had swallowed ordinary code, these
/// would be the rows that caught it.
test "0570: an ordinary division and an ordinary name are unchanged" {
  assert_eq(names0570("a / b\n"), 2)
  assert_eq(name0570("a / b\n", 0), "a")
  assert_eq(name0570("a / b\n", 1), "b")
}
