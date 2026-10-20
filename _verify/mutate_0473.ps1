# Mutation gate 0473 -- the `for` HEADER is a binder head or an initializer head, and the
# initializer's clause list has a variable length.
#
# WHAT THIS PINS. Two defects, one discriminator.
#
# THE DISCRIMINATOR. `is_c_style_for` asked which of `;` and `{` arrives FIRST at depth 0.
# That is wrong in BOTH directions, because the header is variable length:
#
#     for n = step() { break n + 1 }     no `;` before `{`, so read as a BINDER and died on
#                                        `expected 'in'` -- async/src/websocket/conn.mbt:486
#
#     for p in ps; len = 0 { .. }        a `;` before `{`, so read as C-STYLE, and
#                                        `c_for_init` cannot read `p in ps`
#                                        -- async/src/io/reader.mbt:176
#
# Both were measured on the analyzer, and the second one is NOT FIXED by this increment: the
# binder head now routes correctly and the binder reader stops at the `;`, so the error
# moves from `expected ';'` to `expected 'in'` and the file is still unread. M1..M4 below
# exist to keep the discriminator honest about both halves of that, including the half that
# is deliberately left broken.
#
# THE CLAUSE LIST. `parse_c_for` carried two unconditional `expect(TSemi)`, which were
# rejecting legal headers rather than describing the grammar. Settled in
# `_verify/settle_0473_for_header_forms.ps1`, 6 gated rows, 2 controls, all ACCEPT.
#
# => 判据: M1 AND M2 ARE THE SAME FUNCTION REPLACED BY ITS TWO CONSTANTS, because a
# discriminator cannot be wrong in one direction only -- if every `for` were C-style the
# binder form breaks, and if every `for` were a binder the initializer form breaks. One of
# them is redundant with any other mutation here and that is the point: they bracket the
# answer from both sides.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'mutate_lib.ps1')

$PARSER = 'src\parser\parser.mbt'

Invoke-MutationGate -Name '0473' -Target 'wasm' -Mutations @(

  # M1 EVERY `for` IS C-STYLE. The whole scan replaced by its answer, so nothing about the
  # tokens can rescue it and the mutation genuinely exercises the routing rather than the
  # loop. The binder controls are what it has to break.
  @{
    Name = 'M1 every `for` is read as the C-style form'
    File = $PARSER
    Find = @'
fn Parser::is_c_style_for(self : Parser) -> Bool {
  let mut i = self.p + 1
  let mut depth = 0
  while i < self.toks.length() {
    match self.toks[i] {
      // The binder keyword. `in` is a reserved word, so a bare one at depth 0 in
      // the header can only be this and not a name.
      TName("in") => if depth == 0 { return false } else { i += 1 }
      TSemi => if depth == 0 { return true } else { i += 1 }
      TLParen | TLBracket => {
        depth += 1
        i += 1
      }
      TRParen | TRBracket => {
        depth -= 1
        i += 1
      }
      // The body's opening brace, still at depth 0, with no binder `in` in front
      // of it: the head is an initializer and there are no clauses after it. Do
      // not look past it.
      TLBrace =>
        if depth == 0 {
          return true
        } else {
          depth += 1
          i += 1
        }
      TRBrace => {
        depth -= 1
        i += 1
      }
      TEOF => return true
      _ => i += 1
    }
  }
  true
}
'@.Replace("`r`n", "`n")
    Repl = @'
fn Parser::is_c_style_for(self : Parser) -> Bool {
  true
}
'@.Replace("`r`n", "`n")
    MustRed = '0473 control: a plain binder head is still read as SFor, not as the C-style form'
  }

  # M2 EVERY `for` IS A BINDER. This is the discriminator's behaviour BEFORE this increment,
  # restored literally, and it is the conn.mbt:486 defect exactly.
  @{
    Name = 'M2 every `for` is read as the binder form (the pre-0473 answer)'
    File = $PARSER
    Find = @'
fn Parser::is_c_style_for(self : Parser) -> Bool {
  let mut i = self.p + 1
  let mut depth = 0
  while i < self.toks.length() {
    match self.toks[i] {
      // The binder keyword. `in` is a reserved word, so a bare one at depth 0 in
      // the header can only be this and not a name.
      TName("in") => if depth == 0 { return false } else { i += 1 }
      TSemi => if depth == 0 { return true } else { i += 1 }
      TLParen | TLBracket => {
        depth += 1
        i += 1
      }
      TRParen | TRBracket => {
        depth -= 1
        i += 1
      }
      // The body's opening brace, still at depth 0, with no binder `in` in front
      // of it: the head is an initializer and there are no clauses after it. Do
      // not look past it.
      TLBrace =>
        if depth == 0 {
          return true
        } else {
          depth += 1
          i += 1
        }
      TRBrace => {
        depth -= 1
        i += 1
      }
      TEOF => return true
      _ => i += 1
    }
  }
  true
}
'@.Replace("`r`n", "`n")
    Repl = @'
fn Parser::is_c_style_for(self : Parser) -> Bool {
  false
}
'@.Replace("`r`n", "`n")
    MustRed = '0473: a for head with one initializer and no semicolons desugars to SLet + SWhile(true)'
  }

  # M3 THE BINDER KEYWORD IS NOT A KEYWORD. The arm removed, so `in` falls through to the
  # catch-all and the scan carries on to the body's brace -- which is the pre-0473 rule again,
  # reached by a different edit. M2 already covers "always binder"; this one is the narrower
  # claim that the TOKEN is load-bearing rather than its position in the match.
  @{
    Name = 'M3 the binder keyword arm is gone, so `in` is just another name'
    File = $PARSER
    Find = '      TName("in") => if depth == 0 { return false } else { i += 1 }'
    Repl = '      // M3: the binder keyword arm removed'
    MustRed = '0473 control: a two-binder head is still read as a for'
  }

  # M4 THE BODY'S BRACE CALLS IT A BINDER AGAIN. One arm, one keyword changed back. This is
  # the smallest edit that reproduces conn.mbt:486 and nothing else moves.
  @{
    Name = 'M4 the body brace at depth 0 decides the form again (the pre-0473 arm)'
    File = $PARSER
    Find = @'
      TLBrace =>
        if depth == 0 {
          return true
        } else {
          depth += 1
          i += 1
        }
'@.Replace("`r`n", "`n")
    Repl = @'
      TLBrace =>
        if depth == 0 {
          return false
        } else {
          depth += 1
          i += 1
        }
'@.Replace("`r`n", "`n")
    MustRed = '0473: a for head with one initializer and no semicolons desugars to SLet + SWhile(true)'
  }

  # M5 THE CLAUSE LIST IS MANDATORY AGAIN. `parse_c_for` exactly as it shipped, minus the
  # list. This is the defect that rejected `for ; n > 0 { .. }` and `for n = step() { .. }`,
  # both ACCEPTED by `moon check`.
  #
  # RE-ANCHORED at 0482, like M1..M4 were at 0472. The question is unchanged and so is the
  # `MustRed`; only the text moved. 0482 rewrote this clause chain to be POSITIONAL -- it
  # asks whether the next token can begin another clause rather than whether a separator was
  # typed -- and this anchor pointed at the old spelling, so the 65-gate release run would have
  # aborted on it with `PREFLIGHT MISS` and nothing else. The name lost its "both `;`" too,
  # because 0482 settled that the separator may be a LINE BREAK and this mutation no longer
  # describes the grammar it is supposed to restore.
  @{
    Name = 'M5 the clause list is mandatory again'
    File = $PARSER
    Find = @'
  if self.at(TSemi) {
    let _ = self.bump()
  }
  if !self.at(TSemi) && !self.at(TLBrace) && !self.at(TEOF) {
    cond = self.parse_expr()
  }
  if self.at(TSemi) {
    let _ = self.bump()
  }
  if !self.at(TLBrace) && !self.at(TEOF) {
    updates = self.c_for_updates()
  }
'@.Replace("`r`n", "`n")
    Repl = @'
  if !self.at(TSemi) {
    for d in self.c_for_inits(sp) {
      stmts.push(d)
    }
  }
  self.expect(TSemi, "';'")
  if !self.at(TSemi) {
    cond = self.parse_expr()
  }
  self.expect(TSemi, "';'")
  if !self.at(TLBrace) {
    updates = self.c_for_updates()
  }
'@.Replace("`r`n", "`n")
    MustRed = '0473: a for head with no initializer carries no statement for one'
  }

  # M6 THE UPDATE CLAUSE IS READ WHETHER OR NOT IT IS THERE. The list's last `;` promised a
  # further clause and this ignores the promise. It is the only mutation here that a corpus
  # number would be slow to catch, because the form it breaks -- `for i = 0; i < n; {` -- is
  # legal and was already read before this increment.
  #
  # RE-ANCHORED at 0482 with M5, for the same reason and with the same MustRed. 0482
  # de-nested this guard (it is no longer inside an `if self.at(TSemi)`) and added the `TEOF`
  # guard beside it, so the old indentation no longer appears anywhere in the function and the
  # anchor matched nothing. M5 and M6 are the two mutations that name this chain; a fix that
  # moved one and not the other would have looked like a half-done re-anchor.
  @{
    Name = 'M6 the update clause is read even when the header ends before it'
    File = $PARSER
    Find = @'
  if !self.at(TLBrace) && !self.at(TEOF) {
    updates = self.c_for_updates()
  }
'@.Replace("`r`n", "`n")
    Repl = '  updates = self.c_for_updates()'
    MustRed = '0473: an absent update clause leaves the body exactly as written'
  }

  # M7 M2 AGAIN, PINNED ON A PIPELINE ROW. The parser rows prove the discriminator returns
  # the right answer; this proves the answer reaches the corpus at the level a scan sees. A
  # wrong discriminator stops the file at the header, so nothing after it is analysed and the
  # probe inside the body is never looked for.
  #
  # => the same rule the four vacuous 0470 rows broke: before keeping a negative row, ask
  # whether ANY mutation can turn it red.
  @{
    Name = 'M7 the binder answer for every `for`, pinned on the pipeline row'
    File = $PARSER
    Find = @'
fn Parser::is_c_style_for(self : Parser) -> Bool {
  let mut i = self.p + 1
  let mut depth = 0
  while i < self.toks.length() {
    match self.toks[i] {
      // The binder keyword. `in` is a reserved word, so a bare one at depth 0 in
      // the header can only be this and not a name.
      TName("in") => if depth == 0 { return false } else { i += 1 }
      TSemi => if depth == 0 { return true } else { i += 1 }
      TLParen | TLBracket => {
        depth += 1
        i += 1
      }
      TRParen | TRBracket => {
        depth -= 1
        i += 1
      }
      // The body's opening brace, still at depth 0, with no binder `in` in front
      // of it: the head is an initializer and there are no clauses after it. Do
      // not look past it.
      TLBrace =>
        if depth == 0 {
          return true
        } else {
          depth += 1
          i += 1
        }
      TRBrace => {
        depth -= 1
        i += 1
      }
      TEOF => return true
      _ => i += 1
    }
  }
  true
}
'@.Replace("`r`n", "`n")
    Repl = @'
fn Parser::is_c_style_for(self : Parser) -> Bool {
  false
}
'@.Replace("`r`n", "`n")
    MustRed = '0473: the body of a one-initializer for header is walked'
  }
)

# NO MUTATION FOR THE DEPTH GUARD, and that is measured rather than assumed. The
# `depth == 0` tests cannot be reached by a legal program: `in` and `;` are reserved words
# and cannot appear inside a group as names, so no token that flips an arm of this scan can
# sit at depth > 0 in a `for` header. The depth COUNTER is still load-bearing for `TLBrace`
# and `TRBrace` -- a struct literal in a header is ordinary MoonBit -- but there is no
# mutation here that could turn it red, and a mutation that cannot fail tests nothing.
# The same argument removed an earlier lookahead on the token before `in`; see the settle's
# `record_field_named_in`, which is REJECT(3002, 4041, 4091) because `in` cannot be a field.

Write-MutationGateVerdict -Name '0473'
if ($script:MutationGateFailures.Count -gt 0) { exit 1 }
exit 0
