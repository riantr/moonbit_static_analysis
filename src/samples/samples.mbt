// Embedded MoonBit-subset samples for the demo.

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
