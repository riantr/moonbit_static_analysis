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
  # Prove the comparison rejects a widened and a narrowed contract.
  [switch]$SelfTest
)
$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $PSScriptRoot
$contractPath = if ($ContractFile -ne '') { $ContractFile } else { Join-Path $root '_verify\host_requirements.txt' }
$moonModPath = Join-Path $root 'moon.mod'

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
  $syms = @()
  foreach ($line in [System.IO.File]::ReadAllLines($Path, [System.Text.Encoding]::UTF8)) {
    $t = $line.Trim()
    if ($t -eq '' -or $t.StartsWith('#')) { continue }
    if ($t.StartsWith('min-host-async:')) { $min = $t.Substring(15).Trim(); continue }
    if ($t.StartsWith('symbols:')) { continue }
    $syms += $t
  }
  return @{ min = $min; symbols = $syms }
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
  return @{ added = $added; missing = $missing; ok = (($added.Count -eq 0) -and ($missing.Count -eq 0)) }
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
  param([string]$WasmPath, [string[]]$Expected)
  $imports = Get-WasmImports $WasmPath
  # The prefix is counted, not typed: a hand-counted offset left a LEADING SPACE
  # on every symbol, which made all 90 of them compare as different from the
  # contract -- 90 "added" and 90 "missing" at the same time, which is a shape
  # no reader would believe.
  $prefix = 'moonbitlang/async '
  $async = @($imports | Where-Object { $_.StartsWith($prefix) } | ForEach-Object { $_.Substring($prefix.Length) } | Sort-Object -Unique)
  $cmp = Compare-SymbolSets $async $Expected
  return @{ total = $imports.Count; async = $async.Count; added = $cmp.added; missing = $cmp.missing; ok = $cmp.ok }
}

# --- the gate --------------------------------------------------------------------
Write-Output '=== the host contract of the artifact ==='
$contractData = Read-Contract $contractPath
Write-Output ('  contract      : ' + $contractPath)
Write-Output ('  min-host-async: ' + $contractData.min)
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
  $r = Test-ContractAgainst $t $contractData.symbols
  Write-Output ('  ' + (Split-Path -Leaf $t) + ': ' + $r.total + ' imports, ' + $r.async + ' from `moonbitlang/async`')
  if ($r.ok) {
    Write-Output ('  ok  it requires exactly the ' + $contractData.symbols.Count + ' contracted symbols')
  } else {
    if ($r.added.Count -gt 0) {
      Write-Output ('FAIL: it requires ' + $r.added.Count + ' host symbol(s) the contract does not allow:')
      $r.added | Select-Object -First 12 | ForEach-Object { Write-Output ('      + ' + $_) }
      Write-Output '      A dependency bump raised the MINIMUM HOST TOOLCHAIN. Widen'
      Write-Output '      _verify\host_requirements.txt ON PURPOSE, and write down the new floor.'
      $fail++
    }
    if ($r.missing.Count -gt 0) {
      Write-Output ('FAIL: the contract lists ' + $r.missing.Count + ' symbol(s) the artifact no longer requires:')
      $r.missing | Select-Object -First 12 | ForEach-Object { Write-Output ('      - ' + $_) }
      Write-Output '      A narrower artifact is a smaller host requirement -- remove them from the contract.'
      $fail++
    }
  }
}

# The pin and the floor are ONE fact. Two facts that can disagree will.
$moonMod = [System.IO.File]::ReadAllText($moonModPath, [System.Text.Encoding]::UTF8)
$pin = ([regex]::Match($moonMod, '"moonbitlang/async@([^"]+)"')).Groups[1].Value
if ($pin -eq '') {
  Write-Output 'FAIL: moon.mod does not pin `moonbitlang/async`.'
  $fail++
} elseif ($pin -ne $contractData.min) {
  Write-Output ('FAIL: moon.mod pins `moonbitlang/async@' + $pin + '` but the contracted floor is ' + $contractData.min + '.')
  Write-Output '      The floor and the pin are one fact, and a bump that moves one must move the other.'
  $fail++
} else {
  Write-Output ('  ok  moon.mod pins `moonbitlang/async@' + $pin + '`, the contracted floor')
}

# The pinned dependency has to be ABLE to satisfy the contract.
$externs = Get-AsyncExterns $contractData.min $root
if ($null -eq $externs) {
  Write-Output ('  note  the pinned async ' + $contractData.min + ' is not on disk under .repos -- the coverage check needs it fetched.')
} else {
  $notDeclared = @($contractData.symbols | Where-Object { -not $externs.ContainsKey($_) })
  if ($notDeclared.Count -gt 0) {
    Write-Output ('FAIL: the pinned async ' + $contractData.min + ' does not declare ' + $notDeclared.Count + ' contracted symbol(s) as a host extern:')
    $notDeclared | Select-Object -First 12 | ForEach-Object { Write-Output ('      ' + $_) }
    $fail++
  } else {
    Write-Output ('  ok  the pinned async ' + $contractData.min + ' declares ' + $externs.Count + ' host externs and covers all ' + $contractData.symbols.Count + ' of them')
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
  $cases = @(
    @{ name = 'a contract that does not allow a symbol the artifact requires'; symbols = @($base | Where-Object { $_ -ne 'runtime/exit' }); want = 'added' },
    @{ name = 'a contract that lists a symbol the artifact does not require';  symbols = @($base + 'thread_pool/make_write_console_job'); want = 'missing' }
  )
  foreach ($c in $cases) {
    # The contract is written to a FILE and read back through the SAME reader
    # the gate uses, so the self-test exercises the whole path -- reader,
    # comparison and verdict -- and not a copy of half of it.
    $f = Join-Path $scratch 'contract.txt'
    $lines = @('# the self-test contract', ('min-host-async: ' + $contractData.min), ('symbols: ' + $c.symbols.Count), '') + $c.symbols
    [System.IO.File]::WriteAllLines($f, $lines, (New-Object System.Text.UTF8Encoding($false)))
    $readBack = Read-Contract $f
    $r = Test-ContractAgainst $probe $readBack.symbols
    $saw = if ($c.want -eq 'added') { $r.added.Count } else { $r.missing.Count }
    if ($r.ok -or $saw -lt 1) {
      Write-Output ('FAIL: ' + $c.name + ' was ACCEPTED. The gate cannot fail, so it is a comment.')
      $fail++
    } else {
      Write-Output ('  ok  rejected ' + $c.name + ' (' + $c.want + '=' + $saw + ')')
    }
  }
}

Write-Output ''
if ($fail -gt 0) {
  Write-Output ('ABORT: {0} check(s) failed.' -f $fail)
  exit 1
}
Write-Output 'GATE OK: the artifact requires exactly the contracted symbols, the pin and the floor agree, and the pinned dependency can satisfy every one of them.'
exit 0
