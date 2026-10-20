//| 0490: FIVE defects the PER-FUNCTION view made visible, each with a control.
//
//| THE CONTEXT. 0489 gave the behavioral lens a per-function entry, and the
//| per-function view reported 265 actionable findings on moui 0.1.12 where the
//| module view reports 0. Those 265 were not 265 defects -- they were an
//| INVENTORY of what was still wrong with the lens, and this file is the
//| measurement of FIVE of those classes, each of which was a lens defect
//| rather than a defect in the code being analysed.
//
//| EVERY ROW HAS A CONTROL, and the control is the point. A fix that silences
//| a class of finding is worth nothing if the class was the only thing that
//| distinguished a wrong program from a right one, so each row is paired with
//| a row that must STILL report.

///|
/// A LIST VALUE AGAINST A LIST PARAMETER IS NOT A TYPE ERROR.
///
/// The two lenses spell a list differently and never met: the TYPE lens
/// writes a list type as `[int]` (`ty_name`), the BEHAVIORAL lens writes a
/// list VALUE as `List` (`abs_of`), and `vmatches` compares a value name
/// against a type name. So "List" was never equal to "[int]", and every call
/// passing a list was reported `no method matching take(List)` -- on code
/// `moon check` accepts.
test "a list value is not a type error against a list parameter" {
  let src = "fn take(xs : Array[Int]) -> Int {\n  xs.length()\n}\n\nfn caller(list : Array[Int]) -> Int {\n  take(list)\n}\n"
  let perfn = @pipeline.run_functions(src, "x.mbt", @core.IfaceSymTab::empty())
  assert_eq(count_family(perfn, "MethodError"), 0)
}

///|
/// THE CONTROL FOR THE ROW ABOVE: a value that is NOT a list is still a type
/// error against a list parameter. Without this row, a rule that silenced
/// every call whose parameter happened to be a list would pass the row above.
test "a non-list value against a list parameter is still an error" {
  let src = "fn take(xs : Array[Int]) -> Int {\n  xs.length()\n}\n\nfn caller(n : Int) -> Int {\n  take(n)\n}\n"
  let perfn = @pipeline.run_functions(src, "x.mbt", @core.IfaceSymTab::empty())
  assert_eq(count_family(perfn, "MethodError"), 1)
}

///|
/// A CALL THAT OMITS AN OPTIONAL PARAMETER IS NOT A METHOD ERROR.
///
/// `name? : T` is the OPTIONAL spelling, and the toolchain accepts a call that
/// omits it (settled with `moon check` 0.1.20261012, re-settled on
/// 0.1.20261016). The arity check used to compare the argument count against
/// the DECLARED count, so every such call was reported.
test "a call that omits an optional parameter is not a method error" {
  let src = "fn opt(x : Int, y? : Int) -> Int {\n  x + (y.unwrap_or(0))\n}\n\nfn caller(a : Int) -> Int {\n  opt(a)\n}\n"
  let perfn = @pipeline.run_functions(src, "x.mbt", @core.IfaceSymTab::empty())
  assert_eq(count_family(perfn, "MethodError"), 0)
}

///|
/// THE OTHER OMITTABLE SPELLING: a LABELLED parameter with a DEFAULT value.
/// `fn labelled_default(x : Int, y~ : Int = 0)` called as `labelled_default(1)`
/// COMPILES -- settled with the toolchain, not assumed.
test "a call that omits a labelled parameter with a default is not an error" {
  let src = "fn labelled(x : Int, y~ : Int = 0) -> Int {\n  x + y\n}\n\nfn caller(a : Int) -> Int {\n  labelled(a)\n}\n"
  let perfn = @pipeline.run_functions(src, "x.mbt", @core.IfaceSymTab::empty())
  assert_eq(count_family(perfn, "MethodError"), 0)
}

///|
/// THE CONTROL FOR THE TWO ROWS ABOVE: a call that omits a REQUIRED parameter
/// is still an error. The toolchain agrees -- "This function has type
/// (Int) -> Int, which requires 1 arguments, but is given 0 arguments" (4080)
/// -- and an arity rule that simply stopped counting would pass both rows
/// above and fail this one.
test "a call that omits a required parameter is still an error" {
  let src = "fn required(x : Int) -> Int {\n  x\n}\n\nfn caller() -> Int {\n  required()\n}\n"
  let perfn = @pipeline.run_functions(src, "x.mbt", @core.IfaceSymTab::empty())
  assert_eq(count_family(perfn, "MethodError"), 1)
}

///|
/// THE OTHER CONTROL FOR THE SAME RULE: a call that passes too MANY arguments
/// is still an error. The rule is a RANGE -- `declared - omittable <=
/// arguments <= declared` -- and this row is what stops it from being a
/// blanket.
test "a call that passes too many arguments is still an error" {
  let src = "fn one(x : Int) -> Int {\n  x\n}\n\nfn caller() -> Int {\n  one(1, 2)\n}\n"
  let perfn = @pipeline.run_functions(src, "x.mbt", @core.IfaceSymTab::empty())
  assert_eq(count_family(perfn, "MethodError"), 1)
}

///|
/// A FUNCTION WHOSE BODY IS AN `if` RETURNS THE BRANCH'S VALUE.
///
/// The branch's value was evaluated and DISCARDED -- the `SIf` arm ran the
/// branch, and the branch's trailing expression was an `SExpr`, whose value
/// nothing kept. So the function's `ret_vals` stayed empty, `join_vals([])`
/// answered "None", and every operator applied to the result was reported as a
/// method error: `no method matching +(None, int)`.
///
/// MEASURED on moui 0.1.12: `clamp_double` is an `if` body, and every call
/// site of it inherited the "None".
test "a function whose body is an if returns the branch value" {
  let src = "fn pick(v : Int, lo : Int, hi : Int) -> Int {\n  if v < lo {\n    lo\n  } else {\n    hi\n  }\n}\n\nfn caller() -> Int {\n  let x = pick(1, 0, 2)\n  let y = x + 1\n  1\n}\n"
  let perfn = @pipeline.run_functions(src, "x.mbt", @core.IfaceSymTab::empty())
  assert_eq(count_family(perfn, "MethodError"), 0)
}

///|
/// THE CONTROL FOR THE ROW ABOVE: a function whose body's last statement is a
/// `let` returns UNIT, and using that as a number IS an error. So the "None"
/// answer is right in that case, and the fix must not have replaced it with
/// "some value we know nothing about" -- which would silence the finding.
test "a function whose body's last statement is a let returns unit, and that is an error" {
  let src = "fn nothing() -> Int {\n  let y = 1\n  ()\n}\n\nfn caller() -> Int {\n  let x = nothing()\n  let y = x + 1\n  1\n}\n"
  let perfn = @pipeline.run_functions(src, "x.mbt", @core.IfaceSymTab::empty())
  assert_eq(count_family(perfn, "MethodError"), 1)
}

///|
/// A STRING CONCATENATION IS A STRING.
///
/// `bin_widen` had arms for `float`, for `Any`, and the `int` fallback -- and
/// none for two strings, so `"a" + "b"` evaluated to the type "int". The
/// consequence was a false positive on the OUTER `+` of a concatenation:
/// `("a" + "b") + "c"` has an "int" left operand and a "str" right one, and
/// the operator check reported `no method matching +(int, str)` -- on code
/// `moon check` accepts. Measured on moui 0.1.12
/// `render/common/provider_shell.mbt:10`.
test "a string concatenation is a string" {
  let src = "fn cat(a : String, b : String) -> String {\n  a + b\n}\n\nfn caller() -> String {\n  let s = cat(\"x\", \"y\")\n  let t = s + \"z\"\n  s\n}\n"
  let perfn = @pipeline.run_functions(src, "x.mbt", @core.IfaceSymTab::empty())
  assert_eq(count_family(perfn, "MethodError"), 0)
}

///|
/// THE CONTROL FOR THE ROW ABOVE: an `Int` added to a `String` is still an
/// error. The fix is a STRING arm in `bin_widen`, not a rule that stopped
/// checking the operands.
test "an int added to a string is still an error" {
  let src = "fn f() -> Int {\n  let x = 1 + \"a\"\n  x\n}\n"
  let perfn = @pipeline.run_functions(src, "x.mbt", @core.IfaceSymTab::empty())
  assert_eq(count_family(perfn, "MethodError"), 1)
}

///|
/// TWO STRINGS COMPARE.
///
/// The comparison operators accepted only `numeric(l) && numeric(r)`, and a
/// String comparison is legal MoonBit -- settled with the toolchain: `fn
/// cmp_string(a : String, b : String) -> Bool { a <= b }` COMPILES.
///
/// MEASURED, the corpus paid for the missing case: proton 0.3.4 reported
/// `no method matching <=(str, str)` and `>=(str, str)` -- eight findings, on
/// code `moon check` accepts.
test "two strings compare" {
  let src = "fn cmp(a : String, b : String) -> Bool {\n  a <= b\n}\n\nfn caller() -> Bool {\n  cmp(\"a\", \"b\")\n}\n"
  let perfn = @pipeline.run_functions(src, "x.mbt", @core.IfaceSymTab::empty())
  assert_eq(count_family(perfn, "MethodError"), 0)
}

///|
/// THE CONTROL FOR THE ROW ABOVE: a MIXED comparison is still an error. The
/// fix is `strv(l) && strv(r)`, which is as narrow as the `+` arm's.
test "an int compared with a string is still an error" {
  let src = "fn f() -> Bool {\n  let x = 1 <= \"a\"\n  x\n}\n"
  let perfn = @pipeline.run_functions(src, "x.mbt", @core.IfaceSymTab::empty())
  assert_eq(count_family(perfn, "MethodError"), 1)
}

///|
/// THE MODULE VIEW MUST NOT HAVE MOVED. Every fix above is in the BEHAVIORAL
/// lens, and the module entry does not execute a function body -- so its
/// numbers are the pinned ones, and this row is the statement of that.
///
/// It is a row rather than a comment because the corpus pins are a SUMMARY
/// line, and a SUMMARY line cannot tell two states apart.
test "the module view is unchanged by the per-function fixes" {
  let src = "fn take(xs : Array[Int]) -> Int {\n  xs.length()\n}\n\nfn caller(list : Array[Int]) -> Int {\n  take(list)\n}\n"
  let modview = @pipeline.run(src, "x.mbt", @core.IfaceSymTab::empty())
  let perfn = @pipeline.run_functions(src, "x.mbt", @core.IfaceSymTab::empty())
  assert_eq(perfn.n_structural, modview.n_structural)
  assert_eq(perfn.n_type, modview.n_type)
}

///|
/// A BUILTIN METHOD UNDER THE NEW SPELLING IS NOT UNDEFINED.
///
/// The toolchain changed the CANONICAL SPELLING of the integer type on
/// 0.1.20261012 -- `Int` is now `Int32` -- and declares ALL FORTY-FOUR of the
/// integer type's methods under the new spelling --
/// `Int32::popcnt`, `Int32::to_char`, `Int32::next_power_of_two` -- and NONE
/// under the old one. The analyzer's builtin-method TABLE is the only thing
/// that decides whether a qualified call is a builtin or an undefined name, and
/// the table had the old spelling only.
///
/// So a user who wrote `Int32::popcnt(x)` -- or whose `moon fmt` rewrote
/// `Int::popcnt` into `Int32::popcnt`, which it does, because the new
/// spelling is the toolchain's canonical form -- got `undefined function
/// 'Int32::popcnt'` on code `moon check` accepts. Settled with the toolchain:
/// `Int32::popcnt(x)` COMPILES.
///
/// THE TYPE DID NOT CHANGE, and that is what the official wording says: "Int
/// and UInt remain accepted as aliases of Int32 and UInt32. The formatter uses
/// the explicit-width names Int32 and UInt32."
/// (https://docs.moonbitlang.com/en/latest/language/fundamentals.html)
test "0490: a builtin method under the new spelling is not undefined" {
  let src = "fn f(x : Int32) -> Int32 {\n  Int32::popcnt(x)\n}\n"
  let perfn = @pipeline.run_functions(src, "x.mbt", @core.IfaceSymTab::empty())
  assert_eq(count_family(perfn, "UndefinedName"), 0)
}

///|
/// THE OLD SPELLING OF THE SAME METHOD STILL RESOLVES, because the table
/// carries BOTH: a name the toolchain has renamed is a MISSED report, and a
/// name the toolchain still has is a FALSE POSITIVE, and only the second is
/// acceptable.
test "0490: the old spelling of the same builtin method still resolves" {
  let src = "fn f(x : Int) -> Int {\n  Int::popcnt(x)\n}\n"
  let perfn = @pipeline.run_functions(src, "x.mbt", @core.IfaceSymTab::empty())
  assert_eq(count_family(perfn, "UndefinedName"), 0)
}

///|
/// THE CONTROL FOR THE TWO ROWS ABOVE. A method that does not exist under
/// EITHER spelling is still reported -- the fix is a TABLE of measured names,
/// not a rule that stopped reporting qualified calls, and the table's own
/// header records why: it only ever suppresses, so a name it misses is noise
/// and a name it invents is a false alarm.
test "0490: a method that does not exist under the new spelling is still reported" {
  let src = "fn f(x : Int32) -> Int32 {\n  Int32::popcntnope(x)\n}\n"
  let perfn = @pipeline.run_functions(src, "x.mbt", @core.IfaceSymTab::empty())
  assert_eq(count_family(perfn, "UndefinedName"), 1)
}
