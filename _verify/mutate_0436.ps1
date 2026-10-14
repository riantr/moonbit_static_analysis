# Mutation gate 0436 -- a QUALIFIED constructor in an `is` pattern.
#
# On the harness: no runner of its own, all six rules from
# `_verify/mutate_lib.ps1` apply.
#
# THE CHANGE, and the correction it carries. The standing backlog called this "`is`
# pattern in EXPRESSION position", on the reading that `parse_is` was not reached.
# It is reached, and had been for several releases. What is missing is INSIDE
# `parse_is_pattern`: the lexer has no `TColonColon`, `::` is two `TColon` tokens,
# and the pattern reader bumped the head name and returned without consuming them.
# The surviving `:` walked back up through `parse_cmp` into `parse_atom`'s
# catch-all -- which is why the scanner's reason string read
# ``unexpected token `:` `` on a line whose only `:` is a PATH MARKER.
#
# "A reason string is not a reason" has now cost three rankings in a row. The
# right question was never which token the parser died on but which line it died
# on, and `blockers.ps1` is the tool that answers that.
#
#   M1  The qualified-path tail is not consumed at all. Every positive test goes
#       red on `first_error`.
#   M2  The two `::` tokens are consumed but the NAME after them is not. This is
#       the half-fix: the file still parses far enough to look plausible, and the
#       payload test is what catches it.
#   M3  `while` weakened to `if`. DECLARED SURVIVED -- see the prove text, which
#       records that the first version of that argument was WRONG and says what
#       replaced it.
#
#   M4  The path tail is consumed AFTER the payload test rather than before, which
#       is the ordering the comment claims is load-bearing. Expressed as a
#       mutation by moving the `::` consumption below the `TLParen` branch.
#
# NOT IN THIS GATE: a PACKAGE-qualified pattern head, `is @pkg.Type::Ctor`, does
# not parse at all -- the head token is `@`, not a name, so `peek_name()` is "" and
# the reader returns having consumed nothing.
#
# 48 corpus SITES, 32 of them in wzzc-dev/moui across 16 files -- and SITES ARE NOT
# FILES. `_verify/pkg_head_impact.ps1` scans each of those 16 files ALONE: 15 come
# back `parsed=1/1` (their site sits inside a skipped `test` block) and exactly ONE
# is blocked, `backend/macos/macos_services.mbt`. So this is a ONE-FILE fix today
# and a SIXTEEN-FILE one the day test blocks are analysed -- smaller than the
# five-file `Type::Ctor` change beside it, which is the opposite of what the site
# count suggested.
#
# It is also the construct `blockers.ps1` cannot see: `macos_services.mbt` is one
# of the four blocked files that print no `PARTIAL` line, so cross-referencing the
# two lists gives OVERLAP 0 and the gap reads as free. Pinned as a KNOWN LIMIT in
# `parser_0436_test.mbt` with a control that drops the `@sqlite3.` prefix.
#
# Settled with the toolchain, one form per package with a broken canary beside it
# (`_verify/probe_sweep_0434.ps1`, re-run at 0.4.30, canary firing):
#   `if self is St::Shutdown { 1 } else { 2 }`   MOON-OK
#   `status() is St::Presented`                  MOON-OK
#   `fn canary( { let = 1 }`                     MOON-BAD, as it must be
# all three SELF-FAILing before this change.

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'mutate_lib.ps1')

Invoke-MutationGate -Name 'M1..M4' -Target 'js' -Mutations @(

  @{
    Name = 'M1 a qualified constructor path is not consumed at all'
    File = 'src\parser\parser.mbt'
    Find = @'
    while self.at(TColon) && self.at_next(TColon) {
      let _ = self.bump()
      let _ = self.bump()
      if self.peek_name() == "" {
        break
      }
      let _ = self.bump()
    }
'@.Replace("`r`n", "`n")
    Repl = ''
    MustRed = 'a qualified constructor is read in an if condition'
  },

  @{
    Name = 'M2 the :: is consumed but the name after it is left behind'
    File = 'src\parser\parser.mbt'
    Find = @'
    while self.at(TColon) && self.at_next(TColon) {
      let _ = self.bump()
      let _ = self.bump()
      if self.peek_name() == "" {
        break
      }
      let _ = self.bump()
    }
'@.Replace("`r`n", "`n")
    Repl = @'
    while self.at(TColon) && self.at_next(TColon) {
      let _ = self.bump()
      let _ = self.bump()
    }
'@.Replace("`r`n", "`n")
    MustRed = 'a qualified constructor is read in an if condition'
  },

  @{
    Name = 'M3 the path tail loop only handles ONE segment (while -> if)'
    File = 'src\parser\parser.mbt'
    Find = @'
    while self.at(TColon) && self.at_next(TColon) {
      let _ = self.bump()
      let _ = self.bump()
      if self.peek_name() == "" {
        break
      }
      let _ = self.bump()
    }
'@.Replace("`r`n", "`n")
    Repl = @'
    if self.at(TColon) && self.at_next(TColon) {
      let _ = self.bump()
      let _ = self.bump()
      if self.peek_name() != "" {
        let _ = self.bump()
      }
    }
'@.Replace("`r`n", "`n")
    MustRed = 'a qualified constructor is read in an if condition'
    Expect = 'SURVIVED'
    Prove = @'
declared survivor, and the argument was WRONG the first time it was written here.
It claimed the `while` existed for `@pkg.Type::Ctor`. That is false for this loop:
such a head begins with `@`, so `peek_name()` is "" and the reader returns before
reaching the loop at all. `@pkg.Type::Ctor` turned out to be a SEPARATE gap, and a
smaller one than the site count suggested -- 48 sites but ONE blocked file, since
the rest sit inside skipped `test` blocks. It is pinned as a KNOWN LIMIT in
`parser_0436_test.mbt` and measured by `_verify/pkg_head_impact.ps1`.

What `while` and `if` actually differ on is a head with TWO or more `::` after the
first segment, and there are ZERO such sites anywhere in the corpora:
`Select-String '\bis\s+(?!@)\w+(\w*::\w*){2,}'` over every .mbt/.mbti under
.repos returns nothing. No test written from the corpus can separate them, so
writing one would be inventing evidence.

The loop is kept because narrowing it would be a change justified by no
measurement at all, while keeping it costs one comparison per iteration. This
mutation stays in the gate as the thing that turns red if a multi-`::` head ever
appears.
'@.Replace("`r`n", "`n")
  },

  @{
    Name = 'M4 the path tail is consumed AFTER the payload test, not before'
    File = 'src\parser\parser.mbt'
    Find = @'
    while self.at(TColon) && self.at_next(TColon) {
      let _ = self.bump()
      let _ = self.bump()
      if self.peek_name() == "" {
        break
      }
      let _ = self.bump()
    }
  } else {
    return []
  }
  let binding : Array[String] = []
  if self.at(TLParen) {
'@.Replace("`r`n", "`n")
    Repl = @'
  } else {
    return []
  }
  let binding : Array[String] = []
  if self.at(TLParen) {
'@.Replace("`r`n", "`n")
    MustRed = 'a qualified constructor with a payload binds its argument'
  }
)

Write-MutationGateVerdict -Name '0436'
if ($script:MutationGateFailures.Count -gt 0) { exit 1 }
exit 0