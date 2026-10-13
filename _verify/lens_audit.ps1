# Direction 2: is the BEHAVIOR LENS observable at all?
#
# The question this answers, and the one a README cannot: `src/interp` is a whole
# module -- an abstract interpreter with a lattice, a call cache and its own finding
# emitter. Either it contributes findings a user can see, or it is dead weight whose
# presence in the pipeline is a claim rather than a fact.
#
# PHASE 1 counts. Every rendered finding carries a lens tag (`report.mbt:50` prints
# `[structural]`, `[behavior]`, or a `+`-joined set), so the share of the corpus
# report that the behavior lens is responsible for can be read straight out of a
# scan. Cheap, and it bounds what phase 2 can possibly find.
#
# PHASE 2 is the differential, and it is the one that settles it. `analyze_module`
# is made to return nothing, the analyzer is rebuilt over the SAME corpus tree, and
# every report is diffed. A lens that contributes nothing produces byte-identical
# output on every file, which is the only honest way to say "unobservable" -- as
# opposed to "I looked at the code and could not see how it is reached".
#
# The tree is asserted unchanged before and after, because a corpus that swapped
# underneath the comparison is how a count once appeared to move for no reason.
#
# `analyzed_sigs` is NOT neutralised. It is a second consumer of the same module
# and it feeds the rendered signatures, so the phase-2 result is about
# `analyze_module` specifically. Claiming the whole of `interp` is dead from a
# mutation of one function would be the overreach this project keeps correcting.
#
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File _verify\lens_audit.ps1
$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root
$repos = Join-Path $root '.repos'
$moon = 'C:\Users\31379\.moon\bin\moon.exe'
$moonrun = 'C:\Users\31379\.moon\bin\moonrun.exe'

$targets = [ordered]@{
  'moui'            = 'wzzc-dev\moui\0.1.12'
  'moonbit_labeler' = 'riantr\moonbit_labeler\0.2.13'
  'moonbit_image'   = 'riantr\moonbit_image\0.3.7'
  'async'           = 'moonbitlang\async\0.22.4'
  'proton'          = 'moonbit-community\proton\0.3.4'
  'proton_contract' = 'moonbit-community\proton_contract\0.3.4'
}

$baseDir = Join-Path $env:TEMP ('lens_base_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$muteDir = Join-Path $env:TEMP ('lens_nobehavior_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
foreach ($d in @($baseDir, $muteDir)) { New-Item -ItemType Directory -Force -Path $d | Out-Null }
Write-Output ("dumps: " + $baseDir + "  |  " + $muteDir)

# ---------------------------------------------------------------------------
# 0. THE TREE MUST BE THE TREE
# ---------------------------------------------------------------------------
Write-Output '=== corpus file counts ==='
$counts = @{}
$bad = 0
foreach ($k in $targets.Keys) {
  $p = Join-Path $repos $targets[$k]
  $n = @(Get-ChildItem -Path $p -Recurse -File -Filter '*.mbt' -EA SilentlyContinue |
         Where-Object { $_.FullName -notmatch '\\\.mooncakes\\' }).Count
  $counts[$k] = $n
  if ($n -eq 0) { Write-Output ("  {0,-16} NO CORPUS -- not a zero" -f $k); $bad++ }
  else { Write-Output ("  {0,-16} {1} .mbt files" -f $k, $n) }
}
if ($bad -gt 0) { Write-Output 'ABORT: a corpus is absent.'; exit 1 }

function Invoke-Scans {
  param([string]$DestDir)
  foreach ($k in $targets.Keys) {
    $p = Join-Path $repos $targets[$k]
    $out = Join-Path $DestDir "$k.txt"
    $err = Join-Path $DestDir "$k.err"
    Start-Process -FilePath $moonrun `
      -ArgumentList @($script:wasm, $p, '--extern-iface-dir', $repos, '--no-auto-fetch-deps') `
      -RedirectStandardOutput $out -RedirectStandardError $err -NoNewWindow -Wait | Out-Null
    if (-not (Test-Path $out) -or (Get-Item $out).Length -eq 0) {
      Write-Output ("  ABORT: empty scan output for " + $k); $script:bad++
    }
  }
}

$bad = 0

# ---------------------------------------------------------------------------
# 1. BASELINE BUILD + SCANS
# ---------------------------------------------------------------------------
Write-Output ''
Write-Output 'Building the analyzer as committed...'
$bo = Join-Path $env:TEMP 'lens_build.out'; $be = Join-Path $env:TEMP 'lens_build.err'
Start-Process -FilePath $moon -ArgumentList @('build','--target','wasm') `
  -RedirectStandardOutput $bo -RedirectStandardError $be -NoNewWindow -Wait | Out-Null
$wasm = Join-Path $root '_build\wasm\debug\build\moonbit_static_analysis.wasm'
if (-not (Test-Path $wasm)) { Write-Output 'ABORT: no wasm artifact.'; exit 1 }
Write-Output ("  artifact {0} bytes" -f (Get-Item $wasm).Length)

Write-Output 'Scanning six corpora with the behavior lens LIVE...'
Invoke-Scans -DestDir $baseDir
if ($bad -gt 0) { Write-Output 'ABORT: a scan produced no output.'; exit 1 }

# ---------------------------------------------------------------------------
# 2. PHASE 1 -- how many findings does the behavior lens carry?
# ---------------------------------------------------------------------------
# The lens tag is the LAST bracketed group on a rendered finding line:
#   12:5 - error: undefined name 'x' (UndefinedName) [structural+type]
Write-Output ''
Write-Output '=== phase 1: lens share of the printed corpus report ==='
Write-Output '  (a rendered finding carries its lenses last, e.g. [structural+behavior])'
$grandTotal = 0; $grandBehavior = 0
foreach ($k in $targets.Keys) {
  $txt = [System.IO.File]::ReadAllText((Join-Path $baseDir "$k.txt"))
  $lines = @($txt -split "`r?`n" | Where-Object { $_ -match '^\d+:\d+ - (error|warning|hint): ' })
  $withB = @($lines | Where-Object {
    $tag = ([regex]::Match($_, '\[([^\]]*)\]\s*$')).Groups[1].Value
    ($tag -split '\+') -contains 'behavior'
  })
  $grandTotal += $lines.Count
  $grandBehavior += $withB.Count
  $sum = ([regex]::Match($txt, '(?m)^SUMMARY.*$')).Value
  Write-Output ("  {0,-16} printed={1,-6} behavior-tagged={2}" -f $k, $lines.Count, $withB.Count)
  if ($k -eq 'proton' -or $k -eq 'async') { Write-Output ("      " + $sum) }
}
Write-Output ("  {0,-16} printed={1,-6} behavior-tagged={2}" -f 'ALL SIX', $grandTotal, $grandBehavior)

# ---------------------------------------------------------------------------
# 3. PHASE 2 -- the differential
# ---------------------------------------------------------------------------
# `analyze_module` is the behavior lens's findings path. Making it return nothing is
# the strongest possible version of "does anything downstream notice": if the report
# is byte-identical over every corpus, then nothing downstream noticed.
$interpPath = Join-Path $root 'src\interp\interp.mbt'
$sig = ([regex]::Match([System.IO.File]::ReadAllText($interpPath),
                        '(?s)pub fn analyze_module\(.*?\n\}')).Value
if ($sig.Length -eq 0) { Write-Output 'ABORT: could not locate analyze_module to neutralise.'; exit 1 }
Write-Output ''
Write-Output ("Neutralising analyze_module ({0} chars of body)..." -f $sig.Length)

$bytes0 = [System.IO.File]::ReadAllBytes($interpPath)
$sha0 = (Get-FileHash -LiteralPath $interpPath -Algorithm SHA256).Hash
$text0 = [System.Text.Encoding]::UTF8.GetString($bytes0)
Write-Output '  (the function is reported below; its body is emptied in place)'

# Replace the whole function with one that returns nothing. The parameter list is
# lifted from the parsed source rather than retyped -- it is `@ast.Module` and
# `@types.TypeResult`, not what a reader would guess, and a wrong type here would
# fail to compile and look like "the lens cannot be neutralised" rather than like a
# typo in the probe.
$cut = $sig.IndexOf('-> Array[@report.Report] {')
if ($cut -lt 0) { Write-Output 'ABORT: could not find analyze_module return type in the parsed body.'; exit 1 }
$header = $sig.Substring(0, $cut)
$stub = $header + "-> Array[@report.Report] {" + "`n  []" + "`n}"
$mutated = $text0.Replace($sig, $stub)
if ($mutated -eq $text0) { Write-Output 'ABORT: the replacement did not change the file.'; exit 1 }
[System.IO.File]::WriteAllText($interpPath, $mutated, (New-Object System.Text.UTF8Encoding($false)))
Write-Output '  the neutralised function is:'
foreach ($l in ($stub -split "`n")) { Write-Output ('    | ' + $l) }

Write-Output 'Rebuilding with the behavior lens silenced...'
Start-Process -FilePath $moon -ArgumentList @('build','--target','wasm') `
  -RedirectStandardOutput $bo -RedirectStandardError $be -NoNewWindow -Wait | Out-Null
$buildErr = [System.IO.File]::ReadAllText($be)
$wasm2 = Join-Path $root '_build\wasm\debug\build\moonbit_static_analysis.wasm'
$built = (Test-Path $wasm2)
Write-Output ("  build produced an artifact: " + $built)

Write-Output 'Scanning the same six corpora...'
Invoke-Scans -DestDir $muteDir

# ---- restore, and prove it -------------------------------------------------
[System.IO.File]::WriteAllBytes($interpPath, $bytes0)
$sha1 = (Get-FileHash -LiteralPath $interpPath -Algorithm SHA256).Hash
if ($sha0 -ne $sha1) {
  Write-Output 'ABORT: restore mismatch -- the source tree is NOT back where it was.'
  exit 1
}
Write-Output '  restore verified byte-identical by SHA256'

# ---------------------------------------------------------------------------
# 4. THE ANSWER
# ---------------------------------------------------------------------------
Write-Output ''
Write-Output '=== phase 2: per-corpus diff, behavior lens live vs silenced ==='
$differs = 0
foreach ($k in $targets.Keys) {
  $bt = [System.IO.File]::ReadAllText((Join-Path $baseDir "$k.txt"))
  $nt = [System.IO.File]::ReadAllText((Join-Path $muteDir "$k.txt"))
  if ($bt -ceq $nt) {
    Write-Output ("  [IDENTICAL] {0,-16} {1} files" -f $k, $counts[$k])
  } else {
    $differs++
    $bs = ([regex]::Match($bt, '(?m)^SUMMARY.*$')).Value
    $ns = ([regex]::Match($nt, '(?m)^SUMMARY.*$')).Value
    $bl = @($bt -split "`r?`n"); $nl2 = @($nt -split "`r?`n")
    $bOnly = @(Compare-Object $bl $nl2 | Where-Object { $_.SideIndicator -eq '<=' }).Count
    $nOnly = @(Compare-Object $bl $nl2 | Where-Object { $_.SideIndicator -eq '=>' }).Count
    Write-Output ("  [CHANGED  ] {0,-16} {1} files   lines only-live={2} only-silenced={3}" -f $k, $counts[$k], $bOnly, $nOnly)
    Write-Output ("      live    : " + $bs)
    Write-Output ("      silenced: " + $ns)
  }
}
Write-Output ''
if ($differs -eq 0) {
  Write-Output 'VERDICT: the behavior lens is UNOBSERVABLE on all six corpora.'
  Write-Output '          Every report is byte-identical with analyze_module silenced.'
} else {
  Write-Output ("VERDICT: the behavior lens IS observable on {0} of 6 corpora." -f $differs)
}
Write-Output ("phase 1 measured {0} behavior-tagged findings of {1} printed, corpus-wide." -f $grandBehavior, $grandTotal)
exit 0
