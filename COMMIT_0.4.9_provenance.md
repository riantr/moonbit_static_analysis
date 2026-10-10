0.4.9: a `@latest` scan named its own artifact `unknown`

Scanning the published package through itself with the invocation the tool's own
header recommends:

    moonx riantr/moonbit_static_analysis@latest riantr/moonbit_static_analysis@latest --mmd-auto

reported 46/46 parsed, actionable=0 - the published 0.4.8 scans itself clean,
which is the check a working tree cannot give you. But the artifact came out as
`riantr-moonbit_static_analysis_unknown_0.1.20260920_20261010T234949Z.mmd`, its
header saying `version=unknown`, while the scan was reading
`.repos/riantr/moonbit_static_analysis/0.4.8/` - whose moon.mod declares
version = "0.4.8".

provenance_for took the version from the coordinate when the target was one and
never fell back to the tree. @latest names no version: split_coord blanks it on
purpose so `moon fetch` receives a bare module. So the documented example
invocation always wrote unknown, on the one field that exists to tell two scans
apart.

target_version now takes the tree's moon.mod for BOTH kinds of target and picks
between the two in one place. A coordinate that PINNED a version is still
believed over the tree - the caller asked for that one, and it is the fact that
decided what was fetched - and only the empty case falls back. The rule is
extracted as a pure function so it can be tested without a filesystem: the
reading half is async and needs a real directory, while this half is where the
decision that was wrong actually lives.

Verified end to end on the same coordinate scan after the fix:

    MMD  riantr-moonbit_static_analysis_0.4.8_0.1.20260920_20261010T235302Z.mmd
      %% version=0.4.8

Four tests: pinned coordinate wins over a disagreeing tree; @latest and a bare
coordinate both fall back; and the negative control that a target with no
version anywhere still admits it rather than borrowing a neighbouring fact.
Mutation-verified - reverting to the old coordinate-only branch turns exactly the
two fallback tests red while the pinned-version and negative controls stay green.

Suite 207 js / 277 wasm / 207 wasm-gc, --deny-warn clean, moon fmt --check
clean.

The lesson is recorded in LOOP.md because it is the same shape as the round-3
finding: three rounds of self-scan verified the report's CONCLUSIONS
(actionable, parsed) and never once looked at the artifact's own name and
header. A defect that only appears in the filename is invisible to a check that
only reads the SUMMARY line.