# Self-check through the JSON API, built by PowerShell because the payload
# embeds a source file that is far past the 32,767-char Windows command-line
# cap. --file exists for exactly this.
$ErrorActionPreference = 'Stop'
$root = 'D:\src\DeepseekHarness\Projects\xiuyueren\StaticAnalysis\moonbit_static_analysis'
$wasm = "$root\_build\wasm\debug\build\src\jsoncli\jsoncli.wasm"
$out  = "$env:TEMP\api_selfcheck"
New-Item -ItemType Directory -Force -Path $out | Out-Null

$targets = @(
  @{ rel = 'src\parser\parser.mbt' }
  @{ rel = 'src\types\infer.mbt' }
  @{ rel = 'src\walk\walk.mbt' }
)

foreach ($t in $targets) {
  $path = Join-Path $root $t.rel
  $src  = [System.IO.File]::ReadAllText($path)
  $req  = @{
    kind     = 'program'
    filename = ($t.rel -replace '\\','/')
    source   = $src
  } | ConvertTo-Json -Compress -Depth 5
  $reqFile = Join-Path $out ((Split-Path -Leaf $t.rel) + '.request.json')
  [System.IO.File]::WriteAllText($reqFile, $req, (New-Object System.Text.UTF8Encoding($false)))
  Write-Output ("{0,-26} request {1,7} bytes" -f $t.rel, $req.Length)

  Push-Location $root
  $reply = & C:\Users\31379\.moon\bin\moonrun.exe $wasm --file $reqFile 2>&1 | Out-String
  Pop-Location
  $replyFile = Join-Path $out ((Split-Path -Leaf $t.rel) + '.reply.json')
  [System.IO.File]::WriteAllText($replyFile, $reply, (New-Object System.Text.UTF8Encoding($false)))

  $j = $reply | ConvertFrom-Json
  Write-Output ("   ok={0}  count={1}  reply {2} bytes" -f $j.ok, $j.count, $reply.Length)
  foreach ($f in $j.findings) {
    Write-Output ("   {0}:{1}:{2}  [{3}] {4}" -f $f.file, $f.line, $f.col, $f.family, $f.message)
  }
  Write-Output ''
}