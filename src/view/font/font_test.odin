#+test
package font

import app_core "../../core"
import "../../taskpool"

import "core:mem"
import "core:os"
import "core:testing"
import "core:thread"
import vmem "core:mem/virtual"

Codepoint_Resolver_Test_Result :: struct {
    ascii : Font_Glyph_Resolve_Status,
    math : Font_Glyph_Resolve_Status,
    unsupported : Font_Glyph_Resolve_Status,
    capacity : Font_Glyph_Resolve_Status,
    pending_count : i32,
}

Math_Shaping_Task_Test_Result :: struct {
    capability: ^Font_Math_Shaping_Capability,
    generation: u64,
    workspace: [32]u8,
    glyphs: [8]Shaped_Glyph,
    glyph_count: int,
    shaped: bool,
    properties_ready: bool,
}

Font_Cancel_Test_State :: struct {
    query_count: int,
    cancel_at: int,
}

// Request cancellation at one deterministic preparation checkpoint.
font_test_cancel_at_checkpoint :: proc(user_data: rawptr) -> bool {
    state := cast(^Font_Cancel_Test_State)user_data
    state^.query_count += 1
    return state^.query_count >= state^.cancel_at
}

// Wait until a font-owner test requests cancellation through the live task token.
font_test_wait_for_cancellation :: proc(
    payload: rawptr,
    token: taskpool.Task_Cancellation_Token) -> taskpool.Task_Result {
    observed := cast(^bool)payload
    for !taskpool.task_cancellation_requested(token) {
        thread.yield()
    }
    observed^ = true
    return .Cancelled
}

// Configure one accepted stale page operation over caller-owned glyph storage.
font_test_configure_stale_page :: proc(
    cache: ^Font_Cache, handle: taskpool.Task_Handle,
    glyphs: []Font_Glyph_Record) {
    glyphs[17].state = .Queued
    glyphs[18].state = .Queued
    cache.entries[int(Font_Key.Bold)] = {
        generation = 5,
        requested_generation = 6,
        resident = true,
        state = .Requested,
        glyphs = glyphs,
        queued_demand_count = 1,
    }
    cache.preparation.state = .Queued
    cache.preparation.handle = handle
    cache.preparation.task = {
        kind = .Glyph_Page,
        key = .Bold,
        generation = 5,
        glyph_id_count = 2,
        demanded_glyph_count = 1,
    }
    cache.preparation.task.glyph_ids[0] = 17
    cache.preparation.task.glyph_ids[1] = 18
}

// Complete one pool slot without touching shared application state.
test_task_succeed :: proc(
    payload: rawptr, _: taskpool.Task_Cancellation_Token) -> taskpool.Task_Result {
    return .Succeeded
}

// Shape one fixed math run through worker-exclusive capability ownership.
test_math_shaping_task :: proc(
    payload: rawptr, _: taskpool.Task_Cancellation_Token) -> taskpool.Task_Result {
    result := cast(^Math_Shaping_Task_Test_Result)payload
    result^.glyph_count, result^.shaped = math_shaping_shape(
        result^.capability, result^.generation, {
            text = "x+1", role = .Italic, workspace = result^.workspace[:],
        }, result^.glyphs[:])
    result^.properties_ready = math_shaping_has_math_properties(
        result^.capability)
    return .Succeeded if result^.shaped else .Failed
}

// Submit and join one math shape through the production task-pool boundary.
view_run_math_shaping_task :: proc(
    t: ^testing.T, capability: ^Font_Math_Shaping_Capability,
    generation: u64) -> Math_Shaping_Task_Test_Result {

    pool: taskpool.Task_Pool
    testing.expect(t, taskpool.task_pool_init(&pool, 1, 1))
    defer taskpool.task_pool_destroy(&pool)
    task := Math_Shaping_Task_Test_Result{
        capability = capability,
        generation = generation,
    }
    handle, outcome := taskpool.task_pool_submit(
        &pool, test_math_shaping_task, &task)
    testing.expect_value(t, outcome, taskpool.Task_Submit_Outcome.Queued)
    result, joined := taskpool.task_pool_wait(&pool, handle)
    testing.expect_value(t, joined, taskpool.Task_Join_Outcome.Joined)
    testing.expect_value(t, result, taskpool.Task_Result.Succeeded)
    return task
}

// Verify approved extents and MATH queries for one shaped NewCM glyph.
view_expect_math_glyph_queries :: proc(
    t: ^testing.T, capability: ^Font_Math_Shaping_Capability,
    generation: u64, glyph_id: u32) {

    extents, extents_ok := math_shaping_glyph_extents(
        capability, generation, glyph_id)
    testing.expect(t, extents_ok && extents.width != 0 && extents.height != 0)
    _, italic_ok := math_shaping_italic_correction(
        capability, generation, glyph_id)
    _, accent_ok := math_shaping_top_accent_attachment(
        capability, generation, glyph_id)
    testing.expect(t, italic_ok && accent_ok)
}

// Verify direct resolver statuses and telemetry remain mutually consistent.
view_expect_codepoint_resolver_result :: proc(
    t: ^testing.T, entry: ^Font_Cache_Entry,
    result: Codepoint_Resolver_Test_Result) {

    testing.expect_value(t, result.ascii, Font_Glyph_Resolve_Status.Resident)
    testing.expect_value(t, result.math, Font_Glyph_Resolve_Status.Pending)
    testing.expect_value(
        t, result.unsupported, Font_Glyph_Resolve_Status.Unsupported)
    testing.expect_value(
        t, result.capacity, Font_Glyph_Resolve_Status.Capacity_Exhausted)
    testing.expect_value(t, result.pending_count, i32(1))
    testing.expect_value(t, entry.pending_glyph_count, result.pending_count)
    testing.expect_value(t, entry.pending_codepoint_count, u64(1))
    testing.expect_value(t, entry.unsupported_codepoint_count, u64(1))
    testing.expect_value(t, entry.capacity_rejection_count, u64(1))
}

// Verify the production compatibility seed is bounded and prepares independently.
@(test)
view_test_seed_codepoint_set :: proc(t: ^testing.T) {
    codepoints := seed_codepoint_set()
    testing.expect_value(t, codepoints.count, i32(96))
    testing.expect_value(t, codepoints.values[0], rune(0x0020))
    testing.expect_value(t, codepoints.values[94], rune(0x007e))
    testing.expect_value(t, codepoints.values[95], rune(0xfffd))

    prepared: Prepared_Font
    testing.expect(t, prepare({
        key = .Regular,
        path = "assets/JuliaMono-Regular.ttf",
        pixel_size = JULIA_MONO_FONT_SIZE,
        codepoints = codepoints.values[:codepoints.count],
    }, &prepared, context.allocator))
    testing.expect_value(t, prepared.glyph_count, i32(96))
    testing.expect(t, prepared.atlas_width <= 1024)
    testing.expect(t, prepared.atlas_height <= 1024)
    prepare_destroy(&prepared)
}

// Verify the required NewCM seed is bounded and the shipped face has MATH data.
@(test)
view_test_math_seed_and_table :: proc(t: ^testing.T) {
    codepoints := math_seed_codepoint_set()
    testing.expect(t, codepoints.count > 0)
    testing.expect(t, codepoints.count <= FONT_SEED_CODEPOINT_CAPACITY)
    testing.expect(t, codepoints.count <= len(Font_Prepare_Task{}.codepoints))
    testing.expect_value(t, codepoints.values[0], rune(0x0020))

    path := "assets/NewCMSansMath-Regular.otf"
    prepared: Prepared_Font
    testing.expect(t, prepare({
        key = .Math_Regular,
        path = path,
        pixel_size = JULIA_MONO_FONT_SIZE,
        codepoints = codepoints.values[:codepoints.count],
    }, &prepared, context.allocator))
    prepare_destroy(&prepared)

    source, read_error := os.read_entire_file(path, context.allocator)
    testing.expect(t, read_error == nil)
    defer delete(source)
    shaping: Font_Shaping_Resource
    testing.expect(t, harfbuzz_shaper_init(
        source, JULIA_MONO_FONT_SIZE, &shaping))
    testing.expect(t, harfbuzz_face_has_math_table(&shaping))
    harfbuzz_shaper_destroy(&shaping)
}

// Verify the semantic math key maps only to the packaged NewCM source and seed.
@(test)
view_test_math_required_source_policy :: proc(t: ^testing.T) {
    testing.expect_value(
        t, FONT_FILENAMES[int(Font_Key.Math_Regular)],
        "NewCMSansMath-Regular.otf")
    testing.expect_value(t, FONT_KEY_COUNT, int(Font_Key.Math_Regular) + 1)
    math_seed := required_seed_codepoints(.Math_Regular)
    text_seed := required_seed_codepoints(.Regular)
    testing.expect(t, math_seed.count > text_seed.count)
    testing.expect_value(t, math_seed.count, i32(417))
    testing.expect_value(t, text_seed.count, i32(96))
}

// Verify the shipped faces yield a measurable lowercase match scale in MATH constants.
@(test)
view_test_math_text_match_scale_is_measured :: proc(t: ^testing.T) {
    text_source, text_error := os.read_entire_file(
        "assets/JuliaMono-Regular.ttf", context.allocator)
    math_source, math_error := os.read_entire_file(
        "assets/NewCMSansMath-Regular.otf", context.allocator)
    testing.expect(t, text_error == nil && math_error == nil)
    defer delete(text_source)
    defer delete(math_source)

    text_shaping: Font_Shaping_Resource
    math_shaping: Font_Shaping_Resource
    testing.expect(t, harfbuzz_shaper_init(
        text_source, JULIA_MONO_FONT_SIZE, &text_shaping))
    defer harfbuzz_shaper_destroy(&text_shaping)
    testing.expect(t, harfbuzz_shaper_init(
        math_source, JULIA_MONO_FONT_SIZE, &math_shaping))
    defer harfbuzz_shaper_destroy(&math_shaping)

    text_height, text_ok := harfbuzz_lowercase_ink_height(&text_shaping)
    math_height, math_ok := harfbuzz_lowercase_ink_height(&math_shaping)
    testing.expect(t, text_ok && math_ok)
    testing.expect(t, text_height > 0 && math_height > 0)

    scale := harfbuzz_text_match_scale(&text_shaping, &math_shaping)
    testing.expect_value(t, scale, text_height / math_height)
    testing.expect(t, scale > 0.5 && scale < 2.0)

    constants: Font_Math_Constants
    testing.expect(t, harfbuzz_math_constants_capture(
        &math_shaping, 7, f32(JULIA_MONO_FONT_SIZE), &constants, scale))
    testing.expect_value(t, constants.text_match_scale, scale)

    empty: Font_Shaping_Resource
    testing.expect_value(t, harfbuzz_text_match_scale(&empty, &math_shaping), f32(1))
    testing.expect(t, !harfbuzz_math_constants_capture(
        &math_shaping, 7, f32(JULIA_MONO_FONT_SIZE), &constants, 0))
}

// Verify every scalar in one advertised mathematical alphabet resolves in NewCM.
view_expect_math_alphabet_coverage :: proc(
    t: ^testing.T,
    shaping: ^Font_Shaping_Resource,
    ranges: []Font_Codepoint_Range,
    exceptions: []rune) {

    for interval in ranges {
        for scalar := interval.first; scalar <= interval.last; scalar += 1 {
            glyph, found := harfbuzz_nominal_glyph(shaping, scalar)
            testing.expect(t, found && glyph != 0)
        }
    }
    for scalar in exceptions {
        glyph, found := harfbuzz_nominal_glyph(shaping, scalar)
        testing.expect(t, found && glyph != 0)
    }
}

// Verify every Stage 7 alphabet scalar is supplied by the authoritative math face.
@(test)
view_test_math_alphabet_coverage :: proc(t: ^testing.T) {
    source, read_error := os.read_entire_file(
        "assets/NewCMSansMath-Regular.otf", context.allocator)
    testing.expect(t, read_error == nil)
    defer delete(source)
    shaping: Font_Shaping_Resource
    testing.expect(t, harfbuzz_shaper_init(
        source, JULIA_MONO_FONT_SIZE, &shaping))
    defer harfbuzz_shaper_destroy(&shaping)

    ranges := [?]Font_Codepoint_Range{
        {0x1d400, 0x1d454}, {0x1d456, 0x1d467},
        {0x1d49c, 0x1d49c}, {0x1d49e, 0x1d49f}, {0x1d4a2, 0x1d4a2},
        {0x1d4a5, 0x1d4a6}, {0x1d4a9, 0x1d4ac}, {0x1d4ae, 0x1d4b5},
        {0x1d538, 0x1d539}, {0x1d53b, 0x1d53e}, {0x1d540, 0x1d544},
        {0x1d546, 0x1d546}, {0x1d54a, 0x1d550}, {0x1d552, 0x1d56b},
        {0x1d7ce, 0x1d7e1},
    }
    exceptions := [?]rune{
        0x2102, 0x210b, 0x210d, 0x210e, 0x2110, 0x2112, 0x2115,
        0x2119, 0x211a, 0x211b, 0x211d, 0x2124, 0x212c, 0x2130,
        0x2131, 0x2133,
    }
    view_expect_math_alphabet_coverage(t, &shaping, ranges[:], exceptions[:])
}

// Verify a face without OpenType MATH data cannot become the math generation.
@(test)
view_test_math_generation_rejects_missing_math_table :: proc(t: ^testing.T) {
    cache: Font_Cache
    resource: Font_Shaping_Resource
    testing.expect(t, !font_shaping_create(
        &cache, .Math_Regular, "assets/JuliaMono-Regular.ttf", &resource))
    testing.expect(t, resource.blob == nil)
    testing.expect(t, resource.face == nil)
    testing.expect(t, resource.font == nil)
    testing.expect(t, resource.buffer == nil)
    cache.preparation.state = .Idle
    cache_preparation_arena_destroy(&cache)
}

// Verify math generation metadata and native shaping ownership retire together.
@(test)
view_test_math_generation_teardown :: proc(t: ^testing.T) {
    source, read_error := os.read_entire_file(
        "assets/NewCMSansMath-Regular.otf", context.allocator)
    testing.expect(t, read_error == nil)
    defer delete(source)

    entry: Font_Cache_Entry
    entry.resident = true
    testing.expect(t, harfbuzz_shaper_init(
        source, JULIA_MONO_FONT_SIZE, &entry.shaping))
    testing.expect(t, font_generation_glyphs_init(
        &entry, 128, context.allocator))
    font_generation_destroy(&entry)

    testing.expect(t, entry.shaping.blob == nil)
    testing.expect(t, entry.shaping.face == nil)
    testing.expect(t, entry.shaping.font == nil)
    testing.expect(t, entry.shaping.buffer == nil)
    testing.expect_value(t, len(entry.glyphs), 0)
}

// Verify NewCM vertical variants are bounded, ordered, stable, and generation-safe.
view_expect_math_vertical_variants :: proc(
    t: ^testing.T, capability: ^Font_Math_Shaping_Capability) {

    sum_glyph, sum_ok := harfbuzz_nominal_glyph(&capability^.resource, '∑')
    variants: [app_core.FONT_MATH_GLYPH_VARIANT_CAPACITY]app_core.Font_Math_Glyph_Variant
    repeated: [app_core.FONT_MATH_GLYPH_VARIANT_CAPACITY]app_core.Font_Math_Glyph_Variant
    result := math_shaping_vertical_variants(capability, 7, sum_glyph, variants[:])
    repeated_result := math_shaping_vertical_variants(
        capability, 7, sum_glyph, repeated[:])
    stale_result := math_shaping_vertical_variants(
        capability, 6, sum_glyph, repeated[:])
    testing.expect(t, sum_ok && result.ok && repeated_result.ok)
    testing.expect(t, result.count > 0 && result.extended_shape)
    testing.expect_value(t, repeated_result.count, result.count)
    testing.expect(t, !stale_result.ok)
    for index in 0..<result.count {
        testing.expect(t, variants[index].glyph_id > 0 && variants[index].advance > 0)
        testing.expect_value(t, repeated[index], variants[index])
        if index > 0 {
            testing.expect(t, variants[index].advance >= variants[index-1].advance)
        }
    }
}

// Verify NewCM's surd assembly is bounded, connected, and generation-safe.
view_expect_math_vertical_assembly :: proc(
    t: ^testing.T, capability: ^Font_Math_Shaping_Capability) {

    surd_glyph, surd_ok := harfbuzz_nominal_glyph(&capability^.resource, '√')
    parts: [app_core.FONT_MATH_GLYPH_PART_CAPACITY]app_core.Font_Math_Glyph_Part
    result := math_shaping_vertical_assembly(capability, 7, surd_glyph, parts[:])
    stale := math_shaping_vertical_assembly(capability, 6, surd_glyph, parts[:])
    testing.expect(t, surd_ok && result.ok && !stale.ok)
    testing.expect(t, result.count > 0 && result.min_connector_overlap >= 0)
    has_extender := false
    for part in parts[:result.count] {
        testing.expect(t, part.glyph_id > 0 && part.full_advance > 0)
        testing.expect(t, part.start_connector_length <= part.full_advance)
        testing.expect(t, part.end_connector_length <= part.full_advance)
        has_extender = has_extender || part.extender
    }
    testing.expect(t, has_extender)
}

// Verify NewCM exposes circumflex variants and reports its absent assembly cleanly.
view_expect_math_horizontal_accent_variants :: proc(
    t: ^testing.T, capability: ^Font_Math_Shaping_Capability) {

    glyph, glyph_ok := harfbuzz_nominal_glyph(
        &capability^.resource, rune(0x0302))
    variants: [app_core.FONT_MATH_GLYPH_VARIANT_CAPACITY]app_core.Font_Math_Glyph_Variant
    variant_result := math_shaping_horizontal_variants(
        capability, 7, glyph, variants[:])
    parts: [app_core.FONT_MATH_GLYPH_PART_CAPACITY]app_core.Font_Math_Glyph_Part
    assembly_result := math_shaping_horizontal_assembly(
        capability, 7, glyph, parts[:])
    testing.expect(t, glyph_ok)
    testing.expect(t, variant_result.ok && variant_result.count > 0)
    testing.expect(t, !assembly_result.ok && assembly_result.count == 0)
}

// Verify standalone normal and flattened accents suppress dotted-circle insertion.
view_expect_math_standalone_accent_shape :: proc(
    t: ^testing.T, capability: ^Font_Math_Shaping_Capability) {

    workspace: [16]u8
    normal: [2]Shaped_Glyph
    normal_count, normal_ok := math_shaping_shape(capability, 7, {
        text = "̂", standalone_accent = true, workspace = workspace[:]}, normal[:])
    flattened: [2]Shaped_Glyph
    flattened_count, flattened_ok := math_shaping_shape(capability, 7, {
        text = "̂", standalone_accent = true, flattened_accent = true,
        workspace = workspace[:]}, flattened[:])
    testing.expect(t, normal_ok && flattened_ok)
    testing.expect_value(t, normal_count, 1)
    testing.expect_value(t, flattened_count, 1)
    testing.expect(t, normal[0].glyph_id > 0 && flattened[0].glyph_id > 0)
}

// Verify every MATH kern corner accepts signed heights and rejects stale generations.
view_expect_math_glyph_kerning :: proc(
    t: ^testing.T,
    capability: ^Font_Math_Shaping_Capability,
    glyph_id: u32) {

    corners := [4]Harfbuzz_Math_Kern{
        .Top_Right, .Top_Left, .Bottom_Right, .Bottom_Left}
    heights := [3]i32{-64, 0, 64}
    for corner in corners {
        for height in heights {
            value, ok := math_shaping_glyph_kerning(
                capability, 7, glyph_id, corner, height)
            repeated, repeated_ok := math_shaping_glyph_kerning(
                capability, 7, glyph_id, corner, height)
            testing.expect(t, ok && repeated_ok)
            testing.expect_value(t, repeated, value)
        }
    }
    _, stale_ok := math_shaping_glyph_kerning(
        capability, 6, glyph_id, .Top_Right, 0)
    testing.expect(t, !stale_ok)
}

// Verify bounded bulk tables reproduce direct queries at every native boundary.
view_expect_math_glyph_kern_tables :: proc(
    t: ^testing.T,
    capability: ^Font_Math_Shaping_Capability,
    glyph_id: u32) {

    corners := [4]Harfbuzz_Math_Kern{
        .Top_Right, .Top_Left, .Bottom_Right, .Bottom_Left}
    for corner in corners {
        entries: [app_core.FONT_MATH_KERN_ENTRY_CAPACITY]app_core.Font_Math_Kern_Entry
        result := math_shaping_glyph_kern_table(
            capability, 7, glyph_id, corner, entries[:])
        testing.expect(t, result.ok)
        for entry, index in entries[:result.count] {
            direct, direct_ok := math_shaping_glyph_kerning(
                capability, 7, glyph_id, corner, entry.max_correction_height)
            testing.expect(t, direct_ok)
            testing.expect_value(t, direct, entry.kern_value)
            if index+1 < result.count {
                next, next_ok := math_shaping_glyph_kerning(
                    capability, 7, glyph_id, corner,
                    entry.max_correction_height+1)
                testing.expect(t, next_ok)
                testing.expect_value(t, next, entries[index+1].kern_value)
            }
        }
    }
}

// Verify synchronized capability metadata and all supported MATH queries.
view_expect_math_shaping_capability :: proc(
    t: ^testing.T,
    capability: ^Font_Math_Shaping_Capability) {

    testing.expect_value(t, capability.generation, u64(7))
    testing.expect(t, capability.constants.valid)
    testing.expect_value(t, capability.constants.generation, u64(7))
    testing.expect_value(t, capability.constants.base_pixel_size,
        f32(JULIA_MONO_FONT_SIZE))
    testing.expect(t, capability.constants.values[int(
        Harfbuzz_Math_Constant.Script_Percent_Scale_Down)] > 0)
    testing.expect(t, capability.constants.values[int(
        Harfbuzz_Math_Constant.Script_Script_Percent_Scale_Down)] > 0)
    task := view_run_math_shaping_task(t, capability, 7)
    testing.expect(t, task.shaped && task.glyph_count == 3)
    italic_x, italic_x_ok := harfbuzz_nominal_glyph(
        &capability.resource, rune(0x1d465))
    testing.expect(t, italic_x_ok)
    testing.expect_value(t, task.glyphs[0].glyph_id, italic_x)
    testing.expect(t, task.properties_ready)
    view_expect_math_glyph_queries(t, capability, 7, task.glyphs[0].glyph_id)
    view_expect_math_glyph_kerning(t, capability, task.glyphs[0].glyph_id)
    view_expect_math_glyph_kern_tables(t, capability, task.glyphs[0].glyph_id)
    view_expect_math_vertical_variants(t, capability)
    view_expect_math_vertical_assembly(t, capability)
    view_expect_math_horizontal_accent_variants(t, capability)
    view_expect_math_standalone_accent_shape(t, capability)
}

// Verify worker math shaping is isolated, explicit, bounded, and query-capable.
@(test)
view_test_worker_math_shaping_capability :: proc(t: ^testing.T) {
    cache: Font_Cache
    entry := &cache.entries[int(Font_Key.Math_Regular)]
    entry.resident = true
    entry.generation = 7
    entry.requested_generation = 7
    source, read_error := os.read_entire_file(
        "assets/NewCMSansMath-Regular.otf", context.allocator)
    testing.expect(t, read_error == nil)
    defer delete(source)
    testing.expect(t, harfbuzz_shaper_init(
        source, JULIA_MONO_FONT_SIZE, &entry.shaping))

    capability: Font_Math_Shaping_Capability
    testing.expect(t, math_shaping_sync(&cache, &capability))
    testing.expect(t, capability.resource.buffer != entry.shaping.buffer)
    view_expect_math_shaping_capability(t, &capability)

    math_shaping_destroy(&capability)
    font_shaping_destroy(&entry.shaping)
}

// Verify missing glyphs, invalid queries, and stale generations fail as a unit.
@(test)
view_test_worker_math_shaping_rejects_invalid_requests :: proc(t: ^testing.T) {
    cache: Font_Cache
    entry := &cache.entries[int(Font_Key.Math_Regular)]
    entry.resident = true
    entry.generation = 3
    capability: Font_Math_Shaping_Capability
    testing.expect(t, math_shaping_sync(&cache, &capability))
    defer math_shaping_destroy(&capability)

    output: [4]Shaped_Glyph
    workspace: [16]u8
    _, stale_ok := math_shaping_shape(
        &capability, 2, {text = "x", role = .Italic, workspace = workspace[:]},
        output[:])
    _, missing_ok := math_shaping_shape(
        &capability, 3, {
            text = "\U0010ffff", role = .Upright, workspace = workspace[:],
        }, output[:])
    _, role_ok := math_shaping_shape(
        &capability, 3, {
            text = "x", role = Math_Shaping_Role(99), workspace = workspace[:],
        }, output[:])
    _, extents_ok := math_shaping_glyph_extents(
        &capability, 3, max(u32))
    testing.expect(t, !stale_ok && !missing_ok && !role_ok && !extents_ok)
}

// Verify role projection is bounded, strict, and leaves source bytes untouched.
@(test)
view_test_math_shaping_source_projection :: proc(t: ^testing.T) {
    source := "Ahx αω ∂ϵϑϰϕϱϖ 𝑥+1"
    expected := "𝐴ℎ𝑥 𝛼𝜔 𝜕𝜖𝜗𝜘𝜙𝜚𝜛 𝑥+1"
    workspace: [128]u8
    projected, projected_ok := math_shaping_project_source(
        source, .Italic, workspace[:])
    testing.expect(t, projected_ok)
    testing.expect_value(t, projected, expected)
    testing.expect_value(t, source, "Ahx αω ∂ϵϑϰϕϱϖ 𝑥+1")

    upright, upright_ok := math_shaping_project_source(
        "A1+Ω", .Upright, workspace[:])
    testing.expect(t, upright_ok)
    testing.expect_value(t, upright, "A1+Ω")

    invalid_role := Math_Shaping_Role(99)
    _, role_ok := math_shaping_project_source("x", invalid_role, workspace[:])
    _, capacity_ok := math_shaping_project_source("x", .Italic, workspace[:3])
    malformed_bytes := [?]u8{0xc0, 0x80}
    malformed := string(malformed_bytes[:])
    _, utf8_ok := math_shaping_project_source(malformed, .Italic, workspace[:])
    testing.expect(t, !role_ok && !capacity_ok && !utf8_ok)
}

// Verify failed generation synchronization preserves the prior worker capability.
@(test)
view_test_worker_math_shaping_failed_sync_preserves_previous :: proc(t: ^testing.T) {
    cache: Font_Cache
    entry := &cache.entries[int(Font_Key.Math_Regular)]
    entry.resident = true
    entry.generation = 1
    capability: Font_Math_Shaping_Capability
    testing.expect(t, math_shaping_sync(&cache, &capability))
    previous_buffer := capability.resource.buffer

    entry.generation = 2
    invalid_path := "assets/JuliaMono-Regular.ttf"
    source_path := &cache.source_paths[int(Font_Key.Math_Regular)]
    copy(source_path.storage[:], transmute([]u8)invalid_path)
    source_path.length = len(invalid_path)
    testing.expect(t, !math_shaping_sync(&cache, &capability))
    testing.expect_value(t, capability.generation, u64(1))
    testing.expect_value(t, capability.failed_generation, u64(2))
    testing.expect(t, capability.resource.buffer == previous_buffer)
    testing.expect(t, !math_shaping_sync(&cache, &capability))
    testing.expect(t, capability.resource.buffer == previous_buffer)
    math_shaping_destroy(&capability)
}

// Verify every existing dynview weight and italic combination maps to its cache key.
@(test)
view_test_font_flags_map_to_cache_keys :: proc(t: ^testing.T) {
    cases := [?]struct {
        flags: app_core.Font_Variant_Flags,
        key: Font_Key,
    }{
        {.Regular, .Regular},
        {.Light, .Light},
        {.Medium, .Medium},
        {.Semibold, .Semi_Bold},
        {.Bold, .Bold},
        {.Extrabold, .Extra_Bold},
        {.Black, .Black},
    }
    for test_case in cases {
        testing.expect_value(t, font_key_from_flags(test_case.flags), test_case.key)
        italic_flags := app_core.Font_Variant_Flags(
            u32(test_case.flags) | u32(app_core.Font_Variant_Flags.Italic))
        testing.expect_value(t, int(font_key_from_flags(italic_flags)),
            int(test_case.key) + 1)
    }
}

// Verify CPU preparation reproduces the production Regular seed contract.
@(test)
view_test_prepare_regular :: proc(t: ^testing.T) {
    codepoint_set := seed_codepoint_set()
    codepoints := codepoint_set.values[:codepoint_set.count]
    prepared: Prepared_Font
    success := prepare({
        key = .Regular,
        generation = 7,
        path = "assets/JuliaMono-Regular.ttf",
        pixel_size = JULIA_MONO_FONT_SIZE,
        codepoints = codepoints,
    }, &prepared, context.allocator)

    testing.expect(t, success)
    testing.expect_value(t, prepared.key, Font_Key.Regular)
    testing.expect_value(t, prepared.generation, u64(7))
    testing.expect_value(t, prepared.base_size, i32(32))
    testing.expect_value(t, prepared.glyph_count, i32(96))
    testing.expect_value(t, prepared.padding, i32(4))
    testing.expect(t, prepared.atlas_width <= 1024)
    testing.expect(t, prepared.atlas_height <= 1024)
    testing.expect_value(t, len(prepared.glyphs), 96)
    testing.expect_value(t, len(prepared.rectangles), 96)
    testing.expect_value(t, prepared.glyphs[0].value, rune(' '))
    testing.expect(t, prepared.glyphs[0].glyph_id > 0)
    testing.expect_value(t, prepared.glyphs[0].advance_x, i32(16))
    testing.expect_value(t, prepared.glyphs[0].bitmap_width, i32(16))
    testing.expect_value(t, prepared.glyphs[0].bitmap_height, i32(32))

    prepare_destroy(&prepared)
    testing.expect_value(t, prepared.glyph_count, i32(0))
    testing.expect_value(t, len(prepared.atlas_pixels), 0)
}

// Verify complete preparation includes every Regular face glyph in ID order.
@(test)
view_test_prepare_complete_regular :: proc(t: ^testing.T) {
    codepoints := seed_codepoint_set()
    prepared: Prepared_Font
    success := prepare({
        key = .Regular,
        generation = 9,
        path = "assets/JuliaMono-Regular.ttf",
        pixel_size = JULIA_MONO_FONT_SIZE,
        codepoints = codepoints.values[:codepoints.count],
        complete_face = true,
    }, &prepared, context.allocator)

    testing.expect(t, success)
    testing.expect(t, prepared.glyph_count > 0)
    testing.expect_value(t, prepared.glyphs[0].glyph_id, u32(0))
    last_index := len(prepared.glyphs) - 1
    testing.expect_value(t, prepared.glyphs[last_index].glyph_id, u32(last_index))
    testing.expect(t, prepared.atlas_width > 0)
    testing.expect(t, prepared.atlas_height > 0)

    prepare_destroy(&prepared)
}

// Verify cancellation before source I/O leaves no partial prepared-font ownership.
@(test)
view_test_prepare_cancels_before_open :: proc(t: ^testing.T) {
    state := Font_Cancel_Test_State{cancel_at = 1}
    prepared: Prepared_Font
    success := prepare({
        path = "assets/JuliaMono-Regular.ttf",
        pixel_size = JULIA_MONO_FONT_SIZE,
        codepoints = []rune{'A'},
        cancellation = {
            user_data = &state,
            requested = font_test_cancel_at_checkpoint,
        },
    }, &prepared, context.allocator)

    testing.expect(t, !success)
    testing.expect_value(t, state.query_count, 1)
    testing.expect_value(t, prepared.glyph_count, i32(0))
    testing.expect_value(t, len(prepared.glyphs), 0)
    testing.expect_value(t, len(prepared.atlas_pixels), 0)
}

// Verify full-face cancellation rolls back metadata allocated before rasterization.
@(test)
view_test_prepare_complete_cancellation_clears_result :: proc(t: ^testing.T) {
    codepoints := seed_codepoint_set()
    state := Font_Cancel_Test_State{cancel_at = 8}
    prepared: Prepared_Font
    success := prepare({
        path = "assets/JuliaMono-Regular.ttf",
        pixel_size = JULIA_MONO_FONT_SIZE,
        codepoints = codepoints.values[:codepoints.count],
        complete_face = true,
        cancellation = {
            user_data = &state,
            requested = font_test_cancel_at_checkpoint,
        },
    }, &prepared, context.allocator)

    testing.expect(t, !success)
    testing.expect(t, state.query_count >= state.cancel_at)
    testing.expect_value(t, prepared.glyph_count, i32(0))
    testing.expect_value(t, len(prepared.glyphs), 0)
    testing.expect_value(t, len(prepared.atlas_pixels), 0)
}

// Verify bounded subset preparation preserves face glyph IDs and deterministic packing.
@(test)
view_test_prepare_glyph_page :: proc(t: ^testing.T) {
    glyph_ids := [3]u32{0, 17, 4000}
    request := Font_Glyph_Page_Request{
        key = .Regular,
        generation = 11,
        path = "assets/JuliaMono-Regular.ttf",
        pixel_size = JULIA_MONO_FONT_SIZE,
        glyph_ids = glyph_ids[:],
    }
    first, second: Prepared_Font
    testing.expect(t, prepare_glyph_page(request, &first, context.allocator))
    testing.expect(t, prepare_glyph_page(request, &second, context.allocator))
    testing.expect_value(t, first.glyph_count, i32(len(glyph_ids)))
    testing.expect_value(t, first.atlas_width, second.atlas_width)
    testing.expect_value(t, first.atlas_height, second.atlas_height)
    for glyph, index in first.glyphs {
        testing.expect_value(t, glyph.glyph_id, glyph_ids[index])
        testing.expect_value(t, first.rectangles[index], second.rectangles[index])
    }
    prepare_destroy(&first)
    prepare_destroy(&second)
}

// Verify glyph-page cancellation clears partial compact-page ownership.
@(test)
view_test_prepare_glyph_page_cancellation_clears_result :: proc(t: ^testing.T) {
    glyph_ids := [3]u32{0, 17, 4000}
    state := Font_Cancel_Test_State{cancel_at = 5}
    prepared: Prepared_Font
    success := prepare_glyph_page({
        path = "assets/JuliaMono-Regular.ttf",
        pixel_size = JULIA_MONO_FONT_SIZE,
        glyph_ids = glyph_ids[:],
        cancellation = {
            user_data = &state,
            requested = font_test_cancel_at_checkpoint,
        },
    }, &prepared, context.allocator)

    testing.expect(t, !success)
    testing.expect(t, state.query_count >= state.cancel_at)
    testing.expect_value(t, prepared.glyph_count, i32(0))
    testing.expect_value(t, len(prepared.glyphs), 0)
    testing.expect_value(t, len(prepared.atlas_pixels), 0)
}

// Verify page preparation rejects duplicate and out-of-range face glyph IDs.
@(test)
view_test_prepare_glyph_page_rejects_invalid_ids :: proc(t: ^testing.T) {
    duplicate_ids := [2]u32{17, 17}
    out_of_range_ids := [1]u32{65535}
    prepared: Prepared_Font
    request := Font_Glyph_Page_Request{
        path = "assets/JuliaMono-Regular.ttf",
        pixel_size = JULIA_MONO_FONT_SIZE,
        glyph_ids = duplicate_ids[:],
    }
    testing.expect(t, !prepare_glyph_page(request, &prepared, context.allocator))
    testing.expect_value(t, len(prepared.glyphs), 0)
    request.glyph_ids = out_of_range_ids[:]
    testing.expect(t, !prepare_glyph_page(request, &prepared, context.allocator))
    testing.expect_value(t, len(prepared.glyphs), 0)
}

// Verify generation glyph metadata is exact-size, deduplicated, and reclaimed whole.
@(test)
view_test_font_generation_glyph_demand_lifecycle :: proc(t: ^testing.T) {
    entry: Font_Cache_Entry
    testing.expect(t, font_generation_glyphs_init(
        &entry, 6795, context.allocator))
    testing.expect_value(t, len(entry.glyphs), 6795)
    testing.expect(t, font_generation_request_glyph(&entry, 4000))
    testing.expect(t, !font_generation_request_glyph(&entry, 4000))
    testing.expect(t, !font_generation_request_glyph(&entry, 6795))
    testing.expect_value(t, entry.pending_glyph_count, i32(1))
    testing.expect_value(t, entry.glyphs[4000].state, Font_Glyph_State.Pending)

    font_generation_glyphs_destroy(&entry)
    testing.expect_value(t, len(entry.glyphs), 0)
    testing.expect_value(t, entry.pending_glyph_count, i32(0))
    font_generation_glyphs_destroy(&entry)
}

// Verify glyph resolution records one missing face glyph without duplicate demand.
@(test)
view_test_glyph_resolver_records_missing_demand :: proc(t: ^testing.T) {
    cache: Font_Cache
    entry := &cache.entries[int(Font_Key.Regular)]
    entry.resident = true
    entry.state = .Ready
    entry.generation = 1
    entry.requested_generation = 1
    testing.expect(t, font_generation_glyphs_init(
        entry, 32, context.allocator))

    _, first_resident := cache_terminal_resolve_glyph(
        &cache, .Regular, 17)
    _, second_resident := cache_terminal_resolve_glyph(
        &cache, .Regular, 17)
    testing.expect(t, !first_resident && !second_resident)
    testing.expect_value(t, entry.pending_glyph_count, i32(1))
    testing.expect_value(t, entry.glyphs[17].state, Font_Glyph_State.Pending)
    font_generation_glyphs_destroy(entry)
}

// Verify one page task takes a deterministic bounded batch and marks it queued.
@(test)
view_test_page_task_batches_pending_glyphs :: proc(t: ^testing.T) {
    cache: Font_Cache
    entry := &cache.entries[int(Font_Key.Regular)]
    entry.resident = true
    entry.state = .Ready
    entry.generation = 3
    entry.requested_generation = 3
    testing.expect(t, font_generation_glyphs_init(
        entry, 300, context.allocator))
    for glyph_id in 0..<300 {
        testing.expect(t, font_generation_request_glyph(entry, u32(glyph_id)))
    }
    testing.expect(t, cache_preparation_arena_init(&cache))
    task: Font_Prepare_Task
    testing.expect(t, cache_prepare_page_task(&cache, .Regular, &task))
    testing.expect_value(
        t, task.glyph_id_count, i32(FONT_GLYPH_PAGE_REQUEST_CAPACITY))
    testing.expect_value(
        t, task.demanded_glyph_count, i32(FONT_GLYPH_PAGE_REQUEST_CAPACITY))
    testing.expect_value(t, task.glyph_ids[0], u32(0))
    testing.expect_value(t, task.glyph_ids[255], u32(255))
    testing.expect_value(t, entry.glyphs[255].state, Font_Glyph_State.Queued)
    testing.expect_value(t, entry.glyphs[256].state, Font_Glyph_State.Pending)
    testing.expect_value(t, entry.queued_demand_count, i32(256))

    cache.preparation.task = task
    cache_fail_preparation(&cache)
    testing.expect_value(t, entry.glyphs[0].state, Font_Glyph_State.Pending)
    testing.expect_value(t, entry.queued_demand_count, i32(0))
    cache.preparation.state = .Idle
    cache_preparation_arena_destroy(&cache)
    font_generation_glyphs_destroy(entry)
}

// Verify one sparse demand fills the remaining page with deterministic glyph IDs.
@(test)
view_test_page_task_fills_sparse_demand :: proc(t: ^testing.T) {
    cache: Font_Cache
    entry := &cache.entries[int(Font_Key.Regular)]
    entry.resident = true
    entry.state = .Ready
    entry.generation = 3
    entry.requested_generation = 3
    testing.expect(t, font_generation_glyphs_init(
        entry, 300, context.allocator))
    testing.expect(t, font_generation_request_glyph(entry, 17))
    testing.expect(t, cache_preparation_arena_init(&cache))
    task: Font_Prepare_Task
    testing.expect(t, cache_prepare_page_task(&cache, .Regular, &task))
    testing.expect_value(t, task.demanded_glyph_count, i32(1))
    testing.expect_value(t, task.glyph_id_count, i32(256))
    testing.expect_value(t, task.glyph_ids[0], u32(17))
    testing.expect_value(t, task.glyph_ids[1], u32(0))
    testing.expect_value(t, task.glyph_ids[18], u32(18))

    cache.preparation.task = task
    cache_restore_page_demand(&cache)
    testing.expect_value(t, entry.glyphs[17].state, Font_Glyph_State.Pending)
    testing.expect_value(t, entry.glyphs[0].state, Font_Glyph_State.Missing)
    testing.expect_value(t, entry.pending_glyph_count, i32(1))
    cache.preparation.state = .Idle
    cache_preparation_arena_destroy(&cache)
    font_generation_glyphs_destroy(entry)
}

// Verify a full page table rejects demand without leaving unschedulable work.
@(test)
view_test_page_capacity_blocks_scheduling :: proc(t: ^testing.T) {
    cache: Font_Cache
    entry := &cache.entries[int(Font_Key.Regular)]
    entry.resident = true
    entry.state = .Ready
    entry.generation = 1
    entry.requested_generation = 1
    entry.page_count = app_core.FONT_GLYPH_PAGE_CAPACITY
    testing.expect(t, font_generation_glyphs_init(
        entry, 2, context.allocator))
    testing.expect(t, !font_generation_request_glyph(entry, 1))
    testing.expect_value(
        t, entry.glyphs[1].state, Font_Glyph_State.Capacity_Blocked)
    testing.expect_value(t, entry.pending_glyph_count, i32(0))
    _, found := cache_next_page_key(&cache)
    testing.expect(t, !found)
    font_generation_glyphs_destroy(entry)
}

// Verify a queued final page reserves capacity against newly arriving demand.
@(test)
view_test_final_queued_page_blocks_new_demand :: proc(t: ^testing.T) {
    entry: Font_Cache_Entry
    entry.page_count = app_core.FONT_GLYPH_PAGE_CAPACITY - 1
    entry.pending_glyph_count = 1
    entry.queued_demand_count = 1
    testing.expect(t, font_generation_glyphs_init(
        &entry, 4, context.allocator))
    entry.glyphs[0].state = .Queued

    testing.expect(t, !font_generation_request_glyph(&entry, 1))
    testing.expect_value(
        t, entry.glyphs[1].state, Font_Glyph_State.Capacity_Blocked)
    testing.expect_value(t, entry.pending_glyph_count, i32(1))
    font_generation_glyphs_destroy(&entry)
}

// Verify superseded page work remains requestable while its old generation survives.
@(test)
view_test_stale_page_restores_old_generation_demand :: proc(t: ^testing.T) {
    cache: Font_Cache
    entry := &cache.entries[int(Font_Key.Regular)]
    entry.generation = 4
    entry.requested_generation = 5
    testing.expect(t, font_generation_glyphs_init(
        entry, 32, context.allocator))
    testing.expect(t, font_generation_request_glyph(entry, 17))
    entry.glyphs[17].state = .Queued
    cache.preparation.task = {
        kind = .Glyph_Page,
        key = .Regular,
        generation = 4,
        glyph_id_count = 1,
        demanded_glyph_count = 1,
    }
    cache.preparation.task.glyph_ids[0] = 17

    cache_restore_page_demand(&cache)
    testing.expect_value(t, entry.glyphs[17].state, Font_Glyph_State.Pending)
    testing.expect_value(t, entry.pending_glyph_count, i32(1))
    font_generation_glyphs_destroy(entry)
}

// Verify contextual alternates are repeatable and differ from disabled shaping.
@(test)
view_test_harfbuzz_contextual_alternates :: proc(t: ^testing.T) {
    source, read_error := os.read_entire_file(
        "assets/JuliaMono-Regular.ttf", context.allocator)
    testing.expect(t, read_error == nil)
    defer delete(source)

    shaping: Font_Shaping_Resource
    testing.expect(t, harfbuzz_shaper_init(
        source, JULIA_MONO_FONT_SIZE, &shaping))
    defer harfbuzz_shaper_destroy(&shaping)

    enabled, repeated, disabled: [8]Shaped_Glyph
    enabled_count, enabled_ok := harfbuzz_shape(
        &shaping, "=>", true, enabled[:])
    repeated_count, repeated_ok := harfbuzz_shape(
        &shaping, "=>", true, repeated[:])
    disabled_count, disabled_ok := harfbuzz_shape(
        &shaping, "=>", false, disabled[:])

    testing.expect(t, enabled_ok && repeated_ok && disabled_ok)
    testing.expect_value(t, enabled_count, repeated_count)
    testing.expect_value(t, enabled_count, disabled_count)
    differs := false
    for index in 0..<enabled_count {
        testing.expect_value(t, enabled[index], repeated[index])
        differs = differs || enabled[index].glyph_id != disabled[index].glyph_id
    }
    testing.expect(t, differs)
}

// Verify the resident HarfBuzz cmap defines Unicode support without a range policy.
@(test)
view_test_harfbuzz_nominal_glyph :: proc(t: ^testing.T) {
    source, read_error := os.read_entire_file(
        "assets/JuliaMono-Regular.ttf", context.allocator)
    testing.expect(t, read_error == nil)
    defer delete(source)

    shaping: Font_Shaping_Resource
    testing.expect(t, harfbuzz_shaper_init(
        source, JULIA_MONO_FONT_SIZE, &shaping))
    defer harfbuzz_shaper_destroy(&shaping)

    ascii_glyph, ascii_found := harfbuzz_nominal_glyph(&shaping, 'A')
    math_glyph, math_found := harfbuzz_nominal_glyph(&shaping, '∫')
    _, unsupported_found := harfbuzz_nominal_glyph(&shaping, rune(0x10ffff))
    _, surrogate_found := harfbuzz_nominal_glyph(&shaping, rune(0xd800))
    testing.expect(t, ascii_found && ascii_glyph > 0)
    testing.expect(t, math_found && math_glyph > 0)
    testing.expect(t, !unsupported_found)
    testing.expect(t, !surrogate_found)
}

// Verify direct codepoint resolution reports residency, demand, and hard bounds.
@(test)
view_test_codepoint_resolver_status :: proc(t: ^testing.T) {
    source, read_error := os.read_entire_file(
        "assets/JuliaMono-Regular.ttf", context.allocator)
    testing.expect(t, read_error == nil)
    defer delete(source)

    cache: Font_Cache
    entry := &cache.entries[int(Font_Key.Regular)]
    entry.resident = true
    entry.state = .Ready
    entry.generation = 1
    entry.requested_generation = 1
    testing.expect(t, harfbuzz_shaper_init(
        source, JULIA_MONO_FONT_SIZE, &entry.shaping))
    testing.expect(t, font_generation_glyphs_init(
        entry, 10000, context.allocator))

    ascii_id, _ := harfbuzz_nominal_glyph(&entry.shaping, 'A')
    entry.glyphs[ascii_id].state = .Resident
    _, ascii_status := cache_terminal_resolve_codepoint(
        &cache, .Regular, 'A')
    _, math_status := cache_terminal_resolve_codepoint(
        &cache, .Regular, '∫')
    pending_count := entry.pending_glyph_count
    _, unsupported_status := cache_terminal_resolve_codepoint(
        &cache, .Regular, rune(0x10ffff))
    entry.page_count = app_core.FONT_GLYPH_PAGE_CAPACITY
    _, capacity_status := cache_terminal_resolve_codepoint(
        &cache, .Regular, 'α')

    view_expect_codepoint_resolver_result(t, entry, {
        ascii = ascii_status,
        math = math_status,
        unsupported = unsupported_status,
        capacity = capacity_status,
        pending_count = pending_count,
    })

    harfbuzz_shaper_destroy(&entry.shaping)
    font_generation_glyphs_destroy(entry)
}

// Verify native source ownership survives arena release and output remains bounded.
@(test)
view_test_harfbuzz_owns_source_and_bounds_output :: proc(t: ^testing.T) {
    arena: vmem.Arena
    arena_error := vmem.arena_init_static(
        &arena, 16*mem.Megabyte, mem.Megabyte)
    testing.expect(t, arena_error == nil)
    source, read_error := os.read_entire_file(
        "assets/JuliaMono-Regular.ttf", vmem.arena_allocator(&arena))
    testing.expect(t, read_error == nil)

    shaping: Font_Shaping_Resource
    testing.expect(t, harfbuzz_shaper_init(
        source, JULIA_MONO_FONT_SIZE, &shaping))
    vmem.arena_destroy(&arena)

    output: [8]Shaped_Glyph
    glyph_count, shaped := harfbuzz_shape(
        &shaping, "=>", true, output[:])
    testing.expect(t, shaped)
    testing.expect(t, glyph_count > 0)

    bounded: [1]Shaped_Glyph
    _, bounded_ok := harfbuzz_shape(
        &shaping, "abcdef", true, bounded[:])
    testing.expect(t, !bounded_ok)

    harfbuzz_shaper_destroy(&shaping)
    harfbuzz_shaper_destroy(&shaping)
    testing.expect(t, shaping.font == nil)
    testing.expect(t, shaping.buffer == nil)
}

// Verify the cache reuses committed preparation pages until explicit destruction.
@(test)
view_test_preparation_arena_reuses_committed_pages :: proc(t: ^testing.T) {
    cache: Font_Cache
    testing.expect(t, cache_preparation_arena_init(&cache))
    allocator := vmem.arena_allocator(&cache.preparation_arena)
    first, first_error := make([]u8, 2*mem.Megabyte, allocator)
    testing.expect(t, first_error == nil)
    first_pointer := raw_data(first)
    committed := cache.preparation_arena.curr_block.committed
    testing.expect(t, committed >= 2*mem.Megabyte)

    cache_preparation_arena_reset(&cache)
    testing.expect_value(t, cache.preparation_arena.total_used, uint(0))
    testing.expect_value(
        t, cache.preparation_arena.curr_block.committed, committed)
    second, second_error := make([]u8, 2*mem.Megabyte, allocator)
    testing.expect(t, second_error == nil)
    testing.expect(t, raw_data(second) == first_pointer)

    cache.preparation.state = .Idle
    cache_preparation_arena_destroy(&cache)
    testing.expect(t, !cache.preparation_arena_initialized)
    testing.expect(t, cache.preparation_arena.curr_block == nil)
}

// Verify arena-owned prepared slices remain allocated until the cache resets them.
@(test)
view_test_prepared_font_uses_bulk_arena_release :: proc(t: ^testing.T) {
    cache: Font_Cache
    testing.expect(t, cache_preparation_arena_init(&cache))
    allocator := vmem.arena_allocator(&cache.preparation_arena)
    codepoints := [1]rune{'A'}
    prepared: Prepared_Font
    testing.expect(t, prepare({
        key = .Bold,
        generation = 1,
        path = "assets/JuliaMono-Bold.ttf",
        pixel_size = JULIA_MONO_FONT_SIZE,
        codepoints = codepoints[:],
    }, &prepared, allocator, .Arena))
    used := cache.preparation_arena.total_used
    testing.expect(t, used > 0)

    prepare_destroy(&prepared)
    testing.expect_value(t, cache.preparation_arena.total_used, used)
    cache_preparation_arena_reset(&cache)
    testing.expect_value(t, cache.preparation_arena.total_used, uint(0))

    cache.preparation.state = .Idle
    cache_preparation_arena_destroy(&cache)
}

// Verify incomplete prepared results are rejected before display finalization.
@(test)
view_test_prepared_validation :: proc(t: ^testing.T) {
    prepared := Prepared_Font{
        base_size = 64,
        glyph_count = 1,
        atlas_width = 8,
        atlas_height = 8,
    }
    testing.expect(t, !prepared_is_valid(&prepared))

    glyphs: [1]Prepared_Glyph
    rectangles: [1]Prepared_Rectangle
    atlas_pixels: [8*8*2]u8
    prepared.glyphs = glyphs[:]
    prepared.rectangles = rectangles[:]
    prepared.atlas_pixels = atlas_pixels[:]
    testing.expect(t, prepared_is_valid(&prepared))
}

// Verify stale generations preserve the active font and prepared ownership.
@(test)
view_test_cache_rejects_stale_publication :: proc(t: ^testing.T) {
    cache: Font_Cache
    cache.entries[int(Font_Key.Bold)] = {
        font = {baseSize = 55},
        generation = 5,
        requested_generation = 5,
        resident = true,
    }
    prepared := Prepared_Font{
        key = .Bold,
        generation = 4,
        glyph_count = 1,
    }

    testing.expect(t, !cache_publish(&cache, &prepared))
    testing.expect_value(t, cache.entries[int(Font_Key.Bold)].font.baseSize, 55)
    testing.expect_value(t, cache.entries[int(Font_Key.Bold)].generation, u64(5))
    testing.expect_value(t, prepared.glyph_count, i32(1))
}

// Verify a rapid replacement supersedes active work before GPU finalization.
@(test)
view_test_cache_reload_supersedes_active_generation :: proc(t: ^testing.T) {
    cache: Font_Cache
    cache.entries[int(Font_Key.Bold)] = {
        font = {baseSize = 55},
        generation = 5,
        requested_generation = 5,
        resident = true,
        state = .Ready,
    }
    testing.expect(t, cache_reload(&cache, .Bold))
    testing.expect_value(t, cache.preparation.task.generation, u64(6))
    testing.expect(t, cache_reload(&cache, .Bold))
    testing.expect_value(
        t, cache.entries[int(Font_Key.Bold)].requested_generation, u64(7))

    prepared := Prepared_Font{key = .Bold, generation = 6, glyph_count = 1}
    testing.expect(t, !cache_publish(&cache, &prepared))
    testing.expect_value(t, prepared.glyph_count, i32(1))
    testing.expect_value(t, cache.entries[int(Font_Key.Bold)].font.baseSize, 55)
    testing.expect_value(t, cache.entries[int(Font_Key.Bold)].generation, u64(5))
}

// Verify a matching reload failure leaves the previous resident generation drawable.
@(test)
view_test_cache_reload_failure_preserves_resident :: proc(t: ^testing.T) {
    cache: Font_Cache
    cache.entries[int(Font_Key.Regular)] = {
        font = {baseSize = 64},
        generation = 3,
        requested_generation = 3,
        resident = true,
        state = .Ready,
    }
    testing.expect(t, cache_reload(&cache, .Regular))
    cache_fail_preparation(&cache)

    entry := cache.entries[int(Font_Key.Regular)]
    testing.expect_value(t, entry.state, Font_Load_State.Failed)
    testing.expect(t, entry.resident)
    testing.expect_value(t, entry.generation, u64(3))
    testing.expect_value(t, entry.font.baseSize, i32(64))
}

// Verify a failed required-math replacement preserves its resident generation.
@(test)
view_test_math_reload_failure_preserves_resident :: proc(t: ^testing.T) {
    cache: Font_Cache
    cache.entries[int(Font_Key.Math_Regular)] = {
        font = {baseSize = 32},
        generation = 4,
        requested_generation = 4,
        resident = true,
        state = .Ready,
    }
    testing.expect(t, cache_reload(&cache, .Math_Regular))
    cache_fail_preparation(&cache)

    entry := cache.entries[int(Font_Key.Math_Regular)]
    testing.expect_value(t, entry.state, Font_Load_State.Failed)
    testing.expect(t, entry.resident)
    testing.expect_value(t, entry.generation, u64(4))
    testing.expect_value(t, entry.font.baseSize, i32(32))
}

// Verify cached drawing accepts only the exact resident math generation.
@(test)
view_test_math_cached_drawing_rejects_stale_generation :: proc(t: ^testing.T) {
    cache: Font_Cache
    cache.entries[int(Font_Key.Math_Regular)] = {
        generation = 4,
        resident = true,
    }

    testing.expect(t, cache_generation_is_resident(&cache, .Math_Regular, 4))
    testing.expect(t, !cache_generation_is_resident(&cache, .Math_Regular, 3))
    testing.expect(t, !cache_generation_is_resident(&cache, .Regular, 4))
}

// Verify rapid source edits collapse into one newest replacement generation.
@(test)
view_test_source_monitor_debounces_rapid_changes :: proc(t: ^testing.T) {
    cache: Font_Cache
    key := Font_Key.Bold
    cache.entries[int(key)] = {
        font = {baseSize = 55},
        generation = 2,
        requested_generation = 2,
        resident = true,
        state = .Ready,
    }
    cache.source_monitor.initialized = true
    cache.source_monitor.entries[int(key)].observed = {
        modification_ns = 10, size = 100, present = true,
    }

    source_monitor_observe(
        &cache, key, {modification_ns = 20, size = 110, present = true}, 100)
    source_monitor_observe(
        &cache, key, {modification_ns = 30, size = 120, present = true}, 200)
    source_monitor_commit(&cache, 200 + FONT_SOURCE_DEBOUNCE_NS - 1)
    testing.expect_value(
        t, cache.entries[int(key)].requested_generation, u64(2))

    source_monitor_commit(&cache, 200 + FONT_SOURCE_DEBOUNCE_NS)
    testing.expect_value(
        t, cache.entries[int(key)].requested_generation, u64(3))
    testing.expect_value(t, cache.preparation.task.generation, u64(3))
    testing.expect_value(t, cache.source_monitor.change_count, u64(1))
    testing.expect_value(t, cache.source_monitor.reload_count, u64(1))
    testing.expect_value(
        t, cache.source_monitor.entries[int(key)].observed.modification_ns,
        i64(30))
}

// Verify changes to unused optional sources do not create demand.
@(test)
view_test_source_monitor_ignores_unused_variant :: proc(t: ^testing.T) {
    cache: Font_Cache
    key := Font_Key.Black_Italic
    cache.source_monitor.entries[int(key)].observed = {
        modification_ns = 10, present = true,
    }
    source_monitor_observe(
        &cache, key, {modification_ns = 20, present = true}, 100)
    source_monitor_commit(&cache, 100 + FONT_SOURCE_DEBOUNCE_NS)

    testing.expect_value(
        t, cache.entries[int(key)].state, Font_Load_State.Unrequested)
    testing.expect_value(t, cache.source_monitor.change_count, u64(1))
    testing.expect_value(t, cache.source_monitor.reload_count, u64(0))
}

// Verify the service joins and discards stale successful work without publication.
@(test)
view_test_cache_service_discards_stale_completion :: proc(t: ^testing.T) {
    pool: taskpool.Task_Pool
    testing.expect(t, taskpool.task_pool_init(&pool, 1, 1))
    defer taskpool.task_pool_destroy(&pool)
    handle, outcome := taskpool.task_pool_submit(
        &pool, test_task_succeed, nil)
    testing.expect_value(t, outcome, taskpool.Task_Submit_Outcome.Queued)

    cache: Font_Cache
    cache.entries[int(Font_Key.Bold)] = {
        font = {baseSize = 55},
        generation = 4,
        requested_generation = 6,
        resident = true,
        state = .Requested,
    }
    cache.preparation.state = .Queued
    cache.preparation.handle = handle
    cache.preparation.task = {
        key = .Bold,
        generation = 5,
        prepared = {key = .Bold, generation = 5, glyph_count = 1},
    }
    for taskpool.task_pool_poll(&pool, handle) == .Pending {
        thread.yield()
    }
    cache_complete_preparation(&cache, &pool)

    testing.expect_value(t, cache.preparation.stale_completion_count, u64(1))
    testing.expect_value(t, cache.preparation.publication_count, u64(0))
    testing.expect_value(t, cache.preparation.failure_count, u64(0))
    testing.expect_value(t, cache.entries[int(Font_Key.Bold)].font.baseSize, 55)
    testing.expect_value(t, cache.entries[int(Font_Key.Bold)].generation, u64(4))
}

// Verify a superseded accepted seed is cancelled, joined, and classified separately.
@(test)
view_test_cache_service_cancels_superseded_preparation :: proc(t: ^testing.T) {
    pool: taskpool.Task_Pool
    testing.expect(t, taskpool.task_pool_init(&pool, 1, 1))
    defer taskpool.task_pool_destroy(&pool)
    observed := false
    handle, outcome := taskpool.task_pool_submit(
        &pool, font_test_wait_for_cancellation, &observed)
    testing.expect_value(t, outcome, taskpool.Task_Submit_Outcome.Queued)
    cache: Font_Cache
    cache.entries[int(Font_Key.Bold)] = {
        generation = 4,
        requested_generation = 6,
        resident = true,
        state = .Requested,
    }
    cache.preparation.state = .Queued
    cache.preparation.handle = handle
    cache.preparation.task = {
        kind = .Seed,
        key = .Bold,
        generation = 5,
    }

    for !cache_preparation_idle(&cache) {
        cache_service(&cache, &pool)
        thread.yield()
    }

    testing.expect(t, observed)
    testing.expect_value(t, cache.preparation.cancellation_request_count, u64(1))
    testing.expect_value(t, cache.preparation.cancellation_completion_count, u64(1))
    testing.expect_value(t, cache.preparation.failure_count, u64(0))
    testing.expect_value(t, cache.preparation.stale_completion_count, u64(0))
    testing.expect_value(t, pool.outstanding_count, 0)
}

// Verify cancelled page work restores demand before the next generation proceeds.
@(test)
view_test_cache_service_cancelled_page_restores_demand :: proc(t: ^testing.T) {
    pool: taskpool.Task_Pool
    testing.expect(t, taskpool.task_pool_init(&pool, 1, 1))
    defer taskpool.task_pool_destroy(&pool)
    observed := false
    handle, outcome := taskpool.task_pool_submit(
        &pool, font_test_wait_for_cancellation, &observed)
    testing.expect_value(t, outcome, taskpool.Task_Submit_Outcome.Queued)
    glyph_storage: [32]Font_Glyph_Record
    glyphs := glyph_storage[:]
    cache: Font_Cache
    font_test_configure_stale_page(&cache, handle, glyphs)

    for !cache_preparation_idle(&cache) {
        cache_service(&cache, &pool)
        thread.yield()
    }

    testing.expect(t, observed)
    testing.expect_value(t, glyphs[17].state, Font_Glyph_State.Pending)
    testing.expect_value(t, glyphs[18].state, Font_Glyph_State.Missing)
    testing.expect_value(t, cache.entries[int(Font_Key.Bold)].queued_demand_count, i32(0))
    testing.expect_value(t, cache.preparation.cancellation_completion_count, u64(1))
    testing.expect_value(t, pool.outstanding_count, 0)
}

// Verify demand for another font does not cancel a current accepted preparation.
@(test)
view_test_cache_service_preserves_current_other_key_work :: proc(t: ^testing.T) {
    pool: taskpool.Task_Pool
    testing.expect(t, taskpool.task_pool_init(&pool, 1, 1))
    defer taskpool.task_pool_destroy(&pool)
    observed := false
    handle, outcome := taskpool.task_pool_submit(
        &pool, font_test_wait_for_cancellation, &observed)
    testing.expect_value(t, outcome, taskpool.Task_Submit_Outcome.Queued)
    cache: Font_Cache
    cache.entries[int(Font_Key.Bold)] = {
        requested_generation = 5,
        state = .Preparing,
    }
    cache.entries[int(Font_Key.Regular_Italic)] = {
        requested_generation = 2,
        state = .Requested,
    }
    cache.preparation.state = .Queued
    cache.preparation.handle = handle
    cache.preparation.task = {
        kind = .Seed,
        key = .Bold,
        generation = 5,
    }

    cache_service(&cache, &pool)
    testing.expect_value(t, cache.preparation.cancellation_request_count, u64(0))
    testing.expect(t, !observed)

    testing.expect_value(t, taskpool.task_pool_cancel(&pool, handle),
        taskpool.Task_Cancel_Outcome.Requested)
    for !cache_preparation_idle(&cache) {
        cache_service(&cache, &pool)
        thread.yield()
    }
    testing.expect(t, observed)
}

// Verify queue saturation retries and terminal task failure preserves residency.
@(test)
view_test_cache_retries_queue_full :: proc(t: ^testing.T) {
    pool: taskpool.Task_Pool
    testing.expect(t, taskpool.task_pool_init(&pool, 1, 1))
    defer taskpool.task_pool_destroy(&pool)
    occupied, _ := taskpool.task_pool_submit(
        &pool, test_task_succeed, nil)
    cache: Font_Cache
    cache.entries[int(Font_Key.Bold)] = {
        font = {baseSize = 55}, resident = true,
    }
    testing.expect(t, cache_request(&cache, .Bold))
    testing.expect(t, prepare_task_set_path(
        &cache.preparation.task, "assets/missing-font.ttf"))

    cache_service(&cache, &pool)
    testing.expect_value(t, cache.preparation.state, Font_Prepare_Operation_State.Retry)
    testing.expect_value(t, cache.preparation.queue_full_count, u64(1))

    taskpool.task_pool_wait(&pool, occupied)
    cache_service(&cache, &pool)
    for !cache_preparation_idle(&cache) {
        cache_service(&cache, &pool)
        thread.yield()
    }
    testing.expect_value(t, cache.preparation.failure_count, u64(1))
    testing.expect_value(t, cache.entries[int(Font_Key.Bold)].font.baseSize, 55)
}

// Verify shutdown cleans both retry-only and accepted task ownership states.
@(test)
view_test_cache_shutdown_task_states :: proc(t: ^testing.T) {
    retry_pool: taskpool.Task_Pool
    testing.expect(t, taskpool.task_pool_init(&retry_pool, 1, 1))
    retry_cache: Font_Cache
    testing.expect(t, cache_request(&retry_cache, .Bold))
    cache_shutdown_service(&retry_cache, &retry_pool)
    testing.expect(t, cache_preparation_idle(&retry_cache))
    testing.expect_value(t, retry_cache.preparation.failure_count, u64(1))
    taskpool.task_pool_destroy(&retry_pool)

    queued_pool: taskpool.Task_Pool
    testing.expect(t, taskpool.task_pool_init(&queued_pool, 1, 1))
    queued_cache: Font_Cache
    testing.expect(t, cache_request(&queued_cache, .Bold))
    testing.expect(t, prepare_task_set_path(
        &queued_cache.preparation.task, "assets/missing-font.ttf"))
    cache_service(&queued_cache, &queued_pool)
    testing.expect_value(
        t, queued_cache.preparation.state, Font_Prepare_Operation_State.Queued)
    cache_shutdown_service(&queued_cache, &queued_pool)
    testing.expect(t, cache_preparation_idle(&queued_cache))
    testing.expect_value(
        t, queued_cache.preparation.cancellation_request_count, u64(1))
    testing.expect_value(
        t, queued_cache.preparation.cancellation_completion_count, u64(1))
    testing.expect_value(t, queued_cache.preparation.failure_count, u64(0))
    taskpool.task_pool_destroy(&queued_pool)
}

// Verify cache resolution borrows resident variants and falls back to Regular.
@(test)
view_test_cache_resolution :: proc(t: ^testing.T) {
    cache: Font_Cache
    cache.entries[int(Font_Key.Regular)] = {
        font = {baseSize = 11},
        resident = true,
    }
    cache.entries[int(Font_Key.Bold)] = {
        font = {baseSize = 22},
        resident = true,
        state = .Ready,
    }

    testing.expect_value(t, cache_resolve(&cache, .Bold).baseSize, 22)
    testing.expect_value(
        t, cache_resolve(&cache, .Black_Italic).baseSize, 11)
    testing.expect_value(
        t, cache.entries[int(Font_Key.Black_Italic)].request_count, u64(1))
    testing.expect_value(
        t, cache.entries[int(Font_Key.Black_Italic)].state,
        Font_Load_State.Preparing)
    testing.expect(t, !cache_request(&cache, .Black_Italic))
    testing.expect_value(
        t, cache.entries[int(Font_Key.Black_Italic)].coalesced_request_count,
        u64(1))
    testing.expect_value(
        t, cache.entries[int(Font_Key.Black_Italic)].fallback_resolution_count,
        u64(1))

    resolver := cache_terminal_resolver(&cache)
    testing.expect_value(
        t, resolver.resolve(resolver.user_data, .Bold).baseSize, 22)
}

// Verify distinct demand is serialized and failed variants remain on fallback.
@(test)
view_test_cache_serializes_demand :: proc(t: ^testing.T) {
    cache: Font_Cache
    cache.entries[int(Font_Key.Regular)] = {
        font = {baseSize = 11}, resident = true, state = .Ready,
    }

    testing.expect_value(t, cache_resolve(&cache, .Bold).baseSize, 11)
    testing.expect_value(t, cache_resolve(&cache, .Black).baseSize, 11)
    testing.expect_value(
        t, cache.entries[int(Font_Key.Bold)].state,
        Font_Load_State.Preparing)
    testing.expect_value(
        t, cache.entries[int(Font_Key.Black)].state,
        Font_Load_State.Requested)

    cache.entries[int(Font_Key.Bold)].state = .Failed
    cache_finish_preparation(&cache)
    cache_begin_next_request(&cache)
    testing.expect_value(
        t, cache.entries[int(Font_Key.Black)].state,
        Font_Load_State.Preparing)
    testing.expect_value(t, cache_resolve(&cache, .Bold).baseSize, 11)
    testing.expect_value(
        t, cache.entries[int(Font_Key.Bold)].state, Font_Load_State.Failed)
}
