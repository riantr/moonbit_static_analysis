//| Tests for 0.4.30: the PIPE tokens.
//|
//| THE LEXER HALF of 0464. `<|` and `|>` are the increment's whole content at this
//! level: the parser had a pipe tier before this token existed? No -- it did not.
//! `f <| x` lexed as `f`, `<`, `|`, `x`, and the parser then reported the `|`.
//!
//!     "unexpected token `|`" -- 22 sites in moonbitlang/async 0.22.4, a message
//!     that names neither the operator nor the problem.
//!
//! THE DIRECTION IS SETTLED, and it is why `<|` and `|>` are separate tokens rather
//! than one token with a flag (`_verify/settle_0464_pipe_operators.ps1`, 14/14):
//!
//!     `f <| x`   ACCEPT        `x <| f`   REJECT(4101)
//!     `x |> f`   ACCEPT        `f |> x`   REJECT(4101)
//!
//! One token shared by both spellings would accept code the toolchain refuses.

///|
/// `<|` IS ONE TOKEN. Two tokens is what all 11 corpus files tripped over.
test "0464: the <| pipe is one token" {
  let (toks, _, reports) = @lexer.lex("f <| g")
  assert_eq(reports.length(), 0)
  // `lex` appends a trailing TEOF.
  assert_eq(toks.length(), 4)
}

///|
/// AND `|>` IS ONE TOKEN, and a DIFFERENT one -- see the header for the settle
/// that makes a shared token wrong rather than merely terse.
test "0464: the |> pipe is its own token, distinct from <|" {
  let (lt, _, _) = @lexer.lex("a <| b")
  let (gt, _, _) = @lexer.lex("a |> b")
  match (lt[1], gt[1]) {
    (@lexer.TPipeLt, @lexer.TPipeGt) => assert_true(true)
    (_, _) => assert_true(false)
  }
}

///|
/// AND `<+` IS A THIRD TOKEN, because it is a StringBuilder APPEND and not a pipe.
/// That was not a guess: the first settle described `<+` as "pipe or append" and
/// `inc <+ 1` is refused with [3002] "you may expect template string", while
/// `"a" <+ "b"` is REJECT(4015) and `sb <+ "b"` is ACCEPT. Two readings taken from
/// the symbol's shape, both wrong.
test "0464: <+ is an append token, not a pipe token" {
  let (toks, _, _) = @lexer.lex("sb <+ 1")
  match toks[1] {
    @lexer.TAppendPlus => assert_true(true)
    _ => assert_true(false)
  }
}

///|
/// AND THE CONTROL for the LEXER: `||` and `<=` are still their own tokens. The
/// pipe branch sits among the shifts and the compound assignments, and each of
/// those is mutually exclusive with it only by its SECOND character. A pipe check
/// written before `<=` rather than after it would eat `a <= b`.
test "0464: || and <= are still single tokens beside the pipe" {
  let (or, _, _) = @lexer.lex("a || b")
  let (le, _, _) = @lexer.lex("a <= b")
  match (or[1], le[1]) {
    (@lexer.TOrOr, @lexer.TLe) => assert_true(true)
    (_, _) => assert_true(false)
  }
}

///|
/// AND THE OTHER NEIGHBOUR, `<<`: the pipe check must not eat a shift, and `>>` is
/// deliberately NOT application (`inc >> 1` is a type error, settled), so it stays
/// its own token rather than becoming a third pipe spelling.
test "0464: shifts are untouched beside the pipe" {
  let (shl, _, _) = @lexer.lex("a << b")
  let (shr, _, _) = @lexer.lex("a >> b")
  match (shl[1], shr[1]) {
    (@lexer.TShl, @lexer.TShr) => assert_true(true)
    (_, _) => assert_true(false)
  }
}
