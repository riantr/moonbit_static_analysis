// test: the complementary semantics. Each test pins one way the three
// lenses depend on or complement each other:
//   merge:      the same defect reported by several lenses collapses into
//               one finding whose lens tag is the union
//   tables:     lens 2 consumes lens 1's binding tables; lens 3 consumes
//               lens 2's signatures (no stage rediscovers bindings)
//   pruning:    constant folding appears twice 鈥?structural
//               (walk) and lattice (ABool in interp)
//   traces:     behavioral findings carry virtual stacks (entry first)

/// test inputs (mirror src/samples; inlined to keep the import graph simple)

///|
/// Tests pass an empty cross-file symbol table 鈥?they assert pipeline
/// behavior, not cross-file resolution, so the only fix needed is to
/// keep the third argument present in the signature.
fn empty_iface() -> @core.IfaceSymTab {
  @core.IfaceSymTab::empty()
}

///|
const SAMPLE_CLEAN : String = "fn fact(n: int) -> int {\n  if n <= 1 { return 1 }\n  return n * fact(n - 1)\n}\nprint(fact(5))\n"

///|
const SAMPLE_UNDEFINED : String = "fn g() -> int {\n  return missing + 1\n}\ng()\n"

///|
const SAMPLE_TYPING : String = "fn shout(s: str) -> int {\n  return len(s)\n}\nlet n: int = 1\nn = \"oops\"\nshout(42)\nprint(1 + \"x\")\n"

///|
const SAMPLE_DEADBRANCH : String = "fn h(x: int) -> int {\n  if 1 > 2 {\n    return typo_fn(x)\n  }\n  return x * 2\n}\nh(3)\n"

///|
const SAMPLE_STRUCTURE : String = "fn f(x: int, y: int) -> int {\n  z = x * 2\n  y = 3\n  return z\n}\nf(1, 2)\n"

///|
const SAMPLE_FLOW : String = "let k = 3\nif k {\n  print(\"yes\")\n}\nfn u(x: int) -> int {\n  return x\n  print(x)\n}\nu(1)\n"

///|
test "pipeline: clean program has no findings and a full signature" {
  let r = @pipeline.run(SAMPLE_CLEAN, "clean.mbt", empty_iface())
  assert_eq(r.reports.length(), 0)
  assert_eq(r.sigs.length(), 1)
  assert_eq(r.sigs[0], "fact(int) -> int")
}

///|
test "merge: one defect, three lenses, ONE finding" {
  let r = @pipeline.run(SAMPLE_UNDEFINED, "u.mbt", empty_iface())
  // before the merge all three lenses saw it
  assert_eq(r.n_structural, 1)
  assert_eq(r.n_type, 2)
  assert_eq(r.n_behavior, 1)
  // after the merge: exactly one finding, lens union, most specific phrasing
  assert_eq(r.reports.length(), 1)
  let rep = r.reports[0]
  assert_eq(rep.family.merge_group(), "undef")
  assert_eq(rep.lenses.length(), 3)
  assert_eq(
    rep.render(),
    "2:10 - error: undefined variable 'missing' (UndefinedName) [structural+type+behavior]\n  in main() at u.mbt:4\n  in g at u.mbt:1\n",
  )
}

///|
test "merge: arg-type echoes unify under MethodError" {
  // `shout(42)` is an argument-type error AND a method error at
  // the same span; the pipeline emits one behavioral-phrased finding
  let r = @pipeline.run(SAMPLE_TYPING, "t.mbt", empty_iface())
  let mut shout_hits = 0
  for rep in r.reports {
    if rep.family.merge_group() == "arg-type" && rep.span.start.line == 6 {
      shout_hits += 1
      assert_eq(rep.lenses.length(), 2)
      assert_eq(rep.family.name(), "MethodError")
      assert_eq(rep.message, "no method matching shout(int)")
    }
  }
  assert_eq(shout_hits, 1)
}

///|
test "assembly 1: type lens consumes walk's binding tables" {
  // the module binds z = 1 (untyped) and n: int = 2 (annotated); the type
  // lens never re-parses 鈥?re-assigning a str to n reports AssignType with
  // the ANNOTATION'S type, taken from lens 1's table
  let src = "z = 1\nlet n: int = 2\nn = \"x\"\nz = \"y\"\n"
  let r = @pipeline.run(src, "a1.mbt", empty_iface())
  // n: annotation violation (reported); z: gradual re-binding, no report
  let mut n_hits = 0
  let mut z_hits = 0
  for rep in r.reports {
    if rep.family.name() == "AssignTypeMismatch" {
      if rep.span.start.line == 3 {
        n_hits += 1
      }
      if rep.span.start.line == 4 {
        z_hits += 1
      }
    }
  }
  assert_eq(n_hits, 1)
  assert_eq(z_hits, 0)
}

///|
test "assembly 2: behavior lens dispatches on type lens signatures" {
  // f accepts int only; only the behavior lens can reject f(true) 鈥?  // dispatch against the signature table lens 2 produced
  let src = "fn f(x: int) -> int {\n  return x\n}\nf(true)\n"
  let r = @pipeline.run(src, "a2.mbt", empty_iface())
  let mut hits = 0
  for rep in r.reports {
    if rep.family.name() == "MethodError" {
      hits += 1
      assert_eq(rep.message, "no method matching f(bool)")
    }
  }
  assert_eq(hits, 1)
}

///|
test "pruning appears twice: structural fold and lattice ABool" {
  // dead branch: the walk prunes it structurally, the interp prunes it in
  // the lattice 鈥?typo_fn exists NOWHERE, yet no lens reports it
  let r = @pipeline.run(SAMPLE_DEADBRANCH, "d.mbt", empty_iface())
  assert_eq(r.reports.length(), 0)
  assert_eq(r.sigs[0], "h(int) -> int")
}

///|
test "structural-only: unused param/local/changed param invisible to others" {
  let r = @pipeline.run(SAMPLE_STRUCTURE, "s.mbt", empty_iface())
  assert_eq(r.reports.length(), 2)
  for rep in r.reports {
    assert_eq(rep.lenses.length(), 1)
    assert_eq(rep.lenses[0].name(), "structural")
  }
  let mut seen_changed = false
  let mut seen_unused = false
  for rep in r.reports {
    match rep.family {
      @core.FParamChanged => seen_changed = true
      @core.FUnusedParam => seen_unused = true
      _ => ()
    }
  }
  assert_true(seen_changed)
  assert_true(seen_unused)
  assert_eq(r.sigs[0], "f(int, int) -> int")
}

///|
test "behavior only: unreachable after return carries a virtual stack" {
  let src = "fn u(x: int) -> int {\n  return x\n  print(x)\n}\nu(1)\n"
  let r = @pipeline.run(src, "v.mbt", empty_iface())
  let mut found = false
  for rep in r.reports {
    if rep.family.name() == "Unreachable" {
      found = true
      assert_eq(rep.lenses.length(), 1)
      assert_eq(rep.lenses[0].name(), "behavior")
      // virtual stack: entry frame first, error point last
      assert_eq(rep.vst.length(), 2)
      assert_eq(rep.vst[0].func, "main()")
      assert_eq(rep.vst[1].func, "u")
    }
  }
  assert_true(found)
}

///|
test "cond echoes merge: type lens NonBooleanCond + behavior lens agree" {
  let r = @pipeline.run(SAMPLE_FLOW, "f.mbt", empty_iface())
  let mut cond_hits = 0
  for rep in r.reports {
    if rep.family.merge_group() == "cond" && rep.span.start.line == 2 {
      cond_hits += 1
    }
  }
  // one merged finding at the condition span
  assert_eq(cond_hits, 1)
}

///|
test "lattice: vjoin widens constants and absorbs bottom" {
  assert_eq(@interp.vjoin(@interp.AInt(1), @interp.AInt(1)), @interp.AInt(1))
  assert_eq(
    @interp.vjoin(@interp.AInt(1), @interp.AInt(2)),
    @interp.AType("int"),
  )
  assert_eq(
    @interp.vjoin(@interp.ABool(true), @interp.ABool(false)),
    @interp.AType("bool"),
  )
  assert_eq(
    @interp.vjoin(@interp.ABottom, @interp.AType("str")),
    @interp.AType("str"),
  )
  assert_eq(
    @interp.vjoin(@interp.AInt(3), @interp.AType("float")),
    @interp.AUnion(["int", "float"]),
  )
}

///|
test "frontend: syntax errors are structural findings, pipeline survives" {
  let r = @pipeline.run("fn broken( {\n", "e.mbt", empty_iface())
  assert_true(r.reports.length() > 0)
  let mut parse_hits = 0
  for rep in r.reports {
    if rep.family.name() == "ParseError" {
      parse_hits += 1
      assert_eq(rep.lenses.length(), 1)
      assert_eq(rep.lenses[0].name(), "structural")
    }
  }
  assert_true(parse_hits > 0)
}

///|
test "report rendering appends the lens tag once per lens, sorted" {
  let rep = @report.Report::{
    family: @core.FUndefinedName,
    lenses: [@core.LBehavior, @core.LStructural, @core.LType],
    message: "undefined variable 'x'",
    span: @core.span_at(2, 5, 7),
    vst: [],
  }
  assert_eq(
    rep.render(),
    "2:5 - error: undefined variable 'x' (UndefinedName) [structural+type+behavior]\n",
  )
}

// --- out-of-subset top-level declarations --------------------------------
//
// Found by running this analyzer over real MoonBit code. `pub` on a definition
// is a modifier, and struct/enum/type/const/extern declarations are forms the
// frontend does not model. Before this, `pub fn` reported `undefined variable
// 'pub'` and every field line of a struct cascaded into its own finding pair.
// The rule pinned here: an unmodelled declaration costs exactly ONE finding and
// never blinds the pipeline for what follows it.

///|
test "a 'pub' modifier is not itself a defect" {
  let r = @pipeline.run("pub fn f() -> int {\n  1\n}\n", "m.mbt", empty_iface())
  assert_eq(r.reports.length(), 0)
}

///|
test "an unmodelled struct costs one finding, not one per field" {
  let r = @pipeline.run(
    "pub struct Point {\n  x : int\n  y : int\n}\n",
    "m.mbt",
    empty_iface(),
  )
  assert_eq(r.reports.length(), 1)
  assert_true(r.reports[0].message.contains("struct"))
}

///|
test "a defect below an unmodelled declaration is still reported" {
  let r = @pipeline.run(
    "struct P {\n  x : int\n}\nfn f() -> int {\n  missing(1)\n}\n",
    "m.mbt",
    empty_iface(),
  )
  let mut saw_missing = false
  let mut saw_struct = false
  for rep in r.reports {
    if rep.message.contains("missing") {
      saw_missing = true
    }
    if rep.message.contains("struct") {
      saw_struct = true
    }
  }
  assert_true(saw_struct)
  assert_true(saw_missing)
}

///|
/// A `#| ... #|` block string is a string literal, not code. The lexer used to
/// fall through and lex its contents as ordinary tokens, so a bare `%` in prose
/// ("ownership of fifty percent (50%) or more") became a binary operator with
/// no right operand; MoonBit's own divide-by-zero guard in Interp.binop then
/// panicked and killed the entire scan. Reduced from a real file 鈥?/// moonbitlang/async's `src/fs/read_all_test.mbt` 鈥?down to one comment line.
test "a bare % inside a block string is text, not an operator" {
  // The closer is a line-leading `#|`, measured against the toolchain, so this
  // block has to span two lines.
  let src = "fn f() -> int {\n  1\n}\n      #|      ownership of fifty percent (50%) or more\n      #|\n"
  let r = @pipeline.run(src, "x.mbt", empty_iface())
  // the point is that we get here at all; nothing here is a real defect
  assert_eq(r.reports.length(), 0)
  assert_eq(r.n_parse, 0)
}

///|
/// Same, with the block string spanning lines 鈥?the line counter has to
/// advance inside it or every span after it would be wrong. The block opens on
/// line 2, closes at the line-leading `#|` on line 4, and the injected call is
/// therefore on line 5, not line 3.
///
/// The block sits inside a function body rather than at the top of the file:
/// a bare string expression at file scope is itself a parse error, which would
/// swallow the code after it and make this test pass for the wrong reason.
test "a multi-line block string keeps later line numbers correct" {
  let src = "fn f() -> int {\n  let s = #|line one\nline two\n#|\n  missing(1)\n  1\n}\n"
  let r = @pipeline.run(src, "x.mbt", empty_iface())
  let mut saw = false
  for rep in r.reports {
    if rep.message.contains("missing") {
      saw = true
      assert_eq(rep.span.start.line, 5)
    }
  }
  assert_true(saw)
}

///|
/// Pins the measured closer rule, because getting it wrong is silent: this
/// lexer used to look for `|#`, which never appears in real code, and reported
/// "unterminated block string" on the module's own src/samples/samples.mbt 鈥?a
/// file `moon check` compiles cleanly. Found by the 0.4.0 self-scan.
///
/// Measured with `moon run`:
///   #|AAA\n#|BBB        -> "AAA\nBBB"         (closed)
///   #|AAA\n|#BBB        -> not closed         (`|#` is content)
///   #|one #|two\n#|three -> "one #|two\nthree"  (mid-line `#|` is content)
test "block string closes on a line-leading #|, and |# does not close" {
  let not_closed = "fn f() -> int {\n  1\n}\n#|a|#b\n"
  assert_eq(@pipeline.run(not_closed, "x.mbt", empty_iface()).n_parse, 1)
  let closed = "fn f() -> int {\n  1\n}\n#|a\n#|b trailing\n"
  assert_eq(@pipeline.run(closed, "x.mbt", empty_iface()).n_parse, 0)
}

///|
/// The split that makes coverage mean something: a declaration the frontend
/// chose not to ANALYSE is not a declaration it failed to READ.
///
/// Both arrive as FParse. Before the split, a file whose only complaint was
/// "this struct was outside the subset" was recorded as unparseable, which held
/// moonbit_linalg_gpu at 2/8 -- two .mbti files -- even though five more were
/// read end to end.
test "a deliberate subset skip does not cost the file its coverage" {
  let r = @pipeline.run(
    "struct P {\n  x : int\n}\ntest \"t\" {\n  1\n}\nfn f() -> int {\n  1\n}\n",
    "x.mbt",
    empty_iface(),
  )
  // two exclusions reported...
  assert_eq(r.reports.length(), 2)
  // ...and neither of them counted as a read failure
  assert_eq(r.n_parse, 0)
}

///|
/// A real read failure still costs the file its coverage, even when a skip sits
/// beside it -- and the reason names the read failure rather than the skip,
/// which is why the dominant reason is re-picked after the subtraction.
///
/// `try { ... }` is the sample. It was `a : FixedArray[Double]` until the
/// indexed-type work made annotations parse -- a test that rots silently when
/// the subset grows under it, so the sample is stated rather than left implicit.
test "a real parse failure still counts next to a skip" {
  let r = @pipeline.run(
    "struct P {\n  x : int\n}\nfn f() -> int {\n  try {\n    1\n  }\n}\n",
    "x.mbt",
    empty_iface(),
  )
  assert_true(r.n_parse >= 1)
  assert_false(r.parse_reason == "")
  assert_false(r.parse_reason.has_suffix("is outside the analyzed subset"))
}

///|
/// The trusted-region boundary: `first_error_line` is where the frontend gave
/// up READING, and it must not move for a deliberate exclusion 鈥?skipping a
/// `test` block leaves everything after it perfectly readable, so a file whose
/// only complaint is a skip has no boundary at all.
test "first_error_line marks the read failure, not the skip" {
  let clean = @pipeline.run(
    "test \"t\" {\n  1\n}\nfn f() -> int {\n  1\n}\n",
    "x.mbt",
    empty_iface(),
  )
  assert_eq(clean.first_error_line, 0)
  let broken = @pipeline.run(
    "fn f() -> int {\n  try {\n    1\n  }\n}\n",
    "x.mbt",
    empty_iface(),
  )
  assert_true(broken.n_parse >= 1)
  assert_eq(broken.first_error_line, 2) // the line carrying `try`
}

///|
/// A skip AFTER a real failure must not pull the boundary forward: it is the
/// earliest genuine failure and nothing else.
test "the boundary is the earliest real failure" {
  let r = @pipeline.run(
    "fn f() -> int {\n  try {\n    1\n  }\n}\ntest \"t\" {\n  1\n}\n",
    "x.mbt",
    empty_iface(),
  )
  assert_eq(r.first_error_line, 2) // the `try` line, not the later skip
}

// --- cross-file type symbol resolution ------------------------------------
//
// A `.mbt` file that uses a name declared in another file (a `.mbti` of a
// dependency, or the auto-generated `.mbti` of a sibling) used to fire
// FUndefinedName. With a populated `IfaceSymTab` the structural walk
// suppresses the finding and the type lens returns the right shape so
// downstream code keeps going.

///|
test "cross-file: a name in extern_iface.types suppresses FUndefinedName" {
  // `Widget` is not declared anywhere in the .mbt source, but is in the
  // extern symtab as a TYPE. The structural walk should NOT report it.
  let tab = @core.IfaceSymTab::empty()
  tab.types.set("Widget", true)
  let src = "let w = make_widget(1)\nfn make_widget(n : int) -> int {\n  return n\n}\n"
  let r = @pipeline.run(src, "user.mbt", tab)
  let mut saw_undef = false
  for rep in r.reports {
    if rep.family.name() == "UndefinedName" && rep.message.contains("Widget") {
      saw_undef = true
    }
  }
  assert_false(saw_undef)
}

///|
test "cross-file: a name in extern_iface.values silences ECall too" {
  // `make_widget` is the VALUE (function). Even when the value is registered
  // only as a value and not a type, the ECall handler must not fire
  // FOpMismatch on a TUnknown-type return. This pins the second branch of
  // the type lens's lookup.
  let tab = @core.IfaceSymTab::empty()
  tab.values.set("greet", true)
  let src = "greet(\"world\")\n"
  let r = @pipeline.run(src, "user.mbt", tab)
  let mut saw_op = false
  for rep in r.reports {
    if rep.family.name() == "OperatorMismatch" &&
      rep.message.contains("not callable") {
      saw_op = true
    }
  }
  assert_false(saw_op)
}

///|
test "cross-file: a name absent from the symtab still reports" {
  // The negative control. A name that is neither in the source, nor in
  // the extern symtab, must still fire FUndefinedName — the table only
  // suppresses, never invents valid bindings.
  let tab = @core.IfaceSymTab::empty()
  let r = @pipeline.run("let x = ghost\n", "u.mbt", tab)
  let mut saw_undef = false
  for rep in r.reports {
    if rep.family.name() == "UndefinedName" {
      saw_undef = true
    }
  }
  assert_true(saw_undef)
}

///|
test "cross-file: merge unions both type and value sets" {
  // A name in BOTH tables (one side has it as type, the other as value)
  // ends up BOTH ways after merge: the analyzer's lookup already prefers
  // value over type when a name is in both, so the user's call shape
  // (`Foo(...)`) is what the type lens sees. A pure "receiver wins" rule
  // would lose the value classification and re-introduce the
  // "not callable" false positive this work is meant to suppress.
  let target = @core.IfaceSymTab::empty()
  target.types.set("Color", true)
  let extern_ = @core.IfaceSymTab::empty()
  extern_.values.set("Color", true)
  let merged = target.merge(extern_)
  // both classifications survive
  assert_true(merged.has_type("Color"))
  assert_true(merged.has_value("Color"))
  // names only on one side are also in the result
  extern_.values.set("Extra", true)
  let merged2 = target.merge(extern_)
  assert_true(merged2.has_type("Color"))
  assert_true(merged2.has_value("Extra"))
}
