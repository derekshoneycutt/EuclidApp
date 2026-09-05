package ui

import "core:testing"

import app_core "../../core"
import app_bridge "../../bridge"

import rl "vendor:raylib"

//   Verify the baseline UI regions are valid and mutually consistent.
@(test)
ui_regions_baseline_is_valid_and_consistent :: proc(t: ^testing.T) {
    // Verifies baseline UI region construction is internally consistent and matches fixed panel sizing contracts.
    regions := compute_ui_regions(.Baseline)

    testing.expect(t, validate_ui_regions(regions))
    testing.expect_value(t, regions.world_rect.width, VIEW_WIDTH)
    testing.expect_value(t, regions.world_rect.height, VIEW_HEIGHT)
    testing.expect_value(
        t, regions.tree_rect.x, VIEW_WIDTH + TREE_PANEL_PADDING)
    testing.expect_value(
        t, regions.text_rect.y, VIEW_HEIGHT + TREE_PANEL_PADDING)
    testing.expect_value(t, regions.settings_rect.width, regions.gif_rect.width)
    testing.expect_value(t, regions.settings_rect.height, regions.gif_rect.height)
    testing.expect(t, regions.scratchpad_rect.width >= 0)
    testing.expect(t, regions.scratchpad_rect.height >= 0)
}

//   Verify UI region validation rejects negative dimensions.
@(test)
validate_ui_regions_rejects_negative_dimensions :: proc(t: ^testing.T) {
    // Ensures region validation fails when any panel rectangle has negative width or height.
    regions := app_core.Ui_Regions{}
    regions.world_rect = rl.Rectangle{0, 0, -1, 10}

    testing.expect(t, !validate_ui_regions(regions))

    regions.world_rect = rl.Rectangle{0, 0, 1, 10}
    regions.tree_rect = rl.Rectangle{0, 0, 10, -1}
    testing.expect(t, !validate_ui_regions(regions))
}

//   Verify the scrollbar thumb math clamps and positions correctly.
@(test)
scrollbar_thumb_math_clamps_and_positions_correctly :: proc(t: ^testing.T) {
    // Checks scrollbar thumb sizing and placement clamp correctly across top, bottom, and constructed panel geometry.
    thumb_h := scrollbar_thumb_height(100, 1000, 24)
    testing.expect(t, thumb_h >= 24)
    testing.expect(t, thumb_h <= 100)

    y_top := scrollbar_thumb_y(50, 100, thumb_h, 0, 300)
    y_bottom := scrollbar_thumb_y(50, 100, thumb_h, 300, 300)
    testing.expect_value(t, y_top, f32(50))
    testing.expect_value(t, y_bottom, f32(150) - thumb_h)

    panel := rl.Rectangle{10, 20, 200, 120}
    scrollbar := build_vertical_scrollbar(
        Vertical_Scrollbar_Input{panel, 480, 60, 360}, 8, 24)
    testing.expect(t, scrollbar.has_scrollbar)
    testing.expect_value(t, scrollbar.track_rect.x, panel.x + panel.width - 8)
    testing.expect_value(t, scrollbar.thumb_height, scrollbar.thumb_rect.height)
}

//   Seed one tree node with a name and optional children for testing.
seed_tree_node :: proc(
    node: ^app_core.Euclid_Julia_Animation_Interface,
    parent: ^app_core.Euclid_Julia_Animation_Interface,
    first_child: ^app_core.Euclid_Julia_Animation_Interface,
    next_sibling: ^app_core.Euclid_Julia_Animation_Interface,
    expanded: bool) {

    node^.parent = parent
    node^.first_child = first_child
    node^.next_sibling = next_sibling
    node^.is_expanded = expanded
}

//   Verify the tree row count respects each node's expansion state.
@(test)
tree_row_count_respects_expansion_state :: proc(t: ^testing.T) {
    // Verifies visible tree row counting respects node expansion state and first-child expansion helper behavior.
    ji := app_core.Euclid_Julia_Interface{}
    nodes: [3]app_core.Euclid_Julia_Animation_Interface
    ji.animation_head = &nodes[0]
    ji.animation_tail = &nodes[2]
    ji.animation_count = 3

    nodes[0].next_in_registry = &nodes[1]
    nodes[1].next_in_registry = &nodes[2]

    // root(0) -> child(1) -> sibling(2)
    seed_tree_node(&nodes[0], nil, &nodes[1], nil, true)
    seed_tree_node(&nodes[1], &nodes[0], nil, &nodes[2], false)
    seed_tree_node(&nodes[2], &nodes[0], nil, nil, false)

    count_expanded := count_visible_tree_rows_all_roots(&ji)
    testing.expect_value(t, count_expanded, 3)

    nodes[0].is_expanded = false
    count_collapsed := count_visible_tree_rows_all_roots(&ji)
    testing.expect_value(t, count_collapsed, 1)

    testing.expect_value(t, expanded_first_child(&nodes[1]), nil)
    nodes[0].is_expanded = true
    testing.expect_value(t, expanded_first_child(&nodes[0]), &nodes[1])
}

//   Verify tree row lookup follows visible depth-first order across roots.
@(test)
tree_visible_row_follows_draw_order :: proc(t: ^testing.T) {
    ji := app_core.Euclid_Julia_Interface{}
    nodes: [4]app_core.Euclid_Julia_Animation_Interface
    ji.animation_head = &nodes[0]
    ji.animation_count = len(nodes)
    for index in 0..<len(nodes) - 1 {
        nodes[index].next_in_registry = &nodes[index + 1]
    }
    seed_tree_node(&nodes[0], nil, &nodes[1], nil, true)
    seed_tree_node(&nodes[1], &nodes[0], nil, &nodes[2], false)
    seed_tree_node(&nodes[2], &nodes[0], nil, nil, false)
    seed_tree_node(&nodes[3], nil, nil, nil, false)

    row, found := tree_visible_row(&ji, &nodes[2])
    testing.expect(t, found)
    testing.expect_value(t, row, 2)
    row, found = tree_visible_row(&ji, &nodes[3])
    testing.expect(t, found)
    testing.expect_value(t, row, 3)

    nodes[0].is_expanded = false
    _, found = tree_visible_row(&ji, &nodes[2])
    testing.expect(t, !found)
}

//   Verify tree reveal scrolling moves only enough to expose the target row.
@(test)
tree_reveal_scroll_is_minimal_and_clamped :: proc(t: ^testing.T) {
    testing.expect_value(t, tree_reveal_scroll(44, 3, 66, 220), f32(44))
    testing.expect_value(t, tree_reveal_scroll(88, 2, 66, 220), f32(44))
    testing.expect_value(t, tree_reveal_scroll(0, 5, 66, 220), f32(66))
    testing.expect_value(t, tree_reveal_scroll(200, 0, 66, 220), f32(0))
    testing.expect_value(t, tree_reveal_scroll(30, 1, 100, 44), f32(0))
}

//   Verify a stable reveal request scrolls, cancels dragging, and is consumed.
@(test)
pending_tree_reveal_applies_display_state :: proc(t: ^testing.T) {
    ji := app_core.Euclid_Julia_Interface{}
    nodes: [2]app_core.Euclid_Julia_Animation_Interface
    ji.animation_head = &nodes[0]
    ji.animation_count = len(nodes)
    nodes[0].next_in_registry = &nodes[1]
    nodes[0].stable_id[0] = 1
    nodes[1].stable_id[0] = 2
    ui_runtime := app_core.Euclid_Ui_Runtime_State{
        tree_reveal_pending = true,
        tree_reveal_stable_id = nodes[1].stable_id,
        tree_scroll_dragging = true,
        tree_scroll_drag_off = 5,
        ui_press_owner = {active = true, kind = .Scrollbar, id = 1003},
    }
    scroll_y: f32
    apply_pending_tree_reveal(Tree_List_Params{
        ji = &ji,
        ui_runtime = &ui_runtime,
        list_panel = {height = TREE_ROW_HEIGHT},
        scroll_y = &scroll_y,
    }, TREE_ROW_HEIGHT * 2)

    testing.expect_value(t, scroll_y, TREE_ROW_HEIGHT)
    testing.expect(t, !ui_runtime.tree_reveal_pending)
    testing.expect(t, !ui_runtime.tree_scroll_dragging)
    testing.expect(t, !ui_runtime.ui_press_owner.active)

    ui_runtime.tree_reveal_pending = true
    ui_runtime.tree_reveal_stable_id[0] = 3
    apply_pending_tree_reveal(Tree_List_Params{
        ji = &ji,
        ui_runtime = &ui_runtime,
        list_panel = {height = TREE_ROW_HEIGHT},
        scroll_y = &scroll_y,
    }, TREE_ROW_HEIGHT * 2)
    testing.expect(t, ui_runtime.tree_reveal_pending)
}

//   Verify build_tree_view_panels clamps small panels to non-negative rects.
@(test)
build_tree_view_panels_clamps_small_panels :: proc(t: ^testing.T) {
    // Confirms tiny tree panels still produce a fixed-height toolbar and non-negative list viewport dimensions.
    panel := rl.Rectangle{0, 0, 8, 8}
    toolbar, list := build_tree_view_panels(panel)

    testing.expect(t, toolbar.height == TREE_TOOLBAR_HEIGHT)
    testing.expect(t, list.width >= 0)
    testing.expect(t, list.height >= 0)
}

//   Verify the input-box UTF-8 helpers preserve codepoint boundaries.
@(test)
input_box_utf8_helpers_preserve_codepoint_boundaries :: proc(t: ^testing.T) {
    // Ensures UTF-8 cursor movement, backspace, and replacement operations preserve codepoint boundaries.
    buffer: [32]u8
    text_len := 0
    caret := 0

    input_box_replace_text(buffer[:], &text_len, &caret, "αβ")
    testing.expect_value(t, text_len, len("αβ"))
    testing.expect_value(t, caret, len("αβ"))

    prev_start := input_box_prev_codepoint_start(buffer[:], 0, caret)
    testing.expect_value(t, prev_start, len("α"))

    input_box_backspace_codepoint(buffer[:], &text_len, &caret)
    testing.expect_value(t, string(buffer[:text_len]), "α")
    testing.expect_value(t, caret, len("α"))

    replaced := input_box_replace_byte_range(
        buffer[:],
        Input_Box_Edit_State{text_len = &text_len, caret = &caret},
        0,
        text_len,
        "γ")
    testing.expect(t, replaced)
    testing.expect_value(t, string(buffer[:text_len]), "γ")
    testing.expect_value(t, caret, len("γ"))
}

//   Verify the terminal input layout wraps multiline UTF-8 caret correctly.
@(test)
terminal_input_layout_wraps_multiline_utf8_caret :: proc(t: ^testing.T) {
    text := "abcd\nαβγδε"
    buffer := transmute([]u8)text

    first_wrap := terminal_input_position(buffer, len(text), 4, 4)
    second_line_caret := terminal_input_position(buffer, len(text), len(text), 4)

    testing.expect_value(t, first_wrap, Terminal_Input_Position{1, 0})
    testing.expect_value(t, second_line_caret, Terminal_Input_Position{2, 1})
    testing.expect_value(
        t, terminal_input_row_count(buffer, len(text), len(text), 4), 3)
}

//   Verify a terminal input cell maps to the correct UTF-8 byte caret.
@(test)
terminal_input_cell_maps_to_utf8_byte_caret :: proc(t: ^testing.T) {
    text := "abcd\nαβγδε"
    buffer := transmute([]u8)text

    caret := terminal_input_byte_offset_at(buffer, len(text), 4, 2, 1)

    testing.expect_value(t, caret, len(text))
}

//   Verify scratchpad bottom detection uses the terminal epsilon.
@(test)
scratchpad_bottom_detection_uses_terminal_epsilon :: proc(t: ^testing.T) {
    testing.expect(t, scratchpad_scroll_is_at_bottom(99.6, 100))
    testing.expect(t, !scratchpad_scroll_is_at_bottom(99.0, 100))
}

//   Verify a scratchpad completion payload parses and applies to the input.
@(test)
scratchpad_completion_payload_parses_and_applies :: proc(t: ^testing.T) {
    // Verifies completion payload parsing extracts start, end, and replacement text from the wire format.
    completion := scratchpad_parse_completion_payload("2\n5\npoint!")
    testing.expect(t, completion.ok)
    testing.expect_value(t, completion.replace_start, 2)
    testing.expect_value(t, completion.replace_end, 5)
    testing.expect_value(t, completion.replacement, "point!")
}

//   Verify scratchpad_parse_non_negative_int rejects non-digit input.
@(test)
scratchpad_parse_non_negative_int_rejects_non_digits :: proc(t: ^testing.T) {
    // Confirms non-digit characters invalidate scratchpad non-negative integer parsing.
    _, ok := scratchpad_parse_non_negative_int("12x")
    testing.expect(t, !ok)
}

//   Verify the scratchpad prompt tracks the active input mode.
@(test)
scratchpad_prompt_tracks_input_mode :: proc(t: ^testing.T) {
    testing.expect_value(t, scratchpad_prompt(.Julia), "julia> ")
    testing.expect_value(t, scratchpad_prompt(.Help), "help?> ")
}

//   Verify a history payload restores the mode and text.
@(test)
scratchpad_history_payload_restores_mode_and_text :: proc(t: ^testing.T) {
    history := scratchpad_parse_history_payload("1\n@time")
    testing.expect(t, history.ok)
    testing.expect_value(t, history.mode, app_core.Scratchpad_Input_Mode.Help)
    testing.expect_value(t, history.text, "@time")

    missing_separator := scratchpad_parse_history_payload("1@time")
    testing.expect(t, !missing_separator.ok)
    unknown_mode := scratchpad_parse_history_payload("2\n@time")
    testing.expect(t, !unknown_mode.ok)
}

//   Verify a typed question mark enters help mode.
@(test)
scratchpad_question_mark_enters_help_mode :: proc(t: ^testing.T) {
    ui_runtime := app_core.Euclid_Ui_Runtime_State{}
    input_box_replace_text(
        ui_runtime.scratchpad_input[:], &ui_runtime.scratchpad_input_len,
        &ui_runtime.scratchpad_input_cursor, "?")

    changed := apply_scratchpad_mode_transition(
        &ui_runtime, Input_Box_Result{}, 0, 0)

    testing.expect(t, changed)
    testing.expect_value(t, ui_runtime.scratchpad_input_mode,
        app_core.Scratchpad_Input_Mode.Help)
    testing.expect_value(t, ui_runtime.scratchpad_input_len, 0)
    testing.expect_value(t, ui_runtime.scratchpad_input_cursor, 0)
}

//   Verify a pasted question mark stays in Julia mode.
@(test)
scratchpad_pasted_question_mark_stays_in_julia_mode :: proc(t: ^testing.T) {
    ui_runtime := app_core.Euclid_Ui_Runtime_State{}
    input_box_replace_text(
        ui_runtime.scratchpad_input[:], &ui_runtime.scratchpad_input_len,
        &ui_runtime.scratchpad_input_cursor, "?")

    changed := apply_scratchpad_mode_transition(
        &ui_runtime, Input_Box_Result{paste_applied = true}, 0, 0)

    testing.expect(t, !changed)
    testing.expect_value(t, ui_runtime.scratchpad_input_mode,
        app_core.Scratchpad_Input_Mode.Julia)
    testing.expect_value(t, ui_runtime.scratchpad_input_len, 1)
}

//   Verify an empty backspace exits help mode.
@(test)
scratchpad_empty_backspace_exits_help_mode :: proc(t: ^testing.T) {
    ui_runtime := app_core.Euclid_Ui_Runtime_State{scratchpad_input_mode = .Help}

    changed := apply_scratchpad_mode_transition(
        &ui_runtime, Input_Box_Result{backspace_pressed = true}, 0, 0)

    testing.expect(t, changed)
    testing.expect_value(t, ui_runtime.scratchpad_input_mode,
        app_core.Scratchpad_Input_Mode.Julia)
}

//   Seed one scratchpad async result slot for testing.
seed_scratchpad_async_result :: proc(
    slot: ^app_bridge.Scratchpad_Async_Slot, text: string) {

    slot^.result_len = len(text)
    copy(slot^.result[:slot^.result_len], transmute([]u8)text)
}

//   Verify a stale submit preserves the newer input text.
@(test)
scratchpad_stale_submit_preserves_newer_input :: proc(t: ^testing.T) {
    ui_runtime := app_core.Euclid_Ui_Runtime_State{}
    input_box_replace_text(
        ui_runtime.scratchpad_input[:], &ui_runtime.scratchpad_input_len,
        &ui_runtime.scratchpad_input_cursor, "new input")
    ui_runtime.scratchpad_input_generation = 2
    ui_runtime.scratchpad_pending_submit_request_id = 9
    slot := app_bridge.Scratchpad_Async_Slot{
        kind = .Submit,
        request_id = 9,
        input_generation = 1,
        parse_result = app_bridge.SCRATCHPAD_PARSE_COMPLETE,
        succeeded = true,
    }

    apply_scratchpad_async_result(&ui_runtime, &slot)

    testing.expect_value(
        t, string(ui_runtime.scratchpad_input[:ui_runtime.scratchpad_input_len]),
        "new input")
    testing.expect_value(t, ui_runtime.scratchpad_pending_submit_request_id, u64(0))
}

//   Verify only the matching submit reply releases scenario-forced bottom pinning.
@(test)
scratchpad_forced_bottom_requires_matching_submit_reply :: proc(t: ^testing.T) {
    ui_runtime := app_core.Euclid_Ui_Runtime_State{
        scratchpad_input_generation = 2,
        scratchpad_forced_bottom_request_id = 9,
    }
    unrelated := app_bridge.Scratchpad_Async_Slot{
        kind = .Complete,
        request_id = 9,
        input_generation = 2,
    }
    apply_scratchpad_async_result(&ui_runtime, &unrelated)
    testing.expect_value(t, ui_runtime.scratchpad_forced_bottom_request_id, u64(9))

    stale_submit := app_bridge.Scratchpad_Async_Slot{
        kind = .Submit,
        request_id = 9,
        input_generation = 1,
    }
    apply_scratchpad_async_result(&ui_runtime, &stale_submit)
    testing.expect_value(t, ui_runtime.scratchpad_forced_bottom_request_id, u64(0))
    testing.expect(t, ui_runtime.scratchpad_bottom_pinned)
}

//   Verify the zero request sentinel cannot force ordinary submit scrolling.
@(test)
scratchpad_zero_request_does_not_force_bottom :: proc(t: ^testing.T) {
    ui_runtime := app_core.Euclid_Ui_Runtime_State{}
    slot := app_bridge.Scratchpad_Async_Slot{kind = .Submit}

    apply_scratchpad_async_result(&ui_runtime, &slot)

    testing.expect(t, !ui_runtime.scratchpad_bottom_pinned)
    testing.expect_value(t, ui_runtime.scratchpad_forced_bottom_request_id, u64(0))
}

//   Verify changed Scratchpad output moves a pinned transcript to its new bottom.
@(test)
scratchpad_output_growth_repins_to_bottom :: proc(t: ^testing.T) {
    state := new(app_core.Euclid_General_State)
    defer free(state)
    ui_runtime := &state^.ui_runtime
    ui_runtime.scratchpad_bottom_pinned = true
    ui_runtime.scratchpad_last_output_len = 4

    scratchpad_track_output_length(state, ui_runtime, 12, 88)

    testing.expect_value(t, state^.ui_runtime.view_text_scroll_y, f32(88))
    testing.expect_value(t, ui_runtime.scratchpad_last_output_len, 12)
}

//   Verify an incomplete submit appends a trailing newline.
@(test)
scratchpad_incomplete_submit_appends_newline :: proc(t: ^testing.T) {
    ui_runtime := app_core.Euclid_Ui_Runtime_State{}
    input_box_replace_text(
        ui_runtime.scratchpad_input[:], &ui_runtime.scratchpad_input_len,
        &ui_runtime.scratchpad_input_cursor, "begin")
    ui_runtime.scratchpad_input_generation = 4
    slot := app_bridge.Scratchpad_Async_Slot{
        kind = .Submit,
        input_generation = 4,
        parse_result = app_bridge.SCRATCHPAD_PARSE_INCOMPLETE,
    }

    apply_scratchpad_async_result(&ui_runtime, &slot)

    testing.expect_value(
        t, string(ui_runtime.scratchpad_input[:ui_runtime.scratchpad_input_len]),
        "begin\n")
    testing.expect_value(t, ui_runtime.scratchpad_input_generation, u64(5))
}

//   Verify a completion only applies to the latest request generation.
@(test)
scratchpad_completion_requires_latest_request :: proc(t: ^testing.T) {
    ui_runtime := app_core.Euclid_Ui_Runtime_State{}
    input_box_replace_text(
        ui_runtime.scratchpad_input[:], &ui_runtime.scratchpad_input_len,
        &ui_runtime.scratchpad_input_cursor, "EuclidRep")
    ui_runtime.scratchpad_input_generation = 3
    ui_runtime.scratchpad_latest_completion_request_id = 12
    stale_slot := app_bridge.Scratchpad_Async_Slot{
        kind = .Complete, request_id = 11, input_generation = 3}
    seed_scratchpad_async_result(&stale_slot, "0\n9\nEuclidREPL")
    latest_slot := app_bridge.Scratchpad_Async_Slot{
        kind = .Complete, request_id = 12, input_generation = 3}
    seed_scratchpad_async_result(&latest_slot, "0\n9\nEuclidREPL")

    apply_scratchpad_async_result(&ui_runtime, &stale_slot)
    testing.expect_value(
        t, string(ui_runtime.scratchpad_input[:ui_runtime.scratchpad_input_len]),
        "EuclidRep")

    apply_scratchpad_async_result(&ui_runtime, &latest_slot)
    testing.expect_value(
        t, string(ui_runtime.scratchpad_input[:ui_runtime.scratchpad_input_len]),
        "EuclidREPL")
    testing.expect_value(t, ui_runtime.scratchpad_input_generation, u64(4))
}

//   Verify backspace removes a multibyte codepoint at the cursor.
@(test)
input_box_backspace_codepoint_removes_multibyte_cursor :: proc(t: ^testing.T) {
    // Checks backspace removes one full multibyte codepoint and updates caret to the previous codepoint start.
    buffer: [8]u8
    text_len := 0
    caret := 0

    input_box_replace_text(buffer[:], &text_len, &caret, "αβ")
    caret = text_len
    input_box_backspace_codepoint(buffer[:], &text_len, &caret)

    testing.expect_value(t, string(buffer[:text_len]), "α")
    testing.expect_value(t, caret, 2)
}

//   Verify the tree row-count guard stops recursive walks.
@(test)
tree_row_count_guard_stops_recursive_walks :: proc(t: ^testing.T) {
    // Verifies row counting guard limits recursive traversal depth to prevent runaway tree walks.
    ji := app_core.Euclid_Julia_Interface{}
    nodes: [2]app_core.Euclid_Julia_Animation_Interface
    ji.animation_head = &nodes[0]
    ji.animation_tail = &nodes[1]
    ji.animation_count = 2

    nodes[0].next_in_registry = &nodes[1]

    seed_tree_node(&nodes[0], nil, &nodes[1], nil, true)
    seed_tree_node(&nodes[1], &nodes[0], nil, nil, true)

    testing.expect_value(t, count_visible_tree_rows_limited(&ji, &nodes[0], 1), 1)
}

//   Verify insert_text_at_caret inserts in the middle of existing text.
@(test)
input_box_insert_text_at_caret_inserts_in_middle :: proc(t: ^testing.T) {
    // Ensures inserting text at an interior caret position shifts existing bytes and advances caret correctly.
    buffer: [32]u8
    text_len := 0
    caret := 0

    input_box_replace_text(buffer[:], &text_len, &caret, "ab")
    caret = 1

    inserted := input_box_insert_text_at_caret(
        buffer[:],
        &text_len,
        &caret,
        "XYZ")

    testing.expect(t, inserted)
    testing.expect_value(t, string(buffer[:text_len]), "aXYZb")
    testing.expect_value(t, caret, 4)
}

//   Verify insert_text_at_caret truncates on a UTF-8 boundary at capacity.
@(test)
input_box_insert_text_at_caret_truncates_on_utf8_boundary :: proc(t: ^testing.T) {
    // Validates insertion truncates safely at UTF-8 boundaries when destination capacity is limited.
    buffer: [5]u8
    text_len := 0
    caret := 0

    input_box_replace_text(buffer[:], &text_len, &caret, "ab")

    inserted := input_box_insert_text_at_caret(
        buffer[:],
        &text_len,
        &caret,
        "αβ")

    testing.expect(t, inserted)
    testing.expect_value(t, string(buffer[:text_len]), "abα")
    testing.expect_value(t, text_len, len("abα"))
    testing.expect_value(t, caret, len("abα"))
}

//   Verify insert_text_at_caret is a no-op when there is no capacity.
@(test)
input_box_insert_text_at_caret_noop_when_no_capacity :: proc(t: ^testing.T) {
    // Confirms insertion is rejected without mutating text when there is no remaining buffer capacity.
    buffer: [2]u8
    text_len := 0
    caret := 0

    input_box_replace_text(buffer[:], &text_len, &caret, "ab")

    inserted := input_box_insert_text_at_caret(
        buffer[:],
        &text_len,
        &caret,
        "Z")

    testing.expect(t, !inserted)
    testing.expect_value(t, string(buffer[:text_len]), "ab")
    testing.expect_value(t, text_len, 2)
    testing.expect_value(t, caret, 2)
}

//   Verify byte-range replacement swaps UTF-8 content and moves the caret.
@(test)
input_box_replace_byte_range_supports_utf8_safe_replacement :: proc(t: ^testing.T) {
    // Checks byte-range replacement swaps UTF-8 content and repositions caret to the end of replacement text.
    buffer: [16]u8
    text_len := 0
    caret := 0

    input_box_replace_text(buffer[:], &text_len, &caret, "αβ")
    replaced := input_box_replace_byte_range(
        buffer[:],
        Input_Box_Edit_State{text_len = &text_len, caret = &caret},
        0,
        text_len,
        "γ")

    testing.expect(t, replaced)
    testing.expect_value(t, string(buffer[:text_len]), "γ")
    testing.expect_value(t, caret, len("γ"))
}

//   Verify a completion payload rejects a missing separator.
@(test)
scratchpad_completion_payload_rejects_missing_separator :: proc(t: ^testing.T) {
    // Verifies malformed completion payloads without all required separators are rejected.
    invalid_completion := scratchpad_parse_completion_payload("1\n2")
    testing.expect(t, !invalid_completion.ok)
}

