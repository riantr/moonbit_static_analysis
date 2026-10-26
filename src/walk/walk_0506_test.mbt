// test: the GEOMETRY that decides whether a notice can hide a finding.
//
// 0506. The analyzer renders a notice for every construct it reads past, and
// on the pinned core corpus that was 10,096 notices: the OLD rendering -- the
// per-file cap as it ships -- was 9,128 lines of output to say 28 things, and
// with the cap lifted, so that every notice is on a line of its own, it is
// 11,223. 0506 prints only the notices that can HIDE a
// finding and counts the rest, and the question "which is which" is answered
// here, in the package that owns the geometry.
//
// THE ANSWER IS A POSITION, and this file pins the position rule itself:
//
//   * a region INSIDE some function's extent is in that function's hole list,
//     so the frame audit could not judge a binding the region might have
//     read -- it can hide a finding;
//   * a region OUTSIDE every function's extent is in NO function's list, so
//     it hides nothing at all.
//
// The sharp control for that rule is the SAME construct in both positions. A
// message's wording cannot decide it: "if expression is outside the analyzed
// subset" is printed when it sits inside a function and aggregated when it
// sits at module top level. These tests use spans directly rather than
// messages, because the geometry is about spans.
//
// => 判据: the rule is the analyzer's own extents, not a list of message
// shapes. A second spelling of the geometry is how two parts of the analyzer
// come to disagree about which regions hide a finding.

///|
/// A span running from one line to another.
fn mk_span(sl : Int32, el : Int32) -> @core.Span {
  { start: @core.pos(sl, 1), end: @core.pos(el, 1), }
}

///|
/// A function whose extent runs from one line to another.
fn mk_fn(name : String, sl : Int32, el : Int32) -> @walk.FnInfo {
  let f : @walk.FnInfo = {
    name,
    params: [],
    retann: "",
    body: [],
    span: mk_span(sl, el),
  }
  f
}

///|
/// A region that STARTS inside the function's extent is in it. The rule is
/// about where the region BEGINS: the parser records a region at the
/// construct it declined to analyse, and that construct is where the region
/// begins.
test "0506: a region that starts inside a function's extent is in it" {
  assert_true(@walk.span_in_extent(mk_span(12, 12), mk_span(10, 20)))
}

///|
/// The two boundaries. A region that starts on the function's FIRST line is
/// in it, and so is one that starts on its LAST: the extent runs from the
/// header to the closing brace, and both of those lines are inside it.
test "0506: a region on the function's first line and on its last line is in it" {
  assert_true(@walk.span_in_extent(mk_span(10, 10), mk_span(10, 20)))
  assert_true(@walk.span_in_extent(mk_span(20, 20), mk_span(10, 20)))
}

///|
/// The other two sides. A region that starts BEFORE the function is not in
/// it, and neither is one that starts after it. A region that merely OVERLAPS
/// the function -- one that starts above it and ends inside it -- is not in
/// it either, and that is the same rule read the other way: the START is what
/// counts.
test "0506: a region that starts before or after the function is not in it" {
  assert_false(@walk.span_in_extent(mk_span(9, 9), mk_span(10, 20)))
  assert_false(@walk.span_in_extent(mk_span(21, 21), mk_span(10, 20)))
  assert_false(@walk.span_in_extent(mk_span(5, 15), mk_span(10, 20)))
}

///|
/// `hiding_spans` keeps the regions that lie inside SOME function's extent.
test "0506: hiding_spans keeps the regions inside a function's extent" {
  let fns = [mk_fn("g", 10, 20)]
  let inner = mk_span(12, 12)
  let out = @walk.hiding_spans(fns, [inner])
  assert_eq(out.length(), 1)
  assert_true(out[0] == inner)
}

///|
/// AND THE CONTROL: the same region, in the same list, against a function
/// it does not lie inside. The one that hides nothing is dropped, and it is
/// dropped because of WHERE it is -- not because of what it says.
test "0506: a region outside every function's extent hides nothing" {
  let fns = [mk_fn("g", 10, 20)]
  let inner = mk_span(12, 12)
  let outside = mk_span(30, 30)
  let out = @walk.hiding_spans(fns, [inner, outside])
  assert_eq(out.length(), 1)
  assert_true(out[0] == inner)
}

///|
/// A LOCAL function is covered by its enclosing top-level one: the local
/// function's extent lies inside the top-level function's extent, so a region
/// inside the local function is inside the top-level one too. Without this,
/// a `fn` declared inside a `fn` would be a hole in the coverage.
test "0506: a region inside a local function is inside the enclosing one too" {
  let top = mk_fn("outer", 10, 40)
  let inner_fn = mk_fn("inner", 20, 30)
  let region = mk_span(25, 25)
  let out = @walk.hiding_spans([top, inner_fn], [region])
  assert_eq(out.length(), 1)
  assert_true(out[0] == region)
  // And with ONLY the top-level function known, the same region is still
  // inside it -- the local one is not what makes it a hiding region.
  assert_eq(@walk.hiding_spans([top], [region]).length(), 1)
}

///|
/// A region in NO function at all is in no function's hole list, so it hides
/// nothing -- and this is the shape that is 88.7% of the corpus's notices.
test "0506: a region in no function at all hides nothing" {
  let out = @walk.hiding_spans([], [mk_span(1, 1)])
  assert_eq(out.length(), 0)
}

///|
/// TWO functions, and a region in each: both are hiding regions, and the
/// result keeps them BOTH. The rule is "inside SOME function's extent", and
/// a filter that stopped at the first match would drop the second.
test "0506: a region in each of two functions is hiding in both" {
  let fns = [mk_fn("a", 10, 20), mk_fn("b", 30, 40)]
  let ra = mk_span(12, 12)
  let rb = mk_span(32, 32)
  let out = @walk.hiding_spans(fns, [ra, rb])
  assert_eq(out.length(), 2)
}
