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
//|   - `modifier_env.mbt` is a real, reproduced defect, and a different one: a
//|     lambda in an `if` BRANCH is not parsed. See the last test.
//
//| WHAT IS *NOT* CLAIMED. Nothing here asserts what breaks those three files.
//| Nine fixtures were tried against the cut-line shape -- with and without a
//| preceding `let`, parens and no parens, ascribed and not ascribed, one line and
//| many, qualified and unqualified method -- and all of them read cleanly. The
//| next move is to bisect one real file, not to guess at the construct again.

///|
fn any_parse_error_contains(
  r : @pipeline.PipelineResult,
  needle : String,
) -> Bool {
  for rep in r.reports {
    if rep.family.name() == "ParseError" && rep.message.contains(needle) {
      return true
    }
  }
  false
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
  assert_eq(count_family(r, "ParseError"), 0)
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
  assert_eq(count_family(r, "ParseError"), 0)
}

///|
/// WHAT *IS* REPRODUCED: a lambda in an `if` branch.
///
///     if disabled {
///       fn(_ctx) { .. }
///     } else {
///       fn(_ctx) { .. }
///     }
///
/// is valid MoonBit -- `_verify/settle_0450_shapes.ps1`, ACCEPT -- and this
/// parser reports `expected function name` at each `fn`. That is `modifier_env.mbt`
/// cut at `fn(_ctx) {`.
///
/// The name is wrong in a way worth stating: the token is not unexpected and
/// there IS a name. `parse_stmt` is being asked for a declaration and is handing
/// back a complaint about a function name it never wanted. A reader trusting the
/// message would look for a malformed function header and find none.
///
/// THIS TEST ASSERTS A DEFECT, deliberately. It pins today's behaviour so that
/// fixing it cannot land unnoticed: whoever fixes it must update this test in the
/// same commit, and the update is the evidence the defect is gone. The surrounding
/// tests assert the opposite direction -- that legal code keeps reading -- and a
/// suite that silently flipped all of them would be the real problem.
test "0450: a lambda in an if branch is not parsed (known defect)" {
  let r = @pipeline.run(
    "///|\nfn probe(disabled : Bool) -> (Int) -> Plan {\n  if disabled {\n    fn(_ctx) {\n      {\n        commands: 1,\n      }\n    }\n  } else {\n    fn(_ctx) { plan0() }\n  }\n}\n",
    "modifier_env.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(any_parse_error_contains(r, "expected function name"), true)
}

///|
/// THE CONTROL FOR THAT ONE, and the reason it is believable: the SAME `if` of
/// lambdas, with the struct-literal field wrapper the corpus puts around it,
/// fails the same way. The wrapper is not what breaks it.
///
/// And the narrowest control of all: a bare `{ .. }` struct literal as a whole
/// function body reads fine, so the two are not the same defect wearing one
/// hat -- which is the split this file exists to record.
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
  assert_eq(any_parse_error_contains(bare, "expected function name"), true)
  assert_eq(any_parse_error_contains(wrapped, "expected function name"), true)
}
