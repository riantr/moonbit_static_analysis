// module: riantr/moonbit_static_analysis — a three-lens static analysis
// pipeline: one pipeline, three lenses, one report stream. Two uses: MLang
// program revision, and static state revision of state machines via
// src/statecheck (pure-data MachineSpec). Dependency direction: machines
// call US (reference consumer: riantr/pyroduct audit package); we never
// import them.
name = "riantr/moonbit_static_analysis"

version = "0.1.0"

preferred_target = "js"

warnings = "-0079"
