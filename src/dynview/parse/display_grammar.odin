package dynview_parse

// Retain one top-level technical-display environment spelling and policy.
Tex_Document_Display_Info :: struct {
    kind: Tex_Document_Display_Kind,
    opener: string,
    closer: string,
    numbered: bool,
}

// Retain source boundaries discovered while scanning one display row.
Tex_Document_Display_Row_Source :: struct {
    start: int,
    end: int,
    alignment: int,
    notag: int,
}

Tex_Display_Scan_Result :: struct {
    row: Tex_Document_Display_Row_Source,
    next: int,
    ok: bool,
}

Tex_Display_Control_Action :: enum u8 {
    None,
    Continue,
    Row_End,
    Invalid,
}

Tex_Display_Control_Result :: struct {
    action: Tex_Display_Control_Action,
    next: int,
}

// Return the technical display beginning at the parser cursor, if any.
tex_document_display_info :: proc(
    parser: ^Tex_Document_Parser) -> Tex_Document_Display_Info {

    infos := [?]Tex_Document_Display_Info{
        {.Equation, "\\begin{equation*}", "\\end{equation*}", false},
        {.Equation, "\\begin{equation}", "\\end{equation}", true},
        {.Align, "\\begin{align*}", "\\end{align*}", false},
        {.Align, "\\begin{align}", "\\end{align}", true},
        {.Gather, "\\begin{gather*}", "\\end{gather*}", false},
        {.Gather, "\\begin{gather}", "\\end{gather}", true},
        {.Multline, "\\begin{multline*}", "\\end{multline*}", false},
        {.Multline, "\\begin{multline}", "\\end{multline}", true},
    }
    for info in infos {
        if tex_document_starts(parser, info.opener) {return info}
    }
    return {}
}

// Report whether a command at one offset ends before another control word letter.
tex_display_command_at :: proc(source: string, offset: int, command: string) -> bool {
    if offset < 0 || len(command) > len(source)-offset ||
        source[offset:offset+len(command)] != command {
        return false
    }
    end := offset+len(command)
    return end >= len(source) || source[end] < 'A' || source[end] > 'Z' &&
        source[end] < 'a' || source[end] > 'z'
}

// Find the closing boundary of a nested begin/end environment command.
tex_display_environment_command_end :: proc(source: string, offset: int) -> int {
    open := tex_document_find(source, "{", offset)
    if open != offset+len("\\begin") && open != offset+len("\\end") {
        return offset
    }
    close := tex_document_find(source, "}", open+1)
    return close+1 if close >= 0 else offset
}

// Scan one top-level control command and update nested-environment row state.
tex_display_scan_control :: proc(
    source: string,
    offset: int,
    kind: Tex_Document_Display_Kind,
    environment_depth: ^int,
    row: ^Tex_Document_Display_Row_Source) -> Tex_Display_Control_Result {

    command_end := tex_display_environment_command_end(source, offset)
    if command_end > offset {
        if tex_display_command_at(source, offset, "\\begin") {
            environment_depth^ += 1
        } else if environment_depth^ > 0 {
            environment_depth^ -= 1
        } else {
            return {.Invalid, offset}
        }
        return {.Continue, command_end}
    }
    if environment_depth^ == 0 && offset <= len(source)-2 &&
        source[offset:offset+2] == "\\\\" {
        row^.end = offset
        return {.Row_End, offset+2}
    }
    if environment_depth^ != 0 ||
        !tex_display_command_at(source, offset, "\\notag") {
        return {.None, offset}
    }
    if kind != .Align || row^.notag >= 0 {return {.Invalid, offset}}
    row^.notag = offset
    return {.Continue, offset+len("\\notag")}
}

// Scan one row through a top-level separator while preserving nested math tables.
tex_display_scan_row :: proc(
    source: string,
    row_start, body_end: int,
    kind: Tex_Document_Display_Kind) -> Tex_Display_Scan_Result {

    result := Tex_Document_Display_Row_Source{
        start = row_start, end = body_end, alignment = -1, notag = -1}
    brace_depth := 0
    environment_depth := 0
    offset := row_start
    for offset < body_end {
        if source[offset] == '{' {brace_depth += 1; offset += 1; continue}
        if source[offset] == '}' {
            if brace_depth == 0 {return {result, offset, false}}
            brace_depth -= 1
            offset += 1
            continue
        }
        if source[offset] == '\\' && brace_depth == 0 {
            control := tex_display_scan_control(
                source, offset, kind, &environment_depth, &result)
            if control.action == .Invalid {return {result, offset, false}}
            if control.action == .Row_End {return {result, control.next, true}}
            if control.action == .Continue {offset = control.next; continue}
        }
        if source[offset] == '&' && brace_depth == 0 && environment_depth == 0 {
            if kind != .Align || result.alignment >= 0 {
                return {result, offset, false}
            }
            result.alignment = offset
        }
        offset += tex_utf8_sequence_width(source, offset)
    }
    return {result, body_end, brace_depth == 0 && environment_depth == 0}
}

// Return a trimmed row segment, excluding a trailing numbering suppression command.
tex_display_row_segment :: proc(
    source: string,
    row: Tex_Document_Display_Row_Source,
    start, end: int) -> (string, bool) {

    segment_end := end
    if row.notag >= start && row.notag < end {
        segment_end = row.notag
        if len(tex_document_trim(source[row.notag+len("\\notag"):end])) != 0 {
            return "", false
        }
    }
    text := tex_document_trim(source[start:segment_end])
    return text, len(text) > 0
}

// Parse and append one existing native math program for a display row segment.
tex_display_parse_program :: proc(
    parser: ^Tex_Document_Parser,
    source: string) -> (int, Tex_Parse_Status) {

    return tex_parse_math_fragment(source, .Display, parser.output, parser.limits)
}

// Append one display math inline retaining the segment's source and copy geometry.
tex_display_append_inline :: proc(
    parser: ^Tex_Document_Parser,
    block_index, source_start, source_end, program: int,
    text: string,
    color: Tex_Document_Color) -> Tex_Parse_Status {

    span, ok := tex_semantic_append_text(parser.output, text)
    if !ok {return .Work_Limit}
    if !tex_semantic_append_document_inline(parser.output, block_index, {
        kind = .Math, source = {source_start, source_end-source_start},
        text = span, color = color, root_style = .Display,
        math_program = program,
    }) {return .Work_Limit}
    return .Ok
}

// Parse, publish, and retain one bounded row in a technical display block.
tex_display_commit_row :: proc(
    parser: ^Tex_Document_Parser,
    block_index: int,
    row: Tex_Document_Display_Row_Source,
    kind: Tex_Document_Display_Kind,
    color: Tex_Document_Color) -> Tex_Parse_Status {

    if kind == .Align && row.alignment < 0 {return .Unexpected_Token}
    split := row.alignment if row.alignment >= 0 else row.end
    primary_text, primary_ok := tex_display_row_segment(
        parser.source, row, row.start, split)
    if !primary_ok {return .Unexpected_Token}
    primary, status := tex_display_parse_program(parser, primary_text)
    if status != .Ok {return status}
    secondary := -1
    secondary_text := ""
    if row.alignment >= 0 {
        secondary_ok: bool
        secondary_text, secondary_ok = tex_display_row_segment(
            parser.source, row, row.alignment+1, row.end)
        if !secondary_ok {return .Unexpected_Token}
        secondary, status = tex_display_parse_program(parser, secondary_text)
        if status != .Ok {return status}
    }
    status = tex_display_append_inline(
        parser, block_index, row.start, split, primary, primary_text, color)
    if status != .Ok {return status}
    if row.alignment >= 0 {
        status = tex_display_append_inline(parser, block_index,
            row.alignment+1, row.end, secondary, secondary_text, color)
        if status != .Ok {return status}
    }
    row_index := tex_semantic_append_document_display_row(parser.output, {
        source = {row.start, row.end-row.start},
        primary_program = primary, secondary_program = secondary,
        alignment = .Center, suppress_number = row.notag >= 0,
    })
    return .Ok if row_index >= 0 else .Work_Limit
}

// Parse all rows in one top-level technical display environment.
tex_document_parse_display_environment :: proc(
    parser: ^Tex_Document_Parser,
    info: Tex_Document_Display_Info,
    color: Tex_Document_Color) -> Tex_Parse_Status {

    source_start := parser.offset
    body_start := source_start+len(info.opener)
    body_end := tex_document_find(parser.source, info.closer, body_start)
    if body_end < 0 {return .Unexpected_Token}
    tex_document_close_paragraph(parser)
    row_start := parser.output.document_display_row_count
    block_index := tex_semantic_append_document_block(parser.output, {
        kind = .Display, inline_start = parser.output.document_inline_count,
        source = {source_start, body_end+len(info.closer)-source_start},
        format = {alignment = .Center}, display_kind = info.kind,
        display_row_start = row_start, display_numbered = info.numbered,
    })
    if block_index < 0 {return .Work_Limit}
    next := body_start
    for next < body_end {
        scanned := tex_display_scan_row(parser.source, next, body_end, info.kind)
        if !scanned.ok {return .Unexpected_Token}
        status := tex_display_commit_row(
            parser, block_index, scanned.row, info.kind, color)
        if status != .Ok {return status}
        next = scanned.next
    }
    block := &parser.output.document_blocks[block_index]
    block.display_row_count = parser.output.document_display_row_count-row_start
    block.source = {source_start, body_end+len(info.closer)-source_start}
    if block.display_row_count == 0 || info.kind == .Equation && block.display_row_count != 1 {
        return .Unexpected_Token
    }
    if info.kind == .Multline {
        rows := parser.output.document_display_rows[
            row_start:row_start+block.display_row_count]
        rows[0].alignment = .Left
        rows[len(rows)-1].alignment = .Right
        if len(rows) == 1 {rows[0].alignment = .Center}
    }
    parser.offset = body_end+len(info.closer)
    return .Ok
}
