package view

import "../core"
import capture "../evidence/capture"
import "../diagnostics"
import artifact "../evidence/artifact"
import scenario "../evidence/scenario"
import evidence_trace "../evidence/trace"

import "core:log"
import "core:os"
import "core:strings"
import "core:testing"

// Accept one injected post-presentation capture.
scenario_runtime_test_capture :: proc(
    user_data: rawptr, checkpoint: capture.Checkpoint) -> bool {
    captured := cast(^capture.Checkpoint)user_data
    captured^ = checkpoint
    return true
}

// Verify the expected passed and failed scenario records in one completed log.
scenario_runtime_expect_outcome_logs :: proc(t: ^testing.T, path: string) {
    context.logger = log.nil_logger()
    content_bytes, read_error := os.read_entire_file(path, context.allocator)
    testing.expect(t, read_error == nil)
    defer delete(content_bytes)
    defer os.remove(path)
    content := string(content_bytes)
    testing.expect(t, strings.contains(content,
        "scenario_passed step=3 assertions=0 failures=0 reason=0"))
    testing.expect(t, strings.contains(content,
        "scenario_failed step=5 assertions=3 failures=1"))
}

// Verify ordinary state requests and orderly shutdown flow through the action sink.
@(test)
scenario_runtime_actions_use_display_owned_state :: proc(t: ^testing.T) {
    path := ".build/test-artifacts/scenario-outcomes.log"
    os.make_directory_all(".build/test-artifacts")
    os.remove(path)
    logging_state: diagnostics.Logging_State
    testing.expect(t, diagnostics.logging_start(&logging_state, path, .Info))
    context.logger = logging_state.logger
    state := new(Euclid_General_State)
    defer free(state)
    state^.julia_interface = &state^.julia_interface_slots[0]
    state^.evidence_session.enabled = true
    state^.evidence_session.required_evidence_complete = true

    program := scenario.Program{count = 3}
    program.commands[0] = {kind = .Pause_Simulation}
    program.commands[1] = {kind = .Resume_Simulation}
    program.commands[2] = {kind = .Shutdown}
    runtime: Scenario_Runtime
    scenario_runtime_init(&runtime, state, program)

    testing.expect_value(t,
        scenario_runtime_update(&runtime, 1), scenario.Run_Status.Passed)
    testing.expect(t, !state^.ui_runtime.simulation_paused)
    testing.expect(t, runtime.shutdown_requested)

    failed := Scenario_Runtime{
        state = state,
        terminal_reason = artifact.Reason.Assertion_Failed,
    }
    failed.runner.step = 5
    failed.runner.assertion_count = 3
    failed.runner.failure_count = 1
    scenario_runtime_record_terminal(&failed, .Failed)

    context.logger = log.nil_logger()
    diagnostics.logging_stop(&logging_state)
    scenario_runtime_expect_outcome_logs(t, path)
}

// Verify a required screenshot keeps the run active until post-presentation completion.
@(test)
scenario_runtime_waits_for_post_present_capture :: proc(t: ^testing.T) {
    state := new(Euclid_General_State)
    defer free(state)
    state^.julia_interface = &state^.julia_interface_slots[0]
    state^.evidence_session.enabled = true
    state^.evidence_session.required_evidence_complete = true
    state^.fixed_step = 11

    path, copied := scenario.text_copy(".build/test-artifacts/frame.png")
    testing.expect(t, copied)
    program := scenario.Program{count = 1}
    program.commands[0] = {kind = .Request_Screenshot, text = path}
    runtime: Scenario_Runtime
    scenario_runtime_init(&runtime, state, program)

    testing.expect_value(t,
        scenario_runtime_update(&runtime, 1), scenario.Run_Status.Running)
    captured: capture.Checkpoint
    testing.expect_value(t, scenario_runtime_after_present(&runtime, {
        user_data = &captured,
        capture = scenario_runtime_test_capture,
    }), capture.Checkpoint_Status.Completed)
    testing.expect_value(t, captured.fixed_step, u64(11))
    testing.expect_value(t,
        scenario_runtime_update(&runtime, 2), scenario.Run_Status.Passed)
}

// Verify accepted scenario Scratchpad work owns bottom scrolling until its reply.
@(test)
scenario_scratchpad_submission_marks_forced_bottom_scroll :: proc(t: ^testing.T) {
    ui_runtime := core.Euclid_Ui_Runtime_State{
        text_scroll_dragging = true,
        text_scroll_drag_off = 7,
        ui_press_owner = {
            active = true,
            kind = .Scrollbar,
            id = 1002,
        },
    }

    scenario_mark_scratchpad_submitted(&ui_runtime, 42)

    testing.expect(t, ui_runtime.scratchpad_bottom_pinned)
    testing.expect_value(t, ui_runtime.scratchpad_forced_bottom_request_id, u64(42))
    testing.expect(t, !ui_runtime.text_scroll_dragging)
    testing.expect_value(t, ui_runtime.text_scroll_drag_off, f32(0))
    testing.expect(t, !ui_runtime.ui_press_owner.active)
}

// Verify scenario selection uses the programmatic tree synchronization path.
@(test)
scenario_animation_selection_requests_tree_reveal :: proc(t: ^testing.T) {
    state := new(core.Euclid_General_State)
    defer free(state)
    service := new(core.Julia_Runtime_Service)
    defer free(service)
    state^.julia_runtime_service = service
    ji := &state^.julia_interface_slots[0]
    state^.julia_interface = ji
    nodes: [2]core.Euclid_Julia_Animation_Interface
    nodes[0].name = "Group"
    nodes[1].name = "Target"
    nodes[0].next_in_registry = &nodes[1]
    nodes[0].first_child = &nodes[1]
    nodes[1].parent = &nodes[0]
    nodes[1].stable_id[0] = 7
    ji.animation_head = &nodes[0]
    ji.animation_count = len(nodes)
    command_text, copied := scenario.text_copy("Target")
    testing.expect(t, copied)
    command := scenario.Command{kind = .Select_Animation, text = command_text}
    runtime := Scenario_Runtime{state = state}
    identity: evidence_trace.Identity

    handled, accepted := scenario_issue_julia_action(&runtime, &command, &identity)

    testing.expect(t, handled && accepted)
    testing.expect_value(t, ji.selected_animation, &nodes[1])
    testing.expect(t, nodes[0].is_expanded && nodes[1].is_selected)
    testing.expect(t, state^.ui_runtime.tree_reveal_pending)
    testing.expect_value(t, identity.kind, evidence_trace.Correlation_Kind.Animation)
}

// Verify deferred reload actions identify the runtime generation they will publish.
@(test)
scenario_reload_action_targets_next_runtime_generation :: proc(t: ^testing.T) {
    state := new(core.Euclid_General_State)
    defer free(state)
    service := new(core.Julia_Runtime_Service)
    defer free(service)
    state^.julia_runtime_service = service
    service^.runtime_generation = 7
    command := scenario.Command{kind = .Reload_Runtime}
    runtime := Scenario_Runtime{state = state}
    identity: evidence_trace.Identity

    handled, accepted := scenario_issue_julia_action(&runtime, &command, &identity)

    testing.expect(t, handled && accepted && service^.reload_requested)
    testing.expect_value(t, identity.kind,
        evidence_trace.Correlation_Kind.Runtime_Request)
    testing.expect_value(t, identity.id, u64(8))
    testing.expect_value(t, identity.generation, u64(8))
}

// Verify rejected scenario Scratchpad work does not mutate display scroll state.
@(test)
scenario_rejected_scratchpad_submission_preserves_scroll_state :: proc(t: ^testing.T) {
    state := new(core.Euclid_General_State)
    defer free(state)
    state^.ui_runtime.text_scroll_dragging = true
    command_text, copied := scenario.text_copy("1 + 1")
    testing.expect(t, copied)
    command := scenario.Command{kind = .Submit_Scratchpad, text = command_text}
    identity: evidence_trace.Identity

    testing.expect(t, !scenario_submit_scratchpad(state, &command, &identity))
    testing.expect(t, state^.ui_runtime.text_scroll_dragging)
    testing.expect(t, !state^.ui_runtime.scratchpad_bottom_pinned)
    testing.expect_value(t,
        state^.ui_runtime.scratchpad_forced_bottom_request_id, u64(0))
}
