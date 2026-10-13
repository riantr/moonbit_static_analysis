# Published-vs-local byte comparison.
#
# `moonx riantr/moonbit_static_analysis@0.4.29 <coordinate>` runs the PUBLISHED
# wasm. This runs the LOCAL wasm over the same corpus sources and diffs the two
# outputs. CI proving the tag builds is not the same claim: this says the artifact
# people actually install behaves like the one in this working tree.
#
# THE PATHS DIFFER BY CONSTRUCTION. moonx materialises the corpus under its own
# cache and prints that path; the local run prints the path under `.repos`. The
# corpus SOURCES are the same package versions, so every absolute path is
# normalised to a leaf-relative form before comparing. Anything left over after
# that is a real behavioural difference.
#
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File _verify/diff0429_published.ps1
$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $PSScriptRoot
$wasm = "$root\_build\wasm\debug\build\moonbit_static_analysis.wasm"
$repos = "$root\.repos"
$tag = '0.4.29'
$outdir = Join-Path $env:TEMP "pubdiff_$tag"
New-Item -ItemType Directory -Force -Path $outdir | Out-Null

$targets = [ordered]@{
  'moui'    = @{ coord = 'wzzc-dev/moui@0.1.12';              path = "$repos\wzzc-dev\moui\0.1.12" }
  'async'   = @{ coord = 'moonbitlang/async@0.22.4';          path = "$repos\moonbitlang\async\0.22.4" }
  'proton'  = @{ coord = 'moonbit-community/proton@0.3.4';    path = "$repos\moonbit-community\proton\0.3.4" }
}

function Normalize([string]$text, [string]$path) {
  # SEPARATORS FIRST. moonx prints `...\.repos/wzzc-dev/moui/0.1.12/moui.mbt` --
  # backslashes up to `.repos`, forward slashes after. The local run prints the
  # whole thing with a backslash after the version too. Everything matched and
  # nothing compared equal: 1,168 of 3,590 lines "differed" over the difference
  # between `\` and `/`. Flatten to `/` before any prefix rule runs, because a
  # prefix written with the other separator silently matches nothing.
  $t = $text.Replace('\', '/')
  # ONE marker for the corpus location, produced by the SAME rule on both sides.
  # An earlier version also replaced the known corpus path with `<corpus>` before
  # the `.repos/` rules, so the local side came out as `<corpus>/moui.mbt` and the
  # moonx side as `<corpusroot>/` -- 1,168 of 3,590 lines differing, all of them
  # the same rename applied on one side only.
  $t = [regex]::Replace($t, '(?i)[A-Z]:[^\s"]*?\.mooncakes/[^\s"]*', '<cache>')
  # everything from `.repos/` onward is corpus location, not content
  $t = [regex]::Replace($t, '(?i)[A-Z]:[^\s"]*?\.repos/[^\s"]*', '<corpusroot>/')
  # UNANCHORED. moonx's path is not at the start of the line -- a per-file verdict
  # is `CLEAN\t.mbt\t.repos/wzzc-dev/moui/0.1.12/moui.mbt` -- so the `^\s*` form
  # matched nothing and every path survived into the diff. 1,168 lines again.
  $t = [regex]::Replace($t, '(?i)\.repos/[^\s"]*', '<corpusroot>/')
  return $t
}

# ONLY THE ANALYZER'S OWN LINES.
#
# moonx wraps the same wasm in its own driver, so its output carries progress
# lines the local run never prints -- `Info: ... already exists at ...`, `FETCH 6
# import(s) from moon.mod`, `WALKING dirs=45 files=505 so far under ...` -- and
# its `TARGET` line names the coordinate rather than a path. Comparing whole
# streams produced 1,215 "differing" lines on moui and not one of them was a
# finding.
#
# The filter below is the analyzer's report vocabulary: per-file verdicts, the
# summary lines, the interface/privtab banners, the per-finding `L:C - ...`
# lines, and the NOTPARSE histogram. Everything moonx adds is excluded by
# construction rather than by a list of things that happen to differ today.
$ANALYZER_LINE = '^(FOUND|PARTIAL|CLEAN|NOTPARSE|SUMMARY|BYKIND|PARSED|IFACE|PRIVTAB|UNREACHABLE)\s|^\s*\d+x\s|^\d+:\d+ - '

function AnalyzerLines([string]$text) {
  $keep = @()
  foreach ($l in ($text -split "`r?`n")) { if ($l -match $ANALYZER_LINE) { $keep += $l } }
  return $keep
}

Set-Location $root
$bad = 0
foreach ($k in $targets.Keys) {
  $t = $targets[$k]
  $n = @(Get-ChildItem -Path $t.path -Recurse -File -Filter '*.mbt' -EA SilentlyContinue |
         Where-Object { $_.FullName -notmatch '\\\.mooncakes\\' }).Count
  if ($n -eq 0) { Write-Output ("{0,-8} NO CORPUS -- aborting, NOT a zero" -f $k); exit 1 }

  $local = Join-Path $outdir "$k.local.txt"
  $pub   = Join-Path $outdir "$k.pub.txt"
  # Start-Process takes an ARGUMENT ARRAY, so the paths need no quoting at all.
  # The first version of this shelled out to `cmd.exe /c "... > file 2>&1"`, whose
  # embedded quotes PowerShell mangles: cmd ran nothing, the local capture came
  # back 0 BYTES, and only the EMPTY CAPTURE guard below caught it. The moonx side
  # captured 420 KB in the same run, which is what made the asymmetry legible.
  $err = Join-Path $outdir "$k.local.err"
  # NO `--extern-iface-dir` ON EITHER SIDE. The local run originally passed the
  # shared `.repos`, and 1,170 of 3,590 analyzer lines "differed" -- including the
  # IFACE banner (`types=673 values=3199` on the moonx side) and per-file notice
  # counts. That is not a build difference: `--extern-iface-dir` feeds sibling
  # interface tables into the run, and moonx does not pass it. Two invocations
  # that are given different inputs are not a comparison of two builds, so the
  # local side is run exactly the way moonx runs it.
  $proc = Start-Process -FilePath 'C:\Users\31379\.moon\bin\moonrun.exe' `
      -ArgumentList @($wasm, $t.path, '--no-auto-fetch-deps') `
      -RedirectStandardOutput $local -RedirectStandardError $err -NoNewWindow -Wait -PassThru
  $out = & C:\Users\31379\.moon\bin\moonrun.exe $wasm $t.path --extern-iface-dir $repos --no-auto-fetch-deps
  # moonx separately, through Start-Process. `2>&1 | Out-String` merges stderr as
  # formatted PowerShell ERROR RECORDS -- `moonx` prints "Registry index updated
  # successfully" to stderr, and the merge wrapped it in a stack trace and a
  # FullyQualifiedErrorId. That produced 1,236 "differing" lines on moui of which
  # none were analyzer output. Separate streams, and stderr is not the subject.
  $pubOut = Join-Path $outdir "$k.pub.out"
  $pubErr = Join-Path $outdir "$k.pub.err"
  $p2 = Start-Process -FilePath 'C:\Users\31379\.moon\bin\moonx.exe' `
        -ArgumentList @("riantr/moonbit_static_analysis@$tag", $t.coord) `
        -RedirectStandardOutput $pubOut -RedirectStandardError $pubErr -NoNewWindow -Wait -PassThru
  $out = [System.IO.File]::ReadAllText($pubOut)

  $lb = (Get-Item $local).Length; $pb = (Get-Item $pubOut).Length
  if ($lb -eq 0 -or $pb -eq 0) {
    Write-Output ("{0,-8} EMPTY CAPTURE (local={1}B pub={2}B) -- aborting, NOT a match" -f $k, $lb, $pb); $bad++; continue
  }
  $ln = Normalize ([System.IO.File]::ReadAllText($local)) $t.path
  $pn = Normalize $out $t.path
  $a = AnalyzerLines $ln
  $b = AnalyzerLines $pn
  if ($a.Count -eq 0 -or $b.Count -eq 0) {
    Write-Output ("{0,-8} NO ANALYZER LINES (local={1} pub={2}) -- the filter matched nothing, which is NOT a match" -f $k, $a.Count, $b.Count)
    $bad++; continue
  }
  if (($a -join "`n") -ceq ($b -join "`n")) {
    $ls = ([regex]::Match($ln, '(?m)^SUMMARY.*$')).Value
    Write-Output ("{0,-8} IDENTICAL  files={1}  {2} analyzer lines  {3}" -f $k, $n, $a.Count, $ls)
  } else {
    $d = Compare-Object $a $b -SyncWindow 5000
    Write-Output ("{0,-8} DIFFERS    {1} local vs {2} pub analyzer lines, {3} differing" -f $k, $a.Count, $b.Count, @($d).Count)
    @($d) | Select-Object -First 10 | ForEach-Object { Write-Output ('      ' + $_.SideIndicator + ' ' + $_.InputObject) }
    $bad++
  }
}
Write-Output ''
if ($bad -gt 0) { Write-Output "ABORT: $bad corpus/corpora differ."; exit 1 }
Write-Output "Published $tag matches the local build byte-for-byte on all three corpora."
exit 0