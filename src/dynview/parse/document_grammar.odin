package dynview_parse

TEX_DOCUMENT_STYLE_REGULAR :: i32(4)
TEX_DOCUMENT_STYLE_BOLD :: i32(32)
TEX_DOCUMENT_STYLE_ITALIC :: i32(1)

// Distinguish standalone math from complete semantic documents.
Tex_Source_Mode :: enum {
    Math,
    Document,
}

// Describe one recognized document math delimiter pair.
Tex_Document_Math_Delimiters :: struct {
    opener: string,
    closer: string,
    is_inline: bool,
    present: bool,
}

// Describe one recognized Euclid shape command.
Tex_Document_Shape_Command :: struct {
    kind: Tex_Document_Shape_Kind,
    text: string,
    present: bool,
}

// Describe one complete outer math fragment.
Tex_Document_Whole_Math :: struct {
    content: string,
    style: Tex_Math_Root_Style,
    present: bool,
}

// Identify one supported prose alignment environment during recursive parsing.
Tex_Document_Environment :: enum u8 {
    None,
    Center,
    Flush_Left,
    Flush_Right,
}

// Carry inherited prose style and one recursive sequence terminator.
Tex_Document_Parse_Context :: struct {
    font_flags: i32,
    color: Tex_Document_Color,
    environment: Tex_Document_Environment,
    stop_on_brace: bool,
}

// Track bounded recursive document parsing without allocation.
Tex_Document_Parser :: struct {
    source: string,
    offset: int,
    work_count: int,
    depth: int,
    active_paragraph: int,
    paragraph_alignment: Tex_Document_Alignment,
    pending_no_indent: bool,
    limits: Tex_Parse_Limits,
    output: ^Tex_Semantic_Output,
}

//   Classify one source using the frozen document-marker heuristic.
tex_classify_source_mode :: proc(source: string) -> Tex_Source_Mode {
    text := tex_document_trim(source)
    if tex_document_whole_math(text).present ||
        tex_source_starts_math_environment(text) {
        return .Math
    }
    markers := [?]string{
        "\\textbf{", "\\textit{", "\\emph{", "\\textcolor{",
        "\\textnormal{", "\\texttt{", "\\bfseries", "\\itshape",
        "\\begin{", "\\noindent", "\\newline", "\\par", "\\euclid",
        "\\%", "\\#", "\\_", "\\&", "\\{", "\\}", "\\ ",
        "\\\\", "$", "\\(", "\\[", "~", "%",
    }
    for marker in markers {
        if tex_document_contains(text, marker) {
            return .Document
        }
    }
    return .Math
}

// Report whether source starts with a matrix-like environment valid only in math mode.
tex_source_starts_math_environment :: proc(source: string) -> bool {
    prefix := "\\begin{"
    if len(source) <= len(prefix) || source[:len(prefix)] != prefix {
        return false
    }
    close := tex_document_find(source, "}", len(prefix))
    if close < 0 {return false}
    return tex_table_environment_supported(source[len(prefix):close])
}

//   Parse a complete document transaction into bounded semantic blocks and inlines.
tex_parse_document :: proc(
    source: string,
    output: ^Tex_Semantic_Output,
    limits := TEX_PARSE_DEFAULT_LIMITS) -> Tex_Parse_Status {
    if !tex_semantic_output_init(output) {
        return .Work_Limit
    }
    parser := Tex_Document_Parser{
        source = source,
        active_paragraph = -1,
        paragraph_alignment = .Left,
        output = output,
        limits = limits,
    }
    status := tex_document_validate_source(&parser)
    if status == .Ok {
        status = tex_document_parse_sequence(&parser, {
            font_flags = TEX_DOCUMENT_STYLE_REGULAR,
        })
    }
    if status == .Ok {
        tex_document_close_paragraph(&parser)
    }
    output.status = status
    output.error_offset = parser.offset
    if status != .Ok {
        output.document_block_count = 0
        output.document_inline_count = 0
        output.document_display_row_count = 0
    }
    return status
}

//   Validate source bytes and admission limits before semantic mutation.
tex_document_validate_source :: proc(
    parser: ^Tex_Document_Parser) -> Tex_Parse_Status {
    if len(parser.source) > parser.limits.source_bytes {
        return .Source_Too_Large
    }
    offset := 0
    for offset < len(parser.source) {
        width := tex_utf8_sequence_width(parser.source, offset)
        if width == 0 {
            parser.offset = offset
            return .Invalid_Utf8
        }
        offset += width
    }
    return .Ok
}

//   Parse runs recursively through source end or one required closing brace.
tex_document_parse_sequence :: proc(
    parser: ^Tex_Document_Parser,
    inherited: Tex_Document_Parse_Context) -> Tex_Parse_Status {

    if parser.depth >= parser.limits.depth {
        return .Work_Limit
    }
    parse_ctx := inherited
    parser.depth += 1
    defer parser.depth -= 1
    for parser.offset < len(parser.source) {
        if !tex_document_charge(parser) {
            return .Work_Limit
        }
        if parser.source[parser.offset] == '}' {
            parser.offset += 1
            return .Ok if parse_ctx.stop_on_brace else .Unexpected_Token
        }
        if tex_document_environment_ends(parser, parse_ctx.environment) {
            tex_document_close_paragraph(parser)
            tex_document_consume_environment_end(parser, parse_ctx.environment)
            return .Ok
        }
        if parser.source[parser.offset] == '{' {
            status := tex_document_parse_group(parser, parse_ctx)
            if status != .Ok {return status}
        } else if !tex_document_parse_declaration(parser, &parse_ctx) {
            status := tex_document_parse_run(parser, parse_ctx)
            if status != .Ok {return status}
        }
    }
    return .Unclosed_Group if parse_ctx.stop_on_brace ||
        parse_ctx.environment != .None else .Ok
}

// Parse one bare brace group while preserving value-scoped declarations.
tex_document_parse_group :: proc(
    parser: ^Tex_Document_Parser,
    inherited: Tex_Document_Parse_Context) -> Tex_Parse_Status {

    parser.offset += 1
    nested := inherited
    nested.stop_on_brace = true
    return tex_document_parse_sequence(parser, nested)
}

//   Parse one styled, colored, shape, math, break, or prose run.
tex_document_parse_run :: proc(
    parser: ^Tex_Document_Parser,
    parse_ctx: Tex_Document_Parse_Context) -> Tex_Parse_Status {

    display_info := tex_document_display_info(parser)
    if display_info.kind != .Plain {
        return tex_document_parse_display_environment(
            parser, display_info, parse_ctx.color)
    }
    environment := tex_document_environment_starts(parser)
    if environment != .None {
        return tex_document_parse_environment(parser, parse_ctx, environment)
    }
    style_status, style_handled := tex_document_parse_style_command(
        parser, parse_ctx)
    if style_handled {return style_status}
    if tex_document_starts(parser, "\\textcolor{") {
        return tex_document_parse_color(
            parser, parse_ctx.font_flags, parse_ctx.color)
    }
    shape_command := tex_document_shape_command(parser)
    if shape_command.present {
        return tex_document_parse_shape(parser, parse_ctx.font_flags, parse_ctx.color,
            shape_command.kind, shape_command.text)
    }
    if tex_document_math_delimiters(parser).present {
        return tex_document_parse_math_run(parser, parse_ctx.color)
    }
    return tex_document_parse_prose_or_break(
        parser, parse_ctx.font_flags, parse_ctx.color)
}


// Parse one scoped prose style command when the current source begins one.
tex_document_parse_style_command :: proc(
    parser: ^Tex_Document_Parser,
    parse_ctx: Tex_Document_Parse_Context) -> (Tex_Parse_Status, bool) {

    if tex_document_starts(parser, "\\textbf{") {
        parser.offset += len("\\textbf{")
        nested := parse_ctx
        nested.font_flags |= TEX_DOCUMENT_STYLE_BOLD
        nested.stop_on_brace = true
        return tex_document_parse_sequence(parser, nested), true
    }
    if tex_document_starts(parser, "\\textit{") ||
        tex_document_starts(parser, "\\emph{") {
        command := "\\textit{" if tex_document_starts(
            parser, "\\textit{") else "\\emph{"
        parser.offset += len(command)
        nested := parse_ctx
        nested.font_flags |= TEX_DOCUMENT_STYLE_ITALIC
        nested.stop_on_brace = true
        return tex_document_parse_sequence(parser, nested), true
    }
    if tex_document_starts(parser, "\\textnormal{") {
        parser.offset += len("\\textnormal{")
        nested := parse_ctx
        nested.font_flags = TEX_DOCUMENT_STYLE_REGULAR
        nested.stop_on_brace = true
        return tex_document_parse_sequence(parser, nested), true
    }
    if tex_document_starts(parser, "\\texttt{") {
        parser.offset += len("\\texttt{")
        nested := parse_ctx
        nested.stop_on_brace = true
        return tex_document_parse_sequence(parser, nested), true
    }
    if tex_document_starts(parser, "\\textrm{") ||
        tex_document_starts(parser, "\\textsc{") {
        return .Unexpected_Token, true
    }
    return .Ok, false
}

//   Parse one nested text-color command with unresolved-name inheritance.
tex_document_parse_color :: proc(
    parser: ^Tex_Document_Parser,
    font_flags: i32,
    inherited: Tex_Document_Color) -> Tex_Parse_Status {
    parser.offset += len("\\textcolor")
    name, ok := tex_document_take_group_source(parser)
    if !ok || parser.offset >= len(parser.source) ||
        parser.source[parser.offset] != '{' {
        return .Unexpected_Token
    }
    color, resolved := tex_document_resolve_color(tex_document_trim(name))
    if !resolved {
        color = inherited
    }
    parser.offset += 1
    return tex_document_parse_sequence(parser, {
        font_flags = font_flags, color = color, stop_on_brace = true,
    })
}

//   Parse and append one validated Euclid inline shape.
tex_document_parse_shape :: proc(
    parser: ^Tex_Document_Parser,
    font_flags: i32,
    color: Tex_Document_Color,
    shape_kind: Tex_Document_Shape_Kind,
    command: string) -> Tex_Parse_Status {
    source_start := parser.offset
    parser.offset += len(command)
    shape, ok := tex_document_parse_shape_options(parser, shape_kind)
    if !ok {
        return .Unexpected_Token
    }
    return tex_document_append_paragraph_inline(parser, {
        kind = .Shape,
        source = {source_start, parser.offset - source_start},
        font_flags = font_flags,
        color = color,
        shape = shape,
        math_program = -1,
    })
}

//   Parse one trimmed inline or display math fragment into semantic structure.
tex_document_parse_math_run :: proc(
    parser: ^Tex_Document_Parser,
    color: Tex_Document_Color) -> Tex_Parse_Status {
    source_start := parser.offset
    delimiters := tex_document_math_delimiters(parser)
    content_start := parser.offset + len(delimiters.opener)
    close_offset := tex_document_find(
        parser.source, delimiters.closer, content_start)
    if close_offset < 0 {
        return .Unexpected_Token
    }
    content := tex_document_trim(parser.source[content_start:close_offset])
    if len(content) == 0 {
        return .Unexpected_Token
    }
    parser.offset = close_offset + len(delimiters.closer)
    style := Tex_Math_Root_Style.Display
    if delimiters.is_inline {
        style = .Text
    }
    program, status := tex_parse_math_fragment(
        content, style, parser.output, parser.limits)
    if status != .Ok {
        return status
    }
    span, span_ok := tex_semantic_append_text(parser.output, content)
    if !span_ok {
        return .Work_Limit
    }
    return tex_document_append_semantic_math(
        parser, span, color, style, program, source_start, delimiters.is_inline)
}

//   Append parsed math to its semantic paragraph or display block.
tex_document_append_semantic_math :: proc(
    parser: ^Tex_Document_Parser,
    text: Tex_Text_Span,
    color: Tex_Document_Color,
    root_style: Tex_Math_Root_Style,
    math_program: int,
    source_start: int,
    is_inline: bool) -> Tex_Parse_Status {
    item := Tex_Document_Inline{
        kind = .Math,
        source = {source_start, parser.offset - source_start},
        text = text,
        color = color,
        root_style = root_style,
        math_program = math_program,
    }
    if is_inline {
        return tex_document_append_paragraph_inline(parser, item)
    }
    tex_document_close_paragraph(parser)
    block_index := tex_semantic_append_document_block(parser.output, {
        kind = .Display,
        inline_start = parser.output.document_inline_count,
        source = item.source,
        format = {alignment = .Center},
    })
    if block_index < 0 ||
        !tex_semantic_append_document_inline(parser.output, block_index, item) {
        return .Work_Limit
    }
    return .Ok
}

//   Parse source newlines, forced breaks, ordinary prose, or reject commands.
tex_document_parse_prose_or_break :: proc(
    parser: ^Tex_Document_Parser,
    font_flags: i32,
    color: Tex_Document_Color) -> Tex_Parse_Status {
    control_status, handled := tex_document_parse_prose_control(
        parser, font_flags, color)
    if handled {return control_status}
    break_status, break_handled := tex_document_parse_break_control(
        parser, font_flags, color)
    if break_handled {return break_status}
    if parser.source[parser.offset] == '\\' ||
        parser.source[parser.offset] == '$' {
        return .Unexpected_Token
    }
    return tex_document_parse_text(parser, font_flags, color)
}

// Parse a prose newline or explicit paragraph and line-break command when present.
tex_document_parse_break_control :: proc(
    parser: ^Tex_Document_Parser,
    font_flags: i32,
    color: Tex_Document_Color) -> (Tex_Parse_Status, bool) {

    if parser.source[parser.offset] == '\n' {
        return tex_document_parse_newlines(parser, font_flags, color), true
    }
    if tex_document_starts(parser, "\\\\") {
        source_start := parser.offset
        parser.offset += 2
        tex_document_consume_break_whitespace(parser)
        return tex_document_append_forced_break(parser, source_start), true
    }
    if tex_document_command_starts(parser, "\\newline") {
        source_start := parser.offset
        parser.offset += len("\\newline")
        tex_document_consume_break_whitespace(parser)
        return tex_document_append_forced_break(parser, source_start), true
    }
    if tex_document_command_starts(parser, "\\par") {
        parser.offset += len("\\par")
        tex_document_close_paragraph(parser)
        return .Ok, true
    }
    if tex_document_command_starts(parser, "\\noindent") {
        if parser.active_paragraph >= 0 {
            return .Unexpected_Token, true
        }
        parser.offset += len("\\noindent")
        parser.pending_no_indent = true
        return .Ok, true
    }
    return .Ok, false
}

// Parse a prose comment, escaped special, or controlled-space symbol when present.
tex_document_parse_prose_control :: proc(
    parser: ^Tex_Document_Parser,
    font_flags: i32,
    color: Tex_Document_Color) -> (Tex_Parse_Status, bool) {

    if parser.source[parser.offset] == '%' {
        tex_document_consume_comment(parser)
        return .Ok, true
    }
    if tex_document_is_escaped_special(parser) {
        return tex_document_parse_escaped_special(
            parser, font_flags, color), true
    }
    if !tex_document_starts(parser, "\\ ") {return .Ok, false}
    source_start := parser.offset
    parser.offset += 2
    return tex_document_append_semantic_space(
        parser, {source_start, 2}, .Controlled, font_flags, color), true
}

//   Normalize one source newline run to a space or a blank line.
tex_document_parse_newlines :: proc(
    parser: ^Tex_Document_Parser,
    font_flags: i32,
    color: Tex_Document_Color) -> Tex_Parse_Status {
    source_start := parser.offset
    newline_count := 0
    for parser.offset < len(parser.source) &&
        tex_math_ascii_space(parser.source[parser.offset]) {
        if parser.source[parser.offset] == '\n' {
            newline_count += 1
        }
        parser.offset += 1
    }
    if newline_count < 2 {
        if parser.active_paragraph < 0 {
            return .Ok
        }
        return tex_document_append_semantic_space(parser,
            {source_start, parser.offset - source_start},
            .Breakable, font_flags, color)
    }
    tex_document_close_paragraph(parser)
    return .Ok
}

//   Parse ordinary document bytes up to the next syntax character.
tex_document_parse_text :: proc(
    parser: ^Tex_Document_Parser,
    font_flags: i32,
    color: Tex_Document_Color) -> Tex_Parse_Status {
    start := parser.offset
    for parser.offset < len(parser.source) {
        value := parser.source[parser.offset]
        if value == '\\' || value == '$' || value == '{' || value == '}' ||
            value == '%' || value == '\n' {
            break
        }
        width := tex_utf8_sequence_width(parser.source, parser.offset)
        parser.offset += width
    }
    text := parser.source[start:parser.offset]
    status := tex_document_append_semantic_prose(
        parser, text, start, font_flags, color)
    if status != .Ok {
        return status
    }
    return .Ok
}

//   Lower one prose source span to text and semantic space nodes.
tex_document_append_semantic_prose :: proc(
    parser: ^Tex_Document_Parser,
    text: string,
    source_start: int,
    font_flags: i32,
    color: Tex_Document_Color) -> Tex_Parse_Status {
    start := 0
    for index := 0; index < len(text); {
        if text[index] == '~' {
            status := tex_document_append_semantic_text_span(
                parser, text[start:index], source_start + start, font_flags, color)
            if status != .Ok {return status}
            status = tex_document_append_semantic_space(
                parser, {source_start + index, 1}, .Nonbreaking, font_flags, color)
            if status != .Ok {return status}
            index += 1
            start = index
            continue
        }
        if tex_math_ascii_space(text[index]) {
            status := tex_document_append_semantic_text_span(
                parser, text[start:index], source_start + start, font_flags, color)
            if status != .Ok {return status}
            space_start := index
            for index < len(text) && tex_math_ascii_space(text[index]) {index += 1}
            status = tex_document_append_semantic_space(parser,
                {source_start + space_start, index - space_start},
                .Breakable, font_flags, color)
            if status != .Ok {return status}
            start = index
            continue
        }
        index += tex_utf8_sequence_width(text, index)
    }
    return tex_document_append_semantic_text_span(
        parser, text[start:], source_start + start, font_flags, color)
}

//   Append one semantic text node with its canonical bytes and source range.
tex_document_append_semantic_text_span :: proc(
    parser: ^Tex_Document_Parser,
    text: string,
    source_start: int,
    font_flags: i32,
    color: Tex_Document_Color) -> Tex_Parse_Status {
    if len(text) == 0 {return .Ok}
    span, ok := tex_semantic_append_text(parser.output, text)
    if !ok {return .Work_Limit}
    return tex_document_append_paragraph_inline(parser, {
        kind = .Text,
        source = {source_start, len(text)},
        text = span,
        font_flags = font_flags,
        color = color,
        math_program = -1,
    })
}

//   Append one semantic spacing node without assigning physical dimensions.
tex_document_append_semantic_space :: proc(
    parser: ^Tex_Document_Parser,
    source: Tex_Source_Span,
    kind: Tex_Document_Space_Kind,
    font_flags: i32,
    color: Tex_Document_Color) -> Tex_Parse_Status {
    if parser.active_paragraph < 0 && kind == .Breakable {
        return .Ok
    }
    text, ok := tex_semantic_append_text(parser.output, " ")
    if !ok {return .Work_Limit}
    return tex_document_append_paragraph_inline(parser, {
        kind = .Space,
        source = source,
        text = text,
        font_flags = font_flags,
        color = color,
        space_kind = kind,
        math_program = -1,
    })
}

//   Append an inline to the current paragraph, opening one when necessary.
tex_document_append_paragraph_inline :: proc(
    parser: ^Tex_Document_Parser,
    item: Tex_Document_Inline) -> Tex_Parse_Status {
    if parser.active_paragraph < 0 {
        parser.active_paragraph = tex_semantic_append_document_block(
            parser.output, {
                kind = .Paragraph,
                inline_start = parser.output.document_inline_count,
                source = {item.source.offset, 0},
                format = {
                    alignment = parser.paragraph_alignment,
                    no_indent = parser.pending_no_indent,
                },
            })
        parser.pending_no_indent = false
    }
    if parser.active_paragraph < 0 || !tex_semantic_append_document_inline(
        parser.output, parser.active_paragraph, item) {
        return .Work_Limit
    }
    return .Ok
}

// Apply one scoped declaration to the remainder of the current group.
tex_document_parse_declaration :: proc(
    parser: ^Tex_Document_Parser,
    parse_ctx: ^Tex_Document_Parse_Context) -> bool {

    if tex_document_command_starts(parser, "\\bfseries") {
        parser.offset += len("\\bfseries")
        parse_ctx.font_flags |= TEX_DOCUMENT_STYLE_BOLD
        return true
    }
    if tex_document_command_starts(parser, "\\itshape") {
        parser.offset += len("\\itshape")
        parse_ctx.font_flags |= TEX_DOCUMENT_STYLE_ITALIC
        return true
    }
    return false
}

// Return the alignment environment beginning at the current source offset.
tex_document_environment_starts :: proc(
    parser: ^Tex_Document_Parser) -> Tex_Document_Environment {

    if tex_document_starts(parser, "\\begin{center}") {return .Center}
    if tex_document_starts(parser, "\\begin{flushleft}") {return .Flush_Left}
    if tex_document_starts(parser, "\\begin{flushright}") {return .Flush_Right}
    return .None
}

// Return the exact source spelling for one supported alignment environment.
tex_document_environment_name :: proc(environment: Tex_Document_Environment) -> string {
    switch environment {
    case .Center: return "center"
    case .Flush_Left: return "flushleft"
    case .Flush_Right: return "flushright"
    case .None: return ""
    }
    return ""
}

// Report whether the current source closes the active alignment environment.
tex_document_environment_ends :: proc(
    parser: ^Tex_Document_Parser,
    environment: Tex_Document_Environment) -> bool {

    switch environment {
    case .Center: return tex_document_starts(parser, "\\end{center}")
    case .Flush_Left: return tex_document_starts(parser, "\\end{flushleft}")
    case .Flush_Right: return tex_document_starts(parser, "\\end{flushright}")
    case .None: return false
    }
    return false
}

// Consume the already-validated closing command for one environment.
tex_document_consume_environment_end :: proc(
    parser: ^Tex_Document_Parser,
    environment: Tex_Document_Environment) {

    parser.offset += len("\\end{")+len(tex_document_environment_name(environment))+1
}

// Parse one alignment environment as complete paragraphs with inherited inline style.
tex_document_parse_environment :: proc(
    parser: ^Tex_Document_Parser,
    inherited: Tex_Document_Parse_Context,
    environment: Tex_Document_Environment) -> Tex_Parse_Status {

    tex_document_close_paragraph(parser)
    name := tex_document_environment_name(environment)
    parser.offset += len("\\begin{")+len(name)+1
    prior_alignment := parser.paragraph_alignment
    switch environment {
    case .Center: parser.paragraph_alignment = .Center
    case .Flush_Left: parser.paragraph_alignment = .Left
    case .Flush_Right: parser.paragraph_alignment = .Right
    case .None: return .Unexpected_Token
    }
    nested := inherited
    nested.environment = environment
    nested.stop_on_brace = false
    status := tex_document_parse_sequence(parser, nested)
    tex_document_close_paragraph(parser)
    parser.paragraph_alignment = prior_alignment
    return status
}

// Report whether one control symbol emits a literal prose special.
tex_document_is_escaped_special :: proc(parser: ^Tex_Document_Parser) -> bool {
    if parser.offset > len(parser.source)-2 || parser.source[parser.offset] != '\\' {
        return false
    }
    value := parser.source[parser.offset+1]
    return value == '%' || value == '#' || value == '_' || value == '&' ||
        value == '{' || value == '}'
}

// Append one escaped prose special while preserving its two-byte source span.
tex_document_parse_escaped_special :: proc(
    parser: ^Tex_Document_Parser,
    font_flags: i32,
    color: Tex_Document_Color) -> Tex_Parse_Status {

    source_start := parser.offset
    parser.offset += 2
    return tex_document_append_semantic_text_span(parser,
        parser.source[source_start+1:parser.offset], source_start,
        font_flags, color)
}

// Consume a prose comment and its terminating source newline.
tex_document_consume_comment :: proc(parser: ^Tex_Document_Parser) {
    for parser.offset < len(parser.source) &&
        parser.source[parser.offset] != '\n' {
        parser.offset += 1
    }
    if parser.offset < len(parser.source) {
        parser.offset += 1
    }
}

//   Close one paragraph after removing trailing breakable spacing nodes.
tex_document_close_paragraph :: proc(parser: ^Tex_Document_Parser) {
    if parser.active_paragraph < 0 {return}
    block := &parser.output.document_blocks[parser.active_paragraph]
    for block.inline_count > 0 {
        item := &parser.output.document_inlines[
            block.inline_start + block.inline_count - 1]
        if item.kind != .Space || item.space_kind != .Breakable {break}
        block.inline_count -= 1
        parser.output.document_inline_count -= 1
    }
    if block.inline_count == 0 {
        parser.output.document_block_count -= 1
    } else {
        last := &parser.output.document_inlines[
            block.inline_start + block.inline_count - 1]
        block.source.length = last.source.offset + last.source.length -
            block.source.offset
    }
    parser.active_paragraph = -1
}

//   Preserve one explicit line break inside the current paragraph.
tex_document_append_forced_break :: proc(
    parser: ^Tex_Document_Parser,
    source_start: int) -> Tex_Parse_Status {
    if parser.active_paragraph < 0 {
        return .Unexpected_Token
    }
    return tex_document_append_paragraph_inline(parser, {
        kind = .Forced_Break,
        source = {source_start, parser.offset - source_start},
        math_program = -1,
    })
}

//   Return the supported shape command at the current source offset.
tex_document_shape_command :: proc(
    parser: ^Tex_Document_Parser) -> Tex_Document_Shape_Command {
    commands := [?]string{
        "\\euclidpoint", "\\euclidline", "\\euclidcircle", "\\euclidbox",
        "\\euclidangle", "\\euclidsemicircle", "\\euclidperpendicular",
        "\\euclidtriangle", "\\euclidpentagon",
    }
    kinds := [?]Tex_Document_Shape_Kind{
        .Point, .Line, .Circle, .Box, .Angle, .Semicircle,
        .Perpendicular, .Triangle, .Pentagon,
    }
    for index in 0..<len(commands) {
        if tex_document_command_starts(parser, commands[index]) {
            return {kind = kinds[index], text = commands[index], present = true}
        }
    }
    return {}
}

//   Return math delimiters and whether they imply inline Text style.
tex_document_math_delimiters :: proc(
    parser: ^Tex_Document_Parser) -> Tex_Document_Math_Delimiters {
    if tex_document_starts(parser, "$$") {
        return {opener = "$$", closer = "$$", present = true}
    }
    if tex_document_starts(parser, "$") {
        return {opener = "$", closer = "$", is_inline = true, present = true}
    }
    if tex_document_starts(parser, "\\(") {
        return {
            opener = "\\(",
            closer = "\\)",
            is_inline = true,
            present = true,
        }
    }
    if tex_document_starts(parser, "\\[") {
        return {opener = "\\[", closer = "\\]", present = true}
    }
    return {}
}

//   Return a complete outer math fragment and its root style.
tex_document_whole_math :: proc(
    source: string) -> Tex_Document_Whole_Math {
    parser := Tex_Document_Parser{source = source}
    delimiters := tex_document_math_delimiters(&parser)
    if !delimiters.present ||
        len(source) < len(delimiters.opener)+len(delimiters.closer) ||
        source[len(source)-len(delimiters.closer):] != delimiters.closer {
        return {}
    }
    content := source[
        len(delimiters.opener):len(source)-len(delimiters.closer)]
    style := Tex_Math_Root_Style.Text if delimiters.is_inline else .Display
    return {content = content, style = style, present = true}
}

//   Consume one nonnested braced source field.
tex_document_take_group_source :: proc(
    parser: ^Tex_Document_Parser) -> (string, bool) {
    if parser.offset >= len(parser.source) || parser.source[parser.offset] != '{' {
        return "", false
    }
    start := parser.offset + 1
    end := start
    for end < len(parser.source) && parser.source[end] != '}' {
        end += 1
    }
    if end >= len(parser.source) {
        return "", false
    }
    parser.offset = end + 1
    return parser.source[start:end], true
}

//   Consume whitespace attached to one forced line break.
tex_document_consume_break_whitespace :: proc(parser: ^Tex_Document_Parser) {
    for parser.offset < len(parser.source) &&
        (parser.source[parser.offset] == ' ' || parser.source[parser.offset] == '\t') {
        parser.offset += 1
    }
    if parser.offset >= len(parser.source) || parser.source[parser.offset] != '\n' {
        return
    }
    next := parser.offset + 1
    for next < len(parser.source) &&
        (parser.source[next] == ' ' || parser.source[next] == '\t') {
        next += 1
    }
    if next >= len(parser.source) || parser.source[next] != '\n' {
        parser.offset = next
    }
}

//   Charge one document parser work unit.
tex_document_charge :: proc(parser: ^Tex_Document_Parser) -> bool {
    if parser.work_count >= parser.limits.work_units {
        return false
    }
    parser.work_count += 1
    return true
}

//   Return whether one literal starts at the parser offset.
tex_document_starts :: proc(
    parser: ^Tex_Document_Parser,
    text: string) -> bool {
    return parser.offset <= len(parser.source)-len(text) &&
        parser.source[parser.offset:parser.offset+len(text)] == text
}

//   Match a complete control word rather than a longer command prefix.
tex_document_command_starts :: proc(
    parser: ^Tex_Document_Parser,
    command: string) -> bool {
    if !tex_document_starts(parser, command) {
        return false
    }
    next := parser.offset + len(command)
    return next >= len(parser.source) || parser.source[next] < 'A' ||
        parser.source[next] > 'Z' && parser.source[next] < 'a' ||
        parser.source[next] > 'z'
}

//   Find one literal byte sequence at or after a source offset.
tex_document_find :: proc(source, text: string, start: int) -> int {
    if len(text) == 0 {
        return -1
    }
    for index in start..=len(source)-len(text) {
        if source[index:index+len(text)] == text {
            return index
        }
    }
    return -1
}

//   Return whether a source contains one literal byte sequence.
tex_document_contains :: proc(source, text: string) -> bool {
    return tex_document_find(source, text, 0) >= 0
}