package bridge

import "../core"

import "core:testing"

View_Snapshot_Record_Test_Payloads :: struct {
    commands: []core.Dynview_Command,
    programs: []core.Dynview_Math_Program,
    math_commands: []core.Dynview_Command,
    nodes: []core.Dynview_Math_Node,
}

//   Allocate a service with initialized snapshot arenas but no worker or channels.
view_snapshot_arena_test_service :: proc(t: ^testing.T) -> ^Julia_Runtime_Service {
    service := new(Julia_Runtime_Service)
    testing.expect(t, service != nil)
    testing.expect(t, view_snapshot_slots_init(service))
    return service
}

//   Destroy test-owned snapshot arenas and service storage.
view_snapshot_arena_test_service_destroy :: proc(service: ^Julia_Runtime_Service) {
    view_snapshot_slots_destroy(service)
    free(service)
}

//   Verify one free slot prepares every future payload builder at fixed limits.
@(test)
view_snapshot_free_slot_prepares_all_builders :: proc(t: ^testing.T) {
    service := view_snapshot_arena_test_service(t)
    defer view_snapshot_arena_test_service_destroy(service)
    slot := &service^.view_snapshots[0]

    testing.expect(t, prepare_view_snapshot_slot(slot))

    testing.expect_value(t, slot^.arena.reset_count, u64(1))
    testing.expect_value(t, slot^.fallback_text_builder.max_count,
        VIEW_SNAPSHOT_TEXT_CAPACITY)
    testing.expect_value(t, slot^.command_text_builder.max_count,
        core.DYNVIEW_MAX_TEXT_BYTES)
    testing.expect_value(t, slot^.command_builder.max_count,
        core.DYNVIEW_MAX_COMMANDS)
    testing.expect_value(t, slot^.math_program_builder.max_count,
        core.DYNVIEW_MAX_MATH_PROGRAMS)
    testing.expect_value(t, slot^.math_table_descriptor_builder.max_count,
        core.DYNVIEW_MAX_MATH_TABLE_DESCRIPTORS)
    testing.expect_value(t, slot^.math_command_builder.max_count,
        core.DYNVIEW_MAX_MATH_COMMANDS)
    testing.expect_value(t, slot^.math_node_builder.max_count,
        core.DYNVIEW_MAX_MATH_NODES)
}

//   Verify slot-owned builders reject overflow transactionally at their hard limit.
@(test)
view_snapshot_builder_saturation_preserves_payload :: proc(t: ^testing.T) {
    service := view_snapshot_arena_test_service(t)
    defer view_snapshot_arena_test_service_destroy(service)
    slot := &service^.view_snapshots[0]
    testing.expect(t, prepare_view_snapshot_slot(slot))
    bytes := make([]u8, VIEW_SNAPSHOT_TEXT_CAPACITY)
    defer delete(bytes)
    bytes[len(bytes) - 1] = 'z'

    testing.expect_value(t, core.bounded_byte_builder_append(
        &slot^.fallback_text_builder, bytes), core.Bounded_Builder_Status.Ok)
    testing.expect_value(t, core.bounded_byte_builder_append(
        &slot^.fallback_text_builder, []u8{'x'}),
        core.Bounded_Builder_Status.Limit_Exceeded)
    testing.expect_value(t, slot^.fallback_text_builder.count, len(bytes))
    testing.expect_value(t, slot^.fallback_text_builder.storage[len(bytes) - 1], u8('z'))
}

//   Verify text transfer truncates fallback, admits exact semantic capacity, and seals.
@(test)
view_snapshot_text_transfer_enforces_capacity_and_sealing :: proc(t: ^testing.T) {
    service := view_snapshot_arena_test_service(t)
    defer view_snapshot_arena_test_service_destroy(service)
    fallback_bytes: [VIEW_SNAPSHOT_TEXT_CAPACITY + 1]u8
    semantic_bytes: [core.DYNVIEW_MAX_TEXT_BYTES]u8
    fallback_bytes[VIEW_SNAPSHOT_TEXT_CAPACITY - 1] = 'f'
    semantic_bytes[len(semantic_bytes) - 1] = 's'
    slot := &service^.view_snapshots[0]
    testing.expect(t, prepare_view_snapshot_slot(slot))

    testing.expect(t, build_view_snapshot_text_payloads(
        slot, string(fallback_bytes[:]), semantic_bytes[:]))

    testing.expect_value(t, len(slot^.fallback_text), VIEW_SNAPSHOT_TEXT_CAPACITY)
    testing.expect_value(t, len(slot^.command_text), core.DYNVIEW_MAX_TEXT_BYTES)
    testing.expect_value(t, slot^.fallback_text[len(slot^.fallback_text) - 1], u8('f'))
    testing.expect_value(t, slot^.command_text[len(slot^.command_text) - 1], u8('s'))
    testing.expect(t, slot^.fallback_text_builder.sealed)
    testing.expect(t, slot^.command_text_builder.sealed)

    overflow: [core.DYNVIEW_MAX_TEXT_BYTES + 1]u8
    overflow_slot := &service^.view_snapshots[1]
    testing.expect(t, prepare_view_snapshot_slot(overflow_slot))
    testing.expect(t, !build_view_snapshot_text_payloads(
        overflow_slot, "fallback", overflow[:]))
    testing.expect(t, !overflow_slot^.fallback_text_builder.sealed)
    testing.expect(t, !overflow_slot^.command_text_builder.sealed)
    testing.expect_value(t, len(overflow_slot^.fallback_text), 0)
    testing.expect_value(t, len(overflow_slot^.command_text), 0)
}

//   Verify all record families admit their exact limits, preserve order, and seal.
view_snapshot_expect_record_limits :: proc(
    t: ^testing.T,
    slot: ^View_Snapshot,
    payloads: View_Snapshot_Record_Test_Payloads) {
    testing.expect_value(t, len(slot^.commands), len(payloads.commands))
    testing.expect_value(t, len(slot^.math_programs), len(payloads.programs))
    testing.expect_value(t, len(slot^.math_commands), len(payloads.math_commands))
    testing.expect_value(t, len(slot^.math_nodes), len(payloads.nodes))
    testing.expect_value(t, slot^.commands[0].block_id, i32(11))
    testing.expect_value(t, slot^.commands[len(payloads.commands) - 1].block_id, i32(12))
    testing.expect_value(t, slot^.math_programs[0].root_node_index, 21)
    testing.expect_value(t,
        slot^.math_programs[len(payloads.programs) - 1].root_node_index, 22)
    testing.expect_value(t, slot^.math_commands[0].block_id, i32(31))
    testing.expect_value(t,
        slot^.math_commands[len(payloads.math_commands) - 1].block_id, i32(32))
    testing.expect_value(t, slot^.math_nodes[0].style_id, i32(41))
    testing.expect_value(t, slot^.math_nodes[len(payloads.nodes) - 1].style_id, i32(42))
    testing.expect(t, slot^.command_builder.sealed &&
        slot^.math_program_builder.sealed && slot^.math_command_builder.sealed &&
        slot^.math_node_builder.sealed)
}

//   Verify all record families admit their exact limits, preserve order, and seal.
@(test)
view_snapshot_record_transfer_accepts_exact_limits :: proc(t: ^testing.T) {
    service := view_snapshot_arena_test_service(t)
    defer view_snapshot_arena_test_service_destroy(service)
    slot := &service^.view_snapshots[0]
    testing.expect(t, prepare_view_snapshot_slot(slot))
    commands := make([]core.Dynview_Command, core.DYNVIEW_MAX_COMMANDS)
    programs := make([]core.Dynview_Math_Program, core.DYNVIEW_MAX_MATH_PROGRAMS)
    math_commands := make([]core.Dynview_Command, core.DYNVIEW_MAX_MATH_COMMANDS)
    nodes := make([]core.Dynview_Math_Node, core.DYNVIEW_MAX_MATH_NODES)
    defer delete(commands)
    defer delete(programs)
    defer delete(math_commands)
    defer delete(nodes)
    commands[0].block_id = 11
    commands[len(commands) - 1].block_id = 12
    programs[0].root_node_index = 21
    programs[len(programs) - 1].root_node_index = 22
    math_commands[0].block_id = 31
    math_commands[len(math_commands) - 1].block_id = 32
    nodes[0].style_id = 41
    nodes[len(nodes) - 1].style_id = 42

    testing.expect(t, build_view_snapshot_record_payloads(
        slot, {commands = commands, math_programs = programs,
            math_commands = math_commands, math_nodes = nodes}))
    view_snapshot_expect_record_limits(t, slot, {
        commands, programs, math_commands, nodes})
}

//   Require an overflowing record transaction to publish no slice or seal.
view_snapshot_record_overflow_rejected :: proc(
    t: ^testing.T, slot: ^View_Snapshot,
    payloads: View_Snapshot_Record_Test_Payloads) {

    slot^.state = .Free
    testing.expect(t, prepare_view_snapshot_slot(slot))
    testing.expect(t, !build_view_snapshot_record_payloads(
        slot, {commands = payloads.commands, math_programs = payloads.programs,
            math_commands = payloads.math_commands, math_nodes = payloads.nodes}))
    testing.expect(t, !slot^.command_builder.sealed &&
        !slot^.math_program_builder.sealed && !slot^.math_command_builder.sealed &&
        !slot^.math_node_builder.sealed)
    testing.expect_value(t, len(slot^.commands), 0)
    testing.expect_value(t, len(slot^.math_programs), 0)
    testing.expect_value(t, len(slot^.math_commands), 0)
    testing.expect_value(t, len(slot^.math_nodes), 0)
}

//   Verify every record family rejects one element beyond its hard limit.
@(test)
view_snapshot_record_transfer_rejects_each_overflow :: proc(t: ^testing.T) {
    service := view_snapshot_arena_test_service(t)
    defer view_snapshot_arena_test_service_destroy(service)
    slot := &service^.view_snapshots[0]
    commands := make([]core.Dynview_Command, core.DYNVIEW_MAX_COMMANDS + 1)
    programs := make([]core.Dynview_Math_Program, core.DYNVIEW_MAX_MATH_PROGRAMS + 1)
    math_commands := make([]core.Dynview_Command,
        core.DYNVIEW_MAX_MATH_COMMANDS + 1)
    nodes := make([]core.Dynview_Math_Node, core.DYNVIEW_MAX_MATH_NODES + 1)
    defer delete(commands)
    defer delete(programs)
    defer delete(math_commands)
    defer delete(nodes)

    view_snapshot_record_overflow_rejected(t, slot, {commands = commands})
    view_snapshot_record_overflow_rejected(t, slot, {programs = programs})
    view_snapshot_record_overflow_rejected(
        t, slot, {math_commands = math_commands})
    view_snapshot_record_overflow_rejected(t, slot, {nodes = nodes})
}

//   Verify semantic document bytes and records reject one element beyond each limit.
@(test)
view_snapshot_document_transfer_rejects_overflow :: proc(t: ^testing.T) {
    service := view_snapshot_arena_test_service(t)
    defer view_snapshot_arena_test_service_destroy(service)
    slot := &service^.view_snapshots[0]
    document_text := make([]u8, core.DYNVIEW_MAX_DOCUMENT_BYTES + 1)
    documents := make([]core.Dynview_Document, core.DYNVIEW_MAX_DOCUMENTS + 1)
    blocks := make([]core.Dynview_Document_Block,
        core.DYNVIEW_MAX_DOCUMENT_BLOCKS + 1)
    items := make([]core.Dynview_Document_Inline,
        core.DYNVIEW_MAX_DOCUMENT_INLINES + 1)
    rows := make([]core.Dynview_Document_Display_Row,
        core.DYNVIEW_MAX_DOCUMENT_DISPLAY_ROWS + 1)
    defer delete(document_text)
    defer delete(documents)
    defer delete(blocks)
    defer delete(items)
    defer delete(rows)

    testing.expect(t, prepare_view_snapshot_slot(slot))
    testing.expect(t, !build_view_snapshot_record_payloads(
        slot, {document_text = document_text}))
    slot^.state = .Free
    testing.expect(t, prepare_view_snapshot_slot(slot))
    testing.expect(t, !build_view_snapshot_record_payloads(
        slot, {documents = documents}))
    slot^.state = .Free
    testing.expect(t, prepare_view_snapshot_slot(slot))
    testing.expect(t, !build_view_snapshot_record_payloads(
        slot, {document_blocks = blocks}))
    slot^.state = .Free
    testing.expect(t, prepare_view_snapshot_slot(slot))
    testing.expect(t, !build_view_snapshot_record_payloads(
        slot, {document_inlines = items}))
    slot^.state = .Free
    testing.expect(t, prepare_view_snapshot_slot(slot))
    testing.expect(t, !build_view_snapshot_record_payloads(
        slot, {document_display_rows = rows}))
}

// Verify display row ownership and math references cannot escape sealed records.
@(test)
view_snapshot_document_validation_rejects_malformed_display_rows :: proc(
    t: ^testing.T) {

    service := view_snapshot_arena_test_service(t)
    defer view_snapshot_arena_test_service_destroy(service)
    slot := &service^.view_snapshots[0]
    testing.expect(t, prepare_view_snapshot_slot(slot))
    testing.expect(t, build_view_snapshot_text_payloads(slot, "fallback", nil))
    programs := []core.Dynview_Math_Program{{
        valid = true, root_node_index = 0, node_count = 1}}
    nodes := []core.Dynview_Math_Node{{kind = .Glyph_Run}}
    documents := []core.Dynview_Document{{source_count = 1, block_count = 1,
        display_row_count = 1}}
    blocks := []core.Dynview_Document_Block{{kind = .Display, source_count = 1,
        display_kind = .Equation, display_row_count = 1}}
    rows := []core.Dynview_Document_Display_Row{{source_count = 1,
        primary_program_id = 0, secondary_program_id = -1,
        alignment = .Center, number = 1}}
    testing.expect(t, build_view_snapshot_record_payloads(slot, {
        math_programs = programs, math_nodes = nodes, document_text = {'x'},
        documents = documents, document_blocks = blocks,
        document_display_rows = rows,
    }))
    testing.expect(t, view_snapshot_is_valid(slot))

    slot^.document_blocks[0].display_row_count = 2
    testing.expect(t, !view_snapshot_is_valid(slot))
    slot^.document_blocks[0].display_row_count = 1
    slot^.document_display_rows[0].primary_program_id = 1
    testing.expect(t, !view_snapshot_is_valid(slot))
}

//   Verify malformed semantic ownership ranges fail before publication.
@(test)
view_snapshot_document_validation_rejects_malformed_ranges :: proc(t: ^testing.T) {
    service := view_snapshot_arena_test_service(t)
    defer view_snapshot_arena_test_service_destroy(service)
    slot := &service^.view_snapshots[0]
    testing.expect(t, prepare_view_snapshot_slot(slot))
    testing.expect(t, build_view_snapshot_text_payloads(slot, "fallback", nil))
    document_text: string = "sourceplain"
    documents := []core.Dynview_Document{{
        source_count = 6, text_offset = 6, text_count = 5,
        block_count = 1, inline_count = 1}}
    blocks := []core.Dynview_Document_Block{{
        kind = .Paragraph, inline_count = 1, source_count = 6}}
    items := []core.Dynview_Document_Inline{{
        kind = .Text, source_count = 6, text_offset = 6, text_count = 5,
        math_program_id = -1}}
    testing.expect(t, build_view_snapshot_record_payloads(slot, {
        document_text = transmute([]u8)document_text,
        documents = documents,
        document_blocks = blocks,
        document_inlines = items,
    }))
    testing.expect(t, view_snapshot_is_valid(slot))

    slot^.document_blocks[0].inline_count = 2
    testing.expect(t, !view_snapshot_is_valid(slot))
    slot^.document_blocks[0].inline_count = 1
    slot^.document_inlines[0].text_offset = 5
    testing.expect(t, !view_snapshot_is_valid(slot))
    slot^.document_inlines[0].text_offset = 6
    slot^.documents[0].source_count = 12
    testing.expect(t, !view_snapshot_is_valid(slot))
}

//   Verify record validation rejects same-length slices outside sealed storage.
@(test)
view_snapshot_record_validation_rejects_forged_aliases :: proc(t: ^testing.T) {
    service := view_snapshot_arena_test_service(t)
    defer view_snapshot_arena_test_service_destroy(service)
    slot := &service^.view_snapshots[0]
    testing.expect(t, prepare_view_snapshot_slot(slot))
    testing.expect(t, build_view_snapshot_text_payloads(slot, "fallback", nil))
    commands := []core.Dynview_Command{{}}
    programs := []core.Dynview_Math_Program{{
        valid = true, root_node_index = 0, node_count = 1, command_count = 1}}
    math_commands := []core.Dynview_Command{{math_atom_class = .Ord}}
    nodes := []core.Dynview_Math_Node{{kind = .Glyph_Run}}
    testing.expect(t, build_view_snapshot_record_payloads(
        slot, {commands = commands, math_programs = programs,
            math_commands = math_commands, math_nodes = nodes}))
    testing.expect(t, view_snapshot_is_valid(slot))
    forged_commands := [1]core.Dynview_Command{commands[0]}
    forged_programs := [1]core.Dynview_Math_Program{programs[0]}
    forged_math_commands := [1]core.Dynview_Command{math_commands[0]}
    forged_nodes := [1]core.Dynview_Math_Node{nodes[0]}

    slot^.commands = forged_commands[:]
    testing.expect(t, !view_snapshot_is_valid(slot))
    slot^.commands = slot^.command_builder.storage[:1]
    slot^.math_programs = forged_programs[:]
    testing.expect(t, !view_snapshot_is_valid(slot))
    slot^.math_programs = slot^.math_program_builder.storage[:1]
    slot^.math_commands = forged_math_commands[:]
    testing.expect(t, !view_snapshot_is_valid(slot))
    slot^.math_commands = slot^.math_command_builder.storage[:1]
    slot^.math_nodes = forged_nodes[:]
    testing.expect(t, !view_snapshot_is_valid(slot))
}

//   Verify program and node corruption cannot reach display-owned storage.
view_snapshot_expect_malformed_math_rejected :: proc(
    t: ^testing.T,
    slot: ^View_Snapshot) {
    slot^.math_programs[0].command_count = 2
    testing.expect(t, !view_snapshot_is_valid(slot))
    slot^.math_programs[0].command_count = 1
    slot^.math_programs[0].node_start = 1
    testing.expect(t, !view_snapshot_is_valid(slot))
    slot^.math_programs[0].node_start = 0
    slot^.math_programs[0].root_node_index = 2
    testing.expect(t, !view_snapshot_is_valid(slot))
    slot^.math_programs[0].root_node_index = 0
    slot^.math_programs[0].copy_text_offset = 1
    testing.expect(t, !view_snapshot_is_valid(slot))
    slot^.math_programs[0].copy_text_offset = 0
    slot^.math_nodes[1].text_offset = 1
    testing.expect(t, !view_snapshot_is_valid(slot))
    slot^.math_nodes[1].text_offset = 0
    slot^.math_nodes[0].first_child = 2
    testing.expect(t, !view_snapshot_is_valid(slot))
    slot^.math_nodes[0] = {
        kind = .Fraction, numerator_child = 0, denominator_child = 2}
    testing.expect(t, !view_snapshot_is_valid(slot))
}

//   Verify program and node corruption cannot reach display-owned storage.
@(test)
view_snapshot_math_record_validation_rejects_malformed_structure :: proc(
    t: ^testing.T) {

    service := view_snapshot_arena_test_service(t)
    defer view_snapshot_arena_test_service_destroy(service)
    slot := &service^.view_snapshots[0]
    testing.expect(t, prepare_view_snapshot_slot(slot))
    text: string = "math"
    testing.expect(t, build_view_snapshot_text_payloads(
        slot, "", transmute([]u8)text))
    programs := []core.Dynview_Math_Program{{
        valid = true, root_node_index = 0, node_count = 2,
        command_count = 1, copy_text_len = 4}}
    nodes := []core.Dynview_Math_Node{
        {kind = .Sequence, first_child = 1, child_count = 1},
        {kind = .Glyph_Run, text_len = 4},
    }
    testing.expect(t, build_view_snapshot_record_payloads(
        slot, {math_programs = programs,
            math_commands = []core.Dynview_Command{{math_atom_class = .Ord}},
            math_nodes = nodes}))
    testing.expect(t, view_snapshot_is_valid(slot))
    view_snapshot_expect_malformed_math_rejected(t, slot)
}

//   Verify snapshot math semantics accept every class and reject malformed metadata.
@(test)
view_snapshot_math_semantics_validate_atom_and_glue_enums :: proc(t: ^testing.T) {
    for atom in core.Dynview_Math_Atom_Class.Ord..=core.Dynview_Math_Atom_Class.Inner {
        testing.expect(t, view_snapshot_math_command_semantics_are_valid({
            math_atom_class = atom,
        }))
    }
    for glue in core.Dynview_Math_Glue_Kind.Thick..=core.Dynview_Math_Glue_Kind.Thin {
        testing.expect(t, view_snapshot_math_command_semantics_are_valid({
            math_glue_kind = glue,
        }))
    }

    testing.expect(t, !view_snapshot_math_command_semantics_are_valid({}))
    testing.expect(t, !view_snapshot_math_command_semantics_are_valid({
        math_atom_class = .Ord,
        math_glue_kind = .Thick,
    }))
    testing.expect(t, !view_snapshot_math_command_semantics_are_valid({
        math_atom_class = core.Dynview_Math_Atom_Class(99),
    }))
    testing.expect(t, !view_snapshot_math_command_semantics_are_valid({
        math_glue_kind = core.Dynview_Math_Glue_Kind(99),
    }))
}

//   Verify pending, complete, and published slots cannot reset arena storage.
@(test)
view_snapshot_reset_requires_free_state :: proc(t: ^testing.T) {
    service := view_snapshot_arena_test_service(t)
    defer view_snapshot_arena_test_service_destroy(service)
    slot := &service^.view_snapshots[0]
    testing.expect(t, prepare_view_snapshot_slot(slot))
    testing.expect_value(t, core.bounded_byte_builder_append(
        &slot^.fallback_text_builder, []u8{'x'}), core.Bounded_Builder_Status.Ok)
    testing.expect(t, build_view_snapshot_record_payloads(
        slot, {commands = []core.Dynview_Command{{block_id = 7}}}))
    storage := raw_data(slot^.fallback_text_builder.storage)
    record_storage := raw_data(slot^.commands)

    guarded_states := []View_Snapshot_Slot_State{.Pending, .Complete, .Published}
    for state in guarded_states {
        slot^.state = state
        testing.expect(t, !prepare_view_snapshot_slot(slot))
        testing.expect_value(t, slot^.arena.reset_count, u64(1))
        testing.expect_value(t, raw_data(slot^.fallback_text_builder.storage), storage)
        testing.expect_value(t, raw_data(slot^.commands), record_storage)
    }

    slot^.state = .Free
    testing.expect(t, prepare_view_snapshot_slot(slot))
    testing.expect_value(t, slot^.arena.reset_count, u64(2))
    testing.expect_value(t, slot^.fallback_text_builder.count, 0)
    testing.expect_value(t, slot^.command_builder.count, 0)
    testing.expect_value(t, len(slot^.commands), 0)
    testing.expect(t, !slot^.command_builder.sealed)
}

//   Verify saturation never selects pending or published snapshot storage.
@(test)
view_snapshot_reservation_respects_slot_saturation :: proc(t: ^testing.T) {
    service := view_snapshot_arena_test_service(t)
    defer view_snapshot_arena_test_service_destroy(service)
    service^.view_snapshots[0].state = .Pending
    service^.view_snapshots[1].state = .Published

    testing.expect_value(t, reserve_view_snapshot(service), -1)
    service^.view_snapshots[0].state = .Free
    testing.expect_value(t, reserve_view_snapshot(service), 0)
}

//   Verify superseded completion storage remains intact until its next free reuse.
@(test)
view_snapshot_supersession_defers_arena_reset :: proc(t: ^testing.T) {
    service := view_snapshot_arena_test_service(t)
    defer view_snapshot_arena_test_service_destroy(service)
    older := &service^.view_snapshots[0]
    newer := &service^.view_snapshots[1]
    testing.expect(t, prepare_view_snapshot_slot(older))
    testing.expect(t, prepare_view_snapshot_slot(newer))
    testing.expect_value(t, core.bounded_byte_builder_append(
        &older^.fallback_text_builder, []u8{'o'}), core.Bounded_Builder_Status.Ok)
    storage := raw_data(older^.fallback_text_builder.storage)
    older^.state = .Complete
    older^.generation = 1
    newer^.state = .Complete
    newer^.generation = 2

    release_superseded_completed_view_snapshots(service, 1)

    testing.expect_value(t, older^.state, View_Snapshot_Slot_State.Free)
    testing.expect_value(t, raw_data(older^.fallback_text_builder.storage), storage)
    testing.expect_value(t, older^.arena.reset_count, u64(1))
    testing.expect(t, prepare_view_snapshot_slot(older))
    testing.expect_value(t, older^.arena.reset_count, u64(2))
}

//   Verify a reload makes completion stale without reclaiming worker-owned storage early.
@(test)
view_snapshot_reload_stale_completion_defers_arena_reset :: proc(t: ^testing.T) {
    service := view_snapshot_arena_test_service(t)
    defer view_snapshot_arena_test_service_destroy(service)
    state := new(core.Euclid_General_State)
    defer free(state)
    state^.julia_interface = &state^.julia_interface_slots[0]
    animation := &state^.julia_interface^.null_animation
    state^.julia_interface^.current_animation = animation
    slot := &service^.view_snapshots[0]
    testing.expect(t, prepare_view_snapshot_slot(slot))
    slot^.state = .Complete
    slot^.animation = animation
    slot^.runtime_generation = 4
    slot^.animation_generation = 7
    service^.runtime_generation = 5
    service^.animation_generation = 7

    testing.expect(t, !view_snapshot_matches_current(state, service, slot))
    testing.expect_value(t, slot^.arena.reset_count, u64(1))
    slot^.state = .Free
    testing.expect(t, prepare_view_snapshot_slot(slot))
    testing.expect_value(t, slot^.arena.reset_count, u64(2))
}

//   Verify stale published storage becomes reusable without resetting while displayed.
@(test)
view_snapshot_stale_publication_defers_arena_reset :: proc(t: ^testing.T) {
    service := view_snapshot_arena_test_service(t)
    defer view_snapshot_arena_test_service_destroy(service)
    state := new(core.Euclid_General_State)
    defer free(state)
    state^.julia_interface = &state^.julia_interface_slots[0]
    state^.julia_runtime_service = service
    current_animation := &state^.julia_interface^.null_animation
    state^.julia_interface^.current_animation = current_animation
    published := &service^.view_snapshots[0]
    testing.expect(t, prepare_view_snapshot_slot(published))
    published^.state = .Published
    published^.animation = current_animation
    published^.runtime_generation = 1
    service^.runtime_generation = 2
    service^.published_view_snapshot_index = 0
    records := [1]core.Dynview_Command{{block_id = 9}}
    state^.dynview.content.commands = records[:]
    state^.dynview.command_buffer.command_view = records[:]

    clear_stale_published_view(state, service)

    testing.expect_value(t, published^.state, View_Snapshot_Slot_State.Free)
    testing.expect_value(t, published^.arena.reset_count, u64(1))
    testing.expect_value(t, service^.published_view_snapshot_index, -1)
    testing.expect_value(t, len(state^.dynview.content.commands), 0)
    testing.expect_value(t, len(state^.dynview.command_buffer.command_view), 0)
    testing.expect(t, prepare_view_snapshot_slot(published))
    testing.expect_value(t, published^.arena.reset_count, u64(2))
}

//   Verify shutdown release detaches every display alias before slot destruction.
@(test)
view_snapshot_shutdown_release_clears_published_views :: proc(t: ^testing.T) {
    service := view_snapshot_arena_test_service(t)
    defer view_snapshot_arena_test_service_destroy(service)
    state := new(core.Euclid_General_State)
    defer free(state)
    published := &service^.view_snapshots[0]
    testing.expect(t, prepare_view_snapshot_slot(published))
    testing.expect(t, build_view_snapshot_text_payloads(
        published, "fallback", nil))
    testing.expect(t, build_view_snapshot_record_payloads(
        published, {commands = []core.Dynview_Command{{block_id = 7}}}))
    install_view_snapshot_content(published, &state^.dynview)
    published^.state = .Published
    service^.published_view_snapshot_index = 0

    release_published_view_snapshot(state, service)

    testing.expect_value(t, published^.state, View_Snapshot_Slot_State.Free)
    testing.expect_value(t, service^.published_view_snapshot_index, -1)
    testing.expect_value(t, len(state^.dynview.content.commands), 0)
    testing.expect_value(t, len(state^.dynview.command_buffer.command_view), 0)
    testing.expect_value(t, len(state^.dynview.command_buffer.text_view), 0)
    testing.expect_value(t, published^.arena.reset_count, u64(1))
}

//   Verify teardown destroys every slot arena regardless of retained slot state.
@(test)
view_snapshot_slot_teardown_covers_all_states :: proc(t: ^testing.T) {
    service := view_snapshot_arena_test_service(t)
    service^.view_snapshots[0].state = .Pending
    service^.view_snapshots[1].state = .Published

    view_snapshot_slots_destroy(service)

    for &slot in service^.view_snapshots {
        testing.expect(t, !slot.arena.initialized)
        testing.expect_value(t, slot.arena.destroy_count, u64(1))
    }
    free(service)
}