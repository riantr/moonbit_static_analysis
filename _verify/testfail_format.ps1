$ErrorActionPreference = 'Continue'
# What does `moon test` actually print for a FAILING test?
#
# `_verify/mutate_lib.ps1` proves a mutation was killed by counting red tests. That
# cannot tell whether the INTENDED test died or some unrelated one did -- which is
# the gap 0418's dead `$ExpectRed` parameter was supposed to close. To implement a
# named-test check I need the failure line format, so it is captured here from a
# known mutation rather than assumed.
#
# The capture is read-only with respect to the tree: the file is backed up as BYTES,
# restored from those bytes, and the restore proven by SHA256. A wrong format guess
# would make a new gate silently never match.
$ErrorActionPreference = 'Stop'
$root = 'D:\src\DeepseekHarness\Projects\xiuyueren\StaticAnalysis\moonbit_static_analysis'
$moon = 'C:\Users\31379\.moon\bin\moon.exe'
$path = Join-Path $root 'src\parser\parser.mbt'

$find = "  if self.at_name(`"else`") {`n    let _ = self.bump()`n    let (eb, _) = self.parse_block(false)`n    els = Some(eb)`n  }"
$repl = "  if self.at_name(`"else`") && self.at_name(`"zzz_never`") {`n    let _ = self.bump()`n    let (eb, _) = self.parse_block(false)`n    els = Some(eb)`n  }"

$bytes = [System.IO.File]::ReadAllBytes($path)
$sha0 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
$text = [System.Text.Encoding]::UTF8.GetString($bytes)
$nl = [string][char]10
$eol = if ($text.Contains([string][char]13 + [char]10)) { [string][char]13 + [char]10 } else { $nl }
$norm = $text.Replace($eol, $nl)
$findN = $find.Replace("`r`n", $nl)
$replN = $repl.Replace("`r`n", $nl)

if ($norm.IndexOf($findN, [System.StringComparison]::Ordinal) -lt 0) {
  Write-Output 'ABORT: the 0.4.21 M2 pattern is not present; nothing was changed.'
  exit 1
}
Write-Output 'pattern present; applying it'
[System.IO.File]::WriteAllText($path, $norm.Replace($findN, $replN).Replace($nl, $eol), (New-Object System.Text.UTF8Encoding($false)))

$prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
$out = & $moon test --target wasm 2>&1 | Out-String
$ErrorActionPreference = $prev

# restore FIRST, then analyse -- no analysis path can leave the tree mutated
[System.IO.File]::WriteAllBytes($path, $bytes)
$sha1 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
Write-Output ("restore byte-identical: " + ($sha0 -eq $sha1))
Write-Output ''

Write-Output '=== lines that look like test failures ==='
$lines = $out -split "`r?`n"
$hit = @()
for ($i = 0; $i -lt $lines.Count; $i++) {
  $l = $lines[$i]
  if ($l -match 'Total tests:' -or $l -match '^\s*$') { continue }
  if ($l -match 'FAIL|failed|✗|×|error\[|assert' -or $l -match '^\s+\d{4}: ') {
    $hit += ("  {0}" -f $l.Trim())
  }
}
if ($hit.Count -eq 0) {
  Write-Output '  (nothing matched those patterns -- the format is something else)'
} else {
  $hit | Select-Object -First 25
}
Write-Output ''
Write-Output '=== the Total line ==='
Write-Output ('  ' + ([regex]::Match($out, '(?m)^\s*Total tests:.*$')).Value.Trim())
Write-Output ''
Write-Output '=== full output, first 40 non-blank lines (so the format cannot be misread) ==='
($lines | Where-Object { $_.Trim() -ne '' } | Select-Object -First 40) | ForEach-Object { Write-Output ('  | ' + $_.TrimEnd()) }
