package dynview_parse

TEX_PARSE_SOURCE_BYTE_LIMIT :: 8192
TEX_PARSE_WORK_LIMIT :: 8192
TEX_PARSE_COMMAND_BYTE_LIMIT :: 64

// Report bounded lexical and parser failures with stable categories.
Tex_Parse_Status :: enum {
    Ok,
    End,
    Source_Too_Large,
    Work_Limit,
    Invalid_Utf8,
    Command_Too_Long,
    Unexpected_Token,
    Unclosed_Group,
}

// Bound parser admission independently from semantic output capacities.
Tex_Parse_Limits :: struct {
    source_bytes: int,
    work_units: int,
    command_bytes: int,
    depth: int,
}

TEX_PARSE_DEFAULT_LIMITS :: Tex_Parse_Limits{
    source_bytes = TEX_PARSE_SOURCE_BYTE_LIMIT,
    work_units = TEX_PARSE_WORK_LIMIT,
    command_bytes = TEX_PARSE_COMMAND_BYTE_LIMIT,
    depth = 32,
}

// Track one allocation-free UTF-8 source traversal.
Tex_Cursor :: struct {
    source: string,
    offset: int,
    work_count: int,
    limits: Tex_Parse_Limits,
    status: Tex_Parse_Status,
    error_offset: int,
}

//   Return the production parser limits derived from the frozen corpus.
tex_parse_default_limits :: proc() -> Tex_Parse_Limits {
    return TEX_PARSE_DEFAULT_LIMITS
}

//   Initialize a cursor after validating source admission limits.
tex_cursor_init :: proc(
    cursor: ^Tex_Cursor,
    source: string,
    limits := TEX_PARSE_DEFAULT_LIMITS) -> Tex_Parse_Status {
    if cursor == nil {
        return .Unexpected_Token
    }
    cursor^ = {source = source, limits = limits}
    if len(source) > limits.source_bytes {
        return tex_cursor_fail(cursor, .Source_Too_Large, 0)
    }
    return .Ok
}

//   Record the first terminal cursor failure and its source byte offset.
tex_cursor_fail :: proc(
    cursor: ^Tex_Cursor,
    status: Tex_Parse_Status,
    offset: int) -> Tex_Parse_Status {
    if cursor.status == .Ok {
        cursor.status = status
        cursor.error_offset = offset
    }
    return cursor.status
}

//   Charge one bounded lexical work unit before consuming source.
tex_cursor_charge :: proc(cursor: ^Tex_Cursor) -> bool {
    if cursor.work_count >= cursor.limits.work_units {
        tex_cursor_fail(cursor, .Work_Limit, cursor.offset)
        return false
    }
    cursor.work_count += 1
    return true
}

//   Return the strict UTF-8 sequence width at one source byte offset.
tex_utf8_sequence_width :: proc(source: string, offset: int) -> int {
    if offset < 0 || offset >= len(source) {
        return 0
    }
    first := source[offset]
    if first <= 0x7f {
        return 1
    }
    if first >= 0xc2 && first <= 0xdf {
        return tex_utf8_continuations_valid(source, offset, 2) ? 2 : 0
    }
    if first >= 0xe0 && first <= 0xef {
        return tex_utf8_three_byte_width(source, offset)
    }
    if first >= 0xf0 && first <= 0xf4 {
        return tex_utf8_four_byte_width(source, offset)
    }
    return 0
}

//   Validate a fixed-width sequence's continuation bytes and available span.
tex_utf8_continuations_valid :: proc(
    source: string,
    offset, width: int) -> bool {
    if offset > len(source)-width {
        return false
    }
    for index in 1..<width {
        if source[offset + index] & 0xc0 != 0x80 {
            return false
        }
    }
    return true
}

//   Validate one three-byte UTF-8 scalar, excluding overlongs and surrogates.
tex_utf8_three_byte_width :: proc(source: string, offset: int) -> int {
    if !tex_utf8_continuations_valid(source, offset, 3) {
        return 0
    }
    first, second := source[offset], source[offset + 1]
    if first == 0xe0 && second < 0xa0 || first == 0xed && second >= 0xa0 {
        return 0
    }
    return 3
}

//   Validate one four-byte UTF-8 scalar within the Unicode range.
tex_utf8_four_byte_width :: proc(source: string, offset: int) -> int {
    if !tex_utf8_continuations_valid(source, offset, 4) {
        return 0
    }
    first, second := source[offset], source[offset + 1]
    if first == 0xf0 && second < 0x90 || first == 0xf4 && second >= 0x90 {
        return 0
    }
    return 4
}