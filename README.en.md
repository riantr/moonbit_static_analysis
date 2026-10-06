# moonbit_static_analysis

[中文](README.md) | **English**

`riantr/moonbit_static_analysis` — **a three-inspection (structural / type / behavior) static-analysis pipeline: one infrastructure, two uses**:

1. **Program-code revision**: analyze programs in the **fast-evolving MoonBit language** (undefined names, unused bindings, type mismatches, dead branches, unreachable code);
2. **Static state revision**: a generic machine-table audit for multi-layer state machines (`src/statecheck`) — **the audited subject calls this module**, feeding its machine tables in as plain data. The reference consumer is [riantr/pyroduct](https://mooncakes.io/docs/riantr/pyroduct@0.1.28) (a subject / group / society / evolution state-machine family); its `audit` package drives this module black-box with its real tables.

One pipeline runs through both: **structural walk → types/symbols → abstract interpretation → unified report**.

## Install / Quick start

```bash
moon add riantr/moonbit_static_analysis@0.4.0
```

```moonbit
// Use 1: revise a MoonBit (current-subset) program
let result : @pipeline.PipelineResult = @pipeline.run(source, "main.mbt")
println(@pipeline.render_result(result))

// Use 2: audit a state machine (machine tables come in as plain data)
let spec : @statecheck.MachineSpec = { name: "主体", states: [...], ... }
println(@statecheck.render(spec))
```

## The three inspections (pipeline core)

The inspections are assembled so that "each later one consumes the previous one's tables":

| Inspection | Package | Responsibility | Output |
|---|---|---|---|
| Structural | `src/walk` | assignment-as-binding, unused/undefined/param-reassigned, constant-folding pruning | binding tables `fn_bindings` |
| Type | `src/types` | annotations-as-contracts, inference, assignment/argument/condition checks (**declarations come from the binding tables**) | signature tables `sigs` |
| Behavior | `src/interp` | abstract interpretation over a lattice, signature-dispatched methods, virtual stacks (**method table comes from the signature tables**) | behavior findings |
| Merge | `src/pipeline` | one defect's echoes across inspections → one report, union of lenses | `render_result` |

Four assembly points: binding tables → symbol table (point 1), signature tables → method table (point 2), constant folding lifted into the lattice (point 3), merge/dedupe (point 4).

## Use 1: program-code revision (the fast-evolving MoonBit language)

```bash
moon run src/cli          # demo: 6 samples × 3 inspections
```

```
=== undefined.mbt ===
2:10 - error: undefined variable 'missing' (UndefinedName) [structural+type+behavior]
  in main() at undefined.mbt:4
  in g at undefined.mbt:1
Summary: 1 finding(s) (before merge: structural 1, type 2, behavior 1)
```

One defect seen by all three inspections → **one** report whose tag is the union; counts before and after the merge are both kept (the merge is lossless). Dead branches are pruned twice (structural `const_eval` + behavioral `ABool` lattice value); a call to a nonexistent `typo_fn` produces zero findings.

## Use 2: static state revision (machine tables → three inspections)

`src/statecheck` accepts a **plain-data specification of any state machine** — a `MachineSpec` (states / initial / terminal / transitions / trigger-slot placements / Block reasons / course). The three inspections read machine tables exactly like they read programs:

| Inspection | Machine-side semantics | What it checks |
|---|---|---|
| Structural | **states are bindings** ("assignment-as-binding" lifted to machine tables) | every state must be bound by at least one transition (in or out); out-only → `never entered`; reachability closure from the initial position; the terminal must be reachable (the machine must be able to finish) |
| Type | **the drive-slot contract** ("annotations-as-contracts") | every trigger must be placed into a known slot, no empty slots; a `Block` must carry a reason — **a road-less step must say so out loud, never silently** |
| Behavior | **the course as abstract execution** (virtual stacks) | every course step must be carried by some transition; a stranded step carries a virtual stack from entry frame → error frame |

```moonbit
let spec : @statecheck.MachineSpec = { name: "主体", states: [...], ... }
let findings : Array[@report.Report] = @statecheck.audit(spec)
let text : String = @statecheck.render(spec)   // merged text report
```

**pyroduct is the audited subject, not a dependency**: this module does not depend on pyroduct; the direction is pyroduct (its `audit` package) building a `MachineSpec` from its real tables and calling this module. One-way: machine → analyzer.

pyroduct's real self-audit (`moon run cmd/main -- audit`). **It pins 0.2.0**, so the
`0.2.0` in the output below refers to that pin, not to the version `moon add`
installs above:

```
规格 | 计数
---|---
状态 | 034
迁移 | 053
触发→槽 | 049 → 8
无路组合（带理由） | 228
修习历程 | 031 站

已知设计（4 条，出处层：设计使然——0.2.0 审计已验证）：
- state '无忆' is never entered: it appears only as a transition source
- state '无筹' is never entered: it appears only as a transition source
- state '无忆' is unreachable from the initial position '立位'
- state '无筹' is unreachable from the initial position '立位'

未预期发现：**0 条**
```

`无忆` / `无筹` (the model's names; in the source text 失忆 / 浑噩) are two real "out-only and
unreachable" positions in the subject machine (34 positions · 53 transitions · 8 drive slots) —
beyond pyroduct's own 192 tests, the three-inspection language independently re-derives the
machine's thesis-level boundary ("a past you cannot recall, a future not yet arrived"). The
"0 unexpected findings" line is a tripwire: any new structural / type / behavior finding on the
real tables fails pyroduct's tests and forces a re-review.

> The `pyroduct-shaped sample machine` printed at the end of `moon run src/cli` is this module's
> own **8-state toy** (`statecheck.pyroduct_flavored()`), not pyroduct's real tables. It carries
> coordinates like `182:12`; those are **stable pseudo-spans** hashed from the state name by
> `state_span()` (the same name always yields the same coordinate), not positions in any source
> file — don't go looking for that line in pyroduct.

## Package structure

```
src/core      Span/Severity/Lens/Family(merge_group contract)/Frame
src/report    Report struct and rendering (union lens tags, vst frames)
src/lexer     MoonBit lexer frontend
src/parser    MoonBit syntax → ast
src/ast       MoonBit abstract syntax
src/walk      structural inspection: binding tables + structural findings
src/types     type inspection: Ty/Ty?/Sig inference
src/interp    behavior inspection: AbsVal lattice + dispatch + virtual stacks
src/pipeline  assembly: run the three inspections + merge_group merge
src/moonfiles the other file kinds: .mbt.md per-block three-inspection / .mbti
              interface audit / .mbtp proof lint
src/statecheck use 2: generic machine-table audit (plain-data MachineSpec bridge)
src/samples   demo samples (embedded MoonBit source)
src/cli       executable entry (program demo + file-kind demo + sample machine audit)
```

## Verification

```bash
moon check --target all --deny-warn   # 0 errors, 0 warnings (js / native / wasm / wasm-gc)
moon test --deny-warn                # 75/75 green (75 on each of the four targets)
moon run src/cli                     # program demo + file-kind demo + pyroduct-shaped sample machine audit
```

`--deny-warn` is deliberate: the official package-configuration page says "In CI, add
`--deny-warn` to `moon check`, `moon test`, or the equivalent command to treat enabled
warnings as fatal errors". Without it nothing enforces the "0 warnings" claim — a warning
regression passes CI silently. The gate in `.github/workflows/gate.yml` therefore carries
`--deny-warn`; the cost is that a future toolchain release adding a warning turns CI red,
which is the point.

> CI runs `--target js` only. The "four targets" line above is a local result; CI does not
> cover native or wasm.

## File kinds (the other MoonBit toolchain suffixes)

The full taxonomy is in [EXTENSIONS.md](EXTENSIONS.md). Semantics follow
[docs.moonbitlang.com/en/latest](https://docs.moonbitlang.com/en/latest/) as the final
authority, cross-checked against mooncakes' [`moonbitlang/parser@0.4.3`](https://mooncakes.io/docs/moonbitlang/parser@0.4.3)
and [`moonbitlang/lexer@0.4.2`](https://mooncakes.io/docs/moonbitlang/lexer@0.4.2):

| suffix | static analysis here |
|---|---|
| `.mbt` | three-inspection program analysis |
| `.mbtx` | three-inspection program analysis + import-block audit (entry grammar `"path" [@alias] [*]`; duplicate paths report FParse; the import list is echoed in the report) |
| `.mbti` | interface audit: malformed lines / duplicate signatures / unknown type references. The line grammar matches what `moon info` actually emits, so generated files raise nothing |
| `.mbt.md` | literate: only fences the toolchain actually **compiles** — `mbt check` / `mbt test` and the `moonbit` spellings; a second word of `check` or `test` is what makes a block live code. Line numbers align to the `.md` file's real lines. A bare `mbt`, a bare `moonbit` and `nocheck` are display blocks and are skipped — measured against the toolchain, see EXTENSIONS.md |
| `.mbtp` | logic-side proof lint (string constants in bodies, banned `!`/`↔` forms, cross-package calls, lemma without `proof_ensure`) — **not a replacement for `moon prove`** |
| `moon.mod` / `moon.pkg` / workspace | recorded only, no static analysis (configuration is not code — upstream puts both in the parser's separate `moon_config` subpackage, alongside `syntax` and `mbti_parser` rather than inside them; see the config-boundary section of EXTENSIONS.md) |

The `.mbti` line grammar was aligned against real generated output: `moon info` emits
`import {}` blocks, `#deprecated` / `#alias(...)` / `#callsite(...)` attribute lines,
`const`, `impl ... for T`, `suberror`, and `fn` signatures carrying `pub` / `async` /
`extern` / type parameters / labeled parameters (`input_offset? : Int`) / `raise` /
`String?`. The earlier version reported every one of those as a malformed line — that
is, it false-positived on **every** real generated interface file.

## Formal verification (moon prove)

`src/core` is a pure kernel (no Array-carrying structs, no strings) with
`"proof-enabled": true` enabling MoonBit 2026 experimental formal verification;
`src/core/core_proof.mbtp` is the logic side: predicates (is_error /
type_error_family / lower_irreflexive_ok / lower_transitive_ok /
lower_antisymmetric_ok / rank_order_ok) + **19 lemmas** (the three rank constants,
the three strict-order laws for lower, rank_order_agrees, and the severity
classification: one lemma per Error family and per Warning family, plus the
full taxonomy).

```bash
moon prove src/core --why3-config .why3.conf   # emits 19 VCs for cvc5/alt-ergo
```

Verification status (each why3-lowered task in `_build/verif/src/core/*.smt2`
machine-checked with cvc5):

- **21/21 goals VALID** (unsat): the 19 lemmas plus the span_at/zero_span automatic safety VCs.
- Known toolchain limitations (all upstream, not this project's code):
  1. A `#proof_pure` function whose body is a **struct literal** (pos/span_at/zero_span)
     lowers to an opaque logic symbol — the body is dropped, so the span-shape law is
     unprovable in logic today (pinned operationally by tests; see the note in
     core_proof.mbtp).
  2. The bundled why3server (Windows build) loses the prover's stdout — why3 reports
     "High failure" with output `.`; the bare `why3 ... prove` CLI reproduces it.
     Per-goal bypass: `why3 -o <dir> -P cvc5 <mlw>` exports the SMT files, then run
     cvc5 on each.

Local reproduction shims (not part of the published zip): `.why3.conf`
(datadir/libdir pointing at `.moon/share/why3` and `.moon/lib/why3`, explicit
`[prover]` section) and `cvc5wrap.ps1` (strips why3's trailing
`get-info :reason-unknown` — cvc5 1.0.9 errors on it after a definitive answer,
which why3 1.7.2 fails to parse).

## Publishing

The module is published through the following channels (one source, three syncs):

| Channel | Address |
|---|---|
| Gitee (primary) | <https://gitee.com/ren-yongxiang/moonbit_static_analysis.git> |
| GitHub (mirror) | <https://github.com/riantr/moonbit_static_analysis> |
| mooncakes.io (package registry) | <https://mooncakes.io/docs/riantr/moonbit_static_analysis> |

- **mooncakes.io**: `moon publish` (after publishing, `riantr/moonbit_static_analysis@0.4.0` can be imported by any MoonBit module; `src/cli` ships a SKILL.md and is listed on [skills.mooncakes.io](https://skills.mooncakes.io)).
- **Gitee / GitHub**: `git push` to both; tags stay in lockstep with the moon.mod version.

## Analyze another project (without pulling this one in)

This tool scans **any** MoonBit repository, and that repository neither depends
on this module nor is modified — its sources are only READ, at scan time:

```bash
moonx riantr/moonbit_static_analysis@latest riantr/moonbit_doubleML@latest
```

The target is a registry coordinate (`author/module`, optionally `@version` or
`@latest`) or a local path; omit it to scan the current directory. A coordinate
is materialised with `moon fetch` into `.repos/` and then walked.

Output is one `kind<TAB>count<TAB>path` line per file plus a `SUMMARY` line.
**Measured**:

| target | files | result |
|---|---|---|
| this repository | 38 | 16 `.mbti` + 1 `.mbtp` **all clean**; 21 `.mbt` → 7215 findings (all subset edges) |
| `riantr/moonbit_doubleML@latest` → 0.107.0 | 177 | `.mbt.md` **0**; 176 `.mbt` → 49945 findings (all subset edges) |

The root package is a thin forwarder; the implementation is `src/sa`, a
**library**. That is deliberate: a main package importing another main package
is deprecated by the toolchain. Both `src/sa` and the root declare
`supported_targets = "+wasm+native"`, because file IO and subprocesses come from
`moonbitlang/async` and only some backends have a working async runtime (js has
none, wasm-gc wants a `run_async_main` that async 0.22.4 does not export); the
other backends SKIP those two packages instead of failing.

## DeepSeek Harness plugin

`src/jsoncli` is the JSON bridge entry: it runs under Node, takes one JSON
request on the command line, and answers with one JSON reply —
`{"kind":"program","source":...}` goes through the three program inspections,
`{"kind":"file","filename":...}` dispatches on the extension to the matching
file-kind analysis (`.mbt` / `.mbtx` / `.mbt.md` / `.mbti` / `.mbtp`),
`{"kind":"machine","spec":...}` through the machine-table audit. It is packaged
as the DeepSeek Harness plugin `@riantr/moonbit-static-analysis-dsh` (workspace
directory `dsh-plugin-moonbit-static-analysis/`), which exposes the **four**
tools `moonbit_analyze` / `moonbit_analyze_file` / `moonbit_audit` /
`moonbit_gates` to the agent — the
plugin only spawns and formats; every analysis semantic stays in MoonBit,
versioned and gated with the module. See that directory's README for the
install step (`plugin_manager` with `install_bundle`).
