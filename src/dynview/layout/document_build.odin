package dynview_layout

import app_core "../../core"
import dynmath "../math"

Document_Copy_Run :: struct {
    run: app_core.Dynview_Document_Shaped_Run,
    glyphs: []app_core.Shaped_Glyph,
    scale: f32,
}

Document_Copy_Cluster :: struct {
    end: int,
    advance: i32,
}

Document_Display_Compose_Context :: struct {
    cache: ^app_core.Dynview_Compile_Cache,
    builders: ^Document_Layout_Builders,
    block: app_core.Dynview_Document_Layout_Block,
    source: app_core.Dynview_Document_Block,
    rows: []app_core.Dynview_Document_Display_Row,
    block_index: int,
    available_width: f32,
}

Document_Display_Measurement :: struct {
    rows: []app_core.Dynview_Document_Display_Row,
    max_primary: f32,
    max_secondary: f32,
    numbered_width: f32,
    alignment_gap: f32,
    aligned_width: f32,
    align_numbers_below: bool,
}

// Clear every semantic document-layout alias without touching command layout.
document_layout_clear :: proc(cache: ^app_core.Dynview_Compile_Cache) {
    if cache == nil {
        return
    }
    cache^.document_layout_nodes = nil
    cache^.document_layout_blocks = nil
    cache^.document_layout_lines = nil
    cache^.document_layout_items = nil
    cache^.document_layout_copy_targets = nil
    cache^.document_layout_total_height = 0
    cache^.document_layout_is_valid = false
    cache^.document_layout_used_greedy_fallback = false
    cache^.document_layout_break_fallback_code = 0
    cache^.document_layout_overfull_line_count = 0
}

// Report whether every prose inline has the Phase 3 measurement required to lower it.
document_layout_inputs_ready :: proc(runtime: ^app_core.Dynview_System) -> bool {
    cache := &runtime^.compile_cache
    shaped_index := 0
    for item, inline_index in runtime^.content.document_inlines {
        if item.kind != .Text && item.kind != .Space {
            continue
        }
        if shaped_index >= len(cache^.document_shaped_runs) ||
            cache^.document_shaped_runs[shaped_index].inline_index != inline_index {
            return false
        }
        shaped_index += 1
    }
    return true
}

// Measure every document-owned math program before semantic layout consumes it.
document_measure_math_programs :: proc(runtime: ^app_core.Dynview_System) -> bool {
    cache := &runtime^.compile_cache
    measured: [app_core.DYNVIEW_MAX_MATH_PROGRAMS]bool
    for item in runtime^.content.document_inlines {
        if item.kind != .Math {continue}
        program_id := item.math_program_id
        if program_id < 0 || program_id >= cache^.math_program_count {return false}
        if measured[program_id] {continue}
        if cache^.math_programs[program_id].draw_width > 0 {
            measured[program_id] = true
            continue
        }
        if !dynmath.measure_math_program(cache, &runtime^.command_buffer,
            &cache^.math_programs[program_id], cache^.last_font_size,
            {dynmath.Math_Style_Level(item.root_style), false}) {
            return false
        }
        measured[program_id] = true
    }
    return true
}

// Append one source-span target for a non-prose atomic item.
document_layout_append_atomic_copy_target :: proc(
    builders: ^Document_Layout_Builders,
    item: app_core.Dynview_Document_Layout_Item) -> app_core.Bounded_Builder_Status {

    if item.source_count <= 0 {
        return .Ok
    }
    target := app_core.Dynview_Document_Layout_Copy_Target{
        line_index = item.line_index, item_index = builders^.items.count,
        offset = item.source_offset, count = item.source_count,
        x = item.x, width = item.width,
    }
    return app_core.bounded_element_builder_append(
        &builders^.copy_targets,
        []app_core.Dynview_Document_Layout_Copy_Target{target})
}

// Resolve and validate the sealed shaping span used by one prose layout item.
document_layout_copy_run :: proc(
    cache: ^app_core.Dynview_Compile_Cache,
    item: app_core.Dynview_Document_Layout_Item) -> (Document_Copy_Run, bool) {

    if item.shaped_run_index < 0 ||
        item.shaped_run_index >= len(cache^.document_shaped_runs) {
        return {}, false
    }
    run := cache^.document_shaped_runs[item.shaped_run_index]
    if run.base_pixel_size <= 0 || run.glyph_start < 0 || run.glyph_count <= 0 ||
        run.glyph_count > len(cache^.document_shaped_glyphs)-run.glyph_start {
        return {}, false
    }
    return {
        run = run,
        glyphs = cache^.document_shaped_glyphs[
            run.glyph_start:run.glyph_start+run.glyph_count],
        scale = cache^.last_font_size/run.base_pixel_size/64,
    }, true
}

// Aggregate adjacent glyphs that map to the same canonical UTF-8 cluster.
document_layout_copy_cluster :: proc(
    glyphs: []app_core.Shaped_Glyph,
    start: int) -> Document_Copy_Cluster {

    result := Document_Copy_Cluster{end = start+1, advance = glyphs[start].x_advance}
    for result.end < len(glyphs) &&
        glyphs[result.end].cluster == glyphs[start].cluster {
        result.advance += glyphs[result.end].x_advance
        result.end += 1
    }
    return result
}

// Append canonical UTF-8 spans from one shaped run's ordered glyph clusters.
document_layout_append_prose_copy_targets :: proc(
    cache: ^app_core.Dynview_Compile_Cache,
    builders: ^Document_Layout_Builders,
    item: app_core.Dynview_Document_Layout_Item) -> app_core.Bounded_Builder_Status {

    shaped, ok := document_layout_copy_run(cache, item)
    if !ok {
        return .Invalid_Argument
    }
    pen_x := item.x
    for start := 0; start < len(shaped.glyphs); {
        cluster := document_layout_copy_cluster(shaped.glyphs, start)
        span_end := shaped.run.text_count
        if cluster.end < len(shaped.glyphs) {
            span_end = int(shaped.glyphs[cluster.end].cluster)
        }
        target := app_core.Dynview_Document_Layout_Copy_Target{
            line_index = item.line_index, item_index = builders^.items.count,
            offset = shaped.run.text_offset+int(shaped.glyphs[start].cluster),
            count = span_end-int(shaped.glyphs[start].cluster),
            x = pen_x, width = f32(cluster.advance)*shaped.scale,
            canonical_text = true,
        }
        status := app_core.bounded_element_builder_append(
            &builders^.copy_targets,
            []app_core.Dynview_Document_Layout_Copy_Target{target})
        if status != .Ok {
            return status
        }
        pen_x += f32(cluster.advance)*shaped.scale
        start = cluster.end
    }
    return .Ok
}

// Append copy geometry using shaped clusters for prose and source spans for atoms.
document_layout_append_copy_targets :: proc(
    cache: ^app_core.Dynview_Compile_Cache,
    builders: ^Document_Layout_Builders,
    item: app_core.Dynview_Document_Layout_Item) -> app_core.Bounded_Builder_Status {

    if item.box_kind == .Prose {
        return document_layout_append_prose_copy_targets(cache, builders, item)
    }
    return document_layout_append_atomic_copy_target(builders, item)
}

// Resolve one node's horizontal extent under its line's glue adjustment.
document_layout_node_width :: proc(
    node: app_core.Dynview_Document_Layout_Node,
    adjustment_ratio: f32) -> f32 {

    if node.kind != .Glue {
        return node.width
    }
    if adjustment_ratio >= 0 {
        return node.width+adjustment_ratio*node.stretch
    }
    return node.width+max(adjustment_ratio, -1)*node.shrink
}

// Append positioned boxes from one broken node range into final item storage.
document_layout_place_line :: proc(
    cache: ^app_core.Dynview_Compile_Cache,
    builders: ^Document_Layout_Builders,
    line_index: int,
    line: ^app_core.Dynview_Document_Layout_Line) -> app_core.Bounded_Builder_Status {

    line^.item_start = builders^.items.count
    x: f32
    for node in builders^.nodes.storage[
        line^.node_start:line^.node_start+line^.node_count] {
        node_width := document_layout_node_width(node, line^.adjustment_ratio)
        if node.kind == .Box || node.kind == .Glue {
            item := app_core.Dynview_Document_Layout_Item{
                box_kind = node.box_kind, inline_index = node.inline_index,
                shaped_run_index = node.shaped_run_index, line_index = line_index,
                source_offset = node.source_offset, source_count = node.source_count,
                text_offset = node.text_offset, text_count = node.text_count,
                x = x, width = node_width,
                ascent = node.ascent, descent = node.descent,
            }
            status := document_layout_append_copy_targets(cache, builders, item)
            if status != .Ok {
                return status
            }
            status = app_core.bounded_element_builder_append(
                &builders^.items, []app_core.Dynview_Document_Layout_Item{item})
            if status != .Ok {
                return status
            }
            line^.ascent = max(line^.ascent, node.ascent)
            line^.descent = max(line^.descent, node.descent)
        }
        x += node_width
    }
    line^.item_count = builders^.items.count-line^.item_start
    return .Ok
}

// Retain one block's breaker outcome for diagnostics and evidence snapshots.
document_layout_record_break_result :: proc(
    cache: ^app_core.Dynview_Compile_Cache,
    result: Document_Break_Result) {

    if result.fallback == .None {
        return
    }
    cache^.document_layout_used_greedy_fallback = true
    cache^.document_layout_break_fallback_code = i32(result.fallback)
}

// Position and summarize every newly broken line for one semantic block.
document_layout_finish_block :: proc(
    cache: ^app_core.Dynview_Compile_Cache,
    builders: ^Document_Layout_Builders,
    block_index, node_start, line_start: int) -> app_core.Bounded_Builder_Status {

    for line_index in line_start..<builders^.lines.count {
        line := &builders^.lines.storage[line_index]
        line^.node_start += node_start
        if line^.overfull {
            cache^.document_layout_overfull_line_count += 1
        }
        status := document_layout_place_line(cache, builders, line_index, line)
        if status != .Ok {return status}
        if line^.display_number > 0 {
            number_ascent := cache^.last_font_size*0.8
            number_descent := cache^.last_font_size*0.2
            if line^.display_number_baseline_offset > 0 {
                line^.descent = max(line^.descent,
                    line^.display_number_baseline_offset+number_descent)
            } else {
                line^.ascent = max(line^.ascent, number_ascent)
                line^.descent = max(line^.descent, number_descent)
            }
        }
    }
    record := &builders^.blocks.storage[block_index]
    record^.line_start = line_start
    record^.line_count = builders^.lines.count-line_start
    for line in builders^.lines.storage[line_start:builders^.lines.count] {
        record^.width = max(record^.width, line.width)
    }
    return .Ok
}

// Return the fixed-width number box needed for a parenthesized positive integer.
document_display_number_width :: proc(
    number: int, cell_width: f32) -> f32 {

    if number <= 0 {return 0}
    digits := 1
    for remaining := number; remaining >= 10; remaining /= 10 {
        digits += 1
    }
    return f32(digits+2)*cell_width
}

// Measure shared columns and numbering space for one technical display block.
document_layout_measure_display :: proc(
    ctx: Document_Display_Compose_Context) -> (
        Document_Display_Measurement, app_core.Bounded_Builder_Status) {

    source, block := ctx.source, ctx.block
    if source.display_row_count <= 0 || source.display_row_start < 0 ||
        source.display_row_count > len(ctx.rows)-source.display_row_start {
        return {}, .Invalid_Argument
    }
    result := Document_Display_Measurement{rows = ctx.rows[
        source.display_row_start:source.display_row_start+source.display_row_count]}
    cursor := block.node_start
    number_column: f32
    for row in result.rows {
        node_count := 3 if row.secondary_program_id >= 0 else 1
        if cursor < block.node_start || node_count >
            block.node_start+block.node_count-cursor {return {}, .Invalid_Argument}
        result.max_primary = max(
            result.max_primary, ctx.builders^.nodes.storage[cursor].width)
        if node_count == 3 {
            result.max_secondary = max(
                result.max_secondary, ctx.builders^.nodes.storage[cursor+2].width)
        }
        number_column = max(number_column,
            document_display_number_width(row.number, ctx.cache^.last_cell_width))
        cursor += node_count
    }
    if cursor != block.node_start+block.node_count {return {}, .Invalid_Argument}
    result.numbered_width = max(
        1, ctx.available_width-number_column-ctx.cache^.last_font_size)
    result.alignment_gap = ctx.cache^.last_font_size*0.5
    result.aligned_width = result.max_primary+result.alignment_gap+result.max_secondary
    result.align_numbers_below = source.display_kind == .Align &&
        number_column > 0 && result.aligned_width > result.numbered_width
    return result, .Ok
}

// Emit one measured technical-display row and return its next node cursor.
document_layout_append_display_row :: proc(
    ctx: Document_Display_Compose_Context,
    measured: Document_Display_Measurement,
    row: app_core.Dynview_Document_Display_Row,
    relative_index, cursor: int) -> (int, app_core.Bounded_Builder_Status) {

    node_count := 3 if row.secondary_program_id >= 0 else 1
    width := ctx.builders^.nodes.storage[cursor].width
    if node_count == 3 {
        spacer := &ctx.builders^.nodes.storage[cursor+1]
        spacer^.width = measured.max_primary-width+measured.alignment_gap
        width = measured.aligned_width
    }
    number_width := document_display_number_width(
        row.number, ctx.cache^.last_cell_width)
    number_below := row.number > 0 &&
        (width > measured.numbered_width || measured.align_numbers_below)
    content_width := ctx.available_width
    if ctx.source.display_kind == .Align && !measured.align_numbers_below ||
        ctx.source.display_kind != .Align && row.number > 0 && !number_below {
        content_width = measured.numbered_width
    }
    line := app_core.Dynview_Document_Layout_Line{
        node_start = cursor-ctx.block.node_start, node_count = node_count,
        block_index = ctx.block_index, natural_width = width, width = width,
        overfull = width > content_width || number_below,
        display_row_index = ctx.source.display_row_start+relative_index,
        display_number = row.number,
        display_number_x = ctx.available_width-number_width,
        display_number_width = number_width,
        display_number_baseline_offset = ctx.cache^.last_font_size*1.2 if number_below else 0,
        display_content_width = content_width,
    }
    status := app_core.bounded_element_builder_append(
        &ctx.builders^.lines, []app_core.Dynview_Document_Layout_Line{line})
    return cursor+node_count, status
}

// Compose one technical display as exactly one immutable line per semantic row.
document_layout_compose_display :: proc(
    ctx: Document_Display_Compose_Context) -> app_core.Bounded_Builder_Status {

    measured, status := document_layout_measure_display(ctx)
    if status != .Ok {return status}
    cursor := ctx.block.node_start
    for row, relative_index in measured.rows {
        cursor, status = document_layout_append_display_row(
            ctx, measured, row, relative_index, cursor)
        if status != .Ok {return status}
    }
    return .Ok
}

// Break and position every lowered semantic block against the real content width.
document_layout_compose_blocks :: proc(
    cache: ^app_core.Dynview_Compile_Cache,
    builders: ^Document_Layout_Builders,
    source_blocks: []app_core.Dynview_Document_Block,
    display_rows: []app_core.Dynview_Document_Display_Row,
    available_width: f32) -> app_core.Bounded_Builder_Status {

    for block, block_index in builders^.blocks.storage[:builders^.blocks.count] {
        if block.source_block_index < 0 ||
            block.source_block_index >= len(source_blocks) {
            return .Invalid_Argument
        }
        source_block := source_blocks[block.source_block_index]
        first_line_indent := document_block_first_line_indent(
            source_block, cache^.last_font_size)
        node_start := block.node_start
        node_count := block.node_count
        line_start := builders^.lines.count
        status: app_core.Bounded_Builder_Status
        if source_block.kind == .Display && source_block.display_kind != .Plain {
            status = document_layout_compose_display({
                cache = cache, builders = builders, block = block,
                source = source_block, rows = display_rows,
                block_index = block_index, available_width = available_width,
            })
        } else {
            break_result := document_optimal_break(builders^.nodes.storage[
                node_start:node_start+node_count], block_index,
                available_width, &builders^.lines, first_line_indent)
            status = break_result.status
            document_layout_record_break_result(cache, break_result)
        }
        if status != .Ok {return status}
        status = document_layout_finish_block(
            cache, builders, block_index, node_start, line_start)
        if status != .Ok {return status}
    }
    return .Ok
}

// Seal all semantic layout families and publish one complete document cache.
document_layout_seal :: proc(
    cache: ^app_core.Dynview_Compile_Cache,
    builders: ^Document_Layout_Builders) -> app_core.Bounded_Builder_Status {

    nodes, node_status := app_core.bounded_element_builder_seal(&builders^.nodes)
    blocks, block_status := app_core.bounded_element_builder_seal(&builders^.blocks)
    lines, line_status := app_core.bounded_element_builder_seal(&builders^.lines)
    items, item_status := app_core.bounded_element_builder_seal(&builders^.items)
    copy_targets, copy_status := app_core.bounded_element_builder_seal(
        &builders^.copy_targets)
    if node_status != .Ok {
        return node_status
    }
    if block_status != .Ok {
        return block_status
    }
    if line_status != .Ok {
        return line_status
    }
    if item_status != .Ok {
        return item_status
    }
    if copy_status != .Ok {
        return copy_status
    }
    cache^.document_layout_nodes = nodes
    cache^.document_layout_blocks = blocks
    cache^.document_layout_lines = lines
    cache^.document_layout_items = items
    cache^.document_layout_copy_targets = copy_targets
    cache^.document_layout_is_valid = true
    return .Ok
}

// Build the authoritative measured semantic document layout.
rebuild_document_layout_cache :: proc(
    runtime: ^app_core.Dynview_System,
    arena: ^app_core.Arena_Owner) -> app_core.Bounded_Builder_Status {

    cache := &runtime^.compile_cache
    document_layout_clear(cache)
    if len(runtime^.content.document_blocks) == 0 {
        cache^.document_layout_is_valid = true
        return .Ok
    }
    if !document_layout_inputs_ready(runtime) {
        return .Ok
    }
    if !document_measure_math_programs(runtime) {
        return .Invalid_Argument
    }
    builders: Document_Layout_Builders
    status := document_layout_builders_init(&builders, arena)
    if status == .Ok {
        status = document_lower_all_blocks(runtime, &builders)
    }
    if status == .Ok {
        available_width := max(1, cache^.last_panel_width-16)
        status = document_layout_compose_blocks(cache, &builders,
            runtime^.content.document_blocks,
            runtime^.content.document_display_rows, available_width)
        if status == .Ok {
            status = document_place_vertical_layout(runtime, &builders, available_width)
        }
    }
    if status == .Ok {
        status = document_layout_seal(cache, &builders)
    }
    if status != .Ok {
        document_layout_clear(cache)
    }
    return status
}