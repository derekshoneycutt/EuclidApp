package dynview_parse

TEX_DOCUMENT_STYLE_REGULAR :: i32(4)
TEX_DOCUMENT_STYLE_BOLD :: i32(32)
TEX_DOCUMENT_STYLE_ITALIC :: i32(1)

// Distinguish standalone math from complete flat documents.
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

// Track bounded recursive document parsing without allocation.
Tex_Document_Parser :: struct {
    source: string,
    offset: int,
    work_count: int,
    depth: int,
    limits: Tex_Parse_Limits,
    output: ^Tex_Semantic_Output,
}

//   Classify one source using the frozen document-marker heuristic.
tex_classify_source_mode :: proc(source: string) -> Tex_Source_Mode {
    text := tex_document_trim(source)
    if tex_document_whole_math(text).present {
        return .Math
    }
    markers := [?]string{
        "\\textbf{", "\\textit{", "\\emph{", "\\textcolor{",
        "\\newline", "\\euclid", "\\\\", "$", "\\(", "\\[",
    }
    for marker in markers {
        if tex_document_contains(text, marker) {
            return .Document
        }
    }
    return .Math
}

//   Parse a complete flat document transaction into bounded semantic runs.
tex_parse_document :: proc(
    source: string,
    output: ^Tex_Semantic_Output,
    limits := TEX_PARSE_DEFAULT_LIMITS) -> Tex_Parse_Status {
    if !tex_semantic_output_init(output) {
        return .Work_Limit
    }
    parser := Tex_Document_Parser{
        source = source,
        output = output,
        limits = limits,
    }
    status := tex_document_validate_source(&parser)
    if status == .Ok {
        status = tex_document_parse_sequence(
            &parser, TEX_DOCUMENT_STYLE_REGULAR, {}, false)
    }
    output.status = status
    output.error_offset = parser.offset
    if status != .Ok {
        output.document_run_count = 0
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
    font_flags: i32,
    color: Tex_Document_Color,
    stop_on_brace: bool) -> Tex_Parse_Status {
    if parser.depth >= parser.limits.depth {
        return .Work_Limit
    }
    parser.depth += 1
    defer parser.depth -= 1
    for parser.offset < len(parser.source) {
        if !tex_document_charge(parser) {
            return .Work_Limit
        }
        if parser.source[parser.offset] == '}' {
            parser.offset += 1
            return .Ok if stop_on_brace else .Unexpected_Token
        }
        status := tex_document_parse_run(parser, font_flags, color)
        if status != .Ok {
            return status
        }
    }
    return .Unclosed_Group if stop_on_brace else .Ok
}

//   Parse one styled, colored, shape, math, break, or prose run.
tex_document_parse_run :: proc(
    parser: ^Tex_Document_Parser,
    font_flags: i32,
    color: Tex_Document_Color) -> Tex_Parse_Status {
    if tex_document_starts(parser, "\\textbf{") {
        parser.offset += len("\\textbf{")
        return tex_document_parse_sequence(
            parser, font_flags | TEX_DOCUMENT_STYLE_BOLD, color, true)
    }
    if tex_document_starts(parser, "\\textit{") ||
        tex_document_starts(parser, "\\emph{") {
        command := "\\textit{" if tex_document_starts(
            parser, "\\textit{") else "\\emph{"
        parser.offset += len(command)
        return tex_document_parse_sequence(
            parser, font_flags | TEX_DOCUMENT_STYLE_ITALIC, color, true)
    }
    if tex_document_starts(parser, "\\textcolor{") {
        return tex_document_parse_color(parser, font_flags, color)
    }
    shape_command := tex_document_shape_command(parser)
    if shape_command.present {
        return tex_document_parse_shape(parser, font_flags, color,
            shape_command.kind, shape_command.text)
    }
    if tex_document_math_delimiters(parser).present {
        return tex_document_parse_math_run(parser, color)
    }
    return tex_document_parse_prose_or_break(parser, font_flags, color)
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
    return tex_document_parse_sequence(parser, font_flags, color, true)
}

//   Parse and append one validated Euclid inline-shape run.
tex_document_parse_shape :: proc(
    parser: ^Tex_Document_Parser,
    font_flags: i32,
    color: Tex_Document_Color,
    shape_kind: Tex_Document_Shape_Kind,
    command: string) -> Tex_Parse_Status {
    parser.offset += len(command)
    shape, ok := tex_document_parse_shape_options(parser, shape_kind)
    if !ok {
        return .Unexpected_Token
    }
    return tex_document_append_run(parser.output, {
        kind = .Shape,
        font_flags = font_flags,
        color = color,
        shape = shape,
        math_program = -1,
    })
}

//   Parse one trimmed inline or display math fragment into a document run.
tex_document_parse_math_run :: proc(
    parser: ^Tex_Document_Parser,
    color: Tex_Document_Color) -> Tex_Parse_Status {
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
    kind := Tex_Document_Run_Kind.Math_Display
    if delimiters.is_inline {
        style, kind = .Text, .Math_Inline
    }
    program, status := tex_parse_math_fragment(
        content, style, parser.output, parser.limits)
    if status != .Ok {
        return status
    }
    return tex_document_append_math_run(parser.output, content, {
        kind = kind,
        font_flags = TEX_DOCUMENT_STYLE_REGULAR,
        color = color,
        root_style = style,
        math_program = program,
    })
}

//   Publish one parsed document math fragment as a flat run.
tex_document_append_math_run :: proc(
    output: ^Tex_Semantic_Output,
    content: string,
    run: Tex_Document_Run) -> Tex_Parse_Status {
    span, span_ok := tex_semantic_append_text(output, content)
    if !span_ok {
        return .Work_Limit
    }
    published := run
    published.text = span
    return tex_document_append_run(output, published)
}

//   Parse source newlines, forced breaks, ordinary prose, or reject commands.
tex_document_parse_prose_or_break :: proc(
    parser: ^Tex_Document_Parser,
    font_flags: i32,
    color: Tex_Document_Color) -> Tex_Parse_Status {
    if parser.source[parser.offset] == '\n' {
        return tex_document_parse_newlines(parser, font_flags, color)
    }
    if tex_document_starts(parser, "\\\\") {
        parser.offset += 2
        tex_document_consume_break_whitespace(parser)
        return tex_document_append_line_break(parser.output)
    }
    if tex_document_command_starts(parser, "\\newline") {
        parser.offset += len("\\newline")
        tex_document_consume_break_whitespace(parser)
        return tex_document_append_line_break(parser.output)
    }
    if parser.source[parser.offset] == '\\' ||
        parser.source[parser.offset] == '$' {
        return .Unexpected_Token
    }
    return tex_document_parse_text(parser, font_flags, color)
}

//   Normalize one source newline run to a space or a blank line.
tex_document_parse_newlines :: proc(
    parser: ^Tex_Document_Parser,
    font_flags: i32,
    color: Tex_Document_Color) -> Tex_Parse_Status {
    newline_count := 0
    for parser.offset < len(parser.source) &&
        tex_math_ascii_space(parser.source[parser.offset]) {
        if parser.source[parser.offset] == '\n' {
            newline_count += 1
        }
        parser.offset += 1
    }
    if newline_count < 2 {
        return tex_document_append_text(parser.output, " ", font_flags, color)
    }
    status := tex_document_append_line_break(parser.output)
    if status == .Ok {
        status = tex_document_append_line_break(parser.output)
    }
    return status
}

//   Parse ordinary document bytes up to the next syntax character.
tex_document_parse_text :: proc(
    parser: ^Tex_Document_Parser,
    font_flags: i32,
    color: Tex_Document_Color) -> Tex_Parse_Status {
    start := parser.offset
    for parser.offset < len(parser.source) {
        value := parser.source[parser.offset]
        if value == '\\' || value == '$' || value == '}' || value == '\n' {
            break
        }
        width := tex_utf8_sequence_width(parser.source, parser.offset)
        parser.offset += width
    }
    return tex_document_append_normalized_text(
        parser.output, parser.source[start:parser.offset], font_flags, color)
}

//   Append prose while translating source tildes to nonbreaking spaces.
tex_document_append_normalized_text :: proc(
    output: ^Tex_Semantic_Output,
    text: string,
    font_flags: i32,
    color: Tex_Document_Color) -> Tex_Parse_Status {
    start := 0
    for index in 0..<len(text) {
        if text[index] != '~' {
            continue
        }
        status := tex_document_append_text(
            output, text[start:index], font_flags, color)
        if status != .Ok {
            return status
        }
        status = tex_document_append_text(
            output, "\xc2\xa0", font_flags, color)
        if status != .Ok {
            return status
        }
        start = index + 1
    }
    return tex_document_append_text(output, text[start:], font_flags, color)
}

//   Append text and merge adjacent runs with identical style and color.
tex_document_append_text :: proc(
    output: ^Tex_Semantic_Output,
    text: string,
    font_flags: i32,
    color: Tex_Document_Color) -> Tex_Parse_Status {
    if len(text) == 0 {
        return .Ok
    }
    span, ok := tex_semantic_append_text(output, text)
    if !ok {
        return .Work_Limit
    }
    if output.document_run_count > 0 {
        previous := &output.document_runs[output.document_run_count-1]
        if previous.kind == .Text && previous.font_flags == font_flags &&
            previous.color == color {
            previous.text, ok = tex_semantic_join_text(output, previous.text, span)
            return .Ok if ok else .Work_Limit
        }
    }
    return tex_document_append_run(output, {
        kind = .Text,
        text = span,
        font_flags = font_flags,
        color = color,
        math_program = -1,
    })
}

//   Append one line break while suppressing runs beyond a blank line.
tex_document_append_line_break :: proc(
    output: ^Tex_Semantic_Output) -> Tex_Parse_Status {
    if output.document_run_count >= 2 &&
        output.document_runs[output.document_run_count-1].kind == .Line_Break &&
        output.document_runs[output.document_run_count-2].kind == .Line_Break {
        return .Ok
    }
    return tex_document_append_run(output, {
        kind = .Line_Break,
        font_flags = TEX_DOCUMENT_STYLE_REGULAR,
        math_program = -1,
    })
}

//   Append one checked flat run to bounded document storage.
tex_document_append_run :: proc(
    output: ^Tex_Semantic_Output,
    run: Tex_Document_Run) -> Tex_Parse_Status {
    if output.document_run_count >= len(output.document_runs) {
        return .Work_Limit
    }
    output.document_runs[output.document_run_count] = run
    output.document_run_count += 1
    return .Ok
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