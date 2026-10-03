// statecheck: static state revision for multi-layer state machines.
//
// The machine tables come in as PLAIN DATA (a MachineSpec) — this package
// has no dependency on any particular machine library. riantr/pyroduct is
// the reference consumer: its `audit` package builds a MachineSpec from its
// real subject machine and calls into this API, so pyroduct's own test
// suite runs the three-lens treatment over its own tables.
//
// The three lenses read a machine exactly like they read a program:
//   lens 1 (structural): states are BINDINGS — every state must be bound
//                        by at least one transition, entered at least once,
//                        reachable from the initial position; the terminal
//                        must be reachable (赋值即绑定 → 状态即绑定)
//   lens 2 (type):       the drive-slot contract as types — triggers are
//                        placed into slots; an unplaced slot or a silent
//                        Block is a contract violation
//                        (注解即契约; 无路必须说出口)
//   lens 3 (behavior):   the course (修习历程) is abstractly EXECUTED —
//                        every consecutive step must be carried by some
//                        transition; broken steps carry a virtual stack
//                        (抽象解释 + 虚栈)
//
// Findings merge through the same merge_group contract as program defects
// (assembly point 4 applies to machines too).

///|
/// A state machine as plain data. pyroduct builds this from its real
/// tables; tests embed faithful excerpts.
pub(all) struct MachineSpec {
  /// machine name (主体 / 群体 / …)
  name : String
  /// the positions (位置全集)
  states : Array[String]
  /// the initial position
  initial : String
  /// the terminal position (宁静); "" = the machine has no terminal
  terminal : String
  /// (from, trigger, to)
  transitions : Array[(String, String, String)]
  /// (trigger, slot) — the drive-slot placement (注解即契约)
  trigger_slots : Array[(String, String)]
  /// the expected slot set; empty = skip the empty-slot check
  slot_names : Array[String]
  /// Block results from the step contract: (state, slot, reason);
  /// reason "" = a silent 无路 (defect)
  blocks : Array[(String, String, String)]
  /// the canonical course (修习历程): positions the machine claims to walk
  course : Array[String]
}

///|
/// Run the three lenses over a machine spec.
pub fn audit(spec : MachineSpec) -> Array[@report.Report] {
  let all : Array[@report.Report] = []
  let declared : Map[String, Bool] = Map([])
  for s in spec.states {
    declared.set(s, true)
  }
  // ---- lens 1: structural binding accounting (状态即绑定)
  for tr in spec.transitions {
    let (from, trigger, to) = tr
    for pair in [(from, "from"), (to, "to")] {
      let (endpoint, which) = pair
      if !declared.get(endpoint).unwrap_or(false) {
        all.push(@report.Report::{
          family: @core.FUndefinedName,
          lenses: [@core.LStructural],
          message: "transition \{which} '\{trigger}' references undeclared state '\{endpoint}'",
          span: state_span(endpoint),
          vst: [],
        })
      }
    }
    let mut trigger_declared = false
    for pair in spec.trigger_slots {
      if pair.0 == trigger {
        trigger_declared = true
      }
    }
    if !trigger_declared {
      all.push(@report.Report::{
        family: @core.FUndefinedName,
        lenses: [@core.LStructural],
        message: "transition uses undeclared trigger '\{trigger}'",
        span: state_span(from),
        vst: [],
      })
    }
  }
  let bound : Map[String, Bool] = Map([])
  let entered : Map[String, Bool] = Map([])
  for s in spec.states {
    bound.set(s, false)
    entered.set(s, false)
  }
  for tr in spec.transitions {
    let (from, _, to) = tr
    bound.set(from, true)
    bound.set(to, true)
    entered.set(to, true)
  }
  for s in spec.states {
    if !bound.get(s).unwrap_or(false) {
      all.push(@report.Report::{
        family: @core.FUndefinedName,
        lenses: [@core.LStructural],
        message: "state '\{s}' is bound nowhere: no transition mentions it",
        span: state_span(s),
        vst: [],
      })
    } else if !entered.get(s).unwrap_or(false) &&
      s != spec.terminal &&
      s != spec.initial {
      all.push(@report.Report::{
        family: @core.FUnusedLocal,
        lenses: [@core.LStructural],
        message: "state '\{s}' is never entered: it appears only as a transition source",
        span: state_span(s),
        vst: [],
      })
    }
  }
  // reachability closure from the initial position (fixpoint)
  let reach : Map[String, Bool] = Map([])
  reach.set(spec.initial, true)
  let mut grew = true
  while grew {
    grew = false
    for tr in spec.transitions {
      let (from, _, to) = tr
      if reach.get(from).unwrap_or(false) && !reach.get(to).unwrap_or(false) {
        reach.set(to, true)
        grew = true
      }
    }
  }
  for s in spec.states {
    if !reach.get(s).unwrap_or(false) {
      all.push(@report.Report::{
        family: @core.FUnreachable,
        lenses: [@core.LStructural],
        message: "state '\{s}' is unreachable from the initial position '\{spec.initial}'",
        span: state_span(s),
        vst: [],
      })
    }
  }
  if spec.terminal != "" && !reach.get(spec.terminal).unwrap_or(false) {
    all.push(@report.Report::{
      family: @core.FMethodError,
      lenses: [@core.LStructural],
      message: "terminal position '\{spec.terminal}' is unreachable — the machine cannot finish",
      span: state_span(spec.terminal),
      vst: [],
    })
  }
  // ---- lens 2: the drive-slot contract (注解即契约)
  // determinism: one (state, trigger) pair must resolve to ONE destination —
  // two different `to`s for the same drive and the contract cannot decide
  // where the machine goes.
  let first_to : Map[String, String] = Map([])
  let amb_reported : Map[String, Bool] = Map([])
  for tr in spec.transitions {
    let (from, trigger, to) = tr
    let key = "\{from}\n\{trigger}"
    match first_to.get(key) {
      Some(prev) =>
        if prev != to && !amb_reported.get(key).unwrap_or(false) {
          amb_reported.set(key, true)
          all.push(@report.Report::{
            family: @core.FArgType,
            lenses: [@core.LType],
            message: "trigger '\{trigger}' at state '\{from}' resolves to multiple destinations ('\{prev}' vs '\{to}') — ambiguous drive",
            span: state_span(from),
            vst: [],
          })
        }
      None => first_to.set(key, to)
    }
  }
  if spec.slot_names.length() > 0 {
    let placed : Map[String, Bool] = Map([])
    for pair in spec.trigger_slots {
      let (_, slot) = pair
      placed.set(slot, true)
      let mut known = false
      for s in spec.slot_names {
        if s == slot {
          known = true
        }
      }
      if !known {
        all.push(@report.Report::{
          family: @core.FArgType,
          lenses: [@core.LType],
          message: "trigger placed in unknown drive slot '\{slot}'",
          span: @core.zero_span(),
          vst: [],
        })
      }
    }
    for slot in spec.slot_names {
      if !placed.get(slot).unwrap_or(false) {
        all.push(@report.Report::{
          family: @core.FArgType,
          lenses: [@core.LType],
          message: "drive slot '\{slot}' has no trigger placed in it",
          span: @core.zero_span(),
          vst: [],
        })
      }
    }
  }
  for b in spec.blocks {
    let (state, slot, reason) = b
    if reason.is_empty() {
      all.push(@report.Report::{
        family: @core.FCondBool,
        lenses: [@core.LType],
        message: "step(\{state}, \{slot}) blocks without a reason",
        span: state_span(state),
        vst: [],
      })
    }
  }
  // ---- lens 3: the course as abstract execution (轨迹虚栈)
  let mut i = 0
  while i < spec.course.length() {
    if !declared.get(spec.course[i]).unwrap_or(false) {
      all.push(@report.Report::{
        family: @core.FUndefinedName,
        lenses: [@core.LBehavior],
        message: "course references undeclared state '\{spec.course[i]}'",
        span: state_span(spec.course[i]),
        vst: [{ func: "course", file: spec.name, line: i + 1, }],
      })
    }
    i += 1
  }
  i = 0
  while i < spec.course.length() - 1 {
    let here = spec.course[i]
    let next = spec.course[i + 1]
    let mut connected = false
    for tr in spec.transitions {
      let (from, _, to) = tr
      if from == here && to == next {
        connected = true
      }
    }
    if !connected {
      all.push(@report.Report::{
        family: @core.FMethodError,
        lenses: [@core.LBehavior],
        message: "course step \{i + 1}: '\{here}' → '\{next}' has no trigger to carry it",
        span: state_span(next),
        vst: [
          { func: "course", file: spec.name, line: i + 1, },
          { func: here, file: spec.name, line: i + 2, },
        ],
      })
    }
    i += 1
  }
  all
}

///|
/// Stable pseudo-span for a state name (deterministic per name).
fn state_span(name : String) -> @core.Span {
  let mut h = 0
  for c in name {
    h = h * 31 + c.to_int()
  }
  let line = 1 + (h & 1023)
  let col = 1 + ((h >> 10) & 63)
  @core.span_at(line, col, name.length())
}

///|
/// Merged rendering: same merge semantics as the program pipeline
/// (assembly point 4 applies to machine defects too).
pub fn render(spec : MachineSpec) -> String {
  let findings = audit(spec)
  let merged = @pipeline.merge_findings(findings)
  let buf = StringBuilder()
  if merged.length() == 0 {
    buf.write_string("No machine defects found, finished checking\n")
  } else {
    for rep in merged {
      buf.write_string(rep.render())
    }
  }
  buf.write_string(
    "Machine '\{spec.name}' summary: \{merged.length()} finding(s)\n",
  )
  buf.to_string()
}

///|
/// A pyroduct-flavored demo machine: a faithful miniature of the real
/// subject machine's audit shape — 失忆/浑噩 are sources-only and
/// unreachable, exactly as the real audit finds them.
pub fn pyroduct_flavored() -> MachineSpec {
  {
    name: "主体",
    states: [
      "站立", "自由", "相遇", "秘密", "痛苦", "宁静", "失忆", "浑噩",
    ],
    initial: "站立",
    terminal: "宁静",
    transitions: [
      ("站立", "表明立场", "自由"),
      ("自由", "相遇他者", "相遇"),
      ("相遇", "怀疑", "秘密"),
      ("秘密", "召回", "痛苦"),
      ("痛苦", "痛感有限", "宁静"),
      ("失忆", "切断过去", "痛苦"),
      ("浑噩", "召唤偶像", "痛苦"),
    ],
    trigger_slots: [
      ("表明立场", "行动"),
      ("相遇他者", "共在"),
      ("怀疑", "揭蔽"),
      ("召回", "反馈"),
      ("痛感有限", "处境"),
      ("切断过去", "取向"),
      ("召唤偶像", "先行"),
    ],
    slot_names: [
      "处境", "取向", "行动", "反馈", "共在", "揭蔽", "先行",
    ],
    blocks: [
      ("宁静", "行动", "终点无路"),
      ("失忆", "共在", "他者已被切断"),
    ],
    course: ["站立", "自由", "相遇", "秘密", "痛苦", "宁静"],
  }
}
