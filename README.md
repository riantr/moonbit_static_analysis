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

Measured on `moonbitlang/core` (1679 files): **1621 parsed, 30 actionable** — 10 of them are
constructs this frontend does not read or an operator it does not model, and the other 20 are
`MSA-015` dead stores on declarations: a `let` whose value is overwritten before anything reads
it. That is dead weight in the analysed code rather than a reader gap, and every one of the
20 was measured against the source it names. The 14 findings demoted in 0.4.38 — names the
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
moon add riantr/moonbit_static_analysis@0.4.46
```

Then import it in your `moon.mod`:

```moonbit
import {
  "riantr/moonbit_static_analysis@0.4.46",
}
```

### The host your toolchain has to be

The published wasm is **not self-contained**. It imports **93 symbols** from
`moonbitlang/async` — the file IO, the process calls, the event loop — and the **host** has to
supply every one of them when the module is instantiated. `moonx` supplies them from the
async runtime that ships with **your** MoonBit toolchain.

So the artifact has a **floor**, and the floor is a property of the published *bytes*:

| what | where |
|---|---|
| the symbols the artifact is allowed to require from a host | `_verify/host_requirements.txt` |
| the gate that holds the artifact to them | `_verify/check_host_requirements.ps1` |
| the same check against the **published** bytes | `_verify/selfscan_published.ps1` |

**Since 0.4.45 the runtime comes from `moonbitlang/core/async` — the copy bundled with
your toolchain — and this package depends on nothing at all.** No `moon.mod` import
block, no version to keep in step with the user's toolchain. That is the whole point:
the disagreement between "the version this package pins" and "the version the user's
toolchain has" is what broke 0.4.38.

**THE HOST ABI NAME DID NOT CHANGE, AND THE SYMBOL SET GOT BIGGER.** A wasm import's
module name comes from the FFI declaration in the source, and `moonbitlang/core/async`
still declares its host externs under the name `moonbitlang/async` — so the host
supplies the same module as before. What changed is the set: **90 → 93**.

| | symbols |
|---|---|
| **new** | `stdio/get_stdio_handle`, `thread_pool/get_read_console_result`, `thread_pool/make_read_console_job`, `thread_pool/make_write_console_job`, `thread_pool/run_job` |
| **gone** | `io/errno_is_read_EOF/windows`, `thread_pool/errno_is_cancelled` |

**AND THE FLOOR WENT UP WITH IT, WHICH IS THE PART TO READ TWICE.** MEASURED: the
standalone `moonbitlang/async` 0.22.5 covers only **89** of the 93 — it has
`stdio/get_stdio_handle` and none of the four `thread_pool` additions. The bundled
`moonbitlang/core` **0.10.20+65efd5b93** declares 215 externs and covers all 93. So:

> **0.4.45 and later need a MoonBit toolchain bundling `moonbitlang/core` 0.10.20+65efd5b93
> or later** — moon 0.1.20261104 or later. A toolchain that still bundles the standalone
> `moonbitlang/async` cannot instantiate this artifact, and upgrading this package alone
> will not change that: the import surface is a property of the published bytes.

The failure arrives before the analyzer runs a single line:

```
LinkError: WebAssembly.Instance(): Import #5 "moonbitlang/async" "thread_pool/make_write_console_job": function import requires a callable
```

**0.4.38 WAS BUILT FOR A NEWER HOST THAN MOST, AND A USER FOUND OUT.** Its
`moonbitlang/async` had been bumped to 0.22.6, which declares three more host-provided
symbols — the same three console jobs. A toolchain bundling 0.22.5 cannot supply them.
0.4.45 asks for those three again, plus two more, because the runtime it uses is the one
that ships with the toolchain. If you hit that error on 0.4.38: use **0.4.37**, or
upgrade your MoonBit toolchain, or move to **0.4.46**.

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
moonbit_static_analysis_0.4.46_0.1.20261023_20261024T060000Z.mmd
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
| `--ssa-cost` | Measure what **static single assignment** would cost on the target tree and print one `SSA-COST` line: the variables the programs define, the versions SSA would give them, the phi-functions, and the copies their removal would need. It is a **query** and not a scan — it prints the line and stops, and no finding is reported. The claim it measures is the lecture's own — the *Intermediate Representation* lecture (Nanjing University, Fall 2026), p.37: *"SSA may introduce too many variables and phi-functions"* — a claim with no number in it. The line carries its **coverage** beside the numbers, because a number without its coverage is half a number. |
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
NOTICES	TOTAL	notices=13520	printed=1705	aggregated=11815	1705 of them are printed per line: the ones that can hide a finding, and the low-confidence ones, which name a place. The other 11815 are counted by shape below
NOTICES	count=7947	test declaration is outside the analyzed subset; its body was not analyzed
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
| `MSA-017` | `NegativeIndex` | | |

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
Measured on the seven pinned corpora: **29,887** unchecked calls, against **31** actionable
findings.

## Coverage and limits

### What this tool does not compete with

On `.mbt`, this tool does **not** compete with the toolchain's compiler: `moon check` has a
real parser and reads the **whole** language. On the same `moonbitlang/core` it reports
**no** diagnostic at all; this tool's `.mbt` frontend reads a **subset**
and parses **1621 of 1679** files (96.5%); `.mbti` and `.mbt.md` are 100%.

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
Analysis* (Yue Li, Fall 2026); the full map — which of the course's own analyses this tree
implements, and the one place where the framework and this tree disagree — is in
`_verify/NARRATIVE.md` §0564.

### The constructs the frontend reads past

Every declaration or expression form it reads past **without analysing** is reported as a
notice, and the notice is a statement about the tool, not about your code — so it is
rendered **`notice:`**, a label of its own rather than a borrowed `error:`. Measured on this
project's own source (236 files), with the per-file printing cap lifted so the count is the
whole finding set:

| notice | n | | notice | n | |
|---|---:|---|---|---:|---|
| `test` declaration | 1600 | | `const` declaration | 7 |
| `if` expression | 100 | | `short lambda` | 8 |
| `struct` declaration | 85 | | `type` declaration | 7 |
| `anonymous function literal` | 48 | | `try` expression | 1 |
| `enum` declaration | 25 | | | |

Removing one of those rows needs an AST node for that form, which is why they are features
and not notices to be reworded. The distinction that matters is not the wording but the
**position**: **157** of them sit inside a function's extent and can switch that body's
audit off, so they are printed one per line; the other **1724** sit outside every function's
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
per-file printing cap lifted so the count is the whole finding set: **23,226** notices —
every declared scope limit, plus the low-confidence findings demoted in 0.4.38. The scan
says so itself: its `NOTICES` table counts **3,971** of them as printed per line and
**19,255** as aggregated — which is 3,971 + 19,255 = 23,226, the same number — and the 3,971
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
the tool produces **694** `UnusedLocal` and **1,343** `UnusedParam` findings across the
seven pinned corpora and this repository's own source — the same 236 files the notice table
above counts, with `_verify/` excluded because it holds no tracked source, so the pair is
reproducible from a clean checkout. With it on, as it ships, it
produces **one** of them: a local assigned and never read, in `moonbit_labeler`. So the
suppression is hiding **693** locals and **1,343** parameters, and the per-binding
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
> **AND 17 MORE ARE DEMOTED.** Since 0.4.38 a finding the analyzer does not stand behind is
> rendered `notice:` and counted as a notice rather than as actionable, and the census keeps
> the demoted set in its own table and its own total — a set of findings that leaves the
> census is a set that can go missing silently. Every one of the 17 carries the confidence
> `low`, and every one of them is a name the analyzer could not resolve.
>
> **THE MODULE VIEW COUNTS 14 OF THEM, AND IT IS NOT THE SAME 14.** The two views are two
> analyses — this one takes every function as an entry point, the module view takes the
> module — so they do not find the same names: in `moonbit_core` this view reports 17 and
> the module view 14, and only **8** of those are the same site. That is the same difference
> as the 46 against the 30 above, and the two views stay separate, not additive.
>
> | demoted family | n | what the lens claimed |
> |---|---:|---|
> | B | 8 | a BigInt literal's `N` suffix (`0N`) is not read |
> | F | 1 | a name the analyzer cannot see — a sibling-file helper, a type parameter's method, an internal API absent from the `.mbti` index |
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
              and the pointer analysis read three more times: with a context
              (call-site / object), with a scope (on demand), and without a
              heap at all (access paths -- the storeless model)
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
the lecture states (*Data Flow Analysis -- Foundations*, Nanjing University): a CFG, the meet
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
(Tian Tan, Nanjing University), p.33-39 and p.52-56 -- and it is where a method call
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
names that merging as a **choice**, not a fact: `Pointer Analysis` (Tian Tan, Nanjing University,
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

**TYPE SENSITIVITY IS NOT BUILT, AND THE REASON IS A MEASUREMENT.** The third `Select` variant is
the receiver's *type*. A local's type is published nowhere this package can read — the type lens
publishes only the module frame, so `src/flow` cannot ask what type a receiver has, and a variant
that asked would have to invent one. It is left out rather than guessed at.

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
report pipeline. The family roster is unchanged at seventeen.

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
report: the family roster is unchanged at seventeen, and the storeless model is a
library-level analysis beside the other two pointer readings.

### And under the CFG there are basic blocks

`src/flow/bb.mbt` builds the **basic blocks** of a CFG and the control-flow graph over
them — the layer a CFG is normally drawn on top of. The lecture it is pinned to
(`Intermediate Representation`, Nanjing University, Fall 2026) prints a worked example
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
would need **16** copies. Over this project's own source — 208 files, 961 functions, 7,487
instructions of 3AC — the same measurement gives **837** variables becoming **2,087** versions,
**756** phi-functions and **1,860** copies. The claim is not a figure of speech.

The measurement is a mode of the scanner, `--ssa-cost`, and it prints one line:

```
SSA-COST	files=208	unreadable=0	functions=961	converted=5	partial=956	declined=5080	…
```

It reports its **coverage** beside the numbers, because a number without its coverage is half a
number: the files read, the functions measured, and the statements the lowering declined (4,979
of them — the 3AC layer converts the statements it understands and counts the rest). The release
gate pins the line, so the next increment that moves it has to move the pin on purpose.
## Verification

```bash
moon check --target all --deny-warn   # 0 errors, 0 warnings (js / native / wasm / wasm-gc)
moon test --deny-warn                # 1600/1600 on wasm; 1458/1458 on js and wasm-gc
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
versions and counts**; **the mutation-gate roster and a self-test that shows it can go
red**; **what the registry will actually receive, and a check that the junk stays out of
it**; **the notice labels, and a check that a scope limit is not an error**; **the frame
audit, and a check that a region silences only the bindings it could have read**; the
published-package self-scan's own self-test; the corpus comparison against the
pinned baselines; the per-function census and its control; **the behavior lens's own
table, checked against what the analyzer produces today**; and then **every mutation
gate** — 87 of them.

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
    gate roster: self-test (seven injected defects must be caught)
    gate roster: one harness, one list, and a count that matches
    the shared harness: the INCONCLUSIVE verdict, shown to go red
    proof contracts: no false #proof_pure
    package contents: the junk stays out, the evidence stays in
    notice labels: a scope limit is a notice, a defect is an error
    the family roster: one id each, contiguous, and reversible
    frame audit: a region silences the bindings it could have read, and no others
    match arms: the arms are read, the findings are true ones, and the fallback is exact
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

The list is DERIVED from `_verify/release.ps1` and checked by
`_verify/check_readme_links.ps1`, so a stage added to the gate and not named here makes
that gate red rather than quietly widening what the gate does.

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
directions, and its `-SelfTest` injects seven defects into a copy of `_verify` — a gate the
list does not name, a gate in the list that is not on disk, a gate off the shared harness,
a guarantee deleted from the harness, a `--filter` in the harness, a stale count in the
harness header, a moon invocation that does not name the project root — and requires each
to be caught. **All seven are.**

**What the registry receives is checked too.** `.moonignore` decides what gets packaged,
and a list of intentions that nothing exercises is a comment.
`_verify/check_package_contents.ps1` runs `moon package --list` — the same command
`moon publish` packages from — and asserts that the scratch is **out** (the scratch commit
messages, the scan artifacts, the credential, the gate transcripts, the remeasure dumps) and
that the evidence is **in** (the 87 mutation gates and their harness, the settle scripts, the
narrative, the roster gate, the documents a reader is sent to), and that every tracked file
ships. **Both directions have been shown to go red**: disabling the `COMMIT_*.md` rule puts
23 scratch messages into the package and the gate fails; excluding `_verify/NARRATIVE.md`
takes the narrative out of it and the gate fails.

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
> `moon prove src/core --why3-config .why3.conf` fails with
> `unbound type symbol 'map'`. `src/core` grew `IfaceSymTab` on 2026-10-08 — a struct
> whose fields are `Map[String, Bool]` — and the toolchain's proof prelude has **no
> `Map` theory**, so the generated Why3 file declares `map int bool` and neither
> `moon prove` nor `why3` can load it. The 19 lemmas never touch `IfaceSymTab`: it is
> the **package** that is proved, and the package carries the type. The fix is to move
> `IfaceSymTab` out of the proof subject, and that changes this package's public API
> (`@core.IfaceSymTab` is exported), so it is a version-line decision rather than a
> patch.
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

The gate is not optional decoration: it runs **87 mutation gates**, each of which mutates
the source, requires a test to go red, and proves the restore byte-identically.
Of the **504** live mutations, **461** expect a kill; **384** of them also name the test
that must go red, so the gate log says *which* test was the guard and not merely that
something was. All three numbers are **computed** by the README gate from the gate
sources themselves — a published count that no gate checks is a count that goes missing
quietly.

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
- Nanjing University, *Static Program Analysis* (Yue Li, Fall 2026) — the lecture series this
  tool's analyses follow; the map of what this tree implements is in `_verify/NARRATIVE.md`
  §0564
