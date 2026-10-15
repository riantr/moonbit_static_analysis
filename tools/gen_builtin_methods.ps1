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
# TWO HEAD SHAPES, and the second is why this file was stale for so long:
#
#     pub fn Set::x(..)          non-generic
#     pub fn[K : Eq] Set::x(..)  GENERIC -- type parameters sit between `fn`
#                                 and the name
#
# The old pattern demanded that `fn` be followed by the name, so every generic
# method of every builtin type was invisible. Measured against the toolchain in
# hand it produced ZERO hits on `<core>/set/pkg.generated.mbti`, which alone
# declares 32 of them, and it missed 445 names in total -- `Array::add`,
# `Set::add`, `Map::insert` among them. `Array::add` had never been reported on
# the corpora only because real code writes the METHOD form `a.add(x)`; the
# qualified form is mostly used for constructors, which is exactly the shape the
# one remaining async finding had (`Set::from_array`).
#
# ALIASES ARE NOT DECLARATIONS. `#alias(from_array)` above `type Set[K]` makes
# `Set::from_array` a real, callable name, and the directive -- not a `fn` line --
# is where it is written. So the scan is line-based and carries pending aliases
# to whatever declaration comes next. Two filters, both measured:
#
#   - Only IDENTIFIER-shaped alias names are kept. `#alias("_[_:_]")` is a
#     quoted operator and is not a qualified name this table can hold.
#   - Any declaration clears the pending list, because an alias binds to the
#     NEXT declaration, not to the next one of a kind.
$set = @{}
$aliasesKept = 0
$declRx = '^(?:pub\s+|priv\s+|extern\s+|unsafe\s+)*(?:fn|type|let|const|struct|enum|class|effect|exception)\b'
foreach ($f in Get-ChildItem $core -Recurse -Include *.mbti -File) {
  $pending = @()
  foreach ($line in [IO.File]::ReadAllLines($f.FullName, $enc)) {
    $s = $line.Trim()
    if ($s.StartsWith('#alias(')) {
      $a = [regex]::Match($s, '^#alias\(\s*([A-Za-z_][A-Za-z0-9_]*)')
      if ($a.Success) { $pending += $a.Groups[1].Value }
      continue
    }
    if ($s -notmatch $declRx) { continue }
    $t = ''; $m = ''
    $x = [regex]::Match($s, '^(?:pub\s+)?fn\s*(?:\[[^\]]*\])?\s*([A-Za-z_][A-Za-z0-9_]*)::([A-Za-z_][A-Za-z0-9_]*)')
    if ($x.Success) {
      $t = $x.Groups[1].Value; $m = $x.Groups[2].Value
    } else {
      $y = [regex]::Match($s, '^(?:pub\s+)?type\s+([A-Za-z_][A-Za-z0-9_]*)')
      if ($y.Success) { $t = $y.Groups[1].Value; $m = $t }
    }
    if ($t -ne '' -and $bare.ContainsKey($t)) {
      $set[$t + '::' + $m] = 1
      foreach ($a in $pending) {
        $set[$t + '::' + $a] = 1
        $aliasesKept += 1
      }
    }
    $pending = @()
  }
}
$declared = $set.Count

# --- 3. compiler intrinsics, settled with `moon check` ------------------
# `to_json` IS one of these, and getting that wrong is the whole reason this
# section is commented at length. `Bool::to_json` appears in NO `pkg.generated.mbti`
# in the tree, so a generator that reads only the interfaces concludes it does not
# exist and drops it -- and the corpus call sites of `T::to_json` turn straight back
# into `undefined function` false positives on code `moon check` accepts.
#
# It was assumed the 17 such names were STALE, left over from when the table was
# generated at 0.1.20260920 against a toolchain that is no longer installed. That
# was wrong, and `_verify/settle_0445_alias.ps1` is what proved it: `Bool::to_json(true)`
# compiles today. They are intrinsic members that no interface declares -- the same
# category as `Array::make` below, which is why this list exists at all.
#
# NOTE FOR THE NEXT PERSON TO WRITE A PROBE HERE. The obvious sweep is to call
# `T::to_json(1)` for every type. That reports 35 of 45 as "does not exist" and is
# entirely an artefact of passing an Int to Bool::to_json. The error is a TYPE
# mismatch. A probe that is wrong about its own prelude produces a clean, confident,
# completely false answer, and the settle caught this one only because it had a
# type-correct case next to it.
$intrinsic = @(
  'Array::copy', 'Array::from_iter', 'Array::make', 'Array::makei',
  'Array::sort', 'Float::NaN', 'Int::unsafe_to_char', 'Map::each',
  'Map::from_array', 'Map::new', 'Option::None', 'Ref::new',
  'String::starts_with', 'StringBuilder::new',
  # T::to_json -- declared by no interface, present on the builtin types.
  # Preserved from the pre-0.4.35 table rather than re-derived, because the
  # failure direction of keeping a name the toolchain has since dropped is a
  # MISSED report, which this table already accepts, while the direction of
  # dropping one it still has is a FALSE POSITIVE, which it does not.
  # The list is transcribed, not composed: the first version of it guessed
  # `UInt32::to_json` into existence and dropped `Unit::to_json`, which the
  # superset check caught immediately. Read it out of the old table instead.
  'ArgsLoc::to_json', 'Bool::to_json', 'Byte::to_json', 'Bytes::to_json',
  'BytesView::to_json', 'Char::to_json', 'Double::to_json', 'Error::to_json',
  'Failure::to_json', 'Float::to_json', 'Int::to_json', 'Int64::to_json',
  'String::to_json', 'StringView::to_json', 'UInt::to_json', 'UInt16::to_json',
  'UInt64::to_json', 'Unit::to_json'
)
foreach ($n in $intrinsic) { $set[$n] = 1 }

# DERIVED, not copied. The provenance line written into the generated file used to
# carry a version typed in by hand, so it went stale the moment the toolchain moved
# and nobody could tell a stale table from a current one. The whole point of
# recording provenance is that it is checkable.
$verdict = (& $moon version 2>&1 | Select-Object -First 1) -replace '\s+', ' '

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
[void]$sb.AppendLine("// <toolchain>/lib/core/**/pkg.generated.mbti, at the toolchain this was")
[void]$sb.AppendLine("// last run against -- the version below is WRITTEN BY THE GENERATOR and")
[void]$sb.AppendLine("// was typed in by hand until 0.4.35, which is how a stale table could")
[void]$sb.AppendLine("// not be told apart from a current one.        toolchain: $verdict")
[void]$sb.AppendLine("//")
[void]$sb.AppendLine("// Of the $(($declared + $intrinsic.Count)) names below, $aliasesKept come from an")
[void]$sb.AppendLine("// #alias DIRECTIVE rather than from a declaration: #alias(from_array)")
[void]$sb.AppendLine("// above [type Set[K]] is what makes Set::from_array a real callable")
[void]$sb.AppendLine("// name. The rest are plain declarations, of which every GENERIC one")
[void]$sb.AppendLine("// ([pub fn[K : Eq] Set::add]) was invisible to this generator until")
[void]$sb.AppendLine("// 0.4.35, because its pattern demanded the name come straight after")
[void]$sb.AppendLine("// fn. The last $($intrinsic.Count) are compiler builtins that no")
[void]$sb.AppendLine("// interface declares, settled with [moon check].")
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
& $moon fmt | Out-Null
Pop-Location

# --- report -------------------------------------------------------------
Write-Host "wrote src/core/builtin_methods.mbt"
Write-Host "  declared in .mbti : $declared"
Write-Host "  via #alias        : $aliasesKept"
Write-Host "  intrinsics        : $($intrinsic.Count)"
Write-Host "  total             : $($set.Count)"
Write-Host "  heads             : $($groups.Count)"
Write-Host "  toolchain         : $verdict"