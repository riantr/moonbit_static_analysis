///|
/// 0442: `try ... catch { .. } noraise { .. }` is a SECOND HANDLER BLOCK, not a
/// name.
///

///|
/// THE DEFECT. The postfix reader had a production for `catch` and none for
/// `noraise`, so the bare token was resolved as an ordinary identifier and
/// reported as `undefined name 'noraise'`. Measured, four sites:
///
///   proton facade_identity.mbt:99     } noraise {
///   proton facade_identity.mbt:136    } noraise {
///   proton protocol_wbtest.mbt:5      } noraise {
///   async  network.mbt:68             } noraise {
///
/// The measured corpus shape (proton facade_identity.mbt:95-101) is
///
///     try validate_application_identifier(identifier) catch {
///       InvalidField(expectation~, ..) =>
///         Err(InvalidSetting(name="identifier", message=expectation))
///       error => Err(InvalidSetting(name="identifier", message=error.message()))
///     } noraise {
///       identifier => Ok(identifier)
///     }
///
/// so there are two errors in one construct: the token `noraise` is undefined,
/// and everything inside the second block is invisible -- `identifier` is
/// mentioned nowhere else in that function, so reads there could not resolve and
/// could not make a parameter look unused.
///
/// THE GRAMMAR IS SETTLED, NOT ASSUMED. `_verify/settle_0441_noraise.ps1`, 8/8
/// as predicted with the positive control green:
///
///   - `noraise` REQUIRES a preceding `catch`; `try expr noraise { .. }` alone
///     is REJECTED by the compiler. The parser therefore nests the production
///     inside its `catch` arm instead of matching a bare keyword, which is both
///     faithful and keeps a user's own function named `noraise` from being
///     swallowed.
///   - the arm list is the SAME grammar as `catch`.
///   - an empty `noraise { }` is REJECTED.
///   - `noraise`'s pattern binds the BASE'S RESULT VALUE, not the error.
test "0442: a `noraise` handler is read, not read as a name" {
  let r = @pipeline.run(
    "fn fallible(n : Int) -> Int {\n  n\n}\n\nfn keep(a : Int) -> Int {\n  fallible(a) catch { _ => 0 } noraise { identifier => identifier + 1 }\n}\n",
    "nr.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(r.first_error_line, 0)
  assert_eq(count_family(r, "UndefinedName"), 0)
}

///|
/// AND THE DIRECTION THAT MATTERS MOST, because it is the one that produces a
/// FALSE POSITIVE rather than a missing one: a parameter read ONLY inside a
/// `noraise` body. Before this the block was consumed by `skip_braces`, so the
/// read was invisible and the parameter reported unread -- exactly the
/// `macos_native_ime.mbt:437` shape 0439 fixed for `catch`, one construct over.
///
/// Every parameter in this source is read in the function's ordinary tail, so the
/// ONLY thing that can produce a finding is the `noraise` body.
test "0442 control: a read only inside a `noraise` body is still a read" {
  let r = @pipeline.run(
    "fn fallible(n : Int) -> Int {\n  n\n}\n\nfn keep(a : Int, p : String) -> Int {\n  fallible(a) catch { _ => 0 } noraise { x => p.length() + x }\n}\n",
    "ctl.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(r.first_error_line, 0)
  assert_eq(count_family(r, "UnusedParam"), 0)
}

///|
/// THE RESULT-BINDING SHAPE, which is what makes the type lens able to say
/// anything here: the pattern binds the base's RESULT, so `x + 1` is the base's
/// type plus a literal. A `noraise` pattern bound to the error would make this
/// source a type error rather than a clean one, so a clean reading is itself
/// evidence of which value arrived.
test "0442: the `noraise` pattern binds the base's result value" {
  let r = @pipeline.run(
    "fn fallible(n : Int) -> Int {\n  n\n}\n\nfn keep(a : Int) -> Int {\n  fallible(a) catch { _ => 0 } noraise { x => x + 1 }\n}\n",
    "res.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(r.first_error_line, 0)
  assert_eq(count_family(r, "UndefinedName"), 0)
  assert_eq(count_family(r, "OperatorMismatch"), 0)
}

///|
/// SEVERAL ARMS, the same way `catch` takes several. proton's own `catch` block
/// directly above the `noraise` has two arms, so the two blocks sit side by side
/// and a reader that handled only one arm shape would be visible here.
test "0442: a `noraise` block takes several arms" {
  let r = @pipeline.run(
    "fn fallible(n : Int) -> Int {\n  n\n}\n\nfn keep(a : Int) -> Int {\n  fallible(a) catch { _ => 0 } noraise {\n    x => x + 1\n    _ => 0\n  }\n}\n",
    "two.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(r.first_error_line, 0)
  assert_eq(count_family(r, "UndefinedName"), 0)
}

///|
/// A BLOCK-BODIED ARM. `_verify/census_catch.ps1` says the expression form is the
/// COMMON one for `catch`, and proton's `noraise` blocks are expression-bodied --
/// but a block body is the form `catch` also accepts, so the two blocks do not
/// get to differ in what they can hold.
///
/// THE SOURCE IS A SINGLE TAIL EXPRESSION AND NOT `let y = .. ; y + 1`, and the
/// reason is worth recording rather than hiding. A `let` INSIDE a handler's block
/// body does not bind for the block's trailing expression, and MEASURED, this is
/// NOT A `noraise` DEFECT: the identical `catch` source reports the identical
///
///     no visible binding for 'y'
///
/// while the same `let` in an ordinary function body is clean. So the gap is in
/// `Parser::parse_block` as reached from `parse_catch_arms`, it predates 0442, and
/// it is a false positive on valid MoonBit. Pinning it here would have been
/// pinning a defect as if it were a contract, and "fixing" it inside this
/// increment would have meant shipping a `catch` behaviour change under a
/// `noraise` commit. It is a separate increment.
test "0442: a `noraise` arm can have a block body" {
  let r = @pipeline.run(
    "fn fallible(n : Int) -> Int {\n  n\n}\n\nfn keep(a : Int) -> Int {\n  fallible(a) catch { _ => 0 } noraise { x => {\n    x + 1\n  } }\n}\n",
    "blk.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(r.first_error_line, 0)
  assert_eq(count_family(r, "UndefinedName"), 0)
}

///|
/// AND THE SHAPE THE COMPILER REJECTS. `fallible(a) noraise { .. }` with no
/// `catch` is not MoonBit (`settle_0441_noraise.ps1`, case
/// `nr_without_catch`, REJECTED), so reporting it is CORRECT and pinning it is
/// what keeps the production from being loosened into a bare keyword match that
/// would swallow a user's own `noraise` function.
///
/// This is a test that asserts a finding, which is worth saying out loud: it is
/// not pinning a defect, it is pinning that the analyzer refuses a program the
/// compiler refuses, and it is the only thing that notices if that changes.
test "0442: `noraise` with no `catch` is still reported, as the compiler rejects it" {
  let r = @pipeline.run(
    "fn fallible(n : Int) -> Int {\n  n\n}\n\nfn keep(a : Int) -> Int {\n  fallible(a) noraise { _ => 1 }\n}\n",
    "nocatch.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "UndefinedName"), 1)
}

///|
/// THE OTHER DIRECTION, and it exists so that the two walk halves are killed by
/// DIFFERENT tests. The control above reads a name only inside the `noraise`
/// body; this one reads a name only inside the TRY EXPRESSION, and the `noraise`
/// arms read nothing of their own.
///
/// The node's base is the `ECatch`, not the original try expression, so skipping
/// `walk_expr(base)` in the `ENoRaise` arm discards the whole catch subtree --
/// including the read of `a`. An arm list that is walked but not bound, or bound
/// but not walked, is a different defect and is pinned by a different test; a
/// gate that named this one for both would have been satisfied by a fix to
/// either half.
test "0442: a read inside the try expression stays read through the `noraise` wrapper" {
  let r = @pipeline.run(
    "fn fallible(n : Int) -> Int {\n  n\n}\n\nfn keep(a : Int) -> Int {\n  fallible(a) catch { _ => 0 } noraise { _ => 0 }\n}\n",
    "base.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(r.first_error_line, 0)
  assert_eq(count_family(r, "UnusedParam"), 0)
}

///|
/// THE SHAPE THE CORPUS ACTUALLY WRITES, and the one that produced all four
/// findings. Every other test here uses the POSTFIX form
/// `expr catch { .. } noraise { .. }`; proton and async write a statement-level
/// `try` in front of it:
///
///     try validate_application_identifier(identifier) catch {
///       InvalidField(expectation~, ..) => Err(...)
///       error => Err(...)
///     } noraise {
///       identifier => Ok(identifier)
///     }
///
/// THAT IS A DIFFERENT PARSER PATH, and finding that out is why this test is
/// separate from the rest. `Parser::parse_postfix_from` reads a postfix `catch`
/// into an `@ast.ECatch`, and 0442 taught it `noraise` first -- with all seven
/// tests above green AND all four corpus findings STILL PRESENT. The statement
/// `try` lives in the prefix reader instead, and its catch loop consumes the
/// block with `skip_braces`, which left `noraise` stranded and resolved as a
/// name.
///
/// A GREEN SUITE AND AN UNCHANGED CORPUS ARE NOT THE SAME RESULT, and the second
/// is the one that matters. Had this been folded into test 1, the increment would
/// have shipped claiming to fix four findings and fixed none.
test "0442: a `noraise` after a statement-level `try` is not read as a name" {
  let r = @pipeline.run(
    "fn fallible(n : Int) -> Int {\n  n\n}\n\nfn keep(a : Int) -> Int {\n  try fallible(a) catch { _ => 0 } noraise { identifier => identifier + 1 }\n  0\n}\n",
    "stmttry.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "UndefinedName"), 0)
}
