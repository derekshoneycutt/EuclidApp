package dynview_parse

import "core:testing"

//   Verify nested styles and inline math match the frozen mixed document runs.
@(test)
tex_parse_document_matches_styled_mixed_fixture :: proc(t: ^testing.T) {
    output := tex_math_test_output()
    defer free(output)
    source := "\\textbf{Title} plain \\textit{italic} and $x^2$."
    testing.expect_value(t, tex_parse_document(source, output), Tex_Parse_Status.Ok)
    testing.expect_value(t, output.document_run_count, 6)
    expected_text := [?]string{"Title", " plain ", "italic", " and ", "x^2", "."}
    expected_flags := [?]i32{36, 4, 5, 4, 4, 4}
    for index in 0..<len(expected_text) {
        testing.expect_value(t, tex_semantic_text(
            output, output.document_runs[index].text), expected_text[index])
        testing.expect_value(t, output.document_runs[index].font_flags,
            expected_flags[index])
    }
    math_run := &output.document_runs[4]
    testing.expect_value(t, math_run.kind, Tex_Document_Run_Kind.Math_Inline)
    testing.expect_value(t, math_run.root_style, Tex_Math_Root_Style.Text)
    root := &output.ops[output.programs[math_run.math_program].first_op]
    testing.expect_value(t, root.kind, Tex_Math_Op_Kind.Style_Override)
}

//   Verify nested document color inheritance and style flattening.
@(test)
tex_parse_document_matches_colored_nested_fixture :: proc(t: ^testing.T) {
    output := tex_math_test_output()
    defer free(output)
    source := "\\textcolor{julia_blue}{outer \\textbf{bold}} default"
    testing.expect_value(t, tex_parse_document(source, output), Tex_Parse_Status.Ok)
    testing.expect_value(t, output.document_run_count, 3)
    for index in 0..<2 {
        color := output.document_runs[index].color
        testing.expect(t, color.present)
        testing.expect_value(t, color.red, u8(64))
        testing.expect_value(t, color.green, u8(99))
        testing.expect_value(t, color.blue, u8(216))
    }
    testing.expect(t, !output.document_runs[2].color.present)
}

//   Verify representative Euclid shape defaults and explicit options.
@(test)
tex_parse_document_matches_shapes_fixture :: proc(t: ^testing.T) {
    output := tex_math_test_output()
    defer free(output)
    source := "\\euclidpoint[color=steelblue,size=1] " +
        "\\euclidline[length=4,thickness=2] " +
        "\\euclidcircle[color=khaki3,size=2,filled] " +
        "\\euclidbox[width=3,height=2,thickness=1,filled=false] " +
        "\\euclidsemicircle[color=steelblue,radius=2,thickness=2]"
    testing.expect_value(t, tex_parse_document(source, output), Tex_Parse_Status.Ok)
    testing.expect_value(t, output.document_run_count, 9)
    point := output.document_runs[0].shape
    line := output.document_runs[2].shape
    circle := output.document_runs[4].shape
    box := output.document_runs[6].shape
    semicircle := output.document_runs[8].shape
    testing.expect_value(t, point.kind, Tex_Document_Shape_Kind.Point)
    testing.expect(t, point.filled && point.color.present)
    testing.expect_value(t, line.width, f32(4))
    testing.expect_value(t, line.thickness, f32(2))
    testing.expect_value(t, circle.width, f32(2))
    testing.expect(t, circle.filled)
    testing.expect_value(t, box.height, f32(2))
    testing.expect(t, !box.filled)
    testing.expect_value(t, semicircle.kind, Tex_Document_Shape_Kind.Semicircle)
    testing.expect_value(t, semicircle.start_angle, f32(0))
    testing.expect_value(t, semicircle.end_angle, f32(180))
}

//   Verify every literal color used by authored TeX shape commands remains supported.
@(test)
tex_parse_document_accepts_authored_shape_colors :: proc(t: ^testing.T) {
    names := [?]string{
        "steelblue", "khaki3", "palevioletred1", "grey", "grey60",
        "plum1", "lightgreen", "firebrick",
    }
    output := tex_math_test_output()
    defer free(output)
    for name in names {
        _, ok := tex_document_resolve_color(name)
        testing.expect(t, ok)
    }
}

//   Verify forced and paragraph breaks collapse to one blank line.
@(test)
tex_parse_document_matches_line_break_fixture :: proc(t: ^testing.T) {
    output := tex_math_test_output()
    defer free(output)
    testing.expect_value(t, tex_parse_document(
        "first\\\\\n\nsecond", output), Tex_Parse_Status.Ok)
    testing.expect_value(t, output.document_run_count, 4)
    testing.expect_value(t, output.document_runs[1].kind,
        Tex_Document_Run_Kind.Line_Break)
    testing.expect_value(t, output.document_runs[2].kind,
        Tex_Document_Run_Kind.Line_Break)
}

//   Verify the prime document preserves inline/display math and shape ordering.
@(test)
tex_parse_document_matches_prime_fixture :: proc(t: ^testing.T) {
    output := tex_math_test_output()
    defer free(output)
    source := "\\textbf{Euclid} \\textit{document} " +
        "$x_1^2 \\in \\mathbb{R}$\n\n" +
        "\\euclidpoint[color=steelblue,size=1] " +
        "\\euclidline[color=steelblue,length=3,thickness=2]\n\n" +
        "$$\\frac{a+b}{\\sqrt{c}}$$"
    testing.expect_value(t, tex_parse_document(source, output), Tex_Parse_Status.Ok)
    testing.expect_value(t, output.document_run_count, 13)
    testing.expect_value(t, output.document_runs[4].kind,
        Tex_Document_Run_Kind.Math_Inline)
    testing.expect_value(t, output.document_runs[12].kind,
        Tex_Document_Run_Kind.Math_Display)
    display_program := output.document_runs[12].math_program
    display_op := &output.ops[output.programs[display_program].first_op]
    testing.expect_value(t, display_op.kind, Tex_Math_Op_Kind.Fraction)
}

//   Verify each structured prime-document component parses independently.
@(test)
tex_parse_document_accepts_prime_components :: proc(t: ^testing.T) {
    output := tex_math_test_output()
    defer free(output)
    testing.expect_value(t, tex_parse_document(
        "$x_1^2 \\in \\mathbb{R}$", output), Tex_Parse_Status.Ok)
    testing.expect_value(t, tex_parse_document(
        "\\euclidpoint[color=steelblue,size=1] " +
        "\\euclidline[color=steelblue,length=3,thickness=2]",
        output), Tex_Parse_Status.Ok)
    testing.expect_value(t, tex_parse_document(
        "$$\\frac{a+b}{\\sqrt{c}}$$", output), Tex_Parse_Status.Ok)
}

//   Verify malformed document fixtures reject atomically with no published runs.
@(test)
tex_parse_document_matches_rejection_fixtures :: proc(t: ^testing.T) {
    cases := [?]string{
        "\\euclidpoint[color=not-a-color]",
        "\\euclidline[size=2]",
        "broken $math",
        "\\section{unsupported}",
        "\\textcolor{red}{unclosed",
    }
    output := tex_math_test_output()
    defer free(output)
    for source in cases {
        testing.expect(t, tex_parse_document(source, output) != .Ok)
        testing.expect_value(t, output.document_run_count, 0)
    }
}

//   Verify whole-math delimiters win over document marker classification.
@(test)
tex_classify_source_mode_matches_frozen_rules :: proc(t: ^testing.T) {
    testing.expect_value(t, tex_classify_source_mode("$x^2$"), Tex_Source_Mode.Math)
    testing.expect_value(t, tex_classify_source_mode("\\[x^2\\]"), Tex_Source_Mode.Math)
    testing.expect_value(t, tex_classify_source_mode(
        "text $x^2$"), Tex_Source_Mode.Document)
    testing.expect_value(t, tex_classify_source_mode("x^2"), Tex_Source_Mode.Math)
}