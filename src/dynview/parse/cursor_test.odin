package dynview_parse

import "core:testing"

//   Verify punctuation, control words, symbols, text, and trailing slash parity.
@(test)
tex_parse_tokens_match_legacy_lexer :: proc(t: ^testing.T) {
    source := "α+{x}_2\\alpha \\,\\"
    cursor: Tex_Cursor
    testing.expect_value(t, tex_cursor_init(&cursor, source), Tex_Parse_Status.Ok)
    expected_kinds := [?]Tex_Token_Kind{
        .Text, .Left_Brace, .Text, .Right_Brace, .Subscript,
        .Text, .Command, .Text, .Command, .Text,
    }
    expected_text := [?]string{
        "α+", "{", "x", "}", "_", "2", "\\alpha", " ", "\\,", "\\",
    }
    for index in 0..<len(expected_kinds) {
        token, status := tex_cursor_next_token(&cursor)
        testing.expect_value(t, status, Tex_Parse_Status.Ok)
        testing.expect_value(t, token.kind, expected_kinds[index])
        testing.expect_value(t, tex_token_text(source, token), expected_text[index])
    }
    _, status := tex_cursor_next_token(&cursor)
    testing.expect_value(t, status, Tex_Parse_Status.End)
}

//   Verify malformed UTF-8 reports the exact byte without advancing past it.
@(test)
tex_parse_cursor_rejects_malformed_utf8 :: proc(t: ^testing.T) {
    cursor: Tex_Cursor
    testing.expect_value(t, tex_cursor_init(&cursor, "x\xc3"), Tex_Parse_Status.Ok)
    _, status := tex_cursor_next_token(&cursor)
    testing.expect_value(t, status, Tex_Parse_Status.Invalid_Utf8)
    testing.expect_value(t, cursor.error_offset, 1)
    testing.expect_value(t, cursor.offset, 1)
}

//   Verify source, work, and command limits fail before excess consumption.
@(test)
tex_parse_cursor_enforces_lexical_limits :: proc(t: ^testing.T) {
    limits := Tex_Parse_Limits{
        source_bytes = 3,
        work_units = 1,
        command_bytes = 2,
        depth = 1,
    }
    cursor: Tex_Cursor
    testing.expect_value(t, tex_cursor_init(
        &cursor, "four", limits), Tex_Parse_Status.Source_Too_Large)
    testing.expect_value(t, tex_cursor_init(&cursor, "{}", limits), Tex_Parse_Status.Ok)
    _, first_status := tex_cursor_next_token(&cursor)
    _, second_status := tex_cursor_next_token(&cursor)
    testing.expect_value(t, first_status, Tex_Parse_Status.Ok)
    testing.expect_value(t, second_status, Tex_Parse_Status.Work_Limit)

    limits.source_bytes = 8
    limits.work_units = 8
    limits.command_bytes = 4
    testing.expect_value(t, tex_cursor_init(
        &cursor, "\\abc", limits), Tex_Parse_Status.Ok)
    _, exact_command_status := tex_cursor_next_token(&cursor)
    testing.expect_value(t, exact_command_status, Tex_Parse_Status.Ok)
    limits.command_bytes = 3
    testing.expect_value(t, tex_cursor_init(
        &cursor, "\\abc", limits), Tex_Parse_Status.Ok)
    _, command_status := tex_cursor_next_token(&cursor)
    testing.expect_value(t, command_status, Tex_Parse_Status.Command_Too_Long)
}