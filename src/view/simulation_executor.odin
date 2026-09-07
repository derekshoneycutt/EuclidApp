package view

import "../core"
import dyncompile "../dynview/compile"
import dynmath "../dynview/math"
import evidence_session "../evidence/session"
import evidence_trace "../evidence/trace"
import "../particles"
import "../shapes"
import "../taskpool"
import "./font"
import "./ui"

import "core:os"

Simulation_Task_Data :: core.Simulation_Task_Data
Frame_Preparation_Task_Data :: core.Frame_Preparation_Task_Data
Simulation_Executor :: core.Simulation_Executor

//   Create and start the persistent fixed-step worker pool.
create_simulation_executor :: proc(
    state: ^Euclid_General_State) -> ^Simulation_Executor {

    if state == nil || !core.arena_owner_init(&state^.dynview.cache_arena) {
        return nil
    }
    state^.dynview.cache_access_state = .Display_Readable
    executor := new(Simulation_Executor)
    executor^.particle_task.state = state
    executor^.constraint_task.state = state
    executor^.shape_cache_task.state = state
    executor^.dynview_task.state = state
    executor^.dynview_task.math_shaping_workspace = &executor^.math_shaping_workspace
    executor^.prose_shaping_workspace = new(core.Document_Prose_Shaping_Workspace)
    if executor^.prose_shaping_workspace == nil {
        free(executor)
        core.arena_owner_destroy(&state^.dynview.cache_arena)
        return nil
    }
    executor^.dynview_task.prose_shaping_workspace = executor^.prose_shaping_workspace
    evidence_trace.ring_init(
        &executor^.particle_task.evidence_ring, .Particle_Worker)
    evidence_trace.ring_init(
        &executor^.constraint_task.evidence_ring, .Constraint_Worker)
    evidence_trace.ring_init(
        &executor^.shape_cache_task.evidence_ring, .Shape_Cache_Worker)
    evidence_trace.ring_init(
        &executor^.dynview_task.evidence_ring, .Dynview_Worker)
    if !taskpool.task_pool_init(&executor^.pool) {
        free(executor^.prose_shaping_workspace)
        free(executor)
        core.arena_owner_destroy(&state^.dynview.cache_arena)
        return nil
    }
    return executor
}

//   Finish queued simulation work and release persistent worker resources.
destroy_simulation_executor :: proc(executor: ^Simulation_Executor) {
    if executor == nil {
        return
    }
    taskpool.task_pool_destroy(&executor^.pool)
    if executor^.dynview_task.state != nil {
        runtime := &executor^.dynview_task.state^.dynview
        runtime^.cache_access_state = .Uninitialized
        dynmath.clear_shaped_records(&runtime^.compile_cache)
        core.arena_owner_destroy(
            &runtime^.cache_arena)
    }
    free(executor^.prose_shaping_workspace)
    free(executor)
}

//   Run one particle-system fixed step on a simulation worker.
update_particles_task :: proc(
    payload: rawptr, _: taskpool.Task_Cancellation_Token) -> taskpool.Task_Result {
    data := cast(^Simulation_Task_Data)payload
    particles.update_particles(data^.state^.particle_system, data^.dt)
    _ = evidence_session.session_record(
        &data^.state^.evidence_session, &data^.evidence_ring, {
            lane = .Domain,
            kind = .Particle_Emission_Committed,
            correlation_kind = .Fixed_Step,
            correlation = data^.state^.fixed_step + 1,
            tick = data^.state^.fixed_step + 1,
            payload = {counts = {
                first = u32(max(data^.state^.particle_system^.next_index, 0)),
            }},
        })
    return .Succeeded
}

//   Solve point-system constraints on a simulation worker.
solve_constraints_task :: proc(
    payload: rawptr, _: taskpool.Task_Cancellation_Token) -> taskpool.Task_Result {
    data := cast(^Simulation_Task_Data)payload
    shapes.apply_all_constraints_to_error(
        data^.state^.point_system, ALLOWED_CONSTRAINT_ERROR)
    _ = evidence_session.session_record(
        &data^.state^.evidence_session, &data^.evidence_ring, {
            lane = .Domain,
            kind = .Constraint_Solve_Completed,
            correlation_kind = .Fixed_Step,
            correlation = data^.state^.fixed_step + 1,
            tick = data^.state^.fixed_step + 1,
            flags = {.Required},
            payload = {counts = {
                first = u32(max(
                    data^.state^.point_system^.next_constraint_index, 0)),
            }},
        })
    return .Succeeded
}

//   Build interpolated shape draw data on a frame-preparation worker.
build_shape_cache_task :: proc(
    payload: rawptr, _: taskpool.Task_Cancellation_Token) -> taskpool.Task_Result {
    data := cast(^Frame_Preparation_Task_Data)payload
    shapes.build_draw_cache(data^.state^.point_system, data^.interpolation_alpha)
    _ = evidence_session.session_record(
        &data^.state^.evidence_session, &data^.evidence_ring, {
            lane = .Presentation,
            kind = .Shape_Cache_Prepared,
            correlation_kind = .Fixed_Step,
            correlation = data^.state^.fixed_step,
            tick = data^.state^.fixed_step,
            payload = {counts = {
                first = u32(max(
                    data^.state^.point_system^.draw_cache.item_count, 0)),
            }},
        })
    return .Succeeded
}

//   Compile invalidated Dynview text and layout caches on a frame-preparation worker.
compile_dynview_task :: proc(
    payload: rawptr, _: taskpool.Task_Cancellation_Token) -> taskpool.Task_Result {
    data := cast(^Frame_Preparation_Task_Data)payload
    runtime := &data^.state^.dynview
    runtime^.cache_access_state = .Worker_Mutable
    runtime^.cache_worker_thread_id = os.get_current_thread_id()
    dyncompile.compile_if_needed(
        runtime, &runtime^.cache_arena, math_shaping_service(data),
        prose_shaping_service(data))
    runtime^.cache_access_state = .Display_Readable
    _ = evidence_session.session_record(
        &data^.state^.evidence_session, &data^.evidence_ring, {
            lane = .Presentation,
            kind = .Dynview_Compiled,
            correlation_kind = .Fixed_Step,
            correlation = data^.state^.fixed_step,
            tick = data^.state^.fixed_step,
        })
    return .Succeeded
}

//   Borrow the current capability and task-owned shaping workspaces for one rebuild.
math_shaping_service :: proc(
    data: ^Frame_Preparation_Task_Data) -> dynmath.Math_Shaping_Service {

    capability := &data^.state^.dynview.math_shaping
    workspace := data^.math_shaping_workspace
    if workspace == nil {
        return {}
    }
    return {
        user_data = capability,
        generation = capability^.generation,
        base_pixel_size = f32(font.JULIA_MONO_FONT_SIZE),
        raster_ascent = capability^.raster_ascent,
        constants = capability^.constants,
        shape = math_shape_run,
        glyph_metrics = math_shape_glyph_metrics,
        glyph_variants = math_shape_glyph_variants,
        glyph_assembly = math_shape_glyph_assembly,
        horizontal_glyph_variants = math_shape_horizontal_glyph_variants,
        horizontal_glyph_assembly = math_shape_horizontal_glyph_assembly,
        glyph_kern_table = math_shape_glyph_kern_table,
        projection_workspace = workspace^.projection[:],
        glyph_workspace = workspace^.glyphs[:],
    }
}

// Borrow exact effective JuliaMono identities and task-owned prose workspace.
prose_shaping_service :: proc(
    data: ^Frame_Preparation_Task_Data) -> dyncompile.Document_Prose_Shaping_Service {

    workspace := data^.prose_shaping_workspace
    if workspace == nil {
        return {}
    }
    result := dyncompile.Document_Prose_Shaping_Service{
        user_data = &data^.state^.font_cache,
        base_pixel_size = f32(font.JULIA_MONO_FONT_SIZE),
        shape = prose_shape_run,
        glyph_extents = prose_shape_glyph_extents,
        glyph_workspace = workspace^.glyphs[:],
    }
    for key_index in 0..<dyncompile.DOCUMENT_PROSE_FONT_COUNT {
        requested_key := core.Font_Key(key_index)
        identity, ready :=
            font.cache_shaping_identity(&data^.state^.font_cache, requested_key)
        if !ready {
            return {}
        }
        result.fonts[key_index] = {
            identity.key, identity.generation, identity.raster_ascent}
    }
    return result
}

// Shape one prose run through the exact face identity captured for this rebuild.
prose_shape_run :: proc(
    user_data: rawptr,
    request: dyncompile.Document_Prose_Shape_Request) -> (int, bool) {

    return font.cache_shape_generation(
        cast(^core.Font_Cache)user_data, request.key, request.generation,
        request.text, request.output)
}

// Query exact-generation JuliaMono ink extents for one shaped glyph.
prose_shape_glyph_extents :: proc(
    user_data: rawptr, key: core.Font_Key,
    generation: u64, glyph_id: u32) -> (core.Font_Glyph_Extents, bool) {

    return font.cache_glyph_extents_generation(
        cast(^core.Font_Cache)user_data, key, generation, glyph_id)
}

//   Query one bounded corner table through the generation-checked capability.
math_shape_glyph_kern_table :: proc(
    user_data: rawptr,
    request: dynmath.Math_Glyph_Kern_Table_Request) ->
        dynmath.Math_Glyph_Kern_Table_Result {

    result := font.math_shaping_glyph_kern_table(
        cast(^core.Font_Math_Shaping_Capability)user_data,
        request.generation, request.glyph_id,
        font.Harfbuzz_Math_Kern(request.corner), request.output)
    return {result.count, result.ok}
}

//   Shape one math site through the generation-checked NewCM capability.
math_shape_run :: proc(
    user_data: rawptr,
    request: dynmath.Math_Shape_Request) -> dynmath.Math_Shape_Result {

    role := font.Math_Shaping_Role.Upright
    if request.italic {
        role = .Italic
    }
    glyph_count, ok := font.math_shaping_shape(
        cast(^core.Font_Math_Shaping_Capability)user_data,
        request.generation,
        {text = request.text, role = role,
            standalone_accent = request.standalone_accent,
            flattened_accent = request.flattened_accent,
            workspace = request.projection_workspace},
        request.glyph_output)
    return {glyph_count, ok}
}

//   Query and enrich bounded horizontal variants through the math capability.
math_shape_horizontal_glyph_variants :: proc(
    user_data: rawptr,
    request: dynmath.Math_Glyph_Variants_Request) ->
        dynmath.Math_Glyph_Variants_Result {

    capability := cast(^core.Font_Math_Shaping_Capability)user_data
    result := font.math_shaping_horizontal_variants(
        capability, request.generation, request.glyph_id, request.output)
    if !result.ok {
        return {}
    }
    for index in 0..<result.count {
        variant := &request.output[index]
        extents, ok := font.math_shaping_glyph_extents(
            capability, request.generation, variant^.glyph_id)
        accent, accent_ok := font.math_shaping_top_accent_attachment(
            capability, request.generation, variant^.glyph_id)
        if !ok || !accent_ok {
            return {}
        }
        variant^.extents = extents
        variant^.top_accent_attachment = accent
    }
    return {result.count, result.extended_shape, true}
}

//   Query and enrich one bounded horizontal assembly through the math capability.
math_shape_horizontal_glyph_assembly :: proc(
    user_data: rawptr,
    request: dynmath.Math_Glyph_Assembly_Request) ->
        dynmath.Math_Glyph_Assembly_Result {

    capability := cast(^core.Font_Math_Shaping_Capability)user_data
    result := font.math_shaping_horizontal_assembly(
        capability, request.generation, request.glyph_id, request.output)
    if !result.ok {
        return {}
    }
    for index in 0..<result.count {
        part := &request.output[index]
        extents, ok := font.math_shaping_glyph_extents(
            capability, request.generation, part^.glyph_id)
        if !ok {
            return {}
        }
        part^.extents = extents
    }
    return {result.count, result.min_connector_overlap,
        result.italic_correction, true}
}

//   Query complete extents and approved MATH values for one shaped glyph.
math_shape_glyph_metrics :: proc(
    user_data: rawptr,
    request: dynmath.Math_Glyph_Metrics_Request) -> dynmath.Math_Glyph_Metrics_Result {

    capability := cast(^core.Font_Math_Shaping_Capability)user_data
    extents, extents_ok := font.math_shaping_glyph_extents(
        capability, request.generation, request.glyph_id)
    italic, italic_ok := font.math_shaping_italic_correction(
        capability, request.generation, request.glyph_id)
    accent, accent_ok := font.math_shaping_top_accent_attachment(
        capability, request.generation, request.glyph_id)
    return {extents, italic, accent, extents_ok && italic_ok && accent_ok}
}

//   Query bounded vertical variants through the generation-checked capability.
math_shape_glyph_variants :: proc(
    user_data: rawptr,
    request: dynmath.Math_Glyph_Variants_Request) -> dynmath.Math_Glyph_Variants_Result {

    result := font.math_shaping_vertical_variants(
        cast(^core.Font_Math_Shaping_Capability)user_data,
        request.generation, request.glyph_id, request.output)
    if !result.ok {
        return {}
    }
    capability := cast(^core.Font_Math_Shaping_Capability)user_data
    for index in 0..<result.count {
        variant := &request.output[index]
        extents, extents_ok := font.math_shaping_glyph_extents(
            capability, request.generation, variant^.glyph_id)
        italic, italic_ok := font.math_shaping_italic_correction(
            capability, request.generation, variant^.glyph_id)
        accent, accent_ok := font.math_shaping_top_accent_attachment(
            capability, request.generation, variant^.glyph_id)
        if !extents_ok || !italic_ok || !accent_ok {
            return {}
        }
        variant^.extents = extents
        variant^.italic_correction = italic
        variant^.top_accent_attachment = accent
    }
    return {result.count, result.extended_shape, result.ok}
}

//   Query and enrich one bounded vertical assembly through the math capability.
math_shape_glyph_assembly :: proc(
    user_data: rawptr,
    request: dynmath.Math_Glyph_Assembly_Request) -> dynmath.Math_Glyph_Assembly_Result {

    capability := cast(^core.Font_Math_Shaping_Capability)user_data
    result := font.math_shaping_vertical_assembly(
        capability, request.generation, request.glyph_id, request.output)
    if !result.ok {
        return {}
    }
    for index in 0..<result.count {
        part := &request.output[index]
        extents, ok := font.math_shaping_glyph_extents(
            capability, request.generation, part^.glyph_id)
        if !ok {
            return {}
        }
        part^.extents = extents
    }
    return {result.count, result.min_connector_overlap,
        result.italic_correction, true}
}

//   Submit one task into a deterministic batch and require bounded admission.
submit_simulation_task :: proc(
    executor: ^Simulation_Executor, fence: ^taskpool.Task_Fence,
    procedure: taskpool.Task_Procedure, payload: rawptr) {

    outcome := taskpool.task_fence_submit(
        &executor^.pool, fence, procedure, payload)
    assert(outcome == .Queued)
}

//   Submit independent fixed-step systems and wait for the complete batch.
run_parallel_simulation_step :: proc(executor: ^Simulation_Executor, dt: f32) {
    assert(executor != nil)
    executor^.particle_task.dt = dt
    executor^.constraint_task.dt = dt
    fence, initialized := taskpool.task_fence_begin(&executor^.pool)
    assert(initialized)
    submit_simulation_task(executor, &fence, update_particles_task,
        rawptr(&executor^.particle_task))
    submit_simulation_task(executor, &fence, solve_constraints_task,
        rawptr(&executor^.constraint_task))
    assert(taskpool.task_fence_wait(&executor^.pool, &fence) == .Succeeded)
    evidence_session.session_accept_ring(
        &executor^.particle_task.state^.evidence_session,
        &executor^.particle_task.evidence_ring)
    evidence_session.session_accept_ring(
        &executor^.constraint_task.state^.evidence_session,
        &executor^.constraint_task.evidence_ring)
}

//   Prepare frame-owned shape and text caches concurrently before rendering.
run_parallel_frame_preparation :: proc(state: ^core.Euclid_General_State, alpha: f32) {
    assert(state != nil && state^.simulation_executor != nil)
    executor := state^.simulation_executor
    executor^.shape_cache_task.interpolation_alpha = alpha
    fence, initialized := taskpool.task_fence_begin(&executor^.pool)
    assert(initialized)
    submit_simulation_task(executor, &fence, build_shape_cache_task,
        rawptr(&executor^.shape_cache_task))
    if ui.prepare_ui_frame(state) {
        submit_simulation_task(executor, &fence, compile_dynview_task,
            rawptr(&executor^.dynview_task))
    }
    assert(taskpool.task_fence_wait(&executor^.pool, &fence) == .Succeeded)
    evidence_session.session_accept_ring(
        &state^.evidence_session, &executor^.shape_cache_task.evidence_ring)
    evidence_session.session_accept_ring(
        &state^.evidence_session, &executor^.dynview_task.evidence_ring)
}