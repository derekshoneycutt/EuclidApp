package font

import "../../core"

import stbtt "vendor:stb/truetype"

import "core:mem"
import "core:os"

// Empty pixels reserved around each glyph during row packing.
FONT_GLYPH_PADDING :: i32(4)

// Opaque white marker dimensions written into the atlas bottom-right corner.
FONT_ATLAS_CORNER_SIZE :: 3

// Caller-owned cancellation query used at bounded font-preparation checkpoints.
Font_Prepare_Cancel_Proc :: #type proc(user_data: rawptr) -> bool

// Optional cooperative cancellation capability borrowed for one preparation call.
Font_Prepare_Cancellation :: struct {
    user_data: rawptr,
    requested: Font_Prepare_Cancel_Proc,
}

// Result of cancellable glyph layout before atlas allocation.
Font_Prepare_Layout_Result :: struct {
    width: i32,
    height: i32,
    ready: bool,
}

// Immutable CPU preparation request; path/codepoints are borrowed for the call/task lifetime.
Font_Prepare_Request :: struct {
    key: Font_Key,
    generation: u64,
    path: string,
    pixel_size: i32,
    codepoints: []rune,
    complete_face: bool,
    cancellation: Font_Prepare_Cancellation,
}

// Immutable subset request whose glyph IDs are borrowed for the preparation call.
Font_Glyph_Page_Request :: struct {
    key: Font_Key,
    generation: u64,
    path: string,
    pixel_size: i32,
    glyph_ids: []u32,
    cancellation: Font_Prepare_Cancellation,
}

Prepared_Font_Allocation_Mode :: core.Prepared_Font_Allocation_Mode
Prepared_Glyph :: core.Prepared_Glyph
Prepared_Rectangle :: core.Prepared_Rectangle
Prepared_Font :: core.Prepared_Font

//   Query an optional caller-owned cancellation capability.
prepare_cancellation_requested :: proc(
    cancellation: Font_Prepare_Cancellation) -> bool {
    return cancellation.requested != nil &&
        cancellation.requested(cancellation.user_data)
}

//   Release every allocation owned by a prepared CPU font result.
//
// Side effects:
//   - Individually deletes slices in `.Individual` mode; arena mode only clears the
//     record because the owning arena performs bulk reclamation.
prepare_destroy :: proc(prepared: ^Prepared_Font) {
    if prepared == nil {
        return
    }
    if prepared.allocation_mode == .Individual {
        delete(prepared.atlas_pixels, prepared.allocator)
        delete(prepared.glyphs, prepared.allocator)
        delete(prepared.rectangles, prepared.allocator)
    }
    prepared^ = {}
}

//   Lay out prepared glyphs and commit stable result metadata.
prepare_commit_layout :: proc(
    request: Font_Prepare_Request, prepared: ^Prepared_Font) -> bool {
    layout := prepare_layout(
        prepared.glyphs, request.pixel_size, prepared.rectangles,
        request.cancellation)
    if !layout.ready {
        return false
    }
    prepared.key = request.key
    prepared.generation = request.generation
    prepared.base_size = request.pixel_size
    prepared.glyph_count = i32(len(prepared.glyphs))
    prepared.padding = FONT_GLYPH_PADDING
    prepared.atlas_width = layout.width
    prepared.atlas_height = layout.height
    return true
}

//   Read one font source and initialize its stb font descriptor.
prepare_open_font :: proc(
    path: string, allocator: mem.Allocator,
    info: ^stbtt.fontinfo) -> ([]u8, bool) {
    file_data, file_error := os.read_entire_file(path, allocator)
    if file_error != nil {
        return nil, false
    }
    if !stbtt.InitFont(info, raw_data(file_data), 0) {
        return file_data, false
    }
    return file_data, true
}

//   Count supported glyphs and allocate their parallel metadata slices.
prepare_allocate_glyph_metadata :: proc(
    info: ^stbtt.fontinfo, request: Font_Prepare_Request,
    prepared: ^Prepared_Font, allocator: mem.Allocator) -> bool {
    if prepare_cancellation_requested(request.cancellation) {
        return false
    }
    glyph_count := int(info.numGlyphs) if request.complete_face else
        prepare_count_glyphs(info, request.codepoints)
    return glyph_count > 0 &&
        prepare_allocate_metadata(prepared, glyph_count, allocator)
}

//   Populate one opened font descriptor into prepared CPU atlas ownership.
prepare_populate :: proc(
    info: ^stbtt.fontinfo, request: Font_Prepare_Request,
    prepared: ^Prepared_Font, allocator: mem.Allocator) -> bool {

    if !prepare_allocate_glyph_metadata(info, request, prepared, allocator) {
        prepare_destroy(prepared)
        return false
    }
    prepared.face_glyph_count = info.numGlyphs
    ascent: i32
    stbtt.GetFontVMetrics(info, &ascent, nil, nil)
    prepared.raster_ascent = f32(ascent) *
        stbtt.ScaleForPixelHeight(info, f32(request.pixel_size))
    metrics_ready := prepare_complete_glyph_metrics(
        info, request, prepared.glyphs) if request.complete_face else
        prepare_glyph_metrics(info, request, prepared.glyphs)
    if !metrics_ready {
        prepare_destroy(prepared)
        return false
    }
    if !prepare_commit_layout(request, prepared) {
        prepare_destroy(prepared)
        return false
    }
    if !prepare_allocate_atlas(prepared, allocator) {
        return false
    }
    if !prepare_render_atlas(info, prepared, request.cancellation) {
        prepare_destroy(prepared)
        return false
    }
    if prepare_cancellation_requested(request.cancellation) {
        prepare_destroy(prepared)
        return false
    }
    return true
}

//   Parse, rasterize, and pack one TrueType font without calling raylib.
//
// Parameters:
//   - request: Valid borrowed source path, positive size, and nonempty codepoint policy.
//   - prepared: Destination reset to owned result state before allocation begins.
//   - allocator: Allocation source retained in the result.
//   - allocation_mode: Slice cleanup policy matching the allocator's lifetime.
//
// Returns:
//   - True for a complete CPU font; false after rollback/clear where required.
//
// Notes:
//   - This worker-safe path performs file I/O and stb rasterization but no raylib calls.
prepare :: proc(
    request: Font_Prepare_Request, prepared: ^Prepared_Font,
    allocator: mem.Allocator,
    allocation_mode := Prepared_Font_Allocation_Mode.Individual) -> bool {

    if prepared == nil || request.pixel_size <= 0 ||
        (!request.complete_face && len(request.codepoints) == 0) {
        return false
    }
    prepared^ = {
        allocator = allocator,
        allocation_mode = allocation_mode,
        complete_face = request.complete_face,
    }
    if prepare_cancellation_requested(request.cancellation) {
        prepare_destroy(prepared)
        return false
    }
    info: stbtt.fontinfo
    file_data, opened := prepare_open_font(request.path, allocator, &info)
    if !opened {
        if file_data != nil && allocation_mode == .Individual {
            delete(file_data, allocator)
        }
        return false
    }
    defer if allocation_mode == .Individual {
        delete(file_data, allocator)
    }
    if prepare_cancellation_requested(request.cancellation) {
        prepare_destroy(prepared)
        return false
    }
    return prepare_populate(&info, request, prepared, allocator)
}

//   Report whether one page request contains unique glyph IDs from this face.
//
// Returns:
//   - True for a nonempty bounded set of unique in-range glyph IDs.
prepare_glyph_page_request_is_valid :: proc(
    info: ^stbtt.fontinfo, glyph_ids: []u32) -> bool {

    if info == nil || len(glyph_ids) == 0 ||
        len(glyph_ids) > FONT_GLYPH_PAGE_REQUEST_CAPACITY {
        return false
    }
    for glyph_id, index in glyph_ids {
        if glyph_id >= u32(info.numGlyphs) {
            return false
        }
        for previous in glyph_ids[:index] {
            if previous == glyph_id {
                return false
            }
        }
    }
    return true
}

//   Populate compact page-local metrics while preserving original face glyph IDs.
prepare_glyph_page_metrics :: proc(
    info: ^stbtt.fontinfo, pixel_size: i32,
    glyph_ids: []u32, glyphs: []Prepared_Glyph,
    cancellation: Font_Prepare_Cancellation) -> bool {

    scale := stbtt.ScaleForPixelHeight(info, f32(pixel_size))
    ascent: i32
    stbtt.GetFontVMetrics(info, &ascent, nil, nil)
    for glyph_id, index in glyph_ids {
        if prepare_cancellation_requested(cancellation) {
            return false
        }
        glyphs[index] = prepare_face_glyph_metric(
            info, i32(glyph_id), scale, ascent)
    }
    return true
}

//   Allocate, lay out, and rasterize one validated glyph page.
prepare_glyph_page_populate :: proc(
    info: ^stbtt.fontinfo, request: Font_Glyph_Page_Request,
    prepared: ^Prepared_Font, allocator: mem.Allocator) -> bool {

    if !prepare_glyph_page_request_is_valid(info, request.glyph_ids) ||
        !prepare_allocate_metadata(prepared, len(request.glyph_ids), allocator) {
        prepare_destroy(prepared)
        return false
    }
    prepared.face_glyph_count = info.numGlyphs
    if !prepare_glyph_page_metrics(
        info, request.pixel_size, request.glyph_ids, prepared.glyphs,
        request.cancellation) || !prepare_commit_layout({
        key = request.key,
        generation = request.generation,
        pixel_size = request.pixel_size,
        cancellation = request.cancellation,
    }, prepared) {
        prepare_destroy(prepared)
        return false
    }
    if !prepare_allocate_atlas(prepared, allocator) {
        return false
    }
    if !prepare_render_atlas(info, prepared, request.cancellation) {
        prepare_destroy(prepared)
        return false
    }
    if prepare_cancellation_requested(request.cancellation) {
        prepare_destroy(prepared)
        return false
    }
    return true
}

//   Parse, rasterize, and pack one bounded glyph-ID subset without raylib calls.
//
// Returns:
//   - True for a complete compact CPU page; false after owned-result rollback.
prepare_glyph_page :: proc(
    request: Font_Glyph_Page_Request, prepared: ^Prepared_Font,
    allocator: mem.Allocator,
    allocation_mode := Prepared_Font_Allocation_Mode.Individual) -> bool {

    if prepared == nil || request.pixel_size <= 0 || len(request.path) == 0 {
        return false
    }
    prepared^ = {
        allocator = allocator,
        allocation_mode = allocation_mode,
    }
    if prepare_cancellation_requested(request.cancellation) {
        prepare_destroy(prepared)
        return false
    }
    info: stbtt.fontinfo
    file_data, opened := prepare_open_font(request.path, allocator, &info)
    if !opened {
        if file_data != nil && allocation_mode == .Individual {
            delete(file_data, allocator)
        }
        return false
    }
    defer if allocation_mode == .Individual {
        delete(file_data, allocator)
    }
    if prepare_cancellation_requested(request.cancellation) {
        prepare_destroy(prepared)
        return false
    }
    return prepare_glyph_page_populate(&info, request, prepared, allocator)
}

//   Allocate prepared metadata while preserving individual-allocation rollback.
//
// Returns:
//   - True after equal-length glyph and rectangle slices are owned by `prepared`.
prepare_allocate_metadata :: proc(
    prepared: ^Prepared_Font, glyph_count: int,
    allocator: mem.Allocator) -> bool {

    glyphs, glyphs_error := make([]Prepared_Glyph, glyph_count, allocator)
    if glyphs_error != nil {
        return false
    }
    prepared.glyphs = glyphs
    rectangles, rectangles_error := make(
        []Prepared_Rectangle, glyph_count, allocator)
    if rectangles_error != nil {
        prepare_destroy(prepared)
        return false
    }
    prepared.rectangles = rectangles
    return true
}

//   Allocate the prepared atlas while preserving individual-allocation rollback.
//
// Returns:
//   - True after allocating exactly `width * height * 2` zeroed bytes.
prepare_allocate_atlas :: proc(
    prepared: ^Prepared_Font, allocator: mem.Allocator) -> bool {

    atlas_size := int(prepared.atlas_width*prepared.atlas_height*2)
    atlas_pixels, atlas_error := make([]u8, atlas_size, allocator)
    if atlas_error != nil {
        prepare_destroy(prepared)
        return false
    }
    prepared.atlas_pixels = atlas_pixels
    return true
}

//   Count requested codepoints represented by real glyphs in the font.
//
// Returns:
//   - Number of codepoints whose stb glyph index is greater than zero.
prepare_count_glyphs :: proc(
    info: ^stbtt.fontinfo, codepoints: []rune) -> int {

    result := 0
    for codepoint in codepoints {
        if stbtt.FindGlyphIndex(info, codepoint) > 0 {
            result += 1
        }
    }
    return result
}

//   Reproduce raylib's stb metrics and synthesized space bitmap dimensions.
//
// Returns:
//   - True when every pre-counted real glyph receives one output record.
prepare_glyph_metrics :: proc(
    info: ^stbtt.fontinfo, request: Font_Prepare_Request,
    glyphs: []Prepared_Glyph) -> bool {

    scale := stbtt.ScaleForPixelHeight(info, f32(request.pixel_size))
    ascent: i32
    descent: i32
    line_gap: i32
    stbtt.GetFontVMetrics(info, &ascent, &descent, &line_gap)
    glyph_index := 0
    for codepoint in request.codepoints {
        if prepare_cancellation_requested(request.cancellation) {
            return false
        }
        if stbtt.FindGlyphIndex(info, codepoint) <= 0 {
            continue
        }
        glyphs[glyph_index] = prepare_glyph_metric(
            info, codepoint, request.pixel_size, scale, ascent)
        glyph_index += 1
    }
    return glyph_index == len(glyphs)
}

//   Populate metrics for every face glyph ID, including missing glyph ID zero.
prepare_complete_glyph_metrics :: proc(
    info: ^stbtt.fontinfo, request: Font_Prepare_Request,
    glyphs: []Prepared_Glyph) -> bool {

    if len(glyphs) != int(info.numGlyphs) {
        return false
    }
    scale := stbtt.ScaleForPixelHeight(info, f32(request.pixel_size))
    ascent: i32
    stbtt.GetFontVMetrics(info, &ascent, nil, nil)
    for &glyph, glyph_index in glyphs {
        if prepare_cancellation_requested(request.cancellation) {
            return false
        }
        glyph = prepare_face_glyph_metric(
            info, i32(glyph_index), scale, ascent)
    }
    for codepoint in request.codepoints {
        if prepare_cancellation_requested(request.cancellation) {
            return false
        }
        glyph_id := stbtt.FindGlyphIndex(info, codepoint)
        if glyph_id > 0 {
            glyphs[glyph_id].value = codepoint
        }
    }
    return true
}

//   Calculate one face glyph's scaled advance, offsets, and bitmap bounds.
prepare_face_glyph_metric :: proc(
    info: ^stbtt.fontinfo, glyph_id: i32,
    scale: f32, ascent: i32) -> Prepared_Glyph {

    advance: i32
    stbtt.GetGlyphHMetrics(info, glyph_id, &advance, nil)
    x0, y0, x1, y1: i32
    stbtt.GetGlyphBitmapBox(
        info, glyph_id, scale, scale, &x0, &y0, &x1, &y1)
    result := Prepared_Glyph{
        value = rune(-1 - glyph_id),
        glyph_id = u32(glyph_id),
        offset_x = x0,
        offset_y = y0,
        advance_x = i32(f32(advance)*scale),
        bitmap_width = x1 - x0,
        bitmap_height = y1 - y0,
    }
    if result.bitmap_width > 0 && result.bitmap_height > 0 {
        result.offset_y += i32(f32(ascent)*scale)
    }
    return result
}

//   Calculate one glyph's raylib-compatible offsets, advance, and bitmap bounds.
//
// Notes:
//   - ASCII and ideographic spaces synthesize empty full-height rectangles using
//     horizontal advance; nonempty glyph offsets are adjusted by scaled ascent.
//
// Returns:
//   - Complete CPU metrics for the requested represented codepoint.
prepare_glyph_metric :: proc(
    info: ^stbtt.fontinfo, codepoint: rune, pixel_size: i32,
    scale: f32, ascent: i32) -> Prepared_Glyph {

    advance: i32
    glyph_id := stbtt.FindGlyphIndex(info, codepoint)
    stbtt.GetGlyphHMetrics(info, glyph_id, &advance, nil)
    result := Prepared_Glyph{
        value = codepoint,
        glyph_id = u32(glyph_id),
    }
    if codepoint == ' ' || codepoint == rune(0x3000) {
        result.advance_x = i32(f32(advance)*scale)
        result.bitmap_width = result.advance_x
        result.bitmap_height = pixel_size
        return result
    }

    x0, y0, x1, y1: i32
    stbtt.GetCodepointBitmapBox(
        info, codepoint, scale, scale, &x0, &y0, &x1, &y1)
    result.offset_x = x0
    result.offset_y = y0
    result.bitmap_width = x1 - x0
    result.bitmap_height = y1 - y0
    if result.bitmap_width > 0 && result.bitmap_height > 0 {
        result.advance_x = i32(f32(advance)*scale)
        result.offset_y += i32(f32(ascent)*scale)
    }
    return result
}

//   Estimate power-of-two atlas dimensions from prepared glyph area.
prepare_initial_atlas_size :: proc(
    glyphs: []Prepared_Glyph,
    pixel_size: i32) -> (i32, i32) {
    total_area := f32(0)
    minimum_width := i32(1)
    for glyph in glyphs {
        padded_width := glyph.bitmap_width + 2*FONT_GLYPH_PADDING
        padded_height := max(glyph.bitmap_height, pixel_size) +
            2*FONT_GLYPH_PADDING
        total_area += f32(padded_width*padded_height)
        minimum_width = max(minimum_width, padded_width)
    }
    atlas_width := i32(1)
    for atlas_width < minimum_width ||
        f32(atlas_width*atlas_width) < total_area*1.2 {
        atlas_width *= 2
    }
    atlas_height := atlas_width
    if total_area < f32(atlas_width*atlas_width/2) {
        atlas_height /= 2
    }
    return atlas_width, atlas_height
}

//   Reproduce raylib's default row packing and atlas growth policy.
//
// Parameters:
//   - glyphs: Prepared metrics to place in order.
//   - pixel_size: Positive base font height used for row spacing.
//   - rectangles: Output parallel to glyphs.
//
// Returns:
//   - Power-of-two atlas width and dynamically doubled height containing every glyph.
prepare_layout :: proc(
    glyphs: []Prepared_Glyph, pixel_size: i32,
    rectangles: []Prepared_Rectangle,
    cancellation: Font_Prepare_Cancellation = {}) -> Font_Prepare_Layout_Result {

    atlas_width, atlas_height := prepare_initial_atlas_size(glyphs, pixel_size)
    offset_x := FONT_GLYPH_PADDING
    offset_y := FONT_GLYPH_PADDING
    row_height := i32(0)
    for glyph, index in glyphs {
        if prepare_cancellation_requested(cancellation) {
            return {}
        }
        if offset_x > FONT_GLYPH_PADDING &&
            offset_x+glyph.bitmap_width+FONT_GLYPH_PADDING > atlas_width {
            offset_x = FONT_GLYPH_PADDING
            offset_y += row_height + 2*FONT_GLYPH_PADDING
            row_height = 0
        }
        for offset_y+glyph.bitmap_height+FONT_GLYPH_PADDING > atlas_height {
            atlas_height *= 2
        }
        rectangles[index] = {
            x = offset_x,
            y = offset_y,
            width = glyph.bitmap_width,
            height = glyph.bitmap_height,
        }
        row_height = max(row_height, glyph.bitmap_height)
        offset_x += glyph.bitmap_width + 2*FONT_GLYPH_PADDING
    }
    return {width = atlas_width, height = atlas_height, ready = true}
}

//   Initialize the atlas gray channel while observing cancellation once per row.
prepare_initialize_atlas :: proc(
    prepared: ^Prepared_Font,
    cancellation: Font_Prepare_Cancellation) -> bool {
    for row in 0..<int(prepared.atlas_height) {
        if prepare_cancellation_requested(cancellation) {
            return false
        }
        for column in 0..<int(prepared.atlas_width) {
            pixel_index := row*int(prepared.atlas_width) + column
            prepared.atlas_pixels[pixel_index*2] = 255
        }
    }
    return true
}

//   Rasterize each nonempty glyph while observing cancellation between glyphs.
prepare_render_glyphs :: proc(
    info: ^stbtt.fontinfo, prepared: ^Prepared_Font,
    cancellation: Font_Prepare_Cancellation) -> bool {
    scale := stbtt.ScaleForPixelHeight(info, f32(prepared.base_size))
    for glyph, index in prepared.glyphs {
        if prepare_cancellation_requested(cancellation) {
            return false
        }
        if glyph.value == ' ' || glyph.value == rune(0x3000) ||
            glyph.bitmap_width == 0 || glyph.bitmap_height == 0 {
            continue
        }
        width, height, offset_x, offset_y: i32
        bitmap := stbtt.GetGlyphBitmap(
            info, scale, scale, i32(glyph.glyph_id), &width, &height,
            &offset_x, &offset_y)
        if bitmap != nil {
            prepare_copy_bitmap(
                bitmap, width, height, prepared.rectangles[index], prepared)
            stbtt.FreeBitmap(bitmap, info.userdata)
        }
    }
    return true
}

//   Mark the atlas validation corner after every glyph is complete.
prepare_mark_atlas_corner :: proc(prepared: ^Prepared_Font) {
    for corner_y in 0..<FONT_ATLAS_CORNER_SIZE {
        for corner_x in 0..<FONT_ATLAS_CORNER_SIZE {
            x := prepared.atlas_width - 1 - i32(corner_x)
            y := prepared.atlas_height - 1 - i32(corner_y)
            prepared.atlas_pixels[
                int((y*prepared.atlas_width + x)*2 + 1)] = 255
        }
    }
}

//   Rasterize glyph alpha into the packed two-channel atlas and add its white corner.
//
// Side effects:
//   - Sets every gray channel byte to 255, writes non-space stb bitmap coverage into
//     alpha, and marks the bottom-right corner opaque for downstream validation.
prepare_render_atlas :: proc(
    info: ^stbtt.fontinfo, prepared: ^Prepared_Font,
    cancellation: Font_Prepare_Cancellation = {}) -> bool {
    if !prepare_initialize_atlas(prepared, cancellation) ||
        !prepare_render_glyphs(info, prepared, cancellation) {
        return false
    }
    prepare_mark_atlas_corner(prepared)
    return true
}

//   Copy one grayscale stb bitmap into the atlas alpha channel.
//
// Side effects:
//   - Copies only pixels whose rectangle-derived destination lies inside atlas bounds.
prepare_copy_bitmap :: proc(
    bitmap: [^]u8, width, height: i32, rectangle: Prepared_Rectangle,
    prepared: ^Prepared_Font) {

    for y in 0..<height {
        for x in 0..<width {
            destination_x := rectangle.x + x
            destination_y := rectangle.y + y
            if destination_x >= 0 && destination_x < prepared.atlas_width &&
                destination_y >= 0 && destination_y < prepared.atlas_height {
                source_index := y*width + x
                destination_index :=
                    (destination_y*prepared.atlas_width + destination_x)*2 + 1
                prepared.atlas_pixels[int(destination_index)] = bitmap[source_index]
            }
        }
    }
}
