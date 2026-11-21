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
# WHAT THIS GATE CHECKS, and it is five things:
#
#   1. THE TASK LIST: T1..T13, each named exactly once, every one TICKED, and
#      no open box anywhere.
#   2. EVERY TASK NAMES AN INCREMENT THAT EXISTS. A task that says it rides
#      increment 0613 is a claim about this repository's history, and the
#      history is readable -- so the gate reads it.
#   3. EVERY PATH A TASK'S "Done when" NAMES RESOLVES, and every `path:line`
#      pin's line is INSIDE the file it names. This is the class the two
#      defects above were made of.
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
  param([string]$QaTxt, [string]$LoopTxt, [string]$RelTxt, [hashtable]$Increments, [string]$Root)
  $probs = @()

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
  foreach ($m in $rides) {
    $inc = $m.Groups[1].Value
    if (-not $Increments.ContainsKey($inc)) {
      $probs += ('FAIL: a task rides increment ' + $inc + ', and this repository''s history has no such increment.')
    }
  }

  # --- 3. EVERY PATH A "Done when" NAMES RESOLVES -----------------------------
  # The paths are the ones inside the DONE-WHEN blocks: that is where a task
  # says WHERE ITS EVIDENCE IS, and that is where a pointer rots.
  $blocks = @([regex]::Matches($QaTxt, '(?ms)^\- \[x\] \*\*T\d+\..*?(?=^\- \[x\] \*\*T\d+\.|\z)'))
  foreach ($b in $blocks) {
    $body = $b.Value
    $doneIdx = $body.IndexOf('**Done when:**')
    if ($doneIdx -lt 0) { continue }
    $tail = $body.Substring($doneIdx)
    $endIdx = $tail.IndexOf('**Rides:**')
    if ($endIdx -ge 0) { $tail = $tail.Substring(0, $endIdx) }
    foreach ($m in [regex]::Matches($tail, '`([A-Za-z0-9_./\\-]+\.(?:mbt|ps1|mbtp|md|mlw|mbti))(?::(\d+))?`')) {
      $rel = $m.Groups[1].Value -replace '/', '\'
      $line = 0
      if ($m.Groups[2].Success) { $line = [int]$m.Groups[2].Value }
      $full = Join-Path $Root $rel
      if (-not (Test-Path -LiteralPath $full)) {
        # A BARE FILE NAME (no directory) is looked up by name, because the
        # checklist writes `sa_0507_test.mbt` and not its path.
        $found = @(Get-ChildItem -LiteralPath (Join-Path $Root 'src') -Recurse -File -Filter ([System.IO.Path]::GetFileName($rel)) -ErrorAction SilentlyContinue)
        if ($found.Count -eq 1) { $full = $found[0].FullName } else { $full = '' }
      }
      if ($full -eq '') {
        $probs += ('FAIL: a "Done when" names ' + $m.Groups[1].Value + ', and that file is not in the tree.')
        continue
      }
      if ($line -gt 0) {
        $n = @([System.IO.File]::ReadAllLines($full, [Text.Encoding]::UTF8)).Count
        if ($line -gt $n) {
          $probs += ('FAIL: a "Done when" pins ' + $m.Groups[1].Value + ':' + $line + ', and that file has only ' + $n + ' line(s).')
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
  Write-Output ('  the increments this history holds: ' + $incs.Count)

  Write-Output ''
  Write-Output '--- the control: the documents as they stand ---'
  $ctl = @(Get-ChecklistProblems $qa $loop $rel $incs $root)
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
  )

  foreach ($f in $faults) {
    Write-Output ''
    Write-Output ('--- the defect: ' + $f.N + ' ---')
    $mutated = & $f.Apply $qa $loop $rel
    if ($null -eq $mutated -or @($mutated).Count -ne 3) {
      Write-Output '  FAIL: the mutation did not produce a copy of the documents.'
      $bad++
      continue
    }
    $probs = @(Get-ChecklistProblems $mutated[0] $mutated[1] $mutated[2] $incs $root)
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

  if ($checked -ne 11) {
    Write-Output ('  FAIL: ' + $checked + ' of 11 checks ran.')
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

$taskCount = @([regex]::Matches($qa, '(?m)^- \[( |x)\] \*\*T\d+\.')).Count
$openCount = @([regex]::Matches($qa, '(?m)^- \[ \]')).Count
$rules = @(Get-RuleNumbers $loop)
Write-Output ('  the tasks: ' + $taskCount + '   the open boxes: ' + $openCount)
Write-Output ('  the LOOP''s rules: ' + $rules.Count + '   the pin: ' + (Get-Pin $rel 'LOOP_RULES'))
Write-Output ('  the increments this history holds: ' + $incs.Count)
$qFiles = @([regex]::Matches($qa, 'files=(\d+)\s+parsed=(\d+)\s+actionable=(\d+)\s+notices=(\d+)'))
$qGates = @([regex]::Matches($qa, 'MEASURED:\s*(\d+)\s+`check_\*` gates'))
$liveGates = @(Get-ChildItem -LiteralPath (Join-Path $root '_verify') -Filter 'check_*.ps1' -File -ErrorAction SilentlyContinue).Count
if ($qFiles.Count -gt 0) {
  Write-Output ('  the plan file quotes: files=' + $qFiles[0].Groups[1].Value + ' notices=' + $qFiles[0].Groups[4].Value + '   the tree''s pins say: files=' + (Get-Pin $rel 'SELF_FILES'))
}
if ($qGates.Count -gt 0) {
  Write-Output ('  the plan file quotes: ' + $qGates[0].Groups[1].Value + ' check gates   the tree holds: ' + $liveGates)
}

$probs = @(Get-ChecklistProblems $qa $loop $rel $incs $root)
foreach ($p in $probs) {
  Write-Output ''
  Write-Output $p
}
$fail += $probs.Count

Write-Output ''
if ($fail -eq 0) {
  Write-Output ('CHECKLIST OK: ' + $taskCount + ' task(s), all ticked, every one riding an increment this')
  Write-Output ('history holds, every path it names resolving, and the LOOP''s ' + $rules.Count + ' rule(s) numbered')
  Write-Output 'contiguously and matching the pin, and every number the plan file quotes matching the tree.'
  exit 0
}
Write-Output ('CHECKLIST FAILED: ' + $fail + ' problem(s).')
exit 1
