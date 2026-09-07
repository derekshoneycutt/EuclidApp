package dynview_compile

import app_core "../../core"

import "base:runtime"

// Number of JuliaMono variants preceding the dedicated math face.
DOCUMENT_PROSE_FONT_COUNT :: int(app_core.Font_Key.Math_Regular)

// Identify one effective resident face borrowed for a prose rebuild.
Document_Prose_Font :: struct {
    effective_key: app_core.Font_Key,
    generation: u64,
    raster_ascent: f32,
}

// Request exact-generation shaping into caller-owned temporary storage.
Document_Prose_Shape_Request :: struct {
    key: app_core.Font_Key,
    generation: u64,
    text: string,
    output: []app_core.Shaped_Glyph,
}

// Shape one prose run without retaining its source or output storage.
Document_Prose_Shape_Handler :: #type proc(
    user_data: rawptr,
    request: Document_Prose_Shape_Request) -> (int, bool)

// Query one exact-generation prose glyph's ink extents.
Document_Prose_Extents_Handler :: #type proc(
    user_data: rawptr, key: app_core.Font_Key,
    generation: u64, glyph_id: u32) -> (app_core.Font_Glyph_Extents, bool)

// Borrow immutable face identities, callbacks, and workspace for one rebuild.
Document_Prose_Shaping_Service :: struct {
    user_data: rawptr,
    fonts: [DOCUMENT_PROSE_FONT_COUNT]Document_Prose_Font,
    base_pixel_size: f32,
    shape: Document_Prose_Shape_Handler,
    glyph_extents: Document_Prose_Extents_Handler,
    glyph_workspace: []app_core.Shaped_Glyph,
}

// Hold one shaped prose run's aggregate advance and ink measurements.
Document_Shaped_Run_Metrics :: struct {
    width: f32,
    ascent: f32,
    descent: f32,
}

// Build bounded prose runs and glyphs before atomic cache publication.
Document_Shaped_Builder :: struct {
    runs: app_core.Bounded_Element_Builder(app_core.Dynview_Document_Shaped_Run),
    glyphs: app_core.Bounded_Element_Builder(app_core.Shaped_Glyph),
    initialized: bool,
}

// Describe one complete prose run presented for transactional append.
Document_Shaped_Append :: struct {
    run: app_core.Dynview_Document_Shaped_Run,
    glyphs: []app_core.Shaped_Glyph,
}

// Initialize prose shaping builders through a supplied allocator.
document_shaped_builder_init :: proc(
    builder: ^Document_Shaped_Builder,
    allocator: runtime.Allocator) -> app_core.Bounded_Builder_Status {

    if builder == nil {
        return .Invalid_Argument
    }
    run_status := app_core.bounded_element_builder_init_with_allocator(
        &builder^.runs, app_core.DYNVIEW_MAX_DOCUMENT_SHAPED_RUNS, allocator)
    if run_status != .Ok {
        return run_status
    }
    glyph_status := app_core.bounded_element_builder_init_with_allocator(
        &builder^.glyphs, app_core.DYNVIEW_MAX_DOCUMENT_SHAPED_GLYPHS, allocator)
    if glyph_status != .Ok {
        builder^ = {}
        return glyph_status
    }
    builder^.initialized = true
    return .Ok
}

// Append one complete prose run without exposing a partial glyph span.
document_shaped_builder_append :: proc(
    builder: ^Document_Shaped_Builder,
    append: Document_Shaped_Append) -> app_core.Bounded_Builder_Status {

    run := append.run
    if builder == nil || !builder^.initialized || run.inline_index < 0 ||
        run.text_offset < 0 || run.text_count <= 0 || len(append.glyphs) <= 0 ||
        run.font_generation == 0 || run.base_pixel_size <= 0 {
        return .Invalid_Argument
    }
    glyph_status := app_core.bounded_element_builder_reserve(
        &builder^.glyphs, len(append.glyphs))
    if glyph_status != .Ok {
        return glyph_status
    }
    run_status := app_core.bounded_element_builder_reserve(&builder^.runs, 1)
    if run_status != .Ok {
        return run_status
    }
    run.glyph_start = builder^.glyphs.count
    run.glyph_count = len(append.glyphs)
    copy(builder^.glyphs.storage[run.glyph_start:], append.glyphs)
    builder^.glyphs.count += len(append.glyphs)
    builder^.runs.storage[builder^.runs.count] = run
    builder^.runs.count += 1
    return .Ok
}

// Remove every sealed prose shaping alias from a compile cache.
clear_document_shaped_records :: proc(cache: ^app_core.Dynview_Compile_Cache) {
    if cache == nil {
        return
    }
    cache^.document_shaped_runs = nil
    cache^.document_shaped_glyphs = nil
}

// Validate ordered inline, text, glyph, and generation spans before publication.
document_shaped_builder_can_seal :: proc(
    builder: ^Document_Shaped_Builder,
    inline_count, text_count: int,
    current_generations: []u64) -> bool {

    if builder == nil || !builder^.initialized || inline_count < 0 || text_count < 0 {
        return false
    }
    previous_inline := -1
    for run in builder^.runs.storage[:builder^.runs.count] {
        key_index := int(run.effective_font_key)
        if run.inline_index <= previous_inline || run.inline_index >= inline_count ||
            run.text_offset < 0 || run.text_count <= 0 ||
            run.text_count > text_count-run.text_offset || run.glyph_start < 0 ||
            run.glyph_count <= 0 ||
            run.glyph_count > builder^.glyphs.count-run.glyph_start ||
            key_index < 0 || key_index >= len(current_generations) ||
            run.font_generation != current_generations[key_index] ||
            run.raster_ascent <= 0 {
            return false
        }
        previous_inline = run.inline_index
    }
    return true
}

// Seal validated prose records and publish both immutable slices atomically.
document_shaped_builder_seal :: proc(
    builder: ^Document_Shaped_Builder,
    cache: ^app_core.Dynview_Compile_Cache,
    inline_count, text_count: int,
    current_generations: []u64) -> app_core.Bounded_Builder_Status {

    if cache == nil || !document_shaped_builder_can_seal(
        builder, inline_count, text_count, current_generations) {
        clear_document_shaped_records(cache)
        return .Invalid_Argument
    }
    runs, run_status := app_core.bounded_element_builder_seal(&builder^.runs)
    if run_status != .Ok {
        clear_document_shaped_records(cache)
        return run_status
    }
    glyphs, glyph_status := app_core.bounded_element_builder_seal(&builder^.glyphs)
    if glyph_status != .Ok {
        clear_document_shaped_records(cache)
        return glyph_status
    }
    cache^.document_shaped_runs = runs
    cache^.document_shaped_glyphs = glyphs
    return .Ok
}

// Accumulate one shaped run's advance and ink bounds in HarfBuzz pixel units.
document_shaped_run_metrics :: proc(
    service: Document_Prose_Shaping_Service,
    font: Document_Prose_Font,
    glyphs: []app_core.Shaped_Glyph) -> (Document_Shaped_Run_Metrics, bool) {

    pen_x, pen_y: i32
    top, bottom: i32
    for glyph in glyphs {
        extents, ok := service.glyph_extents(
            service.user_data, font.effective_key, font.generation, glyph.glyph_id)
        if !ok {
            return {}, false
        }
        glyph_top := pen_y + glyph.y_offset + extents.y_bearing
        glyph_bottom := glyph_top + extents.height
        top = max(top, max(glyph_top, glyph_bottom))
        bottom = min(bottom, min(glyph_top, glyph_bottom))
        pen_x += glyph.x_advance
        pen_y += glyph.y_advance
    }
    return {
        width = max(0, f32(pen_x)/64),
        ascent = max(0, f32(top)/64),
        descent = max(0, f32(-bottom)/64),
    }, true
}

// Report whether HarfBuzz clusters remain ordered inside one source byte span.
document_shaped_clusters_are_valid :: proc(
    glyphs: []app_core.Shaped_Glyph, text_count: int) -> bool {

    previous: u32
    for glyph, index in glyphs {
        if glyph.cluster >= u32(text_count) || index > 0 && glyph.cluster < previous {
            return false
        }
        previous = glyph.cluster
    }
    return true
}

// Measure one complete shaped result and append its sealed run metadata.
document_append_measured_run :: proc(
    builder: ^Document_Shaped_Builder,
    service: Document_Prose_Shaping_Service,
    font: Document_Prose_Font,
    glyphs: []app_core.Shaped_Glyph,
    run: app_core.Dynview_Document_Shaped_Run) -> app_core.Bounded_Builder_Status {

    metrics, measured := document_shaped_run_metrics(
        service, font, glyphs)
    if !measured {
        return .Invalid_Argument
    }
    measured_run := run
    measured_run.width = metrics.width
    measured_run.ascent = metrics.ascent
    measured_run.descent = metrics.descent
    return document_shaped_builder_append(builder, {measured_run, glyphs})
}

// Resolve one nonempty inline text span without escaping snapshot-owned bytes.
document_inline_text :: proc(
    document_text: []u8,
    item: app_core.Dynview_Document_Inline) -> (string, bool) {

    if item.text_offset < 0 || item.text_count <= 0 ||
        item.text_count > len(document_text)-item.text_offset {
        return "", false
    }
    return string(document_text[
        item.text_offset:item.text_offset+item.text_count]), true
}

// Shape and append one eligible semantic prose inline.
document_shape_inline :: proc(
    builder: ^Document_Shaped_Builder,
    service: Document_Prose_Shaping_Service,
    document_text: []u8,
    item: app_core.Dynview_Document_Inline,
    inline_index: int) -> app_core.Bounded_Builder_Status {

    text, text_ok := document_inline_text(document_text, item)
    if !text_ok {
        return .Invalid_Argument
    }
    requested_key := app_core.font_key_from_flags(
        app_core.Font_Variant_Flags(item.font_flags))
    font := service.fonts[int(requested_key)]
    glyph_count, shaped := service.shape(service.user_data, {
        font.effective_key, font.generation, text, service.glyph_workspace})
    if !shaped || glyph_count <= 0 || glyph_count > len(service.glyph_workspace) {
        return .Invalid_Argument
    }
    glyphs := service.glyph_workspace[:glyph_count]
    if !document_shaped_clusters_are_valid(glyphs, item.text_count) {
        return .Invalid_Argument
    }
    return document_append_measured_run(builder, service, font, glyphs, {
        inline_index = inline_index,
        text_offset = item.text_offset,
        text_count = item.text_count,
        requested_font_key = requested_key,
        effective_font_key = font.effective_key,
        font_generation = font.generation,
        base_pixel_size = service.base_pixel_size,
        raster_ascent = font.raster_ascent,
    })
}

// Return true when every requested JuliaMono variant has an effective generation.
document_prose_shaping_service_ready :: proc(
    service: Document_Prose_Shaping_Service) -> bool {

    if service.base_pixel_size <= 0 || service.shape == nil ||
        service.glyph_extents == nil || len(service.glyph_workspace) == 0 {
        return false
    }
    for font in service.fonts {
        if font.effective_key == .Math_Regular || font.generation == 0 ||
            font.raster_ascent <= 0 {
            return false
        }
    }
    return true
}

// Shape every text and space inline in immutable semantic document order.
document_shape_all_inlines :: proc(
    builder: ^Document_Shaped_Builder,
    runtime: ^app_core.Dynview_System,
    service: Document_Prose_Shaping_Service) -> app_core.Bounded_Builder_Status {

    for item, inline_index in runtime^.content.document_inlines {
        if item.kind != .Text && item.kind != .Space {
            continue
        }
        status := document_shape_inline(
            builder, service, runtime^.content.document_text, item, inline_index)
        if status != .Ok {
            return status
        }
    }
    return .Ok
}

// Snapshot effective generations by cache key for final publication validation.
document_prose_generations :: proc(
    service: Document_Prose_Shaping_Service) -> [app_core.FONT_KEY_COUNT]u64 {

    result: [app_core.FONT_KEY_COUNT]u64
    for font in service.fonts {
        result[int(font.effective_key)] = font.generation
    }
    return result
}

// Build and atomically seal authoritative JuliaMono measurements for semantic prose.
rebuild_document_shaped_cache :: proc(
    runtime: ^app_core.Dynview_System,
    arena: ^app_core.Arena_Owner,
    service: Document_Prose_Shaping_Service) -> app_core.Bounded_Builder_Status {

    cache := &runtime^.compile_cache
    clear_document_shaped_records(cache)
    if len(runtime^.content.document_inlines) == 0 ||
        !document_prose_shaping_service_ready(service) {
        return .Ok
    }
    builder: Document_Shaped_Builder
    status := document_shaped_builder_init(
        &builder, app_core.arena_owner_allocator(arena))
    if status == .Ok {
        status = document_shape_all_inlines(&builder, runtime, service)
    }
    if status == .Ok {
        generations := document_prose_generations(service)
        status = document_shaped_builder_seal(&builder, cache,
            len(runtime^.content.document_inlines),
            len(runtime^.content.document_text), generations[:])
    }
    if status != .Ok {
        clear_document_shaped_records(cache)
    }
    return status
}