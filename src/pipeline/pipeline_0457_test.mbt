//| Tests for 0.4.29: a nested `async fn NAME(..) { .. }` DECLARATION read past
//|| instead of being bound as a name.
//|
//| WHY THIS FILE EXISTS AT ALL, when 0453 already pinned a nested async
//| declaration. 0453 pinned that the declaration is not MISTAKEN for a literal
//| -- its test asserts `parse_failures == 0` and that the false notice
//| "async without a following `fn`" is absent. What 0453 could not see is that
//| the branch still YIELDED `EName("async")` on the way past, and 0453's own
//| comment recorded the reason without connecting it: a middle arm that
//| announces itself produces a notice, not a failure, so `parse_failures == 0`
//| passed while a false positive was being manufactured.
//|
//| => 判据: "the file parses and the wrong notice is absent" is not the same
//| property as "the branch does not invent a binding". The first is satisfied by
//| a branch that reads past correctly AND by one that reads past while still
//| yielding a name. Only a lens that resolves names can tell them apart, so a
//| parser fix whose harm is semantic needs a LENS-level assertion, not a
//| parse-failure count.
//|
//| THE DEFECT, and why it survived an entire increment. 0456 fixed
//| `is @pkg.Type::Ctor`, which unblocked `async 0.22.4 src/fs/watch_test.mbt` --
//| it had been dying at line 389 on `is @async.TimeoutError`. The file then
//| parsed whole for the first time and THREE sites surfaced at once, all
//| `undefined name 'async'`, taking async's actionable count from 0 to 3. So
//| the false positive existed for as long as the shape did; it was simply
//| unreachable, because every file carrying it was blocked by something earlier
//| and a finding no corpus can reach is not a finding that does not exist.
//|
//|   verified by `_verify/ab_0456_0457_coverage.ps1`: watch_test.mbt went from
//|   reach 389 to EOF in the same A/B that unblocked it. The line number the
//|   comment above names is the line number the reach map moved from.
//|
//| The toolchain agrees that `async` cannot be bound at all
//| (`_verify/settle_0457_nested_async_fn.ps1`, 5/5: `ctl_async_cannot_be_bound`
//| is REJECT(3002)), so the finding was refuted by construction rather than
//| merely unverified.

///|
/// THE GATE ITSELF. With the branch reverted to `EName("async")` this reports
/// `undefined name 'async'` on a declaration the toolchain accepts -- the
/// confident finding 0457 removes.
///
/// `== 0` and not `== 1`: the whole point is that there is no such name to
/// find. The control below is what keeps this honest from the other side.
test "0457: a nested async fn declaration does not bind `async` as a name" {
  let r = @pipeline.run(
    "///|\nfn outer() -> Int {\n  async fn log(s : String) -> Unit {\n    ignore(s)\n  }\n  1\n}\n",
    "nested_async_decl.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "UndefinedName"), 0)
}

///|
/// AND IT IS ANNOUNCED, not skipped in silence. A read-past that records
/// nothing is indistinguishable from a read-past that lost track of the token
/// stream, and only one of those is honest.
///
/// The needle is the DECLARATION's message. Asserting the sibling branch's
/// message here instead would be a test that passes for the wrong reason --
/// that is precisely mutation M3, and 0453's test 172 is what kills it.
test "0457: the async of an async fn declaration is announced as read past" {
  let r = @pipeline.run(
    "///|\nfn outer() -> Int {\n  async fn log(s : String) -> Unit {\n    ignore(s)\n  }\n  1\n}\n",
    "nested_async_decl.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(
    reports_containing(r, "the `async` of an `async fn` declaration"),
    true,
  )
}

///|
/// AND THE CONTROL: a program with no nested async declaration produces no such
/// notice. Without it the test above would also pass a parser that announced
/// this on every file it read.
///
/// The fixture deliberately contains an undefined name, so a parser that
/// announced nothing AT ALL -- because it never got that far -- is caught by
/// the count rather than being mistaken for a clean run.
test "0457: no nested async declaration means no such notice (control)" {
  let r = @pipeline.run(
    "///|\nfn probe() -> Int {\n  missing_name_here\n}\nprobe()\n",
    "control.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(
    reports_containing(r, "the `async` of an `async fn` declaration"),
    false,
  )
  // The file really was analysed, so the `false` above is a clean run and not a
  // file that was never read. Same reasoning as 0453's "expected value is 1,
  // not 0".
  assert_eq(count_family(r, "UndefinedName"), 1)
}

///|
/// AND THE STREAM STAYS IN STEP. A declaration AFTER the nested `async fn`
/// contains its own undefined name. The branch deliberately does NOT bump the
/// cursor -- the keyword is handed back unchanged so the next statement still
/// begins at `fn` and `parse_block` declares the function -- so anything that
/// moved the cursor would stop the following declaration from being analysed.
///
/// `== 1` is the load-bearing half. A zero here is what a truncation looks
/// like, and an assertion of zero cannot tell "analysed and clean" from "never
/// read".
test "0457: what follows a nested async fn declaration is still analysed" {
  let r = @pipeline.run(
    "///|\nfn outer() -> Int {\n  async fn log(s : String) -> Unit {\n    ignore(s)\n  }\n  1\n}\n\n///|\nfn after() -> Int {\n  missing_name_here\n}\nafter()\n",
    "after.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(parse_failures(r), 0)
  assert_eq(count_family(r, "UndefinedName"), 1)
}
