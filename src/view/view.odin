package view

// Here is where we initialize the application state and load up the window, running
// the loop for the lifetime of this instance.

import view_core "core"
import "font"
import "ui"
import "../core"
import "../audio"
import "../dynview"
import "../shapes"
import julia "../bridge"
import evidence_allocation "../evidence/allocation"
import capture "../evidence/capture"
import evidence_checkpoint "../evidence/checkpoint"
import evidence_profile "../evidence/profile"
import evidence_session "../evidence/session"
import evidence_trace "../evidence/trace"
import "../files"

import "base:runtime"
import "core:fmt"
import "core:log"
import "core:strings"
import "core:thread"
import "core:time"

import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"

MAX_SHAPESPOINTS :: core.MAX_SHAPESPOINTS
TOOL_LENGTH :: core.TOOL_LENGTH

Vector2 :: core.Vector2
Vector3 :: core.Vector3
Iso_Scale :: core.Iso_Scale
Shapes_Point_Type :: core.Shapes_Point_Type
Shapes_Point :: core.Shapes_Point
Shapes_Constraint :: core.Shapes_Constraint
Shapes_Point_System :: core.Shapes_Point_System
Particle :: core.Particle
Particle_System :: core.Particle_System
Euclid_Drawing_Surface :: core.Euclid_Drawing_Surface
Euclid_General_State :: core.Euclid_General_State
Euclid_Run_Settings :: core.Euclid_Run_Settings

ISO_SCALE_VALUE :: view_core.ISO_SCALE_VALUE
ISO_X_OFFSET :: view_core.ISO_X_OFFSET
ISO_Y_OFFSET :: view_core.ISO_Y_OFFSET

LIMIT_FPS :: view_core.LIMIT_FPS
FIXED_DT :: view_core.FIXED_DT
MAX_FRAME_DT :: view_core.MAX_FRAME_DT
MAX_STEPS_PER_FRAME :: view_core.MAX_STEPS_PER_FRAME
FPS_AVERAGE_BUCKET_COUNT :: view_core.FPS_AVERAGE_BUCKET_COUNT

ALLOWED_CONSTRAINT_ERROR :: view_core.ALLOWED_CONSTRAINT_ERROR

WINDOW_HEIGHT :: view_core.WINDOW_HEIGHT
WINDOW_WIDTH :: view_core.WINDOW_WIDTH

VIEW_HEIGHT :: view_core.VIEW_HEIGHT
BOTTOM_BAR_HEIGHT :: view_core.BOTTOM_BAR_HEIGHT
VIEW_WIDTH :: view_core.VIEW_WIDTH
RIGHT_BAR_WIDTH :: view_core.RIGHT_BAR_WIDTH

WINDOW_TITLE :: view_core.WINDOW_TITLE

BACKGROUND_COLOR :: view_core.BACKGROUND_COLOR
TOOL_COLOR :: view_core.TOOL_COLOR

UI_BACK_COLOR :: view_core.UI_BACK_COLOR
UI_BORDER_COLOR :: view_core.UI_BORDER_COLOR
UI_TEXT_COLOR :: view_core.UI_TEXT_COLOR

UI_COMPONENT_BACKGROUND_COLOR :: view_core.UI_COMPONENT_BACKGROUND_COLOR

SURFACE_COLOR :: view_core.SURFACE_COLOR
SURFACE_EDGE_SIZE :: view_core.SURFACE_EDGE_SIZE
SURFACE_EDGE_COLOR :: view_core.SURFACE_EDGE_COLOR
JULIA_SHUTDOWN_TIMEOUT_SECONDS :: 5.0


//   Run full app lifecycle loop: init state/window, fixed updates, frame draw, cleanup.
//
// Notes:
//   - Owns state/window setup and teardown via deferred cleanup calls.
//   - Resets temp allocator each frame after drawing.
//
// Parameters:
//   - settings: The settings describing how to operate the window
//
// Returns:
//   - exit_code: non-zero when strict trace validation failed.
//   Submit one GIF frame while recording, aborting and noting the error on failure.
run_gif_capture_frame :: proc(state: ^Euclid_General_State) {
    if state^.ui_runtime.simulation_paused ||
        state^.ui_runtime.gif_capture_phase != .Recording {
        return
    }
    if view_core.gif_capture_submit_frame(state) {
        return
    }
    view_core.gif_capture_abort_session(&state^.gif_capture)
    state^.ui_runtime.gif_capture_phase = .Error
    view_core.set_gif_status_note(&state^.ui_runtime,
        "Error: failed to submit GIF frame.")
}

//   Publish frame evidence, close profiling zones, and release temporary storage.
finish_window_frame :: proc(
    state: ^Euclid_General_State, display_profile: ^evidence_profile.State) {
    _ = evidence_session.session_record(
        &state^.evidence_session, &state^.evidence_ring, {
            lane = .Presentation,
            kind = .Frame_Presented,
            correlation_kind = .Fixed_Step,
            correlation = state^.fixed_step,
            tick = state^.fixed_step,
        })
    evidence_session.session_accept_ring(
        &state^.evidence_session, &state^.evidence_ring)
    evidence_profile.zone_end(display_profile)
    evidence_profile.frame(display_profile)
    free_all(context.temp_allocator)
}

//   Synchronize Dynview shaping when the resident math-font generation changes.
sync_window_math_shaping :: proc(state: ^Euclid_General_State) {
    entry := &state^.font_cache.entries[int(font.Font_Key.Math_Regular)]
    generation_changed :=
        state^.dynview.math_shaping.generation != entry.generation &&
        state^.dynview.math_shaping.failed_generation != entry.generation
    if !generation_changed {
        return
    }
    if font.math_shaping_sync(&state^.font_cache, &state^.dynview.math_shaping) {
        log.infof("dynview_math_shaper_ready generation=%d",
            state^.dynview.math_shaping.generation)
    } else {
        log.errorf("dynview_math_shaper_failed generation=%d", entry.generation)
    }
    dynview.invalidate(&state^.dynview, dynview.DYNVIEW_INVALIDATE_FONT)
}

//   Run one window frame: async results, simulation update, draw, and GIF capture.
run_window_frame :: proc(
    state: ^Euclid_General_State,
    scenario_runtime: ^Scenario_Runtime = nil,
    capture_sink: capture.Sink = {},
    display_profile: ^evidence_profile.State = nil) {
    evidence_profile.zone_begin(display_profile, "display_frame")
    font.cache_service(
        &state^.font_cache, &state^.simulation_executor^.pool)
    sync_window_math_shaping(state)
    ui.apply_scratchpad_async_results(state, &state^.ui_runtime)
    julia.publish_available_view_snapshot(state)
    alpha := accumulate_and_update_systems(state)
    run_parallel_frame_preparation(state, alpha)
    audio.update_chalk_runtime(&state^.chalk_audio)
    if scenario_runtime != nil {
        _ = scenario_runtime_update(
            scenario_runtime, u64(i64(time.tick_since({}))))
    }

    evidence_profile.zone_begin(display_profile, "frame_present")
    rl.BeginDrawing()
        draw_frame(state, alpha)
    rl.EndDrawing()
    evidence_profile.zone_end(display_profile)

    if scenario_runtime != nil {
        _ = scenario_runtime_after_present(scenario_runtime, capture_sink)
    }
    run_gif_capture_frame(state)
    finish_window_frame(state, display_profile)
}

//   Build the screenshot sink routed through one active scenario runtime.
scenario_capture_sink :: proc(runtime: ^Scenario_Runtime) -> capture.Sink {
    return {
        user_data = rawptr(runtime),
        capture = scenario_runtime_capture_screenshot,
    }
}

//   Initialize optional display profiling and begin the startup zone.
init_display_profile :: proc(
    profile: ^evidence_profile.State, path: string) {
    if len(path) > 0 && !evidence_profile.init_spall(profile, path) {
        fmt.eprintln("Failed to initialize display profile output.")
        log.warn("display_profile_init_failed")
    }
    evidence_profile.thread_name(profile, "display")
    evidence_profile.zone_begin(profile, "total startup")
}

//   Process display frames until the window or active scenario requests completion.
run_window_frames :: proc(
    state: ^Euclid_General_State, scenario_runtime: ^Scenario_Runtime,
    capture_sink: capture.Sink, display_profile: ^evidence_profile.State) {
    for !rl.WindowShouldClose() {
        run_window_frame(state, scenario_runtime, capture_sink, display_profile)
        if scenario_runtime_finished(scenario_runtime) {
            return
        }
    }
}

//   Shut down a completed window session and convert scenario failure to process status.
finish_window_session :: proc(
    session: Euclid_Runtime_Session, scenario_runtime: ^Scenario_Runtime,
    artifact_output: string) -> int {
    exit_code := shutdown_window_runtime(
        session, scenario_runtime, artifact_output)
    if scenario_runtime != nil && !scenario_runtime_succeeded(scenario_runtime) {
        return 1
    }
    return exit_code
}

//   - Owns state/window setup and teardown via deferred cleanup calls.
//   - Resets temp allocator each frame after drawing.
//
// Parameters:
//   - settings: The settings describing how to operate the window
//
// Returns:
//   - exit_code: non-zero when strict trace validation failed.
run_window_loop :: proc(settings: ^Euclid_Run_Settings) -> int {
    display_profile: evidence_profile.State
    init_display_profile(&display_profile, settings^.profile_path)
    defer evidence_profile.destroy(&display_profile)

    open_window(settings)
    defer rl.CloseWindow()

    session, ok := initialize_window_runtime_with_loading(
        settings, &display_profile)
    evidence_profile.zone_end(&display_profile)
    if !ok {
        log.error("display_runtime_start_failed")
        return 1
    }
    state := session.state
    log.info("display_runtime_ready")

    scenario_runtime: Scenario_Runtime
    active_scenario: ^Scenario_Runtime
    capture_sink: capture.Sink
    if len(settings^.scenario_input) > 0 {
        if !scenario_runtime_load_file(
            &scenario_runtime, state, settings^.scenario_input) {
            fmt.eprintln("Failed to load semantic scenario: ", settings^.scenario_input)
            log.error("scenario_load_failed")
            _ = shutdown_window_runtime(session)
            return 1
        }
        active_scenario = &scenario_runtime
        capture_sink = scenario_capture_sink(active_scenario)
    }

    free_all(context.temp_allocator)

    run_window_frames(
        state, active_scenario, capture_sink, &display_profile)
    log.infof("display_loop_stopped fixed_step=%d scenario_active=%v",
        state^.fixed_step, active_scenario != nil)

    return finish_window_session(
        session, active_scenario, settings^.scenario_artifact_output)
}

//   Release graphics-owned resources before destroying their backing runtime state.
shutdown_window_runtime :: proc(
    session: Euclid_Runtime_Session,
    scenario_runtime: ^Scenario_Runtime = nil,
    artifact_output: string = "") -> int {
    shutdown_window_resources(session.state)
    return shutdown_runtime_session(session, scenario_runtime, artifact_output)
}

//   Allocate and initialize persistent runtime state for simulation and rendering.
//
// Notes:
//   - Runtime state construction lives in runtime_session.odin and is shared with headless execution.
submit_julia_shutdown :: proc(
    service: ^julia.Julia_Runtime_Service, started_at: time.Tick) -> u64 {
    shutdown_id: u64
    sent := false
    for !sent {
        shutdown_id, sent = julia.try_submit_julia_request(service, .Shutdown)
        _, _ = julia.try_receive_julia_event(service)
        if time.duration_seconds(time.tick_since(started_at)) >=
            JULIA_SHUTDOWN_TIMEOUT_SECONDS {
            fmt.eprintln(
                "Julia shutdown request queue remained saturated; terminating process.")
            runtime.exit(1)
        }
        thread.yield()
    }
    return shutdown_id
}

//   Wait for the matching shutdown completion within the shared timeout window.
wait_for_julia_shutdown :: proc(
    service: ^julia.Julia_Runtime_Service, shutdown_id: u64,
    started_at: time.Tick) {
    for {
        event, ok := julia.try_receive_julia_event(service)
        if ok && event.request_id == shutdown_id && event.kind == .Shutdown_Complete {
            return
        }
        if time.duration_seconds(time.tick_since(started_at)) >=
            JULIA_SHUTDOWN_TIMEOUT_SECONDS {
            fmt.eprintln("Julia shutdown timed out; terminating process.")
            runtime.exit(1)
        }
        thread.yield()
    }
}

//   Allocate and initialize persistent runtime state for simulation and rendering.
//
// Notes:
//   - Runtime state construction lives in runtime_session.odin and is shared with headless execution.
shutdown_julia_runtime :: proc(
    state: ^Euclid_General_State, service: ^julia.Julia_Runtime_Service) {
    started_at := time.tick_now()
    shutdown_id := submit_julia_shutdown(service, started_at)
    _ = evidence_session.session_record(
        &state^.evidence_session, &state^.evidence_ring, {
            lane = .Lifecycle,
            kind = .Runtime_Shutdown_Started,
            correlation_kind = .Runtime_Request,
            correlation = shutdown_id,
            generation = service^.runtime_generation,
            flags = {.Required},
        })
    wait_for_julia_shutdown(service, shutdown_id, started_at)
    evidence_session.session_accept_ring(
        &state^.evidence_session, &state^.evidence_ring)
}

//   Release runtime state allocations and finalize Julia/GIF runtime resources.
//
// Notes:
//   - Must be paired with initiate_animations_state to release owned allocations.
free_animations_state :: proc(state : ^Euclid_General_State) {
    if state == nil {
        return
    }
    view_core.gif_capture_destroy_session(&state^.gif_capture)
    evidence_allocation.domain_destroy(&state^.evidence_allocations)
    core.animation_storage_destroy(
        &state^.animation_memory,
        &state^.animation_values,
        &state^.dynview_documents)
    julia.destroy_julia_interface_resources(state)
    free(state^.particle_system)
    free(state^.point_system)
    free(state^.draw_surface)
    free(state^.iso_scale)
    free(state)
}

//   Open the startup window without requiring packaged assets or application state.
//
// Notes:
//   - Should be paired with rl.CloseWindow on shutdown.
open_window :: proc(settings: ^Euclid_Run_Settings) {
    if settings.do_antialiasing && settings.do_vsync {
        rl.SetConfigFlags({.MSAA_4X_HINT, .VSYNC_HINT, .WINDOW_HIGHDPI})
    } else if settings.do_antialiasing {
        rl.SetConfigFlags({.MSAA_4X_HINT, .WINDOW_HIGHDPI})
    } else if settings.do_vsync {
        rl.SetConfigFlags({.VSYNC_HINT, .WINDOW_HIGHDPI})
    } else {
        rl.SetConfigFlags({.WINDOW_HIGHDPI})
    }

    rl.InitWindow(WINDOW_WIDTH, WINDOW_HEIGHT, WINDOW_TITLE)
    rl.SetTargetFPS(LIMIT_FPS)
}

//   Load the packaged application icon when the asset is available.
initialize_window_icon :: proc() {
    icon_file := strings.clone_to_cstring(
        files.packaged_asset_path("compass_icon.png", context.temp_allocator),
        context.temp_allocator)
    if rl.FileExists(icon_file) {
        icon_image := rl.LoadImage(icon_file)
        rl.SetWindowIcon(icon_image)
        rl.UnloadImage(icon_image)
    }
}

//   Initialize audio, icon, shader, and font resources after application state exists.
initialize_window_resources :: proc(
    state: ^Euclid_General_State, settings: ^Euclid_Run_Settings) {

    rl.InitAudioDevice()
    if !rl.IsAudioDeviceReady() {
        fmt.eprintln("warning: failed to initialize audio device; chalk sound disabled")
    } else {
        chalk_path := files.packaged_asset_path(
            "Chalk On Blackboard.wav", context.temp_allocator)
        audio.init_chalk_runtime(&state^.chalk_audio, chalk_path)
    }

    state^.ui_runtime.use_gpu_dust_instancing =
        settings^.use_gpu_dust_instancing && rlgl.GetVersion() >= .OPENGL_33

    if state^.ui_runtime.limit_fps {
        rl.SetTargetFPS(LIMIT_FPS)
    } else {
        rl.SetTargetFPS(0)
    }

    initialize_window_icon()

    init_tool_brush_shader(state)

    required_fonts_ready := font.cache_init(&state^.font_cache)
    if !required_fonts_ready {
        fmt.eprintln("error: failed to load required JuliaMono or NewCM font")
    }
    assert(required_fonts_ready)
    math_shaping_ready := font.math_shaping_sync(
        &state^.font_cache, &state^.dynview.math_shaping)
    if !math_shaping_ready {
        fmt.eprintln("error: failed to initialize Dynview NewCM shaping")
    }
    assert(math_shaping_ready)
    log.infof("dynview_math_shaper_ready generation=%d",
        state^.dynview.math_shaping.generation)
    _ = font.cache_request(&state^.font_cache, .Bold)
    _ = font.cache_request(&state^.font_cache, .Regular_Italic)
}

//   Shutdown state-dependent render and audio resources before closing the window.
//
// Notes:
//   - Intended as the shutdown pair for initialize_window_resources.
shutdown_window_resources :: proc(state : ^Euclid_General_State) {
    font.cache_shutdown_service(
        &state^.font_cache, &state^.simulation_executor^.pool)
    font.math_shaping_destroy(&state^.dynview.math_shaping)
    font.cache_destroy(&state^.font_cache)
    audio.shutdown_chalk_runtime(&state^.chalk_audio)
    if rl.IsAudioDeviceReady() {
        rl.CloseAudioDevice()
    }
    shutdown_particle_render_resources(state)
    shutdown_tool_brush_shader(state)
}

//   Update rolling FPS statistics used for average-FPS overlay display.
//   Advance the rolling FPS window by one full bucket when it completes.
fps_advance_bucket_if_full :: proc(ui_runtime: ^core.Euclid_Ui_Runtime_State) {
    if ui_runtime.fps_avg_bucket_elapsed < 1.0 {
        return
    }

    cursor := ui_runtime.fps_avg_bucket_cursor
    next_cursor := (cursor + 1) % FPS_AVERAGE_BUCKET_COUNT

    ui_runtime.fps_avg_rolling_seconds -=
        ui_runtime.fps_avg_bucket_seconds[next_cursor]
    ui_runtime.fps_avg_rolling_frames -=
        ui_runtime.fps_avg_bucket_frames[next_cursor]

    ui_runtime.fps_avg_bucket_seconds[next_cursor] = 0
    ui_runtime.fps_avg_bucket_frames[next_cursor] = 0

    ui_runtime.fps_avg_bucket_cursor = next_cursor
    ui_runtime.fps_avg_bucket_elapsed = 0
}

//   Accumulate one frame's elapsed time into the rolling FPS buckets.
fps_accumulate_seconds :: proc(
    ui_runtime: ^core.Euclid_Ui_Runtime_State, frame_dt: f32) {

    remaining := frame_dt
    for remaining > 0 {
        space := 1.0 - ui_runtime.fps_avg_bucket_elapsed
        step := min(remaining, space)

        cursor := ui_runtime.fps_avg_bucket_cursor
        ui_runtime.fps_avg_bucket_seconds[cursor] += step
        ui_runtime.fps_avg_rolling_seconds += step
        ui_runtime.fps_avg_bucket_elapsed += step
        remaining -= step

        fps_advance_bucket_if_full(ui_runtime)
    }
}

//   Update the rolling-average FPS from one frame's delta time.
update_average_fps :: proc(state: ^Euclid_General_State, frame_dt: f32) {
    if frame_dt <= 0 {
        return
    }

    ui_runtime := &state^.ui_runtime
    fps_accumulate_seconds(ui_runtime, frame_dt)

    cursor := ui_runtime.fps_avg_bucket_cursor
    ui_runtime.fps_avg_bucket_frames[cursor] += 1
    ui_runtime.fps_avg_rolling_frames += 1

    if ui_runtime.fps_avg_rolling_seconds > 0 {
        ui_runtime.fps_avg_live =
            f32(ui_runtime.fps_avg_rolling_frames) / ui_runtime.fps_avg_rolling_seconds
        return
    }
    ui_runtime.fps_avg_live = 0
}

//   Run fixed-step simulation updates and return interpolation alpha for rendering.
accumulate_and_update_systems :: proc(state : ^Euclid_General_State) -> f32 {
    view_core.recompute_iso_scale_precompute(state^.iso_scale)

    frame_dt := rl.GetFrameTime()
    if frame_dt > MAX_FRAME_DT {
        frame_dt = MAX_FRAME_DT
    }
    update_average_fps(state, frame_dt)
    view_core.screenshake_update(state^.iso_scale, frame_dt)

    if state^.ui_runtime.simulation_paused {
        state^.accumulator = 0
        return 0
    }

    state^.accumulator += frame_dt

    shapes.update_last_cache_vectors(state^.point_system)
    step_count := 0
    for state^.accumulator >= FIXED_DT {
        // Never expose worker-commanded tool dimensions before constraints normalize them.
        run_windowed_fixed_step(state, FIXED_DT)

        state^.accumulator -= FIXED_DT
        step_count += 1
        if step_count >= MAX_STEPS_PER_FRAME {
            state^.accumulator = 0
            break
        }
    }

    alpha := state^.accumulator / FIXED_DT
    return alpha
}

//   Run one deterministic fixed step through animation publication and worker join.
//
// Parameters:
//   - state: Runtime state advanced by one fixed step.
//   - dt: Deterministic fixed-step duration.
//
// Returns:
//   - ok: true when the step completed and post-join identity advanced.
run_deterministic_fixed_step :: proc(state: ^Euclid_General_State, dt: f32) -> bool {
    if state == nil || state^.simulation_executor == nil || dt <= 0 {
        return false
    }

    state^.current_delta_time = dt
    julia.publish_available_animation_tick(state)
    julia.schedule_animation_tick(state, dt)
    run_parallel_simulation_step(state^.simulation_executor, dt)
    state^.fixed_step += 1
    state^.simulation_time += dt
    record_constraint_trace_summary(state)
    _ = record_evidence_checkpoint(state, false)
    return true
}

//   Run one fixed step and apply windowed presentation side effects after the worker join.
//
// Parameters:
//   - state: Runtime state advanced by one fixed step.
//   - dt: Fixed-step duration from the windowed runtime.
//
// Returns:
//   - ok: true when the deterministic step completed.
run_windowed_fixed_step :: proc(state: ^Euclid_General_State, dt: f32) -> bool {
    if !run_deterministic_fixed_step(state, dt) {
        return false
    }

    previous_phase := state^.ui_runtime.gif_capture_phase
    view_core.gif_capture_update_fixed_step(state)
    record_gif_capture_transition(
        state, previous_phase, state^.ui_runtime.gif_capture_phase)
    return true
}

//   Record a required semantic event when GIF capture changes lifecycle phase.
record_gif_capture_transition :: proc(
    state: ^Euclid_General_State,
    previous, current: core.Gif_Capture_Phase) {
    if state == nil || previous == current {
        return
    }
    kind := evidence_trace.Kind.Unknown
    flags: evidence_trace.Flags = {.Required}
    if previous == .Armed && current == .Recording {
        kind = .Gif_Started
    } else if previous == .Recording && current == .Saved {
        kind = .Gif_Completed
    } else if previous == .Recording && current == .Error {
        kind = .Gif_Failed
        flags += {.Failure}
    } else {
        return
    }
    _ = evidence_session.session_record(
        &state^.evidence_session, &state^.evidence_ring, {
            lane = .Presentation,
            kind = kind,
            correlation_kind = .Capture,
            correlation = state^.fixed_step,
            tick = state^.fixed_step,
            flags = flags,
        })
}

//   Record one post-join constraint summary for semantic trace consumers.
record_constraint_trace_summary :: proc(state: ^Euclid_General_State) {
    if state == nil || state^.point_system == nil {
        return
    }
    active_constraints := 0
    for constraint_index in 0..<state^.point_system^.next_constraint_index {
        if state^.point_system^.constraints[constraint_index].do_apply {
            active_constraints += 1
        }
    }
    _ = evidence_session.session_record(
        &state^.evidence_session, &state^.evidence_ring, {
            lane = .Domain,
            kind = .Constraint_Solve_Completed,
            correlation_kind = .Fixed_Step,
            correlation = state^.fixed_step,
            tick = state^.fixed_step,
            payload = {counts = {
                first = u32(active_constraints),
                second = u32(state^.point_system^.next_constraint_index),
            }},
        })
}

//   Capture and record one bounded canonical checkpoint after worker join.
//
// Parameters:
//   - state: Display-owned state observed after synchronized simulation work.
//   - required: Whether later checkpoint eviction makes evidence incomplete.
record_evidence_checkpoint :: proc(
    state: ^Euclid_General_State,
    required: bool) -> evidence_checkpoint.Handle {
    if state == nil || state^.point_system == nil || state^.julia_runtime_service == nil {
        return {}
    }

    typed := capture_evidence_checkpoint(state)
    handle := evidence_checkpoint.store_put(
        &state^.evidence_checkpoints, typed, required)
    if state^.evidence_checkpoints.required_evidence_lost {
        evidence_session.session_mark_incomplete(&state^.evidence_session)
    }
    flags: evidence_trace.Flags
    if required {
        flags += {.Required}
    }
    _ = evidence_session.session_record(
        &state^.evidence_session, &state^.evidence_ring, {
            lane = .Domain,
            kind = .Checkpoint_Stored,
            correlation_kind = .Checkpoint,
            correlation = state^.fixed_step,
            generation = u64(handle.generation),
            tick = state^.fixed_step,
            flags = flags,
            payload = {handle = {
                slot = handle.slot,
                generation = handle.generation,
            }},
        })
    return handle
}

//   Copy authoritative post-join Euclid state into one fixed checkpoint value.
capture_evidence_checkpoint :: proc(
    state: ^Euclid_General_State) -> evidence_checkpoint.Snapshot {
    snapshot := evidence_checkpoint.Snapshot{
        fixed_step = state^.fixed_step,
        simulation_time = state^.simulation_time,
        runtime_generation = state^.julia_runtime_service^.runtime_generation,
        animation_generation = state^.julia_runtime_service^.animation_generation,
        animation_tick_sequence = state^.julia_runtime_service^.animation_tick_sequence,
        point_count = min(
            state^.point_system^.next_point_index,
            evidence_checkpoint.CHECKPOINT_POINT_CAPACITY),
        constraint_count = state^.point_system^.next_constraint_index,
    }
    for constraint in state^.point_system^.constraints[
        :state^.point_system^.next_constraint_index] {
        if constraint.do_apply {
            snapshot.active_constraint_count += 1
        }
    }
    for point_index in 0..<snapshot.point_count {
        point := &state^.point_system^.points[point_index]
        captured := &snapshot.points[point_index]
        captured.index = i32(point_index)
        captured.active_child = i32(point.active_child)
        captured.visible = point.do_draw
        captured.brush_size = point.brush_size
        captured.offset = point.offset
        if position, ok := point.position.?; ok {
            captured.x = position.x
            captured.y = position.y
            captured.z = position.z
            captured.has_position = true
        }
    }
    return snapshot
}

//   Render one full frame including world, particles, UI panels, and capture step.
draw_frame :: proc(state : ^Euclid_General_State, alpha: f32) {
    rl.ClearBackground(BACKGROUND_COLOR)

    base_x_offset := state^.iso_scale^.x_offset
    base_y_offset := state^.iso_scale^.y_offset

    apply_world_shake := state^.particle_system != nil &&
        state^.ui_runtime.gif_capture_phase != .Recording
    if apply_world_shake {
        state^.iso_scale^.x_offset += state^.iso_scale^.screenshake_offset_x
        state^.iso_scale^.y_offset += state^.iso_scale^.screenshake_offset_y
    }

    draw_drawing_surface(state)

    draw_shapes_points_low_cached(state)
    render_low_particles(state^.particle_system, state)
    draw_shapes_shapes_shadows_cached(state)
    draw_shapes_points_shadows_cached(state)
    render_particles(state^.particle_system, state)
    draw_shapes_points_high_merged_cached(state)
    render_high_particles(state^.particle_system, state)

    state^.iso_scale^.x_offset = base_x_offset
    state^.iso_scale^.y_offset = base_y_offset

    ui.draw_ui_panels(state)

    if state^.ui_runtime.display_fps {
        fps_flags := core.Font_Variant_Flags.Medium
        mono_font := font.cache_resolve(
            &state^.font_cache, font.font_key_from_flags(fps_flags))

        fps_text := fmt.tprintf("FPS: %d", rl.GetFPS())
        fps_text_c := strings.clone_to_cstring(fps_text, context.temp_allocator)
        rl.DrawTextEx(mono_font, fps_text_c, rl.Vector2{10, 10}, 18, 0, UI_TEXT_COLOR)

        avg_text := fmt.tprintf("Avg FPS (60s): %.1f", state^.ui_runtime.fps_avg_live)
        avg_text_c := strings.clone_to_cstring(avg_text, context.temp_allocator)
        rl.DrawTextEx(mono_font, avg_text_c, rl.Vector2{10, 30}, 18, 0, UI_TEXT_COLOR)
    }
}
