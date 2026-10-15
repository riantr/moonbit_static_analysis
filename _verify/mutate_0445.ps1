# Mutation gate 0445 -- the builtin-method TABLE could not see generic methods.
#
# On the harness: no runner of its own, all six rules from `_verify/mutate_lib.ps1`
# apply.
#
# THE DEFECT IS IN THE GENERATOR, and that shapes this gate. `tools/gen_builtin_methods.ps1`
# extracted methods with a pattern demanding the name come STRAIGHT AFTER `fn`:
#
#     (?m)^\s*(?:pub\s+)?fn\s+([A-Za-z_][A-Za-z0-9_]*)::([A-Za-z_][A-Za-z0-9_]*)
#
# MoonBit's generated interfaces put type parameters there -- `pub fn[K : Eq] Set::add(..)` --
# so every generic method of every builtin type was invisible: ZERO hits on
# `<core>/set/pkg.generated.mbti`, 445 names missed across the tree. And the one
# corpus finding it produced, `Set::from_array`, is not a declared `fn` at all --
# `#alias(from_array)` sits above `type Set[K]` and the DIRECTIVE is the name.
#
# So every mutation here removes a name that ONE of the two new mechanisms is the
# only source of. A mutation that removed a name present before 0.4.35 would
# measure nothing this change is responsible for.
#
#   M1  `Array::add` -- reachable ONLY through a generic head.
#   M2  `Set::from_array` -- reachable ONLY through a `#alias` on a type constructor.
#   M3  `Bool::to_json` -- declared by NO interface at all; carried by hand.
#   M4  `Array::clone` -- reachable ONLY through a `#alias` on a METHOD.
#
# M3 is the one that nearly went the other way. Those 18 names were assumed stale,
# left over from when the table was generated at moon 0.1.20260920 against a
# toolchain no longer installed. `_verify/settle_0445_alias.ps1` proved it wrong:
# `Bool::to_json(true)` compiles today. They are intrinsic members, the same
# category as `Array::make`, and M3 exists so that dropping them again is a red
# suite rather than a quiet regression.
#
# NOT THIS GATE: the generator's own patterns. `tools/gen_builtin_methods.ps1` is
# PowerShell and no `moon test` reads it, so a mutation there would have to be
# proved by re-running the generator and diffing -- a different instrument, and the
# settle plus this gate cover the artifact that actually ships.
#
# 1 actionable across the six corpora went to 0 (async `src/http/send.mbt:37`,
# `undefined function 'Set::from_array'`), `parsed=` unchanged on all six, and the
# table is verified a STRICT SUPERSET of the old one: 656 names -> 1265, none lost.

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'mutate_lib.ps1')

Invoke-MutationGate -Name 'M1..M4' -Target 'js' -Mutations @(

  @{
    Name = 'M1 a generic-head method is dropped (Array::add)'
    File = 'src\core\builtin_methods.mbt'
    Find = @'
     "Array::add", "Array::all", "Array::any", "Array::append", "Array::Array", "Array::at",
'@.Replace("`r`n", "`n")
    Repl = @'
     "Array::all", "Array::any", "Array::append", "Array::Array", "Array::at",
'@.Replace("`r`n", "`n")
    MustRed = '0445: a generic builtin method is not an undefined function'
  },

  @{
    Name = 'M2 a #alias on a type constructor is dropped (Set::from_array)'
    File = 'src\core\builtin_methods.mbt'
    Find = @'
    "Set::filter", "Set::from_array", "Set::from_iter", "Set::from_iterator", "Set::insert",
'@.Replace("`r`n", "`n")
    Repl = @'
    "Set::filter", "Set::from_iter", "Set::from_iterator", "Set::insert",
'@.Replace("`r`n", "`n")
    MustRed = '0445: a builtin method behind a #alias directive is not an undefined function'
  },

  @{
    Name = 'M3 a name no interface declares is dropped (Bool::to_json)'
    File = 'src\core\builtin_methods.mbt'
    Find = @'
    "Bool::to_int16", "Bool::to_int64", "Bool::to_json", "Bool::to_string", "Bool::to_uint",
'@.Replace("`r`n", "`n")
    Repl = @'
    "Bool::to_int16", "Bool::to_int64", "Bool::to_string", "Bool::to_uint",
'@.Replace("`r`n", "`n")
    MustRed = '0445: T::to_json resolves even though no interface declares it'
  },

  @{
    Name = 'M4 a #alias on a METHOD is dropped (Array::clone)'
    File = 'src\core\builtin_methods.mbt'
    Find = @'
    "Array::chunk_by", "Array::chunks", "Array::clamped_view", "Array::clear", "Array::clone",
'@.Replace("`r`n", "`n")
    Repl = @'
    "Array::chunk_by", "Array::chunks", "Array::clamped_view", "Array::clear",
'@.Replace("`r`n", "`n")
    MustRed = '0445: the builtin method table carries the generic and aliased names'
    Prove = @'
Pinned on the TABLE MEMBERSHIP test rather than on a behavioural one, and the reason
is worth recording: no behavioural test in the suite calls `Array::clone`.

`Array::clone` is `#alias(clone, deprecated)` sitting above
`pub fn[T] Array::copy(Self[T]) -> Self[T]` -- a deprecated alias of a deprecated
spelling, which is exactly the shape nobody writes in new code and exactly why it
had no corpus site to become a behavioural test from. The settle DOES call it
(`c_alias_method.mbt`, ACCEPTED), so the name is verified against `moon check`;
what it is not is exercised by the analyzer's own suite.

So this mutation is pinning table MEMBERSHIP for the second alias shape -- alias of a
method rather than alias of a type constructor -- and M2 pins the first. Writing a
behavioural test to match it would have meant inventing a call site no corpus
produced, which is the thing the M3 survivor in gate 0436 says not to do.
'@.Replace("`r`n", "`n")
  }
)

Write-MutationGateVerdict -Name '0445'
if ($script:MutationGateFailures.Count -gt 0) { exit 1 }
exit 0
