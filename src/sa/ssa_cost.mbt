// 0553: WHAT SSA WOULD COST ON A TREE -- the deck's "Why not SSA" (p.37),
// measured on real code instead of asserted.
//
// THE DECK'S THIRD SECTION-PRINTED CLAIM (p.37) IS:
//
//     "SSA may introduce too many variables and phi-functions"
//     "May introduce inefficiency problem when translating to machine code
//      (due to copy operations)"
//
// NEITHER CLAIM HAS A NUMBER IN IT, and a claim without a number is a
// slogan. `src/flow/ssa.mbt` measures the cost of ONE program, and
// `ssa_test.mbt` pins that measurement on the deck's own twelve-instruction
// program -- which is a real measurement, but of a twelve-instruction
// example. THIS FILE IS THE SAME MEASUREMENT OVER REAL CODE.
//
// AND THE COVERAGE IS REPORTED, because a number without its coverage is
// half a number:
//
//   * `files`      -- the `.mbt` files that were read;
//   * `unreadable` -- the files the parser could not read past an error, whose
//                     functions are therefore only partly measured;
//   * `functions`  -- the functions that were measured;
//   * `converted`  -- the functions the lowering converted WHOLE;
//   * `partial`    -- the functions with a statement the lowering declined,
//                     so the SSA form of those is a form of PART of the
//                     function.
//
// AND THE MEASUREMENT IS NOT OF THE ANALYZER'S OPINIONS: it is of the
// deck's SSA over the deck's 3AC, and the 3AC is this tree's lowering of
// real MoonBit.

///|
/// The SSA cost over a whole tree.
pub(all) struct TreeCost {
  /// The number of `.mbt` files that were read.
  mut files : Int32
  /// The number of files the parser could not read past an error.
  mut unreadable : Int32
  /// The number of functions measured.
  mut functions : Int32
  /// The number of functions the lowering converted WHOLE.
  mut converted : Int32
  /// The number of functions with a statement the lowering declined.
  mut partial : Int32
  /// The number of STATEMENTS the lowering declined.
  ///
  /// IT IS THE COVERAGE IN ITS SMALLEST FORM: the lowering converts the
  /// statements it understands and counts the ones it does not, and this is
  /// that count. A function can be one declined or loop among twenty
  /// converted statements, so the count of functions and the count of
  /// statements are both reported.
  mut declined : Int32
  /// The number of instructions, the phis included.
  mut instructions : Int32
  /// The number of variables the programs define.
  mut variables : Int32
  /// The number of SSA versions: one per definition, the phis included.
  mut versions : Int32
  /// The number of phi-functions.
  mut phis : Int32
  /// The number of phi operands with no definition on that path.
  mut undef_operands : Int32
  /// The number of copies a phi-elimination would insert.
  mut copies : Int32
  /// The number of blocks the programs cannot reach.
  mut dead_blocks : Int32
  /// The number of uses with no live definition.
  mut undef_uses : Int32
}

///|
/// Measure what SSA would cost on a tree, and print one line.
///
/// IT PRINTS ONE LINE, and the line is TAB-separated like the scanner's
/// SUMMARY lines, so a gate can read one field without reading the rest.
/// THE FILE LIST IS THE SCANNER'S OWN: the same walk, the same exclusions,
/// the same cap -- one definition of "which files are in this tree".
pub async fn print_ssa_cost(root : String, excludes : Array[String]) -> Unit {
  let files : Array[String] = []
  let _ = collect(root, files, excludes)
  let cost = ssa_cost_over_files(files)
  println(
    "SSA-COST\tfiles=\{cost.files}\tunreadable=\{cost.unreadable}\tfunctions=\{cost.functions}\tconverted=\{cost.converted}\tpartial=\{cost.partial}\tdeclined=\{cost.declined}\tinstructions=\{cost.instructions}\tvariables=\{cost.variables}\tversions=\{cost.versions}\tphis=\{cost.phis}\tcopies=\{cost.copies}\tundef_operands=\{cost.undef_operands}\tdead_blocks=\{cost.dead_blocks}\tundef_uses=\{cost.undef_uses}",
  )
}

///|
/// The SSA cost of every function in a list of files.
pub async fn ssa_cost_over_files(files : Array[String]) -> TreeCost {
  let cost = {
    files: 0,
    unreadable: 0,
    functions: 0,
    converted: 0,
    partial: 0,
    declined: 0,
    instructions: 0,
    variables: 0,
    versions: 0,
    phis: 0,
    undef_operands: 0,
    copies: 0,
    dead_blocks: 0,
    undef_uses: 0,
  }
  let mut i = 0
  while i < files.length() {
    // ONLY THE `.mbt` FILES, because only they carry functions. The scanner
    // also reads `.mbti`, `.mbtp`, `.mbt.md` and `.mbtx`, and none of those
    // has a function body to measure.
    if files[i].has_suffix(".mbt") {
      measure_file(cost, files[i])
    }
    i = i + 1
  }
  cost
}

///|
/// Measure one file's functions.
async fn measure_file(cost : TreeCost, path : String) -> Unit {
  let text = @fs.read_text(path) catch { _ => return }
  if text == "" {
    return
  }
  let parsed = @parser.parse(text)
  // A FILE THE PARSER COULD NOT READ PAST AN ERROR IS COUNTED, because its
  // functions are only partly there and a number that does not say so is a
  // number about a file that is not the file.
  if parsed.first_error > 0 {
    cost.unreadable = cost.unreadable + 1
  }
  cost.files = cost.files + 1
  let mut i = 0
  while i < parsed.tree.body.length() {
    match parsed.tree.body[i].kind {
      @ast.SFunc(_, _, _, body, _) => measure_function(cost, body)
      _ => ()
    }
    i = i + 1
  }
}

///|
/// Measure one function.
fn measure_function(cost : TreeCost, body : Array[@ast.Stmt]) -> Unit {
  let ir = @flow.lower_body(body)
  let c = @flow.ssa_cost(ir)
  cost.functions = cost.functions + 1
  // A FUNCTION WITH A STATEMENT THE LOWERING DECLINED IS COUNTED AS PARTIAL:
  // its SSA form is a form of the part that converted, and the two kinds of
  // function are counted apart on purpose.
  if ir.skipped_count() > 0 {
    cost.partial = cost.partial + 1
    cost.declined = cost.declined + ir.skipped_count()
  } else {
    cost.converted = cost.converted + 1
  }
  cost.instructions = cost.instructions + c.instructions
  cost.variables = cost.variables + c.variables
  cost.versions = cost.versions + c.versions
  cost.phis = cost.phis + c.phis
  cost.undef_operands = cost.undef_operands + c.undef_operands
  cost.copies = cost.copies + c.copies
  cost.dead_blocks = cost.dead_blocks + c.unreachable_blocks
  cost.undef_uses = cost.undef_uses + c.undef_uses
}
