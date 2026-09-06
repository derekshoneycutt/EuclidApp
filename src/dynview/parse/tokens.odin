package dynview_parse

// Classify allocation-free TeX lexical spans.
Tex_Token_Kind :: enum {
    End,
    Text,
    Command,
    Left_Brace,
    Right_Brace,
    Superscript,
    Subscript,
    Left_Bracket,
    Right_Bracket,
    Alignment,
}

// Reference one token as a checked half-open source byte span.
Tex_Token :: struct {
    kind: Tex_Token_Kind,
    start: int,
    end: int,
}

//   Return the source bytes referenced by one checked token.
tex_token_text :: proc(source: string, token: Tex_Token) -> string {
    if token.start < 0 || token.end < token.start || token.end > len(source) {
        return ""
    }
    return source[token.start:token.end]
}

//   Read one bounded token and advance the cursor on success.
tex_cursor_next_token :: proc(cursor: ^Tex_Cursor) -> (Tex_Token, Tex_Parse_Status) {
    if cursor == nil || cursor.status != .Ok {
        return {}, .Unexpected_Token
    }
    if cursor.offset >= len(cursor.source) {
        return {kind = .End, start = cursor.offset, end = cursor.offset}, .End
    }
    if !tex_cursor_charge(cursor) {
        return {}, cursor.status
    }
    kind, punctuation := tex_token_punctuation_kind(cursor.source[cursor.offset])
    if punctuation {
        token := Tex_Token{kind = kind, start = cursor.offset, end = cursor.offset + 1}
        cursor.offset += 1
        return token, .Ok
    }
    if cursor.source[cursor.offset] == '\\' {
        return tex_cursor_read_command(cursor)
    }
    return tex_cursor_read_text(cursor)
}

//   Classify one ASCII punctuation byte used by the recursive grammar.
tex_token_punctuation_kind :: proc(value: u8) -> (Tex_Token_Kind, bool) {
    switch value {
    case '{': return .Left_Brace, true
    case '}': return .Right_Brace, true
    case '^': return .Superscript, true
    case '_': return .Subscript, true
    case '[': return .Left_Bracket, true
    case ']': return .Right_Bracket, true
    case '&': return .Alignment, true
    }
    return .End, false
}

//   Read a control word, one-character control symbol, or trailing slash text.
tex_cursor_read_command :: proc(
    cursor: ^Tex_Cursor) -> (Tex_Token, Tex_Parse_Status) {
    start := cursor.offset
    cursor.offset += 1
    if cursor.offset >= len(cursor.source) {
        return {kind = .Text, start = start, end = cursor.offset}, .Ok
    }
    width := tex_utf8_sequence_width(cursor.source, cursor.offset)
    if width == 0 {
        return {}, tex_cursor_fail(cursor, .Invalid_Utf8, cursor.offset)
    }
    if !tex_command_letter(cursor.source, cursor.offset, width) {
        cursor.offset += width
        return {kind = .Command, start = start, end = cursor.offset}, .Ok
    }
    for cursor.offset < len(cursor.source) {
        width = tex_utf8_sequence_width(cursor.source, cursor.offset)
        if width == 0 {
            return {}, tex_cursor_fail(cursor, .Invalid_Utf8, cursor.offset)
        }
        if !tex_command_letter(cursor.source, cursor.offset, width) {
            break
        }
        cursor.offset += width
        if cursor.offset-start > cursor.limits.command_bytes {
            return {}, tex_cursor_fail(cursor, .Command_Too_Long, start)
        }
    }
    return {kind = .Command, start = start, end = cursor.offset}, .Ok
}

//   Read ordinary text through the next TeX syntax byte.
tex_cursor_read_text :: proc(
    cursor: ^Tex_Cursor) -> (Tex_Token, Tex_Parse_Status) {
    start := cursor.offset
    for cursor.offset < len(cursor.source) {
        _, punctuation := tex_token_punctuation_kind(cursor.source[cursor.offset])
        if punctuation || cursor.source[cursor.offset] == '\\' {
            break
        }
        width := tex_utf8_sequence_width(cursor.source, cursor.offset)
        if width == 0 {
            return {}, tex_cursor_fail(cursor, .Invalid_Utf8, cursor.offset)
        }
        cursor.offset += width
    }
    return {kind = .Text, start = start, end = cursor.offset}, .Ok
}

//   Return whether one scalar belongs to the lexer control-word class.
tex_command_letter :: proc(source: string, offset, width: int) -> bool {
    if width > 1 {
        return true
    }
    value := source[offset]
    return value >= 'A' && value <= 'Z' || value >= 'a' && value <= 'z'
}