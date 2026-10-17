//| Tests for 0473 -- reach through a `for` head that carries ONE initializer and no
//| semicolons.
//|
//| THE REACHABLE SITE. async/src/websocket/conn.mbt:486 is
//|
//|     let kind : MessageKind = for frame = self.recv_frame_header() { .. }
//|
//| and every line of that file after 486 was unread because the head was read as a binder
//| and died on `expected 'in'`. Fixing the header does not by itself make the loop's body
//| readable: the body is walked by `parse_block`, and these rows are what say that the
//| body of the NEW header shape is walked exactly like the old one.
//|
//| EVERY ZERO ROW HERE HAS A CONTROL THAT CAN FAIL. That is the rule this repository
//| learned twice the hard way -- four 0470 pipeline rows asserted a count of a family
//| string that does not exist, so they read 0 whatever the code did, and they passed 868/868
//| while proving nothing. A negative row without a control is a missing test.

///|
/// A parameter read ONLY inside the body of the single-clause header. If the body were
/// skipped the way a loop EXPRESSION's body is, `p` would be reported unread -- which is the
/// defect 0443 removed for `nobreak`, in the same way and for the same reason.
test "0473: a parameter read only inside a one-initializer for body is still read" {
  let r = @pipeline.run(
    "///|\nfn f(n : Int, p : String) -> Unit {\n  for i = n {\n    p.length()\n  }\n}\n",
    "oneinitread.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "UnusedParam"), 0)
}

///|
/// THE CONTROL FOR THAT ZERO, and it is the same program with the one read removed. If this
/// were also 0 the row above would be passing because the lens had stopped looking at
/// parameters, not because `p` is read inside the body.
test "0473 control: the same parameter unread is reported unused" {
  let r = @pipeline.run(
    "///|\nfn f(n : Int, p : String) -> Unit {\n  for i = n {\n    ignore(1)\n  }\n}\n",
    "oneinitunread.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "UnusedParam"), 1)
}

///|
/// THE POSITIVE DIRECTION, which is the one that needs no control to be trusted: a name that
/// does not exist, used ONLY inside the body of this header, IS reported. A count of one is
/// a claim about work that happened, and the body cannot be walked without producing it.
test "0473: the body of a one-initializer for header is walked" {
  let r = @pipeline.run(
    "///|\nfn f(n : Int) -> Unit {\n  for i = n {\n    ignore(probe_0473_nowhere)\n  }\n}\n",
    "oneinitwalk.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "UndefinedName"), 1)
}

///|
/// AND THE CONTROL FOR THAT ZERO: the name absent from the program entirely. This is the row
/// that keeps the previous one honest -- if `UndefinedName` were 0 because the header still
/// stops the file early, the row above would also be 0 and would look like a pass.
test "0473 control: the same name absent from the program reports nothing" {
  let r = @pipeline.run(
    "///|\nfn f(n : Int) -> Unit {\n  ignore(1)\n}\n",
    "oneinitcontrol.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "UndefinedName"), 0)
}
