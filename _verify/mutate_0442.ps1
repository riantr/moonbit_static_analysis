# Mutation gate 0442 -- `noraise { .. }` is a handler block, not a name.
#
# On the harness: no runner of its own, all six rules from `_verify/mutate_lib.ps1`
# apply.
#
# THE CHANGE, IN TWO PLACES, and the two are not variations of one another.
#
# 1. THE POSTFIX PRODUCTION. `Parser::parse_postfix_from` reads
#    `expr catch { .. }` into `@ast.ECatch`; it now reads a following
#    `noraise { .. }` into the new `@ast.ENoRaise`, reusing `parse_catch_arms` so
#    the arm grammar AND the `<?` log-payload guard are the same as `catch`'s.
#    The new node's base is the `ECatch`, and the walker binds each arm's pattern
#    names and walks its body.
#
# 2. THE STATEMENT-LEVEL SKIP LOOP. proton and async write
#
#        try validate(identifier) catch {
#          InvalidField(expectation~, ..) => Err(...)
#          error => Err(...)
#        } noraise {
#          identifier => Ok(identifier)
#        }
#
#    and that `try` is read by the PREFIX reader, not the postfix one. Its catch
#    loop ends in `skip_braces`, which stranded the `noraise` token and left it to
#    be resolved as an ordinary identifier.
#
# MEASURED, proton 0.3.4 and async 0.22.4, all four:
#
#     facade_identity.mbt:99     136    protocol_wbtest.mbt:5    network.mbt:68
#     99:5 - error: undefined name 'noraise' (UndefinedName)
#
# THEY ARE FALSE POSITIVES. This is MoonBit, the compiler accepts all four
# programs, and `_verify/settle_0441_noraise.ps1` settles the grammar: `noraise`
# is a postfix handler block on a COMPLETED `try ... catch` (a `try expr
# noraise { .. }` with no catch is REJECTED), its arm list is `catch`'s grammar,
# an empty block is rejected, and its pattern binds the base's RESULT value.
#
# WHAT COST THE FIRST ATTEMPT, RECORDED BECAUSE IT IS THE GENERAL SHAPE. Change
# 1 alone left the suite 8/8 GREEN and the corpus COMPLETELY UNCHANGED -- async
# still 7 actionable, proton still 10, all four `undefined name 'noraise'` still
# present. A green suite is not evidence that a corpus finding moved; the two
# were separate measurements and only the second one is the claim. Change 2 is
# what removed the findings, and M5 is the mutation that keeps it honest.
#
#   M1  the postfix production is deleted -- the original defect on that path.
#   M2  the walker does not BIND the arm patterns. Distinct from M3: the names
#       are still in the tree, they just resolve as undefined.
#   M3  the walker does not WALK the arm bodies. This is the one that produces a
#       FALSE POSITIVE rather than a missing read, and it is the `catch` defect
#       0439 fixed, one construct over.
#   M4  the walker does not walk the BASE. The base is the `ECatch`, so this
#       discards the whole catch subtree; killed by a different test from M3 on
#       purpose, so neither half can be satisfied by a fix to the other.
#   M5  the statement-level skip loop is deleted -- the defect that was ACTUALLY
#       costing the four corpus findings, and the one M1..M4 cannot see.

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'mutate_lib.ps1')

$WALK = @'
    ENoRaise(base, arms) => {
      self.walk_expr(base)
      for arm in arms {
        for b in arm.bindings {
          if b != "" {
            self.bind_pattern(b, arm.span)
          }
        }
        for st in arm.body {
          self.walk_stmt(st)
        }
      }
    }
'@.Replace("`r`n", "`n")

$POSTFIX = @'
      if self.at_name("noraise") {
        let nsp = self.span()
        let _ = self.bump()
        let narms = self.parse_catch_arms()
        e = { span: nsp, kind: @ast.ENoRaise(e, narms), }
      }
'@.Replace("`r`n", "`n")

$STMT = @'
        while self.at_name("noraise") {
          let _ = self.bump()
          self.skip_braces()
        }
'@.Replace("`r`n", "`n")

Invoke-MutationGate -Name 'M1..M5' -Target 'js' -Mutations @(

  @{
    Name = 'M1 the postfix `noraise` production is deleted'
    File = 'src\parser\parser.mbt'
    Find = $POSTFIX
    Repl = ''
    MustRed = '0442: a `noraise` handler is read, not read as a name'
  },

  @{
    Name = 'M2 the walker binds the arms but not their PATTERN names'
    File = 'src\walk\walk.mbt'
    Find = $WALK
    Repl = @'
    ENoRaise(base, arms) => {
      self.walk_expr(base)
      for arm in arms {
        for st in arm.body {
          self.walk_stmt(st)
        }
      }
    }
'@.Replace("`r`n", "`n")
    MustRed = '0442: the `noraise` pattern binds the base''s result value'
  },

  @{
    Name = 'M3 the walker walks the arms but not their BODIES'
    File = 'src\walk\walk.mbt'
    Find = $WALK
    Repl = @'
    ENoRaise(base, arms) => {
      self.walk_expr(base)
      for arm in arms {
        for b in arm.bindings {
          if b != "" {
            self.bind_pattern(b, arm.span)
          }
        }
      }
    }
'@.Replace("`r`n", "`n")
    MustRed = '0442 control: a read only inside a `noraise` body is still a read'
  },

  @{
    Name = 'M4 the walker walks the arms but not the BASE'
    File = 'src\walk\walk.mbt'
    Find = $WALK
    Repl = @'
    ENoRaise(base, arms) => {
      for arm in arms {
        for b in arm.bindings {
          if b != "" {
            self.bind_pattern(b, arm.span)
          }
        }
        for st in arm.body {
          self.walk_stmt(st)
        }
      }
    }
'@.Replace("`r`n", "`n")
    MustRed = '0442: a read inside the try expression stays read through the `noraise` wrapper'
  },

  @{
    Name = 'M5 the statement-level `noraise` skip loop is deleted, which is the defect that cost the corpus'
    File = 'src\parser\parser.mbt'
    Find = $STMT
    Repl = ''
    MustRed = '0442: a `noraise` after a statement-level `try` is not read as a name'
  }
)

Write-MutationGateVerdict -Name '0442'
if ($script:MutationGateFailures.Count -gt 0) { exit 1 }
exit 0
