param([switch]$SelfTest, [string]$Root = '')
$ErrorActionPreference = 'Continue'
# THE RELEASED ARTIFACT AND THE PUBLISHED DOCUMENTS DESCRIBE DIFFERENT ANALYZERS,
# AND NOTHING MEASURED THE GAP.
#
# WHY THIS EXISTS. The published tool and the published documents are two things
# a reader gets, and they are supposed to agree. This repository publishes a set
# of MEASUREMENTS of its own tree -- 280 files, 2128 notices, 5611 call sites,
# 1344 native surface, and above all "this tree has no actionable finding" --
# and it tells the reader to run the tool through `moonx
# riantr/moonbit_static_analysis@latest`. The `@latest` resolves to the RELEASED
# artifact. The measurements come from THIS TREE'S BUILD.
#
# MEASURED 0626, on this tree at 0625's HEAD:
#
#     the RELEASED 0.5.0   files=280 notices=2128 unchecked=4589
#                          calls sites=5611 checked=1122 not-verified=4489
#                          native-surface modelled=1344
#                          actionable=19      <-- every one MSA-012 StaleNosec
#
#     THIS TREE'S BUILD   files=280 notices=2128 unchecked=4589
#                          calls sites=5611 checked=1122 not-verified=4489
#                          native-surface modelled=1344
#                          actionable=0
#
# EVERY NUMBER AGREES EXCEPT THE ONE THE DOCUMENTATION IS PROUDEST OF. And the
# reason is not a mystery: the released artifact was cut at the tag `v0.5.0`
# (`e11da29`), and the FIRST commit that touched `src/` after that tag is
# `267ff05` -- increment 0613, "THE ANALYZER READ ITS OWN DOCUMENTATION AS
# TWELVE SUPPRESSIONS". `moon.mod` still says `version = "0.5.0"`, so the
# released version no longer names the released source: `src/` has moved 25
# files and 1838 lines under a version that is already on the registry.
#
# AND THE DOCUMENTATION SAYS SO, IN WORDS, WITHOUT KNOWING IT. README.md's own
# nosec section publishes "the analyzer BEFORE these two rules reported
# NINETEEN stale suppressions ... and the tree with the two rules reports
# ZERO". The released artifact IS the "before" analyzer. A reader who downloads
# the tool the README names gets exactly the pre-fix behaviour the README
# describes as fixed.
#
# WHY NOBODY NOTICED. The false-positive pin (`check_own_tree_clean.ps1`)
# measures the LOCAL build, so it is right about the tree and silent about the
# release. `publish.yml` checks that `moon.mod` agrees with the TAG, so it
# cannot publish a second 0.5.0 -- but nothing compared the published CLAIM with
# the published ARTIFACT. The two can disagree by construction, and the only
# thing that noticed was a reader.
#
# WHAT IT CHECKS. One invariant, and it is about the VERSION:
#
#   The version in `moon.mod` must still describe the source it names.
#
# The anchor is the commit that SET that version -- `git log -S'version = "V"'
# -- which is the release commit, because the version is bumped at release time.
# If `src/` has moved after that anchor, then the released artifact is an OLDER
# BUILD than this tree, and the documents MUST SAY SO. If `src/` has NOT moved,
# the sentence must be GONE, because a statement that says the release is stale
# when it is not is a lie in the other direction.
#
# THE SENTENCE IS KEYED TO THE VERSION AND NOT TO A COUNT, and that is what
# makes the gate stable: the version changes only at release time, so between
# releases the condition "the source moved under the version" is constant-true
# and the sentence stays; at the next release the anchor moves with the version,
# the sentence has to be rewritten, and once the release catches up it has to be
# removed. A gate that counted the moved lines would go red on every commit.
#
# IT IS OFFLINE. No registry, no network, no compiler, no corpus -- it reads
# `moon.mod` and asks git two questions.
#
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File _verify\check_release_freshness.ps1
#   powershell -NoProfile -ExecutionPolicy Bypass -File _verify\check_release_freshness.ps1 -SelfTest
$root = if ($Root) { $Root } else { Split-Path -Parent $PSScriptRoot }
$fail = 0

# THE MARKERS. Each document carries the sentence in its own language, and the
# gate looks for its own marker in each of them -- so a sentence that is only
# added to one of the two READMEs is caught.
#
# The Chinese marker is written with \u escapes, because a BOM-less .ps1 with
# non-ASCII in it is read as ANSI by PowerShell 5.1.
$markers = @(
  @{ F = 'README.md';    M = 'the released artifact is older than this tree' }
  @{ F = 'README.zh.md'; M = '\u5DF2\u53D1\u5E03\u7684\u4EA7\u7269\u6BD4\u8FD9\u68F5\u6811\u65E7' }
)

# ------------------------------------------------------------------- the version ---
function Get-ModuleVersion {
  param([string]$RootPath)
  $p = Join-Path $RootPath 'moon.mod'
  if (-not (Test-Path -LiteralPath $p)) { return '' }
  $t = [System.IO.File]::ReadAllText($p, [Text.Encoding]::UTF8)
  $m = [regex]::Match($t, '(?m)^\s*version\s*=\s*"([^"]+)"')
  if (-not $m.Success) { return '' }
  return $m.Groups[1].Value
}

# --------------------------------------------------------------------- the anchor ---
# THE COMMIT THAT SET THE VERSION.
#
# THE PICKAXE IS ON THE VERSION TOKEN AND NOT ON THE WHOLE LINE, because a
# native command argument that carries DOUBLE QUOTES loses them on the way out
# of PowerShell. MEASURED 0626: `git log -S'version = "0.5.0"'` matches
# NOTHING, and the same command with `-S0.5.0` matches the release commit --
# so an anchor search written the obvious way reads the history as empty and
# reports a version that has no history at all.
#
# AND THE CANDIDATE IS VERIFIED, not trusted: the commit has to BE the one that
# set the version, so its own `moon.mod` must carry the version and its PARENT's
# must not. The pickaxe alone is not enough -- the version token can appear
# anywhere in the file, including in a comment.
function Get-VersionAt {
  param([string]$RootPath, [string]$Rev)
  $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  $out = & git -C $RootPath show ($Rev + ':moon.mod') 2>$null | Out-String
  $ErrorActionPreference = $prev
  $m = [regex]::Match($out, '(?m)^\s*version\s*=\s*"([^"]+)"')
  if (-not $m.Success) { return '' }
  return $m.Groups[1].Value
}

function Get-VersionAnchor {
  param([string]$RootPath, [string]$Version)
  if ($Version -eq '') { return '' }
  $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  $out = & git -C $RootPath log ('-S' + $Version) '--format=%H' -- moon.mod 2>&1 | Out-String
  $ErrorActionPreference = $prev
  $cands = @($out -split "`r?`n" | Where-Object { $_.Trim() -match '^[0-9a-f]{40}$' })
  foreach ($c in $cands) {
    $c = $c.Trim()
    if ((Get-VersionAt $RootPath $c) -ne $Version) { continue }
    $parent = Get-VersionAt $RootPath ($c + '^')
    if ($parent -ne $Version) { return $c }
  }
  return ''
}

# -------------------------------------------------------------- has the source moved ---
function Test-SourceMoved {
  param([string]$RootPath, [string]$Anchor)
  if ($Anchor -eq '') { return $null }
  $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  $out = & git -C $RootPath diff --name-only ($Anchor + '..HEAD') -- src/ 2>&1 | Out-String
  $ErrorActionPreference = $prev
  $lines = @($out -split "`r?`n" | Where-Object { $_.Trim() -ne '' })
  return ($lines.Count -gt 0)
}

# ------------------------------------------------------------- the sentence itself ---
# THE SENTENCE'S OWN PARAGRAPH, and not the document. 0625's lesson, one level
# down: a container is not a claim. The paragraph is found by the marker, and
# the version has to be in THAT paragraph -- and as an exact token, because a
# version is a prefix of other versions and a document-wide search for it is
# vacuous (that is the `0.1.20261117` inside `0.1.20261117+06da1ed44` trap).
function Get-StatementProblems {
  param([string[]]$Texts, [string[]]$Names, [string]$Version, [bool]$Moved)
  $bad = @()
  for ($i = 0; $i -lt $Names.Count; $i++) {
    $name = $Names[$i]
    $text = $Texts[$i]
    $marker = $markers[$i].M
    $para = $null
    foreach ($q in [regex]::Split($text, '(?:\r?\n)[ \t]*(?:\r?\n)+')) {
      if ($q -imatch $marker) { $para = $q; break }
    }
    if (-not $Moved) {
      # THE SOURCE HAS NOT MOVED. The sentence would be a lie in the other
      # direction, so it has to be gone.
      if ($null -ne $para) {
        $bad += ($name + ' carries the statement that the released artifact is older than this tree, but the source has NOT moved under version ' + $Version + ' -- the statement is stale')
      }
      continue
    }
    if ($null -eq $para) {
      $bad += ($name + ' does not carry the statement that the released artifact is older than this tree, but the source HAS moved under version ' + $Version)
      continue
    }
    $plain = $para.Replace('**', '').Replace('`', '')
    $tokens = @([regex]::Matches($plain, '(?<![\w.])\d+\.\d+\.\d+(?![\w])') | ForEach-Object { $_.Value })
    if ($tokens -notcontains $Version) {
      $bad += ($name + ' carries the statement, but its own paragraph does not name version ' + $Version + ' (it names: ' + $(if ($tokens.Count -eq 0) { 'no version at all' } else { ($tokens -join ', ') }) + ')')
    }
  }
  return $bad
}

# ------------------------------------------------------------------- the self-test ---
# THE DEFECT IS IN THE DOCUMENTS, so the copy that has to go red is a COPY OF
# THE DOCUMENTS. The control is the documents as they stand, and it must be
# green: a self-test that only proves the gate can fail proves nothing about the
# gate.
if ($SelfTest) {
  Write-Output 'check the release freshness -- SELF TEST'
  $bad = 0
  $checked = 0

  $version = Get-ModuleVersion $root
  $anchor = Get-VersionAnchor $root $version
  $moved = Test-SourceMoved $root $anchor
  Write-Output ('  the module version: ' + $version + '   the anchor: ' + $anchor + '   the source moved: ' + $moved)

  $names = @()
  $texts = @()
  foreach ($mk in $markers) {
    $names += $mk.F
    $p = Join-Path $root $mk.F
    if (-not (Test-Path -LiteralPath $p)) { $names += ''; $texts += ''; continue }
    $texts += [System.IO.File]::ReadAllText($p, [Text.Encoding]::UTF8)
  }

  Write-Output ''
  Write-Output '--- the control: the documents as they stand ---'
  $ctlBad = @(Get-StatementProblems $texts $names $version $moved)
  $checked++
  if ($ctlBad.Count -eq 0) {
    Write-Output ('  OK: the control passes (version ' + $version + ').')
  } else {
    Write-Output ('  FAIL: the control does NOT pass: ' + $ctlBad.Count + ' problem(s).')
    foreach ($x in $ctlBad) { Write-Output ('        ' + $x) }
    $bad++
  }

  # THE DOCUMENTS THE FAULTS WORK ON.
  #
  # MEASURED 2026-11-21: this self-test was written for a tree in which the
  # source HAD moved under the version, and it asked its faults with the tree's
  # OWN condition. The tree then crossed the release boundary -- the anchor is
  # now the release commit, so the source has NOT moved -- and every fault
  # stopped landing: the three document faults were asked with $moved = $false,
  # where a MISSING statement is CORRECT, and the fourth was asked with
  # documents that no longer carry a statement at all. Four faults, none of
  # them applied, and the self-test said so honestly -- but nothing was
  # watching, because the release gate did not run this self-test.
  #
  # So the documents the faults work on are BUILT here: the real text plus a
  # statement paragraph that names the version, placed FIRST so that the gate
  # finds it. And each fault is asked with the branch it is a defect OF. The
  # gate has two branches, and a fault that exercises only one of them says
  # nothing about the other.
  #
  # The Chinese sentence is built from \u escapes because this file is
  # ASCII-only on purpose: a BOM-less .ps1 with non-ASCII in it is read as ANSI
  # by PowerShell 5.1.
  $zhMarkerText = [regex]::Unescape('\u5DF2\u53D1\u5E03\u7684\u4EA7\u7269\u6BD4\u8FD9\u68F5\u6811\u65E7')
  $zhTail = [regex]::Unescape('\uFF0C\u56E0\u4E3A\u6E90\u7801\u5728\u7248\u672C')
  $zhTail2 = [regex]::Unescape('\u4E4B\u540E\u79FB\u52A8\u8FC7\u3002')
  $statements = @(
    ('NOTE: the released artifact is older than this tree, because the source has moved under version ' + $version + '.'),
    ('NOTE: ' + $zhMarkerText + $zhTail + ' ' + $version + ' ' + $zhTail2)
  )
  $withStatement = @()
  for ($i = 0; $i -lt $texts.Count; $i++) {
    $withStatement += ($statements[$i] + "`r`n`r`n" + $texts[$i])
  }
  # A VERSION THAT IS NOT THIS ONE, derived rather than typed: a fault that
  # names a literal stops applying the moment the tree's version moves.
  $wrongVersion = [regex]::Replace($version, '(\d+)$', { param($m) ([int]$m.Groups[1].Value + 1000).ToString() })

  # THE FAULTS. Each one takes a COPY of the documents and changes exactly one
  # thing, and the gate has to go red with the RIGHT message.
  $faults = @(
    [pscustomobject]@{
      N = 'the statement is missing from README.md'
      Expect = 'does not carry the statement'
      Moved = $true
      Apply = {
        param($t, $n, $v)
        $out = @()
        for ($i = 0; $i -lt $t.Count; $i++) {
          $s = $t[$i]
          if ($n[$i] -eq 'README.md') {
            $s = [regex]::Replace($s, '(?im)^.*the released artifact is older than this tree.*$\r?\n?', '')
          }
          $out += $s
        }
        return ,$out
      }
    }
    [pscustomobject]@{
      N = 'the statement is missing from README.zh.md'
      Expect = 'does not carry the statement'
      Moved = $true
      Apply = {
        param($t, $n, $v)
        $out = @()
        for ($i = 0; $i -lt $t.Count; $i++) {
          $s = $t[$i]
          if ($n[$i] -eq 'README.zh.md') {
            $s = [regex]::Replace($s, '(?im)^.*\u5DF2\u53D1\u5E03\u7684\u4EA7\u7269\u6BD4\u8FD9\u68F5\u6811\u65E7.*$\r?\n?', '')
          }
          $out += $s
        }
        return ,$out
      }
    }
    [pscustomobject]@{
      N = 'the statement names a version that is not the module version'
      Expect = 'does not name version'
      Moved = $true
      Apply = {
        param($t, $n, $v)
        $out = @()
        for ($i = 0; $i -lt $t.Count; $i++) {
          $s = $t[$i]
          # THE STATEMENT'S OWN PARAGRAPH, and its FIRST version token. A
          # `String.Replace` cannot be used here: the Chinese marker is a
          # REGEX escape, and `Replace` would look for the six characters
          # `\u5DF2` rather than for the character. The regex engine is the one
          # that understands the escape.
          $paras = @([regex]::Split($s, '(?:\r?\n)[ \t]*(?:\r?\n)+'))
          for ($j = 0; $j -lt $paras.Count; $j++) {
            if ($paras[$j] -imatch $markers[$i].M) {
              $paras[$j] = [regex]::Replace($paras[$j], '(?<![\w.])\d+\.\d+\.\d+(?![\w])', $v, 1)
            }
          }
          $out += ($paras -join "`r`n`r`n")
        }
        return ,$out
      }
    }
  )

  foreach ($f in $faults) {
    Write-Output ''
    Write-Output ('--- the defect: ' + $f.N + ' ---')
    $mutated = & $f.Apply $withStatement $names $wrongVersion
    if ($null -eq $mutated -or @($mutated).Count -ne $withStatement.Count) {
      Write-Output '  FAIL: the mutation did not produce a copy of the documents.'
      $bad++
      continue
    }
    # DID THE FAULT LAND? A mutation that changed NOTHING is a fault that was
    # never injected, and a gate that stays green because nothing changed has
    # proved nothing. This is the shape the four faults above had: they were
    # applied to documents that did not carry what the fault needed, so they
    # changed nothing and the gate was right to stay green.
    $landed = $false
    for ($i = 0; $i -lt $mutated.Count; $i++) {
      if ($mutated[$i] -ne $withStatement[$i]) { $landed = $true }
    }
    if (-not $landed) {
      Write-Output '  FAIL: the fault did not land -- the mutation changed nothing.'
      $bad++
      continue
    }
    $probs = @(Get-StatementProblems $mutated $names $version $f.Moved)
    $checked++
    $caught = 0
    try {
      if (($probs -join ' | ') -match [regex]::Escape($f.Expect)) { $caught++ }
    } catch {
      Write-Output ('  FAIL: the check itself threw: ' + $_.Exception.Message)
    }
    if ($caught -eq 1) {
      Write-Output ('  OK: the gate caught it: ' + $probs[0])
    } else {
      Write-Output ('  FAIL: the gate did NOT catch it (expected "' + $f.Expect + '").')
      foreach ($pr in $probs) { Write-Output ('        ' + $pr) }
      $bad++
    }
  }

  # AND THE OTHER DIRECTION: the sentence must be GONE when the source has not
  # moved under the version. The documents here CARRY the statement, and the
  # condition is flipped, so the statement is stale -- and the gate has to say
  # so. A gate that only knows how to fail in one direction does not know the
  # other direction.
  Write-Output ''
  Write-Output '--- the defect: the statement is there, and the source has NOT moved ---'
  $otherProbs = @(Get-StatementProblems $withStatement $names $version $false)
  $checked++
  if (($otherProbs -join ' | ') -match 'has NOT moved under version') {
    Write-Output ('  OK: the gate caught it: ' + $otherProbs[0])
  } else {
    Write-Output '  FAIL: the gate did NOT catch a stale statement.'
    foreach ($pr in $otherProbs) { Write-Output ('        ' + $pr) }
    $bad++
  }

  if ($checked -ne 5) {
    Write-Output ('  FAIL: ' + $checked + ' of 5 checks ran.')
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
Write-Output '=== the release freshness: the version must still describe the source ==='
$version = Get-ModuleVersion $root
if ($version -eq '') {
  Write-Output 'FAIL: moon.mod carries no version line, so there is nothing to check.'
  exit 1
}
Write-Output ('  the version in moon.mod: ' + $version)
$anchor = Get-VersionAnchor $root $version
if ($anchor -eq '') {
  Write-Output ('FAIL: no commit in this repository ever set version "' + $version + '", so the anchor cannot be read.')
  Write-Output '      The version has to be committed before the gate can say anything about it.'
  exit 1
}
Write-Output ('  the anchor (the commit that set it): ' + $anchor.Substring(0, 8))
$moved = Test-SourceMoved $root $anchor
if ($null -eq $moved) {
  Write-Output 'FAIL: the source movement could not be read from git.'
  exit 1
}
if ($moved) {
  Write-Output '  the source HAS moved under that version: the released artifact is an OLDER BUILD than this tree.'
  Write-Output '  => the documents have to say so, and they have to name the version.'
} else {
  Write-Output '  the source has NOT moved under that version: the released artifact still describes this tree.'
  Write-Output '  => the documents must NOT carry the statement that it does.'
}

$names = @()
$texts = @()
foreach ($mk in $markers) {
  $names += $mk.F
  $p = Join-Path $root $mk.F
  if (-not (Test-Path -LiteralPath $p)) {
    Write-Output ('FAIL: ' + $mk.F + ' is not in the tree, so nothing can check what it says.')
    $fail++
    $texts += ''
    continue
  }
  $texts += [System.IO.File]::ReadAllText($p, [Text.Encoding]::UTF8)
}
$probs = @(Get-StatementProblems $texts $names $version $moved)
if ($probs.Count -eq 0) {
  Write-Output ('  OK: both documents agree with the version ' + $version + '.')
} else {
  foreach ($x in $probs) {
    Write-Output ('FAIL: ' + $x)
    $fail++
  }
}

Write-Output ''
if ($fail -eq 0) {
  Write-Output ('FRESHNESS OK: version ' + $version + ' and the published documents agree about what the released artifact contains.')
  exit 0
}
Write-Output ('FRESHNESS FAILED: ' + $fail + ' problem(s).')
exit 1
