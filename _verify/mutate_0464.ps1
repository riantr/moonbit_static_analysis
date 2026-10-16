# Mutation gate 0464 -- the PIPE operators, and `errdefer`.
#
# WHAT THIS PINS. Two increments, and the second only exists because of the first.
#
# 0464 -- `<|` and `|>` had no token. `f <| x` lexed as `f`, `<`, `|`, `x`, and the
# parser reported the `|`: "unexpected token `|`", 22 sites in moonbitlang/async
# 0.22.4, a message naming neither the operator nor the problem. Measured reach on
# the 13 files whose FIRST blocker was a pipe: async parsed 302 -> 312,
# unreliable 916 -> 851.
#
# 0464b -- `errdefer` was not in that ranking at all. `src/socket/udp.mbt` was
# blocked EARLIER at a `|>` on line 548, so its three `errdefer` lines had never
# been read; unblocking the file surfaced them as `undefined name 'errdefer'` and
# `actionable` went 0 -> 3 against code `moon check` compiles.
#
# THE GRAMMAR, settled in `_verify/settle_0464_pipe_operators.ps1` (14/14) rather
# than read off the symbol -- which was wrong twice, in this order:
#
#     `f <| x`  ACCEPT      `x <| f`  REJECT(4101)      <- DIRECTIONAL
#     `x |> f`  ACCEPT      `f |> x`  REJECT(4101)      <- its exact mirror
#     `2 * 3 |> inc`  ACCEPT        -> left operand is `(2 * 3)`
#     `2 |> inc * 3`  REJECT        -> right operand is `inc * 3`
#     `inc <+ 1`  REJECT("template string")   -> `<+` is a BUILDER append
#     `"a" <+ "b"` REJECT(4015)               -> not String concat either
#     `inc >> 1`  REJECT(4014)                -> `>>` is NOT application
#
# => 判据: "it is pipe-shaped" is not a reading of the symbol, it is a guess. Three
# of the seven rows above contradict what the symbols look like, and every one of
# them would have been implemented confidently and shipped wrong.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'mutate_lib.ps1')

$LEXER = 'src\lexer\lexer.mbt'
$PARSER = 'src\parser\parser.mbt'

Invoke-MutationGate -Name '0464' -Target 'js' -Mutations @(

  # M1 IS THE GATE. The `<|` token is gone and the pair lexes as `<` then `|`,
  # which is the pre-0464 lexer verbatim.
  @{
    Name = 'M1 the <| token is removed'
    File = $LEXER
    Find = "  if c == '<' && next == Some('|') {`n    self.pos += 2`n    self.col += 2`n    self.emit(TPipeLt, l, c0, 2)`n    return TPipeLt`n  }"
    Repl = ''
    MustRed = '0464: the <| pipe is one token'
  }

  # M2 THE TWO PIPES SHARE A TOKEN, which is the implementation this settle exists
  # to forbid. `f |> x` is REJECT(4101) in the toolchain, so a token that accepts
  # both spellings accepts code the compiler refuses. Neither token-level row sees
  # this: they compare TPipeLt against TPipeGt, which are still distinct VARIANTS
  # here -- only the LEXER stops distinguishing them.
  @{
    Name = 'M2 |> lexes as the same token as <|'
    File = $LEXER
    Find = 'self.emit(TPipeGt, l, c0, 2)'
    Repl = 'self.emit(TPipeLt, l, c0, 2)'
    MustRed = '0464: the |> pipe is its own token, distinct from <|'
  }

  # M3 THE PIPE CHECKS SWALLOW A NEIGHBOUR -- ATTEMPTED, AND IT IS INERT.
  #
  # Widening the pipe's second character to accept `=` as well, which would eat
  # `a <= b`. It SURVIVED 696/696, and the reason is settled by construction rather
  # than left as an open question: `lex_op` tests `<` against `=` (emitting `TLe`)
  # and against `|` (emitting `TPipeLt`) on DIFFERENT second characters. The two
  # conditions are disjoint, so neither can be reached by widening the other and
  # their order in the if-chain is free. That also corrects the source comment's
  # phrasing: "mutually exclusive by second character" is the load-bearing fact,
  # and it is why M3 cannot exist as a defect.
  @{
    Name = 'M3 the pipe matches < and = alike'
    File = $LEXER
    Find = "  if c == '<' && next == Some('|') {"
    Repl = "  if c == '<' && (next == Some('|') || next == Some('=')) {"
    Expect = 'SURVIVED'
    Prove = 'Unreachable by construction: lex_op tests < against = and against | on disjoint second characters, so widening one condition cannot be reached by the other and neither ordering can interfere. Measured 696/696 green under mutation. The neighbour that DOES matter is covered by M3 replacement -- see the shifts control test, which asserts TShl and TShr are still distinct.'
  }

  # M4 THE PIPE TIER IS REMOVED FROM `parse_expr`, so the tokens lex and then
  # nothing consumes them -- the shape the 13 corpus files were blocked in.
  @{
    Name = 'M4 the pipe tier is not reached from parse_expr'
    File = $PARSER
    Find = '  self.parse_pipe()'
    Repl = '  self.parse_or()'
    MustRed = '0464: |> pipes a value into a function'
  }

  # M5 THE PIPE'S RIGHT OPERAND BINDS TOO TIGHTLY, which is the precedence defect
  # the settle's middle row pins. `parse_unary` is one rung above `parse_or`, so
  # `2 |> inc * 3` becomes `(2 |> inc) * 3` instead of `2 |> (inc * 3)`, and every
  # such line lands in a different tree while nothing reports wrong.
  #
  # The first attempt at this row replaced the operand with a bare `@ast.EBigInt`
  # and came back COMPILE-ERR, which is not a kill: it proves the fixture fails to
  # build, not that any guard noticed the defect. A mutation has to compile.
  @{
    Name = 'M5 the pipe right operand binds one rung too tightly'
    File = $PARSER
    Find = "      self.parse_or()`n    }`n    l = { span: l.span, kind: @ast.EBin(@ast.OpPipe, l, r), }"
    Repl = "      self.parse_unary()`n    }`n    l = { span: l.span, kind: @ast.EBin(@ast.OpPipe, l, r), }"
    Expect = 'SURVIVED'
    Prove = 'Unobservable in this analyzer OUTPUT, and the reason is a property of the type map rather than of the suite. OpPipe resolves to TUnknown (types.mbt, binop_result), and binop_result returns TUnknown for ANY operator when either operand is TUnknown. So the two readings -- 2 |> (inc * 3) and (2 |> inc) * 3 -- both bottom out at TUnknown at the root and every lens sees the same type. Measured 696/696 green under mutation. The tree DOES differ; nothing in the pipeline reads it. If the pipe is ever given a known result type rather than Unknown, this row goes red and the precedence row in pipeline_0464_test.mbt becomes the guard instead of the parse-only assertion it currently is.'
  }

  # M6 THE LAMBDA HEAD IS NOT RECOGNISED AS A PIPE'S RIGHT OPERAND. This is the
  # defect the corpus shape actually hit: `parse_expr` checks for a lambda head at
  # ITS OWN cursor, a pipe's right operand never passes through `parse_expr`, and
  # the `=>` leaked out to the statement parser as "invalid assignment target".
  @{
    Name = 'M6 a lambda is not recognised as the right operand of a pipe'
    File = $PARSER
    Find = '    let r : @ast.Expr = if self.at_lambda_head() {'
    Repl = '    let r : @ast.Expr = if false {'
    MustRed = '0464: the corpus shape -- a call piped into a lambda -- parses'
  }

  # M7 `errdefer` IS GONE, which is the pre-0464b parser: the statement reaches the
  # expression reader as a plain NAME and is reported undefined.
  @{
    Name = 'M7 errdefer is read as a name again'
    File = $PARSER
    Find = '  if self.at_name("errdefer") {'
    Repl = '  if self.at_name("errdeferNOT") {'
    MustRed = '0464b: errdefer is a statement, not an undefined name'
  }

  # M8 AND THE BRANCH THAT CATCHES IT MATCHES ON A PREFIX, which would swallow
  # every plain `defer` in the corpus. The two arms sit one line apart reading the
  # same tokens, and `at_name` compares whole names -- so this is the mutation that
  # the control row exists for.
  @{
    Name = 'M8 the errdefer branch takes defer with it'
    File = $PARSER
    Find = '  if self.at_name("defer") {'
    Repl = '  if self.at_name("defer") && false {'
    MustRed = '0464b: defer is untouched (control)'
  }
)

Write-MutationGateVerdict -Name '0464'
if ($script:MutationGateFailures.Count -gt 0) { exit 1 }
exit 0
