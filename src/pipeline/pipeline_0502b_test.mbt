///|
/// 0502b: THE SIX FALSE POSITIVES THAT READING A MATCH'S ARMS BROUGHT BACK.
///
/// Reading a match's arms is a change that makes findings APPEAR, and every
/// finding that appears has to be checked against the finding it makes appear.
/// These rows are that check, one row per mechanism.
///
/// EACH MECHANISM WAS FOUND THE SAME WAY: the arms surfaced a finding, the
/// finding was traced to its source in the corpus, and the COMPILER was asked
/// whether the corpus code is legal. All six are FALSE POSITIVES on code
/// `moon check` accepts.
///
///   1. `as` MAY START A NEW LINE. moonbitlang/async 0.22.4
///      `src/fs/watch.mbt:216,222,233` -- `no visible binding for 'as'`.
///      Settled: `_verify/settle_0502_as.ps1`, 6/6.
///   2. A DESTRUCTURING LET'S INITIALISER IS NOT DISCARDED.
///      moonbitlang/core `internal/regex_engine/shared_types/rechar_set/
///      rechar_set.mbt:202,214` -- `no visible binding for 'p'` / `'s'`.
///   3. A SAME-PACKAGE TYPE'S METHOD MAY BE CALLED UNQUALIFIED.
///      moonbitlang/core `immut/vector/invariants_wbtest.mbt:354,363,366` --
///      `no visible binding for 'makei'`. `Vector::makei` is declared at
///      `immut/vector/vector.mbt:68` and called unqualified in the same
///      package.
///   4. A STRUCT LITERAL'S FIELD VALUES ARE COLLECTED.
///      wzzc-dev/moui 0.1.12 `views/text/text_input_apply.mbt:166` --
///      `no visible binding for 'start'`.
///   5. AN ASSIGNMENT INTRODUCES NO BINDING. moonbitlang/async 0.22.4
///      `src/process/windows.mbt:105` -- `local variable 'segment_start'
///      assigned but may not be used`, for a name read at 109 and 110 inside a
///      nested local `fn`. The same shape in moonbitlang/core `diff/diff.mbt`
///      was reported for `i1` and `i2` and is gone.
///   6. A `with` CONSTRAINT READS. moonbitlang/core `builtin/option.mbt:50` --
///      `parameter 'default' may not be used`, for a parameter whose only
///      mention is `None with t = default`.
///
/// => 判据: A FIX THAT MAKES A FINDING APPEAR MUST BE CHECKED AGAINST THE
/// FINDING IT MAKES APPEAR. Six mechanisms produced six false positives, and
/// each one is now pinned by a row that says the finding must NOT come back.

///|
/// 1. `as` MAY START A NEW LINE. The cast is at the end of a block body, on
/// the line after its operand -- the async corpus shape. Before the fix the
/// `as` was left in the token stream and read as a name.
test "0502b: a cast may start a new line" {
  let src = "fn f(x : Int) -> Int {\n  match 0 {\n    0 => {\n      x\n      as &Bar\n    }\n    _ => 0\n  }\n}\n"
  let r = @pipeline.run(src, "x.mbt", @core.IfaceSymTab::empty())
  assert_eq(r.first_error_line, 0)
  assert_eq(count_family(r, "UndefinedName"), 0)
}

///|
/// AND ITS CANARY: the same shape with an undefined name beside the cast. The
/// cast's own TARGET TYPE is deliberately not resolved -- `type_annotation`
/// reads it and discards it, and a type name is not a binding -- so the canary
/// cannot be the cast's type. What the canary IS: the arm body is still read
/// after the cast, so the row above is not passing because the arm body was
/// never read.
test "0502b: the arm body is still read after a cast (canary)" {
  let src = "fn f(x : Int) -> Int {\n  match 0 {\n    0 => {\n      x\n      as &Bar\n      nope\n    }\n    _ => 0\n  }\n}\n"
  let r = @pipeline.run(src, "x.mbt", @core.IfaceSymTab::empty())
  assert_eq(count_family(r, "UndefinedName"), 1)
}

///|
/// 2. A DESTRUCTURING LET'S INITIALISER IS NOT DISCARDED. `let (lo, l) = {
/// let p = ..; p }` -- the inner `let p` is a real binding and the tail of
/// the block reads it. The collector threw the initialiser away, so the frame
/// never learned `p`.
test "0502b: a destructuring let's initialiser binds" {
  let src = "fn f(lo : Int) -> Int {\n  match 0 {\n    0 => {\n      let (lo, l) = {\n        let p = lo - 1\n        p\n      }\n      l\n    }\n    _ => 0\n  }\n}\n"
  let r = @pipeline.run(src, "x.mbt", @core.IfaceSymTab::empty())
  assert_eq(r.first_error_line, 0)
  assert_eq(count_family(r, "UndefinedName"), 0)
}

///|
/// 3. A SAME-PACKAGE TYPE'S METHOD MAY BE CALLED UNQUALIFIED. `Vector::makei`
/// is declared in the package and called as `makei`. The analyzer's package
/// table holds the QUALIFIED name, so the bare one resolved to nothing.
///
/// THE ROW IS ABOUT THE TABLE, and the table is built by the SCANNER
/// (`collect_private_symtabs`), not by this library -- so this row exercises
/// the table's own half, `IfaceSymTab::add_value`, and the rule that fills
/// the table with method segments is pinned in `src/sa/sa_0502_test.mbt`
/// (`@sa.method_segments`, `@sa.add_method_segments`), where the scanner
/// lives. The two rows chain: this one says a table entry under the bare name
/// makes the call RESOLVE, and that one says the segment rule puts the bare
/// name INTO the table. The gate `_verify/check_match_arms.ps1` section 4b
/// exercises the whole thing end to end on the real scanner.
test "0502b: a package table records a type's method under its bare name" {
  let src = "fn g() -> Int {\n  let v = makei(3, i => i)\n  v.len\n}\n"
  let t = @core.IfaceSymTab::empty()
  t.add_value("makei")
  let r = @pipeline.run(src, "x.mbt", t)
  assert_eq(r.first_error_line, 0)
  assert_eq(count_family(r, "UndefinedName"), 0)
}

///|
/// AND THE CONTROL for the same mechanism: without the bare name in the
/// table, the call resolves to nothing and IS reported. The row above is not
/// passing because undefined names are not reported at all.
test "0502b: a method called unqualified without the table entry is reported (control)" {
  let src = "fn g() -> Int {\n  let v = makei(3, i => i)\n  v.len\n}\n"
  let r = @pipeline.run(src, "x.mbt", @core.IfaceSymTab::empty())
  assert_eq(count_family(r, "UndefinedName"), 1)
}

///|
/// 4. A STRUCT LITERAL'S FIELD VALUES ARE COLLECTED. The inner `match` sits
/// in a struct-literal field, and the collector never descended into the
/// field, so the `let start` inside the arm body never reached the frame.
test "0502b: a struct literal's field values are collected" {
  let src = "fn f(n : Int) -> Int {\n  match 0 {\n    0 => {\n      let c = {\n        cursor: match n {\n          Some(v) => {\n            let start = v\n            start\n          }\n          None => 0\n        },\n      }\n      c.cursor\n    }\n    _ => 0\n  }\n}\n"
  let r = @pipeline.run(src, "x.mbt", @core.IfaceSymTab::empty())
  assert_eq(r.first_error_line, 0)
  assert_eq(count_family(r, "UndefinedName"), 0)
}

///|
/// 5. AN ASSIGNMENT INTRODUCES NO BINDING. The local is read inside a NESTED
/// LOCAL FUNCTION and assigned there too. The collector gave the inner scope
/// its own shadow of the name, so the read counted against the shadow and the
/// enclosing binding kept zero reads.
///
/// THE TOOLCHAIN SETTLED THE LANGUAGE: a local `fn` captures the enclosing
/// scope, so `x` inside it IS the enclosing `x`.
test "0502b: a local read inside a nested local fn is not a dead local" {
  let src = "fn f(k : Int) -> Unit {\n  let mut x = 0\n  fn g() {\n    if k > x {\n      ignore(k)\n    }\n    x = 1\n  }\n  g()\n}\n"
  let r = @pipeline.run(src, "x.mbt", @core.IfaceSymTab::empty())
  assert_eq(r.first_error_line, 0)
  assert_eq(count_family(r, "UnusedLocal"), 0)
}

///|
/// AND ITS CANARY: the same shape with the read REMOVED. The name really is
/// dead there, and the row above is not passing because the family is off.
test "0502b: a local assigned and never read is still reported (canary)" {
  let src = "fn f(k : Int) -> Unit {\n  let mut x = 0\n  fn g() {\n    x = 1\n  }\n  g()\n}\n"
  let r = @pipeline.run(src, "x.mbt", @core.IfaceSymTab::empty())
  assert_eq(count_family(r, "UnusedLocal"), 1)
}

///|
/// 6. A `with` CONSTRAINT READS. `None with t = default` binds `t` and READS
/// `default`, and `default` is a parameter whose only mention in the function
/// is inside that constraint.
test "0502b: a with constraint reads its right-hand side" {
  let src = "fn f(self : Int?, default : Int) -> Int {\n  match self {\n    Some(t) | (None with t = default) => t\n  }\n}\n"
  let r = @pipeline.run(src, "x.mbt", @core.IfaceSymTab::empty())
  assert_eq(r.first_error_line, 0)
  assert_eq(count_family(r, "UnusedParam"), 0)
}

///|
/// AND ITS CANARY: the constraint reads a name nothing binds, and that name
/// IS reported. The row above is not passing because the constraint is not
/// read at all.
test "0502b: a with constraint's read is resolved (canary)" {
  let src = "fn f(self : Int?) -> Int {\n  match self {\n    Some(t) | (None with t = nope) => t\n  }\n}\n"
  let r = @pipeline.run(src, "x.mbt", @core.IfaceSymTab::empty())
  assert_eq(count_family(r, "UndefinedName"), 1)
}

///|
/// AND THE CONTROL for the same mechanism: without the constraint the
/// parameter really is unused, and it is reported. The row above is not
/// passing because unused parameters are not reported at all.
test "0502b: a parameter read by no constraint is reported (control)" {
  let src = "fn f(self : Int?, default : Int) -> Int {\n  match self {\n    Some(t) | None => t\n  }\n}\n"
  let r = @pipeline.run(src, "x.mbt", @core.IfaceSymTab::empty())
  assert_eq(count_family(r, "UnusedParam"), 1)
}

///|
/// AND THE CONSTRAINT'S LEFT-HAND SIDE IS A PATTERN BINDING, not a local and
/// not a read: `with t = 1` binds `t`, and a binding that is never read is
/// not an unused local.
///
/// THE SHAPE IS NOT THE CORPUS SHAPE, and the reason is worth recording.
/// The corpus shape is `Some(t) | (None with t = default) => t` -- and there,
/// `Some(t)` binds `t` TOO, so the row cannot tell "the constraint's
/// left-hand side binds" from "the constraint's left-hand side reads": under
/// the second reading `t` is still bound by `Some(t)` and the row still
/// passes. A row that passes under both readings measures nothing.
///
/// So the constraint is the ONLY binder here, and the row has teeth: a
/// constraint whose left-hand side was read instead of bound would leave `t`
/// unbound and report it undefined.
test "0502b: a with constraint's left-hand side is a pattern binding" {
  let src = "fn f(self : Int?) -> Int {\n  match self {\n    (None with t = 1) => t\n  }\n}\n"
  let r = @pipeline.run(src, "x.mbt", @core.IfaceSymTab::empty())
  assert_eq(r.first_error_line, 0)
  assert_eq(count_family(r, "UnusedLocal"), 0)
  assert_eq(count_family(r, "UndefinedName"), 0)
}
