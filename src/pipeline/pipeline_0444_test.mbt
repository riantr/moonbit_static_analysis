///|
/// 0444: a BARE LOWERCASE `is` head is a variable binding.
///

///|
/// THE DEFECT. `Parser::parse_is_pattern` consumed the head name unconditionally,
/// as a CONSTRUCTOR, and collected bindings only from a parenthesised payload.
/// So
///
///     if probe() is err && err != 0 { .. err .. }
///
/// produced an EMPTY binding list: `err` was swallowed by the head and every
/// later use of it was an undefined name.
///
/// The corpus manifestation is NOT an undefined name, which is what made this
/// worth an increment rather than a patch. Measured, async 0.22.4
/// `src/tls/schannel.mbt` lines 218, 224, 235, 284, 446 -- all
/// `if EXPR is err && err != 0 {` -- report
///
///     unsupported operand types for '!=': 'fn err (signature not read)' and 'int'
///
/// because something ELSE named `err` is in scope in that package and wins the
/// lookup. An isolated reproduction of the same source reports
/// `undefined name 'err'` instead. Two different symptoms, one cause, and only
/// the isolated form points at the parser.
///
/// THE GRAMMAR IS SETTLED, not inferred --
/// `_verify/settle_0444_is_head.ps1`, 9/9 with the positive control AND a canary
/// green:
///
///   - `if probe() is err && err != 0 { err }` COMPILES, so a lowercase head binds.
///   - `if opt() is Some && Some != 0` is REJECTED, and the only reading that
///     explains a rejection is `Some` being the CONSTRUCTOR -- a function
///     compared with an integer. An uppercase head is a constructor TEST.
///   - an unused head binding AND an unused payload binding are both LEGAL.
///   - `_` binds nothing.
///
/// The probe's own first draft asked this question with an `Int` base and `Some`
/// as the pattern, so three cases failed with 4014 -- a plain Int/Option type
/// mismatch -- and would have been read as "an uppercase head is rejected". The
/// fix was a second `opt() -> Option[Int]`, not a revised expectation.
test "0444: a lowercase `is` head binds, and the guard can read it" {
  let r = @pipeline.run(
    "fn probe() -> Int {\n  0\n}\n\nfn keep() -> Int {\n  if probe() is err && err != 0 {\n    err\n  } else {\n    0\n  }\n}\n",
    "head.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(r.first_error_line, 0)
  assert_eq(count_family(r, "UndefinedName"), 0)
}

///|
/// AND THE DIRECTION THAT WOULD HAVE BEEN A NEW FALSE POSITIVE. Binding the head
/// put `err` on the audit list, and `audit_frame` then reported `local variable
/// 'err' assigned but may not be used` -- on a program `moon check` accepts.
/// The settle's `b_lower_unused` is that program: an unused `is` binding is legal.
///
/// So `EIs` binds with `bind_pattern`, which does not touch the audit list, the
/// same trade `ECatch` makes for its arm patterns. The head and the payload share
/// the call because the settle measures BOTH as exempt, so the AST does not have
/// to distinguish them.
test "0444: an unused `is` head binding is legal, not an unused local" {
  let r = @pipeline.run(
    "fn probe() -> Int {\n  0\n}\n\nfn keep() -> Int {\n  if probe() is err {\n    1\n  } else {\n    0\n  }\n}\n",
    "unused.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(r.first_error_line, 0)
  assert_eq(count_family(r, "UnusedLocal"), 0)
}

///|
/// THE PAYLOAD HALF, which is the PRE-EXISTING half of the same false positive:
/// `is Some(v)` with `v` unread. Settled by `h_payload_unused`, ACCEPTED.
test "0444: an unused `is` payload binding is legal too" {
  let r = @pipeline.run(
    "fn opt() -> Option[Int] {\n  Some(0)\n}\n\nfn keep() -> Int {\n  if opt() is Some(v) {\n    1\n  } else {\n    0\n  }\n}\n",
    "payload.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(r.first_error_line, 0)
  assert_eq(count_family(r, "UnusedLocal"), 0)
}

///|
/// THE UPPERCASE SIDE, asserted as a NON-BINDING. `Some` must not become a local:
/// if the head bound unconditionally, this would report `Some` as an unused local,
/// because nothing in the body reads it. This is the case that separates "lowercase
/// binds" from "every head binds", and it is the same distinction `d_upper_compared`
/// settles with the compiler.
test "0444: an uppercase `is` head is a constructor test and binds nothing" {
  let r = @pipeline.run(
    "fn opt() -> Option[Int] {\n  Some(0)\n}\n\nfn keep() -> Int {\n  if opt() is Some {\n    1\n  } else {\n    0\n  }\n}\n",
    "ctor.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(r.first_error_line, 0)
  assert_eq(count_family(r, "UnusedLocal"), 0)
  assert_eq(count_family(r, "UndefinedName"), 0)
}

///|
/// THE QUALIFIED HEAD, which is the other thing the new predicate must not break:
/// `is St::Shutdown` is a constructor TEST whose name is the last `::` segment,
/// so `St::Shutdown` binds nothing. Settled by `_verify/probe_sweep_0434.ps1`
/// case `is_expr_if_cond` -- 0 errors from `moon check`.
test "0444: a qualified `is` head binds nothing" {
  let r = @pipeline.run(
    "enum St {\n  Shutdown\n  Running\n}\n\nfn keep(x : St) -> Int {\n  if x is St::Shutdown {\n    1\n  } else {\n    0\n  }\n}\n",
    "qual.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(r.first_error_line, 0)
  assert_eq(count_family(r, "UnusedLocal"), 0)
  assert_eq(count_family(r, "UndefinedName"), 0)
}

///|
/// AND THE CONTROL THAT SAYS THE ANALYZER IS STILL LOOKING. Binding one more name
/// is exactly the kind of change that can make a resolver blind in the direction
/// that reads as an improvement, so a genuinely unbound name in the same guard is
/// pinned as a finding.
///
/// This asserts a FINDING, which is worth saying out loud: it is not pinning a
/// defect, it is pinning that the fix did not come from switching the check off.
test "0444 control: a genuinely unbound name in the same guard is still reported" {
  let r = @pipeline.run(
    "fn probe() -> Int {\n  0\n}\n\nfn keep() -> Int {\n  if probe() is err && nope != 0 {\n    1\n  } else {\n    0\n  }\n}\n",
    "ctl.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "UndefinedName"), 1)
}
