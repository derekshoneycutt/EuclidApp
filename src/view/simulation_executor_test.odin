package view

import app_core "../core"
import "../dynview"
import dyncompile "../dynview/compile"
import dyncore "../dynview/core"
import evidence_checkpoint "../evidence/checkpoint"
import evidence_session "../evidence/session"
import evidence_trace "../evidence/trace"
import app_files "../files"

import "core:math"
import "core:os"
import "core:path/filepath"
import "core:testing"

//   Enable all typed evidence lanes on one lightweight test state.
init_test_evidence :: proc(state: ^app_core.Euclid_General_State) {
    testing_config := evidence_session.Config{
        enabled = true,
        output_mode = .Sink,
        lanes = {.Lifecycle, .Domain, .Transport, .Presentation, .Scenario, .Diagnostic},
    }
    _ = evidence_session.session_init(&state^.evidence_session, testing_config)
    evidence_trace.ring_init(&state^.evidence_ring, .Display)
}

//   Build the run settings for one headless trace-enabled session.
make_headless_trace_settings :: proc() -> app_core.Euclid_Run_Settings {
    return app_core.Euclid_Run_Settings{
        do_run = true,
        do_antialiasing = false,
        do_vsync = false,
        dust_particle_max = app_core.MAX_LOW_PARTICLES,
        limit_fps = true,
        use_simd_batch_projection = false,
        use_gpu_dust_instancing = false,
        evidence = {
            enabled = true,
            strict = true,
            output_mode = .Sink,
            lanes = evidence_session.ALL_LANES,
        },
    }
}

//   Assert the headless session started with a ready service and live state.
expect_headless_session_ready :: proc(
    t: ^testing.T, session: Euclid_Runtime_Session) {

    state := session.state
    service := session.julia_service
    testing.expect(t, state != nil)
    testing.expect(t, service != nil)
    testing.expect_value(t, service^.lifecycle, app_core.Julia_Lifecycle_State.Ready)
    testing.expect(t, state^.julia_interface != nil)
    testing.expect(t, state^.julia_interface^.current_animation != nil)
    testing.expect(t, state^.simulation_executor != nil)
    testing.expect(t, state^.simulation_executor^.pool.state == .Running)
    testing.expect_value(t,
        state^.simulation_executor^.pool.outstanding_count, 0)
    testing.expect_value(t, state^.fixed_step, u64(0))
    testing.expect_value(t, state^.simulation_time, f32(0))
}

//   Verify a headless runtime session starts, steps, and shuts down without a window.
@(test)
headless_runtime_session_starts_steps_and_shuts_down_without_window :: proc(
    t: ^testing.T) {
    profile_path := ".build/test-artifacts/headless.spall"
    worker_profile_path := ".build/test-artifacts/headless.spall.worker.spall"
    os.make_directory_all(".build/test-artifacts")
    os.remove(worker_profile_path)
    cwd, cwd_err := os.get_working_directory(context.temp_allocator)
    testing.expect(t, cwd_err == nil)
    testing.expect(t, len(cwd) > 0)
    bin_dir, bin_join_err := filepath.join([]string{cwd, "bin"}, context.allocator)
    testing.expect(t, bin_join_err == nil)
    defer delete(bin_dir)
    asset_root_config := app_files.make_asset_root_config(bin_dir, context.allocator)
    defer app_files.destroy_asset_root_config(&asset_root_config)
    testing.expect(t, app_files.reload_packaged_assets_root_with_config(
        &asset_root_config))

    settings := make_headless_trace_settings()
    settings.profile_path = profile_path
    session, ok := create_runtime_session(&settings, &asset_root_config)
    testing.expect(t, ok)
    if !ok {
        return
    }
    expect_headless_session_ready(t, session)

    state := session.state
    testing.expect(t, run_deterministic_fixed_step(state, 0.025))
    testing.expect(t, run_deterministic_fixed_step(state, 0.025))
    testing.expect_value(t, state^.fixed_step, u64(2))
    testing.expectf(t, math.abs(state^.simulation_time - 0.05) <= 0.0001,
        "expected simulation_time near 0.05, got %v", state^.simulation_time)
    testing.expect(t, state^.evidence_session.required_evidence_complete)
    testing.expect_value(t, shutdown_runtime_session(session), 0)

    profile_info, profile_error := os.stat(worker_profile_path, context.allocator)
    testing.expect(t, profile_error == nil)
    testing.expect(t, profile_info.size > 0)
    os.remove(worker_profile_path)
}

//   Verify a deterministic fixed step advances identity after the worker joins.
@(test)
deterministic_fixed_step_advances_identity_after_worker_join :: proc(t: ^testing.T) {
    state := new(app_core.Euclid_General_State)
    defer free(state)
    state^.julia_interface = &state^.julia_interface_slots[0]
    state^.particle_system = new(app_core.Particle_System)
    defer free(state^.particle_system)
    state^.point_system = new(app_core.Shapes_Point_System)
    defer free(state^.point_system)
    init_test_evidence(state)

    executor := create_simulation_executor(state)
    testing.expect(t, executor != nil)
    state^.simulation_executor = executor
    defer destroy_simulation_executor(executor)

    testing.expect(t, run_deterministic_fixed_step(state, 0.025))
    testing.expect_value(t, state^.fixed_step, u64(1))
    testing.expectf(t, math.abs(state^.simulation_time - 0.025) <= 0.0001,
        "expected simulation_time near 0.025, got %v", state^.simulation_time)
    testing.expect_value(t, state^.evidence_ring.count, 1)
    first_event := state^.evidence_ring.events[0]
    testing.expect_value(t, first_event.kind,
        evidence_trace.Kind.Constraint_Solve_Completed)
    testing.expect_value(t, first_event.tick, u64(1))

    testing.expect(t, run_deterministic_fixed_step(state, 0.025))
    testing.expect_value(t, state^.fixed_step, u64(2))
    testing.expectf(t, math.abs(state^.simulation_time - 0.05) <= 0.0001,
        "expected simulation_time near 0.05, got %v", state^.simulation_time)
    testing.expect_value(t, state^.evidence_ring.count, 2)
    second_event := state^.evidence_ring.events[1]
    testing.expect_value(t, second_event.kind,
        evidence_trace.Kind.Constraint_Solve_Completed)
    testing.expect_value(t, second_event.tick, u64(2))
}

//   Verify the canonical one-point checkpoint captured by the fixed-step fixture.
expect_single_point_checkpoint :: proc(
    t: ^testing.T, state: ^app_core.Euclid_General_State,
    event: evidence_trace.Event) {
    handle := evidence_checkpoint.Handle{
        slot = event.payload.handle.slot,
        generation = event.payload.handle.generation,
    }
    checkpoint, found := evidence_checkpoint.store_get(
        &state^.evidence_checkpoints, handle)
    testing.expect(t, found)
    testing.expect_value(t, checkpoint^.fixed_step, u64(1))
    testing.expectf(t, math.abs(checkpoint^.simulation_time - 0.025) <= 0.0001,
        "expected checkpoint simulation_time near 0.025, got %v",
        checkpoint^.simulation_time)
    testing.expect_value(t, checkpoint^.point_count, 1)
    testing.expect_value(t, checkpoint^.points[0].index, i32(0))
    testing.expect_value(t, checkpoint^.points[0].x, f32(1))
    testing.expect_value(t, checkpoint^.points[0].y, f32(2))
    testing.expect_value(t, checkpoint^.points[0].z, f32(3))
}

//   Verify a deterministic fixed step emits a post-join checkpoint snapshot.
@(test)
deterministic_fixed_step_emits_post_join_checkpoint_snapshot :: proc(t: ^testing.T) {
    state := new(app_core.Euclid_General_State)
    defer free(state)
    state^.julia_interface = &state^.julia_interface_slots[0]
    state^.julia_interface^.current_animation = &state^.julia_interface^.null_animation
    state^.julia_interface^.null_animation.name = "null"
    state^.julia_runtime_service = new(app_core.Julia_Runtime_Service)
    defer free(state^.julia_runtime_service)
    state^.particle_system = new(app_core.Particle_System)
    defer free(state^.particle_system)
    state^.point_system = new(app_core.Shapes_Point_System)
    defer free(state^.point_system)
    state^.point_system^.next_point_index = 1
    state^.point_system^.points[0].kind = .Point
    state^.point_system^.points[0].position = app_core.Vector3{1, 2, 3}
    init_test_evidence(state)

    executor := create_simulation_executor(state)
    testing.expect(t, executor != nil)
    state^.simulation_executor = executor
    defer destroy_simulation_executor(executor)

    testing.expect(t, run_deterministic_fixed_step(state, 0.025))
    testing.expect_value(t, state^.evidence_ring.count, 2)

    checkpoint_event := state^.evidence_ring.events[1]
    testing.expect_value(t, checkpoint_event.kind,
        evidence_trace.Kind.Checkpoint_Stored)
    expect_single_point_checkpoint(t, state, checkpoint_event)
}

//   Verify a parallel step joins the particle and constraint updates.
@(test)
parallel_simulation_step_joins_particle_and_constraint_updates :: proc(t: ^testing.T) {
    state := new(app_core.Euclid_General_State)
    defer free(state)
    state^.particle_system = new(app_core.Particle_System)
    defer free(state^.particle_system)
    state^.point_system = new(app_core.Shapes_Point_System)
    defer free(state^.point_system)

    particles := state^.particle_system
    particles^.use_max_dust_particles = 1
    particles^.low_particles.alive[0] = true
    particles^.low_particles.life[0] = 10
    particles^.low_particles.vel_x[0] = 0.25

    points := state^.point_system
    points^.points[0].position = app_core.Vector3{0, 0, -1}
    points^.constraints[0] = app_core.Shapes_Constraint{
        kind = .Floor,
        on_point = 0,
        restriction = app_core.Vector3{0, 0, 0},
        do_apply = true,
    }

    executor := create_simulation_executor(state)
    testing.expect(t, executor != nil)
    defer destroy_simulation_executor(executor)
    run_parallel_simulation_step(executor, 0.01)
    first_batch_x := particles^.low_particles.pos_x[0]
    run_parallel_simulation_step(executor, 0.01)

    testing.expect_value(t, first_batch_x, f32(0.25))
    testing.expect(t, particles^.low_particles.pos_x[0] > first_batch_x)
    position := points^.points[0].position.? or_else app_core.Vector3{}
    testing.expect_value(t, position.z, f32(0))
}

//   Verify terminal Dynview arena diagnostics after executor destruction.
expect_dynview_cache_arena_destroyed :: proc(
    t: ^testing.T, state: ^app_core.Euclid_General_State) {

    diagnostics := app_core.arena_owner_diagnostics(
        &state^.dynview.cache_arena)
    testing.expect(t, !diagnostics.initialized)
    testing.expect_value(t, diagnostics.destroy_count, u64(1))
    testing.expect_value(t, len(state^.dynview.compile_cache.shaped_runs), 0)
    testing.expect_value(t, len(state^.dynview.compile_cache.shaped_glyphs), 0)
}

//   Verify cache state after the first joined frame preparation.
expect_parallel_frame_cache_ready :: proc(
    t: ^testing.T,
    state: ^app_core.Euclid_General_State,
    executor: ^Simulation_Executor) {
    testing.expect_value(t, state^.point_system^.draw_cache.item_count, 1)
    testing.expect(t, state^.dynview.compile_cache.is_valid)
    testing.expect(t, state^.dynview.compile_cache.layout_is_valid)
    testing.expect_value(t, executor^.pool.outstanding_count, 0)
    testing.expect_value(t, state^.dynview.cache_access_state,
        app_core.Dynview_Cache_Access_State.Display_Readable)
    testing.expect(t, state^.dynview.cache_worker_thread_id != 0)
    testing.expect_value(t, state^.dynview.cache_arena.reset_count, u64(1))
}

//   Verify a failed rebuild clears derived views while preserving fallback text.
expect_failed_dynview_rebuild :: proc(
    t: ^testing.T,
    state: ^app_core.Euclid_General_State) {
    cache := &state^.dynview.compile_cache
    buffer := &state^.dynview.command_buffer
    testing.expect(t, !cache^.is_valid && !cache^.layout_is_valid)
    testing.expect_value(t, cache^.last_error_code,
        dyncore.DYNVIEW_STATUS_ILLEGAL_STATE)
    testing.expect(t, buffer^.has_stream_error)
    testing.expect_value(t, cache^.compiled_plain_text_len, 0)
    testing.expect_value(t, len(cache^.copy_blocks), 0)
    testing.expect_value(t, len(cache^.copy_hit_targets), 0)
    testing.expect_value(t, len(cache^.layout_lines), 0)
    testing.expect_value(t, len(cache^.layout_items), 0)
    testing.expect_value(t, cache^.copy_hit_target_count, 0)
    testing.expect_value(t, state^.dynview.cache_arena.reset_count, u64(2))
    testing.expect_value(t, state^.dynview.cache_access_state,
        app_core.Dynview_Cache_Access_State.Display_Readable)
    testing.expect_value(t,
        dyncompile.scratchpad_text_or_fallback(&state^.dynview, "fallback"),
        "fallback")
}

//   Verify frame preparation joins the shape and dynview cache updates.
@(test)
parallel_frame_preparation_joins_shape_and_dynview_cache_updates :: proc(t: ^testing.T) {
    state := new(app_core.Euclid_General_State)
    defer free(state)
    state^.point_system = new(app_core.Shapes_Point_System)
    defer free(state^.point_system)
    state^.point_system^.next_point_index = 1
    state^.point_system^.points[0].kind = .Point
    state^.point_system^.points[0].do_draw = true
    state^.point_system^.points[0].position = app_core.Vector3{1, 2, 3}
    state^.dynview.enabled = true

    executor := create_simulation_executor(state)
    testing.expect(t, executor != nil)
    state^.simulation_executor = executor
    testing.expect(t, state^.dynview.cache_arena.initialized)

    dyncompile.compile_if_needed(
        &state^.dynview, &state^.dynview.cache_arena)
    testing.expect_value(t, state^.dynview.cache_arena.reset_count, u64(0))
    testing.expect(t, !state^.dynview.compile_cache.is_valid)

    run_parallel_frame_preparation(state, 0.25)
    expect_parallel_frame_cache_ready(t, state, executor)

    run_parallel_frame_preparation(state, 0.75)
    testing.expect_value(t, state^.point_system^.draw_cache.item_count, 1)
    testing.expect_value(t, executor^.pool.outstanding_count, 0)
    testing.expect_value(t, state^.dynview.cache_arena.reset_count, u64(1))

    dynview.invalidate(&state^.dynview, dynview.DYNVIEW_INVALIDATE_FONT)
    run_parallel_frame_preparation(state, 0.75)
    testing.expect_value(t, executor^.pool.outstanding_count, 0)
    testing.expect_value(t, state^.dynview.cache_arena.reset_count, u64(2))

    destroy_simulation_executor(executor)
    expect_dynview_cache_arena_destroyed(t, state)
}

//   Verify failed worker rebuilds clear partial views and retain plain fallback.
@(test)
dynview_cache_arena_failed_rebuild_preserves_fallback :: proc(t: ^testing.T) {
    state := new(app_core.Euclid_General_State)
    defer free(state)
    state^.point_system = new(app_core.Shapes_Point_System)
    defer free(state^.point_system)
    state^.dynview.enabled = true

    executor := create_simulation_executor(state)
    testing.expect(t, executor != nil)
    state^.simulation_executor = executor
    defer destroy_simulation_executor(executor)
    run_parallel_frame_preparation(state, 0)

    buffer := &state^.dynview.command_buffer
    buffer^.revision += 1
    buffer^.command_count = 2
    buffer^.text_bytes_len = 1
    buffer^.text_bytes[0] = 'x'
    buffer^.commands[0] = {kind = .Begin_Block, block_id = 1}
    buffer^.commands[1] = {
        kind = .Text_Run, block_id = 1, text_offset = 0, text_len = 1,
    }
    run_parallel_frame_preparation(state, 0)

    expect_failed_dynview_rebuild(t, state)
}