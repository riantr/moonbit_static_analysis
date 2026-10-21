# Settle 0496 -- `lexmatch`, the LEXICAL MATCH, and the LABELLED CAPTURE.
#
# WHY. `lexmatch <subject> [with longest] { arms }` is MoonBit's regex-lexer
# form of a match. Its arms are patterns whose first element is a REGEX LITERAL
# and whose second is the LABELLED `after=` binding that names the input AFTER
# the match:
#
#     lexmatch rest with longest {
#       (re"^//+" as t, after=next) => { ...; next }
#       (re"^[A-Za-z_][A-Za-z0-9_]*" as t, after=next) => { ...; next }
#       _ => abort("unreachable")
#     }
#
# The standing note in `src/parser/parser.mbt` said the construct was NOT DONE
# and gave the reason: it "is written in `moonbitlang/lexer 0.4.0` and
# `moonbitlang/json5 0.5.5` -- neither is a PINNED corpus". That reason was
# WRONG, and the note's own numbers were wrong too.
#
# THE SCOPE IS MEASURED, NOT INHERITED. A grep for `after=` over every `.mbt`
# under `.repos` gives 283 lines in 22 files -- but a grep counts LOCAL
# VARIABLES and COMMENTS too. Classified by hand:
#
#     moonbitlang/core   84 sites in  5 files   <- the construct
#     wzzc-dev/moui      13 "sites" in 11 files  <- `let after = ...`,
#                                                  `receipt.after`, `// after = ...`
#     riantr/moonbit_labeler 2 "sites" in  2 files  <- a `let after`, a doc comment
#     moonbit_image / async / proton / proton_contract   0
#
# So the construct IS in a PINNED corpus -- five files of `moonbitlang/core` --
# and the standing note's "18 sites in 3 PINNED core files" was wrong on both
# counts.
#
# THE GRAMMAR IS WHAT THIS SETTLES. Three forms, one probe each:
#
#     lexmatch s { .. }                the bare form
#     lexmatch s with longest { .. }   the corpus's form
#     lexmatch s with { .. }           `with` without its `longest`
#
# AND THE ARMS, because the labelled capture is the thing the construct EXISTS
# for: `(re"..." as t, after=next)` binds the matched text AND the input after
# the match.
#
# SCAFFOLD NOTES, CARRIED FROM 0480 AND 0488 BECAUSE ALL THREE BIT THE SAME
# WAY. Every row here is written to a project that HAS a `src/moon.pkg`,
# because a MoonBit project without a package inside its source directory is
# not a package: `moon check` prints "no work to do", exits 0, and every row
# reads ACCEPT. `ctl_must_reject` exists so a harness that cannot fail cannot
# look like a harness that found the corpus legal, and "no work to do" is
# matched by name so that specific no-op can never again pass silently.
$ErrorActionPreference = 'Stop'
$fail = 0
$cases = [ordered]@{}
$expect = [ordered]@{}

function Add-Case([string]$name, [string]$src, [string]$want) {
  $script:cases[$name] = $src
  $script:expect[$name] = $want
}

# --- CONTROLS. Gated. ---------------------------------------------------------
Add-Case 'ctl_no_escape' @'
///|
fn a(s : String) -> String {
  s
}
'@ 'ACCEPT'

# ctl_must_reject proves the INSTRUMENT can fail.
Add-Case 'ctl_must_reject' @'
///|
fn broken() -> Int {
  "not an int"
}
'@ 'REJECT'

# ctl_plain_match -- an ordinary `match` is accepted, so the rows below are
# about the `lexmatch` and not about matching in general.
Add-Case 'ctl_plain_match' @'
///|
fn a(s : String) -> String {
  match s {
    "x" => s
    _ => s
  }
}
'@ 'ACCEPT'

# ctl_regex_literal -- the regex literal itself is legal (0494), so a row that
# failed on the `re"..."` and not on the `lexmatch` would be about the wrong
# thing.
Add-Case 'ctl_regex_literal' @'
///|
fn a(s : String) -> Bool {
  s =~ re"^a"
}
'@ 'ACCEPT'

# --- THE GRAMMAR. ------------------------------------------------------------
Add-Case 'L1_lexmatch_bare' @'
///|
fn a(s : String) -> String {
  lexmatch s {
    (re"^a", after=_) => s
    _ => s
  }
}
'@ 'ACCEPT'

Add-Case 'L2_lexmatch_with_longest' @'
///|
fn a(s : String) -> String {
  lexmatch s with longest {
    (re"^a", after=_) => s
    _ => s
  }
}
'@ 'ACCEPT'

# L3 IS THE ROW THAT PINS `with`'s COMPANION: `with` on its own is not a
# clause, it is the first half of one.
Add-Case 'L3_lexmatch_bare_with' @'
///|
fn a(s : String) -> String {
  lexmatch s with {
    (re"^a", after=_) => s
    _ => s
  }
}
'@ 'REJECT'

# --- THE LABELLED CAPTURE. ---------------------------------------------------
# L4 BINDS THE MATCHED TEXT with `as` -- the capture 0494 settled.
Add-Case 'L4_capture_only' @'
///|
fn a(s : String) -> String {
  lexmatch s with longest {
    (re"^a" as t, after=_) => s
    _ => s
  }
}
'@ 'ACCEPT'

# L5 BINDS THE INPUT AFTER THE MATCH with `after=`. The binding's type is the
# subject's VIEW type -- a `StringView` subject yields a `StringView` rest --
# and the corpus writes exactly that:
#
#     fn SourceLocRepr::parse(repr : String) -> SourceLocRepr {
#       lexmatch repr[:] with longest { ... }
#     }
#
# `repr[:]` is a `StringView` VIEW of a `String`, which is why the corpus's own
# `after=` bindings type-check and why a bare `String` subject does not (L10).
Add-Case 'L5_after_label' @'
///|
fn a(s : String) -> String {
  lexmatch s with longest {
    (re"^a", after=rest) => s
    _ => s
  }
}
'@ 'ACCEPT'

# L6 IS THE `after=_` FORM -- the corpus's own spelling for "do not bind the
# rest", and the one that lets a `String` subject work at all.
Add-Case 'L6_after_underscore' @'
///|
fn a(s : String) -> String {
  lexmatch s with longest {
    (re"^a", after=_) => s
    _ => s
  }
}
'@ 'ACCEPT'

# L7 IS THE CORPUS'S OWN SHAPE: a CAPTURE and an `after=` together.
Add-Case 'L7_capture_and_after' @'
///|
fn a(s : String) -> String {
  lexmatch s with longest {
    (re"^a" as t, after=next) => s
    _ => s
  }
}
'@ 'ACCEPT'

# L8 IS THE ROW THAT CORRECTED AN EXPECTATION. `as _` -- a capture with no
# name -- is REJECTed by the toolchain:
#
#     Parse error, unexpected token `_`, you may expect id (lowercase start).
#
# So the capture's name must be an IDENTIFIER, and the only way to say "do not
# bind the matched text" is to bind it to a name and not read it. The first
# version of this row expected ACCEPT and was wrong; the toolchain was right.
Add-Case 'L8_underscore_capture_is_refused' @'
///|
fn a(s : String) -> String {
  lexmatch s with longest {
    (re"^a" as _, after=_) => s
    _ => s
  }
}
'@ 'REJECT'

# L10 IS THE TYPE RULE, and it is why the corpus writes `StringView` subjects.
# The `after=` binding carries the subject's VIEW type, so an arm that RETURNS
# it from a `String`-subjected `lexmatch` is a type mismatch:
#
#     4014 -- the arm returns a `StringView` where a `String` is wanted
#
# The corpus's own line is `lexmatch repr[:] with longest { ... }` -- a VIEW of
# a `String` -- and that is the spelling that type-checks.
Add-Case 'L10_after_binding_is_the_view_type' @'
///|
fn a(s : String) -> String {
  lexmatch s with longest {
    (re"^a", after=next) => next
    _ => s
  }
}
'@ 'REJECT'

# --- AND THE ARM IS NOT A MATCH ARM OUTSIDE A LEXMATCH. ---------------------
# L9 IS THE CONTROL FOR THE WHOLE THING: the labelled capture belongs to the
# `lexmatch` grammar, so the same pattern in a plain `match` is refused.
Add-Case 'L9_plain_match_rejects_the_arm' @'
///|
fn a(s : String) -> String {
  match s {
    (re"^a" as t, after=_) => s
    _ => s
  }
}
'@ 'REJECT'

# L11 IS THE SPACING OF THE ARROW, and it is ACCEPTed: `=>` written tight
# against its operands is the same construct. The LEXER has to recognise it
# either way -- the reader that looks for the arrow has to skip the whitespace
# before it, and the reader that finds the arrow with the name still pending is
# a DIFFERENT path from the one that finds it after a space.
Add-Case 'L11_no_space_arrow' @'
///|
fn a(s : String) -> String {
  lexmatch s with longest {
    (re"^a" as t, after=next)=>s
    _ => s
  }
}
'@ 'ACCEPT'

# --- run ----------------------------------------------------------------------
$root = Join-Path $env:TEMP ('settle0496lm_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$enc = New-Object System.Text.UTF8Encoding($false)

foreach ($k in $cases.Keys) {
  $d = Join-Path $root $k
  New-Item -ItemType Directory -Force -Path (Join-Path $d 'src') | Out-Null
  [IO.File]::WriteAllText((Join-Path $d 'moon.mod'), "name = `"s0496lm`"`n`nversion = `"0.1.0`"`n`nsource = `"src`"`n", $enc)
  # REQUIRED. See the scaffold notes above.
  [IO.File]::WriteAllText((Join-Path $d 'src\moon.pkg'), "", $enc)
  [IO.File]::WriteAllText((Join-Path $d 'src\main.mbt'), $cases[$k], $enc)

  Push-Location $d
  $o = cmd.exe /c "moon check 2>&1"
  Pop-Location
  $joined = ($o -join "`n")
  $noop = $joined -match 'no work to do'
  $plan = $joined -match 'Failed to calculate build plan|Cannot find import'
  $errs = @([regex]::Matches($joined, '(?m)^Error: \[(\d+)\]') | ForEach-Object { $_.Groups[1].Value })
  $want = $expect[$k]
  if ($noop) {
    $got = 'MOON-DID-NOT-RUN'; $ok = $false
  } elseif ($plan) {
    $got = 'BUILD-PLAN-FAILED'; $ok = $false
  } elseif ($errs.Count) {
    $got = 'REJECT(' + ($errs -join ',') + ')'
    if ($want -eq 'RECORD') { $ok = $true }
    elseif ($want -eq 'ACCEPT') { $ok = $false }
    else { $ok = $got -like 'REJECT*' }
  } else {
    $got = 'ACCEPT'
    if ($want -eq 'RECORD') { $ok = $true } else { $ok = ($want -eq 'ACCEPT') }
  }
  Write-Output ('{0,-42} {1,-22} (want {2,-8}) {3}' -f $k, $got, $want, $(if ($ok) { 'OK' } else { '*** MISMATCH ***' }))
  if (-not $ok) {
    $fail++
    $lines = $joined -split "`n"
    for ($j = 0; $j -lt $lines.Count; $j++) {
      if ($lines[$j] -match 'Error: \[') {
        ($lines[$j..([Math]::Min($j + 12, $lines.Count - 1))] |
          Where-Object { $_ -match 'main\.mbt:|expected|wanted|has type|undefined|declared|unknown|Unknown|unexpected' }) |
          ForEach-Object { Write-Output ('      ' + $_.Trim()) }
        break
      }
    }
  }
}

Write-Output ''
if ($fail -gt 0) {
  Write-Output 'ABORT. Fix the SCAFFOLD, not the expectation. All four controls must behave.'
  exit 1
}
Write-Output 'GATE OK.'
Write-Output 'Read the ACCEPT/REJECT column above -- it is the answer, not this line.'
exit 0
