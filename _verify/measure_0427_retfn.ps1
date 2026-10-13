# 0.4.27: how many RETURN positions carry a parenthesised FUNCTION TYPE?
#
# THIS SCRIPT HAS NOW REPORTED A WRONG ZERO TWICE, and both are kept here because
# the second one is the interesting one.
#
# ZERO #1: an earlier version matched `\([^()]*\)`, which cannot match `(() -> Int)`
# -- the inner group refuses a nested paren, so it reported "none found" for a
# shape that contains one by construction. Fixed with a balanced scan.
#
# ZERO #2 (this file's predecessor): the balanced scan was correct, and it still
# reported ZERO for all six corpora. The bug was in the PREFIX, not the paren
# logic:
#
#     \bfn\s+[A-Za-z_]\w*\s*\([^()]*\)\s*->\s*\(
#
# Every clause of that is wrong for ordinary MoonBit:
#   - `fn` is immediately followed by `[`, so `fn[T] ServiceTask::start` never
#     matches `\bfn\s+[A-Za-z_]` -- generics are everywhere in this corpus;
#   - `[A-Za-z_]\w*` does not match `ServiceTask::start`, because of the `::`;
#   - `\([^()]*\)` cannot span a MULTI-LINE parameter list, or one whose
#     parameters are themselves parenthesised.
#
# And the shape it missed is the single most common one in the corpus:
#
#     pub fn[T] ServiceTask::start(
#       self : ServiceTask[T],
#       complete : (ServiceTaskResult[T]) -> Unit,
#     ) -> (() -> Unit)? {            <-- `-> (` and an arrow INSIDE
#
# So the fix under test moves three real moui files from PARTIAL to fully parsed,
# while the measurement said there was nothing to move.
#
# THE LESSON, which is why this is longer than the answer: a matcher that is too
# NARROW does not report "none found", it reports "I did not look", and the two
# are the same shape on screen. Matching a real signature is a parsing problem;
# regexing one is a bet. So this version does not try to recognise the signature
# at all. It finds every `->` token, and asks whether the group that follows it
# contains an arrow. That is the defect shape wherever it occurs, and it cannot
# fail to look at a signature because it does not need to know what a signature
# looks like.
#
# THE CONTROL IS THE A/B, NOT A SYNTHETIC FILE. A synthetic file proves the
# matcher can match something. What proves it finds the real population is that
# it must find the three files the analyzer's own before/after diff says changed:
# services/service_task.mbt, core/program_subscription.mbt and
# backend/common/services/service_async_queue.mbt. Asserted at the bottom; if a
# future edit makes this report 0 again, the gate says so instead of the reader
# trusting it.
#
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File _verify/measure_0427_retfn.ps1
$ErrorActionPreference = 'Continue'
$repos = Join-Path (Split-Path -Parent $PSScriptRoot) '.repos'

$targets = [ordered]@{
  'moui'            = "$repos\wzzc-dev\moui\0.1.12"
  'moonbit_labeler' = "$repos\riantr\moonbit_labeler\0.2.13"
  'moonbit_image'   = "$repos\riantr\moonbit_image\0.3.7"
  'async'           = "$repos\moonbitlang\async\0.22.4"
  'proton'          = "$repos\moonbit-community\proton\0.3.4"
  'proton_contract' = "$repos\moonbit-community\proton_contract\0.3.4"
}

# The files the analyzer's own A/B (0.4.26b -> 0.4.27 dumps, same tree, two
# builds) says changed from PARTIAL to FOUND. The matcher MUST find every one.
$mustFind = @(
  'services\service_task.mbt',
  'core\program_subscription.mbt',
  'backend\common\services\service_async_queue.mbt'
)

# Strip block and line comments and string literals, so an arrow inside prose or
# a quoted fragment cannot be counted. Leaving them in makes the result an UPPER
# BOUND, which is safe for "is it zero" and useless for "how many".
function Strip-NonCode([string]$t) {
  $sb = New-Object System.Text.StringBuilder
  $n = $t.Length; $i = 0
  while ($i -lt $n) {
    $ch = $t[$i]
    if ($ch -eq '/' -and $i + 1 -lt $n -and $t[$i+1] -eq '/') { while ($i -lt $n -and $t[$i] -ne "`n") { $i++ }; continue }
    if ($ch -eq '#' ) { while ($i -lt $n -and $t[$i] -ne "`n") { $i++ }; continue }
    if ($ch -eq '/' -and $i + 1 -lt $n -and $t[$i+1] -eq '*') {
      $i += 2
      while ($i + 1 -lt $n -and -not ($t[$i] -eq '*' -and $t[$i+1] -eq '/')) { if ($t[$i] -eq "`n") { [void]$sb.Append("`n") }; $i++ }
      $i += 2; continue
    }
    if ($ch -eq '"') {
      $i++
      while ($i -lt $n) { if ($t[$i] -eq '\\') { $i += 2; continue }; if ($t[$i] -eq '"') { break }; $i++ }
      $i++; [void]$sb.Append('""'); continue
    }
    [void]$sb.Append($ch); $i++
  }
  $sb.ToString()
}

function Get-Balanced([string]$t, [int]$open) {
  $depth = 0; $i = $open; $n = $t.Length
  while ($i -lt $n) {
    $ch = $t[$i]
    if ($ch -eq '(') { $depth++ }
    elseif ($ch -eq ')') { $depth--; if ($depth -eq 0) { return $i } }
    $i++
  }
  -1
}

$found = @{}
$bad = 0
foreach ($k in $targets.Keys) {
  $dir = $targets[$k]
  if (-not (Test-Path $dir)) { Write-Output "MISSING $k"; $bad++; continue }
  $files = Get-ChildItem -Path $dir -Recurse -File -Filter '*.mbt' -ErrorAction SilentlyContinue |
           Where-Object { $_.FullName -notmatch '\\\.mooncakes\\' }
  if (@($files).Count -eq 0) {
    Write-Output ("{0,-16} NO CORPUS -- 0 files under {1}" -f $k, $dir); $bad++; continue
  }
  $hits = 0; $hitFiles = @{}; $tuple = 0; $scalar = 0; $unbal = 0
  foreach ($f in $files) {
    try { $raw = [System.IO.File]::ReadAllText($f.FullName) } catch { continue }
    $t = Strip-NonCode $raw
    # EVERY arrow, wherever it is. No attempt to recognise a signature.
    for ($i = 0; $i + 1 -lt $t.Length; $i++) {
      if ($t[$i] -ne '-' -or $t[$i+1] -ne '>') { continue }
      $j = $i + 2
      while ($j -lt $t.Length -and [char]::IsWhiteSpace($t[$j])) { $j++ }
      if ($j -ge $t.Length -or $t[$j] -ne '(') { continue }
      $close = Get-Balanced $t $j
      if ($close -lt 0) { $unbal++; $i = $j; continue }
      $inner = $t.Substring($j + 1, $close - $j - 1)
      $rel = $f.FullName.Substring($dir.Length + 1)
      if ($inner.Contains('->')) { $hits++; $hitFiles[$rel] = $true }
      elseif ($inner.Contains(',')) { $tuple++ }
      else { $scalar++ }
      $i = $close
    }
  }
  Write-Output ("{0,-16} files={1,-5} FN-TYPE={2,-4} in {3} file(s); look-alikes: tuple={4} paren-scalar={5}; unbalanced={6}" -f `
    $k, $files.Count, $hits, $hitFiles.Count, $tuple, $scalar, $unbal)
  if ($hitFiles.Count -gt 0) {
    $hitFiles.Keys | Sort-Object | ForEach-Object { Write-Output ("      " + $_); $found[$k + '|' + $_] = $true }
  }
}
Write-Output ''
Write-Output '--- CONTROL: files the analyzer A/B says the fix unblocked ---'
foreach ($m in $mustFind) {
  $key = 'moui|' + $m
  if ($found.ContainsKey($key)) { Write-Output ("  FOUND     " + $m) }
  else { Write-Output ("  *** MISSED " + $m + " -- this matcher is too narrow again ***"); $bad++ }
}
if ($bad -gt 0) { Write-Output ''; Write-Output "ABORT: $bad problem(s)."; exit 1 }
exit 0