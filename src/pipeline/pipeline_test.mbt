// test: the complementary semantics. Each test pins one way the three
// lenses depend on or complement each other:
//   merge:      the same defect reported by several lenses collapses into
//               one finding whose lens tag is the union
//   tables:     lens 2 consumes lens 1's binding tables; lens 3 consumes
//               lens 2's signatures (no stage rediscovers bindings)
//   pruning:    constant folding appears twice — structural
//               (walk) and lattice (ABool in interp)
//   traces:     behavioral findings carry virtual stacks (entry first)

/// test inputs (mirror src/samples; inlined to keep the import graph simple)

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
  let r = @pipeline.run(SAMPLE_CLEAN, "clean.mlang")
  assert_eq(r.reports.length(), 0)
  assert_eq(r.sigs.length(), 1)
  assert_eq(r.sigs[0], "fact(int) -> int")
}

///|
test "merge: one defect, three lenses, ONE finding" {
  let r = @pipeline.run(SAMPLE_UNDEFINED, "u.mlang")
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
    "2:10 - error: undefined variable 'missing' (UndefinedName) [structural+type+behavior]\n  in main() at u.mlang:4\n  in g at u.mlang:1\n",
  )
}

///|
test "merge: arg-type echoes unify under MethodError" {
  // `shout(42)` is an argument-type error AND a method error at
  // the same span; the pipeline emits one behavioral-phrased finding
  let r = @pipeline.run(SAMPLE_TYPING, "t.mlang")
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
  // lens never re-parses — re-assigning a str to n reports AssignType with
  // the ANNOTATION'S type, taken from lens 1's table
  let src = "z = 1\nlet n: int = 2\nn = \"x\"\nz = \"y\"\n"
  let r = @pipeline.run(src, "a1.mlang")
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
  // f accepts int only; only the behavior lens can reject f(true) —
  // dispatch against the signature table lens 2 produced
  let src = "fn f(x: int) -> int {\n  return x\n}\nf(true)\n"
  let r = @pipeline.run(src, "a2.mlang")
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
  // the lattice — typo_fn exists NOWHERE, yet no lens reports it
  let r = @pipeline.run(SAMPLE_DEADBRANCH, "d.mlang")
  assert_eq(r.reports.length(), 0)
  assert_eq(r.sigs[0], "h(int) -> int")
}

///|
test "structural-only: unused param/local/changed param invisible to others" {
  let r = @pipeline.run(SAMPLE_STRUCTURE, "s.mlang")
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
  let r = @pipeline.run(src, "v.mlang")
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
  let r = @pipeline.run(SAMPLE_FLOW, "f.mlang")
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
  let r = @pipeline.run("fn broken( {\n", "e.mlang")
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
