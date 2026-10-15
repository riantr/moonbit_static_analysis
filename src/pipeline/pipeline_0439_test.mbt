///|
/// 0439: a parameter read only inside a `catch` handler is now SEEN.
///

///|
/// THIS IS THE FINDING-LEVEL TEST, and it is the only assertion in this
/// increment that could have caught the defect.
///
/// The parser tests (`parser_0439_test.mbt`) pin the SHAPE: that an arm's
/// bindings and statements are in the tree. They cannot be the ones to prove the
/// read, because `skip_braces` also produced a clean parse — the old code
/// reported nothing and left the token stream in step, so "it parses" was true
/// of the parser that threw the handler away.
///
/// The observable is `FUnusedParam`, and its reason for being delicate is
/// recorded in `pipeline_0433_test.mbt`: a `match` body puts a hole in the
/// frame and `audit_frame` is skipped for the WHOLE function, which makes
/// `UnusedParam` assertions over a `match` vacuous — they pass because the
/// family was switched off, not because anything was read. The obvious cheap fix
/// for a catch arm was exactly that trick (`note_skip` on the handler), and it
/// would have made this file's first assertion pass while proving nothing.
///
/// SO THE CONTROL IS THE POINT OF THE WHOLE FILE. Every positive assertion here
/// is a `count_family(..., "UnusedParam") == 0`, and a parser that silently
/// disabled the family would produce every one of them. Each positive therefore
/// has a negative that differs by ONE unread parameter and must report 1. If
/// the family were switched off, the negatives would go red; if the catch body
/// were being skipped, the positives would go red.

///|
/// The measured case. wzzc-dev/moui `backend/macos/macos_native_ime.mbt:437`:
/// `prefix~` is read only inside `catch { err => { ... } }`.
test "0439: a parameter read only inside a catch arm is not reported unused" {
  let r = @pipeline.run(
    "fn call() -> Int { 1 }\nfn f(prefix : String) -> Int {\n  call() catch {\n    err => {\n      println(prefix)\n      0\n    }\n  }\n}\n",
    "x.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(r.first_error_line, 0)
  assert_eq(count_family(r, "UnusedParam"), 0)
}

///|
/// THE CONTROL. The same source with ONE more parameter that nothing reads.
/// It must still be reported — that is what proves the family is ON and that
/// the zero above is a fact about `prefix` rather than about the family.
test "0439 control: an unread parameter beside a read one is still reported" {
  let r = @pipeline.run(
    "fn call() -> Int { 1 }\nfn f(prefix : String, spare : Int) -> Int {\n  call() catch {\n    err => {\n      println(prefix)\n      0\n    }\n  }\n}\n",
    "x.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(r.first_error_line, 0)
  assert_eq(count_family(r, "UnusedParam"), 1)
}

///|
/// AN EXPRESSION-BODIED ARM, which is the COMMON one — 45 of moui's 54 handler
/// sites and 273 of proton's 323 (`_verify/census_catch.ps1`). The control
/// above uses a block body because that is the shape moui:437 has; if the
/// expression form had been missed, the fix would have passed the corpus check
/// and failed here.
test "0439: a parameter read only inside an expression-bodied catch arm is seen" {
  let r = @pipeline.run(
    "fn call() -> Int { 1 }\nfn f(prefix : String) -> Int {\n  call() catch { _ => prefix.length() }\n}\n",
    "x.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(r.first_error_line, 0)
  assert_eq(count_family(r, "UnusedParam"), 0)
}

///|
/// THE CONTROL for that one, on the same axis as the first: one unread
/// parameter beside the read one.
test "0439 control: an unread parameter beside an expression-bodied catch arm is reported" {
  let r = @pipeline.run(
    "fn call() -> Int { 1 }\nfn f(prefix : String, spare : Int) -> Int {\n  call() catch { _ => prefix.length() }\n}\n",
    "x.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(r.first_error_line, 0)
  assert_eq(count_family(r, "UnusedParam"), 1)
}

///|
/// THE OTHER DIRECTION, and the one a superset could plausibly break.
/// `Parser::parse_catch_pattern` returns EVERY name in the pattern text, so
/// `catch Boom(n) => ...` carries both `Boom` and `n`. `Boom` is a variant, not
/// a variable. If `Walker::bind_pattern` put those names in the frame the way
/// `bind` does, `Boom` would be audited with no reads and reported as
/// `local variable 'Boom' assigned but may not be used` — a NEW false positive,
/// manufactured by the fix, in exchange for removing an old one.
///
/// This is the `ECast`/`EComp` lesson in its second form: both halves of the
/// change have to be checked, not just the one that was the point.
test "0439: a catch pattern's constructor name is not reported as an unused local" {
  let r = @pipeline.run(
    "fn call() -> Int { 1 }\nfn f() -> Int {\n  call() catch {\n    Boom(n) => n\n    _ => 0\n  }\n}\n",
    "x.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(r.first_error_line, 0)
  assert_eq(count_family(r, "UnusedLocal"), 0)
}

///|
/// THE CONTROL for that. A `let` that genuinely is never read must still be
/// reported, or the assertion above only says `FUnusedLocal` is off.
test "0439 control: a genuinely unread local beside a catch arm is reported" {
  let r = @pipeline.run(
    "fn call() -> Int { 1 }\nfn f() -> Int {\n  let dead = 1\n  call() catch {\n    Boom(n) => n\n    _ => 0\n  }\n}\n",
    "x.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(r.first_error_line, 0)
  assert_eq(count_family(r, "UnusedLocal"), 1)
}

///|
/// AND THE OTHER DIRECTION AGAIN: the pattern's name must RESOLVE. Reading the
/// body without binding the pattern is what would manufacture
/// `no visible binding for 'err'` on correct code — the reason `parse_atom`'s
/// `try` arm skips its handlers whole. This asserts the binding happened, by
/// naming a function the arm calls that exists nowhere else.
test "0439: a handler body can use the name its own pattern bound" {
  let r = @pipeline.run(
    "fn call() -> Int { 1 }\nfn describe(err : String) -> Int { err.length() }\nfn f() -> Int {\n  call() catch {\n    e => describe(e)\n    _ => 0\n  }\n}\n",
    "x.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(r.first_error_line, 0)
  assert_eq(count_family(r, "UndefinedName"), 0)
}

///|
/// THE CONTROL for THAT one: the same call with the binding removed from the
/// pattern's use. This must go red — if it did not, the test above would only be
/// saying `UndefinedName` is off.
test "0439 control: an unresolvable name in a handler body is still reported" {
  let r = @pipeline.run(
    "fn call() -> Int { 1 }\nfn describe(err : String) -> Int { err.length() }\nfn f() -> Int {\n  call() catch {\n    _ => describe(nowhere)\n  }\n}\n",
    "x.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(r.first_error_line, 0)
  assert_eq(count_family(r, "UndefinedName"), 1)
}
