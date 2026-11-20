param(
  # The tree to re-gate. Defaults to the repository this script lives in.
  [string]$Root = '',
  # Where the newest toolchain is kept. It is a CACHE, and it is big: the
  # toolchain is ~94 MB and the link that serves it is unreliable.
  [string]$Cache = (Join-Path $env:TEMP 'moonbit_static_analysis_newest_toolchain'),
  # Do not touch the network: use whatever the cache already holds.
  [switch]$Offline
)
$ErrorActionPreference = 'Continue'

# THE RE-GATE: THE SAME TREE, THE NEWEST TOOLCHAIN.
#
# WHY THIS EXISTS. The CI workflows install moon with
#
#     curl -fsSL https://cli.moonbitlang.com/install/unix.sh | bash
#
# with NO version, so the runner gets `latest`. And the installer resolves the
# core SEPARATELY:
#
#     core_uri="$CLI_MOONBIT/cores/core-$version.tar.gz"
#
# with version=latest, i.e. `cores/core-latest.tar.gz` -- the NEWEST core, not
# the one the toolchain shipped with. So the runner's core moves on its own,
# independently of the toolchain's version, and a tree that compiles on the
# machine that cuts the release can still fail on the runner.
#
# THAT IS NOT A THEORY. MEASURED 2026-11-20, on the tree as it stood: the
# newest core (0.10.22+124d61d05) reports `unused_package` for
# `moonbitlang/core/async` in two packages, and `moon check --deny-warn` -- the
# first thing CI runs -- FAILS. The release would have shipped a tree that
# does not build.
#
# WHAT IT DOES, in order:
#
#   1. asks the registry which core is the newest, and compares the build hash
#      with the one in the cache;
#   2. downloads the newest core and the newest toolchain if they are missing
#      or stale -- with a RESUMED download, because the link drops big
#      transfers and the server does advertise `accept-ranges: bytes`;
#   3. BUNDLES the core, which is not optional: without the bundle every
#      target fails with "... bundle/async/aqueue/aqueue.mi missing";
#   4. copies the tree and runs the CI steps against the copy -- the CI steps
#      exactly, plus the two the LOCAL gate runs and CI does not;
#   5. prints a table and exits 0 or 1.
#
# THE TREE IS COPIED, not measured in place: `moon` writes into `_build/`, and
# a re-gate must not touch the working tree it is re-gating.
#
# THE DOWNLOAD IS SLOW ON A BAD LINK and the core is small, the toolchain is
# not: 2.9 MB against 94 MB. The toolchain is cached, so the second run is
# fast. A run that has to download takes minutes; a run against a warm cache
# takes about seven, most of it `moon update`.
#
# IT IS A RELEASE-PREP CHECK, not a stage of the release gate: the gate must
# stay fast, and the gate's own stage that watches the core is the one that
# says WHEN this has to be run again.
#
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File _verify\regate_newest_toolchain.ps1
#   powershell -NoProfile -ExecutionPolicy Bypass -File _verify\regate_newest_toolchain.ps1 -Offline

$root = if ($Root) { $Root } else { Split-Path -Parent $PSScriptRoot }
$curl = 'C:\Windows\system32\curl.exe'
$fail = 0

function Write-Step([string]$s) { Write-Output ('  ' + $s) }

# THE STATUS OF ONE URL. 0 means THE HOST DID NOT ANSWER, which is not the
# same thing as 404, and the two are reported differently.
function Get-UrlStatus([string]$Url) {
  $code = 0
  try {
    $req = [System.Net.HttpWebRequest]::Create($Url)
    $req.Method = 'GET'; $req.Timeout = 30000; $req.AllowAutoRedirect = $true
    $req.UserAgent = 'moonbit_static_analysis re-gate'
    $resp = $req.GetResponse(); $code = [int]$resp.StatusCode; $resp.Close()
  } catch {
    $ex = $_.Exception
    while ($null -ne $ex -and $null -eq $ex.Response -and $null -ne $ex.InnerException) { $ex = $ex.InnerException }
    if ($null -ne $ex -and $null -ne $ex.Response) { $code = [int]$ex.Response.StatusCode }
  }
  return $code
}

# THE BODY OF ONE URL.
function Get-UrlBody([string]$Url) {
  try {
    $c = New-Object System.Net.WebClient
    $c.Headers.Add('User-Agent', 'moonbit_static_analysis re-gate')
    return $c.DownloadString($Url)
  } catch { return '' }
}

# THE BUILD HASH OUT OF A VERSION. The registry publishes the core as
# `0.1.<date>+<hash>` and the core's own `moon.mod` says `0.10.<n>+<hash>`:
# the two strings differ, and the hash is what they share. So the hash is the
# join key, and the two strings are both printed.
function Get-BuildHash([string]$Version) {
  if ($Version -match '\+([0-9a-fA-F]+)$') { return $Matches[1] }
  return ''
}

# DOWNLOAD WITH A RESUME LOOP. The link drops big transfers, and the server
# advertises `accept-ranges: bytes`, so the bytes already on disk are kept and
# the rest is asked for again.
function Get-File([string]$Url, [string]$Out, [long]$Expected) {
  for ($i = 1; $i -le 40; $i++) {
    $have = 0
    if (Test-Path -LiteralPath $Out) { $have = (Get-Item -LiteralPath $Out).Length }
    if ($have -ge $Expected) { return $true }
    Write-Output ('      ' + [int]($have / 1KB) + ' KB of ' + [int]($Expected / 1KB) + ' KB')
    & $curl -sS -L -C - --http1.1 --connect-timeout 20 --max-time 180 --speed-limit 20000 --speed-time 20 -o $Out $Url 2>&1 | Out-Null
    Start-Sleep -Seconds 2
  }
  $have = 0
  if (Test-Path -LiteralPath $Out) { $have = (Get-Item -LiteralPath $Out).Length }
  return ($have -ge $Expected)
}

Write-Output '=== the newest toolchain, and the tree against it ==='
Write-Output ('  the tree: ' + $root)
Write-Output ('  the cache: ' + $Cache)

# --- 1. which core is the newest? ----------------------------------------------------
Write-Output ''
Write-Output '--- 1. the newest core, as the registry publishes it ---'
$regUrl = 'https://mooncakes.io/api/v0/modules/moonbitlang/core'
$regVer = ''
if ($Offline) {
  $regVer = ''
} else {
  $body = Get-UrlBody $regUrl
  if ($body -match '"latest_version"\s*:\s*"([^"]+)"') { $regVer = $Matches[1] }
}
$regHash = Get-BuildHash $regVer
if (-not $Offline -and $regHash -eq '') {
  Write-Output '  FAIL: the registry did not answer with a core version, so the newest core is unknown.'
  Write-Output '        A core that cannot be checked is not a core with nothing wrong.'
  exit 1
}
Write-Output ('  the registry publishes: ' + $(if ($regVer -eq '') { '(offline)' } else { $regVer }))

# --- 2. the toolchain and the core --------------------------------------------------
Write-Output ''
Write-Output '--- 2. the toolchain and the core ---'
New-Item -ItemType Directory -Path $Cache -Force | Out-Null
$moon = Join-Path $Cache 'bin\moon.exe'
$coreMod = Join-Path $Cache 'lib\core\moon.mod'

if (-not (Test-Path -LiteralPath $moon)) {
  $zip = Join-Path $Cache 'moonbit-windows-x86_64.zip'
  Write-Output '  the toolchain is not in the cache: downloading it (94 MB, and the link is slow)'
  if ($Offline) {
    Write-Output '  FAIL: offline, and there is no toolchain in the cache.'
    exit 1
  }
  if (-not (Get-File 'https://cli.moonbitlang.com/binaries/latest/moonbit-windows-x86_64.zip' $zip 94334795)) {
    Write-Output '  FAIL: the toolchain download did not finish.'
    exit 1
  }
  Write-Output '  extracting the toolchain'
  Expand-Archive -Path $zip -DestinationPath $Cache -Force
} else {
  Write-Output '  the toolchain is in the cache'
}

$coreHash = ''
if (Test-Path -LiteralPath $coreMod) {
  $t = [System.IO.File]::ReadAllText($coreMod, [Text.Encoding]::UTF8)
  if ($t -match 'version\s*=\s*"([^"]+)"') { $coreHash = Get-BuildHash $Matches[1] }
}
if ($regHash -ne '' -and $coreHash -eq $regHash) {
  Write-Output ('  the core in the cache is the newest one (' + $coreHash + ')')
} else {
  if ($Offline) {
    Write-Output '  FAIL: offline, and the cached core is not the newest one.'
    exit 1
  }
  Write-Output '  the core is not the newest one: downloading it (2.9 MB)'
  $tgz = Join-Path $Cache 'core-latest.tar.gz'
  if (-not (Get-File 'https://cli.moonbitlang.com/cores/core-latest.tar.gz' $tgz 2943845)) {
    Write-Output '  FAIL: the core download did not finish.'
    exit 1
  }
  Write-Output '  extracting the core'
  & tar -xzf $tgz -C (Join-Path $Cache 'lib')
}

$coreVer = ''
$t = [System.IO.File]::ReadAllText($coreMod, [Text.Encoding]::UTF8)
if ($t -match 'version\s*=\s*"([^"]+)"') { $coreVer = $Matches[1] }
$moonVer = (& $moon version 2>&1 | Out-String).Trim()
Write-Output ('  the toolchain: ' + $moonVer)
Write-Output ('  the core:      ' + $coreVer)

# --- 3. bundle the core -------------------------------------------------------------
Write-Output ''
Write-Output '--- 3. bundling the core (without it every target fails) ---'
$mi = @(Get-ChildItem (Join-Path $Cache 'lib\core') -Recurse -Filter *.mi -ErrorAction SilentlyContinue).Count
if ($mi -gt 0) {
  Write-Output ('  the core is bundled (' + $mi + ' artifacts)')
} else {
  $env:MOON_HOME = $Cache
  $env:PATH = (Join-Path $Cache 'bin') + ';' + $env:PATH
  & $moon -C (Join-Path $Cache 'lib\core') bundle --warn-list -a --all 2>&1 | Out-Null
  if ($LASTEXITCODE -ne 0) { Write-Output '  FAIL: the core did not bundle.'; exit 1 }
  & $moon -C (Join-Path $Cache 'lib\core') bundle --warn-list -a --target wasm-gc --quiet 2>&1 | Out-Null
  if ($LASTEXITCODE -ne 0) { Write-Output '  FAIL: the core did not bundle for wasm-gc.'; exit 1 }
  $mi = @(Get-ChildItem (Join-Path $Cache 'lib\core') -Recurse -Filter *.mi -ErrorAction SilentlyContinue).Count
  Write-Output ('  bundled: ' + $mi + ' artifacts')
  if ($mi -eq 0) { Write-Output '  FAIL: the core did not produce a single artifact.'; exit 1 }
}

# --- 4. the tree, on a copy ---------------------------------------------------------
Write-Output ''
Write-Output '--- 4. the tree, on a copy (a re-gate must not touch the tree it re-gates) ---'
$copy = Join-Path $env:TEMP ('regate_' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $copy -Force | Out-Null
Get-ChildItem -Path (Join-Path $root '*') -Force |
  Where-Object { $_.Name -ne '.git' -and $_.Name -ne '_build' } |
  ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $copy -Recurse -Force }
Write-Output ('  the copy: ' + $copy)

$env:MOON_HOME = $Cache
$env:PATH = (Join-Path $Cache 'bin') + ';' + $env:PATH

$steps = @(
  'update',
  'check --deny-warn',
  'fmt --check',
  'test --target js --deny-warn',
  'test --target wasm --deny-warn',
  'test --target wasm-gc --deny-warn',
  'build --target wasm',
  'build --release --target wasm'
)
Write-Output ''
Write-Output '--- 5. the CI steps, against the newest toolchain ---'
foreach ($spec in $steps) {
  $parts = @($spec -split ' ')
  $sw = [Diagnostics.Stopwatch]::StartNew()
  $out = & $moon -C $copy @parts 2>&1 | Out-String
  $code = $LASTEXITCODE
  $sw.Stop()
  if ($code -ne 0) {
    $fail++
    Write-Step ('FAILED  ' + $spec + '   (exit ' + $code + ', ' + [int]$sw.Elapsed.TotalSeconds + 's)')
    ($out -split "`r?`n") | Where-Object { $_.Trim() -ne '' } | Select-Object -Last 25 | ForEach-Object { Write-Output ('      | ' + $_) }
  } else {
    Write-Step ('ok      ' + $spec + '   (' + [int]$sw.Elapsed.TotalSeconds + 's)')
  }
}

Write-Output ''
if ($fail -eq 0) {
  Write-Output ('REGATE OK: the tree builds and tests on moon ' + $moonVer + ' with core ' + $coreVer + '.')
  exit 0
}
Write-Output ('REGATE FAILED: ' + $fail + ' step(s) failed on moon ' + $moonVer + ' with core ' + $coreVer + '.')
Write-Output 'A release may not be tagged against a toolchain that refuses this tree.'
exit 1
