package dynview_compile

import app_core "../../core"
import "core:mem"
import "core:testing"

Prose_Shaping_Rebuild_Fixture :: struct {
    inlines: [3]app_core.Dynview_Document_Inline,
    workspace: [8]app_core.Shaped_Glyph,
}

// Shape ASCII test text one glyph per byte with source-relative clusters.
prose_shaping_test_shape :: proc(
    _: rawptr,
    request: Document_Prose_Shape_Request) -> (int, bool) {

    if request.generation == 0 || len(request.text) > len(request.output) {
        return 0, false
    }
    for byte, index in transmute([]u8)request.text {
        request.output[index] = {
            glyph_id = u32(byte), cluster = u32(index), x_advance = 64}
    }
    return len(request.text), true
}

// Return stable one-pixel ink metrics for fake prose glyphs.
prose_shaping_test_extents :: proc(
    _: rawptr, _: app_core.Font_Key,
    generation: u64, glyph_id: u32) -> (app_core.Font_Glyph_Extents, bool) {

    if generation == 0 || glyph_id == 0 {
        return {}, false
    }
    return {y_bearing = 64, width = 64, height = -64}, true
}

// Build a complete service with Bold resolved to its own generation.
prose_shaping_test_service :: proc(
    workspace: []app_core.Shaped_Glyph) -> Document_Prose_Shaping_Service {

    result := Document_Prose_Shaping_Service{
        base_pixel_size = 32,
        shape = prose_shaping_test_shape,
        glyph_extents = prose_shaping_test_extents,
        glyph_workspace = workspace,
    }
    for index in 0..<DOCUMENT_PROSE_FONT_COUNT {
        result.fonts[index] = {.Regular, 7, 24}
    }
    result.fonts[int(app_core.Font_Key.Bold)] = {.Bold, 11, 25}
    return result
}

// Populate one semantic text, space, and variant run for deterministic rebuild tests.
prose_shaping_rebuild_fixture_init :: proc(
    runtime: ^app_core.Dynview_System,
    fixture: ^Prose_Shaping_Rebuild_Fixture) -> Document_Prose_Shaping_Service {

    fixture^.inlines = {
        {kind = .Text, text_offset = 0, text_count = 1,
            font_flags = i32(app_core.Font_Variant_Flags.Regular)},
        {kind = .Space, text_offset = 1, text_count = 1,
            font_flags = i32(app_core.Font_Variant_Flags.Regular)},
        {kind = .Text, text_offset = 2, text_count = 1,
            font_flags = i32(app_core.Font_Variant_Flags.Bold)},
    }
    text: string = "A B"
    runtime^.content.document_text = transmute([]u8)text
    runtime^.content.document_inlines = fixture^.inlines[:]
    return prose_shaping_test_service(fixture^.workspace[:])
}

// Initialize bounded test storage for prose shaping records.
prose_shaping_test_builder :: proc(
    t: ^testing.T, arena: ^app_core.Arena_Owner) -> Document_Shaped_Builder {

    testing.expect(t, app_core.arena_owner_init(arena, 2*uint(mem.Megabyte)))
    builder: Document_Shaped_Builder
    testing.expect_value(t, document_shaped_builder_init(
        &builder, app_core.arena_owner_allocator(arena)),
        app_core.Bounded_Builder_Status.Ok)
    return builder
}

// Build one valid Regular prose run for builder boundary tests.
prose_shaping_test_append :: proc(
    inline_index: int,
    glyphs: []app_core.Shaped_Glyph) -> Document_Shaped_Append {

    return {{
        inline_index = inline_index,
        text_offset = inline_index,
        text_count = 1,
        requested_font_key = .Regular,
        effective_font_key = .Regular,
        font_generation = 7,
        base_pixel_size = 32,
        raster_ascent = 24,
        width = 16,
        ascent = 20,
        descent = 4,
    }, glyphs}
}

// Verify ordered complete runs seal into immutable compile-cache aliases.
@(test)
document_prose_shaping_seals_complete_records :: proc(t: ^testing.T) {
    arena: app_core.Arena_Owner
    builder := prose_shaping_test_builder(t, &arena)
    defer app_core.arena_owner_destroy(&arena)
    allocator := app_core.arena_owner_allocator(&arena)
    glyphs := [1]app_core.Shaped_Glyph{{glyph_id = 3, x_advance = 1024}}
    testing.expect_value(t, document_shaped_builder_append(
        &builder, prose_shaping_test_append(0, glyphs[:])),
        app_core.Bounded_Builder_Status.Ok)
    cache := new(app_core.Dynview_Compile_Cache, allocator)
    generations: [app_core.FONT_KEY_COUNT]u64
    generations[int(app_core.Font_Key.Regular)] = 7

    status := document_shaped_builder_seal(
        &builder, cache, 1, 1, generations[:])

    testing.expect_value(t, status, app_core.Bounded_Builder_Status.Ok)
    testing.expect_value(t, len(cache^.document_shaped_runs), 1)
    testing.expect_value(t, len(cache^.document_shaped_glyphs), 1)
    testing.expect_value(t, cache^.document_shaped_runs[0].glyph_count, 1)
}

// Verify publication rejects a run measured against a stale effective generation.
@(test)
document_prose_shaping_rejects_stale_generation :: proc(t: ^testing.T) {
    arena: app_core.Arena_Owner
    builder := prose_shaping_test_builder(t, &arena)
    defer app_core.arena_owner_destroy(&arena)
    allocator := app_core.arena_owner_allocator(&arena)
    glyphs := [1]app_core.Shaped_Glyph{{glyph_id = 3}}
    _ = document_shaped_builder_append(
        &builder, prose_shaping_test_append(0, glyphs[:]))
    cache := new(app_core.Dynview_Compile_Cache, allocator)
    generations: [app_core.FONT_KEY_COUNT]u64
    generations[int(app_core.Font_Key.Regular)] = 8

    status := document_shaped_builder_seal(
        &builder, cache, 1, 1, generations[:])

    testing.expect_value(t, status, app_core.Bounded_Builder_Status.Invalid_Argument)
    testing.expect_value(t, len(cache^.document_shaped_runs), 0)
}

// Verify glyph admission fails transactionally at the fixed prose capacity.
@(test)
document_prose_shaping_rejects_glyph_overflow :: proc(t: ^testing.T) {
    arena: app_core.Arena_Owner
    builder := prose_shaping_test_builder(t, &arena)
    defer app_core.arena_owner_destroy(&arena)
    builder.glyphs.count = app_core.DYNVIEW_MAX_DOCUMENT_SHAPED_GLYPHS
    glyphs := [1]app_core.Shaped_Glyph{{glyph_id = 3}}

    status := document_shaped_builder_append(
        &builder, prose_shaping_test_append(0, glyphs[:]))

    testing.expect_value(t, status, app_core.Bounded_Builder_Status.Limit_Exceeded)
    testing.expect_value(t, builder.runs.count, 0)
}

// Verify run admission fails transactionally at the fixed prose capacity.
@(test)
document_prose_shaping_rejects_run_overflow :: proc(t: ^testing.T) {
    arena: app_core.Arena_Owner
    builder := prose_shaping_test_builder(t, &arena)
    defer app_core.arena_owner_destroy(&arena)
    builder.runs.count = app_core.DYNVIEW_MAX_DOCUMENT_SHAPED_RUNS
    glyphs := [1]app_core.Shaped_Glyph{{glyph_id = 3}}

    status := document_shaped_builder_append(
        &builder, prose_shaping_test_append(0, glyphs[:]))

    testing.expect_value(t, status, app_core.Bounded_Builder_Status.Limit_Exceeded)
    testing.expect_value(t, builder.glyphs.count, 0)
}

// Verify text, spaces, clusters, and requested variants survive deterministic rebuilds.
@(test)
document_prose_shaping_measures_semantic_inlines_deterministically :: proc(
    t: ^testing.T) {

    runtime_arena, cache_arena: app_core.Arena_Owner
    testing.expect(t, app_core.arena_owner_init(&runtime_arena))
    testing.expect(t, app_core.arena_owner_init(&cache_arena))
    defer app_core.arena_owner_destroy(&runtime_arena)
    defer app_core.arena_owner_destroy(&cache_arena)
    runtime_allocator := app_core.arena_owner_allocator(&runtime_arena)
    runtime := new(app_core.Dynview_System, runtime_allocator)
    fixture: Prose_Shaping_Rebuild_Fixture
    service := prose_shaping_rebuild_fixture_init(runtime, &fixture)

    first_status := rebuild_document_shaped_cache(runtime, &cache_arena, service)
    first_runs := [3]app_core.Dynview_Document_Shaped_Run{}
    first_glyphs := [3]app_core.Shaped_Glyph{}
    copy(first_runs[:], runtime^.compile_cache.document_shaped_runs)
    copy(first_glyphs[:], runtime^.compile_cache.document_shaped_glyphs)
    app_core.arena_owner_reset(&cache_arena)
    second_status := rebuild_document_shaped_cache(runtime, &cache_arena, service)

    testing.expect_value(t, first_status, app_core.Bounded_Builder_Status.Ok)
    testing.expect_value(t, second_status, app_core.Bounded_Builder_Status.Ok)
    for index in 0..<3 {
        testing.expect_value(t,
            runtime^.compile_cache.document_shaped_runs[index], first_runs[index])
        testing.expect_value(t,
            runtime^.compile_cache.document_shaped_glyphs[index], first_glyphs[index])
    }
    testing.expect_value(t, first_runs[1].width, f32(1))
    testing.expect_value(t, first_glyphs[1].cluster, u32(0))
    testing.expect_value(t, first_runs[2].requested_font_key, app_core.Font_Key.Bold)
    testing.expect_value(t, first_runs[2].effective_font_key, app_core.Font_Key.Bold)
    testing.expect_value(t, first_runs[2].font_generation, u64(11))
}

// Verify clusters outside an inline's source byte span are rejected.
@(test)
document_prose_shaping_rejects_invalid_cluster :: proc(t: ^testing.T) {
    glyphs := [1]app_core.Shaped_Glyph{{glyph_id = 2, cluster = 1}}
    testing.expect(t, !document_shaped_clusters_are_valid(glyphs[:], 1))
}