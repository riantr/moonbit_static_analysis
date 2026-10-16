# Mutation gate 0455 -- newline suppression after the BITWISE-OR token.
#
# WHAT THIS PINS. `newline_suppressed_after` (src/lexer/lexer.mbt) decides which
# tokens let an expression continue across a line break. It listed TPlus, TAmp,
# TCaret, TAndAnd, TOrOr, TShl, TShr and every comparison operator, and did NOT
# list TBar. The lexer therefore emitted TNewline after `|`, `parse_bitor` bumped
# the `|` correctly, and the operand parse landed on TNewline and `parse_primary`
# raised "unexpected end of line" (parser.mbt:4664).
#
# WHY IT SURVIVED SO LONG, which is the part worth recording. `+`, `&` and `||` were
# all already in the set, so `a +\n b` and `a &\n b` parsed. Only the one-character
# `|` was missing. Every other kind of evidence pointed elsewhere:
#
#   - A sweep for "trailing binary operators" reports 178 corpus files and 2296
#     sites, and would have ranked this as the biggest available lever. 103 of those
#     are moui files and only 3 moui files fail to parse at all, because every
#     operator except this one already continues correctly. A site count is not a
#     leverage count.
#   - `input_dispatch_result.mbt` had been carried across several rounds as "a
#     parenthesised `if` as an operand", which is false: a parenthesised `if` parses
#     fine, alone and as a single-line operand. `\(\s*if\s` also appears in 20 files
#     of moui while only 3 files in all of moui fail to parse.
#   - The lexer's own token comment said `TBar` is "the or-pattern separator ... The
#     parser never sees one". That was true when written and stopped being true when
#     `parse_bitor` was added (parser.mbt:3134), which consumes TBar and builds
#     `EBin(OpBitOr, ...)`. A stale comment about a token is enough to keep that
#     token out of the set it belongs in.
#
# ⇒ 判据: a token's role is whatever the CONSUMER does with it, and a comment
# describing an earlier consumer will outlive the consumer and mislead the next
# reader about what the token is for.
#
# THE FIX, and what it cost. One line -- `| TBar` added to the suppression set.
# Measured across all six corpora:
#
#   moui             parsed 605 -> 606    actionable 0 -> 0
#   moonbit_labeler  parsed  28 ->  28    unreliable 311 -> 294
#   moonbit_image    parsed   2 ->   2    unreliable 294 -> 285
#   async            parsed 274 -> 274    unreliable 1188 -> 1175
#   proton           parsed 109 -> 109    byte-identical
#   proton_contract  parsed   4 ->   4    byte-identical
#
# `unexpected end of line` is now 0 occurrences across all six corpora; it was 1 in
# moui before. The 42 findings that left the `unreliable` bucket are NOT a coverage
# loss, and that was verified rather than assumed: both builds were made from the
# same tree, one with TBar in the set and one without, and the per-file comparison
# found ZERO files read less, one newly complete (moui `input_dispatch_result.mbt`)
# and one read further (labeler). `actionable` and `notices` are unchanged in every
# corpus, so the findings that vanished were exactly the ones the analyzer itself had
# flagged as "this file was not fully understood".
#
# THE RISK THIS GATE EXISTS TO RULE OUT is M4-adjacent: `|` is ALSO the or-pattern
# separator inside match arms (`SAssign(_) | SLet(_) => ...`). Adding TBar to the
# suppression set drops the TNewline TOKEN after it; TBar itself still reaches the
# stream, and match bodies are skipped whole, so no pattern parser can be confused by
# the missing line break. `or-pattern survives suppression` in
# src/lexer/lexer_0455_test.mbt pins that, and it is the row that would go red if the
# token were ever dropped from the lexer altogether.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'mutate_lib.ps1')

$LEXER = 'src\lexer\lexer.mbt'

Invoke-MutationGate -Name '0455' -Target 'js' -Mutations @(

  # M1 IS THE GATE. Without `| TBar` the construct stops being recognised at all, and
  # the lexer tests are the only thing standing between that and the corpus.
  @{
    Name = 'M1 the TBar arm is removed from the suppression set'
    File = $LEXER
    Find = @'
    | TShr
    | TBar
'@
    Repl = @'
    | TShr
'@
    MustRed = 'bitwise-or continues an expression across a line break'
  }

  # M2 THE POLARITY. A set that suppresses EVERY newline would pass every "this
  # continues" assertion in the file, so the direction has to be pinned too: this one
  # makes every UNLISTED token suppress, which is what a too-wide set looks like.
  @{
    Name = 'M2 every unlisted token also suppresses (the set becomes all-true)'
    File = $LEXER
    Find = @'
    | TSemi => true
    _ => false
'@
    Repl = @'
    | TSemi => true
    _ => true
'@
    MustRed = 'operators continue, a name and a closer do not'
  }

  # M3 THE CALL ITSELF. The set can be perfect and still never be consulted.
  @{
    Name = 'M3 the suppression call is dropped from the lexer'
    File = $LEXER
    Find = 'if !newline_suppressed_after(last) && !closer_ahead(self.chars, self.pos) {'
    Repl = 'if !closer_ahead(self.chars, self.pos) {'
    MustRed = 'operators continue, a name and a closer do not'
  }

  # M4 THE OTHER HALF OF THE SAME CONDITION, kept separate from M3 on purpose: the
  # two conjuncts are independent rules, and a gate that only drops one of them at a
  # time cannot tell which one stopped holding.
  @{
    Name = 'M4 the newline-before-a-closer rule is dropped'
    File = $LEXER
    Find = 'if !newline_suppressed_after(last) && !closer_ahead(self.chars, self.pos) {'
    Repl = 'if !newline_suppressed_after(last) {'
  }
)

Write-MutationGateVerdict -Name '0455'
if ($script:MutationGateFailures.Count -gt 0) { exit 1 }
exit 0
