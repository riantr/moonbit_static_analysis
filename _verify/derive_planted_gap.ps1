# Derive a LIVE planted gap for `_verify/grammar_probe_control.ps1`, at RUN time,
# from the pinned corpora -- a file this frontend genuinely cannot read.
#
# WHY THIS EXISTS. The control's `ctrl_real_gap` row has been moved FOUR times:
# a lambda with an explicit parameter type, then `1..<=n`, then `value[:]`, then
# an anonymous `fn` as a call argument. Each move happened because a real
# increment closed the row, which is the control working -- and each one cost a
# hand-built fixture and a full release-gate round trip to find. A hardcoded row
# is a countdown, and the fourth strike is also what made it obvious the next one
# could not be found by hand: after 0467, ~26 known forms and ~20 hand-written
# candidates yielded ZERO live gaps.
#
# So the row is no longer a construct. It is a SLOT, and the source of the row is
# derived at run time from whatever the corpora still contain. The control's
# ASSERTIONS are unchanged by this file -- same five checks, same strings. What
# changed is where the row comes from.
#
# HOW IT WORKS -- A DESCENT, NOT A CHOICE.
#
# The first version of this file PICKED one granularity by a textual test: if the
# file mentions an external package (`import` or `@pkg`), take the top-level item
# enclosing the blocker; otherwise take the whole file. One candidate per file,
# and the other granularity was never tried.
#
# 0488 measured why that stopped working. The pinned corpora had shrunk to four
# unreadable files, all in `async`, and the derivation returned NOTHING:
#
#   async     PARTIAL files = 4
#   async     skip file   MOON-BAD    src/http/utils.mbt:23
#
# One skip line for four files. The other three were skipped SILENTLY -- the
# `continue` on the `@`-test had no log line -- so the log read like "one file
# was tried" when in fact three were dropped without a trace. And the one that
# WAS tried failed for a reason the old code could not see: the whole file
# mentions `BadRequest`, which is defined in a SIBLING file of the same package,
# so the file is not a legal standalone program. The file-level candidate is
# rejected for a reason that has nothing to do with the gap inside it.
#
# The method is now a DESCENT through the units that contain the blocker, and
# every unit is tried on its own merits:
#
#   1. `file` -- the whole file.
#   2. `item` -- the top-level item ENCLOSING the blocker.
#   3. `sub`  -- a definition NESTED inside that item, lifted to column 0.
#   4. `item` -- the other top-level items, AFTER the blocker first.
#   5. `item` -- the other top-level items BEFORE the blocker.
#
# Step 3 is the "plant from a self-contained sub-item even when the enclosing
# item is not" rule: an item that mentions an external package is not a legal
# standalone program, so instead of giving up on the file the derivation looks
# INSIDE it for a piece that stands on its own. Steps 4 and 5 exist because a
# PARTIAL file means the reader STOPPED at the blocker: everything after it was
# never read, so a later item is an UNVERIFIED region that may still hold a gap
# even after the enclosing item is fixed.
#
# => MEASURED YIELD PER LAYER, 2026-10-19, on the tree that shipped as f9019e4
# + 0488. All 107 candidates in the four unreadable `async` files were scored
# (MOON-OK AND SELF-FAIL) at every granularity:
#
#   file  --  0 usable of   4. Every whole file mentions a name from a sibling
#            file, so none is a legal standalone program.
#   item  --  1 usable of  95. `src/http/utils.mbt:16-31`, `fn encode_int` --
#            MOON-OK and SELF-FAIL, and it holds the for-header with a
#            non-empty update clause that this frontend cannot read.
#   sub   --  0 usable of   8. A nested definition lifted to column 0 refers to
#            the enclosing item's locals, so it is never a legal standalone
#            program on its own.
#
# So the layer that pays is the ENCLOSING ITEM, and the reason is the same in
# every file: the unreadable construct lives in an item that happens to be
# self-contained, inside a file that is not. The `sub` layer is implemented
# because the rule calls for it and because it is the only layer that can find a
# gap in an item that references an external package -- it simply contributes
# nothing today, which is a measurement, not an assumption.
#
# => 判据: A CANDIDATE IS REJECTED ON ITS OWN MERITS, AND EVERY REJECTION IS
# LOGGED. A skip that prints nothing is indistinguishable from a candidate that
# was never generated, and the 0488 run showed exactly that: three of four
# files vanished without a trace, and the log made the search look smaller than
# it was. The log now carries one line per candidate, with the reason.
#
# => 判据: THE HONEST ENDPOINT IS STILL A FAILURE. When every layer is
# exhausted, this returns Found = $false and the control FAILS, saying so. It
# must never quietly fall back to a hardcoded row or skip the assertion -- a
# control that passes because it stopped looking is the exact defect the control
# exists to catch, wearing the control's own clothes.
$ErrorActionPreference = 'Continue'

# --- the pinned corpora, in the order they are tried -------------------------
# `core` first, and the reason is measured rather than guessed. The six corpora
# below were fully readable by 0494 -- `async` reached 419/419 and the other five
# had no PARTIAL file at all -- so the derivation searched them and found
# NOTHING, and the grammar probe control FAILED with its own designed message:
#
#   - no corpus file is both legal MoonBit and unread by this frontend, so there
#     is no row left that can prove the REAL GAP tally fires.
#
# That is the control working. It says the honest endpoint is a FAILURE, and it
# is not a licence to weaken the assertions or to hardcode a replacement row.
# The control names the other option itself: "pin a NEW corpus that still
# contains a gap this frontend cannot read". So `moonbitlang/core` was added,
# and it is pinned by VERSION (0.1.20260920+7d59c7ec9 -- a build-stamped
# version, so it cannot drift under you the way a `@latest` would).
#
# MEASURED YIELD OF THE NEW CORPUS, on the 0494 tree: 74 PARTIAL files, and the
# FIRST candidate that survives the descent was `string/quickcheck_test.mbt:138`,
# the top-level
#
#     let qc_boundary_chars : Array[Char] = [
#       ..., '\u{7F}', ..., '\u{FFFF}', '\u{10000}', '\u{1F600}', '\u{10FFFF}',
#     ]
#
# The WHOLE FILE is rejected first (it mentions `@quickcheck`), and the ITEM is
# accepted: it is a `let` of nothing but char literals, so `moon check` calls it
# legal MoonBit with 0 errors, and the frontend cannot read it. The gap was
# PRECISE and was measured on the construct itself, not inferred from the file:
#
#     '\u{7F}'      (2 hex digits)  read
#     '\u{FFFF}'    (4 hex digits)  read
#     '\u{FFFE}'    (4 hex digits)  read
#     '\u{10000}'   (5 hex digits)  NOT read -> "character literal must hold exactly one character"
#     '\u{1F600}'   (5 hex digits)  NOT read
#     '\u{10FFFF}'  (6 hex digits)  NOT read
#     '\u{1FFFF}'   (5 hex digits)  NOT read
#     '\u{20000}'   (5 hex digits)  NOT read
#
# So the escape reader takes at most FOUR hex digits, which is the BMP. A
# supplementary-plane escape -- U+10000 and above, the range that needs a
# surrogate pair in UTF-16 -- is past the end of what it reads. `moon check`
# accepts all of them.
#
# => 0496 CORRECTED THE PARAGRAPH ABOVE, AND THE MOVE IS THE FIFTH. The escape
# gap was REAL, and 0496 CLOSED it -- the reader now counts CHARACTERS instead of
# UTF-16 CODE UNITS, so `'\u{1F600}'` is one character and is read. The sentence
# "the escape reader takes at most FOUR hex digits" was the WRONG EXPLANATION of a
# right observation: the reader took as many digits as the literal had, and the
# refusal came from a UTF-16 COUNT. The correction is written in the 0494 block of
# NARRATIVE.md beside the original claim, and the same correction is in the
# `lexer.mbt` source.
#
# THE GAP MOVED, AND THE CORPUS DID NOT RUN OUT. On 0496's tree `core` still has
# 55 PARTIAL files and the other six corpora have NONE, so `core` is the only
# place a planted gap can come from -- and the row that survives the descent
# there is now:
#
#     core  range/quickcheck_test.mbt:69   item 127-158
#           fn anchors(min : BigInt, max : BigInt) -> Array[BigInt] { ... }
#
# MOON-OK (`moon check` reports 0 errors and one `unused_value` warning) and
# SELF-FAIL (the scanner reports `parsed=0`, 13 findings withheld), because the
# item uses the `N` SUFFIX on an integer literal -- `0N`, `1N`, `-1N`, `2N` --
# which is the family the 0494 inventory listed as "7 `undefined name 'N'`".
# `moon check` accepts it.
#
# AND THE MOVE COST THE SEARCH ITS BUDGET, WHICH IS THE PART THAT ACTUALLY
# MATTERED. Every previous move was cheap because the row sat near the FRONT of
# the search order. It does not any more: with `string/quickcheck_test.mbt`
# whole, the search walks `string/internal/regex_parser/parser.mbt`,
# `sorted_set/set.mbt`, `sorted_map/map.mbt`, `set/linked_hash_set.mbt` and
# `ref/ref.mbt` first -- 122 checks -- before it reaches
# `range/quickcheck_test.mbt` at check 123.
#
# The check cap was 12, and it was calibrated to a corpus state where the gap sat
# at check ~4. So 0496 did NOT run out of gaps: the SEARCH ran out of BUDGET, and
# the control reported the first of those two things rather than the true one.
# The cap is now 500, and that number is MEASURED rather than chosen: the gap is
# at 123 and one check costs ~0.3s (`moon check` plus a scanner run on a
# one-file package), so the whole corpus can be walked in under three minutes.
# A cap that can be reached is a BUDGET; a cap that stops the search short of a
# gap that is still there is a FALSE RED, and a false red is the one thing this
# control must not be.
#
# The other corpora stay in the list, in the order they were tried, because a
# corpus that gains a gap later must be found without touching this file.
$script:GP_CORPORA = [ordered]@{
  'core'     = 'moonbitlang\core\0.1.20260920+7d59c7ec9'
  'async'    = 'moonbitlang\async\0.22.4'
  'proton'   = 'moonbit-community\proton\0.3.4'
  'moui'     = 'wzzc-dev\moui\0.1.12'
  'labeler'  = 'riantr\moonbit_labeler\0.2.13'
  'image'    = 'riantr\moonbit_image\0.3.7'
  'contract' = 'moonbit-community\proton_contract\0.3.4'
}

# Column-0 openers of a top-level item. ASCII ONLY: a BOM-less .ps1 is read as
# ANSI on Windows PowerShell 5.1, so a non-ASCII character in a pattern is a
# silent trap that has cost this repo a whole settle cycle before.
#
# `async` is in the list because `pub async fn request(` at
# `async 0.22.4 src/http/request.mbt:84` was NOT recognised as an item opener
# until 2026-10-19. The damage was a wrong unit: the item enclosing the
# blocker at line 59 was computed as lines 55-212 (everything to the end of the
# file) instead of 55-72. It happened not to change today's outcome, because
# `resolve_host` mentions `@string` either way, but an item extent that runs to
# the end of the file is exactly the kind of unit whose "@-test" is then
# answering a question nobody asked.
$script:GP_OPENER = '^(pub(\([A-Za-z0-9_,\s]*\))?\s+)?(async\s+)?(fn|struct|enum|impl|type|let|const|extern)\b'

# Openers of a NESTED definition -- a real item, not a binding statement. `let`
# is deliberately absent: a nested `let` is a statement, and lifting it to
# column 0 yields a snippet that refers to the enclosing item's locals, which
# is why the measured `sub` yield is zero.
$script:GP_NESTED = '^\s+(pub(\([A-Za-z0-9_,\s]*\))?\s+)?(async\s+)?(fn|struct|enum|type|const)\b'

# Resolved ONCE, at file scope. `$PSScriptRoot` read from inside the function
# would depend on which script dot-sourced it, so the paths are bound where
# `$PSScriptRoot` unambiguously means this file's directory.
$script:GP_ROOT    = Split-Path -Parent $PSScriptRoot
$script:GP_REPOS   = Join-Path $script:GP_ROOT '.repos'
$script:GP_WASM    = Join-Path $script:GP_ROOT '_build\wasm\debug\build\moonbit_static_analysis.wasm'
$script:GP_MOON    = 'C:\Users\31379\.moon\bin\moon.exe'
$script:GP_MOONRUN = 'C:\Users\31379\.moon\bin\moonrun.exe'

# A short, readable name for a unit, for the log: the first line of the unit,
# trimmed and cut to 44 characters. The first line of a MoonBit item is its
# signature, so this is the name the reader will recognise.
function Get-GpHead([string]$line) {
  $t = $line.Trim()
  if ($t.Length -gt 44) { $t = $t.Substring(0, 44) + '...' }
  return $t
}

# Read a corpus file as UTF-8, and RETRY while another process holds it open.
#
# THE ENCODING WAS WRONG, AND IT WAS WRONG INVISIBLY. `File.ReadAllLines` does
# NOT read UTF-8: its default encoding is `Encoding.Default` -- the ANSI
# codepage of the machine -- and it only switches to UTF-8 when the file
# carries a BOM. The pinned corpus files have no BOM, so every non-ASCII byte
# in them was decoded with the ANSI codepage (GBK on this machine) and
# re-encoded on the way into the probe package.
#
# That is not cosmetic. A candidate carrying an em dash in a doc comment came
# out as bytes that are NOT valid UTF-8, so `moon check` refused the file with
# [3001] "Could not read the file because it contains invalid UTF-8 streams"
# (MOON-BAD) while this frontend read it happily (SELF-OK). The planted row was
# then NEITHER a gap NOR a too-permissive row, and the control failed on a row
# that had never been one -- and the failure message blamed the corpus.
#
# It was invisible while the planted rows happened to be ASCII. That is the
# whole shape of the defect: a reader that is wrong in a way the data never
# exercises, and a control that cannot see the difference.
#
# THE RETRY IS RULE 9, THE SAME RULE THE MUTATION HARNESS GOT. `ReadAllLines`
# THROWS when another process holds the file open, and the old code caught that
# and skipped the file SILENTLY -- one more unreadable file per locked read, and
# a gap the search could not reach for a reason that had nothing to do with the
# gap. The retry is on the TRANSIENT, not on the verdict: a genuinely unreadable
# file still fails, and the caller still logs the skip.
function Read-CorpusLinesUtf8 {
  param([string]$Path, [int]$Tries = 12)
  $utf8 = New-Object System.Text.UTF8Encoding($false)
  for ($i = 1; $i -le $Tries; $i++) {
    try {
      return [System.IO.File]::ReadAllLines($Path, $utf8)
    } catch [System.IO.IOException] {
      if ($i -eq $Tries) { throw }
      Start-Sleep -Milliseconds (50 * $i)
    }
  }
}

# Enumerate the units that CONTAIN the blocker, in the order they are tried.
#
# Returns an ordered list of { Mode, Start, End, Text, Label }. `Start`/`End`
# are 0-based line indices into the file; `Label` names the unit for the log.
function Get-GapCandidates {
  param([string[]]$Src, [int]$BlockerIndex)

  $cands = New-Object System.Collections.ArrayList
  $n = $Src.Length

  # 1. the whole file
  [void]$cands.Add([pscustomobject]@{
    Mode = 'file'; Start = 0; End = $n - 1
    Text = ($Src -join "`n"); Label = 'whole file'
  })

  # --- top-level item extents ------------------------------------------------
  $tops = @()
  for ($i = 0; $i -lt $n; $i++) { if ($Src[$i] -match $script:GP_OPENER) { $tops += $i } }
  $ext = @{}
  for ($t = 0; $t -lt $tops.Count; $t++) {
    $s = $tops[$t]
    $e = if ($t + 1 -lt $tops.Count) { $tops[$t + 1] - 1 } else { $n - 1 }
    $ext[$t] = @($s, $e)
  }

  # the item that encloses the blocker
  $enc = -1
  for ($t = 0; $t -lt $tops.Count; $t++) {
    if ($tops[$t] -le $BlockerIndex) { $enc = $t } else { break }
  }

  if ($enc -ge 0) {
    $es = $ext[$enc][0]
    $ee = $ext[$enc][1]

    # 2. the enclosing item
    [void]$cands.Add([pscustomobject]@{
      Mode = 'item'; Start = $es; End = $ee
      Text = ($Src[$es..$ee] -join "`n")
      Label = ('item {0}-{1} {2}' -f ($es + 1), ($ee + 1), (Get-GpHead $Src[$es]))
    })

    # 3. definitions nested inside the enclosing item, lifted to column 0
    for ($i = $es + 1; $i -le $ee; $i++) {
      if ($Src[$i] -match $script:GP_NESTED) {
        $ind = $Src[$i].Length - $Src[$i].TrimStart().Length
        $j = $i + 1
        while ($j -le $ee) {
          if ($Src[$j].Trim().Length -gt 0) {
            $ind2 = $Src[$j].Length - $Src[$j].TrimStart().Length
            if ($ind2 -le $ind) { break }
          }
          $j++
        }
        $f = $j - 1
        $body = @()
        for ($k = $i; $k -le $f; $k++) { $body += ($Src[$k] -replace ('^' + (' ' * $ind)), '') }
        [void]$cands.Add([pscustomobject]@{
          Mode = 'sub'; Start = $i; End = $f
          Text = ($body -join "`n")
          Label = ('sub {0}-{1} {2}' -f ($i + 1), ($f + 1), (Get-GpHead $Src[$i]))
        })
        $i = $f
      }
    }
  }

  # 4 and 5. the other top-level items. AFTER the blocker first: a PARTIAL file
  # means the reader stopped at the blocker, so everything past it is an
  # UNVERIFIED region that may still hold a gap once the enclosing item is
  # fixed. Before the blocker comes last: that region was already read.
  foreach ($pass in @('after', 'before')) {
    for ($t = 0; $t -lt $tops.Count; $t++) {
      if ($t -eq $enc) { continue }
      $isAfter = ($tops[$t] -gt $BlockerIndex)
      if ($pass -eq 'after' -and -not $isAfter) { continue }
      if ($pass -eq 'before' -and $isAfter) { continue }
      $s = $ext[$t][0]
      $e = $ext[$t][1]
      [void]$cands.Add([pscustomobject]@{
        Mode = 'item'; Start = $s; End = $e
        Text = ($Src[$s..$e] -join "`n")
        Label = ('item {0}-{1} {2}' -f ($s + 1), ($e + 1), (Get-GpHead $Src[$s]))
      })
    }
  }

  return $cands
}

function Get-DerivedPlantedGap {
  # The check budget. It was 12 and it is now 500, and the change is MEASURED
  # rather than chosen: on 0496's tree the planted gap sits at check 123, because
  # the search walks five unreadable files that are all method-heavy before it
  # reaches the one that carries the gap. One check costs ~0.3s, so 500 checks
  # is under three minutes -- affordable, and enough that the budget can never
  # be the reason the control reports a gap that is still there.
  param([int]$MaxChecksPerCorpus = 500)

  $repos = $script:GP_REPOS
  $wasm = $script:GP_WASM
  $moon = $script:GP_MOON
  $moonrun = $script:GP_MOONRUN

  $log = @()
  # `CapHit` says the SEARCH ran out of budget. It is different from "the corpus
  # ran out of gaps", and the control's failure message must not confuse them:
  # one is a fixable budget, the other is a fact worth recording.
  $capHitAny = $false
  $totalChecks = 0
  if (-not (Test-Path -LiteralPath $wasm)) {
    return [pscustomobject]@{ Found = $false; Text = ''; Provenance = ''; Checks = 0; CapHit = $false; CorporaScanned = @(); Log = @('no scanner wasm at ' + $wasm) }
  }

  $base = Join-Path $env:TEMP ('gapderive_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
  New-Item -ItemType Directory -Force -Path $base | Out-Null

  foreach ($k in $script:GP_CORPORA.Keys) {
    $corpus = Join-Path $repos $script:GP_CORPORA[$k]
    if (-not (Test-Path -LiteralPath $corpus)) { $log += ("{0,-9} corpus missing, skipped" -f $k); continue }

    $out = & $moonrun $wasm $corpus --extern-iface-dir $repos 2>&1 | Out-String
    # @() on purpose: a bare PSCustomObject has no .Count on 5.1. This is the same
    # trap the control was written for, and it does not get a pass because the
    # author knows about it.
    $partial = @()
    foreach ($line in ($out -split "`n")) {
      if ($line -match '^PARTIAL\s+\.mbt\s+.*read up to line (\d+),.*\t(.+)$') {
        $partial += [pscustomobject]@{ Line = [int]$Matches[1]; Path = $Matches[2].Trim() }
      }
    }
    $log += ("{0,-9} PARTIAL files = {1}" -f $k, $partial.Count)
    if ($partial.Count -eq 0) { continue }

    $tried = 0
    $capHit = $false
    foreach ($p in $partial) {
      if ($capHit) { break }
      # A failed read must NOT leave the previous file's lines alive, so the read
      # is checked rather than assumed. UTF-8, with a retry while the file is
      # locked -- see `Read-CorpusLinesUtf8`.
      $src = $null
      try { $src = Read-CorpusLinesUtf8 -Path $p.Path } catch { $src = $null }
      if ($null -eq $src) { $log += ("{0,-9} skip file   READ-FAIL {1}" -f $k, $p.Path); continue }
      $n = $p.Line - 1
      if ($n -lt 0 -or $n -ge $src.Length) { continue }

      $rel = $p.Path.Replace($corpus + '\', '').Replace($corpus + '/', '')
      $blocker = $src[$n].Trim()
      $site = ('{0}:{1}' -f $rel, $p.Line)

      foreach ($c in (Get-GapCandidates -Src $src -BlockerIndex $n)) {
        # A snippet that mentions an external package cannot be legal MoonBit on
        # its own, so it is rejected WITHOUT a `moon check` -- a fresh probe
        # package has no way to resolve `@proton_xlog` or `import "async/os"`.
        # That rejection is free, so it does not consume the check cap, and it is
        # LOGGED: the 0488 run dropped three of four files this way without a
        # trace, and the log then read as if only one file had been tried.
        if ($c.Text -match '@[A-Za-z_]') {
          $log += ("{0,-9} skip {1,-5} {2,-24} {3,-10} {4}" -f $k, $c.Mode, $c.Label, 'HAS-AT', $site)
          continue
        }
        if (@($c.Text -split "`n" | Where-Object { $_ -match '^\s*import\b' }).Count -gt 0) {
          $log += ("{0,-9} skip {1,-5} {2,-24} {3,-10} {4}" -f $k, $c.Mode, $c.Label, 'HAS-IMPORT', $site)
          continue
        }

        if ($tried -ge $MaxChecksPerCorpus) {
          $log += ("{0,-9} stopped at the {1}-check cap; unreadable files remain" -f $k, $MaxChecksPerCorpus)
          $capHit = $true
          $capHitAny = $true
          break
        }
        $tried++
        $totalChecks++

        $tag = ('{0}_{1}_{2}' -f $k, ($rel -replace '[^A-Za-z0-9]', '_'), $c.Mode)
        $d = Join-Path $base $tag
        New-Item -ItemType Directory -Force -Path $d | Out-Null
        [IO.File]::WriteAllText((Join-Path $d 'moon.mod'), ("name = `"probe/$tag`"`n`nversion = `"0.1.0`"`n"))
        [IO.File]::WriteAllText((Join-Path $d 'moon.pkg'), "supported_targets = `"+all`"`n")
        [IO.File]::WriteAllText((Join-Path $d 'subject.mbt'), $c.Text)

        Push-Location $d
        $mo = (& $moon check 2>&1 | Out-String)
        Pop-Location
        # NOT '0 errors'. That pattern is unanchored, so `10 errors` matches it and
        # a case with ten type errors scores MOON-OK -- a false REAL GAP. The
        # negative lookbehind is the fix; see grammar_probe.ps1 for the sweep that
        # pins it. A candidate carrying the bug would hand the control a planted
        # row that is not a gap at all, which is the one thing the row must not be.
        $moonOk = (($mo -replace "`r?`n", ' ') -match '(?<!\d)0 errors')

        $so = & $moonrun $wasm $d 2>&1 | Out-String
        $parsed = [regex]::Match($so, 'parsed=(\d+)').Groups[1].Value
        $selfOk = ($parsed -eq '1')

        if ($moonOk -and -not $selfOk) {
          $log += ("{0,-9} USE  {1,-5} {2,-24} {3,-10} {4}" -f $k, $c.Mode, $c.Label, 'MOON-OK/SELF-FAIL', $site)
          return [pscustomobject]@{
            Found = $true; Text = $c.Text; Provenance = $site; Checks = $totalChecks
            CapHit = $false
            CorporaScanned = @($k); Log = $log; BlockedLine = $blocker; Corpus = $k
            Unit = $c.Label; Mode = $c.Mode
          }
        }
        $why = if (-not $moonOk) { 'MOON-BAD' } else { 'SELF-OK' }
        $log += ("{0,-9} skip {1,-5} {2,-24} {3,-10} {4}" -f $k, $c.Mode, $c.Label, $why, $site)
      }
    }
  }

  return [pscustomobject]@{
    Found = $false; Text = ''; Provenance = ''; Checks = $totalChecks
    CapHit = $capHitAny
    CorporaScanned = @(); Log = $log
  }
}

# Standalone run: `powershell -File _verify\derive_planted_gap.ps1` prints the
# derivation, so it can be measured on its own instead of only through the control.
if ($MyInvocation.InvocationName -eq $PSCommandPath) {
  $r = Get-DerivedPlantedGap
  Write-Output '=== derived planted gap ==='
  foreach ($l in $r.Log) { Write-Output ('  ' + $l) }
  Write-Output ''
  Write-Output ('  FOUND = {0}' -f $r.Found)
  if ($r.Found) {
    Write-Output ('  site  = {0}:{1}' -f $r.Corpus, $r.Provenance)
    Write-Output ('  unit  = {0}' -f $r.Unit)
    Write-Output ('  line  = {0}' -f $r.BlockedLine)
    Write-Output ('  chars = {0}' -f $r.Text.Length)
  }
}
