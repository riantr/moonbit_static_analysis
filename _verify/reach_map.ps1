# Per-file reach map for one corpus.
#
# WHY THIS FILE EXISTS
# --------------------
# The obvious metric -- "did this file print a FOUND line" -- covers only
# 183 of async's 419 files. A file that parsed cleanly prints CLEAN, and a
# file that was read past its first parse error prints PARTIAL. Keying the
# A/B diff on FOUND alone therefore drops 56% of the corpus silently, and
# every clean file would read as "absent" rather than "unchanged".
#
# So the metric used for coverage-loss A/B is:
#
#   CLEAN                      -> reach = EOF  (read to the end)
#   FOUND  /  other complete   -> reach = EOF
#   PARTIAL ... read up to N   -> reach = N
#
# This script PROVES the map is total: it enumerates the corpus on disk and
# reports every file the scan printed no line for. An incomplete map cannot
# support a "no file was read less" claim, so the gap is reported, not hidden.

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$moonrun = 'C:\Users\31379\.moon\bin\moonrun.exe'
$repos = Join-Path $root '.repos'

$param_target = $args[0]
if (-not $param_target) { throw 'usage: reach_map.ps1 <repo-relative-corpus-dir>' }

$wasm = Join-Path $root '_build\wasm\debug\build\moonbit_static_analysis.wasm'
if (-not (Test-Path $wasm)) { throw "no wasm: $wasm" }

$dir = Join-Path $env:TEMP ('reach_' + [guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Force -Path $dir | Out-Null
$out = Join-Path $dir 'o.txt'; $err = Join-Path $dir 'o.err'

# The scanner resolves the target itself and wants the path it will see on
# disk. Handed a bare repo-relative path it prints
#   ERROR  cannot locate source for target: <path>
# and still exits 0, which would read downstream as "every file unmapped".
# So the target is checked here rather than inferred from the exit code.
$target = Join-Path '.repos' $param_target
if (-not (Test-Path (Join-Path $root $target))) { throw "no corpus at $target" }

Start-Process -FilePath $moonrun `
  -ArgumentList @($wasm, $target, '--extern-iface-dir', $repos) `
  -RedirectStandardOutput $out -RedirectStandardError $err -NoNewWindow -Wait | Out-Null

$text = [IO.File]::ReadAllText($out)
if ($text -match '(?m)^ERROR\b') { throw "scan failed: " + (($text -split "`r?`n" | Where-Object { $_ -match '^ERROR' }) -join ' | ') }
$lines = $text -split "`r?`n"

# reach : path -> integer reach line (EOF = [int]::MaxValue)
$reach = @{}
$kind  = @{}
foreach ($ln in $lines) {
  $f = $ln -split "`t"
  if ($f.Count -lt 3) { continue }
  $tag = $f[0]
  if ($tag -ne 'FOUND' -and $tag -ne 'CLEAN' -and $tag -ne 'PARTIAL') { continue }
  $path = $f[$f.Count - 1]
  # The scan prints the target dir with the separator it was given and the
  # rest with '/', e.g. `.repos\a\b/src/x.mbt`. Both sides of the comparison
  # are normalised to '/' below; without that, ZERO keys ever match and the
  # script reports every file unmapped.
  $path = $path.Replace('\','/')
  if ($tag -eq 'PARTIAL') {
    # PARTIAL <kind> defects=N notices=M read up to line N, K after it not shown <path>
    $reach[$path] = -1
    $kind[$path]  = 'PARTIAL'
    for ($i = 0; $i -lt $f.Count; $i++) {
      if ($f[$i] -match 'read up to line (\d+)') { $reach[$path] = [int]$Matches[1] }
    }
  } else {
    $reach[$path] = [int]::MaxValue
    $kind[$path]  = $tag
  }
}

# The corpus on disk, so the map can be shown to be total. Only the three
# kinds the scanner actually reads: .mbt, .mbti, and .mbt.md. A plain .md
# (README.md, AGENTS.md) is not scanned, and counting it would inflate the
# denominator by 14 on async and invent an unmapped-file finding.
$abs = Join-Path $repos $param_target
$onDisk = Get-ChildItem -Path $abs -Recurse -File |
  Where-Object {
    $_.Extension -in @('.mbt', '.mbti') -or $_.Name.EndsWith('.mbt.md')
  } |
  ForEach-Object { $_.FullName.Substring($root.Length + 1).Replace('\','/') } | Sort-Object -Unique

$scanned = ([regex]::Match($text, '(?m)^SCANNED\s+(\d+)\s').Groups[1].Value)
Write-Output ("SCANNED " + $scanned + "  onDisk " + $onDisk.Count + "  mapped " + $reach.Count)

$missing = @($onDisk | Where-Object { -not $reach.ContainsKey($_) })
Write-Output ("UNMAPPED " + $missing.Count)
foreach ($m in ($missing | Sort-Object | Select-Object -First 25)) { Write-Output ("  " + $m) }

# Every scanned file gets EXACTLY one reach state, so the A/B diff can
# classify all 419 files instead of silently skipping 61 of them:
#
#   EOF      read to the end            (CLEAN / FOUND)
#   <int>    read up to that line       (PARTIAL)
#   NOLINE   no per-file line printed at all
#
# NOLINE is not "unchanged": it is what a file whose FIRST construct fails to
# parse looks like. Those files are counted in NOTPARSE yet emit nothing, and
# they are the most volatile files in a parser change -- a fix that moves one
# of them turns NOLINE into a line. Leaving them out would drop exactly the
# files most likely to move out of the comparison.
$rows = @()
foreach ($p in $onDisk) {
  if ($reach.ContainsKey($p)) {
    $r = $reach[$p]
    $rs = if ($r -eq [int]::MaxValue) { 'EOF' } else { [string]$r }
    $rows += ($rs + "`t" + $kind[$p] + "`t" + $p)
  } else {
    $rows += ("NOLINE`t-`t" + $p)
  }
}
foreach ($r in ($rows | Sort-Object)) { Write-Output ("REACH`t" + $r) }
