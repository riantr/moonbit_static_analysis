// GENERATED FILE 鈥?do not edit by hand. See tools/gen_builtin_methods.ps1.
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
// other 41 are latent, masked rather than absent 鈥?see the note at the
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
// <toolchain>/lib/core/**/pkg.generated.mbti, at moon 0.1.20260920
// (914d7da 2026-09-20). $declared of the $(( $declared + $intrinsic.Count )) names
// below are declared in one of those files; the last $intrinsic.Count are
// compiler builtins that no interface declares, settled with `moon check`.
//
// The bare TYPE names themselves live in builtins.mbt. This file is sliced to
// those heads, so the two cannot drift: adding a type to the bare list without
// regenerating this one leaves its methods unresolved, which is the failure
// direction 鈥?a report the user can see 鈥?not a silent hole.

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
     "Array::copy", "Array::from_iter", "Array::make", "Array::makei", "Array::sort",
    // Bool
     "Bool::compare", "Bool::equal", "Bool::hash", "Bool::op_compare", "Bool::to_int",
    "Bool::to_int16", "Bool::to_int64", "Bool::to_json", "Bool::to_string", "Bool::to_uint",
    "Bool::to_uint16", "Bool::to_uint64",
    // Byte
     "Byte::add", "Byte::Byte", "Byte::compare", "Byte::default", "Byte::div", "Byte::equal",
    "Byte::hash", "Byte::land", "Byte::lnot", "Byte::lor", "Byte::lsl", "Byte::lsr",
    "Byte::lxor", "Byte::mod", "Byte::mul", "Byte::popcnt", "Byte::shl", "Byte::shr",
    "Byte::sub", "Byte::to_char", "Byte::to_double", "Byte::to_float", "Byte::to_hex",
    "Byte::to_int", "Byte::to_int16", "Byte::to_int64", "Byte::to_json", "Byte::to_string",
    "Byte::to_uint", "Byte::to_uint16", "Byte::to_uint64",
    // Bytes
     "Bytes::add", "Bytes::at", "Bytes::chop_prefix", "Bytes::chop_suffix", "Bytes::clamped_view",
    "Bytes::compare", "Bytes::copy", "Bytes::equal", "Bytes::exact_view", "Bytes::find",
    "Bytes::from_array", "Bytes::from_fixedarray", "Bytes::from_iter", "Bytes::get",
    "Bytes::get_view", "Bytes::has_prefix", "Bytes::has_suffix", "Bytes::hash", "Bytes::is_empty",
    "Bytes::iter", "Bytes::iter2", "Bytes::length", "Bytes::lexical_compare", "Bytes::make",
    "Bytes::makei", "Bytes::new", "Bytes::of_string", "Bytes::repeat", "Bytes::rev_find",
    "Bytes::to_array", "Bytes::to_fixedarray", "Bytes::to_json", "Bytes::to_string",
    "Bytes::to_unchecked_string",
    // BytesView
     "BytesView::at", "BytesView::chop_prefix", "BytesView::chop_suffix", "BytesView::clamped_view",
    "BytesView::compare", "BytesView::data", "BytesView::equal", "BytesView::equal_to_bytes",
    "BytesView::exact_view", "BytesView::find", "BytesView::get", "BytesView::get_view",
    "BytesView::has_prefix", "BytesView::has_suffix", "BytesView::hash", "BytesView::is_empty",
    "BytesView::iter", "BytesView::iter2", "BytesView::length", "BytesView::lexical_compare",
    "BytesView::rev_find", "BytesView::start_offset", "BytesView::to_array", "BytesView::to_fixedarray",
    "BytesView::to_json", "BytesView::to_owned", "BytesView::to_string",
    // Char
     "Char::compare", "Char::equal", "Char::escape", "Char::from_int", "Char::hash",
    "Char::is_ascii", "Char::is_ascii_alphabetic", "Char::is_ascii_control", "Char::is_ascii_digit",
    "Char::is_ascii_graphic", "Char::is_ascii_hexdigit", "Char::is_ascii_lowercase",
    "Char::is_ascii_octdigit", "Char::is_ascii_punctuation", "Char::is_ascii_uppercase",
    "Char::is_ascii_whitespace", "Char::is_bmp", "Char::is_control", "Char::is_digit",
    "Char::is_numeric", "Char::is_printable", "Char::is_whitespace", "Char::to_ascii_lowercase",
    "Char::to_ascii_uppercase", "Char::to_int", "Char::to_json", "Char::to_string",
    "Char::to_uint", "Char::utf16_len",
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
     "FixedArray::blit_from_bytes", "FixedArray::blit_from_bytesview", "FixedArray::blit_from_string",
    "FixedArray::set_utf16be_char", "FixedArray::set_utf16le_char", "FixedArray::set_utf8_char",
    "FixedArray::unsafe_write_uint16_be", "FixedArray::unsafe_write_uint16_le", "FixedArray::unsafe_write_uint32_be",
    "FixedArray::unsafe_write_uint32_le", "FixedArray::unsafe_write_uint64_be", "FixedArray::unsafe_write_uint64_le",
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
     "Hasher::combine_bool", "Hasher::combine_byte", "Hasher::combine_bytes", "Hasher::combine_char",
    "Hasher::combine_double", "Hasher::combine_float", "Hasher::combine_int", "Hasher::combine_int64",
    "Hasher::combine_string", "Hasher::combine_uint", "Hasher::combine_uint64", "Hasher::combine_unit",
    "Hasher::finalize", "Hasher::Hasher",
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
    // Int64
     "Int64::abs", "Int64::add", "Int64::asr", "Int64::clamp", "Int64::clz", "Int64::compare",
    "Int64::ctz", "Int64::div", "Int64::equal", "Int64::from_int", "Int64::hash",
    "Int64::Int64", "Int64::land", "Int64::lnot", "Int64::lor", "Int64::lsl", "Int64::lsr",
    "Int64::lxor", "Int64::max", "Int64::min", "Int64::mod", "Int64::mul", "Int64::neg",
    "Int64::popcnt", "Int64::reinterpret_as_double", "Int64::reinterpret_as_uint64",
    "Int64::shl", "Int64::shr", "Int64::sub", "Int64::to_byte", "Int64::to_double",
    "Int64::to_float", "Int64::to_int", "Int64::to_int16", "Int64::to_json", "Int64::to_string",
    "Int64::to_uint16", "Int64::to_uint64", "Int64::until",
    // Json
     "Json::array", "Json::as_array", "Json::as_bool", "Json::as_null", "Json::as_number",
    "Json::as_object", "Json::as_string", "Json::boolean", "Json::empty_object",
    "Json::equal", "Json::item", "Json::null", "Json::number", "Json::object", "Json::string",
    "Json::stringify", "Json::transform", "Json::value",
    // Map
     "Map::each", "Map::from_array", "Map::new",
    // Option
     "Option::None",
    // Ref
     "Ref::new",
    // Repr
     "Repr::to_string",
    // SourceLoc
     "SourceLoc::to_json_string", "SourceLoc::to_string",
    // String
     "String::add", "String::after", "String::all", "String::any", "String::at",
    "String::before", "String::char_length", "String::char_length_eq", "String::char_length_ge",
    "String::clamped_view", "String::code_units", "String::compare", "String::compare_ignore_ascii_case",
    "String::contains", "String::contains_any", "String::contains_char", "String::contains_code_unit",
    "String::equal", "String::equal_ignore_ascii_case", "String::escape", "String::exact_view",
    "String::find", "String::find_by", "String::from_array", "String::from_iter",
    "String::get", "String::get_char", "String::get_view", "String::has_prefix",
    "String::has_suffix", "String::hash", "String::is_blank", "String::is_empty",
    "String::iter", "String::iter2", "String::length", "String::lexical_compare",
    "String::make", "String::offset_of_nth_char", "String::pad_end", "String::pad_start",
    "String::repeat", "String::replace", "String::replace_all", "String::rev", "String::rev_after",
    "String::rev_before", "String::rev_find", "String::rev_iter", "String::rev_split_once",
    "String::split", "String::split_at", "String::split_once", "String::starts_with",
    "String::strip_prefix", "String::strip_suffix", "String::substring", "String::suffixes",
    "String::to_array", "String::to_bytes", "String::to_json", "String::to_lower",
    "String::to_string", "String::to_string_view", "String::to_upper", "String::trim",
    "String::trim_end", "String::trim_space", "String::trim_start", "String::unsafe_char_at",
    "String::unsafe_substring", "String::view",
    // StringBuilder
     "StringBuilder::is_empty", "StringBuilder::new", "StringBuilder::reset", "StringBuilder::StringBuilder",
    "StringBuilder::to_string", "StringBuilder::write_char", "StringBuilder::write_iter",
    "StringBuilder::write_string", "StringBuilder::write_stringview", "StringBuilder::write_substring",
    "StringBuilder::write_view",
    // StringView
     "StringView::add", "StringView::after", "StringView::all", "StringView::any",
    "StringView::at", "StringView::before", "StringView::char_length", "StringView::char_length_eq",
    "StringView::char_length_ge", "StringView::clamped_view", "StringView::code_units",
    "StringView::compare", "StringView::compare_ignore_ascii_case", "StringView::contains",
    "StringView::contains_any", "StringView::contains_char", "StringView::contains_code_unit",
    "StringView::data", "StringView::equal", "StringView::equal_ignore_ascii_case",
    "StringView::equal_to_string", "StringView::escape", "StringView::exact_view",
    "StringView::find", "StringView::find_by", "StringView::from_array", "StringView::from_iter",
    "StringView::get", "StringView::get_char", "StringView::get_view", "StringView::has_prefix",
    "StringView::has_suffix", "StringView::hash", "StringView::is_blank", "StringView::is_empty",
    "StringView::iter", "StringView::iter2", "StringView::length", "StringView::lexical_compare",
    "StringView::make", "StringView::offset_of_nth_char", "StringView::pad_end",
    "StringView::pad_start", "StringView::repeat", "StringView::replace", "StringView::replace_all",
    "StringView::rev", "StringView::rev_after", "StringView::rev_before", "StringView::rev_find",
    "StringView::rev_iter", "StringView::rev_split_once", "StringView::split", "StringView::split_at",
    "StringView::split_once", "StringView::start_offset", "StringView::strip_prefix",
    "StringView::strip_suffix", "StringView::suffixes", "StringView::to_array", "StringView::to_bytes",
    "StringView::to_json", "StringView::to_lower", "StringView::to_owned", "StringView::to_string_view",
    "StringView::to_upper", "StringView::trim", "StringView::trim_end", "StringView::trim_space",
    "StringView::trim_start", "StringView::unsafe_charcode_at", "StringView::unsafe_get",
    "StringView::view",
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
    // UInt64
     "UInt64::add", "UInt64::clz", "UInt64::compare", "UInt64::ctz", "UInt64::div",
    "UInt64::equal", "UInt64::extend_uint", "UInt64::hash", "UInt64::land", "UInt64::lnot",
    "UInt64::lor", "UInt64::lsl", "UInt64::lsr", "UInt64::lxor", "UInt64::mod", "UInt64::mul",
    "UInt64::popcnt", "UInt64::reinterpret_as_double", "UInt64::reinterpret_as_int64",
    "UInt64::shl", "UInt64::shr", "UInt64::sub", "UInt64::to_be_bytes", "UInt64::to_byte",
    "UInt64::to_double", "UInt64::to_float", "UInt64::to_int", "UInt64::to_int64",
    "UInt64::to_json", "UInt64::to_le_bytes", "UInt64::to_string", "UInt64::to_uint",
    "UInt64::to_uint16", "UInt64::trunc_double", "UInt64::UInt64",
    // Unit
     "Unit::compare", "Unit::equal", "Unit::hash", "Unit::to_json", "Unit::to_string",
  ]
}
