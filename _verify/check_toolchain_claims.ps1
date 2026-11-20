param([switch]$SelfTest, [string]$Root = '')
$ErrorActionPreference = 'Continue'
# THE SHIPPED DOCUMENTS' CLAIMS ABOUT THE TOOLCHAIN, as a gate.
#
# WHY THIS EXISTS. The documents that tell a reader how to run this module SHIP,
# and two of them said:
#
#     `moon runwasm ...` is deprecated (the toolchain says removal after
#     2026-09-14) but still works. Prefer `moonx`.
#
# MEASURED 0624, and the claim is FALSE. The toolchain on this machine is
# `moon 0.1.20261117 (eb64713 2026-11-17)`, and the probe answers:
#
#     Error: no such subcommand: `runwasm`, is `moon-runwasm` a valid
#     executable accessible via your `PATH`?
#
# and there is no `moon-runwasm` binary in `~/.moon/bin` and none on PATH.
# `moonx.exe` IS there, so the RECOMMENDATION is right and the claim about the
# command is not: a reader who follows it gets "no such subcommand".
#
# AND THE CLAIM CARRIED ITS OWN EXPIRY DATE. The toolchain said "removal after
# 2026-09-14"; the claim was written on 2026-10-06 (`8a31e88`) -- a month AFTER
# that date -- and it was true then. Nothing re-measured it, and the removal
# happened without a line of this repository changing.
#
# => A DATED OLD NUMBER IS A RECORD; AN UNDATED ONE IS A DEFECT. This claim
# carried a date INSIDE it ("removal after 2026-09-14"), which is part of the
# claim and not a stamp saying when it was measured -- so it is a PRESENT-TENSE
# claim about a MOVING thing, and a present-tense claim about a moving thing
# has to be re-measured.
#
# WHAT IT CHECKS, in one sentence: the shipped documents must agree with the
# toolchain about the command they tell the reader about.
#
# THE TWO DOCUMENTS ARE NAMED, and the third copy is NOT among them. The third
# copy is in `EXTENSIONS.md`, inside the section dated `2026-10-06` -- a
# SNAPSHOT of what was checked against the toolchain's pages that day -- so it
# is a RECORD, and a record is left alone. The gate's scope is the two LIVE
# copies.
#
# THE PIN. `$RUNWASM_GONE_IN` in `_verify/release.ps1` is the toolchain version
# in which the subcommand was measured gone, and the documents carry THAT
# version -- so the claim is a versioned fact and not a floating one.
#
# THE MEASUREMENT. The gate asks the toolchain itself, with `moon runwasm
# --help`, which exits 0 when the subcommand exists and non-zero when it does
# not; the CLI answers "no such subcommand" before it reads anything, so the
# probe cannot build or run anything. If the local toolchain is the pinned one
# or NEWER, the measurement must agree with the documents. If the local
# toolchain is OLDER than the pin, the claim is about the pin and only the
# shape is checked -- the gate says so instead of failing on a toolchain the
# claim does not talk about.
#
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File _verify\check_toolchain_claims.ps1
#   powershell -NoProfile -ExecutionPolicy Bypass -File _verify\check_toolchain_claims.ps1 -SelfTest

$root = if ($Root) { $Root } else { Split-Path -Parent $PSScriptRoot }

# THE TWO LIVE COPIES. The third copy is in `EXTENSIONS.md`, in a section dated
# 2026-10-06, so it is a record and is left alone -- see the header.
$docs = @('SKILL.md', 'src\cli\SKILL.md')

# THE MOON EXECUTABLE. Looked up rather than written down, so the gate does not
# carry a machine-local path -- the same defect 0617 fixed in seven other
# gates.
function Get-MoonExe {
  $c = Get-Command 'moon.exe' -ErrorAction SilentlyContinue
  if ($null -ne $c) { return $c.Source }
  if ($env:MOON_HOME -ne '') {
    $p = Join-Path $env:MOON_HOME 'bin\moon.exe'
    if (Test-Path -LiteralPath $p) { return $p }
  }
  $p = Join-Path $env:USERPROFILE '.moon\bin\moon.exe'
  if (Test-Path -LiteralPath $p) { return $p }
  return ''
}

# THE PIN, read from the one place that carries it.
function Get-Pin {
  param([string]$RootPath)
  $rel = Join-Path $RootPath '_verify\release.ps1'
  if (-not (Test-Path -LiteralPath $rel)) { return '' }
  $txt = [System.IO.File]::ReadAllText($rel, [Text.Encoding]::UTF8)
  $m = [regex]::Match($txt, "\`$RUNWASM_GONE_IN\s*=\s*'([^']+)'")
  if (-not $m.Success) { return '' }
  return $m.Groups[1].Value
}

# THE MEASUREMENT.
function Get-Toolchain {
  param([string]$RootPath)
  $moon = Get-MoonExe
  if ($moon -eq '') { return $null }
  $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  $vout = & $moon version 2>&1 | Out-String
  $ver = ''
  $m = [regex]::Match($vout, '(\d+\.\d+\.\d{8})')
  if ($m.Success) { $ver = $m.Groups[1].Value }
  # THE PROBE. `moon runwasm --help` exits 0 when the subcommand exists and
  # non-zero when it does not. The answer comes before any project is read, so
  # the probe cannot build or run anything.
  $null = & $moon -C $RootPath runwasm --help 2>&1
  $code = $LASTEXITCODE
  $ErrorActionPreference = $prev
  return [pscustomobject]@{ Version = $ver; Exists = ($code -eq 0); Code = $code }
}

# THE VERSION ORDER. The toolchain's versions are `0.1.YYYYMMDD`, so the parts
# compare as numbers. A part that is not a number makes the comparison
# INCOMPARABLE, and an incomparable version is treated as "older", because a
# gate that guesses is worse than a gate that says it cannot tell.
function Compare-Version {
  param([string]$A, [string]$B)
  if ($A -eq '' -or $B -eq '') { return -1 }
  $pa = @($A -split '\.'); $pb = @($B -split '\.')
  $n = [Math]::Max($pa.Count, $pb.Count)
  for ($i = 0; $i -lt $n; $i++) {
    $x = '0'; $y = '0'
    if ($i -lt $pa.Count) { $x = $pa[$i] }
    if ($i -lt $pb.Count) { $y = $pb[$i] }
    if ($x -notmatch '^\d+$' -or $y -notmatch '^\d+$') { return -1 }
    if ([int]$x -lt [int]$y) { return -1 }
    if ([int]$x -gt [int]$y) { return 1 }
  }
  return 0
}

# THE DOCUMENT CHECK. It takes the TEXT, so the self-test can run it against a
# COPY in %TEMP% and leave this repository alone.
function Get-DocProblems {
  param([string]$Text, [string]$Pin)
  $bad = @()
  # THE DOCUMENT'S OWN FORMATTING IS NORMALISED AWAY, for the reason 5c of
  # `check_readme_links.ps1` gives: the pin is a bare version and the document
  # writes it in bold.
  $plain = $Text.Replace(',', '').Replace('**', '')
  if ($Pin -eq '') {
    $bad += 'the pin is missing, so there is nothing to check the document against'
  } else {
    # THE VERSION MUST BE IN THE CLAIM'S OWN BLOCK, and a document-wide search
    # for it is VACUOUS HERE. MEASURED: the corpus version
    # `0.1.20261117+06da1ed44` CONTAINS the toolchain version `0.1.20261117`,
    # and the root `SKILL.md` carries the corpus version -- so a document-wide
    # search passed a document whose CLAIM had no version in it at all, three
    # hundred lines away from the claim.
    #
    # A BLOCK is a run of lines with no blank line between them. The claim is
    # the block that mentions the command, and the version has to be in it.
    #
    # 0625. AND A BLOCKQUOTE'S PARAGRAPHS ARE NOT SEPARATED BY BLANK LINES --
    # they are separated by a line that holds nothing but the `>` marker. The
    # first version of this split did not know that, so the "block" of the
    # root `SKILL.md` was the WHOLE blockquote -- and when 0625 added the floor
    # note (which carries the pin) to that same blockquote, the check could no
    # longer see a stale version in the runwasm note: the pin was somewhere in
    # the block, and the block is not the claim. The self-test caught it: it
    # went from two defects caught to one.
    #
    # => THE CLAIM'S OWN PARAGRAPH, and not the block that happens to contain
    # it. The same lesson 0624 wrote down, one level down.
    $blocks = @($plain -split "(?:\r?\n){2,}|(?:\r?\n)[ \t]*>[ \t]*(?:\r?\n)")
    $claimBlocks = @($blocks | Where-Object { $_.Contains('moon runwasm') })
    if ($claimBlocks.Count -gt 0) {
      $withVersion = @($claimBlocks | Where-Object { $_.Contains($Pin) }).Count
      if ($withVersion -eq 0) {
        $bad += ('it does not carry the pinned toolchain version ' + $Pin + ' in the block that makes the claim')
      }
    }
  }
  # THE SHAPE. `still works` and the Chinese form are the two ways this claim
  # was written; both are banned, because both say that a command the toolchain
  # does not have is usable.
  foreach ($shape in @('still works', '\u76EE\u524D\u4ECD\u53EF\u7528')) {
    if ($plain -match $shape) { $bad += ('it claims the command still works (' + $shape + ')') }
  }
  # AND THE REPLACEMENT. A document that mentions the removed command has to
  # name the one that works.
  if ($plain.Contains('moon runwasm') -and -not $plain.Contains('moonx')) {
    $bad += 'it names the removed command but not the replacement'
  }
  return $bad
}

# --- the self-test ---------------------------------------------------------------
# THE DEFECT IS IN THE DOCUMENT, so the copy that has to go red is a COPY OF THE
# DOCUMENT. The control is the document as it stands, and it must be green: a
# self-test that only proves the gate can fail proves nothing about the gate.
if ($SelfTest) {
  Write-Output 'check the shipped documents against the toolchain -- SELF TEST'
  $bad = 0
  $checked = 0
  $pin = Get-Pin $root

  Write-Output ''
  Write-Output '--- the control: the documents as they stand ---'
  $ctlBad = 0
  foreach ($d in $docs) {
    $p = Join-Path $root $d
    if (-not (Test-Path -LiteralPath $p)) { $ctlBad++; continue }
    $probs = Get-DocProblems ([System.IO.File]::ReadAllText($p, [Text.Encoding]::UTF8)) $pin
    $ctlBad += $probs.Count
  }
  $checked++
  if ($ctlBad -eq 0) {
    Write-Output ('  OK: the control passes (' + $docs.Count + ' document(s), the pin is ' + $pin + ').')
  } else {
    Write-Output ('  FAIL: the control does NOT pass: ' + $ctlBad + ' problem(s).')
    $bad++
  }

  Write-Output ''
  Write-Output '--- the defect: the stale claim, put back into a COPY ---'
  $src = Join-Path $root 'SKILL.md'
  if (-not (Test-Path -LiteralPath $src)) {
    Write-Output '  FAIL: SKILL.md is not in the tree, so the defect could not be injected.'
    $bad++
  } else {
    $orig = [System.IO.File]::ReadAllText($src, [Text.Encoding]::UTF8)
    # THE MUTATION. Two defects, the way the real one had two: the version in
    # the CLAIM goes stale, and the shape that says the command works comes
    # back.
    #
    # MEASURED: the first version of this mutation replaced EVERY occurrence of
    # the pin in the document -- including the CORPUS version, which CONTAINS
    # it -- so it did not exercise the defect at all: the check it was supposed
    # to break passed, and the self-test said OK. The mutation has to touch the
    # CLAIM, so the claim's own copy is what goes stale.
    $mutated = $orig.Replace('`moon ' + $pin + '`', '`moon 0.1.20261004`')
    $lines = @($mutated -split "`r?`n")
    $idx = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
      if ($lines[$i].Contains('moon runwasm')) { $idx = $i; break }
    }
    if ($idx -lt 0) {
      Write-Output '  FAIL: no line of the document mentions the command, so the defect could not be injected.'
      $bad++
    } else {
      $lines[$idx] = $lines[$idx] + ' -- but still works'
      $mutated = ($lines -join "`r`n")
      $probs = Get-DocProblems $mutated $pin
      $checked++
      # THE MESSAGES ARE COMPARED AS LITERALS. A comparison that throws skips
      # the check and prints SELFTEST OK having checked nothing.
      $caught = 0
      try {
        if (($probs -join ' | ') -match 'does not carry the pinned toolchain version') { $caught++ }
        if (($probs -join ' | ') -match 'claims the command still works') { $caught++ }
      } catch {
        Write-Output ('  FAIL: the check itself threw: ' + $_.Exception.Message)
      }
      if ($caught -eq 2) {
        Write-Output ('  OK: the gate caught both defects (' + $probs.Count + ' problem(s) reported):')
        foreach ($pr in $probs) { Write-Output ('        ' + $pr) }
      } else {
        Write-Output ('  FAIL: the gate caught only ' + $caught + ' of the 2 defects.')
        foreach ($pr in $probs) { Write-Output ('        ' + $pr) }
        $bad++
      }
    }
  }

  # AND EVERY CHECK RAN. A self-test that silently skipped one of its own
  # checks is the same green light that measured nothing.
  if ($checked -ne 2) {
    Write-Output ('  FAIL: ' + $checked + ' of 2 checks ran.')
    $bad++
  }

  Write-Output ''
  if ($bad -eq 0) {
    Write-Output 'SELFTEST OK: the control passed, and a shipped document with the stale claim was caught.'
    exit 0
  }
  Write-Output ('SELFTEST FAILED: ' + $bad + ' of 2 checks did not hold.')
  exit 1
}

# --- the live check --------------------------------------------------------------
Write-Output '=== the toolchain claims: the shipped documents must agree with the toolchain ==='
$pin = Get-Pin $root
if ($pin -eq '') {
  Write-Output '  FAIL: release.ps1 no longer carries the $RUNWASM_GONE_IN pin, so there is nothing to check the documents against.'
  Write-Output '        Restore it, or this gate has nothing to check.'
  exit 1
}
Write-Output ('  the pinned toolchain: ' + $pin)
$tool = Get-Toolchain $root
if ($null -eq $tool) {
  Write-Output '  FAIL: no moon executable was found (PATH, MOON_HOME and ~/.moon/bin all failed).'
  Write-Output '        The toolchain cannot be asked, so the documents cannot be checked against it.'
  exit 1
}
Write-Output ('  the local toolchain: ' + $tool.Version + '   the `runwasm` subcommand: ' + $(if ($tool.Exists) { 'STILL THERE' } else { 'GONE' }))
$bad = 0
foreach ($d in $docs) {
  $p = Join-Path $root $d
  if (-not (Test-Path -LiteralPath $p)) {
    Write-Output ('  FAIL: ' + $d + ' is not in the tree, so nothing can check what it says.')
    $bad++
    continue
  }
  $txt = [System.IO.File]::ReadAllText($p, [Text.Encoding]::UTF8)
  $probs = Get-DocProblems $txt $pin
  if ($probs.Count -eq 0) {
    Write-Output ('  ' + $d.PadRight(20) + ' carries the pinned version and does not claim the command works  OK')
  } else {
    foreach ($pr in $probs) {
      Write-Output ('  FAIL: ' + $d + ' -- ' + $pr)
      $bad++
    }
  }
}
# AND THE MEASUREMENT MUST AGREE, WHEN THE LOCAL TOOLCHAIN IS THE PINNED ONE OR NEWER.
$cmp = Compare-Version $tool.Version $pin
if ($cmp -ge 0) {
  if ($tool.Exists) {
    Write-Output ('  FAIL: the documents say the subcommand is gone in ' + $pin + ', and the local toolchain ' + $tool.Version + ' STILL HAS IT.')
    $bad++
  } else {
    Write-Output ('  OK: the local toolchain (' + $tool.Version + ') agrees: the `runwasm` subcommand is gone.')
  }
} else {
  Write-Output ('  the local toolchain (' + $tool.Version + ') is OLDER than the pin (' + $pin + '), so the claim is about the pin and only the shape was checked.')
}
if ($bad -eq 0) {
  Write-Output 'TOOLCHAIN CLAIMS OK: the shipped documents carry the pinned toolchain version, they do not claim the removed command works, and the toolchain agrees.'
  exit 0
}
Write-Output ('TOOLCHAIN CLAIMS FAILED: ' + $bad + ' problem(s).')
exit 1
