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
/// The chain reaches `exec_alt` because the OUTER condition folds to FALSE;
/// the else-if conditions stay unfolded, so `exec_alt` enters its own
/// unknown-condition arm. There the FIRST else-if returns and the SECOND falls
/// through -- so the answer is "falls through" and `return 5` is live.
///
/// A join that stops after the first else-if reads "terminated" and silences
/// this. That is mutation M5.
///
/// 0543. THE OUTER CONDITION USED TO BE `n > 0`, WHICH FOLDED TO FALSE FOR
/// `n = -1`. IT DOES NOT ANY MORE, AND THIS ROW WAS VACUOUS FOR ELEVEN DAYS
/// BECAUSE OF IT.
///
/// 0537 made a condition that names a CALLER-BOUND PARAMETER explore BOTH
/// sides: `n` is a parameter, its value comes from the call site, so `n > 0`
/// is no longer folded to a constant and the ELSE branch is no longer taken
/// alone. `exec_alt` is reached ONLY from the folded-false arm
/// (`interp.mbt`: `self.flow = self.exec_alt(elseifs, els, env, 0)` is the
/// `ABool(false)` arm), so after 0537 this fixture never entered `exec_alt`
/// at all -- and the row still passed, because the INLINE chain handling
/// reaches the same verdict. A test that passes for a different reason is
/// worse than a test that fails: it looks like coverage and is not.
///
/// The condition is now a LITERAL COMPARISON, which folds whatever the
/// parameter's value is, and the pair below is the control that proves the
/// fold is what decides: same shape, the comparison the other way round, and
/// the OPPOSITE expected count.
test "0425: an else-if chain whose later branch falls through stays live" {
  let r = @pipeline.run(
    "fn f(s : String) -> Int {\n  if 1 > 2 {\n    return 1\n  } else if s == \"a\" {\n    return 2\n  } else if s == \"b\" {\n    let _ = 3\n  } else {\n    return 4\n  }\n  return 5\n}\nlet x = f(\"a\")\n",
    "chain_later_branch_falls.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "Unreachable"), 0)
}

///|
/// THE CONTROL FOR THE ROW ABOVE, and the reason that row is worth anything.
///
/// Same program, and the OUTER CONDITION IS TRUE instead of false, so the
/// then-branch runs ALONE and `exec_alt` is never reached. The then-branch
/// returns, so the code after the chain is dead -- the OPPOSITE expected
/// count.
///
/// The two rows together say the fold decides which chain is walked, and the
/// control is what makes the first row's zero a fact about the analyzer
/// rather than a fact about a fixture that never arrived.
test "0425: a chain whose outer condition is true never reaches the else-if" {
  let r = @pipeline.run(
    "fn f(s : String) -> Int {\n  if 2 > 1 {\n    return 1\n  } else if s == \"a\" {\n    return 2\n  } else if s == \"b\" {\n    let _ = 3\n  } else {\n    return 4\n  }\n  return 5\n}\nlet x = f(\"a\")\n",
    "chain_outer_true.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "Unreachable"), 1)
}

///|
/// THE OPPOSITE, THROUGH THE SAME PATH. One else-if, and it returns; the `else`
/// returns too. So every branch of the chain terminates and `return 5` is dead.
///
/// This is what says `exec_alt` is allowed to say "terminated" at all. A version
/// of it that always reported fall-through -- M6 -- would make the check
/// unfireable in the one direction that matters.
///
/// 0543. THE OUTER CONDITION WAS `n > 0`, WHICH STOPPED FOLDING TO FALSE IN
/// 0537, so this row stopped reaching `exec_alt` while still passing. It is a
/// LITERAL COMPARISON now, for the same reason as the rows above.
test "0425: a chain that reaches exec_alt and returns everywhere is still dead" {
  let r = @pipeline.run(
    "fn f(s : String) -> Int {\n  if 1 > 2 {\n    return 1\n  } else if s == \"a\" {\n    return 2\n  } else {\n    return 4\n  }\n  return 5\n}\nlet x = f(\"a\")\n",
    "chain_all_return.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "Unreachable"), 1)
}

///|
/// NO `else` AT ALL, ONE LEVEL DOWN. The chain is the same shape but the `else`
/// is missing. When no condition holds, nothing runs and control continues, so
/// `return 3` is live -- M7 turns this into a false `unreachable code`.
///
/// 0543. THIS ROW HAD TWO DEFECTS, and it is the one that made M7 survivable.
///
/// 1. The OUTER CONDITION was `n > 0`, which stopped folding to false in 0537
///    (a caller-bound parameter's condition is explored on both sides now), so
///    the fixture stopped reaching `exec_alt` altogether.
///
/// 2. The ONLY ELSE-IF DID NOT RETURN. It was `let _ = 2`, and a branch that
///    does not terminate leaves the flow at FNormal by itself -- so the
///    missing-else arm contributed nothing that the branch had not already
///    contributed, and REMOVING that arm could not change the verdict. The
///    row claimed "M7 turns this into a false `unreachable code`" and that was
///    not true of the program it ran: M7 could not have done anything to it.
///
///    The else-if now RETURNS, which is the only shape in which "the chain
///    falls through because there is no else" is a decision the missing-else
///    arm makes rather than one the branch makes by accident.
test "0425: a chain with no else at all falls through" {
  let r = @pipeline.run(
    "fn f(s : String) -> Int {\n  if 1 > 2 {\n    return 1\n  } else if s == \"a\" {\n    return 2\n  }\n  return 3\n}\nlet x = f(\"a\")\n",
    "chain_no_else.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "Unreachable"), 0)
}

///|
/// THE CONTROL FOR THE ROW ABOVE: the same program with the outer condition
/// TRUE, so the then-branch runs alone and the chain is never walked. The
/// then-branch returns, so the code after it is dead -- the OPPOSITE count.
test "0425: a chain with no else at all is dead when its outer condition is true" {
  let r = @pipeline.run(
    "fn f(s : String) -> Int {\n  if 2 > 1 {\n    return 1\n  } else if s == \"a\" {\n    return 2\n  }\n  return 3\n}\nlet x = f(\"a\")\n",
    "chain_no_else_outer_true.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "Unreachable"), 1)
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
///
/// 0543. THE OUTER CONDITION WAS `n > 0`, WHICH STOPPED FOLDING TO FALSE IN
/// 0537 (a caller-bound parameter's condition is explored on both sides now),
/// so this row stopped reaching `exec_alt` and M6 became unobservable here
/// too. It is a LITERAL COMPARISON now, which folds whatever the parameter's
/// value is, and the control below says the same program with a FALLING-THROUGH
/// `else` gives the opposite answer.
test "0425: a false condition whose else returns leaves the rest dead" {
  let r = @pipeline.run(
    "fn f() -> Int {\n  if 1 > 2 {\n    return 1\n  } else {\n    return 2\n  }\n  return 3\n}\nlet x = f()\n",
    "false_cond_else_returns.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "Unreachable"), 1)
}

///|
/// THE CONTROL FOR THE ROW ABOVE, and the row that makes it mean something:
/// the same program with an `else` that does NOT terminate. The chain falls
/// through, so `return 3` is live -- the OPPOSITE expected count.
///
/// The pair says the terminal `else`'s FLOW is what decides, which is exactly
/// what M6 takes away.
test "0425: a false condition whose else falls through leaves the rest live" {
  let r = @pipeline.run(
    "fn f() -> Int {\n  if 1 > 2 {\n    return 1\n  } else {\n    let _ = 2\n  }\n  return 3\n}\nlet x = f()\n",
    "false_cond_else_falls.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "Unreachable"), 0)
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
///
/// 0543. THE OUTER CONDITION WAS `n > 0`, WHICH STOPPED FOLDING TO FALSE IN
/// 0537, so this row stopped reaching the terminal block it names. It is a
/// LITERAL COMPARISON now.
test "0425: a false condition with no else at all falls through" {
  let r = @pipeline.run(
    "fn f() -> Int {\n  if 1 > 2 {\n    return 1\n  }\n  return 2\n}\nlet x = f()\n",
    "false_cond_no_else.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "Unreachable"), 0)
}

///|
/// THE CONTROL FOR THE ROW ABOVE: the outer condition TRUE, so the then-branch
/// runs alone, returns, and the code after it is dead -- the OPPOSITE count.
test "0425: a true condition with no else at all leaves the rest dead" {
  let r = @pipeline.run(
    "fn f() -> Int {\n  if 2 > 1 {\n    return 1\n  }\n  return 2\n}\nlet x = f()\n",
    "true_cond_no_else.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "Unreachable"), 1)
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
test "0425: a condition decided by the CALLER's argument does not kill the continuation" {
  // 0537. THIS ROW USED TO EXPECT 1, AND THE EXPECTATION WAS THE 0524 FALSE
  // POSITIVE WEARING A TRUE POSITIVE'S NAME. `n > 0` folds only because `f` was
  // called with the literal `1`; `f(-1)` reaches `return 2` on the very next
  // line. A condition that names a caller-bound parameter now explores both
  // sides and joins, so nothing after the `if` is claimed dead -- which is what
  // this row measures now.
  let r = @pipeline.run(
    "fn f(n : Int) -> Int {\n  if n > 0 {\n    return 1\n  }\n  return 2\n}\nlet x = f(1)\n",
    "folded_condition.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "Unreachable"), 0)
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
