// Tests for 0.4.25: the behaviour lens joined the flow of an `if`'s branches.
//
// Found while measuring 0.4.24's `SRaise`, and NOT caused by it: the defect
// reproduces with no `raise` anywhere. The lens explores an unknown condition's
// branches ONE AFTER ANOTHER in the same `Interp`, so the flow state simply
// carried over between them -- a branch that terminated made the next branch's
// first statement look unreachable, and whatever the LAST branch left behind was
// what survived past the whole `if`.
//
// The falsest case is the shortest. `guard` is modelled as an `SIf` with an EMPTY
// then-branch, so:
//
//     guard g is Some(v) else { return 0 }
//     return v
//
// reported `return v` as `unreachable code`. The else terminates, the then does
// not, and the else's flow won the race. This is the shape
// `moonbit-community/proton` 0.3.4 `facade_app_metadata.mbt:81-82` has, with a
// `raise` in the else instead of a `return`.
//
// MEASURED, and stated plainly because a zero is easy to misread: across the
// six corpora, 12,428 files, this change moves NOTHING. Every scan is
// byte-identical before and after. Zero `Unreachable` findings existed before it
// and zero exist after. So this is a correctness fix with a reproducer and no
// corpus delta, not a claim that it cleaned up anything it can be measured
// cleaning up.
//
// ---------------------------------------------------------------------------
// HOW A FIXTURE REACHES THE JOIN, because getting this wrong is invisible
// ---------------------------------------------------------------------------
//
// The join lives in the `cv` arm of `SIf` -- the arm for a condition that is
// NEITHER `ABool(true)` nor `ABool(false)`. Two shapes miss it:
//
//   `f(1)`, `if n > 0`  -> `n` binds to `AInt(1)`, `binop` folds `n > 0` to
//                          `ABool(true)`, and the then-branch runs ALONE. Three
//                          mutations survived the first gate because of exactly
//                          this, while the tests looked perfectly reasonable.
//   `f(g())`, undefined  -> the call returns `ABottom`, `n > 0` is `ABottom`,
//                          and the whole body goes quiet. Looks like "no
//                          findings", which is indistinguishable from a pass.
//
// What DOES work, and is used below:
//
//   `s == "a"`          -> `binop`'s `OpEq | OpNe` arm returns `AType("bool")`
//                          unconditionally; there is no string arm to fold with.
//   `f(@core.nothing)`  -> an `@`-prefixed name is `AAny`, and `binop` lets
//                          `AAny` absorb to `AType("bool")`.
//   `x is Some(v)`      -> `EIs` returns `AAny` on purpose, so every `guard` in
//                          real code already reaches the join.
//
// The string shape is the only one of the three that reads like ordinary code,
// so the fixtures use it -- and the folding test is the control that proves the
// folding is real: same shape, folded argument, OPPOSITE expected count.
// Without it, these fixtures would also pass against an analyzer that never
// entered the join.

// ---------------------------------------------------------------------------
// A — the false positives this removes
// ---------------------------------------------------------------------------

///|
/// THE SHORTEST REPRODUCER, and the one with no `raise` in it at all.
///
/// `guard` becomes `SIf(cond, [], [], els)`, so the then-branch is empty and
/// never terminates, while the else returns. Reporting `return v` as
/// unreachable is simply wrong: when `g` is `Some(v)` the guard passes and
/// control reaches it.
test "0425: a guard whose else returns does not make the code after it dead" {
  let r = @pipeline.run(
    "fn f(g : Int?) -> Int {\n  guard g is Some(v) else {\n    return 0\n  }\n  return v\n}\nlet x = f(1)\n",
    "guard_else_return.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "Unreachable"), 0)
}

///|
/// THE SAME SHAPE WITH A `raise` IN THE ELSE, which is what 0.4.24 introduced
/// the risk of: once `raise` terminates a frame, every `guard ... else { raise }`
/// in real code would have started reporting its continuation as dead. This is
/// the fixture that says it does not.
test "0425: a guard whose else raises does not make the code after it dead" {
  let r = @pipeline.run(
    "suberror E {\n  E(Int)\n}\nfn f(g : Int?) -> Int raise E {\n  guard g is Some(v) else {\n    raise E(0)\n  }\n  return v\n}\nlet x = f(1)\n",
    "guard_else_raise.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "Unreachable"), 0)
}

///|
/// A MISSING `else` ALWAYS falls through -- when no condition holds, nothing
/// runs and control continues -- so it must not make the following statement
/// look dead either.
///
/// The argument is the string `"a"` ON PURPOSE. See the folding note above:
/// `f(1)` folds `s > 0` to true, takes the then-branch, and `return 2` IS
/// unreachable for that call -- correct, and pinned by the folding test further
/// down. Only a condition the abstract interpreter cannot fold separates "no
/// else means fall through" from "this branch really did terminate", which is
/// exactly the decision M1 mutates.
test "0425: a missing else falls through even when the then-branch returns" {
  let r = @pipeline.run(
    "fn f(s : String) -> Int {\n  if s == \"a\" {\n    return 1\n  }\n  return 2\n}\nlet x = f(\"a\")\n",
    "no_else_falls_through.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "Unreachable"), 0)
}

// ---------------------------------------------------------------------------
// B — and the true dead code it must NOT silence
// ---------------------------------------------------------------------------

///|
/// EVERY BRANCH TERMINATING IS REAL DEAD CODE. If the join were written as
/// "always fall through", this would go quiet, and that failure is worse than
/// the false positive being fixed: it is a check that can never fire.
test "0425: code after an if where every branch terminates is still dead" {
  let r = @pipeline.run(
    "fn f(s : String) -> Int {\n  if s == \"a\" {\n    return 1\n  } else {\n    return 2\n  }\n  return 3\n}\nlet x = f(\"a\")\n",
    "both_terminate.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "Unreachable"), 1)
}

///|
/// THE `else if` CHAIN IS THE HARDER VERSION of the same thing, because every
/// branch has to be visited for the join to know whether any of them falls
/// through. Here all three return, so `return 4` is dead.
test "0425: an else-if chain where every branch terminates is still dead" {
  let r = @pipeline.run(
    "fn f(s : String) -> Int {\n  if s == \"a\" {\n    return 1\n  } else if s == \"b\" {\n    return 2\n  } else {\n    return 3\n  }\n  return 4\n}\nlet x = f(\"a\")\n",
    "elseif_all_terminate.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "Unreachable"), 1)
}

///|
/// THE JOIN HAS TO LOOK PAST THE FIRST BRANCH, which is the one thing a "join"
/// that only reads a single branch cannot do.
///
/// The chain reaches `exec_alt` because the OUTER condition `n > 0` folds to
/// FALSE for `-1`; the else-if conditions stay unfolded, so `exec_alt` enters
/// its own unknown-condition arm. There the FIRST else-if returns and the SECOND
/// falls through -- so the answer is "falls through" and `return 5` is live.
///
/// A join that stops after the first else-if reads "terminated" and silences
/// this. That is mutation M5.
test "0425: an else-if chain whose later branch falls through stays live" {
  let r = @pipeline.run(
    "fn f(n : Int, s : String) -> Int {\n  if n > 0 {\n    return 1\n  } else if s == \"a\" {\n    return 2\n  } else if s == \"b\" {\n    let _ = 3\n  } else {\n    return 4\n  }\n  return 5\n}\nlet x = f(-1, \"a\")\n",
    "chain_later_branch_falls.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "Unreachable"), 0)
}

///|
/// THE OPPOSITE, THROUGH THE SAME PATH. One else-if, and it returns; the `else`
/// returns too. So every branch of the chain terminates and `return 5` is dead.
///
/// This is what says `exec_alt` is allowed to say "terminated" at all. A version
/// of it that always reported fall-through -- M6 -- would make the check
/// unfireable in the one direction that matters.
test "0425: a chain that reaches exec_alt and returns everywhere is still dead" {
  let r = @pipeline.run(
    "fn f(n : Int, s : String) -> Int {\n  if n > 0 {\n    return 1\n  } else if s == \"a\" {\n    return 2\n  } else {\n    return 4\n  }\n  return 5\n}\nlet x = f(-1, \"a\")\n",
    "chain_all_return.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "Unreachable"), 1)
}

///|
/// NO `else` AT ALL, ONE LEVEL DOWN. The chain is the same shape but the `else`
/// is missing and the only else-if falls through. When no condition holds,
/// nothing runs and control continues, so `return 3` is live -- M7 turns this
/// into a false `unreachable code`.
test "0425: a chain with no else at all falls through" {
  let r = @pipeline.run(
    "fn f(n : Int, s : String) -> Int {\n  if n > 0 {\n    return 1\n  } else if s == \"a\" {\n    let _ = 2\n  }\n  return 3\n}\nlet x = f(-1, \"a\")\n",
    "chain_no_else.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "Unreachable"), 0)
}

///|
/// THE SAME TWO DECISIONS WITH NO ELSE-IF AT ALL, which is the only way to
/// reach `exec_alt`'s TERMINAL `match els` -- a different block from the one
/// above, reached when `idx < elseifs.length()` is already false on entry.
///
/// The `else` returns, so `exec_alt` has to be able to say "terminated", and
/// `return 3` is dead. M6 makes this arm report fall-through unconditionally,
/// which is why the previous version of this file -- in which every chain had an
/// else-if -- let M6 survive while every test still passed.
test "0425: a false condition whose else returns leaves the rest dead" {
  let r = @pipeline.run(
    "fn f(n : Int) -> Int {\n  if n > 0 {\n    return 1\n  } else {\n    return 2\n  }\n  return 3\n}\nlet x = f(-1)\n",
    "false_cond_else_returns.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "Unreachable"), 1)
}

///|
/// AND ITS `None` SIBLING: the same terminal block, but with no else at all.
/// Nothing runs when the condition is false, so `return 2` is live. M8 turns
/// this into a false `unreachable code`.
///
/// This is the fourth statement that decides "a missing else falls through".
/// The other three -- `SIf`'s join, `exec_alt`'s inner `match`, and `exec_alt`'s
/// terminal `None` -- are separate lines in the source with separate mutations,
/// so they need separate fixtures. A single "the else is optional" test would
/// have left three of the four unobserved.
test "0425: a false condition with no else at all falls through" {
  let r = @pipeline.run(
    "fn f(n : Int) -> Int {\n  if n > 0 {\n    return 1\n  }\n  return 2\n}\nlet x = f(-1)\n",
    "false_cond_no_else.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "Unreachable"), 0)
}

///|
/// THE CONSTANT-FOLDING CASE, which is what makes the two tests above mean
/// something rather than accidentally agree.
///
/// Same SHAPE as "a missing else falls through" -- `if` with no `else`,
/// then-branch returns, one statement after -- but a folded argument. `f(1)`
/// lets the interpreter fold `n > 0` to true, take the then-branch, and report
/// the rest of the body as dead -- correctly, because for THAT call nothing else
/// is reachable.
///
/// The expected count is the OPPOSITE of that test's. That inversion is the
/// proof that the string fixtures reach the join and this one reaches the folded
/// arm: an earlier version of this file used `f(1)` for BOTH, so its "control"
/// was re-testing constant folding and looked like it proved something about
/// `else`.
test "0425: a folded condition makes the untaken branch's continuation dead" {
  let r = @pipeline.run(
    "fn f(n : Int) -> Int {\n  if n > 0 {\n    return 1\n  }\n  return 2\n}\nlet x = f(1)\n",
    "folded_condition.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "Unreachable"), 1)
}

///|
/// A RAISE STILL TERMINATES, unchanged by any of this. `SRaise` sets the flow
/// to `FReturn` and a raise is a terminator whether or not it sits inside a
/// branch, so this pins that the join did not quietly turn raises into
/// fall-throughs on its way past.
test "0425: a raise still terminates the frame (control)" {
  let r = @pipeline.run(
    "suberror E {\n  E(Int)\n}\nfn f() -> Int raise E {\n  raise E\n  return 1\n}\nlet x = f()\n",
    "raise_still_terminates.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "Unreachable"), 1)
}
