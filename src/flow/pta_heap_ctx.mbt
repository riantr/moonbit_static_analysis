// 0581: THE CONTEXT-SENSITIVE HEAP -- deck 11-12 p.28-56.
//
// THE DECK'S OWN SECTION (p.28-30) says three things, and this module is built
// around all three:
//
//     "In practice, to improve precision, context sensitivity should also be
//      applied to heap abstraction"                                     (p.28)
//     "The abstract objects are also qualified by contexts (called heap
//      contexts)"                                                       (p.28)
//     "The most common choice is to inherit contexts from the method where the
//      object is allocated"                                             (p.29)
//     "Context-sensitive heap abstraction provides a finer-grained heap model
//      over allocation-site abstraction"                                (p.30)
//
// AND THE DECK'S NOTATION IS ITS OWN (p.30): the object is `c: o_i` -- the
// context, a colon, and the object -- so the object of the allocation site at
// line 8, in the calling context 3, is `3:o8`.
//
// THE DECK'S EXAMPLE IS p.34-56, and its two tables are the whole point:
//
//     1 n1 = new One();
//     2  n2 = new Two();
//     3  x1 = newX(n1);
//     4  x2 = newX(n2);
//     5  n = x1.f;
//     6
//     7 X newX(Number p) {
//     8   X x = new X();
//     9   x.f = p;
//    10   return x;
//    11 }
//    12 class X {
//    13  Number f;
//    14 }
//
// THE TWO COLUMNS OF p.56, and the deck's own conclusions:
//
//     "C.I. + C.S. heap"   n1 -> o1      n2 -> o2      p   -> o1, o2
//                          x  -> 3:o8, 4:o8
//                          x1 -> 3:o8, 4:o8        x2 -> 3:o8, 4:o8
//                          n  -> o1, o2
//                          3:o8.f -> o1, o2         4:o8.f -> o1, o2
//
//     "C.S. + C.S heap"    n1 -> o1      n2 -> o2      3:p -> o1
//                          3:x -> 3:o8              x1  -> 3:o8
//                          4:p -> o2                4:x -> 4:o8
//                          x2 -> 4:o8              n   -> o1
//                          3:o8.f -> o1             4:o8.f -> o2
//
//     "Context-sensitive heap improves precision"
//     "Without C.S., C.S. heap cannot improve precision"
//
// THE FIRST COLUMN IS NOT "C.S. WITHOUT A C.S. HEAP" -- it is CONTEXT
// INSENSITIVITY WITH A CONTEXT-SENSITIVE HEAP, and the difference is visible in
// the table itself: `p` is ONE pointer holding BOTH objects, because `newX` was
// analysed ONCE, while `x` holds TWO objects, `3:o8` AND `4:o8`, because the
// heap is still sensitive to the call site. That is the deck's second
// conclusion made visible: the heap can be split while the analysis is merged,
// and splitting the heap alone buys nothing.
//
// SO THE THREE READINGS THIS MODULE COMPARES ARE:
//
//     1. THE ORDINARY HEAP        -- the caller's context abstraction, one
//                                    object per allocation site.
//     2. C.S. + C.S. heap         -- the same abstraction, and the object's
//                                    name carries the frame's heap context.
//     3. C.I. + C.S. heap         -- a context-INsensitive analysis over the
//                                    same context-sensitive heap.
//
// AND THE MEASUREMENT IS THE PAIR COUNT, because the deck's claim is about what
// the analysis SAYS: "x.f" holding two objects is a stronger claim than holding
// one, and the deck's `n` is the pointer that says it.
//
// WHAT IS BUILT HERE, AND WHERE. The heap context qualifies the OBJECT'S NAME
// (`pta_heap_objs`: `3:o8`), and the field keys follow from the name
// (`3:o8.f`). So the four rules are NOT rewritten: `pta_sweep_heap` is
// `pta_sweep` with the heap context, and `pta_ctx_run_heap` is `pta_ctx_run`
// with it. One rule, one place -- the same contract `pta.mbt` has held since
// 0547.
//
// AND THE HEAP IS SHARED BY EVERY FRAME, because a field belongs to the object
// and not to the frame that stores into it: the deck's own example writes
// `x.f = p` inside `newX` and reads `n = x1.f` in `main`.

///|
/// The three readings the deck prints, side by side.
pub(all) struct HeapCtxCompare {
  /// "C.S., no C.S. heap" -- the context-sensitive analysis over the ordinary
  /// allocation-site heap.  This is what `pta_ctx_run` has always done, and it
  /// is the BASELINE the deck's two columns are compared against.
  plain : PtaCtxResult
  /// "C.S. + C.S. heap" -- the same analysis over the context-sensitive heap.
  cs_heap : PtaCtxResult
  /// "C.I. + C.S. heap" -- the context-sensitive HEAP under a context-INSENSITIVE
  /// analysis, which is the deck's "Without C.S., C.S. heap cannot improve
  /// precision" (p.56) made into a measurement.
  no_cs : PtaCtxResult
  /// The (pointer, object) pairs of each reading.
  pairs_plain : Int32
  pairs_cs_heap : Int32
  pairs_no_cs : Int32
}

///|
/// The (pointer, object) PAIRS of a run -- the precision measure.
///
/// IT IS PAIRS AND NOT OBJECTS, because a heap can be made smaller by saying
/// less about the same objects, and the deck's claim is about what the analysis
/// says: "x.f" holding two objects is a stronger claim than holding one.
///
/// THE HEAP COUNTS TOO, because the field cells are part of what the analysis
/// says: the deck's p.56 prints them in its own table.
pub fn pta_heap_ctx_pairs(res : PtaCtxResult) -> Int32 {
  let mut n = 0
  for _, pt in res.states {
    for _, s in pt {
      for _k, _v in s {
        n = n + 1
      }
    }
  }
  for _, s in res.heap {
    for _k, _v in s {
      n = n + 1
    }
  }
  n
}

///|
/// The state table in the DECK'S NOTATION: "<context>:<pointer> -> {objects}".
///
/// THE DECK PRINTS THE CONTEXT AS PART OF THE VARIABLE'S NAME (p.56: "3:p",
/// "3:x", "4:p", "4:x"), and this tree keeps the context in the STATE'S KEY
/// instead -- so the table is rebuilt with the deck's spelling before it is
/// printed. The FORMATTER is `pta_text`'s, because a second formatter would be a
/// second idea of what a points-to table looks like.
pub fn pta_heap_ctx_state_text(
  res : PtaCtxResult,
  fname : String,
  ctx : String,
) -> String {
  match res.states.get(pta_ctx_key(fname, ctx)) {
    Some(pt) => {
      let out : Map[String, Map[String, Bool]] = Map([])
      for k, v in pt {
        if ctx == "" {
          out.set(k, v)
        } else {
          out.set(ctx + ":" + k, v)
        }
      }
      pta_text(out)
    }
    None => ""
  }
}

///|
/// THE WHOLE PROGRAM'S TABLE, as a map -- every frame's variables, with the
/// context in front of the name, and the heap's field cells beside them.
///
/// THIS IS THE DECK'S p.56 TABLE, ROW FOR ROW: the right column's nine variable
/// rows (`n1`, `n2`, `3:p`, `3:x`, `x1`, `4:p`, `4:x`, `x2`, `n`) and its two
/// field rows (`3:o8.f`, `4:o8.f`), and the left column's seven variable rows
/// and two field rows.
///
/// IT IS ONE MAP BECAUSE THE DECK'S TABLE IS ONE TABLE, and the only thing that
/// tells `n1` from `3:p` apart is the context in front of the name -- which is
/// why the map is built here, in ONE place, and not by every reader.
pub fn pta_heap_ctx_program_map(res : PtaCtxResult) -> Pta {
  let out : Map[String, Map[String, Bool]] = Map([])
  for key, pt in res.states {
    let ctx = pta_ctx_split(key).1
    for k, v in pt {
      if ctx == "" {
        out.set(k, v)
      } else {
        out.set(ctx + ":" + k, v)
      }
    }
  }
  // THE HEAP'S CELLS, in the same table: the object's own name is the heap's
  // address, so a field cell is already named the way the deck names it.
  for k, v in res.heap {
    out.set(k, v)
  }
  out
}

///|
/// THE WHOLE PROGRAM'S TABLE, printed.
///
/// THE FORMATTER IS `pta_text`'s -- ONE formatter in this tree -- so the table
/// is compared by its ENTRIES and not by the order the entries come out in:
/// the order is SHORTLEX (length first), which is the toolchain's own order.
pub fn pta_heap_ctx_program_text(res : PtaCtxResult) -> String {
  pta_text(pta_heap_ctx_program_map(res))
}

///|
/// The three readings, side by side.
///
/// THE SELECTOR IS THE CALLER'S, because the deck's claim is about the PAIR of
/// choices: the same context abstraction is used for all three readings, so the
/// only thing that differs between them is the HEAP.
pub fn pta_heap_ctx_compare(
  fns : Array[CgFn],
  tab : TraitTable,
  main : String,
  sel : CtxSelect,
) -> HeapCtxCompare {
  let plain = pta_ctx_run(fns, tab, main, sel)
  let cs_heap = pta_ctx_run_heap(fns, tab, main, sel, true)
  let no_cs = pta_ctx_run_heap(fns, tab, main, CtxSelect::Insensitive, true)
  {
    plain,
    cs_heap,
    no_cs,
    pairs_plain: pta_heap_ctx_pairs(plain),
    pairs_cs_heap: pta_heap_ctx_pairs(cs_heap),
    pairs_no_cs: pta_heap_ctx_pairs(no_cs),
  }
}
