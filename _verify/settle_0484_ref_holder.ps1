# Settle 0484 -- a TRAIT METHOD WHOSE RECEIVER IS A REFERENCE, `fn &Trait::method`.
#
# WHY. After 0483 async stands at 406/419. The ranking by what is actually ON each boundary line
# (not by the scanner's grouped message tally -- the 0472 lesson) puts this next: two files stop on
#
#     pub fn &Data::binary(self : &Data) -> Bytes          io/data.mbt:77
#     pub fn &ProcessInput::close(self : &ProcessInput) -> Unit   process/redirect.mbt:229
#
# and redirect.mbt ARRIVED here during 0483 -- it stopped on `@fs.CreateMode::to_int` at line 156,
# was fixed, read 73 more lines, and stopped again on the `&` holder 73 lines later. That is the
# second time a boundary line named more than one construct and only one of them was broken, so the
# measurement below is not a formality.
#
# *** THE FIRST FRAMING OF THIS CONSTRUCT WAS WRONG, AND `moon check` SAID SO. *** The obvious
# reading of `fn &Type::method` is "a method on Type, declared through a reference". It is not.
# Both fixture drafts declared `Data` as a STRUCT and every row came back
#
#     4100  The type Data is not a trait
#
# at the holder AND at the `self : &Data` annotation. A struct cannot carry this declaration
# because the `&`-holder is not a reference marker at all -- it says the method belongs to a
# TRAIT, and the trait's methods may take `&Self`. The corpus agrees, and it was in the corpus all
# along:
#
#     io/data.mbt:23        trait Data {
#                              fn to_bytesview(Self) -> BytesView = _
#                              fn to_bytes(Self) -> Bytes
#                            }
#     io/data.mbt:77        pub fn &Data::binary(self : &Data) -> Bytes
#     process/redirect.mbt:212   trait ProcessInput {
#     process/redirect.mbt:229   pub fn &ProcessInput::close(self : &ProcessInput) -> Unit
#
# So the construct is a TRAIT DEFAULT METHOD whose receiver is a reference, declared OUTSIDE the
# trait body. Reading the boundary line and calling it a "reference-type holder" would have built
# a parse production for the right tokens and an AST name with the wrong meaning in it, and the
# corpus scan would have called that a success. Two of the three drafts for this settle were
# fixture faults wearing the costume of a grammar refusal.
#
# MEASURED against this analyzer's own parser first, with a ten-case probe. The probe bodies are
# `( )` and the return type is `Bytes`, which does NOT typecheck -- these fixtures were parsed by
# this analyzer only, never by `moon check`, so a type error in them is invisible here and says
# nothing about the grammar:
#
#     fn Data::binary(self : Data)            -> Bytes { }        first_error = 0  <- already works
#     impl Data with fn binary(_)             { }                  first_error = 0  <- already works
#     type Ref = &Data                                             first_error = 0  <- `&` is fine
#     fn @other.Buf::repr(b : @other.Buf)     -> Int = "%identity" first_error = 0  <- 0483 control
#     fn &Data::binary(self : &Data)          -> Bytes { }        first_error = 2  <- HERE
#     pub fn &Data::binary(self : &Data)      -> Bytes { }        first_error = 2
#     pub fn &Data::text(self : &Data)        -> String raise { } first_error = 2
#     fn &Data::binary(self : &Data)          -> Bytes = "%id"     first_error = 2
#     extern "C" fn &Data::binary(...)        = "x"                first_error = 2
#     fn &&Data::binary(self : &&Data)        -> Bytes { }        first_error = 2
#
# The body is IRRELEVANT and the `&` IN FRONT OF THE HOLDER is decisive. Same shape as 0483:
# reading the boundary line would have built an extern-body production for a body this parser
# already reads in every other spelling.
#
# THE TOKEN SHAPE, and it is NOT the 0483 shape. `Lexer::run` starts a name at
# `is_letter(c) || c == '@'`, so `@` glues INTO the name -- which is why 0483's fix was a DOT and
# not a prefix token, and why there is no `TAt`. `&` is NOT a name-start character: it falls
# through to `lex_op`, which maps `'&' => TAmp`. So here the `&` is a STANDALONE `TAmp` in front of
# an ordinary `TName`, not a glued prefix. Assuming the 0483 shape would have produced a copy of
# 0483 that silently does nothing.
#
# THE SCAFFOLD IS TWO PACKAGES, per the 0483 header: `src/other` needs its OWN `moon.pkg`, the
# import goes in `moon.pkg` and not in the source file, and the path is `<module>/<dir>` --
# `s0484/other`, NOT `s0484/src/other`. Both packages are written for every row so the scaffold is
# constant across rows; a fixture that changes shape between rows cannot be compared to itself.
$ErrorActionPreference = 'Stop'
$fail = 0
$cases = [ordered]@{}
$expect = [ordered]@{}

function Add-Case([string]$name, [string]$src, [string]$want) {
  $script:cases[$name] = $src
  $script:expect[$name] = $want
}

# THE SECOND PACKAGE. A TRAIT this time, not a struct -- the other two drafts got 4100 "The type
# Buf is not a trait" for exactly the reason the first draft got it for `Data`.
$OTHER = @'
trait Buf {
  fn peek(Self) -> Int
}
'@

# THE LOCAL TRAIT. `fn peek(Self) -> Int` with NO `= _`, and that is measured rather than
# preferred: adding `= _` to give the method a default turns EVERY row red with 4158 on the trait
# declaration itself, while leaving it off accepts C1-C4 outright. A trait method with no default
# is the shape used where no default exists, which is all the `&`-holder rows need.
$LOCAL = @'
///|
trait Data {
  fn to_bytes(Self) -> Int
}
'@

# --- CONTROLS. Gated. ---------------------------------------------------------

# THE CONTROL that discriminates. The SAME `&Data::binary` declaration against a STRUCT instead of
# a trait is refused 4100 "The type Data is not a trait". This is the row that makes the trait
# framing a measured fact rather than an interpretation: it shows the toolchain really is reading
# the holder as a TRAIT reference, and it is the exact failure the first two fixture drafts
# produced by accident.
Add-Case 'ctl_struct_holder_must_reject' @'
///|
struct Data {
  x : Int
}

fn &Data::binary(self : &Data) -> Int {
  1
}
'@ 'REJECT'

# An ordinary function body. The argument under test is that a foreign-function BODY is not what
# is unread.
Add-Case 'ctl_plain_body' @'
///|
fn f(x : Int) -> Int {
  x + 1
}
'@ 'ACCEPT'

# ctl_must_reject proves the INSTRUMENT can fail. Every other gated row here wants ACCEPT, so a
# compiler that is not running looks exactly like a compiler that approves the corpus.
Add-Case 'ctl_must_reject' @'
///|
fn broken() -> Int {
  "not an int"
}
'@ 'REJECT'

# --- probe_unqualified_*  WHICH SPELLING IS THE CONTROL ------------------------
# Recorded, not gated: the point of these rows is to find out, and the answer becomes the gate.
Add-Case 'probe_unqualified_self_type' ($LOCAL + @'

fn Data::binary(self : Data) -> Int {
  1
}
'@) 'RECORD'

Add-Case 'probe_unqualified_ref_self' ($LOCAL + @'

fn Data::binary(self : &Data) -> Int {
  1
}
'@) 'RECORD'

Add-Case 'probe_unqualified_self_kw' ($LOCAL + @'

fn Data::binary(self : Self) -> Int {
  1
}
'@) 'RECORD'

Add-Case 'probe_unqualified_plain_param' ($LOCAL + @'

fn Data::binary(x : Int) -> Int {
  1
}
'@) 'RECORD'

# --- C1  THE CORPUS SHAPE ------------------------------------------------------
# io/data.mbt:77 and process/redirect.mbt:229, both `pub`, both a LABELLED `self`.
Add-Case 'C1_ref_trait_holder_pub' ($LOCAL + @'

pub fn &Data::binary(self : &Data) -> Int {
  1
}

fn call_it(d : &Data) -> Int {
  d.binary()
}
'@) 'ACCEPT'

# --- C2  `pub` IS NOT THE DECIDING TOKEN HERE -----------------------------------
# 0483 measured `pub fn @other.Buf::m` REJECTing 4059 on a FOREIGN type, and concluded `pub` is
# not part of that grammar. This row asks whether the same refusal follows the `&` onto a LOCAL
# trait -- the corpus writes `pub` on both its `&` sites, so if `pub` were fatal here the corpus
# shape itself would be illegal and the ranking above would be wrong.
Add-Case 'C2_ref_trait_holder_nopub' ($LOCAL + @'

fn &Data::binary(self : &Data) -> Int {
  1
}
'@) 'ACCEPT'

# --- C3  THE `raise` EFFECT TAIL -----------------------------------------------
# io/data.mbt:86 is `pub fn &Data::text(self : &Data) -> String raise`. The effect clause is read
# AFTER the return annotation, so a reader that consumed the `&` holder with the wrong number of
# tokens would land on it rather than on the parameter list.
Add-Case 'C3_ref_trait_holder_raise' ($LOCAL + @'

pub fn &Data::text(self : &Data) -> String raise {
  "x"
}
'@) 'ACCEPT'

# --- C4  THE CALL SITE, THROUGH A REFERENCE ------------------------------------
# `d.binary()` where `d : &Data`. If the toolchain accepts this then the `&` describes the
# RECEIVER and not the type's identity -- which is what decides whether the AST name keeps it.
Add-Case 'C4_call_through_ref' ($LOCAL + @'

pub fn &Data::binary(self : &Data) -> Int {
  1
}

fn call_it(d : &Data) -> Int {
  d.binary()
}
'@) 'ACCEPT'

# --- C5  THE CALL SITE, BY PATH ------------------------------------------------
# Recorded, NOT gated, and the reason is the toolchain's rather than the fixture's: a trait is
# not a value type, so `fn call_it(d : Data)` is refused 4099 "`Data` is a trait, not a type" and
# the path-call row cannot be written at all against a trait holder. That is worth knowing --
# it means `&Trait::m` has exactly ONE call spelling, `m()` through a value satisfying the trait,
# and there is no `Trait::m(x)` form to resolve names against. The name question is therefore
# settled by C4 plus `record_both_qualifiers`, not by this row.
Add-Case 'record_call_by_path' ($LOCAL + @'

pub fn &Data::binary(self : &Data) -> Int {
  1
}

fn call_it(d : Data) -> Int {
  Data::binary(d)
}
'@) 'RECORD'

# --- RECORDED. Read the column, do not gate on it. ----------------------------

# A REFERENCE TO A REFERENCE as the receiver. Nothing in the corpus writes one.
Add-Case 'record_double_ref_holder' ($LOCAL + @'

fn &&Data::deep(self : &&Data) -> Int {
  1
}
'@) 'RECORD'

# The foreign-function BODY on an `&` holder WITHOUT `extern` -- a shape that reads on neither of
# the two corpus sites, both of which have brace bodies. If this ACCEPTs, a fix aimed at the body
# would be aimed at nothing.
Add-Case 'record_ref_holder_foreign_body' ($LOCAL + @'

fn &Data::repr(self : &Data) -> Int = "%identity"
'@) 'RECORD'

# Whether `extern "C"` composes with the `&` holder. The analyzer reads the extern form and does
# not read the `&` holder, so until something says they are one they are two gaps.
Add-Case 'record_extern_and_ref_holder' ($LOCAL + @'

extern "C" fn &Data::binary(self : &Data) -> Int = "binary"
'@) 'RECORD'

# BOTH qualifiers at once: `&@other.Trait::m`. 0483 fixed the `@other.` fold and this settle
# fixes the `&` fold; nothing has ever asked the toolchain what happens when both appear on one
# holder, and there is no corpus instance either way. Whichever way it lands, the analyzer has to
# answer the same way as the compiler.
Add-Case 'record_ref_and_pkg_holder' @'
///|
fn &@other.Buf::repr(b : &@other.Buf) -> Int = "%identity"
'@ 'RECORD'

# THE COLLISION THAT MATTERS FOR THE HARVEST. There is no `fn Data::binary` to collide with --
# all four `probe_unqualified_*` rows REJECT 4032, so for a TRAIT the `&`-holder is the ONLY
# spelling and dropping the `&` from the recorded name cannot collide with a declaration. What can
# collide is an `impl ... with fn` default, which is the other way a method named `binary` reaches
# trait `Data`. If this ACCEPTs then two spellings of one method exist, and a harvest that folds
# both onto `Data::binary` holds a name twice -- harmless unless something counts, which is worth
# knowing before it is discovered by a corpus number.
Add-Case 'record_impl_default_collision' ($LOCAL + @'

pub fn &Data::binary(self : &Data) -> Int {
  1
}

impl Data with fn binary(_) {
  2
}
'@) 'RECORD'

# Two `&`-holder methods of the same name on one trait -- the duplicate check inside the construct.
Add-Case 'record_duplicate_ref_holder' ($LOCAL + @'

fn &Data::binary(self : &Data) -> Int {
  1
}

fn &Data::binary(self : &Data) -> Int {
  2
}
'@) 'RECORD'

# Whether an `async` `&` holder is legal -- nothing in the corpus writes one, and an increment
# that fixed only the synchronous spelling would leave this open with no row at all.
Add-Case 'record_async_ref_holder' ($LOCAL + @'

async fn &Data::fetch(self : &Data) -> Int {
  1
}
'@) 'RECORD'

# --- run ----------------------------------------------------------------------
$root = Join-Path $env:TEMP ('settle0484_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$enc = New-Object System.Text.UTF8Encoding($false)

foreach ($k in $cases.Keys) {
  $d = Join-Path $root $k
  New-Item -ItemType Directory -Force -Path (Join-Path $d 'src\other') | Out-Null
  [IO.File]::WriteAllText((Join-Path $d 'moon.mod'), "name = `"s0484`"`n`nversion = `"0.1.0`"`n`nsource = `"src`"`n", $enc)
  # REQUIRED, BOTH OF THEM. The package under test needs one or `moon check` prints "no work to
  # do" and exits 0 -- which every ACCEPT row would read as a pass. And `src/other` needs its
  # OWN marker or the directory is not a package at all and the qualified rows fail with
  # "Package 'other' not found in the loaded packages".
  [IO.File]::WriteAllText((Join-Path $d 'src\moon.pkg'), 'import { "s0484/other" }', $enc)
  [IO.File]::WriteAllText((Join-Path $d 'src\other\moon.pkg'), '', $enc)
  [IO.File]::WriteAllText((Join-Path $d 'src\other\buf.mbt'), $OTHER, $enc)
  [IO.File]::WriteAllText((Join-Path $d 'src\main.mbt'), $cases[$k], $enc)

  Push-Location $d
  $o = cmd.exe /c "moon check 2>&1"
  Pop-Location
  $joined = ($o -join "`n")
  $noop = $joined -match 'no work to do'
  $plan = $joined -match 'Failed to calculate build plan|Cannot find import|not found in the loaded packages'
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
  Write-Output ('{0,-38} {1,-22} (want {2,-8}) {3}' -f $k, $got, $want, $(if ($ok) { 'OK' } else { '*** MISMATCH ***' }))
  # VERBOSE dumps the compiler's own WORDS for every row, gated or not. The error CODE alone is
  # not the answer: 4100 meant "type mismatch" in one draft and "The type Data is not a trait" in
  # the next, and reading which is which off the code is how a settle ends up explaining a scaffold
  # fault as a grammar refusal. The code is printed for the gate's benefit; the text is read.
  if ($env:SETTLE_VERBOSE -eq '1' -and $errs.Count) {
    $lines = $joined -split "`n"
    for ($j = 0; $j -lt $lines.Count; $j++) {
      if ($lines[$j] -match 'Error: \[') {
        $slice = $lines[$j..([Math]::Min($j + 9, $lines.Count - 1))]
        $slice | ForEach-Object { Write-Output ('      | ' + $_.Trim()) }
        break
      }
    }
  }
  if (-not $ok) {
    $fail++
    $lines = $joined -split "`n"
    for ($j = 0; $j -lt $lines.Count; $j++) {
      if ($lines[$j] -match 'Error: \[') {
        $slice = $lines[$j..([Math]::Min($j + 12, $lines.Count - 1))]
        $slice |
          Where-Object { $_ -match 'main\.mbt:|other\\|expected|wanted|has type|undefined|declared|unknown|Unexpected|unexpected|method|trait' } |
          ForEach-Object { Write-Output ('      ' + $_.Trim()) }
        break
      }
    }
  }
}

Write-Output ''
if ($fail -gt 0) {
  Write-Output 'ABORT. Fix the SCAFFOLD, not the expectation. All four controls must behave.'
  Write-Output 'A flipped CLAIM means the analyzer change is aimed at something the toolchain refuses.'
  Write-Output 'A red CONTROL means the fixture does not compile -- that is a scaffold fault, and every'
  Write-Output 'row is then agreeing for the wrong reason. See the header: two of those drafts are listed.'
  exit 1
}
Write-Output 'GATE OK.'
Write-Output 'Read the ACCEPT/REJECT column above -- it is the answer, not this line.'
exit 0
