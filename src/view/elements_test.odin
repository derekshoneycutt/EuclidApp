package view

import "../core"

import "core:math"
import "core:math/linalg"
import "core:testing"


TOOL_BRUSH_TEST_EPSILON :: f32(1e-4)


//   Verify nearby and distant tool segments are classified by expanded bounds.
@(test)
tool_brush_occluder_overlap_respects_expanded_bounds :: proc(t: ^testing.T) {
    receiver := Tool_Brush_Occluder{p0 = {0, 0}, p1 = {10, 0}, thickness = 2}
    nearby := Tool_Brush_Occluder{p0 = {5, 4}, p1 = {5, 8}, thickness = 2}
    distant := Tool_Brush_Occluder{p0 = {5, 20}, p1 = {5, 24}, thickness = 2}

    testing.expect(t, tool_brush_occluder_overlaps(receiver, nearby))
    testing.expect(t, !tool_brush_occluder_overlaps(receiver, distant))
}


//   Verify caster thickness expands the interaction reach conservatively.
@(test)
tool_brush_occluder_overlap_accounts_for_caster_thickness :: proc(t: ^testing.T) {
    receiver := Tool_Brush_Occluder{p0 = {0, 0}, p1 = {10, 0}, thickness = 2}
    thin := Tool_Brush_Occluder{p0 = {5, 8}, p1 = {5, 12}, thickness = 1}
    thick := Tool_Brush_Occluder{p0 = {5, 8}, p1 = {5, 12}, thickness = 4}

    testing.expect(t, !tool_brush_occluder_overlaps(receiver, thin))
    testing.expect(t, tool_brush_occluder_overlaps(receiver, thick))
}


//   Verify context insertion rejects distant casters and respects fixed capacity.
@(test)
append_tool_brush_occluder_filters_and_caps_context :: proc(t: ^testing.T) {
    receiver := Tool_Brush_Occluder{p0 = {0, 0}, p1 = {10, 0}, thickness = 2}
    nearby1 := Tool_Brush_Occluder{p0 = {2, 1}, p1 = {2, 3}, thickness = 2}
    nearby2 := Tool_Brush_Occluder{p0 = {5, 1}, p1 = {5, 3}, thickness = 2}
    nearby3 := Tool_Brush_Occluder{p0 = {8, 1}, p1 = {8, 3}, thickness = 2}
    distant := Tool_Brush_Occluder{p0 = {30, 30}, p1 = {35, 35}, thickness = 2}
    ctx := Tool_Brush_Occluder_Context{}

    append_tool_brush_occluder(&ctx, receiver, distant)
    testing.expect_value(t, ctx.count, 0)

    append_tool_brush_occluder(&ctx, receiver, nearby1)
    append_tool_brush_occluder(&ctx, receiver, nearby2)
    append_tool_brush_occluder(&ctx, receiver, nearby3)

    testing.expect_value(t, ctx.count, core.MAX_TOOL_BRUSH_OCCLUDERS)
    testing.expect_value(t, ctx.occluders[0].p0, nearby1.p0)
    testing.expect_value(t, ctx.occluders[1].p0, nearby2.p0)
}


//   Verify only the earlier cached tool receives shadows from the later tool.
@(test)
tool_brush_interaction_receivers_follow_cache_order :: proc(t: ^testing.T) {
    pen_receives, compass_receives := tool_brush_interaction_receivers(2, 5)
    testing.expect(t, pen_receives)
    testing.expect(t, !compass_receives)

    pen_receives, compass_receives = tool_brush_interaction_receivers(7, 3)
    testing.expect(t, !pen_receives)
    testing.expect(t, compass_receives)

    pen_receives, compass_receives = tool_brush_interaction_receivers(-1, 3)
    testing.expect(t, !pen_receives)
    testing.expect(t, !compass_receives)
}


//   Verify the orthonormal view transform maps its basis and preserves length.
@(test)
tool_brush_light_to_view_preserves_basis_and_length :: proc(t: ^testing.T) {
    right_view := tool_brush_light_to_view(STROKE3D_VIEW_RIGHT)
    testing.expectf(t, math.abs(right_view.x - 1.0) <= TOOL_BRUSH_TEST_EPSILON,
        "view-right x | expected=1 got=%v", right_view.x)
    testing.expectf(t, math.abs(right_view.y) <= TOOL_BRUSH_TEST_EPSILON,
        "view-right y | expected=0 got=%v", right_view.y)
    testing.expectf(t, math.abs(right_view.z) <= TOOL_BRUSH_TEST_EPSILON,
        "view-right z | expected=0 got=%v", right_view.z)

    direction := linalg.normalize(Vector3{1, 2, 3})
    direction_view := tool_brush_light_to_view(direction)
    testing.expectf(t,
        math.abs(linalg.length(direction_view) - 1.0) <= TOOL_BRUSH_TEST_EPSILON,
        "view transform length | expected=1 got=%v", linalg.length(direction_view))
}


//   Verify canonical depth increases toward the camera and opposes the old sort key.
@(test)
tool_brush_view_depth_uses_larger_as_closer :: proc(t: ^testing.T) {
    origin := Vector3{}
    closer := STROKE3D_VIEW_FORWARD

    testing.expect(t, tool_brush_view_depth(closer) > tool_brush_view_depth(origin))
    old_origin_depth := origin.x + origin.y - origin.z
    old_closer_depth := closer.x + closer.y - closer.z
    testing.expect(t, old_closer_depth < old_origin_depth)
}


//   Verify fixed arc samples span the complete normalized parameter interval.
@(test)
compass_arc_parameter_includes_both_endpoints :: proc(t: ^testing.T) {
    testing.expect_value(t, compass_arc_parameter(0), f32(0))
    testing.expect_value(t,
        compass_arc_parameter(COMPASS_TOPCIRCLE_SEGMENTS), f32(1))
}


//   Verify welded attachment length scales with brush size and remains bounded.
@(test)
compass_arc_attachment_extent_is_scaled_and_bounded :: proc(t: ^testing.T) {
    thin := compass_arc_attachment_extent(2, 0.25, math.PI, 400)
    thick := compass_arc_attachment_extent(8, 0.25, math.PI, 400)
    minimum := f32(1.0 / f32(COMPASS_TOPCIRCLE_SEGMENTS))

    testing.expect(t, thick > thin)
    testing.expect(t, thin >= minimum)
    testing.expect(t, thick <= 0.18)
}


//   Verify each physical leg retains its corresponding arc endpoint slot.
@(test)
make_compass_arc_occluders_preserves_attachment_slots :: proc(t: ^testing.T) {
    leg1 := Tool_Brush_Occluder{depth0 = 1, depth1 = 2}
    leg2 := Tool_Brush_Occluder{depth0 = 3, depth1 = 4}

    ctx := make_compass_arc_occluders(leg1, leg2)

    testing.expect_value(t, ctx.count, core.MAX_TOOL_BRUSH_OCCLUDERS)
    testing.expect_value(t, ctx.occluders[0].depth0, leg1.depth0)
    testing.expect_value(t, ctx.occluders[1].depth0, leg2.depth0)
}