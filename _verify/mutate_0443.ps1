# Mutation gate 0443 -- `nobreak { .. }` is a postfix block on a LOOP.
#
# On the harness: no runner of its own, all six rules from `_verify/mutate_lib.ps1`
# apply.
#
# THE CHANGE. `loop nobreak { .. }` had no production, so the bare token resolved
# as an ordinary identifier. Measured:
#
#     proton internal/bridge_admission_test/main.mbt:20
#     20:5 - error: undefined name 'nobreak' (UndefinedName)
#
# A false positive: proton 0.3.4 compiles. `_verify/settle_0443_nobreak.ps1`
# settles the grammar, 10/10 with the positive control green -- `nobreak` is a
# postfix on a LOOP (`while` and `for`), a loop is REQUIRED, the body is a
# STATEMENT LIST (`nobreak { 1 }` is rejected 4139), and an EMPTY block is
# ACCEPTED, unlike `noraise { }` which is rejected.
#
# The census is 34 `nobreak` lines in moonbitlang/async and 2 in proton, and ONE
# of them reaches the actionable set. A census number is not a finding count.
#
# THE NODE NEEDS FOUR ARMS, NOT ONE, and M2..M5 are the four. `walk_stmt` was
# taught `SNoBreak` first and the suite's two `for` tests failed with
# `no visible binding for 'x'` and `no visible binding for 'i'` -- the FOR
# BINDERS, not `nobreak` -- because both binding collectors have a `_ => ()`
# catch-all and the compiler says nothing about a missing arm. There are two
# collectors, not one: `collect_fn_bindings` for a function's own declarations
# and `collect_top` for the module frame, and a top-level `for` executes at
# module level and so puts its binder there.
#
#   M1  the wrap never happens -- the original defect.
#   M2  the walker walks the loop but NOT the block, which is the false-positive
#       direction: a read only inside a `nobreak` body disappears and the name it
#       reads starts reporting unread.
#   M3  the walker walks the block but NOT the loop. Distinct from M2, and pinned
#       by a different test on purpose.
#   M4  the per-function collector stops descending -- the `for` binder is lost.
#   M5  the MODULE collector stops descending -- the same loss one function
#       lower, and invisible to M4.

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'mutate_lib.ps1')

$WALK = @'
    SNoBreak(loop_stmt, block) => {
      self.walk_stmt(loop_stmt)
      for st in block {
        self.walk_stmt(st)
      }
    }
'@.Replace("`r`n", "`n")

# RE-POINTED BY 0467b, and NOT retired -- the difference matters. `mutate_lib.ps1`
# matches `Find` by literal ordinal `IndexOf`, so a 2-space dedent is
# indistinguishable from a deletion: this anchor missed preflight on a change that
# moved the code rather than removing it. The arm is still there and still carries
# the same defect surface -- the per-function collector must descend into the loop
# statement or the `for` binder is lost -- so retiring it would trade a live guard
# for a footnote.
#
# Two things changed under the anchor at once, and both are 0467b: the arm dedented
# from 8 to 6 spaces when the collector was hoisted to top level, and the callee was
# renamed `scan` -> `collect_stmt_bindings`. The property M4 pins is UNCHANGED, so
# the mutation stays one property: drop the `loop_stmt` descent, keep the block.
$SCAN = @'
      SNoBreak(loop_stmt, block) => {
        collect_stmt_bindings(bs, [loop_stmt])
        collect_stmt_bindings(bs, block)
      }
'@.Replace("`r`n", "`n")

$TOP = @'
        SNoBreak(loop_stmt, block) => {
          collect_top([loop_stmt])
          collect_top(block)
        }
'@.Replace("`r`n", "`n")

Invoke-MutationGate -Name 'M1..M5' -Target 'js' -Mutations @(

  @{
    Name = 'M1 the loop is never wrapped, so `nobreak` is a name again'
    File = 'src\parser\parser.mbt'
    Find = @'
  if !self.at_name("nobreak") {
    return loop_stmt
  }
'@.Replace("`r`n", "`n")
    Repl = @'
  if true {
    return loop_stmt
  }
'@.Replace("`r`n", "`n")
    MustRed = '0443: a `nobreak` block on a `while` is read, not read as a name'
  },

  @{
    Name = 'M2 the walker walks the loop but NOT the `nobreak` block'
    File = 'src\walk\walk.mbt'
    Find = $WALK
    Repl = @'
    SNoBreak(loop_stmt, block) => {
      self.walk_stmt(loop_stmt)
      for _ in block {
        ()
      }
    }
'@.Replace("`r`n", "`n")
    MustRed = '0443 control: a read only inside a `nobreak` body is still a read'
  },

  @{
    Name = 'M3 the walker walks the block but NOT the loop'
    File = 'src\walk\walk.mbt'
    Find = $WALK
    Repl = @'
    SNoBreak(_loop_stmt, block) => {
      for st in block {
        self.walk_stmt(st)
      }
    }
'@.Replace("`r`n", "`n")
    MustRed = '0443: a read inside the loop stays read through the `nobreak` wrapper'
  },

  @{
    Name = 'M4 the per-function collector stops descending, so the `for` binder is lost'
    File = 'src\walk\walk.mbt'
    Find = $SCAN
    Repl = @'
      SNoBreak(_, block) => {
        collect_stmt_bindings(bs, block)
      }
'@.Replace("`r`n", "`n")
    MustRed = '0443: a `nobreak` block on a `for` loop is read'
  },

  @{
    Name = 'M5 the MODULE collector stops descending, one function lower than M4'
    File = 'src\walk\walk.mbt'
    Find = $TOP
    Repl = @'
        SNoBreak(_, block) => {
          collect_top(block)
        }
'@.Replace("`r`n", "`n")
    MustRed = '0443: a module-level `for` binder still binds through a `nobreak` block'
  }
)

Write-MutationGateVerdict -Name '0443'
if ($script:MutationGateFailures.Count -gt 0) { exit 1 }
exit 0
