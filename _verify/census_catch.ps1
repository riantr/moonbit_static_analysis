# Census: what does a postfix `catch { ... }` handler look like in the corpora?
#
# WHY. The design for carrying the handler into the AST depends on which ARM
# SHAPES occur. A census is cheaper and more honest than guessing from the
# grammar probe: the grammar probe says what COMPILES, this says what the code
# we actually analyse WRITES.
#
# Classified per `catch` site by the first arm's text after `=>`:
#   block    -- `=> {`  (the shape the AST would carry as a statement list)
#   expr     -- `=>` followed by anything else on the same line
#   noarrow  -- no `=>` at all before the closing brace (a second production)
#   wildcard -- `=>` on the same line as `catch {` (the corpus shorthand)
#
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File _verify/census_catch.ps1
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$repos = Join-Path $root '.repos'
$moon = Join-Path $env:USERPROFILE '.moon\bin\moon.exe'

$targets = [ordered]@{
  moui             = Join-Path $repos 'wzzc-dev\moui\0.1.12'
  moonbit_labeler  = Join-Path $repos 'riantr\moonbit_labeler\0.2.13'
  moonbit_image    = Join-Path $repos 'riantr\moonbit_image\0.3.7'
  async            = Join-Path $repos 'moonbitlang\async\0.22.4'
  proton           = Join-Path $repos 'moonbit-community\proton\0.3.4'
  proton_contract  = Join-Path $repos 'moonbit-community\proton_contract\0.3.4'
}

$all = [ordered]@{}
foreach ($k in $targets.Keys) {
  $files = @(Get-ChildItem -Path $targets[$k] -Recurse -Include '*.mbt', '*.mbti' -File)
  $sites = 0
  $forms = [ordered]@{ block = 0; expr = 0; noarrow = 0; multiarm = 0; postsame = 0 }
  $samples = @{}
  foreach ($f in $files) {
    $lines = [System.IO.File]::ReadAllLines($f.FullName)
    for ($i = 0; $i -lt $lines.Length; $i++) {
      if ($lines[$i] -notmatch '\bcatch\s*\{') { continue }
      $sites++
      # Collect from this line until braces balance (cap 40 lines so a runaway
      # does not walk the rest of the file).
      $depth = 0; $chunk = @(); $started = $false
      for ($j = $i; $j -lt $lines.Length -and $j -lt $i + 40; $j++) {
        $chunk += $lines[$j]
        foreach ($ch in $lines[$j].ToCharArray()) {
          if ($ch -eq '{') { $depth++; $started = $true }
          elseif ($ch -eq '}') { $depth-- }
        }
        if ($started -and $depth -le 0) { break }
      }
      $text = ($chunk -join "`n")
      # How many `=>` arms? `=>` also appears in fn types; inside a catch chunk
      # at this size that is rare, and the counts below are a census not a proof.
      $arrows = ([regex]::Matches($text, '=>')).Count
      if ($arrows -ge 2) { $forms.multiarm++ }
      if ($text -match '\}\s*catch\s*\{\s*[^}\n]*=>') { $forms.postsame++ }
      if ($arrows -eq 0) { $forms.noarrow++; if (-not $samples.ContainsKey('noarrow')) { $samples['noarrow'] = ($f.Name + ':' + ($i + 1)) } }
      else {
        $kind = if ($text -match '=>\s*\{') { 'block' } else { 'expr' }
        $forms[$kind]++
        if (-not $samples.ContainsKey($kind)) { $samples[$kind] = ($f.Name + ':' + ($i + 1)) }
      }
      $all["$k|" + ($f.Name) + ':' + ($i + 1)] = $text
    }
  }
  $sum = $forms.block + $forms.expr + $forms.noarrow
  Write-Output ('{0,-16} sites={1,-5} block={2,-5} expr={3,-5} noarrow={4,-4} (sum {5}/{1} sites, rest are multi-arm or same-line)' -f `
    $k, $sites, $forms.block, $forms.expr, $forms.noarrow, $sum)
  foreach ($sk in $samples.Keys) { Write-Output ('                 {0,-9} first: {1}' -f $sk, $samples[$sk]) }
}
$dump = Join-Path $env:TEMP 'catch_sites.txt'
[System.IO.File]::WriteAllLines($dump, $all.Keys)
Write-Output ''
Write-Output ('per-site text: ' + $dump)
