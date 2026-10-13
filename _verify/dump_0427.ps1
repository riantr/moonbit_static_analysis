# Dump each corpus's FULL analyzer output to a file, for a byte-level A/B.
#
# 0.4.27's first scan produced numbers that LOOK like a big win -- proton
# actionable 100 -> 68 -- but that baseline was taken on the TEMP sibling tree
# and this scan runs against the project's `.repos`. Those two trees are not
# interchangeable: `--extern-iface-dir` feeds sibling interface tables into the
# run, so a different tree legitimately yields different counts. Comparing a
# number across two trees measures the trees, not the change.
#
# The only comparison that attributes anything to a code change is the SAME tree,
# TWO BUILDS. So this script takes a label and writes one full dump per corpus.
#
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File _verify/dump_0427.ps1 <label>
$ErrorActionPreference = 'Continue'
$label = $args[0]
if (-not $label) { Write-Output 'usage: dump_0427.ps1 <label>'; exit 2 }
$root = Split-Path -Parent $PSScriptRoot
$wasm = "$root\_build\wasm\debug\build\moonbit_static_analysis.wasm"
$repos = "$root\.repos"
$outdir = Join-Path $env:TEMP "fin_$label"
New-Item -ItemType Directory -Force -Path $outdir | Out-Null

$targets = [ordered]@{
  'moui'            = "$repos\wzzc-dev\moui\0.1.12"
  'moonbit_labeler' = "$repos\riantr\moonbit_labeler\0.2.13"
  'moonbit_image'   = "$repos\riantr\moonbit_image\0.3.7"
  'async'           = "$repos\moonbitlang\async\0.22.4"
  'proton'          = "$repos\moonbit-community\proton\0.3.4"
  'proton_contract' = "$repos\moonbit-community\proton_contract\0.3.4"
}

Set-Location $root
if (-not (Test-Path $wasm)) { Write-Output ("MISSING WASM: " + $wasm); exit 1 }
$abs = (Resolve-Path $wasm).Path
$moonrun = 'C:\Users\31379\.moon\bin\moonrun.exe'
foreach ($k in $targets.Keys) {
  $p = $targets[$k]
  $n = @(Get-ChildItem -Path $p -Recurse -File -Filter '*.mbt' -ErrorAction SilentlyContinue |
         Where-Object { $_.FullName -notmatch '\\\.mooncakes\\' }).Count
  if ($n -eq 0) { Write-Output ("{0,-16} NO CORPUS -- aborting, NOT a zero" -f $k); exit 1 }
  $out = Join-Path $outdir "$k.txt"
  $err = Join-Path $outdir "$k.err"
  # Start-Process takes an ARGUMENT ARRAY, so the paths need no quoting at all.
  # The first version shelled out to `cmd.exe /c "... > file 2>&1"` and the
  # embedded quotes were mangled by PowerShell's native-argument handling: cmd
  # exited without running anything, every dump came back 0 BYTES, and the script
  # still printed a line per corpus and exited 0. A differential gate that
  # diffs two 0-byte files reports "identical" and is worthless -- so the check
  # below is not decoration.
  $proc = Start-Process -FilePath $moonrun `
      -ArgumentList @($abs, $p, '--extern-iface-dir', $repos, '--no-auto-fetch-deps') `
      -RedirectStandardOutput $out -RedirectStandardError $err -NoNewWindow -Wait -PassThru
  $len = (Get-Item $out).Length
  if ($len -eq 0) {
    Write-Output ("{0,-16} EMPTY DUMP (exit {1}) -- aborting, NOT a zero" -f $k, $proc.ExitCode)
    Write-Output ("      stderr: " + ((Get-Content $err -Raw -EA SilentlyContinue) -replace '\s+', ' '))
    exit 1
  }
  $sum = (Select-String -Path $out -Pattern '^SUMMARY' | Select-Object -First 1).Line
  Write-Output ("{0,-16} files={1,-5} bytes={2,-9} {3}" -f $k, $n, $len, $sum)
}
Write-Output ("DUMP DIR: " + $outdir)
exit 0