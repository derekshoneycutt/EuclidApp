package dynview_layout

import app_core "../../core"
import "../../grid"

// Font-relative spacing inputs for pixel-native document vertical placement.
Document_Vertical_Style :: struct {
    baseline_skip: f32,
    line_skip_limit: f32,
    line_skip: f32,
    paragraph_spacing: f32,
    display_spacing: f32,
}

Document_Vertical_Context :: struct {
    runtime: ^app_core.Dynview_System,
    builders: ^Document_Layout_Builders,
    style: Document_Vertical_Style,
    available_width: f32,
}

Document_Block_Placement_Result :: struct {
    next_row: int,
    status: app_core.Bounded_Builder_Status,
}

// Derive stable paragraph leading from the active semantic prose size.
document_vertical_style :: proc(font_size: f32) -> (Document_Vertical_Style, bool) {
    if font_size <= 0 {
        return {}, false
    }
    return {
        baseline_skip = font_size*1.2,
        line_skip_limit = 0,
        line_skip = max(1, font_size*0.1),
        paragraph_spacing = font_size*0.5,
        display_spacing = font_size*0.75,
    }, true
}

// Resolve TeX-inspired glue between adjacent measured line ink extents.
document_interline_glue :: #force_inline proc(
    previous_depth, next_ascent: f32,
    style: Document_Vertical_Style) -> f32 {

    candidate := style.baseline_skip-previous_depth-next_ascent
    return style.line_skip if candidate < style.line_skip_limit else candidate
}

// Place one block's lines from an exact pixel top without row quantization.
document_place_block_lines :: proc(
    lines: []app_core.Dynview_Document_Layout_Line,
    block_top: f32,
    style: Document_Vertical_Style) -> (f32, bool) {

    if len(lines) == 0 || block_top < 0 {
        return 0, false
    }
    previous_depth: f32
    previous_baseline: f32
    for &line, index in lines {
        if line.ascent < 0 || line.descent < 0 {
            return 0, false
        }
        if index == 0 {
            line.baseline = block_top+line.ascent
        } else {
            glue := document_interline_glue(previous_depth, line.ascent, style)
            line.baseline = previous_baseline+previous_depth+glue+line.ascent
        }
        line.top = line.baseline-line.ascent
        line.bottom = line.baseline+line.descent
        previous_depth = line.descent
        previous_baseline = line.baseline
    }
    return lines[len(lines)-1].bottom, true
}

// Resolve collapsed vertical glue before one block from adjacent block kinds.
document_block_spacing_before :: proc(
    documents: []app_core.Dynview_Document,
    blocks: []app_core.Dynview_Document_Block,
    block_index: int,
    style: Document_Vertical_Style) -> (f32, bool) {

    if block_index < 0 || block_index >= len(blocks) {
        return 0, false
    }
    if block_index == 0 {
        return 0, true
    }
    for document in documents {
        if document.block_start == block_index {
            return 0, true
        }
    }
    previous := blocks[block_index-1].kind
    current := blocks[block_index].kind
    if previous == .Display || current == .Display {
        return style.display_spacing, true
    }
    return style.paragraph_spacing, true
}

// Resolve a stable visual center from non-shape content on one line.
document_line_shape_center :: proc(
    builders: ^Document_Layout_Builders,
    line: app_core.Dynview_Document_Layout_Line) -> (f32, bool) {

    ascent, descent: f32
    found := false
    for item_index in line.item_start..<line.item_start+line.item_count {
        if item_index < 0 || item_index >= builders^.items.count {return 0, false}
        item := builders^.items.storage[item_index]
        if item.box_kind == .Shape {continue}
        ascent = max(ascent, item.ascent)
        descent = max(descent, item.descent)
        found = true
    }
    if found {return line.baseline+(descent-ascent)*0.5, true}
    return (line.top+line.bottom)*0.5, true
}

// Apply one line's final document-space origin to items and copy targets.
document_place_line_contents :: proc(
    builders: ^Document_Layout_Builders,
    line_index: int,
    line: app_core.Dynview_Document_Layout_Line) -> bool {

    shape_center, center_ok := document_line_shape_center(builders, line)
    if !center_ok {return false}
    for item_index in line.item_start..<line.item_start+line.item_count {
        if item_index < 0 || item_index >= builders^.items.count {
            return false
        }
        item := &builders^.items.storage[item_index]
        item^.x += line.x
        item^.baseline = line.baseline
        if item^.box_kind == .Shape {
            item^.top = shape_center-(item^.ascent+item^.descent)*0.5
        } else {
            item^.top = line.baseline-item^.ascent
        }
    }
    for &target in builders^.copy_targets.storage[:builders^.copy_targets.count] {
        if target.line_index != line_index {
            continue
        }
        if target.item_index < 0 || target.item_index >= builders^.items.count {
            return false
        }
        item := builders^.items.storage[target.item_index]
        target.x += line.x
        target.y = item.top
        target.height = item.ascent+item.descent
    }
    return true
}

// Publish one completed block's exact and outward-rounded vertical extents.
document_publish_block_reservation :: proc(
    block: ^app_core.Dynview_Document_Layout_Block,
    spacing: f32,
    reservation: grid.Vertical_Reservation) {

    block^.height = block^.bottom-block^.top
    block^.spacing_before = spacing
    block^.reserved_top = reservation.top
    block^.reserved_bottom = reservation.bottom
    block^.trailing_padding = reservation.trailing_padding
    block^.row_start = reservation.row_start
    block^.row_count = reservation.row_count
}

// Report whether one layout block references complete source and line ranges.
document_vertical_block_ranges_valid :: #force_inline proc(
    block: app_core.Dynview_Document_Layout_Block,
    source_block_count, line_count: int) -> bool {

    return block.source_block_index >= 0 &&
        block.source_block_index < source_block_count &&
        block.line_start >= 0 && block.line_count > 0 &&
        block.line_count <= line_count-block.line_start
}

// Place and reserve one validated semantic block from the current outer row.
document_place_vertical_block :: proc(
    ctx: Document_Vertical_Context,
    block_index, row_cursor: int) -> Document_Block_Placement_Result {

    builders := ctx.builders
    block := &builders^.blocks.storage[block_index]
    content := &ctx.runtime^.content
    if !document_vertical_block_ranges_valid(
        block^, len(content^.document_blocks), builders^.lines.count) {
        return {row_cursor, .Invalid_Argument}
    }
    spacing, ok := document_block_spacing_before(
        content^.documents, content^.document_blocks,
        block.source_block_index, ctx.style)
    cache := &ctx.runtime^.compile_cache
    reservation_top := f32(row_cursor)*cache^.last_cell_height
    block.top = reservation_top+spacing
    lines := builders^.lines.storage[block.line_start:block.line_start+block.line_count]
    block.bottom, ok = document_place_block_lines(lines, block.top, ctx.style)
    if !ok {
        return {row_cursor, .Invalid_Argument}
    }
    reservation, reserved := grid.reserve_vertical_extent(
        row_cursor, block.bottom-reservation_top, cache^.last_cell_height)
    if !reserved {
        return {row_cursor, .Invalid_Argument}
    }
    source_block := content^.document_blocks[block.source_block_index]
    first_line_indent := document_block_first_line_indent(
        source_block, cache^.last_font_size)
    document_place_block_horizontally(
        source_block, lines, content^.document_display_rows,
        ctx.available_width, first_line_indent)
    for line, relative_index in lines {
        if !document_place_line_contents(
            builders, block.line_start+relative_index, line) {
            return {row_cursor, .Invalid_Argument}
        }
    }
    document_publish_block_reservation(block, spacing, reservation)
    return {row_cursor+reservation.row_count, .Ok}
}

// Place all semantic blocks and reserve each completed extent on the outer grid.
document_place_vertical_layout :: proc(
    runtime: ^app_core.Dynview_System,
    builders: ^Document_Layout_Builders,
    available_width: f32) -> app_core.Bounded_Builder_Status {

    cache := &runtime^.compile_cache
    style, style_ok := document_vertical_style(cache^.last_font_size)
    if !style_ok || cache^.last_cell_height <= 0 {
        return .Invalid_Argument
    }
    ctx := Document_Vertical_Context{
        runtime = runtime, builders = builders,
        style = style, available_width = available_width,
    }
    row_cursor := 0
    for block_index in 0..<builders^.blocks.count {
        result := document_place_vertical_block(ctx, block_index, row_cursor)
        if result.status != .Ok {
            return result.status
        }
        row_cursor = result.next_row
    }
    cache^.document_layout_total_height = f32(row_cursor)*cache^.last_cell_height
    return .Ok
}