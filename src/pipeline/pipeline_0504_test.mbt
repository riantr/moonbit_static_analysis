//| Tests for 0504 -- the COMPREHENSION GUARD.
//!
//! THE DEFECT. A comprehension may filter: `[ for x in xs if <cond> => <body> ]`.
//! The parser read that `if` and then THREW IT AWAY -- `ignore(self.parse_or())`
//! -- so the `is` binding the condition introduces never reached the AST, and
//! the body's read of it had no binding to resolve. On `moonbitlang/core`
//! `hashset/hashset.mbt:382`:
//!
//!     [ for entry in self.entries if entry is Some({ key, .. }) => key ]
//!
//! that produced `undefined variable 'key'` -- a FALSE POSITIVE on a file the
//! toolchain compiles. 0503 (`raise?`) made that file readable; 0504 is what the
//! readability exposed.
//!
//! SETTLED WITH THE COMPILER AS THE ORACLE, not assumed.
//! `_verify/settle_0504_comp_guard.ps1`, 18 rows: 16 with `moon check` and 2 with
//! `moon test`. The two runtime rows are the ones `moon check` cannot answer --
//! that the condition is EVALUATED once per element, and that the `is` binding
//! it introduces reaches the body.
//!
//! => 判据: the condition is real code. It is resolved by the compiler, it is
//! evaluated per element, and its binding is in scope for the body and for
//! nothing else. A reader that drops it invents a finding -- so the fix is to
//! CARRY it, and these rows pin the three things that carrying it must not
//! break: the undefined-name family must stay alive, the unused family must
//! stay honest, and the condition's own scope must stay bounded.
//!
//! THE TWO INSTRUMENTS ARE DIFFERENT AND BOTH ARE NEEDED. `count_named`
//! counts by MESSAGE, because every finding here is family `UndefinedName` and
//! a family count cannot tell "no undefined `key`" from "no undefined names at
//! all" -- and the second would still pass if the fix had muted the lens.
//! `count_family` is the right tool for the unused rows, where the question is
//! about a family and not about one name.
//!
//! AND EVERY FIXTURE GOES IN THROUGH `run_functions`, not `run`, and the reason
//! is MEASURED rather than tidiness. `run` enters the behavioural lens at the
//! MODULE entry, and a function nothing calls is never evaluated there -- so
//! the behaviour lens never reached the comprehension at all, and the whole
//! third lens was absent from these fixtures. That is not a theoretical gap:
//! the first run of gate 0504 found TWO mutations (M6 "the condition is not
//! evaluated", M7 "the condition is evaluated in the outer environment") that
//! SURVIVED, because the lens that could see them was never switched on.
//! `run_functions` enters at each FUNCTION instead, so a function nothing calls
//! is still analysed -- which is the whole point of it, and the same reason
//! gate 0495's `0495 H` row uses it.

// ---------------------------------------------------------------------------
// THE DEFECT
// ---------------------------------------------------------------------------

///|
/// THE CORPUS SHAPE, byte for byte in form: `moonbitlang/core`
/// `hashset/hashset.mbt:382`. The body's `key` is bound by the condition's own
/// `is` pattern, and it must resolve.
///
/// Before the fix this was `undefined variable 'key'`.
test "0504: the name the condition binds is not reported undefined" {
  let r = @pipeline.run_functions(
    "struct Entry {\n  key : Int\n  other : Int\n}\n\nfn to_array(entries : Array[Option[Entry]]) -> Array[Int] {\n  [\n    for entry in entries if entry is Some({ key, .. }) => key\n  ]\n}\n",
    "comp_guard_shape.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_named(r, "key"), 0)
}

///|
/// THE SAME LINE WITH `self.entries`, which is how core writes it -- the
/// iterable is a FIELD of the receiver, not a bare name. A reader that carried
/// the condition but broke the iterable would still pass the row above.
test "0504: the corpus shape over a field iterable is not reported undefined" {
  let r = @pipeline.run_functions(
    "struct Entry {\n  key : Int\n  other : Int\n}\n\nstruct Set {\n  entries : Array[Option[Entry]]\n}\n\nfn to_array(self : Set) -> Array[Int] {\n  [\n    for entry in self.entries if entry is Some({ key, .. }) => key\n  ]\n}\n",
    "comp_guard_self.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_named(r, "key"), 0)
}

///|
/// THE CONTROL FOR THE TWO ROWS ABOVE, and it differs from them by ONE TOKEN.
/// A name that genuinely does not exist must still be reported -- otherwise the
/// fix could have been "stop resolving names after a condition", which would
/// silence real defects in every comprehension that has one.
test "0504: control -- a genuinely undefined name is still reported" {
  let r = @pipeline.run_functions(
    "fn to_array(xs : Array[Option[Int]]) -> Array[Int] {\n  let _ = nosuchname\n  [\n    for x in xs if x is Some(v) => v\n  ]\n}\n",
    "comp_guard_control.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_named(r, "nosuchname"), 1)
  assert_eq(count_named(r, "v"), 0)
}

// ---------------------------------------------------------------------------
// THE CONDITION'S READS ARE READS
// ---------------------------------------------------------------------------

///|
/// A NAME READ ONLY INSIDE THE CONDITION IS USED. This is the half of the
/// defect that was still latent after the false positive was fixed: the
/// condition's reads were lost too, so a parameter read only there would have
/// been reported as never used.
///
/// `keep` is read in exactly one place -- the condition -- and the condition
/// is evaluated once per element (settle row RT1), so the read is a real one.
test "0504: a parameter read only inside the condition is not reported unused" {
  let r = @pipeline.run_functions(
    "fn to_array(xs : Array[Option[Int]], keep : Bool) -> Array[Int] {\n  [\n    for x in xs if keep && x is Some(v) => v\n  ]\n}\n",
    "comp_guard_reads.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "UnusedParam"), 0)
}

///|
/// THE CONTROL FOR THE ROW ABOOVE, and it must expect the OPPOSITE number.
/// Same function, same shape -- and `keep` is read by nothing at all. If this
/// ever reported 0, the row above would have stopped meaning anything: "no
/// unused finding" would then be true of the program rather than of the
/// condition.
test "0504: control -- the same parameter read by nothing is still unused" {
  let r = @pipeline.run_functions(
    "fn to_array(xs : Array[Option[Int]], keep : Bool) -> Array[Int] {\n  [\n    for x in xs if x is Some(v) => v\n  ]\n}\n",
    "comp_guard_reads_control.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "UnusedParam"), 1)
}

// ---------------------------------------------------------------------------
// THE CONDITION'S SCOPE IS BOUNDED
// ---------------------------------------------------------------------------

///|
/// THE CONDITION'S BINDING DOES NOT ESCAPE THE COMPREHENSION. The toolchain
/// agrees -- settle row C, `c_binding_not_visible_after.mbt`, is REJECTED by
/// `moon check` -- and the analyzer must agree with it, or it would resolve a
/// name the language does not have in scope.
test "0504: the name the condition binds does not escape the comprehension" {
  let r = @pipeline.run_functions(
    "fn to_array(xs : Array[Option[Int]]) -> Array[Int] {\n  let a = [\n    for x in xs if x is Some(v) => v\n  ]\n  v\n}\n",
    "comp_guard_scope.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_named(r, "v"), 1)
}

// ---------------------------------------------------------------------------
// THE CONDITION IS STILL ANALYSED
// ---------------------------------------------------------------------------

///|
/// AN UNDEFINED NAME INSIDE THE CONDITION IS STILL REPORTED. The condition is
/// real code -- the toolchain rejects this program -- so a reader that carries
/// the condition and then ignores it would be wrong in the other direction.
///
/// This is the row that kills "carry the condition and never look at it".
test "0504: an undefined name inside the condition is still reported" {
  let r = @pipeline.run_functions(
    "fn to_array(xs : Array[Int]) -> Array[Int] {\n  [ for x in xs if nosuchfn(x) => x ]\n}\n",
    "comp_guard_undefined.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_named(r, "nosuchfn"), 1)
}

///|
/// THE LOOP VARIABLE IS IN SCOPE INSIDE THE CONDITION. The condition reads the
/// loop variable -- settle row D, `d_guard_reads_loop_var.mbt`, is ACCEPTED by
/// `moon check` -- and the loop variable is bound in the COMPREHENSION's own
/// environment, not in the enclosing one.
///
/// This row was written after gate 0504's M7, and the reason is worth
/// recording. M7 moves the condition's evaluation into the enclosing
/// environment, and the first thing that breaks is not the condition's own
/// binding -- it is the LOOP VARIABLE, which only ever lived in the
/// comprehension's environment. The test M7 killed first was the one counting
/// the undefined name INSIDE the condition, and it went red for a reason one
/// step removed from the mutation's name: two undefined names on one line are
/// merged into one finding, so the condition's own `nosuchfn` stopped being
/// the message that survived the merge.
///
/// A test that pins the mechanism directly is worth more than one that pins the
/// symptom, and this is the mechanism.
test "0504: the loop variable is in scope inside the condition" {
  let r = @pipeline.run_functions(
    "fn to_array(xs : Array[Int]) -> Array[Int] {\n  [ for x in xs if x > 0 => x ]\n}\n",
    "comp_guard_loop_var.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_named(r, "x"), 0)
}

///|
/// A TYPE ERROR INSIDE THE CONDITION IS STILL FOUND. The condition is TYPED,
/// not merely walked, so `take(1)` -- an `Int` where a `Bool` is declared --
/// is reported.
///
/// This is the row that kills "the condition is walked but not typed". Without
/// it, dropping the type lens's call on the condition would lose real checking
/// and every other row in this file would still pass.
///
/// THIS ROW GOES IN THROUGH `run` AND NOT `run_functions`, and the reason is
/// the MERGE, not a preference. The merge takes the most specific lens's
/// report as the representative and rewrites the family to it --
/// "merged arg-type echoes present as MethodError (the behavioral phrasing is
/// the most specific)". In the per-function entry the behaviour lens evaluates
/// `take(1)` as well, so the same line carries BOTH lenses and the merged
/// finding's family is `MethodError`, not `ArgTypeMismatch` -- and counting by
/// family then counts ZERO. The row would measure the merge instead of the
/// type lens.
///
/// The module entry is the right instrument for this one row: the type lens
/// runs in both entries, and the behaviour lens has nothing to echo from
/// because a module entry never calls a library function.
test "0504: a type error inside the condition is still reported" {
  let r = @pipeline.run(
    "fn take(x : Bool) -> Bool {\n  x\n}\n\nfn to_array(xs : Array[Int]) -> Array[Int] {\n  [ for x in xs if take(1) => x ]\n}\n",
    "comp_guard_type_error.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "ArgTypeMismatch"), 1)
}
