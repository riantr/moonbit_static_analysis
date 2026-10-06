---
name: moonbit-static-analysis
description: >-
  Demonstrate the moonbit_static_analysis three-inspection pipeline
  (structural / type / behavior) over embedded MoonBit-subset samples and a
  sample state-machine audit with the published CLI. Use to showcase or
  smoke-check the analyzer's findings format (line:col findings with family,
  lens tags, and virtual stacks). This entry takes no input. To ANALYSE a real
  project use the scanner skill (moonx riantr/moonbit_static_analysis@latest
  <target>), or import the module and call @pipeline.run / @moonfiles.* /
  @statecheck.audit.
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

The demo now covers every file kind the module analyzes, not just `.mbt`:
`.mbt` samples, a `.mbtx` script (its import block is echoed under
`Imports (.mbtx script, recorded not resolved):`), a `.mbt.md` document, a
`.mbti` interface and a `.mbtp` proof file. See
[EXTENSIONS.md](../../EXTENSIONS.md) for the full taxonomy and for which
fences inside a `.mbt.md` count as code.

## Reading the output

Each finding is one line with position, severity, message, family, and the
union of lenses that saw it; multi-lens findings carry a virtual stack
(entry frame first, error point last):

```
2:10 - error: undefined variable 'missing' (UndefinedName) [structural+type+behavior]
  in main() at undefined.mbt:4
  in g at undefined.mbt:1
Summary: 1 finding(s) (before merge: structural 1, type 2, behavior 1)
```

The machine-audit section prints the same shape over machine tables — but its
`line:col` is **not** a source position. A `MachineSpec` is a plain-data table
with no file behind it, so `state_span()` derives a stable pseudo-span from the
state name (`h = h*31 + c`, `line = 1 + (h & 1023)`, `col = 1 + ((h>>10) & 63)`).
The same name always prints the same coordinate, and that coordinate points at
nothing on disk — don't go looking for it in the audited project's sources.

```
182:12 - warning: state '失忆' is never entered: it appears only as a transition source (UnusedLocal) [structural]
Machine '主体' summary: 4 finding(s)
```

## Analyze real source or a real machine

Two routes, depending on whether the target may take a dependency.

**Scan a project as-is** — nothing to add to it, nothing written into it:

```sh
moonx riantr/moonbit_static_analysis@latest riantr/moonbit_doubleML@latest
```

The target is a registry coordinate or a filesystem path; omit it for the
current directory. Sources are only read. This is the right default for
"analyse this other repository".

**Depend on the module** when you want structured output, or are analysing the
analyzer's own repository:

```moonbit
// program revision: source is a String in the MoonBit subset
let result : @pipeline.PipelineResult = @pipeline.run(source, "main.mbt")
println(@pipeline.render_result(result))

// the other file kinds have their own frontends (src/moonfiles)
let doc  = @moonfiles.literate(md_text, "README.mbt.md")   // .mbt.md, real line numbers
let iface = @moonfiles.iface(mbti_text, "pkg.mbti")       // interface audit
let proof = @moonfiles.proof(mbtp_text, "core.mbtp")      // proof lint
println(@moonfiles.render_reports(iface))

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

The CLI takes **no arguments**: the samples are embedded (`src/samples`), so it
can only show the findings format. To analyse anything else use one of the two
routes above.

> The `moon runwasm …` command shown on this skill's page is **deprecated** (the
> toolchain says removal after 2026-09-14) but still works. Prefer `moonx`, which
> is the recommended invocation above.
>
> The "Download wasm" button on this skill's page is **usable**. It serves the
> same prebuilt artifact `moonx` downloads and caches — nothing to compile. (If a
> tool reports that URL as 404, that check used an HTTP `HEAD`; `download.mooncakes.io`
> answers 404 to `HEAD` even for artifacts that exist. Re-check with `GET`.)

It does not replace a linter integration: for CI use `moon check` plus the
module's tests. Consult the adjacent
[README.md](../../README.md) for the full architecture and
[EXTENSIONS.md](../../EXTENSIONS.md) for the file-kind taxonomy and the formal
verification story.
