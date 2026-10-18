//| Tests for 0483 -- a PACKAGE-QUALIFIED METHOD HOLDER, `@pkg.Type::method`.
//|
//| THE DEFECT. `fn @io.ReaderBuffer::repr(buf : Self) -> @io_buffer.Buffer = "%identity"` is the
//| boundary line of three of async's sixteen unreadable files. It reads like a missing
//| foreign-function body -- a `= "string"` where a `{ }` would go -- and it is not. Measured
//| against this analyzer's own parser with a nine-case probe, not inferred:
//|
//|     fn Buf::repr(b : Buf) -> Int = "%identity"       first_error = 0   <- already works
//|     fn Buf::repr(b : Buf) -> Int { 1 }               first_error = 0
//|     extern "C" fn exit(code : Int) = "exit"          first_error = 0
//|     type @pkg.Buf                                   first_error = 0   <- @pkg is fine
//|     fn @pkg.Buf::repr(b : Buf) -> Int = "%identity"  first_error = 2   <- HERE
//|     fn @pkg.Buf::repr(b : Buf) -> Int { 1 }          first_error = 2
//|     fn @pkg.Buf::repr(b : Buf)                       first_error = 2
//|     extern "C" fn @pkg.Buf::repr(...) = "x"          first_error = 2
//|
//| The body form is IRRELEVANT and the `@pkg.` is decisive. Reading the boundary line would have
//! produced an extern-body production for a body this parser already reads in every other
//! spelling.
//!
//| THE `@` IS INSIDE THE NAME TOKEN, which is the whole shape of the fix. `Lexer::run` starts a
//! name at `@`, so `@other` is ONE `TName("@other")` and the `.` is a separate `TDot`. There
//! is no `TAt` in the token enum at all, which is why an earlier reading of the enum did not
//! find the arm and would have sent the fix looking for a token that does not exist.
//!
//| Settled in `_verify/settle_0483_pkg_qualified_holder.ps1`, 9 rows / 3 controls, GATE OK:
//!   ACCEPT  `fn @other.Buf::m(...) = "%identity"`   the corpus shape
//!   ACCEPT  the same with a brace body               so the body is not the point
//!   ACCEPT  `fn @other.Buf::m(self : @other.Buf)`   labelled, as the corpus writes it
//!   ACCEPT  `async fn @other.Buf::m(...)`
//!   REJECT(4059)  `pub fn @other.Buf::m(...)`         "Cannot define method for foreign type"
//!   REJECT(4156)  `extern "C" fn @other.Buf::m(...)`
//!
//! `pub` IS NOT PART OF THIS GRAMMAR and the corpus agrees -- all three async sites are non-pub
//! `fn`. The analyzer reads `pub fn @pkg.T::m` anyway, which is a MISSED error in the same
//! direction as the `for let` and one-line-header gaps; `record_pub_qualified_holder` carries it.

///|
/// THE DECLARATION IS READ, AND THE NAME IS THE WHOLE QUALIFIED PATH.
///
/// A row asserting only `first_error == 0` would pass against a reader that consumed the
/// tokens and threw the function away, which is precisely the failure 0482's M3 was written
/// for. So this asserts on the NAME the AST carries -- `@other.Buf::repr`, not `@other`.
test "0483: a package-qualified holder reads whole" {
  let r = @parser.parse(
    "///|\nfn @other.Buf::repr(b : @other.Buf) -> Int = \"%identity\"\n",
  )
  assert_eq(r.first_error, 0)
  match r.tree.body[0].kind {
    @ast.SFunc(name, _, _, _, _) => assert_eq(name, "@other.Buf::repr")
    _ => assert_true(false)
  }
}

///|
/// THE HOLDER WITHOUT A METHOD, which is the other half of the fold: `fn @other.Buf::zero()`.
///
/// A reader that only ever looked three tokens ahead for `::` would take the name as
/// `@other.Buf` and stop -- leaving the rest as a stray. Settled as C2 (with a brace body).
test "0483: a package-qualified type with no method name reads whole" {
  let r = @parser.parse("///|\nfn @other.Buf::zero() -> Int = \"%identity\"\n")
  assert_eq(r.first_error, 0)
  match r.tree.body[0].kind {
    @ast.SFunc(name, _, _, _, _) => assert_eq(name, "@other.Buf::zero")
    _ => assert_true(false)
  }
}

///|
/// THE LABELLED-PARAMETER SPELLING, which is what two of the three corpus sites write:
/// `fn @fs.CreateMode::to_int(self : @fs.CreateMode) -> Int` and `self : Self`.
///
/// The parameter TYPE is a separate production from the holder, and this row is what says the
/// fix did not stop at the first `:` it saw. Settled as C3.
test "0483: a package-qualified holder with a labelled self parameter reads whole" {
  let r = @parser.parse(
    "///|\nfn @other.Buf::to_int(self : @other.Buf) -> Int = \"%identity\"\n",
  )
  assert_eq(r.first_error, 0)
  match r.tree.body[0].kind {
    @ast.SFunc(name, params, _, _, _) => {
      assert_eq(name, "@other.Buf::to_int")
      assert_eq(params.length(), 1)
      assert_eq(params[0].name, "self")
    }
    _ => assert_true(false)
  }
}

///|
/// THE CONTROL, and the row that makes the three above mean something: an UNQUALIFIED holder,
/// which this parser already read. It is the same declaration with two characters deleted, so
/// the pair is a two-character A/B rather than an argument from a comment.
test "0483 CONTROL: an unqualified holder is unchanged" {
  let r = @parser.parse("///|\nfn Buf::repr(b : Buf) -> Int = \"%identity\"\n")
  assert_eq(r.first_error, 0)
  match r.tree.body[0].kind {
    @ast.SFunc(name, _, _, _, _) => assert_eq(name, "Buf::repr")
    _ => assert_true(false)
  }
}

///|
/// THE CONTROL FOR THE GUARD ITSELF. `fn f.bar` is not a declaration, the dot arm is keyed on
/// the `@` precisely so this stays refused, and without a row saying so a future edit that
/// widened the guard to any dot would look like a harmless generalization.
///
/// `moon check` REJECTs this as well, so the analyzer is not being stricter than the compiler --
/// but the row exists to pin THAT, not to argue it.
test "0483 CONTROL: a dot after an unqualified declaration name is still refused" {
  let r = @parser.parse("///|\nfn f.bar(b : Int) -> Int = \"%identity\"\n")
  assert_true(r.first_error != 0)
}

///|
/// THE HALF NO PARSE COUNT COULD HAVE CAUGHT, and the reason the fix is two edits rather than
/// one. `parse_fn_signature` folds `@other` `.` `Buf` `::` `repr` into the AST name, and
/// `declared_name_at` folds the same path to HARVEST it. Fixing only the first is the worst
/// outcome available: the file PARSES, so `parsed` goes UP and a corpus scan calls it a fix,
/// while the harvest carries `@other` and every resolution of `@other.Buf::repr` misses.
///
/// `collect_declared_names` is `pub`, so this asserts the harvest DIRECTLY. The first draft of
/// this row asserted instead that a CALL to the method is not reported as an undefined name --
/// and it was VACUOUS. A method call resolves through the type's interface table, which is
/// empty for a foreign type, so the structural lens never had a candidate and reported nothing
/// either way. Mutations M1 and M4 both survived it. Asking the harvest what it contains is
/// the question that was being answered badly.
test "0483: the harvest carries the whole qualified name" {
  let tab = @parser.collect_declared_names(
    "///|\nfn @other.Buf::repr(b : @other.Buf) -> Int = \"%identity\"\n",
  )
  assert_true(tab.has_value("@other.Buf::repr"))
}

///|
/// AND IT IS NOT A SUPERSET. Without this the row above and a fold that simply consumed `@`
/// and `.` and invented `@other` `@other.Buf` alongside the right name would both pass, and
/// the difference between "names the declared path" and "names everything near it" is the
/// difference between a harvest and a guess.
test "0483: the harvest does not also carry the truncated prefix" {
  let tab = @parser.collect_declared_names(
    "///|\nfn @other.Buf::repr(b : @other.Buf) -> Int = \"%identity\"\n",
  )
  assert_true(tab.has_value("@other.Buf::repr"))
  assert_false(tab.has_value("@other"))
  assert_false(tab.has_value("@other.Buf"))
}

///|
/// THE CONTROL FOR THE HARVEST, and the same argument the M3 control makes on the reader: an
/// UNQUALIFIED holder must still be harvested exactly as it always was. A fold keyed on the
/// `@` that reached past it would name `Buf::repr` twice under two spellings and this row
/// would be the only thing that noticed.
test "0483 CONTROL: an unqualified holder is still harvested as one name" {
  let tab = @parser.collect_declared_names(
    "///|\nfn Buf::repr(b : Buf) -> Int = \"%identity\"\n",
  )
  assert_true(tab.has_value("Buf::repr"))
}
