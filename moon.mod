// module: riantr/moonbit_static_analysis — a three-lens static analysis
// pipeline: one pipeline, three lenses, one report stream. Two uses: MoonBit
// program revision (the MLang subset of the fast-evolving language), and
// static state revision of state machines via
// src/statecheck (pure-data MachineSpec). Dependency direction: machines
// call US (reference consumer: riantr/pyroduct audit package); we never
// import them.
name = "riantr/moonbit_static_analysis"

version = "0.1.2"

readme = "README.md"

repository = "https://github.com/riantr/moonbit_static_analysis"

license = "MIT"

keywords = [
  "static-analysis",
  "linter",
  "state-machine",
  "abstract-interpretation",
]

description = "Three-lens static analysis pipeline (structural / type / behavioral) for MLang programs and state-machine tables"

preferred_target = "js"

warnings = "-0079"
