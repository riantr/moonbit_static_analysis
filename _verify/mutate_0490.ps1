# Mutation gate 0490 -- SIX defects: five the PER-FUNCTION view made visible,
# and one the TOOLCHAIN UPGRADE exposed.
#
# WHAT THIS INCREMENT IS. 0489 gave the behavioral lens a per-function entry, and
# the per-function view reported 265 actionable findings on moui 0.1.12 where
# the module view reports 0. Those 265 were not 265 defects in the analysed
# code: they were an INVENTORY of what was still wrong with the LENS, and
# this gate pins the five classes that were fixed.
#
#   M1  A LIST VALUE against a LIST PARAMETER was a type error. The type lens
#       writes a list type as `[int]` (`ty_name`); the behavioral lens writes a
#       list VALUE as `List` (`abs_of`); `vmatches` compares a value name
#       against a type name, so "List" was never equal to "[int]".
#   M2  THE ARITY FLOOR. The check compared the argument count against the
#       DECLARED count, so a call that omitted an omittable parameter was
#       reported. `control_state` declares SEVEN and is called with THREE.
#   M3  THE ARITY CEILING. The other half of the same rule: too MANY
#       arguments is still an error.
#   M4  A FUNCTION WHOSE BODY IS AN `if` returned "None", because the
#       branch's value was evaluated and discarded -- so `ret_vals` stayed
#       empty and `join_vals([])` answered "None", and every operator applied
#       to that result was reported.
#   M5  A STRING CONCATENATION was the type "int": `bin_widen` had arms for
#       `float`, for `Any` and the `int` fallback, and none for two strings.
#   M6  A STRING COMPARISON was a method error: the comparison operators
#       accepted only `numeric(l) && numeric(r)`, and `<=` on two Strings is
#       legal MoonBit.
#   M7  THE PARSER DID NOT RECORD `omittable`, so the `?` spelling of an
#       omittable parameter was invisible to the arity rule.
#
# M8 AND M9 COME FROM A DIFFERENT SOURCE, and the difference is worth stating.
# The toolchain was upgraded 0.1.20261012 -> 0.1.20261016 in the middle of this
# release, by another process on the same machine, and the new toolchain RENAMED
# the two unsuffixed integer types: `Int` is now `Int32`, `UInt` is now
# `UInt32`. `Int16` and `UInt16` were not renamed -- the change is of the
# UNSUFFIXED names only.
#
#   M8  THE AMBIENT TYPE LIST did not learn the new names, so every
#       interface the new toolchain generates reported `unknown type 'Int32'
#       in interface signature` -- 37 findings on the analyzer's OWN
#       regenerated `src/*/pkg.generated.mbti` files.
#   M9  THE METHOD TABLE did not learn them either, and it has a second face:
#       the toolchain declares all 44 of the integer type's methods under
#       `Int32::` and NONE under `Int::`, so `Int32::popcnt(x)` -- legal
#       MoonBit, and what `moon fmt` rewrites `Int::popcnt` into -- was
#       reported `undefined function 'Int32::popcnt'`.
#
# Both spellings are kept, and the reason is that they are the SAME type:
# `moon check` accepts `let x : Int32 = 1` and `let x : Int = 1` and accepts
# either in either position. Settled with the toolchain --
# `_verify/settle_0490_int32.ps1` and `_verify/settle_0490_intrinsic.ps1`, one
# package per row, with a control module that must be rejected.
#
# THE `?` AND THE DEFAULT VALUE are the TWO OMITTABLE SPELLINGS, and both are
# settled against the toolchain (`moon check` 0.1.20261012):
#
#   ACCEPT  `fn opt(x : Int, y? : Int)` called as `opt(1)`
#   ACCEPT  `fn labelled_default(x : Int, y~ : Int = 0)` called as
#           `labelled_default(1)`
#   REJECT 4080  `required()` against `fn required(x : Int)` -- omitting a
#           REQUIRED parameter is an error, and that is what M2's control
#           pins.
#   REJECT 3010  `fn f(y : Int = 0)` -- "Only labelled arguments can have
#           default value", so the default spelling is only legal on a `~`.
#
# ANCHORS ARE WRITTEN AGAINST THE POST-`moon fmt` SOURCE. fmt both rewraps one
# line into several and collapses several into one, and either way a stale
# anchor is a PREFLIGHT MISS that runs no suite at all.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'mutate_lib.ps1')

$INTERP = 'src\interp\interp.mbt'
$PIPE   = 'src\pipeline\pipeline.mbt'
$PARSER = 'src\parser\parser.mbt'
$BUILT  = 'src\core\builtins.mbt'
$METHOD = 'src\core\builtin_methods.mbt'

Invoke-MutationGate -Name '0490' -Target 'wasm' -Mutations @(

  # M1 THE LIST SPELLING. The two lenses spell a list differently and never
  # met, so every call passing a list was reported `no method matching
  # take(List)` -- on code `moon check` accepts.
  @{
    Name = 'M1 a list value is a type error against a list parameter again'
    File = $INTERP
    Find = @'
    AType(t) => t == ty || ty == "Any" || (is_list_name(t) && is_list_name(ty))
'@.Replace("`r`n", "`n")
    Repl = @'
    AType(t) => t == ty || ty == "Any"
'@.Replace("`r`n", "`n")
    MustRed = 'a list value is not a type error against a list parameter'
  }

  # M2 THE ARITY FLOOR. A call may OMIT the parameters the function declares
  # omittable, so the floor is the REQUIRED count and not the declared one.
  #
  # THE CONTROL IS THE POINT: removing the floor entirely would silence
  # "a call that omits a required parameter is still an error", which the
  # toolchain agrees with (4080). So this mutation is killed by a CONTROL
  # row, and that is what makes it a KILL rather than a quieter report.
  @{
    Name = 'M2 the arity rule has no floor'
    File = $INTERP
    Find = @'
      let declared = def.ptypes.length()
      if vals.length() > declared || vals.length() < declared - def.nopt {
        ok = false
      }
'@.Replace("`r`n", "`n")
    Repl = @'
      let declared = def.ptypes.length()
      if vals.length() > declared {
        ok = false
      }
'@.Replace("`r`n", "`n")
    MustRed = 'a call that omits a required parameter is still an error'
  }

  # M3 THE ARITY CEILING. The other half: too MANY arguments is still an
  # error, so the rule is a RANGE and not a blanket.
  @{
    Name = 'M3 the arity rule has no ceiling'
    File = $INTERP
    Find = @'
      if vals.length() > declared || vals.length() < declared - def.nopt {
        ok = false
      }
      if !ok {
'@.Replace("`r`n", "`n")
    Repl = @'
      if vals.length() < declared - def.nopt {
        ok = false
      }
      if !ok {
'@.Replace("`r`n", "`n")
    MustRed = 'a call that passes too many arguments is still an error'
  }

  # M4 THE `if` VALUE. The branch's value was evaluated and DISCARDED, so a
  # function whose body's last statement is an `if` returned "None" and every
  # operator applied to the result was reported.
  @{
    Name = 'M4 a function whose body is an if returns None again'
    File = $INTERP
    Find = @'
    SExpr(e) => self.last_value = self.eval(e, env)
'@.Replace("`r`n", "`n")
    Repl = @'
    SExpr(e) => {
      let _ = self.eval(e, env)
    }
'@.Replace("`r`n", "`n")
    MustRed = 'a function whose body is an if returns the branch value'
  }

  # M5 THE STRING CONCATENATION. `bin_widen` had no arm for two strings, so
  # `"a" + "b"` evaluated to the type "int" and the OUTER `+` of a
  # concatenation was reported `no method matching +(int, str)`.
  @{
    Name = 'M5 a string concatenation is an int again'
    File = $INTERP
    Find = @'
  if lname == "str" && rname == "str" {
    return "str"
  }
'@.Replace("`r`n", "`n")
    Repl = @'
  if lname == "str" && rname == "NEVER" {
    return "str"
  }
'@.Replace("`r`n", "`n")
    MustRed = 'a string concatenation is a string'
  }

  # M6 THE STRING COMPARISON. `<=` on two Strings is legal MoonBit, and the
  # corpus paid for the missing case: proton reported `<=(str, str)` and
  # `>=(str, str)`.
  @{
    Name = 'M6 two strings do not compare again'
    File = $INTERP
    Find = @'
          if (numeric(l) && numeric(r)) || (strv(l) && strv(r)) {
            AType("bool")
'@.Replace("`r`n", "`n")
    Repl = @'
          if numeric(l) && numeric(r) {
            AType("bool")
'@.Replace("`r`n", "`n")
    MustRed = 'two strings compare'
  }

  # M7 THE PARSER FORGOT TO RECORD IT. The `?` spelling of an omittable
  # parameter was consumed and discarded, so the arity rule never saw it.
  #
  # This mutation is in the PARSER, and it is the one that makes the arity
  # rule's floor wrong rather than the rule itself: the rule was right about
  # what it was told and the AST never told it.
  @{
    Name = 'M7 the parser does not record an optional parameter'
    File = $PARSER
    Find = @'
      if self.at(TQuestion) {
        let _ = self.bump()
        more_mods = true
        omittable = true
      } else if self.at(TTilde) {
'@.Replace("`r`n", "`n")
    Repl = @'
      if self.at(TQuestion) {
        let _ = self.bump()
        more_mods = true
        omittable = false
      } else if self.at(TTilde) {
'@.Replace("`r`n", "`n")
    MustRed = 'a call that omits an optional parameter is not a method error'
  }

  # M8 THE AMBIENT TYPE LIST. The `.mbti` frontend resolves a signature's type
  # names against this list, and the list carried `Int` and not `Int32`. So
  # every interface the new toolchain generates -- which says `Int32` -- was
  # reported `unknown type 'Int32' in interface signature`.
  #
  # 37 findings on the analyzer's OWN regenerated `src/*/pkg.generated.mbti`
  # files, and it is the SELF-SCAN that caught them: the release gate's
  # self-scan stage requires `actionable` to be 0, so this mutation is what
  # keeps the gate's own green light honest.
  @{
    Name = 'M8 the ambient type list does not know the renamed integer types'
    File = $BUILT
    Find = @'
    "Double", "Failure", "FixedArray", "Hasher", "Int", "Int32", "Int64", "Iter",
    "Iter2", "Json", "Map", "MutArrayView", "Option", "ReadOnlyArray", "Result",
    "SourceLoc", "String", "StringBuilder", "StringView", "UInt", "UInt16", "UInt32",
'@.Replace("`r`n", "`n")
    Repl = @'
    "Double", "Failure", "FixedArray", "Hasher", "Int", "Int64", "Iter",
    "Iter2", "Json", "Map", "MutArrayView", "Option", "ReadOnlyArray", "Result",
    "SourceLoc", "String", "StringBuilder", "StringView", "UInt", "UInt16",
'@.Replace("`r`n", "`n")
    MustRed = 'a .mbti that names the renamed integer types has no findings'
  }

  # M9 THE METHOD TABLE. The other face of the same rename: the toolchain
  # declares all 44 of the integer type's methods under `Int32::` and NONE
  # under `Int::`, so `Int32::popcnt(x)` -- legal MoonBit, and what `moon fmt`
  # rewrites `Int::popcnt` into -- was reported `undefined function
  # 'Int32::popcnt'`.
  #
  # The OLD spelling stays in the table on purpose, so the control for this
  # row still passes while this one fails: keeping a name the toolchain has
  # renamed is a MISSED report, and dropping one it still has is a FALSE
  # POSITIVE, and only the second is acceptable.
  @{
    Name = 'M9 the method table does not know the renamed type''s methods'
    File = $METHOD
    Find = @'
    "Int32::neg", "Int32::next_power_of_two", "Int32::popcnt", "Int32::reinterpret_as_uint",
'@.Replace("`r`n", "`n")
    Repl = @'
    "Int32::neg", "Int32::next_power_of_two", "Int32::reinterpret_as_uint",
'@.Replace("`r`n", "`n")
    MustRed = 'a builtin method under the renamed type spelling is not undefined'
  }
)

Write-MutationGateVerdict -Name '0490'
if ($script:MutationGateFailures.Count -gt 0) { exit 1 }
exit 0
