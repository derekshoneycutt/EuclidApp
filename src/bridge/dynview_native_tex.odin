package bridge

import "../core"
import dyncore "../dynview/core"
import dynparse "../dynview/parse"
import rl "vendor:raylib"

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

// Group immutable state shared while replaying one flat native document.
Dynview_Native_Document_Replay :: struct {
    runtime: ^core.Dynview_System,
    document: ^dyncore.Dynview_Document,
    program_base: int,
    blob_offset: int,
    text_style: i32,
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
    styles := Dynview_Native_Math_Styles{
        text = text_style,
        math = BRIDGE_DYNVIEW_STYLE_ITALIC,
        regular = BRIDGE_DYNVIEW_STYLE_CUSTOM_FONT |
            BRIDGE_DYNVIEW_FONT_FLAG_REGULAR,
        mathbb = BRIDGE_DYNVIEW_STYLE_CUSTOM_FONT |
            BRIDGE_DYNVIEW_FONT_FLAG_REGULAR,
    }
    return dynview_native_import_math(runtime, &document, styles)
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

//   Copy document semantics once and replay every flat run in source order.
dynview_native_replay_document :: proc(
    runtime: ^core.Dynview_System,
    document: ^dyncore.Dynview_Document,
    text_style: i32) -> i32 {
    replay, status := dynview_native_prepare_document_replay(
        runtime, document, text_style)
    if status != BRIDGE_STATUS_OK {
        return status
    }
    for &run, index in document.document_runs {
        status = dynview_native_replay_document_run(&replay, &run, index)
        if status != BRIDGE_STATUS_OK {
            return status
        }
    }
    return BRIDGE_STATUS_OK
}

//   Copy shared semantics and prepare stable offsets for flat document replay.
dynview_native_prepare_document_replay :: proc(
    runtime: ^core.Dynview_System,
    document: ^dyncore.Dynview_Document,
    text_style: i32) -> (Dynview_Native_Document_Replay, i32) {
    if !dynview_native_record_capacity_available(runtime, document) {
        return {}, BRIDGE_STATUS_OUT_OF_CAPACITY
    }
    styles := Dynview_Native_Math_Styles{
        text = text_style,
        math = BRIDGE_DYNVIEW_STYLE_ITALIC,
        regular = BRIDGE_DYNVIEW_STYLE_CUSTOM_FONT |
            BRIDGE_DYNVIEW_FONT_FLAG_REGULAR,
        mathbb = BRIDGE_DYNVIEW_STYLE_CUSTOM_FONT |
            BRIDGE_DYNVIEW_FONT_FLAG_REGULAR,
    }
    blob_offset, blob_count: int
    status := dynview_append_text_payload(
        runtime, string(document.text), &blob_offset, &blob_count)
    if status == BRIDGE_STATUS_OK {
        status = dynview_native_import_math_records(
            runtime, document, styles, blob_offset)
    }
    if status != BRIDGE_STATUS_OK {
        return {}, status
    }
    program_base := runtime.compile_cache.math_program_count - len(document.programs)
    return Dynview_Native_Document_Replay{
        runtime = runtime,
        document = document,
        program_base = program_base,
        blob_offset = blob_offset,
        text_style = text_style,
    }, BRIDGE_STATUS_OK
}

//   Replay one flat document run into the current command stream.
dynview_native_replay_document_run :: proc(
    ctx: ^Dynview_Native_Document_Replay,
    run: ^dynparse.Tex_Document_Run,
    index: int) -> i32 {
    switch run.kind {
    case .Text:
        return dynview_native_push_document_text(
            ctx.runtime, run, ctx.blob_offset, ctx.text_style)
    case .Line_Break:
        return dynview_native_push_line_break(ctx.runtime)
    case .Math_Inline:
        return dynview_native_push_document_math(
            ctx.runtime, run, ctx.program_base, ctx.blob_offset, ctx.text_style)
    case .Math_Display:
        return dynview_native_push_display_math(ctx, run, index)
    case .Shape:
        return dynview_native_push_document_shape(ctx.runtime, run, ctx.text_style)
    }
    return BRIDGE_STATUS_INVALID_ARGUMENT
}

//   Append one document text run referencing the copied semantic text blob.
dynview_native_push_document_text :: proc(
    runtime: ^core.Dynview_System,
    run: ^dynparse.Tex_Document_Run,
    blob_offset: int,
    text_style: i32) -> i32 {
    command := core.Dynview_Command{
        kind = .Text_Run,
        block_id = runtime.command_buffer.stream_open_block_id,
        style_id = dynview_native_document_style(run.font_flags, text_style),
        text_offset = blob_offset + run.text.offset,
        text_len = run.text.length,
    }
    dynview_native_apply_color(&command, run.color)
    return dynview_push_command(runtime, command)
}

//   Append one line-break command to the current native document block.
dynview_native_push_line_break :: proc(runtime: ^core.Dynview_System) -> i32 {
    return dynview_push_command(runtime, {
        kind = .Line_Break,
        block_id = runtime.command_buffer.stream_open_block_id,
    })
}

//   Append one document math run referencing an already imported native program.
dynview_native_push_document_math :: proc(
    runtime: ^core.Dynview_System,
    run: ^dynparse.Tex_Document_Run,
    program_base, blob_offset: int,
    text_style: i32) -> i32 {
    if run.math_program < 0 ||
        run.math_program >= runtime.compile_cache.math_program_count-program_base {
        return BRIDGE_STATUS_INVALID_ARGUMENT
    }
    program_id := program_base + run.math_program
    runtime.compile_cache.math_programs[program_id].copy_text_offset =
        blob_offset + run.text.offset
    runtime.compile_cache.math_programs[program_id].copy_text_len = run.text.length
    return dynview_push_command(runtime, {
        kind = .Math_Block,
        block_id = runtime.command_buffer.stream_open_block_id,
        style_id = dynview_native_document_style(run.font_flags, text_style),
        math_program_id = i32(program_id),
        text_offset = blob_offset + run.text.offset,
        text_len = run.text.length,
    })
}

//   Replay display math with one surrounding break where the document lacks one.
dynview_native_push_display_math :: proc(
    ctx: ^Dynview_Native_Document_Replay,
    run: ^dynparse.Tex_Document_Run,
    index: int) -> i32 {
    if index == 0 || ctx.document.document_runs[index-1].kind != .Line_Break {
        status := dynview_native_push_line_break(ctx.runtime)
        if status != BRIDGE_STATUS_OK {
            return status
        }
    }
    status := dynview_native_push_document_math(
        ctx.runtime, run, ctx.program_base, ctx.blob_offset, ctx.text_style)
    if status != BRIDGE_STATUS_OK {
        return status
    }
    if index+1 == len(ctx.document.document_runs) ||
        ctx.document.document_runs[index+1].kind != .Line_Break {
        return dynview_native_push_line_break(ctx.runtime)
    }
    return BRIDGE_STATUS_OK
}

//   Preserve caller text style for regular runs and encode explicit font flags.
dynview_native_document_style :: proc(font_flags, text_style: i32) -> i32 {
    if font_flags == BRIDGE_DYNVIEW_FONT_FLAG_REGULAR {
        return text_style
    }
    return BRIDGE_DYNVIEW_STYLE_CUSTOM_FONT | font_flags
}

//   Apply one parser color to a command without retaining parser-owned memory.
dynview_native_apply_color :: proc(
    command: ^core.Dynview_Command,
    color: dynparse.Tex_Document_Color) {
    if color.present {
        command.has_brush_color = true
        command.brush_color = rl.Color{color.red, color.green, color.blue, color.alpha}
    }
}

//   Convert one flat shape run to the established pointer-free command payload.
dynview_native_push_document_shape :: proc(
    runtime: ^core.Dynview_System,
    run: ^dynparse.Tex_Document_Run,
    text_style: i32) -> i32 {
    shape := &run.shape
    command := core.Dynview_Command{
        block_id = runtime.command_buffer.stream_open_block_id,
        style_id = dynview_native_document_style(run.font_flags, text_style),
        inline_atom_dimension = shape.width,
        inline_box_height = shape.height,
        inline_atom_stroke = shape.thickness,
        shape_is_filled = shape.filled,
        inline_outline_stroke = shape.thickness,
    }
    if !dynview_native_shape_kind(&command, shape) {
        return BRIDGE_STATUS_INVALID_ARGUMENT
    }
    dynview_native_apply_shape_colors(&command, shape)
    return dynview_push_command(runtime, command)
}

//   Select one command kind and geometry convention for a parsed shape.
dynview_native_shape_kind :: proc(
    command: ^core.Dynview_Command,
    shape: ^dynparse.Tex_Document_Shape) -> bool {
    switch shape.kind {
    case .Point:
        command.kind = .Inline_Filled_Circle
        command.inline_outline_stroke = 0
    case .Line: command.kind = .Inline_Line
    case .Circle:
        command.kind = .Inline_Filled_Circle if shape.filled else .Inline_Circle
    case .Box:
        command.kind = .Inline_Filled_Box if shape.filled else .Inline_Box
    case .Angle, .Semicircle:
        command.kind = .Inline_Pie_Section
        command.pie_start_angle_degrees = shape.start_angle
        command.pie_end_angle_degrees = shape.end_angle
        command.pie_is_filled = shape.filled
    case .Perpendicular: command.kind = .Inline_Perpendicular
    case .Triangle: command.kind = .Inline_Triangle
    case .Pentagon: command.kind = .Inline_Pentagon
    case .None: return false
    }
    return true
}

//   Copy inherited fill, outline, and edge colors into one shape command.
dynview_native_apply_shape_colors :: proc(
    command: ^core.Dynview_Command,
    shape: ^dynparse.Tex_Document_Shape) {
    base := dynview_native_color_or_white(shape.color)
    command.has_brush_color = shape.filled || shape.color.present
    command.brush_color = dynview_native_color_or(shape.fill_color, base)
    command.has_outline_color = shape.arc_color.present || shape.color.present
    command.outline_color = dynview_native_color_or(shape.arc_color, base)
    command.shape_edge_color_1 = dynview_native_color_or(shape.edge_colors[0], base)
    command.shape_edge_color_2 = dynview_native_color_or(shape.edge_colors[1], base)
    command.shape_edge_color_3 = dynview_native_color_or(shape.edge_colors[2], base)
    command.shape_edge_color_4 = dynview_native_color_or(shape.edge_colors[3], base)
    command.shape_edge_color_5 = dynview_native_color_or(shape.edge_colors[4], base)
}

//   Convert one present parser color or use a caller-provided rendering fallback.
dynview_native_color_or :: proc(
    color: dynparse.Tex_Document_Color,
    fallback: rl.Color) -> rl.Color {
    if color.present {
        return {color.red, color.green, color.blue, color.alpha}
    }
    return fallback
}

//   Convert one parser color with the legacy white shape fallback.
dynview_native_color_or_white :: proc(
    color: dynparse.Tex_Document_Color) -> rl.Color {
    return dynview_native_color_or(color, rl.Color{255, 255, 255, 255})
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