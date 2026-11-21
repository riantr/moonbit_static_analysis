param([switch]$SelfTest, [string]$Root = '')
$ErrorActionPreference = 'Continue'
# THE GOAL'S OWN CHECKLIST, AND THE LOOP IT COMPILES.
#
# WHY THIS FILE EXISTS. This repository's goal is written down in one sentence:
# compile the LOOP, and complete every task in `_verify/QA_TODO.md`. That
# sentence is a CLAIM about two documents -- the task list and the rule list --
# and until now NOTHING held either of them. Every other number in this
# repository is pinned in `_verify/release.ps1` and checked by a gate; the
# objective's own completion state was a checkbox in a markdown file, and a
# checkbox is a comment.
#
# MEASURED 0628, and the thing this gate found was not a missing box:
#
#   - `_verify/QA_TODO.md` carries THIRTEEN tasks, T1..T13, and every one is
#     ticked -- and TWO of them named a place the evidence had MOVED FROM. T1
#     named `src/sa/profile.mbt:224` for `parse_nosec`, which is line 285 today
#     (0613 added 84 lines to that file). T2 named `src/sa/sa_0507_test.mbt` for
#     the rows that pin the two rules, and those rows live in
#     `src/sa/sa_0613_test.mbt` -- 0613 added a file of its own and the task's
#     "Done when" was never updated. Both are corrected IN PLACE, with the
#     increment that moved them, exactly as that file's own rule says.
#
# => A POINTER THAT RESOLVES IS NOT A POINTER THAT RESOLVES TO THE RIGHT THING.
# `src/sa/sa_0507_test.mbt` exists, so every "does this path ship?" check was
# green on it. The two defects were both a path that resolves and a line that
# moved, and neither could be caught by asking whether the file is there.
#
# WHAT THIS GATE CHECKS, and it is eight things:
#
#   1. THE TASK LIST: T1..T13, each named exactly once, every one TICKED, and
#      no open box anywhere.
#   2. EVERY TASK NAMES AN INCREMENT THAT EXISTS. A task that says it rides
#      increment 0613 is a claim about this repository's history, and the
#      history is readable -- so the gate reads it.
#   3. EVERY PATH A TASK'S "Done when" NAMES RESOLVES, and every `path:line`
#      pin's line is INSIDE the file it names. This is the class the two
#      defects above were made of. A criterion may also name a path that must
#      NOT be there -- the word ABSENT turns the check around -- because a
#      task that DELETED a file cannot state its criterion in terms of a path
#      that resolves.
#   4. THE LOOP'S RULE LIST: 1..N, contiguous, each rule once, and N equals
#      the pin. The rules are the trailing run of the document, and a deleted
#      rule would otherwise leave a shorter run that is still perfectly
#      contiguous -- so the COUNT is pinned, and the pin moves deliberately.
#   5. THE NUMBERS THE PLAN FILE QUOTES ARE THE LIVE NUMBERS. The file's own
#      header says that a number which has since MOVED is corrected IN PLACE,
#      with the increment that moved it -- and until 0633 nothing checked that,
#      so two of its numbers sat stale for eight increments. The numbers it
#      quotes are the ones this repository PINS elsewhere, so they are read
#      from the pins and compared, never re-measured here: one place says how
#      many files the tree has, one place says how many notices it carries,
#      and one place says how many check gates are on disk.
#   6. EVERY TASK STATES ITS OWN CRITERION. A task with no "Done when" is a
#      task this gate cannot cover -- the path check reads the criterion, and
#      a task that states none is skipped in silence.
#   7. THE PLAN FILE MUST NOT CLAIM WHAT THE PACKAGE DOES NOT HOLD. A shipped
#      document that asserts something false about the published package is a
#      false claim with a reader attached.
#   8. EVERY PATH A "Done when" NAMES EXISTED AT THE COMMIT THE TASK RIDES.
#      A path that RESOLVES today is not a path that resolved WHEN THE TASK
#      LANDED, and the difference is a whole class of defect that checks 3
#      cannot see: T13's criterion named a file that did not exist until the
#      NEXT increment, so every "does this path ship?" check was green on it
#      while the criterion could never have been true at increment 0614. The
#      path is asked about at that commit, with `git cat-file -e`, and a
#      criterion that declares a path ABSENT must declare it absent THERE too.
#
# THE DIRECTION MATTERS. The rule count is a pin like every other pin here:
# when a rule is added, the pin moves with it and the release gate's own pin
# check asks that it was declared exactly once.
#
# The self-test injects each defect into a COPY OF THE DOCUMENTS -- the defect
# is in prose, so the copy that has to go red is a copy of the prose -- and
# requires the control, the documents as they stand, to stay green.
#
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File _verify\check_goal_checklist.ps1
#   powershell -NoProfile -ExecutionPolicy Bypass -File _verify\check_goal_checklist.ps1 -SelfTest

$root = if ($Root) { $Root } else { Split-Path -Parent $PSScriptRoot }
$fail = 0

# THE RULE COUNT PIN. It lives in `release.ps1` with every other pin, and it is
# read from there -- so there is ONE place that says how many rules the LOOP
# has, and the gate asks whether the document agrees with it.
function Get-Pin([string]$RelTxt, [string]$Name) {
  $m = [regex]::Match($RelTxt, "\`$" + $Name + "\s*=\s*'(\d+)'")
  if ($m.Success) { return $m.Groups[1].Value }
  return ''
}

# A PIN THAT IS NOT A SINGLE NUMBER. `$SELF_NOTICES` is a breakdown -- "kind=count"
# pairs -- and the number the plan file quotes is its SUM, so the pin is read as
# TEXT here and summed where it is used.
function Get-PinText([string]$RelTxt, [string]$Name) {
  $m = [regex]::Match($RelTxt, "\`$" + $Name + "\s*=\s*'([^']*)'")
  if ($m.Success) { return $m.Groups[1].Value }
  return ''
}

# THE TASK BLOCKS. Each block runs from a task's heading to the next task's
# heading, and it is what "the task's own words" means here: the criterion it
# states, the paths that criterion names, and whether it states one at all.
function Get-TaskBlocks([string]$QaTxt) {
  if ([string]::IsNullOrWhiteSpace($QaTxt)) { return @() }
  return @([regex]::Matches($QaTxt, '(?ms)^\- \[x\] \*\*T\d+\..*?(?=^\- \[x\] \*\*T\d+\.|\z)'))
}

# THE TASKS THAT STATE NO CRITERION. ONE implementation, used by the CHECK and
# by the line the gate PRINTS. A number a gate prints is a claim too, and a
# claim computed in two places is two implementations of one claim -- which is
# how a line ends up answering a question it never asked.
function Get-CriterionlessTasks([string]$QaTxt) {
  $out = @()
  foreach ($b in @(Get-TaskBlocks $QaTxt)) {
    if ($b.Value.IndexOf('**Done when:**') -lt 0) { $out += $b }
  }
  return $out
}

# DOES THE PLAN FILE ASSERT THAT THE FIXTURES SHIP? A QUOTATION IS NOT A CLAIM:
# the corrected record quotes the sentence it retired, so the quote count on the
# line BEFORE the phrase decides it -- and it is counted PER LINE, because this
# document's double-quote count is unbalanced overall and a global count would
# misjudge every position after the imbalance. The test is the one the URL gate
# already uses: a quote on the same line before the phrase makes it a quotation.
function Test-StaleShippingClaim([string]$QaTxt) {
  if ([string]::IsNullOrWhiteSpace($QaTxt)) { return $false }
  $stale = 'they DO ship'
  $idx = 0
  while ($true) {
    $idx = $QaTxt.IndexOf($stale, $idx)
    if ($idx -lt 0) { return $false }
    $lineStart = 0
    if ($idx -gt 0) { $lineStart = $QaTxt.LastIndexOf("`n", $idx - 1) + 1 }
    $prevStart = $lineStart
    if ($prevStart -gt 0) { $prevStart = $QaTxt.LastIndexOf("`n", $prevStart - 1) + 1 }
    $before = $QaTxt.Substring($prevStart, $idx - $prevStart)
    $quotes = ([regex]::Matches($before, '"')).Count
    if (($quotes % 2) -eq 0) { return $true }
    $idx += $stale.Length
  }
}

# THE INCREMENTS THIS REPOSITORY'S HISTORY ACTUALLY CONTAINS. Read from git,
# so a task cannot claim to ride an increment that never shipped.
function Get-KnownIncrements([string]$Root) {
  $out = @{}
  $gitCmd = Get-Command git -ErrorAction SilentlyContinue
  if ($null -eq $gitCmd) { return $out }
  $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  $subjects = @(& git -C $Root log --format='%s' 2>&1)
  $ErrorActionPreference = $prev
  foreach ($s in $subjects) {
    if ($s -match '^(\d{4}):') { $out[$Matches[1]] = $true }
  }
  return $out
}

# THE COMMIT EACH INCREMENT LANDED AS. Read from git, so "the commit the task
# rides" is a COMMIT and not a paragraph. Where an increment has more than one
# commit -- 0533 has two: the work, and a `moon fmt` after the last edit --
# the NEWEST is taken, because that is the state the increment LEFT the tree
# in. 139 of the 140 increments have exactly one commit, so the choice is
# invisible today; it is written down so it is not made twice.
function Get-IncrementCommits([string]$Root) {
  $out = @{}
  $gitCmd = Get-Command git -ErrorAction SilentlyContinue
  if ($null -eq $gitCmd) { return $out }
  $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  $rows = @(& git -C $Root log --format='%H %s' 2>&1)
  $ErrorActionPreference = $prev
  foreach ($s in $rows) {
    $m = [regex]::Match([string]$s, '^([0-9a-f]{40})\s+(\d{4}):')
    if ($m.Success -and -not $out.ContainsKey($m.Groups[2].Value)) {
      $out[$m.Groups[2].Value] = $m.Groups[1].Value
    }
  }
  return $out
}

# THE INCREMENT A TASK RIDES. ONE implementation, used by the check that the
# increment exists and by the check that asks whether the task's own paths
# existed at the commit that increment landed as.
function Get-TaskRides([string]$Block) {
  if ([string]::IsNullOrWhiteSpace($Block)) { return '' }
  $m = [regex]::Match($Block, '(?m)^\s+\*\*Rides:\*\* increment \*\*(\d{4})\*\*')
  if ($m.Success) { return $m.Groups[1].Value }
  return ''
}

# THE PATHS A "Done when" NAMES, and for each one whether it must be ABSENT.
# ONE implementation, used by the check that resolves the paths against the
# tree of today and by the check that asks whether they existed at the commit
# the task rides -- a claim computed in two places is two implementations of
# one claim, and the second one is the one that drifts.
function Get-CriterionPaths([string]$Body) {
  $out = @()
  if ([string]::IsNullOrWhiteSpace($Body)) { return $out }
  $doneIdx = $Body.IndexOf('**Done when:**')
  if ($doneIdx -lt 0) { return $out }
  $tail = $Body.Substring($doneIdx)
  $endIdx = $tail.IndexOf('**Rides:**')
  if ($endIdx -ge 0) { $tail = $tail.Substring(0, $endIdx) }
  foreach ($m in [regex]::Matches($tail, '`([A-Za-z0-9_./\\-]+\.(?:mbt|ps1|mbtp|md|mlw|mbti))(?::(\d+))?`')) {
    $line = 0
    if ($m.Groups[2].Success) { $line = [int]$m.Groups[2].Value }
    # A CRITERION MAY NAME A PATH THAT MUST NOT BE THERE. A task that
    # DELETED a file cannot state its criterion in terms of a path that
    # resolves -- and without this, T12 ("delete the stub") could not say
    # what it deleted, and the gate would call the deletion a dead pointer.
    # The word ABSENT after the path turns the check around: the path must
    # NOT be in the tree.
    $after = $tail.Substring($m.Index + $m.Length)
    $absent = $false
    if ($after -match '^\s+is ABSENT') { $absent = $true }
    $out += [pscustomobject]@{
      Raw    = $m.Groups[1].Value
      Line   = $line
      Absent = $absent
    }
  }
  return $out
}

# DOES A REPO-RELATIVE PATH EXIST AT A COMMIT? `git cat-file -e` answers it
# without reading the blob, and it answers it about the TREE AT THAT COMMIT --
# which is the question. "Does the file exist now" is a different question,
# and it is the one that let T13's criterion name a file that had not been
# written yet.
function Test-PathAtCommit([string]$Root, [string]$Sha, [string]$RelPath) {
  if ($Sha -eq '' -or $RelPath -eq '') { return $false }
  $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  & git -C $Root cat-file -e ($Sha + ':' + $RelPath) 2>$null | Out-Null
  $rc = $LASTEXITCODE
  $ErrorActionPreference = $prev
  return ($rc -eq 0)
}

# A CRITERION MAY NAME A BARE FILE NAME -- "sa_0507_test.mbt", with no
# directory. The path check resolves such a name by looking it up under
# `src/` in the tree of today; at a COMMIT the same lookup is done against the
# tree of that commit, so a file that moved between the commit and today is
# still found. A name that is there ZERO times or MORE THAN ONCE resolves to
# nothing, and the check then says so.
function Resolve-NameAtCommit([string]$Root, [string]$Sha, [string]$Base) {
  if ($Sha -eq '' -or $Base -eq '') { return '' }
  $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  $rows = @(& git -C $Root ls-tree -r $Sha --name-only 2>$null)
  $ErrorActionPreference = $prev
  $hits = @()
  foreach ($p in $rows) {
    $p = ([string]$p).Trim()
    if ($p -eq '') { continue }
    $leaf = $p
    if ($p.Contains('/')) { $leaf = $p.Substring($p.LastIndexOf('/') + 1) }
    if ($leaf -eq $Base) { $hits += $p }
  }
  if ($hits.Count -eq 1) { return $hits[0] }
  return ''
}

# DID THE PATH A CRITERION NAMES EXIST AT THE COMMIT THE TASK RIDES? A path
# with a directory is asked about directly; a BARE FILE NAME is looked up in
# the tree of that commit.
function Test-CriterionPathAtCommit([string]$Root, [string]$Sha, [string]$Named) {
  if ($Sha -eq '' -or $Named -eq '') { return $false }
  $rel = ($Named -replace '\\', '/')
  if ($rel.Contains('/')) { return (Test-PathAtCommit $Root $Sha $rel) }
  $resolved = Resolve-NameAtCommit $Root $Sha $rel
  return ($resolved -ne '')
}

# THE AUDIT OF THE CRITERIA'S PATHS AT THE COMMITS THEIR TASKS RIDE. It
# returns the number of paths it CHECKED as well as the problems it found,
# because the gate prints that number and a printed number is a claim.
function Get-RidingCommitAudit([string]$QaTxt, [hashtable]$Commits, [string]$Root) {
  $checked = 0
  $problems = @()
  foreach ($b in @(Get-TaskBlocks $QaTxt)) {
    $inc = Get-TaskRides $b.Value
    if ($inc -eq '') { continue }
    if (-not $Commits.ContainsKey($inc)) { continue }
    $sha = $Commits[$inc]
    foreach ($p in @(Get-CriterionPaths $b.Value)) {
      $checked++
      if ($p.Absent) {
        # A criterion that declares a path ABSENT must have declared it
        # absent AT THE COMMIT TOO: a deletion that had not happened yet is
        # not a deletion.
        if (Test-CriterionPathAtCommit $Root $sha $p.Raw) {
          $problems += ('FAIL: a "Done when" declares ' + $p.Raw + ' ABSENT, and it WAS in the tree at the commit increment ' + $inc + ' rides.')
        }
        continue
      }
      if (-not (Test-CriterionPathAtCommit $Root $sha $p.Raw)) {
        $problems += ('FAIL: a "Done when" names ' + $p.Raw + ', and it WAS NOT in the tree at the commit increment ' + $inc + ' rides.')
      }
    }
  }
  return [pscustomobject]@{ Checked = $checked; Problems = $problems }
}

# THE RULE LIST OF LOOP.md. The rules are the TRAILING run of numbered items:
# each rule's number is one more than the rule above it, and the run ends at
# the document's last numbered item. The earlier numbered lists in the document
# are prose (a candidate list, a list of lessons), and they are not part of the
# rule list -- so the run is found by walking BACK from the last item.
function Get-RuleRun([string]$LoopTxt) {
  $out = @()
  if ([string]::IsNullOrWhiteSpace($LoopTxt)) { return $out }
  $lines = @($LoopTxt -split "`r?`n")
  $items = @()
  for ($i = 0; $i -lt $lines.Count; $i++) {
    $m = [regex]::Match($lines[$i], '^(\d+)\.\s+\*\*')
    if ($m.Success) { $items += [pscustomobject]@{ N = [int]$m.Groups[1].Value; Line = $i } }
  }
  if ($items.Count -eq 0) { return $out }
  $run = @()
  $expect = $items[$items.Count - 1].N
  for ($k = $items.Count - 1; $k -ge 0; $k--) {
    if ($items[$k].N -ne $expect) { break }
    $run = ,($items[$k]) + $run
    $expect--
  }
  return $run
}

function Get-RuleNumbers([string]$LoopTxt) {
  $out = @()
  foreach ($it in @(Get-RuleRun $LoopTxt)) { $out += $it.N }
  return $out
}

# REMOVE ONE RULE'S HEADING LINE from a copy of the LOOP. The line index comes
# from the rule RUN itself, so the removal cannot land on one of the document's
# earlier PROSE lists -- it also starts with "1." -- and the numbering cannot
# be renumbered out from under the fault.
function Remove-RuleHeading([string]$LoopTxt, [int]$Index) {
  $run = @(Get-RuleRun $LoopTxt)
  if ($run.Count -eq 0) { return $LoopTxt }
  if ($Index -lt 0) { $Index = $run.Count - 1 }
  if ($Index -ge $run.Count) { return $LoopTxt }
  $lineIdx = $run[$Index].Line
  $nl = "`n"
  if ($LoopTxt.Contains("`r`n")) { $nl = "`r`n" }
  $lines = @($LoopTxt -split "`r?`n")
  $kept = @()
  for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($i -ne $lineIdx) { $kept += $lines[$i] }
  }
  return ($kept -join $nl)
}

# WHAT IS WRONG WITH THE DOCUMENTS, given the measurement. The texts are passed
# in, so the self-test can hand it a COPY with one thing changed.
function Get-ChecklistProblems {
  param([string]$QaTxt, [string]$LoopTxt, [string]$RelTxt, [hashtable]$Increments, [string]$Root, [hashtable]$Commits)
  $probs = @()

  # THE TASK BLOCKS. Each block runs from a task's heading to the next task's
  # heading, and it is what "the task's own words" means here: the criterion it
  # states, the paths that criterion names, and whether it states one at all.
  $blocks = @(Get-TaskBlocks $QaTxt)

  # --- 1. THE TASK LIST -------------------------------------------------------
  $taskLines = @()
  if (-not [string]::IsNullOrWhiteSpace($QaTxt)) {
    $taskLines = @([regex]::Matches($QaTxt, '(?m)^- \[( |x)\] \*\*(T\d+)\.'))
  }
  $seen = @{}
  foreach ($m in $taskLines) {
    $box = $m.Groups[1].Value
    $id = $m.Groups[2].Value
    if ($seen.ContainsKey($id)) {
      $probs += ('FAIL: the task list names ' + $id + ' more than once.')
    } else {
      $seen[$id] = $true
    }
    if ($box -ne 'x') {
      $probs += ('FAIL: the task ' + $id + ' is not ticked.')
    }
  }
  if ($taskLines.Count -eq 0) {
    $probs += 'FAIL: the task list names no task at all.'
  }
  for ($i = 1; $i -le $taskLines.Count; $i++) {
    if (-not $seen.ContainsKey('T' + $i)) {
      $probs += ('FAIL: the task list does not name T' + $i + '.')
    }
  }
  $open = @([regex]::Matches($QaTxt, '(?m)^- \[ \]'))
  if ($open.Count -gt 0) {
    $probs += ('FAIL: the task list carries ' + $open.Count + ' open box(es).')
  }

  # --- 2. EVERY TASK RIDES AN INCREMENT THAT EXISTS ---------------------------
  $rides = @([regex]::Matches($QaTxt, '(?m)^\s+\*\*Rides:\*\* increment \*\*(\d{4})\*\*'))
  if ($rides.Count -ne $taskLines.Count) {
    $probs += ('FAIL: ' + $taskLines.Count + ' task(s) and ' + $rides.Count + ' riding increment(s) -- every task must name the increment it rides.')
  }
  foreach ($b in $blocks) {
    $inc = Get-TaskRides $b.Value
    if ($inc -eq '') { continue }
    if (-not $Increments.ContainsKey($inc)) {
      $probs += ('FAIL: a task rides increment ' + $inc + ', and this repository''s history has no such increment.')
    }
  }

  # --- 3. EVERY PATH A "Done when" NAMES RESOLVES -----------------------------
  # The paths are the ones inside the DONE-WHEN blocks: that is where a task
  # says WHERE ITS EVIDENCE IS, and that is where a pointer rots. The paths
  # and the ABSENT declaration are read by `Get-CriterionPaths` -- ONE
  # implementation, shared with the riding-commit check below.
  foreach ($b in $blocks) {
    foreach ($p in @(Get-CriterionPaths $b.Value)) {
      $rel = $p.Raw -replace '/', '\'
      $line = $p.Line
      $full = Join-Path $Root $rel
      if ($p.Absent) {
        if (Test-Path -LiteralPath $full) {
          $probs += ('FAIL: a "Done when" declares ' + $p.Raw + ' ABSENT, and it is still in the tree.')
        }
        continue
      }
      if (-not (Test-Path -LiteralPath $full)) {
        # A BARE FILE NAME (no directory) is looked up by name, because the
        # checklist writes `sa_0507_test.mbt` and not its path.
        $found = @(Get-ChildItem -LiteralPath (Join-Path $Root 'src') -Recurse -File -Filter ([System.IO.Path]::GetFileName($rel)) -ErrorAction SilentlyContinue)
        if ($found.Count -eq 1) { $full = $found[0].FullName } else { $full = '' }
      }
      if ($full -eq '') {
        $probs += ('FAIL: a "Done when" names ' + $p.Raw + ', and that file is not in the tree.')
        continue
      }
      if ($line -gt 0) {
        $n = @([System.IO.File]::ReadAllLines($full, [Text.Encoding]::UTF8)).Count
        if ($line -gt $n) {
          $probs += ('FAIL: a "Done when" pins ' + $p.Raw + ':' + $line + ', and that file has only ' + $n + ' line(s).')
        }
      }
    }
  }

  # --- 4. THE LOOP'S RULE LIST ------------------------------------------------
  $rules = @(Get-RuleNumbers $LoopTxt)
  if ($rules.Count -eq 0) {
    $probs += 'FAIL: the LOOP names no rule.'
  } else {
    for ($i = 0; $i -lt $rules.Count; $i++) {
      if ($rules[$i] -ne ($i + 1)) {
        $probs += ('FAIL: the LOOP''s rule list is not contiguous: it starts at rule ' + $rules[0] + ' instead of rule 1, and reads ' + ($rules -join ',') + '.')
        break
      }
    }
    $pin = Get-Pin $RelTxt 'LOOP_RULES'
    if ($pin -eq '') {
      $probs += 'FAIL: release.ps1 no longer carries the $LOOP_RULES pin, so the rule count is measured against nothing.'
    } elseif ([int]$pin -ne $rules.Count) {
      $probs += ('FAIL: the LOOP carries ' + $rules.Count + ' rule(s) and the pin says ' + $pin + '.')
    }
  }

  # --- 5. THE NUMBERS THE PLAN FILE QUOTES ARE THE LIVE NUMBERS ---------------
  # The file's own header says that a number which has since MOVED is corrected
  # IN PLACE, with the increment that moved it. Nothing checked that until 0633,
  # and two of its numbers had been sitting stale for eight increments while
  # this gate stayed green -- because this gate held the ticks, the riding
  # increments, the paths and the rule count, and NOT the numbers inside a
  # record. A rule written in a document about itself is prose until a gate
  # holds it.
  #
  # The numbers the file quotes are the ones the REST of this repository PINS,
  # so they are READ from the pins and compared here rather than re-measured: a
  # second measurement would be a second implementation of a claim that already
  # has one. The one number with no pin -- how many check gates are on disk --
  # is counted the way `check_gate_roster.ps1` counts it, on disk.
  $filesPin = Get-Pin $RelTxt 'SELF_FILES'
  $noticesPin = Get-PinText $RelTxt 'SELF_NOTICES'
  $noticeSum = 0
  if ($noticesPin -ne '') {
    foreach ($pair in ($noticesPin -split '\|')) {
      $kv = $pair -split '='
      if ($kv.Count -ge 2) { $noticeSum += [int]$kv[1] }
    }
  }
  $gateCount = 0
  if ($Root -ne '') {
    $gateCount = @(Get-ChildItem -LiteralPath (Join-Path $Root '_verify') -Filter 'check_*.ps1' -File -ErrorAction SilentlyContinue).Count
  }

  $fileQuotes = @([regex]::Matches($QaTxt, 'files=(\d+)\s+parsed=(\d+)\s+actionable=(\d+)\s+notices=(\d+)'))
  if ($fileQuotes.Count -eq 0) {
    $probs += 'FAIL: the plan file quotes no file-and-notice measurement at all, so the numbers it holds cannot be checked against the tree.'
  }
  foreach ($m in $fileQuotes) {
    $f = [int]$m.Groups[1].Value
    $p = [int]$m.Groups[2].Value
    $a = [int]$m.Groups[3].Value
    $n = [int]$m.Groups[4].Value
    if ($filesPin -eq '') {
      $probs += 'FAIL: release.ps1 no longer carries the $SELF_FILES pin, so the plan file''s file count would be measured against nothing.'
    } elseif ($f -ne [int]$filesPin) {
      $probs += ('FAIL: the plan file quotes files=' + $f + ', and the tree''s own pin says ' + $filesPin + '.')
    }
    if ($p -ne $f) {
      $probs += ('FAIL: the plan file quotes parsed=' + $p + ' against files=' + $f + '.')
    }
    if ($a -ne 0) {
      $probs += ('FAIL: the plan file quotes actionable=' + $a + ', and this tree has none.')
    }
    if ($noticesPin -eq '') {
      $probs += 'FAIL: release.ps1 no longer carries the $SELF_NOTICES pin, so the plan file''s notice count would be measured against nothing.'
    } elseif ($n -ne $noticeSum) {
      $probs += ('FAIL: the plan file quotes notices=' + $n + ', and the tree''s own pins say ' + $noticeSum + '.')
    }
  }

  $gateQuotes = @([regex]::Matches($QaTxt, 'MEASURED:\s*(\d+)\s+`check_\*` gates'))
  if ($gateQuotes.Count -eq 0) {
    $probs += 'FAIL: the plan file quotes no check-gate count at all, so the number of gates it holds cannot be checked against the tree.'
  }
  foreach ($m in $gateQuotes) {
    $c = [int]$m.Groups[1].Value
    if ($c -ne $gateCount) {
      $probs += ('FAIL: the plan file quotes ' + $c + ' check_* gates, and the tree holds ' + $gateCount + '.')
    }
  }

  # --- 6. EVERY TASK STATES ITS OWN CRITERION ---------------------------------
  # A task that states no "Done when" is a task this gate CANNOT cover: the
  # path check above reads the criterion, and a task with none is skipped in
  # SILENCE -- which is how two of the thirteen (T12 and T13) held their
  # evidence as prose while every tick was green. A QA that is not a gate is a
  # comment, and a criterion that no gate reads is one too.
  foreach ($b in @(Get-CriterionlessTasks $QaTxt)) {
    $tid = [regex]::Match($b.Value, '^\- \[x\] \*\*(T\d+)\.').Groups[1].Value
    $probs += ('FAIL: the task ' + $tid + ' states no "Done when", so the gate cannot cover its evidence.')
  }

  # --- 7. THE PLAN FILE MUST NOT CLAIM WHAT THE PACKAGE DOES NOT HOLD ---------
  # A shipped document that asserts something FALSE about the published package
  # is a false claim with a reader attached: the plan file said the twenty-four
  # fixtures ship, and they stopped shipping in 0632. The decision is
  # `Test-StaleShippingClaim` -- ONE implementation, shared with the line the
  # gate prints, because a quotation is not a claim and the two places that
  # talk about it must agree on what a quotation is.
  if (Test-StaleShippingClaim $QaTxt) {
    $probs += 'FAIL: the plan file still claims the fixtures ship. They stopped shipping in increment 0632.'
  }

  # --- 8. EVERY PATH A "Done when" NAMES EXISTED AT THE COMMIT THE TASK RIDES -
  # A pointer that RESOLVES is not a pointer that resolved WHEN THE TASK
  # LANDED, and the difference is a whole class of defect that check 3 cannot
  # see. T13's criterion named `_verify/check_own_tree_clean.ps1` as the file
  # the comparison lives in -- a file that did not exist until increment 0615,
  # so the criterion could never have been true at 0614, the increment the task
  # rides -- and check 3 was GREEN on it, because the file IS in the tree
  # today. The path is asked about AT THAT COMMIT, with `git cat-file -e`.
  #
  # And the other direction: a criterion that declares a path ABSENT must
  # declare it absent AT THE COMMIT TOO, because a deletion that had not
  # happened yet is not a deletion.
  if ($Commits.Count -eq 0) {
    $probs += 'FAIL: the riding commits could not be read from git, so the criteria were NOT checked against the commits their tasks ride.'
  } else {
    $audit = Get-RidingCommitAudit $QaTxt $Commits $Root
    $probs += @($audit.Problems)
  }

  return $probs
}

# ------------------------------------------------------------------- the self-test ---
if ($SelfTest) {
  Write-Output 'check the goal checklist -- SELF TEST'
  $bad = 0
  $checked = 0

  $qa = [System.IO.File]::ReadAllText((Join-Path $root '_verify\QA_TODO.md'), [Text.Encoding]::UTF8)
  $loop = [System.IO.File]::ReadAllText((Join-Path $root 'LOOP.md'), [Text.Encoding]::UTF8)
  $rel = [System.IO.File]::ReadAllText((Join-Path $root '_verify\release.ps1'), [Text.Encoding]::UTF8)
  $incs = Get-KnownIncrements $root
  $commits = Get-IncrementCommits $root
  Write-Output ('  the increments this history holds: ' + $incs.Count)
  Write-Output ('  the riding commits this history holds: ' + $commits.Count)

  Write-Output ''
  Write-Output '--- the control: the documents as they stand ---'
  $ctl = @(Get-ChecklistProblems $qa $loop $rel $incs $root $commits)
  $checked++
  if ($ctl.Count -eq 0) {
    Write-Output '  OK: the control passes.'
  } else {
    Write-Output ('  FAIL: the control does NOT pass: ' + $ctl.Count + ' problem(s).')
    foreach ($x in $ctl) { Write-Output ('        ' + $x) }
    $bad++
  }

  $faults = @(
    [pscustomobject]@{
      N = 'a task is not ticked'
      Expect = 'is not ticked'
      Apply = { param($q, $l, $r) $q = $q.Replace('- [x] **T7.', '- [ ] **T7.'); return ,@($q, $l, $r) }
    }
    [pscustomobject]@{
      N = 'a task is missing'
      Expect = 'does not name'
      Apply = { param($q, $l, $r) $q = [regex]::Replace($q, '(?m)^- \[x\] \*\*T9\..*$', ''); return ,@($q, $l, $r) }
    }
    [pscustomobject]@{
      N = 'a task rides an increment that does not exist'
      Expect = 'history has no such increment'
      # The Rides lines END WITH A PERIOD -- "**Rides:** increment **0613**." --
      # so the number is matched, not the end of the line. An earlier version of
      # this fault anchored with `$`, matched nothing, and therefore injected
      # NOTHING: the gate stayed green on an unmutated document and the fault
      # reported itself as a miss.
      Apply = { param($q, $l, $r) $q = [regex]::Replace($q, '(?m)^(\s+\*\*Rides:\*\* increment \*\*)\d{4}', '${1}0000'); return ,@($q, $l, $r) }
    }
    [pscustomobject]@{
      N = 'a "Done when" names a file that is not in the tree'
      Expect = 'that file is not in the tree'
      Apply = { param($q, $l, $r) $q = $q.Replace('`src/sa/sa_0613_test.mbt`', '`src/sa/sa_9999_test.mbt`'); return ,@($q, $l, $r) }
    }
    [pscustomobject]@{
      N = 'a "Done when" pins a line past the end of its file'
      Expect = 'has only'
      Apply = { param($q, $l, $r) $q = $q.Replace('`src/sa/sa_0613_test.mbt`', '`src/sa/sa_0613_test.mbt:9999`'); return ,@($q, $l, $r) }
    }
    [pscustomobject]@{
      N = 'the LOOP loses a rule in the middle'
      Expect = 'not contiguous'
      # A rule deleted from the MIDDLE leaves the trailing run starting above
      # 1 -- that is the CONTIGUITY check's own defect. Deleting the LAST rule
      # instead leaves 1..N-1, which is still perfectly contiguous, so that
      # fault is a different one and it is listed below.
      Apply = {
        param($q, $l, $r)
        $l = Remove-RuleHeading $l ([int][math]::Floor((@(Get-RuleRun $l)).Count / 2))
        return ,@($q, $l, $r)
      }
    }
    [pscustomobject]@{
      N = 'the LOOP loses its last rule'
      Expect = 'the pin says'
      # The last rule gone leaves a CONTIGUOUS but SHORTER run -- the count is
      # what catches that, and the count is a pin.
      Apply = {
        param($q, $l, $r)
        $l = Remove-RuleHeading $l -1
        return ,@($q, $l, $r)
      }
    }
    [pscustomobject]@{
      N = 'the pin and the rule list disagree'
      Expect = 'the pin says 99'
      # The pin is moved to a value no rule count can take, and the fault does
      # not name the current one -- so it does not rot when the pin moves.
      Apply = { param($q, $l, $r) $r = [regex]::Replace($r, "(\`$LOOP_RULES\s*=\s*')(\d+)(')", '${1}99${3}'); return ,@($q, $l, $r) }
    }
    [pscustomobject]@{
      N = 'the plan file quotes a file count the tree does not have'
      Expect = 'the tree''s own pin says'
      # The number the document quotes is READ and then moved by one, so the
      # fault does not name the current one -- a fault that hard-coded "280"
      # would rot the day the tree's own count moved, which is the very
      # defect class this check exists for.
      Apply = {
        param($q, $l, $r)
        $m = [regex]::Match($q, 'files=(\d+)\s+parsed=(\d+)\s+actionable=(\d+)\s+notices=(\d+)')
        if (-not $m.Success) { return ,@($q, $l, $r) }
        $f = [int]$m.Groups[1].Value + 1
        $q = $q.Replace($m.Value, ('files=' + $f + ' parsed=' + $f + ' actionable=' + $m.Groups[3].Value + ' notices=' + $m.Groups[4].Value))
        return ,@($q, $l, $r)
      }
    }
    [pscustomobject]@{
      N = 'the plan file quotes a check-gate count the tree does not have'
      Expect = 'the tree holds'
      Apply = {
        param($q, $l, $r)
        $m = [regex]::Match($q, 'MEASURED:\s*(\d+)\s+`check_\*` gates')
        if (-not $m.Success) { return ,@($q, $l, $r) }
        $c = [int]$m.Groups[1].Value + 1
        $q = $q.Replace($m.Value, ('MEASURED: ' + $c + ' `check_*` gates'))
        return ,@($q, $l, $r)
      }
    }
    [pscustomobject]@{
      N = 'a task states no "Done when"'
      Expect = 'states no "Done when"'
      # The marker is removed from T1's OWN block -- the lazy match stops at the
      # first "Done when" after T1's heading, which is T1's -- so no other task
      # is touched and the fault is about the one thing it says it is about.
      Apply = {
        param($q, $l, $r)
        $q = [regex]::Replace($q, '(?ms)^(- \[x\] \*\*T1\..*?)\*\*Done when:\*\*', '${1}')
        return ,@($q, $l, $r)
      }
    }
    [pscustomobject]@{
      N = 'a "Done when" that declares a path ABSENT loses the word'
      Expect = 'that file is not in the tree'
      # The word ABSENT is what turns the path check around. Without it, the
      # deleted stub is a path that does not resolve -- which is exactly what a
      # deletion IS, and what the gate used to call a dead pointer.
      Apply = {
        param($q, $l, $r)
        $q = $q.Replace(' is ABSENT', ' is present')
        return ,@($q, $l, $r)
      }
    }
    [pscustomobject]@{
      N = 'the plan file claims the fixtures ship again'
      Expect = 'still claims the fixtures ship'
      Apply = {
        param($q, $l, $r)
        $q = [regex]::Replace($q, 'only the two `\.out`\s+captures still ship\.', 'and they DO ship, because the evidence a reader is sent to has to be in the package.')
        return ,@($q, $l, $r)
      }
    }
    [pscustomobject]@{
      N = 'a "Done when" names a file that did not exist at the commit the task rides'
      Expect = 'WAS NOT in the tree at the commit increment'
      # THE DEFECT THIS CHECK EXISTS FOR. T13's criterion named a file that
      # did not exist until the NEXT increment, so it resolved today and could
      # never have been true when the task landed -- and check 3 was GREEN on
      # it. The fault reproduces that EXACT shape: a file that IS in the tree
      # (so the path check stays green) and was NOT in the tree at the riding
      # commit (so the riding-commit check goes red).
      #
      # The replacement is scoped to the Done-when clause, because the
      # corrected record NAMES THE SAME FILE while explaining the correction.
      Apply = {
        param($q, $l, $r)
        $q = [regex]::Replace($q, '(?m)(\*\*Done when:\*\* the comparison lives in )`_verify/release\.ps1`', '${1}`_verify/check_own_tree_clean.ps1`')
        return ,@($q, $l, $r)
      }
    }
    [pscustomobject]@{
      N = 'a "Done when" that declares a path ABSENT names one that WAS there'
      Expect = 'WAS in the tree at the commit increment'
      # The other direction. A deletion that had not happened yet is not a
      # deletion, so a criterion that declares a path ABSENT must declare it
      # absent AT THE COMMIT TOO. The fault points T12's ABSENT declaration at
      # a file that WAS in the tree at 0614 -- so the path check goes red as
      # well, but with its OWN message, and only the riding-commit check
      # carries this one.
      Apply = {
        param($q, $l, $r)
        $q = [regex]::Replace($q, '(?m)^(\s+\*\*Done when:\*\* `)src/lexer/lexer_0488_test\.mbt(` is ABSENT)', '${1}src/parser/parser_0488_test.mbt${2}')
        return ,@($q, $l, $r)
      }
    }
  )

  foreach ($f in $faults) {
    Write-Output ''
    Write-Output ('--- the defect: ' + $f.N + ' ---')
    $mutated = $null
    try {
      $mutated = & $f.Apply $qa $loop $rel
    } catch {
      Write-Output ('  FAIL: the mutation threw: ' + $_.Exception.Message)
      $bad++
      continue
    }
    if ($null -eq $mutated -or @($mutated).Count -ne 3) {
      Write-Output '  FAIL: the mutation did not produce a copy of the documents.'
      $bad++
      continue
    }
    # THE FAULT MUST HAVE LANDED. A mutation that changes NOTHING is
    # indistinguishable from a defect that was not caught -- the gate stays
    # green either way and the fault reports itself as a miss. So the
    # documents are compared before and after, and a mutation that did not
    # change them is reported as what it is: a fault that never landed.
    if ($mutated[0] -eq $qa -and $mutated[1] -eq $loop -and $mutated[2] -eq $rel) {
      Write-Output '  FAIL: the mutation did not change the documents, so the fault never landed.'
      $bad++
      continue
    }
    $probs = @(Get-ChecklistProblems $mutated[0] $mutated[1] $mutated[2] $incs $root $commits)
    $checked++
    $caught = 0
    try {
      if (($probs -join ' | ') -match [regex]::Escape($f.Expect)) { $caught++ }
    } catch {
      Write-Output ('  FAIL: the check itself threw: ' + $_.Exception.Message)
    }
    if ($caught -eq 1) {
      $hit = @($probs | Where-Object { $_ -match [regex]::Escape($f.Expect) })[0]
      Write-Output ('  OK: the gate caught it: ' + $hit)
    } else {
      Write-Output ('  FAIL: the gate did NOT catch it (expected "' + $f.Expect + '").')
      foreach ($pr in $probs) { Write-Output ('        ' + $pr) }
      $bad++
    }
  }

  if ($checked -ne 16) {
    Write-Output ('  FAIL: ' + $checked + ' of 16 checks ran.')
    $bad++
  }

  Write-Output ''
  if ($bad -eq 0) {
    Write-Output ('SELFTEST OK: the control passed, and ' + $faults.Count + ' injected defects were caught.')
    exit 0
  }
  Write-Output ('SELFTEST FAILED: ' + $bad + ' problem(s).')
  exit 1
}

# ------------------------------------------------------------------ the live check ---
Write-Output '=== the goal checklist: the tasks are ticked and the rules are numbered ==='
$qaPath = Join-Path $root '_verify\QA_TODO.md'
$loopPath = Join-Path $root 'LOOP.md'
$relPath = Join-Path $root '_verify\release.ps1'
foreach ($p in @($qaPath, $loopPath, $relPath)) {
  if (-not (Test-Path -LiteralPath $p)) {
    Write-Output ('ABORT: no ' + $p)
    exit 1
  }
}
$qa = [System.IO.File]::ReadAllText($qaPath, [Text.Encoding]::UTF8)
$loop = [System.IO.File]::ReadAllText($loopPath, [Text.Encoding]::UTF8)
$rel = [System.IO.File]::ReadAllText($relPath, [Text.Encoding]::UTF8)
$incs = Get-KnownIncrements $root
$commits = Get-IncrementCommits $root

$taskCount = @([regex]::Matches($qa, '(?m)^- \[( |x)\] \*\*T\d+\.')).Count
$openCount = @([regex]::Matches($qa, '(?m)^- \[ \]')).Count
$rules = @(Get-RuleNumbers $loop)
Write-Output ('  the tasks: ' + $taskCount + '   the open boxes: ' + $openCount)
Write-Output ('  the LOOP''s rules: ' + $rules.Count + '   the pin: ' + (Get-Pin $rel 'LOOP_RULES'))
Write-Output ('  the increments this history holds: ' + $incs.Count)
Write-Output ('  the riding commits this history holds: ' + $commits.Count)
$qFiles = @([regex]::Matches($qa, 'files=(\d+)\s+parsed=(\d+)\s+actionable=(\d+)\s+notices=(\d+)'))
$qGates = @([regex]::Matches($qa, 'MEASURED:\s*(\d+)\s+`check_\*` gates'))
$liveGates = @(Get-ChildItem -LiteralPath (Join-Path $root '_verify') -Filter 'check_*.ps1' -File -ErrorAction SilentlyContinue).Count
if ($qFiles.Count -gt 0) {
  Write-Output ('  the plan file quotes: files=' + $qFiles[0].Groups[1].Value + ' notices=' + $qFiles[0].Groups[4].Value + '   the tree''s pins say: files=' + (Get-Pin $rel 'SELF_FILES'))
}
if ($qGates.Count -gt 0) {
  Write-Output ('  the plan file quotes: ' + $qGates[0].Groups[1].Value + ' check gates   the tree holds: ' + $liveGates)
}
$noCriterion = @(Get-CriterionlessTasks $qa)
Write-Output ('  the tasks that state no criterion: ' + $noCriterion.Count)
Write-Output ('  the plan file ASSERTS the fixtures ship: ' + (Test-StaleShippingClaim $qa))
$audit = Get-RidingCommitAudit $qa $commits $root
Write-Output ('  the criteria paths checked at the commit their task rides: ' + $audit.Checked)

$probs = @(Get-ChecklistProblems $qa $loop $rel $incs $root $commits)
foreach ($p in $probs) {
  Write-Output ''
  Write-Output $p
}
$fail += $probs.Count

Write-Output ''
if ($fail -eq 0) {
  Write-Output ('CHECKLIST OK: ' + $taskCount + ' task(s), all ticked, every one riding an increment this')
  Write-Output ('history holds, every path it names resolving, and the LOOP''s ' + $rules.Count + ' rule(s) numbered')
  Write-Output 'contiguously and matching the pin, every number the plan file quotes matching the tree,'
  Write-Output ('every task stating its own criterion, no claim about the package it does not hold, and')
  Write-Output ('every criterion path present at the commit its task rides (' + $audit.Checked + ' path(s) checked).')
  exit 0
}
Write-Output ('CHECKLIST FAILED: ' + $fail + ' problem(s).')
exit 1
