# Mutation gate 0508 -- THE CONFIDENCE DEMOTION.
#
# WHAT THIS INCREMENT IS. The confidence AXIS shipped in 0507: every finding
# carries `high`, `low` or `undecided`. Nothing acted on it. The clause of the
# transfer that was still open is the one `bandit` implements as a filter over
# two axes -- an issue carries a severity AND a confidence, and the filter
# needs BOTH to clear the thresholds.
#
# 0508 is that filter:
#
#   Report::is_notice()  =  is_declared_scope_limit()  ||  confidence() == Low
#
# A finding the analyzer does not stand behind is rendered `notice:` and is
# counted in `notices` rather than in `actionable`. It is DEMOTED, NOT HIDDEN:
# it keeps its family, its stable id, its confidence and its line.
#
# NINE RULES, AND EVERY MUTATION BELOW NAMES THE TEST THAT MUST GO RED:
#
#   M1, M2     the demotion predicate: a low-confidence finding is a notice,
#              and a declared scope limit is still a notice
#   M3         the demoted finding is PRINTED, never aggregated
#   M4         the rendered label is the notice label
#   M5         the scope-limit question is the family AND the marker
#   M6         the notice COUNT is the demoted findings too
#   M7         the mermaid note says which KIND of notice it is
#   M8         the demoted finding leaves the actionable count
#   M9         the JSON record's confidence comes from the axis
#
# ANCHORS ARE WRITTEN AGAINST THE POST-`moon fmt` SOURCE and every one of them
# is UNIQUE in its file -- the harness mutates the FIRST match, and a second
# copy would never be verified.
#
# THE TARGET IS `wasm`, and it has to be: the `src/sa` and `src/report` tests
# do not run on the `js` and `wasm-gc` targets (MEASURED: js 1196 tests,
# wasm-gc 1196, wasm 1330 -- the 134-test difference is the async packages),
# so a gate run on `js` would report SURVIVED for every mutation in this file
# that touches `src/sa` or `src/report`.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'mutate_lib.ps1')

$REPORT  = 'src\report\report.mbt'
$SA      = 'src\sa\main.mbt'
$MERMAID = 'src\sa\mermaid.mbt'
$JSON    = 'src\jsoncli\main.mbt'

Invoke-MutationGate -Name '0508' -Target 'wasm' -Mutations @(

  # M1 A LOW-CONFIDENCE FINDING IS A NOTICE. The whole increment. Without the
  # clause the axis is a column: the finding is rendered `error:` and counted as
  # actionable, which says "the analyzer checked this and it is wrong" about a
  # finding the analyzer says it could not check.
  @{
    Name = 'M1 a low-confidence finding is not a notice'
    File = $REPORT
    Find = @'
pub fn Report::is_notice(self : Report) -> Bool {
  self.is_declared_scope_limit() || self.confidence() == @core.Low
}
'@.Replace("`r`n", "`n")
    Repl = @'
pub fn Report::is_notice(self : Report) -> Bool {
  self.is_declared_scope_limit()
}
'@.Replace("`r`n", "`n")
    MustRed = 'demotion: a low-confidence finding is a notice'
  }

  # M2 AND A DECLARED SCOPE LIMIT IS STILL A NOTICE. The other kind of notice
  # did not move: the analyzer saying "this construct is outside the analyzed
  # subset" is the analyzer saying it could not DECIDE at all. Dropping the
  # clause would put it back to `error:`, which is what 0505 and 0506 had to
  # undo.
  @{
    Name = 'M2 a declared scope limit is not a notice'
    File = $REPORT
    Find = @'
  self.is_declared_scope_limit() || self.confidence() == @core.Low
'@.Replace("`r`n", "`n")
    Repl = @'
  self.confidence() == @core.Low
'@.Replace("`r`n", "`n")
    MustRed = 'demotion: a scope limit is still undecided and still a notice'
  }

  # M3 THE DEMOTED FINDING IS PRINTED, NEVER AGGREGATED. This is the mutation
  # that reproduces the FIRST implementation of this increment, which used
  # `!r.is_notice()` here -- and therefore aggregated the demoted finding with
  # the scope limits, and took the name and the place off it. That is HIDING
  # it, and it is why the 0505 and 0507 settles went red.
  @{
    Name = 'M3 the demoted finding is aggregated away'
    File = $SA
    Find = @'
    if !r.is_declared_scope_limit() {
      printed.push(r)
    } else if is_hiding(r.span, hiding) {
'@.Replace("`r`n", "`n")
    Repl = @'
    if !r.is_notice() {
      printed.push(r)
    } else if is_hiding(r.span, hiding) {
'@.Replace("`r`n", "`n")
    MustRed = 'demotion: a demoted finding is printed, never aggregated'
  }

  # M4 THE LABEL IS THE NOTICE LABEL. The demotion changes what the finding is
  # CALLED, and a finding the analyzer does not stand behind that is still
  # rendered `error:` has not been demoted at all -- it has only been counted
  # differently.
  @{
    Name = 'M4 the rendered label is not the notice label'
    File = $REPORT
    Find = @'
pub fn Report::severity_label(self : Report) -> String {
  if self.is_notice() {
    return "notice"
  }
'@.Replace("`r`n", "`n")
    Repl = @'
pub fn Report::severity_label(self : Report) -> String {
'@.Replace("`r`n", "`n")
    MustRed = 'demotion: a low-confidence finding is a notice'
  }

  # M5 THE SCOPE-LIMIT QUESTION IS THE FAMILY AND THE MARKER. `FParse` is ONE
  # family carrying TWO meanings: a deliberate exclusion and a genuine defect
  # (an unterminated string literal, a malformed interface line). Dropping
  # the marker makes every FParse report a scope limit, so a real defect is
  # demoted as a thing the analyzer did not read.
  @{
    Name = 'M5 the scope-limit question ignores the marker'
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
    MustRed = 'demotion: the scope-limit question and the low-confidence question differ'
  }

  # M6 THE NOTICE COUNT IS THE DEMOTED FINDINGS TOO. The count was an inline
  # loop in two places -- once per file, and once over what was printed -- and
  # two inline loops are two copies of the question. They are one function now,
  # and this mutation is that function asking the wrong question.
  @{
    Name = 'M6 the notice count misses the demoted findings'
    File = $SA
    Find = @'
pub fn count_notices(reports : Array[@report.Report]) -> Int32 {
  let mut n = 0
  for r in reports {
    if r.is_notice() {
      n += 1
    }
  }
  n
}
'@.Replace("`r`n", "`n")
    Repl = @'
pub fn count_notices(reports : Array[@report.Report]) -> Int32 {
  let mut n = 0
  for r in reports {
    if r.is_declared_scope_limit() {
      n += 1
    }
  }
  n
}
'@.Replace("`r`n", "`n")
    MustRed = 'demotion: the notice count is the demoted findings too'
  }

  # M7 THE MERMAID NOTE SAYS WHICH KIND OF NOTICE IT IS. The note under a
  # notice node used to name the FAMILY -- "ParseError covers a form this
  # analyzer does not model" -- which was true while a notice was always a
  # scope limit, and became a FALSE STATEMENT under a demoted finding: a name
  # the analyzer could not resolve is not a form it does not model.
  @{
    Name = 'M7 the notice note is not kind-aware'
    File = $MERMAID
    Find = @'
        let body = if rep.is_declared_scope_limit() {
'@.Replace("`r`n", "`n")
    Repl = @'
        let body = if rep.is_notice() {
'@.Replace("`r`n", "`n")
    MustRed = 'a demoted finding carries the not-sure note'
  }

  # M8 THE DEMOTED FINDING LEAVES THE ACTIONABLE COUNT. The SUMMARY's
  # `actionable` is the per-file finding count MINUS the notice count, so a
  # demoted finding leaves it -- and the identity
  # `actionable + notices + unreliable = total` still holds. Putting the
  # notices back breaks the identity the SUMMARY prints.
  @{
    Name = 'M8 the demoted finding stays in the actionable count'
    File = $SA
    Find = @'
    actionable += n - v.notices
'@.Replace("`r`n", "`n")
    Repl = @'
    actionable += n
'@.Replace("`r`n", "`n")
    MustRed = 'SUMMARY identity: actionable + notices + unreliable == total'
  }

  # M9 THE JSON RECORD'S CONFIDENCE COMES FROM THE AXIS.
  #
  # This is a DECLARED SURVIVOR, and the argument travels with the result.
  # The `src/jsoncli` package has no test file -- `moon test` builds it but
  # runs no test in it -- so the suite cannot see the JSON record at all, and
  # every mutation of that record would come out SURVIVED whether it broke
  # anything or not. The place it IS observable is
  # `_verify/settle_0508_confidence_demotion.ps1`, whose row D11 reads the
  # source and checks that the record takes its severity from `severity_label`
  # and its confidence from `confidence().name()` -- so a JSON record that
  # computed its own confidence, or reported `error` about a finding the text
  # calls a `notice`, fails that settle, and that settle is a release-gate
  # stage.
  @{
    Name = 'M9 the JSON record hardcodes the confidence'
    File = $JSON
    Find = @'
    confidence: rep.confidence().name(),
'@.Replace("`r`n", "`n")
    Repl = @'
    confidence: "high",
'@.Replace("`r`n", "`n")
    Expect = 'SURVIVED'
    Prove = 'the src/jsoncli package has no test file, so `moon test` cannot observe the JSON record. The rule is pinned by _verify\settle_0508_confidence_demotion.ps1 row D11, which reads the source and checks that the record takes its severity from severity_label() and its confidence from confidence().name(); that settle is a release-gate stage.'
  }
)

Write-MutationGateVerdict -Name '0508'
if ($script:MutationGateFailures.Count -gt 0) { exit 1 }
exit 0
