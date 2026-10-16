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
# HOW IT WORKS.
#   1. Scan a pinned corpus for PARTIAL files, and take the FIRST blocker line of
#      each. (Per-file first blocker, not per-message: a message covers several
#      constructs, and sites are not blockers. Same rule as
#      `_verify/rank_0467_first_blocker.ps1`.)
#   2. Build a candidate SNIPPET from that file -- the whole file when it carries
#      no `import` and no `@pkg` ref, otherwise the top-level item enclosing the
#      blocker. A snippet containing `import`/`@` cannot be legal MoonBit on its
#      own, so it is skipped without running `moon check`: a fresh probe package
#      has no way to resolve `@proton_xlog` or `import "async/os"`.
#   3. Score it the way the probe scores a case. A row is usable only when it is
#      MOON-OK (legal MoonBit standalone) AND SELF-FAIL (this frontend cannot read
#      it). Anything else is logged and skipped.
#   4. Take the FIRST usable candidate and stop. Corpora are tried in a fixed
#      order and candidates in the scanner's own PARTIAL order, so for a given
#      tree the derivation is deterministic and a failure reproduces.
#
# MEASURED YIELD, 2026-10-17, on the tree that shipped as 12b38a3 + 0467: 50
# unreadable files across the six corpora, 14 of them textually self-contained,
# 4 usable (labeler labeler.mbt:2741, async addr_utils.mbt:262, async
# gzip_internal/crc32.mbt:53, async http/send.mbt:43). All 14 scored SELF-FAIL,
# which is the point: the candidate pool contains only real gaps, because every
# candidate came out of the scanner's own PARTIAL list.
#
# => 判据: THE HONEST ENDPOINT IS STILL A FAILURE. When the last corpus is read
# whole, this returns Found = $false and the control FAILS, saying so. It must
# never quietly fall back to a hardcoded row or skip the assertion -- a control
# that passes because it stopped looking is the exact defect the control exists
# to catch, wearing the control's own clothes.
$ErrorActionPreference = 'Continue'

# --- the pinned corpora, in the order they are tried -------------------------
# async first: it held 3 of the 4 usable rows when this was measured, and the most
# unreadable files. Order is FIXED so a failure is reproducible.
$script:GP_CORPORA = [ordered]@{
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
$script:GP_OPENER = '^(pub(\([A-Za-z0-9_,\s]*\))?\s+)?(fn|struct|enum|impl|type|let|const|extern)\b'

# Resolved ONCE, at file scope. `$PSScriptRoot` read from inside the function
# would depend on which script dot-sourced it, so the paths are bound where
# `$PSScriptRoot` unambiguously means this file's directory.
$script:GP_ROOT    = Split-Path -Parent $PSScriptRoot
$script:GP_REPOS   = Join-Path $script:GP_ROOT '.repos'
$script:GP_WASM    = Join-Path $script:GP_ROOT '_build\wasm\debug\build\moonbit_static_analysis.wasm'
$script:GP_MOON    = 'C:\Users\31379\.moon\bin\moon.exe'
$script:GP_MOONRUN = 'C:\Users\31379\.moon\bin\moonrun.exe'

function Get-DerivedPlantedGap {
  param([int]$MaxChecksPerCorpus = 12)

  $repos = $script:GP_REPOS
  $wasm = $script:GP_WASM
  $moon = $script:GP_MOON
  $moonrun = $script:GP_MOONRUN

  $log = @()
  if (-not (Test-Path -LiteralPath $wasm)) {
    return [pscustomobject]@{ Found = $false; Text = ''; Provenance = ''; Checks = 0; CorporaScanned = @(); Log = @('no scanner wasm at ' + $wasm) }
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
    foreach ($p in $partial) {
      # A failed read must NOT leave the previous file's lines alive, so the read
      # is checked rather than assumed.
      $src = $null
      try { $src = [IO.File]::ReadAllLines($p.Path) } catch { $src = $null }
      if ($null -eq $src) { continue }
      $n = $p.Line - 1
      if ($n -lt 0 -or $n -ge $src.Length) { continue }

      $whole = ($src -join "`n")
      $rel = $p.Path.Replace($corpus + '\', '').Replace($corpus + '/', '')
      $blocker = $src[$n].Trim()

      $hasImport = @($src | Where-Object { $_ -match '^\s*import\b' }).Count -gt 0
      if ((-not ($whole -match '@[A-Za-z_]')) -and (-not $hasImport)) {
        $snippet = $whole
        $mode = 'file'
      } else {
        $start = -1
        for ($i = $n; $i -ge 0; $i--) { if ($src[$i] -match $script:GP_OPENER) { $start = $i; break } }
        if ($start -lt 0) { continue }
        $end = $src.Length
        for ($i = $n + 1; $i -lt $src.Length; $i++) { if ($src[$i] -match $script:GP_OPENER) { $end = $i; break } }
        $snippet = ($src[$start..($end - 1)] -join "`n")
        $mode = 'item'
        if ($snippet -match '@[A-Za-z_]') { continue }
      }

      if ($tried -ge $MaxChecksPerCorpus) {
        $log += ("{0,-9} stopped at the {1}-check cap; unreadable files remain" -f $k, $MaxChecksPerCorpus)
        break
      }
      $tried++

      $tag = ('{0}_{1}' -f $k, ($rel -replace '[^A-Za-z0-9]', '_'))
      $d = Join-Path $base $tag
      New-Item -ItemType Directory -Force -Path $d | Out-Null
      [IO.File]::WriteAllText((Join-Path $d 'moon.mod'), ("name = `"probe/$tag`"`n`nversion = `"0.1.0`"`n"))
      [IO.File]::WriteAllText((Join-Path $d 'moon.pkg'), "supported_targets = `"+all`"`n")
      [IO.File]::WriteAllText((Join-Path $d 'subject.mbt'), $snippet)

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

      $site = ('{0}:{1}' -f $rel, $p.Line)
      if ($moonOk -and -not $selfOk) {
        $log += ("{0,-9} USE  {1,-6} {2}   | blocker: {3}" -f $k, $mode, $site, $blocker)
        return [pscustomobject]@{
          Found = $true; Text = $snippet; Provenance = $site; Checks = $tried
          CorporaScanned = @($k); Log = $log; BlockedLine = $blocker; Corpus = $k
        }
      }
      $why = if (-not $moonOk) { 'MOON-BAD' } else { 'SELF-OK' }
      $log += ("{0,-9} skip {1,-6} {2,-11} {3}" -f $k, $mode, $why, $site)
    }
  }

  return [pscustomobject]@{
    Found = $false; Text = ''; Provenance = ''; Checks = 0; CorporaScanned = @(); Log = $log
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
    Write-Output ('  line  = {0}' -f $r.BlockedLine)
    Write-Output ('  chars = {0}' -f $r.Text.Length)
  }
}
