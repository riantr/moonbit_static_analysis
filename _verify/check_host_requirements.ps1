param(
  # The wasm to audit. Default: every local build of the artifact -- the release
  # one (that is the one that is published) and the debug one (that is the one
  # the rest of the gate suite runs). Their host requirements have to be the
  # same, and the contract has to cover both.
  [string]$Wasm = '',
  # Audit a CONTRACT other than the pinned one. This is how the comparison is
  # shown to go RED: a contract with one symbol too many, and one with one
  # symbol too few.
  #
  # The parameter is NOT named `Contract`: PowerShell variables are
  # case-insensitive, so a `$contract` local would be the SAME variable as this
  # `[string]` one -- and assigning the parsed contract (a hashtable) to a
  # `[string]` variable coerces it to the text "System.Collections.Hashtable",
  # silently. That is not a theory: the first run of this gate read 0 symbols
  # and 90 "extra" ones, and the cause was that coercion.
  [string]$ContractFile = '',
  # The toolchain's BUNDLED `moonbitlang/core`, whose `core/async` is the host's
  # own implementation of the `moonbitlang/async` ABI. This is where the
  # contract has to be checked against: there is no package this repository
  # pins any more, so the floor is a property of the TOOLCHAIN.
  [string]$CoreDir = '',
  # Prove the comparison rejects a NARROWED contract, and ACCEPTS a widened
  # one as the floor it is. 0606: the contract is a floor, so the two
  # directions are not symmetric, and the self-test says which is which.
  [switch]$SelfTest
)
$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $PSScriptRoot
$contractPath = if ($ContractFile -ne '') { $ContractFile } else { Join-Path $root '_verify\host_requirements.txt' }
$moonModPath = Join-Path $root 'moon.mod'
if ($CoreDir -eq '') { $CoreDir = Join-Path $HOME '.moon\lib\core' }
# 0606. The toolchain's C runtime, the level BELOW the core that implements the
# host ABI. The floor is the toolchain, and this is half of it.
$RuntimeDir = Join-Path $HOME '.moon\lib\runtime'

# --- the wasm reader ------------------------------------------------------------
# The import section is a flat list of (module, name, kind) triples. The reader
# lives here because the PUBLISHED bytes have to be read exactly the way the
# local build is read, and one reader is one answer.
function Read-Leb128 {
  param([byte[]]$Bytes, [ref]$Pos)
  $result = [long]0
  $shift = 0
  do {
    $b = $Bytes[$Pos.Value]
    $Pos.Value = $Pos.Value + 1
    $result = $result -bor (([long]($b -band 0x7F)) -shl $shift)
    $shift = $shift + 7
  } while (($b -band 0x80) -ne 0)
  return $result
}

function Get-WasmImports {
  param([string]$Path)
  $bytes = [System.IO.File]::ReadAllBytes($Path)
  if ($bytes.Length -lt 8) { throw ('not a wasm module: ' + $Path) }
  if ($bytes[0] -ne 0x00 -or $bytes[1] -ne 0x61 -or $bytes[2] -ne 0x73 -or $bytes[3] -ne 0x6D) {
    throw ('not a wasm module: ' + $Path)
  }
  $pos = 8
  $out = @()
  while ($pos -lt $bytes.Length) {
    $id = $bytes[$pos]
    $pos = $pos + 1
    $p = $pos
    $size = Read-Leb128 $bytes ([ref]$p)
    $pos = $p
    if ($id -eq 2) {
      $q = $pos
      $count = Read-Leb128 $bytes ([ref]$q)
      for ($i = 0; $i -lt $count; $i++) {
        $mlen = Read-Leb128 $bytes ([ref]$q)
        $module = [System.Text.Encoding]::UTF8.GetString($bytes, $q, $mlen)
        $q = $q + $mlen
        $nlen = Read-Leb128 $bytes ([ref]$q)
        $name = [System.Text.Encoding]::UTF8.GetString($bytes, $q, $nlen)
        $q = $q + $nlen
        $kind = $bytes[$q]
        $q = $q + 1
        switch ($kind) {
          0 { [void](Read-Leb128 $bytes ([ref]$q)) }
          1 {
            $q = $q + 1
            $flags = $bytes[$q]; $q = $q + 1
            [void](Read-Leb128 $bytes ([ref]$q))
            if (($flags -band 1) -ne 0) { [void](Read-Leb128 $bytes ([ref]$q)) }
          }
          2 {
            $flags = $bytes[$q]; $q = $q + 1
            [void](Read-Leb128 $bytes ([ref]$q))
            if (($flags -band 1) -ne 0) { [void](Read-Leb128 $bytes ([ref]$q)) }
          }
          3 { $q = $q + 2 }
        }
        $out += ($module + ' ' + $name)
      }
    }
    $pos = $pos + $size
  }
  return $out
}

# --- the contract ---------------------------------------------------------------
function Read-Contract {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) { throw ('the contract file is missing: ' + $Path) }
  $min = ''
  $tool = ''
  $abi = ''
  # 0625. THE COUNT IS A PIN TOO. The contract's own `symbols:` line and the list
  # it carries are ONE fact, and the prose that says how many symbols there are
  # is a third copy of it -- so the line is READ, not skipped.
  $count = ''
  $syms = @()
  foreach ($line in [System.IO.File]::ReadAllLines($Path, [System.Text.Encoding]::UTF8)) {
    $t = $line.Trim()
    if ($t -eq '' -or $t.StartsWith('#')) { continue }
    if ($t.StartsWith('min-host-core:')) { $min = $t.Substring(14).Trim(); continue }
    # 0606. THE TOOLCHAIN FLOOR. One contracted symbol is provided by the
    # toolchain's RUNTIME and by no core, so the floor is the toolchain and the
    # contract has to say which one.
    if ($t.StartsWith('min-host-toolchain:')) { $tool = $t.Substring(19).Trim(); continue }
    if ($t.StartsWith('host-abi-module:')) { $abi = $t.Substring(16).Trim(); continue }
    if ($t.StartsWith('symbols:')) { $count = $t.Substring(8).Trim(); continue }
    $syms += $t
  }
  return @{ min = $min; tool = $tool; abi = $abi; count = $count; symbols = $syms }
}

# --- the floor's copies -----------------------------------------------------------
# THE FLOOR IS ONE FACT, and this repository states it in SEVERAL PLACES: the
# contract, `SKILL.md`, `moon.mod`, and the two READMEs. 0615 moved the floor --
# the toolchain's bundled core went from 0.10.20+65efd5b93 to
# 0.10.21+06da1ed44, with `moon` 0.1.20261117 -- and the refresh reached the
# READMEs and NOT the other three. MEASURED 0625:
#
#   * `SKILL.md` still said "moon 0.1.20261104 or later", which bundles a core
#     that does NOT declare `thread_pool/make_openat_job` -- a floor that names
#     a symbol no host can provide is a floor that drops users, and that is the
#     direction this gate treats as a failure;
#   * `SKILL.md` also said "the published wasm imports 93 symbols", which is the
#     CONTRACT's count and not the published artifact's;
#   * `moon.mod` named the same superseded core, and described this gate as
#     comparing the import surface "in BOTH directions" -- the rule is a SUBSET
#     check (0606);
#   * the contract itself said "all 94 symbols below" while the list below it
#     carries 93, and its `min-host-core` field definition named the superseded
#     core.
#
# => ONE FACT, ONE PLACE: the contract is the authority, and these functions hold
# every copy of the floor to the contract's PINS. They do not recompute the
# floor -- the floor IS the contract, and a toolchain that moves moves the pin
# there and nowhere else.
#
# THE ANCHOR IS A REGEX, so the Chinese copy can be written with \u escapes and
# this file can stay ASCII.
function Get-Paragraph {
  param([string]$Text, [string]$Anchor)
  # A PARAGRAPH is the blank-line separated block that carries the anchor.
  foreach ($p in [regex]::Split($Text, '(?:\r?\n)[ \t]*(?:\r?\n)+')) {
    if ($p -cmatch $Anchor) { return $p }
  }
  return $null
}

function Get-Tokens {
  param([string]$Text, [string]$Pattern)
  $out = @()
  foreach ($m in [regex]::Matches($Text, $Pattern)) { $out += $m.Value }
  return $out
}

function Get-Region {
  param([string]$Text, [string]$From, [string]$To)
  # The text from the anchor FROM up to (not including) the anchor TO. The
  # contract's own header is ONE paragraph -- it has no blank lines for 147
  # lines -- so a paragraph-scoped check on it would read its whole HISTORY,
  # and the history names the superseded versions on purpose.
  $i = $Text.IndexOf($From, [System.StringComparison]::Ordinal)
  if ($i -lt 0) { return $null }
  $j = $Text.IndexOf($To, $i, [System.StringComparison]::Ordinal)
  if ($j -lt 0) { $j = $Text.Length }
  return $Text.Substring($i, $j - $i)
}

function Test-FloorCopy {
  param([hashtable]$Contract, [string]$Path, [string]$Anchor, [bool]$RequireCount)
  $problems = @()
  if (-not (Test-Path -LiteralPath $Path)) {
    return @{ ok = $false; problems = @('the file is missing: ' + $Path) }
  }
  $txt = [System.IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8)
  $p = Get-Paragraph $txt $Anchor
  if ($null -eq $p) {
    return @{ ok = $false; problems = @('no paragraph names the floor (' + $Anchor + ')') }
  }
  # THE PINS, NOT A RECOMPUTATION.
  if ($p.IndexOf($Contract.tool, [System.StringComparison]::Ordinal) -lt 0) {
    $problems += ('it does not name the contracted toolchain (' + $Contract.tool + ')')
  }
  if ($p.IndexOf($Contract.min, [System.StringComparison]::Ordinal) -lt 0) {
    $problems += ('it does not name the contracted core (' + $Contract.min + ')')
  }
  # AND NO OTHER VERSION. A paragraph that names a SUPERSEDED toolchain or core
  # is the defect this section exists for, and it is found by the version it
  # names, not by the version it is missing.
  foreach ($v in (Get-Tokens $p '0\.1\.\d{8}(?![+\d])')) {
    if ($v -cne $Contract.tool) { $problems += ('it names a toolchain that is not the contracted one: ' + $v) }
  }
  foreach ($v in (Get-Tokens $p '0\.10\.\d+\+[0-9a-f]{9}')) {
    if ($v -cne $Contract.min) { $problems += ('it names a core that is not the contracted one: ' + $v) }
  }
  if ($RequireCount) {
    $n = $Contract.symbols.Count
    if ($p -notmatch ('(?<!\d)' + $n + '(?!\d)')) { $problems += ('it does not state the contracted symbol count (' + $n + ')') }
  }
  return @{ ok = ($problems.Count -eq 0); problems = $problems }
}

function Test-RuleDirection {
  param([string]$Path, [string]$Anchor, [string]$Want, [string]$Ban)
  $problems = @()
  if (-not (Test-Path -LiteralPath $Path)) {
    return @{ ok = $false; problems = @('the file is missing: ' + $Path) }
  }
  $txt = [System.IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8)
  $p = Get-Paragraph $txt $Anchor
  if ($null -eq $p) {
    return @{ ok = $false; problems = @('no paragraph names the rule (' + $Anchor + ')') }
  }
  if ($p -notmatch $Want) { $problems += ('it does not say the rule is a subset (' + $Want + ')') }
  if ($p -imatch $Ban) { $problems += ('it still calls the two directions symmetric (' + $Ban + ')') }
  return @{ ok = ($problems.Count -eq 0); problems = $problems }
}

function Test-ContractSelf {
  param([string]$Path)
  # THE CONTRACT MUST NOT CONTRADICT ITSELF. The `symbols:` pin, the list it
  # carries, and the numbers its own prose states are ONE fact -- and 0625 found
  # the prose saying 94 while the list below it carried 93.
  $problems = @()
  $c = Read-Contract $Path
  if ($c.count -eq '') {
    $problems += 'the contract carries no `symbols:` pin'
  } elseif ($c.count -notmatch '^\d+$') {
    $problems += ('the `symbols:` pin is not a number: ' + $c.count)
  } elseif ([int]$c.count -ne $c.symbols.Count) {
    $problems += ('the `symbols:` pin says ' + $c.count + ' and the list carries ' + $c.symbols.Count)
  }
  $txt = [System.IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8)
  foreach ($m in [regex]::Matches($txt, 'all (\d+) symbols below')) {
    if ([int]$m.Groups[1].Value -ne $c.symbols.Count) {
      $problems += ('it says "all ' + $m.Groups[1].Value + ' symbols below" and the list below carries ' + $c.symbols.Count)
    }
  }
  # AND THE FIELD DEFINITION NAMES THE PINNED CORE. The `min-host-core`
  # definition is the block between that anchor and the next field's, and it has
  # to name the CONTRACTED core: a definition that names a superseded one is a
  # definition of a floor that no host can satisfy.
  $region = Get-Region $txt '`min-host-core` is the bundled' '`min-host-toolchain` is NEW'
  if ($null -eq $region) {
    $problems += 'it has no `min-host-core` field definition'
  } else {
    foreach ($v in (Get-Tokens $region '0\.10\.\d+\+[0-9a-f]{9}')) {
      if ($v -cne $c.min) { $problems += ('the `min-host-core` definition names a core that is not the contracted one: ' + $v) }
    }
    foreach ($v in (Get-Tokens $region '0\.1\.\d{8}(?![+\d])')) {
      if ($v -cne $c.tool) { $problems += ('the `min-host-core` definition names a toolchain that is not the contracted one: ' + $v) }
    }
  }
  return @{ ok = ($problems.Count -eq 0); problems = $problems }
}

function Replace-InParagraph {
  param([string]$Text, [string]$Anchor, [string]$From, [string]$To)
  # The replacement happens in the block that carries the anchor and NOWHERE
  # ELSE. The corpus version CONTAINS the toolchain version, so a
  # document-wide replacement would change a DIFFERENT copy of the number --
  # and a self-test that mutates another copy proves less than one that mutates
  # the claim (0624).
  $parts = [regex]::Split($Text, '(?:\r?\n)[ \t]*(?:\r?\n)+')
  $hit = $false
  for ($i = 0; $i -lt $parts.Count; $i++) {
    if ($parts[$i] -cmatch $Anchor) { $parts[$i] = $parts[$i].Replace($From, $To); $hit = $true; break }
  }
  if (-not $hit) { return $null }
  return ($parts -join "`r`n`r`n")
}

# --- the comparison -------------------------------------------------------------
# ONE definition of the question, used by the gate and by its self-test: a
# comparison that the self-test exercises is not a copy of the gate's logic.
function Compare-SymbolSets {
  param([string[]]$Actual, [string[]]$Expected)
  $exp = @{}
  foreach ($x in $Expected) { $exp[$x] = $true }
  $act = @{}
  foreach ($x in $Actual) { $act[$x] = $true }
  $added = @($Actual | Where-Object { -not $exp.ContainsKey($_) } | Sort-Object -Unique)
  $missing = @($Expected | Where-Object { -not $act.ContainsKey($_) } | Sort-Object -Unique)
  # 0606. `ok` IS THE FLOOR PROPERTY, and it was the EXACT property before
  # this release: the artifact's imports are a SUBSET of what the contract
  # promises. `added` is empty iff the artifact asks for nothing outside the
  # contract, and that is the direction that drops users, so it is the one
  # that decides. `missing` counts the symbols the contract promises that THIS
  # build does not ask for -- a floor is allowed to be wider than one build,
  # because the BUILDER decides the artifact's exact set.
  return @{ added = $added; missing = $missing; ok = ($added.Count -eq 0) }
}

# --- the floor's VERSION rule --------------------------------------------------
#
# A FLOOR IS A LOWER BOUND. The contract's `min-host-core` is the MINIMUM core a
# host has to bundle -- both READMEs say "0.10.21+06da1ed44 **or later**" -- so
# the question asked of the toolchain standing in front of this gate is "is it AT
# OR ABOVE the floor", and NOT "is it EXACTLY the floor".
#
# MEASURED 2026-11-24: this gate compared the two for EQUALITY, and the
# toolchain that 0631 RE-GATED this tree on -- core `0.10.22+124d61d05`, the
# `$CORE_REGATED` pin in `_verify/release.ps1` -- turned it RED, while the
# coverage check right underneath it said the contract is still satisfiable
# (213 core externs + 289 runtime names cover all 93). So the gate reported a
# defect where there was none, and it did so on the one machine whose toolchain
# the tree was re-gated on. The tree was re-gated against 0.10.22 (0631), so
# 0.10.22 is the SANCTIONED state and the gate has to be GREEN in it.
#
# THAT IS THE SAME MISTAKE 0606 FIXED FOR THE SYMBOL SET AND NEVER CARRIED OVER
# TO THE VERSION. 0606: "the contract is a FLOOR, so the check is a SUBSET
# check" -- a symbol outside the contract is a failure, a symbol inside it that
# one build does not ask for is a note. The version was left as an EQUALITY, so
# the floor was compared as if it were a MIRROR: a mirror is a floor's opposite.
# And 0631 already ruled the question: "the floor stays `moon 0.1.20261117 or
# later` -- the new core declares 213 host externs and the runtime implements
# 288 more, and together they still cover all 93."
#
# THE ORDER. The core's own version is `0.10.<n>+<hash>`, so the numeric part
# orders and the hash only says WHICH BUILD. An incomparable pair is treated as
# OLDER -- a gate that guesses is worse than a gate that says it cannot tell --
# which is the rule `_verify/check_toolchain_claims.ps1` already uses for the
# toolchain's own versions.
function Compare-CoreVersion {
  param([string]$A, [string]$B)
  if ($A -eq '' -or $B -eq '') { return -1 }
  $ma = [regex]::Match($A, '^(\d+)\.(\d+)\.(\d+)')
  $mb = [regex]::Match($B, '^(\d+)\.(\d+)\.(\d+)')
  if (-not $ma.Success -or -not $mb.Success) { return -1 }
  for ($i = 1; $i -le 3; $i++) {
    $x = [int]$ma.Groups[$i].Value
    $y = [int]$mb.Groups[$i].Value
    if ($x -lt $y) { return -1 }
    if ($x -gt $y) { return 1 }
  }
  return 0
}

# THE FLOOR'S VERDICT ON ONE CORE VERSION. ONE definition of the question, used
# by the gate AND by its self-test: a comparison the self-test exercises is not
# a copy of the gate's logic.
function Test-CoreFloor {
  param([hashtable]$Contract, [string]$CoreVersion)
  $rel = Compare-CoreVersion $CoreVersion $Contract.min
  if ($rel -lt 0) {
    return @{
      ok = $false
      relation = 'older'
      problems = @('this toolchain bundles core ' + $CoreVersion + ', which is OLDER than the contracted floor ' + $Contract.min + '. A toolchain below the floor cannot satisfy the contract, so the floor is not met by the toolchain that has to meet it.')
    }
  }
  return @{ ok = $true; relation = $(if ($rel -eq 0) { 'equal' } else { 'newer' }); problems = @() }
}

# A CORE VERSION WITH ITS MINOR MOVED. The self-test's fixtures are DERIVED
# from the floor, not written down: a case that hardcodes a version rots the
# day the floor moves, and then the "above the floor" case silently becomes a
# "below the floor" case and proves the opposite of what it claims.
function Shift-CoreVersion {
  param([string]$Version, [int]$Delta)
  $m = [regex]::Match($Version, '^(\d+)\.(\d+)\.(\d+)(.*)$')
  if (-not $m.Success) { return '' }
  $n = [int]$m.Groups[3].Value + $Delta
  if ($n -lt 0) { return '' }
  return ($m.Groups[1].Value + '.' + $m.Groups[2].Value + '.' + $n + $m.Groups[4].Value)
}

function Get-AsyncExterns {
  param([string]$Version, [string]$Root)
  $dir = Join-Path $Root ('.repos\moonbitlang\async\' + $Version)
  if (-not (Test-Path -LiteralPath $dir)) { return $null }
  $set = @{}
  foreach ($f in Get-ChildItem -LiteralPath $dir -Recurse -File -Filter '*.mbt') {
    $txt = [System.IO.File]::ReadAllText($f.FullName, [System.Text.Encoding]::UTF8)
    foreach ($m in [regex]::Matches($txt, '"moonbitlang/async"\s+"([^"]+)"')) { $set[$m.Groups[1].Value] = $true }
  }
  return $set
}

function Test-ContractAgainst {
  param([string]$WasmPath, [string[]]$Expected, [string]$AbiModule)
  $imports = Get-WasmImports $WasmPath
  # The prefix is counted, not typed: a hand-counted offset left a LEADING SPACE
  # on every symbol, which made all 90 of them compare as different from the
  # contract -- 90 "added" and 90 "missing" at the same time, which is a shape
  # no reader would believe.
  #
  # THE ABI MODULE NAME COMES FROM THE CONTRACT, not from a literal here. The
  # runtime moved into `moonbitlang/core`, but the wasm import name is still
  # "moonbitlang/async" -- the FFI declarations in `core/async` say so -- and a
  # literal here would have silently compared the wrong set.
  $prefix = $AbiModule + ' '
  $async = @($imports | Where-Object { $_.StartsWith($prefix) } | ForEach-Object { $_.Substring($prefix.Length) } | Sort-Object -Unique)
  $cmp = Compare-SymbolSets $async $Expected
  return @{ total = $imports.Count; async = $async.Count; added = $cmp.added; missing = $cmp.missing; ok = $cmp.ok }
}

# THE HOST'S OWN IMPLEMENTATION OF THE ABI: the async runtime bundled with the
# toolchain. The host supplies the contracted symbols from THIS, at
# instantiation time, so the contract is checked against THIS -- not against a
# package this repository pins, because there is no such package any more.
function Get-BundledCore {
  param([string]$CoreDir)
  $mm = Join-Path $CoreDir 'moon.mod'
  if (-not (Test-Path -LiteralPath $mm)) { return $null }
  $txt = [System.IO.File]::ReadAllText($mm, [System.Text.Encoding]::UTF8)
  $v = ([regex]::Match($txt, '(?m)^version\s*=\s*"([^"]+)"')).Groups[1].Value
  $n = ([regex]::Match($txt, '(?m)^name\s*=\s*"([^"]+)"')).Groups[1].Value
  return @{ version = $v; name = $n; dir = $CoreDir }
}

# The host externs the bundled core declares under the ABI module name.
function Get-CoreAsyncExterns {
  param([string]$CoreDir, [string]$AbiModule)
  $dir = Join-Path $CoreDir 'async'
  if (-not (Test-Path -LiteralPath $dir)) { return $null }
  $set = @{}
  foreach ($f in Get-ChildItem -LiteralPath $dir -Recurse -File -Filter '*.mbt') {
    $txt = [System.IO.File]::ReadAllText($f.FullName, [System.Text.Encoding]::UTF8)
    foreach ($m in [regex]::Matches($txt, '"' + [regex]::Escape($AbiModule) + '"\s+"([^"]+)"')) { $set[$m.Groups[1].Value] = $true }
  }
  return $set
}

# THE RUNTIME'S OWN EXPORTED NAMES.
#
# 0606. THE HOST ABI HAS A LEVEL BELOW THE CORE. The published 0.4.52 artifact
# imports `thread_pool/make_openat_job`, and the bundled core does NOT declare
# it -- the core's wasm backend declares `thread_pool/make_open_stat_job`
# instead. The toolchain's C runtime implements the file-IO job as
# `moonbit_rt_make_openat_job` (`~/.moon/lib/runtime/fs.c`), so a floor
# checked against the core ALONE would call a symbol the host really provides
# missing.
#
# So the floor covers a symbol when the CORE declares it or the RUNTIME
# implements it, and the reader for the runtime reads the NAMES the runtime
# exports -- not the names it happens to mention in a comment.
function Get-RuntimeNames {
  param([string]$RuntimeDir)
  $set = @{}
  if (-not (Test-Path -LiteralPath $RuntimeDir)) { return $set }
  foreach ($f in Get-ChildItem -LiteralPath $RuntimeDir -Recurse -File -Include '*.c', '*.h') {
    $txt = [System.IO.File]::ReadAllText($f.FullName, [System.Text.Encoding]::UTF8)
    foreach ($m in [regex]::Matches($txt, '\bmoonbit_rt_([A-Za-z0-9_]+)\s*\(')) {
      $set[$m.Groups[1].Value] = $true
    }
  }
  return $set
}

# The module's IMPORTED PATHS, and nothing else.
#
# THE IMPORT BLOCK, NOT THE FILE. The first version of this check was
# `'moonbitlang/async' -match` over the whole of moon.mod, and it fired on the
# COMMENT that explains what the host ABI is called -- a sentence with the
# module name in quotes. A gate that reads prose is a gate that fires on
# prose, and the fix is to read the thing being checked: the import block.
function Get-MoonModImports {
  param([string]$Text)
  $paths = @()
  foreach ($m in [regex]::Matches($Text, '(?ms)^import\s*\{(.*?)^\}')) {
    foreach ($p in [regex]::Matches($m.Groups[1].Value, '"([^"]+)"')) { $paths += $p.Groups[1].Value }
  }
  return $paths
}

# --- the gate --------------------------------------------------------------------
Write-Output '=== the host contract of the artifact ==='
$contractData = Read-Contract $contractPath
Write-Output ('  contract      : ' + $contractPath)
Write-Output ('  min-host-core : ' + $contractData.min)
Write-Output ('  host ABI      : ' + $contractData.abi)
Write-Output ('  symbols       : ' + $contractData.symbols.Count)
$fail = 0

Write-Output ''
Write-Output '  the floor, and the copies of it that ship:'
$selfCheck = Test-ContractSelf $contractPath
if ($selfCheck.ok) {
  Write-Output ('  ok  the contract does not contradict itself (' + $contractData.symbols.Count + ' symbols, and it says so)')
} else {
  foreach ($pr in $selfCheck.problems) { Write-Output ('FAIL: the contract -- ' + $pr); $fail++ }
}
$floors = @(
  @{ Label = 'SKILL.md';     Path = (Join-Path $root 'SKILL.md');     Anchor = 'IT IS A TOOLCHAIN FLOOR'; Count = $true },
  @{ Label = 'README.md';    Path = (Join-Path $root 'README.md');    Anchor = 'need a MoonBit toolchain bundling'; Count = $false },
  @{ Label = 'README.zh.md'; Path = (Join-Path $root 'README.zh.md'); Anchor = '\u53CA\u4EE5\u540E\u9700\u8981\u81EA\u5E26'; Count = $false },
  @{ Label = 'moon.mod';     Path = (Join-Path $root 'moon.mod');     Anchor = 'THE FLOOR IS A TOOLCHAIN NOW'; Count = $true }
)
foreach ($d in $floors) {
  $r = Test-FloorCopy $contractData $d.Path $d.Anchor $d.Count
  if ($r.ok) {
    Write-Output ('  ok  ' + $d.Label.PadRight(14) + ' states the contracted floor (' + $contractData.tool + ', ' + $contractData.min + ')')
  } else {
    foreach ($pr in $r.problems) { Write-Output ('FAIL: ' + $d.Label + ' -- ' + $pr); $fail++ }
  }
}
# AND THE DIRECTION OF THE RULE. The contract is a FLOOR, so the check is a
# SUBSET check (0606): a symbol outside the contract is a failure, and a symbol
# inside it that one build does not ask for is a note. `moon.mod` still
# described this gate as comparing the two surfaces "in BOTH directions", which
# is the property 0606 measured to be the wrong one.
$rules = @(
  @{ Label = 'moon.mod';     Path = (Join-Path $root 'moon.mod');     Anchor = 'holds the artifact to it'; Want = 'subset'; Ban = 'both direction' },
  @{ Label = 'README.md';    Path = (Join-Path $root 'README.md');    Anchor = 'imports are a \*\*subset\*\*'; Want = 'subset'; Ban = 'both direction' },
  @{ Label = 'README.zh.md'; Path = (Join-Path $root 'README.zh.md'); Anchor = '\u662F\u5951\u7EA6\u7684\*\*\u5B50\u96C6\*\*'; Want = '\u5B50\u96C6'; Ban = '\u4E24\u4E2A\u65B9\u5411' }
)
foreach ($d in $rules) {
  $r = Test-RuleDirection $d.Path $d.Anchor $d.Want $d.Ban
  if ($r.ok) {
    Write-Output ('  ok  ' + $d.Label.PadRight(14) + ' states the rule as a subset check')
  } else {
    foreach ($pr in $r.problems) { Write-Output ('FAIL: ' + $d.Label + ' -- ' + $pr); $fail++ }
  }
}

$targets = @()
if ($Wasm -ne '') {
  $targets = @($Wasm)
} else {
  foreach ($cand in @('_build\wasm\release\build\moonbit_static_analysis.wasm', '_build\wasm\debug\build\moonbit_static_analysis.wasm')) {
    $p = Join-Path $root $cand
    if (Test-Path -LiteralPath $p) { $targets += $p }
  }
}
if ($targets.Count -eq 0) {
  Write-Output 'ABORT: there is no artifact to audit. Build it first.'
  exit 1
}

foreach ($t in $targets) {
  $r = Test-ContractAgainst $t $contractData.symbols $contractData.abi
  Write-Output ('  ' + (Split-Path -Leaf $t) + ': ' + $r.total + ' imports, ' + $r.async + ' from `' + $contractData.abi + '`')
  # 0606. THE CONTRACT IS A FLOOR, so the two directions are NOT symmetric any
  # more, and the reason is MEASURED rather than stylistic:
  #
  #   'added'   the artifact requires a symbol the contract does not allow --
  #             this is the direction that DROPS USERS, because the host has to
  #             supply a symbol an older toolchain does not have. It stays a
  #             FAIL.
  #   'missing' the contract lists a symbol THIS artifact does not require --
  #             the contract is wider than this build, which is what a floor
  #             IS. The published 0.4.52 needs `thread_pool/make_openat_job`
  #             and not the two fsync/open-stat jobs, while the LOCAL build of
  #             the same source needs exactly the reverse, and the contract
  #             has to serve BOTH because the builder decides the set. It is a
  #             NOTE now.
  if ($r.added.Count -gt 0) {
    Write-Output ('FAIL: it requires ' + $r.added.Count + ' host symbol(s) the contract does not allow:')
    $r.added | Select-Object -First 12 | ForEach-Object { Write-Output ('      + ' + $_) }
    Write-Output '      A dependency bump raised the MINIMUM HOST TOOLCHAIN. Widen'
    Write-Output '      _verify\host_requirements.txt ON PURPOSE, and write down the new floor.'
    $fail++
  } else {
    Write-Output ('  ok  every symbol it requires (' + $r.async + ') is in the contract (' + $contractData.symbols.Count + ')')
  }
  if ($r.missing.Count -gt 0) {
    Write-Output ('  note  the contract is wider than this build by ' + $r.missing.Count + ' symbol(s) -- the contract is a FLOOR, so this is expected and not a failure:')
    $r.missing | Select-Object -First 12 | ForEach-Object { Write-Output ('      - ' + $_) }
  }
}

# THE DEPENDENCY MUST NOT COME BACK. `moon.mod` used to pin
# `moonbitlang/async@0.22.5`; the runtime now comes from the toolchain-bundled
# `moonbitlang/core`, so there is no dependency to pin -- and no pin that could
# disagree with the floor, which is the whole point of the swap. A dependency on
# the standalone module coming back would make the artifact's import surface a
# function of a version THIS repository chooses, which is the failure mode the
# swap removed. So the gate refuses it instead of ignoring it.
$moonMod = [System.IO.File]::ReadAllText($moonModPath, [System.Text.Encoding]::UTF8)
$modImports = @(Get-MoonModImports $moonMod)
$asyncImports = @($modImports | Where-Object { $_ -eq 'moonbitlang/async' -or $_ -like 'moonbitlang/async@*' -or $_ -like 'moonbitlang/async/*' })
if ($asyncImports.Count -gt 0) {
  Write-Output ('FAIL: moon.mod imports `' + ($asyncImports -join '`, `') + '` again.')
  Write-Output '      The runtime now comes from the toolchain-bundled moonbitlang/core,'
  Write-Output '      and a dependency on the standalone module would make the import'
  Write-Output '      surface a function of a version this repository chooses -- with the'
  Write-Output '      floor and the artifact two facts again.'
  $fail++
} else {
  Write-Output ('  ok  moon.mod imports no `moonbitlang/async` (it imports ' + $modImports.Count + ' path(s) in total)')
}

# THE FLOOR IS A TOOLCHAIN NOW. The host supplies the ABI from the async
# runtime bundled with the USER's toolchain, so the floor is checked against
# that bundle: it has to declare every contracted symbol, and its version has
# to be AT OR ABOVE the recorded floor -- a floor is a LOWER BOUND, and both
# READMEs say "0.10.21+06da1ed44 or later".
$core = Get-BundledCore $CoreDir
if ($null -eq $core) {
  Write-Output ('  note  no bundled core at ' + $CoreDir + ' -- the coverage check needs the toolchain that built the artifact.')
} else {
  Write-Output ('  bundled core  : ' + $core.name + ' ' + $core.version)
  $floorVerdict = Test-CoreFloor $contractData $core.version
  if (-not $floorVerdict.ok) {
    foreach ($pr in $floorVerdict.problems) { Write-Output ('FAIL: ' + $pr); $fail++ }
  } elseif ($floorVerdict.relation -eq 'equal') {
    Write-Output ('  ok  the toolchain bundles core ' + $core.version + ', the contracted floor')
  } else {
    Write-Output ('  ok  the toolchain bundles core ' + $core.version + ', which is NEWER than the contracted floor ' + $contractData.min + '.')
    Write-Output '      The floor is a floor: it stays where it is when the toolchain moves (0631), and the'
    Write-Output '      coverage check below is what decides whether the contract is still satisfiable.'
  }
  $externs = Get-CoreAsyncExterns $CoreDir $contractData.abi
  if ($null -eq $externs) {
    Write-Output ('  note  the bundled core has no async package -- the coverage check needs it.')
  } else {
    # 0606. THE FLOOR IS THE TOOLCHAIN, so the coverage is checked against the
    # core AND the runtime. One contracted symbol -- `thread_pool/make_openat_job`
    # -- is implemented by the runtime and declared by no core.
    $runtime = Get-RuntimeNames $RuntimeDir
    $notDeclared = @($contractData.symbols | Where-Object {
      $bare = $_.Substring($_.LastIndexOf('/') + 1)
      (-not $externs.ContainsKey($_)) -and (-not $runtime.ContainsKey($bare))
    })
    if ($notDeclared.Count -gt 0) {
      Write-Output ('FAIL: the toolchain declares ' + $externs.Count + ' core externs and implements ' + $runtime.Count + ' runtime names, and together they cover only ' + ($contractData.symbols.Count - $notDeclared.Count) + ' of the ' + $contractData.symbols.Count + ':')
      $notDeclared | Select-Object -First 12 | ForEach-Object { Write-Output ('      ' + $_) }
      $fail++
    } else {
      Write-Output ('  ok  the bundled core declares ' + $externs.Count + ' host externs and the runtime implements ' + $runtime.Count + ' more, and together they cover all ' + $contractData.symbols.Count + ' of them')
    }
  }
}

# AND THE COUNTS THE DOCUMENTS QUOTE FROM THE TOOLCHAIN. The core's extern count
# and the runtime's name count are MEASUREMENTS of a MOVING thing, and a
# document that quotes one has to quote the current one -- so the gate measures
# them and the documents are held to the measurement.
#
# They are checked only when the bundled core IS the contracted one: the counts
# are MEASUREMENTS of the floor's own build, and a toolchain that bundles a
# NEWER core measures its own numbers instead -- the floor's counts are then
# the ones the contract and the documents recorded, not the ones this machine
# can re-measure. (The toolchain being older than the floor is already
# reported above, in the gate's own words.)
if ($null -eq $core) {
  Write-Output '  note  no bundled core, so the counts the documents quote are not checked'
} elseif ($core.version -ne $contractData.min) {
  Write-Output '  note  the bundled core is not the contracted one, so the counts the documents quote are not checked'
} elseif ($null -eq $externs -or $null -eq $runtime) {
  Write-Output '  note  the toolchain has no core async package, so the counts the documents quote are not checked'
} else {
  $quoted = @(
    @{ Label = 'README.md'; Path = (Join-Path $root 'README.md'); From = 'the toolchain has two layers'; To = ''; Extern = 'declares \*\*(\d+)\*\* host externs'; Runtime = 'implements\s+\*\*(\d+)\*\* `moonbit_rt_\*`' },
    @{ Label = 'host_requirements.txt'; Path = $contractPath; From = 'MEASURED on this host: the core declares'; To = '# The floor is a TOOLCHAIN now, not a pin:'; Extern = 'the core declares (\d+) externs'; Runtime = 'the runtime implements\s+(?:#\s*)?(\d+) `moonbit_rt_\*`' }
  )
  $countFails = 0
  foreach ($d in $quoted) {
    $txt = [System.IO.File]::ReadAllText($d.Path, [Text.Encoding]::UTF8)
    # The contract's header is ONE paragraph (no blank line for 147 lines), so
    # its counts are read from the REGION that states them, not from the whole
    # header -- the history above states other measurements on purpose.
    if ($d.To -eq '') { $p = Get-Paragraph $txt $d.From } else { $p = Get-Region $txt $d.From $d.To }
    if ($null -eq $p) {
      Write-Output ('FAIL: ' + $d.Label + ' -- no paragraph names the toolchain counts (' + $d.From + ')')
      $countFails++
      continue
    }
    $em = [regex]::Match($p, $d.Extern)
    $rm = [regex]::Match($p, $d.Runtime)
    if (-not $em.Success -or -not $rm.Success) {
      Write-Output ('FAIL: ' + $d.Label + ' -- it does not state both toolchain counts')
      $countFails++
      continue
    }
    if ([int]$em.Groups[1].Value -ne $externs.Count) {
      Write-Output ('FAIL: ' + $d.Label + ' -- it says the core declares ' + $em.Groups[1].Value + ' host externs and this toolchain declares ' + $externs.Count)
      $countFails++
    }
    if ([int]$rm.Groups[1].Value -ne $runtime.Count) {
      Write-Output ('FAIL: ' + $d.Label + ' -- it says the runtime implements ' + $rm.Groups[1].Value + ' names and this runtime implements ' + $runtime.Count)
      $countFails++
    }
  }
  if ($countFails -eq 0) {
    Write-Output ('  ok  the counts the documents quote are this toolchain''s (' + $externs.Count + ' core externs, ' + $runtime.Count + ' runtime names)')
  }
  $fail += $countFails
}

# --- 0639. THE SENTENCE THAT PUBLISHES THE ARTIFACT'S OWN IMPORT COUNT ----------
#
# MEASURED 2026-11-22, while increment 0639 was being written: the READMEs publish
# "The published 0.5.2 artifact imports **92** symbols" -- a number about ONE
# artifact, named by version -- and NOTHING held it. The search for a gate that
# holds it came back EMPTY: the search for `artifact imports` across `_verify/`
# matches nothing, and the only sentence this gate holds in the READMEs about
# imports is the SUBSET rule. The number had been moved BY HAND after every
# publish -- 0632 for 0.5.1, 0633 for 0.5.2 -- and no gate could say whether it
# was right.
#
# So the sentence is now measured against the artifact it NAMES:
#
#   the version it names    the artifact a reader of THIS release gets, so once
#                           that version has been published it has to be the
#                           version this tree declares -- and "has been published"
#                           is MEASURED, by the artifact's presence in the local
#                           registry cache, which is the same file the
#                           published-bytes rows are re-hashed against.
#   the numbers it quotes   the MEASURED import count of that artifact, of this
#                           tree's own release build, and the contract's own
#                           symbol count.
#
# "STILL TRUE" IS NOT "STILL ABOUT THE RIGHT ARTIFACT". The sentence said 0.5.2
# while 0.5.3 was the published release, and 92 WAS the truth about 0.5.2 -- so a
# gate that asks "is this number true?" stays green while the sentence is about
# the wrong bytes. This one asks WHICH artifact.
#
# AND THE ORDER IS THE ORDER. Before the registry has compiled the version, its
# bytes do not exist, so the version and the number it publishes cannot be
# measured yet: that is stated, not failed. It is the ordering the published-bytes
# rows obey too -- cut the version, run the gate, tag, CI publishes, then measure
# and record.
#
# THE SENTENCE IS ONE REGION AND FOUR NUMBERS, in both languages. The region is
# BOUNDED, so a reworded paragraph cannot make the match run away into another
# one, and the four numbers come out of ONE match, so a document that states the
# contract's count twice is not read twice.
$sentPatterns = @{
  'en' = '(?s)published\s+(\d+\.\d+\.\d+)\s+artifact\s+imports\s+\*\*(\d+)\*\*\s+symbols.{0,600}?imports\s+\*\*(\d+)\*\*\s+as\s+well.{0,600}?the\s+contract\s+is\s+\*\*(\d+)\*\*'
  'zh' = '(?s)\u53D1\u5E03\u51FA\u53BB\u7684\s+(\d+\.\d+\.\d+)\s+\u4EA7\u7269\u5BFC\u5165\u4E86\s+\*\*(\d+)\*\*.{0,600}?\u7684\u4E5F\u662F\s+\*\*(\d+)\*\*.{0,600}?\u5951\u7EA6\u662F\s+\*\*(\d+)\*\*'
}

function Get-PublishedSentence {
  param([string]$Path, [string]$Kind)
  $txt = [System.IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8)
  $m = [regex]::Match($txt, $sentPatterns[$Kind])
  if (-not $m.Success) { return $null }
  return @{
    Version   = $m.Groups[1].Value
    Published = [int]$m.Groups[2].Value
    Local     = [int]$m.Groups[3].Value
    Contract  = [int]$m.Groups[4].Value
  }
}

function Test-PublishedSentence {
  param(
    [string]$Path,
    [string]$Label,
    [string]$Kind,
    [string]$ExpectVersion,
    [int]$ExpectPublished,
    [int]$ExpectLocal,
    [int]$ExpectContract,
    [bool]$VersionChecked
  )
  $problems = @()
  $s = Get-PublishedSentence -Path $Path -Kind $Kind
  if ($null -eq $s) {
    $problems += 'it does not state the published artifact''s import count in the published form.'
    return @{ ok = $false; problems = $problems }
  }
  if ($VersionChecked -and $s.Version -ne $ExpectVersion) {
    $problems += ('it names the published ' + $s.Version + ' artifact, and this release published ' + $ExpectVersion + '.')
  }
  if ($s.Published -ne $ExpectPublished) {
    $problems += ('it says the published artifact imports ' + $s.Published + ' symbols, and that artifact imports ' + $ExpectPublished + '.')
  }
  if ($s.Local -ne $ExpectLocal) {
    $problems += ('it says this tree''s own release build imports ' + $s.Local + ' symbols, and that build imports ' + $ExpectLocal + '.')
  }
  if ($s.Contract -ne $ExpectContract) {
    $problems += ('it says the contract is ' + $s.Contract + ' symbols, and the contract holds ' + $ExpectContract + '.')
  }
  return @{ ok = ($problems.Count -eq 0); problems = $problems }
}

# THE MEASUREMENTS THE SENTENCE IS HELD AGAINST. The published artifact is the
# one in the local registry cache -- the same file the published-bytes rows are
# re-hashed against -- and this tree's own release build is the one the sentence
# names. Both are read with the SAME reader the rest of this gate uses, so "one
# reader, one answer" holds.
$mv = ([regex]::Match([string]$moonMod, '(?m)^version\s*=\s*"([^"]+)"')).Groups[1].Value
$pubWasm = Join-Path ([Environment]::GetFolderPath('UserProfile')) ('.moon\registry\cache\assets\riantr\moonbit_static_analysis\' + $mv + '\moonbit_static_analysis.wasm')
$pubAsync = -1
$publishedHere = $false
if (Test-Path -LiteralPath $pubWasm) {
  $pubR = Test-ContractAgainst $pubWasm $contractData.symbols $contractData.abi
  $pubAsync = $pubR.async
  $publishedHere = $true
}
$releaseWasm = Join-Path $root '_build\wasm\release\build\moonbit_static_analysis.wasm'
$localAsync = -1
$localHere = $false
if (Test-Path -LiteralPath $releaseWasm) {
  $localR = Test-ContractAgainst $releaseWasm $contractData.symbols $contractData.abi
  $localAsync = $localR.async
  $localHere = $true
}
$sentDocs = @(
  @{ Label = 'README.md';    Path = (Join-Path $root 'README.md');    Kind = 'en' },
  @{ Label = 'README.zh.md'; Path = (Join-Path $root 'README.zh.md'); Kind = 'zh' }
)
Write-Output ''
Write-Output '=== the published-artifact sentence is held against the artifact it names ==='
if (-not $publishedHere) {
  Write-Output ('  note  the published ' + $mv + ' artifact is not in the local registry cache, so the version and the number it publishes were not measured here.')
  Write-Output '        The bytes do not exist before the registry compiles them. That is the release order, not a defect.'
}
if (-not $localHere) {
  Write-Output '  note  this tree''s release build is not present, so the number the document quotes about it was not measured here.'
}
if ($publishedHere -and $localHere) {
  foreach ($d in $sentDocs) {
    $r = Test-PublishedSentence -Path $d.Path -Label $d.Label -Kind $d.Kind -ExpectVersion $mv -ExpectPublished $pubAsync -ExpectLocal $localAsync -ExpectContract $contractData.symbols.Count -VersionChecked $true
    if ($r.ok) {
      Write-Output ('  ok  ' + $d.Label.PadRight(14) + ' names the published ' + $mv + ' artifact and quotes the counts that were measured (' + $pubAsync + ' published, ' + $localAsync + ' local, ' + $contractData.symbols.Count + ' contracted)')
    } else {
      foreach ($pr in $r.problems) { Write-Output ('FAIL: ' + $d.Label + ' -- ' + $pr); $fail++ }
    }
  }
}

# --- the self-test: the comparison can go red -------------------------------------
if ($SelfTest) {
  # 0625. THE FLOOR'S COPIES, SHOWN TO GO RED. The defect is in the DOCUMENTS,
  # so the copies that have to go red are COPIES OF THE DOCUMENTS in %TEMP%, and
  # this repository is not touched.
  Write-Output ''
  Write-Output '=== the self-test: a stale copy of the floor has to be caught ==='
  $docScratch = Join-Path $env:TEMP ('hostreq_docs_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
  New-Item -ItemType Directory -Force -Path $docScratch | Out-Null
  # AND THE CONTROL: the documents as they stand must be green.
  foreach ($d in $floors) {
    $r = Test-FloorCopy $contractData $d.Path $d.Anchor $d.Count
    if ($r.ok) {
      Write-Output ('  ok  the control: ' + $d.Label + ' states the contracted floor')
    } else {
      Write-Output ('FAIL: the control: ' + $d.Label + ' -- ' + ($r.problems -join '; '))
      $fail++
    }
  }
  $copyCases = @(
    @{ Label = 'SKILL.md';  File = 'SKILL.md';  Anchor = 'IT IS A TOOLCHAIN FLOOR'; Count = $true;  From = $contractData.tool; To = '0.1.20261104'; Want = 'names a toolchain that is not the contracted one' },
    @{ Label = 'moon.mod';  File = 'moon.mod';  Anchor = 'THE FLOOR IS A TOOLCHAIN NOW'; Count = $true;  From = $contractData.min;  To = '0.10.20+65efd5b93'; Want = 'names a core that is not the contracted one' },
    @{ Label = 'README.md'; File = 'README.md'; Anchor = 'need a MoonBit toolchain bundling'; Count = $false; From = $contractData.tool; To = '0.1.20261104'; Want = 'names a toolchain that is not the contracted one' }
  )
  foreach ($c in $copyCases) {
    $src = Join-Path $root $c.File
    $txt = [System.IO.File]::ReadAllText($src, [Text.Encoding]::UTF8)
    # THE MUTATION IS SCOPED TO THE BLOCK THAT MAKES THE CLAIM, because the
    # corpus version CONTAINS the toolchain version: a document-wide
    # replacement would change a different copy of the number (0624).
    $mutated = Replace-InParagraph $txt $c.Anchor $c.From $c.To
    if ($null -eq $mutated -or $mutated -eq $txt) {
      Write-Output ('FAIL: ' + $c.Label + ' -- the mutation changed nothing, so the case proved nothing')
      $fail++
      continue
    }
    $dst = Join-Path $docScratch $c.File
    [System.IO.File]::WriteAllText($dst, $mutated, (New-Object System.Text.UTF8Encoding($false)))
    $r = Test-FloorCopy $contractData $dst $c.Anchor $c.Count
    if ($r.ok) {
      Write-Output ('FAIL: ' + $c.Label + ' -- a stale copy was ACCEPTED')
      $fail++
      continue
    }
    $joined = ($r.problems -join ' | ')
    if ($joined -notmatch [regex]::Escape($c.Want)) {
      Write-Output ('FAIL: ' + $c.Label + ' -- the copy went red, but not with the right message: ' + $joined)
      $fail++
      continue
    }
    Write-Output ('  ok  ' + $c.Label + ' -- a stale copy is caught: ' + $joined)
  }
  # AND THE CONTRACT AGAINST ITSELF. A copy whose prose says 94 while its list
  # carries 93 has to be caught.
  $ctxt = [System.IO.File]::ReadAllText($contractPath, [Text.Encoding]::UTF8)
  $cmut = $ctxt.Replace('all 93 symbols below', 'all 94 symbols below')
  if ($cmut -eq $ctxt) {
    Write-Output 'FAIL: the contract -- the mutation changed nothing, so the case proved nothing'
    $fail++
  } else {
    $contractCopy = Join-Path $docScratch 'host_requirements.txt'
    [System.IO.File]::WriteAllText($contractCopy, $cmut, (New-Object System.Text.UTF8Encoding($false)))
    $r = Test-ContractSelf $contractCopy
    if ($r.ok) {
      Write-Output 'FAIL: the contract -- a contract that contradicts itself was ACCEPTED'
      $fail++
    } else {
      Write-Output ('  ok  the contract -- a contract that contradicts itself is caught: ' + ($r.problems -join '; '))
    }
  }
  # AND THE CONTRACT'S FIELD DEFINITION. A copy whose `min-host-core`
  # definition names a superseded core has to be caught, and the mutation is
  # SCOPED to that definition: the contract's HISTORY names the superseded core
  # on purpose, and a document-wide replacement would change it too.
  $region = Get-Region $ctxt '`min-host-core` is the bundled' '`min-host-toolchain` is NEW'
  if ($null -eq $region) {
    Write-Output 'FAIL: the contract -- it has no `min-host-core` field definition, so the case proved nothing'
    $fail++
  } else {
    $mutRegion = $region.Replace($contractData.min, '0.10.20+65efd5b93')
    if ($mutRegion -eq $region) {
      Write-Output 'FAIL: the contract -- the mutation changed nothing, so the case proved nothing'
      $fail++
    } else {
      $cdef = Join-Path $docScratch 'host_requirements_def.txt'
      [System.IO.File]::WriteAllText($cdef, $ctxt.Replace($region, $mutRegion), (New-Object System.Text.UTF8Encoding($false)))
      $r = Test-ContractSelf $cdef
      if ($r.ok) {
        Write-Output 'FAIL: the contract -- a definition that names a superseded core was ACCEPTED'
        $fail++
      } else {
        $joined = ($r.problems -join ' | ')
        if ($joined -notmatch 'names a core that is not the contracted one') {
          Write-Output ('FAIL: the contract -- the copy went red, but not with the right message: ' + $joined)
          $fail++
        } else {
          Write-Output ('  ok  the contract -- a definition that names a superseded core is caught: ' + $joined)
        }
      }
    }
  }
  Write-Output ''
  Write-Output '=== the self-test: the comparison rejects a contract that does not match ==='
  $base = $contractData.symbols
  $scratch = Join-Path $env:TEMP ('hostreq_selftest_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
  New-Item -ItemType Directory -Force -Path $scratch | Out-Null
  $probe = $targets[0]
  # The two directions are DIFFERENT reader harms, so the two cases are not
  # mirror images:
  #
  #   'added'   the artifact requires a symbol the contract does not allow --
  #             this is the direction that DROPS USERS, because the host has to
  #             supply a symbol an older toolchain does not have.
  #   'missing' the contract lists a symbol the artifact no longer requires --
  #             the artifact got NARROWER, which is safe for users but leaves
  #             the contract claiming a requirement that is not there.
  #
  # So the artifact's imports are the FIXED side here, and the contract is what
  # is made wrong on purpose.
  # 0606. THE TWO DIRECTIONS ARE NOT SYMMETRIC, and the self-test says so.
  #
  #   'added'   must FAIL -- it is the direction that drops users.
  #   'missing' must NOT fail -- the contract is a floor and is allowed to be
  #             wider than any one build, because the BUILDER decides the
  #             artifact's exact import set. MEASURED: the published 0.4.52
  #             and the local build of the same source differ in exactly three
  #             symbols, and the contract has to serve both.
  #
  # So the self-test has TWO obligations, and a gate that only checks the first
  # would pass a contract that is a mirror -- which is the property that was
  # wrong.
  $cases = @(
    @{ name = 'a contract that does not allow a symbol the artifact requires'; symbols = @($base | Where-Object { $_ -ne 'runtime/exit' }); want = 'added' },
    @{ name = 'a contract that lists a symbol the artifact does not require';  symbols = @($base + 'thread_pool/never_declared'); want = 'missing' }
  )
  foreach ($c in $cases) {
    # The contract is written to a FILE and read back through the SAME reader
    # the gate uses, so the self-test exercises the whole path -- reader,
    # comparison and verdict -- and not a copy of half of it.
    $f = Join-Path $scratch 'contract.txt'
    $lines = @('# the self-test contract', ('min-host-core: ' + $contractData.min), ('min-host-toolchain: ' + $contractData.tool), ('host-abi-module: ' + $contractData.abi), ('symbols: ' + $c.symbols.Count), '') + $c.symbols
    [System.IO.File]::WriteAllLines($f, $lines, (New-Object System.Text.UTF8Encoding($false)))
    $readBack = Read-Contract $f
    $r = Test-ContractAgainst $probe $readBack.symbols $readBack.abi
    $saw = if ($c.want -eq 'added') { $r.added.Count } else { $r.missing.Count }
    if ($c.want -eq 'added') {
      # THE 'added' DIRECTION MUST STILL BE ABLE TO FAIL.
      if ($r.ok -or $saw -lt 1) {
        Write-Output ('FAIL: ' + $c.name + ' was ACCEPTED. The gate cannot fail, so it is a comment.')
        $fail++
      } else {
        Write-Output ('  ok  rejected ' + $c.name + ' (' + $c.want + '=' + $saw + ')')
      }
    } else {
      # THE 'missing' DIRECTION MUST NOT FAIL, because the contract is a floor.
      # AND IT MUST BE SEEN, because a floor that is silently wider than the
      # build is a floor nobody reads.
      if (-not $r.ok -or $saw -lt 1) {
        Write-Output ('FAIL: ' + $c.name + ' did not widen the comparison (' + $c.want + '=' + $saw + '). The floor has to be compared as a floor.')
        $fail++
      } else {
        Write-Output ('  ok  accepted ' + $c.name + ' as a NOTE (' + $c.want + '=' + $saw + '), because the contract is a floor')
      }
    }
  }
function Replace-InSentence {
  param([string]$Text, [string]$Kind, [string]$FromPattern, [string]$To)
  $m = [regex]::Match($Text, $sentPatterns[$Kind])
  if (-not $m.Success) { return $null }
  $region = $m.Value
  $rm = [regex]::Match($region, $FromPattern)
  if (-not $rm.Success) { return $null }
  $mut = $region.Substring(0, $rm.Index) + $To + $region.Substring($rm.Index + $rm.Length)
  return $Text.Replace($region, $mut)
}


  # AND THE PUBLISHED-ARTIFACT SENTENCE (0639). The document that PUBLISHES the
  # artifact's import count has to be HELD, and the self-test has to show the
  # hold can go red: a copy that names a DIFFERENT artifact, or that quotes a
  # DIFFERENT number, has to be caught -- and each fault asks whether it LANDED,
  # because a mutation that changed nothing proves nothing.
  Write-Output ''
  Write-Output '=== the self-test: the published-artifact sentence has to be held ==='
  if (-not ($publishedHere -and $localHere)) {
    Write-Output '  note  the published artifact or this tree''s release build is not on this machine, so there is nothing here to measure.'
  } else {
    $sentScratch = Join-Path $env:TEMP ('hostreq_sent_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Force -Path $sentScratch | Out-Null
    # THE CONTROL: the documents as they stand must be green.
    foreach ($d in $sentDocs) {
      $r = Test-PublishedSentence -Path $d.Path -Label $d.Label -Kind $d.Kind -ExpectVersion $mv -ExpectPublished $pubAsync -ExpectLocal $localAsync -ExpectContract $contractData.symbols.Count -VersionChecked $true
      if ($r.ok) {
        Write-Output ('  ok  the control: ' + $d.Label + ' names the published artifact and quotes the measured counts')
      } else {
        Write-Output ('FAIL: the control: ' + $d.Label + ' -- ' + ($r.problems -join '; '))
        $fail++
      }
    }
    # THE FAULTS. They are the two things the sentence can get wrong -- it names
    # the wrong ARTIFACT, or it quotes the wrong NUMBER -- in both languages.
    $sentCases = @(
      @{ Label = 'README.md';    Kind = 'en'; From = ([regex]::Escape($mv)); To = '0.5.2'; Want = 'names the published' },
      @{ Label = 'README.md';    Kind = 'en'; From = ('\*\*' + $pubAsync + '\*\* symbols'); To = ('**' + ($pubAsync + 1) + '** symbols'); Want = 'that artifact imports' },
      @{ Label = 'README.zh.md'; Kind = 'zh'; From = ('\*\*' + $pubAsync + '\*\*'); To = ('**' + ($pubAsync + 1) + '**'); Want = 'that artifact imports' },
      @{ Label = 'README.zh.md'; Kind = 'zh'; From = ([regex]::Escape($mv)); To = '0.5.2'; Want = 'names the published' }
    )
    foreach ($c in $sentCases) {
      $src = Join-Path $root $c.Label
      $txt = [System.IO.File]::ReadAllText($src, [Text.Encoding]::UTF8)
      $mutated = Replace-InSentence $txt $c.Kind $c.From $c.To
      if ($null -eq $mutated -or $mutated -eq $txt) {
        Write-Output ('FAIL: ' + $c.Label + ' -- the mutation changed nothing, so the case proved nothing')
        $fail++
        continue
      }
      $dst = Join-Path $sentScratch $c.Label
      [System.IO.File]::WriteAllText($dst, $mutated, (New-Object System.Text.UTF8Encoding($false)))
      $r = Test-PublishedSentence -Path $dst -Label $c.Label -Kind $c.Kind -ExpectVersion $mv -ExpectPublished $pubAsync -ExpectLocal $localAsync -ExpectContract $contractData.symbols.Count -VersionChecked $true
      if ($r.ok) {
        Write-Output ('FAIL: ' + $c.Label + ' -- a wrong published-artifact sentence was ACCEPTED')
        $fail++
        continue
      }
      $joined = ($r.problems -join ' | ')
      if ($joined -notmatch [regex]::Escape($c.Want)) {
        Write-Output ('FAIL: ' + $c.Label + ' -- the copy went red, but not with the right message: ' + $joined)
        $fail++
        continue
      }
      Write-Output ('  ok  ' + $c.Label + ' -- a wrong published-artifact sentence is caught: ' + $joined)
    }
  }

  # --- the VERSION rule: a floor is a LOWER BOUND, and it can still go red ------
  #
  # THE THREE CASES ARE THREE COPIES OF ONE CORE, AND THE VERSION IS THE ONLY
  # DIFFERENCE BETWEEN THEM. Every one of them declares EVERY contracted
  # symbol, so the COVERAGE check passes in all three -- and that is MEASURED
  # here, recomputed from each fixture with the SAME reader the gate uses,
  # rather than asserted. A case that also failed coverage would prove
  # something about the coverage, not about the version.
  #
  #   the floor itself        ACCEPTED -- it is the floor
  #   a core BELOW the floor  REJECTED -- a host cannot be below the minimum
  #                        the contract asks for, and this is the direction
  #                        that DROPS USERS
  #   a core ABOVE the floor  ACCEPTED -- this is the case that was RED on
  #                        2026-11-24, and 0631 already ruled it: "the floor
  #                        stays moon 0.1.20261117 or later"
  #
  # THE VERSIONS ARE DERIVED FROM THE FLOOR, never written down, so that the
  # cases survive the floor moving.
  Write-Output ''
  Write-Output '=== the self-test: the floor is a lower bound, and the version rule can still go red ==='
  $verScratch = Join-Path $env:TEMP ('hostreq_ver_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
  $rt = Get-RuntimeNames $RuntimeDir
  $verCases = @(
    @{ label = 'the floor itself';      version = $contractData.min;                      want = 'ok'  },
    @{ label = 'a core below the floor'; version = (Shift-CoreVersion $contractData.min -1); want = 'red' },
    @{ label = 'a core above the floor'; version = (Shift-CoreVersion $contractData.min 1); want = 'ok'  }
  )
  foreach ($c in $verCases) {
    if ($c.version -eq '') {
      Write-Output ('FAIL: ' + $c.label + ' -- the floor ' + $contractData.min + ' could not be shifted, so the case proved nothing')
      $fail++
      continue
    }
    $cdir = Join-Path $verScratch ([regex]::Replace($c.version, '[^0-9A-Za-z]', '_'))
    New-Item -ItemType Directory -Force -Path (Join-Path $cdir 'async') | Out-Null
    $mm = @('name = "moonbitlang/core"', ('version = "' + $c.version + '"'), '') -join "`n"
    [System.IO.File]::WriteAllText((Join-Path $cdir 'moon.mod'), $mm, (New-Object System.Text.UTF8Encoding($false)))
    # EVERY contracted symbol, declared the way the bundled core declares them.
    $decls = @()
    foreach ($s in $contractData.symbols) {
      $decls += ('fn host_' + $decls.Count + '() = "' + $contractData.abi + '" "' + $s + '"')
    }
    [System.IO.File]::WriteAllText((Join-Path $cdir 'async\externs.mbt'), (($decls -join "`n") + "`n"), (New-Object System.Text.UTF8Encoding($false)))
    # THE SAME READERS THE GATE USES: the version out of the fixture's own
    # moon.mod, the coverage out of the fixture's own async package.
    $fc = Get-BundledCore $cdir
    $fx = Get-CoreAsyncExterns $cdir $contractData.abi
    if ($null -eq $fc -or $null -eq $fx) {
      Write-Output ('FAIL: ' + $c.label + ' -- the fixture could not be read back, so the case proved nothing')
      $fail++
      continue
    }
    if ($fc.version -ne $c.version) {
      Write-Output ('FAIL: ' + $c.label + ' -- the fixture reads back as ' + $fc.version + ' instead of ' + $c.version + ', so the case proved nothing')
      $fail++
      continue
    }
    $covered = @($contractData.symbols | Where-Object {
      $bare = $_.Substring($_.LastIndexOf('/') + 1)
      $fx.ContainsKey($_) -or $rt.ContainsKey($bare)
    })
    if ($covered.Count -ne $contractData.symbols.Count) {
      Write-Output ('FAIL: ' + $c.label + ' -- the fixture covers only ' + $covered.Count + ' of the ' + $contractData.symbols.Count + ' contracted symbols, so the version rule is not the only thing that can decide')
      $fail++
      continue
    }
    $r = Test-CoreFloor $contractData $fc.version
    if ($c.want -eq 'ok') {
      if (-not $r.ok) {
        Write-Output ('FAIL: ' + $c.label + ' (' + $fc.version + ') was REJECTED: ' + ($r.problems -join '; '))
        $fail++
      } else {
        Write-Output ('  ok  accepted ' + $c.label + ' (' + $fc.version + '), and the verdict says it is ' + $r.relation + ' the floor')
      }
    } else {
      if ($r.ok) {
        Write-Output ('FAIL: ' + $c.label + ' (' + $fc.version + ') was ACCEPTED. A floor that cannot be checked is a comment.')
        $fail++
      } else {
        Write-Output ('  ok  rejected ' + $c.label + ' (' + $fc.version + '): ' + ($r.problems -join '; '))
      }
    }
  }
}

Write-Output ''
if ($fail -gt 0) {
  Write-Output ('ABORT: {0} check(s) failed.' -f $fail)
  exit 1
}
Write-Output 'GATE OK: every symbol the artifact requires is in the contract, the dependency has not come back, and the toolchain -- its bundled core AND its runtime -- is at or above the contracted floor and can satisfy every one of them.'
exit 0
