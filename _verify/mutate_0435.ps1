# Mutation gate 0435 -- the INCLUSIVE range operator `a..<=b`.
#
# On the harness: no runner of its own, all six rules from
# `_verify/mutate_lib.ps1` apply.
#
# THE CHANGE. `..<=` is four characters and the lexer had no token for it. The
# comment that stood in its place said "`..=` is not modelled: it was not
# measured in the blocked corpus this token was added for" -- true when written
# (`1..<chars.length()` was the shape that motivated the token), and stale by the
# time anyone read it again.
#
# SETTLED WITH THE TOOLCHAIN, one form per package with a broken canary beside
# each, because the toolchain's own error message names both real forms:
#
#   `0..n`    REJECTED -- "Missing `=` after `..` in range expression. Hint:
#              use `a..<=b` for inclusive range or `a..<b` for exclusive"
#   `0..<n`   accepted -- exclusive, already one TRange token
#   `0..<=n`  accepted -- INCLUSIVE. This is the form, not `..=`.
#   `0..=<n`  REJECTED
#
# So the inclusive operator is `..<=`, and a bare `..` staying two TDots is
# CORRECT rather than an omission.
#
# It is a SEPARATE token from `TRange` even though both become the same
# `ERange` node, because no lens models inclusivity -- `walk`, `types::infer` and
# `interp` all read both operands and nothing else. The parser therefore emits a
# subset-exclusion notice for the inclusive end, so `a..<=b` and `a..<b` are not
# silently the same tree. M3 is the mutation for that honesty.
#
#   M1  The four-character `..<=` branch is gone.
#   M2  The three-character `..<` branch is gone. This is the risk of adding a
#       LONGER SIBLING next to an existing rule: two near-identical conditions,
#       and dropping the wrong one is a compile-clean no-op.
#   M3  The inclusive-end notice is not emitted. The file still PARSES, so this
#       is invisible to any `first_error == 0` assertion -- which is the reason
#       the tests assert the notice rather than the absence of reports.

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'mutate_lib.ps1')

Invoke-MutationGate -Name 'M1..M3' -Target 'js' -Mutations @(

  @{
    Name = 'M1 the inclusive range operator is not lexed at all'
    File = 'src\lexer\lexer.mbt'
    Find = @'
  if c == '.' &&
    next == Some('.') &&
    self.pos + 3 < self.chars.length() &&
    self.chars[self.pos + 2] == '<' &&
    self.chars[self.pos + 3] == '=' {
    self.pos += 4
    self.col += 4
    self.emit(TRangeIncl, l, c0, 4)
    return TRangeIncl
  }
'@.Replace("`r`n", "`n")
    Repl = ''
    MustRed = 'an inclusive range a..<=b is read'
  },

  @{
    Name = 'M2 the exclusive range operator is not lexed any more'
    File = 'src\lexer\lexer.mbt'
    Find = @'
  if c == '.' &&
    next == Some('.') &&
    self.pos + 2 < self.chars.length() &&
    self.chars[self.pos + 2] == '<' {
    self.pos += 3
    self.col += 3
    self.emit(TRange, l, c0, 3)
    return TRange
  }
'@.Replace("`r`n", "`n")
    Repl = ''
    MustRed = 'an exclusive range a..<b is read and says nothing extra'
  },

  @{
    Name = 'M3 the inclusive end is read and NOT announced'
    File = 'src\parser\parser.mbt'
    Find = @'
      if incl {
        self.note_skip(
          "inclusive range end is outside the analyzed subset; it was read but the bound was not analysed",
          sp,
        )
      }
'@.Replace("`r`n", "`n")
    Repl = ''
    MustRed = 'an inclusive range a..<=b is read'
  }
)

Write-MutationGateVerdict -Name '0435'
if ($script:MutationGateFailures.Count -gt 0) { exit 1 }
exit 0