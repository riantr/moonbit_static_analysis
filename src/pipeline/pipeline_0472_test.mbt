//| Tests for 0472 at the PIPELINE level -- what the analyzer SEES, not what the tree holds.
//!
//| The failure this increment could plausibly have shipped is the same one 0471 had to guard
//! against, in a new place. `continue` MAY CARRY VALUES, and the arm that reads them has to
// decide whether a value follows. Get that wrong in the direction of "always read one" and a
// bare `continue` on its own line swallows the NEXT STATEMENT: the file parses, `parsed` goes
//! UP on every affected corpus, every SUMMARY line looks like progress, and the analyzer has
// quietly stopped reading code.
//!
//! Neither the six pinned corpora nor a parse-shape assertion can see that. Only a NAME
//! placed after the continue, looked for by a later lens, can.
//!
//! => 判据: a fix that makes files readable has to be checked for what it stops reading. The
//! probe goes on the FAR SIDE of the change, because that is the side that can disappear.

//| A name after a bare `continue` must still be reported. This is the row the first draft of
//| the arm would have failed: it called `skip_seps()` before looking for a value, so this
//| name was read as the continue's value and the rest of the body went with it.

///|
test "0472: a name after a bare continue is still reported undefined" {
  let r = @pipeline.run(
    "///|\nfn f(n : Int) -> Unit {\n  for i = 0; i < n; i = i + 1 {\n    continue\n    ignore(zq_after_bare)\n  }\n}\n",
    "contbare.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "UndefinedName"), 1)
}

///|
/// THE SAME PROBE AFTER A `continue` THAT DOES CARRY A VALUE, where the value legitimately
/// ends the line and the next line is still a statement. Both forms have to leave it alone,
/// and the two rows together are what say the arm distinguishes them rather than always or
/// never reading a value.
test "0472: a name after a valued continue is still reported undefined" {
  let r = @pipeline.run(
    "///|\nfn f(n : Int) -> Unit {\n  for i = 0, j = 0; i < n; i = i + 1 {\n    continue i + 1, j + 1\n    ignore(zq_after_valued)\n  }\n}\n",
    "contvalued.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "UndefinedName"), 1)
}

///|
/// THE CONTROL. A name after an ordinary statement in the same loop body, with no `continue`
/// involved at all. If this were zero the two rows above would be passing because the probe
/// is unreachable rather than because the arm is right.
test "0472: the probe is reachable without any continue at all" {
  let r = @pipeline.run(
    "///|\nfn f(n : Int) -> Unit {\n  for i = 0; i < n; i = i + 1 {\n    ignore(i)\n    ignore(zq_no_continue)\n  }\n}\n",
    "contnone.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "UndefinedName"), 1)
}

///|
/// THE NAMES INSIDE A `continue`'s VALUES ARE NOW READ, which is the half of this increment
/// that REMOVES findings rather than adding reach. `walk.mbt` and `infer.mbt` both treat
/// `SContinue` as a no-op, so before this increment `continue p, r` left `p` and `r`
/// unread by anything -- and an unread binding is exactly what `UnusedLocal` reports.
/// Asserting `== 0` here is the row that would have caught the value-reading being dropped,
/// and it is a zero-row, so the row below is what gives it teeth.
test "0472: a name used only in a continue's values is not reported unused" {
  let r = @pipeline.run(
    "///|\nfn f(n : Int) -> Unit {\n  for i = 0, j = 0; i < n; i = i + 1 {\n    continue i + 1, j + 1\n  }\n}\n",
    "contunused.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "UnusedLocal"), 0)
}

///|
/// AND THE CONTROL FOR THAT ZERO: the same two bindings, with the `continue` carrying no
/// value, so `probe_unused` really is never read. If this were also zero the row above would
/// pass because the lens had stopped looking rather than because the names are read.
/// The first draft of this row wrote `ignore(j)` as its filler -- which READS `j`, so the
/// fixture contradicted the assertion it was meant to support and the row came back 0.
/// => a control row that cannot fail when the thing it controls is broken is not a control.
test "0472: a binding nothing reads is reported unused" {
  let r = @pipeline.run(
    "///|\nfn f(n : Int) -> Unit {\n  let probe_unused = 0\n  for i = 0; i < n; i = i + 1 {\n    continue\n  }\n}\n",
    "contunusedctrl.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "UnusedLocal"), 1)
}
