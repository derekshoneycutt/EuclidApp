package dynview_layout

import app_core "../../core"

// Resolve the first-line indent supported by one semantic paragraph format.
document_block_first_line_indent :: #force_inline proc(
    block: app_core.Dynview_Document_Block,
    font_size: f32) -> f32 {

    if block.kind != .Paragraph || block.no_indent || block.alignment != .Left {
        return 0
    }
    return max(0, font_size)
}

// Resolve one semantic line's horizontal origin within the document content width.
document_line_horizontal_offset :: #force_inline proc(
    block: app_core.Dynview_Document_Block,
    line_width, available_width: f32) -> f32 {

    remaining := max(0, available_width-line_width)
    if block.kind == .Display || block.alignment == .Center {
        return remaining*0.5
    }
    if block.alignment == .Right {
        return remaining
    }
    return 0
}

// Place paragraph alignment and dedicated display centering without changing widths.
document_place_block_horizontally :: proc(
    block: app_core.Dynview_Document_Block,
    lines: []app_core.Dynview_Document_Layout_Line,
    display_rows: []app_core.Dynview_Document_Display_Row,
    available_width: f32,
    first_line_indent: f32) {

    for &line, line_index in lines {
        line_width := available_width
        if line.display_content_width > 0 {
            line_width = line.display_content_width
        }
        alignment_block := block
        if block.display_kind == .Multline && line.display_row_index >= 0 &&
            line.display_row_index < len(display_rows) {
            alignment_block.kind = .Paragraph
            alignment_block.alignment = display_rows[line.display_row_index].alignment
        }
        line.x = document_line_horizontal_offset(
            alignment_block, line.width, line_width)
        if line_index == 0 {
            line.x += first_line_indent
        }
    }
}