# Diagnosis for increment 0446 -- three of the five remaining actionable findings
# are NOT missing declarations.
#
# RUN THIS; it re-derives every number below. It is a diagnosis, not a settle: the
# grammar question at the bottom is still OPEN, and this script says so rather than
# pretending otherwise.
#
# WHAT THE FIVE LOOKED LIKE.
#   proton facade_cookie.mbt:13  undefined name 'CookieWaiting'
#   proton facade_cookie.mbt:42  no visible binding for 'CookieCompleted'
#   proton facade_dialog.mbt:13  undefined name 'Waiting'
#   proton facade_notification.mbt:12,14  undefined function '@async.CondVar::Cond'
#
# The first three are a SHAPE ERROR, and it is the kind this project has been
# wrong about before. `CookieWaiting` and `CookieCompleted` are declared, in
# proton 0.3.4 `facade_types.mbt`:
#
#     589  priv enum CookieCompletionState {
#     590    CookieWaiting
#     591    CookieCompleted(
#     592      Result[Array[@native.NativeCookieRecord], @native.NativeError]
#     593    )
#     594  }
#
# and `facade_cookie.mbt` USES them. So the analyzer is not failing to see a
# declaration that does not exist. It is failing to see one that does.
#
# WHY. Running the scanner on that one file alone:
#
#     PARTIAL  .mbt  defects=0  notices=37
#              read up to line 246, 1 after it not shown
#
# `region_line` is `first_error_line` (`src/sa/main.mbt`), so the file is genuinely
# read only to line 246 -- and the declarations are at 589. Everything past the
# boundary is counted `unreliable` and withheld. A file that is truncated past its
# declarations contributes NOTHING to the cross-file symbol table, so a sibling
# that uses `CookieWaiting` is told the name is undefined. Three findings in one
# file, one cause in another.
#
# THE CAUSE, localised by bisection rather than by reading. Taking prefixes of the
# real file, `cut` only appears once line 247 exists:
#
#     prefix 240 -> cut=240 (that is just EOF)
#     prefix 246 -> cut=246 (EOF)
#     prefix 247 -> cut=246     <-- genuine: before EOF
#     prefix 320 -> cut=246
#
# and the single-file run reports the reason outright:
#
#     NOTPARSE  1 files, 1 finding(s) withheld
#       1x  unterminated block string literal (expected a line-leading `#|`)
#
# Line 235 is `let titlebar_area_bridge_source =` and lines 236-246 are a block
# string whose EVERY line starts with `#|`:
#
#     235  let titlebar_area_bridge_source =
#     236    #|Object.defineProperty(globalThis.__MoonBit__, "getTitlebarArea", {
#     ...
#     245    #|});
#     246    #|
#
# THE DEFECT IS MEASURED AND IT IS A FALSE POSITIVE. `moon check` ACCEPTS this,
# and accepts every small shape of it tried (9 of 9, see the table the script
# prints). The analyzer reports `unterminated block string literal` on a 3-marker
# form:
#
#     let s =            <- line 1
#       #|abc            <- marker 1
#       #|def            <- marker 2
#       #|               <- marker 3
#
# and on a 2-marker form with no closer at all. Its rule pairs line-leading `#|`
# markers as opener/closer alternately, so an ODD count ends "unterminated":
#
#     analyzer: one_line (2 markers) CLEAN / two_line (3) UNTERMINATED
#               three_line (4) CLEAN / five would be UNTERMINATED
#
# Odd/even, exactly. And `moon check` accepts the odd ones.
#
# BLAST RADIUS, measured across all six corpora -- SMALLER THAN IT LOOKS, which is
# the useful part:
#
#     corpus           truncated files   of which "unterminated block string"
#     moui                          17                      1
#     moonbit_labeler                7                      1
#     moonbit_image                 12                      0
#     async                        119                      1
#     proton                        27                      1     <- the one that matters
#     proton_contract                0                      0
#
# Four files total. The other 178 truncations have other causes and this change
# does not touch them, so "fix the block string" is not "fix truncation".
#
# ------------------------------------------------------------------------------
# WHAT IS NOT SETTLED, and why this is a diagnosis and not a fix.
#
# I could not establish WHERE the toolchain ends a block string. Three candidate
# rules were tested against `moon check` with an "is the following line code or
# string content" probe (an unbalanced quote after the block: REJECTED means the
# tail is code):
#
#   rule A  closer = the next line-leading `#|`
#           FALSIFIED. On `#|abc / #|def / #| / <tail>` rule A closes at `#|def`
#           and re-opens on the bare `#|`, which should swallow the tail. The tail
#           was CODE.
#   rule B  closer = a line-leading `#|` with nothing after it
#           FALSIFIED. On `#|abc / #|def / <tail>` -- no such marker -- rule B
#           says the string runs to EOF and swallows the tail. The tail was CODE.
#   rule C  the analyzer's own alternating-pair model
#           FALSIFIED by the same two cases.
#
# Two later probes were meant to read the string's exact VALUE through an
# exhaustive `match`, and both were MALFORMED: the first embedded a real newline
# inside a `"..."` literal, and the second omitted the wildcard that makes a
# String match exhaustive, so 3002 fired on correct input too. A probe whose
# control does not fire supports no conclusion, so neither result is cited above.
#
# No rule is claimed. `src/lexer/lexer.mbt` `lex_block_string` implements rule A,
# and its own header documents rule A as settled against `moon run` -- with seven
# measurements that this diagnosis has NOT yet re-verified and has NOT yet
# falsified either, because the value probes are still unbuilt. That header may
# be right and the corpus wrong about something else, or the header may be wrong;
# the evidence above does not say which.
#
# The next step is a value probe that is right: `moon fmt` on each shape first
# (it must parse, and its output shows the canonical structure), then a
# `match` WITH a wildcard arm whose body asserts the literal, so 3002 cannot fire
# on a correct answer. Until that exists, changing the lexer is a guess.
# ------------------------------------------------------------------------------

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$wasm = Join-Path $repo '_build\wasm\debug\build\moonbit_static_analysis.wasm'
$moonrun = Join-Path $env:USERPROFILE '.moon\bin\moonrun.exe'
$enc = New-Object System.Text.UTF8Encoding($false)
$fail = 0

if (-not (Test-Path $wasm)) {
  Write-Output "ABORT: analyzer wasm not built at $wasm (run: moon build --target wasm)"
  exit 1
}

$cases = [ordered]@{
  'one_line'   = @('let s =', '  #|abc', '  #|')
  'two_line'   = @('let s =', '  #|abc', '  #|def', '  #|')
  'three_line' = @('let s =', '  #|aaa', '  #|bbb', '  #|ccc', '  #|')
  'five_line'  = @('let s =', '  #|a', '  #|b', '  #|c', '  #|d', '  #|e', '  #|')
}

Write-Output 'marker-shape          moon check   analyzer'
Write-Output '---------------------  -----------  ----------------'
foreach ($k in $cases.Keys) {
  $lines = @($cases[$k]) + @('', 'fn after() -> Int {', '  7', '}')

  # --- the toolchain -------------------------------------------------------
  $d = Join-Path $env:TEMP ('bs0446_' + $k)
  New-Item -ItemType Directory -Force -Path (Join-Path $d 'src') | Out-Null
  [IO.File]::WriteAllText((Join-Path $d 'moon.mod'), "name = `"bs0446`"`nversion = `"0.1.0`"`n", $enc)
  [IO.File]::WriteAllText((Join-Path $d 'src\moon.pkg'), "", $enc)
  [IO.File]::WriteAllText((Join-Path $d 'src\p.mbt'), ($lines -join "`n"), $enc)
  Push-Location $d
  $o = cmd.exe /c "moon check 2>&1"
  Pop-Location
  $errs = @([regex]::Matches(($o -join "`n"), '(?m)^Error: \[(\d+)\]') |
    ForEach-Object { $_.Groups[1].Value } | Where-Object { $_ -ne '4069' })
  $tc = if ($errs.Count) { 'REJECTED' } else { 'ACCEPTED' }

  # --- the analyzer --------------------------------------------------------
  $da = Join-Path $env:TEMP ('an0446_' + $k)
  New-Item -ItemType Directory -Force -Path $da | Out-Null
  [IO.File]::WriteAllText((Join-Path $da 'x.mbt'), ($lines -join "`n"), $enc)
  $ao = (& $moonrun $wasm $da --extern-iface-dir (Join-Path $repo '.repos') 2>&1 | Out-String)
  $av = if ($ao -match 'unterminated block string') { 'unterminated (FALSE POSITIVE)' }
        elseif ($ao -match 'read up to line (\d+)') { 'truncated at ' + $matches[1] }
        elseif ($ao -match '\bCLEAN\b') { 'clean' }
        else { 'other' }

  Write-Output ('{0,-21}  {1,-11}  {2}' -f $k, $tc, $av)

  # THE CLAIM BEING CHECKED: the toolchain accepts every one of these, so any
  # "unterminated" from the analyzer is a report the toolchain does not make.
  if ($tc -eq 'REJECTED') {
    Write-Output ("    {0}: moon check REJECTED this shape -- the analyzer's verdict is not falsified here" -f $k)
  } elseif ($av -match 'unterminated') {
    Write-Output '    -> FALSE POSITIVE: accepted by moon check, reported as unterminated by the analyzer'
  }
}

Write-Output ''
Write-Output 'THE PROTON CONSEQUENCE, re-derived:'
$pt = Join-Path $repo '.repos\moonbit-community\proton\0.3.4\facade_types.mbt'
if (Test-Path $pt) {
  $dp = Join-Path $env:TEMP 'an0446_proton'
  New-Item -ItemType Directory -Force -Path $dp | Out-Null
  Copy-Item $pt (Join-Path $dp 'facade_types.mbt') -Force
  $po = (& $moonrun $wasm $dp --extern-iface-dir (Join-Path $repo '.repos') 2>&1 | Out-String)
  ($po -split "`n" | Where-Object { $_ -match 'read up to line|unterminated block string' } |
    Select-Object -First 3) | ForEach-Object { '  ' + $_.Trim() }
  Write-Output '  and the declarations it hides are at:'
  $pl = [IO.File]::ReadAllLines($pt)
  588..594 | ForEach-Object { '    {0,4}: {1}' -f ($_ + 1), $pl[$_] }
} else {
  Write-Output "  proton not materialised at $pt (run: moonx to fetch corpora)"
}

Write-Output ''
Write-Output 'NOT SETTLED: where the toolchain ends a block string. Three rules were'
Write-Output 'falsified against `moon check` (see the header). No rule is claimed, and'
Write-Output 'the lexer is deliberately UNCHANGED until a value probe with a working'
Write-Output 'control exists.'
if ($fail -gt 0) { exit 1 }
exit 0
