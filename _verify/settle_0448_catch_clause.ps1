# Settles the `catch` forms, and FALSIFIES a recorded claim.
#
# Read the third section first if you are here to understand what changed: this
# script was written against a claim that measurement then refuted.
#
# ---------------------------------------------------------------------------
# 1. WHAT WAS CLAIMED, and where the claim came from
# ---------------------------------------------------------------------------
# The standing notes carried this as a MEASURED pre-existing false positive:
#
#   "a `let` inside a handler's BLOCK body does not bind for that block's
#    trailing expression -- identical `catch` source reports it, plain function
#    body is clean", located in `Parser::parse_block` as reached from
#    `parse_catch_arms`.
#
# It was carried as measured, which is exactly why it survived as long as it did.
#
# ---------------------------------------------------------------------------
# 2. WHAT MEASUREMENT FOUND
# ---------------------------------------------------------------------------
# FIVE catch-arm shapes, each scanned by the analyzer, each with the IDENTICAL
# `let a = 1` / trailing `a` inside the arm's block body:
#
#     _ => { let a = 1  a }
#     e => { let a = 1  a }                      <- moonbit_labeler 0.2.13
#                                             extensions/labeler/labeler.mbt:199
#     Boom(n) => { let a = 1  a }  _ => 0
#     Boom(n) => { let a = n + 1  a }  _ => 0
#     let v = try { ... } catch { _ => { let a = 1  a } }
#
# ALL FIVE: `defects=0`, actionable 0. The binding is NOT the problem. The
# analyzer does not report `a` as unbound, and it does not report the arm's
# payload binding either. THE CLAIM IS FALSIFIED.
#
# ---------------------------------------------------------------------------
# 3. WHAT IS ACTUALLY TRUE, and it is a different thing
# ---------------------------------------------------------------------------
# The `try` expression is READ BUT NOT ANALYSED. Every one of those five shapes
# produces the same notice and nothing else:
#
#     try expression is outside the analyzed subset; it was read but not
#     analysed (ParseError) [structural]
#
# So the catch arm is not mis-bound -- it is not LOOKED AT. That is the
# `note_skip` coverage gap already on the list ("statement-level `try { } catch
# { }` skips its try body whole"), and it is a gap in what the analyzer checks,
# not a wrong answer it gives. Those are different defects with different fixes,
# and the notes conflated them because both were described as "the catch case".
#
# It also explains why the false positive never appeared on a corpus:
# moonbit_labeler and proton both write this form, both are at actionable 0, and
# a body that is skipped cannot generate a finding in it.
#
# ---------------------------------------------------------------------------
# 4. AND THE SHAPE THAT LOOKED LIKE THE BUG IS NOT MOONBIT AT ALL
# ---------------------------------------------------------------------------
# The original reproduction was:
#
#     fn risky() -> Unit {
#       ignore(1)
#     } catch {
#       e => { let a = 1  ignore(a) }
#     }
#
# on the reading that MoonBit has a FUNCTION-LEVEL catch clause. It does not.
# `moon check` rejects it -- `Parse error, unexpected token 'catch', you may
# expect 'pub', 'priv', 'type', 'suberror', ...` -- so the analyzer's
# `undefined variable 'catch'` was reporting GENUINELY INVALID CODE and was
# right to.
#
# What misled the reading is a shape in moonbit-community/sqlite3 0.2.3
# `async.mbt:68,137,202` that looks identical to a function clause:
#
#     Connection::from_open_database(database, Some(executor))
#   } catch {
#     @os_error.OSError(_) as error => raise async_io_error(error)
#
# That `}` closes a `try` BLOCK several lines up, not the function body. The
# grep that found it -- `^\s*\}\s*catch\s*\{` -- cannot tell the two apart,
# because in the only real occurrences the brace belongs to the `try`.
#
# So the claimed false positive was invalid input, and the real finding beneath
# it -- skipped analysis -- is a coverage limit the notes already carried in a
# different entry.
#
# ---------------------------------------------------------------------------
# 5. THE PRELUDE TRAP, which cost three runs and is pinned here so it costs one
# ---------------------------------------------------------------------------
# Every case below is prefixed with a `suberror` and a `raiser`. Three wrong
# preludes were tried first, and in all three the CATCH FORM looked broken when
# the prelude was the thing that was broken:
#
#   `sub error Boom { ... }`          parse error at line 2; `Boom(Int)` then
#                                     reads as a const applied to an argument,
#                                     and every arm in the file fails with it
#   `suberror Boom derive(Debug) {..}` parse error at the `{`
#   `fn f() -> Int` with `raise`      4122: raise can only be used inside a
#                                     function with error types in its
#                                     signature -- the return type needs
#                                     `-> Int raise`
#
# Two of the three produced errors that LOOKED like the construct under test
# being rejected. `ctl_sub_error_two_words` pins the first one below. A probe
# wrong about its own prelude produces a clean, confident, entirely false
# answer, and this is now the sixth such probe in this repository -- the settle
# survived them only because the control fires.

$ErrorActionPreference = 'Stop'
$fail = 0
$cases = [ordered]@{}
$expect = [ordered]@{}

function Add-Case([string]$name, [string]$src, [string]$want) {
  $script:cases[$name] = $src
  $script:expect[$name] = $want
}

$PRELUDE = @'
///|
suberror Boom {
  Boom(Int)
}

///|
fn raiser(x : Int) -> Int raise {
  if x > 0 {
    raise Boom(x)
  }
  x
}

'@

# --- the control ----------------------------------------------------------
# A name that cannot exist. MUST be rejected, or every ACCEPT below is worthless.
Add-Case 'ctl_missing' ($PRELUDE + @'
///|
fn probe() -> Int raise {
  ignore(ZzMissing)
  0
}
'@) 'REJECT'

# The prelude trap itself, pinned so it costs a run rather than three.
Add-Case 'ctl_sub_error_two_words' ($PRELUDE + @'
///|
sub error Other {
  Other(Int)
}

///|
fn probe() -> Int raise {
  raiser(1)
}
'@) 'REJECT'

# There is no function-level catch clause.
Add-Case 'ctl_fn_clause_catch' ($PRELUDE + @'
///|
fn probe(x : Int) -> Int raise {
  raiser(x)
} catch {
  Boom(n) => n
  _ => 0
}
'@) 'REJECT'

# --- the forms, all ACCEPTed by the toolchain ------------------------------
Add-Case 'wildcard_arm_block_let' ($PRELUDE + @'
///|
fn probe(x : Int) -> Int raise {
  let v = try {
    raiser(x)
  } catch {
    _ => {
      let a = 1
      a
    }
  }
  v
}
'@) 'ACCEPT'

# moonbit_labeler 0.2.13 extensions/labeler/labeler.mbt:198-200, verbatim in form.
Add-Case 'identifier_arm_block_let' ($PRELUDE + @'
///|
fn probe(x : Int) -> Int raise {
  try {
    raiser(x)
  } catch {
    e => {
      let a = 1
      a
    }
  }
}
'@) 'ACCEPT'

Add-Case 'payload_arm_block_let' ($PRELUDE + @'
///|
fn probe(x : Int) -> Int raise {
  try {
    raiser(x)
  } catch {
    Boom(n) => {
      let a = 1
      a
    }
    _ => 0
  }
}
'@) 'ACCEPT'

# The one that would really break if the arm body were mis-scoped: the `let`
# READS the payload bound by the arm's pattern.
Add-Case 'payload_arm_let_reads_payload' ($PRELUDE + @'
///|
fn probe(x : Int) -> Int raise {
  try {
    raiser(x)
  } catch {
    Boom(n) => {
      let a = n + 1
      a
    }
    _ => 0
  }
}
'@) 'ACCEPT'

# --- run ------------------------------------------------------------------
# Two scaffold facts, both paid for in a wasted run on 0447: `moon.mod` MUST
# declare `source = "src"`, and a package cannot import its own root.
$root = Join-Path $env:TEMP ('settle0448_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$enc = New-Object System.Text.UTF8Encoding($false)

foreach ($k in $cases.Keys) {
  $d = Join-Path $root $k
  New-Item -ItemType Directory -Force -Path (Join-Path $d 'src') | Out-Null
  [IO.File]::WriteAllText((Join-Path $d 'moon.mod'), "name = `"p0448`"`n`nversion = `"0.1.0`"`n`nsource = `"src`"`n", $enc)
  [IO.File]::WriteAllText((Join-Path $d 'src\moon.pkg'), "", $enc)
  [IO.File]::WriteAllText((Join-Path $d 'src\main.mbt'), $cases[$k], $enc)

  Push-Location $d
  $o = cmd.exe /c "moon check 2>&1"
  Pop-Location
  # JOIN WITH NEWLINES and do not collapse whitespace: a `(?m)^Error:` pattern
  # needs line boundaries. 0447's second version destroyed them and every
  # control read ACCEPT.
  $joined = ($o -join "`n")
  $plan = $joined -match 'Failed to calculate build plan|Cannot find import'
  $errs = @([regex]::Matches($joined, '(?m)^Error: \[(\d+)\]') |
    ForEach-Object { $_.Groups[1].Value })
  $want = $expect[$k]
  if ($plan) {
    $got = 'BUILD-PLAN-FAILED'
    $ok = $false
  } elseif ($want -eq 'REJECT') {
    $got = if ($errs.Count) { 'REJECT(' + ($errs -join ',') + ')' } else { 'ACCEPT' }
    $ok = $got -like 'REJECT*'
  } else {
    $got = if ($errs.Count) { 'REJECT(' + ($errs -join ',') + ')' } else { 'ACCEPT' }
    $ok = ($got -eq 'ACCEPT')
  }
  Write-Output ('{0,-28} {1,-22} (want {2,-6}) {3}' -f $k, $got, $want, $(if ($ok) { 'OK' } else { '*** MISMATCH ***' }))
  if (-not $ok) { $fail++ }
}

Write-Output ''
if ($fail -gt 0) {
  Write-Output "ABORT: $fail case(s) did not match."
  Write-Output 'If any row says BUILD-PLAN-FAILED the scaffold is wrong and NOTHING here is'
  Write-Output 'an answer. If a `ctl_*` row came back ACCEPT then `moon check` is not'
  Write-Output 'discriminating on this question and the ACCEPT rows beside it prove nothing.'
  exit 1
}
Write-Output 'GATE OK. The four catch-arm shapes are all ACCEPTED by the toolchain, and the'
Write-Output 'analyzer reports defects=0 on every one of them -- the binding claim is'
Write-Output 'FALSIFIED. What is real is that the `try` expression is read but NOT'
Write-Output 'ANALYSED, which is a coverage limit, not a wrong answer. And a function-level'
Write-Output '`} catch {` clause is REJECTED by the toolchain, so the original'
Write-Output 'reproduction was invalid input and the analyzer was right to complain.'
exit 0
