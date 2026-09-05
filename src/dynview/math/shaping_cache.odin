package dynview_math

import app_core "../../core"
import dyncore "../core"

MATH_ACCENT_TEXTS :: [16]string{
    "", "", "", "̂", "̃", "⃗", "̇", "̈",
    "̄", "̌", "̆", "́", "̀", "̊", "⏞", "⏟",
}

Math_Shape_Request :: struct {
    generation: u64,
    text: string,
    italic: bool,
    standalone_accent: bool,
    flattened_accent: bool,
    projection_workspace: []u8,
    glyph_output: []app_core.Shaped_Glyph,
}

Math_Shape_Result :: struct {
    glyph_count: int,
    ok: bool,
}

// Shape one semantic math text site into caller-owned temporary glyph storage.
Math_Shape_Handler :: #type proc(
    user_data: rawptr,
    request: Math_Shape_Request) -> Math_Shape_Result

Math_Glyph_Metrics_Request :: struct {
    generation: u64,
    glyph_id: u32,
}

Math_Glyph_Metrics_Result :: struct {
    extents: app_core.Font_Glyph_Extents,
    italic_correction: i32,
    top_accent_attachment: i32,
    ok: bool,
}

// Query approved intrinsic and OpenType MATH metrics for one shaped glyph.
Math_Glyph_Metrics_Handler :: #type proc(
    user_data: rawptr,
    request: Math_Glyph_Metrics_Request) -> Math_Glyph_Metrics_Result

Math_Glyph_Variants_Request :: struct {
    generation: u64,
    glyph_id: u32,
    output: []app_core.Font_Math_Glyph_Variant,
}

Math_Glyph_Variants_Result :: struct {
    count: int,
    extended_shape: bool,
    ok: bool,
}

// Query one bounded generation-specific vertical glyph variant set.
Math_Glyph_Variants_Handler :: #type proc(
    user_data: rawptr,
    request: Math_Glyph_Variants_Request) -> Math_Glyph_Variants_Result

Math_Glyph_Assembly_Request :: struct {
    generation: u64,
    glyph_id: u32,
    output: []app_core.Font_Math_Glyph_Part,
}

Math_Glyph_Assembly_Result :: struct {
    count: int,
    min_connector_overlap: i32,
    italic_correction: i32,
    ok: bool,
}

// Query one bounded generation-specific vertical glyph assembly.
Math_Glyph_Assembly_Handler :: #type proc(
    user_data: rawptr,
    request: Math_Glyph_Assembly_Request) -> Math_Glyph_Assembly_Result

Math_Glyph_Kern_Table_Request :: struct {
    generation: u64,
    glyph_id: u32,
    corner: u8,
    output: []app_core.Font_Math_Kern_Entry,
}

Math_Glyph_Kern_Table_Result :: struct {
    count: int,
    ok: bool,
}

// Query one bounded generation-specific glyph corner kern table.
Math_Glyph_Kern_Table_Handler :: #type proc(
    user_data: rawptr,
    request: Math_Glyph_Kern_Table_Request) -> Math_Glyph_Kern_Table_Result

// Borrow worker-owned shaping behavior and temporary storage for one cache rebuild.
Math_Shaping_Service :: struct {
    user_data: rawptr,
    generation: u64,
    base_pixel_size: f32,
    raster_ascent: f32,
    constants: app_core.Font_Math_Constants,
    shape: Math_Shape_Handler,
    glyph_metrics: Math_Glyph_Metrics_Handler,
    glyph_variants: Math_Glyph_Variants_Handler,
    glyph_assembly: Math_Glyph_Assembly_Handler,
    horizontal_glyph_variants: Math_Glyph_Variants_Handler,
    horizontal_glyph_assembly: Math_Glyph_Assembly_Handler,
    glyph_kern_table: Math_Glyph_Kern_Table_Handler,
    projection_workspace: []u8,
    glyph_workspace: []app_core.Shaped_Glyph,
}

// Scaled shaped-run dimensions consumed by recursive math layout.
Shaped_Run_Layout_Metrics :: struct {
    draw_width: f32,
    advance: f32,
    ascent: f32,
    descent: f32,
    italic_correction: f32,
    top_accent_attachment: f32,
}

Shaped_Ink_Bounds :: struct {
    left, right, top, bottom: i32,
}

Shape_Command_Site_Context :: struct {
    builder: ^Dynview_Shaped_Builder,
    runtime: ^app_core.Dynview_System,
    service: Math_Shaping_Service,
    command_index: int,
    command: app_core.Dynview_Command,
}

Math_Command_Site :: struct {
    offset, count: int,
    style_id: i32,
    eligible: bool,
}

Shaped_Measure_Accumulator :: struct {
    pen_x: i32,
    bounds: Shaped_Ink_Bounds,
    trailing_italic: i32,
    top_accent: i32,
}

//   Return one sealed shaped run for a math command site.
shaped_run_for_command :: #force_inline proc(
    cache: ^app_core.Dynview_Compile_Cache,
    command: app_core.Dynview_Command,
    site: app_core.Dynview_Shaped_Site) -> (^app_core.Dynview_Shaped_Run, bool) {

    run_index := int(command.shaped_run_indices[int(site)])
    if cache == nil || run_index < 0 || run_index >= len(cache^.shaped_runs) {
        return nil, false
    }
    run := &cache^.shaped_runs[run_index]
    return run, run^.font_generation == cache^.shaped_font_generation &&
        run^.site == site
}

//   Scale cached 32-pixel shaping metrics to one requested math size.
shaped_run_layout_metrics :: #force_inline proc(
    run: ^app_core.Dynview_Shaped_Run,
    font_size: f32) -> (Shaped_Run_Layout_Metrics, bool) {

    if run == nil || run^.base_pixel_size <= 0 || font_size <= 0 {
        return {}, false
    }
    scale := font_size / run^.base_pixel_size
    left := min(0, run^.ink_left)
    right := max(run^.advance, run^.ink_right)
    return {
        draw_width = max(1, (right-left)*scale),
        advance = max(1, run^.advance*scale),
        ascent = max(1, run^.ascent*scale),
        descent = max(1, run^.descent*scale),
        italic_correction = max(0, run^.italic_correction*scale),
        top_accent_attachment = run^.top_accent_attachment*scale,
    }, true
}

//   Return the complete sealed glyph slice for one shaped run.
shaped_glyphs_for_run :: #force_inline proc(
    cache: ^app_core.Dynview_Compile_Cache,
    run: ^app_core.Dynview_Shaped_Run) -> ([]app_core.Shaped_Glyph, bool) {

    if cache == nil || run == nil || run^.glyph_start < 0 || run^.glyph_count <= 0 {
        return nil, false
    }
    glyph_end := run^.glyph_start + run^.glyph_count
    if glyph_end > len(cache^.shaped_glyphs) {
        return nil, false
    }
    return cache^.shaped_glyphs[run^.glyph_start:glyph_end], true
}

//   Shape every supported site for all compiled math commands.
shape_all_math_command_sites :: proc(
    builder: ^Dynview_Shaped_Builder,
    runtime: ^app_core.Dynview_System,
    service: Math_Shaping_Service) -> app_core.Bounded_Builder_Status {

    cache := &runtime^.compile_cache
    for command_index in 0..<cache^.math_command_count {
        command := cache^.math_commands[command_index]
        ctx := Shape_Command_Site_Context{
            builder, runtime, service, command_index, command}
        for site in app_core.Dynview_Shaped_Site {
            status := shape_math_command_site(ctx, site)
            if status != .Ok {
                return status
            }
        }
    }
    return .Ok
}

//   Build and atomically seal proportional records for supported math text sites.
rebuild_shaped_math_cache :: proc(
    runtime: ^app_core.Dynview_System,
    arena: ^app_core.Arena_Owner,
    service: Math_Shaping_Service) -> app_core.Bounded_Builder_Status {

    cache := &runtime^.compile_cache
    clear_shaped_records(cache)
    if cache^.math_command_count <= 0 || !math_shaping_service_ready(service) {
        return .Ok
    }
    builder: Dynview_Shaped_Builder
    status := shaped_builder_init(&builder, arena, service.generation)
    if status != .Ok {
        return status
    }
    status = shape_all_math_command_sites(&builder, runtime, service)
    if status != .Ok {
        clear_shaped_records(cache)
        return status
    }
    status = shaped_builder_seal(&builder, cache,
        len(dyncore.command_buffer_text(&runtime^.command_buffer)),
        cache^.math_command_count, service.generation)
    if status == .Ok {
        cache^.math_constants = service.constants
        status = cache_math_kern_records(runtime, arena, service)
    }
    if status == .Ok {
        cache_math_operator_variant_records(runtime, service)
        cache_math_stretch_source_records(runtime, service)
        status = cache_math_accent_source_records(runtime, arena, service)
    }
    if status != .Ok {
        clear_shaped_records(cache)
    }
    return status
}

//   Report whether one borrowed shaping service can process a complete rebuild.
math_shaping_service_ready :: #force_inline proc(service: Math_Shaping_Service) -> bool {
    return service.generation != 0 && service.base_pixel_size > 0 &&
        service.raster_ascent > 0 &&
        math_constants_are_current(service.constants, service.generation) &&
        service.shape != nil && service.glyph_metrics != nil &&
        service.glyph_variants != nil && service.glyph_assembly != nil &&
        service.horizontal_glyph_variants != nil &&
        service.horizontal_glyph_assembly != nil &&
        service.glyph_kern_table != nil &&
        len(service.projection_workspace) > 0 && len(service.glyph_workspace) > 0
}

//   Query one complete edge-glyph corner record into unpublished arena storage.
cache_math_kern_record :: proc(
    service: Math_Shaping_Service,
    glyph_id: u32,
    corner: u8,
    record: ^app_core.Font_Math_Kern_Table) -> bool {

    result := service.glyph_kern_table(service.user_data, {
        generation = service.generation, glyph_id = glyph_id, corner = corner,
        output = record^.entries[:],
    })
    if !result.ok || result.count < 0 || result.count > len(record^.entries) {
        return false
    }
    record^.valid = true
    record^.generation = service.generation
    record^.glyph_id = glyph_id
    record^.corner = corner
    record^.count = result.count
    return true
}

//   Publish four immutable edge kern tables for every sealed shaped run.
cache_math_kern_records :: proc(
    runtime: ^app_core.Dynview_System,
    arena: ^app_core.Arena_Owner,
    service: Math_Shaping_Service) -> app_core.Bounded_Builder_Status {

    cache := &runtime^.compile_cache
    count := len(cache^.shaped_runs) * 4
    allocator := app_core.arena_owner_allocator(arena)
    tables, allocation_error := make(
        []app_core.Font_Math_Kern_Table, count, allocator)
    if allocation_error != nil {
        return .Allocation_Failed
    }
    for _, run_index in cache^.shaped_runs {
        glyphs, ok := shaped_glyphs_for_run(
            cache, &cache^.shaped_runs[run_index])
        if !ok {
            return .Invalid_Argument
        }
        edge_glyphs := [4]u32{
            glyphs[len(glyphs)-1].glyph_id, glyphs[0].glyph_id,
            glyphs[len(glyphs)-1].glyph_id, glyphs[0].glyph_id}
        for corner in u8(0)..=u8(3) {
            record := &tables[run_index*4+int(corner)]
            if !cache_math_kern_record(
                service, edge_glyphs[int(corner)], corner, record) {
                return .Invalid_Argument
            }
        }
    }
    cache^.math_kern_tables = tables
    return .Ok
}

//   Shape, measure, and append one already validated semantic text site.
shape_valid_math_command_site :: proc(
    ctx: Shape_Command_Site_Context,
    site: app_core.Dynview_Shaped_Site,
    command_site: Math_Command_Site,
    text: string) -> app_core.Bounded_Builder_Status {
    service := ctx.service
    result := service.shape(service.user_data, {
        generation = service.generation,
        text = text,
        italic = dyncore.style_by_id(command_site.style_id).italic,
        flattened_accent = false,
        projection_workspace = service.projection_workspace,
        glyph_output = service.glyph_workspace,
    })
    if !result.ok || result.glyph_count <= 0 ||
        result.glyph_count > len(service.glyph_workspace) {
        return .Ok
    }
    glyphs := service.glyph_workspace[:result.glyph_count]
    metrics, measured := measure_shaped_glyphs(service, glyphs)
    if !measured {
        return .Ok
    }
    status := shaped_builder_append(ctx.builder, {
        math_command_index = ctx.command_index,
        site = site,
        text_offset = command_site.offset,
        text_len = command_site.count,
        glyphs = glyphs,
        metrics = metrics,
    })
    return status
}

// Cache one display-growing operator's bounded vertical variants by command index.
cache_math_operator_variants :: proc(
    cache: ^app_core.Dynview_Compile_Cache,
    service: Math_Shaping_Service,
    command_index: int,
    glyph_id: u32) {

    record := &cache^.math_operator_variants[command_index]
    result := service.glyph_variants(service.user_data, {
        generation = service.generation,
        glyph_id = glyph_id,
        output = record^.values[:],
    })
    if !result.ok || result.count <= 0 || result.count > len(record^.values) {
        record^ = {}
        return
    }
    record^.valid = true
    record^.generation = service.generation
    record^.base_glyph_id = glyph_id
    record^.extended_shape = result.extended_shape
    record^.count = result.count
}

//   Publish variants for sealed primary runs of display-growing operators.
cache_math_operator_variant_records :: proc(
    runtime: ^app_core.Dynview_System,
    service: Math_Shaping_Service) {

    cache := &runtime^.compile_cache
    for command_index in 0..<cache^.math_command_count {
        command := cache^.math_commands[command_index]
        if command.kind != .Large_Op ||
            command.operator_growth != OPERATOR_GROWTH_DISPLAY {
            continue
        }
        run, run_ok := shaped_run_for_command(cache, command, .Primary)
        glyphs, glyphs_ok := shaped_glyphs_for_run(cache, run)
        if run_ok && glyphs_ok && len(glyphs) > 0 {
            cache_math_operator_variants(
                cache, service, command_index, glyphs[0].glyph_id)
        }
    }
}

//   Query one shaped glyph's ready variants and optional assembly recipe.
cache_math_stretch_source :: proc(
    service: Math_Shaping_Service,
    glyph_id: u32,
    source: ^app_core.Font_Math_Stretch_Source) {

    source^.raster_ascent = service.raster_ascent
    variant_result := service.glyph_variants(service.user_data, {
        generation = service.generation, glyph_id = glyph_id,
        output = source^.variants.values[:],
    })
    if variant_result.ok && variant_result.count > 0 {
        source^.variants.valid = true
        source^.variants.generation = service.generation
        source^.variants.base_glyph_id = glyph_id
        source^.variants.extended_shape = variant_result.extended_shape
        source^.variants.count = variant_result.count
    }
    assembly_result := service.glyph_assembly(service.user_data, {
        generation = service.generation, glyph_id = glyph_id,
        output = source^.assembly.values[:],
    })
    if assembly_result.ok && assembly_result.count > 0 {
        source^.assembly.valid = true
        source^.assembly.generation = service.generation
        source^.assembly.base_glyph_id = glyph_id
        source^.assembly.min_connector_overlap =
            assembly_result.min_connector_overlap
        source^.assembly.italic_correction = assembly_result.italic_correction
        source^.assembly.count = assembly_result.count
    }
}

//   Resolve one semantic delimiter text to its single base glyph.
math_stretch_base_glyph :: proc(
    service: Math_Shaping_Service,
    text: string,
    flattened_accent: bool = false) -> (u32, bool) {

    result := service.shape(service.user_data, {
        generation = service.generation, text = text,
        flattened_accent = flattened_accent,
        projection_workspace = service.projection_workspace,
        glyph_output = service.glyph_workspace,
    })
    if !result.ok || result.glyph_count != 1 {
        return 0, false
    }
    return service.glyph_workspace[0].glyph_id, true
}

//   Return the semantic combining glyph text for one glyph-accent mode.
math_accent_text :: proc(accent_mode: i32) -> string {
    if accent_mode < 0 || int(accent_mode) >= len(MATH_ACCENT_TEXTS) {
        return ""
    }
    texts := MATH_ACCENT_TEXTS
    return texts[accent_mode]
}

//   Query one accent glyph's horizontal variants and assembly.
cache_math_accent_source :: proc(
    service: Math_Shaping_Service,
    base: app_core.Font_Math_Glyph_Variant,
    source: ^app_core.Font_Math_Stretch_Source) -> bool {

    source^.raster_ascent = service.raster_ascent
    source^.variants.valid = true
    source^.variants.generation = service.generation
    source^.variants.base_glyph_id = base.glyph_id
    source^.variants.count = 1
    source^.variants.values[0] = base
    variant_result := service.horizontal_glyph_variants(service.user_data, {
        generation = service.generation, glyph_id = base.glyph_id,
        output = source^.variants.values[:],
    })
    if variant_result.ok && variant_result.count > 0 {
        source^.variants.valid = true
        source^.variants.generation = service.generation
        source^.variants.base_glyph_id = base.glyph_id
        source^.variants.count = variant_result.count
    }
    assembly_result := service.horizontal_glyph_assembly(service.user_data, {
        generation = service.generation, glyph_id = base.glyph_id,
        output = source^.assembly.values[:],
    })
    if assembly_result.ok && assembly_result.count > 0 {
        source^.assembly.valid = true
        source^.assembly.generation = service.generation
        source^.assembly.base_glyph_id = base.glyph_id
        source^.assembly.min_connector_overlap = assembly_result.min_connector_overlap
        source^.assembly.italic_correction = assembly_result.italic_correction
        source^.assembly.count = assembly_result.count
    }
    return source^.variants.valid || source^.assembly.valid
}

//   Shape and measure the intrinsic narrow glyph for one accent source.
math_accent_base_variant :: proc(
    service: Math_Shaping_Service,
    text: string,
    flattened: bool) -> (app_core.Font_Math_Glyph_Variant, bool) {

    result := service.shape(service.user_data, {
        generation = service.generation, text = text,
        standalone_accent = true,
        flattened_accent = flattened,
        projection_workspace = service.projection_workspace,
        glyph_output = service.glyph_workspace,
    })
    if !result.ok || result.glyph_count != 1 {
        return {}, false
    }
    glyph := service.glyph_workspace[0]
    metrics := service.glyph_metrics(
        service.user_data, {service.generation, glyph.glyph_id})
    if !metrics.ok {
        return {}, false
    }
    return {
        glyph_id = glyph.glyph_id, advance = max(1, glyph.x_advance),
        extents = metrics.extents,
        italic_correction = metrics.italic_correction,
        top_accent_attachment = metrics.top_accent_attachment,
    }, true
}

//   Publish normal and flattened horizontal sources for every glyph accent.
cache_math_accent_source_records :: proc(
    runtime: ^app_core.Dynview_System,
    arena: ^app_core.Arena_Owner,
    service: Math_Shaping_Service) -> app_core.Bounded_Builder_Status {

    cache := &runtime^.compile_cache
    allocator := app_core.arena_owner_allocator(arena)
    sources, allocation_error := make([][2]app_core.Font_Math_Stretch_Source,
        cache^.math_command_count, allocator)
    if allocation_error != nil {
        return .Allocation_Failed
    }
    for command, command_index in cache^.math_commands[:cache^.math_command_count] {
        text := math_accent_text(command.accent_mode)
        if command.kind != .Accent_Bar || len(text) == 0 {
            continue
        }
        for flattened in 0..=1 {
            base, ok := math_accent_base_variant(
                service, text, flattened == 1)
            if !ok {
                return .Invalid_Argument
            }
            if !cache_math_accent_source(
                service, base, &sources[command_index][flattened]) {
                return .Invalid_Argument
            }
        }
    }
    cache^.math_accent_sources = sources
    return .Ok
}

//   Publish radical and visible delimiter construction sources after cache sealing.
cache_math_stretch_source_records :: proc(
    runtime: ^app_core.Dynview_System,
    service: Math_Shaping_Service) {

    cache := &runtime^.compile_cache
    for command_index in 0..<cache^.math_command_count {
        command := cache^.math_commands[command_index]
        texts := [2]string{}
        if command.kind == .Radical_Bar {
            texts[0] = "√"
        } else if command.kind == .Stretch_Delimiter {
            texts = {delimiter_text(command.accent_mode),
                delimiter_text(command.radical_mode)}
        } else {
            continue
        }
        for text, side in texts {
            glyph_id, found := math_stretch_base_glyph(service, text)
            if found {
                cache_math_stretch_source(service, glyph_id,
                    &cache^.math_stretch_sources[command_index][side])
            }
        }
    }
}

//   Shape one eligible command site, retaining baseline fallback on native rejection.
shape_math_command_site :: proc(
    ctx: Shape_Command_Site_Context,
    site: app_core.Dynview_Shaped_Site) -> app_core.Bounded_Builder_Status {

    command_site := math_command_site(ctx.command, site)
    if !command_site.eligible || command_site.count <= 0 {
        return .Ok
    }
    text_bytes := dyncore.command_buffer_text(&ctx.runtime^.command_buffer)
    if command_site.offset < 0 ||
        command_site.count > len(text_bytes)-command_site.offset {
        return .Invalid_Argument
    }
    text := string(text_bytes[
        command_site.offset:command_site.offset+command_site.count])
    return shape_valid_math_command_site(ctx, site, command_site, text)
}

//   Select one semantic text span and style from a recursive math command.
math_command_site :: #force_inline proc(
    command: app_core.Dynview_Command,
    site: app_core.Dynview_Shaped_Site) -> Math_Command_Site {

    switch site {
    case .Primary:
        eligible := command.kind == .Math_Glyph_Run || command.kind == .Large_Op
        return {command.text_offset, command.text_len, command.style_id, eligible}
    case .Superscript:
        eligible := command.kind == .Script_Attach || command.kind == .Large_Op
        return {command.script_sup_text_offset, command.script_sup_text_len,
            command.script_style_id, eligible}
    case .Subscript:
        eligible := command.kind == .Script_Attach || command.kind == .Large_Op
        return {command.script_sub_text_offset, command.script_sub_text_len,
            command.script_style_id, eligible}
    case .Radical_Index:
        return {command.radical_index_text_offset, command.radical_index_text_len,
            command.script_style_id, command.kind == .Radical_Bar}
    }
    return {}
}

//   Aggregate one shaped run's advance, ink bounds, and approved MATH values.
measure_shaped_glyphs :: proc(
    service: Math_Shaping_Service,
    glyphs: []app_core.Shaped_Glyph) -> (app_core.Dynview_Shaped_Run, bool) {

    accumulator: Shaped_Measure_Accumulator
    for glyph, glyph_index in glyphs {
        if !measure_shaped_glyph_include(
            &accumulator, service, glyph, glyph_index) {
            return {}, false
        }
    }
    unit := f32(1.0 / 64.0)
    return app_core.Dynview_Shaped_Run{
        base_pixel_size = service.base_pixel_size,
        raster_ascent = service.raster_ascent,
        advance = f32(accumulator.pen_x) * unit,
        ink_left = f32(accumulator.bounds.left) * unit,
        ink_right = f32(accumulator.bounds.right) * unit,
        ascent = max(0, f32(accumulator.bounds.top) * unit),
        descent = max(0, -f32(accumulator.bounds.bottom) * unit),
        italic_correction = f32(accumulator.trailing_italic) * unit,
        top_accent_attachment = f32(accumulator.top_accent) * unit,
    }, true
}

//   Query and accumulate one positioned glyph's intrinsic and MATH metrics.
measure_shaped_glyph_include :: proc(
    accumulator: ^Shaped_Measure_Accumulator,
    service: Math_Shaping_Service,
    glyph: app_core.Shaped_Glyph,
    glyph_index: int) -> bool {

    metrics := service.glyph_metrics(service.user_data,
        {service.generation, glyph.glyph_id})
    if !metrics.ok {
        return false
    }
    left := accumulator^.pen_x + glyph.x_offset + metrics.extents.x_bearing
    top := glyph.y_offset + metrics.extents.y_bearing
    right := left + metrics.extents.width
    bottom := top + metrics.extents.height
    if glyph_index == 0 {
        accumulator^.bounds = {left, right, top, bottom}
        accumulator^.top_accent = metrics.top_accent_attachment
    } else {
        shaped_ink_bounds_include(&accumulator^.bounds, left, right, top, bottom)
    }
    accumulator^.pen_x += glyph.x_advance
    accumulator^.trailing_italic = metrics.italic_correction
    return true
}

//   Expand aggregate ink bounds with one positioned glyph extent.
shaped_ink_bounds_include :: #force_inline proc(
    bounds: ^Shaped_Ink_Bounds,
    left, right, top, bottom: i32) {

    bounds^.left = min(bounds^.left, left)
    bounds^.right = max(bounds^.right, right)
    bounds^.top = max(bounds^.top, top)
    bounds^.bottom = min(bounds^.bottom, bottom)
}