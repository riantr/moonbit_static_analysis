//| Tests for 0.4.43: the LABEL recorded for a `label?=value` call argument.
//|
//| WHY THIS FILE EXISTS AND WHY IT IS NOT IN `src/pipeline`. The first version of
//| this increment tested the new `?=` form entirely through `@pipeline.run`, and
//| gate M4 -- dropping the label -- SURVIVED it, 623/623 green.
//!
//| The reason is not that the label is unimportant. It is that NOTHING on the
//| pipeline path READS it. `parse_call_args` returns `(args, labels)`, the labels go
//| into `ECall`, and neither the structural walk nor the type lens consults them for
//| any finding this corpus triggers. So a test that asserts findings cannot see a
//| dropped label -- not because the label does not matter, but because nothing
//| downstream has been wired to it yet.
//!
//| That is a property of the ANALYZER, not of the parser, and the parser's own tree
//| carries the label faithfully. So the assertion belongs here, reading `ECall`'s
//| third field directly, exactly as `parser_0430_test.mbt` does for `x~` and `x?`.
//|
//| THE CORRESPONDENCE MATTERS. All three spellings name the SAME parameter, and
//| `?=` must record the bare name beside the other two -- the settle
//| (`_verify/settle_0454_label_qmark_eq.ps1`, 9/9) establishes that `?=` and `=`
//| differ only in the TARGET's declared optionality, which is a call-site fact the
//| parser has no way to see. So the three tests below pin the same string, and a
//| fix that gave `?=` a decorated label would break all three in the same place.

///|
/// `ECall(String, Array[Expr], Array[String])` and `SFunc(name, params, ret, body,
/// span)` are read by position; the `else` arms fail loudly rather than letting an
/// empty match read as a pass. The `assert_true(seen)` at the end is what makes the
/// empty-match arms un-passable.
test "0454: the ?= argument carries the label 'border', not a blank one" {
  let r = @parser.parse(
    "fn sink(border? : Int) -> Int { 1 }\nfn pass(border? : Int) -> Int { sink(border?=7) }\n",
  )
  assert_eq(r.reports.length(), 0)
  let mut seen = false
  match r.tree.body[1].kind {
    @ast.SFunc(_, _, _, body, _) =>
      match body[0].kind {
        @ast.STail(e) =>
          match e.kind {
            @ast.ECall(name, args, labels) => {
              seen = true
              assert_eq(name, "sink")
              assert_eq(labels.length(), 1)
              assert_eq(labels[0], "border")
              // AND THE VALUE IS THERE, not just the label: one argument, and it
              // is the expression after the `=`. A label with no argument is the
              // shape a "recorded the name and forgot the value" bug takes, and
              // the count alone would not see it.
              assert_eq(args.length(), 1)
            }
            _ => ()
          }
        _ => ()
      }
    _ => ()
  }
  assert_true(seen)
}

///|
/// THE THREE SPELLINGS, PINNED TOGETHER, so they cannot drift. `x?=` is the new one;
/// `x=` and `x~` are the siblings that already existed. All three record the BARE
/// name, because `name? : T` is a single parameter and the `?` belongs to the
/// declaration, not to the argument's identity.
test "0454 control: the = and ~ spellings carry the same bare label" {
  let r = @parser.parse(
    "fn sink(border~ : Int) -> Int { 1 }\nfn a(border~ : Int) -> Int { sink(border=7) }\nfn b(border~ : Int) -> Int { let border = 1\nsink(border~) }\n",
  )
  assert_eq(r.reports.length(), 0)
  let mut seen = 0
  match r.tree.body[1].kind {
    @ast.SFunc(_, _, _, body, _) =>
      match body[0].kind {
        @ast.STail(e) =>
          match e.kind {
            @ast.ECall(_, _, labels) => {
              seen = seen + 1
              assert_eq(labels[0], "border")
            }
            _ => ()
          }
        _ => ()
      }
    _ => ()
  }
  match r.tree.body[2].kind {
    @ast.SFunc(_, _, _, body, _) =>
      match body[1].kind {
        @ast.STail(e) =>
          match e.kind {
            @ast.ECall(_, _, labels) => {
              seen = seen + 1
              assert_eq(labels[0], "border")
            }
            _ => ()
          }
        _ => ()
      }
    _ => ()
  }
  assert_eq(seen, 2)
}

///|
/// AND IN A CALL THAT MIXES THEM, because that is the shape the corpus writes and
/// the one where a blank label would send the argument back to positional index
/// matching. `views/popover/sheet.mbt:21-29` mixes `~`, `?` and `?=value` in one
/// call, so the labels have to survive a loop that touches all three.
test "0454: a mixed call labels every argument it names" {
  let r = @parser.parse(
    "fn sink(a~ : Int, b? : Int, c~ : Int) -> Int { 1 }\nfn pass(a~ : Int, c~ : Int) -> Int { let b : Int? = Some(2)\nsink(a~, b?=b, c~) }\n",
  )
  assert_eq(r.reports.length(), 0)
  let mut seen = false
  match r.tree.body[1].kind {
    // `body[1]`, NOT `body[0]`. The fixture needs a preceding `let b = ...` for the
    // `?=` value to have something to forward, and that `let` is a statement of its
    // own -- so the call is the SECOND statement. The first version navigated to
    // `body[0]` and read an `SLet` where it expected an `ECall`, fell through every
    // `else`, and failed on `assert_true(seen)` with no message about which arm
    // missed. `seen` is asserted precisely so that an empty match cannot read as a
    // pass, and it is also what makes an index mistake visible at all.
    @ast.SFunc(_, _, _, body, _) =>
      match body[1].kind {
        @ast.STail(e) =>
          match e.kind {
            @ast.ECall(_, args, labels) => {
              seen = true
              assert_eq(args.length(), 3)
              assert_eq(labels.length(), 3)
              assert_eq(labels[0], "a")
              assert_eq(labels[1], "b")
              assert_eq(labels[2], "c")
            }
            _ => ()
          }
        _ => ()
      }
    _ => ()
  }
  assert_true(seen)
}
