//| Tests for 0466 (`-> T noraise` / `-> T nocancel`) and 0466b (`.. rest` in an
//| array pattern) end to end, 0466-10.
//|
//| 0466 stopped the parse at the keyword and reported `expected '{'` AT THE BODY, on
//| 16 of the files still unread across the two corpora that have any.
//!
//| 0466b is the 0464b shape: 0466 unblocked
//| `moonbitlang/async 0.22.4 src/internal/event_loop/fs.mbt` (it had `-> Unit
//| nocancel` on two signatures) and the file then reported `undefined name
//| 'payload'` TWICE -- a name its own `guard! buf is [u32le(_), u32le(mask), ..
//| payload]` introduces.
//|
//| => 判据: a false positive nobody can reach is not a false positive that does not
//| exist. It is a finding whose file has not been read yet, and the only way to tell
//| the two apart is to unblock the corpus and look. The reach was legitimate, so the
//| GAP was fixed -- giving the reach back would mean refusing to read correct code.

//|

///|
/// THE CORPUS SHAPE, and the assertion is a FINDING COUNT rather than a parse
/// success. A parser that skipped the pattern and left `rest` unbound still parses;
/// what it produces is an `UndefinedName` two lines later, so only this assertion
/// separates the two.
test "0466b: a name bound by `.. rest` is not reported undefined" {
  let r = @pipeline.run(
    "///|\nfn fstatx_single(buf : Array[Int]) -> Array[Int] {\n  let mask = 0\n  guard! buf is [a, b, .. payload]\n  ignore(a)\n  ignore(b)\n  ignore(mask)\n  payload\n}\n",
    "rest.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "ParseError"), 0)
  assert_eq(count_family(r, "UndefinedName"), 0)
}

//|

///|
/// THE CANARY BESIDE IT, and this is the row that gives the one above meaning. Same
/// pattern; the use is of a name the pattern never mentions. If this reported zero,
// something was inventing bindings and the row above proved nothing.
test "0466b: a name the pattern never mentions is still reported" {
  let r = @pipeline.run(
    "///|\nfn f(buf : Array[Int]) -> Array[Int] {\n  guard! buf is [a, .. rest]\n  ignore(a)\n  ignore(rest)\n  nope\n}\n",
    "canary.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "UndefinedName"), 1)
}

//|

///|
/// 0466b ALSO HAS TO NOT BIND A CONSTRUCTOR HEAD. `Some(v)` binds `v` and not `Some`,
/// and binding the head would report an unused local for a constructor in every
/// pattern. Settled 7/7 in `_verify/settle_0460_array_pattern.ps1`.
///
/// This row pins THAT and does not pin the two-dot width. Mutation M3 was first
/// declared against it and the harness reported a MUST-RED MISS, correctly: a `match`
/// arm has no `..` and no path, so the row cannot see the difference between one dot
/// and two. The width is unobservable from outside -- `is Foo.bar` is REJECTed by the
/// toolchain with 4021 + 3002 -- and is proven that way instead.
test "0466b: a match constructor head is not bound, end to end" {
  let r = @pipeline.run(
    "///|\nfn f(x : Int) -> Int {\n  match x {\n    Some(v) => v\n    None => 0\n  }\n}\n",
    "ctor.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "UnusedParam"), 0)
  assert_eq(count_family(r, "UndefinedName"), 0)
}

//|

///|
/// 0466 -- both corpus spellings, with the return type used so the fixture is not
/// trivially parseable.
test "0466: `-> Unit noraise` and `-> Unit nocancel` report nothing" {
  let a = @pipeline.run(
    "///|\nasync fn acquire(self : Int) -> Int noraise {\n  self\n}\n",
    "noraise.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(a, "ParseError"), 0)
  assert_eq(count_family(a, "UnusedParam"), 0)
  let b = @pipeline.run(
    "///|\nasync fn remove(path : String) -> String nocancel {\n  path\n}\n",
    "nocancel.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(b, "ParseError"), 0)
  assert_eq(count_family(b, "UnusedParam"), 0)
}

//|

///|
/// THE CANARY FOR THE EFFECT SLOT, end to end. A parser that consumed whatever sat
/// between the return type and the brace would accept `-> Unit bogus`, which
/// `_verify/settle_0466_effect_annotation.ps1` row `ret_bogus_effect` REJECTs with
/// 3002. This row is what stops that shortcut from ever being introduced.
///
/// THE COUNT IS `>= 1` AND NOT `== 1`, and that is a measured fact rather than
/// slackness. The parser emits TWO ParseErrors here: `expected '{'` at `bogus`, and
/// one more from the statement parser reading `bogus` and the brace as code after it.
/// That cascade is the same shape 0465 fixed in the `..` arm, where it mattered
/// because a grouped message tally RANKS the remaining work and one defect counted as
/// two messages sends the next increment after a shape that does not exist.
///
/// It is not fixed here, and the reason is reach: no pinned corpus writes a
/// non-effect word after a return type, so the second report cannot appear in any
/// measured file. Fixing an unreachable path would be a change with no test that
/// could ever fail on real input, which is the trade the house rule refuses. If a
/// corpus ever grows the shape, this row's count is where it shows up first.
test "0466: a non-effect word after the return type reports a ParseError" {
  let r = @pipeline.run(
    "///|\nfn f() -> Unit bogus {\n  ()\n}\n",
    "bogus.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_true(count_family(r, "ParseError") >= 1)
}

//|
/// AND THE TWO SPELLINGS THAT ALREADY WORKED, kept as guards. `raise` is the control
// that made 0466 a two-keyword gap at all: proton has 781 `-> T raise` sites and was
// blocked at none of them, while the 16 files this increment unblocked were blocked at

///|
/// `noraise` and `nocancel` exactly. If `raise` ever regresses, that reasoning is no
/// longer evidence for anything.
test "0466: `raise` and `!` still report nothing" {
  let a = @pipeline.run(
    "///|\nfn f() -> Int raise {\n  1\n}\n",
    "raise.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(a, "ParseError"), 0)
  let b = @pipeline.run(
    "///|\nfn f() -> Int ! {\n  1\n}\n",
    "bang.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(b, "ParseError"), 0)
}
