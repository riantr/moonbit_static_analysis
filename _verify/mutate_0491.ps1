# Mutation gate 0491 -- the CROSS-FILE NAME gap in the behavioral lens's READ path.
#
# WHAT THIS INCREMENT IS. The behavioral lens's READ path never asked the
# cross-file symbol table, while the STRUCTURAL lens has asked it since 0.4.3
# (`walk.mbt`'s "no visible binding" gate) and the behavioral lens's OWN CALL
# path has asked it since 0.4.3 (`Interp::call`). So a name bound in ANOTHER
# file -- a sibling of this one in the same package, or a dependency -- was
# reported `undefined variable` by one lens and silent by the other two, on the
# same line.
#
# MEASURED, wzzc-dev/moui 0.1.12, the per-function view: 51 findings of this
# shape -- 49 PRINTED, plus 2 the scanner's per-file print cap hides -- of
# which 35 are `undefined variable 'Constant'` -- an enum variant of
# `pub(all) enum DeclarationChannel` in `core/declaration.mbt`, read bare in
# `core/modifier_paint.mbt`. The rest are the same shape: the unit variants of
# a `priv enum` in a sibling file (`MoveLeft`, `MoveRight`, `MoveStart`,
# `MoveEnd`), `Up`, `view_size_key`, `DeclarationKey::double`, and the
# package-private `dispatch_web_*`, `web_active_app`, `clone_semantics_issue`
# and `macos_perf_now_ms`.
#
# THE FIX IS ONE BRANCH in the `EName` read chain, and it asks the same two
# questions the call path asks:
#
#     self.extern_iface.has_value(n) || self.extern_iface.has_type(n)
#
# SETTLED WITH THE TOOLCHAIN, `_verify/settle_0491_crossfile.ps1`, 12/12 with
# every control firing: the toolchain ACCEPTS every same-package sibling shape
# -- a bare unit variant of a `pub(all)` enum, a bare unit variant of a `priv`
# enum, a package-private `fn`, a package-private `let`, a `pub const`, a
# qualified `pub fn`, and all of them in one file -- and REFUSES the
# cross-package ones (a package-private `fn`, a bare variant of another
# package's enum) and a name that exists nowhere.
#
# THE FOUR MUTATIONS below are the four ways this branch can be wrong:
#
#   M1  the `has_value` half is gone -- a cross-file VALUE reads as undefined.
#   M2  the `has_type` half is gone -- a cross-file TYPE reads as undefined.
#   M3  the answer is `AType("Function")` -- the lens claims a type the table
#       never said, and ordinary arithmetic on the value becomes a METHOD
#       ERROR.
#   M4  THE BLANKET. The branch fires for EVERY name. This is the failure mode
#       the whole fix risks -- "stop reporting undefined names" instead of
#       "resolve the names that are bound" -- and the CONTROL row is what
#       kills it: a name bound nowhere must STILL be reported.
#
# ANCHORS ARE WRITTEN AGAINST THE POST-`moon fmt` SOURCE. fmt both rewraps one
# line into several and collapses several into one, and either way a stale
# anchor is a PREFLIGHT MISS that runs no suite at all.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'mutate_lib.ps1')

$INTERP = 'src\interp\interp.mbt'

Invoke-MutationGate -Name '0491' -Target 'wasm' -Mutations @(

  # M1 THE VALUE HALF. A cross-file value -- a function, a constant, an enum
  # constructor -- read in a function body. The moui corpus's own shape is
  # `host_runtime.mbt:71` (`open_url=dispatch_web_open_url,`): a READ, not a
  # call, and a CALL of a cross-file name was already resolved by
  # `Interp::call`, so a test that called one would pass before this fix and
  # prove nothing.
  @{
    Name = 'M1 a cross-file value read in a function body is undefined again'
    File = $INTERP
    Find = @'
              } else if self.extern_iface.has_value(n) ||
                self.extern_iface.has_type(n) {
'@
    Repl = @'
              } else if self.extern_iface.has_type(n) {
'@
    MustRed = 'a cross-file name read in a function body is not undefined'
  }

  # M2 THE TYPE HALF. The structural lens's gate asks BOTH halves
  # (`!has_type(name) && !has_value(name)`), so a lens that asked only one
  # would still contradict it on a name the table holds as a TYPE.
  @{
    Name = 'M2 a cross-file type read in a function body is undefined again'
    File = $INTERP
    Find = @'
              } else if self.extern_iface.has_value(n) ||
                self.extern_iface.has_type(n) {
'@
    Repl = @'
              } else if self.extern_iface.has_value(n) {
'@
    MustRed = 'a cross-file type read in a function body is not undefined'
  }

  # M3 THE ANSWER. The table says a name IS bound; it says nothing about what
  # the name IS. `has_value` cannot tell a function from a constant -- the
  # table records that difference in a flag this lens has no reason to read --
  # so claiming `AType("Function")` would report a METHOD ERROR on ordinary
  # arithmetic. The honest answer is "a value of unknown type", which absorbs.
  #
  # THE FAMILY IS `MethodError`, NOT `OperatorMismatch`, and the first version
  # of this gate's M3 asserted `OperatorMismatch`. The mutant SURVIVED -- 1067
  # of 1067 tests green -- and the gate reported a survivor it had not earned.
  # `Interp::binop`'s fallback arm reports `FMethodError` ("no method matching
  # +(...)"); `FOpMismatch` is the TYPE lens's family. The two share a merge
  # GROUP -- `Family::merge_group` puts `FArgType | FMethodError | FOpMismatch`
  # under "arg-type" -- but a merge group is not a family, and a count BY FAMILY
  # cannot see the other one. MEASURED under this mutation: exactly ONE
  # `MethodError`, from the behavioral lens, at `pipeline_0491_test.mbt:153`.
  # => 判据: two families that share a merge group are still two families, and
  # an assertion on the wrong one is green forever.
  @{
    Name = "M3 a cross-file name's value claims to be a function"
    File = $INTERP
    Find = @'
                // in the type lens (`TUnknown`). `AType("Function")` would
                // claim more than the table knows: `has_value` cannot tell a
                // function from a constant, and the table records that
                // difference only in a flag this lens has no reason to read.
                AAny
'@
    Repl = @'
                // in the type lens (`TUnknown`). `AType("Function")` would
                // claim more than the table knows: `has_value` cannot tell a
                // function from a constant, and the table records that
                // difference only in a flag this lens has no reason to read.
                AType("Function")
'@
    MustRed = "a cross-file name's value absorbs instead of claiming a type"
  }

  # M4 THE BLANKET. The branch fires for every name, whatever the table says.
  # This is the shape a "just stop reporting undefined names" fix would take,
  # and it is the one the CONTROL row exists to kill: a name that is bound
  # NOWHERE must still be reported, because the toolchain rejects it
  # (`_verify/settle_0491_crossfile.ps1`, rows xf11 and xf12).
  #
  # AND THE CONTROL ROW COUNTS BY LENS, which it did not at first. BOTH lenses
  # report the unbound name -- the structural lens says "no visible binding",
  # the behavioral lens says "undefined variable" -- at the same span, so the
  # merge collapses them into ONE finding and the family-level count is
  # satisfied by the STRUCTURAL lens alone. MEASURED: with the family-level
  # count alone, this mutation was killed by a pre-existing merge test and NOT
  # by the row that was written to kill it -- the control had no teeth against
  # the lens it is about. The control row now counts
  # `count_family_in(..., @core.LBehavior)`, and under this mutation it goes
  # red at `pipeline_0491_test.mbt:91`.
  # => 判据: a merged finding is counted by family, but a claim about ONE
  # lens's decision has to be counted by lens, or the other lens answers for it.
  @{
    Name = 'M4 the cross-file branch fires for every name'
    File = $INTERP
    Find = @'
              } else if self.extern_iface.has_value(n) ||
                self.extern_iface.has_type(n) {
'@
    Repl = @'
              } else if self.extern_iface.has_value(n) ||
                self.extern_iface.has_type(n) ||
                self.ambient.contains(n) || !self.ambient.contains(n) {
'@
    MustRed = 'the same name with an empty table is still reported'
  }
)
