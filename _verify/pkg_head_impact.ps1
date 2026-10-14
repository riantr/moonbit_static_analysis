# How many files does the `@pkg` is-pattern head actually BLOCK?
#
# WHY THIS SCRIPT EXISTS. `blockers.ps1` reported OVERLAP 0 between "moui files
# containing an `@pkg` is-head" and "blocked files with a PARTIAL line" -- which
# reads like the gap costs nothing. It does not. Scanning
# `backend/macos/macos_services.mbt` on its own gives `PARSED 0/1`: it IS
# blocked, and it is one of the four files that print NO PARTIAL line because
# they had zero findings before their boundary. `blockers.ps1` documents that
# blind spot in its own header ("this list is a lower bound, not the whole of
# it") and the cross-reference landed squarely in it.
#
# ⇒ 判据: a lower bound that agrees with "no problem" is not evidence of no
# problem. Cross-referencing two lists only tells you about the part both can
# see.
#
# The measurement each file needs is the only honest one: scan the file ALONE
# and read `parsed=0/1`. moonrun takes a DIRECTORY, so each file is copied into
# its own temp directory. The copy loses its imports, which does not matter --
# this is a parse question, not a name-resolution one.
param()
$ErrorActionPreference = 'Continue'
$repo = Split-Path -Parent $PSScriptRoot
Set-Location $repo
$wasm = Join-Path $repo '_build\wasm\debug\build\moonbit_static_analysis.wasm'
$repos = Join-Path $repo '.repos'
$moonrun = 'C:\Users\31379\.moon\bin\moonrun.exe'
$moui = Join-Path $repos 'wzzc-dev\moui\0.1.12'

$files = @(Get-ChildItem -Recurse -Include *.mbt, *.mbti -File $moui |
  Select-String -Pattern '\bis\s+@[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)*::' |
  ForEach-Object { $_.Path } | Sort-Object -Unique)

Write-Output ('=== files whose only suspect construct is an `@pkg` is-head: ' + $files.Count + ' ===')
Write-Output '    (each scanned ALONE; parsed=0/1 means this construct blocks the file)'
$blocked = 0
foreach ($f in $files) {
  $rel = $f.Substring($moui.Length + 1)
  $t = Join-Path $env:TEMP ('one_' + [guid]::NewGuid().ToString('N').Substring(0, 6))
  New-Item -ItemType Directory -Force -Path $t | Out-Null
  Copy-Item -LiteralPath $f -Destination $t
  $o = Join-Path $t '..\o.txt'
  $e = Join-Path $t '..\e.txt'
  Start-Process -FilePath $moonrun `
    -ArgumentList @($wasm, $t, '--extern-iface-dir', $repos) `
    -RedirectStandardOutput $o -RedirectStandardError $e -NoNewWindow -Wait | Out-Null
  $txt = ''
  for ($i = 1; $i -le 20; $i++) {
    try { $txt = [System.IO.File]::ReadAllText($o); break }
    catch [System.IO.IOException] {
      if ($i -eq 20) { throw ("could not read " + $o + " after 20 attempts") }
      Start-Sleep -Milliseconds (100 * $i)
    }
  }
  $p = [regex]::Match($txt, '(?m)^BYKIND.*$')
  $parsed = if ($p.Value -match 'parsed=(\d+)') { [int]$Matches[1] } else { -1 }
  $total = if ($p.Value -match 'files=(\d+)') { [int]$Matches[1] } else { -1 }
  $tag = if ($parsed -ge 0 -and $total -gt 0 -and $parsed -lt $total) { 'BLOCKED' } else { 'parses ' }
  if ($tag -eq 'BLOCKED') { $blocked += 1 }
  Write-Output ('  {0}  {1,-46} parsed={2}/{3}' -f $tag, $rel, $parsed, $total)
  Remove-Item -LiteralPath $t -Recurse -Force
  Remove-Item -LiteralPath $o -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $e -Force -ErrorAction SilentlyContinue
}
Write-Output ''
Write-Output ("  $blocked of $($files.Count) files are BLOCKED by this construct alone.")
Write-Output '  A file can also be blocked by an EARLIER construct of its own, so this is a'
Write-Output '  LOWER BOUND on what fixing the `@pkg` head would unblock, not a forecast.'