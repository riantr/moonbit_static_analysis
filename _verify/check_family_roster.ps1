# The FAMILY ROSTER is HAND-ALLOCATED, and a hand-allocated table is a table
# that rots.
#
# WHY AN ID AT ALL. The public NAME of a family is a second, hand-maintained
# vocabulary: five of the original eleven names are not the tag with its `F`
# removed (`FParse` -> `ParseError`, `FAssignType` -> `AssignTypeMismatch`,
# `FArgType` -> `ArgTypeMismatch`, `FOpMismatch` -> `OperatorMismatch`,
# `FCondBool` -> `NonBooleanCond`). A consumer that pins `"family":
# "ArgTypeMismatch"` in a suppression or a CI filter gets no warning at all
# when the name moves, because a name is not a contract. An id IS a contract:
# it is allocated once and NEVER RENUMBERED.
#
# WHY A GATE. Two tables exist, and they are written out by hand:
#
#   * `Family::id`       -- the family to its id
#   * `family_by_id`     -- the id to the family
#
# The compiler enforces the FIRST one: a new family breaks the build there,
# because the match is exhaustive over the enum. It enforces NOTHING about the
# SECOND one, because that match is on strings and a missing arm would simply
# never match -- a family whose id could not be selected in a profile and
# could not be named in a `nosec`, with nothing saying so.
#
# Two tables that are written down twice will disagree with each other
# eventually, and a disagreement between them is invisible to the reader: the
# analyzer would quietly accept one spelling of an id and not the other.
#
# So this gate compares them, and it compares them to the ENUM:
#
#   1. every member of the `Family` enum has exactly one id;
#   2. no id is used twice;
#   3. the ids form a CONTIGUOUS run from MSA-001 -- a gap means a number was
#      allocated and never used, and a family given a number in the middle of
#      the run means every suppression written against that number now names
#      a different family;
#   4. `family_by_id` is the EXACT INVERSE of `Family::id`;
#   5. the id has the shape `MSA-NNN`;
#   6. the count matches the pin.
#
# The enum is read from the SOURCE, not from a running analyzer: this gate
# costs milliseconds, runs next to anything, and cannot be fooled by a stale
# build artifact.
#
# 0615. A GATE THAT HAS NEVER BEEN SHOWN TO GO RED IS A COMMENT. The roster
# gate reads exactly THREE files -- `src/core/core.mbt`, `src/core/soundiness.mbt`
# and `_verify/release.ps1` -- so a defect can be injected into a COPY of those
# three and the gate pointed at the copy. `-Root` is what points it there; the
# real tree is never touched.
#
# THE CONTROL IS NOT OPTIONAL. A copy that is not green proves nothing: a gate
# that says "the tables disagree" on an unmodified tree is not a gate. So the
# self-test runs the copy twice, once as it is and once with the defect in it,
# and BOTH have to hold.
#
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File _verify\check_family_roster.ps1
#   powershell -NoProfile -ExecutionPolicy Bypass -File _verify\check_family_roster.ps1 -SelfTest
param([switch]$SelfTest, [string]$Root = '')
$ErrorActionPreference = 'Continue'
$root = if ($Root) { $Root } else { Split-Path -Parent $PSScriptRoot }
$core = Join-Path $root 'src\core\core.mbt'
$fail = 0

# The number of families. Pinned, because a family added without an id --
# or an id added without a family -- is exactly what the checks below are for.
$WANT_FAMILIES = 18

# ================================================================= the self-test ===
if ($SelfTest) {
  Write-Output '=== the family roster, shown to go red ==='
  $bad = 0

  # THE THREE FILES THIS GATE READS. A copy of these three IS a tree this
  # gate can be pointed at; nothing else in the repository is read.
  function New-GateCopy {
    $tmp = Join-Path $env:TEMP ('famroster_selftest_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path (Join-Path $tmp 'src\core') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $tmp '_verify') -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $root 'src\core\core.mbt')      -Destination (Join-Path $tmp 'src\core\core.mbt') -Force
    Copy-Item -LiteralPath (Join-Path $root 'src\core\soundiness.mbt') -Destination (Join-Path $tmp 'src\core\soundiness.mbt') -Force
    Copy-Item -LiteralPath (Join-Path $root '_verify\release.ps1')     -Destination (Join-Path $tmp '_verify\release.ps1') -Force
    return $tmp
  }

  # THE GATE, RUN AGAINST A COPY. The script that runs is THIS one -- the copy
  # holds the data, not the checker, so the checker under test is the checker
  # that ships.
  function Run-GateAt([string]$Dir) {
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $o = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'check_family_roster.ps1') -Root $Dir 2>&1 | Out-String
    $code = $LASTEXITCODE
    $ErrorActionPreference = $prev
    return [pscustomobject]@{ Code = $code; Out = $o }
  }

  # THE CONTROL. The unmodified copy must be GREEN. Without this, a red copy
  # proves nothing -- the gate could be red for a reason that has nothing to
  # do with the injected defect.
  $ctl = New-GateCopy
  try {
    $r1 = Run-GateAt $ctl
    $ctlOk = ($r1.Code -eq 0)
    Write-Output ('  CONTROL  exit=' + $r1.Code + '  -> ' + $(if ($ctlOk) { 'as it must be' } else { 'WRONG' }))
    if (-not $ctlOk) {
      $bad++
      foreach ($ln in ($r1.Out -split "`r?`n" | Where-Object { $_.Trim() } | Select-Object -Last 8)) {
        Write-Output ('      | ' + $ln.Trim())
      }
    }
  } finally {
    Remove-Item -LiteralPath $ctl -Recurse -Force -ErrorAction SilentlyContinue
  }

  # THE TWO FAULTS. They are the two properties this gate exists for: the ids
  # are allocated ONCE and never renumbered, and the two tables are exact
  # inverses. Each defect is injected into its own fresh copy, so one fault
  # cannot mask another.
  $faults = @(
    [pscustomobject]@{
      N = 'a family id renumbered'
      Expect = 'the ids are not contiguous'
      Apply = {
        param($dir)
        $p = Join-Path $dir 'src\core\core.mbt'
        $t = [System.IO.File]::ReadAllText($p)
        if ($t.IndexOf('FTaintFlow => "MSA-018"') -lt 0) { return $false }
        $t = $t.Replace('FTaintFlow => "MSA-018"', 'FTaintFlow => "MSA-019"')
        [System.IO.File]::WriteAllText($p, $t, (New-Object System.Text.UTF8Encoding($false)))
        return $true
      }
    }
    [pscustomobject]@{
      N = 'the inverse table disagreeing with the forward one'
      Expect = 'in Family::id and'
      Apply = {
        param($dir)
        $p = Join-Path $dir 'src\core\core.mbt'
        $t = [System.IO.File]::ReadAllText($p)
        if ($t.IndexOf('"MSA-003" => Some(FUnusedLocal)') -lt 0) { return $false }
        $t = $t.Replace('"MSA-003" => Some(FUnusedLocal)', '"MSA-003" => Some(FUnusedParam)')
        [System.IO.File]::WriteAllText($p, $t, (New-Object System.Text.UTF8Encoding($false)))
        return $true
      }
    }
  )

  foreach ($f in $faults) {
    $c = New-GateCopy
    try {
      $applied = & $f.Apply $c
      if (-not $applied) {
        Write-Output ('  MISSED  ' + $f.N + '  (the anchor was not found -- the defect was never injected)')
        $bad++
        continue
      }
      $r = Run-GateAt $c
      $caught = ($r.Code -ne 0) -and ($r.Out.Contains($f.Expect))
      Write-Output ('  ' + $(if ($caught) { 'CAUGHT ' } else { 'MISSED ' }) + $f.N +
                    '  (exit ' + $r.Code + ', expected "' + $f.Expect + '")')
      if (-not $caught) {
        $bad++
        foreach ($ln in ($r.Out -split "`r?`n" | Where-Object { $_.Trim() } | Select-Object -Last 8)) {
          Write-Output ('      | ' + $ln.Trim())
        }
      }
    } finally {
      Remove-Item -LiteralPath $c -Recurse -Force -ErrorAction SilentlyContinue
    }
  }

  Write-Output ''
  if ($bad -eq 0) {
    Write-Output ('SELFTEST OK: the control passed and all ' + $faults.Count + ' injected defects were caught.')
    exit 0
  }
  Write-Output ('SELFTEST FAILED: ' + $bad + ' of ' + ($faults.Count + 1) + ' checks did not hold.')
  exit 1
}

if (-not (Test-Path -LiteralPath $core)) {
  Write-Output ('ABORT: no ' + $core)
  exit 1
}
$src = [System.IO.File]::ReadAllText($core, [System.Text.Encoding]::UTF8)

# ------------------------------------------------------------------ 1. the enum ---
Write-Output '=== 1. the Family enum ==='
$enumM = [regex]::Match($src, '(?s)pub\(all\) enum Family \{(.*?)\n\}')
if (-not $enumM.Success) {
  Write-Output '  MISSING: the Family enum was not found in src/core/core.mbt.'
  Write-Output '          The source changed shape, and this gate cannot read it.'
  exit 1
}
$tags = @()
foreach ($l in ($enumM.Groups[1].Value -split "`r?`n")) {
  $t = $l.Trim()
  if ($t -match '^F[A-Za-z]+$') { $tags += $t }
}
Write-Output ('  ' + $tags.Count + ' members: ' + ($tags -join ', '))
if ($tags.Count -ne $WANT_FAMILIES) {
  Write-Output ('  FAIL: the enum has ' + $tags.Count + ' members, pinned ' + $WANT_FAMILIES + '.')
  $fail++
}

# ------------------------------------------------------- 2. the forward table ---
Write-Output ''
Write-Output '=== 2. Family::id -- the family to its id ==='
$fwdM = [regex]::Match($src, '(?s)pub fn Family::id\(self : Family\) -> String \{(.*?)\n\}')
if (-not $fwdM.Success) {
  Write-Output '  MISSING: Family::id was not found.'
  $fail++
} else {
  $fwd = @{}
  foreach ($m in [regex]::Matches($fwdM.Groups[1].Value, 'F([A-Za-z]+)\s*=>\s*"(MSA-\d{3})"')) {
    $fwd['F' + $m.Groups[1].Value] = $m.Groups[2].Value
  }
  Write-Output ('  ' + $fwd.Count + ' ids')
  if ($fwd.Count -ne $tags.Count) {
    Write-Output ('  FAIL: Family::id gives ' + $fwd.Count + ' ids for ' + $tags.Count + ' families.')
    $fail++
  }
  foreach ($t in $tags) {
    if (-not $fwd.ContainsKey($t)) {
      Write-Output ('  FAIL: the family ' + $t + ' has no id.')
      $fail++
    }
  }
  # ONE id per family, and the SHAPE of the id.
  $seen = @{}
  foreach ($t in $fwd.Keys) {
    $id = $fwd[$t]
    if ($id -notmatch '^MSA-\d{3}$') {
      Write-Output ('  FAIL: the id of ' + $t + ' is "' + $id + '", which is not MSA-NNN.')
      $fail++
    }
    if ($seen.ContainsKey($id)) {
      Write-Output ('  FAIL: the id ' + $id + ' is used by both ' + $seen[$id] + ' and ' + $t + '.')
      $fail++
    }
    $seen[$id] = $t
  }
  # CONTIGUITY: MSA-001, MSA-002, ... with no gap and no repeat. This is the
  # "never renumbered" property, made checkable.
  $nums = @($seen.Keys | ForEach-Object { [int]($_ -replace '^MSA-', '') } | Sort-Object)
  for ($i = 0; $i -lt $nums.Count; $i++) {
    if ($nums[$i] -ne ($i + 1)) {
      Write-Output ('  FAIL: the ids are not contiguous: position ' + ($i + 1) + ' holds ' + $nums[$i] + '.')
      Write-Output '        A gap means a number was allocated and never used.'
      $fail++
      break
    }
  }
  Write-Output ('  ids: ' + (($seen.Keys | Sort-Object) -join ', '))
}

# ------------------------------------------------------- 3. the inverse table ---
Write-Output ''
Write-Output '=== 3. family_by_id -- the id to the family ==='
$invM = [regex]::Match($src, '(?s)pub fn family_by_id\(id : String\) -> Family\? \{(.*?)\n\}')
if (-not $invM.Success) {
  Write-Output '  MISSING: family_by_id was not found.'
  $fail++
} else {
  $inv = @{}
  foreach ($m in [regex]::Matches($invM.Groups[1].Value, '"(MSA-\d{3})"\s*=>\s*Some\(F([A-Za-z]+)\)')) {
    $inv[$m.Groups[1].Value] = 'F' + $m.Groups[2].Value
  }
  Write-Output ('  ' + $inv.Count + ' ids')
  if ($inv.Count -ne $tags.Count) {
    Write-Output ('  FAIL: family_by_id knows ' + $inv.Count + ' ids for ' + $tags.Count + ' families.')
    $fail++
  }
  # THE INVERSE, exactly. Both directions: an id that maps to a different
  # family is as wrong as an id that maps to none.
  foreach ($t in $tags) {
    if (-not $fwd.ContainsKey($t)) { continue }
    $id = $fwd[$t]
    if (-not $inv.ContainsKey($id)) {
      Write-Output ('  FAIL: the id ' + $id + ' (' + $t + ') names no family in family_by_id.')
      $fail++
    } elseif ($inv[$id] -ne $t) {
      Write-Output ('  FAIL: the id ' + $id + ' is ' + $t + ' in Family::id and ' + $inv[$id] + ' in family_by_id.')
      $fail++
    }
  }
  foreach ($id in $inv.Keys) {
    if (-not $seen.ContainsKey($id)) {
      Write-Output ('  FAIL: family_by_id knows the id ' + $id + ', which Family::id does not hand out.')
      $fail++
    }
  }
}

# ------------------------------------------- 4. the confidence vocabulary -------
Write-Output ''
Write-Output '=== 4. the confidence vocabulary ==='
$confM = [regex]::Match($src, '(?s)pub\(all\) enum Confidence \{(.*?)\n\}')
if (-not $confM.Success) {
  Write-Output '  MISSING: the Confidence enum was not found.'
  $fail++
} else {
  $vals = @()
  foreach ($l in ($confM.Groups[1].Value -split "`r?`n")) {
    $t = $l.Trim()
    if ($t -match '^[A-Z][A-Za-z]+$') { $vals += $t }
  }
  Write-Output ('  ' + $vals.Count + ' values: ' + ($vals -join ', '))
  if ($vals.Count -ne 3) {
    Write-Output ('  FAIL: the confidence axis has ' + $vals.Count + ' values, and it must have three:')
    Write-Output '        high (the lens read the thing), low (it read a name), undecided (it could not decide).'
    $fail++
  }
  $names = @()
  foreach ($m in [regex]::Matches($src, '(?m)^\s+(High|Low|Undecided) => "([a-z]+)"')) {
    $names += $m.Groups[2].Value
  }
  Write-Output ('  the three names: ' + ($names -join ', '))
  if (($names | Sort-Object -Unique).Count -ne $names.Count) {
    Write-Output '  FAIL: two confidence values share a name.'
    $fail++
  }
  foreach ($want in @('high','low','undecided')) {
    if ($names -notcontains $want) {
      Write-Output ('  FAIL: no confidence is called "' + $want + '".')
      $fail++
    }
  }
}

# --------------------------------------------- 5. the family CONTRACTS --------
#
# 0520. A family used to be an id, a severity and a confidence: enough to filter
# and to suppress, and not enough to know what the tool just told you. Each
# family now carries three parts -- what it ASSERTS, the ASSUMPTION under which
# that assertion is sound, and what it deliberately does NOT cover -- and this
# section is what stops "we will document it later" from shipping.
#
# THE THREE TABLES ARE READ THE SAME WAY `Family::id` IS, so one parser owns
# them all and a new projection is one line here. An arm that is empty, or a
# family with no arm, is a failure; the compile-time match makes a MISSING arm
# impossible, so what is left to check is that the text is real.
Write-Output ''
Write-Output '=== 5. the family contracts (property, assumption, excluded) ==='
foreach ($part in @('property', 'assumption', 'excluded', 'reach')) {
  $cm = [regex]::Match($src, '(?s)pub fn Family::' + $part + '\(self : Family\) -> String \{(.*?)\n\}')
  if (-not $cm.Success) {
    Write-Output ('  MISSING: Family::' + $part + ' was not found.')
    Write-Output '           A family without a contract is a family whose claim the reader cannot check.'
    $fail++
    continue
  }
  # `(?s)` and `\s*` both matter: `moon fmt` chooses where to break the arm, and
  # this gate must not care which spelling the formatter picked.
  $arms = @{}
  foreach ($m in [regex]::Matches($cm.Groups[1].Value, '(?s)F([A-Za-z]+)\s*=>\s*"((?:[^"\\]|\\.)*)"')) {
    $arms['F' + $m.Groups[1].Value] = $m.Groups[2].Value
  }
  Write-Output ('  ' + $part + ': ' + $arms.Count + ' arm(s)')
  if ($arms.Count -ne $tags.Count) {
    Write-Output ('  FAIL: Family::' + $part + ' has ' + $arms.Count + ' arms for ' + $tags.Count + ' families.')
    $fail++
  }
  foreach ($t in $tags) {
    if (-not $arms.ContainsKey($t)) {
      Write-Output ('  FAIL: the family ' + $t + ' declares no ' + $part + '.')
      $fail++
      continue
    }
    $v = $arms[$t].Trim()
    if ($v -eq '') {
      Write-Output ('  FAIL: the ' + $part + ' of ' + $t + ' is empty.')
      $fail++
      continue
    }
    # A contract that is one word is a label, not a contract. The floor is low
    # on purpose -- it is not a style rule -- but it does reject "n/a" and "todo".
    if ($v.Length -lt 15) {
      Write-Output ('  FAIL: the ' + $part + ' of ' + $t + ' is ' + $v.Length + ' characters: "' + $v + '".')
      Write-Output '        A contract that short is a label; it cannot tell a reader what is claimed.'
      $fail++
    }
  }
}

# ------------------------------------------ 6. the SOUNDINESS classification ------
#
# 0602. The deck is `Soundiness` (Yue Li and Tian Tan, Nanjing University, 2021
# Fall), and its p.14 gives three verdicts -- sound, soundy, unsound -- whose
# difference is the CAUSE of the gap, not its size:
#
#   A sound analysis requires to capture all dynamic behaviors
#   A soundy analysis aims to capture all dynamic behaviors with certain hard
#   language features unsoundly handled within reason
#   An unsound analysis deliberately ignores certain behaviors in its design
#   for better efficiency, precision or accessibility
#
# And p.10 is the complaint the tree answers: "Treatments to hard language
# features are usually omitted or only mentioned in an off-hand manner in some
# impl/eval parts in papers."
#
# So the tree declares, per family, its EXCLUSIONS with the cause of each, and
# the VERDICT IS DERIVED. This section derives it AGAIN, from the SOURCE, and
# compares it with the pin -- which is the point: a verdict written out by
# hand in the code could drift from the causes, and nothing would say so.
#
# AND THE EXCLUSION'S `text` IS A QUOTE of the family's own `excluded`
# contract, and this section checks that it really is a quote. Without that
# check the exclusion list would be a SECOND table, written down twice, and
# the two would drift -- the exact failure this gate was built for.
Write-Output ''
Write-Output '=== 6. the soundiness classification (0602) ==='
$sn = Join-Path $root 'src\core\soundiness.mbt'
if (-not (Test-Path -LiteralPath $sn)) {
  Write-Output '  MISSING: src/core/soundiness.mbt is not in the tree.'
  Write-Output '           The deck''s three-way verdict is derived in that file, and this gate has nothing to derive.'
  $fail++
} else {
  $snTxt = [System.IO.File]::ReadAllText($sn, [System.Text.Encoding]::UTF8)

  # --- the two vocabularies ------------------------------------------------
  foreach ($v in @(@('Soundiness', 3), @('ExclusionCause', 2))) {
    $vm = [regex]::Match($snTxt, '(?s)pub\(all\) enum ' + $v[0] + ' \{(.*?)\n\}')
    if (-not $vm.Success) {
      Write-Output ('  MISSING: the ' + $v[0] + ' enum was not found.')
      $fail++
      continue
    }
    $vals = @()
    foreach ($l in ($vm.Groups[1].Value -split "`r?`n")) {
      $t = $l.Trim()
      if ($t -match '^[A-Z][A-Za-z]+$') { $vals += $t }
    }
    Write-Output ('  ' + $v[0] + ': ' + $vals.Count + ' values: ' + ($vals -join ', '))
    if ($vals.Count -ne $v[1]) {
      Write-Output ('  FAIL: the ' + $v[0] + ' axis has ' + $vals.Count + ' values, and it must have ' + $v[1] + '.')
      $fail++
    }
  }

  # --- the per-family exclusions -------------------------------------------
  $exM = [regex]::Match($snTxt, '(?s)pub fn Family::exclusions\(self : Family\)\s*->\s*Array\[Exclusion\]\s*\{(.*?)\n\}')
  if (-not $exM.Success) {
    Write-Output '  MISSING: Family::exclusions was not found.'
    $fail++
  } else {
    $armStarts = [regex]::Matches($exM.Groups[1].Value, '(?m)^\s*(F[A-Za-z0-9]+)\s*=>')
    $arms = @{}
    for ($i = 0; $i -lt $armStarts.Count; $i++) {
      $tag = $armStarts[$i].Groups[1].Value
      $from = $armStarts[$i].Index
      $to = if ($i + 1 -lt $armStarts.Count) { $armStarts[$i + 1].Index } else { $exM.Groups[1].Value.Length }
      $body = $exM.Groups[1].Value.Substring($from, $to - $from)
      $exs = @()
      foreach ($p in [regex]::Matches($body, '(?s)Exclusion::\{(.*?)\n\s*\},')) {
        $idM = [regex]::Match($p.Groups[1].Value, 'id:\s*"([^"]+)"')
        $cM = [regex]::Match($p.Groups[1].Value, 'cause:\s*([A-Za-z]+)')
        $tM = [regex]::Match($p.Groups[1].Value, '(?s)text:\s*"((?:[^"\\]|\\.)*)"')
        if (-not $idM.Success -or -not $cM.Success -or -not $tM.Success) {
          Write-Output ('  FAIL: an exclusion of ' + $tag + ' is missing its id, its cause or its text.')
          $fail++
          continue
        }
        $exs += @{ id = $idM.Groups[1].Value; cause = $cM.Groups[1].Value; text = $tM.Groups[1].Value }
      }
      $arms[$tag] = $exs
    }
    Write-Output ('  Family::exclusions: ' + $arms.Count + ' arm(s) for ' + $tags.Count + ' families')
    if ($arms.Count -ne $tags.Count) {
      Write-Output ('  FAIL: Family::exclusions has ' + $arms.Count + ' arms for ' + $tags.Count + ' families.')
      $fail++
    }

    # the family's own `excluded` contract, read the same way section 5 reads it
    $exclM = [regex]::Match($src, '(?s)pub fn Family::excluded\(self : Family\) -> String \{(.*?)\n\}')
    $contract = @{}
    foreach ($m in [regex]::Matches($exclM.Groups[1].Value, '(?s)F([A-Za-z]+)\s*=>\s*"((?:[^"\\]|\\.)*)"')) {
      $contract['F' + $m.Groups[1].Value] = $m.Groups[2].Value
    }

    # --- the derivation, and the pin -----------------------------------------
    $seenIds = @{}
    $counts = @{ sound = 0; soundy = 0; unsound = 0 }
    $unsoundIds = @()
    foreach ($t in $tags) {
      if (-not $arms.ContainsKey($t)) {
        Write-Output ('  FAIL: the family ' + $t + ' declares no exclusion, so it has no verdict.')
        $fail++
        continue
      }
      $exs = $arms[$t]
      if ($exs.Count -eq 0) {
        Write-Output ('  FAIL: the family ' + $t + ' declares an empty exclusion list.')
        $fail++
        continue
      }
      $verdict = 'soundy'
      foreach ($e in $exs) {
        if ($seenIds.ContainsKey($e.id)) {
          Write-Output ('  FAIL: the exclusion id ' + $e.id + ' is used twice.')
          $fail++
        }
        $seenIds[$e.id] = $true
        if ($e.cause -ne 'HardFeature' -and $e.cause -ne 'Deliberate') {
          Write-Output ('  FAIL: the exclusion ' + $e.id + ' has the cause ' + $e.cause + ', which is neither HardFeature nor Deliberate.')
          $fail++
        }
        if ($e.cause -eq 'Deliberate') {
          $verdict = 'unsound'
          $unsoundIds += $e.id
        }
        # THE QUOTE: the exclusion's text must be IN the family's own contract.
        if (-not $contract.ContainsKey($t) -or -not $contract[$t].Contains($e.text)) {
          Write-Output ('  FAIL: the exclusion ' + $e.id + ' quotes "' + $e.text + '", which is not in the family''s own excluded contract.')
          $fail++
        }
      }
      $counts[$verdict] = $counts[$verdict] + 1
    }
    Write-Output ('  derived: sound=' + $counts['sound'] + '  soundy=' + $counts['soundy'] + '  unsound=' + $counts['unsound'])
    Write-Output ('  the deliberate treatments: ' + ($unsoundIds -join ', '))
    # THE PIN, read from release.ps1 so there is one authority for a number.
    $relTxt = [System.IO.File]::ReadAllText((Join-Path $root '_verify\release.ps1'), [System.Text.Encoding]::UTF8)
    foreach ($pair in @(@('SOUNDINESS_SOUND', $counts['sound']), @('SOUNDINESS_SOUNDY', $counts['soundy']), @('SOUNDINESS_UNSOUND', $counts['unsound']))) {
      $pm = [regex]::Match($relTxt, "\`$" + $pair[0] + "\s*=\s*'(\d+)'")
      if (-not $pm.Success) {
        Write-Output ('  FAIL: release.ps1 has no $' + $pair[0] + ' pin, so the derived count cannot be checked.')
        $fail++
        continue
      }
      if ([int]$pm.Groups[1].Value -ne $pair[1]) {
        Write-Output ('  FAIL: $' + $pair[0] + ' is pinned at ' + $pm.Groups[1].Value + ' and the source derives ' + $pair[1] + '.')
        $fail++
      }
    }
    $unPin = [regex]::Match($relTxt, "\`$SOUNDINESS_UNSOUND_IDS\s*=\s*'([^']*)'")
    if (-not $unPin.Success) {
      Write-Output '  FAIL: release.ps1 has no $SOUNDINESS_UNSOUND_IDS pin.'
      $fail++
    } else {
      $want = ($unPin.Groups[1].Value -split '\|')
      if (($want -join ',') -ne ($unsoundIds -join ',')) {
        Write-Output ('  FAIL: $SOUNDINESS_UNSOUND_IDS is pinned at "' + $unPin.Groups[1].Value + '" and the source derives "' + ($unsoundIds -join '|') + '".')
        $fail++
      }
    }
  }
}

Write-Output ''
if ($fail -eq 0) {
  Write-Output ('ROSTER OK: ' + $tags.Count + ' families, one id each, contiguous from MSA-001, the two tables are exact inverses,')
  Write-Output '           every family declares a non-empty property, assumption and excluded, and every family''s'
  Write-Output '           soundiness verdict is DERIVED from the cause of its exclusions and matches the pin.'
  exit 0
}
Write-Output ('ROSTER FAILED: ' + $fail + ' problem(s).')
exit 1
