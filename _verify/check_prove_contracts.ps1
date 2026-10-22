param([switch]$SelfTest)
$ErrorActionPreference = 'Continue'
# The PROOF CONTRACTS must be honest.
#
# WHY THIS FILE EXISTS. `#proof_pure` marks a function as a proof contract: the
# prover generates a verification condition for it and the body has to be
# PURE -- only Int/Bool constants and direct pure calls. A function whose body
# allocates a `StringBuilder` is not pure, and the prover rejects it with
# error 4207, "unsupported expression in pure function body".
#
# AND ONE FALSE ANNOTATION STOPS THE WHOLE FILE FROM PROVING. The check is
# per-package, so a single 4207 anywhere in `src/core` means the file does not
# lower at all -- no goals, no VCs, no proof. That is not a partial result; it
# is the whole thing gone.
#
# MEASURED 2026-10-22. Two `#proof_pure` annotations were false, on
# `path_tail` and `unqualified` -- both build a `StringBuilder` -- and both
# were added on 2026-10-09, in the same commit that added the second of them.
# `moon prove src/core` had been failing with 4207 ever since, and nothing
# noticed, because the release gate never ran it.
#
# The two annotations are removed. This gate is what keeps them removed.
#
# WHAT IT CHECKS, and what it does NOT:
#   - it FAILS if `moon prove` reports ANY error 4207. That is the false
#     annotation class, and it is checkable and it can pass.
#   - it does NOT fail on the known `unbound type symbol 'map'` limitation:
#     `src/core` carries `IfaceSymTab` (fields are `Map[String, Bool]`) and the
#     toolchain's proof prelude has no `Map` theory, so the generated Why3 file
#     will not load. That is a separate defect with a separate fix -- moving
#     `IfaceSymTab` out of the proof subject changes the package's public API --
#     and it is reported here, not papered over.
#
# => 判据: a documented command that nothing runs is a comment. The claim was
# "21/21 goals VALID", and the release gate could not tell a proof from a
# command that had not run since 2026-10-09.
#
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File _verify\check_prove_contracts.ps1
$root = Split-Path -Parent $PSScriptRoot
$moon = 'C:\Users\31379\.moon\bin\moon.exe'
$why3 = Join-Path $root '.why3.conf'
$fail = 0

Write-Output '=== the proof contracts in src/core ==='
$core = Join-Path $root 'src\core\core.mbt'
$lines = Get-Content -LiteralPath $core -Encoding UTF8
$pure = @()
for ($i = 0; $i -lt $lines.Count; $i++) {
  if ($lines[$i].Trim() -eq '#proof_pure') {
    $j = $i + 1
    while ($j -lt $lines.Count -and $lines[$j].Trim() -eq '') { $j++ }
    $pure += $lines[$j].Trim()
  }
}
Write-Output ('  #proof_pure contracts: ' + $pure.Count)
foreach ($p in $pure) { Write-Output ('    ' + $p) }

Write-Output '=== moon prove src/core ==='
if (-not (Test-Path -LiteralPath $why3)) {
  Write-Output '  MISSING: .why3.conf is not in the repository (it is a local shim).'
  Write-Output '          The proof lane cannot run without it; see the skill notes.'
  exit 1
}
$prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
$out = & $moon -C $root prove src/core --why3-config $why3 2>&1 | Out-String
$code = $LASTEXITCODE
$ErrorActionPreference = $prev

$n4207 = ([regex]::Matches($out, '\[4207\]')).Count
$nMap  = ([regex]::Matches($out, "unbound type symbol 'map'")).Count
Write-Output ('  exit code: ' + $code)
Write-Output ('  error 4207 (a #proof_pure body the prover rejects): ' + $n4207)
Write-Output ('  the known `map` limitation: ' + $nMap)

if ($n4207 -gt 0) {
  Write-Output ''
  Write-Output ('  FAIL: ' + $n4207 + ' error(s) 4207. A #proof_pure contract has a body the')
  Write-Output '  prover rejects, and ONE of them stops the whole file from proving.'
  Write-Output '  Find the function above whose body allocates or calls anything impure, and'
  Write-Output '  remove its #proof_pure -- the annotation was a claim the body did not keep.'
  ($out -split "`r?`n" | Where-Object { $_ -match '4207' -or $_ -match 'core\.mbt:\d+' } | Select-Object -First 8) |
    ForEach-Object { Write-Output ('    | ' + $_.Trim()) }
  $fail++
}

if ($nMap -gt 0) {
  Write-Output ''
  Write-Output '  KNOWN, and reported rather than hidden: the generated Why3 file declares'
  Write-Output '  `map int bool` for IfaceSymTab and the proof prelude has no Map theory,'
  Write-Output '  so the file will not load and the 19 lemmas are NOT being discharged.'
  Write-Output '  The fix is to move IfaceSymTab out of the proof subject -- a public-API'
  Write-Output '  change, and therefore a version-line decision.'
}

Write-Output ''
if ($fail -eq 0) {
  Write-Output 'PROVE CONTRACTS OK: no false annotation, so the file lowers and the goals are generated.'
  exit 0
}
Write-Output ('PROVE CONTRACTS FAILED: ' + $fail + ' problem(s).')
exit 1
