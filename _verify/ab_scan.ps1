# A/B two analyzer builds over the SAME corpus, and refuse to compare them if their
# interface trees differ.
#
# WHY THIS EXISTS. An A/B that does not verify its own inputs agrees with a broken one by
# coincidence, and the coincidence is indistinguishable from the result. That is not
# hypothetical: NARRATIVE 0477 records an A/B that reported the right answer for entirely the
# wrong reason, and the first diagnosis of it ("`--extern-iface-dir` is ignored") was itself
# wrong. Measured 2026-10-18, same binary, same CWD, proton 0.3.4:
#
#                        IFACE types   values        dirs   actionable
#        with the flag        1490      11315            2           0
#        without it             205       1755            1          36
#
# The flag IS honoured (sa/main.mbt:239-243 pushes each --extern-iface-dir onto a list that
# already holds the target root). What actually moves with the process CWD is auto_fetch_deps:
# sa/main.mbt:483 fetches into a path RELATIVE to the CWD ("let base = \".repos/\" + mod"), so
# two runs in different directories can index different trees even when both pass the flag.
#
# THE INSTRUMENT is the IFACE line the scan prints (sa/main.mbt:244-248). It reports how many
# type and value names were indexed and how many directories were searched. Comparing that
# triple across the two runs is what makes an A/B trustworthy, and it is cheap.
#
# USAGE
#   powershell -File _verify\ab_scan.ps1 -Corpus <dir> -WasmA <a.wasm> [-WasmB <b.wasm>]
#
# With one -Wasm it scans that build twice, which is the CONTROL case: two identical runs
# must produce an identical IFACE triple and identical summaries. If they do not, the scanner
# is not deterministic on this input and no A/B on it means anything.
param(
  [Parameter(Mandatory = $true)][string]$Corpus,
  [Parameter(Mandatory = $true)][string]$WasmA,
  [string]$WasmB = '',
  [string]$ExternDir = '',
  # The run B's working directory. THE ORIGINAL FAILURE MODE WAS THIS: two runs in
  # different CWDs, same flag, different auto-fetched trees. Supplying it lets the script
  # reproduce that confound on purpose instead of only being careful about it.
  [string]$CwdB = '',
  [string]$Moonrun = 'C:\Users\31379\.moon\bin\moonrun.exe'
)

$ErrorActionPreference = 'Stop'

# THE WASM PATHS ARE MADE ABSOLUTE HERE, and that is load-bearing rather than tidy. A run
# whose WorkingDirectory differs from this one cannot find a relative wasm path, so it would
# produce no output at all and the guard would abort for a reason that has nothing to do with
# the interface tree. Resolving first leaves exactly ONE variable free to differ -- where
# `--extern-iface-dir` resolves -- which is the variable under test.
if (-not [System.IO.Path]::IsPathRooted($WasmA)) { $WasmA = (Resolve-Path $WasmA).Path }
if ($WasmB -ne '' -and -not [System.IO.Path]::IsPathRooted($WasmB)) { $WasmB = (Resolve-Path $WasmB).Path }

if ($ExternDir -eq '') { $ExternDir = '.repos' }

function Invoke-Scan {
  param([string]$Wasm, [string]$Label, [string]$Cwd = '')
  $dir = Join-Path $env:TEMP ('ab_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  $out = Join-Path $dir 'o.txt'
  $err = Join-Path $dir 'o.err'
  $sp = @{
    FilePath               = $Moonrun
    ArgumentList           = @($Wasm, $Corpus, '--extern-iface-dir', $ExternDir)
    RedirectStandardOutput = $out
    RedirectStandardError  = $err
    NoNewWindow            = $true
    Wait                   = $true
  }
  if ($Cwd -ne '') { $sp['WorkingDirectory'] = $Cwd }
  Start-Process @sp | Out-Null
  # `Start-Process -Wait` waits for the PROCESS. It does not promise the redirected output
  # file's handle is closed, and on this machine it is not -- release.ps1 carries
  # Read-TextWhenFree for exactly this, and reads the resulting lock as an EMPTY scan, which
  # is indistinguishable from a scan that found nothing. Reused here for the same reason.
  # The IFACE line is parsed even when the run produced no SUMMARY, because a run that lost
  # its tree is precisely the case this script must catch.
  $text = ''
  $locked = $false
  for ($i = 1; $i -le 20; $i++) {
    try {
      $text = [System.IO.File]::ReadAllText($out)
      break
    } catch [System.IO.IOException] {
      $locked = $true
      Start-Sleep -Milliseconds 250
    }
  }
  if ($locked -and $text -eq '') {
    Write-Output ("ABORT: " + $Label + " -- its redirected stdout was still locked after 20 attempts.")
    Write-Output '       This is a HARNESS failure, not a corpus result. Nothing was compared.'
    exit 1
  }
  $iface = ([regex]::Match($text, '(?m)^IFACE\ttypes=(\d+)\tvalues=(\d+)\s+\(dirs=(\d+)\)'))
  $summary = ([regex]::Match($text, '(?m)^SUMMARY.*$').Value) -replace "`t", ' '
  [pscustomobject]@{
    Label   = $Label
    Wasm    = $Wasm
    Cwd     = $(if ($Cwd -eq '') { '(this one)' } else { $Cwd })
    HasIface = $iface.Success
    Types   = $(if ($iface.Success) { [int]$iface.Groups[1].Value } else { -1 })
    Values  = $(if ($iface.Success) { [int]$iface.Groups[2].Value } else { -1 })
    Dirs    = $(if ($iface.Success) { [int]$iface.Groups[3].Value } else { -1 })
    Summary = ($summary -replace '^SUMMARY\s*', '') -replace '\s*\(actionable.*$', ''
  }
}

$a = Invoke-Scan -Wasm $WasmA -Label 'A'
$b = $(if ($WasmB -eq '') { Invoke-Scan -Wasm $WasmA -Label 'A(again)' -Cwd $CwdB }
        else { Invoke-Scan -Wasm $WasmB -Label 'B' -Cwd $CwdB })

Write-Output ('corpus : ' + $Corpus)
Write-Output ('extern : ' + $ExternDir)
foreach ($r in @($a, $b)) {
  Write-Output ("  {0,-9} types={1,-6} values={2,-6} dirs={3,-3} {4}" -f $r.Label, $r.Types, $r.Values, $r.Dirs, $r.Summary)
  Write-Output ("             cwd: " + $r.Cwd)
}

Write-Output ''
if (-not ($a.HasIface -and $b.HasIface)) {
  Write-Output 'ABORT: a run printed no IFACE line, so its interface tree is unknown.'
  Write-Output '       Comparing counts from runs whose inputs you cannot see is the failure'
  Write-Output '       this script exists to prevent. Nothing was compared.'
  exit 1
}

if ($a.Types -ne $b.Types -or $a.Values -ne $b.Values -or $a.Dirs -ne $b.Dirs) {
  Write-Output 'ABORT: THE TWO RUNS INDEXED DIFFERENT INTERFACE TREES.'
  Write-Output ("       A types/values/dirs = {0}/{1}/{2}" -f $a.Types, $a.Values, $a.Dirs)
  Write-Output ("       B types/values/dirs = {0}/{1}/{2}" -f $b.Types, $b.Values, $b.Dirs)
  Write-Output '       Any count difference below is uninterpretable. Fix the inputs first:'
  Write-Output '       run both from ONE CWD, and pass an --extern-iface-dir that resolves in it.'
  exit 1
}

Write-Output 'IFACE triples agree, so a difference in the summaries is attributable to the build.'
if ($a.Summary -eq $b.Summary) {
  Write-Output 'RESULT: identical. The two runs agree on every counted number.'
  exit 0
}
Write-Output 'RESULT: the summaries DIFFER. That is a real difference between the two builds.'
exit 0
