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
    if ($t.StartsWith('symbols:')) { continue }
    $syms += $t
  }
  return @{ min = $min; tool = $tool; abi = $abi; symbols = $syms }
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

$fail = 0
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
# to BE the recorded floor.
$core = Get-BundledCore $CoreDir
if ($null -eq $core) {
  Write-Output ('  note  no bundled core at ' + $CoreDir + ' -- the coverage check needs the toolchain that built the artifact.')
} else {
  Write-Output ('  bundled core  : ' + $core.name + ' ' + $core.version)
  if ($core.version -ne $contractData.min) {
    Write-Output ('FAIL: the toolchain bundles core ' + $core.version + ', the contracted floor is ' + $contractData.min + '.')
    Write-Output '      The floor and the toolchain are one fact, and a toolchain that moved must move the floor.'
    $fail++
  } else {
    Write-Output ('  ok  the toolchain bundles core ' + $core.version + ', the contracted floor')
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

# --- the self-test: the comparison can go red -------------------------------------
if ($SelfTest) {
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
}

Write-Output ''
if ($fail -gt 0) {
  Write-Output ('ABORT: {0} check(s) failed.' -f $fail)
  exit 1
}
Write-Output 'GATE OK: every symbol the artifact requires is in the contract, the dependency has not come back, and the toolchain -- its bundled core AND its runtime -- is the contracted floor and can satisfy every one of them.'
exit 0
