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
moon check --deny-warn      # 0 errors, 0 warnings — first gate
moon fmt                   # format; `moon fmt --check` must stay clean
moon test --target js      # 73/73 (see the breakdown below)
moon run src/cli           # program demo + file-kind demo + sample machine audit
moon prove src/core --why3-config .why3.conf   # formal verification (19 lemma VCs)
```

`--deny-warn` matches what CI actually runs. The official package-configuration page
requires it in CI; without it a warning regression passes silently while the READMEs
claim "0 errors, 0 warnings".

The test breakdown is 4 targets × 59: pipeline, moonfiles (literate / .mbti /
.mbtp), parser (.mbtx import block), statecheck, walk/types/interp.

**`pkg.generated.mbti` is tracked.** Changing a public surface (`pub`, `pub(all)`,
a struct field, an enum constructor) requires `moon info`, and the regenerated
files must be committed — otherwise the committed interface describes a module
version that no longer exists. A brand-new package gets its `.mbti` from the
same run; it will not appear on its own.

pyroduct gates (run inside `pyroduct/`): `moon check`, `moon fmt --check` both pass;
`moon test` was **190/192** as of 2026-10-06 — the two failures are in
`audit/fleet_test.mbt` (lines 152 and 202, the mutation-harness family checks) and
are NOT caused by the analyzer: `v0.1.2..v0.2.0` left `src/statecheck`,
`src/core` and `src/report` — the only packages pyroduct imports — byte-identical.
Re-measure before quoting a number.

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
- `.mbt.md` — only fences the toolchain actually compiles (`mbt check` / `mbt test`,
  and the `moonbit` spellings) are three-inspected, with line numbers aligned to
  the .md file. A second word of `check` or `test` is what makes a block live
  code. A bare `mbt`, a bare `moonbit` and `nocheck` are display-only and are
  SKIPPED. Measured against the toolchain, not taken from doc wording — see the
  fence table in EXTENSIONS.md.
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
- Check `moon whoami` first — login is permanent until the token rotates.
- `moon publish --dry-run` first. **`--dry-run` ALWAYS exits non-zero with
  "Error: `moon publish` failed" even on success** — by design, since it does
  not upload. Read the line above it: `202 Accepted ... Dry run completed
  successfully` is the real signal. Do not re-bump the version because of it.
  The run packages the zip, extracts it, re-checks the extracted package, and
  POSTs — so a 202 does verify the package is publishable.
- Then `moon publish` for real: expect **200 OK**, which appears on stdout.
  PowerShell mangles both streams (`2>&1` loses output, exit reads as -1); to
  see the real status use
  `Start-Process moon.exe -ArgumentList publish -NoNewWindow -Wait -PassThru -RedirectStandardOutput out.log -RedirectStandardError err.log`.
- Git remotes: `origin` = Gitee (primary), `github` = mirror; tags stay in lockstep with the
  moon.mod version (v0.1.x). Push master + tag to both.
- Registry README is the moon.mod `readme` file (Chinese `README.md`; English twin
  `README.en.md` cross-linked).
- After publishing a new version, bump `pyroduct/moon.mod`'s
  `riantr/moonbit_static_analysis@<ver>` and run `moon update` there, then the pyroduct gates.
- Version policy: this module is `0.x`. `PipelineResult` gained the public
  `imports` field in 0.2.0 — a `pub` struct gaining a field breaks any
  consumer that constructs it, so that is a MINOR bump (0.1.x -> 0.2.0), not a
  patch. Check the registry manifest before choosing a number:
  `https://mooncakes.io/api-new/v0/manifest/riantr/moonbit_static_analysis`
  (returns the latest version plus the full version list; a version-specific
  URL 404s).
- The public surface splits in two, and they move independently:
  `@statecheck` (machine tables) is what pyroduct consumes — its `audit/audit.mbt`
  only calls `@statecheck.audit` / `.render`; **`@pipeline` / `PipelineResult`
  is consumed by the JSON bridge and the DSH plugin, not by pyroduct**, and
  nothing outside this module constructs that struct. So a `PipelineResult`
  change has no effect on the machine-table consumer, and pyroduct is safe
  on the old pin until you deliberately move it. Bump the pin for hygiene, not
  because something is broken.
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
