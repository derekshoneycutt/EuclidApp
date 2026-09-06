package dynview_parse

import "core:strings"

TEX_MATH_ITALIC_UNICODE :: "αβγδεζηθικλμνξοπρςστυφχψωϵϑϰϕϱϖ"
TEX_MATH_BINARY_SCALARS :: "+-*/±∓×÷·∗⋆∙⋄⊕⊖⊗⊘⊙∖⊓⊔⊎∪∩"
TEX_MATH_RELATION_SCALARS :: "=<>≤≥≠≪≫≺≻≼≽∼≃≅≈≡∝∈∉∋∌⊂⊆⊊⊈⊃⊇⊋⊉⊏⊑⊐⊒∥⊥⊨"
TEX_MATH_OPEN_SCALARS :: "([{⌈⌊⟨"
TEX_MATH_CLOSE_SCALARS :: ")]}⌉⌋⟩"

// Hold one-token lookahead and bounded recursive parser state.
Tex_Math_Parser :: struct {
    cursor: Tex_Cursor,
    output: ^Tex_Semantic_Output,
    lookahead: Tex_Token,
    lookahead_status: Tex_Parse_Status,
    has_lookahead: bool,
    depth: int,
}

// Group glyph classification fields passed together during semantic lowering.
Tex_Math_Glyph_Properties :: struct {
    role: Tex_Math_Style_Role,
    atom_class: Tex_Math_Atom_Class,
    glue: Tex_Math_Glue_Kind,
}

// Group one explicit glue kind with its readable fallback text.
Tex_Math_Glue_Result :: struct {
    kind: Tex_Math_Glue_Kind,
    text: string,
}

// Carry one optional structured-command parse result without a three-value tuple.
Tex_Math_Command_Result :: struct {
    index: int,
    status: Tex_Parse_Status,
    handled: bool,
}

// Group a parsed stretch delimiter before semantic publication.
Tex_Math_Stretch_Result :: struct {
    text: Tex_Text_Span,
    left: string,
    right: string,
    child: int,
}

//   Parse one math source into bounded font-independent semantic operations.
tex_parse_math :: proc(
    source: string,
    root_style: Tex_Math_Root_Style,
    output: ^Tex_Semantic_Output,
    limits := TEX_PARSE_DEFAULT_LIMITS) -> Tex_Parse_Status {
    if !tex_semantic_output_init(output) {
        return .Work_Limit
    }
    parser := Tex_Math_Parser{output = output}
    status := tex_cursor_init(&parser.cursor, source, limits)
    if status != .Ok {
        return tex_math_finish(&parser, status)
    }
    status = tex_math_parse_sequence(&parser, output.root_program, false)
    if status == .Ok && root_style == .Text {
        output.root_program, status =
            tex_math_wrap_root_style(&parser, output.root_program)
    }
    return tex_math_finish(&parser, status)
}

//   Append one independently rooted math fragment to an initialized output.
tex_parse_math_fragment :: proc(
    source: string,
    root_style: Tex_Math_Root_Style,
    output: ^Tex_Semantic_Output,
    limits := TEX_PARSE_DEFAULT_LIMITS) -> (int, Tex_Parse_Status) {
    if output == nil {
        return -1, .Unexpected_Token
    }
    root := tex_semantic_begin_program(output)
    if root < 0 {
        return -1, .Work_Limit
    }
    parser := Tex_Math_Parser{output = output}
    status := tex_cursor_init(&parser.cursor, source, limits)
    if status == .Ok {
        status = tex_math_parse_sequence(&parser, root, false)
    }
    if status == .Ok && root_style == .Text {
        root, status = tex_math_wrap_root_style(&parser, root)
    }
    if status == .Ok && parser.cursor.status != .Ok {
        status = parser.cursor.status
    }
    if status == .Ok && output.status != .Ok {
        status = output.status
    }
    if status != .Ok {
        output.status = status
        output.error_offset = parser.cursor.error_offset
        return -1, status
    }
    return root, .Ok
}

//   Publish the parser's terminal status and source offset.
tex_math_finish :: proc(
    parser: ^Tex_Math_Parser,
    status: Tex_Parse_Status) -> Tex_Parse_Status {
    terminal_status := status
    if terminal_status == .Ok && parser.cursor.status != .Ok {
        terminal_status = parser.cursor.status
    }
    if terminal_status == .Ok && parser.output.status != .Ok {
        terminal_status = parser.output.status
    }
    if terminal_status == .Ok {
        parser.output.plain_text =
            tex_math_program_plain_span(parser.output, parser.output.root_program)
    }
    parser.output.status = terminal_status
    parser.output.error_offset = parser.cursor.error_offset
    return terminal_status
}

//   Return one token without consuming it from parser lookahead.
tex_math_peek :: proc(parser: ^Tex_Math_Parser) -> (Tex_Token, Tex_Parse_Status) {
    if !parser.has_lookahead {
        parser.lookahead, parser.lookahead_status =
            tex_cursor_next_token(&parser.cursor)
        parser.has_lookahead = true
    }
    return parser.lookahead, parser.lookahead_status
}

//   Consume and return the current lookahead token.
tex_math_take :: proc(parser: ^Tex_Math_Parser) -> (Tex_Token, Tex_Parse_Status) {
    token, status := tex_math_peek(parser)
    parser.has_lookahead = false
    return token, status
}

//   Parse operations until source end or one required closing brace.
tex_math_parse_sequence :: proc(
    parser: ^Tex_Math_Parser,
    program_id: int,
    stop_on_brace: bool) -> Tex_Parse_Status {
    for {
        token, status := tex_math_peek(parser)
        if status == .End {
            return .Unclosed_Group if stop_on_brace else .Ok
        }
        if status != .Ok {
            return status
        }
        if token.kind == .Right_Brace && stop_on_brace {
            _, _ = tex_math_take(parser)
            return .Ok
        }
        if token.kind == .Command {
            command := tex_token_text(parser.cursor.source, token)
            if level, explicit := tex_math_explicit_style(command); explicit {
                _, _ = tex_math_take(parser)
                return tex_math_parse_style_remainder(
                    parser, program_id, stop_on_brace, level)
            }
        }
        if token.kind == .Left_Brace {
            _, _ = tex_math_take(parser)
            status = tex_math_parse_nested_sequence(parser, program_id)
        } else {
            status = tex_math_parse_atom(parser, program_id)
        }
        if status != .Ok {
            return status
        }
    }
}

//   Resolve one explicit TeX style command to its semantic level.
tex_math_explicit_style :: proc(
    command: string) -> (Tex_Math_Style_Level, bool) {
    switch command {
    case "\\displaystyle": return .Display, true
    case "\\textstyle": return .Text, true
    case "\\scriptstyle": return .Script, true
    case "\\scriptscriptstyle": return .Script_Script, true
    }
    return .Display, false
}

//   Wrap the remainder of one sequence in an explicit math style.
tex_math_parse_style_remainder :: proc(
    parser: ^Tex_Math_Parser,
    program_id: int,
    stop_on_brace: bool,
    level: Tex_Math_Style_Level) -> Tex_Parse_Status {
    child := tex_semantic_begin_program(parser.output)
    if child < 0 {
        return .Work_Limit
    }
    status := tex_math_parse_sequence(parser, child, stop_on_brace)
    if status != .Ok {
        return status
    }
    _, status = tex_math_append_style_override(parser, program_id, child, level)
    return status
}

//   Enter one checked recursive brace sequence.
tex_math_parse_nested_sequence :: proc(
    parser: ^Tex_Math_Parser,
    program_id: int) -> Tex_Parse_Status {
    if parser.depth >= parser.cursor.limits.depth {
        return tex_cursor_fail(&parser.cursor, .Work_Limit, parser.cursor.offset)
    }
    parser.depth += 1
    status := tex_math_parse_sequence(parser, program_id, true)
    parser.depth -= 1
    return status
}

//   Parse one token atom and consume any following scripts.
tex_math_parse_atom :: proc(
    parser: ^Tex_Math_Parser,
    program_id: int) -> Tex_Parse_Status {
    token, status := tex_math_take(parser)
    if status != .Ok {
        return status
    }
    op_index, atom_status := tex_math_parse_atom_token(parser, program_id, token)
    if atom_status != .Ok || op_index < 0 {
        return atom_status
    }
    return tex_math_consume_scripts(parser, program_id, op_index)
}

//   Parse exactly one already-consumed token without attaching later scripts.
tex_math_parse_atom_token :: proc(
    parser: ^Tex_Math_Parser,
    program_id: int,
    token: Tex_Token) -> (int, Tex_Parse_Status) {
    op_index := -1
    status := Tex_Parse_Status.Ok
    switch token.kind {
    case .Text:
        op_index = tex_math_append_text_atoms(parser, program_id, token)
    case .Command:
        op_index, status = tex_math_parse_command(parser, program_id, token)
    case .End, .Left_Brace, .Right_Brace, .Superscript, .Subscript,
         .Left_Bracket, .Right_Bracket, .Alignment:
        op_index = tex_math_append_token_atom(parser, program_id, token)
    }
    return op_index, status
}

//   Append classified scalar runs from one ordinary text token.
tex_math_append_text_atoms :: proc(
    parser: ^Tex_Math_Parser,
    program_id: int,
    token: Tex_Token) -> int {
    last_index := -1
    offset := token.start
    for offset < token.end {
        width := tex_utf8_sequence_width(parser.cursor.source, offset)
        if width == 0 {
            tex_cursor_fail(&parser.cursor, .Invalid_Utf8, offset)
            return -1
        }
        if width == 1 && tex_math_ascii_space(parser.cursor.source[offset]) {
            offset += width
            continue
        }
        if width == 1 && parser.cursor.source[offset] == '~' {
            last_index, _ = tex_math_append_glue(
                parser, program_id, .Space, "\u00a0")
            offset += width
            continue
        }
        role, atom_class := tex_math_scalar_class(
            parser.cursor.source, offset, width)
        end := offset + width
        for end < token.end {
            next_width := tex_utf8_sequence_width(parser.cursor.source, end)
            next_role, next_class := tex_math_scalar_class(
                parser.cursor.source, end, next_width)
            if next_role != role || next_class != atom_class {
                break
            }
            end += next_width
        }
        last_index = tex_math_append_glyph(parser, program_id,
            parser.cursor.source[offset:end], {
                role = role,
                atom_class = atom_class,
            })
        offset = end
    }
    return last_index
}

//   Return whether one byte is discarded source whitespace in normalized math.
tex_math_ascii_space :: proc(value: u8) -> bool {
    return value == ' ' || value == '\t' || value == '\n' || value == '\r'
}

//   Classify one source scalar by role and initial TeX atom class.
tex_math_scalar_class :: proc(
    source: string,
    offset, width: int) -> (Tex_Math_Style_Role, Tex_Math_Atom_Class) {
    scalar := source[offset:offset+width]
    if width > 1 {
        role := Tex_Math_Style_Role.Math_Upright
        if strings.contains(TEX_MATH_ITALIC_UNICODE, scalar) {
            role = .Math_Italic
        }
        return role, tex_math_unicode_atom_class(scalar)
    }
    value := source[offset]
    role := Tex_Math_Style_Role.Math_Upright
    if value >= 'A' && value <= 'Z' || value >= 'a' && value <= 'z' {
        role = .Math_Italic
    }
    switch value {
    case '+', '-', '*', '/': return role, .Bin
    case '=', '<', '>': return role, .Rel
    case '(', '[': return role, .Open
    case ')', ']': return role, .Close
    case ',', ';': return role, .Punct
    }
    return role, .Ord
}

//   Classify one non-ASCII scalar using the frozen TeX atom sets.
tex_math_unicode_atom_class :: proc(scalar: string) -> Tex_Math_Atom_Class {
    if strings.contains(TEX_MATH_BINARY_SCALARS, scalar) { return .Bin }
    if strings.contains(TEX_MATH_RELATION_SCALARS, scalar) { return .Rel }
    if strings.contains(TEX_MATH_OPEN_SCALARS, scalar) { return .Open }
    if strings.contains(TEX_MATH_CLOSE_SCALARS, scalar) { return .Close }
    return .Ord
}

//   Append one glyph operation with copied semantic text.
tex_math_append_glyph :: proc(
    parser: ^Tex_Math_Parser,
    program_id: int,
    text: string,
    properties: Tex_Math_Glyph_Properties) -> int {
    span, ok := tex_semantic_append_text(parser.output, text)
    if !ok {
        return -1
    }
    return tex_semantic_append_op(parser.output, program_id, {
        kind = .Math_Glyph_Run,
        text = span,
        style_role = properties.role,
        atom_class = properties.atom_class,
        glue_kind = properties.glue,
        child_program = -1,
        secondary_program = -1,
        tertiary_program = -1,
        table_descriptor = -1,
    })
}

//   Preserve unexpected punctuation as an upright ordinary atom.
tex_math_append_token_atom :: proc(
    parser: ^Tex_Math_Parser,
    program_id: int,
    token: Tex_Token) -> int {
    return tex_math_append_glyph(parser, program_id,
        tex_token_text(parser.cursor.source, token), {
            role = .Math_Upright,
            atom_class = .Ord,
        })
}

//   Dispatch one fixture-supported command or preserve it as fallback text.
tex_math_parse_command :: proc(
    parser: ^Tex_Math_Parser,
    program_id: int,
    token: Tex_Token) -> (int, Tex_Parse_Status) {
    command := tex_token_text(parser.cursor.source, token)
    if tex_math_registry_is_fixed_delimiter(command) {
        return tex_math_parse_fixed_delimiter(parser, program_id, command)
    }
    if accent, ok := tex_math_registry_accent(command); ok {
        return tex_math_parse_accent(parser, program_id, accent.mode)
    }
    structured := tex_math_parse_structured_command(parser, program_id, command)
    if structured.handled {
        return structured.index, structured.status
    }
    switch command {
    case "\\left": return tex_math_parse_stretch_delimiter(parser, program_id)
    case "\\mathbb", "\\mathbf", "\\mathit", "\\mathcal":
        return tex_math_parse_alphabet(parser, program_id, command)
    case "\\mathrm", "\\text":
        return tex_math_parse_upright_group(parser, program_id, command)
    case "\\operatorname":
        return tex_math_parse_operator_name(parser, program_id)
    case "\\begin": return tex_math_parse_table(parser, program_id)
    }
    return tex_math_parse_symbol_command(parser, program_id, command)
}

//   Dispatch commands that construct recursive child programs.
tex_math_parse_structured_command :: proc(
    parser: ^Tex_Math_Parser,
    program_id: int,
    command: string) -> Tex_Math_Command_Result {
    index := -1
    status := Tex_Parse_Status.Ok
    switch command {
    case "\\frac": index, status = tex_math_parse_fraction(parser, program_id)
    case "\\dfrac": index, status = tex_math_parse_fraction_variant(
        parser, program_id, .Display)
    case "\\tfrac": index, status = tex_math_parse_fraction_variant(
        parser, program_id, .Text)
    case "\\binom": index, status = tex_math_parse_binomial(
        parser, program_id, false, .Display)
    case "\\dbinom": index, status = tex_math_parse_binomial(
        parser, program_id, true, .Display)
    case "\\tbinom": index, status = tex_math_parse_binomial(
        parser, program_id, true, .Text)
    case "\\sqrt": index, status = tex_math_parse_radical(parser, program_id)
    case "\\overset": index, status = tex_math_parse_annotation(
        parser, program_id, true)
    case "\\underset": index, status = tex_math_parse_annotation(
        parser, program_id, false)
    case: return {}
    }
    return {index = index, status = status, handled = true}
}

//   Parse one standalone fixed-size delimiter with explicit atom semantics.
tex_math_parse_fixed_delimiter :: proc(
    parser: ^Tex_Math_Parser,
    program_id: int,
    command: string) -> (int, Tex_Parse_Status) {
    tex_math_skip_argument_whitespace(parser)
    delimiter, ok := tex_math_take_delimiter(parser)
    if !ok {
        parser.output.recoverable = true
        return tex_math_append_fallback_command(parser, program_id, command), .Ok
    }
    growth, atom_class := tex_math_fixed_delimiter_policy(command)
    return tex_math_append_standalone_delimiter(
        parser, program_id, delimiter, growth, 0, atom_class)
}

//   Resolve one fixed delimiter command's size and atom class.
tex_math_fixed_delimiter_policy :: proc(
    command: string) -> (i32, Tex_Math_Atom_Class) {
    growth: i32 = 1
    if len(command) >= 4 && command[1:4] == "Big" {
        growth = 2
    }
    if len(command) >= 5 && command[1:5] == "bigg" {
        growth = 3
    }
    if len(command) >= 5 && command[1:5] == "Bigg" {
        growth = 4
    }
    suffix := command[len(command)-1]
    if suffix == 'l' { return growth, .Open }
    if suffix == 'r' { return growth, .Close }
    if suffix == 'm' { return growth, .Rel }
    return growth, .Ord
}

//   Append one delimiter without recursive content.
tex_math_append_standalone_delimiter :: proc(
    parser: ^Tex_Math_Parser,
    program_id: int,
    delimiter: string,
    growth, shared_extent: i32,
    atom_class: Tex_Math_Atom_Class) -> (int, Tex_Parse_Status) {
    text, _ := tex_semantic_append_text(parser.output, delimiter)
    left := Tex_Delimiter_Kind.None
    right := tex_math_delimiter_kind(delimiter)
    if atom_class != .Close {
        left, right = right, .None
    }
    return tex_math_append_structured(parser, program_id, {
        kind = .Stretch_Delimiter, text = text, radical_index_text = text,
        left_delimiter = left, right_delimiter = right, style_role = .Math,
        atom_class = atom_class, operator_growth = growth,
        operator_limits = shared_extent, child_program = -1,
        secondary_program = -1, tertiary_program = -1, table_descriptor = -1,
    })
}

//   Dispatch glyph, operator, and spacing commands from the frozen registry.
tex_math_parse_symbol_command :: proc(
    parser: ^Tex_Math_Parser,
    program_id: int,
    command: string) -> (int, Tex_Parse_Status) {
    if operator, ok := tex_math_registry_large_operator(command); ok {
        return tex_math_append_large_operator(parser, program_id, operator)
    }
    if text, ok := tex_math_registry_text_operator(command); ok {
        return tex_math_append_text_run(parser, program_id, text, .Op)
    }
    if glue, ok := tex_math_resolve_glue(command); ok {
        return tex_math_append_glue(parser, program_id, glue.kind, glue.text)
    }
    symbol, ok := tex_math_registry_fixed_symbol(command)
    if ok {
        return tex_math_append_glyph(
            parser, program_id, symbol.text, symbol.properties), .Ok
    }
    return tex_math_append_fallback_command(parser, program_id, command), .Ok
}

//   Resolve every explicit glue command from the frozen parser registry.
tex_math_resolve_glue :: proc(
    command: string) -> (Tex_Math_Glue_Result, bool) {
    switch command {
    case "\\;": return {.Thick, " "}, true
    case "\\:", "\\>", "\\ ", "\\enspace": return {.Space, " "}, true
    case "\\!": return {.Negative_Thin, ""}, true
    case "\\quad": return {.Quad, " "}, true
    case "\\qquad": return {.Quad, "  "}, true
    case "\\,": return {.Thin, " "}, true
    }
    return {}, false
}

//   Append one fixed command as a classified Unicode math atom.
tex_math_append_fixed_symbol :: proc(
    parser: ^Tex_Math_Parser,
    program_id: int,
    text: string,
    role: Tex_Math_Style_Role,
    atom_class: Tex_Math_Atom_Class) -> (int, Tex_Parse_Status) {
    return tex_math_append_glyph(parser, program_id, text, {
        role = role,
        atom_class = atom_class,
    }), .Ok
}

//   Parse one required group as upright text within a math program.
tex_math_parse_upright_group :: proc(
    parser: ^Tex_Math_Parser,
    program_id: int,
    command: string) -> (int, Tex_Parse_Status) {
    span, ok := tex_math_take_nested_raw_group(parser)
    if !ok {
        parser.output.recoverable = true
        return tex_math_append_fallback_command(parser, program_id, command), .Ok
    }
    return tex_math_append_text_run(
        parser, program_id, tex_semantic_text(parser.output, span), .Ord)
}

//   Append one text-font operation with a specified TeX atom class.
tex_math_append_text_run :: proc(
    parser: ^Tex_Math_Parser,
    program_id: int,
    text: string,
    atom_class: Tex_Math_Atom_Class) -> (int, Tex_Parse_Status) {
    span, ok := tex_semantic_append_text(parser.output, text)
    if !ok { return -1, .Work_Limit }
    index := tex_semantic_append_op(parser.output, program_id, {
        kind = .Text_Run, text = span, style_role = .Text,
        atom_class = atom_class, child_program = -1,
        secondary_program = -1, tertiary_program = -1, table_descriptor = -1,
    })
    return index, .Ok if index >= 0 else .Work_Limit
}

//   Consume one required group while retaining its exact authored interior.
tex_math_take_nested_raw_group :: proc(
    parser: ^Tex_Math_Parser) -> (Tex_Text_Span, bool) {
    opening, status := tex_math_peek(parser)
    if status != .Ok || opening.kind != .Left_Brace {
        return {}, false
    }
    _, _ = tex_math_take(parser)
    start, depth := opening.end, 1
    for depth > 0 {
        token, token_status := tex_math_take(parser)
        if token_status != .Ok {
            return {}, false
        }
        if token.kind == .Left_Brace { depth += 1 }
        if token.kind == .Right_Brace {
            depth -= 1
            if depth == 0 {
                return tex_semantic_append_text(
                    parser.output, parser.cursor.source[start:token.start])
            }
        }
    }
    return {}, false
}

//   Parse an upright operator name and its starred stacked-limit form.
tex_math_parse_operator_name :: proc(
    parser: ^Tex_Math_Parser,
    program_id: int) -> (int, Tex_Parse_Status) {
    starred := tex_math_consume_optional_asterisk(parser)
    span, ok := tex_math_take_nested_raw_group(parser)
    if !ok {
        parser.output.recoverable = true
        return tex_math_append_fallback_command(
            parser, program_id,
            "\\operatorname*" if starred else "\\operatorname"), .Ok
    }
    if !starred {
        return tex_math_append_fixed_symbol(parser, program_id,
            tex_semantic_text(parser.output, span), .Operator_Name, .Op)
    }
    index := tex_semantic_append_op(parser.output, program_id, {
        kind = .Large_Operator, text = span, style_role = .Operator_Name_Star,
        atom_class = .Op, large_op_kind = 4, operator_growth = 0,
        operator_limits = 2, child_program = -1, secondary_program = -1,
        tertiary_program = -1, table_descriptor = -1,
    })
    return index, .Ok if index >= 0 else .Work_Limit
}

//   Consume one optional asterisk from the next plain-text token.
tex_math_consume_optional_asterisk :: proc(parser: ^Tex_Math_Parser) -> bool {
    token, status := tex_math_peek(parser)
    if status != .Ok || token.kind != .Text || token.start >= token.end ||
        parser.cursor.source[token.start] != '*' {
        return false
    }
    parser.lookahead.start += 1
    if parser.lookahead.start >= parser.lookahead.end {
        parser.has_lookahead = false
    }
    return true
}

//   Parse one verified mathematical alphabet command.
tex_math_parse_alphabet :: proc(
    parser: ^Tex_Math_Parser,
    program_id: int,
    command: string) -> (int, Tex_Parse_Status) {
    alphabet, found := tex_math_alphabet_spec(command)
    if !found {
        return tex_math_append_fallback_command(parser, program_id, command), .Ok
    }
    child, ok := tex_math_parse_group_program(parser)
    if !ok {
        parser.output.recoverable = true
        return tex_math_append_fallback_command(parser, program_id, command), .Ok
    }
    source := tex_math_program_plain_span(parser.output, child)
    text := tex_semantic_text(parser.output, source)
    if len(text) == 0 {
        parser.output.recoverable = true
        return tex_math_append_fallback_command(parser, program_id, command), .Ok
    }
    mapped, mapped_ok := tex_math_append_alphabet_text(
        parser.output, text, alphabet)
    if !mapped_ok {
        parser.output.recoverable = true
        return tex_math_append_fallback_command(parser, program_id, command), .Ok
    }
    index := tex_semantic_append_op(parser.output, program_id, {
        kind = .Math_Glyph_Run,
        text = mapped,
        style_role = alphabet.role,
        atom_class = .Ord,
        child_program = -1,
        secondary_program = -1,
        tertiary_program = -1,
        table_descriptor = -1,
    })
    return index, .Ok if index >= 0 else .Work_Limit
}

//   Parse one recursive left/right delimiter pair with recoverable closure.
tex_math_parse_stretch_delimiter :: proc(
    parser: ^Tex_Math_Parser,
    program_id: int) -> (int, Tex_Parse_Status) {
    left, left_ok := tex_math_take_delimiter(parser)
    if !left_ok {
        return tex_math_append_fallback_command(
            parser, program_id, "\\left"), .Ok
    }
    child := tex_semantic_begin_program(parser.output)
    has_right := tex_math_parse_until_right(parser, child)
    right := "."
    if has_right {
        right, has_right = tex_math_take_delimiter(parser)
    }
    if !has_right {
        parser.output.recoverable = true
    }
    text := tex_math_stretch_text(parser.output, left, child, right)
    if !has_right {
        return tex_math_append_glyph(
            parser, program_id, tex_semantic_text(parser.output, text),
            {role = .Math, atom_class = .Ord}), .Ok
    }
    return tex_math_append_stretch_delimiter(parser, program_id, {
        text = text,
        left = left,
        right = right,
        child = child,
    })
}

//   Publish one complete structured stretch-delimiter operation.
tex_math_append_stretch_delimiter :: proc(
    parser: ^Tex_Math_Parser,
    program_id: int,
    result: Tex_Math_Stretch_Result) -> (int, Tex_Parse_Status) {
    left_span, _ := tex_semantic_append_text(parser.output, result.left)
    right_span, _ := tex_semantic_append_text(parser.output, result.right)
    return tex_math_append_structured(parser, program_id, {
        kind = .Stretch_Delimiter,
        text = result.text,
        radical_index_text = left_span,
        superscript_text = right_span,
        left_delimiter = tex_math_delimiter_kind(result.left),
        right_delimiter = tex_math_delimiter_kind(result.right),
        style_role = .Math,
        atom_class = .Inner,
        child_program = result.child,
        secondary_program = -1,
        tertiary_program = -1,
        table_descriptor = -1,
    })
}

//   Parse child atoms until a right-delimiter command or source end.
tex_math_parse_until_right :: proc(
    parser: ^Tex_Math_Parser,
    program_id: int) -> bool {
    for {
        token, status := tex_math_peek(parser)
        if status != .Ok {
            return false
        }
        if token.kind == .Command &&
            tex_token_text(parser.cursor.source, token) == "\\right" {
            _, _ = tex_math_take(parser)
            return true
        }
        if token.kind == .Command &&
            tex_token_text(parser.cursor.source, token) == "\\middle" {
            _, _ = tex_math_take(parser)
            delimiter, ok := tex_math_take_delimiter(parser)
            if !ok {
                return false
            }
            _, status = tex_math_append_standalone_delimiter(
                parser, program_id, delimiter, 0, 1, .Rel)
            if status != .Ok {
                return false
            }
            continue
        }
        if tex_math_parse_atom(parser, program_id) != .Ok {
            return false
        }
    }
}

//   Consume one delimiter scalar or mapped control symbol.
tex_math_take_delimiter :: proc(parser: ^Tex_Math_Parser) -> (string, bool) {
    token, status := tex_math_peek(parser)
    if status != .Ok {
        return "", false
    }
    if token.kind == .Text {
        width := tex_utf8_sequence_width(parser.cursor.source, token.start)
        delimiter := parser.cursor.source[token.start:token.start + width]
        parser.lookahead.start += width
        if parser.lookahead.start >= parser.lookahead.end {
            parser.has_lookahead = false
        }
        return delimiter, tex_math_delimiter_valid(delimiter)
    }
    token, _ = tex_math_take(parser)
    delimiter := tex_token_text(parser.cursor.source, token)
    return delimiter, tex_math_delimiter_valid(delimiter)
}

//   Return whether one plain scalar is a supported stretch delimiter.
tex_math_delimiter_valid :: proc(delimiter: string) -> bool {
    return delimiter == "." || tex_math_delimiter_kind(delimiter) != .None
}

//   Resolve one authored delimiter spelling to its renderer-independent kind.
tex_math_delimiter_kind :: proc(delimiter: string) -> Tex_Delimiter_Kind {
    switch delimiter {
    case "(": return .Left_Paren
    case ")": return .Right_Paren
    case "[": return .Left_Bracket
    case "]": return .Right_Bracket
    case "\\{": return .Left_Brace
    case "\\}": return .Right_Brace
    case "|": return .Vert
    case "\\|": return .Double_Vert
    case "\\lceil": return .Left_Ceil
    case "\\rceil": return .Right_Ceil
    case "\\lfloor": return .Left_Floor
    case "\\rfloor": return .Right_Floor
    case "\\langle": return .Left_Angle
    case "\\rangle": return .Right_Angle
    }
    return .None
}

//   Build canonical text for one recursive stretch-delimiter operation.
tex_math_stretch_text :: proc(
    output: ^Tex_Semantic_Output,
    left: string,
    child: int,
    right: string) -> Tex_Text_Span {
    child_text := tex_math_program_plain_span(output, child)
    start := output.text_count
    parts := [?]string{
        "\\left", left, tex_semantic_text(output, child_text), "\\right", right}
    for part in parts {
        _, _ = tex_semantic_append_text(output, part)
    }
    return {offset = start, length = output.text_count-start}
}

//   Append one explicit semantic glue operation.
tex_math_append_glue :: proc(
    parser: ^Tex_Math_Parser,
    program_id: int,
    kind: Tex_Math_Glue_Kind,
    text: string) -> (int, Tex_Parse_Status) {
    return tex_math_append_glyph(
        parser, program_id, text, {
            role = .Math_Upright,
            glue = kind,
        }), .Ok
}

//   Preserve an unsupported control word as slash plus normal command text.
tex_math_append_fallback_command :: proc(
    parser: ^Tex_Math_Parser,
    program_id: int,
    command: string) -> int {
    parser.output.recoverable = true
    _ = tex_math_append_glyph(
        parser, program_id, "\\", {
            role = .Math_Upright,
            atom_class = .Ord,
        })
    if len(command) <= 1 {
        return parser.output.programs[program_id].last_op
    }
    return tex_math_append_glyph(
        parser, program_id, command[1:], {
            role = .Math_Italic,
            atom_class = .Ord,
        })
}

//   Append one large operator whose scripts attach directly to the operation.
tex_math_append_large_operator :: proc(
    parser: ^Tex_Math_Parser,
    program_id: int,
    operator: Tex_Math_Large_Operator) -> (int, Tex_Parse_Status) {
    span, ok := tex_semantic_append_text(parser.output, operator.text)
    if !ok {
        return -1, .Work_Limit
    }
    index := tex_semantic_append_op(parser.output, program_id, {
        kind = .Large_Operator,
        text = span,
        style_role = .Math,
        atom_class = .Op,
        large_op_kind = operator.family,
        operator_growth = operator.growth,
        operator_limits = operator.limits,
        child_program = -1,
        secondary_program = -1,
        tertiary_program = -1,
        table_descriptor = -1,
    })
    return index, .Ok
}

//   Parse a fraction with independently recursive numerator and denominator.
tex_math_parse_fraction :: proc(
    parser: ^Tex_Math_Parser,
    program_id: int) -> (int, Tex_Parse_Status) {
    numerator, numerator_ok := tex_math_parse_group_program(parser)
    denominator, denominator_ok := tex_math_parse_group_program(parser)
    parser.output.recoverable = parser.output.recoverable || !denominator_ok
    if !numerator_ok {
        parser.output.recoverable = true
    }
    text := tex_math_fraction_text(parser.output, numerator, denominator)
    return tex_math_append_structured(parser, program_id, {
        kind = .Fraction,
        text = text,
        style_role = .Math,
        atom_class = .Inner,
        child_program = numerator,
        secondary_program = denominator,
        tertiary_program = -1,
        table_descriptor = -1,
    })
}

//   Parse a fraction wrapped in one explicit historical variant style.
tex_math_parse_fraction_variant :: proc(
    parser: ^Tex_Math_Parser,
    program_id: int,
    level: Tex_Math_Style_Level) -> (int, Tex_Parse_Status) {
    child := tex_semantic_begin_program(parser.output)
    if child < 0 {
        return -1, .Work_Limit
    }
    _, status := tex_math_parse_fraction(parser, child)
    if status != .Ok {
        return -1, status
    }
    return tex_math_append_style_override(parser, program_id, child, level)
}

//   Parse a ruleless two-part stack enclosed by stretch parentheses.
tex_math_parse_binomial :: proc(
    parser: ^Tex_Math_Parser,
    program_id: int,
    explicit_style: bool,
    level: Tex_Math_Style_Level) -> (int, Tex_Parse_Status) {
    top, top_ok := tex_math_parse_group_program(parser)
    bottom, bottom_ok := tex_math_parse_group_program(parser)
    parser.output.recoverable = parser.output.recoverable || !top_ok || !bottom_ok
    stack_program := tex_semantic_begin_program(parser.output)
    content_program := tex_semantic_begin_program(parser.output)
    if stack_program < 0 || content_program < 0 {
        return -1, .Work_Limit
    }
    stack_text := tex_math_stack_text(parser.output, top, bottom)
    _, status := tex_math_append_structured(parser, stack_program, {
        kind = .Stack,
        text = stack_text,
        style_role = .Math,
        atom_class = .Inner,
        child_program = top,
        secondary_program = bottom,
        tertiary_program = -1,
        table_descriptor = -1,
    })
    if status != .Ok {
        return -1, status
    }
    delimited_text := tex_math_stretch_text(
        parser.output, "(", stack_program, ")")
    _, status = tex_math_append_stretch_delimiter(parser, content_program, {
        text = delimited_text, left = "(", right = ")", child = stack_program})
    if status != .Ok {
        return -1, status
    }
    if explicit_style {
        return tex_math_append_style_override(
            parser, program_id, content_program, level)
    }
    op := parser.output.programs[content_program].first_op
    copy_op := parser.output.ops[op]
    return tex_semantic_append_op(parser.output, program_id, copy_op), .Ok
}

//   Build canonical source for one ruleless two-part stack.
tex_math_stack_text :: proc(
    output: ^Tex_Semantic_Output,
    top, bottom: int) -> Tex_Text_Span {
    top_text := tex_math_program_plain_span(output, top)
    bottom_text := tex_math_program_plain_span(output, bottom)
    start := output.text_count
    parts := [?]string{"{", tex_semantic_text(output, top_text), "\\atop ",
        tex_semantic_text(output, bottom_text), "}"}
    for part in parts {
        _, _ = tex_semantic_append_text(output, part)
    }
    return {offset = start, length = output.text_count-start}
}

//   Parse an optional radical degree followed by one radicand group.
tex_math_parse_radical :: proc(
    parser: ^Tex_Math_Parser,
    program_id: int) -> (int, Tex_Parse_Status) {
    degree := -1
    token, status := tex_math_peek(parser)
    if status == .Ok && token.kind == .Left_Bracket {
        _, _ = tex_math_take(parser)
        degree, _ = tex_math_parse_delimited_program(parser, .Right_Bracket)
    }
    radicand, ok := tex_math_parse_group_program(parser)
    parser.output.recoverable = parser.output.recoverable || !ok
    text := tex_math_program_plain_span(parser.output, radicand)
    degree_text := tex_math_program_plain_span(parser.output, degree)
    mode := Tex_Radical_Mode.Square_Root
    if degree >= 0 {
        mode = .Nth_Root
    }
    return tex_math_append_structured(parser, program_id, {
        kind = .Radical,
        text = text,
        radical_index_text = degree_text,
        style_role = .Math,
        atom_class = .Ord,
        radical_mode = mode,
        child_program = radicand,
        secondary_program = degree,
        tertiary_program = -1,
        table_descriptor = -1,
    })
}

//   Parse one bar accent around a recursive required group.
tex_math_parse_accent :: proc(
    parser: ^Tex_Math_Parser,
    program_id: int,
    mode: Tex_Accent_Mode) -> (int, Tex_Parse_Status) {
    tex_math_skip_argument_whitespace(parser)
    child, ok := tex_math_parse_script_program(parser)
    parser.output.recoverable = parser.output.recoverable || !ok
    return tex_math_append_structured(parser, program_id, {
        kind = .Accent,
        text = tex_math_program_plain_span(parser.output, child),
        style_role = .Math,
        atom_class = .Ord,
        accent_mode = mode,
        child_program = child,
        secondary_program = -1,
        tertiary_program = -1,
        table_descriptor = -1,
    })
}

//   Parse one over- or under-annotation into the renderer's stack ordering.
tex_math_parse_annotation :: proc(
    parser: ^Tex_Math_Parser,
    program_id: int,
    over: bool) -> (int, Tex_Parse_Status) {
    annotation, annotation_ok := tex_math_parse_group_program(parser)
    base, base_ok := tex_math_parse_group_program(parser)
    parser.output.recoverable =
        parser.output.recoverable || !annotation_ok || !base_ok
    top := annotation if over else base
    bottom := base if over else annotation
    text := tex_math_stack_text(parser.output, top, bottom)
    return tex_math_append_structured(parser, program_id, {
        kind = .Stack, text = text, style_role = .Math, atom_class = .Inner,
        operator_limits = 1 if over else 2, child_program = top,
        secondary_program = bottom, tertiary_program = -1,
        table_descriptor = -1,
    })
}

//   Skip source whitespace ignored between a control word and its argument.
tex_math_skip_argument_whitespace :: proc(parser: ^Tex_Math_Parser) {
    token, status := tex_math_peek(parser)
    if status != .Ok || token.kind != .Text {
        return
    }
    for parser.lookahead.start < parser.lookahead.end {
        value := parser.cursor.source[parser.lookahead.start]
        if value != ' ' && value != '\t' && value != '\n' && value != '\r' {
            break
        }
        parser.lookahead.start += 1
    }
    if parser.lookahead.start >= parser.lookahead.end {
        parser.has_lookahead = false
    }
}

//   Append a fully prepared recursive operation to one program.
tex_math_append_structured :: proc(
    parser: ^Tex_Math_Parser,
    program_id: int,
    op: Tex_Math_Op) -> (int, Tex_Parse_Status) {
    index := tex_semantic_append_op(parser.output, program_id, op)
    return index, .Ok if index >= 0 else .Work_Limit
}

//   Parse one required brace group into a new child program.
tex_math_parse_group_program :: proc(parser: ^Tex_Math_Parser) -> (int, bool) {
    token, status := tex_math_peek(parser)
    program_id := tex_semantic_begin_program(parser.output)
    if status != .Ok || token.kind != .Left_Brace || program_id < 0 {
        return program_id, false
    }
    _, _ = tex_math_take(parser)
    status = tex_math_parse_nested_sequence(parser, program_id)
    return program_id, status == .Ok
}

//   Parse through one non-brace closing punctuation into a child program.
tex_math_parse_delimited_program :: proc(
    parser: ^Tex_Math_Parser,
    closing: Tex_Token_Kind) -> (int, bool) {
    program_id := tex_semantic_begin_program(parser.output)
    for {
        token, status := tex_math_peek(parser)
        if status != .Ok {
            return program_id, false
        }
        if token.kind == closing {
            _, _ = tex_math_take(parser)
            return program_id, true
        }
        if tex_math_parse_atom(parser, program_id) != .Ok {
            return program_id, false
        }
    }
}

//   Attach following scripts to one atom, preserving large-operator policy.
tex_math_consume_scripts :: proc(
    parser: ^Tex_Math_Parser,
    program_id, op_index: int) -> Tex_Parse_Status {
    superscript, subscript := -1, -1
    tex_math_consume_operator_limit_modifier(parser, op_index)
    for {
        token, status := tex_math_peek(parser)
        if status != .Ok || token.kind != .Superscript && token.kind != .Subscript {
            break
        }
        _, _ = tex_math_take(parser)
        child, ok := tex_math_parse_script_program(parser)
        if !ok {
            parser.output.recoverable = true
            return .Ok
        }
        if token.kind == .Superscript {
            superscript = child
        } else {
            subscript = child
        }
    }
    if superscript < 0 && subscript < 0 {
        return .Ok
    }
    tex_math_attach_scripts(parser, program_id, op_index, superscript, subscript)
    return .Ok
}

//   Apply a limit modifier only to the immediately preceding large operator.
tex_math_consume_operator_limit_modifier :: proc(
    parser: ^Tex_Math_Parser,
    op_index: int) {
    if op_index < 0 || parser.output.ops[op_index].kind != .Large_Operator {
        return
    }
    token, status := tex_math_peek(parser)
    if status != .Ok || token.kind != .Command {
        return
    }
    command := tex_token_text(parser.cursor.source, token)
    if command == "\\nolimits" {
        parser.output.ops[op_index].operator_limits = 1
    } else if command == "\\limits" || command == "\\displaylimits" {
        parser.output.ops[op_index].operator_limits = 2
    } else {
        return
    }
    _, _ = tex_math_take(parser)
}

//   Parse one grouped or single-token script into a child program.
tex_math_parse_script_program :: proc(parser: ^Tex_Math_Parser) -> (int, bool) {
    token, status := tex_math_peek(parser)
    if status != .Ok {
        return -1, false
    }
    if token.kind == .Left_Brace {
        return tex_math_parse_group_program(parser)
    }
    program_id := tex_semantic_begin_program(parser.output)
    if token.kind == .Text {
        width := tex_utf8_sequence_width(parser.cursor.source, token.start)
        token.end = token.start + width
        parser.lookahead.start = token.end
        if parser.lookahead.start >= parser.lookahead.end {
            parser.has_lookahead = false
        }
    } else {
        token, status = tex_math_take(parser)
    }
    if status != .Ok || token.end <= token.start {
        return program_id, false
    }
    op_index, atom_status := tex_math_parse_atom_token(parser, program_id, token)
    return program_id, atom_status == .Ok && op_index >= 0
}

//   Mutate one just-appended operation into its recursive script form.
tex_math_attach_scripts :: proc(
    parser: ^Tex_Math_Parser,
    program_id, op_index, superscript, subscript: int) {
    op := &parser.output.ops[op_index]
    sup_text := tex_math_program_plain_span(parser.output, superscript)
    sub_text := tex_math_program_plain_span(parser.output, subscript)
    if op.kind == .Large_Operator {
        op.child_program = superscript
        op.secondary_program = subscript
        op.superscript_text = sup_text
        op.subscript_text = sub_text
        return
    }
    if op.kind == .Accent &&
        tex_math_attach_brace_annotation(
            parser, op, superscript, subscript, sup_text, sub_text) {
        return
    }
    base_program := tex_semantic_begin_program(parser.output)
    base := op^
    base.next_op = -1
    _ = tex_semantic_append_op(parser.output, base_program, base)
    op.kind = .Script
    op.child_program = base_program
    op.secondary_program = superscript
    op.tertiary_program = subscript
    op.superscript_text = sup_text
    op.subscript_text = sub_text
    _ = program_id
}

//   Rewrite matching overbrace/underbrace scripts as stacked annotations.
tex_math_attach_brace_annotation :: proc(
    parser: ^Tex_Math_Parser,
    op: ^Tex_Math_Op,
    superscript, subscript: int,
    sup_text, sub_text: Tex_Text_Span) -> bool {
    over := op.accent_mode == .Overbrace && superscript >= 0
    under := op.accent_mode == .Underbrace && subscript >= 0
    if !over && !under {
        return false
    }
    brace_program := tex_semantic_begin_program(parser.output)
    brace := op^
    brace.next_op = -1
    _ = tex_semantic_append_op(parser.output, brace_program, brace)
    op.kind = .Stack
    op.child_program = superscript if over else brace_program
    op.secondary_program = brace_program if over else subscript
    op.tertiary_program = -1
    op.operator_limits = 1 if over else 2
    op.superscript_text = sup_text
    op.subscript_text = sub_text
    return true
}

//   Wrap a complete root program in the frozen text-style operation.
tex_math_wrap_root_style :: proc(
    parser: ^Tex_Math_Parser,
    child: int) -> (int, Tex_Parse_Status) {
    root := tex_semantic_begin_program(parser.output)
    _, status := tex_math_append_style_override(
        parser, root, child, .Text)
    return root, status
}

//   Append one recursive explicit-style wrapper.
tex_math_append_style_override :: proc(
    parser: ^Tex_Math_Parser,
    program_id, child: int,
    level: Tex_Math_Style_Level) -> (int, Tex_Parse_Status) {
    text := tex_math_program_plain_span(parser.output, child)
    index := tex_semantic_append_op(parser.output, program_id, {
        kind = .Style_Override,
        text = text,
        style_role = .Math,
        atom_class = .Inner,
        style_level = level,
        child_program = child,
        secondary_program = -1,
        tertiary_program = -1,
        table_descriptor = -1,
    })
    if index < 0 {
        return index, .Work_Limit
    }
    return index, .Ok
}

//   Serialize one program's plain payload into newly owned semantic text.
tex_math_program_plain_span :: proc(
    output: ^Tex_Semantic_Output,
    program_id: int) -> Tex_Text_Span {
    if program_id < 0 || program_id >= output.program_count {
        return {}
    }
    start := output.text_count
    index := output.programs[program_id].first_op
    for index >= 0 {
        if !tex_math_append_op_plain(output, &output.ops[index]) {
            return {}
        }
        index = output.ops[index].next_op
    }
    return {offset = start, length = output.text_count-start}
}

//   Append one operation's recursive canonical plain representation.
tex_math_append_op_plain :: proc(
    output: ^Tex_Semantic_Output,
    op: ^Tex_Math_Op) -> bool {
    switch op.kind {
    case .Script:
        return tex_math_append_script_plain(output, op)
    case .Large_Operator:
        return tex_math_append_large_operator_plain(output, op)
    case .Accent:
        return tex_math_append_wrapped_program(
            output, tex_math_accent_command(op.accent_mode), op.child_program)
    case .Radical:
        return tex_math_append_radical_plain(output, op)
    case .Style_Override:
        return tex_math_append_program_plain(output, op.child_program)
    case .Text_Run, .Math_Glyph_Run, .Fraction, .Stretch_Delimiter, .Matrix, .Stack:
        _, ok := tex_semantic_append_text(output, tex_semantic_text(output, op.text))
        return ok
    }
    return false
}

//   Return the canonical source command for one accent mode.
tex_math_accent_command :: proc(mode: Tex_Accent_Mode) -> string {
    for accent in TEX_MATH_ACCENTS {
        if accent.mode == mode {
            return accent.canonical
        }
    }
    return ""
}

//   Append every operation in one child program to canonical plain text.
tex_math_append_program_plain :: proc(
    output: ^Tex_Semantic_Output,
    program_id: int) -> bool {
    if program_id < 0 || program_id >= output.program_count {
        return true
    }
    index := output.programs[program_id].first_op
    for index >= 0 {
        if !tex_math_append_op_plain(output, &output.ops[index]) {
            return false
        }
        index = output.ops[index].next_op
    }
    return true
}

//   Append a command and one braced recursive child program.
tex_math_append_wrapped_program :: proc(
    output: ^Tex_Semantic_Output,
    command: string,
    program_id: int) -> bool {
    _, command_ok := tex_semantic_append_text(output, command)
    _, open_ok := tex_semantic_append_text(output, "{")
    children_ok := tex_math_append_program_plain(output, program_id)
    _, last_ok := tex_semantic_append_text(output, "}")
    return command_ok && open_ok && children_ok && last_ok
}

//   Append canonical grouped base and optional superscript/subscript suffixes.
tex_math_append_script_plain :: proc(
    output: ^Tex_Semantic_Output,
    op: ^Tex_Math_Op) -> bool {
    _, ok := tex_semantic_append_text(output, "{")
    ok = tex_math_append_program_plain(output, op.child_program) && ok
    _, close_ok := tex_semantic_append_text(output, "}")
    ok = ok && close_ok
    if op.secondary_program >= 0 {
        ok = tex_math_append_script_suffix(output, "^{", op.secondary_program) && ok
    }
    if op.tertiary_program >= 0 {
        ok = tex_math_append_script_suffix(output, "_{", op.tertiary_program) && ok
    }
    return ok
}

//   Append one canonical braced script suffix.
tex_math_append_script_suffix :: proc(
    output: ^Tex_Semantic_Output,
    prefix: string,
    program_id: int) -> bool {
    _, first_ok := tex_semantic_append_text(output, prefix)
    child_ok := tex_math_append_program_plain(output, program_id)
    _, last_ok := tex_semantic_append_text(output, "}")
    return first_ok && child_ok && last_ok
}

//   Append one large operator and its subscript-before-superscript fallback.
tex_math_append_large_operator_plain :: proc(
    output: ^Tex_Semantic_Output,
    op: ^Tex_Math_Op) -> bool {
    ok := true
    if op.style_role == .Operator_Name_Star {
        _, ok = tex_semantic_append_text(output, "\\operatorname*{")
        _, text_ok := tex_semantic_append_text(
            output, tex_semantic_text(output, op.text))
        _, close_ok := tex_semantic_append_text(output, "}")
        ok = ok && text_ok && close_ok
    } else {
        _, ok = tex_semantic_append_text(output, tex_semantic_text(output, op.text))
    }
    if op.secondary_program >= 0 {
        ok = tex_math_append_script_suffix(output, "_{", op.secondary_program) && ok
    }
    if op.child_program >= 0 {
        ok = tex_math_append_script_suffix(output, "^{", op.child_program) && ok
    }
    return ok
}

//   Append one square-root or nth-root canonical fallback.
tex_math_append_radical_plain :: proc(
    output: ^Tex_Semantic_Output,
    op: ^Tex_Math_Op) -> bool {
    _, ok := tex_semantic_append_text(output, "\\sqrt")
    if op.secondary_program >= 0 {
        _, open_ok := tex_semantic_append_text(output, "[")
        degree_ok := tex_math_append_program_plain(output, op.secondary_program)
        _, close_ok := tex_semantic_append_text(output, "]")
        ok = ok && open_ok && degree_ok && close_ok
    }
    _, open_ok := tex_semantic_append_text(output, "{")
    child_ok := tex_math_append_program_plain(output, op.child_program)
    _, close_ok := tex_semantic_append_text(output, "}")
    return ok && open_ok && child_ok && close_ok
}

//   Build the canonical fraction text from two child programs.
tex_math_fraction_text :: proc(
    output: ^Tex_Semantic_Output,
    numerator, denominator: int) -> Tex_Text_Span {
    numerator_text := tex_math_program_plain_span(output, numerator)
    denominator_text := tex_math_program_plain_span(output, denominator)
    start := output.text_count
    parts := [?]string{
        "{", tex_semantic_text(output, numerator_text), "}/{",
        tex_semantic_text(output, denominator_text), "}"}
    for text in parts {
        _, _ = tex_semantic_append_text(output, text)
    }
    return {offset = start, length = output.text_count-start}
}