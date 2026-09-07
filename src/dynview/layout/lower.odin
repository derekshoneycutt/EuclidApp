package dynview_layout

import app_core "../../core"

// Mutable bounded storage for one semantic document layout transaction.
Document_Layout_Builders :: struct {
    nodes: app_core.Bounded_Element_Builder(app_core.Dynview_Document_Layout_Node),
    blocks: app_core.Bounded_Element_Builder(app_core.Dynview_Document_Layout_Block),
    lines: app_core.Bounded_Element_Builder(app_core.Dynview_Document_Layout_Line),
    items: app_core.Bounded_Element_Builder(app_core.Dynview_Document_Layout_Item),
    copy_targets: app_core.Bounded_Element_Builder(
        app_core.Dynview_Document_Layout_Copy_Target),
}

Document_Shaped_Run_Ref :: struct {
    run: ^app_core.Dynview_Document_Shaped_Run,
    index: int,
}

Document_Display_Program_Node_Result :: struct {
    node: app_core.Dynview_Document_Layout_Node,
    next: int,
    ok: bool,
}

// Initialize every semantic layout builder in the worker-owned cache arena.
document_layout_builders_init :: proc(
    builders: ^Document_Layout_Builders,
    arena: ^app_core.Arena_Owner) -> app_core.Bounded_Builder_Status {

    if builders == nil || arena == nil {
        return .Invalid_Argument
    }
    allocator := app_core.arena_owner_allocator(arena)
    status := app_core.bounded_element_builder_init_with_allocator(
        &builders^.nodes, app_core.DYNVIEW_MAX_DOCUMENT_LAYOUT_NODES, allocator)
    if status == .Ok {
        status = app_core.bounded_element_builder_init_with_allocator(
            &builders^.blocks, app_core.DYNVIEW_MAX_DOCUMENT_BLOCKS, allocator)
    }
    if status == .Ok {
        status = app_core.bounded_element_builder_init_with_allocator(
            &builders^.lines, app_core.DYNVIEW_MAX_DOCUMENT_LAYOUT_LINES, allocator)
    }
    if status == .Ok {
        status = app_core.bounded_element_builder_init_with_allocator(
            &builders^.items, app_core.DYNVIEW_MAX_DOCUMENT_LAYOUT_ITEMS, allocator)
    }
    if status == .Ok {
        status = app_core.bounded_element_builder_init_with_allocator(
            &builders^.copy_targets,
            app_core.DYNVIEW_MAX_DOCUMENT_LAYOUT_COPY_TARGETS, allocator)
    }
    return status
}

// Resolve the Phase 3 shaped prose run for one semantic inline index.
document_shaped_run_for_inline :: proc(
    cache: ^app_core.Dynview_Compile_Cache,
    inline_index: int) -> (Document_Shaped_Run_Ref, bool) {

    for run, run_index in cache^.document_shaped_runs {
        if run.inline_index == inline_index {
            return {&cache^.document_shaped_runs[run_index], run_index}, true
        }
        if run.inline_index > inline_index {
            break
        }
    }
    return {}, false
}

// Scale one authoritative prose measurement to the tracked layout font size.
document_prose_node :: proc(
    cache: ^app_core.Dynview_Compile_Cache,
    item: app_core.Dynview_Document_Inline,
    inline_index: int) -> (app_core.Dynview_Document_Layout_Node, bool) {

    shaped, found := document_shaped_run_for_inline(cache, inline_index)
    if !found || shaped.run^.base_pixel_size <= 0 {
        return {}, false
    }
    run := shaped.run
    scale := cache^.last_font_size/run^.base_pixel_size
    kind := app_core.Dynview_Document_Layout_Node_Kind.Box
    break_allowed := false
    if item.kind == .Space {
        kind = .Glue
        break_allowed = item.space_kind != .Nonbreaking
    }
    return {
        kind = kind,
        box_kind = .Prose,
        inline_index = inline_index,
        shaped_run_index = shaped.index,
        source_offset = item.source_offset,
        source_count = item.source_count,
        text_offset = item.text_offset,
        text_count = item.text_count,
        width = run^.width*scale,
        ascent = run^.ascent*scale,
        descent = run^.descent*scale,
        stretch = run^.width*scale*0.5 if kind == .Glue else 0,
        shrink = run^.width*scale/3 if kind == .Glue else 0,
        break_allowed = break_allowed,
    }, true
}

// Resolve one already-measured semantic math program as an atomic box.
document_math_node :: proc(
    cache: ^app_core.Dynview_Compile_Cache,
    item: app_core.Dynview_Document_Inline,
    inline_index: int) -> (app_core.Dynview_Document_Layout_Node, bool) {

    program_id := item.math_program_id
    if program_id < 0 || program_id >= cache^.math_program_count {
        return {}, false
    }
    program := &cache^.math_programs[program_id]
    if !program^.valid {
        return {}, false
    }
    return {
        kind = .Box, box_kind = .Math, inline_index = inline_index,
        shaped_run_index = -1, width = max(program^.draw_width, program^.advance),
        source_offset = item.source_offset, source_count = item.source_count,
        ascent = program^.ascent, descent = program^.descent,
    }, true
}

// Convert one semantic Euclid shape to the legacy intrinsic-geometry payload.
document_shape_command :: proc(
    shape: app_core.Dynview_Document_Shape) -> (app_core.Dynview_Command, bool) {

    command := app_core.Dynview_Command{
        inline_atom_dimension = shape.width,
        inline_box_height = shape.height,
        inline_atom_stroke = shape.thickness,
        inline_outline_stroke = shape.thickness,
        pie_start_angle_degrees = shape.start_angle,
        pie_end_angle_degrees = shape.end_angle,
        pie_is_filled = shape.filled,
    }
    switch shape.kind {
    case .Point:
        command.kind = .Inline_Filled_Circle
        command.inline_outline_stroke = 0
    case .Line: command.kind = .Inline_Line
    case .Circle:
        command.kind = .Inline_Filled_Circle if shape.filled else .Inline_Circle
    case .Box:
        command.kind = .Inline_Filled_Box if shape.filled else .Inline_Box
    case .Angle, .Semicircle: command.kind = .Inline_Pie_Section
    case .Perpendicular: command.kind = .Inline_Perpendicular
    case .Triangle: command.kind = .Inline_Triangle
    case .Pentagon: command.kind = .Inline_Pentagon
    case .None: return {}, false
    }
    return command, true
}

// Measure one semantic shape with the established stroke-inclusive geometry.
document_shape_geometry :: proc(
    shape: app_core.Dynview_Document_Shape,
    cell_width: f32) -> (Inline_Shape_Geometry, bool) {

    command, ok := document_shape_command(shape)
    if !ok {
        return {}, false
    }
    return inline_shape_geometry(command, cell_width), true
}

// Measure one semantic Euclid shape using its established font-relative dimensions.
document_shape_node :: proc(
    cache: ^app_core.Dynview_Compile_Cache,
    item: app_core.Dynview_Document_Inline,
    inline_index: int) -> (app_core.Dynview_Document_Layout_Node, bool) {

    if !item.shape.present || item.shape.kind == .None {
        return {}, false
    }
    geometry, ok := document_shape_geometry(item.shape, cache^.last_cell_width)
    if !ok {
        return {}, false
    }
    return {
        kind = .Box, box_kind = .Shape, inline_index = inline_index,
        shaped_run_index = -1, width = geometry.draw_width,
        source_offset = item.source_offset, source_count = item.source_count,
        ascent = geometry.draw_height*0.5, descent = geometry.draw_height*0.5,
    }, true
}

// Lower one semantic inline to one measured horizontal-list node.
document_lower_inline :: proc(
    cache: ^app_core.Dynview_Compile_Cache,
    item: app_core.Dynview_Document_Inline,
    inline_index: int) -> (app_core.Dynview_Document_Layout_Node, bool) {

    switch item.kind {
    case .Text, .Space:
        return document_prose_node(cache, item, inline_index)
    case .Math:
        return document_math_node(cache, item, inline_index)
    case .Shape:
        return document_shape_node(cache, item, inline_index)
    case .Penalty:
        return {kind = .Penalty, inline_index = inline_index,
            shaped_run_index = -1, penalty = item.penalty,
            break_allowed = item.penalty < 10000}, true
    case .Forced_Break:
        return {kind = .Forced_Break, inline_index = inline_index,
            shaped_run_index = -1, break_allowed = true}, true
    }
    return {}, false
}

// Append one measured node to the bounded document layout transaction.
document_append_layout_node :: proc(
    builders: ^Document_Layout_Builders,
    node: app_core.Dynview_Document_Layout_Node) -> app_core.Bounded_Builder_Status {

    return app_core.bounded_element_builder_append(
        &builders^.nodes, []app_core.Dynview_Document_Layout_Node{node})
}

// Resolve one display program through its source-mapping math inline.
document_display_program_node :: proc(
    cache: ^app_core.Dynview_Compile_Cache,
    content: ^app_core.Dynview_Content_View,
    block: app_core.Dynview_Document_Block,
    program_id, search_start: int) -> Document_Display_Program_Node_Result {

    end := block.inline_start+block.inline_count
    for inline_index in search_start..<end {
        item := content^.document_inlines[inline_index]
        if item.kind == .Math && item.math_program_id == program_id {
            node, ok := document_math_node(cache, item, inline_index)
            return {node, inline_index+1, ok}
        }
    }
    return {next = search_start}
}

// Lower one technical display block as ordered row math boxes and align spacers.
document_lower_display_block :: proc(
    cache: ^app_core.Dynview_Compile_Cache,
    content: ^app_core.Dynview_Content_View,
    block: app_core.Dynview_Document_Block,
    builders: ^Document_Layout_Builders) -> app_core.Bounded_Builder_Status {

    if block.display_row_start < 0 || block.display_row_count <= 0 ||
        block.display_row_count >
            len(content^.document_display_rows)-block.display_row_start {
        return .Invalid_Argument
    }
    search_start := block.inline_start
    rows := content^.document_display_rows[block.display_row_start:
        block.display_row_start+block.display_row_count]
    for row in rows {
        primary := document_display_program_node(
            cache, content, block, row.primary_program_id, search_start)
        if !primary.ok {return .Invalid_Argument}
        status := document_append_layout_node(builders, primary.node)
        if status != .Ok {return status}
        search_start = primary.next
        if row.secondary_program_id < 0 {
            continue
        }
        status = document_append_layout_node(builders, {
            kind = .Glue, inline_index = -1, shaped_run_index = -1})
        if status != .Ok {return status}
        secondary := document_display_program_node(
            cache, content, block, row.secondary_program_id, search_start)
        if !secondary.ok {return .Invalid_Argument}
        status = document_append_layout_node(builders, secondary.node)
        if status != .Ok {return status}
        search_start = secondary.next
    }
    return .Ok
}

// Lower one semantic block's contiguous inline range into measured nodes.
document_lower_block :: proc(
    cache: ^app_core.Dynview_Compile_Cache,
    content: ^app_core.Dynview_Content_View,
    block: app_core.Dynview_Document_Block,
    builders: ^Document_Layout_Builders) -> app_core.Bounded_Builder_Status {

    if block.inline_start < 0 || block.inline_count < 0 ||
        block.inline_count > len(content^.document_inlines)-block.inline_start {
        return .Invalid_Argument
    }
    if block.kind == .Display && block.display_kind != .Plain {
        return document_lower_display_block(cache, content, block, builders)
    }
    for inline_index in block.inline_start..<block.inline_start+block.inline_count {
        node, ok := document_lower_inline(
            cache, content^.document_inlines[inline_index], inline_index)
        if !ok {
            return .Invalid_Argument
        }
        status := document_append_layout_node(builders, node)
        if status != .Ok {
            return status
        }
    }
    return .Ok
}

// Lower all semantic blocks and preserve each block's bounded node range.
document_lower_all_blocks :: proc(
    runtime: ^app_core.Dynview_System,
    builders: ^Document_Layout_Builders) -> app_core.Bounded_Builder_Status {

    content := &runtime^.content
    cache := &runtime^.compile_cache
    for block, block_index in content^.document_blocks {
        node_start := builders^.nodes.count
        status := document_lower_block(cache, content, block, builders)
        if status != .Ok {
            return status
        }
        record := app_core.Dynview_Document_Layout_Block{
            source_block_index = block_index,
            node_start = node_start,
            node_count = builders^.nodes.count-node_start,
        }
        status = app_core.bounded_element_builder_append(
            &builders^.blocks, []app_core.Dynview_Document_Layout_Block{record})
        if status != .Ok {
            return status
        }
    }
    return .Ok
}