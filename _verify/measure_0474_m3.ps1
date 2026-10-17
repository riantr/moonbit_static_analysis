# The measurement behind `mutate_0474`'s M3 SURVIVED verdict. It is COMMITTED, and it is not
# part of the release gate: it is the one-off A/B whose numbers the gate's `Prove` quotes, and a
# claim that cannot be re-run is a claim nobody can check. The gate asserts the verdict; this
# script is what would show the verdict to be wrong.
#
# THE QUESTION. M3 turns the cursor restore `self.p -= 1` into `self.p += 1` in the `for`
# arm of `parse_atom`. The mutation harness reports it as surviving, and the usual response
# is to go looking for the missing row. This script instead asks the question that decides
# it: is M3 observable AT ALL, or only unobserved?
#
# The two answers need different verdicts. "No test catches it" is a missing test. "Nothing
# can catch it" is a structural fact about the increment and has to be declared as a
# survivor with its mechanism written out -- otherwise a future reader assumes the suite
# has a hole and goes looking for a fixture that cannot exist.
#
# WHY THE CORPUS AND NOT JUST THE SUITE. `parse_loop_as_expr` discards the statement it just
# parsed, so no AST the caller can see should differ. But `c_for_init` calls `parse_stmt`
# on whatever the misrouted header presents, and `parse_stmt` is a whole statement reader --
# it is entirely capable of consuming a different number of tokens than the binder reader
# did. If it does, the file still parses, `first_error` is still 0, and every tree-shape
# assertion in the suite still passes, while the corpus notices move. A test suite cannot
# see that; the corpus can. So both trees are measured, in ONE session, so the only
# difference between the two columns is the single line under test.
#
# Everything is restored from the bytes read at entry and the SHA256 is re-checked on the
# way out, because the mutation harness's rule 4 is that writing back what you read is not
# the same as writing back what was there.
#
# NOT SAFE TO RUN CONCURRENTLY WITH A GATE. Both rewrite `src/parser/parser.mbt` and both
# rebuild into `_build`; that is mutate_lib's rule 7, and it applies to this script too.
# 'Continue', not 'Stop': `moon` writes its progress banner to stderr, and under 'Stop' that
# raises NativeCommandError and kills the script on the FIRST successful build. Every native
# call below is checked on $LASTEXITCODE instead, which is the honest test anyway.
$ErrorActionPreference = 'Continue'

$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$moon = 'C:\Users\31379\.moon\bin\moon.exe'
$moonrun = 'C:\Users\31379\.moon\bin\moonrun.exe'
$repos = Join-Path $root '.repos'
$wasm = Join-Path $root '_build\wasm\debug\build\moonbit_static_analysis.wasm'
$parser = Join-Path $root 'src\parser\parser.mbt'
$async = Join-Path $repos 'moonbitlang\async\0.22.4'

$FIND = @'
    TName("for") => {
      self.p -= 1
      self.parse_loop_as_expr(sp)
    }
'@.Replace("`r`n", "`n")
$REPL = @'
    TName("for") => {
      self.p += 1
      self.parse_loop_as_expr(sp)
    }
'@.Replace("`r`n", "`n")

function Get-Summary {
  param([string]$Text)
  $s = ([regex]::Match($Text, '(?m)^SUMMARY.*$').Value) -replace "`t", ' '
  $s = $s -replace '^SUMMARY\s*', ''
  $s = $s -replace '\s*\(actionable.*$', ''
  return ((($s -split '\s+') | Where-Object { $_ -ne '' }) -join ' ')
}

function Measure-Tree {
  param([string]$Label)
  & $moon build --target wasm 2>&1 | Out-Null
  if ($LASTEXITCODE -ne 0) { Write-Output ("{0}: BUILD FAILED" -f $Label); return }
  $t = (& $moon test --target wasm --deny-warn 2>&1 | Out-String)
  $tot = ([regex]::Match($t, '(?m)^Total tests:.*$')).Value.Trim()
  if ($tot -eq '') { $tot = 'NO Total tests: LINE (compile error)' }
  $dir = Join-Path $env:TEMP ('m3_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  $out = Join-Path $dir 'o.txt'
  Start-Process -FilePath $moonrun `
    -ArgumentList @($wasm, $async, '--extern-iface-dir', $repos) `
    -RedirectStandardOutput $out -RedirectStandardError (Join-Path $dir 'o.err') `
    -NoNewWindow -Wait | Out-Null
  $txt = Get-Content -Raw $out
  Write-Output ("{0}  tests: {1}" -f $Label, $tot)
  Write-Output ("{0}  async: {1}" -f $Label, (Get-Summary $txt))
  # The blocked-file list is the part a summary cannot hide: a file that moves between
  # blocked and parsed is the only observable this whole question turns on.
  $part = @([regex]::Matches($txt, '(?m)^.*\bPARTIAL\b.*$') | ForEach-Object { $_.Value.Trim() })
  Write-Output ("{0}  async PARTIAL lines: {1}" -f $Label, $part.Count)
  Set-Content -Path (Join-Path $env:TEMP ('m3_' + $Label + '_partial.txt')) -Value $part -Encoding UTF8
}

$orig = [IO.File]::ReadAllText($parser)
$sha0 = (Get-FileHash -Algorithm SHA256 $parser).Hash
Write-Output ('parser.mbt sha256 before : ' + $sha0)
Write-Output ''

try {
  Write-Output '=== COLUMN A: correct (self.p -= 1) ==='
  Measure-Tree 'correct'

  $n = ([regex]::Matches($orig, [regex]::Escape($FIND))).Count
  Write-Output ''
  Write-Output ("anchor occurrences: " + $n)
  if ($n -ne 1) { throw 'anchor is not unique -- refusing to measure' }
  $mut = $orig.Replace($FIND, $REPL)
  [IO.File]::WriteAllText($parser, $mut)
  Write-Output ''
  Write-Output '=== COLUMN B: mutated (self.p += 1) ==='
  Measure-Tree 'mutated'
}
finally {
  [IO.File]::WriteAllText($parser, $orig)
  $sha1 = (Get-FileHash -Algorithm SHA256 $parser).Hash
  Write-Output ''
  Write-Output ('parser.mbt sha256 after  : ' + $sha1)
  Write-Output ('restore verified        : ' + ($sha0 -eq $sha1))
}
