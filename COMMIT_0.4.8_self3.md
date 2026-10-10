0.4.8: three self-scan rounds, actionable 104 -> 0 on 46/46 files

Pointed the scanner at itself for three rounds, each round taking the previous
round's output as its work list. Evidence was the mermaid artifact (--mmd '@');
the stdout text report stayed authoritative because the drawing is lossy by
construction (findings_shown_per_file = 40).

  start (0.4.7)  46/46 parsed  actionable 104
  after round 2  46/46 parsed  actionable   8
  after round 3  46/46 parsed  actionable   0

Coverage never regressed. Suite 208 js / 274 wasm / 208 wasm-gc, --deny-warn
clean, moon fmt --check clean.

## Round 1 - parser coverage (A/B/C/E/F)

Six parse shapes that each truncated a file at the first error: shorthand and
labeled struct-literal tails (A), nested string literals inside an
interpolation (B), a trailing `||` on its own line (C), `expected '='` on an
optional type parameter, expression-position `catch` (E), and the five bitwise
operators / compound assignments (F - the lexer had no `& | ^ << >>` tokens at
all and the parser no bit layer). All six probe shapes now reach
first_error_line == 0.

## Round 2 - three trust boundaries

A substitution skip is a hole in the function frame. A `match`, a `try` or an
fn literal is a *declared* scope limit: it moves no error line and costs no
coverage, but the region it skipped is exactly where a binding's only
assignment could be, so UnusedLocal / UnusedParam / ParamChanged could not be
drawn from such a frame. Those functions now skip the frame audit - a second
boundary, independent of first_error_line, because it guards a different fact.
This required the function's whole extent, header to closing brace, so
SFunc / SLocalFunc now carry a body-covering span (parse_block returns the
closer span). 104 -> 8.

Writing through a parameter is a read, not a rebinding. MoonBit structs are
references: `self.field = v`, `v[0] = x` and `pair.0 = x` mutate the object the
parameter points at and leave the parameter itself alone. All three counted as
ParamChanged, producing a report whose own advice ("no longer holds the value
the caller passed") was false. ParamChanged is now a bare-name rebinding only;
the read through the base is kept, because `self.pos += 1` is ordinary.

The 12 UndefinedName findings were stale interfaces, not code: lexer.mbti was
missing 7 constructors the source has had, ast.mbti 5 BOp variants. `moon info`
regenerates them; no code changed.

## Round 3 - the premise was wrong, and that was the finding

The 8 remaining findings were slated for cleanup as dead code. They were not
dead. All 8 were a name read only through a `\{...}` string interpolation -
copy_interp copies the body raw into the payload, so it never became a token.
A name read that way looked unread, and - the worse direction - a name that
does NOT exist inside an interpolation was never reported at all.

So the round fixed the analyzer instead: TStr and EStr now carry the names
their interpolations reference, and the walk resolves each. 8 -> 0.

Then the rescan caught the fix manufacturing two new false positives of its own:
`no visible binding for '1'` and `'10'`, on `\{i + 1}` and `\{pct / 10}`, because
an identifier was allowed to start with a digit. A number is a literal; an
identifier may continue with digits but not start with one. Only a rescan over
real code finds that class.

## Mutation verification

Eight reverts, each red then restored green, because a suppression-shaped change
that nothing can fail is not a check:

  G1 drop the pass-3 guard        -> pins 1,2 red
  G2 drop the local-func guard    -> pin 3 red ONLY (the two guards are
                                     independent paths, not one guard twice)
  G3 audit_suppressed -> false    -> all 3 pins red, control still green
  G4 restore the header-only span -> pins red (proves the body-covering extent
                                     does the work, not the guard line)
  H1 restore assign_to on EField  -> field-write test red only
  H3 restore assign_to on ETupleField -> tuple-field assertion red, NOT the
                                     index one (third branch really covered)
  L1 stop resolving interp names  -> 5 red (both directions)
  L2 drop member + keyword guards -> 3 red (each guard independently load-bearing)
  L3 drop the digit rule          -> 1 red

Three claims about earlier work were falsified by measurement and corrected in
place: walk_module has exactly one call site (pipeline.mbt:130, not sa/main.mbt);
the SAMPLE_STRUCTURE test needed no change under Fix H (its sample has only a
bare-name write); and there were 7 parser skip messages, not 6, all still
covered exactly by the marker substring.

Docs: SKILL.md's subset description claimed "no interpolation" and "no method
calls at all", both long false; README (zh/en) and LOOP.md record the three
rounds with the numbers and the two falsified premises.