# Mutation gate 0479 -- U+FEFF, the BYTE-ORDER MARK, skipped by the lexer.
#
# WHAT THIS PINS. `_verify/corpus_backlog.ps1` reported one `unexpected character '<U+FEFF>'`
# naming one file: `riantr/moonbit_labeler/0.2.13/app_moui/labeler_ui_test.mbt`, first three
# bytes EF BB BF. A sweep of every `.mbt` under `.repos` finds it is the ONLY file in the
# corpus that starts with one. Before this change the mark reached `lex_op`'s catch-all, so
# the lexer refused a character the toolchain does not object to.
#
# Measured: moonbit_labeler `parsed 36 -> 37`, `unreliable 16 -> 0`, `withheld 16 -> 0`,
# `notices 776 -> 791`, `actionable 0 -> 0`. That is the WHOLE corpus: 37/37 files parse and
# nothing sits in the reliability quarantine any more.
#
# `_verify/settle_0479_bom.ps1`, 3 controls + 5 rows, GATE OK:
#   ACCEPT  the corpus's first three lines, byte for byte including the mark
#   ACCEPT  a mark before a declaration / before a `///|` / on an empty file
#   ACCEPT  a mark MIDFILE          <- the discriminator
#   ACCEPT  a mark inside a string literal
#
# M2 IS THE MUTATION THAT KEEPS THE FIX THE SIZE THE SETTLE LICENSED. The mark is legal
# wherever it appears, so a "strip a three-byte preamble" implementation passes the corpus
# file -- the only file anyone has seen fail -- and nothing else. M2 builds exactly that and
# the midfile row kills it.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'mutate_lib.ps1')

$LEXER = 'src\lexer\lexer.mbt'

Invoke-MutationGate -Name '0479' -Target 'wasm' -Mutations @(

  # M1 THE GUARD IS GONE. The mark falls through to `lex_op` again and the file is refused,
  # which is the defect this increment exists to remove.
  @{
    Name = 'M1 the mark is not skipped at all'
    File = $LEXER
    Find = "    if c == ' ' || c == '\t' || c == '\r' || c == '\u{FEFF}' {"
    Repl = "    if c == ' ' || c == '\t' || c == '\r' {"
    MustRed = '0479: a byte-order mark before code is skipped'
  }

  # M2 THE MARK IS A PREAMBLE, NOT A CHARACTER. This is the narrow fix: it unblocks the one
  # corpus file, passes every ACCEPT control, and leaves `1 <mark> + 2` refused -- which the
  # settle says the compiler accepts. A fix verified by its own symptom.
  @{
    Name = 'M2 only a leading mark is skipped (a preamble, not a character)'
    File = $LEXER
    Find = "    if c == ' ' || c == '\t' || c == '\r' || c == '\u{FEFF}' {"
    Repl = "    if c == ' ' || c == '\t' || c == '\r' || (c == '\u{FEFF}' && self.pos == 0) {"
    MustRed = '0479: a byte-order mark inside an expression is skipped (control)'
  }

  # M3 THE GUARD IS A RANGE. The settle licenses EXACTLY ONE character; U+FFFE is the one
  # immediately before it in Unicode, and a guard that reached for "the byte-order marks"
  # takes it. The control row is that character for exactly this reason.
  @{
    Name = 'M3 the guard swallows the neighbouring code point too'
    File = $LEXER
    Find = "    if c == ' ' || c == '\t' || c == '\r' || c == '\u{FEFF}' {"
    Repl = "    if c == ' ' || c == '\t' || c == '\r' || c == '\u{FFFE}' || c == '\u{FEFF}' {"
    MustRed = '0479: the character beside the mark is still refused (control)'
  }

  # M4 THE WRONG CHARACTER. Off-by-one-in-Unicode, and the most likely shape of a mistake
  # here: the mark is U+FEFF and a reader reaches for U+FEFE. It reads as plausible, it
  # compiles, and it refuses every file that has the mark.
  @{
    Name = 'M4 the guard matches the code point before the mark'
    File = $LEXER
    Find = " || c == '\u{FEFF}'"
    Repl = " || c == '\u{FEFE}'"
    MustRed = '0479: a byte-order mark before code is skipped'
  }
)

Write-MutationGateVerdict -Name '0479'
if ($script:MutationGateFailures.Count -gt 0) { exit 1 }
exit 0
