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
# THE MAINTENANCE PATH WAS UNSAFE, and the fix is measured. 0490's release gate
# ran while the toolchain was upgraded 0.1.20261012 -> 0.1.20261016, and the
# new core's interfaces declare 102 FEWER type-qualified names. The 102 SPLIT
# cleanly once it was measured, and the two halves are different upgrades:
#
#   84  the SPELLING CHANGE of 0.1.20261012. `Int::abs` is now `Int32::abs` and
#       `UInt::to_json` is now `UInt32::to_json` -- the same declarations, under
#       the explicit-width names, moved from the (now deprecated) `int` and
#       `uint` packages into `builtin`. The TYPE did not change: `Int` remains
#       accepted as an alias, which is what MoonBit's own documentation says.
#   18  0.1.20261016's own changes. The `Buffer::write` family was renamed
#       (`Buffer::write` is `Buffer::write_bytes` and friends), the deprecated
#       `Bool::to_int16` was removed (`#4409`), and a few more.
#
# Running this script on the new toolchain produced 1163 names against the
# committed 1265 -- 102 LOST, 0 gained -- and the header's own warning does not
# cover that direction.
#
# The table only ever SUPPRESSES, so its two failure directions are not
# symmetric, and the repo already settled which one it accepts:
#
#   keeping a name the toolchain has DROPPED  -> a MISSED report
#   dropping a name the toolchain still HAS    -> a FALSE POSITIVE
#
# And the 102 are NOT all dropped names. Measured one module per name against
# the new toolchain (`_verify/_settle_0490_builtins_alive.ps1`, with a control
# module that must be rejected): 33 are DEAD -- the call is rejected, so
# reporting it would be CORRECT -- and 69 are ALIVE, the call is accepted, and
# dropping them turns valid code into `undefined function`. Measured on the
# analyzer itself: `Int::popcnt`, `Int::next_power_of_two`,
# `UInt::trunc_double`, `Int::reinterpret_as_uint`, `Int::to_char`,
# `Int::to_byte` and `UInt::add` all became REPORTS on code `moon check`
# accepts, and the last two are CALLED by moui 0.1.12.
#
# So the extraction reads a WEAKER source than the compiler's own resolution:
# the .mbti interfaces do not declare every name the compiler accepts. The
# repair is the SAME one this script already applies to the intrinsic list --
# keep the names that were in the table, and only ever ADD:
#
#     THE TABLE IS A SUPERSET. It is the union of what the current interfaces
#     declare and what the previous table held, so running this on a newer
#     toolchain cannot turn a valid call into a report.
#
# THE REPAIR IS IMPLEMENTED -- section 4 reads the previous table back and
# unions it in. Measured on 0.1.20261016 with the committed 1265-name table in
# place: the extraction alone reaches 1163, the union reaches 1265, and not
# one name is lost. The 102 the new interfaces no longer declare come back
# through the union, 33 of them dead and 69 still callable, and the live ones
# keep the analyzer quiet on code `moon check` accepts.
#
# A SECOND COUNT WAS ALSO WRONG, and the union is not what fixed it. The
# header said `$declared + $intrinsic.Count` names, which double-counts the
# intrinsics that an interface ALSO declares -- twelve of the thirty-two, so
# every version of this file was 12 too high (1277 against 1265). The overlap
# is now computed, and the header counts the set.
#
# The consequence is that the table only ever GROWS, and the dead names
# accumulate. That is the direction the table already accepts -- a missed
# report is a smaller cost than a false positive, and the header says so.
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
  'Array::sort', 'Float::NaN', 'Int::unsafe_to_char', 'Int32::unsafe_to_char',
  'Map::each',
  'Map::from_array', 'Map::new', 'Option::None', 'Ref::new',
  'String::starts_with', 'StringBuilder::new',
  # T::to_json -- declared by no interface, present on the builtin types.
  #
  # BOTH SPELLINGS ARE KEPT, for the reason the whole table keeps both: a
  # name the toolchain has RENAMED is a MISSED report, and a name the toolchain
  # still has is a FALSE POSITIVE. Only the second is acceptable.
  #
  # THE SPELLING CHANGE, AND THE THREE NAMES IT ADDS. The toolchain changed
  # the CANONICAL SPELLING of the two unsuffixed integer types on 0.1.20261012
  # -- `Int` is now `Int32`, `UInt` is now `UInt32` -- and this list is
  # HAND-WRITTEN, so it is the one part of the table that no extraction can
  # repair and no carrying-forward can reach: the old table never had
  # `Int32::to_json`, because `Int32` did not exist.
  #
  # THE TYPE DID NOT CHANGE, and the official wording is the authority -- from
  # MoonBit's own Language Fundamentals page:
  #
  #     Int and UInt remain accepted as aliases of Int32 and UInt32.
  #     The formatter uses the explicit-width names Int32 and UInt32.
  #
  # (https://docs.moonbitlang.com/en/latest/language/fundamentals.html) The
  # core library says the same in its commit subject, on every package at once:
  # "Update for moon 0.1.20261012 (Int32/UInt32, new deprecations)", Oct 13 2026.
  #
  # The three names below are therefore SETTLED, not composed. A probe per
  # name, one package each, with a control module that must be rejected
  # (`_verify/settle_0490_intrinsic.ps1`):
  #
  #   ACCEPT   Int32::to_json        ACCEPT   UInt32::to_json
  #   ACCEPT   Int32::unsafe_to_char
  #   REJECT 4015  UInt32::unsafe_to_char   <- the intrinsic is signed-only
  #   REJECT 4015  Int32::to_jsonnope      <- the CONTROL
  #
  # `UInt32::to_json` is worth a note. An earlier version of this list GUESSED
  # it into existence and the superset check caught it and removed it, because
  # the old table did not hold it and a guessed name is a guess. On this
  # toolchain it is a real, settled name -- the guess was right for the wrong
  # reason, and it is back because it was MEASURED.
  #
  # `Int32::to_json` returns `Json`, not `String`. A probe that declares the
  # return type as `String` gets 4014 "Expr Type Mismatch" and reads as a
  # missing method, which is a probe bug that looks exactly like a toolchain
  # fact.
  'ArgsLoc::to_json', 'Bool::to_json', 'Byte::to_json', 'Bytes::to_json',
  'BytesView::to_json', 'Char::to_json', 'Double::to_json', 'Error::to_json',
  'Failure::to_json', 'Float::to_json', 'Int::to_json', 'Int32::to_json',
  'Int64::to_json',
  'String::to_json', 'StringView::to_json', 'UInt::to_json', 'UInt32::to_json',
  'UInt16::to_json',
  'UInt64::to_json', 'Unit::to_json'
)
#
# TWELVE OF THESE ARE ALSO DECLARED IN AN INTERFACE, and that is the whole
# explanation for a count that was 12 too high in every version of this file:
# the header said `$declared + $intrinsic.Count`, which counts a name twice
# when the interface already declared it. The overlap is COMPUTED here rather
# than transcribed, so it cannot go stale the way a hand-written list of the
# twelve would.
$intrinsicOverlap = @()
foreach ($n in $intrinsic) {
  if ($set.ContainsKey($n)) { $intrinsicOverlap += $n }
  $set[$n] = 1
}
$intrinsicDeclared = $intrinsicOverlap.Count

# --- 4. carry the PREVIOUS table forward --------------------------------
# THE TABLE IS A SUPERSET, and this step is what makes it one.
#
# The extraction above reads a WEAKER source than the compiler's own
# resolution: the .mbti interfaces do not declare every name the compiler
# accepts. So a toolchain upgrade can REMOVE names from the extraction while
# the calls stay valid. Measured on the 0.1.20261012 -> 0.1.20261016 upgrade:
# the new interfaces declare 102 fewer names, and a probe per name (one module
# each, with a control module that must be rejected) settled 33 of them DEAD
# and 69 still ALIVE. Dropping those 69 turned valid calls -- two of them
# called by moui 0.1.12 -- into `undefined function`.
#
# The two failure directions are not symmetric, and this repo settled which one
# it accepts:
#
#     keeping a name the toolchain has DROPPED  -> a MISSED report   (accepted)
#     dropping a name the toolchain still HAS    -> a FALSE POSITIVE (not accepted)
#
# So the previous table is read back and UNIONED IN. The table then only ever
# grows and dead names accumulate -- the same trade the intrinsic list already
# makes, and the direction the header has always accepted.
#
# The previous table is read from the file this script is about to overwrite.
# That is deliberate: the file IS the accumulated state, and it is the only
# copy of the carried names that exists anywhere. If it is absent the union
# has nothing to read, and the report below says so out loud rather than
# letting a reader assume a superset it did not get.
$prevPath = "$repo\src\core\builtin_methods.mbt"
$carried = 0
$hadPrev = $false
$prevNames = @{}
if (Test-Path $prevPath) {
  $hadPrev = $true
  foreach ($line in [IO.File]::ReadAllLines($prevPath, $enc)) {
    $s = $line.Trim()
    # Comment lines carry prose, and prose carries backticked names. Only the
    # array body is data.
    if ($s.StartsWith('//')) { continue }
    foreach ($m in [regex]::Matches($s, '"([A-Za-z_][A-Za-z0-9_]*::[A-Za-z_][A-Za-z0-9_]*)"')) {
      $prevNames[$m.Groups[1].Value] = 1
    }
  }
  foreach ($n in $prevNames.Keys) {
    if (-not $set.ContainsKey($n)) { $carried += 1 }
    $set[$n] = 1
  }
}

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
[void]$sb.AppendLine("// last run against, PLUS the previous table for the names that")
[void]$sb.AppendLine("// toolchain no longer declares -- see the SUPERSET note below. The")
[void]$sb.AppendLine("// version below is WRITTEN BY THE GENERATOR and was typed in by hand")
[void]$sb.AppendLine("// until 0.4.35, which is how a stale table could not be told apart from")
[void]$sb.AppendLine("// a current one.                    toolchain: $verdict")
[void]$sb.AppendLine("//")
[void]$sb.AppendLine("// Of the $($set.Count) names below, $aliasesKept come from an")
[void]$sb.AppendLine("// #alias DIRECTIVE rather than from a declaration: #alias(from_array)")
[void]$sb.AppendLine("// above [type Set[K]] is what makes Set::from_array a real callable")
[void]$sb.AppendLine("// name. The rest are plain declarations, of which every GENERIC one")
[void]$sb.AppendLine("// ([pub fn[K : Eq] Set::add]) was invisible to this generator until")
[void]$sb.AppendLine("// 0.4.35, because its pattern demanded the name come straight after")
[void]$sb.AppendLine("// fn.")
[void]$sb.AppendLine("//")
[void]$sb.AppendLine("// THE LIST IS A SUPERSET, and it is BUILT as one: the union of what the")
[void]$sb.AppendLine("// current interfaces declare, what the compiler intrinsics add, and")
[void]$sb.AppendLine("// what the PREVIOUS table held. $carried names are carried forward from")
[void]$sb.AppendLine("// the table this run replaces. The two failure directions are not")
[void]$sb.AppendLine("// symmetric -- keeping a name the toolchain has DROPPED is a MISSED")
[void]$sb.AppendLine("// report, dropping a name the toolchain still HAS is a FALSE POSITIVE")
[void]$sb.AppendLine("// -- and only the second is unacceptable. Measured on the")
[void]$sb.AppendLine("// 0.1.20261012 -> 0.1.20261016 upgrade: the new interfaces declare 102")
[void]$sb.AppendLine("// fewer names, 69 of them still callable, and dropping those 69 turned")
[void]$sb.AppendLine("// valid calls into `undefined function`. The cost of the union is that")
[void]$sb.AppendLine("// the list only grows and dead names accumulate -- the direction this")
[void]$sb.AppendLine("// table already accepts.")
[void]$sb.AppendLine("//")
[void]$sb.AppendLine("// Of the $($intrinsic.Count) compiler intrinsics settled with")
[void]$sb.AppendLine("// [moon check], $intrinsicDeclared are ALSO declared in an interface, so")
[void]$sb.AppendLine("// they are counted once and not twice.")
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
Write-Host "  intrinsics        : $($intrinsic.Count)  ($intrinsicDeclared of them are ALSO declared in an interface)"
Write-Host "  carried forward   : $carried  (from the previous table)"
Write-Host "  total             : $($set.Count)"
Write-Host "  heads             : $($groups.Count)"
Write-Host "  toolchain         : $verdict"
if ($intrinsicDeclared -gt 0) {
  Write-Host "  intrinsic overlap :"
  foreach ($n in ($intrinsicOverlap | Sort-Object)) { Write-Host "                      $n" }
}
if (-not $hadPrev) {
  Write-Host "  WARNING: no previous table at $prevPath -- the output is the"
  Write-Host "           extraction alone, NOT a superset of anything."
}