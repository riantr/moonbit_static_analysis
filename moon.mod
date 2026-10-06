// module: riantr/moonbit_static_analysis — a three-inspection static
// analysis pipeline (structural / type / behavior): one pipeline, three
// inspections, one report stream. Two uses: MoonBit program revision (the
// frontend subset of the fast-evolving MoonBit language), and static state
// revision of state machines via src/statecheck (pure-data MachineSpec).
// Dependency direction: machines call US (reference consumer:
// riantr/pyroduct audit package); we never import them.
name = "riantr/moonbit_static_analysis"

version = "0.3.3"

readme = "README.md"

repository = "https://github.com/riantr/moonbit_static_analysis"

license = "MIT"

keywords = [
  "static-analysis",
  "linter",
  "state-machine",
  "abstract-interpretation",
  "file-kinds",
  "mbti",
  "literate-markdown",
  "formal-verification",
]

description = "Three-inspection (structural / type / behavior) static analysis for MoonBit programs, every toolchain file kind (.mbt / .mbtx / .mbti / .mbt.md / .mbtp) and state-machine tables"

// wasm, not js: `src/sa` needs the async runtime (file IO + `moon fetch`) and
// `moonx` runs the wasm backend. The js backend has no async runtime, so those
// packages degrade and their functions vanish. The DSH plugin still builds the
// JSON bridge for js explicitly, so nothing downstream of that changes.

preferred_target = "wasm"

warnings = "-0079"

import {
  "moonbitlang/async@0.22.4",
}
