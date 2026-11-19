# Mutation gate 0615 -- `lexscan`, THE LEXICAL SCAN, and the arms it carries.
#
# WHAT THIS INCREMENT IS. One construct the analyzer's subset did not know, and
# three false positives it produced because of it.
#
#   `lexscan <subject> [with <strategy>] { arms }` is MoonBit's STREAMING
#   regex-lexer form of a match. The subject is a SCANNER -- a `Lexbuf`, a
#   `StringScanner`, or anything implementing `Scannable` -- and the arms are
#   patterns whose first element is a REGEX LITERAL.
#
#   It is NOT a name, and reading it as one produced `undefined variable
#   'lexscan'` -- a FALSE POSITIVE on code `moon check` accepts. MEASURED on
#   the re-pinned corpus (`moonbitlang/core` `0.1.20261117+06da1ed44`), three
#   sites, and every one of them in ORDINARY CODE rather than in a test body:
#
#       lexbuf/read_line.mbt:37
#       lexbuf/read_line_test.mbt:53
#       lexbuf/async_read_line_test.mbt:29
#
#   The OLD corpus used `lexscan` in six files and the analyzer reported
#   nothing at all, because every one of those uses was in a place the analyzer
#   never reads -- a `test` body, or a doc comment. The construct was in the
#   corpus the whole time and in no analysed code at all, which is the same
#   shape the 0496 note records for `radix`: a real false positive that an
#   inventory of the files the analyzer CAN read cannot see.
#
#   THE FIX IS A PARSER PRODUCTION, and it is the same shape as the one 0496
#   gave `lexmatch` -- with ONE DIFFERENCE, which is the difference M3 pins:
#   a `lexmatch`'s arms are SKIPPED, because an arm body ends in `next` and
#   `next` is not in this frontend's statement grammar, while a `lexscan` arm
#   body is an ordinary expression, so the arms are READ.
#
# EVERY MUTATION BELOW NAMES THE TEST THAT MUST GO RED. A mutation that kills
# some other test is not evidence: the test named here is the one that pins the
# rule, so the kill is the rule's own.
#
# ANCHORS ARE WRITTEN AGAINST THE POST-`moon fmt` SOURCE, and every one of them
# is UNIQUE in its file -- the harness mutates the FIRST match, and a second
# copy would never be verified.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'mutate_lib.ps1')

$PARSER = 'src\parser\parser.mbt'
$LEXER = 'src\lexer\lexer.mbt'

Invoke-MutationGate -Name '0615' -Target 'wasm' -Mutations @(

  # M1 THE CONSTRUCT IS NOT A NAME. The arm stops matching, so `lexscan` is
  # read as an identifier and the false positive comes back.
  #
  # THE TEST THAT KILLS IT is the one that says the file PARSES. The finding
  # itself cannot kill this mutation: a name read where a construct belongs is
  # not a clean parse, so the file stops at the `lexscan` line and the
  # undefined-name finding is WITHHELD rather than reported -- the very
  # silence the 0615 corpus measurement recorded as `read only up to their
  # first parse error`. A reader that killed this mutation on the finding
  # would be killing it for the wrong reason.
  @{
    Name = 'M1 a lexscan is read as a name'
    File = $PARSER
    Find = @'
    TName("lexscan") => {
'@.Replace("`r`n", "`n")
    Repl = @'
    TName("lexscan_disabled") => {
'@.Replace("`r`n", "`n")
    MustRed = '0615: a lexscan is a match whose subject is carried'
  }

  # M2 THE `with` CLAUSE IS CONSUMED. Without it, the strategy word is left in
  # the token stream, the arms are not read, and the parse breaks.
  @{
    Name = 'M2 the with-strategy clause is not consumed'
    File = $PARSER
    Find = @'
        if self.at_name("longest") || self.at_name("first") {
          let _ = self.bump()
        }
'@.Replace("`r`n", "`n")
    Repl = @'
        if self.at_name("longest_disabled") || self.at_name("first_disabled") {
          let _ = self.bump()
        }
'@.Replace("`r`n", "`n")
    MustRed = '0615: a lexscan with a strategy clause is read'
  }

  # M3 THE ARMS ARE READ, and this is the mutation that pins the DIFFERENCE
  # from `lexmatch`. The arms are skipped whole instead, exactly as a
  # `lexmatch`'s are, and the construct falls back to the `lexmatch` shape:
  # an empty arm list and a notice.
  #
  # It is the difference that MATTERS, and it is not a matter of taste. A
  # skipped block leaves a HOLE in the frame of the enclosing function, and a
  # hole silences `UnusedLocal` and `UnusedParam` for that WHOLE function --
  # which is the treatment `pipeline_0469` records as making the family
  # unobservable. The arms of a `lexscan` are ordinary expressions, so there
  # is nothing to stop them from being read, and reading them keeps the
  # enclosing function's frame whole.
  @{
    Name = 'M3 the arms of a lexscan are skipped whole'
    File = $PARSER
    Find = @'
      let snap = self.snapshot()
      let arms = self.parse_match_arms()
      if self.error_count != snap.errors {
        self.restore(snap)
        self.skip_braces()
        self.note_skip(
          "lexscan expression is outside the analyzed subset; it was read but not analysed",
          sp,
        )
        { span: sp, kind: @ast.EMatch(subject, []), }
      } else {
        { span: sp, kind: @ast.EMatch(subject, arms), }
      }
'@.Replace("`r`n", "`n")
    Repl = @'
      self.skip_braces()
      self.note_skip(
        "lexscan expression is outside the analyzed subset; it was read but not analysed",
        sp,
      )
      { span: sp, kind: @ast.EMatch(subject, []), }
'@.Replace("`r`n", "`n")
    MustRed = '0615: the arms of a lexscan are read'
  }

  # M4 THE `first` STRATEGY IS READ. The toolchain's own error message says
  # "Only `first` (the default one) and `longest` match strategies are
  # supported", so the two strategies are the two words -- and a reader that
  # knew only `longest` would leave `first` in the stream, which is M2's
  # defect with a different word. The corpus uses NEITHER strategy, so this
  # mutation survives every corpus measurement and is killed only by the row
  # that names it. That is the whole reason the row is there.
  @{
    Name = 'M4 the first strategy is not read'
    File = $PARSER
    Find = @'
        if self.at_name("longest") || self.at_name("first") {
'@.Replace("`r`n", "`n")
    Repl = @'
        if self.at_name("longest") {
'@.Replace("`r`n", "`n")
    MustRed = '0615: a lexscan with the first strategy is read'
  }

  # M5 THE KEYWORD LIST. `lexscan` IS SYNTAX, NOT A NAME, and the lexer keyword
  # list is where the codebase says so -- it is the one place that asks "is this
  # a name to resolve?".
  #
  # IT IS LOAD-BEARING, and the test that says so is the one that pins the
  # PREDICATE: `is_moonbit_keyword` is the single answer to "is this word
  # syntax?", and a word that is not on the list is resolved as a binding. The
  # 0496 gate could only declare this mutation SURVIVED, because 0496 had no
  # row for the predicate -- and a mutation declared SURVIVED is a mutation
  # that is allowed to go unnoticed. This one has a row, so it is killed.
  #
  # AND THE CORPUS'S FINDINGS DO NOT DEPEND ON IT, which is the other half of
  # the truth and is worth keeping: every `lexscan` in the pinned corpus is in
  # EXPRESSION position, where M1's arm consumes it, so no name ever reaches
  # the frame and the list cannot change a finding. The entry is what a
  # `lexscan` in a PATTERN or inside an interpolation would stand on.
  @{
    Name = 'M5 the keyword list loses lexscan'
    File = $LEXER
    Find = @'
    | "lexscan"
'@.Replace("`r`n", "`n")
    Repl = @'
    | "lexscan_disabled"
'@.Replace("`r`n", "`n")
    MustRed = '0615: lexscan is a keyword'
  }
)

# THE VERDICT, AND THE EXIT THAT CARRIES IT. These two lines are what make this
# gate ABLE TO FAIL, and they are here because 0615 MEASURED that five of the
# gates in this directory did not have them: the harness RECORDS a failure in
# `$script:MutationGateFailures`, and without these lines that record goes
# nowhere -- the script ends normally, `powershell -File` exits 0, the
# transcript carries no `GATE FAILED` line, and `release.ps1`'s `Run-Gate`
# reports the gate as PASS.
#
# `check_gate_roster.ps1` now checks that every numbered gate carries both
# lines, so this cannot rot back into a comment.
Write-MutationGateVerdict -Name '0615 mutation gate'
if ($script:MutationGateFailures.Count -gt 0) { exit 1 }
