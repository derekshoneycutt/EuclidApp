package particles

import "core:math"
import "core:testing"

import app_core "../core"
import app_view_core "../view/core"
import test_helpers "../test_helpers"

EPS :: f32(1e-5)

//   Snapshot one low-particle slot's position and velocity.
Dust_Slot_Snapshot :: struct {
    x:  f32,
    y:  f32,
    vx: f32,
    vy: f32,
}

//   Verify theta normalization and sweep delta wrap correctly across zero.
@(test)
normalize_theta_and_sweep_delta_are_stable :: proc(t: ^testing.T) {
    theta := normalize_theta(f32(-0.5))
    test_helpers.expect_close(t, theta, f32(2.0 * math.PI - 0.5),
        "normalize_theta should wrap negatives")

    delta := compute_sweep_delta(
        f32(1.5 * math.PI),
        f32(0.5 * math.PI))
    test_helpers.expect_close(t, delta, f32(math.PI),
        "sweep delta should wrap across zero")
}

//   Verify dust_grid_cell_index clamps out-of-range coordinates to the grid.
@(test)
dust_grid_cell_index_clamps_bounds :: proc(t: ^testing.T) {
    testing.expect_value(t, dust_grid_cell_index(-1, -1), 0)

    max_idx := DUST_GRID_DIM * DUST_GRID_DIM - 1
    testing.expect_value(t, dust_grid_cell_index(99, 99), max_idx)
}

//   Verify slot reservation prefers dead slots and wraps at the particle cap.
@(test)
reserve_dead_low_particle_slot_prefers_dead_then_wraps :: proc(t: ^testing.T) {
    ps := new(app_core.Particle_System)
    defer free(ps)
    ps^.use_max_dust_particles = 3
    ps^.next_index = 0

    idx0, ok0 := reserve_dead_low_particle_slot(ps)
    testing.expect(t, ok0)
    testing.expect_value(t, idx0, 0)
    testing.expect_value(t, ps^.next_index, 1)

    ps^.low_particles.alive[1] = true
    idx1, ok1 := reserve_dead_low_particle_slot(ps)
    testing.expect(t, ok1)
    testing.expect_value(t, idx1, 2)
    testing.expect_value(t, ps^.next_index, 0)

    ps^.low_particles.alive[0] = true
    ps^.low_particles.alive[1] = true
    ps^.low_particles.alive[2] = true
    idx2, ok2 := reserve_dead_low_particle_slot(ps)
    testing.expect(t, ok2)
    testing.expect_value(t, idx2, 0)
}

//   Verify the reservation ring index wraps back to zero at the cap.
@(test)
reserve_dead_particle_slot_ring_advances :: proc(t: ^testing.T) {
    ps := new(app_core.Particle_System)
    defer free(ps)
    ps^.next_index = MAX_PARTICLES - 1

    idx, ok := reserve_dead_particle_slot(ps)
    testing.expect(t, ok)
    testing.expect_value(t, idx, MAX_PARTICLES - 1)
    testing.expect_value(t, ps^.next_index, 0)
}

//   Capture one low-particle slot's current position and velocity.
dust_slot_snapshot :: #force_inline proc(
    ps: ^app_core.Particle_System, index: int) -> Dust_Slot_Snapshot {

    return Dust_Slot_Snapshot{
        ps^.low_particles.pos_x[index],
        ps^.low_particles.pos_y[index],
        ps^.low_particles.vel_x[index],
        ps^.low_particles.vel_y[index],
    }
}

//   Assert one low-particle slot still matches a prior snapshot.
expect_dust_slot_unchanged :: proc(
    t: ^testing.T,
    ps: ^app_core.Particle_System,
    index: int,
    before: Dust_Slot_Snapshot) {

    test_helpers.expect_close(t, ps^.low_particles.pos_x[index], before.x,
        "no collision should keep x")
    test_helpers.expect_close(t, ps^.low_particles.pos_y[index], before.y,
        "no collision should keep y")
    test_helpers.expect_close(t, ps^.low_particles.vel_x[index], before.vx,
        "no collision should keep vx")
    test_helpers.expect_close(t, ps^.low_particles.vel_y[index], before.vy,
        "no collision should keep vy")
}

//   Verify a non-overlapping dust pair keeps positions and velocities unchanged.
@(test)
resolve_dust_pair_no_collision_keeps_state :: proc(t: ^testing.T) {
    ps := new(app_core.Particle_System)
    defer free(ps)

    ps^.low_particles.pos_x[0] = 0.2
    ps^.low_particles.pos_y[0] = 0.2
    ps^.low_particles.pos_x[1] = 0.9
    ps^.low_particles.pos_y[1] = 0.9

    ps^.low_particles.vel_x[0] = 0.01
    ps^.low_particles.vel_y[0] = -0.02
    ps^.low_particles.vel_x[1] = -0.03
    ps^.low_particles.vel_y[1] = 0.04

    before_a := dust_slot_snapshot(ps, 0)
    before_b := dust_slot_snapshot(ps, 1)

    min_sep: f32 = DUST_COLLISION_RADIUS * f32(2.0)
    radius_sq: f32 = DUST_COLLISION_RADIUS *
        DUST_COLLISION_RADIUS
    resolve_dust_pair(ps, 0, 1, min_sep, radius_sq)

    expect_dust_slot_unchanged(t, ps, 0, before_a)
    expect_dust_slot_unchanged(t, ps, 1, before_b)
}

//   Verify an approaching overlapping pair receives a separating impulse.
@(test)
resolve_dust_pair_overlap_with_approach_applies_impulse :: proc(t: ^testing.T) {
    ps := new(app_core.Particle_System)
    defer free(ps)

    ps^.low_particles.pos_x[0] = 0.4
    ps^.low_particles.pos_y[0] = 0.5
    ps^.low_particles.pos_x[1] = 0.403
    ps^.low_particles.pos_y[1] = 0.5

    ps^.low_particles.vel_x[0] = 0.01
    ps^.low_particles.vel_y[0] = 0.0
    ps^.low_particles.vel_x[1] = -0.01
    ps^.low_particles.vel_y[1] = 0.0

    before_x0 := ps^.low_particles.pos_x[0]
    before_x1 := ps^.low_particles.pos_x[1]

    min_sep: f32 = DUST_COLLISION_RADIUS * f32(2.0)
    radius_sq: f32 = DUST_COLLISION_RADIUS *
        DUST_COLLISION_RADIUS
    resolve_dust_pair(ps, 0, 1, min_sep, radius_sq)

    testing.expect(t, ps^.low_particles.pos_x[0] < before_x0)
    testing.expect(t, ps^.low_particles.pos_x[1] > before_x1)
    testing.expect(t, ps^.low_particles.vel_x[0] < 0)
    testing.expect(t, ps^.low_particles.vel_x[1] > 0)
}

//   Verify a separating overlapping pair repositions but skips the impulse.
@(test)
resolve_dust_pair_overlap_with_separating_velocity_skips_impulse :: proc(t: ^testing.T) {
    ps := new(app_core.Particle_System)
    defer free(ps)

    ps^.low_particles.pos_x[0] = 0.4
    ps^.low_particles.pos_y[0] = 0.5
    ps^.low_particles.pos_x[1] = 0.403
    ps^.low_particles.pos_y[1] = 0.5

    ps^.low_particles.vel_x[0] = -0.01
    ps^.low_particles.vel_y[0] = 0.0
    ps^.low_particles.vel_x[1] = 0.01
    ps^.low_particles.vel_y[1] = 0.0

    before_x0 := ps^.low_particles.pos_x[0]
    before_x1 := ps^.low_particles.pos_x[1]

    min_sep: f32 = DUST_COLLISION_RADIUS * f32(2.0)
    radius_sq: f32 = DUST_COLLISION_RADIUS *
        DUST_COLLISION_RADIUS
    resolve_dust_pair(ps, 0, 1, min_sep, radius_sq)

    testing.expect(t, ps^.low_particles.pos_x[0] < before_x0)
    testing.expect(t, ps^.low_particles.pos_x[1] > before_x1)
    test_helpers.expect_close(t, ps^.low_particles.vel_x[0], f32(-0.01),
        "separating vx0 should be unchanged")
    test_helpers.expect_close(t, ps^.low_particles.vel_x[1], f32(0.01),
        "separating vx1 should be unchanged")
}

//   Verify exactly coincident particles separate along a deterministic direction.
@(test)
resolve_dust_pair_exact_overlap_uses_deterministic_separation :: proc(t: ^testing.T) {
    ps := new(app_core.Particle_System)
    defer free(ps)

    ps^.low_particles.pos_x[0] = 0.5
    ps^.low_particles.pos_y[0] = 0.5
    ps^.low_particles.pos_x[1] = 0.5
    ps^.low_particles.pos_y[1] = 0.5

    min_sep: f32 = DUST_COLLISION_RADIUS * f32(2.0)
    radius_sq: f32 = DUST_COLLISION_RADIUS *
        DUST_COLLISION_RADIUS
    resolve_dust_pair(ps, 0, 1, min_sep, radius_sq)

    dx := ps^.low_particles.pos_x[1] - ps^.low_particles.pos_x[0]
    dy := ps^.low_particles.pos_y[1] - ps^.low_particles.pos_y[0]
    testing.expect(t, dx * dx + dy * dy > 0)
}

//   Verify two fresh particle systems produce identical seeded random ranges.
@(test)
particle_random_ranges_use_independent_seeded_generators :: proc(t: ^testing.T) {
    first := new(app_core.Particle_System)
    defer free(first)
    second := new(app_core.Particle_System)
    defer free(second)

    testing.expect_value(t,
        random_f32_range(first, -1, 1),
        random_f32_range(second, -1, 1))
    testing.expect_value(t,
        random_i32_range(first, -10, 10),
        random_i32_range(second, -10, 10))
}

//   Verify dense-bucket collision resolution rotates samples and tracks counts.
@(test)
resolve_dust_collisions_rotates_dense_bucket_samples :: proc(t: ^testing.T) {
    ps := new(app_core.Particle_System)
    defer free(ps)

    ps^.use_max_dust_particles = app_core.DUST_GRID_BUCKET_CAP + 8
    for i in 0..<ps^.use_max_dust_particles {
        ps^.low_particles[i].alive = true
        ps^.low_particles.pos_x[i] = 0.5
        ps^.low_particles.pos_y[i] = 0.5
    }

    resolve_dust_collisions(ps)

    testing.expect_value(t, ps^.dust_collision_frame, u64(1))
    testing.expect_value(t,
        ps^.dust_counts[dust_grid_cell_index(0.5, 0.5)],
        i32(app_core.DUST_GRID_BUCKET_CAP))
    testing.expect_value(t,
        ps^.dust_seen_counts[dust_grid_cell_index(0.5, 0.5)],
        i32(ps^.use_max_dust_particles))
}

//   Verify reset_particles zeroes runtime state and marks every slot dead.
@(test)
reset_particles_clears_runtime_state_and_marks_all_slots_dead :: proc(t: ^testing.T) {
    ps := new(app_core.Particle_System)
    defer free(ps)

    ps^.use_max_dust_particles = 2
    ps^.spawn_timer = 1.0
    ps^.next_index = 3
    ps^.low_particles.alive[0] = true
    ps^.low_particles.age[0] = 0.25
    ps^.particles.alive[0] = true
    ps^.particles.age[0] = 0.5
    ps^.high_particles.alive[0] = true
    ps^.high_particles.age[0] = 0.75

    reset_particles(ps)

    testing.expect_value(t, ps^.next_index, 0)
    testing.expect_value(t, ps^.spawn_timer, 0.0)
    testing.expect(t, !ps^.low_particles.alive[0])
    testing.expect_value(t, ps^.low_particles.age[0], 0.0)
    testing.expect(t, !ps^.particles.alive[0])
    testing.expect_value(t, ps^.particles.age[0], 0.0)
    testing.expect(t, !ps^.high_particles.alive[0])
    testing.expect_value(t, ps^.high_particles.age[0], 0.0)
}

//   Verify a single dust kick adds trauma and resets the screenshake clock.
@(test)
screenshake_on_dust_kick_adds_trauma :: proc(t: ^testing.T) {
    scale: app_core.Iso_Scale

    app_view_core.screenshake_on_dust_kick(&scale)

    testing.expect(t, scale.screenshake_trauma > 0)
    testing.expect_value(t, scale.screenshake_elapsed, 0.0)
}

//   Verify a batched dust kick produces a stronger aggregated impulse.
@(test)
screenshake_on_dust_kick_batch_uses_stronger_aggregated_impulse :: proc(t: ^testing.T) {
    single: app_core.Iso_Scale
    batch: app_core.Iso_Scale

    app_view_core.screenshake_on_dust_kick(&single)
    app_view_core.screenshake_on_dust_kick_batch(&batch, 8)

    testing.expect(t, batch.screenshake_trauma > single.screenshake_trauma)
}

//   Verify screenshake decays over time and clears fully at the max time.
@(test)
screenshake_update_decays_and_clears_deterministically :: proc(t: ^testing.T) {
    scale: app_core.Iso_Scale

    app_view_core.screenshake_on_dust_kick(&scale)
    before := scale.screenshake_trauma

    app_view_core.screenshake_update(&scale, 0.01)

    testing.expect(t, scale.screenshake_trauma < before)
    testing.expect(t, scale.screenshake_offset_x != 0 || scale.screenshake_offset_y != 0)

    app_view_core.screenshake_update(&scale, app_view_core.SCREENSHAKE_MAX_TIME)

    testing.expect_value(t, scale.screenshake_trauma, 0.0)
    testing.expect_value(t, scale.screenshake_elapsed, 0.0)
    testing.expect_value(t, scale.screenshake_offset_x, 0.0)
    testing.expect_value(t, scale.screenshake_offset_y, 0.0)
}

//   Verify slot reservation wraps to index zero when every slot is alive.
@(test)
reserve_dead_low_particle_slot_wraps_when_all_slots_alive :: proc(t: ^testing.T) {
    ps := new(app_core.Particle_System)
    defer free(ps)

    ps^.use_max_dust_particles = 2
    ps^.next_index = 0
    ps^.low_particles.alive[0] = true
    ps^.low_particles.alive[1] = true

    idx, ok := reserve_dead_low_particle_slot(ps)
    testing.expect(t, ok)
    testing.expect_value(t, idx, 0)
    testing.expect_value(t, ps^.next_index, 1)
}

//   Verify a shape-hide burst spawns dust for the supported shape kinds.
@(test)
emit_shapes_hide_burst_spawns_dust_for_supported_shapes :: proc(t: ^testing.T) {
    ps := new(app_core.Particle_System)
    defer free(ps)
    ps^.use_max_dust_particles = 4

    ks: app_core.Shapes_Point_System
    ks.points[0].do_draw = true
    ks.points[0].kind = .Point
    ks.points[0].position = app_core.Vector3{1, 2, 0}

    emit_shapes_hide_burst(ps, &ks, 0, false)

    testing.expect(t, ps^.low_particles.alive[0])
    testing.expect(t, ps^.low_particles.alive[1] || ps^.low_particles.alive[2] ||
        ps^.low_particles.alive[3])
}

//   Verify out-of-bounds particles clamp to the bounds and bounce their velocity.
@(test)
clamp_xy_bounds_index_bounces_particles_back_inside_bounds :: proc(t: ^testing.T) {
    ps := new(app_core.Particle_System)
    defer free(ps)
    ps^.use_max_dust_particles = 1

    ps^.low_particles.pos_x[0] = -0.5
    ps^.low_particles.pos_y[0] = 1.2
    ps^.low_particles.vel_x[0] = -0.1
    ps^.low_particles.vel_y[0] = 0.2

    clamp_xy_bounds_index(ps, 0)

    testing.expect_value(t, ps^.low_particles.pos_x[0], DUST_XY_MIN)
    testing.expect_value(t, ps^.low_particles.pos_y[0], DUST_XY_MAX)
    testing.expect(t, ps^.low_particles.vel_x[0] > 0)
    testing.expect(t, ps^.low_particles.vel_y[0] < 0)
}
