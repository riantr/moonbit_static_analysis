// test: the 0570 rows -- the three shapes the re-pinned corpus exposed.
//
// ALL THREE ARE FALSE POSITIVES ON CODE `moon check` COMPILES, and all three
// were measured on moonbitlang/core 0.1.20261105+65efd5b93:
//
//   0x1.0p54                       math/log_double_nonjs.mbt:131 and :216
//                                  -> `undefined variable 'p54'`
//   @encoding/utf8.encode(s)       archive/zip/writer.mbt:194
//                                  archive/zip/stream_writer.mbt:149
//                                  -> `undefined variable 'utf8'`
//   Err(e) if allow_missing => ()  async/fs/file.mbt:465
//                                  -> `parameter 'allow_missing' may not be
//                                     used`
//
// Each one is a fragment of a construct the analyzer did not know: a hex float
// SPLIT into an integer and a name, a package path SPLIT into a name and a
// division, and a catch guard's names READ AS BINDINGS. A false positive is
// fixed, never pinned -- so each of these has a row here, and each row has a
// control beside it that must still report.
//
// The fix is in the source, not in the census: the 0.4.46 census had DEMOTED
// twelve of these hex-float findings rather than fixing them, which is what
// this project calls "a set that can go missing silently".

///|
/// A HEX FLOAT IS ONE LITERAL. The whole point of the row is the name count:
/// before the fix the literal left `p54` behind, and `p54` had no binding.
test "0570: a hex float produces no undefined name" {
  let r = @pipeline.run(
    "fn f(x : Double) -> Double {\n  x * 0x1.0p54\n}\n",
    "x.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(r.first_error_line, 0)
  assert_eq(count_family(r, "UndefinedName"), 0)
}

///|
/// A PACKAGE PATH IS NOT A VARIABLE. `@encoding/utf8` names a PACKAGE, and the
/// toolchain's own error says so ("Cannot use @encoding/utf8: package
/// encoding/utf8 is not imported.") -- so the analyzer reporting `utf8` as an
/// undefined variable was reporting a package's last path segment as a name.
test "0570: a package path produces no undefined name" {
  let r = @pipeline.run(
    "fn f(s : String) -> Int {\n  let b = @encoding/utf8.encode(s)\n  b.length()\n}\n",
    "x.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(r.first_error_line, 0)
  assert_eq(count_family(r, "UndefinedName"), 0)
}

///|
/// A CATCH ARM'S GUARD IS CODE, AND ITS READS ARE READS. The parameter is read
/// in the guard and nowhere else, so before the fix -- when the guard's names
/// were collected as PATTERN NAMES, and a pattern name is a binding and not a
/// read -- the parameter had no read at all and was reported unused.
test "0570: a catch arm's guard reads the parameter" {
  let r = @pipeline.run(
    "fn f(allow_missing : Bool) -> Int {\n  0 catch {\n    e if allow_missing => 1\n    _ => 2\n  }\n}\n",
    "x.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(r.first_error_line, 0)
  assert_eq(count_family(r, "UnusedParam"), 0)
}

///|
/// THE SAME ROW FOR A LOCAL, and it is here because the direction of the error
/// matters: the guard's read of `flag` was a BINDING of `flag`, so the local
/// looked unread. A false `unused` is the same defect as a false `unused
/// parameter` wearing a different hat.
test "0570: a catch arm's guard reads an enclosing local" {
  let r = @pipeline.run(
    "fn f() -> Int {\n  let flag = true\n  0 catch {\n    e if flag => 1\n    _ => 2\n  }\n}\n",
    "x.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(r.first_error_line, 0)
  assert_eq(count_family(r, "UnusedLocal"), 0)
}

///|
/// THE CONTROL FOR THE TWO ROWS ABOVE. A parameter the guard does NOT read is
/// still unread, and it must still be reported: if the guard simply stopped
/// counting as a read -- or if the arm's bindings had stopped being bindings
/// -- these two rows would pass while the analyzer had stopped saying anything
/// at all.
test "0570 control: a parameter no guard reads is still reported unused" {
  let r = @pipeline.run(
    "fn f(unused_param : Bool) -> Int {\n  0 catch {\n    e => 1\n    _ => 2\n  }\n}\n",
    "x.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "UnusedParam"), 1)
}

///|
/// THE CONTROL FOR THE OTHER DIRECTION. A local that is genuinely never read
/// is still reported, guard or no guard -- the fix made the guard's read
/// visible, not the family quiet.
test "0570 control: a local no guard reads is still reported unused" {
  let r = @pipeline.run(
    "fn f() -> Int {\n  let never_read = 1\n  0 catch {\n    e => 1\n    _ => 2\n  }\n}\n",
    "x.mbt",
    @core.IfaceSymTab::empty(),
  )
  assert_eq(count_family(r, "UnusedLocal"), 1)
}
