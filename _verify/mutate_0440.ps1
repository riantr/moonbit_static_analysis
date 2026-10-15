# Mutation gate 0440 -- a `.mbti` `suberror` body declares VALUE CONSTRUCTORS.
#
# On the harness: no runner of its own, all six rules from
# `_verify/mutate_lib.ps1` apply.
#
# THE CHANGE. One predicate, in `parse_iface`:
#
#     in_ctor_body = matched == "enum " && d > 0
#
# became
#
#     in_ctor_body = (matched == "enum " || matched == "suberror ") && d > 0
#
# A braced `suberror` body was already MATCHED and descended into -- its member
# types were collected as type references -- and its member NAMES were then
# discarded.
#
# THE COST, which is the largest single false-positive source the project had:
# 58 of the 80 actionable findings in existence across the six corpora were
# `no visible binding for '<a suberror variant>'` in moonbit-community/proton
# 0.3.4. `InvalidSetting` alone was 7. The names were not missing:
# `pkg.generated.mbti:68` in the package being scanned reads
#
#     pub(all) suberror AppConfigurationError {
#       InvalidSetting(name~ : String, message~ : String)
#       ...
#     }
#
# and `collect_iface_symtabs` already reads the target's own tree -- the target's
# root is `iface_dirs[0]` in `sa/main.mbt`.
#
# WHY IT WAS INVISIBLE SO LONG. The MAIN PARSER already harvested suberror
# bodies (`Parser::skip_decl`: `what == "enum" || what == "suberror"`), so a
# variant used in the file that DECLARES it always resolved. proton's `.mbti`
# files carry 30 braced suberror bodies and 0 body-less ones, so there was no
# rare spelling that would have shown up as a discrepancy. Only the CROSS-FILE
# path was broken, which is why the symptom was false positives on correct code
# rather than unreadable files -- and why reading more files, the move that has
# fixed every blocker so far, could never have fixed this one.
#
#   M1  the predicate reverted to `enum ` only -- the defect itself.
#   M2  DECLARED SURVIVED, and it is an EQUIVALENT MUTANT. The `d > 0` clause
#       restates `decl_depth = d`, which is the line above it, and the harvest
#       branch is guarded by `decl_depth > 0` -- the two numbers are the same
#       one. Deleting the clause leaves 546/546 green, which is the proof rather
#       than an argument.
#
#       It was written expecting a body-less `pub suberror QueueAlreadyClosed
#       derive(Debug)` to harvest `derive`, and that expectation was simply
#       wrong: with `d == 0` the code sets `decl_depth = 0`, so the next line is
#       not "inside a body" and the harvest branch never runs. The behaviour M2
#       claims to break is already prevented one line earlier.
#       => an equivalent mutant is declared SURVIVED with its proof. Rescuing it
#          would mean inventing a test for behaviour that does not exist, which
#          is the "declare true survivors with their argument" rule.
#   M3  the harvest lands in `tab.types` instead of `tab.values`. Not a strawman:
#       the DECLARED suberror name genuinely IS a type (a first draft of the
#       test asserted `has_value` on it and failed), so putting constructors on
#       that side is an easy and wrong move that still looks reasonable.
#   M4  the keyword check dropped, so EVERY braced declaration body is
#       harvested and a `struct`'s FIELDS become values.
#
# M1 and M3 are killed by the same test, and that is fine: the point of a
# mutation is to fail, not to fail distinctively. M4 is the one that would ship a
# quiet regression, and its test was written before the mutation existed.

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'mutate_lib.ps1')

$PRED = @'
      in_ctor_body = (matched == "enum " || matched == "suberror ") && d > 0
'@.Replace("`r`n", "`n")

Invoke-MutationGate -Name 'M1..M4' -Target 'js' -Mutations @(

  @{
    Name = 'M1 the predicate is reverted to `enum ` only, which is the defect'
    File = 'src\moonfiles\moonfiles.mbt'
    Find = $PRED
    Repl = @'
      in_ctor_body = matched == "enum " && d > 0
'@.Replace("`r`n", "`n")
    MustRed = '0440: a braced suberror body in a .mbti yields its constructors as values'
  },

  @{
    Name = 'M2 the `d > 0` clause is deleted'
    File = 'src\moonfiles\moonfiles.mbt'
    Find = $PRED
    Repl = @'
      in_ctor_body = matched == "enum " || matched == "suberror "
'@.Replace("`r`n", "`n")
    Expect = 'SURVIVED'
    Prove = 'EQUIVALENT MUTANT: `d > 0` restates `decl_depth = d`, the line above, and the harvest branch is guarded by `decl_depth > 0` -- the same number. Measured: 546/546 stay green.'
  },

  @{
    Name = 'M3 the harvest lands in `types` instead of `values`'
    File = 'src\moonfiles\moonfiles.mbt'
    Find = @'
  for n in result.ctors {
    if !tab.values.contains(n) {
      tab.values.set(n, true)
    }
  }
'@.Replace("`r`n", "`n")
    Repl = @'
  for n in result.ctors {
    if !tab.types.contains(n) {
      tab.types.set(n, true)
    }
  }
'@.Replace("`r`n", "`n")
    MustRed = '0440: a braced suberror body in a .mbti yields its constructors as values'
  },

  @{
    Name = 'M4 the keyword check is dropped, so every braced body is harvested'
    File = 'src\moonfiles\moonfiles.mbt'
    Find = $PRED
    Repl = @'
      in_ctor_body = d > 0
'@.Replace("`r`n", "`n")
    MustRed = '0440: a struct body does not harvest its fields as constructors'
  }
)

Write-MutationGateVerdict -Name '0440'
if ($script:MutationGateFailures.Count -gt 0) { exit 1 }
exit 0
