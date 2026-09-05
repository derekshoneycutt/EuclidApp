package shapes

import "core:math"
import "core:math/linalg"
import "core:testing"


import test_helpers "../test_helpers"

TEST_EPSILON :: f32(1e-4)

//   Build a test point with a fixed position.
make_point :: proc(x, y, z: f32) -> Shapes_Point {
    return Shapes_Point{position = Vector3{x, y, z}}
}

//   Build a distance constraint with a target length and depend_on weighting.
make_distance_constraint :: proc(
    depend_on: i32, req_len: f32) -> Shapes_Constraint {
    return Shapes_Constraint{
        kind = .Distance,
        do_apply = true,
        depend_on = depend_on,
        restriction = Vector3{req_len, 0, 0},
    }
}

//   Verify rotating a vector around an axis preserves its length.
@(test)
rotate_around_axis_preserves_length :: proc(t: ^testing.T) {
    axis := linalg.normalize(Vector3{0, 0, 1})
    input := Vector3{3, 4, 0}
    output := rotate_around_axis(input, axis, math.PI / 2)

    input_len := linalg.length(input)
    output_len := linalg.length(output)

    test_helpers.expect_close(t, output_len, input_len,
        "rotate_around_axis must preserve vector length")
    test_helpers.expect_vec3_close(t, output, Vector3{-4, 3, 0},
        "rotation around +Z by 90 degrees")
}

//   Verify a positive depend_on distance constraint moves only point1.
@(test)
apply_constraint_distance_depend_on_positive_moves_point1 :: proc(t: ^testing.T) {
    p1 := make_point(0, 0, 0)
    p2 := make_point(1, 0, 0)
    constraint := make_distance_constraint(1, 3)

    apply_constraint_distance(&constraint, &p1, &p2)

    expected_p1 := Vector3{-2, 0, 0}
    test_helpers.expect_vec3_close(t, p1.position.? or_else Vector3{},
        expected_p1,
        "depend_on>0 should move point1 only")
    test_helpers.expect_vec3_close(t, p2.position.? or_else Vector3{},
        Vector3{1, 0, 0},
        "depend_on>0 should keep point2 fixed")
}

//   Verify a zero depend_on distance constraint splits motion between both points.
@(test)
apply_constraint_distance_depend_on_zero_splits_motion :: proc(t: ^testing.T) {
    p1 := make_point(-1, 0, 0)
    p2 := make_point(1, 0, 0)
    constraint := make_distance_constraint(0, 6)

    apply_constraint_distance(&constraint, &p1, &p2)

    test_helpers.expect_vec3_close(t, p1.position.? or_else Vector3{},
        Vector3{-3, 0, 0},
        "depend_on==0 should move point1 around midpoint")
    test_helpers.expect_vec3_close(t, p2.position.? or_else Vector3{},
        Vector3{3, 0, 0},
        "depend_on==0 should move point2 around midpoint")
}

//   Verify a negative depend_on distance constraint moves only point2.
@(test)
apply_constraint_distance_depend_on_negative_moves_point2 :: proc(t: ^testing.T) {
    p1 := make_point(0, 0, 0)
    p2 := make_point(1, 0, 0)
    constraint := make_distance_constraint(-1, 4)

    apply_constraint_distance(&constraint, &p1, &p2)

    test_helpers.expect_vec3_close(t, p1.position.? or_else Vector3{},
        Vector3{0, 0, 0},
        "depend_on<0 should keep point1 fixed")
    test_helpers.expect_vec3_close(t, p2.position.? or_else Vector3{},
        Vector3{4, 0, 0},
        "depend_on<0 should move point2 only")
}

//   Verify resolve_constraint_targets honors a child offset in the point chain.
@(test)
resolve_constraint_targets_supports_child_offset :: proc(t: ^testing.T) {
    points: [MAX_SHAPESPOINTS]Shapes_Point

    points[0] = Shapes_Point{
        child_point_head = 1,
        child_count = 3,
    }

    points[1] = Shapes_Point{next_child_point = 2}
    points[2] = Shapes_Point{next_child_point = 3}
    points[3] = Shapes_Point{}

    constraint := Shapes_Constraint{
        kind = .Distance,
        on_point = 0,
        child_offset = 1,
        do_apply = true,
    }

    targets, ok := resolve_constraint_targets(&constraint, &points)

    testing.expect(t, ok)
    testing.expect_value(t, targets.child_count, 2)
    testing.expect_value(t, targets.host, &points[0])
    testing.expect_value(t, targets.children[0], &points[2])
    testing.expect_value(t, targets.children[1], &points[3])
}
