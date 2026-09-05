package view

import "core:strings"
import "core:testing"

import app_core "../core"
import app_bridge "../bridge"
import evidence_session "../evidence/session"
import evidence_trace "../evidence/trace"
import app_view "./core"

//   Verify clearing then setting a long GIF status note truncates with a terminator.
@(test)
clear_and_set_gif_status_note_handles_truncation :: proc(t: ^testing.T) {
    ui_runtime := new(app_core.Euclid_Ui_Runtime_State)
    defer free(ui_runtime)

    app_view.clear_gif_status_note(ui_runtime)
    testing.expect_value(t, ui_runtime^.gif_status_note_len, 0)
    testing.expect_value(t, ui_runtime^.gif_status_note[0], u8(0))

    long_note := strings.repeat(
        "x", len(ui_runtime^.gif_status_note) + 20, context.temp_allocator)
    app_view.set_gif_status_note(ui_runtime, long_note)

    expected_len := len(ui_runtime^.gif_status_note) - 1
    testing.expect_value(t, ui_runtime^.gif_status_note_len, expected_len)
    testing.expect_value(t, ui_runtime^.gif_status_note[expected_len], u8(0))
}

//   Verify clearing then setting a long GIF path truncates with a terminator.
@(test)
clear_and_set_last_gif_path_handles_truncation :: proc(t: ^testing.T) {
    ui_runtime := new(app_core.Euclid_Ui_Runtime_State)
    defer free(ui_runtime)

    app_view.clear_last_gif_path(ui_runtime)
    testing.expect_value(t, ui_runtime^.last_gif_path_len, 0)
    testing.expect_value(t, ui_runtime^.last_gif_path[0], u8(0))

    long_path := strings.repeat(
        "a", len(ui_runtime^.last_gif_path) + 32, context.temp_allocator)
    app_view.set_last_gif_path(ui_runtime, long_path)

    expected_len := len(ui_runtime^.last_gif_path) - 1
    testing.expect_value(t, ui_runtime^.last_gif_path_len, expected_len)
    testing.expect_value(t, ui_runtime^.last_gif_path[expected_len], u8(0))
}

//   Verify gif_capture_delay_centiseconds maps frame steps to expected delays.
@(test)
gif_capture_delay_centiseconds_matches_expected_steps :: proc(t: ^testing.T) {
    testing.expect_value(t, app_view.gif_capture_delay_centiseconds(1), 2)
    testing.expect_value(t, app_view.gif_capture_delay_centiseconds(4), 7)
    testing.expect_value(t, app_view.gif_capture_delay_centiseconds(0), 1)
}

//   Verify gif_capture_scaled_extent matches the screen-to-render ratio with rounding.
@(test)
gif_capture_scaled_extent_matches_screen_to_render_ratio :: proc(t: ^testing.T) {
    one_x := app_view.gif_capture_scaled_extent(900, 1280, 1280)
    testing.expect_value(t, one_x, 900)

    two_x := app_view.gif_capture_scaled_extent(900, 1280, 2560)
    testing.expect_value(t, two_x, 1800)

    round_nearest := app_view.gif_capture_scaled_extent(3, 2, 3)
    testing.expect_value(t, round_nearest, 5)

    safe_minimum := app_view.gif_capture_scaled_extent(0, 0, 0)
    testing.expect_value(t, safe_minimum, 1)
}

//   Verify a cycle boundary is consumed exactly once per generation.
@(test)
gif_capture_consume_cycle_boundary_consumes_once_per_generation :: proc(t: ^testing.T) {
    state := new(app_core.Euclid_General_State)
    defer free(state)

    testing.expect(t, !app_view.gif_capture_consume_cycle_boundary(state))

    state^.cycle_boundary_generation = 1
    testing.expect(t, app_view.gif_capture_consume_cycle_boundary(state))
    testing.expect(t, !app_view.gif_capture_consume_cycle_boundary(state))

    state^.cycle_boundary_generation = 2
    testing.expect(t, app_view.gif_capture_consume_cycle_boundary(state))
}

//   Verify aborting an inactive GIF capture session is a safe no-op.
@(test)
gif_capture_abort_session_is_safe_when_inactive :: proc(t: ^testing.T) {
    session := app_core.Gif_Capture_Session{}
    app_view.gif_capture_abort_session(&session)
    testing.expect(t, !session.active)
}

//   Verify GIF lifecycle transitions retain required typed display evidence.
@(test)
gif_capture_transitions_record_required_evidence :: proc(t: ^testing.T) {
    state := new(app_core.Euclid_General_State, context.allocator)
    defer free(state)
    testing.expect(t, evidence_session.session_init(&state^.evidence_session, {
        enabled = true,
        output_mode = .Sink,
        lanes = {.Presentation},
    }))
    evidence_trace.ring_init(&state^.evidence_ring, .Display)

    record_gif_capture_transition(state, .Armed, .Recording)
    record_gif_capture_transition(state, .Recording, .Saved)
    record_gif_capture_transition(state, .Recording, .Error)

    events: [3]evidence_trace.Event
    count := evidence_trace.ring_drain(&state^.evidence_ring, events[:])
    testing.expect_value(t, count, 3)
    testing.expect_value(t, events[0].kind, evidence_trace.Kind.Gif_Started)
    testing.expect_value(t, events[1].kind, evidence_trace.Kind.Gif_Completed)
    testing.expect_value(t, events[2].kind, evidence_trace.Kind.Gif_Failed)
    testing.expect(t, .Required in events[0].flags)
    testing.expect(t, .Failure in events[2].flags)
}

//   Verify a large hide-point batch splits into multiple commands.
@(test)
scene_command_batch_splits_large_hide_point_batches :: proc(t: ^testing.T) {
    state := new(app_core.Euclid_General_State)
    defer free(state)

    state^.point_system = new(app_core.Shapes_Point_System)
    defer free(state^.point_system)
    state^.julia_interface = new(app_core.Euclid_Julia_Interface)
    defer free(state^.julia_interface)
    state^.julia_interface^.current_animation =
        new(app_core.Euclid_Julia_Animation_Interface)
    defer free(state^.julia_interface^.current_animation)

    batch: app_bridge.Scene_Command_Batch
    app_bridge.begin_scene_command_batch(state, &batch)

    ids: [10]i32
    for i in 0..<len(ids) {
        ids[i] = i32(i)
    }

    ok := app_bridge.capture_hide_point_batch_command(state, &ids[0], i32(len(ids)))
    testing.expect(t, ok)
    testing.expect_value(t, batch.command_count, 2)

    app_bridge.end_scene_command_batch(state)
}

//   Verify gif_output_filename produces an Euclid-prefixed .gif name.
@(test)
gif_output_filename_has_expected_shape :: proc(t: ^testing.T) {
    name := app_view.gif_output_filename()

    testing.expect(t, strings.has_prefix(name, "Euclid_"))
    testing.expect(t, strings.has_suffix(name, ".gif"))
}
