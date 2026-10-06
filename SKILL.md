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
moonx riantr/moonbit_static_analysis@0.3.0 riantr/moonbit_doubleML
```

> `moon runwasm …` is **deprecated** and its prebuilt asset may be absent (404).
> Use `moonx`, as above. `moonx` with no package path resolves the module's ROOT
> package, which is why the command needs no `/src/sa` suffix.

## Reading the output

One line per file, `kind<TAB>count<TAB>path`, then a `SUMMARY` line:

```
TARGET	riantr/moonbit_doubleML@latest	.repos/riantr/moonbit_doubleML/0.107.0
SCANNED	177 files under .repos/riantr/moonbit_doubleML/0.107.0
.mbt	49945	.repos/.../quantile.mbt
.mbt.md	0	.repos/.../README.mbt.md
SUMMARY	files=177	findings=49945
```

**Read the output, not the exit code.** MoonBit exposes no process-exit entry
point in the available packages, so a target that could not be located still
exits 0 — it prints
`ERROR<TAB>cannot locate source for target: <target>`. A successful run always
prints a `SUMMARY` line.

## What the numbers mean, and what they do not

`.mbti`, `.mbt.md` and `.mbtp` are audited properly: on a real project they
report **0 findings** unless something is actually wrong.

`.mbt` is different. The program frontend covers a **subset** of MoonBit — no
struct literals, no `match`, no `@alias` calls, no type annotations in general
position, no lambdas or interpolation. On real code it therefore reports a large
number of findings that are **all subset edges, not defects**. Treat a `.mbt`
count as a rough size indicator, never as a defect list. Do not report those
numbers to a user as "problems found".

## Instead of the CLI

For the analyzer's own repository, or when you want structured output, depend
on the module and call the API — `@pipeline.run`, `@moonfiles.literate` /
`.iface` / `.proof`, `@statecheck.audit`. See the adjacent
[README.md](../../README.md) and [EXTENSIONS.md](../../EXTENSIONS.md).
