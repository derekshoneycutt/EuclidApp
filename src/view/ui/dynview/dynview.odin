package ui_dynview

import "../../../core"
import dynmath "../../../dynview/math"
import dyncore "../../../dynview/core"
import dynlayout "../../../dynview/layout"
import view_core "../../core"
import view_font "../../font"

import rl "vendor:raylib"


Mouse_Input_State :: view_core.Mouse_Input_State

UI_BORDER_COLOR :: view_core.UI_BORDER_COLOR
UI_TEXT_COLOR :: view_core.UI_TEXT_COLOR

//   Fallback wrapped-text layout metrics, grouped so the styled-or-fallback
//   entry point passes typography settings as one coherent value.
Wrapped_Text_Metrics :: struct {
    padding : f32,
    row_height : f32,
    wrap_advance : f32,
    font_size : f32,
}

//   Fallback plain-text payload for the styled-or-fallback draw path.
Fallback_Text_Content :: struct {
    text : string,
    color : rl.Color,
}

//   Panel, font, and metrics for one scratchpad draw pass.
Scratchpad_Draw_Params :: struct {
    panel : rl.Rectangle,
    scroll_y : f32,
    font : rl.Font,
    font_cache : ^view_font.Font_Cache,
    metrics : Wrapped_Text_Metrics,
}

//   Baseline draw position for one child math program.
Program_Draw_Position :: struct {
    draw_x : f32,
    baseline_y : f32,
    font_size: f32,
    math_style: dynmath.Math_Style,
    delimiter_target_height: f32,
}


//   Draw the fallback plain-text content for one scratchpad pass.
draw_scratchpad_fallback_text :: proc(
    fallback: Fallback_Text_Content, params: Scratchpad_Draw_Params) {

    view_core.draw_wrapped_text_content(fallback.text,
        view_core.Wrapped_Text_Content_Params{
            panel = params.panel,
            scroll_y = params.scroll_y,
            font = params.font,
            text_padding = params.metrics.padding,
            text_row_height = params.metrics.row_height,
            text_color = fallback.color,
            wrap_advance = params.metrics.wrap_advance,
            font_size = params.metrics.font_size,
            font_cache = params.font_cache,
            font_key = .Regular,
        })
}

//   Draw style-aware dynview content, falling back to plain wrapped text when unavailable.
draw_scratchpad_styled_or_fallback :: proc(
    state: ^core.Euclid_General_State,
    ui_runtime: ^core.Euclid_Ui_Runtime_State,
    fallback: Fallback_Text_Content,
    params: Scratchpad_Draw_Params) {

    if ui_runtime == nil {
        draw_scratchpad_fallback_text(fallback, params)
        return
    }

    runtime := &state^.dynview
    if runtime^.enabled && runtime^.cache_access_state == .Display_Readable &&
        runtime^.compile_cache.is_valid &&
        !runtime^.command_buffer.has_stream_error {
        if dynlayout.document_layout_is_authoritative(runtime) {
            draw_document_layout(Layout_Draw_Context{
                state = state,
                runtime = runtime,
                panel = params.panel,
                font = params.font,
                font_size = params.metrics.font_size,
            }, params.scroll_y, params.metrics.padding)
            return
        }
        if runtime^.command_buffer.command_count <= 0 {
            draw_scratchpad_fallback_text(fallback, params)
            return
        }
        if runtime^.compile_cache.layout_is_valid {
            draw_cached_layout(Layout_Draw_Context{
                state = state,
                runtime = runtime,
                panel = params.panel,
                font = params.font,
                font_size = params.metrics.font_size,
            }, params.scroll_y, params.metrics.padding)
            return
        }
    }

    draw_scratchpad_fallback_text(fallback, params)
}

//   Draw one measured child math program with a shared baseline.
draw_math_program_at :: proc(
    ctx: Layout_Draw_Context,
    program: core.Dynview_Math_Program,
    position: Program_Draw_Position) {

    runtime := ctx.runtime
    child_ctx := ctx
    if position.font_size > 0 {
        child_ctx.font_size = position.font_size
    }
    child_x := position.draw_x
    command_end := program.command_start + program.command_count
    for command_index in program.command_start..<command_end {
        cmd := runtime^.compile_cache.math_commands[command_index]
        child_item, ok := dynmath.math_program_item({
            cache = &runtime^.compile_cache,
            buffer = &runtime^.command_buffer,
            cmd = cmd,
            font_size = child_ctx.font_size,
            command_index = command_index,
            math_style = position.math_style,
            delimiter_target_height = position.delimiter_target_height,
        })
        if !ok {
            continue
        }

        child_x += dynmath.math_program_command_leading_space(
            &runtime^.compile_cache, program, command_index, child_ctx.font_size)
        child_y := position.baseline_y - child_item.ascent
        child_style := dyncore.style_by_id(child_item.style_id)
        draw_cached_text_item(child_ctx, child_style, child_item, child_x, child_y)
        child_x += child_item.draw_width
    }
}
