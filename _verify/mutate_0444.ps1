# Mutation gate 0444 -- a BARE LOWERCASE `is` head is a variable binding.
#
# On the harness: no runner of its own, all six rules from `_verify/mutate_lib.ps1`
# apply.
#
# THE CHANGE. `Parser::parse_is_pattern` consumed the pattern head unconditionally
# as a CONSTRUCTOR and collected bindings only from a parenthesised payload, so
#
#     if probe() is err && err != 0 { .. err .. }
#
# bound nothing at all. The walker already bound whatever `EIs` carried -- the
# parser was handing it an empty list -- so the defect was entirely on this side.
#
# THE CORPUS MANIFESTATION IS NOT AN UNDEFINED NAME, which is what made this worth
# an increment. Measured, async 0.22.4 `src/tls/schannel.mbt` lines 218, 224, 235,
# 284 and 446 all report
#
#     unsupported operand types for '!=': 'fn err (signature not read)' and 'int'
#
# because something ELSE named `err` is in scope in that package and wins the
# lookup. An ISOLATED reproduction of the same source reports `undefined name
# 'err'` instead. Two symptoms, one cause, and only the isolated form points at
# the parser -- which is why the first move was a probe rather than a patch.
#
# SETTLED, not inferred -- `_verify/settle_0444_is_head.ps1`, 9/9, positive
# control AND a canary green:
#
#   - `if probe() is err && err != 0 { err }` COMPILES: a lowercase head binds.
#   - `if opt() is Some && Some != 0` is REJECTED: an uppercase head is a
#     CONSTRUCTOR TEST, and a function compared with an integer is the only
#     reading that explains the rejection.
#   - an unused head binding AND an unused payload binding are both LEGAL, which
#     is why `EIs` moved from `bind` to `bind_pattern` and why the head and the
#     payload can share that one call.
#
#   M1  the head binding is not recorded -- the defect itself.
#   M2  the lowercase test accepts UPPERCASE too, so every head binds. This is the
#       mutation that separates "lowercase binds" from "every head binds", and it
#       is invisible to M1's test: the corpus does not care, the test does.
#   M3  `EIs` binds with `bind` instead of `bind_pattern`, putting the name on the
#       audit list. This is a FALSE POSITIVE that the fix has to avoid, not one
#       it introduces, and it is the mutation that would catch a regression back
#       into it.
#   M4  the QUALIFIED guard is dropped, so `is St::Shutdown` binds the first `::`
#       segment as a local.
#   M5  the PAYLOAD guard is dropped, so `is Some(x)` binds `Some` as well.
#
# M2, M4 AND M5 SURVIVE, and the reason is a DIRECTION rather than a missing
# test, so they are declared rather than re-anchored onto something that does go
# red. Measured 574/574 green under each.
#
# Both halves of the mechanism are in the source and were read to establish this:
#
#   - `Walker::bind_pattern` sets the frame entry and does NOT push onto
#     `self.orders[fi]`, the audit list. An extra unread binding therefore cannot
#     produce `UnusedLocal`. (`bind` DOES push, which is exactly why M3 is
#     observable and M3's KILL confirms the audit path is live.)
#   - `Infer::EIs` binds the names it is given as `TUnknown`, not as nothing. So
#     a spurious name becomes RESOLVED-AND-UNKNOWN rather than unresolved, and a
#     resolved-but-unknown name can only SUPPRESS a type finding, never create
#     one.
#
# Both mutations move in the same direction: quieter. A suppressed finding is not
# observable in this tool's output, which is the definition of an equivalent
# mutant for a diagnostic.
#
# THE HONEST CAVEAT, because "equivalent" must not become "harmless": these three
# guards are currently UNOBSERVABLE. They express the settled grammar -- an
# uppercase head is a constructor test, a qualified head's name is its last `::`
# segment, a head with a payload is a constructor taking arguments -- and none of
# the three is load-bearing against today's lenses. They would become load-bearing
# the moment a lens started AUDITING `is` bindings, at which point each would
# immediately produce a false positive. That is the thing worth keeping them for,
# and it is also why they are declared here rather than left as five silent
# passes.

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'mutate_lib.ps1')

$HEAD = @'
  if !qualified && !self.at(TLParen) && is_binding_head_name(head) {
    binding.push(head)
  }
'@.Replace("`r`n", "`n")

Invoke-MutationGate -Name 'M1..M5' -Target 'js' -Mutations @(

  @{
    Name = 'M1 the head binding is not recorded, which is the defect'
    File = 'src\parser\parser.mbt'
    Find = $HEAD
    Repl = @'
  if false {
    binding.push(head)
  }
'@.Replace("`r`n", "`n")
    MustRed = '0444: a lowercase `is` head binds, and the guard can read it'
  },

  @{
    Name = 'M2 the lowercase test accepts UPPERCASE too, so every head binds'
    File = 'src\parser\parser.mbt'
    Find = @'
    return ch >= 'a' && ch <= 'z'
'@.Replace("`r`n", "`n")
    Repl = @'
    return ch >= 'a' && ch <= 'z' || ch >= 'A' && ch <= 'Z'
'@.Replace("`r`n", "`n")
    Expect = 'SURVIVED'
    Prove  = 'MEASURED 574/574 green. DIRECTION: `is_binding_head_name` only widens the frame. `bind_pattern` does not push onto the audit list, so no UnusedLocal can appear; and `Infer::EIs` seeds a spurious name as TUnknown, i.e. RESOLVED-AND-UNKNOWN rather than unresolved, which can only SUPPRESS a type finding. Both directions are quieter. See the header.'
  },

  @{
    Name = 'M3 `EIs` binds with `bind`, putting an unused `is` binding on the audit list'
    File = 'src\walk\walk.mbt'
    Find = @'
          self.bind_pattern(b, e.span)
'@.Replace("`r`n", "`n")
    Repl = @'
          self.bind({ name: b, tyann: "", param: false, decl_span: e.span, })
'@.Replace("`r`n", "`n")
    MustRed = '0444: an unused `is` head binding is legal, not an unused local'
  },

  @{
    Name = 'M4 the QUALIFIED guard is dropped, so `is St::Shutdown` binds a local'
    File = 'src\parser\parser.mbt'
    Find = $HEAD
    Repl = @'
  if !self.at(TLParen) && is_binding_head_name(head) {
    binding.push(head)
  }
'@.Replace("`r`n", "`n")
    Expect = 'SURVIVED'
    Prove  = 'MEASURED 574/574 green. Same DIRECTION as M2: binding `St` adds an unaudited frame entry and a TUnknown seed. `St` is otherwise used only as a TYPE ANNOTATION (`x : St`), which no lens resolves as a value, so the extra entry has nothing to shadow. Cannot create a finding.'
  },

  @{
    Name = 'M5 the PAYLOAD guard is dropped, so `is Some(x)` binds `Some` as well'
    File = 'src\parser\parser.mbt'
    Find = $HEAD
    Repl = @'
  if !qualified && is_binding_head_name(head) {
    binding.push(head)
  }
'@.Replace("`r`n", "`n")
    Expect = 'SURVIVED'
    Prove  = 'MEASURED 574/574 green. Same DIRECTION as M2, and the test that looks like it should catch it asserts UnusedLocal == 0, which is the wrong instrument: `bind_pattern` never reaches the audit list, so an extra binding is invisible to that family by construction. The payload guard keeps `Some` from being seeded TUnknown over the constructor.'
  }
)

Write-MutationGateVerdict -Name '0444'
if ($script:MutationGateFailures.Count -gt 0) { exit 1 }
exit 0
