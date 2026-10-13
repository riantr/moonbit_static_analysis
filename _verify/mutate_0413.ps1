# 0.4.13 mutation gate.
#
# CONVERTED to `_verify/mutate_lib.ps1`. This one is already a better generation than
# 0.4.12's: it captures `ran`, how many tests the `--filter` actually selected, and
# scores a mutation `INVALID (ran 0 tests)` when it selected none. That was the
# 0.4.13 fix for the shape 0.4.12 still has -- a filter glob matching zero test names
# reports green for any mutation, because nothing ran. The fix is preserved here in
# a stronger form: the harness runs the FULL suite, so "selected nothing" is not
# expressible.
#
# Running it BEFORE the conversion still found two things:
#
#   1. N4's ANCHOR HAS ROTTED. `let mut n = name + self.indexed_suffix()` no longer
#      appears in parser.mbt -- the annotation reader was refactored into
#      `indexed_suffix`'s own return path. The old runner printed "anchor not found",
#      counted it as neither kill nor failure, and exited 0. The same defect 0.4.12
#      had. It is now `Retired` with the reason recorded, and NOT re-anchored.
#
#   2. N1 AND N2 ARE THE SAME MUTATION. Byte-identical: same file, same `old`, same
#      `new`, same filter, and the run shows both selecting the same 6 tests. The
#      labels say "(read arm)" and "(write arm)", so the AUTHOR intended two different
#      mutations and wrote one twice -- which means the read/write arm distinction
#      this gate claims to cover has never actually been covered by two independent
#      mutations. N2 is retired with that reason rather than deleted, so the gap
#      stays visible instead of shrinking the count by one.
#
# WHAT THE HARNESS STILL FIXES HERE:
#   - a green BASELINE is now ASSERTED, not printed. The old file printed six
#     `exit=0 ran=N` lines and then went on to score mutations regardless; if the
#     suite had been red before the first mutation, every verdict below it was
#     uninterpretable and the gate would still exit 0.
#   - a kill is judged by the `Total tests:` line, so a mutant that fails to BUILD
#     is COMPILE-ERR rather than indistinguishable from a caught one.
#   - restores are proven by SHA256, not by moving a `.bakmut` file back.
#
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File _verify/mutate_0413.ps1
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'mutate_lib.ps1')

$INFER = 'src\types\infer.mbt'
$TYPES = 'src\types\types.mbt'
$PARSER = 'src\parser\parser.mbt'
$LEXER = 'src\lexer\lexer.mbt'
$WALK = 'src\walk\walk.mbt'

$mutations = @(
  # N1/N2 -- the subscript type gate. This is the check that keeps a list-subscript
  # read from being reported with the wrong element type when the base is not a
  # list. The two entries were byte-identical; only one distinct mutation exists.
  @{
    Name = 'N1 subscript gate (read arm)'
    File = $INFER
    Find = 'if bt is TList(_) && !(it is TInt) && !(it is TUnknown) {'
    Repl = 'if !(it is TInt) && !(it is TUnknown) {'
  }
  @{
    Name = 'N2 subscript gate (write arm)'
    File = $INFER
    Retired = 'byte-identical to N1 -- same file, same anchor, same replacement, same 6 tests selected. The "(read arm)"/"(write arm)" split was never implemented, so the write arm is not separately covered by any mutation'
    Find = 'if bt is TList(_) && !(it is TInt) && !(it is TUnknown) {'
    Repl = 'if !(it is TInt) && !(it is TUnknown) {'
  }

  # N3 -- `Array[T]` is a list type. The prefix test is on the first five characters
  # so `Arrayx` must not read as a list; killing the whole clause is what proves the
  # table is reached at all.
  @{
    Name = 'N3 Array is a list'
    File = $TYPES
    Find = 'if n > 6 &&'
    Repl = 'if false &&'
  }

  # N4 -- the annotation reader must KEEP the `[...]` suffix. Rotten: the reader was
  # refactored after 0.4.13 and this line no longer exists in that form.
  @{
    Name = 'N4 parser keeps [] args'
    File = $PARSER
    Retired = 'the annotation reader was refactored after 0.4.13; `let mut n = name + self.indexed_suffix()` no longer exists in that form. N3 above still pins the Array[T] half of this'
    Find = 'let mut n = name + self.indexed_suffix()'
    Repl = 'let mut n = name'
  }

  # N5 -- list-to-list assignability is elementwise, not wholesale.
  @{
    Name = 'N5 TList assignability'
    File = $TYPES
    Find = '(TList(a), TList(b)) => ty_assignable(a, b)'
    Repl = '(TList(_), TList(_)) => false'
  }

  # N6 -- `self` is a CONVENTIONAL PARAMETER NAME, not a keyword. It was listed as
  # one, so a parameter read only inside an interpolation reported unused while the
  # identical read in a plain expression was silent.
  @{
    Name = 'N6 self is not a keyword'
    File = $LEXER
    Find = '    | "init" => true'
    Repl = '    | "init"
    | "self" => true'
  }

  # N7/N8 -- the discard rule and its negative control, in one place because they
  # share an anchor and only make sense as a pair: N7 alone proves the prefix rule
  # is load-bearing, N8 alone proves the rule is not "everything is a discard".
  @{
    Name = 'N7 discard prefix'
    File = $WALK
    Find = "fn is_discard_name(n : String) -> Bool {
  n.has_prefix(`"_`")
}"
    Repl = "fn is_discard_name(n : String) -> Bool {
  n == `"_`"
}"
  }
  @{
    Name = 'N8 non-underscore still reported'
    File = $WALK
    Find = "fn is_discard_name(n : String) -> Bool {
  n.has_prefix(`"_`")
}"
    Repl = "fn is_discard_name(n : String) -> Bool {
  true
}"
  }
)

Invoke-MutationGate -Name '0.4.13' -Target 'wasm' -Mutations $mutations
Write-MutationGateVerdict -Name '0.4.13 mutation gate'
if ($script:MutationGateFailures.Count -gt 0) { exit 1 }
exit 0