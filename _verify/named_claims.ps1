$ErrorActionPreference = 'Continue'
# Are the gates' NAMED-TEST claims true?
#
# 0.4.21's gate says of M2: "Only `0421: a guard's else body is still analyzed`
# can catch this." That test exists (pipeline_0421_test.mbt:76). A capture of the
# real `moon test` failure output under exactly that mutation says it does NOT go
# red -- six other tests do, three of them from the LATER 0.4.25 gate.
#
# A count cannot see this. `KILLED` means SOMETHING went red; the gate's claim is
# about WHICH. The 0.4.18 runner carried a `[string[]]$ExpectRed` parameter
# documented as "test-name substrings that MUST go red", passed the literal
# 'expectRed' at all twelve call sites, and never read it -- so the check the
# project believed it had was not running.
#
# So each named claim is checked here against the real failure output. The failure
# format is a single line per red test:
#   [<pkg>] test <file>:<line> ("<test name>") failed: ...
# and this reads the name out of the quotes.
$ErrorActionPreference = 'Stop'
$root = 'D:\src\DeepseekHarness\Projects\xiuyueren\StaticAnalysis\moonbit_static_analysis'
$moon = 'C:\Users\31379\.moon\bin\moon.exe'
$nl = [string][char]10

# Each case: the gate, the mutation, the file, the literal pattern, the literal
# replacement, the target the gate itself uses, and the test the gate NAMES.
$cases = @(
  [pscustomobject]@{
    Gate = 'mutate_0419 M3'; Target = 'wasm'
    File = 'src\parser\parser.mbt'
    Find = '            is_fn = j + 1 < self.toks.length() && self.toks[j + 1] == TArrow'
    Repl = '            is_fn = j + 1 < self.toks.length() && self.toks[j - 1] == TArrow'
    Named = '0419: a function-type return annotation parses'
  },
  [pscustomobject]@{
    Gate = 'mutate_0420 M2'; Target = 'wasm'
    File = 'src\parser\parser.mbt'
    Find = 'if self.at_name("fn") && !saw_with {'
    Repl = 'if self.at_name("fn") && !saw_with && self.at_name("zzz_never") {'
    Named = '0420: a bodiless impl still stops at the next top-level fn'
  },
  [pscustomobject]@{
    Gate = 'mutate_0421 M2'; Target = 'wasm'
    File = 'src\parser\parser.mbt'
    Find = "  if self.at_name(`"else`") {`n    let _ = self.bump()`n    let (eb, _) = self.parse_block(false)`n    els = Some(eb)`n  }"
    Repl = "  if self.at_name(`"else`") && self.at_name(`"zzz_never`") {`n    let _ = self.bump()`n    let (eb, _) = self.parse_block(false)`n    els = Some(eb)`n  }"
    Named = "0421: a guard's else body is still analyzed"
  }
)

$verdicts = @()
foreach ($c in $cases) {
  Write-Output ("=== " + $c.Gate + " ===")
  Write-Output ('  gate names: "' + $c.Named + '"')
  $path = Join-Path $root $c.File
  $bytes = [System.IO.File]::ReadAllBytes($path)
  $sha0 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
  $text = [System.Text.Encoding]::UTF8.GetString($bytes)
  $eol = if ($text.Contains([string][char]13 + [char]10)) { [string][char]13 + [char]10 } else { $nl }
  $norm = $text.Replace($eol, $nl)
  $findN = $c.Find.Replace("`r`n", $nl)
  $replN = $c.Repl.Replace("`r`n", $nl)
  if ($norm.IndexOf($findN, [System.StringComparison]::Ordinal) -lt 0) {
    Write-Output '  ABORT: pattern absent; nothing changed.'
    Write-Output ''
    continue
  }
  [System.IO.File]::WriteAllText($path, $norm.Replace($findN, $replN).Replace($nl, $eol), (New-Object System.Text.UTF8Encoding($false)))

  $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  $out = & $moon test --target $c.Target 2>&1 | Out-String
  $ErrorActionPreference = $prev

  [System.IO.File]::WriteAllBytes($path, $bytes)
  $okRestore = ($sha0 -eq (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash)

  $red = @([regex]::Matches($out, '\("([^"]+)"\) failed:') | ForEach-Object { $_.Groups[1].Value })
  $total = ([regex]::Match($out, 'Total tests: (\d+), passed: (\d+), failed: (\d+)'))
  $killed = if ($total.Success) { [int]$total.Groups[3].Value } else { -1 }
  $fired = @($red | Where-Object { $_ -like "*$($c.Named)*" }).Count -gt 0

  Write-Output ("  killed=" + $killed + "  restore byte-identical=" + $okRestore)
  Write-Output ('  named test among the red : ' + $(if ($fired) { 'YES' } else { 'NO' }))
  Write-Output '  what actually went red:'
  if ($red.Count -eq 0) { Write-Output '    (nothing)' }
  foreach ($r in $red) { Write-Output ('    - ' + $r) }
  $verdicts += [pscustomobject]@{ Gate = $c.Gate; Killed = $killed; NamedFired = $fired; Restore = $okRestore }
  Write-Output ''
}

Write-Output '=== summary ==='
foreach ($v in $verdicts) {
  Write-Output ("  {0,-16} killed={1,-3} named test fired={2,-3} restore={3}" -f $v.Gate, $v.Killed, $v.NamedFired, $v.Restore)
}
Write-Output ''
$false_claims = @($verdicts | Where-Object { $_.Killed -gt 0 -and -not $_.NamedFired })
Write-Output ("  gates whose named-test claim is FALSE: " + $false_claims.Count + " of " + $verdicts.Count)
