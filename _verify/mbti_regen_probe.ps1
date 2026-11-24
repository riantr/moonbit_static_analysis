# Is the .mbti regeneration a TOOLCHAIN behaviour or an accident?
#
# 0490 fixed FOUR stale pkg.generated.mbti files (ast, interp, pipeline, sa) by
# running `moon info` inside each package. During the 0490 release gate the
# installed toolchain was UPGRADED from 0.1.20261012 to 0.1.20261016, and after
# that five MORE .mbti files changed on their own: core, lexer, moonfiles,
# types, walk. Every change is the same shape -- `Int` -> `Int32`.
#
# That is the same defect 0490 already fixed in four files: the committed
# interface said `Int` while the source said `Int32` (0.1.20261012 renamed the
# default integer type and `moon fmt` rewrote the source, but the .mbti files
# were never regenerated).
#
# The question this script answers: did the new toolchain REGENERATE them, or
# did something else touch them? The answer decides what 0490's commit message
# is allowed to claim. It restores one file, runs `moon check`, and reports
# whether the file came BACK -- and whether it came back with `Int32`.
$ErrorActionPreference = 'Stop'
$root = 'D:\src\DeepseekHarness\Projects\xiuyueren\StaticAnalysis\moonbit_static_analysis'
Set-Location $root

$target = 'src\core\pkg.generated.mbti'
$moon   = 'C:\Users\31379\.moon\bin\moon.exe'

Write-Output 'BEFORE:'
Write-Output ('  has Int32 : ' + ((Get-Content -LiteralPath $target -Raw) -match 'Int32'))
Write-Output ('  has bare Int : ' + ((Get-Content -LiteralPath $target -Raw) -match '(?<![A-Za-z0-9_])Int(?![0-9A-Za-z_])'))

# Put the OLD text back -- the committed version, with `Int` and no `Int32`.
$old = & git show ('HEAD:' + ($target -replace '\\','/')) 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) { throw ('could not read the committed ' + $target + ': ' + $old) }
[System.IO.File]::WriteAllText((Join-Path $root $target), $old, (New-Object System.Text.UTF8Encoding($false)))
Write-Output ''
Write-Output 'RESTORED the committed version (Int, no Int32). Now running `moon check`...'

$prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
$o = (& $moon check --deny-warn 2>&1 | Out-String)
$code = $LASTEXITCODE
$ErrorActionPreference = $prev
Write-Output ('  moon check exit = ' + $code)

$now = Get-Content -LiteralPath $target -Raw
Write-Output ''
Write-Output 'AFTER `moon check`:'
Write-Output ('  has Int32 : ' + ($now -match 'Int32'))
Write-Output ('  has bare Int : ' + ($now -match '(?<![A-Za-z0-9_])Int(?![0-9A-Za-z_])'))
if ($now -match 'Int32') {
  Write-Output '  => THE TOOLCHAIN REGENERATED IT. `moon check` (or the build it drives) writes the'
  Write-Output '     interface file, and the committed `Int` spelling was simply stale.'
} else {
  Write-Output '  => `moon check` did NOT regenerate it. Something else wrote it, and 0490 must not'
  Write-Output '     claim the toolchain did.'
}
