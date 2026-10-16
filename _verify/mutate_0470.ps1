# Mutation gate 0470 -- the C-style `for` INIT CLAUSE is a declaration.
#
# WHAT THIS PINS. The C-style `for` desugars to `SBlock([<init>, SWhile(cond, body + update)])`,
# so the init clause is a statement inside a block. It carries no `let`, so the ordinary
# statement reader built an `SAssign`. That is the wrong node twice over: the clause DECLARES
# rather than assigns, and the name does not outlive the loop.
#
# The settle (`_verify/settle_0470_c_for_init.ps1`, 9 rows, 2 controls + 1 claim control)
# establishes the semantics against the toolchain rather than against the fixture that
# failed. The sharpest row is the compiler's own message:
#
#     Unknown binder n in the for-loop steps. Binders in the steps must be declared in the
#     initialization block of the for-loop.                      [4106]
#
# That is this increment stated as a rule. An assignment reading has no way to produce it,
# because there would be nothing to "declare in the initialization block".
#
# The observable cost was moonbit_labeler 0.2.13 app_moui/rasterizer.mbt:1218, the last
# `actionable` on any pinned corpus:
#
#     argument 2 to 'blend_pixel' has incompatible type 'float'; expected 'int'
#
# `Infer::assign_check` REPORTS a mismatch but does not rebind, so an `x : Double` leaked
# from an enclosing body survived and the loop's own `x` never replaced it.
#
# => 判据: the FIRST version of `c_for_init` unwrapped an `EBin` out of the right-hand side
# and matched NOTHING, because `EBin` is what the COMPOUND branch produces while the plain
# `=` branch stores the value DIRECTLY. It returned every statement unchanged, and
# `moon check --deny-warn` was 0 while all 857 tests stayed green and the corpus finding
# stayed. M2 is that exact inert version, kept here as a mutation rather than as history:
# a function that is never reached cannot be caught by a suite, only by asking what it
# would look like if it did nothing.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'mutate_lib.ps1')

$PARSER = 'src\parser\parser.mbt'

Invoke-MutationGate -Name '0470' -Target 'wasm' -Mutations @(

  # M1 THE ORIGINAL DEFECT, RESTORED LITERALLY. The call site goes back to the ordinary
  # statement reader, which is the one-line shape this increment actually had before it.
  # This is the defect as it shipped, not a paraphrase of it.
  @{
    Name = 'M1 the init clause is read by the ordinary statement reader again'
    File = $PARSER
    Find = '    stmts.push(self.c_for_init(sp))'
    Repl = '    stmts.push(self.parse_stmt())'
    MustRed = '0470: a C-style for init clause is built as SLet, not SAssign'
  }

  # M2 THE VERSION THAT GREEN-BARRED. The function exists, is called, parses the clause and
  # hands the result straight back: the conversion is gone and nothing else changed. This is
  # the mutation that reproduces the INCIDENT rather than the defect -- the increment
  # compiled clean, tested 857/857 and changed no corpus number, because this is what it was
  # doing all along.
  #
  # THE FIRST DRAFT OF THIS MUTATION REPLACED ONLY THE `let st .. return st` HEAD, leaving
  # the `match` below it referring to an unbound `st`. It came back COMPILE-ERR, which is
  # NOT a kill -- a mutation that does not compile tests nothing. The replacement below
  # removes the whole conversion instead, so the function genuinely runs and genuinely does
  # nothing, which is the state this gate exists to catch.
  # => a mutation gate is also a record of the ways a change can be INERT, not only of the
  # ways it can be wrong.
  @{
    Name = 'M2 c_for_init parses the clause and hands it back, conversion removed'
    File = $PARSER
    Find = "  match st.kind {`n    SAssign(target, value) =>`n      match target.kind {`n        @ast.EName(n) => { span: st.span, kind: @ast.SLet(n, `"`", value), }`n        _ => st`n      }`n    _ => st`n  }"
    Repl = '  st'
    MustRed = '0470: a C-style for init clause is built as SLet, not SAssign'
  }

  # M3 THE VALUE AND THE TARGET SWAPPED. Keeps the declaration, binds the wrong thing:
  # `for i = 0` becomes `SLet("i", "", EName("i"))`, a self-referential binding. A name is
  # still introduced and the tree still has the right SHAPE, which is why only a row that
  # looks at the value can see it -- the node-kind rows above all stay green.
  @{
    Name = 'M3 the declaration binds the target expression instead of the value'
    File = $PARSER
    Find = '@ast.SLet(n, "", value), }'
    Repl = '@ast.SLet(n, "", target), }'
    MustRed = '0470: a C-style for init clause is built as SLet, not SAssign'
  }

  # M4 THE CLAUSE IS GIVEN A TYPE ANNOTATION IT CANNOT HAVE. The settle says `let` is
  # forbidden in the init clause, so there is no annotation to carry and "" is the honest
  # encoding. Pinning "Int" would be a small lie that happens to be right for `for i = 0`
  # and wrong for every `for x = xs` where xs is not an Int.
  @{
    Name = 'M4 the init clause is given a type annotation it cannot have'
    File = $PARSER
    Find = '@ast.SLet(n, "", value), }'
    Repl = '@ast.SLet(n, "Int", value), }'
    MustRed = '0470: a C-style for init clause is built as SLet, not SAssign'
  }

  # M5 THE SAME EDIT AS M2, PINNED ON THE PIPELINE ROW. This is here because the 0470
  # pipeline rows were written against the family string `ArgumentTypeMismatch`, which does
  # not exist -- the real one is `ArgTypeMismatch`. Four rows asserting `== 0` on a family
  # that cannot occur are VACUOUS and passed 868/868. Only the one `== 1` row caught it, by
  # failing.
  #
  # => 判据: before keeping a negative row, ask whether ANY mutation can turn it red. A row
  # asserting zero of a misspelled family is not a passing test, it is a missing one. M5
  # answers that question for the row that matters, at the level the corpus sees.
  @{
    Name = 'M5 the inert function again, pinned on the pipeline row (proves it is not vacuous)'
    File = $PARSER
    Find = "  match st.kind {`n    SAssign(target, value) =>`n      match target.kind {`n        @ast.EName(n) => { span: st.span, kind: @ast.SLet(n, `"`", value), }`n        _ => st`n      }`n    _ => st`n  }"
    Repl = '  st'
    MustRed = '0470: a C-style for init clause rebinds the name for the loop body'
  }
)

# NO MUTATION FOR THE SEPARATOR STEP, and that is a measured decision rather than an
# oversight. `c_for_init` steps over `TNewline`/`TSemi` before it discriminates, and no legal
# MoonBit program can reach that step: the lexer emits no whitespace token between `for` and
# its first name, and a header split across lines with no semicolon on the `for` line is
# REJECTed [3002] by `moon check` -- measured, and recorded in `parser_0470_test.mbt`.
# There is therefore no row that can kill it and no mutation that could be honest about it.
# The step stays because a token-level discriminator that silently stops discriminating if
# the lexer ever emits separators is worse than six lines that are currently unreachable.

Write-MutationGateVerdict -Name '0470'
if ($script:MutationGateFailures.Count -gt 0) { exit 1 }
exit 0
