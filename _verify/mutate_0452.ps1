# Mutation gate 0452 -- a QUOTED key in a brace literal is a MAP literal.
#
# On the harness: no runner of its own, all rules from `_verify/mutate_lib.ps1`.
# And rule 7 is the one to keep in mind here: nothing else may touch
# `src/parser/parser.mbt` while this runs.
#
# THE DEFECT. Three of the twelve files moui 0.1.12 still cannot finish reading cut
# at a `{`:
#
#     (
#       {
#         "schemaVersion": envelope.schema_version,
#       } : Json).stringify()
#
# Those keys are QUOTED. A quoted key is not a struct-literal field name, so this is
# a MAP literal, and `parse_struct_fields` had no production for one: it reported
# `expected a struct literal field here`, which is the file's `first_error`, which
# marks the file NOTPARSE and truncates everything after it.
#
# Settled in `_verify/settle_0452_quoted_key_map.ps1`, 5/5 with a positive control:
#
#     { "a": 1, "b": 2 }   as Map[String, Int]   ACCEPT
#     { a: 1 }             as Map[String, Int]   REJECT(4033, 4028)
#     { a: 1 }             as a struct           ACCEPT
#     the corpus declaration, verbatim in shape  ACCEPT
#
# THE TWO ROWS THAT CONSTRAIN THE FIX. The toolchain accepts the quoted form
# against a Map and REFUSES the unquoted one there, while the unquoted form is a
# struct literal it does accept. So the two spellings are different language forms
# and a fix that merged them would read legal code as illegal and illegal code as
# legal. M4 exists for exactly that.
#
#   M1  the quoted-key branch is removed -- the original behaviour.
#   M2  the colon is not required, so `{ "a" }` parses as a field.
#   M3  the value is read but DISCARDED: consumed without being analysed.
#   M4  the discrimination is dropped, so `{ a: 1 }` is read as a map literal too.
#
# M3 is the one worth having. M1 and M2 are both "the branch is wrong"; M3 is "the
# branch is right and the work behind it is skipped", and it produces neither a
# parse error nor a lost notice. Only the `UnusedLocal` assertion catches it: `e`
# is bound, read as the literal's value, and dead the moment the value is dropped.
# A gate that only counted parse failures would have called this mutant killed.

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'mutate_lib.ps1')

Invoke-MutationGate -Name 'M1..M4' -Target 'js' -Mutations @(

  @{
    Name = 'M1 the quoted-key branch is removed (the original behaviour)'
    File = 'src\parser\parser.mbt'
    Find = @'
    if self.at_str() {
      let key = match self.peek() {
        TStr(s, _) => s
        _ => ""
      }
      let _ = self.bump()
      self.expect(TColon, "':'")
      let v = self.parse_expr()
      fields.push((key, v))
'@.Replace("`r`n", "`n")
    Repl = @'
    if false {
      let key = match self.peek() {
        TStr(s, _) => s
        _ => ""
      }
      let _ = self.bump()
      self.expect(TColon, "':'")
      let v = self.parse_expr()
      fields.push((key, v))
'@.Replace("`r`n", "`n")
    MustRed = '0452: a quoted-key brace literal is read as a map literal'
    Prove = @'
The state before this increment. Measured on the three corpus declarations and on
two fixtures:

    { "a": 1 } as a bare tail   -> `unexpected token ':'`
    { "a": e } as a let value   -> `expected a struct literal field here`
    { a: e }   (unquoted)      -> clean

So the failure message differs with the position, which is why the blocker tally in
the corpus reads `expected ')'`, `unexpected token ':'` and
`expected a struct literal field here` for what is one defect.

`if false` rather than deleting the branch, so the code stays compiled and the
mutation measures the DECISION.
'@.Replace("`r`n", "`n")
  },

  @{
    Name = 'M2 a quoted key needs no colon'
    File = 'src\parser\parser.mbt'
    Find = @'
      self.expect(TColon, "':'")
'@.Replace("`r`n", "`n")
    Repl = @'
      if self.at(TColon) { let _ = self.bump() }
'@.Replace("`r`n", "`n")
    MustRed = '0452: a quoted key without a colon is reported as a missing colon'
    Prove = @'
THE TOLERANT IMPLEMENTATION, and it is the obvious one: accept a string wherever a
name is accepted and do not insist on a separator.

It is wrong because the shorthand does not exist. `{ "a" }` has no meaning --
there is no field named by a string -- and the toolchain rejects it. Accepting it
means the parser reads a program as legal that the compiler refuses, which is the
one failure mode a validator cannot afford: everything downstream then reasons
about code that will not build.

THE NAMED TEST WAS RENAMED BECAUSE THIS MUTATION SURVIVED IT, and the reason is
worth keeping. It asserted `parse_failures == 2`, and under M2 the fixture still
produces TWO read failures -- `{ "a" }` fails either way, just with `expected '}'`
where the test had expected `expected ':'`. A COUNT cannot tell two complaints
apart, so the count survived the mutation and the property it was written for did
not. The test now asserts the message.

M1's MustRed was updated for the same rename.
'@.Replace("`r`n", "`n")
  },

  @{
    Name = 'M3 the value is read but discarded'
    File = 'src\parser\parser.mbt'
    Find = @'
      let v = self.parse_expr()
      fields.push((key, v))
'@.Replace("`r`n", "`n")
    Repl = @'
      let v = self.parse_expr()
      fields.push((key, { span: v.span, kind: @ast.EBigInt, }))
'@.Replace("`r`n", "`n")
    MustRed = '0452: the map literal''s values are read, not stepped over'
    Prove = @'
THE MUTATION THAT MATTERS MOST, because it is the only one a parse-error count
cannot see. The tokens are consumed in order, so there is no parse failure and no
lost notice -- the file reads clean and reports exactly what it reported before.

What is lost is the VALUE. `let e = self.take()` is bound, and `e` is read as the
literal's value; drop that and `e` is dead, so the walk reports `UnusedLocal` for a
local that is used. The test pins that count at zero, which is why it exists:
`parse_failures == 0` and the notice count are both satisfied by a literal that was
stepped over rather than read.

This is the same shape as the three FFI `fn`s in 0449 and as skipping an
expression's body: the pipeline stays green and the analyzer quietly stops looking
at something.
'@.Replace("`r`n", "`n")
  },

  @{
    Name = 'M4 the quoted/unquoted discrimination is dropped'
    File = 'src\parser\parser.mbt'
    Find = @'
    if self.at_str() {
'@.Replace("`r`n", "`n")
    Repl = @'
    if self.at_str() || self.peek_name() != "" {
'@.Replace("`r`n", "`n")
    MustRed = 'a struct literal with a type path parses as EStruct with its fields'
    Prove = @'
THE OVER-CORRECTION, and the direction a reader reaches after reading the settle:
if a quoted key is a valid field, treat ANY key as one and route both forms through
the map reading.

It reads legal code as illegal. The settle is what forbids it:

    { a: 1 }  as Map[String, Int]   REJECT(4033, 4028)   <- the toolchain's answer
    { a: 1 }  as a struct           ACCEPT

So a struct literal written with unquoted keys -- the ordinary form, and the one
this parser has always read correctly -- would be handed to the map production. The
two forms CANNOT be merged: they are different language forms, not two spellings of
one.

THE NAMED TEST IS NOT IN `pipeline_0452_test.mbt` and that is the measurement.
This mutation does NOT stop `{ a: a }` parsing -- it bumps the name, the match on
`TStr` misses so the key comes back EMPTY, and the literal is built with a nameless
field. What it destroys is the KEY, so the test has to be one that observes a field
name, and "a struct literal with a type path parses as EStruct with its fields"
already is. The test written for this mutation in the 0452 file asserted only that
the fixture parsed, and it stayed GREEN under the mutation.

That is the "a count or a shape that two different functions both satisfy" failure
again, and the gate caught it by naming a test that had not gone red rather than
accepting that five unrelated tests had.
'@.Replace("`r`n", "`n")
  }
)

Write-MutationGateVerdict -Name '0452'
if ($script:MutationGateFailures.Count -gt 0) { exit 1 }
exit 0
