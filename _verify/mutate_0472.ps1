# Mutation gate 0472 -- the C-style `for`'s initializer LIST, and a `continue` that carries
# VALUES.
#
# WHAT THIS PINS. Two gaps, both measured as per-FILE first blockers on the tree at 0471.
#
#   THE HEADER. `c_for_init` read exactly ONE initializer and `parse_c_for` pushed one
#   statement, so a comma-separated list stopped the parse:
#
#       async/src/websocket/utils.mbt:49     for i = 0, remaining = remaining; i < data.length(); {
#       async/src/internal/gzip_internal/crc32.mbt:53     for crc = current, i = 0; i + 8 <= len; {
#       async/src/socket/addr_utils.mbt:262   for i = 0, zero_group_start = 0; i < 8; i = i + 1 {
#
#   THE VALUE. `continue` bumped the keyword and returned, leaving its values unread -- and
#   `walk.mbt` and `infer.mbt` both treat `SContinue` as a no-op, so the names in
#   `continue p, r, c, vr` were read by NOTHING and were reported unused. Two of the three
#   header files then stopped on that line:
#
#       async/src/socket/addr_utils.mbt:267               continue i + 1, i + 1
#       async/src/internal/gzip_internal/crc32.mbt:63    continue crc, i + 8
#
# The grammar is settled in `_verify/settle_0472_for_init_list.ps1`: 10 rows, 2 controls,
# 8 claims.
#
# REACH, measured on the tree at 0471: async parsed 390 -> 392, `unreliable` 285 -> 264,
# `notices` 1686 -> 1690, `actionable` 0 throughout. labeler, proton, moui and contract are
# BYTE-IDENTICAL. moonbit_image moved ONE number and it is worth being exact about why,
# because it looked like a regression and was not:
#
#   image `unreliable` 23 -> 15, `total` 230 -> 222, `notices` 207 UNCHANGED, `actionable` 0.
#
# `unreliable` is defined in `src/sa/main.mbt` as the findings at or after a file's FIRST
# READ FAILURE -- "derived from an already-wrong tree, so reported only as a count, never as
# results". bmp.mbt's failure is line 117, a multi-line C-style header, and reading
# `continue a, b` correctly changes the ALREADY-WRONG tree past that line. Verified on a
# derived copy of bmp.mbt with the header repaired, so the whole file parses and every
# finding is shown: `notices` 14 vs 14, every shown finding byte-identical, and only the
# suppressed remainder changed (14 -> 6). No evidence-bearing number moved anywhere.
#
# => 判据: the values are READ and NOT ASSIGNED, and M5 is the mutation that says so.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'mutate_lib.ps1')

$PARSER = 'src\parser\parser.mbt'
$WALK = 'src\walk\walk.mbt'

Invoke-MutationGate -Name '0472' -Target 'wasm' -Mutations @(

  # M1 THE LIST READER IS GONE, which is the header defect restored.
  @{
    Name = 'M1 the initializer list is read as a single initializer again'
    File = $PARSER
    Find = "    for d in self.c_for_inits(sp) {`n      stmts.push(d)`n    }"
    Repl = '    stmts.push(self.c_for_init(sp))'
    MustRed = '0472: a comma-separated initializer list binds every name'
  }

  # M2 THE LIST LOOP STOPS AFTER ONE ENTRY. M1 removes the call and this keeps the call while
  # making the loop vacuous -- the two ways the same header can fail, and only one of them is
  # reachable by "put the old line back".
  @{
    Name = 'M2 the list reader stops after the first initializer'
    File = $PARSER
    Find = "  while self.at(TComma) {`n    let _ = self.bump()`n    self.skip_seps()`n    out.push(self.c_for_init(sp))`n  }"
    Repl = '  let _ = 0'
    MustRed = '0472: a three-element initializer list parses'
  }

  # M3 `continue` DOES NOT READ ITS VALUES -- the original defect, restored literally. This is
  # also the variant that leaves the names unread, which is what made the image corpus's
  # finding count move: it is a REGRESSION in both directions at once.
  #
  # RE-ANCHORED 0495. The `bare` guard this mutation names is now CARRIED BY BOTH
  # TERMINATORS: the `break` arm and the `continue` arm each compute it, and the two
  # blocks are byte-identical up to the node they return. An anchor that stops at the
  # closing brace is therefore satisfied TWICE, and the harness mutates the FIRST
  # occurrence -- which is the `break` arm, so the gate would have reported a kill for a
  # mutation it never made. The anchor now runs on to the `SContinue([])` return, which
  # is what makes it the `continue` arm and not the `break` one.
  @{
    Name = 'M3 continue does not read its values'
    File = $PARSER
    Find = "    let bare = match self.peek() {`n      TNewline | TSemi | TRBrace | TLBrace | TEOF => true`n      _ => false`n    }`n    if bare {`n      return { span: sp, kind: @ast.SContinue([]), }`n    }"
    Repl = "    let bare = match self.peek() {`n      _ => true`n    }`n    if bare {`n      return { span: sp, kind: @ast.SContinue([]), }`n    }"
    MustRed = '0472: a continue with values reads them'
  }

  # M4 THE GUARD IS INVERTED -- a bare `continue` now reads whatever follows it. This is the
  # dangerous direction and the one the corpus cannot see: a bare `continue` on its own line
  # would take the NEXT STATEMENT as its value and swallow the rest of the body. The file
  # would still parse and `parsed` would still go UP, so only a probe placed after the
  # continue can tell. The first draft of this arm had exactly this bug.
  #
  # RE-ANCHORED 0495, same reason as M3: the one-line guard is now shared by the `break`
  # arm and the `continue` arm, so the anchor runs on through the `SContinue([])` return
  # and the following `let vals` line to be unique.
  @{
    Name = 'M4 the bare-continue guard is inverted, so the next statement is swallowed'
    File = $PARSER
    Find = "    let bare = match self.peek() {`n      TNewline | TSemi | TRBrace | TLBrace | TEOF => true`n      _ => false`n    }`n    if bare {`n      return { span: sp, kind: @ast.SContinue([]), }`n    }`n    let vals : Array[@ast.Expr] = []"
    Repl = "    let bare = match self.peek() {`n      TEOF => true`n      _ => false`n    }`n    if bare {`n      return { span: sp, kind: @ast.SContinue([]), }`n    }`n    let vals : Array[@ast.Expr] = []"
    MustRed = '0472: a name after a bare continue is still reported undefined'
  }

  # M5 THE VALUES ARE READ AND THEN ASSIGNED TO INVENTED TARGETS -- the fabrication this
  # increment deliberately does NOT do. There are no loop-variable names here, so the closest
  # honest version of the wrong behaviour is to treat every value as an assignment to a fixed
  # name, which the type lens then checks against a binding that may not exist. The row it
  # must redden is the UnusedLocal one, because reading a name is not the same as evaluating
  # it in a position where nothing consumes it.
  #
  # RETIRED at 0495, AND THE REASON IS A MEASUREMENT, NOT A SCHEDULE.
  #
  # The mutation wrote `SExpr(v)` -> `SAssign(EName("zz_never_bound"), v)` into the
  # list of carried values. 0495 changed that list's ELEMENT TYPE: the carried
  # values are now the TERMINATOR'S OWN PAYLOAD, `SContinue(Array[Expr])`, where
  # before they were SIBLING STATEMENTS in an `SBlock`. `SAssign` is a `Stmt`
  # kind and `SExpr` was a `Stmt` kind; `Expr` has no assignment constructor at
  # all. So the mutation is no longer EXPRESSIBLE -- not moved, not renamed:
  # `moon` rejects it with
  #
  #     Constr Type Mismatch(constructor SAssign)
  #       has type : @riantr/moonbit_static_analysis/src/ast.SKind
  #       wanted   : @riantr/moonbit_static_analysis/src/ast.EKind
  #
  # which is the COMPILE-ERR verdict, and a COMPILE-ERR is not a kill. Measured:
  # the mutation applied cleanly to the 0495 source and the suite did not build.
  #
  # WHAT IS LEFT OF THE CLAIM. "THE VALUES ARE READ AND NOT ASSIGNED" had two
  # halves. The "NOT ASSIGNED" half is now enforced BY THE TYPE -- an assignment
  # cannot be put in an `Array[Expr]` -- so there is no line of code left to
  # mutate, and the claim is stronger than it was rather than weaker. The "READ"
  # half is enforced by `walk.mbt` and `infer.mbt`, and M6 below pins it.
  @{
    Name = 'M5 continue values are read as assignments rather than evaluations'
    File = $PARSER
    Find = '      vals.push({ span: v.span, kind: @ast.SExpr(v), })'
    Repl = '      vals.push({ span: v.span, kind: @ast.SAssign({ span: v.span, kind: @ast.EName("zz_never_bound"), }, v), })'
    Retired = 'the carried values are the terminator''s own payload now -- Array[Expr] -- and an assignment is a Stmt kind, so this mutation is not expressible: moon rejects it with Constr Type Mismatch (SKind vs EKind), which is COMPILE-ERR and not a kill. The "not assigned" half of the claim is now enforced by the type; the "read" half is pinned by M6.'
  }

  # M6 THE VALUES ARE NOT READ BY THE WALK -- the other half of the same claim.
  #
  # `walk.mbt` and `infer.mbt` both treat `SContinue` as a no-op before 0472, so
  # the names in `continue p, r, c, vr` were read by NOTHING and were reported
  # unused. The `UnusedLocal` verdict is decided in `walk.mbt`'s `audit_frame`
  # (`e.varuses == 0`), so a walk that does not walk the carried values leaves
  # their names unread and the verdict comes back -- which is exactly the
  # original defect, restored.
  #
  # This is the row that carries the claim M5 used to carry, at the site the
  # claim now lives on. M5 is RETIRED because an assignment cannot be put in an
  # `Array[Expr]`; M6 is here because a READ still has to be made somewhere, and
  # this is where it is made.
  @{
    Name = 'M6 the walk does not read the values a continue carries'
    File = $WALK
    Find = @'
    SContinue(vals) =>
      for v in vals {
        self.walk_expr(v)
      }
'@.Replace("`r`n", "`n")
    Repl = @'
    SContinue(_) => ()
'@.Replace("`r`n", "`n")
    MustRed = '0472: a name used only in a continue''s values is not reported unused'
  }
)

Write-MutationGateVerdict -Name '0472'
if ($script:MutationGateFailures.Count -gt 0) { exit 1 }
exit 0
