package dynview_parse

import "core:testing"

TEX_TEST_BREAK_PATTERN_BYTES :: 10

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

//   Verify document parsing admits exactly 512 alternating text and break runs.
@(test)
tex_parse_document_enforces_exact_run_capacity :: proc(t: ^testing.T) {
    pattern := "x\\newline "
    bytes: [256 * TEX_TEST_BREAK_PATTERN_BYTES + 1]u8
    for index in 0..<256 {
        start := index * TEX_TEST_BREAK_PATTERN_BYTES
        copy(bytes[start:start+TEX_TEST_BREAK_PATTERN_BYTES],
            transmute([]u8)pattern)
    }
    output := tex_math_test_output()
    defer free(output)
    testing.expect_value(t, tex_parse_document(
        string(bytes[:len(bytes)-1]), output), Tex_Parse_Status.Ok)
    testing.expect_value(t, output.document_run_count, TEX_DOCUMENT_RUN_CAPACITY)
    bytes[len(bytes)-1] = 'x'
    testing.expect_value(t, tex_parse_document(
        string(bytes[:]), output), Tex_Parse_Status.Work_Limit)
    testing.expect_value(t, output.document_run_count, 0)
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