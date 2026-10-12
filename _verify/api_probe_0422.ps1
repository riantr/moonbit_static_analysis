# Probe: why does a named/positional wrong argument type produce no finding?
# Runs several shapes through the JSON API and prints every finding, so the
# answer is read off the output rather than guessed from a test count.
#
# The S helper exists because a MoonBit source contains double quotes (for its
# own string literals). In a single-quoted PowerShell string those stay literal,
# and only the newline markers are expanded; a double-quoted string would need
# backtick escaping, which is the kind of quoting that silently eats a
# character.
$ErrorActionPreference = 'Stop'
$root = 'D:\src\DeepseekHarness\Projects\xiuyueren\StaticAnalysis\moonbit_static_analysis'
$wasm = "$root\_build\wasm\debug\build\src\jsoncli\jsoncli.wasm"
$out  = "$env:TEMP\api_probe_0422"
New-Item -ItemType Directory -Force -Path $out | Out-Null

function S([string]$t) { return ($t -replace '\\n', [string][char]10) }

$cases = @(
  @{ name = 'q1_tilde_both_wrong'
     src  = S 'fn from_logical(size? : Bool, scale? : Bool) -> Int {\n  0\n}\nfn build(size : Int, scale : Int) -> Int {\n  from_logical(scale~, size=size)\n}\n' }
  @{ name = 'q2_tilde_only_wrong'
     src  = S 'fn from_logical(size? : Bool, scale? : Int) -> Int {\n  0\n}\nfn build(size : Int, scale : Int) -> Int {\n  from_logical(scale~, size=size)\n}\n' }
  @{ name = 'q3_named_only_wrong'
     src  = S 'fn from_logical(size? : Bool, scale? : Int) -> Int {\n  0\n}\nfn build(size : Int, scale : Int) -> Int {\n  from_logical(size=size, scale=scale)\n}\n' }
  @{ name = 'q4_tilde_declared_first'
     src  = S 'fn from_logical(scale? : Bool, size? : Bool) -> Int {\n  0\n}\nfn build(size : Int, scale : Int) -> Int {\n  from_logical(scale~, size=size)\n}\n' }
)

foreach ($c in $cases) {
  $req = @{ kind = 'program'; filename = "$($c.name).mbt"; source = $c.src } |
         ConvertTo-Json -Compress -Depth 5
  $reqFile = Join-Path $out "$($c.name).request.json"
  [System.IO.File]::WriteAllText($reqFile, $req, (New-Object System.Text.UTF8Encoding($false)))
  Push-Location $root
  $reply = & C:\Users\31379\.moon\bin\moonrun.exe $wasm --file $reqFile 2>&1 | Out-String
  Pop-Location
  $j = $reply | ConvertFrom-Json
  Write-Output ("{0,-28} ok={1} count={2}" -f $c.name, $j.ok, $j.count)
  foreach ($f in $j.findings) {
    Write-Output ("    {0}:{1}  [{2}] {3}" -f $f.line, $f.col, $f.family, $f.message)
  }
  if ($c.name -eq 'q1_tilde_both_wrong') {
    Write-Output '    ---- rendered ----'
    foreach ($l in ($j.rendered -split "`n")) { Write-Output ("    " + $l) }
  }
  Write-Output ''
}