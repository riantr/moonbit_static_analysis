// demo: run the three-lens pipeline over every embedded sample.

///|
fn main {
  println("moonbit_static_analysis — structural ⊕ type ⊕ behavior")
  println("====================================================")
  for pair in @samples.all() {
    let (file, src) = pair
    println("")
    println("=== \{file} ===")
    println(
      @pipeline.render_result(
        @pipeline.run(src, file, @core.IfaceSymTab::empty()),
      ),
    )
  }
  println("")
  println(
    "lens key: [structural]=binding walk  [type]=symbols+inference  [behavior]=abstract execution",
  )
  println("")
  println("====================================================")
  println(
    "toolchain file kinds (.mbt / .mbtx / .mbti / .mbt.md / .mbtp — see EXTENSIONS.md)",
  )
  println("")
  // counted from the sample, never hard-coded: see @moonfiles.fence_census
  {
    let (live, display) = @moonfiles.fence_census(@samples.literate_md)
    println(
      "=== demo.mbt.md (literate: \{live} live fence(s), \{display} display-only skipped) ===",
    )
  }
  println(
    @pipeline.render_result(
      @moonfiles.literate(@samples.literate_md, "demo.mbt.md"),
    ),
  )
  println("=== demo.mbtx (script: import block + a body defect) ===")
  println(
    @pipeline.render_result(
      @pipeline.run(
        @samples.script_mbtx,
        "demo.mbtx",
        @core.IfaceSymTab::empty(),
      ),
    ),
  )
  println("=== demo.mbti (interface: unknown type reference) ===")
  println(
    @moonfiles.render_reports(
      @moonfiles.iface(
        @samples.iface_bad,
        "demo.mbti",
        @core.IfaceSymTab::empty(),
      ),
    ),
  )
  println("=== demo.mbtp (proof: string constant in a logic body) ===")
  println(
    @moonfiles.render_reports(@moonfiles.proof(@samples.proof_bad, "demo.mbtp")),
  )
  println("")
  println("====================================================")
  println(
    "state-machine audit: pyroduct-shaped machine (via @statecheck — pyroduct is the consumer)",
  )
  println(@statecheck.render(@statecheck.pyroduct_flavored()))
  println("")
  println(
    "state lens key: same three lenses on machine tables — states as bindings,",
  )
  println("drive-slot contract as types, step traces as abstract execution")
}
