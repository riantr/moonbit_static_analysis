# Mutation gate 0466 -- the return-type EFFECT annotation, and 0466b `.. rest`.
#
# WHAT THIS PINS. Two increments, and the second is only here because of the first.
#
# 0466 -- `-> T noraise` and `-> T nocancel` had no production. `parse_raise_effect`
# handles `!` and `raise` and stopped at the other two, so every one reported
# `expected '{'` AT THE BODY -- a message about a brace standing where a keyword is.
# Measured reach, as per-FILE first blocker over the files still unread: 16 of them
# (async 11, proton 5).
#
# 0466b -- unblocking `async src/internal/event_loop/fs.mbt` then reported
# `undefined name 'payload'` TWICE, from
#     guard! buf is [u32le(_), u32le(mask), .. payload]
# A name the pattern itself introduces.
#
# THE GRAMMAR, settled in `_verify/settle_0466_effect_annotation.ps1` (17 rows) and
# `_verify/settle_0466b_rest_binding.ps1` (6 rows) rather than read off the symbols:
#
#     -> T !              ACCEPT       <- `!` is in the SAME slot as `noraise`
#     -> T noraise raise  REJECT(3002) <- effects do NOT stack
#     -> T bogus          REJECT(3002) <- CANARY: a keyword set, not "any word"
#     -> T noraise E      REJECT(3002) <- and it takes NO error type, unlike `raise`
#     .. rest             ACCEPT       <- binds
#     is [a, .. ]         ACCEPT       <- a bare `..` is legal
#     name not in pattern REJECT(4021) <- CANARY: bindings are not invented
#
# => 判据: three of those rows would have been implemented wrong from the symbol.
# `!` does not look like a neighbour of `noraise`, effects stacking is what
# `raise` + `noraise` looks like in every other language, and `raise` carrying an
# error type is true OF `raise` -- which is why M6 below is the mutation that shares
# their tail.
#
# PATTERNS ARE PURE ASCII ON PURPOSE. Several of these sites carry em dashes in their
# comments, and a Find pattern containing one is read as ANSI by PowerShell 5.1 and
# silently matches nothing -- which a mutation harness reports as a failure to apply,
# not as a defect.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'mutate_lib.ps1')

$PARSER = 'src\parser\parser.mbt'

Invoke-MutationGate -Name '0466' -Target 'js' -Mutations @(

  # M1 THE INCREMENT ITSELF. The `noraise` / `nocancel` arm is gone, which is the
  # pre-0466 parser verbatim: both words stop the parse and the body reports.
  @{
    Name = 'M1 `noraise` and `nocancel` are not consumed as effects'
    File = $PARSER
    Find = "  if self.at_name(`"noraise`") || self.at_name(`"nocancel`") {`n    let _ = self.bump()`n    return`n  }`n"
    Repl = ''
    MustRed = '0466: `-> T noraise` and `-> T nocancel` parse'
  }

  # M2 THE SHORTCUT THE CANARY FORBIDS. Consume whatever name sits between the return
  # type and the brace. Every ACCEPT row above still passes -- `noraise`, `nocancel`,
  # `!`, `raise` are all names -- and `-> Unit bogus` starts parsing, which is a
  # program `moon check` rejects with 3002.
  @{
    Name = 'M2 the effect slot consumes ANY name'
    File = $PARSER
    Find = '  if self.at_name("noraise") || self.at_name("nocancel") {'
    Repl = '  if self.peek_name() != "" {'
    MustRed = '0466: a non-effect word after the return type reports a ParseError'
  }

  # M3 ONE DOT INSTEAD OF TWO. DECLARED SURVIVOR, and the reason is a reach
  # measurement rather than an absence of coverage -- the first draft of this row
  # declared MustRed against the constructor-head guard and the harness reported a
  # MUST-RED MISS, which was CORRECT: that guard pins that `Some` does not bind, and
  # `Some(v)` contains no dot at all, so it cannot see the difference between one dot
  # and two.
  #
  # The two-dot rule cannot be observed at all, because a ONE-DOT name cannot occur
  # in a valid `is` pattern. Settled: `is Foo.bar` is REJECTed by the toolchain with
  # 4021 and 3002 -- `Foo` is an unknown name and a path is not a pattern. So every
  # name preceded by a dot in real pattern syntax is preceded by TWO of them, and
  # widening the predicate to one dot changes nothing on any program that compiles.
  @{
    Name = 'M3 `.. rest` accepts ONE dot, so path segments bind'
    File = $PARSER
    Find = '  if self.toks[j - 1] != TDot || self.toks[j - 2] != TDot {'
    Repl = '  if self.toks[j - 1] != TDot {'
    Expect = 'SURVIVED'
    Prove = 'Unreachable by construction rather than untested: a ONE-dot name cannot occur in a valid `is` pattern. `is Foo.bar` is REJECTed by moon check with 4021 + 3002 (unknown name, and a path is not a pattern), so in real pattern syntax every dot-preceded name is preceded by TWO. Widening to one dot therefore differs on no program that compiles. Kept as its own predicate rather than a flag on pattern_binding_at precisely because that width cannot be tested from the outside.'
  }

  # M4 THE ASYMMETRY WITH `raise`, SHARED AWAY. `-> T raise E` names an error type and
  # `parse_raise_effect` reads it with a careful guard. `-> T noraise E` is REJECTed
  # by the toolchain, so `noraise` must NOT read one -- and the mutation that shares
  # the tail eats the body's `{`, because a brace is not a type head.
  @{
    Name = 'M4 `noraise` reads an error type the way `raise` does'
    File = $PARSER
    Find = "  if self.at_name(`"noraise`") || self.at_name(`"nocancel`") {`n    let _ = self.bump()`n    return`n  }"
    Repl = "  if self.at_name(`"noraise`") || self.at_name(`"nocancel`") {`n    let _ = self.bump()`n    let _ = self.type_annotation()`n    return`n  }"
    MustRed = '0466: `-> T noraise` and `-> T nocancel` parse'
  }

  # M5 THE REST BINDING WIDENED TO THE TUPLE BRANCH. DECLARED SURVIVOR, and the Prove
  # is a reach argument rather than an absence of coverage: no pinned corpus writes
  # `is (a, .. rest)` -- 9 sites in 4 files exist and every one is an ARRAY pattern --
  # so no program in any corpus can observe it. Widening it would be teaching the
  # parser a shape with no evidence that anything writes it.
  @{
    Name = 'M5 `.. rest` also binds in a TUPLE pattern'
    File = $PARSER
    Find = '        if !in_type && depth >= 2 && self.pattern_binding_at(j) {'
    Repl = '        if !in_type && depth >= 2 && (self.pattern_binding_at(j) || self.rest_binding_at(j)) {'
    Expect = 'SURVIVED'
    Prove = 'Unreachable by construction rather than untested: no pinned corpus writes `is (a, .. rest)`. The 9 measured `..` rest sites are all in ARRAY patterns (async 0.22.4, 4 files) and the tuple branch needs depth >= 2. Widening it would add a shape no evidence suggests is written. If a corpus ever grows the form this survivor becomes killable and must then be declared KILLED.'
  }

  # M6 THE `_` AND KEYWORD GUARD DROPPED, so `.. _` and `.. for` would bind. DECLARED
  # SURVIVOR on the same reach argument: the settle confirms a bare `..` is legal
  # (`rest_bare` ACCEPT) but no corpus writes `.. _` or `.. <keyword>`, so nothing in
  # the measured set can observe it. The guard stays because it is the same guard
  # `pattern_binding_at` applies, and dropping it there would bind every keyword head
  # in every pattern.
  @{
    Name = 'M6 `.. rest` binds `_` and keywords too'
    File = $PARSER
    Find = '  n != "_" && !@lexer.is_moonbit_keyword(n)'
    Repl = '  true'
    Expect = 'SURVIVED'
    Prove = 'Unreachable by construction: a bare `..` with no name is legal (settle row rest_bare ACCEPT) but no pinned corpus writes `.. _` or `.. <keyword>`, so no measured file can observe the difference. Kept because it is the identical guard pattern_binding_at applies on the ordinary path, where every keyword head in every pattern would otherwise bind.'
  }
)

# THE VERDICT TAIL, and its absence was a real defect in this file and in
# `mutate_0465.ps1`: both ended at the closing paren of the mutation list, so
# `Write-MutationGateVerdict` was never called and `exit` never ran. A MUST-RED MISS
# printed loudly and the process still returned 0 -- which is the same defect
# release.ps1 already fixed once ("a Stage that prints twelve lines returns an array of
# twelve things ... every stage would have reported ok while failing"), reintroduced in
# the mutation harness. 0466's first run is what exposed it: M3 was declared MustRed,
# the harness printed `MUST-RED MISS`, and the gate still exited 0.
Write-MutationGateVerdict -Name '0466'
if ($script:MutationGateFailures.Count -gt 0) { exit 1 }
exit 0
