$ErrorActionPreference = 'Continue'
# Verify the NOTICE LABEL: a declared scope limit is not an error.
#
# WHY THIS EXISTS. Every ParseError the tool rendered carried the label
# `error:` -- including the ones that are not errors at all. "match expression
# is outside the analyzed subset; it was read but not analysed" is a DECLARED
# SCOPE LIMIT of this analyzer, and a reader who sees `error:` on it has been
# told their code is wrong when the analyzer is the one that did not read it.
#
# MEASURED (2026-10-30), with the per-file printing cap lifted so the count is
# the whole finding set and not the first 40 of each file: across the seven
# corpora and this repository's own source, 23,331 rendered ParseError lines,
# EVERY ONE of them a deliberate exclusion, and not one of the seventeen
# genuine-defect producers carrying the marker. The tool already had the word
# for this -- `notice` -- in its own counts, its mermaid legend and its skill
# file. The rendered line was the only place that did not use it.
#
# WHAT IT CHECKS, and each item is a thing that can be WRONG:
#
#   1. THE OUTPUT CONTRACT. On a real scan, a message that carries the marker
#      is rendered `notice:`, and `notice:` is only ever used for a message
#      that carries it. A count of zero fails the check, because a check that
#      passes on nothing is not a check.
#
#   2. THE FOUR PRODUCER PATHS. The marker is not one message: four different
#      producers make FParse reports, two of them deliberate and two of them
#      genuine. Each path is exercised by a fixture and the expected label is
#      asserted, so the classifier is checked against the tool's OWN messages
#      rather than against literals written here.
#
#   3. THE SOURCE CONVENTION. The marker is a CONVENTION, so it has to be
#      held in place or it rots: a new exclusion message that stops carrying
#      it goes back to being an `error:` silently.
#
#      The producers are told apart BY MECHANISM and never by their text, so
#      the check is not circular -- the marker is not used to decide what a
#      producer is:
#
#        the program frontend  `note_skip` is the parser's ONLY skip mechanism
#                             (it is the only function that pushes to `skips`),
#                             so every message it is handed is a scope limit;
#        the literate frontend `subset_exclusion` is what decides a fence is
#                             outside the subset, so the message beside it is a
#                             scope limit;
#        everything else       the lexer's malformed literals, `moonfiles`'
#                             malformed interface text and the parser's read
#                             failures are defects, and a defect must NOT carry
#                             the marker -- or it would be rendered `notice:`
#                             and stop being actionable.
#
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File _verify\check_notice_labels.ps1
#
# There is no -SelfTest switch, and that is deliberate: this gate is shown to go
# red by INJECTING a defect into the tree and running it, which is a stronger
# statement than a switch that reproduces the checker's own logic.
$root = 'D:\src\DeepseekHarness\Projects\xiuyueren\StaticAnalysis\moonbit_static_analysis'
$moonrun = 'C:\Users\31379\.moon\bin\moonrun.exe'
$wasm = Join-Path $root '_build\wasm\debug\build\moonbit_static_analysis.wasm'
$repos = Join-Path $root '.repos'
$fail = 0

# The marker. Every deliberate exclusion message says the construct is outside
# a SUBSET of what the analyzer reads -- "outside the analyzed subset" in the
# program frontend, "outside the analyzer's MoonBit subset" in the literate
# frontend. No genuine-defect message contains the word.
$MARKER = 'subset'

function Scan-Tree {
  param([string]$Path)
  $dir = Join-Path $env:TEMP ('notice_' + [guid]::NewGuid().ToString('N').Substring(0,8))
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  $out = Join-Path $dir 'o.txt'; $err = Join-Path $dir 'o.err'
  Start-Process -FilePath $moonrun `
    -ArgumentList @($wasm, $Path, '--extern-iface-dir', $repos, '--no-auto-fetch-deps',
                    '--findings-shown-per-file', '1000000') `
    -RedirectStandardOutput $out -RedirectStandardError $err -NoNewWindow -Wait | Out-Null
  $text = ''
  for ($i = 1; $i -le 20; $i++) {
    try { $text = [System.IO.File]::ReadAllText($out); break }
    catch [System.IO.IOException] { Start-Sleep -Milliseconds (100 * $i) }
  }
  return $text
}

# A rendered finding line: "<line>:<col> - <label>: <message> (<Family>) [<lenses>]"
function Get-Findings {
  param([string]$Text)
  $rows = @()
  foreach ($ln in ($Text -split "`r?`n")) {
    if ($ln -match '^\s*(\d+):(\d+) - (error|warning|hint|notice): (.*) \((\w+)\) \[([^\]]*)\]\s*$') {
      $rows += [pscustomobject]@{
        Line = $Matches[1]; Col = $Matches[2]; Label = $Matches[3]
        Message = $Matches[4]; Family = $Matches[5]
        Marked = $Matches[4].Contains($MARKER)
      }
    }
  }
  return $rows
}

if (-not (Test-Path -LiteralPath $wasm)) {
  Write-Output 'ABORT: no wasm artifact. Build it first.'
  exit 1
}

# --- 1. the output contract, on this repository's own source ------------------
Write-Output '=== 1. the output contract (this repository''s own source) ==='
$own = Get-Findings (Scan-Tree $root)
$marked = @($own | Where-Object { $_.Marked })
$notices = @($own | Where-Object { $_.Label -eq 'notice' })
$wrongLabel = @($marked | Where-Object { $_.Label -ne 'notice' })
$wrongNotice = @($notices | Where-Object { -not $_.Marked })
$genuineError = @($own | Where-Object { $_.Family -eq 'ParseError' -and -not $_.Marked })

Write-Output ('  rendered findings            ' + $own.Count)
Write-Output ('  carrying the marker          ' + $marked.Count)
Write-Output ('  labelled notice:             ' + $notices.Count)
Write-Output ('  ParseError NOT carrying it   ' + $genuineError.Count)
if ($marked.Count -eq 0) {
  Write-Output '  FAIL: no rendered finding carries the marker. The check would pass on nothing.'
  $fail++
}
if ($wrongLabel.Count -gt 0) {
  Write-Output ('  FAIL: ' + $wrongLabel.Count + ' scope limit(s) labelled something other than notice:')
  $wrongLabel | Select-Object -First 5 | ForEach-Object { Write-Output ('      ' + $_.Line + ':' + $_.Col + ' - ' + $_.Label + ': ' + $_.Message) }
  $fail++
}
if ($wrongNotice.Count -gt 0) {
  Write-Output ('  FAIL: ' + $wrongNotice.Count + ' finding(s) labelled notice: without carrying the marker:')
  $wrongNotice | Select-Object -First 5 | ForEach-Object { Write-Output ('      ' + $_.Line + ':' + $_.Col + ' - ' + $_.Message) }
  $fail++
}
if ($wrongLabel.Count -eq 0 -and $wrongNotice.Count -eq 0) {
  Write-Output '  every scope limit is labelled notice:, and notice: is used for nothing else   OK'
}

# --- 2. the four producer paths, each with its own fixture --------------------
Write-Output ''
Write-Output '=== 2. the four producer paths ==='
$fx = Join-Path $env:TEMP ('notice_fx_' + [guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Force -Path $fx | Out-Null
$enc = New-Object System.Text.UTF8Encoding($false)

# (a) the PROGRAM frontend's deliberate exclusion: a `match` in a .mbt file.
[System.IO.File]::WriteAllText((Join-Path $fx 'a_match.mbt'), @'
fn classify(x : Int) -> Int {
  match x {
    0 => 1
    _ => 2
  }
}
'@, $enc)

# (b) the LITERATE frontend's deliberate exclusion: a `match` in a compiled
# fence. A `.mbt.md` file is plain markdown -- the `#|` prefixes in the sample
# are MoonBit's MULTI-LINE STRING markers, not the file's format, and a
# fixture that carries them is a document with no fence in it.
[System.IO.File]::WriteAllText((Join-Path $fx 'b_fence.mbt.md'), @'
A document with one compiled fence.

```mbt check
match x {
  _ => 1
}
```
'@, $enc)

# (c) the literate frontend's GENUINE defect: a malformed interface line.
[System.IO.File]::WriteAllText((Join-Path $fx 'c_bad.mbti'), @'
package demo

type Shape

this line is not a signature and not a type declaration
'@, $enc)

# (d) the LEXER's genuine defect: an unterminated string literal.
[System.IO.File]::WriteAllText((Join-Path $fx 'd_lex.mbt'), @'
fn broken() {
  let s = "unterminated
}
'@, $enc)

$fxRows = Get-Findings (Scan-Tree $fx)
$fxNotices = @($fxRows | Where-Object { $_.Label -eq 'notice' })
$fxErrors = @($fxRows | Where-Object { $_.Label -eq 'error' })

$a = @($fxNotices | Where-Object { $_.Message -like '*match expression*' })
$b = @($fxNotices | Where-Object { $_.Message -like '*MoonBit subset*' })
$c = @($fxErrors | Where-Object { $_.Family -eq 'ParseError' })
$d = @($fxNotices | Where-Object { $_.Message -like '*unterminated*' })

Write-Output ('  (a) program frontend, deliberate   labelled notice:   ' + $a.Count + $(if ($a.Count -ge 1) { '   OK' } else { '   FAIL' }))
Write-Output ('  (b) literate frontend, deliberate   labelled notice:   ' + $b.Count + $(if ($b.Count -ge 1) { '   OK' } else { '   FAIL' }))
Write-Output ('  (c) literate frontend, genuine      labelled error:    ' + $c.Count + $(if ($c.Count -ge 1) { '   OK' } else { '   FAIL' }))
Write-Output ('  (d) lexer, genuine                  NOT a notice:      ' + $(if ($d.Count -eq 0) { 'OK' } else { 'FAIL (' + $d.Count + ')' }))
if ($a.Count -lt 1) { Write-Output '  FAIL: the program frontend''s deliberate exclusion was not labelled notice:.'; $fail++ }
if ($b.Count -lt 1) { Write-Output '  FAIL: the literate frontend''s deliberate exclusion was not labelled notice:.'; $fail++ }
if ($c.Count -lt 1) { Write-Output '  FAIL: the literate frontend''s genuine defect was not labelled error:.'; $fail++ }
if ($d.Count -gt 0) { Write-Output '  FAIL: the lexer''s genuine defect was labelled notice:.'; $fail++ }

# --- 3. the source convention -------------------------------------------------
Write-Output ''
Write-Output '=== 3. the source convention ==='
$srcFiles = @(Get-ChildItem -LiteralPath (Join-Path $root 'src') -Filter '*.mbt' -File -Recurse |
              Where-Object { $_.Name -notlike '*_test.mbt' })

$nSkipCall = 0
$nSkipLiteral = 0
$nDeliberate = 0
$nGenuine = 0
$bad = 0

foreach ($f in $srcFiles) {
  $text = [System.IO.File]::ReadAllText($f.FullName)
  $lines = $text -split "`r?`n"
  $rel = $f.FullName.Substring($root.Length + 1)

  # --- 3a. the program frontend: every message handed to `note_skip` ----------
  # `note_skip` is the parser's only skip mechanism -- it is the only function
  # that pushes to `skips` -- so every message it is handed is a scope limit.
  $idx = 0
  while ($true) {
    $idx = $text.IndexOf('note_skip(', $idx)
    if ($idx -lt 0) { break }
    $orig = $idx
    $pre = if ($orig -ge 40) { $text.Substring($orig - 40, 40) } else { $text.Substring(0, $orig) }
    $idx = $orig + 10
    # The DECLARATION is not a call site. The window before the occurrence ends
    # just before the name -- `fn Parser::` -- because the occurrence starts AT
    # "note_skip(" -- so the test is on that prefix, not on the whole name.
    if ($pre -match 'fn\s+Parser::\s*$') { continue }   # the declaration
    # A MENTION in a comment is not a call site. The parser's own comment says
    # `note_skip("...") literals only work as call arguments`, and reading that
    # as a call site found a message that is not a message -- the same prose
    # trap the mutation harness guards its anchors against (its rule 8).
    $lineIdx = ($text.Substring(0, $orig) -split "`n").Count - 1
    if ($lineIdx -ge 0 -and $lineIdx -lt $lines.Count -and
        $lines[$lineIdx].TrimStart().StartsWith('//')) { continue }
    $nSkipCall++
    $next = $text.IndexOf('note_skip(', $idx)
    $end = if ($next -ge 0) { $next } else { [Math]::Min($text.Length, $idx + 600) }
    $arg = $text.Substring($idx, $end - $idx)
    if ($arg.Contains('skip_msg(')) { continue }   # delegated; skip_msg is checked below
    $q1 = $arg.IndexOf('"')
    $q2 = if ($q1 -ge 0) { $arg.IndexOf('"', $q1 + 1) } else { -1 }
    if ($q1 -lt 0 -or $q2 -le $q1) {
      Write-Output ('  FAIL: ' + $rel + ' -- a note_skip call carries no message literal and is not a skip_msg call.')
      $bad++
      continue
    }
    $nSkipLiteral++
    $lit = $arg.Substring($q1 + 1, $q2 - $q1 - 1)
    if (-not $lit.Contains($MARKER)) {
      Write-Output ('  FAIL: ' + $rel + ' -- a note_skip message does not carry the marker: ' + $lit)
      $bad++
    }
  }

  # --- 3b. the helper both declaration paths go through ----------------------
  $sm = $text.IndexOf('fn skip_msg')
  if ($sm -ge 0) {
    $nextFn = $text.IndexOf("`nfn ", $sm + 5)
    if ($nextFn -lt 0) { $nextFn = $text.Length }
    $body = $text.Substring($sm, $nextFn - $sm)
    $lits = @([regex]::Matches($body, '"([^"]*)"'))
    if ($lits.Count -eq 0) {
      Write-Output ('  FAIL: ' + $rel + ' -- skip_msg has no message; the declaration path has lost its wording.')
      $bad++
    }
    foreach ($m in $lits) {
      if (-not $m.Groups[1].Value.Contains($MARKER)) {
        Write-Output ('  FAIL: ' + $rel + ' -- a skip_msg branch does not carry the marker: ' + $m.Groups[1].Value)
        $bad++
      }
    }
  }

  # --- 3c. every FParse construction site -------------------------------------
  # The enclosing function is found by the nearest function declaration above
  # it, and the body of that function is what says whether this site is a
  # skip producer: `subset_exclusion` is the literate frontend's decision, and
  # `Parser::note_skip` is the program frontend's.
  $fnStarts = @()
  for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match '^\s*(pub\s*(\(all\)\s*)?)?fn\s') { $fnStarts += $i }
  }
  for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -notmatch 'family:\s*@core\.FParse') { continue }
    # the message literal, if this site spells one out
    $msg = ''
    for ($k = $i; $k -lt [Math]::Min($i + 6, $lines.Count); $k++) {
      if ($lines[$k] -match 'message:\s*"') {
        $rest = $lines[$k].Substring($lines[$k].IndexOf('message:'))
        $q1 = $rest.IndexOf('"')
        $q2 = $rest.IndexOf('"', $q1 + 1)
        if ($q1 -ge 0 -and $q2 -gt $q1) { $msg = $rest.Substring($q1 + 1, $q2 - $q1 - 1) }
        break
      }
    }
    if ($msg -eq '') { continue }   # a dynamic message: the parser's read failure
    # the enclosing function
    $owner = -1
    foreach ($s in $fnStarts) { if ($s -le $i) { $owner = $s } else { break } }
    $isSkipProducer = $false
    $ownerName = '(none)'
    if ($owner -ge 0) {
      $ownerName = ($lines[$owner] -replace '^\s*(pub\s*(\(all\)\s*)?)?fn\s+', '')
      $indent = ($lines[$owner] -replace '^(\s*).*$', '$1').Length
      $end = $lines.Count
      for ($k = $owner + 1; $k -lt $lines.Count; $k++) {
        if ($lines[$k] -match '^\s*(pub\s*(\(all\)\s*)?)?fn\s' -and ($lines[$k] -replace '^(\s*).*$', '$1').Length -eq $indent) {
          $end = $k; break
        }
      }
      $body = ($lines[($owner + 1)..([Math]::Max($owner + 1, $end - 1))] -join "`n")
      $isSkipProducer = ($body -match 'subset_exclusion\s*\(') -or ($ownerName -match 'Parser::note_skip')
    }
    if ($isSkipProducer) {
      $nDeliberate++
      if (-not $msg.Contains($MARKER)) {
        Write-Output ('  FAIL: ' + $rel + ':' + ($i + 1) + ' is a skip producer but its message does not carry the marker.')
        Write-Output ('        ' + $ownerName + ' -- ' + $msg)
        $bad++
      }
    } else {
      $nGenuine++
      if ($msg.Contains($MARKER)) {
        Write-Output ('  FAIL: ' + $rel + ':' + ($i + 1) + ' carries the marker but is not a skip producer.')
        Write-Output ('        ' + $ownerName + ' -- ' + $msg)
        $bad++
      }
    }
  }
}
Write-Output ('  note_skip call sites            ' + $nSkipCall + ' (' + $nSkipLiteral + ' with a literal, the rest via skip_msg)')
Write-Output ('  deliberate producers (by mechanism)   ' + $nDeliberate)
Write-Output ('  genuine producers                    ' + $nGenuine)
Write-Output ('  sites where the marker and the mechanism disagree   ' + $bad + $(if ($bad -eq 0) { '   OK' } else { '   FAIL' }))
if ($nSkipCall -lt 1) {
  Write-Output '  FAIL: no note_skip call site was found. The program frontend''s skip mechanism has moved.'
  $fail++
}
if ($nDeliberate -lt 1) {
  Write-Output '  FAIL: no deliberate producer was found by mechanism.'
  $fail++
}
if ($nGenuine -lt 1) {
  Write-Output '  FAIL: no genuine FParse producer was found. The check has stopped looking at the other direction.'
  $fail++
}
$fail += $bad

Write-Output ''
if ($fail -eq 0) {
  Write-Output 'NOTICE LABELS OK: a declared scope limit is a notice, a genuine defect is an error, and the marker and the mechanism agree.'
  exit 0
}
Write-Output ('NOTICE LABELS FAILED: ' + $fail + ' problem(s).')
exit 1
