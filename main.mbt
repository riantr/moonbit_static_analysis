///|
/// Cross-project static analysis, without naming a package:
///
///   moonx riantr/moonbit_static_analysis@latest <target>
///
/// `<target>` is a registry coordinate (`author/module`, optionally
/// `@version` or `@latest`) or a filesystem path; omit it for the current
/// directory. The target project neither depends on this module nor is
/// modified — sources are only READ, at scan time.
///
/// This root package exists purely to make the short `moonx <module>` form
/// work: an unpinned `moonx <module>` resolves the module's ROOT package, and
/// without a root executable it fails with "Prebuilt wasm asset does not
/// exist". The implementation lives in `src/sa`; this forwards to it.
async fn main {
  let args = @env.args()
  let target = if args.length() >= 2 { args[1] } else { "." }
  @sa.scan(target)
}
