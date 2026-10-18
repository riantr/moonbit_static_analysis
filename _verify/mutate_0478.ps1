# Mutation gate 0478 -- the `<?` PAYLOAD on an expression.
#
# WHAT THIS PINS. proton 0.3.4 carries 26 sites of `expr <? { "key": value, .. }` across 7
# files and no other pinned corpus carries one; four of those files were unreadable for it.
# Measured: `parsed` 131 -> 135, `unreliable` 186 -> 37, `actionable` still 0.
#
# The payload is a JSON object literal DESUGARED TO METHOD CALLS ON AN OPTIONAL receiver --
# `@xlog` 0.4.2 declares `error(...) -> Event?` and `Event::{write_object_begin,
# write_object_field, write_object_end}`. The subset has no `Event`, so the payload is
# consumed with NO NODE of its own while its VALUES are parsed AND KEPT, because a name the
# walker never visits is a name it reports dead (`facade_bridge.mbt:11` passes a lambda parameter).
#
# `_verify/settle_0478_log_payload.ps1`, 2 controls + 5 rows, GATE OK:
#   ACCEPT             the corpus shape / an EXPRESSION value / a TRAILING COMMA / `{ }` empty
#   REJECT(3002)       the KEY must be a string literal
#   REJECT(3002, 3002) AT MOST ONE payload
#
# M1 AND M2 ARE THE MUTATIONS THAT FAILED FIRST, which is why they are here rather than being
# written after the fact as though the reader had been right all along: a guard that consumed
# `<` and `?` without checking the brace left the flag to be read as a fresh statement, and a
# postfix LOOP absorbed a second payload. Both are false negatives -- the analyzer accepting
# code the compiler refuses -- and they were found by rows written against the settle rather
# than against the reader.
# EVERY ANCHOR BELOW MOVED TWICE AFTER THE FIRST "4/4 KILLED", and the run did not say so.
# The 4/4 that first stood up was measured against a reader that no longer exists: M1 anchored
# on the INLINE `self.toks[self.p + 2] == TLBrace`, which the newline fix replaced with a call
# to `at_log_payload_brace`; M3 anchored on `_ => return`, which became `_ => return kept` when
# the function started returning the values it keeps; M4 anchored on a bare `self.skip_log_payload()`
# call, which became `let kept = self.skip_log_payload()` at the same moment. Two FIXES landed,
# each moving an anchor, and the pre-flight caught all three on the next full release -- 3
# patterns absent, no suite run, in 1s.
#
# THAT IS THE SECOND TIME IN THIS INCREMENT that a number I had already written down was
# describing older code (the first was the release gate finding the newline). The anchors are
# re-pointed at the CURRENT spelling of the SAME three questions -- the brace is still required
# (M1), the key is still required to be a TStr (M3), the payload is still consumed (M4) -- and
# the verdicts below are re-measured from scratch. None of the three was retired: retiring a
# mutation because its anchor moved is how a rule quietly stops being checked.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'mutate_lib.ps1')

$PARSER = 'src\parser\parser.mbt'

Invoke-MutationGate -Name '0478' -Target 'wasm' -Mutations @(

  # M1 THE BRACE CHECK IS DROPPED, so `< ?` alone becomes the operator. `a < ?flag` is not
  # MoonBit and the settle's own reasoning says the pair can only be the payload BECAUSE a
  # brace follows; without the check the flag is left on the cursor and read as a fresh
  # statement, so the file parses and nothing is reported.
  @{
    Name = 'M1 the brace is not required after `< ?`'
    File = $PARSER
    Find = '  return j < self.toks.length() && self.toks[j] == TLBrace'
    Repl = '  return true'
    MustRed = '0478 control: no payload parses, and `a < ?` stays refused'
  }

  # M2 THE ONE-PAYLOAD LIMIT IS GONE, so the postfix chain absorbs a second `<?`. The settle
  # is REJECT(3002, 3002) on `x <? {..} <? {..}`, so the loop turns a refusal the toolchain
  # makes into an acceptance -- the single most dangerous shape a reader can have, because
  # every file still parses and the disagreement is invisible in every count.
  @{
    Name = 'M2 a second payload is absorbed instead of refused (the flag is never set)'
    File = $PARSER
    Find = '      had_payload = true'
    Repl = '      had_payload = had_payload'
    MustRed = '0478: a second payload is a parse error, not a second consumption'
  }

  # M3 THE KEY IS SKIPPED RATHER THAN MATCHED. The settle is REJECT(3002) for anything that
  # is not a string literal, and this mutation consumes whatever is there instead -- so
  # `{ k: d }` parses and the reader has thrown away exactly the check that distinguishes a
  # payload key from an arbitrary token.
  @{
    Name = 'M3 the payload key is not required to be a string literal'
    File = $PARSER
    Find = @'
    match self.peek() {
      TStr(_, _) => {
        let _ = self.bump()
      }
      _ => return kept
    }
'@.Replace("`r`n", "`n")
    Repl = @'
    if !self.at(TEOF) {
      let _ = self.bump()
    }
'@.Replace("`r`n", "`n")
    MustRed = '0478: a key that is not a string literal is refused'
  }

  # M4 THE PAYLOAD IS NEVER CONSUMED. The `<?` pair is eaten and the braces are left, so the
  # statement reader meets `{` where it wants a statement. This is the regression that a
  # `first_error == 0` assertion exists to catch, and it is why that assertion is the first
  # line of the corpus row rather than the last.
  @{
    Name = 'M4 the payload braces are left in the token stream'
    File = $PARSER
    Find = '      let kept = self.skip_log_payload()'
    Repl = '      let kept : Array[@ast.Expr] = []'
    MustRed = '0478: the payload is consumed and leaves no node behind'
  }
)

Write-MutationGateVerdict -Name '0478'
if ($script:MutationGateFailures.Count -gt 0) { exit 1 }
exit 0
