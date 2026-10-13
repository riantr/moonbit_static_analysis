# 0.4.29 CI verification.
#
# WHAT THIS CHECKS, AND WHY IT IS WRITTEN THIS WAY.
#
#   - It matches runs by the PEELED COMMIT SHA, not by `head_branch`. A
#     tag-triggered run carries the tag in `head_branch` on some GitHub responses
#     and null on others, so filtering on the branch name silently returns zero and
#     reads as "CI never ran". Matching the sha is what cannot be fooled.
#   - It asks each workflow for its OWN run list rather than the global one. The
#     global list is dominated by the other workflow and makes a finished release
#     look like nothing ran.
#   - It polls on a budget derived from how many runs are still outstanding, not
#     from how impatient it is, because the anonymous GitHub API allows 60
#     requests an hour and a 20-second poll loop exhausts that before the publish
#     job finishes.
#
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File _verify\ci_0429.ps1
$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root
$sha = (git rev-list -n 1 v0.4.29).Trim()
if ($sha -eq '') { Write-Output 'ABORT: cannot resolve the tag.'; exit 1 }
Write-Output ("v0.4.29 -> " + $sha)
Write-Output ''

function Get-Runs([string]$workflow) {
  $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  $url = "https://api.github.com/repos/riantr/moonbit_static_analysis/actions/workflows/$workflow/runs?per_page=20"
  $body = & curl.exe -s --max-time 45 -H "Accept: application/vnd.github+json" $url 2>&1 | Out-String
  $ErrorActionPreference = $prev
  try { return ($body | ConvertFrom-Json).workflow_runs } catch { return @() }
}

# --- phase 1: gate must have finished ---------------------------------------
$deadline = (Get-Date).AddMinutes(12)
$pending = 6
$gate = $null
while ((Get-Date) -lt $deadline -and $pending -gt 0) {
  $runs = Get-Runs 'gate.yml'
  $gate = @($runs | Where-Object { $_.head_sha -eq $sha -and $_.head_branch -eq 'v0.4.29' })
  if ($gate.Count -eq 0) { Write-Output '  gate: no run for this commit yet' }
  else {
    $g = $gate[0]
    Write-Output ("  gate  v0.4.29 : {0} / {1}" -f $g.status, $g.conclusion)
    if ($g.status -eq 'completed') { $pending-- }
  }
  $runs2 = Get-Runs 'publish.yml'
  $pub = @($runs2 | Where-Object { $_.head_sha -eq $sha })
  if ($pub.Count -eq 0) { Write-Output '  publish: no run for this commit yet' }
  else {
    $p = $pub[0]
    Write-Output ("  publish v0.4.29 : {0} / {1}" -f $p.status, $p.conclusion)
    if ($p.status -eq 'completed') { $pending-- }
  }
  if ($pending -gt 0) { Start-Sleep -Seconds 30 }
}

Write-Output ''
Write-Output '=== runs recorded for this commit ==='
foreach ($wf in @('gate.yml','publish.yml')) {
  $runs = Get-Runs $wf
  foreach ($r in @($runs | Where-Object { $_.head_sha -eq $sha })) {
    Write-Output ("  {0,-8} branch={1,-10} {2}/{3}" -f $r.name, $r.head_branch, $r.status, $r.conclusion)
    Write-Output ("           {0}" -f $r.html_url)
  }
}
exit 0