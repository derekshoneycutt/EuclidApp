package dynview_compile

import app_core "../../core"
import dyncore "../core"
import dynlayout "../layout"
import dynmath "../math"

import "core:os"
import rl "vendor:raylib"

Dynview_Compile_State :: struct {
    plain_text_builder: app_core.Bounded_Byte_Builder,
    copy_payload_builder: app_core.Bounded_Byte_Builder,
    copy_block_builder: app_core.Bounded_Element_Builder(app_core.Dynview_Copy_Block),
    open_block: bool,
    block_id: i32,
    block_kind: i32,
    block_row_start: int,
    block_row_end: int,
    block_payload_start: int,
    block_has_copy_payload: bool,
    current_row: int,
}

//   Uniform handler shape for one dynview command kind during compilation.
Compile_Command_Handler :: #type proc(
    cache: ^app_core.Dynview_Compile_Cache,
    buffer: ^app_core.Dynview_Command_Buffer,
    state: ^Dynview_Compile_State,
    cmd: app_core.Dynview_Command) -> i32

//   Dispatch table mapping each dynview command kind to its compile handler.
COMPILE_COMMAND_HANDLERS ::
    [app_core.Dynview_Command_Kind]Compile_Command_Handler{
    .Begin_Block = compile_handle_begin_block,
    .End_Block = compile_handle_end_block,
    .Text_Run = compile_text_run,
    .Math_Glyph_Run = compile_text_run,
    .Math_Block = compile_text_run,
    .Script_Attach = compile_script_attach_recursive,
    .Frac = compile_text_run,
    .Stretch_Delimiter = compile_text_run,
    .Matrix = compile_text_run,
    .Style_Override = compile_text_run,
    .Stack = compile_text_run,
    .Large_Op = compile_large_op_recursive,
    .Accent_Bar = compile_text_run,
    .Radical_Bar = compile_text_run,
    .Copyable_Text_Run = compile_copyable_text_run,
    .Line_Break = compile_handle_newline,
    .Divider = compile_handle_newline,
    .Inline_Line = compile_handle_inline_line,
    .Inline_Box = compile_handle_inline_box,
    .Inline_Circle = compile_handle_inline_circle,
    .Inline_Filled_Box = compile_handle_inline_filled_box,
    .Inline_Filled_Circle = compile_handle_inline_filled_circle,
    .Inline_Pie_Section = compile_handle_inline_pie_section,
    .Inline_Perpendicular = compile_handle_inline_box,
    .Inline_Triangle = compile_handle_inline_box,
    .Inline_Pentagon = compile_handle_inline_box,
}

Compiled_Optional_Group :: struct {
    offset, count: int,
    prefix: string,
    close: u8,
}

Copy_Hit_Target_Layout :: struct {
    panel: rl.Rectangle,
    scroll_y, text_padding, icon_size, icon_x_pad: f32,
}

Visible_Copy_Block_Rows :: struct {
    top, bottom, last_hover_bottom: f32,
}

//   Append one compiled plain-text byte through the bounded cache builder.
append_compiled_byte :: proc(
    cache: ^app_core.Dynview_Compile_Cache,
    state: ^Dynview_Compile_State,
    value: u8) -> i32 {

    status := app_core.bounded_byte_builder_append(
        &state^.plain_text_builder, []u8{value})
    if status == .Ok {
        cache^.compiled_plain_text_len = state^.plain_text_builder.count
    }
    return dyncore.compiled_builder_status(status)
}

//   Copy one command text slice into compiled plain-text cache with bounds checks.
append_compiled_text_slice :: proc(
    cache: ^app_core.Dynview_Compile_Cache,
    buffer: ^app_core.Dynview_Command_Buffer,
    state: ^Dynview_Compile_State,
    offset, count: int) -> i32 {

    if offset < 0 || count < 0 {
        return dyncore.DYNVIEW_STATUS_INVALID_ARGUMENT
    }
    text_bytes := dyncore.command_buffer_text(buffer)
    if offset + count > len(text_bytes) {
        return dyncore.DYNVIEW_STATUS_INVALID_ARGUMENT
    }

    status := app_core.bounded_byte_builder_append(
        &state^.plain_text_builder, text_bytes[offset:offset + count])
    if status == .Ok {
        cache^.compiled_plain_text_len = state^.plain_text_builder.count
    }
    return dyncore.compiled_builder_status(status)
}

//   Append one byte to compiled copy payload cache and report capacity errors.
append_copy_payload_byte :: proc(
    cache: ^app_core.Dynview_Compile_Cache,
    state: ^Dynview_Compile_State,
    value: u8) -> i32 {

    status := app_core.bounded_byte_builder_append(
        &state^.copy_payload_builder, []u8{value})
    if status == .Ok {
        cache^.compiled_copy_payload_len = state^.copy_payload_builder.count
    }
    return dyncore.compiled_builder_status(status)
}

//   Copy one command copy-text slice into compiled copy payload cache.
append_copy_payload_slice :: proc(
    cache: ^app_core.Dynview_Compile_Cache,
    buffer: ^app_core.Dynview_Command_Buffer,
    state: ^Dynview_Compile_State,
    offset, count: int) -> i32 {

    if offset < 0 || count < 0 {
        return dyncore.DYNVIEW_STATUS_INVALID_ARGUMENT
    }
    text_bytes := dyncore.command_buffer_text(buffer)
    if offset + count > len(text_bytes) {
        return dyncore.DYNVIEW_STATUS_INVALID_ARGUMENT
    }

    status := app_core.bounded_byte_builder_append(
        &state^.copy_payload_builder, text_bytes[offset:offset + count])
    if status == .Ok {
        cache^.compiled_copy_payload_len = state^.copy_payload_builder.count
    }
    return dyncore.compiled_builder_status(status)
}

//   Require an open block before consuming block-scoped content commands.
require_open_block :: #force_inline proc(open_block: bool) -> i32 {
    if open_block {
        return dyncore.DYNVIEW_STATUS_OK
    }
    return dyncore.DYNVIEW_STATUS_ILLEGAL_STATE
}

//   Apply begin-block ordering rule.
compile_begin_block :: #force_inline proc(
    cache: ^app_core.Dynview_Compile_Cache,
    state: ^Dynview_Compile_State,
    cmd: app_core.Dynview_Command) -> i32 {

    if state^.open_block {
        return dyncore.DYNVIEW_STATUS_ILLEGAL_STATE
    }

    state^.open_block = true
    state^.block_id = cmd.block_id
    state^.block_kind = cmd.style_id
    state^.block_row_start = state^.current_row
    state^.block_row_end = state^.current_row
    state^.block_payload_start = cache^.compiled_copy_payload_len
    state^.block_has_copy_payload = false
    return dyncore.DYNVIEW_STATUS_OK
}

//   Apply end-block ordering rule.
compile_end_block :: #force_inline proc(
    cache: ^app_core.Dynview_Compile_Cache,
    state: ^Dynview_Compile_State) -> i32 {

    if !state^.open_block {
        return dyncore.DYNVIEW_STATUS_ILLEGAL_STATE
    }

    if state^.block_has_copy_payload {
        payload_len := cache^.compiled_copy_payload_len - state^.block_payload_start
        block := app_core.Dynview_Copy_Block{
            block_id = state^.block_id,
            block_kind = state^.block_kind,
            row_start = state^.block_row_start,
            row_end = state^.block_row_end,
            payload_offset = state^.block_payload_start,
            payload_len = payload_len,
        }
        status := app_core.bounded_element_builder_append(
            &state^.copy_block_builder, []app_core.Dynview_Copy_Block{block})
        if status != .Ok {
            return dyncore.compiled_builder_status(status)
        }
        cache^.copy_block_count = state^.copy_block_builder.count
    }

    state^.open_block = false
    return dyncore.DYNVIEW_STATUS_OK
}

//   Apply text-run compilation rule.
compile_text_run :: #force_inline proc(
    cache: ^app_core.Dynview_Compile_Cache,
    buffer: ^app_core.Dynview_Command_Buffer,
    state: ^Dynview_Compile_State,
    cmd: app_core.Dynview_Command) -> i32 {

    status := require_open_block(state^.open_block)
    if status != dyncore.DYNVIEW_STATUS_OK {
        return status
    }

    state^.block_row_end = state^.current_row
    return append_compiled_text_slice(cache, buffer, state, cmd.text_offset, cmd.text_len)
}

//   Apply recursive script-wrapper compilation using grouped parent serialization.
compile_script_attach_recursive :: #force_inline proc(
    cache: ^app_core.Dynview_Compile_Cache,
    buffer: ^app_core.Dynview_Command_Buffer,
    state: ^Dynview_Compile_State,
    cmd: app_core.Dynview_Command) -> i32 {

    status := require_open_block(state^.open_block)
    if status != dyncore.DYNVIEW_STATUS_OK {
        return status
    }

    status = append_compiled_byte(cache, state, '{')
    if status != dyncore.DYNVIEW_STATUS_OK {
        return status
    }

    status = append_compiled_text_slice(
        cache, buffer, state, cmd.text_offset, cmd.text_len)
    if status != dyncore.DYNVIEW_STATUS_OK {
        return status
    }

    status = append_compiled_byte(cache, state, '}')
    if status != dyncore.DYNVIEW_STATUS_OK {
        return status
    }

    status = append_compiled_optional_group(cache, buffer, state, {
        cmd.script_sup_text_offset, cmd.script_sup_text_len, "^{", '}',
    })
    if status != dyncore.DYNVIEW_STATUS_OK {
        return status
    }

    status = append_compiled_optional_group(cache, buffer, state, {
        cmd.script_sub_text_offset, cmd.script_sub_text_len, "_{", '}',
    })
    if status != dyncore.DYNVIEW_STATUS_OK {
        return status
    }

    state^.block_row_end = state^.current_row
    return dyncore.DYNVIEW_STATUS_OK
}

//   Append a wrapped text group: prefix bytes, body bytes, then a closing byte.
append_compiled_group :: proc(
    cache: ^app_core.Dynview_Compile_Cache,
    state: ^Dynview_Compile_State,
    prefix, body: string,
    close: u8) -> i32 {

    for i in 0..<len(prefix) {
        status := append_compiled_byte(cache, state, prefix[i])
        if status != dyncore.DYNVIEW_STATUS_OK {
            return status
        }
    }
    for i in 0..<len(body) {
        status := append_compiled_byte(cache, state, body[i])
        if status != dyncore.DYNVIEW_STATUS_OK {
            return status
        }
    }
    return append_compiled_byte(cache, state, close)
}

//   Append one wrapped group only when its body is non-empty.
append_compiled_optional_group :: proc(
    cache: ^app_core.Dynview_Compile_Cache,
    buffer: ^app_core.Dynview_Command_Buffer,
    state: ^Dynview_Compile_State,
    group: Compiled_Optional_Group) -> i32 {

    text := dyncore.text_span_from_buffer(buffer, group.offset, group.count)
    if len(text) == 0 {
        return dyncore.DYNVIEW_STATUS_OK
    }
    return append_compiled_group(cache, state, group.prefix, text, group.close)
}

//   Apply display-style large-operator compilation with canonical limits ordering.
compile_large_op_recursive :: #force_inline proc(
    cache: ^app_core.Dynview_Compile_Cache,
    buffer: ^app_core.Dynview_Command_Buffer,
    state: ^Dynview_Compile_State,
    cmd: app_core.Dynview_Command) -> i32 {

    status := require_open_block(state^.open_block)
    if status != dyncore.DYNVIEW_STATUS_OK {
        return status
    }

    base_text := dynlayout.large_op_visible_text(buffer, cmd)
    for i in 0..<len(base_text) {
        status = append_compiled_byte(cache, state, base_text[i])
        if status != dyncore.DYNVIEW_STATUS_OK {
            return status
        }
    }

    status = append_compiled_optional_group(cache, buffer, state, {
        cmd.script_sub_text_offset, cmd.script_sub_text_len, "_{", '}',
    })
    if status != dyncore.DYNVIEW_STATUS_OK {
        return status
    }

    status = append_compiled_optional_group(cache, buffer, state, {
        cmd.script_sup_text_offset, cmd.script_sup_text_len, "^{", '}',
    })
    if status != dyncore.DYNVIEW_STATUS_OK {
        return status
    }

    state^.block_row_end = state^.current_row
    return dyncore.DYNVIEW_STATUS_OK
}

//   Apply copyable-run compilation rule.
compile_copyable_text_run :: #force_inline proc(
    cache: ^app_core.Dynview_Compile_Cache,
    buffer: ^app_core.Dynview_Command_Buffer,
    state: ^Dynview_Compile_State,
    cmd: app_core.Dynview_Command) -> i32 {

    status := require_open_block(state^.open_block)
    if status != dyncore.DYNVIEW_STATUS_OK {
        return status
    }

    status = append_copy_payload_slice(
        cache, buffer, state, cmd.copy_text_offset, cmd.copy_text_len)
    if status != dyncore.DYNVIEW_STATUS_OK {
        return status
    }

    if cmd.copy_text_len > 0 {
        state^.block_has_copy_payload = true
    }
    return dyncore.DYNVIEW_STATUS_OK
}

//   Apply inline-line compilation rule.
compile_inline_line :: #force_inline proc(
    state: ^Dynview_Compile_State,
    cmd: app_core.Dynview_Command) -> i32 {

    status := require_open_block(state^.open_block)
    if status != dyncore.DYNVIEW_STATUS_OK {
        return status
    }

    if cmd.inline_atom_dimension <= 0 || cmd.inline_atom_stroke <= 0 {
        return dyncore.DYNVIEW_STATUS_INVALID_ARGUMENT
    }

    state^.block_row_end = state^.current_row
    return dyncore.DYNVIEW_STATUS_OK
}

//   Apply inline-box compilation rule.
compile_inline_box :: #force_inline proc(
    state: ^Dynview_Compile_State,
    cmd: app_core.Dynview_Command) -> i32 {

    status := require_open_block(state^.open_block)
    if status != dyncore.DYNVIEW_STATUS_OK {
        return status
    }

    if cmd.inline_atom_dimension <= 0 || cmd.inline_box_height <= 0 ||
        cmd.inline_atom_stroke <= 0 {
        return dyncore.DYNVIEW_STATUS_INVALID_ARGUMENT
    }

    state^.block_row_end = state^.current_row
    return dyncore.DYNVIEW_STATUS_OK
}

//   Apply inline-circle compilation rule.
compile_inline_circle :: #force_inline proc(
    state: ^Dynview_Compile_State,
    cmd: app_core.Dynview_Command) -> i32 {

    status := require_open_block(state^.open_block)
    if status != dyncore.DYNVIEW_STATUS_OK {
        return status
    }

    if cmd.inline_atom_dimension <= 0 || cmd.inline_atom_stroke <= 0 {
        return dyncore.DYNVIEW_STATUS_INVALID_ARGUMENT
    }

    state^.block_row_end = state^.current_row
    return dyncore.DYNVIEW_STATUS_OK
}

//   Apply inline-filled-box compilation rule.
compile_inline_filled_box :: #force_inline proc(
    state: ^Dynview_Compile_State,
    cmd: app_core.Dynview_Command) -> i32 {

    status := require_open_block(state^.open_block)
    if status != dyncore.DYNVIEW_STATUS_OK {
        return status
    }

    if cmd.inline_atom_dimension <= 0 || cmd.inline_box_height <= 0 ||
        cmd.inline_outline_stroke < 0 {
        return dyncore.DYNVIEW_STATUS_INVALID_ARGUMENT
    }

    state^.block_row_end = state^.current_row
    return dyncore.DYNVIEW_STATUS_OK
}

//   Apply inline-filled-circle compilation rule.
compile_inline_filled_circle :: #force_inline proc(
    state: ^Dynview_Compile_State,
    cmd: app_core.Dynview_Command) -> i32 {

    status := require_open_block(state^.open_block)
    if status != dyncore.DYNVIEW_STATUS_OK {
        return status
    }

    if cmd.inline_atom_dimension <= 0 || cmd.inline_outline_stroke < 0 {
        return dyncore.DYNVIEW_STATUS_INVALID_ARGUMENT
    }

    state^.block_row_end = state^.current_row
    return dyncore.DYNVIEW_STATUS_OK
}

//   Apply inline pie-section compilation rule.
compile_inline_pie_section :: #force_inline proc(
    state: ^Dynview_Compile_State,
    cmd: app_core.Dynview_Command) -> i32 {

    status := require_open_block(state^.open_block)
    if status != dyncore.DYNVIEW_STATUS_OK {
        return status
    }

    if cmd.inline_atom_dimension <= 0 || cmd.inline_outline_stroke < 0 {
        return dyncore.DYNVIEW_STATUS_INVALID_ARGUMENT
    }

    state^.block_row_end = state^.current_row
    return dyncore.DYNVIEW_STATUS_OK
}

//   Apply newline-like command rule shared by line-break and divider.
compile_newline_command :: #force_inline proc(
    cache: ^app_core.Dynview_Compile_Cache,
    state: ^Dynview_Compile_State) -> i32 {

    status := require_open_block(state^.open_block)
    if status != dyncore.DYNVIEW_STATUS_OK {
        return status
    }

    status = append_compiled_byte(cache, state, '\n')
    if status != dyncore.DYNVIEW_STATUS_OK {
        return status
    }

    if state^.block_has_copy_payload {
        status = append_copy_payload_byte(cache, state, '\n')
        if status != dyncore.DYNVIEW_STATUS_OK {
            return status
        }
    }

    state^.current_row += 1
    return dyncore.DYNVIEW_STATUS_OK
}

//   Adapt compile_begin_block (no command buffer) to the uniform table shape.
compile_handle_begin_block :: #force_inline proc(
    cache: ^app_core.Dynview_Compile_Cache,
    buffer: ^app_core.Dynview_Command_Buffer,
    state: ^Dynview_Compile_State,
    cmd: app_core.Dynview_Command) -> i32 {
    return compile_begin_block(cache, state, cmd)
}

//   Adapt compile_end_block (no command payload) to the uniform table shape.
compile_handle_end_block :: #force_inline proc(
    cache: ^app_core.Dynview_Compile_Cache,
    buffer: ^app_core.Dynview_Command_Buffer,
    state: ^Dynview_Compile_State,
    cmd: app_core.Dynview_Command) -> i32 {
    return compile_end_block(cache, state)
}

//   Adapt newline commands (no command payload) to the uniform table shape.
compile_handle_newline :: #force_inline proc(
    cache: ^app_core.Dynview_Compile_Cache,
    buffer: ^app_core.Dynview_Command_Buffer,
    state: ^Dynview_Compile_State,
    cmd: app_core.Dynview_Command) -> i32 {
    return compile_newline_command(cache, state)
}

//   Adapt compile_inline_line (no cache or buffer) to the uniform table shape.
compile_handle_inline_line :: #force_inline proc(
    cache: ^app_core.Dynview_Compile_Cache,
    buffer: ^app_core.Dynview_Command_Buffer,
    state: ^Dynview_Compile_State,
    cmd: app_core.Dynview_Command) -> i32 {
    return compile_inline_line(state, cmd)
}

//   Adapt compile_inline_box (no cache or buffer) to the uniform table shape.
compile_handle_inline_box :: #force_inline proc(
    cache: ^app_core.Dynview_Compile_Cache,
    buffer: ^app_core.Dynview_Command_Buffer,
    state: ^Dynview_Compile_State,
    cmd: app_core.Dynview_Command) -> i32 {
    return compile_inline_box(state, cmd)
}

//   Adapt compile_inline_circle (no cache or buffer) to the uniform table shape.
compile_handle_inline_circle :: #force_inline proc(
    cache: ^app_core.Dynview_Compile_Cache,
    buffer: ^app_core.Dynview_Command_Buffer,
    state: ^Dynview_Compile_State,
    cmd: app_core.Dynview_Command) -> i32 {
    return compile_inline_circle(state, cmd)
}

//   Adapt compile_inline_filled_box (no cache or buffer) to the uniform shape.
compile_handle_inline_filled_box :: #force_inline proc(
    cache: ^app_core.Dynview_Compile_Cache,
    buffer: ^app_core.Dynview_Command_Buffer,
    state: ^Dynview_Compile_State,
    cmd: app_core.Dynview_Command) -> i32 {
    return compile_inline_filled_box(state, cmd)
}

//   Adapt compile_inline_filled_circle (no cache or buffer) to the uniform shape.
compile_handle_inline_filled_circle :: #force_inline proc(
    cache: ^app_core.Dynview_Compile_Cache,
    buffer: ^app_core.Dynview_Command_Buffer,
    state: ^Dynview_Compile_State,
    cmd: app_core.Dynview_Command) -> i32 {
    return compile_inline_filled_circle(state, cmd)
}

//   Adapt compile_inline_pie_section (no cache or buffer) to the uniform shape.
compile_handle_inline_pie_section :: #force_inline proc(
    cache: ^app_core.Dynview_Compile_Cache,
    buffer: ^app_core.Dynview_Command_Buffer,
    state: ^Dynview_Compile_State,
    cmd: app_core.Dynview_Command) -> i32 {
    return compile_inline_pie_section(state, cmd)
}

//   Compile one command into cache and enforce the ordering contract.
compile_command :: #force_inline proc(
    cache: ^app_core.Dynview_Compile_Cache,
    buffer: ^app_core.Dynview_Command_Buffer,
    state: ^Dynview_Compile_State,
    cmd: app_core.Dynview_Command) -> i32 {

    kind := cmd.kind
    if kind < .Begin_Block || kind > .Inline_Pentagon {
        return dyncore.DYNVIEW_STATUS_INVALID_ARGUMENT
    }
    handlers := COMPILE_COMMAND_HANDLERS
    handler := handlers[kind]
    if handler == nil {
        return dyncore.DYNVIEW_STATUS_INVALID_ARGUMENT
    }
    return handler(cache, buffer, state, cmd)
}

//   Initialize bounded storage for one compiled Dynview cache transaction.
compiled_builders_init :: proc(
    cache: ^app_core.Dynview_Compile_Cache,
    state: ^Dynview_Compile_State,
    cache_arena: ^app_core.Arena_Owner) -> i32 {
    plain_status := app_core.bounded_byte_builder_init(
        &state^.plain_text_builder, app_core.DYNVIEW_MAX_TEXT_BYTES, cache_arena)
    if plain_status != .Ok {
        return dyncore.compiled_builder_status(plain_status)
    }
    copy_status := app_core.bounded_byte_builder_init(
        &state^.copy_payload_builder, app_core.DYNVIEW_MAX_TEXT_BYTES, cache_arena)
    if copy_status != .Ok {
        return dyncore.compiled_builder_status(copy_status)
    }
    block_status := app_core.bounded_element_builder_init(
        &state^.copy_block_builder, app_core.DYNVIEW_MAX_COMMANDS, cache_arena)
    if block_status != .Ok {
        return dyncore.compiled_builder_status(block_status)
    }
    target_status := app_core.bounded_element_builder_init(
        &cache^.copy_hit_target_builder, app_core.DYNVIEW_MAX_COMMANDS, cache_arena)
    if target_status != .Ok {
        return dyncore.compiled_builder_status(target_status)
    }
    return dyncore.DYNVIEW_STATUS_OK
}

//   Seal and publish all compiled text and copy-block payloads atomically.
compiled_builders_seal :: proc(
    cache: ^app_core.Dynview_Compile_Cache,
    state: ^Dynview_Compile_State) -> i32 {
    plain_text, plain_status := app_core.bounded_byte_builder_seal(
        &state^.plain_text_builder)
    if plain_status != .Ok {
        return dyncore.compiled_builder_status(plain_status)
    }
    copy_payload, copy_status := app_core.bounded_byte_builder_seal(
        &state^.copy_payload_builder)
    if copy_status != .Ok {
        return dyncore.compiled_builder_status(copy_status)
    }
    copy_blocks, block_status := app_core.bounded_element_builder_seal(
        &state^.copy_block_builder)
    if block_status != .Ok {
        return dyncore.compiled_builder_status(block_status)
    }
    cache^.compiled_plain_text = plain_text
    cache^.compiled_copy_payload = copy_payload
    cache^.copy_blocks = copy_blocks
    return dyncore.DYNVIEW_STATUS_OK
}

//   Validate ordering contract and materialize stream text for host rendering.
rebuild_compiled_plain_text :: proc(
    runtime: ^app_core.Dynview_System,
    cache_arena: ^app_core.Arena_Owner) -> i32 {

    cache := &runtime^.compile_cache
    buffer := &runtime^.command_buffer
    cache^.compiled_plain_text = nil
    cache^.compiled_copy_payload = nil
    cache^.copy_blocks = nil
    cache^.copy_hit_targets = nil
    cache^.compiled_plain_text_len = 0
    cache^.compiled_copy_payload_len = 0
    cache^.copy_block_count = 0
    cache^.copy_hit_target_count = 0

    compile_state := Dynview_Compile_State{}
    init_status := compiled_builders_init(cache, &compile_state, cache_arena)
    if init_status != dyncore.DYNVIEW_STATUS_OK {
        return init_status
    }
    for command in dyncore.command_buffer_commands(buffer) {
        status := compile_command(cache, buffer, &compile_state, command)
        if status != dyncore.DYNVIEW_STATUS_OK {
            return status
        }
    }

    if compile_state.open_block {
        return dyncore.DYNVIEW_STATUS_ILLEGAL_STATE
    }
    return compiled_builders_seal(cache, &compile_state)
}

//   Rebuild scratchpad copy icon hit targets from compiled copy blocks.
rebuild_copy_hit_targets :: proc(
    runtime: ^app_core.Dynview_System,
    layout: Copy_Hit_Target_Layout) -> i32 {

    if runtime == nil {
        return dyncore.DYNVIEW_STATUS_INVALID_ARGUMENT
    }

    cache := &runtime^.compile_cache
    cache^.copy_hit_targets = nil
    cache^.copy_hit_target_count = 0
    semantic_document := dynlayout.document_layout_is_authoritative(runtime)
    if !cache^.is_valid || (!semantic_document && !cache^.layout_is_valid) {
        return dyncore.DYNVIEW_STATUS_OK
    }
    clear_status := app_core.bounded_element_builder_clear(
        &cache^.copy_hit_target_builder)
    if clear_status != .Ok {
        return dyncore.compiled_builder_status(clear_status)
    }
    if semantic_document {
        return rebuild_document_copy_hit_target(cache, layout)
    }

    panel_top := layout.panel.y
    last_hover_bottom := panel_top
    for i in 0..<cache^.copy_block_count {
        next_bottom, status := rebuild_one_copy_hit_target(cache,
            cache^.copy_blocks[i], layout, last_hover_bottom)
        if status != dyncore.DYNVIEW_STATUS_OK {
            _ = app_core.bounded_element_builder_clear(&cache^.copy_hit_target_builder)
            return status
        }
        last_hover_bottom = next_bottom
    }
    targets, view_status := app_core.bounded_element_builder_view(
        &cache^.copy_hit_target_builder)
    if view_status != .Ok {
        return dyncore.compiled_builder_status(view_status)
    }
    cache^.copy_hit_targets = targets
    cache^.copy_hit_target_count = len(targets)
    return dyncore.DYNVIEW_STATUS_OK
}

//   Build the authored document copy action from sealed semantic block bounds.
rebuild_document_copy_hit_target :: proc(
    cache: ^app_core.Dynview_Compile_Cache,
    layout: Copy_Hit_Target_Layout) -> i32 {

    blocks := cache^.document_layout_blocks
    if cache^.copy_block_count != 1 || len(blocks) == 0 {
        return dyncore.DYNVIEW_STATUS_ILLEGAL_STATE
    }
    first := blocks[0]
    last := blocks[len(blocks)-1]
    content_origin := layout.panel.y + layout.text_padding - layout.scroll_y
    rows := Visible_Copy_Block_Rows{
        top = content_origin + first.reserved_top,
        bottom = content_origin + last.reserved_bottom,
        last_hover_bottom = layout.panel.y,
    }
    _, status := append_visible_copy_hit_target(
        cache, cache^.copy_blocks[0], layout, rows)
    if status != dyncore.DYNVIEW_STATUS_OK {
        return status
    }
    targets, view_status := app_core.bounded_element_builder_view(
        &cache^.copy_hit_target_builder)
    if view_status != .Ok {
        return dyncore.compiled_builder_status(view_status)
    }
    cache^.copy_hit_targets = targets
    cache^.copy_hit_target_count = len(targets)
    return dyncore.DYNVIEW_STATUS_OK
}

//   Build one copy hit target for a block when its rows are visible on the panel.
//   Returns the updated last-hover bottom edge (unchanged when nothing was added).
rebuild_one_copy_hit_target :: proc(
    cache: ^app_core.Dynview_Compile_Cache,
    block: app_core.Dynview_Copy_Block,
    layout: Copy_Hit_Target_Layout,
    last_hover_bottom: f32) -> (f32, i32) {

    line_span := dynlayout.layout_item_line_span_for_block(cache, block.block_id)
    if !line_span.has_visible_items || line_span.last_line >= cache^.layout_line_count {
        return last_hover_bottom, dyncore.DYNVIEW_STATUS_OK
    }

    panel_top := layout.panel.y
    panel_bottom := layout.panel.y + layout.panel.height
    start_line := cache^.layout_lines[line_span.first_line]
    end_line := cache^.layout_lines[line_span.last_line]
    row_top := layout.panel.y + layout.text_padding +
        f32(start_line.row_start) * cache^.last_cell_height - layout.scroll_y
    row_bottom := layout.panel.y + layout.text_padding +
        f32(end_line.row_start + end_line.row_span) * cache^.last_cell_height -
        layout.scroll_y
    if row_bottom < panel_top || row_top > panel_bottom {
        return last_hover_bottom, dyncore.DYNVIEW_STATUS_OK
    }

    return append_visible_copy_hit_target(
        cache, block, layout, {row_top, row_bottom, last_hover_bottom})
}

//   Append the hit target for a visible copy block and return its hover bottom.
append_visible_copy_hit_target :: proc(
    cache: ^app_core.Dynview_Compile_Cache,
    block: app_core.Dynview_Copy_Block,
    layout: Copy_Hit_Target_Layout,
    rows: Visible_Copy_Block_Rows) -> (f32, i32) {

    panel := layout.panel
    panel_top := panel.y
    panel_bottom := panel.y + panel.height
    visible_top := max(max(rows.top, panel_top), rows.last_hover_bottom)
    visible_bottom := min(rows.bottom, panel_bottom)
    hover_rect := rl.Rectangle{
        panel.x + layout.text_padding,
        visible_top,
        max(0.0, panel.width - layout.text_padding * 2),
        max(0.0, visible_bottom - visible_top),
    }
    if hover_rect.height <= 0 || hover_rect.width <= 0 {
        return rows.last_hover_bottom, dyncore.DYNVIEW_STATUS_OK
    }

    icon_x := panel.x + panel.width - layout.text_padding - layout.icon_size -
        layout.icon_x_pad
    icon_y := max(panel_top + 1, min(
        rows.top + 2, panel_bottom - layout.icon_size - 1))
    target := app_core.Dynview_Copy_Hit_Target{
        block_id = block.block_id,
        payload_offset = block.payload_offset,
        payload_len = block.payload_len,
        rect = {icon_x, icon_y, layout.icon_size, layout.icon_size},
        hover_rect = hover_rect,
    }
    status := app_core.bounded_element_builder_append(
        &cache^.copy_hit_target_builder, []app_core.Dynview_Copy_Hit_Target{target})
    if status != .Ok {
        return rows.last_hover_bottom, dyncore.compiled_builder_status(status)
    }
    return hover_rect.y + hover_rect.height, dyncore.DYNVIEW_STATUS_OK
}

//   Return compiled copy payload string for one hit target index.
copy_target_payload :: proc(
    runtime: ^app_core.Dynview_System, target_index: int) -> string {
    if runtime == nil || runtime^.cache_access_state != .Display_Readable {
        return ""
    }

    cache := &runtime^.compile_cache
    if target_index < 0 || target_index >= cache^.copy_hit_target_count {
        return ""
    }

    target := cache^.copy_hit_targets[target_index]
    if target.payload_offset < 0 || target.payload_len <= 0 {
        return ""
    }
    if target.payload_offset + target.payload_len > cache^.compiled_copy_payload_len {
        return ""
    }

    return string(cache^.compiled_copy_payload[
            target.payload_offset:target.payload_offset + target.payload_len])
}

//   Clear worker-built views after a failed compile without touching semantic input.
clear_partial_derived_views :: proc(cache: ^app_core.Dynview_Compile_Cache) {
    if cache == nil {
        return
    }
    cache^.compiled_plain_text_len = 0
    cache^.compiled_copy_payload_len = 0
    cache^.compiled_plain_text = nil
    cache^.compiled_copy_payload = nil
    cache^.copy_blocks = nil
    cache^.copy_hit_targets = nil
    cache^.copy_hit_target_builder = {}
    cache^.copy_block_count = 0
    cache^.copy_hit_target_count = 0
    clear_document_shaped_records(cache)
    dynlayout.document_layout_clear(cache)
    dynmath.layout_reset_cache(cache)
    cache^.is_valid = false
}

//   Seed mutable math measurement records from the immutable published content.
prepare_math_working_records :: proc(runtime: ^app_core.Dynview_System) {
    content := &runtime^.content
    cache := &runtime^.compile_cache
    cache^.math_program_count = len(content^.math_programs)
    cache^.math_table_descriptor_count = len(content^.math_table_descriptors)
    cache^.math_command_count = len(content^.math_commands)
    cache^.math_node_count = len(content^.math_nodes)
    copy(cache^.math_programs[:cache^.math_program_count], content^.math_programs)
    copy(cache^.math_table_descriptors[:cache^.math_table_descriptor_count],
        content^.math_table_descriptors)
    copy(cache^.math_commands[:cache^.math_command_count], content^.math_commands)
    copy(cache^.math_nodes[:cache^.math_node_count], content^.math_nodes)
}

//   Rebuild compiled text, shaped math, and layout views in dependency order.
compile_derived_views :: proc(
    runtime: ^app_core.Dynview_System,
    cache_arena: ^app_core.Arena_Owner,
    shaping_service: dynmath.Math_Shaping_Service,
    prose_service: Document_Prose_Shaping_Service) -> i32 {
    status := rebuild_compiled_plain_text(runtime, cache_arena)
    if status != dyncore.DYNVIEW_STATUS_OK {
        return status
    }
    prose_status := rebuild_document_shaped_cache(runtime, cache_arena, prose_service)
    if prose_status != .Ok {
        return shaped_builder_error_status(prose_status)
    }
    shaping_status := dynmath.rebuild_shaped_math_cache(
        runtime, cache_arena, shaping_service)
    if shaping_status != .Ok {
        return shaped_builder_error_status(shaping_status)
    }
    if len(runtime^.content.documents) > 0 {
        dynmath.layout_reset_cache(&runtime^.compile_cache)
    } else {
        layout_status := dynlayout.rebuild_layout_cache(runtime, cache_arena)
        if layout_status != dyncore.DYNVIEW_STATUS_OK {
            return layout_status
        }
    }
    document_status := dynlayout.rebuild_document_layout_cache(runtime, cache_arena)
    if document_status == .Ok {
        return dyncore.DYNVIEW_STATUS_OK
    }
    return shaped_builder_error_status(document_status)
}

//   Compile invalidated command and layout caches through worker-owned arena lifetime.
//
// Side effects:
//   - Resets `cache_arena` before mutating derived cache state for one rebuild.
//   - Leaves the arena and cache unchanged when no rebuild is required.
compile_if_needed :: proc(
    runtime: ^app_core.Dynview_System,
    cache_arena: ^app_core.Arena_Owner,
    shaping_service: dynmath.Math_Shaping_Service = {},
    prose_service: Document_Prose_Shaping_Service = {}) {

    if runtime == nil || !runtime^.enabled {
        return
    }

    if !compile_is_needed(runtime) {
        return
    }

    if !compile_worker_can_rebuild(runtime, cache_arena) {
        return
    }
    cache := &runtime^.compile_cache
    clear_partial_derived_views(cache)
    dynmath.clear_shaped_records(cache)
    app_core.arena_owner_reset(cache_arena)
    if runtime^.command_buffer.command_view != nil {
        prepare_math_working_records(runtime)
    }
    buffer := &runtime^.command_buffer
    cache^.last_error_code = dyncore.DYNVIEW_STATUS_OK
    status := compile_derived_views(
        runtime, cache_arena, shaping_service, prose_service)
    cache^.compiled_revision = buffer^.revision
    cache^.compiled_command_count = len(dyncore.command_buffer_commands(buffer))
    cache^.compiled_text_bytes_len = len(dyncore.command_buffer_text(buffer))
    cache^.last_invalidation_mask = runtime^.pending_invalidation_mask
    runtime^.pending_invalidation_mask = 0

    if status != dyncore.DYNVIEW_STATUS_OK {
        fail_compile_rebuild(runtime, status)
        return
    }

    buffer^.has_stream_error = false
    cache^.is_valid = true
}

//   Mark one rebuild failure and discard all partially derived cache views.
fail_compile_rebuild :: proc(runtime: ^app_core.Dynview_System, status: i32) {
    dyncore.mark_stream_error(runtime, status)
    clear_partial_derived_views(&runtime^.compile_cache)
    dynmath.clear_shaped_records(&runtime^.compile_cache)
}

//   Validate worker ownership and arena lifetime before one invalidated rebuild.
compile_worker_can_rebuild :: #force_inline proc(
    runtime: ^app_core.Dynview_System,
    cache_arena: ^app_core.Arena_Owner) -> bool {

    if runtime^.cache_access_state != .Worker_Mutable ||
        runtime^.cache_worker_thread_id != os.get_current_thread_id() {
        return false
    }
    if cache_arena == nil || !cache_arena^.initialized {
        dyncore.mark_stream_error(runtime, dyncore.DYNVIEW_STATUS_ILLEGAL_STATE)
        return false
    }
    return true
}

//   Translate bounded shaping storage failures into stable Dynview status values.
shaped_builder_error_status :: #force_inline proc(
    status: app_core.Bounded_Builder_Status) -> i32 {

    switch status {
    case .Invalid_Argument:
        return dyncore.DYNVIEW_STATUS_INVALID_ARGUMENT
    case .Sealed:
        return dyncore.DYNVIEW_STATUS_ILLEGAL_STATE
    case .Ok, .Limit_Exceeded, .Allocation_Failed:
        return dyncore.DYNVIEW_STATUS_OUT_OF_CAPACITY
    }
    return dyncore.DYNVIEW_STATUS_ILLEGAL_STATE
}

//   Return whether the current command stream or layout inputs require compilation.
compile_is_needed :: proc(runtime: ^app_core.Dynview_System) -> bool {
    if runtime == nil || !runtime^.enabled {
        return false
    }

    cache := &runtime^.compile_cache
    buffer := &runtime^.command_buffer
    return !cache^.is_valid || runtime^.pending_invalidation_mask != 0 ||
        cache^.compiled_revision != buffer^.revision
}

//   Return compiled text when validation succeeds without mutating compile state.
scratchpad_text_or_fallback :: proc(
    runtime: ^app_core.Dynview_System,
    fallback_text: string) -> string {

    if runtime == nil || !runtime^.enabled ||
        runtime^.cache_access_state != .Display_Readable ||
        !runtime^.compile_cache.is_valid ||
        runtime^.command_buffer.has_stream_error {
        return fallback_text
    }

    text_len := runtime^.compile_cache.compiled_plain_text_len
    return string(runtime^.compile_cache.compiled_plain_text[:text_len])
}

//   Recompute copy hit-target cache for the current scratchpad panel and scroll.
refresh_scratchpad_copy_targets :: proc(
    runtime: ^app_core.Dynview_System,
    layout: Copy_Hit_Target_Layout) {

    if !runtime^.enabled {
        runtime^.compile_cache.copy_hit_targets = nil
        runtime^.compile_cache.copy_hit_target_count = 0
        return
    }

    status := rebuild_copy_hit_targets(runtime, layout)
    if status != dyncore.DYNVIEW_STATUS_OK {
        runtime^.compile_cache.last_error_code = status
    }
}
