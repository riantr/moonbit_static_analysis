# Regenerates src/core/builtin_methods.mbt from the local toolchain.
#
#   pwsh -File tools/gen_builtin_methods.ps1
#
# It lives in the repository rather than in a scratch directory because
# builtin_methods.mbt is a GENERATED file whose header says not to edit it by
# hand. A generated table whose generator is not committed rots silently: the
# next MoonBit adds methods, nobody regenerates, and the analyzer goes back to
# reporting real builtin calls as undefined.
#
# Every name it writes is measured, never guessed:
#
#   1. BARE NAMES. The type names come from the literal already in
#      src/core/builtins.mbt (comment lines stripped first, so a quoted word
#      in prose cannot become a type). The slice is deliberately
#      self-consistent: the methods of a type the table already names bare.
#      Adding a type to that list without re-running this is the drift the
#      slice is designed to expose, and it fails toward a visible report.
#   2. METHODS. Every `fn T::m` declared at the start of a line in any
#      <toolchain>/lib/core/**/pkg.generated.mbti, with T in that slice.
#      Indented lines are members inside `impl` blocks and are skipped, for
#      the reason the builtins.mbt header gives.
#   3. INTRINSICS. The compiler builtins that no .mbti declares — `Array::make`
#      among them. There is no interface to read for these, so the list is
#      fixed here and each entry was settled with `moon check`, not with
#      inference: a probe file calling all of them bare, with no imports,
#      alongside one impossible control name, and the toolchain flagged only
#      the control.
#
# Running this on a NEWER toolchain may legitimately produce a different list.
# That is the intended maintenance path, and it is also the failure mode: a
# stale list omits new names, which puts the analyzer back to reporting them.
# It can never invent a false alarm, because the table only ever suppresses.
#
# The script runs `moon fmt` over the tree at the end. moonfmt reflows the
# array literal and this script does not try to imitate that — its line filling
# differs, and a generator that guessed at it would emit a file `moon fmt
# --check` rejects.
$ErrorActionPreference = 'Stop'

# Both roots are derived, not hardcoded: this file is committed, so a path
# that only exists on the machine that wrote it would be a bug waiting.
$repo = Split-Path -Parent $PSScriptRoot
$moonHome = if ($env:MOON_HOME) { $env:MOON_HOME } else { Join-Path $env:USERPROFILE '.moon' }
$core = Join-Path $moonHome 'lib\core'
$moon = Join-Path $moonHome 'bin\moon.exe'
$enc = [Text.UTF8Encoding]::new($false)

if (-not (Test-Path $core)) {
  throw "toolchain core not found at $core - is MOON_HOME set, or has moon been installed?"
}
# --- 1. bare names -------------------------------------------------------
$bt = [IO.File]::ReadAllText("$repo\src\core\builtins.mbt", $enc)
$bare = @{}
foreach ($line in ($bt -split "`n")) {
  if ($line -match '^\s*//') { continue }
  foreach ($m in [regex]::Matches($line, '"(?:[^"\\]|\\.)*"')) {
    $v = $m.Value.Trim('"')
    if ($v -cmatch '^[A-Z]' -and -not $v.Contains('::')) { $bare[$v] = 1 }
  }
}

# --- 2. methods declared in the ambient packages ------------------------
$set = @{}
foreach ($f in Get-ChildItem $core -Recurse -Include *.mbti -File) {
  $t = [IO.File]::ReadAllText($f.FullName, $enc)
  foreach ($x in [regex]::Matches(
      $t, '(?m)^\s*(?:pub\s+)?fn\s+([A-Za-z_][A-Za-z0-9_]*)::([A-Za-z_][A-Za-z0-9_]*)')) {
    if ($bare.ContainsKey($x.Groups[1].Value)) {
      $set[$x.Groups[1].Value + '::' + $x.Groups[2].Value] = 1
    }
  }
}
$declared = $set.Count

# --- 3. compiler intrinsics, settled with `moon check` ------------------
$intrinsic = @(
  'Array::copy', 'Array::from_iter', 'Array::make', 'Array::makei',
  'Array::sort', 'Float::NaN', 'Int::unsafe_to_char', 'Map::each',
  'Map::from_array', 'Map::new', 'Option::None', 'Ref::new',
  'String::starts_with', 'StringBuilder::new'
)
foreach ($n in $intrinsic) { $set[$n] = 1 }

# --- emit ---------------------------------------------------------------
$groups = @{}
foreach ($k in $set.Keys) {
  $h = ($k -split '::')[0]
  if (!$groups.ContainsKey($h)) { $groups[$h] = @() }
  $groups[$h] += $k
}
$sb = [Text.StringBuilder]::new()
[void]$sb.AppendLine('// GENERATED FILE — do not edit by hand. See tools/gen_builtin_methods.ps1.')
[void]$sb.AppendLine('//')
[void]$sb.AppendLine('// The METHODS of the builtin types, as bare qualified names.')
[void]$sb.AppendLine('//')
[void]$sb.AppendLine('// What this fixes, measured. riantr/moonbit_labeler 0.2.13,')
[void]$sb.AppendLine('// `app_moui/rasterizer.mbt:74`:')
[void]$sb.AppendLine('//')
[void]$sb.AppendLine('//     let pixels : Array[Byte] = Array::make(total, Byte::default())')
[void]$sb.AppendLine('//                                                    ^^^^^^^^^^')
[void]$sb.AppendLine('//')
[void]$sb.AppendLine('// was reported as `undefined function ''Array::make''` by the behavioral')
[void]$sb.AppendLine('// lens, on a line `moon check` accepts. Across the four sibling corpora')
[void]$sb.AppendLine('// (933 files) this family is 42 distinct names over 4450 call sites; the')
[void]$sb.AppendLine('// other 41 are latent, masked rather than absent — see the note at the')
[void]$sb.AppendLine('// bottom of this file.')
[void]$sb.AppendLine('//')
[void]$sb.AppendLine('// Why a TABLE and not a rule. The obvious one-line fix is "a call')
[void]$sb.AppendLine('// qualified on an ambient type is a builtin method, stay quiet." It was')
[void]$sb.AppendLine('// written for 0.4.16 and reverted, because two of its mutations survived.')
[void]$sb.AppendLine('// With this table in place the negative control settles it:')
[void]$sb.AppendLine('//')
[void]$sb.AppendLine('//     Array::mkae(4, 0)   <- reported, because `mkae` is not in the table')
[void]$sb.AppendLine('//     Array::make(4, 0)   <- silent, because `make` is')
[void]$sb.AppendLine('//')
[void]$sb.AppendLine('// The rule version silences both. This is not a style preference: the')
[void]$sb.AppendLine('// whole cost of an ambient name is a MISSED report, which the builtins')
[void]$sb.AppendLine('// header already accepts, and the cheapest way to keep that cost bounded')
[void]$sb.AppendLine('// is to name the methods rather than to forgive every spelling.')
[void]$sb.AppendLine('//')
[void]$sb.AppendLine('// Provenance. Read out of the toolchain''s own generated interfaces,')
[void]$sb.AppendLine('// <toolchain>/lib/core/**/pkg.generated.mbti, at moon 0.1.20260920')
[void]$sb.AppendLine('// (914d7da 2026-09-20). $declared of the $(( $declared + $intrinsic.Count )) names')
[void]$sb.AppendLine('// below are declared in one of those files; the last $intrinsic.Count are')
[void]$sb.AppendLine('// compiler builtins that no interface declares, settled with `moon check`.')
[void]$sb.AppendLine('//')
[void]$sb.AppendLine('// The bare TYPE names themselves live in builtins.mbt. This file is sliced to')
[void]$sb.AppendLine('// those heads, so the two cannot drift: adding a type to the bare list without')
[void]$sb.AppendLine('// regenerating this one leaves its methods unresolved, which is the failure')
[void]$sb.AppendLine('// direction — a report the user can see — not a silent hole.')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('///|')
[void]$sb.AppendLine('/// Every builtin type method a `.mbt` file may call bare, qualified.')
[void]$sb.AppendLine('///')
[void]$sb.AppendLine('/// Merged into `@core.ambient_names()` by `builtins.mbt`, which is where the')
[void]$sb.AppendLine('/// three lenses look. Kept in its own file so the data stays separate from the')
[void]$sb.AppendLine('/// reasoning about why the table is allowed to suppress.')
[void]$sb.AppendLine('pub fn builtin_method_names() -> Array[String] {')
[void]$sb.AppendLine('  [')
foreach ($h in ($groups.Keys | Sort-Object)) {
  [void]$sb.AppendLine("    // $h")
  $names = $groups[$h] | Sort-Object
  $line = '     '
  foreach ($n in $names) {
    $piece = '"' + $n + '",'
    if (($line + $piece).Length -gt 76) {
      [void]$sb.AppendLine($line.TrimEnd())
      $line = '     '
    }
    $line += $piece + ' '
  }
  if ($line.Trim().Length -gt 0) { [void]$sb.AppendLine($line.TrimEnd()) }
}
[void]$sb.AppendLine('  ]')
[void]$sb.AppendLine('}')
[IO.File]::WriteAllText("$repo\src\core\builtin_methods.mbt", $sb.ToString(), $enc)

# moonfmt reflows the array literal and this script does not try to imitate it —
# its line-filling differs, and a generator that guessed at it would produce a
# file `moon fmt --check` rejects. Formatting the tree is therefore part of the
# recipe rather than a follow-up somebody has to remember.
Push-Location $repo
& 'C:\Users\31379\.moon\bin\moon.exe' fmt | Out-Null
Pop-Location

# --- report -------------------------------------------------------------
$verdict = & 'C:\Users\31379\.moon\bin\moon.exe' version --all 2>&1 | Select-Object -First 1
Write-Host "wrote src/core/builtin_methods.mbt"
Write-Host "  declared in .mbti : $declared"
Write-Host "  intrinsics        : $($intrinsic.Count)"
Write-Host "  total             : $($set.Count)"
Write-Host "  heads             : $($groups.Count)"
Write-Host "  toolchain         : $verdict"