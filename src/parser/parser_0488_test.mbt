//| Tests for 0488 -- `<+` across a newline, and the `$|...` template string. The third defect
//| 0488 fixed (a LABEL read as a name) is in `src/pipeline/pipeline_0488_test.mbt`, because it is
//| only observable as an UNDEFINED-NAME FINDING and `src/parser` cannot see `@pipeline`.
//
//| THREE DEFECTS THAT LOOK LIKE ONE CONSTRUCT IN THE SOURCE:
//
//|   A. `newline_supplied_after` ... `newline_suppressed_after` did not list `TAppendPlus`, so the
//|      line break AFTER `<+` ended the statement and the operand was read as a new one.
//|   B. `$|...` had no lexer production at all -- the `$` fell to lex_op's catch-all -- so the
//|      template string was never a token. It is a GENERAL expression, not a `<+`-only slot.
//|   C. `copy_interp` flushed a LABEL as a name READ, so `\{value.to_string(radix=16)}` reported
//:      `no visible binding for 'radix'`. Nothing named `radix` is ever bound; `label=value` is
//|      MoonBit's labelled-argument call syntax.
//
//| `_verify/settle_0488_append_nextline.ps1`, 20 rows / 4 controls, GATE OK.
//
//| *** TWO ROWS THAT WERE WRITTEN, FAILED, AND ARE NOT HERE. *** Both are recorded rather than
//| quietly dropped, because the reason is the same standing limit and it is worth a fresh instance:
//
//|   "a" NEWLINE `+ b` -- asserted `first_error > 0`. It is 0, and that is CORRECT: `first_error`
//:   measures whether the reader STOPPED, and the reader does not stop, because `+ b` is a second
//:   statement. The toolchain rejects the program too, but with 4139 "its value cannot be implicitly
//:   ignored" -- a TYPE error at `a`, not a parse error. So the token-stream question "was the
//|   newline suppressed" has no `first_error` observable at all, and `mutate_0488` pins it by
//:   mutating the suppression SET instead.
//
//|   `$|` not spanning lines -- asserted `first_error > 0` on `let x = $|` NEWLINE `<a>`. The
//|   settled REJECT 3002 row is the one with a CLOSING `$|</a>` after the break (settle C3); the
//:   shape asserted here has no second interpolant and the toolchain treats it differently. The
//:   property is pinned by a mutation that removes the `c == '\n'` guard outright.

///|
/// DEFECT A. The corpus shape at `src/socket/addr_utils.mbt:297`: a `<+` whose operand is one plain
/// double-quoted string on the NEXT line.
///
/// This is the row defect A is written for. Before the fix the newline after `<+` was not
/// suppressed, so the statement ended there and the string was parsed as a new one.
test "0488: an append continues across the line break" {
  let r = @parser.parse(
    "///|\nfn f(sb : StringBuilder) -> Unit {\n  sb <+\n    \"x\"\n  ignore(sb)\n}\n",
  )
  assert_eq(r.first_error, 0)
}

///|
/// AND WITH INTERPOLATIONS, which is the exact site. The element is a `Byte` because an address is
/// made of bytes -- an earlier draft typed it `Int`, and `Int` has no `to_int`, which produced two
/// compiler errors that had nothing to do with the construct under test.
test "0488: the interpolated next-line operand is the corpus shape" {
  let r = @parser.parse(
    "///|\nfn f(sb : StringBuilder, addr : Array[Byte]) -> Unit {\n  sb <+\n    \"\\{addr[12].to_int()}.\\{addr[13].to_int()}\"\n  ignore(sb)\n}\n",
  )
  assert_eq(r.first_error, 0)
}

///|
/// DEFECT B, the second corpus site: `examples/http_file_server/main.mbt:24`. `conn <+` then SEVERAL
/// one-line `$|...` lines. It can be gated because the two halves are separate rows already --
/// the break is defect A and the `$|` is defect B -- and this one is just the two stacked.
test "0488: several template-string lines under one append" {
  let r = @parser.parse(
    "///|\nfn f(conn : StringBuilder, path : String) -> Unit {\n  conn <+\n    $|<!DOCTYPE html><html><body>\n    $|<h1>\\{path}</h1>\n  ignore(conn)\n}\n",
  )
  assert_eq(r.first_error, 0)
}

///|
/// `$|` IS A GENERAL EXPRESSION, not a slot only `<+` can fill. Both of these ACCEPT, which is what
/// says the fix belongs in the expression grammar rather than in `parse_pipe`; the settle's rows C1
/// and C2 are the toolchain's half of that claim.
test "0488: the template string is an expression in its own right" {
  assert_eq(
    @parser.parse("///|\nfn f() -> Unit {\n  let x = $|<a>\n  ignore(x)\n}\n").first_error,
    0,
  )
  assert_eq(
    @parser.parse(
      "///|\nfn f(a : String) -> Unit {\n  let x = a + $|<b>\n  ignore(x)\n}\n",
    ).first_error,
    0,
  )
}

///|
/// AND THE SAME-LINE SPELLING IS UNAFFECTED, which is the regression the settle's
/// `ctl_append_sameline` predicts. If this ever goes red the construct moved rather than grew.
test "0488: the same-line append is unaffected" {
  assert_eq(
    @parser.parse(
      "///|\nfn f(sb : StringBuilder) -> Unit {\n  sb <+ \"x\"\n  ignore(sb)\n}\n",
    ).first_error,
    0,
  )
}
