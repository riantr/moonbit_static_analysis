# Pre-flight: does a mutation's replacement actually COMPILE?
#
# WHY THIS FILE EXISTS. `mutate_lib.ps1` reports COMPILE-ERR as its own outcome
# (rule 2: "a mutant that fails to build is not a killed mutant; it is a mutant
# nobody measured"). That is correct for the gate, but it means a mutation whose
# replacement CANNOT compile costs a whole gate run before anyone learns that --
# gate 0441's M1 was written as `fn_bindings.set(f.name, bs)` against a field
# that is an `Array` now, and it would have died COMPILE-ERR on the full suite.
#
# So: apply the replacement, run `moon check`, restore. Cheap, and it is the only
# way to know a mutation measures behaviour rather than types.
#
# THE TRAP THIS SCRIPT IS WRITTEN AROUND. The first hand-rolled version set
# `$ErrorActionPreference = 'Stop'` and then ran `moon.exe check 2>&1`. moon
# prints its normal `Finished. moon: ran N tasks, now up to date` line on
# STDERR, so PowerShell raised `NativeCommandError` as a TERMINATING error and
# the script died BEFORE the restore -- leaving `src/walk/walk.mbt` mutated in
# the working tree. `mutate_lib.ps1` already wraps its native calls with
# `$ErrorActionPreference = 'Continue'`; this file does the same AND puts the
# restore in a `finally`, because a killed script restores nothing.
#
# Usage:
#   .\_verify\preflight_compile.ps1 -File 'src\walk\walk.mbt' -FindFile '.repos\_m1.txt'
#
# Reads Find/Repl from two files so the here-string indentation rule does not
# apply and no shell escaping can alter the text.

param(
  [Parameter(Mandatory = $true)][string]$File,
  [Parameter(Mandatory = $true)][string]$FindFile,
  [Parameter(Mandatory = $true)][string]$ReplFile,
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

try {
  [System.IO.File]::WriteAllText($path, $norm.Replace($findN, $replN).Replace($nl, $eol), $enc)

  Push-Location $Root
  $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  $out = & $MoonExe check 2>&1 | Out-String
  $ErrorActionPreference = $prev
  Pop-Location

  # The guard, from the "moon check did no work" note: a clean check prints a
  # `Finished` line, a rejected one prints `Error: failed when checking project`
  # and NO `Finished` line. Anything else -- including blank -- is UNKNOWN.
  $finished = $out -match 'Finished'
  $rejected = $out -match 'failed when checking project'
  if ($finished -and -not $rejected) {
    Write-Output 'COMPILES. The mutation measures behaviour, not types.'
  } elseif ($rejected) {
    Write-Output 'DOES NOT COMPILE. A gate run would report COMPILE-ERR, not a kill.'
    ($out -split "`r?`n" | Where-Object { $_ -match 'error' } | Select-Object -First 15) |
      ForEach-Object { Write-Output ('  ' + $_.Trim()) }
  } else {
    Write-Output 'UNKNOWN: neither marker present. Treat as a failed measurement.'
    ($out -split "`r?`n" | Select-Object -First 15) | ForEach-Object { Write-Output ('  ' + $_.Trim()) }
  }
}
finally {
  [System.IO.File]::WriteAllBytes($path, $bytes0)
  $sha1 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
  Write-Output ('restore byte-identical: ' + ($sha0 -eq $sha1))
}
