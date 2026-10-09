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
moonx riantr/moonbit_static_analysis@0.4.4 riantr/moonbit_doubleML
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

### Cross-file type resolution

A `.mbt` that uses a type from another package (e.g. `Command` from
`@argparse`) would normally fire `undefined name 'Command'` because the
single-file analyzer only sees the file it is reading. Two flags teach it the
missing names:

```
moonx riantr/moonbit_static_analysis@latest moonbitlang/pdf2md@0.1.1 \
  --extern-iface-dir .repos
```

`--extern-iface-dir <dir>` is repeatable. Every `.mbti` file under the named
directory is parsed and its declared types + value signatures enter the
**cross-file symbol table** the structural walk and the type lens consult
before reporting `FUndefinedName`. The natural target is `.repos/` after you
have `moon fetch`ed the dependencies you want indexed. The target's own tree
is always indexed.

By default the analyzer also reads the target's `moon.mod` and `moon fetch`es
each direct import (so the simple case needs no extra flags). Pass
`--no-auto-fetch-deps` to skip the auto-fetch. Only the real `import { … }`
block is read: a `//` comment that happens to contain the word "import" does
not open one, and a URL is not mistaken for a coordinate. Each import that
could not be fetched is named on its own line, because its types are then
absent from the table.

Dot-directories under the **target** are skipped (they hold a dependency's
code, not the target's), and the count is printed so a reader knows the table
is not complete. Directories you name yourself are read in full, dot entries
included — that is what pointing at `.repos` means.

The table is consulted by all three lenses, which is the point: the structural
walk does not report the name, the type lens returns `TUnknown` for a type
elsewhere and `TFunc(name, [TUnknown], TUnknown)` for a value, and the
behavioral lens dispatches a known-but-unread callee as an
unknown-returning call instead of calling it undefined. Names absent from the
table still report, so the table never invents valid bindings — it only
suppresses, never the other way around.

## What the numbers mean, and what they do not

`.mbt.md` and `.mbtp` are audited properly: on a real project they report
**0 findings** unless something is actually wrong.

**`.mbti` is NOT.** It used to be claimed here alongside the other two, and
that was wrong — measured, not suspected. On `moonbitlang/core` (1029 files,
which `moon check --target all` accepts with 0 errors and 1 warning across 716
tasks) the 80 generated `pkg.generated.mbti` files produced **97** actionable
findings, every one of them false. Two causes:

- the lens has no cross-file awareness at all — it consults neither the
  cross-file symbol table nor the packages a `.mbti` imports, only a
  hardcoded 33-name builtin list. MoonBit makes `moonbitlang/core/builtin`
  available without an import, so `debug/pkg.generated.mbti` uses `Hasher`,
  `Iter2`, `ArgsLoc` and `InspectError` bare with **no import block in the
  file at all**, and each one is reported as an unknown type
  (`Iter` 60, `Iter2` 12, `Show` 5, `ArgsLoc` 4, `InspectError` 3,
  `SnapshotError` 2, and seven singletons — 93 in all, counted from the scan
  output rather than summed by hand);
- a `const`'s default value used to be scanned for type references, so
  `pub const MAX_VALUE : Byte = b'\xFF'` reported `unknown type 'b'` and
  `unknown type 'xFF'`. Fixed.

So an `unknown type ... in interface signature` finding on a `.mbti` should
be treated as **unverified**, the same way a `.mbt` finding past the
`PARSED` boundary should be — not as a defect to report to a user.

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

The same discipline applies to `actionable` itself: a finding is only as good
as the oracle it was checked against. Every actionable finding the analyzer
reported on `moonbitlang/core` was a defect **in the analyzer**, found by
running `moon check` over the same tree and comparing. A large project the
toolchain accepts is the only oracle that catches a lens inventing a claim
about code it could not read.

## Instead of the CLI

For the analyzer's own repository, or when you want structured output, depend
on the module and call the API — `@pipeline.run`, `@moonfiles.literate` /
`.iface` / `.proof`, `@statecheck.audit`. See the adjacent
[README.md](../../README.md) and [EXTENSIONS.md](../../EXTENSIONS.md).
