# moonbit_static_analysis

[中文](README.md) | **English**

`riantr/moonbit_static_analysis` — **a three-inspection (structural / type / behavior) static-analysis pipeline: one infrastructure, two uses**:

1. **Program-code revision**: analyze programs in the **fast-evolving MoonBit language** (undefined names, unused bindings, type mismatches, dead branches, unreachable code);
2. **Static state revision**: a generic machine-table audit for multi-layer state machines (`src/statecheck`) — **the audited subject calls this module**, feeding its machine tables in as plain data. The reference consumer is [riantr/pyroduct](https://mooncakes.io/docs/riantr/pyroduct@0.1.28) (a subject / group / society / evolution state-machine family); its `audit` package drives this module black-box with its real tables.

One pipeline runs through both: **structural walk → types/symbols → abstract interpretation → unified report**.

## What 0.4.7 changes

**The `.mbti` interface audit resolves types across files.** Generated interface
files heavily reference types declared in other files of the same package (or in
extern directories) — `&Show` parameters, `raise SnapshotError` returns, `impl
Debug for BenchError` targets. `@moonfiles.iface` used to see one file alone, so
13 real core `.mbti` files were flagged for "unknown type". This version gives
the interface audit a **module-wide interface symbol table**: declarations and
`pub using` re-exports are collected file by file across the scan target and
merged; resolution order is this-file declarations → builtins → type parameters
→ any scanned interface (types only). Core `.mbti` defects go **13 → 0**,
actionable **49 → 36**.

Fixed along the way: the re-export collector recorded nothing for the `pub using
@pkg {type T}` shape (24 type and 20 trait prelude segments were invisible to
it); they now enter the table.

Measured on `moonbitlang/core` (1029 files, same machine):

| | files | parsed | actionable | undefined names |
|---|---|---|---|---|
| 0.4.6 | 1029 | 320 | 49 | 17\* |
| 0.4.7 | 1029 | **320** | **36** | **17** |

\* Correction: the 0.4.6 row was published with **0** undefined names, which
contradicts that release's own scan — the same 17 findings are present there.
Confirmed this round against the original artifact and corrected to the measured
values; the `.mbti` fix did not touch them.

The remaining 36 (the next layer): 17 undefined names = 11 cross-file function
references (the hex / base64 v128 bench files call `sample_bytes` /
`encode_scalar`, defined in other files of the same package) + 3 references to
names declared outside the subset (`E_MAX` / `b` / `N`) + 3 other shapes (`is` /
`e`); the other 19 are unused bindings and similar defects.

Self-scan (this repository's own source) stays at **0**. Tests 231 → 233.

## 0.4.8 — three self-scan rounds, mermaid artifact as the evidence

The scanner was pointed at itself for three rounds, each round taking the
previous round's output as its work list. Evidence was the mermaid artifact
(`--mmd '@'`); the **stdout text report is authoritative**, because the drawing
is lossy by construction (`findings_shown_per_file = 40`).

| round | parsed | actionable | what it fixed |
|---|---|---|---|
| start (0.4.7) | 46/46 | **104** | — |
| after round 2 | 46/46 | **8** | substitution skips, `walk_target` write-through, stale `.mbti` |
| after round 3 | 46/46 | **0** | string-interpolation reads were invisible |

Coverage never regressed. Suite: 208 js / 274 wasm / 208 wasm-gc, `--deny-warn`
clean.

**A substitution skip is a hole in the function frame.** A `match`, a `try` or
an fn literal is a declared scope limit — it moves no error line and costs no
coverage — but the region it skipped is where a binding's only assignment could
be, so `UnusedLocal` / `UnusedParam` / `ParamChanged` are now skipped for any
function containing one. This required the function's **whole extent** (header
to closing brace), which `SFunc` / `SLocalFunc` now carry. `104 → 8`.

**Writing through a parameter is a read, not a rebinding.** MoonBit structs are
references, so `self.field = v`, `v[0] = x` and `pair.0 = x` mutate the object
the parameter points at and leave the parameter alone. All three previously
counted as `ParamChanged`, producing a "changed by assignment" report whose own
advice ("no longer holds the value the caller passed") was false. `ParamChanged`
is now a bare-name rebinding only.

**A name read through `\{...}` is a read.** The interpolation body is copied
raw into the string payload, so it was never a token — a name read only that
way looked unread, and a name that does *not* exist inside one was never
reported at all. `TStr` now carries the names its interpolations reference and
the walk resolves them. **All 8** findings that survived the previous step were
this one defect: `mermaid.mbt` `anchor`, `pipeline.mbt` `i`/`s`/`r`, `parser.mbt`
`what` ×2, `interp.mbt` `name`, `cli/main.mbt` `live`. `8 → 0`.

Two notes on how those numbers were reached, because both are the kind of thing
that gets repeated as a rule:

- **Round 3's premise was wrong.** The 8 findings were slated for cleanup as
  dead code. They were not dead — deleting them would have removed working code
  to satisfy a false positive. The round found a defect in the analyzer instead.
- **The interpolation fix immediately manufactured two new false positives**,
  `no visible binding for '1'` and `'10'`, on `\{i + 1}` and `\{pct / 10}`: an
  identifier was allowed to start with a digit. Only the rescan over real code
  found them. Fixing a false positive and introducing one are the same class of
  action; the difference is running the scan again.

## Install / Quick start

```bash
moon add riantr/moonbit_static_analysis@0.4.8
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

## Rendering a scan as a diagram (public API)

`@sa.mermaid_states(verdicts, summary, prov, per_file, max_files)` turns a scan into a
mermaid `stateDiagram-v2` — the same findings the CLI prints, shaped for a program to read
rather than a human to skim.

The spine of every file's box is the trust chain the counts depend on: `lexed → structural →
type → behavioral`. A file the frontend did not finish stops at the line it stopped at, with
the post-boundary findings **counted and not drawn**. Each finding is its own state, hung off
the inspection that reported it, carrying a note with `WHY:` (the rule that fired and the
evidence it fired on) and `HOW:` (what to change), taken from `@core.Family::advice`.

Two families carry a caveat their reader must know *before* acting, and both say so in the
note text: `ParseError` on a `.mbti` / `.mbtp` / `.mbt.md` file is usually a frontend rule
rather than a parse boundary, and `UndefinedName` has two known blind spots (a `#doc(hidden)`
API appears in no `.mbti`; a `@pkg.fn(1, 2)` top-level reference is not folded into a
callable name).

`per_file` and `max_files` cap the drawing, `0` meaning no cap. **Whatever a cap leaves out is
stated in the diagram** — in the header and in a note on the file — so a truncated diagram
cannot be read as a clean one. `summary` always describes the WHOLE scan while the drawing may
be a subset. Files are taken in descending **actionable** count, not raw findings: on
moonbitlang/core the largest raw-finding file is a 402-finding test file that is 402 notices
and zero defects, and ranking by raw count put it first in a diagram whose job is to lead
with what to fix.

```moonbit
let root = /* the resolved source root */
let prov = @sa.provenance_for("my/module@1.2.3", root)
let text = @sa.mermaid_states(verdicts, @sa.aggregate(verdicts), prov, 8, 25)
println(scan_artifact_name(prov, root))
```

The output is valid mermaid, verified by parsing *and rendering* a real moonbitlang/core scan
(1029 files) through `mermaid@10.9.8`. Two grammar constraints the renderer is written around,
both measured rather than assumed:

- a transition label is everything after the **first** `:`, so it may not contain one —
  locations and messages therefore live in the quoted state label, never on the arrow
- MoonBit has no operator continuation, so a source line beginning with `+` is a parse error;
  the document is emitted one `write_string` at a time for that reason alone

`src/sa/mermaid_test.mbt` re-reads the emitted text against that grammar on every run — every
line must be a form mermaid accepts, every node id an identifier, every transition endpoint a
declared state — and is itself shown failing on five documents it is meant to catch.

### Naming the artifact: what was read, by what, and when

A scan result is a claim about a specific tree, read by a specific toolchain, at a
specific moment. All three go in the filename —
`@sa.provenance_for(target, root)` collects them and
`@sa.scan_artifact_name(prov, root)` lays them out:

```
moonbit_static_analysis_0.4.7_0.1.20260920_20261009T155222Z.mmd
moonbitlang-core_0.1.20260920+7d59c7ec9_0.1.20260920_20261009T051925Z.mmd
tree_unknown_0.1.20260920_20261009T051511Z.mmd     # version not determined
```

`<package>_<version>_<moonbit>_<stamp>.mmd`. Four fields, each answering a
different question:

| field | question | source |
|---|---|---|
| `package` | what was read | the coordinate, or the **resolved** directory |
| `version` | which revision of it | the target's `moon.mod` (`moon.mod.json` too) |
| `moonbit` | **which toolchain read it** | `moon version`, run as a subprocess |
| `stamp` | when | `@async.now()`, UTC |

`moonbit` is the field that cannot be recovered from the tree, and it is the one
that decides whether a scan can be compared with a later one. `moon.mod` records
the module's own version and its imports, never the compiler that built it, and
there is no `MOONBITS_*` environment variable to ask (checked — `env:` filtered
on MOON is empty). It is measured, not read off a doc comment: `moon version`
prints

```
moon 0.1.20260920 (914d7da 2026-09-20)
```

and the second field is taken. It costs a subprocess, so it runs once per
artifact and only when a diagram is actually being written; if that fails the
field reads `unknown` rather than being wrong.

Why it matters here specifically: this analyzer's own `.mbt` subset went from
158 files to 173 on one **unchanged** core checkout when method calls were
modelled. Results move with the toolchain, so a scan that does not name its
toolchain is not comparable with a later one.

`package` is the coordinate's module, or for a path the **resolved** directory
name — scanning `.` is the most ordinary invocation there is, and naming the
artifact after the string the caller typed would produce `_.mmd`.

The stamp is UTC, from `@async.now()`, which was **measured** rather than read
off a doc comment: a wasm run returned `1791522911114` against a wall clock of
`1791522910008` taken ~1.1 s earlier, which is exactly the delay between the two
calls. There is no timezone database available, so the stamp is UTC and says so
with a trailing `Z` rather than being an hour wrong twice a year.

> **Corrected in this round.** The previous version of this section claimed the
> CLI could not stamp a time at all, because "the only clock is behind an
> `internal` package". That was wrong: `moonbitlang/async` re-exports it
> publicly as `pub using @event_loop {now}`, and `provenance_for` had been
> calling `@async.now()` since 0.4.5. The CLI was stamping `unknown` only
> because it had been given a hand-rolled empty stamp instead of calling the
> function that already worked.

Three things this deliberately does **not** do:

- **It does not omit what it could not determine.** A missing version, toolchain
  or clock is written as the literal token `unknown`. Dropping the segment would
  produce a name that looks complete and is not — and with four fields it is
  worse than that: the gap would SHIFT, so a reader parsing
  `core_0.1.2_20261009` would take the stamp for the toolchain version.
- **It does not produce a dotfile.** A name starting with `.` is invisible to
  `ls` on Linux and macOS, and an artifact nobody can list is not one anybody
  will find again.
- **It does not trust the filename as the record.** The same three facts are
  repeated as `%%` header comments *inside* the document, because a file gets
  renamed and once it does its name is no longer evidence of anything.

### Writing one from the CLI: `--mmd` / `--mmd-auto`

The renderer is a library call, and it is now also reachable without writing
any code:

```
moonx riantr/moonbit_static_analysis@latest <target> --mmd out/scan.mmd
moonx riantr/moonbit_static_analysis@latest <target> --mmd-auto
```

Both **also** write the diagram and print `MMD<TAB><path>` as the last line;
the text report on stdout is unchanged and remains the authoritative output.
`--mmd-auto` picks the name above and writes it to the **working directory**.

Three decisions here, none of them incidental:

- **Opt-in, never the default.** The drawing is lossy by construction:
  `mermaid_states` ranks files by actionable count and stops at its own cap,
  saying so in a `%% THIS DRAWING IS A SUBSET` comment. A tool that made the
  picture the only output would hide that, and would silently break every
  script grepping `SUMMARY`.
- **`--mmd` requires its path; `--mmd-auto` is a separate flag.** An optional
  value is ambiguous here: in `<target> --mmd <path>` the bare word after
  `--mmd` could equally be a second, unexpected target, and there is no way to
  tell the two apart. Rather than guess and fail with "unexpected extra
  argument", the value is mandatory.
- **The artifact never lands inside the analysed tree.** This module's stated
  invariant is that it only ever *reads* the target's files; dropping a file
  into someone's source repository would break that promise and dirty a tree
  the user may not own.

Every field is real. Measured on a full 1029-file scan of `moonbitlang/core`:

```
MMD  _mbcore_0.1.20260920+7d59c7ec9_0.1.20260920_20261009T132547Z.mmd
```

`_mbcore` is the resolved directory, `0.1.20260920+7d59c7ec9` the target's own
version from its `moon.mod`, `0.1.20260920` the toolchain from `moon version`,
and `20261009T132547Z` a real UTC stamp — which against a local wall clock of
`20261009T212552` is exactly the expected +8. If the `moon version` subprocess
fails, that field reads `unknown` and the rest is unaffected.

A write failure prints `ERROR --mmd: cannot write <path>` and leaves stdout
otherwise intact — `write_file` does not create parent directories, so
`--mmd no/such/dir/x.mmd` fails cleanly rather than leaving a half-written
file.

`@sa.stamp_utc(ms) -> String` is pure and separately usable: it converts epoch
milliseconds to `YYYYMMDDTHHMMSSZ` with the civil date computed by Hinnant's
`civil_from_days`, pinned in the tests against dates whose answers are not in
dispute — the epoch, a leap day, year and month boundaries, the exact instant a
real run reported, and both sides of the 400-year century rule (2000 is a leap
year, 2100 is not).

## Package structure

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
```

## Verification

```bash
moon check --target all --deny-warn   # 0 errors, 0 warnings (js / native / wasm / wasm-gc)
moon test --deny-warn                # 192/192 on wasm; 139/139 on js and wasm-gc
moon run src/cli                     # program demo + file-kind demo + pyroduct-shaped sample machine audit
```

The per-target counts differ on purpose: `src/sa` and `src/jsoncli` declare
`supported_targets = "+wasm+native"`, so the js and wasm-gc runs SKIP those two packages rather
than failing them. A test count that claims one number for every target is therefore wrong, and
the wasm number is the only one that covers the renderer and the scanner.

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
| `.mbti` | interface audit: malformed lines / duplicate signatures / unknown type references. The line grammar matches what `moon info` actually emits, so a generated file raises no *malformed line* — but its **unknown-type** check has no cross-file awareness and does raise false positives on generated files (measured: 93 on `moonbitlang/core`, a tree `moon check --target all` accepts with 0 errors). Treat those as unverified, not as defects |
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

- **mooncakes.io**: `moon publish` (after publishing, `riantr/moonbit_static_analysis@0.4.8` can be imported by any MoonBit module; `src/cli` ships a SKILL.md and is listed on [skills.mooncakes.io](https://skills.mooncakes.io)).
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
`--exclude <dir>` is repeatable and skips vendored source kept under an ordinary
directory name, which a dot-directory rule cannot catch.

### The output says what was UNDERSTOOD, not how much was counted

```
SCANNED	107 files under ...\ML\CI
CLEAN	.mbti	...\CI/pof/pkg.generated.mbti
PARTIAL	.mbt	defects=2	notices=1	read up to line 36, 57 after it not shown	...\CI/pof/aggregator.mbt
12:3 - error: ... (UndefinedName) [behavior]
PARSED	32/107 files understood (29.9%); 75 more read only up to their first parse error
SUMMARY	files=107	parsed=32	actionable=57	notices=211	unreliable=15759	withheld=6769	total=16027	(actionable+notices+unreliable = total; withheld ⊆ unreliable)
```

- **`PARSED` is the headline.** The frontend covers a SUBSET of MoonBit, so what it
  cannot read measures the tool's blind spot, not your code.
- **A partly-understood file is still worth reading.** The parser records the first
  line it genuinely failed on; findings before it are reported (`PARTIAL`), and
  everything after is counted in `unreliable` and never shown — it comes from a
  tree that is already wrong, so presenting it as results would reintroduce the
  exact failure this tool started with.
- **Skipped declarations do not move that boundary.** "This `test` block is not
  analysed" leaves the code after it readable, so such a file is `FOUND`.
- **`actionable` excludes notices.** A declaration form we chose not to analyse is
  not a defect in your code — otherwise the self-scan once reported "92 problems"
  where the true count was zero.
- Unparsed files are grouped BY REASON rather than listed one per line.
- `actionable + notices + unreliable` = `total`, asserted in the line.

**Cross-file type symbol resolution** (new in 0.4.3): a `.mbt` that uses a
type declared in another package (e.g. `Command` from `@argparse`) used to
fire `undefined name 'Command'` because the single-file analyzer only sees
the file it is reading. `--extern-iface-dir <dir>` (repeatable) walks the
named directory for `.mbti` files and loads their declared types and value
signatures into a **cross-file symbol table** the structural walk and the
type lens consult before reporting `FUndefinedName`. The natural target is
`.repos/` after you have `moon fetch`ed the dependencies you want indexed.
The target's own tree is always indexed. By default the analyzer also reads
the target's `moon.mod` and `moon fetch`es each direct import — pass
`--no-auto-fetch-deps` to skip it. A type hit returns `TUnknown`; a value
hit returns `TUnknownFn` — a new `Ty` variant meaning "known to be a value,
signature not read" — so a call like `Command(...)` neither fires
`FOpMismatch` nor has its arity checked against an invented one: a `.mbti`
gives the name and never the parameter list, so an invented arity is a
guess the checks would then report as fact. Names absent from the table
still report — the table only suppresses, never invents valid bindings.
Lookups strip a leading `@pkg.` first: a `.mbti` writes the declaration
bare (`pub fn T::m`) while a use site must write `@pkg.T::m`, so with exact
matching the two spellings never met and the only common way of naming
another package never hit.
  `withheld` is reported alongside it but is a subset of `unreliable` (the
  post-boundary findings of partial files whose pre-boundary finding count
  was zero), so it is intentionally not part of the sum.

**Measured** (before and after the trusted-region gate, same trees):

| target | files | parsed | actionable (before → after) |
|---|---|---|---|
| `riantr/moonbit_doubleML@latest` → 0.113.0 | 180 | **73 (40.5%)** | 0 → **123** |
| this repository (`.repos/0.3.5`) | 39 | **22 (56.4%)** | 0 → **7** |
| `moonbit_linalg_gpu` | 8 | **4 (50.0%)** | 1 → **5** |
| `ML/CI` (`--exclude _qa_verify`) | 107 | **32 (29.9%)** | 11 → **57** |

> **Where this stands against `moon check`.** On `.mbt` this tool does NOT compete
> with the toolchain's compiler: `moon check` has a real parser and ~90 built-in
> warnings at 100% coverage — measured 2.3 s for 128 diagnostics, each with
> `file:line:col`, the source line and a fix. This tool's `.mbt` frontend reads a
> **subset**, and on `moonbitlang/core` it parses **173 of 882** `.mbt` files
> (19.6%); `.mbti` and `.mbt.md` are 100%. The single largest reason used to be
> that **method calls could not be represented in the AST at all** — `ECall` takes
> a `String`, so `m.set(k, v)` had nowhere to go and the parse stopped there.
> **That is fixed** (a dedicated `EMethodCall` node, wired into all three
> lenses); the blocker went from 34 files to **0**. That
> is the honest headline number, and it is why `PARSED` is printed first.
> What this tool can do that the compiler cannot is the three file kinds it does
> not audit at all — `.mbti`, `.mbt.md`, `.mbtp` — plus cross-package semantics.
>
> An earlier version of this tool reported **529** "unused locals" on that ML/CI
> source where the compiler reports 8. Those were not a different opinion: they
> were struct bodies it had never parsed, and it reported the unread fields as
> unread bindings. It no longer can — a function the frontend truncated is now
> excluded from the unused-local / unused-param / param-changed audit outright,
> because "never read" is a claim about a whole function and a half-read
> function cannot support one. That fix alone took `moonbitlang/core` from 270
> actionable findings to 147, and this repository from 11 to **0**.
>
> Reading further, the same principle turned out to apply to the module frame
> too, and to a class of names the resolver had never been taught: a file the
> frontend did not finish has a **provably incomplete** module frame, so
> "nothing visible binds this name" is not evidence of anything there; and a
> `Type::member` path — `@debug.Repr::opaque_(v)` — is a member reference, not
> a binding, exactly as a field name and a method name already were. With
> `extern "c" fn` modelled as a declaration (it was skipped, which lost the
> name, so every call site of an extern function read as unbound) and the
> numeric-literal / enum-constructor gaps closed, `moonbitlang/core` goes from
> **270 to 49** actionable with `undefined name` down from 64 to 17 (published
> as 0 at the time; that release's own scan contradicts it, since corrected to
> the measured value), and this repository stays at **0**. 0.4.7 then wires the
> `.mbti` audit's unknown-type check to the module-wide interface table,
> clearing the remaining 13 false reports: **36**.
>
> | moonbitlang/core | files | parsed | actionable | undefined names |
> |---|---|---|---|---|
> | 0.4.5 | 1029 | 305 | 270 | 64 |
> | 0.4.6 | 1029 | 320 | 49 | 17 |
> | 0.4.7 | 1029 | **320** | **36** | **17** |

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
