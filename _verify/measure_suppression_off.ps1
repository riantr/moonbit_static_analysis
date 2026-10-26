$ErrorActionPreference = 'Continue'
# Measure what the CURRENT region suppression hides.
#
# WHY THIS IS A STAGE AND NOT A NUMBER WRITTEN DOWN. The README publishes
# "the tool produces N UnusedLocal and M UnusedParam findings that it does not
# produce with the suppression on". That number is a claim about a MECHANISM, and
# 0501 changed the mechanism (per-function -> per-binding) and 0502 changed the
# REGION SET (a `match`'s arms are read now, so a `match` is no longer a region).
# The 836 / 1,906 pair was measured against the OLD mechanism and was stale the
# moment 0501 landed; nothing noticed, because nothing re-measured it.
#
# => 判据: A PUBLISHED NUMBER THAT IS NOT RE-MEASURED IS A NUMBER THAT WILL BE
# WRONG. The corpus numbers are re-measured on every release gate for the same
# reason. This is the same discipline, applied to the one number that describes
# the analyzer's own conservatism.
#
# HOW THE SUPPRESSION IS SWITCHED OFF. The suppression is driven from ONE place:
# `Walker::holes_in`. The unused-PARAMETER check is gated on
# `holes.length() == 0` and the unused-LOCAL check is gated on
# `hole_can_reach(e, holes)`, so making `holes_in` return an empty array
# disables the WHOLE region suppression at once -- which is what "the
# suppression switched off" has to mean for the number to be about the
# mechanism and not about one of its two consumers.
#
# THE RESTORE IS THE POINT. The patch is written, the analyzer is rebuilt, the
# eight trees are scanned, and the source is restored -- in a `finally`, and the
# restore is PROVEN by SHA256. A killed run between the write and the restore
# leaves the patch applied, so the stage also REFUSES TO START if it finds the
# source already patched: a stage that cannot tell "patched by me" from
# "patched by a run that was killed" is how a tree ends up analysing with no
# suppression at all and nobody notices.
$ErrorActionPreference = 'Continue'
$root = 'D:\src\DeepseekHarness\Projects\xiuyueren\StaticAnalysis\moonbit_static_analysis'
$moon = 'C:\Users\31379\.moon\bin\moon.exe'
$moonrun = 'C:\Users\31379\.moon\bin\moonrun.exe'
$repos = Join-Path $root '.repos'
$target = Join-Path $root 'src\walk\walk.mbt'
$wasm = Join-Path $root '_build\wasm\debug\build\moonbit_static_analysis.wasm'
$normalWasm = Join-Path $env:TEMP ('_wasm_supp_off_normal_' + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.wasm')

# THE PATCH TARGET IS THE CALL, NOT THE RULE. 0506 moved the line-range rule
# out of `holes_in` and into `span_in_extent`, which is now SHARED by two
# mechanisms: the suppression's `holes_in` and the notice classification's
# `hiding_spans`. Patching the rule itself would switch off BOTH, and this
# stage is about the suppression alone -- so the patch replaces `holes_in`'s
# own test, the one call whose second argument is the function extent.
# (The first version of this anchor was the rule's own text, `if t.start.line
# >= sp.start.line && ...`, and 0506 made it vanish: the stage then failed
# with "the patch anchor is not unique", which was true and also misleading --
# the anchor was not there AT ALL.)
$anchor = 'if span_in_extent(t, sp) {'
$patched = 'if false {'

# THE PINS live in release.ps1's pin table -- ONE place, the same place the
# corpus numbers live. This script reads them from there rather than keeping a
# second copy, because a number written down twice is a number that will
# disagree with itself.
$relTxt = [System.IO.File]::ReadAllText((Join-Path $root '_verify\release.ps1'), [System.Text.Encoding]::UTF8)
$loM = [regex]::Match($relTxt, "\`$SUPPOFF_LOCAL\s*=\s*'(\d+)'")
$paM = [regex]::Match($relTxt, "\`$SUPPOFF_PARAM\s*=\s*'(\d+)'")
if (-not $loM.Success -or -not $paM.Success) {
  Write-Output 'FAIL: release.ps1 no longer carries the suppression-off pins.'
  exit 1
}
$wantLocal = [int]$loM.Groups[1].Value
$wantParam = [int]$paM.Groups[1].Value
Write-Output ('  pinned: UnusedLocal ' + $wantLocal + ', UnusedParam ' + $wantParam)

$trees = [ordered]@{
  'moui'            = (Join-Path $repos 'wzzc-dev\moui\0.1.12')
  'moonbit_labeler' = (Join-Path $repos 'riantr\moonbit_labeler\0.2.13')
  'moonbit_image'   = (Join-Path $repos 'riantr\moonbit_image\0.3.7')
  'async'           = (Join-Path $repos 'moonbitlang\async\0.22.4')
  'proton'          = (Join-Path $repos 'moonbit-community\proton\0.3.4')
  'proton_contract' = (Join-Path $repos 'moonbit-community\proton_contract\0.3.4')
  'moonbit_core'    = (Join-Path $repos 'moonbitlang\core\0.1.20260920+7d59c7ec9')
  'self'            = $root
}

$origBytes = [System.IO.File]::ReadAllBytes($target)
$origSha = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
$origText = [System.Text.Encoding]::UTF8.GetString($origBytes)
$anchorCount = ([regex]::Matches($origText, [regex]::Escape($anchor))).Count
if ($anchorCount -ne 1) {
  # THE COUNT IS REPORTED, not just "not unique". A count of 0 means the rule
  # MOVED again; a count above 1 means the source grew a second copy of the
  # same test. Different failures, different fixes, so the message says which.
  Write-Output ('FAIL: the patch anchor occurs ' + $anchorCount + ' times in walk.mbt (it must be exactly 1) -- the source is not what this stage expects.')
  exit 1
}
# AND THE ANCHOR MUST BE INSIDE `holes_in`. `span_in_extent` is shared with
# `hiding_spans`, so an anchor naming the RULE would switch off the notice
# classification as well. This one names `holes_in`'s call, and this guard
# proves the patch lands there and nowhere else.
$holesAt = $origText.IndexOf('fn Walker::holes_in(self : Walker, sp : @core.Span) -> Array[@core.Span] {')
$nextFnAt = $origText.IndexOf("`nfn ", $holesAt + 1)
$anchorAt = $origText.IndexOf($anchor)
if ($holesAt -lt 0 -or $anchorAt -lt $holesAt -or $anchorAt -gt $nextFnAt) {
  Write-Output 'FAIL: the patch anchor is not inside Walker::holes_in -- the patch would not switch off the suppression.'
  exit 1
}
if ($origText.Contains($patched)) {
  Write-Output 'FAIL: walk.mbt is ALREADY PATCHED. A previous run of this stage was interrupted between the write and the restore.'
  Write-Output '      Restore walk.mbt from git (or reverse the patch by hand) before running the gate again.'
  exit 1
}

if (-not (Test-Path -LiteralPath $wasm)) { Write-Output 'FAIL: the analyzer has not been built.'; exit 1 }
Copy-Item -LiteralPath $wasm -Destination $normalWasm -Force

$lines = New-Object System.Collections.Generic.List[string]
$gotLocal = 0
$gotParam = 0
try {
  $newText = $origText.Replace($anchor, $patched)
  [System.IO.File]::WriteAllText($target, $newText, (New-Object System.Text.UTF8Encoding($false)))

  Push-Location $root
  try {
    # The build writes a WARNING to stderr (the patched file leaves `t` unused),
    # and under `$ErrorActionPreference = 'Stop'` a native command's stderr is a
    # TERMINATING error -- the build would be reported as failed when it
    # succeeded. So the native call runs with 'Continue' and the EXIT CODE
    # decides.
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $b = & $moon build --target wasm 2>&1 | Out-String
    $code = $LASTEXITCODE
    $ErrorActionPreference = $prev
  } finally { Pop-Location }
  if ($code -ne 0) { Write-Output ('FAIL: the build with the suppression off failed:' + $b); exit 1 }

  foreach ($k in $trees.Keys) {
    $tree = $trees[$k]
    $dir = Join-Path $env:TEMP ('supp_off_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $o = Join-Path $dir 'o.txt'; $e = Join-Path $dir 'o.err'
    Start-Process -FilePath $moonrun -ArgumentList @($wasm, $tree, '--extern-iface-dir', $repos, '--no-auto-fetch-deps', '--findings-shown-per-file', '1000000') -RedirectStandardOutput $o -RedirectStandardError $e -NoNewWindow -Wait | Out-Null
    $all = ([System.IO.File]::ReadAllText($o, [System.Text.Encoding]::UTF8)) -split "`r?`n"
    $ul = @($all | Where-Object { $_ -match "local variable '.*' assigned but may not be used" }).Count
    $up = @($all | Where-Object { $_ -match "parameter '.*' may not be used" }).Count
    $gotLocal += $ul
    $gotParam += $up
    $lines.Add(("{0,-18} UnusedLocal={1,-5} UnusedParam={2}" -f $k, $ul, $up))
  }
}
finally {
  [System.IO.File]::WriteAllBytes($target, $origBytes)
  $nowSha = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
  if ($nowSha -ne $origSha) {
    Write-Output ('FAIL: the restore did not reproduce the original bytes: ' + $nowSha + ' != ' + $origSha)
    exit 1
  }
  Write-Output ('  restored walk.mbt, SHA256 ' + $nowSha.Substring(0, 12) + ' == the original')
  if (Test-Path -LiteralPath $normalWasm) {
    Copy-Item -LiteralPath $normalWasm -Destination $wasm -Force
    Write-Output '  restored the unpatched analyzer'
  }
}

foreach ($l in $lines) { Write-Output ('  ' + $l) }
Write-Output ('  TOTAL  UnusedLocal=' + $gotLocal + '  UnusedParam=' + $gotParam)
if ($gotLocal -ne $wantLocal -or $gotParam -ne $wantParam) {
  Write-Output ('  FAIL: the measurement is UnusedLocal ' + $gotLocal + ' / UnusedParam ' + $gotParam +
                ', and the pin is ' + $wantLocal + ' / ' + $wantParam + '.')
  Write-Output '        Either the mechanism changed and the README and the pin are stale, or the measurement is wrong.'
  exit 1
}
Write-Output '  the measurement matches the pin'
exit 0
