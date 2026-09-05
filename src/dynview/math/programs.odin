package dynview_math

import app_core "../../core"
import dyncore "../core"

//   Build one layout-like child item for the command kinds supported inside math blocks.
//   Uniform handler shape for building one math-program layout item.
Math_Program_Item_Handler :: #type proc(
    ctx: Math_Program_Item_Context) -> (app_core.Dynview_Layout_Item, bool)

//   Dispatch table mapping each recursive math command kind to its item builder.
//   Non-math kinds map to nil and are rejected by the caller.
MATH_PROGRAM_ITEM_HANDLERS :: [app_core.Dynview_Command_Kind]Math_Program_Item_Handler{
    .Begin_Block = nil, .End_Block = nil, .Copyable_Text_Run = nil, .Line_Break = nil,
    .Divider = nil, .Math_Block = nil, .Inline_Line = nil, .Inline_Box = nil,
    .Inline_Circle = nil, .Inline_Filled_Box = nil, .Inline_Filled_Circle = nil,
    .Inline_Pie_Section = nil, .Inline_Perpendicular = nil, .Inline_Triangle = nil,
    .Inline_Pentagon = nil,
    .Text_Run = math_program_text_item_entry,
    .Math_Glyph_Run = math_program_text_item_entry,
    .Script_Attach = math_program_script_item_entry,
    .Frac = math_program_recursive_fraction_item,
    .Stretch_Delimiter = math_program_recursive_stretch_delimiter_item,
    .Matrix = math_program_recursive_matrix_item,
    .Style_Override = math_program_recursive_style_override_item,
    .Stack = math_program_recursive_stack_item,
    .Large_Op = math_program_large_op_item_entry,
    .Accent_Bar = math_program_accent_item_entry,
    .Radical_Bar = math_program_recursive_radical_item,
}

//   Aggregated per-column and per-row cell metrics for one matrix layout.
Matrix_Cell_Dims :: struct {
    col_widths:  [16]f32,
    row_ascents: [16]f32,
    row_descents: [16]f32,
    top_pad:     f32,
    bottom_pad:  f32,
}

Script_Metrics :: struct {
    cols: int,
    scale, ascent, descent, top_pad, bottom_pad, advance, draw_width: f32,
}

Script_Metrics_Context :: struct {
    cache: ^app_core.Dynview_Compile_Cache,
    command: app_core.Dynview_Command,
    site: app_core.Dynview_Shaped_Site,
    text: string,
    style_id: i32,
    scale: f32,
    font_size: f32,
}

Script_Attach_Kerns :: struct {
    base_top_right: app_core.Font_Math_Kern_Table,
    base_bottom_right: app_core.Font_Math_Kern_Table,
    superscript_bottom_left: app_core.Font_Math_Kern_Table,
    subscript_top_left: app_core.Font_Math_Kern_Table,
}

Math_Measure_Context :: struct {
    cache: ^app_core.Dynview_Compile_Cache,
    buffer: ^app_core.Dynview_Command_Buffer,
    font_size: f32,
    math_style: Math_Style,
}

Math_Program_Item_Context :: struct {
    cache: ^app_core.Dynview_Compile_Cache,
    buffer: ^app_core.Dynview_Command_Buffer,
    cmd: app_core.Dynview_Command,
    style: dyncore.Dynview_Text_Style,
    font_size: f32,
    command_index: int,
    math_style: Math_Style,
    delimiter_target_height: f32,
}

Math_Program_Metrics :: struct {
    width, advance, ascent, descent, top_pad, bottom_pad: f32,
    italic_correction, top_accent_attachment: f32,
    first_glyph_id, last_glyph_id: u32,
    has_edge_glyphs: bool,
}

Stretch_Delimiter_Item_Geometry :: struct {
    selected: Stretch_Delimiter_Selection,
    left_clearance, right_clearance: f32,
    content_width, axis: f32,
    generation: u64,
    scale: f32,
}

Large_Op_Variant_Result :: struct {
    geometry: Math_Operator_Geometry,
    selected: Math_Operator_Variant,
    run: ^app_core.Dynview_Shaped_Run,
    generation: u64,
    font_size: f32,
}

Large_Op_Glyph_Metrics :: struct {
    width, ascent, descent: f32,
}

Stretch_Delimiter_Content :: struct {
    width, ascent, descent, top_pad, bottom_pad: f32,
}

Stack_Item_Geometry :: struct {
    top_x, top_baseline, bottom_x, bottom_baseline: f32,
    width, ascent, descent: f32,
    operator_limits: i32,
}

Radical_Geometry :: struct {
    draw_width, ascent, descent, top_pad, bottom_pad: f32,
}

Fraction_Item_Metrics :: struct {
    numerator, denominator: ^app_core.Dynview_Math_Program,
    draw_width, ascent, descent, visual_pad: f32,
    geometry: Math_Fraction_Geometry,
}

Fraction_Layout_Context :: struct {
    cache: ^app_core.Dynview_Compile_Cache,
    numerator, denominator: ^app_core.Dynview_Math_Program,
    command: app_core.Dynview_Command,
    style: dyncore.Dynview_Text_Style,
    font_size: f32,
    math_style: Math_Style,
}

Script_Attach_Metrics :: struct {
    scale, draw_width, ascent, descent, top_pad, bottom_pad: f32,
    geometry: Math_Script_Geometry,
    base_first_glyph_id, base_last_glyph_id: u32,
    sup_first_glyph_id, sub_first_glyph_id: u32,
    base_has_edge_glyphs: bool,
}

Script_Attach_Context :: struct {
    cache: ^app_core.Dynview_Compile_Cache,
    buffer: ^app_core.Dynview_Command_Buffer,
    child: ^app_core.Dynview_Math_Program,
    command: app_core.Dynview_Command,
    font_size, script_scale: f32,
    math_style: Math_Style,
}

Script_Attach_Children :: struct {
    superscript, subscript: Script_Metrics,
    superscript_program, subscript_program: ^app_core.Dynview_Math_Program,
}

Large_Op_Metrics :: struct {
    scale, draw_width, ascent, descent, top_pad, bottom_pad: f32,
}

Matrix_Item_Metrics :: struct {
    rows, cols: int,
    draw_width, total_height, axis_height, top_pad, bottom_pad: f32,
}

Stretch_Delimiter_Dimensions :: struct {
    font_size, content_height, content_width: f32,
}

Matrix_Program :: struct {
    program: ^app_core.Dynview_Math_Program,
    descriptor: ^app_core.Dynview_Math_Table_Descriptor,
    rows, cols: int,
}

Radical_Geometry_Context :: struct {
    cache: ^app_core.Dynview_Compile_Cache,
    buffer: ^app_core.Dynview_Command_Buffer,
    child: ^app_core.Dynview_Math_Program,
    cmd: app_core.Dynview_Command,
    style: dyncore.Dynview_Text_Style,
    font_size: f32,
}

Stretch_Delimiter_Selection :: struct {
    constructions: [2]app_core.Font_Math_Stretch_Construction,
    widths, origins, vertical_origins: [2]f32,
    half_heights: [2]f32,
    raster_ascent: f32,
    ok: bool,
}

Math_Stretch_Vertical_Bounds :: struct {
    top, bottom: f32,
    valid: bool,
}

Radical_Math_Metrics :: struct {
    gap, rule, extra, before_degree, after_degree: f32,
    degree_raise_percent: f32,
    ok: bool,
}

Radical_Construction_Geometry :: struct {
    construction: app_core.Font_Math_Stretch_Construction,
    raster_ascent, scale, surd_x, surd_left, surd_width: f32,
    surd_bottom: f32,
    content_width, child_ascent, child_descent: f32,
    degree_width, degree_descent, degree_baseline: f32,
    metrics: Radical_Math_Metrics,
    generation: u64,
    valid: bool,
}

Radical_Degree_Dimensions :: struct {
    width, descent: f32,
}

Radical_Construction_Input :: struct {
    selected: app_core.Font_Math_Stretch_Construction,
    source: app_core.Font_Math_Stretch_Source,
    child: ^app_core.Dynview_Math_Program,
    metrics: Radical_Math_Metrics,
    bounds: Math_Stretch_Vertical_Bounds,
    degree: Radical_Degree_Dimensions,
    scale, left, right: f32,
    generation: u64,
}

//   Resolve optical interior gaps from one delimiter's structural atom role.
stretch_delimiter_clearances :: #force_inline proc(
    cmd: app_core.Dynview_Command,
    font_size: f32) -> (left, right: f32) {

    clearance := stretch_delimiter_content_clearance(font_size)
    if cmd.math_program_id > 0 {
        return clearance if cmd.accent_mode != DELIMITER_KIND_NONE else 0,
            clearance if cmd.radical_mode != DELIMITER_KIND_NONE else 0
    }
    switch cmd.math_atom_class {
    case .Open:
        left = clearance if cmd.accent_mode != DELIMITER_KIND_NONE else 0
    case .Close:
        right = clearance if cmd.radical_mode != DELIMITER_KIND_NONE else 0
    case .None, .Ord, .Op, .Bin, .Rel, .Punct, .Inner:
    }
    return
}

//   Measure one child program under an explicit scoped math style.
math_program_recursive_style_override_item :: proc(
    ctx: Math_Program_Item_Context) -> (app_core.Dynview_Layout_Item, bool) {

    target_level := int(ctx.cmd.radical_mode)
    if target_level < int(Math_Style_Level.Display) ||
        target_level > int(Math_Style_Level.Script_Script) {
        return {}, false
    }
    child, ok := math_program_from_command(ctx.cache, ctx.cmd)
    if !ok {
        return {}, false
    }
    target := Math_Style{Math_Style_Level(target_level), false}
    target_size := math_target_font_size(
        ctx.cache, ctx.font_size, ctx.math_style, target)
    if !measure_math_program(ctx.cache, ctx.buffer, child, target_size, target) {
        return {}, false
    }
    return app_core.Dynview_Layout_Item{
        kind = .Style_Override,
        style_id = ctx.cmd.style_id,
        math_program_id = ctx.cmd.math_program_id,
        radical_mode = ctx.cmd.radical_mode,
        draw_width = child^.draw_width,
        draw_height = child^.ascent + child^.descent,
        ascent = child^.ascent,
        descent = child^.descent,
        visual_padding_top = child^.visual_padding_top,
        visual_padding_bottom = child^.visual_padding_bottom,
    }, true
}

//   Resolve a child style and its font size relative to the current style.
math_child_font_size :: proc(
    cache: ^app_core.Dynview_Compile_Cache,
    font_size: f32,
    style: Math_Style,
    role: Math_Child_Style_Role) -> (Math_Style, f32) {

    child_style := math_child_style(style, role)
    current_scale, current_ok := math_style_scale(cache^.math_constants,
        cache^.shaped_font_generation, style)
    child_scale, child_ok := math_style_scale(cache^.math_constants,
        cache^.shaped_font_generation, child_style)
    if !current_ok || !child_ok || current_scale <= 0 {
        return child_style, font_size
    }
    return child_style, font_size * child_scale / current_scale
}

//   Resolve an explicit target math style and font size from a parent style.
math_target_font_size :: proc(
    cache: ^app_core.Dynview_Compile_Cache,
    font_size: f32,
    parent, target: Math_Style) -> f32 {

    parent_scale, parent_ok := math_style_scale(cache^.math_constants,
        cache^.shaped_font_generation, parent)
    target_scale, target_ok := math_style_scale(cache^.math_constants,
        cache^.shaped_font_generation, target)
    if !parent_ok || !target_ok || parent_scale <= 0 {
        return font_size
    }
    return font_size * target_scale / parent_scale
}

//   Build the recursive measurement context selected by one table descriptor.
matrix_cell_measure_context :: proc(
    ctx: Math_Program_Item_Context,
    descriptor: ^app_core.Dynview_Math_Table_Descriptor) -> Math_Measure_Context {

    cell_style := Math_Style{Math_Style_Level(descriptor^.cell_style), false}
    cell_font_size := math_target_font_size(
        ctx.cache, ctx.font_size, ctx.math_style, cell_style)
    return {ctx.cache, ctx.buffer, cell_font_size, cell_style}
}

//   Measure script text and its scaled typography for a recursive math item.
script_metrics :: #force_inline proc(
    ctx: Script_Metrics_Context) -> Script_Metrics {

    resolved_scale := max(0.2, ctx.scale)
    style := dyncore.style_by_id(ctx.style_id)
    scaled_font_size := max(1.0, ctx.font_size * resolved_scale)
    ascent, descent := dyncore.style_ascent_descent(style, scaled_font_size)
    top_pad, bottom_pad := script_visual_padding(scaled_font_size)
    metrics := Script_Metrics{
        cols = dyncore.text_codepoint_count_span(ctx.text, 0, len(ctx.text)),
        scale = resolved_scale,
        ascent = ascent,
        descent = descent,
        top_pad = top_pad,
        bottom_pad = bottom_pad,
        advance = dyncore.effective_advance(
            style, ctx.cache^.last_cell_width) * resolved_scale,
    }
    metrics.draw_width = f32(metrics.cols) * metrics.advance
    run, shaped := shaped_run_for_command(ctx.cache, ctx.command, ctx.site)
    shaped_metrics, measured := shaped_run_layout_metrics(run, scaled_font_size)
    if shaped && measured {
        metrics.ascent = shaped_metrics.ascent
        metrics.descent = shaped_metrics.descent
        metrics.advance = shaped_metrics.advance
        metrics.draw_width = shaped_metrics.draw_width
    }
    return metrics
}

// Reset a cache structure for the dynview layout engine
layout_reset_cache :: proc(cache: ^app_core.Dynview_Compile_Cache) {
    cache^.layout_lines = nil
    cache^.layout_items = nil
    cache^.layout_line_builder = {}
    cache^.layout_item_builder = {}
    cache^.layout_line_count = 0
    cache^.layout_item_count = 0
    cache^.layout_total_height = 0
    cache^.layout_average_line_height = 0
    cache^.layout_is_valid = false
}

//   Return one precomputed math program slot when the command references a valid id.
math_program_from_command :: #force_inline proc(
    cache: ^app_core.Dynview_Compile_Cache,
    cmd: app_core.Dynview_Command) -> (^app_core.Dynview_Math_Program, bool) {

    program_id := int(cmd.math_program_id)
    if cache == nil || program_id < 0 || program_id >= cache^.math_program_count {
        return nil, false
    }

    program := &cache^.math_programs[program_id]
    if !program^.valid {
        return nil, false
    }

    return program, true
}

//   Return one precomputed child math program slot from a math-command reference.
math_program_from_id :: #force_inline proc(
    cache: ^app_core.Dynview_Compile_Cache,
    program_id: i32) -> (^app_core.Dynview_Math_Program, bool) {

    index := int(program_id)
    if cache == nil || index < 0 || index >= cache^.math_program_count {
        return nil, false
    }

    program := &cache^.math_programs[index]
    if !program^.valid {
        return nil, false
    }

    return program, true
}

//   Return the next non-glue command index in one direction, or -1 at the edge.
math_program_neighbor_atom_index :: proc(
    cache: ^app_core.Dynview_Compile_Cache,
    program: app_core.Dynview_Math_Program,
    command_index, direction: int) -> int {

    lower := program.command_start
    upper := lower + program.command_count
    index := command_index + direction
    for index >= lower && index < upper {
        if cache^.math_commands[index].math_glue_kind == .None {
            return index
        }
        index += direction
    }
    return -1
}

//   Return whether a left neighbor forces a binary atom to ordinary class.
math_bin_left_cancels :: #force_inline proc(
    atom: app_core.Dynview_Math_Atom_Class) -> bool {

    return atom == .None || atom == .Bin || atom == .Op || atom == .Rel ||
        atom == .Open || atom == .Punct
}

//   Return whether a right neighbor forces a binary atom to ordinary class.
math_bin_right_cancels :: #force_inline proc(
    atom: app_core.Dynview_Math_Atom_Class) -> bool {

    return atom == .None || atom == .Rel || atom == .Close || atom == .Punct
}

//   Resolve one command's atom class after TeX binary-operator cancellation.
math_program_effective_atom_class :: proc(
    cache: ^app_core.Dynview_Compile_Cache,
    program: app_core.Dynview_Math_Program,
    command_index: int) -> app_core.Dynview_Math_Atom_Class {

    atom := cache^.math_commands[command_index].math_atom_class
    if atom != .Bin {
        return atom
    }
    previous := math_program_neighbor_atom_index(cache, program, command_index, -1)
    next := math_program_neighbor_atom_index(cache, program, command_index, 1)
    previous_atom: app_core.Dynview_Math_Atom_Class = .None if previous < 0 else
        cache^.math_commands[previous].math_atom_class
    next_atom: app_core.Dynview_Math_Atom_Class = .None if next < 0 else
        cache^.math_commands[next].math_atom_class
    return .Ord if math_bin_left_cancels(previous_atom) ||
        math_bin_right_cancels(next_atom) else .Bin
}

//   Convert one explicit glue kind to math units.
math_explicit_glue_mu :: #force_inline proc(
    glue: app_core.Dynview_Math_Glue_Kind) -> f32 {

    switch glue {
    case .Thick:
        return 5
    case .Space:
        return 6
    case .Negative_Thin:
        return -3
    case .Quad:
        return 18
    case .Thin:
        return 3
    case .None:
        return 0
    }
    return 0
}

//   Return display-style TeX spacing in mu for one adjacent atom-class pair.
math_atom_spacing_mu :: proc(
    left, right: app_core.Dynview_Math_Atom_Class) -> f32 {

    spacing := [9][9]f32{
        {0, 0, 0, 0, 0, 0, 0, 0, 0},
        {0, 0, 3, 4, 5, 0, 0, 0, 3},
        {0, 3, 3, 0, 5, 0, 0, 0, 3},
        {0, 4, 4, 0, 0, 4, 0, 0, 4},
        {0, 5, 5, 0, 0, 5, 0, 0, 5},
        {0, 0, 0, 0, 0, 0, 0, 0, 0},
        {0, 0, 3, 4, 5, 0, 0, 0, 3},
        {0, 3, 3, 0, 3, 3, 3, 3, 3},
        {0, 3, 3, 4, 5, 3, 0, 3, 3},
    }
    return spacing[int(left)][int(right)]
}

//   Resolve leading semantic spacing for one command at the requested font size.
math_program_command_leading_space :: proc(
    cache: ^app_core.Dynview_Compile_Cache,
    program: app_core.Dynview_Math_Program,
    command_index: int,
    font_size: f32) -> f32 {

    command := cache^.math_commands[command_index]
    if command.math_glue_kind != .None {
        return math_explicit_glue_mu(command.math_glue_kind) * font_size / 18.0
    }
    previous := math_program_neighbor_atom_index(cache, program, command_index, -1)
    if previous < 0 {
        return 0
    }
    left := math_program_effective_atom_class(cache, program, previous)
    right := math_program_effective_atom_class(cache, program, command_index)
    return math_atom_spacing_mu(left, right) * font_size / 18.0
}

//   Return one secondary child math program from a command reference.
secondary_math_program_from_command :: #force_inline proc(
    cache: ^app_core.Dynview_Compile_Cache,
    cmd: app_core.Dynview_Command) -> (^app_core.Dynview_Math_Program, bool) {

    return math_program_from_id(cache, cmd.secondary_math_program_id)
}

//   Publish shaped run metrics and edge glyph identities to one text item.
math_program_apply_shaped_text_metrics :: proc(
    item: ^app_core.Dynview_Layout_Item,
    cache: ^app_core.Dynview_Compile_Cache,
    run: ^app_core.Dynview_Shaped_Run,
    metrics: Shaped_Run_Layout_Metrics) {

    item^.draw_width = metrics.draw_width
    item^.math_advance = metrics.advance
    item^.draw_height = metrics.ascent + metrics.descent
    item^.ascent = metrics.ascent
    item^.descent = metrics.descent
    item^.italic_correction = metrics.italic_correction
    item^.top_accent_attachment = metrics.top_accent_attachment
    glyphs, glyphs_ok := shaped_glyphs_for_run(cache, run)
    if glyphs_ok {
        item^.math_first_glyph_id = glyphs[0].glyph_id
        item^.math_last_glyph_id = glyphs[len(glyphs)-1].glyph_id
        item^.math_has_edge_glyphs = true
    }
}

//   Build one layout-like item for a text or math-glyph child command inside a math block.
math_program_text_item :: #force_inline proc(
    cache: ^app_core.Dynview_Compile_Cache,
    buffer: ^app_core.Dynview_Command_Buffer,
    cmd: app_core.Dynview_Command,
    style: dyncore.Dynview_Text_Style,
    font_size: f32) -> app_core.Dynview_Layout_Item {

    text := dyncore.text_for_command(buffer, cmd)
    cols := max(1, dyncore.text_codepoint_count_span(text, 0, len(text)))
    ascent, descent := dyncore.style_ascent_descent(style, font_size)
    kind := app_core.Dynview_Layout_Item_Kind.Math_Glyph_Run if
        cmd.kind == .Math_Glyph_Run else .Text_Run
    if cmd.math_glue_kind != .None {
        return {kind = kind, style_id = cmd.style_id}
    }

    item := app_core.Dynview_Layout_Item{
        kind = kind,
        style_id = cmd.style_id,
        text_offset = cmd.text_offset,
        text_len = cmd.text_len,
        draw_width = f32(cols) * dyncore.effective_advance(style, cache^.last_cell_width),
        draw_height = ascent + descent,
        ascent = ascent,
        descent = descent,
    }
    run, shaped := shaped_run_for_command(cache, cmd, .Primary)
    metrics, measured := shaped_run_layout_metrics(run, font_size)
    if cmd.kind == .Math_Glyph_Run && shaped && measured {
        math_program_apply_shaped_text_metrics(&item, cache, run, metrics)
    }
    return item
}

//   Build one layout-like item for a recursive script wrapper around a child math program.
script_attach_item :: #force_inline proc(
    cmd: app_core.Dynview_Command,
    metrics: Script_Attach_Metrics) -> app_core.Dynview_Layout_Item {

    return app_core.Dynview_Layout_Item{
        kind = .Script_Attach,
        style_id = cmd.style_id,
        math_program_id = cmd.math_program_id,
        secondary_math_program_id = cmd.secondary_math_program_id,
        tertiary_math_program_id = cmd.tertiary_math_program_id,
        script_sup_text_offset = cmd.script_sup_text_offset,
        script_sup_text_len = cmd.script_sup_text_len,
        script_sub_text_offset = cmd.script_sub_text_offset,
        script_sub_text_len = cmd.script_sub_text_len,
        script_style_id = cmd.script_style_id, script_scale = metrics.scale,
        script_sup_raise = cmd.script_sup_raise, script_sub_drop = cmd.script_sub_drop,
        script_gap = cmd.script_gap,
        script_sup_x = metrics.geometry.superscript_x,
        script_sup_baseline = metrics.geometry.superscript_baseline,
        script_sub_x = metrics.geometry.subscript_x,
        script_sub_baseline = metrics.geometry.subscript_baseline,
        script_space_after = metrics.geometry.space_after,
        script_geometry_valid = metrics.geometry.valid,
        math_first_glyph_id = metrics.base_first_glyph_id,
        math_last_glyph_id = metrics.base_last_glyph_id,
        math_has_edge_glyphs = metrics.base_has_edge_glyphs,
        script_base_glyph_id = metrics.base_last_glyph_id,
        script_sup_glyph_id = metrics.sup_first_glyph_id,
        script_sub_glyph_id = metrics.sub_first_glyph_id,
        draw_width = metrics.draw_width,
        math_advance = metrics.draw_width,
        draw_height = metrics.ascent + metrics.descent,
        ascent = metrics.ascent, descent = metrics.descent,
        visual_padding_top = metrics.top_pad,
        visual_padding_bottom = metrics.bottom_pad,
    }
}

//   Extend a measured child width by any visible attached scripts.
script_attach_draw_width :: proc(
    child: ^app_core.Dynview_Math_Program,
    cmd: app_core.Dynview_Command,
    font_size: f32,
    sup: Script_Metrics,
    sub: Script_Metrics) -> f32 {
    if max(sup.cols, sub.cols) <= 0 {
        return child^.draw_width
    }
    script_width := max(sup.draw_width, sub.draw_width)
    italic_correction := child^.italic_correction if sup.cols > 0 else 0
    return child^.draw_width + max(1.0, cmd.script_gap * font_size) +
        italic_correction + script_width
}

//   Replace fallback script metrics with one measured recursive program.
recursive_script_metrics :: proc(
    cache: ^app_core.Dynview_Compile_Cache,
    program_id: i32,
    fallback: Script_Metrics) -> Script_Metrics {

    if program_id <= 0 {
        return fallback
    }
    program, found := math_program_from_id(cache, program_id)
    if !found {
        return fallback
    }
    return {
        cols = 1,
        scale = fallback.scale,
        ascent = program^.ascent,
        descent = program^.descent,
        top_pad = program^.visual_padding_top,
        bottom_pad = program^.visual_padding_bottom,
        draw_width = program^.draw_width,
    }
}

//   Resolve the four edge-glyph kern tables used by script attachment.
script_attach_kerns :: proc(
    ctx: Script_Attach_Context,
    children: Script_Attach_Children) -> Script_Attach_Kerns {

    result: Script_Attach_Kerns
    result.base_top_right, _ = math_kern_table_for_glyph(
        ctx.cache, ctx.child^.last_glyph_id, 0)
    result.base_bottom_right, _ = math_kern_table_for_glyph(
        ctx.cache, ctx.child^.last_glyph_id, 2)
    sup_glyph := script_attach_first_glyph(ctx, children, true)
    sub_glyph := script_attach_first_glyph(ctx, children, false)
    result.superscript_bottom_left, _ = math_kern_table_for_glyph(
        ctx.cache, sup_glyph, 3)
    result.subscript_top_left, _ = math_kern_table_for_glyph(
        ctx.cache, sub_glyph, 1)
    return result
}

//   Resolve exact MATH script geometry from measured base and child boxes.
script_attach_math_geometry :: proc(
    ctx: Script_Attach_Context,
    children: Script_Attach_Children) -> Math_Script_Geometry {

    kerns := script_attach_kerns(ctx, children)
    return math_script_geometry({
        constants = ctx.cache^.math_constants,
        generation = ctx.cache^.shaped_font_generation,
        font_size = ctx.font_size,
        script_font_size = ctx.font_size * ctx.script_scale,
        style = ctx.math_style,
        base = {
            width = ctx.child^.draw_width,
            advance = ctx.child^.advance,
            ascent = ctx.child^.ascent,
            descent = ctx.child^.descent,
        },
        superscript = {
            width = children.superscript.draw_width,
            ascent = children.superscript.ascent,
            descent = children.superscript.descent,
        },
        subscript = {
            width = children.subscript.draw_width,
            ascent = children.subscript.ascent,
            descent = children.subscript.descent,
        },
        italic_correction = ctx.child^.italic_correction,
        base_top_right = kerns.base_top_right,
        base_bottom_right = kerns.base_bottom_right,
        superscript_bottom_left = kerns.superscript_bottom_left,
        subscript_top_left = kerns.subscript_top_left,
        has_superscript = children.superscript.cols > 0,
        has_subscript = children.subscript.cols > 0,
    })
}

//   Resolve one recursive or directly shaped script's first edge glyph.
script_attach_first_glyph :: proc(
    ctx: Script_Attach_Context,
    children: Script_Attach_Children,
    superscript: bool) -> u32 {

    if superscript {
        if children.superscript_program != nil &&
            children.superscript_program^.has_edge_glyphs {
            return children.superscript_program^.first_glyph_id
        }
        return script_site_first_glyph(
            ctx.cache, ctx.command, .Superscript)
    }
    if children.subscript_program != nil &&
        children.subscript_program^.has_edge_glyphs {
        return children.subscript_program^.first_glyph_id
    }
    return script_site_first_glyph(ctx.cache, ctx.command, .Subscript)
}

//   Return the first sealed glyph identity for one shaped command site.
script_site_first_glyph :: #force_inline proc(
    cache: ^app_core.Dynview_Compile_Cache,
    command: app_core.Dynview_Command,
    site: app_core.Dynview_Shaped_Site) -> u32 {

    run, run_ok := shaped_run_for_command(cache, command, site)
    glyphs, glyphs_ok := shaped_glyphs_for_run(cache, run)
    if !run_ok || !glyphs_ok {
        return 0
    }
    return glyphs[0].glyph_id
}

//   Copy recursive or shaped edge glyph identities into one script result.
script_attach_preserve_glyphs :: #force_inline proc(
    metrics: ^Script_Attach_Metrics,
    ctx: Script_Attach_Context,
    children: Script_Attach_Children) {

    metrics^.base_first_glyph_id = ctx.child^.first_glyph_id
    metrics^.base_last_glyph_id = ctx.child^.last_glyph_id
    metrics^.base_has_edge_glyphs = ctx.child^.has_edge_glyphs
    metrics^.sup_first_glyph_id = script_attach_first_glyph(ctx, children, true)
    metrics^.sub_first_glyph_id = script_attach_first_glyph(ctx, children, false)
}

//   Build stored positions for the explicit heuristic fallback path.
script_attach_fallback_geometry :: #force_inline proc(
    ctx: Script_Attach_Context,
    offsets: Script_Draw_Offsets) -> Math_Script_Geometry {

    script_x := ctx.child^.draw_width +
        max(1.0, ctx.command.script_gap * ctx.font_size)
    return {
        superscript_x = script_x + ctx.child^.italic_correction,
        superscript_baseline = -offsets.sup_raise_px,
        subscript_x = script_x,
        subscript_baseline = offsets.sub_drop_px,
    }
}

//   Measure flat or recursive superscript and subscript children.
script_attach_children :: proc(
    ctx: Script_Attach_Context,
    scale: f32) -> Script_Attach_Children {

    cmd := ctx.command
    result := Script_Attach_Children{}
    result.superscript = script_metrics({ctx.cache, cmd, .Superscript,
        dyncore.text_span_from_buffer(ctx.buffer, cmd.script_sup_text_offset,
            cmd.script_sup_text_len), cmd.script_style_id, scale, ctx.font_size})
    result.subscript = script_metrics({ctx.cache, cmd, .Subscript,
        dyncore.text_span_from_buffer(ctx.buffer, cmd.script_sub_text_offset,
            cmd.script_sub_text_len), cmd.script_style_id, scale, ctx.font_size})
    if cmd.secondary_math_program_id > 0 {
        result.superscript_program, _ = math_program_from_id(
            ctx.cache, cmd.secondary_math_program_id)
    }
    if cmd.tertiary_math_program_id > 0 {
        result.subscript_program, _ = math_program_from_id(
            ctx.cache, cmd.tertiary_math_program_id)
    }
    result.superscript = recursive_script_metrics(
        ctx.cache, cmd.secondary_math_program_id, result.superscript)
    result.subscript = recursive_script_metrics(
        ctx.cache, cmd.tertiary_math_program_id, result.subscript)
    return result
}

//   Build script metrics from valid OpenType MATH geometry.
script_attach_valid_metrics :: proc(
    ctx: Script_Attach_Context,
    children: Script_Attach_Children,
    geometry: Math_Script_Geometry,
    scale: f32) -> Script_Attach_Metrics {

    result := Script_Attach_Metrics{
        scale = scale,
        draw_width = geometry.width,
        ascent = geometry.ascent,
        descent = geometry.descent,
        top_pad = max(ctx.child^.visual_padding_top, children.superscript.top_pad),
        bottom_pad = max(ctx.child^.visual_padding_bottom, children.subscript.bottom_pad),
        geometry = geometry,
    }
    script_attach_preserve_glyphs(&result, ctx, children)
    return result
}

//   Build script metrics through the explicit heuristic fallback path.
script_attach_fallback_metrics :: proc(
    ctx: Script_Attach_Context,
    children: Script_Attach_Children,
    scale: f32) -> Script_Attach_Metrics {

    offsets := script_draw_offsets(ctx.font_size, scale,
        ctx.command.script_sup_raise, ctx.command.script_sub_drop)
    ascent := ctx.child^.ascent
    descent := ctx.child^.descent
    if children.superscript.cols > 0 {
        ascent = max(ascent, children.superscript.ascent +
            offsets.sup_raise_px + children.superscript.top_pad)
    }
    if children.subscript.cols > 0 {
        descent = max(descent, children.subscript.descent +
            offsets.sub_drop_px + children.subscript.bottom_pad)
    }
    result := Script_Attach_Metrics{
        scale = scale,
        draw_width = script_attach_draw_width(ctx.child, ctx.command, ctx.font_size,
            children.superscript, children.subscript),
        ascent = ascent,
        descent = descent,
        top_pad = max(ctx.child^.visual_padding_top, children.superscript.top_pad),
        bottom_pad = max(ctx.child^.visual_padding_bottom, children.subscript.bottom_pad),
        geometry = script_attach_fallback_geometry(ctx, offsets),
    }
    script_attach_preserve_glyphs(&result, ctx, children)
    return result
}

//   Calculate script placement dimensions around an already measured child program.
script_attach_metrics :: proc(
    ctx: Script_Attach_Context) -> Script_Attach_Metrics {

    resolved_scale := max(0.2, ctx.script_scale)
    children := script_attach_children(ctx, resolved_scale)
    geometry := script_attach_math_geometry(ctx, children)
    if geometry.valid {
        return script_attach_valid_metrics(
            ctx, children, geometry, resolved_scale)
    }
    return script_attach_fallback_metrics(ctx, children, resolved_scale)
}

//   Build one layout-like item for a recursive script wrapper around a child math program.
math_program_recursive_script_item :: #force_inline proc(
    cache: ^app_core.Dynview_Compile_Cache,
    buffer: ^app_core.Dynview_Command_Buffer,
    cmd: app_core.Dynview_Command,
    font_size: f32,
    math_style: Math_Style) -> (app_core.Dynview_Layout_Item, bool) {

    child_program, ok := math_program_from_id(cache, cmd.math_program_id)
    if !ok || !measure_math_program(cache, buffer, child_program, font_size, math_style) {
        return app_core.Dynview_Layout_Item{}, false
    }
    sup_style, sup_size := math_child_font_size(
        cache, font_size, math_style, .Superscript)
    sub_style, sub_size := math_child_font_size(
        cache, font_size, math_style, .Subscript)
    if cmd.secondary_math_program_id > 0 {
        sup_program, sup_ok := math_program_from_id(
            cache, cmd.secondary_math_program_id)
        if !sup_ok || !measure_math_program(
            cache, buffer, sup_program, sup_size, sup_style) {
            return app_core.Dynview_Layout_Item{}, false
        }
    }
    if cmd.tertiary_math_program_id > 0 {
        sub_program, sub_ok := math_program_from_id(cache, cmd.tertiary_math_program_id)
        if !sub_ok || !measure_math_program(
            cache, buffer, sub_program, sub_size, sub_style) {
            return app_core.Dynview_Layout_Item{}, false
        }
    }

    return script_attach_item(cmd, script_attach_metrics({cache, buffer,
        child_program, cmd, font_size, sup_size / font_size, math_style})), true
}

//   Build one layout-like item for a display-style large operator with stacked limits.
large_op_item :: #force_inline proc(
    cmd: app_core.Dynview_Command,
    metrics: Large_Op_Metrics) -> app_core.Dynview_Layout_Item {

    return app_core.Dynview_Layout_Item{
        kind = .Large_Op, style_id = cmd.style_id, text_offset = cmd.text_offset,
        text_len = cmd.text_len, script_sup_text_offset = cmd.script_sup_text_offset,
        script_sup_text_len = cmd.script_sup_text_len,
        script_sub_text_offset = cmd.script_sub_text_offset,
        script_sub_text_len = cmd.script_sub_text_len,
        script_style_id = cmd.script_style_id, script_scale = metrics.scale,
        secondary_math_program_id = cmd.secondary_math_program_id,
        tertiary_math_program_id = cmd.tertiary_math_program_id,
        script_gap = cmd.script_gap, large_op_kind = cmd.large_op_kind,
        operator_growth = cmd.operator_growth,
        operator_limits = cmd.operator_limits,
        draw_width = metrics.draw_width, draw_height = metrics.ascent + metrics.descent,
        ascent = metrics.ascent, descent = metrics.descent,
        visual_padding_top = metrics.top_pad, visual_padding_bottom = metrics.bottom_pad,
    }
}

//   Resolve synthetic or shaped glyph dimensions for one large operator.
large_op_glyph_metrics :: proc(
    cache: ^app_core.Dynview_Compile_Cache,
    buffer: ^app_core.Dynview_Command_Buffer,
    cmd: app_core.Dynview_Command,
    style: dyncore.Dynview_Text_Style,
    font_size: f32) -> Large_Op_Glyph_Metrics {
    glyph_scale := large_op_glyph_scale(cmd.large_op_kind)
    ascent, descent := dyncore.style_ascent_descent(
        style, max(1.0, font_size * glyph_scale))
    text := dyncore.text_for_command(buffer, cmd)
    cols := max(1, dyncore.text_codepoint_count_span(text, 0, len(text)))
    width := f32(cols) *
        dyncore.effective_advance(style, cache^.last_cell_width) * glyph_scale
    run, shaped := shaped_run_for_command(cache, cmd, .Primary)
    metrics, measured := shaped_run_layout_metrics(run, font_size * glyph_scale)
    if shaped && measured {
        return {metrics.draw_width, metrics.ascent, metrics.descent}
    }
    return {width, ascent, descent}
}

//   Replace one textual limit box with its measured recursive program.
large_op_resolve_program_metrics :: proc(
    cache: ^app_core.Dynview_Compile_Cache,
    program_id: i32,
    metrics: ^Script_Metrics,
    superscript: bool) {

    if program_id <= 0 {
        return
    }
    program, found := math_program_from_id(cache, program_id)
    if !found {
        return
    }
    metrics^.cols = 1
    metrics^.draw_width = program^.draw_width
    metrics^.ascent = program^.ascent
    metrics^.descent = program^.descent
    if superscript {
        metrics^.top_pad = program^.visual_padding_top
    } else {
        metrics^.bottom_pad = program^.visual_padding_bottom
    }
}

//   Calculate glyph and stacked-limit dimensions for one large operator.
large_op_metrics :: proc(
    ctx: Math_Program_Item_Context,
    limit_scale: f32) -> Large_Op_Metrics {

    resolved_scale := max(0.2, limit_scale)
    sup := script_metrics({ctx.cache, ctx.cmd, .Superscript,
        dyncore.text_span_from_buffer(ctx.buffer, ctx.cmd.script_sup_text_offset,
            ctx.cmd.script_sup_text_len),
        ctx.cmd.script_style_id, resolved_scale, ctx.font_size})
    sub := script_metrics({ctx.cache, ctx.cmd, .Subscript,
        dyncore.text_span_from_buffer(ctx.buffer, ctx.cmd.script_sub_text_offset,
            ctx.cmd.script_sub_text_len),
        ctx.cmd.script_style_id, resolved_scale, ctx.font_size})
    large_op_resolve_program_metrics(
        ctx.cache, ctx.cmd.secondary_math_program_id, &sup, true)
    large_op_resolve_program_metrics(
        ctx.cache, ctx.cmd.tertiary_math_program_id, &sub, false)
    glyph := large_op_glyph_metrics(
        ctx.cache, ctx.buffer, ctx.cmd, ctx.style, ctx.font_size)
    gap := large_op_limit_gap_for_kind(
        ctx.cmd.large_op_kind, ctx.font_size, ctx.cmd.script_gap)
    ascent := glyph.ascent if sup.cols == 0 else
        glyph.ascent + sup.ascent + sup.descent + gap
    descent := glyph.descent if sub.cols == 0 else
        glyph.descent + sub.ascent + sub.descent + gap
    return {
        scale = resolved_scale,
        draw_width = max(glyph.width, max(sup.draw_width, sub.draw_width)),
        ascent = ascent, descent = descent,
        top_pad = sup.top_pad, bottom_pad = sub.bottom_pad,
    }
}

//   Build one layout-like item for a display-style large operator with stacked limits.
math_program_large_op_item :: #force_inline proc(
    ctx: Math_Program_Item_Context,
    limit_scale: f32) -> app_core.Dynview_Layout_Item {

    return large_op_item(ctx.cmd, large_op_metrics(ctx, limit_scale))
}

//   Resolve measured superscript and subscript boxes for operator geometry.
large_op_script_boxes :: proc(
    cache: ^app_core.Dynview_Compile_Cache,
    buffer: ^app_core.Dynview_Command_Buffer,
    cmd: app_core.Dynview_Command,
    font_size: f32,
    math_style: Math_Style) -> (Script_Box_Metrics, Script_Box_Metrics) {

    _, sup_size := math_child_font_size(cache, font_size, math_style, .Superscript)
    _, sub_size := math_child_font_size(cache, font_size, math_style, .Subscript)
    sup := script_metrics({cache, cmd, .Superscript, dyncore.text_span_from_buffer(
        buffer, cmd.script_sup_text_offset, cmd.script_sup_text_len),
        cmd.script_style_id, sup_size/font_size, font_size})
    sub := script_metrics({cache, cmd, .Subscript, dyncore.text_span_from_buffer(
        buffer, cmd.script_sub_text_offset, cmd.script_sub_text_len),
        cmd.script_style_id, sub_size/font_size, font_size})
    if cmd.secondary_math_program_id > 0 {
        program, found := math_program_from_id(cache, cmd.secondary_math_program_id)
        if found {
            sup = {
                cols = 1, draw_width = program^.draw_width,
                ascent = program^.ascent, descent = program^.descent,
            }
        }
    }
    if cmd.tertiary_math_program_id > 0 {
        program, found := math_program_from_id(cache, cmd.tertiary_math_program_id)
        if found {
            sub = {
                cols = 1, draw_width = program^.draw_width,
                ascent = program^.ascent, descent = program^.descent,
            }
        }
    }
    return {sup.draw_width, sup.draw_width, sup.ascent, sup.descent},
        {sub.draw_width, sub.draw_width, sub.ascent, sub.descent}
}

//   Store one validated operator geometry and its selected generation identity.
large_op_store_variant_geometry :: proc(
    item: ^app_core.Dynview_Layout_Item,
    result: Large_Op_Variant_Result) {

    geometry := result.geometry
    item^.draw_width = geometry.width
    item^.draw_height = geometry.ascent + geometry.descent
    item^.ascent = geometry.ascent
    item^.descent = geometry.descent
    item^.script_sup_x = geometry.superscript_x
    item^.script_sup_baseline = geometry.superscript_baseline
    item^.script_sub_x = geometry.subscript_x
    item^.script_sub_baseline = geometry.subscript_baseline
    item^.script_geometry_valid = true
    item^.operator_glyph_id = result.selected.glyph_id
    item^.operator_font_generation = result.generation
    item^.operator_glyph_x = geometry.glyph_x
    scale := result.font_size/result.run^.base_pixel_size/64.0
    natural_ascent := f32(result.selected.extents.y_bearing)*scale
    baseline_shift := natural_ascent-geometry.glyph_ascent
    item^.operator_glyph_line_top = geometry.ascent+baseline_shift-
        result.run^.raster_ascent*result.font_size/result.run^.base_pixel_size
    item^.operator_glyph_font_size = result.font_size
    item^.operator_geometry_valid = true
}

//   Replace synthetic operator dimensions with generation-safe MATH variant geometry.
math_program_apply_operator_variant :: proc(
    ctx: Math_Program_Item_Context,
    item: ^app_core.Dynview_Layout_Item) {

    generation := ctx.cache^.shaped_font_generation
    selected := math_operator_select_variant(
        ctx.cache^.math_operator_variants[ctx.command_index],
        ctx.cache^.math_constants, generation, ctx.font_size)
    if !selected.valid {
        return
    }
    sup, sub := large_op_script_boxes(
        ctx.cache, ctx.buffer, ctx.cmd, ctx.font_size, ctx.math_style)
    geometry := math_operator_geometry({
        constants = ctx.cache^.math_constants, generation = generation,
        font_size = ctx.font_size, style = ctx.math_style, variant = selected,
        superscript = sup, subscript = sub,
        has_superscript = sup.width > 0, has_subscript = sub.width > 0,
        limits_policy = ctx.cmd.operator_limits,
    })
    run, run_ok := shaped_run_for_command(ctx.cache, ctx.cmd, .Primary)
    if geometry.valid && run_ok && run^.base_pixel_size > 0 {
        large_op_store_variant_geometry(item, {
            geometry, selected, run, generation, ctx.font_size,
        })
    }
}

//   Build one layout-like item for a recursive fraction with centered numerator and denominator.
fraction_item :: #force_inline proc(
    cmd: app_core.Dynview_Command,
    metrics: Fraction_Item_Metrics) -> app_core.Dynview_Layout_Item {

    return app_core.Dynview_Layout_Item{
        kind = .Frac,
        style_id = cmd.style_id,
        math_program_id = cmd.math_program_id,
        secondary_math_program_id = cmd.secondary_math_program_id,
        accent_style_id = cmd.accent_style_id,
        accent_thickness = cmd.accent_thickness,
        fraction_numerator_x = metrics.geometry.numerator_x,
        fraction_numerator_baseline = metrics.geometry.numerator_baseline,
        fraction_denominator_x = metrics.geometry.denominator_x,
        fraction_denominator_baseline = metrics.geometry.denominator_baseline,
        fraction_rule_left = metrics.geometry.rule_left,
        fraction_rule_right = metrics.geometry.rule_right,
        fraction_rule_center = metrics.geometry.rule_center,
        fraction_rule_thickness = metrics.geometry.rule_thickness,
        fraction_geometry_valid = metrics.geometry.valid,
        draw_width = metrics.draw_width,
        math_advance = metrics.draw_width,
        draw_height = metrics.ascent + metrics.descent,
        ascent = metrics.ascent,
        descent = metrics.descent,
        visual_padding_top = max(max(metrics.numerator^.visual_padding_top,
            metrics.denominator^.visual_padding_top), metrics.visual_pad),
        visual_padding_bottom = max(max(metrics.numerator^.visual_padding_bottom,
            metrics.denominator^.visual_padding_bottom), metrics.visual_pad),
    }
}

//   Build complete stored geometry for the explicit fraction fallback path.
fraction_fallback_geometry :: #force_inline proc(
    ctx: Fraction_Layout_Context,
    width, side_padding, gap, thickness: f32) -> Math_Fraction_Geometry {

    half := thickness * 0.5
    return {
        numerator_x = (width - ctx.numerator^.draw_width) * 0.5,
        numerator_baseline = -half - gap - ctx.numerator^.descent,
        denominator_x = (width - ctx.denominator^.draw_width) * 0.5,
        denominator_baseline = half + gap + ctx.denominator^.ascent,
        rule_left = side_padding,
        rule_right = width - side_padding,
        rule_thickness = thickness,
        width = width,
        ascent = ctx.numerator^.ascent + ctx.numerator^.descent + gap + half,
        descent = ctx.denominator^.ascent + ctx.denominator^.descent + gap + half,
    }
}

//   Resolve MATH or explicit fallback geometry for two measured fraction children.
fraction_resolve_geometry :: proc(
    ctx: Fraction_Layout_Context) -> Math_Fraction_Geometry {

    base_advance := dyncore.effective_advance(ctx.style, ctx.cache^.last_cell_width)
    side_padding := fraction_side_padding(ctx.font_size, base_advance)
    content_width := max(ctx.numerator^.draw_width, ctx.denominator^.draw_width)
    width := max(content_width + side_padding * 2.0, base_advance)
    geometry := math_fraction_geometry({
        constants = ctx.cache^.math_constants,
        generation = ctx.cache^.shaped_font_generation,
        font_size = ctx.font_size,
        style = ctx.math_style,
        numerator = {ctx.numerator^.draw_width,
            ctx.numerator^.ascent, ctx.numerator^.descent},
        denominator = {ctx.denominator^.draw_width,
            ctx.denominator^.ascent, ctx.denominator^.descent},
        side_padding = side_padding,
        minimum_width = base_advance,
    })
    if geometry.valid {
        return geometry
    }
    gap := fraction_vertical_gap(ctx.font_size)
    thickness := max(1.0, ctx.command.accent_thickness * ctx.font_size)
    return fraction_fallback_geometry(ctx, width, side_padding, gap, thickness)
}

//   Build one layout-like item for a recursive fraction with centered numerator and denominator.
math_program_recursive_fraction_item :: #force_inline proc(
    ctx: Math_Program_Item_Context) -> (app_core.Dynview_Layout_Item, bool) {

    numerator_program, ok := math_program_from_command(ctx.cache, ctx.cmd)
    numerator_style, numerator_size := math_child_font_size(
        ctx.cache, ctx.font_size, ctx.math_style, .Fraction_Numerator)
    if !ok || !measure_math_program(
        ctx.cache, ctx.buffer, numerator_program, numerator_size, numerator_style) {
        return app_core.Dynview_Layout_Item{}, false
    }

    denominator_program, ok_den := secondary_math_program_from_command(
        ctx.cache, ctx.cmd)
    denominator_style, denominator_size := math_child_font_size(
        ctx.cache, ctx.font_size, ctx.math_style, .Fraction_Denominator)
    if !ok_den || !measure_math_program(
        ctx.cache, ctx.buffer, denominator_program, denominator_size,
        denominator_style) {
        return app_core.Dynview_Layout_Item{}, false
    }

    geometry := fraction_resolve_geometry({ctx.cache, numerator_program,
        denominator_program, ctx.cmd, ctx.style, ctx.font_size, ctx.math_style})
    visual_pad := max(0.6, geometry.rule_thickness * 0.5)

    return fraction_item(ctx.cmd, {
        numerator = numerator_program,
        denominator = denominator_program,
        draw_width = geometry.width,
        ascent = geometry.ascent,
        descent = geometry.descent,
        visual_pad = visual_pad,
        geometry = geometry,
    }), true
}

//   Build one ruleless two-part stack from font-driven MATH constants.
stack_layout_item :: #force_inline proc(
    ctx: Math_Program_Item_Context,
    geometry: Stack_Item_Geometry) -> app_core.Dynview_Layout_Item {

    return {
        kind = .Stack, style_id = ctx.cmd.style_id,
        math_program_id = ctx.cmd.math_program_id,
        secondary_math_program_id = ctx.cmd.secondary_math_program_id,
        operator_limits = geometry.operator_limits,
        fraction_numerator_x = geometry.top_x,
        fraction_numerator_baseline = geometry.top_baseline,
        fraction_denominator_x = geometry.bottom_x,
        fraction_denominator_baseline = geometry.bottom_baseline,
        draw_width = geometry.width, draw_height = geometry.ascent+geometry.descent,
        ascent = geometry.ascent, descent = geometry.descent,
    }
}

//   Build one ruleless two-part stack from font-driven MATH constants.
math_program_recursive_stack_item :: proc(
    ctx: Math_Program_Item_Context) -> (app_core.Dynview_Layout_Item, bool) {

    if ctx.cmd.operator_limits > 0 {
        return math_program_recursive_over_under_item(ctx)
    }

    top, top_ok := math_program_from_command(ctx.cache, ctx.cmd)
    top_style, top_size := math_child_font_size(
        ctx.cache, ctx.font_size, ctx.math_style, .Fraction_Numerator)
    bottom, bottom_ok := secondary_math_program_from_command(ctx.cache, ctx.cmd)
    bottom_style, bottom_size := math_child_font_size(
        ctx.cache, ctx.font_size, ctx.math_style, .Fraction_Denominator)
    if !top_ok || !bottom_ok ||
        !measure_math_program(ctx.cache, ctx.buffer, top, top_size, top_style) ||
        !measure_math_program(
            ctx.cache, ctx.buffer, bottom, bottom_size, bottom_style) {
        return {}, false
    }
    geometry := math_stack_geometry({
        constants = ctx.cache^.math_constants,
        generation = ctx.cache^.shaped_font_generation,
        font_size = ctx.font_size,
        style = ctx.math_style,
        top = {top^.draw_width, top^.ascent, top^.descent},
        bottom = {bottom^.draw_width, bottom^.ascent, bottom^.descent},
    })
    if !geometry.valid {
        return {}, false
    }
    return stack_layout_item(ctx, {
        top_x = geometry.top_x, top_baseline = geometry.top_baseline,
        bottom_x = geometry.bottom_x, bottom_baseline = geometry.bottom_baseline,
        width = geometry.width, ascent = geometry.ascent, descent = geometry.descent,
    }), true
}

//   Build one over- or under-annotation with an unscaled base and script annotation.
math_program_recursive_over_under_item :: proc(
    ctx: Math_Program_Item_Context) -> (app_core.Dynview_Layout_Item, bool) {

    top, top_ok := math_program_from_command(ctx.cache, ctx.cmd)
    bottom, bottom_ok := secondary_math_program_from_command(ctx.cache, ctx.cmd)
    annotation_style, annotation_size := math_child_font_size(
        ctx.cache, ctx.font_size, ctx.math_style, .Superscript)
    over := ctx.cmd.operator_limits == 1
    annotation := top if over else bottom
    base := bottom if over else top
    if !top_ok || !bottom_ok ||
        !measure_math_program(ctx.cache, ctx.buffer, annotation,
            annotation_size, annotation_style) ||
        !measure_math_program(ctx.cache, ctx.buffer, base,
            ctx.font_size, ctx.math_style) {
        return {}, false
    }
    geometry := math_over_under_geometry({
        constants = ctx.cache^.math_constants,
        generation = ctx.cache^.shaped_font_generation,
        font_size = ctx.font_size,
        annotation = {annotation^.draw_width, annotation^.ascent, annotation^.descent},
        base = {base^.draw_width, base^.ascent, base^.descent},
        over = over,
    })
    if !geometry.valid {
        return {}, false
    }
    return stack_layout_item(ctx, {
        operator_limits = ctx.cmd.operator_limits,
        top_x = geometry.top_x, top_baseline = geometry.top_baseline,
        bottom_x = geometry.bottom_x, bottom_baseline = geometry.bottom_baseline,
        width = geometry.width, ascent = geometry.ascent, descent = geometry.descent,
    }), true
}

//   Build one layout-like item for a recursive stretch-delimiter wrapper.
stretch_delimiter_content :: proc(
    ctx: Math_Program_Item_Context) -> (Stretch_Delimiter_Content, bool) {

    ascent, descent := dyncore.style_ascent_descent(ctx.style, ctx.font_size)
    content := Stretch_Delimiter_Content{ascent = ascent, descent = descent}
    if ctx.cmd.math_program_id <= 0 {
        return content, true
    }

    child_program, ok := math_program_from_command(ctx.cache, ctx.cmd)
    if !ok || !measure_math_program(
        ctx.cache, ctx.buffer, child_program, ctx.font_size, ctx.math_style) {
        return {}, false
    }
    return Stretch_Delimiter_Content{
        width = child_program^.draw_width,
        ascent = child_program^.ascent,
        descent = child_program^.descent,
        top_pad = child_program^.visual_padding_top,
        bottom_pad = child_program^.visual_padding_bottom,
    }, true
}

//   Calculate the combined width of delimiter glyphs and their content padding.
stretch_delimiter_widths :: #force_inline proc(
    cache: ^app_core.Dynview_Compile_Cache,
    cmd: app_core.Dynview_Command,
    style: dyncore.Dynview_Text_Style,
    dimensions: Stretch_Delimiter_Dimensions) -> f32 {

    left_clearance, right_clearance := stretch_delimiter_clearances(
        cmd, dimensions.font_size)
    left_width := stretch_delimiter_width(
        style, cache^.last_cell_width, dimensions.font_size,
        dimensions.content_height, cmd.accent_mode)
    right_width := stretch_delimiter_width(
        style, cache^.last_cell_width, dimensions.font_size,
        dimensions.content_height, cmd.radical_mode)
    return dimensions.content_width + left_width + right_width +
        left_clearance + right_clearance
}

//   Build one layout-like item for a recursive stretch-delimiter wrapper.
math_program_recursive_stretch_delimiter_item :: #force_inline proc(
    ctx: Math_Program_Item_Context) -> (app_core.Dynview_Layout_Item, bool) {

    content, ok := stretch_delimiter_content(ctx)
    if !ok {
        return app_core.Dynview_Layout_Item{}, false
    }

    content_height := content.ascent + content.descent
    draw_width := stretch_delimiter_widths(
        ctx.cache, ctx.cmd, ctx.style, {ctx.font_size, content_height, content.width})
    return app_core.Dynview_Layout_Item{
        kind = .Stretch_Delimiter,
        style_id = ctx.cmd.style_id,
        math_program_id = ctx.cmd.math_program_id,
        secondary_math_program_id = ctx.cmd.secondary_math_program_id,
        accent_mode = ctx.cmd.accent_mode,
        radical_mode = ctx.cmd.radical_mode,
        operator_growth = ctx.cmd.operator_growth,
        operator_limits = ctx.cmd.operator_limits,
        math_atom_class = ctx.cmd.math_atom_class,
        draw_width = draw_width,
        draw_height = content_height,
        ascent = content.ascent,
        descent = content.descent,
        visual_padding_top = content.top_pad,
        visual_padding_bottom = content.bottom_pad,
    }, true
}

//   Return the horizontal ink bounds shared by every selected construction part.
math_stretch_horizontal_bounds :: proc(
    construction: app_core.Font_Math_Stretch_Construction,
    scale: f32) -> (f32, f32) {

    left, right: f32
    for index in 0..<construction.count {
        extents := construction.parts[index].extents
        part_left := f32(extents.x_bearing)*scale
        part_right := f32(extents.x_bearing+extents.width)*scale
        if index == 0 {
            left, right = part_left, part_right
        } else {
            left, right = min(left, part_left), max(right, part_right)
        }
    }
    return left, right
}

//   Return bottom-to-top construction ink bounds relative to its first origin.
math_stretch_ink_vertical_bounds :: proc(
    construction: app_core.Font_Math_Stretch_Construction,
    scale: f32) -> Math_Stretch_Vertical_Bounds {

    if !construction.valid || construction.count <= 0 ||
        construction.count > len(construction.parts) || scale <= 0 {
        return {}
    }
    top, bottom: f32
    for index in 0..<construction.count {
        part := construction.parts[index]
        part_top := (-part.advance_offset-f32(part.extents.y_bearing))*scale
        part_bottom := (-part.advance_offset-
            f32(part.extents.y_bearing+part.extents.height))*scale
        if index == 0 {
            top, bottom = part_top, part_bottom
        } else {
            top, bottom = min(top, part_top), max(bottom, part_bottom)
        }
    }
    return {top = top, bottom = bottom, valid = bottom > top}
}

//   Select every visible side without publishing a partial two-sided result.
math_stretch_select_delimiters :: proc(
    sources: [2]app_core.Font_Math_Stretch_Source,
    cmd: app_core.Dynview_Command,
    generation: u64,
    scale: f32,
    target: i32) -> Stretch_Delimiter_Selection {

    result := Stretch_Delimiter_Selection{ok = true}
    kinds := [2]i32{cmd.accent_mode, cmd.radical_mode}
    for kind, side in kinds {
        if kind == DELIMITER_KIND_NONE {
            continue
        }
        source := sources[side]
        selected := math_stretch_select(
            source.variants, source.assembly, generation, target)
        if !selected.valid {
            return {}
        }
        left, right := math_stretch_horizontal_bounds(selected, scale)
        bounds := math_stretch_ink_vertical_bounds(selected, scale)
        if !bounds.valid {
            return {}
        }
        result.widths[side] = max(0, right-left)
        result.origins[side] = -left
        result.vertical_origins[side] = -(bounds.top+bounds.bottom)*0.5
        result.half_heights[side] = (bounds.bottom-bounds.top)*0.5
        result.constructions[side] = selected
        result.raster_ascent = source.raster_ascent
    }
    return result
}

//   Resolve the measured child width used between a delimiter pair.
stretch_delimiter_content_width :: proc(
    cache: ^app_core.Dynview_Compile_Cache,
    program_id: i32) -> f32 {

    if program_id <= 0 {
        return 0
    }
    content, found := math_program_from_id(cache, program_id)
    return content^.draw_width if found else 0
}

//   Publish selected delimiter geometry to one layout item.
stretch_delimiter_apply_item :: proc(
    item: ^app_core.Dynview_Layout_Item,
    geometry: Stretch_Delimiter_Item_Geometry) {

    selected := geometry.selected
    item^.math_stretch_left_x = selected.origins[0]
    item^.math_stretch_content_x = selected.widths[0] + geometry.left_clearance
    item^.math_stretch_right_x = item^.math_stretch_content_x +
        geometry.content_width + geometry.right_clearance + selected.origins[1]
    item^.draw_width = selected.widths[0] + geometry.left_clearance +
        geometry.content_width + geometry.right_clearance + selected.widths[1]
    for side in 0..<2 {
        item^.math_stretch_vertical_origins[side] =
            selected.vertical_origins[side]-geometry.axis
        item^.ascent = max(item^.ascent, selected.half_heights[side]+geometry.axis)
        item^.descent = max(item^.descent, selected.half_heights[side]-geometry.axis)
    }
    item^.draw_height = item^.ascent + item^.descent
    item^.math_stretch_constructions = selected.constructions
    item^.math_stretch_font_generation = geometry.generation
    item^.math_stretch_raster_ascent = max(0, selected.raster_ascent)
    item^.math_stretch_scale = geometry.scale
    item^.math_stretch_geometry_valid = true
}

//   Return the child width after remeasuring shared middle delimiters.
stretch_delimiter_shared_content_width :: proc(
    cache: ^app_core.Dynview_Compile_Cache,
    buffer: ^app_core.Dynview_Command_Buffer,
    program_id: i32,
    font_size, target_height: f32) -> f32 {

    content_width := stretch_delimiter_content_width(cache, program_id)
    child, child_ok := math_program_from_id(cache, program_id)
    if !child_ok {
        return content_width
    }
    command_end := child^.command_start+child^.command_count
    for child_index in child^.command_start..<command_end {
        child_cmd := cache^.math_commands[child_index]
        if child_cmd.kind != .Stretch_Delimiter || child_cmd.operator_limits != 1 {
            continue
        }
        base_item, base_ok := math_program_item({
            cache = cache, buffer = buffer, cmd = child_cmd,
            font_size = font_size, command_index = child_index})
        shared_item, shared_ok := math_program_item({
            cache = cache, buffer = buffer, cmd = child_cmd,
            font_size = font_size, command_index = child_index,
            delimiter_target_height = target_height})
        if base_ok && shared_ok {
            content_width += shared_item.draw_width-base_item.draw_width
        }
    }
    return content_width
}

//   Resolve the requested delimiter height, including shared middle sizing.
stretch_delimiter_target_height :: #force_inline proc(
    ctx: Math_Program_Item_Context,
    item: ^app_core.Dynview_Layout_Item) -> f32 {

    target_height := max(item^.ascent+item^.descent,
        delimiter_requested_height(ctx.font_size, ctx.cmd.operator_growth))
    if ctx.cmd.operator_limits == 1 {
        target_height = max(target_height, ctx.delimiter_target_height)
    }
    return target_height
}

//   Select both visible delimiters and replace fallback dimensions transactionally.
math_program_apply_stretch_delimiters :: proc(
    ctx: Math_Program_Item_Context,
    item: ^app_core.Dynview_Layout_Item) {

    constants := ctx.cache^.math_constants
    generation := ctx.cache^.shaped_font_generation
    if !math_constants_are_current(constants, generation) || ctx.font_size <= 0 {
        return
    }
    scale := ctx.font_size/constants.base_pixel_size/64.0
    target_height := stretch_delimiter_target_height(ctx, item)
    target := i32(target_height/scale + 0.999)
    selected := math_stretch_select_delimiters(
        ctx.cache^.math_stretch_sources[ctx.command_index],
        ctx.cmd, generation, scale, target)
    if !selected.ok {
        return
    }
    left_clearance, right_clearance := stretch_delimiter_clearances(
        ctx.cmd, ctx.font_size)
    content_width := stretch_delimiter_shared_content_width(
        ctx.cache, ctx.buffer, ctx.cmd.math_program_id, ctx.font_size, target_height)
    axis, _ := math_constant_position_px(
        constants, generation, .Axis_Height, ctx.font_size)
    stretch_delimiter_apply_item(item, {
        selected = selected,
        left_clearance = left_clearance,
        right_clearance = right_clearance,
        content_width = content_width,
        axis = axis,
        generation = generation,
        scale = scale,
    })
    item^.math_stretch_target_height = target_height
}

//   Resolve all six MATH constants controlling radical and degree placement.
radical_math_metrics :: proc(
    constants: app_core.Font_Math_Constants,
    generation: u64,
    font_size: f32,
    style: Math_Style) -> Radical_Math_Metrics {

    gap_constant := Math_Constant.Radical_Vertical_Gap
    if style.level == .Display {
        gap_constant = .Radical_Display_Style_Vertical_Gap
    }
    result := Radical_Math_Metrics{}
    gap_ok, rule_ok, extra_ok, before_ok, after_ok: bool
    result.gap, gap_ok = math_constant_position_px(
        constants, generation, gap_constant, font_size)
    result.rule, rule_ok = math_constant_position_px(
        constants, generation, .Radical_Rule_Thickness, font_size)
    result.extra, extra_ok = math_constant_position_px(
        constants, generation, .Radical_Extra_Ascender, font_size)
    result.before_degree, before_ok = math_constant_position_px(
        constants, generation, .Radical_Kern_Before_Degree, font_size)
    result.after_degree, after_ok = math_constant_position_px(
        constants, generation, .Radical_Kern_After_Degree, font_size)
    raise, raise_ok := math_constant_raw(constants, generation,
        .Radical_Degree_Bottom_Raise_Percent)
    result.degree_raise_percent = f32(raise)
    result.ok = gap_ok && rule_ok && extra_ok && before_ok && after_ok && raise_ok
    return result
}

//   Resolve optional radical-degree dimensions from the measured child program.
radical_degree_dimensions :: proc(
    cache: ^app_core.Dynview_Compile_Cache,
    program_id: i32) -> Radical_Degree_Dimensions {

    if program_id <= 0 {
        return {}
    }
    degree, found := math_program_from_id(cache, program_id)
    if !found {
        return {}
    }
    return {width = degree^.draw_width, descent = degree^.descent}
}

//   Assemble validated radical measurements into immutable construction geometry.
radical_construction_geometry :: proc(
    input: Radical_Construction_Input) -> Radical_Construction_Geometry {

    surd_x := max(0, input.degree.width+input.metrics.before_degree+
        input.metrics.after_degree)
    rule_top := -input.child^.ascent-input.metrics.gap-input.metrics.rule
    surd_origin := rule_top-input.bounds.top
    degree_bottom := surd_origin+input.bounds.bottom-
        (input.bounds.bottom-input.bounds.top)*input.metrics.degree_raise_percent/100.0
    return {
        construction = input.selected, raster_ascent = input.source.raster_ascent,
        scale = input.scale, surd_x = surd_x, surd_left = input.left,
        surd_width = max(0, input.right-input.left), surd_bottom = surd_origin,
        content_width = input.child^.draw_width,
        child_ascent = input.child^.ascent, child_descent = input.child^.descent,
        degree_width = input.degree.width, degree_descent = input.degree.descent,
        degree_baseline = degree_bottom-input.degree.descent,
        metrics = input.metrics, generation = input.generation, valid = true,
    }
}

//   Resolve one radical construction without mutating the destination item.
math_program_radical_construction :: proc(
    cache: ^app_core.Dynview_Compile_Cache,
    cmd: app_core.Dynview_Command,
    font_size: f32,
    command_index: int,
    math_style: Math_Style) -> Radical_Construction_Geometry {

    generation := cache^.shaped_font_generation
    metrics := radical_math_metrics(
        cache^.math_constants, generation, font_size, math_style)
    if !metrics.ok || font_size <= 0 {
        return {}
    }
    child, child_ok := math_program_from_id(cache, cmd.math_program_id)
    if !child_ok {
        return {}
    }
    source := cache^.math_stretch_sources[command_index][0]
    scale := font_size/cache^.math_constants.base_pixel_size/64.0
    target_px := child^.ascent+child^.descent+metrics.gap+metrics.rule
    selected := math_stretch_select(source.variants, source.assembly,
        generation, i32(target_px/scale+0.999))
    if !selected.valid {
        return {}
    }
    bounds := math_stretch_ink_vertical_bounds(selected, scale)
    if !bounds.valid {
        return {}
    }
    left, right := math_stretch_horizontal_bounds(selected, scale)
    degree := radical_degree_dimensions(cache, cmd.secondary_math_program_id)
    return radical_construction_geometry({
        selected = selected, source = source, child = child, metrics = metrics,
        bounds = bounds, degree = degree, scale = scale, left = left, right = right,
        generation = generation,
    })
}

//   Commit one fully resolved radical construction to the destination item.
math_program_apply_radical_construction :: proc(
    geometry: Radical_Construction_Geometry,
    item: ^app_core.Dynview_Layout_Item) {

    if !geometry.valid {
        return
    }
    item^.math_stretch_constructions[0] = geometry.construction
    item^.math_stretch_left_x = geometry.surd_x-geometry.surd_left
    item^.math_stretch_content_x = geometry.surd_x+geometry.surd_width
    item^.math_stretch_bottom = geometry.surd_bottom
    item^.radical_rule_left = item^.math_stretch_content_x
    item^.radical_rule_right = item^.radical_rule_left+geometry.content_width
    item^.radical_rule_center = -geometry.child_ascent-
        geometry.metrics.gap-geometry.metrics.rule*0.5
    item^.radical_rule_thickness = geometry.metrics.rule
    item^.radical_degree_x = geometry.surd_x-
        geometry.degree_width-geometry.metrics.after_degree
    item^.radical_degree_baseline = geometry.degree_baseline
    item^.draw_width = item^.radical_rule_right
    item^.ascent = max(geometry.child_ascent+geometry.metrics.gap+
        geometry.metrics.rule+geometry.metrics.extra,
        geometry.construction.advance*geometry.scale-geometry.child_descent)
    item^.descent = max(geometry.child_descent, geometry.degree_descent)
    item^.draw_height = item^.ascent+item^.descent
    item^.math_stretch_font_generation = geometry.generation
    item^.math_stretch_raster_ascent = geometry.raster_ascent
    item^.math_stretch_scale = geometry.scale
    item^.math_stretch_geometry_valid = true
    item^.radical_geometry_valid = true
}

//   Measure every matrix cell, accumulating column widths and row extents.
measure_matrix_cells :: proc(
    ctx: Math_Measure_Context,
    cell_program: ^app_core.Dynview_Math_Program,
    descriptor: ^app_core.Dynview_Math_Table_Descriptor,
    dims: ^Matrix_Cell_Dims) -> bool {

    strut_ascent, strut_descent :=
        math_table_row_strut(descriptor^.row_spacing, ctx.font_size)
    for row in 0..<descriptor^.rows {
        dims.row_ascents[row] = strut_ascent
        dims.row_descents[row] = strut_descent
        for col in 0..<descriptor^.columns {
            cell_index := row * descriptor^.columns + col
            cmd_index := cell_program^.command_start + cell_index
            cell_cmd := ctx.cache^.math_commands[cmd_index]
            cell_item, cell_ok := math_program_item({
                cache = ctx.cache, buffer = ctx.buffer,
                cmd = cell_cmd, font_size = ctx.font_size,
                command_index = cmd_index, math_style = ctx.math_style,
            })
            if !cell_ok {
                return false
            }

            dims.col_widths[col] = max(dims.col_widths[col], cell_item.draw_width)
            dims.row_ascents[row] = max(dims.row_ascents[row], cell_item.ascent)
            dims.row_descents[row] = max(dims.row_descents[row], cell_item.descent)
            dims.top_pad = max(dims.top_pad, cell_item.visual_padding_top)
            dims.bottom_pad = max(dims.bottom_pad, cell_item.visual_padding_bottom)
        }
    }
    return true
}

//   Aggregate matrix draw width and total height from per-column/row cell metrics.
matrix_aggregate_dims :: proc(
    dims: ^Matrix_Cell_Dims,
    descriptor: ^app_core.Dynview_Math_Table_Descriptor,
    font_size: f32,
    base_advance: f32) -> (draw_width, total_height: f32) {

    for boundary in 0..=descriptor^.columns {
        draw_width += math_table_column_boundary_width(
            descriptor, boundary, font_size, base_advance)
    }
    for col in 0..<descriptor^.columns {
        draw_width += dims.col_widths[col]
    }

    for boundary in 0..=descriptor^.rows {
        total_height += math_table_row_boundary_height(descriptor, boundary, font_size)
    }
    for row in 0..<descriptor^.rows {
        total_height += dims.row_ascents[row] + dims.row_descents[row]
    }

    return draw_width, total_height
}

//   Build one layout-like item for a recursive matrix with row-major child cells.
matrix_item :: #force_inline proc(
    cmd: app_core.Dynview_Command,
    metrics: Matrix_Item_Metrics) -> app_core.Dynview_Layout_Item {

    half_height := metrics.total_height * 0.5
    axis_height := clamp(metrics.axis_height, -half_height, half_height)
    ascent := half_height + axis_height
    return app_core.Dynview_Layout_Item{
        kind = .Matrix, style_id = cmd.style_id, math_program_id = cmd.math_program_id,
        table_descriptor_index = cmd.table_descriptor_index,
        accent_mode = i32(metrics.rows), radical_mode = i32(metrics.cols),
        draw_width = metrics.draw_width, draw_height = metrics.total_height,
        ascent = ascent, descent = metrics.total_height - ascent,
        visual_padding_top = metrics.top_pad, visual_padding_bottom = metrics.bottom_pad,
    }
}

//   Resolve a matrix child program with a matching descriptor cell count.
matrix_program_from_command :: proc(
    cache: ^app_core.Dynview_Compile_Cache,
    cmd: app_core.Dynview_Command) -> (Matrix_Program, bool) {

    descriptor, descriptor_ok := matrix_descriptor_from_command(cache, cmd)
    if !descriptor_ok {
        return {}, false
    }
    program, ok := math_program_from_command(cache, cmd)
    if !ok || program^.command_count != descriptor^.rows * descriptor^.columns {
        return {}, false
    }
    return {program, descriptor, descriptor^.rows, descriptor^.columns}, true
}

//   Build one layout-like item for a recursive matrix with row-major child cells.
math_program_recursive_matrix_item :: #force_inline proc(
    ctx: Math_Program_Item_Context) -> (app_core.Dynview_Layout_Item, bool) {

    matrix_info, ok := matrix_program_from_command(ctx.cache, ctx.cmd)
    if !ok {
        return app_core.Dynview_Layout_Item{}, false
    }

    cell_dims := Matrix_Cell_Dims{}
    if !measure_matrix_cells(
        matrix_cell_measure_context(ctx, matrix_info.descriptor), matrix_info.program,
        matrix_info.descriptor, &cell_dims) {
        return app_core.Dynview_Layout_Item{}, false
    }
    top_pad := cell_dims.top_pad
    bottom_pad := cell_dims.bottom_pad

    base_advance := dyncore.effective_advance(ctx.style, ctx.cache^.last_cell_width)
    draw_width, total_height := matrix_aggregate_dims(
        &cell_dims,
        matrix_info.descriptor,
        ctx.font_size, base_advance)
    axis_height, axis_ok := math_constant_position_px(
        ctx.cache^.math_constants, ctx.cache^.shaped_font_generation,
        .Axis_Height, ctx.font_size)
    if !axis_ok {
        axis_height = 0
    }

    return matrix_item(ctx.cmd, {
        rows = matrix_info.rows,
        cols = matrix_info.cols,
        draw_width = max(draw_width, base_advance),
        total_height = total_height,
        axis_height = axis_height,
        top_pad = top_pad,
        bottom_pad = bottom_pad,
    }), true
}

//   Build command-defined fallback geometry for a recursive accent bar.
accent_fallback_geometry :: #force_inline proc(
    child: ^app_core.Dynview_Math_Program,
    cmd: app_core.Dynview_Command,
    font_size: f32) -> Math_Bar_Geometry {

    thickness := max(1.0, cmd.accent_thickness * font_size)
    offset := max(0.0, cmd.accent_offset * font_size)
    half := thickness * 0.5
    result := Math_Bar_Geometry{
        rule_thickness = thickness, width = child^.draw_width,
        ascent = child^.ascent, descent = child^.descent}
    if cmd.accent_mode == 1 {
        result.rule_center = -child^.ascent - offset
        result.ascent = max(result.ascent, child^.ascent + offset + half)
    } else {
        result.rule_center = child^.descent + offset
        result.descent = max(result.descent, child^.descent + offset + half)
    }
    return result
}

//   Resolve MATH or explicit fallback geometry around one measured accent child.
accent_resolve_geometry :: proc(
    cache: ^app_core.Dynview_Compile_Cache,
    child: ^app_core.Dynview_Math_Program,
    cmd: app_core.Dynview_Command,
    font_size: f32) -> Math_Bar_Geometry {

    bar_kind := Math_Bar_Kind.Underbar
    if cmd.accent_mode == 1 {
        bar_kind = .Overbar
    }
    geometry := math_bar_geometry({
        constants = cache^.math_constants,
        generation = cache^.shaped_font_generation,
        font_size = font_size,
        kind = bar_kind,
        child_width = child^.draw_width,
        child_ascent = child^.ascent,
        child_descent = child^.descent,
    })
    if geometry.valid {
        return geometry
    }
    return accent_fallback_geometry(child, cmd, font_size)
}

//   Build one sealed recursive accent layout item from resolved bar geometry.
accent_bar_item :: #force_inline proc(
    cmd: app_core.Dynview_Command,
    child: ^app_core.Dynview_Math_Program,
    geometry: Math_Bar_Geometry) -> app_core.Dynview_Layout_Item {

    return {
        kind = .Accent_Bar, style_id = cmd.style_id,
        math_program_id = cmd.math_program_id,
        secondary_math_program_id = cmd.secondary_math_program_id,
        accent_mode = cmd.accent_mode, accent_style_id = cmd.accent_style_id,
        accent_thickness = cmd.accent_thickness, accent_offset = cmd.accent_offset,
        accent_child_baseline = geometry.child_baseline,
        accent_rule_right = geometry.width,
        accent_rule_center = geometry.rule_center,
        accent_rule_thickness = geometry.rule_thickness,
        accent_geometry_valid = geometry.valid,
        draw_width = geometry.width, math_advance = geometry.width,
        draw_height = geometry.ascent + geometry.descent,
        ascent = geometry.ascent, descent = geometry.descent,
        visual_padding_top = child^.visual_padding_top,
        visual_padding_bottom = child^.visual_padding_bottom,
        italic_correction = child^.italic_correction,
        top_accent_attachment = child^.top_accent_attachment,
    }
}

//   Build one undecided glyph-accent item around an already measured child.
accent_glyph_item :: #force_inline proc(
    cmd: app_core.Dynview_Command,
    child: ^app_core.Dynview_Math_Program) -> app_core.Dynview_Layout_Item {

    return {
        kind = .Accent_Bar, style_id = cmd.style_id,
        math_program_id = cmd.math_program_id, accent_mode = cmd.accent_mode,
        accent_style_id = cmd.accent_style_id,
        draw_width = child^.draw_width, math_advance = child^.advance,
        draw_height = child^.ascent+child^.descent,
        ascent = child^.ascent, descent = child^.descent,
        visual_padding_top = child^.visual_padding_top,
        visual_padding_bottom = child^.visual_padding_bottom,
        italic_correction = child^.italic_correction,
        top_accent_attachment = child^.top_accent_attachment,
    }
}

//   Preserve single-child attachment; use the geometric center for expression boxes.
math_program_base_accent_attachment :: #force_inline proc(
    child: ^app_core.Dynview_Math_Program) -> f32 {

    if child == nil || child^.command_count != 1 ||
        child^.top_accent_attachment <= 0 {
        return child^.draw_width*0.5 if child != nil else 0
    }
    return child^.top_accent_attachment
}

//   Publish resolved glyph-accent construction geometry to one layout item.
math_program_publish_glyph_accent :: proc(
    item: ^app_core.Dynview_Layout_Item,
    geometry: Math_Glyph_Accent_Geometry,
    generation: u64) {

    item^.accent_child_x = geometry.child_x
    item^.accent_glyph_x = geometry.accent_x
    item^.accent_glyph_line_top = geometry.accent_line_top
    item^.accent_glyph_scale = geometry.scale
    item^.accent_glyph_raster_ascent = geometry.raster_ascent
    item^.accent_glyph_font_generation = generation
    item^.accent_glyph_construction = geometry.construction
    item^.accent_geometry_valid = true
    item^.draw_width, item^.math_advance = geometry.width, geometry.width
    item^.ascent, item^.descent = geometry.ascent, geometry.descent
    item^.draw_height = geometry.ascent+geometry.descent
    item^.top_accent_attachment = geometry.top_accent_attachment
}

//   Replace one glyph-accent fallback with sealed MATH construction geometry.
math_program_apply_glyph_accent :: proc(
    ctx: Math_Program_Item_Context,
    item: ^app_core.Dynview_Layout_Item) {

    if ctx.command_index < 0 ||
        ctx.command_index >= len(ctx.cache^.math_accent_sources) {
        return
    }
    child, found := math_program_from_id(ctx.cache, ctx.cmd.math_program_id)
    if !found {
        return
    }
    geometry := math_glyph_accent_geometry({
        constants = ctx.cache^.math_constants,
        generation = ctx.cache^.shaped_font_generation, font_size = ctx.font_size,
        child_width = child^.draw_width, child_ascent = child^.ascent,
        child_descent = child^.descent,
        base_attachment = math_program_base_accent_attachment(child),
        sources = ctx.cache^.math_accent_sources[ctx.command_index],
        brace_mode = ctx.cmd.accent_mode,
    })
    if !geometry.valid {
        return
    }
    math_program_publish_glyph_accent(
        item, geometry, ctx.cache^.shaped_font_generation)
}

//   Build one layout-like item for a recursive accent wrapper around a child math program.
math_program_recursive_accent_item :: #force_inline proc(
    cache: ^app_core.Dynview_Compile_Cache,
    buffer: ^app_core.Dynview_Command_Buffer,
    cmd: app_core.Dynview_Command,
    font_size: f32,
    math_style: Math_Style) -> (app_core.Dynview_Layout_Item, bool) {

    child_program, ok := math_program_from_id(cache, cmd.math_program_id)
    if !ok || !measure_math_program(
        cache, buffer, child_program, font_size, math_style) {
        return app_core.Dynview_Layout_Item{}, false
    }
    if cmd.accent_mode > 2 {
        return accent_glyph_item(cmd, child_program), true
    }
    geometry := accent_resolve_geometry(cache, child_program, cmd, font_size)
    return accent_bar_item(cmd, child_program, geometry), true
}

//   Build one layout-like item for a recursive radical wrapper around a child math program.
radical_item :: #force_inline proc(
    cmd: app_core.Dynview_Command,
    geometry: Radical_Geometry,
    script_scale: f32) -> app_core.Dynview_Layout_Item {

    return app_core.Dynview_Layout_Item{
        kind = .Radical_Bar,
        style_id = cmd.style_id,
        math_program_id = cmd.math_program_id,
        secondary_math_program_id = cmd.secondary_math_program_id,
        script_style_id = cmd.script_style_id, script_scale = script_scale,
        script_sup_raise = cmd.script_sup_raise, script_sub_drop = cmd.script_sub_drop,
        radical_mode = cmd.radical_mode,
        radical_index_text_offset = cmd.radical_index_text_offset,
        radical_index_text_len = cmd.radical_index_text_len,
        accent_style_id = cmd.accent_style_id, accent_thickness = cmd.accent_thickness,
        accent_offset = cmd.accent_offset, draw_width = geometry.draw_width,
        draw_height = geometry.ascent + geometry.descent,
        ascent = geometry.ascent, descent = geometry.descent,
        visual_padding_top = geometry.top_pad,
        visual_padding_bottom = geometry.bottom_pad,
    }
}

//   Measure the flat or recursive index attached to one radical.
radical_index_metrics :: proc(
    ctx: Radical_Geometry_Context,
    scale: f32) -> Script_Metrics {

    index := script_metrics({
        ctx.cache, ctx.cmd, .Radical_Index, dyncore.text_span_from_buffer(
            ctx.buffer, ctx.cmd.radical_index_text_offset,
            ctx.cmd.radical_index_text_len),
        ctx.cmd.script_style_id, scale, ctx.font_size})
    if ctx.cmd.secondary_math_program_id <= 0 {
        return index
    }
    program, found := math_program_from_id(
        ctx.cache, ctx.cmd.secondary_math_program_id)
    if found {
        index.cols = 1
        index.draw_width = program^.draw_width
        index.ascent = program^.ascent
        index.descent = program^.descent
    }
    return index
}

//   Calculate radical bar, root hook, and optional index geometry around a child.
radical_geometry :: proc(
    ctx: Radical_Geometry_Context) -> Radical_Geometry {

    scale := max(0.2, ctx.cmd.script_scale)
    index := radical_index_metrics(ctx, scale)
    offsets := script_draw_offsets(ctx.font_size, scale, ctx.cmd.script_sup_raise,
        ctx.cmd.script_sub_drop)
    script_top, script_bottom := script_visual_padding(offsets.script_font_size)
    stroke := max(1.0, ctx.cmd.accent_thickness * ctx.font_size)
    ascent := max(ctx.child^.ascent, ctx.child^.ascent +
        max(0.0, ctx.cmd.accent_offset * ctx.font_size) + stroke * 0.5)
    root_low := radical_root_low_offset(ctx.font_size, ctx.child^.descent)
    descent := max(ctx.child^.descent, root_low +
        max(stroke, stroke * 1.25) * 0.5)
    if index.cols > 0 {
        ascent = max(ascent, ctx.child^.ascent * 0.62 + index.ascent * 0.50 + script_top)
        descent = max(descent, index.descent * 0.2)
    }
    advance := dyncore.effective_advance(ctx.style, ctx.cache^.last_cell_width)
    lead := max(radical_lead_width(ctx.font_size, advance),
        index.draw_width + max(1.0, advance * 1.05))
    front, back := radical_side_paddings(ctx.font_size, advance)
    accent_pad := accent_script_clearance(ctx.font_size, scale, false)
    return {
        draw_width = lead + ctx.child^.draw_width + front + back,
        ascent = ascent, descent = descent,
        top_pad = max(ctx.child^.visual_padding_top, max(script_top, accent_pad)),
        bottom_pad = max(
            ctx.child^.visual_padding_bottom, max(script_bottom, accent_pad)),
    }
}

//   Build one layout-like item for a recursive radical wrapper around a child math program.
math_program_recursive_radical_item :: #force_inline proc(
    ctx: Math_Program_Item_Context) -> (app_core.Dynview_Layout_Item, bool) {

    child_program, ok := math_program_from_id(ctx.cache, ctx.cmd.math_program_id)
    radicand_style, radicand_size := math_child_font_size(
        ctx.cache, ctx.font_size, ctx.math_style, .Radical_Radicand)
    if !ok || !measure_math_program(
        ctx.cache, ctx.buffer, child_program, radicand_size, radicand_style) {
        return app_core.Dynview_Layout_Item{}, false
    }

    if ctx.cmd.secondary_math_program_id > 0 {
        degree_program, degree_ok := math_program_from_id(
            ctx.cache, ctx.cmd.secondary_math_program_id)
        degree_style, degree_size := math_child_font_size(
            ctx.cache, ctx.font_size, ctx.math_style, .Radical_Degree)
        if !degree_ok || !measure_math_program(
            ctx.cache, ctx.buffer, degree_program, degree_size, degree_style) {
            return app_core.Dynview_Layout_Item{}, false
        }
    }

    script_scale := max(0.2, ctx.cmd.script_scale)
    return radical_item(
        ctx.cmd, radical_geometry({ctx.cache, ctx.buffer, child_program,
            ctx.cmd, ctx.style, ctx.font_size}),
        script_scale), true
}

//   Adapt the text-run item builder (no style-independent result) to the table.
math_program_text_item_entry :: #force_inline proc(
    ctx: Math_Program_Item_Context) -> (app_core.Dynview_Layout_Item, bool) {
    return math_program_text_item(
        ctx.cache, ctx.buffer, ctx.cmd, ctx.style, ctx.font_size), true
}

//   Adapt the script-attach item builder (resolves its own style) to the table.
math_program_script_item_entry :: #force_inline proc(
    ctx: Math_Program_Item_Context) -> (app_core.Dynview_Layout_Item, bool) {
    return math_program_recursive_script_item(
        ctx.cache, ctx.buffer, ctx.cmd, ctx.font_size, ctx.math_style)
}

//   Adapt the accent-bar item builder (resolves its own style) to the table.
math_program_accent_item_entry :: #force_inline proc(
    ctx: Math_Program_Item_Context) -> (app_core.Dynview_Layout_Item, bool) {
    return math_program_recursive_accent_item(
        ctx.cache, ctx.buffer, ctx.cmd, ctx.font_size, ctx.math_style)
}

//   Adapt the large-op item builder (returns no bool) to the table shape.
math_program_large_op_item_entry :: #force_inline proc(
    ctx: Math_Program_Item_Context) -> (app_core.Dynview_Layout_Item, bool) {
    sup_style, sup_size := math_child_font_size(
        ctx.cache, ctx.font_size, ctx.math_style, .Superscript)
    sub_style, sub_size := math_child_font_size(
        ctx.cache, ctx.font_size, ctx.math_style, .Subscript)
    if ctx.cmd.secondary_math_program_id > 0 {
        program, found := math_program_from_id(
            ctx.cache, ctx.cmd.secondary_math_program_id)
        if !found || !measure_math_program(
            ctx.cache, ctx.buffer, program, sup_size, sup_style) {
            return app_core.Dynview_Layout_Item{}, false
        }
    }
    if ctx.cmd.tertiary_math_program_id > 0 {
        program, found := math_program_from_id(
            ctx.cache, ctx.cmd.tertiary_math_program_id)
        if !found || !measure_math_program(
            ctx.cache, ctx.buffer, program, sub_size, sub_style) {
            return app_core.Dynview_Layout_Item{}, false
        }
    }
    return math_program_large_op_item(ctx, sup_size / ctx.font_size), true
}

//   Build one layout item for a math-program command using the matching builder.
math_program_item :: #force_inline proc(
    ctx: Math_Program_Item_Context) -> (app_core.Dynview_Layout_Item, bool) {

    handlers := MATH_PROGRAM_ITEM_HANDLERS
    handler := handlers[ctx.cmd.kind]
    if handler == nil {
        return app_core.Dynview_Layout_Item{}, false
    }
    resolved_ctx := ctx
    resolved_ctx.style = dyncore.style_by_id(ctx.cmd.style_id)
    item, ok := handler(resolved_ctx)
    item.math_command_index = i32(ctx.command_index)
    item.math_style_level = u8(ctx.math_style.level)
    item.math_style_cramped = ctx.math_style.cramped
    item.math_font_size = ctx.font_size
    if ok && ctx.cmd.kind == .Large_Op && ctx.command_index >= 0 {
        math_program_apply_operator_variant(resolved_ctx, &item)
    }
    if ok && ctx.cmd.kind == .Stretch_Delimiter && ctx.command_index >= 0 {
        math_program_apply_stretch_delimiters(ctx, &item)
    }
    if ok && ctx.cmd.kind == .Radical_Bar && ctx.command_index >= 0 {
        geometry := math_program_radical_construction(
            ctx.cache, ctx.cmd, ctx.font_size, ctx.command_index, ctx.math_style)
        math_program_apply_radical_construction(geometry, &item)
    }
    if ok && ctx.cmd.kind == .Accent_Bar && ctx.cmd.accent_mode > 2 &&
        ctx.command_index >= 0 {
        math_program_apply_glyph_accent(ctx, &item)
    }
    return item, ok
}

//   Measure one flat child-command math program and cache its deterministic outer metrics.
math_program_is_measurable :: #force_inline proc(
    cache: ^app_core.Dynview_Compile_Cache,
    buffer: ^app_core.Dynview_Command_Buffer,
    program: ^app_core.Dynview_Math_Program) -> bool {

    return cache != nil && buffer != nil && program != nil && program^.valid &&
        program^.command_start >= 0 && program^.command_count > 0 &&
        program^.command_start + program^.command_count <= cache^.math_command_count
}

//   Accumulate one child item's outer metrics in command order.
math_program_metrics_include :: proc(
    metrics: ^Math_Program_Metrics,
    item: app_core.Dynview_Layout_Item,
    leading_space: f32) {
    metrics^.width += leading_space + item.draw_width
    item_advance := item.math_advance
    if item_advance <= 0 {
        item_advance = item.draw_width
    }
    metrics^.advance += leading_space + item_advance
    metrics^.ascent = max(metrics^.ascent, item.ascent)
    metrics^.descent = max(metrics^.descent, item.descent)
    metrics^.top_pad = max(metrics^.top_pad, item.visual_padding_top)
    metrics^.bottom_pad = max(metrics^.bottom_pad, item.visual_padding_bottom)
    metrics^.italic_correction = item.italic_correction
    metrics^.top_accent_attachment = item.top_accent_attachment
    if item.math_has_edge_glyphs {
        if !metrics^.has_edge_glyphs {
            metrics^.first_glyph_id = item.math_first_glyph_id
            metrics^.has_edge_glyphs = true
        }
        metrics^.last_glyph_id = item.math_last_glyph_id
    }
}

//   Publish one complete aggregate measurement to its math program.
math_program_metrics_apply :: proc(
    program: ^app_core.Dynview_Math_Program,
    metrics: Math_Program_Metrics) {
    program^.draw_width = metrics.width
    program^.advance = metrics.advance
    program^.ascent = max(1.0, metrics.ascent)
    program^.descent = max(1.0, metrics.descent)
    program^.visual_padding_top = metrics.top_pad
    program^.visual_padding_bottom = metrics.bottom_pad
    program^.italic_correction = metrics.italic_correction
    program^.top_accent_attachment = metrics.top_accent_attachment
    program^.first_glyph_id = metrics.first_glyph_id
    program^.last_glyph_id = metrics.last_glyph_id
    program^.has_edge_glyphs = metrics.has_edge_glyphs
}

//   Measure one flat child-command math program and cache its deterministic outer metrics.
measure_math_program :: proc(
    cache: ^app_core.Dynview_Compile_Cache,
    buffer: ^app_core.Dynview_Command_Buffer,
    program: ^app_core.Dynview_Math_Program,
    font_size: f32,
    math_style: Math_Style = {.Display, false}) -> bool {

    if !math_program_is_measurable(cache, buffer, program) {
        return false
    }

    metrics: Math_Program_Metrics
    command_end := program^.command_start + program^.command_count
    for command_index in program^.command_start..<command_end {
        cmd := cache^.math_commands[command_index]
        item, ok := math_program_item({
            cache = cache, buffer = buffer, cmd = cmd, font_size = font_size,
            command_index = command_index, math_style = math_style,
        })
        if !ok {
            return false
        }

        leading_space := math_program_command_leading_space(
            cache, program^, command_index, font_size)
        math_program_metrics_include(&metrics, item, leading_space)
    }
    math_program_metrics_apply(program, metrics)
    return true
}
