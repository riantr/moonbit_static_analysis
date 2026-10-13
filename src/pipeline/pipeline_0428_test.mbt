// Tests for 0.4.28: a `derive` declaration has no body, and the analyzer was
// saying it had one.
//
// THE DEFECT. `derive(Debug, Eq, Clone)` is a PARENTHESISED TRAIT LIST with no
// braces, but the top-level dispatch routed it through `skip_decl_braced` --
// the skipper for `struct` / `enum` / `trait` / `impl` / `extend` / `test`. Two
// things followed from that, and only one of them was visible:
//
//   1. THE MESSAGE WAS FALSE. `skip` builds its text from a `braced` flag, so
//      every derive notice read "derive declaration is outside the analyzed
//      subset; ITS BODY WAS NOT ANALYZED". A derive has no body to analyze.
//      570 of those in production code across the six corpora.
//
//   2. IT COULD EAT ITS NEIGHBOUR. `skip_decl_braced` scans forward for `{`,
//      breaking only at a `fn`, so
//
//          derive(Debug, Eq)
//          struct Box { n : Int }
//
//      consumed the STRUCT's braces as the derive's body. The struct's own
//      exclusion notice was then never emitted -- the file claimed one
//      deliberate exclusion where it had made two, and the lost one is exactly
//      the fact the notice exists to record.
//
// WHAT THIS DOES NOT DO. The notice STAYS. The analyzer genuinely does not model
// derived implementations, so a reader is right to be told; only the false claim
// about a body is removed. **This does not reduce the notice count**, and a
// count-based expectation here would be asserting something the fix does not do.
//
// MEASURED, not assumed: that ordering occurs ZERO times in wzzc-dev/moui
// 0.1.12, so this is a latent bug with no corpus impact today. It is fixed
// because it is wrong -- a silently dropped exclusion is the failure mode this
// file has been bitten by more than once.

///|
/// Count ParseError notices whose message contains `needle`. A family count is
/// the wrong tool for the same reason `count_named` exists in 0424: every
/// notice here is `ParseError`, so a family count cannot tell "no derive notice"
/// from "no ParseErrors at all" -- and the second would still pass if the fix
/// had suppressed the notice entirely.
fn count_parse_with(r : @pipeline.PipelineResult, needle : String) -> Int32 {
  let mut n = 0
  for rep in r.reports {
    if rep.family.name() == "ParseError" && rep.message.contains(needle) {
      n += 1
    }
  }
  n
}

///|
/// THE FALSE CLAIM, stated directly. One notice, and it does not mention a
/// body.
test "0428: a derive notice does not claim there was a body to analyze" {
  let r = @pipeline.run(
    "derive(Debug, Eq)\nfn main {\n  let _ = 1\n}\n",
    "derive_alone.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_parse_with(r, "derive declaration"), 1)
  assert_eq(count_parse_with(r, "its body was not analyzed"), 0)
}

///|
/// THE NOTICE IS STILL THERE. This is the control for the test above: if the
/// fix had simply stopped reporting derives, "no false claim" would pass while
/// the reader lost the fact that derived implementations are unmodelled.
test "0428: control -- a derive is still reported as outside the subset" {
  let r = @pipeline.run(
    "derive(Debug, Eq)\nfn main {\n  let _ = 1\n}\n",
    "derive_still_noticed.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_parse_with(r, "outside the analyzed subset"), 1)
}

///|
/// THE REGRESSION THIS EXISTS FOR. The derive line used to consume the struct's
/// braces, so this file produced ONE notice where it has two deliberate
/// exclusions. Asserted as exactly two exclusions of two DIFFERENT kinds -- a
/// count of 1 here would be the bug, and a count of 2 with the struct's notice
/// missing would also be the bug.
test "0428: a derive before a struct does not swallow the struct's notice" {
  let r = @pipeline.run(
    "derive(Debug, Eq)\n\nstruct Box {\n  n : Int\n}\n\nfn main {\n  let b = Box::{ n: 1 }\n  let _ = b\n}\n",
    "derive_then_struct.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_parse_with(r, "derive declaration"), 1)
  assert_eq(count_parse_with(r, "struct declaration"), 1)
}

///|
/// AND A BRACED DECLARATION STILL CLAIMS A BODY, which is the opposite
/// expectation from the derive fixtures above. Without this the fix could have
/// been "stop saying anything about bodies", which would silence the one case

///|
/// where the claim is true -- and 548 struct plus 148 enum notices would lose
/// the only part that tells a reader what was skipped.
test "0428: control -- a braced declaration still reports an unanalyzed body" {
  let r = @pipeline.run(
    "struct Box {\n  n : Int\n}\nfn main {\n  let _ = 1\n}\n",
    "struct_body.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_parse_with(r, "struct declaration"), 1)
  assert_eq(count_parse_with(r, "its body was not analyzed"), 1)
}

///|
/// THE ORDINARY MOONBIT ORDER IS UNCHANGED. `derive` conventionally follows the
/// declaration it belongs to, and that is the shape all 570 corpus sites have:
/// the line skipper stops at the newline either way, so the next declaration is
/// reached in the same state. This is the case that would move if the derive
/// skipper started consuming a neighbour -- and the corpus measurement says that
// ordering has zero occurrences, so without a fixture here the shape is untested.
test "0428: a struct followed by a derive keeps both notices" {
  let r = @pipeline.run(
    "struct Box {\n  n : Int\n}\nderive(Debug, Eq)\nfn main {\n  let b = Box::{ n: 1 }\n  let _ = b\n}\n",
    "struct_then_derive.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_parse_with(r, "struct declaration"), 1)
  assert_eq(count_parse_with(r, "derive declaration"), 1)
}
