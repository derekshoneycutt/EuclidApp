package ui_dynview

import "../../../core"
import dynmath "../../../dynview/math"
import dyncore "../../../dynview/core"
import dynlayout "../../../dynview/layout"
import view_core "../../core"
import "../../font"

import "core:math"

import rl "vendor:raylib"

//   Measured per-cell items plus per-column widths and per-row extents.
Matrix_Draw_Cells :: struct {
    col_widths : [16]f32,
    row_ascents : [16]f32,
    row_descents : [16]f32,
}

//   Matrix grid geometry: column alignments, grid extents, and inter-cell gaps.
Matrix_Draw_Geometry :: struct {
    alignments : [16]dynmath.Dynview_Matrix_Column_Alignment,
    column_boundaries : [17]f32,
    row_boundaries : [17]f32,
    row_rule_offsets : [17]f32,
    vertical_rule_counts : [17]u8,
    horizontal_rule_counts : [17]u8,
    rows : int,
    cols : int,
    rule_thickness : f32,
    rule_separation : f32,
    color : rl.Color,
}

//   Control points and style for one normalized cubic Bezier segment.
Cubic_Segment_Params :: struct {
    p0, p1, p2, p3 : rl.Vector2,
    color : rl.Color,
    thickness : f32,
    segment_count : int,
}

//   Vertical stem run endpoints and stroke for one stretched brace.
Brace_Stem :: struct {
    y0 : f32,
    y1 : f32,
    thickness : f32,
    color : rl.Color,
}

//   Radical bar/hook geometry derived from one radical layout item.
Radical_Bar_Geometry :: struct {
    bar_y : f32,
    bar_start_x : f32,
    bar_end_x : f32,
    hook_start_x : f32,
    hook_start_y : f32,
    hook_flag_x : f32,
    root_low_x : f32,
    root_low_y : f32,
    root_rise_x : f32,
    root_rise_y : f32,
    root_high_x : f32,
    root_high_y : f32,
    bar_thickness : f32,
    hook_stroke : f32,
}

//   Per-side variant for one stretch delimiter glyph (which delimiter, where).
Stretch_Glyph_Side :: struct {
    delimiter_kind : i32,
    draw_x : f32,
}

//   Measured limit/glyph metrics for one large operator item.
Large_Op_Metrics :: struct {
    script_style : dyncore.Dynview_Text_Style,
    script_font : rl.Font,
    glyph_font_size : f32,
    glyph_ascent : f32,
    glyph_descent : f32,
    glyph_width : f32,
    limit_font_size : f32,
    sup_height : f32,
    sub_height : f32,
    sup_ascent : f32,
    sub_ascent : f32,
    sup_width : f32,
    sub_width : f32,
    limit_advance : f32,
    limit_gap : f32,
    sup_text : string,
    sub_text : string,
    sup_cols : int,
    sub_cols : int,
}

Large_Op_Limit_Position :: struct {
    x, top: f32,
}

Stretch_Construction_Position :: struct {
    origin_x, baseline_y, vertical_origin: f32,
}

//   Normalized control-point geometry for one stretched brace glyph.
Brace_Control_Geometry :: struct {
    r_norm : f32,
    tip_x : f32,
    stem_x : f32,
    cusp_x : f32,
    bend : f32,
}

//   Resolved text payload and font for one cached text item.
Cached_Item_Text :: struct {
    text : string,
    resolved_font : rl.Font,
    draw_x : f32,
}

//   Grouped inputs for one matrix cell grid draw pass.
Matrix_Cell_Draw :: struct {
    ctx : Layout_Draw_Context,
    cell_program : ^core.Dynview_Math_Program,
    cells : ^Matrix_Draw_Cells,
    geometry : Matrix_Draw_Geometry,
    math_style : dynmath.Math_Style,
    draw_x : f32,
    item_y : f32,
}

Matrix_Cell_Resolve :: struct {
    ctx: Layout_Draw_Context,
    item: core.Dynview_Layout_Item,
    rows, cols: int,
    math_style: dynmath.Math_Style,
    descriptor: ^core.Dynview_Math_Table_Descriptor,
    cells: ^Matrix_Draw_Cells,
}

//   Resolved script font and offsets for one script-attach item.
Script_Attach_Style :: struct {
    font : rl.Font,
    style : dyncore.Dynview_Text_Style,
    ascent : f32,
    font_size : f32,
}

Script_Child_Draw :: struct {
    program_id: i32,
    x, baseline: f32,
    role: dynmath.Math_Child_Style_Role,
}

//   Resolved numerator and denominator programs for one fraction item.
Fraction_Programs :: struct {
    numerator : ^core.Dynview_Math_Program,
    denominator : ^core.Dynview_Math_Program,
}

//   Shared inputs describing one radical item's placement and child content.
Radical_Layout :: struct {
    ctx : Layout_Draw_Context,
    item : core.Dynview_Layout_Item,
    draw_x : f32,
    baseline_y : f32,
    child_program : ^core.Dynview_Math_Program,
    front_padding : f32,
    back_padding : f32,
    lead_width : f32,
}

//   Measured position and font size for one optional radical index.
Radical_Index_Layout :: struct {
    position : rl.Vector2,
    font_size : f32,
}

//   Shared placement and style state for attached script limits.
Script_Limits_Draw :: struct {
    ctx : Layout_Draw_Context,
    item : core.Dynview_Layout_Item,
    script : Script_Attach_Style,
    offsets : dynmath.Script_Draw_Offsets,
    font : view_core.Ui_Text_Font,
    script_x : f32,
    baseline_y : f32,
}

//   Grouped inputs for one structured math item draw variant.
Math_Item_Draw :: struct {
    ctx : Layout_Draw_Context,
    style : dyncore.Dynview_Text_Style,
    item : core.Dynview_Layout_Item,
    resolved_font : rl.Font,
    text : string,
    draw_x : f32,
    item_y : f32,
}

//   Shared draw environment passed to cached layout item renderers so the
//   state/runtime/panel/font tuple travels as one coherent value.
Layout_Draw_Context :: struct {
    state : ^core.Euclid_General_State,
    runtime : ^core.Dynview_System,
    panel : rl.Rectangle,
    font : rl.Font,
    font_size : f32,
}

//   Inputs for one unshaped math run resolved through demand-loaded glyph pages.
Math_Text_Draw :: struct {
    state: ^core.Euclid_General_State,
    style: dyncore.Dynview_Text_Style,
    text: string,
    position: rl.Vector2,
    font: view_core.Ui_Text_Font,
}

//   Exact cached math command/site presentation request.
Cached_Math_Site_Draw :: struct {
    ctx: Layout_Draw_Context,
    item: core.Dynview_Layout_Item,
    site: core.Dynview_Shaped_Site,
    position: rl.Vector2,
    font_size: f32,
    color: rl.Color,
}

//   Complete draw context for one stretched delimiter glyph invocation.
//   Groups layout metrics, style/font state, and delimiter identity into one argument.
Stretch_Delimiter_Glyph_Params :: struct {
    state : ^core.Euclid_General_State,
    style : dyncore.Dynview_Text_Style,
    fallback_font : rl.Font,
    wrap_advance : f32,
    font_size : f32,
    content_height : f32,
    content_ascent : f32,
    content_descent : f32,
    delimiter_kind : i32,
    draw_x : f32,
    baseline_y : f32,
}

//   Pixel-space geometry derived from baseline/ascent/descent for one delimiter glyph.
//   The geometry is normalized so family renderers can share the same frame of reference.
Stretch_Delimiter_Glyph_Geometry :: struct {
    draw_x : f32,
    baseline_y : f32,
    top_y : f32,
    bottom_y : f32,
    center_y : f32,
    width : f32,
    height : f32,
    thickness : f32,
    right_side : bool,
}

//   Uniform handler shape for line-only delimiter family renderers.
Delimiter_Line_Handler :: #type proc(
    style : dyncore.Dynview_Text_Style,
    geom : Stretch_Delimiter_Glyph_Geometry,
    family: dynmath.Dynview_Delimiter_Family)

//   Line-renderers indexed by delimiter family; nil means the family needs a
//   curved renderer or the text fallback instead of a line fast path.
DELIMITER_LINE_HANDLERS ::
    [dynmath.Dynview_Delimiter_Family]Delimiter_Line_Handler{
    .None = nil,
    .Paren = nil,
    .Bracket = draw_delimiter_bracket,
    .Brace = nil,
    .Vert = draw_delimiter_vert,
    .Double_Vert = draw_delimiter_double_vert,
    .Ceil = draw_delimiter_bracket,
    .Floor = draw_delimiter_bracket,
    .Angle = draw_delimiter_angle,
}

//   Draw inputs for one text-run item: the runtime, style, resolved font,
//   colors, and draw position, grouped so the renderer passes one coherent value.
Text_Run_Draw_Params :: struct {
    state : ^core.Euclid_General_State,
    runtime : ^core.Dynview_System,
    font_size : f32,
    style : dyncore.Dynview_Text_Style,
    item : core.Dynview_Layout_Item,
    text : string,
    resolved_font : rl.Font,
    text_color : rl.Color,
    draw_x : f32,
    item_y : f32,
}

//   Draw math text without shaping while allowing any cmap-supported glyph.
draw_math_text :: proc(draw: Math_Text_Draw) {
    if draw.state == nil {
        view_core.ui_text_f32(
            draw.text, draw.position.x, draw.position.y,
            draw.style.color, draw.font)
        return
    }
    resolver := font.cache_terminal_resolver(&draw.state^.font_cache)
    view_core.ui_text_unshaped_paged({
        resolver = resolver,
        key = style_font_key(draw.style),
        text = draw.text,
        position = draw.position,
        color = draw.style.color,
        font = draw.font,
    })
}

//   Draw one math text span only when it contains content.
draw_optional_math_text :: proc(draw: Math_Text_Draw) {
    if len(draw.text) > 0 {
        draw_math_text(draw)
    }
}

//   Resolve the exact shaped run measured for one recursive math item site.
cached_math_site_run :: proc(
    ctx: Layout_Draw_Context,
    item: core.Dynview_Layout_Item,
    site: core.Dynview_Shaped_Site) -> (^core.Dynview_Shaped_Run, bool) {

    cache := &ctx.runtime^.compile_cache
    command_index := int(item.math_command_index)
    if command_index < 0 || command_index >= cache^.math_command_count {
        return nil, false
    }
    command := cache^.math_commands[command_index]
    run, ok := dynmath.shaped_run_for_command(cache, command, site)
    return run, ok && run^.math_command_index == command_index
}

//   Return the same scaled command/site metrics consumed during measurement.
cached_math_site_metrics :: #force_inline proc(
    ctx: Layout_Draw_Context,
    item: core.Dynview_Layout_Item,
    site: core.Dynview_Shaped_Site,
    font_size: f32) -> (dynmath.Shaped_Run_Layout_Metrics, bool) {

    run, ok := cached_math_site_run(ctx, item, site)
    if !ok {
        return {}, false
    }
    return dynmath.shaped_run_layout_metrics(run, font_size)
}

//   Draw one measured command/site run through its exact Math_Regular generation.
draw_cached_math_site :: proc(draw: Cached_Math_Site_Draw) -> bool {
    if draw.ctx.state == nil || draw.ctx.runtime == nil {
        return false
    }
    run, ok := cached_math_site_run(draw.ctx, draw.item, draw.site)
    if !ok || !font.cache_generation_is_resident(
        &draw.ctx.state^.font_cache, .Math_Regular, run^.font_generation) {
        return false
    }
    cache := &draw.ctx.runtime^.compile_cache
    glyphs, glyphs_ok := dynmath.shaped_glyphs_for_run(cache, run)
    if !glyphs_ok {
        return false
    }
    scale := draw.font_size/run^.base_pixel_size
    origin_x := draw.position.x - min(0, run^.ink_left)*scale
    line_top_y := view_core.ui_text_cached_run_line_top(
        draw.position.y, run^.ascent, run^.raster_ascent,
        draw.font_size, run^.base_pixel_size)
    resolver := font.cache_terminal_resolver(&draw.ctx.state^.font_cache)
    return view_core.ui_text_cached_shaped_run({
        resolver = resolver,
        key = .Math_Regular,
        glyphs = glyphs,
        position = {origin_x, line_top_y},
        color = draw.color,
        font_size = draw.font_size,
        base_pixel_size = run^.base_pixel_size,
    })
}

//   Fast vertical cull check for one layout line against panel bounds.
//   Returns true only when the full line is strictly outside the visible span.
layout_line_outside_panel :: #force_inline proc(
    line_top, line_bottom, panel_top, panel_bottom: f32) -> bool {

    return line_bottom < panel_top || line_top > panel_bottom
}

//   Draw one cached math-block item from its precomputed program slot.
draw_math_block_item :: proc(
    ctx: Layout_Draw_Context,
    item: core.Dynview_Layout_Item,
    item_x, item_y: f32) {

    runtime := ctx.runtime
    program_id := int(item.math_program_id)
    if runtime == nil || program_id < 0 ||
        program_id >= runtime^.compile_cache.math_program_count {
        return
    }

    program := runtime^.compile_cache.math_programs[program_id]
    if !program.valid {
        return
    }

    baseline_y := item_y + item.visual_padding_top + item.ascent
    draw_math_program_at(ctx,
        program, Program_Draw_Position{item_x, baseline_y, 0, {}, 0})
}

//   Draw one fully resident horizontal glyph-accent construction.
draw_glyph_accent_construction :: proc(
    ctx: Layout_Draw_Context,
    item: core.Dynview_Layout_Item,
    draw_x, baseline_y: f32,
    color: rl.Color) -> bool {

    construction := item.accent_glyph_construction
    cache := &ctx.runtime^.compile_cache
    if !item.accent_geometry_valid || !construction.valid ||
        item.accent_glyph_font_generation != cache^.shaped_font_generation ||
        !stretch_construction_is_resident(ctx, construction) {
        return false
    }
    resolver := font.cache_terminal_resolver(&ctx.state^.font_cache)
    for index in 0..<construction.count {
        part := construction.parts[index]
        glyphs := [1]core.Shaped_Glyph{{glyph_id = part.glyph_id}}
        if !view_core.ui_text_cached_shaped_run({
            resolver = resolver, key = .Math_Regular, glyphs = glyphs[:],
            position = {
                draw_x+item.accent_glyph_x+
                    part.advance_offset*item.accent_glyph_scale,
                baseline_y+item.accent_glyph_line_top,
            },
            color = color, font_size = item.math_font_size,
            base_pixel_size = cache^.math_constants.base_pixel_size,
        }) {
            return false
        }
    }
    return true
}

//   Draw one recursive rule or glyph accent from sealed geometry.
draw_recursive_accent_item :: proc(
    ctx: Layout_Draw_Context,
    style: dyncore.Dynview_Text_Style,
    item: core.Dynview_Layout_Item,
    draw_x, item_y: f32) {

    child_program, ok := dynmath.math_program_from_id(
        &ctx.runtime^.compile_cache, item.math_program_id)
    if !ok {
        return
    }

    baseline_y := item_y + item.ascent
    draw_math_program_at(ctx,
        child_program^, Program_Draw_Position{
            draw_x+item.accent_child_x,
            baseline_y + item.accent_child_baseline, 0, {}, 0})

    accent_style := dyncore.style_by_id(item.accent_style_id)
    if item.accent_mode > 2 {
        _ = draw_glyph_accent_construction(
            ctx, item, draw_x, baseline_y, accent_style.color)
        return
    }
    rl.DrawLineEx(
        rl.Vector2{draw_x + item.accent_rule_left,
            baseline_y + item.accent_rule_center},
        rl.Vector2{draw_x + item.accent_rule_right,
            baseline_y + item.accent_rule_center},
        item.accent_rule_thickness,
        accent_style.color)
}

//   Derive the bar/hook geometry for one radical item.
radical_bar_geometry :: proc(layout: Radical_Layout) -> Radical_Bar_Geometry {
    g := Radical_Bar_Geometry{}
    item := layout.item
    g.bar_thickness = max(1.0, item.accent_thickness * layout.ctx.font_size)
    bar_offset := max(0.0, item.accent_offset * layout.ctx.font_size)
    g.bar_y = layout.baseline_y - layout.child_program^.ascent - bar_offset
    g.bar_start_x = layout.draw_x + layout.front_padding + layout.lead_width * 0.84
    g.bar_end_x = layout.draw_x + item.draw_width - layout.back_padding
    g.hook_start_x = layout.draw_x + layout.front_padding - layout.lead_width * 0.20
    g.hook_start_y = layout.baseline_y - layout.ctx.font_size * 0.3
    g.hook_flag_x = g.hook_start_x - 2.5
    g.root_low_x = layout.draw_x + layout.front_padding + layout.lead_width * 0.26
    g.root_low_y = layout.baseline_y +
        dynmath.radical_root_low_offset(
            layout.ctx.font_size, layout.child_program^.descent)
    g.root_rise_x = layout.draw_x + layout.front_padding + layout.lead_width * 0.88
    g.root_rise_y = g.bar_y - layout.ctx.font_size * 0.14
    g.root_high_x = layout.draw_x + layout.front_padding + layout.lead_width * 1.24
    g.root_high_y = g.bar_y - layout.ctx.font_size * 0.06 + g.bar_thickness * 0.5
    g.hook_stroke = max(g.bar_thickness, g.bar_thickness * 1.25)
    return g
}

//   Draw the radical hook stroke (flag, low, rise, high, into the bar).
draw_radical_hook :: proc(g: Radical_Bar_Geometry, color: rl.Color) {
    rl.DrawLineEx(rl.Vector2{g.hook_flag_x, g.hook_start_y},
        rl.Vector2{g.hook_start_x, g.hook_start_y}, g.hook_stroke, color)
    rl.DrawLineEx(rl.Vector2{g.hook_start_x, g.hook_start_y},
        rl.Vector2{g.root_low_x, g.root_low_y}, g.hook_stroke, color)
    rl.DrawLineEx(rl.Vector2{g.root_low_x, g.root_low_y},
        rl.Vector2{g.root_rise_x, g.root_rise_y}, g.hook_stroke, color)
    rl.DrawLineEx(rl.Vector2{g.root_rise_x, g.root_rise_y},
        rl.Vector2{g.root_high_x, g.root_high_y}, g.hook_stroke, color)
    rl.DrawLineEx(rl.Vector2{g.root_high_x, g.root_high_y},
        rl.Vector2{g.bar_start_x, g.bar_y}, g.hook_stroke, color)
}

//   Measure and position one optional radical index against the hook.
radical_index_layout :: proc(
    layout: Radical_Layout,
    index_text: string,
    script_style: dyncore.Dynview_Text_Style) -> Radical_Index_Layout {
    ctx := layout.ctx
    index_scale := max(0.75, layout.item.script_scale)
    font_size := max(3.0, ctx.font_size * index_scale)
    ascent, _ := dyncore.style_ascent_descent(script_style, font_size)
    cols := max(1, dyncore.text_codepoint_count_span(index_text, 0, len(index_text)))
    advance := dyncore.effective_advance(
        script_style, ctx.runtime^.compile_cache.last_cell_width) * index_scale
    width := f32(cols) * advance
    metrics, measured := cached_math_site_metrics(
        ctx, layout.item, .Radical_Index, font_size)
    if measured {
        ascent = metrics.ascent
        width = metrics.draw_width
    }
    right := layout.draw_x + layout.front_padding + layout.lead_width * 0.36
    return {{
        right - width,
        layout.baseline_y - layout.child_program^.ascent * 0.62 -
            ascent * 0.50 - ctx.font_size * 0.25,
    }, font_size}
}

//   Draw the optional radical index text left of the hook.
draw_radical_index_text :: proc(
    layout: Radical_Layout,
    index_text: string,
    script_style: dyncore.Dynview_Text_Style,
    script_font: rl.Font) {

    if len(index_text) == 0 {
        return
    }
    ctx := layout.ctx
    index := radical_index_layout(layout, index_text, script_style)
    if draw_cached_math_site({
        ctx = ctx,
        item = layout.item,
        site = .Radical_Index,
        position = index.position,
        font_size = index.font_size,
        color = script_style.color,
    }) {
        return
    }
    draw_math_text({
        state = ctx.state,
        style = script_style,
        text = index_text,
        position = index.position,
        font = {script_font, index.font_size},
    })
}

//   Build and draw the radicand portion of one resolved radical layout.
radical_layout_for_child :: proc(
    ctx: Layout_Draw_Context,
    item: core.Dynview_Layout_Item,
    child_program: ^core.Dynview_Math_Program,
    draw_x, item_y: f32) -> Radical_Layout {

    baseline_y := item_y + item.ascent
    style := dyncore.style_by_id(item.style_id)
    base_advance :=
        dyncore.effective_advance(style, ctx.runtime^.compile_cache.last_cell_width)
    lead_width := dynmath.radical_lead_width(ctx.font_size, base_advance)
    front_padding, back_padding :=
        dynmath.radical_side_paddings(ctx.font_size, base_advance)
    content_x := draw_x + front_padding + lead_width
    if item.radical_geometry_valid {
        content_x = draw_x + item.math_stretch_content_x
    }
    math_style := dynmath.Math_Style{
        dynmath.Math_Style_Level(item.math_style_level), item.math_style_cramped}
    radicand_style, radicand_size := dynmath.math_child_font_size(
        &ctx.runtime^.compile_cache, item.math_font_size,
        math_style, .Radical_Radicand)
    draw_math_program_at(ctx, child_program^, Program_Draw_Position{
        content_x, baseline_y, radicand_size, radicand_style, 0})
    return {
        ctx = ctx, item = item, draw_x = draw_x, baseline_y = baseline_y,
        child_program = child_program, front_padding = front_padding,
        back_padding = back_padding, lead_width = lead_width,
    }
}

//   Resolve a radical item's child program and layout paddings, drawing the child.
//
// Returns:
//   - layout: Populated radical layout when ok.
//   - ok: true when the child program resolved and was drawn.
radical_make_layout :: proc(
    ctx: Layout_Draw_Context,
    item: core.Dynview_Layout_Item,
    draw_x, item_y: f32,
    out_layout: ^Radical_Layout) -> bool {

    child_program, ok := dynmath.math_program_from_id(
        &ctx.runtime^.compile_cache, item.math_program_id)
    if !ok {
        return false
    }

    out_layout^ = radical_layout_for_child(
        ctx, item, child_program, draw_x, item_y)
    return true
}

//   Draw the optional recursive radical degree in sealed or fallback position.
draw_radical_degree :: proc(layout: Radical_Layout, sealed: bool) -> bool {
    item := layout.item
    if item.secondary_math_program_id <= 0 {
        return false
    }
    degree, found := dynmath.math_program_from_id(
        &layout.ctx.runtime^.compile_cache, item.secondary_math_program_id)
    if !found {
        return false
    }
    math_style := dynmath.Math_Style{
        dynmath.Math_Style_Level(item.math_style_level), item.math_style_cramped}
    degree_style, degree_size := dynmath.math_child_font_size(
        &layout.ctx.runtime^.compile_cache, item.math_font_size,
        math_style, .Radical_Degree)
    position := Program_Draw_Position{
        layout.draw_x+item.radical_degree_x,
        layout.baseline_y+item.radical_degree_baseline,
        degree_size, degree_style, 0}
    if !sealed {
        right := layout.draw_x + layout.front_padding + layout.lead_width * 0.36
        position.draw_x = right - degree^.draw_width
        position.baseline_y = layout.baseline_y -
            layout.child_program^.ascent * 0.62 + degree^.ascent * 0.50 -
            item.math_font_size * 0.25
    }
    draw_math_program_at(layout.ctx, degree^, position)
    return true
}

//   Draw a sealed OpenType surd, MATH rule, and optional recursive degree.
draw_sealed_radical :: proc(
    layout: Radical_Layout,
    radical_style: dyncore.Dynview_Text_Style) -> bool {

    item := layout.item
    construction := item.math_stretch_constructions[0]
    if !item.radical_geometry_valid || !construction.valid ||
        !stretch_construction_is_resident(layout.ctx, construction) {
        return false
    }
    if !draw_stretch_construction(layout.ctx, item, construction, {
        layout.draw_x+item.math_stretch_left_x,
        layout.baseline_y,
        item.math_stretch_bottom,
    }, radical_style.color) {
        return false
    }
    rl.DrawLineEx(
        {layout.draw_x+item.radical_rule_left,
            layout.baseline_y+item.radical_rule_center},
        {layout.draw_x+item.radical_rule_right,
            layout.baseline_y+item.radical_rule_center},
        item.radical_rule_thickness, radical_style.color)
    _ = draw_radical_degree(layout, true)
    return true
}

//   Draw the heuristic radical rule and hook strokes.
draw_fallback_radical_strokes :: proc(
    layout: Radical_Layout,
    style: dyncore.Dynview_Text_Style) {

    geometry := radical_bar_geometry(layout)
    rl.DrawLineEx(
        {geometry.bar_start_x, geometry.bar_y},
        {geometry.bar_end_x, geometry.bar_y},
        geometry.bar_thickness, style.color)
    draw_radical_hook(geometry, style.color)
}

//   Draw one recursive radical wrapper by drawing the child math program first, then index and radical stroke.
draw_recursive_radical_item :: proc(
    ctx: Layout_Draw_Context,
    item: core.Dynview_Layout_Item,
    draw_x, item_y: f32) {

    layout := Radical_Layout{}
    if !radical_make_layout(ctx, item, draw_x, item_y, &layout) {
        return
    }

    script_style := dyncore.style_by_id(item.script_style_id)
    script_font := resolve_font_for_style(ctx.state, script_style, ctx.font)
    index_text := dyncore.text_span_from_buffer(
        &ctx.runtime^.command_buffer,
        item.radical_index_text_offset,
        item.radical_index_text_len)
    radical_style := dyncore.style_by_id(item.accent_style_id)

    if draw_sealed_radical(layout, radical_style) {
        return
    }

    draw_fallback_radical_strokes(layout, radical_style)
    if item.secondary_math_program_id > 0 {
        _ = draw_radical_degree(layout, false)
    } else {
        draw_radical_index_text(layout, index_text, script_style, script_font)
    }
}

//   Resolve a style-specific font handle, falling back to provided font when state is nil.
resolve_font_for_style :: #force_inline proc(
    state: ^core.Euclid_General_State,
    style: dyncore.Dynview_Text_Style,
    fallback_font: rl.Font) -> rl.Font {

    resolved := fallback_font
    if state == nil {
        return resolved
    }

    resolved = font.cache_resolve(
        &state^.font_cache, style_font_key(style))
    return resolved
}

//   Resolve final draw-x for one text item, honoring centered first-column alignment.
text_item_draw_x :: #force_inline proc(
    panel: rl.Rectangle,
    style: dyncore.Dynview_Text_Style,
    item: core.Dynview_Layout_Item,
    item_x: f32) -> f32 {

    if style.alignment == .Center && item.col_start == 0 {
        return panel.x + (panel.width - item.draw_width) * 0.5
    }
    return item_x
}

//   Resolve the script style, font, and vertical offsets for one script-attach item.
script_attach_style :: proc(
    ctx: Layout_Draw_Context,
    item: core.Dynview_Layout_Item) -> Script_Attach_Style {

    out := Script_Attach_Style{}
    out.style = dyncore.style_by_id(item.script_style_id)
    out.font = resolve_font_for_style(ctx.state, out.style, ctx.font)
    script_scale := max(0.2, item.script_scale)
    offsets := dynmath.script_draw_offsets(
        ctx.font_size,
        script_scale,
        item.script_sup_raise,
        item.script_sub_drop)
    out.font_size = offsets.script_font_size
    out.ascent, _ = dyncore.style_ascent_descent(out.style, out.font_size)
    return out
}

//   Draw one cached or fallback script site for a script-attach item.
draw_script_limit :: proc(
    draw: Script_Limits_Draw,
    site: core.Dynview_Shaped_Site) {
    superscript := site == .Superscript
    text := dyncore.text_span_from_buffer(&draw.ctx.runtime^.command_buffer,
        superscript ? draw.item.script_sup_text_offset : draw.item.script_sub_text_offset,
        superscript ? draw.item.script_sup_text_len : draw.item.script_sub_text_len)
    ascent := draw.script.ascent
    metrics, measured := cached_math_site_metrics(
        draw.ctx, draw.item, site, draw.script.font_size)
    if measured {
        ascent = metrics.ascent
    }
    top := draw.baseline_y - ascent +
        (superscript ? -draw.offsets.sup_raise_px : draw.offsets.sub_drop_px)
    if len(text) > 0 && !draw_cached_math_site({
        ctx = draw.ctx, item = draw.item, site = site,
        position = {draw.script_x, top}, font_size = draw.script.font_size,
        color = draw.script.style.color}) {
        draw_optional_math_text({
            state = draw.ctx.state, style = draw.script.style, text = text,
            position = {draw.script_x, top}, font = draw.font})
    }
}

//   Draw the superscript and subscript text for one script-attach item.
draw_script_attach_scripts :: proc(
    ctx: Layout_Draw_Context,
    item: core.Dynview_Layout_Item,
    script: Script_Attach_Style,
    child_width: f32,
    position: Program_Draw_Position) {

    offsets := dynmath.script_draw_offsets(ctx.font_size, max(0.2, item.script_scale),
        item.script_sup_raise, item.script_sub_drop)
    script_x := position.draw_x + child_width +
        max(1.0, item.script_gap * ctx.font_size)
    draw := Script_Limits_Draw{ctx, item, script, offsets,
        {script.font, script.font_size}, script_x, position.baseline_y}
    if item.secondary_math_program_id <= 0 {
        draw_script_limit(draw, .Superscript)
    }
    if item.tertiary_math_program_id <= 0 {
        draw_script_limit(draw, .Subscript)
    }
}

//   Draw one recursive superscript or subscript child program.
draw_script_attach_child :: proc(
    ctx: Layout_Draw_Context,
    item: core.Dynview_Layout_Item,
    math_style: dynmath.Math_Style,
    child: Script_Child_Draw) {

    if child.program_id <= 0 {
        return
    }
    program, found := dynmath.math_program_from_id(
        &ctx.runtime^.compile_cache, child.program_id)
    if !found {
        return
    }
    child_style, child_size := dynmath.math_child_font_size(
        &ctx.runtime^.compile_cache, item.math_font_size, math_style, child.role)
    draw_math_program_at(ctx, program^, Program_Draw_Position{
        child.x, child.baseline, child_size, child_style, 0})
}

//   Draw one recursive ScriptAttach wrapper by drawing a child program and script text.
draw_recursive_script_attach_item :: #force_inline proc(
    ctx: Layout_Draw_Context,
    item: core.Dynview_Layout_Item,
    draw_x, item_y: f32) {

    child_program, ok :=
        dynmath.math_program_from_id(&ctx.runtime^.compile_cache, item.math_program_id)
    if !ok {
        return
    }

    baseline_y := item_y + item.ascent
    math_style := dynmath.Math_Style{
        dynmath.Math_Style_Level(item.math_style_level), item.math_style_cramped}
    draw_math_program_at(ctx,
        child_program^, Program_Draw_Position{
            draw_x, baseline_y, item.math_font_size, math_style, 0})

    script := script_attach_style(ctx, item)
    draw_script_attach_scripts(ctx, item, script,
        child_program^.draw_width, Program_Draw_Position{
            draw_x, baseline_y, item.math_font_size, math_style, 0})

    draw_script_attach_child(ctx, item, math_style, {
        item.secondary_math_program_id, draw_x + item.script_sup_x,
        baseline_y + item.script_sup_baseline, .Superscript})
    draw_script_attach_child(ctx, item, math_style, {
        item.tertiary_math_program_id, draw_x + item.script_sub_x,
        baseline_y + item.script_sub_baseline, .Subscript})
}

//   Resolve the numerator and denominator math programs for one fraction item.
//
// Returns:
//   - programs: Resolved program pointers when ok.
//   - ok: true when both programs resolved.
fraction_resolve_programs :: proc(
    ctx: Layout_Draw_Context,
    item: core.Dynview_Layout_Item) -> (Fraction_Programs, bool) {

    out := Fraction_Programs{}
    numerator, ok := dynmath.math_program_from_id(
        &ctx.runtime^.compile_cache, item.math_program_id)
    if !ok {
        return out, false
    }
    denominator, ok_den := dynmath.math_program_from_id(
        &ctx.runtime^.compile_cache, item.secondary_math_program_id)
    if !ok_den {
        return out, false
    }
    out.numerator = numerator
    out.denominator = denominator
    return out, true
}

//   Resolve the fraction divider color, honoring an accent-style override.
fraction_divider_color :: #force_inline proc(
    item: core.Dynview_Layout_Item,
    style: dyncore.Dynview_Text_Style) -> rl.Color {

    if item.accent_style_id > 0 {
        return dyncore.style_by_id(item.accent_style_id).color
    }
    return style.color
}

//   Draw the centered divider rule for one recursive fraction.
draw_fraction_divider :: proc(
    style: dyncore.Dynview_Text_Style,
    item: core.Dynview_Layout_Item,
    draw_x, baseline_y: f32) {

    rl.DrawLineEx(
        {draw_x + item.fraction_rule_left,
            baseline_y + item.fraction_rule_center},
        {draw_x + item.fraction_rule_right,
            baseline_y + item.fraction_rule_center},
        item.fraction_rule_thickness,
        fraction_divider_color(item, style))
}

//   Draw one recursive fraction with centered numerator/denominator and center divider.
draw_recursive_fraction_item :: #force_inline proc(
    ctx: Layout_Draw_Context,
    style: dyncore.Dynview_Text_Style,
    item: core.Dynview_Layout_Item,
    draw_x, item_y: f32) {

    programs, programs_ok := fraction_resolve_programs(ctx, item)
    if !programs_ok {
        return
    }
    numerator_program := programs.numerator
    denominator_program := programs.denominator

    baseline_y := item_y + item.ascent
    math_style := dynmath.Math_Style{
        dynmath.Math_Style_Level(item.math_style_level), item.math_style_cramped}
    numerator_style, numerator_size := dynmath.math_child_font_size(
        &ctx.runtime^.compile_cache, item.math_font_size,
        math_style, .Fraction_Numerator)
    denominator_style, denominator_size := dynmath.math_child_font_size(
        &ctx.runtime^.compile_cache, item.math_font_size,
        math_style, .Fraction_Denominator)
    draw_math_program_at(ctx,
        numerator_program^,
        Program_Draw_Position{draw_x + item.fraction_numerator_x,
            baseline_y + item.fraction_numerator_baseline,
            numerator_size, numerator_style, 0})
    draw_math_program_at(ctx,
        denominator_program^,
        Program_Draw_Position{draw_x + item.fraction_denominator_x,
            baseline_y + item.fraction_denominator_baseline,
            denominator_size, denominator_style, 0})
    draw_fraction_divider(style, item, draw_x, baseline_y)
}

//   Draw one normalized cubic Bezier segment as line samples in pixel space.
//   Control points are in [0,1] glyph coordinates; right delimiters mirror x
//   so family geometry is authored once for the left-hand form.
draw_normalized_cubic_segment :: #force_inline proc(
    geom: Stretch_Delimiter_Glyph_Geometry,
    seg: Cubic_Segment_Params) {

    if seg.segment_count <= 0 {
        return
    }

    x0_norm := seg.p0.x
    if geom.right_side {
        x0_norm = 1.0 - x0_norm
    }
    prev := rl.Vector2{geom.draw_x + geom.width * x0_norm,
        geom.top_y + geom.height * seg.p0.y}

    for i in 1..=seg.segment_count {
        t := f32(i) / f32(seg.segment_count)
        u := 1.0 - t
        x_norm := u * u * u * seg.p0.x + 3.0 * u * u * t * seg.p1.x +
            3.0 * u * t * t * seg.p2.x + t * t * t * seg.p3.x
        y_norm := u * u * u * seg.p0.y + 3.0 * u * u * t * seg.p1.y +
            3.0 * u * t * t * seg.p2.y + t * t * t * seg.p3.y
        if geom.right_side {
            x_norm = 1.0 - x_norm
        }

        current := rl.Vector2{geom.draw_x + geom.width * x_norm,
            geom.top_y + geom.height * y_norm}
        rl.DrawLineEx(prev, current, seg.thickness, seg.color)
        prev = current
    }
}

//   Build the common geometry frame consumed by every delimiter family renderer.
//   Converts baseline/ascent/descent metrics into top/bottom extents, derives a
//   stable stroke thickness, and records side orientation for mirroring logic.
build_stretch_delimiter_geometry :: #force_inline proc(
    params: Stretch_Delimiter_Glyph_Params,
    width: f32) -> Stretch_Delimiter_Glyph_Geometry {

    top_y := params.baseline_y - params.content_ascent
    bottom_y := params.baseline_y + params.content_descent
    return Stretch_Delimiter_Glyph_Geometry{
        draw_x = params.draw_x,
        baseline_y = params.baseline_y,
        top_y = top_y,
        bottom_y = bottom_y,
        center_y = (top_y + bottom_y) * 0.5,
        width = width,
        height = max(1.0, bottom_y - top_y),
        thickness = max(1.0, params.font_size * 0.09),
        right_side = dynmath.delimiter_is_right(params.delimiter_kind),
    }
}

//   Render a single vertical bar centered in the glyph frame.
draw_delimiter_vert :: #force_inline proc(
    style: dyncore.Dynview_Text_Style,
    geom: Stretch_Delimiter_Glyph_Geometry,
    family: dynmath.Dynview_Delimiter_Family) {

    _ = family
    x := geom.draw_x + geom.width * 0.5
    rl.DrawLineEx(rl.Vector2{x, geom.top_y},
        rl.Vector2{x, geom.bottom_y}, geom.thickness, style.color)
}

//   Render a double vertical bar as two lanes centered in the glyph frame.
draw_delimiter_double_vert :: #force_inline proc(
    style: dyncore.Dynview_Text_Style,
    geom: Stretch_Delimiter_Glyph_Geometry,
    family: dynmath.Dynview_Delimiter_Family) {

    _ = family
    lane_gap := max(1.0, geom.width * 0.26)
    x1 := geom.draw_x + geom.width * 0.5 - lane_gap
    x2 := geom.draw_x + geom.width * 0.5 + lane_gap
    rl.DrawLineEx(rl.Vector2{x1, geom.top_y},
        rl.Vector2{x1, geom.bottom_y}, geom.thickness, style.color)
    rl.DrawLineEx(rl.Vector2{x2, geom.top_y},
        rl.Vector2{x2, geom.bottom_y}, geom.thickness, style.color)
}

//   Render a bracket/ceil/floor as a vertical stem plus optional top/bottom hooks.
//   Ceil omits the bottom hook; Floor omits the top hook.
draw_delimiter_bracket :: #force_inline proc(
    style: dyncore.Dynview_Text_Style,
    geom: Stretch_Delimiter_Glyph_Geometry,
    family: dynmath.Dynview_Delimiter_Family) {

    stem_x := geom.draw_x + geom.width * 0.28
    hook_x := geom.draw_x + geom.width * 0.88
    if geom.right_side {
        stem_x = geom.draw_x + geom.width * 0.72
        hook_x = geom.draw_x + geom.width * 0.12
    }
    rl.DrawLineEx(rl.Vector2{stem_x, geom.top_y},
        rl.Vector2{stem_x, geom.bottom_y}, geom.thickness, style.color)
    if family != .Floor {
        rl.DrawLineEx(rl.Vector2{stem_x, geom.top_y},
            rl.Vector2{hook_x, geom.top_y}, geom.thickness, style.color)
    }
    if family != .Ceil {
        rl.DrawLineEx(rl.Vector2{stem_x, geom.bottom_y},
            rl.Vector2{hook_x, geom.bottom_y}, geom.thickness, style.color)
    }
}

//   Render an angle bracket as two rails meeting at an apex on the glyph midline.
draw_delimiter_angle :: #force_inline proc(
    style: dyncore.Dynview_Text_Style,
    geom: Stretch_Delimiter_Glyph_Geometry,
    family: dynmath.Dynview_Delimiter_Family) {

    _ = family
    apex_x := geom.draw_x + geom.width * 0.14
    rail_x := geom.draw_x + geom.width * 0.86
    if geom.right_side {
        apex_x = geom.draw_x + geom.width * 0.86
        rail_x = geom.draw_x + geom.width * 0.14
    }
    rl.DrawLineEx(rl.Vector2{rail_x, geom.top_y},
        rl.Vector2{apex_x, geom.center_y}, geom.thickness, style.color)
    rl.DrawLineEx(rl.Vector2{apex_x, geom.center_y},
        rl.Vector2{rail_x, geom.bottom_y}, geom.thickness, style.color)
}

//   Render line-only delimiter families (no sampled curves or cubic segments).
//   Returns true when this proc handled the family so callers can short-circuit
//   curved renderers and fallback glyph paths.
draw_stretch_delimiter_line_family :: #force_inline proc(
    style: dyncore.Dynview_Text_Style,
    family: dynmath.Dynview_Delimiter_Family,
    geom: Stretch_Delimiter_Glyph_Geometry) -> bool {

    handlers := DELIMITER_LINE_HANDLERS
    handler := handlers[family]
    if handler == nil {
        return false
    }

    handler(style, geom, family)
    return true
}

//   Render stretched parentheses from a sinusoidal side profile.
//   The right side mirrors the same profile so both sides remain symmetric and
//   visually consistent across changing content heights.
draw_stretch_delimiter_paren :: #force_inline proc(
    style: dyncore.Dynview_Text_Style,
    geom: Stretch_Delimiter_Glyph_Geometry) {

    segment_count := 12
    for i in 0..<segment_count {
        t0 := f32(i) / f32(segment_count)
        t1 := f32(i + 1) / f32(segment_count)
        y0 := geom.top_y + geom.height * t0
        y1 := geom.top_y + geom.height * t1
        curve0 := math.sin(t0 * math.PI)
        curve1 := math.sin(t1 * math.PI)

        x0 := geom.draw_x + geom.width * (0.78 - 0.46 * curve0)
        x1 := geom.draw_x + geom.width * (0.78 - 0.46 * curve1)
        if geom.right_side {
            x0 = geom.draw_x + geom.width * (0.22 + 0.46 * curve0)
            x1 = geom.draw_x + geom.width * (0.22 + 0.46 * curve1)
        }

        rl.DrawLineEx(rl.Vector2{x0, y0}, rl.Vector2{x1, y1}, geom.thickness, style.color)
    }
}

//   Draw one vertical stem run of a stretched brace when the stem is long enough.
draw_brace_stem :: #force_inline proc(
    geom: Stretch_Delimiter_Glyph_Geometry,
    stem_x, stem_len: f32,
    stem: Brace_Stem) {

    if stem_len <= 0.5 {
        return
    }
    x_stem := geom.draw_x + geom.width * stem_x
    if geom.right_side {
        x_stem = geom.draw_x + geom.width * (1.0 - stem_x)
    }
    rl.DrawLineEx(
        rl.Vector2{x_stem, stem.y0},
        rl.Vector2{x_stem, stem.y1},
        stem.thickness,
        stem.color)
}

//   Draw the four quarter-turn cubic segments (two hooks, two cusps) of a brace.
//
//   Left brace layout (mirrored automatically for right): tips point right
//   toward the content, the vertical stem sits just left of center, and the
//   middle cusp juts left away from the content. Four quarter-turn cubic
//   curves join two straight stem runs; corner radius stays fixed while the
//   stems absorb any extra height, matching how TeX stretches braces.
draw_brace_curves :: proc(
    geom: Stretch_Delimiter_Glyph_Geometry,
    cg: Brace_Control_Geometry,
    seg: Cubic_Segment_Params) {

    tip_x := cg.tip_x
    stem_x := cg.stem_x
    cusp_x := cg.cusp_x
    bend := cg.bend
    r_norm := cg.r_norm

    // Top hook: horizontal at the tip, vertical where it joins the stem.
    top := seg
    top.p0 = rl.Vector2{tip_x, 0.0}
    top.p1 = rl.Vector2{tip_x - bend * (tip_x - stem_x), 0.0}
    top.p2 = rl.Vector2{stem_x, r_norm * (1.0 - bend)}
    top.p3 = rl.Vector2{stem_x, r_norm}
    draw_normalized_cubic_segment(geom, top)

    // Upper cusp curve: vertical at the stem, horizontal into the cusp point.
    upper := seg
    upper.p0 = rl.Vector2{stem_x, 0.5 - r_norm}
    upper.p1 = rl.Vector2{stem_x, 0.5 - r_norm * (1.0 - bend)}
    upper.p2 = rl.Vector2{cusp_x + bend * (stem_x - cusp_x), 0.5}
    upper.p3 = rl.Vector2{cusp_x, 0.5}
    draw_normalized_cubic_segment(geom, upper)

    // Lower cusp curve mirrors the upper one below the midline.
    lower := seg
    lower.p0 = rl.Vector2{cusp_x, 0.5}
    lower.p1 = rl.Vector2{cusp_x + bend * (stem_x - cusp_x), 0.5}
    lower.p2 = rl.Vector2{stem_x, 0.5 + r_norm * (1.0 - bend)}
    lower.p3 = rl.Vector2{stem_x, 0.5 + r_norm}
    draw_normalized_cubic_segment(geom, lower)

    // Bottom hook mirrors the top hook.
    bottom := seg
    bottom.p0 = rl.Vector2{stem_x, 1.0 - r_norm}
    bottom.p1 = rl.Vector2{stem_x, 1.0 - r_norm * (1.0 - bend)}
    bottom.p2 = rl.Vector2{tip_x - bend * (tip_x - stem_x), 1.0}
    bottom.p3 = rl.Vector2{tip_x, 1.0}
    draw_normalized_cubic_segment(geom, bottom)
}

//   Render stretched braces from four cubic turns plus two optional stem runs.
//   Corner radius is kept stable while extra height stretches only the stems,
//   which prevents braces from becoming pointy or overly flat at large sizes.
draw_stretch_delimiter_brace :: #force_inline proc(
    style: dyncore.Dynview_Text_Style,
    geom: Stretch_Delimiter_Glyph_Geometry,
    font_size: f32) {

    segment_count := 16
    brace_thickness := max(1.0, geom.thickness * 0.85)

    half_height := geom.height * 0.5
    radius_px := min(max(2.0, font_size * 0.24), half_height * 0.5)
    stem_len := max(0.0, half_height - 2.0 * radius_px)

    cg := Brace_Control_Geometry{
        r_norm = radius_px / geom.height,
        tip_x = f32(0.88),
        stem_x = f32(0.45),
        cusp_x = f32(0.06),
        bend = f32(0.55),
    }
    draw_brace_curves(geom, cg, Cubic_Segment_Params{
        color = style.color,
        thickness = brace_thickness,
        segment_count = segment_count,
    })

    draw_brace_stem(geom, cg.stem_x, stem_len,
        Brace_Stem{geom.top_y + radius_px, geom.center_y - radius_px,
            brace_thickness, style.color})
    draw_brace_stem(geom, cg.stem_x, stem_len,
        Brace_Stem{geom.center_y + radius_px, geom.bottom_y - radius_px,
            brace_thickness, style.color})
}

//   Draw a font glyph fallback when no procedural family renderer is used.
//   The fallback scales with content height while preserving baseline alignment
//   so mixed text/math lines remain vertically coherent.
draw_stretch_delimiter_text_fallback :: #force_inline proc(
    params: Stretch_Delimiter_Glyph_Params,
    width: f32) {

    delimiter := dynmath.delimiter_text(params.delimiter_kind)
    if len(delimiter) == 0 {
        return
    }

    stretch_scale := max(1.0, params.content_height / max(1.0, params.font_size))
    delimiter_font_size := max(1.0, params.font_size * stretch_scale)
    delim_ascent, _ := dyncore.style_ascent_descent(params.style, delimiter_font_size)
    resolved_font :=
        resolve_font_for_style(params.state, params.style, params.fallback_font)
    draw_math_text({
        state = params.state,
        style = params.style,
        text = delimiter,
        position = {params.draw_x, params.baseline_y - delim_ascent},
        font = {resolved_font, delimiter_font_size},
    })
    _ = width
}

//   Draw one stretched delimiter and return its advance width.
//   Dispatch order is deliberate: line-family fast path, curved family renderer,
//   then baseline-aligned text fallback when no procedural path applies.
draw_stretch_delimiter_glyph :: #force_inline proc(
    params: Stretch_Delimiter_Glyph_Params) -> f32 {

    if params.delimiter_kind == dynmath.DELIMITER_KIND_NONE {
        return 0
    }

    family := dynmath.delimiter_family(params.delimiter_kind)
    width := dynmath.stretch_delimiter_width(
        params.style,
        params.wrap_advance,
        params.font_size,
        params.content_height,
        params.delimiter_kind)
    if family == .None || width <= 0 {
        return 0
    }

    geom := build_stretch_delimiter_geometry(params, width)
    if draw_stretch_delimiter_line_family(params.style, family, geom) {
        return width
    }

    switch family {
    case .Paren:
        draw_stretch_delimiter_paren(params.style, geom)
        return width
    case .Brace:
        draw_stretch_delimiter_brace(params.style, geom, params.font_size)
        return width
    case .Vert, .Double_Vert, .Bracket, .Ceil, .Floor, .Angle, .None:
    }

    draw_stretch_delimiter_text_fallback(params, width)
    return width
}

//   Demand every selected glyph before drawing any part of a construction.
stretch_construction_is_resident :: proc(
    ctx: Layout_Draw_Context,
    construction: core.Font_Math_Stretch_Construction) -> bool {

    if ctx.state == nil || !construction.valid || construction.count <= 0 ||
        construction.count > len(construction.parts) {
        return false
    }
    resident := true
    for index in 0..<construction.count {
        _, found := font.cache_terminal_resolve_glyph(
            &ctx.state^.font_cache, .Math_Regular,
            construction.parts[index].glyph_id)
        resident = resident && found
    }
    return resident
}

//   Draw one fully resident bottom-to-top OpenType MATH construction.
draw_stretch_construction :: proc(
    ctx: Layout_Draw_Context,
    item: core.Dynview_Layout_Item,
    construction: core.Font_Math_Stretch_Construction,
    position: Stretch_Construction_Position,
    color: rl.Color) -> bool {

    if !stretch_construction_is_resident(ctx, construction) {
        return false
    }
    cache := &ctx.runtime^.compile_cache
    resolver := font.cache_terminal_resolver(&ctx.state^.font_cache)
    raster_scale := item.math_font_size/cache^.math_constants.base_pixel_size
    for index in 0..<construction.count {
        part := construction.parts[index]
        glyphs := [1]core.Shaped_Glyph{{glyph_id = part.glyph_id}}
        part_baseline := position.baseline_y + position.vertical_origin -
            part.advance_offset*item.math_stretch_scale
        if !view_core.ui_text_cached_shaped_run({
            resolver = resolver, key = .Math_Regular, glyphs = glyphs[:],
            position = {position.origin_x,
                part_baseline-item.math_stretch_raster_ascent*raster_scale},
            color = color, font_size = item.math_font_size,
            base_pixel_size = cache^.math_constants.base_pixel_size,
        }) {
            return false
        }
    }
    return true
}

//   Draw both sealed delimiter sides only when all selected parts are resident.
draw_sealed_stretch_delimiters :: proc(
    ctx: Layout_Draw_Context,
    style: dyncore.Dynview_Text_Style,
    item: core.Dynview_Layout_Item,
    draw_x, baseline_y: f32) -> bool {

    cache := &ctx.runtime^.compile_cache
    if !item.math_stretch_geometry_valid ||
        item.math_stretch_font_generation != cache^.shaped_font_generation {
        return false
    }
    for construction in item.math_stretch_constructions {
        if construction.valid &&
            !stretch_construction_is_resident(ctx, construction) {
            return false
        }
    }
    left := item.math_stretch_constructions[0]
    right := item.math_stretch_constructions[1]
    left_ok := !left.valid || draw_stretch_construction(
        ctx, item, left, {draw_x+item.math_stretch_left_x, baseline_y,
            item.math_stretch_vertical_origins[0]}, style.color)
    right_ok := !right.valid || draw_stretch_construction(
        ctx, item, right, {draw_x+item.math_stretch_right_x, baseline_y,
            item.math_stretch_vertical_origins[1]}, style.color)
    return left_ok && right_ok
}

//   Build the glyph params for one stretch delimiter, shared by left and right.
stretch_delimiter_glyph_params :: #force_inline proc(
    ctx: Layout_Draw_Context,
    style: dyncore.Dynview_Text_Style,
    item: core.Dynview_Layout_Item,
    baseline_y: f32,
    side: Stretch_Glyph_Side) -> Stretch_Delimiter_Glyph_Params {

    return Stretch_Delimiter_Glyph_Params{
        state = ctx.state,
        style = style,
        fallback_font = ctx.font,
        wrap_advance = ctx.runtime^.compile_cache.last_cell_width,
        font_size = ctx.font_size,
        content_height = item.ascent + item.descent,
        content_ascent = item.ascent,
        content_descent = item.descent,
        delimiter_kind = side.delimiter_kind,
        draw_x = side.draw_x,
        baseline_y = baseline_y,
    }
}

//   Recover the measured style inherited by recursive delimiter content.
stretch_delimiter_child_style :: #force_inline proc(
    item: core.Dynview_Layout_Item) -> dynmath.Math_Style {

    return {
        dynmath.Math_Style_Level(item.math_style_level),
        item.math_style_cramped,
    }
}

//   Draw optional content between one pair of stretch delimiters.
draw_stretch_delimiter_content :: proc(
    ctx: Layout_Draw_Context,
    item: core.Dynview_Layout_Item,
    content_x, baseline_y: f32) -> f32 {

    if item.math_program_id <= 0 {
        return 0
    }
    child_program, ok := dynmath.math_program_from_id(
        &ctx.runtime^.compile_cache, item.math_program_id)
    if !ok {
        return 0
    }
    draw_math_program_at(ctx, child_program^, Program_Draw_Position{
        content_x, baseline_y, 0, stretch_delimiter_child_style(item), 0})
    return child_program^.draw_width
}

//   Draw measured content inside a sealed stretch-delimiter construction.
draw_sealed_stretch_content :: proc(
    ctx: Layout_Draw_Context,
    item: core.Dynview_Layout_Item,
    draw_x, baseline_y: f32) {

    if item.math_program_id <= 0 {
        return
    }
    child_program, ok := dynmath.math_program_from_id(
        &ctx.runtime^.compile_cache, item.math_program_id)
    if ok {
        draw_math_program_at(ctx, child_program^, Program_Draw_Position{
            draw_x+item.math_stretch_content_x, baseline_y, 0,
            stretch_delimiter_child_style(item), item.math_stretch_target_height})
    }
}

//   Draw one recursive stretch-delimiter wrapper around optional child content.
//   Left delimiter, child program, and right delimiter are laid out in-order
//   using runtime stretch metrics so both delimiters share the same baseline.
draw_recursive_stretch_delimiter_item :: #force_inline proc(
    ctx: Layout_Draw_Context,
    style: dyncore.Dynview_Text_Style,
    item: core.Dynview_Layout_Item,
    draw_x, item_y: f32) {

    baseline_y := item_y + item.ascent
    if draw_sealed_stretch_delimiters(ctx, style, item, draw_x, baseline_y) {
        draw_sealed_stretch_content(ctx, item, draw_x, baseline_y)
        return
    }
    left_clearance, right_clearance: f32
    left_clearance, right_clearance = dynmath.stretch_delimiter_clearances({
        math_program_id = item.math_program_id,
        math_atom_class = item.math_atom_class,
        accent_mode = item.accent_mode,
        radical_mode = item.radical_mode,
    }, ctx.font_size)

    left_draw_x := draw_x
    left_width := draw_stretch_delimiter_glyph(
        stretch_delimiter_glyph_params(ctx, style, item, baseline_y,
            Stretch_Glyph_Side{item.accent_mode, left_draw_x}))

    content_x := left_draw_x + left_width + left_clearance
    content_width := draw_stretch_delimiter_content(
        ctx, item, content_x, baseline_y)

    right_draw_x := content_x + content_width + right_clearance
    _ = draw_stretch_delimiter_glyph(
        stretch_delimiter_glyph_params(ctx, style, item, baseline_y,
            Stretch_Glyph_Side{item.radical_mode, right_draw_x}))
}

//   Resolve the matrix cell program and measured cells for one matrix item.
//
// Returns:
//   - cell_program: The matrix cell program when ok.
//   - ok: true when the program resolved and all cells measured.
matrix_resolve_cells :: proc(
    input: Matrix_Cell_Resolve) -> (^core.Dynview_Math_Program, bool) {

    cell_program, ok :=
        dynmath.math_program_from_id(&input.ctx.runtime^.compile_cache,
            input.item.math_program_id)
    if !ok || cell_program^.command_count < input.rows * input.cols {
        return nil, false
    }

    if !measure_matrix_draw_cells(input, cell_program) {
        return nil, false
    }
    return cell_program, true
}

//   Build the matrix grid geometry (alignments, gaps) for one matrix item.
matrix_draw_geometry :: proc(
    ctx: Layout_Draw_Context,
    style: dyncore.Dynview_Text_Style,
    item: core.Dynview_Layout_Item,
    descriptor: ^core.Dynview_Math_Table_Descriptor) -> Matrix_Draw_Geometry {

    base_advance :=
        dyncore.effective_advance(style, ctx.runtime^.compile_cache.last_cell_width)
    geometry := Matrix_Draw_Geometry{
        alignments = descriptor^.column_alignments,
        vertical_rule_counts = descriptor^.vertical_rule_counts,
        horizontal_rule_counts = descriptor^.horizontal_rule_counts,
        rows = descriptor^.rows,
        cols = descriptor^.columns,
        rule_thickness = dynmath.math_table_rule_thickness(ctx.font_size),
        rule_separation = dynmath.math_table_rule_separation(ctx.font_size),
        color = style.color,
    }
    for boundary in 0..=descriptor^.columns {
        geometry.column_boundaries[boundary] =
            dynmath.math_table_column_boundary_width(
                descriptor, boundary, ctx.font_size, base_advance)
    }
    for boundary in 0..=descriptor^.rows {
        geometry.row_boundaries[boundary] =
            dynmath.math_table_row_boundary_height(descriptor, boundary, ctx.font_size)
        geometry.row_rule_offsets[boundary] =
            dynmath.math_table_row_rule_offset(descriptor, boundary, ctx.font_size)
    }
    return geometry
}

//   Draw one recursive matrix wrapper by centering cells per column and baselining per row.
draw_recursive_matrix_item :: #force_inline proc(
    ctx: Layout_Draw_Context,
    style: dyncore.Dynview_Text_Style,
    item: core.Dynview_Layout_Item,
    draw_x, item_y: f32) {

    descriptor, descriptor_ok := dynmath.matrix_descriptor_from_command(
        &ctx.runtime^.compile_cache,
        core.Dynview_Command{table_descriptor_index = item.table_descriptor_index})
    if !descriptor_ok {
        return
    }
    rows := descriptor^.rows
    cols := descriptor^.columns
    parent_style := dynmath.Math_Style{
        dynmath.Math_Style_Level(item.math_style_level), item.math_style_cramped}
    cell_style := dynmath.Math_Style{
        dynmath.Math_Style_Level(descriptor^.cell_style), false}
    cell_ctx := ctx
    cell_ctx.font_size = dynmath.math_target_font_size(
        &ctx.runtime^.compile_cache, item.math_font_size, parent_style, cell_style)

    cells := Matrix_Draw_Cells{}
    cell_program, cells_ok := matrix_resolve_cells({
        cell_ctx, item, rows, cols, cell_style, descriptor, &cells})
    if !cells_ok {
        return
    }

    geometry := matrix_draw_geometry(ctx, style, item, descriptor)

    draw_matrix_cells(Matrix_Cell_Draw{
        ctx = cell_ctx,
        cell_program = cell_program,
        cells = &cells,
        geometry = geometry,
        math_style = cell_style,
        draw_x = draw_x,
        item_y = item_y,
    })
}

//   Draw one matrix cell at its aligned position within the grid.
draw_matrix_cell :: #force_inline proc(
    ctx: Layout_Draw_Context,
    cell_program: ^core.Dynview_Math_Program,
    cell_index: int,
    cell_item: core.Dynview_Layout_Item,
    position: Program_Draw_Position) {

    command_start := cell_program^.command_start + cell_index
    cell_single_program := core.Dynview_Math_Program{
        valid = true,
        command_start = command_start,
        command_count = 1,
        draw_width = cell_item.draw_width,
        ascent = cell_item.ascent,
        descent = cell_item.descent,
    }
    draw_math_program_at(
        ctx,
        cell_single_program,
        position)
}

//   Draw one aligned row of measured matrix cells.
draw_matrix_row :: proc(
    d: Matrix_Cell_Draw,
    row: int,
    row_baseline: f32) {

    ctx := d.ctx
    col_x := d.draw_x + d.geometry.column_boundaries[0]
    for col in 0..<d.geometry.cols {
        cell_index := row * d.geometry.cols + col
        command_index := d.cell_program^.command_start + cell_index
        command := ctx.runtime^.compile_cache.math_commands[command_index]
        cell_item, ok := dynmath.math_program_item({
            cache = &ctx.runtime^.compile_cache,
            buffer = &ctx.runtime^.command_buffer,
            cmd = command, font_size = ctx.font_size,
            command_index = command_index,
            math_style = d.math_style,
        })
        if ok {
            cell_x := dynmath.matrix_aligned_cell_x(
                col_x, d.cells.col_widths[col], cell_item.draw_width,
                d.geometry.alignments[col])
            draw_matrix_cell(ctx, d.cell_program, cell_index, cell_item,
                Program_Draw_Position{cell_x, row_baseline, 0, d.math_style, 0})
        }
        col_x += d.cells.col_widths[col]
        col_x += d.geometry.column_boundaries[col + 1]
    }
}

//   Draw all rules carried by one column boundary.
draw_matrix_vertical_boundary_rules :: proc(
    d: Matrix_Cell_Draw, boundary_x, table_height: f32, boundary: int) {

    count := int(d.geometry.vertical_rule_counts[boundary])
    if count == 0 {
        return
    }
    occupied := f32(count) * d.geometry.rule_thickness +
        f32(count - 1) * d.geometry.rule_separation
    free_space := d.geometry.column_boundaries[boundary] - occupied
    rule_x := boundary_x + free_space * 0.5
    if boundary == 0 {
        rule_x = boundary_x
    } else if boundary == d.geometry.cols {
        rule_x = boundary_x + free_space
    }
    for _ in 0..<count {
        center_x := rule_x + d.geometry.rule_thickness * 0.5
        rl.DrawLineEx({center_x, d.item_y}, {center_x, d.item_y + table_height},
            d.geometry.rule_thickness, d.geometry.color)
        rule_x += d.geometry.rule_thickness + d.geometry.rule_separation
    }
}

//   Draw every vertical table rule from sealed boundary spans.
draw_matrix_vertical_rules :: proc(d: Matrix_Cell_Draw) {
    table_height: f32
    for row in 0..<d.geometry.rows {
        table_height += d.cells.row_ascents[row] + d.cells.row_descents[row]
    }
    for boundary in 0..=d.geometry.rows {
        table_height += d.geometry.row_boundaries[boundary]
    }
    boundary_x := d.draw_x
    for boundary in 0..=d.geometry.cols {
        draw_matrix_vertical_boundary_rules(d, boundary_x, table_height, boundary)
        boundary_x += d.geometry.column_boundaries[boundary]
        if boundary < d.geometry.cols {
            boundary_x += d.cells.col_widths[boundary]
        }
    }
}

//   Draw all rules carried by one row boundary.
draw_matrix_horizontal_boundary_rules :: proc(
    d: Matrix_Cell_Draw, boundary_y, table_width: f32, boundary: int) {

    count := int(d.geometry.horizontal_rule_counts[boundary])
    if count == 0 {
        return
    }
    rule_y := boundary_y + d.geometry.row_rule_offsets[boundary]
    for _ in 0..<count {
        center_y := rule_y + d.geometry.rule_thickness * 0.5
        rl.DrawLineEx({d.draw_x, center_y}, {d.draw_x + table_width, center_y},
            d.geometry.rule_thickness, d.geometry.color)
        rule_y += d.geometry.rule_thickness + d.geometry.rule_separation
    }
}

//   Draw every horizontal table rule from sealed boundary spans.
draw_matrix_horizontal_rules :: proc(d: Matrix_Cell_Draw) {
    table_width: f32
    for col in 0..<d.geometry.cols {
        table_width += d.cells.col_widths[col]
    }
    for boundary in 0..=d.geometry.cols {
        table_width += d.geometry.column_boundaries[boundary]
    }
    boundary_y := d.item_y
    for boundary in 0..=d.geometry.rows {
        draw_matrix_horizontal_boundary_rules(d, boundary_y, table_width, boundary)
        boundary_y += d.geometry.row_boundaries[boundary]
        if boundary < d.geometry.rows {
            boundary_y += d.cells.row_ascents[boundary] + d.cells.row_descents[boundary]
        }
    }
}

//   Draw every measured matrix cell at its aligned position.
draw_matrix_cells :: proc(d: Matrix_Cell_Draw) {
    cells := d.cells
    geometry := d.geometry
    draw_matrix_vertical_rules(d)
    draw_matrix_horizontal_rules(d)
    row_top := d.item_y + geometry.row_boundaries[0]
    for row in 0..<geometry.rows {
        row_baseline := row_top + cells.row_ascents[row]
        draw_matrix_row(d, row, row_baseline)
        row_top += cells.row_ascents[row] + cells.row_descents[row]
        row_top += geometry.row_boundaries[row + 1]
    }
}

//   Measure every matrix cell, accumulating items, column widths, row extents.
measure_matrix_draw_cells :: proc(
    input: Matrix_Cell_Resolve,
    cell_program: ^core.Dynview_Math_Program) -> bool {

    runtime := input.ctx.runtime
    font_size := input.ctx.font_size
    strut_ascent, strut_descent :=
        dynmath.math_table_row_strut(input.descriptor^.row_spacing, font_size)

    for row in 0..<input.rows {
        input.cells.row_ascents[row] = strut_ascent
        input.cells.row_descents[row] = strut_descent
        for col in 0..<input.cols {
            cell_index := row * input.cols + col
            cmd_index := cell_program^.command_start + cell_index
            cell_cmd := runtime^.compile_cache.math_commands[cmd_index]
            cell_item, cell_ok := dynmath.math_program_item({
                cache = &runtime^.compile_cache,
                buffer = &runtime^.command_buffer,
                cmd = cell_cmd,
                font_size = font_size,
                command_index = cmd_index,
                math_style = input.math_style,
            })
            if !cell_ok {
                return false
            }

            input.cells.col_widths[col] =
                max(input.cells.col_widths[col], cell_item.draw_width)
            input.cells.row_ascents[row] =
                max(input.cells.row_ascents[row], cell_item.ascent)
            input.cells.row_descents[row] =
                max(input.cells.row_descents[row], cell_item.descent)
        }
    }
    return true
}

//   Draw the primary recursive item kinds and report whether one matched.
draw_primary_structured_item :: #force_inline proc(d: Math_Item_Draw) -> bool {
    ctx := d.ctx
    style := d.style
    item := d.item
    draw_x := d.draw_x
    item_y := d.item_y

    #partial switch item.kind {
    case .Script_Attach:
        draw_recursive_script_attach_item(ctx, item, draw_x, item_y)
    case .Frac:
        draw_recursive_fraction_item(ctx, style, item, draw_x, item_y)
    case .Stretch_Delimiter:
        draw_recursive_stretch_delimiter_item(ctx, style, item, draw_x, item_y)
    case .Matrix:
        draw_recursive_matrix_item(ctx, style, item, draw_x, item_y)
    case .Style_Override:
        draw_recursive_style_override_item(ctx, item, draw_x, item_y)
    case:
        return false
    }
    return true
}

//   Draw one recursive structured math item variant routed by layout item kind.
draw_recursive_structured_item :: #force_inline proc(d: Math_Item_Draw) {
    if draw_primary_structured_item(d) {
        return
    }
    #partial switch d.item.kind {
    case .Stack:
        draw_recursive_stack_item(d.ctx, d.item, d.draw_x, d.item_y)
    case .Large_Op:
        draw_large_op_recursive_item(d)
    case .Accent_Bar:
        draw_recursive_accent_item(d.ctx, d.style, d.item, d.draw_x, d.item_y)
    case .Radical_Bar:
        draw_recursive_radical_item(d.ctx, d.item, d.draw_x, d.item_y)
    case .Text_Run, .Math_Glyph_Run, .Math_Block,
        .Inline_Line, .Inline_Box, .Inline_Circle, .Inline_Filled_Box,
        .Inline_Filled_Circle, .Inline_Pie_Section, .Inline_Perpendicular,
        .Inline_Triangle, .Inline_Pentagon:
    }
}

//   Draw one ruleless two-part stack from its sealed child positions.
draw_recursive_stack_item :: proc(
    ctx: Layout_Draw_Context,
    item: core.Dynview_Layout_Item,
    draw_x, item_y: f32) {

    programs, ok := fraction_resolve_programs(ctx, item)
    if !ok {
        return
    }
    baseline_y := item_y + item.ascent
    style := dynmath.Math_Style{
        dynmath.Math_Style_Level(item.math_style_level), item.math_style_cramped}
    top_style, top_size := dynmath.math_child_font_size(
        &ctx.runtime^.compile_cache, item.math_font_size,
        style, .Fraction_Numerator)
    bottom_style, bottom_size := dynmath.math_child_font_size(
        &ctx.runtime^.compile_cache, item.math_font_size,
        style, .Fraction_Denominator)
    if item.operator_limits == 1 {
        bottom_style, bottom_size = style, item.math_font_size
    } else if item.operator_limits == 2 {
        top_style, top_size = style, item.math_font_size
        bottom_style, bottom_size = dynmath.math_child_font_size(
            &ctx.runtime^.compile_cache, item.math_font_size,
            style, .Superscript)
    }
    draw_math_program_at(ctx, programs.numerator^, Program_Draw_Position{
        draw_x + item.fraction_numerator_x,
        baseline_y + item.fraction_numerator_baseline, top_size, top_style, 0})
    draw_math_program_at(ctx, programs.denominator^, Program_Draw_Position{
        draw_x + item.fraction_denominator_x,
        baseline_y + item.fraction_denominator_baseline, bottom_size, bottom_style, 0})
}

//   Draw one scoped child program under its explicit math style.
draw_recursive_style_override_item :: proc(
    ctx: Layout_Draw_Context,
    item: core.Dynview_Layout_Item,
    draw_x, item_y: f32) {

    child, ok := dynmath.math_program_from_id(
        &ctx.runtime^.compile_cache, item.math_program_id)
    if !ok {
        return
    }
    parent := dynmath.Math_Style{
        dynmath.Math_Style_Level(item.math_style_level), item.math_style_cramped}
    target := dynmath.Math_Style{
        dynmath.Math_Style_Level(item.radical_mode), false}
    target_size := dynmath.math_target_font_size(
        &ctx.runtime^.compile_cache, item.math_font_size, parent, target)
    draw_math_program_at(ctx, child^, Program_Draw_Position{
        draw_x, item_y + item.ascent, target_size, target, 0})
}

//   Overlay exact cached glyph and limit dimensions used by measurement.
large_op_apply_cached_metrics :: proc(
    d: Math_Item_Draw, metrics: ^Large_Op_Metrics) {

    glyph, glyph_ok := cached_math_site_metrics(
        d.ctx, d.item, .Primary, metrics^.glyph_font_size)
    if glyph_ok {
        metrics^.glyph_ascent = glyph.ascent
        metrics^.glyph_descent = glyph.descent
        metrics^.glyph_width = glyph.draw_width
    }
    if d.item.secondary_math_program_id <= 0 {
        sup, sup_ok := cached_math_site_metrics(
            d.ctx, d.item, .Superscript, metrics^.limit_font_size)
        if sup_ok {
            metrics^.sup_width = sup.draw_width
            metrics^.sup_height = sup.ascent + sup.descent
            metrics^.sup_ascent = sup.ascent
        }
    }
    if d.item.tertiary_math_program_id <= 0 {
        sub, sub_ok := cached_math_site_metrics(
            d.ctx, d.item, .Subscript, metrics^.limit_font_size)
        if sub_ok {
            metrics^.sub_width = sub.draw_width
            metrics^.sub_height = sub.ascent + sub.descent
            metrics^.sub_ascent = sub.ascent
        }
    }
}

//   Override one large-operator limit with a recursive program's metrics.
large_op_apply_program_limit :: proc(
    d: Math_Item_Draw,
    metrics: ^Large_Op_Metrics,
    site: core.Dynview_Shaped_Site) {

    program_id := d.item.secondary_math_program_id
    if site == .Subscript {
        program_id = d.item.tertiary_math_program_id
    }
    if program_id <= 0 {
        return
    }
    program, found := dynmath.math_program_from_id(
        &d.ctx.runtime^.compile_cache, program_id)
    if !found {
        return
    }
    if site == .Superscript {
        metrics^.sup_cols = 1
        metrics^.sup_width = program^.draw_width
        metrics^.sup_height = program^.ascent + program^.descent
        metrics^.sup_ascent = program^.ascent
    } else {
        metrics^.sub_cols = 1
        metrics^.sub_width = program^.draw_width
        metrics^.sub_height = program^.ascent + program^.descent
        metrics^.sub_ascent = program^.ascent
    }
}

//   Populate synthetic script and limit metrics for one large operator.
large_op_measure_limits :: proc(d: Math_Item_Draw, m: ^Large_Op_Metrics) {
    ctx := d.ctx
    item := d.item
    m^.script_style = dyncore.style_by_id(item.script_style_id)
    m^.script_font = resolve_font_for_style(ctx.state, m^.script_style, d.resolved_font)
    limit_scale := max(0.2, item.script_scale)
    m^.limit_font_size = max(1.0, ctx.font_size * limit_scale)
    limit_ascent, limit_descent :=
        dyncore.style_ascent_descent(m^.script_style, m^.limit_font_size)
    m^.sup_height = limit_ascent + limit_descent
    m^.sub_height = m^.sup_height
    m^.sup_ascent = limit_ascent
    m^.sub_ascent = limit_ascent
    m^.limit_advance = dyncore.effective_advance(m^.script_style,
        ctx.runtime^.compile_cache.last_cell_width) * limit_scale
    m^.limit_gap = dynmath.large_op_limit_gap_for_kind(
        item.large_op_kind, ctx.font_size, item.script_gap)
    m^.sup_text = dyncore.text_span_from_buffer(&ctx.runtime^.command_buffer,
        item.script_sup_text_offset, item.script_sup_text_len)
    m^.sub_text = dyncore.text_span_from_buffer(&ctx.runtime^.command_buffer,
        item.script_sub_text_offset, item.script_sub_text_len)
    m^.sup_cols = dyncore.text_codepoint_count_span(m^.sup_text, 0, len(m^.sup_text))
    m^.sub_cols = dyncore.text_codepoint_count_span(m^.sub_text, 0, len(m^.sub_text))
    m^.sup_width = f32(m^.sup_cols) * m^.limit_advance
    m^.sub_width = f32(m^.sub_cols) * m^.limit_advance
    large_op_apply_program_limit(d, m, .Superscript)
    large_op_apply_program_limit(d, m, .Subscript)
}

//   Compute glyph and limit metrics for one large operator item.
large_op_metrics :: proc(d: Math_Item_Draw) -> Large_Op_Metrics {
    ctx := d.ctx
    style := d.style
    item := d.item
    text := d.text
    m := Large_Op_Metrics{}

    glyph_scale := dynmath.large_op_glyph_scale(item.large_op_kind)
    m.glyph_font_size = max(1.0, ctx.font_size * glyph_scale)
    m.glyph_ascent, m.glyph_descent =
        dyncore.style_ascent_descent(style, m.glyph_font_size)
    glyph_cols := max(1, dyncore.text_codepoint_count_span(text, 0, len(text)))
    glyph_advance := dyncore.effective_advance(style,
        ctx.runtime^.compile_cache.last_cell_width) * glyph_scale
    m.glyph_width = f32(glyph_cols) * glyph_advance

    large_op_measure_limits(d, &m)
    large_op_apply_cached_metrics(d, &m)
    return m
}

//   Compute the stacked superscript or subscript top within a large operator box.
large_op_limit_top :: #force_inline proc(
    m: Large_Op_Metrics,
    item_y: f32,
    site: core.Dynview_Shaped_Site) -> f32 {

    if site == .Superscript {
        return item_y
    }
    top := item_y + m.glyph_ascent + m.glyph_descent + m.limit_gap
    if m.sup_cols > 0 {
        top += m.sup_height + m.limit_gap
    }
    return top
}

//   Resolve one operator limit's fallback or sealed position.
large_op_limit_position :: proc(
    d: Math_Item_Draw,
    m: Large_Op_Metrics,
    site: core.Dynview_Shaped_Site) -> Large_Op_Limit_Position {

    width := m.sup_width
    if site == .Subscript {
        width = m.sub_width
    }
    position := Large_Op_Limit_Position{
        d.draw_x + (d.item.draw_width-width)*0.5,
        large_op_limit_top(m, d.item_y, site)}
    if !d.item.script_geometry_valid {
        return position
    }
    baseline := d.item.script_sup_baseline
    ascent := m.sup_ascent
    position.x = d.draw_x + d.item.script_sup_x
    if site == .Subscript {
        baseline = d.item.script_sub_baseline
        ascent = m.sub_ascent
        position.x = d.draw_x + d.item.script_sub_x
    }
    position.top = d.item_y + d.item.ascent + baseline - ascent
    return position
}

//   Resolve and draw one recursive large-operator limit program.
large_op_draw_program_limit :: proc(
    d: Math_Item_Draw,
    position: Large_Op_Limit_Position,
    program_id: i32,
    role: dynmath.Math_Child_Style_Role) -> bool {

    if program_id <= 0 {
        return false
    }
    program, found := dynmath.math_program_from_id(
        &d.ctx.runtime^.compile_cache, program_id)
    if !found {
        return true
    }
    math_style := dynmath.Math_Style{
        dynmath.Math_Style_Level(d.item.math_style_level),
        d.item.math_style_cramped}
    child_style, child_size := dynmath.math_child_font_size(
        &d.ctx.runtime^.compile_cache, d.item.math_font_size, math_style, role)
    draw_math_program_at(d.ctx, program^, Program_Draw_Position{
        position.x, position.top + program^.ascent, child_size, child_style, 0})
    return true
}

//   Draw the stacked superscript or subscript limit for one large operator.
large_op_draw_limit :: #force_inline proc(
    d: Math_Item_Draw,
    m: Large_Op_Metrics,
    text: string,
    site: core.Dynview_Shaped_Site) {

    position := large_op_limit_position(d, m, site)
    program_id := d.item.secondary_math_program_id
    role: dynmath.Math_Child_Style_Role = .Superscript
    if site == .Subscript {
        program_id = d.item.tertiary_math_program_id
        role = .Subscript
    }
    if large_op_draw_program_limit(d, position, program_id, role) {
        return
    }
    if draw_cached_math_site({
        ctx = d.ctx, item = d.item, site = site,
        position = {position.x, position.top}, font_size = m.limit_font_size,
        color = m.script_style.color}) {
        return
    }
    draw_math_text({
        state = d.ctx.state,
        style = m.script_style,
        text = text,
        position = {position.x, position.top},
        font = {m.script_font, m.limit_font_size},
    })
}

//   Resolve and draw one sealed display-operator glyph through bounded page demand.
draw_large_op_variant :: proc(d: Math_Item_Draw) -> bool {
    item := d.item
    cache := &d.ctx.runtime^.compile_cache
    if !item.operator_geometry_valid || item.operator_glyph_id == 0 ||
        item.operator_font_generation != cache^.shaped_font_generation ||
        item.operator_glyph_font_size <= 0 || cache^.math_constants.base_pixel_size <= 0 {
        return false
    }
    glyphs := [1]core.Shaped_Glyph{{glyph_id = item.operator_glyph_id}}
    resolver := font.cache_terminal_resolver(&d.ctx.state^.font_cache)
    return view_core.ui_text_cached_shaped_run({
        resolver = resolver,
        key = .Math_Regular,
        glyphs = glyphs[:],
        position = {
            d.draw_x + item.operator_glyph_x,
            d.item_y + item.operator_glyph_line_top,
        },
        color = d.style.color,
        font_size = item.operator_glyph_font_size,
        base_pixel_size = cache^.math_constants.base_pixel_size,
    })
}

//   Draw one display-style large operator with stacked limits above and below.
draw_large_op_recursive_item :: #force_inline proc(d: Math_Item_Draw) {
    m := large_op_metrics(d)

    glyph_top := d.item_y
    if m.sup_cols > 0 {
        glyph_top += m.sup_height + m.limit_gap
    }
    glyph_x := d.draw_x + (d.item.draw_width - m.glyph_width) * 0.5
    if !draw_large_op_variant(d) && !draw_cached_math_site({
        ctx = d.ctx, item = d.item, site = .Primary,
        position = {glyph_x, glyph_top}, font_size = m.glyph_font_size,
        color = d.style.color}) {
        draw_math_text({
            state = d.ctx.state, style = d.style, text = d.text,
            position = {glyph_x, glyph_top},
            font = {d.resolved_font, m.glyph_font_size}})
    }

    if m.sup_cols > 0 {
        large_op_draw_limit(d, m, m.sup_text, .Superscript)
    }
    if m.sub_cols > 0 {
        large_op_draw_limit(d, m, m.sub_text, .Subscript)
    }
}

//   Resolve the text payload, font, and centered draw-x for one cached text item.
//
// Returns:
//   - resolved: Populated text/font/draw_x when ok.
//   - ok: true when the item text range is valid.
cached_item_resolve_text :: proc(
    ctx: Layout_Draw_Context,
    style: dyncore.Dynview_Text_Style,
    item: core.Dynview_Layout_Item,
    item_x: f32) -> (Cached_Item_Text, bool) {

    out := Cached_Item_Text{}
    runtime := ctx.runtime
    text_end := item.text_offset + item.text_len
    if item.text_offset < 0 || item.text_len < 0 {
        return out, false
    }
    text_bytes := dyncore.command_buffer_text(&runtime^.command_buffer)
    if text_end > len(text_bytes) {
        return out, false
    }

    out.text = string(text_bytes[item.text_offset:text_end])
    out.resolved_font = resolve_font_for_style(ctx.state, style, ctx.font)
    out.draw_x = text_item_draw_x(ctx.panel, style, item, item_x)
    return out, true
}

//   Build the text-run draw params for one resolved cached text item.
text_run_draw_params :: #force_inline proc(
    ctx: Layout_Draw_Context,
    style: dyncore.Dynview_Text_Style,
    item: core.Dynview_Layout_Item,
    resolved: Cached_Item_Text,
    item_y: f32) -> Text_Run_Draw_Params {

    text_color := item.has_brush_color ? item.brush_color : style.color
    return Text_Run_Draw_Params{
        state = ctx.state,
        runtime = ctx.runtime,
        font_size = ctx.font_size,
        style = style,
        item = item,
        text = resolved.text,
        resolved_font = resolved.resolved_font,
        text_color = text_color,
        draw_x = resolved.draw_x,
        item_y = item_y,
    }
}

//   Dispatch one resolved cached text item to its kind-specific renderer.
draw_cached_text_item_dispatch :: proc(
    ctx: Layout_Draw_Context,
    style: dyncore.Dynview_Text_Style,
    item: core.Dynview_Layout_Item,
    resolved: Cached_Item_Text,
    item_y: f32) {

    draw_x := resolved.draw_x

    switch item.kind {
    case .Script_Attach, .Frac, .Stretch_Delimiter,
        .Matrix, .Style_Override, .Stack, .Large_Op, .Accent_Bar, .Radical_Bar:
        draw_recursive_structured_item(Math_Item_Draw{
            ctx = ctx,
            style = style,
            item = item,
            resolved_font = resolved.resolved_font,
            text = resolved.text,
            draw_x = draw_x,
            item_y = item_y,
        })
    case .Math_Block:
        draw_math_block_item(ctx, item, draw_x, item_y)
    case .Text_Run, .Math_Glyph_Run:
        draw_text_run_item(text_run_draw_params(ctx, style, item, resolved, item_y))
    case .Inline_Line, .Inline_Box, .Inline_Circle, .Inline_Filled_Box,
        .Inline_Filled_Circle, .Inline_Pie_Section, .Inline_Perpendicular,
        .Inline_Triangle, .Inline_Pentagon:
    }
}

//   Draw one cached text item.
draw_cached_text_item :: proc(
    ctx: Layout_Draw_Context,
    style: dyncore.Dynview_Text_Style,
    item: core.Dynview_Layout_Item,
    item_x, item_y: f32) {

    resolved, text_ok := cached_item_resolve_text(ctx, style, item, item_x)
    if !text_ok {
        return
    }
    draw_cached_text_item_dispatch(ctx, style, item, resolved, item_y)
}

//   Draw the shaped or math content of one resolved text run.
draw_text_run_content :: proc(
    params: Text_Run_Draw_Params, text_font: view_core.Ui_Text_Font) {

    if params.item.kind == .Text_Run && params.state != nil {
        resolver := font.cache_terminal_resolver(&params.state^.font_cache)
        view_core.ui_text_shaped({
            resolver = resolver,
            key = style_font_key(params.style),
            text = params.text,
            position = {params.draw_x, params.item_y},
            color = params.text_color,
            font = text_font,
        })
        return
    }
    if params.item.kind == .Math_Glyph_Run && draw_cached_math_site({
        ctx = {
            state = params.state,
            runtime = params.runtime,
            font_size = params.font_size,
        },
        item = params.item,
        site = .Primary,
        position = {params.draw_x, params.item_y},
        font_size = text_font.font_size,
        color = params.text_color,
    }) {
        return
    }
    draw_math_text({
        state = params.state,
        style = params.style,
        text = params.text,
        position = {params.draw_x, params.item_y},
        font = text_font,
    })
}

//   Draw the optional underline for one resolved text run.
draw_text_run_underline :: proc(params: Text_Run_Draw_Params) {
    if !params.style.underline {
        return
    }
    underline_width := f32(params.item.col_span) * dyncore.effective_advance(
        params.style, params.runtime^.compile_cache.last_cell_width)
    underline_y := params.item_y + params.font_size + 1
    rl.DrawLineEx(
        rl.Vector2{params.draw_x, underline_y},
        rl.Vector2{params.draw_x + underline_width, underline_y},
        1,
        params.text_color)
}

//   Draw one cached text-run item with optional underline.
draw_text_run_item :: proc(params: Text_Run_Draw_Params) {
    text_font := view_core.Ui_Text_Font{params.resolved_font, params.font_size}
    draw_text_run_content(params, text_font)
    draw_text_run_underline(params)
}

//   Draw one inline box outline with per-edge colors.
draw_inline_box_outline :: #force_inline proc(
    item: core.Dynview_Layout_Item,
    item_x, item_y: f32,
    color: rl.Color) {

    stroke := max(1.0, item.inline_atom_stroke)
    inset := stroke * 0.5
    left := item_x + inset
    right := item_x + item.draw_width - inset
    top := item_y + inset
    bottom := item_y + item.draw_height - inset
    top_left := rl.Vector2{left, top}
    top_right := rl.Vector2{right, top}
    bottom_left := rl.Vector2{left, bottom}
    bottom_right := rl.Vector2{right, bottom}
    rl.DrawLineEx(top_left, top_right, stroke,
        shape_edge_color_or(item.shape_edge_color_1, color))
    rl.DrawLineEx(top_right, bottom_right, stroke,
        shape_edge_color_or(item.shape_edge_color_2, color))
    rl.DrawLineEx(bottom_right, bottom_left, stroke,
        shape_edge_color_or(item.shape_edge_color_3, color))
    rl.DrawLineEx(bottom_left, top_left, stroke,
        shape_edge_color_or(item.shape_edge_color_4, color))
}

//   Draw one inline circle outline with optional inner stroke.
draw_inline_circle_outline :: #force_inline proc(
    item: core.Dynview_Layout_Item,
    item_x, item_y: f32,
    color: rl.Color) {

    stroke := max(1.0, item.inline_atom_stroke)
    center := rl.Vector2{
        item_x + item.draw_width * 0.5,
        item_y + item.draw_height * 0.5,
    }
    radius := max(0.5, (min(item.draw_width, item.draw_height) - stroke) * 0.5)
    rl.DrawRing(center,
        max(0.0, radius - stroke * 0.5), radius + stroke * 0.5,
        0, 360, 64, color)
}

//   Draw one cached inline shape item.
draw_cached_inline_basic_item :: #force_inline proc(
    style: dyncore.Dynview_Text_Style,
    item: core.Dynview_Layout_Item,
    item_x, item_y: f32,
    color: rl.Color) {

    switch item.kind {
    case .Inline_Line:
        stroke := max(1.0, item.inline_atom_stroke)
        half_stroke := stroke * 0.5
        center_y := item_y + item.draw_height * 0.5
        rl.DrawLineEx(
            rl.Vector2{item_x + half_stroke, center_y},
            rl.Vector2{item_x + item.draw_width - half_stroke, center_y},
            stroke,
            color)
    case .Inline_Box:
        draw_inline_box_outline(item, item_x, item_y, color)
    case .Inline_Circle:
        draw_inline_circle_outline(item, item_x, item_y, color)
    case .Text_Run, .Math_Glyph_Run, .Math_Block, .Script_Attach, .Frac,
         .Stretch_Delimiter, .Matrix, .Style_Override, .Stack, .Large_Op,
         .Accent_Bar, .Radical_Bar, .Inline_Filled_Box, .Inline_Filled_Circle,
         .Inline_Pie_Section, .Inline_Perpendicular, .Inline_Triangle, .Inline_Pentagon:
    }
}

//   Draw one filled box and optional outline inside its intrinsic visual bounds.
draw_inline_filled_box :: #force_inline proc(
    style: dyncore.Dynview_Text_Style,
    item: core.Dynview_Layout_Item,
    item_x, item_y: f32,
    color: rl.Color) {

    stroke := max(0.0, item.inline_outline_stroke)
    inset := stroke * 0.5
    rect := rl.Rectangle{
        item_x + inset,
        item_y + inset,
        max(0.5, item.draw_width - stroke),
        max(0.5, item.draw_height - stroke),
    }
    rl.DrawRectangleRec(rect, color)
    if stroke > 0 {
        rl.DrawRectangleLinesEx(rect, max(1.0, stroke), style.color)
    }
}

//   Draw one filled circle and optional outline inside its intrinsic visual bounds.
draw_inline_filled_circle :: #force_inline proc(
    style: dyncore.Dynview_Text_Style,
    item: core.Dynview_Layout_Item,
    item_x, item_y: f32,
    color: rl.Color) {

    stroke := max(0.0, item.inline_outline_stroke)
    center := rl.Vector2{item_x + item.draw_width * 0.5,
        item_y + item.draw_height * 0.5}
    radius := max(0.5,
        (min(item.draw_width, item.draw_height) - stroke) * 0.5)
    rl.DrawCircleV(center, radius, color)
    if stroke > 0 {
        rl.DrawRing(center,
            max(0.0, radius - stroke * 0.5), radius + stroke * 0.5,
            0, 360, 64, style.color)
    }
}

//   Draw one cached filled inline shape item.
draw_cached_inline_filled_item :: #force_inline proc(
    style: dyncore.Dynview_Text_Style,
    item: core.Dynview_Layout_Item,
    item_x, item_y: f32,
    color: rl.Color) {

    switch item.kind {
    case .Inline_Filled_Box:
        draw_inline_filled_box(style, item, item_x, item_y, color)
    case .Inline_Filled_Circle:
        draw_inline_filled_circle(style, item, item_x, item_y, color)
    case .Text_Run, .Math_Glyph_Run, .Math_Block, .Script_Attach, .Frac,
         .Stretch_Delimiter, .Matrix, .Style_Override, .Stack, .Large_Op,
         .Accent_Bar, .Radical_Bar, .Inline_Line, .Inline_Box,
         .Inline_Circle, .Inline_Pie_Section, .Inline_Perpendicular, .Inline_Triangle,
         .Inline_Pentagon:
    }
}

//   Draw one inline pie-section atom, filled or outline-only.
draw_inline_pie_section_item :: #force_inline proc(
    style: dyncore.Dynview_Text_Style,
    item: core.Dynview_Layout_Item,
    item_x, item_y: f32,
    color: rl.Color) {

    center := rl.Vector2{item_x + item.pie_center_offset_x,
        item_y + item.pie_center_offset_y}
    visual_radius := max(
        max(item.pie_center_offset_x, item.draw_width - item.pie_center_offset_x),
        max(item.pie_center_offset_y, item.draw_height - item.pie_center_offset_y))
    radius := max(0.5, visual_radius - item.inline_atom_stroke * 0.5)
    outline_color := item.has_outline_color ? item.outline_color : style.color
    stroke := max(1.0, item.inline_outline_stroke)
    if item.pie_is_filled {
        draw_filled_pie_section(center, radius,
            item.pie_start_angle_degrees, item.pie_end_angle_degrees, color)
    }
    if !item.pie_is_filled || item.inline_outline_stroke > 0 {
        draw_pie_section_outline(center, radius,
            item.pie_start_angle_degrees, item.pie_end_angle_degrees,
            Pie_Section_Style{stroke, outline_color})
    }
}

//   Draw one inline triangle atom with optional fill and per-edge colors.
draw_inline_triangle_item :: #force_inline proc(
    item: core.Dynview_Layout_Item,
    item_x, item_y: f32,
    color: rl.Color) {

    stroke := max(1.0, item.inline_atom_stroke)
    inset := stroke * 0.5
    rect := rl.Rectangle{item_x + inset, item_y + inset,
        max(0.5, item.draw_width - stroke), max(0.5, item.draw_height - stroke)}
    draw_triangle_shape(rect,
        item.shape_is_filled,
        Triangle_Colors{
            color,
            shape_edge_color_or(item.shape_edge_color_1, color),
            shape_edge_color_or(item.shape_edge_color_2, color),
            shape_edge_color_or(item.shape_edge_color_3, color),
        },
        stroke)
}

//   Draw one inline pentagon atom with optional fill and per-edge colors.
draw_inline_pentagon_item :: #force_inline proc(
    item: core.Dynview_Layout_Item,
    item_x, item_y: f32,
    color: rl.Color) {

    stroke := max(1.0, item.inline_atom_stroke)
    inset := stroke * 0.5
    rect := rl.Rectangle{item_x + inset, item_y + inset,
        max(0.5, item.draw_width - stroke), max(0.5, item.draw_height - stroke)}
    draw_pentagon_shape(rect,
        item.shape_is_filled,
        Pentagon_Colors{
            color,
            shape_edge_color_or(item.shape_edge_color_1, color),
            shape_edge_color_or(item.shape_edge_color_2, color),
            shape_edge_color_or(item.shape_edge_color_3, color),
            shape_edge_color_or(item.shape_edge_color_4, color),
            shape_edge_color_or(item.shape_edge_color_5, color),
        },
        stroke)
}

//   Draw one cached advanced inline shape item.
draw_cached_inline_advanced_item :: #force_inline proc(
    style: dyncore.Dynview_Text_Style,
    item: core.Dynview_Layout_Item,
    item_x, item_y: f32,
    color: rl.Color) {

    switch item.kind {
    case .Inline_Pie_Section:
        draw_inline_pie_section_item(style, item, item_x, item_y, color)
    case .Inline_Perpendicular:
        stroke := max(1.0, item.inline_atom_stroke)
        inset := stroke * 0.5
        rect := rl.Rectangle{item_x + inset, item_y + inset,
            max(0.5, item.draw_width - stroke),
            max(0.5, item.draw_height - stroke)}
        draw_perpendicular_shape(
            rect,
            stroke,
            Perpendicular_Colors{item.brush_color, item.shape_edge_color_1})
    case .Inline_Triangle:
        draw_inline_triangle_item(item, item_x, item_y, color)
    case .Inline_Pentagon:
        draw_inline_pentagon_item(item, item_x, item_y, color)
    case .Text_Run, .Math_Glyph_Run, .Math_Block, .Script_Attach, .Frac,
         .Stretch_Delimiter, .Matrix, .Style_Override, .Stack, .Large_Op,
         .Accent_Bar, .Radical_Bar, .Inline_Line, .Inline_Box,
         .Inline_Circle, .Inline_Filled_Box, .Inline_Filled_Circle:
    }
}

//   Draw one cached inline shape item.
draw_cached_inline_item :: proc(
    style: dyncore.Dynview_Text_Style,
    item: core.Dynview_Layout_Item,
    item_x, item_y: f32) {

    color := dynlayout.inline_draw_color(style, item)
    switch item.kind {
    case .Inline_Line, .Inline_Box, .Inline_Circle:
        draw_cached_inline_basic_item(style, item, item_x, item_y, color)
    case .Inline_Filled_Box, .Inline_Filled_Circle:
        draw_cached_inline_filled_item(style, item, item_x, item_y, color)
    case .Inline_Pie_Section, .Inline_Perpendicular, .Inline_Triangle, .Inline_Pentagon:
        draw_cached_inline_advanced_item(style, item, item_x, item_y, color)
    case .Text_Run, .Math_Glyph_Run, .Math_Block, .Script_Attach, .Frac,
        .Stretch_Delimiter, .Matrix, .Style_Override, .Stack, .Large_Op,
        .Accent_Bar, .Radical_Bar:
    }
}

//   Draw one cached layout line and all its items.
draw_cached_line :: proc(
    ctx: Layout_Draw_Context,
    line: core.Dynview_Layout_Line,
    line_top, text_padding: f32) {

    runtime := ctx.runtime
    cache := &runtime^.compile_cache
    item_end := line.item_start + line.item_count
    for item_index in line.item_start..<item_end {
        item := runtime^.compile_cache.layout_items[item_index]
        style := dyncore.style_by_id(item.style_id)
        item_x := ctx.panel.x + text_padding +
            f32(item.col_start) * cache^.last_cell_width + item.content_offset_x
        item_y := line_top + f32(item.row_offset) * cache^.last_cell_height +
            item.content_offset_y

        if item.kind == .Text_Run ||
            item.kind == .Math_Block ||
            item.kind == .Math_Glyph_Run ||
            item.kind == .Script_Attach ||
            item.kind == .Frac ||
            item.kind == .Stretch_Delimiter ||
            item.kind == .Matrix ||
            item.kind == .Large_Op {
            draw_cached_text_item(ctx, style, item, item_x, item_y)
            continue
        }

        draw_cached_inline_item(style, item, item_x, item_y)
    }
}

//   Draw the canonical layout cache using explicit per-line baselines and offsets.
draw_cached_layout :: proc(
    ctx: Layout_Draw_Context,
    scroll_y, text_padding: f32) {

    runtime := ctx.runtime
    if runtime == nil {
        return
    }

    cache := &runtime^.compile_cache
    if !cache^.layout_is_valid {
        return
    }

    panel := ctx.panel
    panel_top := panel.y
    panel_bottom := panel.y + panel.height
    for line_index in 0..<cache^.layout_line_count {
        line := cache^.layout_lines[line_index]
        line_top := panel.y + text_padding +
            f32(line.row_start) * cache^.last_cell_height - scroll_y
        line_bottom := line_top + f32(line.row_span) * cache^.last_cell_height
        if layout_line_outside_panel(
            line_top,
            line_bottom,
            panel_top,
            panel_bottom) {
            continue
        }

        draw_cached_line(ctx, line, line_top, text_padding)
    }
}

