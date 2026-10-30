// module: riantr/moonbit_static_analysis — a three-inspection static
// analysis pipeline (structural / type / behavior): one pipeline, three
// inspections, one report stream. Two uses: MoonBit program revision (the
// frontend subset of the fast-evolving MoonBit language), and static state
// revision of state machines via src/statecheck (pure-data MachineSpec).
// Dependency direction: machines call US (reference consumer:
// riantr/pyroduct audit package); we never import them.
name = "riantr/moonbit_static_analysis"

version = "0.4.39"

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

// The async pin is also a promise about the HOST, and that is the promise that
// was broken once.
//
// The published wasm imports 90 symbols from `moonbitlang/async`, and the host
// has to supply every one of them when the module is instantiated -- `moonx`
// supplies them from the async bundled with the USER's toolchain, not from the
// version pinned here. async 0.22.6 turned three of the console jobs into host
// externs, so a build against 0.22.6 needs a toolchain bundling 0.22.6 or
// later; 0.4.38 shipped that and a user on an older toolchain could not
// instantiate it.
//
// 0.22.5 is the newest async whose host requirements a toolchain bundling
// 0.22.4 or 0.22.5 can satisfy, and it is what the artifact is built against.
// The contract that says so is `_verify/host_requirements.txt`, and
// `_verify/check_host_requirements.ps1` holds the artifact to it: a dependency
// bump that widens the host requirements fails that gate instead of quietly
// dropping users. Raising the floor is allowed -- it is a decision -- but it
// has to be written down here and in the README.
import {
  "moonbitlang/async@0.22.5",
}
