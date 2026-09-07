package dynview_parse

//   Reset bounded semantic output and reserve its root program.
tex_semantic_output_init :: proc(output: ^Tex_Semantic_Output) -> bool {
    if output == nil {
        return false
    }
    output^ = {}
    output.root_program = tex_semantic_begin_program(output)
    return output.root_program >= 0
}

//   Reserve one empty program or mark semantic capacity exhaustion.
tex_semantic_begin_program :: proc(output: ^Tex_Semantic_Output) -> int {
    if output == nil || output.program_count >= len(output.programs) {
        tex_semantic_fail(output, .Work_Limit, 0)
        return -1
    }
    index := output.program_count
    output.programs[index] = {first_op = -1, last_op = -1}
    output.program_count += 1
    return index
}

//   Append immutable bytes to semantic storage and return their checked span.
tex_semantic_append_text :: proc(
    output: ^Tex_Semantic_Output,
    text: string) -> (Tex_Text_Span, bool) {
    if output == nil || len(text) > len(output.text)-output.text_count {
        tex_semantic_fail(output, .Work_Limit, 0)
        return {}, false
    }
    span := Tex_Text_Span{offset = output.text_count, length = len(text)}
    copy(output.text[span.offset:span.offset + span.length], transmute([]u8)text)
    output.text_count += span.length
    return span, true
}

//   Append one operation to a program while retaining stable pool indices.
tex_semantic_append_op :: proc(
    output: ^Tex_Semantic_Output,
    program_id: int,
    op: Tex_Math_Op) -> int {
    if output == nil || program_id < 0 || program_id >= output.program_count ||
        output.op_count >= len(output.ops) {
        tex_semantic_fail(output, .Work_Limit, 0)
        return -1
    }
    index := output.op_count
    output.ops[index] = op
    output.ops[index].next_op = -1
    program := &output.programs[program_id]
    if program.last_op >= 0 {
        output.ops[program.last_op].next_op = index
    } else {
        program.first_op = index
    }
    program.last_op = index
    program.op_count += 1
    output.op_count += 1
    return index
}

//   Append one bounded semantic document block.
tex_semantic_append_document_block :: proc(
    output: ^Tex_Semantic_Output,
    block: Tex_Document_Block) -> int {
    if output == nil ||
        output.document_block_count >= len(output.document_blocks) {
        tex_semantic_fail(output, .Work_Limit, block.source.offset)
        return -1
    }
    index := output.document_block_count
    output.document_blocks[index] = block
    output.document_block_count += 1
    return index
}

//   Append one bounded inline and extend its owning block.
tex_semantic_append_document_inline :: proc(
    output: ^Tex_Semantic_Output,
    block_index: int,
    item: Tex_Document_Inline) -> bool {
    if output == nil || block_index < 0 ||
        block_index >= output.document_block_count ||
        output.document_inline_count >= len(output.document_inlines) {
        tex_semantic_fail(output, .Work_Limit, item.source.offset)
        return false
    }
    block := &output.document_blocks[block_index]
    if block.inline_start + block.inline_count != output.document_inline_count {
        tex_semantic_fail(output, .Unexpected_Token, item.source.offset)
        return false
    }
    output.document_inlines[output.document_inline_count] = item
    output.document_inline_count += 1
    block.inline_count += 1
    block.source.length = item.source.offset + item.source.length -
        block.source.offset
    return true
}

// Append one bounded technical-display row and return its stable semantic index.
tex_semantic_append_document_display_row :: proc(
    output: ^Tex_Semantic_Output,
    row: Tex_Document_Display_Row) -> int {

    if output == nil ||
        output.document_display_row_count >= len(output.document_display_rows) {
        tex_semantic_fail(output, .Work_Limit, row.source.offset)
        return -1
    }
    index := output.document_display_row_count
    output.document_display_rows[index] = row
    output.document_display_row_count += 1
    return index
}

//   Append two semantic spans as one newly owned span.
tex_semantic_join_text :: proc(
    output: ^Tex_Semantic_Output,
    left, right: Tex_Text_Span) -> (Tex_Text_Span, bool) {
    left_text := tex_semantic_text(output, left)
    right_text := tex_semantic_text(output, right)
    total := len(left_text) + len(right_text)
    if total > len(output.text)-output.text_count {
        tex_semantic_fail(output, .Work_Limit, 0)
        return {}, false
    }
    span := Tex_Text_Span{offset = output.text_count, length = total}
    copy(output.text[span.offset:], transmute([]u8)left_text)
    copy(output.text[span.offset + len(left_text):], transmute([]u8)right_text)
    output.text_count += total
    return span, true
}

//   Preserve the first terminal semantic construction failure.
tex_semantic_fail :: proc(
    output: ^Tex_Semantic_Output,
    status: Tex_Parse_Status,
    offset: int) {
    if output != nil && output.status == .Ok {
        output.status = status
        output.error_offset = offset
    }
}