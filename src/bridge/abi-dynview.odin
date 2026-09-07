package bridge

import "../core"
import dynparse "../dynview/parse"

import "base:runtime"
import "core:log"
import rl "vendor:raylib"

Dynview_Inline_Target :: struct {
    runtime: ^core.Dynview_System,
    buffer:  ^core.Dynview_Command_Buffer,
    status:  i32,
}

Dynview_Math_Import_Checkpoint :: struct {
    text_bytes_len: int,
    command_count: int,
    math_program_count: int,
    math_command_count: int,
    math_table_descriptor_count: int,
    document_text_count: int,
    document_count: int,
    document_block_count: int,
    document_inline_count: int,
}

//   Classify one TeX source using the native grammar authority.
@(export)
dynview_tex_source_mode :: proc "c" (source: cstring) -> i32 {
    if source == nil {
        return BRIDGE_STATUS_INVALID_ARGUMENT
    }
    context = runtime.default_context()
    return i32(dynparse.tex_classify_source_mode(string(source)))
}

//   Lazily prepare the request-owned view candidate for structured emission.
@(export)
begin_view_update :: proc "c" (state: ^core.Euclid_General_State) -> i32 {
    if state == nil {
        return BRIDGE_STATUS_ILLEGAL_STATE
    }
    context = state^.saved_context
    if state^.julia_runtime_service == nil || state^.view_update_candidate == nil {
        log.warnf("begin_view_update_without_candidate service=%v candidate=%v",
            state^.julia_runtime_service != nil, state^.view_update_candidate != nil)
        return BRIDGE_STATUS_ILLEGAL_STATE
    }
    slot := state^.view_update_candidate
    if slot^.state != .Reserved {
        log.warnf("begin_view_update_invalid_candidate state=%d", slot^.state)
        return BRIDGE_STATUS_ILLEGAL_STATE
    }
    service := state^.julia_runtime_service
    service^.view_snapshot_generation += 1
    slot^.state = .Pending
    slot^.generation = service^.view_snapshot_generation
    slot^.runtime_generation = service^.runtime_generation
    slot^.scratchpad_request_id =
        service^.worker_scratchpad_completed_request_id
    slot^.scratchpad_runtime_generation =
        service^.worker_scratchpad_completed_runtime_generation
    slot^.host_state = state
    reset_view_snapshot_staging(service^.dynview_staging)
    state^.dynview_emit_target = service^.dynview_staging
    return BRIDGE_STATUS_OK
}

//   Copy fallback text into the active request-owned candidate.
@(export)
set_view_text :: proc "c" (
    state: ^core.Euclid_General_State, text: cstring) -> i32 {

    if state == nil || text == nil || state^.view_update_candidate == nil {
        return BRIDGE_STATUS_INVALID_ARGUMENT
    }
    context = state^.saved_context
    slot := state^.view_update_candidate
    if slot^.state != .Pending {
        return BRIDGE_STATUS_ILLEGAL_STATE
    }
    payload := string(text)
    payload_count := min(len(payload), VIEW_SNAPSHOT_TEXT_CAPACITY)
    status := core.bounded_byte_builder_append(
        &slot^.fallback_text_builder, transmute([]u8)payload[:payload_count])
    return status == .Ok ? BRIDGE_STATUS_OK : BRIDGE_STATUS_OUT_OF_CAPACITY
}

//   Seal structured and fallback payloads without publishing them independently.
@(export)
commit_view_update :: proc "c" (state: ^core.Euclid_General_State) -> i32 {
    if state == nil || state^.julia_runtime_service == nil ||
        state^.view_update_candidate == nil {
        return BRIDGE_STATUS_ILLEGAL_STATE
    }
    context = state^.saved_context
    slot := state^.view_update_candidate
    if slot^.state != .Pending || slot^.candidate_committed {
        return BRIDGE_STATUS_ILLEGAL_STATE
    }
    staging := state^.julia_runtime_service^.dynview_staging
    if !build_generated_view_snapshot_payloads(slot, staging, "") {
        return BRIDGE_STATUS_OUT_OF_CAPACITY
    }
    if !view_snapshot_is_valid(slot) {
        return BRIDGE_STATUS_ILLEGAL_STATE
    }
    slot^.candidate_committed = true
    service := state^.julia_runtime_service
    if slot^.scratchpad_request_id != 0 &&
        slot^.scratchpad_request_id ==
            service^.worker_scratchpad_completed_request_id {
        service^.worker_scratchpad_completed_request_id = 0
        service^.worker_scratchpad_completed_runtime_generation = 0
    }
    state^.dynview_emit_target = nil
    return BRIDGE_STATUS_OK
}

//   Publish an explicit empty candidate through the current request transaction.
@(export)
clear_view :: proc "c" (state: ^core.Euclid_General_State) -> i32 {
    status := begin_view_update(state)
    if status != BRIDGE_STATUS_OK {
        return status
    }
    status = set_view_text(state, "")
    if status != BRIDGE_STATUS_OK {
        return status
    }
    return commit_view_update(state)
}

//   Reset the dynview command stream for the current frame.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//
// Returns:
//   - BRIDGE_STATUS_OK when the stream is reset.
//   - BRIDGE_STATUS_INVALID_ARGUMENT when state is nil.
@(export)
dynview_reset_stream :: proc "c" (state: ^core.Euclid_General_State) -> i32 {
    context = state^.saved_context
    runtime: ^core.Dynview_System
    status := dynview_require_runtime(state, &runtime)
    if status != BRIDGE_STATUS_OK {
        return status
    }
    if runtime == nil || !runtime^.enabled {
        return BRIDGE_STATUS_OK
    }

    runtime^.command_buffer.command_count = 0
    runtime^.command_buffer.text_bytes_len = 0
    runtime^.command_buffer.has_stream_error = false
    runtime^.command_buffer.stream_open_block = false
    runtime^.command_buffer.stream_open_block_id = -1
    runtime^.compile_cache.math_program_count = 0
    runtime^.compile_cache.math_table_descriptor_count = 0
    runtime^.compile_cache.math_command_count = 0
    runtime^.compile_cache.math_node_count = 0
    runtime^.command_buffer.revision += 1
    runtime^.compile_cache.last_error_code = BRIDGE_STATUS_OK
    runtime^.compile_cache.is_valid = false
    return BRIDGE_STATUS_OK
}

//   Start a new dynview block.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - block_kind: Style id assigned to the new block.
//   - block_id: Block identifier used for pairing with the matching end command.
//
// Returns:
//   - BRIDGE_STATUS_OK when the block starts successfully.
//   - BRIDGE_STATUS_ILLEGAL_STATE when a block is already open.
@(export)
dynview_begin_block :: proc "c" (
    state: ^core.Euclid_General_State, block_kind, block_id: i32) -> i32 {

    context = state^.saved_context
    runtime: ^core.Dynview_System
    status := dynview_require_runtime(state, &runtime)
    if status != BRIDGE_STATUS_OK {
        return status
    }
    if runtime == nil || !runtime^.enabled {
        return BRIDGE_STATUS_OK
    }

    buffer: ^core.Dynview_Command_Buffer
    status = dynview_require_buffer(runtime, &buffer, false)
    if status != BRIDGE_STATUS_OK {
        return status
    }
    if buffer^.stream_open_block {
        return dynview_fail(runtime, BRIDGE_STATUS_ILLEGAL_STATE)
    }

    status = dynview_push_command(runtime, core.Dynview_Command{
        kind = .Begin_Block,
        block_id = block_id,
        style_id = block_kind,
    })
    if status != BRIDGE_STATUS_OK {
        return status
    }

    buffer^.stream_open_block = true
    buffer^.stream_open_block_id = block_id
    return BRIDGE_STATUS_OK
}

//   Append one visible text run to the current dynview block.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - text: UTF-8 text payload to append to the current block.
//   - style_id: Style id assigned to the emitted text run.
//
// Returns:
//   - BRIDGE_STATUS_OK when the command is emitted.
//   - BRIDGE_STATUS_ILLEGAL_STATE when no block is open.
@(export)
dynview_text_run :: proc "c" (
    state: ^core.Euclid_General_State, text: cstring, style_id: i32) -> i32 {

    context = state^.saved_context
    runtime: ^core.Dynview_System
    status := dynview_require_runtime(state, &runtime)
    if status != BRIDGE_STATUS_OK {
        return status
    }
    if runtime == nil || !runtime^.enabled {
        return BRIDGE_STATUS_OK
    }

    buffer: ^core.Dynview_Command_Buffer
    status = dynview_require_buffer(runtime, &buffer, true)
    if status != BRIDGE_STATUS_OK {
        return status
    }

    offset := 0
    count := 0
    status = dynview_append_text_payload(runtime, string(text), &offset, &count)
    if status != BRIDGE_STATUS_OK {
        return status
    }

    return dynview_push_command(runtime, core.Dynview_Command{
        kind = .Text_Run,
        block_id = buffer^.stream_open_block_id,
        style_id = style_id,
        text_offset = offset,
        text_len = count,
    })
}

//   Append one visible text run with an explicit brush color override.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - text: UTF-8 text payload to append to the current block.
//   - style_id: Style id assigned to the emitted text run.
//   - brush_color: Brush color override for the text run.
//
// Returns:
//   - BRIDGE_STATUS_OK when the command is emitted.
//   - BRIDGE_STATUS_ILLEGAL_STATE when no block is open.
@(export)
dynview_text_run_brush :: proc "c" (
    state: ^core.Euclid_General_State,
    text: cstring,
    style_id: i32,
    brush_color: Bridge_Color) -> i32 {

    context = state^.saved_context
    runtime: ^core.Dynview_System
    status := dynview_require_runtime(state, &runtime)
    if status != BRIDGE_STATUS_OK {
        return status
    }
    if runtime == nil || !runtime^.enabled {
        return BRIDGE_STATUS_OK
    }

    buffer: ^core.Dynview_Command_Buffer
    status = dynview_require_buffer(runtime, &buffer, true)
    if status != BRIDGE_STATUS_OK {
        return status
    }

    offset := 0
    count := 0
    status = dynview_append_text_payload(runtime, string(text), &offset, &count)
    if status != BRIDGE_STATUS_OK {
        return status
    }

    return dynview_push_command(runtime, core.Dynview_Command{
        kind = .Text_Run,
        block_id = buffer^.stream_open_block_id,
        style_id = style_id,
        text_offset = offset,
        text_len = count,
        has_brush_color = true,
        brush_color =
            rl.Color{brush_color.r, brush_color.g, brush_color.b, brush_color.a},
    })
}

//   Append one visible math-glyph run to the current dynview block.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - text: Glyph payload to append to the current block.
//   - style_id: Style id assigned to the emitted math-glyph run.
//
// Returns:
//   - BRIDGE_STATUS_OK when the command is emitted.
//   - BRIDGE_STATUS_ILLEGAL_STATE when no block is open.
@(export)
dynview_math_glyph_run :: proc "c" (
    state: ^core.Euclid_General_State, text: cstring, style_id: i32) -> i32 {

    context = state^.saved_context
    runtime: ^core.Dynview_System
    status := dynview_require_runtime(state, &runtime)
    if status != BRIDGE_STATUS_OK {
        return status
    }
    if runtime == nil || !runtime^.enabled {
        return BRIDGE_STATUS_OK
    }

    buffer: ^core.Dynview_Command_Buffer
    status = dynview_require_buffer(runtime, &buffer, true)
    if status != BRIDGE_STATUS_OK {
        return status
    }

    offset := 0
    count := 0
    status = dynview_append_text_payload(runtime, string(text), &offset, &count)
    if status != BRIDGE_STATUS_OK {
        return status
    }

    return dynview_push_command(runtime, core.Dynview_Command{
        kind = .Math_Glyph_Run,
        block_id = buffer^.stream_open_block_id,
        style_id = style_id,
        text_offset = offset,
        text_len = count,
    })
}

//   Parse, intern, and append one whole inline math block from raw TeX source.
@(export)
dynview_math_block :: proc "c" (
    state: ^core.Euclid_General_State,
    request: Bridge_Dynview_Math_Request) -> i32 {
    if state == nil {
        return BRIDGE_STATUS_INVALID_ARGUMENT
    }
    context = state^.saved_context
    return dynview_native_math_source(state, request)
}

//   Build one complete mixed-TeX stream while retaining fallback on import failure.
@(export)
dynview_tex_document :: proc "c" (
    state: ^core.Euclid_General_State,
    request: Bridge_Dynview_Document_Request) -> i32 {
    if state == nil {
        return BRIDGE_STATUS_INVALID_ARGUMENT
    }
    context = state^.saved_context
    return dynview_native_document_source(state, request)
}

//   Capture mutable counters touched by one math-block import transaction.
dynview_math_import_checkpoint :: #force_inline proc(
    runtime: ^core.Dynview_System) -> Dynview_Math_Import_Checkpoint {

    return {
        runtime^.command_buffer.text_bytes_len,
        runtime^.command_buffer.command_count,
        runtime^.compile_cache.math_program_count,
        runtime^.compile_cache.math_command_count,
        runtime^.compile_cache.math_table_descriptor_count,
        runtime^.compile_cache.document_text_count,
        runtime^.compile_cache.document_count,
        runtime^.compile_cache.document_block_count,
        runtime^.compile_cache.document_inline_count,
    }
}

//   Restore mutable counters after a rejected math-block import.
dynview_math_import_rollback :: #force_inline proc(
    runtime: ^core.Dynview_System,
    checkpoint: Dynview_Math_Import_Checkpoint) {

    runtime^.command_buffer.text_bytes_len = checkpoint.text_bytes_len
    runtime^.command_buffer.command_count = checkpoint.command_count
    runtime^.compile_cache.math_program_count = checkpoint.math_program_count
    runtime^.compile_cache.math_command_count = checkpoint.math_command_count
    runtime^.compile_cache.math_table_descriptor_count =
        checkpoint.math_table_descriptor_count
    runtime^.compile_cache.document_text_count = checkpoint.document_text_count
    runtime^.compile_cache.document_count = checkpoint.document_count
    runtime^.compile_cache.document_block_count = checkpoint.document_block_count
    runtime^.compile_cache.document_inline_count = checkpoint.document_inline_count
}

//   Resolve the runtime and command buffer for an inline atom emission.
//
// Returns:
//   - Target with status set on failure; a nil buffer means the runtime is
//     disabled and the caller should return BRIDGE_STATUS_OK.
dynview_inline_atom_target :: proc(
    state: ^core.Euclid_General_State) -> Dynview_Inline_Target {

    target := Dynview_Inline_Target{status = BRIDGE_STATUS_OK}
    status := dynview_require_runtime(state, &target.runtime)
    if status != BRIDGE_STATUS_OK {
        target.status = status
        return target
    }
    if target.runtime == nil || !target.runtime^.enabled {
        return target
    }

    status = dynview_require_buffer(target.runtime, &target.buffer, true)
    if status != BRIDGE_STATUS_OK {
        target.status = status
    }
    return target
}

//   Append one non-rendering copyable payload segment to the current dynview block.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - copy_text: Plain-text payload to copy into the dynview stream.
//
// Returns:
//   - BRIDGE_STATUS_OK when the command is emitted.
//   - BRIDGE_STATUS_ILLEGAL_STATE when no block is open.
@(export)
dynview_copyable_text_run :: proc "c" (
    state: ^core.Euclid_General_State,
    copy_text: cstring) -> i32 {

    context = state^.saved_context
    runtime: ^core.Dynview_System
    status := dynview_require_runtime(state, &runtime)
    if status != BRIDGE_STATUS_OK {
        return status
    }
    if runtime == nil || !runtime^.enabled {
        return BRIDGE_STATUS_OK
    }

    buffer: ^core.Dynview_Command_Buffer
    status = dynview_require_buffer(runtime, &buffer, true)
    if status != BRIDGE_STATUS_OK {
        return status
    }

    copy_text_value := ""
    if copy_text != nil {
        copy_text_value = string(copy_text)
    }

    offset := 0
    count := 0
    status = dynview_append_text_payload(runtime, copy_text_value, &offset, &count)
    if status != BRIDGE_STATUS_OK {
        return status
    }

    return dynview_push_command(runtime, core.Dynview_Command{
        kind = .Copyable_Text_Run,
        block_id = buffer^.stream_open_block_id,
        copy_text_offset = offset,
        copy_text_len = count,
    })
}

//   Append one inline line atom to the current dynview block.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - length: Line length in world units.
//   - thickness: Line stroke thickness.
//   - style_id: Style id assigned to the emitted atom.
//
// Returns:
//   - BRIDGE_STATUS_OK when the command is emitted.
//   - BRIDGE_STATUS_INVALID_ARGUMENT for non-positive dimensions.
@(export)
dynview_inline_line :: proc "c" (
    state: ^core.Euclid_General_State,
    length, thickness: f32,
    style_id: i32) -> i32 {

    context = state^.saved_context
    runtime: ^core.Dynview_System
    status := dynview_require_runtime(state, &runtime)
    if status != BRIDGE_STATUS_OK {
        return status
    }
    if runtime == nil || !runtime^.enabled {
        return BRIDGE_STATUS_OK
    }

    buffer: ^core.Dynview_Command_Buffer
    status = dynview_require_buffer(runtime, &buffer, true)
    if status != BRIDGE_STATUS_OK {
        return status
    }

    if length <= 0 || thickness <= 0 {
        return dynview_fail(runtime, BRIDGE_STATUS_INVALID_ARGUMENT)
    }

    return dynview_push_command(runtime, core.Dynview_Command{
        kind = .Inline_Line,
        block_id = buffer^.stream_open_block_id,
        style_id = style_id,
        inline_atom_dimension = length,
        inline_atom_stroke = thickness,
    })
}

//   Append one inline box atom to the current dynview block.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - width: Box width in world units.
//   - height: Box height in world units.
//   - stroke: Box outline stroke thickness.
//   - style_id: Style id assigned to the emitted atom.
//
// Returns:
//   - BRIDGE_STATUS_OK when the command is emitted.
//   - BRIDGE_STATUS_INVALID_ARGUMENT for non-positive dimensions.
@(export)
dynview_inline_box :: proc "c" (
    state: ^core.Euclid_General_State,
    width, height, stroke: f32,
    style_id: i32) -> i32 {

    context = state^.saved_context
    runtime: ^core.Dynview_System
    status := dynview_require_runtime(state, &runtime)
    if status != BRIDGE_STATUS_OK {
        return status
    }
    if runtime == nil || !runtime^.enabled {
        return BRIDGE_STATUS_OK
    }

    buffer: ^core.Dynview_Command_Buffer
    status = dynview_require_buffer(runtime, &buffer, true)
    if status != BRIDGE_STATUS_OK {
        return status
    }

    if width <= 0 || height <= 0 || stroke <= 0 {
        return dynview_fail(runtime, BRIDGE_STATUS_INVALID_ARGUMENT)
    }

    return dynview_push_command(runtime, core.Dynview_Command{
        kind = .Inline_Box,
        block_id = buffer^.stream_open_block_id,
        style_id = style_id,
        inline_atom_dimension = width,
        inline_atom_stroke = stroke,
        inline_box_height = height,
    })
}

//   Append one inline circle atom to the current dynview block.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - radius: Circle radius in world units.
//   - stroke: Circle outline stroke thickness.
//   - style_id: Style id assigned to the emitted atom.
//
// Returns:
//   - BRIDGE_STATUS_OK when the command is emitted.
//   - BRIDGE_STATUS_INVALID_ARGUMENT for non-positive dimensions.
@(export)
dynview_inline_circle :: proc "c" (
    state: ^core.Euclid_General_State,
    radius, stroke: f32,
    style_id: i32) -> i32 {

    context = state^.saved_context
    runtime: ^core.Dynview_System
    status := dynview_require_runtime(state, &runtime)
    if status != BRIDGE_STATUS_OK {
        return status
    }
    if runtime == nil || !runtime^.enabled {
        return BRIDGE_STATUS_OK
    }

    buffer: ^core.Dynview_Command_Buffer
    status = dynview_require_buffer(runtime, &buffer, true)
    if status != BRIDGE_STATUS_OK {
        return status
    }

    if radius <= 0 || stroke <= 0 {
        return dynview_fail(runtime, BRIDGE_STATUS_INVALID_ARGUMENT)
    }

    return dynview_push_command(runtime, core.Dynview_Command{
        kind = .Inline_Circle,
        block_id = buffer^.stream_open_block_id,
        style_id = style_id,
        inline_atom_dimension = radius,
        inline_atom_stroke = stroke,
    })
}

//   Append one inline line atom with an explicit brush color override.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - length: Line length in world units.
//   - thickness: Line stroke thickness.
//   - style_id: Style id assigned to the emitted atom.
//   - brush_color: Brush color override for the atom.
//
// Returns:
//   - BRIDGE_STATUS_OK when the command is emitted.
//   - BRIDGE_STATUS_INVALID_ARGUMENT for non-positive dimensions.
@(export)
dynview_inline_line_brush :: proc "c" (
    state: ^core.Euclid_General_State,
    length, thickness: f32,
    style_id: i32,
    brush_color: Bridge_Color) -> i32 {

    context = state^.saved_context
    runtime: ^core.Dynview_System
    status := dynview_require_runtime(state, &runtime)
    if status != BRIDGE_STATUS_OK {
        return status
    }
    if runtime == nil || !runtime^.enabled {
        return BRIDGE_STATUS_OK
    }

    buffer: ^core.Dynview_Command_Buffer
    status = dynview_require_buffer(runtime, &buffer, true)
    if status != BRIDGE_STATUS_OK {
        return status
    }

    if length <= 0 || thickness <= 0 {
        return dynview_fail(runtime, BRIDGE_STATUS_INVALID_ARGUMENT)
    }

    return dynview_push_command(runtime, core.Dynview_Command{
        kind = .Inline_Line,
        block_id = buffer^.stream_open_block_id,
        style_id = style_id,
        inline_atom_dimension = length,
        inline_atom_stroke = thickness,
        has_brush_color = true,
        brush_color =
            rl.Color{brush_color.r, brush_color.g, brush_color.b, brush_color.a},
    })
}

//   Append one inline box atom with an explicit brush color override.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - dims: Box width, height, and outline stroke thickness.
//   - style_id: Style id assigned to the emitted atom.
//   - brush_color: Brush color override for the atom.
//
// Returns:
//   - BRIDGE_STATUS_OK when the command is emitted.
//   - BRIDGE_STATUS_INVALID_ARGUMENT for non-positive dimensions.
@(export)
dynview_inline_box_brush :: proc "c" (
    state: ^core.Euclid_General_State,
    dims: core.Bridge_Inline_Box_Dims,
    style_id: i32,
    brush_color: Bridge_Color) -> i32 {

    context = state^.saved_context
    runtime: ^core.Dynview_System
    status := dynview_require_runtime(state, &runtime)
    if status != BRIDGE_STATUS_OK {
        return status
    }
    if runtime == nil || !runtime^.enabled {
        return BRIDGE_STATUS_OK
    }

    buffer: ^core.Dynview_Command_Buffer
    status = dynview_require_buffer(runtime, &buffer, true)
    if status != BRIDGE_STATUS_OK {
        return status
    }

    if dims.width <= 0 || dims.height <= 0 || dims.stroke <= 0 {
        return dynview_fail(runtime, BRIDGE_STATUS_INVALID_ARGUMENT)
    }

    return dynview_push_command(runtime, core.Dynview_Command{
        kind = .Inline_Box,
        block_id = buffer^.stream_open_block_id,
        style_id = style_id,
        inline_atom_dimension = dims.width,
        inline_atom_stroke = dims.stroke,
        inline_box_height = dims.height,
        has_brush_color = true,
        brush_color =
            rl.Color{brush_color.r, brush_color.g, brush_color.b, brush_color.a},
    })
}

//   Append one inline circle atom with an explicit brush color override.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - radius: Circle radius in world units.
//   - stroke: Circle outline stroke thickness.
//   - style_id: Style id assigned to the emitted atom.
//   - brush_color: Brush color override for the atom.
//
// Returns:
//   - BRIDGE_STATUS_OK when the command is emitted.
//   - BRIDGE_STATUS_INVALID_ARGUMENT for non-positive dimensions.
@(export)
dynview_inline_circle_brush :: proc "c" (
    state: ^core.Euclid_General_State,
    radius, stroke: f32,
    style_id: i32,
    brush_color: Bridge_Color) -> i32 {

    context = state^.saved_context
    runtime: ^core.Dynview_System
    status := dynview_require_runtime(state, &runtime)
    if status != BRIDGE_STATUS_OK {
        return status
    }
    if runtime == nil || !runtime^.enabled {
        return BRIDGE_STATUS_OK
    }

    buffer: ^core.Dynview_Command_Buffer
    status = dynview_require_buffer(runtime, &buffer, true)
    if status != BRIDGE_STATUS_OK {
        return status
    }

    if radius <= 0 || stroke <= 0 {
        return dynview_fail(runtime, BRIDGE_STATUS_INVALID_ARGUMENT)
    }

    return dynview_push_command(runtime, core.Dynview_Command{
        kind = .Inline_Circle,
        block_id = buffer^.stream_open_block_id,
        style_id = style_id,
        inline_atom_dimension = radius,
        inline_atom_stroke = stroke,
        has_brush_color = true,
        brush_color =
            rl.Color{brush_color.r, brush_color.g, brush_color.b, brush_color.a},
    })
}

//   Append one filled inline box atom with an optional outline stroke.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - size: Box width and height in world units.
//   - style_id: Style id assigned to the emitted atom.
//   - fill_color: Fill color for the atom.
//   - outline_stroke: Optional outline stroke thickness.
//
// Returns:
//   - BRIDGE_STATUS_OK when the command is emitted.
//   - BRIDGE_STATUS_INVALID_ARGUMENT for non-positive dimensions.
@(export)
dynview_inline_filled_box :: proc "c" (
    state: ^core.Euclid_General_State,
    size: core.Bridge_Inline_Size,
    style_id: i32,
    fill_color: Bridge_Color,
    outline_stroke: f32) -> i32 {

    context = state^.saved_context
    runtime: ^core.Dynview_System
    status := dynview_require_runtime(state, &runtime)
    if status != BRIDGE_STATUS_OK {
        return status
    }
    if runtime == nil || !runtime^.enabled {
        return BRIDGE_STATUS_OK
    }

    buffer: ^core.Dynview_Command_Buffer
    status = dynview_require_buffer(runtime, &buffer, true)
    if status != BRIDGE_STATUS_OK {
        return status
    }

    if size.width <= 0 || size.height <= 0 || outline_stroke < 0 {
        return dynview_fail(runtime, BRIDGE_STATUS_INVALID_ARGUMENT)
    }

    return dynview_push_command(runtime, core.Dynview_Command{
        kind = .Inline_Filled_Box,
        block_id = buffer^.stream_open_block_id,
        style_id = style_id,
        inline_atom_dimension = size.width,
        inline_box_height = size.height,
        has_brush_color = true,
        brush_color = rl.Color{fill_color.r, fill_color.g, fill_color.b, fill_color.a},
        inline_outline_stroke = outline_stroke,
    })
}

//   Append one filled inline circle atom with an optional outline stroke.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - radius: Circle radius in world units.
//   - style_id: Style id assigned to the emitted atom.
//   - fill_color: Fill color for the atom.
//   - outline_stroke: Optional outline stroke thickness.
//
// Returns:
//   - BRIDGE_STATUS_OK when the command is emitted.
//   - BRIDGE_STATUS_INVALID_ARGUMENT for non-positive dimensions.
@(export)
dynview_inline_filled_circle :: proc "c" (
    state: ^core.Euclid_General_State,
    radius: f32,
    style_id: i32,
    fill_color: Bridge_Color,
    outline_stroke: f32) -> i32 {

    context = state^.saved_context
    runtime: ^core.Dynview_System
    status := dynview_require_runtime(state, &runtime)
    if status != BRIDGE_STATUS_OK {
        return status
    }
    if runtime == nil || !runtime^.enabled {
        return BRIDGE_STATUS_OK
    }

    buffer: ^core.Dynview_Command_Buffer
    status = dynview_require_buffer(runtime, &buffer, true)
    if status != BRIDGE_STATUS_OK {
        return status
    }

    if radius <= 0 || outline_stroke < 0 {
        return dynview_fail(runtime, BRIDGE_STATUS_INVALID_ARGUMENT)
    }

    return dynview_push_command(runtime, core.Dynview_Command{
        kind = .Inline_Filled_Circle,
        block_id = buffer^.stream_open_block_id,
        style_id = style_id,
        inline_atom_dimension = radius,
        has_brush_color = true,
        brush_color = rl.Color{fill_color.r, fill_color.g, fill_color.b, fill_color.a},
        inline_outline_stroke = outline_stroke,
    })
}

//   Append one inline perpendicular atom with two independently colored legs.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - dims: Top-bar length, stem height, and stroke thickness.
//   - style_id: Style id assigned to the emitted atom.
//   - colors: Top and stem colors for the atom.
//
// Returns:
//   - BRIDGE_STATUS_OK when the command is emitted.
//   - BRIDGE_STATUS_INVALID_ARGUMENT for non-positive dimensions.
@(export)
dynview_inline_perpendicular :: proc "c" (
    state: ^core.Euclid_General_State,
    dims: core.Bridge_Inline_Perpendicular_Dims,
    style_id: i32,
    colors: core.Bridge_Perpendicular_Colors) -> i32 {

    context = state^.saved_context
    runtime: ^core.Dynview_System
    status := dynview_require_runtime(state, &runtime)
    if status != BRIDGE_STATUS_OK {
        return status
    }
    if runtime == nil || !runtime^.enabled {
        return BRIDGE_STATUS_OK
    }

    buffer: ^core.Dynview_Command_Buffer
    status = dynview_require_buffer(runtime, &buffer, true)
    if status != BRIDGE_STATUS_OK {
        return status
    }

    if dims.length <= 0 || dims.stem_height <= 0 || dims.stroke <= 0 {
        return dynview_fail(runtime, BRIDGE_STATUS_INVALID_ARGUMENT)
    }

    return dynview_push_command(runtime, core.Dynview_Command{
        kind = .Inline_Perpendicular,
        block_id = buffer^.stream_open_block_id,
        style_id = style_id,
        inline_atom_dimension = dims.length,
        inline_box_height = dims.stem_height,
        inline_atom_stroke = dims.stroke,
        brush_color =
            rl.Color{colors.top.r, colors.top.g, colors.top.b, colors.top.a},
        shape_edge_color_1 =
            rl.Color{colors.stem.r, colors.stem.g, colors.stem.b, colors.stem.a},
    })
}

//   Append one inline triangle atom with optional fill and three edge colors.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - dims: Triangle width, height, and stroke thickness.
//   - style_id: Style id assigned to the emitted atom.
//   - filled: Whether the triangle is filled.
//   - colors: Fill and edge colors for the atom.
//
// Returns:
//   - BRIDGE_STATUS_OK when the command is emitted.
//   - BRIDGE_STATUS_INVALID_ARGUMENT for non-positive dimensions.
@(export)
dynview_inline_triangle :: proc "c" (
    state: ^core.Euclid_General_State,
    dims: core.Bridge_Inline_Box_Dims,
    style_id: i32,
    filled: bool,
    colors: Bridge_Triangle_Colors) -> i32 {

    context = state^.saved_context
    target := dynview_inline_atom_target(state)
    if target.status != BRIDGE_STATUS_OK || target.buffer == nil {
        return target.status
    }

    if dims.width <= 0 || dims.height <= 0 || dims.stroke <= 0 {
        return dynview_fail(target.runtime, BRIDGE_STATUS_INVALID_ARGUMENT)
    }

    return dynview_push_command(target.runtime, core.Dynview_Command{
        kind = .Inline_Triangle,
        block_id = target.buffer^.stream_open_block_id,
        style_id = style_id,
        inline_atom_dimension = dims.width,
        inline_box_height = dims.height,
        inline_atom_stroke = dims.stroke,
        shape_is_filled = filled,
        has_brush_color = filled,
        brush_color =
            rl.Color{colors.fill.r, colors.fill.g, colors.fill.b, colors.fill.a},
        shape_edge_color_1 =
            rl.Color{colors.edge1.r, colors.edge1.g, colors.edge1.b, colors.edge1.a},
        shape_edge_color_2 =
            rl.Color{colors.edge2.r, colors.edge2.g, colors.edge2.b, colors.edge2.a},
        shape_edge_color_3 =
            rl.Color{colors.edge3.r, colors.edge3.g, colors.edge3.b, colors.edge3.a},
    })
}

//   Append one inline box atom with independently colored edges.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - dims: Box width, height, and stroke thickness.
//   - style_id: Style id assigned to the emitted atom.
//   - colors: Independent edge colors for the atom.
//
// Returns:
//   - BRIDGE_STATUS_OK when the command is emitted.
//   - BRIDGE_STATUS_INVALID_ARGUMENT for non-positive dimensions.
@(export)
dynview_inline_box_edges :: proc "c" (
    state: ^core.Euclid_General_State,
    dims: core.Bridge_Inline_Box_Dims,
    style_id: i32,
    colors: Bridge_Box_Edge_Colors) -> i32 {

    context = state^.saved_context
    target := dynview_inline_atom_target(state)
    if target.status != BRIDGE_STATUS_OK || target.buffer == nil {
        return target.status
    }

    if dims.width <= 0 || dims.height <= 0 || dims.stroke <= 0 {
        return dynview_fail(target.runtime, BRIDGE_STATUS_INVALID_ARGUMENT)
    }

    return dynview_push_command(target.runtime, core.Dynview_Command{
        kind = .Inline_Box,
        block_id = target.buffer^.stream_open_block_id,
        style_id = style_id,
        inline_atom_dimension = dims.width,
        inline_atom_stroke = dims.stroke,
        inline_box_height = dims.height,
        shape_edge_color_1 =
            rl.Color{colors.edge1.r, colors.edge1.g, colors.edge1.b, colors.edge1.a},
        shape_edge_color_2 =
            rl.Color{colors.edge2.r, colors.edge2.g, colors.edge2.b, colors.edge2.a},
        shape_edge_color_3 =
            rl.Color{colors.edge3.r, colors.edge3.g, colors.edge3.b, colors.edge3.a},
        shape_edge_color_4 =
            rl.Color{colors.edge4.r, colors.edge4.g, colors.edge4.b, colors.edge4.a},
    })
}

//   Append one inline pentagon atom with optional fill and five edge colors.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - dims: Pentagon width, height, and stroke thickness.
//   - style_id: Style id assigned to the emitted atom.
//   - filled: Whether the pentagon is filled.
//   - colors: Fill and edge colors for the atom.
//
// Returns:
//   - BRIDGE_STATUS_OK when the command is emitted.
//   - BRIDGE_STATUS_INVALID_ARGUMENT for non-positive dimensions.
@(export)
dynview_inline_pentagon :: proc "c" (
    state: ^core.Euclid_General_State,
    dims: core.Bridge_Inline_Box_Dims,
    style_id: i32,
    filled: bool,
    colors: Bridge_Pentagon_Colors) -> i32 {

    context = state^.saved_context
    target := dynview_inline_atom_target(state)
    if target.status != BRIDGE_STATUS_OK || target.buffer == nil {
        return target.status
    }

    if dims.width <= 0 || dims.height <= 0 || dims.stroke <= 0 {
        return dynview_fail(target.runtime, BRIDGE_STATUS_INVALID_ARGUMENT)
    }

    return dynview_push_command(target.runtime, core.Dynview_Command{
        kind = .Inline_Pentagon,
        block_id = target.buffer^.stream_open_block_id,
        style_id = style_id,
        inline_atom_dimension = dims.width,
        inline_box_height = dims.height,
        inline_atom_stroke = dims.stroke,
        shape_is_filled = filled,
        has_brush_color = filled,
        brush_color =
            rl.Color{colors.fill.r, colors.fill.g, colors.fill.b, colors.fill.a},
        shape_edge_color_1 =
            rl.Color{colors.edge1.r, colors.edge1.g, colors.edge1.b, colors.edge1.a},
        shape_edge_color_2 =
            rl.Color{colors.edge2.r, colors.edge2.g, colors.edge2.b, colors.edge2.a},
        shape_edge_color_3 =
            rl.Color{colors.edge3.r, colors.edge3.g, colors.edge3.b, colors.edge3.a},
        shape_edge_color_4 =
            rl.Color{colors.edge4.r, colors.edge4.g, colors.edge4.b, colors.edge4.a},
        shape_edge_color_5 =
            rl.Color{colors.edge5.r, colors.edge5.g, colors.edge5.b, colors.edge5.a},
    })
}

//   Append one filled inline pie-section atom with an optional outline stroke.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - geometry: Radius, sweep angles, and outline stroke for the section.
//   - style_id: Style id assigned to the emitted atom.
//   - filled: Whether the section is filled.
//   - colors: Fill and arc colors for the atom.
//
// Returns:
//   - BRIDGE_STATUS_OK when the command is emitted.
//   - BRIDGE_STATUS_INVALID_ARGUMENT for non-positive dimensions.
@(export)
dynview_inline_pie_section :: proc "c" (
    state: ^core.Euclid_General_State,
    geometry: core.Bridge_Pie_Section_Geometry,
    style_id: i32,
    filled: bool,
    colors: Bridge_Pie_Colors) -> i32 {

    context = state^.saved_context
    target := dynview_inline_atom_target(state)
    if target.status != BRIDGE_STATUS_OK || target.buffer == nil {
        return target.status
    }

    if geometry.radius <= 0 || geometry.outline_stroke < 0 {
        return dynview_fail(target.runtime, BRIDGE_STATUS_INVALID_ARGUMENT)
    }

    return dynview_push_command(target.runtime, core.Dynview_Command{
        kind = .Inline_Pie_Section,
        block_id = target.buffer^.stream_open_block_id,
        style_id = style_id,
        inline_atom_dimension = geometry.radius,
        has_brush_color = true,
        brush_color =
            rl.Color{colors.fill.r, colors.fill.g, colors.fill.b, colors.fill.a},
        inline_outline_stroke = geometry.outline_stroke,
        pie_start_angle_degrees = geometry.start_angle_degrees,
        pie_end_angle_degrees = geometry.end_angle_degrees,
        pie_is_filled = filled,
        has_outline_color = true,
        outline_color =
            rl.Color{colors.arc.r, colors.arc.g, colors.arc.b, colors.arc.a},
    })
}

//   Insert an explicit line break in the current dynview block.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//
// Returns:
//   - BRIDGE_STATUS_OK when the command is emitted.
//   - BRIDGE_STATUS_ILLEGAL_STATE when no block is open.
@(export)
dynview_line_break :: proc "c" (state: ^core.Euclid_General_State) -> i32 {
    context = state^.saved_context
    runtime: ^core.Dynview_System
    status := dynview_require_runtime(state, &runtime)
    if status != BRIDGE_STATUS_OK {
        return status
    }
    if runtime == nil || !runtime^.enabled {
        return BRIDGE_STATUS_OK
    }

    buffer: ^core.Dynview_Command_Buffer
    status = dynview_require_buffer(runtime, &buffer, true)
    if status != BRIDGE_STATUS_OK {
        return status
    }

    return dynview_push_command(runtime, core.Dynview_Command{
        kind = .Line_Break,
        block_id = buffer^.stream_open_block_id,
    })
}

//   End the current dynview block.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//
// Returns:
//   - BRIDGE_STATUS_OK when the block closes successfully.
//   - BRIDGE_STATUS_ILLEGAL_STATE when no block is open.
@(export)
dynview_end_block :: proc "c" (state: ^core.Euclid_General_State) -> i32 {
    context = state^.saved_context
    runtime: ^core.Dynview_System
    status := dynview_require_runtime(state, &runtime)
    if status != BRIDGE_STATUS_OK {
        return status
    }
    if runtime == nil || !runtime^.enabled {
        return BRIDGE_STATUS_OK
    }

    buffer: ^core.Dynview_Command_Buffer
    status = dynview_require_buffer(runtime, &buffer, true)
    if status != BRIDGE_STATUS_OK {
        return status
    }

    status = dynview_push_command(runtime, core.Dynview_Command{
        kind = .End_Block,
        block_id = buffer^.stream_open_block_id,
    })
    if status != BRIDGE_STATUS_OK {
        return status
    }

    buffer^.stream_open_block = false
    buffer^.stream_open_block_id = -1
    return BRIDGE_STATUS_OK
}

