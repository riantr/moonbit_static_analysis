# Mutation gate 0477 -- the CONSTRUCTOR PATTERN on the left of a `let`.
#
# WHAT THIS PINS. `async/src/os_error/error.mbt` reported `1x expected '='` and nothing else,
# because there is no `parse_pattern` in the parser: `let OSError(errno, context~) = self`
# had `OSError` consumed as the bound VARIABLE and then met `(` where it wanted `=`. 21 such
# sites in that corpus, and the analyzer counted the whole file as unreadable.
#
# The reader already existed -- `parse_is_pattern` has read constructor patterns for `is`
# since 0444 -- so this increment is a CALL SITE, and what this gate pins is that the call
# site neither over-reaches (M1, M4) nor under-reaches (M2, M3).
#
# `_verify/settle_0477_let_pattern.ps1`, 2 controls + 9 rows, GATE OK:
#   ACCEPT   positional / labeled / `..` rest / nested / tuple
#   ACCEPT   a label BINDS the name
#   REJECT(4080, 3007)  anything after `..`       NOT this reader's check
#   REJECT(4080, 4085)  an unknown label          NOT this reader's check
#   REJECT(4080)       too many positionals      NOT this reader's check
#   REJECT(0011)       a refutable pattern       NOT this reader's check
#
# => NO NEW NODE. `SLetDestruct(Array[String], Expr)` is already the node for a `let` that
# binds several names at once. The four refusals above are TYPE questions; the parser is
# type-blind, and refusing them here would be a false negative against the corpus.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'mutate_lib.ps1')

$PARSER = 'src\parser\parser.mbt'
$GUARD = '    if self.peek_name() != "" && self.at_next(TLParen) {'

Invoke-MutationGate -Name '0477' -Target 'wasm' -Mutations @(

  # M1 THE TOKEN-SHAPE HALF OF THE GUARD IS DROPPED, so every `let <name> = ..` is read as a
  # pattern. The over-reach, and the row it dies on is the CONTROL: a plain `let b : Int = a+1`
  # would come back as `SLetDestruct`, which drops the type annotation `walk` and `infer` both
  # read off `SLet`. Nothing errors -- the file still parses -- which is why this is the shape
  # that a parse-only assertion cannot see.
  @{
    Name = 'M1 the guard no longer requires a following paren, so a plain let becomes a pattern'
    File = $PARSER
    Find = $GUARD
    Repl = '    if self.peek_name() != "" {'
    MustRed = '0477 control: a plain binding is still SLet, not SLetDestruct'
  }

  # M2 THE PATTERN'S OWN NAMES ARE REPLACED BY ONE INVENTED NAME. This is the mutation the whole
  # increment is aimed at, and it is the one that parses CLEAN: every token is consumed, the file
  # reports no error, and the corpus file counts as READ. What is wrong is invisible to
  # `first_error` and shows only as `undefined name` against names the compiler accepts -- the
  # 0460 failure mode, where an array pattern read as expressions reported
  # `undefined name 'compression_method'` and then used it eight lines later.
  @{
    Name = 'M2 the pattern binds one invented name instead of the names it introduces'
    File = $PARSER
    Find = @'
      let names = self.parse_is_pattern()
      self.expect(TAssign, "'='")
      let init = self.parse_expr()
      return { span: sp, kind: @ast.SLetDestruct(names, init), }
'@.Replace("`r`n", "`n")
    Repl = @'
      let _ = self.parse_is_pattern()
      self.expect(TAssign, "'='")
      let init = self.parse_expr()
      return { span: sp, kind: @ast.SLetDestruct(["bound"], init), }
'@.Replace("`r`n", "`n")
    MustRed = '0477: a labeled constructor pattern binds both names'
  }

  # M3 THE BRANCH NEVER FIRES. The increment reverted, with nothing else touched. Every row in
  # this increment's suite must go red on it, and the one that would go red MOST loudly is the
  # `first_error` assert rather than a binding assert -- which is the point of keeping both kinds
  # of row: a parser test that only checked bindings would report this mutation as a parse
  # failure it did not describe.
  @{
    Name = 'M3 the constructor branch is never taken'
    File = $PARSER
    Find = $GUARD
    Repl = '    if false {'
    MustRed = '0477: a labeled constructor pattern binds both names'
  }

  # M4 THE HEAD IS BOUND AS A NAME. `parse_is_pattern` deliberately does not bind a constructor
  # head -- 0444 settled that a lowercase head binds while an uppercase one is a constructor
  # TEST -- and this call site reuses that reader, so the rule arrives for free. Pinning it
  # separately is what stops a future refactor that "helpfully" collects the head from quietly
  # inventing a local named after every constructor in the corpus.
  @{
    Name = 'M4 the constructor head is bound as a name'
    File = $PARSER
    Find = '      let names = self.parse_is_pattern()'
    Repl = '      let names = [self.peek_name()] + self.parse_is_pattern()'
    MustRed = '0477: a labeled constructor pattern binds both names'
  }
)

# NO MUTATION FOR THE `peek_name() != ""` HALF ALONE, and that is measured rather than skipped.
# Dropping it alone leaves the branch reachable only when the token after the one at the cursor
# is `(`. Every shape that reaches this point has the cursor on a NAME (the plain-binding path
# and the tuple path are both downstream or mutually exclusive with it), so the token at
# `cursor + 1` is `=`, `:`, `(`, or `~` -- never a second `(`. The half is therefore redundant
# GIVEN the placement, and pinning redundancy as a mutation would be pinning a coincidence of
# the branch's position rather than a rule.
#
# => 判据: a mutation that cannot fail tests nothing. The honest statement is that the guard is
# two conditions where one would do, and it is kept because a reader of the code should not have
# to re-derive that `at_next(TLParen)` implies the cursor is on a name. If the branch is ever
# MOVED above the tuple branch, M1 stops being the only thing that matters and this note is the
# thing that has to be revisited.

Write-MutationGateVerdict -Name '0477'
if ($script:MutationGateFailures.Count -gt 0) { exit 1 }
exit 0
