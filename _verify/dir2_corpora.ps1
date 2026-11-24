# Direction 2, step 2: MEASURE the per-function view against the module view on
# every pinned corpus.
#
# The module entry is the default and is what the corpus pins measure. The
# per-function entry is a SEPARATE view: the behavioral lens enters at each
# function instead of at the module.
#
# What this answers, per corpus:
#   - how many findings does the per-function view add?
#   - how many are tagged `behavior`? (the lens that was silent)
#   - how many are ERROR severity? (actionable -- a false positive here is a
#     finding on code `moon check` accepts, which is the worst shape)
#   - are the module view's numbers UNCHANGED? (the per-function view must not
#     disturb the view the pins measure)
$ErrorActionPreference = 'Continue'

$root    = 'D:\src\DeepseekHarness\Projects\xiuyueren\StaticAnalysis\moonbit_static_analysis'
$repos   = Join-Path $root '.repos'
$wasm    = Join-Path $root '_build\wasm\debug\build\moonbit_static_analysis.wasm'
$moonrun = 'C:\Users\31379\.moon\bin\moonrun.exe'

$corpora = [ordered]@{
  'moui'            = 'wzzc-dev\moui\0.1.12'
  'moonbit_labeler' = 'riantr\moonbit_labeler\0.2.13'
  'moonbit_image'   = 'riantr\moonbit_image\0.3.7'
  'async'           = 'moonbitlang\async\0.22.4'
  'proton'          = 'moonbit-community\proton\0.3.4'
  'proton_contract' = 'moonbit-community\proton_contract\0.3.4'
}

function Measure-View([string]$dir, [bool]$perfn) {
  $out = Join-Path $env:TEMP ('dir2m_' + [guid]::NewGuid().ToString('N').Substring(0, 6) + '.txt')
  if ($perfn) {
    & $moonrun $wasm $dir --extern-iface-dir $repos --per-function 2>&1 | Out-File -FilePath $out -Encoding utf8
  } else {
    & $moonrun $wasm $dir --extern-iface-dir $repos 2>&1 | Out-File -FilePath $out -Encoding utf8
  }
  $c = @(Get-Content -LiteralPath $out)
  $tags = @{}
  $errs = 0
  $errTag = @{}
  foreach ($l in $c) {
    if ($l -match '\[([a-z+]+)\]\s*$') {
      $t = $Matches[1]
      if ($tags.ContainsKey($t)) { $tags[$t]++ } else { $tags[$t] = 1 }
      if ($l -match ' - error: ') {
        $errs++
        if ($errTag.ContainsKey($t)) { $errTag[$t]++ } else { $errTag[$t] = 1 }
      }
    }
  }
  $summary = ''
  foreach ($l in $c) { if ($l -like 'SUMMARY*') { $summary = $l; break } }
  Remove-Item -LiteralPath $out -Force -ErrorAction SilentlyContinue
  return [pscustomobject]@{ Tags = $tags; Errs = $errs; ErrTag = $errTag; Summary = $summary }
}

function TagStr($h) {
  if ($null -eq $h -or $h.Count -eq 0) { return '(none)' }
  $parts = @()
  foreach ($k in ($h.Keys | Sort-Object)) { $parts += ('{0}={1}' -f $k, $h[$k]) }
  return ($parts -join ' ')
}

Write-Output '=== Direction 2: the per-function view vs the module view ==='
Write-Output ''
Write-Output ('  {0,-16} {1,-8} {2,-46} {3}' -f 'corpus', 'view', 'lens tags (total)', 'errors by tag')
Write-Output ('  ' + ('-' * 104))

foreach ($k in $corpora.Keys) {
  $dir = Join-Path $repos $corpora[$k]
  if (-not (Test-Path -LiteralPath $dir)) { Write-Output ("  {0,-16} MISSING" -f $k); continue }
  foreach ($view in @(@('module', $false), @('perfn', $true))) {
    $r = Measure-View $dir $view[1]
    Write-Output ('  {0,-16} {1,-8} {2,-46} {3}' -f $k, $view[0], (TagStr $r.Tags), (TagStr $r.ErrTag))
    if ($view[0] -eq 'module') {
      Write-Output ('  {0,-16} {1,-8} {2}' -f '', '', $r.Summary)
    }
  }
}
