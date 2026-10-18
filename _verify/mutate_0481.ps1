# Mutation gate 0481 -- a NESTED optional type, `-> String??`.
#
# WHAT THIS PINS. `type_annotation` folded ONE `?` into a type name and no more, so `String??`
# -- `Option[Option[String]]` -- left its second `?` in the stream. The function reader then
# met a `?` where it wanted a body, and the report landed on a `:` eight tokens EARLIER:
# `self : RuntimeEvent`. proton reported that as `unexpected token ':'`, which is a token with
# nothing to do with the defect, and `internal/native/types.mbt:1351` was that corpus's last
# unreadable file.
#
# Measured: proton `parsed 136 -> 137`, `unreliable 31 -> 0`, `withheld 0`, `notices 2029 ->
# 2131`, `actionable 0 -> 0`. 137/137 -- the corpus is closed, and its quarantine is empty.
#
# `_verify/settle_0481_nested_optional_type.ps1`, 3 controls + 6 rows, GATE OK:
#   ACCEPT  `-> String?` / `-> String??` / `(x : String??)` / `let x : String??`
#   ACCEPT  `-> String???`  the nesting is UNBOUNDED, which is why this is a LOOP
#   ACCEPT  `self : String` labelled parameters -- so the reported `:` was a red herring
#
# M1 IS THE MUTATION THAT DECIDES LOOP-OR-TWO-BUMPS BY BEING WRONG IN THE DIRECTION THE
# CORPUS WOULD NOT NOTICE, and M2 is the one the corpus could not have found either. Neither
# is decoration: both turn a file into one that parses and reports nothing while carrying a
# type annotation that is simply not what the program says.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'mutate_lib.ps1')

$PARSER = 'src\parser\parser.mbt'

Invoke-MutationGate -Name '0481' -Target 'wasm' -Mutations @(

  # M1 BACK TO ONE `?`. The reader stops after the first, so `String??` strands its second `?`
  # and the fn reader trips over it -- which is the defect. Every corpus file has exactly one
  # doubly-optional type, so a corpus scan alone would not distinguish "fixed for the corpus"
  # from "fixed".
  @{
    Name = 'M1 only one question mark is folded into a type'
    File = $PARSER
    Find = '  while self.at(TQuestion) {' + "`n" +
           '    let _ = self.bump()' + "`n" +
           '    n = n + "?"' + "`n" +
           '  }'
    Repl = '  if self.at(TQuestion) {' + "`n" +
           '    let _ = self.bump()' + "`n" +
           '    n = n + "?"' + "`n" +
           '  }'
    MustRed = '0481: a doubly-optional return type reads whole'
  }

  # M2 THE `?` IS CONSUMED BUT NOT RECORDED. The loop still eats every mark, the parse still
  # succeeds, no report is raised -- and the annotation comes back `String` for a program that
  # says `String??`. This is the shape 0478 called "parsed but not read", one layer down: here
  # the type TEXT is lost rather than an expression. The corpus would never see it, because
  # nothing here renders annotations back out and nothing reports a type mismatch.
  @{
    Name = 'M2 the question mark is consumed but not recorded in the annotation'
    File = $PARSER
    Find = '    n = n + "?"' + "`n" +
           '  }' + "`n" +
           '  n' + "`n" +
           '}'
    Repl = '    n = n' + "`n" +
           '  }' + "`n" +
           '  n' + "`n" +
           '}'
    MustRed = '0481: a doubly-optional return type reads whole'
  }

  # M3 ONE `?` TOO MANY, APPENDED UNCONDITIONALLY. The append goes BEFORE the loop, so the
  # loop is untouched and the corpus still parses -- every annotated type in every file gains
  # a trailing `?`. This is the control that says the loop STOPS, and the only one of the
  # three that the singly-optional and plain-type rows can see.
  #
  # The first draft of this mutation put the append AFTER the loop's closing brace, which
  # compiled to a type mismatch rather than to anything: the function's value had already been
  # produced by the `n` above it. The gate reported COMPILE-ERR and named the line, which is
  # the cheap way to find out that a mutation tests nothing.
  @{
    Name = 'M3 a question mark is appended to every type'
    File = $PARSER
    Find = '  while self.at(TQuestion) {' + "`n" +
           '    let _ = self.bump()' + "`n" +
           '    n = n + "?"' + "`n" +
           '  }'
    Repl = '  n = n + "?"' + "`n" +
           '  while self.at(TQuestion) {' + "`n" +
           '    let _ = self.bump()' + "`n" +
           '    n = n + "?"' + "`n" +
           '  }'
    MustRed = '0481: a plain parameter type does not gain a question mark (control)'
  }
)

Write-MutationGateVerdict -Name '0481'
if ($script:MutationGateFailures.Count -gt 0) { exit 1 }
exit 0
