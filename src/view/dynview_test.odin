package view

import "../diagnostics"

import "core:log"
import "core:math"
import "core:os"
import "core:strings"
import "core:testing"

import app_bridge "../bridge"
import app_core "../core"
import app_dyncompile "../dynview/compile"
import dyncore "../dynview/core"
import app_dynlayout "../dynview/layout"
import app_dynview "../dynview"
import app_math "../dynview/math"
import app_evidence_trace "../evidence/trace"
import app_grid "../grid"

View_Snapshot_Published_Expected :: struct {
    text: string,
    fallback_storage: [^]u8,
    record_storage: [^]app_core.Dynview_Command,
    block_id: i32,
}

View_Snapshot_Publication_Fixture :: struct {
    state: ^app_core.Euclid_General_State,
    service: ^app_bridge.Julia_Runtime_Service,
    animation: ^app_core.Euclid_Julia_Animation_Interface,
}

Copy_Hit_Target_Fixture :: struct {
    items: [2]app_core.Dynview_Layout_Item,
    lines: [6]app_core.Dynview_Layout_Line,
    layout: app_dyncompile.Copy_Hit_Target_Layout,
}

//   Initialize caller-owned bounded layout storage for direct layout unit tests.
dynview_test_layout_builders_init :: proc(
    t: ^testing.T,
    cache: ^app_core.Dynview_Compile_Cache,
    arena: ^app_core.Arena_Owner) {
    testing.expect(t, app_core.arena_owner_init(arena))
    testing.expect_value(t, app_dynlayout.layout_builders_init(cache, arena),
        dyncore.DYNVIEW_STATUS_OK)
}

//   Initialize all semantic record builders for one direct snapshot fixture.
view_snapshot_test_record_builders_init :: proc(
    t: ^testing.T, snapshot: ^app_bridge.View_Snapshot) {

    testing.expect_value(t, app_core.bounded_element_builder_init(
        &snapshot^.command_builder, app_core.DYNVIEW_MAX_COMMANDS,
        &snapshot^.arena), app_core.Bounded_Builder_Status.Ok)
    testing.expect_value(t, app_core.bounded_element_builder_init(
        &snapshot^.math_program_builder, app_core.DYNVIEW_MAX_MATH_PROGRAMS,
        &snapshot^.arena), app_core.Bounded_Builder_Status.Ok)
    testing.expect_value(t, app_core.bounded_element_builder_init(
        &snapshot^.math_table_descriptor_builder,
        app_core.DYNVIEW_MAX_MATH_TABLE_DESCRIPTORS,
        &snapshot^.arena), app_core.Bounded_Builder_Status.Ok)
    testing.expect_value(t, app_core.bounded_element_builder_init(
        &snapshot^.math_command_builder, app_core.DYNVIEW_MAX_MATH_COMMANDS,
        &snapshot^.arena), app_core.Bounded_Builder_Status.Ok)
    testing.expect_value(t, app_core.bounded_element_builder_init(
        &snapshot^.math_node_builder, app_core.DYNVIEW_MAX_MATH_NODES,
        &snapshot^.arena), app_core.Bounded_Builder_Status.Ok)
}

//   Initialize and seal both slot-owned text builders for direct snapshot tests.
view_snapshot_test_text_builders_init :: proc(
    t: ^testing.T, snapshot: ^app_bridge.View_Snapshot,
    fallback_text, command_text: string) {

    testing.expect(t, app_core.arena_owner_init(&snapshot^.arena))
    testing.expect_value(t, app_core.bounded_byte_builder_init(
        &snapshot^.fallback_text_builder, app_core.VIEW_SNAPSHOT_TEXT_CAPACITY,
        &snapshot^.arena), app_core.Bounded_Builder_Status.Ok)
    testing.expect_value(t, app_core.bounded_byte_builder_init(
        &snapshot^.command_text_builder, app_core.DYNVIEW_MAX_TEXT_BYTES,
        &snapshot^.arena), app_core.Bounded_Builder_Status.Ok)
    view_snapshot_test_record_builders_init(t, snapshot)
    testing.expect_value(t, app_core.bounded_byte_builder_append(
        &snapshot^.fallback_text_builder, transmute([]u8)fallback_text),
        app_core.Bounded_Builder_Status.Ok)
    testing.expect_value(t, app_core.bounded_byte_builder_append(
        &snapshot^.command_text_builder, transmute([]u8)command_text),
        app_core.Bounded_Builder_Status.Ok)
    fallback, fallback_status := app_core.bounded_byte_builder_seal(
        &snapshot^.fallback_text_builder)
    commands, command_status := app_core.bounded_byte_builder_seal(
        &snapshot^.command_text_builder)
    testing.expect_value(t, fallback_status, app_core.Bounded_Builder_Status.Ok)
    testing.expect_value(t, command_status, app_core.Bounded_Builder_Status.Ok)
    snapshot^.fallback_text = fallback
    snapshot^.command_text = commands
}

//   Initialize one direct snapshot fixture with text and a single command record.
view_snapshot_test_payloads_init :: proc(
    t: ^testing.T, snapshot: ^app_bridge.View_Snapshot,
    fallback_text: string, block_id: i32) {

    view_snapshot_test_text_builders_init(t, snapshot, fallback_text, "")
    testing.expect(t, app_bridge.build_view_snapshot_record_payloads(snapshot,
        {commands = []app_core.Dynview_Command{{block_id = block_id}}}))
}

//   Rebuild text and one command payload after a prepared slot reset.
view_snapshot_test_payloads_build :: proc(
    t: ^testing.T, snapshot: ^app_bridge.View_Snapshot,
    fallback_text: string, block_id: i32) {

    testing.expect(t, app_bridge.build_view_snapshot_text_payloads(
        snapshot, fallback_text, nil))
    testing.expect(t, app_bridge.build_view_snapshot_record_payloads(snapshot,
        {commands = []app_core.Dynview_Command{{block_id = block_id}}}))
}

//   Require a retired slot to be free without resetting its arena early.
view_snapshot_expect_released_without_reset :: proc(
    t: ^testing.T, snapshot: ^app_bridge.View_Snapshot) {

    testing.expect_value(t, snapshot^.state,
        app_bridge.View_Snapshot_Slot_State.Free)
    testing.expect_value(t, snapshot^.arena.reset_count, u64(0))
}

//   Set one complete snapshot's publication identity for direct display tests.
view_snapshot_test_complete :: proc(
    snapshot: ^app_bridge.View_Snapshot,
    animation: ^app_core.Euclid_Julia_Animation_Interface,
    generation, runtime_generation, animation_generation: u64) {

    snapshot^.state = .Complete
    snapshot^.generation = generation
    snapshot^.runtime_generation = runtime_generation
    snapshot^.animation_generation = animation_generation
    snapshot^.animation = animation
}

//   Require every display content slice to alias its published snapshot payload.
view_snapshot_expect_content_aliases :: proc(
    t: ^testing.T, snapshot: ^app_bridge.View_Snapshot,
    runtime: ^app_core.Dynview_System) {

    testing.expect_value(t, raw_data(runtime^.content.commands),
        raw_data(snapshot^.commands))
    testing.expect_value(t, raw_data(runtime^.content.text_bytes),
        raw_data(snapshot^.command_text))
    testing.expect_value(t, raw_data(runtime^.content.math_programs),
        raw_data(snapshot^.math_programs))
    testing.expect_value(t, raw_data(runtime^.content.math_commands),
        raw_data(snapshot^.math_commands))
    testing.expect_value(t, raw_data(runtime^.content.math_nodes),
        raw_data(snapshot^.math_nodes))
}

//   Require derived math mutations to remain isolated from immutable content.
view_snapshot_expect_math_working_isolation :: proc(
    t: ^testing.T, runtime: ^app_core.Dynview_System) {

    app_dyncompile.prepare_math_working_records(runtime)
    runtime^.compile_cache.math_programs[0].draw_width = 42
    runtime^.compile_cache.math_commands[0].block_id = 42
    testing.expect_value(t, runtime^.content.math_programs[0].draw_width, f32(0))
    testing.expect_value(t, runtime^.content.math_commands[0].block_id, i32(0))
}

//   Require one published generation's fallback and command aliases to remain active.
view_snapshot_expect_published_generation :: proc(
    t: ^testing.T, state: ^app_core.Euclid_General_State,
    expected: View_Snapshot_Published_Expected) {

    service := state^.julia_runtime_service
    slot := &service^.view_snapshots[service^.published_view_snapshot_index]
    testing.expect(t, app_bridge.current_view_snapshot_text(state) == expected.text)
    testing.expect_value(t, raw_data(slot.fallback_text), expected.fallback_storage)
    testing.expect_value(t, raw_data(state^.dynview.content.commands),
        expected.record_storage)
    testing.expect_value(t, state^.dynview.content.commands[0].block_id,
        expected.block_id)
}

//   Verify cell height participates in Dynview font invalidation identity.
@(test)
dynview_track_font_retains_canonical_cell_metrics :: proc(t: ^testing.T) {
    runtime := new(app_core.Dynview_System)
    defer free(runtime)
    runtime^.compile_cache.is_valid = true

    app_dynview.track_font(runtime, 16, 8, 22)

    testing.expect_value(t, runtime^.compile_cache.last_font_size, f32(16))
    testing.expect_value(t, runtime^.compile_cache.last_cell_width, f32(8))
    testing.expect_value(t, runtime^.compile_cache.last_cell_height, f32(22))
    testing.expect(t,
        runtime^.pending_invalidation_mask & app_dynview.DYNVIEW_INVALIDATE_FONT != 0)
    testing.expect(t, !runtime^.compile_cache.is_valid)

    runtime^.pending_invalidation_mask = 0
    runtime^.compile_cache.is_valid = true
    app_dynview.track_font(runtime, 16, 8, 23)
    testing.expect(t,
        runtime^.pending_invalidation_mask & app_dynview.DYNVIEW_INVALIDATE_FONT != 0)
}

//   Verify the scratchpad history prompt style matches the live input indent.
@(test)
scratchpad_history_prompt_matches_live_input_indent :: proc(t: ^testing.T) {
    prompt_style := dyncore.style_by_id(dyncore.DYNVIEW_STYLE_PROMPT)
    input_block := app_dynlayout.block_format_for_kind(
        app_bridge.BRIDGE_DYNVIEW_BLOCK_INPUT)
    output_block := app_dynlayout.block_format_for_kind(
        app_bridge.BRIDGE_DYNVIEW_BLOCK_OUTPUT)
    merged := app_dynlayout.style_with_block_format(prompt_style, input_block)

    testing.expect_value(t, merged.indent_cols, 0)
    testing.expect_value(t, input_block.paragraph_spacing_before, f32(0))
    testing.expect_value(t, input_block.paragraph_spacing_after, f32(0))
    testing.expect_value(t, output_block.paragraph_spacing_before, f32(0))
    testing.expect_value(t, output_block.paragraph_spacing_after, f32(0))
}

//   Verify the native error underline style id and flags are stable across the bridge.
@(test)
scratchpad_native_error_underline_style_is_stable :: proc(t: ^testing.T) {
    testing.expect_value(t,
        app_bridge.BRIDGE_DYNVIEW_STYLE_UNDERLINE,
        dyncore.DYNVIEW_STYLE_UNDERLINE)

    style := dyncore.style_by_id(dyncore.DYNVIEW_STYLE_UNDERLINE)
    testing.expect(t, style.underline)
    testing.expect_value(t, style.font_flags, app_core.Font_Variant_Flags.Regular)
}

//   Verify the Julia interface staging slots alternate between the two slots.
@(test)
julia_interface_generation_slots_are_stable_and_alternate :: proc(t: ^testing.T) {
    state := new(app_core.Euclid_General_State)
    defer free(state)
    state^.julia_interface_active_slot = 0
    state^.julia_interface = &state^.julia_interface_slots[0]

    staging, staging_index := app_bridge.julia_interface_staging_slot(state)
    testing.expect_value(t, staging_index, 1)
    testing.expect(t, staging == &state^.julia_interface_slots[1])

    state^.julia_interface_active_slot = staging_index
    state^.julia_interface = staging
    next_staging, next_staging_index := app_bridge.julia_interface_staging_slot(state)
    testing.expect_value(t, next_staging_index, 0)
    testing.expect(t, next_staging == &state^.julia_interface_slots[0])
}

//   Verify a recycled interface pointer from an old generation is rejected.
@(test)
view_snapshot_rejects_recycled_interface_pointer_from_old_generation :: proc(
    t: ^testing.T) {

    state := new(app_core.Euclid_General_State)
    defer free(state)
    service := new(app_bridge.Julia_Runtime_Service)
    defer free(service)
    animation := &state^.julia_interface_slots[0].null_animation
    state^.julia_interface = &state^.julia_interface_slots[0]
    state^.julia_interface^.current_animation = animation
    service^.runtime_generation = 2
    snapshot := new(app_bridge.View_Snapshot)
    defer free(snapshot)
    snapshot^ = app_bridge.View_Snapshot{
        runtime_generation = 0,
        animation = animation,
    }

    testing.expect(t, !app_bridge.view_snapshot_matches_current(state, service, snapshot))
    snapshot^.runtime_generation = service^.runtime_generation
    testing.expect(t, app_bridge.view_snapshot_matches_current(state, service, snapshot))
}

//   Verify a scene command batch commits point positions in submission order.
@(test)
scene_command_batch_commits_point_positions_in_order :: proc(t: ^testing.T) {
    state := new(app_core.Euclid_General_State)
    defer free(state)
    interface := new(app_core.Euclid_Julia_Interface)
    defer free(interface)
    animation := new(app_core.Euclid_Julia_Animation_Interface)
    defer free(animation)
    point_system := new(app_core.Shapes_Point_System)
    defer free(point_system)
    state^.julia_interface = interface
    state^.julia_interface^.current_animation = animation
    state^.point_system = point_system
    point_system^.next_point_index = 2
    batch := app_bridge.Scene_Command_Batch{animation = animation}

    state^.scene_command_batch_target = &batch
    testing.expect(t, app_bridge.capture_point_position_command(
        state, 0, app_core.Vector3{1, 2, 3}))
    testing.expect(t, app_bridge.capture_point_position_command(
        state, 1, app_core.Vector3{4, 5, 6}))
    state^.scene_command_batch_target = nil

    testing.expect(t, app_bridge.commit_scene_command_batch(state, &batch))
    position_0, ok_0 := point_system^.points[0].position.?
    position_1, ok_1 := point_system^.points[1].position.?
    testing.expect(t, ok_0 && position_0 == app_core.Vector3{1, 2, 3})
    testing.expect(t, ok_1 && position_1 == app_core.Vector3{4, 5, 6})
}

//   Verify an invalid tail command rejects the whole batch atomically.
@(test)
scene_command_batch_rejects_invalid_tail_atomically :: proc(t: ^testing.T) {
    state := new(app_core.Euclid_General_State)
    defer free(state)
    interface := new(app_core.Euclid_Julia_Interface)
    defer free(interface)
    animation := new(app_core.Euclid_Julia_Animation_Interface)
    defer free(animation)
    point_system := new(app_core.Shapes_Point_System)
    defer free(point_system)
    state^.julia_interface = interface
    state^.julia_interface^.current_animation = animation
    state^.point_system = point_system
    point_system^.next_point_index = 1
    point_system^.points[0].position = app_core.Vector3{9, 9, 9}
    batch := app_bridge.Scene_Command_Batch{animation = animation, command_count = 2}
    batch.commands[0] = app_bridge.Scene_Command{
        kind = .Set_Point_Position, point_index = 0, position = {1, 2, 3}}
    batch.commands[1] = app_bridge.Scene_Command{
        kind = .Set_Point_Position, point_index = 1, position = {4, 5, 6}}

    testing.expect(t, !app_bridge.commit_scene_command_batch(state, &batch))
    position := point_system^.points[0].position.? or_else app_core.Vector3{}
    testing.expect(t, position == app_core.Vector3{9, 9, 9})
}

//   Verify overflow and stale-animation commands reject the batch atomically.
@(test)
scene_command_batch_rejects_overflow_and_stale_animation :: proc(t: ^testing.T) {
    state := new(app_core.Euclid_General_State)
    defer free(state)
    interface := new(app_core.Euclid_Julia_Interface)
    defer free(interface)
    current := new(app_core.Euclid_Julia_Animation_Interface)
    defer free(current)
    stale := new(app_core.Euclid_Julia_Animation_Interface)
    defer free(stale)
    point_system := new(app_core.Shapes_Point_System)
    defer free(point_system)
    state^.julia_interface = interface
    state^.julia_interface^.current_animation = current
    state^.point_system = point_system

    overflowed := app_bridge.Scene_Command_Batch{animation = current, overflowed = true}
    stale_batch := app_bridge.Scene_Command_Batch{animation = stale}
    testing.expect(t, !app_bridge.validate_scene_command_batch(state, &overflowed))
    testing.expect(t, !app_bridge.validate_scene_command_batch(state, &stale_batch))
}

//   Verify the tick-reject reason classifies stale generation and stale sequence.
@(test)
animation_tick_reject_reason_classifies_stale_generation_and_sequence :: proc(
    t: ^testing.T) {

    state := new(app_core.Euclid_General_State)
    defer free(state)
    service := new(app_bridge.Julia_Runtime_Service)
    defer free(service)
    interface := new(app_core.Euclid_Julia_Interface)
    defer free(interface)
    current := new(app_core.Euclid_Julia_Animation_Interface)
    defer free(current)
    state^.julia_interface = interface
    state^.julia_interface^.current_animation = current
    state^.julia_interface^.selected_animation = current
    service^.animation_generation = 3
    service^.animation_last_committed_sequence = 7

    slot := app_bridge.Animation_Tick_Slot{
        generation = 2,
        sequence = 8,
        animation = current,
    }
    testing.expect_value(
        t, app_bridge.animation_tick_reject_reason(state, service, &slot),
        "stale_generation")

    slot.generation = 3
    slot.sequence = 7
    testing.expect_value(
        t, app_bridge.animation_tick_reject_reason(state, service, &slot),
        "stale_sequence")
}

//   Verify general point properties are deferred until the batch commits.
@(test)
scene_command_batch_defers_general_point_properties_until_commit :: proc(t: ^testing.T) {
    state := new(app_core.Euclid_General_State)
    defer free(state)
    interface := new(app_core.Euclid_Julia_Interface)
    defer free(interface)
    animation := new(app_core.Euclid_Julia_Animation_Interface)
    defer free(animation)
    point_system := new(app_core.Shapes_Point_System)
    defer free(point_system)
    state^.julia_interface = interface
    state^.julia_interface^.current_animation = animation
    state^.point_system = point_system
    point_system^.next_point_index = 1
    point_system^.points[0].offset = 1
    batch: app_bridge.Scene_Command_Batch

    app_bridge.begin_scene_command_batch(state, &batch)
    testing.expect(t, app_bridge.capture_point_scalar_command(
        state, .Set_Point_Offset, 0, 2))
    testing.expect_value(t, point_system^.points[0].offset, f32(1))
    app_bridge.end_scene_command_batch(state)

    testing.expect(t, app_bridge.commit_scene_command_batch(state, &batch))
    testing.expect_value(t, point_system^.points[0].offset, f32(2))
}

//   Verify an invalid implicit compass handle rejects the batch atomically.
@(test)
scene_command_batch_rejects_invalid_implicit_compass_handle_atomically :: proc(
    t: ^testing.T) {

    state := new(app_core.Euclid_General_State)
    defer free(state)
    interface := new(app_core.Euclid_Julia_Interface)
    defer free(interface)
    animation := new(app_core.Euclid_Julia_Animation_Interface)
    defer free(animation)
    point_system := new(app_core.Shapes_Point_System)
    defer free(point_system)
    state^.julia_interface = interface
    state^.julia_interface^.current_animation = animation
    state^.point_system = point_system
    point_system^.next_point_index = 1
    point_system^.points[0].position = app_core.Vector3{9, 9, 9}
    state^.compass.joint1_id = 1
    batch := app_bridge.Scene_Command_Batch{animation = animation, command_count = 2}
    batch.commands[0] = app_bridge.Scene_Command{
        kind = .Set_Point_Position, point_index = 0, position = {1, 2, 3}}
    batch.commands[1] = app_bridge.Scene_Command{kind = .Lock_Compass_Joint1}

    testing.expect(t, !app_bridge.commit_scene_command_batch(state, &batch))
    position := point_system^.points[0].position.? or_else app_core.Vector3{}
    testing.expect(t, position == app_core.Vector3{9, 9, 9})
}

//   Verify the animation query snapshot is immutable while the worker ticks.
@(test)
animation_query_snapshot_is_immutable_during_worker_tick :: proc(t: ^testing.T) {
    state := new(app_core.Euclid_General_State)
    defer free(state)
    point_system := new(app_core.Shapes_Point_System)
    defer free(point_system)
    state^.point_system = point_system
    state^.pen.joint1_id = 0
    point_system^.points[0].position = app_core.Vector3{1, 2, 3}
    snapshot: app_bridge.Animation_Query_Snapshot
    app_bridge.capture_animation_query_snapshot(state, &snapshot)

    point_system^.points[0].position = app_core.Vector3{4, 5, 6}
    state^.animation_query_snapshot_target = &snapshot
    testing.expect(
        t, app_bridge.get_pen_joint1_position(state) == app_core.Vector3{1, 2, 3})
    point_view := app_bridge.get_point_view(state, 0)
    testing.expect(
        t, point_view.has_position && point_view.position == app_core.Vector3{1, 2, 3})
    state^.animation_query_snapshot_target = nil
}

//   Verify an animation tick rejects stale generation and stale sequence.
@(test)
animation_tick_rejects_stale_generation_and_sequence :: proc(t: ^testing.T) {
    state := new(app_core.Euclid_General_State)
    defer free(state)
    interface := new(app_core.Euclid_Julia_Interface)
    defer free(interface)
    animation := new(app_core.Euclid_Julia_Animation_Interface)
    defer free(animation)
    service := new(app_bridge.Julia_Runtime_Service)
    defer free(service)
    state^.julia_interface = interface
    interface^.current_animation = animation
    interface^.selected_animation = animation
    service^.animation_generation = 4
    service^.animation_last_committed_sequence = 8
    slot := app_bridge.Animation_Tick_Slot{
        generation = 4, sequence = 9, animation = animation}

    testing.expect(t, app_bridge.animation_tick_matches_current(state, service, &slot))
    slot.generation = 3
    testing.expect(t, !app_bridge.animation_tick_matches_current(state, service, &slot))
    slot.generation = 4
    slot.sequence = 8
    testing.expect(t, !app_bridge.animation_tick_matches_current(state, service, &slot))
    slot.sequence = 9
    interface^.pending_animation_reset = true
    testing.expect(t, !app_bridge.animation_tick_matches_current(state, service, &slot))
}

//   Verify tick coalescing caps the backlog without growing the queue.
@(test)
animation_tick_coalescing_caps_backlog_without_queue_growth :: proc(t: ^testing.T) {
    service := new(app_bridge.Julia_Runtime_Service)
    defer free(service)

    for _ in 0..<100 {
        app_bridge.coalesce_animation_tick(service, f32(1.0 / 60.0))
    }

    testing.expect_value(t, service^.animation_accumulated_dt,
        app_bridge.MAX_ACCUMULATED_ANIMATION_DT)
    testing.expect_value(t, service^.animation_ticks_coalesced, u64(100))
}

//   Verify a runtime failure event records the request identity.
@(test)
julia_runtime_failure_event_records_request_identity :: proc(t: ^testing.T) {
    path := ".build/test-artifacts/runtime-failure.log"
    os.make_directory_all(".build/test-artifacts")
    os.remove(path)
    logging_state: diagnostics.Logging_State
    testing.expect(t, diagnostics.logging_start(&logging_state, path, .Info))
    context.logger = logging_state.logger
    service := new(app_bridge.Julia_Runtime_Service)
    defer free(service)
    service^.active_request_id = 8
    service^.active_request_kind = .Animation_Tick
    event := app_bridge.Julia_Event{
        kind = .Invoke_Complete,
        request_kind = .Invoke,
        request_id = 7,
        succeeded = false,
    }

    app_bridge.accept_julia_event(service, event)

    testing.expect_value(t, service^.failed_request_count, u64(1))
    testing.expect_value(t, service^.last_failed_request_id, u64(7))
    testing.expect(t, service^.last_failed_request_kind == .Invoke)
    testing.expect_value(t, service^.active_request_id, u64(8))
    context.logger = log.nil_logger()
    diagnostics.logging_stop(&logging_state)
    content_bytes, read_error := os.read_entire_file(path, context.allocator)
    testing.expect(t, read_error == nil)
    defer delete(content_bytes)
    defer os.remove(path)
    testing.expect(t, strings.contains(string(content_bytes),
        "julia_request_failed request_id=7 request_kind=1 event_kind=1 generation=0 count=1"))
}

//   Verify a terminal runtime failure does not report a clean stopped state.
@(test)
julia_runtime_terminal_failure_does_not_report_stopped :: proc(t: ^testing.T) {
    context.logger = log.nil_logger()
    service := new(app_bridge.Julia_Runtime_Service)
    defer free(service)
    service^.lifecycle = .Shutdown_Requested
    event := app_bridge.Julia_Event{
        kind = .Shutdown_Complete,
        request_kind = .Shutdown,
        request_id = 4,
        succeeded = false,
    }

    app_bridge.accept_julia_event(service, event)

    testing.expect(t, service^.lifecycle == .Failed)
}

//   Verify runtime diagnostics report failure and saturation counters.
@(test)
julia_runtime_diagnostics_report_failure_and_saturation :: proc(t: ^testing.T) {
    service := new(app_bridge.Julia_Runtime_Service)
    defer free(service)
    service^.lifecycle = .Ready
    service^.failed_request_count = 3
    service^.last_failed_request_id = 12
    service^.last_failed_request_kind = .Animation_Tick
    service^.request_saturation_count = 5
    service^.reload_state = .Failed
    service^.runtime_generation = 9

    diagnostics := app_bridge.julia_runtime_diagnostics(service)

    testing.expect(t, diagnostics.lifecycle == .Ready)
    testing.expect_value(t, diagnostics.failed_request_count, u64(3))
    testing.expect_value(t, diagnostics.last_failed_request_id, u64(12))
    testing.expect(t, diagnostics.last_failed_request_kind == .Animation_Tick)
    testing.expect_value(t, diagnostics.request_saturation_count, u64(5))
    testing.expect(t, diagnostics.reload_state == .Failed)
    testing.expect_value(t, diagnostics.runtime_generation, u64(9))
}

//   Verify repeated pressure diagnostics use exponentially sparse occurrence counts.
@(test)
julia_runtime_saturation_diagnostics_are_power_of_two_bounded :: proc(t: ^testing.T) {
    for count: u64 = 1; count <= 16; count += 1 {
        expected := count == 1 || count == 2 || count == 4 ||
            count == 8 || count == 16
        testing.expect_value(t,
            app_bridge.diagnostic_occurrence_should_log(count), expected)
    }
}

//   Verify a reload failure records the package revision.
@(test)
julia_reload_failure_records_package_revision :: proc(t: ^testing.T) {
    service := new(app_bridge.Julia_Runtime_Service)
    defer free(service)

    app_bridge.mark_julia_reload_failed(service, 1234)

    testing.expect(t, service^.reload_state == .Failed)
    testing.expect_value(t, service^.reload_failed_mtime_unix_nano, i64(1234))
    testing.expect_value(t, service^.runtime_generation, u64(0))
}

//   Verify font weight resolution prefers the heaviest requested flag.
@(test)
font_weight_resolution_prefers_heaviest_requested_flag :: proc(t: ^testing.T) {
    // Ensures font-weight resolution chooses the heaviest requested weight when multiple flags are set.
    flags := app_core.Font_Variant_Flags(
        u32(app_core.Font_Variant_Flags.Light) |
        u32(app_core.Font_Variant_Flags.Bold) |
        u32(app_core.Font_Variant_Flags.Italic))

    resolved := app_core.font_resolve_weight_from_flags(flags)
    testing.expect_value(t, resolved, app_core.Font_Weight.Bold)

    heavier := app_core.Font_Variant_Flags(
        u32(flags) |
        u32(app_core.Font_Variant_Flags.Extrabold) |
        u32(app_core.Font_Variant_Flags.Black))
    resolved_heavier := app_core.font_resolve_weight_from_flags(heavier)
    testing.expect_value(t, resolved_heavier, app_core.Font_Weight.Black)
}

//   Verify installed recursive math records and cache invalidation state.
view_snapshot_expect_recursive_math_content :: proc(
    t: ^testing.T,
    runtime: ^app_core.Dynview_System) {
    testing.expect_value(t, runtime^.command_buffer.command_count, 1)
    testing.expect_value(t, runtime^.command_buffer.text_bytes_len, len("semantic"))
    testing.expect(t, string(runtime^.command_buffer.text_view) == "semantic")
    testing.expect_value(t, runtime^.compile_cache.math_program_count, 1)
    testing.expect(t, runtime^.content.math_programs[0].valid)
    testing.expect_value(t, runtime^.content.math_nodes[0].kind,
        app_core.Dynview_Math_Node_Kind.Glyph_Run)
    testing.expect_value(t, runtime^.content.math_commands[0].kind,
        app_core.Dynview_Command_Kind.Math_Glyph_Run)
    testing.expect_value(t, runtime^.command_buffer.commands[0].kind,
        app_core.Dynview_Command_Kind.Begin_Block)
    testing.expect_value(t, runtime^.compile_cache.math_programs[0].valid, false)
    view_snapshot_expect_math_working_isolation(t, runtime)
    testing.expect(t, !runtime^.compile_cache.is_valid)
    testing.expect(t, !runtime^.compile_cache.layout_is_valid)
}

//   Verify a view snapshot copy preserves recursive math spans.
@(test)
view_snapshot_copy_preserves_recursive_math_spans :: proc(t: ^testing.T) {
    snapshot := new(app_bridge.View_Snapshot)
    defer free(snapshot)
    view_snapshot_test_text_builders_init(t, snapshot, "fallback", "semantic")
    defer app_core.arena_owner_destroy(&snapshot^.arena)
    runtime := new(app_core.Dynview_System)
    defer free(runtime)

    commands := []app_core.Dynview_Command{{kind = .Math_Block}}
    programs := []app_core.Dynview_Math_Program{{
        valid = true,
        root_node_index = 0,
        node_count = 1,
        command_count = 1,
    }}
    math_commands := []app_core.Dynview_Command{{kind = .Math_Glyph_Run}}
    nodes := []app_core.Dynview_Math_Node{{kind = .Glyph_Run}}
    testing.expect(t, app_bridge.build_view_snapshot_record_payloads(
        snapshot, {commands, programs, math_commands, nodes, nil}))
    runtime^.compile_cache.is_valid = true
    runtime^.compile_cache.layout_is_valid = true

    app_bridge.install_view_snapshot_content(snapshot, runtime)

    view_snapshot_expect_content_aliases(t, snapshot, runtime)
    view_snapshot_expect_recursive_math_content(t, runtime)
}

//   Connect one publication fixture with isolated evidence storage.
view_snapshot_publication_fixture_init :: proc(
    fixture: ^View_Snapshot_Publication_Fixture) {
    fixture.state^.julia_interface = &fixture.state^.julia_interface_slots[0]
    fixture.state^.julia_interface^.current_animation = fixture.animation
    fixture.state^.julia_runtime_service = fixture.service
    init_test_evidence(fixture.state)
}

//   Verify the publication and Scratchpad evidence identities for one snapshot.
view_snapshot_expect_publication_evidence :: proc(
    t: ^testing.T,
    state: ^app_core.Euclid_General_State) {
    testing.expect_value(t, state^.evidence_ring.count, 2)
    event := state^.evidence_ring.events[0]
    testing.expect_value(t, event.kind, app_evidence_trace.Kind.Dynview_Published)
    testing.expect_value(t, event.correlation_kind,
        app_evidence_trace.Correlation_Kind.Animation)
    testing.expect_value(t, event.correlation, u64(7))
    testing.expect_value(t, event.generation, u64(7))
    testing.expect_value(t, event.revision, u64(11))
    completed := state^.evidence_ring.events[1]
    testing.expect_value(t, completed.kind,
        app_evidence_trace.Kind.Scratchpad_Completed)
    testing.expect_value(t, completed.correlation_kind,
        app_evidence_trace.Correlation_Kind.Runtime_Request)
    testing.expect_value(t, completed.correlation, u64(41))
    testing.expect_value(t, completed.generation, u64(3))
    testing.expect_value(t, completed.revision, u64(11))
}

//   Verify valid snapshot publication records the immutable animation identity.
@(test)
view_snapshot_publication_records_animation_generation :: proc(t: ^testing.T) {
    fixture := View_Snapshot_Publication_Fixture{
        new(app_core.Euclid_General_State),
        new(app_bridge.Julia_Runtime_Service),
        new(app_core.Euclid_Julia_Animation_Interface)}
    defer free(fixture.animation)
    defer free(fixture.service)
    defer free(fixture.state)
    view_snapshot_publication_fixture_init(&fixture)
    state, service, animation := fixture.state, fixture.service, fixture.animation
    service^.runtime_generation = 3
    service^.animation_generation = 7
    service^.view_snapshots[0] = {
        state = .Complete,
        runtime_generation = 3,
        animation_generation = 7,
        generation = 11,
        scratchpad_request_id = 41,
        scratchpad_runtime_generation = 3,
        animation = animation,
    }
    view_snapshot_test_text_builders_init(
        t, &service^.view_snapshots[0], "fallback", "")
    testing.expect(t, app_bridge.build_view_snapshot_record_payloads(
        &service^.view_snapshots[0], {}))
    defer app_core.arena_owner_destroy(&service^.view_snapshots[0].arena)

    testing.expect(t, app_bridge.publish_available_view_snapshot(state))
    view_snapshot_expect_publication_evidence(t, state)
}

//   Verify invalid current content cannot claim Scratchpad display completion.
@(test)
scratchpad_completion_waits_for_valid_view_publication :: proc(t: ^testing.T) {
    state := new(app_core.Euclid_General_State)
    defer free(state)
    service := new(app_bridge.Julia_Runtime_Service)
    defer free(service)
    state^.julia_interface = &state^.julia_interface_slots[0]
    animation := &state^.julia_interface^.null_animation
    state^.julia_interface^.current_animation = animation
    state^.julia_runtime_service = service
    init_test_evidence(state)
    service^.runtime_generation = 3
    service^.animation_generation = 7
    snapshot := &service^.view_snapshots[0]
    view_snapshot_test_complete(snapshot, animation, 11, 3, 7)
    snapshot^.scratchpad_request_id = 41
    snapshot^.scratchpad_runtime_generation = 3
    view_snapshot_test_text_builders_init(t, snapshot, "fallback", "")
    defer app_core.arena_owner_destroy(&snapshot^.arena)
    testing.expect(t, app_bridge.build_view_snapshot_record_payloads(
        snapshot, {}))
    snapshot^.stream_open_block = true

    testing.expect(t, !app_bridge.publish_available_view_snapshot(state))
    testing.expect_value(t, state^.evidence_ring.count, 0)
}

//   Verify stale runtime identity and evidence pressure cannot produce false proof.
@(test)
scratchpad_completion_requires_current_complete_evidence :: proc(t: ^testing.T) {
    state := new(app_core.Euclid_General_State)
    defer free(state)
    init_test_evidence(state)
    snapshot := app_bridge.View_Snapshot{
        runtime_generation = 3,
        scratchpad_request_id = 41,
        scratchpad_runtime_generation = 2,
    }
    app_bridge.record_scratchpad_completed(state, &snapshot)
    testing.expect_value(t, state^.evidence_ring.count, 0)

    snapshot.scratchpad_runtime_generation = 3
    for _ in 0..<app_evidence_trace.TRACE_RING_CAPACITY {
        testing.expect(t, app_evidence_trace.ring_record(
            &state^.evidence_ring, {kind = .Frame_Presented}))
    }
    app_bridge.record_scratchpad_completed(state, &snapshot)
    testing.expect(t, state^.evidence_ring.required_evidence_lost)
    testing.expect(t, !app_evidence_trace.ring_evidence_complete(
        &state^.evidence_ring))
}

//   Verify reload and shutdown lifecycle boundaries discard uncommitted identities.
@(test)
scratchpad_completion_watermark_clears_at_lifecycle_boundary :: proc(t: ^testing.T) {
    service := new(app_bridge.Julia_Runtime_Service)
    defer free(service)
    service^.worker_scratchpad_completed_request_id = 41
    service^.worker_scratchpad_completed_runtime_generation = 3
    app_bridge.clear_scratchpad_completion_watermark(service)
    testing.expect_value(t,
        service^.worker_scratchpad_completed_request_id, u64(0))
    testing.expect_value(t,
        service^.worker_scratchpad_completed_runtime_generation, u64(0))
}

//   Verify view snapshot validation rejects incomplete command streams.
@(test)
view_snapshot_validation_rejects_incomplete_streams :: proc(t: ^testing.T) {
    snapshot := new(app_bridge.View_Snapshot)
    defer free(snapshot)
    view_snapshot_test_text_builders_init(t, snapshot, "", "")
    testing.expect(t, app_bridge.build_view_snapshot_record_payloads(
        snapshot, {}))
    defer app_core.arena_owner_destroy(&snapshot^.arena)

    testing.expect(t, app_bridge.view_snapshot_is_valid(snapshot))
    snapshot^.stream_open_block = true
    testing.expect(t, !app_bridge.view_snapshot_is_valid(snapshot))
    snapshot^.stream_open_block = false
    snapshot^.stream_has_error = true
    testing.expect(t, !app_bridge.view_snapshot_is_valid(snapshot))
}

//   Verify every semantic command text span and sealed-builder alias is validated.
@(test)
view_snapshot_validation_rejects_all_malformed_text_spans :: proc(t: ^testing.T) {
    snapshot := new(app_bridge.View_Snapshot)
    defer free(snapshot)
    view_snapshot_test_text_builders_init(t, snapshot, "same", "text")
    defer app_core.arena_owner_destroy(&snapshot^.arena)
    malformed := [6]app_core.Dynview_Command{
        {text_offset = 4, text_len = 1},
        {copy_text_offset = 4, copy_text_len = 1},
        {script_base_text_offset = 4, script_base_text_len = 1},
        {script_sup_text_offset = 4, script_sup_text_len = 1},
        {script_sub_text_offset = 4, script_sub_text_len = 1},
        {radical_index_text_offset = 4, radical_index_text_len = 1},
    }
    testing.expect(t, app_bridge.build_view_snapshot_record_payloads(
        snapshot, {commands = []app_core.Dynview_Command{{}}}))
    for command in malformed {
        snapshot^.commands[0] = command
        testing.expect(t, !app_bridge.view_snapshot_is_valid(snapshot))
    }

    snapshot^.commands[0] = {text_offset = 0, text_len = 4}
    testing.expect(t, app_bridge.view_snapshot_is_valid(snapshot))
    snapshot^.math_commands = snapshot^.commands
    testing.expect(t, !app_bridge.view_snapshot_is_valid(snapshot))
    snapshot^.math_commands = nil
    command_text := snapshot^.command_text
    snapshot^.command_text = snapshot^.fallback_text
    testing.expect(t, !app_bridge.view_snapshot_is_valid(snapshot))
    snapshot^.command_text = command_text
    testing.expect(t, app_bridge.view_snapshot_is_valid(snapshot))
}

//   Build and reject one stale candidate without disturbing published content.
view_snapshot_expect_stale_candidate_rejected :: proc(
    t: ^testing.T,
    fixture: View_Snapshot_Publication_Fixture,
    expected: View_Snapshot_Published_Expected) {
    second := &fixture.service^.view_snapshots[1]
    view_snapshot_test_complete(second, fixture.animation, 2, 1, 3)
    second^.scratchpad_request_id = 41
    second^.scratchpad_runtime_generation = 1
    view_snapshot_test_payloads_init(t, second, "stale", 0)
    testing.expect(t, !app_bridge.publish_available_view_snapshot(fixture.state))
    testing.expect_value(t, fixture.state^.evidence_ring.count, 1)
    view_snapshot_expect_published_generation(t, fixture.state, expected)
}

//   Reuse the stale slot for a valid replacement and verify both arena lifetimes.
view_snapshot_expect_replacement_published :: proc(
    t: ^testing.T,
    fixture: View_Snapshot_Publication_Fixture,
    first: ^app_bridge.View_Snapshot) {
    second := &fixture.service^.view_snapshots[1]
    testing.expect(t, app_bridge.prepare_view_snapshot_slot(second))
    view_snapshot_test_payloads_build(t, second, "second", 2)
    view_snapshot_test_complete(second, fixture.animation, 3, 2, 3)
    testing.expect(t, app_bridge.publish_available_view_snapshot(fixture.state))
    view_snapshot_expect_released_without_reset(t, first)
    expected := View_Snapshot_Published_Expected{
        "second", raw_data(second^.fallback_text), raw_data(second^.commands), 2}
    view_snapshot_expect_published_generation(t, fixture.state, expected)
    testing.expect(t, app_bridge.prepare_view_snapshot_slot(first))
    testing.expect_value(t, first^.arena.reset_count, u64(1))
    view_snapshot_expect_published_generation(t, fixture.state, expected)
}

//   Verify stale candidates preserve published fallback until valid replacement and reuse.
@(test)
view_snapshot_fallback_lifetime_survives_stale_and_repeated_publication :: proc(
    t: ^testing.T) {

    state := new(app_core.Euclid_General_State)
    defer free(state)
    service := new(app_bridge.Julia_Runtime_Service)
    defer free(service)
    state^.julia_interface = &state^.julia_interface_slots[0]
    animation := &state^.julia_interface^.null_animation
    state^.julia_interface^.current_animation = animation
    state^.julia_runtime_service = service
    init_test_evidence(state)
    service^.published_view_snapshot_index = -1
    service^.runtime_generation = 2
    service^.animation_generation = 3
    first := &service^.view_snapshots[0]
    view_snapshot_test_complete(first, animation, 1, 2, 3)
    view_snapshot_test_payloads_init(t, first, "first", 1)
    defer app_core.arena_owner_destroy(&first^.arena)

    testing.expect(t, app_bridge.publish_available_view_snapshot(state))
    first_storage := raw_data(first^.fallback_text)
    first_records := raw_data(first^.commands)
    first_expected := View_Snapshot_Published_Expected{
        "first", first_storage, first_records, 1}
    view_snapshot_expect_published_generation(t, state, first_expected)

    fixture := View_Snapshot_Publication_Fixture{state, service, animation}
    second := &service^.view_snapshots[1]
    view_snapshot_expect_stale_candidate_rejected(t, fixture, first_expected)
    defer app_core.arena_owner_destroy(&second^.arena)
    view_snapshot_expect_replacement_published(t, fixture, first)
}

//   Verify a completed view snapshot is found without needing its event index.
@(test)
completed_view_snapshot_is_found_without_event_index :: proc(t: ^testing.T) {
    service := new(app_bridge.Julia_Runtime_Service)
    defer free(service)
    service^.view_snapshots[0].state = .Published
    service^.view_snapshots[0].generation = 10
    service^.view_snapshots[1].state = .Complete
    service^.view_snapshots[1].generation = 11

    completed_index := app_bridge.newest_completed_view_snapshot_index(service)
    app_bridge.release_superseded_completed_view_snapshots(service, completed_index)

    testing.expect_value(t, completed_index, 1)
    testing.expect_value(t, service^.view_snapshots[0].state,
        app_bridge.View_Snapshot_Slot_State.Published)
    testing.expect_value(t, service^.view_snapshots[1].state,
        app_bridge.View_Snapshot_Slot_State.Complete)
}

//   Verify the newest completed view snapshot supersedes an older completion.
@(test)
newest_completed_view_snapshot_supersedes_older_completion :: proc(t: ^testing.T) {
    service := new(app_bridge.Julia_Runtime_Service)
    defer free(service)
    service^.view_snapshots[0].state = .Complete
    service^.view_snapshots[0].generation = 10
    service^.view_snapshots[1].state = .Complete
    service^.view_snapshots[1].generation = 11

    completed_index := app_bridge.newest_completed_view_snapshot_index(service)
    app_bridge.release_superseded_completed_view_snapshots(service, completed_index)

    testing.expect_value(t, completed_index, 1)
    testing.expect_value(t, service^.view_snapshots[0].state,
        app_bridge.View_Snapshot_Slot_State.Free)
    testing.expect_value(t, service^.view_snapshots[1].state,
        app_bridge.View_Snapshot_Slot_State.Complete)
}

//   Verify a stale view snapshot clears the previous animation commands.
@(test)
stale_view_snapshot_clears_previous_animation_commands :: proc(t: ^testing.T) {
    service := new(app_bridge.Julia_Runtime_Service)
    defer free(service)
    state := new(app_core.Euclid_General_State)
    defer free(state)
    interface := new(app_core.Euclid_Julia_Interface)
    defer free(interface)
    previous_animation := new(app_core.Euclid_Julia_Animation_Interface)
    defer free(previous_animation)
    current_animation := new(app_core.Euclid_Julia_Animation_Interface)
    defer free(current_animation)

    service^.published_view_snapshot_index = 0
    service^.view_snapshots[0].state = .Published
    service^.view_snapshots[0].animation = previous_animation
    state^.julia_interface = interface
    state^.julia_interface^.current_animation = current_animation
    state^.dynview.command_buffer.command_count = 1

    app_bridge.clear_stale_published_view(state, service)

    testing.expect_value(t, service^.published_view_snapshot_index, -1)
    testing.expect_value(t, service^.view_snapshots[0].state,
        app_bridge.View_Snapshot_Slot_State.Free)
    testing.expect_value(t, state^.dynview.command_buffer.command_count, 0)
}

//   Verify the text-span and script-attach helpers respect buffer bounds.
@(test)
dynview_text_span_and_script_attach_helpers_respect_bounds :: proc(t: ^testing.T) {
    // Validates dynview text span extraction bounds checks for base and scripted spans.
    buffer := new(app_core.Dynview_Command_Buffer)
    defer free(buffer)
    text := "abc"
    for i in 0..<len(text) {
        buffer.text_bytes[i] = u8(text[i])
    }
    buffer.text_bytes_len = len(text)

    span := dyncore.text_span_from_buffer(buffer, 1, 2)
    testing.expect_value(t, span, "bc")

    out_of_bounds := dyncore.text_span_from_buffer(buffer, 2, 5)
    testing.expect_value(t, out_of_bounds, "")

    cmd := app_core.Dynview_Command{
        script_base_text_offset = 0,
        script_base_text_len = 3,
        script_sup_text_offset = 1,
        script_sup_text_len = 1,
    }
    base_text := dyncore.text_span_from_buffer(
        buffer,
        cmd.script_base_text_offset,
        cmd.script_base_text_len)
    testing.expect_value(t, base_text, "abc")
}

//   Verify layout style placement forces a line break and indent when requested.
@(test)
dynview_layout_prepare_style_placement_forces_line_break_and_indent :: proc(
    t: ^testing.T) {
    // Verifies style placement can force a line break and apply configured indentation at the next line start.
    cache := new(app_core.Dynview_Compile_Cache)
    defer free(cache)
    arena: app_core.Arena_Owner
    dynview_test_layout_builders_init(t, cache, &arena)
    defer app_core.arena_owner_destroy(&arena)
    cache^.last_cell_width = 8
    cache^.last_cell_height = 22
    testing.expect_value(t, app_core.bounded_element_builder_append(
        &cache^.layout_item_builder, []app_core.Dynview_Layout_Item{{}}),
        app_core.Bounded_Builder_Status.Ok)
    cache^.layout_items = cache^.layout_item_builder.storage[:1]
    cache^.layout_item_count = 1
    state := app_dynlayout.Dynview_Layout_State{col = 2, line_index = 0}
    acc := app_dynlayout.Dynview_Layout_Line_Accumulator{item_start = 0, item_count = 1}
    style := dyncore.Dynview_Text_Style{force_line_start = true, indent_cols = 3}

    status := app_dynlayout.layout_prepare_style_placement(cache, &state, &acc, style, 12)

    testing.expect_value(t, status, dyncore.DYNVIEW_STATUS_OK)
    testing.expect_value(t, cache.layout_line_count, 1)
    testing.expect_value(t, state.line_index, 1)
    testing.expect_value(t, state.col, 3)
    testing.expect_value(t, cache.layout_lines[0].item_count, 1)
    testing.expect_value(t, cache.layout_lines[0].row_start, 0)
    testing.expect_value(t, cache.layout_lines[0].row_span, 1)
    testing.expect_value(t, cache.layout_lines[0].baseline_row, 0)
}

//   Verify layout push_item records the block and column metadata.
@(test)
dynview_layout_push_item_records_block_and_column_metadata :: proc(t: ^testing.T) {
    // Confirms pushed layout items capture block metadata and advance line-column bookkeeping correctly.
    cache := new(app_core.Dynview_Compile_Cache)
    defer free(cache)
    arena: app_core.Arena_Owner
    dynview_test_layout_builders_init(t, cache, &arena)
    defer app_core.arena_owner_destroy(&arena)
    cache^.last_cell_width = 8
    state := app_dynlayout.Dynview_Layout_State{
        active_block_id = 7, line_index = 2, col = 1}
    acc := app_dynlayout.Dynview_Layout_Line_Accumulator{}
    item := app_core.Dynview_Layout_Item{
        style_id = dyncore.DYNVIEW_STYLE_OUTPUT,
        col_span = 3,
        ascent = 8,
        descent = 2,
    }

    status := app_dynlayout.layout_push_item(cache, &state, &acc, item)

    testing.expect_value(t, status, dyncore.DYNVIEW_STATUS_OK)
    testing.expect_value(t, cache.layout_item_count, 1)
    testing.expect_value(t, cache.layout_items[0].block_id, 7)
    testing.expect_value(t, cache.layout_items[0].col_start, 1)
    testing.expect_value(t, cache.layout_items[0].row_offset, 0)
    testing.expect_value(t, cache.layout_items[0].row_span, 0)
    testing.expect_value(t, cache.layout_items[0].baseline_row, 0)
    testing.expect_value(t, cache.layout_items[0].content_offset_x, f32(0))
    testing.expect_value(t, cache.layout_items[0].content_offset_y, f32(0))
    testing.expect(t, !cache.layout_items[0].overflows_horizontally)
    testing.expect_value(t, state.col, 4)
    testing.expect_value(t, acc.item_count, 1)
}

//   Verify layout context derives one canonical cell and centered text baseline.
@(test)
dynview_layout_context_derives_canonical_grid_metrics :: proc(t: ^testing.T) {
    cache := new(app_core.Dynview_Compile_Cache)
    defer free(cache)
    cache^.last_font_size = 16
    cache^.last_cell_width = 8
    cache^.last_cell_height = 22
    buffer := new(app_core.Dynview_Command_Buffer)
    defer free(buffer)
    state := app_dynlayout.Dynview_Layout_State{}
    acc := app_dynlayout.Dynview_Layout_Line_Accumulator{}

    ctx := app_dynlayout.layout_build_context(cache, buffer, &state, &acc)
    text_height := ctx.base_ascent + ctx.base_descent
    expected_baseline := max(0.0, (f32(22) - text_height) * 0.5) + ctx.base_ascent

    testing.expect_value(t, ctx.grid_metrics.cell_width, f32(8))
    testing.expect_value(t, ctx.grid_metrics.cell_height, f32(22))
    testing.expect_value(t, ctx.grid_metrics.baseline_from_top, expected_baseline)
}

//   Verify panel capacity and item origins use style-independent canonical columns.
@(test)
dynview_layout_columns_use_canonical_cell_width :: proc(t: ^testing.T) {
    cache := new(app_core.Dynview_Compile_Cache)
    defer free(cache)
    arena: app_core.Arena_Owner
    dynview_test_layout_builders_init(t, cache, &arena)
    defer app_core.arena_owner_destroy(&arena)
    cache^.last_panel_width = 80
    cache^.last_cell_width = 8
    state := app_dynlayout.Dynview_Layout_State{col = 3}
    acc := app_dynlayout.Dynview_Layout_Line_Accumulator{}
    item := app_core.Dynview_Layout_Item{
        kind = .Text_Run,
        style_id = dyncore.DYNVIEW_STYLE_BOLD,
        col_span = 2,
    }

    status := app_dynlayout.layout_push_item(cache, &state, &acc, item)

    testing.expect_value(t, app_dynlayout.layout_max_cols(cache), 8)
    testing.expect_value(t, status, dyncore.DYNVIEW_STATUS_OK)
    testing.expect_value(t, cache^.layout_items[0].col_start, 3)
}

//   Verify mixed baseline and non-baseline items compose one integral row band.
@(test)
dynview_layout_mixed_line_aggregates_grid_rows :: proc(t: ^testing.T) {
    cache := new(app_core.Dynview_Compile_Cache)
    defer free(cache)
    arena: app_core.Arena_Owner
    dynview_test_layout_builders_init(t, cache, &arena)
    defer app_core.arena_owner_destroy(&arena)
    cache^.last_cell_width = 8
    cache^.last_cell_height = 22
    state := app_dynlayout.Dynview_Layout_State{row = 3}
    acc := app_dynlayout.Dynview_Layout_Line_Accumulator{}
    app_dynlayout.layout_seed_line_accumulator(&acc, 0, 12, 4)
    text := app_core.Dynview_Layout_Item{
        kind = .Text_Run, col_span = 1, draw_height = 16, ascent = 12, descent = 4}
    shape := app_core.Dynview_Layout_Item{
        kind = .Inline_Box, col_span = 1, draw_height = 50}

    text_status := app_dynlayout.layout_push_item(cache, &state, &acc, text)
    shape_status := app_dynlayout.layout_push_item(cache, &state, &acc, shape)
    final_status := app_dynlayout.layout_finalize_line(cache, &state, &acc, 12, 4)

    testing.expect_value(t, text_status, dyncore.DYNVIEW_STATUS_OK)
    testing.expect_value(t, shape_status, dyncore.DYNVIEW_STATUS_OK)
    testing.expect_value(t, final_status, dyncore.DYNVIEW_STATUS_OK)
    testing.expect_value(t, cache^.layout_lines[0].row_start, 3)
    testing.expect_value(t, cache^.layout_lines[0].row_span, 3)
    testing.expect_value(t, cache^.layout_lines[0].baseline_row, 1)
    testing.expect_value(t, cache^.layout_items[0].row_offset, 1)
    testing.expect_value(t, cache^.layout_items[1].row_offset, 0)
    testing.expect_value(t, state.row, 6)
}

//   Verify paragraph spacing rounds outward without moving off the row lattice.
@(test)
dynview_layout_paragraph_spacing_rounds_to_rows :: proc(t: ^testing.T) {
    cache := new(app_core.Dynview_Compile_Cache)
    defer free(cache)
    cache^.last_font_size = 16
    cache^.last_cell_width = 8
    cache^.last_cell_height = 22
    buffer := new(app_core.Dynview_Command_Buffer)
    defer free(buffer)
    state := app_dynlayout.Dynview_Layout_State{}
    acc := app_dynlayout.Dynview_Layout_Line_Accumulator{}
    ctx := app_dynlayout.layout_build_context(cache, buffer, &state, &acc)

    first_status := app_dynlayout.layout_apply_block_spacing(&ctx, 22)
    second_status := app_dynlayout.layout_apply_block_spacing(&ctx, 22.1)

    testing.expect_value(t, first_status, dyncore.DYNVIEW_STATUS_OK)
    testing.expect_value(t, second_status, dyncore.DYNVIEW_STATUS_OK)
    testing.expect_value(t, state.row, 3)
}

//   Verify content and scroll-step metrics derive from finalized row spans.
@(test)
dynview_layout_metrics_derive_from_rows :: proc(t: ^testing.T) {
    cache := new(app_core.Dynview_Compile_Cache)
    defer free(cache)
    arena: app_core.Arena_Owner
    dynview_test_layout_builders_init(t, cache, &arena)
    defer app_core.arena_owner_destroy(&arena)
    cache^.last_font_size = 16
    cache^.last_cell_width = 8
    cache^.last_cell_height = 22
    buffer := new(app_core.Dynview_Command_Buffer)
    defer free(buffer)
    state := app_dynlayout.Dynview_Layout_State{}
    acc := app_dynlayout.Dynview_Layout_Line_Accumulator{}
    ctx := app_dynlayout.layout_build_context(cache, buffer, &state, &acc)
    item := app_core.Dynview_Layout_Item{
        kind = .Inline_Box, col_span = 1, draw_height = 50}
    push_status := app_dynlayout.layout_push_item(cache, &state, &acc, item)

    final_status := app_dynlayout.layout_finalize_metrics(&ctx)

    testing.expect_value(t, push_status, dyncore.DYNVIEW_STATUS_OK)
    testing.expect_value(t, final_status, dyncore.DYNVIEW_STATUS_OK)
    testing.expect_value(t, cache^.layout_lines[0].row_span, 3)
    testing.expect_value(t, cache^.layout_total_height, f32(66))
    testing.expect_value(t, cache^.layout_average_line_height, f32(66))
}

//   Verify Scratchpad scrolling consumes finalized row-derived layout metrics.
@(test)
dynview_scratchpad_scroll_metrics_use_grid_rows :: proc(t: ^testing.T) {
    runtime := new(app_core.Dynview_System)
    defer free(runtime)
    runtime^.enabled = true
    runtime^.command_buffer.command_count = 1
    runtime^.compile_cache.layout_is_valid = true
    runtime^.compile_cache.layout_total_height = 66
    runtime^.compile_cache.layout_average_line_height = 44
    fallback := app_dynlayout.Scratchpad_Fallback_Layout{
        text_padding = 4,
        wrap_advance = 8,
        row_height = 22,
        text = "fallback",
    }

    content_height := app_dynlayout.scratchpad_content_height_or_fallback(
        runtime, {width = 80, height = 100}, fallback)
    scroll_step := app_dynlayout.scratchpad_scroll_step_or_fallback(runtime, 22)

    testing.expect_value(t, content_height, f32(74))
    testing.expect_value(t, scroll_step, f32(44))
}

//   Build canonical row spans and copy-hit geometry for one block fixture.
copy_hit_target_fixture :: proc() -> Copy_Hit_Target_Fixture {
    fixture := Copy_Hit_Target_Fixture{}
    fixture.items = {
        {block_id = 9, line_index = 2},
        {block_id = 9, line_index = 5},
    }
    fixture.lines[2] = {row_start = 2, row_span = 3}
    fixture.lines[5] = {row_start = 7, row_span = 2}
    fixture.layout = {
        panel = {x = 10, y = 100, width = 120, height = 250},
        scroll_y = 22, text_padding = 4, icon_size = 12, icon_x_pad = 2,
    }
    return fixture
}

//   Bind fixture-backed row records to one compile cache.
copy_hit_target_fixture_bind :: proc(
    cache: ^app_core.Dynview_Compile_Cache,
    fixture: ^Copy_Hit_Target_Fixture) {
    cache^.last_cell_height = 22
    cache^.layout_items = fixture^.items[:]
    cache^.layout_lines = fixture^.lines[:]
    cache^.layout_line_count = len(fixture^.lines)
    cache^.layout_item_count = len(fixture^.items)
}

//   Verify copy hit geometry spans canonical rows after applying panel scroll.
@(test)
dynview_copy_hit_target_uses_grid_row_bounds :: proc(t: ^testing.T) {
    arena: app_core.Arena_Owner
    testing.expect(t, app_core.arena_owner_init(&arena))
    defer app_core.arena_owner_destroy(&arena)
    cache := new(app_core.Dynview_Compile_Cache)
    defer free(cache)
    testing.expect_value(t, app_core.bounded_element_builder_init(
        &cache^.copy_hit_target_builder, app_core.DYNVIEW_MAX_COMMANDS, &arena),
        app_core.Bounded_Builder_Status.Ok)
    fixture := copy_hit_target_fixture()
    copy_hit_target_fixture_bind(cache, &fixture)

    hover_bottom, status := app_dyncompile.rebuild_one_copy_hit_target(
        cache, {block_id = 9}, fixture.layout, fixture.layout.panel.y)

    targets, view_status := app_core.bounded_element_builder_view(
        &cache^.copy_hit_target_builder)
    testing.expect_value(t, status, dyncore.DYNVIEW_STATUS_OK)
    testing.expect_value(t, view_status, app_core.Bounded_Builder_Status.Ok)
    testing.expect_value(t, len(targets), 1)
    target := targets[0]
    testing.expect_value(t, target.hover_rect.y, f32(126))
    testing.expect_value(t, target.hover_rect.height, f32(154))
    testing.expect_value(t, hover_bottom, f32(280))
}

//   Verify outer math reserves canonical columns and marks constrained overflow.
@(test)
dynview_math_block_columns_use_intrinsic_width :: proc(t: ^testing.T) {
    exact := app_dynlayout.math_block_columns(16, 8, 10)
    fractional := app_dynlayout.math_block_columns(16.1, 8, 10)
    oversized := app_dynlayout.math_block_columns(81, 8, 10)

    testing.expect_value(t, exact.span, 2)
    testing.expect(t, !exact.overflows_horizontally)
    testing.expect_value(t, fractional.span, 3)
    testing.expect(t, !fractional.overflows_horizontally)
    testing.expect_value(t, oversized.span, 10)
    testing.expect(t, oversized.overflows_horizontally)
}

//   Verify outer math placement includes visual padding and preserves its baseline.
@(test)
dynview_math_block_placement_includes_visual_padding :: proc(t: ^testing.T) {
    cache := new(app_core.Dynview_Compile_Cache)
    defer free(cache)
    cache^.last_cell_width = 8
    cache^.last_cell_height = 22
    item := app_core.Dynview_Layout_Item{
        kind = .Math_Block,
        col_span = 2,
        draw_width = 13,
        draw_height = 32,
        ascent = 25,
        descent = 7,
        visual_padding_top = 3,
        visual_padding_bottom = 4,
    }
    cells := app_dynlayout.layout_cell_metrics(cache, 12, 4)

    placement, ok := app_dynlayout.layout_place_item_on_grid(&item, cells)

    testing.expect(t, ok)
    testing.expect_value(t, placement.column_span, 2)
    testing.expect_value(t, placement.row_span, 3)
    testing.expect_value(t, placement.baseline_row, 1)
    testing.expect_value(t, placement.content_offset_x, f32(1.5))
    testing.expect_value(t, placement.content_offset_y, f32(9))
    baseline_y := placement.content_offset_y + item.visual_padding_top + item.ascent
    expected_baseline := f32(placement.baseline_row) * cells.cell_height +
        cells.baseline_from_top
    testing.expect_value(t, baseline_y, expected_baseline)
}

//   Verify oversized outer math keeps intrinsic width and centers into its reservation.
@(test)
dynview_math_block_overflow_is_symmetric_and_explicit :: proc(t: ^testing.T) {
    cache := new(app_core.Dynview_Compile_Cache)
    defer free(cache)
    cache^.last_cell_width = 8
    cache^.last_cell_height = 22
    program := app_core.Dynview_Math_Program{
        draw_width = 24,
        ascent = 12,
        descent = 4,
    }
    item := app_dynlayout.math_block_item({}, app_dynlayout.Math_Block_Layout{
        program = &program,
        max_cols = 2,
        cols = 2,
        overflows_horizontally = true,
    })
    cells := app_dynlayout.layout_cell_metrics(cache, 12, 4)

    placement, ok := app_dynlayout.layout_place_item_on_grid(&item, cells)

    testing.expect(t, ok)
    testing.expect(t, item.overflows_horizontally)
    testing.expect_value(t, item.draw_width, f32(24))
    testing.expect_value(t, placement.column_span, 2)
    testing.expect_value(t, placement.allocated_width, f32(16))
    testing.expect_value(t, placement.content_offset_x, f32(-4))
}

//   Verify text and padded outer math resolve to one canonical line baseline.
@(test)
dynview_math_block_aligns_with_text_baseline :: proc(t: ^testing.T) {
    cache := new(app_core.Dynview_Compile_Cache)
    defer free(cache)
    arena: app_core.Arena_Owner
    dynview_test_layout_builders_init(t, cache, &arena)
    defer app_core.arena_owner_destroy(&arena)
    cache^.last_cell_width = 8
    cache^.last_cell_height = 22
    state := app_dynlayout.Dynview_Layout_State{}
    acc := app_dynlayout.Dynview_Layout_Line_Accumulator{}
    app_dynlayout.layout_seed_line_accumulator(&acc, 0, 12, 4)
    text := app_core.Dynview_Layout_Item{
        kind = .Text_Run, col_span = 1, draw_height = 16, ascent = 12, descent = 4}
    math_item := app_core.Dynview_Layout_Item{
        kind = .Math_Block, col_span = 2, draw_width = 13, draw_height = 32,
        ascent = 25, descent = 7,
        visual_padding_top = 3, visual_padding_bottom = 4}

    text_status := app_dynlayout.layout_push_item(cache, &state, &acc, text)
    math_status := app_dynlayout.layout_push_item(cache, &state, &acc, math_item)
    final_status := app_dynlayout.layout_finalize_line(cache, &state, &acc, 12, 4)

    testing.expect_value(t, text_status, dyncore.DYNVIEW_STATUS_OK)
    testing.expect_value(t, math_status, dyncore.DYNVIEW_STATUS_OK)
    testing.expect_value(t, final_status, dyncore.DYNVIEW_STATUS_OK)
    text_item := cache^.layout_items[0]
    placed_math := cache^.layout_items[1]
    text_baseline := f32(text_item.row_offset) * 22 +
        text_item.content_offset_y + text_item.ascent
    math_baseline := f32(placed_math.row_offset) * 22 +
        placed_math.content_offset_y + placed_math.visual_padding_top +
        placed_math.ascent
    testing.expect_value(t, text_baseline, math_baseline)
    testing.expect_value(t, cache^.layout_lines[0].baseline_row, 1)
}

//   Finalize one line holding a single math block of the requested vertical extent.
dynview_test_finalize_math_line :: proc(
    cache: ^app_core.Dynview_Compile_Cache,
    state: ^app_dynlayout.Dynview_Layout_State,
    acc: ^app_dynlayout.Dynview_Layout_Line_Accumulator,
    ascent, descent: f32) -> i32 {

    item := app_core.Dynview_Layout_Item{
        kind = .Math_Block, col_span = 1, draw_width = 8,
        draw_height = ascent + descent, ascent = ascent, descent = descent}
    if status := app_dynlayout.layout_push_item(cache, state, acc, item);
        status != dyncore.DYNVIEW_STATUS_OK {
        return status
    }
    return app_dynlayout.layout_finalize_line(cache, state, acc, 12, 4)
}

//   Verify inline math within the lineskip allowance keeps its line one row tall.
@(test)
dynview_line_permits_ink_overflow_into_neighbor_leading :: proc(t: ^testing.T) {
    cache := new(app_core.Dynview_Compile_Cache)
    defer free(cache)
    arena: app_core.Arena_Owner
    dynview_test_layout_builders_init(t, cache, &arena)
    defer app_core.arena_owner_destroy(&arena)
    cache^.last_cell_width = 8
    cache^.last_cell_height = 22
    state := app_dynlayout.Dynview_Layout_State{}
    acc := app_dynlayout.Dynview_Layout_Line_Accumulator{}
    app_dynlayout.layout_seed_line_accumulator(&acc, 0, 12, 4)

    text := app_core.Dynview_Layout_Item{
        kind = .Text_Run, col_span = 1, draw_height = 16, ascent = 12, descent = 4}
    text_status := app_dynlayout.layout_push_item(cache, &state, &acc, text)
    first_status := app_dynlayout.layout_finalize_line(cache, &state, &acc, 12, 4)
    second_status := dynview_test_finalize_math_line(cache, &state, &acc, 17, 4)

    testing.expect_value(t, text_status, dyncore.DYNVIEW_STATUS_OK)
    testing.expect_value(t, first_status, dyncore.DYNVIEW_STATUS_OK)
    testing.expect_value(t, second_status, dyncore.DYNVIEW_STATUS_OK)
    testing.expect_value(t, cache^.layout_lines[0].ink_slack_below, f32(3))
    testing.expect_value(t, cache^.layout_lines[1].row_span, 1)
    testing.expect_value(t, cache^.layout_items[1].content_offset_y, f32(-2))
}

//   Verify ink beyond the lineskip allowance still reserves an additional row.
@(test)
dynview_line_reserves_row_when_ink_exceeds_allowance :: proc(t: ^testing.T) {
    cache := new(app_core.Dynview_Compile_Cache)
    defer free(cache)
    arena: app_core.Arena_Owner
    dynview_test_layout_builders_init(t, cache, &arena)
    defer app_core.arena_owner_destroy(&arena)
    cache^.last_cell_width = 8
    cache^.last_cell_height = 22
    state := app_dynlayout.Dynview_Layout_State{}
    acc := app_dynlayout.Dynview_Layout_Line_Accumulator{}
    app_dynlayout.layout_seed_line_accumulator(&acc, 0, 12, 4)

    status := dynview_test_finalize_math_line(cache, &state, &acc, 19, 4)

    testing.expect_value(t, status, dyncore.DYNVIEW_STATUS_OK)
    testing.expect_value(t, cache^.layout_lines[0].row_span, 2)
    testing.expect_value(t, cache^.layout_lines[0].baseline_row, 1)
}

//   Verify an oversized inline line preserves geometry and centers its clipping.
expect_oversized_inline_line_grid_placement :: proc(
    t: ^testing.T,
    cache: ^app_core.Dynview_Compile_Cache,
    style: dyncore.Dynview_Text_Style,
    cells: app_grid.Cell_Metrics) {

    cmd := app_core.Dynview_Command{
        kind = .Inline_Line,
        inline_atom_dimension = 4,
        inline_atom_stroke = 4,
    }
    cols := app_dynlayout.inline_line_cols(cmd, style, 8, 2)
    item := app_dynlayout.inline_line_item({
        cache = cache,
        cmd = cmd,
        style = style,
        metrics = {max_cols = 2, cols = cols},
    })
    placement, ok := app_dynlayout.layout_place_item_on_grid(&item, cells)

    testing.expect(t, ok)
    testing.expect_value(t, cols, 2)
    testing.expect_value(t, item.draw_width, f32(36))
    testing.expect_value(t, placement.content_offset_x, f32(-10))
    testing.expect(t, item.overflows_horizontally)
}

//   Verify inline lines preserve intrinsic length and stroke inside grid placement.
@(test)
dynview_inline_line_uses_intrinsic_grid_embedding :: proc(t: ^testing.T) {
    cache := new(app_core.Dynview_Compile_Cache)
    defer free(cache)
    cache^ = app_core.Dynview_Compile_Cache{
        last_cell_width = 8,
        last_cell_height = 22,
    }
    cmd := app_core.Dynview_Command{
        kind = .Inline_Line,
        inline_atom_dimension = 2.25,
        inline_atom_stroke = 4,
    }
    style := dyncore.style_by_id(dyncore.DYNVIEW_STYLE_BOLD)
    cols := app_dynlayout.inline_line_cols(cmd, style, 8, 10)
    item := app_dynlayout.inline_line_item({
        cache = cache,
        cmd = cmd,
        style = style,
        metrics = {max_cols = 10, cols = cols},
    })
    cells := app_dynlayout.layout_cell_metrics(cache, 12, 4)

    placement, ok := app_dynlayout.layout_place_item_on_grid(&item, cells)

    testing.expect(t, ok)
    testing.expect_value(t, cols, 3)
    testing.expect_value(t, item.draw_width, f32(22))
    testing.expect_value(t, item.draw_height, f32(4))
    testing.expect_value(t, placement.column_span, 3)
    testing.expect_value(t, placement.row_span, 1)
    testing.expect_value(t, placement.content_offset_x, f32(1))
    testing.expect_value(t, placement.content_offset_y, f32(9))
    testing.expect(t, !item.overflows_horizontally)

    expect_oversized_inline_line_grid_placement(t, cache, style, cells)
}

//   Verify every inline shape family reports stroke-inclusive intrinsic bounds.
@(test)
dynview_inline_shape_families_report_intrinsic_bounds :: proc(t: ^testing.T) {
    box := app_dynlayout.inline_shape_geometry(app_core.Dynview_Command{
        kind = .Inline_Box, inline_atom_dimension = 2.5,
        inline_box_height = 3, inline_atom_stroke = 2}, 8)
    filled_box := app_dynlayout.inline_shape_geometry(app_core.Dynview_Command{
        kind = .Inline_Filled_Box, inline_atom_dimension = 2.5,
        inline_box_height = 3, inline_outline_stroke = 3}, 8)
    circle := app_dynlayout.inline_shape_geometry(app_core.Dynview_Command{
        kind = .Inline_Circle, inline_atom_dimension = 1.25,
        inline_atom_stroke = 2}, 8)
    filled_circle := app_dynlayout.inline_shape_geometry(app_core.Dynview_Command{
        kind = .Inline_Filled_Circle, inline_atom_dimension = 1.25,
        inline_outline_stroke = 3}, 8)
    perpendicular := app_dynlayout.inline_shape_geometry(app_core.Dynview_Command{
        kind = .Inline_Perpendicular, inline_atom_dimension = 4,
        inline_box_height = 5, inline_atom_stroke = 2}, 8)
    triangle := app_dynlayout.inline_shape_geometry(app_core.Dynview_Command{
        kind = .Inline_Triangle, inline_atom_dimension = 4,
        inline_box_height = 5, inline_atom_stroke = 2}, 8)
    pentagon := app_dynlayout.inline_shape_geometry(app_core.Dynview_Command{
        kind = .Inline_Pentagon, inline_atom_dimension = 4,
        inline_box_height = 5, inline_atom_stroke = 2}, 8)

    testing.expect_value(t, box.draw_width, f32(22))
    testing.expect_value(t, box.draw_height, f32(26))
    testing.expect_value(t, filled_box.draw_width, f32(23))
    testing.expect_value(t, filled_box.draw_height, f32(27))
    testing.expect_value(t, circle.draw_width, f32(22))
    testing.expect_value(t, circle.draw_height, f32(22))
    testing.expect_value(t, filled_circle.draw_width, f32(23))
    testing.expect_value(t, filled_circle.draw_height, f32(23))
    testing.expect_value(t, perpendicular, triangle)
    testing.expect_value(t, triangle, pentagon)
    testing.expect_value(t, triangle.draw_width, f32(34))
    testing.expect_value(t, triangle.draw_height, f32(42))
}

//   Verify one tall box retains intrinsic geometry inside centered grid rows.
expect_tall_inline_box_grid_placement :: proc(
    t: ^testing.T,
    cache: ^app_core.Dynview_Compile_Cache,
    bold: dyncore.Dynview_Text_Style,
    cells: app_grid.Cell_Metrics) {

    box_cmd := app_core.Dynview_Command{
        kind = .Inline_Box,
        inline_atom_dimension = 2.5,
        inline_box_height = 4,
        inline_atom_stroke = 2,
    }
    box_cols := app_dynlayout.inline_box_cols(box_cmd, bold, 8, 10)
    box_item := app_dynlayout.inline_box_item({
        cache = cache,
        cmd = box_cmd,
        style = bold,
        metrics = {max_cols = 10, cols = box_cols},
    })
    box_placement, box_ok :=
        app_dynlayout.layout_place_item_on_grid(&box_item, cells)

    testing.expect(t, box_ok)
    testing.expect_value(t, box_cols, 3)
    testing.expect_value(t, box_item.draw_width, f32(22))
    testing.expect_value(t, box_item.draw_height, f32(34))
    testing.expect_value(t, box_placement.row_span, 2)
    testing.expect_value(t, box_placement.content_offset_x, f32(1))
    testing.expect_value(t, box_placement.content_offset_y, f32(5))
}

//   Verify one oversized triangle retains geometry and centers its clipping.
expect_oversized_inline_triangle_grid_placement :: proc(
    t: ^testing.T,
    cache: ^app_core.Dynview_Compile_Cache,
    bold: dyncore.Dynview_Text_Style,
    cells: app_grid.Cell_Metrics) {

    triangle_cmd := app_core.Dynview_Command{
        kind = .Inline_Triangle,
        inline_atom_dimension = 10,
        inline_box_height = 2,
        inline_atom_stroke = 2,
    }
    triangle_cols := app_dynlayout.inline_box_cols(triangle_cmd, bold, 8, 4)
    triangle_item := app_dynlayout.inline_triangle_item({
        cache = cache,
        cmd = triangle_cmd,
        style = bold,
        metrics = {max_cols = 4, cols = triangle_cols},
    })
    triangle_placement, triangle_ok :=
        app_dynlayout.layout_place_item_on_grid(&triangle_item, cells)
    testing.expect(t, triangle_ok)
    testing.expect_value(t, triangle_cols, 4)
    testing.expect_value(t, triangle_item.draw_width, f32(82))
    testing.expect_value(t, triangle_placement.content_offset_x, f32(-25))
    testing.expect(t, triangle_item.overflows_horizontally)
}

//   Verify shape grid placement preserves tall geometry and symmetric overflow.
@(test)
dynview_inline_shapes_use_centered_grid_placement :: proc(t: ^testing.T) {
    cache := new(app_core.Dynview_Compile_Cache)
    defer free(cache)
    cache^.last_cell_width = 8
    cache^.last_cell_height = 22
    bold := dyncore.style_by_id(dyncore.DYNVIEW_STYLE_BOLD)
    cells := app_dynlayout.layout_cell_metrics(cache, 12, 4)

    expect_tall_inline_box_grid_placement(t, cache, bold, cells)
    expect_oversized_inline_triangle_grid_placement(t, cache, bold, cells)
}

//   Verify pie sections retain tight wedge bounds including outline stroke.
@(test)
dynview_inline_pie_section_retains_tight_visual_bounds :: proc(t: ^testing.T) {
    cmd := app_core.Dynview_Command{
        kind = .Inline_Pie_Section,
        inline_atom_dimension = 1,
        inline_outline_stroke = 2,
        pie_start_angle_degrees = 0,
        pie_end_angle_degrees = 90,
        pie_is_filled = true,
    }
    geometry := app_dynlayout.inline_shape_geometry(cmd, 8)
    bold := dyncore.style_by_id(dyncore.DYNVIEW_STYLE_BOLD)
    regular := dyncore.style_by_id(dyncore.DYNVIEW_STYLE_OUTPUT)

    testing.expect_value(t, geometry.draw_width, f32(10))
    testing.expect_value(t, geometry.draw_height, f32(10))
    testing.expect(t, math.abs(geometry.center_offset_x - 1) <= 0.0001)
    testing.expect(t, math.abs(geometry.center_offset_y - 9) <= 0.0001)
    testing.expect_value(t,
        app_dynlayout.inline_pie_section_cols(cmd, bold, 8, 10), 2)
    testing.expect_value(t,
        app_dynlayout.inline_pie_section_cols(cmd, regular, 8, 10), 2)
}

//   Verify layout text-run consumption wraps and places each segment.
@(test)
dynview_layout_consume_text_run_wraps_and_places_segments :: proc(t: ^testing.T) {
    // Checks wrapped text-run consumption emits layout items and lines with a valid reported last line index.
    cache := new(app_core.Dynview_Compile_Cache)
    defer free(cache)
    arena: app_core.Arena_Owner
    dynview_test_layout_builders_init(t, cache, &arena)
    defer app_core.arena_owner_destroy(&arena)
    cache^.last_panel_width = 48
    cache.last_cell_width = 8
    cache.last_cell_height = 22
    cache.last_font_size = 12

    buffer := new(app_core.Dynview_Command_Buffer)
    defer free(buffer)
    state := app_dynlayout.Dynview_Layout_State{}
    acc := app_dynlayout.Dynview_Layout_Line_Accumulator{}
    cmd := app_core.Dynview_Command{
        style_id = dyncore.DYNVIEW_STYLE_OUTPUT,
        has_brush_color = true,
        brush_color = {64, 99, 216, 255},
    }
    style := dyncore.style_by_id(dyncore.DYNVIEW_STYLE_OUTPUT)
    layout_context := app_dynlayout.layout_build_context(cache, buffer, &state, &acc)

    status, last_line := app_dynlayout.layout_consume_text_run(
        &layout_context, cmd, "hello world", style)

    testing.expect_value(t, status, dyncore.DYNVIEW_STATUS_OK)
    testing.expect(t, cache.layout_item_count > 0)
    testing.expect(t, cache.layout_line_count > 0)
    testing.expect(t, last_line >= 0)
    for item_index in 0..<cache.layout_item_count {
        testing.expect(t, cache.layout_items[item_index].has_brush_color)
        testing.expect_value(t, cache.layout_items[item_index].brush_color.r, u8(64))
        testing.expect_value(t, cache.layout_items[item_index].brush_color.g, u8(99))
        testing.expect_value(t, cache.layout_items[item_index].brush_color.b, u8(216))
    }
}

//   Verify the math helpers scale script geometry with the script scale.
@(test)
dynview_math_helpers_scale_script_geometry :: proc(t: ^testing.T) {
    // Ensures script math helper outputs produce sensible ascent, descent, offsets, and visual padding values.
    style := dyncore.style_by_id(dyncore.DYNVIEW_STYLE_BOLD)
    ascent, descent := dyncore.style_ascent_descent(style, 12)

    testing.expect(t, ascent > descent)
    testing.expect(t, ascent > 8)

    offsets := app_math.script_draw_offsets(12, 1.0, 0.25, 0.25)
    top_pad, bottom_pad := app_math.script_visual_padding(offsets.script_font_size)

    testing.expect(t, offsets.script_font_size > 1.0)
    testing.expect(t, offsets.sup_raise_px >= 0)
    testing.expect(t, offsets.sub_drop_px >= 0)
    testing.expect(t, top_pad > 0)
    testing.expect(t, bottom_pad > 0)
}

//   Verify the math size helpers scale with content and operator kind.
@(test)
dynview_math_size_helpers_scale_with_content_and_kind :: proc(t: ^testing.T) {
    // Verifies delimiter and large-operator sizing helpers scale with content height and operator kind.
    style := dyncore.style_by_id(dyncore.DYNVIEW_STYLE_OUTPUT)

    width_none := app_math.stretch_delimiter_width(
        style, 8, 16, 10, app_math.DELIMITER_KIND_NONE)
    width_paren := app_math.stretch_delimiter_width(
        style, 8, 16, 50, app_math.DELIMITER_KIND_LEFT_PAREN)
    width_bigger := app_math.stretch_delimiter_width(
        style, 8, 16, 120, app_math.DELIMITER_KIND_LEFT_PAREN)

    testing.expect_value(t, width_none, f32(0))
    testing.expect(t, width_paren > 0)
    testing.expect(t, width_bigger > width_paren)

    glyph_scale_sum := app_math.large_op_glyph_scale(app_math.LARGE_OP_KIND_SUM)
    glyph_scale_int := app_math.large_op_glyph_scale(app_math.LARGE_OP_KIND_INT)
    glyph_scale_nary := app_math.large_op_glyph_scale(app_math.LARGE_OP_KIND_NARY)
    limit_scale := app_math.large_op_limit_scale(0.8)
    gap := app_math.large_op_limit_gap_for_kind(
        app_math.LARGE_OP_KIND_INT, 16, 0.25)

    testing.expect(t, glyph_scale_sum > 1)
    testing.expect(t, glyph_scale_int > glyph_scale_sum)
    testing.expect_value(t, glyph_scale_nary, glyph_scale_sum)
    testing.expect(t, limit_scale > 0)
    testing.expect(t, gap > 0)
}

//   Verify measure_math_program aggregates child metrics into the program.
@(test)
dynview_measure_math_program_aggregates_child_metrics :: proc(t: ^testing.T) {
    // Confirms math program measurement aggregates child command metrics into non-zero outer dimensions.
    cache := new(app_core.Dynview_Compile_Cache)
    defer free(cache)
    cache^.last_cell_width = 8
    cache^.math_program_count = 1
    cache^.math_command_count = 1

    buffer := new(app_core.Dynview_Command_Buffer)
    defer free(buffer)
    buffer.text_bytes[0] = 'a'
    buffer.text_bytes[1] = 'b'
    buffer.text_bytes_len = 2

    cache^.math_commands[0] = app_core.Dynview_Command{
        kind = .Text_Run,
        style_id = dyncore.DYNVIEW_STYLE_OUTPUT,
        text_offset = 0,
        text_len = 2,
    }

    program := &cache^.math_programs[0]
    program^.valid = true
    program^.command_start = 0
    program^.command_count = 1

    ok := app_math.measure_math_program(cache, buffer, program, 12)

    testing.expect(t, ok)
    testing.expect(t, program.draw_width > 0)
    testing.expect(t, program.ascent > 0)
    testing.expect(t, program.descent > 0)
}

//   Verify the math spacing helpers produce stable positive sizes.
@(test)
dynview_math_spacing_helpers_produce_stable_positive_sizes :: proc(t: ^testing.T) {
    // Checks fraction and radical spacing helpers return positive values and scale upward with larger inputs.
    side_pad_small := app_math.fraction_side_padding(10, 4)
    side_pad_large := app_math.fraction_side_padding(24, 10)
    vert_gap_small := app_math.fraction_vertical_gap(10)
    vert_gap_large := app_math.fraction_vertical_gap(24)

    testing.expect(t, side_pad_small > 0)
    testing.expect(t, side_pad_large > side_pad_small)
    testing.expect(t, vert_gap_small > 0)
    testing.expect(t, vert_gap_large > vert_gap_small)

    lead_width := app_math.radical_lead_width(16, 8)
    front_pad, back_pad := app_math.radical_side_paddings(16, 8)
    testing.expect(t, lead_width > 0)
    testing.expect(t, front_pad > 0)
    testing.expect(t, back_pad > 0)
}

//   Verify the integral large-operator gap is tighter than the sum operator gap.
@(test)
dynview_large_operator_gap_for_integral_is_tighter_than_sum :: proc(t: ^testing.T) {
    // Verifies integral stacked-limit gap is intentionally tighter than the sum/product stacked-limit gap.
    gap_sum := app_math.large_op_limit_gap_for_kind(
        app_math.LARGE_OP_KIND_SUM, 16, 0.25)
    gap_int := app_math.large_op_limit_gap_for_kind(
        app_math.LARGE_OP_KIND_INT, 16, 0.25)

    testing.expect(t, gap_sum > 0)
    testing.expect(t, gap_int > 0)
    testing.expect(t, gap_int < gap_sum)
}

//   Verify measure_math_program rejects invalid program shapes.
@(test)
dynview_measure_math_program_rejects_invalid_shapes :: proc(t: ^testing.T) {
    // Ensures math program measurement rejects invalid or out-of-range command windows.
    cache := new(app_core.Dynview_Compile_Cache)
    defer free(cache)

    buffer := new(app_core.Dynview_Command_Buffer)
    defer free(buffer)

    invalid_program := app_core.Dynview_Math_Program{}
    invalid_program.valid = false
    testing.expect(t, !app_math.measure_math_program(
        cache, buffer, &invalid_program, 12))

    invalid_program.valid = true
    invalid_program.command_start = 0
    invalid_program.command_count = 0
    testing.expect(t, !app_math.measure_math_program(
        cache, buffer, &invalid_program, 12))

    cache^.math_command_count = 1
    invalid_program.command_start = 1
    invalid_program.command_count = 1
    testing.expect(t, !app_math.measure_math_program(
        cache, buffer, &invalid_program, 12))
}

//   Seed a cache with two text-run commands over a 3-byte buffer.
dynview_seed_two_command_cache :: proc(
    cache: ^app_core.Dynview_Compile_Cache,
    buffer: ^app_core.Dynview_Command_Buffer) {

    cache^.last_cell_width = 8
    cache^.math_program_count = 2
    cache^.math_command_count = 2

    buffer.text_bytes[0] = 'a'
    buffer.text_bytes[1] = 'b'
    buffer.text_bytes[2] = 'c'
    buffer.text_bytes_len = 3

    cache^.math_commands[0] = app_core.Dynview_Command{
        kind = .Text_Run,
        style_id = dyncore.DYNVIEW_STYLE_OUTPUT,
        text_offset = 0,
        text_len = 2,
    }
    cache^.math_commands[1] = app_core.Dynview_Command{
        kind = .Text_Run,
        style_id = dyncore.DYNVIEW_STYLE_OUTPUT,
        text_offset = 2,
        text_len = 1,
    }
}

//   Verify measure_math_program sums multiple command widths.
@(test)
dynview_measure_math_program_sums_multiple_command_widths :: proc(t: ^testing.T) {
    // Confirms measured width increases when additional child commands are included in the same math program.
    cache := new(app_core.Dynview_Compile_Cache)
    defer free(cache)

    buffer := new(app_core.Dynview_Command_Buffer)
    defer free(buffer)
    dynview_seed_two_command_cache(cache, buffer)

    one_cmd := &cache^.math_programs[0]
    one_cmd^.valid = true
    one_cmd^.command_start = 0
    one_cmd^.command_count = 1

    two_cmd := &cache^.math_programs[1]
    two_cmd^.valid = true
    two_cmd^.command_start = 0
    two_cmd^.command_count = 2

    ok_one := app_math.measure_math_program(cache, buffer, one_cmd, 12)
    ok_two := app_math.measure_math_program(cache, buffer, two_cmd, 12)

    testing.expect(t, ok_one)
    testing.expect(t, ok_two)
    testing.expect(t, two_cmd.draw_width > one_cmd.draw_width)
}

//   Verify reset_cache clears the dynview layout state.
@(test)
dynview_reset_cache_clears_layout_state :: proc(t: ^testing.T) {
    // Verifies layout cache reset clears counters, aggregate metrics, and layout validity state.
    cache := new(app_core.Dynview_Compile_Cache)
    defer free(cache)
    cache^.layout_line_count = 2
    cache.layout_item_count = 3
    cache.layout_total_height = 9
    cache.layout_average_line_height = 4
    cache.layout_is_valid = true

    app_math.layout_reset_cache(cache)

    testing.expect_value(t, cache.layout_line_count, 0)
    testing.expect_value(t, cache.layout_item_count, 0)
    testing.expect_value(t, cache.layout_total_height, f32(0))
    testing.expect_value(t, cache.layout_average_line_height, f32(0))
    testing.expect(t, !cache.layout_is_valid)
}
