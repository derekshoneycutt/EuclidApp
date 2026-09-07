package dynview_layout

import app_core "../../core"
import "core:mem"
import "core:testing"

Document_Layout_Test_Fixture :: struct {
    blocks: [1]app_core.Dynview_Document_Block,
    inlines: [6]app_core.Dynview_Document_Inline,
    runs: [2]app_core.Dynview_Document_Shaped_Run,
    glyphs: [4]app_core.Shaped_Glyph,
}

// Initialize the semantic records shared by document layout tests.
document_layout_test_semantics :: proc(fixture: ^Document_Layout_Test_Fixture) {
    fixture^.blocks[0] = {
        kind = .Paragraph, inline_start = 0, inline_count = 6,
        source_offset = 0, source_count = 18, alignment = .Left,
    }
    fixture^.inlines = {
        {kind = .Text, source_offset = 0, source_count = 4,
            text_offset = 0, text_count = 4},
        {kind = .Space, source_offset = 4, source_count = 1,
            text_offset = 4, text_count = 1, space_kind = .Breakable},
        {kind = .Math, source_offset = 5, source_count = 4,
            math_program_id = 0},
        {kind = .Penalty, source_offset = 9, penalty = 50},
        {kind = .Forced_Break, source_offset = 9, source_count = 2},
        {kind = .Shape, source_offset = 11, source_count = 7,
            shape = {present = true, kind = .Circle, width = 2, height = 3}},
    }
    fixture^.runs = {
        {inline_index = 0, text_offset = 0, text_count = 4,
            glyph_start = 0, glyph_count = 2, base_pixel_size = 16,
            width = 40, ascent = 12, descent = 3},
        {inline_index = 1, text_offset = 4, text_count = 1,
            glyph_start = 2, glyph_count = 1, base_pixel_size = 16,
            width = 10, ascent = 12, descent = 3},
    }
    fixture^.glyphs = {
        {glyph_id = 1, cluster = 0, x_advance = 1280},
        {glyph_id = 2, cluster = 2, x_advance = 1280},
        {glyph_id = 3, cluster = 0, x_advance = 640},
        {},
    }
}

// Allocate one runtime outside the stack and attach its semantic layout inputs.
document_layout_test_runtime :: proc(
    t: ^testing.T,
    owner: ^app_core.Arena_Owner,
    fixture: ^Document_Layout_Test_Fixture) -> ^app_core.Dynview_System {

    testing.expect(t, app_core.arena_owner_init(owner, 4*uint(mem.Megabyte)))
    allocator := app_core.arena_owner_allocator(owner)
    runtime := new(app_core.Dynview_System, allocator)
    testing.expect(t, runtime != nil)
    document_layout_test_semantics(fixture)
    runtime^.content.document_blocks = fixture^.blocks[:]
    runtime^.content.document_inlines = fixture^.inlines[:]
    cache := &runtime^.compile_cache
    cache^.document_shaped_runs = fixture^.runs[:]
    cache^.document_shaped_glyphs = fixture^.glyphs[:3]
    cache^.last_font_size = 16
    cache^.last_cell_width = 8
    cache^.last_cell_height = 20
    cache^.last_panel_width = 96
    cache^.math_program_count = 1
    cache^.math_programs[0] = {
        valid = true, draw_width = 70, ascent = 18, descent = 6}
    return runtime
}

// Verify semantic shapes retain legacy authored units and fill-only point styling.
@(test)
document_shape_geometry_preserves_authored_units :: proc(t: ^testing.T) {
    point := app_core.Dynview_Document_Shape{
        present = true, kind = .Point, width = 1, height = 1, thickness = 1}
    point_command, point_ok := document_shape_command(point)
    point_geometry, point_geometry_ok := document_shape_geometry(point, 8)
    testing.expect(t, point_ok && point_geometry_ok)
    testing.expect_value(t, point_command.inline_outline_stroke, f32(0))
    testing.expect_value(t, point_geometry.draw_width, f32(16))
    testing.expect_value(t, point_geometry.draw_height, f32(16))

    line := app_core.Dynview_Document_Inline{
        kind = .Shape, shape = {present = true, kind = .Line,
            width = 3, height = 1, thickness = 4}}
    cache := new(app_core.Dynview_Compile_Cache, context.allocator)
    defer free(cache, context.allocator)
    cache^.last_cell_width = 8
    line_node, line_ok := document_shape_node(cache, line, 0)
    testing.expect(t, line_ok)
    testing.expect_value(t, line_node.width, f32(28))
    testing.expect_value(t, line_node.ascent, f32(2))
    testing.expect_value(t, line_node.descent, f32(2))

    pie := app_core.Dynview_Document_Shape{
        present = true, kind = .Angle, width = 2, height = 1,
        thickness = 1, filled = true, start_angle = 0, end_angle = 90}
    pie_geometry, pie_ok := document_shape_geometry(pie, 8)
    testing.expect(t, pie_ok)
    testing.expect(t, pie_geometry.draw_width > 16)
    testing.expect(t, pie_geometry.draw_height > 16)
}

// Verify every semantic layout output family rejects one record beyond its limit.
@(test)
document_layout_builders_enforce_all_output_limits :: proc(t: ^testing.T) {
    arena: app_core.Arena_Owner
    testing.expect(t, app_core.arena_owner_init(&arena, 2*uint(mem.Megabyte)))
    defer app_core.arena_owner_destroy(&arena)
    builders: Document_Layout_Builders
    testing.expect_value(t, document_layout_builders_init(&builders, &arena),
        app_core.Bounded_Builder_Status.Ok)
    builders.nodes.count = app_core.DYNVIEW_MAX_DOCUMENT_LAYOUT_NODES
    builders.blocks.count = app_core.DYNVIEW_MAX_DOCUMENT_BLOCKS
    builders.lines.count = app_core.DYNVIEW_MAX_DOCUMENT_LAYOUT_LINES
    builders.items.count = app_core.DYNVIEW_MAX_DOCUMENT_LAYOUT_ITEMS
    builders.copy_targets.count = app_core.DYNVIEW_MAX_DOCUMENT_LAYOUT_COPY_TARGETS

    testing.expect_value(t, document_append_layout_node(&builders, {}),
        app_core.Bounded_Builder_Status.Limit_Exceeded)
    testing.expect_value(t, app_core.bounded_element_builder_append(
        &builders.blocks, []app_core.Dynview_Document_Layout_Block{{}}),
        app_core.Bounded_Builder_Status.Limit_Exceeded)
    testing.expect_value(t, app_core.bounded_element_builder_append(
        &builders.lines, []app_core.Dynview_Document_Layout_Line{{}}),
        app_core.Bounded_Builder_Status.Limit_Exceeded)
    testing.expect_value(t, app_core.bounded_element_builder_append(
        &builders.items, []app_core.Dynview_Document_Layout_Item{{}}),
        app_core.Bounded_Builder_Status.Limit_Exceeded)
    testing.expect_value(t, app_core.bounded_element_builder_append(
        &builders.copy_targets,
        []app_core.Dynview_Document_Layout_Copy_Target{{}}),
        app_core.Bounded_Builder_Status.Limit_Exceeded)
}

// Verify mixed semantic nodes seal into measured lines and positioned source items.
@(test)
document_layout_builds_mixed_measured_records :: proc(t: ^testing.T) {
    runtime_owner, cache_owner: app_core.Arena_Owner
    fixture: Document_Layout_Test_Fixture
    runtime := document_layout_test_runtime(t, &runtime_owner, &fixture)
    defer app_core.arena_owner_destroy(&runtime_owner)
    testing.expect(t, app_core.arena_owner_init(&cache_owner, 2*uint(mem.Megabyte)))
    defer app_core.arena_owner_destroy(&cache_owner)

    status := rebuild_document_layout_cache(runtime, &cache_owner)
    cache := &runtime^.compile_cache

    testing.expect_value(t, status, app_core.Bounded_Builder_Status.Ok)
    testing.expect(t, cache^.document_layout_is_valid)
    testing.expect_value(t, len(cache^.document_layout_nodes), 6)
    testing.expect_value(t, len(cache^.document_layout_lines), 3)
    testing.expect_value(t, len(cache^.document_layout_items), 3)
    testing.expect_value(t, cache^.document_layout_nodes[1].kind,
        app_core.Dynview_Document_Layout_Node_Kind.Glue)
    testing.expect_value(t, cache^.document_layout_nodes[2].box_kind,
        app_core.Dynview_Document_Box_Kind.Math)
    testing.expect_value(t, cache^.document_layout_nodes[3].kind,
        app_core.Dynview_Document_Layout_Node_Kind.Penalty)
    testing.expect_value(t, cache^.document_layout_items[2].box_kind,
        app_core.Dynview_Document_Box_Kind.Shape)
    testing.expect_value(t, cache^.document_layout_items[2].source_offset, 11)
    testing.expect_value(t, cache^.document_layout_items[2].width, f32(33))
    testing.expect_value(t, cache^.document_layout_items[2].ascent, f32(16.5))
    testing.expect_value(t, cache^.document_layout_items[2].descent, f32(16.5))
    testing.expect_value(t, cache^.document_layout_blocks[0].node_count, 6)
    testing.expect_value(t, cache^.document_layout_blocks[0].line_count, 3)
    testing.expect_value(t, len(cache^.document_layout_copy_targets), 4)
    testing.expect(t, cache^.document_layout_copy_targets[0].canonical_text)
    testing.expect_value(t, cache^.document_layout_copy_targets[0].count, 2)
    testing.expect_value(t, cache^.document_layout_copy_targets[1].offset, 2)
    testing.expect_value(t, cache^.document_layout_copy_targets[2].offset, 5)
    for line_index in 1..<len(cache^.document_layout_lines) {
        previous := cache^.document_layout_lines[line_index-1]
        current := cache^.document_layout_lines[line_index]
        testing.expect(t, previous.bottom <= current.top)
    }
    block := cache^.document_layout_blocks[0]
    testing.expect(t, block.bottom <= block.reserved_bottom)
    testing.expect_value(t, cache^.document_layout_total_height,
        block.reserved_bottom)
}

// Verify changing only panel width deterministically reflows measured prose.
@(test)
document_layout_reflows_from_pixel_width :: proc(t: ^testing.T) {
    runtime_owner, cache_owner: app_core.Arena_Owner
    fixture: Document_Layout_Test_Fixture
    runtime := document_layout_test_runtime(t, &runtime_owner, &fixture)
    defer app_core.arena_owner_destroy(&runtime_owner)
    fixture.blocks[0].inline_count = 3
    fixture.inlines[2] = {kind = .Text, text_offset = 5, text_count = 4}
    fixture.runs[1].inline_index = 1
    third_run := app_core.Dynview_Document_Shaped_Run{
        inline_index = 2, text_offset = 5, text_count = 4,
        glyph_start = 3, glyph_count = 1, base_pixel_size = 16,
        width = 40, ascent = 12, descent = 3}
    runs := [3]app_core.Dynview_Document_Shaped_Run{
        fixture.runs[0], fixture.runs[1], third_run}
    runtime^.compile_cache.document_shaped_runs = runs[:]
    fixture.glyphs[3] = {glyph_id = 4, x_advance = 2560}
    runtime^.compile_cache.document_shaped_glyphs = fixture.glyphs[:]
    testing.expect(t, app_core.arena_owner_init(&cache_owner, 2*uint(mem.Megabyte)))
    defer app_core.arena_owner_destroy(&cache_owner)

    runtime^.compile_cache.last_panel_width = 122
    wide_status := rebuild_document_layout_cache(runtime, &cache_owner)
    wide_lines := len(runtime^.compile_cache.document_layout_lines)
    app_core.arena_owner_reset(&cache_owner)
    runtime^.compile_cache.last_panel_width = 95
    narrow_status := rebuild_document_layout_cache(runtime, &cache_owner)

    testing.expect_value(t, wide_status, app_core.Bounded_Builder_Status.Ok)
    testing.expect_value(t, narrow_status, app_core.Bounded_Builder_Status.Ok)
    testing.expect_value(t, wide_lines, 1)
    testing.expect_value(t, len(runtime^.compile_cache.document_layout_lines), 2)
    targets := runtime^.compile_cache.document_layout_copy_targets
    testing.expect_value(t, targets[len(targets)-1].line_index, 1)
    testing.expect_value(t, targets[len(targets)-1].x, f32(0))
    testing.expect_value(t, targets[len(targets)-1].offset, 5)
}

// Verify no-indent controls both the first-line measure and positioned origin.
@(test)
document_layout_applies_semantic_paragraph_indent :: proc(t: ^testing.T) {
    runtime_owner, cache_owner: app_core.Arena_Owner
    fixture: Document_Layout_Test_Fixture
    runtime := document_layout_test_runtime(t, &runtime_owner, &fixture)
    defer app_core.arena_owner_destroy(&runtime_owner)
    fixture.blocks[0].inline_count = 1
    testing.expect(t, app_core.arena_owner_init(&cache_owner, 2*uint(mem.Megabyte)))
    defer app_core.arena_owner_destroy(&cache_owner)

    indented_status := rebuild_document_layout_cache(runtime, &cache_owner)
    indented_x := runtime^.compile_cache.document_layout_items[0].x
    app_core.arena_owner_reset(&cache_owner)
    fixture.blocks[0].no_indent = true
    plain_status := rebuild_document_layout_cache(runtime, &cache_owner)

    testing.expect_value(t, indented_status, app_core.Bounded_Builder_Status.Ok)
    testing.expect_value(t, plain_status, app_core.Bounded_Builder_Status.Ok)
    testing.expect_value(t, indented_x, f32(16))
    testing.expect_value(t,
        runtime^.compile_cache.document_layout_items[0].x, f32(0))
}

// Verify failed lowering leaves no partially published layout aliases.
@(test)
document_layout_invalid_input_rolls_back :: proc(t: ^testing.T) {
    runtime_owner, cache_owner: app_core.Arena_Owner
    fixture: Document_Layout_Test_Fixture
    runtime := document_layout_test_runtime(t, &runtime_owner, &fixture)
    defer app_core.arena_owner_destroy(&runtime_owner)
    runtime^.compile_cache.math_programs[0].valid = false
    testing.expect(t, app_core.arena_owner_init(&cache_owner, 2*uint(mem.Megabyte)))
    defer app_core.arena_owner_destroy(&cache_owner)

    status := rebuild_document_layout_cache(runtime, &cache_owner)

    testing.expect_value(t, status, app_core.Bounded_Builder_Status.Invalid_Argument)
    testing.expect(t, !runtime^.compile_cache.document_layout_is_valid)
    testing.expect_value(t, len(runtime^.compile_cache.document_layout_nodes), 0)
    testing.expect_value(t, len(runtime^.compile_cache.document_layout_lines), 0)
    testing.expect_value(t, len(runtime^.compile_cache.document_layout_items), 0)
    testing.expect_value(t,
        len(runtime^.compile_cache.document_layout_copy_targets), 0)
}

// Rebuild one width and verify exact lines remain inside outward block reservations.
document_layout_expect_vertical_containment :: proc(
    t: ^testing.T,
    runtime: ^app_core.Dynview_System,
    cache_owner: ^app_core.Arena_Owner,
    panel_width: f32) -> f32 {

    app_core.arena_owner_reset(cache_owner)
    runtime^.compile_cache.last_panel_width = panel_width
    status := rebuild_document_layout_cache(runtime, cache_owner)
    cache := &runtime^.compile_cache
    testing.expect_value(t, status, app_core.Bounded_Builder_Status.Ok)
    for line_index in 1..<len(cache^.document_layout_lines) {
        testing.expect(t, cache^.document_layout_lines[line_index-1].bottom <=
            cache^.document_layout_lines[line_index].top)
    }
    for block in cache^.document_layout_blocks {
        testing.expect(t, block.reserved_top <= block.top)
        testing.expect(t, block.bottom <= block.reserved_bottom)
    }
    return cache^.document_layout_total_height
}

// Verify tall mixed content remains contained while three panel widths reflow it.
@(test)
document_layout_vertical_reservations_contain_three_widths :: proc(t: ^testing.T) {
    runtime_owner, cache_owner: app_core.Arena_Owner
    fixture: Document_Layout_Test_Fixture
    runtime := document_layout_test_runtime(t, &runtime_owner, &fixture)
    defer app_core.arena_owner_destroy(&runtime_owner)
    testing.expect(t, app_core.arena_owner_init(&cache_owner, 2*uint(mem.Megabyte)))
    defer app_core.arena_owner_destroy(&cache_owner)

    wide_height := document_layout_expect_vertical_containment(
        t, runtime, &cache_owner, 160)
    medium_height := document_layout_expect_vertical_containment(
        t, runtime, &cache_owner, 112)
    narrow_height := document_layout_expect_vertical_containment(
        t, runtime, &cache_owner, 72)

    testing.expect(t, wide_height <= medium_height)
    testing.expect(t, medium_height <= narrow_height)
}

// Verify paragraph/display flow shares exact positions and reserves completed blocks.
@(test)
document_layout_places_display_blocks_on_outer_grid :: proc(t: ^testing.T) {
    runtime_owner, cache_owner: app_core.Arena_Owner
    fixture: Document_Layout_Test_Fixture
    runtime := document_layout_test_runtime(t, &runtime_owner, &fixture)
    defer app_core.arena_owner_destroy(&runtime_owner)
    blocks := [3]app_core.Dynview_Document_Block{
        {kind = .Paragraph, inline_start = 0, inline_count = 1,
            source_count = 1, alignment = .Left},
        {kind = .Display, inline_start = 1, inline_count = 1,
            source_offset = 1, source_count = 1, alignment = .Left},
        {kind = .Paragraph, inline_start = 2, inline_count = 1,
            source_offset = 2, source_count = 1, alignment = .Right},
    }
    inlines := [3]app_core.Dynview_Document_Inline{
        {kind = .Shape, source_count = 1,
            shape = {present = true, kind = .Point, width = 1, height = 1}},
        {kind = .Shape, source_offset = 1, source_count = 1,
            shape = {present = true, kind = .Circle, width = 2, height = 2}},
        {kind = .Shape, source_offset = 2, source_count = 1,
            shape = {present = true, kind = .Box, width = 1, height = 1}},
    }
    runtime^.content.document_blocks = blocks[:]
    runtime^.content.document_inlines = inlines[:]
    runtime^.compile_cache.document_shaped_runs = nil
    runtime^.compile_cache.document_shaped_glyphs = nil
    testing.expect(t, app_core.arena_owner_init(&cache_owner, 2*uint(mem.Megabyte)))
    defer app_core.arena_owner_destroy(&cache_owner)

    status := rebuild_document_layout_cache(runtime, &cache_owner)

    testing.expect_value(t, status, app_core.Bounded_Builder_Status.Ok)
    cache := &runtime^.compile_cache
    testing.expect_value(t, cache^.document_layout_blocks[1].spacing_before, f32(12))
    testing.expect_value(t, cache^.document_layout_blocks[2].spacing_before, f32(12))
    testing.expect_value(t, cache^.document_layout_lines[1].x, f32(23.5))
    testing.expect_value(t, cache^.document_layout_lines[2].x, f32(71))
    testing.expect_value(t, cache^.document_layout_items[1].baseline,
        cache^.document_layout_lines[1].baseline)
    testing.expect_value(t, cache^.document_layout_copy_targets[1].y,
        cache^.document_layout_items[1].top)
    for block in cache^.document_layout_blocks {
        testing.expect(t, block.bottom <= block.reserved_bottom)
        testing.expect(t, block.trailing_padding >= 0)
    }
    testing.expect_value(t, cache^.document_layout_blocks[0].row_count, 1)
    testing.expect_value(t, cache^.document_layout_blocks[1].row_count, 3)
    testing.expect_value(t, cache^.document_layout_blocks[2].row_count, 2)
    testing.expect_value(t, cache^.document_layout_total_height, f32(120))
}

// Verify align rows share one measured alignment axis and reserve number space.
@(test)
document_layout_aligns_technical_display_columns :: proc(t: ^testing.T) {
    runtime_owner, cache_owner: app_core.Arena_Owner
    fixture: Document_Layout_Test_Fixture
    runtime := document_layout_test_runtime(t, &runtime_owner, &fixture)
    defer app_core.arena_owner_destroy(&runtime_owner)
    block := [1]app_core.Dynview_Document_Block{{kind = .Display,
        inline_count = 4, display_kind = .Align, display_row_count = 2}}
    rows := [2]app_core.Dynview_Document_Display_Row{
        {primary_program_id = 0, secondary_program_id = 1,
            alignment = .Center, number = 1},
        {primary_program_id = 2, secondary_program_id = 3,
            alignment = .Center},
    }
    inlines := [4]app_core.Dynview_Document_Inline{
        {kind = .Math, math_program_id = 0}, {kind = .Math, math_program_id = 1},
        {kind = .Math, math_program_id = 2}, {kind = .Math, math_program_id = 3},
    }
    runtime^.content.document_blocks = block[:]
    runtime^.content.document_inlines = inlines[:]
    runtime^.content.document_display_rows = rows[:]
    cache := &runtime^.compile_cache
    cache^.math_program_count = 4
    widths := [?]f32{20, 30, 40, 10}
    for width, index in widths {
        cache^.math_programs[index] = {
            valid = true, draw_width = width, ascent = 12, descent = 4}
    }
    testing.expect(t, app_core.arena_owner_init(&cache_owner, 2*uint(mem.Megabyte)))
    defer app_core.arena_owner_destroy(&cache_owner)

    status := rebuild_document_layout_cache(runtime, &cache_owner)

    testing.expect_value(t, status, app_core.Bounded_Builder_Status.Ok)
    testing.expect_value(t, len(cache^.document_layout_lines), 2)
    testing.expect_value(t, len(cache^.document_layout_items), 6)
    testing.expect_value(t, cache^.document_layout_items[2].x,
        cache^.document_layout_items[5].x)
    testing.expect_value(t, cache^.document_layout_lines[0].display_number, 1)
    testing.expect_value(t, cache^.document_layout_lines[1].display_number, 0)
}

// Verify multline row alignment and colliding final-number fallback are deterministic.
@(test)
document_layout_places_narrow_numbered_multline :: proc(t: ^testing.T) {
    runtime_owner, cache_owner: app_core.Arena_Owner
    fixture: Document_Layout_Test_Fixture
    runtime := document_layout_test_runtime(t, &runtime_owner, &fixture)
    defer app_core.arena_owner_destroy(&runtime_owner)
    block := [1]app_core.Dynview_Document_Block{{kind = .Display,
        inline_count = 3, display_kind = .Multline, display_row_count = 3}}
    rows := [3]app_core.Dynview_Document_Display_Row{
        {primary_program_id = 0, secondary_program_id = -1, alignment = .Left},
        {primary_program_id = 1, secondary_program_id = -1, alignment = .Center},
        {primary_program_id = 2, secondary_program_id = -1,
            alignment = .Right, number = 1},
    }
    inlines := [3]app_core.Dynview_Document_Inline{
        {kind = .Math, math_program_id = 0}, {kind = .Math, math_program_id = 1},
        {kind = .Math, math_program_id = 2},
    }
    runtime^.content.document_blocks = block[:]
    runtime^.content.document_inlines = inlines[:]
    runtime^.content.document_display_rows = rows[:]
    cache := &runtime^.compile_cache
    cache^.last_panel_width = 100
    cache^.math_program_count = 3
    widths := [?]f32{20, 30, 70}
    for width, index in widths {
        cache^.math_programs[index] = {
            valid = true, draw_width = width, ascent = 12, descent = 4}
    }
    testing.expect(t, app_core.arena_owner_init(&cache_owner, 2*uint(mem.Megabyte)))
    defer app_core.arena_owner_destroy(&cache_owner)

    status := rebuild_document_layout_cache(runtime, &cache_owner)
    lines := cache^.document_layout_lines

    testing.expect_value(t, status, app_core.Bounded_Builder_Status.Ok)
    testing.expect_value(t, len(lines), 3)
    testing.expect_value(t, lines[0].x, f32(0))
    testing.expect_value(t, lines[1].x, f32(27))
    testing.expect_value(t, lines[2].x, f32(14))
    testing.expect(t, lines[2].display_number_baseline_offset > 0)
    testing.expect(t, lines[2].overfull)
    testing.expect_value(t, cache^.document_layout_overfull_line_count, 1)
}