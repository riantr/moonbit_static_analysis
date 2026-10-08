---
name: moonbit-scan
description: >-
  Scan ANY other MoonBit project with the three-inspection analyzer, without
  that project depending on anything. Pass a registry coordinate
  (author/module[@version]) or a filesystem path; the target is only read, never
  modified. Use this when asked to statically analyse, audit or lint a
  MoonBit codebase that is not the analyzer's own repository. For the analyzer's
  own repository prefer @pipeline.run / @moonfiles.* / @statecheck.audit
  directly, and for the analyzer's built-in demo use src/cli.
---

# Scan another MoonBit project

`riantr/moonbit_static_analysis` is a three-inspection static-analysis pipeline
(structural walk → type/symbol inference → abstract interpretation → merged
report) covering every MoonBit toolchain file kind: `.mbt`, `.mbtx`, `.mbti`,
`.mbt.md`, `.mbtp`.

## Run it

```sh
moonx riantr/moonbit_static_analysis@latest riantr/moonbit_doubleML@latest
```

The target is a registry coordinate (`author/module`, optionally `@version` or
`@latest`) or a filesystem path; omit it to scan the current directory. A
coordinate is materialised with `moon fetch` into `.repos/` and then walked.

**The scanned project neither depends on this module nor is modified.** Its
sources are only READ, at scan time, and the dependency runs one-way:
analyzer → registry → target source.

Pin a version when reproducibility matters:

```sh
moonx riantr/moonbit_static_analysis@0.4.2 riantr/moonbit_doubleML
```

> `moonx` is the recommended invocation. It downloads the **prebuilt wasm** that
> mooncakes built for the published version, caches it under
> `~/.moon/registry/cache/assets/<author>/<module>/<version>/`, and runs it with
> `moonrun` — no clone, no local build. The very same artifact is what the
> "Download wasm" button serves on skills.mooncakes.io.
>
> `moon runwasm …` is **deprecated** (the toolchain says removal after
> 2026-09-14) but still works. Prefer `moonx`.
>
> `moonx` with no package path resolves the module's ROOT package, which is why
> the command needs no `/src/sa` suffix.

## Reading the output

**The headline is parse coverage, not the finding count.** A scan reports what it
understood and what it refused to guess at:

```
EXCLUDE	_qa_verify
TARGET	D:\src\...\ML\CI	D:\src\...\ML\CI
SCANNED	85 files under D:\src\...\ML\CI
CLEAN	.mbti	D:\src\...\CI/pof/pkg.generated.mbti
FOUND	.mbt	defects=0	notices=3	D:\src\...\CI/scm/dag.mbt
PARTIAL	.mbt	defects=2	notices=1	read up to line 36, 57 after it not shown	D:\src\...\CI/pof/aggregator.mbt
12:3 - error: ... (UndefinedName) [behavior]
PARSED	32/107 files understood (29.9%); 75 more read only up to their first parse error
NOTPARSE	0 files, 6769 finding(s) withheld — they measure what this analyzer
  does not understand, not what your code does
  66x  unexpected token
      e.g. D:\src\...\CI/scm/dag.mbt
SUMMARY	files=107	parsed=32	actionable=57	notices=211	unreliable=15759	withheld=6769	total=16027	(actionable+notices+unreliable = total; withheld ⊆ unreliable)
```

- `CLEAN` / `FOUND` cover files the frontend read completely. `PARTIAL` covers
  files it read **up to the first line it genuinely failed on**; the findings
  from the tail are counted in `unreliable` and never shown, because they come
  from a tree that is already wrong.
- **Subset exclusions do not move that boundary.** Skipping a `test` block leaves
  everything after it readable, so such a file is `FOUND`, not `PARTIAL`.
- `actionable` excludes `notices` (a declaration form not analysed is not a
  defect) — otherwise the self-scan once reported "92 problems" where the true
  count was zero.
- `actionable + notices + unreliable` = `total`, asserted in the line.
  `withheld` is reported alongside it but is a subset of `unreliable` (the
  post-boundary findings of partial files whose pre-boundary finding count
  was zero), so it is intentionally not part of the sum.

**Read the output, not the exit code.** MoonBit exposes no process-exit entry
point in the available packages, so a target that could not be located still
exits 0 — it prints
`ERROR<TAB>cannot locate source for target: <target>`. A successful run always
prints a `SUMMARY` line.

### Excluding directories

```
moonx riantr/moonbit_static_analysis@latest <target> --exclude <dir> [--exclude <dir>...]
```

`--exclude` matches any path segment, and is repeatable. Use it when the tree
keeps copies of other people's code under an ordinary directory name: on one
such tree those copies were 1020 files and 126,687 findings — 88% of everything
the scan reported, none of it the target's own code. Dot-directories
(`.mooncakes`, `.repos`) and `_build` are already skipped.

## What the numbers mean, and what they do not

`.mbti`, `.mbt.md` and `.mbtp` are audited properly: on a real project they
report **0 findings** unless something is actually wrong.

`.mbt` is different. The program frontend covers a **subset** of MoonBit — no
struct literals, no `match`, no `@alias` calls, no type annotations in general
position, no lambdas or interpolation. On real code it therefore produces a large
number of findings that are **all subset edges, not defects**.

That is why the scan now withholds them. An unparsed `struct` body turns its
fields into undefined names and its `*` into operator mismatches, so the
downstream families on an unread file are noise with a real-looking shape. On a
63-file module `moon check` reports **8** unused values where this pipeline
reported **529** "unused locals" — the difference is the analyzer not seeing the
struct bodies. So: **quote `PARSED` first**, and treat `actionable` as the only
count that describes the code. Do not report `withheld` to a user as "problems
found".

## Instead of the CLI

For the analyzer's own repository, or when you want structured output, depend
on the module and call the API — `@pipeline.run`, `@moonfiles.literate` /
`.iface` / `.proof`, `@statecheck.audit`. See the adjacent
[README.md](../../README.md) and [EXTENSIONS.md](../../EXTENSIONS.md).
