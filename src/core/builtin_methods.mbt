// GENERATED FILE — do not edit by hand. See tools/gen_builtin_methods.ps1.
//
// The METHODS of the builtin types, as bare qualified names.
//
// What this fixes, measured. riantr/moonbit_labeler 0.2.13,
// `app_moui/rasterizer.mbt:74`:
//
//     let pixels : Array[Byte] = Array::make(total, Byte::default())
//                                                    ^^^^^^^^^^
//
// was reported as `undefined function 'Array::make'` by the behavioral
// lens, on a line `moon check` accepts. Across the four sibling corpora
// (933 files) this family is 42 distinct names over 4450 call sites; the
// other 41 are latent, masked rather than absent — see the note at the
// bottom of this file.
//
// Why a TABLE and not a rule. The obvious one-line fix is "a call
// qualified on an ambient type is a builtin method, stay quiet." It was
// written for 0.4.16 and reverted, because two of its mutations survived.
// With this table in place the negative control settles it:
//
//     Array::mkae(4, 0)   <- reported, because `mkae` is not in the table
//     Array::make(4, 0)   <- silent, because `make` is
//
// The rule version silences both. This is not a style preference: the
// whole cost of an ambient name is a MISSED report, which the builtins
// header already accepts, and the cheapest way to keep that cost bounded
// is to name the methods rather than to forgive every spelling.
//
// Provenance. Read out of the toolchain's own generated interfaces,
// <toolchain>/lib/core/**/pkg.generated.mbti, at the toolchain this was
// last run against, PLUS the previous table for the names that
// toolchain no longer declares -- see the SUPERSET note below. The
// version below is WRITTEN BY THE GENERATOR and was typed in by hand
// until 0.4.35, which is how a stale table could not be told apart from
// a current one.                    toolchain: moon 0.1.20261016 (1af328f 2026-10-16)
//
// Of the 1344 names below, 140 come from an
// #alias DIRECTIVE rather than from a declaration: #alias(from_array)
// above [type Set[K]] is what makes Set::from_array a real callable
// name. The rest are plain declarations, of which every GENERIC one
// ([pub fn[K : Eq] Set::add]) was invisible to this generator until
// 0.4.35, because its pattern demanded the name come straight after
// fn.
//
// THE LIST IS A SUPERSET, and it is BUILT as one: the union of what the
// current interfaces declare, what the compiler intrinsics add, and
// what the PREVIOUS table held. 102 names are carried forward from
// the table this run replaces. The two failure directions are not
// symmetric -- keeping a name the toolchain has DROPPED is a MISSED
// report, dropping a name the toolchain still HAS is a FALSE POSITIVE
// -- and only the second is unacceptable. Measured on the
// 0.1.20261012 -> 0.1.20261016 upgrade: the new interfaces declare 102
// fewer names, 69 of them still callable, and dropping those 69 turned
// valid calls into undefined function. The cost of the union is that
// the list only grows and dead names accumulate -- the direction this
// table already accepts.
//
// Of the 35 compiler intrinsics settled with
// [moon check], 12 are ALSO declared in an interface, so
// they are counted once and not twice.
//
// The bare TYPE names themselves live in builtins.mbt. This file is sliced to
// those heads, so the two cannot drift: adding a type to the bare list without
// regenerating this one leaves its methods unresolved, which is the failure
// direction — a report the user can see — not a silent hole.

///|
/// Every builtin type method a `.mbt` file may call bare, qualified.
///
/// Merged into `@core.ambient_names()` by `builtins.mbt`, which is where the
/// three lenses look. Kept in its own file so the data stays separate from the
/// reasoning about why the table is allowed to suppress.
pub fn builtin_method_names() -> Array[String] {
  [
    // ArgsLoc
    "ArgsLoc::to_json", "ArgsLoc::to_string",
    // Array
     "Array::add", "Array::all", "Array::any", "Array::append", "Array::Array", "Array::at",
    "Array::binary_search", "Array::binary_search_by", "Array::blit_to", "Array::capacity",
    "Array::chunk_by", "Array::chunks", "Array::clamped_view", "Array::clear", "Array::clone",
    "Array::compare", "Array::contains", "Array::copy", "Array::count", "Array::count_if",
    "Array::dedup", "Array::drain", "Array::each", "Array::eachi", "Array::ends_with",
    "Array::equal", "Array::every", "Array::exact_view", "Array::exists", "Array::extract_if",
    "Array::fill", "Array::filter", "Array::filter_map", "Array::find_index", "Array::flatten",
    "Array::fold", "Array::fold_left", "Array::fold_lefti", "Array::fold_right",
    "Array::fold_righti", "Array::foldi", "Array::from_fixed_array", "Array::from_iter",
    "Array::from_iterator", "Array::get", "Array::get_view", "Array::has_prefix",
    "Array::has_suffix", "Array::hash", "Array::insert", "Array::is_empty", "Array::is_sorted",
    "Array::iter", "Array::iter2", "Array::iterator", "Array::iterator2", "Array::join",
    "Array::last", "Array::length", "Array::lexical_compare", "Array::make", "Array::makei",
    "Array::map", "Array::map_in_place", "Array::map_inplace", "Array::mapi", "Array::mapi_in_place",
    "Array::mapi_inplace", "Array::mut_view", "Array::new", "Array::pop", "Array::push",
    "Array::push_iter", "Array::release_unused", "Array::remove", "Array::repeat",
    "Array::reserve_capacity", "Array::resize", "Array::retain", "Array::retain_map",
    "Array::rev", "Array::rev_each", "Array::rev_eachi", "Array::rev_fold", "Array::rev_foldi",
    "Array::rev_in_place", "Array::rev_inplace", "Array::rev_iter", "Array::rev_iterator",
    "Array::search", "Array::search_by", "Array::set", "Array::shrink_to_fit", "Array::shuffle",
    "Array::shuffle_in_place", "Array::sort", "Array::sort_by", "Array::sort_by_key",
    "Array::split", "Array::starts_with", "Array::strip_prefix", "Array::strip_suffix",
    "Array::sub", "Array::suffixes", "Array::swap", "Array::truncate", "Array::unsafe_blit_fixed",
    "Array::unsafe_get", "Array::unsafe_set", "Array::unzip", "Array::view", "Array::windows",
    "Array::zip", "Array::zip_to_iter2",
    // ArrayView
     "ArrayView::add", "ArrayView::all", "ArrayView::any", "ArrayView::ArrayView",
    "ArrayView::at", "ArrayView::binary_search", "ArrayView::binary_search_by", "ArrayView::blit_to",
    "ArrayView::chunk_by", "ArrayView::chunks", "ArrayView::clamped_view", "ArrayView::compare",
    "ArrayView::contains", "ArrayView::count", "ArrayView::count_if", "ArrayView::each",
    "ArrayView::eachi", "ArrayView::ends_with", "ArrayView::equal", "ArrayView::every",
    "ArrayView::exact_view", "ArrayView::exists", "ArrayView::filter", "ArrayView::filter_map",
    "ArrayView::fold", "ArrayView::foldi", "ArrayView::get", "ArrayView::get_view",
    "ArrayView::has_prefix", "ArrayView::has_suffix", "ArrayView::hash", "ArrayView::is_empty",
    "ArrayView::is_sorted", "ArrayView::iter", "ArrayView::iter2", "ArrayView::iterator",
    "ArrayView::iterator2", "ArrayView::join", "ArrayView::last", "ArrayView::length",
    "ArrayView::lexical_compare", "ArrayView::map", "ArrayView::mapi", "ArrayView::rev",
    "ArrayView::rev_each", "ArrayView::rev_eachi", "ArrayView::rev_fold", "ArrayView::rev_foldi",
    "ArrayView::rev_iter", "ArrayView::rev_iterator", "ArrayView::search", "ArrayView::search_by",
    "ArrayView::start_offset", "ArrayView::starts_with", "ArrayView::strip_prefix",
    "ArrayView::strip_suffix", "ArrayView::sub", "ArrayView::suffixes", "ArrayView::to_array",
    "ArrayView::to_owned", "ArrayView::view", "ArrayView::windows",
    // Bool
     "Bool::compare", "Bool::equal", "Bool::hash", "Bool::op_compare", "Bool::to_int",
    "Bool::to_int16", "Bool::to_int64", "Bool::to_json", "Bool::to_string", "Bool::to_uint",
    "Bool::to_uint16", "Bool::to_uint64",
    // Buffer
     "Buffer::Buffer", "Buffer::contents", "Buffer::is_empty", "Buffer::length",
    "Buffer::reset", "Buffer::to_bytes", "Buffer::to_string", "Buffer::view", "Buffer::write",
    "Buffer::write_byte", "Buffer::write_bytes", "Buffer::write_bytes_interpolation",
    "Buffer::write_bytesview", "Buffer::write_char", "Buffer::write_char_utf16be",
    "Buffer::write_char_utf16le", "Buffer::write_char_utf8", "Buffer::write_double_be",
    "Buffer::write_double_le", "Buffer::write_float_be", "Buffer::write_float_le",
    "Buffer::write_int_be", "Buffer::write_int_le", "Buffer::write_int16_be", "Buffer::write_int16_le",
    "Buffer::write_int64_be", "Buffer::write_int64_le", "Buffer::write_iter", "Buffer::write_leb128",
    "Buffer::write_object", "Buffer::write_string", "Buffer::write_string_interpolation",
    "Buffer::write_string_utf16be", "Buffer::write_string_utf16le", "Buffer::write_string_utf8",
    "Buffer::write_stringview", "Buffer::write_substring", "Buffer::write_uint_be",
    "Buffer::write_uint_le", "Buffer::write_uint16_be", "Buffer::write_uint16_le",
    "Buffer::write_uint64_be", "Buffer::write_uint64_le", "Buffer::write_utf8", "Buffer::write_view",
    // Byte
     "Byte::add", "Byte::Byte", "Byte::compare", "Byte::default", "Byte::div", "Byte::equal",
    "Byte::hash", "Byte::land", "Byte::lnot", "Byte::lor", "Byte::lsl", "Byte::lsr",
    "Byte::lxor", "Byte::mod", "Byte::mul", "Byte::popcnt", "Byte::shl", "Byte::shr",
    "Byte::sub", "Byte::to_char", "Byte::to_double", "Byte::to_float", "Byte::to_hex",
    "Byte::to_int", "Byte::to_int16", "Byte::to_int64", "Byte::to_json", "Byte::to_string",
    "Byte::to_uint", "Byte::to_uint16", "Byte::to_uint64",
    // Bytes
     "Bytes::add", "Bytes::at", "Bytes::chop_prefix", "Bytes::chop_suffix", "Bytes::clamped_view",
    "Bytes::clone", "Bytes::compare", "Bytes::copy", "Bytes::equal", "Bytes::exact_view",
    "Bytes::find", "Bytes::from_array", "Bytes::from_fixedarray", "Bytes::from_iter",
    "Bytes::from_iterator", "Bytes::get", "Bytes::get_view", "Bytes::has_prefix",
    "Bytes::has_suffix", "Bytes::hash", "Bytes::is_empty", "Bytes::iter", "Bytes::iter2",
    "Bytes::iterator", "Bytes::iterator2", "Bytes::length", "Bytes::lexical_compare",
    "Bytes::make", "Bytes::makei", "Bytes::new", "Bytes::of", "Bytes::of_string",
    "Bytes::repeat", "Bytes::rev_find", "Bytes::strip_prefix", "Bytes::strip_suffix",
    "Bytes::sub", "Bytes::to_array", "Bytes::to_fixedarray", "Bytes::to_json", "Bytes::to_string",
    "Bytes::to_unchecked_string", "Bytes::view",
    // BytesView
     "BytesView::at", "BytesView::chop_prefix", "BytesView::chop_suffix", "BytesView::clamped_view",
    "BytesView::compare", "BytesView::data", "BytesView::equal", "BytesView::equal_to_bytes",
    "BytesView::exact_view", "BytesView::find", "BytesView::get", "BytesView::get_view",
    "BytesView::has_prefix", "BytesView::has_suffix", "BytesView::hash", "BytesView::is_empty",
    "BytesView::iter", "BytesView::iter2", "BytesView::iterator", "BytesView::iterator2",
    "BytesView::length", "BytesView::lexical_compare", "BytesView::rev_find", "BytesView::start_offset",
    "BytesView::strip_prefix", "BytesView::strip_suffix", "BytesView::sub", "BytesView::to_array",
    "BytesView::to_bytes", "BytesView::to_fixedarray", "BytesView::to_json", "BytesView::to_owned",
    "BytesView::to_string", "BytesView::view",
    // Char
     "Char::compare", "Char::equal", "Char::escape", "Char::from_int", "Char::hash",
    "Char::is_ascii", "Char::is_ascii_alphabetic", "Char::is_ascii_control", "Char::is_ascii_digit",
    "Char::is_ascii_graphic", "Char::is_ascii_hexdigit", "Char::is_ascii_lowercase",
    "Char::is_ascii_octdigit", "Char::is_ascii_punctuation", "Char::is_ascii_uppercase",
    "Char::is_ascii_whitespace", "Char::is_bmp", "Char::is_control", "Char::is_digit",
    "Char::is_numeric", "Char::is_printable", "Char::is_whitespace", "Char::length",
    "Char::to_ascii_lowercase", "Char::to_ascii_uppercase", "Char::to_int", "Char::to_json",
    "Char::to_string", "Char::to_uint", "Char::utf16_len",
    // Double
     "Double::abs", "Double::add", "Double::ceil", "Double::clamp", "Double::compare",
    "Double::convert_uint", "Double::convert_uint64", "Double::div", "Double::Double",
    "Double::equal", "Double::floor", "Double::from_int", "Double::hash", "Double::inf",
    "Double::is_close", "Double::is_inf", "Double::is_nan", "Double::is_neg_inf",
    "Double::is_pos_inf", "Double::lerp", "Double::max", "Double::min", "Double::min_normal",
    "Double::mod", "Double::mul", "Double::nan", "Double::neg", "Double::pow", "Double::reinterpret_as_i64",
    "Double::reinterpret_as_int64", "Double::reinterpret_as_u64", "Double::reinterpret_as_uint64",
    "Double::round", "Double::signum", "Double::sqrt", "Double::sub", "Double::to_float",
    "Double::to_int", "Double::to_int64", "Double::to_json", "Double::to_string",
    "Double::to_uint", "Double::to_uint64", "Double::trunc", "Double::until",
    // Error
     "Error::to_json", "Error::to_string",
    // Failure
     "Failure::to_json", "Failure::to_string",
    // FixedArray
     "FixedArray::add", "FixedArray::all", "FixedArray::any", "FixedArray::at", "FixedArray::binary_search",
    "FixedArray::binary_search_by", "FixedArray::blit_from_bytes", "FixedArray::blit_from_bytesview",
    "FixedArray::blit_from_string", "FixedArray::blit_to", "FixedArray::clamped_view",
    "FixedArray::clone", "FixedArray::compare", "FixedArray::contains", "FixedArray::copy",
    "FixedArray::each", "FixedArray::eachi", "FixedArray::ends_with", "FixedArray::equal",
    "FixedArray::every", "FixedArray::exact_view", "FixedArray::exists", "FixedArray::fill",
    "FixedArray::fold", "FixedArray::foldi", "FixedArray::from_array", "FixedArray::from_iter",
    "FixedArray::from_iterator", "FixedArray::get", "FixedArray::get_view", "FixedArray::has_prefix",
    "FixedArray::has_suffix", "FixedArray::hash", "FixedArray::is_empty", "FixedArray::is_sorted",
    "FixedArray::iter", "FixedArray::iter2", "FixedArray::iterator", "FixedArray::iterator2",
    "FixedArray::join", "FixedArray::last", "FixedArray::length", "FixedArray::lexical_compare",
    "FixedArray::make", "FixedArray::make_and_blit", "FixedArray::makei", "FixedArray::map",
    "FixedArray::mapi", "FixedArray::mut_view", "FixedArray::rev", "FixedArray::rev_each",
    "FixedArray::rev_eachi", "FixedArray::rev_fold", "FixedArray::rev_foldi", "FixedArray::rev_in_place",
    "FixedArray::rev_inplace", "FixedArray::search", "FixedArray::set", "FixedArray::set_utf16be_char",
    "FixedArray::set_utf16le_char", "FixedArray::set_utf8_char", "FixedArray::sort",
    "FixedArray::sort_by", "FixedArray::sort_by_key", "FixedArray::stable_sort",
    "FixedArray::starts_with", "FixedArray::sub", "FixedArray::swap", "FixedArray::unsafe_blit",
    "FixedArray::unsafe_write_uint16_be", "FixedArray::unsafe_write_uint16_le", "FixedArray::unsafe_write_uint32_be",
    "FixedArray::unsafe_write_uint32_le", "FixedArray::unsafe_write_uint64_be", "FixedArray::unsafe_write_uint64_le",
    "FixedArray::view",
    // Float
     "Float::abs", "Float::add", "Float::ceil", "Float::clamp", "Float::compare",
    "Float::div", "Float::equal", "Float::floor", "Float::from_byte", "Float::from_double",
    "Float::from_int", "Float::from_int64", "Float::from_uint", "Float::from_uint64",
    "Float::hash", "Float::is_close", "Float::is_inf", "Float::is_nan", "Float::is_neg_inf",
    "Float::is_pos_inf", "Float::lerp", "Float::max", "Float::min", "Float::mod",
    "Float::mul", "Float::NaN", "Float::neg", "Float::pow", "Float::reinterpret_as_int",
    "Float::reinterpret_as_uint", "Float::reinterpret_from_int", "Float::reinterpret_from_uint",
    "Float::round", "Float::signum", "Float::sqrt", "Float::sub", "Float::to_be_bytes",
    "Float::to_double", "Float::to_int", "Float::to_json", "Float::to_le_bytes",
    "Float::to_string", "Float::trunc", "Float::until",
    // Hasher
     "Hasher::combine", "Hasher::combine_bool", "Hasher::combine_byte", "Hasher::combine_bytes",
    "Hasher::combine_char", "Hasher::combine_double", "Hasher::combine_float", "Hasher::combine_int",
    "Hasher::combine_int64", "Hasher::combine_string", "Hasher::combine_uint", "Hasher::combine_uint64",
    "Hasher::combine_unit", "Hasher::finalize", "Hasher::Hasher", "Hasher::new",
    // Int
     "Int::abs", "Int::add", "Int::asr", "Int::clamp", "Int::clz", "Int::compare",
    "Int::ctz", "Int::div", "Int::equal", "Int::hash", "Int::Int", "Int::is_leading_surrogate",
    "Int::is_neg", "Int::is_non_neg", "Int::is_non_pos", "Int::is_pos", "Int::is_surrogate",
    "Int::is_trailing_surrogate", "Int::land", "Int::lnot", "Int::lor", "Int::lsl",
    "Int::lsr", "Int::lxor", "Int::max", "Int::min", "Int::mod", "Int::mul", "Int::neg",
    "Int::next_power_of_two", "Int::popcnt", "Int::reinterpret_as_float", "Int::reinterpret_as_uint",
    "Int::shl", "Int::shr", "Int::sub", "Int::to_byte", "Int::to_char", "Int::to_double",
    "Int::to_float", "Int::to_int16", "Int::to_int64", "Int::to_json", "Int::to_string",
    "Int::to_uint", "Int::to_uint16", "Int::to_uint64", "Int::unsafe_to_char", "Int::until",
    // Int16
     "Int16::abs", "Int16::add", "Int16::compare", "Int16::div", "Int16::equal",
    "Int16::from_byte", "Int16::from_int", "Int16::from_int64", "Int16::hash", "Int16::land",
    "Int16::lnot", "Int16::lor", "Int16::lxor", "Int16::mod", "Int16::mul", "Int16::neg",
    "Int16::reinterpret_as_uint16", "Int16::reinterpret_from_uint16", "Int16::shl",
    "Int16::shr", "Int16::sub", "Int16::to_byte", "Int16::to_int", "Int16::to_int64",
    "Int16::to_string",
    // Int32
     "Int32::abs", "Int32::add", "Int32::asr", "Int32::clamp", "Int32::clz", "Int32::compare",
    "Int32::ctz", "Int32::div", "Int32::equal", "Int32::hash", "Int32::Int", "Int32::is_leading_surrogate",
    "Int32::is_neg", "Int32::is_non_neg", "Int32::is_non_pos", "Int32::is_pos", "Int32::is_surrogate",
    "Int32::is_trailing_surrogate", "Int32::land", "Int32::lnot", "Int32::lor", "Int32::lsl",
    "Int32::lsr", "Int32::lxor", "Int32::max", "Int32::min", "Int32::mod", "Int32::mul",
    "Int32::neg", "Int32::next_power_of_two", "Int32::popcnt", "Int32::reinterpret_as_uint",
    "Int32::shl", "Int32::shr", "Int32::sub", "Int32::to_byte", "Int32::to_char",
    "Int32::to_double", "Int32::to_int64", "Int32::to_json", "Int32::to_string",
    "Int32::to_uint", "Int32::to_uint16", "Int32::to_uint64", "Int32::unsafe_to_char",
    "Int32::until",
    // Int64
     "Int64::abs", "Int64::add", "Int64::asr", "Int64::clamp", "Int64::clz", "Int64::compare",
    "Int64::ctz", "Int64::div", "Int64::equal", "Int64::from_int", "Int64::hash",
    "Int64::Int64", "Int64::land", "Int64::lnot", "Int64::lor", "Int64::lsl", "Int64::lsr",
    "Int64::lxor", "Int64::max", "Int64::min", "Int64::mod", "Int64::mul", "Int64::neg",
    "Int64::popcnt", "Int64::reinterpret_as_double", "Int64::reinterpret_as_uint64",
    "Int64::shl", "Int64::shr", "Int64::sub", "Int64::to_byte", "Int64::to_double",
    "Int64::to_float", "Int64::to_int", "Int64::to_int16", "Int64::to_json", "Int64::to_string",
    "Int64::to_uint16", "Int64::to_uint64", "Int64::until",
    // Iter
     "Iter::add", "Iter::all", "Iter::any", "Iter::clamped_view", "Iter::collect",
    "Iter::combine", "Iter::concat", "Iter::contains", "Iter::count", "Iter::count_if",
    "Iter::drop", "Iter::drop_while", "Iter::each", "Iter::eachi", "Iter::empty",
    "Iter::filter", "Iter::filter_map", "Iter::find_first", "Iter::flat_map", "Iter::flatten",
    "Iter::fold", "Iter::head", "Iter::intersperse", "Iter::Iter", "Iter::iter2",
    "Iter::Iterator", "Iter::iterator2", "Iter::join", "Iter::last", "Iter::length",
    "Iter::map", "Iter::map_while", "Iter::mapi", "Iter::maximum", "Iter::minimum",
    "Iter::new", "Iter::next", "Iter::nth", "Iter::peek", "Iter::repeat", "Iter::singleton",
    "Iter::size_hint", "Iter::sub", "Iter::take", "Iter::take_while", "Iter::tap",
    "Iter::to_array", "Iter::view", "Iter::zip",
    // Iter2
     "Iter2::concat", "Iter2::each", "Iter2::iter", "Iter2::iter2", "Iter2::iterator",
    "Iter2::Iterator2", "Iter2::new", "Iter2::next", "Iter2::to_array",
    // Json
     "Json::array", "Json::as_array", "Json::as_bool", "Json::as_null", "Json::as_number",
    "Json::as_object", "Json::as_string", "Json::boolean", "Json::empty_object",
    "Json::equal", "Json::item", "Json::Json", "Json::null", "Json::number", "Json::object",
    "Json::string", "Json::stringify", "Json::transform", "Json::value",
    // Map
     "Map::at", "Map::capacity", "Map::clear", "Map::clone", "Map::contains", "Map::contains_kv",
    "Map::copy", "Map::each", "Map::eachi", "Map::equal", "Map::filter", "Map::from_array",
    "Map::from_iter", "Map::from_iterator", "Map::get", "Map::get_from_bytes", "Map::get_from_string",
    "Map::get_or_default", "Map::get_or_init", "Map::is_empty", "Map::iter", "Map::iter2",
    "Map::iterator", "Map::iterator2", "Map::keys", "Map::length", "Map::Map", "Map::merge",
    "Map::merge_in_place", "Map::new", "Map::of", "Map::remove", "Map::remove_and_get",
    "Map::retain", "Map::set", "Map::size", "Map::to_array", "Map::update", "Map::update_or_default",
    "Map::values",
    // MutArrayView
     "MutArrayView::at", "MutArrayView::clamped_view", "MutArrayView::compare", "MutArrayView::equal",
    "MutArrayView::exact_view", "MutArrayView::hash", "MutArrayView::is_empty", "MutArrayView::iter",
    "MutArrayView::iter2", "MutArrayView::iterator", "MutArrayView::iterator2", "MutArrayView::length",
    "MutArrayView::mut_view", "MutArrayView::MutArrayView", "MutArrayView::rev_iter",
    "MutArrayView::rev_iterator", "MutArrayView::set", "MutArrayView::sort", "MutArrayView::sort_by",
    "MutArrayView::sort_by_key", "MutArrayView::stable_sort", "MutArrayView::start_offset",
    "MutArrayView::sub", "MutArrayView::to_array", "MutArrayView::to_owned", "MutArrayView::unsafe_get",
    "MutArrayView::unsafe_set", "MutArrayView::view",
    // Option
     "Option::bind", "Option::compare", "Option::equal", "Option::filter", "Option::flatten",
    "Option::hash", "Option::is_empty", "Option::is_none", "Option::is_some", "Option::iter",
    "Option::iterator", "Option::map", "Option::map_or", "Option::map_or_else", "Option::None",
    "Option::or", "Option::or_default", "Option::or_else", "Option::or_error", "Option::to_string",
    "Option::unwrap", "Option::unwrap_or", "Option::unwrap_or_default", "Option::unwrap_or_else",
    "Option::unwrap_or_error",
    // ReadOnlyArray
     "ReadOnlyArray::all", "ReadOnlyArray::any", "ReadOnlyArray::at", "ReadOnlyArray::binary_search",
    "ReadOnlyArray::binary_search_by", "ReadOnlyArray::chunk_by", "ReadOnlyArray::chunks",
    "ReadOnlyArray::clamped_view", "ReadOnlyArray::compare", "ReadOnlyArray::contains",
    "ReadOnlyArray::each", "ReadOnlyArray::eachi", "ReadOnlyArray::ends_with", "ReadOnlyArray::equal",
    "ReadOnlyArray::every", "ReadOnlyArray::exact_view", "ReadOnlyArray::exists",
    "ReadOnlyArray::filter", "ReadOnlyArray::filter_map", "ReadOnlyArray::fold",
    "ReadOnlyArray::foldi", "ReadOnlyArray::from_array", "ReadOnlyArray::from_iter",
    "ReadOnlyArray::from_iterator", "ReadOnlyArray::get", "ReadOnlyArray::get_view",
    "ReadOnlyArray::has_prefix", "ReadOnlyArray::has_suffix", "ReadOnlyArray::hash",
    "ReadOnlyArray::is_empty", "ReadOnlyArray::is_sorted", "ReadOnlyArray::iter",
    "ReadOnlyArray::iter2", "ReadOnlyArray::iterator", "ReadOnlyArray::join", "ReadOnlyArray::last",
    "ReadOnlyArray::length", "ReadOnlyArray::lexical_compare", "ReadOnlyArray::makei",
    "ReadOnlyArray::map", "ReadOnlyArray::mapi", "ReadOnlyArray::rev", "ReadOnlyArray::rev_each",
    "ReadOnlyArray::rev_eachi", "ReadOnlyArray::rev_fold", "ReadOnlyArray::rev_foldi",
    "ReadOnlyArray::rev_iter", "ReadOnlyArray::search", "ReadOnlyArray::search_by",
    "ReadOnlyArray::starts_with", "ReadOnlyArray::strip_prefix", "ReadOnlyArray::strip_suffix",
    "ReadOnlyArray::sub", "ReadOnlyArray::suffixes", "ReadOnlyArray::view", "ReadOnlyArray::windows",
    // Ref
     "Ref::map", "Ref::new", "Ref::protect", "Ref::Ref", "Ref::swap", "Ref::update",
    // Repr
     "Repr::Repr", "Repr::to_string",
    // Result
     "Result::bind", "Result::compare", "Result::equal", "Result::flatten", "Result::fold",
    "Result::hash", "Result::is_err", "Result::is_ok", "Result::map", "Result::map_err",
    "Result::or", "Result::or_else", "Result::to_option", "Result::unwrap", "Result::unwrap_err",
    "Result::unwrap_or", "Result::unwrap_or_default", "Result::unwrap_or_else", "Result::unwrap_or_error",
    // Set
     "Set::add", "Set::add_and_check", "Set::capacity", "Set::clear", "Set::clone",
    "Set::contains", "Set::copy", "Set::difference", "Set::each", "Set::eachi", "Set::equal",
    "Set::filter", "Set::from_array", "Set::from_iter", "Set::from_iterator", "Set::insert",
    "Set::intersection", "Set::is_disjoint", "Set::is_empty", "Set::is_subset", "Set::is_superset",
    "Set::iter", "Set::iterator", "Set::land", "Set::length", "Set::lor", "Set::lxor",
    "Set::new", "Set::of", "Set::remove", "Set::remove_and_check", "Set::retain",
    "Set::Set", "Set::size", "Set::sub", "Set::symmetric_difference", "Set::to_array",
    "Set::union", "Set::union_in_place",
    // SourceLoc
     "SourceLoc::to_json_string", "SourceLoc::to_string",
    // String
     "String::add", "String::after", "String::all", "String::any", "String::at",
    "String::before", "String::char_length", "String::char_length_eq", "String::char_length_ge",
    "String::charcode_length", "String::chop_prefix", "String::chop_suffix", "String::clamped_view",
    "String::code_unit_at", "String::code_units", "String::codepoint_length", "String::compare",
    "String::compare_ignore_ascii_case", "String::contains", "String::contains_any",
    "String::contains_char", "String::contains_code_unit", "String::ends_with", "String::equal",
    "String::equal_ignore_ascii_case", "String::escape", "String::every", "String::exact_view",
    "String::exists", "String::find", "String::find_by", "String::fold", "String::from_array",
    "String::from_iter", "String::from_iterator", "String::get", "String::get_char",
    "String::get_view", "String::has_prefix", "String::has_suffix", "String::hash",
    "String::is_blank", "String::is_empty", "String::iter", "String::iter2", "String::iterator",
    "String::iterator2", "String::length", "String::lexical_compare", "String::make",
    "String::offset_of_nth_char", "String::pad_end", "String::pad_start", "String::repeat",
    "String::replace", "String::replace_all", "String::rev", "String::rev_after",
    "String::rev_before", "String::rev_find", "String::rev_fold", "String::rev_iter",
    "String::rev_iterator", "String::rev_split_once", "String::split", "String::split_at",
    "String::split_once", "String::starts_with", "String::strip_prefix", "String::strip_suffix",
    "String::sub", "String::substring", "String::suffixes", "String::to_array", "String::to_bytes",
    "String::to_json", "String::to_lower", "String::to_string", "String::to_string_view",
    "String::to_upper", "String::trim", "String::trim_end", "String::trim_space",
    "String::trim_start", "String::unsafe_char_at", "String::unsafe_substring", "String::view",
    // StringBuilder
     "StringBuilder::is_empty", "StringBuilder::new", "StringBuilder::reset", "StringBuilder::StringBuilder",
    "StringBuilder::to_string", "StringBuilder::write", "StringBuilder::write_char",
    "StringBuilder::write_iter", "StringBuilder::write_object", "StringBuilder::write_string",
    "StringBuilder::write_string_interpolation", "StringBuilder::write_stringview",
    "StringBuilder::write_substring", "StringBuilder::write_view",
    // StringView
     "StringView::add", "StringView::after", "StringView::all", "StringView::any",
    "StringView::at", "StringView::before", "StringView::char_length", "StringView::char_length_eq",
    "StringView::char_length_ge", "StringView::chop_prefix", "StringView::chop_suffix",
    "StringView::clamped_view", "StringView::code_unit_at", "StringView::code_units",
    "StringView::compare", "StringView::compare_ignore_ascii_case", "StringView::contains",
    "StringView::contains_any", "StringView::contains_char", "StringView::contains_code_unit",
    "StringView::data", "StringView::ends_with", "StringView::equal", "StringView::equal_ignore_ascii_case",
    "StringView::equal_to_string", "StringView::escape", "StringView::every", "StringView::exact_view",
    "StringView::exists", "StringView::find", "StringView::find_by", "StringView::fold",
    "StringView::from_array", "StringView::from_iter", "StringView::from_iterator",
    "StringView::get", "StringView::get_char", "StringView::get_view", "StringView::has_prefix",
    "StringView::has_suffix", "StringView::hash", "StringView::is_blank", "StringView::is_empty",
    "StringView::iter", "StringView::iter2", "StringView::iterator", "StringView::iterator2",
    "StringView::length", "StringView::lexical_compare", "StringView::make", "StringView::offset_of_nth_char",
    "StringView::pad_end", "StringView::pad_start", "StringView::repeat", "StringView::replace",
    "StringView::replace_all", "StringView::rev", "StringView::rev_after", "StringView::rev_before",
    "StringView::rev_find", "StringView::rev_fold", "StringView::rev_iter", "StringView::rev_iterator",
    "StringView::rev_split_once", "StringView::split", "StringView::split_at", "StringView::split_once",
    "StringView::start_offset", "StringView::starts_with", "StringView::strip_prefix",
    "StringView::strip_suffix", "StringView::sub", "StringView::suffixes", "StringView::to_array",
    "StringView::to_bytes", "StringView::to_json", "StringView::to_lower", "StringView::to_owned",
    "StringView::to_string", "StringView::to_string_view", "StringView::to_upper",
    "StringView::trim", "StringView::trim_end", "StringView::trim_space", "StringView::trim_start",
    "StringView::unsafe_charcode_at", "StringView::unsafe_get", "StringView::view",
    // UInt
     "UInt::add", "UInt::clamp", "UInt::clz", "UInt::compare", "UInt::ctz", "UInt::div",
    "UInt::equal", "UInt::hash", "UInt::land", "UInt::lnot", "UInt::lor", "UInt::lsl",
    "UInt::lsr", "UInt::lxor", "UInt::max", "UInt::min", "UInt::mod", "UInt::mul",
    "UInt::popcnt", "UInt::reinterpret_as_float", "UInt::reinterpret_as_int", "UInt::shl",
    "UInt::shr", "UInt::sub", "UInt::to_byte", "UInt::to_double", "UInt::to_float",
    "UInt::to_int", "UInt::to_int64", "UInt::to_json", "UInt::to_string", "UInt::to_uint16",
    "UInt::to_uint64", "UInt::trunc_double", "UInt::UInt",
    // UInt16
     "UInt16::add", "UInt16::compare", "UInt16::div", "UInt16::equal", "UInt16::hash",
    "UInt16::is_leading_surrogate", "UInt16::is_surrogate", "UInt16::is_trailing_surrogate",
    "UInt16::land", "UInt16::lnot", "UInt16::lor", "UInt16::lxor", "UInt16::mod",
    "UInt16::mul", "UInt16::reinterpret_as_int16", "UInt16::shl", "UInt16::shr",
    "UInt16::sub", "UInt16::to_byte", "UInt16::to_char", "UInt16::to_int", "UInt16::to_int64",
    "UInt16::to_json", "UInt16::to_string", "UInt16::to_uint", "UInt16::to_uint64",
    "UInt16::UInt16",
    // UInt32
     "UInt32::add", "UInt32::clamp", "UInt32::clz", "UInt32::compare", "UInt32::ctz",
    "UInt32::div", "UInt32::equal", "UInt32::hash", "UInt32::land", "UInt32::lnot",
    "UInt32::lor", "UInt32::lsl", "UInt32::lsr", "UInt32::lxor", "UInt32::max", "UInt32::min",
    "UInt32::mod", "UInt32::mul", "UInt32::popcnt", "UInt32::reinterpret_as_int",
    "UInt32::shl", "UInt32::shr", "UInt32::sub", "UInt32::to_byte", "UInt32::to_double",
    "UInt32::to_int", "UInt32::to_int64", "UInt32::to_json", "UInt32::to_string",
    "UInt32::to_uint16", "UInt32::to_uint64", "UInt32::trunc_double", "UInt32::UInt",
    // UInt64
     "UInt64::add", "UInt64::clz", "UInt64::compare", "UInt64::ctz", "UInt64::div",
    "UInt64::equal", "UInt64::extend_uint", "UInt64::hash", "UInt64::land", "UInt64::lnot",
    "UInt64::lor", "UInt64::lsl", "UInt64::lsr", "UInt64::lxor", "UInt64::mod", "UInt64::mul",
    "UInt64::popcnt", "UInt64::reinterpret_as_double", "UInt64::reinterpret_as_int64",
    "UInt64::shl", "UInt64::shr", "UInt64::sub", "UInt64::to_be_bytes", "UInt64::to_byte",
    "UInt64::to_double", "UInt64::to_float", "UInt64::to_int", "UInt64::to_int64",
    "UInt64::to_json", "UInt64::to_le_bytes", "UInt64::to_string", "UInt64::to_uint",
    "UInt64::to_uint16", "UInt64::trunc_double", "UInt64::UInt64",
    // UninitializedArray
     "UninitializedArray::at", "UninitializedArray::clamped_view", "UninitializedArray::exact_view",
    "UninitializedArray::length", "UninitializedArray::make", "UninitializedArray::make_and_blit",
    "UninitializedArray::set", "UninitializedArray::sub", "UninitializedArray::UninitializedArray",
    // Unit
     "Unit::compare", "Unit::equal", "Unit::hash", "Unit::to_json", "Unit::to_string",
  ]
}
