package dynview_parse

import "core:testing"

// Retain one compact frozen plain-text compatibility case.
Tex_Math_Plain_Test_Case :: struct {
    source: string,
    expected: string,
}

//   Verify every remaining successful math fixture has exact canonical text.
@(test)
tex_parse_math_matches_remaining_success_fixtures :: proc(t: ^testing.T) {
    cases := [?]Tex_Math_Plain_Test_Case{
        {"\\oint_C f+\\iint_D g+\\coprod_i A_i+\\bigcup_i S_i",
            "∮_{C}f+∬_{D}g+∐_{i}{A}_{i}+⋃_{i}{S}_{i}"},
        {"\\sqrt[n]{x+1}", "\\sqrt[n]{x+1}"},
        {"\\left(\\frac{a}{b}\\right)", "\\left({a}/{b}\\right)"},
        {"\\begin{bmatrix}a&b\\\\c&d\\end{bmatrix}",
            "\\left[\\begin{matrix}a&b\\\\c&d\\end{matrix}\\right]"},
        {"\\begin{Bmatrix}a&b\\\\c&d\\end{Bmatrix}+" +
            "\\begin{Vmatrix}1&0\\\\0&1\\end{Vmatrix}",
            "\\left\\{\\begin{matrix}a&b\\\\c&d\\end{matrix}\\right\\}+" +
            "\\left\\|\\begin{matrix}1&0\\\\0&1\\end{matrix}\\right\\|"},
        {"\\overline{AB}+\\underline{CD}",
            "\\overline{AB}+\\underline{CD}"},
        {"\\frac{1}{1+\\frac{1}{x^2}}", "{1}/{1+{1}/{{x}^{2}}}"},
        {"\\begin{array}{||c|c||}\\hline a&b\\\\[1.5em]c&d" +
            "\\\\[-2pt]\\hline\\hline\\end{array}",
            "\\begin{array}{||c|c||}a&b\\\\c&d\\end{array}"},
    }
    output := tex_math_test_output()
    defer free(output)
    for test_case in cases {
        testing.expect_value(t, tex_parse_math(
            test_case.source, .Display, output), Tex_Parse_Status.Ok)
        testing.expect(t, !output.recoverable)
        testing.expect_value(t, tex_semantic_text(
            output, output.plain_text), test_case.expected)
    }
}

//   Verify all frozen malformed math cases retain recoverable canonical output.
@(test)
tex_parse_math_matches_recoverable_fixtures :: proc(t: ^testing.T) {
    cases := [?]Tex_Math_Plain_Test_Case{
        {"\\unsupported{readable}", "\\unsupportedreadable"},
        {"\\frac{a}", "{a}/{}"},
        {"\\begin{matrix}a&b\\\\c\\end{matrix}", "\\begin"},
        {"x^{", "x"},
        {"\\left(x", "\\left(x\\right."},
    }
    output := tex_math_test_output()
    defer free(output)
    for test_case in cases {
        testing.expect_value(t, tex_parse_math(
            test_case.source, .Display, output), Tex_Parse_Status.Ok)
        testing.expect(t, output.recoverable)
        testing.expect_value(t, tex_semantic_text(
            output, output.plain_text), test_case.expected)
    }
}

//   Verify frozen source-style interpretation produces the required root wrapper.
@(test)
tex_parse_math_matches_root_style_fixtures :: proc(t: ^testing.T) {
    output := tex_math_test_output()
    defer free(output)
    testing.expect_value(t, tex_parse_math(
        "x^2", .Display, output), Tex_Parse_Status.Ok)
    display_op := &output.ops[output.programs[output.root_program].first_op]
    testing.expect_value(t, display_op.kind, Tex_Math_Op_Kind.Script)
    testing.expect_value(t, tex_parse_math(
        "x^2", .Text, output), Tex_Parse_Status.Ok)
    text_op := &output.ops[output.programs[output.root_program].first_op]
    testing.expect_value(t, text_op.kind, Tex_Math_Op_Kind.Style_Override)
    testing.expect_value(t, tex_semantic_text(
        output, output.plain_text), "{x}^{2}")
}