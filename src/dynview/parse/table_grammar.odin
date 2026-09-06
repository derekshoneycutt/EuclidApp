package dynview_parse

TEX_TABLE_DIMENSION_LIMIT :: 16
TEX_TABLE_CELL_LIMIT :: TEX_TABLE_DIMENSION_LIMIT * TEX_TABLE_DIMENSION_LIMIT

// Identify one table-cell terminator consumed by the row parser.
Tex_Table_Boundary :: enum {
    Alignment,
    Row,
    End,
    Invalid,
}

// Retain bounded table construction state before semantic publication.
Tex_Table_Parse_State :: struct {
    cells: [TEX_TABLE_CELL_LIMIT]int,
    cell_count: int,
    rows: int,
    columns: int,
    current_columns: int,
    descriptor: Tex_Table_Descriptor,
}

// Group parsed matrix fields passed together during semantic publication.
Tex_Table_Publication :: struct {
    text: Tex_Text_Span,
    preamble: Tex_Text_Span,
    cells_program: int,
    rows: int,
    columns: int,
    descriptor: int,
}

//   Parse one supported matrix-like environment or preserve `\begin` fallback.
tex_math_parse_table :: proc(
    parser: ^Tex_Math_Parser,
    program_id: int) -> (int, Tex_Parse_Status) {
    environment_span, environment_ok := tex_math_take_raw_group(parser)
    environment := tex_semantic_text(parser.output, environment_span)
    if !environment_ok || !tex_table_environment_supported(environment) {
        return tex_table_append_fallback(parser, program_id)
    }
    preamble: Tex_Text_Span
    if environment == "array" || environment == "alignedat" ||
        environment == "subarray" {
        preamble, environment_ok = tex_math_take_raw_group(parser)
    }
    state := Tex_Table_Parse_State{}
    state.descriptor.cell_style = .Text
    state.descriptor.row_spacing = .Matrix
    if !environment_ok || !tex_table_parse_rows(parser, environment, &state) {
        tex_table_discard_through_end(parser, environment)
        return tex_table_append_fallback(parser, program_id)
    }
    state.descriptor.rows = state.rows
    state.descriptor.columns = state.columns
    if environment == "array" &&
        !tex_table_parse_preamble(parser.output, preamble, &state.descriptor) {
        return tex_table_append_fallback(parser, program_id)
    }
    if environment != "array" &&
        !tex_table_apply_environment_preset(
            parser.output, environment, preamble, &state.descriptor) {
        return tex_table_append_fallback(parser, program_id)
    }
    return tex_table_publish(parser, program_id, environment, preamble, &state)
}

//   Publish the frozen recoverable fallback for an invalid table environment.
tex_table_append_fallback :: proc(
    parser: ^Tex_Math_Parser,
    program_id: int) -> (int, Tex_Parse_Status) {
    parser.output.recoverable = true
    return tex_math_append_glyph(parser, program_id, "\\begin", {
        role = .Math,
        atom_class = .Ord,
    }), .Ok
}

//   Drain a malformed environment through its matching end marker.
tex_table_discard_through_end :: proc(
    parser: ^Tex_Math_Parser,
    environment: string) {
    for {
        token, status := tex_math_take(parser)
        if status != .Ok {
            return
        }
        if token.kind != .Command ||
            tex_token_text(parser.cursor.source, token) != "\\end" {
            continue
        }
        span, ok := tex_math_take_raw_group(parser)
        if ok && tex_semantic_text(parser.output, span) == environment {
            return
        }
    }
}

//   Return whether one environment belongs to the frozen matrix surface.
tex_table_environment_supported :: proc(environment: string) -> bool {
    return environment == "matrix" || environment == "bmatrix" ||
        environment == "Bmatrix" || environment == "pmatrix" ||
        environment == "vmatrix" || environment == "Vmatrix" ||
        environment == "array" || environment == "smallmatrix" ||
        environment == "cases" || environment == "dcases" ||
        environment == "aligned" || environment == "alignedat" ||
        environment == "gathered" || environment == "subarray"
}

//   Parse rows and cells through a matching environment terminator.
tex_table_parse_rows :: proc(
    parser: ^Tex_Math_Parser,
    environment: string,
    state: ^Tex_Table_Parse_State) -> bool {
    for {
        if !tex_table_consume_prefix_controls(parser, state) {
            return false
        }
        if tex_table_at_end(parser) {
            return state.rows > 0 && tex_table_consume_end(parser, environment)
        }
        cell := tex_semantic_begin_program(parser.output)
        boundary := tex_table_parse_cell(parser, cell)
        if !tex_table_commit_cell(parser, state, cell, boundary) {
            return false
        }
        if boundary == .Row || boundary == .End {
            if !tex_table_finish_row(state) {
                return false
            }
        }
        if boundary == .Row {
            tex_table_parse_optional_gap(parser, state)
        } else if boundary == .End {
            return tex_table_consume_end(parser, environment)
        }
    }
}

//   Commit one parsed cell while enforcing bounded dimensions and storage.
tex_table_commit_cell :: proc(
    parser: ^Tex_Math_Parser,
    state: ^Tex_Table_Parse_State,
    cell: int,
    boundary: Tex_Table_Boundary) -> bool {
    if state.cell_count >= len(state.cells) {
        tex_semantic_fail(parser.output, .Work_Limit, parser.cursor.offset)
        return false
    }
    if boundary == .Invalid {
        return false
    }
    state.cells[state.cell_count] = cell
    state.cell_count += 1
    state.current_columns += 1
    if boundary == .Alignment &&
        state.current_columns >= TEX_TABLE_DIMENSION_LIMIT {
        tex_semantic_fail(parser.output, .Work_Limit, parser.cursor.offset)
        return false
    }
    return true
}

//   Consume leading hline controls and count them at the current row boundary.
tex_table_consume_prefix_controls :: proc(
    parser: ^Tex_Math_Parser,
    state: ^Tex_Table_Parse_State) -> bool {
    for {
        token, status := tex_math_peek(parser)
        if status != .Ok {
            return false
        }
        if token.kind != .Command ||
            tex_token_text(parser.cursor.source, token) != "\\hline" {
            return true
        }
        _, _ = tex_math_take(parser)
        if state.rows > TEX_TABLE_DIMENSION_LIMIT ||
            state.descriptor.horizontal_rule_counts[state.rows] == max(u8) {
            return false
        }
        state.descriptor.horizontal_rule_counts[state.rows] += 1
    }
}

//   Parse one cell program until alignment, row, or environment termination.
tex_table_parse_cell :: proc(
    parser: ^Tex_Math_Parser,
    program_id: int) -> Tex_Table_Boundary {
    for {
        token, status := tex_math_peek(parser)
        if status != .Ok {
            return .Invalid
        }
        if token.kind == .Alignment {
            _, _ = tex_math_take(parser)
            return .Alignment
        }
        if token.kind == .Command {
            command := tex_token_text(parser.cursor.source, token)
            if command == "\\\\" {
                _, _ = tex_math_take(parser)
                return .Row
            }
            if command == "\\end" {
                return .End
            }
        }
        if tex_math_parse_atom(parser, program_id) != .Ok {
            return .Invalid
        }
    }
}

//   Validate one completed row against the first row width.
tex_table_finish_row :: proc(state: ^Tex_Table_Parse_State) -> bool {
    if state.current_columns <= 0 {
        return false
    }
    if state.current_columns > TEX_TABLE_DIMENSION_LIMIT ||
        state.rows >= TEX_TABLE_DIMENSION_LIMIT {
        return false
    }
    if state.columns == 0 {
        state.columns = state.current_columns
    } else if state.columns != state.current_columns {
        return false
    }
    state.rows += 1
    state.current_columns = 0
    return true
}

//   Return whether the current lookahead starts an environment terminator.
tex_table_at_end :: proc(parser: ^Tex_Math_Parser) -> bool {
    token, status := tex_math_peek(parser)
    return status == .Ok && token.kind == .Command &&
        tex_token_text(parser.cursor.source, token) == "\\end"
}

//   Consume and validate one matching `\end{environment}` sequence.
tex_table_consume_end :: proc(
    parser: ^Tex_Math_Parser,
    environment: string) -> bool {
    _, status := tex_math_take(parser)
    if status != .Ok {
        return false
    }
    span, ok := tex_math_take_raw_group(parser)
    return ok && tex_semantic_text(parser.output, span) == environment
}

//   Consume one optional signed row gap after a row separator.
tex_table_parse_optional_gap :: proc(
    parser: ^Tex_Math_Parser,
    state: ^Tex_Table_Parse_State) {
    token, status := tex_math_peek(parser)
    if status != .Ok || token.kind != .Left_Bracket || state.rows <= 0 {
        return
    }
    _, _ = tex_math_take(parser)
    span, ok := tex_math_take_raw_until(parser, .Right_Bracket)
    if ok {
        state.descriptor.row_extra_gaps[state.rows - 1], _ =
            tex_table_parse_length(tex_semantic_text(parser.output, span))
    }
}

//   Parse a brace-delimited raw token sequence into semantic text storage.
tex_math_take_raw_group :: proc(
    parser: ^Tex_Math_Parser) -> (Tex_Text_Span, bool) {
    token, status := tex_math_take(parser)
    if status != .Ok || token.kind != .Left_Brace {
        return {}, false
    }
    start := parser.output.text_count
    depth := 1
    for depth > 0 {
        token, status = tex_math_take(parser)
        if status != .Ok { return {}, false }
        if token.kind == .Left_Brace {
            depth += 1
        } else if token.kind == .Right_Brace {
            depth -= 1
            if depth == 0 { break }
        }
        if _, ok := tex_semantic_append_text(
            parser.output, tex_token_text(parser.cursor.source, token)); !ok {
            return {}, false
        }
    }
    return {offset = start, length = parser.output.text_count-start}, true
}

//   Copy token bytes until one required punctuation token.
tex_math_take_raw_until :: proc(
    parser: ^Tex_Math_Parser,
    closing: Tex_Token_Kind) -> (Tex_Text_Span, bool) {
    start := parser.output.text_count
    for {
        token, status := tex_math_take(parser)
        if status != .Ok {
            return {}, false
        }
        if token.kind == closing {
            return {offset = start, length = parser.output.text_count-start}, true
        }
        text := tex_token_text(parser.cursor.source, token)
        if _, ok := tex_semantic_append_text(parser.output, text); !ok {
            return {}, false
        }
    }
}

//   Parse one decimal em/pt length without dynamic conversion.
tex_table_parse_length :: proc(text: string) -> (Tex_Table_Length, bool) {
    unit := Tex_Table_Length_Unit.Default
    number_end := len(text)
    if len(text) >= 2 && text[len(text)-2:] == "em" {
        unit, number_end = .Em, len(text)-2
    } else if len(text) >= 2 && text[len(text)-2:] == "pt" {
        unit, number_end = .Pt, len(text)-2
    } else {
        return {}, false
    }
    value, ok := tex_table_parse_decimal(text[:number_end])
    return {value = value, unit = unit}, ok
}

//   Parse one bounded signed decimal used by table row gaps.
tex_table_parse_decimal :: proc(text: string) -> (f32, bool) {
    if len(text) == 0 {
        return 0, false
    }
    sign: f32 = 1
    offset := 0
    if text[0] == '-' {
        sign, offset = -1, 1
    }
    value: f32
    scale: f32
    seen_digit := false
    after_point := false
    for index in offset..<len(text) {
        if text[index] == '.' && !after_point {
            after_point, scale = true, 0.1
            continue
        }
        if text[index] < '0' || text[index] > '9' {
            return 0, false
        }
        digit := f32(text[index]-'0')
        value = value*10 + digit if !after_point else value + digit*scale
        scale *= 0.1 if after_point else 1
        seen_digit = true
    }
    return sign*value, seen_digit
}

//   Parse array alignment and vertical-rule semantics from one preamble.
tex_table_parse_preamble :: proc(
    output: ^Tex_Semantic_Output,
    span: Tex_Text_Span,
    descriptor: ^Tex_Table_Descriptor) -> bool {
    text := tex_semantic_text(output, span)
    column, boundary, offset := 0, 0, 0
    for offset < len(text) {
        value := text[offset]
        if tex_math_ascii_space(value) {
            offset += 1
            continue
        }
        if offset+3 <= len(text) && text[offset:offset+3] == "@{}" {
            descriptor.boundary_gaps[boundary].unit = .Zero
            offset += 3
            continue
        }
        if value == '|' {
            if descriptor.vertical_rule_counts[boundary] == max(u8) {
                return false
            }
            descriptor.vertical_rule_counts[boundary] += 1
            offset += 1
            continue
        }
        if value != 'l' && value != 'c' && value != 'r' || column >= 16 {
            return false
        }
        descriptor.alignments[column] =
            .Left if value == 'l' else (.Center if value == 'c' else .Right)
        column += 1
        boundary = column
        offset += 1
    }
    descriptor.present = column > 0
    return column == descriptor.columns
}

//   Apply one historical table preset and validate its column contract.
tex_table_apply_environment_preset :: proc(
    output: ^Tex_Semantic_Output,
    environment: string,
    argument: Tex_Text_Span,
    descriptor: ^Tex_Table_Descriptor) -> bool {
    columns := descriptor.columns
    argument_text := tex_semantic_text(output, argument)
    if environment == "cases" || environment == "dcases" {
        if columns != 2 { return false }
        tex_table_apply_cases_preset(descriptor, environment == "dcases")
    } else if environment == "aligned" || environment == "alignedat" {
        if columns < 2 || columns%2 != 0 { return false }
        if environment == "alignedat" &&
            !tex_table_alignedat_columns_match(argument_text, columns) {
            return false
        }
        tex_table_apply_aligned_preset(descriptor, environment == "aligned")
    } else if environment == "gathered" {
        if columns != 1 { return false }
        descriptor.cell_style, descriptor.row_spacing = .Display, .Alignment
    } else if environment == "smallmatrix" {
        descriptor.cell_style, descriptor.row_spacing = .Script, .Tight
    } else if environment == "subarray" {
        if columns != 1 || argument_text != "l" && argument_text != "c" {
            return false
        }
        descriptor.cell_style, descriptor.row_spacing = .Script, .Tight
        descriptor.alignments[0] =
            .Left if argument_text == "l" else .Center
    }
    descriptor.present = true
    return true
}

//   Apply left-aligned cases spacing and optional display-style cells.
tex_table_apply_cases_preset :: proc(
    descriptor: ^Tex_Table_Descriptor,
    display: bool) {
    descriptor.cell_style = .Display if display else .Text
    descriptor.row_spacing = .Cases
    for column in 0..<descriptor.columns { descriptor.alignments[column] = .Left }
    for boundary in 0..=descriptor.columns {
        descriptor.boundary_gaps[boundary].unit = .Zero
    }
    descriptor.boundary_gaps[1] = {value = 1, unit = .Em}
}

//   Apply alternating right/left alignment and pair spacing.
tex_table_apply_aligned_preset :: proc(
    descriptor: ^Tex_Table_Descriptor,
    spaced_pairs: bool) {
    descriptor.cell_style, descriptor.row_spacing = .Display, .Alignment
    for column in 0..<descriptor.columns {
        descriptor.alignments[column] = .Right if column%2 == 0 else .Left
    }
    for boundary in 0..=descriptor.columns {
        descriptor.boundary_gaps[boundary].unit = .Zero
        if spaced_pairs && boundary >= 2 && boundary%2 == 0 &&
            boundary < descriptor.columns {
            descriptor.boundary_gaps[boundary] = {value = 1, unit = .Em}
        }
    }
}

//   Validate alignedat's bounded pair-count argument against parsed columns.
tex_table_alignedat_columns_match :: proc(argument: string, columns: int) -> bool {
    pairs, ok := tex_table_parse_positive_integer(argument)
    return ok && pairs <= 8 && columns == pairs*2
}

//   Parse one bounded positive decimal integer.
tex_table_parse_positive_integer :: proc(text: string) -> (int, bool) {
    if len(text) == 0 { return 0, false }
    value := 0
    for byte in transmute([]u8)text {
        if byte < '0' || byte > '9' { return 0, false }
        value = value*10 + int(byte-'0')
    }
    return value, value > 0
}

//   Publish cell wrappers, matrix semantics, and any delimiter wrapper atomically.
tex_table_publish :: proc(
    parser: ^Tex_Math_Parser,
    program_id: int,
    environment: string,
    preamble: Tex_Text_Span,
    state: ^Tex_Table_Parse_State) -> (int, Tex_Parse_Status) {
    cells_program := tex_semantic_begin_program(parser.output)
    for index in 0..<state.cell_count {
        tex_table_append_cell(parser.output, cells_program, state.cells[index])
    }
    text := tex_table_canonical_text(parser.output, environment, preamble, state)
    descriptor_index := tex_table_publish_descriptor(parser.output, &state.descriptor)
    matrix_program := program_id
    if tex_table_environment_wrapped(environment) {
        matrix_program = tex_semantic_begin_program(parser.output)
    }
    matrix_index := tex_table_append_matrix(parser.output, matrix_program, {
        text = text,
        preamble = preamble,
        cells_program = cells_program,
        rows = state.rows,
        columns = state.columns,
        descriptor = descriptor_index,
    })
    if matrix_program == program_id {
        return matrix_index, .Ok
    }
    return tex_table_append_wrapper(
        parser.output, program_id, environment, matrix_program)
}

//   Return whether one environment adds delimiters around its table program.
tex_table_environment_wrapped :: proc(environment: string) -> bool {
    return environment == "bmatrix" || environment == "Bmatrix" ||
        environment == "pmatrix" || environment == "vmatrix" ||
        environment == "Vmatrix" || environment == "cases" ||
        environment == "dcases"
}

//   Append one cell as a single operation, wrapping multi-operation cells.
tex_table_append_cell :: proc(
    output: ^Tex_Semantic_Output,
    destination, cell: int) {
    program := &output.programs[cell]
    if program.op_count == 1 {
        op := output.ops[program.first_op]
        op.next_op = -1
        _ = tex_semantic_append_op(output, destination, op)
        return
    }
    text := tex_math_program_plain_span(output, cell)
    _ = tex_semantic_append_op(output, destination, {
        kind = .Script,
        text = text,
        style_role = .Math,
        atom_class = .Inner,
        child_program = cell,
        secondary_program = -1,
        tertiary_program = -1,
        table_descriptor = -1,
    })
}

//   Publish one present array descriptor or return the absent sentinel.
tex_table_publish_descriptor :: proc(
    output: ^Tex_Semantic_Output,
    descriptor: ^Tex_Table_Descriptor) -> int {
    if !descriptor.present {
        return -1
    }
    if output.table_descriptor_count >= len(output.table_descriptors) {
        tex_semantic_fail(output, .Work_Limit, 0)
        return -1
    }
    index := output.table_descriptor_count
    output.table_descriptors[index] = descriptor^
    output.table_descriptor_count += 1
    return index
}

//   Append one recursive matrix operation with decimal dimensions.
tex_table_append_matrix :: proc(
    output: ^Tex_Semantic_Output,
    program_id: int,
    publication: Tex_Table_Publication) -> int {
    row_text := tex_table_small_integer_text(output, publication.rows)
    column_text := tex_table_small_integer_text(output, publication.columns)
    return tex_semantic_append_op(output, program_id, {
        kind = .Matrix,
        text = publication.text,
        radical_index_text = row_text,
        superscript_text = column_text,
        subscript_text = publication.preamble,
        style_role = .Math,
        atom_class = .Inner,
        child_program = publication.cells_program,
        secondary_program = -1,
        tertiary_program = -1,
        table_descriptor = publication.descriptor,
    })
}

//   Append one bounded positive table dimension as decimal text.
tex_table_small_integer_text :: proc(
    output: ^Tex_Semantic_Output,
    value: int) -> Tex_Text_Span {
    bytes: [2]u8
    count := 1
    bytes[0] = u8(value%10) + '0'
    if value >= 10 {
        bytes[1] = bytes[0]
        bytes[0] = u8(value/10) + '0'
        count = 2
    }
    span, _ := tex_semantic_append_text(output, string(bytes[:count]))
    return span
}

//   Build canonical matrix or array source from parsed cell programs.
tex_table_canonical_text :: proc(
    output: ^Tex_Semantic_Output,
    environment: string,
    preamble: Tex_Text_Span,
    state: ^Tex_Table_Parse_State) -> Tex_Text_Span {
    canonical_environment := "matrix" if
        tex_table_environment_wrapped(environment) else environment
    start := output.text_count
    parts := [?]string{"\\begin{", canonical_environment, "}"}
    for part in parts {
        _, _ = tex_semantic_append_text(output, part)
    }
    if environment == "array" || environment == "alignedat" ||
        environment == "subarray" {
        _, _ = tex_semantic_append_text(output, "{")
        _, _ = tex_semantic_append_text(output, tex_semantic_text(output, preamble))
        _, _ = tex_semantic_append_text(output, "}")
    }
    for index in 0..<state.cell_count {
        if index > 0 {
            separator := "\\\\" if index%state.columns == 0 else "&"
            _, _ = tex_semantic_append_text(output, separator)
        }
        _ = tex_math_append_program_plain(output, state.cells[index])
    }
    _, _ = tex_semantic_append_text(output, "\\end{")
    _, _ = tex_semantic_append_text(output, canonical_environment)
    _, _ = tex_semantic_append_text(output, "}")
    return {offset = start, length = output.text_count-start}
}

//   Wrap matrix variants in their frozen stretch-delimiter semantics.
tex_table_append_wrapper :: proc(
    output: ^Tex_Semantic_Output,
    program_id: int,
    environment: string,
    matrix_program: int) -> (int, Tex_Parse_Status) {
    left, right := "[", "]"
    if environment == "Bmatrix" {
        left, right = "\\{", "\\}"
    } else if environment == "pmatrix" {
        left, right = "(", ")"
    } else if environment == "vmatrix" {
        left, right = "|", "|"
    } else if environment == "Vmatrix" {
        left, right = "\\|", "\\|"
    } else if environment == "cases" || environment == "dcases" {
        left, right = "\\{", "."
    }
    text := tex_math_stretch_text(output, left, matrix_program, right)
    left_span, _ := tex_semantic_append_text(output, left)
    right_span, _ := tex_semantic_append_text(output, right)
    index := tex_semantic_append_op(output, program_id, {
        kind = .Stretch_Delimiter,
        text = text,
        radical_index_text = left_span,
        superscript_text = right_span,
        left_delimiter = tex_math_delimiter_kind(left),
        right_delimiter = tex_math_delimiter_kind(right),
        style_role = .Math,
        atom_class = .Inner,
        child_program = matrix_program,
        secondary_program = -1,
        tertiary_program = -1,
        table_descriptor = -1,
    })
    return index, .Ok
}