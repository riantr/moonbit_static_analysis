# Mutation gate 0485 -- a BRACED STRUCT PATTERN in `is` position, `x is { "cmd": [cmd], .. }`.
#
# WHAT THIS PINS. `parse_is_pattern` had NO `{` BRANCH AT ALL, so a brace pattern fell to the
# `else { return [] }` at the bottom of that function and CONSUMED NOTHING. One missing arm, and it
# produced two different failures rather than one. Measured with first_error AND UndefinedName
# TOGETHER, because measuring them apart is what made the `if` row look unaffected when its
# first_error had never been measured at all:
#
#     caller        { "cmd": [cmd] }     { "cmd": [cmd], .. }
#     match arm     fe=0  undef=0        fe=0  undef=0     <- correct already (skip_pattern)
#     guard         fe=0  undef=2        fe=2  undef=0
#     bare `is`     fe=0  undef=2        fe=2  undef=0
#     if            fe=2  undef=0        fe=2  undef=0
#     while         fe=2  undef=0        fe=2  undef=0
#     let destr     fe=2  undef=0        fe=2  undef=0
#
# *** THE QUIET HALF IS WHY THIS GATE IS MOSTLY ABOUT BINDINGS. *** `guard` and a bare `is` PARSE:
# the leftovers happen to re-read as a BLOCK, so nothing halts, and then the names the pattern was
# supposed to bind are reported undefined -- a FALSE POSITIVE on code `moon check` compiles. No
# corpus number moves in either direction for that half, so every row below asserts a BINDING.
#
# ONE READER FIXES ALL OF `guard`, `if`, `while` AND a bare `is`, because all four reach
# `parse_is_pattern` through `parse_is`. Measured before implementing rather than after --
# `_verify/settle_0485_is_struct_pattern.ps1`, 16 rows / 4 controls, GATE OK.
#
# Measured: async `parsed 408 -> 411`, `unreliable 72 -> 65`, `notices 1807 -> 1812`,
# `total 1879 -> 1877`, `actionable 0 -> 0`. Three files closed outright, exactly the three the
# ranking predicted (examples/xargs, examples/curl, examples/tcp_server_benchmark). The other FIVE
# corpora are UNCHANGED -- moui 4225, moonbit_labeler 791, moonbit_image 218, proton 2131,
# proton_contract 34 -- which is itself the finding: a grammar this general that moves exactly one
# corpus is not over-reaching.
#
# `let { "cmd": [cmd], .. } = x` is REJECTED 0011 `partial_match` (a `let` pattern must be
# irrefutable), so that row is left UNREAD on purpose and a test pins the choice.
#
# ANCHORS ARE WRITTEN AGAINST THE POST-`moon fmt` SOURCE. That is the 0483 lesson repeating: fmt
# collapses `TColon => if c { stmt }` onto one line, so a multi-line anchor written before fmt is a
# PREFLIGHT MISS afterwards, and a pre-flight MISS runs no suite at all.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'mutate_lib.ps1')

$PARSER = 'src\parser\parser.mbt'

Invoke-MutationGate -Name '0485' -Target 'wasm' -Mutations @(

  # M1 THE ARM CONSUMES THE PATTERN AND BINDS NOTHING, which is the QUIET half of the defect and
  # the one worth pinning first: the file parses, `first_error` stays 0, and every name the
  # pattern introduced is reported undefined -- a false positive on code `moon check` compiles.
  #
  # The first draft disabled the arm's GUARD (`if false && self.at(TLBrace)`) and came back
  # COMPILE-ERR: the arm's own locals stopped being read, and a mutation that stops compiling is
  # not the behavioural question this row asks.
  @{
    Name = 'M1 the braced pattern is consumed and binds nothing'
    File = $PARSER
    Find = @'
    self.p = j
    return found
  }
  let mut head = ""
'@.Replace("`r`n", "`n")
    Repl = @'
    self.p = j
    return []
  }
  let mut head = ""
'@.Replace("`r`n", "`n")
    MustRed = '0485: a braced pattern binds the element it names'
  }

  # M2 THE VALUE POSITION IS DROPPED, so EVERY name inside the braces is collected. Only the
  # unquoted-key row can see this, and it is why that row exists: with a quoted key the key is a
  # STRING and cannot be mistaken for a binding, so a corpus of quoted patterns happily passes a
  # reader that INVENTS bindings the moment a key is a name.
  @{
    Name = 'M2 every name in the braces binds, including a key'
    File = $PARSER
    Find = '          if in_value && (self.pattern_binding_at(j) || self.rest_binding_at(j)) {'
    Repl = '          if self.pattern_binding_at(j) || self.rest_binding_at(j) {'
    MustRed = '0485: an unquoted key does not bind, its value does'
  }

  # M3 THE BRACKET IS NOT TRACKED, so the flag is set by `in_value = true` on `[` and cleared by
  # the FIRST `]`. Invisible on every corpus shape -- the corpus binds a one-element list and never
  # nests -- and invisible on the first draft of the row too, which used `{ "m": [[a], [b]], .. }`:
  # with a comma between the sub-lists, flat tracking still rebinds at the second `[`.
  #
  # M3 ALSO FOUND A REAL GAP IN THE READER, not just a weak row: the `TColon`/`TComma` guards
  # tested `depth == 1` but not `bracket == 0`, so a comma INSIDE a nested `[ a, b ]` cleared the
  # value flag and `{ "m": [[a, b]], .. }` bound only `a`. Both the guards and the fixture moved.
  @{
    Name = 'M3 the comma guard ignores the bracket, so a nested list binds only its first element'
    File = $PARSER
    Find = '        TComma => if depth == 1 && bracket == 0 { in_value = false }'
    Repl = '        TComma => if depth == 1 { in_value = false }'
    MustRed = '0485: a nested array pattern binds every element'
  }

  # M4 ONLY THE FIRST FIELD'S VALUE BINDS. What a "consume the rest and take the head" shortcut
  # produces: the pattern is consumed correctly, the file parses, `first_error` stays 0, and the
  # SECOND name and everything after it are reported undefined. Only a row that COUNTS the
  # bindings can see it.
  @{
    Name = 'M4 only the first field value binds'
    File = $PARSER
    Find = '        TComma => if depth == 1 && bracket == 0 { in_value = false }'
    Repl = '        TComma => if depth == 1 && bracket == 0 { in_value = false; j = self.toks.length() }'
    MustRed = '0485: every key''s value binds'
  }

  # M5 THE PLAIN-VALUE SPELLING IS NOT COLLECTED, because the reader only looks INSIDE brackets.
  # Every corpus row binds a one-element list, so this mutation is invisible to all six corpora
  # and is caught only by the row written for it.
  @{
    Name = 'M5 only a bracketed value binds, so a plain value binds nothing'
    File = $PARSER
    Find = '        TColon => if depth == 1 && bracket == 0 { in_value = true }'
    Repl = '        TColon => if depth == 1 && bracket == 0 { bracket = 1 }'
    MustRed = '0485: a plain value binds'
  }
)

Write-MutationGateVerdict -Name '0485'
if ($script:MutationGateFailures.Count -gt 0) { exit 1 }
exit 0
