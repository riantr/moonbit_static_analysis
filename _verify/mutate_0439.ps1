# Mutation gate 0439 -- `expr catch { pattern => body }`, the handler is READ.
#
# On the harness: no runner of its own, all six rules from
# `_verify/mutate_lib.ps1` apply.
#
# THE CHANGE. `parse_postfix_from`'s `catch` arm called `skip_braces`: the CALL
# survived (which is why the arm existed at all) but the handler body was thrown
# away. A handler body is where the reads of the enclosing function's parameters
# live, so the only mention of such a parameter could be invisible.
#
# The measured cost, and it was the only actionable finding wzzc-dev/moui had:
#   backend/macos/macos_native_ime.mbt:437:3
#   parameter 'prefix' may not be used (UnusedParam)
#
# `prefix~` is read at line 442, inside `catch { err => { ... } }`. The fix
# parses the arms into `@ast.CatchArm` and walks them, so the read is seen. The
# handler's PATTERN has to be parsed at the same time, because reading a body
# whose pattern was never bound manufactures `no visible binding for 'err'` --
# which is why `parse_atom`'s `try` arm skips its handlers whole.
#
# THE ARM SHAPES ARE A CENSUS, NOT A GUESS (`_verify/census_catch.ps1`):
#   moui    54 handler sites: 9 block-bodied, 45 expression-bodied
#   proton 323 handler sites: 29 block-bodied, 273 expression-bodied
# The expression form is the COMMON one, and it is the one the first draft got
# wrong twice: `parse_stmt` reads a leading `{` as a BLOCK, so the arm-body
# choice has to be made before `parse_stmt` sees anything.
#
#   M1  `at_fat_arrow` looks for `TArrow`, which is `->`. `=>` has NO token: it
#       arrives as `TAssign` then `TGt`. This is the bug the first draft shipped
#       and then measured -- the arm ran past its own braces and every
#       expression-bodied handler died with `expected '}'` at EOF.
#   M2  `parse_catch_pattern` drops the `depth == 0` brace guard, so a struct
#       pattern `Wrap({ inner })` ends at the `{` of its own inner brace.
#   M3  The walker binds the arms but does not walk their bodies -- the read
#       still goes missing, which is the defect restated.
#   M4  The walker walks the arms but does not bind them, so the body resolves
#       its own pattern name against nothing.
#   M5  `bind_pattern` becomes a real `bind`, putting the superset's constructor
#       names into the audit list: `catch Boom(n) => ...` would then report
#       `local variable 'Boom' assigned but may not be used`. A false positive
#       manufactured BY the fix, in exchange for removing an old one.
#   M6  THE ONE THAT MATTERS MOST. Put a `note_skip` on the handler -- the cheap
#       fix this change deliberately rejected. It silences `UnusedParam` for the
#       WHOLE enclosing function, exactly as a `match` does, so every POSITIVE
#       assertion in `pipeline_0439_test.mbt` still returns 0 and every one of
#       them passes for the wrong reason.
#   M7  The `<?` guard is removed, so a handler carrying an `@xlog` payload is
#       parsed and the file dies. This is not hypothetical: with the arms parsed
#       and no guard, proton 0.3.4 `facade_locale.mbt` went from `parsed` to
#       `not-parsed` -- the fix fixed one corpus and broke another, and
#       `parsed=` is the number that went DOWN.
#
# M6 is why that file's positives are all zero-counts with a matching
# one-unread-parameter negative. A guard that has never been seen to go red is
# not a guard, and "the family was switched off" is the specific way this fix
# could have shipped looking correct.
#
# M6's first draft used the message "catch handler was read but not analysed"
# and SURVIVED -- 537/537 green, which reads like the cheap fix being harmless.
# It is not harmless, it is INERT: `pipeline.mbt` builds `unread` from reports
# whose message contains the literal substring "outside the analyzed subset",
# so a skip with any other wording suppresses nothing at all. The mutation was
# reporting on its own wording, not on the behaviour.
# => a surviving mutation is a question about the MUTATION first, exactly as a
#    failing one is a question about the CODE.
#
# M7's first draft looked for `TQuestion` followed by `TLt`. `<?` is `<`
# THEN `?`, so the guard never fired and M7 passed for the wrong reason -- the
# mutation was not being caught because the thing it removes was already
# inert. A mutation gate reports on the mutation, not on the intent.
#
# M7's MustRed also had to lose its backticks: the harness matches the test name
# as a REGEX, and `<?` in a pattern means "optional `<`", so the pattern did not
# match the literal name even though the test went red and the harness said so
# in the very next line.
# => read what the harness says it actually saw, not only the verdict word.
#
# THE COST, RECORDED RATHER THAN DISCOVERED LATER:
#   moui             actionable  1 -> 0   parsed 590 unchanged  (the target)
#   moonbit_labeler  actionable  0 -> 0   parsed  25 unchanged
#   moonbit_image    actionable  0 -> 0   parsed   2 unchanged
#   async            actionable 14 -> 12  parsed 227 unchanged
#   proton           actionable 63 -> 78  parsed 103 -> 102, then 103 with M7
#   proton_contract  actionable  0 -> 0   parsed   4 unchanged
#
# proton's +15 are ALL `no visible binding for '<some suberror variant>'`, and
# every one is inside a catch body that used to be skipped -- `protocol.mbt:260`
#     err => raise MalformedJson(detail=err.to_string())
# is the clearest. That is the per-file `enum_ctors` harvest limitation,
# becoming VISIBLE because the body is read now. It is the same trade the
# README already describes, in the same direction it has gone before, and it is
# paid in false positives rather than in unread files.
#
# Grammar settled with the compiler: `_verify/settle_0439_catch.ps1` (12 cases,
# positive control + two negative controls). Its first run was VOID -- all 12
# cells came back REJECTED including the control -- because the PRELUDE was
# wrong twice over: `priv fn` does not exist ("No 'private' visibility for
# function") and `derive(Error)` is not a trait ("The type Error is not a
# trait"). The error trait is `@error.Error`.
# => a settle case that fails for an UNRELATED reason settles nothing, whatever
#    else it prints -- and a settle run whose POSITIVE CONTROL fails has
#    measured the probe, not the grammar.
#
# The arm shapes themselves were settled by CENSUS rather than by the probe,
# which is the stronger evidence for a question about what real code writes:
# `_verify/census_catch.ps1` counts 9 block-bodied against 45 expression-bodied
# handler sites in moui, and 29 against 273 in proton.

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'mutate_lib.ps1')

$PARSE_PATTERN_HEAD = @'
  while !self.at(TEOF) {
    if self.at_fat_arrow() {
      break
    }
    if self.at(TLBrace) && depth == 0 {
      break
    }
'@.Replace("`r`n", "`n")

$WALK_ARMS = @'
    ECatch(base, arms) => {
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

Invoke-MutationGate -Name 'M1..M7' -Target 'js' -Mutations @(

  @{
    Name = 'M1 the fat arrow is looked up as TArrow, which is `->` not `=>`'
    File = 'src\parser\parser.mbt'
    Find = @'
fn Parser::at_fat_arrow(self : Parser) -> Bool {
  self.at(TAssign) && self.peek2() == TGt
}
'@.Replace("`r`n", "`n")
    Repl = @'
fn Parser::at_fat_arrow(self : Parser) -> Bool {
  self.at(TArrow)
}
'@.Replace("`r`n", "`n")
    MustRed = '0439: an expression-bodied catch arm parses'
  },

  @{
    Name = 'M2 a struct pattern ends at its own inner brace'
    File = 'src\parser\parser.mbt'
    Find = $PARSE_PATTERN_HEAD
    Repl = @'
  while !self.at(TEOF) {
    if self.at_fat_arrow() {
      break
    }
    if self.at(TLBrace) {
      break
    }
'@.Replace("`r`n", "`n")
    MustRed = '0439: a struct pattern does not end at its own brace'
  },

  @{
    Name = 'M3 the walker binds the arms but never walks their bodies'
    File = 'src\walk\walk.mbt'
    Find = $WALK_ARMS
    Repl = @'
    ECatch(base, arms) => {
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
    MustRed = '0439: a parameter read only inside a catch arm is not reported unused'
  },

  @{
    Name = 'M4 the walker walks the arms but never binds their patterns'
    File = 'src\walk\walk.mbt'
    Find = $WALK_ARMS
    Repl = @'
    ECatch(base, arms) => {
      self.walk_expr(base)
      for arm in arms {
        for st in arm.body {
          self.walk_stmt(st)
        }
      }
    }
'@.Replace("`r`n", "`n")
    MustRed = '0439: a handler body can use the name its own pattern bound'
  },

  @{
    Name = 'M5 pattern names go through the real bind, so the superset is audited'
    File = 'src\walk\walk.mbt'
    Find = @'
fn Walker::bind_pattern(self : Walker, name : String, sp : @core.Span) -> Unit {
  let fi = self.frames.length() - 1
  let frame = self.frames[fi]
  if !frame.contains(name) {
    frame.set(name, { param: false, assigns: 0, varuses: 0, decl_span: sp, })
  }
}
'@.Replace("`r`n", "`n")
    Repl = @'
fn Walker::bind_pattern(self : Walker, name : String, sp : @core.Span) -> Unit {
  self.bind({ name: name, tyann: "", param: false, decl_span: sp, })
}
'@.Replace("`r`n", "`n")
    MustRed = "0439: a catch pattern's constructor name is not reported as an unused local"
  },

  @{
    Name = 'M6 the handler gets a note_skip, silencing UnusedParam for the whole function'
    File = 'src\parser\parser.mbt'
    Find = @'
      let arms = self.parse_catch_arms()
'@.Replace("`r`n", "`n")
    Repl = @'
      let arms = self.parse_catch_arms()
      self.note_skip("catch handler is outside the analyzed subset; it was read but not analysed", csp)
'@.Replace("`r`n", "`n")
    MustRed = '0439 control: an unread parameter beside a read one is still reported'
  },

  @{
    Name = 'M7 the `<?` log-payload guard is gone, so a handler with a payload dies'
    File = 'src\parser\parser.mbt'
    Find = @'
  if self.catch_group_has_log_payload() {
    // A `<?` log payload is inside this group and is not in the subset. The
    // whole group goes back to being skipped, which is what every release did
    // before the handler was parsed at all. See `catch_group_has_log_payload`.
    self.skip_braces()
    return arms
  }
'@.Replace("`r`n", "`n")
    Repl = @'
'@.Replace("`r`n", "`n")
    MustRed = '0439: a catch group holding a log payload is skipped, not parsed'
  }
)

Write-MutationGateVerdict -Name '0439'
if ($script:MutationGateFailures.Count -gt 0) { exit 1 }
exit 0
