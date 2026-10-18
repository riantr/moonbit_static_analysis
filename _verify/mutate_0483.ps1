# Mutation gate 0483 -- a PACKAGE-QUALIFIED METHOD HOLDER, `@pkg.Type::method`.
#
# WHAT THIS PINS. `fn @io.ReaderBuffer::repr(buf : Self) -> @io_buffer.Buffer = "%identity"` is
# the boundary line of three of async's sixteen unreadable files, and it reads like a missing
# foreign-function BODY. It is not: a nine-case probe against this analyzer's own parser showed
# `fn Buf::repr(b : Buf) -> Int = "%identity"` already reads (first_error 0), and every one of
# the eight failing cases fails because of the `@pkg.` and not because of the `= "string"`.
#
# There are TWO readers of this grammar and the fix had to touch both, which is what M1 and M4
# are about. `parse_fn_signature` folds the path into the AST name; `declared_name_at` folds the
# same path to HARVEST it. Fixing only the first is the worst outcome available: the file PARSES
# (so `parsed` goes up, which is the number a corpus scan measures), `actionable` stays 0, and
# every call site reports `undefined name '@other.Buf::repr'` -- ACTIONABLE, on code
# `moon check` compiles. A loud parse failure traded for a quiet false positive.
#
# Measured: async `parsed 403 -> 406`, `unreliable 122 -> 100`, `withheld 31 -> 25`,
# `notices 1776 -> 1783`, `actionable 0 -> 0`, `total 1896 -> 1883`. Two files closed outright
# (`tls/transport.mbt`, `http/parser.mbt`) and `process/redirect.mbt` moved from line 156 to
# line 229 -- it read 73 more lines and stopped at the NEXT construct, `fn &ProcessInput::close`.
#
# `_verify/settle_0483_pkg_qualified_holder.ps1`, 9 rows / 3 controls, GATE OK:
#   ACCEPT  `fn @other.Buf::m(...) = "%identity"` / `{ ... }` / `(self : @other.Buf)` / `async`
#   REJECT(4059)  `pub fn @other.Buf::m(...)`   "Cannot define method for foreign type"
#   REJECT(4156)  `extern "C" fn @other.Buf::m(...)`
#
# `pub` IS NOT PART OF THIS GRAMMAR -- which is why the analyzer reading it is a MISSED error,
# and why `record_pub_qualified_holder` carries it rather than a fix.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'mutate_lib.ps1')

$PARSER = 'src\parser\parser.mbt'

Invoke-MutationGate -Name '0483' -Target 'wasm' -Mutations @(

  # M1 THE HARVEST DOES NOT FOLD THE PACKAGE PATH. This is the mutation the corpus could not
  # have found in either direction: `parsed` goes UP (the declaration reader still works), so a
  # scan reading only parse coverage would call it a fix, and `actionable` is 0 until someone
  # calls the method. The pipeline row is the only thing that sees it.
  @{
    Name = 'M1 the harvest stops at the package alias'
    File = $PARSER
    Find = @'
      if n.has_prefix("@") && i + 1 < toks.length() {
        match (toks[i + 1], toks[i + 2]) {
          (TDot, TName(t)) => {
            let base = n + "." + t
            if i + 4 < toks.length() &&
              toks[i + 3] == TColon &&
              toks[i + 4] == TColon {
              if i + 5 < toks.length() {
                match toks[i + 5] {
                  TName(m) => return Some(base + "::" + m)
                  _ => ()
                }
              }
            }
            return Some(base)
          }
          _ => ()
        }
      }
'@.Replace("`r`n", "`n")
    Repl = '      // M1: the package-qualified fold is gone; the harvest stops at `@other`.'
    MustRed = '0483: the harvest carries the whole qualified name'
  }

  # M2 THE DECLARATION DOES NOT FOLD IT EITHER, so the file fails to parse again. The obvious
  # first mutation, and the reason M1 is the interesting one: this one is loud.
  @{
    Name = 'M2 the declaration reader does not consume the dot'
    File = $PARSER
    Find = @'
  if full.has_prefix("@") && self.at(TDot) {
    let _ = self.bump()
    let (t, _) = self.expect_name("type name after '.'")
    full = full + "." + t
  }
'@.Replace("`r`n", "`n")
    Repl = '  // M2: the package-qualified fold is gone; the reader dies on the dot.'
    MustRed = '0483: a package-qualified holder reads whole'
  }

  # M3 THE `@` GUARD IS DROPPED, so ANY dot after a declaration name is read as a qualified
  # holder. `fn f.bar(...)` is not a declaration and `moon check` refuses it, so this widens the
  # analyzer into accepting a program the compiler rejects -- the direction this project has
  # never taken, and the one the control row exists for.
  #
  # Kept as a separate mutation rather than folded into M2 because the two questions are
  # different: M2 says the arm must exist, M3 says the arm must be NARROW.
  @{
    Name = 'M3 the @ guard is dropped, so any dot after a declaration name is a qualified holder'
    File = $PARSER
    Find = '  if full.has_prefix("@") && self.at(TDot) {'
    Repl = '  if self.at(TDot) {'
    MustRed = '0483 CONTROL: a dot after an unqualified declaration name is still refused'
  }

  # M4 THE HARVEST FOLDS THE PACKAGE BUT NOT THE METHOD. The nastiest of the four, because the
  # two readers DISAGREE by exactly one token and neither is wrong on its own: the AST carries
  # `@other.Buf::repr` and the harvest produces `@other.Buf`. Every call site is then undefined,
  # on code that compiles, and M1's row catches it only because both mutations break the same
  # name -- so this row is what proves M1's row was not accidentally specific to M1.
  @{
    Name = 'M4 the harvest folds the package but not the method name'
    File = $PARSER
    Find = '                  TName(m) => return Some(base + "::" + m)'
    Repl = '                  TName(_) => return Some(base)'
    MustRed = '0483: the harvest carries the whole qualified name'
  }
)

Write-MutationGateVerdict -Name '0483'
if ($script:MutationGateFailures.Count -gt 0) { exit 1 }
exit 0
