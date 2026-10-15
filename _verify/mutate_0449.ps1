# Mutation gate 0449 -- two shapes the parser did not read, and one that read a
# declaration that was not there.
#
# On the harness: no runner of its own, all rules from `_verify/mutate_lib.ps1`.
#
# DEFECT A -- the EXTERNAL BINDING tail of a `fn`: `= "module" "symbol"`. A `fn`
# whose body lives in another language is declared, not defined. The parser
# finished the signature, found `=` where it wanted `{`, and reported
# `expected '{'` -- the parser naming a token that was never the problem. That
# report is the file's `first_error`, so the file is marked NOTPARSE and
# everything after the declaration goes unread.
#
# Settled in `_verify/settle_0449_ffi_decl.ps1`, 7/7 with BOTH negative controls
# firing. Cost, on wzzc-dev/moui 0.1.12: FOUR of the seventeen files the
# truncation ranking reports (`_verify/diagnose_moui_truncations.ps1`), the largest
# single shape there. Settling it also made 21 async files readable, which is
# where DEFECT B was found.
#
# DEFECT B -- the TUPLE STRUCT `struct Name(T)`. `skip_decl_braced` scans forward
# for the `{` that opens a body; a tuple struct has none, so the scan ran on and
# took the NEXT declaration's brace. In moonbitlang/async 0.22.4
# `src/process/cancellation.mbt` that brace belongs to an
# `if @event_loop.platform is Windows {`, so the `let` and the `if` were
# swallowed and `else` / `SIGTERM` were reported as undefined variables -- two
# false positives blamed on a declaration nobody was complaining about.
#
# Settled in `_verify/settle_0449b_tuple_struct.ps1`, 8/8 with three negative
# controls firing.
#
#   M1  The binding is not consumed at all -- the original behaviour.
#   M2  The binding consumes ONE string, which is what `parse_extern_fn` did.
#   M3  The binding parses but does not REGISTER the name.
#   M4  Every struct is treated as a tuple struct -- the over-correction.
#   M5  No struct is treated as a tuple struct -- the original behaviour.
#   M6  A tuple struct is skipped as if it were braced (the tuple branch never
#       fires for the declaration shape the corpus actually writes).
#
# M2 and M4/M5 are the pair that matters most. M2 is the obvious implementation
# and it silently leaves half the binding in the token stream. M4 is the obvious
# over-correction after reading M2: treat every struct as bodiless, which would
# parse a braced struct's body as top-level statements and trade two false
# positives for a cascade.

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'mutate_lib.ps1')

Invoke-MutationGate -Name 'M1..M6' -Target 'js' -Mutations @(

  @{
    Name = 'M1 the external binding is not consumed'
    File = 'src\parser\parser.mbt'
    Find = @'
  if self.parse_external_binding(name) {
    return { span: sp, kind: @ast.SFunc(name, params, retann, [], sp), }
  }
'@.Replace("`r`n", "`n")
    Repl = @'
  if false {
    return { span: sp, kind: @ast.SFunc(name, params, retann, [], sp), }
  }
'@.Replace("`r`n", "`n")
    MustRed = '0449: an external fn binding parses instead of expecting a body'
    Prove = @'
The state before this increment: the `=` is left in the token stream, `parse_block`
is called, it wants `{`, and it reports `expected '{'` at a token that is not the
problem. Measured on the settled shapes, that is `2x expected '{'` and both files
NOTPARSE.

`if false` rather than deleting the call, so the binding code stays compiled and
the mutation measures the DECISION rather than the compiler.
'@.Replace("`r`n", "`n")
  },

  @{
    Name = 'M2 the binding consumes one string, leaving the second behind'
    File = 'src\parser\parser.mbt'
    Find = @'
  while seen < 2 && self.at_str() {
'@.Replace("`r`n", "`n")
    Repl = @'
  while seen < 1 && self.at_str() {
'@.Replace("`r`n", "`n")
    Expect = 'SURVIVED'
    Prove = @'
DECLARED SURVIVED, and the claim it replaces was falsified rather than defended.

This was originally written as "the control that catches the obvious wrong
implementation", with a `MustRed` naming the test that distinguishes reading the
binding from reading HALF of it. That test was ALREADY GREEN under this mutation
(598/598) and stays green, so the control did not control anything.

MEASURED WHY, over nine fixtures -- an external binding followed by a `fn`, by a
top-level `let`, by a braced struct, by a tuple struct, by a second external
binding, with no blank line before the next declaration, plus two controls.
Findings under `seen < 1` are identical to findings under `seen < 2`, in every
one. The reason is a fact about what a leftover string literal IS: a well-formed
top-level expression statement, which the analyzer accepts silently. It does not
report, it does not set `first_error`, and it does not swallow the declaration
after it.

So the loop bound is still right -- leaving a token in the stream is not a parse
-- but nothing in this analyzer can see it. The fixture is kept and its comment
rewritten to say this rather than to claim a discrimination it does not make.
'@.Replace("`r`n", "`n")
  },

  @{
    Name = 'M3 the binding parses but does not register the name'
    File = 'src\parser\parser.mbt'
    Find = @'
  if !self.extern_fns.contains(name) {
    self.extern_fns.push(name)
  }
  true
}
'@.Replace("`r`n", "`n")
    Repl = @'
  let _ = name
  true
}
'@.Replace("`r`n", "`n")
    MustRed = '0449: an external fn is not audited for a body that was never read'
    Prove = @'
The declaration parses either way. What changes is whether the header-only
function's frame gets audited.

THE MECHANISM IN THIS ENTRY WAS WRONG AND IS CORRECTED HERE. It used to say the
missing registration makes "every call site read `undefined function`". Measured:
it does not, and it cannot. `extern_fns` is consumed at exactly one place --
`walk.mbt:1170`, in the condition that guards `audit_frame` -- and an undefined
FUNCTION is not produced there. A same-file call also keeps resolving through the
analyzer's own top-level declaration table, which is why the original test for
this mutation was green under it and had to be rewritten.

What the registration actually buys is measured. `parse_external_binding` returns
a header-only `SFunc` whose body was never read, so every parameter of an
external fn is unused for a reason the file does not contain:

    registration present   no findings at all
    registration absent    UnusedParam = 1

That is the whole trade the mutation refuses, and it is why the fix cannot stop at
"it parses": four unread files would have become four files with a false positive
each. The corpus CANNOT catch this -- `parsed=` goes UP either way, and the
findings introduced are exactly the kind a corpus scan cannot tell from real ones.
Only a test that asserts on a header-only function's audit can, so that is what
the named test does.

`let _ = name` keeps the parameter read, so the mutation compiles.
'@.Replace("`r`n", "`n")
  },

  @{
    Name = 'M4 every struct is treated as a tuple struct'
    File = 'src\parser\parser.mbt'
    Find = @'
      TName(_) => i += 1
      TLParen => return true
'@.Replace("`r`n", "`n")
    Repl = @'
      TName(_) => i += 1
      TLBrace => return true
'@.Replace("`r`n", "`n")
    MustRed = '0449: an ordinary braced struct still skips its body whole'
    Prove = @'
THE OVER-CORRECTION, and the direction a reader reaches for after reading M2: if
a bodyless struct is the problem, treat them all as bodyless.

It would parse a braced struct's first line and hand the BODY to the statement
parser, so every field becomes an undefined name and a top-level statement. Two
false positives traded for a cascade, on the most common declaration MoonBit
has.

THE NAMED TEST FOR THIS WAS GREEN UNDER IT, and the reason is a fixture detail
rather than a mechanism. Measured against this mutation:

    struct with ONE field   -> ParseError 2, UndefinedName ABSENT
    struct with TWO fields  -> ParseError 3, UndefinedName 1

With a single field the leftover line is absorbed by the struct's own stray `}`
and no name is ever reported, so the fixture the gate named asserted nothing
about the mutation it was written for. The suite caught this mutation anyway by
accident, killing 21 tests -- which is precisely the "the kill is incidental"
failure `mutate_lib.ps1` rule 6 exists to name. The fixture now has two fields.
'@.Replace("`r`n", "`n")
  },

  @{
    Name = 'M5 no struct is treated as a tuple struct'
    File = 'src\parser\parser.mbt'
    Find = @'
    } else if kw == "struct" && p.at_tuple_struct() {
'@.Replace("`r`n", "`n")
    Repl = @'
    } else if kw == "struct" && false && p.at_tuple_struct() {
'@.Replace("`r`n", "`n")
    MustRed = '0449: a tuple struct does not swallow the declaration after it'
    Prove = @'
The original behaviour, isolated: the tuple branch never fires, so
`skip_decl_braced` runs past the tuple struct to the next `{`.

On the corpus that next brace was an `if`'s, and `cancellation.mbt:41,42`
reported `undefined variable 'else'` and `undefined variable 'SIGTERM'` -- two
false positives on correct code.

THE NAMED TEST WAS CHANGED BACK ONCE, for a measured reason worth keeping.
`skip_decl_braced` breaks at a top-level `fn` (`parser.mbt:802`), the sentinel
that stops a bodiless `pub impl Eq for T` from swallowing the file. A tuple
struct inherits it, so a tuple struct followed by a FUNCTION is not affected at
all. A fixture built that way -- "the tuple struct does not swallow the function
after it" -- stayed GREEN under this mutation while the suite was red, and rule
6 named the test that had actually gone red. The damage needs a `let ... = if`
between the struct and the brace, which is exactly what the corpus writes.

`false &&` keeps `at_tuple_struct` compiled and called, so the mutation measures
the dispatch and not a dead function.
'@.Replace("`r`n", "`n")
  },

  @{
    Name = 'M6 a tuple struct is skipped as if it were braced'
    File = 'src\parser\parser.mbt'
    Find = @'
      p.skip_decl_line(kw, sp)
    } else if kw == "struct" ||
'@.Replace("`r`n", "`n")
    Repl = @'
      p.skip_decl_braced(kw, sp)
    } else if kw == "struct" ||
'@.Replace("`r`n", "`n")
    MustRed = '0449: a tuple struct does not swallow the declaration after it'
    Prove = @'
The SAME test kills M5, and the two mutations are kept anyway because they fail
by DIFFERENT routes and a reader needs both routes visible: M5 leaves the
dispatch alone and disarms the predicate, M6 arms the predicate and picks the
wrong skipper. A gate that only kept one would describe the fix as "call the
predicate" when half of it is "and then skip to the end of the line, not to the
next brace".

It also pins the SKIPPER and not just the branch. The notice wording is part of
it: `skip_decl_line` says "declaration is outside the analyzed subset", which is
true of a tuple struct, while `skip_decl_braced` says "its body was not
analyzed", which claims a body this declaration does not have -- the same
correction the `derive` branch in that dispatcher already carries.
'@.Replace("`r`n", "`n")
  }
)

Write-MutationGateVerdict -Name '0449'
if ($script:MutationGateFailures.Count -gt 0) { exit 1 }
exit 0
