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

## 0.4.11 — the first external scan: 4 fixes, all measured on real code

The analyzer was pointed at a package it had never seen:

```
moonx riantr/moonbit_static_analysis@latest riantr/pyroduct@latest
```

119 files, 87 parsed, **actionable 43**. Triaging the 43 instead of counting
them found 30 that were analyzer defects. Four fixes, each one traceable to a
specific finding:

| fix | what it was | findings |
|---|---|---|
| `Repr` added to the ambient list | a constructor of the `Repr` enum in `core/debug`, in implicit scope — and in no `core/builtin` interface, which is where every other ambient name came from | 16 |
| import alias inside `\{...}` | `@` is not an identifier character, so `\{@sm.all_states()}` recorded the alias WITHOUT the `@` and the walk's `!has_prefix("@")` guard could not see it. **A regression 0.4.8 introduced** | 6 |
| `extend` is a declaration | read as a statement, `extend` became a name | 8 |
| C-style three-clause `for` | MoonBit's other `for` form; reading its head as a binder demanded `in` | coverage |

`Repr` was settled with the toolchain, not by inference: one probe file calling
`Repr(1)` and `ZzNoSuchName123(2)` in the same interpolation, where `moon check`
flagged only the second.

**Coverage: 73.1% → 86.5%** (87 → 103 of 119 files). The `for` fix is what
moved it, and only after a second bug in the fix itself: the first lookahead
that tells the two `for` forms apart scanned for a `;` at depth 0 without
stopping at the body's `{`, so any binder-form `for` followed later in the file
by a `;` was misclassified and died on `expected ';'`. It converted a 12-file
recovery into 4 and **moved the error instead of removing it** — 15 ×
`expected 'in'` became 14 × `expected ';'`. The test that now pins it is
written around exactly that failure.

The `for` desugars to `SBlock[SAssign, SWhile]` rather than a new AST node,
because every lens matches `SKind` exhaustively. Its one inexactness — the
update clause runs once after the loop rather than once per iteration — is
deliberate and in the quiet direction: the update is kept, because
`i = i + 1` is where `i` is *read*, and dropping it would make every loop
counter look unused. A test pins that.

After all four: **actionable 43 → 31**, of which 26 are one known limitation —
a call to a package-private helper in a sibling file, invisible to `.mbti`
resolution. That was the single dominant cause of what remained; **0.4.12 closes
it** (next section).

Tests: 215 js / 285 wasm / 215 wasm-gc. Self-scan stays 46/46 with
actionable=0. All five new guards are mutation-verified.

## 0.4.12 — package-private cross-file resolution: the largest class left is gone

26 of the 31 actionable findings 0.4.11 left behind were one thing: a call to a
**package-private top-level name in another file of the same package**. That is
not a limit, it is a gap in the analyzer. A MoonBit **directory is a package**:
a top-level name declared in any `.mbt` of a directory is visible from its
siblings. This analyzer resolved cross-file names only through `.mbti`, and a
generated interface carries `pub` items alone.

Measure first, then build:

- The 11 names behind those 26 findings (`sieve`, `ridge_fit`, `ridge_predict`,
  `ols_core`, `normal_cdf`, `fmt`, `claim_code`, `claim_of`, `phase_code`,
  `contains_state`, `has_state`) are **all** package-private top-level `fn`s in a
  sibling file of the same directory — 26/26, no exceptions.
- The toolchain confirms the language allows it: in a two-file package where one
  file calls the other's private `fn`, `moon check` and `moon test` both pass,
  **including across `_test.mbt`** (`has_state` is exactly that case). So all 26
  were false positives about this analyzer.

The shape is one table per **directory**: harvest the top-level declarations of
every `.mbt` in it, union them with the cross-file table, and hand that table
only to files in that directory. `@parser.collect_declared_names` is a token-only
scan (`fn` / `struct` / `enum` / `trait` / `type` / `const` / `let` / `extern` /
`suberror`), the same technique as `harvest_ctors`, not a parse — the caller
needs names, and lexing is the cheap half of a parse.

Three edges, each pinned deliberately:

1. **Depth 0 only.** A binding inside a function, a `test`, an `extend` or an
   `impl` block sits at least one brace deep and is never collected. Otherwise a
   local `let` could make itself visible package-wide.
2. **The name must be the token IMMEDIATELY after the keyword.** A destructuring
   `let (a, b) = ...` has `(` there, so nothing is collected.
3. **`fn Foo::new` is collected whole, not as `Foo`** — `Foo` may not exist.

The analyzed file is in its own table: it is part of its package. The side
effect is that a same-file top-level `const` is no longer misreported either (the
walk does not register `const` declarations — a long-standing hole). That was
measured, not picked up in passing.

`IfaceSymTab::merge` mutates its receiver, so this uses a new
`IfaceSymTab::union`: merging into the shared table would hand one package's
private names to another, and every name in a symbol table is a **suppression**,
so a cross-package leak only ever silences a genuinely undefined name.

**pyroduct actionable 31 → 5**, and the total finding count went 658 → 632,
exactly −26: nothing new appeared anywhere, and nothing else was swept up. The 5
left are two `OperatorMismatch` on `paths.mbt`, `_classes` in `algebra.mbt`,
`self` in `slot.mbt`, and `_f` in `audit/mbti.mbt`.

Self-scan 46/46, actionable=0. The output gains one line,
`PRIVTAB packages=N names=M`: a table that never looked and a table that found
nothing print the same, so it has to be said.

Tests: 220 js / 292 wasm / 220 wasm-gc. Seven guards mutation-verified, and one
of them was found *by* a mutation: rewriting the types half of `union` to write
into `self` left the whole suite green, because the test only checked the values
half. It went red once the type side was covered too.

## 0.4.24 — `raise` as an expression: the clause's third position

**A measurement redirected this release.** When 0.4.23 finished with actionable
up, I classified every `UndefinedName` and concluded they were `enum`/`suberror`
/`derive` constructors falling outside the analyzed subset — which is what I
had written the previous release. The classification showed the biggest bucket
was not constructors at all: of roughly 70 `UndefinedName` findings, **65 were
the literal name `raise`**. Constructors were a real but small tail, about 7.

`raise E` as a STATEMENT had never been implemented. 0.4.23 handled the same
clause in the two positions it appears on a FUNCTION (the signature annotation
and a function type's return annotation); the statement that actually performs
the raising is the third position. It was read as an ordinary identifier, so
every raise statement reported `undefined name 'raise'` — a confidently false
positive about code that compiles.

From proton 0.3.4 `facade_app_metadata.mbt:82`:

```moonbit
guard config.package_config() is Some(package_config) else {
  raise MissingPackageMetadata
}
```

Scale (vendored `.mooncakes` excluded): **585 sites across 54 files of proton,
427 / 90 of async, 180 / 16 of moonbit_image, 15 / 9 of moonbit_labeler,
6 / 1 of proton_contract.**

Settled first: all five payload-carrying forms give zero errors from `moon check`.
A **bare `raise` with no payload is itself valid MoonBit**, in three positions
(alone in a body, at the end of a body, closing a nested block with no
semicolon) — also zero errors.

### A new `SRaise` node, deliberately not `SReturn`

Three lenses would read a raise wrongly as a return:

- `Infer::scan_returns` has `SReturn(Some(e)) => acc = ty_join(acc, self.ty_of(e, TUnknown))`,
  which would join the error CONSTRUCTOR's type into the function's return type;
- `Interp`'s `SReturn` evaluates the operand and pushes it into `ret_vals`,
  inventing a return value `raise` never produces;
- only the divergence is shared, and that is exactly what `SRaise` keeps.

The payload IS still walked and type-checked (`nosuchfunction` inside
`raise E(nosuchfunction())` still reports), but it is NOT evaluated — everything
after a terminator is dead, so evaluating a discarded expression could only
perturb the abstract value stack. One test per lens pins that.

### The result: strictly fewer, never more

| Corpus | 0.4.23 | 0.4.24 | At finding level |
|---|---|---|---|
| `wzzc-dev/moui` 0.1.12 | parsed 483 / actionable 1 | **parsed 483 / actionable 1** | identical |
| `moonbitlang/async` 0.22.4 | parsed 216 / actionable 22 | **parsed 216 / actionable 19** | −8, **0 new** |
| `moonbit-community/proton` 0.3.4 | parsed 95 / actionable 103 | **parsed 95 / actionable 100** | −6, **0 new** |
| `riantr/moonbit_image` 0.3.7 | parsed 2 / actionable 3 | **parsed 2 / actionable 0** | −3, **0 new** |
| `proton_contract` 0.3.4 | parsed 4 / actionable 3 | **parsed 4 / actionable 3** | identical |
| `riantr/moonbit_labeler` 0.2.13 | parsed 25 / actionable 0 | **parsed 25 / actionable 0** | identical |

All 65 `undefined name 'raise'` findings are **gone**, and **nothing new
appeared in any family** — `Unreachable` included, 0 → 0. That is unusual for a
project where every extra bit of syntax brings extra findings, so it is worth
saying why: before touching anything I **measured whether this would get
noisier**.

### Measuring the noise first

The moment `SRaise` was wired in I went looking for `Unreachable`, because the
behaviour lens explores an `if`'s branches **one after another in the same
`Interp`** and flow state leaks between them: a terminating branch makes
everything after the `if` look dead. If that were real, this release would have
traded 56 false positives for a new batch of them.

Measured: across 12,428 files `Unreachable` went 0 → 0. **But the defect is
real and reproduces independently, with no `raise` involved at all:**

```moonbit
fn f(g : Int?) -> Int {
  guard g is Some(v) else { return 0 }
  return v            // reported unreachable — a false positive
}
```

The else terminates, the then branch (empty, because that is how `guard` is
modelled) does not, and the else's flow won the race. ⇒ **Recorded honestly,
not fixed here:** it fires on 0 of the six corpora's files, and changing it
means changing the behaviour lens's branch-merge semantics, which is a separate
change from `raise`. ⇒ Also recorded: `enum_ctors` harvesting is wired **only**
to `enum`, not `suberror`/`derive`; and constructor names that live in another
package's `.mbti` (proton's `OperationFailed`) never reach `IfaceSymTab` at
all. That is where the remaining 7 come from.

### Mutation gate: 7 mutations, **4 killed / 3 survived on the first version, 7 / 0 at the end**

The three survivors share one cause, and it is worth writing down: **when the
payload is not parsed it does not disappear, it becomes the next statement.**
`raise E(nosuchfunction())` is then read as `SRaise(None)` followed by the
expression statement `E(nosuchfunction())`, and the same two undefined names
still land on the same line and still merge into one — **every count-based
assertion passes either way**.

- **M2**: first tried separating them by the behaviour lens not evaluating the
  payload; that failed too, because an orphaned payload follows a terminating
  `SRaise(None)`, so the behaviour lens does not execute it either — it gets
  reported as unreachable instead. What finally separated them was the **anchor
  line**: with the payload attached the dead statement is `return 1` on line 6;
  orphaned, the dead statement is the payload itself, still on line 5. Same
  count, same family, same lens — a different line, and the line *is* the claim.
- **M4**: a second reason. Every payload before that was a call to an **unknown**
  name (`E`), and a call to an unknown function has no signature to check its
  arguments against, so `ty_of` returns early and the payload was never really
  looked at. Replaced with an expression the type lens checks on its own:
  `raise 1 + "a"` (settled valid; `int + str` is an `OperatorMismatch`) — a
  binary operator cannot be skipped for want of a signature.
- **M7**: the file had **no bare `raise` fixture at all**. The function named
  `bare` writes `raise E`, which has a payload. Adding the genuinely
  payload-less form turned it red.

Tests: 386 js / 458 wasm / 386 wasm-gc (12 new).
## 0.4.23 — the `raise` effect annotation, and a false positive it uncovered

**First, a correction to a number I gave earlier.** When this release started I
said "149 of moui's 608 files (24.5%) carry `-> T raise E`, and every one of
them failed to parse at all". **That grep counted vendored `.mooncakes`, which
the scanner does not scan.** Excluding vendored trees, moui has **2** such
files. The same ruler across all six corpora (`.mooncakes` excluded):

| Corpus | Files | Signature `-> T raise` | Type position `() -> T raise` |
|---|---|---|---|
| `moonbitlang/async` 0.22.4 | 409 | **72** | **10** |
| `moonbit-community/proton` 0.3.4 | 136 | **70** | **33** |
| `riantr/moonbit_image` 0.3.7 | 17 | **14** | 0 |
| `proton_contract` 0.3.4 | 3 | 2 | 0 |
| `riantr/moonbit_labeler` 0.2.13 | 35 | 2 | 1 |
| `wzzc-dev/moui` 0.1.12 | 607 | 2 | 0 |

The fix is real — `moonbit_image/bmp.mbt:26`'s `-> Image raise Failure` now
parses cleanly, where `decode_bmp` previously died on `expected '{'` — but **I
reported the scale an order of magnitude too large**. Readable files went
**787 → 825** in total, not by anything like 149.

### One clause, two positions

`parse_fn_signature` expected `{` straight after `-> T` and did not know
`raise`. Settled first: all four forms (`-> T raise`, `-> T raise E`, `-> T!`,
`-> Unit raise E`) give **zero errors** from `moon check`. The bare form comes
from `moonbitlang/core/error/error_test.mbt`, so it is a corpus shape rather
than one invented here.

**The type position was missed until the signature position was done.** A
function type may carry its own effect annotation — `fn f(g : () -> Int raise)`
also settles to zero errors — but the parser reported `expected ')'` and lost
the rest of the file. Fixing only the signature would have left a half-fix that
knows `raise` in one position and not the other, and proton's 33 files plus
async's 10 are exactly that shape. Both call sites now share
`Parser::parse_raise_effect`.

The "a bare `raise` must stop here" guard asks **"can the next token begin a
type at all"** (`TName` / `TLParen` / `TAmp`), not "which tokens terminate",
because the two directions are not symmetric: **reading one token too many is a
silent misparse** (the body gets swallowed into the type annotation and nothing
reports), while **stopping one token early is a loud `expected '{'`**.

### A false positive the fix uncovered: `guard!`

`parse_guard` bumped the name `guard` and went straight to the condition, so the
`!` in `guard! cond` fell through to the expression reader and became a boolean
NOT applied to the condition. The result is a confidently-worded false positive
about code that compiles:

```moonbit
// moonbitlang/async 0.22.4 src/internal/fd_util/pipe.mbt:31
guard! fds is [r, w]
// reported: operand of '!' must be bool, got '[int]'
```

The defect was always there; "the file did not parse at all" was hiding it.
**The raise fix only stopped covering for it.**

So `TBang` has three owners in one file: the `raise` short form, `guard!`, and
real boolean negation. Three control tests pin one each. Dispatch any of them by
scanning for the token instead of deciding by position and one of the three goes
red.

### The cost: actionable rose, and every new one is `UndefinedName`

More readable files means more findings, and some of them are wrong. Stated
plainly:

| Corpus | 0.4.22 parsed / actionable | 0.4.23 parsed / actionable | At finding level |
|---|---|---|---|
| `wzzc-dev/moui` 0.1.12 | parsed 481 / actionable **1** | **parsed 483 / actionable 1** | 0 new |
| `moonbitlang/async` 0.22.4 | parsed 206 / actionable 17 | **parsed 216 / actionable 22** | +5 `UndefinedName` |
| `moonbit-community/proton` 0.3.4 | parsed 72 / actionable 43 | **parsed 95 / actionable 103** | +60 `UndefinedName` |
| `riantr/moonbit_image` 0.3.7 | parsed 1 / actionable 0 | **parsed 2 / actionable 3** | +3 `UndefinedName` |
| `proton_contract` 0.3.4 | parsed 3 / actionable 1 | **parsed 4 / actionable 3** | +2 `UndefinedName` |
| `riantr/moonbit_labeler` 0.2.13 | parsed 24 / actionable 0 | **parsed 25 / actionable 0** | 0 new |

Counted by family, **every new actionable finding is `UndefinedName`**.
`UnusedParam` is unchanged and `OperatorMismatch` went **down** (2 → 0) once
`guard!` was fixed. Sampling confirms the false positives:

```moonbit
// proton facade_error.mbt:6
OperationFailed(action~, status=..., detail=...)
// reported: no visible binding for 'OperationFailed'
```

`OperationFailed` is a constructor of `WindowSessionError`, used that way in
four places across the corpus. Its declaration (an `enum` / `suberror` /
`derive`) is **outside the analyzed subset**, so its body is never analysed and
the name never enters the symbol table. **The cause is the pre-existing subset
boundary, not this release's parse change** — this release simply made those
files readable for the first time, so the hole became visible. It is now the
largest single source of actionable noise, and worth more than `raise` itself
in the next release.

### Mutation gate: 9 mutations, **9 killed, 0 survived** (`_verify/mutate_0423.ps1`)

Cleaner than 0.4.22's 6 killed / 2 survived. Three worth recording:

- **M7 / M8 are the same guard in opposite directions.** Admit everything and a
  bare `raise` swallows the body's `{` or the closing `)` — a **silent
  misparse** — turning 4 tests red. Admit nothing and every named effect stops
  being consumed, turning 6 red. Testing one direction alone lets "too strict"
  pass for "correct".
- **What M5 killed was not `skip_indexed()`, it was the `raise` keyword itself.**
  The first version of M5 removed `skip_indexed()` and came back **371/371
  green — an equivalent mutation**: `type_annotation` already calls
  `indexed_suffix()` on the name it reads, so `raise E[Int]` is consumed whole
  without that line. The dead call was **deleted**, with the reason recorded at
  the call site: keeping it would make the reader look responsible for a case it
  is not, and the next person to delete it would have no evidence anything
  checked it.
- **M2's first result was COMPILE-ERR, which was a bug in the gate rather than a
  result.** My Find string began with a newline, so after the replacement the
  code merged into the preceding comment line and the mutation **never ran**.
  There is one reliable criterion: a compile error is the **absence of a
  `Total tests:` line**, never a grep.

### Two gaps measured but not fixed here

- **The return type renders as `None` when the body ends in a tail
  expression.** `fn f() -> Int { 1 }` gives `f() -> None`, while
  `fn f() -> Int { return 1 }` gives `f() -> int`. This has **nothing to do
  with `raise`**: all four raise forms behave identically with and without an
  explicit `return`. Real MoonBit leans on tail expressions heavily, so its
  corpus impact is probably larger than `raise`'s. The 0.4.23 tests therefore
  **deliberately use an explicit `return`** — otherwise the assertion would go
  red for a reason that has nothing to do with the effect annotation.
- **A parenthesised function type in return position is read as a tuple.**
  `fn f() -> (() -> Int) {` reports `expected '{'`, **with no `raise` involved**
  (`return_annotation`'s tuple branch stops at the first `)` rather than the
  matching one). A real `-> (Int, String)` is fine. Corpus cost is small: 6
  files in moui, 0 elsewhere. Next release.

Tests: 374 js / 446 wasm / 374 wasm-gc (14 new).

## 0.4.22 — named arguments matched by **name**, and `Int32` read as `Int`

Readable files unchanged (**481**), but moui actionable **8 → 1**. All seven
that disappeared were the same shape
`argument 4 ... has incompatible type 'str'; expected 'bool'`, starting at
`core/gesture.mbt:754`:

```moonbit
// declared order, core/pkg.generated.mbt:92
ActionCommand::new(intent~, label?, shortcut?, enabled?, group?, description?)
// call order, core/gesture.mbt:754
ActionCommand::new(intent=..., label=..., group=..., description=..., shortcut=...)
```

MoonBit allows named arguments in any order (`moon check` confirms), so **an
argument's index is not its parameter's index**. The old code compared `args[3]`
with `params[3]`, which put `description` (String) where `enabled` (Bool) was
expected. Each named argument now finds its parameter **by label**, falling back
to position only when there is no label or no label matches.

The `~` shorthand (`f(x~)`) is also a label, recovered from the token stream
(`Parser::name_at`), so it can be reordered too.

| | Shape | Result |
|---|---|---|
| A | Reordered named arguments (`moui core/gesture.mbt:754`) | actionable 8 → **1** |
| B | `ann_to_ty` missing an `"Int32"` arm | **removed 87 silent points the formatter had created in its own source** |

**The reverse control is the important part of this release.** A's assertion is
zero findings, and "turn the check off entirely" also yields zero — so there has
to be a test asserting **one** finding before it means anything. The nine tests
are written in pairs: wrong type by name, wrong type by position, a label that
matches nothing falling back to position, the `~` shorthand reordered right and
wrong, positional arity, omitted `?` parameters, and `Int32` synonymous versus
not.

**The mutation gate found three things that were invisible at the time**
(`_verify/mutate_0422.ps1`, 8 mutations, 6 killed, 2 survived):

- **One extra `let r = build()` line in the fixture makes three mutations
  survive.** When an argument's type is wrong the behaviour lens reports the
  same call as `MethodError`, which merges with the type lens's
  `ArgTypeMismatch` (`merge_findings` groups by `(merge family, line)`), so
  `count_family("ArgTypeMismatch")` is permanently 0. **Changing
  `param_index` to never match left all 432 tests green.** A zero-count
  assertion can only fail if the finding it counts actually arrives under that
  family.
- **Two on one line collapse into one.** Same reason: `merge_key` is
  `(merge_group, line)`, so two wrong arguments written on one line come back
  as one, and a case expecting 2 must be split across lines.
- **`parse_call_args` has four push points.** The one for "an argument that does
  not start with a name" is not the one for "starts with a name"; missing a
  single push does not error, it leaves `labels` shorter than `args`, and every
  argument after the gap reads **some later argument's label**. The fixture
  added for this is `g(1, b=true)` — which also settles a semantic: a `?`
  optional parameter **cannot be passed positionally at all** (`moon check`
  reports "requires 0 positional arguments"), nor can a required `~` label; only
  a bare `a : Int` can. Which is exactly why named arguments are everywhere in
  real MoonBit and why positional matching produced so many false positives.

**Two surviving mutations, recorded honestly rather than papered over with a
test**:

- **M7, the `all_positional` gate (no arity check on labelled calls).** No test
  can see it, because **no valid MoonBit program** passes more named arguments
  than the function declares — settled: a duplicate label is 4084 and a label
  naming no parameter is 4085, both compile errors `moon check` already
  reports. Its cost was measured rather than assumed: across 12,428 files in
  the six corpora it changes exactly **one** finding, an arity report in `moui
  backend/web/web_host.mbt` past that file's reliable-region boundary, so it
  lands in the `unreliable` bucket and is never shown as a result. That one
  could not be confirmed as a true positive, and an argument-COUNT check is
  exactly where a misread cross-file signature manufactures a false positive.
  Writing a test that pins a behaviour no valid program exhibits would make the
  gate green and the suite weaker.
- **M8, method-call labels.** `EMethodCall` carries labels now, but infer
  discards them (`EMethodCall(base, _, args, _)`), because method arguments are
  **not type-checked at all** in this model — there is no receiver signature to
  check them against. That is a real gap, not a designed leniency: killing it
  needs a method-receiver signature, which is a larger change than this release.

**`Int64` / `UInt` are deliberately NOT folded into `TInt`.** `moon check`
confirms that passing `UInt` to an `Int` parameter is an `Expr Type Mismatch`
and so is the reverse, and `Int64` is against both. Folding them in is not a
harmless widening, it is **precisely silencing the mismatches `moon check` does
report** — the failure mode of 0.4.5 inverted (a check whose precondition can
never hold). They read as Unknown until they have their own `Ty` variants and
assignability rules. For whoever picks this up: across proton + async + moui
there are **122 `: Int64` and 23 `: UInt`**.

Tests: 360 js / 432 wasm / 360 wasm-gc (17 new). Self-scan 59/59,
`actionable=0`, `unreliable=0`, `withheld=0`.

| Corpus | 0.4.21 | 0.4.22 | At finding level |
|---|---|---|---|
| `wzzc-dev/moui` 0.1.12 | parsed 481 / actionable 8 | **parsed 481 / actionable 1** | 7 false positives gone, **0 new** |
| `riantr/moonbit_labeler` 0.2.13 | parsed 24 / actionable 0 | **byte-identical** | — |
| `moonbitlang/async` 0.22.4 | parsed 206 / actionable 17 | **byte-identical** | — |
| `moonbit-community/proton` 0.3.4 | parsed 72 / actionable 43 | **byte-identical** | — |
| `riantr/moonbit_image` 0.3.7 | parsed 1 / actionable 0 | **byte-identical** | — |
| `proton_contract` 0.3.4 | parsed 3 / actionable 1 | **byte-identical** | — |

## 0.4.21 — 436 → 481: `guard`, lambdas as named-argument values, `is` across a newline, and an `is` that bound only its first name

Files understood 436 → **481 (71.7% → 79.1%)**, withheld 1078 → **242**, unreliable
3025 → **1711**, `unexpected token` 163 → **113**, moui actionable 10 → **8**. All
seven findings on `embedded_runtime_backend.mbt` (3× `image_state`, 4× `host_bridge`)
are gone.

Four independent shapes, every one measured before it was written:

| | Shape | Where |
|---|---|---|
| A | `guard COND else { ... }` read as an identifier | 550 sites / 126 files |
| B | a named argument whose value is a lambda ended the argument list | parsed 436 → **481** |
| C | `is` did not continue across a newline — and the file STILL PARSED | `embedded_runtime_backend.mbt:227` |
| D | an `is` pattern bound only its FIRST name, and only at depth 1 | 7 findings, 13 sites corpus-wide |

### C is the hardest kind of bad here: it parses, and the tree is wrong

```moonbit
guard (self.frame, self.image, self.host_bridge)
  is (Some(frame_state), Some(image_state), Some(host_bridge)) &&
  !self.disposed else {
```

The line break ended the expression, `is` was read as an ordinary identifier, and
the file parsed WITHOUT an error — into a tree where every name after that point is
wrong. Fifteen findings, and because nothing had failed, NONE of them was reported
as unreliable. So that gate does not assert `n_parse == 0` (it is green either way);
it asserts that the names AFTER the continuation resolve.

The continuation skips only `TNewline`, never `skip_seps` — that also eats `;`, and
a semicolon is STRUCTURAL in a C-style `for`. Writing `skip_seps` here turned an
existing test red, and it is pinned by
`0421: a C-style for body is still analyzed (control)`.

### D: settle first, and the answer was not the obvious one

I assumed `error` in `Some(Os(error))` was already bound and simply unused. **Ran
`moon check` first**:

```
fn f(x : Int) -> Int {
  guard try_os(x) is Some(Os(error)) else { return 0 }
  error + 1
}
```

`moon check` accepts it — `error` IS a binding. The old reader only looked at depth
1, so `Os` became the binding, `error` fell through, and every use of it reported
`undefined variable`. Depth 3's `Some(DragLeft(Some(event_position)))` is the same.

The rules collapse into ONE predicate, called from BOTH branches (0.4.18 and 0.4.20
each lost a cycle to "a second name reader drifts from the first"; this one takes an
index, so it cannot):

- not `_`, not a keyword
- the next token is not `(` — that is a nested CONSTRUCTOR, not a binding
- neither neighbour is `.` — `@core.Role::Checkbox` is a qualified path, 18 in corpus
- the first `:` ends it — the rest is a type annotation and `Int` is not a binding;
  a qualified path's `::` lands on the same rule

### The differential caught a regression I had INTRODUCED

`proton internal/bridge_admission_test/main.mbt:93`:

```moonbit
runtime.prepare_bridge_request(request, window) is (Gone | PageUnavailable)
```

That `(` is a GROUPING paren, not a constructor payload, so `Gone` and
`PageUnavailable` were bound as locals and two nonexistent unused locals were
reported. **One of the two was new** — the old reader stopped after the first name,
so it had only ever bound `Gone`. The tuple branch therefore collects at `depth >= 2`
(a real tuple's bindings live one level in, inside `Some(`)). This was not reasoned
out; it came out of a finding-level differential across six corpora, and M8 pins it.

### Differential

| Corpus | 0.4.20 | 0.4.21 | Finding-level |
|---|---|---|---|
| `wzzc-dev/moui` 0.1.12 | parsed 436 / actionable 10 | **parsed 481 / actionable 8** | 45 more files readable |
| `riantr/moonbit_labeler` 0.2.13 | parsed 23 / actionable 3 | **parsed 24 / actionable 0** | 3 × `undefined function '@core.X::new'` gone |
| `moonbitlang/async` 0.22.4 | parsed 206 / actionable 29 | **parsed 206 / actionable 17** | 12 × `undefined name 'guard'` gone, **0 new** |
| `moonbit-community/proton` 0.3.4 | parsed 71 / actionable 44 | **parsed 72 / actionable 43** | 2 `guard` gone, 1 new (see below) |
| `riantr/moonbit_image` 0.3.7 | parsed 1 / actionable 0 | **byte-identical** | — |
| `proton_contract` 0.3.4 | parsed 3 / actionable 1 | **byte-identical** | — |

proton's single new finding is `undefined name 'nobreak'` in
`internal/bridge_admission_test/main.mbt` — a **newly readable** file, where
`nobreak` is a loop modifier this frontend does not implement yet. It is not a false
positive this change created; it is a real gap a newly readable file exposed.

### Mutations: 8 of 8 killed, both directions covered

M1 `guard` unparsed, M2 **the guard's `else` block dropped** (only the control test
catches this: the condition's names still resolve without it), M3 named-argument
lambda head off, M4 the newline continuation off, M5 only the first name bound, M6
the qualified-path rule removed, M7 the nested-constructor rule removed, M8 the
or-pattern depth rule removed. 8/8, every restore byte-identical by SHA256.

### Not fixed, written down honestly

moui's remaining 8 actionable all fall in two known items: `navigation_routing.mbt`
×1 and `gesture.mbt` ×6 are **named-argument positional matching** (`TFunc` carries
no parameter names, so it needs the whole signature pipeline), and `view_tree.mbt` ×1
is `expr as Type`, for which the AST has no `ECast`.

Two more limitations were MEASURED but left alone, because they are not in this
cycle's shape family:

- **Calling a function-typed parameter reports `undefined function`.** `let f = inc`
  then `f(1)` does it with no lambda anywhere in the file — a pre-existing false
  positive from 0.4.19's function-type annotations. My first gate fixtures hit it,
  which is why the warning is at the top of the test file.
- **`is Some(x : Int)`, a typed pattern.** Zero sites corpus-wide (all 18 `is X(...)`
  matches containing a colon are qualified paths like `@core.Role::Checked`). The `:`
  rule is in place but is **not corpus-verified**, and is not claimed as covered.

### The toolchain moved on the day of this release, and CI went red

The moment the `v0.4.21` tag was pushed, `gate` went **red at
`moon fmt --check`** while `moon check` was green. Both workflows install moon
from `curl .../install/unix.sh | bash` — **unpinned**, i.e. `latest`.

**Measure first, then decide how to fix it:**

1. `moon fmt --check` is green locally, so it is not my tree.
2. Checking out the already-shipped **v0.4.20 tag** and running the same new
   moon — **also red**. So this is a pre-existing environment problem, unrelated
   to any commit: the moment upstream changes the formatter, an unpinned gate
   turns red on everything, including a revert.
3. The new moon is `0.1.20261012`, released that day; local is `0.1.20260920`.
   The difference is not whitespace: it rewrites `src/core/moon.pkg`'s
   `options("proof-enabled": true,)` to `proof_enabled = true` and reformats
   **19 files tree-wide**, including a `Int` → `Int32` type rewrite.
4. Pinning first, since it is the cheapest fix.
   `MOONBIT_INSTALL_VERSION=0.1.20260920` on CI, and **`Install moon` itself
   fails**: the CDN no longer carries that version's Linux binary. **Pinning is a
   dead end**, because old builds get pruned.
5. Which leaves one option: accept the new toolchain's formatting.

Before accepting, measure whether it changes anything. The **un-reformatted**
0.4.21 source under the new moon gives `moon check` exit 0 and `moon test`
415/415 — so `Int` → `Int32` is the formatter's canonical form, not a
requirement. After reformatting: check 0, three targets 343/415/343 all green,
self-scan 59/59 `actionable=0`, and the **six corpora's SUMMARY lines are
byte-identical**. None of those 19 files moved a single measurable number.

### Also found: a mutation script that silently stops matching

The reformat flipped the `.mbt` files from LF to CRLF, while
`mutate_0421.ps1` itself stayed LF — it is not MoonBit source, so the formatter
never touches it. Every multi-line pattern then matched nothing, and six of the
eight mutations reported NO-OP.

The gate **failed loudly** (NO-OP counts as a failure, which is the behaviour it
should have), but a gate that silently stops matching is one edit away from being
decorative. So the comparison now **normalises line endings on both sides** and
writes back in whatever style the file already used. All eight are killed
afterwards, and each restore is still byte-identical by SHA256 — which is also
what proves the normalisation round-trips.

### Tests

415 (js 343 / wasm 415 / wasm-gc 343). Self-scan 59/59, `actionable=0`,
`unreliable=0`, `withheld=0`.

## 0.4.20 — a method was being harvested as a top-level function

`impl T for U with fn m(...) { ... }`. Files understood 432 → **436**, withheld
176 → 172, unreliable 3193 → **3025**, and moui actionable **14 → 10**: the four
`undefined name 'self'` findings are gone.

### My first test was HOLLOW, and the mutation is what caught it

The first version asserted only that `self` was not reported undefined. Reverting
the fix left the whole suite green. The reason is not the intuitive one, and it
is in `Parser::skip`: it records a note and CONSUMES NOTHING. So before the fix
the cursor stopped ON `fn` and the top-level loop re-read
`with fn identity(self) { ... }` as an ordinary top-level FUNCTION — `self` was
bound all along, and the corpus finding was never about a missing binding.

What actually changed is the HARVEST. `collect_declared_names` saw a depth-0 `fn`
and recorded the method name `identity` as a package-level value, so every call
to `identity` anywhere in the package resolved to "defined".

### TWO places, because there are TWO readers

1. `skip_decl_braced`: the `fn` sentinel exists for `pub impl Eq for T` (no body;
   methods live in a separate block), and `with` only ever appears in the
   body-carrying form — so `with` is the discriminator.
2. `collect_declared_names`: a completely separate name reader that never goes
   through `skip_decl_braced`. Without its own guard the phantom name returns.

That is the second time the same 0.4.18 lesson has repeated — a generic
function's name missing from the sibling table was the same root cause.

Measured on the corpus: 1224 `impl ... with` headers across 221 files, of which
**1047 write `with fn`** and the other 177 OMIT `fn` entirely
(`pub impl ToJson for Affine with to_json(self : Affine)`). The 177 never met the
sentinel and were never wrong; the 1047 all were. None of the 1047 headers
carries more than one `fn`, so stopping after the first body leaves nothing
dangling.

### `trait`'s OWN name has to stay

The first version blocked the whole holder, so `trait Marker { ... }` stopped
harvesting `Marker` and turned a pre-existing pyroduct test red. A `trait`
declares a package-level TYPE and must be kept; `impl Eq for T` and `extend`
declare nothing — `Eq` is the trait being implemented, declared elsewhere — so
only `trait` contributes a name. Mutation M4 pins that on its own.

### The harvest fix shows NO benefit on moui, and that is expected

The corpus numbers are identical to parser-only (436 / 10). It repairs a
FABRICATED binding — a false NEGATIVE — not a visible finding. It prevents "a
method name called from the package resolving to defined". moui has no such
call, so it cannot be measured there. Its gate is
"0420: an impl method is not harvested as a top-level function", which tests
the harvester directly.

### Differential

| Corpus | 0.4.19 | 0.4.20 |
|---|---|---|
| `riantr/moonbit_image` 0.3.7 | parsed 1 / actionable 0 | **byte-identical on all six metrics** |
| `riantr/moonbit_labeler` 0.2.13 | parsed 23 / actionable 3 | **parsed 23 / actionable 3** |
| `moonbitlang/async` 0.22.4 | parsed 196 / actionable 30 | **parsed 206 / actionable 29** |
| `wzzc-dev/moui` 0.1.12 | parsed 432 / actionable 14 | **parsed 436 / actionable 10** |

Self-scan 56/56, `actionable=0`, `unreliable=0`, `withheld=0`.

### Four mutations, all killed, in BOTH directions

M1 removes the `with` exception (the fix is gone); M2 disables the sentinel
entirely — only the CONTROL test can catch that, because a bodiless impl would
run on and swallow the rest of the file; M3 removes the harvest guard; M4 drops
the `trait` name. M2 is the reason this gate exists: testing only "the fix is
gone" is not enough.

## 0.4.19 — 389 → 432: a literal bound as a variable, and a function type that ended the file

Same corpus, wzzc-dev/moui 0.1.12. Files understood 389 → **432** (71.1%),
withheld 219 → 176, unreliable 4388 → **3193**.

### `if x is Some(true)` bound the literal `true`

`core/view_node_test.mbt` reported `local variable 'true' assigned but may not
be used`. `parse_is_pattern` treated ANY name in the payload as a binding — but
a binding is a name that INTRODUCES A VARIABLE, and a keyword introduces none.

The test is `@lexer.is_moonbit_keyword`, **not** a second copy of the list in the
parser. That table already carries `true`/`false`, and it already holds a long
comment on why `self` is deliberately NOT in it; a private copy is exactly how
the two would drift. `self` therefore still binds (`if x is Some(self)` means
that), and that is pinned as a control test.

### Function types in annotations: 845 sites / 171 files

`on_input~ : ((String) -> Msg)?`, `key : (T) -> String`, `emit : (Msg) -> Unit`.
The `(` used to hit `expect_name`, report "expected type name", and end the file.

The annotation's elements are read by `type_annotation` ITSELF, which is what
makes nesting fall out: `((String) -> Msg)?` is a function type returning a
function type. It is rendered faithfully rather than flattened, so the string
the type lens receives still says what it said; `ann_to_ty` has no arm for a
`(`-leading annotation and returns `TUnknown`, which is the honest answer — the
lens models no function types, and unknown is what keeps every operation on one
quiet.

Return position has an extra trap: the tuple arm of `return_annotation` accepts
ANY `(`. The first version recognised a function type by the three tokens `(`,
`)`, `->` — which matches only `() -> T`, because `(Int) -> String` has `Int`
BETWEEN the brackets. The fixture (4 parse errors) is what caught it. It now
SCANS to the matching `)` and asks whether `->` follows.

### Honest entry: actionable went from 4 to 14

43 more readable files necessarily produced 9 new findings. **Seven of them are
false positives**, from three classes this release only made VISIBLE. All three
are measured and written down in SKILL:

| Class | Count | Corpus size | Root cause |
|---|---|---|---|
| Named arguments compared positionally | 5 | `ActionCommand::new(...)` ×5 | the call OMITS defaulted parameters and passes the rest by label; the lens drops labels and compares by position, so `description` (String) was checked against the 4th parameter `enabled` (Bool) |
| `self` in `impl ... with fn name(self)` | 4 | 1047 sites / 204 files | `skip_decl_braced`'s sentinel gives up on the impl body, so the parameters are never bound |
| `expr as Type` cast | 1 | 29 sites / 21 files | `as` is unhandled and read as a bare name |

The first two need an **AST change** (`ECall`'s arguments must carry labels;
`Param` must record whether it has a default) — not a one-line change. Not
attempted here; logged as next cycle's work.

The leading `is` matcher (`f(x)` then `is Some(_)` on the next line) was **not
settled** this round: the minimal probe could not reproduce a legal form, so no
fix was written on it. It stays a known gap.

### Differential

| Corpus | 0.4.18 | 0.4.19 |
|---|---|---|
| `riantr/moonbit_labeler` 0.2.13 | parsed 22 / actionable 3 | **parsed 23 / actionable 3** |
| `riantr/moonbit_image` 0.3.7 | parsed 1 / actionable 0 | **byte-identical on all six metrics** |
| `wzzc-dev/moui` 0.1.12 | parsed 389 / actionable 4 | **parsed 432 / actionable 14** |

labeler's unreliable fell 360 → 352 with actionable unchanged at 3. Self-scan
55/55, `actionable=0`, `unreliable=0`, `withheld=0`.

### One mutation survives, and it SHOULD

Four mutations, three killed. The fourth — "treat every `(`-leading return as a
function type" — survived, and the reason is honest: for every annotation this
lens can read, the tuple arm and the function-type arm consume EXACTLY the same
tokens. With no `->` after the close, `fn_type_annotation` renders it and
returns, and `ann_to_ty` gets an unknown either way. `n_parse` cannot tell them
apart, so the mutation is genuinely non-discriminating. The tuple test stays
anyway — not as a kill for this mutation, but as a regression test for a future
change that breaks tuple parsing.

And one instrument was simply wrong: the `.mbti` export of `is_moonbit_keyword`
has **no** mutation coverage, because `moon test` compiles from SOURCE and only
the SELF-SCAN reads the tracked `.mbti` interface files. Delete the export line
and all 391 tests stay green. That gap is real — it already bit once in 0.4.18
with `TTilde` — so the release check runs the self-scan and requires
`actionable=0`.

## 0.4.18 — a fresh corpus: 193 → 389 of 608 files, actionable 588 → 6

The first seventeen versions all scanned corpora this project already knew. This
one is a package never scanned before: **wzzc-dev/moui 0.1.12** (608 files). It
was chosen for one reason — `moon check` runs through it, so anything the
analyzer reports about it is either valid MoonBit it cannot read, or a real
defect. There is no third possibility.

Result: 193/608 files understood (31.7%), then **389/608 (63.9%)** after six
fixes; actionable **588 → 6**.

### Settle first, then act

One root cause was wrong, and wrong in exactly the way I assumed right. The `&`
in `data : &RuntimeViewNode` I had been reading as a reference type. `moon check`
says otherwise:

```
Error [4100] x : &Node
  ╰── The type Node is not a trait
Error [4091] x.n
  ╰── @moonbitlang/core/ref.Ref[Node] has no field n
```

`&T` is `Ref[T]`, and `T` must be a **trait** — moui only writes it on traits
(`&RuntimeViewNode`), which is the shape that typechecks. So the fix is not "add
a reference type": it is to consume the `&`, fold it into the type name, and let
`ann_to_ty` return `TUnknown` honestly (the same answer `Map[K,V]` already gets).

`~` also turned out to be two-sided. The compiler's own words: `The labels f~
are required by this function` (declaration) and `This function has no parameter
with label x~` (call).

### Six fixes, each costed

| Fix | Shape | Corpus volume |
|---|---|---|
| `&T` | `Ref[T]` annotation | 31 sites / 13 files |
| `~` | `label~ : T` / `x~` | 594 files |
| `fn[T]` | type parameters | 1563 sites / 266 files |
| `b"..."` | byte-string literal | 878 sites / 134 files |
| `{ ..base }` | struct update | 370 sites / 88 files |
| `.m(...)` | leading-dot continuation | 1124 lines / 131 files |

Files understood, fix by fix: 193 →(`&`)195 →(`~`)313 →(`fn[T]`)342 →(`{..}`)373 →(`.`)389.

### Three "read it and dropped it", not three rules

`b"..."`, `{ ..base }` and the leading-dot chain would each MANUFACTURE a new
false positive if the fix simply ate the tokens: the arguments inside a chain or
a spread are ordinary expressions, and dropping them reports a parameter that is
used only inside one as unused. So all three preserve the reads:

- the spread base is pushed under an **empty field name** — `walk`, `infer` and
  `interp` all destructure as `let (_, v) = f` and only ever traverse the value,
  so the empty name is invisible to them while the expression stays alive and
  `self` is still seen used;
- the leading-dot chain reuses the **real postfix builder** (`parse_postfix` split
  into a `parse_postfix_from`), so segments become `EMethodCall`s whose arguments
  are naturally in the tree.

### One honest entry: `b"..."` bought no readable files

The parsed count did not move at all (342 → 342). In moui `b"` is never a file's
*first* error — something earlier always blocks first. It is a real lexer defect
(mutation-verified: without it, `undefined variable 'b'` plus `expected ')'`),
but on this corpus it shows no benefit. Kept, and booked as such.

### The mutation script caught the script's own bug

Twelve mutations, eleven killed. The twelfth (the chain rewind) is deliberately
marked SURVIVED: removing `self.p = save` leaves the cursor past the separators,
but the enclosing statement loop calls `skip_seps` anyway, so the result is
identical. That line is **defensive**, and no test or corpus line distinguishes
it. It stays (the loop is correct on its own terms rather than because a caller
tidies up), but it is not pretended to be covered.

More worth recording: the script's own error. The first version detected
COMPILE-ERR by grepping for `Parse error`, and matched its own test **named**
"0418: &T in a parameter type is not a parse error" — reporting a mutation that
killed 2 tests as "build broke; not evidence". It now keys off whether a
`Total tests:` line exists at all. A fragile detector that hides a working gate
is worse than none: it would have pushed a real fix out of the release.

The `Buffer` gate was also written wrong first: it mentioned `Buffer` only in a
type annotation, and the `.mbt` frontend does not report unknown type names at
all — so the test was permanently green and mutation M12 survived it. The real
corpus shape is `Buffer(size_hint=12)`, a **constructor call**. Rewritten to the
corpus shape, it kills.

### Differential

| Corpus | 0.4.17 | 0.4.18 |
|---|---|---|
| `riantr/moonbit_labeler` 0.2.13 | parsed 18 / actionable 3 | **parsed 22 / actionable 3** |
| `riantr/moonbit_image` 0.3.7 | parsed 1 / actionable 0 | **parsed 1 / actionable 0 (byte-identical)** |
| `moonbit-community/proton` 0.3.4 | — | parsed 70 / actionable 45 |
| `moonbit-community/proton_contract` 0.3.4 | — | parsed 3 / actionable 1 |
| `moonbitlang/async` 0.22.4 | — | parsed 196 / actionable 30 |
| `wzzc-dev/moui` 0.1.12 | parsed 193 / actionable 588 | **parsed 389 / actionable 6** |

labeler's unreliable fell 612 → 360 and withheld 179 → 146 with actionable
unchanged at 3 — **more readable, no new verdicts**. moonbit_image is identical
on all six metrics.

Self-scan: 54/54 files understood, `actionable=0`, `unreliable=0`, `withheld=0`.

(A real problem surfaced here too: after adding `TTilde` the self-scan reported
2 × `undefined name 'TTilde'`. Not a code bug — `src/lexer/pkg.generated.mbti` is
a **git-tracked generated file** that did not follow, and neither `moon update`
nor `moon doc` rewrites it. After adding the variant by hand the self-scan
returns to 0.)

### Still unfixed (all parser; deliberately unchanged in behavior)

- A leading `is` expression (an `f(x)` followed by `is Some(_)` on the next line)
  is read as the bare name `is`, giving `undefined name 'is'`; `if x is Some(true)`
  binds the literal `true`, giving `local variable 'true'`. Three actionable in
  total, around `core/view_node_test.mbt`.
- The untyped `self` in `impl ... with fn layout(self, context)` is reported
  undefined — one finding.
- After the three parser fixes 219 files are still not read whole; the dominant
  cause remains `unexpected token`.

## 0.4.17 — 11 → 9: one root cause was "0.4.16 wrote the probe wrong", the other "it read the answer and threw it away"

0.4.16 left 11. This release went back to the `Array::make` finding that 0.4.16
declared **unobservable** and therefore reverted. The conclusion was that the
unobservability came from a broken probe, not from the rule being wrong.

### `Array::make`: the probe never called the function

The behavioral lens analyzes a function body only when the body is **reached**
from a top-level statement. `rasterizer.mbt` calls `PixelBuffer::new` at line
**1378**; every 0.4.16 probe copied the definition and not that call. "Changing
the rule made no difference" was therefore guaranteed — it never ran.

With the call restored the finding reproduces, and a **second** fact turned up,
which overturns how it was read the first time:

| Probe | Result |
|---|---|
| top-level call present, the real line | reports `Byte::default` |
| top-level call removed | completely silent |
| `Array::make` called alone | **reported** |
| `Byte::default` called alone | **reported** |
| outer also missing + inner `Byte::default` | **only the inner is reported** |

The last row is the point: **a call that reports returns `ABottom`, and the
enclosing call is then never visited**. A nested chain therefore reports only
its innermost unknown name. Reading "adding `Byte::default` exposed
`Array::make` beside it" as whack-a-mole with no termination was wrong — that
was a **mask lifting**, not an endless list, and the family ends once the
callees are known.

### Why a table and not a rule

The rule version is "a call qualified on a builtin type is a builtin method,
stay quiet". A control settles it:

| Spelling | Result |
|---|---|
| `Array::make(4, 0)` | silent (the name is in the table) |
| `Array::mkae(4, 0)` | **reported** (the name is not) |

The rule silences both. So `src/core/builtin_methods.mbt` is a **generated
table**: 656 names, 642 read out of the toolchain's own
`moonbitlang/core/**/pkg.generated.mbti`, and 14 compiler builtins
(`Array::make`, `Map::new`, `StringBuilder::new`, …) that **no interface
declares**, each settled with `moon check` — one probe file calling all of them
bare, next to an impossible control name, and the toolchain flagged only the
control.

The generator ships with the repository at `tools/gen_builtin_methods.ps1` and
runs `moon fmt` itself. It has to be in the repository rather than a scratch
directory: `builtin_methods.mbt` says "do not edit by hand", and a generated
table whose generator is not committed rots silently — the next MoonBit adds
methods, nobody regenerates, and the analyzer goes back to reporting real
builtin calls as undefined. The table joins the ambient list in `builtins.mbt`, whose header has
always said that every use of that list **can only cost a missed report and
never invent a false alarm** — which is why it can be data.

### A 0.4.16 conclusion, falsified

The 0.4.16 test claimed "an unresolvable qualified call is silent — the mirror
image of the over-reporting". **False.** Its fixture was
`fn f() -> Int { Nope::also_missing() }` and `f` was **never called** — the same
probe defect as `Array::make`. Add `let top = f()` and the very same name is
reported.

Two silences stack and look like one: the behavioral lens needs the body
reached, and the type lens does not treat a `::` name as a type reference at
all. The test now asserts what is actually true.

### `Select`: an enum variant in a sibling file

`canvas_view_test.mbt:4917`:

```moonbit
fn every_mode() -> Array[Mode] {
  [Select, Rect, Polygon, Keypoint, EditBinding]
}
```

`Mode` and all five variants live in `app_moui/app.mbt:23`, the same package
directory. `collect_declared_names` collects only the names after a **top-level**
keyword, and an enum variant is brace-declared, so the depth-0 rule skipped it.
This is the cross-file twin of the in-file unit-variant gap 0.4.15 closed with a
path-tail fallback: `Mode::Select` goes through it, bare `[Select, ...]` does
not.

The fix enters the `enum` body — but a **payload type is not a variant**, or
`Conv2d(Params)` would make `Params` package-visible and silence a real finding
elsewhere. So the rule is: starts a line (or follows `{` / `,` / `|`) **and is
not inside parentheses**.

(Mettled along the way: the space-separated one-liner `enum E { A B }` is a
**parse error** — `moon check` says `expect ; or }`. The test was first written
assuming it legal, went red, and the answer came from the toolchain rather than
from a guess at the grammar.)

### The differential: 2 of 933 files changed verdict

| Corpus | 0.4.16 | 0.4.17 |
|---|---|---|
| `riantr/snn_mbt` 0.155.0 | 6 | **6** (all true positives, untouched) |
| `riantr/moonbit_doubleML` 0.139.0 | 0 | **0** |
| `riantr/moonbit_labeler` 0.2.13 | 5 | **3** |
| `riantr/moonbit_image` 0.3.7 | 0 | **0** |
| `riantr/pyroduct` 0.1.29 | 0 | **0** |
| Total | 11 | **9** |

File by file, only `rasterizer.mbt` and `canvas_view_test.mbt` changed verdict,
each losing **exactly one** actionable finding, with their notice counts (1 /
175) **unchanged**. The other 931 files are byte-identical.

The 3 left in labeler are `@core.SurfaceMetrics::new` ×1 and `@core.Size::new`
×2 — the `--extern-iface-dir .repos` invocation class 0.4.16 already settled.

Tests js 286 / wasm 358 / wasm-gc 286. Seven mutations, all killed. Two of them
test the SHAPE rather than the value: M3 puts a name that does not exist
(`Array::mkae`) into the table and the negative control has to go red; M4
installs 0.4.16's **rule** in place of the table and 8 tests go red — "a table
beats a rule" is measured, not chosen for style.

## 0.4.16 — 19 → 8, six of them TRUE positives: acknowledge "correct" first, then fix the rest

0.4.15 left 19 findings. This cycle did the thing the previous one skipped:
**adjudicating which ones are real.**

Six are **true positives** — the analyzer was right and the code has a problem:

| Site | Finding | Evidence |
|---|---|---|
| `neuron_identity.mbt` | parameter `dt` is never read | read the source; `dt` appears nowhere in the body |
| `dsac.mbt` ×2 + 3 × `examples/*/main.mbt` | `for a in 0..<n` binder `a`/`s` never read | same; probed that `moon check` warns on an unread for-binder too |

Three more are **not defects at all**: labeler's `@core.SurfaceMetrics::new` and
friends. The analyzer printed the reason itself — `FETCH ... pass
--extern-iface-dir .repos to index their interface names`. Rescanning with that
flag takes labeler from 5 findings to 2. **Those three were never a bug; they
were a usage mistake.**

The 9 that were genuinely fixed share one shape: **the information had already
been read, and was then discarded or never used.**

| Cause | Count | Site |
|---|---|---|
| a cross-package `const` typed as a FUNCTION | 4 | `IfaceSymTab.values`'s `Bool` was written `true` and read by nobody |
| a braced `suberror` body parsed as expressions | 4 | always routed to the "skip to end of line" path |
| `Byte::default` missing from the builtin list | 1 | — |

### Cross-package const: `3.0F * hz` reported as `'float' and 'fn hz'`

```moonbit
// snn_mbt/istdp.mbt
r: 3.0F * hz,   // hz is a `const hz : Float` from @snn_kw
```

The `.mbti` reader **already told** `const` from `fn` — it matches a different
prefix for each — and then threw the difference away, because both branches
produced a bare name. The `Bool` in `Map[String, Bool]` was written `true` and
never read. It is now `is_const`, and `merge` / `union` carry it.

The counter-test is mandatory: a cross-package **function** must still type as
`TUnknownFn`. Demoting it to `TUnknown` too would let the call handler check an
invented parameter count.

### Braced suberror

`suberror` has two shapes: `suberror Timeout of String` (one line) and
`pub suberror DecodeError { ... }` (braced). Both were routed to the line
skipper, so the braced shape stopped at the newline and the remaining `{ ... }`
was parsed as an expression block — every payload type inside it became an
undefined name, `String` four times over in `moonbit_image/types.mbt`.

The split now follows what actually follows the keyword, with the lookahead
bounded at 8 tokens (a `suberror X of T` header is never longer), so a later
declaration's brace cannot be mistaken for this one's. The counter-test: an
unbraced suberror must still parse, and the function declared AFTER it must
still exist.

### A finding in the opposite direction: this analyzer UNDER-reports

`Nope::also_missing()` — a qualified call whose callee cannot be resolved — is
reported **not at all**. That is not new; it is the mirror image of the
over-reporting 0.4.14–0.4.16 spent three releases removing:

> Qualified names were once OVER-reported (`Layer::ReLU`, `fn hz`); fixing that
> left them UNDER-reported.

I wrote this up as a test asserting the CURRENT behaviour, labelled KNOWN GAP.
Asserting a finding that does not exist yet would turn every release red for a
problem nobody has scoped. Moving in the right direction means first telling a
method receiver apart from a package alias, which this cycle does not do.

### Results

| Corpus | 0.4.13 | 0.4.14 | 0.4.15 | 0.4.16 |
|---|---|---|---|---|
| `snn_mbt` | 33 | 19 | 9 | **6** (all true) |
| `moonbit_doubleML` | 28 | 3 | 1 | **0** |
| `moonbit_labeler` | 6 | 5 | 5 | **5** (2 with `--extern-iface-dir`) |
| `moonbit_image` | 4 | 4 | 4 | **0** |
| `pyroduct` | 0 | 0 | 0 | **0** |
| Total | 71 | 31 | 19 | **11** |

Of the 11 left, six are true positives, three are usage, and two are in labeler
(one a `Byte::default`-like builtin, one hidden behind stdout truncation).

Tests: js 270 / wasm 342 / wasm-gc 270 (8 new). All four mutations killed,
restore verified byte-identical by SHA256; self-scan 52/52, actionable=0.

## 0.4.15 — 12 of the remaining 30: three causes, one of which nearly muted a whole rule

0.4.14 took the four corpora from 71 actionable findings down to 31. **One of
those 31 was a true positive** — `neuron_identity.mbt`'s `dt` parameter really
is never read, and the compiler warns about it too. That is the first genuine
one in this whole corpus set. The other 30 were triaged and three causes account
for 12 of them.

| Cause | Count | Evidence |
|---|---|---|
| an `extern "C"` parameter reported unused | 6 | probe: extern is silent, a normal fn beside it warns |
| `Bool == Bool` reported as unsupported operands | 2 | probe: 0 errors, 0 warnings |
| a UNIT (payload-less) enum variant unread | 4 | probe: 0 errors; the payload variant beside it already worked |

### Unit variants: payload resolves, unit does not, in the same file

```moonbit
enum Layer {
  Conv2d(Conv2dParam)   // resolves
  ReLU                 // reported undefined
}
```

This is not "the enum was not harvested". The harvest does collect both names —
but it stores the BARE name (`ReLU`), while the reference is the whole PATH
(`Layer::ReLU`). `Layer::Conv2d(p)` is a CALL, and the call path has its own
fallback; `Layer::ReLU` is a bare reference and does not.

The fix gives a qualified path a tail fallback (`@core.path_tail`), taken ONLY
after the whole path has already failed to resolve — so it can never turn a
resolvable path into an unresolved one, only rescue a path whose tail names
something real, which is exactly what a unit variant is.

The counter-test that keeps it honest: `Colour::Purple`, never declared, must
still be reported. Otherwise every mistyped enum path in every codebase goes
silent.

### "The body is empty" is NOT a usable proxy for extern

The tempting shortcut is that an extern function has no body, so "empty body ⇒
don't audit its parameters" would do. The probe killed it:

| Source | `moon check` |
|---|---|
| `extern "C" fn expf(x : Float) -> Float = "expf"` | silent |
| `fn p7(z : Float) -> Float { }` | **warns** |
| `fn p6(y : Float) -> Float { 1.0 }` | **warns** |

So the parser must record extern names explicitly (`ParseResult.extern_fns`),
following the same precedent as `enum_ctors`.

### Results

| Corpus | 0.4.13 | 0.4.14 | 0.4.15 |
|---|---|---|---|
| `snn_mbt` | 33 | 19 | **9** |
| `moonbit_doubleML` | 28 | 3 | **1** |
| `moonbit_labeler` | 6 | 5 | 5 |
| `moonbit_image` | 4 | 4 | 4 |
| `pyroduct` | 0 | 0 | **0** |
| Total | 71 | 31 | **19** |

`snn_mbt` lost 10 and `doubleML` lost 2 — exactly the per-cause counts.
`labeler` and `moonbit_image` did not move, because their causes are different
ones (cross-package constructors like `@core.X::new`, a missing builtin like
`Byte::default`, and `suberror` bodies being re-scanned).

Tests: js 263 / wasm 335 / wasm-gc 263 (7 new). All five mutations killed,
restore verified byte-identical by SHA256; self-scan 51/51, actionable=0.

### The harness's third self-inflicted bug

A mutation's replacement was written as PowerShell's `$true`, which is not
MoonBit syntax. Two mutations therefore failed to COMPILE, and the script
reported them as `COMPILE-ERR` — which looks just like "the suite caught it",
while it had caught nothing. **A mutation that cannot compile and a mutation
that succeeded in killing something must never be reported the same way.**

## 0.4.14 — pyroduct's zero was not "correct": four other corpora, three real defects plus one silent one

0.4.13 drove pyroduct's actionable count to 0, but that was pyroduct happening not
to exercise the analyzer, not the analyzer being right. Pointing the same binary at
four other published modules (`snn_mbt` / `moonbit_doubleML` / `moonbit_labeler` /
`moonbit_image`, 933 files) produced **71 actionable findings** immediately.

| Cause | Count | Evidence |
|---|---|---|
| `F`-suffixed float literals `0.0F` unmodelled → `undefined name 'F'` | 28 | valid per `moon run`; `7F` is the syntax error |
| `/` typed as float division → `cannot assign 'float' into '[int]'` | 14 | `7 / 2` is `3`, **not** 3.5 |
| exponent notation `1.0e-12` unlexed → `undefined name 'e'` | 14 | valid per `moon run` |
| `suberror` bodies re-scanned → `undefined variable 'String'` | 4 | the same line already reports ParseError |

All 68 adjudicated findings are false positives. **Zero true positives.**

### A defect that produces no finding at all

While fixing the above, a probe turned up something worse than any of them:

```
1.5 -> 1 | 0.25 -> 0 | 3.14159 -> 3
```

**Every float literal was losing its fractional part.** In `lexer.mbt`, `int_part`
was captured before the fraction was consumed, so the later
`slice(start, int_part)` cut the token back to its integer part.

It stayed invisible because the existing tests asserted only that the token *kind*
was `float` — which a truncated value satisfies perfectly. **A defect that emits no
finding leaves the analyzer silently wrong about every float it ever reads.** The
new tests therefore read the VALUE and the TOKEN COUNT.

### One fix that was measured, and then withdrawn

The constant folding and result type of `/` in `walk.mbt` / `interp.mbt` are also
wrong as MoonBit describes them (`OpDiv => None`, `AType("float")`). After fixing
all three:

- three of the five mutations **survived** (reverting them left the suite green);
- a differential scan over 933 files produced **byte-identical report streams**.

The constant-evaluation layer simply does not reach any emitted finding for a
division today. Under this project's rule — unobservable branches do not ship —
**those three changes were reverted**, with the reasoning recorded in the comments
at both sites. Claiming a fix that cannot be demonstrated is worse than leaving a
known, currently-harmless formulation in place.

### Results

| Corpus | Files | Parsed | Actionable |
|---|---|---|---|
| `riantr/snn_mbt` 0.155.0 | 673 | 234 → **603** | 33 → **19** |
| `riantr/moonbit_doubleML` 0.139.0 | 205 | 145 → **165** | 28 → **3** |
| `riantr/moonbit_labeler` 0.2.13 | 37 | 16 → 18 | 6 → **5** |
| `riantr/moonbit_image` 0.3.7 | 18 | 1 | 4 |
| `riantr/pyroduct` 0.1.29 (no regression) | 119 | 103 → **104** | **0** |
| Total actionable | | | 71 → **31** |

Tests: js 256 / wasm 328 / wasm-gc 256 (16 new). All five mutations killed, and
after each restore the file is verified byte-identical to before the run.

### Two self-inflicted bugs the harness caught

The verification script itself bit twice during this cycle:

1. A bare `Get-Content -Raw` decodes UTF-8 as GBK on a Chinese-locale Windows,
   rewriting `—` as `鈥?` **and eating the newline after it**, merging two comment
   lines. Reading by bytes and proving the restore with SHA256 fixed it.
2. In the differential script `"$v_"` parses as a variable *named* `v_` (empty), so
   both variants were written to the same file and the second overwrote the first.
   "Variant A vs variant B" had become a file compared against itself, reporting
   "identical". Now `${v_}`, and the comparison asserts both files exist first —
   two failed reads had once been scored as "same".

Criterion: **before comparing two results, prove both results exist.**

## 0.4.13 — the last five: three causes, one of them a trap in narrowing a check

0.4.12 left 5. **All five are analyzer defects** — pyroduct's code is clean, and
`moon check` accepts every one of those files with zero errors.

| Cause | Count | Where |
|---|---|---|
| `color[u]`: a **`Map` treated as a list**, reported as an index type error | 2 | `src/paths.mbt` 135/152 |
| `self` read **only** inside an interpolation, reported as an unused parameter | 1 | `src/slot.mbt` 127 |
| `_`-prefixed unused binding/parameter — **the analyzer's rule was the opposite of the compiler's** | 2 | `src/algebra.mbt` 118, `audit/mbti.mbt` 69 |

### The first one nearly got traded for a worse bug

Indexing a `Map[String, Int]` with a `String` is **correct** — a map is indexed by
its key. The type lens never asked whether the subscript's base is a list at all;
it reported `list indices must be int` for any non-int index, putting an
`error:`-severity finding on a clean file.

The obvious fix is a precondition: only when the base is a `TList`. **That
immediately swallowed two real errors**, measured with a probe: `xs["k"]` on
`Array[String]` and on `Array[Int]`, both "Expr Type Mismatch" in `moon check`,
both caught by 0.4.12, both gone the moment the precondition went in.

The cause is that `ann_to_ty` does not recognise `Array[T]` (it knows only `[T]`,
which is not even valid MoonBit), and `type_annotation` **discards the `[...]`
entirely** via `skip_indexed` — so `Array[String]` reached the lens as bare
`"Array"`. The `TList` precondition could therefore **never fire**, and the check
had become a mute.

The real fix is to complete the type model, not to silence the check, and it took
three pieces: `ann_to_ty` learns `Array[T]`; the parser keeps the head's `[...]`
(its own comment there had argued "the type lens does not model containers, so
dropping it costs nothing" — that sentence was the bug's own explanation); and
`ty_assignable` recurses into `TList`, so `TList(TUnknown)` is assignable to
`TList(TStr]` rather than the "Unknown fits anything" rule being quietly defeated
one level down.

Measured on a probe of five subscripts, of which `moon check` calls 3 real errors:

| | real errors caught | false positives |
|---|---|---|
| 0.4.12 | 3 / 3 | **1** (the `Map`) |
| 0.4.13 | **3 / 3** | **0** |

⇒ **Lesson: before adding a precondition to a check, ask whether the types it now
depends on are even readable.** The precondition was correct, and the thing it
depends on was being thrown away upstream — so adding it muted the check, and it
muted it *plausibly*, because the check genuinely "only reports when the base is
a list".

⇒ **Paired: a comment defending a lossy decision becomes the bug's own
specification.** "This is not a compromise" is only true while its premise holds,
and it stops holding the moment someone tightens the premise it justifies.

### The `_` prefix: the analyzer's rule was the compiler's opposite

A leading `_` is MoonBit's discard convention. Probe — one file holding `_f` /
`_classes` / `_ok3` plus a non-underscore `plain` control: `moon check` warns on
`plain` and on **nothing else**. The analyzer exempted only the bare `_` and
asserted in a comment that "a name is not a discard pile" — an **argument, not a
measurement**, and one the compiler contradicted immediately.

⇒ **Lesson: probe an exemption rule before writing it down.** Both the rule and
its rationale were added in 0.4.8 and never checked against the toolchain.

### `self` is a conventional parameter name, not a keyword

The lexer listed `self` among the words that are not bindings inside an
interpolation, so `\{self.designation()}` recorded **no read** and a parameter
read only inside an interpolation was reported as never used. It was added in
0.4.8 alongside interpolation tracking, as a guess that `self` was syntax.

⇒ **Lesson: one read must have one answer on every path.** The bug was precisely
that "inside an interpolation counts as a read, inside a plain expression does
not". Pin **both** directions in the test, or pinning one looks like coverage.

### Two things the mutation run turned up

1. **The mutation harness's own filter matched zero tests.** Two guards reported
   GREEN because the `--filter` glob selected no test at all — an "all green" that
   proved nothing. The script now asserts `ran > 0` and reports `ran = 0` as
   INVALID.
2. **One fix that no test could kill.** I briefly had an empty list literal
   "adopt" its annotation type; muting it left the finding stream **byte-identical**
   on both corpora (496 and 528 findings), and no test failed. What actually
   carries it is the `TList` arm of `ty_assignable`. **A branch no test can fail
   and no corpus can distinguish is untested code that looks like a decision** —
   removed, with the reason recorded at both sites.

pyroduct **actionable 5 → 0**, total findings 632 → 627, exactly −5: nothing new
appeared anywhere. Self-scan 48/48, actionable=0. Tests 240 js / 312 wasm /
240 wasm-gc (24 new, 6 of them in a new `types_test.mbt` — a file that did not
exist before, and whose absence is why the regression above survived a whole
release). Eight guards, all mutation-verified.

## 0.4.10 — publishing 0.4.9 exposed two things the self-scan had been hiding

Releasing the provenance fix meant running the published package through itself
again — the check that found the `unknown` bug. That run came back
`actionable=2` where 0.4.8 had been clean, on two names in `provenance.mbt`:

```
no visible binding for 'is_coordinate'
no visible binding for 'split_coord'
```

Neither is a defect in the code. Both are this release reading its own source
and finding two things worth knowing about the tool.

**An `if` *expression* hides undefined names.** The same two names appear twice
in that one file, and only one was reported:

```moonbit
let stem = if is_coordinate(p.target) {   // line 226 — an if-EXPRESSION
  ...
if is_coordinate(target) {                // line 411 — an if-STATEMENT
```

`let x = if c { … } else { … }` is parsed, its branches are read, and then
**discarded** — it is outside the analyzed subset, and the notice says so. So a
name that does not exist inside such a branch is never reported. The 0.4.8
self-scan was clean partly for that reason: the calls sat inside a dropped
if-expression. Moving them into a plain function turned the if into a statement,
which is parsed in full, and two latent false negatives became two findings.

**A package-private helper in another file is invisible.** Cross-file
resolution goes through `.mbti` files, and a package-private `fn` appears in
none — so a file calling a sibling file's private helper reads as unbound. That
is what the two findings actually were: real bindings the analyzer has no way to
see. `is_coordinate` and `split_coord` are now `pub`, which puts them in the
interface, for the same reason `prov_or_unknown`, `stamp_utc` and
`scan_artifact_name` already were. The comment on each says why, so nobody
tidies them back into private and silently reintroduces the finding.

Neither class is fixed here: both are declared subset / visibility limits, and
both fail toward *silence* rather than noise. Worth knowing when a scan of a
multi-file package returns nothing.

## 0.4.9 — a `@latest` scan named its own artifact `unknown`

Scanning the published package through itself with the documented invocation:

```
moonx riantr/moonbit_static_analysis@latest riantr/moonbit_static_analysis@latest --mmd-auto
```

reported `46/46 parsed, actionable=0` — the published artifact scans itself
clean, which is the check the working tree cannot give you. But the artifact came
out named `riantr-moonbit_static_analysis_unknown_0.1.20260920_…mmd`, with
`version=unknown` in its own header, while the scan was reading
`.repos/riantr/moonbit_static_analysis/0.4.8/` — whose `moon.mod` declares
`version = "0.4.8"`.

`provenance_for` took the version from the coordinate when the target was one,
and never fell back to the tree. `@latest` names no version: `split_coord` blanks
it on purpose so `moon fetch` receives a bare module. So the one invocation the
tool's own header recommends as the example always wrote `unknown` — on the field
that exists to tell two scans apart.

A coordinate that **pinned** a version is still believed over the tree, since the
caller asked for that one; only the empty case falls back. Verified by running
the same coordinate scan after the fix:

```
MMD	riantr-moonbit_static_analysis_0.4.8_0.1.20260920_20261010T235302Z.mmd
  %% version=0.4.8
```

Tests: 207 js / 277 wasm / 207 wasm-gc.

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
moon add riantr/moonbit_static_analysis@0.4.24
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

- **mooncakes.io**: `moon publish` (after publishing, `riantr/moonbit_static_analysis@0.4.24` can be imported by any MoonBit module; `src/cli` ships a SKILL.md and is listed on [skills.mooncakes.io](https://skills.mooncakes.io)).
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
