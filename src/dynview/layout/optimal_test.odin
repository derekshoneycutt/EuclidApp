package dynview_layout

import app_core "../../core"
import "core:mem"
import "core:testing"

// Initialize bounded line storage for optimal paragraph tests.
document_optimal_test_lines :: proc(
    t: ^testing.T,
    arena: ^app_core.Arena_Owner) ->
        app_core.Bounded_Element_Builder(app_core.Dynview_Document_Layout_Line) {

    testing.expect(t, app_core.arena_owner_init(arena, 2*uint(mem.Megabyte)))
    builder: app_core.Bounded_Element_Builder(
        app_core.Dynview_Document_Layout_Line)
    testing.expect_value(t, app_core.bounded_element_builder_init(
        &builder, app_core.DYNVIEW_MAX_DOCUMENT_LAYOUT_LINES, arena),
        app_core.Bounded_Builder_Status.Ok)
    return builder
}

// Verify a strongly favorable semantic penalty defeats the later greedy breakpoint.
@(test)
document_optimal_penalty_selects_competing_path :: proc(t: ^testing.T) {
    optimal_arena, greedy_arena: app_core.Arena_Owner
    lines := document_optimal_test_lines(t, &optimal_arena)
    defer app_core.arena_owner_destroy(&optimal_arena)
    greedy_lines := document_optimal_test_lines(t, &greedy_arena)
    defer app_core.arena_owner_destroy(&greedy_arena)
    nodes := [7]app_core.Dynview_Document_Layout_Node{
        {kind = .Box, width = 30},
        {kind = .Penalty, penalty = -9999, break_allowed = true},
        {kind = .Box, width = 30},
        {kind = .Glue, width = 10, stretch = 20, shrink = 3,
            break_allowed = true},
        {kind = .Box, width = 30},
        {kind = .Glue, width = 10, stretch = 20, shrink = 3,
            break_allowed = true},
        {kind = .Box, width = 30},
    }

    result := document_optimal_break(nodes[:], 2, 80, &lines)
    greedy_status := document_greedy_break(nodes[:], 2, 80, &greedy_lines)

    testing.expect_value(t, result.status, app_core.Bounded_Builder_Status.Ok)
    testing.expect_value(t, greedy_status, app_core.Bounded_Builder_Status.Ok)
    testing.expect_value(t, result.fallback, Document_Break_Fallback.None)
    testing.expect(t, lines.count > 1)
    testing.expect_value(t, lines.storage[0].node_count, 2)
    testing.expect(t,
        lines.storage[0].node_count != greedy_lines.storage[0].node_count)
}

// Verify glue ratios use stretch below measure and shrink above measure.
@(test)
document_optimal_quality_uses_glue_ratios :: proc(t: ^testing.T) {
    loose := document_break_quality(80, 40, 10, 100, false)
    tight := document_break_quality(110, 40, 20, 100, false)

    testing.expect_value(t, loose.ratio, f32(0.5))
    testing.expect_value(t, loose.badness, f64(12.5))
    testing.expect_value(t, loose.fitness, Document_Break_Fitness.Decent)
    testing.expect(t, !loose.overfull)
    testing.expect_value(t, tight.ratio, f32(-0.5))
    testing.expect_value(t, tight.badness, f64(12.5))
    testing.expect_value(t, tight.fitness, Document_Break_Fitness.Decent)
    testing.expect(t, !tight.overfull)
}

// Verify one adjusted line publishes its natural width, ratio, and target width.
document_optimal_expect_adjustment :: proc(
    t: ^testing.T,
    line: app_core.Dynview_Document_Layout_Line,
    natural_width, ratio, width: f32) {

    testing.expect_value(t, line.natural_width, natural_width)
    testing.expect_value(t, line.adjustment_ratio, ratio)
    testing.expect_value(t, line.width, width)
}

// Verify selected interior lines publish exact stretch and shrink geometry.
@(test)
document_optimal_publishes_adjusted_line_widths :: proc(t: ^testing.T) {
    stretch_arena, shrink_arena: app_core.Arena_Owner
    stretch_lines := document_optimal_test_lines(t, &stretch_arena)
    defer app_core.arena_owner_destroy(&stretch_arena)
    shrink_lines := document_optimal_test_lines(t, &shrink_arena)
    defer app_core.arena_owner_destroy(&shrink_arena)
    stretch_nodes := [5]app_core.Dynview_Document_Layout_Node{
        {kind = .Box, width = 30},
        {kind = .Glue, width = 10, stretch = 20, shrink = 3},
        {kind = .Box, width = 30},
        {kind = .Glue, width = 10, stretch = 20, shrink = 3,
            break_allowed = true}, {kind = .Box, width = 30},
    }
    shrink_nodes := [5]app_core.Dynview_Document_Layout_Node{
        {kind = .Box, width = 40},
        {kind = .Glue, width = 20, stretch = 10, shrink = 10},
        {kind = .Box, width = 40},
        {kind = .Glue, width = 10, stretch = 5, shrink = 3,
            break_allowed = true}, {kind = .Box, width = 40},
    }
    stretch_result := document_optimal_break(stretch_nodes[:], 0, 80, &stretch_lines)
    shrink_result := document_optimal_break(shrink_nodes[:], 0, 95, &shrink_lines)

    testing.expect_value(t, stretch_result.status, app_core.Bounded_Builder_Status.Ok)
    testing.expect_value(t, shrink_result.status, app_core.Bounded_Builder_Status.Ok)
    document_optimal_expect_adjustment(t, stretch_lines.storage[0], 70, 0.5, 80)
    document_optimal_expect_adjustment(t, shrink_lines.storage[0], 100, -0.5, 95)
    testing.expect_value(t,
        stretch_lines.storage[stretch_lines.count-1].adjustment_ratio, f32(0))
}

// Verify nonadjacent fitness classes add the documented transition demerits.
@(test)
document_optimal_penalizes_abrupt_fitness_changes :: proc(t: ^testing.T) {
    adjacent := document_break_demerits(20, 0, .Decent, .Loose)
    abrupt := document_break_demerits(20, 0, .Tight, .Very_Loose)

    testing.expect_value(t, abrupt-adjacent, DOCUMENT_BREAK_FITNESS_DEMERITS)
}

// Verify forced boundaries terminate paths while an indivisible box remains overfull.
@(test)
document_optimal_honors_forced_and_atomic_overfull_lines :: proc(t: ^testing.T) {
    arena: app_core.Arena_Owner
    lines := document_optimal_test_lines(t, &arena)
    defer app_core.arena_owner_destroy(&arena)
    nodes := [3]app_core.Dynview_Document_Layout_Node{
        {kind = .Box, width = 20},
        {kind = .Forced_Break, break_allowed = true},
        {kind = .Box, width = 140},
    }

    result := document_optimal_break(nodes[:], 4, 100, &lines)

    testing.expect_value(t, result.status, app_core.Bounded_Builder_Status.Ok)
    testing.expect_value(t, result.fallback, Document_Break_Fallback.None)
    testing.expect_value(t, lines.count, 2)
    testing.expect_value(t, lines.storage[0].node_count, 1)
    testing.expect(t, lines.storage[1].overfull)
}

// Verify every bounded-search exhaustion mode reproduces greedy line records exactly.
@(test)
document_optimal_exhaustion_is_exact_greedy_fallback :: proc(t: ^testing.T) {
    optimal_arena, greedy_arena: app_core.Arena_Owner
    optimal_lines := document_optimal_test_lines(t, &optimal_arena)
    defer app_core.arena_owner_destroy(&optimal_arena)
    greedy_lines := document_optimal_test_lines(t, &greedy_arena)
    defer app_core.arena_owner_destroy(&greedy_arena)
    nodes := [5]app_core.Dynview_Document_Layout_Node{
        {kind = .Box, width = 40},
        {kind = .Glue, width = 5, stretch = 3, shrink = 2,
            break_allowed = true},
        {kind = .Box, width = 70},
        {kind = .Glue, width = 5, stretch = 3, shrink = 2,
            break_allowed = true},
        {kind = .Box, width = 20},
    }

    result := document_optimal_break_with_limits(
        nodes[:], 3, {available = 100}, &optimal_lines,
        {candidates = 8, states = 32, work = 1})
    greedy_status := document_greedy_break(nodes[:], 3, 100, &greedy_lines)

    testing.expect_value(t, result.status, greedy_status)
    testing.expect_value(t, result.fallback, Document_Break_Fallback.Work_Limit)
    testing.expect_value(t, optimal_lines.count, greedy_lines.count)
    for index in 0..<greedy_lines.count {
        testing.expect_value(t, optimal_lines.storage[index], greedy_lines.storage[index])
    }
}

// Verify candidate and state ceilings each select deterministic greedy fallback.
@(test)
document_optimal_storage_limits_fallback :: proc(t: ^testing.T) {
    candidate_arena, state_arena: app_core.Arena_Owner
    candidate_lines := document_optimal_test_lines(t, &candidate_arena)
    defer app_core.arena_owner_destroy(&candidate_arena)
    state_lines := document_optimal_test_lines(t, &state_arena)
    defer app_core.arena_owner_destroy(&state_arena)
    nodes := [3]app_core.Dynview_Document_Layout_Node{
        {kind = .Box, width = 40},
        {kind = .Glue, width = 10, break_allowed = true},
        {kind = .Box, width = 40},
    }

    candidate_result := document_optimal_break_with_limits(
        nodes[:], 0, {available = 70}, &candidate_lines,
        {candidates = 1, states = 16, work = 100})
    state_result := document_optimal_break_with_limits(
        nodes[:], 0, {available = 70}, &state_lines,
        {candidates = 4, states = 1, work = 100})

    testing.expect_value(t, candidate_result.fallback,
        Document_Break_Fallback.Candidate_Limit)
    testing.expect_value(t, state_result.fallback,
        Document_Break_Fallback.State_Limit)
    testing.expect_value(t, candidate_lines.count, state_lines.count)
    testing.expect_value(t, candidate_lines.storage[0], state_lines.storage[0])
}
