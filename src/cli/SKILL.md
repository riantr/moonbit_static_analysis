---
name: moonbit-static-analysis
description: >-
  Demonstrate the moonbit_static_analysis three-inspection pipeline
  (structural / type / behavior) over embedded MoonBit-subset samples and a
  sample state-machine audit with the published CLI. Use to showcase or
  smoke-check the analyzer's findings format (line:col findings with family,
  lens tags, and virtual stacks). Do not use it to analyze user-supplied
  source or machine tables — import the module instead and call
  @pipeline.run / @statecheck.audit.
---

# The three-inspection pipeline demo

`riantr/moonbit_static_analysis` is a three-inspection static-analysis pipeline
(structural walk → type/symbol inference → abstract interpretation → merged
report) for MoonBit-subset programs and for state-machine tables
(`@statecheck.MachineSpec`). The CLI is the demo entry: it runs the pipeline
over six embedded samples and audits a pyroduct-shaped sample machine.

## Launch

Use the published executable through `moonx` from any directory:

```sh
moonx riantr/moonbit_static_analysis/src/cli
```

From a local checkout of the module directory, run the same demo with:

```sh
moon run src/cli
```

The CLI takes no arguments; the samples are embedded (`src/samples`). Pin a
verified published version with `@VERSION` when reproducibility matters.

## Reading the output

Each finding is one line with position, severity, message, family, and the
union of lenses that saw it; multi-lens findings carry a virtual stack
(entry frame first, error point last):

```
2:10 - error: undefined variable 'missing' (UndefinedName) [structural+type+behavior]
  in main() at undefined.mbtx:4
  in g at undefined.mbtx:1
Summary: 1 finding(s) (before merge: structural 1, type 2, behavior 1)
```

The machine-audit section prints the same shape over machine tables:

```
182:12 - warning: state '失忆' is never entered: it appears only as a transition source (UnusedLocal) [structural]
Machine '主体' summary: 4 finding(s)
```

## Analyze real source or a real machine (import, not the CLI)

The demo CLI cannot analyze user input. Depend on the module and call the API:

```moonbit
// program revision: source is a String in the MoonBit subset
let result : @pipeline.PipelineResult = @pipeline.run(source, "main.mbtx")
println(@pipeline.render_result(result))

// machine-table audit: plain data, any state machine
let spec : @statecheck.MachineSpec = {
  name: "主体",
  states: ["站立", "宁静"],
  initial: "站立",
  terminal: "宁静",
  transitions: [("站立", "抵达", "宁静")],
  trigger_slots: [("抵达", "处境")],
  slot_names: ["处境"],
  blocks: [],
  course: ["站立", "宁静"],
}
println(@statecheck.render(spec))
```

## Scope

The CLI exposes no flags, no file input, and no JSON output. It does not
replace a linter integration: for CI use `moon check` plus the module's tests;
for machine-table audits use `@statecheck.audit` directly. Consult the adjacent
[README.md](../../README.md) for the full architecture and the formal
verification story.
