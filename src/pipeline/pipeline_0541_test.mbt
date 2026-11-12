// pipeline_0541_test.mbt -- THE CALL-CONTEXT LEDGER (§8.2-8.4).
//
// WHAT THESE TESTS ARE ABOUT. `Interp::analyze_fn` has no cache short-circuit:
// every call site RE-EXECUTES the callee's body with its own abstract
// arguments, and `sig_key` is read as a summary and used as the recursion cut.
// That is a design decision about precision and cost (§8.3 call strings vs
// §8.4's functional approach), and `--contexts` is where it becomes measurable.
//
// THE NUMBERS BELOW ARE COUNTED BY HAND, from the program text, and then
// asserted. A ledger tested only for "greater than zero" would pass on an
// implementation that counted the dry pass, or that counted a cut as an
// execution, and neither error is visible anywhere else.

///|
/// One body execution per call, and TWO executions of ONE signature is one
/// CONTEXT when the two calls share a call string: the loop-free, caller-free
/// case. This is the distinction the ledger exists for -- `executions` counts
/// the work, `call-strings` counts the places it came from, and a summary-based
/// analysis would have collapsed the pair into one entry.
test "0541: two calls to one signature from one call string" {
  let src = "fn f(n : Int) -> Int {\n  n + 1\n}\nlet a = f(1)\nlet b = f(1)\n"
  let r = @pipeline.run_tracked(src, "u.mbt", empty_iface(), false)
  // f's body ran twice, and both arrivals carried the same arguments
  assert_eq(r.ctx.exec, 2)
  assert_eq(r.ctx.sig, 1)
  // both arrivals came from the module's top level: one call string
  assert_eq(r.ctx.context, 1)
  assert_eq(r.ctx.shared, 0)
  assert_eq(r.ctx.cuts, 0)
}

///|
/// THE SIGNATURE IS TYPE-LEVEL, and this row pins that as a fact rather than
/// leaving it to be discovered.
///
/// `AbsVal` DOES carry constants (`AInt(1)` is not `AInt(2)`), and the two
/// executions below therefore receive different abstract arguments -- but
/// `sig_key` builds its key from `val_name`, which names the TYPE (`AInt(_)` ->
/// `"int"`). So `f(1)` and `f(2)` are ONE signature and TWO executions.
///
/// That is coarser than §8.4's `Context = State` and it is deliberate in effect
/// if not in design: the key is read by `analyzed_sigs` (a summary of shapes)
/// and used as the recursion cut, and neither needs the constant, because the
/// body is re-executed with the real value at every call site. A cache
/// SHORT-CIRCUIT here would have made this coarseness a precision loss; there is
/// none (see `analyze_fn`).
test "0541: two integer literals are one signature, because the key is a type" {
  let src = "fn f(n : Int) -> Int {\n  n + 1\n}\nlet a = f(1)\nlet b = f(2)\n"
  let r = @pipeline.run_tracked(src, "u.mbt", empty_iface(), false)
  assert_eq(r.ctx.exec, 2)
  assert_eq(r.ctx.sig, 1)
  // one call string (the module frame), so the pair count does not rise either
  assert_eq(r.ctx.context, 1)
  assert_eq(r.ctx.shared, 0)
}

///|
/// ONE signature reached from TWO call strings -- the measurement §8.3 is
/// actually about. `g(3)` is called from `h1` and from `h2`, with the same
/// abstract argument, so it is ONE signature under §8.4's rule and TWO contexts
/// under a call-string rule.
///
/// The counts: `h1` and `h2` each run once (2), `g` runs twice (2 more), so
/// four executions over three signatures -- and the two `g` calls hang off
/// different strings, which is exactly one `shared` signature.
test "0541: one signature reached from two call strings" {
  let src = "fn g(x : Int) -> Int {\n  x * 2\n}\nfn h1() -> Int {\n  g(3)\n}\nfn h2() -> Int {\n  g(3)\n}\nlet p = h1()\nlet q = h2()\n"
  let r = @pipeline.run_tracked(src, "u.mbt", empty_iface(), false)
  assert_eq(r.ctx.exec, 4)
  assert_eq(r.ctx.sig, 3)
  assert_eq(r.ctx.context, 4)
  // `g(3)` is the one signature reached from more than one call string
  assert_eq(r.ctx.shared, 1)
  assert_eq(r.ctx.cuts, 0)
  // the deepest arrival was inside `h1`/`h2`, under the module frame. The
  // MODULE FRAME COUNTS: every top-level statement runs under a synthetic
  // `main()` frame, so a call from a function called from the top level sits at
  // depth 2, not 1.
  assert_eq(r.ctx.depth, 2)
}

///|
/// THE TERMINATION DEVICE, counted. A self-call with the SAME abstract argument
/// is the case the cache cannot replay: the signature is already in progress, so
/// the arrival returns the partial instead of running the body. That is the only
/// place this analysis merges two contexts, and it must show up as ONE cut, not
/// as one more execution.
test "0541: a self-call with the same signature is a cut, not an execution" {
  let src = "fn r(n : Int) -> Int {\n  r(n)\n}\nlet z = r(1)\n"
  let r = @pipeline.run_tracked(src, "u.mbt", empty_iface(), false)
  assert_eq(r.ctx.exec, 1)
  assert_eq(r.ctx.cuts, 1)
  assert_eq(r.ctx.sig, 1)
}

///|
/// THE COUNTS COME FROM THE REPORT PASS, not from the dry one. The dry pass runs
/// every body too, so an implementation that forgot the flag reports exactly
/// TWICE these numbers -- which is why the assertion is an equality and not a
/// bound.
test "0541: the dry pass is not counted" {
  let src = "fn f(n : Int) -> Int {\n  n + 1\n}\nlet a = f(1)\n"
  let r = @pipeline.run_tracked(src, "u.mbt", empty_iface(), false)
  assert_eq(r.ctx.exec, 1)
}

///|
/// THE IDENTITIES, on a program with all three shapes at once. Each is a
/// consequence of the definitions and none of them can be arranged afterwards:
///
///   signatures <= call-strings <= executions     every signature has a string,
///                                                every string has an execution
///   shared-signatures <= signatures
///   recursion-cuts are DISJOINT from executions  a cut does not run the body
test "0541: the ledger's identities hold" {
  let src = "fn g(x : Int) -> Int {\n  if x > 0 {\n    r(x)\n  } else {\n    x\n  }\n}\nfn r(n : Int) -> Int {\n  r(n)\n}\nfn m() -> Int {\n  g(1)\n}\nlet a = m()\nlet b = g(2)\n"
  let r = @pipeline.run_tracked(src, "u.mbt", empty_iface(), false)
  assert_true(r.ctx.sig <= r.ctx.context)
  assert_true(r.ctx.context <= r.ctx.exec)
  assert_true(r.ctx.shared <= r.ctx.sig)
  // the self-call in `r` was cut at least once, and cutting is not executing
  assert_true(r.ctx.cuts >= 1)
  assert_true(r.ctx.depth >= 1)
}

///|
/// A SCAN THAT DID NOT ASK pays nothing and reports nothing: the untracked entry
/// leaves the ledger at zero, so no existing output can move because this
/// diagnostic exists.
test "0541: the untracked entry leaves the ledger empty" {
  let src = "fn g(x : Int) -> Int {\n  x * 2\n}\nlet p = g(3)\n"
  let tracked = @pipeline.run_tracked(src, "u.mbt", empty_iface(), false)
  let plain = @pipeline.run(src, "u.mbt", empty_iface())
  assert_true(tracked.ctx.exec > 0)
  assert_eq(plain.ctx.exec, 0)
  assert_eq(plain.ctx.sig, 0)
  assert_eq(plain.ctx.context, 0)
  assert_eq(plain.ctx.shared, 0)
  assert_eq(plain.ctx.cuts, 0)
  // and the findings are the same either way: the ledger observes, it does not
  // analyse
  assert_eq(plain.reports.length(), tracked.reports.length())
}

///|
/// THE DEFECT THIS INCREMENT'S OWN CODE EXPOSED, pinned where a reader will hit
/// it.
///
///     fn e(c : Bool) -> String {
///       let mut s = "n/a"
///       if c { s = "si" }
///       "value: \{s}"          <- the only read of `s`
///     }
///
/// `MSA-015` reported the initializer as a dead store on this shape, because
/// `@flow.names_of_expr` answered () for `EStr` and dropped the identifiers the
/// parser had already collected. MEASURED on this tree's own `src/sa/main.mbt`
/// (`ctx_line`'s `per_sig`): one high-confidence finding on code that reads the
/// variable two lines later.
///
/// THE CONTROL IS THE SECOND HALF: the same program with a TAIL EXPRESSION
/// instead of an interpolation must also be clean, so the row cannot pass by
/// suppressing the family on `if`-with-assignment shapes in general.
test "0541: a read inside a string interpolation is not a dead store" {
  let interpolated = "fn e(c : Bool) -> String {\n  let mut s = \"n/a\"\n  if c {\n    s = \"si\"\n  }\n  \"value: \\{s}\"\n}\nlet z = e(true)\n"
  let r1 = @pipeline.run(interpolated, "u.mbt", empty_iface())
  assert_eq(count_0541(r1.reports, "MSA-015"), 0)
  // the control: a plain read, which was never affected
  let plain = "fn e(c : Bool) -> String {\n  let mut s = \"n/a\"\n  if c {\n    s = \"si\"\n  }\n  s\n}\nlet z = e(true)\n"
  let r2 = @pipeline.run(plain, "u.mbt", empty_iface())
  assert_eq(count_0541(r2.reports, "MSA-015"), 0)
  // and the family still speaks when the store really is dead: `s = "si"` is
  // overwritten before any read. (The `let` initializer above is NOT the shape
  // to test with -- an unread `let` is `FUnusedLocal`'s business, which is why
  // the first version of this control measured zero.)
  //
  // 0565. AND THE INITIALIZER IS DEAD IN ITS OWN RIGHT: `let mut s = "n/a"` is
  // overwritten by `s = "si"` before anything reads it. The family says so now,
  // so this control measures TWO -- the declaration and the first store -- and
  // the two are told apart by their own wording.
  let dead = "fn e() -> String {\n  let mut s = \"n/a\"\n  s = \"si\"\n  s = \"no\"\n  s\n}\nlet z = e()\n"
  let r3 = @pipeline.run(dead, "u.mbt", empty_iface())
  assert_eq(count_0541(r3.reports, "MSA-015"), 2)
}

///|
/// Count findings of one family by its stable id.
fn count_0541(rs : Array[@report.Report], id : String) -> Int32 {
  let mut n = 0
  for r in rs {
    if r.family.id() == id {
      n += 1
    }
  }
  n
}
