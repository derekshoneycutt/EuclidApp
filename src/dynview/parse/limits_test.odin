package dynview_parse

import "core:testing"

//   Verify recursive math depth admits the configured maximum and rejects one more.
@(test)
tex_parse_math_enforces_exact_depth_limit :: proc(t: ^testing.T) {
    output := tex_math_test_output()
    defer free(output)
    limits := TEX_PARSE_DEFAULT_LIMITS
    limits.depth = 1
    testing.expect_value(t, tex_parse_math(
        "{x}", .Display, output, limits), Tex_Parse_Status.Ok)
    testing.expect_value(t, tex_parse_math(
        "{{x}}", .Display, output, limits), Tex_Parse_Status.Work_Limit)
}

//   Verify the operation pool admits its exact capacity and rejects one more atom.
@(test)
tex_parse_math_enforces_exact_node_capacity :: proc(t: ^testing.T) {
    bytes: [TEX_MATH_OP_CAPACITY + 1]u8
    for index in 0..<len(bytes) {
        bytes[index] = 'a' if index%2 == 0 else '+'
    }
    output := tex_math_test_output()
    defer free(output)
    testing.expect_value(t, tex_parse_math(
        string(bytes[:TEX_MATH_OP_CAPACITY]), .Display, output),
        Tex_Parse_Status.Ok)
    testing.expect_value(t, output.op_count, TEX_MATH_OP_CAPACITY)
    testing.expect_value(t, tex_parse_math(
        string(bytes[:]), .Display, output), Tex_Parse_Status.Work_Limit)
}

//   Verify semantic block storage admits its exact capacity and no more.
@(test)
tex_semantic_builder_enforces_exact_document_block_capacity :: proc(t: ^testing.T) {
    output := tex_math_test_output()
    defer free(output)
    testing.expect(t, tex_semantic_output_init(output))
    for index in 0..<TEX_DOCUMENT_BLOCK_CAPACITY {
        testing.expect(t, tex_semantic_append_document_block(output, {
            kind = .Paragraph,
            inline_start = output.document_inline_count,
            source = {index, 1},
        }) >= 0)
    }
    testing.expect_value(t, output.document_block_count,
        TEX_DOCUMENT_BLOCK_CAPACITY)
    testing.expect_value(t, tex_semantic_append_document_block(output, {}), -1)
    testing.expect_value(t, output.status, Tex_Parse_Status.Work_Limit)
}

//   Verify inline overflow rejects the complete semantic document.
@(test)
tex_parse_document_enforces_exact_inline_capacity :: proc(t: ^testing.T) {
    bytes: [TEX_DOCUMENT_INLINE_CAPACITY + 1]u8
    for index in 0..<len(bytes) {
        bytes[index] = 'x' if index%2 == 0 else ' '
    }
    bytes[TEX_DOCUMENT_INLINE_CAPACITY-1] = '~'
    output := tex_math_test_output()
    defer free(output)
    testing.expect_value(t, tex_parse_document(
        string(bytes[:TEX_DOCUMENT_INLINE_CAPACITY]), output),
        Tex_Parse_Status.Ok)
    testing.expect_value(t, output.document_inline_count,
        TEX_DOCUMENT_INLINE_CAPACITY)
    testing.expect_value(t, tex_parse_document(string(bytes[:]), output),
        Tex_Parse_Status.Work_Limit)
    testing.expect_value(t, output.document_block_count, 0)
    testing.expect_value(t, output.document_inline_count, 0)
}

// Verify semantic display-row storage admits its exact capacity and no more.
@(test)
tex_semantic_builder_enforces_exact_display_row_capacity :: proc(t: ^testing.T) {
    output := tex_math_test_output()
    defer free(output)
    testing.expect(t, tex_semantic_output_init(output))
    for index in 0..<TEX_DOCUMENT_DISPLAY_ROW_CAPACITY {
        testing.expect(t, tex_semantic_append_document_display_row(output, {
            source = {index, 1}, primary_program = index,
        }) >= 0)
    }
    testing.expect_value(t, output.document_display_row_count,
        TEX_DOCUMENT_DISPLAY_ROW_CAPACITY)
    testing.expect_value(t, tex_semantic_append_document_display_row(output, {}), -1)
    testing.expect_value(t, output.status, Tex_Parse_Status.Work_Limit)
}

//   Verify semantic text storage admits its exact byte capacity and no more.
@(test)
tex_semantic_builder_enforces_exact_text_capacity :: proc(t: ^testing.T) {
    bytes: [TEX_SEMANTIC_TEXT_BYTE_CAPACITY + 1]u8
    output := tex_math_test_output()
    defer free(output)
    testing.expect(t, tex_semantic_output_init(output))
    _, exact_ok := tex_semantic_append_text(
        output, string(bytes[:TEX_SEMANTIC_TEXT_BYTE_CAPACITY]))
    testing.expect(t, exact_ok)
    _, excess_ok := tex_semantic_append_text(output, string(bytes[:1]))
    testing.expect(t, !excess_ok)
    testing.expect_value(t, output.status, Tex_Parse_Status.Work_Limit)
}

//   Verify a 16-column table is admitted and a seventeenth column is bounded.
@(test)
tex_parse_math_enforces_exact_table_column_limit :: proc(t: ^testing.T) {
    output := tex_math_test_output()
    defer free(output)
    admitted := "\\begin{matrix}a&a&a&a&a&a&a&a&a&a&a&a&a&a&a&a\\end{matrix}"
    excess := "\\begin{matrix}a&a&a&a&a&a&a&a&a&a&a&a&a&a&a&a&a\\end{matrix}"
    testing.expect_value(t, tex_parse_math(
        admitted, .Display, output), Tex_Parse_Status.Ok)
    testing.expect_value(t, tex_parse_math(
        excess, .Display, output), Tex_Parse_Status.Work_Limit)
}