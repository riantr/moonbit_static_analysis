# 0.4.26: how big is the LATENT surface of the tail-expression defect?
#
# The observable is already measured and it is ZERO: no `None`-flavoured method
# error in any of the six corpora, 12,428 files. That is the number that moves
# the actionable count. This script measures something different -- how many
# functions in real MoonBit are even ELIGIBLE to be poisoned -- because an earlier
# note claimed this defect was "probably bigger than raise itself", and that claim
# has never been tested.
#
# A function is eligible when it has a DECLARED return type and its body's LAST
# statement is an expression rather than `return` / `raise`.
#
# NOT A GREP. A one-line regex cannot tell a function's last statement from a
# nested block's, so this walks braces properly, skipping `//` comments, string
# literals and `#"` block strings `"#`. It reports a sanity total against a plain
# `fn` count so a broken matcher is visible instead of quietly reporting zero.
#
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File _verify/measure_0426_tail_surface.ps1
$ErrorActionPreference = 'Continue'
$repos = "$env:TEMP\riantr_sibling_scans\riantr_moonbit_labeler\.repos"

$targets = [ordered]@{
  'moui'            = "$repos\wzzc-dev\moui\0.1.12"
  'moonbit_labeler' = "$repos\riantr\moonbit_labeler\0.2.13"
  'moonbit_image'   = "$repos\riantr\moonbit_image\0.3.7"
  'async'           = "$repos\moonbitlang\async\0.22.4"
  'proton'          = "$repos\moonbit-community\proton\0.3.4"
  'proton_contract' = "$repos\moonbit-community\proton_contract\0.3.4"
}

# Scan one file's text and return
#   [0] total `fn` keywords        (sanity: the matcher must be in this ballpark)
#   [1] functions with `-> T`
#   [2] of those, last statement is a TAIL EXPRESSION  <- the eligible surface
#   [3] of those, declared return type is `Unit`       (where None is accidentally right)
function Measure-File([string]$text) {
  $n = $text.Length
  $total = 0; $declared = 0; $tail = 0; $tailUnit = 0
  $i = 0
  $fnRe = [regex]'(?m)^\s*fn\s+[A-Za-z_]'
  while ($i -lt $n) {
    $m = $fnRe.Match($text, $i)
    if (-not $m.Success) { break }
    $total++
    $start = $m.Index
    # find the body-opening brace, skipping comments and strings
    $depth = 0; $j = $start; $opened = -1
    while ($j -lt $n) {
      $ch = $text[$j]
      if ($ch -eq '/' -and $j + 1 -lt $n -and $text[$j+1] -eq '/') { while ($j -lt $n -and $text[$j] -ne "`n") { $j++ }; continue }
      if ($ch -eq '#' -and $j + 1 -lt $n -and $text[$j+1] -eq '"') { $j += 2; while ($j + 1 -lt $n -and -not ($text[$j] -eq '"' -and $text[$j+1] -eq '#')) { $j++ }; $j += 2; continue }
      if ($ch -eq '"') { $j++; while ($j -lt $n) { if ($text[$j] -eq '\\') { $j += 2; continue }; if ($text[$j] -eq '"') { break }; $j++ }; $j++; continue }
      if ($ch -eq '{') { $depth++; if ($opened -lt 0) { $opened = $j } }
      elseif ($ch -eq '}') { $depth--; if ($depth -eq 0 -and $opened -ge 0) { break } }
      $j++
    }
    if ($opened -lt 0 -or $j -ge $n) { $i = $m.Index + $m.Length; continue }
    $sig = $text.Substring($start, $opened - $start)
    $body = $text.Substring($opened + 1, $j - $opened - 1)
    # declared return type: `->` before the opening brace, with something after
    $retm = [regex]::Match($sig, '->\s*([A-Za-z_][A-Za-z0-9_]*(\?|\[.*?\])?)')
    if ($retm.Success) {
      $declared++
      $lines = $body -split "`n" | Where-Object { $_.Trim() -ne '' -and -not $_.Trim().StartsWith('//') }
      if ($lines.Count -gt 0) {
        $last = $lines[-1].Trim()
        $isTail = ($last -ne '' -and $last -notmatch '^(return|raise)\b' -and $last -notmatch '^[})\]}]')
        if ($isTail) {
          $tail++
          if ($retm.Groups[1].Value -eq 'Unit') { $tailUnit++ }
        }
      }
    }
    $i = $j + 1
  }
  @($total, $declared, $tail, $tailUnit)
}

foreach ($k in $targets.Keys) {
  $dir = $targets[$k]
  if (-not (Test-Path $dir)) { Write-Output "MISSING $k"; continue }
  $files = Get-ChildItem -Path $dir -Recurse -File -Include '*.mbt' -ErrorAction SilentlyContinue |
           Where-Object { $_.FullName -notmatch '\\\.mooncakes\\' }
  $t = 0; $d = 0; $tl = 0; $tu = 0
  foreach ($f in $files) {
    try { $r = Measure-File ([System.IO.File]::ReadAllText($f.FullName)) } catch { continue }
    $t += $r[0]; $d += $r[1]; $tl += $r[2]; $tu += $r[3]
  }
  Write-Output ("{0,-16} files={1,-5} fn={2,-6} with->T={3,-6} TAIL={4,-6} (of which Unit: {5})" -f $k, $files.Count, $t, $d, $tl, $tu)
}