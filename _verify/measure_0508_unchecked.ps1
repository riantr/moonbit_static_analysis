# 0508 INSTRUMENT: how the unchecked calls divide, and how much of each division
# is reachable. This is an INSTRUMENT, not a gate: it answers a question, it does
# not assert a rule, and it is NOT in release.ps1's stage list.
#
# WHAT IT ANSWERS. The type lens checks a call's arity and its argument types only
# when it has read the callee's signature. Three kinds of call never get that read:
#
#   A  a name known only by NAME   the callee is known from another package's .mbti
#   B  a method call               the receiver's method signature is not in hand
#   C  a `..` chain link           a method call wearing different syntax
#
# and this instrument splits each of them further, because the split is what says
# whether a signature would HELP. A method call can only be checked if the
# receiver's TYPE is known (so the method can be found) and the parameter list is
# in hand (so the arguments can be checked). So B splits into:
#
#   n_m_known    the receiver's type is known  -> a signature would reach it
#   n_m_unknown  the receiver's type is TUnknown -> no signature table reaches it
#   n_m_qual     the receiver is a qualifier (`@pkg.f(..)`) -> a package-level fn
#
# and A splits into a callee that is a plain function name and one that is a
# `Type::method` name.
#
# HOW IT WORKS. It patches ONE file -- src/types/infer.mbt -- with counters that
# are not in the shipped analyzer, builds the wasm, scans the eight trees, and then
# RESTORES THE FILE BYTE-IDENTICALLY (SHA256-proven) and rebuilds the wasm so the
# binary on disk matches the committed source again.
#
#   * THE ANCHORS ARE LINE-PINNED, and every one is CHECKED against its expected
#     content before anything is touched. If the source has moved, the run ABORTS
#     and restores the file rather than patching the wrong line. Re-pin the
#     anchors when src/types/infer.mbt moves.
#   * IF YOU INTERRUPT IT, THE FILE STAYS PATCHED. Re-run it (it backs up and
#     restores) or `git checkout` the one file. Nothing else in the tree is
#     touched.
#   * IT MUST NOT RUN WHILE ANOTHER BUILD OR SCAN IS USING src/ OR THE WASM.
#
# WHAT IT PROVES. The counters it adds are ADDED TO the shipped ones, never
# replacing them, so the instrument's own sum has to equal the shipped SUMMARY's
# `unchecked=` on every tree. That is the instrument's own control: a measurement
# that cannot reproduce the number it is explaining is not a measurement.
#
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File _verify\measure_0508_unchecked.ps1
$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $PSScriptRoot
$repos = Join-Path $root '.repos'
$wasm = Join-Path $root '_build\wasm\debug\build\moonbit_static_analysis.wasm'
$moon = 'C:\Users\31379\.moon\bin\moon.exe'
$moonrun = 'C:\Users\31379\.moon\bin\moonrun.exe'
$target = Join-Path $root 'src\types\infer.mbt'

if (-not (Test-Path -LiteralPath $moon)) { $moon = 'moon' }
if (-not (Test-Path -LiteralPath $moonrun)) { $moonrun = 'moonrun' }

$origBytes = [System.IO.File]::ReadAllBytes($target)
$origSha = (Get-FileHash -Path $target -Algorithm SHA256).Hash
Write-Output ('ORIGINAL SHA256 : ' + $origSha)
$lines = [System.IO.File]::ReadAllText($target) -split "`n"

$COUNTERS = @(
  'n_m_known', 'n_m_unknown', 'n_m_qual',
  'n_dd_known', 'n_dd_unknown', 'n_dd_qual',
  'n_a_value', 'n_a_method'
)

# At     = the 1-based line number of the anchor
# Must   = the exact content that must be on that line
# Mode   = 'after' | 'before' | 'replace' | 'replaceblock'
# Add    = lines to insert (after/before)
# New    = replacement lines (replace/replaceblock)
# Old    = the lines a 'replaceblock' must find, in order
$edits = @(
  @{ At = 1116; Must = '  TypeResult::{'; Mode = 'before'
     Add = @('  println("UNCHECKED-SPLIT n_m_known=\{inf.n_m_known} n_m_unknown=\{inf.n_m_unknown} n_m_qual=\{inf.n_m_qual} n_dd_known=\{inf.n_dd_known} n_dd_unknown=\{inf.n_dd_unknown} n_dd_qual=\{inf.n_dd_qual} n_a_value=\{inf.n_a_value} n_a_method=\{inf.n_a_method}")') }

  @{ At = 401; Must = '        let bt = self.ty_of(base, TUnknown)'; Mode = 'after'
     Add = @('        if bt is TUnknown {', '          self.n_dd_unknown += 1', '        } else {', '          self.n_dd_known += 1', '        }') }

  @{ At = 394; Must = '      self.n_unchecked += 1'; Mode = 'after'
     Add = @('      if base.is_qualifier() {', '        self.n_dd_qual += 1', '      }') }

  @{ At = 360; Mode = 'replaceblock'
     Old = @('      if !base.is_qualifier() {', '        ignore(self.ty_of(base, TUnknown))', '      }')
     New = @('      if base.is_qualifier() {', '        self.n_m_qual += 1', '      } else {', '        let bt = self.ty_of(base, TUnknown)', '        if bt is TUnknown {', '          self.n_m_unknown += 1', '        } else {', '          self.n_m_known += 1', '        }', '      }') }

  @{ At = 323; Must = '          self.n_unchecked += 1'; Mode = 'after'
     Add = @('          if nm.contains("::") {', '            self.n_a_method += 1', '          } else {', '            self.n_a_value += 1', '          }') }

  @{ At = 314; Must = '        Some(TUnknownFn(_)) => {'; Mode = 'replace'
     New = @('        Some(TUnknownFn(nm)) => {') }

  @{ At = 63; Must = '    n_unchecked: 0,'; Mode = 'after'
     Add = @('    n_m_known: 0,', '    n_m_unknown: 0,', '    n_m_qual: 0,', '    n_dd_known: 0,', '    n_dd_unknown: 0,', '    n_dd_qual: 0,', '    n_a_value: 0,', '    n_a_method: 0,') }

  @{ At = 29; Must = '  mut n_unchecked : Int32'; Mode = 'after'
     Add = @('  mut n_m_known : Int32', '  mut n_m_unknown : Int32', '  mut n_m_qual : Int32', '  mut n_dd_known : Int32', '  mut n_dd_unknown : Int32', '  mut n_dd_qual : Int32', '  mut n_a_value : Int32', '  mut n_a_method : Int32') }
)

# ---- guard: every anchor checked BEFORE anything is touched --------------------
foreach ($e in $edits) {
  $i = $e.At - 1
  if ($e.Mode -eq 'replaceblock') {
    for ($k = 0; $k -lt $e.Old.Count; $k++) {
      if ($lines[$i + $k] -ne $e.Old[$k]) {
        Write-Output ('ABORT: the block at line ' + $e.At + ' line ' + ($k + 1) + ' is not what was expected.')
        Write-Output ('  expected: [' + $e.Old[$k] + ']')
        Write-Output ('  actual  : [' + $lines[$i + $k] + ']')
        [System.IO.File]::WriteAllBytes($target, $origBytes)
        Write-Output 'RESTORED (the anchor guard fired)'
        exit 1
      }
    }
  } else {
    if ($lines[$i] -ne $e.Must) {
      Write-Output ('ABORT: the anchor at line ' + $e.At + ' is not what was expected.')
      Write-Output ('  expected: [' + $e.Must + ']')
      Write-Output ('  actual  : [' + $lines[$i] + ']')
      [System.IO.File]::WriteAllBytes($target, $origBytes)
      Write-Output 'RESTORED (the anchor guard fired)'
      exit 1
    }
  }
}

# ---- apply, bottom-up ---------------------------------------------------------
foreach ($e in ($edits | Sort-Object { $_.At } -Descending)) {
  $i = $e.At - 1
  $head = @(); if ($i -gt 0) { $head = @($lines[0..($i-1)]) }
  $rest = @($lines[$i..($lines.Length-1)])
  switch ($e.Mode) {
    'before'       { $lines = $head + @($e.Add) + $rest }
    'after'        { $lines = $head + @($rest[0]) + @($e.Add) + @($rest[1..($rest.Count-1)]) }
    'replace'      { $lines = $head + @($e.New) + @($rest[1..($rest.Count-1)]) }
    'replaceblock' { $lines = $head + @($e.New) + @($rest[$e.Old.Count..($rest.Count-1)]) }
  }
}
[System.IO.File]::WriteAllText($target, ($lines -join "`n"), (New-Object System.Text.UTF8Encoding($false)))
Write-Output ('PATCH APPLIED, sha256 now ' + (Get-FileHash -Path $target -Algorithm SHA256).Hash)

function Restore-And-Rebuild {
  param([string]$Why)
  [System.IO.File]::WriteAllBytes($target, $origBytes)
  $nowSha = (Get-FileHash -Path $target -Algorithm SHA256).Hash
  Write-Output ('RESTORED SHA256: ' + $nowSha + '   identical: ' + ($nowSha -eq $origSha) + '   (' + $Why + ')')
  $ob = Join-Path $env:TEMP 'm0508_restore_build.out'
  $pb = Start-Process -FilePath $moon -ArgumentList @('-C', $root, 'build', '--target', 'wasm') `
    -WorkingDirectory $root -RedirectStandardOutput $ob `
    -RedirectStandardError (Join-Path $env:TEMP 'm0508_restore_build.err') -NoNewWindow -Wait -PassThru
  Write-Output ('RESTORE-BUILD EXIT = ' + $pb.ExitCode + '  (the wasm on disk matches the committed source again)')
}

$o = Join-Path $env:TEMP 'm0508_build.out'
$e2 = Join-Path $env:TEMP 'm0508_build.err'
$p = Start-Process -FilePath $moon -ArgumentList @('-C', $root, 'build', '--target', 'wasm') -WorkingDirectory $root -RedirectStandardOutput $o -RedirectStandardError $e2 -NoNewWindow -Wait -PassThru
Write-Output ('BUILD EXIT = ' + $p.ExitCode)
if ($p.ExitCode -ne 0) {
  Write-Output '--- the build error, HEAD first ---'
  Get-Content $e2 -Encoding UTF8 | Select-Object -First 70 | ForEach-Object { Write-Output ('  ' + $_) }
  Restore-And-Rebuild -Why 'the build failed'
  exit 1
}

function Read-TextWhenFree {
  param([string]$Path, [int]$Tries = 20)
  for ($i = 1; $i -le $Tries; $i++) {
    try { return [System.IO.File]::ReadAllText($Path) }
    catch [System.IO.IOException] { Start-Sleep -Milliseconds (100 * $i) }
  }
  throw ('could not read ' + $Path)
}

function Scan-Tree {
  param([string]$Path)
  $dir = Join-Path $env:TEMP ('m0508_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  $out = Join-Path $dir 'o.txt'
  Start-Process -FilePath $moonrun `
    -ArgumentList @($wasm, $Path, '--extern-iface-dir', $repos, '--no-auto-fetch-deps', '--findings-shown-per-file', '1000000') `
    -RedirectStandardOutput $out -RedirectStandardError (Join-Path $dir 'o.err') -NoNewWindow -Wait | Out-Null
  return Read-TextWhenFree -Path $out
}

function Get-Split {
  param([string]$Text)
  $acc = @{}
  foreach ($k in $COUNTERS) { $acc[$k] = 0 }
  $n = 0
  foreach ($m in [regex]::Matches($Text, '(?m)^UNCHECKED-SPLIT (.+)$')) {
    $n++
    foreach ($kv in ($m.Groups[1].Value -split ' ')) {
      $pair = $kv -split '='
      if ($acc.ContainsKey($pair[0])) { $acc[$pair[0]] += [int]$pair[1] }
    }
  }
  return @{ counters = $acc; files = $n }
}

$TARGETS = [ordered]@{
  'moui'            = 'wzzc-dev\moui\0.1.12'
  'moonbit_labeler' = 'riantr\moonbit_labeler\0.2.13'
  'moonbit_image'   = 'riantr\moonbit_image\0.3.7'
  'async'           = 'moonbitlang\async\0.22.4'
  'proton'          = 'moonbit-community\proton\0.3.4'
  'proton_contract' = 'moonbit-community\proton_contract\0.3.4'
  'moonbit_core'    = 'moonbitlang\core\0.1.20260920+7d59c7ec9'
}

$tot = @{}
foreach ($k in $COUNTERS) { $tot[$k] = 0 }
$sumT = 0
$sumFiles = 0

Write-Output ''
Write-Output '=== HOW THE UNCHECKED CALLS DIVIDE ==='
foreach ($k in $TARGETS.Keys) {
  $text = Scan-Tree (Join-Path $repos $TARGETS[$k])
  $s = Get-Split $text
  $c = $s.counters
  foreach ($kk in $COUNTERS) { $tot[$kk] += $c[$kk] }
  $sumFiles += $s.files
  $total = [int]([regex]::Match($text, '(?m)^SUMMARY.*$').Value -replace '.*unchecked=(\d+).*', '$1')
  $sumT += $total
  $b = $c['n_m_known'] + $c['n_m_unknown'] + $c['n_m_qual']
  $cc = $c['n_dd_known'] + $c['n_dd_unknown'] + $c['n_dd_qual']
  $a = $c['n_a_value'] + $c['n_a_method']
  Write-Output ('  {0,-16} A={1,-6} B={2,-6} C={3,-4} | m: known={4,-5} unknown={5,-5} qual={6,-4} | a: value={7,-4} method={8,-4} | sum={9,-6} summary={10,-6} files={11}' -f `
    $k, $a, $b, $cc, $c['n_m_known'], $c['n_m_unknown'], $c['n_m_qual'], $c['n_a_value'], $c['n_a_method'], ($a + $b + $cc), $total, $s.files)
}
$text = Scan-Tree $root
$s = Get-Split $text
$c = $s.counters
foreach ($kk in $COUNTERS) { $tot[$kk] += $c[$kk] }
$sumFiles += $s.files
$total = [int]([regex]::Match($text, '(?m)^SUMMARY.*$').Value -replace '.*unchecked=(\d+).*', '$1')
$sumT += $total
$b = $c['n_m_known'] + $c['n_m_unknown'] + $c['n_m_qual']
$cc = $c['n_dd_known'] + $c['n_dd_unknown'] + $c['n_dd_qual']
$a = $c['n_a_value'] + $c['n_a_method']
Write-Output ('  {0,-16} A={1,-6} B={2,-6} C={3,-4} | m: known={4,-5} unknown={5,-5} qual={6,-4} | a: value={7,-4} method={8,-4} | sum={9,-6} summary={10,-6} files={11}' -f `
  'own source', $a, $b, $cc, $c['n_m_known'], $c['n_m_unknown'], $c['n_m_qual'], $c['n_a_value'], $c['n_a_method'], ($a + $b + $cc), $total, $s.files)

$bAll = $tot['n_m_known'] + $tot['n_m_unknown'] + $tot['n_m_qual']
$cAll = $tot['n_dd_known'] + $tot['n_dd_unknown'] + $tot['n_dd_qual']
$aAll = $tot['n_a_value'] + $tot['n_a_method']
Write-Output ''
Write-Output '  THE EIGHT TREES'
Write-Output ('    A  a name known only by NAME              : ' + $aAll)
Write-Output ('    B  a method call                          : ' + $bAll)
Write-Output ('    C  a `..` chain link                      : ' + $cAll)
Write-Output ('    the unchecked calls, eight trees         : ' + ($aAll + $bAll + $cAll))
Write-Output ('    the shipped SUMMARY says                 : ' + $sumT)
Write-Output ('    the trees the instrument read            : ' + $sumFiles)
Write-Output ''
Write-Output '  B SPLIT BY THE RECEIVER TYPE'
Write-Output ('    the receiver type is KNOWN               : ' + $tot['n_m_known'])
Write-Output ('    the receiver type is UNKNOWN             : ' + $tot['n_m_unknown'])
Write-Output ('    a qualifier receiver (`@pkg.f(..)`)      : ' + $tot['n_m_qual'])
Write-Output ''
Write-Output '  A SPLIT BY WHAT THE CALLEE IS'
Write-Output ('    a plain function name                    : ' + $tot['n_a_value'])
Write-Output ('    a `Type::method` name                    : ' + $tot['n_a_method'])
Write-Output ''
if (($aAll + $bAll + $cAll) -ne $sumT) {
  Write-Output ('  CONTROL FAILED: the split sums to ' + ($aAll + $bAll + $cAll) + ' but the SUMMARY says ' + $sumT + '.')
  Restore-And-Rebuild -Why 'the control failed'
  exit 1
}
Write-Output ('  CONTROL OK: the split accounts for every unchecked call the shipped SUMMARY counted.')

Restore-And-Rebuild -Why 'the measurement is done'
exit 0
