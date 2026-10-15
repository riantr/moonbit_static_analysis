///|
/// 0440: a `.mbti` `suberror` body declares VALUE CONSTRUCTORS, so they are
/// harvested exactly like an `enum` body's.
///

///|
/// THE DEFECT THIS REMOVES, and it was the largest single source of false
/// positives the project had. Across the six corpora, 58 of the 80 actionable
/// findings in existence were `no visible binding for '<a suberror variant>'`
/// in moonbit-community/proton 0.3.4. `InvalidSetting` alone was 7.
///
/// The name was not missing. proton's OWN generated interface says, at
/// `pkg.generated.mbti:68`,
///
///     pub(all) suberror AppConfigurationError {
///       InvalidSetting(name~ : String, message~ : String)
///       ...
///     }
///
/// and `collect_iface_symtabs` already reads the target's own tree -- the
/// target's root is `iface_dirs[0]` in `sa/main.mbt`. One predicate stood in
/// the way: `in_ctor_body = matched == "enum " && d > 0`, so a `suberror` body
/// was matched, descended into, and its members discarded.
///

///|
/// WHY IT WAS INVISIBLE SO LONG, which is the part worth keeping. The MAIN
/// PARSER already harvested suberror bodies (`Parser::skip_decl`:
/// `what == "enum" || what == "suberror"`), so a suberror variant used in the
/// file that DECLARES it always resolved -- and 30 braced suberror bodies
/// exist in proton's `.mbti` files against 0 body-less ones, so there was no
/// rare spelling to notice. Only the CROSS-FILE path was broken, which is why
/// the symptom was false positives on correct code rather than unreadable
/// files, and why no amount of reading more files would have fixed it.
///

///|
/// THESE ASSERT ON THE TABLE, NOT ON A FINDING, because that is the layer the
/// defect was in -- and because a `count_family`-style assertion in `@parser`
/// or a table-level one in `@pipeline` would both be satisfied by a table that
/// is merely large. Every test below names the exact constructor it expects and
/// the exact payload words it expects NOT to be harvested.

///|
/// THE POSITIVE CASE, written as proton writes it. `InvalidSetting` is the
/// measured name; `kind` stands in for a payload TYPE, which must not be
/// harvested as a constructor -- the `radius` case in 0432 pins the same thing
/// on the parser side.
test "0440: a braced suberror body in a .mbti yields its constructors as values" {
  let src = "package \"p\"\n\npub(all) suberror AppConfigurationError {\n  InvalidSetting(name~ : String, message~ : String)\n  WindowDestroy(status~ : Int)\n} derive(Debug)\n"
  let tab = @moonfiles.collect_iface_names(src)
  assert_true(tab.has_value("InvalidSetting"))
  assert_true(tab.has_value("WindowDestroy"))
  // The payload types are not constructors.
  assert_false(tab.has_value("name"))
  assert_false(tab.has_value("status"))
}

///|
/// THE CONTROL, and it is the one that makes the test mean anything. The same
/// file with `enum` instead of `suberror` harvested those constructors BEFORE
/// this change -- `parser_0432_test.mbt:127` pins the parser side and the
/// `.mbti` side has harvested enum bodies since the table existed. If the
/// positive test above ever goes green because the harvest got broader in some
/// other way, this one is what catches it.
test "0440 control: an enum body still yields its constructors, unchanged" {
  let src = "package \"p\"\n\npub enum AppConfiguration {\n  InvalidSetting(name~ : String, message~ : String)\n} derive(Debug)\n"
  let tab = @moonfiles.collect_iface_names(src)
  assert_true(tab.has_value("InvalidSetting"))
  assert_false(tab.has_value("name"))
}

///|
/// A BODY-LESS `suberror` must harvest NOTHING from a body, because it has no
/// body. `pub suberror QueueAlreadyClosed derive(Debug)` is the shape
/// moonbitlang/async writes, and it is the discriminating case for the `d > 0`
/// half of the predicate. Had the fix been `matched == "suberror "` alone,
/// `derive` and `Debug` would have entered the VALUE table, and a name
/// harvested as a value silences a real `no visible binding` — the quiet
/// direction, which is the one that costs true positives.
///
/// AND THE DECLARED NAME IS A *TYPE*, NOT A VALUE — which the first draft of
/// this test got wrong by asserting `has_value`. A `suberror` declaration is a
/// type declaration like any other (`parse_iface` pushes `suberror ` into
/// `declared`, and `collect_iface_names` sends `declared` to `tab.types`). It is
/// `raise`n by name rather than constructed, but the table is about names, and
/// the name is recorded on the type side. Asserting the wrong side would have
/// "documented" a fact about the table that does not hold.
test "0440: a body-less suberror harvests nothing from a body it does not have" {
  let src = "package \"p\"\n\npub suberror QueueAlreadyClosed derive(Debug)\n"
  let tab = @moonfiles.collect_iface_names(src)
  // The declaration itself, on the TYPE side.
  assert_true(tab.has_type("QueueAlreadyClosed"))
  // `derive` names a trait and `Debug` is one; neither is a value.
  assert_false(tab.has_value("derive"))
  assert_false(tab.has_value("Debug"))
  assert_false(tab.has_value("QueueAlreadyClosed"))
}

///|
/// THE `derive` LINE THAT CLOSES A BODY. proton writes `} derive(Debug, Eq)` on
/// its suberror, and the closing brace is on that line. `line_head_identifier`
/// is specified to return "" for a line whose first relevant character is `}`,
/// so `derive` must not leak in from there -- and it is now reachable, because
/// this is the first time a suberror body is harvested at all.
test "0440: `} derive(...)` on a suberror closing line harvests nothing" {
  let src = "package \"p\"\n\npub(all) suberror Boom {\n  Detail(detail~ : String)\n} derive(Debug, Eq)\n"
  let tab = @moonfiles.collect_iface_names(src)
  assert_true(tab.has_value("Detail"))
  assert_false(tab.has_value("derive"))
  assert_false(tab.has_value("Eq"))
}

///|
/// THE OVER-HARVEST CONTROL, and it is the failure mode this fix could most
/// easily have had. The predicate discriminates by KEYWORD; a draft that simply
/// harvested every braced declaration body would put a `struct`'s FIELDS into
/// the value table, and a field harvested as a value silences a real `no
/// visible binding` -- the quiet direction.
///
/// It is asserted as `has_value`, not merely "no new report", because the
/// consequence test lives in `@pipeline` and this layer cannot see it: what is
/// wrong here is the TABLE, whether or not anyone consults it yet.
test "0440: a struct body does not harvest its fields as constructors" {
  let src = "package \"p\"\n\npub struct Box {\n  width : Int\n  label : String\n} derive(Debug)\n"
  let tab = @moonfiles.collect_iface_names(src)
  assert_true(tab.has_type("Box"))
  assert_false(tab.has_value("width"))
  assert_false(tab.has_value("label"))
}

///|
/// THE CROSS-FILE OBSERVABLE lives in `pipeline_0440_test.mbt`, not here.
/// This package has no `count_family`, and a finding-level assertion written
/// against the table would be the wrong layer anyway: the table is where the
/// defect was, but only the walker's refusal to report can say the name
/// RESOLVED.
