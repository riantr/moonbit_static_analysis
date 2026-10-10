// advice: what each finding family MEANS and what to DO about it, so a
// downstream agent reading a report does not have to guess.
//
// Every `why` here is written against the code that actually raises the
// family, not against how the name reads. Two of them carry a caveat that
// the tool cannot work around on its own and that a reader must know before
// acting on the finding — see FParse and FUndefinedName.

///|
/// One family's explanation: `why` the code was judged wrong, and `how` to
/// fix it. Plain strings on purpose — this is consumed by another program,
/// so it is prose an agent can read, not a machine-readable rule id.
pub(all) struct Advice {
  /// The rule that fired and the evidence it fired on.
  why : String
  /// What to change.
  how : String
}

///|
/// The explanation for one finding family.
///
/// A finding is only as good as the oracle behind it, so the FParse and
/// FUndefinedName entries say plainly when a finding of that family may be
/// the analyzer's blindness rather than the code's defect.
pub fn Family::advice(self : Family) -> Advice {
  match self {
    FParse =>
      Advice::{
        why: "The frontend did not read a construct, or a file-kind frontend rejected a shape. On a .mbt this marks the FIRST genuine read failure in the file: every finding at or after that line is withheld, because it would be derived from an already-wrong tree. On .mbti / .mbt.md / .mbtp it is a frontend rule (malformed line, duplicate signature, unresolvable type reference) rather than a parse boundary.",
        how: "Fix the FIRST parse error only — it is the boundary, and later ones are frequently its consequences. If the message is 'test declaration is outside the analyzed subset' or 'struct declaration is outside the analyzed subset', it is a declared scope limit of this analyzer, not a defect: there is nothing to fix. If it is 'unknown type ... in interface signature', the .mbti lens has no cross-file awareness and the type may well be declared in a sibling package; treat that finding as unverified rather than acting on it.",
      }
    FUnusedLocal =>
      Advice::{
        why: "A local binding was assigned and never read anywhere in the function. The scan is not flow-sensitive, so a read inside an unreachable or dead branch still counts as a use.",
        how: "Remove the binding, or read it. The bare `_` is exempt: a binding named `_` exists only to be discarded (`let _ = f(x)`, a `for k, _ in pairs` binder), so reporting it would contradict the language's own discard idiom. An underscore-PREFIXED name like `_unused` is still reported — a name is not a discard pile; if a binding exists only to be discarded, the honest fix is to delete the statement, not to rename it.",
      }
    FUnusedParam =>
      Advice::{
        why: "A parameter was never read in the function body. Writing THROUGH a parameter counts as a read, so `self.field = v` and `v[0] = x` do not trigger this; only a parameter that is genuinely never touched does.",
        how: "Remove the parameter and its argument at every call site, or keep it for signature compatibility and accept the warning. A parameter named exactly `_` is exempt — the same discard idiom as locals; an underscore-PREFIXED name is not exempt.",
      }
    FParamChanged =>
      Advice::{
        why: "A parameter's BINDING was rebound by a bare assignment — `p = expr` or `p += 1` — so from the next read on, `p` names something the caller never passed. Writing THROUGH a parameter is not this: MoonBit structs are references, so `self.field = v`, `v[0] = x` and `pair.0 = x` mutate the object the parameter points at and leave the parameter itself alone, and those do not report.",
        how: "If the rebinding is deliberate, accept the finding as advisory. If you meant to reach a field or an element, write that target directly instead of the parameter. If you need the original value after the write, copy it first: `let mut copy = p`, then assign to `copy` — that is also the fix for a genuine rebind, because it makes the change local to the call.",
      }
    FAssignType =>
      Advice::{
        why: "The right-hand side's inferred type is not assignable to the declared annotation. `Unknown` is always assignable, so a finding here means both sides were resolvable and disagreed.",
        how: "Correct the annotation, or convert the value. Caveat: optional types (`String?`) and the `None` literal are not modelled by the type lens, so a `None` passed into an optional parameter can be typed as something unrelated and report here; verify against `moon check` before acting.",
      }
    FArgType =>
      Advice::{
        why: "Either an argument's type is not assignable to the declared parameter, or more arguments were passed than the signature declares. The 'too many arguments' form only runs against a REAL parameter list — a function known only through a `.mbti` declaration is typed as an unknown-signature value and is never arity-checked.",
        how: "Check the declared parameter type at the call site. If this is an 'expected N, got M' on a cross-package call, confirm the callee's real signature first: this analyzer skips the check precisely because it cannot see the signature, so a report here means it did see one.",
      }
    FOpMismatch =>
      Advice::{
        why: "One of four shapes: `!` applied to a non-boolean; a binary operator applied to operand types it does not accept; a value that is known not to be callable being called; or a list index that is not an integer. A callee whose type is `Unknown` is never reported — an unresolved type is not evidence of anything.",
        how: "For an operand error, check both sides against the operator's domain. For 'not callable', the callee's type is known and is not a function — name a function, or call the method on the receiver. For a list index, pass an Int.",
      }
    FMethodError =>
      Advice::{
        why: "The behavioral lens could not find a method matching the operator or function on the abstract values it computed for the operands. It reasons about the concrete values it can fold, so it is the lens that reports most precisely and the one least likely to be the tool's blindness.",
        how: "Confirm the receiver type and the method's parameter types at the call site. This family is raised by the behavioral lens on folded constant values, so a finding usually corresponds to a real compile error.",
      }
    FCondBool =>
      Advice::{
        why: "A condition's type is known and is not boolean. As with the operand checks, an `Unknown` condition is never reported.",
        how: "Make the condition a boolean expression — compare explicitly, or replace a non-boolean value with a test on it.",
      }
    FUndefinedName =>
      Advice::{
        why: "No visible binding for the name: not declared in this file, not a builtin, and not present in the cross-file symbol table. The wording says which lens saw it — `no visible binding` (structural), `undefined name` (type), `undefined variable` / `undefined function` (behavior). All three consult the same table, so one finding means all three looked.",
        how: "Declare it, import it, or — when it lives in another package — index that package's interface with `--extern-iface-dir <dir>` (target `.repos/` after `moon fetch`). TWO known limits, both unfixable from the CLI: a `#doc(hidden)` API appears in no `.mbti` and so cannot be indexed that way, and a top-level cross-package reference written `@pkg.fn(1, 2)` is not folded into a callable name by the parser, so it is reported even when the package is indexed.",
      }
    FUnreachable =>
      Advice::{
        why: "A statement follows a `return`, `break` or `continue` on every path to it, so it can never execute.",
        how: "Delete it. If it was meant to run, the control flow above it needs to change.",
      }
  }
}
