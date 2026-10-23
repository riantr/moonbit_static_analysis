$ErrorActionPreference = 'Continue'
# Verify what the REGISTRY WILL RECEIVE.#
# WHY THIS EXISTS. `.moonignore` is a list of intentions. A rule that is never
# exercised is a comment, and an ignore file whose rules silently stop matching
# is a package that silently grows. This gate runs `moon package --list` --
# the same command `moon publish` packages from -- and checks the result.
#
# WHAT IT CHECKS, and each item is a thing that can be WRONG:
#
#   1. The JUNK CLASSES are absent: the scratch commit messages, the scan
#      artifacts, the credential, the gate transcripts, the remeasure dumps, and
#      the one source file the repository itself declares un-committable.
#   2. The EVIDENCE is present: the mutation gates, the settle scripts, the
#      narrative, the roster gate, and the four documents a reader is sent to.
#      An ignore file that is too eager takes the evidence with it, and that is
#      the failure this check exists to catch -- the one that looks like a
#      successful cleanup.
#   3. Every TRACKED file is in the package, except the six the toolchain
#      excludes by default (files and folders whose name starts with `.`).
#      So a rule cannot quietly eat a file that belongs to the project.
#
# WHY IT RUNS ON THE WORKING TREE AND NOT ON A CHECKOUT. `moon package` reads the
# working tree and does not consult git, so the two differ: MEASURED on this
# tree, the package carries 424 entries and 24 of them are UNTRACKED scratch
# that exists only because the tree is dirty. CI checks out clean, so those 24
# are not in the published package and never were. Check 3 is therefore written
# against the TRACKED set -- it is true of a clean checkout and of a dirty one
# alike, which is what makes it a gate rather than a snapshot.
#
# The 13 files that were tracked and are not any more (four `COMMIT_*.md` at
# the root, nine `_verify/commitmsg*.txt`) were removed from the index in the
# same commit that added the rules that exclude them. Nothing referenced them:
# MEASURED, `git grep` finds no mention of any of them.
#
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File _verify\check_package_contents.ps1
#
# There is no -SelfTest switch, and that is deliberate: this gate is shown to go
# red by INJECTING a defect into the tree and running it, which is a stronger
# statement than a switch that reproduces the checker's own logic.
$root = 'D:\src\DeepseekHarness\Projects\xiuyueren\StaticAnalysis\moonbit_static_analysis'
$moon = 'C:\Users\31379\.moon\bin\moon.exe'
$fail = 0

# --- the package, as the packager sees it -----------------------------------
$prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
$out = & $moon -C $root package --list --frozen 2>&1 | ForEach-Object { [string]$_ }
$ErrorActionPreference = $prev
if ($LASTEXITCODE -ne 0) {
  Write-Output ('  FAIL: `moon package --list` exited ' + $LASTEXITCODE)
  $out | Select-Object -Last 5 | ForEach-Object { Write-Output ('      ' + $_) }
  exit 1
}
$noise = '^(Running moon check|Finished\. moon:|Check passed|Package to )'
$pkg = @($out | Where-Object { $_ -notmatch $noise -and $_.Trim() -ne '' } | ForEach-Object { $_.Trim() } | Sort-Object -Unique)
Write-Output ('=== the package: ' + $pkg.Count + ' entries ===')

# --- 1. the junk classes are absent ------------------------------------------
Write-Output ''
Write-Output '=== 1. the junk classes are absent ==='
$junk = @(
  @{ N = 'scratch commit messages (root)';       R = '^COMMIT_.*\.md$' }
  @{ N = 'scratch commit messages (_verify)';    R = '^_verify\\commitmsg.*\.txt$' }
  @{ N = 'scan artifacts';                       R = '\.mmd$' }
  @{ N = 'the credential';                       R = '(^|\\)credentials\.json$' }
  @{ N = 'gate transcripts';                     R = '^_verify\\_gatelogs\\' }
  @{ N = 'the remeasure dumps';                  R = '^_verify\\remeasure_out\\' }
  @{ N = 'the un-committable source stub';       R = '^src\\lexer\\lexer_0488_test\.mbt$' }
  @{ N = 'the release-run working copies';       R = '^_verify\\release_.*\.txt$' }
  @{ N = 'the scratch probes and working copies'; R = '^_verify\\_' }
)
foreach ($j in $junk) {
  # `_verify\_split_release_narrative.ps1` is the ONE tracked file whose name
  # starts with `_`, and the .moonignore re-includes it on purpose -- so it is
  # not a hit for any of these rules. It is asserted separately, below.
  $hits = @($pkg | Where-Object { $_ -match $j.R -and $_ -ne '_verify\_split_release_narrative.ps1' })
  $ok = ($hits.Count -eq 0)
  if (-not $ok) { $fail++ }
  Write-Output ('  {0,-42} {1,4}  {2}' -f $j.N, $hits.Count, $(if ($ok) { 'OK' } else { 'FAIL' }))
  $hits | Select-Object -First 3 | ForEach-Object { Write-Output ('      ' + $_) }
}
$exempt = @($pkg | Where-Object { $_ -eq '_verify\_split_release_narrative.ps1' })
if ($exempt.Count -ne 1) {
  Write-Output '  FAIL: the re-inclusion of _verify\_split_release_narrative.ps1 did not survive.'
  $fail++
} else {
  Write-Output '  the one re-included underscore file IS present       OK'
}

# --- 2. the evidence is present ----------------------------------------------
Write-Output ''
Write-Output '=== 2. the evidence is present ==='
$gateCount = @(Get-ChildItem -LiteralPath (Join-Path $root '_verify') -Filter 'mutate_0*.ps1' -File).Count
$evidence = @(
  @{ N = 'numbered mutation gates';      Want = $gateCount;        R = '^_verify\\mutate_0\d\d\d\.ps1$' }
  @{ N = 'the shared harness';           Want = 1;                R = '^_verify\\mutate_lib\.ps1$' }
  @{ N = 'the settle scripts';           Want = -1;               R = '^_verify\\settle_.*\.ps1$' }
  @{ N = 'the narrative';                Want = 1;                R = '^_verify\\NARRATIVE\.md$' }
  @{ N = 'the roster gate';              Want = 1;                R = '^_verify\\check_gate_roster\.ps1$' }
  @{ N = 'the prove-contracts gate';     Want = 1;                R = '^_verify\\check_prove_contracts\.ps1$' }
  @{ N = 'the notice-labels gate';       Want = 1;                R = '^_verify\\check_notice_labels\.ps1$' }
  @{ N = 'the frame-audit gate';        Want = 1;                R = '^_verify\\check_frame_audit\.ps1$' }
  @{ N = 'the README';                   Want = 1;                R = '^README\.md$' }
  @{ N = 'the Chinese README';           Want = 1;                R = '^README\.zh\.md$' }
  @{ N = 'the skill file';               Want = 1;                R = '^SKILL\.md$' }
  @{ N = 'the extensions document';      Want = 1;                R = '^EXTENSIONS\.md$' }
  @{ N = 'the loop document';            Want = 1;                R = '^LOOP\.md$' }
  @{ N = 'the module manifest';          Want = 1;                R = '^moon\.mod$' }
  @{ N = 'the module source';            Want = 1;                R = '^main\.mbt$' }
  @{ N = 'the proof file';               Want = 1;                R = '^src\\core\\core_proof\.mbtp$' }
)
foreach ($e in $evidence) {
  $hits = @($pkg | Where-Object { $_ -match $e.R }).Count
  # PowerShell 5.1 has no ternary operator.
  if ($e.Want -lt 0) { $ok = ($hits -gt 0) } else { $ok = ($hits -eq $e.Want) }
  if (-not $ok) { $fail++ }
  Write-Output ('  {0,-42} {1,4}  {2}' -f $e.N, $hits, $(if ($ok) { 'OK' } else { 'FAIL (want ' + $e.Want + ')' }))
}

# --- 3. every tracked file is in the package ---------------------------------
Write-Output ''
Write-Output '=== 3. every tracked file is in the package ==='
$tracked = @(git -C $root ls-files | ForEach-Object { $_ -replace '/', '\' })
# The toolchain ignores, by default and not overridably, files and folders
# whose name starts with `.`. Those six are the only tracked files that are
# expected to be absent.
$defaultExcluded = @('.gitattributes', '.gitignore', '.moonignore',
  '.github\workflows\gate.yml', '.github\workflows\publish.yml',
  '.dsh\skills\moonbit-static-analysis\SKILL.md')
$missing = @($tracked | Where-Object { ($pkg -notcontains $_) -and ($defaultExcluded -notcontains $_) })
Write-Output ('  tracked files: ' + $tracked.Count + '   default-excluded: ' + $defaultExcluded.Count)
Write-Output ('  tracked but not in the package: ' + $missing.Count + $(if ($missing.Count -eq 0) { '   OK' } else { '   FAIL' }))
$missing | Select-Object -First 10 | ForEach-Object { Write-Output ('      ' + $_) }
if ($missing.Count -gt 0) { $fail++ }

Write-Output ''
if ($fail -eq 0) {
  Write-Output 'PACKAGE OK: the junk is out, the evidence is in, and every tracked file ships.'
  exit 0
}
Write-Output ('PACKAGE FAILED: ' + $fail + ' problem(s).')
exit 1
