package bridge

import "../core"

//   Convert a bridge decoration code to its native label decoration.
label_decoration_kind_from_i32 :: #force_inline proc(
    kind: i32) -> core.Shapes_Label_Decoration_Kind {
    switch kind {
    case BRIDGE_LABEL_DECORATION_PRIME:
        return .Prime
    case BRIDGE_LABEL_DECORATION_DOUBLEPRIME:
        return .Double_Prime
    case BRIDGE_LABEL_DECORATION_TRIPLEPRIME:
        return .Triple_Prime
    case BRIDGE_LABEL_DECORATION_HAT:
        return .Hat
    case BRIDGE_LABEL_DECORATION_BAR:
        return .Bar
    }
    return .None
}

//   Mark the current Dynview stream and compile cache invalid.
dynview_fail :: #force_inline proc(
    runtime: ^core.Dynview_System, code: i32) -> i32 {
    runtime^.command_buffer.has_stream_error = true
    if runtime^.compile_cache.last_error_code == 0 {
        runtime^.compile_cache.last_error_code = code
    }
    runtime^.compile_cache.is_valid = false
    return code
}

//   Append one command to bounded Dynview staging.
dynview_push_command :: #force_inline proc(
    runtime: ^core.Dynview_System,
    command: core.Dynview_Command) -> i32 {

    buffer := &runtime^.command_buffer
    if buffer^.command_count >= len(buffer^.commands) {
        return dynview_fail(runtime, BRIDGE_STATUS_OUT_OF_CAPACITY)
    }
    buffer^.commands[buffer^.command_count] = command
    buffer^.command_count += 1
    runtime^.compile_cache.is_valid = false
    return BRIDGE_STATUS_OK
}

//   Append text to bounded Dynview staging and return its span.
dynview_append_text_payload :: #force_inline proc(
    runtime: ^core.Dynview_System,
    text: string,
    offset_out, count_out: ^int) -> i32 {

    buffer := &runtime^.command_buffer
    text_len := len(text)
    if buffer^.text_bytes_len + text_len > len(buffer^.text_bytes) {
        return dynview_fail(runtime, BRIDGE_STATUS_OUT_OF_CAPACITY)
    }
    start := buffer^.text_bytes_len
    copy(buffer^.text_bytes[start:], transmute([]u8)text)
    buffer^.text_bytes_len += text_len
    offset_out^ = start
    count_out^ = text_len
    return BRIDGE_STATUS_OK
}

//   Return the active Dynview emission target for the current bridge state.
dynview_require_runtime :: proc(
    state: ^core.Euclid_General_State,
    runtime_out: ^^core.Dynview_System) -> i32 {

    if state == nil || runtime_out == nil {
        return BRIDGE_STATUS_INVALID_ARGUMENT
    }
    context = state^.saved_context
    runtime_out^ = state^.dynview_emit_target
    if runtime_out^ == nil {
        runtime_out^ = &state^.dynview
    }
    return BRIDGE_STATUS_OK
}

//   Return the active command buffer and optionally require an open block.
dynview_require_buffer :: proc(
    runtime: ^core.Dynview_System,
    buffer_out: ^^core.Dynview_Command_Buffer,
    require_open_block: bool) -> i32 {

    if runtime == nil || buffer_out == nil {
        return BRIDGE_STATUS_INVALID_ARGUMENT
    }
    if !runtime^.enabled {
        return BRIDGE_STATUS_OK
    }
    buffer_out^ = &runtime^.command_buffer
    if require_open_block && !buffer_out^^.stream_open_block {
        return dynview_fail(runtime, BRIDGE_STATUS_ILLEGAL_STATE)
    }
    return BRIDGE_STATUS_OK
}