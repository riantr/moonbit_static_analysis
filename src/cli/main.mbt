// demo: run the three-lens pipeline over every embedded sample.

///|
fn main {
  println("moonbit_static_analysis — structural ⊕ type ⊕ behavior")
  println("====================================================")
  for pair in @samples.all() {
    let (file, src) = pair
    println("")
    println("=== \{file} ===")
    println(@pipeline.render_result(@pipeline.run(src, file)))
  }
  println("")
  println(
    "lens key: [structural]=binding walk  [type]=symbols+inference  [behavior]=abstract execution",
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
