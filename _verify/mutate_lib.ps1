# Shared mutation-gate harness.
#
# WHY THIS FILE EXISTS. `_verify/mutate_0429.ps1` once reported
# "M4 KILLED, 2 of 442 red" while the two tests doing the killing were FAILING ON
# CLEAN CODE -- they asserted a `MethodError` the analyzer never emits. Every later
# mutation reported those same two red, so the gate looked healthy and the one
# mutation it had not actually pinned was reported as pinned. The fix was to run the
# UNMUTATED suite first and abort unless it is green.
#
# That fix was applied to 0429 only. Measured 2026-10-13, thirteen of the fourteen
# gates had no baseline check at all:
#
#     mutate_0412.ps1  baseline=False preflight=False sha256=False
#     mutate_0428.ps1  baseline=False preflight=True  sha256=True
#     mutate_0429.ps1  baseline=True  preflight=True  sha256=True
#
# THAT TABLE IS A MEASUREMENT OF THE DEFECT, NOT OF THE PRESENT, and it is worth saying
# so, because it reads like a status report. MEASURED 2026-10-23: all 87 numbered gates
# call `Invoke-MutationGate`, and it has NO pre-flight or SHA256 switch at all -- so every
# one of them gets the baseline, the pre-flight and the SHA256 restore check, and ZERO
# gates carry their own copy of the runner. `mutate_0412.ps1` and `mutate_0413.ps1`, the
# two this table names, both print a pre-flight line and both end with "every restore
# verified byte-identical".
#
# THE COUNT IN THAT SENTENCE IS NOW CHECKED, NOT ASSERTED. It said 74 on 2026-10-20 and
# it was five stale by 2026-10-22, because a number in a comment is not checked by
# anything -- and the sentence it was supporting ("every gate in this repository gets
# the baseline, the pre-flight and the SHA256 restore check") was the whole content of
# Direction 1's remainder. Five gates had been added in between; none of them was
# wrong, and nothing would have said so if one had been. `_verify/check_gate_roster.ps1`
# now reads this sentence, counts the numbered gates on disk, and fails if the two
# disagree -- so a gate added without this sentence being updated is a FAILING gate,
# not a quietly-wrong one. Change the number here when you add a gate.
#
# So the defect was not in one script, it was in the PATTERN that fourteen copies
# of the pattern inherited -- and each copy has to be fixed by hand, which is
# exactly how the next one gets missed. This file is the harness; a release gate
# becomes a list of mutations and nothing else, so a new gate cannot reintroduce
# the bug by forgetting a guard.
#
# THE RULES IT ENFORCES, all of them learned the hard way.
#
#   1. BASELINE FIRST. A mutation count means nothing against a red suite. "KILLED"
#      and "was already red" are indistinguishable without a baseline.
#   2. COMPILE-ERR IS THE ABSENCE OF A `Total tests:` LINE, never a grep. A mutant
#      that fails to build is not a killed mutant; it is a mutant nobody measured.
#   3. NO-OP IS A FAILURE. A pattern that does not apply means the mutation never
#      happened, and a gate that reports success for a mutation it did not apply
#      is worse than no gate.
#   4. EVERY RESTORE IS PROVEN BY SHA256. Writing back the bytes you read is not
#      the same as writing back the bytes that were there.
#   5. `Expect = 'SURVIVED'` IS ALLOWED AND MUST BE ARGUED. Some mutations really
#      are unobservable; those are declared, not quietly dropped. The harness
#      cannot tell whether a survivor is legitimate -- only the comment can, and
#      that is the point of requiring the field.
#   6. `MustRed = '<test-name substring>'` SAYS WHICH TEST, not just that one went
#      red. See the long note on it below; it is the newest rule and the only one
#      the other five cannot imply.
#
#   7. ONE GATE AT A TIME, AND NOTHING ELSE TOUCHING ITS FILES. Rule 4 proves a
#      restore byte-for-byte, but it cannot see a SECOND process: two gates
#      mutating `src/parser/parser.mbt` concurrently read, rewrite and restore
#      each other's bytes, and each one's SHA256 check still passes because each
#      wrote back what IT read.
#
#      Measured, not theorised. A release run reported gates 0442 and 0444 FAILED
#      with every other gate green; both are 5/5 run alone, and both leave the
#      tree byte-identical. The cause was a gate launched in the background while
#      another ran in the foreground. The symptom is a gate failing for no
#      reproducible reason, which is the one symptom worth chasing before
#      believing anything else.
#
#      The same applies outside this harness: any script that edits a source file
#      to measure it -- `_verify/measure_*.ps1` -- must not share the machine with
#      a gate. Those scripts rebuild between scans, so a concurrent gate also
#      fights over `_build`.
#
#   8. AN ANCHOR MUST NOT BE SATISFIABLE BY PROSE. Presence and uniqueness cannot
#      tell code from a comment that QUOTES it, and such an anchor is applied,
#      unique, and behaviourally inert -- so the suite stays green and the gate
#      reports a result for a mutation it never performed. Added 0474, after gate
#      0465's M6 did exactly this: 0474 split one arm into two, the anchor survived
#      only inside the comment explaining the split, and M6 rewrote the prose.
#
# Usage from a release gate:
#
#     . (Join-Path $PSScriptRoot 'mutate_lib.ps1')
#     Invoke-MutationGate -Name 'M1..M5' -Target 'js' -Mutations @(
#       @{ Name='M1 ...'; File=$PARSER; Find=@'
#   ...
# '@; Repl='' },
#       ...
#     )
#
# `$Mutations` entries accept an optional `Expect` (default 'KILLED') and an
# optional `Prove` string, printed alongside a survivor so the argument travels
# with the result.

$script:MutationGateFailures = @()

# RULE 9, added 0495b: A FILE THAT ANOTHER PROCESS HAS OPEN IS NOT A FAILED GATE.
#
# MEASURED. The full release gate on 2026-10-21 failed at ONE gate, 0455, with
# this and nothing else:
#
#     Exception calling "WriteAllText" with "3" argument(s): "The requested
#     operation cannot be performed on a file with a user-mapped section open."
#
# M1 and M2 had already been KILLED, with their named tests confirmed, when the
# WRITE of the next mutation's replacement threw. Windows refuses a write to a
# file that a reader has MEMORY-MAPPED, and the reader here was the compiler:
# `moon` had the source mapped while the gate was between its test runs. The
# same gate, run alone in the same tree minutes earlier, was GREEN.
#
# WHY IT MATTERS MORE THAN IT LOOKS. The write that threw was not necessarily
# the one that APPLIES a mutation -- it could have been the RESTORE. A restore
# that throws leaves the target file MUTATED, and the next gate then measures a
# tree nobody intended to measure. The tree was checked after the failure (the
# target, `src/lexer/lexer.mbt`, was byte-identical to HEAD) -- but a check
# after the fact is not a guard.
#
# So the I/O gets a retry, and the retry is on the TRANSIENT, not on the
# verdict: the mutation still has to be applied, still has to kill, and the
# restore still has to be proven byte-identical by SHA256 afterwards. Nothing
# about the judgement changes. This is the same shape as the EMPTY-RUN retry
# below -- "the machine misbehaved" is not a verdict -- and the same shape as
# `release.ps1`'s `Read-TextWhenFree`, which was written for the same reason.
#
# The exception is an `IOException` (ERROR_USER_MAPPED_FILE / a sharing
# violation). A genuinely unreadable or genuinely unwritable file still throws,
# after the tries are spent.
function Read-BytesWithRetry {
  param([string]$Path, [int]$Tries = 12)
  for ($i = 1; $i -le $Tries; $i++) {
    try {
      return [System.IO.File]::ReadAllBytes($Path)
    } catch [System.IO.IOException] {
      if ($i -eq $Tries) { throw }
      Start-Sleep -Milliseconds (50 * $i)
    }
  }
}

function Write-BytesWithRetry {
  param([string]$Path, [byte[]]$Bytes, [int]$Tries = 12)
  for ($i = 1; $i -le $Tries; $i++) {
    try {
      [System.IO.File]::WriteAllBytes($Path, $Bytes)
      return
    } catch [System.IO.IOException] {
      if ($i -eq $Tries) { throw }
      Write-Output ('      the file was busy (another process has it mapped); retrying write ' + $i + '/' + $Tries)
      Start-Sleep -Milliseconds (50 * $i)
    }
  }
}

function Write-TextWithRetry {
  param([string]$Path, [string]$Text, [System.Text.Encoding]$Enc, [int]$Tries = 12)
  for ($i = 1; $i -le $Tries; $i++) {
    try {
      [System.IO.File]::WriteAllText($Path, $Text, $Enc)
      return
    } catch [System.IO.IOException] {
      if ($i -eq $Tries) { throw }
      Write-Output ('      the file was busy (another process has it mapped); retrying write ' + $i + '/' + $Tries)
      Start-Sleep -Milliseconds (50 * $i)
    }
  }
}

# RULE 6, in its own place because it needs the failure format and that format was
# captured, not assumed.
#
# `KILLED` says SOMETHING went red. Every rule above is compatible with the wrong
# test going red -- which is exactly what 0.4.18's runner gestured at and never did:
# its `[string[]]$ExpectRed` parameter carried the comment "test-name substrings
# that MUST go red", was passed the literal 'expectRed' at all twelve call sites,
# and was never read by the judgement. The capability was documented and absent.
#
# Measured with `_verify/named_claims.ps1` on the three gates that name a test:
# two claims hold, and one is false. 0.4.21 M2 says only `0421: a guard's else body
# is still analyzed` can catch it; that test exists, and it does NOT go red. The
# mutation is killed by six other tests, three of them belonging to the LATER
# 0.4.25 gate -- so the kill is incidental, and would have disappeared if those
# tests were ever reworded.
#
# The red line `moon test` prints is one per failing test:
#   [<pkg>] test <file>:<line> ("<test name>") failed: ...
# which is why this reads the name out of the quotes.
function Get-RedTestNames {
  param([string]$Out)
  return @([regex]::Matches($Out, '\("([^"]+)"\) failed:') | ForEach-Object { $_.Groups[1].Value })
}

function Invoke-MutationGate {
  param(
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][string]$Target,
    [Parameter(Mandatory = $true)][Array]$Mutations,
    [string]$Root = (Split-Path -Parent $PSScriptRoot),
    [string]$MoonExe = 'C:\Users\31379\.moon\bin\moon.exe'
  )

  Write-Output ('=== mutation gate: ' + $Name + ' (target ' + $Target + ') ===')

  $nl = [string][char]10
  $enc = New-Object System.Text.UTF8Encoding($false)

  # ---- validate the table before touching anything ------------------------------
  # mutate_0425's table carries no `File` key at all -- its original runner had a
  # single-file convention ($F = 'src\interp\interp.mbt') and applied it to every
  # mutation. Converted as-is, the harness died with "Index operation failed; the
  # array index evaluated to null" from inside the file-collection line, which names
  # neither the mutation nor the field. A malformed table is a fact about the gate
  # and has to be reported as one.
  $shapeErrors = @()
  foreach ($m in $Mutations) {
    foreach ($k in @('Name', 'File', 'Find')) {
      if (-not $m.ContainsKey($k) -or $null -eq $m[$k]) {
        $shapeErrors += ("'" + $m.Name + "' has no " + $k)
      }
    }
    if (-not $m.ContainsKey('Repl')) {
      $shapeErrors += ("'" + $m.Name + "' has no Repl")
    }
  }
  if ($shapeErrors.Count -gt 0) {
    Write-Output 'ABORT: the mutation table is malformed. Nothing was run.'
    foreach ($e in $shapeErrors) { Write-Output ('  ' + $e) }
    Write-Output '  The harness needs Name/File/Find/Repl per mutation. A gate that used a'
    Write-Output '  single-file convention must say so on each entry.'
    $script:MutationGateFailures += ($Name + ' (malformed table)')
    return
  }

  # ---- read every file the mutations touch, once ------------------------------
  $files = @($Mutations | ForEach-Object { $_.File } | Sort-Object -Unique)
  $texts = @{}
  foreach ($f in $files) {
    $p = Join-Path $Root $f
    if (-not (Test-Path -LiteralPath $p)) {
      Write-Output ('ABORT: no such file: ' + $f)
      $script:MutationGateFailures += ($Name + ' (missing file ' + $f + ')')
      return
    }
    $texts[$f] = [System.Text.Encoding]::UTF8.GetString((Read-BytesWithRetry -Path $p))
  }

  # ---- pre-flight: every pattern must be present, in milliseconds -------------
  # Rule 3, with one honest exception. A pattern that does not apply means the
  # mutation never happened. mutate_0412 discovered this the cheap way: its M1, M2
  # and M5b anchors stopped matching when `collect_declared_names` and `union` were
  # refactored after 0.4.12, and the old runner PRINTED "anchor text not found",
  # counted the mutation as neither kill nor failure, and exited 0. A gate that
  # reports success for mutations it never applied is worse than no gate.
  #
  # `Retired = '<reason>'` is the honest form for a mutation whose target code no
  # longer exists. It is EXCLUDED, with the reason printed, and it does not fail the
  # gate -- because the honest verdict is "this guard can no longer be run", not
  # "this guard still holds". What it must never do is pass silently, and what it
  # must never be is a fresh anchor invented to make the count look right.
  $live = @($Mutations | Where-Object { -not $_.ContainsKey('Retired') })
  $retired = @($Mutations | Where-Object { $_.ContainsKey('Retired') })
  foreach ($r in $retired) {
    Write-Output ('  RETIRED: ' + $r.Name + '  -- ' + $r.Retired)
  }
  if ($retired.Count -gt 0) {
    Write-Output ('  ' + $retired.Count + ' of ' + $Mutations.Count + ' mutations retired; ' + $live.Count + ' live.')
  }
  if ($live.Count -eq 0) {
    Write-Output 'ABORT: every mutation in this gate is retired. Nothing left to verify.'
    $script:MutationGateFailures += ($Name + ' (all mutations retired)')
    return
  }

  $absent = @()
  $ambiguous = @()
  $prose = @()
  # PROSE MAP, built once per file. A line is PROSE if it starts with `//` after trimming --
  # which covers `//` and `///` and `///|` alike, since all three are comment markers.
  $proseMap = @{}
  foreach ($m in $live) {
    if (-not $proseMap.ContainsKey($m.File)) {
      $flags = New-Object 'System.Collections.Generic.List[bool]'
      foreach ($ln in ($texts[$m.File] -split "`n")) {
        $flags.Add($ln.TrimStart().StartsWith('//'))
      }
      $proseMap[$m.File] = $flags
    }
  }
  foreach ($m in $live) {
    $findText = ([string]$m.Find).Replace("`r`n", $nl)
    $hay = $texts[$m.File]
    # COUNT, do not merely test presence. `mutate_lib` removes the FIRST literal match, so
    # an anchor that occurs twice silently targets the wrong site while the gate reports
    # a clean kill. Four anchors have now been found that way, across three increments:
    #   0467  a DEDENT that made a `Find` stop matching, indistinguishable from a deletion
    #   0468  a RENAME (`fn_body` -> `value_block`) in 0426's M3/M4
    #   0468  a DUPLICATED block: 0433's M4 named `defer` and removed `errdefer`
    #   0469  the same rename again in 0433's M1 (`let scrutinee` -> `let subject`)
    # => 判据: a pre-flight that tests PRESENCE cannot distinguish a unique anchor from a
    # duplicated one, and a wrong site is a green result that means nothing.
    #
    # This WARNS and does not fail. Several gates legitimately anchor on text that occurs
    # more than once, and turning that into an error would abort working gates over a
    # diagnostic. The count is printed so it is in front of whoever reads the output.
    $count = 0
    $step = [Math]::Max(1, $findText.Length)
    $first = -1
    $idx = $hay.IndexOf($findText, [System.StringComparison]::Ordinal)
    while ($idx -ge 0) {
      if ($first -lt 0) { $first = $idx }
      $count++
      $idx = $hay.IndexOf($findText, $idx + $step, [System.StringComparison]::Ordinal)
    }
    if ($count -gt 0) {
      # PROSE TEST, added 0474 after gate 0465 M6 caught it. Presence and uniqueness are the
      # WRONG two properties to check when the only occurrence of an anchor is inside a
      # COMMENT THAT QUOTES THE CODE. Such an anchor is satisfied, unique, and applied -- and
      # it changes no behaviour at all, so the suite stays green and the gate reports a
      # result for a mutation it never performed. That is rule 3's NO-OP wearing rule 6's
      # clothes, and it is worse than an absent anchor because an absent one aborts loudly.
      #
      # The case was real: 0474 split `TName("for") | TName("while") =>` into two explicit
      # arms, and 0465's M6 anchor survived in exactly one place -- a comment explaining the
      # split. It rewrote the prose, passed pre-flight, and went green. Re-anchored, and the
      # parser comment was reworded so it cannot satisfy an anchor again.
      #
      # => 判据: a match on a line beginning `//` is not a match on CODE. An anchor is a
      # pointer to the line that decides behaviour; if the text it names is somewhere the
      # compiler never reads, the pointer is decoration.
      $flags = $proseMap[$m.File]
      $startLine = 0
      for ($k = 0; $k -lt $first; $k++) { if ($hay[$k] -eq "`n") { $startLine++ } }
      $span = 0
      for ($k = $first + $findText.Length - 1; $k -gt $first; $k--) { if ($hay[$k] -eq "`n") { $span++ } }
      $allProse = $true
      for ($l = $startLine; $l -le ($startLine + $span) -and $l -lt $flags.Count; $l++) {
        if (-not $flags[$l]) { $allProse = $false; break }
      }
      if ($allProse) { $prose += $m.Name }
    }
    if ($count -eq 0) {
      $absent += $m.Name
      Write-Output ('PREFLIGHT MISS: ' + $m.Name + '  (' + $m.File + ')')
      Write-Output ('  looking for: |' + (($findText -split "`n")[0]) + '|')
    } elseif ($count -gt 1) {
      $ambiguous += $m.Name
      Write-Output ('PREFLIGHT AMBIGUOUS x' + $count + ': ' + $m.Name + '  (' + $m.File + ')')
      Write-Output ('  the FIRST occurrence is the one that will be mutated -- check that')
      Write-Output ('  it is the one the mutation names.')
    }
  }
  if ($absent.Count -gt 0) {
    Write-Output ('ABORT: ' + $absent.Count + ' pattern(s) absent. No suite was run.')
    Write-Output '      If the code a mutation targeted has since changed shape, mark it'
    Write-Output '      Retired = "<reason>" rather than inventing an anchor to match.'
    $script:MutationGateFailures += ($Name + ' (preflight)')
    return
  }
  if ($prose.Count -gt 0) {
    Write-Output ''
    foreach ($pn in $prose) {
      Write-Output ('PREFLIGHT PROSE: ' + $pn)
      Write-Output '  the anchor matches only inside `//` comment lines, so the mutation'
      Write-Output '  rewrites PROSE and leaves behaviour untouched. A green result for it'
      Write-Output '  means nothing. Re-anchor onto the code it names.'
    }
    Write-Output ''
    Write-Output ('ABORT: ' + $prose.Count + ' anchor(s) satisfied by a comment. No suite was run.')
    $script:MutationGateFailures += ($Name + ' (preflight prose)')
    return
  }
  if ($ambiguous.Count -gt 0) {
    Write-Output ('Pre-flight: all ' + $live.Count + ' live patterns present, ' + $ambiguous.Count + ' AMBIGUOUS (see above).')
  } else {
    Write-Output ('Pre-flight: all ' + $live.Count + ' live patterns present and UNIQUE.')
  }

  # ---- BASELINE --------------------------------------------------------------
  # Rule 1. Without this, every count below is uninterpretable.
  #
  # `-C $Root` IS NOT OPTIONAL, and it is here for a measured reason. `moon`
  # resolves the project from the CURRENT DIRECTORY, so a gate invoked from
  # anywhere but the repository root prints "not in a Moon project" -- and this
  # harness reported that as "the suite does not compile", which accuses the
  # SUITE for a mistake about the DIRECTORY. The file paths in this harness are
  # already `$Root`-relative; the moon calls were the only ones that were not,
  # and that inconsistency is what let the trap through.
  # Measured 2026-10-29: three gates run from the parent directory all aborted
  # with "baseline did not run", and the suite had not been compiled at all.
  # ONE copy of the summary-line pattern for the baseline, and it is used by
  # BOTH halves of the baseline below (the first run and the retry).
  #
  # The harness carries that pattern THREE times on purpose -- the baseline, the
  # mutation run and the mutation run's own retry -- so that breaking one of
  # them does not break the others. `_verify/mutate_lib_selftest.ps1` proves
  # that: it breaks the MUTATION path's copies in a copy of the tree, leaves the
  # baseline's intact, and requires the copy's gate to reach its mutation row
  # and score it INCONCLUSIVE. A FOURTH literal copy would leave two intact and
  # that self-test would (rightly) refuse to run -- which is what it did, the
  # first time this retry was written with its own literal.
  $summaryRx = 'Total tests: (\d+), passed: (\d+), failed: (\d+)'
  $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  $base = & $MoonExe -C $Root test --target $Target 2>&1 | Out-String
  $bCode = $LASTEXITCODE
  $ErrorActionPreference = $prev
  $bRan = [regex]::Matches($base, $summaryRx)
  # 0508. THE BASELINE GETS THE RULE THE MUTATION RUNS ALREADY HAVE.
  #
  # Measured 2026-10-30, in the 0.4.38 release run: gate 0470 aborted at its
  # BASELINE with "baseline did not run ... The suite does not compile", and its
  # transcript showed that `moon test` had printed NOTHING AT ALL -- no summary,
  # no diagnostic, no output on either stream. That is the shape of a run that
  # never happened: a contended `_build`, a starved binary, a killed compiler.
  # The suite was fine -- 1330/1330 in every other gate of the same run, and the
  # same tree passes this gate standalone.
  #
  # The mutation runs already know this. A run with no summary and no compiler
  # diagnostic is INCONCLUSIVE there: it is retried once, and it FAILS the gate
  # if the retry does not happen either. The baseline had no such rule, so it
  # reported the machine's hiccup as a verdict about the CODE -- and it named the
  # victim ("the suite does not compile") instead of the cause.
  #
  # So the baseline asks the same question and gets the same answer: a baseline
  # with no summary and no compiler diagnostic is a FAILED MEASUREMENT, and it is
  # retried once. A compiler diagnostic IS a verdict about the tree, and it is
  # NOT retried. And the retry can never manufacture a pass: if the second run
  # does not produce a summary either, the gate FAILS, and it says what happened
  # instead of blaming the suite.
  if ($bRan.Count -lt 1 -and -not [regex]::IsMatch($base, 'Error:\s*\[\d+\]')) {
    if ([string]::IsNullOrWhiteSpace($base)) {
      Write-Output 'EMPTY RUN: moon printed nothing at all -- the run did not happen. Retrying once.'
    } else {
      Write-Output ('NO RUN: moon exited ' + $bCode + ' and printed no test summary,')
      Write-Output ('      and nothing in its ' + $base.Length + ' characters is a compiler diagnostic.')
      Write-Output '      A compiler that rejects the tree ALWAYS says why (`Error: [NNNN]`), so'
      Write-Output '      this is not a broken suite -- it is a run that never happened. Retrying once.'
    }
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $base = & $MoonExe -C $Root test --target $Target 2>&1 | Out-String
    $bCode = $LASTEXITCODE
    $ErrorActionPreference = $prev
    $bRan = [regex]::Matches($base, $summaryRx)
    if ($bRan.Count -ge 1) {
      Write-Output '  RETRY GOT A REAL RUN -- the first run was transient, not a verdict.'
    } else {
      Write-Output ('  RETRY ALSO GOT NO RUN (moon exited ' + $bCode + ', ' + $base.Length + ' chars).')
    }
  }
  if ($bRan.Count -lt 1) {
    if ([regex]::IsMatch($base, 'Error:\s*\[\d+\]')) {
      Write-Output 'ABORT: the baseline did not run (no `Total tests:` line). The suite does not compile:'
    } else {
      Write-Output 'ABORT: the baseline did not run, and it did not happen twice.'
      Write-Output '      This is a FAILED MEASUREMENT, not a verdict about the tree: the suite did'
      Write-Output '      not compile is NOT what was observed -- nothing was observed.'
    }
    # Rule 2 reads the ABSENCE of a line, which is correct -- but an absence with no
    # evidence attached is exactly what makes a transient failure unrootable, and a
    # transient failure here is indistinguishable from a broken tree until you can
    # see what `moon` actually said. A lock on _build, a half-finished rebuild and a
    # genuinely broken module all produce the same absent line. Print the tail.
    Write-Output '  what moon test actually printed:'
    foreach ($t in ($base -split "`r?`n" | Where-Object { $_.Trim() } | Select-Object -Last 15)) {
      Write-Output ('    | ' + $t.TrimEnd())
    }
    $script:MutationGateFailures += ($Name + ' (baseline did not run)')
    return
  }
  $bM = $bRan[$bRan.Count - 1]
  $bTotal = [int]$bM.Groups[1].Value
  $bFailed = [int]$bM.Groups[3].Value
  Write-Output ("Baseline: {0}/{1} passed, {2} failed." -f $bM.Groups[2].Value, $bTotal, $bFailed)
  if ($bTotal -le 0) { Write-Output 'ABORT: baseline ran 0 tests.'; $script:MutationGateFailures += ($Name + ' (baseline 0)'); return }
  if ($bFailed -gt 0) {
    Write-Output ''
    Write-Output 'ABORT: the suite is RED on unmutated code. Every count below would be meaningless.'
    foreach ($ln in ($base -split "`r?`n" | Where-Object { $_ -match 'failed' } | Select-Object -First 10)) {
      Write-Output ('  ' + $ln.Trim())
    }
    $script:MutationGateFailures += ($Name + ' (baseline red)')
    return
  }

  # ---- run -------------------------------------------------------------------
  # `$live`, NOT `$Mutations`: a retired entry has no Find pattern, and
  # `$text.Replace('', '')` is a no-op that would read as SURVIVED -- a retired
  # mutation silently reporting a result it never tested.
  $results = @()
  foreach ($m in $live) {
    $path = Join-Path $Root $m.File
    $bytes0 = Read-BytesWithRetry -Path $path
    $sha0 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    $text = [System.Text.Encoding]::UTF8.GetString($bytes0)
    $eol = if ($text.Contains([string][char]13 + [char]10)) { [string][char]13 + [char]10 } else { $nl }
    $norm = $text.Replace($eol, $nl)
    $findN = ([string]$m.Find).Replace("`r`n", $nl)
    $replN = ([string]$m.Repl).Replace("`r`n", $nl)
    $want = if ($m.ContainsKey('Expect')) { [string]$m.Expect } else { 'KILLED' }

    # RULE 5, ENFORCED. The rule says a declared non-KILLED outcome has to carry its
    # argument -- and until now the harness only PRINTED the argument when the field
    # was there. So the rule was a WISH: a mutation that declared SURVIVED and carried
    # no `Prove` was reported as a survivor, with no reason, and nothing failed.
    #
    # MEASURED 2026-10-22, over the 37 declarations in the 79 numbered gates: 35
    # SURVIVED and 2 COMPILE-ERR, and FOUR of them had no `Prove` at all -- one in
    # 0418, one in 0419, two in 0422. Three of the four had their argument written
    # out in the comment directly above the mutation, in prose, carefully, and it
    # never travelled with the RESULT: the gate's output said "SURVIVED" and
    # nothing else, which is the exact shape the rule was written to prevent.
    #
    # => 判据: a rule that is only PRINTED is not a rule. The harness cannot tell
    # whether a survivor is legitimate -- only the argument can, and an argument
    # that is not required is an argument that is not there.
    #
    # This is a DECLARATION check, not a run check: it fires on the field, so a
    # mutation that declares COMPILE-ERR and turns out to be KILLED is still
    # reported for its missing argument as well as for its wrong verdict.
    if ($want -ne 'KILLED' -and -not $m.ContainsKey('Prove')) {
      Write-Output ('      NO ARGUMENT: this mutation declares ' + $want + ' and carries no `Prove`.')
      Write-Output '      Rule 5: a declared non-KILLED outcome has to carry its argument.'
      Write-Output '      Add Prove = "<why this mutation is unobservable>".'
      $script:MutationGateFailures += ($m.Name + ' (declared ' + $want + ' with no argument)')
    }

    # Rule 3. A pattern that does not apply is a failure, not a pass.
    if ($norm.IndexOf($findN, [System.StringComparison]::Ordinal) -lt 0) {
      $results += [pscustomobject]@{ Mutation = $m.Name; Outcome = 'NO-OP'; Killed = 0; Want = $want; Detail = 'pattern absent' }
      $script:MutationGateFailures += ($m.Name + ' (NO-OP)')
      continue
    }
    Write-TextWithRetry -Path $path -Text ($norm.Replace($findN, $replN).Replace($nl, $eol)) -Enc $enc

    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $out = & $MoonExe -C $Root test --target $Target 2>&1 | Out-String
    $code = $LASTEXITCODE
    $ErrorActionPreference = $prev

    $ran = [regex]::Matches($out, 'Total tests: (\d+), passed: (\d+), failed: (\d+)')

    # A COMPILER DIAGNOSTIC IS WHAT MAKES A MISSING SUMMARY LINE THE MUTANT'S FAULT.
    #
    # AN EMPTY RUN IS THE HARNESS'S FAULT, NOT THE MUTANT'S.
    #
    # Rule 2 says COMPILE-ERR is not a kill, and that is right: a mutant that does not
    # build is a mutant nobody measured. What rule 2 did NOT say is that an empty run
    # is a property OF THE MUTATION -- and treating it as one is how a release run
    # reported four gates FAILED that each pass standalone, twice, across six gates.
    #
    # The discriminator is not a guess. A compiler that rejects a mutant ALWAYS says
    # why, and a build that fails ALWAYS leaves a line behind. Gate 0430 M4 is the
    # control: it is declared COMPILE-ERR, and it does so with real diagnostics every
    # time. Gate 0425 M7 is the failure: `moon test` was asked once, and its output
    # was the empty string, so the harness recorded COMPILE-ERR and blamed a mutation
    # that had built and been killed correctly every other time.
    #
    # So: no summary line AND nothing at all printed == the run never started, and one
    # retry decides it. The retry CANNOT manufacture a pass. If the retry also yields
    # no run, the verdict still fails; and a non-empty COMPILE-ERR -- an actual
    # compiler rejection -- is never retried, so declared non-buildable mutants keep
    # the verdict they declare.
    #
    # 0506: AND "NOTHING AT ALL" WAS TOO NARROW A TEST. MEASURED on gate 0466's M6
    # during the 0506 release gate: `moon test` printed the COMPILER'S OWN WARNING --
    #
    #     Warning (unused_value): Unused variable 'n'
    #
    # -- and exited 1 WITHOUT a test summary. That is not an empty output, so the
    # retry above did not fire, and the harness recorded COMPILE-ERR and blamed the
    # mutation for a run that never happened. The same mutation on the same tree,
    # run standalone, is SURVIVED with 1184/1184 green; and `moon test` on the
    # mutated tree, with the package REBUILT, exits 0 and DOES print the summary
    # (the warning goes to stderr, the summary to stdout). The machine was busy at
    # the time -- another session's test binary was running -- and a starved build
    # wears the same shape as a rejected one.
    #
    # THE THREE-WAY RULE, and the retry is the fourth case:
    #
    #     a summary line + a non-zero exit          -> KILLED
    #     a summary line + a zero exit              -> SURVIVED
    #     a COMPILER DIAGNOSTIC (`Error: [NNNN]`)   -> COMPILE-ERR
    #     NONE OF THE ABOVE                          -> INCONCLUSIVE
    #
    # INCONCLUSIVE IS NOT A VERDICT. It is a failed measurement, and it FAILS the
    # gate -- but it is retried once first, because the failure mode is fast (a
    # starved binary answers in seconds) and a retry costs almost nothing. It can
    # never manufacture a pass: if the retry also yields no summary, the mutation
    # is reported INCONCLUSIVE and the gate fails.
    $hasCompilerError = [regex]::IsMatch($out, 'Error:\s*\[\d+\]')
    $retried = $false
    if ($ran.Count -eq 0 -and -not $hasCompilerError) {
      if ([string]::IsNullOrWhiteSpace($out)) {
        Write-Output ('      EMPTY RUN: moon exited ' + $code + ' and printed nothing at all.')
        Write-Output '      No summary line and no output is not a mutant that failed to build;'
        Write-Output '      it is a run that never happened. Retrying once.'
      } else {
        Write-Output ('      NO RUN: moon exited ' + $code + ' and printed no test summary,')
        Write-Output ('      and nothing in its ' + $out.Length + ' characters is a compiler diagnostic.')
        Write-Output '      A compiler that rejects a mutant ALWAYS says why (`Error: [NNNN]`), so'
        Write-Output '      this is not the mutant failing to build -- it is a run that never happened.'
        Write-Output '      Retrying once.'
      }
      $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
      $out = & $MoonExe -C $Root test --target $Target 2>&1 | Out-String
      $code = $LASTEXITCODE
      $ErrorActionPreference = $prev
      $ran = [regex]::Matches($out, 'Total tests: (\d+), passed: (\d+), failed: (\d+)')
      $hasCompilerError = [regex]::IsMatch($out, 'Error:\s*\[\d+\]')
      $retried = $true
      if ($ran.Count -ge 1) {
        Write-Output '      RETRY GOT A REAL RUN -- the first run was transient, not a verdict.'
      } else {
        Write-Output ('      RETRY ALSO GOT NO RUN (moon exited ' + $code +
                      ', ' + $out.Length + ' chars). Still a failure, reported as such below.')
      }
    }

    # Rule 2. Absence of the line, not a grep for an error string.
    $killed = 0; $detail = ''
    if ($ran.Count -ge 1) {
      $m2 = $ran[$ran.Count - 1]
      $total = [int]$m2.Groups[1].Value
      $passed = [int]$m2.Groups[2].Value
      if ($total -le 0) { $outcome = 'NO-RUN'; $detail = 'Total tests: 0' }
      else {
        $killed = $total - $passed
        if ($killed -gt 0) { $outcome = 'KILLED'; $detail = "$killed of $total red" }
        else { $outcome = 'SURVIVED'; $detail = "$total/$total still green" }
      }
      # A run that only exists because the first attempt came back empty is a real
      # measurement, but it is also the only evidence that the machine misbehaved.
      # Say so on the line rather than letting the retry pass for a clean kill.
      if ($retried) { $detail += ' [after an empty first run]' }
    } elseif ($hasCompilerError) {
      $outcome = 'COMPILE-ERR'
      $detail = 'no Total tests line; moon exited ' + $code + ' after printing ' + $out.Length + ' chars'
      # Rule 2's verdict is right and must not be softened -- a mutant that does not
      # build is NOT a kill. But the verdict used to be the LAST thing said about it:
      # `$out` was captured, tested for one regex, and dropped. That is the single
      # reason a gate can report COMPILE-ERR with nothing to act on, and it is why a
      # suite-wide run produced four gate failures whose cause was unrecoverable.
      # COMPILE-ERR is also the shape a TRANSIENT `moon test` failure wears -- a
      # contended _build, a killed compiler, a full disk all look like this -- so the
      # transcript is the difference between a flake and a cause.
      Write-Output '      the suite did not run. What moon test printed:'
      foreach ($t in ($out -split "`r?`n" | Where-Object { $_.Trim() } | Select-Object -Last 20)) {
        Write-Output ('        | ' + $t.TrimEnd())
      }
    } else {
      # INCONCLUSIVE. No summary line, and nothing that says WHY -- so this is not a
      # mutant that failed to build, and it is not a mutant that was caught. It is a
      # measurement that did not happen, and it is reported as one: the gate FAILS,
      # because a number nobody observed is not a number a document may quote.
      $outcome = 'INCONCLUSIVE'
      $detail = 'no test summary and no compiler diagnostic; moon exited ' + $code +
        ' after printing ' + $out.Length + ' chars'
      Write-Output '      the run did not happen and nothing said why. Not a verdict:'
      foreach ($t in ($out -split "`r?`n" | Where-Object { $_.Trim() } | Select-Object -Last 20)) {
        Write-Output ('        | ' + $t.TrimEnd())
      }
    }

    # Rule 4. Prove the restore byte-for-byte.
    Write-BytesWithRetry -Path $path -Bytes $bytes0
    if ($sha0 -ne (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash) {
      $detail += ' RESTORE-MISMATCH'
      $script:MutationGateFailures += ($m.Name + ' (restore)')
    }

    # Rule 6. WHICH test went red, when the mutation says which one must.
    #
    # ORDINAL `IndexOf`, NOT `-like`. Measured on gate 0442: every one of its five
    # mutations was KILLED, every named test WAS visibly in the list of tests that
    # went red, and all five still reported MUST-RED MISS -- against strings that
    # were byte-identical (65 bytes each, same hex).
    #
    # The cause is that PowerShell's `-like` runs the PATTERN through escape
    # processing, and the backtick is the escape character. A test name with a
    # backtick in it -- which is most of this suite's, because MoonBit doc
    # comments and prose use markdown backticks -- therefore cannot match a
    # needle containing the same backtick. Bisected on the failing needle:
    #
    #     prefix 30 chars ("...inside a ")       -like -> True   (no backtick)
    #     prefix 40 chars ("...inside a `nor")   -like -> False  (one backtick)
    #     literal pattern '*noraise*'            -like -> True
    #     variable  pattern "*noraise*"          -like -> True
    #     variable  pattern "*<full needle>*"    -like -> False
    #
    # `-like` also treats `[` `]` as a wildcard SET and throws
    # `WildcardPatternException` on an unbalanced one, so a test name with a
    # bracket could crash the harness rather than merely miss.
    #
    # BOTH are the same defect seen from two sides: the check is a SUBSTRING
    # question and it was being answered with a PATTERN matcher. `IndexOf` with
    # Ordinal is that question, with no escapes and no wildcards.
    #
    # Only applied when the mutation actually wants to be KILLED: a declared
    # SURVIVED or a COMPILE-ERR has no red test to match, and failing there would
    # be checking something the caller did not ask for.
    $proved = $null
    if ($m.ContainsKey('MustRed') -and $want -eq 'KILLED') {
      $names = Get-RedTestNames $out
      $needle = [string]$m.MustRed
      $proved = @($names | Where-Object { $_.IndexOf($needle, [System.StringComparison]::Ordinal) -ge 0 }).Count -gt 0
      if (-not $proved) {
        # Loud, and names what DID go red. "KILLED" next to a false claim reads as
        # pinned, which is the whole failure this rule exists to prevent.
        Write-Output ('      MUST-RED MISS: "' + $needle + '" did not go red; these did:')
        foreach ($n in $names) { Write-Output ('        - ' + $n) }
        $script:MutationGateFailures += ($m.Name + ' (named test did not go red)')
      } else {
        $detail += ' [named test confirmed]'
      }
    }

    if ($outcome -eq 'INCONCLUSIVE') {
      # A FAILED MEASUREMENT IS NOT A VERDICT, and it is not the mutant's fault
      # either -- so it does not say "wanted SURVIVED", it says what happened.
      $script:MutationGateFailures += ($m.Name + ' (INCONCLUSIVE: the run did not happen -- a failed measurement, not a verdict)')
    } elseif ($outcome -ne $want) {
      $script:MutationGateFailures += ($m.Name + ' (wanted ' + $want + ')')
    }
    $results += [pscustomobject]@{ Mutation = $m.Name; Outcome = $outcome; Killed = $killed; Want = $want; Detail = $detail }

    # The tag marks a row that MATCHED its declaration. A row that came out
    # INCONCLUSIVE carries "[expected survivor]" next to a verdict it never got,
    # which reads like a pass.
    $tag = if ($want -eq 'SURVIVED' -and $outcome -eq 'SURVIVED') { '   [expected survivor]' } else { '' }
    Write-Output ('  ' + $outcome.PadRight(11) + ' ' + $m.Name + '  -- ' + $detail + $tag)

    # Rule 5. A declared non-KILLED outcome has to carry its argument -- and that
    # includes COMPILE-ERR, which is the easiest verdict to smuggle past: a mutant
    # that fails to build looks exactly like a mutant that was caught.
    if ($want -ne 'KILLED' -and $outcome -eq $want -and $m.ContainsKey('Prove')) {
      Write-Output ('      prove: ' + $m.Prove)
    }
  }

  Write-Output ''
  $results | Format-Table -AutoSize | Out-String -Width 200 | Write-Output
  $killedCount = @($results | Where-Object { $_.Outcome -eq 'KILLED' }).Count
  $survExpected = @($results | Where-Object { $_.Outcome -eq 'SURVIVED' }).Count
  Write-Output ("{0} killed, {1} expected survivor(s), of {2}; every restore verified byte-identical" -f $killedCount, $survExpected, $Mutations.Count)
}

function Write-MutationGateVerdict {
  # RETURNS NOTHING, ON PURPOSE. The first version of this function ended with
  # `return $true` / `return $false` AND used Write-Output for its messages, and
  # PowerShell put those messages into the return value: `$ok` became a
  # `System.Object[]`, every array is truthy, so `if (-not $ok)` never fired and a
  # gate that had ABORTED still exited 0. The exact failure this harness exists to
  # prevent, reintroduced by the harness.
  #
  # Callers read `$script:MutationGateFailures.Count` directly. A function that both
  # speaks and answers has to choose, and in PowerShell the speaking wins.
  param([string]$Name)
  if ($script:MutationGateFailures.Count -eq 0) {
    Write-Output ("GATE OK: " + $Name)
    return
  }
  Write-Output ("GATE FAILED: " + $Name)
  foreach ($f in $script:MutationGateFailures) { Write-Output ('  - ' + $f) }
}
