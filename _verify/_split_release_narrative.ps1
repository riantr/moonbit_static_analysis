# One-shot: move release.ps1's PER-INCREMENT NARRATIVE into its own file.
#
# WHY. Measured on release.ps1 at 0470: 1811 lines total, of which 262 are code. The other
# 1524 are comments, and 1270 of THOSE sit in one contiguous block between the corpus stage
# and the pin table -- one block per increment, appended forever. The 0450 block alone is
# 454 lines, a quarter of the file's executable length.
#
# A release entry point you cannot read is not an entry point, and the cost is paid by
# whoever has to verify a release. This splits it by KIND, not by size:
#
#   STAYS in release.ps1   the harness, the stages, the pin table, and the documentation
#                          that explains code ADJACENT to it (a reader needs that at the site)
#   MOVES to NARRATIVE.md  the per-increment historical record: what was wrong, what it was
#                          settled against, what the evidence was
#
# The second kind is history. History at the top of a release script is what pushed the
# entry point to 84% comment.
#
# => 判据: a refactor of the thing that verifies the release must be verified BY the thing
# that verifies the release. This script changes no expectation, no pin, and no threshold;
# if the gate did not pass identically afterwards, the script would be wrong and so would
# this extraction.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$src = Join-Path $root '_verify\release.ps1'
$dst = Join-Path $root '_verify\NARRATIVE.md'
$enc = New-Object System.Text.UTF8Encoding($false)

$lines = [IO.File]::ReadAllLines($src, [System.Text.Encoding]::UTF8)

# Locate the contiguous comment-only region rather than trusting a hard-coded range, so the
# script says what it did instead of assuming where the boundary was.
$first = -1
$last = -1
for ($i = 0; $i -lt $lines.Length; $i++) {
  $t = $lines[$i].TrimStart()
  if ($t.StartsWith('# --- 0.4.30')) { $first = $i }
  if ($first -ge 0 -and $last -lt 0 -and $t -notmatch '^#' -and $t -ne '') {
    # first non-comment line after the region began
    $last = $i - 1
    break
  }
}
if ($first -lt 0 -or $last -lt 0) { throw "narrative region not found (first=$first last=$last)" }
Write-Output ("narrative region: lines {0}..{1}  ({2} lines)" -f ($first + 1), ($last + 1), ($last - $first + 1))

# --- build NARRATIVE.md ------------------------------------------------------
$out = New-Object System.Collections.Generic.List[string]
$out.Add('# Increment narrative')
$out.Add('')
$out.Add('Extracted from `_verify/release.ps1` by `_verify/_split_release_narrative.ps1`.')
$out.Add('Nothing here is executable and nothing here is an expectation: `release.ps1` does not')
$out.Add('read this file. It is the record of what each increment was WRONG about, what it was')
$out.Add('settled against, and what the evidence was -- the part a future reader needs and cannot')
$out.Add('reconstruct from the diff alone.')
$out.Add('')
$out.Add('It lived inside the release script because that was the only file being read at the')
$out.Add('time. At 0470 the script measured 1811 lines with 262 of them code: 84% narrative, and')
$out.Add('1270 contiguous lines of it between the corpus stage and the pin table. A release entry')
$out.Add('point nobody can skim is not an entry point.')
$out.Add('')
$out.Add('Newest first would need re-sorting on every increment, so this is chronological, the')
$out.Add('order the blocks were written in. The live caveats that bear on the pin table itself')
$out.Add('stayed in `release.ps1` next to the table.')
$out.Add('')
$out.Add('---')
$out.Add('')

$prevBlank = 0
$i = $first
while ($i -le $last) {
  $l = $lines[$i]
  $t = $l.TrimStart()

  # A section marker. THREE shapes exist and the first two drafts of this script each got
  # one of them wrong:
  #   - a line that is only `# ---` (an OPENING marker, title on the following lines). The
  #     second draft treated it as an unclosed heading and accumulated until the next
  #     `----` line, which swallowed FOUR increments into one heading;
  #   - a BARE separator `# ------` with no title, which became `## -`;
  #   - a heading whose closer is not on its own line (0449: `# --- title` then
  #     `#     continuation ---`), which a single-line regex misses entirely.
  if ($t -match '^#\s*-{3,}\s*(.*)$') {
    $title = $Matches[1]
    if ($title.Trim() -eq '') { $i++; continue }   # bare separator or opening marker
    $closed = ($title -match '-{3,}\s*$')
    $i++
    while (-not $closed -and $i -le $last) {
      $nt = $lines[$i].TrimStart()
      if ($nt -match '^#\s*-{3,}') { break }            # the next marker starts here
      if ($nt -notmatch '^#(\s{2,})(.*)$') { break }   # not an indented continuation
      $seg = $Matches[2]
      if ($seg -match '-{3,}\s*$') { $closed = $true }
      $title = $title.TrimEnd() + ' ' + $seg.Trim()
      $i++
    }
    $title = ($title -replace '-{3,}\s*$', '').Trim()
    if ($title -ne '') {
      $out.Add('')
      $out.Add('## ' + $title)
      $out.Add('')
      $prevBlank = 0
    }
    continue
  }

  $i++
  if ($t -eq '#') { $out.Add(''); $prevBlank++; continue }
  $body = $l -replace '^\# ?', ''
  $out.Add($body)
  $prevBlank = 0
}
# collapse runs of blank lines
$collapsed = New-Object System.Collections.Generic.List[string]
$run = 0
foreach ($l in $out) {
  if ($l -eq '') { $run++ } else { $run = 0 }
  if ($run -le 2) { $collapsed.Add($l) }
}
while ($collapsed.Count -gt 0 -and $collapsed[$collapsed.Count - 1] -eq '') { $collapsed.RemoveAt($collapsed.Count - 1) }

[IO.File]::WriteAllLines($dst, $collapsed, $enc)
Write-Output ("wrote {0}  ({1} lines)" -f $dst, $collapsed.Count)

# --- rewrite release.ps1 -----------------------------------------------------
$pointer = @(
  '# --- the per-increment narrative now lives in NARRATIVE.md ------------------',
  '#',
  '# Everything between here used to be in this file: one comment block per increment, 1270',
  '# lines of it at 0470, against 262 lines of code in the whole script. It was moved by',
  '# `_verify/_split_release_narrative.ps1` -- verbatim, minus the leading comment marker.',
  '#',
  '# WHAT STAYS HERE, and why: the harness, the stages, the pin table, and the notes that',
  '# explain code ADJACENT to them. A reader verifying a release needs those at the site. The',
  '# moved text is history -- what an increment got wrong, what it was settled against, which',
  '# corpus moved -- and history at the top of the release script is what made the entry',
  '# point unreadable.',
  '#',
  '# THREE LIVE CAVEATS that bear on the pin table below stayed here deliberately, because',
  '# they are claims about THESE numbers rather than about a past increment:',
  '#',
  '#   - the six SUMMARY lines carry ZERO signal about the behavior lens, which no pinned',
  '#     corpus reaches (7493 findings, none of them from that lens; see the DIRECTION 2',
  '#     block in NARRATIVE.md). A pin that cannot distinguish two states is not a pin.',
  '#   - `moonbit_labeler` moved 801 -> 800 at 0470, the last `actionable` on any corpus.',
  '#     The other five are byte-identical, and five-unchanged is what makes the sixth mean',
  '#     something.',
  "#   - ``parse_block``'s parameter is named ``value_block``, not ``fn_body``. The old name is",
  '#     what let a real bug read as a decision.',
  '#'
) -split "`r?`n"

$new = New-Object System.Collections.Generic.List[string]
for ($i = 0; $i -lt $first; $i++) { $new.Add($lines[$i]) }
foreach ($l in $pointer) { if ($l -ne '') { $new.Add($l) } }
for ($i = $last + 1; $i -lt $lines.Length; $i++) { $new.Add($lines[$i]) }
[IO.File]::WriteAllLines($src, $new, $enc)
Write-Output ("rewrote release.ps1  ({0} -> {1} lines)" -f $lines.Length, $new.Count)
