# Mutation gate 0500 -- THE NOTICE LABEL, AND THE ONE PREDICATE BEHIND IT.
#
# WHAT THIS INCREMENT IS. Every ParseError the tool rendered carried the label
# `error:`, including the ones that are not errors at all. "match expression is
# outside the analyzed subset; it was read but not analysed" is a DECLARED
# SCOPE LIMIT of this analyzer, and a reader who sees `error:` on it has been
# told their code is wrong when the analyzer is the one that did not read it.
#
# The fix is one predicate -- `Report::is_notice` -- and one label function
# that uses it. FParse is ONE family with TWO meanings, and the question "is
# this a scope limit or a defect?" is not "is this FParse?":
#
#   deliberate  `Parser::note_skip` and `moonfiles`' subset skip
#   genuine     the lexer's eight malformed-literal reports, `moonfiles`'
#               eight malformed-interface reports, and the parser's `err()`
#
# MEASURED (2026-10-30), with the per-file printing cap lifted so the count is
# the whole finding set: across the seven corpora and this repository's own
# source, 23,331 rendered ParseError lines, EVERY ONE of them a deliberate
# exclusion. So the two predicates agree NUMERICALLY on today's corpora --
# which is why this increment moves no count -- and the gate below is about
# the RULE, not about the numbers.
#
# EVERY MUTATION BELOW NAMES THE TEST THAT MUST GO RED. A mutation that kills
# some other test is not evidence: the test named here is the one that pins the
# rule, so the kill is the rule's own.
#
# WHAT IS NOT IN THIS GATE, AND WHY. The CLI's NOTICE COUNT (`sa/main.mbt`) is
# not mutated here. The old predicate and the new one agree numerically on
# every corpus -- measured -- so a counter mutation would be invisible to the
# suite, and a mutation nobody can kill is a comment. What holds the counter is
# `_verify/check_notice_labels.ps1`, which reads the tool's own rendered output
# and the four producer paths, and the corpus pins, which are unchanged by
# this increment and would move if the count moved.
#
# ANCHORS ARE WRITTEN AGAINST THE POST-`moon fmt` SOURCE, and every one of them
# is UNIQUE in its file -- the harness mutates the FIRST match, and a second
# copy would never be verified.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'mutate_lib.ps1')

$REPORT = 'src\report\report.mbt'

Invoke-MutationGate -Name '0500' -Target 'wasm' -Mutations @(

  # M1 THE PREDICATE GOES BACK TO BEING "IS IT FParse?". This is the OLD bug,
  # written as a mutation: the marker is dropped, so every FParse is a notice
  # again -- including the lexer's malformed literals and `moonfiles`'
  # malformed interface text, which are defects. The test that says a genuine
  # defect is not a notice goes red.
  #
  # 0508 RE-ANCHORED THIS ONE. The scope-limit question used to be the whole
  # of `Report::is_notice`; the demotion made `is_notice` the answer to TWO
  # questions and moved the scope-limit half into `is_declared_scope_limit`.
  # The rule being pinned did not move -- the scope-limit question is still
  # "the family AND the marker" -- so the anchor moved with the code rather
  # than being re-typed. An anchor that stops matching is a mutation that
  # never happens.
  @{
    Name = 'M1 the notice predicate stops asking whether it is a scope limit'
    File = $REPORT
    Find = @'
pub fn Report::is_declared_scope_limit(self : Report) -> Bool {
  self.family == @core.FParse && is_scope_limit(self.message)
}
'@.Replace("`r`n", "`n")
    Repl = @'
pub fn Report::is_declared_scope_limit(self : Report) -> Bool {
  self.family == @core.FParse
}
'@.Replace("`r`n", "`n")
    MustRed = 'every genuine defect is NOT a notice'
  }

  # M2 THE PREDICATE STOPS ASKING WHICH FAMILY IT IS. The marker alone decides,
  # so any message that happens to carry the word is a notice -- including one
  # on a family that is not FParse at all, which would be a normal defect
  # relabelled and stopped counting. The test that says the marker alone does
  # not make a notice goes red.
  #
  # 0508 RE-ANCHORED THIS ONE TOO, for the same reason as M1: the scope-limit
  # question moved into `is_declared_scope_limit`, and the marker-alone rule
  # moved with it.
  @{
    Name = 'M2 the notice predicate stops asking which family it is'
    File = $REPORT
    Find = @'
pub fn Report::is_declared_scope_limit(self : Report) -> Bool {
  self.family == @core.FParse && is_scope_limit(self.message)
}
'@.Replace("`r`n", "`n")
    Repl = @'
pub fn Report::is_declared_scope_limit(self : Report) -> Bool {
  is_scope_limit(self.message)
}
'@.Replace("`r`n", "`n")
    MustRed = 'the marker alone does not make a notice'
  }

  # M3 THE LABEL GOES BACK TO "error". The predicate is untouched, so this
  # mutation is invisible to every test about the predicate -- which is the
  # point of having a test about the LABEL. The renderer is what a reader
  # sees, and the renderer is what regressed.
  @{
    Name = 'M3 a scope limit is labelled error again'
    File = $REPORT
    Find = @'
  if self.is_notice() {
    return "notice"
  }
'@.Replace("`r`n", "`n")
    Repl = @'
  if self.is_notice() {
    return "error"
  }
'@.Replace("`r`n", "`n")
    MustRed = 'the rendered label is notice for a notice and error for a defect'
  }

  # M4 THE MARKER NARROWS. "subset" becomes "analyzed subset", which every
  # PROGRAM-frontend message carries and the LITERATE frontend's does not
  # ("outside the analyzer's MoonBit subset"). So one deliberate exclusion --
  # the literate frontend's fence skip -- stops being a scope limit and goes
  # back to being an `error:`. The test that says every deliberate exclusion is
  # a notice goes red.
  @{
    Name = 'M4 the marker narrows to the program frontend''s wording'
    File = $REPORT
    Find = @'
fn is_scope_limit(message : String) -> Bool {
  message.contains("subset")
}
'@.Replace("`r`n", "`n")
    Repl = @'
fn is_scope_limit(message : String) -> Bool {
  message.contains("analyzed subset")
}
'@.Replace("`r`n", "`n")
    MustRed = 'every deliberate exclusion is a notice'
  }
)
