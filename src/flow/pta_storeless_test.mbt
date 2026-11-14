// 0576: the storeless heap abstraction, pinned to the deck's own programs and to
// the survey's own definitions.
//
// THE FIXTURES ARE THE DECK'S. `Pointer Analysis` (Tian Tan, Nanjing University,
// 2021) prints an answer for a small program, and this file pins the storeless
// model's answer for the SAME programs -- so the two heap abstractions can be
// read side by side on one program instead of argued about.
//
// THE EXPECTED TABLES ARE IN SHORTLEX ORDER, like `pta_text`'s, because the
// toolchain's `Compare for String` is shortlex (length first, code units as the
// tie-break): `core/builtin/string.mbt:408-428`. So `c`, `d` and `s` come out
// BEFORE `c.f`, and a reader comparing these tables with the deck's should match
// the ENTRIES and not their order.
//
// THE GRAPHHS COME FROM `cfg_of`, never from a hand-built node list, for the
// reason `pta_test.mbt` states: `cfg_of` allocates nodes BACK TO FRONT.

///|
fn ss_span(line : Int32) -> @core.Span {
  { start: @core.pos(line, 1), end: @core.pos(line, 1), }
}

///|
fn ss_name(n : String) -> @ast.Expr {
  { span: ss_span(0), kind: @ast.EName(n), }
}

///|
fn ss_struct(ty : String) -> @ast.Expr {
  { span: ss_span(0), kind: @ast.EStruct(ty, []), }
}

///|
fn ss_field(b : @ast.Expr, f : String) -> @ast.Expr {
  { span: ss_span(0), kind: @ast.EField(b, f), }
}

///|
fn ss_let(line : Int32, x : String, e : @ast.Expr) -> @ast.Stmt {
  { span: ss_span(line), kind: @ast.SLet(x, "", e), }
}

///|
fn ss_store(line : Int32, lhs : @ast.Expr, rhs : @ast.Expr) -> @ast.Stmt {
  { span: ss_span(line), kind: @ast.SAssign(lhs, rhs), }
}

///|
/// The storeless model's table for one body.
fn ss_table(g : @flow.Cfg, k : Int32) -> String {
  @flow.ss_text(@flow.ss_run([g], k).states[0])
}

///|
test "0576: an access path is a root and a field sequence, and its depth counts the indirections" {
  // The survey's own shape (p.7): "an access path consists of a pointer variable
  // which is followed by a sequence of fields of a structure".
  assert_eq(@flow.ss_depth("x"), 0)
  assert_eq(@flow.ss_depth("x.f"), 1)
  assert_eq(@flow.ss_depth("x.f.g"), 2)
  assert_eq(@flow.ss_root("x"), "x")
  assert_eq(@flow.ss_root("x.f.g"), "x")
  // And the extension is the survey's: one more field.
  let (p, cut) = @flow.ss_extend("x", "f", 2)
  assert_eq(p, "x.f")
  assert_eq(cut, false)
}

///|
test "0576: the k-limiting cuts at the bound, and the cut is the survey's self loop" {
  // The survey's predicate (p.12): "Is the heap location at most k indirections
  // from a root variable?" and its mechanism (p.9): "a self loop is created on
  // the second indirection (node corresponding to x.f.f)".
  //
  // So at k = 2 the path "x.f" extends to "x.f.f", and "x.f.f" -- already at the
  // bound -- extends to ITSELF. The second return value says the extension was
  // CUT, which is what makes the loss of information countable.
  let (p1, c1) = @flow.ss_extend("x.f", "g", 2)
  assert_eq(p1, "x.f.g")
  assert_eq(c1, false)
  let (p2, c2) = @flow.ss_extend("x.f.g", "h", 2)
  assert_eq(p2, "x.f.g")
  assert_eq(c2, true)
  // And at k = 1 the very first extension is already at the bound.
  let (p3, c3) = @flow.ss_extend("x", "f", 1)
  assert_eq(p3, "x.f")
  assert_eq(c3, false)
  let (p4, c4) = @flow.ss_extend("x.f", "g", 1)
  assert_eq(p4, "x.f")
  assert_eq(c4, true)
}

///|
test "0576: the deck's alias program, in the storeless model's vocabulary (p.28-29)" {
  // `p = new C(); q = p; x = new X(); y = new Y();` -- the deck's alias example.
  // p.29 prints two verdicts: p and q ARE aliases, x and y are NOT.
  //
  // THE TABLE IS THE MODEL'S OWN: the VALUES are access paths, so the object the
  // deck names "o1" is here the path "p" -- the ROOT that reaches it. There is no
  // allocation site in this model, because the survey classifies "allocation
  // site" as a SUMMARIZATION (p.11 section 2) and this cell is the model
  // WITHOUT it.
  let g = @flow.cfg_of([
    ss_let(1, "p", ss_struct("C")),
    ss_let(2, "q", ss_name("p")),
    ss_let(3, "x", ss_struct("X")),
    ss_let(4, "y", ss_struct("Y")),
  ])
  assert_eq(ss_table(g, 2), "p -> {p}; q -> {p}; x -> {x}; y -> {y}")
  // And the two verdicts p.29 prints, in this model's own relation.
  let pts = @flow.ss_run([g], 2).states[0]
  assert_eq(@flow.ss_alias(pts, "p", "q", 2), true)
  assert_eq(@flow.ss_alias(pts, "x", "y", 2), false)
  // And the pair that must not alias just because both are objects.
  assert_eq(@flow.ss_alias(pts, "p", "x", 2), false)
}

///|
test "0576: the deck's own program, read in the storeless domain (p.77)" {
  // p.77's program: `1 x = new A(); 2 y = x; ... 4 z = new T();` and its answer
  // `x -> {o1}, y -> {o1}, z -> {o4}`.
  let g = @flow.cfg_of([
    ss_let(1, "x", ss_struct("A")),
    ss_let(2, "y", ss_name("x")),
    ss_let(4, "z", ss_struct("T")),
  ])
  // The deck's OBJECTS become this model's PATHS: the same three relations, in
  // the other vocabulary. `y` reaches the path "x", so `y` and `x` alias.
  assert_eq(ss_table(g, 2), "x -> {x}; y -> {x}; z -> {z}")
  let pts = @flow.ss_run([g], 2).states[0]
  assert_eq(@flow.ss_alias(pts, "x", "y", 2), true)
  assert_eq(@flow.ss_alias(pts, "x", "z", 2), false)
}

///|
test "0576: a field pointer is named by its PATH, and the store rule extends it" {
  // `c = new C(); d = new D(); c.f = d; s = c.f;` -- the four rules, with the
  // store going THROUGH a field.
  //
  // THE FIELD POINTER IS NAMED BY THE PATH ("c.f"), not by an object ("o1.f" in
  // the allocation-site model), because the survey's model does not explicate the
  // objects (p.7): "The storeless model does not explicate the memory locations
  // or objects corresponding to these access paths."
  let g = @flow.cfg_of([
    ss_let(1, "c", ss_struct("C")),
    ss_let(2, "d", ss_struct("D")),
    ss_store(3, ss_field(ss_name("c"), "f"), ss_name("d")),
    ss_let(4, "s", ss_field(ss_name("c"), "f")),
  ])
  assert_eq(ss_table(g, 2), "c -> {c}; d -> {d}; s -> {d}; c.f -> {d}")
  let pts = @flow.ss_run([g], 2).states[0]
  // `s` holds what `c.f` holds, so `s` and `d` alias ...
  assert_eq(@flow.ss_alias(pts, "s", "d", 2), true)
  // ... and `c` does not alias `s`: `c` reaches the path "c" and `s` reaches "d".
  assert_eq(@flow.ss_alias(pts, "c", "s", 2), false)
}

///|
test "0576: the two heap abstractions answer the alias question the same way here" {
  // THE SAME PROGRAM, READ BY BOTH MODELS. The allocation-site model names a
  // location by its SITE ("o1"); the storeless model names it by its ROOT ("x").
  // The alias question is the same question, so the two answers are compared --
  // and the comparison is COUNTED, not asserted.
  let g = @flow.cfg_of([
    ss_let(1, "c", ss_struct("C")),
    ss_let(2, "d", ss_struct("D")),
    ss_store(3, ss_field(ss_name("c"), "f"), ss_name("d")),
    ss_let(4, "s", ss_field(ss_name("c"), "f")),
  ])
  let sb = @flow.pta_run([g])[0]
  let ss = @flow.ss_run([g], 2).states[0]
  let names = ["c", "d", "s"]
  let (same, differ) = @flow.ss_agree(ss, sb, names, 2)
  // Three variables, three pairs, and the two models agree on all three.
  assert_eq(same, 3)
  assert_eq(differ, 0)
}

///|
test "0576: the two models DIFFER in what a variable may reach, and that difference is measured" {
  // `x = new C(); x = new D(); y = x;` -- ONE variable, TWO allocations.
  //
  // THE ALLOCATION-SITE MODEL HAS TWO OBJECTS for it ("o1" and "o2"), because the
  // two allocations are at two SITES. THE STORELESS MODEL HAS ONE PATH, because
  // the location is named by the ROOT that reaches it and both allocations are
  // reached by "x". So the two models disagree about the SIZE of the answer
  // while agreeing about the alias verdicts, and the disagreement is a fact
  // about the two heap abstractions rather than about either implementation.
  let g = @flow.cfg_of([
    ss_let(1, "x", ss_struct("C")),
    ss_let(2, "x", ss_struct("D")),
    ss_let(3, "y", ss_name("x")),
  ])
  let sb = @flow.pta_run([g])[0]
  let ss = @flow.ss_run([g], 2).states[0]
  // The allocation-site model: two objects.
  assert_eq(@flow.pta_text(sb), "x -> {o1,o2}; y -> {o1,o2}")
  // The storeless model: one path.
  assert_eq(@flow.ss_text(ss), "x -> {x}; y -> {x}")
  // And the alias verdicts still agree.
  let (same, differ) = @flow.ss_agree(ss, sb, ["x", "y"], 2)
  assert_eq(same, 1)
  assert_eq(differ, 0)
}

///|
test "0576: the summarization's cut is COUNTED, and it is visible as a lost write" {
  // AT k = 0 EVERY FIELD WRITE IS AT THE BOUND, so the summarization cuts every
  // extension of a path. The cut is not hidden: the count is in the result, and
  // the write lands on the BOUND's path instead of on the extension.
  let g = @flow.cfg_of([
    ss_let(1, "c", ss_struct("C")),
    ss_let(2, "d", ss_struct("D")),
    ss_store(3, ss_field(ss_name("c"), "f"), ss_name("d")),
  ])
  let loose = @flow.ss_run([g], 2)
  // At k = 2 nothing is cut: the only extension is one deep.
  assert_eq(loose.cuts, 0)
  assert_eq(@flow.ss_text(loose.states[0]), "c -> {c}; d -> {d}; c.f -> {d}")
  // At k = 0 the extension is at the bound, so it is cut -- and the cut is
  // COUNTED rather than dropped silently.
  //
  // THE COUNT IS TWO, AND THE SECOND ONE IS THE ALIAS. The write lands on the
  // bound's path, so "c" ends up holding "d" -- and once it does, the next
  // sweep's store through "c" is ALSO a store through "d", and THAT extension
  // is cut as well. Two distinct cut SITES, not two sweeps of one site: the
  // count is a set of sites because a fixed point applies the rules until
  // nothing changes, and a counter would have reported the sweep count.
  let tight = @flow.ss_run([g], 0)
  assert_eq(tight.cuts, 2)
  assert_eq(@flow.ss_text(tight.states[0]), "c -> {c,d}; d -> {d}")
}

///|
test "0576: the summarization merges a deeper path into the bound, and that is the survey's spurious alias" {
  // The survey's own example (p.9): "This stores spurious aliases for access
  // paths with more than k = 2 indirections (for example, x.f.f.f and y are
  // spuriously marked as aliases at Out6)."
  //
  // THE MECHANISM IS THE PREDICATE, and it is tested directly: a path DEEPER
  // than the bound is merged into the location at the bound, so "c.f.f.f" may
  // denote the same location as "c.f.f". That merge is where the spurious alias
  // comes from, and it is the survey's own -- "a self loop is created on the
  // second indirection" (p.9), and the second indirection is the bound for
  // k = 2.
  assert_eq(@flow.ss_same("c.f.f", "c.f.f.f", 2), true)
  // Equal paths are the same location, and a path that is not below the other is
  // not merged into it.
  assert_eq(@flow.ss_same("c.f.f", "c.f.f", 2), true)
  assert_eq(@flow.ss_same("c.f", "c.g", 2), false)
  // AND TWO PATHS THAT ARE BOTH WITHIN THE BOUND ARE DISTINCT LOCATIONS: the
  // bound is "x.f.f" for k = 2, and "c.f.f" is that node, so "c.f" and "c.f.f"
  // are two places and not one.
  assert_eq(@flow.ss_same("c.f", "c.f.f", 2), false)
  // And the BOUND is what does the merging: at k = 3 the same pair is NOT
  // merged, because "c.f.f.f" is then within the bound.
  assert_eq(@flow.ss_same("c.f.f", "c.f.f.f", 3), false)
}

///|
test "0576: in THIS rule system no pointer ever REACHES a deep path, and that is measured" {
  // THE SPURIOUS ALIAS NEEDS A POINTER THAT REACHES A DEEP PATH, and this rule
  // system never produces one. The reason is a fact about the rules: a value is
  // always the ROOT of the location it names -- the New rule names the fresh
  // location by the path rooted at the variable -- so the only paths deeper than
  // a root are the FIELD-POINTER NAMES, and a name is not a value.
  //
  // SO THE MEASUREMENT IS NEGATIVE AND IT IS PINNED, because a boundary that is
  // not stated is a boundary nobody can check: the pointer "c.f" reaches the
  // path "d", and "d" is not below "c.f", so the summarization does not merge
  // them and the survey's spurious alias does not arise HERE.
  let g = @flow.cfg_of([
    ss_let(1, "c", ss_struct("C")),
    ss_let(2, "d", ss_struct("D")),
    ss_store(3, ss_field(ss_name("c"), "f"), ss_name("d")),
  ])
  let pts = @flow.ss_run([g], 2).states[0]
  // The pointer "c.f" REACHES "d" -- and "d" is not below "c.f".
  assert_eq(@flow.ss_alias_at(pts, "c.f", "c.f.f", 2), false)
  assert_eq(@flow.ss_alias_at(pts, "c.f", "c.f", 2), false)
  // And the values really are roots: the deepest VALUE is at depth 0, while the
  // deepest path the relation holds at all is the field pointer's name, one deep.
  assert_eq(@flow.ss_value_deepest(pts), 0)
  assert_eq(@flow.ss_deepest(pts), 1)
}
