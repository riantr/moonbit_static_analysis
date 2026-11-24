# Are the 102 names the new toolchain's core no longer declares type-qualified
# still CALLABLE?
#
# WHY THIS IS THE DECISION. The builtin-methods table is a SUPPRESSION list, and
# its two failure directions are not symmetric:
#
#   keeping a name the toolchain has DROPPED  -> a MISSED report
#   dropping a name the toolchain still HAS    -> a FALSE POSITIVE
#
# The table's own header says it accepts the first and not the second. The
# generator run on the new toolchain produced 1163 names against the committed
# 1265, so 102 were dropped -- and the settle already showed the two directions
# are MIXED: `Int::abs` is still ACCEPTED (the new core declares it bare, in
# the `int` package, and the qualified call still resolves), while
# `Buffer::write` and `Double::nan` are genuinely gone (4015).
#
# ONE MODULE PER NAME. The first version of this probe put all 102 names in ONE
# file, on the theory that a name's liveness does not depend on its
# neighbours'. That is true of the SEMANTICS and false of the TOOLCHAIN: the
# compiler reports a bounded number of errors and then STOPS, so the names
# after the cut were never checked.
#
# And the version of this script that did it that way had a SECOND bug on top
# of that: it recorded each name's INDEX where the compiler reports a FILE
# LINE, and the two differ by three per name. It produced a confident 51/51
# split -- twice, with two DIFFERENT halves, because the index mapping and the
# early-stop cut moved independently. Both halves were wrong.
#
# WHAT CAUGHT IT was the CONTROL: a name that cannot exist, placed LAST. The
# control was not reported, which means the compiler had already stopped, which
# means the "alive" list was a list of names the compiler never reached. The
# control is not decoration -- it is the only thing that distinguishes "this
# name is alive" from "the compiler gave up before reaching it".
#
# So: one module per name, the control beside each, and the whole set is
# checked for the control's presence before ANY conclusion is drawn.
$ErrorActionPreference = 'Stop'
$repo = 'D:\src\DeepseekHarness\Projects\xiuyueren\StaticAnalysis\moonbit_static_analysis'
$moon = 'C:\Users\31379\.moon\bin\moon.exe'
$root = Join-Path $env:TEMP 'dir2builtins_alive3'
if (Test-Path $root) { Remove-Item -LiteralPath $root -Recurse -Force }

# --- the 102: committed table minus the regenerated one ---------------------
$rx = '"([A-Za-z_][A-Za-z0-9_]*::[A-Za-z_][A-Za-z0-9_]*)"'
function Get-Names([string]$path) {
  $set = [System.Collections.Generic.HashSet[string]]::new()
  $t = Get-Content -LiteralPath $path -Raw
  foreach ($m in [regex]::Matches($t, $rx)) { [void]$set.Add($m.Groups[1].Value) }
  return $set
}
$old = Get-Names (Join-Path $env:TEMP 'builtin_methods_0490_backup.mbt')
$new = Get-Names (Join-Path $repo 'src\core\builtin_methods.mbt')
$lost = @($old | Where-Object { -not $new.Contains($_) } | Sort-Object)
Write-Output ('names to test: ' + $lost.Count)

# --- one module per name, plus a CONTROL module ----------------------------
# The control module holds a name that cannot exist. It must be REJECTED. If it
# is not, the scaffold is broken and every verdict below is void.
$mods = @()
$i = 0
foreach ($n in $lost) {
  $i++
  $safe = 'r' + $i.ToString('000')
  $mods += [pscustomobject]@{ Dir = $safe; Name = $n; Body = "fn use_it() -> Unit {`n  let _ = " + $n + "`n}`n" }
}
$mods += [pscustomobject]@{ Dir = 'control'; Name = 'ZZMissing::nope'; Body = "fn use_it() -> Unit {`n  let _ = ZZMissing::nope`n}`n" }

foreach ($m in $mods) {
  $pkg = Join-Path $root $m.Dir
  $src = Join-Path $pkg ('src\' + $m.Dir)
  New-Item -ItemType Directory -Force -Path $src | Out-Null
  [System.IO.File]::WriteAllText((Join-Path $pkg 'moon.mod'), "name = `"$($m.Dir)`"`n`nversion = `"0.1.0`"`n", (New-Object System.Text.UTF8Encoding($false)))
  [System.IO.File]::WriteAllText((Join-Path $src 'moon.pkg'), "import {`n}`n", (New-Object System.Text.UTF8Encoding($false)))
  [System.IO.File]::WriteAllText((Join-Path $src ($m.Dir + '.mbt')), $m.Body, (New-Object System.Text.UTF8Encoding($false)))
}

# --- check them, SEQUENTIALLY ----------------------------------------------
# The parallel version took twenty-five minutes and produced nothing usable,
# because `Start-Process` with redirected output serializes the whole thing
# anyway. Sequential is slower per name but it is SIMPLE, and a measurement
# whose own instrument is in doubt is not a measurement.
$prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
$alive = @()
$dead = @()
$k = 0
foreach ($m in $mods) {
  $k++
  $pkg = Join-Path $root $m.Dir
  & $moon -C $pkg check 2>&1 | Out-Null
  $code = $LASTEXITCODE
  if ($m.Dir -eq 'control') {
    if ($code -eq 0) {
      Write-Output ''
      Write-Output '=> THE CONTROL WAS ACCEPTED. The scaffold cannot reject an impossible name,'
      Write-Output '   so every verdict below would be void. THIS RUN SAYS NOTHING.'
      exit 1
    }
    Write-Output ('control REJECTED as it must be (exit ' + $code + ') -- the scaffold is sound')
    continue
  }
  if ($code -eq 0) { $alive += $m.Name } else { $dead += $m.Name }
  if ($k % 20 -eq 0) { Write-Output ('  ... ' + $k + ' of ' + $mods.Count) }
}
$ErrorActionPreference = $prev

Write-Output ''
Write-Output ('checked: ' + ($alive.Count + $dead.Count) + ' of ' + $lost.Count)
Write-Output ('DEAD: ' + $dead.Count + '   ALIVE: ' + $alive.Count)
Write-Output ''
Write-Output '--- ALIVE (the toolchain still accepts the qualified name) ---'
foreach ($a in $alive) { Write-Output ('  ' + $a) }
Write-Output ''
Write-Output '--- DEAD (first 20) ---'
foreach ($d in ($dead | Select-Object -First 20)) { Write-Output ('  ' + $d) }
Write-Output ''
if ($alive.Count -gt 0) {
  Write-Output '=> THE REGENERATED TABLE IS A SUBSET OF WHAT IS CALLABLE. Regenerating it as-is'
  Write-Output '   would turn every ALIVE name into a false positive.'
  Write-Output '   THE REPAIR IS TO KEEP THE OLD NAMES AND ADD THE NEW ONES -- A SUPERSET.'
} else {
  Write-Output '=> All 102 are dead. The regenerated table is correct as it stands.'
}
