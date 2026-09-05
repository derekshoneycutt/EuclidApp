package view_core

import "core:math"
import "core:testing"


TEST_EPSILON :: f32(1e-4)

//   Assert that two Vector2 values match component-wise within TEST_EPSILON.
expect_vec2_close :: proc(
    t: ^testing.T,
    actual, expected: Vector2,
    msg: string) {
    testing.expectf(t, math.abs(actual.x - expected.x) <= TEST_EPSILON,
        "%s (x) | expected=%v got=%v", msg, expected.x, actual.x)
    testing.expectf(t, math.abs(actual.y - expected.y) <= TEST_EPSILON,
        "%s (y) | expected=%v got=%v", msg, expected.y, actual.y)
}

//   Build an Iso_Scale with the given scale and offsets, precomputing coefficients.
make_iso_scale :: proc(scale, x_offset, y_offset: f32) -> Iso_Scale {
    iso := Iso_Scale{
        scale = scale,
        x_offset = x_offset,
        y_offset = y_offset,
    }
    recompute_iso_scale_precompute(&iso)
    return iso
}

//   Verify recompute_iso_scale_precompute sets the cached half/quarter coefficients.
@(test)
recompute_iso_scale_precompute_sets_cached_coefficients :: proc(t: ^testing.T) {
    iso := Iso_Scale{scale = 800}

    recompute_iso_scale_precompute(&iso)

    testing.expect_value(t, iso.half_scale, f32(400))
    testing.expect_value(t, iso.quarter_scale, f32(200))
}

//   Verify the inline component projection matches the isometric formula.
@(test)
iso_to_cartesian_components_inline_matches_projection_formula :: proc(t: ^testing.T) {
    iso := make_iso_scale(800, 450, 450)

    projected := iso_to_cartesian_components_inline(2, -1, 3, iso)

    expect_vec2_close(t, projected, Vector2{1650, -950},
        "components inline projection should match formula")
}

//   Verify the coordinate, inline, and component projection variants agree.
@(test)
iso_to_cartesian_variants_match_each_other :: proc(t: ^testing.T) {
    iso := make_iso_scale(640, 320, 240)
    input := Vector3{3, 1, -2}

    via_coord := iso_to_cartesian(input, iso)
    via_inline := iso_to_cartesian_inline(input, iso)
    via_components := iso_to_cartesian_components_inline(
        input.x, input.y, input.z, iso)

    expect_vec2_close(t, via_coord, via_inline,
        "iso_to_cartesian and iso_to_cartesian_inline should agree")
    expect_vec2_close(t, via_coord, via_components,
        "coordinate and component projection helpers should agree")
}

//   Verify the batch projection stops at the shortest input slice length.
@(test)
iso_to_cartesian_components_batch_respects_shortest_input_length :: proc(t: ^testing.T) {
    iso := make_iso_scale(800, 450, 450)

    xs := []f32{0, 1, 2, 3}
    ys := []f32{0, 1}
    zs := []f32{0, 0, 0}
    out: [4]Vector2

    count := iso_to_cartesian_components_batch(xs, ys, zs, out[:], iso)

    testing.expect_value(t, count, 2)
    expect_vec2_close(t, out[0],
        iso_to_cartesian_components_inline(0, 0, 0, iso),
        "batch projection index 0")
    expect_vec2_close(t, out[1],
        iso_to_cartesian_components_inline(1, 1, 0, iso),
        "batch projection index 1")
}

//   Verify the scalar selected projection path matches the batch projection.
@(test)
iso_to_cartesian_components_batch_selected_scalar_path_matches_batch :: proc(
    t: ^testing.T) {
    iso := make_iso_scale(500, 100, -50)

    xs := []f32{1, 2, 3, 4}
    ys := []f32{2, 3, 4, 5}
    zs := []f32{0, 1, 2, 3}

    out_batch: [4]Vector2
    out_selected: [4]Vector2

    batch_count := iso_to_cartesian_components_batch(
        xs, ys, zs, out_batch[:], iso)
    selected_count := iso_to_cartesian_components_batch_selected(
        Iso_Batch_Projection{xs, ys, zs, out_selected[:], iso}, false)

    testing.expect_value(t, selected_count, batch_count)
    for i in 0..<batch_count {
        expect_vec2_close(t, out_selected[i], out_batch[i],
            "selected scalar path should match scalar batch")
    }
}
