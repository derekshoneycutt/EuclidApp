package font

import "../../core"

import "core:c"

when ODIN_OS == .Windows {
    foreign import harfbuzz "system:harfbuzz.lib"
} else {
    foreign import harfbuzz "system:harfbuzz"
}

// Opaque HarfBuzz font-data storage referenced by a face.
Harfbuzz_Blob :: struct {}

// Opaque HarfBuzz view of one font face within a blob.
Harfbuzz_Face :: struct {}

// Opaque HarfBuzz shaping font configured with OpenType behavior and pixel scale.
Harfbuzz_Font :: struct {}

// Opaque reusable HarfBuzz input and shaped-output buffer.
Harfbuzz_Buffer :: struct {}

// HarfBuzz buffer direction values used by explicit math shaping setup.
Harfbuzz_Direction :: enum c.int {
    Invalid = 0,
    Left_To_Right = 4,
    Right_To_Left = 5,
    Top_To_Bottom = 6,
    Bottom_To_Top = 7,
}

// OpenType MATH glyph-kern table corners in HarfBuzz ABI order.
Harfbuzz_Math_Kern :: enum c.int {
    Top_Right = 0,
    Top_Left = 1,
    Bottom_Right = 2,
    Bottom_Left = 3,
}

// HarfBuzz policy controlling whether a blob copies or borrows source bytes.
Harfbuzz_Memory_Mode :: enum c.int {
    Duplicate = 0,
    Readonly = 1,
    Writable = 2,
    Readonly_May_Make_Writable = 3,
}

// ABI-compatible OpenType feature selection over a source byte interval.
Harfbuzz_Feature :: struct {
    tag: u32,
    value: u32,
    start: u32,
    end: u32,
}

// ABI-compatible HarfBuzz glyph identity and source-cluster record.
Harfbuzz_Glyph_Info :: struct {
    codepoint: u32,
    mask: u32,
    cluster: u32,
    private_a: u32,
    private_b: u32,
}

// ABI-compatible HarfBuzz glyph advances and offsets in configured font units.
Harfbuzz_Glyph_Position :: struct {
    x_advance: i32,
    y_advance: i32,
    x_offset: i32,
    y_offset: i32,
    private: i32,
}

// ABI-compatible HarfBuzz glyph ink extents in configured 26.6 units.
Harfbuzz_Glyph_Extents :: struct {
    x_bearing: i32,
    y_bearing: i32,
    width: i32,
    height: i32,
}

// ABI-compatible OpenType MATH glyph variant and vertical advance record.
Harfbuzz_Math_Glyph_Variant :: struct {
    glyph: u32,
    advance: i32,
}

// ABI-compatible OpenType MATH glyph assembly part.
Harfbuzz_Math_Glyph_Part :: struct {
    glyph: u32,
    start_connector_length: i32,
    end_connector_length: i32,
    full_advance: i32,
    flags: u32,
}

// ABI-compatible height boundary and value from one MATH kern table.
Harfbuzz_Math_Kern_Entry :: struct {
    max_correction_height: i32,
    kern_value: i32,
}

// Math_Variant_Query_Result reports one bounded native variant query outcome.
Math_Variant_Query_Result :: struct {
    count: int,
    extended_shape: bool,
    ok: bool,
}

// Math_Assembly_Query_Result reports one bounded native assembly query outcome.
Math_Assembly_Query_Result :: struct {
    count: int,
    min_connector_overlap: i32,
    italic_correction: i32,
    ok: bool,
}

// Math_Kern_Query_Result reports one bounded native corner-table query outcome.
Math_Kern_Query_Result :: struct {
    count: int,
    ok: bool,
}

Shaped_Glyph :: core.Shaped_Glyph
Font_Shaping_Resource :: core.Font_Shaping_Resource
Font_Math_Shaping_Capability :: core.Font_Math_Shaping_Capability
Font_Math_Constants :: core.Font_Math_Constants
Font_Glyph_Extents :: core.Font_Glyph_Extents

// Harfbuzz_Math_Constant mirrors hb_ot_math_constant_t values 0 through 55.
Harfbuzz_Math_Constant :: enum c.int {
    Script_Percent_Scale_Down = 0,
    Script_Script_Percent_Scale_Down,
    Delimited_Sub_Formula_Min_Height,
    Display_Operator_Min_Height,
    Math_Leading,
    Axis_Height,
    Accent_Base_Height,
    Flattened_Accent_Base_Height,
    Subscript_Shift_Down,
    Subscript_Top_Max,
    Subscript_Baseline_Drop_Min,
    Superscript_Shift_Up,
    Superscript_Shift_Up_Cramped,
    Superscript_Bottom_Min,
    Superscript_Baseline_Drop_Max,
    Sub_Superscript_Gap_Min,
    Superscript_Bottom_Max_With_Subscript,
    Space_After_Script,
    Upper_Limit_Gap_Min,
    Upper_Limit_Baseline_Rise_Min,
    Lower_Limit_Gap_Min,
    Lower_Limit_Baseline_Drop_Min,
    Stack_Top_Shift_Up,
    Stack_Top_Display_Style_Shift_Up,
    Stack_Bottom_Shift_Down,
    Stack_Bottom_Display_Style_Shift_Down,
    Stack_Gap_Min,
    Stack_Display_Style_Gap_Min,
    Stretch_Stack_Top_Shift_Up,
    Stretch_Stack_Bottom_Shift_Down,
    Stretch_Stack_Gap_Above_Min,
    Stretch_Stack_Gap_Below_Min,
    Fraction_Numerator_Shift_Up,
    Fraction_Numerator_Display_Style_Shift_Up,
    Fraction_Denominator_Shift_Down,
    Fraction_Denominator_Display_Style_Shift_Down,
    Fraction_Numerator_Gap_Min,
    Fraction_Num_Display_Style_Gap_Min,
    Fraction_Rule_Thickness,
    Fraction_Denominator_Gap_Min,
    Fraction_Denom_Display_Style_Gap_Min,
    Skewed_Fraction_Horizontal_Gap,
    Skewed_Fraction_Vertical_Gap,
    Overbar_Vertical_Gap,
    Overbar_Rule_Thickness,
    Overbar_Extra_Ascender,
    Underbar_Vertical_Gap,
    Underbar_Rule_Thickness,
    Underbar_Extra_Descender,
    Radical_Vertical_Gap,
    Radical_Display_Style_Vertical_Gap,
    Radical_Rule_Thickness,
    Radical_Extra_Ascender,
    Radical_Kern_Before_Degree,
    Radical_Kern_After_Degree,
    Radical_Degree_Bottom_Raise_Percent,
}

Math_Shaping_Role :: enum {
    Upright,
    Italic,
}

Math_Projection_Decode_Result :: struct {
    value: rune,
    width: int,
    valid: bool,
}

Math_Shaping_Input :: struct {
    text: string,
    role: Math_Shaping_Role,
    standalone_accent: bool,
    flattened_accent: bool,
    workspace: []u8,
}

foreign harfbuzz {
    hb_blob_create :: proc(
        data: rawptr, length: u32, mode: Harfbuzz_Memory_Mode,
        user_data, destroy: rawptr) -> ^Harfbuzz_Blob ---
    hb_blob_destroy :: proc(blob: ^Harfbuzz_Blob) ---
    hb_blob_get_length :: proc(blob: ^Harfbuzz_Blob) -> u32 ---
    hb_face_create :: proc(blob: ^Harfbuzz_Blob, index: u32) -> ^Harfbuzz_Face ---
    hb_face_destroy :: proc(face: ^Harfbuzz_Face) ---
    hb_face_get_glyph_count :: proc(face: ^Harfbuzz_Face) -> u32 ---
    hb_face_reference_table :: proc(
        face: ^Harfbuzz_Face, tag: u32) -> ^Harfbuzz_Blob ---
    hb_font_create :: proc(face: ^Harfbuzz_Face) -> ^Harfbuzz_Font ---
    hb_font_destroy :: proc(font: ^Harfbuzz_Font) ---
    hb_font_set_scale :: proc(font: ^Harfbuzz_Font, x_scale, y_scale: i32) ---
    hb_font_get_nominal_glyph :: proc(
        font: ^Harfbuzz_Font, unicode: u32, glyph: ^u32) -> c.int ---
    hb_font_get_glyph_extents :: proc(
        font: ^Harfbuzz_Font, glyph: u32,
        extents: ^Harfbuzz_Glyph_Extents) -> c.int ---
    hb_ot_font_set_funcs :: proc(font: ^Harfbuzz_Font) ---
    hb_buffer_create :: proc() -> ^Harfbuzz_Buffer ---
    hb_buffer_destroy :: proc(buffer: ^Harfbuzz_Buffer) ---
    hb_buffer_pre_allocate :: proc(buffer: ^Harfbuzz_Buffer, size: u32) -> c.int ---
    hb_buffer_clear_contents :: proc(buffer: ^Harfbuzz_Buffer) ---
    hb_buffer_set_direction :: proc(
        buffer: ^Harfbuzz_Buffer, direction: Harfbuzz_Direction) ---
    hb_buffer_set_flags :: proc(buffer: ^Harfbuzz_Buffer, flags: u32) ---
    hb_buffer_get_direction :: proc(
        buffer: ^Harfbuzz_Buffer) -> Harfbuzz_Direction ---
    hb_buffer_set_script :: proc(buffer: ^Harfbuzz_Buffer, script: u32) ---
    hb_buffer_get_script :: proc(buffer: ^Harfbuzz_Buffer) -> u32 ---
    hb_buffer_add_utf8 :: proc(
        buffer: ^Harfbuzz_Buffer, text: cstring, text_length: c.int,
        item_offset: u32, item_length: c.int) ---
    hb_buffer_guess_segment_properties :: proc(buffer: ^Harfbuzz_Buffer) ---
    hb_buffer_get_length :: proc(buffer: ^Harfbuzz_Buffer) -> u32 ---
    hb_buffer_get_glyph_infos :: proc(
        buffer: ^Harfbuzz_Buffer, length: ^u32) -> [^]Harfbuzz_Glyph_Info ---
    hb_buffer_get_glyph_positions :: proc(
        buffer: ^Harfbuzz_Buffer,
        length: ^u32) -> [^]Harfbuzz_Glyph_Position ---
    hb_shape :: proc(
        font: ^Harfbuzz_Font, buffer: ^Harfbuzz_Buffer,
        features: [^]Harfbuzz_Feature, feature_count: u32) ---
    hb_ot_math_get_glyph_italics_correction :: proc(
        font: ^Harfbuzz_Font, glyph: u32) -> i32 ---
    hb_ot_math_get_glyph_top_accent_attachment :: proc(
        font: ^Harfbuzz_Font, glyph: u32) -> i32 ---
    hb_ot_math_get_glyph_kerning :: proc(
        font: ^Harfbuzz_Font, glyph: u32,
        corner: Harfbuzz_Math_Kern, correction_height: i32) -> i32 ---
    hb_ot_math_get_glyph_kernings :: proc(
        font: ^Harfbuzz_Font, glyph: u32, corner: Harfbuzz_Math_Kern,
        start_offset: u32, entries_count: ^u32,
        entries: [^]Harfbuzz_Math_Kern_Entry) -> u32 ---
    hb_ot_math_get_constant :: proc(
        font: ^Harfbuzz_Font, constant: Harfbuzz_Math_Constant) -> i32 ---
    hb_ot_math_get_glyph_variants :: proc(
        font: ^Harfbuzz_Font, glyph: u32, direction: Harfbuzz_Direction,
        start_offset: u32, variants_count: ^u32,
        variants: [^]Harfbuzz_Math_Glyph_Variant) -> u32 ---
    hb_ot_math_get_min_connector_overlap :: proc(
        font: ^Harfbuzz_Font, direction: Harfbuzz_Direction) -> i32 ---
    hb_ot_math_get_glyph_assembly :: proc(
        font: ^Harfbuzz_Font, glyph: u32, direction: Harfbuzz_Direction,
        start_offset: u32, parts_count: ^u32, parts: [^]Harfbuzz_Math_Glyph_Part,
        italic_correction: ^i32) -> u32 ---
    hb_ot_math_is_glyph_extended_shape :: proc(
        face: ^Harfbuzz_Face, glyph: u32) -> c.int ---
}

//   Measure one face's lowercase ink height in its configured 26.6 pixel units.
//
// Notes:
//   - Uses the ink extent of `x`, which is what `Scale=MatchLowercase` compares.
harfbuzz_lowercase_ink_height :: proc(shaper: ^Font_Shaping_Resource) -> (f32, bool) {
    if shaper == nil || shaper.font == nil {
        return 0, false
    }
    font := cast(^Harfbuzz_Font)shaper.font
    glyph: u32
    if hb_font_get_nominal_glyph(font, 'x', &glyph) == 0 {
        return 0, false
    }
    extents: Harfbuzz_Glyph_Extents
    if hb_font_get_glyph_extents(font, glyph, &extents) == 0 {
        return 0, false
    }
    height := f32(abs(extents.height))
    return height, height > 0
}

//   Resolve the optical scale matching a math face's lowercase height to the text face.
//
// Returns:
//   - The ratio to apply to the math root size, or one when either face is unmeasurable.
harfbuzz_text_match_scale :: proc(text, math_face: ^Font_Shaping_Resource) -> f32 {
    text_height, text_ok := harfbuzz_lowercase_ink_height(text)
    math_height, math_ok := harfbuzz_lowercase_ink_height(math_face)
    if !text_ok || !math_ok {
        return 1
    }
    return text_height / math_height
}

//   Capture all OpenType MATH constants for one initialized capability generation.
harfbuzz_math_constants_capture :: proc(
    shaper: ^Font_Shaping_Resource,
    generation: u64,
    base_pixel_size: f32,
    output: ^Font_Math_Constants,
    text_match_scale: f32 = 1) -> bool {

    if shaper == nil || shaper.font == nil || generation == 0 ||
        base_pixel_size <= 0 || output == nil || text_match_scale <= 0 {
        return false
    }
    candidate := Font_Math_Constants{
        generation = generation,
        base_pixel_size = base_pixel_size,
        text_match_scale = text_match_scale,
    }
    for constant in Harfbuzz_Math_Constant {
        candidate.values[int(constant)] = hb_ot_math_get_constant(
            cast(^Harfbuzz_Font)shaper.font, constant)
    }
    candidate.valid = true
    output^ = candidate
    return true
}

//   Pack four ASCII bytes into HarfBuzz's canonical OpenType tag order.
//
// Parameters:
//   - a, b, c, d: Tag bytes ordered from most to least significant.
//
// Returns:
//   - One 32-bit OpenType tag suitable for `Harfbuzz_Feature.tag`.
harfbuzz_tag :: proc(a, b, c, d: u8) -> u32 {
    return u32(a) << 24 | u32(b) << 16 | u32(c) << 8 | u32(d)
}

//   Report whether one initialized face exposes a nonempty OpenType MATH table.
harfbuzz_face_has_math_table :: proc(shaper: ^Font_Shaping_Resource) -> bool {
    if shaper == nil || shaper.face == nil {
        return false
    }
    table := hb_face_reference_table(
        cast(^Harfbuzz_Face)shaper.face, harfbuzz_tag('M', 'A', 'T', 'H'))
    if table == nil {
        return false
    }
    defer hb_blob_destroy(table)
    return hb_blob_get_length(table) > 0
}

//   Release every native handle owned by one shaper in reverse acquisition order.
//
// Parameters:
//   - shaper: Native shaping state to release; nil and zero values are accepted.
//
// Side effects:
//   - Releases the buffer, font, face, and blob references owned by `shaper`.
//   - Clears the complete destination so repeated destruction is safe.
//
// Notes:
//   - Releases the blob's duplicated source bytes.
harfbuzz_shaper_destroy :: proc(shaper: ^Font_Shaping_Resource) {
    if shaper == nil {
        return
    }
    if shaper.buffer != nil {
        hb_buffer_destroy(cast(^Harfbuzz_Buffer)shaper.buffer)
    }
    if shaper.font != nil {
        hb_font_destroy(cast(^Harfbuzz_Font)shaper.font)
    }
    if shaper.face != nil {
        hb_face_destroy(cast(^Harfbuzz_Face)shaper.face)
    }
    if shaper.blob != nil {
        hb_blob_destroy(cast(^Harfbuzz_Blob)shaper.blob)
    }
    shaper^ = {}
}

//   Configure font behavior and acquire the reusable shaping buffer.
harfbuzz_shaper_finish_init :: proc(
    shaper: ^Font_Shaping_Resource, pixel_size: i32) -> bool {

    hb_ot_font_set_funcs(cast(^Harfbuzz_Font)shaper.font)
    hb_font_set_scale(
        cast(^Harfbuzz_Font)shaper.font, pixel_size*64, pixel_size*64)
    shaper.buffer = hb_buffer_create()
    if shaper.buffer == nil || hb_buffer_pre_allocate(
        cast(^Harfbuzz_Buffer)shaper.buffer,
        u32(core.FONT_SHAPED_GLYPH_CAPACITY)) == 0 {
        harfbuzz_shaper_destroy(shaper)
        return false
    }
    return true
}

//   Acquire one reusable shaper for a single immutable font face.
//
// Parameters:
//   - source: Nonempty font bytes copied during this call.
//   - pixel_size: Positive raster source height; converted to HarfBuzz 26.6 units.
//   - shaper: Destination replaced with initialized native ownership on success.
//
// Returns:
//   - True when all native handles and OpenType font behavior are initialized.
//   - False for invalid input, a malformed face, or any native acquisition failure.
//
// Side effects:
//   - Clears `shaper` before acquisition and rolls back partial ownership on failure.
//
// Notes:
//   - The blob duplicates `source`; caller storage may be released after this call.
harfbuzz_shaper_init :: proc(
    source: []u8, pixel_size: i32, shaper: ^Font_Shaping_Resource) -> bool {

    if shaper == nil || len(source) == 0 || len(source) > int(max(u32)) ||
        pixel_size <= 0 || pixel_size > max(i32)/64 {
        return false
    }
    shaper^ = {}
    shaper.blob = hb_blob_create(
        raw_data(source), u32(len(source)), .Duplicate, nil, nil)
    if shaper.blob == nil {
        return false
    }
    shaper.face = hb_face_create(cast(^Harfbuzz_Blob)shaper.blob, 0)
    if shaper.face == nil ||
        hb_face_get_glyph_count(cast(^Harfbuzz_Face)shaper.face) == 0 {
        harfbuzz_shaper_destroy(shaper)
        return false
    }
    shaper.font = hb_font_create(cast(^Harfbuzz_Face)shaper.face)
    if shaper.font == nil {
        harfbuzz_shaper_destroy(shaper)
        return false
    }
    return harfbuzz_shaper_finish_init(shaper, pixel_size)
}

//   Resolve one valid Unicode scalar through the immutable face cmap.
//
// Returns:
//   - Face glyph ID and true when the resident font defines the codepoint.
//   - Zero and false for invalid scalars, missing mappings, or invalid state.
harfbuzz_nominal_glyph :: proc(
    shaper: ^Font_Shaping_Resource, codepoint: rune) -> (u32, bool) {

    scalar := u32(codepoint)
    if shaper == nil || shaper.font == nil || scalar > 0x10ffff ||
        scalar >= 0xd800 && scalar <= 0xdfff {
        return 0, false
    }
    glyph_id: u32
    found := hb_font_get_nominal_glyph(
        cast(^Harfbuzz_Font)shaper.font, scalar, &glyph_id)
    return glyph_id, found != 0 && glyph_id != 0
}

// Query one initialized face glyph's ink extents in configured 26.6 pixel units.
harfbuzz_glyph_extents :: proc(
    shaper: ^Font_Shaping_Resource,
    glyph_id: u32) -> (Font_Glyph_Extents, bool) {

    if shaper == nil || shaper.face == nil || shaper.font == nil || glyph_id == 0 ||
        glyph_id >= hb_face_get_glyph_count(cast(^Harfbuzz_Face)shaper.face) {
        return {}, false
    }
    native: Harfbuzz_Glyph_Extents
    found := hb_font_get_glyph_extents(
        cast(^Harfbuzz_Font)shaper.font, glyph_id, &native)
    return {
        x_bearing = native.x_bearing,
        y_bearing = native.y_bearing,
        width = native.width,
        height = native.height,
    }, found != 0
}

//   Report whether one capability is ready for an exact resident generation.
math_shaping_generation_matches :: proc(
    capability: ^Font_Math_Shaping_Capability,
    generation: u64) -> bool {

    return capability != nil && generation != 0 &&
        capability.generation == generation &&
        capability.resource.face != nil && capability.resource.font != nil &&
        capability.resource.buffer != nil
}

//   Release one worker-owned math capability and clear its generation identity.
math_shaping_destroy :: proc(capability: ^Font_Math_Shaping_Capability) {
    if capability == nil {
        return
    }
    harfbuzz_shaper_destroy(&capability.resource)
    capability^ = {}
}

//   Report whether a glyph identity belongs to the capability's immutable face.
math_shaping_has_glyph :: proc(
    capability: ^Font_Math_Shaping_Capability, glyph_id: u32) -> bool {

    if capability == nil || capability.resource.face == nil || glyph_id == 0 {
        return false
    }
    glyph_count := hb_face_get_glyph_count(
        cast(^Harfbuzz_Face)capability.resource.face)
    return glyph_id < glyph_count
}

//   Query one math glyph's ink extents in configured 26.6 pixel units.
math_shaping_glyph_extents :: proc(
    capability: ^Font_Math_Shaping_Capability, generation: u64,
    glyph_id: u32) -> (Font_Glyph_Extents, bool) {

    if !math_shaping_generation_matches(capability, generation) ||
        !math_shaping_has_glyph(capability, glyph_id) {
        return {}, false
    }
    return harfbuzz_glyph_extents(&capability.resource, glyph_id)
}

//   Query one math glyph's italic correction in configured 26.6 pixel units.
math_shaping_italic_correction :: proc(
    capability: ^Font_Math_Shaping_Capability, generation: u64,
    glyph_id: u32) -> (i32, bool) {

    if !math_shaping_generation_matches(capability, generation) ||
        !math_shaping_has_glyph(capability, glyph_id) {
        return 0, false
    }
    value := hb_ot_math_get_glyph_italics_correction(
        cast(^Harfbuzz_Font)capability.resource.font, glyph_id)
    return value, true
}

//   Query one math glyph's top-accent attachment in configured 26.6 pixel units.
math_shaping_top_accent_attachment :: proc(
    capability: ^Font_Math_Shaping_Capability, generation: u64,
    glyph_id: u32) -> (i32, bool) {

    if !math_shaping_generation_matches(capability, generation) ||
        !math_shaping_has_glyph(capability, glyph_id) {
        return 0, false
    }
    value := hb_ot_math_get_glyph_top_accent_attachment(
        cast(^Harfbuzz_Font)capability.resource.font, glyph_id)
    return value, true
}

//   Query one glyph's MATH kern at a validated corner and correction height.
math_shaping_glyph_kerning :: proc(
    capability: ^Font_Math_Shaping_Capability,
    generation: u64,
    glyph_id: u32,
    corner: Harfbuzz_Math_Kern,
    correction_height: i32) -> (i32, bool) {

    if !math_shaping_generation_matches(capability, generation) ||
        !math_shaping_has_glyph(capability, glyph_id) ||
        corner < .Top_Right || corner > .Bottom_Left {
        return 0, false
    }
    value := hb_ot_math_get_glyph_kerning(
        cast(^Harfbuzz_Font)capability.resource.font,
        glyph_id, corner, correction_height)
    return value, true
}

//   Validate and copy one complete native MATH kern table.
math_shaping_copy_kern_table :: proc(
    font: ^Harfbuzz_Font,
    glyph_id: u32,
    corner: Harfbuzz_Math_Kern,
    native: []Harfbuzz_Math_Kern_Entry,
    output: []core.Font_Math_Kern_Entry) -> bool {

    previous_height: i32
    for entry, index in native {
        if index > 0 && entry.max_correction_height <= previous_height {
            return false
        }
        direct := hb_ot_math_get_glyph_kerning(
            font, glyph_id, corner, entry.max_correction_height)
        if direct != entry.kern_value {
            return false
        }
        output[index] = {entry.max_correction_height, entry.kern_value}
        previous_height = entry.max_correction_height
    }
    for index in 0..<len(native)-1 {
        next_height := native[index].max_correction_height + 1
        next_direct := hb_ot_math_get_glyph_kerning(
            font, glyph_id, corner, next_height)
        if next_direct != native[index+1].kern_value {
            return false
        }
    }
    return true
}

//   Copy one glyph corner's complete MATH kern table into bounded caller storage.
math_shaping_glyph_kern_table :: proc(
    capability: ^Font_Math_Shaping_Capability,
    generation: u64,
    glyph_id: u32,
    corner: Harfbuzz_Math_Kern,
    output: []core.Font_Math_Kern_Entry) -> Math_Kern_Query_Result {

    if !math_shaping_generation_matches(capability, generation) ||
        !math_shaping_has_glyph(capability, glyph_id) ||
        corner < .Top_Right || corner > .Bottom_Left || len(output) <= 0 ||
        len(output) > core.FONT_MATH_KERN_ENTRY_CAPACITY {
        return {}
    }
    native: [core.FONT_MATH_KERN_ENTRY_CAPACITY]Harfbuzz_Math_Kern_Entry
    count := u32(len(output))
    available := hb_ot_math_get_glyph_kernings(
        cast(^Harfbuzz_Font)capability.resource.font,
        glyph_id, corner, 0, &count, &native[0])
    if available > u32(len(output)) || count != available {
        return {}
    }
    font := cast(^Harfbuzz_Font)capability.resource.font
    if !math_shaping_copy_kern_table(
        font, glyph_id, corner, native[:count], output) {
        return {}
    }
    return {int(count), true}
}

//   Copy one glyph's directional MATH variants into caller-owned bounded storage.
math_shaping_directional_variants :: proc(
    capability: ^Font_Math_Shaping_Capability,
    generation: u64,
    glyph_id: u32,
    direction: Harfbuzz_Direction,
    output: []core.Font_Math_Glyph_Variant) -> Math_Variant_Query_Result {

    if !math_shaping_generation_matches(capability, generation) ||
        !math_shaping_has_glyph(capability, glyph_id) || len(output) <= 0 ||
        len(output) > core.FONT_MATH_GLYPH_VARIANT_CAPACITY {
        return {}
    }
    native: [core.FONT_MATH_GLYPH_VARIANT_CAPACITY]Harfbuzz_Math_Glyph_Variant
    count := u32(len(output))
    available := hb_ot_math_get_glyph_variants(
        cast(^Harfbuzz_Font)capability.resource.font, glyph_id, direction,
        0, &count, &native[0])
    if count == 0 || int(count) > len(output) || available < count {
        return {}
    }
    for index in 0..<int(count) {
        output[index] = {
            glyph_id = native[index].glyph,
            advance = native[index].advance,
        }
    }
    extended := hb_ot_math_is_glyph_extended_shape(
        cast(^Harfbuzz_Face)capability.resource.face, glyph_id) != 0
    return {int(count), extended, true}
}

//   Copy one glyph's vertical MATH variants into caller-owned bounded storage.
math_shaping_vertical_variants :: proc(
    capability: ^Font_Math_Shaping_Capability,
    generation: u64,
    glyph_id: u32,
    output: []core.Font_Math_Glyph_Variant) -> Math_Variant_Query_Result {

    return math_shaping_directional_variants(
        capability, generation, glyph_id, .Top_To_Bottom, output)
}

//   Copy one glyph's horizontal MATH variants into caller-owned bounded storage.
math_shaping_horizontal_variants :: proc(
    capability: ^Font_Math_Shaping_Capability,
    generation: u64,
    glyph_id: u32,
    output: []core.Font_Math_Glyph_Variant) -> Math_Variant_Query_Result {

    return math_shaping_directional_variants(
        capability, generation, glyph_id, .Left_To_Right, output)
}

//   Validate and copy native assembly parts into bounded application records.
math_shaping_copy_assembly_parts :: proc(
    native: []Harfbuzz_Math_Glyph_Part,
    output: []core.Font_Math_Glyph_Part) -> bool {

    for part, index in native {
        if part.glyph == 0 || part.full_advance <= 0 ||
            part.start_connector_length < 0 || part.end_connector_length < 0 {
            return false
        }
        output[index] = {
            glyph_id = part.glyph,
            start_connector_length = part.start_connector_length,
            end_connector_length = part.end_connector_length,
            full_advance = part.full_advance,
            extender = part.flags & 1 != 0,
        }
    }
    return true
}

//   Copy one glyph's directional MATH assembly into caller-owned bounded storage.
math_shaping_directional_assembly :: proc(
    capability: ^Font_Math_Shaping_Capability,
    generation: u64,
    glyph_id: u32,
    direction: Harfbuzz_Direction,
    output: []core.Font_Math_Glyph_Part) -> Math_Assembly_Query_Result {

    if !math_shaping_generation_matches(capability, generation) ||
        !math_shaping_has_glyph(capability, glyph_id) || len(output) <= 0 ||
        len(output) > core.FONT_MATH_GLYPH_PART_CAPACITY {
        return {}
    }
    native: [core.FONT_MATH_GLYPH_PART_CAPACITY]Harfbuzz_Math_Glyph_Part
    count := u32(len(output))
    italic_correction: i32
    font := cast(^Harfbuzz_Font)capability^.resource.font
    available := hb_ot_math_get_glyph_assembly(
        font, glyph_id, direction, 0, &count, &native[0], &italic_correction)
    if count == 0 || available != count || int(count) > len(output) {
        return {}
    }
    min_overlap := hb_ot_math_get_min_connector_overlap(font, direction)
    if min_overlap < 0 {
        return {}
    }
    if !math_shaping_copy_assembly_parts(native[:count], output) {
        return {}
    }
    return {int(count), min_overlap, italic_correction, true}
}

//   Copy one glyph's vertical MATH assembly into caller-owned bounded storage.
math_shaping_vertical_assembly :: proc(
    capability: ^Font_Math_Shaping_Capability,
    generation: u64,
    glyph_id: u32,
    output: []core.Font_Math_Glyph_Part) -> Math_Assembly_Query_Result {

    return math_shaping_directional_assembly(
        capability, generation, glyph_id, .Top_To_Bottom, output)
}

//   Copy one glyph's horizontal MATH assembly into caller-owned bounded storage.
math_shaping_horizontal_assembly :: proc(
    capability: ^Font_Math_Shaping_Capability,
    generation: u64,
    glyph_id: u32,
    output: []core.Font_Math_Glyph_Part) -> Math_Assembly_Query_Result {

    return math_shaping_directional_assembly(
        capability, generation, glyph_id, .Left_To_Right, output)
}

//   Copy one completed native shape result into caller-owned bounded storage.
//
// Parameters:
//   - buffer: HarfBuzz buffer containing glyph information and positions.
//   - output: Caller-owned destination whose capacity bounds the copied glyph count.
//
// Returns:
//   - Copied glyph count and true when all records fit and native arrays agree.
//   - Zero and false for empty, oversized, missing, or inconsistent native results.
//
// Side effects:
//   - Overwrites only the returned prefix of `output`; retains no destination pointer.
harfbuzz_copy_result :: proc(
    buffer: ^Harfbuzz_Buffer, output: []Shaped_Glyph) -> (int, bool) {

    glyph_count := hb_buffer_get_length(buffer)
    if glyph_count == 0 || int(glyph_count) > len(output) {
        return 0, false
    }
    info_count, position_count := glyph_count, glyph_count
    infos := hb_buffer_get_glyph_infos(buffer, &info_count)
    positions := hb_buffer_get_glyph_positions(buffer, &position_count)
    if infos == nil || positions == nil || info_count != glyph_count ||
       position_count != glyph_count {
        return 0, false
    }
    for index in 0..<int(glyph_count) {
        output[index] = {
            glyph_id = infos[index].codepoint,
            cluster = infos[index].cluster,
            x_advance = positions[index].x_advance,
            y_advance = positions[index].y_advance,
            x_offset = positions[index].x_offset,
            y_offset = positions[index].y_offset,
        }
    }
    return int(glyph_count), true
}

//   Decode one strict UTF-8 scalar and its byte width at `offset`.
math_projection_decode_utf8 :: proc(
    text: string, offset: int) -> Math_Projection_Decode_Result {

    if offset < 0 || offset >= len(text) {
        return {}
    }
    first := text[offset]
    width := 1
    minimum: u32 = 0
    scalar := u32(first)
    if first >= 0xc2 && first <= 0xdf {
        width, minimum, scalar = 2, 0x80, u32(first & 0x1f)
    } else if first >= 0xe0 && first <= 0xef {
        width, minimum, scalar = 3, 0x800, u32(first & 0x0f)
    } else if first >= 0xf0 && first <= 0xf4 {
        width, minimum, scalar = 4, 0x10000, u32(first & 0x07)
    } else if first > 0x7f {
        return {}
    }
    if offset + width > len(text) {
        return {}
    }
    for index in 1..<width {
        continuation := text[offset + index]
        if continuation & 0xc0 != 0x80 {
            return {}
        }
        scalar = scalar << 6 | u32(continuation & 0x3f)
    }
    valid := scalar >= minimum && scalar <= 0x10ffff &&
        !(scalar >= 0xd800 && scalar <= 0xdfff)
    return {value = rune(scalar), width = width, valid = valid}
}

//   Encode one valid Unicode scalar into caller-provided four-byte storage.
math_projection_encode_utf8 :: proc(value: rune, output: ^[4]u8) -> int {
    scalar := u32(value)
    if scalar <= 0x7f {
        output[0] = u8(scalar)
        return 1
    } else if scalar <= 0x7ff {
        output[0] = u8(0xc0 | scalar >> 6)
        output[1] = u8(0x80 | scalar & 0x3f)
        return 2
    } else if scalar <= 0xffff {
        output[0] = u8(0xe0 | scalar >> 12)
        output[1] = u8(0x80 | scalar >> 6 & 0x3f)
        output[2] = u8(0x80 | scalar & 0x3f)
        return 3
    }
    output[0] = u8(0xf0 | scalar >> 18)
    output[1] = u8(0x80 | scalar >> 12 & 0x3f)
    output[2] = u8(0x80 | scalar >> 6 & 0x3f)
    output[3] = u8(0x80 | scalar & 0x3f)
    return 4
}

//   Map one source scalar to NewCM's mathematical italic alphabet repertoire.
math_projection_italic_scalar :: proc(value: rune) -> rune {
    scalar := u32(value)
    if scalar >= 'A' && scalar <= 'Z' {
        return rune(0x1d434 + scalar - 'A')
    } else if scalar >= 'a' && scalar <= 'z' {
        return rune(0x210e) if value == 'h' else rune(0x1d44e + scalar - 'a')
    } else if scalar >= 0x03b1 && scalar <= 0x03c9 {
        return rune(0x1d6fc + scalar - 0x03b1)
    }
    special_sources := [?]rune{'∂', 'ϵ', 'ϑ', 'ϰ', 'ϕ', 'ϱ', 'ϖ'}
    for source, index in special_sources {
        if value == source {
            return rune(0x1d715 + index)
        }
    }
    return value
}

//   Project source math into bounded worker-owned shaping bytes without mutation.
//
// Returns:
//   - A workspace-backed projected string and true when all source is valid and fits.
//   - An empty string and false for malformed UTF-8, role, or insufficient capacity.
math_shaping_project_source :: proc(
    text: string, role: Math_Shaping_Role, workspace: []u8) -> (string, bool) {

    if len(text) == 0 || role < .Upright || role > .Italic {
        return "", false
    }
    read_offset, write_offset := 0, 0
    for read_offset < len(text) {
        decoded := math_projection_decode_utf8(text, read_offset)
        if !decoded.valid {
            return "", false
        }
        projected := decoded.value
        if role == .Italic {
            projected = math_projection_italic_scalar(decoded.value)
        }
        encoded: [4]u8
        encoded_len := math_projection_encode_utf8(projected, &encoded)
        if write_offset + encoded_len > len(workspace) {
            return "", false
        }
        copy(workspace[write_offset:write_offset + encoded_len], encoded[:encoded_len])
        read_offset += decoded.width
        write_offset += encoded_len
    }
    return string(workspace[:write_offset]), true
}

//   Report whether every shaped glyph identity in one buffer is valid.
math_shaping_buffer_has_glyphs :: proc(buffer: ^Harfbuzz_Buffer) -> bool {
    glyph_count := hb_buffer_get_length(buffer)
    info_count := glyph_count
    infos := hb_buffer_get_glyph_infos(buffer, &info_count)
    if infos == nil || info_count != glyph_count {
        return false
    }
    for index in 0..<int(glyph_count) {
        if infos[index].codepoint == 0 {
            return false
        }
    }
    return true
}

//   Shape one math run with explicit left-to-right mathematical script properties.
//
// Returns:
//   - Complete bounded glyph output and true, or zero/false for invalid input,
//     role, workspace, generation, missing glyphs, or native result failure.
//
// Side effects:
//   - Mutates the caller's temporary workspace and worker-owned reusable buffer.
math_shaping_shape :: proc(
    capability: ^Font_Math_Shaping_Capability, generation: u64,
    input: Math_Shaping_Input, output: []Shaped_Glyph) -> (int, bool) {

    if !math_shaping_generation_matches(capability, generation) ||
        len(input.text) == 0 || len(input.text) > int(max(c.int)) || len(output) == 0 {
        return 0, false
    }
    shaping_text, projected := math_shaping_project_source(
        input.text, input.role, input.workspace)
    if !projected || len(shaping_text) > int(max(c.int)) {
        return 0, false
    }
    buffer := cast(^Harfbuzz_Buffer)capability.resource.buffer
    hb_buffer_clear_contents(buffer)
    hb_buffer_set_flags(buffer, 0x10 if input.standalone_accent else 0)
    hb_buffer_set_direction(buffer, .Left_To_Right)
    hb_buffer_set_script(buffer, harfbuzz_tag('m', 'a', 't', 'h'))
    hb_buffer_add_utf8(
        buffer, cstring(raw_data(shaping_text)), c.int(len(shaping_text)), 0, -1)
    feature := Harfbuzz_Feature{
        tag = harfbuzz_tag('f', 'l', 'a', 'c'),
        value = 1 if input.flattened_accent else 0,
        end = max(u32),
    }
    hb_shape(cast(^Harfbuzz_Font)capability.resource.font, buffer, &feature, 1)
    if !math_shaping_buffer_has_glyphs(buffer) {
        return 0, false
    }
    return harfbuzz_copy_result(buffer, output)
}

//   Report whether explicit math direction and script remain installed on the buffer.
math_shaping_has_math_properties :: proc(
    capability: ^Font_Math_Shaping_Capability) -> bool {

    if capability == nil || capability.resource.buffer == nil {
        return false
    }
    buffer := cast(^Harfbuzz_Buffer)capability.resource.buffer
    return hb_buffer_get_direction(buffer) == .Left_To_Right &&
        hb_buffer_get_script(buffer) == harfbuzz_tag('m', 'a', 't', 'h')
}

//   Shape borrowed UTF-8 into bounded presentation glyphs using JuliaMono `calt`.
//
// Parameters:
//   - shaper: Initialized native state whose buffer is reused by this call.
//   - text: Nonempty UTF-8 borrowed only for the duration of the native shape call.
//   - calt_enabled: Enables or disables contextual alternates for the complete input.
//   - output: Caller-owned shaped-glyph storage bounding native result publication.
//
// Returns:
//   - Shaped glyph count and true when the complete result fits in `output`.
//   - Zero and false for invalid state/input or an unusable native result.
//
// Side effects:
//   - Clears and repopulates the reusable HarfBuzz buffer owned by `shaper`.
//
// Notes:
//   - Glyph positions are signed 26.6 values at the pixel scale selected during init.
//   - Source bytes and semantic terminal cells are never modified.
harfbuzz_shape :: proc(
    shaper: ^Font_Shaping_Resource, text: string, calt_enabled: bool,
    output: []Shaped_Glyph) -> (int, bool) {

    if shaper == nil || len(text) == 0 || len(text) > int(max(c.int)) ||
        len(output) == 0 {
        return 0, false
    }
    if shaper.font == nil || shaper.buffer == nil {
        return 0, false
    }
    buffer := cast(^Harfbuzz_Buffer)shaper.buffer
    hb_buffer_clear_contents(buffer)
    hb_buffer_add_utf8(
        buffer, cstring(raw_data(text)), c.int(len(text)), 0, -1)
    hb_buffer_guess_segment_properties(buffer)
    feature := Harfbuzz_Feature{
        tag = harfbuzz_tag('c', 'a', 'l', 't'),
        value = 1 if calt_enabled else 0,
        end = max(u32),
    }
    hb_shape(cast(^Harfbuzz_Font)shaper.font, buffer, &feature, 1)
    return harfbuzz_copy_result(buffer, output)
}