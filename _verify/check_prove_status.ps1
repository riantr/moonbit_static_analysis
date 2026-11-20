param([switch]$SelfTest, [string]$Root = '')
$ErrorActionPreference = 'Continue'
# THE PROOF LANE'S STORY MUST BE THE ONE THE PROVER TELLS.
#
# WHY THIS FILE EXISTS. `moon prove src/core` does not run green today. That is
# known, and it is REPORTED rather than hidden -- `_verify/check_prove_contracts.ps1`
# runs the prover and prints the symbols it cannot resolve. But the CAUSE the
# repository publishes for that failure was WRONG, and it was wrong in FOUR
# places at once: `README.md`, `README.zh.md`, `.dsh/skills/.../SKILL.md`, and
# the header of the very gate that measures the failure.
#
# WHAT THEY SAID: the toolchain's proof prelude has no `Map` theory, so the
# generated Why3 file declares `map int bool` and neither `moon prove` nor
# `why3` can load it; the fix is to move `IfaceSymTab` out of the proof
# subject, which changes the package's public API and is therefore a
# version-line decision rather than a patch.
#
# MEASURED (0627), on the toolchain of 2026-11-20 (core 0.10.21+06da1ed44):
#
#   1. `moon prove src/core` fails with `unbound type symbol 'array'` -- NOT
#      `'map'`. The README named the SECOND error in the queue.
#   2. The failure needs no `.why3.conf`: `moon prove src/core` on its own
#      fails the same way, so the proof lane is measurable OFFLINE, in CI,
#      without the local why3 shim (which is gitignored and never ships).
#   3. `why3` itself, run directly on the generated file, reports the same
#      error -- so this is a Why3 typing error, not a `moon` artifact.
#   4. THE FILE DECLARES BOTH TYPES ITSELF: `type array 'a1` at line 136 and
#      `type map 'a1  'a2` at line 138. The prelude is not missing anything;
#      the file carries its own declarations.
#   5. THE CAUSE IS THE ORDER. Why3 requires a type to be declared before it
#      is used, and the toolchain's lowering emits those two declarations
#      AFTER the records that use them (`IfaceSig` at line 20, `IfaceSymTab`
#      at line 27). Hoisting ONLY the `array` declaration moves the error
#      forward -- it becomes `unbound type symbol 'map'` at line 28 -- and
#      hoisting BOTH makes `why3` load the file, generate 21 VCs, and exit 0.
#   6. And the goals discharge: of those 21 VCs, cvc5 answers `unsat` for 20
#      and `unknown (incomplete)` for `severity_taxonomy_holds`.
#
# => So the published cause was refuted, and so was the advice it carried. The
# lemmas are NOT blocked by this package's source; they are blocked by the
# order two declarations are emitted in. Nobody has to break the public API of
# `src/core` to find that out.
#
# WHAT THIS GATE DOES. It RUNS the prover (so the fact is measured, not
# quoted), it DERIVES the cause from the generated file itself (it does not
# take the cause on trust from a document), and then it HOLDS the documents to
# the measurement:
#
#   - every document must name the symbol the prover reports TODAY;
#   - every document must say that the command does not run green today;
#   - every document must state the cause that was measured;
#   - no document may carry the cause that was refuted;
#   - and the workspace skill may not list the failing command among the
#     commands to RUN.
#
# THE DIRECTION MATTERS. If a future toolchain makes `moon prove src/core`
# go green, the documents must stop claiming that it fails -- so the same
# check is run in both directions, and the "it passes now" branch is exercised
# on the check, with the measurement flipped.
#
# The self-test injects the defect into a COPY OF THE DOCUMENTS (the defect is
# in prose, so the copy that has to go red is a copy of the prose), and
# requires the control -- the documents as they stand -- to stay green.
#
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File _verify\check_prove_status.ps1
#   powershell -NoProfile -ExecutionPolicy Bypass -File _verify\check_prove_status.ps1 -SelfTest

$root = if ($Root) { $Root } else { Split-Path -Parent $PSScriptRoot }
$moon = 'C:\Users\31379\.moon\bin\moon.exe'
$fail = 0

# THE PHRASES THE DOCUMENTS MUST CARRY. The English one is what the three
# English documents say; the Chinese one is what the Chinese twin says. They
# are written here as \u escapes so that THIS FILE STAYS ASCII: a BOM-less
# .ps1 with non-ASCII in it is read as ANSI by PowerShell 5.1, and the phrase
# would silently become mojibake.
$CAUSE_EN = 'declared after its first use'
$CAUSE_ZH_RX = '\u5148\u4F7F\u7528\u3001\u540E\u58F0\u660E'
$CLAIMS_EN = 'does not run green today'
$CLAIMS_ZH_RX = '\u4ECA\u5929\u8DD1\u4E0D\u7EFF'

# THE CAUSE THAT WAS REFUTED, named VERBATIM, so it cannot come back in
# another wording of the same false claim. The Chinese one is an escape for
# the same reason as above.
$REFUTED = @(
  'no `Map` theory',
  'the proof prelude has no theory for',
  "the toolchain's proof prelude defines neither",
  'the symbols the proof prelude does not define',
  'missing prelude theories',
  'the prelude defines neither',
  '\u6CA1\u6709 `Map` \u7406\u8BBA'
)

# THE DOCUMENTS. `Need` says whether the document has to carry the MEASURED
# failure and the CLAIM that the command fails. The sibling gate is not a
# document about the failure -- it PRINTS the failure -- so it is held to the
# cause and to the absence of the refuted one, and no more.
$docs = @(
  @{ N = 'README.md'; Lang = 'en'; Need = $true }
  @{ N = 'README.zh.md'; Lang = 'zh'; Need = $true }
  @{ N = '.dsh/skills/moonbit-static-analysis/SKILL.md'; Lang = 'en'; Need = $true }
  @{ N = '_verify/check_prove_contracts.ps1'; Lang = 'en'; Need = $false }
)

# ONE PROVE RUN, and everything it is asked about. Every number this gate
# prints comes out of here, so there is ONE place the fact is measured.
function Get-ProveRun([string]$Root) {
  $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  $out = & $moon -C $Root prove src/core --frozen 2>&1 | Out-String
  $code = $LASTEXITCODE
  $ErrorActionPreference = $prev
  $unbound = @()
  foreach ($m in [regex]::Matches($out, "unbound type symbol '([A-Za-z_][A-Za-z0-9_]*)'")) {
    $n = $m.Groups[1].Value
    if ($unbound -notcontains $n) { $unbound += $n }
  }
  $mlw = @(Get-ChildItem -Path (Join-Path $Root '_build\verif\src\core\*.mlw') -ErrorAction SilentlyContinue)
  $mlwText = ''
  if ($mlw.Count -gt 0) { $mlwText = [System.IO.File]::ReadAllText($mlw[0].FullName, [Text.Encoding]::UTF8) }
  return [pscustomobject]@{
    Code = $code
    Out = $out
    Unbound = $unbound
    MlwPath = $(if ($mlw.Count -gt 0) { $mlw[0].FullName } else { '' })
    MlwText = $mlwText
  }
}

# THE CAUSE, DERIVED FROM THE GENERATED FILE. For every type the file
# declares, where is it USED for the first time? A use that comes BEFORE the
# declaration is the thing Why3 cannot resolve -- and why3 stops at the FIRST
# such symbol, so the first one in file order is the one it reports.
function Get-UseBeforeDeclare([string]$Mlw) {
  $out = @()
  if ([string]::IsNullOrWhiteSpace($Mlw)) { return $out }
  $lines = @($Mlw -split "`r?`n")
  $decl = @{}
  for ($i = 0; $i -lt $lines.Count; $i++) {
    $m = [regex]::Match($lines[$i], '^\s*type\s+([A-Za-z_][A-Za-z0-9_]*)')
    if ($m.Success -and -not $decl.ContainsKey($m.Groups[1].Value)) { $decl[$m.Groups[1].Value] = ($i + 1) }
  }
  foreach ($sym in $decl.Keys) {
    $rx = '(?<![A-Za-z0-9_])' + [regex]::Escape($sym) + '(?![A-Za-z0-9_])'
    $first = 0
    for ($i = 0; $i -lt $lines.Count; $i++) {
      if (($i + 1) -eq $decl[$sym]) { continue }
      if ($lines[$i].Trim().StartsWith('(*')) { continue }
      if ([regex]::IsMatch($lines[$i], $rx)) { $first = ($i + 1); break }
    }
    if ($first -gt 0 -and $first -lt $decl[$sym]) {
      $out += [pscustomobject]@{ Symbol = $sym; UseLine = $first; DeclLine = $decl[$sym] }
    }
  }
  return @($out | Sort-Object UseLine)
}

# THE COMMANDS THE WORKSPACE SKILL ASKS THE READER TO RUN. A command that
# fails today may not sit in the list of commands to run, next to four that
# pass, with nothing said about it.
function Get-ListedCommands([string]$Text) {
  $cmds = @()
  if ([string]::IsNullOrWhiteSpace($Text)) { return $cmds }
  $lines = @($Text -split "`r?`n")
  $inSection = $false
  $inFence = $false
  for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match '^##\s+Commands') { $inSection = $true; continue }
    if ($inSection -and $lines[$i] -match '^##\s+') { break }
    if ($inSection -and $lines[$i] -match '^\s*```') { $inFence = -not $inFence; continue }
    if ($inSection -and $inFence -and $lines[$i] -match '^\s*(moon|moonc|git|node)\b') {
      $cmds += $lines[$i].Trim()
    }
  }
  return $cmds
}

# WHAT IS WRONG WITH THE DOCUMENTS, given the measurement. The texts and the
# names are passed in, so the self-test can hand it a COPY with one thing
# changed and see whether it notices.
function Get-DocumentProblems {
  param([string[]]$Texts, [string[]]$Names, [string]$First, [bool]$Proved)
  $probs = @()
  for ($i = 0; $i -lt $docs.Count; $i++) {
    $d = $docs[$i]
    $name = $d.N
    if ($i -ge $Texts.Count) { continue }
    $text = $Texts[$i]
    if ([string]::IsNullOrWhiteSpace($text)) { continue }

    # THE REFUTED CAUSE MUST NOT COME BACK, in any of the four copies.
    foreach ($p in $REFUTED) {
      if ([regex]::IsMatch($text, $p)) {
        $probs += ('FAIL: ' + $name + ' carries the refuted cause: ' + $p)
      }
    }

    # THE CAUSE THAT WAS MEASURED MUST BE THERE.
    $causeRx = if ($d.Lang -eq 'zh') { $CAUSE_ZH_RX } else { [regex]::Escape($CAUSE_EN) }
    if (-not [regex]::IsMatch($text, $causeRx)) {
      $probs += ('FAIL: ' + $name + ' does not carry the measured cause (' + $CAUSE_EN + ')')
    }

    if (-not $d.Need) { continue }

    if (-not $Proved) {
      # THE MEASURED FAILURE, named with the symbol the prover reports TODAY.
      if ($First -ne '') {
        $tok = "unbound type symbol '" + $First + "'"
        if (-not $text.Contains($tok)) {
          $probs += ('FAIL: ' + $name + ' does not carry the measured failure: ' + $tok)
        }
      }
      # AND THE CLAIM THAT IT FAILS, so the reader is not left guessing.
      $claimRx = if ($d.Lang -eq 'zh') { $CLAIMS_ZH_RX } else { [regex]::Escape($CLAIMS_EN) }
      if (-not [regex]::IsMatch($text, $claimRx)) {
        $probs += ('FAIL: ' + $name + ' does not say that the command does not run green today')
      }
    } else {
      # THE OTHER DIRECTION. The prover passed, so nothing may claim it fails.
      if ($text.Contains("unbound type symbol '")) {
        $probs += ('FAIL: ' + $name + ' claims the proof fails, but the prover proved it')
      }
      $claimRx = if ($d.Lang -eq 'zh') { $CLAIMS_ZH_RX } else { [regex]::Escape($CLAIMS_EN) }
      if ([regex]::IsMatch($text, $claimRx)) {
        $probs += ('FAIL: ' + $name + ' claims the command does not run green today, but the prover proved it')
      }
    }

    # AND THE WORKSPACE SKILL MAY NOT LIST THE FAILING COMMAND AMONG THE
    # COMMANDS TO RUN.
    if ($name -like '*.dsh*') {
      foreach ($c in @(Get-ListedCommands $text)) {
        if ($c -match '^moon\s+prove\b' -and -not $Proved) {
          $probs += ('FAIL: ' + $name + ' lists a command that fails today as a command to run: ' + $c)
        }
      }
    }
  }
  return $probs
}

# ------------------------------------------------------------------- the self-test ---
# THE DEFECT IS IN THE DOCUMENTS, so the copy that has to go red is a COPY OF
# THE DOCUMENTS. The control is the documents as they stand, and it must be
# green: a self-test that only proves the gate can fail proves nothing.
if ($SelfTest) {
  Write-Output 'check the proof status -- SELF TEST'
  $bad = 0
  $checked = 0

  $run = Get-ProveRun $root
  $first = if ($run.Unbound.Count -gt 0) { $run.Unbound[0] } else { '' }
  Write-Output ('  the prover exits ' + $run.Code + ' and reports: ' + $(if ($run.Unbound.Count -gt 0) { $run.Unbound -join ', ' } else { 'nothing' }))

  $names = @()
  $texts = @()
  foreach ($d in $docs) {
    $names += $d.N
    $p = Join-Path $root ($d.N -replace '/', '\')
    if (Test-Path -LiteralPath $p) {
      $texts += [System.IO.File]::ReadAllText($p, [Text.Encoding]::UTF8)
    } else {
      $texts += ''
    }
  }

  Write-Output ''
  Write-Output '--- the control: the documents as they stand ---'
  $ctl = @(Get-DocumentProblems $texts $names $first ($run.Code -eq 0))
  $checked++
  if ($ctl.Count -eq 0) {
    Write-Output ('  OK: the control passes (the prover reports ' + $first + ').')
  } else {
    Write-Output ('  FAIL: the control does NOT pass: ' + $ctl.Count + ' problem(s).')
    foreach ($x in $ctl) { Write-Output ('        ' + $x) }
    $bad++
  }

  # THE FAULTS. Each one takes a COPY of the documents and changes exactly one
  # thing, and the gate has to go red with the RIGHT message.
  $faults = @(
    [pscustomobject]@{
      N = 'the README names a symbol the prover does not report'
      Expect = 'does not carry the measured failure'
      Apply = {
        param($t, $n, $f)
        $out = @()
        for ($i = 0; $i -lt $t.Count; $i++) {
          $s = $t[$i]
          if ($n[$i] -eq 'README.md') {
            $s = $s.Replace("unbound type symbol '" + $f + "'", "unbound type symbol 'stale_symbol'")
          }
          $out += $s
        }
        return ,$out
      }
    }
    [pscustomobject]@{
      N = 'the README carries the refuted cause again'
      Expect = 'carries the refuted cause'
      Apply = {
        param($t, $n, $f)
        $out = @()
        for ($i = 0; $i -lt $t.Count; $i++) {
          $s = $t[$i]
          if ($n[$i] -eq 'README.md') {
            $s = $s.Replace($CAUSE_EN, 'the proof prelude has no theory for')
          }
          $out += $s
        }
        return ,$out
      }
    }
    [pscustomobject]@{
      N = 'the workspace skill lists the failing command among the commands to run'
      Expect = 'lists a command that fails today'
      Apply = {
        param($t, $n, $f)
        $out = @()
        $cmd = 'moon prove src/core --why3-config .why3.conf   # formal verification'
        for ($i = 0; $i -lt $t.Count; $i++) {
          $s = $t[$i]
          if ($n[$i] -like '*.dsh*') {
            # THE COMMAND GOES INSIDE THE FIRST FENCED BLOCK -- after the line
            # that OPENS it, which carries a language tag (` ```console `), so a
            # plain fence match would land after the block instead.
            $s = [regex]::Replace($s, '(?m)^(```[^\r\n]*\r?\n)', '$1' + $cmd + "`n", 1)
          }
          $out += $s
        }
        return ,$out
      }
    }
    [pscustomobject]@{
      N = 'the Chinese README does not carry the cause'
      Expect = 'does not carry the measured cause'
      Apply = {
        param($t, $n, $f)
        $out = @()
        for ($i = 0; $i -lt $t.Count; $i++) {
          $s = $t[$i]
          if ($n[$i] -eq 'README.zh.md') {
            $s = [regex]::Replace($s, $CAUSE_ZH_RX, 'the cause is not stated here')
          }
          $out += $s
        }
        return ,$out
      }
    }
    [pscustomobject]@{
      N = 'the sibling gate carries the refuted cause again'
      Expect = 'carries the refuted cause'
      Apply = {
        param($t, $n, $f)
        $out = @()
        for ($i = 0; $i -lt $t.Count; $i++) {
          $s = $t[$i]
          if ($n[$i] -like '*check_prove_contracts.ps1') {
            $s = $s.Replace($CAUSE_EN, 'the proof prelude has no theory for')
          }
          $out += $s
        }
        return ,$out
      }
    }
  )

  foreach ($f in $faults) {
    Write-Output ''
    Write-Output ('--- the defect: ' + $f.N + ' ---')
    $mutated = & $f.Apply $texts $names $first
    if ($null -eq $mutated -or @($mutated).Count -ne $texts.Count) {
      Write-Output '  FAIL: the mutation did not produce a copy of the documents.'
      $bad++
      continue
    }
    $probs = @(Get-DocumentProblems $mutated $names $first ($run.Code -eq 0))
    $checked++
    $caught = 0
    try {
      if (($probs -join ' | ') -match [regex]::Escape($f.Expect)) { $caught++ }
    } catch {
      Write-Output ('  FAIL: the check itself threw: ' + $_.Exception.Message)
    }
    if ($caught -eq 1) {
      Write-Output ('  OK: the gate caught it: ' + ($probs | Where-Object { $_ -match [regex]::Escape($f.Expect) } | Select-Object -First 1))
    } else {
      Write-Output ('  FAIL: the gate did NOT catch it (expected "' + $f.Expect + '").')
      foreach ($pr in $probs) { Write-Output ('        ' + $pr) }
      $bad++
    }
  }

  # AND THE OTHER DIRECTION: the prover passed, so nothing may claim it fails.
  # This branch cannot be reached from the tree as it stands -- the prover
  # fails -- so it is exercised on the CHECK, with the measurement flipped. A
  # gate that only knows how to fail in one direction does not know the other
  # direction.
  Write-Output ''
  Write-Output '--- the defect: the documents claim a failure, and the prover PASSED ---'
  $otherProbs = @(Get-DocumentProblems $texts $names $first $true)
  $checked++
  if (($otherProbs -join ' | ') -match 'but the prover proved it') {
    Write-Output ('  OK: the gate caught it: ' + ($otherProbs | Select-Object -First 1))
  } else {
    Write-Output '  FAIL: the gate did NOT catch a stale failure claim.'
    foreach ($pr in $otherProbs) { Write-Output ('        ' + $pr) }
    $bad++
  }

  if ($checked -ne 7) {
    Write-Output ('  FAIL: ' + $checked + ' of 7 checks ran.')
    $bad++
  }

  Write-Output ''
  if ($bad -eq 0) {
    Write-Output ('SELFTEST OK: the control passed, and ' + $faults.Count + ' injected defects were caught.')
    exit 0
  }
  Write-Output ('SELFTEST FAILED: ' + $bad + ' problem(s).')
  exit 1
}

# ------------------------------------------------------------------ the live check ---
Write-Output '=== the proof status: the documents must say what the prover says ==='
if (-not (Test-Path -LiteralPath $moon)) {
  Write-Output ('ABORT: no ' + $moon)
  exit 1
}

$run = Get-ProveRun $root
$first = if ($run.Unbound.Count -gt 0) { $run.Unbound[0] } else { '' }
Write-Output ('  the prover exits: ' + $run.Code)
Write-Output ('  the symbols it cannot resolve: ' + $(if ($run.Unbound.Count -gt 0) { $run.Unbound -join ', ' } else { 'none' }))
Write-Output ('  the generated file: ' + $(if ($run.MlwPath -ne '') { $run.MlwPath } else { 'none' }))

$order = @(Get-UseBeforeDeclare $run.MlwText)
if ($order.Count -gt 0) {
  foreach ($o in $order) {
    Write-Output ('  used before it is declared: ' + $o.Symbol + ' -- used at line ' + $o.UseLine + ', declared at line ' + $o.DeclLine)
  }
} else {
  Write-Output '  used before it is declared: none'
}

# THE MEASUREMENT HAS TO MATCH THE DIAGNOSIS. If the prover reports a symbol
# that the generated file does not use before declaring it, then the cause is
# something else, and the documents -- which now name this cause -- would be
# wrong in a new way.
if ($run.Code -ne 0 -and $first -eq '') {
  Write-Output ''
  Write-Output 'FAIL: the proof run failed and the gate cannot tell which symbol the prover'
  Write-Output '      stopped on, so it cannot hold the documents to a measured failure.'
  Write-Output '      This is not a document problem; the proof lane failed in a way this gate'
  Write-Output '      does not model, and it has to be read by a human.'
  ($run.Out -split "`r?`n" | Where-Object { $_.Trim() } | Select-Object -First 10) |
    ForEach-Object { Write-Output ('        | ' + $_.Trim()) }
  exit 1
}
if ($first -ne '' -and $order.Count -gt 0 -and $order[0].Symbol -ne $first) {
  Write-Output ''
  Write-Output ('FAIL: the prover stops on ''' + $first + ''' but the first type the generated file')
  Write-Output ('      uses before declaring it is ''' + $order[0].Symbol + '''. The cause the documents')
  Write-Output '      state is therefore not the one that was measured, and it has to be re-measured.'
  $fail++
}

$names = @()
$texts = @()
$inCheckout = Test-Path -LiteralPath (Join-Path $root '.git')
foreach ($d in $docs) {
  $names += $d.N
  $p = Join-Path $root ($d.N -replace '/', '\')
  if (Test-Path -LiteralPath $p) {
    $texts += [System.IO.File]::ReadAllText($p, [Text.Encoding]::UTF8)
  } else {
    $texts += ''
    if ($d.N -like '*.dsh*') {
      if ($inCheckout) {
        Write-Output ''
        Write-Output ('FAIL: ' + $d.N + ' is not in the tree, so nothing can check what it says.')
        $fail++
      } else {
        Write-Output ('  SKIP: ' + $d.N + ' is not in this tree -- a published package does not carry a dot-prefixed folder -- so it is not checked here.')
      }
    }
  }
}

$probs = @(Get-DocumentProblems $texts $names $first ($run.Code -eq 0))
foreach ($p in $probs) {
  Write-Output ''
  Write-Output $p
}
$fail += $probs.Count

Write-Output ''
if ($fail -eq 0) {
  Write-Output ('PROVE STATUS OK: the documents name the failure the prover reports today (' + $first + '),')
  Write-Output 'and the cause they state is the one the generated file shows.'
  exit 0
}
Write-Output ('PROVE STATUS FAILED: ' + $fail + ' problem(s).')
exit 1
