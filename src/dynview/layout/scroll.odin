package dynview_layout

import "../../core"
import dyncore "../core"

import rl "vendor:raylib"

Scratchpad_Fallback_Layout :: struct {
    text_padding, wrap_advance, row_height: f32,
    text: string,
}

// Report whether this runtime has a complete authoritative semantic document layout.
document_layout_is_authoritative :: #force_inline proc(
    runtime: ^core.Dynview_System) -> bool {

    return runtime != nil && len(runtime^.content.documents) > 0 &&
        runtime^.compile_cache.document_layout_is_valid &&
        !runtime^.command_buffer.has_stream_error
}

//   Return fallback wrapped row count for plain-text rendering.
fallback_row_count :: #force_inline proc(
    panel: rl.Rectangle,
    wrap_advance: f32,
    fallback_text: string) -> int {

    max_cols := dyncore.chars_per_text_row(
        panel.width - dyncore.TEXT_PADDING * 2, wrap_advance)
    return dyncore.count_wrapped_text_rows(fallback_text, max_cols)
}

//   Return total content height using cached line metrics, else fallback row math.
scratchpad_content_height_or_fallback :: proc(
    runtime: ^core.Dynview_System,
    panel: rl.Rectangle,
    fallback: Scratchpad_Fallback_Layout) -> f32 {

    fallback_rows := fallback_row_count(panel, fallback.wrap_advance, fallback.text)
    fallback_height := fallback.text_padding * 2 +
        f32(fallback_rows) * fallback.row_height

    if document_layout_is_authoritative(runtime) {
        return fallback.text_padding*2+
            runtime^.compile_cache.document_layout_total_height
    }
    if !runtime^.enabled ||
        !runtime^.compile_cache.layout_is_valid ||
        runtime^.command_buffer.has_stream_error ||
        len(dyncore.command_buffer_commands(&runtime^.command_buffer)) <= 0 {
        return fallback_height
    }

    return fallback.text_padding * 2 + runtime^.compile_cache.layout_total_height
}

//   Return scroll step derived from cached line metrics, else fallback to fixed row height.
scratchpad_scroll_step_or_fallback :: proc(
    runtime: ^core.Dynview_System,
    fallback_row_height: f32) -> f32 {

    if document_layout_is_authoritative(runtime) {
        lines := runtime^.compile_cache.document_layout_lines
        if len(lines) > 0 {
            return max(1.0,
                runtime^.compile_cache.document_layout_total_height/f32(len(lines)))
        }
    }
    if !runtime^.enabled ||
        !runtime^.compile_cache.layout_is_valid ||
        runtime^.command_buffer.has_stream_error ||
        len(dyncore.command_buffer_commands(&runtime^.command_buffer)) <= 0 {
        return fallback_row_height
    }

    return max(1.0, runtime^.compile_cache.layout_average_line_height)
}
