# Mutation gate 0488 -- `<+` across a newline, the `$|...` template string, and a LABEL read as a name.
#
# THREE DEFECTS THAT LOOK LIKE ONE CONSTRUCT IN THE SOURCE, all found by ONE increment and all three
# settled before any of them was implemented. `_verify/settle_0488_append_nextline.ps1`, 20 rows /
# 4 controls, GATE OK:
#
#   A. ACCEPT   sb <+ NEWLINE "x"      <- the corpus shape, at TWO sites
#      REJECT 4139  a NEWLINE + b   /   - b   /   * b   /   == b
#   B. ACCEPT   let x = $|<a>       /   a + $|<b>      <- a GENERAL expression
#      ACCEPT   $|                       <- empty is legal
#      REJECT 3002  let x = $| NEWLINE <a> NEWLINE $|</a>   <- one interpolant is ONE line
#   C. ACCEPT   \{value.to_string(radix=16)}    <- a label is not a read
#      ACCEPT   \{a == b}   /   \{xs.map(x => x + 1).length()}   <- `==` and `=>` ARE reads
#
# THE SETTLE IS WHAT KEEPS DEFECT A TO ONE LINE, and that is the reason to keep re-reading it. The
# obvious "be helpful" version of this fix is a general rule that any expression may continue across
# a line break. That would accept four programs the toolchain REJECTs -- the liberal direction this
# reader has never once taken -- and M1 pins the narrow version instead.
#
# *** TWO PROPERTIES ARE PINNED HERE BECAUSE NO ROW COULD PIN THEM, AND THE REASON IS WORTH READING. ***
# Both rows were written and both failed; neither is in `parser_0488_test.mbt`, and the header of
# that file records why. `first_error` measures whether the reader STOPPED, which is the wrong
# instrument for a TOKEN-STREAM question:
#
#   "a" NEWLINE "+ b"  ->  first_error is 0, and that is CORRECT. `+ b` is a SECOND statement, so
#     nothing fails to parse. The toolchain rejects the same program too, but with 4139 "its value
#     cannot be implicitly ignored" -- a TYPE error at `a`, not a parse error. So there is no
#     `first_error` observable for "the newline before an operator was not suppressed", and M2
#     pins it by mutating the suppression SET instead.
#
#   `$|` not spanning lines  ->  the shape asserted (`let x = $|` NEWLINE `<a>`, no second
#     interpolant) is not the settled REJECT row; settle C3 has a closing `$|</a>` after the break.
#     M3 removes the `c == '\n'` guard outright, which is the direct test.
#
# ANCHORS ARE WRITTEN AGAINST THE POST-`moon fmt` SOURCE. fmt both rewraps one line into several
# and collapses several into one, and either way a stale anchor is a PREFLIGHT MISS that runs no
# suite at all.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'mutate_lib.ps1')

$LEXER = 'src\lexer\lexer.mbt'

Invoke-MutationGate -Name '0488' -Target 'wasm' -Mutations @(

  # M1 DEFECT A, THE INCREMENT. `TAppendPlus` leaves the suppression set, so the break after `<+`
  # ends the statement again and both corpus sites go back to being unread.
  @{
    Name = 'M1 `<+` no longer continues across the line break'
    File = $LEXER
    Find = @'
    | TLBrace
    | TAppendPlus
    | TSemi => true
'@.Replace("`r`n", "`n")
    Repl = @'
    | TLBrace
    | TSemi => true
'@.Replace("`r`n", "`n")
    MustRed = '0488: an append continues across the line break'
  }

  # M2 THE "BE HELPFUL" OVER-CORRECTION. `TStar` is swapped in for `TAppendPlus`: `<+` stops working
  # AND `*` starts continuing across a break, which the toolchain REJECTs with 4139 (settle row B3).
  #
  # This is the mutation that would have caught a general newline rule, and it is why the settle's
  # four REJECT rows are load-bearing rather than documentation. It is killed by the append rows,
  # because losing `<+` is visible even though gaining `*` is not -- this reader parses `a` NEWLINE
  # `* b` without a parse error too, so the second half of this mutation is UNOBSERVABLE at the
  # parser level. The comment says so rather than implying the row proves more than it does.
  @{
    Name = 'M2 `*` is continued across the break instead of `<+`'
    File = $LEXER
    Find = @'
    | TLBrace
    | TAppendPlus
    | TSemi => true
'@.Replace("`r`n", "`n")
    Repl = @'
    | TLBrace
    | TStar
    | TSemi => true
'@.Replace("`r`n", "`n")
    MustRed = '0488: an append continues across the line break'
  }

  # M3 DEFECT B, THE NEWLINE GUARD. `lex_template_string` runs on past the end of the line, so a
  # `$|` swallows the following `$|` and the statement structure after it -- the shape settle C3
  # rejects with 3002, and the reason this function stops where it does.
  #
  # *** THE FIRST DRAFT OF THIS MUTATION HUNG THE GATE FOR ELEVEN MINUTES, AND THE REPL IS WHY IT IS
  # RECORDED HERE. *** It replaced the `break` with `continue`. But `pos` has already been advanced
  # past the newline's INDEX by the loop header's own step... no -- for `\n` this loop body runs
  # BEFORE the trailing `self.pos += 1`, because the `if` sits above it. So `continue` skipped that
  # step, `pos` never moved, and `while self.pos < self.chars.length()` spun forever.
  #
  # => 判据: A MUTATION MUST BE CHECKED FOR LIVENESS, NOT ONLY FOR KILLABILITY. The harness runs a
  # mutation and waits for a `Total tests:` line; a mutation that hangs has no such line and looks
  # exactly like a very slow one. Replacing a `break` with a `continue` inside a cursor loop is the
  # specific shape to check first, because the cursor step usually lives BELOW the branch.
  @{
    Name = 'M3 a template string does not stop at the newline'
    File = $LEXER
    Find = @'
    if c == '\n' {
      // Leave it for run(): it still has to advance the line, and it separates this
      // statement from the next one. An UNTERMINATED `$|` is therefore not a report here --
      // an empty one is legal (settle row C4), so there is no "missing closer" to complain about.
      break
    }
'@.Replace("`r`n", "`n")
    Repl = ''
    MustRed = '0488: several template-string lines under one append'
  }

  # M4 DEFECT B, THE DISPATCH. The `$` falls to lex_op's catch-all and reports "unexpected
  # character" -- the pre-0488 reader, which is what made `examples/http_file_server/main.mbt` read
  # ZERO lines.
  #
  # *** THE WHOLE BRANCH IS REMOVED, NOT JUST ITS BODY, AND M3 IS WHERE THAT LESSON WAS PAINFULLY
  # LEARNED. *** The first version deleted only `last = self.lex_template_string()` and left
  #
  #     if c == '$' && ... { continue }
  #
  # `run()` advances `pos` inside each branch's lexer call, so a bare `continue` never moves it and
  # the main loop spins forever. This gate TIMED OUT at 1500s rather than reporting anything, and
  # the file was left mutated afterwards. A mutation's Repl is a PROGRAM, not a deletion: what it
  # compiles to has to terminate.
  @{
    Name = 'M4 the template string has no lexer branch at all'
    File = $LEXER
    Find = @'
    if c == '$' &&
      self.pos + 1 < self.chars.length() &&
      self.chars[self.pos + 1] == '|' {
      // A `$|...` template string is a STRING LITERAL, not code, and it is a
      // GENERAL one -- settled in `_verify/settle_0488_append_nextline.ps1` that `let x = $|<a>`
      // and `a + $|<b>` both ACCEPT, so this is not a slot only `<+` can fill. Without this
      // branch the `$` fell to lex_op's catch-all and reported "unexpected character", which is
      // what made moonbitlang/async `examples/http_file_server/main.mbt` read ZERO lines.
      last = self.lex_template_string()
      continue
    }
'@.Replace("`r`n", "`n")
    Repl = ''
    MustRed = '0488: the template string is an expression in its own right'
  }

  # M5 DEFECT C. A bare `=` is no longer treated as a label, so `\{value.to_string(radix=16)}` flushes
  # `radix` as a READ and `no visible binding for 'radix'` comes back -- the finding that reached
  # the inventory as async's first `actionable` and was fixed in the same increment.
  @{
    Name = 'M5 a labelled argument is read as a name again'
    File = $LEXER
    Find = @'
    } else if c == '=' &&
      self.pos < self.chars.length() &&
      self.chars[self.pos] != '=' &&
      self.chars[self.pos] != '>' {
'@.Replace("`r`n", "`n")
    Repl = @'
    } else if false {
'@.Replace("`r`n", "`n")
    MustRed = '0488: a labelled argument inside an interpolation is not a read'
  }

  # M6 THE CARVE-OUT, AND IT IS A SEPARATE MUTATION BECAUSE IT FAILS IN THE OPPOSITE DIRECTION.
  # Treating EVERY `=` as a label -- including `==` and `=>` -- would fix M5's finding by deleting
  # reads that are real, so `\{a == b}` and `\{nothing.map(x => x + 1).length()}` stop being reported
  # and the toolchain still accepts them. This is the row that says the fix is a carve-out and not a
  # blanket, and it is the positive control for M5's row.
  @{
    Name = 'M6 every = is treated as a label, so == and => stop reading their names'
    File = $LEXER
    Find = @'
      self.chars[self.pos] != '=' &&
      self.chars[self.pos] != '>' {
'@.Replace("`r`n", "`n")
    Repl = @'
      true {
'@.Replace("`r`n", "`n")
    MustRed = '0488: equality and a lambda still read their names inside an interpolation'
  }
)

Write-MutationGateVerdict -Name '0488'
if ($script:MutationGateFailures.Count -gt 0) { exit 1 }
exit 0
