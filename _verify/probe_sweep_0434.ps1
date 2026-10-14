# A sweep of every candidate construct behind moui's 61 blocked files, settled
# against the toolchain rather than guessed at.
#
# WHY A SEPARATE FILE. `_verify/grammar_probe.ps1` carries the cases that a
# parser comment CITES. This file carries the ones being TRIED. They are kept
# apart so that adding a candidate never silently changes the meaning of an
# already-cited case.
#
# HOW THE SOURCES WERE CORRECTED, because it is the whole content of this file.
# The first run of this sweep reported 5 MOON-BAD verdicts that had nothing to
# do with the grammar. All five were MY probe source, and each failure was
# information about the source rather than about MoonBit:
#
#   * `enum St { Presented  Closed }` on ONE LINE does not parse --
#     "Parse error, unexpected token id (uppercase start), you may expect `;`
#     or `}`". Enum bodies want newlines. (A one-line `struct Box { n : Int }`
#     is fine, which is why the earlier chain cases passed and these did not.)
#   * `@utf8.encode(...)` in a bare probe package: "Package "utf8" not found in
#     the loaded packages". The slice is the thing under test, not the encoder.
#   * `g(async fn(...) {...})` from a NON-async `fn`: "cannot call async
#     function in non-async function". The caller has to be `async fn` too.
#   * `let static_children = (_node : Flow) => children` where `children` is a
#     zero-argument FUNCTION reported `has type (Flow) -> () -> Int`. That is
#     CORRECT MoonBit -- the lambda returns `children`, which is itself a
#     function. moui's `children` is `Array[@core.View[Msg]]`, a plain value,
#     so the lambda is `(Flow) -> Array[...]`. My probe had the types wrong, not
#     the grammar.
#   * `ignore(request); ignore(ms)` on one line: statements want newlines.
#
# ⇒ 判据: a MOON-BAD cell is a question about the probe source first and about
# the grammar second. Read the error before believing the cell.
$PROBE_CASES = [ordered]@{
  # ---- 1. lambda with an EXPLICIT param type ------------------------------
  # moui views/layout/layout_flow.mbt:83
  # `let static_children = (_node : Flow) => children`
  'lam_explicit_param_type'    = "enum Flow {`n  Leaf`n}`nfn take(cb : (Flow) -> Int) -> Int {`n  cb(Flow::Leaf)`n}`nfn f() -> Int {`n  let children = 7`n  let static_children = (_node : Flow) => children`n  take(static_children)`n}`n"

  # ---- 1b. CONTROL: the same lambda with no explicit param type ----------
  'lam_plain_param_control'    = "enum Flow {`n  Leaf`n}`nfn take(cb : (Flow) -> Int) -> Int {`n  cb(Flow::Leaf)`n}`nfn f() -> Int {`n  let children = 7`n  let static_children = _node => children`n  take(static_children)`n}`n"

  # ---- 2. `is` pattern as a bare EXPRESSION ------------------------------
  # moui render/renderer_session.mbt:167
  # `completion.status() is RenderPresentStatus::Presented`
  'is_expr_bare'               = "enum St {`n  Presented`n  Closed`n}`nfn status() -> St { St::Presented }`nfn f() -> Bool {`n  status() is St::Presented`n}`n"

  # ---- 2b. `is` pattern as an `if` CONDITION -----------------------------
  # moui render/common/gpu_render_worker.mbt:114, views/presentation.mbt:475,
  #     backend/common/host_modal/host_modal_session.mbt:107
  'is_expr_if_cond'            = "enum St {`n  Shutdown`n  Busy`n}`nfn f(self : St) -> Int {`n  if self is St::Shutdown {`n    1`n  } else {`n    2`n  }`n}`n"

  # ---- 3. inclusive range `1..<=n` ---------------------------------------
  # moui views/form/date_picker_control.mbt:411, core/text_layout.mbt:411,
  #     render/common/advanced_execution.mbt:320,
  #     views/data/data_grid_viewport_state.mbt:95
  'range_inclusive'            = "fn f(n : Int) -> Unit {`n  for day in 1..<=n {`n    ignore(day)`n  }`n}`n"
  'range_exclusive_control'    = "fn f(n : Int) -> Unit {`n  for day in 0..<n {`n    ignore(day)`n  }`n}`n"

  # ---- 4. optional param whose default is a QUALIFIED call ---------------
  # moui runtime/renderer_recovery.mbt:98
  # `budget? : RendererRecoveryBudget = RendererRecoveryBudget::default(),`
  'optparam_qualified_default' = "enum Budget {`n  Small`n  Big`n}`nfn Budget::default() -> Budget { Budget::Small }`nfn f(budget? : Budget = Budget::default()) -> Unit { ignore(budget) }`n"
  'optparam_plain_default_control' = "fn f(budget? : Int = 3) -> Unit { ignore(budget) }`n"

  # ---- 5. call argument spelled `name?=value` -----------------------------
  # moui views/popover/sheet.mbt:25 `background?=background_brush,`
  'callarg_question_eq'        = "fn g(background? : Int = 0) -> Unit { ignore(background) }`nfn f(b : Int) -> Unit {`n  g(background?=b)`n}`n"
  'callarg_tilde_eq_control'   = "fn g(background~ : Int = 0) -> Unit { ignore(background) }`nfn f(b : Int) -> Unit {`n  g(background~=b)`n}`n"

  # ---- 6. PARENTHESISED single-arg function type annotation --------------
  # moui views/layout/layout_views.mbt:346
  # `let child_views : (ListLayout) -> Array[@core.View[Msg]] = _node => {`
  'fntype_parenthesised_annotation' = "struct LL {`n  n : Int`n}`nfn f(_node : LL) -> Array[Int] { [1] }`nfn g() -> Int {`n  let child_views : (LL) -> Array[Int] = _node => [1]`n  child_views({ n: 0 }).length()`n}`n"

  # ---- 7. a lambda with a BARE single parameter, no parentheses ----------
  # moui runtime/subscription_adapters.mbt:126 `let start = dispatch => {`
  'lam_bare_single_param'      = "fn f(dispatch : Int) -> Int {`n  let start = dispatch => { dispatch + 1 }`n  start(1)`n}`n"

  # ---- 8. empty slice bounds `value[:]` ---------------------------------
  # moui core/semantics.mbt:71 and 3 more
  'slice_empty_bounds'         = "fn f(value : String) -> Int {`n  let s = value[:]`n  s.length()`n}`n"

  # ---- 9. parenthesised type ascription ----------------------------------
  # moui backend/common/embedded/host_transport.mbt:63
  # `(code - ('0' : Int)).to_uint64()`
  'ascription_in_parens'       = "fn f(code : Int) -> UInt64 {`n  (code - ('0' : Int)).to_uint64()`n}`n"

  # ---- 9b. the SAME ascription with NO parentheses -------------------------
  # If this is also MOON-OK then scoping the fix to the parenthesised form
  # leaves a live gap on the table, and the question is how many corpus sites
  # carry it. Decided by measurement, not by which branch is easier to write.
  'ascription_bare_let'        = "fn f() -> Int {`n  let y = 1 : Int`n  y`n}`n"

  # ---- 9c. ascription on a TUPLE element, still parenthesised --------------
  # `(a : T, b)` -- the grouping branch and the tuple branch are different code,
  # and covering one does not cover the other.
  'ascription_tuple_elem'      = "fn f() -> Int {`n  let p = (1 : Int, 2)`n  p.0 + p.1`n}`n"

  # ---- 9d. is an ascription a COERCION or an ASSERTION? -------------------
  # Decides whether the type may be discarded without a subset-exclusion
  # notice. If `s : Int` on a String is accepted, the ascription CHANGES the
  # value and dropping its type is a silent loss of meaning; if it is rejected,
  # the ascription only states what the compiler already checked, and there is
  # nothing to announce. Guessing this wrong is how a notice either becomes
  # noise or goes missing.
  'ascription_is_coercion'     = "fn f() -> Int {`n  let s = `"a`"`n  let n = (s : Int)`n  n`n}`n"

  # ---- 10. anonymous `fn` as a CALL ARGUMENT value ----------------------
  # moui backend/windows/windows_backend.mbt:155
  # `launch_async=Some(async fn(request, frame_interval_ms) {`
  'anon_fn_call_arg'           = "async fn g(cb : async (Int, Int) -> Unit) -> Unit {`n  cb(1, 2)`n}`nasync fn f() -> Unit {`n  g(async fn(request : Int, ms : Int) {`n    ignore(request)`n    ignore(ms)`n  })`n}`n"

  # ---- 11. the `fn name() -> T = "js" "symbol"` FFI declaration ----------
  # moui backend/web/web_host.mbt:382
  # `fn web_begin_create_string() -> Int = "window_web" "begin_create_string"`
  'extern_js_decl'             = "fn web_begin_create_string() -> Int = `"window_web`" `"begin_create_string`"`nfn f() -> Int { web_begin_create_string() }`n"

  # ---- 12. unsigned literal with a suffix --------------------------------
  # moui backend/linux/linux_atspi_host.mbt:193 `actions.fold(init=0U, ...)`
  'uint_literal_suffix'        = "fn f(flags : UInt32) -> UInt32 {`n  let z = 0U`n  z | flags`n}`n"

  # ---- the canary. MUST be rejected; if it is not, the probe is a no-op ---
  'zz_canary_must_be_rejected' = "fn canary( { let = 1 }`n"
}