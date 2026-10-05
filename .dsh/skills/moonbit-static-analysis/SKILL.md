---
name: moonbit-static-analysis
description: Revise MoonBit-subset programs and audit state-machine tables with the riantr/moonbit_static_analysis three-inspection pipeline (structural / type / behavior). Use when working in this workspace — before changing the pipeline, its tests, or the published package; when running the gates (moon check / moon test --target js / moon fmt --check / moon run src/cli); or when running formal verification (moon prove). Load this skill before editing sources under moonbit_static_analysis or pyroduct/audit.
---

# moonbit_static_analysis — the three-inspection pipeline

Module `riantr/moonbit_static_analysis` (dir `moonbit_static_analysis/`): one pipeline, three
inspections, one report stream. Two uses: MoonBit program revision (the current working subset of the
fast-evolving language) and static state revision of machine tables (`src/statecheck`, plain-data
`MachineSpec`). The reference consumer is `pyroduct/audit` (module `riantr/pyroduct`): pyroduct
calls US — we never import pyroduct.

## Commands (run inside `moonbit_static_analysis/`)

```console
moon check                # 0 errors, 0 warnings — first gate
moon fmt                  # format; `moon fmt --check` must stay clean
moon test --target js     # 51/51 (see the breakdown below)
moon run src/cli          # program demo + file-kind demo + sample machine audit
moon prove src/core --why3-config .why3.conf   # formal verification (19 lemma VCs)
```

The test breakdown is 4 targets × 51: pipeline, moonfiles (literate / .mbti /
.mbtp), parser (.mbtx import block), statecheck, walk/types/interp.

**`pkg.generated.mbti` is tracked.** Changing a public surface (`pub`, `pub(all)`,
a struct field, an enum constructor) requires `moon info`, and the regenerated
files must be committed — otherwise the committed interface describes a module
version that no longer exists. A brand-new package gets its `.mbti` from the
same run; it will not appear on its own.

pyroduct gates (run inside `pyroduct/`): `moon check`, `moon test` (98/98), `moon fmt --check`.

## Architecture (read before changing the pipeline)

```
parse (src/lexer, src/parser) → ast
① structural  src/walk    binding tables fn_bindings + structural findings
② type        src/types   symbols/signatures + type findings — declarations COME FROM ①'s tables
③ behavior    src/interp  abstract execution + behavior findings — method table COMES FROM ②'s sigs
④ merge       src/pipeline  same merge_group at the same span → ONE report, union of lenses
```

The other file kinds are frontends in `src/moonfiles` (see EXTENSIONS.md, which
is the taxonomy and the authority for what each suffix means):
- `.mbt.md` — only fences the toolchain actually compiles (`mbt`, `mbt check`)
  are three-inspected, with line numbers aligned to the .md file. `mbt nocheck`
  and a bare `moonbit` are display-only and are SKIPPED.
- `.mbti` — interface audit. The line grammar matches what `moon info` emits
  (import blocks, `#attribute` lines, const/let, `impl ... for T`, suberror,
  using re-exports, async/extern, type params, labeled params, noraise/cancel).
  Verified over the 71 generated interfaces in pyroduct/.mooncakes: 71/71
  clean, and 4/4 injected defects caught in 71/71.
- `.mbtp` — logic-side lint. A lint, NOT a substitute for `moon prove`.
- `.mbtx` — a standalone script (no module/package config). Its import block
  is `"path" [@alias] [*]`: modifiers TRAIL the path and are ordered. Recorded
  into `Module.imports` as a typed `ImportSpec`, echoed in the report; a
  repeated path is an FParse. Dependencies are not resolved.

- Assembly points are one-directional: a later stage never rediscovers what an earlier stage
  produced (types consume walk's binding tables; interp consumes types' signature tables).
- Dead branches are pruned twice (structural `const_eval` + behavioral `ABool` lattice value) and
  this double-pruning is pinned by tests — keep both.
- `src/core` is the pure kernel (no Array-carrying structs, no strings): `Pos`, `Span`, `Severity`,
  `Lens`, `Family` (merge_group contract), `Frame`. `Report` lives in `src/report` — the kernel must
  stay Array-free for the proof lowering.
- Machine audit: `src/statecheck` reads a plain-data `MachineSpec`; the three inspections read
  machine tables like programs (states are bindings; the drive-slot contract; the course as
  abstract execution with virtual stacks). pyroduct is the audited SUBJECT, not a dependency.

## Formal verification (moon prove)

- `src/core/moon.pkg` has `"proof-enabled": true`; `src/core/core_proof.mbtp` is the logic side:
  predicates + 19 lemmas (rank constants, the three strict-order laws, rank_order_agrees, the
  full severity taxonomy per Family).
- Contracts: `#proof_pure` on `pos`, `span_at`, `zero_span`, `Lens::rank`, `Lens::lower`,
  `Family::severity`. Only Int/Bool constants in pure bodies (strings → E4207). Logic bodies
  reject `!`, `↔`, `Type::method` forms and cross-package calls — keep proof code in the same
  package, use `== false`, method-call syntax, and wrap compound laws in predicates.
- The span-shape law is NOT provable (struct-literal bodies lower to opaque symbols) — pinned by
  tests instead; see the note in core_proof.mbtp. Do not re-add it casually.
- The bundled why3server (Windows) loses prover stdout — `moon prove`'s JSON bookkeeping records
  failure even when goals discharge. Machine-check per goal:
  `why3 --config .why3.conf prove -o <dir> -P cvc5 <mlw> -L <prelude>` then `cvc5` each `.smt2`
  (expect unsat = VALID). The local shims `.why3.conf` + `cvc5wrap.ps1` are gitignored and must
  not enter the published zip.

## Publishing

- moon.mod carries readme/repository/license/keywords/description (mooncakes requires license).
- `moon publish --dry-run` first (expect 202 Accepted), then `moon publish` (200 OK).
- Git remotes: `origin` = Gitee (primary), `github` = mirror; tags stay in lockstep with the
  moon.mod version (v0.1.x). Push master + tag to both.
- Registry README is the moon.mod `readme` file (Chinese `README.md`; English twin
  `README.en.md` cross-linked).
- After publishing a new version, bump `pyroduct/moon.mod`'s
  `riantr/moonbit_static_analysis@<ver>` and run `moon update` there, then the pyroduct gates.
- pyroduct/moon.mod contains Chinese — edit it only with file tools (pwsh `Get-Content` defaults
  to GBK on this machine and double-encodes the Chinese; recovery is possible from the registry
  zip but avoid it).

## Conventions

- MoonBit style: `///|` before each top-level definition; `pub(all)` for data surfaces; explicit
  `derive(Eq)`; `.unwrap_or()` (not `.or()`); `panic` is 0-arg; `moonbitlang/core` is NOT
  importable by name — import `riantr/moonbit_static_analysis/src/core` instead.
- Tests are black-box (`*_test.mbt` via `@pkg.`) and pin invariants, not snapshots — when you
  change a check, extend the invariant tests.
- Keep comments free of upstream-tool attribution (the module is standalone); the three
  inspections are 结构/类型/行为 (three-inspection, "三鉴") in Chinese prose, "lens" in code.
