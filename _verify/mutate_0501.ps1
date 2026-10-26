# Mutation gate 0501 -- THE FRAME AUDIT, PER BINDING INSTEAD OF PER FUNCTION.
#
# WHAT THIS INCREMENT IS. `Walker::audit_suppressed` was a single Bool over a
# function's extent: ONE region the frontend did not analyse anywhere in the
# function switched off EVERY conclusion the frame could support. So a `match`
# at the end of a function took the unused-local verdict away from a binding
# declared at the top of it -- a binding the unread region cannot have read,
# because the region comes LATER.
#
# 0501 replaced the Bool with the LIST of regions, and the frame audit now
# judges each binding against the regions that can reach it:
#
#   a region can reach a binding only if the region ENDS after the binding was
#   declared, because a region that has already ended cannot have read a
#   binding that did not exist yet.
#
# EVERY MUTATION BELOW NAMES THE TEST THAT MUST GO RED. A mutation that kills
# some other test is not evidence: the test named here is the one that pins the
# rule, so the kill is the rule's own.
#
# THE MEASUREMENT THIS GATE EXISTS UNDER, because a rule nobody has measured is
# a guess. With the suppression switched OFF, the tool produces 836 UnusedLocal
# and 1906 UnusedParam findings across the seven pinned corpora and this
# repository's own source that it does not produce with it ON. The narrowing
# recovers NONE of them on today's corpora -- every one of those bindings is
# declared BEFORE its region, so the region could still have read it. What the
# narrowing buys is that the regions are now judged ONE BINDING AT A TIME, so
# that removing a region -- which is what analysing `match` does -- restores
# the verdicts for the bindings the OTHER regions cannot reach.
#
# ANCHORS ARE WRITTEN AGAINST THE POST-`moon fmt` SOURCE, and every one of them
# is UNIQUE in its file -- the harness mutates the FIRST match, and a second
# copy would never be verified.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'mutate_lib.ps1')

$WALK = 'src\walk\walk.mbt'

Invoke-MutationGate -Name '0501' -Target 'wasm' -Mutations @(

  # M1 THE THRESHOLD IS INVERTED. A region now reaches the bindings it cannot
  # possibly have read, and spares the ones it could. The binding declared
  # AFTER the region stops being judged -- which is the whole behaviour 0501
  # adds, and the test that says so goes red.
  @{
    Name = 'M1 the threshold is inverted'
    File = $WALK
    Find = @'
fn hole_can_reach(e : Entry, holes : Array[@core.Span]) -> Bool {
  for h in holes {
    if e.decl_span.start.line <= h.end.line {
      return true
    }
  }
  false
}
'@.Replace("`r`n", "`n")
    Repl = @'
fn hole_can_reach(e : Entry, holes : Array[@core.Span]) -> Bool {
  for h in holes {
    if e.decl_span.start.line > h.end.line {
      return true
    }
  }
  false
}
'@.Replace("`r`n", "`n")
    MustRed = 'a local declared after a match is reported unused'
  }

  # M2 THE REGION'S LIST COMES BACK EMPTY. No region can reach anything, so
  # every binding is judged -- including the ones read ONLY inside the unread
  # region, which is the false positive the suppression exists to avoid. The
  # test that says that binding must NOT be reported goes red.
  @{
    Name = 'M2 the region list comes back empty'
    File = $WALK
    Find = @'
fn Walker::holes_in(self : Walker, sp : @core.Span) -> Array[@core.Span] {
  let out : Array[@core.Span] = []
'@.Replace("`r`n", "`n")
    Repl = @'
fn Walker::holes_in(self : Walker, sp : @core.Span) -> Array[@core.Span] {
  let out : Array[@core.Span] = []
  return out
'@.Replace("`r`n", "`n")
    MustRed = 'a local read only inside a match is not reported unused'
  }

  # M3 THE PARAMETER GUARD IS DROPPED. A parameter is in scope for the WHOLE
  # body, so any region in the function can read it -- and the narrowing must
  # not reach parameters. With the guard gone, the parameter in a function with
  # a region is reported unused, which is a false positive on correct code.
  @{
    Name = 'M3 the parameter guard is dropped'
    File = $WALK
    Find = @'
        if e.param {
          if holes.length() == 0 {
'@.Replace("`r`n", "`n")
    Repl = @'
        if e.param {
          if true {
'@.Replace("`r`n", "`n")
    MustRed = 'a parameter in a function with a match is not reported'
  }

  # M4 THE FUNCTION'S EXTENT IS NOT CHECKED. Every unread region in the FILE
  # now reaches every binding in every function, so a region in the SECOND
  # function silences a binding in the FIRST -- which it cannot have read. This
  # is the blanket again, reached by a different road: the regions are no
  # longer sorted into the function they belong to.
  #
  # 0506 MOVED THE ANCHOR, AND THE MOVE IS THE POINT. The rule itself was the
  # comparison, inline here; 0506 lifted it into `span_in_extent` so that the
  # notice classification could ask the SAME question of all the functions at
  # once. This row still mutates the CALL, in `holes_in`, because that is where
  # the mutation's meaning lives: the regions are no longer sorted into the
  # function they belong to. Mutating the shared rule instead would also have
  # switched off the 0506 classification, so the row would have been testing
  # two mechanisms at once -- and `mutate_0506`'s M1 and M2 already mutate that
  # rule, from the rule's own side.
  @{
    Name = 'M4 the function''s extent is not checked'
    File = $WALK
    Find = @'
    if span_in_extent(t, sp) {
      out.push(t)
    }
'@.Replace("`r`n", "`n")
    Repl = @'
    if true {
      out.push(t)
    }
'@.Replace("`r`n", "`n")
    MustRed = 'a region in another function does not silence this function'
  }
)
