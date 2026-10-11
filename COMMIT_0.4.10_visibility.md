0.4.10: publishing 0.4.9 exposed two things the self-scan had been hiding

Shipping the provenance fix meant running the published package through itself
again - the check that found the unknown-version bug. That run came back
actionable=2 where 0.4.8 had been clean, on two names in provenance.mbt:

    no visible binding for 'is_coordinate'
    no visible binding for 'split_coord'

Neither is a defect in the code. Both are this release reading its own source
and finding out two things about the tool.

An if EXPRESSION hides undefined names. The same two names appear twice in that
one file and only one was reported:

    let stem = if is_coordinate(p.target) {   // line 226 - if EXPRESSION
    if is_coordinate(target) {                // line 411 - if STATEMENT

`let x = if c { ... } else { ... }` is parsed, its branches are read, and then
discarded - outside the analyzed subset, and the notice says so. A name that
does not exist inside such a branch is never reported. The 0.4.8 self-scan was
clean partly for that reason: those two calls sat in a dropped if-expression.
Moving them into a plain function turned the `if` into a statement, which is
parsed in full, and two latent false negatives became two findings at once.

A package-private helper in another file is invisible. Cross-file resolution
goes through .mbti files and a package-private `fn` appears in none, so one file
calling a sibling file's private helper reads as unbound. That is what the two
findings actually were: real bindings the analyzer has no way to see.
is_coordinate and split_coord are now `pub`, so they enter the interface, for
the same reason prov_or_unknown, stamp_utc and scan_artifact_name already were.
Each carries a comment saying why, so nobody tidies them back to private and
quietly reintroduces the finding.

Neither class is fixed here. Both are declared subset / visibility limits, and
both fail toward silence rather than noise, which is the direction to be wrong
in - but it means a clean scan of a multi-file package is not by itself proof
of anything. Both are recorded in SKILL.md and LOOP.md.

Also: `moon clean; moon info` chained in ONE PowerShell command leaves the info
build on stale incremental state - it reports "no work to do" and does not
rewrite pkg.generated.mbti. They must be separate steps; the .mbti mtime is how
you notice.

Suite 207 js / 277 wasm / 207 wasm-gc, --deny-warn clean, moon fmt --check
clean, self-scan back to 46/46 parsed with actionable=0.