# Prove that one NAMED test really goes red under a mutation, before spending a
# full gate run on it.
#
# WHY THIS FILE EXISTS. Gate 0441's first run reported "4 killed" and still FAILED,
# because M2 and M4 named `0441: the type lens also keeps the two variants apart`
# as the test that must go red and it did not. That test was documented as the pin
# for `Infer::run_fn`'s separate by-name lookup -- so it was a guard claiming
# coverage it did not have, and the only reason anyone found out is that
# `MustRed` (harness rule 6) demands the NAME and not merely "something went red".
#
# Re-anchoring the name would have made the gate green and left the test still
# worthless. Fixing the TEST was the only honest move, and fixing it needs its own
# proof: the new source must be green on clean code AND red under the mutation.
# The first half is `moon test`; this file is the second half.
#
# `moon test --filter '0441*'` runs six tests in well under a minute against a
# full-suite run, and the trailing `*` is required: the filter anchors at the
# start of the test name, and `0441` with no star matched NOTHING while still
# printing `Total tests: 0` and exiting 0.
#
# Usage:
#   .\_verify\prove_mustred.ps1 -File src\types\infer.mbt -FindFile f.txt -ReplFile r.txt `
#       -ExpectRed 'the type lens also keeps the two variants apart' [-Filter '0441*']

param(
  [Parameter(Mandatory = $true)][string]$File,
  [Parameter(Mandatory = $true)][string]$FindFile,
  [Parameter(Mandatory = $true)][string]$ReplFile,
  [Parameter(Mandatory = $true)][string]$ExpectRed,
  [string]$Filter = '*',
  [string]$Root = (Split-Path -Parent $PSScriptRoot),
  [string]$MoonExe = 'C:\Users\31379\.moon\bin\moon.exe'
)

$ErrorActionPreference = 'Stop'
$nl = [string][char]10
$enc = New-Object System.Text.UTF8Encoding($false)
$path = Join-Path $Root $File

$bytes0 = [System.IO.File]::ReadAllBytes($path)
$sha0 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash

$findN = [System.IO.File]::ReadAllText($FindFile, [System.Text.Encoding]::UTF8).Replace("`r`n", $nl)
$replN = [System.IO.File]::ReadAllText($ReplFile, [System.Text.Encoding]::UTF8).Replace("`r`n", $nl)
if (-not $findN.EndsWith($nl)) { $findN = $findN + $nl }
if ($replN -ne '' -and -not $replN.EndsWith($nl)) { $replN = $replN + $nl }

$text = [System.Text.Encoding]::UTF8.GetString($bytes0)
$eol = if ($text.Contains([string][char]13 + [char]10)) { [string][char]13 + [char]10 } else { $nl }
$norm = $text.Replace($eol, $nl)
if ($norm.IndexOf($findN, [System.StringComparison]::Ordinal) -lt 0) {
  Write-Output 'PREFLIGHT MISS: the pattern is absent, so nothing was applied.'
  exit 1
}

function Invoke-Test {
  param([string]$Root, [string]$MoonExe, [string]$Filter)
  Push-Location $Root
  $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  $o = & $MoonExe test --target js --filter $Filter 2>&1 | Out-String
  $ErrorActionPreference = $prev
  Pop-Location
  return $o
}

$clean = Invoke-Test $Root $MoonExe $Filter
$cRan = [regex]::Matches($clean, 'Total tests: (\d+), passed: (\d+), failed: (\d+)')
if ($cRan.Count -lt 1) { Write-Output 'ABORT: clean run printed no `Total tests:` line.'; exit 1 }
$cM = $cRan[$cRan.Count - 1]
if ([int]$cM.Groups[3].Value -ne 0) {
  Write-Output ("ABORT: clean code is RED ({0} failed). Nothing below means anything." -f $cM.Groups[3].Value)
  exit 1
}
Write-Output ("Clean: {0}/{1} passed." -f $cM.Groups[2].Value, $cM.Groups[1].Value)

try {
  [System.IO.File]::WriteAllText($path, $norm.Replace($findN, $replN).Replace($nl, $eol), $enc)
  $mut = Invoke-Test $Root $MoonExe $Filter
  $names = @([regex]::Matches($mut, '\("([^"]+)"\) failed:') | ForEach-Object { $_.Groups[1].Value })
  $hit = @($names | Where-Object { $_ -like "*$ExpectRed*" }).Count -gt 0

  $mRan = [regex]::Matches($mut, 'Total tests: (\d+), passed: (\d+), failed: (\d+)')
  $sum = if ($mRan.Count -ge 1) { $mRan[$mRan.Count - 1].Value } else { 'NO SUMMARY (compile error)' }

  if ($hit) {
    Write-Output ("PROVEN: the named test goes red.  {0}" -f $sum)
  } else {
    Write-Output ("NOT PROVEN: '" + $ExpectRed + "' did not go red.  {0}" -f $sum)
    Write-Output 'These went red instead:'
    foreach ($n in $names) { Write-Output ('  - ' + $n) }
  }
}
finally {
  [System.IO.File]::WriteAllBytes($path, $bytes0)
  $sha1 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
  Write-Output ('restore byte-identical: ' + ($sha0 -eq $sha1))
}
