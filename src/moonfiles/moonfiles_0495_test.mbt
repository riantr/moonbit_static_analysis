///|
/// 0495: A TRAIT'S METHODS ARE VALUES, AND THE CROSS-FILE TABLE CARRIES THEM.
///
/// A `.mbti` declares a trait's methods INSIDE the trait's body:
///
///     pub(open) trait Writer {
///       async fn write_once(Self, Bytes, offset~ : Int, len~ : Int) -> Int
///       async fn write(Self, &Data) -> Unit = _
///       async fn write_reader(Self, &Reader) -> Unit = _
///     }
///
/// and the reader skipped every declaration body, exactly as it skips an
/// enum's. So a call to one of those methods from another file had no name to
/// resolve against:
///
///     undefined function '@io.Writer::write'
///
/// MEASURED, moonbitlang/async 0.22.4, three sites:
///
///     src/http/server.mbt:155   @io.Writer::write(self, s)
///     src/fs/file.mbt:510       @io.Reader::read_all(file)
///     src/fs/file.mbt:539       @io.Writer::write(file, content.binary())
///
/// on code `moon check` accepts.
///
/// THE NAME THE USE SITE RESOLVES TO is `Trait::method`: the package qualifier
/// is dropped by `unqualified` (`@core.unqualified`), so `@io.Writer::write`
/// becomes `Writer::write`. That is the key the table has to hold.
test "0495 E: a trait's methods are values in the cross-file table" {
  let tab = @moonfiles.collect_iface_names(
    "pub(open) trait Writer {\n  async fn write_once(Self, Bytes, offset~ : Int, len~ : Int) -> Int\n  async fn write(Self, &Data) -> Unit = _\n  async fn write_reader(Self, &Reader) -> Unit = _\n}\n",
  )
  assert_true(tab.has_value("Writer::write"))
  assert_true(tab.has_value("Writer::write_once"))
  assert_true(tab.has_value("Writer::write_reader"))
  // and through the package qualifier, which is how a use site spells it
  assert_true(tab.has_value("@io.Writer::write"))
}

///|
/// THE CONTROL: a method the trait does NOT declare is still not a value.
/// The harvest reads the trait's body; it does not invent a member.
test "0495 E control: a method the trait does not declare is not in the table" {
  let tab = @moonfiles.collect_iface_names(
    "pub(open) trait Writer {\n  async fn write(Self, &Data) -> Unit = _\n}\n",
  )
  assert_true(tab.has_value("Writer::write"))
  assert_false(tab.has_value("Writer::wrtie"))
}

///|
/// THE SECOND CONTROL: A TRAIT'S NAME IS A TYPE, AND ITS METHODS ARE NOT
/// TYPES. The two halves of the table must not be mixed up -- a member read
/// as a type is a different claim.
test "0495 E control: a trait's name is a type and its methods are not" {
  let tab = @moonfiles.collect_iface_names(
    "pub(open) trait Writer {\n  async fn write(Self, &Data) -> Unit = _\n}\n",
  )
  assert_true(tab.has_type("Writer"))
  assert_false(tab.has_type("Writer::write"))
}

///|
/// THE THIRD CONTROL: A METHOD DECLARED OUTSIDE A TRAIT BODY IS STILL READ
/// THE WAY IT ALWAYS WAS, and the harvest does not change the top-level
/// signature reader. A top-level `pub fn write(...)` is a value named
/// `write`.
test "0495 E control: a top-level signature is still a value under its own name" {
  let tab = @moonfiles.collect_iface_names("pub fn write(x : Int) -> Unit\n")
  assert_true(tab.has_value("write"))
  assert_false(tab.has_value("Writer::write"))
}
