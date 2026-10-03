// tests: the static state-revision lens. Each test pins one way the three
// lenses read machine tables like they read programs.

///|
test "clean machine has no findings" {
  let spec : @statecheck.MachineSpec = {
    name: "demo",
    states: ["a", "b", "c"],
    initial: "a",
    terminal: "c",
    transitions: [("a", "go", "b"), ("b", "stop", "c")],
    trigger_slots: [("go", "act"), ("stop", "rest")],
    slot_names: ["act", "rest"],
    blocks: [("c", "act", "terminal has no road")],
    course: ["a", "b", "c"],
  }
  assert_eq(@statecheck.audit(spec).length(), 0)
  assert_true(@statecheck.render(spec).contains("No machine defects found"))
}

///|
test "pyroduct-shaped machine: sources-only states produce the real audit shape" {
  // 失忆/浑噩 appear only as transition sources — each produces BOTH a
  // never-entered finding and an unreachable finding, all structural
  let spec = @statecheck.pyroduct_flavored()
  let findings = @statecheck.audit(spec)
  let mut never = 0
  let mut unreach = 0
  let mut other = 0
  for rep in findings {
    match rep.family {
      @core.FUnusedLocal => never += 1
      @core.FUnreachable => unreach += 1
      _ => other += 1
    }
  }
  assert_eq(never, 2)
  assert_eq(unreach, 2)
  assert_eq(other, 0)
  for rep in findings {
    assert_eq(rep.lenses.length(), 1)
    assert_eq(rep.lenses[0].name(), "structural")
  }
}

///|
test "merged rendering carries the machine's own vocabulary" {
  let text = @statecheck.render(@statecheck.pyroduct_flavored())
  assert_true(text.contains("Machine '主体' summary: 4 finding(s)"))
  assert_true(text.contains("失忆"))
  assert_true(text.contains("浑噩"))
  assert_true(text.contains("站立"))
  assert_true(text.contains("[structural]"))
}

///|
test "lens 1: dangling transition endpoints and undeclared triggers" {
  let spec : @statecheck.MachineSpec = {
    name: "broken",
    states: ["a", "b"],
    initial: "a",
    terminal: "",
    transitions: [("a", "go", "ghost"), ("a", "vanish", "b")],
    trigger_slots: [("go", "act")],
    slot_names: [],
    blocks: [],
    course: [],
  }
  let findings = @statecheck.audit(spec)
  let mut dangling = 0
  let mut undeclared_trigger = 0
  for rep in findings {
    if rep.message.contains("references undeclared state 'ghost'") {
      dangling += 1
    }
    if rep.message.contains("undeclared trigger 'vanish'") {
      undeclared_trigger += 1
    }
  }
  assert_eq(dangling, 1)
  assert_eq(undeclared_trigger, 1)
}

///|
test "lens 2: empty slot and silent 无路 are contract violations" {
  let spec : @statecheck.MachineSpec = {
    name: "contract",
    states: ["a", "b", "c"],
    initial: "a",
    terminal: "c",
    transitions: [("a", "go", "b"), ("b", "stop", "c")],
    trigger_slots: [("go", "act"), ("stop", "rest"), ("flee", "elsewhere")],
    slot_names: ["act", "rest", "hold"],
    blocks: [("b", "act", "")],
    course: ["a", "b", "c"],
  }
  let findings = @statecheck.audit(spec)
  let mut empty_slot = 0
  let mut unknown_slot = 0
  let mut silent = 0
  for rep in findings {
    if rep.message == "drive slot 'hold' has no trigger placed in it" {
      empty_slot += 1
      assert_eq(rep.lenses[0].name(), "type")
    }
    if rep.message.contains("unknown drive slot 'elsewhere'") {
      unknown_slot += 1
    }
    if rep.message == "step(b, act) blocks without a reason" {
      silent += 1
      assert_eq(rep.lenses[0].name(), "type")
    }
  }
  assert_eq(empty_slot, 1)
  assert_eq(unknown_slot, 1)
  assert_eq(silent, 1)
}

///|
test "lens 3: broken course steps carry a virtual stack" {
  // 站立 → 相遇 has no direct transition; the course step is stranded
  let spec : @statecheck.MachineSpec = {
    name: "主体",
    states: ["站立", "自由", "相遇", "宁静"],
    initial: "站立",
    terminal: "宁静",
    transitions: [
      ("站立", "表明立场", "自由"),
      ("自由", "相遇他者", "相遇"),
      ("相遇", "抵达", "宁静"),
    ],
    trigger_slots: [
      ("表明立场", "行动"),
      ("相遇他者", "共在"),
      ("抵达", "处境"),
    ],
    slot_names: [],
    blocks: [],
    course: ["站立", "相遇", "宁静", "幽灵"],
  }
  let findings = @statecheck.audit(spec)
  let mut broken = 0
  let mut undeclared_course = 0
  for rep in findings {
    if rep.message.contains("has no trigger to carry it") {
      broken += 1
      assert_eq(rep.lenses.length(), 1)
      assert_eq(rep.lenses[0].name(), "behavior")
      // virtual stack: entry frame first, error point last
      assert_eq(rep.vst.length(), 2)
      assert_eq(rep.vst[0].func, "course")
    }
    if rep.message.contains("course references undeclared state '幽灵'") {
      undeclared_course += 1
      assert_eq(rep.vst.length(), 1)
    }
  }
  // two stranded steps: 站立→相遇 has no transition, and 宁静→幽灵 has
  // neither a transition nor a declared target
  assert_eq(broken, 2)
  assert_eq(undeclared_course, 1)
}

///|
test "lens 1: unreachable terminal means the machine cannot finish" {
  let spec : @statecheck.MachineSpec = {
    name: "stuck",
    states: ["a", "b", "end"],
    initial: "a",
    terminal: "end",
    transitions: [("a", "loop", "b"), ("b", "loop2", "a")],
    trigger_slots: [("loop", "act"), ("loop2", "act")],
    slot_names: [],
    blocks: [],
    course: [],
  }
  let findings = @statecheck.audit(spec)
  let mut cannot_finish = 0
  for rep in findings {
    if rep.message.contains("the machine cannot finish") {
      cannot_finish += 1
      assert_eq(rep.lenses[0].name(), "structural")
    }
  }
  assert_eq(cannot_finish, 1)
}

///|
test "lens 2: one (state, trigger) with two destinations is ambiguous" {
  // 同位同触发多去向：a --go--> b 与 a --go--> c 并存，驱动契约无法
  // 决定去向 —— 恰好一条 FArgType 报告（去重后只报一次）
  let spec : @statecheck.MachineSpec = {
    name: "fork",
    states: ["a", "b", "c"],
    initial: "a",
    terminal: "c",
    transitions: [("a", "go", "b"), ("a", "go", "c"), ("a", "go", "c")],
    trigger_slots: [("go", "act")],
    slot_names: [],
    blocks: [],
    course: [],
  }
  let findings = @statecheck.audit(spec)
  let mut ambiguous = 0
  for rep in findings {
    if rep.message.contains("resolves to multiple destinations ('b' vs 'c')") {
      ambiguous += 1
      assert_true(
        match rep.family {
          @core.FArgType => true
          _ => false
        },
      )
      assert_eq(rep.lenses.length(), 1)
      assert_eq(rep.lenses[0].name(), "type")
    }
  }
  assert_eq(ambiguous, 1)
}

///|
test "clean machine stays clean with the determinism check" {
  let spec : @statecheck.MachineSpec = {
    name: "demo2",
    states: ["a", "b", "c"],
    initial: "a",
    terminal: "c",
    transitions: [("a", "go", "b"), ("a", "wake", "c"), ("b", "stop", "c")],
    trigger_slots: [("go", "act"), ("wake", "act"), ("stop", "rest")],
    slot_names: [],
    blocks: [],
    course: [],
  }
  assert_eq(@statecheck.audit(spec).length(), 0)
}
