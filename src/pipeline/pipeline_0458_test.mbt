//| Tests for 0.4.29: the ASYNC FUNCTION TYPE, `(async (A, B) -> R)?`.
//
//| WHY THIS IS THE LAST BLOCKER. After 0456 and 0457, wzzc-dev/moui 0.1.12 stood
//| at 607 of 608 files. The one remaining file, `runtime/app_builder.mbt`, stopped
//| at line 47 on `expected ')'`:
//!
//!     launch_async? : (async (AppLaunchRequest, Int) -> Unit)? = None,
//!
//! `fn_type_annotation` bumped the `(`, handed `async` to `type_annotation()` as an
//! ordinary type NAME, broke out of the parameter loop on the `(` that followed it
//! instead of on a comma, and then `expect(TRParen)` reported the bracket it was
//! still looking for. The name was never the problem; the missing head was.
//!
//| WHY LINE 40 IS NOT EVIDENCE THAT THE TYPE ALREADY PARSED. The identical type is
//! written on line 40, inside a `struct` body, and struct bodies are skipped
//| WHOLESALE -- the reader never got there, so line 40 could not testify.
//!
//| => 判据: "it already parses elsewhere in the file" is evidence only if the reader
//| REACHED the other occurrence. Two identical constructs at different depths can sit
//| on opposite sides of a skipped region, and only the one the reader entered can
//| testify about the other.
//!
//| THE PART THAT IS NOT OBVIOUS, settled against the toolchain
//! (`_verify/settle_0458_async_fn_type.ps1`, 7/7 with two failure-capable controls):
//! the trailing `?` makes the RETURN type optional. It does NOT lift the group into a
//! nullable function type. The toolchain reads the source as
//!
//!     async (Int, Int) -> Unit?
//!
//| which is why three earlier fixtures failed before any grammar was measured: two
//! were call sites given the wrong return shape, and one treated an optional
//! PARAMETER (`x?`) as if it were a nullable TYPE (`T?`). The corpus line has both.
//!
//| The `?` clause already existed in `fn_type_annotation`; what was missing was the
//! `async` head. That is worth stating plainly, because the obvious fix -- treating
//! `async` as any other type name -- is exactly the bug.

///|
/// THE CONSTRUCT, in the corpus's shape: an async function type on an optional
/// parameter defaulted to `None`.
///
/// `parse_failures == 0` is the assertion that was false before this increment,
/// and it is a genuine signal here rather than a formality: the pre-fix parser
/// reported `expected ')'` on exactly this line, which `parse_failures` counts.
test "0458: an async function type is read as a type" {
  let r = @pipeline.run(
    "///|\nfn build(\n  launch_async? : (async (Int, Int) -> Unit)? = None,\n) -> Unit {\n  ignore(launch_async)\n}\n",
    "app_builder.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(parse_failures(r), 0)
}

///|
/// IN A RETURN POSITION, which is a different call site from the parameter one
/// and reaches `type_annotation` from the signature rather than from a parameter
/// list. Settled independently by `async_bare_field`/`async_optional_param` only
/// in parameter and field positions, so nothing in the settle speaks to this.
///
/// AN HONEST NOTE ON WHAT THIS FILE DOES NOT ASSERT. The first draft asserted the
/// RENDERED form -- that some signature contains `async (Int, Int) -> Unit?` -- and
/// both such tests failed. The rendered annotation string is consumed inside the
/// parser and handed to `ann_to_ty`, and it is not part of the pipeline result, so
/// no end-to-end assertion can reach it. That is the same trap
/// `pipeline_0413_test.mbt:83` describes: an end-to-end assertion here would be
/// asserting something unreachable, and would have been deleted or weakened rather
/// than satisfied.
///
/// So the `?`-on-the-return-type fact is pinned where it is observable at all --
/// in `settle_0458_async_fn_type.ps1`, against the toolchain, 7/7 -- and this file
/// pins what it can see: the construct parses, in every position, and the token
/// stream stays in step behind it.
test "0458: an async function type in a return position is read" {
  let r = @pipeline.run(
    "///|\nfn fetch() -> (async (Int, Int) -> Unit)? {\n  None\n}\n",
    "ret.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(parse_failures(r), 0)
}

///|
/// THE BARE FORM still reads, with no `?` anywhere. Without it, a fix could add
/// the optional-return shape while dropping the plain one -- and the plain one is
/// what `runtime/app_builder.mbt:40` and the interface file both write.
test "0458: a bare async function type is still read" {
  let r = @pipeline.run(
    "///|\nstruct Holder {\n  f : (async (Int, Int) -> Unit)\n}\n\n///|\nfn use_it(h : Holder) -> Unit {\n  ignore(h.f)\n}\n",
    "holder.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(parse_failures(r), 0)
}

///|
/// AND THE CONTROL: an ordinary function type in the identical position is
/// unchanged by this increment. A head that fires on any `(`-prefixed annotation
/// rather than on `async` would break the far more common plain form, and a gate
/// that only ever showed the async shape would not notice.
test "0458: a plain function type in the same position is unchanged (control)" {
  let r = @pipeline.run(
    "///|\nfn build(\n  on_input~ : ((String) -> Int)? = None,\n) -> Unit {\n  ignore(on_input)\n}\n",
    "plain.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(parse_failures(r), 0)
}

///|
/// AND THE SHARPER EDGE OF THAT CONTROL, which is the only thing that can tell
/// the async head from a bracket test -- and the reason gate M4 was measured
/// instead of argued.
///
/// `fn_type_annotation`'s lookahead is `at_name("async") && lparen_at(p + 1)`. Drop
/// the name half and the condition reads "the token after `(` is also a `(`",
/// which a caller can satisfy with valid MoonBit:
///
///     fn f(g : (((Int)) -> Unit)) -> Unit { ignore(g) }
///
/// ACCEPT, zero errors, settled against `moon check`. After the outer `(` is
/// bumped the cursor is on `(` and the next token is `(` -- the shape M4 needs.
///
/// The control above cannot see it: in `((String) -> Int)?` the cursor lands on
/// `String`, so `lparen_at(p + 1)` is false either way and the two versions of the
/// head agree. 648 tests were green with M4 mutating the head unchecked, which is
/// why this test exists rather than a `Prove` claiming the guard was unobservable.
///
/// The assertion is on what the parameter renders as, because the damage M4 does
/// is to consume a bracket and emit an `async` head where no `async` was written.
test "0458: a nested parenthesised parameter is not read as an async head" {
  let r = @pipeline.run(
    "///|\nfn f(g : (((Int)) -> Unit)) -> Unit {\n  ignore(g)\n}\n",
    "nested_paren.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(parse_failures(r), 0)
  // Nothing in this file says `async`, so no rendered signature may claim one.
  for s in r.sigs {
    assert_false(s.contains("async"))
  }
}

///|
/// AND THE STREAM STAYS IN STEP. A function after the declaration carries its own
/// undefined name. If the async head consumed the wrong number of tokens,
/// everything after the parameter list would be unread and the count would be 0.
///
/// `== 1` is the load-bearing half: a zero is what a truncation looks like, and an
/// assertion of zero cannot tell "analysed and clean" from "never read".
test "0458: what follows an async function type is still analysed" {
  let r = @pipeline.run(
    "///|\nfn build(\n  launch_async? : (async (Int, Int) -> Unit)? = None,\n) -> Unit {\n  ignore(launch_async)\n}\n\n///|\nfn after() -> Int {\n  missing_name_here\n}\nafter()\n",
    "after.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(parse_failures(r), 0)
  assert_eq(count_family(r, "UndefinedName"), 1)
}
