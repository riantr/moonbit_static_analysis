# Increment narrative

Extracted from `_verify/release.ps1` by `_verify/_split_release_narrative.ps1`.
Nothing here is executable and nothing here is an expectation: `release.ps1` does not
read this file. It is the record of what each increment was WRONG about, what it was
settled against, and what the evidence was -- the part a future reader needs and cannot
reconstruct from the diff alone.

It lived inside the release script because that was the only file being read at the
time. At 0470 the script measured 1811 lines with 262 of them code: 84% narrative, and
1270 contiguous lines of it between the corpus stage and the pin table. A release entry
point nobody can skim is not an entry point.

Newest first would need re-sorting on every increment, so this is chronological, the
order the blocks were written in. The live caveats that bear on the pin table itself
stayed in `release.ps1` next to the table.

---


## 0.4.30, 0440: a `.mbti` `suberror` body declares value constructors


ONE PREDICATE, and it was the largest single false-positive source in the
project. `parse_iface` set `in_ctor_body = matched == "enum " && d > 0`, so a
braced `suberror` body was matched and descended into -- its member types were
collected -- and its member NAMES were discarded.

proton's OWN generated interface says, at `pkg.generated.mbti:68`,

    pub(all) suberror AppConfigurationError {
      InvalidSetting(name~ : String, message~ : String)
    }

and `collect_iface_symtabs` already reads the target's own tree, the target's
root being `iface_dirs[0]` in `sa/main.mbt`. `InvalidSetting` was written down
in the file being scanned and was still reported as having no visible binding.

  moui             actionable  0 -> 0    parsed 590 UNCHANGED
  moonbit_labeler  actionable  0 -> 0    parsed  25 UNCHANGED
  moonbit_image    actionable  0 -> 0    parsed   2 UNCHANGED
  async            actionable 12 -> 12   parsed 227 UNCHANGED
  proton           actionable 78 -> 12   parsed 103 UNCHANGED
  proton_contract  actionable  0 -> 0    parsed   4 UNCHANGED

80 actionable findings across the six corpora became 24. proton's drop is 66,
larger than the 58 the re-rank counted before the change, because 0439's 15
catch-body findings were the same shape -- `err => raise MalformedJson(..)` --
and were waiting on this same harvest.

WHY IT WAS INVISIBLE FOR SO LONG, which is the part worth keeping. The MAIN
PARSER already harvested suberror bodies (`Parser::skip_decl`: `what == "enum"
|| what == "suberror"`), so a variant used in the file that DECLARES it always
resolved. proton's `.mbti` files carry 30 braced suberror bodies and 0
body-less ones, so no rare spelling ever showed up as a discrepancy. Only the
CROSS-FILE path was broken, which is why the symptom was false positives on
correct code rather than unreadable files -- and why reading more files, the
move that has fixed every blocker so far, could never have fixed this one.


## 0.4.31, 0441: two top-level functions of ONE NAME shared one table


A TABLE KEYED BY A NAME THAT IS NOT UNIQUE. `WalkResult.fn_bindings` was a
`Map[String, Array[Binding]]` keyed by `f.name`, and BOTH consumers looked a
function's declarations up by that name -- the walk at pass 3 and, separately,
`Infer::run_fn` in the type lens. Two top-level functions of one name therefore
shared ONE table and the second `set` overwrote the first, so every function of
that name was analysed against the LAST one's parameters.

It is now an `Array` parallel to `fns`, indexed by position, and `run_fn` takes
its bindings as an argument because the position is the caller's to know. There
is no longer any by-name lookup to get wrong.

`#cfg` IS HOW REAL CODE REACHES THIS, AND IT IS NOT THE CAUSE. MoonBit allows
two top-level functions of one name when `#cfg` gates them per platform, and
`Lexer::lex_attribute` deliberately emits NO token for an attribute, so both
variants are analysed together -- a stated fidelity cost, not an accident. The
regression test has NO `#cfg` in it at all, because the defect is the key and
not the attribute. `#cfg` appears 689 times across 99 async files: that is how
real code reaches the defect, not what causes it.

  moui             actionable  0 -> 0    parsed 590 UNCHANGED
  moonbit_labeler  actionable  0 -> 0    parsed  25 UNCHANGED
  moonbit_image    actionable  0 -> 0    parsed   2 UNCHANGED
  async            actionable 12 ->  7   parsed 227 UNCHANGED
  proton           actionable 12 -> 10   parsed 103 UNCHANGED
  proton_contract  actionable  0 -> 0    parsed   4 UNCHANGED

24 actionable across the six corpora became 17, and `parsed=` did not move on any
of them -- which is the acceptance criterion here, because this was a change to
how findings are ATTRIBUTED, and a change that lowered one corpus while raising
another would be a regression wearing a fix's clothes.

WORTH KEEPING: this gate failed its FIRST run with all four mutations KILLED.
M2 and M4 named the test that was supposed to pin `run_fn`'s own by-name lookup,
and that test did not go red -- a guard claiming coverage it did not have,
written with a source in which mistyping a parameter could not show up. The test
was rewritten rather than the claim re-anchored onto something that did go red,
and the rewrite was proved green on clean code AND red under both mutations
before the gate was re-run. The four kills are the SECOND run. The whole account
is in `mutate_0441.ps1`.


## 0.4.32, 0442: `noraise { .. }` is a handler block, not a name


FOUR FALSE POSITIVES ON CODE `moon check` ACCEPTS, and the shape of the fix was
not the one the findings suggested. proton `facade_identity.mbt:99` and `:136`,
`protocol_wbtest.mbt:5`, and async `network.mbt:68` all reported
`undefined name 'noraise'`.

THE GRAMMAR IS SETTLED BY THE COMPILER, `_verify/settle_0441_noraise.ps1`, 8/8
as predicted with the positive control green: `noraise { pattern => body }` is
a postfix handler block on a COMPLETED `try ... catch`. A `try expr noraise {..}`
with no catch is REJECTED, the arm list is `catch`'s grammar, an empty block is
rejected, and the pattern binds the base's RESULT value. Nesting the production
inside the existing `catch` arm is therefore faithful grammar rather than a
convenient placement, and it cannot swallow a user's own `noraise` function.

THERE ARE TWO PARSER PATHS AND THE FINDINGS LIVE IN THE SECOND ONE, which cost
most of the increment. `parse_postfix_from` reads the postfix `catch`; the
statement-level `try` is read by the PREFIX reader and its catch loop ends in
`skip_braces`. The first change taught the postfix path `noraise`, and the
result was a fully GREEN suite with a COMPLETELY UNCHANGED corpus -- all four
findings still present. A green suite is not evidence that a corpus finding
moved; the two are separate measurements and only the second is the claim.

  moui             actionable  0 -> 0    parsed 590 UNCHANGED
  moonbit_labeler  actionable  0 -> 0    parsed  25 UNCHANGED
  moonbit_image    actionable  0 -> 0    parsed   2 UNCHANGED
  async            actionable  7 ->  6   parsed 227 UNCHANGED
  proton           actionable 10 ->  7   parsed 103 UNCHANGED
  proton_contract  actionable  0 -> 0    parsed   4 UNCHANGED

17 actionable across the six corpora became 13, with `parsed=` unmoved
everywhere. The statement-level block is CONSUMED but not analysed, deliberately
and consistently with the lines above it: that branch is the un-analysed `try`,
its body is already skipped and `note_skip` already put a hole in the frame, and
reading the `noraise` arms alone would find reads in a block whose sibling
catch block is deliberately unread.


## A HARNESS DEFECT THIS GATE FOUND, WHICH AFFECTS EVERY GATE


Gate 0442 reported five of five KILLED and still reported MUST-RED MISS on all
five, naming as evidence the very tests that had gone red. The needle and the
captured name were BYTE-IDENTICAL (65 bytes each, same hex).

The cause: `mutate_lib.ps1` matched with `-like`, and PowerShell's `-like` runs
the PATTERN through escape processing, where the backtick is the escape
character. A needle containing a backtick therefore cannot match a name
containing the same backtick -- and this suite's test names are full of them,
because the doc comments are markdown. Bisected on the failing needle: a
30-character prefix with no backtick matched, 40 characters with one did not.
`-like` also treats `[` `]` as a wildcard set and throws on an unbalanced one,
so a bracketed test name could crash the harness rather than merely miss.

Rule 6 asks a SUBSTRING question and was being answered with a PATTERN matcher.
It is now an ordinal `IndexOf`, which is that question. All 27 gates were
re-checked: no gate relied on wildcard behaviour, and the one `MustRed`
containing a `?` (0430's `f(x?)`) is a literal in that test's name, so it
matches exactly.


## 0.4.33, 0443: `nobreak { .. }` is a postfix block on a LOOP


One false positive, and the smallest increment in a while: proton
`internal/bridge_admission_test/main.mbt:20` reported `undefined name
'nobreak'` on code proton 0.3.4 compiles.

SETTLED, not assumed -- `_verify/settle_0443_nobreak.ps1`, 10/10 with the
positive control green, after three corrections to the probe itself:

  - it is a postfix on a LOOP, and the compiler REJECTS `expr nobreak { .. }`
    with no loop at all, so matching the keyword loosely would accept programs
    the compiler refuses.
  - it is accepted on `while` AND `for`, so the wrap is applied to all three
    loop forms. The corpus site happens to be a `while`, so a `while`-only
    parser would have passed the corpus measurement while being wrong.
  - the body is a STATEMENT LIST: `nobreak { 1 }` is rejected 4139, a value in
    statement position cannot be dropped. A different shape from `noraise`,
    which takes an arm list.
  - an EMPTY `nobreak { }` is ACCEPTED, unlike `noraise { }`. The two are easy
    to assume identical and are not, and a parser copying `noraise`'s "at least
    one arm" rule would reject valid MoonBit.

  moui             actionable  0 -> 0    parsed 590 UNCHANGED
  moonbit_labeler  actionable  0 -> 0    parsed  25 UNCHANGED
  moonbit_image    actionable  0 -> 0    parsed   2 UNCHANGED
  async            actionable  6 -> 6    parsed 227 UNCHANGED
  proton           actionable  7 -> 6    parsed 103 UNCHANGED
  proton_contract  actionable  0 -> 0    parsed   4 UNCHANGED

13 actionable across the six corpora became 12. async is UNCHANGED and that is
the expected result rather than a disappointment: it carries 34 `nobreak` lines
and every one of them was already blocked or already excluded. A census number
is not a finding count -- the same lesson `noraise` taught at 4x the size.

THE NODE NEEDS FOUR ARMS AND THE FIRST DRAFT HAD ONE. `walk_stmt` learned
`SNoBreak`, and the suite's two `for` tests then failed with `no visible
binding for 'x'` and `no visible binding for 'i'` -- the FOR BINDERS, not
`nobreak`. There are two binding collectors, not one: `collect_fn_bindings` for
a function's own declarations and `collect_top` for the module frame, and both
have a `_ => ()` catch-all, so the compiler said nothing about the missing arms.
A top-level `for` executes at module level and so puts its binder there. M4 and
M5 pin the two collectors separately.


## 0.4.34, 0444: a bare LOWERCASE `is` pattern head is a BINDING


Six actionable findings, async 6 -> 1 and proton 6 -> 5, `parsed=` unchanged on
all six. Twelve across the six corpora became six.

SETTLED, not assumed -- `_verify/settle_0444_is_head.ps1`, 9/9 with BOTH the
positive control and a deliberately-broken canary green:

  - `if probe() is err && err != 0 { err }` COMPILES: a lowercase head BINDS,
    so it is not a constructor test and must have a binding.
  - `if opt() is Some && Some != 0` is REJECTED. Uppercase is a constructor
    test, and "a function compared with an integer" is the only reading that
    explains the rejection. So case is not a heuristic, it is the grammar.
  - an unused head binding AND an unused payload binding are both LEGAL, and `_`
    binds nothing. `is St::Shutdown` binds nothing either.

THE PROBE'S FIRST DRAFT WAS WRONG IN A WAY THAT WOULD HAVE BEEN MISREAD. It
used an `Int` base with `Some`/`Err`, so three cases failed 4014 for a plain
Int-vs-Option mismatch and would have read as "uppercase is rejected". The fix
was a second `opt() -> Option[Int]`, NOT a revised expectation. A failing
positive control means fix the prelude, never the expectation.

THE CORPUS SYMPTOM AND THE ISOLATED SYMPTOM WERE TWO BUGS' FINGERPRINTS FOR ONE
CAUSE. 0444 reported `unsupported operand types for '!=': 'fn err (signature
not read)' and 'int'` in async schannel.mbt -- NOT `undefined name 'err'` --
because something else named `err` is in scope in that package and wins. An
isolated reproduction reports `undefined name 'err'`. Two symptoms, one cause,
and only the isolated form points at the parser. The shape-based re-rank would
have filed 0444 under the TYPE lens, and the type lens was already correct.

BINDING THE HEAD INTRODUCED A NEW FALSE POSITIVE THAT THE SETTLE CAUGHT.
`Walker::bind` puts the name on the audit list, so an unused `is` head binding
reported `local variable 'err' assigned but may not be used` -- a false
positive, `b_lower_unused` ACCEPTED. `EIs` therefore uses `bind_pattern`, which
never touches `self.orders[fi]`. That also fixes the PRE-EXISTING payload half
(`is Some(v)` with `v` unread), so the fix is strictly an improvement on both
halves rather than a trade between them.

  moui             actionable  0 -> 0    parsed 590 UNCHANGED
  moonbit_labeler  actionable  0 -> 0    parsed  25 UNCHANGED
  moonbit_image    actionable  0 -> 0    parsed   2 UNCHANGED
  async            actionable  6 -> 1    parsed 227 UNCHANGED
  proton           actionable  6 -> 5    parsed 103 UNCHANGED
  proton_contract  actionable  0 -> 0    parsed   4 UNCHANGED

GATE 0444: 2 KILLED (M1 the parse, M3 the walk), 3 declared SURVIVED with a
measured argument -- M2/M4/M5 are green because `bind_pattern` never reaches
the audit list (so no `UnusedLocal` can appear) and `Infer::EIs` seeds a
spurious name as `TUnknown`, i.e. resolved-and-unknown rather than unresolved,
which can only SUPPRESS a type finding. Both mutations are quieter; a
suppressed finding is not observable in this tool's output. Declared honestly
as expressing the settled grammar while NOT being load-bearing against today's
lenses -- they would become so the moment a lens began auditing `is` bindings.

AND THE SAME ARGUMENT, ONE SCALE UP: 0444 COST FOUR PINS THAT WERE STILL
LOAD-BEARING. This is the part that must not be buried in a gate log.

Moving `EIs` from `bind` to `bind_pattern` closes the unused-local audit for `is`
bindings: `bind` appends to `self.orders[fi]`, `bind_pattern` never touches it.
Every guard inside `pattern_binding_at` was observable ONLY through that audit,
because the phantom names each one prevents -- `true`, `Os`, `core`/`Role`/
`Checkbox`, `Gone`/`PageUnavailable` -- are never READ anywhere. A name that binds
but is never read resolves (no `UndefinedName`), and `Infer::EIs` seeds it `TUnknown`,
which can only suppress a type finding. So four pins that had been load-bearing
since 0.4.19/0.4.21 stopped being load-bearing:

    0419 M1  is-pattern keyword test          646/646 green
    0421 M6  qualified-path rule removed      646/646 green
    0421 M7  nested-constructor rule removed  646/646 green
    0421 M8  or-pattern depth rule removed    646/646 green

The move itself is REQUIRED, not a trade: the settle measured 9/9 that an unread
`is` head or payload binding is legal MoonBit, so auditing them would be a false
positive on correct code. All four guards remain in the source and remain
semantically right; none of them is load-bearing against today's lenses.

WHAT PROVES IT IS THE CHANNEL AND NOT A STALE ANCHOR: gate 0421 M5 anchors on the
SAME `depth >= 2` expression, survives the same parser change, and still KILLS,
because its symptom is `UndefinedName` -- it leaves `error` unbound in
`is Some(Os(error))` where `error + 1` reads it. Same file, same change,
different channel, opposite outcome.

GATE 0436 ALSO BROKE, for the ordinary reason, and is re-anchored rather than
retired. 0444 added `qualified = true` inside the `::` consumption loop and a new
block between `let binding` and `if self.at(TLParen)`, so all four Find strings went
absent and the preflight aborted before a suite ran. M1 and M4 additionally stopped
being VALID mutations: they deleted that loop, and the loop now sets a variable the
head-binding decision reads, so deleting it no longer compiled at all (COMPILE-ERR,
no `Total tests:` line -- a mutation that cannot build measures the compiler, not
the guard). Both now point the loop condition at a token a qualified head never
sits on: same broken behaviour, still builds. Anchors shortened to the two lines
carrying `qualified = true`, unique to this one of the three qualified-path readers,
which is the point -- the previous anchors named surrounding prose and that is what
0444's growth invalidated. 0436 is back to 3 KILLED + 1 declared survivor.

GATE 0436 M4 IS DUPLICATE M1 UNDER A SECOND NAME, which predates 0.4.34 and is
recorded rather than quietly rewritten: both mutations stop the `::` loop from
running, and they differ only in which named test they pin. The "consumed AFTER
the payload test" in its title is not what its Find/Repl pair expresses -- a real
ordering mutation would MOVE the loop below the `TLParen` branch. Both still KILL,
so nothing is unprotected today; the duplication is a genuine weakness.


## 0.4.35, 0445: the builtin-method table could not see GENERIC methods


The defect was in the GENERATOR, not in the analyzer. `tools/gen_builtin_methods.ps1`
extracted methods with a pattern demanding the name come straight after `fn`:

    (?m)^\s*(?:pub\s+)?fn\s+([A-Za-z_][A-Za-z0-9_]*)::([A-Za-z_][A-Za-z0-9_]*)

MoonBit's generated interfaces put type parameters there --
`pub fn[K : Eq] Set::add(Self[K], K) -> Unit` -- so every generic method of every
builtin type was invisible. Measured against the toolchain in hand the old pattern
produced ZERO hits on `<core>/set/pkg.generated.mbti`, which alone declares 32 of
them, and missed 445 names across the tree.

WHY IT STAYED INVISIBLE. `Array::add` was never reported on any corpus only
because real MoonBit writes the METHOD form `a.add(x)`; the qualified form
`Array::add(a, x)` is mostly used for constructors. That is the shape the one
finding had: `Set::from_array`, async 0.22.4 `src/http/send.mbt:37`, reported
`undefined function` on code `moon check` accepts.

AND IT IS NOT A DECLARED `fn` AT ALL. `#alias(from_array)` sits above
`type Set[K]`, so the DIRECTIVE is where the name is written. The generator now
carries pending aliases to whatever declaration follows, and keeps only
identifier-shaped ones -- `#alias("_[_:_]")` is a quoted operator and is not a
qualified name this table can hold. 140 such names; 1265 in the table against 656
before, VERIFIED A STRICT SUPERSET with none lost.

  moui             actionable  0 -> 0    parsed 590 UNCHANGED
  moonbit_labeler  actionable  0 -> 0    parsed  25 UNCHANGED
  moonbit_image    actionable  0 -> 0    parsed   2 UNCHANGED
  async            actionable  1 -> 0    parsed 227 UNCHANGED
  proton           actionable  5 -> 5    parsed 103 UNCHANGED
  proton_contract  actionable  0 -> 0    parsed   4 UNCHANGED

Six actionable across the six corpora became five. proton is UNCHANGED and that is
the expected result, not a disappointment: its remaining five are `undefined name`
and `undefined function` on names that are not builtin methods at all
(`CookieWaiting`, `@async.CondVar::Cond`), so no amount of table can move them.

THE 18 `T::to_json` NAMES, AND A HYPOTHESIS THAT WAS WRONG. Those names appear in
NO `pkg.generated.mbti` in the tree, and the table had been generated at
moon 0.1.20260920 against a toolchain that is no longer installed, so the reading
was "stale, drop it". They are not stale: `Bool::to_json(true)` COMPILES today.
They are intrinsic members, the same category as `Array::make`, which is why the
generator carries a hand-settled intrinsic list. They are listed there now, and
gate 0445's M3 exists so that dropping them again is a red suite.

The sweep that "confirmed" it was worse. Calling `T::to_json(1)` for all 45 bare
types reported 35 as nonexistent, and every one of those was a TYPE mismatch,
because `1` is not a `Bool`. A probe wrong about its own prelude produces a
clean, confident, entirely false answer; the settle survived it only because a
correctly-typed case sat beside the malformed one. Second time this repository
has been caught by it, and both times the fix was the PRELUDE.

NOT ESTABLISHED, and deliberately claimed nowhere: whether the `.mbti` fn-head
FORMAT changed between those two toolchains, or whether the generator was always
blind to generic heads. The old toolchain is not installed. The claim here is the
gap against the toolchain in hand, and nothing earlier.

GATE 0445: 4/4 KILLED, every named test confirmed, every restore byte-identical.
M1 generic head, M2 alias of a type constructor, M3 name no interface declares,
M4 alias of a METHOD. M4 is pinned on table MEMBERSHIP rather than behaviourally,
because `Array::clone` is a deprecated alias of a deprecated spelling that no
corpus writes -- a behavioural test for it would have meant inventing a call site
no measurement produced.

## 0.4.36, 0446: a `#|` closer is a BLANK one, and the lexer was eating it


Three of the five remaining actionable findings were ONE predicate, and the cause was not
a missing declaration. proton 0.3.4 `facade_types.mbt` declares `CookieWaiting` and
`CookieCompleted` at lines 589-594, but the scanner read that file only to line 246.
`region_line` is `first_error_line`, so a file that hit an error was cut at the error and
contributed NOTHING to the cross-file symtab -- and the sibling that USES those names was
told they were undefined. Three findings, three files, one predicate.

WHY THE FILE WAS CUT. `lex_block_string` demanded a `#|` with only whitespace BEFORE it
on its line. The CLOSER is a `#|` with nothing AFTER it, so it satisfied that demand and
was consumed as content; the block never closed and the lexer went on reading it as code.

THE RULE, SETTLED BY VALUE, not by acceptance. `moon check` accepts EVERY shape -- all
nine probes passed it -- so it measures nothing here and was not used to settle it.
`moon run`'s printed string settles it, in `_verify/settle_0446_block_string.ps1` (9/9,
positive control green). A closer is a LINE-LEADING `#|` whose rest of line is blank;
trailing spaces are fine and it may be indented. Every other `#|` is a content segment.
Segments are trimmed and joined by a SINGLE SPACE, and the closer contributes an empty
final segment, hence the trailing space. End of input also closes, with no trailing empty
segment, and is still reported. A non-blank line without `#|` ends the block as CODE with
no unterminated report; a blank line does not.

THE OLD HEADER WAS WRONG, AND IT IS RECORDED RATHER THAN DELETED. It claimed the closer
needs whitespace BEFORE it, and listed `#|AAA\n#|BBB trailing -> "AAA\nBBB trailing"` as a
measurement. Both are false: trailing text is CONTENT, and the join is a space, not a
newline. Its one correct claim -- that the closer may be indented -- had NO test of its
own and survived only because an unrelated test happened to indent one.

  moui             actionable  0 -> 0    parsed 590 -> 591
  moonbit_labeler  actionable  0 -> 0    parsed  25 ->  26
  moonbit_image    actionable  0 -> 0    parsed   2 UNCHANGED
  async            actionable  0 -> 0    parsed 227 -> 253
  proton           actionable  5 -> 2    parsed 103 -> 106
  proton_contract  actionable  0 -> 0    parsed   4 UNCHANGED

Five actionable across the six corpora became two, and 31 more files parse fully -- the
sum of those `parsed` deltas -- with none lost anywhere. NOT A GENERAL TRUNCATION FIX:
178 other truncated files across the corpora have other causes. The
`unterminated block string literal` report itself fired on only 4 files, and that is NOT
the same count as the 31 extra parses; a file cut here can stop short without ever
producing that report. This note does not claim the two sets are identical.

GATE 0446: 5/5 KILLED, every named test confirmed, every restore byte-identical. M1/M3
first came back COMPILE-ERR -- they removed a binding still read later (`j`), or made
`cur` an unused `let mut` -- so what they were measuring was the COMPILER. Both were
corrected to compile, with the failure recorded in their `Prove`.

M2 is the one worth reading. It indents the closer, and no test had ever done that: seven
tests for this construct all put the closer at column 0 because they were copied from each
other, so the rule was pinned only by an UNRELATED test that happened to indent. Two tests
were added and M2 re-pointed at them.

WHAT IS LEFT, and it is not this predicate: proton `facade_notification.mbt:12,14`,
`undefined function '@async.CondVar::Cond'` twice -- a qualified path through
`pub using @cond_var {type Cond as CondVar}` in async's `pkg.generated.mbti`.

WHAT THE RELEASE GATE CAUGHT IN 0446, AND IT WAS IN 0446'S OWN CODE. The first
run of this file failed at stage 2 with four `0020` deprecation warnings: the new
`lex_block_string` wrote `cur.to_string().trim().to_string()`, and `StringView::to_string`
is deprecated in favour of `to_owned`. `--deny-warn` turns those into errors, so the
suite stopped before a single mutation gate ran. All four sites now say `to_owned()`.

A GREEN TEST TALLY IS NOT `--deny-warn` CLEAN, and the reverse is also true.
During development this same code reported `moon test --target wasm` at 655/655;
under this suite the same package exits 1 and prints NO tally at all. The cause
of THAT discrepancy is NOT ESTABLISHED and is not claimed here.

0.4.37 supplied the cleaner half of the same point, in the OPPOSITE direction: a
`local` binding in a new test file left `moon test --target wasm` reporting
662/662 PASSED while `moon check --deny-warn` failed it -- `local` is a MoonBit
reserved keyword and the test runner does not treat that as fatal. Neither stage
is a substitute for the other in either direction, which is the actual reason
this suite runs both. A suite running only the tests would have shipped four
deprecation warnings; a suite running only the linter would have shipped a
reserved-keyword binding inside the test that guards the re-export link.

Counted as shipped: wasm 657/657 (the two tests M2 forced into existence are in that
657), js 585/585, wasm-gc 585/585. js and wasm-gc run fewer because `src/sa` needs the
async runtime and degrades off wasm. GATE 0446: 5/5 KILLED.


## 0.4.37, 0447: a RE-EXPORTED type carried its name but not its MEMBERS


These were the last 2 actionable findings in existence across the six corpora.
proton 0.3.4 `facade_notification.mbt:12,14` writes

    gate: @async.CondVar::Cond(),

and was reported `undefined function '@async.CondVar::Cond'` on both lines, on
code the toolchain accepts. async 0.22.4 re-exports the type under that name --
`pub using @cond_var {type Cond as CondVar}`, `src/pkg.generated.mbti:111` -- and
`@cond_var/pkg.generated.mbti` declares `type Cond` with `pub fn Cond::Cond() -> Self`.

BOTH HALVES WERE ALREADY IN THE TABLE. The re-exported NAME, because the `using`
branch pushed it into `declared`; and `Cond::Cond`, because `@cond_var`'s own
interface is read and its signatures are bare. Nothing CONNECTED them.
`has_value` tried the exact key and then `unqualified`, so `@async.CondVar::Cond`
became `CondVar::Cond`, found nothing, and reported a name written down two files
away. It looked like a missing declaration and was a missing LINK.

THE RULE, settled WITH THE TOOLCHAIN in `_verify/settle_0447_condvar_alias.ps1`
(6/6, three negative controls firing). A constructor IS callable through an
aliased type re-export, CROSS-PACKAGE -- and a name that does not exist is STILL
rejected through it: `[4029]` for a missing member, `[4032]` for a missing type.

THAT SECOND HALF IS THE POINT, and it is why this is a link and not a
suppression. An earlier version of this fix -- silence every `@mod.X::m` that
reaches a re-exported name -- ALSO takes these two findings to zero, on all six
corpora, with a green suite and nothing whatever to tell the two apart. Gate
0447's M2 is that version, and the control test is what kills it. The settle
exists because the corpus cannot make that distinction and the test can.

  moui             actionable  0 -> 0    parsed 591 UNCHANGED
  moonbit_labeler  actionable  0 -> 0    parsed  26 UNCHANGED
  moonbit_image    actionable  0 -> 0    parsed   2 UNCHANGED
  async            actionable  0 -> 0    parsed 253 UNCHANGED
  proton           actionable  2 -> 0    parsed 106 UNCHANGED
  proton_contract  actionable  0 -> 0    parsed   4 UNCHANGED

TOTAL actionable across the six corpora is ZERO, and `parsed=` did not move on
any of them -- so this is a false positive removed, not a corpus traded. notices,
unreliable and withheld are identical on all six too; only proton's `total`
falls, by exactly the 2 findings that were wrong.

TWO LIMITS, recorded because they are limits and not because they were reached.
The alias key is the BARE re-exported name, since `collect_iface_names` reads
interface text and is not told which module it came from -- two modules
re-exporting different types under one name would collide, first-one-wins. And
only the FIRST alias on a re-export line is recorded, because later segments have
already lost their package qualifier to the `{`-strip. The whole table is flat in
exactly this way, so neither is a new shape of limit; neither is a claim that the
mapping is sound, and no corpus here exercises either.

The settle also records two SCAFFOLD facts that cost a wasted run each: `moon.mod`
must declare `source = "src"` or the build plan fails and every case reads ACCEPT,
and a package cannot import its OWN root package. Its first version reported all
three negative controls as ACCEPT for the first reason, and its second did so for
the third -- it normalised the toolchain's output with `replace '\s+', ' '` before
matching `(?m)^Error:`, which destroys the line boundaries the pattern needs. Four
malformed probes in four days now, each of which would have reported the right
answer for the wrong reason.

GATE 0447: 4 KILLED + 1 declared SURVIVED (M5, the redundant bare form: both
callers apply `unqualified` to every candidate and `unqualified("@cond_var.Cond::Cond")`
IS `Cond::Cond`, so the extra entry cannot be reached). wasm 662/662, js and
wasm-gc 590/590 (up 5 on each 鈥?the five 0447 tests live in `moonfiles`, which is
not a `src/sa` package, so they run on every target). Self-scan 88/88 actionable 0,
up one file and six notices over 0.4.36: the new test file.

## 0.4.38, 0449: an EXTERNAL fn binding, and a TUPLE STRUCT that read the next declaration's brace


TWO DEFECTS IN ONE INCREMENT, because fixing the first one found the second.

DEFECT A. `fn f() -> T = "module" "symbol"` -- a `fn` whose body lives in another
language is DECLARED, not defined. The parser finished the signature, found `=`
where it wanted `{`, and reported `expected '{'`: the parser naming a token that
was never the problem. That report is the file's `first_error`, so the file went
NOTPARSE and everything after the declaration went unread. Settled with the
toolchain in `_verify/settle_0449_ffi_decl.ps1`, 7/7 with BOTH negative controls
firing; all three shapes (no parameters, single-line list, multi-line list) are
ACCEPTed by `moon check`. Cost on moui 0.1.12: FOUR of the seventeen files
`_verify/diagnose_moui_truncations.ps1` reports, the largest single shape there.

DEFECT B. `struct Name(T)` -- a tuple struct has no body, so the braced skipper
scanned forward for the `{` that opens one and took the NEXT declaration's brace.
On async 0.22.4 `src/process/cancellation.mbt` that brace belongs to an `if`, so
the `let` and the `if` went with it and `else` / `SIGTERM` were reported as
undefined variables -- two false positives on correct code. Settled in
`_verify/settle_0449b_tuple_struct.ps1`, 8/8 with three negative controls.

THREE HYPOTHESES WERE FALSIFIED before that one, and the record is worth more
than the fix: the `is` pattern, a qualified receiver, and a cross-package
`@pkg.field` receiver each looked like the cause, and each probe varied the `if`.
The cause was never in the `if`. It was that what came BEFORE the `if` had no
`{` to stop at.

TWO CLAIMS IN THE OLD GATE PROSE WERE FALSIFIED BY MEASUREMENT, and both are
corrected in place in `_verify/mutate_0449.ps1` rather than quietly dropped.

  1. `extern_fns` does NOT suppress `undefined function`. It is consumed at
     exactly one place, `walk.mbt:1170`, guarding `audit_frame` -- so what the
     registration buys is `UnusedParam = 0` on a header-only fn whose body was
     never read. Dropping it leaves undefined-function findings untouched and
     takes a clean external fn from no findings to `UnusedParam = 1`. That is
     the whole trade the fix refuses: without it, four unread files would have
     become four files with a false positive each.
  2. Consuming only the FIRST of the two strings is unobservable. Nine fixtures
     -- an external binding followed by a `fn`, a `let`, a braced struct, a tuple
     struct, a second external binding, with no blank line, plus two controls --
     give byte-identical findings, because a leftover string literal is a
     well-formed top-level expression statement. M2 is now a declared SURVIVED.

AND ONE FIXTURE WAS WRONG IN A WAY WORTH KEEPING. The M4 fixture had a struct
with ONE field, which absorbs the leftover line without ever reporting a name, so
the named test stayed green while the suite was red. Two fields is what makes it
discriminating. Separately, a fixture putting a `fn` after the tuple struct was
rejected by rule 6 and named the test that had actually gone red: `skip_decl_braced`
breaks at a top-level `fn` (`parser.mbt:802`), so a following FUNCTION is never
swallowed. The damage needs a `let ... = if` between the struct and the brace --
which is what the corpus writes.

  moui             actionable  0 -> 0    parsed 591 -> 595 (+4, exactly the FFI files)
                         unreliable 244 -> 144, notices 4120 -> 4123, total 4364 -> 4267
  async            actionable  0 -> 0    parsed 253 -> 274 (+21)
                         unreliable 2208 -> 1193, notices 1081 -> 1234, total 3289 -> 2427
  the other FOUR corpora byte-identical.

The async actionable=0 is the load-bearing line and it was NOT free. The FFI fix
alone took it 0 -> 2, both false positives revealed by 21 newly-readable files
rather than introduced by the change. "Pre-existing defect merely revealed" is a
real distinction and still not a shippable one, so the tuple-struct defect went in
the same increment instead of leaving actionable above zero.

GATE 0449: 5 KILLED + 1 declared SURVIVED (M2, above), every named test confirmed
red, every restore byte-identical, baseline 600/600.

## 0.4.39, 0450: a `fn` in STATEMENT position is two different things


A lambda whose value is a branch:

    paint: if disabled {
      fn(_ctx) { { commands: 1 } }
    } else {
      fn(_ctx) { plan0() }
    }

`parse_block` routed EVERY `fn` to the declaration path, so the lambda fell into
`parse_fn_signature`, which asks for a name, found `(`, and reported
`expected function name` -- at a token that is neither unexpected nor unnamed, so
the message sent a reader hunting a malformed function header that does not
exist. That is moui 0.1.12 `modifier_env.mbt` cut at `fn(_ctx) {`.

ONE CONDITION, and the token after `fn` is the whole discriminator: a NAME means a
local function declaration, `(` means a lambda expression. It only ever surfaced
in a BRANCH because expression position always worked -- `let f = fn(x) { .. }`
reaches `parse_primary`'s lambda branch -- and a lambda that is the tail of an
`if` branch is a block STATEMENT, the one place the two forms share a token and a
cursor.

Settled in `_verify/settle_0450_shapes.ps1`, 10/10 with THREE positive controls,
two of which exist because malformed preludes built first: a wrong field type made
nine agreeing REJECT(4014) rows, and the corpus's QUOTED keys reject against a
struct too. Fix the prelude, never the expectation.

  moui     parsed 595 -> 596 (+1, exactly modifier_env.mbt)  unreliable 144 -> 131
  async    parsed 274 UNCHANGED                              unreliable 1193 -> 1201
  proton   parsed 106 UNCHANGED                              unreliable 1077 -> 1103
  the other three corpora byte-identical.  actionable 0 on all six.

THE UNRELIABLE RISE IS NOT NEW FINDINGS, and saying so required a measurement
rather than an argument. `_verify/measure_0450_unreliable.ps1` diffs the scan of
both corpora before and after the fix. Every differing line is a CONTROL line:

    async  task_group.mbt      read up to line 50, 35 after -> 47 after
    async  process/redirect.mbt                     57 after -> 32 after
    async  io/data.mbt                              6 after ->  4 after
    proton six files, +2 to +9 lines each

Six files per corpus now read FURTHER, so more of an already-unread tail is seen,
and the extra findings land in NOTPARSE files where they are already unreliable or
withheld. NOT ONE new finding message appears anywhere. The defect's own
signature is gone: `1x expected function name` leaves async's withheld tally, and
proton's `2x unexpected token ')'` with it.

THAT DIFF HAD TO BE REWRITTEN ONCE, because the first version compared only the
printed `LINE:COL - error:` lines and reported added=0 removed=0 on both corpora
-- while the SUMMARY beside it said `unreliable` had moved 1193 -> 1201 and
1077 -> 1103. Byte-identical lists and a moving count cannot both be true. The
findings that moved are printed as control lines (PARTIAL read-depth, the withheld
tally), not one line per finding. A probe that engages its instrument and prints a
confident zero is worse than one that prints nothing, and that is the whole
hazard: `actionable = 0` on its own would have "confirmed" this change while
measuring nothing about it.

GATE 0450: 3/3 KILLED (M1 the original, M2 the inversion, M3 the condition
deleted outright), every named test confirmed red, every restore byte-identical.
M2 and M3 turn the same test red for different reasons, and only M3 tells "I
flipped it" from "I removed it".

GATE 0452: the three remaining `{`-cut moui files. The cause was NOT a brace.
`parse_struct_fields` reads a braced list and keys every entry by the identifier
before the colon; a map literal with a QUOTED key has no identifier there, so
`peek_name()` returned "" and the whole literal was abandoned. The fix reads a
string key in that position and requires the colon that follows it, because
`{ "a" }` is rejected by the toolchain and must not parse.

THE TWO FORMS CANNOT BE MERGED, and `_verify/settle_0452_quoted_key_map.ps1`
(5/5, with a positive control) is what establishes it. `{ "a": 1 }` as
`Map[String,Int]` ACCEPTS; `{ a: 1 }` as Map REJECTS (4033, 4028); `{ a: 1 }`
as a struct literal ACCEPTS; the corpus declaration verbatim ACCEPTS. So the
quoted form is a map, the unquoted form is a struct, and a fix that let a
string key pass WITHOUT a colon would have silently taught the parser to accept
a program the toolchain rejects.

  moui     parsed 596 -> 599 (+3, exactly the three `{`-cut files)  unreliable 131 -> 105
  labeler  parsed  26 ->  28 (+2)                                  unreliable 319 -> 309
  proton   parsed 106 -> 108 (+2)                                  unreliable 1103 -> 1082
  async    parsed 274 UNCHANGED                                    unreliable 1201 -> 1189
  moonbit_image and proton_contract byte-identical.  actionable 0 on all six.

async is the interesting row: `parsed` did not move, yet 12 findings left the
unreliable bucket and 7 joined notices. Both are expected of this fix and both
are reported here so that neither can later be mistaken for corpus noise -- a
map literal previously read as a struct literal contributed a bogus control
line, and reading it correctly replaces that with real findings on a now-parsed
file. Across all six corpora: parsed +7, unreliable -69, total findings -30.

GATE 0452: 4/4 KILLED (M1 the branch removed, M2 no colon demanded, M3 the value
expression discarded, M4 the string-vs-name discrimination dropped), every named
test confirmed red, every restore byte-identical. Two of the four had to be
re-aimed before they could distinguish anything: M2 was asserted on a failure
COUNT, and under the mutation the fixture still produced two failures, only the
second one different -- so it now asserts the MESSAGE `expected ':'`. M4's
MustRed points at an existing test in another file, because the mutation
destroys the field KEY while `{ a: a }` still parses as a value.
GATE 0453: an anonymous ASYNC function literal in expression position.
After 0452 moui still could not finish reading 9 files, and the largest by-reason
bucket was `4x expected ')'`. That label is about the ARGUMENT of a call, not the
parenthesis -- the parser is downstream of the real failure, which is why the first
reading sent the search towards brackets. Three of the four are one construct:

    launch_async=Some(async fn(request, frame_interval_ms) { .. }),

`parse_atom` had an arm for `TName("fn")` and none for `async`. The short-lambda
named argument on the line ABOVE it parses, which is why those files were PARTIAL
at line 23-24 rather than unparsed at zero.

Settled in `_verify/settle_0453_async_fn_expr.ps1`, 6/6 with a positive control:

    Some(fn(a) { .. })        ACCEPT   <- already read, identical shape
    Some(async fn(a) { .. })  ACCEPT
    the corpus declaration    ACCEPT
    ignore(async)             REJECT(3002) "you may expect `fn`"
    async work()              REJECT(3002)

  moui     parsed 599 -> 602 (+3)   unreliable 105 -> 46   notices 4150 -> 4203
  image and proton_contract byte-identical; actionable 0 on all six.
  The `expected ')'` bucket is GONE from the by-reason grouping, and the
  `unexpected token ','` bucket is 4 -- the three files that were in it, plus
  runtime/app_builder.mbt, which has a SECOND defect behind the first and only
  now shows its own.

THE THREE OTHER CORPORA MOVED AND NOBODY ASKED THEM TO. proton unreliable
1082 -> 1112, withheld 309 -> 321; async notices 1234 -> 1241; labeler withheld
134 -> 136. `parsed=` is UNCHANGED on all three, which is the signature of
"reading further", not of a regression -- and it was checked rather than argued:
proton carries 25 `async fn(` literal sites and async carries 45, so a file that
used to stop at one of them now stops at whatever comes NEXT and has more of its
tail seen. That is the same mechanism 0450 documented, and it is the reason
`unreliable` can rise while `parsed=` holds.

TWO REGRESSIONS OF MY OWN WERE CAUGHT BY THOSE CORPORA, NOT BY THE GATE:

  1. A `fn`-only guard consumed `async fn log(s) { .. }` -- a NESTED
     DECLARATION -- as an anonymous literal, so `parse_block` never declared it.
     labeler withheld 134 -> 136, two files that had parsed became PARTIAL.
  2. The compound guard `at_name("fn") && name_at(p+1) == ""` sent that same
     nested declaration to the `else`, which announced `async without a following
     fn` -- a FALSE notice about legal code. async hit it on all five of its
     nested sites. `else` fires 0 times in all six corpora now.

Neither was visible to `_verify/mutate_0453.ps1`, and the reason is worth
recording rather than fixing: no fixture in the 0453 file contains a nested async
declaration, and a mutation gate cannot see a corpus it was not given. The corpus
is the instrument for that, which is why all six SUMMARY lines are pinned.

GATE 0453: 5/5 KILLED (M1 the arm never fires, M2 the `fn` not consumed, M3 the
body skipped, M4 the `fn` guard dropped, M5 the nested declaration announced).
M3's MustRed was RENAMED TWICE before it could discriminate, and both attempts
were structurally incapable: `UnusedParam` on the literal's own parameters (they
are `let _ =`-discarded, never bound) and a defect inside the body (`parse_block`
returns statements that are thrown away, so nothing inside a function literal
reaches a lens -- for a plain `fn` exactly as much as for an async one). What
works is what reading the body DISCOVERS: a `match` inside it is announced.
GATE 0454: `label?=value` in a call argument -- the member the shorthand family
was missing. After 0453 moui could not finish reading 6 files and the largest
by-reason bucket was `unexpected token `,``:

    let normal = @views.new_control_state_style(
      foreground=@core.Color::black(),
      border?=normal_border,
      radius=0.0,
    )

The complaint named a COMMA, three tokens from the cause. `parse_call_args`
handles two shorthands, both AFTER the argument is parsed -- `f(x~)` at the
`TTilde` test and `f(x?)` at the `TQuestion` test -- and neither is followed by
an `=`. So for `border?=normal_border` the `TAssign` test was FALSE (the next
token is `?`), `p` was restored, `border` was read as a positional name, the
`TQuestion` shorthand consumed the `?` as if the argument ENDED, the comma test
found the `=` that the first test skipped over, and the loop broke.

The `?` CARRIES MEANING, so this is not sugar for `=`. Settled in
`_verify/settle_0454_label_qmark_eq.ps1`, 9/9 with a positive control:

    border?=v   against  border? : Int   ACCEPT
    border?=v   against  border~ : Int   REJECT(4141) "not declared with border? : _"
    border?=                      REJECT(3002)
    border?v                      REJECT(3002)

A `name? : T` parameter has type `T?` -- measured as REJECT(4014) "wanted Int?"
with a bare `7` -- so dropping the `?` would read illegal code as legal. The last
row is what licenses the two-token lookahead: `?` either ends an argument or starts
`?=`, and never prefixes an expression.

  moui     parsed 602 -> 605 (+3)   unreliable 46 -> 23   notices 4203 -> 4209
  proton   parsed 108 -> 109 (+1)   unreliable 1112 -> 1032   notices 1344 -> 1374
  the other four byte-identical. actionable 0 on all six.

proton moved too, and it was CHECKED rather than waved at: it uses `label?=value`
17 times across four files (`facade_builders.mbt` 5, `facade_native_types.mbt` 7,
`facade_runtime.mbt` 4, `facade_event_loop.mbt` 1). `facade_builders.mbt` is also
the file that held the `async fn(context) {` literal 0453 fixed, so it had two
stacked defects and only now resolves. The -80 unreliable is that file's.

The `unexpected token `,`` bucket is GONE from moui and the three files that
resolved are exactly the three `?=` ones. What remains is three files and three
DIFFERENT causes, one each -- the shape a tail of this kind is supposed to have:

    1x  expected ')'             runtime/app_builder.mbt:47
    1x  unexpected end of line   runtime/input_dispatch_result.mbt:13
    1x  unexpected token `:`     backend/macos/macos_services.mbt:406

GATE 0454: 5/5 KILLED (M1 the branch removed, M2 the `=` not required, M3 the
value consumed but not analysed, M4 the `?` dropped from the label, M5 the
lookahead widened to any `?`).

M4's MustRed MOVED FILES and that is the finding. It SURVIVED the first version of
this gate: every 0454 test was written through `@pipeline.run`, asserting findings,
and nothing on the pipeline path READS the label -- `parse_call_args` returns
`(args, labels)`, the labels go into `ECall`, and neither lens consults them for any
finding these fixtures trigger. A blank label changed no count; 623/623 stayed
green. That is a property of the ANALYZER, not of the parser, so the assertion
moved to `src/parser/parser_0454_test.mbt` and reads `ECall`'s third field directly,
the way `parser_0430_test.mbt` already does for `x~` and `x?`. Asserting "the call
parses" passes; asserting a finding count passes; neither is evidence about a label.
0.4.xx -- newline suppression after the BITWISE-OR token. `unexpected end of line`
is 0 occurrences across all six corpora; it was 1 in moui.

ONE TOKEN WAS MISSING. `newline_suppressed_after` listed TPlus, TAmp, TCaret,
TAndAnd, TOrOr, TShl, TShr and every comparison operator, and did not list TBar. So
the lexer emitted TNewline after `|`, `parse_bitor` bumped the `|` correctly, and
the operand parse landed on TNewline and `parse_primary` raised "unexpected end of
line" (parser.mbt:4664).

THE EVIDENCE KEPT POINTING ELSEWHERE, which is the part worth keeping. A sweep for
"trailing binary operators" reports 178 corpus files and 2296 sites and would have
ranked this as the largest available lever; 103 of those are moui files and only 3
moui files fail to parse at all, because `+`, `&` and `||` already continue. And
`input_dispatch_result.mbt` had been carried for several rounds as "a parenthesised
`if` as an operand", which is false -- a parenthesised `if` parses fine. A token's
role is whatever the CONSUMER does with it, and `TBar`'s own comment still said "the
parser never sees one" after `parse_bitor` had started consuming it.

  moui             parsed 605 -> 606 (+1)   actionable 0 -> 0
  moonbit_labeler  parsed  28 ->  28        unreliable 311 -> 294
  moonbit_image    parsed   2 ->   2        unreliable 294 -> 285
  async            parsed 274 -> 274        unreliable 1188 -> 1175
  proton           parsed 109 -> 109        byte-identical
  proton_contract  parsed   4 ->   4        byte-identical

THE 42 FINDINGS THAT LEFT `unreliable` ARE NOT A COVERAGE LOSS, and it was verified
rather than assumed: both builds came from the same tree, one with TBar in the set
and one without, and the per-file comparison found ZERO files read less, one newly
complete (`input_dispatch_result.mbt`) and one read further (labeler). `actionable`
and `notices` are unchanged in every corpus, so what vanished was exactly the class
the analyzer itself flags as "this file was not fully understood".

GATE 0455, 4/4 KILLED with named tests. M4 is the row worth noting: it deletes the
OTHER conjunct of the same `if` -- `closer_ahead` -- and it SURVIVED the first run,
which is how the repository learned that the newline-before-a-closing-bracket rule
had no test pinning it anywhere. That test now exists.

GATES 0456 + 0457, shipped together because 0456 alone breaks the invariant this
file exists to protect.

0456 consumed the `.Type` of a package-qualified `is` head (`@pkg.Type::Ctor`, four
tokens, parser.mbt:3033). moui 606 -> 607; `backend/macos/macos_services.mbt` parses
whole. It also corrects the pin on `parser_0436_test.mbt` that recorded the WRONG
mechanism: it said `peek_name()` is `""` for an `@` head, which is false -- it returns
`"@pkg"`. Both stories predict the same symptom and a different repair, which is the
only reason the disagreement was worth chasing.

0456 BROKE async actionable 0 -> 3 by unblocking `src/fs/watch_test.mbt`, which had
been dying at line 389 on `is @async.TimeoutError`. The file then parsed whole and
three `undefined name 'async'` sites surfaced at once -- a false positive 0457 removed.
So `actionable` could not be pinned between the two increments, which is why they ship
as one commit: a visible parse failure traded for invisible wrong findings is worse
than either alone.

WHY async's `unreliable` ROSE 1175 -> 1248 while `actionable` fell to 0. Honest
re-classification, verified rather than argued. 46 read-past `async fn` sites now mark
their region unreliable instead of silently binding a name. A move that size cannot be
pinned on inference, so `_verify/ab_0456_0457_coverage.ps1` builds BOTH parsers from ONE
tree and diffs how far the scanner reads in EVERY file of all six corpora:

    files in HEAD map 1223 / fixed map 1223
    unchanged 1220   read further 3   READ LESS 0

    async/src/fs/watch_test.mbt          389 -> EOF     (0456 unblocked it)
    async/src/websocket/server.mbt   NOLINE -> PARTIAL 34
    moui/backend/macos/macos_services.mbt 406 -> EOF     (0456)

`watch_test.mbt` moving FROM 389 is the cross-check: 389 is the `is @async.TimeoutError`
line the 0457 comment names as the blocker, so the A/B confirms the comment's own claim
by a different instrument.

THE REACH METRIC, and why it had to be built rather than reused. `FOUND` lines look like
the per-file record and cover only 183 of async's 419 files -- a fully-read clean file
prints `CLEAN`, and one that failed at its FIRST construct prints nothing at all. Keying
the diff on `FOUND` would have dropped 56% of the corpus silently, and every clean file
would have read as "absent" rather than "unchanged". So reach is one state per file:
EOF / a line number / NOLINE, with NOLINE made explicit precisely because it is the
state most likely to MOVE. The map is checked for totality against the files on disk,
and it validates itself twice against the scanner's own accounting:
EOF == `parsed` (275) and PARTIAL + NOLINE == `NOTPARSE` (83 + 61 = 144).

`pins.ps1` exists because these six numbers were once measured by an ad-hoc loop that
returned `files=3675 parsed=2831 actionable=125` for moonbit_labeler and then returned
the IDENTICAL line for moonbit_image. Two corpora cannot agree exactly, so that was a
stale file being read -- and it was caught only by the coincidence of the match. Every
corpus now asserts its TARGET line and its file count against disk before the number is
printed, and any two identical summaries abort the run.

GATE 0457, 3 KILLED / 1 declared survivor. M4 (adding the `bump` the branch deliberately
does not have) was declared KILLED in the first run so the suite could decide; it
survived 643/643, and structurally so -- `parse_block` tests the token at the cursor, and
after this branch that token is `fn` either way, so both variants build the same tree.

639 -> 643 tests: `pipeline_0457_test.mbt` is new, and none of its four cases existed
before. 0453 pinned that a nested async declaration is not mistaken for a literal, via
`parse_failures == 0` plus the absence of a false notice -- and both hold while the branch
still binds a bogus name, because a notice is not a failure. Only a lens that resolves
names separates the two, which is what the new file asserts.

GATE 0458 -- and this one closes the corpus.

    PARSED 608/608 files understood (100.0%); 0 more read only up to their
    first parse error

moui is no longer "607 of 608". `runtime/app_builder.mbt` was the last file it
could not finish, and `unreliable` went 9 -> 0 with it: every file in that corpus
is now UNDERSTOOD rather than read-until-some-error, which is a stronger statement
than "no file is blocked".

The blocker was one missing head in `fn_type_annotation`. After the `(` it handed
`async` to `type_annotation()` as an ordinary type NAME; the parameter loop then
broke on the `(` that followed rather than on a comma, and `expect(TRParen)`
reported `expected ')'` at line 47.

THE GRAMMAR IS NOT WHAT THE SOURCE LOOKS LIKE, settled 7/7 with two controls that
can fail (`_verify/settle_0458_async_fn_type.ps1`). The trailing `?` makes the
RETURN type optional; it does not lift the group into a nullable function:

    fn build(f? : ((Int) -> Unit)? = None)                          ACCEPT
    fn build(f? : ((Int) -> Unit)  = None)                          REJECT(4014)
    fn build(launch_async? : (async (Int, Int) -> Unit)? = None)    ACCEPT

Three fixtures had to be corrected before any grammar was measured, and each
correction first looked like a verdict ABOUT the grammar: two were call sites given
the wrong return shape, one confused an optional PARAMETER (`x?`) with a nullable
TYPE (`T?`) -- and the corpus line carries both. When a probe about the language
disagrees with you, suspect the probe's fixture first; it was wrong three times here.

M4 IS THE ROW WORTH READING. Dropping `at_name("async")` from the head and keying on
the bracket alone SURVIVED the first 648-test run -- which is exactly enough evidence
to write "unobservable by construction" into a `Prove`, and it would have been wrong.
`fn f(g : (((Int)) -> Unit)) -> Unit` is valid MoonBit (ACCEPT, zero errors), and after
the outer `(` is bumped the cursor is on `(` with the next token also `(`. The
plain-function-type control cannot see it, because there the cursor lands on
`String`. So: "no test covers this" and "no program can reach this" are different
claims, and a survivor verdict is a claim about the second while the evidence on hand
only ever supports the first.

M5 IS A SURVIVOR WHOSE CLAIM IS MEASURED RATHER THAN ARGUED. Two end-to-end tests in
this increment's first draft asserted the RENDERED annotation and were deleted: the
string is consumed inside the parser and handed to `ann_to_ty`, and it is not part of
the pipeline result, so no end-to-end assertion can reach it (the same trap
`pipeline_0413_test.mbt:83` describes). `src/types/types_0458_test.mbt` then answers
the real question -- are the two renderings indistinguishable DOWNSTREAM -- by
asserting `ann_to_ty("async (Int, Int) -> Unit?")` is `TUnknown` beside a control
showing `ann_to_ty` does distinguish types. Teach it the `async` head and that test
goes red on purpose, at which point M5 must become KILLED. A survivor with no
tripwire is an untested guard with a footnote.

Tests 643 -> 651: `pipeline_0458_test.mbt` and `types_0458_test.mbt`, eight cases.
Re-pinned after 0464 (the pipe operators, `errdefer`, and a lambda as a pipe's
right operand). Two corpora moved, both in the direction that means more files are
understood rather than merely more opinions:

    async   parsed 302 -> 325   unreliable 916 -> 733   notices 1406 -> 1550
    proton  parsed 115 (same)   unreliable 922 -> 921   total    2406 -> 2405

`unreliable` is the number that carries the meaning: it counts files read only up
to a parse error, so async's 23 newly-parsed files are now read whole. The
`notices` rise on async is the same trade 0459 made and is worth reading rather
than waving at -- a file that parses reports the deliberate exclusions inside it
(mostly skipped lambda bodies), so more files understood means more notices as
well as fewer unreachable ones.

proton moved by ONE finding: the `errdefer` arm reads its argument rather than
skipping it, so a name in an already-understood file is now read at all.
`notices` there is unchanged, so nothing new was merely noticed -- something that
could not have been seen before is now seen.

MEASURED TWICE, because the first pin was wrong and nothing noticed until the
gate ran. The 312 in an earlier draft of this block was taken BEFORE the
lambda-as-pipe-right-operand fix landed; that fix is worth 13 more async files on
its own (312 -> 325). The pin now records the FINAL source state, re-measured by
`_verify/scan_0427.ps1` independently of this gate and agreeing with it.

=> 判据: a pin is a claim about a source state, so it must be measured against
the state that ships. A number copied from a scan taken mid-increment is not a
stale baseline, it is a wrong one -- and the release gate is the only thing in
this repository positioned to catch it.
Tests 795 -> 820: `parser_0467_test.mbt` (13 cases) and `pipeline_0467_test.mbt`
(12 cases). Re-pinned after 0467 and 0467b. TWO corpora moved, and async moved a long
way -- the largest single-increment gain since the pipe:

    async   parsed 337 -> 352   unreliable 614 -> 373   withheld 189 -> 115
    proton  parsed 116 -> 121   unreliable 727 -> 575   withheld  59 ->  53

async's `unreliable` fell 241 and proton's 152. `unreliable` is the count that carries
meaning: those files are now read whole instead of stopping at a parse error. `withheld`
counts the notices the analyzer deliberately does not make inside a partially-read file,
so a drop there is reach rather than silence.

0467 THE ASYNC FUNCTION TYPE. One construct, THREE spellings, and until this increment
exactly one of them parsed:

    (async (A, B) -> R)?      a parenthesised annotation   -- parsed=1 (0458)
    async (A, B) -> R         a bare parameter annotation  -- parsed=0
    -> async (A, B) -> R      a bare return annotation    -- parsed=0

Measured by running the analyzer over one file per shape, NOT by reading the code. The
cause was an ORDERING fact rather than a missing keyword: the `async` lookahead in
`fn_type_annotation` sat AFTER its `bump() // (`, so it could only ever see `async` when
something had already put a `(` in front of it. The body is now shared
(`fn_type_body`) behind three thin entry arms, so the spellings cannot drift again.

The grammar is settled in `_verify/settle_0467_async_param_type.ps1`, 17 rows, and two
parts of it are not guessable from the symbol. The toolchain's own diagnostic for a bare
`async` is the whole first argument --

    Parse error, unexpected token `)`, you may expect `(`.

-- so the parenthesised list is REQUIRED and `lparen_at` is a discriminator rather than
a guard. And `g : bogus (Int) -> Unit` REJECTs with 3002, so the head is a KEYWORD and
not any name followed by a parenthesised list; that is what makes gate 0467's M3
killable rather than a survivor.

0467b THE BINDING COLLECTOR, WHICH WAS NOT IN THE RANKING AT ALL. Reaching
`moonbitlang/async 0.22.4 src/fs/dir.mbt` produced two ACTIONABLE false positives on
code `moon check` compiles: `49:26 no visible binding for 'last_path_sep_index'` and
`55:13 no visible binding for 'parent'`. Both are bound by a `let` INSIDE A CATCH ARM.
`collect_fn_bindings` descends into `SIf`/`SFor`/`SWhile`/`SBlock`, but `catch` is an
EXPRESSION, so no arm ever scanned one -- and `walk_stmt`'s `SLet` never binds anything
itself, so the pre-pass is the only thing that fills the frame.

THAT IS THE 0464b SHAPE FOR THE FOURTH TIME, and gate 0443 had already written the same
sentence one level up for `SNoBreak`: "walk_stmt was taught `SNoBreak` and the COLLECTOR
was not, and the compiler is silent about a missing arm in a match that has a catch-all".
Nobody noticed for years because `Walker::resolve` is gated on `!self.partial`, and
every file containing a catch arm was unread.

=> 判据: a false positive nobody can reach is not a false positive that does not exist.
It is a finding whose file has not been read yet, and the only way to tell the two apart
is to unblock the corpus and look. The reach was legitimate, so the GAP was fixed rather
than the reach given back.

## 0468: a BLOCK in the RHS of a `let`, and TWO THINGS IT IS NOT ONE OF


Until this increment every `{` in expression position reached the atom's TLBrace arm and
went to the FIELD grammar, which rejected the content and reported `expected a struct
literal field here` at the brace. A block -- `{ let y = 1; y + 1 }`, whose value is its
TAIL -- was unreadable.

  moui             actionable  0 -> 0   parsed 608 UNCHANGED
  moonbit_labeler  actionable  0 -> 1   parsed  32 -> 33
  moonbit_image    actionable  0 -> 1   parsed  15 -> 17
  async            actionable  0 -> 0   parsed 352 -> 390
  proton           actionable  0 -> 0   parsed 121 -> 122
  proton_contract  actionable  0 -> 0   parsed   4 UNCHANGED

moui and proton_contract are the CONTROL and they are the reason the other four can be
read as gain: both were ALREADY complete (608/608 and 4/4) and so cannot have
contributed a single parse.

*** ACTIONABLE IS 1 ON TWO CORPORA AND NOT 0, AND NEITHER IS CAUSED BY THE BLOCK. ***

Both are PRE-EXISTING defects that 0468 made REACHABLE by reading more files -- the
standing 判据 that a false positive nobody can reach is not a false positive that does not
exist. They are pinned HERE rather than quietly, and they are the reason the pin moves UP:

  moonbit_image 0.3.7 png.mbt:980          `operand of '!' must be bool, got 'int'`
  moonbit_labeler 0.2.13 app_moui/rasterizer.mbt:1218
                                          `argument 2 to 'blend_pixel' has incompatible
                                           type 'float'; expected 'int'`

The image one is ROOT-CAUSED and the fix is one line, deliberately NOT in this increment:
parser.mbt's `TName("match")` arm reads the scrutinee and YIELDS IT, so
`let vok = match bd { .. }` binds `vok` to `bd` itself -- same value, same type. The
sibling `TName("fn")` arm does the same kind of skip and correctly yields an OPAQUE node;
`match` is the inconsistent one. That changes parser semantics for an existing construct,
so it is its own increment with its own guard test, not a line borrowed into 0468.
The comment at that arm asserted the opposite ("the scrutinee is an ordinary expression")
and has been corrected in place.

The labeler one is LOCATED, and the two hypotheses above are both FALSIFIED. Measured on a
four-case probe (`moon check` ACCEPTs all of it), an `if` body, a `while` body, a `for` body
and a bare block ALL leak identically:

  fn s3(n : Int) -> Unit {
    for i = 0; i < n; i = i + 1 {
      let x : Double = 1.0
      ignore(x)
    }
    for x = 0; x <= 1; x = x + 1 { take(x) }   <- take's Int param
  }

reports `argument 1 to 'take' has incompatible type 'float'; expected 'int'`. The control is
the same function with the inner `let x` renamed: it reports NOTHING.

So it is neither an argument-index bug nor a single-line `for`-header bug. It is a BINDING
SCOPE LEAK: `collect_stmt_bindings` descends into a nested statement list with the SAME
binding array, so an inner binding outlives the construct and SHADOWS a later binder of the
same name.

THIS IS THE MIRROR IMAGE OF A KNOWN FALSE NEGATIVE ALREADY PINNED, not a second bug. 0468
measured that a block's bindings do NOT scope -- `let y` inside a block stayed visible
afterwards, where `moon check` reports [4021] unbound. That is the same missing scope seen
from the side that loses findings; labeler:1218 is the same missing scope seen from the side
that MANUFACTURES one. A leaked name only becomes a false positive when something later
binds the same name.
=> 判据: one mechanism, two directions. A class of findings is not a list of defects.

NOT FIXED HERE. Every nested body in every corpus shares that frame, so the fix moves the
finding count corpus-wide and is its own increment.

A SECOND PIN MOVED INSIDE 0468 THAT NEVER SHOWED IN ANY SUMMARY: `parse_block` was called
with `false`, so no `EBlock` body ever contained a `STail`, `Infer::ty_of` returned
`TUnknown` for EVERY block and `Interp::eval` returned `AAny`. Both arms were dead code
and every corpus number above is the same with and without them, because `walk_stmt` reads
an `SExpr` tail exactly as well as an `STail` one.
=> 判据: a construct can be READ correctly and still carry no value. Only a row that
counts what the tree CARRIES sees this -- `0468: the tail's TYPE reaches the operator
below` -- and it is M4 of `mutate_0468.ps1`. The flag is now named `value_block`, because
"this is a function body" was the name that let the bug read as a decision.

GATE 0468: 11/11 KILLED, no declared survivors, every restore byte-identical. Two of the
eleven had to be REWRITTEN rather than re-anchored, and both rewrites are in the gate:
M5's named row was the wrong one (a third lens already reports that name), and M11's first
form mutated to `AAny`, which this behavior lens absorbs BY DESIGN -- interp.mbt:1076 has
`AAny => true` in `numeric` and :1094 short-circuits the whole operator arm on it.
=> 判据: a survivor is not always an untested property. Sometimes it is a mutation whose
RESULT is unobservable, and the two want opposite responses.


## 0469: a `match`'s value is the ARMS, not the subject


`parser.mbt`'s `TName("match")` arm used to read the subject and YIELD IT. That is the
one place in the parser where "the expression I had to parse to keep the token stream in
step" and "the value this expression produces" are different things: a `match`'s value is
the join of its arms, and the arms are what this analyzer skips.

  moui             actionable 0 -> 0   UNCHANGED, byte for byte
  moonbit_labeler  actionable 1 -> 1   total 803 -> 801
  moonbit_image    actionable 1 -> 0   total 231 -> 230
  async            actionable 0 -> 0   UNCHANGED, byte for byte
  proton           actionable 0 -> 0   UNCHANGED, byte for byte
  proton_contract  actionable 0 -> 0   UNCHANGED, byte for byte

FOUR OF SIX ARE BYTE-IDENTICAL, and that is the result being claimed: a fix that moved
every corpus would be a fix whose scope nobody measured. moonbit_image's actionable goes
to ZERO -- that is the whole increment. labeler's stays at 1 because its finding is the
unrelated `for`-header/argument-index defect 0468 made reachable.

THE OBVIOUS FIX WAS WRONG, WAS WRITTEN FIRST, AND WAS MEASURED BEFORE IT WAS KEPT.
Yielding the bare `EBigInt` the anonymous-`fn` arm uses fixes the type and LOSES THE
SUBJECT'S READS, turning two TRUE positives in `pipeline_0433_test.mbt` into false
negatives. It passed this corpus stage and failed two unit tests.
=> 判据: "the fix removed the finding" is not the same claim as "the fix removed the
defect". A trade of one true positive for the absence of a false one is not a trade.
`EMatch(subject)` carries the subject and says nothing about the value: `walk_expr`
descends, `ty_of` answers Unknown, `eval` runs the subject for its effects and yields
`ABottom` rather than `AAny` (which every operator arm absorbs).

IT CANNOT BE FOLDED INTO `ECatch` DESPITE THE IDENTICAL SHAPE. `ECatch` TYPES as its
base because `expr catch { .. }` really does produce the base's value when no arm
matches. A `match` does not -- its value comes from the arms. Same shape, opposite
answer, and that difference is the entire argument for a new variant.

A TEST WAS CORRECTED IN PLACE RATHER THAN LEFT: it was named "a match expression is
skipped whole and yields its scrutinee" and asserted `@ast.EName("e")`. That was not a
description of the construct, it was a PIN ON THE DEFECT.

AND TWO ROWS WERE FOUND VACUOUS BY THE GATE. `UnusedParam == 0` for a parameter read
only inside a match subject cannot fail, because a `match` silences `UnusedParam` for its
whole enclosing function by design. M2 measured it: deleting the walk arm reddens three
rows and not that one. It is recorded in place rather than deleted.
=> 判据: before keeping a negative row, ask whether ANY mutation can turn it red.

GATE 0469: 4/4 KILLED, no declared survivors, every restore byte-identical.


## DIRECTION 2: THE BEHAVIOR LENS IS UNOBSERVABLE ON EVERY PINNED CORPUS


This is a VERIFICATION gap, not a correctness gap, and the distinction decides what to do
about it. Measured by `_verify/dir2_behavior_reach.ps1`, which carries its own POSITIVE
CONTROL -- a fixture the scanner really does tag `[behavior]` -- so its zeros cannot be an
artefact of a broken reader:

  ALL SIX CORPORA      7493 findings      0 carrying the behavior lens
    moui                4152              0
    async               1677              0
    proton               959              0
    moonbit_labeler      469              0
    moonbit_image        202              0
    proton_contract        34              0

THE MECHANISM, CONFIRMED CAUSALLY RATHER THAN BY CORRELATION. `interp.mbt` executes
top-level statements and whatever they reach; a function nothing calls is never executed.
Appending ONE top-level call to a copy of proton_contract 0.3.4 -- changing no other byte
-- takes that corpus from 0 findings to 1, and that 1 is `[behavior]` ALONE:

    322:18 - error: no method matching application_route() (MethodError) [behavior]

So the lens is neither broken nor silent for want of defects. It has nothing to run: all
six pinned corpora are libraries, and not one contains a `main()`.

=> WHAT THIS COSTS. Roughly a thousand lines of `interp.mbt` are unexercised by every
corpus, so the SIX SUMMARY lines this gate pins -- its primary defence -- carry ZERO signal
about the behavior lens. Any regression there leaves all six pins green. Every interp
mutation is catchable ONLY by a unit test, which is why `mutate_0426`'s M1/M2, `mutate_0443`
and `mutate_0469`'s M11 all name interp tests explicitly rather than relying on a drift.

=> 判据: a pin is a claim about a source state, and a pin that cannot distinguish two
states is not a pin. Six corpus lines that stay identical whatever `interp.mbt` does are
the same confident zero as a broken reader, and the only defence against both is a
control that proves the counter can see a thing it is reporting as absent.

NOT CHANGED HERE. Making the lens analyze every function rather than only main-reachable
ones is a SEMANTIC change to what the third lens means, and it is a decision rather than
a defect fix: the honest options are to give it per-function entry, to say plainly that
it only analyses programs, or to keep it and state the coverage it does not have.

GATE 0470: the C-style `for` INIT CLAUSE is a DECLARATION. 5/5 KILLED, no declared
survivors, every restore byte-identical.

The clause carries no `let`, so the ordinary statement reader built an `SAssign`. That is
the wrong node twice over: the clause DECLARES rather than assigns, and the name does not
outlive the loop. `Infer::assign_check` REPORTS a mismatch but does not rebind, so an
`x : Double` leaked from an enclosing body survived and the loop's own `x` never replaced
it -- moonbit_labeler 0.2.13 app_moui/rasterizer.mbt:1218, the last `actionable` on any
corpus.

THE TOOLCHAIN STATES THE INCREMENT IN ONE LINE, and the settle gates it as claim 4:

    Unknown binder n in the for-loop steps. Binders in the steps must be declared in the
    initialization block of the for-loop.                      [4106]

An assignment reading cannot produce that message, because there would be nothing to
"declare in the initialization block". The settle's RECORDed row is the second half: an
enclosing `let x : Int`, then `for x = 0; ..`, then `ignore(x)` after the loop ACCEPTs --
the clause SHADOWS the enclosing binding and the enclosing one survives, which only a
declaration does.

=> THE PIN MOVED ON EXACTLY ONE CORPUS. labeler actionable 1 -> 0, total 801 -> 800. moui
4225, image 230, async 1971, proton 2189 and contract 34 are BYTE-IDENTICAL to the pins
above. Five of six unchanged is the control that makes the sixth meaningful: a parser
change that moved every number everywhere would be a different parser change, and one that
moved nothing would have cleared nothing.

=> THE FIRST VERSION OF THE FIX WAS INERT AND NOTHING REPORTED IT. It unwrapped an `EBin`
out of the right-hand side -- which is the shape the COMPOUND branch produces, while the
plain `=` branch stores the value DIRECTLY -- so it matched nothing and handed every
statement back. `moon check --deny-warn` was 0 and all 857 tests stayed green while the
corpus finding it was written to clear stayed. M2 of the gate IS that inert version, and
it is killed by the row that asserts the node KIND rather than a count.

=> 判据: before keeping a negative row, ask whether ANY mutation can turn it red. The 0470
pipeline rows were first written against the family `ArgumentTypeMismatch`, which does not
exist -- it is `ArgTypeMismatch`. Four rows asserting `== 0` on a family that cannot occur
are vacuous and passed 868/868; only the one `== 1` row caught it, by failing. M5 pins the
inert mutation on the pipeline row specifically so that vacuity cannot come back silently.

=> 判据: a token-level test and a node-shape test are not interchangeable. `for i = j + 1`
is a plain `=` whose value is legitimately an `EBin`, and `x += 1` wraps its value in one,
so the shape cannot tell a declaration from a compound assignment. The discriminator is
`TName(_)` followed by `TAssign`, which excludes `TPlusEq` and its siblings for free.
## 0471: an anonymous `fn`'s TAIL between `)` and `{`

`parse_fn_literal` went from `parse_param_list()` straight to `parse_block()`. A literal
carrying `-> Type` or `raise`/`noraise` therefore left the cursor on the tail token, and
`parse_block` -- looking for `{` -- reported `expected '{'`. A complaint about a brace that
was never the problem, which is the same shape as the DECLARED-fn `-> T raise E` clause
whose absence once cost 24.5% of moui's 608 files.

THE FIX IS NOT A THIRD READER. A declared `fn` already reads this tail with two calls, and
the literal was making neither:

    if self.at(TArrow) { retann = self.return_annotation() }
    self.parse_raise_effect()

`return_annotation` already knows both spellings of a function-type return (settle_0427_retfn)
and `parse_raise_effect` already knows `raise E`, `!`, `noraise` and `nocancel`. A literal and
a declared function are the same production, and `parse_fn_literal` exists precisely so the
two literal arms (`fn` and `async fn`) share one reader -- which is why adding the two calls
in one place was the whole fix.

=> THE POSITION WAS RULED OUT BY MEASUREMENT, and this is the part worth keeping. The
obvious reading -- "literals only work as call arguments" -- is wrong in BOTH directions:

    let h = fn(x : Int) { x }          ACCEPTED
    g(fn(x) { x })                     ACCEPTED
    let h = fn(x : Int) -> Int { x }   PARSE ERROR
    g(fn(x) -> Int { x })              PARSE ERROR

so the variable is the RETURN ANNOTATION and not where the literal sits. Had the first
draft's fixture used a call argument -- which is what the proton blockers look like -- the
increment would have been filed as "literals work as arguments but not as values", a
different defect with a different fix.

REACH, per-FILE first blocker, measured on the tree at 0470:

    corpus          parsed        unreliable        notices
    moonbit_labeler  33 -> 35 (+2)  89 -> 55  (-34)   711 -> 738 (+27)
    proton          122 -> 131 (+9) 544 -> 187(-357) 1645 -> 1881 (+236)
    moui / image / async / contract      BYTE-IDENTICAL

`unreliable` is the number that carries the meaning: it counts files read only up to a parse
error, so proton's 357 is files now read whole. The `notices` rise is the same trade 0459,
0464 and 0467 made -- a file that parses reports the deliberate exclusions inside it. proton's
`withheld` fell 35 -> 6 for the same reason: fewer partial reads means fewer notices withheld
from files the analyzer could not trust.

`actionable` stayed 0 on both. Nine more proton files became readable and not one manufactured
a finding, which is the number that makes the rest mean anything -- more reach is also more
opportunity to invent something.

THE GRAMMAR IS SETTLED, 9 rows with two controls (`_verify/settle_0471_fn_literal_tail.ps1`).
Four of its seven claims failed on the first run and every failure was the FIXTURE, not the
grammar: a one-line `if x < 0 { raise Boom } x` inside a body is rejected by the toolchain
with `unexpected token id`, calling a `raise`-annotated literal from a non-raising function
is [4122], and `raise` with no error type needs a bare-`raise` CALLER or the toolchain asks
for a specific error [4118]. None of those say anything about the tail, and all three read
like a grammar rejection if you do not check the error code.

=> 判据: GATE 0471: 5/5 KILLED, no declared survivors, every restore byte-identical. M4 is the
mutation worth reading -- it removes the `if self.at(TArrow)` GUARD, so `return_annotation()`
runs on an untailed literal and eats the BODY's first token as a type. Every "a literal with
a tail parses" row stays green; only the untailed row and the corpus numbers move. A fix
that guards its new reader badly is worse than no reader, and no row that only asks "does the
new form parse" would have caught it.

M2's anchor is `self.parse_raise_effect()` PLUS its next line, because that call appears
THREE times in `parser.mbt` (1605, 2039, 5128) and a bare anchor mutates whichever comes
first -- a different function entirely. The pre-flight counts occurrences and would have
warned; anchoring correctly was cheaper than reading the warning.

TWO ROWS IN `pipeline_0471_test.mbt` PLACE THEIR PROBE ON THE FAR SIDE OF THE LITERAL, and
they are the ones this increment really turns on. A tail read with the wrong extent
swallows the token after the literal: `parsed` goes UP on every affected corpus, every
SUMMARY line looks like progress, and the analyzer has quietly stopped reading the code
that follows. The six pins cannot see that, and neither can a parse-shape assertion.

One row asserts `ArgTypeMismatch == 0` because the literal yields `EBigInt` and is
therefore deliberately opaque to the type lens whatever its annotation says. The first draft
asserted `== 1` for `g(fn(c : Char) -> Char { c })` and it came back 0, which is CORRECT --
`-> T` is read to keep the token stream in step and nothing reads it. Asserting a finding
the analyzer never makes is not a strong row, it is a false one written in the test rather
than in the product.
ONE OLDER GATE HAD TO BE RE-ANCHORED, and the pre-flight is what caught it rather than a red
test. `mutate_0453`'s M3 ("the body is skipped, not read") anchored on the two ADJACENT lines
`let _ = self.parse_param_list()` and `let (_, _) = self.parse_block(false)`, because before
0471 the literal went straight from one to the other. Putting the tail between them broke the
two-line pattern, and the gate ABORTED at pre-flight with `PREFLIGHT MISS` rather than running
a suite it could not honestly report.

The mutation was RE-ANCHORED, not retired, because the thing it mutates did not change shape --
it only grew. The new anchor is the `parse_raise_effect()` / `parse_block(false)` pair, which
is UNIQUE in the file; the bare `let (_, _) = self.parse_block(false)` is not, and anchoring on
that alone would have mutated `parse_c_for` or `parse_if` instead. Gate 0453 is 5/5 KILLED
after the move, every restore byte-identical.

=> 判据: a PREFLIGHT MISS is not a gate failure to be worked around, it is the harness doing
the one job it cannot do any other way -- telling you that a mutation's anchor no longer
points at the thing it was written to mutate. The alternative -- inventing a nearby anchor
until the pre-flight is quiet -- is how a gate ends up testing a function nobody changed. The
re-anchor was only safe because the mutation's MEANING was unchanged and that could be
checked by reading the two versions of the function side by side; a re-anchor of a pattern
whose intent had drifted would have been a silent weakening, so the reasoning is recorded
here rather than left in the diff.
## 0472: the C-style `for`'s initializer LIST, and a `continue` that CARRIES VALUES

Two gaps, both located by asking the scanner for `read up to line N` and then reading line N
of THAT FILE. That is worth a note of its own, because `_verify/rank_0468_first_blocker.ps1`
prints a header line and then the blocker source line, and the lines are laid out loosely
enough that reading them as PAIRS produced a shape count that was wrong in both directions --
attributing a `for` to a file whose blocker was a destructuring `let`. => 判据: a ranking is
a REPORT. Deriving structure from a report's formatting is how the report gets wrong.

THE HEADER. Three async files stop on a comma-separated initializer list:

    async/src/websocket/utils.mbt:49        for i = 0, remaining = remaining; i < data.length(); {
    async/src/internal/gzip_internal/crc32.mbt:53     for crc = current, i = 0; i + 8 <= len; {
    async/src/socket/addr_utils.mbt:262     for i = 0, zero_group_start = 0; i < 8; i = i + 1 {

`c_for_init` read exactly ONE initializer and `parse_c_for` pushed one statement. The list
reader calls `c_for_init` per entry rather than re-implementing it, so the token test from
0470 stays in one place.

THE VALUE. Two of those three then stopped on the NEXT line, because `continue` bumped the
keyword and returned, leaving its values in the stream:

    async/src/socket/addr_utils.mbt:267                continue i + 1, i + 1
    async/src/internal/gzip_internal/crc32.mbt:63     continue crc, i + 8

AND THIS IS THE HALF THAT REMOVES FINDINGS. `walk.mbt` and `infer.mbt` both treat `SContinue`
as a no-op (`SBreak | SContinue => ()`), so before this increment the names in
`continue p, r, c, vr` were read by NOTHING -- and an unread binding is exactly what
`UnusedLocal` reports. moonbit_image's bmp.mbt carries `continue p, r, c, vr` eight times.

THE VALUES ARE READ AND NOT ASSIGNED, and that is the deliberate choice. `continue a, b` means
"set loop variable one to a, loop variable two to b", and those variables are named by the
header, four frames away. Synthesising `SAssign(EName(loopvar_i), v_i)` would have the type
lens check an assignment nobody wrote against a target that may not exist -- a plausible
fabrication that would manufacture findings. Gate M5 is that fabrication, and it is killed.

NO `skip_seps()` BEFORE LOOKING FOR A VALUE, and the first draft had it. A bare `continue` is
followed by a `TNewline` and then the NEXT STATEMENT, so skipping separators reads that
statement's head as the value and swallows the rest of the body -- the file would still parse
and `parsed` would still go UP, so no corpus number could see it. Gate M4 inverts the guard
and the row that kills it puts a name after the continue.

REACH, measured on the tree at 0471:

    async   parsed 390 -> 392   unreliable 285 -> 264   notices 1686 -> 1690   actionable 0
    labeler / proton / moui / contract   BYTE-IDENTICAL

THE SETTLE'S FIRST RUN SAID "REJECT" FOUR TIMES OUT OF EIGHT CLAIMS AND WAS WRONG EVERY TIME
-- the fixtures, not the grammar. A loop variable is NOT MUTABLE: `for i = 0, total = 0;
i < n; i = i + 1 { total = total + i }` is [4087] "The variable total is not mutable", and
the body has to go through `continue`. The header those two rows were written to test is
fine -- A3 and A4, which put the update in the `continue`, ACCEPT, and so does the corpus.
=> 判据: when a settle row fails, read the ERROR CODE before deciding which of you is wrong.
4122 (calling a raising fn from a non-raising one) and 4118 (a bare `raise` needing a
bare-`raise` caller) both look exactly like a grammar refusal in the output.

=> ONE CORPUS NUMBER MOVED AND IT IS NOT EVIDENCE. moonbit_image `unreliable` 23 -> 15, total
230 -> 222, with `notices` 207 UNCHANGED and `actionable` 0. `unreliable` is defined in
`src/sa/main.mbt` as the findings at or after a file's FIRST READ FAILURE -- "derived from an
already-wrong tree, so reported only as a count, never as results". bmp.mbt's failure is
line 117, a multi-line C-style header, and reading `continue a, b` correctly CHANGES that
already-wrong tree.

Checked rather than waved through, in three steps: the count is stable across four runs of
the same wasm (so it is not the flakiness this project has seen elsewhere); reverting ONLY
the `continue` arm and keeping the header list reproduces HEAD's 23 exactly, so the header
change did not touch image at all; and on a COPY of bmp.mbt with the line-117 header repaired
so the whole file parses, `notices` is 14 vs 14 and every shown finding is byte-identical,
with only the suppressed remainder moving 14 -> 6. No evidence-bearing number moved anywhere,
and the whole investigation cost about an hour of not shipping a mystery.

Gate 0472: 5/5 KILLED, no declared survivors, every restore byte-identical.

## 0473: the `for` HEADER is one grammar, not two

THE DEFECT. `Parser::is_c_style_for` decided which of the two `for` forms it was looking at by
scanning forward for whichever of `;` and `{` arrived FIRST at depth 0. The header is variable
length, so that question has no right answer, and it was wrong in BOTH directions:

    for n = step() { break n + 1 }              no `;` before `{`, so read as a BINDER and
                                                died on `expected 'in'`.
                                                async/src/websocket/conn.mbt:486

    for p in ps; len = 0 { .. }                 a `;` before `{`, so read as C-STYLE;
                                                `c_for_init` only converts `TName` + `TAssign`
                                                and cannot read `p in ps`, so `expect(TSemi)`
                                                failed. async/src/io/reader.mbt:176

The second half is NOT FIXED here and must not be read as fixed. The binder head now routes
CORRECTLY, to the binder reader, and that reader stops at the `;`. The error moved from
`expected ';'` to `expected 'in'` and reader.mbt is still unread. Moving an error is not
removing it, and `parser_0473_test.mbt` pins the failure so a later reader cannot mistake the
improvement for the fix. That is 0474 and it is a different increment, because it needs an AST
decision rather than a discriminator.

THE SECOND DEFECT. `parse_c_for` carried two unconditional `expect(TSemi)`. They were not
describing the grammar, they were REJECTING LEGAL HEADERS -- which is why they also stood in the
way of `for ; n > 0 { .. }`, the optional-third-clause note that has been sitting on the todo
list since 0470. Every `;` now only says that a further clause FOLLOWS; none of them terminates
the list. That old item is closed by this increment.

SETTLED, NOT INFERRED. `_verify/settle_0473_for_header_forms.ps1`, 6 gated rows (2 controls, 4
claims) and 3 recorded, against `moon check`:

    ctl_c_for_three_clause            ACCEPT       <- the form 0470 settled
    ctl_binder_plain                  ACCEPT       <- the form 0470's control protects
    C1_single_clause_no_semicolons    ACCEPT
    C2_binder_then_one_clause         ACCEPT
    C3_binder_then_two_clauses        ACCEPT
    C4_two_binders_then_clause        ACCEPT
    record_binder_empty_clauses       ACCEPT       <- `for x in xs; ; {` is legal
    record_empty_single_clause        REJECT(4014,3002)  <- but `for ; {` is not
    record_field_named_in             REJECT(3002,4041,4091)

THE LAST ROW REMOVED CODE. The first draft of the new discriminator also required the token
before `in` to be able to end a pattern, so that `for i = some.in; ..` would not be read as a
binder head. `in` is a RESERVED word, so a struct field cannot be named it, and the settle says
so in the toolchain's own words. Every input that guard would have rejected is a program the
toolchain refuses anyway, so the predicate was unreachable and was deleted rather than kept as
decoration. A bare `in` at depth 0 in a header IS the binder keyword by definition.

THE SAME ARGUMENT IS WHY THERE IS NO MUTATION FOR THE DEPTH GUARD. `in` and `;` are reserved and
cannot appear inside a group as names, so no token that can flip an arm of this scan sits at
depth > 0 in a `for` header. A mutation that cannot fail tests nothing, and the gate says so
rather than inventing one.

MEASURED. Four of six corpora are byte-identical -- moui, moonbit_labeler, proton and
proton_contract did not move by a single field. `actionable` is 0 on all six.

    async           parsed 392 -> 394, notices 1690 -> 1698, unreliable 264 -> 243
    moonbit_image   parsed 17 unchanged, notices 207 unchanged, unreliable 15 -> 13

and both movements were ATTRIBUTED rather than waved through. Every C1-shaped header in async
was enumerated across the tree, and the scanner's own PARTIAL lines were diffed against a
`git worktree` build of HEAD:

    io/buffered_reader.mbt       blocked at 57  -> PARSES          `for searched = 0 {`
    internal/event_loop/io.mbt   blocked at 202 -> blocked at 364  `for rest = .., produced = 0 {`
    bmp.mbt (moonbit_image)      blocked at 117 -> blocked at 118

Nothing else moved in either corpus. bmp.mbt's header is the semicolon-less multi-line form at
lines 117-119, which `moon check` REJECTS [3002], so the analyzer's refusal is correct and what
changed is only WHERE it refuses: `expected ';'` at 117 became `expected '{'` at 118, because
the header reader no longer demands the `;`.

THE SECOND `+1` IS AN INFERENCE AND IS LABELLED AS ONE. Unparsed went 27 -> 25 while
blocked-with-findings went 22 -> 21, so one file moved out of the unparsed set without ever
printing a PARTIAL line -- it failed at HEAD with no findings. `http/utils.mbt`
(`for input = input {`, `for rest = start {`) is the only candidate in that class. That is
arithmetic, not measurement, and the pin comment in `release.ps1` says so in the same words.

Gate 0473: 7/7 KILLED, no declared survivors, every restore byte-identical. 913 tests.

AND A NOTE FOR ANYONE READING A GATE LOG. The test total is TARGET dependent: 899 on wasm and
827 on js, so gates `0.4.23` onward report `of 827 red` and a mid-run drop from 899 to 827 is
that, not a suite quietly losing 8% of its tests while reporting green.

## 0474: a loop in EXPRESSION position was dispatched to the WRONG reader

THE DEFECT. `parse_atom` matches on `self.bump()`, so the loop keyword is consumed as the match
SCRUTINEE and the cursor has already moved past it by the time the arm's body runs.
`parse_loop_as_expr` then chose between `parse_while_stmt` and `parse_for_stmt` by RE-TESTING
`at_name("while")` -- against that already-moved cursor. The re-test was therefore false for
EVERY loop expression, and all of them went to `parse_for_stmt`, which bumped the token after the
keyword as if it were `for`.

Isolated by a temporary trace, added, measured, then reverted:

    TRACE atom enter    p=13 cur=`while`
    TRACE atom dispatch p=14 cur=`a`
    TRACE as_expr       p=14 cur=`a` at_while=false

THE MEASURED TRIGGER, one fixture per row, all `let k = <loop> { 1 }`:

    while a { 1 }          parsed   nothing after the keyword to misread
    while a > 0 { 1 }      `unexpected token `>``
    while a + 0 { 1 }      `unexpected token `+``
    while 1 < 2 { 1 }      `unexpected token `<``
    while g(a) > 0 { 1 }   parses   a CALL head survives the misroute
    any of the above in STATEMENT position: parses

Two rows in that table are why this survived so long. The call head shows the OPERATOR is not the
trigger -- the misroute is, and a call happens to survive it. And `if a { while a > 0 { 1 } } else
{ 2 }` parses too, which is a FALSE PASS: the `TName("if")` arm skips the branch whole, so nothing
inside it was ever parsed. An `if` branch is not evidence about its contents, and a call head is
not evidence that the head was handled.

THE FIX restores the cursor before dispatching, so every downstream reader sees exactly the state
its own comments describe -- `parse_while_stmt` opens with `bump()`, `is_c_style_for` scans from
`self.p + 1`, `parse_c_for` opens with `bump() // for`. One line, in TWO EXPLICIT ARMS rather than
one `TName("for") | TName("while")`: written as an or-pattern with the comment above it, `moon fmt`
lays the comment out BETWEEN the alternatives and the result reads like a half-finished pattern.

=> 判据: a helper that RE-DERIVES which construct it is handling, from a cursor its caller has
already moved, cannot be correct by construction. The caller already knows which arm it matched.
Reading the code says the code is correct here -- `peek()` is the CURRENT token -- so this one
cannot be found by reading.

SETTLED. `_verify/settle_0474_loop_expr.ps1`, 7 gated rows (2 controls, 5 claims) and 1 recorded,
all ACCEPT against `moon check`. Tests: `parser_0474_test.mbt` 8 rows, `pipeline_0474_test.mbt` 3.

WHAT IT BUYS IS EXACTLY "THE FILE PARSES", AND NOT ONE FINDING MORE. `parse_loop_as_expr` consumes
the loop through the statement-position readers and then DISCARDS the statement, returning an
opaque `EBigInt`, so the loop body is parsed and thrown away. `pipeline_0474_test.mbt` pins that in
both directions: an undefined name inside a loop expression's body is NOT reported, while the same
name in a statement-position loop IS. A gain in `parsed` is a gain in COVERAGE, not in analysis,
and the two are not the same claim.

MEASURED. Five of six corpora are byte-identical -- moui, moonbit_labeler, moonbit_image, proton and
proton_contract did not move by a single field. `actionable` is 0 on all six.

    async    parsed 394 -> 396, notices 1698 -> 1728, unreliable 243 -> 203,
             withheld 40 -> 31, total 1941 -> 1931

`notices` +30 with `unreliable` -40 is ONE event, not two: the two files that recovered used to be
counted rather than reported, so they now report real notices. Attributed against a `git worktree`
build of HEAD:

    websocket/conn.mbt           blocked at 486 -> PARSES   `let kind = for frame = .. {`
    internal/event_loop/io.mbt   blocked at 364 -> PARSES   a `while` expression
    http/parser.mbt              blocked at  80 -> blocked at 440

Nothing else moved; blocked-with-findings 21 -> 20.

### The mutation that CANNOT fail, and why it was kept anyway

Gate 0474 is 3 KILLED and 1 declared SURVIVED, and the survivor is the interesting part.

M3 turns the restore `self.p -= 1` into `self.p += 1`. The obvious move is to go looking for the
row that kills it. That is the wrong question, because "which test catches this" and "can ANY test
catch this" have different answers and different verdicts. So the second one was measured instead
(`_verify/measure_0474_m3.ps1`, both trees built and scanned in one session, changing only that
line):

    correct   924/924 green   files=419 parsed=396 actionable=0 notices=1728 unreliable=203
                               withheld=31 total=1931    20 PARTIAL (blocked-file) lines
    mutated   924/924 green   files=419 parsed=396 actionable=0 notices=1728 unreliable=203
                               withheld=31 total=1931    20 PARTIAL (blocked-file) lines

and the two blocked-file lists are IDENTICAL NAME FOR NAME, not merely equal in length -- the count
alone would have hidden a file trading places with another. A 419-file corpus containing the very
loop-expression sites this increment is about moves not one bit.

The mechanism is one line of the increment's own code: `let _ = self.parse_for_stmt(sp)`. M3 sends
the header to `parse_c_for` instead, which builds a perfectly well-formed `SBlock`+`SWhile` -- and
it is thrown away. Both readers consume the identical token range. That is the worst shape a
mutation can have: it does not crash, does not error, and is wrong.

WHAT WOULD KILL IT was stated as a real change rather than a missing fixture: analysing the
loop-expression body. **That prediction was WRONG, and 0475 killed M3 without it.** 0475 added
rows on a header the misroute cannot swallow -- `for p in ps; len = 0 { .. }` -- and M3 now
fails them with `3 != 0`, because stepping the cursor forward sends the binder scan past the
`in`, `is_c_style_for` returns true, and `parse_c_for` cannot read `p in ps` as an initializer.
The two rows that kill it are `0475: the corpus loop-expression shape is read` and the inverted
`0473: a binder head followed by a C-style clause is now READ`.

Every binder head that existed at 0474 was a PLAIN one, and those survive the misroute. So M3
was never harmless -- it was silent on the headers that happened to be written.

=> 判据: this project has already used "a mutation that cannot fail tests nothing" to DELETE a
mutation. This is the same sentence pointing the other way, and both halves are needed: a green run
is compatible with "untested" and with "unobservable", and only one of them is acceptable to leave
behind. Reach PAST the suite before declaring a survivor -- the corpus is a measurement the test
suite structurally cannot make, because a discarded subtree cannot fail an assertion and cannot
move a finding count either.

AND THE HALF THAT WAS MISSED: a declared survivor is a claim about the CURRENT suite and it
EXPIRES THE MOMENT A ROW IS ADDED. The 0474 measurement was sound; the conclusion drawn from it
was still wrong, because "no test covers this" and "nothing can distinguish this" were separated
by evidence that did not yet exist. So the 58-gate run caught `mutate_0474` reporting M3 as
KILLED where the gate file said SURVIVED -- neither of the two files had changed, and only the
full run was looking. A `Prove` is an argument, not a constant, and the harness is what tells you
when to write a new one.

Gate 0474 at 0475: **4 KILLED, 0 survivors**, every restore byte-identical, 933 tests.

### The release gate caught a gate lying to itself, and that is the better story

The first full run after this increment FAILED, at `mutate_0465` M6 -- a gate three increments
old, whose row belongs to the very arms this increment rewrote:

    SURVIVED  M6 `for` and `while` in expression position report as undefined names
    GATE FAILED: 0465  (named test did not go red)

M6's anchor was the single line `TName("for") | TName("while") =>`. 0474 split that or-pattern
into two explicit arms, and afterwards the string existed in the file in exactly ONE place --
inside the comment this increment wrote to explain why the arm had been split.

So the mutation rewrote the PROSE. The text edit applied cleanly. The pre-flight reported the
anchor "present and UNIQUE", which was true. 852/852 stayed green. And the gate reported a
SURVIVED for a mutation that had changed no code at all.

It failed only because M6 is declared KILLED. Had it been a declared survivor -- which, by rule
5, is exactly the verdict a `--=`-turned-`+=` row invites when someone cannot find a test -- it
would have passed silently and nobody would ever have looked again.

FOUR things came out of it, and the third is the one that outlives the increment:

1. M6 is RE-ANCHORED onto the two real arms, keeping its meaning exactly: both keywords are
   renamed in one edit, because they are now two arms and the row is about both.

2. The parser comment was REWORDED so it cannot satisfy an anchor again. This is the part that
   feels like tidying and is not: a comment that quotes an anchor-shaped string is a live
   tripwire for every future gate, and this one was live for exactly one run.

3. `mutate_lib.ps1` GAINED RULE 8: an anchor must not be satisfiable by prose. The pre-flight
   already counted occurrences and reported uniqueness, and NEITHER property can distinguish
   code from a comment that quotes it. It now also tests whether every line the match spans
   begins with `//`, and ABORTS if so. A match on a line the compiler never reads is not a
   match on code.

4. The near-miss is recorded here rather than only in the gate that fixed it, because the
   general shape is not about parsers. An anchor is a POINTER to the line that decides
   behaviour. Presence says the text exists; uniqueness says it is alone; neither says it is
   the line that matters. A gate that verifies a pointer has found its target is a different
   thing from a gate that verifies the pointer's label appears once.

=> 判据: a mutation that changed nothing and a mutation that changed the wrong thing produce
the SAME green suite. The harness already had a rule for the first (NO-OP IS A FAILURE, added
when an absent anchor was read as a clean run). It had nothing for the second, and the second
is the more dangerous one, because an absent anchor aborts loudly while a prose-satisfied one
does not.

AND THE ORDER MATTERS, because it is the reason this was caught at all. `mutate_0474` was run
ALONE first and was green; had the 57-gate run been the only check, the failure would still
have surfaced -- but the 0474 anchor split and the 0465 anchor were made in the SAME increment,
and the gate that noticed was the older one. A new gate does not test the increment that added
it. Only the gates that already existed can notice that adding it broke something.

## 0475: a BINDER head carrying ONE declaration -- and the `nobreak` it turned up

THE DEFECT is the one 0473 refused to claim as fixed. `for p in ps; len = 0 { .. }` is legal
MoonBit; 0473 made the head route CORRECTLY to `parse_for_stmt`'s binder branch, and that
branch stopped at the `;`, so the error moved from `expected ';'` to `expected 'in'` and five
sites stayed unread. Moving an error is not removing it, which is why `parser_0473_test.mbt`
pinned the failure as a FAILING test. That pin is now INVERTED, which is the only honest
thing to do with it once the shape is read.

THE GRAMMAR IS NOT THE C-STYLE ONE, and this is the part a "just reuse the list reader" fix
gets wrong. `_verify/settle_0475_binder_clauses.ps1`, 2 controls and 9 rows, GATE OK:

    for p in ps; len = 0 { .. }              ACCEPT
    the declaration is readable in the body  ACCEPT
    for p in ps; len = 0; n = 1 { .. }       REJECT(4106)  a second `;`-clause is STEPS
    for p in ps; len = 0; len > 0 { .. }     REJECT(3002)  no condition after a binder head
    for p in ps; n = p.length() { .. }       REJECT(4021)  the binder is NOT in scope here
    for p in ps; len = 0 { .. } ignore(len)  REJECT(4021)  it does NOT outlive the loop
    for k, v in m; n = 0 { .. }              ACCEPT

The settle's FIRST DRAFT was wrong and aborted on it. It assumed the C-style variable-length
clause list carries across the binder head, and two of three claims flipped. What the compiler
volunteered is the sentence that settled it:

    Unknown binder n in the for-loop steps.
    Binders in the steps must be declared in the initialization block of the for-loop.

4106 is a SEMANTIC error, which means the text parsed and was then refused. The initialization
block after a binder head takes exactly ONE declaration; a second `;` introduces for-loop
STEPS, which this increment does not model and records as a known limit.

=> NO NEW NODE, and two REJECT(4021) rows are what say so. The declaration cannot see the
binder, so it is evaluated OUTSIDE the binder's scope, and hoisting it BEFORE the loop is
correct by construction rather than by argument. It does not outlive the loop either -- the
same scoping 0470 measured for the C-style init clause -- so `c_for_init`'s conversion is
reused unchanged. The desugar is the shape `parse_c_for` already builds.

### `actionable` went 0 -> 4 and back, which is the part worth reading twice

With the reader in place and `async` rescanned, the corpus reported **actionable 0 -> 4**:

    undefined name 'nobreak'   x3   async/src/process/{unix,windows}.mbt
    undefined name 'acc'            async/src/process/windows.mbt

Both are FALSE POSITIVES on code `moon check` compiles, and the cause is a PRE-EXISTING defect
this increment REVEALED rather than created. The multi-binder path never called
`maybe_nobreak`; `nobreak` is a postfix on a loop and is legal on all three forms (settle_0443),
so the multi-binder head is a loop like any other. Without the call the keyword stayed on the
cursor and the next statement reader took `nobreak { acc }` as an ordinary expression plus a
block -- and `acc` IS the loop binder, so reporting it out of scope there is the resolver being
correct about a block that had stopped being the loop's body. The second finding is a knock-on
of the first, not a separate defect.

They were invisible while the header itself failed to parse. Reading the header revealed them,
which is the same lesson 0464b and 0474 both turned on: UNBLOCKING A FILE DOES NOT CREATE
FINDINGS, IT REVEALS ONES WHOSE REACH WAS BLOCKED, and the honest response is to fix the gap
rather than give the reach back.

`mutate_0475` M4 is this regression with a corpus number attached -- applied, `actionable` goes
back to 4 and `parsed` 399 -> 396. That is the row that will catch it if it ever returns.

MEASURED. Five of six corpora byte-identical; `actionable` 0 on all six.

    async    parsed 396 -> 399, notices 1728 -> 1752, unreliable 203 -> 161,
             withheld 31 unchanged, total 1941 -> 1913

`notices` +24 with `unreliable` -42 is ONE event, not two: files that used to be counted
rather than reported now report. And not everything recovered -- `io/reader.mbt`'s header at
line 176 IS read now, and the file still stops, later, at line 186. That file is the next
blocker, not this one.

Gate 0475: 5/5 KILLED, no declared survivors, every restore byte-identical. 933 tests.

AND THIS INCREMENT ALSO EXPIRED A SURVIVOR DECLARED BY THE LAST ONE. The full 58-gate run
reported `mutate_0474` M3 as KILLED where 0474 had declared it SURVIVED with a measured proof,
and neither file had changed. 0475 added rows on the one header the misroute cannot swallow, so
M3 now fails them with `3 != 0`. The `Expect` is gone and a `MustRed` names the row; the proof
stays in the gate as the record of what was true when it was written. The full account is in the
0474 section above, and the lesson is the general one: A DECLARED SURVIVOR IS A CLAIM ABOUT THE
CURRENT SUITE, NOT A CONSTANT, and the harness is what tells you when it has expired.

TWO ROWS IN THE TEST FILE HAVE NO MUTATION, and the gate says so rather than implying coverage.
They are the negative rows -- a condition after a binder head, and a second declaration clause
-- and nothing in this increment can turn them red, because the refusal is not produced by a
guard here: the reader takes the one declaration and hands the cursor to `parse_block`, which
finds a `;` where it wants `{`. They are kept as a NAMED FUTURE RISK against an edit that
hands the tail to `c_for_inits`, which would accept headers the toolchain refuses.

=> 判据: a corpus number moving the WRONG way is the most informative reading this project
gets, and it only arrives because `actionable` is pinned to 0 rather than merely recorded. A
pin that only ever moves in one direction is not measuring anything. The same applies to the
mechanism: 0475 did not create a false positive, it removed a wall in front of one, and the
correct response was to fix the false positive -- not to leave the wall.

## 0476: the STEP, and a settle that had to be overturned by the corpus

0475 left a measured blocker -- `io/reader.mbt` read past line 176 and stopped at 186 -- and
line 186 is:

    for prefix in prefix_list; len = 0; len = len + prefix.length() { .. }

0475'S SETTLE SAID THIS CLASS OF HEADER IS REJECT. Its C3 row answered REJECT(4106) for
`for p in ps; len = 0; n = 1 { .. }` and the increment generalised "a second `;`-clause is
steps". The corpus disagreed, and the settle was the thing that had to give.

THE REASON IS IN THE COMPILER'S OWN SENTENCE, WHICH NEITHER HAND-WRITTEN PROGRAM SAID OUTRIGHT:

    Unknown binder n in the for-loop steps.
    Binders in the steps must be declared in the initialization block of the for-loop.

4106 was never about the NUMBER OF CLAUSES. It was about WHERE THE BINDER WAS DECLARED. `n`
is declared nowhere; `len` is declared two tokens earlier. `reader.mbt:186` was already
settled by any compiler run -- 0475 generalised a grammar from one convenient fixture, and the
corpus was carrying the verdict the whole time.

SETTLED, `_verify/settle_0476_for_steps.ps1`, 2 controls + 7 rows, GATE OK:

    for p in ps; len = 0; len = len + p.length() { .. }  ACCEPT   the corpus shape
    for p in ps; len = 0; len = p.length() { .. }         ACCEPT   the LOOP BINDER is in scope
    a step declaring a binder the init block does not declare REJECT(4106)
    a bare expression in a step                           REJECT(3002)
    two steps                                             REJECT
    a step with no initialization clause                  REJECT(4021, 4018)
    `;` immediately followed by `{` (an empty step list)  ACCEPT

=> NO NEW NODE AGAIN. A step runs at the END of each iteration, which is where `parse_c_for`
already puts the C-style update clause, so the step is APPENDED to the loop body -- and
appending before the multi-binder path builds its `$pair` destructuring is what puts the step
after it, which is the order that path needs.

TWO THINGS THE GATE CAUGHT IN ME, both of which were about writing the reader honestly:

1. **The first draft was too PERMISSIVE, and 0475's negative rows said so.** It accepted
   `n = 1` and `len > 0`, both of which the toolchain REJECTs. Those two rows were kept at 0475
   with the written admission that no mutation in that gate could turn them red -- this was the
   risk they were naming, arriving one increment later. The fix went in the READER, not the
   tests: a step must match the token shape AND assign the declared binder, and when either
   fails the cursor is deliberately left for `parse_block` to report. Weakening the rows would
   have bought a green suite and a false negative.

2. **A MUTATION SURVIVED AND THE COMMENT WAS LYING.** The reader carried an explicit
   `!self.at(TLBrace)` guard and a comment claiming it prevented the body's brace from being
   read as a step. M1 showed the mutation SURVIVED: `peek_name` returns `""` for a brace, so
   the `target != ""` test already does that, and the two conditions are equivalent. The guard
   was decoration and was deleted rather than kept with a proof it did not need -- the same call
   0473 made on an unreachable predicate, and the same one rule 8 makes about prose.

MEASURED. Five of six corpora byte-identical; `actionable` 0 on all six.

    async    parsed 399 -> 400, notices 1752 -> 1754, unreliable 161 -> 158,
             withheld 31 unchanged, total 1913 -> 1912

`io/reader.mbt` PARSES, with zero defects and nine notices. The increment is one file and one
grammar clause, which is the honest size of what was wrong.

Gate 0476: 4/4 KILLED, no declared survivors, every restore byte-identical. 938 tests.

RECORDED, NOT WORKED AROUND: `for p in ps; len = len + p.length() { .. }` is REJECT(4021, 4018)
by the toolchain -- the right-hand side names a binder that is not yet declared -- and the
analyzer reads that single clause as the initialization declaration and accepts it. That is a
consequence of the ALREADY-FILED scoping limitation rather than a decision taken here, and it
is recorded against that increment.

=> 判据: a settle row that passes BECAUSE the toolchain refused the fixture is evidence only
about the fixture. 0475's C3 used `n = 1`, which nothing declares, and generalised from one
program to a rule about clause COUNT. The rows that decide a grammar are the ones the corpus
ALREADY WRITES -- and when a corpus file and a settle disagree, the corpus is the one carrying a
compiler's verdict on real code. The cheapest possible check would have been to write the
corpus line as a settle row from the start; it was four lines away in the same repository.
## 0477 -- the PATTERN on the left of a `let`

`async/src/os_error/error.mbt` reported one line and nothing else:

    1x  expected '='

Line 79 is `let OSError(errno, context~) = self`, and the reason is not a near miss. There is
no pattern reader in the parser at all: a binding was read as a NAME followed by `=`, so
`OSError` was consumed as the bound VARIABLE and the reader then met `(` where it wanted `=`.
21 such sites in that corpus -- os_error, pipe, js_async, process/redirect -- and each one
cost its whole file.

**THE READER ALREADY EXISTED.** `parse_is_pattern` has read constructor patterns for `is`
since 0444, including the payload loop that collects every binding at every depth, and its
sub-features were settled against the toolchain for exactly what this shape uses: a lowercase
head binds while an uppercase one is a constructor TEST (settle_0444, 9/9), and `.. rest`
binds in an array (settle_0466b). So 0477 is a CALL SITE, not a second pattern reader. Two
readers would be two sets of rules for one grammar, and the corpus would be what found the
difference.

Settled in `_verify/settle_0477_let_pattern.ps1`, 2 controls + 9 rows, GATE OK:

    ACCEPT   positional / labeled / `..` rest / nested / tuple
    ACCEPT   a label BINDS the name (`let Circle(label~) = s`, then reading `label`)
    REJECT(4080, 3007)   anything after `..`        NOT this reader's check
    REJECT(4080, 4085)   an unknown label             NOT this reader's check
    REJECT(4080)         too many positionals         NOT this reader's check
    REJECT(0011)         a refutable pattern          NOT this reader's check

**THE SCAFFOLD WAS WRONG TWICE, and the controls caught both.** Declaring the fixture as a
`struct` made BOTH controls reject with 4199 -- *The type OSError does not declare a custom
constructor* -- because a struct declares no constructor, and `let OSError(..) = e` was never
a struct pattern. The corpus agrees; `pkg.generated.mbti:22` has `suberror OSError {
OSError(Int, context~ : String) }`. Then `Square(Int, side : Int)` was a parse error: inside a
variant the fields are POSITIONAL (`Int`) or LABELLED (`name~ : Type`), never `name : Type`.
Both faults were in the PRELUDE, and both were fixed by changing the fixture until the
toolchain agreed rather than by relaxing an expectation the compiler rejects.

**AND ONE OF MY OWN ROWS WAS LYING ABOUT ITSELF.** S7 is labelled "nested constructor" and as
first written it was a byte-for-byte copy of S9, so it duplicated the irrefutability question
instead of asking its own. Caught on re-read, replaced, and the answer moved: nested
constructors are ACCEPT.

=> NO NEW NODE. `SLetDestruct(Array[String], Expr)` is already the node for a `let` that binds
several names at once -- it is what `let (a, b) = pair` produces, and walk, infer and interp
already bind every name in it and evaluate the initialiser once. The four REJECTs are TYPE
questions and the parser is type-blind; refusing them here would mean refusing the corpus on a
check this reader is not equipped to make.

**THE BINDING IS THE CLAIM, AND THE CORPUS FILE COULD NOT PROVE IT.** `error.mbt:79` sits in
an `impl` body, and impl bodies are outside the analyzed subset, so the file proves the PARSE
and leaves the binding untested. A file that parses while binding nothing is the worst outcome
available: it converts a coverage blocker into a confident false positive against code the
compiler accepts, which is what 0460's comment records happening when an array pattern was read
as expressions. So the rows that matter are at the FINDING level, and every positive row has a
canary beside it -- because a row asserting `UndefinedName == 0` passes just as well on a lens
that has stopped resolving names altogether.

MEASURED. `actionable` 0 on all six corpora; ZERO `undefined name` findings anywhere in async.

    async    parsed 400 -> 403, unreliable 158 -> 120, notices 1754 -> 1776,
             withheld 31 unchanged, total 1912 -> 1896
    proton   unreliable 187 -> 186, total 2068 -> 2067; parsed, notices, withheld UNCHANGED

`parsed +3` is exactly the three files the backlog named. `unreliable -38` against `parsed +3`
is the expected PAIR and not two events: unblocking a file reveals findings whose reach was
blocked, it does not create them.

**PROTON'S -1, ATTRIBUTED -- AND MY FIRST ATTRIBUTION WAS WRONG TWICE.** The whole 2198-line
scan output differs on exactly one line: `facade_session.mbt ... 91 after it not shown`, where
HEAD said 92. `notices` is 128 in both and the region boundary is 1548 in both, so one finding
moved from after the boundary to before it. The mechanism is `facade_session.mbt:1664`,
`let Open(id, completion) = command` -- the single constructor-pattern site in that corpus.
At HEAD that line was the file's first parse error; 0477 reads past it, so the first failure
moves later and one fewer finding sits in the untrusted zone. The file is still blocked, by the
`<?` log payload, which is the next backlog item.

Two wrong turns are worth recording because both would have shipped a confident story:

1. I concluded 1664 "cannot matter" because the file reports `read up to line 1548`. That number
   is the ANALYSIS REGION boundary, not the parse cut. The arithmetic (`total = actionable +
   notices + unreliable`, with total findings fixed at 128) is what actually pins the move.
2. The first `git worktree` A/B was CONFOUNDED. It reported HEAD 187 vs mine 186 -- the right
   answer for entirely the wrong reason: the two runs sat in different directories, and
   `auto_fetch_deps` materialises a target's imports with `moon fetch` into a path that is
   RELATIVE to the process CWD (`sa/main.mbt:483`, `let base = ".repos/" + mod`), so the two
   runs indexed different interface trees. The right answer re-measured from one CWD still
   stands. => an A/B that does not verify its own inputs agrees with a broken one by
   coincidence, and the coincidence is indistinguishable from the result.

   **CORRECTED 2026-10-18: `--extern-iface-dir` is NOT ignored, and the sentence above that
   said so was wrong.** It was wrong because the run passed the flag AND sat next to the tree
   it names, so the flag and the CWD agreed and neither could be blamed. Measured directly, same
   binary, same CWD, proton 0.3.4:

                        IFACE types   values        dirs   actionable
       with the flag        1490      11315            2           0
       without it             205       1755            1          36

   `sa/main.mbt:239-243` starts the list at `[root]` and PUSHES each `--extern-iface-dir` onto
   it, so the flag is honoured and `dirs` reports exactly what it added. The CWD sensitivity is
   real but it comes from `auto_fetch_deps`, not from the flag being skipped. And there is no
   `Info:` line: the instrument that settles this is the `IFACE types=/values=/dirs=` triple
   the scan prints at `sa/main.mbt:244-248`. => a claim about a flag's being ignored needs its
   own run with the flag REMOVED; without that, "ignored" and "agreed by coincidence" are the
   same observation.

**AND A NAVIGATION TRAP THAT MADE ALL FIVE OF MY OWN TESTS FAIL, CONTROLS INCLUDED.** A
function body is wrapped in `SBlock` only when it is a SINGLE statement. `parser_0476`
navigates `body[0].kind -> SBlock(stmts)` because its fixture is one `for` loop;
`parser_0432` goes direct because its fixture is two statements. Both are right. My fixtures
have two or three statements and I navigated through `SBlock` anyway. Five failures including
both controls is the signature of a wrong NAVIGATION rather than a wrong reader -- and the
corpus scan had already measured the reader working.

Gate 0477: 4/4 KILLED, no declared survivors, every restore byte-identical. M2 is the mutation
the increment exists for: it binds one INVENTED name instead of the pattern's, parses clean,
and is invisible to `first_error` -- visible only as `undefined name` on the next line.

**AND A DECLARED SURVIVOR FROM 0.4.34 EXPIRED UNDER THIS INCREMENT.** The full 60-gate run came
back red on gate **0421**, not on 0477: `M7 nested-constructor rule removed` was declared
`Expect = 'SURVIVED'` with a `Prove` argument that it had become UNREACHABLE rather than merely
unobserved -- with the rule removed, `Some(Os(error))` binds both `Os` and `error`, nothing is
undefined and nothing is audited, so the mutated source reads CLEANER than the original. That
argument was TRUE, and true about a particular OBSERVATION SURFACE.

0477 is what ended it. The new row asserts `names.length()` at the AST, so removing the rule
makes `One` bind alongside `inner` and the assertion reports `2 != 1`. Applied by hand the
mutation turns exactly ONE test red and it is that one -- which is also why the gate's own
summary line, "1 of 948 red", was not enough on its own to NAME it. `Expect` is now `MustRed`,
and the 0.4.34 reasoning is left in place rather than quietly rewritten: it was checked and
found wanting, not forgotten.

=> 判据: a declared survivor is a claim about the CURRENT suite, not a constant -- and it was
also a claim about a current OBSERVATION SURFACE. "No lens can disagree with this rule" stayed
true; an AST assertion is not a lens. The risk a survivor names is the risk that the next
increment buys a different instrument, and this one did. The failure mode to watch is the
opposite one: a gate that reads "KILLED" and moves on has told you the suite grew, and a gate
that reads "SURVIVED" and leaves the note alone has told you nothing has.

## 0478 -- the `<?` PAYLOAD

26 sites across 7 files in proton 0.3.4, and four of those files were unreadable because of it:

    @xlog.error(category="proton.command") <?
      { "message": "command dispatch failed", "detail": detail }

MEASURED, and it is the largest single drop in the backlog:

    proton   parsed 131 -> 135, unreliable 186 -> 37, notices 1881 -> 2023,
             withheld 6 unchanged, actionable 0 -> 0, total 2067 -> 2060

`unreliable -149` against `parsed +4` is the expected PAIR and not two events: unblocking a file
reveals findings whose reach was blocked, it does not create them. `actionable` staying at 0
matters more than either -- this reader makes four whole files analysable and invents nothing
against code the compiler accepts.

**THE SHAPE WAS READ FROM THE INTERFACE, NOT PROBED.** `@xlog` 0.4.2's `pkg.generated.mbti`:

    pub fn error(category? : String, loc~ : SourceLoc) -> Event?
    type Event
    pub fn Event::write_object_begin(Self) -> Unit
    pub fn[T : ToJson] Event::write_object_field(Self, String, T) -> Unit
    pub fn Event::write_object_end(Self) -> Unit

so the payload is a JSON object literal DESUGARED TO METHOD CALLS ON THE RECEIVER -- `{` is
`write_object_begin`, each `"key": value` is `write_object_field`, `}` is `write_object_end`.
The receiver is an `Event?`, an OPTIONAL, and the subset has no `Event` to hang fields on.
That is why this reader has no NODE: there is nothing in the analyzed subset for it to be.

Settled in `_verify/settle_0478_log_payload.ps1`, 2 controls + 5 rows, GATE OK:

    ACCEPT              the corpus shape
    ACCEPT              a value may be an EXPRESSION (`"detail": detail`)
    ACCEPT              a TRAILING COMMA is legal here, unlike a struct field (3800)
    ACCEPT              `<? { }` with no field at all
    REJECT(3002)        the KEY must be a string literal
    REJECT(3002, 3002)  AT MOST ONE payload

The last row is the one that shapes the reader rather than bounding it: a LOOP would consume
the second `{` of `x <? {..} <? {..}` and carry on, so `had_payload` exists to stop at the
closing brace and leave the rest for the statement reader to report.

**MY OWN GATE WAS 4/4 KILLED AND THE RELEASE GATE STILL FOUND A REAL BUG.** M1 brace-not-required,
M2 the flag never set, M3 the key not required to be a string literal, M4 the payload braces left
in the stream -- 4/4 KILLED, every restore byte-identical, no declared survivors. All four
mutations are correct questions and all four pass on synthetic fixtures. None of them can see
that the corpus does not spell the brace where my lookahead expects it:

    same-line brace : 12
    next-line brace : 14

The first version asked for `TLBrace` at `self.p + 2`. That refuses 14 of the corpus's own 26
sites. The damage looked small because only the files whose FIRST error is a next-line brace go
unparsed -- 5 of the 7 open that way -- and with the fix reverted the run came back with
`3x unexpected token '?'`: three files gave back the ground 0478 had just gained for them, and
every count that mattered moved the wrong way. A fix that is right in spirit and wrong in
SPELLING, invisible to a gate that asks "does this rule still discriminate?" and answered only
by a gate that asks "does this still read the corpus?".

**AND THEN THE RELEASE GATE CAUGHT THE OPPOSITE ERROR, WHICH WAS NOT MYSELF.** With the lookahead
fixed the run came back red on the proton pin: 2060 pinned, 2066 actual, `actionable` 0 -> 2.

    NOW: SUMMARY  files=137 parsed=135 actionable=0 notices=2023 unreliable=37 withheld=6 total=2060

The first version parsed the payload's values and then DISCARDED them. The corpus does not care --
it parses either way -- but the walker never visited a value it was not handed, and a parameter
used only inside a payload is then indistinguishable from an unused one:

    facade_runtime.mbt:136    parameter `error`
    facade_session.mbt:3413   parameter `detail`

Two FALSE `UnusedParam` findings against code the compiler accepts. Worse, `actionable` 0 -> 2 is
the direction that 0475 was investigated for and not accepted, so the run refused to pin.

**AND THEY WERE INVISIBLE, WHICH IS A HARNESS FACT AND NOT A LUCK ONE.** `findings_shown_per_file
= 40` in `sa/main.mbt` truncates both files -- 23 and 215 notices -- so the scan that changed the
pin printed a summary whose two changed numbers were not on the screen. Raising the limit to 400
is what made them visible; it was restored to 40 and the diff left clean. A truncation setting
that hides the two lines a run failed on is a silent amplifier, and the pin is the only reason
this was caught at all.

**AND THEN THE GATE'S OWN ANCHORS ROTTED, WHICH MEANS THE "4/4 KILLED" ABOVE WAS TRUE AND WAS
ABOUT CODE THAT NO LONGER EXISTS.** Gate 0478 first stood up 4/4 KILLED. Two fixes landed after
that measurement, and each moved an anchor:

- the newline fix replaced the inline `self.toks[self.p + 2] == TLBrace` with a call to
  `at_log_payload_brace`, so M1 was pointing at a line that had been deleted;
- making the function RETURN the values it keeps turned `_ => return` into `_ => return kept`
  (M3) and a bare `self.skip_log_payload()` into `let kept = self.skip_log_payload()` (M4).

The next full release said all of that in one second: `ABORT: 3 pattern(s) absent. No suite was
run.` None of the three was retired -- retiring a mutation because its anchor moved is precisely
how a rule stops being checked while the gate keeps reading OK -- and all three are re-anchored
at the CURRENT spelling of the SAME three questions: the brace is still required (M1), the key is
still required to be a string literal (M3), the payload is still consumed (M4). Re-measured from
scratch: 4/4 KILLED, every kill naming its test, every restore byte-identical.

=> PARSED IS NOT READ. A value consumed by the reader and dropped is syntactically accounted
for and semantically invisible, and every lens that reports on USE will call its names dead. The
fix is `@ast.ETuple([e] + kept)` -- not a payload node, but the receiver and the values in one
tuple, so the walker visits what the program actually says. `skip_log_payload` now returns
`Array[@ast.Expr]` and nothing is thrown away.

=> 判据: the two instruments answered two different questions and only one of them had the corpus
in it. A mutation gate asks whether a rule still DISCRIMINATES, on fixtures I wrote; the release
gate asks whether the reader still AGREES with 26 sites of code I did not. Four mutations killed
and a newline in the wrong place is not a contradiction -- it is the reason the release gate
exists, and the reason "4/4 KILLED" was never going to be the sentence that ends an increment.

The corollary cuts the other way too: `actionable` 0 -> 2 on a corpus the release gate had pinned
is the pin WORKING, not the reader regressing. Pin it or do not ship it, and read the two changed
numbers even when the screen truncates them.

And the third instrument is the one I keep under-using. A mutation verdict is a CLAIM ABOUT A
SPELLING, and two fixes later that spelling is gone. Pre-flight is not bureaucracy before the
real work -- it is the only stage that notices when a number I already banked has stopped
describing the code, and in this increment it fired on three mutations I would otherwise have
reported as passing.

## 0480 -- the UNBRACED escape, `'\uXXXX'`

`character literal must hold exactly one character` -- one line, in two corpora, and the reason
was a spelling 0459 had already settled the other side of.

    proton  internal/native/configuration.mbt:4        c < '\u007f'
    labeler extensions/labeler/labeler.mbt:2741        buf.write_char('\u000C')

0459's guard required `\u` to be followed by `{`, so the unbraced spelling fell through to
`other => other`, which wrote the letter `u`, and the four hex digits were appended by the
ordinary character path. The payload became `u007f` -- five characters -- and the length check
refused it. **A FALSE REFUSAL**: the corpus writes this form and the compiler accepts it.

**IT IS NOT TWO FILES.** A sweep of every `.mbt` under `.repos` for single-quoted literals
holding an unbraced escape finds the form in `moonbitlang/core` `builtin/char.mbt` about a
hundred and fifty times, in `char/predicate_reference_test.mbt` as many again, and through
`x/json5`, `x/unicode`, `svg` and `sqlite3`. The standard library's own source uses the
spelling, which is what makes this a grammar clause rather than a local quirk.

MEASURED.

    moonbit_labeler  parsed 35 -> 36, unreliable 55 -> 16, notices 738 -> 776,
                    withheld 16 unchanged, actionable 0 -> 0, total 793 -> 792
    proton           parsed 135 -> 136, unreliable 37 -> 31, notices 2023 -> 2029,
                    withheld 6 -> 0, actionable 0 -> 0, total 2060 unchanged

`unreliable -39` and `-6` against `parsed +1` each is the expected PAIR: unblocking a file
reveals findings whose reach was blocked. proton's `withheld 6 -> 0` is the whole increment in
one number -- those six findings were being withheld because the file could not be read at all,
and now every one of them is analysed.

Settled in `_verify/settle_0480_unbraced_unicode_escape.ps1`, 3 controls + 6 rows, GATE OK:

    ACCEPT        `'\u007f'`  the proton shape       ACCEPT  `'\u000C'`  the labeler shape
    ACCEPT        `'\u{1F600}'`  the braced form, and the ONLY spelling for astral
    REJECT(3001)  `'\u07f'`     three digits           REJECT(3001)  `'\u01F600'`  six, astral
    REJECT(3001)  `'\u00007f'`  six, BMP               REJECT(3001)  `b'\u000C'`   the byte form

**M2 IS A REAL BUG THE GATE FOUND, AND IT IS WHY THE READER TAKES A FLAG.** The first
implementation widened the escape guard without a context flag, and `b'\u000C'` then lexed
cleanly -- while the toolchain calls it REJECT(3001) with `b'\x0C'` ACCEPTing beside it. The
byte-literal branch routes `b'...'` into the SAME reader, so a guard widened in one place is
widened in both, and the file still parses. The test row caught it (`0 != 1`) before a corpus
was scanned. Two literals, one reader, one flag.

**AND TWO OF MY OWN TEST ROWS COULD NOT SEE THE MUTATIONS THEY WERE WRITTEN FOR.** Both were
caught by `MustRed` rather than by reading them, which is the argument for that field existing:

1. The six-digit row used `'\u01F600'`, which is ASTRAL. With the fourth-digit check removed
   that literal lexes to U+01F600, whose LENGTH through this token is measured by the string
   builder's astral handling -- so both the correct and the broken reader report one finding.
   The fixture is now `'\u00007f'`: same six digits, BMP value, and the broken reader produces
   one character and NO report. 0459's test file says this in its own words, and I repeated it
   a hundred lines below the place it was written down.
2. No row observed the VALUE. With `braced` reverted to `e == 'u'`, the branch consumes the
   first hex digit as though it were a brace and `'\u1234'` becomes U+0234 -- one character,
   zero reports, length correct. The corpus would never have found it: nothing in this project
   compares characters.

**M3 SURVIVES BY PROOF, and the proof is about the CURRENT guard.** Dropping the first two
digit checks cannot change any well-formed literal, because the digit loop already stops at the
first non-hex and writes nothing when it consumed none -- so an escape admitted by a weakened
guard contributes no character, and the one-character check refuses the literal either way.
That is stated in the gate rather than left implicit, and it expires the moment the guard is
rewritten: if a future increment makes the escape write a character at `digits == 0`, the proof
stops being true and has to be re-argued rather than inherited.

Gate 0480: 3 killed, 1 declared survivor, every restore byte-identical. 962 tests.

=> 判据: a rule can be right and a test can still be blind, and "both readers report one
finding" is not agreement. The two blind rows failed for the same underlying reason -- each
asserted a COUNT where the failure was in a VALUE -- and one shared fix: assert the thing the
rule is actually about. `'\u1234'` is one character with or without the bug, so the row has to
compare it to `"\u{1234}"` or it is a comment with an assertion in it. The general shape:
a mutation that survives is either a rule that is not load-bearing, which is worth knowing and
worth writing down, or an instrument that is not measuring -- and the difference between those
two is exactly one question, which is whether ANY input makes the two readers disagree.

## 0479 -- U+FEFF, the BYTE-ORDER MARK

One line, one file, and a refusal of code the toolchain accepts.

    unexpected character '<U+FEFF>'
    e.g. riantr/moonbit_labeler/0.2.13/app_moui/labeler_ui_test.mbt   (first three bytes EF BB BF)

A sweep of every `.mbt` under `.repos` finds this is the ONLY file in the corpus that starts
with a byte-order mark. One file is a reason to fix it rather than to skip it, because a
refusal of valid code is never coverage and always wrong.

MEASURED, and it is the whole corpus:

    moonbit_labeler  parsed 36 -> 37, unreliable 16 -> 0, withheld 16 -> 0,
                    notices 776 -> 791, actionable 0 -> 0, total 792 -> 791

37/37 files parse and `unreliable` is 0 for the first time in this corpus: nothing sits in the
quarantine. `actionable` staying at 0 is the number that matters, and the unblocked file
reports 15 notices and zero defects.

**THE ROW THAT DECIDED THE SIZE OF THE FIX IS S4, AND IT ACCEPTED.**

    ACCEPT  the corpus's first three lines, byte for byte including the mark
    ACCEPT  a mark before a declaration / before a `///|` / on an empty file
    ACCEPT  a mark MIDFILE           `1 <mark> + 2` is `1 + 2`
    ACCEPT  a mark inside a string literal

So this is NOT a "strip a three-byte preamble" change. U+FEFF is legal wherever it appears, the
lexer has to skip the character, and the fix reaches every position. A preamble-only fix would
have passed every ACCEPT control, unblocked the one file anyone had seen fail, and left the
rule wrong for every file a mark turns up in later -- the 0475 shape, and 0459's `b'\x00'`
before it. `Lexer::run` skips it beside space, tab and carriage return, and nothing else.

**STRING CONTENTS ARE UNAFFECTED BY WHERE THE SKIP LIVES, NOT BY A SECOND GUARD.** `run`
dispatches to `lex_string` on `"` and that reader consumes the whole literal, so a mark inside
one is never offered to the skip. A second guard would be a way to change a string's value by
accident, and the test asserts the payload LENGTH for exactly that reason: if the skip ever
moved inside `lex_string`, `"a<mark>b"` would lose a character and every program comparing
that string would silently disagree with the compiler.

**THE CONTROL IS THE CHARACTER IMMEDIATELY BESIDE IT.** The settle licenses exactly one
character, so the nearest miss is the right probe: U+FFFE, one code point away, which a guard
written as a range or one reaching for "the byte-order marks" swallows. `\u{FFFF}` is not used
-- it is not adjacent to anything this change touches, so it would pass against a guard that
widened to a whole block.

Gate 0479: 4/4 KILLED, no declared survivors, every restore byte-identical -- and the first
gate in three increments to pass on its first run, after 0478 and 0480 both arrived with
anchors that two fixes had already moved. 967 tests.

RECORDED, NOT SETTLED: the skip advances `col` like a space does, so a token after a midfile
mark is reported one column further right than it appears. Whether the compiler does the same
is not observable through `moon check` -- it reports line and column for its own diagnostics,
not for a character it skips -- so there was nothing to settle and this is a judgement call.
It affects only the COLUMN of findings that follow a midfile mark, of which the corpus has one.

=> 判据: the corpus names one file at a time, and a fix sized to the file that was reported is
a fix verified by its own symptom. The settle's job is to say how big the rule is, and here it
said bigger than the defect: one file refused a PREAMBLE-shaped problem, and the grammar says
the character is legal everywhere. The row that decides this is never the row about the
reported case -- it is the one about a case nobody reported, and it is the row that costs
nothing to write and everything to skip.

## 0481 -- a NESTED optional type, and the last file in proton

    unexpected token ':'
    e.g. proton 0.3.4/internal/native/types.mbt   read up to line 1351, 31 after it not shown

Line 1351 is `pub fn RuntimeEvent::notification_click(self : RuntimeEvent) -> String?? {`, and
`String??` is `Option[Option[String]]`. The reader folded ONE `?` into the type and left the
second in the stream, so the function reader met a `?` where it wanted a body.

**THE REPORTED TOKEN WAS EIGHT TOKENS EARLIER THAN THE DEFECT.** `self : RuntimeEvent` holds
the only colon on that line, and it is perfectly ordinary -- labelled parameters, which work,
and which the settle's `ctl_labelled_param` row now pins with a name instead of my assuming
it. Chasing the reported token would have meant rewriting labelled parameters, which is a
class of change this project has already made and reversed twice. The report was not wrong
about where it stopped; it was wrong about what stopped it.

MEASURED, and it closes a corpus.

    proton  parsed 136 -> 137, unreliable 31 -> 0, withheld 0, notices 2029 -> 2131,
            actionable 0 -> 0, total 2060 -> 2131

137/137 with an empty quarantine. Four of the six pinned corpora now parse every file:
moui 608/608, moonbit_labeler 37/37, proton 137/137, proton_contract 4/4.

Settled in `_verify/settle_0481_nested_optional_type.ps1`, 3 controls + 6 rows, GATE OK:

    ACCEPT  `-> String?`   `-> String??`   `(x : String??)`   `let x : String??`
    ACCEPT  `-> String???`      the nesting is UNBOUNDED
    ACCEPT  `self : String`     so the reported `:` was a red herring

**S5 IS WHY THIS IS A LOOP AND NOT A SECOND BUMP.** `-> String???` is ACCEPT beside
`-> String??`, so the grammar has no cap and a two-bump fix would be right by luck: it would
pass S1, S2 and the corpus -- which has exactly one doubly-optional type in it -- and would
refuse the third for no reason the toolchain shares. The settle says UNBOUNDED and the reader
is now a `while`.

There is no ternary to confuse this with. A type annotation is not an expression, and the
optional-ARGUMENT shorthand `?` is written before the parameter name, never after a type.

**M2 IS "PARSED IS NOT READ" ONE LAYER DOWN, AND IT IS THE MUTATION THE CORPUS COULD NOT HAVE
FOUND.** Dropping `n = n + "?"` leaves the loop eating every mark: the parse succeeds, nothing
is reported, and the annotation comes back `String` for a program that says `String??`. The
text of the type is simply lost. Nothing here renders annotations back out and nothing reports
a type mismatch, so no scan of any corpus would ever have seen it -- the tests assert on the
RENDERED annotation precisely because "the file parses" is not evidence about it.

**AND ONE OF MY OWN MUTATIONS TESTED NOTHING, WHICH THE GATE SAID IN ONE LINE.** M3's first
draft appended the extra `?` AFTER the loop's closing brace, so the function's value had
already been produced by the `n` above it and the result was a type mismatch, not a mutation.
The gate reported COMPILE-ERR and named the line. A mutation that fails to compile is not a
mutation; it is a check that the code has a particular shape, and reading the compile error
rather than the verdict is what told me which.

Gate 0481: 3/3 KILLED, no declared survivors, every restore byte-identical. M3 kills 49 tests,
which is the plain-type control turning out to be load-bearing far past this file. 973 tests.

=> 判据: a reported token is a claim about where the reader STOPPED, not about what stopped it,
and the two came eight tokens apart here. The corpus names a line; the grammar is wider than
the line; and the difference between fixing the line and fixing the grammar is whether anyone
asked a question outside the corpus before writing the fix. Both of this increment's surprises
came from that: the UNBOUNDED nesting, and the error message pointing at a working feature. The
settle row that is about the reported case will agree with you either way -- S2 would have
passed against a two-bump reader. The rows that disagree are the ones about shapes nobody has
written yet, and those are the only ones with any information in them.

## 0482 -- a `for` HEADER SEPARATED BY LINE BREAKS, and the last file in moonbit_image

    expected '{'
    e.g. moonbit_image 0.3.7/bmp.mbt   read up to line 118, 13 after it not shown

Lines 117-119 are a three-clause C-style `for` header with not one semicolon:

    for i = 0
        i < num_colors && i * 4 + palette_offset + 3 < self.data.length()
        i = i + 1 {

`parse_c_for` gated the condition and the update behind a single `if self.at(TSemi)`, so a
header with no semicolon skipped the whole clause list, and the cursor -- sitting on the
condition -- went to `parse_block`, which reported `expected '{'`.

**`region_line` 118 RATHER THAN 117 IS THE RECEIPT THAT DECIDED WHERE THE FIX BELONGS.** 118
is the condition token; 117 is the `for`. The head was READ and only the separator was missing,
so this was a gate and not a head. Same shape as 0481, whose report landed eight tokens before
its defect: a reported token is a claim about where the reader stopped, not about what stopped
it. Third increment running, third time the reported position and the defect have been
different things.

MEASURED, and it closes a corpus.

    moonbit_image  parsed 17 -> 18, unreliable 13 -> 0, withheld 0, notices 207 -> 218,
                   actionable 0 -> 0, total 220 -> 218

18/18 with an empty quarantine. FIVE of the six pinned corpora now parse every file: moui
608/608, moonbit_labeler 37/37, moonbit_image 18/18, proton 137/137, proton_contract 4/4. Only
async is short, at 403/419, and it is unchanged -- its five `expected '{'` files are a DIFFERENT
construct, which is worth knowing because two increments' worth of ranking would otherwise have
sent the next one after this one twice. Distinct NOTPARSE reasons across the whole backlog: 14
-> 9. async's `unreliable` moved 120 -> 122 with `parsed` unchanged at 403: two files now read
FARTHER before their boundary, so this is the boundary moving and not a new failure.

Settled in `_verify/settle_0482_for_header_no_semicolons.ps1`, 3 controls + 3 claims + 6
recorded, GATE OK:

    ACCEPT  three clauses on three lines with no `;`
    ACCEPT  init + condition, no update
    ACCEPT  a `&&`/`<` chain spanning two comparisons
    REJECT(3002)      all on ONE line
    REJECT(3002)      a `;` before the condition and a line break before the update
    REJECT(3002,4021) the head on the line after the `for`

**THE NEWLINES ARE LOAD-BEARING, AND THAT IS THE ROW THAT SIZED THE FIX.** `for i = 0 i < n i =
i + 1 {` on one line is REJECTed, and both mixed-separator rows REJECT too: it is all `;` or all
line breaks, never a mixture. So the separator is not optional punctuation and the rule is not
"be liberal about `;`".

**THE NATURAL FIX DID NOT WORK, AND THE REASON IS A COUPLING THREE FUNCTIONS AWAY.** Gate on
"is the cursor on a `;` or a `TNewline`" -- `at_sep` -- is the direct reading of the settle and
it does not fire, because `parse_is` (parser.mbt:3779) consumes trailing newlines
UNCONDITIONALLY before testing for its own `is` continuation, so that

    guard (a, b, c)
      is (x, y, z) && ...

keeps working -- a 15-finding fix on `embedded_runtime_backend.mbt`. Every full expression ends
there. By the time any clause reader looks, a newline-separated clause is INDISTINGUISHABLE
from an adjacent one, and there is no separator token left to ask about. I found this by
printing the cursor at four points rather than by reading, which is the third time this round
that reading the code would have produced a confident wrong answer.

**SO THE CLAUSE LIST IS POSITIONAL.** "Another clause exists" is asked of the TOKEN -- can this
begin the body? -- and the two `at(TSemi)` bumps are what keep the slots aligned when a
separator is spelled. The coupling is real and falsifiable, and it is written into `parse_c_for`
rather than left to be inferred from a chain that looks like it should be testing `TNewline`: if
`parse_is` ever stops eating newlines, every row in `parser_0482_test.mbt` goes red and this
becomes a rewrite.

**THE SECOND DRAFT BROKE A PASSING ROW, AND THAT IS M4.** `skip_seps` instead of one separator
at a time collapses `for i = (0, 1); ; i = i + 1 {` -- 0472's `ctl_tuple_comma`, an ACCEPTed
program whose MIDDLE slot is empty -- and shifts the update into the condition slot. One line of
this increment turned that row red before the draft was replaced. An empty clause is legal; the
`at(TSemi)` guard on the condition is the only thing holding it in place, and it looks redundant
next to the `{` guard.

Gate 0482: 4/4 KILLED, no declared survivors, every restore byte-identical. 980 tests.

**AND ONE OF MY OWN MUTATIONS TESTED NOTHING AGAIN, IN THE SAME PLACE.** M2's first draft
replaced the condition clause with `let _ = cond`, which leaves `cond` declared `mut` and never
assigned, and `moon test --deny-warn` rejects the unused mutability as Error [0015]. COMPILE-ERR
is a shape check, not a mutation. 0481's M3 failed to compile for a different reason and 0482's
M2 for this one, which is twice in three increments -- worth remembering as a habit rather than a
fluke: check that the mutated code still ASSIGNS what it declares before reading the verdict.

**M3 IS THE MUTATION NO CORPUS SCAN COULD FIND, AND IT IS WHY THE TESTS ASSERT ON THE BODY.**
The update clause is parsed, consumed, and then dropped on the floor: the file still parses,
`parsed` stays 18/18, `actionable` stays 0, and the loop body is one statement shorter in every
loop that has a step. "Parsed is not read" again, and the row that catches it asserts on the
RENDERED loop body rather than on `first_error`.

**A CLAIM I HAVE BEEN CARRYING SINCE 0470 WAS WRONG, AND 0482 IS WHY IT MATTERED.** Both
`mutate_0470.ps1` and `parser_0470_test.mbt` justified a defensive step by saying "the lexer
emits no whitespace token between `for` and its first name". It does -- `TNewline` is emitted
there like everywhere else, which is why the step exists at all. The real reason the step is
unreachable is narrower and is now measured: MoonBit requires the head on the `for` line
(settle C4, REJECT 3002/4021). The decision stood; the reason did not, and believing it would
have pointed 0482 away from `parse_is` -- exactly where the bug was. Both files carry the
correction now, and the settle row that measures it was added rather than left to be found
later. The same lesson as the falsified `--extern-iface-dir` claim in 0477, and the second time
the argument itself was the defect.

RECORDED, NOT ENFORCED: four shapes the toolchain REFUSES are now read -- the one-line header,
both mixed-separator spellings, and a skipped clause. They are MISSED errors, not false
positives, and the direction that matters is closed. Enforcing the rest needs a rule this
increment has not measured (whether a wrapped `for i = 0;\n  i < n;` counts as a mixed
separator), and a false error on legal code is the worse of the two. The one-line case is
asserted in `parser_0482_test.mbt` as a known over-permissiveness rather than left in prose,
because a comment does not fail when the behaviour changes. `parser_0470_test.mbt` recorded the
same species for `for let` in prose only, because it had no measured toolchain row to point at;
there is one here, so the bar is different.

=> 判据: THE ROW ABOUT THE REPORTED CASE CANNOT TELL YOU HOW BIG THE RULE IS. C1 is the corpus
line and C1 would have passed against almost any permissive fix -- including `skip_seps`, which
is the draft that broke a passing row two steps later. The rows that carried the information
were `record_all_on_one_line` (the separator is load-bearing, not optional) and the two mixed
rows (all-or-nothing), and both of them are about a program nobody reported. 0479 said the same
thing about a preamble, 0481 about a third `?`, and 0482 about a line break: three increments,
three rules that turned out wider than the file that named them, and in all three cases the
settle row that disagreed was free to write and easy to skip. The corpus tells you where to
look; only a question outside it tells you how far to reach.

## 0483 -- a PACKAGE-QUALIFIED HOLDER, `@pkg.Type::method`, and the last three async files

    tls/transport.mbt:36      read up to line 36, 6 after it not shown
    http/parser.mbt:440       read up to line 440, 3 after it not shown
    process/redirect.mbt:156  read up to line 156, 31 after it not shown

All three stop on one line:

    fn @io.ReaderBuffer::repr(buf : Self) -> @io_buffer.Buffer = "%identity"

**THE LINE NAMES TWO CONSTRUCTS AND ONLY ONE OF THEM IS BROKEN.** It reads like a missing
foreign-function body -- a `= "string"` where a `{ }` would go. A nine-case probe against this
analyzer's OWN parser, not inference:

    fn Buf::repr(b : Buf) -> Int = "%identity"       0   <- the body is already read
    fn Buf::repr(b : Buf) -> Int { 1 }               0
    extern "C" fn exit(code : Int) = "exit"          0
    type @pkg.Buf                                   0   <- @pkg is fine in a TYPE
    fn @pkg.Buf::repr(b : Buf) -> Int = "%identity"  2   <- HERE
    fn @pkg.Buf::repr(b : Buf) -> Int { 1 }          2
    fn @pkg.Buf::repr(b : Buf)                       2
    extern "C" fn @pkg.Buf::repr(...) = "x"          2

The body form is IRRELEVANT and the `@pkg.` is decisive. This is the THIRD boundary line in three
increments carrying a construct that already worked, and the fourth time the reported line was
read as the defect: 0481's `unexpected token ':'` named `self : RuntimeEvent`, eight tokens early;
0482's `expected '{'` named a missing brace when the header was missing a separator rule. => 判据:
the reported line is a place, and three places in a row have been a place that contained a
working feature beside the broken one. Probe the neighbourhood before believing the address.

`gzip/decoder.mbt:19` carries the IDENTICAL line and is not blocked -- it is platform-gated and
outside the scanned source set, so "that file parses" could never have settled it either way.

MEASURED.

    async  parsed 403 -> 406, unreliable 122 -> 100, withheld 31 -> 25, notices 1776 -> 1783,
           actionable 0 -> 0, total 1896 -> 1883

Two files closed outright and `redirect.mbt` moved from line 156 to **229** -- it read 73 more
lines and stopped at the next construct, `pub fn &ProcessInput::close(self : &ProcessInput)`.
That is the `&Type::method` holder, which the ranking had measured at ONE file; it is now two,
which is the ranking paying off without being re-derived. `actionable` stays 0, which is the
number that says the fix did not trade a parse failure for a false positive.

Settled in `_verify/settle_0483_pkg_qualified_holder.ps1`, 9 rows / 3 controls, GATE OK:

    ACCEPT  `fn @other.Buf::m(...) = "%identity"` / `{ ... }` / `(self : @other.Buf)` / `async`
    REJECT(4059)  `pub fn @other.Buf::m(...)`   "Cannot define method for foreign type"
    REJECT(4156)  `extern "C" fn @other.Buf::m(...)`

**`pub` IS NOT PART OF THIS GRAMMAR.** The analyzer reads it anyway, which is a MISSED error in
the same direction as the `for let` and the one-line header, and it is recorded rather than
fixed because the corpus has no instance and the corpus is what this project measures with.

**THE FIX IS TWO EDITS AND ONLY ONE OF THEM WAS THE OBVIOUS ONE.** `parse_fn_signature` folds
the path into the AST name; `declared_name_at` folds the same path to HARVEST it. Fixing the
first alone is the worst outcome available -- the file PARSES, so `parsed` goes UP and a corpus
scan calls it a fix, while the harvest still carries `@other` and every resolution of
`@other.Buf::repr` misses. That is a loud failure traded for a quiet false positive.

The shape of the token is worth recording because it cost a look: `@` is INSIDE the name. The
lexer starts a name at `@`, so `@other` is ONE `TName("@other")` and the `.` is a separate
`TDot`. There is no `TAt` in the token enum at all, and an earlier reading of that enum did not
find the arm -- which would have sent the fix looking for a token that does not exist.

**A POSITIVE ROW CAN BE VACUOUS, AND THIS IS THE SHARPEST VERSION OF THAT.** The first draft
asserted that `b.repr()` on a foreign type is not reported as an undefined name. It passed. It
would have passed on a harvest that named nothing whatsoever: a method call resolves through the
type's interface table, and that table is EMPTY for a type from another package, so the
structural lens never had a candidate to report. The second draft moved the same claim into the
pipeline, which changed the LENS and not the question, and was equally vacuous. M1 and M4 both
survived both drafts.

What answers it is `collect_declared_names`, which is `pub` and returns an `IfaceSymTab`: ask the
harvest what it contains instead of inferring it from whether a finding turned up downstream.
=> 判据: a row is only as good as the mechanism that makes it red. 0470's rule was about NEGATIVE
rows -- ask whether any mutation can turn it red. This is the same failure wearing the opposite
sign: a POSITIVE row that passes because the thing it names is unreachable rather than correct,
which no pre-flight can catch and which survives until a mutation is written that disagrees with
it. The evidence that a row is vacuous is not that it is green. It is that you cannot say WHICH
thing would make it red.

**THE SCAFFOLD COST THREE DRAFTS AND EVERY ONE WAS CAUGHT BY A CONTROL, NOT BY A CLAIM.** A
fixture that needs a second package must give it its OWN `moon.pkg` -- a directory with only a
`.mbt` file in it is not a package -- and the import goes in `moon.pkg`, not in the source, and
its path is `<module>/<dir relative to source>` and NOT `<module>/src/<dir>`. Each of the three
failures reported itself in the shape of a grammar refusal: *"Cannot define method ... is
undefined"*, *"Cannot find import"*, *"Package not found in the loaded packages"*. That is the
`no work to do` lesson one level up, and it is why the header lists all three: a settle whose
controls are red is measuring its fixture.

Gate 0483: 4/4 KILLED, no declared survivors, every restore byte-identical. 990 tests. The 66-gate
release PASSED with 6/6 pins MATCH.

=> 判据: TWO READERS OF ONE GRAMMAR IS THE DEFAULT, NOT THE EXCEPTION. Reading is not harvesting,
naming is not binding, and a fix to one of a pair can leave the file BETTER off than it found it
-- parsed, counted as coverage, and wrong in the only place anyone was relying on. The corpus
number that catches this does not exist, because the number moves the right way.

## 0484 -- `fn &Trait::method`, a trait default method whose receiver is a reference

`pub fn &Data::binary(self : &Data) -> Bytes` sits at `io/data.mbt:77` and
`process/redirect.mbt:229`, and `expect_name` was called with the cursor on a `TAmp`.
`process/redirect.mbt` ARRIVED here during 0483 -- it stopped on `@fs.CreateMode::to_int` at line
156, was fixed, read 73 more lines, and stopped again on the `&` holder 73 lines later. That is the
second time a boundary line named more than one construct and only one of them was broken.

A ten-case probe against this analyzer's own parser, not inference:

    fn Data::binary(self : Data)            -> Bytes { }        first_error = 0  <- already works
    impl Data with fn binary(_)             { }                  first_error = 0  <- already works
    type Ref = &Data                                             first_error = 0  <- `&` is fine
    fn @other.Buf::repr(b : @other.Buf)     -> Int = "%identity" first_error = 0  <- 0483 control
    fn &Data::binary(self : &Data)          -> Bytes { }        first_error = 2  <- HERE
    pub fn &Data::binary(self : &Data)      -> Bytes { }        first_error = 2
    pub fn &Data::text(self : &Data)        -> String raise { } first_error = 2
    fn &Data::binary(self : &Data)          -> Bytes = "%id"     first_error = 2
    extern "C" fn &Data::binary(...)        = "x"                first_error = 2
    fn &&Data::binary(self : &&Data)        -> Bytes { }        first_error = 2

The body is IRRELEVANT and the `&` IN FRONT OF THE HOLDER is decisive. Same shape as 0483: reading
the boundary line would have built an extern-body production for a body this parser already reads.

**THE FIRST FRAMING OF THIS CONSTRUCT WAS WRONG, AND `moon check` SAID SO IN ONE LINE.** The obvious
reading of `fn &Type::method` is "a method on Type, declared through a reference". It is a TRAIT's
default method whose receiver is a reference. Both fixture drafts declared `Data` as a STRUCT and
every row came back `4100 The type Data is not a trait`, at the holder AND at the `self : &Data`
annotation. The corpus said so all along:

    io/data.mbt:23            trait Data {
    io/data.mbt:77            pub fn &Data::binary(self : &Data) -> Bytes
    process/redirect.mbt:212  trait ProcessInput {
    process/redirect.mbt:229  pub fn &ProcessInput::close(self : &ProcessInput) -> Unit

A reader that got the tokens right and the meaning wrong would have passed every corpus number,
because the number does not know what a trait is.

**THE TOKEN SHAPE IS NOT 0483's, AND GETTING IT WRONG IS SILENT.** `Lexer::run` starts a name at
`is_letter(c) || c == '@'`, so `@` glues INTO the name and `@other` is ONE `TName`. `&` is not a
name-start character at all: it falls through to `lex_op`, which maps `'&' => TAmp`. So the `&`
here is a STANDALONE token in front of an ordinary `TName`. Copying 0483's shape would have produced
a fix that compiled, passed every existing test, and changed nothing.

**TWO READERS AGAIN, AND THE QUIET ONE IS THE HARVEST.** `declared_name_after_kw` handed a `TAmp` to
`declared_name_at`, which did not match `TName` and returned `None`. Nothing goes red: the sibling
table is simply missing an entry, and the cost lands later as `undefined name 'Trait::m'` at a call
site -- ACTIONABLE, on code `moon check` compiles. M1 is the only mutation here that no corpus
number in either direction could have found.

`_verify/settle_0484_ref_holder.ps1`, 19 rows / 3 controls, GATE OK:

    ACCEPT  fn &Trait::m(self : &Trait)   with and without `pub`, with a `raise` tail
    ACCEPT  called as `d.m()` through a `&Trait`   so `m` IS a method of the trait
    ACCEPT  `= "%identity"` body, `async fn &Trait::m`, and `fn &@other.Trait::m`
    REJECT(4100)  the same declaration on a STRUCT   <- the control that makes `trait` measured
    REJECT(4032)  EVERY unqualified spelling         <- forces the `&` out of the AST name
    REJECT(4099)  `Trait::m(x)` -- a trait is not a type, so there is no by-path call form
    REJECT(4074)  `fn &&Trait::m`
    REJECT(4156)  `extern "C" fn &Trait::m`

`&` IS DROPPED FROM THE RECORDED NAME, and that is a decision with a falsification condition rather
than a convenience. Two settled facts force it: there is no `Trait::m` declaration to collide with,
and there is no `Trait::m(x)` call form either, so `m()` is the only spelling on BOTH sides and
`&Data::binary` would be a name nothing could ever look up. What identifies the TYPE stays in the
name; what describes the RECEIVER is already in `self : &Data`, which `parse_param_list` reads
either way. Falsified if either call form ever settles ACCEPT. M3 is the mutation that would do it.

`fn &@other.Trait::m` is the row with NO corpus instance anywhere: 0483 settled `@other.T::m` and
this settles `&Trait::m`, and the two are adjacent in the source but on OPPOSITE sides of the
reader's cursor -- the `&` is consumed before the name is read, the `@` lives inside the name token.
Asserted on both readers, because a disagreement between them is neither a parse error nor a finding.

**TWO OF MY OWN MUTATIONS WERE WRONG AND THE GATE REPORTED BOTH THE SAME WAY.** M3's first draft
introduced `amp_prefix` and then still built the name from `name` -- a mutation that changes nothing,
which is indistinguishable from a test that cannot fail. M5's first draft widened the `if` to a
`while` over `TAmp`, on the assumption that `&&` lexes as two of them; it lexes as ONE `TAndAnd`, so
no number of `TAmp` bumps can ever reach it.

**AND THAT SECOND ONE EXPOSED A VACUOUS GUARD ROW, WHICH IS THE 0483 LESSON POINTED THE OTHER WAY.**
The guard was `fn &&Data::deep(self : &&Data)`, carrying `&&` in TWO places. Widening the holder to
the logical-and token left the suite green -- because the PARAMETER TYPE `&&Data` fails on its own
whether or not the holder was read. The row was green for a reason that had nothing to do with what
it claimed to guard. The parameter is `Int` now, so the only `&&` in the fixture is the one the row
is about.

=> 判据: a GUARD row is vacuous in exactly the way a positive row is -- not when it is green, but
when it cannot be RED for a reason of its own. The evidence is the same question both times: which
thing, specifically, would have to change? A mutation that "survived" may be reporting a broken
mutation, a wrong lexing assumption, or a fixture that fails twice over, and those three are
distinguishable only by reading what the mutation was supposed to do.

Measured: async `parsed 406 -> 408`, `unreliable 100 -> 72`, `withheld 25 -> 25`,
`notices 1783 -> 1807`, `actionable 0 -> 0`, `total 1883 -> 1879`. Two files closed outright --
exactly the two the ranking predicted, having been made by looking at what is ON each boundary line
rather than at the scanner's grouped message tally.

Gate 0484: 5/5 KILLED, no declared survivors, every restore byte-identical. 998 tests.

## 0485 -- a BRACED STRUCT PATTERN in `is` position, and the FALSE POSITIVE the ranking missed

Three files stop on

    guard matches.values is { "cmd": [cmd], .. } else { fail("no command specified") }

at `examples/xargs/main.mbt:49`, `examples/curl/main.mbt:53` and
`examples/tcp_server_benchmark/main.mbt:98`. The boundary line named two constructs AGAIN, and the
second one was the expensive one: `is` on the next line reads fine (`first_error = 0`), and the
3-vs-2 code difference in the first probe was a CONSEQUENCE of the rest failing, not a second
defect.

Measured with first_error AND UndefinedName TOGETHER, because measuring them apart is what made
the `if` row look unaffected when its first_error had never been measured at all:

    caller        { "cmd": [cmd] }     { "cmd": [cmd], .. }
    match arm     fe=0  undef=0        fe=0  undef=0     <- ALREADY CORRECT
    guard         fe=0  undef=2        fe=2  undef=0
    bare `is`     fe=0  undef=2        fe=2  undef=0
    if            fe=2  undef=0        fe=2  undef=0
    while         fe=2  undef=0        fe=2  undef=0
    let destr     fe=2  undef=0        fe=2  undef=0

**TWO DISTINCT OUTCOMES, AND THE QUIET ONE IS WORTH MORE THAN THE THREE FILES THAT STOP.** `guard`
and a bare `is` PARSE: the leftovers happen to re-read as a BLOCK, so nothing halts, and then the
names the pattern was supposed to bind are reported undefined -- a FALSE POSITIVE on code
`moon check` compiles. It moves no parse-coverage number in either direction, which is why it had
to be found by a binding count and could not be found by the ranking.

**MECHANISM, read from source rather than inferred.** `parse_is_pattern` has branches for a `(`
tuple, a `[` array, a name head and literals -- and NO `{` BRANCH AT ALL. A brace pattern fell to
`else { return [] }`, which CONSUMES NOTHING. The match-arm path reads arms through `skip_pattern`,
a different reader that already handles `..`, which is why one caller was correct and four were
not.

`_verify/settle_0485_is_struct_pattern.ps1`, 16 rows / 4 controls, GATE OK:

    ACCEPT  guard / if / while / bare `is`, with and without `..`, one key or several,
            a plain value, a NESTED array pattern, `{ .. }` alone, `{}` alone
    REJECT(4028)  `{ cmd: [cmd], .. }` -- unquoted key on a `Json` subject
    REJECT(0011)  `let { "cmd": [cmd], .. } = x` -- `partial_match`, a `let` pattern must be
                 irrefutable. Left UNREAD on purpose; a test pins the choice.

ONE reader fixes all four callers, because all four reach `parse_is_pattern` through `parse_is`.
Measured before implementing, not after.

**WHY VALUE POSITION IS TRACKED RATHER THAN "EVERY NAME":** in `{ "cmd": [cmd] }` the key is a
STRING and cannot be mistaken for a binding, but in the unquoted spelling it is a `TName`, and
collecting it would INVENT a binding the pattern never introduces -- a false finding manufactured
out of a key, in a construct whose whole purpose is to stop manufacturing findings.

**A SETTLE THAT COULD NOT FAIL.** The first draft of this settle printed six MISMATCH rows and
still ended `GATE OK`, because the `$fail++` was dropped in a restructure. A settle that cannot
fail is worse than no settle: it reports the same verdict whether the grammar is legal or not. The
abort path now has to be exercised, not merely present.

**AND M3 FOUND A REAL GAP IN THE READER, NOT JUST A WEAK ROW.** The `TColon`/`TComma` guards
tested `depth == 1` but not `bracket == 0`, so a comma INSIDE a nested `[ a, b ]` cleared the
value flag and `{ "m": [[a, b]], .. }` bound only `a`. Nothing in six corpora writes a two-element
nested list, so no corpus number moved and only a synthetic row could see it. The guards moved to
`depth == 1 && bracket == 0` and the fixture moved to `[[a, b]]`.

=> 判据: `first_error` measures only whether the reader STOPPED. It says nothing about whether the
tree is right. A construct is handled when a BINDING survives, and for half of this defect nothing
else would ever have shown. Measure `first_error` and the finding count in the SAME run, and never
compare one against the other across different fixtures -- that is how the `if` row looked
unaffected when it had never been measured on the axis that mattered.

Measured: async `parsed 408 -> 411`, `unreliable 72 -> 65`, `notices 1807 -> 1812`,
`total 1879 -> 1877`, `actionable 0 -> 0`. Three files closed outright, exactly the three the
ranking predicted. The other FIVE corpora are UNCHANGED -- moui 4225, moonbit_labeler 791,
moonbit_image 218, proton 2131, proton_contract 34 -- which is itself the finding: a grammar this
general that moves exactly one corpus is not over-reaching.

Gate 0485: 5/5 KILLED, no declared survivors, every restore byte-identical. 1006 tests.

## 0486 -- a `+`-JOINED EFFECT clause, `-> T noraise + nocancel`

Re-ranking the async backlog by MEASUREMENT rather than by the list carried between increments
found the list had decayed: it named four files, the real backlog was EIGHT, and the two that read
ZERO lines were not among them. The ranked boundary line was wrong too -- but that turned out to
be the smaller of the two errors.

    src/internal/coroutine/async_primitive.mbt:16   async fn[T] async_suspend(cb : ...) -> T
                                                        noraise + nocancel = "%async.suspend"
    examples/http_file_server/main.mbt:24            conn <+ with the operand on the NEXT line

Construct A is this one. `parse_raise_effect` consumed `noraise` and returned, leaving
`+ nocancel` to be read as code.

*** THE CLAUSE IS NOT `noraise + nocancel`. IT IS `<any effect> + nocancel`. *** That correction
came from a mutation that SURVIVED, which is the useful kind:

    M2  accept ANY name after the `+`
        SURVIVED

M2 did not survive because the reader was wrong. It survived because the GUARD ROW was half
vacuous: it used `raise + noraise`, which the `noraise`-first test rejects BEFORE the operand's
name is ever examined. So the row pinned half the guard and was structurally unable to see the
other half. Settling what nobody had asked changed the grammar:

    ACCEPT       fn f() -> Unit noraise + nocancel { () }
    REJECT(3002) fn f() -> Unit noraise + raise { () }
    REJECT(3002) fn f() -> Unit noraise + whatever { () }
    REJECT(3002) fn f() -> Unit raise + noraise { () }
    ACCEPT       fn f() -> Unit raise + nocancel { () }      <- NOT READ. A missing construct.
    REJECT(4074) fn f() noraise + nocancel { () }           -- the clause needs an annotation

`_verify/settle_0486_append_nextline_and_effects.ps1`, 16 rows / 5 controls, GATE OK.

`raise + nocancel` is recorded as gate 0486's DECLARED SURVIVOR rather than quietly retrofitted
onto this gate: it is a different shape of clause, and half-implementing it on the back of a
mutation gate is how the two drift. It is the next increment, with its own settle rows.

One fix covers THREE call sites (parser.mbt:1633, :2127, :5875) -- a signature, a function type and
a parameter position all route here, so there is one grammar and one reader.

Measured: async `parsed 411 -> 413`, `unreliable 65 -> 41`, `withheld 25 -> 17`,
`notices 1812 -> 1821`, `total 1877 -> 1862`, `actionable 0 -> 0`. TWO files closed, not one --
`internal/coroutine/coroutine.mbt` and `async_primitive.mbt` -- which is the third time the
carried list named the right construct and under-counted the sites.

=> 判据: A ROW CAN BE HALF VACUOUS. `raise + noraise` is rejected by a guard one step EARLIER than
the one the row was written to check, so the row passes without ever exercising the thing it
names. The evidence is the same question as everywhere else -- which thing, specifically, would
make it red -- and "which half" is part of the answer.

*** COLLATERAL: gate 0466's M1 and M4 anchors, broken and re-anchored. ***

The first 69-gate release FAILED on `mutate:0466` with PREFLIGHT MISS on exactly two mutations.
0486-A had put its explanatory comment block INSIDE the arm, between the `if` and the `bump`:

    0486-A shape                    what 0466 M1/M4 `Find`
    if ... at_name("noraise") ... {   if ... at_name("noraise") ... {
      // 19 lines of comment    <--     let _ = self.bump()
      let was_noraise = ...          return
      let _ = self.bump()         }
      return
    }

Both anchors `Find` that block as ONE string, so inserting a line between the `if` and the
`bump` made the string vanish. Same class as 0484's gate 0418 collateral, and it cost a second
full release cycle.

The fix is not a re-anchor in the narrow sense -- it is moving the comment ABOVE the `if`, so
the arm is contiguous and comment-free:

    // 0486 A `+`-JOINED EFFECT ... (the whole note, above the `if`)
    if ... at_name("noraise") ... {
      let was_noraise = ...
      let _ = self.bump()
      ...

Re-anchored afterwards: 0466 M1 spans the whole current arm, M4 spans `if` / `was_noraise` /
`bump`. 0466 is GATE OK again, 3 KILLED / 3 declared survivors, and its M1 kill count rose
from 6 to 10 red tests because the arm it deletes is now the 0486 clause as well.

=> 判据: AN ANCHOR IS WRITTEN AGAINST A CODE SHAPE, AND A COMMENT IS PART OF THAT SHAPE. The
question to ask before inserting an explanatory block between two pinned-adjacent lines is not
"does this comment belong here logically" but "does it belong between these two lines". When it
does not have to, it goes above the region. A gate that reports PREFLIGHT MISS is telling the
truth about the shape, not about the logic.

Gate 0486: 3 KILLED, 1 declared survivor with a Prove, every restore byte-identical. 1013 tests.
(That survivor is RETIRED by 0487 below -- not because it was wrong, but because it turned out to
be observable.)

## 0487 -- the WHOLE `+`-joined effect clause, and a survivor that turned out to be observable

0486 shipped ONE spelling and declared `raise + nocancel` a survivor with a Prove: *"no legal
MoonBit pair starts with a bare `nocancel`"*. That is the sentence that had to die.

`_verify/settle_0487_combined_effect_order.ps1`, 21 rows / 6 controls, GATE OK:

    ACCEPT    -> T noraise + nocancel        <- 0486's spelling
    ACCEPT    -> T raise + nocancel          <- 0486's declared survivor
    ACCEPT    -> T raise MyErr + nocancel
    ACCEPT    -> T nocancel + noraise        <- 0486 REFUSED THIS LEGAL PROGRAM
    ACCEPT    -> T nocancel + raise
    ACCEPT    -> T nocancel + raise MyErr

    REJECT 3002  -> T ! + nocancel
    REJECT 3002  -> T noraise + raise MyErr
    REJECT 3002  -> T raise MyErr + raise MyErr2
    REJECT 3002  -> T noraise + nocancel + noraise    <- exactly two, never a chain
    REJECT 4074  fn f() noraise + nocancel { () }     <- still needs an annotation

=> THE GRAMMAR IS: EXACTLY TWO EFFECTS, EXACTLY ONE OF WHICH IS `nocancel`, THE OTHER BEING
`noraise` OR `raise [E]`, IN EITHER ORDER.

So 0486 was not merely incomplete, it was **refusing programs the toolchain accepts**. `mutate_0487`
M3 is 0486's M4 -- the `was_noraise` test, forced false -- and it is now **KILLED** by
`0487: nocancel + noraise reads`. 0486's M4 is `Retired`, with the reason recorded, rather than
re-anchored: a retired row is not a weaker claim here, it is a claim that has been SUPERSEDED by a
stronger pin, exactly as 0458's M4 was.

*** THE ORDER IS A RULE AND THE ARITY BELONGS TO THE ORDER, NOT TO THE WORD. *** `noraise + raise
MyErr` is REJECT 3002 and `nocancel + raise MyErr` is ACCEPT, differing by one token. Both failure
directions are SILENT: reading an illegal program removes no blocker from any corpus, and skipping
a legal error type parses it as code.

`left_was_nocancel && right == "raise"` therefore had a conjunct that turned out to be REDUNDANT --
`joins` can only be true with `right == "raise"` when the left operand was `nocancel`, because the
else branch admits `"nocancel"` and nothing else. It is gone, the order is enforced in one place,
and the reason is recorded in the source rather than tidied away.

`0487: the error type belongs to the order, not the word` asserts the UNTYPED and the TYPED form
together, and that pairing is load-bearing: the typed assertion alone PASSES on a reader whose
arity is wrong and whose join is right, because the `MyErr` is never reached. Only the untyped one
catches the join being widened. That was found by a mutation reporting `KILLED` with no
`[named test confirmed]` -- a green kill that was green for the wrong reason.

**MEASURED: NOT ONE PIN MOVED.** All six corpora are byte-identical to 0486 -- moui 4225, labeler
791, image 218, async 1821/41/17, proton 2131, contract 34. Five of the six were already fully
parsed and could not move; async has 6 files still unread and none of them is blocked on this
clause.

That is the finding, and it is the third time the same thing has shown up: **a correctness defect
can be real, measured, and invisible to every number this repository pins.** Nothing in any pinned
corpus writes `nocancel + <effect>`. So the instrument here is the settle and the rows -- a corpus
would have reported this increment as a no-op, and correctly so.

Gate 0487: 7 KILLED, 0 declared survivors, every restore byte-identical. Gate 0486: 3 KILLED, 1
RETIRED (superseded by 0487 M3). Gate 0466: 3 KILLED / 3 declared survivors, re-anchored. 1024 tests.

## 0488 -- `<+` across a newline, the `$|...` template string, and a false positive the inventory had been hiding

The backlog was re-derived from the scanner rather than taken from the list carried between
increments, because that list has been wrong three separate ways. Every unread file's BOUNDARY LINE
was read directly:

    src/http/utils.mbt:23                    for-header with a NON-EMPTY update clause
    examples/http_file_server/main.mbt:24     `conn <+` , operand NEXT line      <- read ZERO
    src/http/request.mbt:59                  `host =~ (re"^" + ...)`, regex literals
    src/fs/watch_kqueue.mbt:240               `let { identity, .. } = ...`
    src/socket/addr_utils.mbt:297             `logger <+` , operand NEXT line
    src/fs/watch_windows.mbt:320              `>..` range, `break path[:i]`

Ranked by measured REACH rather than depth, `<+` wins: **TWO** files, one of them reading zero lines.
And `addr_utils.mbt:297` is a SECOND SITE for the same construct that the carried list never named --
the same "named the construct, under-counted the sites" failure as 0486, on that settle's other half.

*** THREE DEFECTS THAT LOOK LIKE ONE CONSTRUCT IN THE SOURCE. *** `settle_0488_append_nextline.ps1`,
20 rows / 4 controls, GATE OK.

    ACCEPT   sb <+ NEWLINE "x"           REJECT 4139  a NEWLINE + b   /  - b  /  * b  /  == b
    ACCEPT   let x = $|<a>  /  a + $|<b> REJECT 3002  let x = $| NEWLINE <a> NEWLINE $|</a>
    ACCEPT   sb <+ $|<h1>\{name}</h1>

    A. `newline_suppressed_after` did not list `TAppendPlus`. ONE LINE.
    B. `$|...` had NO lexer production at all -- the `$` fell to lex_op's catch-all. It is a GENERAL
       expression, not a slot only `<+` can fill, which is why the fix belongs in the expression
       grammar rather than in `parse_pipe`.
    C. `copy_interp` flushed a LABEL as a name READ.

=> THE BREAK IS LEGAL *AFTER* THE OPERATOR AND NOT BEFORE IT. The obvious "be helpful" fix is a
general rule letting expressions continue across line breaks. That would accept four programs the
toolchain REJECTs. Suppression looks only at the PRECEDING token, so listing `TAppendPlus` grants
`sb <+` NEWLINE `"x"` and leaves `a` NEWLINE `+ b` refused. mutate_0488 M2 pins that narrowness by
swapping `TStar` in for `TAppendPlus`.

*** READING A FILE FOR THE FIRST TIME IS A FALSE-POSITIVE DISCOVERY EVENT. *** `addr_utils.mbt` used
to stop at line 297, and findings on a PARTIAL file are WITHHELD rather than reported -- so the
inventory said `actionable=0` while a defect sat inside the file. The moment the append fix let it be
read whole, `no visible binding for 'radix'` appeared at `addr_utils.mbt:291`, and async went 0 -> 1
actionable on an increment whose stated job was to add no findings at all.

It is a false positive: `value.to_string(radix=16)` supplies 16 to the parameter named `radix`, which
is MoonBit's labelled-argument call syntax -- the counterpart of the `protocol~ : Protocol`
declaration this same corpus writes at `http/request.mbt:56`. `copy_interp` had no notion of a label,
so it recorded one as a READ. Fixed in this increment rather than the next, because pinning
`actionable=1` would have asserted the finding correct. The carve-out is settled, not guessed:
`==` and `=>` are still reads (rows F3/F4, both ACCEPT).

*** TWO ROWS I WROTE WERE WRONG AND ARE NOT IN THE TREE. *** `"a" NEWLINE `"+ b"` asserted
`first_error > 0`; it is 0 and that is CORRECT -- `first_error` measures whether the reader STOPPED,
and `+ b` is a second statement, so nothing fails to parse. The toolchain rejects the program too,
but with 4139 "its value cannot be implicitly ignored", a TYPE error at `a`. There is no
`first_error` observable for a token-stream question, so M1/M2 pin it by mutating the SET.

*** AND A POSITIVE CONTROL TOOK TWO ATTEMPTS, BOTH WRONG IN AN INSTRUCTIVE WAY. *** M6 treats every
`=` as a label. It SURVIVED against `\{a == b}` -- because `b` is still read -- and then against
`\{a == 1}` -- because the SPACE flushed `a` before the `=` arrived. Only the UNSPACED `\{a==1}`
leaves the identifier pending when the operator comes, which is exactly the shape the defect lives
in. Spacing is not cosmetic: it decides whether the identifier reaches the guard under test at all.

*** TWO GATE RUNS HUNG, AND BOTH WERE MY MUTATIONS, NOT THE READER. *** M3 replaced `break` with
`continue` where the cursor step sits BELOW the branch; M4 deleted only the body of the dispatch
branch, leaving a bare `continue`. `run()` advances `pos` inside each branch's lexer call, so neither
mutation ever moved it. A hung mutation produces no `Total tests:` line and is indistinguishable
from a slow one, and the harness does NOT restore the file when a run is killed.

Gate 0488: 6 KILLED, 0 declared survivors, every restore byte-identical. 1032 tests.

=> 判据: A MUTATION'S `Repl` IS A PROGRAM, NOT A DELETION. What it compiles to has to TERMINATE, and
the two shapes to check first are `break` -> `continue` inside a cursor loop and a branch reduced to
a bare `continue`. Before killing a gate that has run long past its siblings, work out WHY it is slow
-- and after killing one, read the mutated region back. `git diff --stat` will not tell you: the
mutation had replaced five lines with three and the file still read as clean.

=> 判据: THE SAME ARM WAS RE-ANCHORED IN THREE GATES ACROSS TWO INCREMENTS, AND THE SECOND TIME
IT WAS NOT MY FAULT. `parse_raise_effect`'s `noraise` / `nocancel` arm is a SHARED INTERFACE: gate
0466 pins the effect SLOT, 0486 and 0487 pin the JOIN inside it, and each pins a contiguous SHAPE.
So an edit there is never local -- it is a coordinated change across gates, and the two that break
are always 0466's M1 and M4 because they are the two that SPAN the arm. Both times the symptom was
PREFLIGHT MISS on exactly those two while 67 other gates passed, which reads like a one-gate flake
and is not one. Budget the re-anchor, and prefer changes that leave the arm's line count and order
alone.

*** AND GATE 0423 IS THE MORE DANGEROUS VERSION OF THE SAME THING, SO IT IS WORTH ITS OWN NOTE. ***
`eat_joined_effect` introduced a SECOND `type_head` guard with the same four lines as the one in
`parse_raise_effect`. 0423's M6 anchored the type read followed IMMEDIATELY by the closing `}` --
that adjacency died when `eat_joined_effect(false)` was added after the type, and M6 PREFLIGHT-MISSED.
Loud, and therefore harmless.

M7 and M8 anchored the guard's four lines alone. Those did not MISS -- they became AMBIGUOUS, which
the harness only WARNS about, because it removes the FIRST match and that match had just moved
into the new helper. So M7 and M8 would have reported clean kills for mutations applied to the
WRONG SITE: green, meaningless, and invisible in every number this repository pins. `if
!type_head` is what distinguishes the two guards (`if type_head` in the helper), and including it
makes both anchors unique again. 0423 is GATE OK, 9/9 KILLED, no ambiguity warning.

=> 判据: A PREFLIGHT MISS IS THE LUckY OUTCOME. An anchor that STOPS MATCHING aborts the gate and
tells you. An anchor that starts matching TWICE is warned about and then used anyway, on whichever
site comes first -- so when a change introduces a second copy of a shape, the question is not "did
my anchors survive" but "did any of them become AMBIGUOUS, and does the first match still point at
the code I meant". `grep` the whole `_verify` tree for every shape you duplicated before
believing a green gate.


*** AND THE RELEASE GATE FAILED ON THE GRAMMAR-PROBE CONTROL, AND THE FAILURE WAS IN THE
CONTROL'S OWN PLANTED-ROW DERIVATION. ***

The 0488 release run stopped at `grammar-probe-control`. The control's planted row is not
hand-written: it is DERIVED at run time from a file in the pinned corpora that this frontend
genuinely cannot read, because the row has been moved four times as increments closed it. The
derivation returned NOTHING, and its log was:

    async     PARTIAL files = 4
    async     skip file   MOON-BAD    src/http/utils.mbt:23

ONE skip line for FOUR files. The other three were dropped by a `continue` that carried no log
line, so the log read like "one file was tried" when in fact three had vanished without a trace.
That is the same defect the control exists to catch, wearing the control's own clothes: a search
that stops looking and leaves no mark.

AND THE ONE THAT WAS TRIED FAILED FOR A REASON THE OLD METHOD COULD NOT SEE. The whole file
mentions `BadRequest`, which is defined in a SIBLING file of the same package, so the file is not
a legal standalone program and `moon check` rejects it. The file-level candidate was rejected for
a reason that has nothing to do with the gap inside it -- the unreadable for-header with a
non-empty update clause, at `src/http/utils.mbt:23`, inside `fn encode_int`.

THE METHOD IS NOW A DESCENT, NOT A CHOICE. The old code PICKED one granularity by a textual test
(`import` or `@pkg`? take the item, else take the file) and never tried the other. The new code
walks the units that CONTAIN the blocker and tries each on its own merits: the whole file, the
enclosing top-level item, a definition NESTED inside that item lifted to column 0, then the other
top-level items -- after the blocker first, because a PARTIAL file means the reader STOPPED there
and everything past it is an UNVERIFIED region that may still hold a gap once the enclosing item
is fixed.

=> MEASURED YIELD PER LAYER, on all 107 candidates in the four unreadable `async` files, every
one scored MOON-OK AND SELF-FAIL:

    file  --  0 usable of   4
    item  --  1 usable of  56      src/http/utils.mbt:16-31, fn encode_int
    sub   --  0 usable of  47

So the layer that pays is the ENCLOSING ITEM, and the reason is the same in every file: the
unreadable construct lives in an item that happens to be self-contained, inside a file that is
not. The `sub` layer -- "plant from a self-contained sub-item even when the enclosing item is
not" -- is implemented because it is the only layer that can find a gap in an item that references
an external package, and it contributes nothing today. That is a MEASUREMENT, not an assumption:
a nested definition lifted to column 0 refers to the enclosing item's locals, so it is never a
legal standalone program on its own.

=> 判据: A CANDIDATE IS REJECTED ON ITS OWN MERITS, AND EVERY REJECTION IS LOGGED. A skip that
prints nothing is indistinguishable from a candidate that was never generated. The log now
carries one line per candidate with its reason (HAS-AT / HAS-IMPORT / MOON-BAD / SELF-OK), and
the 0488 run's own log is the proof that this was needed: it showed 14 candidates where the
failing run had shown 1.

AND A LATENT WRONG-UNIT BUG CAME OUT OF THE SAME MEASUREMENT. The item-opener pattern did not
match `async fn`, so `pub async fn request(` at `async 0.22.4 src/http/request.mbt:84` was not
recognised as an item opener at all. The item enclosing the blocker at line 59 was therefore
computed as lines 55-212 -- everything to the end of the file -- instead of 55-72. It changed
nothing today, because `resolve_host` mentions `@string` either way, but an item extent that runs
to the end of the file is exactly the kind of unit whose "@-test" ends up answering a question
nobody asked.

THE CONTROL'S FIVE ASSERTIONS ARE UNCHANGED. Same five checks, same strings, and the
`-SimulateExhaustion` branch still FAILS with exit 1, which is the honest endpoint: when the
derivation finds nothing, the control says so rather than falling back to a hardcoded row. The
planted row is now `async:src/http/utils.mbt:23`, unit `fn encode_int` -- real corpus code, and
the construct in it is the for-header with a non-empty update clause, which is one of the four
gaps left in the backlog.


## 0489: the BEHAVIORAL LENS ENTERS AT EACH FUNCTION, and it turns out it was WRONG

(NO VERSION PREFIX, and the reason is that the prefix was already taken: this file's counter reached
`0.4.39` at 0450 and was dropped there, so every section from 0468 on is headed by its increment
number alone. A `0.4.30, 0489:` header would have been a SECOND `0.4.30` in one file -- `0.4.30,
0440:` is already there -- and a version label that means two different increments. The package
version and this file's counter are not the same number either: the package is at `0.4.29`.)


DIRECTION 2, AND THE QUESTION IT ASKED WAS "IS THE LENS OBSERVABLE AT ALL -- AND IF IT IS, WHAT
DOES IT SAY?" The answer is: it was not observable, and once it was, it said several things that
were wrong.

THE LENS NEVER EXECUTED A FUNCTION BODY. `Interp::run_top` SKIPS `SFunc` items:

    for s in m.body {
      match s.kind {
        SFunc(_, _, _, _, _) => ()
        _ => { ...exec_stmt(s, self.globals)... }
      }
    }

so a body ran only if something CALLED it from a top-level statement. A library module does not
call its own functions at top level, so on every pinned corpus the lens executed ZERO bodies:

    moui             4152 findings, ALL tagged `structural`
    proton           1062 findings, ALL tagged `structural`
    async            1820 findings, ALL tagged `structural`

not one tagged `behavior`. MEASURED, the gap was the ENTRY and nothing else -- the same defect, in
the same body, three ways:

    top     -- a top-level statement        -> [type+behavior]
    incall  -- in a function CALLED at top  -> [type+behavior]
    uncall  -- in a function NEVER called   -> [type]      <- behavior GONE

for every defect kind tried. `Unreachable` is the family the tests pin with, because it is the
one NO OTHER LENS SEES: the structural and type lenses both walk the body and find nothing there,
so a merged report carrying `behavior` is unambiguous evidence that the behavioral lens -- and
only it -- executed the body.

THE NEW ENTRY. `Interp::analyze_functions` binds each parameter to a fresh abstract value of its
DECLARED type and executes the body. `Interp::setup_interp` is now SHARED by the two entries, so
they cannot drift about which names exist; `PipelineResult::run_functions` is the pipeline-level
door, and the scanner reaches it with `--per-function`.

THE DECLARED TYPE IS THE ONLY SOUND CHOICE FOR AN ENTRY POINT: the parameter's runtime value is
unknown, so the lens must assume the declared type and nothing more. An UNANNOTATED parameter
becomes `AAny`, which every operation accepts -- an unannotated parameter must not manufacture a
finding, and there is a row for that, with its opposite (a declared `Int` used as a condition IS
a defect) as the control.

*** AND THE ENTRY UNCOVERED FOUR LATENT DEFECTS IN THE LENS, WHICH IS THE PART THAT WAS WORTH
THE INCREMENT. *** Each is a case where the lens INVENTED a finding the other two lenses
contradicted -- the shape this lens has been corrected for before.

  M2  AN ENUM CONSTRUCTOR was `undefined variable`. The lens never received
      `ParseResult::enum_ctors` -- the list the structural and type lenses BOTH get. MEASURED on
      the first corpus the entry touched: `proton_contract 0.3.4 contract.mbt:261`,
      `ContractRoute::{ scope: Application, name, }` -> `undefined variable 'Application'`, an
      ERROR, on code `moon check` accepts. `Application` is a constructor of the `ContractScope`
      enum, whose BRACED body this frontend SKIPS -- so the name arrives in `enum_ctors` and the
      lens simply never asked.
  M3  A QUALIFIED CONSTRUCTOR (`PixelFormat::RGBA8`) was `undefined variable`. The STRUCTURAL
      lens has the TAIL rule -- `walk.mbt`: "a qualified path whose TAIL is bound is a real name:
      `Layer::ReLU` is a unit enum variant, and the harvest binds `ReLU` but not the whole path" --
      and this lens had none. 200+ of these on moui alone.
  M4  A CALL TO A FUNCTION-TYPED PARAMETER was `undefined function`. `Interp::call` dispatched
      only through the top-level method table and never consulted the frame the parameter is
      bound in, so `cb()` on a `cb : () -> Unit` parameter was an ERROR.
  M5  and the fresh value IGNORED the declared type, which is M5 in the gate.

MEASURED, THE FALSE POSITIVES FELL FROM 629 TO 265 ON moui, and the remaining classes are
different ones: a `#cfg` duplicate-name method table (the walk fixed this in 0441 and the
interp's table is still keyed by name), a `Unit`/`None` conflation, and arity mismatches.

=> 判据: A BLANKET RULE IS NOT A RULE. The first attempt at M3 was "any qualified name is
unresolvable, so stay silent" -- and it broke ELEVEN pinned tests, including `Array::mkae` (a
builtin type with a method that does not exist) and `ZzMissing::nope` (an unknown head), which the
repository pins ON PURPOSE. The precise rule is the TAIL rule the structural lens already uses,
and it leaves both of those reported because the tail of each is not bound. Every blanket rule
this lens has ever grown was one of these: `StringBuilder()`, `Int::max`, `Builder()` -- each one
a table, never a shape.

=> 判据: THE ENTRY AND THE DEFECT ARE SEPARATE, AND THE ENTRY IS WHAT MAKES THE DEFECT VISIBLE.
Every one of the four defects above was in the lens, not in the entry, and every one of them was
invisible because the lens never ran. The same is recorded at 0.4.16 -> 0.4.17, where a rule
about qualified builtin calls was reverted as "unobservable" -- and the reason it was
unobservable was THIS: the probe copied a function DEFINITION without ever calling it, so
nothing ran. The 0.4.17 comment says so in as many words, and the fix was to restore the CALL.
The per-function entry is the general form of that fix.

MEASURED, AND THE DEFAULT VIEW DID NOT MOVE: the module entry's numbers are byte-identical to the
0488 pins on all six corpora -- moui 4225, labeler 791, image 218, async 1829/23/0/1852, proton
2131, contract 34. The per-function view is a SEPARATE, OPT-IN view (`--per-function`), so the
pins measure what they measured.

  corpus             module view (the pins)          per-function view
  moui             actionable 0, notices 4225          actionable 265, notices 4225
  moonbit_labeler  actionable 0, notices  791          actionable  95, notices  791
  moonbit_image    actionable 0, notices  218          actionable  94, notices  218
  async            actionable 0, notices 1829          actionable 279, notices 1829
  proton           actionable 0, notices 2131          actionable 136, notices 2131
  proton_contract  actionable 0, notices   34          actionable   0, notices   34

THE PER-FUNCTION VIEW IS NOT YET SOUND, and the counts above are the reason it is opt-in. 265
actionable on a corpus `moon check` accepts is not a finding rate, it is an inventory of what is
still wrong with the lens. The remaining classes are named in the source and the next increment
has them.

GATE 0489: 6 KILLED, 0 declared survivors, every restore byte-identical. 1042 tests.


## 0490: FIVE LENS DEFECTS THE PER-FUNCTION VIEW MADE VISIBLE, AND A RENAME THE TOOLCHAIN DID

0489 shipped the per-function entry and left the view reporting 265 actionable findings on moui
0.1.12 where the module view reports 0. That 265 was never 265 defects in the analysed code. It
was an INVENTORY of what was still wrong with the BEHAVIORAL LENS, and this increment is the
measurement of five of those classes -- each one a defect the lens INVENTED, on code `moon check`
accepts, and each one with a minimal repro fixture that stands on its own.

THE INVENTORY WAS TAKEN BEFORE ANY FIX, by grouping the actionable findings by family and by
message, and the groups were the diagnosis: a group of ~20 rows that all said "no method matching
<fn>(List, ...)", a group that said "no method matching <fn>(Any, Any, Any)" against functions that
declare seven parameters, and a group that said "no method matching +/</>=(None, ...)".

  M1  A LIST VALUE AGAINST A LIST PARAMETER. The TYPE lens writes a list type as `[int]`
      (`ty_name`); the BEHAVIORAL lens writes a list VALUE as `List` (`abs_of`); and `vmatches`
      compares a value name against a type name. So "List" was NEVER equal to "[int]", and every
      call passing a list was reported `no method matching take(List)`.
  M2/M3  THE ARITY RULE. The check compared the argument count against the DECLARED count, so a
      call that omitted an omittable parameter was reported. Measured on moui: `control_state`
      declares SEVEN parameters (`foreground~`, `background~`, and five `?` ones) and is called
      with THREE arguments throughout the corpus -- eleven sites, every one reported.
  M4  A FUNCTION WHOSE BODY IS AN `if` RETURNED "None". The `SIf` arm ran the branch, and the
      branch's trailing expression was an `SExpr`, whose value the `SExpr` arm DISCARDED. So
      `ret_vals` stayed empty, `join_vals([])` answered "None", and every operator applied to that
      result was reported `no method matching +(None, int)`. `clamp_double` is an `if` body, and
      every call site of it inherited the "None".
  M5  A STRING CONCATENATION WAS THE TYPE "int". `bin_widen` had arms for `float`, for `Any`, and
      the `int` fallback -- and none for two strings, so `"a" + "b"` evaluated to "int". The
      consequence was a false positive on the OUTER `+`: `("a" + "b") + "c"` has an "int" left
      operand and a "str" right one, and the operator check reported `no method matching
      +(int, str)`. Measured on moui `render/common/provider_shell.mbt:10`.
  M6  A STRING COMPARISON WAS A METHOD ERROR. The comparison operators accepted only
      `numeric(l) && numeric(r)`, and `<=` on two Strings is legal MoonBit.

THE OMITTABLE SPELLINGS ARE TWO, AND BOTH ARE SETTLED AGAINST THE TOOLCHAIN (`moon check`
0.1.20261012, and RE-SETTLED on 0.1.20261016 -- see the toolchain-upgrade section below), not
inferred:

    ACCEPT   `fn opt(x : Int, y? : Int)` called as `opt(1)`
    ACCEPT   `fn labelled_default(x : Int, y~ : Int = 0)` called as `labelled_default(1)`
    REJECT 4080   `required()` against `fn required(x : Int)` -- omitting a REQUIRED parameter
    REJECT 3010   `fn f(y : Int = 0)` -- "Only labelled arguments can have default value", so the
                  default spelling is only legal on a `~`

The third row is the one that makes the rule a RANGE and not a blanket: `declared - omittable
<= arguments <= declared`. The floor is the REQUIRED count and the ceiling is the DECLARED count,
and a rule with either half missing is wrong in a different direction. M2 and M3 are the two
mutations that remove them, and each is killed by a CONTROL row rather than by a positive one.

MEASURED, the per-function view, before and after:

    corpus             0489                    0490
    moui             actionable 265      ->    actionable  58
    proton           actionable 136      ->    actionable  92
    moonbit_image    actionable  94      ->    actionable  68
    moonbit_labeler  actionable  95      ->    actionable  48

AND THE PINS DID NOT MOVE. The module view's numbers are byte-identical to the 0488 pins on all
six corpora -- moui 4225, labeler 791, image 218, async 1829/23/0/1852, proton 2131, contract 34
-- because every fix above is in the BEHAVIORAL lens and the module entry does not execute a
function body. That is the property the 0489 split was built for, and this increment is the
first thing that has exercised it: a change of this size in the lens, and the pinned numbers did
not move.

WHAT IS LEFT, and it is ONE class now rather than five. On moui, 35 of the remaining 58 are
`undefined variable 'Constant'` -- an enum VARIANT of `DeclarationChannel` used in a SIBLING file
of the same package -- and the rest are the same shape: `MoveEnd`, `MoveStart`, `Up`,
`FIM_HEADER_BYTES`, `QOI_OP_RGB`, `Rect`, `proton_err_buffer_too_small`. These are the SAME-PACKAGE
CROSS-FILE resolution gap, and the per-file `enum_ctors` limitation that the repository has
recorded since 0432. The behavioral lens is single-file, exactly as the other two lenses are, and a
library package is where that shows.

AND A COLLATERAL DEFECT, and it is one 0489 SHIPPED: the four `pkg.generated.mbti` files were
STALE. 0489 changed the public signature of `analyze_module` and `analyzed_sigs` (they take the
`enum_ctors` list now) and of `scan` (it takes the `per_function` flag), and added
`analyze_functions` and `run_functions` -- and did not regenerate the interface files that
DECLARE those signatures. `src/interp/pkg.generated.mbti` still said `analyze_module(...,
@core.IfaceSymTab)` with five parameters, and `src/sa/pkg.generated.mbti` still said `scan(String,
Array[String], Array[String], Bool, String)`. The header of each file says "Generated using
`moon info`, DON'T EDIT IT", and the repository's own history shows them being regenerated with
the source (0468 and 0469 each touched `src/ast/pkg.generated.mbti`). So the published interface
of four packages did not match their own source.

The cost of the staleness is small but the class is not: the scanner reads a `.mbti` for the
NAMES it declares, and a package whose interface is stale is a package that describes itself
wrongly to every consumer. Regenerated with `moon info` in `src/ast`, `src/interp`, `src/pipeline`
and `src/sa`.

GATE 0490 (the five lens defects): 7 KILLED, 0 declared survivors, every restore byte-identical. 1055 tests.

=> 判据: TWO LENSES SPELL THE SAME THING DIFFERENTLY, AND A COMPARISON BETWEEN THEM IS A
COMPARISON BETWEEN VOCABULARIES. `vmatches` compares a VALUE name against a TYPE name, and the
two lenses do not share a spelling for a list: `[int]` on one side, `List` on the other. The
defect was invisible because a list against a list is a MATCH in every language the lens speaks,
so the mismatch could only ever be found by a call. The fix is not a third spelling -- it is the
one place that has to know about both (`is_list_name`), and the element type is deliberately not
compared, because this lens models no list element types at all.

=> 判据: A LENS THAT HAS NEVER RUN IS NOT A LENS, IT IS A HYPOTHESIS. Four of these five defects
(`bin_widen`'s missing string arm, the comparison arm, the `if` value, the arity rule) were in
place since before the behavioral lens existed, and the corpus never showed them because the
module entry does not execute a function body. The per-function entry did not find them by being
smarter -- it found them by RUNNING, and every one of them is a false positive on code the
toolchain accepts. An instrument that has never been exercised is not an instrument.

=> 判据: A MEASUREMENT NEEDS A CONTROL, OR IT IS A NUMBER. "The list rule is gone" and "the list
rule was replaced by a blanket that silences every call whose parameter is a list" are the same
observation. Every row in `pipeline_0490_test.mbt` is paired with one that must STILL report: a
non-list value against a list parameter, a call that omits a REQUIRED parameter, a call that
passes too MANY arguments, a function whose body's last statement is a `let` (which returns
UNIT, and using that as a number IS an error), an `Int` added to a `String`, and an `Int`
compared with a `String`.

THE RELEASE GATE THEN FOUND THREE ANCHORS THAT 0490 HAD MADE STALE, and it found them LOUDLY
rather than silently -- which is the only reason the next paragraph exists at all.

    GATE FAILED: 0.4.25 mutation gate   PREFLIGHT MISS: M7 exec_alt missing else stops falling
    GATE FAILED: 0.4.26 mutation gate   PREFLIGHT MISS: M1 the tail value is not recorded
                                        PREFLIGHT MISS: M2 the tail pushes Bottom instead of the value
    GATE FAILED: 0431                   PREFLIGHT MISS: M4 an ORDINARY default value is not consumed

All three are the same shape, and the shape is the thing worth recording: 0490 changed the CODE
AROUND a decision, not the decision.

  0.4.25 M7  `exec_alt`'s unknown-condition arm grew two lines, because 0490 gave the else-if
              chain a VALUE (`val = vjoin(val, self.last_value)`) and published it
              (`self.last_value = val`). The decision under test -- `None => falls = true` -- is
              unchanged.
  0.4.26 M1/M2  the `STail` arm became a three-line block, because 0490 gave the interpreter a
              `last_value` and the tail's value now has TWO homes. The decision under test --
              "is the tail's value recorded, and is it the value that is pushed?" -- is unchanged.
  0431 M4  the pushed `Param` grew a field (`omittable`), so the anchor's LAST line stopped
              matching. The decision under test -- `ignore(self.parse_expr())` on the ordinary
              default path -- is unchanged.

A PREFLIGHT MISS IS THE LUCKY OUT. The harness had three ways to answer an anchor that no longer
matches: abort loudly (what it did), mutate the FIRST of several matches (what it would have
done with a short anchor that happened to occur twice), or retire the row. All three of these
anchors were ABSENT rather than AMBIGUOUS -- the pre-flight counts occurrences and reports the
two cases separately -- so the abort was the only thing that could happen. What the abort bought is
the time to notice that the decision under test had not moved. The alternative, a short anchor
that silently matched a different site, would have reported a clean kill for a question nobody
asked.

THE REPAIR IS A RE-ANCHOR, NOT A RETIREMENT, and the difference is worth spelling out because the
repository has already made this repair twice: 0449 re-anchored 0.4.26 M7 after a line was
inserted between two adjacent lines, and 0468 re-pointed 0.4.26 M3/M4 after a RENAME. A
retirement deletes a question; a re-anchor re-points the question at the same decision in the new
shape. What must NOT happen is the third option: inventing an anchor that merely MATCHES --
pointing M7 at some other `match els` because it also happens to contain the word `falls` -- and
that is how a gate ends up green while meaning nothing.

MEASURED, the three re-anchored gates, standalone, on the same tree:

    0.4.25   8 KILLED, 0 survivors   (M7 among them)
    0.4.26   7 KILLED, 0 survivors   (M1 and M2 among them)
    0431     3 KILLED, 1 declared survivor with its proof   (M4 among them)

Every restore byte-identical, every baseline green.

=> 判据: A PREFLIGHT MISS ASKS "DID THE CODE CHANGE SHAPE?" BEFORE IT ASKS "DID THE TEXT CHANGE?".
Get that order wrong and a RENAME looks like a DELETION -- which is exactly what `mutate_lib.ps1`'s
literal `IndexOf` matching did to 0443's M4 in 0467, where a DEDENT was indistinguishable from a
deletion. The text moved here and the code did not, and the honest repair is the one that KEEPS
ASKING: a re-anchor, and the prose in the gate script saying WHICH decision it still asks.

THE TOOLCHAIN WAS UPGRADED IN THE MIDDLE OF THE RELEASE GATE, and it is the second thing the gate
found, and the more interesting one.

The second run of the 73-gate release gate failed THIRTY gates -- 0459 through 0487 -- and every
one of them failed the same way, at one second each, with a message that was not about the code at
all:

    GATE FAILED: 0465
      ABORT: baseline did not run (no `Total tests:` line). The suite does not compile.
        what moon test actually printed:
          | moon.exe : Error: Failed to resolve the module dependency graph
          | Caused by:
          |     Cannot inject the standard library `moonbitlang/core`: Cannot load the core file

and, in another of them:

    Error: Sys_error("C:\\Users\\31379\\.moon\\lib\\core\\_build\\wasm\\release\\bundle\\prelude\\prelude.mi:
    No such file or directory")

The CAUSE was not in this repository. `C:\Users\31379\.moon\lib\core` and `...\bin` were REWRITTEN
at 2026-10-20 00:54:16, and the whole standard library was rebuilt between 00:54:32 and 00:54:38
-- while the gate was running. The toolchain went from **0.1.20261012** to **0.1.20261016** in the
middle of the run. The gates that failed are exactly the ones that happened to be executing during
that window, and the ones after it -- 0488, 0489, 0490 -- passed, because the standard library was
whole again by then.

Nothing in this repository asked for that upgrade. The registry index was refreshed at 00:52:29 and
`riantr/moonbit_doubleML 0.163.9` was cached at 00:45:12, so another project on this machine was
installing from mooncakes.io at the same time, and the toolchain went with it.

AND THE UPGRADE HAD TWO CONSEQUENCES FOR THE WORK, one mechanical and one substantive.

THE MECHANICAL ONE: THE TOOLCHAIN NOW REGENERATES THE `.mbti` INTERFACE FILES ITSELF. Under
0.1.20261012 `moon check` and `moon fmt` left `src/*/pkg.generated.mbti` alone, which is why 0490
had to regenerate four of them by hand and why this repository's own history notes the header
"Generated using `moon info`, DON'T EDIT IT". Under 0.1.20261016 the build writes them, and FIVE
MORE changed on their own -- `core`, `lexer`, `moonfiles`, `types`, `walk` -- every one of them the
same shape:

    -  pub fn pos(Int, Int) -> Pos
    +  pub fn pos(Int32, Int32) -> Pos
    -  line : Int
    +  line : Int32

That is the SAME defect 0490 fixed in four files, in the five files 0490 did not touch: 0.1.20261012
renamed the default integer type, `moon fmt` rewrote this repository's SOURCE to `Int32`, and the
committed interface files kept the old spelling. They were stale, and the new toolchain noticed.
Measured, not assumed: `_verify/_mbti_regen_probe.ps1` restores `src/core/pkg.generated.mbti` from
`HEAD` (the `Int` spelling) and runs `moon check` -- and the file comes back with `Int32`. The
toolchain regenerates it.

THE SUBSTANTIVE ONE: **A SETTLED FACT IS A CLAIM ABOUT A TOOLCHAIN VERSION, AND ONE OF 0490's WAS
INVERTED.** 0490's `n_omittable` comment said:

    the toolchain settles that: `fn f(x~ : Int)` called as `f(1)` is accepted, but `f(x=1)` is
    rejected with 4085, "This function has no parameter with label x~"

That is WRONG ON BOTH HALVES, and the toolchain says the opposite:

    ACCEPT         `fn f(x~ : Int)` called as `f(x=1)`   -- BY LABEL
    REJECT 4086   `fn f(x~ : Int)` called as `f()`       -- "The labels x~ are required by this
                                                          function, but not supplied."
    REJECT 4086   `fn f(x~ : Int)` called as `f(1)`     -- a POSITIONAL pass fails too, with 4080
                                                          as well: "requires 0 positional arguments,
                                                          but is given 1"
    REJECT 4085   `fn f(x : Int)` called as `f(x=1)`     -- and 4085 belongs to THIS row: a label
                                                          on a POSITIONAL parameter, not on a `~` one

The CONCLUSION the wrong evidence was offered for -- "`~` alone does not make a parameter
omittable" -- was RIGHT, and so was the CODE, because the parser sets `omittable` only for `?` and
for a default value. So this was a false STATEMENT in a comment, not a false rule in the analyzer.
The `omittable` flag is set for exactly the two spellings the toolchain allows to be omitted, and
the arity floor is exactly the required count.

WHAT MAKES IT WORTH THE SPACE is that the repository ALREADY HAD THE CORRECT VERSION OF IT, in a
different file, written earlier: `src/lexer/lexer.mbt`'s `TTilde` note (0.4.18) says a `~`
parameter "must be supplied BY LABEL" and that the compiler "rejects a positional pass with 'The
labels f~ are required by this function, but not supplied.'" That is EXACTLY right, and it was
there before 0490. So the defect was not a missing measurement -- it was a SECOND, contradictory
copy of a measurement the repository already held, and a reader who went to the lexer would have
found the truth.

THE RE-SETTLE that caught it is `_verify/_settle_0490_resettle.ps1`: EIGHTEEN rows, ONE PACKAGE
EACH, on the installed toolchain. One package per row because a single package cannot hold two
rows -- one row's error would mask another's -- and the whole point of a settle is to see each
verdict separately. All eighteen agree with 0490's conclusions, and the two the old comment got
backwards are among them.

And the settle script itself had a bug worth recording, because it produced four false REJECTs on
its first run: **`moon.mod` IS NOT JSON.** It is `key = "value"`, and a JSON body is a PARSE ERROR
-- "unexpected token { at line 1, column 1" -- which the toolchain reports as "Failed to calculate
build plan". A build failure that looks like a settle verdict is neither. The four rows that came
back REJECT for the wrong reason were exactly the four that were supposed to be ACCEPT.

=> 判据: A SETTLED FACT IS A CLAIM ABOUT A TOOLCHAIN, AND THE CLAIM HAS TO NAME THE VERSION. Every
fact 0490 settled cited `moon check` 0.1.20261012 by number, and the toolchain moved to
0.1.20261016 in the middle of the release gate -- so every one of them had to be re-checked against
what is actually installed, and one was found INVERTED. The number in the citation is not
decoration: it is what makes the claim checkable. And a fact that is settled ONCE and then quoted
in a second file is a fact with two copies and no owner, and the second copy is where the
inversion went.

THE THIRD RUN OF THE GATE FAILED ON THE SELF-SCAN, and it is the most interesting of the three
failures, because what it found was not a lens defect at all. It was a TOOLCHAIN RENAME that the
analyzer's own tables had not followed.

    GATE FAILED: self-scan (own source)
      files=159 parsed=159 actionable=37 notices=1749 unreliable=0 withheld=0 total=1786
      FAIL: actionable is not 0.

Thirty-seven findings, and EVERY ONE of them was the same line:

    unknown type 'Int32' in interface signature (not declared here, not builtin, not in any scanned interface)

-- in the analyzer's OWN `src/*/pkg.generated.mbti` files, the ones the new toolchain had just
rewritten. The `.mbti` frontend resolves a signature's type names against the ambient list, and the
ambient list carried `Int` and not `Int32`.

THE TOOLCHAIN RENAMED TWO BUILTIN TYPES. On 0.1.20261016 `Int` is `Int32` and `UInt` is `UInt32`,
and the interfaces it generates say so:

    -  pub fn pos(Int, Int) -> Pos
    +  pub fn pos(Int32, Int32) -> Pos

`Int16` and `UInt16` were NOT renamed -- the change is of the UNSUFFIXED names only, which is what
makes it a rename rather than a widening. And the rename is not confined to the interfaces: the
toolchain declares ALL FORTY-FOUR of the integer type's methods under `Int32::` and NONE under
`Int::`,

    44   Int32::abs, Int32::add, Int32::asr, ... Int32::unsafe_to_char
    0    Int::...                                   <- the same forty-four, under the old name

-- so the defect has TWO faces, and the second is the more expensive one:

  M8  THE AMBIENT TYPE LIST did not learn the new names, so every interface the new toolchain
      generates reported `unknown type 'Int32' in interface signature`. Thirty-seven findings on
      this repository's own files -- and in the DEFAULT view, so every user on the new toolchain
      was getting them too.
  M9  THE METHOD TABLE did not learn them either. `Int32::popcnt(x)` is legal MoonBit -- and it is
      what `moon fmt` rewrites `Int::popcnt(x)` into, because the new spelling is the toolchain's
      canonical form -- and it was reported `undefined function 'Int32::popcnt'`.

BOTH SPELLINGS ARE KEPT, and the reason is that they are the SAME type. Settled with the toolchain,
one package per row, with a control module that must be rejected
(`_verify/settle_0490_int32.ps1`, NINETEEN rows):

    ACCEPT   `let x : Int32 = 1`            ACCEPT   `let x : Int = 1`
    ACCEPT   `fn f(x : Int32) -> Int`       ACCEPT   `fn f(x : Int) -> Int32`
    ACCEPT   `Array[Int32]`, `Map[String, Int32]`, `type MyInt = Int32`
    REJECT 4032   a type that cannot exist                  <- the CONTROL

and `_verify/settle_0490_intrinsic.ps1`, TEN rows, for the names NO interface declares -- the
`T::to_json` family and `unsafe_to_char`, which the generator keeps in a HAND-WRITTEN list and which
therefore no extraction can reach and no carrying-forward can supply:

    ACCEPT   Int32::to_json      ACCEPT   UInt32::to_json      ACCEPT   Int32::unsafe_to_char
    REJECT 4015  UInt32::unsafe_to_char     REJECT 4015  Int32::to_jsonnope    <- the CONTROL

A PROBE THAT DECLARES THE WRONG RETURN TYPE LOOKS EXACTLY LIKE A MISSING METHOD. `T::to_json`
returns `Json`, not `String`, and a probe that says `-> String` gets 4014 "Expr Type Mismatch" --
which reads as "the method does not exist" and is a PROBE BUG, not a toolchain fact. It cost one
round of settling and it is worth recording, because the wrong reading would have removed eighteen
LIVE names from the table.

THE TABLE IS A SUPERSET, AND THE RENAME IS WHY THAT RULE HAD TO BE WRITTEN DOWN. The generator's own
header already said "It can never invent a false alarm, because the table only ever suppresses" --
and the rename is the case that sentence did not cover. Running the generator on the new toolchain
produced 1163 names against the committed 1265: 102 LOST, 0 gained, because the new interfaces no
longer declare the old spellings.

Those 102 are NOT all dropped names. One module per name, with a control module that must be
rejected (`_verify/_settle_0490_builtins_alive.ps1`): 33 are DEAD -- the call is rejected, so
reporting it would be CORRECT -- and 69 are ALIVE, the call is accepted, and dropping them turns
valid code into `undefined function`. Measured on the analyzer itself, in the per-function view:
`Int::popcnt`, `Int::next_power_of_two`, `UInt::trunc_double`, `Int::reinterpret_as_uint`,
`Int::to_char`, `Int::to_byte` and `UInt::add` all became REPORTS on code `moon check` accepts, and
the last two are CALLED by moui 0.1.12.

    keeping a name the toolchain has DROPPED  -> a MISSED report   (accepted)
    dropping a name the toolchain still HAS    -> a FALSE POSITIVE (not accepted)

AND THE SIX PINS STILL MATCHED WITH THE REGENERATED TABLE, which is worth a sentence of its own
because it is what a pin that cannot distinguish two states looks like. The pins are measured in the
MODULE view, which never executes a function body, and the false positives live in the per-function
view -- so the table could have been wrong and the pins could not have said so.

THE REPAIR IS THE UNION, and it is the same repair the generator already applies to its intrinsic
list. The previous table is read back and unioned in, so the table is the union of what the current
interfaces declare, what the intrinsics add, and what the previous table held. Measured on
0.1.20261016 with the committed table in place:

    declared in .mbti         1143
    carried forward            102      <- the names the new interfaces dropped
    intrinsics                  32      (12 of them are ALSO declared in an interface)
    total                      1265      <- the committed count, with NOTHING lost

and with the rename applied -- "Int32" and "UInt32" added to the bare type list, so the extraction
picks up the new spellings -- the table is 1344 names across 40 heads, carrying BOTH spellings of
every renamed method.

A SECOND COUNT WAS ALSO WRONG. The header said `$declared + $intrinsic.Count`, which double-counts
the intrinsics an interface ALSO declares -- twelve of the thirty-two, so every version of the file
was 12 too high (1277 against 1265). The overlap is now COMPUTED rather than assumed, and the
header counts the set.

GATE 0490, IN FULL: 9 KILLED, 0 declared survivors, every restore byte-identical. 1061 tests. The
self-scan is 0 actionable, and the six corpus pins are byte-identical to the 0488 numbers on all
six corpora -- moui 4225, labeler 791, image 218, async 1829/23/0/1852, proton 2131, contract 34.

=> 判据: A TOOLCHAIN RENAME IS A CHANGE TO THE ANALYZER'S TABLES, AND NO AMOUNT OF READING THE
ANALYZER'S OWN SOURCE WILL FIND IT. Every one of these tables is a list of names the TOOLCHAIN
publishes, and the analyzer is the only thing that knows they can change. The self-scan found it in
twelve seconds, because the analyzer's OWN regenerated interfaces were among the files it scanned.
The corpus -- frozen at the old toolchain, and green on all six -- would never have shown it. A
green corpus is not a green analyzer.

=> 判据: A TABLE THAT ONLY SUPPRESSES HAS ASYMMETRIC FAILURE DIRECTIONS, AND THE ASYMMETRY IS THE
RULE. "The table is a MIRROR of the toolchain" and "the table is a SUPERSET of the toolchain" look
like the same sentence until the toolchain renames something. Then one of them loses sixty-nine
live names and the other loses nothing. The direction the repository already accepted -- a missed
report is cheaper than a false positive -- was written into the generator's header as a warning, and
the rename is what turned the warning into a rule.
