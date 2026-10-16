# Mutation gate 0465 -- the `..` CHAIN LINK, and 0465b loops in expression position.
#
# WHAT THIS PINS. Two increments, and the second is only here because of the first.
#
# 0465 -- `recv..name(args)` had no production. The lexer emits TWO TDot tokens for a
# bare `..` (it has `..<` and `..<=` but no `..`), so `parse_postfix_from` bumped the
# first and handed the second to `expect_name`, which reported `expected field name` --
# a message naming neither the operator nor the receiver. 180 sites in 33 files of
# moonbitlang/async 0.22.4; async parsed 325 -> 331.
#
# 0465b -- `for` and `while` in EXPRESSION position had no `parse_atom` arm, so `for`
# fell through to the generic TName arm, became `EName("for")`, and the structural
# walk resolved a KEYWORD as a binding: `undefined name 'for'`, actionable, on code
# `moon check` compiles. `match` and `if` in the identical position already reported
# honestly, which is the control that makes it a two-keyword gap and not a general one.
# Reachable ONLY after 0465: the `..` chain in
# `moonbitlang/async 0.22.4 src/websocket/conn.mbt` stopped the parse 80 lines above
# line 486, so the finding had no path to be observed at all.
#
# THE GRAMMAR, settled in `_verify/settle_0465_dotdot_chain.ps1` (14 rows) rather than
# read off the symbol. The corpus cannot settle it -- all 180 sites chain methods that
# RETURN the receiver, so they are consistent with both readings:
#
#     S::new()..get().v   ACCEPT       <- `get` returns Int, and this is S.v
#     S::new().get().v    REJECT(4028) <- the `.` spelling of the same expression
#     ..two(1)            REJECT(4080) <- arity, so the arguments really bind
#     ..v                 REJECT(4015) <- the link must be callable
#     ..bump  (no parens) REJECT(4014) <- the parentheses are the grammar
#
# => 判据: `recv..name(args)` calls `name`, DISCARDS its result, and EVALUATES TO
# `recv`. M2 below is the mutation that implements the other reading, and it is the
# one this whole gate exists to kill.
#
# PATTERNS ARE PURE ASCII ON PURPOSE. Several of these sites carry em dashes in their
# comments, and a Find pattern containing one is read as ANSI by PowerShell 5.1 and
# silently matches nothing -- which a mutation harness reports as a failure to apply,
# not as a defect.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'mutate_lib.ps1')

$PARSER = 'src\parser\parser.mbt'
$WALK = 'src\walk\walk.mbt'
$TYPES = 'src\types\infer.mbt'
$INTERP = 'src\interp\interp.mbt'

Invoke-MutationGate -Name '0465' -Target 'js' -Mutations @(

  # M1 THE `..` ARM IS NEVER ENTERED. Widening its guard to a single TDot is the
  # mutation "there is no `..` branch": the single-dot branch below then consumes the
  # FIRST dot of every `..` and hands the second to expect_name, which is the
  # pre-0465 parser verbatim. It also makes the arm STEAL every ordinary `.name()`,
  # which is the direction that makes it observable.
  @{
    Name = 'M1 the `..` guard matches one TDot and steals single-dot chains'
    File = $PARSER
    Find = "    if self.at(TDot) && self.at_next(TDot) {`n      let csp = self.span()"
    Repl = "    if self.at(TDot) {`n      let csp = self.span()"
    MustRed = '0465: a single-dot chain is untouched by the `..` arm'
  }

  # M2 THE WRONG SEMANTICS, AND THE ONE THIS GATE EXISTS FOR. Producing an
  # `EMethodCall` implements the reading the symbol's shape suggests -- "`..` is a
  # spelling of `.`" -- and it is the reading the 180 corpus sites are consistent
  # with. It would parse all 33 files and type every chain in them by the METHOD's
  # return type when the language says the receiver's.
  #
  # Killed by the node-shape rows, not by an end-to-end finding: this lens has no
  # signature for a method, so the two readings are indistinguishable downstream.
  @{
    Name = 'M2 `..` builds an EMethodCall instead of an EDotDot'
    File = $PARSER
    Find = 'kind: @ast.EDotDot(e, m, args, labels), }'
    Repl = 'kind: @ast.EMethodCall(e, m, args, labels), }'
    MustRed = '0465: the corpus shape builds one EDotDot per `..` link'
  }

  # M3 THE ARGUMENT LIST IS DROPPED. This is the bug that shipped in the first draft:
  # `Parser::expect` bumps on success, an extra `bump()` consumed the FIRST argument,
  # and `moon check --deny-warn` stayed completely silent because a dropped argument
  # still yields a smaller, perfectly well-typed tree. The only control that catches
  # it is one that counts what the node carries.
  @{
    Name = 'M3 the `..` argument list is dropped'
    File = $PARSER
    Find = "      let (args, labels) = self.parse_call_args()`n      self.expect(TRParen, `"')'`")`n      e = { span: csp, kind: @ast.EDotDot(e, m, args, labels), }"
    Repl = "      let (args, labels) : (Array[@ast.Expr], Array[String]) = ([], [])`n      self.expect(TRParen, `"')'`")`n      e = { span: csp, kind: @ast.EDotDot(e, m, args, labels), }"
    MustRed = '0465: the first `..` argument is not dropped'
  }

  # M4 A MISSING `(` CASCADES. Without the guard the arm falls through to
  # parse_call_args at whatever token the cursor sits on, so one defect reports twice.
  # That is not cosmetic: the NOTPARSE message tally is what RANKS the remaining work,
  # so a cascade sends the next increment after a shape that does not exist.
  @{
    Name = 'M4 a missing "(" falls through and reports twice'
    File = $PARSER
    Find = "      if !self.at(TLParen) {`n        self.err(`"expected '(' after '..' method name`", self.span())`n        break`n      }`n"
    Repl = ''
    MustRed = "0465: a bare ``..name`` reports a ParseError naming the missing paren"
  }

  # M5 THE WALK DOES NOT READ THE ARGUMENTS. The structural lens stops counting a name
  # that is passed only to a `..` link, so a parameter read in exactly one place reads
  # as unused. This is the `ECatch`/`EComp` half-vanishing defect on a new node.
  @{
    Name = 'M5 walk does not read the `..` arguments'
    File = $WALK
    Find = "    EDotDot(base, _, args, _) => {`n      if !base.is_qualifier() {`n        self.walk_expr(base)`n      }`n      for a in args {`n        self.walk_expr(a)`n      }`n    }"
    Repl = "    EDotDot(base, _, _, _) => {`n      if !base.is_qualifier() {`n        self.walk_expr(base)`n      }`n    }"
    MustRed = '0465: a parameter read ONLY as a `..` argument, or ONLY as a receiver'
  }

  # M6 THE LOOP-EXPRESSION ARMS NEVER MATCH, and `for` becomes a name again.
  @{
    Name = 'M6 `for` and `while` in expression position report as undefined names'
    File = $PARSER
    Find = 'TName("for") | TName("while") =>'
    Repl = 'TName("forr") | TName("whilee") =>'
    MustRed = '0465b: `for` and `while` in expression position report honestly'
  }

  # M7 THE TYPE OF A `..` LINK IS UNKNOWN rather than the receiver's. DECLARED
  # SURVIVOR, and the proof is a property of the lens rather than of this suite: the
  # type lens has NO signature table for methods, which is exactly why `EMethodCall`
  # returns TUnknown. The only two candidates here are TUnknown and the receiver's
  # type, and TUnknown is the fail-safe that reports nothing, so no program in any
  # corpus can separate them. The claim that IS observable -- and is guarded -- is
  # structural: `..` is its own node, and M2 is what kills that.
  @{
    Name = 'M7 a `..` link types as unknown rather than as the receiver'
    File = $TYPES
    Find = "        let bt = self.ty_of(base, TUnknown)`n        for arg in args {`n          ignore(self.ty_of(arg, TUnknown))`n        }`n        bt"
    Repl = "        let bt = TUnknown`n        for arg in args {`n          ignore(self.ty_of(arg, TUnknown))`n        }`n        bt"
    Expect = 'SURVIVED'
    Prove = 'Unobservable by construction: the type lens holds no method signature table, which is why EMethodCall also returns TUnknown. The candidates are TUnknown and the receiver type; TUnknown is the fail-safe and reports nothing, so no program distinguishes them. The risk this guards against is the opposite one -- typing by the METHOD return type -- and that is unreachable here and killed by M2.'
  }

  # M8 THE VALUE OF A `..` LINK IS UNKNOWN rather than the receiver's. DECLARED
  # SURVIVOR for the same structural reason on the behavioral lens: AAny is the value
  # it already yields for a receiver it does not model, and a chain that yields AAny
  # cannot be shown to misbehave by a fixture. The settle is what makes the receiver
  # the right answer; it is not what makes it observable.
  @{
    Name = 'M8 a `..` link evaluates to unknown rather than to the receiver'
    File = $INTERP
    Find = 'out = self.eval(base, env)'
    Repl = 'out = AAny'
    Expect = 'SURVIVED'
    Prove = 'Unobservable by construction: the behavioral lens returns AAny for any receiver it does not model, and AAny is itself the fail-safe, so a chain yielding AAny produces no finding a fixture could catch. The settle (S::new()..get().v ACCEPT vs S::new().get().v REJECT 4028) is what makes the receiver the correct answer; no in-tree observation separates the two.'
  }
)
