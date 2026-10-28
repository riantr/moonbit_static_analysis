# The per-function census over the SEVEN pinned corpora.
#
# WHY THIS SCRIPT EXISTS. The 0.4.31 README claimed the per-function view was
# "measured across the pinned corpora" and that the inventory was "empty but for
# two findings". The census that produced those two covered SIX corpora:
# `moonbit_core` was never in it. The seventh corpus carries more findings than
# all six put together, so the claim was true of the corpora that were measured
# and false of the ones that were not. This script is the census over SEVEN,
# and it is a TRACKED script so that the seventh cannot be dropped again.
#
# WHAT IT MEASURES. `--per-function` enters the behavioural lens at each
# FUNCTION instead of at the module. The two views are separate, not additive.
#
# WHAT COUNTS AS "actionable". The scanner prints a finding as
#     <line>:<col> - <error|warning>: <message> (<Category>) [<lens>]
# and a finding whose CATEGORY is `ParseError` is a NOTICE -- it is the
# analyzer saying "this construct is outside the subset I analyse". Everything
# else is a real finding and is counted as actionable, whether its severity is
# `error` or `warning`. A severity of `warning` does not make a finding a
# notice: `unreachable code` and `unused local` are warnings, and they are
# findings.
#
# THE FAMILIES. Every actionable finding must land in a named family, and a
# finding that lands in none is printed as UNCLASSIFIED and makes this script
# FAIL. A census that silently buckets what it does not understand is a census
# that cannot be compared with the next one.
#
# Read-TextWhenFree: a file another process holds open makes ReadAllLines
# THROW. The census reads its own output only, so this is about the corpus
# files being read by the scanner, not by this script.
$ErrorActionPreference = 'Continue'

$root    = Split-Path -Parent $PSScriptRoot
$repos   = Join-Path $root '.repos'
$wasm    = Join-Path $root '_build\wasm\debug\build\moonbit_static_analysis.wasm'
$moonrun = 'C:\Users\31379\.moon\bin\moonrun.exe'

if (-not (Test-Path -LiteralPath $wasm)) {
  Write-Output ("MISSING wasm: " + $wasm)
  exit 1
}

$C = [ordered]@{
  'moui'            = 'wzzc-dev\moui\0.1.12'
  'moonbit_labeler' = 'riantr\moonbit_labeler\0.2.13'
  'moonbit_image'   = 'riantr\moonbit_image\0.3.7'
  'async'           = 'moonbitlang\async\0.22.4'
  'proton'          = 'moonbit-community\proton\0.3.4'
  'proton_contract' = 'moonbit-community\proton_contract\0.3.4'
  'moonbit_core'    = 'moonbitlang\core\0.1.20260920+7d59c7ec9'
}

# --- the families, by pattern -------------------------------------------------
# Each entry is: Name, Then (a regex on the MESSAGE), What (the claim).
$FAMILIES = @(
  @{ Name = 'A  a hex float literal is not read'
     Then = "^undefined (variable|name) '(p1023|p|P|F6A8885A308CA8A54)'"
     What = 'the lexer reads 0x1.0p1023 as 0x1 followed by an identifier, so the exponent part is reported as an undefined name' }
  @{ Name = 'B  a BigInt literal''s N suffix is not read'
     Then = "^undefined (variable|name) 'N'"
     What = '0N and -1N are BigInt literals; the suffix N is read as a name' }
  @{ Name = 'C  == between two arrays'
     Then = "^unsupported operand types for '=='"
     What = 'structural equality on an array is a method the operator table does not have' }
  @{ Name = 'D  a + the operator table does not have'
     Then = "^no method matching \+\("
     What = 'Int+Char and List+List are additions the analyzer does not model' }
  @{ Name = 'E  a * on a struct'
     Then = "^no method matching \*\(Struct"
     What = 'the operands are a struct and the operator table has no * for it' }
  @{ Name = 'F  a name the analyzer cannot see'
     Then = "^undefined function '(makei|X::arbitrary|T::range|T::direction|Array::unsafe_make_uninit)'|^undefined variable 'strconv'"
     What = 'a helper in another file of the same package, a type parameter''s method, an internal API absent from the .mbti index, or the module qualifier of @pkg.name' }
  @{ Name = 'G  unreachable code'
     Then = '^unreachable code'
     What = 'the lens says the statement cannot be reached' }
  @{ Name = 'H  a local that is assigned and never read'
     Then = "^local variable '.*' assigned but may not be used"
     What = 'the lens says the local is dead' }
  @{ Name = 'I  abs on a Double'
     Then = "^argument 1 to 'abs' has incompatible type 'float'"
     What = 'abs is overloaded for Int and Double and the analyzer only knows the Int one' }
  @{ Name = 'J  a * on two function values'
     Then = "^unsupported operand types for '\*'"
     What = 'the operand was inferred as a function, which is a mis-inference, not a defect in the code' }
  @{ Name = 'K  a local call with a named argument'
     Then = '^no method matching array_to_json'
     What = 'array_to_json(f = ...) is read as a method call on array_to_json' }
  @{ Name = 'L  the documented #doc(hidden) limit'
     Then = "^undefined function '@.*::"
     What = 'a cross-package #doc(hidden) function cannot be indexed from the dependency''s SOURCE, only from its .mbti' }
)

function Classify([string]$msg) {
  foreach ($f in $FAMILIES) {
    if ($msg -match $f.Then) { return $f.Name }
  }
  return 'UNCLASSIFIED'
}

$total = 0
$allRows = @()
$unclassified = 0

Write-Output '=== the per-function census, seven pinned corpora ==='
Write-Output ''
foreach ($k in $C.Keys) {
  $dir = Join-Path $repos $C[$k]
  if (-not (Test-Path -LiteralPath $dir)) { Write-Output ("  " + $k + " MISSING " + $dir); continue }
  $out = Join-Path $env:TEMP ('census_' + [guid]::NewGuid().ToString('N').Substring(0,6) + '.txt')
  $err = Join-Path $env:TEMP ('census_' + [guid]::NewGuid().ToString('N').Substring(0,6) + '.err')
  $p = Start-Process -FilePath $moonrun -ArgumentList @(
        $wasm, $dir, '--extern-iface-dir', $repos,
        '--per-function', '--findings-shown-per-file', '1000000'
      ) -WorkingDirectory $root -RedirectStandardOutput $out -RedirectStandardError $err -NoNewWindow -Wait -PassThru
  $txt = [System.IO.File]::ReadAllText($out, [System.Text.Encoding]::UTF8)
  $sum = (([regex]::Match($txt, '(?m)^SUMMARY.*$').Value) -replace "`t", ' ') -replace '^SUMMARY\s*', ''
  $sum = $sum -replace '\s*\(actionable.*$', ''
  # The path in the header is absolute; the corpus root is stripped so that the
  # report carries the PACKAGE too. Four corpora have a file called
  # `quickcheck_test.mbt`, so the file name alone does not identify a site.
  $corpusRoot = [regex]::Escape($dir.TrimEnd('\'))
  $lines = $txt -split "`r?`n"
  $cur = ''
  $rows = @()
  foreach ($l in $lines) {
    $t = $l -split "`t"
    if ($t.Count -ge 2 -and ($t[0] -in @('FOUND','PARTIAL','CLEAN'))) { $cur = ($t[-1].Trim() -replace ('^' + $corpusRoot + '[\\/]'), ''); continue }
    if (($l -match ' - error: ' -or $l -match ' - warning: ') -and $l -notmatch '\(ParseError\)') {
      # 0507. The rendered finding carries its METADATA in the bracket:
      # the lenses, the family's STABLE id, and the confidence. The pattern
      # REQUIRES all three, so a change to the shape fails this gate loudly
      # instead of turning every finding into an UNCLASSIFIED row that reads
      # as "the census found something it could not name".
      $m = [regex]::Match($l, '^(?<f>\d+):(?<c>\d+) - (?<sev>error|warning): (?<msg>.*) \((?<cat>[A-Za-z]+)\) \[(?<lens>[a-z+\-]+), (?<id>MSA-\d{3}), (?<conf>high|low|undecided)\]$')
      if ($m.Success) {
        $rows += [pscustomobject]@{ Corpus = $k; File = $cur; Line = [int]$m.Groups['f'].Value; Sev = $m.Groups['sev'].Value; Msg = $m.Groups['msg'].Value; Fam = (Classify $m.Groups['msg'].Value); Id = $m.Groups['id'].Value; Conf = $m.Groups['conf'].Value }
      } else {
        $rows += [pscustomobject]@{ Corpus = $k; File = $cur; Line = -1; Sev = '?'; Msg = $l; Fam = 'UNCLASSIFIED'; Id = ''; Conf = '' }
      }
    }
  }
  $n = $rows.Count
  $total += $n
  Write-Output ("  {0,-16} actionable={1,-4} {2}" -f $k, $n, $sum)
  $allRows += $rows
  Remove-Item -LiteralPath $out -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $err -Force -ErrorAction SilentlyContinue
}

Write-Output ''
Write-Output '=== the families ==='
$byFam = $allRows | Group-Object Fam | Sort-Object Name
foreach ($g in $byFam) {
  $what = ''
  foreach ($f in $FAMILIES) { if ($f.Name -eq $g.Name) { $what = $f.What } }
  Write-Output ("  {0,-52} {1,4}" -f $g.Name, $g.Count)
  if ($what) { Write-Output ("      {0}" -f $what) }
}
Write-Output ''
Write-Output ("PER-FUNCTION CENSUS actionable = " + $total)
Write-Output ('  per corpus: ' + (($allRows | Group-Object Corpus | Sort-Object Name | ForEach-Object { $_.Name + '=' + $_.Count }) -join ' '))
$unclassified = @($allRows | Where-Object { $_.Fam -eq 'UNCLASSIFIED' })
if ($unclassified.Count -gt 0) {
  Write-Output ''
  Write-Output ('UNCLASSIFIED findings: ' + $unclassified.Count)
  foreach ($u in $unclassified) { Write-Output ('  ' + $u.Corpus + ' ' + $u.File + ':' + $u.Line + '  ' + $u.Msg) }
  exit 1
}
Write-Output 'every actionable finding landed in a named family.'
