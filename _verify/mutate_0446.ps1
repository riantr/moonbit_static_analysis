# Mutation gate 0446 -- the block-string CLOSER was wrong, and wrong silently.
#
# On the harness: no runner of its own, all six rules from `_verify/mutate_lib.ps1`
# apply.
#
# THE DEFECT. `lex_block_string` closed the string at ANY line-leading `#|`. That
# pairs markers as opener/closer alternately, so a block whose lines all carry text
# after the marker -- the way proton 0.3.4 `facade_types.mbt:236-246` is written --
# closes at its FIRST line and re-opens on the bare `#|`, which then runs to end of
# input. The file is reported "unterminated block string literal", which sets
# `first_error_line`, which truncates the trusted region at line 246 while the enum
# declaring `CookieWaiting` and `CookieCompleted` sits at 589.
#
# A file truncated past its declarations contributes NOTHING to the cross-file symbol
# table, so the sibling that USES those names was told they were undefined: three
# findings in three files, from one lexer predicate.
#
# THE RULE, settled by VALUE in `_verify/settle_0446_block_string.ps1` (9/9, positive
# control green). `moon check` accepts every shape of this construct, so acceptance
# measures nothing and only the printed value settles it.
#
#   M1  The closer stops requiring a blank rest of line -- i.e. the old rule back.
#   M2  The closer requires MORE than the toolchain asks: it must be at column 0.
#   M3  A line-leading `#|` stops being a segment boundary (all one string).
#   M4  The value goes back to being accumulated raw, joined by newlines.
#   M5  The closer stops contributing its empty final segment.
#
# M2 is the direction that is easy to get wrong from the other side: an UNINDENTED
# closer is what the old header's `#|AAA\n  #|BBB` line half-claimed, and the
# settle measured it legal (`blank_closer`, `#|   ` with trailing spaces, still
# closes). Rejecting an indented closer would break real code, so it is pinned.
#
# RE-ANCHORED TWICE, and the pre-flight is what noticed -- not a failing test. M3 and M5
# both anchored on `segs.push(cur.to_string().trim().to_string())`, and a lint fix
# arriving from somewhere else entirely rewrote that expression to `to_owned()`
# (`StringView::to_string` is deprecated). Nothing about the CLOSER RULE changed; two
# anchors simply stopped matching, and the gate reported "2 pattern(s) absent. No suite
# was run" rather than a green run that meant nothing. The anchors moved to the new
# spelling and were re-verified. The same thing happens to a mutation when prose
# grows around it, so: re-anchor, never retire.

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'mutate_lib.ps1')

Invoke-MutationGate -Name 'M1..M5' -Target 'js' -Mutations @(

  @{
    Name = 'M1 the closer stops requiring a blank rest of line (the old rule)'
    File = 'src\lexer\lexer.mbt'
    Find = @'
      if j >= n || self.chars[j] == '\n' {
'@.Replace("`r`n", "`n")
    Repl = @'
      if j >= 0 || j < 0 {
'@.Replace("`r`n", "`n")
    MustRed = 'block string: a #| with text after it is a content line'
    Prove = @'
The first version of this mutation deleted the `let mut j` line as well, and that
is worth recording because it is the recurring shape here: the harness reported
COMPILE-ERR -- no `Total tests:` line -- and a mutation that cannot build measures
the compiler, not the guard. `j` is still read further down, so removing its
declaration breaks the build. The condition is mutated instead, and `j >= 0 || j < 0`
keeps it READ so nothing goes unused.

The mutation is exactly the old rule: any line-leading `#|` closes.
'@.Replace("`r`n", "`n")
  },

  @{
    Name = 'M2 the closer is demanded at column 0 (indented closers rejected)'
    File = 'src\lexer\lexer.mbt'
    Find = @'
      if j >= n || self.chars[j] == '\n' {
'@.Replace("`r`n", "`n")
    Repl = @'
      if self.col == 1 && (j >= n || self.chars[j] == '\n') {
'@.Replace("`r`n", "`n")
    MustRed = 'block string: an indented #| still closes'
    Prove = @'
A weak-looking mutation that is not weak, and the reason is worth recording.

The replacement demands the closer sit at COLUMN 0. `moon fmt` and the settle both
say that is not the rule: `#|abc` / `  #|def` / `#|   ` closes fine, and the
`blank_closer` case has TRAILING SPACES after the marker and still closes. A closer
that has to be unindented rejects valid MoonBit, so this is the direction that would
cost real code -- and it is the one a future reader is most likely to "fix" into the
implementation by accident, having seen the old header's `#|AAA\n  #|BBB` line.

THE FIRST VERSION OF THIS PIN WAS WRONG, and the harness said so rather than letting
it pass. It named "a blank line inside the block does not end it", and that test did
NOT go red -- its closer turned out to be at column 0 after all. The truth is worse
and better than that: SEVEN tests were written for this construct and every one of
them put the closer at column 0, because they were written by copying each other.
The only test in the suite that distinguished column-0 from indented was an unrelated
block-string test that happened to indent its markers. The rule was pinned by
ACCIDENT, and an accident is not a guard.

`block string: an indented #| still closes` and the trailing-blanks case beside it
were added because of that, and the old header's one correct claim -- that the closer
may be indented -- is now pinned by a test of its own instead of by coincidence.
'@.Replace("`r`n", "`n")
  },

  @{
    Name = 'M3 a line-leading #| stops opening a segment'
    File = 'src\lexer\lexer.mbt'
    Find = @'
      // NOT a closer: this line begins a new SEGMENT and its text is content.
      segs.push(cur.to_string().trim().to_owned())
'@.Replace("`r`n", "`n")
    Repl = @'
      // NOT a closer: this line begins a new SEGMENT and its text is content.
      let _ = cur.to_string().trim().to_owned()
'@.Replace("`r`n", "`n")
    MustRed = 'block string: a #| with text after it is a content line'
    Prove = @'
Without the push, the text before a line-leading `#|` never becomes a segment of its
own and the whole block collapses.

TWO VERSIONS OF THIS MUTATION FAILED TO COMPILE, which is the recurring shape of
this gate's first attempt and worth writing down rather than fixing quietly:

  - removing `cur = StringBuilder()` entirely leaves a `let mut` that is never
    reassigned, and `moon test` here FAILS on `unused_mut` -- no `Total tests:` line,
    so the harness reports COMPILE-ERR and the mutation measures the compiler.
  - the first attempt at the push also added a second `self.pos += 2`, which
    double-consumes the marker. Same verdict, different cause.

The marker has to be consumed exactly once either way, and `cur` has to stay
assigned. Only the PUSH is the property under test.
'@.Replace("`r`n", "`n")
  },

  @{
    Name = 'M4 the value is accumulated raw, joined by newlines again'
    File = 'src\lexer\lexer.mbt'
    Find = @'
  let s = segs.join(" ")
'@.Replace("`r`n", "`n")
    Repl = @'
  let s = segs.join("\n")
'@.Replace("`r`n", "`n")
    MustRed = 'block string: a #| with text after it is a content line'
    Prove = @'
Pinned on the VALUE, and that is the only place the join can be observed -- the
separator never appears in a span, so the mutation is otherwise silent.

Worth stating plainly because it is a whole extra property that was wrong before
0.4.36 and nobody noticed: the value is not newline-joined under EITHER the old or
the new closer rule. Measured, `#|line one {` / `  #|line two` / `#|}` / `#|` is
"line one { line two } " -- segments TRIMMED and joined by a single SPACE. "AAA\nBBB"
was never the string, and three tests in `lexer_test.mbt` asserted it was.

This is also the one mutation in the gate with no relationship to the closer rule at
all. It is here because a gate that only covers the property that was diagnosed is a
gate that will not catch the property nobody has looked at yet.
'@.Replace("`r`n", "`n")
  },

  @{
    Name = 'M5 the closer stops contributing its empty final segment'
    File = 'src\lexer\lexer.mbt'
    Find = @'
        segs.push(cur.to_string().trim().to_owned())
        segs.push("")
'@.Replace("`r`n", "`n")
    Repl = @'
        segs.push(cur.to_string().trim().to_owned())
'@.Replace("`r`n", "`n")
    MustRed = 'block string: a bare #| closes and contributes an empty segment'
    Prove = @'
The trailing space is the ONLY observable difference between a block that closes and
one that runs to end of input: `#|abc` / `#|def` / `#|` is "abc def " while
`#|abc` / `#|def` is "abc def". Both are legal MoonBit and both were measured, so a
change here cannot be justified by "the file still compiles" -- only by the value.
'@.Replace("`r`n", "`n")
  }
)

Write-MutationGateVerdict -Name '0446'
if ($script:MutationGateFailures.Count -gt 0) { exit 1 }
exit 0
