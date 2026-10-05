// Embedded MoonBit-subset samples for the demo.

///|
/// A toolchain file-kind sample set: a literate .mbt.md document, an .mbti
/// interface file and a .mbtp proof file (see EXTENSIONS.md).
///
/// The fences are `mbt`, the language the toolchain actually compiles. The
/// first two blocks are display-only (`mbt nocheck` and bare `moonbit`) and
/// must be skipped even though the second one names an undefined function —
/// that is the whole point of honouring the fence language.
pub let literate_md : String =
  #|# Demo document
  #|
  #|A display-only block, shown but never compiled (its bad name is NOT reported):
  #|
  #|```mbt nocheck
  #|fn ignored() -> int {
  #|  vanish(1)
  #|}
  #|```
  #|
  #|Another display-only block, the bare `moonbit` fence:
  #|
  #|```moonbit
  #|fn also_ignored() -> int {
  #|  gone(2)
  #|}
  #|```
  #|
  #|A compiled block:
  #|
  #|```mbt
  #|fn twice(n: int) -> int {
  #|  n * 2
  #|}
  #|twice(21)
  #|```
  #|
  #|A compiled block with a real defect (lands on file line 32):
  #|
  #|```mbt check
  #|fn shrug() -> int {
  #|  vanish(1)
  #|}
  #|```
  #|

///|
/// A `.mbtx` script sample: the import block in the official form (a quoted
/// path with trailing, ordered modifiers) plus a body defect, so the report
/// shows both the echoed imports and a finding.
pub let script_mbtx : String =
  #|import {
  #|  "moonbitlang/core/list" @ls,
  #|  "moonbitlang/core/queue" @q *,
  #|}
  #|
  #|fn total(xs) -> int {
  #|  vanish(xs)
  #|}
  #|

///|
/// An .mbti interface sample: one unknown type reference.
pub let iface_bad : String =
  #|// Generated using `moon info`, DON'T EDIT IT
  #|package "riantr/demo"
  #|
  #|pub(all) struct Pos {
  #|  line : Int
  #|} derive(Eq)
  #|pub fn Pos::shift(Self, Int) -> Pos
  #|pub fn leap(Mystery) -> Int
  #|

///|
/// A .mbtp proof sample: a string constant inside a logic body.
pub let proof_bad : String =
  #|///|
  #|predicate is_hot(s : Severity) {
  #|  s.tag() == "hot"
  #|}
  #|
  #|///|
  #|lemma one_zero() where {
  #|  proof_ensure: LStructural.rank() == 0,
  #|} {}
  #|

///|
/// Clean: recursion + dispatch — zero findings, signature inferred.
pub let clean : String =
  #|fn fact(n: int) -> int {
  #|  if n <= 1 { return 1 }
  #|  return n * fact(n - 1)
  #|}
  #|print(fact(5))
  #|

///|
/// One defect, three lenses: `missing` is bound nowhere. The structural
/// walk, the type checker and the abstract interpreter all see it — the
/// pipeline merges them into ONE finding with three lens tags.
pub let undefined : String =
  #|fn g() -> int {
  #|  return missing + 1
  #|}
  #|g()
  #|

///|
/// Structural-only findings: unused parameter, unused local, parameter
/// changed by assignment — types and behavior are silent.
pub let structure : String =
  #|fn f(x: int, y: int) -> int {
  #|  z = x * 2
  #|  y = 3
  #|  return z
  #|}
  #|f(1, 2)
  #|

///|
/// Dead branch pruned everywhere: `1 > 2` folds to a literal false, so
/// `typo_fn` never becomes a finding in any lens.
pub let deadbranch : String =
  #|fn h(x: int) -> int {
  #|  if 1 > 2 {
  #|    return typo_fn(x)
  #|  }
  #|  return x * 2
  #|}
  #|h(3)
  #|

///|
/// Type-lens findings that the behavior lens echoes: the annotated
/// assignment mismatch, and a call whose argument breaks the declared
/// signature (argument-type error + method error merge).
pub let typing : String =
  #|fn shout(s: str) -> int {
  #|  return len(s)
  #|}
  #|let n: int = 1
  #|n = "oops"
  #|shout(42)
  #|print(1 + "x")
  #|

///|
/// Behavior-lens findings with a type echo: non-bool condition (merged
/// lens) and unreachable code after a return.
pub let flow : String =
  #|let k = 3
  #|if k {
  #|  print("yes")
  #|}
  #|fn u(x: int) -> int {
  #|  return x
  #|  print(x)
  #|}
  #|u(1)
  #|

///|
pub fn all() -> Array[(String, String)] {
  [
    ("clean.mbt", clean),
    ("undefined.mbt", undefined),
    ("structure.mbt", structure),
    ("deadbranch.mbt", deadbranch),
    ("typing.mbt", typing),
    ("flow.mbt", flow),
  ]
}
