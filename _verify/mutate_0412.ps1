# 0.4.12 mutation gate.
#
# CONVERTED to `_verify/mutate_lib.ps1`. The runner this file used to carry has
# three defects the harness does not have, all found by running it before touching
# it:
#
#   1. IT REPORTED SUCCESS FOR MUTATIONS IT NEVER APPLIED. M1, M2 and M5b print
#      "anchor text not found", are counted as neither a kill nor a failure, and
#      the gate still exits 0. Those anchors stopped matching when
#      `collect_declared_names` and `union` were refactored after 0.4.12, and the
#      old runner treated a stale guard as a passing guard. Under rule 3 a NO-OP is
#      a failure, so this gate as written would now FAIL loudly -- which is correct,
#      but it means the three have to be accounted for rather than tolerated.
#
#   2. IT JUDGED A KILL BY PROCESS EXIT CODE, with no `Total tests:` line and no
#      COMPILE-ERR distinction. A mutant that fails to BUILD and a mutant whose
#      tests all pass look identical through an exit code.
#
#   3. IT RESTORED BY MOVING A `.bakmut` FILE BACK. Nothing verified the bytes.
#      The harness restores from the bytes it read and proves it with SHA256.
#
# IT ALSO RAN SUBSETS, NOT THE SUITE. Each mutation carried a `--filter`
# (`collect_declared_names*`, `union*`, `dir_of*`) and judged only that slice. The
# filters are recorded below for the record; the harness runs the FULL suite, which
# is a superset -- a mutation that reddens its slice reddens the suite -- so this is
# a strictness increase, not a loss of coverage. The 0.4.13 release notes already
# record the failure this shape invites: a `--filter` glob that selects ZERO tests
# reports green for any mutation, because nothing ran.
#
# THE TARGET IS `wasm`, AND THAT IS LOAD-BEARING. The first conversion ran this
# gate on `js`, which reported M5a and M6 as SURVIVED. They are not survivors:
# both are guarded by tests in `src/sa`, and `moon.mod` says `src/sa` needs the
# async runtime, so on the js backend that package DEGRADES AND ITS TESTS DO NOT
# RUN. Changing the target silently deleted the guards and then reported the
# absence as a pass. This is the 0.4.27 lesson in a new costume: the change that
# mattered was not in the code under test, it was in the harness's flags.
#
# THE THREE RETIRED MUTATIONS are retired because the code they targeted has since
# changed shape. They are NOT re-anchored: inventing an anchor that happens to match
# would manufacture a fixture to make a count look right, which is the opposite of
# what a mutation gate is for. What they verified when live is recorded, so the
# 0.4.12 release notes remain the authoritative account of that release.
#
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File _verify/mutate_0412.ps1
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'mutate_lib.ps1')

$PARSER = 'src\parser\parser.mbt'
$CORE   = 'src\core\core.mbt'
$SA     = 'src\sa\main.mbt'

$mutations = @(
  # M1 -- live then. The depth clamp in the declared-name scanner: a declaration
  # keyword must not drive the brace depth below zero.
  @{
    Name = 'M1 depth clamp'
    File = $PARSER
    Retired = 'the brace-depth clamp in the declared-name scanner was refactored after 0.4.12; the anchor text no longer exists and no equivalent shape was identified'
    Find = "        if depth > 0 {`n          depth -= 1`n        }"
    Repl = "        depth -= 1"
  }

  # M2 -- live then. The depth==0 guard that decides whether a token DECLARES a
  # name. M1 and M2 were the pair that had to be mutated separately: M1 alone
  # reddens, M2 alone reddens, and M1+M2 together were the state that produced the
  # false positives 0.4.12 fixed.
  @{
    Name = 'M2 depth==0 guard'
    File = $PARSER
    Retired = 'the depth==0 declaration guard was refactored after 0.4.12; the anchor text no longer exists'
    Find = 'if depth == 0 && (declares_value(kw) || declares_type(kw)) {'
    Repl = 'if declares_value(kw) || declares_type(kw) {'
  }

  # M3 -- the name-immediacy rule: only a token AT `i` may declare a name.
  # Loosening it to a scan was the regression this guard pins.
  #
  # DECLARED COMPILE-ERR, AND THAT IS NOT A PASS. The ANCHOR still matches, but the
  # REPLACEMENT was written against the 0.4.12 source shape: it opens a `while` and a
  # `match` where the current source closes neither, so the mutant does not build.
  # The old runner scored this "RED (killed)" on exit code alone and reported the
  # name-immediacy guard as verified. It was never verified by this mutation -- there
  # was no test run at all. So the honest verdict is COMPILE-ERR, and the honest
  # consequence is that the guard is currently UNCOVERED by mutation. Writing a fresh
  # replacement that happens to compile would manufacture a fixture to make the
  # count look right; the coverage gap is the finding, and it is recorded instead.
  @{
    Name = 'M3 name immediacy'
    File = $PARSER
    Expect = 'COMPILE-ERR'
    Prove = 'anchor matches, replacement does not build against current source; the name-immediacy guard is therefore NOT mutation-verified today'
    Find = "  match toks[i] {`n    TName(n) => {"
    Repl = "  let mut j = i`n  while j < toks.length() {`n    match toks[j] {`n      TName(n) => {"
  }

  # M4 -- the `::` fold: a declared name is `Type::name`, not just the head.
  @{
    Name = 'M4 :: fold'
    File = $PARSER
    Find = '(TColon, TColon, TName(m)) => return Some(n + "::" + m)'
    Repl = '(TColon, TColon, TName(m)) => return Some(n)'
  }

  # M5a/M5b -- `IfaceSymTab::union` must accumulate into the NEW table. Both
  # halves are separate mutations: dropping the types half and dropping the values
  # half fail in different files, and a gate that merged them would pass with
  # either one broken.
  @{
    Name = 'M5a union leaks types'
    File = $CORE
    Find = "  for k, _ in other.types {`n    if !out.types.contains(k) {`n      out.types.set(k, true)`n    }`n  }"
    Repl = "  for k, _ in other.types {`n    if !self.types.contains(k) {`n      self.types.set(k, true)`n    }`n  }"
  }
  @{
    Name = 'M5b union leaks values'
    File = $CORE
    Retired = 'the values half of IfaceSymTab::union was refactored after 0.4.12; the anchor text no longer exists. M5a above still pins the types half'
    Find = "  for k, _ in other.values {`n    if !out.values.contains(k) {`n      out.values.set(k, true)`n    }`n  }"
    Repl = "  for k, _ in other.values {`n    if !self.values.contains(k) {`n      self.values.set(k, true)`n    }`n  }"
  }

  # M6 -- `dir_of` accepts a separator; dropping the backslash half breaks the
  # Windows form of every path the tool is handed.
  @{
    Name = 'M6 dir_of backslash'
    File = $SA
    Find = "    if chars[i] == '/' || chars[i] == '\\' {"
    Repl = "    if chars[i] == '/' {"
  }
)

Invoke-MutationGate -Name '0.4.12' -Target 'wasm' -Mutations $mutations
Write-MutationGateVerdict -Name '0.4.12 mutation gate'
if ($script:MutationGateFailures.Count -gt 0) { exit 1 }
exit 0