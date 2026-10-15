# Measures what the 0450 `parse_block` fix did to a corpus's UNRELIABLE findings.
#
# WHY THIS EXISTS. The release run showed actionable 0 everywhere and `parsed=` up
# by one file, but `unreliable` UP on async (+8) and proton (+26). Unreliable
# findings are already excluded from actionable, so the shipping gate passes -- but
# "a fix that lowers one corpus and raises another" is a standing refusal, and the
# question is not whether the count moved but whether the new entries are a NEW
# CLASS of wrong finding or merely more of the right ones in code that used to be
# unread.
#
# Only a before/after diff answers that, and the diff has to be taken on SCANNED
# OUTPUT, not on source: the scanner reads the prebuilt wasm, so the mutation has to
# be rebuilt before it is re-scanned. Skipping the rebuild is how a measurement of
# this shape silently measures nothing.
#
# RESTORE IS PROVEN BY SHA256, and the backup is taken BEFORE the edit.

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$enc = New-Object System.Text.UTF8Encoding($false)
$parser = Join-Path $root 'src\parser\parser.mbt'
$wasm = Join-Path $root '_build\wasm\debug\build\moonbit_static_analysis.wasm'
$moon = 'C:\Users\31379\.moon\bin\moon.exe'
$moonrun = 'C:\Users\31379\.moon\bin\moonrun.exe'

$nl = [string][char]10
$bytes0 = [System.IO.File]::ReadAllBytes($parser)
$sha0 = (Get-FileHash -LiteralPath $parser -Algorithm SHA256).Hash
$text0 = [System.Text.Encoding]::UTF8.GetString($bytes0)
$find = '    if self.at_name("fn") && self.name_at(self.p + 1) != "" {'
$repl = '    if self.at_name("fn") {'
if ($text0.IndexOf($find, [System.StringComparison]::Ordinal) -lt 0) {
  Write-Output 'ABORT: the anchor is absent, so this would measure nothing.'
  exit 1
}

function Scan-Target([string]$rel) {
  $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  Push-Location $root
  $null = & $moon build --target wasm 2>&1
  $out = & $moonrun $wasm $rel '--extern-iface-dir' '.repos' 2>&1 | Out-String
  Pop-Location
  $ErrorActionPreference = $prev
  return ($out -split "`r?`n")
}

$targets = @(
  @{ Name = 'async';  Path = '.repos\moonbitlang\async\0.22.4' },
  @{ Name = 'proton'; Path = '.repos\moonbit-community\proton\0.3.4' }
)

try {
  foreach ($t in $targets) {
    Write-Output ('=== ' + $t.Name + ' (AFTER the fix) ===')
    $after = Scan-Target $t.Path
    ($after | Where-Object { $_ -like 'SUMMARY*' }) | ForEach-Object { '  ' + $_ }

    # Reverse the fix, rebuild, re-scan.
    [System.IO.File]::WriteAllText($parser, $text0.Replace($find, $repl), $enc)
    Write-Output ('=== ' + $t.Name + ' (BEFORE the fix) ===')
    $before = Scan-Target $t.Path
    ($before | Where-Object { $_ -like 'SUMMARY*' }) | ForEach-Object { '  ' + $_ }

    # Restore before anything else, and prove it.
    [System.IO.File]::WriteAllBytes($parser, $bytes0)
    if ($sha0 -ne (Get-FileHash -LiteralPath $parser -Algorithm SHA256).Hash) {
      Write-Output ('RESTORE MISMATCH on ' + $t.Name)
      exit 1
    }

    # WHAT ACTUALLY MOVED. The first version of this script compared only the
    # printed `LINE:COL - error: ...` lines and reported added=0 removed=0 on both
    # corpora -- while the SUMMARY beside it said `unreliable` had gone 1193 -> 1201
    # and 1077 -> 1103. Byte-identical lists and a moving count cannot both be
    # true, so the instrument was wrong: the findings that moved are in a
    # population this scanner does NOT print one line per finding for.
    #
    # That is the same failure the corpus has punished before -- a probe that
    # engages its instrument and prints a clean, confident zero is worse than one
    # that prints nothing, because the zero looks like a result. So this now diffs
    # EVERY non-empty line and names the lines that are not the SUMMARY, rather
    # than assuming where the findings are printed.
    $la = @($after  | Where-Object { $_.Trim() -ne '' })
    $lb = @($before | Where-Object { $_.Trim() -ne '' })
    $diff = @(Compare-Object $lb $la)
    Write-Output ('  all lines before=' + $lb.Count + ' after=' + $la.Count + '  differing=' + $diff.Count)
    Write-Output '  -- every differing line that is NOT the SUMMARY --'
    $nonSummary = @($diff | Where-Object { $_.InputObject -notlike 'SUMMARY*' })
    if ($nonSummary.Count -eq 0) {
      Write-Output '    (none -- the only difference is the SUMMARY line itself)'
    } else {
      $nonSummary | ForEach-Object { '    ' + $_.SideIndicator + ' ' + $_.InputObject }
    }
    Write-Output ''
  }
}
finally {
  [System.IO.File]::WriteAllBytes($parser, $bytes0)
  $shaEnd = (Get-FileHash -LiteralPath $parser -Algorithm SHA256).Hash
  if ($sha0 -ne $shaEnd) { Write-Output 'FINAL RESTORE MISMATCH -- the source is left mutated.'; exit 1 }
  Write-Output 'restore verified byte-identical at exit'
}
