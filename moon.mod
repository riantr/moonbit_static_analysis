// module: riantr/moonbit_static_analysis — a three-inspection static
// analysis pipeline (structural / type / behavior): one pipeline, three
// inspections, one report stream. Two uses: MoonBit program revision (the
// frontend subset of the fast-evolving MoonBit language), and static state
// revision of state machines via src/statecheck (pure-data MachineSpec).
// Dependency direction: machines call US (reference consumer:
// riantr/pyroduct audit package); we never import them.
name = "riantr/moonbit_static_analysis"

version = "0.4.46"

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

// THE ASYNC RUNTIME COMES FROM THE TOOLCHAIN, AND THAT IS THE WHOLE POINT.
//
// There is NO dependency on a separate `moonbitlang/async` module any more.
// The runtime is `moonbitlang/core/async`, part of the `moonbitlang/core`
// module that the user's toolchain already bundles, so:
//
//   * there is no pin here that could disagree with the user's toolchain --
//     which is the disagreement that broke 0.4.38, when the pin said 0.22.6
//     and the user's toolchain bundled 0.22.5;
//   * the build and the host come from the SAME toolchain, so the artifact
//     cannot ask for symbols the host was never going to have.
//
// The host ABI NAME did not change, and that is worth being precise about: a
// wasm import's module name comes from the FFI declaration in the source, and
// `moonbitlang/core/async` still declares its host externs under the name
// "moonbitlang/async". The host supplies the same MODULE as before. What
// changed is the SET of symbols, and the set got BIGGER: the artifact now
// requires 93, not 90.
//
//     + stdio/get_stdio_handle
//     + thread_pool/get_read_console_result
//     + thread_pool/make_read_console_job
//     + thread_pool/make_write_console_job
//     + thread_pool/run_job
//     - io/errno_is_read_EOF/windows
//     - thread_pool/errno_is_cancelled
//
// (measured 2026-11-09 from the artifact's own import section, not from a
// package's declared externs, because the bytes are what a user instantiates.)
//
// THE FLOOR IS A TOOLCHAIN NOW, AND IT IS HIGHER THAN IT WAS. MEASURED: the
// standalone `moonbitlang/async` 0.22.5 covers only 89 of the 93 -- it has
// `stdio/get_stdio_handle` and none of the four thread_pool additions -- so a
// toolchain still bundling the standalone module CANNOT instantiate this
// artifact. The bundled `moonbitlang/core` 0.10.20+65efd5b93 declares 215
// externs and covers all 93.
//
// THAT IS THE TRADE, and it is a real one. The dependency is gone, but the
// minimum host toolchain moved up with it, and a user on an older toolchain
// gets "function import requires a callable" at instantiation -- the same
// failure 0.4.38 had. The contract that says so is
// `_verify/host_requirements.txt`, and `_verify/check_host_requirements.ps1`
// holds the artifact to it: it compares the published import surface against
// the contract in BOTH directions, it refuses a `moonbitlang/async` dependency
// coming back, and it checks the toolchain's bundled core against the
// contract. Raising the floor is allowed -- it is a decision -- but it has to
// be written down here and in the README.
//
// The packages that use the runtime declare it as an experimental package: see
// the `options("allow-experimental-packages": ...)` blocks in `moon.pkg`,
// `src/sa/moon.pkg` and `src/jsoncli/moon.pkg`. `moonbitlang/core/async` is
// still marked experimental by the core team, and that is the other side of
// the same trade: a package that ships with the toolchain but is not yet
// stable.
//
// There is NO import block below, and that is the change: this module depends
// on nothing but the standard library the toolchain already carries.
