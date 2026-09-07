package dynview_layout

import app_core "../../core"
import "core:mem"
import "core:testing"

// Initialize bounded line storage for measured greedy tests.
document_greedy_test_lines :: proc(
    t: ^testing.T,
    arena: ^app_core.Arena_Owner) ->
        app_core.Bounded_Element_Builder(app_core.Dynview_Document_Layout_Line) {

    testing.expect(t, app_core.arena_owner_init(arena, 64*uint(mem.Kilobyte)))
    builder: app_core.Bounded_Element_Builder(
        app_core.Dynview_Document_Layout_Line)
    testing.expect_value(t, app_core.bounded_element_builder_init(
        &builder, app_core.DYNVIEW_MAX_DOCUMENT_LAYOUT_LINES, arena),
        app_core.Bounded_Builder_Status.Ok)
    return builder
}

// Verify shaped widths choose the last legal breakpoint that fits.
@(test)
document_greedy_breaks_at_last_fitting_glue :: proc(t: ^testing.T) {
    arena: app_core.Arena_Owner
    lines := document_greedy_test_lines(t, &arena)
    defer app_core.arena_owner_destroy(&arena)
    nodes := [5]app_core.Dynview_Document_Layout_Node{
        {kind = .Box, width = 40},
        {kind = .Glue, width = 5, break_allowed = true},
        {kind = .Box, width = 70},
        {kind = .Glue, width = 5, break_allowed = true},
        {kind = .Box, width = 20},
    }

    status := document_greedy_break(nodes[:], 3, 100, &lines)

    testing.expect_value(t, status, app_core.Bounded_Builder_Status.Ok)
    testing.expect_value(t, lines.count, 2)
    testing.expect_value(t, lines.storage[0].node_start, 0)
    testing.expect_value(t, lines.storage[0].node_count, 1)
    testing.expect_value(t, lines.storage[0].width, f32(40))
    testing.expect_value(t, lines.storage[1].node_start, 2)
    testing.expect_value(t, lines.storage[1].width, f32(95))
}

// Verify one atomic box wider than the measure becomes an explicit overfull line.
@(test)
document_greedy_marks_oversized_box_overfull :: proc(t: ^testing.T) {
    arena: app_core.Arena_Owner
    lines := document_greedy_test_lines(t, &arena)
    defer app_core.arena_owner_destroy(&arena)
    nodes := [1]app_core.Dynview_Document_Layout_Node{{kind = .Box, width = 140}}

    status := document_greedy_break(nodes[:], 0, 100, &lines)

    testing.expect_value(t, status, app_core.Bounded_Builder_Status.Ok)
    testing.expect_value(t, lines.count, 1)
    testing.expect(t, lines.storage[0].overfull)
    testing.expect_value(t, lines.storage[0].width, f32(140))
}

// Verify nonbreaking glue keeps adjacent boxes together on one overfull line.
@(test)
document_greedy_preserves_nonbreaking_sequences :: proc(t: ^testing.T) {
    arena: app_core.Arena_Owner
    lines := document_greedy_test_lines(t, &arena)
    defer app_core.arena_owner_destroy(&arena)
    nodes := [3]app_core.Dynview_Document_Layout_Node{
        {kind = .Box, width = 40},
        {kind = .Glue, width = 10, break_allowed = false},
        {kind = .Box, width = 40},
    }

    status := document_greedy_break(nodes[:], 0, 70, &lines)

    testing.expect_value(t, status, app_core.Bounded_Builder_Status.Ok)
    testing.expect_value(t, lines.count, 1)
    testing.expect_value(t, lines.storage[0].node_count, 3)
    testing.expect_value(t, lines.storage[0].width, f32(90))
    testing.expect(t, lines.storage[0].overfull)
}

// Verify an explicit forced break terminates the current measured line.
@(test)
document_greedy_honors_forced_breaks :: proc(t: ^testing.T) {
    arena: app_core.Arena_Owner
    lines := document_greedy_test_lines(t, &arena)
    defer app_core.arena_owner_destroy(&arena)
    nodes := [3]app_core.Dynview_Document_Layout_Node{
        {kind = .Box, width = 20},
        {kind = .Forced_Break, break_allowed = true},
        {kind = .Box, width = 30},
    }

    status := document_greedy_break(nodes[:], 3, 100, &lines)

    testing.expect_value(t, status, app_core.Bounded_Builder_Status.Ok)
    testing.expect_value(t, lines.count, 2)
    testing.expect_value(t, lines.storage[0].node_count, 1)
    testing.expect_value(t, lines.storage[1].node_start, 2)
    testing.expect_value(t, lines.storage[1].block_index, 3)
}