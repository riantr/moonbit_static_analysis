Three fixes from the first external scan (riantr/pyroduct 0.1.29)

The analyzer was pointed at a real external target for the first time:

    moonx riantr/moonbit_static_analysis@latest riantr/pyroduct@latest

119 files, 87 parsed (73.1%), actionable=43. Triaging the 43 rather than
counting them found 22 that were analyzer defects, in two fixable classes and
one syntax gap. All three are fixed here.

## 1. `Repr` was missing from the ambient list (16 findings)

`render.mbt` calls `Repr(x)` 16 times inside interpolations. `Repr` is declared
nowhere in the package, is in no .mbti, and comes from no import - because it is
a CONSTRUCTOR of the `Repr` enum in moonbitlang/core/debug
(`pub fn[T : Debug] Repr::Repr(T) -> Self`), and MoonBit puts `core` in implicit
scope. Every other name in ambient_names() was read out of core/builtin's
interface, which does not contain it.

Settled with the toolchain rather than by inference: a probe file calling
`Repr(1)` and `ZzNoSuchName123(2)` in the same interpolation, where `moon check`
flagged only the second.

## 2. An import alias inside an interpolation (6 findings) - a regression of 0.4.8

`\{@sm.all_states()}` reported `no visible binding for 'sm'`. The walk already
refuses to resolve an `@`-prefixed name, but that guard cannot reach into an
interpolation: `@` is not an identifier character, so the scan recorded the
alias WITHOUT its `@` and the guard saw an ordinary bare name. The
interpolation support introduced the very finding it was meant to remove.

## 3. `extend` is a declaration, not an expression (8 findings)

`pub extend Outcome with Eq::{not_equal, equal}` read as a statement turned
`extend` into a name. It is now a skipped declaration form alongside struct /
enum / trait / impl / derive / test, so the member list is consumed as a block
and the declarations after it are still read in full.

Measured on pyroduct 0.1.29: actionable 43 -> 13, coverage unchanged at 87/119.

## What this does NOT fix, stated plainly

I predicted fix 3 would also recover coverage - the 32 unreadable files are
dominated by 15x "expected 'in'", and I assumed extend was the cause. It was
not. The measurement says coverage did not move by one file.

The real blocker is the C-style three-clause for loop:

    for round = 0; round < 3; round = round + 1 {

`parse_stmt`'s for branch reads the head as a binder and then demands `in`,
which is where "expected 'in'" comes from. 15 of 32 unreadable files, 12.6% of
the corpus, one construct. That is the highest-value next change and it is NOT
in this release.

Also still open: 8 findings for calls to a package-private helper in a sibling
file (the cross-file visibility limit documented in 0.4.10), 2 `_`-prefixed
unused reports (by design), and 2 OperatorMismatch in paths.mbt not yet traced.

Tests: 212 js / 282 wasm / 212 wasm-gc, --deny-warn clean, moon fmt --check
clean. Each of the three guards is mutation-verified (revert -> red -> restore
-> green), and the extend mutation isolates cleanly: the second test fails with
`2 != 1`, the extra being the `undefined variable 'extend'` it was written to
catch. Self-scan stays 46/46 with actionable=0.