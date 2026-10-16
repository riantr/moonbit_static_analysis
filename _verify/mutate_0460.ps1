# Mutation gate 0460 -- an ARRAY PATTERN binds its elements, and a LITERAL pattern
# is CONSUMED.
#
# WHAT THIS PINS. `parse_is_pattern` had a tuple branch and a head branch and no
# array branch, so `is [ a, b ]` fell through to the head branch, which read the
# FIRST ELEMENT as the head name and returned. Measured on
# `moonbitlang/async 0.22.4 src/internal/gzip_internal/metadata.mbt`:
#
#   * `undefined name 'compression_method'` -- a name the pattern BINDS and then
#     uses eight lines later;
#   * `undefined name 'else'`, ON A KEYWORD, because the `]` was never consumed
#     and the token after the pattern was read as code;
#   * `no visible binding for 'u32le'`.
#
# All 14 async and all 9 proton findings the 0459 lexer work surfaced are this
# shape, which is why 0459 could not ship alone.
#
# The second half is separate and easy to lose: a LITERAL pattern used to hit a
# bare `return []` that CONSUMED NOTHING. A literal binds no name, so returning
# immediately left the literal in the stream -- and the token after a guard's
# pattern is `else`.
#
# THE GRAMMAR, settled 7/7 in `_verify/settle_0460_array_pattern.ps1`:
#
#     [first, second]        binds both
#     [Some(inner)]          binds inner  (a name inside constructor parens)
#     [[inner], tail]        binds both  (depth 2, inside a NESTED bracket)
#     [1, 2, 3]              binds nothing
#     name(args) in a pattern is a CONSTRUCTOR pattern, not a call
#
# => 判据: `undefined name 'else'` is the loudest possible tell, and it is the only
# one of the three that cannot be explained away as "the name is not in scope".
# A pattern that did not end has no more specific error available to it.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'mutate_lib.ps1')

$PARSER = 'src\parser\parser.mbt'

Invoke-MutationGate -Name '0460' -Target 'js' -Mutations @(

  # M1 IS THE GATE. The array branch is never taken, which is the pre-0460 parser:
  # the `[` falls through to the head branch and the first element is read as the
  # head name.
  @{
    Name = 'M1 the array-pattern branch is removed'
    File = $PARSER
    Find = "  if self.at(TLBracket) {`n    let _ = self.bump()`n    let found : Array[String] = []`n    let mut depth = 1"
    Repl = "  if false {`n    let _ = self.bump()`n    let found : Array[String] = []`n    let mut depth = 1"
    MustRed = '0460: an array pattern binds its elements'
  }

  # M2 THE BRANCH MATCHES BUT CONSUMES NOTHING -- `self.p` is left where it was, so
  # the `]` and everything after it fall to the expression reader. Same verdict as
  # M1 by a different route, and the code still reads as though the group were
  # handled.
  @{
    Name = 'M2 the array pattern is read but not consumed'
    File = $PARSER
    Find = "      j += 1`n    }`n    self.p = j`n    return found`n  }"
    Repl = "      j += 1`n    }`n    self.p = self.p`n    return found`n  }"
    MustRed = '0460: an array pattern binds its elements'
  }

  # M3 THE DEPTH IS NOT TRACKED, so the inner `]` of a nested pattern ends the outer
  # one and the tail is read as code. This is the mutation that makes the depth
  # counter load-bearing rather than decorative.
  @{
    Name = 'M3 bracket depth is not tracked'
    File = $PARSER
    Find = "        TLBracket => depth += 1`n        TRBracket => {`n          depth -= 1`n          if depth == 0 {"
    Repl = "        TLBracket => depth += 0`n        TRBracket => {`n          depth -= 1`n          if depth == 0 {"
    MustRed = '0460: a nested array pattern binds its inner names'
  }

  # M4 ONLY THE TOP LEVEL BINDS, so `u32le(mtime)` -- the corpus shape -- registers
  # nothing. An implementation that handled bare elements alone would have traded
  # one false positive for another, which is the whole point of the settle's
  # `[Some(inner)]` case.
  #
  # WITNESS: the NESTED row, not the constructor-argument row, and the reason is
  # measured rather than argued. With this mutation applied, the `[Some(inner)]`
  # fixture reports NOTHING at all -- probed directly, `r.reports.length() == 0`
  # -- so its `UndefinedName == 0` assertion is satisfied whether or not `inner`
  # was bound. That row therefore cannot see this mutation, and naming it as the
  # witness would have recorded a kill that the witness did not produce.
  #
  # WHY `inner` still resolves is NOT established. The guard binds through the
  # pattern AST as well as through the name list `parse_is_pattern` returns, and
  # this probe did not separate the two paths. Stated as open rather than guessed.
  @{
    Name = 'M4 only top-level array elements bind'
    File = $PARSER
    Find = 'TName(n) => if self.pattern_binding_at(j) { found.push(n) }'
    Repl = 'TName(n) => if depth == 1 { found.push(n) }'
    MustRed = '0460: a nested array pattern binds its inner names'
  }

  # M5 THE LITERAL PATTERN IS NOT CONSUMED, restoring the bare `return []`. The
  # finding this produces is `undefined name 'else'` -- on a keyword, in a file the
  # toolchain compiles.
  @{
    Name = 'M5 a literal pattern is read but not consumed'
    File = $PARSER
    Find = "    let _ = self.bump()`n    return []`n  } else {`n    return []`n  }"
    Repl = "    return []`n  } else {`n    return []`n  }"
    MustRed = '0460: a literal pattern leaves the else after it intact'
  }
)

Write-MutationGateVerdict -Name '0460'
if ($script:MutationGateFailures.Count -gt 0) { exit 1 }
exit 0
