// pipeline_0616_test.mbt -- the FIVE REASONS, counted on the REAL PATH.
//
// 0616. `n_calls - n_checked` was ONE number for FIVE different reasons, and
// the sentence beside it named TWO of them -- the two that REPORT. The other
// three are SILENT, and they are the majority.
//
// The five counters are added in the type lens, and `src/sa/sa_0616_test.mbt`
// checks what the REPORT says about them. That leaves the counters themselves
// unchecked: a lens that counted every class as one of the others would print
// a perfectly self-consistent row and be wrong about the tree.
//
// SO THESE TESTS PIN THE LENS, one class at a time:
//
//   sig-unknown   the callee is a cross-file VALUE the interface table knows by
//                 NAME but has no signature for
//   not-callable  the callee resolved to something that is not a function
//   unresolved    the name did not resolve at all
//   method        a method call: this lens has no signature for a method
//   dotdot        a `..` chain link: this lens has no signature for it
//
// EACH FIXTURE IS ONE LINE OF SOURCE, AND EACH ONE IS COUNTED ALONE: the
// fixture asserts its own class is 1 AND that the other four are 0. A lens that
// counted a method call as "not callable" would push not-callable to 1 and
// still pass a report-level test built from a hand-made verdict -- it fails
// here, and it fails in its own test.
//
// THE CONTROL MATTERS MORE. A lens that counted EVERY call as one of the five
// would also pass every fixture above, one at a time. The control is a call
// that RESOLVES: it is a site the lens checked, and it belongs to none of the
// five -- because the five are the reasons a call was NOT verified.

///|
/// THE SIG-UNKNOWN CLASS. `helper` is in the interface table by NAME and has
/// NO signature, so the call is real and its arguments were never checked.
test "0616: the sig-unknown class is counted on its own" {
  let tab = @core.IfaceSymTab::empty()
  tab.add_value("helper")
  let src = "fn main() -> Unit {\n  helper(1)\n}\n"
  let r = @pipeline.run(src, "u.mbt", tab)
  assert_eq(r.n_unknown_fn, 1)
  assert_eq(r.n_not_callable, 0)
  assert_eq(r.n_unresolved, 0)
  assert_eq(r.n_method_call, 0)
  assert_eq(r.n_dotdot_call, 0)
}

///|
/// THE NOT-CALLABLE CLASS. `x` is an `Int`, so the callee resolved to
/// something that is not a function -- the class that REPORTS.
test "0616: the not-callable class is counted on its own" {
  let src = "fn main() -> Unit {\n  let x = 1\n  x()\n}\n"
  let r = @pipeline.run(src, "u.mbt", empty_iface())
  assert_eq(r.n_not_callable, 1)
  assert_eq(r.n_unknown_fn, 0)
  assert_eq(r.n_unresolved, 0)
  assert_eq(r.n_method_call, 0)
  assert_eq(r.n_dotdot_call, 0)
}

///|
/// THE UNRESOLVED CLASS. The name is nowhere -- not a local, not in the
/// interface table -- so it did not resolve at all. The other class that
/// REPORTS.
test "0616: the unresolved class is counted on its own" {
  let src = "fn main() -> Unit {\n  unknown_fn_xyz(1)\n}\n"
  let r = @pipeline.run(src, "u.mbt", empty_iface())
  assert_eq(r.n_unresolved, 1)
  assert_eq(r.n_unknown_fn, 0)
  assert_eq(r.n_not_callable, 0)
  assert_eq(r.n_method_call, 0)
  assert_eq(r.n_dotdot_call, 0)
}

///|
/// THE METHOD CLASS. This lens has no signature for a method, so the call is
/// a site it reached and could not verify.
test "0616: the method class is counted on its own" {
  let src = "fn main() -> Unit {\n  let s = \"a\"\n  s.no_such_method()\n}\n"
  let r = @pipeline.run(src, "u.mbt", empty_iface())
  assert_eq(r.n_method_call, 1)
  assert_eq(r.n_unknown_fn, 0)
  assert_eq(r.n_not_callable, 0)
  assert_eq(r.n_unresolved, 0)
  assert_eq(r.n_dotdot_call, 0)
}

///|
/// THE `..` CLASS. A `..` chain link has no signature either, and it is a
/// class of its own: it is not a method call.
test "0616: the dotdot class is counted on its own" {
  let src = "fn main() -> Unit {\n  let y = 1\n  y..to_string()\n}\n"
  let r = @pipeline.run(src, "u.mbt", empty_iface())
  assert_eq(r.n_dotdot_call, 1)
  assert_eq(r.n_unknown_fn, 0)
  assert_eq(r.n_not_callable, 0)
  assert_eq(r.n_unresolved, 0)
  assert_eq(r.n_method_call, 0)
}

///|
/// AND THE FIVE ARE ALL OF THE UNVERIFIED SITES. Five sites, five reasons, one
/// each -- so a lens that counted one site twice would break the site total
/// below, and a lens that counted nothing would break it the other way.
test "0616: five unverified sites are five reasons" {
  let tab = @core.IfaceSymTab::empty()
  tab.add_value("helper")
  let src = "fn main() -> Unit {\n" +
    "  helper(1)\n" +
    "  unknown_fn_xyz(1)\n" +
    "  let x = 1\n" +
    "  x()\n" +
    "  let s = \"a\"\n" +
    "  s.no_such_method()\n" +
    "  let y = 1\n" +
    "  y..to_string()\n" +
    "}\n"
  let r = @pipeline.run(src, "u.mbt", tab)
  assert_eq(r.n_calls, 5)
  assert_eq(r.n_checked, 0)
  assert_eq(r.n_unknown_fn, 1)
  assert_eq(r.n_not_callable, 1)
  assert_eq(r.n_unresolved, 1)
  assert_eq(r.n_method_call, 1)
  assert_eq(r.n_dotdot_call, 1)
}

///|
/// THE CONTROL. A call that RESOLVES is a site the lens verified, and it
/// belongs to NONE of the five reasons -- the five are the reasons a call was
/// not verified, and a verified call has none of them.
///
/// A lens that put every call into one of the five buckets would pass all
/// five fixtures above and fail this one. That is the whole point of it.
test "0616: a call that resolves is in none of the five reasons" {
  let src = "fn helper() -> Unit {\n}\n\nfn main() -> Unit {\n  helper()\n}\n"
  let r = @pipeline.run(src, "u.mbt", empty_iface())
  assert_eq(r.n_unknown_fn, 0)
  assert_eq(r.n_not_callable, 0)
  assert_eq(r.n_unresolved, 0)
  assert_eq(r.n_method_call, 0)
  assert_eq(r.n_dotdot_call, 0)
  // AND IT IS A CHECKED SITE, so the five really are the unverified ones.
  assert_eq(r.n_calls, 1)
  assert_eq(r.n_checked, 1)
}

///|
/// AND THE EMPTY CASE, so that "0 of 0" cannot be read as "the lens stopped
/// counting". A body with no call at all has no unverified site and so no
/// reason.
test "0616: a body with no call at all is in none of the five reasons" {
  let src = "fn main() -> Unit {\n  let x = 1\n}\n"
  let r = @pipeline.run(src, "u.mbt", empty_iface())
  assert_eq(r.n_unknown_fn, 0)
  assert_eq(r.n_not_callable, 0)
  assert_eq(r.n_unresolved, 0)
  assert_eq(r.n_method_call, 0)
  assert_eq(r.n_dotdot_call, 0)
  assert_eq(r.n_calls, 0)
}
