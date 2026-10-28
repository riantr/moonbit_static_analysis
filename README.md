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

Measured on `moonbitlang/core` (1029 files): **984 parsed, 28 actionable** — and every one
of the 28 is a construct this frontend does not read or an operator it does not model, not
a defect in the analysed code. On that same tree `moon check --target all` reports exactly
**one** error, in a `.mbt.md` doc file.

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
moon add riantr/moonbit_static_analysis@0.4.37
```

Then import it in your `moon.mod`:

```moonbit
import {
  "riantr/moonbit_static_analysis@0.4.37",
}
```

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
findings: on `moonbitlang/core` the largest raw-finding file is `builtin/int64_test.mbt` at
**1022** findings — every one of them a notice, and none of them a defect — and ranking by
raw count put it first in a diagram whose job is to lead with what to fix.

### Provenance — the artifact name

A scan result is a claim about a specific tree, read by a specific toolchain, at a specific
moment. All three go in the filename — `<package>_<version>_<moonbit>_<stamp>.mmd`:

```
moonbit_static_analysis_0.4.37_0.1.20261023_20261024T060000Z.mmd
moonbitlang-core_0.1.20260920+7d59c7ec9_0.1.20260920_20261009T051925Z.mmd
tree_unknown_0.1.20260920_20261009T051511Z.mmd     # version not determined
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
| `--findings-shown-per-file N` | how many findings are **printed** per file (default 40). A printing limit, not an analysis limit: the SUMMARY counts come from every finding, so raising it reveals findings that were already counted and changes no summary number. |
| `--show-notices` | print **every** notice per line, not only the ones that can hide a finding. By default a notice is printed only when its region lies inside a function's extent -- that is, when a conclusion may have been withheld because of it -- and every other notice is counted by shape in one `NOTICES` table. This flag restores the whole per-line list, which is what the tool printed before 0.4.36, and it changes no count: the SUMMARY's numbers are the same either way. |
| `--families MSA-007,MSA-002` | report **only** these families, by their **stable id**. The ids are the `MSA-NNN` codes every rendered finding and every JSON record carries; the full roster is in [Confidence, ids, profiles and `nosec`](#confidence-ids-profiles-and-nosec). An id this version does not know is a `WARNING` and the scan still runs -- a family added in a later release must not make an older analyzer's profile unusable, and a typo must be loud rather than fatal. |
| `--exclude-families MSA-007` | report everything **except** these families. The same id vocabulary and the same rules. An id that is **both** included and excluded is an `ERROR` and the scan does not run at all: the two rules contradict each other, and which one won would be decided by the order of two `if`s inside the scanner. |
| `--honor-nosec` | honour `// nosec` comments in the **analysed** source: `// nosec` silences every finding on that line, and `// nosec MSA-007` silences that one family on that line. **Off by default**, and the default is a decision rather than an omission: a tool that stops reporting a finding because of a comment in the analysed source has an output the reader cannot trust without reading that source first. A `// nosec` that suppresses **nothing** is reported as a finding of its own -- a stale suppression is a fact about the source, and the source is what this tool analyses. |

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
PARTIAL	.mbt	defects=2	notices=1	unchecked=17	read up to line 36, 57 after it not shown	...\CI/pof/aggregator.mbt
12:3 - error: ... (UndefinedName) [behavior, MSA-002, low]
PARSED	32/107 files understood (29.9%); 75 more read only up to their first parse error
SUMMARY	files=107	parsed=32	actionable=57	notices=211	unreliable=15759	withheld=6769	unchecked=2841	total=16027	(actionable+notices+unreliable = total; withheld ⊆ unreliable; unchecked calls are not findings)
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
NOTICES	TOTAL	notices=10096	printed=1144	aggregated=8952	1144 of them can hide a finding; the other 8952 cannot, and are counted by shape below
NOTICES	count=6148	test declaration is outside the analyzed subset; its body was not analyzed
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
12:3 - error: no visible binding for 'cmd' (UndefinedName) [structural, MSA-002, low]
```

**THE CONFIDENCE IS HOW MUCH THE LENS CHECKED.** The severity says how bad the finding is
*if it is real*; the confidence says how sure the analyzer is that it is real, and the two
are independent — a finding can be severe and uncertain, or trivial and certain. There
are exactly three values, and they are the three situations a lens can be in:

| confidence | the lens… | the family |
|---|---|---|
| `high` | had the declaration, the signature or the type in front of it | everything else |
| `low` | was reasoning from a **name** alone | `UndefinedName` (MSA-002) — the binding it could not find may be in a file, or in a package, it was never given |
| `undecided` | could not decide at all | a declared scope limit — the analyzer's own blind spot, rendered `notice:` |

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

The ids are hand-allocated on purpose — deriving one from the enum's position would
renumber every family after an insertion, which is the one thing an id must never do —
and `_verify/check_family_roster.ps1` **checks** the table: one id per family, no id used
twice, the ids a contiguous run from `MSA-001`, and the inverse table (id → family) the
exact reverse of the forward one. Two tables written down twice will disagree eventually,
and a disagreement between them is invisible, so a gate compares them.

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

**AND THE CALLS THE ANALYZER COULD NOT CHECK ARE DISCLOSED.** The type lens checks a
call's arity and argument types only when it has read the callee's signature; a `.mbti`
gives a name and never a parameter list, a method's signature is not in the source at all,
and a `..` chain link is a method call wearing different syntax. Until 0.4.37 the tool
said nothing about any of them, so *I could not check this* and *there is nothing to
report* were the same output — and a file with no findings and four hundred unchecked
calls printed exactly like a clean file. Now the count is on the file's own verdict line
(`unchecked=N`) and on the `SUMMARY`, where it is deliberately **not** part of the sum.
Measured on the seven pinned corpora: **23,427** unchecked calls, against **28** findings.

## Coverage and limits

### What this tool does not compete with

On `.mbt`, this tool does **not** compete with the toolchain's compiler: `moon check` has a
real parser and reads the **whole** language. On the same `moonbitlang/core` it reports
**one** error and 251 warnings of two kinds; this tool's `.mbt` frontend reads a **subset**
and parses **984 of 1029** files (95.6%); `.mbti` and `.mbt.md` are 100%.

What this tool can do that the compiler cannot: the three file kinds the compiler does not
audit at all — `.mbti`, `.mbt.md`, `.mbtp` — plus cross-package semantics.

### The constructs the frontend reads past

Every declaration or expression form it reads past **without analysing** is reported as a
notice, and the notice is a statement about the tool, not about your code — so it is
rendered **`notice:`**, a label of its own rather than a borrowed `error:`. Measured on this
project's own source (187 files), with the per-file printing cap lifted so the count is the
whole finding set:

| notice | n | | notice | n | |
|---|---:|---|---|---:|---|
| `test` declaration | 1413 | | `anonymous function literal` | 18 |
| `if` expression | 103 | | `const` declaration | 6 |
| `struct` declaration | 62 | | `short lambda` | 2 |
| `derive` declaration | 54 | | `try` expression | 1 |
| `enum` declaration | 25 | | | |

Removing one of those rows needs an AST node for that form, which is why they are features
and not notices to be reworded. The distinction that matters is not the wording but the
**position**: **124** of them sit inside a function's extent and can switch that body's
audit off, so they are printed one per line; the other **1560** sit outside every function's
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
different producers and are told apart by one predicate, `Report::is_notice`, which every
consumer of the finding goes through:

| what it is | rendered | counted as |
|---|---|---|
| a declared scope limit | `notice:` | a notice — excluded from `actionable` |
| a genuine defect in the file | `error:` | actionable |

Measured across the seven pinned corpora and this repository's own source, with the
per-file printing cap lifted so the count is the whole finding set: **19,603** notices,
every one of them a scope limit. The scan says so itself: its `NOTICES` table counts
**3,375** of them as printed per line and **16,228** as aggregated, and the 3,375 is
exactly the number of rendered `ParseError` lines. A genuine defect of this family would
render `error:` and break that equality -- and none does.

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
the tool produces **597** `UnusedLocal` and **1,137** `UnusedParam` findings across the
seven pinned corpora and this repository's own source. With it on, as it ships, it
produces **one** of them: a local assigned and never read, in `moonbit_labeler`. So the
suppression is hiding **596** locals and **1,137** parameters, and the per-binding
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
> gate **pins** the number. Today it reports **50** `actionable` findings, where the module
> view reports 28. **49 of the 50 are constructs this frontend does not read or operators
> it does not model; the fiftieth is a genuine finding** — a local assigned and never read
> in `moonbit_labeler`, and the first true defect this tool has published on any corpus.
>
> | family | n | what the lens claimed |
> |---|---:|---|
> | A | 12 | a hex float literal (`0x1.0p1023`) is not read, so its exponent part is reported as an undefined name |
> | B | 5 | a BigInt literal's `N` suffix (`0N`) is not read |
> | C | 6 | `==` between two arrays |
> | D | 3 | `Int + Char` and `List + List` |
> | E | 3 | `*` on a struct |
> | F | 2 | a name the analyzer cannot see — a sibling-file helper, a type parameter's method, an internal API absent from the `.mbti` index, a module qualifier |
> | G | 11 | unreachable code — the lens's own claim about the code |
> | H | 1 | a local assigned and never read — the lens's own claim about the code, and the one finding in the census that is a real defect |
> | I | 1 | `abs` on a `Double` |
> | J | 1 | `*` on two function values |
> | K | 3 | a local call with a named argument |
> | L | 2 | the documented `#doc(hidden)` limit |
>
> **"Accepted" is measured, not assumed.** `moon check --target all` on `moonbitlang/core`
> reports exactly **one** error, in `json/README.mbt.md`, and it is not one of the
> **twenty** files that carry a finding. That is only half of it: a file with no
> diagnostic is indistinguishable from a file nobody opened, so
> `_verify/control_perfunction_census.ps1` appends a deliberate type error to each of those
> files **in a copy** and requires the error back — **20 of 20**.
>
> **The two in family L are the documented limit rather than a defect**: a cross-package
> `#doc(hidden)` function cannot be indexed from the dependency's *source* — only from its
> `.mbti` — so `@locale.LocalePreferences::resolve` is still reported as an undefined
> function in `proton` 0.3.4. Answering them would mean growing the analyzer into a source
> indexer, which is a different project. **Use the view to see the lens, not to gate a
> build on it.**
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
subprocesses come from `moonbitlang/async` and only some backends have a working async
runtime; the other backends SKIP those two packages instead of failing.

## Verification

```bash
moon check --target all --deny-warn   # 0 errors, 0 warnings (js / native / wasm / wasm-gc)
moon test --deny-warn                # 1316/1316 on wasm; 1196/1196 on js and wasm-gc
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
`moon check --deny-warn`; all three test targets; `moon build --target wasm`; the grammar
probe's own verdicts; the own-source self-scan; **this README's own links, anchors,
versions and counts**; **the mutation-gate roster and a self-test that shows it can go
red**; **what the registry will actually receive, and a check that the junk stays out of
it**; **the notice labels, and a check that a scope limit is not an error**; **the frame
audit, and a check that a region silences only the bindings it could have read**; the
published-package self-scan's own self-test; the corpus comparison against the
pinned baselines; the per-function census and its control; and then **every mutation
gate** — 86 of them.

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
that the evidence is **in** (the 86 mutation gates and their harness, the settle scripts, the
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

The gate is not optional decoration: it runs **86 mutation gates**, each of which mutates
the source, requires a test to go red, and proves the restore byte-identically.
Of the **495** live mutations, **454** expect a kill; **377** of them also name the test
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
