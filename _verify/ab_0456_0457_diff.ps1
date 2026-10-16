# Classify the 0456+0457 reach A/B.
#
# The question is ONE-SIDED on purpose: coverage may grow freely, but a single
# file read less is a regression and must be named out loud. So this reports
# the count of read-less files first and refuses to print "no loss" unless
# that count is exactly zero.
#
# Reach is ordered: NOLINE (0) < line number (n) < EOF (infinity). A file
# moving along that order is "read further"; moving backwards is READ LESS.
# The ordering matters because NOLINE is the weakest state there is -- a file
# that stops printing a line at all has been read strictly less than one that
# still prints PARTIAL at the same line.

$ErrorActionPreference = 'Stop'
$ver = Split-Path -Parent $MyInvocation.MyCommand.Path

function Load-Reach {
  param([string]$Name)
  $m = @{}
  foreach ($ln in [IO.File]::ReadAllLines((Join-Path $ver $Name))) {
    if (-not $ln) { continue }
    $f = $ln -split "`t"
    $corpus = $f[0]; $reach = $f[1]; $kind = $f[2]
    $path = ($f[3..($f.Count-1)]) -join "`t"
    $m["$corpus|$path"] = @{ reach = $reach; kind = $kind }
  }
  return $m
}

function Rank {
  param([string]$Reach)
  if ($Reach -eq 'NOLINE') { return 0 }
  if ($Reach -eq 'EOF')   { return [int]::MaxValue }
  return [int]$Reach
}

$head  = Load-Reach '_ab2_head.txt'
$fixed = Load-Reach '_ab2_fixed.txt'

Write-Host 'coverage A/B -- 0456+0457'
Write-Host ('  files in HEAD map  : ' + $head.Count)
Write-Host ('  files in fixed map : ' + $fixed.Count)
if ($head.Count -ne $fixed.Count) {
  Write-Host ''
  Write-Host 'SETS DIFFER IN SIZE -- the two maps are not the same corpus.'
  Write-Host 'Only-in-HEAD and only-in-fixed are listed; neither can be called'
  Write-Host 'read-less or read-further from reach alone, so this A/B is VOID.'
  foreach ($k in ($head.Keys | Where-Object { -not $fixed.ContainsKey($_) } | Sort-Object)) { Write-Host ('  only-HEAD  ' + $k) }
  foreach ($k in ($fixed.Keys | Where-Object { -not $head.ContainsKey($_) } | Sort-Object)) { Write-Host ('  only-fixed ' + $k) }
  exit 2
}

$readLess = @(); $readMore = @(); $same = 0
foreach ($k in ($head.Keys | Sort-Object)) {
  $a = Rank $head[$k].reach
  $b = Rank $fixed[$k].reach
  if ($b -lt $a)      { $readLess += ("{0}`t{1} -> {2}`t{3}" -f $k, $head[$k].reach, $fixed[$k].reach, $fixed[$k].kind) }
  elseif ($b -gt $a)  { $readMore += ("{0}`t{1} -> {2}`t{3}" -f $k, $head[$k].reach, $fixed[$k].reach, $fixed[$k].kind) }
  else                { $same++ }
}

Write-Host ''
Write-Host ('  unchanged     : ' + $same)
Write-Host ('  read further  : ' + $readMore.Count)
Write-Host ('  READ LESS     : ' + $readLess.Count)
Write-Host ''

if ($readMore.Count -gt 0) {
  Write-Host 'read further:'
  foreach ($r in $readMore) { Write-Host ('  ' + $r) }
  Write-Host ''
}

if ($readLess.Count -gt 0) {
  Write-Host 'READ LESS -- a regression, named individually:'
  foreach ($r in $readLess) { Write-Host ('  ' + $r) }
  Write-Host ''
  Write-Host 'VERDICT: coverage loss. Do not pin this corpus state.'
  exit 1
}

Write-Host 'VERDICT: no file in any of the six corpora was read less.'
Write-Host '         The finding-count movement is a re-classification, not a loss.'
exit 0
