# Mutation gate 0507 -- THE THREE TRANSFERS FROM BANDIT.
#
# WHAT THIS INCREMENT IS. Three things were ported from PyCQA's `bandit` (the
# plan is in NARRATIVE.md, section 0505), plus the disclosure they exist to
# enable:
#
#   1. A PER-FINDING CONFIDENCE AXIS. The severity says how bad a finding is
#      IF IT IS REAL; the confidence says how much the lens CHECKED. The three
#      values are `high` (the lens had the declaration, the signature or the
#      type in front of it), `low` (the lens was reasoning from a NAME alone)
#      and `undecided` (the lens could not decide at all).
#   2. STABLE FAMILY IDS AND A CHECKED PROFILE. An id is allocated and NEVER
#      RENUMBERED; a profile selects families by id; an unknown id is a
#      WARNING and an include/exclude intersection is an ERROR.
#   3. `nosec`. Per line, per family id or blanket, and a `nosec` that
#      suppressed NOTHING is reported as a finding of its own.
#
#   4. AND THE UNCHECKED-CALL DISCLOSURE, which is not a transfer and is the
#      reason transfer 1 exists: the calls the type lens could not check are
#      counted and disclosed, so "I could not check this" stops reading like
#      "there is nothing to report".
#
# FIFTEEN RULES, AND EVERY MUTATION BELOW NAMES THE TEST THAT MUST GO RED:
#
#   M1, M2     the confidence rule: a scope limit is `undecided`, a name-only
#              family is `low`
#   M3, M4     the id table: one id per family, contiguous, and the inverse
#              table the exact reverse of the forward one
#   M5         an unknown id names NO family
#   M6, M7     the rendered finding carries the id and the confidence
#   M8         a finding with no lens renders a dash, not an empty bracket
#   M9, M10    the profile keeps only what it was asked to keep, and drops only
#              what it was asked to drop
#   M11, M12   an unknown id WARNS, and an include/exclude overlap ERRORS
#   M13, M14   the `nosec` suppresses, and a stale one is reported
#   M15        the CLI carries the `--honor-nosec` flag through
#
# ANCHORS ARE WRITTEN AGAINST THE POST-`moon fmt` SOURCE and every one of them
# is UNIQUE in its file -- the harness mutates the FIRST match, and a second
# copy would never be verified.
#
# THE TARGET IS `wasm`, and it has to be: the `src/sa` tests do not run on the
# `js` and `wasm-gc` targets (MEASURED: js 1196 tests, wasm-gc 1196, wasm
# 1316 -- the 120-test difference is the async packages), so a gate run on `js`
# would report SURVIVED for every mutation in this file that touches `src/sa`.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'mutate_lib.ps1')

$CORE    = 'src\core\core.mbt'
$REPORT  = 'src\report\report.mbt'
$PROFILE = 'src\sa\profile.mbt'
$MAIN    = 'main.mbt'

Invoke-MutationGate -Name '0507' -Target 'wasm' -Mutations @(

  # M1 A SCOPE LIMIT IS `undecided`. The analyzer saying "this construct is
  # outside the analyzed subset" is the analyzer saying it could not DECIDE.
  # Reporting it at `high` would claim the opposite: that the lens read the
  # construct and found nothing wrong with it.
  @{
    Name = 'M1 a scope limit is not undecided'
    File = $REPORT
    Find = @'
pub fn Report::confidence(self : Report) -> @core.Confidence {
  if self.is_notice() {
    return @core.Undecided
  }
'@.Replace("`r`n", "`n")
    Repl = @'
pub fn Report::confidence(self : Report) -> @core.Confidence {
  if self.is_notice() {
    return @core.High
  }
'@.Replace("`r`n", "`n")
    MustRed = 'confidence: a scope limit is undecided'
  }

  # M2 A FAMILY THAT REASONS FROM A NAME ALONE IS `low`. `UndefinedName` is
  # the only one: the analyzer found no binding for the name, and the binding
  # it could not find may be in a file, or in a package, it was never given.
  # Reporting it at `high` would claim the lens had read the declaration.
  @{
    Name = 'M2 a name-only family is not low'
    File = $REPORT
    Find = @'
  if self.family == @core.FUndefinedName {
    return @core.Low
  }
'@.Replace("`r`n", "`n")
    Repl = @'
  if self.family == @core.FUndefinedName {
    return @core.High
  }
'@.Replace("`r`n", "`n")
    MustRed = 'confidence: a family that reasons from a name alone is low'
  }

  # M3 THE IDS ARE CONTIGUOUS FROM MSA-001. A family given a number outside the
  # run breaks the run, and every suppression written against the numbers
  # after it now names a different family. This is the "never renumbered"
  # property, made checkable.
  @{
    Name = 'M3 a family id is renumbered'
    File = $CORE
    Find = @'
    FArgType => "MSA-007"
'@.Replace("`r`n", "`n")
    Repl = @'
    FArgType => "MSA-013"
'@.Replace("`r`n", "`n")
    MustRed = 'the family ids are unique, contiguous from MSA-001, and reversible'
  }

  # M4 THE INVERSE TABLE IS THE EXACT INVERSE OF THE FORWARD ONE. Two tables
  # written down twice will disagree eventually, and a disagreement between
  # them is invisible: the analyzer would accept one spelling of an id and
  # not the other.
  @{
    Name = 'M4 the inverse table maps an id to the wrong family'
    File = $CORE
    Find = @'
    "MSA-007" => Some(FArgType)
'@.Replace("`r`n", "`n")
    Repl = @'
    "MSA-007" => Some(FOpMismatch)
'@.Replace("`r`n", "`n")
    MustRed = 'the family ids are unique, contiguous from MSA-001, and reversible'
  }

  # M5 AN UNKNOWN ID NAMES NO FAMILY. A lookup that defaulted to some family
  # would turn a typo in a profile or a suppression into a silent, wrong
  # selection -- and a `nosec` naming a family that does not exist has to
  # suppress nothing, so it has to be STALE.
  @{
    Name = 'M5 an unknown family id names a family'
    File = $CORE
    Find = @'
    "MSA-012" => Some(FStaleNosec)
    _ => None
'@.Replace("`r`n", "`n")
    Repl = @'
    "MSA-012" => Some(FStaleNosec)
    _ => Some(FParse)
'@.Replace("`r`n", "`n")
    MustRed = 'an unknown family id names no family'
  }

  # M6 THE RENDERED FINDING CARRIES THE ID. The bracket is the metadata slot,
  # and the id is what a consumer can pin across a rename.
  @{
    Name = 'M6 the rendered finding drops the family id'
    File = $REPORT
    Find = @'
  let meta = lens_tag(self.lenses) +
    ", " +
    self.family.id() +
    ", " +
    self.confidence().name()
'@.Replace("`r`n", "`n")
    Repl = @'
  let meta = lens_tag(self.lenses) +
    ", " +
    self.confidence().name()
'@.Replace("`r`n", "`n")
    MustRed = 'the rendered finding carries the id and the confidence in the bracket'
  }

  # M7 AND THE CONFIDENCE. The two halves of the same bracket, and the axis
  # is the reason the increment exists.
  @{
    Name = 'M7 the rendered finding drops the confidence'
    File = $REPORT
    Find = @'
  let meta = lens_tag(self.lenses) +
    ", " +
    self.family.id() +
    ", " +
    self.confidence().name()
'@.Replace("`r`n", "`n")
    Repl = @'
  let meta = lens_tag(self.lenses) +
    ", " +
    self.family.id()
'@.Replace("`r`n", "`n")
    MustRed = 'the rendered finding carries the id and the confidence in the bracket'
  }

  # M8 A FINDING WITH NO LENS RENDERS A DASH. The stale-suppression finding
  # is produced by the scanner and not by a lens, and an empty bracket would
  # read as a rendering accident.
  @{
    Name = 'M8 a finding with no lens renders an empty bracket'
    File = $REPORT
    Find = @'
    return "-"
'@.Replace("`r`n", "`n")
    Repl = @'
    return ""
'@.Replace("`r`n", "`n")
    MustRed = 'a finding with no lens renders a dash, not an empty bracket'
  }

  # M9 THE PROFILE'S INCLUDE SET IS APPLIED. A profile that ignored its own
  # include set would report everything, and the reader would have asked for
  # a subset and been given the whole thing. The mutation INVERTS the test
  # rather than disabling it, because a disabled branch is a different kind
  # of defect than a misread one.
  @{
    Name = 'M9 the profile ignores its include set'
    File = $PROFILE
    Find = @'
  if profile.include_ids.length() > 0 && !profile.include_ids.contains(id) {
    return false
  }
'@.Replace("`r`n", "`n")
    Repl = @'
  if profile.include_ids.length() > 0 && profile.include_ids.contains(id) {
    return false
  }
'@.Replace("`r`n", "`n")
    MustRed = 'the include set keeps only the named families'
  }

  # M10 AND ITS EXCLUDE SET. The other half of the filter, and a profile that
  # dropped nothing would make `--exclude-families` a flag that does nothing.
  @{
    Name = 'M10 the profile ignores its exclude set'
    File = $PROFILE
    Find = @'
  if profile.exclude_ids.contains(id) {
    return false
  }
'@.Replace("`r`n", "`n")
    Repl = @'
  if !profile.exclude_ids.contains(id) {
    return false
  }
'@.Replace("`r`n", "`n")
    MustRed = 'the exclude set drops the named families'
  }

  # M11 AN UNKNOWN ID IS A WARNING. A family added in a later release must not
  # make an older analyzer's profile unusable, and a typo must be loud rather
  # than fatal -- so the scan still runs. The mutation makes the INCLUDE
  # loop read the exclude set, so an unknown include id warns about nothing.
  @{
    Name = 'M11 an unknown family id is not warned about'
    File = $PROFILE
    Find = @'
  for id in include_ids {
    if @core.family_by_id(id) is None {
      warnings.push(
        "unknown family id in --families: " +
'@.Replace("`r`n", "`n")
    Repl = @'
  for id in exclude_ids {
    if @core.family_by_id(id) is None {
      warnings.push(
        "unknown family id in --families: " +
'@.Replace("`r`n", "`n")
    MustRed = 'an unknown family id is a warning, not an error'
  }

  # M12 AND AN INCLUDE/EXCLUDE OVERLAP IS AN ERROR. The two rules contradict
  # each other, so no reading of the profile satisfies both, and which one won
  # would be decided by the order of two `if`s inside the scanner.
  @{
    Name = 'M12 an include/exclude overlap is not an error'
    File = $PROFILE
    Find = @'
  if overlap.length() > 0 {
'@.Replace("`r`n", "`n")
    Repl = @'
  if overlap.length() == 0 {
'@.Replace("`r`n", "`n")
    MustRed = 'an id that is both included and excluded is an error'
  }

  # M13 THE `nosec` SUPPRESSES. A `// nosec` on a line silences the finding on
  # that line, and a family-specific one silences only that family. Without
  # this the flag would be accepted and do nothing.
  @{
    Name = 'M13 the nosec suppresses nothing'
    File = $PROFILE
    Find = @'
      if n.line == r.span.start.line && n.covers_family(r.family) {
        covered = true
      }
'@.Replace("`r`n", "`n")
    Repl = @'
      if n.line == r.span.start.line && n.covers_family(r.family) {
        covered = false
      }
'@.Replace("`r`n", "`n")
    MustRed = 'a blanket nosec silences every finding on its line'
  }

  # M14 AND A STALE ONE IS REPORTED. A suppression that has gone stale is dead
  # weight in the source, and it is a sign that the code it referred to has
  # changed. The finding is produced AFTER the suppression pass, so a blanket
  # `// nosec` cannot silence the warning about its own staleness.
  @{
    Name = 'M14 a stale suppression is not reported'
    File = $PROFILE
    Find = @'
    if !hit {
      stale.push(stale_report(n))
    }
'@.Replace("`r`n", "`n")
    Repl = @'
    if hit {
      stale.push(stale_report(n))
    }
'@.Replace("`r`n", "`n")
    MustRed = 'a nosec that matched nothing is reported as a stale suppression'
  }

  # M15 THE CLI CARRIES THE `--honor-nosec` FLAG THROUGH.
  #
  # This is a DECLARED SURVIVOR, and the argument travels with the result.
  # The root package has no test file -- `moon test` builds it but runs no
  # test in it -- so the suite cannot see the CLI's plumbing at all, and every
  # mutation of that plumbing would come out SURVIVED whether it broke
  # anything or not. The place it IS observable is
  # `_verify/settle_0507_bandit_transfers.ps1`, whose rows T11 and T12 scan a
  # fixture with and without `--honor-nosec` and assert that the suppression
  # is OFF by default and ON when asked for -- and that settle is a stage of
  # the release gate.
  @{
    Name = 'M15 the CLI drops the --honor-nosec flag'
    File = $MAIN
    Find = @'
    } else if a == "--honor-nosec" {
      honor_nosec = true
'@.Replace("`r`n", "`n")
    Repl = @'
    } else if a == "--honor-nosec" {
      honor_nosec = false
'@.Replace("`r`n", "`n")
    Expect = 'SURVIVED'
    Prove = 'the root package has no test file, so `moon test` cannot observe the CLI''s plumbing. The rule is pinned by _verify\settle_0507_bandit_transfers.ps1 rows T11 and T12, which scan a fixture with and without `--honor-nosec` and assert that the suppression is OFF by default and ON when asked for; that settle is a release-gate stage.'
  }
)

Write-MutationGateVerdict -Name '0507'
if ($script:MutationGateFailures.Count -gt 0) { exit 1 }
exit 0
