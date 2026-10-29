# Mutation gate 0506 -- THE NOTICE FLOOD.
#
# WHAT THIS INCREMENT IS. The analyzer renders a notice for every construct it
# reads past, and on the pinned core corpus that was 10,096 notices: the OLD
# rendering -- the per-file cap as it ships -- was 9,128 lines of output to say
# 28 things, and with the cap lifted, so that every notice is on a line of its
# own, it is 11,223. 0506 prints only the notices that
# can HIDE a finding and counts the rest by shape, and `--show-notices`
# restores the whole per-line list.
#
# THE CLASSIFICATION IS A POSITION AND NOT A WORDING, and that is the whole
# content of the increment. The same "if expression is outside the analyzed
# subset" notice is printed when it sits inside a function and aggregated when
# it sits at module top level, because only the first is in a function's hole
# list. So the rule is the analyzer's OWN EXTENTS:
#
#     a region INSIDE some function's extent  -> it can hide a finding
#     a region OUTSIDE every function's extent -> it hides nothing
#
# The geometry lives in `src/walk` (`span_in_extent`, `hiding_spans`), and the
# consequence lives in `src/sa` (`is_hiding`, `split_findings`,
# `partition_findings`, `count_by_shape`, `notice_lines`).
#
# SIXTEEN RULES, AND EVERY MUTATION BELOW NAMES THE TEST THAT MUST GO RED:
#
#   M1, M2    the region must START inside the extent, and the extent's last
#             line is inside it
#   M3        a region inside two functions is ONE hiding region
#   M4        the extent contains the region, not the other way round
#   M5        a region in no function at all hides nothing
#   M6        the membership test compares the REGION, not the line
#   M7        a notice inside a function is printed
#   M8        the two classes are not swapped
#   M9        a defect is never aggregated
#   M10       the shapes are sorted, biggest first
#   M11       the shape is the whole message
#   M12       `--show-notices` prints every notice
#   M13       the table is not printed twice
#   M14       the TOTAL line carries the tree's notice count
#   M15       a row carries its shape's count
#   M16       the CLI spells the flag the way the settle calls it
#
# ANCHORS ARE WRITTEN AGAINST THE POST-`moon fmt` SOURCE and every one of them
# is UNIQUE in its file -- the harness mutates the FIRST match, and a second
# copy would never be verified.
#
# THE TARGET IS `wasm`, and it has to be: the `src/sa` and `src/walk` tests do
# not run on the `js` and `wasm-gc` targets (MEASURED: js 1184 tests, wasm-gc
# 1184, wasm 1286 -- the 102-test difference is the async packages), so a gate
# run on `js` would report SURVIVED for every mutation in this file.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'mutate_lib.ps1')

$WALK = 'src\walk\walk.mbt'
$SA   = 'src\sa\main.mbt'
$MAIN = 'main.mbt'

Invoke-MutationGate -Name '0506' -Target 'wasm' -Mutations @(

  # M1 THE REGION MUST START INSIDE THE EXTENT. Dropping the upper bound
  # makes every region after the function a hiding region, and the corpus's
  # own top-level `let d = if ...` shapes are exactly that case.
  @{
    Name = 'M1 the region''s upper bound is dropped'
    File = $WALK
    Find = @'
pub fn span_in_extent(inner : @core.Span, extent : @core.Span) -> Bool {
  inner.start.line >= extent.start.line && inner.start.line <= extent.end.line
}
'@.Replace("`r`n", "`n")
    Repl = @'
pub fn span_in_extent(inner : @core.Span, extent : @core.Span) -> Bool {
  inner.start.line >= extent.start.line
}
'@.Replace("`r`n", "`n")
    MustRed = '0506: a region that starts before or after the function is not in it'
  }

  # M2 THE EXTENT'S LAST LINE IS INSIDE IT. The extent runs from the header
  # to the closing brace, and a region that starts on the closing brace's
  # line is still in the function.
  @{
    Name = 'M2 the extent''s last line is not inside it'
    File = $WALK
    Find = @'
pub fn span_in_extent(inner : @core.Span, extent : @core.Span) -> Bool {
  inner.start.line >= extent.start.line && inner.start.line <= extent.end.line
}
'@.Replace("`r`n", "`n")
    Repl = @'
pub fn span_in_extent(inner : @core.Span, extent : @core.Span) -> Bool {
  inner.start.line >= extent.start.line && inner.start.line < extent.end.line
}
'@.Replace("`r`n", "`n")
    MustRed = '0506: a region on the function''s first line and on its last line is in it'
  }

  # M3 A REGION INSIDE TWO FUNCTIONS IS ONE HIDING REGION. A local function
  # lies inside its enclosing top-level one, so a region inside the local
  # function is inside both -- and it is still ONE region, not two. Dropping
  # the `break` counts it twice, and the count of hiding regions is what the
  # renderer decides on.
  @{
    Name = 'M3 a region inside two functions is counted twice'
    File = $WALK
    Find = @'
    for f in fns {
      if span_in_extent(t, f.span) {
        out.push(t)
        break
      }
    }
'@.Replace("`r`n", "`n")
    Repl = @'
    for f in fns {
      if span_in_extent(t, f.span) {
        out.push(t)
      }
    }
'@.Replace("`r`n", "`n")
    MustRed = '0506: a region inside a local function is inside the enclosing one too'
  }

  # M4 THE EXTENT CONTAINS THE REGION. The question is "is the region inside
  # the function", not "is the function inside the region" -- and the two
  # differ for every region that is not the same size as its function.
  @{
    Name = 'M4 the question is asked backwards'
    File = $WALK
    Find = @'
      if span_in_extent(t, f.span) {
'@.Replace("`r`n", "`n")
    Repl = @'
      if span_in_extent(f.span, t) {
'@.Replace("`r`n", "`n")
    MustRed = '0506: hiding_spans keeps the regions inside a function''s extent'
  }

  # M5 A REGION IN NO FUNCTION AT ALL HIDES NOTHING. This is 88.7% of the
  # corpus's notices: the `test` blocks, the top-level declarations, the
  # module-level expressions. A region that is in no function's hole list
  # cannot switch any frame audit off.
  @{
    Name = 'M5 every region is a hiding region'
    File = $WALK
    Find = @'
  for t in unread {
    for f in fns {
      if span_in_extent(t, f.span) {
        out.push(t)
        break
      }
    }
  }
'@.Replace("`r`n", "`n")
    Repl = @'
  for t in unread {
    out.push(t)
  }
'@.Replace("`r`n", "`n")
    MustRed = '0506: a region outside every function''s extent hides nothing'
  }

  # M6 THE MEMBERSHIP TEST COMPARES THE REGION, NOT THE LINE. A region's
  # identity is where it is, and two exclusions on the same line are two
  # DIFFERENT regions. A test that compared line numbers would put both of
  # them in the same set, and it would be wrong about one of them.
  @{
    Name = 'M6 the membership test compares the line, not the region'
    File = $SA
    Find = @'
  for h in hiding {
    if h == sp {
      return true
    }
  }
'@.Replace("`r`n", "`n")
    Repl = @'
  for h in hiding {
    if h.start.line == sp.start.line {
      return true
    }
  }
'@.Replace("`r`n", "`n")
    MustRed = '0506: two exclusions on the same line are two different regions'
  }

  # M7 A NOTICE INSIDE A FUNCTION IS PRINTED. The half of the rule that
  # keeps the notices that can hide a finding on the reader's screen.
  @{
    Name = 'M7 a notice inside a function is not printed'
    File = $SA
    Find = @'
    } else if is_hiding(r.span, hiding) {
'@.Replace("`r`n", "`n")
    Repl = @'
    } else if is_hiding(r.span, []) {
'@.Replace("`r`n", "`n")
    MustRed = '0506: a notice inside a function''s extent is printed per line'
  }

  # M8 AND THE OTHER HALF: the two classes are not swapped. A rule that
  # printed the notices that hide nothing and counted the ones that can hide
  # something would still add up to the right total, and it would be exactly
  # backwards.
  @{
    Name = 'M8 the two classes are swapped'
    File = $SA
    Find = @'
    } else if is_hiding(r.span, hiding) {
'@.Replace("`r`n", "`n")
    Repl = @'
    } else if !is_hiding(r.span, hiding) {
'@.Replace("`r`n", "`n")
    MustRed = '0506: a notice inside a function''s extent is printed per line'
  }

  # M9 A DEFECT IS NEVER AGGREGATED. The aggregation is about notices. A
  # defect is the one thing the reader came for, and dropping one would hide
  # the very finding the tool exists to report.
  #
  # 0508 RE-ANCHORED THIS ONE. The branch used to read `!r.is_notice()`, and
  # the demotion changed what that branch means: `is_notice` is now the answer
  # to two questions, and a low-confidence finding -- which is NOT a defect --
  # would have been aggregated with the scope limits. The branch now asks the
  # scope-limit question, and this mutation is still the same defect: the
  # defect is aggregated.
  @{
    Name = 'M9 a defect is aggregated'
    File = $SA
    Find = @'
    if !r.is_declared_scope_limit() {
      printed.push(r)
    } else if is_hiding(r.span, hiding) {
'@.Replace("`r`n", "`n")
    Repl = @'
    if !r.is_declared_scope_limit() {
      aggregated.push(r)
    } else if is_hiding(r.span, hiding) {
'@.Replace("`r`n", "`n")
    MustRed = '0506: a defect is printed, never aggregated'
  }

  # M10 THE SHAPES ARE SORTED, BIGGEST FIRST. The reader's eye goes to the
  # shape that accounts for the most, and a breakdown in the wrong order is
  # a breakdown that has to be re-read.
  @{
    Name = 'M10 the shapes are sorted, smallest first'
    File = $SA
    Find = @'
    if a.1 != b.1 {
      b.1 - a.1
    } else {
      0
    }
'@.Replace("`r`n", "`n")
    Repl = @'
    if a.1 != b.1 {
      a.1 - b.1
    } else {
      0
    }
'@.Replace("`r`n", "`n")
    MustRed = '0506: the aggregate is sorted, biggest first'
  }

  # M11 THE SHAPE IS THE WHOLE MESSAGE. The message is what says which
  # construct was not read, so a breakdown that lost it would not tell the
  # reader what the analyzer skipped.
  @{
    Name = 'M11 the shape is dropped'
    File = $SA
    Find = @'
    counts.set(r.message, c)
'@.Replace("`r`n", "`n")
    Repl = @'
    counts.set("", c)
'@.Replace("`r`n", "`n")
    MustRed = '0506: the aggregate counts by shape'
  }

  # M12 `--show-notices` PRINTS EVERY NOTICE. The flag exists so that the
  # complete per-line list stays reachable -- every measurement that reads it
  # needs it, and a reader looking for a specific construct wants it.
  @{
    Name = 'M12 --show-notices does not print every notice'
    File = $SA
    Find = @'
  if show_notices {
    (findings, [])
  } else {
    split_findings(findings, hiding)
  }
'@.Replace("`r`n", "`n")
    Repl = @'
  if !show_notices {
    (findings, [])
  } else {
    split_findings(findings, hiding)
  }
'@.Replace("`r`n", "`n")
    MustRed = '0506: --show-notices prints every notice and aggregates nothing'
  }

  # M13 THE TABLE IS NOT PRINTED TWICE. With `--show-notices` every notice
  # is already on a line of its own, and the table would be a second count of
  # the same facts.
  @{
    Name = 'M13 the table is printed twice'
    File = $SA
    Find = @'
  if show_notices || total <= 0 {
'@.Replace("`r`n", "`n")
    Repl = @'
  if total <= 0 {
'@.Replace("`r`n", "`n")
    MustRed = '0506: --show-notices prints no table'
  }

  # M14 THE TOTAL LINE CARRIES THE TREE'S NOTICE COUNT. It is the line that
  # reconciles the two halves against the SUMMARY, and a TOTAL line that
  # carried the aggregated count would reconcile against nothing.
  @{
    Name = 'M14 the TOTAL line carries the aggregated count'
    File = $SA
    Find = @'
notices=\{total}\tprinted=\{printed}\taggregated=
'@.Replace("`r`n", "`n")
    Repl = @'
notices=\{aggregated.length()}\tprinted=\{printed}\taggregated=
'@.Replace("`r`n", "`n")
    MustRed = '0506: the NOTICES table''s TOTAL line reconciles'
  }

  # M15 A ROW CARRIES ITS SHAPE'S COUNT. The rows are `key=value` so that a
  # gate can parse them without knowing the shape names, and the counts have
  # to be the shape's own.
  @{
    Name = 'M15 a row carries the total instead of the shape''s count'
    File = $SA
    Find = @'
    out.push("NOTICES\tcount=\{c}\t\{msg}")
'@.Replace("`r`n", "`n")
    Repl = @'
    out.push("NOTICES\tcount=\{total}\t\{msg}")
'@.Replace("`r`n", "`n")
    MustRed = '0506: the NOTICES table''s rows add up to the aggregated count'
  }

  # M16 THE CLI SPELLS THE FLAG THE WAY THE SETTLE CALLS IT.
  #
  # This is a DECLARED SURVIVOR, and the argument travels with the result.
  # The root package has no test file -- `moon test` builds it but runs no
  # test in it -- so the suite cannot see the CLI's plumbing at all, and
  # every mutation of that plumbing would come out SURVIVED whether it broke
  # anything or not. That is rule 5's case exactly: the honest verdict is
  # "this rule is not observable here", and the place it IS observable is
  # `_verify/settle_0506_notice_flood.ps1`, whose row N5 scans a fixture with
  # `--show-notices` and asserts that BOTH notices are printed -- and that
  # settle is a stage of the release gate.
  @{
    Name = 'M16 the CLI spells the flag differently'
    File = $MAIN
    Find = @'
    } else if a == "--show-notices" {
'@.Replace("`r`n", "`n")
    Repl = @'
    } else if a == "--show-notices-x" {
'@.Replace("`r`n", "`n")
    Expect = 'SURVIVED'
    Prove = 'the root package has no test file, so `moon test` cannot observe the CLI''s plumbing. The rule is pinned by _verify\settle_0506_notice_flood.ps1 row N5, which scans a fixture with `--show-notices` and asserts that both notices are printed; that settle is a release-gate stage.'
  }
)

Write-MutationGateVerdict -Name '0506'
if ($script:MutationGateFailures.Count -gt 0) { exit 1 }
exit 0
