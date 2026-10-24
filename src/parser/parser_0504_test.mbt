//| Tests for 0504 -- the COMPREHENSION GUARD.
//!
//! A comprehension may FILTER: `[ for x in xs if <cond> => <body> ]`. The
//! parser read that `if` and then THREW IT AWAY -- `ignore(self.parse_or())` --
//! so the `is` binding the condition introduces never reached the AST, and the
//! body's read of it had no binding to resolve. On `moonbitlang/core`
//! `hashset/hashset.mbt:382`:
//!
//!     [ for entry in self.entries if entry is Some({ key, .. }) => key ]
//!
//! that produced `undefined variable 'key'` -- a FALSE POSITIVE on a file the
//! toolchain compiles. 0503 (`raise?`) made that file readable, and 0504 is
//! what the readability exposed.
//!
//! THE COMPILER IS THE ORACLE, and `_verify/settle_0504_comp_guard.ps1` settles
//! the whole shape in 18 rows -- 16 with `moon check` and 2 with `moon test`:
//!
//!     the condition is COMPILED          an undefined name in it is an error
//!     the condition FILTERS              it is evaluated once per element
//!     the `is` binding reaches the body  and nothing else
//!     the condition may read the loop variable
//!
//! => 判据: a reader that keeps the condition and a reader that drops it DISAGREE
//! about a program the toolchain accepts. Dropping it is not the quiet direction
//! here -- it invents a finding -- so the condition is carried in the AST, and
//! the rows below pin WHERE it is carried and WHAT it carries.
//!
//! THE NODE IS NOW `EComp(vars, sources, cond, body)`. The condition sits
//! BETWEEN the iterable and the body because that is where it sits in the
//! source, and because that order IS the scope: the condition reads the loop
//! variables, and its own binding must be live when the body is read.

///|
/// Every comprehension in a module, in source order. A row can then say "the
/// tree holds one comprehension" by saying how many it found -- and the
/// `assert_eq(..., 1)` is what stops a row from passing on an EMPTY tree.
fn comps(m : @ast.Module) -> Array[@ast.EKind] {
  let out : Array[@ast.EKind] = []
  for s in m.body {
    match s.kind {
      @ast.SFunc(_, _, _, body, _) =>
        for st in body {
          match st.kind {
            @ast.SExpr(e) => collect_comps(e, out)
            @ast.STail(e) => collect_comps(e, out)
            _ => ()
          }
        }
      _ => ()
    }
  }
  out
}

///|
/// The comprehensions inside one expression. A comprehension is an element of
/// a list literal, so the walk starts at the list -- but it recurses, because a
/// comprehension may sit inside another one.
fn collect_comps(e : @ast.Expr, out : Array[@ast.EKind]) -> Unit {
  match e.kind {
    @ast.EList(xs) =>
      for x in xs {
        collect_comps(x, out)
      }
    @ast.EComp(_, _, _, _) => out.push(e.kind)
    _ => ()
  }
}

///|
/// THE TARGET SHAPE, and the one that produced the false positive. The
/// condition is CARRIED -- it is `Some(..)`, not `None` -- and it is an `is`
/// test whose binding is `key`.
///
/// The corpus shape is `moonbitlang/core` `hashset/hashset.mbt:382`, byte for
/// byte in form.
test "0504: a comprehension's condition is carried" {
  let r = @parser.parse(
    "fn f(entries : Array[Option[Entry]]) -> Array[Int] {\n  [\n    for entry in entries if entry is Some({ key, .. }) => key\n  ]\n}\n",
  )
  assert_eq(r.first_error, 0)
  let cs = comps(r.tree)
  assert_eq(cs.length(), 1)
  match cs[0] {
    @ast.EComp(_, _, cond, _) =>
      match cond {
        Some(g) =>
          match g.kind {
            @ast.EIs(_, bindings) => assert_eq(bindings.length(), 1)
            _ => assert_true(false)
          }
        None => assert_true(false)
      }
    _ => assert_true(false)
  }
}

///|
/// THE BINDING IS THE ONE THE PATTERN INTRODUCES, and it is `key` and not
/// `entry` and not `Some`. The condition's own `is` pattern is reduced to the
/// names it binds, and the body reads exactly that name.
///
/// This is the row that fails if the condition is carried with the WRONG
/// binding -- a condition carried with no binding at all would still make the
/// first row pass.
test "0504: the carried condition carries the binding the pattern introduces" {
  let r = @parser.parse(
    "fn f(entries : Array[Option[Entry]]) -> Array[Int] {\n  [\n    for entry in entries if entry is Some({ key, .. }) => key\n  ]\n}\n",
  )
  assert_eq(r.first_error, 0)
  let cs = comps(r.tree)
  match cs[0] {
    @ast.EComp(_, _, cond, _) =>
      match cond {
        Some(g) =>
          match g.kind {
            @ast.EIs(_, bindings) => assert_eq(bindings[0], "key")
            _ => assert_true(false)
          }
        None => assert_true(false)
      }
    _ => assert_true(false)
  }
}

///|
/// THE CONTROL FOR THE TWO ROWS ABOVE: a comprehension with NO condition
/// carries NONE. The condition is optional, and a reader that made it
/// mandatory -- or that filled the slot with a placeholder -- would break this
/// row.
///
/// It is also the row that says the change did not disturb the ordinary
/// comprehension, which is the overwhelming majority of them.
test "0504: a comprehension with no condition carries none" {
  let r = @parser.parse(
    "fn f(xs : Array[Int]) -> Array[Int] {\n  [ for x in xs => x ]\n}\n",
  )
  assert_eq(r.first_error, 0)
  let cs = comps(r.tree)
  assert_eq(cs.length(), 1)
  match cs[0] {
    @ast.EComp(_, _, cond, _) =>
      match cond {
        Some(_) => assert_true(false)
        None => ()
      }
    _ => assert_true(false)
  }
}

///|
/// THE OTHER CONTROL: a condition that binds NOTHING is still carried. The
/// condition is not "the `is` test" -- it is an EXPRESSION, and an expression
/// that happens to contain an `is` test is one case of it.
///
/// `Some(_)` binds nothing, which is the shape the settle's NO-BINDING CONTROL
/// measured (`_verify/settle_0504_comp_guard.ps1`, row G).
test "0504: a condition whose is-test binds nothing is still carried" {
  let r = @parser.parse(
    "fn f(args : Array[Option[Int]]) -> Array[Option[Int]] {\n  [ for arg in args if arg is Some(_) => arg ]\n}\n",
  )
  assert_eq(r.first_error, 0)
  let cs = comps(r.tree)
  assert_eq(cs.length(), 1)
  match cs[0] {
    @ast.EComp(_, _, cond, _) =>
      match cond {
        Some(g) =>
          match g.kind {
            @ast.EIs(_, bindings) => assert_eq(bindings.length(), 0)
            _ => assert_true(false)
          }
        None => assert_true(false)
      }
    _ => assert_true(false)
  }
}

///|
/// A CONDITION THAT IS NOT AN `is` TEST AT ALL. This is the shape 8 of the 9
/// comprehensions in `moonbitlang/core` use -- `if !arg.hidden`,
/// `if arg.info is PositionalInfo(_)`, `if args.search_by(arg => ..)` -- and it
/// is the one that carries the READS: a name read only inside a condition is a
/// real read, because the toolchain evaluates the condition once per element
/// (settle row RT1).
test "0504: a condition that only reads the loop variable is carried" {
  let r = @parser.parse(
    "fn f(args : Array[Arg]) -> Array[Arg] {\n  [ for arg in args if !arg.hidden => arg ]\n}\n",
  )
  assert_eq(r.first_error, 0)
  let cs = comps(r.tree)
  assert_eq(cs.length(), 1)
  match cs[0] {
    @ast.EComp(vars, _, cond, _) => {
      assert_eq(vars.length(), 1)
      match cond {
        Some(_) => ()
        None => assert_true(false)
      }
    }
    _ => assert_true(false)
  }
}

///|
/// THE BODY IS STILL THE BODY. The condition is a NEW FIELD, and a reader that
/// put it where the body was would parse the program and then analyse the
/// wrong expression -- silently, because both are expressions.
///
/// The body of this comprehension is `x`, and the condition is `x > 0`. If the
/// two were swapped, the body's `x` would be the comparison and the condition
/// would be the name -- and the row would still see an `EComp` with a
/// `Some(..)` condition.
test "0504: the body is still the body after the condition" {
  let r = @parser.parse(
    "fn f(xs : Array[Int]) -> Array[Int] {\n  [ for x in xs if x > 0 => x ]\n}\n",
  )
  assert_eq(r.first_error, 0)
  let cs = comps(r.tree)
  match cs[0] {
    @ast.EComp(_, _, cond, body) => {
      match cond {
        Some(g) =>
          match g.kind {
            @ast.EBin(_, _, _) => ()
            _ => assert_true(false)
          }
        None => assert_true(false)
      }
      match body.kind {
        @ast.EName(n) => assert_eq(n, "x")
        _ => assert_true(false)
      }
    }
    _ => assert_true(false)
  }
}

///|
/// THE LOOP VARIABLES AND THE ITERABLE ARE STILL CARRIED, and the iterable is
/// still read. The condition is a THIRD thing, not a replacement for either of
/// the first two -- and the corpus has comprehensions with all three:
///
///     [ for entry in self.entries if entry is Some({ key, .. }) => key ]
test "0504: the loop variable and the iterable are still carried" {
  let r = @parser.parse(
    "fn f(entries : Array[Option[Entry]]) -> Array[Int] {\n  [\n    for entry in entries if entry is Some({ key, .. }) => key\n  ]\n}\n",
  )
  assert_eq(r.first_error, 0)
  let cs = comps(r.tree)
  match cs[0] {
    @ast.EComp(vars, sources, _, _) => {
      assert_eq(vars.length(), 1)
      assert_eq(vars[0], "entry")
      assert_eq(sources.length(), 1)
      match sources[0].kind {
        @ast.EName(n) => assert_eq(n, "entries")
        _ => assert_true(false)
      }
    }
    _ => assert_true(false)
  }
}

///|
/// A COMPREHENSION WITH A CONDITION AND A BLOCK BODY -- the shape the settle's
/// block-body rows measured. The block body's statements are parsed, and the
/// condition is carried alongside them.
test "0504: a condition with a block body is carried" {
  let r = @parser.parse(
    "fn f(entries : Array[Option[Entry]]) -> Array[Int] {\n  [\n    for entry in entries if entry is Some({ key, .. }) => { let k = key; k + 1 }\n  ]\n}\n",
  )
  assert_eq(r.first_error, 0)
  let cs = comps(r.tree)
  assert_eq(cs.length(), 1)
  match cs[0] {
    @ast.EComp(_, _, cond, _) =>
      match cond {
        Some(_) => ()
        None => assert_true(false)
      }
    _ => assert_true(false)
  }
}
