package view

import julia "../bridge"
import "../core"
import evidence_allocation "../evidence/allocation"
import artifact "../evidence/artifact"
import capture "../evidence/capture"
import "../evidence/observe"
import scenario "../evidence/scenario"
import evidence_session "../evidence/session"
import evidence_trace "../evidence/trace"

import "core:log"
import "core:os"

import rl "vendor:raylib"

// Display-owned coordinator connecting the generic runner to Euclid actions.
Scenario_Runtime :: struct {
    runner: scenario.Runner,
    capture: capture.Coordinator,
    state: ^Euclid_General_State,
    next_action_id: u64,
    presented_frame: u64,
    shutdown_requested: bool,
    terminal_recorded: bool,
    terminal_reason: artifact.Reason,
}

// Resolved owner-domain identity and its synchronized arena diagnostics.
Scenario_Arena_Sample :: struct {
    kind: evidence_allocation.Arena_Domain_Kind,
    snapshot: evidence_allocation.Arena_Snapshot,
}

//   Load and validate one bounded JSONL scenario before runtime execution.
scenario_runtime_load_file :: proc(
    runtime: ^Scenario_Runtime, state: ^Euclid_General_State,
    path: string) -> bool {
    if runtime == nil || state == nil || len(path) == 0 {
        return false
    }
    source, read_error := os.read_entire_file(path, context.temp_allocator)
    if read_error != nil {
        log.error("scenario_load_failed reason=read")
        return false
    }
    program: scenario.Program
    parse_error := scenario.parse(string(source), &program)
    if parse_error != .None {
        log.errorf("scenario_load_failed reason=parse error=%d", int(parse_error))
        return false
    }
    scenario_runtime_init(runtime, state, program)
    return true
}

//   Initialize one display-owned runtime from a validated fixed program.
scenario_runtime_init :: proc(
    runtime: ^Scenario_Runtime, state: ^Euclid_General_State,
    program: scenario.Program) {
    runtime^ = {state = state, next_action_id = 1}
    scenario.runner_init(&runtime.runner, program)
    log.infof("scenario_started command_count=%d", program.count)
    _ = evidence_session.session_record(
        &state^.evidence_session, &state^.evidence_ring, {
            lane = .Scenario,
            kind = .Scenario_Started,
            flags = {.Required},
        })
}

//   Emit one operational record for a terminal scenario outcome.
scenario_runtime_log_terminal :: proc(
    runtime: ^Scenario_Runtime, status: scenario.Run_Status) {
    switch status {
    case .Passed:
        log.infof(
            "scenario_passed step=%d assertions=%d failures=%d reason=%d",
            runtime.runner.step, runtime.runner.assertion_count,
            runtime.runner.failure_count, int(runtime.terminal_reason))
    case .Failed:
        log.errorf(
            "scenario_failed step=%d assertions=%d failures=%d reason=%d",
            runtime.runner.step, runtime.runner.assertion_count,
            runtime.runner.failure_count, int(runtime.terminal_reason))
    case .Inconclusive:
        log.warnf(
            "scenario_inconclusive step=%d assertions=%d failures=%d reason=%d",
            runtime.runner.step, runtime.runner.assertion_count,
            runtime.runner.failure_count, int(runtime.terminal_reason))
    case .Ready, .Running:
    }
}

//   Record one terminal scenario outcome and its stable failure reason.
scenario_runtime_record_terminal :: proc(
    runtime: ^Scenario_Runtime, status: scenario.Run_Status) {
    if runtime.terminal_recorded ||
        (status != .Passed && status != .Failed && status != .Inconclusive) {
        return
    }
    kind := evidence_trace.Kind.Scenario_Passed
    flags: evidence_trace.Flags = {.Required}
    if status == .Failed {
        kind = .Scenario_Failed
        flags += {.Failure}
        if runtime.terminal_reason == .None &&
            runtime.runner.step < runtime.runner.program.count {
            command_kind := runtime.runner.program.commands[runtime.runner.step].kind
            runtime.terminal_reason = command_kind == .Wait_Event ||
                command_kind == .Wait_State ? .Wait_Timeout : .Assertion_Failed
        }
    } else if status == .Inconclusive {
        kind = .Scenario_Inconclusive
        flags += {.Failure}
        runtime.terminal_reason = .Required_Evidence_Lost
    }
    _ = evidence_session.session_record(
        &runtime.state^.evidence_session, &runtime.state^.evidence_ring, {
            lane = .Scenario,
            kind = kind,
            correlation_kind = .Scenario_Action,
            correlation = u64(runtime.runner.step),
            flags = flags,
        })
    scenario_runtime_log_terminal(runtime, status)
    runtime.terminal_recorded = true
}

//   Advance the scenario against the cumulative synchronized evidence snapshot.
scenario_runtime_update :: proc(
    runtime: ^Scenario_Runtime, now_ns: u64) -> scenario.Run_Status {
    if runtime == nil || runtime.state == nil {
        return .Failed
    }
    state := runtime.state
    status := scenario.runner_update(&runtime.runner, {
        now_ns = now_ns,
        events = state.evidence_session.events[:state.evidence_session.event_count],
        display = observe.display(state),
        actions = {
            user_data = rawptr(runtime),
            issue = scenario_runtime_issue,
        },
    })
    if runtime.capture.checkpoint.status == .Pending && status == .Passed {
        runtime.runner.status = .Running
        return .Running
    }
    if runtime.capture.checkpoint.status == .Failed {
        runtime.runner.status = .Failed
        runtime.terminal_reason = .Capture_Failed
        status = .Failed
    }
    scenario_runtime_record_terminal(runtime, status)
    return status
}

//   Fulfill pending capture work after the display has presented a complete frame.
scenario_runtime_after_present :: proc(
    runtime: ^Scenario_Runtime, sink: capture.Sink) -> capture.Checkpoint_Status {
    if runtime == nil || runtime.state == nil {
        return .Idle
    }
    runtime.presented_frame += 1
    status := capture.checkpoint_after_present(
        &runtime.capture, runtime.presented_frame, runtime.state.fixed_step, sink)
    if status == .Completed || status == .Failed {
        checkpoint := runtime.capture.checkpoint
        flags: evidence_trace.Flags = {.Required}
        if status == .Failed {
            flags += {.Failure}
        }
        _ = evidence_session.session_record(
            &runtime.state^.evidence_session, &runtime.state^.evidence_ring, {
                lane = .Presentation,
                kind = status == .Completed ? .Capture_Completed : .Capture_Failed,
                correlation_kind = checkpoint.trigger.kind,
                correlation = checkpoint.trigger.id,
                generation = checkpoint.trigger.generation,
                tick = checkpoint.fixed_step,
                revision = checkpoint.presented_frame,
                flags = flags,
            })
    }
    if status == .Failed {
        runtime.runner.failure_count += 1
        runtime.runner.status = .Failed
    }
    return status
}

//   Record display-owned scrolling intent for one accepted scenario submission.
scenario_mark_scratchpad_submitted :: proc(
    ui_runtime: ^core.Euclid_Ui_Runtime_State,
    request_id: u64) {

    ui_runtime^.scratchpad_bottom_pinned = true
    ui_runtime^.scratchpad_forced_bottom_request_id = request_id
    ui_runtime^.text_scroll_dragging = false
    ui_runtime^.text_scroll_drag_off = 0
    if ui_runtime^.ui_press_owner.active &&
        ui_runtime^.ui_press_owner.kind == .Scrollbar &&
        ui_runtime^.ui_press_owner.id == 1002 {

        ui_runtime^.ui_press_owner = {}
    }
}

//   Route one Scratchpad command through its ordinary owner API.
scenario_submit_scratchpad :: proc(
    state: ^Euclid_General_State, command: ^scenario.Command,
    identity: ^evidence_trace.Identity) -> bool {
    text := scenario.text_string(&command.text)
    request_id, submitted := julia.try_submit_scratchpad_async(
        state, .Submit, julia.get_scratchpad_submission(text, len(text)))
    if !submitted {
        return false
    }
    scenario_mark_scratchpad_submitted(&state^.ui_runtime, request_id)
    identity.kind = .Runtime_Request
    identity.id = request_id
    identity.generation = state.julia_runtime_service.runtime_generation
    return true
}

//   Arm one validated scenario-only failure for the next runtime reload.
scenario_arm_reload_failure :: proc(
    state: ^Euclid_General_State, command: ^scenario.Command) -> bool {
    if state.julia_runtime_service == nil {
        return false
    }
    injection := scenario.text_string(&command.text)
    switch injection {
    case "candidate_load":
        state.julia_runtime_service.reload_failure_injection = .Candidate_Load
    case "animation_enter":
        state.julia_runtime_service.reload_failure_injection = .Animation_Enter
    case:
        return false
    }
    return true
}

//   Select one named animation and retain its next generation identity.
scenario_select_animation :: proc(
    state: ^Euclid_General_State, command: ^scenario.Command,
    identity: ^evidence_trace.Identity) -> bool {
    selected := scenario_find_animation(
        state.julia_interface, scenario.text_string(&command.text))
    if selected == nil || !julia.select_animation_programmatically(state, selected) {
        return false
    }
    identity.kind = .Animation
    identity.id = state.julia_runtime_service.animation_generation + 1
    identity.generation = identity.id
    return true
}

//   Route one animation or Julia-service command through its ordinary owner API.
scenario_issue_julia_action :: proc(
    runtime: ^Scenario_Runtime, command: ^scenario.Command,
    identity: ^evidence_trace.Identity) -> (bool, bool) {
    state := runtime.state
    #partial switch command.kind {
    case .Reset_Animation:
        state.julia_interface.pending_animation_reset = true
        return true, true
    case .Select_Animation:
        return true, scenario_select_animation(state, command, identity)
    case .Submit_Scratchpad:
        return true, scenario_submit_scratchpad(state, command, identity)
    case .Reload_Runtime:
        if state.julia_runtime_service == nil {
            return true, false
        }
        service := state.julia_runtime_service
        service.reload_requested = true
        identity.kind = .Runtime_Request
        identity.id = service.runtime_generation + 1
        identity.generation = identity.id
        return true, true
    case .Inject_Reload_Failure:
        return true, scenario_arm_reload_failure(state, command)
    case:
        return false, false
    }
}

//   Store a display checkpoint and publish its retained evidence identity.
scenario_issue_checkpoint_action :: proc(
    state: ^Euclid_General_State,
    identity: ^evidence_trace.Identity) -> bool {
    handle := record_evidence_checkpoint(state, true)
    if handle.generation == 0 {
        return false
    }
    identity.kind = .Checkpoint
    identity.id = state.fixed_step
    identity.generation = u64(handle.generation)
    return true
}

//   Route one display or capture command through display-owned state.
scenario_issue_display_action :: proc(
    runtime: ^Scenario_Runtime, command: ^scenario.Command,
    identity: ^evidence_trace.Identity) -> (bool, bool) {
    state := runtime.state
    #partial switch command.kind {
    case .Pause_Simulation:
        state.ui_runtime.simulation_paused = true
        return true, true
    case .Resume_Simulation:
        state.ui_runtime.simulation_paused = false
        return true, true
    case .Request_Screenshot:
        if !capture.checkpoint_request(
            &runtime.capture, u32(runtime.runner.step), identity^,
            scenario.text_string(&command.text)) {
            return true, false
        }
        identity.kind = .Capture
        return true, true
    case .Start_Gif, .Stop_Gif:
        state.ui_runtime.save_gif_requested = true
        identity.kind = .Capture
        return true, true
    case .Checkpoint:
        return true, scenario_issue_checkpoint_action(state, identity)
    case .Shutdown:
        runtime.shutdown_requested = true
        return true, true
    case:
        return false, false
    }
}

//   Evaluate one allocation-domain scenario command.
scenario_arena_snapshot :: proc(
    state: ^Euclid_General_State,
    kind: evidence_allocation.Arena_Domain_Kind) -> evidence_allocation.Arena_Snapshot {

    snapshot: evidence_allocation.Arena_Snapshot
    #partial switch kind {
    case .Animation:
        scenario_add_arena_diagnostics(&snapshot,
            core.animation_memory_diagnostics(&state^.animation_memory))
    case .Snapshot_Slots:
        for &slot in state^.julia_runtime_service^.view_snapshots {
            scenario_add_arena_diagnostics(
                &snapshot, core.arena_owner_diagnostics(&slot.arena))
        }
    case .Display_Cache:
        scenario_add_arena_diagnostics(&snapshot,
            core.arena_owner_diagnostics(&state^.dynview.cache_arena))
    }
    return snapshot
}

//   Aggregate one owner diagnostic into a fixed scenario arena sample.
scenario_add_arena_diagnostics :: proc(
    snapshot: ^evidence_allocation.Arena_Snapshot,
    diagnostics: core.Arena_Owner_Diagnostics) {

    if diagnostics.initialized {
        snapshot^.initialized_count += 1
    }
    snapshot^.current_used += diagnostics.current_used
    snapshot^.current_reserved += diagnostics.current_reserved
    snapshot^.current_committed += diagnostics.current_committed
    snapshot^.peak_used += diagnostics.peak_used
    snapshot^.peak_reserved += diagnostics.peak_reserved
    snapshot^.peak_committed += diagnostics.peak_committed
    snapshot^.reset_count += diagnostics.reset_count
}

//   Resolve and sample one named arena domain at the display synchronization point.
scenario_arena_domain_sample :: proc(
    state: ^Euclid_General_State,
    name: string) -> (Scenario_Arena_Sample, bool) {

    kind, valid := evidence_allocation.arena_domain_kind(name)
    if !valid || state == nil || state^.julia_runtime_service == nil {
        return {}, false
    }
    return {kind = kind, snapshot = scenario_arena_snapshot(state, kind)}, true
}

//   Evaluate one allocation-domain scenario command.
scenario_issue_allocation_action :: proc(
    runtime: ^Scenario_Runtime, command: ^scenario.Command) -> (bool, bool) {
    state := runtime.state
    sample, valid := scenario_arena_domain_sample(
        state, scenario.text_string(&command.text))
    if command.kind != .Assert_No_Bad_Frees && !valid {
        return true, false
    }
    #partial switch command.kind {
    case .Allocation_Checkpoint:
        accepted := evidence_allocation.arena_checkpoint(
            &state.evidence_arena_baselines, sample.kind, sample.snapshot)
        if accepted {
            scenario_record_allocation_evidence(
                runtime, .Allocation_Checkpoint, sample.kind)
        }
        return true, accepted
    case .Assert_Allocation_Baseline:
        accepted := evidence_allocation.arena_matches_baseline(
            &state.evidence_arena_baselines, sample.kind, sample.snapshot)
        scenario_record_allocation_evidence(runtime,
            accepted ? .Allocation_Baseline_Matched :
                .Allocation_Baseline_Mismatched, sample.kind)
        return true, accepted
    case .Assert_No_Bad_Frees:
        return true, evidence_allocation.domain_has_no_bad_frees(
            &state.evidence_allocations)
    case:
        return false, false
    }
}

//   Record the outcome of one named arena checkpoint operation.
scenario_record_allocation_evidence :: proc(
    runtime: ^Scenario_Runtime, event_kind: evidence_trace.Kind,
    domain_kind: evidence_allocation.Arena_Domain_Kind) {

    flags: evidence_trace.Flags = {.Required}
    if event_kind == .Allocation_Baseline_Mismatched {
        flags += {.Failure}
    }
    _ = evidence_session.session_record(
        &runtime.state^.evidence_session, &runtime.state^.evidence_ring, {
            lane = .Domain,
            kind = event_kind,
            correlation_kind = .Scenario_Action,
            correlation = runtime.next_action_id - 1,
            generation = 1,
            flags = flags,
            payload = {counts = {first = u32(domain_kind)}},
        })
}

//   Route one generic scenario command through ordinary Euclid request state and APIs.
scenario_runtime_issue :: proc(
    user_data: rawptr, command: ^scenario.Command) -> scenario.Action_Result {
    runtime := cast(^Scenario_Runtime)user_data
    if runtime == nil || runtime.state == nil || command == nil {
        return {}
    }
    identity := evidence_trace.Identity{
        kind = .Scenario_Action,
        id = runtime.next_action_id,
        generation = 1,
    }
    runtime.next_action_id += 1
    handled, accepted := scenario_issue_julia_action(runtime, command, &identity)
    if !handled {
        handled, accepted = scenario_issue_display_action(runtime, command, &identity)
    }
    if !handled {
        handled, accepted = scenario_issue_allocation_action(runtime, command)
    }
    if !handled || !accepted {
        return {}
    }
    _ = evidence_session.session_record(
        &runtime.state^.evidence_session, &runtime.state^.evidence_ring, {
            lane = .Scenario,
            kind = .Scenario_Action_Issued,
            correlation_kind = identity.kind,
            correlation = identity.id,
            generation = identity.generation,
            flags = {.Required},
            payload = {counts = {first = u32(command.kind)}},
        })
    return {accepted = true, correlation = identity}
}

//   Materialize one requested screenshot after a complete frame presentation.
scenario_runtime_capture_screenshot :: proc(
    user_data: rawptr, checkpoint: capture.Checkpoint) -> bool {
    runtime := cast(^Scenario_Runtime)user_data
    if runtime == nil || checkpoint.status != .Pending {
        return false
    }
    path := capture.checkpoint_path(&runtime.capture)
    if path == nil {
        return false
    }
    rl.TakeScreenshot(path)
    return os.exists(string(runtime.capture.path[:runtime.capture.path_count]))
}

//   Report whether the scenario reached any terminal outcome.
scenario_runtime_finished :: proc(runtime: ^Scenario_Runtime) -> bool {
    if runtime == nil {
        return false
    }
    status := runtime.runner.status
    return status == .Passed || status == .Failed || status == .Inconclusive
}

//   Report whether the scenario completed with authoritative success.
scenario_runtime_succeeded :: proc(runtime: ^Scenario_Runtime) -> bool {
    return runtime != nil && runtime.runner.status == .Passed
}

//   Find one registered animation by exact display name without allocation.
scenario_find_animation :: proc(
    interface: ^core.Euclid_Julia_Interface,
    name: string) -> ^core.Euclid_Julia_Animation_Interface {
    if interface == nil || len(name) == 0 {
        return nil
    }
    for animation := interface.animation_head;
        animation != nil;
        animation = animation.next_in_registry {
        if animation.name == name {
            return animation
        }
    }
    return nil
}
