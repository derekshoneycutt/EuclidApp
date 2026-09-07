package dynview_parse

import "core:testing"

//   Verify nested styles and inline math publish ordered semantic inlines.
@(test)
tex_parse_document_matches_styled_mixed_fixture :: proc(t: ^testing.T) {
    output := tex_math_test_output()
    defer free(output)
    source := "\\textbf{Title} plain \\textit{italic} and $x^2$."
    testing.expect_value(t, tex_parse_document(source, output), Tex_Parse_Status.Ok)
    testing.expect_value(t, output.document_block_count, 1)
    block := output.document_blocks[0]
    testing.expect_value(t, block.inline_count, 10)
    testing.expect_value(t, tex_semantic_text(
        output, output.document_inlines[0].text), "Title")
    testing.expect_value(t, output.document_inlines[0].font_flags, i32(36))
    testing.expect_value(t, tex_semantic_text(
        output, output.document_inlines[1].text), " ")
    testing.expect_value(t, tex_semantic_text(
        output, output.document_inlines[4].text), "italic")
    testing.expect_value(t, output.document_inlines[4].font_flags, i32(5))
    math_inline := output.document_inlines[8]
    testing.expect_value(t, math_inline.kind, Tex_Document_Inline_Kind.Math)
    testing.expect_value(t, math_inline.root_style, Tex_Math_Root_Style.Text)
    root := &output.ops[output.programs[math_inline.math_program].first_op]
    testing.expect_value(t, root.kind, Tex_Math_Op_Kind.Style_Override)
}

//   Verify nested document color inheritance and style flattening.
@(test)
tex_parse_document_matches_colored_nested_fixture :: proc(t: ^testing.T) {
    output := tex_math_test_output()
    defer free(output)
    source := "\\textcolor{julia_blue}{outer \\textbf{bold}} default"
    testing.expect_value(t, tex_parse_document(source, output), Tex_Parse_Status.Ok)
    testing.expect_value(t, output.document_inline_count, 5)
    for index in 0..<3 {
        color := output.document_inlines[index].color
        testing.expect(t, color.present)
        testing.expect_value(t, color.red, u8(64))
        testing.expect_value(t, color.green, u8(99))
        testing.expect_value(t, color.blue, u8(216))
    }
    testing.expect(t, !output.document_inlines[3].color.present)
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
    testing.expect_value(t, output.document_inline_count, 9)
    point := output.document_inlines[0].shape
    line := output.document_inlines[2].shape
    circle := output.document_inlines[4].shape
    box := output.document_inlines[6].shape
    semicircle := output.document_inlines[8].shape
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

//   Verify the complete generated Colors.jl registry and explicit Julia aliases.
@(test)
tex_parse_document_accepts_named_shape_colors :: proc(t: ^testing.T) {
    testing.expect_value(t, len(TEX_NAMED_COLORS), 666)
    cases := [?]struct {
        name: string,
        red, green, blue: u8,
    }{
        {"aliceblue", 240, 248, 255},
        {"antiquewhite4", 139, 131, 120},
        {"gray0", 0, 0, 0},
        {"gray100", 255, 255, 255},
        {"grey60", 153, 153, 153},
        {"rebeccapurple", 102, 51, 153},
        {"yellowgreen", 154, 205, 50},
        {"julia_blue", 64, 99, 216},
        {"julia_green", 56, 152, 38},
        {"julia_purple", 149, 88, 178},
        {"julia_red", 203, 60, 51},
    }
    output := tex_math_test_output()
    defer free(output)
    for test_case in cases {
        color, ok := tex_document_resolve_color(test_case.name)
        testing.expect(t, ok)
        testing.expect_value(t, color.red, test_case.red)
        testing.expect_value(t, color.green, test_case.green)
        testing.expect_value(t, color.blue, test_case.blue)
    }
    testing.expect_value(t, tex_parse_document(
        "\\euclidcircle[color=rebeccapurple,size=2]", output),
        Tex_Parse_Status.Ok)
    shape := output.document_inlines[0].shape
    testing.expect_value(t, shape.color.red, u8(102))
    testing.expect_value(t, shape.color.green, u8(51))
    testing.expect_value(t, shape.color.blue, u8(153))
}

//   Verify forced and paragraph breaks retain distinct semantic structure.
@(test)
tex_parse_document_matches_line_break_fixture :: proc(t: ^testing.T) {
    output := tex_math_test_output()
    defer free(output)
    testing.expect_value(t, tex_parse_document(
        "first\\\\\n\nsecond", output), Tex_Parse_Status.Ok)
    testing.expect_value(t, output.document_block_count, 2)
    testing.expect_value(t, output.document_blocks[0].inline_count, 2)
    testing.expect_value(t, output.document_inlines[1].kind,
        Tex_Document_Inline_Kind.Forced_Break)
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
    testing.expect_value(t, output.document_block_count, 3)
    first := output.document_blocks[0]
    display := output.document_blocks[2]
    testing.expect_value(t, output.document_inlines[
        first.inline_start+4].kind, Tex_Document_Inline_Kind.Math)
    testing.expect_value(t, display.kind, Tex_Document_Block_Kind.Display)
    display_inline := output.document_inlines[display.inline_start]
    testing.expect_value(t, display_inline.root_style, Tex_Math_Root_Style.Display)
    display_program := display_inline.math_program
    display_op := &output.ops[output.programs[display_program].first_op]
    testing.expect_value(t, display_op.kind, Tex_Math_Op_Kind.Fraction)
}

//   Verify the composition fixture publishes paragraph and display blocks only.
@(test)
tex_parse_document_matches_composition_baseline :: proc(t: ^testing.T) {
    output := tex_math_test_output()
    defer free(output)
    source := "First line with tall inline math $\\dfrac{a}{b}$ and a shape\n" +
        "\\euclidcircle[color=steelblue,size=2].\n" +
        "Second source line, same paragraph.\n\n" +
        "Second paragraph before a display.\n" +
        "\\[\\sum_{i=1}^{n} i = \\frac{n(n+1)}{2}\\]\n" +
        "Final paragraph."
    testing.expect_value(t, tex_parse_document(source, output), Tex_Parse_Status.Ok)
    testing.expect_value(t, output.document_block_count, 4)
    expected_kinds := [?]Tex_Document_Block_Kind{
        .Paragraph, .Paragraph, .Display, .Paragraph}
    for block, index in output.document_blocks[:output.document_block_count] {
        testing.expect_value(t, block.kind, expected_kinds[index])
    }
    display := output.document_blocks[2]
    testing.expect_value(t, output.document_inlines[
        display.inline_start].root_style, Tex_Math_Root_Style.Display)
}

//   Verify semantic blocks preserve paragraph, display, space, and break intent.
@(test)
tex_parse_document_builds_semantic_blocks :: proc(t: ^testing.T) {
    output := tex_math_test_output()
    defer free(output)
    source := "one two\\\\\nthree\n\nfour\n\\[x^2\\]\nfive~six"
    testing.expect_value(t, tex_parse_document(source, output), Tex_Parse_Status.Ok)
    testing.expect_value(t, output.document_block_count, 4)
    expected_blocks := [?]Tex_Document_Block_Kind{
        .Paragraph, .Paragraph, .Display, .Paragraph,
    }
    for block, index in output.document_blocks[:output.document_block_count] {
        testing.expect_value(t, block.kind, expected_blocks[index])
    }
    testing.expect_value(t, output.document_blocks[0].format.alignment,
        Tex_Document_Alignment.Left)
    first := output.document_blocks[0]
    testing.expect_value(t, first.inline_count, 5)
    testing.expect_value(t, output.document_inlines[
        first.inline_start + 1].space_kind, Tex_Document_Space_Kind.Breakable)
    testing.expect_value(t, output.document_inlines[
        first.inline_start + 3].kind, Tex_Document_Inline_Kind.Forced_Break)
    display := output.document_blocks[2]
    testing.expect_value(t, display.inline_count, 1)
    testing.expect_value(t, display.format.alignment,
        Tex_Document_Alignment.Center)
    testing.expect_value(t, output.document_inlines[
        display.inline_start].root_style, Tex_Math_Root_Style.Display)
    last := output.document_blocks[3]
    testing.expect_value(t, output.document_inlines[
        last.inline_start + 1].space_kind, Tex_Document_Space_Kind.Nonbreaking)
}

//   Verify explicit paragraph commands produce semantic boundaries.
@(test)
tex_parse_document_accepts_explicit_paragraphs :: proc(t: ^testing.T) {
    output := tex_math_test_output()
    defer free(output)
    testing.expect_value(t, tex_parse_document(
        "first\\par second", output), Tex_Parse_Status.Ok)
    testing.expect_value(t, output.document_block_count, 2)
    testing.expect_value(t, output.document_blocks[0].inline_count, 1)
    testing.expect_value(t, output.document_blocks[1].inline_count, 1)
}

// Verify Phase 8 prose syntax preserves scoped style, spaces, and literal text.
@(test)
tex_parse_document_accepts_familiar_prose_syntax :: proc(t: ^testing.T) {
    output := tex_math_test_output()
    defer free(output)
    source := "{\\bfseries bold {\\itshape both} bold} " +
        "\\textnormal{normal} \\texttt{mono} \\%\\#\\_\\&\\{\\}~x\\ y%gone\n z"

    status := tex_parse_document(source, output)

    testing.expect_value(t, status, Tex_Parse_Status.Ok)
    testing.expect_value(t, tex_semantic_text(
        output, output.document_inlines[0].text), "bold")
    testing.expect_value(t, output.document_inlines[0].font_flags, i32(36))
    testing.expect_value(t, output.document_inlines[2].font_flags, i32(37))
    testing.expect_value(t, output.document_inlines[4].font_flags, i32(36))
    testing.expect_value(t, output.document_inlines[6].font_flags, i32(4))
    testing.expect_value(t, output.document_inlines[8].font_flags, i32(4))
    nonbreaking_count := 0
    controlled_count := 0
    escaped_special_count := 0
    comment_text_found := false
    for inline_index in 0..<output.document_inline_count {
        semantic_inline := output.document_inlines[inline_index]
        if semantic_inline.kind == .Space {
            if semantic_inline.space_kind == .Nonbreaking {nonbreaking_count += 1}
            if semantic_inline.space_kind == .Controlled {controlled_count += 1}
        } else if semantic_inline.kind == .Text {
            text := tex_semantic_text(output, semantic_inline.text)
            if text == "%" || text == "#" || text == "_" || text == "&" ||
                text == "{" || text == "}" {escaped_special_count += 1}
            if text == "gone" {comment_text_found = true}
        }
    }
    testing.expect_value(t, nonbreaking_count, 1)
    testing.expect_value(t, controlled_count, 1)
    testing.expect_value(t, escaped_special_count, 6)
    testing.expect(t, !comment_text_found)
}

// Verify alignment environments and no-indent publish block-level semantics.
@(test)
tex_parse_document_accepts_alignment_and_noindent :: proc(t: ^testing.T) {
    output := tex_math_test_output()
    defer free(output)
    source := "\\noindent left\\par" +
        "\\begin{center}middle\\end{center}" +
        "\\begin{flushright}right\\end{flushright}" +
        "\\begin{flushleft}again\\end{flushleft}"

    status := tex_parse_document(source, output)

    testing.expect_value(t, status, Tex_Parse_Status.Ok)
    testing.expect_value(t, output.document_block_count, 4)
    testing.expect(t, output.document_blocks[0].format.no_indent)
    testing.expect_value(t, output.document_blocks[1].format.alignment,
        Tex_Document_Alignment.Center)
    testing.expect_value(t, output.document_blocks[2].format.alignment,
        Tex_Document_Alignment.Right)
    testing.expect_value(t, output.document_blocks[3].format.alignment,
        Tex_Document_Alignment.Left)
}

// Verify unavailable faces and malformed environment boundaries fail completely.
@(test)
tex_parse_document_rejects_unavailable_prose_faces :: proc(t: ^testing.T) {
    cases := [?]string{
        "\\textrm{roman}", "\\textsc{caps}",
        "\\begin{center}open", "\\end{center}",
        "\\begin{center}wrong\\end{flushright}",
    }
    output := tex_math_test_output()
    defer free(output)
    for source in cases {
        testing.expect(t, tex_parse_document(source, output) != .Ok)
        testing.expect_value(t, output.document_block_count, 0)
        testing.expect_value(t, output.document_inline_count, 0)
    }
}

// Verify equation environments publish one native display row without prose breaks.
@(test)
tex_parse_document_accepts_equation_environments :: proc(t: ^testing.T) {
    output := tex_math_test_output()
    defer free(output)
    cases := [?]string{
        "\\begin{equation}x=1\\end{equation}",
        "\\begin{equation*}y=2\\end{equation*}",
    }
    for source in cases {
        status := tex_parse_document(source, output)
        testing.expect_value(t, status, Tex_Parse_Status.Ok)
        testing.expect_value(t, output.document_block_count, 1)
        testing.expect_value(t, output.document_blocks[0].kind,
            Tex_Document_Block_Kind.Display)
        testing.expect_value(t, output.document_blocks[0].inline_count, 1)
        testing.expect_value(t, output.document_inlines[0].kind,
            Tex_Document_Inline_Kind.Math)
        testing.expect_value(t, output.document_blocks[0].display_kind,
            Tex_Document_Display_Kind.Equation)
        testing.expect_value(t, output.document_blocks[0].display_row_count, 1)
        testing.expect_value(t, output.document_blocks[0].display_numbered,
            source == cases[0])
    }
}

// Verify technical displays retain bounded rows, alignment halves, and notag intent.
@(test)
tex_parse_document_accepts_technical_display_rows :: proc(t: ^testing.T) {
    output := tex_math_test_output()
    defer free(output)
    source := "\\begin{align}a&=b\\\\c&=\\begin{matrix}1&2\\\\3&4" +
        "\\end{matrix}\\notag\\end{align}" +
        "\\begin{gather*}x=1\\\\y=2\\end{gather*}" +
        "\\begin{multline}p+q\\\\r+s\\\\t+u\\end{multline}"

    status := tex_parse_document(source, output)

    testing.expect_value(t, status, Tex_Parse_Status.Ok)
    testing.expect_value(t, output.document_block_count, 3)
    testing.expect_value(t, output.document_display_row_count, 7)
    align_block := output.document_blocks[0]
    testing.expect_value(t, align_block.display_kind, Tex_Document_Display_Kind.Align)
    testing.expect_value(t, align_block.display_row_count, 2)
    testing.expect(t, align_block.display_numbered)
    testing.expect(t, output.document_display_rows[0].secondary_program >= 0)
    testing.expect(t, output.document_display_rows[1].suppress_number)
    gather_block := output.document_blocks[1]
    testing.expect_value(t, gather_block.display_kind,
        Tex_Document_Display_Kind.Gather)
    testing.expect(t, !gather_block.display_numbered)
    multline_start := output.document_blocks[2].display_row_start
    testing.expect_value(t, output.document_display_rows[
        multline_start].alignment, Tex_Document_Alignment.Left)
    testing.expect_value(t, output.document_display_rows[
        multline_start+1].alignment, Tex_Document_Alignment.Center)
    testing.expect_value(t, output.document_display_rows[
        multline_start+2].alignment, Tex_Document_Alignment.Right)
}

// Verify malformed rows and excluded numbering controls reject complete documents.
@(test)
tex_parse_document_rejects_invalid_technical_displays :: proc(t: ^testing.T) {
    output := tex_math_test_output()
    defer free(output)
    cases := [?]string{
        "\\begin{equation}a\\\\b\\end{equation}",
        "\\begin{align}a=b\\end{align}",
        "\\begin{gather}a&=b\\end{gather}",
        "\\begin{multline}a\\notag\\end{multline}",
        "\\begin{equation}a\\tag{A}\\end{equation}",
        "\\begin{align}a&=b\\end{gather}",
    }
    for source in cases {
        testing.expect(t, tex_parse_document(source, output) != .Ok)
        testing.expect_value(t, output.document_block_count, 0)
        testing.expect_value(t, output.document_inline_count, 0)
        testing.expect_value(t, output.document_display_row_count, 0)
    }
}

//   Verify styled text, inline math, and shapes retain ordered source semantics.
@(test)
tex_parse_document_preserves_semantic_inline_details :: proc(t: ^testing.T) {
    output := tex_math_test_output()
    defer free(output)
    source := "\\textbf{bold} $x$ \\euclidpoint[color=steelblue,size=1]"
    testing.expect_value(t, tex_parse_document(source, output), Tex_Parse_Status.Ok)
    block := output.document_blocks[0]
    testing.expect_value(t, block.inline_count, 5)
    text := output.document_inlines[block.inline_start]
    math := output.document_inlines[block.inline_start + 2]
    shape := output.document_inlines[block.inline_start + 4]
    testing.expect_value(t, text.kind, Tex_Document_Inline_Kind.Text)
    testing.expect_value(t, text.font_flags,
        TEX_DOCUMENT_STYLE_REGULAR | TEX_DOCUMENT_STYLE_BOLD)
    testing.expect_value(t, source[
        text.source.offset:text.source.offset + text.source.length], "bold")
    testing.expect_value(t, math.kind, Tex_Document_Inline_Kind.Math)
    testing.expect_value(t, math.root_style, Tex_Math_Root_Style.Text)
    testing.expect(t, math.math_program >= 0)
    testing.expect_value(t, shape.kind, Tex_Document_Inline_Kind.Shape)
    testing.expect_value(t, shape.shape.kind, Tex_Document_Shape_Kind.Point)
    testing.expect(t, shape.shape.color.present)
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

// Verify group inverse and associativity documents remain native semantic input.
@(test)
tex_parse_document_accepts_group_latex_views :: proc(t: ^testing.T) {
    inverse := "\\textbf{Inverse}\n\nAn inverse is the motion that undoes a given " +
        "motion. In $\\mathbb{Z}_2$, every element is its own inverse.\n\n" +
        "For an element $a$ in a group, an inverse $a^{-1}$ is an element such " +
        "that\n$a \\circ a^{-1} = a^{-1} \\circ a = e$, where $e$ is the " +
        "identity.\n\n1. $e^{-1} = e$: doing nothing undoes itself.\\\\\n" +
        "2. $r^{-1} = r$: one reflection undoes itself."
    associative := "\\textbf{Associativity}\n\nAssociativity means the grouping " +
        "of the operation does not matter:\n\n$$(a \\circ b) \\circ c = " +
        "a \\circ (b \\circ c)\\; \\text{for all}\\; a,b,c$$\n\n" +
        "Left grouping: $(\\rho^1\\rho^2)\\rho^3 = \\rho^6$."
    output := tex_math_test_output()
    defer free(output)

    cases := [?]string{inverse, associative}
    for source in cases {
        testing.expect_value(t, tex_parse_document(source, output), Tex_Parse_Status.Ok)
        for item in output.document_inlines[:output.document_inline_count] {
            if item.kind == .Text || item.kind == .Space {
                testing.expect(t, item.text.length > 0)
            }
        }
    }
}

//   Verify malformed document fixtures reject without publishing structured semantics.
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
        testing.expect_value(t, output.document_block_count, 0)
        testing.expect_value(t, output.document_inline_count, 0)
    }
}

//   Verify whole-math delimiters win over document marker classification.
@(test)
tex_classify_source_mode_matches_frozen_rules :: proc(t: ^testing.T) {
    testing.expect_value(t, tex_classify_source_mode("$x^2$"), Tex_Source_Mode.Math)
    testing.expect_value(t, tex_classify_source_mode("\\[x^2\\]"), Tex_Source_Mode.Math)
    testing.expect_value(t, tex_classify_source_mode(
        "\\begin{array}{@{}||l|r||@{}}\\hline x&\\frac{1}{2}\\\\[1em]" +
        "\\hline y&\\sqrt{z}\\\\[-1pt]\\hline\\hline\\end{array}"),
        Tex_Source_Mode.Math)
    testing.expect_value(t, tex_classify_source_mode(
        "\\begin{align}a&=b\\\\c&=d\\end{align}"), Tex_Source_Mode.Document)
    testing.expect_value(t, tex_classify_source_mode(
        "text $x^2$"), Tex_Source_Mode.Document)
    testing.expect_value(t, tex_classify_source_mode("x^2"), Tex_Source_Mode.Math)
}