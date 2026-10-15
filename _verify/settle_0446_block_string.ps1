# Settles the block-string closer for 0.4.36, BY VALUE.
#
# Why this instrument and not `moon check`. Every shape of a block string is
# ACCEPTED by `moon check` -- that was measured, nine of nine -- so acceptance
# cannot distinguish one rule from another. It says only "this lexes". The
# question is where the string ENDS, and the only thing that answers it is what
# the toolchain puts in the variable.
#
# THE INSTRUMENT. A main package with `pkgtype(kind: "executable")` in
# `cmd/main/moon.pkg` -- that declaration is what `moon run` requires, and it is
# NOT `is-main = true` in moon.mod (that key is rejected outright) nor
# `moon.pkg.json` (rejected as no longer supported). `moon run src` on a plain
# package says "not a main package". Getting this wrong twice cost two rounds of
# `moon run` that silently proved nothing, which is the usual way a value probe
# turns into a no-op.
#
# THE POSITIVE CONTROL, and it is the point of the exercise: `ctl_badquote` is a
# deliberately unbalanced quote that MUST be rejected. If it ever passes, every
# "accepted" below is meaningless and the run says so. A probe whose control
# does not fire supports no conclusion -- this repository has now produced three
# such probes in two days (the `T::to_json(1)` sweep, the match-without-wildcard,
# and the earlier one), and each one produced a confident wrong answer.
#
# WHAT WAS FALSIFIED BEFORE THIS SCRIPT EXISTED, recorded so nobody re-runs it:
#   "closer = the next line-leading `#|`"          falsified by `two`
#   "closer = a line-leading `#|` with empty rest"  seemed falsified by
#       `no_closer`, which read as "no closer at all yet the tail was code" --
#       but that reading assumed the value was wrong. The value is right: an
#       unclosed block simply ends at EOF. The rule was never falsified; the
#       probe that appeared to falsify it was.
#   The lexer header's own claim, "a `#|` with only whitespace BEFORE it on its
#       line", IS falsified, by `trailing`.
#
# So: the closer is a line-leading `#|` whose REST OF LINE IS BLANK. Everything
# else is content. Segments are trimmed and joined by a single space; the closer
# contributes an empty final segment, which is why every closed value ends in a
# space and no EOF-terminated one does.

$ErrorActionPreference = 'Stop'
$fail = 0
$cases = [ordered]@{}
$expected = [ordered]@{}

function Add-Case([string]$name, [string[]]$markers, [string]$want) {
  $script:cases[$name] = $markers
  $script:expected[$name] = $want
}

# --- the POSITIVE CONTROL -------------------------------------------------
Add-Case 'ctl_badquote' @('  let t = "') 'REJECT'

# --- the rule -------------------------------------------------------------
# No closer at all: ends at EOF, and NO trailing space. This is the case that
# looks like it falsifies the rule and does not.
Add-Case 'no_closer' @('    #|abc', '    #|def') '[abc def]'
# A bare `#|` closes and contributes an empty final segment.
Add-Case 'bare_closer' @('    #|abc', '    #|def', '    #|') '[abc def ]'
# THE case the old header got wrong: trailing text makes it CONTENT.
Add-Case 'trailing' @('    #|AAA', '    #|BBB trailing', '    #|') '[AAA BBB trailing ]'
# Trailing BLANKS are still blank, so this closes.
Add-Case 'blank_closer' @('    #|abc', '    #|def', '    #|   ') '[abc def ]'
# A mid-line `#|` is content, not a closer.
Add-Case 'mid_line' @('    #|one #|two', '    #|') '[one #|two ]'
# Single content line.
Add-Case 'single' @('    #|abc', '    #|') '[abc ]'
# THE SHAPE proton 0.3.4 facade_types.mbt:236-246 actually uses -- content on
# every line, a bare closer at the end. This is the one the old rule broke.
Add-Case 'proton_shape' @('    #|line one {', '    #|  line two', '    #|}', '    #|') '[line one { line two } ]'
# The OLD RULE'S ODD-COUNT FALSE POSITIVE: three markers, which the analyzer used
# to call "unterminated". It must be a perfectly ordinary closed string.
Add-Case 'three_markers' @('    #|aaa', '    #|bbb', '    #|ccc', '    #|') '[aaa bbb ccc ]'

# --- run ------------------------------------------------------------------
$root = Join-Path $env:TEMP ('settle0446_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$enc = New-Object System.Text.UTF8Encoding($false)

foreach ($k in $cases.Keys) {
  $d = Join-Path $root $k
  New-Item -ItemType Directory -Force -Path (Join-Path $d 'src') | Out-Null
  New-Item -ItemType Directory -Force -Path (Join-Path $d 'cmd\main') | Out-Null
  [IO.File]::WriteAllText((Join-Path $d 'moon.mod'), "name = `"settle0446`"`nversion = `"0.1.0`"`n", $enc)
  [IO.File]::WriteAllText((Join-Path $d 'src\moon.pkg'), "", $enc)
  [IO.File]::WriteAllText((Join-Path $d 'cmd\main\moon.pkg'), 'pkgtype(kind: "executable")', $enc)

  $body = @('fn main {', '  let s =')
  $body += $cases[$k]
  $body += @('  println("[" + s + "]")', '}')
  [IO.File]::WriteAllText((Join-Path $d 'cmd\main\main.mbt'), ($body -join "`n"), $enc)

  Push-Location $d
  $o = cmd.exe /c "moon run cmd\main 2>&1"
  Pop-Location
  $raw = (($o -join ' ') -replace '\s+', ' ').Trim()
  $errs = @([regex]::Matches($raw, '(?m)^Error: \[(\d+)\]') |
    ForEach-Object { $_.Groups[1].Value } | Where-Object { $_ -ne '4069' })
  $want = $expected[$k]
  if ($want -eq 'REJECT') {
    $got = if ($errs.Count) { 'REJECT' } else { 'ACCEPT' }
    $ok = ($got -eq 'REJECT')
  } else {
    $got = if ($errs.Count) { 'REJECT(' + ($errs -join ',') + ')' } else { $raw }
    $ok = ($got -eq $want)
  }
  Write-Output ('{0,-14} {1,-26} (want {2}) {3}' -f $k, $got, $want, $(if ($ok) { 'OK' } else { '*** MISMATCH ***' }))
  if (-not $ok) { $fail++ }
}

Write-Output ''
if ($fail -gt 0) {
  Write-Output "ABORT: $fail case(s) did not match. If ctl_badquote is among them the"
  Write-Output 'probe is not working and nothing else in this run means anything.'
  exit 1
}
Write-Output 'GATE OK: the closer is a line-leading `#|` whose rest of line is blank; every other `#|` is content.'
exit 0
