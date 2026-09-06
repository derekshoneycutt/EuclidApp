package font

import "../../core"
import "../../files"

import "core:mem"
import vmem "core:mem/virtual"
import "core:log"
import "core:os"
import "core:path/filepath"

import rl "vendor:raylib"

// Maximum runes in either required startup seed policy.
FONT_SEED_CODEPOINT_CAPACITY :: core.FONT_SEED_CODEPOINT_CAPACITY

// Maximum face glyphs admitted to one prepared atlas page.
FONT_GLYPH_PAGE_REQUEST_CAPACITY :: 256

// Number of indexed font variants through the final `Font_Key` value.
FONT_KEY_COUNT :: core.FONT_KEY_COUNT

// Pixel height used for synchronous and asynchronously prepared JuliaMono fonts.
JULIA_MONO_FONT_SIZE :: 32

// Virtual address-space reservation shared by serialized font preparations.
FONT_PREPARATION_ARENA_RESERVE_SIZE :: 96 * mem.Megabyte

// Physical pages committed eagerly when the preparation arena is created.
FONT_PREPARATION_ARENA_INITIAL_COMMIT_SIZE :: 1 * mem.Megabyte

// JuliaMono asset filename indexed exactly by `Font_Key`.
FONT_FILENAMES :: [FONT_KEY_COUNT]string{
    "JuliaMono-Regular.ttf",
    "JuliaMono-RegularItalic.ttf",
    "JuliaMono-Light.ttf",
    "JuliaMono-LightItalic.ttf",
    "JuliaMono-Medium.ttf",
    "JuliaMono-MediumItalic.ttf",
    "JuliaMono-SemiBold.ttf",
    "JuliaMono-SemiBoldItalic.ttf",
    "JuliaMono-Bold.ttf",
    "JuliaMono-BoldItalic.ttf",
    "JuliaMono-ExtraBold.ttf",
    "JuliaMono-ExtraBoldItalic.ttf",
    "JuliaMono-Black.ttf",
    "JuliaMono-BlackItalic.ttf",
    "NewCMSansMath-Regular.otf",
}

Font_Key :: core.Font_Key
Font_Load_State :: core.Font_Load_State
Font_Cache_Entry :: core.Font_Cache_Entry
Font_Cache :: core.Font_Cache
Font_Shaping_Telemetry :: core.Font_Shaping_Telemetry
Font_Glyph_State :: core.Font_Glyph_State
Font_Glyph_Record :: core.Font_Glyph_Record
Font_Glyph_Page :: core.Font_Glyph_Page

// Borrowed display-thread glyph data normalized across seed and paged textures.
Resolved_Glyph :: struct {
    texture: rl.Texture2D,
    source: rl.Rectangle,
    offset_x: i32,
    offset_y: i32,
    advance_x: i32,
    base_size: i32,
}

Font_Glyph_Resolve_Status :: enum {
    Resident,
    Pending,
    Unsupported,
    Capacity_Exhausted,
}

// Inclusive Unicode interval included in the JuliaMono loading policy.
Font_Codepoint_Range :: struct {
    first: rune,
    last: rune,
}

// Fixed flat rune set passed to raylib/stb seed loading APIs.
Font_Seed_Codepoint_Set :: struct {
    values: [FONT_SEED_CODEPOINT_CAPACITY]rune,
    count: i32,
}

// Startup and unshaped fallback coverage retained by every resident face.
FONT_SEED_CODEPOINT_RANGES :: [?]Font_Codepoint_Range {
    {0x0020, 0x007e},
    {0xfffd, 0xfffd},
}

// Required NewCM coverage for ordinary operators and projected math variables.
MATH_SEED_CODEPOINT_RANGES :: [?]Font_Codepoint_Range {
    {0x0020, 0x007e},
    {0x0391, 0x03a1},
    {0x03a3, 0x03a9},
    {0x210e, 0x210e},
    {0x2202, 0x2202},
    {0x220f, 0x2211},
    {0x2212, 0x2212},
    {0x221a, 0x221a},
    {0x221e, 0x221e},
    {0x222b, 0x222b},
    {0x2248, 0x2248},
    {0x2260, 0x2260},
    {0x2264, 0x2265},
    {0x2102, 0x2134},
    {0x1d400, 0x1d433},
    {0x1d434, 0x1d467},
    {0x1d49c, 0x1d4b5},
    {0x1d538, 0x1d56b},
    {0x1d6fc, 0x1d71b},
    {0x1d7ce, 0x1d7e1},
}


// Resolve one cache-owned font handle for the requested semantic variant.
Font_Resolve_Handler :: proc(user_data: rawptr, key: Font_Key) -> rl.Font

// Resolve one shaped face glyph to immutable display-owned page data.
Font_Resolve_Glyph_Handler :: proc(
    user_data: rawptr, key: Font_Key,
    glyph_id: u32) -> (Resolved_Glyph, bool)

// Resolve one Unicode scalar through the effective face cmap and glyph pages.
Font_Resolve_Codepoint_Handler :: proc(
    user_data: rawptr, key: Font_Key,
    codepoint: rune) -> (Resolved_Glyph, Font_Glyph_Resolve_Status)

// Shape one borrowed UTF-8 run into caller-owned bounded glyph storage.
Font_Shape_Handler :: proc(
    user_data: rawptr, key: Font_Key, text: string,
    output: []Shaped_Glyph) -> (int, bool)

Shape_Fallback_Reason :: enum {
    Workspace_Overflow,
    Invalid_Result,
    Invalid_Cluster,
    Pending_Glyph,
}

// Record one bounded shaped-presentation fallback without retaining source text.
Font_Shape_Fallback_Handler :: proc(
    user_data: rawptr, reason: Shape_Fallback_Reason)

// Borrowing capability drawing to resolve semantic font keys.
Font_Resolver :: struct {
    user_data: rawptr,
    resolve: Font_Resolve_Handler,
    resolve_glyph: Font_Resolve_Glyph_Handler,
    resolve_codepoint: Font_Resolve_Codepoint_Handler,
    shape: Font_Shape_Handler,
    record_shape_fallback: Font_Shape_Fallback_Handler,
    workspace: []Shaped_Glyph,
}

//   Resolve one font source from packaged assets or the source-tree fallback.
font_asset_path :: proc(filename: string) -> string {
    path := files.packaged_asset_path(filename, context.temp_allocator)
    if len(path) > 0 {
        return path
    }
    fallback, path_error := filepath.join(
        []string{"assets", filename}, context.temp_allocator)
    if path_error != nil || !os.exists(fallback) {
        return ""
    }
    return fallback
}

//   Resolve and retain every configured source path for this cache lifetime.
cache_source_paths_init :: proc(cache: ^Font_Cache) {
    filenames := FONT_FILENAMES
    for key_index in 0..<FONT_KEY_COUNT {
        path := font_asset_path(filenames[key_index])
        destination := &cache.source_paths[key_index]
        if len(path) == 0 || len(path) > len(destination.storage) {
            continue
        }
        copy(destination.storage[:], transmute([]u8)path)
        destination.length = len(path)
    }
}

//   Borrow one cache-owned source path, resolving it lazily for zero-valued tests.
cache_source_path :: proc(cache: ^Font_Cache, key: Font_Key) -> string {
    source := &cache.source_paths[int(key)]
    if source.length == 0 {
        filenames := FONT_FILENAMES
        path := font_asset_path(filenames[int(key)])
        if len(path) == 0 || len(path) > len(source.storage) {
            return ""
        }
        copy(source.storage[:], transmute([]u8)path)
        source.length = len(path)
    }
    return string(source.storage[:source.length])
}

//   Build the compatibility seed in raylib's required flat form.
//
// Returns:
//   - Fixed storage containing every rune from `FONT_SEED_CODEPOINT_RANGES`.
seed_codepoint_set_from_ranges :: proc(
    ranges: []Font_Codepoint_Range) -> Font_Seed_Codepoint_Set {

    result: Font_Seed_Codepoint_Set
    for codepoint_range in ranges {
        for codepoint := codepoint_range.first;
            codepoint <= codepoint_range.last;
            codepoint += 1 {

            assert(result.count < FONT_SEED_CODEPOINT_CAPACITY)
            result.values[result.count] = codepoint
            result.count += 1
        }
    }
    return result
}

//   Build the JuliaMono compatibility seed in raylib's required flat form.
seed_codepoint_set :: proc() -> Font_Seed_Codepoint_Set {
    ranges := FONT_SEED_CODEPOINT_RANGES
    return seed_codepoint_set_from_ranges(ranges[:])
}

//   Build the required NewCM math seed in raylib's required flat form.
math_seed_codepoint_set :: proc() -> Font_Seed_Codepoint_Set {
    ranges := MATH_SEED_CODEPOINT_RANGES
    return seed_codepoint_set_from_ranges(ranges[:])
}

//   Suppress raylib's expected oversized-glyph and sparse-range messages during rasterization.
//
// Side effects:
//   - Sets raylib's process-global trace threshold to errors.
rasterization_begin :: proc() {
    rl.SetTraceLogLevel(.ERROR)
}

//   Restore normal raylib diagnostics immediately after font rasterization.
//
// Side effects:
//   - Sets raylib's process-global trace threshold to informational messages.
rasterization_end :: proc() {
    rl.SetTraceLogLevel(.INFO)
}

//   Release one generation's shaping handles and native source copy.
font_shaping_destroy :: proc(resource: ^Font_Shaping_Resource) {
    harfbuzz_shaper_destroy(resource)
}

//   Allocate one directly indexed glyph-state table for a candidate generation.
//
// Returns:
//   - True after exact-size metadata allocation; false without changing the entry.
font_generation_glyphs_init :: proc(
    entry: ^Font_Cache_Entry, glyph_count: int,
    allocator: mem.Allocator) -> bool {

    if entry == nil || glyph_count <= 0 || entry.glyphs != nil {
        return false
    }
    glyphs, allocation_error := make(
        []Font_Glyph_Record, glyph_count, allocator)
    if allocation_error != nil {
        return false
    }
    entry.glyphs = glyphs
    entry.glyph_allocator = allocator
    return true
}

//   Release generation metadata after every page texture has been retired.
font_generation_glyphs_destroy :: proc(entry: ^Font_Cache_Entry) {
    if entry == nil {
        return
    }
    if entry.glyphs != nil {
        delete(entry.glyphs, entry.glyph_allocator)
    }
    entry.glyphs = nil
    entry.glyph_allocator = {}
    entry.page_count = 0
    entry.pending_glyph_count = 0
    entry.queued_demand_count = 0
}

//   Calculate page slots needed after admitting more unqueued demand.
font_generation_required_page_count :: proc(
    entry: ^Font_Cache_Entry, additional_demand: i32) -> i32 {

    queued_page_count := i32(0)
    if entry.queued_demand_count > 0 {
        queued_page_count = 1
    }
    unqueued_count := entry.pending_glyph_count - entry.queued_demand_count +
        additional_demand
    unqueued_page_count := (unqueued_count + FONT_GLYPH_PAGE_REQUEST_CAPACITY - 1)/
        FONT_GLYPH_PAGE_REQUEST_CAPACITY
    return entry.page_count + queued_page_count + unqueued_page_count
}

//   Mark one unresolved glyph ID as pending without duplicate queue storage.
//
// Returns:
//   - True only when this call creates new bounded demand.
font_generation_request_glyph :: proc(
    entry: ^Font_Cache_Entry, glyph_id: u32) -> bool {

    if entry == nil || glyph_id >= u32(len(entry.glyphs)) {
        return false
    }
    glyph := &entry.glyphs[glyph_id]
    if glyph.state != .Missing {
        return false
    }
    if font_generation_required_page_count(entry, 1) >
        core.FONT_GLYPH_PAGE_CAPACITY {
        glyph.state = .Capacity_Blocked
        entry.capacity_rejection_count += 1
        return false
    }
    glyph.state = .Pending
    entry.pending_glyph_count += 1
    return true
}

//   Copy one prepared seed's metrics into exact-size generation storage.
//
// Returns:
//   - True when every prepared glyph maps uniquely inside the face glyph table.
font_generation_seed_records_init :: proc(
    entry: ^Font_Cache_Entry, prepared: ^Prepared_Font,
    allocator: mem.Allocator) -> bool {

    if entry == nil || prepared == nil || prepared.face_glyph_count <= 0 ||
        !font_generation_glyphs_init(
            entry, int(prepared.face_glyph_count), allocator) {
        return false
    }
    for glyph, index in prepared.glyphs {
        if glyph.glyph_id >= u32(len(entry.glyphs)) {
            font_generation_glyphs_destroy(entry)
            return false
        }
        rectangle := prepared.rectangles[index]
        entry.glyphs[glyph.glyph_id] = {
            rectangle = {
                x = f32(rectangle.x),
                y = f32(rectangle.y),
                width = f32(rectangle.width),
                height = f32(rectangle.height),
            },
            offset_x = glyph.offset_x,
            offset_y = glyph.offset_y,
            advance_x = glyph.advance_x,
            state = .Resident,
        }
    }
    return true
}

//   Destroy every display and native resource owned by one font generation.
font_generation_destroy :: proc(entry: ^Font_Cache_Entry) {
    if entry == nil {
        return
    }
    for page_index in 0..<int(entry.page_count) {
        if rl.IsTextureValid(entry.pages[page_index].texture) {
            rl.UnloadTexture(entry.pages[page_index].texture)
        }
    }
    if rl.IsFontValid(entry.font) {
        rl.UnloadFont(entry.font)
    }
    font_shaping_destroy(&entry.shaping)
    font_generation_glyphs_destroy(entry)
}

//   Read transient source through the preparation arena and acquire a native shaper.
font_shaping_create :: proc(
    cache: ^Font_Cache, key: Font_Key, path: string,
    resource: ^Font_Shaping_Resource) -> bool {

    if cache == nil || resource == nil || len(path) == 0 ||
        !cache_preparation_arena_init(cache) {
        return false
    }
    resource^ = {}
    source, read_error := os.read_entire_file(
        path, vmem.arena_allocator(&cache.preparation_arena))
    if read_error != nil {
        return false
    }
    if !harfbuzz_shaper_init(source, JULIA_MONO_FONT_SIZE, resource) {
        return false
    }
    if key == .Math_Regular && !harfbuzz_face_has_math_table(resource) {
        font_shaping_destroy(resource)
        return false
    }
    return true
}

//   Finalize and publish one synchronous required seed candidate.
cache_publish_required_seed :: proc(
    entry: ^Font_Cache_Entry, prepared: ^Prepared_Font,
    shaping: ^Font_Shaping_Resource) -> bool {

    if !font_generation_seed_records_init(
        entry, prepared, context.allocator) {
        font_shaping_destroy(shaping)
        return false
    }
    raster_ascent := prepared^.raster_ascent
    candidate: rl.Font
    if !finalize(prepared, &candidate) {
        font_shaping_destroy(shaping)
        font_generation_glyphs_destroy(entry)
        return false
    }
    entry.font = candidate
    entry.shaping = shaping^
    entry.raster_ascent = raster_ascent
    return true
}

//   Return the bounded startup seed policy for one required font key.
required_seed_codepoints :: proc(key: Font_Key) -> Font_Seed_Codepoint_Set {
    return math_seed_codepoint_set() if key == .Math_Regular else
        seed_codepoint_set()
}

//   Prepare and finalize one synchronous required font generation.
cache_load_required :: proc(cache: ^Font_Cache, key: Font_Key) -> bool {
    if key != .Regular && key != .Math_Regular {
        return false
    }
    if !cache_preparation_arena_init(cache) {
        return false
    }
    defer cache_preparation_arena_reset(cache)
    allocator := vmem.arena_allocator(&cache.preparation_arena)
    codepoints := required_seed_codepoints(key)
    path := cache_source_path(cache, key)
    prepared: Prepared_Font
    if !prepare({
        key = key,
        path = path,
        pixel_size = JULIA_MONO_FONT_SIZE,
        codepoints = codepoints.values[:codepoints.count],
    }, &prepared, allocator, .Arena) {
        return false
    }
    defer prepare_destroy(&prepared)
    shaping: Font_Shaping_Resource
    if !font_shaping_create(cache, key, path, &shaping) {
        return false
    }
    entry := &cache.entries[int(key)]
    return cache_publish_required_seed(entry, &prepared, &shaping)
}

//   Load the permanent Regular fallback and required NewCM math face at startup.
//
// Parameters:
//   - cache: Zero-valued display-thread-owned cache.
//
// Side effects:
//   - Loads both required GPU fonts synchronously and records source-file baselines.
//   - Rolls back all cache ownership if either required generation fails.
cache_init :: proc(cache: ^Font_Cache) -> bool {
    assert(cache != nil)
    cache^ = {}
    cache_source_paths_init(cache)
    rasterization_begin()
    required_keys := [?]Font_Key{.Regular, .Math_Regular}
    ready := true
    for key in required_keys {
        entry := &cache.entries[int(key)]
        entry.requested_generation = 1
        entry.resident = cache_load_required(cache, key)
        entry.generation = 1 if entry.resident else 0
        entry.state = entry.resident ? .Ready : .Failed
        if entry.resident {
            log.infof("required_font_ready key=%d", int(key))
        } else {
            log.errorf("required_font_failed key=%d", int(key))
        }
        ready = ready && entry.resident
    }
    rasterization_end()
    if !ready {
        cache_destroy(cache)
        return false
    }
    source_monitor_init(cache, source_monitor_now_ns())
    return true
}

//   Unload every resident font owned by the cache.
//
// Parameters:
//   - cache: Cache with no queued preparation; nil is a no-op.
//
// Side effects:
//   - Unloads all resident GPU resources, releases the preparation arena, and resets state.
cache_destroy :: proc(cache: ^Font_Cache) {
    if cache == nil {
        return
    }
    for entry_index in 0..<FONT_KEY_COUNT {
        entry := &cache.entries[entry_index]
        font_generation_destroy(entry)
    }
    cache_preparation_arena_destroy(cache)
    cache^ = {}
}

//   Build and atomically install one resident math-font shaping candidate.
math_shaping_replace :: proc(
    cache: ^Font_Cache,
    entry: ^Font_Cache_Entry,
    capability: ^Font_Math_Shaping_Capability) -> bool {
    path := cache_source_path(cache, .Math_Regular)
    source, read_error := os.read_entire_file(path, context.allocator)
    if read_error != nil {
        capability.failed_generation = entry.generation
        return false
    }
    defer delete(source)
    candidate := Font_Math_Shaping_Capability{
        generation = entry.generation,
        raster_ascent = entry.raster_ascent,
    }
    if !harfbuzz_shaper_init(source, JULIA_MONO_FONT_SIZE, &candidate.resource) ||
        !harfbuzz_face_has_math_table(&candidate.resource) ||
        !harfbuzz_math_constants_capture(&candidate.resource, candidate.generation,
            f32(JULIA_MONO_FONT_SIZE), &candidate.constants,
            harfbuzz_text_match_scale(
                &cache.entries[int(Font_Key.Regular)].shaping,
                &candidate.resource)) {
        math_shaping_destroy(&candidate)
        capability.failed_generation = entry.generation
        return false
    }
    previous := capability^
    capability^ = candidate
    math_shaping_destroy(&previous)
    return true
}

//   Synchronize a separate Dynview math shaper to the resident NewCM generation.
//
// Returns:
//   - True when the existing capability is current or a complete candidate replaces it.
//   - False while no resident math generation exists or candidate construction fails.
//
// Side effects:
//   - Reads source bytes into temporary display-thread storage, atomically replaces
//     `runtime.math_shaping` on success, and preserves the prior capability on failure.
math_shaping_sync :: proc(
    cache: ^Font_Cache,
    capability: ^Font_Math_Shaping_Capability) -> bool {

    if cache == nil || capability == nil {
        return false
    }
    entry := &cache.entries[int(Font_Key.Math_Regular)]
    if !entry.resident || entry.generation == 0 {
        return false
    }
    if math_shaping_generation_matches(capability, entry.generation) {
        return true
    }
    if capability.failed_generation == entry.generation {
        return false
    }
    return math_shaping_replace(cache, entry, capability)
}

//   Borrow a resident font or Regular without recording new demand.
//
// Returns:
//   - The requested resident GPU handle, otherwise the permanent Regular fallback.
//
// Notes:
//   - The returned handle remains cache-owned and may be invalidated by reload/destroy.
cache_borrow :: proc(cache: ^Font_Cache, key: Font_Key) -> rl.Font {
    assert(cache != nil)
    entry := cache.entries[int(key)]
    if entry.resident {
        return entry.font
    }
    return cache.entries[int(Font_Key.Regular)].font
}

//   Record optional demand and borrow its resident font or Regular immediately.
//
// Returns:
//   - The requested resident GPU handle, or Regular while asynchronous work is pending.
//
// Side effects:
//   - Records first demand and increments fallback-resolution telemetry when needed.
cache_resolve :: proc(cache: ^Font_Cache, key: Font_Key) -> rl.Font {
    assert(cache != nil)
    entry := &cache.entries[int(key)]
    if entry.resident {
        return entry.font
    }
    cache_request(cache, key)
    entry.fallback_resolution_count += 1
    return cache_borrow(cache, .Regular)
}

//   Adapt cache resolution to the terminal's borrowing capability.
//
// Returns:
//   - The result of `cache_resolve` for the cache borrowed through `user_data`.
cache_terminal_resolve :: proc(user_data: rawptr, key: Font_Key) -> rl.Font {
    return cache_resolve(cast(^Font_Cache)user_data, key)
}

//   Select the same resident generation used by shaping and glyph resolution.
cache_effective_entry :: proc(
    cache: ^Font_Cache, key: Font_Key) -> ^Font_Cache_Entry {

    if cache == nil {
        return nil
    }
    entry := &cache.entries[int(key)]
    if entry.resident {
        return entry
    }
    return &cache.entries[int(Font_Key.Regular)]
}

//   Report whether one exact font generation is resident for cached drawing.
cache_generation_is_resident :: #force_inline proc(
    cache: ^Font_Cache, key: Font_Key, generation: u64) -> bool {

    if cache == nil || generation == 0 {
        return false
    }
    entry := &cache^.entries[int(key)]
    return entry^.resident && entry^.generation == generation
}

//   Normalize one resident glyph record to borrowed draw data.
font_generation_resolve_glyph :: proc(
    entry: ^Font_Cache_Entry, glyph_id: u32) -> (Resolved_Glyph, bool) {

    if entry == nil || glyph_id >= u32(len(entry.glyphs)) ||
        entry.glyphs[glyph_id].state != .Resident {
        return {}, false
    }
    glyph := entry.glyphs[glyph_id]
    texture := entry.font.texture
    if glyph.page_index > 0 {
        page_index := int(glyph.page_index) - 1
        if page_index >= int(entry.page_count) {
            return {}, false
        }
        texture = entry.pages[page_index].texture
    }
    return {
        texture = texture,
        source = glyph.rectangle,
        offset_x = glyph.offset_x,
        offset_y = glyph.offset_y,
        advance_x = glyph.advance_x,
        base_size = entry.font.baseSize,
    }, true
}

//   Resolve one shaped glyph from the effective resident generation.
//
// Returns:
//   - Borrowed draw data and true when resident; otherwise zero and false.
cache_terminal_resolve_glyph :: proc(
    user_data: rawptr, key: Font_Key,
    glyph_id: u32) -> (Resolved_Glyph, bool) {

    cache := cast(^Font_Cache)user_data
    if cache == nil {
        return {}, false
    }
    entry := cache_effective_entry(cache, key)
    resolved, resident := font_generation_resolve_glyph(entry, glyph_id)
    if resident {
        return resolved, true
    }
    _ = font_generation_request_glyph(entry, glyph_id)
    return {}, false
}

//   Resolve one codepoint through the effective cmap and page state.
cache_terminal_resolve_codepoint :: proc(
    user_data: rawptr, key: Font_Key,
    codepoint: rune) -> (Resolved_Glyph, Font_Glyph_Resolve_Status) {

    cache := cast(^Font_Cache)user_data
    entry := cache_effective_entry(cache, key)
    if entry == nil {
        return {}, .Unsupported
    }
    glyph_id, supported := harfbuzz_nominal_glyph(&entry.shaping, codepoint)
    if !supported || glyph_id >= u32(len(entry.glyphs)) {
        entry.unsupported_codepoint_count += 1
        return {}, .Unsupported
    }
    resolved, resident := font_generation_resolve_glyph(entry, glyph_id)
    if resident {
        return resolved, .Resident
    }
    _ = font_generation_request_glyph(entry, glyph_id)
    if entry.glyphs[glyph_id].state == .Capacity_Blocked {
        return {}, .Capacity_Exhausted
    }
    entry.pending_codepoint_count += 1
    return {}, .Pending
}

//   Validate one completed page against current generation and queued demand.
//
// Returns:
//   - True when every compact glyph record can publish without partial mutation.
cache_glyph_page_can_publish :: proc(
    entry: ^Font_Cache_Entry, prepared: ^Prepared_Font) -> bool {

    if entry == nil || prepared == nil ||
        prepared.generation != entry.generation ||
        entry.generation != entry.requested_generation ||
        entry.page_count >= core.FONT_GLYPH_PAGE_CAPACITY {
        return false
    }
    for glyph in prepared.glyphs {
        if glyph.glyph_id >= u32(len(entry.glyphs)) ||
            entry.glyphs[glyph.glyph_id].state != .Queued {
            return false
        }
    }
    return true
}

//   Report whether a prepared page exactly matches its submitted glyph-ID batch.
//
// Returns:
//   - True when count and ordered face glyph IDs are unchanged by preparation.
cache_glyph_page_matches_task :: proc(
    prepared: ^Prepared_Font, task: ^Font_Prepare_Task) -> bool {

    if prepared == nil || task == nil ||
        prepared.glyph_count != task.glyph_id_count {
        return false
    }
    for glyph, index in prepared.glyphs {
        if glyph.glyph_id != task.glyph_ids[index] {
            return false
        }
    }
    return true
}

//   Publish page-local glyph records and resolve demanded counters.
cache_publish_glyph_records :: proc(
    entry: ^Font_Cache_Entry, prepared: ^Prepared_Font,
    task: ^Font_Prepare_Task, page_index: i32) {

    for glyph, index in prepared.glyphs {
        rectangle := prepared.rectangles[index]
        entry.glyphs[glyph.glyph_id] = {
            rectangle = {
                x = f32(rectangle.x), y = f32(rectangle.y),
                width = f32(rectangle.width), height = f32(rectangle.height),
            },
            offset_x = glyph.offset_x,
            offset_y = glyph.offset_y,
            advance_x = glyph.advance_x,
            page_index = u16(page_index + 1),
            state = .Resident,
        }
        if i32(index) < task.demanded_glyph_count {
            entry.pending_glyph_count -= 1
        }
    }
}

//   Commit one immutable page descriptor and its publication telemetry.
cache_commit_glyph_page :: proc(
    entry: ^Font_Cache_Entry, prepared: ^Prepared_Font,
    task: ^Font_Prepare_Task, texture: rl.Texture2D) {

    page_index := entry.page_count
    entry.pages[page_index] = {
        texture = texture,
        generation = prepared.generation,
        glyph_count = prepared.glyph_count,
    }
    entry.page_count += 1
    entry.page_publication_count += 1
    entry.prefetched_glyph_count += u64(
        task.glyph_id_count - task.demanded_glyph_count)
    entry.queued_demand_count = 0
}

//   Publish one immutable page and resolve its queued glyph records atomically.
//
// Returns:
//   - True after texture and lookup publication; false without glyph-state mutation.
cache_publish_glyph_page :: proc(
    cache: ^Font_Cache, prepared: ^Prepared_Font,
    task: ^Font_Prepare_Task) -> bool {

    if cache == nil || prepared == nil {
        return false
    }
    entry := &cache.entries[int(prepared.key)]
    if !cache_glyph_page_matches_task(prepared, task) ||
        !cache_glyph_page_can_publish(entry, prepared) {
        return false
    }
    texture, finalized := finalize_glyph_page(prepared)
    if !finalized {
        return false
    }
    page_index := entry.page_count
    cache_publish_glyph_records(entry, prepared, task, page_index)
    cache_commit_glyph_page(entry, prepared, task, texture)
    prepare_destroy(prepared)
    return true
}

//   Adapt cache shaping to a frame-local resolver capability.
cache_terminal_shape :: proc(
    user_data: rawptr, key: Font_Key, text: string,
    output: []Shaped_Glyph) -> (int, bool) {

    return cache_shape(cast(^Font_Cache)user_data, key, text, output)
}

//   Record one shaped-presentation rejection in aggregate cache telemetry.
cache_terminal_record_shape_fallback :: proc(
    user_data: rawptr, reason: Shape_Fallback_Reason) {

    cache := cast(^Font_Cache)user_data
    if cache == nil {
        return
    }
    switch reason {
    case .Workspace_Overflow:
        cache.shaping_telemetry.workspace_overflows += 1
    case .Invalid_Result:
        cache.shaping_telemetry.invalid_results += 1
    case .Invalid_Cluster:
        cache.shaping_telemetry.invalid_clusters += 1
    case .Pending_Glyph:
        cache.shaping_telemetry.pending_glyph_runs += 1
    }
}

//   Create a frame-local terminal resolver borrowing from the cache.
//
// Returns:
//   - Callback capability whose `user_data` remains valid only while `cache` does.
cache_terminal_resolver :: proc(cache: ^Font_Cache) -> Font_Resolver {
    return {
        user_data = cache,
        resolve = cache_terminal_resolve,
        resolve_glyph = cache_terminal_resolve_glyph,
        resolve_codepoint = cache_terminal_resolve_codepoint,
        shape = cache_terminal_shape,
        record_shape_fallback = cache_terminal_record_shape_fallback,
        workspace = cache.shaped_glyphs[:],
    }
}

//   Convert dynview's weight and italic flags to one indexed cache key.
font_key_from_flags :: proc(flags: core.Font_Variant_Flags) -> Font_Key {
    italic := core.font_has_flag(flags, .Italic)
    switch core.font_resolve_weight_from_flags(flags) {
    case .Light:
        return italic ? .Light_Italic : .Light
    case .Medium:
        return italic ? .Medium_Italic : .Medium
    case .Semibold:
        return italic ? .Semi_Bold_Italic : .Semi_Bold
    case .Bold:
        return italic ? .Bold_Italic : .Bold
    case .Extrabold:
        return italic ? .Extra_Bold_Italic : .Extra_Bold
    case .Black:
        return italic ? .Black_Italic : .Black
    case .Regular:
        return italic ? .Regular_Italic : .Regular
    }
    return .Regular
}

//   Build generation-owned shaping and GPU candidates from one prepared font.
cache_publication_candidates :: proc(
    cache: ^Font_Cache, prepared: ^Prepared_Font,
    candidate: ^Font_Cache_Entry) -> bool {

    path := cache_source_path(cache, prepared.key)
    if !font_shaping_create(
        cache, prepared.key, path, &candidate.shaping) {
        return false
    }
    if !font_generation_seed_records_init(
        candidate, prepared, context.allocator) ||
        !finalize(prepared, &candidate.font) {
        font_generation_destroy(candidate)
        return false
    }
    candidate.resident = true
    return true
}

//   Finalize and atomically publish a prepared font on the display thread.
//
// Returns:
//   - True after current-generation GPU publication; false for invalid, stale, or
//     finalization failure while preserving any prior resident font.
//
// Side effects:
//   - On success, consumes prepared CPU storage and unloads the previous GPU resource.
cache_publish :: proc(cache: ^Font_Cache, prepared: ^Prepared_Font) -> bool {
    if cache == nil || prepared == nil {
        return false
    }
    entry := &cache.entries[int(prepared.key)]
    generation := prepared.generation
    if generation != entry.requested_generation {
        return false
    }

    candidate: Font_Cache_Entry
    if !cache_publication_candidates(cache, prepared, &candidate) {
        return false
    }
    previous := entry^
    candidate = {
        font = candidate.font,
        shaping = candidate.shaping,
        generation = generation,
        requested_generation = entry.requested_generation,
        resident = true,
        state = .Ready,
        request_count = entry.request_count,
        coalesced_request_count = entry.coalesced_request_count,
        fallback_resolution_count = entry.fallback_resolution_count,
        glyphs = candidate.glyphs,
        glyph_allocator = candidate.glyph_allocator,
    }
    entry^ = candidate
    font_generation_destroy(&previous)
    return true
}

//   Shape one run through a resident variant's generation-owned native state.
cache_shape :: proc(
    cache: ^Font_Cache, key: Font_Key, text: string,
    output: []Shaped_Glyph) -> (int, bool) {

    if cache == nil {
        return 0, false
    }
    cache.shaping_telemetry.shape_calls += 1
    entry := cache_effective_entry(cache, key)
    if !entry.resident || entry.shaping.font == nil {
        cache.shaping_telemetry.native_failures += 1
        return 0, false
    }
    glyph_count, shaped := harfbuzz_shape(
        &entry.shaping, text, true, output)
    if !shaped {
        cache.shaping_telemetry.native_failures += 1
        return 0, false
    }
    cache.shaping_telemetry.shaped_runs += 1
    cache.shaping_telemetry.shaped_glyphs += u64(glyph_count)
    return glyph_count, true
}

