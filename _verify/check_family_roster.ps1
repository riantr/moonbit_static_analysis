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
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File _verify\check_family_roster.ps1
$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $PSScriptRoot
$core = Join-Path $root 'src\core\core.mbt'
$fail = 0

# The number of families. Pinned, because a family added without an id --
# or an id added without a family -- is exactly what the checks below are for.
$WANT_FAMILIES = 12

if (-not (Test-Path -LiteralPath $core)) {
  Write-Output ('ABORT: no ' + $core)
  exit 1
}
$src = [System.IO.File]::ReadAllText($core, [System.Text.Encoding]::UTF8)

# ------------------------------------------------------------------ 1. the enum ---
Write-Output '=== 1. the Family enum ==='
$enumM = [regex]::Match($src, '(?s)pub\(all\) enum Family \{(.*?)\}\s*derive')
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
$confM = [regex]::Match($src, '(?s)pub\(all\) enum Confidence \{(.*?)\}\s*derive')
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

Write-Output ''
if ($fail -eq 0) {
  Write-Output ('ROSTER OK: ' + $tags.Count + ' families, one id each, contiguous from MSA-001, and the two tables are exact inverses.')
  exit 0
}
Write-Output ('ROSTER FAILED: ' + $fail + ' problem(s).')
exit 1
