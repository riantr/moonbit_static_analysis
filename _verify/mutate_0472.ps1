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
  @{
    Name = 'M3 continue does not read its values'
    File = $PARSER
    Find = "    let bare = match self.peek() {`n      TNewline | TSemi | TRBrace | TLBrace | TEOF => true`n      _ => false`n    }"
    Repl = "    let bare = match self.peek() {`n      _ => true`n    }"
    MustRed = '0472: a continue with values reads them'
  }

  # M4 THE GUARD IS INVERTED -- a bare `continue` now reads whatever follows it. This is the
  # dangerous direction and the one the corpus cannot see: a bare `continue` on its own line
  # would take the NEXT STATEMENT as its value and swallow the rest of the body. The file
  # would still parse and `parsed` would still go UP, so only a probe placed after the
  # continue can tell. The first draft of this arm had exactly this bug.
  @{
    Name = 'M4 the bare-continue guard is inverted, so the next statement is swallowed'
    File = $PARSER
    Find = "      TNewline | TSemi | TRBrace | TLBrace | TEOF => true"
    Repl = "      TEOF => true"
    MustRed = '0472: a name after a bare continue is still reported undefined'
  }

  # M5 THE VALUES ARE READ AND THEN ASSIGNED TO INVENTED TARGETS -- the fabrication this
  # increment deliberately does NOT do. There are no loop-variable names here, so the closest
  # honest version of the wrong behaviour is to treat every value as an assignment to a fixed
  # name, which the type lens then checks against a binding that may not exist. The row it
  # must redden is the UnusedLocal one, because reading a name is not the same as evaluating
  # it in a position where nothing consumes it.
  @{
    Name = 'M5 continue values are read as assignments rather than evaluations'
    File = $PARSER
    Find = '      vals.push({ span: v.span, kind: @ast.SExpr(v), })'
    Repl = '      vals.push({ span: v.span, kind: @ast.SAssign({ span: v.span, kind: @ast.EName("zz_never_bound"), }, v), })'
    MustRed = '0472: a name used only in a continue''s values is not reported unused'
  }
)

Write-MutationGateVerdict -Name '0472'
if ($script:MutationGateFailures.Count -gt 0) { exit 1 }
exit 0
