# Changelog

Release-by-release history of `riantr/moonbit_static_analysis`.

**The README is the user-facing document.** This file is the release history: what each
version changed, the measurement behind each change, and the correction when a claim had
to be withdrawn. Start with the [README](README.md) for what the tool does and how to
use it.

The Chinese release history is in [CHANGELOG.zh.md](CHANGELOG.zh.md).


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

## 0.4.33 — the README, checked sentence by sentence, and six claims that were wrong

This release changes **no behaviour of the analyzer**. Its content is a correction:
the README was read sentence by sentence against the current tree, and six of the things
it said were not true.

### The 402-finding file is 1022

The mermaid section said the largest raw-finding file on `moonbitlang/core` is "a
402-finding test file that is 402 notices and zero defects".

MEASURED 2026-10-22, over the pinned corpus and the current wasm, in **both** views:
the largest raw-finding file is `builtin/int64_test.mbt` at **1022** findings — every
one of them a notice, and none of them a defect. The second is `builtin/extends.mbt`
at 394. The *shape* of the sentence was right and the number was wrong.

### "~90 built-in warnings" is a number nobody can measure

The coverage section said `moon check` has "a real parser and ~90 built-in warnings at
100% coverage". The toolchain ships no diagnostic catalogue, so the catalogue size
cannot be measured from here at all, and the claim had been carried unchanged from the
0.4.13-era notes in `LOOP.md`.

It is replaced by what CAN be measured, on the same corpus and the same command:
`moon check --target all` on `moonbitlang/core` reports **one** error and 251 warnings
of **two** kinds. The point of the sentence is unchanged — the compiler reads the whole
language, this tool reads a subset — and it now rests on a number that can be
re-measured.

### The release gate did more than the README said, and less

Two ways, both corrected.

The README listed what `_verify/release.ps1` runs, and the list was missing two stages
that exist: **this README's own links, anchors, versions and counts**, and **the
mutation-gate roster** with its self-test. The roster matters: it is a hand-kept list,
and a gate that exists on disk but is missing from that list **never runs** — and a gate
that does not run is indistinguishable from a gate that passes. The README's claim that
"all 79 are inside the gate list" was true and hand-maintained; it is now **checked**,
in both directions, with a self-test that injects six defects and requires each to be
caught.

And the Contributing section said every mutation gate "requires a named test to go red".
MEASURED over the 426 live mutations: 389 expect a kill, and **312** of them also NAME
the test that must go red. The gate requires a test to go red always; it names one for
312 of the 389.

### The formal verification was not running, and nobody was running it

This is the one that is not about wording.

`moon prove src/core --why3-config .why3.conf` **fails**. The README said "**21/21
goals VALID** (unsat) ... each machine-checked with cvc5", and that measurement dates
from 2026-10-03.

TWO INDEPENDENT BREAKS, both dated:

- **2026-10-09** — two `#proof_pure` annotations were false: on `path_tail` and
  `unqualified`, whose bodies build a `StringBuilder`, which the prover rejects (error
  4207). **One** false annotation stops the whole file from proving, so the package
  produced no goals at all.
- **2026-10-08** — `src/core` grew `IfaceSymTab`, whose fields are `Map[String, Bool]`.
  The toolchain's proof prelude has **no `Map` theory**, so the generated Why3 file
  declares `map int bool` and neither `moon prove` nor `why3` can load it. The 19
  lemmas never touch `IfaceSymTab`; it is the **PACKAGE** that is proved, and the
  package carries the type.

The first break is fixed here: the two annotations are removed, and the six that remain
are exactly the ones the skill records — `pos`, `span_at`, `zero_span`, `Lens::rank`,
`Lens::lower`, `Family::severity`.

The second is **not** fixed, because its fix changes this package's public API
(`@core.IfaceSymTab` is exported), which is a version-line decision and not a patch.
The README now says so, in place, with the reason and the date.

What did NOT notice any of this: **the release gate never ran `moon prove`.** A
documented command that nothing runs is a comment, and this one had been failing for
two releases. `_verify/check_prove_contracts.ps1` now runs it in the gate and fails on
the false-annotation class — the class that is fixable here — while reporting the
`map` limitation rather than hiding it. It has been shown to go red: re-adding one
false annotation produces 25 errors 4207 and a failed gate.

### The README's version is now read, not pinned -- and the matcher had to be built from the package's own name

`_verify/check_readme_links.ps1` used to require the READMEs to name `0.4.32`
literally. A release then had to edit the GATE as well as the README, and a missed edit
either blocked the release for the wrong reason or let a README naming an old version
through. The version is now read from `moon.mod` — the file the registry reads — and the
failure message says which version the README should have named. The same change was
made earlier to the mutation-gate count, for the same reason.

Reading the version out of `moon.mod` fixed the ROT; it did not fix the MATCHER, and the
first release to use it found that out:

    FAIL: README.md must name 0.4.33 and nothing older; also found: 0.4.32

That `0.4.32` is the sentence `> (This note said **116 → 2** until 0.4.32, ...)` — a true
statement about a correction that happened in 0.4.32, and true in every release after
it. The RULE was right (a version the reader is told to install has to be current) and
the MATCHER was wrong: it matched "anything version-shaped" rather than "a reference to
THIS package". So the matcher is built from the package's own name now:

    moonbit_static_analysis@<v>       what the reader installs
    moonbit_static_analysis_<v>_      what the reader receives

A version number in PROSE is not a reference. A version number that FOLLOWS THE PACKAGE
NAME is. `CHANGELOG.md` is deliberately excluded: every release section names its own
version, and those are historical by construction.

### And the check was looking at two of the three documents that ship

`SKILL.md` goes to the registry with the package (MEASURED: the published 0.4.32 tree
carries it at the top level) and it tells the reader to run

    moonx riantr/moonbit_static_analysis@0.4.32 riantr/moonbit_doubleML

That line has been maintained per release — 0.4.30, 0.4.31, 0.4.32 — and the version gate
looked only at the two READMEs. So a release could sync the READMEs, leave `SKILL.md`
behind, and publish an install instruction for the previous version with a green gate.
The gate now reads all three, and each document's install line is checked separately: the
READMEs show `moon add`, `SKILL.md` shows `moonx`.

Both new rules have been shown to go red:

| the defect | what the gate said |
|---|---|
| `SKILL.md`'s install line set to `0.4.31` | `FAIL: SKILL.md tells the reader to install 0.4.31; the released version is 0.4.33.` |
| `README.md`'s artifact name set to `0.4.31` | `FAIL: README.md must name 0.4.33 wherever it names THIS package; also found: 0.4.31` |

and the historical `until 0.4.32` note stayed FOUND and tripped neither.

### The counts, after

```
    the largest raw-finding file in moonbitlang/core   builtin/int64_test.mbt, 1022
    moon check --target all on the same tree            1 error, 251 warnings, 2 kinds
    live mutations                                       426
    ... of those, expecting a kill                       389
    ... of those, naming the test that must go red       312
    #proof_pure contracts in src/core                     6
    ... of those, false                                  0   (was 2)
    the self-scan                                        170 files, actionable 0
    the corpus pins                                      7 of 7 MATCH
    the per-function census                              TOTAL 58 MATCH
    the census control                                  24 of 24
    the release gate                                     96 stages, every one green
```

## 0.4.32 — the escape that was counting UTF-16 units, the lexical match, and the census that was measured over six corpora

### The character literal's escape: the whole grammar, and a CRASH under it

The standing note for this item said the reader "takes at most FOUR hex digits, which is
exactly the BMP". **The observation was right and the explanation was wrong**, and the
explanation was the dangerous part: a fix written from that note would have bounded the
digits and **still refused `'\u{10000}'`**.

The mechanism, measured in MoonBit: `"\u{1F600}".to_string().length()` is **2** — UTF-16
code units — while `.to_array().length()` is **1** — code points. The reader took as many
hex digits as there were and then checked `s.length() != 1`, which is a **UTF-16 count**.
The escape form was never the problem; the *count* was.

So the reader now implements the toolchain's whole escape grammar (29 forms, each settled
against `moon check`) and counts **characters**. `\xNN` takes exactly two digits; `\u{...}`
takes one to six, with the value at most U+10FFFF and no surrogates; `\uXXXX` takes exactly
four; the byte form takes no `\u` at all. Digits past the limit are consumed but not
accumulated, and a seventh digit flags the literal malformed.

**There was a CRASH under all of this.** `'\u{110000}'` reached `v.unsafe_to_char()` and
raised `RuntimeError: unreachable`, which aborted the **whole scan** — every later file
went unread, and the scan still printed a SUMMARY line, so the failure looked like a corpus
that happened to have fewer findings. The bound is not a refinement of the escape rule; it
is the difference between a scanner that answers and a scanner that stops.

**The character count also unblocks the astral literal that is written out.** It was not
only the escaped form: `builtin/string_methods.mbt:117` is `c == '😂'`, and that is what
stopped the file at line 117. A reader that fixed only the escaped form would have left
half the corpus behind.

### `lexmatch` is a construct, not a name

The named item was the labelled capture `(re"..." as t, after=next)`. The scope was
**re-derived** first: `after=` appears on 283 lines across 22 files in the corpus, and
hand-classifying them found **84 real sites in five files of one corpus** and **zero** in
the other six. The standing note said "18 sites in 3 PINNED core files"; 18 is the two
`diff` test files alone, so both the count and the file count were wrong.

`lexmatch` was read as a plain name, so the parser reported `undefined name 'lexmatch'` at
four corpus sites — on code `moon check` accepts. It is now read as a construct: the
subject, an optional `with longest`, and the arms, which are skipped whole. The expression
is noted as outside the analyzed subset, and it reuses `@ast.EMatch` — the shape is
identical, so a new variant would have rippled through walk/types/infer/interp and the
`.mbti` for no new information.

### A lambda parameter inside an interpolation is a BINDING, not a read

Fixing `lexmatch` made `builtin/autoloc.mbt` readable past its old boundary, and the file
then reported `no visible binding for 'sb'` at 83:5 — `sb` is a parameter of a lambda
inside an interpolation:

```
$|{"filename":\{sb => self.filename.escape_to(sb)},...}
```

The collector flushed the name at the first non-identifier character, and in `sb => sb`
that character is the **space**. Both spellings are handled (`sb=>sb` and `sb => sb`), and
an uncovering is not a regression: the finding was withheld behind the old parse boundary,
so it was **fixed** in this increment rather than pinned as `actionable=1`.

### The census was measured over six corpora, and the seventh was never counted

The `--per-function` box above is rewritten, and the reason is worth reading: the census
that produced 0.4.31's "116 → 2" covered **six** corpora, and `moonbit_core` was not in it.
Measured over seven, the number at 0.4.31 was **66**. Two wasms over the same corpus make
the direction unambiguous:

```
                        pre-0496 (be21ecd)        0496
    files                     1029                 1029      UNCHANGED
    parsed                     935                  957      +22
    actionable                  64                   56       -8
```

The finding sets differ by exactly **8**, with **zero new**: all eight are
`undefined variable 'lexmatch'`. So this increment made the census **better**, and the
number that went up is a number that had never been counted.

The 58 are classified into **twelve families** by a **tracked** census script that fails on
a finding it cannot classify, and the release gate **pins** the number per corpus. None of
them is a defect in the analysed code, and that claim is measured rather than asserted:
`moon check --target all` reports exactly one error on `moonbitlang/core`, in
`json/README.mbt.md`, and it is not one of the twenty-four files that carry a finding. A
file with no diagnostic is indistinguishable from a file nobody opened, so a **positive
control** appends a deliberate type error to each of those files, in a **copy**, and
requires the error back — **24 of 24**. Under `--target js` five of them report nothing at
all, because MoonBit's per-file `targets` options do not compile them for that target: a
file no target compiles is a file the checker never saw.

### The counts, after

```
    test suite                 1163 passed, 0 failed   (1136 before 0496; +27)
    per-function census        66 -> 58 over SEVEN corpora   (core 64 -> 56; proton 2 -> 2)
    the 58                     12 families, and not one is a defect in the analysed code
    the files that carry them  24, and moon check READS 24 of 24
    the census                 TRACKED, PINNED, and it fails on an UNCLASSIFIED finding
    module-view corpus pins    moonbit_core 33 (37 before 0496); the other six BYTE-IDENTICAL
    mutation gates             79 in the release gate (78 before 0496)
    0496's own gate            14 mutations: 13 KILLED, 1 declared survivor with its proof
    gates re-anchored          6 (0459 M4, 0480 M1-M3, 0488 M5-M6)
```

## 0.4.31 — the 116 findings were an inventory of the lens, and the inventory is empty

At 0.4.30 the `--per-function` view reported 7 `actionable` on `moui` 0.1.12, in "four
smaller classes" of lens defect. That was the wrong way round: the number was small because
the view had only been pointed at one corpus, and the *classes* were the real content. This
release measures the view across the pinned corpora — **116 actionable findings** — classifies
them into **eight families**, and fixes each one with a control that must still report.

| family | n | what the lens claimed | the fix |
|---|---:|---|---|
| A | 61 | a destructured name is bound to the **whole tuple** | it is bound to an element — the type lens already answered "Unknown" |
| B | 25 | a `continue`/`break` that **carries a value** is unreachable code | the carried values are the terminator's **own payload**, not sibling statements |
| C | 8 | a statement after a loop whose body always terminates is dead | the loop's "may have broken out" is a **separate** signal from the joined flow |
| D | 10 | an `extern`/FFI call, an omittable parameter read as a positional slot, a name declared **twice**, and a function with no body | **four** defects wearing one name, each isolated by its own probe |
| E | 5 | a trait's method is not a value | the `.mbti` reader harvests the trait's methods as `Trait::method` |
| F | 4 | an integer `/` is typed as `float` | `div_type`, and the constant fold beside it |
| G | 2 | a name bound by an `is`-pattern `as`-binding is not bound | the `as` binding is collected at **any** depth |
| H | 1 | a comprehension does not bind its pattern | the names are bound in a copy of the environment |

**NOT ONE OF THE 116 WAS A DEFECT IN THE ANALYSED CODE.** Every one of them sits in a file
`moon check` accepts, in released, published packages. They were an *inventory of the lens*,
and the inventory is now empty but for two findings that are the documented `#doc(hidden)`
limit — a cross-package hidden function cannot be indexed from the dependency's *source*,
only from its `.mbti`, and answering them would mean growing the analyzer into a source
indexer, which is a different project.

### The module view did not move — except on one corpus, and there it moved DOWN

Six of the seven pinned corpora produce byte-identical module-view numbers, which is the whole
point of keeping the two views separate. The seventh, `moonbit_core`, went from **48 actionable
to 37**, and *how* that number moved is the part worth reading: two wasms were built, one from
the pre-0495 tree and one from this one, and the **same** corpus was scanned by both.

```
    actionable  48 -> 37
    notices     9988 -> 9988   UNCHANGED
    unreliable  2956 -> 2956   UNCHANGED
    withheld    552 -> 552     UNCHANGED
    parsed      935 -> 935     UNCHANGED
    files       1029 -> 1029   UNCHANGED
```

The finding **sets** differ by exactly 11, with **zero new ones**: ten `undefined name 'rl'`
/ `'lr'` (the `is` pattern `(Node(..) as rl)`) and one `no visible binding for
'Arbitrary::arbitrary'` (a trait's method read as a value). The per-file `defects=` headers,
which are not truncated, show that exactly **two of the 680** files with findings changed at
all, and every other file's count is identical. A count alone could not have told eleven
findings fixed from eleven findings traded for eleven new ones; the set can, and it says the
first.

### Five mutation gates that this increment's own source changes broke

The full release gate went red on its first run, at five gates, and the cause was this
increment's own work: 0495 moved the text those gates name. A moved anchor is not a typo to
fix — it is re-anchored onto the current text with the **same** mutation, and then measured
to see that it still kills. All 31 anchors across the five gates are present and unique.

**And then three of the five failed for reasons that had nothing to do with the anchor**,
which is the part worth reading, because a re-anchor that ends in a green gate can hide a gate
that has stopped guarding anything.

- **0.4.25's M7 SURVIVED, and the survivor was right.** 0495 replaced a `falls` flag with a
  list of flows and a join, and the missing-else arm went from *assigning* the fall-through to
  *contributing* one — so it became redundant whenever some branch falls through, which is
  exactly where 0.4.25's fixture sat. The line still governs the case no fixture covered: a
  chain with no else where **every** branch terminates. Measured on the pre-0495 tree, that
  mutation killed exactly one test; on this tree it killed none. So the fix was a **fixture**,
  not a re-anchor — and M7 is killed again.
- **0472's M5 is not expressible any more.** The carried values of a `continue` are the
  terminator's own payload now, `Array[Expr]`, and an assignment is a `Stmt` kind — so the
  mutation cannot be written at all, and the compiler says so. The claim it pinned is now
  enforced **by the type**, which is stronger than a line of code; it is retired with that
  reason, and a **new** mutation pins the other half of the claim ("the values are read") at
  the site where it now lives.
- **0493's M3's named test stopped being the right one.** A fix elsewhere — an omittable
  parameter is not a positional slot — made the row it named stop discriminating between the
  two mechanisms. The row that still discriminates (a label the callee does not have) now
  names it, and the reason is written down rather than assumed.

### A flag for the enumeration

`--findings-shown-per-file N` — the per-file print cap was 40, and counting 116 findings across
four corpora needs all of them. The default is unchanged.

### The counts, after

```
    per-function actionable findings   116 -> 2   (the 2 are the documented #doc(hidden) limit)
                                         ^^ CORRECTED IN 0.4.32 -- that census covered SIX corpora.
    module-view corpus pins            UNCHANGED on six corpora; moonbit_core 48 -> 37
    moon test --deny-warn              1136/1136 on wasm; 1056/1056 on js and wasm-gc
    moon check --deny-warn             exit 0
    self-scan (own source)             167/167 parsed, actionable=0
    mutation gates                     78 gates green; one mutation retired with its reason
```

**The "2" was the census of six corpora, and the seventh was never counted.** The census
that produced it covered `moui`, `moonbit_labeler`, `moonbit_image`, `async`, `proton` and
`proton_contract`. `moonbit_core` was not in it — and `moonbit_core` carries more findings
than all six put together. Measured over **seven** corpora, the number at 0.4.31 was
**66**, not 2. The inventory this release declared empty was not empty.

The fix is not a better sentence; it is a census that is **tracked** (so the seventh
cannot be dropped again), that **names** the corpora it covers, that **fails** on a
finding it cannot classify, and that the release gate **pins**. 0.4.32 adds both:
`_verify/census_perfunction.ps1` and `_verify/control_perfunction_census.ps1`.

## 0.4.30 — the last 89 findings went to zero, and the behavioral lens turned out to be WRONG

At 0.4.29 the six pinned corpora carried **89 actionable** findings between them: async 19,
proton 68, proton_contract 2, and 0 on the other three. This release takes that to **0 on all
six** — over **the same 1081 `.mbt` files** (moui 551, labeler 35, image 17, async 362, proton
114, contract 2 — counted again this release, and unchanged). The self-scan reads **161 files**
now against 68 then, `actionable = 0` throughout, and the suite went from **514 wasm tests to
1067**.

### The frontend read nineteen more grammar forms

Most of that cycle's work was the frontend's. A form the reader cannot read leaves a
**provably incomplete** module frame behind, so every name in it looks unbound and every
operator looks mismatched — the 0.4.7 lesson, *"a clean 0 can be partly obtained by not
looking"*, pointed the other way. Each form was settled against the toolchain before it was
written; the history carries a `settle` commit ahead of every increment whose rule the
compiler had a verdict on.

| the form | the increment |
|---|---|
| a C-style `for` init clause is a **declaration** | 0470 |
| an anonymous `fn`'s tail between `)` and `{` | 0471 |
| a `for` header is ONE grammar, not two | 0473 |
| a loop in **expression** position went to the wrong reader | 0474 |
| a binder head carrying ONE declaration | 0475 |
| the step after a binder head's initialisation clause | 0476 |
| a constructor pattern on the left of a `let` | 0477 |
| the `<?` payload, `expr <? { "k": v, .. }` | 0478 |
| the UTF-8 BOM is skipped, not refused | 0479 |
| the unbraced escape, `'\uXXXX'` | 0480 |
| a nested optional type | 0481 |
| a `for` header separated by line breaks | 0482 |
| a package-qualified holder, `@pkg.Type::method` | 0483 |
| a trait method whose receiver is a reference | 0484 |
| a braced struct pattern in `is` position | 0485 |
| a `+`-joined effect clause | 0486–0487 |
| a `<+` with a next-line operand, a `$|` interpolant | 0488 |

0481 closed the last unread file in proton, 0482 the last in moonbit_image, 0483 the async
files that were last at the time. **Four async files are still not read whole**, and they are
the standing backlog: `re"..."` regex literals, `let { .. } = x` rest destructuring, a `for`
header with a non-empty update clause, and `>..` with `break <value>`.

### `--per-function`: the behavioral lens enters at each FUNCTION

0.4.29 measured the behavior lens on real code and the number was brutal: across **1081 `.mbt`
files on six corpora** its entire readable contribution was **3 actionable findings**, 3.4% of
the 89, and its own families — `Unreachable`, `NonBooleanCond`, `MethodError` — counted
**0 / 0 / 0**. The mechanism was not a defect: the lens enters at the **module**, so a function
body is executed only if something *calls* it from a top-level statement, and a library module
calls none of its own functions.

`--per-function` gives it a second entry: every function is analysed as if it were the
program's entry point, with its parameters bound to fresh abstract values of their **declared**
types — the only sound choice for an entry point, because the runtime value is unknown. The
default view is untouched, and the two views are **separate, not additive**.

And the new view showed the lens was **wrong**, not merely quiet. On moui 0.1.12 it reported
**265 actionable** where the module view reports 0 — an inventory of the lens's own defects, on
code `moon check` accepts. 0490 fixed a list value against a list parameter, an arity rule
that had to become a RANGE, a function whose body is an `if`, a string concatenation, a string
comparison, and a parser that never recorded `omittable`; 0491 fixed the last class — the
**read** path never consulted the cross-file symbol table, while the structural lens and the
lens's own **call** path both had since 0.4.3.

| corpus | 0489 | 0490 | 0491 |
|---|---:|---:|---:|
| moui | 265 | 58 | **7** |
| proton | 136 | 92 | **5** |
| moonbit_image | 94 | 68 | **44** |
| moonbit_labeler | 95 | 48 | **40** |

Seven remain on moui, in four named classes: a name bound by an `is`-pattern, a `None`
receiver, a cross-file constructor's arity, and unreachable code.

### The toolchain renamed the two unsuffixed integer types, and the tables had not followed

0.1.20261012 changed the **canonical spelling** of `Int`/`UInt` to `Int32`/`UInt32`. The types
were not renamed — `Int` remains an accepted alias — but `moon fmt` rewrites to the explicit
names, and the analyzer's ambient type list and method table still carried the old spelling:
**37 findings on this repository's own generated interfaces**, in the DEFAULT view, so every
user on the new toolchain got them too.

The repair is a **union**, not a mirror: the builtin-methods table is what the current
interfaces declare, what the intrinsics add, **and** what the previous table held. 102 names
the new interfaces dropped are carried forward; a probe per name settled 33 of them dead and 69
still callable, and dropping those 69 would have turned valid calls into `undefined function`.

### Two corrections, in place

0490 wrote the wrong toolchain version in seven files and the right one in an eighth place in
the same commit, while the repository had it right in three places since 0.4.22. The
correction is a follow-up commit, not a rewrite.

And a `Get-Content -Raw` round trip on this CP936 box rewrote `—` as `鈥?` **and ate the
newline after it**, merging two comment lines in two places. 19 sites across five files, every
repaired line checked against the PARENT of the commit that introduced the corruption. The two
deliberate ones are left alone — the READMEs show the mojibake on purpose, as the record of
the defect.

### The dependency moves

`moonbitlang/async` 0.22.4 → **0.22.5**, and the whole gate was re-run under it before this
release was cut. The claim that wasm-gc wants a `run_async_main` that async does not export
was re-verified against the new version and still holds: `integration.mbt` guards it with
`#cfg(target="native")` and `#cfg(target="js")`, and `integration.wasm.mbt` — the `wasm`
target only, not `wasm-gc` — is the other half.

## 0.4.29 — `expr as &Trait` is an operator, and the parser had no production for it

`as` was already in the lexer's keyword list. Nothing in the **expression** grammar consumed it.
The postfix loop broke on it, the statement reader took the leftover `as` as the start of the next
expression, and the binding walk resolved it as an ordinary identifier:

```
69:38 - error: undefined name 'as' (UndefinedName) [structural+type]
```

**A name that never existed**, reported as actionable, on a program `moon check` accepts with zero
errors. This is the third instance of the same shape — `guard` (0.4.21), `raise` (0.4.23), now `as`:
a keyword the lexer knows and the parser does not.

### Settled against the compiler, not assumed

`_verify/settle_0428_cast.ps1` compiles three forms and requires two negatives to be rejected:

| program | `moon check` |
|---|---|
| `b as &Sink` | **ACCEPTED** |
| `Box::{ n: 2 } as &Sink` | **ACCEPTED** |
| `Box::{ ..o, n: 9 } as &Sink` | **ACCEPTED** |
| `b as` (no target) | REJECTED |
| `b as Box` (not a trait object) | REJECTED |

`moon check` spells the rule out verbatim: *"`Int` is not a trait object type, it cannot be used on
the right hand side of `as`."* So `as` is an operator the parser must accept, and only its
right-hand side is constrained. Two earlier drafts of this settle settled **nothing** — one used
`fn() => 1` as a lambda (MoonBit lambdas use braces; `fn() => 1` is a 3002), and one used `as Int`
as the target, so every case died on the trait-object rule before `as` was ever the question.

### The fix, and what the node deliberately does NOT carry

`ECast(Expr)` — the operand alone — plus an `as` branch in `parse_postfix_from`. The target type is
read by the existing `type_annotation` and **discarded**.

That looks like a missed opportunity: `as` requires a trait object, so the type looks checkable. It
is not. `IfaceSymTab` keeps no trait/struct distinction — `using @pkg { type View }`, a `trait`
declaration and a `struct` declaration all land in the same `types` set. A check built on that table
would report every cast to a struct type. Carrying the type without reading it would be a field no
lens can consult, which is a worse thing to add than not adding it. This is the 0.4.26 `()`→TNone
lesson pointed the other way: a check whose precondition the tables cannot satisfy is a false-positive
generator, and no check at all is the honest answer.

The **span is the `as` token**, not the operand's. Every other extension in that loop keeps the base
span, but those nodes flatten the base into a name and would otherwise lose its position; here the
operand survives as a child, so its position is still reachable through `ECast`, while the position
of `as` itself is recorded nowhere else.

### The three lenses, and the false positive the fix could have introduced

`walk` **must** walk the operand. `fn to_sink(b : Box) -> &Sink { b as &Sink }` reads `b` and nothing
else does — an arm that returned without walking would report the parameter as never read, trading one
false positive for another. That is the `EComp` lesson in its exact form: the half that is not walked
is the half that vanishes. It has a dedicated test, and M2 kills it.

`infer` types the operand (so a wrong name or a wrong argument type inside it is still found) and
yields `TUnknown`. `interp` evaluates the operand and yields `AAny`, keeping the path live rather
than folding it the way `1 as &Trait` would tempt it to.

### Measured

The population was counted **by the tool's own output**, not by a matcher — the analyzer already
emits one finding per occurrence and the finding names the token, so the count cannot inherit a
matcher's blind spot. `undefined name 'as'`, six corpora: **exactly one**, at
`wzzc-dev/moui runtime/view_tree.mbt:69:38`.

One site is small. It was also **moui's entire actionable count**.

| corpus | actionable before | after | |
|---|---:|---:|---|
| moui | 1 | **0** | the `as` false positive |
| moonbit_labeler | 0 | 0 | byte-identical |
| moonbit_image | 0 | 0 | byte-identical |
| async | 19 | 19 | byte-identical |
| proton | 68 | 68 | byte-identical |
| proton_contract | 2 | 2 | byte-identical |

Self-scan 68/68 parsed (100%), **actionable = 0**.

**Read that number with its coverage attached.** Of the 823 notices, **429 are `test declaration is
outside the analyzed subset`** — `test` is routed to the same braced skipper as `impl` and `trait`,
so 429 test bodies are never walked. That is the single largest exclusion in the self-scan.

The full list is measured by `_verify/backlog.ps1` — and **it was previously hand-assembled and
incomplete**:

| # | notice | count |
|---:|---|---:|
| 1 | `test` declaration | **429** |
| 2 | `match` expression | **155** |
| 3 | **`if` expression** | **45** |
| 4 | `struct` declaration | 36 |
| 5 | `derive` declaration | 31 |
| 6 | `enum` declaration | 14 |
| 7 | anonymous function literal | 10 |
| 8 | `const` declaration | 6 |
| 9 | short lambda | 2 |
| 10 | `try` expression | 1 |

That is 729 **printed** notices, with **94** more behind the per-file display cap (823 − 729), so the
table is a lower bound rather than the whole. **Every row is a span the frontend read past and did
not analyse**, which means what lives inside it is invisible to all three lenses: reads are lost and
so are bindings. Removing a row means adding an AST node for that form, so these are **features**, not
notices to be reworded.

`actionable = 0` is a claim about the declaration bodies that *are* analyzed, not about all 823
excluded bodies; the 0 is partly earned by not looking at the largest group of them. This is the
0.4.10 shape — *"a clean 0 can be partly obtained by not looking"* — pointed at the project's own
test suite.

### There is a **second** route by which the 0 is earned, and it is function-granular

The paragraph above is about which **declaration bodies** are never walked. There is another route
it does not mention, and it is quieter.

`Walker::audit_suppressed` (`walk.mbt:354`) treats **any subset-exclusion region overlapping a
function's line range** as "I cannot conclude anything about this function", and then switches that
function's `UnusedLocal` / `UnusedParam` / `ParamChanged` off **entirely** (`walk.mbt:707`,
`walk.mbt:1011`).

Measured by `_verify/match_read_discriminator.ps1`, positive control included:

| case | local never read | result |
|---|---|---|
| function contains **no** unanalysed region | yes | **reported unused** |
| function contains **one** `match` | yes | **not reported** |

Same local, same function; adding a `match` to the function is enough to silence the unused check
for all of it. So *"a local read only inside a match arm is not reported unused"* does **not** mean
"the read inside the arm was recorded" — the first version of that probe asserted exactly that, and
it was wrong. The truth is suppression.

Two consequences, both real:

1. **Expression-level** exclusions that land inside a function body — `match` (155), `if`
   expression (45), anonymous fn (10), short lambda (2), `try` (1) — **213 in total** — switch off
   the unused check for the **whole function**. **Declaration-level** exclusions sit outside every
   function's extent and do **not** trigger this: `test` (429), `struct` (36), `derive` (31),
   `enum` (14), `const` (6) — **516** in total. The source says so at `walk.mbt:349-351`, and
   `backlog.ps1` prints the two classes separately rather than leaving the split to be asserted.
2. Therefore **part of `actionable = 0` is green because it is not looking** — the same shape as
   the test-body exclusion above, on an axis nobody had written down.

There are **two** suppression sites, not one: top-level functions at `walk.mbt:1010`, and **local
functions** (`SLocalFunc`) at `walk.mbt:710`. The reason is in the comment at the latter — *"`sp`
here is the local function's whole extent, so a `match` inside ITS body suppresses its frame audit
the same way."*

**What was NOT measured**: how many functions in this project are switched off this way. 213 is an
**upper bound**; the exact count needs each function's line range and the analyzer does not export
it. A labelled bound beats a precise number from a hand-rolled brace scanner that could be wrong.

Tests: 442 js (12 new) / 514 wasm / 442 wasm-gc. Five mutations, four killed, one expected survivor,
every restore byte-identical by SHA256.

### What the behavior lens actually contributes on real code

`src/interp` is the largest module in the project: an abstract interpreter with a lattice, a call cache
and virtual stacks. Whether it earns its place is not a README's call, so it was measured.

`_verify/lens_audit.ps1` does two things. **Phase 1** counts — every rendered finding carries its lens
tag (`report.mbt:50`), so the share is readable straight out of a scan. **Phase 2** is the differential,
and it is the step that decides: `analyze_module` is made to return nothing, the analyzer is rebuilt,
and every report is diffed **over the same unchanged corpus tree**.

| corpus | `.mbt` | actionable on | off | delta |
|---|---:|---:|---:|---:|
| moui | 551 | 0 | 0 | **0 (byte-identical)** |
| moonbit_labeler | 35 | 0 | 0 | 0 |
| moonbit_image | 17 | 0 | 0 | 0 |
| async | 362 | 19 | 18 | **1** |
| proton | 114 | 68 | 66 | **2** |
| proton_contract | 2 | 2 | 2 | 0 |
| **all six** | **1081** | **89** | **86** | **3** |

**The behavior lens is not dead code — but its entire readable contribution is 3 actionable findings
across six corpora and 1081 `.mbt` files, 3.4% of the 89.** All three are `undefined function`, and all
three sit on **qualified** cross-package constructor calls: `Set::from_array` in async,
`@async.CondVar::Cond` twice in proton. On the largest corpus, moui — 551 files, 3288 printed
findings — silencing it changes the output **not at all**.

The sharper number is about the lens's **own** families. `interp` is the only emitter of `Unreachable`,
`NonBooleanCond` and `MethodError`, and those three count **0 / 0 / 0** of the 89 actionable findings.
Not "few" — zero. A lens built to notice that code after a `return` is unreachable has not once
reported unreachable code in 1081 real files. The README has explained the mechanism since 0.4.16:
the interpreter analyses a body only when a **top-level statement reaches it**, and in real code very
few functions are called from the top level.

**This does not claim those three families are dead.** I built synthetic probes
(`_verify/lens_matrix.ps1`, seven shapes) and **none of them fired** — not even the shape known to
fire, which meant scanning proton's own `facade_notification.mbt` as a single file, because the probes
have no package context and `@async` does not resolve. That is the same probe defect 0.4.16 already
documented: **a probe measures the probe, not the lens.** The zeros support no claim; the differential
is the evidence.

### The survivor, and the gate bug it exposed

**M4** (interp stops evaluating the cast operand) survives, and it took three fixtures and a
measurement script to establish that it survives *legitimately* rather than for want of a test:

1. `MethodError` inside the operand — there is none. `1.nomethod()` reports nothing, and the one
   finding my probe counted was a **warning** (`UnusedParam`) that a grep for `error:` had filtered out.
2. The same idea in a function that is never called. `Interp::run_top` skips `SFunc` outright
   (`interp.mbt:389`).
3. The same idea in `fn main` — which is *also* an `SFunc`, and is skipped the same way.

`_verify/probe_0429_m4.ps1` then applied the mutation, rebuilt, and diffed the analyzer's real output
on five programs. **All five byte-identical**, for two measured reasons: an unbound name inside a
cast operand is reported by *walk* as `undefined name`, and the interpreter's `undefined variable`
shares its family and span so `merge_findings` shows one and hides the other; and `FMethodError`
and `FOpMismatch` share the `"arg-type"` group (`core.mbt:380`), so an operator mismatch inside the
operand collapses too.

**This is recorded as "no fixture I could build observes it", not as "proven equivalent over the whole
input space."** Those are different claims and only the first is supported. The `eval` is kept because
every sibling arm (`EField`, `ETupleField`, `EStruct`, `EComp`, `EMethodCall`) evaluates its operands —
consistency is a reason, not a proof.

**And the gate itself was wrong first.** An earlier run reported *"M4 KILLED, 2 of 442 red"* while the
two tests doing the killing were **failing on clean code** — they asserted a `MethodError` the
analyzer never emits. Every later mutation reported those same two red, so the gate looked healthy
and the one mutation it had not pinned was reported as pinned. `_verify/mutate_0429.ps1` now runs the
suite **unmutated first and aborts if it is not green**, because a mutation count only means something
against a green baseline.

## 0.4.28 — `derive` has no body, and a ParseError notice was saying otherwise

`derive(Debug, Eq, Clone)` is a **parenthesised trait list with no braces**. The top-level
dispatch sent it through `skip_decl_braced` — the skipper for `struct` / `enum` / `trait` /
`impl` / `extend` / `test`. Two things followed, and **only one of them was visible**:

**One, the message was false.** `skip` builds its text from a `braced` flag, so every derive
notice read *"its body was not analyzed"* — and a derive **has no body to analyze**. 570 of
those in production code across the six corpora.

**Two, it could eat its neighbour.** `skip_decl_braced` scans forward for `{`, breaking only
at a `fn`. So in

```moonbit
derive(Debug, Eq)
struct Box { n : Int }
```

the **struct's braces were consumed as the derive's body**, and the struct's own exclusion
notice was never emitted. The file claimed one deliberate exclusion where it had made two, and
the lost one is exactly the fact the notice exists to record.

### The mistake I made, same family as 0.4.27's

I measured how often `derive` is *immediately* followed by a braced declaration in moui 0.1.12:
**zero**. And then I wrote down "a latent bug with no corpus impact."

**The measurement was right and the inference was wrong.** The skipper does not stop at the
next line — it scans until it finds **any** `{`, which may be many lines away. It had been
eating declarations all along; they just were not the adjacent shape I looked for.

| notice | before | after | delta |
|---|---:|---:|---:|
| `derive` (old wording) | 575 | 0 | −575 |
| `derive` (correct wording) | 0 | 547 | +547 |
| **struct** | 572 | **829** | **+257** |
| **enum** | 155 | **246** | **+91** |
| **extend** | 238 | **308** | **+70** |
| **total** | **5,026** | **5,399** | **+373** |

**+418 declaration exclusions that were previously invisible.** The notice count going **up** is
the fix working — those 418 were being swallowed.

**Actionable findings are unchanged in all six corpora** (moui 1 / labeler 0 / image 0 /
async 19 / proton 68 / proton_contract 2). No new false positives.

### What this release does NOT do

The notice **stays**. The analyzer genuinely does not model derived implementations, so a
reader is right to be told; only the false claim about a body is removed. **This is not
looking better by reporting less.**

Tests: 430 js (5 new) / 502 wasm / 430 wasm-gc. Four mutations, four killed, every restore
byte-identical by SHA256. M1 (revert the routing) and M2 (the message claims a body again) are
deliberately separate — with only M1 killed, the tests would pin the *routing* and happily
accept a message claiming a body that does not exist.

## 0.4.27 — a parenthesised function type in return position is no longer read as a tuple

A function type in return position has two spellings, and only one of them was recognised:

```moonbit
-> (Int) -> String     the `->` is AFTER the matching `)`
-> (() -> Int)         the `->` is INSIDE the parens
```

The second fell into the tuple arm of `return_annotation`. That arm consumes to the first `)`
that is not preceded by a comma — and in `(() -> Int)` that is the paren closing the EMPTY
parameter list, so the annotation ended at `()` and `-> Int)` was left in the token stream.
`parse_block` then went looking for `{`, found `->`, and reported `expected '{'`; after that the
file was dead. One annotation took the whole file with it, and the message named a brace that
was never the problem.

The test is now "is there a `->` *associated* with these parens", and there are exactly two
places it can be — inside them, or immediately after the matching `)`. One nesting-tracking scan
answers both; the condition becomes `arrow_inside || is_fn`.

Every affected spelling is settled first, zero errors from `moon check`: the parenthesised form,
the parameterised form, the nested one whose result is a tuple, the optional `-> (() -> Unit)?`,
the `raise`-bearing one, and the multi-line signature with a generic and a qualified name.

### Corpus effect, measured as a two-build A/B on one tree

**First, a number that nearly went down as a win.** proton's actionable count reads **68** on this
tree against a recorded **100**. A gap of 32 looks like a large win and it is not: the corpus
TREE changed. The old baseline was taken against a TEMP sibling tree, and `--extern-iface-dir`
feeds sibling interface tables into the run. **Comparing a number across two trees measures the
trees, not the change.** Only two builds on one tree can attribute anything.

The A/B says: only moui moves, and **three files go from PARTIAL to fully parsed** —
`services/service_task.mbt`, `core/program_subscription.mbt` and
`backend/common/services/service_async_queue.mbt`. `unexpected token` drops from 113 files to
110. The other five corpora are **byte-identical**.

### My measurement script reported a false zero twice

That is the real result of this release, and it is worth more than the fix.

**The first is the A/B above.**

**The second is "how many sites does this shape have".** The measurement script reported "0
across all six corpora" twice. The first matcher, `\([^()]*\)`, cannot match a nested paren at
all — it reported "not found" for a shape that contains one by construction. After switching to a
balanced scan it **still** reported 0. The paren logic was right that time; the prefix was wrong:

```regex
\bfn\s+[A-Za-z_]\w*\s*\([^()]*\)\s*->\s*\(
```

Every clause is wrong for ordinary MoonBit: `fn` immediately followed by `[` (`fn[T]`) never
matches; `[A-Za-z_]\w*` does not match `ServiceTask::start`, because of the `::`; and
`\([^()]*\)` cannot span a multi-line parameter list or one whose parameters are themselves
parenthesised. What it missed is the single most common spelling in the corpus:

```moonbit
pub fn[T] ServiceTask::start(
  self : ServiceTask[T],
  complete : (ServiceTaskResult[T]) -> Unit,
) -> (() -> Unit)? {          ← `-> (`, and an arrow inside
```

**The real count is 24 sites across 9 moui files**, not 0.

**The rule: a matcher that is too narrow does not report "none found", it reports "I did not
look" — and on screen the two are the same shape.** Matching a real signature is a *parsing*
problem; doing it with a regex is a bet. So the current version does not try to recognise a
signature at all. It finds every `->` token and asks whether the group that follows it contains an
arrow, which cannot fail to look at a signature because it never needs to know what one looks like.
And its control is not a synthetic file but the A/B: it **must** find the three files the A/B says
changed, or the gate aborts.

### A settle has to prove it is measuring before anything it says counts

While writing this release's fixtures, the settle script reported **fifteen cases "clean" and
checked nothing**, because the case keys had **no `.mbt` extension**: the cleanup filter
`-Filter '*.mbt'` matched no files, so every case ran on the accumulated pile, and `moon check`
does not compile extensionless files. It printed 44 bytes of
`Finished. moon: ran 2 tasks, now up to date`.

Fifteen green rows. **The only evidence was the negative control, which also read "clean".**

Three guards now each close one half of that failure: G1 asserts exactly one `.mbt` in `src`; G2
asserts `moon check` actually did work (non-empty capture, and not the do-nothing banner); G3
asserts the negative control **goes red**, and voids the whole run otherwise.

Two MoonBit facts came out the same way: **lambdas use braces** (`fn() { 1 }`; `fn() => 1` is
`unexpected token '=>'`), and **an uppercase top-level name is a type** (`fn G() -> Int` is
`unexpected token '(', you may expect '::'`).

### Mutation gate: four killed, one proved equivalent

Five mutations, four killed. **M4 survives, and it is an equivalent mutant — proved, not assumed**:

- the tuple arm returns `""` (`parser.mbt:1272`)
- the function-type arm returns `"(Int)"` (`fn_type_annotation:1016` — no `->` follows, so `out`
  stays the parenthesised group)
- `ann_to_ty("")` == `TUnknown` (`types.mbt:140`)
- `ann_to_ty("(Int)")` is **also** `TUnknown` — no arm of `ann_to_ty` strips the parentheses

The annotation string has exactly one consumer, `declared_ret`, and every input M4 redirects
feeds it `TUnknown`. So over the **whole input space** M4 cannot change an observable.
Fabricating a fixture to kill it would be theatre: the mutant has no behaviour to kill.

My first attempt asserted that `ann_to_ty("(Int)")` was `TInt` — **wrong**, which is why that
fixture changed no verdict. It stays (the declared-return path deserves a fixture), but its
comment now says what it does and does not establish.

Tests: 425 js (13 new). Every fixture is checked by BOTH `moon check` and the analyzer.

## 0.4.26 — a tail expression is the return value, and a fix found by reading code instead of by a corpus delta

**Correcting myself first.** The note this release started from said the declared return
type renders `None` for tail-expression bodies and is "**probably bigger than `raise`
itself**". **Measured, that is wrong.** `raise` accounts for 1,213 sites across the six
corpora; tail-expression functions account for **305** (moui 108 / moonbit_labeler 64 /
async 69 / proton 40 / moonbit_image 24). About a quarter, not more.

**The corpus delta is zero.** Six corpora, 12,428 files, byte-identical to 0.4.25. This
is a **correctness fix** with a reproducer, not a cleanup.

### The defect: the tail expression's value was thrown away

A tail expression parsed as an `SExpr`, and `SExpr` explicitly discards its value:

```moonbit
Interp::exec_stmt   SExpr(e) => { let _ = self.eval(e, env) }
Interp::analyze_fn  let ret = join_vals(self.ret_vals)
join_vals           if vals.length() == 0 { return AType("None") }
```

So `ret_vals` stayed empty, `join_vals` answered `None`, that `None` went into the **call
cache**, and **callers inherited it**:

```moonbit
fn f() -> Int {
  1
}
fn g() -> Int {
  f() + 1        // reported: no method matching +(None, int)
}
```

A confident false positive about code that compiles. The control fixture with `return 1`
is clean, and the wrong value survives two levels of callers — because it is **stored**,
not returned.

Equally important: **the analyzer's own signature line said `f() -> None`.** That line is
its statement about what it understood, so being wrong there is a defect even when no
finding fires.

### The fix: a new `STail` node and a `fn_body` flag

`STail` is produced only in a **function body** — which is exactly what the
`fn_body : Bool` flag is for. The same block parser also reads loop bodies, `if` arms and
bare blocks, and in those a trailing expression is an ordinary **discarded** expression
statement (`fn f() -> Int { while c { 1 } }` returns nothing at all).

The three lenses differ. walk is identical to `SExpr`. The type lens **joins** the tail's
type into the inferred return type (`scan_returns` previously knew nothing about it). The
behaviour lens **records** the value and leaves the **flow alone** — nothing follows a tail
expression anyway. There it **must** be evaluated, which is the exact opposite of a `raise`
operand: everything after a terminator is dead code, so there the value is deliberately
not evaluated.

### The settle: my first version was empty, and empty in two separate ways

The first version reported "0 errors" for twelve shapes, **including one real MoonBit
rejects**. Two independent bugs, both of the kind that do not announce themselves:

1. **`moon check` only type-checks a body REACHED from `fn main`.** With no `main`,
   nothing was type-checked at all.
2. **The script deleted `src/moon.pkg` itself** (`Get-ChildItem src -File | Remove-Item`),
   so from the first case on there was no package to check and `moon check` printed
   nothing. Add PowerShell turning a native command writing to stderr into a
   `NativeCommandError`, and the merged string came back empty — **two independent
   failures stacked, producing a clean bill of health for a program the compiler
   rejects.**

Fixed, there are now **two negative controls**: `fn f() -> Int { "a" }` reports 4014 and
`fn f() { 1 }` reports 4074. **A settle only measures something when its negative control
goes red.**

It also turned up two facts about the **language**:

- `while s == "a" { "b" }` is **4139** — a loop body's trailing expression is discarded,
  and only Unit may be discarded silently. My first loop fixture was written exactly that
  way. **A fixture the compiler rejects is not a fixture.**
- **A tail expression requires a declared return type** (4074). Which is precisely why
  the latent surface is 305: the population this defect can touch is the population the
  compiler already forces you to annotate.

### A regression I caused, caught only by the six-corpus byte diff

I also taught the type lens that `()` is Unit, to match the interpreter. `TNone` is a
**concrete** type, so an empty tuple compared against anything else became a report —
wzzc-dev/moui `backend/macos/macos_backend.mbt:204` gained
`unsupported operand types for '>': 'int' and 'None'`. That file's parse stop point, notice
count and actionable count were all identical a moment earlier; **only the six-corpus diff
saw it.**

The type-lens half is reverted; the interpreter half stays — that is where the value the
signature line prints comes from. **M5 and M6 are now a permanent pair in the gate**: M5
reproduces the mistake I made, M6 is its opposite ("every tuple is Unit").

### Mutation gate: 7 mutations, green on the first run

Seven mutations over four decisions in four files: the parser's `fn_body` (M3), position
(M4), whether the flag reaches a function body at all (M7), whether the behaviour lens
records (M1), what it records (M2), whether `()` is Unit (M5), and whether a real tuple is
still a tuple (M6). **7 killed, 0 survived**, every restore verified byte-identical by
SHA256.

The pre-flight added in 0.4.25 paid for itself immediately: two patterns in this gate's
first version were written against a three-line arm that `moon fmt` collapses to **one
line**, and the pre-flight aborted in milliseconds and printed the line it was looking
for — instead of wasting a whole `moon test` run learning nothing.

Tests js 412 / wasm 484 / wasm-gc 412 (was 398 / 470 / 398). Self-scan 63 files,
**actionable 0**.

## 0.4.25 — the behaviour lens leaked flow between `if` branches, and a check that could not fire

**This release has no corpus delta, and that is measured, not inferred.** Six corpora,
12,428 files: every scan is byte-identical before and after. `Unreachable` was 0 findings
before and is 0 after. So this is **a correctness fix with a reproducer** — not a claim
that it cleaned up anything. Turning a zero into a win is exactly the sentence this
project keeps refusing to write.

### The defect: no join between branches

`Interp` explores an unknown condition's branches ONE AFTER ANOTHER in the same
instance, so the flow state simply carried over between them: a branch that terminated
made the **next** branch's first statement look unreachable, and whatever the **last**
branch left behind was what survived past the whole `if`.

The shortest reproducer contains **no `raise` at all**:

```moonbit
fn f(g : Int?) -> Int {
  guard g is Some(v) else {
    return 0
  }
  return v
}
```

reported `return v` as `unreachable code`. The else terminates, the then does not, and
the else's flow won the race. `guard` is modelled as an `SIf` with an **empty**
then-branch, so the then never terminates — the defect was live at every
`guard ... else { ... }`. That is the shape of proton 0.3.4
`facade_app_metadata.mbt:81-82`, except that the else there holds a `raise`.

### The fix: per-branch reset plus a fall-through join

Each branch resets `self.flow = FNormal` before running and contributes
`falls = self.flow == FNormal` after; a **missing else is always `falls = true`** (no
branch is taken, so control continues); the join at the end is
`self.flow = if falls { FNormal } else { FReturn }`. `exec_alt` changed from `Unit` to
returning `Bool`, and its own `ABool(false)` arm does the same join.

Two MoonBit details are recorded in the source:

- **An enum does not implement `Eq` by default.** `self.flow == FNormal` reports
  `Type Flow does not implement trait Eq`, so `priv enum Flow` gained `derive(Eq)`.
- `for j in (idx + 1)..elseifs.length()` parses as `(idx+1)..elseifs` and then
  `.length()` (reported as `type Int has no method arr`), so walking the remaining
  else-ifs has to be a `while`.

An `ABottom` condition keeps its old meaning (it does not terminate, it falls through).
Whether a bottom condition should suppress everything downstream is a separate question,
and this release does not answer it in either direction.

### Mutation gate: eight mutations, three rounds to green

| Round | Result | Why |
|---|---|---|
| 1st | **1 killed / 3 survived / 3 no-op** | three pattern strings never matched the source at all |
| 2nd | **6 killed / 1 survived (M6)** | patterns fixed; M6 turned out to be a fixture-coverage problem |
| 3rd | **8 killed / 0 survived** | two fixtures added, plus M8 |

Neither kind of survivor was "not enough tests". They were dumber than that, and they
are written down here because they will happen again.

**One: a fixture has to actually reach the code it claims to test.** `f(1)` binds `n` to
`AInt(1)`, `binop` folds `n > 0` to `ABool(true)`, and the then-branch runs alone — the
arm the join lives in is never entered. `f(g())` with `g` undefined returns `ABottom`,
which silences the whole body: "no findings" and "the test passed" look identical. Four
mutations died on this in the first version.

The shape that does reach it is `s == "a"`: `binop`'s `OpEq | OpNe` arm returns
`AType("bool")` unconditionally, and there is no string arm to fold with. Two
alternatives were measured too: `f(@core.nothing)` (`AAny` absorbs into
`AType("bool")`) and `x is Some(v)` (`EIs` returns `AAny` on purpose — so **every
`guard` in real code already reaches the join**).

The control that goes with it matters: **same shape, opposite expectation**. The folded
fixture (`f(1)`, no `else`, then-branch returns) expects **1**; the unfolded fixture
(`f("a")`, same shape) expects **0**. That inversion is the evidence they really take
different arms. The first version used `f(1)` for both, so its "control" was only
re-testing constant folding.

**Two: a NO-OP mutation is only reported after a full suite run.** M5 and M6 were
written with 10 spaces of indentation where the file has 8 and 6, and M7's pattern said
`None => true` where the source reads `None => falls = true` — three wasted
`moon test` runs, each learning nothing. There is now a **pre-flight**: if any pattern
is absent from the pristine text the run aborts in milliseconds and prints the line it
was looking for. On the fourth round it immediately caught one of my own mistakes (M8's
Find string had copied M6's **replaced** text).

**Three: M6's survivor was a coverage problem, not a pattern problem.** `exec_alt`'s
**terminal** `match els` only runs when there are **no else-ifs left**, and every chain
fixture at the time had one. No amount of re-matching could kill it, because no fixture
reached that code. Adding one also turned up **M8** — the terminal version of "a missing
else always falls through", equally unobserved — so M8 was added. M6 and M8 now change
**one line inside the same 8-line block**, and they are the two directions of one
decision: M6 makes the terminal arm unable to say "terminated", M8 makes it unable to
say "falls through". A block that can say neither is useless, and neither mutation is
visible without the other's fixture.

Tests js 398 / wasm 470 / wasm-gc 398. `_verify/scan_0425.ps1` compares BOTH baselines
(0.4.24 and the earlier 0.4.25 scan) and writes a fresh filename rather than
overwriting — the same reason `scan_0423.ps1` says "two scans writing the same filename
is how a baseline silently becomes its own comparison", now used a second time.

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
- ~~After the three parser fixes 219 files are still not read whole; the dominant
  cause remains `unexpected token`.~~ **Superseded — measured, 0.4.30.** That
  bullet could not be acted on, because `unexpected token` named nothing: it was
  the catch-all arm of `parse_atom` with no token in the message, and the scanner
  tallies unreadable files *by reason message*, so 110 of wzzc-dev/moui 0.1.12's
  122 unreadable files were one anonymous row. `tok_desc` now names the token
  (exhaustively, all 46 `Tok` variants) and the same run became a 13-row
  distribution with every other SUMMARY number byte-identical.
- **`a..<=b`, the INCLUSIVE range.** The lexer carried a comment saying "`..=` is
  not modelled: it was not measured in the blocked corpus this token was added
  for". True when written; stale by the time anyone read it again, and it cost 4
  files of moui. Measured against the toolchain, one form per package with a
  broken canary beside each: `0..n` is **REJECTED** — "Missing `=` after `..` in
  range expression. Hint: use `a..<=b` for inclusive range or `a..<b` for
  exclusive" — `0..<=n` is accepted and `0..=<n` is rejected. So the inclusive
  form is `..<=`, and a bare `..` staying two TDots is **correct** rather than an
  omission. The four-character test has to run **before** the three-character one:
  the other order lexes `0..<=n` as `..<` followed by `=n`, which is exactly the
  bare-`..`-then-`=` shape the toolchain rejects.
  It is a **separate token** rather than another `TRange`: `walk`, `types::infer`
  and `interp` all treat `ERange(a, b)` the same, reading both operands and
  nothing else, so **none of them models inclusivity**. The inclusive end is
  therefore read and NOT analysed, and says so — otherwise `a..<=b` and `a..<b`
  are the same tree, and iterating n times versus n+1 times is not a difference
  to drop without saying it out loud.
- The nine largest classes behind that distribution were then fixed, in order — the
  `?` optional-argument shorthand `f(x?)`, a lambda used as a parameter's default
  value, a method chain continuing on the next line, a `match` whose subject starts
  on the following line, an **arrow lambda in expression position**, the
  **inclusive range**, the **qualified `is Type::Ctor` constructor**,
  **`(expr : Type)` ascription inside parentheses**, and **`value[:]` empty slice
  bounds**.
  **486/608 (79.9%) → 590/608 (97.0%)**, `unreliable` 1696 → 246, `withheld` 238 → 2.
- **`is Type::Ctor`: the ranking was wrong again, and in a new way.** The backlog
  called it "`is` patterns in *expression position*", which reads as "`parse_is` is
  never reached". It is reached, and has been at the right precedence tier for
  several releases. What is missing is *inside* `parse_is_pattern`: the lexer has
  **no** `TColonColon`, `::` is **two** `TColon` tokens, and the pattern reader
  bumped the constructor name and returned without consuming them. The surviving
  `:` walked back through `parse_cmp` into `parse_atom`'s catch-all — which is why
  the scanner's reason string reads ``unexpected token `:` `` on a line whose only
  `:` is a path marker. **That is the fourth time a reason string has been the wrong
  thing to rank by**, and the fourth time `blockers.ps1` — which joins each reason
  back to its blocking *source line* — gave the opposite answer. moui gained
  exactly the 5 files the re-rank named, no more; proton's `parsed` and `actionable`
  did not move, and its `unreliable` went 950 → 927.
- **This round overturned my own ranking twice, which is worth recording.** The first
  four classes were ranked by the scanner's *reason wording* (`unexpected token ':'`,
  `expected ')'`), and I read those rows as `is` patterns and function types. Joining
  them back to the actual source lines showed the largest class was neither: it was
  **arrow lambdas** — `(a, b) => …`, `(_n : T) => …` — unreadable in a `let`
  right-hand side and as a **positional** call argument.
  The cause is that three sites each handled part of it: `at_arrow_lambda` (bare
  `x =>` only) on the positional path, `at_lambda_head` (every spelling) only after a
  named `name =`, and nothing at all in `parse_expr`. So `g(a => a)` parsed and
  `g((a) => a)` and `let h = (a, b) => a + b` did not. **A reason string is not a
  reason.**
- The same branch surfaced two things that were not its own doing:
  1. **A comprehension's `=>` is spelled exactly like a lambda's.** Three call sites
     (the iterable, the guard, the body) now use `parse_or`; the first version missed
     the iterable and five comprehension tests went red immediately.
  2. **`at_lambda_head` had a lookahead that could cross the file.** It treats `::`
     as the colon of a parameter's type annotation, then scans to the next `=` — and
     `=>` is `TAssign` + `TGt`. So a `T::{}` followed, tens of lines later, by any
     `=>` was read as one enormous lambda head. **The self-scan found this, not the
     tests**: `src/core/core.mbt` and `src/lexer/lexer.mbt` dropped from 71/71 to
     69/71 while all 551 tests stayed green, because no test had a `::` expression
     and a `=>` in the same file. The regression test is therefore written as a PAIR.
- With the lookahead bounded, async's `actionable` goes 13 → 14 and proton's 54 → 61.
  **These 8 are not new defects — they are what the blind scan was hiding**: 4x
  `undefined name 'noraise'` (proton's `fn f() -> T noraise {`), 3x
  `no visible binding for 'InvalidSetting'` and 1x `'Waiting'` (the latter four are
  the standing cross-file suberror limitation). A/B measured: removing the
  doubled-colon guard alone does NOT bring them back (the bounds stop the scan
  first), removing the bounds alone does NOT either (the guard stops it first), and
  removing both reproduces the original `PARSED 0/1`. **A lookahead wide enough to
  eat a `=>` sixty lines away is not a reading worth keeping to buy that quiet.**
- `defer` fixed a class of FALSE POSITIVE rather than an unreadable file. Without the
  arm, `defer` was read as an ordinary identifier and reported
  `undefined name 'defer'` — a claim about the *analyzer*, on code `moon check`
  accepts with zero errors. async 0.22.4 **18 → 13**, proton 0.3.4 **55 → 54**, also
  A/B measured (arm switched off, same two corpora rescanned: **7 rows of
  `undefined name 'defer'` disappeared**, 5 in async and 2 in proton including
  `command/command.mbt:145`, with **zero** new findings introduced).
- proton went 55 → 56 → 54 → 61 across the changes. The `match` fix made one more file
  readable, which *exposed* more instances of this false positive. **Reading more
  files raising the false-positive count before lowering it is the normal shape of
  this metric.**
- **27** remain on moui. After `is Type::Ctor` landed, `blockers.ps1` was re-run and
  the order came out: `(expr : Type)` ascription in parens **6 files** (first),
  `value[:]` empty slice bounds **4**, `async fn(…)` in argument position **3**, the
  `fn f() -> T = "js" "sym"` FFI declaration form **2**, plus 5 singletons. The entry
  I had ranked first last round (`is`, then recorded as 4 files) was really 5, and
  the one I had third (`(expr : Type)`, recorded as 3) was really 6 — **the list had
  been ranked by the old reading all along.**
- `name?=value` is **settled: not a gap.** Both `?=` and `~=` come back MOON-BAD, so
  the toolchain itself rejects that call-argument form. Adding support for a spelling
  `moon check` will not accept would be the wrong move; it is recorded as a non-gap.
- **The same round produced a gap with 48 sites that blocks exactly ONE file, and
  that is the part worth keeping.** `is @pkg.Type::Ctor` — a package-qualified
  constructor — does not parse at all: the pattern head begins with `@`, `peek_name()`
  only accepts `TName`, so the reader returns having consumed nothing. 48 sites across
  the corpora, 32 of them in moui across 16 files. Scanning each of those 16 files
  **alone** (`_verify/pkg_head_impact.ps1`) gives `parsed=1/1` for fifteen of them and
  `parsed=0/1` for exactly one, `backend/macos/macos_services.mbt` — the other fifteen
  keep the site inside a `test` block, which is skipped whole. **Sites are not
  files**; ranking this at 32 would have put a one-file fix ahead of a six-file one.
  More worth recording: it is **invisible to the ranking tool too**. Cross-referencing
  "files containing an `@pkg` is-head" against `blockers.ps1`'s blocked list gives
  OVERLAP **0**, so the gap looks free — because `macos_services.mbt` is one of the
  four blocked files that print **no `PARTIAL` line at all**, having zero findings
  before its boundary. `blockers.ps1` says in its own header that its list is a
  lower bound, and this landed precisely outside it. ⇒ **A lower bound that agrees
  with "no problem" is not evidence of no problem**; cross-referencing two lists only
  tells you about the part both of them can see. Pinned as a KNOWN LIMIT with a
  control that drops the `@sqlite3.` prefix, in `parser_0436_test.mbt`.
- **`(expr : Type)` ascription in parentheses.** The grouping branch of `parse_atom`'s
  `TLParen` arm parsed the inner expression and then demanded `)`, which is where all
  six blocked files died — `expected ')'`, on a line whose `:` is a type marker and not
  a typo. The scope was settled by the toolchain rather than by convenience: four
  forms, one package each, canary beside every one.

  | form | moon | |
  |---|---|---|
  | `('0' : Int)` | **MOON-OK** | the only legal form, the one implemented |
  | `let y = 1 : Int` | MOON-BAD | no parentheses: rejected |
  | `(1 : Int, 2)` | MOON-BAD | ascription on a tuple element: rejected |
  | `(s : Int)` where `s : String` | MOON-BAD | so: an **assertion**, not a coercion |

  The last row is why there is **no subset-exclusion notice**, and it is the mirror of
  0.4.30's `..<=`. That one discards a value too and does get a notice, because an
  inclusive end turns n iterations into n+1. An ascription changes nothing at runtime
  — the compiler has already checked the type — so announcing a subset exclusion there
  would report a loss that does not happen. Gate 0437's M3 invents exactly that
  notice, and it is killed by a **control** (comparing the two spellings' report
  counts) rather than by a positive test.
- **The first UNDER-delivery of the round, worth its own line.** Ascription held
  **6 files** in the blocked list and delivered **+2**. The other four fail **earlier**,
  on something else, so fixing the ascription was never going to reach them — which is
  what "`blockers.ps1` ranks by *first* error" means. Three increments running, three
  times the list count and the delivered count disagree (`is` +5 against +5, `..<=`
  +5 against +4, ascription +2 against +6). ⇒ **A row count in `blockers.ps1` is not a
  forecast**; ranking by it is a heuristic, not a measurement. Delivered: `is` +5,
  `..<=` +5, ascription +2 — which does *not* preserve the order the lists gave.
  moui's `unreliable` 406 → 335, `withheld` 51 → 34, `notices` 3999 → 4050 (the right
  direction: a file that parses produces subset-exclusion notices, one that stops early
  cannot). The other five corpora are **byte-identical**. **25** blocked files remain.
- **`value[:]` — the largest jump of the round, and the first one that COST
  something.** `parse_postfix_from`'s bracket branch called `parse_expr()` for the
  START bound and only then asked `at(TColon)`, so a `:` sitting directly after `[`
  went to the expression parser and the file died with ``unexpected token `:` `` —
  the reason string on 8 of the blocked files, and on every one of those the `:` is a
  bound separator. The comment there said an open `[:n]` "is not in the corpus and
  reports honestly"; `chars[:index]` made that stale, and "reports honestly" was
  disguising a blocker. The missing bound becomes `EBigInt`, the same opaque
  placeholder the open END already used, because `const_eval` must not fold a bound
  it never read.
  moui **583 → 590 (+7, the round's largest)**, `unreliable` 335 → 246,
  `withheld` 34 → **2**, blocked files 25 → 18; proton 101 → 103, async 226 → 227.
- **But moui's `actionable` went 0 → 1 and proton's 61 → 63 — the first time this
  cycle that reading MORE files has raised an actionable anywhere.** Not a
  regression, and not free either, so the whole accounting is here rather than a
  claim of "no new defects":

  | corpus | new finding | recorded limitation |
  |---|---|---|
  | moui | `macos_native_ime.mbt:437` `parameter 'prefix' may not be used` | `prefix` IS used, at line **442**, inside a `catch { }` body; the `catch` arm consumes its block with `skip_braces`, so a read that happens only there is invisible (KNOWN LIMIT, pinned at `parser_0432_test.mbt:155`) |
  | proton | `app_control.mbt:5` `undefined name 'noraise'` | `parse_raise_effect` handles `!` and `raise E` but not `noraise` |
  | proton | `updater/hex.mbt:22,45` `no visible binding for 'MalformedSignature'` ×2 | a suberror variant used in a different file — the per-file `enum_ctors` limitation |

  All three are **pre-existing limitations of this analyzer** on code `moon check`
  accepts, and none is caused by the slice change, which only made those files
  readable. It is the shape this README described long ago: reading more files
  raises false positives before lowering them. Even so, moui's `actionable` has left
  0 for the first time, and that number IS the standing objective's own metric — so
  the pin moves up with the reason written down rather than quietly, and fixing the
  `catch`-body limitation is the way to move it back. That makes it the cheapest
  thing on the board: the finding is already located and the defect is already
  pinned as a test.
- `_verify/blockers.ps1` ranks *files that cannot be read*; `_verify/backlog.ps1`
  ranks *subset-exclusion notices*. They answer different questions and the
  conflation was the reason this bullet sat unfixed for fourteen releases: only
  the first moves the `parsed=` number.

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
