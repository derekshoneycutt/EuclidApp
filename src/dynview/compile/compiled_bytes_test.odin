package dynview_compile

import app_core "../../core"
import dyncore "../core"

import "core:mem"
import "core:testing"

//   Initialize caller-owned display-cache arena storage without copying its allocator.
compiled_bytes_test_arena_init :: proc(
    t: ^testing.T,
    arena: ^app_core.Arena_Owner) {

    testing.expect(t, app_core.arena_owner_init(arena, 256*uint(mem.Kilobyte)))
}

// Verify semantic compilation skips command layout while standalone streams retain it.
@(test)
semantic_documents_publish_without_command_layout :: proc(t: ^testing.T) {
    runtime_arena, cache_arena: app_core.Arena_Owner
    compiled_bytes_test_arena_init(t, &runtime_arena)
    defer app_core.arena_owner_destroy(&runtime_arena)
    compiled_bytes_test_arena_init(t, &cache_arena)
    defer app_core.arena_owner_destroy(&cache_arena)
    allocator := app_core.arena_owner_allocator(&runtime_arena)
    runtime := new(app_core.Dynview_System, allocator)
    documents := [1]app_core.Dynview_Document{{}}
    runtime^.content.documents = documents[:]

    semantic_status := compile_derived_views(runtime, &cache_arena, {}, {})

    testing.expect_value(t, semantic_status, dyncore.DYNVIEW_STATUS_OK)
    testing.expect(t, runtime^.compile_cache.document_layout_is_valid)
    testing.expect(t, !runtime^.compile_cache.layout_is_valid)
    testing.expect_value(t, len(runtime^.compile_cache.layout_lines), 0)
    testing.expect_value(t, len(runtime^.compile_cache.layout_items), 0)

    runtime^.content.documents = nil
    app_core.arena_owner_reset(&cache_arena)
    standalone_status := compile_derived_views(runtime, &cache_arena, {}, {})

    testing.expect_value(t, standalone_status, dyncore.DYNVIEW_STATUS_OK)
    testing.expect(t, runtime^.compile_cache.layout_is_valid)
}

//   Verify successful compilation seals plain and copy bytes into arena aliases.
@(test)
compiled_bytes_publish_sealed_plain_and_copy_payloads :: proc(t: ^testing.T) {
    arena: app_core.Arena_Owner
    compiled_bytes_test_arena_init(t, &arena)
    defer app_core.arena_owner_destroy(&arena)
    allocator := app_core.arena_owner_allocator(&arena)
    runtime := new(app_core.Dynview_System, allocator)
    buffer := &runtime^.command_buffer
    copy(buffer^.text_bytes[:], "drawcopy")
    buffer^.text_bytes_len = 8
    buffer^.command_count = 4
    buffer^.commands[0] = {kind = .Begin_Block, block_id = 7}
    buffer^.commands[1] = {kind = .Text_Run, text_offset = 0, text_len = 4}
    buffer^.commands[2] = {
        kind = .Copyable_Text_Run, copy_text_offset = 4, copy_text_len = 4,
    }
    buffer^.commands[3] = {kind = .End_Block}

    status := rebuild_compiled_plain_text(runtime, &arena)

    cache := &runtime^.compile_cache
    testing.expect_value(t, status, dyncore.DYNVIEW_STATUS_OK)
    testing.expect_value(t, cache^.compiled_plain_text_len, 4)
    testing.expect_value(t, cache^.compiled_copy_payload_len, 4)
    testing.expect_value(t, string(cache^.compiled_plain_text), "draw")
    testing.expect_value(t, string(cache^.compiled_copy_payload), "copy")
    testing.expect_value(t, cache^.copy_block_count, 1)
    testing.expect_value(t, cache^.copy_blocks[0].payload_offset, 0)
    testing.expect_value(t, cache^.copy_blocks[0].payload_len, 4)
}

//   Verify an incomplete command stream publishes no compiled byte aliases.
@(test)
compiled_bytes_reject_incomplete_stream_without_publication :: proc(t: ^testing.T) {
    arena: app_core.Arena_Owner
    compiled_bytes_test_arena_init(t, &arena)
    defer app_core.arena_owner_destroy(&arena)
    allocator := app_core.arena_owner_allocator(&arena)
    runtime := new(app_core.Dynview_System, allocator)
    runtime^.command_buffer.command_count = 1
    runtime^.command_buffer.commands[0] = {kind = .Begin_Block, block_id = 1}

    status := rebuild_compiled_plain_text(runtime, &arena)

    testing.expect_value(t, status, dyncore.DYNVIEW_STATUS_ILLEGAL_STATE)
    testing.expect_value(t, len(runtime^.compile_cache.compiled_plain_text), 0)
    testing.expect_value(t, len(runtime^.compile_cache.compiled_copy_payload), 0)
}

//   Verify published immutable views override conflicting fixed staging records.
@(test)
compiled_bytes_consume_published_content_views :: proc(t: ^testing.T) {
    arena: app_core.Arena_Owner
    compiled_bytes_test_arena_init(t, &arena)
    defer app_core.arena_owner_destroy(&arena)
    allocator := app_core.arena_owner_allocator(&arena)
    runtime := new(app_core.Dynview_System, allocator)
    buffer := &runtime^.command_buffer
    buffer^.command_count = 1
    buffer^.commands[0] = {kind = .Begin_Block, block_id = 99}
    commands := [3]app_core.Dynview_Command{
        {kind = .Begin_Block, block_id = 7},
        {kind = .Text_Run, block_id = 7, text_len = 4},
        {kind = .End_Block, block_id = 7},
    }
    text: string = "view"
    buffer^.command_view = commands[:]
    buffer^.text_view = transmute([]u8)text

    status := rebuild_compiled_plain_text(runtime, &arena)

    testing.expect_value(t, status, dyncore.DYNVIEW_STATUS_OK)
    testing.expect_value(t, string(runtime^.compile_cache.compiled_plain_text), text)
    testing.expect_value(t, raw_data(dyncore.command_buffer_commands(buffer)),
        raw_data(buffer^.command_view))
    testing.expect_value(t, raw_data(dyncore.command_buffer_text(buffer)),
        raw_data(buffer^.text_view))
}

//   Verify compiled plain text cannot grow beyond its hard admission limit.
@(test)
compiled_bytes_reject_plain_text_overflow_without_publication :: proc(t: ^testing.T) {
    arena: app_core.Arena_Owner
    compiled_bytes_test_arena_init(t, &arena)
    defer app_core.arena_owner_destroy(&arena)
    allocator := app_core.arena_owner_allocator(&arena)
    cache := new(app_core.Dynview_Compile_Cache, allocator)
    state := Dynview_Compile_State{}
    testing.expect_value(t, app_core.bounded_byte_builder_init(
        &state.plain_text_builder, app_core.DYNVIEW_MAX_TEXT_BYTES, &arena),
        app_core.Bounded_Builder_Status.Ok)
    state.plain_text_builder.count = app_core.DYNVIEW_MAX_TEXT_BYTES

    status := append_compiled_byte(cache, &state, 'x')

    testing.expect_value(t, status, dyncore.DYNVIEW_STATUS_OUT_OF_CAPACITY)
    testing.expect_value(t, cache^.compiled_plain_text_len, 0)
    testing.expect_value(t, len(cache^.compiled_plain_text), 0)
}

//   Verify copy blocks preserve source order and payload spans after sealing.
@(test)
compiled_copy_blocks_publish_ordered_payload_spans :: proc(t: ^testing.T) {
    arena: app_core.Arena_Owner
    compiled_bytes_test_arena_init(t, &arena)
    defer app_core.arena_owner_destroy(&arena)
    allocator := app_core.arena_owner_allocator(&arena)
    runtime := new(app_core.Dynview_System, allocator)
    buffer := &runtime^.command_buffer
    copy(buffer^.text_bytes[:], "abcd")
    buffer^.text_bytes_len = 4
    buffer^.command_count = 6
    buffer^.commands[0] = {kind = .Begin_Block, block_id = 7}
    buffer^.commands[1] = {
        kind = .Copyable_Text_Run, copy_text_offset = 0, copy_text_len = 2,
    }
    buffer^.commands[2] = {kind = .End_Block}
    buffer^.commands[3] = {kind = .Begin_Block, block_id = 9}
    buffer^.commands[4] = {
        kind = .Copyable_Text_Run, copy_text_offset = 2, copy_text_len = 2,
    }
    buffer^.commands[5] = {kind = .End_Block}

    status := rebuild_compiled_plain_text(runtime, &arena)

    blocks := runtime^.compile_cache.copy_blocks
    testing.expect_value(t, status, dyncore.DYNVIEW_STATUS_OK)
    testing.expect_value(t, len(blocks), 2)
    testing.expect_value(t, blocks[0].block_id, i32(7))
    testing.expect_value(t, blocks[0].payload_offset, 0)
    testing.expect_value(t, blocks[0].payload_len, 2)
    testing.expect_value(t, blocks[1].block_id, i32(9))
    testing.expect_value(t, blocks[1].payload_offset, 2)
    testing.expect_value(t, blocks[1].payload_len, 2)
}

//   Verify copy-block admission rejects one record beyond the command limit.
@(test)
compiled_copy_blocks_reject_exact_limit_overflow :: proc(t: ^testing.T) {
    arena: app_core.Arena_Owner
    compiled_bytes_test_arena_init(t, &arena)
    defer app_core.arena_owner_destroy(&arena)
    state := Dynview_Compile_State{
        open_block = true,
        block_has_copy_payload = true,
    }
    testing.expect_value(t, app_core.bounded_element_builder_init(
        &state.copy_block_builder, app_core.DYNVIEW_MAX_COMMANDS, &arena),
        app_core.Bounded_Builder_Status.Ok)
    state.copy_block_builder.count = app_core.DYNVIEW_MAX_COMMANDS
    allocator := app_core.arena_owner_allocator(&arena)
    cache := new(app_core.Dynview_Compile_Cache, allocator)
    cache^.compiled_copy_payload_len = 1

    status := compile_end_block(cache, &state)

    testing.expect_value(t, status, dyncore.DYNVIEW_STATUS_OUT_OF_CAPACITY)
    testing.expect_value(t, cache^.copy_block_count, 0)
    testing.expect_value(t, len(cache^.copy_blocks), 0)
}

//   Verify repeated target refreshes reuse arena capacity and preserve geometry.
@(test)
copy_hit_targets_reuse_capacity_across_frames :: proc(t: ^testing.T) {
    arena: app_core.Arena_Owner
    compiled_bytes_test_arena_init(t, &arena)
    defer app_core.arena_owner_destroy(&arena)
    allocator := app_core.arena_owner_allocator(&arena)
    runtime := new(app_core.Dynview_System, allocator)
    cache := &runtime^.compile_cache
    testing.expect_value(t, app_core.bounded_element_builder_init(
        &cache^.copy_hit_target_builder, app_core.DYNVIEW_MAX_COMMANDS, &arena),
        app_core.Bounded_Builder_Status.Ok)
    cache^.is_valid = true
    cache^.layout_is_valid = true
    cache^.last_cell_height = 20
    cache^.copy_blocks = []app_core.Dynview_Copy_Block{{block_id = 3, payload_len = 2}}
    cache^.copy_block_count = 1
    cache^.layout_items = []app_core.Dynview_Layout_Item{{block_id = 3, line_index = 0}}
    cache^.layout_item_count = 1
    cache^.layout_lines = []app_core.Dynview_Layout_Line{{row_span = 1}}
    cache^.layout_line_count = 1
    layout := Copy_Hit_Target_Layout{
        panel = {width = 120, height = 100},
        text_padding = 4,
        icon_size = 12,
    }

    first_status := rebuild_copy_hit_targets(runtime, layout)
    storage := raw_data(cache^.copy_hit_target_builder.storage)
    capacity := cache^.copy_hit_target_builder.allocated_capacity
    second_status := rebuild_copy_hit_targets(runtime, layout)

    testing.expect_value(t, first_status, dyncore.DYNVIEW_STATUS_OK)
    testing.expect_value(t, second_status, dyncore.DYNVIEW_STATUS_OK)
    testing.expect_value(t, len(cache^.copy_hit_targets), 1)
    testing.expect_value(t, cache^.copy_hit_targets[0].block_id, i32(3))
    testing.expect_value(t, raw_data(cache^.copy_hit_target_builder.storage), storage)
    testing.expect_value(t, cache^.copy_hit_target_builder.allocated_capacity, capacity)
}

//   Verify semantic documents derive copy geometry from sealed block bounds.
@(test)
document_copy_hit_target_uses_semantic_layout :: proc(t: ^testing.T) {
    arena: app_core.Arena_Owner
    compiled_bytes_test_arena_init(t, &arena)
    defer app_core.arena_owner_destroy(&arena)
    allocator := app_core.arena_owner_allocator(&arena)
    runtime := new(app_core.Dynview_System, allocator)
    cache := &runtime^.compile_cache
    testing.expect_value(t, app_core.bounded_element_builder_init(
        &cache^.copy_hit_target_builder, app_core.DYNVIEW_MAX_COMMANDS, &arena),
        app_core.Bounded_Builder_Status.Ok)
    documents := [1]app_core.Dynview_Document{{}}
    runtime^.content.documents = documents[:]
    cache^.is_valid = true
    cache^.document_layout_is_valid = true
    cache^.copy_blocks = []app_core.Dynview_Copy_Block{{
        block_id = 7, payload_offset = 3, payload_len = 9}}
    cache^.copy_block_count = 1
    cache^.document_layout_blocks = []app_core.Dynview_Document_Layout_Block{
        {reserved_top = 2, reserved_bottom = 24},
        {reserved_top = 30, reserved_bottom = 58},
    }

    status := rebuild_copy_hit_targets(runtime, {
        panel = {x = 5, y = 10, width = 120, height = 100},
        scroll_y = 4, text_padding = 6, icon_size = 12})

    testing.expect_value(t, status, dyncore.DYNVIEW_STATUS_OK)
    testing.expect_value(t, len(cache^.copy_hit_targets), 1)
    target := cache^.copy_hit_targets[0]
    testing.expect_value(t, target.block_id, i32(7))
    testing.expect_value(t, target.payload_offset, 3)
    testing.expect_value(t, target.payload_len, 9)
    testing.expect_value(t, target.hover_rect.y, f32(14))
    testing.expect_value(t, target.hover_rect.height, f32(56))
}

//   Verify hit-target admission rejects one visible record beyond its hard limit.
@(test)
copy_hit_targets_reject_exact_limit_overflow :: proc(t: ^testing.T) {
    arena: app_core.Arena_Owner
    compiled_bytes_test_arena_init(t, &arena)
    defer app_core.arena_owner_destroy(&arena)
    allocator := app_core.arena_owner_allocator(&arena)
    cache := new(app_core.Dynview_Compile_Cache, allocator)
    testing.expect_value(t, app_core.bounded_element_builder_init(
        &cache^.copy_hit_target_builder, app_core.DYNVIEW_MAX_COMMANDS, &arena),
        app_core.Bounded_Builder_Status.Ok)
    cache^.copy_hit_target_builder.count = app_core.DYNVIEW_MAX_COMMANDS

    _, status := append_visible_copy_hit_target(
        cache,
        {block_id = 1, payload_len = 1},
        {panel = {width = 100, height = 100}, icon_size = 12},
        {top = 0, bottom = 20})

    testing.expect_value(t, status, dyncore.DYNVIEW_STATUS_OUT_OF_CAPACITY)
    testing.expect_value(t, cache^.copy_hit_target_count, 0)
    testing.expect_value(t, len(cache^.copy_hit_targets), 0)
}