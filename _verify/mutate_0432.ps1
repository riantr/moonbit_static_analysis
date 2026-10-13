# Mutation gate 0432 -- a chain continuing on the next line, and suberror
# variant constructors.
#
# On the harness: no runner of its own, all six rules from
# `_verify/mutate_lib.ps1` apply. Verified in the 0.4.30 audit: 16 gates on the
# harness, 0 carrying their own runner.
#
# TWO CHANGES SHARE THIS GATE because they were found by the same A/B and are
# not separable in effect -- reading one more file exposed the other.
#
#   1. A method chain whose `.` starts the FOLLOWING line. The postfix loop used
#      to break at the newline, which was SILENT in a `let` (the receiver was
#      kept, `.length()` discarded, and the type lens then reported a mismatch on
#      correct code) and fatal in argument position (the chain's tokens stayed
#      unconsumed and the file died on the call's own `)`). 17 of wzzc-dev/moui
#      0.1.12's 86 unreadable files at 0.4.30.
#
#   2. `harvest_ctors` was called for `enum` bodies only, so a suberror's
#      variants were never collected and every `raise Variant(...)` was reported
#      as an undefined name -- including where the suberror is declared in the
#      SAME FILE. Measured false positives removed: 13 in proton 0.3.4, 2 in
#      proton_contract 0.3.4, 1 in async 0.22.4.
#
#   M1  Delete the next-line chain block entirely. Invisible to an
#       `first_error`-only assertion: the silent-drop shape PARSES CLEAN.
#   M2  Drop the REWIND of the speculatively consumed separators. Declared
#       SURVIVED with its argument -- see the Prove, and the same reasoning
#       0418's M11 records.
#   M3  Revert the suberror harvest to `enum` only.
#   M4  Harvest payload NAMES too (`depth >= 0` instead of `depth == 0`). Every
#       payload token is nested, so this turns a parameter type name into a
#       module-level value binding -- the exact confusion the depth rule exists
#       to prevent.
#
# MustRed on M1, M3 and M4. "Killed" alone does not say the right thing went red,
# and M1 in particular dies to a test that checks the chain was APPLIED rather
# than merely that the file parsed -- which is the whole distinction, since a
# dropped chain parses clean.

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'mutate_lib.ps1')

$PARSER = 'src\parser\parser.mbt'

Invoke-MutationGate -Name 'M1..M4' -Target 'js' -Mutations @(

  @{
    Name = 'M1 a chain continuing on the next line is not read at all'
    File = $PARSER
    Find = @'
    if self.at(TNewline) {
      let save = self.p
      self.skip_seps()
      if self.at(TDot) {
        continue
      }
      self.p = save
    }
    break
'@.Replace("`r`n", "`n")
    Repl = '    break'
    MustRed = 'keeps the REAL receiver'
  },

  @{
    Name = 'M2 the speculative separators are not rewound, fusing the next statement'
    File = $PARSER
    Find = @'
      if self.at(TDot) {
        continue
      }
      self.p = save
'@.Replace("`r`n", "`n")
    Repl = @'
      if self.at(TDot) {
        continue
      }
      ignore(save)
'@.Replace("`r`n", "`n")
    Expect = 'SURVIVED'
    Prove = @'
MEASURED, not assumed: this mutation survived 462/462 green.

The rewind looks load-bearing and is not, for the same reason 0418's M11 does
not die: the enclosing statement loop calls `skip_seps` again anyway, so the
next statement starts in the same place whether the cursor was rewound or left
after the separators. The test beside it is direct evidence rather than an
absence of evidence -- `0432 control: a newline that does not continue the
chain still ends it` asserts the body really does hold TWO statements
(`let v = a` then `v + 1`), and it stays green under this mutation.

SCOPE OF THE CLAIM, stated because it is narrower than it looks: this is
measured against the suite and that one control, NOT against the six corpora,
so it is evidence that the fusion does not happen for the shapes tested rather
than a proof that no shape exists where it would.

The rewind is KEPT for the same reason M11 keeps its rewind: it makes the loop
correct on its own terms instead of correct only because a caller happens to
clean up. Deleting it to make the mutation KILLED would be the error.

A first draft of this row was mislabelled twice before this verdict: the
replacement text also deleted the `if self.at(TDot) { continue }` above, so the
mutation was M1 wearing M2's name and was reported KILLED twice over. The gate
caught it because the two named tests that killed it were the CHAIN tests, not
the statement-separation test the mutation claimed to break.
'@.Replace("`r`n", "`n")
  },

  @{
    Name = 'M3 suberror variants are not harvested again'
    File = $PARSER
    Find = 'if what == "enum" || what == "suberror" {'
    Repl = 'if what == "enum" {'
    MustRed = 'a suberror variant is a constructor'
  },

  @{
    Name = 'M4 payload names are harvested as values as well as variant heads'
    File = $PARSER
    Find = @'
        if depth == 0 &&
          !self.after_path_marker(i) &&
'@.Replace("`r`n", "`n")
    Repl = @'
        if depth >= 0 &&
          !self.after_path_marker(i) &&
'@.Replace("`r`n", "`n")
    MustRed = 'a suberror variant is a constructor'
  }
)

Write-MutationGateVerdict -Name '0432'
if ($script:MutationGateFailures.Count -gt 0) { exit 1 }
exit 0