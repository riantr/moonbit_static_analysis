# The TRANSFER SCOPE: the requirements document, the three rows it asks for, and
# where each row actually landed.
#
# WHY THIS GATE EXISTS. The objective was "reference `bandit_review.md` and do
# what it says", and that document is NOT in this repository -- it is one
# directory up, and this repository does not edit it, because a requirements
# document edited to match the work is no longer the requirement.
#
# That leaves a hole, and the hole is in the RECORD, not in the code: the three
# transfers were implemented, gated, released and audited, and nothing in the
# repository pointed at the document that asked for them. A reader working from a
# COPY of this repository -- with no network and no parent directory -- could see
# WHAT was built and not WHAT WAS ASKED FOR.
#
# So this gate checks the SCOPE, and it checks it by RESOLVING it:
#
#   1. the requirements document is named, and its own read-at date is carried,
#      so the record says WHICH reading of the document it is answering;
#   2. the three rows are QUOTED VERBATIM -- the requirement text and the
#      review's own prediction of where each row lands -- so a paraphrase cannot
#      quietly become a smaller requirement;
#   3. every implementation site the record names RESOLVES against this tree:
#      the file exists, and the named line still carries the named symbol. This
#      is the part that cannot rot -- a map that names a line nobody checked is
#      a map of where the author THOUGHT the code was;
#   4. every one of the three rows has at least one site, so a row cannot be
#      dropped from the map without the gate noticing;
#   5. the row-3 divergence is EXPLAINED -- the review predicted the parser, the
#      parser is not involved, and the reason is written down;
#   6. the review's own pin for row 3 is accounted for: the settle says in its
#      own words that 0507 inverted that row;
#   7. the three rows are MEASURED, and the measuring scripts are release-gate
#      stages, so a row cannot be satisfied by prose alone;
#   8. the PUBLISHED BYTES are checkable by hash, and the hash is re-checked
#      against the local registry copy whenever that copy is here.
#
# WHY IT IS OFFLINE. It reads files and nothing else: no network, no registry, no
# compiler, no corpus. It is fast enough to run next to anything, and it cannot
# be fooled by a stale build artifact.
#
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File _verify\check_transfer_scope.ps1
#   powershell -NoProfile -ExecutionPolicy Bypass -File _verify\check_transfer_scope.ps1 -SelfTest
#
# The -SelfTest switch INJECTS DEFECTS into a COPY of the tree and shows this
# gate going red for each one, because a guard that has never been shown to go
# red is not a guard. The copy is made under %TEMP%; the repository is not
# touched.
param(
  [switch]$SelfTest,
  [string]$Root = '',
  [string]$AssetPath = ''
)
$ErrorActionPreference = 'Continue'
if (-not $Root) { $Root = Split-Path -Parent $PSScriptRoot }
if (-not $AssetPath) {
  $AssetPath = Join-Path $env:USERPROFILE '.moon\registry\cache\assets\riantr\moonbit_static_analysis\0.4.40\moonbit_static_analysis.wasm'
}

# THE SENTINELS. The map is parsed out of the NARRATIVE between these two lines,
# and the NARRATIVE also QUOTES the review's rows -- and those quoted rows begin
# with "row 1" as well. Without the sentinels the parser would read the quotes
# as sites, and the gate would be checking its own quotation.
$MAP_BEGIN = '    --- TRANSFER MAP ---'
$MAP_END = '    --- END TRANSFER MAP ---'

function Get-Text {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
  return [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
}

function Write-OK {
  param([string]$Msg)
  Write-Output ('  OK: ' + $Msg)
}

function Write-Bad {
  param([string]$Msg)
  Write-Output ('  FAIL: ' + $Msg)
  $script:scopeFail++
}

function Get-MapFiles {
  # The source files the ORIGINAL map names, so a self-test copy carries
  # everything the map points at.
  param([string]$NarrPath)
  $t = Get-Text $NarrPath
  if ($null -eq $t) { return @() }
  $b = $t.IndexOf($MAP_BEGIN)
  $e = $t.IndexOf($MAP_END)
  if ($b -lt 0 -or $e -le $b) { return @() }
  $blk = $t.Substring($b, $e - $b)
  $fs = @()
  foreach ($m in [regex]::Matches($blk, '(?m)^\s*row\s+[123]\s+(\S+):\d+\s+\S')) { $fs += $m.Groups[1].Value }
  return @($fs | Select-Object -Unique)
}

function Test-TransferScope {
  param([string]$Root, [string]$AssetPath)
  $script:scopeFail = 0
  $script:mapFiles = @()

  Write-Output '=== 1. the requirements document is named, and dated ==='
  $narrPath = Join-Path $Root '_verify\NARRATIVE.md'
  $narr = Get-Text $narrPath
  if ($null -eq $narr) {
    Write-Bad ('no ' + $narrPath)
    return
  }
  if ($narr.Contains('bandit_review.md')) {
    Write-OK 'the record names bandit_review.md'
  } else {
    Write-Bad 'the record does not name bandit_review.md.'
    Write-Output '        A requirements document the repository never names is a requirement nobody can check.'
  }
  if ($narr.Contains('2026-10-27')) {
    Write-OK 'the record carries the document''s own read-at date (2026-10-27)'
  } else {
    Write-Bad 'the record does not carry the read-at date of the document it names.'
    Write-Output '        A dated reading is not a stale one, and the date is what says so.'
  }

  Write-Output ''
  Write-Output '=== 2. the three rows are quoted, verbatim ==='
  $quotes = @(
    @{ N = 'row 1, the requirement';    W = 'a per-finding **confidence** axis beside severity' },
    @{ N = 'row 1, where it lands';     W = 'P2 `report.mbt`, P9 `jsoncli`' },
    @{ N = 'row 2, the requirement';    W = '**stable family ids** and a checked profile' },
    @{ N = 'row 2, where it lands';     W = 'P1 `core.mbt:491`, P8 `scan()` options' },
    @{ N = 'row 3, the requirement';    W = '**`nosec`**, including the stale-suppression warning' },
    @{ N = 'row 3, where it lands';     W = 'P3 `parser.mbt`''s skip machinery' }
  )
  foreach ($q in $quotes) {
    if ($narr.Contains($q.W)) {
      Write-OK ($q.N + ' is quoted')
    } else {
      Write-Bad ($q.N + ' is not quoted: ' + $q.W)
    }
  }

  Write-Output ''
  Write-Output '=== 3. every mapped implementation site resolves against this tree ==='
  $b = $narr.IndexOf($MAP_BEGIN)
  $e = $narr.IndexOf($MAP_END)
  if ($b -lt 0 -or $e -le $b) {
    Write-Bad 'the record has no TRANSFER MAP block.'
  } else {
    $blk = $narr.Substring($b + $MAP_BEGIN.Length, $e - ($b + $MAP_BEGIN.Length))
    $entries = @()
    foreach ($m in [regex]::Matches($blk, '(?m)^\s*row\s+([123])\s+(\S+):(\d+)\s+(\S.*?)\s*$')) {
      $entries += [pscustomobject]@{
        Row  = $m.Groups[1].Value
        File = $m.Groups[2].Value
        Line = [int]$m.Groups[3].Value
        Tok  = $m.Groups[4].Value
      }
    }
    Write-Output ('  ' + $entries.Count + ' mapped site(s)')
    if ($entries.Count -eq 0) {
      Write-Bad 'the TRANSFER MAP has no entries in it.'
    }
    $script:mapFiles = @($entries | ForEach-Object { $_.File } | Select-Object -Unique)
    foreach ($en in $entries) {
      $p = Join-Path $Root ($en.File -replace '/', '\')
      if (-not (Test-Path -LiteralPath $p -PathType Leaf)) {
        Write-Bad ('row ' + $en.Row + ' names ' + $en.File + ', which is not in the tree.')
        continue
      }
      $fl = [System.IO.File]::ReadAllLines($p)
      if ($en.Line -lt 1 -or $en.Line -gt $fl.Length) {
        Write-Bad ('row ' + $en.Row + ' names ' + $en.File + ':' + $en.Line + ', and that file has ' + $fl.Length + ' lines.')
        continue
      }
      $text = $fl[$en.Line - 1]
      if ($text.Contains($en.Tok)) {
        Write-OK ('row ' + $en.Row + '  ' + $en.File + ':' + $en.Line + '  ' + $en.Tok)
      } else {
        Write-Bad ('row ' + $en.Row + '  ' + $en.File + ':' + $en.Line + ' does not carry "' + $en.Tok + '".')
        Write-Output ('        the line is: ' + $text.Trim())
      }
    }
    Write-Output ''
    foreach ($r in @('1', '2', '3')) {
      $n = @($entries | Where-Object { $_.Row -eq $r }).Count
      if ($n -eq 0) {
        Write-Bad ('no implementation site is mapped for row ' + $r + '.')
      } else {
        Write-OK ('row ' + $r + ' has ' + $n + ' mapped site(s)')
      }
    }
  }

  Write-Output ''
  Write-Output '=== 4. the row-3 divergence is explained, not just noted ==='
  # The review put row 3 in the parser's skip machinery. The implementation reads
  # the nosec from the raw source line and applies it where the FINAL finding
  # set exists. These three phrases ARE that explanation; without them the
  # record would say the row moved and not say why.
  $why = @(
    'FINAL finding set',
    'BEFORE the lenses',
    'the parser is not involved'
  )
  foreach ($w in $why) {
    if ($narr.Contains($w)) {
      Write-OK ('the rationale says "' + $w + '"')
    } else {
      Write-Bad ('the rationale does not say "' + $w + '".')
    }
  }

  Write-Output ''
  Write-Output '=== 5. the review''s own pin for row 3 was inverted, and says so ==='
  $s5 = Get-Text (Join-Path $Root '_verify\settle_0505_finding_quality.ps1')
  if ($null -eq $s5) {
    Write-Bad 'no _verify\settle_0505_finding_quality.ps1.'
  } else {
    if ($s5.Contains('0507 INVERTED THIS ROW')) {
      Write-OK 'the settle records that 0507 inverted row C3'
    } else {
      Write-Bad 'the settle no longer records that 0507 inverted row C3.'
    }
    if ($s5.Contains('BY DEFAULT')) {
      Write-OK 'row C3 now pins "off by default", not "there is no suppression"'
    } else {
      Write-Bad 'row C3 does not pin the default.'
    }
    if ($narr.Contains('0507 INVERTED THIS ROW')) {
      Write-OK 'the record quotes that inversion'
    } else {
      Write-Bad 'the record does not quote that inversion.'
    }
  }

  Write-Output ''
  Write-Output '=== 6. the rows are measured, and the measuring is a release-gate stage ==='
  $rel = Get-Text (Join-Path $Root '_verify\release.ps1')
  $gates = @('settle_0507_bandit_transfers.ps1', 'settle_0508_confidence_demotion.ps1')
  foreach ($g in $gates) {
    if (-not (Test-Path -LiteralPath (Join-Path $Root ('_verify\' + $g)) -PathType Leaf)) {
      Write-Bad ('no _verify\' + $g + '.')
      continue
    }
    if ($null -ne $rel -and $rel.Contains($g)) {
      Write-OK ($g + ' exists and release.ps1 runs it')
    } else {
      Write-Bad ($g + ' exists but release.ps1 does not run it.')
    }
    if ($narr.Contains($g)) {
      Write-OK ('the record names ' + $g)
    } else {
      Write-Bad ('the record does not name ' + $g + '.')
    }
  }

  Write-Output ''
  Write-Output '=== 7. the published bytes are checkable by hash ==='
  $hm = [regex]::Match($narr, 'the published wasm\s+([0-9A-Fa-f]{64})')
  $cm = [regex]::Match($narr, 'the registry checksum\s+([0-9A-Fa-f]{64})')
  if (-not $hm.Success) {
    Write-Bad 'the record does not carry the published wasm''s SHA256.'
  } else {
    Write-OK ('the record carries the published wasm SHA256 (' + $hm.Groups[1].Value + ')')
  }
  if (-not $cm.Success) {
    Write-Bad 'the record does not carry the registry checksum.'
  } else {
    Write-OK ('the record carries the registry checksum (' + $cm.Groups[1].Value + ')')
  }
  if ($hm.Success -and (Test-Path -LiteralPath $AssetPath -PathType Leaf)) {
    $actual = (Get-FileHash -LiteralPath $AssetPath -Algorithm SHA256).Hash
    if ($actual -eq $hm.Groups[1].Value) {
      Write-OK ('the local registry copy of the published asset hashes to the recorded value (' + $actual + ')')
    } else {
      Write-Bad 'the local registry copy of the published asset does NOT hash to the recorded value.'
      Write-Output ('        recorded: ' + $hm.Groups[1].Value)
      Write-Output ('        on disk:  ' + $actual)
    }
  } elseif ($hm.Success) {
    Write-Output ('  the local copy of the published asset is not on this machine (' + $AssetPath + ')')
    Write-Output '  so the recorded hash could NOT be re-checked here. The record is still there to check.'
  }

  Write-Output ''
  Write-Output '=== 8. the READMEs reach the document, and reach the files ==='
  # The requirements document is outside the repository, so the two places a
  # reader actually starts -- the READMEs -- have to point at it, and they have
  # to name the same files the map does. A README that names a file the map
  # does not is a README pointing at nothing.
  foreach ($rf in @('README.md', 'README.zh.md')) {
    $rt = Get-Text (Join-Path $Root $rf)
    if ($null -eq $rt) {
      Write-Bad ('no ' + $rf)
      continue
    }
    if ($rt.Contains('bandit_review.md')) {
      Write-OK ($rf + ' names bandit_review.md')
    } else {
      Write-Bad ($rf + ' does not name bandit_review.md.')
      Write-Output '        The document is one directory up; a reader of the README has to be told.'
    }
    $missing = @()
    foreach ($f in $script:mapFiles) { if (-not $rt.Contains($f)) { $missing += $f } }
    if ($missing.Count -eq 0) {
      Write-OK ($rf + ' names every file the map names (' + $script:mapFiles.Count + ')')
    } else {
      Write-Bad ($rf + ' does not name ' + $missing.Count + ' of the map''s files:')
      foreach ($f in $missing) { Write-Output ('        ' + $f) }
    }
  }

  Write-Output ''
  if ($script:scopeFail -eq 0) {
    Write-Output 'SCOPE OK: the requirements document is named, its three rows are quoted, every mapped site resolves, and the divergence is explained.'
  } else {
    Write-Output ('SCOPE FAILED: ' + $script:scopeFail + ' problem(s).')
  }
}

# ---------------------------------------------------------------------------
# The self-test: inject a defect, show the gate going red, throw the copy away.
# ---------------------------------------------------------------------------
function Replace-InFile {
  param([string]$Path, [string]$Old, [string]$New)
  $t = Get-Text $Path
  if ($null -eq $t) { return $false }
  if (-not $t.Contains($Old)) { return $false }
  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path, $t.Replace($Old, $New), $enc)
  return $true
}

function Remove-MapRows {
  # Drops every "row N" line out of the map block, keeping the file's own line
  # endings. The separator is DETECTED, not assumed.
  param([string]$Path, [string]$Row)
  $t = Get-Text $Path
  if ($null -eq $t) { return $false }
  $sep = "`n"
  if ($t.Contains("`r`n")) { $sep = "`r`n" }
  $lines = $t -split "`r?`n"
  $kept = @()
  $dropped = 0
  foreach ($l in $lines) {
    if ($l -match ('^\s*row\s+' + $Row + '\s')) { $dropped++ } else { $kept += $l }
  }
  if ($dropped -eq 0) { return $false }
  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path, ($kept -join $sep), $enc)
  return $true
}

function Copy-ScopeFiles {
  param([string]$Src, [string]$Dst)
  $files = @(
    '_verify\NARRATIVE.md',
    '_verify\settle_0505_finding_quality.ps1',
    '_verify\settle_0507_bandit_transfers.ps1',
    '_verify\settle_0508_confidence_demotion.ps1',
    '_verify\release.ps1',
    'README.md',
    'README.zh.md'
  )
  foreach ($f in (Get-MapFiles (Join-Path $Src '_verify\NARRATIVE.md'))) { $files += ($f -replace '/', '\') }
  foreach ($f in ($files | Select-Object -Unique)) {
    $s = Join-Path $Src $f
    if (-not (Test-Path -LiteralPath $s -PathType Leaf)) { continue }
    $d = Join-Path $Dst $f
    $dir = Split-Path -Parent $d
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    Copy-Item -LiteralPath $s -Destination $d -Force
  }
}

if (-not $SelfTest) {
  Test-TransferScope -Root $Root -AssetPath $AssetPath
  if ($script:scopeFail -eq 0) { exit 0 }
  exit 1
}

# --- the self-test ------------------------------------------------------------
Write-Output '=== the transfer-scope self-test: a guard that has never gone red is not a guard ==='
$base = Join-Path $env:TEMP ('tscope_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $base | Out-Null
$pristine = Join-Path $base 'pristine'
Copy-ScopeFiles -Src $Root -Dst $pristine

# A FAKE published asset with known bytes, so the hash check is deterministic and
# does not depend on a registry cache being present on this machine.
$asset = Join-Path $base 'asset.wasm'
[System.IO.File]::WriteAllBytes($asset, [byte[]](1, 2, 3, 4, 5, 6, 7, 8, 9, 10))
$assetHash = (Get-FileHash -LiteralPath $asset -Algorithm SHA256).Hash
# The copy's record must carry THAT hash, or the control run is not green for
# the right reason.
$hm = [regex]::Match((Get-Text (Join-Path $pristine '_verify\NARRATIVE.md')), 'the published wasm\s+([0-9A-Fa-f]{64})')
if (-not $hm.Success) {
  Write-Output 'ABORT: the pristine copy does not carry the published wasm hash.'
  exit 1
}
Replace-InFile (Join-Path $pristine '_verify\NARRATIVE.md') $hm.Groups[1].Value $assetHash | Out-Null

$bad = 0

# THE CONTROL: an unmutated copy must be GREEN. A self-test that only proves
# the gate can fail proves nothing about the gate.
Write-Output ''
Write-Output '--- the control: an unmutated copy must pass ---'
Test-TransferScope -Root $pristine -AssetPath $asset | Out-Null
if ($script:scopeFail -eq 0) {
  Write-Output '  OK: the unmutated copy passes.'
} else {
  Write-Output ('  FAIL: the unmutated copy fails with ' + $script:scopeFail + ' problem(s).')
  $bad++
}

# THE DEFECTS. Each one is a way this gate could stop guarding.
$defects = @(
  @{ N = 'the requirements document is not named';
     M = { param($d) Replace-InFile (Join-Path $d '_verify\NARRATIVE.md') 'bandit_review.md' 'the_review.md' } },
  @{ N = 'a requirement is paraphrased instead of quoted';
     M = { param($d) Replace-InFile (Join-Path $d '_verify\NARRATIVE.md') '**stable family ids** and a checked profile' 'stable family ids and a checked profile' } },
  @{ N = 'a mapped site has moved';
     M = { param($d) Replace-InFile (Join-Path $d '_verify\NARRATIVE.md') 'src/core/core.mbt:478' 'src/core/core.mbt:479' } },
  @{ N = 'a row has no implementation site';
     M = { param($d) Remove-MapRows (Join-Path $d '_verify\NARRATIVE.md') '3' } },
  @{ N = 'the row-3 rationale is gone';
     M = { param($d) Replace-InFile (Join-Path $d '_verify\NARRATIVE.md') 'the parser is not involved' 'the parser is involved' } },
  @{ N = 'the inverted pin lost its marker';
     M = { param($d) Replace-InFile (Join-Path $d '_verify\settle_0505_finding_quality.ps1') '0507 INVERTED THIS ROW' '0507 CHANGED THIS ROW' } },
  @{ N = 'a measuring gate is no longer a release-gate stage';
     M = { param($d) Replace-InFile (Join-Path $d '_verify\release.ps1') 'settle_0508_confidence_demotion.ps1' 'settle_0508_other.ps1' } },
  @{ N = 'the recorded published hash is wrong';
     M = { param($d) Replace-InFile (Join-Path $d '_verify\NARRATIVE.md') $assetHash ('0000000000000000000000000000000000000000000000000000000000000000') } },
  @{ N = 'a README no longer names the requirements document';
     M = { param($d) Replace-InFile (Join-Path $d 'README.md') 'bandit_review.md' 'the_review.md' } }
)

foreach ($x in $defects) {
  Write-Output ''
  Write-Output ('--- the defect: ' + $x.N + ' ---')
  $case = Join-Path $base ('case_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
  Copy-ScopeFiles -Src $pristine -Dst $case
  # A mutation that DOES NOT APPLY is a defect that was never injected, and a
  # gate that stays green because nothing changed has proved nothing.
  $applied = & $x.M $case
  if ($applied -ne $true) {
    Write-Output '  FAIL: the defect did not apply -- the mutation found nothing to change.'
    $bad++
    continue
  }
  Test-TransferScope -Root $case -AssetPath $asset | Out-Null
  if ($script:scopeFail -gt 0) {
    Write-Output ('  OK: the gate caught it (' + $script:scopeFail + ' problem(s)).')
  } else {
    Write-Output '  FAIL: the gate did NOT catch it.'
    $bad++
  }
}

Write-Output ''
if ($bad -eq 0) {
  Write-Output ('SELFTEST OK: the control passed and all ' + $defects.Count + ' injected defects were caught.')
  exit 0
}
Write-Output ('SELFTEST FAILED: ' + $bad + ' of ' + ($defects.Count + 1) + ' checks did not hold.')
exit 1
