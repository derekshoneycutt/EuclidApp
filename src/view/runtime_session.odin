package view

import view_core "core"
import "../core"
import "../dynview"
import evidence_allocation "../evidence/allocation"
import evidence_artifact "../evidence/artifact"
import evidence_export "../evidence/export"
import "../evidence/observe"
import evidence_session "../evidence/session"
import evidence_trace "../evidence/trace"
import "../files"
import "../shapes"
import julia "../bridge"

import "core:fmt"
import "core:log"
import "core:math/linalg"
import "core:time"

Euclid_Runtime_Session :: struct {
    state: ^Euclid_General_State,
    julia_service: ^julia.Julia_Runtime_Service,
}

//   Created Julia runtime service plus its completed initialize request id.
Session_Julia_Service :: struct {
    service:       ^julia.Julia_Runtime_Service,
    initialize_id: u64,
}

//   Allocated point system plus its default compass and pen tools.
Session_Point_System :: struct {
    point_system: ^Shapes_Point_System,
    compass:      core.Shapes_Compass,
    pen:          core.Shapes_Pen,
}

//   Wait for one Julia startup request without driving a window event loop.
wait_for_julia_request :: proc(
    service: ^julia.Julia_Runtime_Service,
    request_id: u64,
    expected_kind: julia.Julia_Event_Kind,
    timeout_seconds: f64) -> bool {

    started_at := time.tick_now()
    for {
        event, ok := julia.try_receive_julia_event(service)
        if ok && event.request_id == request_id && event.kind == expected_kind {
            return event.succeeded
        }
        if time.duration_seconds(time.tick_since(started_at)) >= timeout_seconds {
            fmt.eprintln("Julia request timed out; request id: ", request_id)
            log.errorf("julia_request_timeout request_id=%d expected_kind=%d",
                request_id, int(expected_kind))
            return false
        }
        free_all(context.temp_allocator)
    }
}

//   Create the Julia runtime service and wait for its Initialize phase.
//
// Returns:
//   - ok: true when the service was created and initialized.
session_start_julia_service :: proc(
    out: ^Session_Julia_Service, profile_path: string = "") -> bool {
    julia_service, service_err := julia.create_julia_runtime_service(profile_path)
    if service_err != .None || julia_service == nil {
        log.errorf("julia_startup_failed phase=service_create error=%d",
            int(service_err))
        return false
    }

    initialize_id, initialize_sent :=
        julia.try_submit_julia_request(julia_service, .Initialize)
    if !initialize_sent {
        log.error("julia_startup_failed phase=initialize_submit")
        julia.destroy_julia_runtime_service(julia_service)
        return false
    }
    if !wait_for_julia_request(
        julia_service, initialize_id, .Initialized, 10.0) {
        julia.destroy_julia_runtime_service(julia_service)
        return false
    }
    out.service = julia_service
    out.initialize_id = initialize_id
    return true
}

//   Derive the independent Julia-worker stream from the configured display path.
julia_worker_profile_path :: proc(profile_path: string) -> string {
    if len(profile_path) == 0 {
        return ""
    }
    return fmt.tprintf("%s.worker.spall", profile_path)
}

//   Record one required Julia runtime lifecycle transition.
record_runtime_lifecycle :: proc(
    state: ^Euclid_General_State, kind: evidence_trace.Kind,
    correlation: u64) {
    _ = evidence_session.session_record(
        &state^.evidence_session, &state^.evidence_ring, {
            lane = .Lifecycle,
            kind = kind,
            correlation_kind = .Runtime_Request,
            correlation = correlation,
            generation = state^.julia_runtime_service^.runtime_generation,
            flags = {.Required},
        })
}

//   Allocate runtime state and complete the Julia content Invoke phase.
//
// Returns:
//   - ok: true when state was created and content initialization completed.
session_load_content :: proc(
    julia_service: ^julia.Julia_Runtime_Service,
    settings: ^Euclid_Run_Settings,
    initialize_id: u64,
    out_state: ^^Euclid_General_State) -> bool {

    state := initiate_animations_state(julia_service, settings)
    if state == nil {
        log.error("julia_startup_failed phase=state_create")
        julia.destroy_julia_runtime_service(julia_service)
        return false
    }

    record_runtime_lifecycle(state, .Runtime_Starting, initialize_id)
    content_id, content_sent := julia.try_submit_julia_request(
        julia_service, .Invoke, julia.initialize_julia_state_task, rawptr(state))
    if !content_sent {
        log.error("julia_startup_failed phase=content_submit")
        shutdown_runtime_session(Euclid_Runtime_Session{
            state = state,
            julia_service = julia_service,
        })
        return false
    }
    if !wait_for_julia_request(
        julia_service, content_id, .Invoke_Complete, 10.0) {
        shutdown_runtime_session(Euclid_Runtime_Session{
            state = state,
            julia_service = julia_service,
        })
        return false
    }

    julia.mark_julia_runtime_ready(julia_service)
    record_runtime_lifecycle(state, .Runtime_Ready, content_id)
    evidence_session.session_accept_ring(
        &state^.evidence_session, &state^.evidence_ring)
    out_state^ = state
    return true
}

//   Prepare runtime-owned subsystems and state without initializing presentation resources.
create_runtime_session :: proc(
    settings: ^Euclid_Run_Settings,
    asset_config: ^files.Asset_Root_Config = nil) -> (Euclid_Runtime_Session, bool) {
    if settings == nil {
        return {}, false
    }

    if !files.packaged_asset_archive_exists_root(asset_config) ||
        !files.ensure_packaged_assets_unpacked_root(asset_config) {
        return {}, false
    }
    started: Session_Julia_Service
    if !session_start_julia_service(
        &started, julia_worker_profile_path(settings^.profile_path)) {
        return {}, false
    }
    julia_service := started.service

    state: ^Euclid_General_State
    if !session_load_content(julia_service, settings, started.initialize_id, &state) {
        return {}, false
    }

    return Euclid_Runtime_Session{state = state, julia_service = julia_service}, true
}

//   Allocate and initialize the isometric projection scale.
make_iso_scale :: proc() -> ^Iso_Scale {
    iso_scale := new(Iso_Scale)
    iso_scale^.scale = view_core.ISO_SCALE_VALUE
    iso_scale^.x_offset = view_core.ISO_X_OFFSET
    iso_scale^.y_offset = view_core.ISO_Y_OFFSET
    view_core.recompute_iso_scale_precompute(iso_scale)
    iso_scale^.main_light_dir = linalg.normalize(Vector3{0.35, -0.45, -1.0})
    iso_scale^.use_directional_shadow = true
    return iso_scale
}

//   Allocate and initialize the drawing surface quad.
make_drawing_surface :: proc() -> ^Euclid_Drawing_Surface {
    drawing_surface := new(Euclid_Drawing_Surface)
    edge := f32(view_core.SURFACE_EDGE_SIZE)
    drawing_surface^.zeros = Vector3{0 - edge, 0 - edge, 0}
    drawing_surface^.right_up = Vector3{1 + edge, 0 - edge, 0}
    drawing_surface^.left_down = Vector3{0 - edge, 1 + edge, 0}
    drawing_surface^.right_down = Vector3{1 + edge, 1 + edge, 0}
    drawing_surface^.color = view_core.SURFACE_COLOR
    drawing_surface^.edge_color = view_core.SURFACE_EDGE_COLOR
    drawing_surface^.edge_size = view_core.SURFACE_EDGE_SIZE
    return drawing_surface
}

//   Allocate the point system, build the default tools, and settle constraints.
make_point_system :: proc(out: ^Session_Point_System) {
    point_system := new(Shapes_Point_System)
    compass := shapes.init_compass(point_system, TOOL_LENGTH, view_core.TOOL_COLOR, 5)
    pen := shapes.init_pen(point_system, TOOL_LENGTH, view_core.TOOL_COLOR, 5)
    shapes.freeze_system_indices(point_system)
    shapes.apply_all_constraints_to_error(
        point_system, view_core.ALLOWED_CONSTRAINT_ERROR)
    shapes.update_last_cache_vectors(point_system)
    out.point_system = point_system
    out.compass = compass
    out.pen = pen
}

//   Populate the simulation/UI scalar fields on the general state.
init_runtime_fields :: proc(
    state: ^Euclid_General_State, settings: ^Euclid_Run_Settings) {
    state^.julia_interface_active_slot = 0
    state^.julia_interface = &state^.julia_interface_slots[0]
    state^.user_drawing_sound_enabled = false
    state^.animation_drawing_sound_enabled = true
    state^.fixed_step = 0
    state^.simulation_time = 0
    state^.current_delta_time = view_core.FIXED_DT
    state^.accumulator = 0
    state^.ui_runtime.limit_fps = settings^.limit_fps
    state^.ui_runtime.simulation_paused = false
    state^.ui_runtime.use_simd_batch_projection =
        settings^.use_simd_batch_projection && view_core.simd_batch_projection_available()
    state^.ui_runtime.use_gpu_dust_instancing = false
    dynview.set_enabled(&state.dynview, dynview.DYNVIEW_ENABLED_DEFAULT)
    state^.ui_runtime.gif_downsample_factor = 2
    state^.ui_runtime.gif_frame_step = 2
    state^.ui_runtime.gif_capture_phase = .Idle
    view_core.clear_gif_status_note(&state^.ui_runtime)
    view_core.screenshake_clear(state^.iso_scale)
}

//   Initialize typed evidence policy, freeing the state and returning false on failure.
init_evidence_session :: proc(
    state: ^Euclid_General_State, settings: ^Euclid_Run_Settings) -> bool {
    if !evidence_session.session_init(
        &state^.evidence_session, settings^.evidence) {
        fmt.eprintln("Invalid semantic evidence configuration.")
        destroy_simulation_executor(state^.simulation_executor)
        state^.simulation_executor = nil
        free_animations_state(state)
        return false
    }
    state^.julia_runtime_service^.evidence_session = &state^.evidence_session
    _ = evidence_session.session_record(
        &state^.evidence_session, &state^.evidence_ring, {
            lane = .Lifecycle,
            kind = .Session_Started,
            flags = {.Required},
        })
    _ = evidence_session.session_record(
        &state^.evidence_session, &state^.evidence_ring, {
            lane = .Lifecycle,
            kind = .Session_Configured,
            flags = {.Required},
        })
    return true
}

//   Initialize allocation domains and bind the state-owned runtime resources.
init_animations_state_resources :: proc(
    state: ^Euclid_General_State,
    julia_service: ^julia.Julia_Runtime_Service,
    settings: ^Euclid_Run_Settings,
    particle_system: ^Particle_System,
    points: Session_Point_System) -> bool {
    if !evidence_allocation.domain_init(
        &state^.evidence_allocations, context.allocator, context.allocator) {
        return false
    }
    state^.saved_context = context
    state^.julia_runtime_service = julia_service
    state^.iso_scale = make_iso_scale()
    state^.draw_surface = make_drawing_surface()
    state^.point_system = points.point_system
    state^.particle_system = particle_system
    state^.compass = points.compass
    state^.pen = points.pen
    init_runtime_fields(state, settings)
    return true
}

//   Allocate runtime state shared by the windowed frontend and the headless harness.
initiate_animations_state :: proc(
    julia_service: ^julia.Julia_Runtime_Service,
    settings: ^Euclid_Run_Settings) -> ^Euclid_General_State {

    particle_system := new(Particle_System)
    particle_system^.use_max_dust_particles = settings^.dust_particle_max

    point_system_parts: Session_Point_System
    make_point_system(&point_system_parts)

    state := new(Euclid_General_State)
    if !init_animations_state_resources(
        state, julia_service, settings, particle_system, point_system_parts) {
        free(state)
        free(particle_system)
        free(point_system_parts.point_system)
        return nil
    }
    if !core.animation_storage_init(
        &state^.animation_memory,
        &state^.animation_values,
        &state^.dynview_documents) {
        fmt.eprintln("Failed to initialize animation storage.")
        free_animations_state(state)
        return nil
    }
    evidence_trace.ring_init(&state^.evidence_ring, .Display)
    state^.simulation_executor = create_simulation_executor(state)
    if state^.simulation_executor == nil {
        fmt.eprintln("Failed to initialize the simulation task pool.")
        free_animations_state(state)
        return nil
    }

    if !init_evidence_session(state, settings) {
        return nil
    }

    return state
}

//   Write the terminal scenario artifact when one was requested.
write_scenario_artifact :: proc(
    session: Euclid_Runtime_Session, runtime: ^Scenario_Runtime,
    output: string) -> bool {
    if runtime == nil || len(output) == 0 {
        return true
    }
    result := evidence_artifact.Result.Inconclusive
    if runtime.runner.status == .Passed {
        result = .Passed
    } else if runtime.runner.status == .Failed {
        result = .Failed
    }
    events := session.state.evidence_session.events[
        :session.state.evidence_session.event_count]
    last_trace_sequence: u64
    if len(events) > 0 {
        last_trace_sequence = events[len(events) - 1].sequence
    }
    return evidence_artifact.write_bundle(output, {
        manifest = {
            result = result,
            reason = runtime.terminal_reason,
            failed_step = runtime.runner.step,
            trace_complete = session.state.evidence_session.required_evidence_complete,
            last_trace_sequence = last_trace_sequence,
        },
        events = events,
        state = observe.display(session.state),
        julia_host = observe.julia_host(session.julia_service),
        allocations = observe.allocation(&session.state.evidence_allocations),
        arena_baselines = session.state.evidence_arena_baselines,
    })
}

//   Export the completed evidence session through its selected encoding owner.
write_session_evidence :: proc(session: ^evidence_session.Session) -> bool {
    if session == nil || session.output_mode != .Binary_File {
        return evidence_export.write_session_jsonl(session)
    }
    path := string(session.output_path[:session.output_path_count])
    events := session.events[:session.event_count]
    return evidence_artifact.write_trace(path, events)
}

//   Shut down one runtime session in reverse ownership order.
shutdown_runtime_session :: proc(
    session: Euclid_Runtime_Session,
    scenario_runtime: ^Scenario_Runtime = nil,
    artifact_output: string = "") -> int {
    if session.state == nil || session.julia_service == nil {
        return 0
    }

    destroy_simulation_executor(session.state^.simulation_executor)
    session.state^.simulation_executor = nil
    shutdown_julia_runtime(session.state, session.julia_service)
    _ = evidence_session.session_record(
        &session.state^.evidence_session, &session.state^.evidence_ring, {
            lane = .Lifecycle,
            kind = .Session_Finished,
            flags = {.Required},
        })
    evidence_session.session_accept_ring(
        &session.state^.evidence_session, &session.state^.evidence_ring)
    artifact_succeeded := write_scenario_artifact(
        session, scenario_runtime, artifact_output)
    export_succeeded := write_session_evidence(
        &session.state^.evidence_session) && artifact_succeeded
    evidence_session.session_finish(
        &session.state^.evidence_session, export_succeeded)
    evidence_exit_failed := evidence_session.session_should_fail_process(
        &session.state^.evidence_session)
    julia.release_published_view_snapshot(session.state, session.julia_service)
    julia.destroy_julia_runtime_service(session.julia_service)
    session.state^.julia_runtime_service = nil
    free_animations_state(session.state)
    if evidence_exit_failed || !artifact_succeeded {
        return 1
    }
    return 0
}
