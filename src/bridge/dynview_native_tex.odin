package bridge

import "../core"
import dyncore "../dynview/core"
import dynparse "../dynview/parse"

DYNVIEW_NATIVE_SCRIPT_SCALE :: f32(0.62)
DYNVIEW_NATIVE_SCRIPT_SUP_RAISE :: f32(0.44)
DYNVIEW_NATIVE_SCRIPT_SUB_DROP :: f32(0.30)
DYNVIEW_NATIVE_SCRIPT_GAP :: f32(0.04)
DYNVIEW_NATIVE_ACCENT_THICKNESS :: f32(0.08)
DYNVIEW_NATIVE_ACCENT_OFFSET :: f32(0.10)
DYNVIEW_NATIVE_COMMAND_KINDS :: [11]core.Dynview_Command_Kind{
    .Text_Run, .Math_Glyph_Run, .Accent_Bar, .Radical_Bar, .Script_Attach,
    .Large_Op, .Frac, .Stretch_Delimiter, .Matrix, .Style_Override, .Stack,
}

// Group presentation choices applied while importing parser-owned math semantics.
Dynview_Native_Math_Styles :: struct {
    text: i32,
    math: i32,
    regular: i32,
    mathbb: i32,
}

// Group mutable staging state used by one native math import transaction.
Dynview_Native_Math_Import :: struct {
    runtime: ^core.Dynview_System,
    document: ^dyncore.Dynview_Document,
    styles: Dynview_Native_Math_Styles,
    program_base: int,
    descriptor_base: int,
    blob_offset: int,
}

// Group staging-relative ranges needed to publish one semantic document descriptor.
Dynview_Native_Document_Offsets :: struct {
    source: int,
    text: int,
    block: int,
    inline_start: int,
    display_row: int,
}

//   Build a complete document stream with a fallback command as its commit boundary.
dynview_native_document_source :: proc(
    state: ^core.Euclid_General_State,
    request: Bridge_Dynview_Document_Request) -> i32 {
    if state == nil || request.source == nil || request.fallback == nil ||
        request.text_style < 0 {
        return BRIDGE_STATUS_INVALID_ARGUMENT
    }
    status := dynview_reset_stream(state)
    if status == BRIDGE_STATUS_OK {
        status = dynview_begin_block(state, request.block_kind, request.block_id)
    }
    if status == BRIDGE_STATUS_OK {
        status = dynview_copyable_text_run(state, request.fallback)
    }
    if status != BRIDGE_STATUS_OK {
        return status
    }
    runtime: ^core.Dynview_System
    status = dynview_require_runtime(state, &runtime)
    if status != BRIDGE_STATUS_OK || runtime == nil {
        return status
    }
    checkpoint := dynview_math_import_checkpoint(runtime)
    status = dynview_native_import_document(
        state, runtime, string(request.source), request.text_style)
    if status != BRIDGE_STATUS_OK {
        fallback_status := dynview_native_stage_document_fallback(
            state, runtime, checkpoint, request)
        if fallback_status != BRIDGE_STATUS_OK {
            return fallback_status
        }
    }
    close_status := dynview_end_block(state)
    return status if close_status == BRIDGE_STATUS_OK else close_status
}

//   Roll back rejected semantics and stage the caller's visible fallback text.
dynview_native_stage_document_fallback :: proc(
    state: ^core.Euclid_General_State,
    runtime: ^core.Dynview_System,
    checkpoint: Dynview_Math_Import_Checkpoint,
    request: Bridge_Dynview_Document_Request) -> i32 {
    dynview_math_import_rollback(runtime, checkpoint)
    runtime.command_buffer.has_stream_error = false
    runtime.compile_cache.last_error_code = BRIDGE_STATUS_OK
    return dynview_text_run(state, request.fallback, request.text_style)
}

//   Intern one document and replay its immutable native semantics into staging.
dynview_native_import_document :: proc(
    state: ^core.Euclid_General_State,
    runtime: ^core.Dynview_System,
    source: string,
    text_style: i32) -> i32 {
    text := dynparse.tex_document_trim(source)
    if dynparse.tex_classify_source_mode(text) == .Math {
        fragment := dynparse.tex_document_whole_math(text)
        root_style := dynparse.Tex_Math_Root_Style.Display
        if fragment.present {
            text = fragment.content
            root_style = fragment.style
        }
        return dynview_native_import_math_source(
            state, runtime, text, root_style, text_style)
    }
    handle, intern_status := dyncore.document_store_intern(
        &state.dynview_documents, source, .Document, .Display)
    if intern_status != .Ok {
        return dynview_native_store_status(intern_status)
    }
    document, resolve_status := dyncore.document_store_resolve(
        &state.dynview_documents, handle)
    if resolve_status != .Ok {
        return dynview_native_store_status(resolve_status)
    }
    return dynview_native_replay_document(runtime, &document, text_style)
}

//   Intern and replay one normalized whole-math source inside an open block.
dynview_native_import_math_source :: proc(
    state: ^core.Euclid_General_State,
    runtime: ^core.Dynview_System,
    source: string,
    root_style: dynparse.Tex_Math_Root_Style,
    text_style: i32) -> i32 {
    handle, intern_status := dyncore.document_store_intern(
        &state.dynview_documents, source, .Math, root_style)
    if intern_status != .Ok {
        return dynview_native_store_status(intern_status)
    }
    document, resolve_status := dyncore.document_store_resolve(
        &state.dynview_documents, handle)
    if resolve_status != .Ok {
        return dynview_native_store_status(resolve_status)
    }
    styles := dynview_native_document_styles(text_style)
    return dynview_native_import_math(runtime, &document, styles)
}

//   Build the stable math style profile used by native document imports.
dynview_native_document_styles :: #force_inline proc(
    text_style: i32) -> Dynview_Native_Math_Styles {
    return {
        text = text_style,
        math = BRIDGE_DYNVIEW_STYLE_ITALIC,
        regular = BRIDGE_DYNVIEW_STYLE_CUSTOM_FONT |
            BRIDGE_DYNVIEW_FONT_FLAG_REGULAR,
        mathbb = BRIDGE_DYNVIEW_STYLE_CUSTOM_FONT |
            BRIDGE_DYNVIEW_FONT_FLAG_REGULAR,
    }
}

//   Translate a document-store status without poisoning an authored fallback stream.
dynview_native_store_status :: proc(
    status: dyncore.Dynview_Document_Status) -> i32 {
    if status == .Out_Of_Capacity || status == .Allocation_Failed {
        return BRIDGE_STATUS_OUT_OF_CAPACITY
    }
    if status == .Rejected || status == .Invalid_Argument {
        return BRIDGE_STATUS_INVALID_ARGUMENT
    }
    return BRIDGE_STATUS_ILLEGAL_STATE
}

//   Copy one authoritative semantic document into snapshot staging.
dynview_native_replay_document :: proc(
    runtime: ^core.Dynview_System,
    document: ^dyncore.Dynview_Document,
    text_style: i32) -> i32 {
    if !dynview_native_record_capacity_available(runtime, document) ||
        !dynview_native_document_capacity_available(runtime, document) {
        return BRIDGE_STATUS_OUT_OF_CAPACITY
    }
    styles := dynview_native_document_styles(text_style)
    program_base := runtime.compile_cache.math_program_count
    blob_offset, blob_count: int
    status := dynview_append_text_payload(
        runtime, string(document.text), &blob_offset, &blob_count)
    if status == BRIDGE_STATUS_OK {
        status = dynview_native_import_math_records(
            runtime, document, styles, blob_offset)
    }
    if status == BRIDGE_STATUS_OK {
        status = dynview_native_import_document_semantics(
            runtime, document, program_base)
    }
    return status
}

//   Check exact document byte, descriptor, block, and inline capacities before mutation.
dynview_native_document_capacity_available :: proc(
    runtime: ^core.Dynview_System,
    document: ^dyncore.Dynview_Document) -> bool {

    cache := &runtime.compile_cache
    return cache.document_text_count + len(document.source) + len(document.text) <=
        core.DYNVIEW_MAX_DOCUMENT_BYTES &&
        cache.document_count < core.DYNVIEW_MAX_DOCUMENTS &&
        cache.document_block_count + len(document.document_blocks) <=
            core.DYNVIEW_MAX_DOCUMENT_BLOCKS &&
        cache.document_inline_count + len(document.document_inlines) <=
            core.DYNVIEW_MAX_DOCUMENT_INLINES &&
        cache.document_display_row_count + len(document.document_display_rows) <=
            core.DYNVIEW_MAX_DOCUMENT_DISPLAY_ROWS
}

//   Copy one complete semantic document and rewrite all ranges to staging offsets.
dynview_native_import_document_semantics :: proc(
    runtime: ^core.Dynview_System,
    document: ^dyncore.Dynview_Document,
    program_base: int) -> i32 {

    cache := &runtime.compile_cache
    source_offset, text_offset := dynview_native_copy_document_text(cache, document)
    block_start := cache.document_block_count
    inline_start := cache.document_inline_count
    display_row_start := cache.document_display_row_count
    for row in document.document_display_rows {
        converted, ok := dynview_native_document_display_row(
            row, document, source_offset, program_base)
        if !ok {return BRIDGE_STATUS_INVALID_ARGUMENT}
        cache.document_display_rows[cache.document_display_row_count] = converted
        cache.document_display_row_count += 1
    }
    next_number := 1
    for block in document.document_blocks {
        converted, ok := dynview_native_document_block(
            block, document, source_offset, inline_start, display_row_start)
        if !ok {
            return BRIDGE_STATUS_INVALID_ARGUMENT
        }
        dynview_native_number_display_rows(cache, converted, &next_number)
        cache.document_blocks[cache.document_block_count] = converted
        cache.document_block_count += 1
    }
    for item in document.document_inlines {
        converted, ok := dynview_native_document_inline(
            item, document, source_offset, text_offset, program_base)
        if !ok {
            return BRIDGE_STATUS_INVALID_ARGUMENT
        }
        cache.document_inlines[cache.document_inline_count] = converted
        cache.document_inline_count += 1
    }
    dynview_native_publish_document(cache, document, {
        source = source_offset,
        text = text_offset,
        block = block_start,
        inline_start = inline_start,
        display_row = display_row_start,
    })
    return BRIDGE_STATUS_OK
}

//   Copy exact source and semantic text into staging-owned document bytes.
dynview_native_copy_document_text :: proc(
    cache: ^core.Dynview_Compile_Cache,
    document: ^dyncore.Dynview_Document) -> (int, int) {

    source_offset := cache.document_text_count
    copy(cache.document_text[source_offset:], transmute([]u8)document.source)
    cache.document_text_count += len(document.source)
    text_offset := cache.document_text_count
    copy(cache.document_text[text_offset:], document.text)
    cache.document_text_count += len(document.text)
    return source_offset, text_offset
}

//   Publish one semantic document descriptor after all child records are copied.
dynview_native_publish_document :: proc(
    cache: ^core.Dynview_Compile_Cache,
    document: ^dyncore.Dynview_Document,
    offsets: Dynview_Native_Document_Offsets) {

    cache.documents[cache.document_count] = {
        source_offset = offsets.source,
        source_count = len(document.source),
        text_offset = offsets.text,
        text_count = len(document.text),
        block_start = offsets.block,
        block_count = len(document.document_blocks),
        inline_start = offsets.inline_start,
        inline_count = len(document.document_inlines),
        display_row_start = offsets.display_row,
        display_row_count = len(document.document_display_rows),
    }
    cache.document_count += 1
}

//   Rewrite one parser block into the staging document and source ranges.
dynview_native_document_block :: proc(
    block: dynparse.Tex_Document_Block,
    document: ^dyncore.Dynview_Document,
    source_base, inline_base, display_row_base: int) -> (
        core.Dynview_Document_Block, bool) {

    if !dynview_native_span_valid(
        block.source.offset, block.source.length, len(document.source)) ||
        !dynview_native_span_valid(block.inline_start, block.inline_count,
            len(document.document_inlines)) ||
        !dynview_native_span_valid(block.display_row_start,
            block.display_row_count, len(document.document_display_rows)) {
        return {}, false
    }
    return {
        kind = core.Dynview_Document_Block_Kind(block.kind),
        inline_start = inline_base + block.inline_start,
        inline_count = block.inline_count,
        source_offset = source_base + block.source.offset,
        source_count = block.source.length,
        alignment = core.Dynview_Document_Alignment(block.format.alignment),
        no_indent = block.format.no_indent,
        display_kind = core.Dynview_Document_Display_Kind(block.display_kind),
        display_row_start = display_row_base+block.display_row_start,
        display_row_count = block.display_row_count,
        display_numbered = block.display_numbered,
    }, true
}

// Rewrite one parser display row into staging source and math-program offsets.
dynview_native_document_display_row :: proc(
    row: dynparse.Tex_Document_Display_Row,
    document: ^dyncore.Dynview_Document,
    source_base, program_base: int) -> (core.Dynview_Document_Display_Row, bool) {

    if !dynview_native_span_valid(
        row.source.offset, row.source.length, len(document.source)) ||
        row.primary_program < 0 || row.primary_program >= len(document.programs) ||
        row.secondary_program >= len(document.programs) {
        return {}, false
    }
    return {
        source_offset = source_base+row.source.offset,
        source_count = row.source.length,
        primary_program_id = program_base+row.primary_program,
        secondary_program_id = program_base+row.secondary_program if
            row.secondary_program >= 0 else -1,
        alignment = core.Dynview_Document_Alignment(row.alignment),
        suppress_number = row.suppress_number,
    }, true
}

// Assign stable document-local numbers to eligible rows in one display block.
dynview_native_number_display_rows :: proc(
    cache: ^core.Dynview_Compile_Cache,
    block: core.Dynview_Document_Block,
    next_number: ^int) {

    if !block.display_numbered {return}
    for relative_index in 0..<block.display_row_count {
        row := &cache.document_display_rows[block.display_row_start+relative_index]
        eligible := !row.suppress_number
        if block.display_kind == .Multline {
            eligible = eligible && relative_index == block.display_row_count-1
        }
        if eligible {
            row.number = next_number^
            next_number^ += 1
        }
    }
}

//   Rewrite one parser inline into staging byte and math-program offsets.
dynview_native_document_inline :: proc(
    item: dynparse.Tex_Document_Inline,
    document: ^dyncore.Dynview_Document,
    source_base, text_base, program_base: int) -> (
        core.Dynview_Document_Inline, bool) {

    if !dynview_native_span_valid(
        item.source.offset, item.source.length, len(document.source)) ||
        !dynview_native_span_valid(
            item.text.offset, item.text.length, len(document.text)) ||
        item.math_program < -1 || item.math_program >= len(document.programs) {
        return {}, false
    }
    program_id := -1
    if item.math_program >= 0 {
        program_id = program_base + item.math_program
    }
    result := core.Dynview_Document_Inline{
        kind = core.Dynview_Document_Inline_Kind(item.kind),
        source_offset = source_base + item.source.offset,
        source_count = item.source.length,
        text_offset = text_base + item.text.offset,
        text_count = item.text.length,
        font_flags = item.font_flags,
        color = dynview_native_document_color(item.color),
        space_kind = core.Dynview_Document_Space_Kind(item.space_kind),
        shape = dynview_native_document_shape(item.shape),
        root_style = core.Dynview_Math_Style_Level(item.root_style),
        math_program_id = program_id,
        penalty = item.penalty,
    }
    return result, true
}

//   Copy one parser shape payload without retaining parser-owned storage.
dynview_native_document_shape :: proc(
    shape: dynparse.Tex_Document_Shape) -> core.Dynview_Document_Shape {

    result := core.Dynview_Document_Shape{
        present = shape.present,
        kind = core.Dynview_Document_Shape_Kind(shape.kind),
        color = dynview_native_document_color(shape.color),
        width = shape.width,
        height = shape.height,
        thickness = shape.thickness,
        filled = shape.filled,
        start_angle = shape.start_angle,
        end_angle = shape.end_angle,
        fill_color = dynview_native_document_color(shape.fill_color),
        arc_color = dynview_native_document_color(shape.arc_color),
    }
    for color, index in shape.edge_colors {
        result.edge_colors[index] = dynview_native_document_color(color)
    }
    return result
}

//   Copy one parser color into a render-package-independent semantic wrapper.
dynview_native_document_color :: #force_inline proc(
    color: dynparse.Tex_Document_Color) -> core.Dynview_Document_Color {
    return {
        present = color.present,
        value = {color.red, color.green, color.blue, color.alpha},
    }
}

//   Validate one nonnegative offset and count against a bounded source.
dynview_native_span_valid :: #force_inline proc(
    offset, count, total: int) -> bool {
    return offset >= 0 && count >= 0 && count <= total && offset <= total-count
}

//   Intern raw math source and copy its semantics into current snapshot staging.
dynview_native_math_source :: proc(
    state: ^core.Euclid_General_State,
    request: Bridge_Dynview_Math_Request) -> i32 {
    if state == nil || request.source == nil || request.text_style < 0 ||
        request.math_style < 0 || request.mathbb_style < 0 ||
        request.root_style < BRIDGE_DYNVIEW_MATH_ROOT_DISPLAY ||
        request.root_style > BRIDGE_DYNVIEW_MATH_ROOT_TEXT {
        return BRIDGE_STATUS_INVALID_ARGUMENT
    }
    context = state^.saved_context
    runtime: ^core.Dynview_System
    status := dynview_require_runtime(state, &runtime)
    if status != BRIDGE_STATUS_OK || runtime == nil || !runtime.enabled {
        return status
    }
    buffer: ^core.Dynview_Command_Buffer
    status = dynview_require_buffer(runtime, &buffer, true)
    if status != BRIDGE_STATUS_OK {
        return status
    }
    root_style := dynparse.Tex_Math_Root_Style(request.root_style)
    handle, intern_status := dyncore.document_store_intern(
        &state.dynview_documents, string(request.source), .Math, root_style)
    if intern_status != .Ok {
        return dynview_native_store_failure(runtime, intern_status)
    }
    document, resolve_status := dyncore.document_store_resolve(
        &state.dynview_documents, handle)
    if resolve_status != .Ok {
        return dynview_native_store_failure(runtime, resolve_status)
    }
    return dynview_native_import_math(runtime, &document, Dynview_Native_Math_Styles{
        text = request.text_style,
        math = request.math_style,
        regular = BRIDGE_DYNVIEW_STYLE_CUSTOM_FONT |
            BRIDGE_DYNVIEW_FONT_FLAG_REGULAR,
        mathbb = request.mathbb_style,
    })
}

//   Translate document-store failures to stable bridge status and stream failure.
dynview_native_store_failure :: proc(
    runtime: ^core.Dynview_System,
    status: dyncore.Dynview_Document_Status) -> i32 {
    if status == .Out_Of_Capacity || status == .Allocation_Failed {
        return dynview_fail(runtime, BRIDGE_STATUS_OUT_OF_CAPACITY)
    }
    if status == .Rejected || status == .Invalid_Argument {
        return dynview_fail(runtime, BRIDGE_STATUS_INVALID_ARGUMENT)
    }
    return dynview_fail(runtime, BRIDGE_STATUS_ILLEGAL_STATE)
}

//   Copy one resolved native math document into mutable snapshot staging atomically.
dynview_native_import_math :: proc(
    runtime: ^core.Dynview_System,
    document: ^dyncore.Dynview_Document,
    styles: Dynview_Native_Math_Styles) -> i32 {
    checkpoint := dynview_math_import_checkpoint(runtime)
    if !dynview_native_math_capacity_available(runtime, document) {
        return dynview_fail(runtime, BRIDGE_STATUS_OUT_OF_CAPACITY)
    }
    plain_offset, plain_count, blob_offset, blob_count: int
    plain := dyncore.document_store_text(document, document.plain_text)
    status := dynview_append_text_payload(runtime, plain, &plain_offset, &plain_count)
    if status == BRIDGE_STATUS_OK {
        status = dynview_append_text_payload(
            runtime, string(document.text), &blob_offset, &blob_count)
    }
    if status == BRIDGE_STATUS_OK {
        status = dynview_native_import_math_records(
            runtime, document, styles, blob_offset)
    }
    if status == BRIDGE_STATUS_OK {
        status = dynview_native_push_math_block(runtime, document,
            styles.math, plain_offset, plain_count)
    }
    if status != BRIDGE_STATUS_OK {
        dynview_math_import_rollback(runtime, checkpoint)
    }
    return status
}

//   Check exact program, command, descriptor, and text capacities before mutation.
dynview_native_math_capacity_available :: proc(
    runtime: ^core.Dynview_System,
    document: ^dyncore.Dynview_Document) -> bool {
    return dynview_native_record_capacity_available(runtime, document) &&
        runtime.command_buffer.text_bytes_len + len(document.text) +
            document.plain_text.length <= core.DYNVIEW_MAX_TEXT_BYTES
}

//   Check exact native semantic-record capacities before importing any records.
dynview_native_record_capacity_available :: proc(
    runtime: ^core.Dynview_System,
    document: ^dyncore.Dynview_Document) -> bool {
    cache := &runtime.compile_cache
    default_tables := 0
    for op in document.ops {
        if op.kind == .Matrix && op.table_descriptor < 0 {
            default_tables += 1
        }
    }
    return cache.math_program_count + len(document.programs) <=
        core.DYNVIEW_MAX_MATH_PROGRAMS &&
        cache.math_command_count + len(document.ops) <=
            core.DYNVIEW_MAX_MATH_COMMANDS &&
        cache.math_table_descriptor_count + len(document.table_descriptors) +
            default_tables <= core.DYNVIEW_MAX_MATH_TABLE_DESCRIPTORS
}

//   Import native descriptors and linked programs using staging-relative indices.
dynview_native_import_math_records :: proc(
    runtime: ^core.Dynview_System,
    document: ^dyncore.Dynview_Document,
    styles: Dynview_Native_Math_Styles,
    blob_offset: int) -> i32 {
    import_ctx := Dynview_Native_Math_Import{
        runtime = runtime,
        document = document,
        styles = styles,
        program_base = runtime.compile_cache.math_program_count,
        descriptor_base = runtime.compile_cache.math_table_descriptor_count,
        blob_offset = blob_offset,
    }
    status := dynview_native_import_table_descriptors(&import_ctx)
    if status != BRIDGE_STATUS_OK {
        return dynview_fail(runtime, status)
    }
    for program, program_id in document.programs {
        status = dynview_native_import_program(&import_ctx, program, program_id)
        if status != BRIDGE_STATUS_OK {
            return dynview_fail(runtime, status)
        }
    }
    runtime.compile_cache.math_program_count += len(document.programs)
    return BRIDGE_STATUS_OK
}

//   Copy native table descriptors into the existing pointer-free cache format.
dynview_native_import_table_descriptors :: proc(
    ctx: ^Dynview_Native_Math_Import) -> i32 {
    cache := &ctx.runtime.compile_cache
    for source in ctx.document.table_descriptors {
        destination := &cache.math_table_descriptors[cache.math_table_descriptor_count]
        destination^ = dynview_native_table_descriptor(source)
        if !core.dynview_math_table_descriptor_is_valid(destination^) {
            return BRIDGE_STATUS_INVALID_ARGUMENT
        }
        cache.math_table_descriptor_count += 1
    }
    return BRIDGE_STATUS_OK
}

//   Convert one parser table descriptor to native layout-independent metadata.
dynview_native_table_descriptor :: proc(
    source: dynparse.Tex_Table_Descriptor) -> core.Dynview_Math_Table_Descriptor {
    result := core.Dynview_Math_Table_Descriptor{
        rows = source.rows,
        columns = source.columns,
        cell_style = core.Dynview_Math_Style_Level(source.cell_style),
        row_spacing = core.Dynview_Math_Table_Row_Spacing(source.row_spacing),
    }
    for alignment, index in source.alignments {
        result.column_alignments[index] =
            core.Dynview_Matrix_Column_Alignment(alignment)
    }
    for gap, index in source.boundary_gaps {
        result.column_boundary_gaps[index] = dynview_native_table_length(gap)
        result.vertical_rule_counts[index] = source.vertical_rule_counts[index]
    }
    for gap, index in source.row_extra_gaps {
        result.row_extra_gaps[index] = dynview_native_table_length(gap)
    }
    result.horizontal_rule_counts = source.horizontal_rule_counts
    return result
}

//   Convert one parser table length to the existing native unit enum.
dynview_native_table_length :: proc(
    source: dynparse.Tex_Table_Length) -> core.Dynview_Math_Length {
    unit: core.Dynview_Math_Length_Unit
    switch source.unit {
    case .Default: unit = .Default
    case .Zero: unit = .Zero
    case .Em: unit = .Em
    case .Pt: unit = .Point
    }
    return {value = source.value, unit = unit}
}

//   Import one linked native program into one contiguous cache command range.
dynview_native_import_program :: proc(
    ctx: ^Dynview_Native_Math_Import,
    source: dynparse.Tex_Math_Program,
    program_id: int) -> i32 {
    cache := &ctx.runtime.compile_cache
    command_start := cache.math_command_count
    op_index := source.first_op
    for count in 0..<source.op_count {
        if op_index < 0 || op_index >= len(ctx.document.ops) {
            return BRIDGE_STATUS_INVALID_ARGUMENT
        }
        command, status := dynview_native_command(ctx, &ctx.document.ops[op_index])
        if status != BRIDGE_STATUS_OK {
            return status
        }
        cache.math_commands[cache.math_command_count] = command
        cache.math_command_count += 1
        op_index = ctx.document.ops[op_index].next_op
        _ = count
    }
    if op_index >= 0 {
        return BRIDGE_STATUS_INVALID_ARGUMENT
    }
    cache.math_programs[ctx.program_base + program_id] = {
        valid = true,
        command_start = command_start,
        command_count = source.op_count,
    }
    return BRIDGE_STATUS_OK
}

//   Convert one parser operation and rewrite all references to staging indices.
dynview_native_command :: proc(
    ctx: ^Dynview_Native_Math_Import,
    op: ^dynparse.Tex_Math_Op) -> (core.Dynview_Command, i32) {
    kind, valid := dynview_native_command_kind(op.kind)
    if !valid || !dynview_native_op_references_valid(ctx.document, op) {
        return {}, BRIDGE_STATUS_INVALID_ARGUMENT
    }
    command := core.Dynview_Command{
        kind = kind,
        math_atom_class = core.Dynview_Math_Atom_Class(op.atom_class),
        math_glue_kind = core.Dynview_Math_Glue_Kind(op.glue_kind),
        block_id = ctx.runtime.command_buffer.stream_open_block_id,
        style_id = dynview_native_style_id(op, ctx.styles),
        table_descriptor_index = dynview_native_table_id(ctx, op),
        script_style_id = ctx.styles.math,
        script_scale = DYNVIEW_NATIVE_SCRIPT_SCALE,
        script_sup_raise = DYNVIEW_NATIVE_SCRIPT_SUP_RAISE,
        script_sub_drop = DYNVIEW_NATIVE_SCRIPT_SUB_DROP,
        script_gap = DYNVIEW_NATIVE_SCRIPT_GAP,
        accent_mode = dynview_native_accent_mode_code(op),
        radical_mode = dynview_native_mode_code(op),
        large_op_kind = op.large_op_kind,
        operator_growth = op.operator_growth,
        operator_limits = op.operator_limits,
        accent_style_id = dynview_native_style_id(op, ctx.styles),
        accent_thickness = DYNVIEW_NATIVE_ACCENT_THICKNESS,
        accent_offset = DYNVIEW_NATIVE_ACCENT_OFFSET,
    }
    dynview_native_apply_program_ids(ctx, op, &command)
    dynview_native_apply_spans(&command, op, ctx.blob_offset)
    return command, BRIDGE_STATUS_OK
}

//   Translate semantic child roles into the renderer's command program slots.
dynview_native_apply_program_ids :: proc(
    ctx: ^Dynview_Native_Math_Import,
    op: ^dynparse.Tex_Math_Op,
    command: ^core.Dynview_Command) {
    command.math_program_id = dynview_native_program_id(ctx, op.child_program)
    command.secondary_math_program_id =
        dynview_native_program_id(ctx, op.secondary_program)
    command.tertiary_math_program_id =
        dynview_native_program_id(ctx, op.tertiary_program)
    if op.kind == .Large_Operator {
        command.math_program_id = 0
        command.secondary_math_program_id =
            dynview_native_program_id(ctx, op.child_program)
        command.tertiary_math_program_id =
            dynview_native_program_id(ctx, op.secondary_program)
    }
}

//   Convert an accent or left-delimiter mode without conflating their enums.
dynview_native_accent_mode_code :: #force_inline proc(
    op: ^dynparse.Tex_Math_Op) -> i32 {
    if op.kind == .Stretch_Delimiter {
        return i32(op.left_delimiter)
    }
    return i32(op.accent_mode)
}

//   Convert kind-specific parser modes to the established math-layout codes.
dynview_native_mode_code :: #force_inline proc(
    op: ^dynparse.Tex_Math_Op) -> i32 {
    if op.kind == .Style_Override {
        return i32(op.style_level)
    }
    if op.kind == .Stretch_Delimiter {
        return i32(op.right_delimiter)
    }
    return i32(op.radical_mode)
}

//   Map parser operation kinds to established compile-cache command kinds.
dynview_native_command_kind :: proc(
    kind: dynparse.Tex_Math_Op_Kind) -> (core.Dynview_Command_Kind, bool) {
    index := int(kind)-int(dynparse.Tex_Math_Op_Kind.Text_Run)
    if index < 0 || index >= len(DYNVIEW_NATIVE_COMMAND_KINDS) {
        return .Text_Run, false
    }
    kinds := DYNVIEW_NATIVE_COMMAND_KINDS
    return kinds[index], true
}

//   Validate every program, descriptor, and semantic text reference before copy.
dynview_native_op_references_valid :: proc(
    document: ^dyncore.Dynview_Document,
    op: ^dynparse.Tex_Math_Op) -> bool {
    spans := [?]dynparse.Tex_Text_Span{
        op.text, op.radical_index_text, op.superscript_text, op.subscript_text}
    for span in spans {
        if span.offset < 0 || span.length < 0 ||
            span.offset > len(document.text)-span.length {
            return false
        }
    }
    programs := [?]int{
        op.child_program, op.secondary_program, op.tertiary_program}
    for program in programs {
        if program < -1 || program >= len(document.programs) {
            return false
        }
    }
    return op.table_descriptor >= -1 &&
        op.table_descriptor < len(document.table_descriptors)
}

//   Select the legacy-compatible presentation style for one semantic role.
dynview_native_style_id :: proc(
    op: ^dynparse.Tex_Math_Op,
    styles: Dynview_Native_Math_Styles) -> i32 {
    if op.kind == .Text_Run || op.style_role == .Text {
        return styles.text
    }
    if op.kind == .Large_Operator {
        return BRIDGE_DYNVIEW_STYLE_MEDIUM
    }
    switch op.style_role {
    case .Mathbb:
        return styles.mathbb
    case .Math_Upright, .Mathbf, .Mathit, .Mathcal,
        .Operator_Name, .Operator_Name_Star:
        return styles.regular
    case .None, .Math, .Math_Italic, .Text:
        return styles.math
    }
    return styles.math
}

//   Rewrite one parser program id into the staging cache's program range.
dynview_native_program_id :: #force_inline proc(
    ctx: ^Dynview_Native_Math_Import,
    program_id: int) -> i32 {
    return i32(ctx.program_base + program_id) if program_id >= 0 else 0
}

//   Resolve or append one matrix descriptor in staging-owned storage.
dynview_native_table_id :: proc(
    ctx: ^Dynview_Native_Math_Import,
    op: ^dynparse.Tex_Math_Op) -> i32 {
    if op.kind != .Matrix {
        return -1
    }
    if op.table_descriptor >= 0 {
        return i32(ctx.descriptor_base + op.table_descriptor)
    }
    cache := &ctx.runtime.compile_cache
    index := cache.math_table_descriptor_count
    cache.math_table_descriptors[index] =
        dynview_native_default_table(ctx.document, op)
    cache.math_table_descriptor_count += 1
    return i32(index)
}

//   Build default centered matrix metadata from retained decimal dimensions.
dynview_native_default_table :: proc(
    document: ^dyncore.Dynview_Document,
    op: ^dynparse.Tex_Math_Op) -> core.Dynview_Math_Table_Descriptor {
    result := core.Dynview_Math_Table_Descriptor{
        rows = dynview_native_small_integer(document, op.radical_index_text),
        columns = dynview_native_small_integer(document, op.superscript_text),
        cell_style = .Text,
        row_spacing = .Matrix,
    }
    for &alignment in result.column_alignments {
        alignment = .Center
    }
    return result
}

//   Decode one parser-owned one- or two-digit table dimension span.
dynview_native_small_integer :: proc(
    document: ^dyncore.Dynview_Document,
    span: dynparse.Tex_Text_Span) -> int {
    text := dyncore.document_store_text(document, span)
    value := 0
    for byte in transmute([]u8)text {
        if byte < '0' || byte > '9' {
            return 0
        }
        value = value*10 + int(byte-'0')
    }
    return value
}

//   Rewrite all semantic text spans against the copied staging text base.
dynview_native_apply_spans :: proc(
    command: ^core.Dynview_Command,
    op: ^dynparse.Tex_Math_Op,
    blob_offset: int) {
    command.text_offset = blob_offset + op.text.offset
    command.text_len = op.text.length
    command.script_base_text_offset = command.text_offset
    command.script_base_text_len = command.text_len
    command.script_sup_text_offset = blob_offset + op.superscript_text.offset
    command.script_sup_text_len = op.superscript_text.length
    command.script_sub_text_offset = blob_offset + op.subscript_text.offset
    command.script_sub_text_len = op.subscript_text.length
    command.radical_index_text_offset = blob_offset + op.radical_index_text.offset
    command.radical_index_text_len = op.radical_index_text.length
}

//   Publish one top-level math command after every semantic record is valid.
dynview_native_push_math_block :: proc(
    runtime: ^core.Dynview_System,
    document: ^dyncore.Dynview_Document,
    style_id: i32,
    plain_offset, plain_count: int) -> i32 {
    program_id := runtime.compile_cache.math_program_count -
        len(document.programs) + document.root_program
    runtime.compile_cache.math_programs[program_id].copy_text_offset = plain_offset
    runtime.compile_cache.math_programs[program_id].copy_text_len = plain_count
    return dynview_push_command(runtime, {
        kind = .Math_Block,
        block_id = runtime.command_buffer.stream_open_block_id,
        style_id = style_id,
        math_program_id = i32(program_id),
        text_offset = plain_offset,
        text_len = plain_count,
    })
}