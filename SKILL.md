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
moonx riantr/moonbit_static_analysis@0.4.25 riantr/moonbit_doubleML
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
tasks) the 80 generated `pkg.generated.mbti` files produced **93** actionable
findings, every one of them false. Three causes, and the first two are now
fixed:

- the lens had **its own** builtin list, 33 names, while the `.mbt` walk had a
  different one of **three** (`print`, `len`, `abs`) and no type names at all.
  MoonBit makes `moonbitlang/core/builtin` available without an import, so
  `debug/pkg.generated.mbti` uses `Hasher`, `Iter2` and `ArgsLoc` bare with
  **no import block in the file at all**, and each was reported as an unknown
  type. All three frontends now share one list (`@core.ambient_names`, read out
  of the toolchain's own `lib/core/builtin/pkg.generated.mbti`). That alone
  removed 80 of the 93 — `Iter` 60, `Iter2` 12, `ArgsLoc` 4, `Hasher`,
  `MutArrayView`, `UninitializedArray`, `Failure`;
- a `const`'s default value used to be scanned for type references, so
  `pub const MAX_VALUE : Byte = b'\xFF'` reported `unknown type 'b'` and
  `unknown type 'xFF'`. Fixed;
- **still open**: the lens has no cross-file awareness — it consults neither
  the cross-file symbol table nor the packages a `.mbti` imports. So the
  remaining **13** (`Show` 5, `InspectError` 3, `SnapshotError` 2, `Logger`,
  `ToJson`, `BenchError`) are types genuinely declared in a sibling file.

So an `unknown type ... in interface signature` finding on a `.mbti` should
be treated as **unverified**, the same way a `.mbt` finding past the
`PARSED` boundary should be — not as a defect to report to a user.

`.mbt` is different. The program frontend covers a **subset** of MoonBit — no
`match`, no `try` bodies, no lambdas, and no full modelling of a string's
interpolation: `\{expr}` is consumed and its **names** recorded as reads, but
the expression itself is not parsed, so `\{a + b}` makes no claim about the
addition. Method calls ARE modelled (`EMethodCall`). The subset boundary that
actually costs the most is `match`: it parses, but its arms are skipped whole,
which is why frame-scoped families are suppressed for any function containing
one. On real code the frontend therefore still produces many findings that are
**all subset edges, not defects**.

That is why the scan withholds them. An unparsed `struct` body turns its
fields into undefined names and its `*` into operator mismatches, so the
downstream families on an unread file are noise with a real-looking shape.

The families that could not be silenced that way are the ones whose verdict is
about a whole **function** rather than a line: `UnusedLocal`, `UnusedParam` and
`ParamChanged` are decided when the function's frame is audited, so a function
the frontend truncated halfway cannot support "this was never read". Those are
now skipped outright for the one function a read failure could have cut — the
other functions in the same file keep their verdict. On `moonbitlang/core` that
took actionable findings from 270 to 147; on this repository, from 11 to **0**
(verified one by one: each was a binding read below the boundary). So:
**quote `PARSED` first**, and treat `actionable` as the only count that
describes the code. Do not report `withheld` to a user as "problems found".

The same argument extends past the function frame to the **module** frame, and
that is worth stating as a general rule because it is easy to get backwards:
**"not found" and "does not exist" are different claims, and a report must
distinguish them.** Any assertion resting on a lookup has to ask whether the
table doing the lookup is complete. On a file the frontend did not finish, the
module frame is provably incomplete, so `UndefinedName` is withheld there — on a
whole file it stays exactly as loud. Two name shapes also turned out not to be
bindings at all: a `Type::member` path (`@debug.Repr::opaque_(v)`), which is a
member reference for the same reason a field name and a method name are; and the
name of an `extern "c" fn`, which was being skipped as an unmodelled declaration
form, so every call site of an extern function read as unbound. Measured on
`moonbitlang/core`: actionable **270 → 49**, undefined names **64 → 0**, parsed
**305 → 320**.

### Two more "not found ≠ does not exist" boundaries

**A substitution skip is a hole in the frame, even when the file parses fine.**
A `match`, a `try`, or an fn literal is a *declared* scope limit: it moves no
error line, it costs no coverage, and the rest of the file stays readable. But
the region it skipped is exactly where a binding's only assignment could be, so
a function containing one cannot support "this was never read" either. Those
functions now skip the frame audit too — a second boundary, independent of
`first_error_line`, because it guards a different fact. This needs the
function's *whole extent*, header to closing brace, not just its signature:
that is why `SFunc` / `SLocalFunc` carry a body-covering span. On this
repository it took actionable findings from **104 to 8**.

**A name read through a string interpolation is a read.** `\{x}` is copied raw
into the string payload, so before this the literal was opaque to every lens:
a name read ONLY that way looked unread, and — worse — a name that does not
exist inside an interpolation was never reported at all. `TStr` now carries the
names its interpolations reference and the structural walk resolves them. All 8
findings that survived the previous step were this: `mermaid.mbt` `anchor`,
`pipeline.mbt` `i`/`s`/`r`, `parser.mbt` `what` ×2, `interp.mbt` `name`,
`cli/main.mbt` `live`. Actionable **8 → 0**.

### Two shapes that fail toward silence, not noise

Both measured on this analyzer's own source in 0.4.10, and both are the reason a
clean scan of a multi-file package is not by itself proof of anything.

**An `if` expression's branches are read and then discarded.** `let x = if c {
… } else { … }` is outside the subset; the notice says so. A name that does not
exist inside such a branch is therefore **never reported**. 0.4.8's self-scan
was clean partly for exactly this reason: two calls sat in a dropped
if-expression, and moving them into a plain function turned the `if` into a
statement — which is parsed in full — exposing two latent false negatives at
once.

**Package-private helpers in a sibling file: FIXED in 0.4.12.** This used to be
the single largest source of findings on real code — measured on `riantr/pyroduct`
0.1.29, 26 of the 31 actionable findings after every other false positive was
fixed were one shape, each a private `fn` in a sibling file of the same package.
Cross-file resolution went through `.mbti` alone, and a package-private `fn` is
in none of them, so a call to one read as `no visible binding`. The only fix
available from the CLI was making such a helper `pub`.

Since 0.4.12 the analyzer reads the target's own `.mbt` files instead: one symbol
table per **directory** (a MoonBit directory *is* a package), carrying the
top-level declarations its files make — the private ones included — and only
files in that directory see it. The scan prints what it harvested as
`PRIVTAB packages=N names=M`, so a table that found nothing and a harvest that
never ran do not look alike.

Two consequences worth knowing:

- The table is per-directory, so a private name in one package never suppresses a
  finding in another. If you see an undefined-name finding for a name you can see
  declared in a *different directory*, that is correct — cross-package access
  needs an import.
- A name harvested this way resolves to "a value of unknown type", the same shape
  a name from another package gets. It silences an undefined-name finding and
  infers no type or arity it has not read.

**`list indices must be int` now fires only on a real list (since 0.4.13).** A
`Map[K, V]` is indexed by its KEY, so `m["k"]` on a `Map[String, Int]` is correct
code; before 0.4.13 it was reported as a type error at `error:` severity, which
put findings on files `moon check` accepts with zero errors (measured: 2 on
riantr/pyroduct 0.1.29, `src/paths.mbt`). The check is gated on the base being a
known list, and `Array[T]` is read as one — the parser keeps the `[...]` and the
type lens models it. A subscript on a base whose type was NOT read stays silent,
which is the quiet direction: `m["k"]` on a `Map` and on a value of unknown type
look identical from here, and neither is evidence of a defect.

So on `Array`/`[T]` bases the check is live and matches the compiler; on a `Map`,
or on anything unannotated, expect silence. That asymmetry is intentional.

**A `_`-prefixed binding is exempt from both usage findings (since 0.4.13).** The
bare `_` always was; a leading underscore now is too, matching the toolchain.
Probe: `_f` / `_classes` / `_ok3` and a non-underscore `plain` control in one
file, `moon check` warns on `plain` and on nothing else. Before 0.4.13 the
analyzer exempted only the exact name `_` and reported underscore-prefixed names,
on the stated reasoning that "a name is not a discard pile" — an argument, never
measured, and the compiler contradicted it (measured: 2 of the 5 findings
remaining after 0.4.12, `src/algebra.mbt` and `audit/mbti.mbt`). `FParamChanged`
is unaffected: an underscore-prefixed parameter that is *assigned* is still
reported, which is a different question from whether it was read.

**`self` inside an interpolation is a read (since 0.4.13).** `self` is a
conventional parameter name, not a keyword. The lexer used to list it as one, so
`"\{self.designation()}"` recorded no read and a parameter read only inside an
interpolation was reported as unused (measured: `src/slot.mbt` 127) while the same
read in a plain expression was already silent. If you see `no visible binding` for
a name used only inside `\{...}`, that one is real and worth reporting.

**Numeric literals are read as numbers, not as token kinds (since 0.4.14).**
This matters most because the alternative is invisible: before 0.4.14 a float
literal folded to its *truncated integer part* (`1.5` → 1, `0.25` → 0, `3.14159` → 3),
which emits no finding at all — the analyzer was simply wrong about every float it
read, silently. Three literal forms were also unmodelled and produced false
positives:

- `0.0F` (float32 suffix) lexed as `0.0` plus the name `F`, giving
  `undefined name 'F'` — 28 such findings on riantr/snn_mbt, the largest single
  bucket found on any corpus so far. `7F` is a genuine parse error, so the suffix
  is only consumed on a literal that already has a fractional part.
- `1.0e-12` lexed as `1.0` plus the name `e`, giving `undefined name 'e'` (and
  `undefined name 'e300'` for `1.0e-300`, which is the tell that this is a
  tokenization split rather than a real reference). An `e` with no digits after it
  is still a name: `1.0echo` is the float `1.0` followed by `echo`.
- `/` was typed as float division. In MoonBit `7 / 2` is `3`; the analyzer said
  `float`, which produced `cannot assign 'float' into '[int]'` on correct code
  (14 findings on riantr/moonbit_doubleML).

If you write an assertion about a numeric literal, read its **value** or its
**token count**. Asserting only that the kind is `float` passes just as happily on
a truncated one — that is how the value bug survived every previous release.

Known and deliberately unchanged: the constant-evaluation layer still types `Int/Int`
as a float and does not fold it (`walk.mbt`, `interp.mbt`). Both were implemented and
measured in 0.4.14; reverting either changed nothing across 933 files on four corpora
and no test could distinguish them, so they were reverted rather than shipped as an
undemonstrable fix. If you find code where that matters, that is the finding that
would justify changing it.

**A unit enum variant is not an undefined name (since 0.4.15).** `Layer::ReLU` and
`LayerGrad::Empty` were reported `undefined name`, while the payload variant beside
them in the same enum — `Layer::Conv2d(p)` — resolved. The enum harvest stores the
BARE name (`ReLU`) because it reads tokens, and the bare reference `Layer::ReLU`
carries the whole path. A qualified path now falls back to its last segment, but only
after the whole path has failed, so `Colour::Purple` (never declared) is still
reported. Probe: `enum Colour { Red Green } ... Colour::Green` compiles with 0 errors;
the analyzer reported 4 such findings on riantr/snn_mbt.

**`==` / `!=` between two Bools is legal (since 0.4.15).** The type lens rejected it
as "unsupported operand types for '==': 'bool' and 'bool'". Probe: 0 errors, 0
warnings. Ordering (`<`, `>`) between Bools is NOT extended and is still reported —
the fix widened equality, not comparison.

**A parameter of an `extern "C"` / `extern "wasm"` function is not unused (since
0.4.15).** Its body lives in another language, so the analyzer never read it and
reported "parameter 'x' may not be used" on 6 functions in riantr/snn_mbt. Note that
"the body is empty" is NOT a usable proxy — a normal `fn p7(z : Float) -> Float { }`
warns in `moon check` too, so the parser records extern names explicitly and the
walker skips the frame audit for exactly those.

**A cross-file `const` is not a function (since 0.4.16).** The `.mbti` reader already
told `pub const X : T` from `pub fn f(...) -> T` and discarded the difference. So
`3.0F * hz`, with `hz` a `const hz : Float` from another package, was reported as
"unsupported operand types for '*': 'float' and 'fn hz (signature not read)". The
`Bool` in `IfaceSymTab.values` is now `is_const`; a constant types as `TUnknown` and a
function still types as `TUnknownFn`, which is what keeps the arity check off.

**A braced `suberror` body is skipped whole (since 0.4.16).** `suberror` has two
shapes — `suberror Timeout of String` and `pub suberror DecodeError { ... }` — and
both went to the "skip to end of line" path, so the braced body was parsed as an
expression block and every payload type in it was reported undefined (`String`, four
times, on riantr/moonbit_image).

**A method of a builtin type is not an undefined function (since 0.4.17).**
`Array::make(total, Byte::default())` on riantr/moonbit_labeler was reported as
`undefined function 'Array::make'` on a line `moon check` accepts. The ambient
list carried the builtin TYPES and the top-level builtins, and nothing in
between. `src/core/builtin_methods.mbt` is a generated table of the 656 measured
names — 642 read out of the toolchain's own `moonbitlang/core/**/pkg.generated.mbti`,
plus 14 compiler builtins (`Array::make`, `Map::new`, `StringBuilder::new`, …)
that no interface declares, each settled with `moon check`. It is a table and not
the rule "a call qualified on a builtin type is a builtin method" because that
rule also silences `Array::mkae`, and `Array::mkae` is still reported.

**An enum variant in a SIBLING file is not an undefined name (since 0.4.17).**
The 0.4.15 fix resolved a unit variant written as a path, `Layer::ReLU`. A BARE
reference from another file in the same package was still reported:
`canvas_view_test.mbt:4917` writes `[Select, Rect, Polygon, Keypoint,
EditBinding]` for an `enum Mode` declared in `app_mbt` next door. The name
harvest collects top-level declarations only, and a variant is brace-declared.
Variants are now harvested from the enum body — but a payload's TYPE is not a
variant, so `Conv2d(Params)` does not make `Params` package-visible.

**A nested unknown callee hides the ones around it (known, as of 0.4.17).** A
call that reports returns `ABottom` and the enclosing call is not visited, so a
chain of unknown callees in one expression yields ONE finding — the innermost.
Reading that as "each fix reveals the next one forever" is a mistake: the family
ends when the callees are known. But it does mean a single line can carry more
than one real defect, and the count you see is a floor.

**KNOWN GAP, CORRECTED: an unresolvable qualified call IS reported (as of
0.4.17).** Earlier revisions of this file called it a known gap and wrote that
qualified names were under-reported as the mirror of what 0.4.14–0.4.16 fixed.
That was wrong, and the reason is worth knowing because it produces false
conclusions about reachability: the fixture never CALLED the function, so the
behavioral lens never visited the body. Reach it and `Nope::also_missing()` is
reported like any other name. The behavioral lens analyzes a body only when a
top-level statement reaches it — a large private helper nobody calls will
produce far fewer behavior findings than its size suggests.

**Six shapes that are real MoonBit and used to end the file (since 0.4.18).**
Measured on wzzc-dev/moui 0.1.12, a package `moon check` runs through:

- `&T` in a type annotation is **`Ref[T]`, not a reference type**, and `T` must be
  a trait — `moon check` reports `The type Node is not a trait` and types the
  binding `@moonbitlang/core/ref.Ref[Node]`. It reads as `TUnknown`, the same
  answer `Map[K,V]` gets.
- `~` is the label sigil and has TWO sides: `f~ : T` declares a parameter that
  must be passed BY LABEL, and `x~` is the shorthand for `x=x`. It never changes
  a parameter's name, so it never changes an arity.
- `fn[T]`, `fn[T : Bound]` and `extern fn[T]` carry a type-parameter list. It is
  consumed and discarded: the type variable is not a parameter type, so nothing
  downstream reads it.
- `b"..."` is a byte-string literal. It looks like an identifier followed by a
  string, and the pair ended the file.
- `{ ..base, f: v }` is the struct update. Its base is pushed under an EMPTY
  field name, which keeps the reads (all three consumers destructure
  `let (_, v) = f` and traverse only the value) without inventing a field.
- A `.` at STATEMENT position continues the PREVIOUS line's expression. This is
  by far the most common of the six — 1124 lines across 131 files.

**KNOWN GAP: the shape harvest that feeds the SIBLING table is a second, separate
name reader (as of 0.4.18).** When a new declaration form is taught to the parser,
the name harvest does not follow automatically. `fn[Msg] feedback_panel(` was
parsed correctly but never entered the package-private table, so all four of its
call sites in two other files were reported "no visible binding". If a scan
reports a sibling function as undefined, check the FORM of its declaration
before assuming the scope logic is wrong.

**KNOWN GAP, and the cause is not the analyzer: a blocked file poisons its own
package's names (as of 0.4.18).** The sibling table is filled from files that
were read successfully, so a name declared in a file that stopped at a parse
error is invisible to every other file in the package. Raising parse coverage
removes these findings as a side effect; fixing them one at a time does not.

**KNOWN GAP, still open (as of 0.4.18): a leading `is` expression.** `is` is
matched by NAME and the parser requires a left operand, so an expression
statement that is just `is Some(_)` — MoonBit's newline-tolerant matcher on the
preceding line — is read as the bare name `is`. NOT settled as of 0.4.19: a
minimal `moon check` probe could not reproduce a legal form of it, so no fix was
written on an unverified reading. Treat the semantics as open.

The SECOND half of that entry is fixed in 0.4.19: `parse_is_pattern` no longer
binds the literal in `if x is Some(true)`. The test is
`@lexer.is_moonbit_keyword`, not a private copy of the list — that table already
holds `true`/`false` and documents why `self` is deliberately excluded, so
`if x is Some(self)` still binds.

**KNOWN GAP, still open (as of 0.4.18): an untyped `self` in
`impl ... with fn layout(self, context)`.** The sentinel logic in
`skip_decl_braced` gives up on the impl body and re-reads `fn layout` as a
top-level declaration, so the method's own parameters are not bound. Typed
parameters (`self : Pos`) do not hit this. As of 0.4.19 this is 4 of the 14
actionable findings in moui and covers 1047 declarations across 204 files — it
is now the single largest false-positive class by declaration count.

**A function type is a valid annotation (since 0.4.19).** `(A) -> B` in a
parameter annotation is 845 sites across 171 files of moui. The elements are read
by `type_annotation` itself, so `((String) -> Msg)?` nests with no special case.
`ann_to_ty` returns `TUnknown` deliberately — the lens models no function types,
and unknown is what keeps operations on one quiet.

**KNOWN GAP, largest by finding count (as of 0.4.19): a named argument is
matched POSITIONALLY.** `ECall(String, Array[Expr])` carries no label — the
parser drops them — so a call that OMITS defaulted parameters and passes the rest
by label is compared against the declaration in order.
`ActionCommand::new(intent=…, label=…, group=…, description=…, shortcut=…)` has 7
declared parameters, the first 5 of the call skip `enabled`, and `description`
(String) is checked against parameter 4 `enabled` (Bool). That is 5 false
positives in moui from one declaration. A correct fix carries the label through
the AST and matches by name.

**KNOWN GAP (as of 0.4.19): `expr as Type` is a cast and is not modelled.** `as`
is a keyword, falls through, and is reported as an undefined name. 29 sites
across 21 files in moui. There is no `ECast` node; adding one is the fix and it
was not attempted.

**NOT the analyzer (as of 0.4.19): a stale `pkg.generated.mbti`.** `moon test`
compiles from SOURCE; only the SELF-SCAN reads the git-tracked `.mbti` interface
files, and neither `moon update` nor `moon doc` regenerates them. A newly
exported symbol can therefore be absent with every test green — it bit 0.4.18
with `TTilde`. A self-scan reporting `undefined name '<a name you just added>'`
is this, not a code bug.

**An `impl ... with fn` method is not a top-level function (since 0.4.20).**
Two independent bugs, in two independent readers, and the same root cause twice.

- In `skip_decl_braced`, the `fn` sentinel exists for `pub impl Eq for T` — no
  body, methods in a separate block. But `impl T for U with fn m(...) { ... }`
  puts a `fn` INSIDE the declaration, and the sentinel fired, leaving the body
  behind. `with` is the discriminator: it cannot appear in the bodiless form.
- In `collect_declared_names`, the `with fn` header is written at depth 0 — the
  brace comes after the parameter list — so the harvest recorded the METHOD as a
  package-level value. Any call to that name anywhere in the package then
  resolved to "defined".

Note the mechanism that made the first test hollow: **`Parser::skip` records a
note and consumes nothing.** Before the fix the top-level loop re-read the
`with fn` as an ordinary top-level function, so `self` was bound all along and a
test asserting "no undefined `self`" was green either way. The property that
actually changed was the harvest.

**A `trait`'s own name is still a package-level type.** Skipping the whole
holder loses `trait Marker`'s `Marker`, which is declared here — `impl Eq for T`
and `extend` declare nothing, since `Eq` is the trait being implemented.

**THE PATTERN, seen twice now (0.4.18 and 0.4.20): there are TWO name readers.**
The PARSER skips declarations; `collect_declared_names` is a separate token
scanner that fills the sibling/private table. Teaching a new declaration form to
one does nothing for the other. Both times, the symptom was a name that was
either missing from the package or present when it should not be — and neither
showed up in the actionable count, because a fabricated binding is a false
NEGATIVE and a missing one is masked by a re-read. When you change how a
declaration form is skipped, check whether a gate covers the harvest too.

**`guard COND else { ... }` is a statement, not an identifier (since 0.4.21).**
`guard` is NOT in the lexer's keyword list, so it was read as an ordinary
IDENTIFIER and reported as an undefined name — 550 sites across 126 files. It is
modelled as an `SIf` with an empty `then`, which is the honest mapping for a frame
model that is not flow-scoped: the condition is walked FIRST, so an `is` pattern in
it binds in the current frame exactly where a guard binding belongs. The `else`
block is analyzed like any other block.

**An `if`'s branches are JOINED, not chained (since 0.4.25).** This is the other
half of the `guard` mapping above, and it is where `guard` was paying for it. An
unknown condition's branches are explored ONE AFTER ANOTHER in the same `Interp`,
so before 0.4.25 the flow state simply carried over between them: a branch that
terminated made the NEXT branch's first statement look unreachable, and whatever
the LAST branch left behind was what survived past the whole `if`. With `guard`'s
empty then-branch, `guard g is Some(v) else { return 0 }` followed by `return v`
reported a FALSE `unreachable code` — the else terminates, the then does not, and
the else's flow won the race. It reproduces with no `raise` anywhere.

Each branch now resets `self.flow = FNormal` before running and contributes
`falls = self.flow == FNormal` after; a **missing `else` is always `falls = true`**;
the join is `self.flow = if falls { FNormal } else { FReturn }`. `exec_alt`
returns `Bool` and joins the same way. So every branch terminating is STILL
reported as dead code — the fix makes false positives go away without making the
check unfireable.

MEASURED across six corpora and 12,428 files: every scan byte-identical before and
after, `Unreachable` 0 → 0. **A correctness fix with a reproducer, not a cleanup.**
An `ABottom` condition keeps its old meaning (does not terminate, falls through) —
whether a bottom condition should suppress everything downstream is a separate
open question this does not answer in either direction.

**A pattern in `is` binds EVERY name, at EVERY depth (since 0.4.21).** The rules
collapse into one predicate, `Parser::pattern_binding_at(j)`, called from both the
tuple branch and the single branch — a second reader is how 0.4.18 and 0.4.20 each
lost a cycle, so it takes an index and cannot drift:

- not `_`, not a keyword
- the next token is not `(` — a nested CONSTRUCTOR, not a binding
- neither neighbour is `.` — `@core.Role::Checkbox` is a qualified path (18 sites)
- the first `:` ends it — the rest is a type annotation; `::` lands on the same rule

**The two branches do NOT collect at the same depth, and that is not an oversight.**
The tuple branch's outer `(` is a GROUPING paren, so its bindings live at `depth >=
2`. Without that, `is (Gone | PageUnavailable)` — an or-pattern in
`proton internal/bridge_admission_test/main.mbt:93` — bound both constructors and
reported two nonexistent unused locals. One of them was NEW: the old reader stopped
after the first name, so it had only ever bound `Gone`. **A finding-level
differential over the corpora is what found this; reasoning about it did not.**

**Corollary for gates: `n_parse == 0` is not evidence.** A shape that leaves the
token stream in step produces a file that PARSES with no error and a tree whose
every later name is wrong (0.4.21's newline continuation: 15 findings, none reported
as unreliable because nothing failed). Assert on names AFTER the construct. The
matching control is that the construct does not swallow the rest of the body —
`zzz_after` must still be reported — because a swallowed statement cannot produce
a finding and would leave every count green.

**A short lambda's BODY is skipped, never analyzed.** `at_lambda_head` /
`skip_lambda_head` consume the parameters and the `=>`, then the caller skips the
body. So a fixture for a named-argument lambda can assert `n_parse == 0` and that
the REST of the argument list still parses, but **cannot** assert anything about
names inside the lambda body — they were never walked.

**KNOWN GAP (as of 0.4.21): calling a FUNCTION-TYPED PARAMETER reports
`undefined function`.** `let f = inc` then `f(1)` does it, with no lambda anywhere
in the file. It arrives with 0.4.19's function-type annotations and is unrelated to
them being an `is`-pattern issue. Gate fixtures that would trip it must have the
callee read a different parameter.

**KNOWN GAP (as of 0.4.21): a TYPED pattern, `is Some(x : Int)`, is unverified.**
Zero sites corpus-wide — all 18 `is X(...)` matches containing a colon are qualified
paths like `@core.Role::Checked`. The `:` rule is in place, but nothing in the corpus
exercises it, so do not claim it covered without settling one first.

**The `moon check` settle recipe.** A package is a directory with a `moon.pkg`
file, and the sources live under `src/`; without `moon.pkg`, `moon check` reports
"no work to do" and looks like a pass. Put the probe OUTSIDE any enclosing project
— moon walks up and resolves the outer `moon.mod`, and an inner `moon.mod` is
ignored.

**The CI toolchain is UNPINNED and the formatter is not stable across moon
releases.** Both workflows install `latest` via `install/unix.sh`. On 2026-10-12
the `v0.4.21` tag went red at `moon fmt --check` while `moon check` was green,
and the already-shipped **v0.4.20 tag was red too** — so when a gate step fails,
**test the previous tag before blaming your change**. Pinning is NOT the fix:
`MOONBIT_INSTALL_VERSION` is honoured by the installer, but old Linux binaries
have already been pruned from the CDN and `Install moon` fails outright. The
formatter's rewrite is not whitespace either — it changed
`options("proof-enabled": true,)` to `proof_enabled = true` and `Int` to
`Int32`. Measure the effect before accepting it: the un-reformatted source still
passes check and every test under the new moon, and afterwards all six corpora
were byte-identical.

**A mutation script's multi-line patterns must normalise line endings.** `moon
fmt` flipped every `.mbt` from LF to CRLF in that release, and the gate script
itself stayed LF because it is not MoonBit source. Every multi-line pattern then
matched nothing and six of eight mutations reported NO-OP. NO-OP counts as a
failure, so the gate still failed loudly — but a gate that silently stops
matching is one edit from being decorative. Normalise both sides, write back in
the file's existing style, and keep the SHA256 restore assertion: it is what
proves the round-trip.

If you are scanning a package whose dependencies you care about, pass
`--extern-iface-dir .repos`. Without it the analyzer cannot see cross-package names at
all and says so in its own output: measured on riantr/moonbit_labeler, it goes from 5
findings to 2.

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

### Naming the artifact: what was read, by what, and when

`@sa.provenance_for(target, root)` collects four facts and
`@sa.scan_artifact_name(prov, root)` lays them out —
`<package>_<version>_<moonbit>_<UTC stamp>.mmd`, e.g.
`moonbit_static_analysis_0.4.7_0.1.20260920_20261009T155222Z.mmd`.

Read that name as provenance, not decoration: it is what distinguishes two
scans of the same tree. `package` is the coordinate, or the **resolved**
directory for a path. `version` comes from the coordinate's `@version` or the
target's `moon.mod`. `moonbit` is the toolchain that did the reading, from
`moon version` — it cannot be recovered from the tree, and it is the field that
decides whether two results are comparable, because this analyzer's `.mbt`
subset moved from 158 to 173 files on an unchanged checkout when method calls
were modelled. `unknown` in any slot means it could not be determined — not that
the value was `0`, and not that the segment may be dropped, because with four
fields a dropped segment SHIFTS every later one. The same facts are repeated
as `%%` header comments inside the document, because files get renamed.

### Rendering the result as a state diagram

`@sa.mermaid_states(verdicts, summary, prov, per_file, max_files)` emits a
mermaid `stateDiagram-v2` built for an agent to read: each file is a box whose
spine is the trust chain (`lexed → structural → type → behavioral`), each
finding is its own state hung off the inspection that reported it, and each one
carries a `WHY:` / `HOW:` note from `@core.Family::advice` saying why it was
judged wrong and what to change.

To produce one from the CLI instead of writing a program, pass `--mmd <path>`
or `--mmd-auto`. Both *also* write the file and print `MMD<TAB><path>`; the
text report on stdout is unchanged and stays authoritative. Treat the drawing
as a supplement, never a replacement: it is lossy by construction, ranking
files by actionable count and stopping at its own cap, and it says so in a
`%% THIS DRAWING IS A SUBSET` comment. All four provenance fields are real on
this path; only the toolchain lookup can degrade, to `unknown`, if the `moon
version` subprocess fails.

Two caveats travel inside those notes and must not be skipped: on `.mbti` /
`.mbtp` / `.mbt.md` a `ParseError` is usually a frontend rule rather than a
parse boundary, and `UndefinedName` cannot see a `#doc(hidden)` API (it appears
in no `.mbti`) or a `@pkg.fn(1, 2)` top-level reference (not folded into a
callable name).

`per_file` and `max_files` cap the drawing (`0` = no cap) and whatever is
dropped is stated in the diagram itself, so a truncated diagram never reads as a
clean one. `summary` always describes the whole scan while the drawing may be a
subset; files are ranked by ACTIONABLE count, because the largest raw-finding
file on moonbitlang/core is a 402-finding test file that is all notices and zero
defects.
