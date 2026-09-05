package bridge

import "../core"

Dynview_Validated_Op :: struct {
    op:     Bridge_Dynview_Math_Op,
    kind:   core.Dynview_Command_Kind,
    status: i32,
}

Dynview_Imported_Children :: struct {
    child_program_id:           i32,
    secondary_child_program_id: i32,
    tertiary_child_program_id:  i32,
    status:                     i32,
}

//   Shared import environment for walking the flat bridge math-op stream into
//   the dynview compile cache. Groups the cache target, source stream, cursor,
//   blob window, and program-id allocator so the recursive import helpers pass
//   one coherent value instead of a long positional parameter list.
Dynview_Import_Context :: struct {
    cache:           ^core.Dynview_Compile_Cache,
    block_id:        i32,
    ops:             [^]Bridge_Dynview_Math_Op,
    op_count:        int,
    cursor:          ^int,
    blob_offset:     int,
    blob_count:      int,
    next_program_id: ^int,
    table_descriptors: [^]Bridge_Dynview_Math_Table_Descriptor,
    table_descriptor_count: int,
    table_descriptor_base: int,
}

Dynview_Command_Import_Context :: struct {
    block_id: i32,
    blob_offset: int,
    table_descriptor_base: int,
}

//   Dynview command kind for each bridge math-op kind, indexed by op kind.
BRIDGE_DYNVIEW_OP_KIND_TO_COMMAND ::
    [BRIDGE_DYNVIEW_MATH_OP_MAX + 1]core.Dynview_Command_Kind{
    BRIDGE_DYNVIEW_MATH_OP_TEXT_RUN = .Text_Run,
    BRIDGE_DYNVIEW_MATH_OP_MATH_GLYPH_RUN = .Math_Glyph_Run,
    BRIDGE_DYNVIEW_MATH_OP_ACCENT_BAR_RECURSIVE = .Accent_Bar,
    BRIDGE_DYNVIEW_MATH_OP_RADICAL_BAR_RECURSIVE = .Radical_Bar,
    BRIDGE_DYNVIEW_MATH_OP_SCRIPT_ATTACH_RECURSIVE = .Script_Attach,
    BRIDGE_DYNVIEW_MATH_OP_LARGE_OP_RECURSIVE = .Large_Op,
    BRIDGE_DYNVIEW_MATH_OP_FRACTION_RECURSIVE = .Frac,
    BRIDGE_DYNVIEW_MATH_OP_STRETCH_DELIMITER_RECURSIVE = .Stretch_Delimiter,
    BRIDGE_DYNVIEW_MATH_OP_MATRIX_RECURSIVE = .Matrix,
    BRIDGE_DYNVIEW_MATH_OP_STYLE_OVERRIDE_RECURSIVE = .Style_Override,
    BRIDGE_DYNVIEW_MATH_OP_STACK_RECURSIVE = .Stack,
}

//   Return whether one bridge table descriptor is canonical and bounded.
dynview_math_table_descriptor_valid :: proc(
    descriptor: Bridge_Dynview_Math_Table_Descriptor) -> bool {

    for count in descriptor.vertical_rule_counts {
        if count < 0 || count > 2 {
            return false
        }
    }
    for count in descriptor.horizontal_rule_counts {
        if count < 0 || count > 2 {
            return false
        }
    }
    native := dynview_math_table_descriptor_from_bridge(descriptor)
    return core.dynview_math_table_descriptor_is_valid(native)
}

//   Copy one validated bridge table descriptor into native bounded storage.
dynview_math_table_descriptor_from_bridge :: proc(
    descriptor: Bridge_Dynview_Math_Table_Descriptor) ->
        core.Dynview_Math_Table_Descriptor {

    result := core.Dynview_Math_Table_Descriptor{
        rows = int(descriptor.rows),
        columns = int(descriptor.columns),
        cell_style = core.Dynview_Math_Style_Level(descriptor.cell_style),
        row_spacing = core.Dynview_Math_Table_Row_Spacing(descriptor.row_spacing),
    }
    for alignment, index in descriptor.column_alignments {
        result.column_alignments[index] =
            core.Dynview_Matrix_Column_Alignment(alignment)
    }
    for gap, index in descriptor.column_boundary_gaps {
        result.column_boundary_gaps[index] = {
            gap.value, core.Dynview_Math_Length_Unit(gap.unit)}
        result.vertical_rule_counts[index] = u8(descriptor.vertical_rule_counts[index])
    }
    for gap, index in descriptor.row_extra_gaps {
        result.row_extra_gaps[index] = {
            gap.value, core.Dynview_Math_Length_Unit(gap.unit)}
    }
    for count, index in descriptor.horizontal_rule_counts {
        result.horizontal_rule_counts[index] = u8(count)
    }
    return result
}

//   Validate and append all block-local table descriptors as one native prefix.
dynview_import_math_table_descriptors :: proc(
    cache: ^core.Dynview_Compile_Cache,
    descriptors: [^]Bridge_Dynview_Math_Table_Descriptor,
    descriptor_count: int) -> i32 {

    if descriptor_count < 0 || (descriptor_count > 0 && descriptors == nil) ||
        cache^.math_table_descriptor_count + descriptor_count >
            core.DYNVIEW_MAX_MATH_TABLE_DESCRIPTORS {
        return BRIDGE_STATUS_INVALID_ARGUMENT
    }
    start := cache^.math_table_descriptor_count
    for descriptor_index in 0..<descriptor_count {
        descriptor := descriptors[descriptor_index]
        if !dynview_math_table_descriptor_valid(descriptor) {
            return BRIDGE_STATUS_INVALID_ARGUMENT
        }
        cache^.math_table_descriptors[start + descriptor_index] =
            dynview_math_table_descriptor_from_bridge(descriptor)
    }
    cache^.math_table_descriptor_count += descriptor_count
    return BRIDGE_STATUS_OK
}

//   Convert bridge decoration integer values to label decoration enum values.
//
// Parameters:
//   - kind: Bridge decoration constant encoded as i32.
//
// Returns:
//   - Matching label decoration enum value, or .None for unsupported values.
label_decoration_kind_from_i32 :: #force_inline proc(
    kind: i32) -> core.Shapes_Label_Decoration_Kind {
    switch kind {
    case BRIDGE_LABEL_DECORATION_PRIME:
        return .Prime
    case BRIDGE_LABEL_DECORATION_DOUBLEPRIME:
        return .Double_Prime
    case BRIDGE_LABEL_DECORATION_TRIPLEPRIME:
        return .Triple_Prime
    case BRIDGE_LABEL_DECORATION_HAT:
        return .Hat
    case BRIDGE_LABEL_DECORATION_BAR:
        return .Bar
    }

    return .None
}

//   Mark dynview stream state as failed and lock compile cache into invalid state.
//
// Notes:
//   - Preserves the first encountered error code for diagnostic stability.
dynview_fail :: #force_inline proc(runtime: ^core.Dynview_System, code: i32) -> i32 {
    runtime^.command_buffer.has_stream_error = true
    if runtime^.compile_cache.last_error_code == 0 {
        runtime^.compile_cache.last_error_code = code
    }
    runtime^.compile_cache.is_valid = false
    return code
}

//   Append one dynview command to the command buffer.
//
// Returns:
//   - BRIDGE_STATUS_OK when command is enqueued.
//   - BRIDGE_STATUS_OUT_OF_CAPACITY when command buffer is full.
dynview_push_command :: #force_inline proc(
    runtime: ^core.Dynview_System,
    command: core.Dynview_Command) -> i32 {

    buffer := &runtime^.command_buffer
    if buffer^.command_count >= len(buffer^.commands) {
        return dynview_fail(runtime, BRIDGE_STATUS_OUT_OF_CAPACITY)
    }

    buffer^.commands[buffer^.command_count] = command
    buffer^.command_count += 1
    runtime^.compile_cache.is_valid = false
    return BRIDGE_STATUS_OK
}

//   Append text bytes into dynview payload storage and return payload span.
//
// Parameters:
//   - text: Text payload to append to the shared dynview byte buffer.
//   - offset_out: Receives start offset of appended bytes.
//   - count_out: Receives appended byte count.
//
// Returns:
//   - BRIDGE_STATUS_OK when payload is appended.
//   - BRIDGE_STATUS_OUT_OF_CAPACITY when byte buffer has insufficient space.
dynview_append_text_payload :: #force_inline proc(
    runtime: ^core.Dynview_System,
    text: string,
    offset_out, count_out: ^int) -> i32 {

    buffer := &runtime^.command_buffer
    text_len := len(text)
    if buffer^.text_bytes_len + text_len > len(buffer^.text_bytes) {
        return dynview_fail(runtime, BRIDGE_STATUS_OUT_OF_CAPACITY)
    }

    start := buffer^.text_bytes_len
    for i in 0..<text_len {
        buffer^.text_bytes[start + i] = text[i]
    }

    buffer^.text_bytes_len += text_len
    offset_out^ = start
    count_out^ = text_len
    return BRIDGE_STATUS_OK
}

//   Convert a bridge math-op kind into the matching dynview command kind.
//
// Notes:
//   - Unsupported bridge kinds fall back to a text run so the importer can keep
//     making progress instead of failing the whole program.
dynview_math_command_kind_from_bridge :: #force_inline proc(
    kind: i32) -> (core.Dynview_Command_Kind, bool) {
    if kind < 1 || kind > BRIDGE_DYNVIEW_MATH_OP_MAX {
        return .Text_Run, false
    }
    kinds := BRIDGE_DYNVIEW_OP_KIND_TO_COMMAND
    return kinds[kind], true
}

//   Return whether an op's text spans fit inside the shared text blob.
//
// Notes:
//   - Each span is checked against the shared blob bounds before the importer
//     emits any dynview command using the payload offsets.
dynview_math_op_spans_valid :: #force_inline proc(
    op: Bridge_Dynview_Math_Op, blob_count: int) -> bool {

    spans := [4][2]i32{
        {op.text_offset, op.text_len},
        {op.index_text_offset, op.index_text_len},
        {op.sup_text_offset, op.sup_text_len},
        {op.sub_text_offset, op.sub_text_len},
    }
    for span in spans {
        if span[0] < 0 || span[1] < 0 {
            return false
        }
        if int(span[0] + span[1]) > blob_count {
            return false
        }
    }
    return true
}

//   Validate fields whose meaning depends on the bridge operation kind.
dynview_math_op_kind_semantics_valid :: #force_inline proc(
    op: Bridge_Dynview_Math_Op) -> bool {

    if op.kind == BRIDGE_DYNVIEW_MATH_OP_LARGE_OP_RECURSIVE {
        return op.atom_class == BRIDGE_DYNVIEW_MATH_ATOM_OP &&
            op.large_op_kind > 0 &&
            op.large_op_kind <= BRIDGE_DYNVIEW_LARGE_OP_KIND_MAX &&
            op.operator_growth >= BRIDGE_DYNVIEW_OPERATOR_GROWTH_NONE &&
            op.operator_growth <= BRIDGE_DYNVIEW_OPERATOR_GROWTH_DISPLAY &&
            op.operator_limits >= BRIDGE_DYNVIEW_OPERATOR_LIMITS_SIDE &&
            op.operator_limits <= BRIDGE_DYNVIEW_OPERATOR_LIMITS_STACKED
    }
    if op.kind == BRIDGE_DYNVIEW_MATH_OP_STYLE_OVERRIDE_RECURSIVE {
        return op.atom_class == BRIDGE_DYNVIEW_MATH_ATOM_INNER &&
            op.radical_mode >= 0 && op.radical_mode <= 3 &&
            op.large_op_kind == 0 &&
            op.operator_growth == BRIDGE_DYNVIEW_OPERATOR_GROWTH_NONE &&
            op.operator_limits == BRIDGE_DYNVIEW_OPERATOR_LIMITS_NONE
    }
    if op.kind == BRIDGE_DYNVIEW_MATH_OP_STRETCH_DELIMITER_RECURSIVE {
        return op.large_op_kind == 0 && op.operator_growth >= 0 &&
            op.operator_growth <= 4 && op.operator_limits >= 0 &&
            op.operator_limits <= 1
    }
    if op.kind == BRIDGE_DYNVIEW_MATH_OP_STACK_RECURSIVE {
        return op.large_op_kind == 0 && op.operator_growth == 0 &&
            op.operator_limits >= 0 && op.operator_limits <= 2
    }
    return op.large_op_kind == 0 &&
        op.operator_growth == BRIDGE_DYNVIEW_OPERATOR_GROWTH_NONE &&
        op.operator_limits == BRIDGE_DYNVIEW_OPERATOR_LIMITS_NONE
}

//   Return whether one bridge op carries a valid atom/glue combination.
dynview_math_op_semantics_valid :: #force_inline proc(
    op: Bridge_Dynview_Math_Op) -> bool {

    if op.atom_class < BRIDGE_DYNVIEW_MATH_ATOM_NONE ||
        op.atom_class > BRIDGE_DYNVIEW_MATH_ATOM_MAX ||
        op.glue_kind < BRIDGE_DYNVIEW_MATH_GLUE_NONE ||
        op.glue_kind > BRIDGE_DYNVIEW_MATH_GLUE_MAX {
        return false
    }
    if op.glue_kind != BRIDGE_DYNVIEW_MATH_GLUE_NONE {
        return op.atom_class == BRIDGE_DYNVIEW_MATH_ATOM_NONE
    }
    if op.atom_class == BRIDGE_DYNVIEW_MATH_ATOM_NONE {
        return false
    }
    return dynview_math_op_kind_semantics_valid(op)
}

//   Require table descriptor references only on matrix operations.
dynview_math_op_table_reference_valid :: #force_inline proc(
    op: Bridge_Dynview_Math_Op,
    command_kind: core.Dynview_Command_Kind,
    descriptor_count: int) -> bool {

    if command_kind == .Matrix {
        return op.table_descriptor_index >= 0 &&
            int(op.table_descriptor_index) < descriptor_count
    }
    return op.table_descriptor_index == -1
}

//   Import one recursive child program into the dynview compile cache.
//
// Notes:
//   - The helper reserves the next available program id and reuses the shared
//     recursive importer to pull the requested subtree into the cache.
dynview_import_child_program :: proc(
    ctx: Dynview_Import_Context,
    direct_count: int) -> (program_id: i32, status: i32) {

    if direct_count <= 0 || ctx.next_program_id == nil {
        return 0, BRIDGE_STATUS_INVALID_ARGUMENT
    }
    if ctx.next_program_id^ >= core.DYNVIEW_MAX_MATH_PROGRAMS {
        return 0, BRIDGE_STATUS_INVALID_ARGUMENT
    }

    host_program_id := ctx.next_program_id^
    ctx.next_program_id^ += 1
    child_status: i32 = dynview_import_math_program_from_ops(ctx,
        direct_count, host_program_id)
    if child_status != BRIDGE_STATUS_OK {
        return 0, child_status
    }

    return i32(host_program_id), BRIDGE_STATUS_OK
}

//   Import the numerator and denominator subprograms for a fraction op.
//
// Notes:
//   - The fraction branches are imported from the same flat bridge stream.
//   - The helper advances the shared cursor and program allocation state for both
//     children before returning the assigned program ids.
dynview_import_fraction_children :: proc(
    ctx: Dynview_Import_Context,
    op: Bridge_Dynview_Math_Op) -> Dynview_Imported_Children {

    numerator_direct_count := int(op.child_program_id)
    denominator_direct_count := int(op.secondary_child_program_id)
    if numerator_direct_count <= 0 || denominator_direct_count <= 0 {
        return Dynview_Imported_Children{0, 0, 0, BRIDGE_STATUS_INVALID_ARGUMENT}
    }
    if ctx.next_program_id^ + 1 >= core.DYNVIEW_MAX_MATH_PROGRAMS {
        return Dynview_Imported_Children{0, 0, 0, BRIDGE_STATUS_INVALID_ARGUMENT}
    }

    numerator_result, numerator_status := dynview_import_child_program(ctx,
        numerator_direct_count)
    if numerator_status != BRIDGE_STATUS_OK {
        return Dynview_Imported_Children{0, 0, 0, numerator_status}
    }

    denominator_result, denominator_status := dynview_import_child_program(ctx,
        denominator_direct_count)
    if denominator_status != BRIDGE_STATUS_OK {
        return Dynview_Imported_Children{0, 0, 0, denominator_status}
    }

    return Dynview_Imported_Children{
        numerator_result,
        denominator_result,
        0,
        BRIDGE_STATUS_OK,
    }
}

//   Import up to three direct child programs in preorder.
dynview_import_ordered_children :: proc(
    ctx: Dynview_Import_Context,
    op: Bridge_Dynview_Math_Op,
    require_primary: bool) -> Dynview_Imported_Children {

    counts := [3]int{
        int(op.child_program_id),
        int(op.secondary_child_program_id),
        int(op.tertiary_child_program_id),
    }
    if require_primary && counts[0] <= 0 {
        return Dynview_Imported_Children{0, 0, 0, BRIDGE_STATUS_INVALID_ARGUMENT}
    }
    ids: [3]i32
    for count, index in counts {
        if count <= 0 {
            continue
        }
        child_id, child_status := dynview_import_child_program(ctx, count)
        if child_status != BRIDGE_STATUS_OK {
            return Dynview_Imported_Children{0, 0, 0, child_status}
        }
        ids[index] = child_id
    }
    return Dynview_Imported_Children{ids[0], ids[1], ids[2], BRIDGE_STATUS_OK}
}

//   Import one required direct child program from an operation payload.
dynview_import_direct_child :: proc(
    ctx: Dynview_Import_Context,
    child_count: int) -> Dynview_Imported_Children {

    if child_count <= 0 {
        return {0, 0, 0, BRIDGE_STATUS_INVALID_ARGUMENT}
    }
    child_id, child_status := dynview_import_child_program(ctx, child_count)
    return {child_id, 0, 0, child_status}
}

//   Import an optional direct child, preserving an empty successful result.
dynview_import_optional_child :: proc(
    ctx: Dynview_Import_Context,
    child_count: int) -> Dynview_Imported_Children {

    if child_count <= 0 {
        return {0, 0, 0, BRIDGE_STATUS_OK}
    }
    return dynview_import_direct_child(ctx, child_count)
}

//   Validate a matrix descriptor's cell count and import its direct child program.
dynview_import_matrix_child :: proc(
    ctx: Dynview_Import_Context,
    op: Bridge_Dynview_Math_Op) -> Dynview_Imported_Children {

    child_count := int(op.child_program_id)
    descriptor := ctx.table_descriptors[op.table_descriptor_index]
    if child_count != int(descriptor.rows * descriptor.columns) {
        return {0, 0, 0, BRIDGE_STATUS_INVALID_ARGUMENT}
    }
    return dynview_import_direct_child(ctx, child_count)
}

//   Resolve the child program ids for one recursive math op.
//
// Notes:
//   - Child-bearing kinds import their subprograms from the shared flat stream;
//     leaf kinds keep their incoming child id and a zero secondary id.
dynview_import_op_children :: proc(
    ctx: Dynview_Import_Context,
    command_kind: core.Dynview_Command_Kind,
    op: Bridge_Dynview_Math_Op) -> Dynview_Imported_Children {

    child_direct_count := int(op.child_program_id)
    switch command_kind {
    case .Script_Attach, .Radical_Bar:
        return dynview_import_ordered_children(ctx, op, true)
    case .Large_Op:
        if child_direct_count > 0 {
            return Dynview_Imported_Children{0, 0, 0, BRIDGE_STATUS_INVALID_ARGUMENT}
        }
        return dynview_import_ordered_children(ctx, op, false)
    case .Accent_Bar, .Style_Override:
        return dynview_import_direct_child(ctx, child_direct_count)
    case .Matrix:
        return dynview_import_matrix_child(ctx, op)
    case .Frac, .Stack:
        return dynview_import_fraction_children(ctx, op)
    case .Stretch_Delimiter:
        return dynview_import_optional_child(ctx, child_direct_count)
    case .Begin_Block, .End_Block, .Text_Run, .Math_Glyph_Run, .Math_Block,
        .Copyable_Text_Run, .Line_Break, .Divider,
        .Inline_Line, .Inline_Box, .Inline_Circle, .Inline_Filled_Box,
        .Inline_Filled_Circle, .Inline_Pie_Section, .Inline_Perpendicular,
        .Inline_Triangle, .Inline_Pentagon:
    }
    return Dynview_Imported_Children{
        i32(op.child_program_id), 0, 0, BRIDGE_STATUS_OK}
}

//   Publish blob-relative text spans from one imported math operation.
dynview_math_command_apply_text_spans :: proc(
    command: ^core.Dynview_Command,
    op: Bridge_Dynview_Math_Op,
    blob_offset: int) {

    command^.text_offset = blob_offset + int(op.text_offset)
    command^.text_len = int(op.text_len)
    command^.script_base_text_offset = blob_offset + int(op.text_offset)
    command^.script_base_text_len = int(op.text_len)
    command^.script_sup_text_offset = blob_offset + int(op.sup_text_offset)
    command^.script_sup_text_len = int(op.sup_text_len)
    command^.script_sub_text_offset = blob_offset + int(op.sub_text_offset)
    command^.script_sub_text_len = int(op.sub_text_len)
    command^.radical_index_text_offset = blob_offset + int(op.index_text_offset)
    command^.radical_index_text_len = int(op.index_text_len)
}

//   Build the compiled dynview command record for one imported math op.
dynview_math_command_from_op :: proc(
    op: Bridge_Dynview_Math_Op,
    command_kind: core.Dynview_Command_Kind,
    children: Dynview_Imported_Children,
    import_ctx: Dynview_Command_Import_Context) -> core.Dynview_Command {

    table_descriptor_index: i32 = -1
    if command_kind == .Matrix {
        table_descriptor_index =
            i32(import_ctx.table_descriptor_base) + op.table_descriptor_index
    }
    command := core.Dynview_Command{
        kind = command_kind,
        math_atom_class = core.Dynview_Math_Atom_Class(op.atom_class),
        math_glue_kind = core.Dynview_Math_Glue_Kind(op.glue_kind),
        block_id = import_ctx.block_id,
        style_id = op.style_id,
        math_program_id = children.child_program_id,
        secondary_math_program_id = children.secondary_child_program_id,
        tertiary_math_program_id = children.tertiary_child_program_id,
        script_style_id = op.script_style_id,
        script_scale = op.script_scale,
        script_sup_raise = op.script_sup_raise,
        script_sub_drop = op.script_sub_drop,
        script_gap = op.script_gap,
        accent_mode = op.accent_mode,
        radical_mode = op.radical_mode,
        large_op_kind = op.large_op_kind,
        operator_growth = op.operator_growth,
        operator_limits = op.operator_limits,
        table_descriptor_index = table_descriptor_index,
        accent_style_id = op.accent_style_id,
        accent_thickness = op.accent_thickness,
        accent_offset = op.accent_offset,
    }
    dynview_math_command_apply_text_spans(&command, op, import_ctx.blob_offset)
    return command
}

//   Read and validate the next math op from the flat stream, advancing the cursor.
dynview_read_validated_op :: proc(
    ops: [^]Bridge_Dynview_Math_Op,
    op_count: int,
    cursor: ^int,
    blob_count: int,
    table_descriptor_count: int) -> Dynview_Validated_Op {

    if cursor^ >= op_count {
        return Dynview_Validated_Op{{}, .Text_Run, BRIDGE_STATUS_INVALID_ARGUMENT}
    }

    op := ops[cursor^]
    cursor^ += 1
    command_kind, ok := dynview_math_command_kind_from_bridge(op.kind)
    if !ok || !dynview_math_op_spans_valid(op, blob_count) ||
        !dynview_math_op_semantics_valid(op) ||
        !dynview_math_op_table_reference_valid(
            op, command_kind, table_descriptor_count) {
        return Dynview_Validated_Op{{}, .Text_Run, BRIDGE_STATUS_INVALID_ARGUMENT}
    }
    return Dynview_Validated_Op{op, command_kind, BRIDGE_STATUS_OK}
}

//   Import a single math op into one reserved command slot.
dynview_import_one_op :: proc(
    ctx: Dynview_Import_Context,
    validated: Dynview_Validated_Op,
    command_slot: int) -> i32 {

    children := dynview_import_op_children(ctx, validated.kind, validated.op)
    if children.status != BRIDGE_STATUS_OK {
        return children.status
    }

    ctx.cache^.math_commands[command_slot] =
        dynview_math_command_from_op(validated.op, validated.kind, children, {
            ctx.block_id, ctx.blob_offset, ctx.table_descriptor_base})
    return BRIDGE_STATUS_OK
}

//   Import one math program from the flat bridge op stream.
//
// Notes:
//   - The helper reserves command slots for the requested subtree size and then
//     walks the bridge ops into the dynview compile cache.
dynview_import_math_program_from_ops :: proc(
    ctx: Dynview_Import_Context,
    direct_count: int,
    program_id: int) -> i32 {

    if direct_count <= 0 || ctx.cache == nil || ctx.cursor == nil ||
        ctx.next_program_id == nil {
        return BRIDGE_STATUS_INVALID_ARGUMENT
    }

    command_start := ctx.cache^.math_command_count
    if command_start + direct_count > core.DYNVIEW_MAX_MATH_COMMANDS {
        return BRIDGE_STATUS_OUT_OF_CAPACITY
    }
    ctx.cache^.math_command_count += direct_count

    for local_index in 0..<direct_count {
        validated := dynview_read_validated_op(ctx.ops, ctx.op_count, ctx.cursor,
            ctx.blob_count, ctx.table_descriptor_count)
        if validated.status != BRIDGE_STATUS_OK {
            return validated.status
        }

        status := dynview_import_one_op(ctx, validated,
            command_start + local_index)
        if status != BRIDGE_STATUS_OK {
            return status
        }
    }

    ctx.cache^.math_programs[program_id] = core.Dynview_Math_Program{
        valid = true,
        command_start = command_start,
        command_count = direct_count,
    }
    return BRIDGE_STATUS_OK
}

//   Return a pointer to the dynview runtime for the current bridge state.
//
// Notes:
//   - The helper reuses the bridge state's saved context so the caller can access
//     the active dynview runtime without reaching into the state internals.
dynview_require_runtime :: proc(
    state: ^core.Euclid_General_State,
    runtime_out: ^^core.Dynview_System) -> i32 {

    if state == nil || runtime_out == nil {
        return BRIDGE_STATUS_INVALID_ARGUMENT
    }

    context = state^.saved_context
    runtime_out^ = state^.dynview_emit_target
    if runtime_out^ == nil {
        runtime_out^ = &state^.dynview
    }
    return BRIDGE_STATUS_OK
}

//   Return a pointer to the active dynview command buffer.
//
// Notes:
//   - The helper exposes the current command buffer while optionally enforcing
//     that a dynview block is already open before commands are appended.
dynview_require_buffer :: proc(
    runtime: ^core.Dynview_System,
    buffer_out: ^^core.Dynview_Command_Buffer,
    require_open_block: bool) -> i32 {

    if runtime == nil || buffer_out == nil {
        return BRIDGE_STATUS_INVALID_ARGUMENT
    }
    if !runtime^.enabled {
        return BRIDGE_STATUS_OK
    }

    buffer_out^ = &runtime^.command_buffer
    buffer := buffer_out^
    if require_open_block && !buffer^.stream_open_block {
        return dynview_fail(runtime, BRIDGE_STATUS_ILLEGAL_STATE)
    }
    return BRIDGE_STATUS_OK
}

//   Count the extra math programs and commands needed by recursive ops.
//
// Notes:
//   - Recursive math nodes reserve additional program and command slots based on
//     their child structure so the compile cache can be sized up front.
dynview_count_recursive_math_capacity :: proc(
    ops: [^]Bridge_Dynview_Math_Op,
    op_count: int) -> (extra_programs: int, extra_commands: int) {

    for i in 0..<op_count {
        switch ops[i].kind {
        case BRIDGE_DYNVIEW_MATH_OP_ACCENT_BAR_RECURSIVE,
            BRIDGE_DYNVIEW_MATH_OP_RADICAL_BAR_RECURSIVE,
            BRIDGE_DYNVIEW_MATH_OP_SCRIPT_ATTACH_RECURSIVE:
            extra_programs += 1
            extra_commands += 1
        case BRIDGE_DYNVIEW_MATH_OP_FRACTION_RECURSIVE:
            extra_programs += 2
            extra_commands += 2
        case BRIDGE_DYNVIEW_MATH_OP_STACK_RECURSIVE:
            extra_programs += 2
            extra_commands += 2
        case BRIDGE_DYNVIEW_MATH_OP_STRETCH_DELIMITER_RECURSIVE,
            BRIDGE_DYNVIEW_MATH_OP_MATRIX_RECURSIVE,
            BRIDGE_DYNVIEW_MATH_OP_STYLE_OVERRIDE_RECURSIVE:
            if ops[i].child_program_id > 0 {
                extra_programs += 1
                extra_commands += 1
            }
        }
    }

    return
}