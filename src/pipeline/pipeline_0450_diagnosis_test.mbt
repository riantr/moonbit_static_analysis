//| DIAGNOSIS for the next increment, and the split that corrects a ranking.
//
//| `_verify/diagnose_moui_truncations.ps1` buckets the four "bare brace /
//| lambda body" truncations together. They are TWO defects, and the bucket is
//| wrong. This file pins the measurements that split them, because both halves
//| were wrong in opposite directions before it was measured:
//
//|   - The three `{`-cut files (host_transport, session_transport,
//|     macos_accessibility_bridge) were assumed to fail because of the
//     parenthesised struct literal at their cut line. IT IS NOT THE CAUSE. The
//     construct is valid MoonBit -- settled, `_verify/settle_0450_shapes.ps1` --
//|     AND the parser reads it, which is what the first two tests below assert.
//|     A construct that parses in isolation cannot be what stops a file that
//     contains it, so the cause in those three files is EARLIER CONTEXT that has
//|     not been isolated. Do not read "the read stops here" as "the parser cannot
//|     read this": that script already warns about the two being different claims,
//|     and here they demonstrably are.
//|   - `modifier_env.mbt` was a real, reproduced defect, and is FIXED here: a
//|     lambda in an `if` BRANCH is not parsed. One condition in `parse_block`.
//|     Its tests asserted the failure for one commit and flipped in the same
//|     commit that fixed it, which is the evidence -- see below.
//
//| WHAT IS *NOT* CLAIMED. Nothing here asserts what breaks those three files.
//| Nine fixtures were tried against the cut-line shape -- with and without a
//| preceding `let`, parens and no parens, ascribed and not ascribed, one line and
//| many, qualified and unqualified method -- and all of them read cleanly. The
//| next move is to bisect one real file, not to guess at the construct again.

///|
/// Parse FAILURES, excluding the DECLARED SCOPE LIMITS.
///
/// The subset has no closure node and does not analyse `if` expressions, so both
/// are read and then reported -- and those notices share the `ParseError` family
/// with real read failures. So `count_family(r, "ParseError") == 0` is the wrong
/// assertion for these fixtures: it counts a deliberate, correct notice as if it
/// were a defect, and an assertion that cannot tell the two apart is an assertion
/// about the family rather than about the code.
///
/// The exclusion is the pipeline's OWN rule, not one invented here:
/// `pipeline.mbt:143` filters on `"outside the analyzed subset"` and documents
/// why that is exact -- all seven parser skip messages carry it and no read
/// failure does. Reusing the substring is the point; a hand-rolled list of the
/// two notices this file happened to meet would pass today and miss the other five.
fn parse_failures(r : @pipeline.PipelineResult) -> Int32 {
  let mut n = 0
  for rep in r.reports {
    if rep.family.name() == "ParseError" &&
      !rep.message.contains("outside the analyzed subset") {
      n += 1
    }
  }
  n
}

///|
/// THE SHAPE AT THE CUT LINE, verbatim apart from the quoted keys -- which this
/// analyzer's struct literals do not accept, so the probe uses a plain struct
/// with the same two fields. Settled as ACCEPT by `moon check`.
///
/// It reads cleanly. That is the load-bearing claim, and it is the opposite of
/// what the ranking implied.
test "0450: a parenthesised ascribed struct literal reads cleanly" {
  let r = @pipeline.run(
    "///|\nfn probe() -> String {\n  (\n    {\n      schemaVersion: 1,\n      sessionGeneration: 2,\n    } : Json).stringify()\n}\n",
    "s1.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(parse_failures(r), 0)
}

///|
/// AND WITH THE CORPUS'S LEADING CONTEXT -- a `let` statement, then the
/// parenthesised literal as the function's tail. This is the real shape.
///
/// This was the ninth fixture tried, and the one before it (the same tail with
/// no preceding `let`) reads cleanly too, so the pair looked like the
/// discrimination until the report was read rather than counted: the only
/// finding either produces is `UnusedLocal` on the probe's own `e`. Neither
/// fails to parse. Pinning it here because "valid MoonBit" and "read by this
/// parser" are separate claims and only the second one was ever in doubt.
test "0450: the let-then-parenthesised-literal shape reads cleanly" {
  let r = @pipeline.run(
    "///|\nfn probe() -> String {\n  let e = 1\n  (\n    {\n      schemaVersion: 1,\n      sessionGeneration: 2,\n    } : Json).stringify()\n}\n",
    "s1e.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(parse_failures(r), 0)
}

///|
/// THE DEFECT, NOW FIXED. This test asserted the failure for one commit and its
/// own comment said what would happen when the defect went away: the assertion
/// flips in the SAME commit, and that flip is the evidence it is gone rather than
/// suppressed.
///
/// The change is one condition in `Parser::parse_block`. A `fn` in statement
/// position was routed unconditionally to the declaration path, so a lambda fell
/// into `parse_fn_signature`, which asks for a name, found `(`, and reported
/// `expected function name` at a token that is neither unexpected nor unnamed.
/// The token after `fn` is the whole discriminator -- a NAME means a local
/// function declaration, `(` means a lambda expression.
///
/// It only ever surfaced in a branch because expression position always worked:
/// `let f = fn(x) { .. }` reaches `parse_primary`'s lambda branch, while a
/// lambda that is the tail of an `if` branch is a block STATEMENT. moui's
/// `modifier_env.mbt` is written that way.
test "0450: a lambda in an if branch is parsed" {
  let r = @pipeline.run(
    "///|\nfn probe(disabled : Bool) -> (Int) -> Plan {\n  if disabled {\n    fn(_ctx) {\n      {\n        commands: 1,\n      }\n    }\n  } else {\n    fn(_ctx) { plan0() }\n  }\n}\n",
    "modifier_env.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(parse_failures(r), 0)
  // ... and the complementary claim, which is what makes the first one mean
  // something: TWO lambdas in the fixture, TWO notices. The notice is emitted
  // after the literal's parameters and body have been read, so counting them is
  // how the test knows both were reached. `parse_failures == 0` alone would also
  // be satisfied by skipping the region without looking at it.
  assert_eq(count_family(r, "ParseError"), 2)
}

///|
/// THE CONTROL FOR THE FIX, and the reason it can be believed: the two forms
/// share a token and differ only in what follows it, so a fix that simply stopped
/// treating `fn` as a declaration would pass the test above while losing every
/// named local function. This one is that loss, named.
test "0450: a named function declared inside a block is still a declaration" {
  let r = @pipeline.run(
    "///|\nfn probe() -> Int {\n  fn add(a : Int, b : Int) -> Int {\n    a + b\n  }\n  add(1, 2)\n}\n",
    "local_fn.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(parse_failures(r), 0)
}

///|
/// BOTH IN ONE BLOCK, which is the case neither control covers on its own: the
/// discriminator has to keep working after the first `fn` has been consumed, and
/// not just at the start of a block.
test "0450: a named local function and a lambda coexist in one block" {
  let r = @pipeline.run(
    "///|\nfn probe() -> Int {\n  fn add(a : Int, b : Int) -> Int {\n    a + b\n  }\n  let f = fn(x) { add(x, 1) }\n  f(1)\n}\n",
    "mixed.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(parse_failures(r), 0)
}

///|
/// AND THE WRAPPER IS STILL NOT THE VARIABLE. With the struct-literal field the
/// corpus wraps this in, both the bare and the wrapped form read cleanly -- which
/// is the control that said the wrapper was never what broke it.
test "0450: the if-of-lambdas shape does not depend on the struct wrapper" {
  let bare = @pipeline.run(
    "///|\nfn probe(disabled : Bool) -> (Int) -> Plan {\n  if disabled {\n    fn(_ctx) {\n      {\n        commands: 1,\n      }\n    }\n  } else {\n    fn(_ctx) { plan0() }\n  }\n}\n",
    "bare.mbt",
    @core.IfaceSymTab::empty(),
  )
  let wrapped = @pipeline.run(
    "///|\nfn probe(disabled : Bool) -> View {\n  {\n    paint: if disabled {\n      fn(_ctx) {\n        {\n          commands: 1,\n        }\n      }\n    } else {\n      fn(_ctx) { plan0() }\n    },\n  }\n}\n",
    "wrapped.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(parse_failures(bare), 0)
  assert_eq(parse_failures(wrapped), 0)
}
