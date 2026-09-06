package dynview_parse

import "core:testing"

//   Allocate parser output for one focused test without large stack storage.
tex_math_test_output :: proc() -> ^Tex_Semantic_Output {
    return new(Tex_Semantic_Output)
}

//   Verify the frozen atom-spacing operation sequence and classifications.
@(test)
tex_parse_math_matches_atom_spacing_fixture :: proc(t: ^testing.T) {
    output := tex_math_test_output()
    defer free(output)
    status := tex_parse_math("a+b=c,\\;-a+b", .Display, output)
    testing.expect_value(t, status, Tex_Parse_Status.Ok)
    program := output.programs[output.root_program]
    testing.expect_value(t, program.op_count, 11)
    expected := [?]string{"a", "+", "b", "=", "c", ",", " ", "-", "a", "+", "b"}
    index := program.first_op
    for text in expected {
        testing.expect_value(t, tex_semantic_text(output, output.ops[index].text), text)
        index = output.ops[index].next_op
    }
}

//   Verify scripts preserve base, superscript, and subscript child programs.
@(test)
tex_parse_math_matches_script_fixture :: proc(t: ^testing.T) {
    output := tex_math_test_output()
    defer free(output)
    testing.expect_value(t, tex_parse_math(
        "x_i^2+V_A", .Display, output), Tex_Parse_Status.Ok)
    first := &output.ops[output.programs[output.root_program].first_op]
    testing.expect_value(t, first.kind, Tex_Math_Op_Kind.Script)
    testing.expect_value(t, tex_semantic_text(
        output, first.superscript_text), "2")
    testing.expect_value(t, tex_semantic_text(output, first.subscript_text), "i")
    testing.expect(t, first.child_program >= 0)
    testing.expect(t, first.secondary_program >= 0)
    testing.expect(t, first.tertiary_program >= 0)
}

//   Verify recursive fractions retain canonical child programs and fallback text.
@(test)
tex_parse_math_matches_fraction_fixture :: proc(t: ^testing.T) {
    output := tex_math_test_output()
    defer free(output)
    testing.expect_value(t, tex_parse_math(
        "\\frac{a+b}{c}", .Display, output), Tex_Parse_Status.Ok)
    op := &output.ops[output.programs[output.root_program].first_op]
    testing.expect_value(t, op.kind, Tex_Math_Op_Kind.Fraction)
    testing.expect_value(t, tex_semantic_text(output, op.text), "{a+b}/{c}")
    testing.expect_value(t, output.programs[op.child_program].op_count, 3)
    testing.expect_value(t, output.programs[op.secondary_program].op_count, 1)
}

//   Verify large operators retain independent growth, limits, and script programs.
@(test)
tex_parse_math_matches_operator_fixture :: proc(t: ^testing.T) {
    output := tex_math_test_output()
    defer free(output)
    testing.expect_value(t, tex_parse_math(
        "\\sum_{i=1}^{n}i+\\int_0^1f(x)\\,dx",
        .Display, output), Tex_Parse_Status.Ok)
    first := &output.ops[output.programs[output.root_program].first_op]
    testing.expect_value(t, first.kind, Tex_Math_Op_Kind.Large_Operator)
    testing.expect_value(t, first.large_op_kind, i32(1))
    testing.expect_value(t, first.operator_growth, i32(1))
    testing.expect_value(t, first.operator_limits, i32(2))
    testing.expect_value(t, tex_semantic_text(output, output.plain_text),
        "∑_{i=1}^{n}i+∫_{0}^{1}f(x) dx")
}

//   Verify radical degree and bar accents preserve recursive child programs.
@(test)
tex_parse_math_matches_radical_and_bar_fixtures :: proc(t: ^testing.T) {
    output := tex_math_test_output()
    defer free(output)
    testing.expect_value(t, tex_parse_math(
        "\\sqrt[n]{x+1}", .Display, output), Tex_Parse_Status.Ok)
    radical := &output.ops[output.programs[output.root_program].first_op]
    testing.expect_value(t, radical.radical_mode, Tex_Radical_Mode.Nth_Root)
    testing.expect_value(t, tex_semantic_text(output, radical.text), "x+1")
    testing.expect_value(t, tex_semantic_text(output, radical.radical_index_text), "n")

    testing.expect_value(t, tex_parse_math(
        "\\overline{AB}+\\underline{CD}", .Display, output), Tex_Parse_Status.Ok)
    testing.expect_value(t, tex_semantic_text(output, output.plain_text),
        "\\overline{AB}+\\underline{CD}")
}

//   Verify stretch delimiters preserve both delimiters and recursive content.
@(test)
tex_parse_math_matches_delimiter_fixture :: proc(t: ^testing.T) {
    output := tex_math_test_output()
    defer free(output)
    testing.expect_value(t, tex_parse_math(
        "\\left(\\frac{a}{b}\\right)", .Display, output), Tex_Parse_Status.Ok)
    op := &output.ops[output.programs[output.root_program].first_op]
    testing.expect_value(t, op.kind, Tex_Math_Op_Kind.Stretch_Delimiter)
    testing.expect_value(t, op.left_delimiter, Tex_Delimiter_Kind.Left_Paren)
    testing.expect_value(t, op.right_delimiter, Tex_Delimiter_Kind.Right_Paren)
    testing.expect_value(t, tex_semantic_text(output, op.text),
        "\\left({a}/{b}\\right)")
}

//   Verify caller-selected text style wraps rather than rewrites child semantics.
@(test)
tex_parse_math_matches_text_root_style_fixture :: proc(t: ^testing.T) {
    output := tex_math_test_output()
    defer free(output)
    testing.expect_value(t, tex_parse_math(
        "x^2", .Text, output), Tex_Parse_Status.Ok)
    op := &output.ops[output.programs[output.root_program].first_op]
    testing.expect_value(t, op.kind, Tex_Math_Op_Kind.Style_Override)
    testing.expect_value(t, op.style_level, Tex_Math_Style_Level.Text)
    testing.expect_value(t, tex_semantic_text(output, op.text), "{x}^{2}")
}

//   Verify all explicit style commands scope over the remainder of their group.
@(test)
tex_parse_math_matches_explicit_style_fixtures :: proc(t: ^testing.T) {
    cases := [?]struct {
        source: string,
        level: Tex_Math_Style_Level,
    }{
        {"{\\displaystyle a+b}", .Display},
        {"{\\textstyle a+b}", .Text},
        {"{\\scriptstyle a+b}", .Script},
        {"{\\scriptscriptstyle a+b}", .Script_Script},
    }
    for test_case in cases {
        output := tex_math_test_output()
        testing.expect_value(t, tex_parse_math(
            test_case.source, .Display, output), Tex_Parse_Status.Ok)
        testing.expect(t, !output.recoverable)
        style := &output.ops[output.programs[output.root_program].first_op]
        testing.expect_value(t, style.kind, Tex_Math_Op_Kind.Style_Override)
        testing.expect_value(t, style.style_level, test_case.level)
        testing.expect_value(t, tex_semantic_text(output, style.text), "a+b")
        free(output)
    }
}

//   Verify fraction and binomial variants preserve recursive structure and style.
@(test)
tex_parse_math_matches_fraction_variant_fixtures :: proc(t: ^testing.T) {
    output := tex_math_test_output()
    defer free(output)
    testing.expect_value(t, tex_parse_math(
        "\\dfrac{a}{b}+\\tbinom{n}{k}", .Display, output), Tex_Parse_Status.Ok)
    testing.expect(t, !output.recoverable)
    display := &output.ops[output.programs[output.root_program].first_op]
    testing.expect_value(t, display.kind, Tex_Math_Op_Kind.Style_Override)
    testing.expect_value(t, display.style_level, Tex_Math_Style_Level.Display)
    fraction := &output.ops[output.programs[display.child_program].first_op]
    testing.expect_value(t, fraction.kind, Tex_Math_Op_Kind.Fraction)
    plus_index := display.next_op
    binomial := &output.ops[output.ops[plus_index].next_op]
    testing.expect_value(t, binomial.kind, Tex_Math_Op_Kind.Style_Override)
    testing.expect_value(t, binomial.style_level, Tex_Math_Style_Level.Text)
    delimiter := &output.ops[output.programs[binomial.child_program].first_op]
    testing.expect_value(t, delimiter.kind, Tex_Math_Op_Kind.Stretch_Delimiter)
    stack := &output.ops[output.programs[delimiter.child_program].first_op]
    testing.expect_value(t, stack.kind, Tex_Math_Op_Kind.Stack)
    testing.expect_value(t, tex_semantic_text(output, output.plain_text),
        "{a}/{b}+\\left({n\\atop k}\\right)")
}

//   Verify operator names, glyph accents, and explicit limit policies.
@(test)
tex_parse_math_matches_structured_operator_fixtures :: proc(t: ^testing.T) {
    output := tex_math_test_output()
    defer free(output)
    source := "\\operatorname{rank}_A+\\operatorname*{argmax}\\nolimits_x+" +
        "\\sum\\nolimits_0^1+\\int\\limits_0^1+\\widehat{AB}+\\mathring e"
    testing.expect_value(t, tex_parse_math(source, .Display, output),
        Tex_Parse_Status.Ok)
    testing.expect(t, !output.recoverable)
    testing.expect_value(t, tex_semantic_text(output, output.plain_text),
        "{rank}_{A}+\\operatorname*{argmax}_{x}+∑_{0}^{1}+∫_{0}^{1}+" +
        "\\hat{AB}+\\mathring{e}")
    accent_modes: [2]Tex_Accent_Mode
    accent_count := 0
    index := output.programs[output.root_program].first_op
    for index >= 0 {
        op := &output.ops[index]
        if op.kind == .Accent {
            accent_modes[accent_count] = op.accent_mode
            accent_count += 1
        }
        index = op.next_op
    }
    testing.expect_value(t, accent_count, 2)
    testing.expect_value(t, accent_modes, [2]Tex_Accent_Mode{.Hat, .Ring})
}

//   Verify over/under annotations and brace scripts use stack semantics.
@(test)
tex_parse_math_matches_annotation_fixtures :: proc(t: ^testing.T) {
    output := tex_math_test_output()
    defer free(output)
    testing.expect_value(t, tex_parse_math(
        "\\overset{!}{=}+\\underset{n}{x}+\\overbrace{a+b}^{n}+" +
        "\\underbrace{x+y}_{m}", .Display, output), Tex_Parse_Status.Ok)
    testing.expect(t, !output.recoverable)
    expected_limits := [4]i32{1, 2, 1, 2}
    found := 0
    index := output.programs[output.root_program].first_op
    for index >= 0 {
        op := &output.ops[index]
        if op.kind == .Stack {
            testing.expect_value(t, op.operator_limits, expected_limits[found])
            found += 1
        }
        index = op.next_op
    }
    testing.expect_value(t, found, 4)
}

//   Verify fixed and middle delimiters retain size, class, and shared extent.
@(test)
tex_parse_math_matches_fixed_and_middle_delimiters :: proc(t: ^testing.T) {
    output := tex_math_test_output()
    defer free(output)
    testing.expect_value(t, tex_parse_math(
        "\\bigl( x \\Bigm| y \\biggr)+\\left\\{x \\middle| y " +
        "\\middle\\| z\\right\\}", .Display, output), Tex_Parse_Status.Ok)
    testing.expect(t, !output.recoverable)
    growths: [3]i32
    classes: [3]Tex_Math_Atom_Class
    fixed_count := 0
    root_index := output.programs[output.root_program].first_op
    for root_index >= 0 {
        op := &output.ops[root_index]
        if op.kind == .Stretch_Delimiter && op.operator_growth > 0 {
            growths[fixed_count] = op.operator_growth
            classes[fixed_count] = op.atom_class
            fixed_count += 1
        }
        root_index = op.next_op
    }
    testing.expect_value(t, growths, [3]i32{1, 2, 3})
    testing.expect_value(t, classes, [3]Tex_Math_Atom_Class{.Open, .Rel, .Close})
    testing.expect_value(t, fixed_count, 3)
    outer_child := -1
    root_index = output.programs[output.root_program].first_op
    for root_index >= 0 {
        op := &output.ops[root_index]
        if op.kind == .Stretch_Delimiter && op.operator_growth == 0 &&
            op.child_program >= 0 {
            outer_child = op.child_program
        }
        root_index = op.next_op
    }
    testing.expect(t, outer_child >= 0)
    middle_count := 0
    if outer_child >= 0 {
        child_index := output.programs[outer_child].first_op
        for child_index >= 0 {
            child := &output.ops[child_index]
            if child.kind == .Stretch_Delimiter && child.operator_limits == 1 {
                middle_count += 1
            }
            child_index = child.next_op
        }
    }
    testing.expect_value(t, middle_count, 2)
}

//   Verify command, escaped, and nonbreaking spaces remain distinguishable.
@(test)
tex_parse_math_matches_command_whitespace_fixtures :: proc(t: ^testing.T) {
    cases := [?]Tex_Math_Plain_Test_Case{
        {"\\angle ABC", "∠ABC"},
        {"\\angle\\ ABC", "∠ ABC"},
        {"\\angle~ABC", "∠\u00a0ABC"},
    }
    for test_case in cases {
        output := tex_math_test_output()
        testing.expect_value(t, tex_parse_math(
            test_case.source, .Display, output), Tex_Parse_Status.Ok)
        testing.expect_value(t, tex_semantic_text(
            output, output.plain_text), test_case.expected)
        free(output)
    }
    output := tex_math_test_output()
    defer free(output)
    testing.expect_value(t, tex_parse_math(
        "a~b", .Display, output), Tex_Parse_Status.Ok)
    middle := output.ops[output.programs[output.root_program].first_op].next_op
    testing.expect_value(t, output.ops[middle].glue_kind, Tex_Math_Glue_Kind.Space)
}

//   Verify raw Unicode uses historical math roles and atom classes.
@(test)
tex_parse_math_matches_unicode_roles :: proc(t: ^testing.T) {
    output := tex_math_test_output()
    defer free(output)
    testing.expect_value(t, tex_parse_math(
        "Γα×≤⌈⌉", .Display, output), Tex_Parse_Status.Ok)
    expected_roles := [6]Tex_Math_Style_Role{
        .Math_Upright, .Math_Italic, .Math_Upright, .Math_Upright,
        .Math_Upright, .Math_Upright}
    expected_classes := [6]Tex_Math_Atom_Class{
        .Ord, .Ord, .Bin, .Rel, .Open, .Close}
    index := output.programs[output.root_program].first_op
    for expected_index in 0..<6 {
        testing.expect(t, index >= 0)
        if index < 0 { break }
        testing.expect_value(t, output.ops[index].style_role,
            expected_roles[expected_index])
        testing.expect_value(t, output.ops[index].atom_class,
            expected_classes[expected_index])
        index = output.ops[index].next_op
    }
}

//   Verify text commands and named operators retain historical operation kinds.
@(test)
tex_parse_math_matches_text_run_fixtures :: proc(t: ^testing.T) {
    output := tex_math_test_output()
    defer free(output)
    testing.expect_value(t, tex_parse_math(
        "\\text{Area }A+\\mathrm{mod}+\\sin(x)", .Display, output),
        Tex_Parse_Status.Ok)
    first := output.programs[output.root_program].first_op
    testing.expect_value(t, output.ops[first].kind, Tex_Math_Op_Kind.Text_Run)
    testing.expect_value(t, tex_semantic_text(output, output.ops[first].text),
        "Area ")
    roman := output.ops[output.ops[output.ops[first].next_op].next_op].next_op
    testing.expect_value(t, output.ops[roman].kind, Tex_Math_Op_Kind.Text_Run)
    named := output.ops[output.ops[roman].next_op].next_op
    testing.expect_value(t, output.ops[named].kind, Tex_Math_Op_Kind.Text_Run)
    testing.expect_value(t, tex_semantic_text(output, output.ops[named].text), "sin")
}

//   Verify the cyclic-group formulas lower commands to semantic glyphs and text.
@(test)
tex_parse_math_matches_cyclic_group_fixture :: proc(t: ^testing.T) {
    cases := [?]Tex_Math_Plain_Test_Case{
        {"C_n", "{C}_{n}"},
        {"\\frac{2\\pi}{n}", "{2π}/{n}"},
        {"\\rho", "ρ"},
        {"C_n=\\{e,\\rho,\\rho^2,\\dots,\\rho^{n-1}\\}",
            "{C}_{n}={e,ρ,{ρ}^{2},…,{ρ}^{n-1}}"},
        {"\\rho^i\\rho^j=\\rho^{i+j\\;\\mathrm{mod}\\;n}",
            "{ρ}^{i}{ρ}^{j}={ρ}^{i+j mod n}"},
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

//   Verify every fixed symbol command used by authored documents lowers cleanly.
@(test)
tex_parse_math_matches_authored_symbol_fixture :: proc(t: ^testing.T) {
    output := tex_math_test_output()
    defer free(output)
    source := "\\alpha\\beta\\gamma\\pi\\rho\\angle" +
        "\\circ\\times\\equiv\\neq\\to\\in\\dots"
    testing.expect_value(t, tex_parse_math(
        source, .Display, output), Tex_Parse_Status.Ok)
    testing.expect(t, !output.recoverable)
    testing.expect_value(t, tex_semantic_text(
        output, output.plain_text), "αβγπρ∠∘×≡≠→∈…")
}

//   Verify every historical fixed registry category and alias lowers exactly.
@(test)
tex_parse_math_matches_frozen_symbol_registry :: proc(t: ^testing.T) {
    output := tex_math_test_output()
    defer free(output)
    source := "\\varpi\\digamma\\mp\\ast\\star\\bullet\\oplus" +
        "\\otimes\\setminus\\sqcap\\amalg\\ll\\prec\\preceq" +
        "\\sim\\simeq\\cong\\parallel\\perp\\models\\sqsubseteq" +
        "\\owns\\emptyset\\complement\\therefore\\because\\top" +
        "\\bot\\rightarrow\\leftrightarrow\\uparrow\\Uparrow" +
        "\\longrightarrow\\hookrightarrow\\leftharpoonup" +
        "\\rightleftharpoons\\leadsto\\prime\\hbar\\ell\\Re" +
        "\\Im\\wp\\angle\\triangle\\Box\\Diamond\\clubsuit" +
        "\\flat\\checkmark"
    expected := "ϖϝ∓∗⋆∙⊕⊗∖⊓⨿≪≺≼∼≃≅∥⊥⊨⊑∋∅∁∴∵⊤⊥" +
        "→↔↑⇑⟶↪↼⇌⇝′ℏℓℜℑ℘∠△□◇♣♭✓"
    testing.expect_value(t, tex_parse_math(
        source, .Display, output), Tex_Parse_Status.Ok)
    testing.expect(t, !output.recoverable)
    testing.expect_value(t, tex_semantic_text(
        output, output.plain_text), expected)
}

//   Verify frozen text, large-operator, and explicit-glue registries.
@(test)
tex_parse_math_matches_frozen_operator_and_glue_registry :: proc(t: ^testing.T) {
    output := tex_math_test_output()
    defer free(output)
    source := "\\sin(x)+\\lim_n+\\prod_i+\\iiint_D+\\bigotimes_j" +
        "a\\;b\\ c\\!d\\quad e\\,f"
    testing.expect_value(t, tex_parse_math(
        source, .Display, output), Tex_Parse_Status.Ok)
    testing.expect(t, !output.recoverable)
    testing.expect_value(t, tex_semantic_text(output, output.plain_text),
        "sin(x)+lim_{n}+∏_{i}+∭_{D}+⨂_{j}a b cd e f")
}

//   Verify complete historical mathematical alphabet ranges and exceptions.
@(test)
tex_parse_math_matches_frozen_alphabet_registry :: proc(t: ^testing.T) {
    output := tex_math_test_output()
    defer free(output)
    source := "\\mathbb{ABCHNPQRYZz09}+\\mathbf{Az09}+" +
        "\\mathit{Ahz}+\\mathcal{ABHRZ}"
    expected := "𝔸𝔹ℂℍℕℙℚℝ𝕐ℤ𝕫𝟘𝟡+𝐀𝐳𝟎𝟗+𝐴ℎ𝑧+𝒜ℬℋℛ𝒵"
    testing.expect_value(t, tex_parse_math(
        source, .Display, output), Tex_Parse_Status.Ok)
    testing.expect(t, !output.recoverable)
    testing.expect_value(t, tex_semantic_text(
        output, output.plain_text), expected)
}

//   Verify matrix wrappers preserve dimensions, cells, and delimiter semantics.
@(test)
tex_parse_math_matches_matrix_fixture :: proc(t: ^testing.T) {
    output := tex_math_test_output()
    defer free(output)
    testing.expect_value(t, tex_parse_math(
        "\\begin{bmatrix}a&b\\\\c&d\\end{bmatrix}",
        .Display, output), Tex_Parse_Status.Ok)
    wrapper := &output.ops[output.programs[output.root_program].first_op]
    table_op := &output.ops[output.programs[wrapper.child_program].first_op]
    testing.expect_value(t, wrapper.kind, Tex_Math_Op_Kind.Stretch_Delimiter)
    testing.expect_value(t, table_op.kind, Tex_Math_Op_Kind.Matrix)
    testing.expect_value(t, tex_semantic_text(
        output, table_op.radical_index_text), "2")
    testing.expect_value(t, output.programs[table_op.child_program].op_count, 4)
}

//   Verify array preamble rules and signed row gaps match the rich-table fixture.
@(test)
tex_parse_math_matches_rich_table_fixture :: proc(t: ^testing.T) {
    output := tex_math_test_output()
    defer free(output)
    source := "\\begin{array}{||c|c||}\\hline a&b\\\\[1.5em]c&d" +
        "\\\\[-2pt]\\hline\\hline\\end{array}"
    testing.expect_value(t, tex_parse_math(
        source, .Display, output), Tex_Parse_Status.Ok)
    table_op := &output.ops[output.programs[output.root_program].first_op]
    descriptor := &output.table_descriptors[table_op.table_descriptor]
    testing.expect(t, descriptor.present)
    testing.expect_value(t, descriptor.rows, 2)
    testing.expect_value(t, descriptor.columns, 2)
    testing.expect_value(t, descriptor.vertical_rule_counts[0], u8(2))
    testing.expect_value(t, descriptor.vertical_rule_counts[1], u8(1))
    testing.expect_value(t, descriptor.vertical_rule_counts[2], u8(2))
    testing.expect_value(t, descriptor.horizontal_rule_counts[0], u8(1))
    testing.expect_value(t, descriptor.horizontal_rule_counts[2], u8(2))
    testing.expect_value(t, descriptor.row_extra_gaps[0].value, f32(1.5))
    testing.expect_value(t, descriptor.row_extra_gaps[1].value, f32(-2))
}

//   Verify the reported Scratchpad formulas compile without recoverable fallback.
@(test)
tex_parse_math_matches_reported_scratchpad_formulas :: proc(t: ^testing.T) {
    cases := [?]string{
        "\\sum_{i=1}^{n} i\\;\\;\\; \\prod_{k=1}^{m} a_k\\;\\;\\; " +
            "\\int_0^1 f(x)\\,dx\\;\\;\\; \\lim_{x\\to 0} f(x)",
        "\\sqrt[3]{\\left(\\int_0^1\\begin{bmatrix}1&2&3&4\\\\" +
            "5&6&7&8\\end{bmatrix}\\right)}",
        "\\begin{array}{@{}||l|r||@{}}\\hline x&\\frac{1}{2}\\\\[1em]" +
            "\\hline y&\\sqrt{z}\\\\[-1pt]\\hline\\hline\\end{array}",
        "\\begin{cases}x^2&x>0\\\\-x&x\\le0\\end{cases}\\;" +
            "\\begin{dcases}\\frac{1}{2}&x>0\\\\0&x\\le0\\end{dcases}\\;" +
            "\\begin{aligned}a&=\\begin{smallmatrix}1&2\\\\3&4" +
            "\\end{smallmatrix}\\\\b&=\\sqrt{z}\\end{aligned}",
    }
    for source in cases {
        output := tex_math_test_output()
        testing.expect_value(t, tex_parse_math(
            source, .Display, output), Tex_Parse_Status.Ok)
        testing.expect(t, !output.recoverable)
        free(output)
    }
}

//   Verify each preset table used by the reported nested formula parses directly.
@(test)
tex_parse_math_supports_reported_table_presets :: proc(t: ^testing.T) {
    cases := [?]string{
        "\\sum_{i=1}^{n} i\\;\\;\\; \\prod_{k=1}^{m} a_k\\;\\;\\; " +
            "\\int_0^1 f(x)\\,dx\\;\\;\\; \\lim_{x\\to 0} f(x)",
        "\\begin{array}{@{}||l|r||@{}}\\hline x&\\frac{1}{2}\\\\[1em]" +
            "\\hline y&\\sqrt{z}\\\\[-1pt]\\hline\\hline\\end{array}",
        "\\begin{cases}x^2&x>0\\\\-x&x\\le0\\end{cases}",
        "\\begin{dcases}\\frac{1}{2}&x>0\\\\0&x\\le0\\end{dcases}",
        "\\begin{smallmatrix}1&2\\\\3&4\\end{smallmatrix}",
        "\\begin{aligned}a&=1\\\\b&=\\sqrt{z}\\end{aligned}",
        "\\begin{aligned}a&=\\begin{smallmatrix}1&2\\\\3&4" +
            "\\end{smallmatrix}\\\\b&=\\sqrt{z}\\end{aligned}",
        "\\begin{cases}x^2&x>0\\\\-x&x\\le0\\end{cases}\\;" +
            "\\begin{dcases}\\frac{1}{2}&x>0\\\\0&x\\le0\\end{dcases}",
        "\\begin{dcases}\\frac{1}{2}&x>0\\\\0&x\\le0\\end{dcases}\\;" +
            "\\begin{aligned}a&=\\begin{smallmatrix}1&2\\\\3&4" +
            "\\end{smallmatrix}\\\\b&=\\sqrt{z}\\end{aligned}",
    }
    for source in cases {
        output := tex_math_test_output()
        testing.expect_value(t, tex_parse_math(
            source, .Display, output), Tex_Parse_Status.Ok)
        testing.expect(t, !output.recoverable)
        free(output)
    }
}