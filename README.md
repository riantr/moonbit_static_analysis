# moonbit_static_analysis

**English** | [中文](README.zh.md)

`riantr/moonbit_static_analysis` — a **three-inspection (structural / type / behavior)
static-analysis pipeline** for MoonBit. One infrastructure, two uses:

1. **Program-code revision** — analyze programs in the **fast-evolving MoonBit language**
   (undefined names, unused bindings, type mismatches, dead branches, unreachable code);
2. **Static state revision** — a generic machine-table audit for multi-layer state machines
   (`src/statecheck`), where the audited subject calls this module and feeds its machine
   tables in as plain data.

It reads every MoonBit toolchain file kind — `.mbt` / `.mbtx` / `.mbti` / `.mbt.md` /
`.mbtp` — and it **never modifies the target**: the analysed repository neither depends on
this module nor is touched by it.

Measured on `moonbitlang/core` (1766 files): **1705 parsed, 30 actionable** — 10 of them are
constructs this frontend does not read or an operator it does not model, and the other 20 are
`MSA-015` dead stores on declarations: a `let` whose value is overwritten before anything reads
it. That is dead weight in the analysed code rather than a reader gap, and every one of the
20 was measured against the source it names. The 12 findings demoted in 0.4.38 — names the
analyzer could not resolve — are counted as notices and are not in that 30. On that same tree
`moon check --target all` reports **no** diagnostic at all.

## Contents

- [Features](#features)
- [Installation](#installation)
- [Quick start](#quick-start)
- [Use 1: program-code revision](#use-1-program-code-revision)
- [Use 2: static state revision](#use-2-static-state-revision)
- [API reference](#api-reference)
- [CLI reference](#cli-reference)
- [Understanding the output](#understanding-the-output)
- [Coverage and limits](#coverage-and-limits)
- [File kinds](#file-kinds)
- [Project structure](#project-structure)
- [Verification](#verification)
- [Release history](#release-history)
- [Contributing](#contributing)
- [License](#license)
- [References](#references)

## Features

- ✅ **Three inspections, one report** — structural walk → types/symbols → abstract
  interpretation, merged so one defect is **one** finding whose lens tag is the union of the
  lenses that saw it. The merge is lossless: the counts before and after are both kept.
- ✅ **Every MoonBit file kind** — `.mbt` / `.mbtx` / `.mbti` / `.mbt.md` / `.mbtp`,
  including the three the compiler does not audit at all.
- ✅ **Reads, never writes** — the analysed repository neither depends on this module nor is
  modified by it. The tool only ever reads the target's files, at scan time.
- ✅ **Cross-file symbol resolution** — `--extern-iface-dir` indexes `.mbti` declarations,
  so a type used from another package is not reported as undefined.
- ✅ **Honest coverage** — a file the frontend could not finish is reported `PARTIAL`, and
  its post-boundary findings are **counted and not shown**.
- ✅ **A notice only where it can matter** — a notice is printed per line only when it can
  hide a finding; the rest are counted by shape in one table. `--show-notices` brings the
  whole list back.
- ✅ **State-machine audit** — the same three inspections over plain-data machine tables:
  states as bindings, drive slots as a type contract, the course as abstract execution.
- ✅ **Mermaid diagram output** — `--mmd` / `--mmd-auto`, opt-in, and a truncated diagram
  says so in its own header.
- ✅ **Provenance in the filename** — package, version, **toolchain** and timestamp, so a
  scan can be compared with a later one.
- ⚠️ **`--per-function`** — a second entry point for the behavioral lens. Read
  [Coverage and limits](#coverage-and-limits) before using its numbers.

## Installation

```bash
moon add riantr/moonbit_static_analysis@0.5.2
```

Then import it in your `moon.mod`:

```moonbit
import {
  "riantr/moonbit_static_analysis@0.5.2",
}
```

### The host your toolchain has to be

The published wasm is **not self-contained**. It imports a **set of symbols** from
`moonbitlang/async` — the file IO, the process calls, the event loop — and the **host** has to
supply every one of them when the module is instantiated. `moonx` supplies them from the
async runtime that ships with **your** MoonBit toolchain.

**The set is measured, not stated, and it is a FLOOR rather than a mirror.** The published
0.5.2 artifact imports **92** symbols; this tree's own release build of the *same source*,
rebuilt against the toolchain this host now has, imports **92** as well — and the contract is
**93**, one wider than either, because a floor has to cover the artifact an older build
produced as well as the one this build produces. `moon publish` uploads the **source** and
mooncakes compiles it **server-side**, so the artifact's exact import set belongs to the
registry's builder toolchain rather than to this repository, and the two builders do not
always agree: against core 0.10.20 this tree's build asked for
`thread_pool/make_open_stat_job` where the published one asked for
`thread_pool/make_openat_job`. The gate checks that the artifact's imports are a **subset**
of the contract — a symbol *outside* it is a failure (that is the direction that drops users),
and a symbol *inside* it that one build does not ask for is a note.

So the artifact has a **floor**, and the floor is a property of the **toolchain** — and the
published *bytes* have to fit inside it:

| what | where |
|---|---|
| the symbols a host has to be able to provide — the **floor** | `_verify/host_requirements.txt` |
| the gate that holds the artifact to them | `_verify/check_host_requirements.ps1` |
| the same check against the **published** bytes | `_verify/selfscan_published.ps1` |

The floor is checked against the **toolchain**, and the toolchain has two layers: the bundled
`moonbitlang/core` declares **213** host externs, and the toolchain's C runtime implements
**288** `moonbit_rt_*` names — one of them, `moonbit_rt_make_openat_job`, is the file-IO job
the registry's builder emitted and **no core declares it**. Together they cover all **93**.

**Since 0.4.45 the runtime comes from `moonbitlang/core/async` — the copy bundled with
your toolchain — and this package depends on nothing at all.** No `moon.mod` import
block, no version to keep in step with the user's toolchain. That is the whole point:
the disagreement between "the version this package pins" and "the version the user's
toolchain has" is what broke 0.4.38.

**THE HOST ABI NAME DID NOT CHANGE, AND THE SYMBOL SET GOT BIGGER.** A wasm import's
module name comes from the FFI declaration in the source, and `moonbitlang/core/async`
still declares its host externs under the name `moonbitlang/async` — so the host
supplies the same module as before. What changed is the set: **90 → 93**, and the contract is
now **93** — the floor that serves both the local build and the published one.

| | symbols |
|---|---|
| **new** | `stdio/get_stdio_handle`, `thread_pool/get_read_console_result`, `thread_pool/make_read_console_job`, `thread_pool/make_write_console_job`, `thread_pool/run_job` |
| **gone** | `io/errno_is_read_EOF/windows`, `thread_pool/errno_is_cancelled` |

**AND THE FLOOR WENT UP WITH IT, WHICH IS THE PART TO READ TWICE.** MEASURED: the
standalone `moonbitlang/async` 0.22.5 covers only **89** of the 93 — it has
`stdio/get_stdio_handle` and none of the four `thread_pool` additions. The bundled
`moonbitlang/core` **0.10.21+06da1ed44** declares 213 externs and covers all 93. So:

> **0.4.45 and later need a MoonBit toolchain bundling `moonbitlang/core` 0.10.21+06da1ed44
> or later** — moon 0.1.20261117 or later. A toolchain that still bundles the standalone
> `moonbitlang/async` cannot instantiate this artifact, and upgrading this package alone
> will not change that: the import surface is a property of the published bytes.

**AND THE FLOOR MOVED AGAIN, ON 2026-11-20, BECAUSE THE TOOLCHAIN MOVED.** MEASURED: this
host's bundled core went from `0.10.20+65efd5b93` to `0.10.21+06da1ed44` (moon
`0.1.20261117`), with no change to this repository — the toolchain updated itself. The gate
named the consequence in its own words: *the floor and the toolchain are one fact, and a
toolchain that moved must move the floor.* So the floor moved, and **one symbol went with
it**: core 0.10.21 declares `thread_pool/make_openat_job` where 0.10.20 declared
`thread_pool/make_open_stat_job`, and the new toolchain gives **no host** the old name — so
the contract is **93** symbols, not 94. A floor that names a symbol no host can provide is a
floor that drops users, and that is the direction the gate treats as a failure.

The failure arrives before the analyzer runs a single line:

```
LinkError: WebAssembly.Instance(): Import #5 "moonbitlang/async" "thread_pool/make_write_console_job": function import requires a callable
```

**0.4.38 WAS BUILT FOR A NEWER HOST THAN MOST, AND A USER FOUND OUT.** Its
`moonbitlang/async` had been bumped to 0.22.6, which declares three more host-provided
symbols — the same three console jobs. A toolchain bundling 0.22.5 cannot supply them.
0.4.45 asks for those three again, plus two more, because the runtime it uses is the one
that ships with the toolchain. If you hit that error on 0.4.38: use **0.4.37**, or
upgrade your MoonBit toolchain, or move to **0.5.2**.

One more thing to know before you upgrade: `moonbitlang/core/async` is still marked
**experimental** by the core team, so the packages that use it say so explicitly in their
`moon.pkg`. A package that ships with your toolchain, and one that is not yet stable, are
two different things — this one is both.

## Quick start

### Scan another project — no dependency, no changes

```bash
moonx riantr/moonbit_static_analysis@latest riantr/moonbit_doubleML@latest
```

`moonx` downloads the **prebuilt wasm** that mooncakes built for the published version,
caches it, and runs it with `moonrun` — no clone, no local build.

The target is a registry coordinate (`author/module`, optionally `@version` or `@latest`) or
a local path; omit it to scan the current directory. A coordinate is materialised with
`moon fetch` into `.repos/` and then walked.

### Use it as a library

```moonbit
// Use 1: revise a MoonBit (current-subset) program
let result : @pipeline.PipelineResult =
  @pipeline.run(source, "main.mbt", @core.IfaceSymTab::empty())
println(@pipeline.render_result(result))

// Use 2: audit a state machine (machine tables come in as plain data)
let spec : @statecheck.MachineSpec = { name: "主体", states: [...], ... }
println(@statecheck.render(spec))
```

### Run the demo

```bash
moon run src/cli          # 6 samples × 3 inspections, the file-kind demos, a sample machine
```

## Use 1: program-code revision

The three inspections are assembled so that each later one consumes the previous one's
tables:

| Inspection | Package | Responsibility | Output |
|---|---|---|---|
| Structural | `src/walk` | assignment-as-binding, unused/undefined/param-reassigned, constant-folding pruning | binding tables `fn_bindings` |
| Type | `src/types` | annotations-as-contracts, inference, assignment/argument/condition checks (**declarations come from the binding tables**) | signature tables `sigs` |
| Behavior | `src/interp` | abstract interpretation over a lattice, signature-dispatched methods, virtual stacks (**the method table comes from the signature tables**) | behavior findings |
| Merge | `src/pipeline` | one defect's echoes across inspections → one report, union of lenses | `render_result` |

```
=== undefined.mbt ===
2:10 - error: undefined variable 'missing' (UndefinedName) [structural+type+behavior]
  in main() at undefined.mbt:4
  in g at undefined.mbt:1
Summary: 1 finding(s) (before merge: structural 1, type 2, behavior 1)
```

One defect seen by all three inspections → **one** report whose tag is the union. Dead
branches are pruned twice (structural `const_eval` + the behavioral `ABool` lattice value),
and a call to a nonexistent `typo_fn` produces zero findings.

## Use 2: static state revision

`src/statecheck` accepts a **plain-data specification of any state machine** — a
`MachineSpec` (states / initial / terminal / transitions / trigger-slot placements / Block
reasons / course). The three inspections read machine tables exactly like they read
programs:

| Inspection | Machine-side semantics | What it checks |
|---|---|---|
| Structural | **states are bindings** ("assignment-as-binding" lifted to machine tables) | every state must be bound by at least one transition (in or out); out-only → `never entered`; reachability closure from the initial position; the terminal must be reachable — the machine must be able to finish |
| Type | **the drive-slot contract** ("annotations-as-contracts") | every trigger must be placed into a known slot, no empty slots; a `Block` must carry a reason — **a road-less step must say so out loud, never silently** |
| Behavior | **the course as abstract execution** (virtual stacks) | every course step must be carried by some transition; a stranded step carries a virtual stack from entry frame → error frame |

```moonbit
let spec : @statecheck.MachineSpec = { name: "主体", states: [...], ... }
let findings : Array[@report.Report] = @statecheck.audit(spec)
let text : String = @statecheck.render(spec)   // merged text report
```

**pyroduct is the audited subject, not a dependency**: this module does not depend on
pyroduct; the direction is pyroduct (its `audit` package) building a `MachineSpec` from its
real tables and calling this module. One-way: machine → analyzer.

pyroduct's real self-audit (`moon run cmd/main -- audit`) prints:

```
规格 | 计数
---|---
状态 | 034
迁移 | 053
触发→槽 | 049 → 8
无路组合（带理由） | 228
修习历程 | 031 站

未预期发现：**0 条**
```

The "0 unexpected findings" line is a tripwire: any new structural / type / behavior finding
on the real tables fails pyroduct's tests and forces a re-review. The same run also lists
the four **known-design** findings it always reports (two states that are only ever left,
never entered) — they are omitted above because they are the model, not a defect, and
because the line that matters is the last one.

> The `pyroduct-shaped sample machine` printed at the end of `moon run src/cli` is this
> module's own **8-state toy** (`statecheck.pyroduct_flavored()`), not pyroduct's real
> tables. It carries coordinates like `182:12`; those are **stable pseudo-spans** hashed
> from the state name, not positions in any source file.

## API reference

### Program analysis — `src/pipeline`

| function | signature |
|---|---|
| `run` | `(src : String, file : String, extern_iface : @core.IfaceSymTab) -> PipelineResult` |
| `run_functions` | `(src : String, file : String, extern_iface : @core.IfaceSymTab) -> PipelineResult` |
| `render_result` | `(r : PipelineResult) -> String` |
| `merge_findings` | `(all : Array[@report.Report]) -> Array[@report.Report]` |
| `merge_group` | `(g : Array[@report.Report]) -> @report.Report` |

`run` enters the behavioral lens at the **module**; `run_functions` enters it at each
**function** (see [Coverage and limits](#coverage-and-limits)). The two views are separate,
not additive.

### Machine tables — `src/statecheck`

| function | signature |
|---|---|
| `audit` | `(spec : MachineSpec) -> Array[@report.Report]` |
| `render` | `(spec : MachineSpec) -> String` |
| `pyroduct_flavored` | `() -> MachineSpec` — the 8-state sample machine |

### Diagrams and provenance — `src/sa`

| function | signature |
|---|---|
| `mermaid_states` | `(verdicts : Array[Verdict], summary : Summary, prov : ScanProvenance, per_file : Int32, max_files : Int32) -> String` |
| `provenance_for` | `async (target : String, root : String) -> ScanProvenance` |
| `scan_artifact_name` | `(p : ScanProvenance, root : String) -> String` |
| `aggregate` | `(verdicts : Array[Verdict]) -> Summary` |
| `stamp_utc` | `(ms : Int64) -> String` |
| `moon_mod_version` | `(src : String) -> String` |

`mermaid_states` returns valid mermaid `stateDiagram-v2`. Two constraints it is written
around, both measured rather than assumed: a transition label is everything after the
**first** `:`, so it may not contain one — locations and messages therefore live in the
quoted state label; and MoonBit has no operator continuation, so a source line beginning
with `+` is a parse error, which is why the document is emitted one `write_string` at a
time.

`per_file` and `max_files` cap the drawing, `0` meaning no cap. **Whatever a cap leaves out
is stated in the diagram**, in the header and in a note on the file, so a truncated diagram
cannot be read as a clean one. Files are ranked by descending **actionable** count, not raw
findings: on `moonbitlang/core` the largest raw-finding file is `v128/simd_float.mbt` at
**51** findings — every one of them a notice, and none of them a defect — and ranking by
raw count put it first in a diagram whose job is to lead with what to fix.

### Provenance — the artifact name

A scan result is a claim about a specific tree, read by a specific toolchain, at a specific
moment. All three go in the filename — `<package>_<version>_<moonbit>_<stamp>.mmd`:

```
moonbit_static_analysis_0.5.2_0.1.20261023_20261024T060000Z.mmd
moonbitlang-core_0.1.20261105+65efd5b93_0.1.20261104_20261114T060000Z.mmd
tree_unknown_unknown_0.1.20261104_20261114T055946Z.mmd     # version not determined
```

| field | question | source |
|---|---|---|
| `package` | what was read | the coordinate, or the **resolved** directory |
| `version` | which revision of it | the target's `moon.mod` (`moon.mod.json` too) |
| `moonbit` | **which toolchain read it** | `moon version`, run as a subprocess |
| `stamp` | when | `@async.now()`, UTC |

`moonbit` is the field that cannot be recovered from the tree, and it is the one that
decides whether a scan can be compared with a later one. If the `moon version` subprocess
fails, that field reads `unknown` rather than being wrong.

Three things this deliberately does **not** do: it does not omit what it could not
determine (a missing version, toolchain or clock is the literal token `unknown` — with four
fields, dropping the segment would *shift* the others); it does not produce a dotfile (a
name starting with `.` is invisible to `ls`, and an artifact nobody can list is not one
anybody will find again); and it does not trust the filename as the record — the same
three facts are repeated as `%%` header comments inside the document, because a file gets
renamed and once it does its name is no longer evidence of anything.

### Reports — `src/report`

| function | signature |
|---|---|
| `Report::render` | `(self : Report) -> String` |
| `render_reports` | `(reports : Array[Report]) -> String` |

Each finding carries a note with `WHY:` (the rule that fired and the evidence it fired on)
and `HOW:` (what to change), taken from `@core.Family::advice`.

## CLI reference

```
moonx riantr/moonbit_static_analysis@latest <target> [flags]
```

| flag | meaning |
|---|---|
| `<target>` | registry coordinate (`author/module[@version]`) or a path. Omit it to scan the current directory. |
| `--exclude <dir>` | a directory name to skip. Repeatable. It exists because a dot-directory rule cannot catch everything: a project may keep vendored registry snapshots under an ordinary name. |
| `--extern-iface-dir <dir>` | a directory to scan for `.mbti` files whose declared types/values are treated as valid in every `.mbt` file under analysis. Repeatable. The natural target is `.repos/` after `moon fetch` of the dependencies you want indexed. The target's own tree is always indexed. |
| `--no-auto-fetch-deps` | by default the analyzer reads the target's `moon.mod` and `moon fetch`es each direct import. Pass this to skip the auto-fetch. |
| `--mmd <path>` | **also** write the scan as a mermaid `stateDiagram-v2` to `<path>`, and print `MMD<TAB><path>` on the last line. Opt-in on purpose: stdout stays the authoritative text report. |
| `--mmd-auto` | the same, but pick the name and write it to the **working directory** — never inside the analysed tree. |
| `--per-function` | enter the behavioral lens at each **function** rather than at the module. |
| `--explain MSA-011` | print that family's **contract** — what it asserts, the assumption it rests on, and what it does **not** cover — then stop. No scan runs. The value is mandatory, for the same reason `--mmd`'s is: a bare word after the flag could equally be the value or the target. |
| `--explain-all` | the whole roster, each family's three parts, then stop. No scan runs. |
| `--metrics` | **after** the `SUMMARY`, print the adequacy block: files understood, call sites visited and checked (with the share), findings by family × severity × confidence, and the declared scope-limit count. Opt-in: the block states how much was **checked**, not what was found, so it changes no count above it. |
| `--contexts` | **after** the `SUMMARY`, print one `CONTEXTS` line: how many function bodies the behavioral lens **executed** (`executions`), over how many distinct signatures (function + abstract arguments), reached from how many call strings, how many signatures were reached from more than one string, how many arrivals were recursion cuts, and the deepest call stack. Opt-in for the same reason as `--metrics`, and it answers a different question: not "how much was checked" but "how the analyzer spent its executions" — the code re-executes a body per call site rather than summarizing it (the book's §8.4 functional approach), so the call-string bound of §8.3 is never imposed and the recursion cut is the only context merge. |
| `--findings-shown-per-file N` | how many findings are **printed** per file (default 40). A printing limit, not an analysis limit: the SUMMARY counts come from every finding, so raising it reveals findings that were already counted and changes no summary number. |
| `--show-notices` | print **every** notice per line, not only the ones that can hide a finding. By default a notice is printed only when its region lies inside a function's extent -- that is, when a conclusion may have been withheld because of it -- and every other notice is counted by shape in one `NOTICES` table. This flag restores the whole per-line list, which is what the tool printed before 0.4.36, and it changes no count: the SUMMARY's numbers are the same either way. |
| `--families MSA-007,MSA-002` | report **only** these families, by their **stable id**. The ids are the `MSA-NNN` codes every rendered finding and every JSON record carries; the full roster is in [Confidence, ids, profiles and `nosec`](#confidence-ids-profiles-and-nosec). An id this version does not know is a `WARNING` and the scan still runs -- a family added in a later release must not make an older analyzer's profile unusable, and a typo must be loud rather than fatal. |
| `--exclude-families MSA-007` | report everything **except** these families. The same id vocabulary and the same rules. An id that is **both** included and excluded is an `ERROR` and the scan does not run at all: the two rules contradict each other, and which one won would be decided by the order of two `if`s inside the scanner. |
| `--honor-nosec` | honour `// nosec` comments in the **analysed** source: `// nosec` silences every finding on that line, and `// nosec MSA-007` silences that one family on that line. **Off by default**, and the default is a decision rather than an omission: a tool that stops reporting a finding because of a comment in the analysed source has an output the reader cannot trust without reading that source first. A `// nosec` that suppresses **nothing** is reported as a finding of its own -- a stale suppression is a fact about the source, and the source is what this tool analyses. |
| `--ssa-cost` | Measure what **static single assignment** would cost on the target tree and print one `SSA-COST` line: the variables the programs define, the versions SSA would give them, the phi-functions, and the copies their removal would need. It is a **query** and not a scan — it prints the line and stops, and no finding is reported. The claim it measures is the lecture's own — the *Intermediate Representation* lecture (`2_IR.pdf`, Nanjing University, Fall 2026), p.37: *"SSA may introduce too many variables and phi-functions"* — a claim with no number in it. The line carries its **coverage** beside the numbers, because a number without its coverage is half a number. |
`--mmd` requires its path and `--mmd-auto` is a separate flag, on purpose: an optional
value is ambiguous, because in `<target> --mmd <path>` the bare word after `--mmd` could
equally be a second, unexpected target, and there is no way to tell the two apart.

> **The CLI cannot exit non-zero.** MoonBit exposes no process-exit entry point in the
> packages available here, so a target that cannot be located prints `ERROR` and still
> exits 0 — **a caller must read the output, not the exit code**.

## Understanding the output

```
SCANNED	107 files under ...\ML\CI
CLEAN	.mbti	unchecked=0	...\CI/pof/pkg.generated.mbti
PARTIAL	.mbt	defects=1	notices=2	unchecked=17	read up to line 36, 57 after it not shown	...\CI/pof/aggregator.mbt
12:3 - notice: ... (UndefinedName) [behavior, MSA-002, low]
PARSED	32/107 files understood (29.9%); 75 more read only up to their first parse error
SUMMARY	files=107	parsed=32	actionable=56	notices=212	unreliable=15759	withheld=6769	unchecked=2841	total=16027	(actionable+notices+unreliable = total; withheld ⊆ unreliable; unchecked calls are not findings)
```

- **`PARSED` is the headline.** The frontend covers a SUBSET of MoonBit, so what it cannot
  read measures the tool's blind spot, not your code.
- **A partly-understood file is still worth reading.** The parser records the first line it
  genuinely failed on; findings before it are reported (`PARTIAL`), and everything after is
  counted in `unreliable` and never shown — it comes from a tree that is already wrong, so
  presenting it as results would reintroduce the exact failure this tool started with.
- **Skipped declarations do not move that boundary.** "This `test` block is not analysed"
  leaves the code after it readable, so such a file is `FOUND`.
- **`actionable` excludes notices.** A declaration form we chose not to analyse is not a
  defect in your code — and it does not pretend to be one: a scope limit is rendered
  **`notice:`**, not `error:`.
- Unparsed files are grouped **BY REASON** rather than listed one per line.
- `actionable + notices + unreliable` = `total`, asserted in the line. `withheld` is
  reported alongside it but is a subset of `unreliable`, so it is intentionally not part of
  the sum. **`unchecked` is not a finding count either**: it is how many calls the type
  lens could not check, and it is printed beside the sum precisely so it cannot be read
  as part of it.
- **A notice is printed only when it can hide a finding.** Since 0.4.36 the scan prints a
  notice per line only when its region lies inside some function's extent -- that is, when a
  conclusion may have been withheld because of it -- and counts every other notice by shape
  in one `NOTICES` table at the end of the scan:

```
NOTICES	TOTAL	notices=14157	printed=1754	aggregated=12403	1754 of them are printed per line: the ones that can hide a finding, and the low-confidence ones, which name a place. The other 12403 are counted by shape below
NOTICES	count=8330	test declaration is outside the analyzed subset; its body was not analyzed
```

  The table's `notices` is the SUMMARY's `notices`, its `printed` plus its `aggregated` is
  that number again, and its rows add up to its `aggregated`: three numbers from three
  different computations, and a reader can check that nothing was dropped on the way.
  The excerpt above is the TOTAL line and the largest row; the table carries one row per
  shape, largest first.
  The `printed` count is the CLASSIFICATION and not a promise that every one of those
  lines reached the screen — the per-file printing cap still applies to them, and the
  `... N more in this file` line says how many it hid. `--show-notices` restores the
  whole per-line list.

**Cross-file type symbol resolution** — a `.mbt` that uses a type declared in another
package (e.g. `Command` from `@argparse`) would otherwise fire `undefined name
'Command'`, because a single-file analyzer only sees the file it is reading.
`--extern-iface-dir <dir>` (repeatable) walks the named directory for `.mbti` files and
loads their declared types and value signatures into a **cross-file symbol table** the
structural walk and the type lens consult before reporting `FUndefinedName`.

The table only **suppresses**, it never invents valid bindings: names absent from the
table still report. A type hit returns `TUnknown`; a value hit returns `TUnknownFn` — a
known value whose signature was not read — so a call like `Command(...)` neither fires
`FOpMismatch` nor has its arity checked against an invented one. Lookups strip a leading
`@pkg.` first: a `.mbti` writes the declaration bare (`pub fn T::m`) while a use site must
write `@pkg.T::m`, so with exact matching the two spellings never met and the only common
way of naming another package never hit.

### Confidence, ids, profiles and `nosec`

Since 0.4.37 every finding carries **two facts beside its severity**, and both are in the
bracket that already held the lens tag:

```
12:3 - notice: no visible binding for 'cmd' (UndefinedName) [structural, MSA-002, low]
```

**THE CONFIDENCE IS HOW MUCH THE LENS CHECKED.** The severity says how bad the finding is
*if it is real*; the confidence says how sure the analyzer is that it is real, and the two
are independent — a finding can be severe and uncertain, or trivial and certain. There
are exactly three values, and they are the three situations a lens can be in:

| confidence | the lens… | the family | rendered |
|---|---|---|---|
| `high` | had the declaration, the signature or the type in front of it | everything else | its own severity |
| `low` | was reasoning from a **name** alone | `UndefinedName` (MSA-002) — the binding it could not find may be in a file, or in a package, it was never given | `notice:` |
| `undecided` | could not decide at all | a declared scope limit — the analyzer's own blind spot | `notice:` |

**SINCE 0.4.38 THE AXIS DECIDES SOMETHING.** A finding the analyzer does not stand behind
is **demoted**: it is rendered `notice:` and counted in `notices` rather than in
`actionable`. It is **not** hidden — it keeps its family, its stable id, its confidence
and its own line on the reader's screen; what changes is the label and the bucket. A
`low` finding is the analyzer saying *the binding I could not find may be in a file, or
in a package, I was never given*, and `actionable` is the list of things you should look
at.

A finding is **not** dropped for being uncertain. It is reported at a lower confidence —
and that is the whole difference between a silence that reads as "nothing to report" and
a statement about how much was checked.

**THE ID IS THE STABLE NAME.** The public family name is a second, hand-maintained
vocabulary: five of the original eleven names are not the tag with its `F` removed
(`FParse` → `ParseError`, `FAssignType` → `AssignTypeMismatch`, `FArgType` →
`ArgTypeMismatch`, `FOpMismatch` → `OperatorMismatch`, `FCondBool` → `NonBooleanCond`). A
consumer that pinned `"family": "ArgTypeMismatch"` in a suppression or a CI filter got no
warning at all when the name moved, because a name is not a contract. An **id** is
allocated once and **never renumbered**, so it survives a rename:

| id | family | id | family |
|---|---|---|---|
| `MSA-001` | `ParseError` | `MSA-007` | `ArgTypeMismatch` |
| `MSA-002` | `UndefinedName` | `MSA-008` | `OperatorMismatch` |
| `MSA-003` | `UnusedLocal` | `MSA-009` | `MethodError` |
| `MSA-004` | `UnusedParam` | `MSA-010` | `NonBooleanCond` |
| `MSA-005` | `ParamChanged` | `MSA-011` | `Unreachable` |
| `MSA-006` | `AssignTypeMismatch` | `MSA-012` | `StaleNosec` |
| `MSA-013` | `InfeasibleBranch` | `MSA-014` | `RedundantGuard` |
| `MSA-015` | `DeadStore` | `MSA-016` | `DivisionByZero` |
| `MSA-017` | `NegativeIndex` | `MSA-018` | `TaintFlow` |

The ids are hand-allocated on purpose — deriving one from the enum's position would
renumber every family after an insertion, which is the one thing an id must never do —
and `_verify/check_family_roster.ps1` **checks** the table: one id per family, no id used
twice, the ids a contiguous run from `MSA-001`, and the inverse table (id → family) the
exact reverse of the forward one. Two tables written down twice will disagree eventually,
and a disagreement between them is invisible, so a gate compares them.

**AND THIS TABLE IS CHECKED AGAINST THE CODE TOO**: `MSA-015` (`DeadStore`,
the dead-store family) was missing from this table for a whole release, and nothing said
so, because every gate compared the code's roster with itself and this table was prose.
`_verify/check_readme_links.ps1` now reads the ids and names out of **both** READMEs and
asserts that the set of families each table names is the set `all_families()` returns — so
a family that exists in the code and is missing from the table is a **gate failure**, not
a reader's discovery.

**`MSA-015` COVERS THE DECLARATION TOO.** A `let` is a write, and a `let` whose value is
overwritten before anything reads it is as dead as a re-assignment that is: `let mut x = 0`
followed by `x = 1` before any read of `x` is reported **on the declaration**. The two are
told apart by their own wording — *the value bound to 'x'* and *the value stored in 'x'* —
and a declaration is reported only when the name is read somewhere, so it never doubles up
with `MSA-003` (`UnusedLocal`), whose claim is the opposite one.

**`MSA-016` AND `MSA-017` ARE THE DECK'S OWN TWO APPLICATIONS, AND THE TOOLCHAIN CATCHES
NEITHER SHAPE.** The slide this tool's sign analysis comes from is titled *Static Analysis — An
Example*, and it names two applications of one analysis: *"Determine the sign (+, -, or 0) of
all the variables of a given program"* — *to check divided by zero error*, *to check negative
array indices*. The analysis is a **sign** domain (`+`, `-`, `0`, `unknown`), and it answers in
the **must** direction: a divisor whose sign is unknown is **not** reported, because the tool
says *this division **does** divide by zero* only when it can prove it, and a crash claim that
is "maybe" is a false positive waiting to happen.

MEASURED against the compiler: `moon check` on a probe holding `1 / 0`, `10 / y`, `arr[-1]`,
`arr[0 - 1]` and `arr[0]` exits 0 and says nothing about either shape. So a finding here is
not a duplicate of what the compiler already says — it is the only thing in the toolchain that
says it.

THE TWO CLAIMS ARE SEPARATE FAMILIES, because they are separate claims about separate
operands: `MSA-016` is about the **divisor** (`/` and `%` — the remainder fails the same way at
run time, and a float dividend is not a crash and is not reported), and `MSA-017` is about the
**index**. One line can carry both (`a / b[0]`), and a reader given one family for both would
have to guess which operand the finding was about.

**THE PROFILE SELECTS FAMILIES BY ID**, and it is checked before the scan runs: an id this
version does not know is a `WARNING` and the scan still runs; an id that is both included
and excluded is an `ERROR` and the scan does not run at all. The filter is applied to the
whole report list *before* the trusted-region split, so `total`, `unreliable` and
`notices` all describe the same findings.

**THE `nosec` IS PER LINE AND PER FAMILY**, and it is **off by default**:

```moonbit
let x = cmd()          // nosec              -- silences every finding on this line
let y = cmd()          // nosec MSA-002      -- silences that one family on this line
```

A `// nosec` that suppresses **nothing** is reported as a finding of its own —
`StaleNosec`, `MSA-012` — because a suppression that has gone stale is dead weight in the
source and a sign that the code it referred to has changed. The stale finding is produced
*after* the suppression pass, so a blanket `// nosec` cannot silence the warning about its
own staleness.

**AND A COMMENT THAT NAMES A FAMILY MUST NAME IT BY ITS ID.** The grammar of the comment is
the marker and a list of family ids — `MSA-007`, `MSA-002` — and a token that is not an id
is not part of the comment. Two shapes of text are therefore not suppressions at all: a `//`
inside a `///` doc comment (a doc comment is text, and the text is usually the
documentation of this very syntax), and a `//` inside a string literal (the quote lands on
the id, so the token after the marker is not an id). Measured on this tool's own source
with `--honor-nosec`: the analyzer before these two rules reported **nineteen** stale
suppressions, every one of them this repository's own prose, and the tree with the two
rules reports **zero** — and the two rules move no notice at all.

**AND IT REACHES THE FINDING'S OWN LINE, NOT THE WHOLE STATEMENT.** `bandit` unions the
issue's line with the *context's* line range, so there a `// nosec` on the first line of a
multi-line call silences what is three lines down. Here the line is the line: a `// nosec`
on the statement's first line does **not** reach a name further down, and the name is
reported where it is. Measured both ways — with the comment on the statement's first line
the finding is still reported (as a `notice:`, because it is a name the analyzer could not
resolve), and with the comment on the name's own line the file comes back clean. Widening
the rule would move the pinned corpus baselines, so it is stated here rather than slipped
in.

**AND A SUPPRESSION THAT WORKED LEAVES NO TRACE IN THE COUNT.** `bandit` keeps **two**
counters — `nosec` for blanket suppressions, `skipped_tests` for the id-targeted ones — so a
reader can see how many findings the source's own comments took out of the report. Here a
finding that a `// nosec` removed is simply not there: the SUMMARY counts what is left, and
nothing says how many were taken. Measured: with `--honor-nosec` and two working
suppressions, the output mentions a suppression nowhere. The analyzer does disclose the
*opposite* case — the calls it could not check are counted as `unchecked` rather than rounded
down to silence — so the two halves are not symmetric today, and the asymmetry is stated here
rather than left for a reader to discover.

**AND THE CALLS THE ANALYZER COULD NOT CHECK ARE DISCLOSED.** The type lens checks a
call's arity and argument types only when it has read the callee's signature; a `.mbti`
gives a name and never a parameter list, a method's signature is not in the source at all,
and a `..` chain link is a method call wearing different syntax. Until 0.4.37 the tool
said nothing about any of them, so *I could not check this* and *there is nothing to
report* were the same output — and a file with no findings and four hundred unchecked
calls printed exactly like a clean file. Now the count is on the file's own verdict line
(`unchecked=N`) and on the `SUMMARY`, where it is deliberately **not** part of the sum.
Measured on the seven pinned corpora: **30,340** unchecked calls, against **31** actionable
findings.

**AND THE REMAINDER IS SPLIT BY REASON, BECAUSE THE TWO REASONS THE LINE NAMED ARE NOT THE
ONES THAT DOMINATE.** `METRICS calls` reports `sites`, `checked` and `not-verified`, and for
eight releases the sentence beside `not-verified` said it was **two** classes — *a callee
that is not callable* and *a name that did not resolve*. Measured — one construct per file
against a baseline of one checkable call — the remainder has **five** reasons, and the two
the sentence named are the only two that **report** anything. The other three are
**silent**, and they are the majority:

| reason | this tree | the seven corpora | reports? |
|---|---:|---:|---|
| a method call — the lens has no signature for a method | **3,800** | **21,350** | silent |
| a callee that is not callable | **498** | **7,647** | reports (`MSA-008`) |
| a cross-file value whose signature was never read | **191** | **1,941** | silent |
| a `..` chain link — the lens has no signature for it | **0** | **104** | silent |
| a name that did not resolve at all | **0** | **16** | reports (`MSA-002`) |
| **the remainder** | **4,489** | **31,058** | |

So **88.9 %** of this tree's 4,489 unverified call sites are silent, **75.3 %** of the
corpora's 31,058 are, and **84.7 %** of this tree's remainder is one reason the old
sentence never named — a method call. Across the seven corpora and this repository's own
source together: **35,547** unverified call sites, of which **25,150** are method calls.
The old sentence was not wrong about the two classes it named — those are the two that
report — but it was wrong about the **whole**, and a reader could not tell which part of
the remainder was which. The split is printed by the analyzer as its own
`METRICS unverified-split` row, whose `sum` is the remainder it splits, so the row checks
itself; both figures above are pinned by the release gate.

## Coverage and limits

### What this tool does not compete with

On `.mbt`, this tool does **not** compete with the toolchain's compiler: `moon check` has a
real parser and reads the **whole** language. On the same `moonbitlang/core` it reports
**no** diagnostic at all; this tool's `.mbt` frontend reads a **subset**
and parses **1705 of 1766** files (96.5%); `.mbti` and `.mbt.md` are 100%.

What this tool can do that the compiler cannot: the three file kinds the compiler does not
audit at all — `.mbti`, `.mbt.md`, `.mbtp` — plus cross-package semantics.

### What a finding is worth: sound, complete, useful

No static analyzer is exact. **Rice's theorem** says a non-trivial property of a program's
behaviour cannot be decided in general, so every analyzer gives something up, and the only
question is *what*. The standard vocabulary:

- **sound** — it reports no false negative: everything it reports is really there;
- **complete** — it reports no false positive: everything that is really there is reported;
- **useful** — sound *or* complete, but never both.

**This tool is useful, not perfect, and it says which side it is on.** It does not claim to be
complete: a finding can be a false positive, and the parts of the language it cannot read are
reported as notices rather than as defects. It does not claim to be sound either: the dead-code
and unreachable-code families decide over an approximation of the program's control flow and
values, and the [`--per-function`](#--per-function-the-behavioral-lens-at-each-function) view
says in its own words that it is not yet sound. What it does promise is narrower, and it is
promised per finding: **a finding the analyzer does not stand behind is rendered a notice**
(see [Confidence, ids, profiles and `nosec`](#confidence-ids-profiles-and-nosec)), and every
notice says what the tool could not read.

The lecture series this tool's analyses follow is Nanjing University's *Static Program
Analysis* (`1_Intro.pdf`, Yue Li, Fall 2026); the map of the course's decks — what each
one asks, and where this tree has it — is in `_verify/NARRATIVE.md` §0572, and the two
things the course itself measures this tree against — which of its analyses this tree
implements, and the one place where the framework and this tree disagree — are in §0564.

### The constructs the frontend reads past

Every declaration or expression form it reads past **without analysing** is reported as a
notice, and the notice is a statement about the tool, not about your code — so it is
rendered **`notice:`**, a label of its own rather than a borrowed `error:`. Measured on this
project's own source (280 files), with the per-file printing cap lifted so the count is the
whole finding set:

| notice | n | | notice | n | | 
|---|---:|---|---|---:|---|
| `test` declaration | 1800 | | `const` declaration | 7 |
| `if` expression | 101 | | `short lambda` | 8 |
| `struct` declaration | 121 | | `type` declaration | 7 |
| `anonymous function literal` | 48 | | `try` expression | 1 |
| `enum` declaration | 35 | | | |

Removing one of those rows needs an AST node for that form, which is why they are features
and not notices to be reworded. The distinction that matters is not the wording but the
**position**: **158** of them sit inside a function's extent and can switch that body's
audit off, so they are printed one per line; the other **1970** sit outside every function's
extent, hide nothing, and are counted by shape in one table at the end of the scan.

**The split is the analyzer's own geometry, and it is a position rather than a wording.**
A region inside a function's extent is in that function's hole list, so the frame audit
could not judge a binding the region might have read; a region outside every function's
extent is in no function's list at all, so it hides nothing. The same
`if expression is outside the analyzed subset` notice is printed when it sits inside a
function and counted when it sits at module top level -- so a rule keyed on the message
would be wrong about one of the two.

**The `match` expression row is gone**: since 0.4.34 the arms of a `match` are read, and
arms are ordinary code, so a `match` is no longer a region that was "read past but not
analysed".

**AND THE RATE OF THAT EXCLUSION IS MEASURED, NOT ASSUMED.** The `test` declaration row
above is the largest one, and it is the one that hides the most: a `test` body is not
analysed at all, so a defect planted inside one is invisible. Measured on six planted
defects — each the same defect its family's own fixture carries, the only difference being
that here it sits inside a `test` body — the analyzer detects **0 of 6**. The same six
defects in a `fn` body are **6 of 6**, and the whole eighteen-family fixture set is
**18 of 18**. The rate is pinned by `_verify/check_blindspot_rate.ps1`, and the pin is not
vacuous: its self-test takes the `test` wrapper off a copy of the fixtures and requires
the very same defects to be detected, each of them as its own family — so a green gate
means *the wrapper hides them*, not *the analyzer cannot see them*.

**AND THE EXCLUSION IS THE TOOL'S, NOT THE LANGUAGE'S.** `moon check` — the MoonBit
compiler — **does** analyse a `test` body: given a file whose test body carries a type
error, the compiler reports it, at the line inside the body. So the language permits the
analysis and the compiler performs it. The gap is in this tool's parser, which **skips**
a `test` body instead of parsing it, so no AST is built for the body at all — and it is
not a one-line fix, because this tool's subset parses a file **completely** before it
reports, and a `test` body is a construct the parser has never built an AST for. Both
answers are reproduced by `_verify/settle_0616_blindspot_class.ps1`.

### `ParseError`: one family, two meanings

`ParseError` is not one thing. It covers a **declared scope limit** — the analyzer read a
construct and did not analyse it — and a **genuine defect** in the file: an unterminated
string literal, a malformed interface line, a duplicate signature. The two arrive from
different producers and are told apart by one predicate, `Report::is_notice`, which the
renderer, the counts, the mermaid drawing and the JSON bridge go through. **One consumer
deliberately does not**: the split that decides which notices get a line of the reader's
screen asks `Report::is_declared_scope_limit` instead, so a demoted finding keeps its own
line.

| what it is | rendered | counted as |
|---|---|---|
| a declared scope limit | `notice:` | a notice — excluded from `actionable` |
| a low-confidence finding (since 0.4.38) | `notice:` | a notice — excluded from `actionable` |
| a genuine defect in the file | `error:` | actionable |

Measured across the seven pinned corpora and this repository's own source, with the
per-file printing cap lifted so the count is the whole finding set: **24,110** notices —
every declared scope limit, plus the low-confidence findings demoted in 0.4.38. The scan
says so itself: its `NOTICES` table counts **4,021** of them as printed per line and
**20,089** as aggregated — which is 4,021 + 20,089 = 24,110, the same number — and the 4,021
is exactly the number of rendered notice lines, the scope limits and the demoted findings
together. A genuine defect of this family would
render `error:`, and the release gate counts those separately and requires zero — and there
are none.

### A region silences the bindings it could have read, and no others

When the frontend deliberately does not analyse a construct — a `match`, an `if` in
expression position, a lambda — it leaves a **region** in the file. The region was never
read, so it might contain a read of anything in scope around it. The analyzer used to
treat that as one verdict for the whole function: a single region anywhere switched off
**every** conclusion the function's frame could support, so a `match` at the end of a
function took the unused-local verdict away from a binding declared at the top of it.

The verdict is now per **binding**. A region can only reach a binding that was already in
scope when the region began, so a binding declared *after* the region's extent ends is
judged, and one declared before it is not. A binding read **only** inside the region is
still not reported: the region might have read it, and claiming otherwise would be a
false positive on correct code.

Measured, and the number is the reason this is worth reading. With the region suppression
switched off — one line in `Walker::holes_in`, and the diff against the shipped build —
the tool produces **701** `UnusedLocal` and **1,339** `UnusedParam` findings across the
seven pinned corpora and this repository's own source — the same 280 files the notice table
above counts, with `_verify/` excluded because it holds no tracked source, so the pair is
reproducible from a clean checkout. With it on, as it ships, it
produces **one** of them: a local assigned and never read, in `moonbit_labeler`. So the
suppression is hiding **700** locals and **1,339** parameters, and the per-binding
narrowing recovers **none** of them on today's corpora — every one of those bindings is
declared *before* its region, and the region could still have read it. What the narrowing
buys is that regions are judged one binding at a time, so that **reading** a region
(which is what analysing `match` means) restores the verdicts for the bindings the
*other* regions cannot reach, instead of restoring nothing.

There is no compiler to check this against: MoonBit's `moon check` has no unused-local
warning (the `0079` this repository's own `moon.mod` disables is *unused derive*), and
every pinned corpus sets `warn_list: ""`. The rule is held in place by
`_verify/check_frame_audit.ps1` and `_verify/mutate_0501.ps1`.

### The two blind spots in `UndefinedName`

Both are known and both say so in the finding's own note:

- a `#doc(hidden)` API appears in no `.mbti`, so it cannot be indexed from the dependency's
  **source**;
- a top-level cross-package reference written `@pkg.fn(1, 2)` is not folded into a callable
  name by the parser, so it is reported even when the package *is* indexed.

### `--per-function`: the behavioral lens at each function

`--per-function` analyzes every function as if it were the program's entry point, with its
parameters bound to fresh abstract values of their **declared** types. The declared type is
the only sound choice for an entry point: the parameter's runtime value is unknown, so the
lens must assume the declared type and nothing more.

The two views are **separate, not additive**, so they can be compared without either hiding
the other. The default (module) view is unchanged: the same corpora produce byte-identical
numbers with and without the flag.

> **This view is not yet sound, and the flag is opt-in for that reason.** It is measured
> across **all seven** pinned corpora by `_verify/census_perfunction.ps1`, and the release
> gate **pins** the number. Today it reports **47** `actionable` findings — 46 of them on
> `moonbitlang/core` and one on `moonbit_labeler` — where the module view reports 30 and 1.
> The census classifies them: **26** are constructs this frontend does not read or operators
> it does not model, **20** are dead stores — a value nobody reads, and the lens's own claim
> about the code — and one — a local assigned and never read in `moonbit_labeler` — is still
> the first true defect this tool has published on any corpus.
>
> **Every one of them is in a NAMED family.** The census keeps a bucket for findings it
> cannot classify, and that bucket held nine `MSA-015` dead stores until 0.4.45 — a family
> reporting a store as unread while the read sat inside a region the frontend had declared
> outside its subset. The rule that fixes them is the one the frame audit already applies:
> a function with a hole in it is not audited.
>
> | family | n | what the lens claimed |
> |---|---:|---|
> | C | 6 | `==` between two arrays |
> | D | 4 | `Int + Char` and `List + List` |
> | E | 3 | `*` on a struct |
> | G | 8 | unreachable code — the lens's own claim about the code |
> | H | 1 | a local assigned and never read — the lens's own claim about the code, and the one finding in the census that is a real defect |
> | I | 1 | `abs` on a `Double` |
> | J | 1 | `*` on two function values |
> | K | 3 | a local call with a named argument |
> | M | 20 | a dead store — a value nobody reads — the lens's own claim about the code |
>
> **AND 16 MORE ARE DEMOTED.** Since 0.4.38 a finding the analyzer does not stand behind is
> rendered `notice:` and counted as a notice rather than as actionable, and the census keeps
> the demoted set in its own table and its own total — a set of findings that leaves the
> census is a set that can go missing silently. Every one of the 16 carries the confidence
> `low`, and every one of them is a name the analyzer could not resolve.
>
> **THE MODULE VIEW COUNTS 12 OF THEM, AND IT IS NOT THE SAME 12.** The two views are two
> analyses — this one takes every function as an entry point, the module view takes the
> module — so they do not find the same names: in `moonbit_core` this view reports 16 and
> the module view 12, and only **8** of those are the same site. That is the same difference
> as the 46 against the 30 above, and the two views stay separate, not additive.
>
> | demoted family | n | what the lens claimed |
> |---|---:|---|
> | B | 8 | a BigInt literal's `N` suffix (`0N`) is not read |
> | L | 8 | the documented `#doc(hidden)` limit |
>
> **FAMILY A IS GONE, AND IT IS GONE BECAUSE IT WAS FIXED.** It was the hex float: the
> lexer read `0x1.0p1023` as the integer `0x1` followed by the name `p1023`, and every
> exponent part it could not read became an undefined name. The lexer reads a hex float as
> ONE literal now, with the value the toolchain computes for it, so the family has no
> members left — and the row is kept in the census, empty, so that a hex float that leaks a
> name again is caught rather than reported as something the census could not classify.
>
> **"Accepted" is measured, not assumed.** `moon check --target all` on `moonbitlang/core`
> reports **no** diagnostic at all: the pinned core is self-hosted and the toolchain
> type-checks interface files, and this version of the core passes that check cleanly. That
> is only half of it: a file with no diagnostic is indistinguishable from a file nobody
> opened, so `_verify/control_perfunction_census.ps1` appends a deliberate type error to each
> of the **seventeen** files that carry a finding **in a copy** and requires the error back —
> the requirement is **17 of 17**, and the control reads **17 of 17** today.
>
> (That row was **red from 0.4.43 to 0.4.46**, and the reason was the corpus and not the
> analyzer: the old pin carried one diagnostic of its own — `abort/pkg.mbti:4`, where the
> `String` of `fn[T] abort(String) -> T` is out of scope — and the checker *bails* on it
> before it type-checks anything else, so every probe came back carrying that one error and
> the probe's own error never appeared. The re-pin to `0.1.20261105+65efd5b93` brought a
> corpus this toolchain can check end to end, and the row turned green with it.)
>
> **The eight in family L are the documented limit rather than a defect**: a cross-package
> `#doc(hidden)` function cannot be indexed from the dependency's *source* — only from its
> `.mbti` — so the `new_uninitialized` constructors of `io` are still reported as undefined
> functions: `@io.Utf8TextView::new_uninitialized` on four sites, `@io.Utf8Writer::new_uninitialized`
> on two and `@io.Utf8Reader::new_uninitialized` on two. Answering them would mean growing the
> analyzer into a source indexer, which is a different project. **Use the view to see the lens,
> not to gate a build on it.**
>
> (This note said **116 → 2** until 0.4.32, and the "2" was the census of **six** corpora
> — `moonbit_core` was not in it, and it carries more findings than all six put together.
> The number was true of the corpora that were measured and false of the ones that were
> not. The history is in [CHANGELOG.md](CHANGELOG.md).)

## File kinds

| suffix | static analysis here |
|---|---|
| `.mbt` | three-inspection program analysis |
| `.mbtx` | three-inspection program analysis + import-block audit |
| `.mbti` | interface audit: malformed lines / duplicate signatures / unknown type references. The line grammar matches what `moon info` actually emits, so a generated file raises no *malformed line*. The unknown-type check consults the module-wide interface table and measures **0** on `moonbitlang/core`. A residual finding can still name a type declared outside the scan — treat it as unverified, not as a defect. |
| `.mbt.md` | literate: only fences the toolchain actually **compiles** — `mbt check` / `mbt test` and the `moonbit` spellings. A bare `mbt`, a bare `moonbit` and `nocheck` are display blocks and are skipped. |
| `.mbtp` | logic-side proof lint (string constants in bodies, banned `!`/`↔` forms, cross-package calls, lemma without `proof_ensure`) — **not a replacement for `moon prove`** |
| `moon.mod` / `moon.pkg` / workspace | recorded only, no static analysis — configuration is not code |

The full taxonomy is in [EXTENSIONS.md](EXTENSIONS.md).

## Project structure

```
src/core      Span/Severity/Lens/Family(merge_group contract)/Frame + Family::advice
src/report    Report struct and rendering (union lens tags, vst frames)
src/flow      data-flow framework: CFG + four solvers (round-robin, the
              edge-transfer variant, and the before-node and forward work lists,
              run against each other in tests),
              basic blocks and the CFG over them,
              live variables (may, backward), the
              interval domain with widening, available expressions (must,
              forward — the dual reading of the same solver), constant
              propagation (the same lattice, read over a CFG), the call
              graph (the whole-program graph, over the trait hierarchy),
              and the pointer analysis read seven more times: over a pointer
              flow graph, with a context (call-site / object / type), with a
              scope (on demand), with a context-sensitive heap, without a heap
              at all (access paths -- the storeless model), and interprocedurally
              with the call graph built on the fly
src/sa        scan entry + aggregate() + mermaid_states() (public, library)
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
src/jsoncli   the DeepSeek Harness JSON bridge
```

The root package is a thin forwarder; the implementation is `src/sa`, a **library**. Both
`src/sa` and the root declare `supported_targets = "+wasm+native"`, because file IO and
subprocesses come from `moonbitlang/core/async` and only some backends have a working async
runtime; the other backends SKIP those two packages instead of failing.

### The data-flow framework carries both directions

`src/flow` has a `Lattice` of `bot`/`join`/`eq` and four fixed-point solvers, and for three
increments every analysis built on it was a **may** analysis: live variables is may-and-backward,
and the interval domain widens up an ascending chain. Available expressions is the other
direction — `IN[B] = ∩ over P OUT[P]`, a **must** analysis whose safe answer is an
under-approximation — and it needs no second solver: a must analysis over (⊤, ∩) IS a may
analysis over the same carrier ordered the other way, so it passes the existing solver a lattice
whose `bot` is ⊤ and whose `join` is ∩. The entry node is special-cased to ∅ (nothing is
available before the program starts), and the three ways this goes silently wrong — ⊥ seeding,
a missing entry case, and a meet whose accumulator identity is ∅ — are each pinned by a test in
`src/flow/avail_test.mbt`.

**AND A FOURTH KIND OF ANALYSIS: ONE THAT REMOVES A FACT.** Pointers-to analysis
(`src/flow/pta.mbt`) asks which objects a pointer can point to, and the framework carries it
twice. The flow-insensitive reading — one map of points-to relations for the whole program —
is the one the source is written in, and the flow-sensitive one keeps a map **at each program
location** and **replaces** a pointer's set when it is written instead of joining into it. That
is the first transfer in this package that is not a join, and it is still monotone, so it
still runs on the same solver. Its soundness rests on the pointer domain: a variable's old
binding is private to the variable, and a field pointer is named by its **object** (`o1.f`),
so there is exactly one pointer per (object, field) pair and nothing else can hold a
different opinion about that field. `src/flow/pta_flow_test.mbt` pins the tables the source
deck prints for one program, in both readings, and checks the two solvers agree on it.

**AND A FIFTH KIND: A THREE-VALUED DOMAIN READ OVER A CFG.** Constant propagation
(`src/flow/cprop.mbt`) asks what a variable's value is at each program point, and its domain
is three-valued: `Undef` (no value yet), `C(n)` (the constant `n`) and `Nac` (not a
constant). The domain and the rules were already in this tree, and so was the
*interprocedural* reading of them -- but that reading has no frame: no CFG to run over, no
confluence to meet at, no fixed point to reach. `src/flow/cprop_intra.mbt` supplies the frame
the lecture states (*Data Flow Analysis -- Foundations*, `5-6_DFA-FD.pdf`, Nanjing
University): a CFG, the meet
at every confluence, and the fixed point. **Nothing is re-implemented.** The lecture's four
meet rules -- `NAC ⊓ v = NAC`, `UNDEF ⊓ v = v`, `c ⊓ c = c`, `c₁ ⊓ c₂ = NAC` -- are exactly
this domain's existing join, and the three transfer rules -- `x = c`, `x = y`, `x = y op z` --
are the rules the module already had, now shared by both readings through one function
(`cprop_assign`). The two readings differ at exactly **one node kind**: at a call, the
interprocedural rule answers the identity and the intraprocedural one answers `Nac`. What is
new is the frame, and the third solver that runs it.

**THE THIRD SOLVER IS A DIFFERENT SHAPE, NOT A NEW ALGORITHM.** `solve_worklist` in
`src/flow/worklist.mbt` is the forward work list the lecture's §11 prints: the state is
`OUT[B]`, each node's input is read back from its predecessors, and a successor is re-queued
only when the OUT of its predecessor moved. The package already had a round-robin solver
(the same equation system, a different visit order) and a work list that carried the state
*before* the node; this is the third shape. The lecture calls the work list "an optimization
of Iterative Algorithm" (p.256), which is a claim that the two compute the **same** fixed
point -- so a test runs the constant propagation through the new solver and through the
round-robin one and requires them to agree **node for node**, and a second test requires the
work list to **join** two predecessors rather than overwrite them, which is the meet and the
one thing a work list gets wrong silently.

**THE ANALYSIS IS NOT DISTRIBUTIVE, AND THE TREE SAYS SO.** The lecture prints its own
counterexample (p.249-252): on the graph `Entry → X(a=1,b=9) / Y(a=9,b=1) → Z(c=a+b)`,
joining first and transforming after gives `c = NAC`, while transforming first and joining
after gives `c = 10` -- the sum is 10 either way, but the meet has already thrown the
constants away. This tree's analysis joins first, so it answers `NAC`, the safe answer, and
the test pins **both** orders, so the difference between them is a fact in the tree rather
than a remark on a slide. The domain's order (`cpv_leq`) is published rather than kept
private, because the lecture's last task -- *"Show our constant propagation analysis is
monotonic"* (p.254) -- is a claim about a function that has to be reachable to be tested, and
monotonicity is the precondition the fixed-point theorem needs.

**AND IT SPEAKS NO NEW FAMILY.** The class this analysis could report -- a branch whose
outcome is decided before the program runs -- is already spoken by `MSA-013`
(`InfeasibleBranch`) and `MSA-014` (`RedundantGuard`). So `cprop_const_branches` is a
**measurement**, not a report: it names the branches the analysis can decide, and it adds no
family, because the family that would carry those findings already exists.

**AND A SIXTH KIND: THE WHOLE-PROGRAM GRAPH OVER IT.** The call graph
(`src/flow/callgraph.mbt`) is the deck's second section -- *Interprocedural Analysis*
(`7_Inter.pdf`, Tian Tan, Nanjing University), p.33-39 and p.52-56 -- and it is where a
method call
stops being a hole. The deck's `Resolve(call)` has three cases and MoonBit answers all
three: a **static** call `f(x)` names its target; a **special** call `Type::m(x)` names
its type in the call; and a **virtual** call `recv.m(x)` is resolved through the
receiver's **declared type** -- if that type is a trait, the targets are the trait's own
method plus one for every type that implements it, which is the deck's *"c' that is a
subclass of c or c itself"*; if it is a concrete type, the target is that type's own
method.

MoonBit has no classes, so the deck's **class hierarchy** is the **trait hierarchy** --
`impl Trait for Type` and `derive(Trait)` -- and it is read from the source text,
because this tree's AST does not carry it: the parser reads past `trait` and `impl`
declarations whole, so *"which type implements which trait"* was a fact nobody in this
tree could answer. The **declared type** of a receiver is the annotation (`SLet`'s second
field, `Param.tyann`), because the type lens publishes only the module frame, and a
function's local types are therefore published nowhere.

Two boundaries are counted rather than hidden. A **method's body is not in the tree**,
so the graph's edges *name* the implementations and stop there -- the calls inside an
implementation are not visible. And a call whose receiver has **no declared type**
resolves to nothing, and is counted as unresolved rather than connected to a guess.

**AND A SEVENTH KIND: THE SAME POINTER QUESTION, ASKED WITH A CONTEXT AND WITH A SCOPE.**
The pointer analysis above answers *"which objects can this pointer point to?"* over the whole
program, with every calling context merged into one answer. The deck that defines the analysis
names that merging as a **choice**, not a fact: `Pointer Analysis` (`8_PTA.pdf`, Tian Tan,
Nanjing University,
2021) p.34 prints the **Key Factors** table, and one of its four rows is *Context sensitivity —
"how to model calling contexts?" — Context-sensitive | Context-insensitive*; p.49-53 develops
the two readings and p.53 marks the merged one *"We start with this"*. A fourth row is *Analysis
scope — "which parts of program should be analyzed?" — Whole-program | Demand-driven*, and p.72-77
develops it. So the cells this tree left empty are **the deck's own options**, and two of them
are now built.

`src/flow/pta_ctx.mbt` is the context-sensitive reading: the analysis runs once **per (function,
context) pair**, and the context is what the call site contributes. Three abstractions are
implemented, and they are the deck's own — the follow-on lecture *Pointer Analysis — Context
Sensitivity (I)* (`11-12_PTA-CS.pdf`, p.99-115) prints the `Select` variants: **insensitive**
(`Select _,_,_ = []`, p.102 — one state per function), **call-site** (`Select(c,l,_) = [l_1..l_k]`,
p.103 — the last `k` call sites, which is k-CFA, Shivers 1991), and **object** (p.100 — the
receiver's allocation site). The **call-site label is the line number**, which is the deck's own
labelling, and `line:col` when one line carries two call sites.

**TYPE SENSITIVITY IS BUILT NOW, AND THE REASON IT WAS NOT IS STILL TRUE.** The third `Select`
variant is the receiver's *type*, and it is now implemented: the receiver's **declared** type is
readable — it is the annotation the receiver was bound with — so the variant asks a question this
tree can answer. What is still not readable is the deck's own `InType`, the type *containing* the
allocation site: `11-12_PTA-CS.pdf` p.171 is emphatic about it (*"InType(o3) = X (not Y!)"*), and
that type is the class a method's body sits in — and this tree's AST has **no method bodies**, the
parser reads past `impl`, `trait`, `struct` and `enum` declarations whole. So the variant uses the
receiver's declared type, which is the same *kind* of abstraction — a type instead of an object —
and the deck's own measurement is reproduced: three receivers of one type give **one** context
where object sensitivity gives **three** (p.174). The earlier note here said the variant was left
out because "a local's type is published nowhere this package can read"; that was true of the
*inferred* type and not of the *declared* one, and the reading is built on the declared one.

`src/flow/pta_demand.mbt` is the demand-driven reading, and it is the deck's p.76 **column**,
reproduced: the client is *call graph construction*, the site of interest is *line 5* of the
deck's own program (`z.bar()`), and the answer is `z ➝ {o4}`. The four rules are read
**backward** — which statements write this pointer, and what they read — so the analysis computes
the map of the **demanded pointers only**. Two boundaries are counted rather than hidden. A
**call's result is not a source** in this arm: an unmodelled value contributes nothing rather
than an invented object. And a demanded **parameter** does cross the call boundary, to the
caller's argument — otherwise the demand would stop at the callee's door.

**THE SCOPE CHANGES HOW MUCH IS COMPUTED, NEVER WHAT IS TRUE.** For a pointer that is demanded,
the demand-driven answer is the whole-program answer; what changes is the set of pointers
computed at all. A test requires exactly that equality, so the second reading cannot quietly
become a different analysis.

**AND IT SPEAKS NO NEW FAMILY.** Neither reading reports anything: a context and a scope are
**measurements**, and this tree's pointer analyses are library-level rather than part of the
report pipeline. The family roster is at eighteen, and this analysis added none of them.

**AND AN EIGHTH KIND: THE SAME POINTER QUESTION, ASKED WITHOUT A HEAP.** The pointer
analysis above asks *"which objects can this pointer point to?"*, and the answer is a set of
objects, and the objects have to be **named**. The storeless model does not name them. The
deck's own **Heap abstraction** row — *How to model heap memory? — Allocation-site |
Storeless* (p.34, re-printed at the head of every factor's section: p.48, p.54, p.71, and
p.78 as "Pointer Analysis in This Course") — has a second cell, and the deck cites its
definition on p.42-43: Vini Kanvar and Uday P. Khedker, *"Heap Abstractions for Static
Analysis"*, ACM Computing Surveys 2016 (the free full text is arXiv:1403.4910v5). The
deck names the cell nine times and defines it zero times; the survey is where it is
defined, and this cell reads the survey.

`src/flow/pta_storeless.mbt` is the storeless reading. The heap is a set of **access
paths** — a pointer variable followed by a sequence of field names — and the survey's
definition is exact: *"The storeless model does not explicate the memory locations or
objects corresponding to these access paths. Given V as the set of root variables and F as
the set of field variable names, the set of access paths is defined as V x F*"* (p.7). The
domain here is that set, and the rules are `pta.mbt`'s four rules carried onto it. The one
that differs is **New**: the fresh location is named by the **path rooted at the
variable**, not by an allocation site — because the survey classifies *"allocation site"*
as a *summarization* (p.11), and this cell is the model without it. A tree that named the
fresh location `o1` here would be the allocation-site model wearing the storeless model's
clothes.

**THE SUMMARIZATION IS THE SURVEY'S, AND IT IS WHAT MAKES THE MODEL FINITE.** The access-path
set is `V x F*`, so *"the number of access paths is potentially infinite and the length of
each access path is unbounded"* (p.7). The survey bounds it with a **k-limiting
predicate** — *"Is the heap location at most k indirections from a root variable?"* (p.12)
— and a self loop that *"stores spurious aliases for access paths with more than k = 2
indirections"* (p.9). This tree implements the predicate, and **counts the cut**: the
places where a path deeper than the bound was merged into its prefix. The count is of
**distinct sites** rather than of sweeps, because a fixed point applies the rules once per
sweep, so a counter would report the sweeps a cut appeared in rather than the cuts in the
program.

**AND THE ALGORITHM IS THIS TREE'S, BECAUSE THE SURVEY SAYS IT IS NOT ITS SUBJECT.** Its
abstract says so: *"our interest lies in the abstractions and not in the algorithms that
construct them"* (p.1). So this cell is the survey's model, the survey's summarization,
and this tree's four rules over them — and the survey's Figure 6 is **not** reproduced,
because a tree that reproduced it would be claiming an algorithm the survey does not give.

**THE TWO MODELS SIDE BY SIDE, MEASURED.** The same programs are read by both models and
the alias verdicts are compared pair by pair. On the deck's own p.28-29 program the two
**agree** — three pairs, three agreements, zero disagreements — because the alias question
is the same question in both vocabularies. And they **disagree** about what a variable may
reach, and the difference is a fact about the two abstractions rather than about either
implementation. On `x = new C(); x = new D(); y = x;` the allocation-site model says
`x -> {o1,o2}` and `y -> {o1,o2}` — two SITES, two objects — while the storeless model
says `x -> {x}` and `y -> {x}` — one ROOT, one path. That is the survey's own distinction
(*"Summarization using allocation sites merges heap objects that have been allocated at the
same program site"*, p.11), and it is why the two models' points-to answers are not
comparable while their alias answers are.

**AND THE BOUNDARY IS COUNTED, NOT HIDDEN.** In this rule system a value is always the
**root** of the location it names, so the deepest value sits at depth zero and the
survey's spurious alias — a pointer reaching a path below the bound — does not arise
through a pointer at all. It is visible in the relation instead, where a path deeper than
the bound is merged into its prefix. The two models' alias verdicts are compared row by row
by a test, and the row that disagrees is the one above.

**AND IT STILL SPEAKS NO NEW FAMILY.** A heap abstraction is a **measurement**, not a
report: this analysis added no family, and the storeless model is a
library-level analysis beside the other two pointer readings.
**AND A NINTH KIND: THE SAME POINTER QUESTION, ASKED OVER A POINTER FLOW GRAPH.** Every reading
above sweeps the statements of a function and joins what it learns into one map. The deck that
adds the **method-call rule** asks the same question over a **graph** instead. `9-10_PTA-FD.pdf`
(*Pointer Analysis — Flow and Dispatch*, Tian Tan, Nanjing University) p.23 prints the **pointer
flow graph**'s edge table — *New: N/A; Assign: x←y; Store: o_i.f←y; Load: y←o_i.f* — p.24-25
prints its example program

```
a = b;      ①
c.f = a;    ②
d = c;      ③
c.f = d;    ④
e = d.f;    ⑤
```

with the annotation *(o_i ∈ pts(c), o_i ∈ pts(d))*, and p.33 draws the finished picture: **five**
arrows — `b→a`, `a→o_i.f`, `c→d`, `d→o_i.f`, `o_i.f→e`. Not six: there is no store into `e`.

`src/flow/pfg.mbt` is that graph, and it is solved the deck's way: a work list of **deltas**
(`Δ = pts – pt(n)`, p.116) whose `Propagate` pushes only the difference, and a `AddEdge` that
adds `t, pts(s)` to the work list whenever a new object reaches a node (p.68, p.119). The deck's
own work-list trace is reproduced **step for step** — `b, {o1}; c, {o3}; a, {o1}; d, {o3};
o3.f, {o1}; o3.f, {o3}; e, {o1}; e, {o3}` — eight steps, on the slides that print it (p.74, p.76,
p.81, p.83, p.88, p.89, p.90). The deck's own tables come out of it:
`a -> {o1}; b -> {o1}; c -> {o3}; d -> {o3}; e -> {o1,o3}; o3.f -> {o1,o3}`.

**AND THE GRAPH IS COMPARED WITH THE READING, NOT ALONGSIDE IT.** A second implementation of a
question is a second answer to it, so the pointer-flow-graph reading is run over the same program
as `pta_run` and a test requires the two tables to be **equal**.

**AND THE SAME DECK'S INTERPROCEDURAL ALGORITHM IS BUILT, WITH THE CALL GRAPH ON THE FLY.** p.115
says *"Run together with call graph construction"*, *"Call graph forms a 'reachable world'"* and
*"Only reachable methods and statements are analyzed"*, and p.116-119 gives the pseudocode of
`Solve(main)`, `AddReachable(m)`, `ProcessCall(x, o_i)` and `AddEdge(s, t)` — the last of which is
exactly *"if s → t ∉ PFG then add s → t to PFG; if pts(s) is not empty then add t, pts(s) to
WL"*. The deck's output is **two** things (p.125): *"Points-to Relations (pt), Call Graph (CG)"*.

`src/flow/pta_inter.mbt` is that algorithm, and its headline is a **disagreement with the call
graph built separately**. On the deck's own example (`A b = new B(); b.foo(a);`, p.126-152) the
on-the-fly graph says **`main -> B::foo`** — the dispatch is on the receiver's **object** — while
the separately built call graph says **`main -> A::foo`**, because that one dispatches on the
receiver's **declared** type (deck 7's CHA, p.33-39). The deck's example is built to make that
difference visible, and it is visible. The two graphs are also required to **agree** on a program
whose only call names its callee, so the disagreement cannot spread.

**AND THE CONTEXT-SENSITIVE HEAP IS THE DECK'S OWN, MEASURED ON ITS OWN TABLE.** `11-12_PTA-CS.pdf`
p.28-30 makes the **heap** a choice as well: *"The abstract objects are also qualified by contexts
(called heap contexts)"*, *"The most common choice is to inherit contexts from the method where the
object is allocated"*, and the object's own name is `c: o_i`. p.56 prints **two** columns —
**"C.I. + C.S. heap"** and **"C.S. + C.S heap"** — and **two** conclusions: *"Context-sensitive
heap improves precision"* and *"Without C.S., C.S. heap cannot improve precision"*.

`src/flow/pta_heap_ctx.mbt` is that reading, and **both columns are reproduced row for row**. The
right column: `n1 -> {o1}`, `n2 -> {o2}`, `3:p -> {o1}`, `3:x -> {3:o8}`, `x1 -> {3:o8}`,
`4:p -> {o2}`, `4:x -> {4:o8}`, `x2 -> {4:o8}`, `n -> {o1}`, `3:o8.f -> {o1}`, `4:o8.f -> {o2}`. The
left column: `p -> {o1,o2}`, `x -> {3:o8,4:o8}`, `x1 -> {3:o8,4:o8}`, `x2 -> {3:o8,4:o8}`,
`n -> {o1,o2}`, `3:o8.f -> {o1,o2}`, `4:o8.f -> {o1,o2}`. The two conclusions are measurements
too: the context-sensitive heap takes `n` from two objects to **one** (13 pairs against 14), and
under a context-insensitive analysis it takes it **nowhere at all** — the same answer the ordinary
heap gives, which is what *"Without C.S., C.S. heap cannot improve precision"* means.

**AND THE THREE ABSTRACTIONS ARE COMPARED, NOT JUST OFFERED.** The same deck prints the three
variants' contexts side by side (p.174): *"Object-sensitivity: o3, o5, [o7]"* against
*"Type-sensitivity: [X]"*, and concludes that *"Type sensitivity is a coarser abstraction over
object sensitivity"*. `src/flow/pta_variants.mbt` is that comparison, and this tree's reading
prints the same table — `call-site: [4, 6, 8] | object: [o3, o5, o7] | type: [Y]` — and the
merging is measured where it costs something: under the type variant the two invocations of one
method are **one** state, so the parameter holds both objects and the two results are the same,
where the call-site and the object variants keep them apart.

**AND IT STILL SPEAKS NO NEW FAMILY.** A graph, a call graph built on the fly, a heap and a
context are all **measurements**, and this tree's pointer analyses are library-level rather than
part of the report pipeline. The family roster is at eighteen, and this analysis added none of them.

### And a tainted datum is an object, so taint IS the pointer analysis

`src/flow/taint.mbt` is the **security** lecture's fourth chapter — *Static Analysis for
Security* (Tian Tan, Nanjing University), p.64-85 — and p.70 is the slide that decides how it
is built: **"Taint and Pointer Analysis, Together"**. The deck treats tainted data as
**objects** (p.71-72: *"Tainted data t_i, t_j ∈ T ⊂ O"*), treats a source as an **allocation
site**, and propagates taint with the pointer analysis's **own** rules (p.75). So this is
**not a second pointer analysis**: it is the pointer analysis this tree already has
(`src/flow/pta.mbt`), with **one extra object per source call site**.

**THE SEED IS THE WHOLE DIFFERENCE.** The deck's source rule (p.74) reads
`m ∈ Sources ⇒ t_l ∈ pt(r)`, and the deck's worked example prints the tainted datum **inside**
the points-to set of the variable the source call was bound to — `pw → o11, t3`. So a tainted
datum is an object named after its **call site** (`t3`, the way an allocation site is named
`o3`), and it starts in the points-to set of the call's result. Everything after that is the
deck's four rules — New, Assign, Store, Load — which `pta.mbt` already implements **in one
place**, and which this file *calls* rather than copies.

**THE OUTPUT IS THE DECK'S TRIPLE.** p.73 defines it — *"(i, j, k) = tainted data from call
site i may flow to the k-th argument of call site j"* — and p.84 prints the deck's own answer
to its own example: **`TaintFlows: { ⟨3, 7, 0⟩ }`**. The example is reproduced **line for
line**: the allocation on line 2 is `o2`, the source call on line 3 creates `t3`, the copy on
line 4 shares `o2`, the store on line 5 and the load on line 6 carry `t3`, and the sink on
line 7 reports the deck's own triple. `src/flow/taint_test.mbt` pins every one of those
tables.

**ONE DIFFERENCE FROM THE DECK'S TABLES, AND IT IS MEASURED.** The deck's `o11` is the object
the source call **returned** (`new String(…)` on line 11, inside `getPassword`), and this
tree's pointer analysis does not model what a call returns — so there is no `o11` here, and
`pw` points to the tainted datum **alone**. The MoonBit translation fills the field instead
of leaving it null, so `o2.f` also holds the field's initial value. The deck's **answer** —
the triple — is the same.

**THE SOURCES AND THE SINKS ARE PARAMETERS, AND THAT IS THE DECK'S OWN SHAPE.** p.73 makes
them two sets the analyst supplies: *"Sources = a set of source methods"*, *"Sinks = a set of
sink methods with sensitive arguments"*. The deck's own example uses `getPassword()` and
`log(String)` — two functions of the program under analysis, and neither one is a name any
toolchain defines. A taint analysis that carried its own list of source names would be
answering a different question, so `TaintSpec` carries the two sets and the analysis reads
them.

**AND THE BOUNDARIES ARE THE DECK'S OWN, NOT THE IMPLEMENTATION'S.** The deck itself says
(p.61-62) *"Explicit flows generally carry more information than covert channels, so we focus
on explicit flows"* — so the **implicit** flows (a branch on tainted data, a termination
channel, a timing channel, an exception channel) are out of scope **by the deck's own
decision**. The **security levels** (p.25-28) and the **noninterference** property (p.29-36)
are out of scope for a different reason: a level is a lattice element and the policy is an
order on it, while a noninterference claim is a **relational** property over two runs of the
program with different high inputs, and no may-analysis answers it. And the analysis is
**intraprocedural**, because the pointer analysis it is built on is one map per function.

**AND IN 0587 IT SPEAKS A NEW FAMILY.** The taint analysis is a **library-level** capability
in `src/flow`, like the pointer analyses above it: it computes the deck's triples and hands
them to a caller — and **0587** is the increment that gave those triples a family of their own,
`MSA-018` (`TaintFlow`). The family roster is at eighteen.

### And a tainted datum that reaches a sink is a finding

`src/pipeline/taintcheck.mbt` turns the deck's triples into **findings**, and the family is
**`MSA-018` (`TaintFlow`)** — the roster's **eighteenth**.

**THE FINDING SITS AT THE SINK.** The sink call is what the reader has to look at, so the finding
is on the sink's line and the sink's name leads the message: *the sensitive argument 0 of 'log' may
receive tainted data from 'get_password'*. The **source** is named too, because "tainted data"
without a source is not a fact about the program.

**ONE FINDING PER SINK CALL, AND THAT IS THE MERGE'S FAULT.** The pipeline collapses a family to
one finding per **line**, so a sink with two sensitive arguments would lose one of them, and two
sources reaching one sink would lose one of **them**. So the flows are **grouped** by the sink call
and the message names every argument and every source the group covers — the merge then has nothing
to collapse, and the report keeps the whole fact.

**THE PREDICATE IS CHECKABLE**, and this is the first predicate in this tree whose claim is about a
**flow** rather than about a place:

```
taint_reaches_sink(sink=log, source=get_password, arg=0, line=7, col=3)
```

The **sink** is the subject, the **source** is where the data came from, and the **argument** is the
deck's own `k`. The values are the message's own words, so a checker splits them the way the message
reads.

**THE SPECIFICATION IS THE READER'S, AND IT IS A PARAMETER.** `--taint-source <fn>` names a function
whose result is tainted data; `--taint-sink <fn>:<idx>` names a sink and the index of its sensitive
argument — `log:0` is the deck's own `<log(String), 0>`. Both are repeatable, a malformed one is
**refused** rather than dropped (a dropped sink would scan the program and report nothing, which
looks exactly like a clean program), and with no specification the family says nothing — the same
honest default as every other analysis in this tree.

**AND THE THREE GUARDS ARE THE PIPELINE'S.** A file the frontend did not read whole, a function
holding a region it did not read, and a function whose control-flow graph **lost a statement** are
all functions this family does not analyse — the third one because the statement it lost may have
been a **sanitizer**, and a sanitizer the analysis never read is a flow the analysis believes in and
the program does not have.


### And the deck's own injection example is not reported — measured

**THE SECURITY LECTURE'S SECOND CHAPTER IS *CONFIDENTIALITY AND INTEGRITY*, AND ITS INTEGRITY SLIDE
CARRIES THE SHAPE THE CHAPTER IS ABOUT:**

```
x = readInput();   // untrusted
cmd = "..." + x;
execute(cmd);      // critical (trusted)
```

and p.41 names what that shape is: **"Injection errors (#1 cause of vulnerabilities in 2013-2019)"** —
command injection, SQL injection, XSS.

**THE TOOL DOES NOT REPORT IT, IN BOTH OF ITS SYNTACTIC FORMS, AND THE REASON IS THE POINTER
ANALYSIS'S AND NOT A GAP IN THE TAINT RULES.** A concatenation and an interpolated string are both
values the pointer analysis does **not** model — `src/flow/pta.mbt` says it in its own words:
*"ANYTHING ELSE IS EMPTY, AND THAT IS THE SOUND DIRECTION"* — so the tainted datum never enters the
derived variable's points-to set, and the deck's own sink rule has nothing to find.

**MEASURED, AND THE MEASUREMENT IS THREE ROWS.** The deck's program with the concatenation reports
**nothing**; the same program with the interpolation reports **nothing**; the same program with the
derived value **removed** reports the flow. The three differ by one expression, and the two that
report nothing are pinned by tests.

**AND IT IS ALSO THE DECK'S OWN RULE TABLE.** p.75 lists four rules — New, Assign, Store, Load — and
none of them is a rule for a derived value. The taint analysis is the pointer analysis plus a seed,
so it answers exactly what those four rules answer.

**THE SHAPE IS NOT RARE.** MEASURED over the seven pinned corpora: **827** sites carry a call's result
into a string — **314** concatenations and **513** interpolations. That is a **syntactic** count and
not a flow count: most of those sites are benign (a log line is not an injection), and what the count
says is that the boundary is not theoretical.

**AND THE ONE RULE THAT WOULD CLOSE IT IS NAMED, because a boundary with a named cause is a decision
and a boundary without one is an excuse.** It is *"a value derived from a tainted datum carries the
taint"*, and it belongs to the **taint layer** and not to the pointer analysis — which would make the
taint analysis **one rule wider** than the deck's four. That is a change to what this tool claims, so
it is written down here and not made.


### And the deck's own rules can be READ, and then RUN

The `Datalog-Based Program Analysis` lecture (`14_Datalog.pdf`, Tian Tan, Nanjing University,
93 pages) spends its
first chapter on a complaint: the same pointer analysis has an **imperative** form (p.9-14 — a
worklist, a `Solve(main)` loop, and "so many implementation details") and a **declarative** form
(p.15-16 — seven rules, "Succinct / Readable (logic-based specification) / Easy to implement"). The
lecture's claim is not that Datalog is a nicer language. It is that **the rules are the
specification**, and a specification you can read is a specification you can check.

`src/flow/datalog.mbt` and `src/flow/datalog_parse.mbt` are that engine and that reader, and they
exist to make the claim **testable**: the deck's own rules are written out, read back, run, and
compared with the answer this tree's own pointer analysis already gives.

**THE READER READS THE DECK'S SYNTAX, AND IT READS IT CONTEXTUALLY.** The deck's syntax cannot
distinguish a variable from a value — its facts are `New(b, o1)` (p.65) and its rules are
`VarPointsTo(x, o) <- New(x, o).` (p.70), and in **both** the object name and the variable are bare
identifiers. So the distinction is **contextual**: a **fact**'s bare terms are values, a **rule**'s
bare terms are variables. A reader that guessed would be wrong on one of the two, and the deck
gives both forms on purpose.

**THE DECK'S MULTI-HEAD SHORTHAND IS THREE RULES WITH ONE BODY.** p.15 writes one head over three
lines with a single body, and the reader expands it, because that is what it means:

```
VarPointsTo(x, o) <- New(x, o).        // one head
FieldPointsTo(f, o) <- New(f, o).      // the deck's p.15 form: three heads,
FieldPointsTo(f, o) <- HeapStore(f, o). // one body -- read as THREE rules
```

**THE TWO REFUSALS ARE REFUSALS, NOT SILENT DROPS.** A rule that is **unsafe** — every variable
must appear in at least one non-negated relational atom (p.51-53) — is refused, and so is a program
where **recursion and negation are not separated** (p.54-56). Both produce a diagnostic that names
the rule, and the solve returns *not ok* rather than an empty answer. An empty answer would look
exactly like a program whose answer is empty, and that is the difference between "the tool says
unknown" and "the tool says nothing".

**THE NUMBERS ARE NUMBERS AND NOT TEXT.** `age >= 18` has to put **9** below **18**, and a text
comparison puts `"9"` *above* `"18"` because `'9'` is the larger character. The deck's own example
carries a ninth grader in it (p.29, p.32), and that example is a pinned row.

**AND THE ENGINE IS MONOTONE AND TERMINATES** (p.57-59), because facts are never deleted and the
possible values of an IDB predicate are finite — the second half of that argument being exactly the
rule-safety property above. The recursion's round count is **measured**, not asserted: the pinned
row reads the number of rounds the fixpoint took.

**AND THE ROUND TRIP IS THE POINT.** The reader writes the rules back out in the deck's own
notation, and the deck's own pointer-analysis rules (p.70) and taint rules (p.91) come back
**verbatim** — read from text, in the deck's order, in the deck's words. A specification that
cannot be read back is not a specification this tool can check.

**WHAT THIS IS NOT.** It is **not** a second pointer analysis. The Datalog engine computes the
deck's rules; the pointer analysis this tree already has computes the same answer over the same
program, and the two are compared against each other in the increment that follows. One fact, one
place in the tree — so the Datalog engine is the deck's *specification*, and `src/flow/pta.mbt` is
the tree's *implementation*, and the question the deck raises is which of them the two agree on.

### And the deck's own rules can be RUN, and compared with the answer this tree already gives

The lecture's claim (p.15-16) is not that Datalog is faster than a worklist. It is that **the
rules are the specification** — "Succinct / Readable (logic-based specification) / Easy to
implement" — and a specification you can read is one you can check. `src/flow/datalog_pointer.mbt`
makes that claim **testable**: the deck's own four rules (p.70) are written out, the program's
statements become the deck's own EDB relations, the rules are **run**, and the answer is
**compared** with the one `pta_run` gives on the same program.

**THE RULES ARE TEXT, NOT CODE.** A rule built in code is the imperative form wearing a hat; a
rule that is text can be read, printed, and compared with the slide. The four rules are in the
deck's own order and its own words, and they come back out verbatim.

**AND THE COMPARISON CAN DISAGREE, AND WHEN IT DOES THE DIFFERENCE IS NAMED.** A comparison
that can only say "yes" is not a comparison. On the deck's p.28-29 program — `p = new C();
q = p; x = new X(); y = new Y();` — the two readings **agree exactly** on the pointer relation:
`p → {o1}`, `q → {o1}`, `x → {o3}`, `y → {o4}`, four tuples each.

**AND ON A FIELD THAT HOLDS A STRING THEY DISAGREE, AND THE CAUSE IS THE SPECIFICATIONS' OWN.**
`pta_run`'s field cell holds the **value** a field contains — p.59 puts `"x"` inside a points-to
set — while the deck's `FieldPointsTo` holds the **pointers** a field points at, and a string is
not a pointer. So on the deck's own p.57 program the deck's field relation is empty where
`pta_run`'s holds `{"x"}`, and the two readings disagree about the reader of that field too. That
is a fact about the two *specifications* and not an error in either, and it is reported rather
than normalised away.

**AND THE COMPARISON PRINTS BOTH ANSWERS**, side by side, because a comparison that prints a
boolean is a thing a reader has to take on trust.

### And the deck's taint rules can be RUN, and they found a bug in this engine

The lecture's third thing to understand (p.93) is taint analysis via Datalog, and its
chapter is two pages (p.90-91): the EDB relations `Source(m)`, `Sink(m, i)` and
`Taint(l, t)`, the IDB relation `TaintFlow(sr, sn, i)`, and two rules. `src/flow/datalog_taint.mbt`
runs them and compares the answer with the one `taint_analyze` gives on the same program.

**THE DECK'S TRIPLE IS FOUND, ON THE DECK'S OWN PROGRAM.** The security deck's seven-statement
example (p.77) prints `TaintFlows: { <3, 7, 0> }` on p.84 — the source call site, the sink call
site, the argument index — and the Datalog reading derives exactly that triple, and the two
readings **agree**.

**AND RUNNING THE DECK'S OWN RULES FOUND A REAL BUG IN THIS TOOL'S ENGINE.** The strata-ordering
loop counted **predicates** against the number of **groups** — two different things — so on a
program with three IDB predicates in two strata it exited with the second stratum **never
evaluated**. The `TaintFlow` rule was never run.

**THE SYMPTOM WAS INVISIBLE FROM THE ANSWER**, and that is what made it worth measuring rather
than guessing: the program derived `VarPointsTo(s, t3)` — the tainted datum *did* reach the
sink's argument — and derived **no flow** from it. The relation was right, the rule was right, the
program was right; what was missing was a stratum. The fix counts groups, and the row that
pins it **is proven to fire**: the bug was reintroduced, the suite went red on three rows, and
the file was restored byte for byte.

**AND THE ENGINE NOW EXPOSES ITS EVALUATION ORDER**, because the order is a property of the
program and not of the solver's internals — and a caller that cannot see it cannot explain a
rule that derived nothing.

### And the deck's first chapter is COUNTED, and its last two pages are CHECKED

The lecture's first chapter is the motivation (p.5-16): it prints the imperative `Solve(main)` with a
worklist and asks the questions the imperative form leaves open. The list **grows** across p.10, p.11
and p.12, and by p.12 it carries **five** bullets — the fifth, "How to connect PFG nodes and
pointers?", is on p.12 and is easy to miss.

**THE ANSWER IS NOT "the declarative form has no implementation details".** Measured against this
tool's own engine, the declarative form closes **four** of the deck's five questions and leaves
**one** — the points-to set's representation, which is exactly the deck's own "Hash set or bit
vector?". This tool's engine stores tuples in a **hash set** of length-prefixed tuple keys, so the
deck's question is answered here by naming which of the deck's two options this tree takes.

**AND THE ORDER QUESTION SURVIVES.** "Which worklist entry should be processed first?" becomes
"which stratum first" — the same question in a different hat, and the deck's own p.92 cons line names
it: "Cannot fully control performance". This tree has already paid for it: the strata-ordering bug
that 0594 found is that cost.

**p.92 IS THREE PROS AND TWO CONS, AND ONE PRO IS NOT TRUE HERE.** "Benefit from off-the-shelf
optimized Datalog engines" does not hold for this tree, which has its own engine — and the price is
measured, not asserted: the strata-ordering bug of 0594 is what owning an engine costs. It is
reported as not true rather than left implied by silence.

**AND "Restricted expressiveness" IS TWO REFUSALS HERE, not a vague limit** — an unsafe rule (p.53)
and a recursion-and-negation conflict (p.56) are both refused, and a refusal says which rule and
why.

**p.93 IS THREE THINGS, AND EACH NAMES THE INCREMENT THAT DID IT**: the language (0592), the pointer
analysis via Datalog (0593) and the taint analysis via Datalog (0594).

### And the supergraph is MEASURED, and the exploded supergraph is BUILT

The lecture is `15_IFDS.pdf` -- *CFL-Reachability and IFDS* (Yue Li, Nanjing University, 2021)
— 174 pages, six chapters on p.3, and p.174 names the three things to understand: *Understand
CFL-Reachability*,
*Understand the basic idea of IFDS*, *Understand what problems can be solved by IFDS*.
`src/flow/ifds.mbt` covers its **chapter 4** (p.58-81, the supergraph and the flow functions) and
the first half of its **chapter 5** (p.83-97, the exploded supergraph and the glue edge).

**THE DECK'S RECIPE HAS THREE STEPS, AND THIS INCREMENT IS THE FIRST TWO.** p.52-56 gives them:
build a supergraph `G*` and define flow functions over its edges; transform the flow functions
into **representation relations** (graphs) to get the **exploded supergraph** `G#`; then solve the
problem as graph reachability by running **tabulation** on `G#`. The theorem that makes the third
step an answer is on p.55-56: a fact `d` is in `MRPn` **iff** there is a **realizable path** in
`G#` from `⟨smain, 0⟩` to `⟨n, d⟩`. Tabulation is 0598.

**CHAPTER 4 WAS ALREADY HERE, SO 0597 MEASURES IT INSTEAD OF WRITING A SECOND COPY.** The deck's
p.63-65 gives the supergraph **three edges for every procedure call** — an intraprocedural
call-to-return-site edge, an interprocedural call-to-start edge, and an interprocedural
exit-to-return-site edge — and `src/flow/icfg.mbt` builds exactly those three
(`EdgeKind::CallToReturn`, `EdgeKind::Call`, `EdgeKind::Ret`). A second supergraph would have been
a second implementation of a concept the tree already owns, so the increment **counts** the three
edges: `ifds_supergraph_text` reports the call sites and the edge kinds, and
`ifds_supergraph_calls` says, per call site, which of the two edges that leave the call node are
there.

**AND THE THIRD EDGE IS COUNTED SEPARATELY, because it does not leave the call node.** The deck's
exit-to-return-site edge leaves the **callee's exit** and arrives at the **caller's return site**
(p.65), so a reader who looks for it on the call node will not find it — `ifds_supergraph_returns`
reports it where it is, one line per edge.

**WHAT WAS ABSENT IS THE REPRESENTATION RELATION, and it is the deck's step 2.** p.53 says the
exploded supergraph is built "by transforming flow functions to representation relations
(graphs)", and there was no way to ask this tree for a flow function as a graph.

**AND IT IS THE DECK'S OWN FORMULA, p.84, NOT A REWORDING OF IT:**

```
Rf = { (0,0) } U { (0,y) | y in f(EMPTY) } U { (x,y) | y not in f(EMPTY) and y in f({x}) }
```

Read off this tree's own transfer `OUT[B] = gen_B U (IN[B] - kill_B)` (p.48), that formula is
three kinds of pair:

```
(0 -> 0)   at every node                                  THE GLUE EDGE
(0 -> g)   for every g in gen[B]                          the constant part
(x -> x)   for every x not in gen[B] and not in kill[B]    the fact survives
```

and `ifds_reach_rel` gets them by **calling** `reaching_gen` and `reaching_kill` rather than
re-implementing them, so the exploded supergraph and the traditional analysis are **two readings
of the same transfer functions** — which is what makes the next increment's comparison mean
something.

**THE THIRD CLAUSE EXCLUDES THE GENERATED FACTS, and that is the formula and not a choice.** The
deck's own examples on p.85-87 show it: `lambda S.{a}` has the edges `0->0`, `0->a` and `b->b` —
and **not** `a->a`. A fact the node generates is already carried by the constant part, so it gets
no `(x,x)` pair of its own.

**THE GLUE EDGE IS THE RELATION'S FIRST CLAUSE, and so the switch is on the relation.** p.84's
`{ (0,0) }` is a clause of `Rf` and not an edge added beside it, so `ifds_reach_rel` takes the
glue edge as a **parameter** — a measurement that cannot turn the thing off cannot measure it, and
the deck's p.92-96 is a claim *about* that clause.

**AND WITHOUT IT, THE SUPERGRAPH IS DISCONNECTED — which is the deck's own failure case.** MEASURED
on the five-node graph the rows pin, **no edge leaves the start pair** `⟨entry, 0⟩`: the exploded
supergraph is not subtly wrong, it is **disconnected**. That is p.95's own sentence — without the
edge `0->0` "the representation relation for each edge cannot be connected or 'pasted' together …
Thus IFDS cannot produce correct solutions via such disconnected representation relations."

**AND WITH IT, THE SUPERGRAPH CONNECTS, AND THE FACTS IT REACHES ARE THE ANALYSIS'S OWN.** The
`(0,0)` pair is the edge that carries the zero fact from one relation to the next, so the next
relation's constant part has a zero fact to fire on — that is what "pasted together" means.
MEASURED, the reachable facts at each node are exactly the traditional analysis's `IN[n]`: `x@1`
at node 2, `x@2` at nodes 3 and 4, `y@3` at node 4, and `x@1` **not** at node 3, because node 2
kills it.

**AND THE COUNT IS THE ARITHMETIC, WRITTEN OUT.** Each node contributes its relation's pairs times
its successors, so the exploded supergraph has **14** edges with the glue and **10** without it:
node 0 contributes 4, node 1 contributes 3, node 2 contributes 3, node 3 contributes 4 and node 4
contributes 0 — and the exit node has no successor, so the glue edge appears **four** times, not
five.

**ELEVEN ROWS, EACH NAMING ITS SLIDE**, in `src/flow/ifds_test.mbt` — p.58-65 for the three edges,
p.46 and p.48 for the relation and the kill, p.84 for the formula, p.95 and p.96 for the glue
edge, and p.53 for the edges of the exploded graph.

**AND SIX OF THE INCREMENT'S OWN DEFECTS WERE FOUND BY MEASUREMENT AND FIXED, NOT PINNED.** The
biggest one: the first draft kept `(0,0)` **out** of the relation and put a `0->0` **self-loop** at
every node instead — and a self-loop carries the zero fact *nowhere*, so the exploded supergraph
it built reached nothing at all. MEASURED, the reachable set was one pair. The deck's own p.84
formula puts the `(0,0)` **inside** the relation, and the code now does what the formula says.
The other five: `with` is a reserved keyword; an unused `facts` binding; the per-call edge list
used a space separator while `"CallToReturn"` **contains** the substring `"Ret"`, so a test for
`"Ret"` matched the wrong edge without looking wrong; two `if` expressions used as **values** put
the self-scan's `if expression` row at 102 instead of 100; and one row's expectation was a guess
rather than a measurement. A false positive is fixed and never pinned.

### And the TABULATION is RUN, and it agrees with the analysis this tree already has

The lecture's third step (p.52-56) is the one that turns the exploded supergraph into an
answer: *"Q can be solved as graph reachability problems (find out MRP solutions) via applying
Tabulation algorithm on G#"*. p.139-140 says what the algorithm does — *"Given an exploded
supergraph G#, Tabulation algorithm determines the MRP solution by finding out all realizable
paths starting from ⟨smain, 0⟩"* — and p.141 prints its cost: **O(E·D³)**.

`src/flow/ifds_tab.mbt` is that tabulation, and it is the **intraprocedural** one: the deck
itself says on p.142-143 that it does not cover the whole algorithm.

**AND THE MEASUREMENT IS THAT IT REPRODUCES THE ANALYSIS THIS TREE ALREADY COMPUTES.**
`reaching_out` / `reaching_in` are the traditional reaching-definitions analysis, and they solve a
fixed-point equation over sets; the tabulation **walks a graph**. The two are **two readings of
the same transfer functions**, so they have to agree — node by node, fact by fact. MEASURED, they
do: `IN[2]` = `{x@1}`, `IN[3]` = `{x@2}`, `IN[4]` = `{x@2, y@3}`, and `x@1` is **not** at node 3,
because node 2 kills it.

**AND THE GLUE EDGE'S EFFECT IS A DIFFERENCE IN THE ANSWER, which is the deck's own claim.**
Without the `(0,0)` clause the tabulation's answer is **empty**: the start node carries the zero
fact and nothing else, and every other node carries **nothing at all** — not even the zero fact.
The traditional analysis, on the same graph, finds three definitions. So p.95's sentence is
measured rather than quoted: *"Thus IFDS cannot produce correct solutions via such disconnected
representation relations."*

**AND THE DECK'S OWN BOUND IS PRINTED BESIDE THE MEASURED WORK**, with the coverage next to it:
E = 14 edges, D = 4 facts (three definitions and the zero fact), so the bound is 14 · 4³ =
**896**, and the walk followed **8** of the fourteen edges. The six it did not follow all tell
one story: their source pair was never reached — three of them leave the entry node with a
definition as their source, and no definition reaches the entry, because the walk starts at the
entry's zero fact.

**FIVE ROWS, EACH NAMING ITS SLIDE**, in `src/flow/ifds_tab_test.mbt` — p.139-140 for the
tabulation and the comparison, p.92-96 for the empty answer, p.141 for the bound, p.140 for the
readable rendering.

**AND THE INCREMENT'S OWN ARITHMETIC WAS CORRECTED BY MEASUREMENT**: the first draft of the work
row said the walk followed **ten** edges, and the measurement says **eight**.

### And the DISTRIBUTIVITY BOUNDARY is MEASURED, on the two analyses this tree already has

The lecture's **chapter 6** (p.155-172) is "Understanding the Distributivity of IFDS", and it asks
two questions on p.156-157: *"Can we do constant propagation using IFDS?"* and *"Can we do pointer
analysis using IFDS?"*

**AND THE TEST IS THE DECK'S OWN ALGEBRA, p.158: `F(x ^ y) = F(x) ^ F(y)`.** So the question is not
"does the transfer read two names" but "is the output the join of the outputs each fact produces
alone" — and `src/flow/ifds_distrib.mbt` measures exactly that, on **this tree's own** constant
propagation (`cprop.mbt`) and pointer analysis (`pta.mbt`).

**THE DECK'S RULE, p.162, verbatim:**

> Given a statement S, besides S itself, if we need to consider multiple input data facts to create
> correct outputs, then the analysis is not distributive and should not be expressed in IFDS.

**AND THE DECK'S OWN EXAMPLE IS NOT DISTRIBUTIVE — MEASURED.** `z = x + y` with `x=2`, `y=3`: the
value `z` defines is **5**, and the join of the values the two facts produce alone is **⊥**. The
report reads `reads=2 z:all=5 one=⊥ distributes=false`.

**AND `⊥` AND NOT `NAC`, and that is worth saying.** With only `x` known, `x + y` is not "not a
constant" — it is "nothing has been computed yet", and `⊥` absorbs. The two are different answers.

**AND THE DECK'S OWN HARDER QUESTION, p.164, HAS AN ANSWER.** *"think about whether we could do
linear constant propagation, e.g., y = 2x + 3, or copy constant propagation, e.g., x = 2, y = x,
using IFDS-style analysis?"* **BOTH CAN**, and the measurement is why: each of those statements
reads **one** fact, so the output with that fact alone *is* the output — `reads=1 y:all=9 one=9
distributes=true` for the linear one.

**AND THE POINTER-ANALYSIS HALF IS THE DECK'S CONCLUSION, p.172, AS AN EXECUTABLE QUESTION.** The
deck says that to obtain alias information in IFDS "we need to consider multiple input data facts,
x and y". MEASURED on the deck's own program (`x = new T; y = x; x.f = x; z = y.f`), the relation
`alias(x,y)` holds on the whole state and on **no** one-fact state: `alias(x,y)=true facts=4
one=false distributes=false`.

**AND THE CONTROL IS IN THE SAME ROW, because a test that only ever says "false" is not measuring
the question.** `alias(x,x)` **is** a one-fact fact, and the same function says so on the same
state: `alias(x,x)=true facts=4 one=true distributes=true`.

**AND THE ANSWER AT `z` TRACKS THE ALIAS RELATION.** Change **one line** of the deck's program —
`y = x` becomes `y = new U` — and `z` points to **nothing** instead of to the new object, while
`alias(x,y)` goes from true to false. That is the deck's p.171 sentence measured: the output is
right exactly when the relation holds, and the relation is a fact about **two** variables.

**AND THE LOAD ITSELF NEEDS TWO FACTS, which is p.171's sentence in the deck's own terms.** The
load `z = y.f` produces `{o1}` on the whole state and `{}` from any one fact, so the join of the
one-fact outputs is not the output: `load(y.f)={o1} facts=4 one={} distributes=false`.

**EIGHT ROWS, EACH NAMING ITS SLIDE**, in `src/flow/ifds_distrib_test.mbt` — p.158-163 for the
deck's example, p.164 for its own harder question, p.162 for the rule's boundary, and p.165-172
for the pointer program.

**AND THIS IS NOT THE TREE'S "CONFLUENCE" ROW.** `cprop_intra_test.mbt` pins the *other* deck's
confluence — `F(X meet Y) != F(X) meet F(Y)`, over the **lattice's** meet, which is a statement
about the lattice. What is measured here is the distributivity over the **data facts**, which is a
statement about the transfer. Two questions, two rows, and neither borrows the other's name.

### And CFL-REACHABILITY is EXECUTED, on this tree's own supergraph

The lecture's **p.24-42** is "CFL-Reachability", and p.174 names *Understand CFL-Reachability* as
one of the three things the lecture is about.

**AND THE DECK'S DEFINITION, p.24, verbatim:**

> A path is considered to connect two nodes A and B, or B is reachable from A, only if the
> concatenation of the labels on the edges of the path is a word in a specified context-free
> language.

**AND THE DECK'S LABELLING, p.27, verbatim:**

> Every right parenthesis ")i" is balanced by a preceding left parenthesis "(i", but the converse
> needs not hold. For each call site i, label its call edge "(i" and return edge ")i". Label all
> other edges with symbol "e"

**AND `src/flow/cfl.mbt` IS THAT RULE, APPLIED TO THE EDGES THIS TREE ALREADY HAS.** The call
edges are `(i`, the return edges `)i`, everything else `e` — and the `i` is the index into the
graph's own call-site list, so an edge and its partner carry the same number because they come from
the same place.

**AND THE RECOGNISER IS THE GRAMMAR, p.34-38, READ LEFT TO RIGHT.** The deck's language has
`realizable` and `matched`; the recogniser keeps a stack of unmatched opening parentheses and
rejects a `)i` that does not close the innermost one. The deck's own examples decide it: p.29's
path `(1 (2 e )2 )1 (3` is realizable although it is **not balanced** — that is p.27's "the
converse needs not hold" — p.39's own derivation `e e (1 (2 e e e )2 )1 (3 (4 e` is realizable
for the same reason, p.41's `e(1eee)1e` is in the language, and p.42's `e(1eee)1e(2eee)1` is
not, because its final `)1` closes the `(2` that is still open.

**AND THE MEASUREMENT IS ON THE TREE'S OWN SUPERGRAPH, AND IT IS NOT ZERO.** A function called from
two places has **one** value exit and **two** return edges, so the graph holds a path that enters
the callee through one call and leaves through the other's return edge. MEASURED, on a
three-function program, the witness word is `e (2 e (0 e )1`: the path takes `caller` through call
site 2 and `leaf` through call site 0, and leaves through call site 1's return edge — and the
stack's top is site 0, so the `)1` closes the wrong parenthesis.

**AND THE COST OF THE DEFINITION IS COUNTED IN PAIRS, because p.24 speaks about PAIRS.** The
graph's own connections are **82**; the language keeps **57**; **25** are dropped. Every one of
them is a connection that exists in the graph and is not a call sequence.

**AND THIS IS WHERE 0599 AND 0600 MEET.** The tree's supergraph is the **distributive** one — it
has the call-to-return edge, which is what distributivity buys — and the CFL formulation does not
need that edge. The price of having it is visible here: the supergraph holds paths that are not
call sequences, and the CFL definition is what excludes them.

**EIGHT ROWS, EACH NAMING ITS SLIDE**, in `src/flow/cfl_test.mbt` — p.29 and p.27 for the
recogniser, p.39, p.41 and p.42 for the three membership rows, p.27 for the labelling of the tree's
own graph, and p.24 for the witness and the pair counts.

### And this analyzer says whether it is SOUND, SOUNDY, or UNSOUND

The lecture is `16_Soundiness.pdf` -- *Soundiness* (Yue Li and Tian Tan, Nanjing University,
2021 Fall), and its p.14
gives three verdicts — and the difference between them is the **cause** of a gap, not its size:

> A soundy analysis aims to capture all dynamic behaviors with certain hard language features
> unsoundly handled within reason
> A sound analysis requires to capture all dynamic behaviors
> An unsound analysis deliberately ignores certain behaviors in its design for better
> efficiency, precision or accessibility

**AND THE VERDICT IS DERIVED, NOT ASSERTED.** Each family declares its **exclusions** with the
cause of each, and the verdict is computed from those causes — so a verdict cannot drift from the
contract it summarises. A family with no exclusion is **sound**; a family whose exclusions are
all caused by a hard language feature the analyzer cannot model is **soundy**; a family with even
**one** deliberate exclusion is **unsound**, however many hard features it also has.

**MEASURED over the eighteen families**, and the counts are derived from the source by
`check_family_roster.ps1` and pinned in `_verify/release.ps1`:

    sound=0  soundy=15  unsound=3

**AND THE THREE DELIBERATE TREATMENTS ARE NAMED**, because the lecture's p.10 is the complaint
this answers — *"Treatments to hard language features are usually omitted or only mentioned in an
off-hand manner in some impl/eval parts in papers"*, and *"for experts, it is still hard for them
to interpret the analysis results (how sound, fast, precise is the analysis) without a clear
explanation about how they treat those important and hard language features"*:

| the exclusion | the family | what the analyzer chose not to do |
|---|---|---|
| `X-ARG-TYPE-NAMED-ARITY` | MSA-007 ArgTypeMismatch | the arity of a **named-call** is not checked — a deliberate leniency, kept because the alternative produced false positives |
| `X-OP-PIPE-EXEMPT` | MSA-008 OperatorMismatch | the operands of the **pipe operator** and of regex-match are exempt |
| `X-NOSEC-REALITY` | MSA-012 StaleNosec | the finding a `// nosec` silenced is **removed**, and whether it was real is never re-checked |

**AND `--explain` PRINTS IT**, per family and over the whole roster: the verdict, and every
exclusion with its cause. So the answer to *"how sound is this tool?"* is a command, not a
paragraph in a paper.

**AND THE ANALYSIS AS A WHOLE IS `unsound`** — the deck's p.6 answer, measured rather than
quoted: *"Can we achieve a fully sound analysis for real-world programs?"* No, and the count
that says it is **three families out of eighteen**, each for a named reason.

### And the cross-file signatures it used to throw away are read now

The same lecture's **second** chapter is *Hard Language Feature: Java Reflection*, and its
p.32 names the problem in one sentence:

> Problem: Reflection targets cannot be resolved if the string values are statically unknown

and p.35 names the answer:

> When string arguments cannot be resolved statically, infer the reflective targets at their
> usage points!

**A `.mbti` IS ANOTHER PACKAGE'S INTERFACE**, and this analyzer read it to learn which names
exist across the package boundary. What it did **not** keep was the **parameter list**. The
line

    pub fn action_mask_to_action_vec(UInt) -> Array[Action]

says exactly how many arguments the callee takes and what their types are — and the reader
parsed that list and then dropped it, keeping only the *set* of type names the whole line
mentions, which cannot say which parameter has which type.

**THE SENTENCE THAT DROPPED IT WAS WRONG**, and it was written down as a fact in the source:
*"a `.mbti` gives us the NAME, never the parameter list"*. The interface gives the parameter
list. `src/core/iface_sig.mbt` holds it now, `src/moonfiles/moonfiles.mbt` keeps it, and the
lens asks the table whether the callee it could not check has a **target whose shape is
known**.

**MEASURED over the eight trees**, and the first number is the point of the increment — the
target was resolvable all along:

| the deck's p.40 pair | count |
|---|---|
| cross-file calls whose callee the `.mbti` declares a signature for | **2,943** |
| of those, the ones whose declared arity agrees with the argument count of the call | **2,282** |

**AND THE 661 THAT DISAGREE ARE NOT A BUG IN THE ARITHMETIC — THEY ARE A WARNING ABOUT THE
TABLE.** The interface table is **flat**: every `.mbti` under `.repos` is merged into one
table, and a `.mbti` declares its names unqualified, so a name declared in one package can
match a call in another. Measured: `moonbit_image` declares **no** `.mbti` of its own, and
**73 of its 74** targets disagree; every corpus that has calls declared at all agrees on
between **63.6%** (`async`) and **82.6%** (`moonbit_core`) of them — `proton` 80.4%,
`moonbit_labeler` 78.2%, `moui` 77.7%.

**SO THE INFERENCE IS COUNTED AND NOT ENFORCED**, and that is the deck's p.39 lesson rather
than a dodge: *"The reflective target method at line 175 must have one parameter and its
declared type must be FrameworkCommandInterpreter or its sub/supertypes"* — an inferred
target has to be constrained by its **type**, not by its **name** alone, and a name alone is
what this table has. The counters are printed by `--metrics`, and the release gate pins
both of them against the analyzer's own line.

### And the hand-modelled native surface, measured against the declared one

The same lecture's **third** chapter is *Hard Language Feature: Native Code*, and its p.57
names the practice in two lines:

> Current practice
> Manually models the critical native code

and p.58-59 give the reason it exists at all:

> For efficiency, arraycopy() is implemented in native code

p.60-61 give the **alternative** — the same behaviour written out in the high-level
language instead of modelled by hand:

> An alternative modeling
> System.arraycopy(src, sp, dest, dp, ln);
> Java
> for(int i = 0; i < ln; i++)
> dest[dp+i] = src[sp+i];

p.62 gives the analysis's own view of it, and p.63 names the newer way of reading the
truth:

> Recent work
> Identifying Java Calls in Native Code via Binary Scanning (ISSTA 2020)

**THIS TREE DOES THE FIRST THING**, and it has a number attached to it:
`src/core/builtin_methods.mbt` is a table of **1,344** `Type::method` names over **40**
built-in types, generated by `tools/gen_builtin_methods.ps1` and stamped with the
toolchain it was last read against.

**AND 0604 MEASURES IT AGAINST WHAT THE INTERFACES DECLARE** — the deck's p.60-61
alternative, applied to this tree's own question. The analyzer now reads the target's
**own** `.mbti` files — in the same walk, not a second one — and asks what they declare
about those forty types.

| the deck's p.57 question | declared | covered | missing |
|---|---|---|---|
| `moonbit_core` — the standard library | **1,155** | **1,075** | **80** |
| `async` | 10 | 0 | 10 |
| the other five corpora | 0 | 0 | 0 |
| this repository | 0 | 0 | 0 |
| **the eight trees** | **1,165** | **1,075** | **90** |

**AND THE ZEROS ARE THE MEASUREMENT, NOT A GAP IN THE MEASUREMENT.** The hand-modelled
table is the **standard library's** surface, and a user's own package declares no method
of it — so only the tree that *is* the standard library says anything about it. `async`
is the one other tree that says something: it declares ten methods of a built-in type
(`Buffer`), and the hand-written table holds none of them.

**THE 80 ARE THE FALSE-POSITIVE DIRECTION, AND THEY DO NOT FIRE TODAY.** A name the
toolchain declares and the hand-written table lacks is a false positive waiting — *if the
interfaces are not there to carry it*. MEASURED on `moonbit_core`: **0** of the 80
appear in an `undefined function` finding, because the `.mbti` files resolve them. So
the gap is a **fallback** gap, and it is the direction the deck's p.60-61 alternative
would close for good.

**AND THE OTHER DIRECTION IS 269** — the table's own names `moonbit_core` no longer
declares. That is the MISSED-REPORT direction, and it is the one the table's header says
it accepts on purpose: keeping a name the toolchain has dropped is a missed report, while
dropping a name the toolchain still has is a false positive.

**AND THE TABLE IS ONE TOOLCHAIN GENERATION BEHIND, WHICH IS MEASURED TOO — AND THE
MEASUREMENT HAS MOVED SINCE IT WAS FIRST MEASURED.** The table is stamped
`moon 0.1.20261016`; this host's toolchain is `moon 0.1.20261117`, and the core it pins
declares **1,155** with **80** missing — the same numbers the host toolchain's own core
tree measures. The pin one toolchain generation back declared **1,123** with **47**
missing, so the gap is **wider** than the table's stamp implied, and the measurement
**does** move between two toolchain generations. The earlier claim that it did not was
refuted by this increment's own measurement, and it is corrected here rather than kept.

**SO 0604 PUBLISHES THE COVERAGE AND DOES NOT REGENERATE THE TABLE.** Regenerating it
is a release that changes what the analyzer finds — the table only ever suppresses, so
every name it gains silences a report — and that belongs to a release that re-measures
the seven corpora, not to an increment that measures.

### And under the CFG there are basic blocks

`src/flow/bb.mbt` builds the **basic blocks** of a CFG and the control-flow graph over
them — the layer a CFG is normally drawn on top of. The lecture it is pinned to
(`Intermediate Representation`, `2_IR.pdf`, Nanjing University, Fall 2026) prints a worked
example
and names two questions as the executable ones: *"How to build basic blocks on top of
IR"* and *"How to construct control flow graphs on top of BBs?"*. Its twelve
instructions come with the **leaders** and the **blocks** printed, so the layer is
checked against those and not against its own output.

Two of the lecture's instructions have no MoonBit statement to come from — an
unconditional `goto` and a `return` that leaves the program — so the deck's program is
built as a graph by hand, in the shape this tree's own builder produces (nodes
allocated back to front, so the source order is exercised rather than assumed). The
same shape is then built again through `cfg_of` from real MoonBit statements, because
a layer that only works on hand-built graphs has not been shown to work.

The block graph has the **same shape** as the node graph — a count, a successor
relation, a predecessor relation — so the existing solvers run on it with no second
solver, and one of the tests runs the same reachability analysis over both graphs and
requires them to agree. The lecture's Entry and Exit are not blocks: it says of them
that they "do not correspond to executable IR", so they are carried beside the block
list. A `break` is a way out of a *loop* and not out of the *function*, and the graph
cannot tell the two kinds of `Stop` apart, so the count of statements the builder did
not convert faithfully is carried through and a caller checks it first — the way the
dead-store family does.

### And under the blocks there is the three-address code the rules are written over

`src/flow/ir.mbt` is the **three-address code** the same lecture states its rules over. It
is not a bag of instructions but a language with a grammar, and the lecture prints the
grammar: at most one operator on the right-hand side of an instruction, so `c = a + b + 3`
lowers to `t1 = a + b` then `c = t1 + 3`; at most three addresses per instruction; and
exactly three kinds of address — a **name**, a **constant**, and a **compiler-generated
temporary**. The six common forms are `x = y`, `x = uop y`, `x = y bop z`, `goto L`,
`if x goto L` and `if x rop y goto L`.

`src/flow/ir_cfg.mbt` then applies the lecture's **leader rule**, its **edge rule** and
its **Entry/Exit** to a list of those instructions — with no translation at all. The
previous layer had to translate them, because the lecture states them over 3AC and this
tree's graph is a statement graph; the translation could therefore only be trusted. Now
the two paths are compared against each other on the lecture's own program: same leaders,
same blocks, same edges, same entry, same exits. That is the same shape as the two
solvers being checked against each other.

The 3AC path produces the **same `Bb` type** the statement path produces, on purpose —
the block graph is one thing with one definition, and two structures that could disagree
about what a block is would be two definitions of "a block".

Two extensions are labelled as such rather than smuggled in: the lecture's IR has no
call form at all (which is why it writes `x = input` as a copy from an address named
`input`), and its "six common forms" do not include a `return` although its own program
ends with one.

And the lecture's own twelve instructions are **not** strictly three-address code:
`(9) c = 2a - b` has two operators on its right-hand side, and `2a` is not one of the
three address kinds. The fixture keeps the lecture's text as it is, so the blocks the
lecture prints are the blocks the code produces, and a test says so in words — a fixture
that "corrected" the example would be checking something the lecture does not print.

`src/flow/laws_test.mbt` enumerates every element of the two finite lattices and checks the
five lattice laws and the transfer's **monotonicity** — the precondition the fixed-point
theorem needs, and the one property a lattice's three closures cannot guarantee. The
points-to map lattice is checked the same way.

### And the arrow the deck prints in the footer: 3AC -> SSA

`src/flow/ssa.mbt` is the **static single assignment** form the same lecture's fifth section
defines. The lecture states its rules in three sentences — *"All assignments in SSA are to
variables with distinct names"*, *"Give each definition a fresh name"*, *"Propagate fresh name to
subsequent uses"*, *"Every variable has exactly one definition"* — and the page footer prints the
arrow it is about: `3AC -> SSA`.

The lecture's own drawing is the test. It forks `if e` to `x₀ = 0` and to `x₁ = 1`, the two meet
at one node, and that node holds `y = x + 7` — with the `x` **circled in red**, because that is
the question the page asks: *"What if a variable use is at control flow merges?"* The answer is
the merge operator the next page introduces: `x₂ = ∅(x₀,x₁)`, and *"∅(x₀,x₁) has the value x₀ if
the control flow passes through the true part of the conditional and the value x₁ otherwise"*.
`src/flow/ssa_test.mbt` turns that drawing into a program, lowers it to 3AC, and requires the
result to be the drawing **instruction for instruction**:

```
if e goto L1
goto L2
x₀ = 0
goto L3
x₁ = 1
x₂ = ∅(x₀,x₁)
y = x₂ + 7
```

Two things the lecture leaves open are settled by measurement rather than by taste. It draws a
merge node as a node with **two incoming edges** and says a phi-function "select[s] the values at
merge nodes" — but the place where two definitions of one variable meet is not that, it is the
**dominance frontier**, and `src/flow/dom.mbt` computes it. And the drawing prints `y` with no
subscript while `x` has three, so a variable with exactly one definition keeps its bare name.

**The lecture's own cost claim, measured.** The *Intermediate Representation* lecture's p.37 says *"SSA may introduce too many variables and
phi-functions"* and *"May introduce inefficiency problem when translating to machine code (due to
copy operations)"* — and neither claim carries a number. On the lecture's own twelve-instruction
program: **8** variables become **16** versions, **8** phi-functions appear, and taking them away
would need **16** copies. Over this project's own source — 262 files, 1,436 functions, 9,219
instructions of 3AC — the same measurement gives **1,171** variables becoming **2,808** versions,
**975** phi-functions and **2,408** copies. The claim is not a figure of speech.

The measurement is a mode of the scanner, `--ssa-cost`, and it prints one line:

```
SSA-COST	files=262	unreadable=0	functions=1436	converted=5	partial=1431	declined=6533	…
```

It reports its **coverage** beside the numbers, because a number without its coverage is half a
number: the files read, the functions measured, and the statements the lowering declined (6,533
of them — the 3AC layer converts the statements it understands and counts the rest). The release
gate pins the line, so the next increment that moves it has to move the pin on purpose.
## Verification

```bash
moon check --target all --deny-warn   # 0 errors, 0 warnings (js / native / wasm / wasm-gc)
moon test --deny-warn                # 1800/1800 on wasm; 1635/1635 on js and wasm-gc
moon run src/cli                     # program demo + file-kind demo + sample machine audit
```

`--deny-warn` is deliberate: without it nothing enforces the "0 warnings" claim — a warning
regression passes CI silently. CI (`.github/workflows/gate.yml`) runs `moon update`,
`moon check --deny-warn`, `moon fmt --check`, `moon test --target js --deny-warn` and
`moon build --target wasm`.

The per-target test counts differ on purpose: `src/sa` and `src/jsoncli` declare
`supported_targets = "+wasm+native"`, so the js and wasm-gc runs SKIP those two packages
rather than failing them. A test count that claims one number for every target is therefore
wrong, and the wasm number is the only one that covers the renderer and the scanner.

### The one release entry point

`moon check` and `moon test` are the floor, and this project does not rely on the floor
alone. Everything above it is in ONE script:

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File _verify\release.ps1
```

`_verify/release.ps1` runs: the harness's own self-test; `moon fmt --check`;
`moon check --deny-warn`; all three test targets; `moon build --target wasm`; **the host
contract of the artifact — the symbols a user's toolchain has to supply, checked against the
published bytes as well as the local build**; the grammar probe's own verdicts; the own-source
self-scan; **this README's own links, anchors,
versions and counts**; **and every line the shipped CLI skill file shows as the
CLI's output is a line the CLI actually prints**; **and the shipped documents agree with the toolchain about the command they tell the reader to use**; **the mutation-gate roster and a self-test that shows it can go
red**; **what the registry will actually receive, and a check that the junk stays out of
it**; **the notice labels, and a check that a scope limit is not an error**; **the frame
audit, and a check that a region silences only the bindings it could have read**; the
published-package self-scan's own self-test; the corpus comparison against the
pinned baselines; the per-function census and its control; **the behavior lens's own
table, checked against what the analyzer produces today**; and then **every mutation
gate** — 89 of them.

And these are the other stages, by the exact name each one prints — so a stage that runs
and is not named here is a stage a reader cannot find:

    moon fmt --check
    moon check --deny-warn
    moon test --target js
    moon test --target wasm
    moon test --target wasm-gc
    moon build --target wasm
    moon build --release --target wasm
    the host contract of the artifact (what a user's toolchain must supply)
    grammar probe control (its verdicts can go red)
    self-scan (own source)
    ssa cost (own source)
    README links, anchors, versions and counts
    gate roster: self-test (eleven injected defects must be caught)
    gate roster: one harness, one list, a count that matches, and every check gate accounted for
    the shared harness: the INCONCLUSIVE verdict, shown to go red
    proof contracts: no false #proof_pure
    proof contracts, shown to go red (its own self-test)
    the proof status: the documents must say what the prover says
    the proof status, shown to go red (its own self-test)
    the goal checklist: the tasks are ticked and the rules are numbered
    the goal checklist, shown to go red (its own self-test)
    the registry URLs: the documents must point at URLs that answer
    the registry URLs, shown to go red (its own self-test)
    the newest core: the tree must have been re-gated against the one the registry publishes
    package contents: the junk stays out, the evidence stays in
    notice labels: a scope limit is a notice, a defect is an error
    the family roster: one id each, contiguous, and reversible
    frame audit: a region silences the bindings it could have read, and no others
    match arms: the arms are read, the findings are true ones, and the fallback is exact
    the family sweep: every family fires, from its own fixture
    the family sweep, shown to go red (its own self-test)
    the false-positive pin: this tree has no actionable finding
    the false-positive pin, shown to go red (its own self-test)
    the blind-spot rate: the defects inside a `test` body
    the blind-spot rate, shown to go red (its own self-test)
    the published pointers: every pointer in a shipped document resolves
    the published pointers, shown to go red (its own self-test)
    the shipped CLI example: every line of it is a line the CLI prints
    the shipped CLI example, shown to go red (its own self-test)
    the toolchain claims: the shipped documents must agree with the toolchain itself
    the toolchain claims, shown to go red (its own self-test)
    published self-scan self-test
    published package self-scan
    the notice reconciliation can go red (a real defect is seen)
    corpus SUMMARY vs pinned baseline
    per-function census vs pinned baseline
    per-function census control (the files are READ by moon check)
    the behavior lens: measured against its own header
    the region suppression: what it hides, measured and pinned
    the reach of the `raise?` construct, measured and pinned
    the premises of the 0505 porting plan, measured
    the notice flood: which notices deserve a line, measured
    the three bandit transfers: measured, not asserted
    the confidence demotion: measured, not asserted
    the transfer scope: the requirements document, the three rows, and where they landed
    the release freshness: the version must still describe the source

The list is DERIVED from `_verify/release.ps1` and checked by
`_verify/check_readme_links.ps1`, so a stage added to the gate and not named here makes
that gate red rather than quietly widening what the gate does.

**AND THE SAME STAGE NOW CHECKS THE DOCUMENT'S OWN STRUCTURE.** Section 9 of
`_verify/check_readme_links.ps1` counts the NARRATIVE's chapter headings, requires every one of
them to be a `## ` heading, requires that no chapter number be used twice, and requires that no
family's boundary text repeat a sentence. That check exists because a prose defect IS a defect:
one family's boundary text once carried its paragraph **twice**, and two chapters lost their
heading and rendered as body text. Both are fixed, both are pinned now, and the gate is shown
to go red on each of them.

### What the three transfers were asked for

The confidence axis, the stable family ids and the `nosec` are not features this
project invented. They are three rows of a **requirements document that lives one
directory above this repository** — `bandit_review.md`, a review of PyCQA's
`bandit`, read at the working tree as of **2026-10-27**. That document is **not**
edited here: a requirements document edited to match the work is no longer the
requirement.

| row | what it asks for | the files that implement it |
|---|---|---|
| 1 | a per-finding **confidence** axis beside severity | `src/core/core.mbt`, `src/report/report.mbt`, `src/jsoncli/main.mbt` |
| 2 | **stable family ids** and a checked profile | `src/core/core.mbt`, `src/sa/profile.mbt` |
| 3 | **`nosec`**, including the stale-suppression warning | `src/sa/profile.mbt`, `src/sa/main.mbt` |

Row 3 landed **somewhere else** than the review predicted. The review put it in
`parser.mbt`'s skip machinery, and the parser is not involved: a suppression that
matched nothing is a fact about the **final** finding set, and a parser-level skip
runs **before** the lenses that produce that set. The reasoning, the review's own
pin for that row (which 0507 inverted, in the settle's own words), and the dated
status column are in `_verify/NARRATIVE.md` §0514.

**The map is checked, not asserted.** `_verify/check_transfer_scope.ps1` names the
document, quotes the three rows verbatim, and resolves every `file:line` of the map
in §0514 against this tree — the file exists, and the named line still carries the
named symbol. Its `-SelfTest` injects a defect into a copy of the tree for every way
this gate could stop guarding, and requires each one to be caught. **All of them
are**, and the gate prints how many there were.

The roster is **checked, not asserted**: a gate that exists on disk but is missing from
the list would never run, and a gate that does not run is indistinguishable from a gate
that passes. `_verify/check_gate_roster.ps1` compares the two rosters in **both**
directions, and its `-SelfTest` injects ten defects into a copy of `_verify` — a gate the
list does not name, a gate in the list that is not on disk, a gate off the shared harness,
a guarantee deleted from the harness, a `--filter` in the harness, a stale count in the
harness header, a moon invocation that does not name the project root, a `check_*` gate
the release gate does not run, a `check_*` gate whose `-SelfTest` switch is declared and
never used, and a `check_*` gate with neither a switch nor a stated reason — and requires
each to be caught. **All ten are.**

And the same roster now covers the **`check_*` gates**, which it did not before. A
`check_*.ps1` on disk that the release gate does not name **never runs** — it is on disk,
it is named like a gate, and a release run reports every gate green. And a `check_*.ps1`
whose `-SelfTest` switch is declared and never used is a switch that selects nothing: it
looks like the gate can be shown to go red, and it cannot. Measured on 2026-11-20:
`_verify/check_prove_contracts.ps1` declared `param([switch]$SelfTest)` and then never
mentioned `$SelfTest` again — **in the one gate whose whole subject is a red that had
never been shown**. So every `check_*` gate is now accounted for: it either carries a
**live** `-SelfTest` — declared *and* read by the body, counted over code lines only, so
that prose about the switch cannot make a dead switch look alive — or it says, in a
comment, why it carries none. **Every one of them is.**

**What the registry receives is checked too.** `.moonignore` decides what gets packaged,
and a list of intentions that nothing exercises is a comment.
`_verify/check_package_contents.ps1` runs `moon package --list` — the same command
`moon publish` packages from — and asserts that the scratch is **out** (the scratch commit
messages, the scan artifacts, the credential, the gate transcripts, the remeasure dumps) and
that the evidence is **in** (the 89 mutation gates and their harness, the settle scripts, the
narrative, the roster gate, the documents a reader is sent to), and that every tracked file
ships **except the deliberately defective fixtures** — the `.mbt` files each family needs in
order to prove it fires, which are the gates' *inputs* and not the tool's source. Shipping them
made the published 0.5.1 fail its own self-scan: the analyzer that shipped with it read all 304
of the package's source files and reported **fifteen** actionable findings, every one of them a
defect a fixture carries on purpose. The gate now asserts their absence **in the other
direction**, so the exception is a rule and not a hole. **Both directions have been shown to go
red**: disabling the `COMMIT_*.md` rule puts 23 scratch messages into the package and the gate
fails; excluding `_verify/NARRATIVE.md` takes the narrative out of it and the gate fails;
removing the two fixture rules puts the 24 fixtures back into the package and the gate fails.

**A notice is not an error, and the label says so.** A declared scope limit — "match
expression is outside the analyzed subset; it was read but not analysed" — is rendered
**`notice:`**, never `error:`: it is a statement about what the analyzer read, not a defect
in the code it read. `FParse` is one family with two meanings, and the two are told apart by
one predicate, `Report::is_notice`, which the renderer, the SUMMARY's `actionable` count,
the mermaid drawing and the JSON bridge all go through — so the label and the number cannot
disagree. `_verify/check_notice_labels.ps1` checks the rendered output, exercises all four
producer paths against the tool's own messages, and holds the marker convention in place in
the source. **Both of its halves have been shown to go red**: labelling a scope limit
`error:` again fails it, and dropping the marker from one skip message fails it too.

Two switches change what it does: `-SkipMutations` runs everything except the mutation
gates, and `-SelfTest` exercises the harness's own stage function against a failing body, a
throwing body and a passing body. **A guard that has never been shown to go red is not a
guard**, and this is where that is shown.

### Formal verification (`moon prove`)

`src/core` is the proof subject: `src/core/moon.pkg` sets `proof_enabled = true`,
which enables MoonBit 2026's experimental formal verification, and
`src/core/core_proof.mbtp` is the logic side — predicates + **19 lemmas**. The 19
lemmas were measured **21/21 goals VALID** (unsat) on 2026-10-03, each machine-checked
with cvc5.

> **The command does not run green today, and the reason is measured.**
> `moon prove src/core` fails with `unbound type symbol 'array'` — **not** `'map'`. The
> generated Why3 file declares the two abstract types itself: `type array 'a1` at line
> 136, `type map 'a1  'a2` at line 138. It uses them earlier — `array` at line 20
> (`IfaceSig`), `map` at line 27 (`IfaceSymTab`). Why3 requires a type to be declared
> before it is used, and `array` is **declared after its first use**. So the file does not
> load, and nothing is proved: `0 of 1 packages proved`, `0 goals proved`.
>
> **THE CAUSE WAS RE-MEASURED, AND THE EXPLANATION THIS PARAGRAPH USED TO GIVE WAS
> WRONG.** It blamed the toolchain's proof prelude. The experiment below is what refuted
> it, and it also refuted the advice the old explanation carried — that `IfaceSymTab`
> has to move out of the proof subject, which changes this package's public API and is
> therefore a version-line decision. **No public API has to change to find that out.**
>
> **THE EXPERIMENT.** Hoisting only the `array` declaration moves the error forward: it
> becomes `unbound type symbol 'map'` at line 28. Hoisting both makes `why3` load the
> file, generate 21 VCs and exit 0 — and of those 21, cvc5 answers `unsat` for 20, while
> `severity_taxonomy_holds` comes back `unknown (incomplete)` (measured 2026-11-20 on
> core 0.10.21+06da1ed44; a 300 s limit decides it no better). **The lemmas are not
> blocked by this package's source; they are blocked by the order two declarations are
> emitted in, which is the toolchain's to fix.**
> `_verify/check_prove_status.ps1` runs the prover and holds this paragraph, its Chinese
> twin, the workspace skill and the sibling gate to what the prover reports today.
>
> Two `#proof_pure` annotations were also **false**: on `path_tail` and `unqualified`,
> whose bodies build a `StringBuilder`, which the prover rejects (error 4207). One
> false annotation stops the whole file from proving, and both of those arrived on
> 2026-10-09. They are removed, and `_verify/check_prove_contracts.ps1` now fails the
> release if any `#proof_pure` body is one the prover rejects.

## Release history

The release-by-release history — every version's changes, the measurement behind each
change, and the correction when one was needed — is in **[CHANGELOG.md](CHANGELOG.md)**
([中文](CHANGELOG.zh.md)).

## Contributing

1. Fork the repository and create a feature branch.
2. Add tests for new functionality.
3. Run the release gate and make it green:

   ```bash
   powershell -NoProfile -ExecutionPolicy Bypass -File _verify\release.ps1
   ```

4. Open a pull request.

The gate is not optional decoration: it runs **89 mutation gates**, each of which mutates
the source, requires a test to go red, and proves the restore byte-identically.
Of the **519** live mutations, **477** expect a kill; **400** of them also name the test
that must go red, so the gate log says *which* test was the guard and not merely that
something was. All three numbers are **computed** by the README gate from the gate
sources themselves — a published count that no gate checks is a count that goes missing
quietly.

Four of those 88 gates had been **red since 0570 and 0571** — not failing, but *not running*.
Each mutation gate anchors on the exact text of a source site; 0570 taught the walker to
walk a `catch`/`noraise` arm's guard and 0571 added two families to the id map, and both
moved those sites without moving the anchors, so their pre-flight aborted with
*"N pattern(s) absent. No suite was run."* **0.4.47 was cut with the local release gate
red** — measured over every release tag, not guessed: the four gates are green at every tag
from v0.4.30 through v0.4.46 and red at v0.4.47. They are now **re-pointed at the current
code, not retired** — the code they test is alive and each mutation still has to go red —
and each of the four is measured green with every restore byte-identical.

## License

MIT License. See [LICENSE](LICENSE) for details.

## References

- [MoonBit Language Guide](https://www.moonbitlang.com/docs/)
- [moonbitlang/core](https://mooncakes.io/docs/moonbitlang/core) — the pinned corpus
- [moonbitlang/parser@0.4.3](https://mooncakes.io/docs/moonbitlang/parser@0.4.3) and
  [moonbitlang/lexer@0.4.2](https://mooncakes.io/docs/moonbitlang/lexer@0.4.2) — the
  toolchain's own grammar, cross-checked against
- [riantr/pyroduct](https://mooncakes.io/docs/riantr/pyroduct) — the reference consumer of
  the machine-table audit
- [skills.mooncakes.io](https://skills.mooncakes.io) — the published skill
- Nanjing University, *Static Program Analysis* (`1_Intro.pdf`, Yue Li, Fall 2026) — the
  lecture series this tool's analyses follow; the map of what this tree implements is in
  `_verify/NARRATIVE.md` §0564, and the map of the course's decks in §0572
- Nanjing University, *Static Analysis for Security* (`13_Security.pdf`, Tian Tan) — the
  security lecture the taint analysis (`src/flow/taint.mbt`) follows; its chapter 4 is the
  taint rules and its own worked example is the oracle
