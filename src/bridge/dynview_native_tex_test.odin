package bridge

import "core:testing"
import "core:os"
import "../core"
import dyncore "../dynview/core"
import dyncompile "../dynview/compile"

//   Verify the C ABI classifier preserves native document-mode decisions.
@(test)
dynview_tex_source_mode_classifies_scratchpad_document :: proc(t: ^testing.T) {
    testing.expect_value(t, dynview_tex_source_mode(
        "\\textbf{Definition}\\newline A point has no part."), i32(1))
}

//   Verify raw math is interned once and copied independently into snapshot staging.
@(test)
dynview_native_math_source_survives_animation_reset :: proc(t: ^testing.T) {
    state := animation_value_test_state_create(31)
    testing.expect(t, state != nil)
    defer animation_value_test_state_destroy(state)
    state.saved_context = context
    state.dynview.enabled = true
    state.dynview.command_buffer.stream_open_block = true
    state.dynview.command_buffer.stream_open_block_id = 7

    request := Bridge_Dynview_Math_Request{
        source = "x^2",
        text_style = BRIDGE_DYNVIEW_STYLE_OUTPUT,
        math_style = BRIDGE_DYNVIEW_STYLE_ITALIC,
        mathbb_style = BRIDGE_DYNVIEW_STYLE_CUSTOM_FONT |
            BRIDGE_DYNVIEW_FONT_FLAG_REGULAR,
        root_style = BRIDGE_DYNVIEW_MATH_ROOT_DISPLAY,
    }
    testing.expect_value(t, dynview_math_block(state, request),
        i32(BRIDGE_STATUS_OK))
    before := dyncore.document_store_diagnostics(&state.dynview_documents)
    testing.expect_value(t, dynview_math_block(state, request),
        i32(BRIDGE_STATUS_OK))
    after := dyncore.document_store_diagnostics(&state.dynview_documents)
    testing.expect_value(t, after.entry_count, 1)
    testing.expect_value(t, after.intern_hits, before.intern_hits + 1)
    testing.expect_value(t, state.dynview.compile_cache.math_program_count, 6)
    testing.expect_value(t, state.dynview.command_buffer.command_count, 2)

    copied := string(state.dynview.command_buffer.text_bytes[
        :state.dynview.command_buffer.text_bytes_len])
    core.dynview_document_store_clear_generation(&state.dynview_documents)
    testing.expect_value(t, core.animation_memory_begin_generation(
        &state.animation_memory, 32), core.Animation_Memory_Status.Ok)
    core.dynview_document_store_publish_generation(
        &state.dynview_documents, &state.animation_memory, 32)
    testing.expect(t, len(copied) > 0)
    testing.expect_value(t, state.dynview.command_buffer.command_count, 2)
}

//   Verify mixed native document runs preserve ordering, styles, and display breaks.
@(test)
dynview_native_document_replays_mixed_runs :: proc(t: ^testing.T) {
    state := animation_value_test_state_create(41)
    testing.expect(t, state != nil)
    defer animation_value_test_state_destroy(state)
    state.saved_context = context
    state.dynview.enabled = true
    status := dynview_tex_document(state, {
        source = "\\textbf{Title} plain $x^2$ $$y$$",
        fallback = "fallback",
        block_kind = BRIDGE_DYNVIEW_BLOCK_OUTPUT,
        block_id = 9,
        text_style = BRIDGE_DYNVIEW_STYLE_OUTPUT,
    })

    testing.expect_value(t, status, i32(BRIDGE_STATUS_OK))
    testing.expect(t, !state.dynview.command_buffer.has_stream_error)
    testing.expect(t, !state.dynview.command_buffer.stream_open_block)
    testing.expect_value(t, state.dynview.command_buffer.commands[0].kind,
        core.Dynview_Command_Kind.Begin_Block)
    testing.expect_value(t, state.dynview.command_buffer.commands[1].kind,
        core.Dynview_Command_Kind.Copyable_Text_Run)
    count := state.dynview.command_buffer.command_count
    testing.expect_value(t, state.dynview.command_buffer.commands[count-1].kind,
        core.Dynview_Command_Kind.End_Block)
    testing.expect(t, state.dynview.compile_cache.math_program_count > 0)
    testing.expect_value(t, state.dynview.compile_cache.document_count, 1)
    testing.expect_value(t, state.dynview.compile_cache.document_block_count, 2)
    testing.expect(t, state.dynview.compile_cache.document_inline_count > 0)
}

//   Verify document import publishes semantics without legacy render commands.
@(test)
dynview_native_document_publishes_authoritative_semantics :: proc(t: ^testing.T) {
    state := animation_value_test_state_create(42)
    testing.expect(t, state != nil)
    defer animation_value_test_state_destroy(state)
    state.saved_context = context
    state.dynview.enabled = true
    source := "First line with tall inline math $\\dfrac{a}{b}$ and a shape\n" +
        "\\euclidcircle[color=steelblue,size=2].\n" +
        "Second source line, same paragraph.\n\n" +
        "Second paragraph before a display.\n" +
        "\\[\\sum_{i=1}^{n} i = \\frac{n(n+1)}{2}\\]\n" +
        "Final paragraph."
    status := dynview_tex_document(state, {
        source = cstring(raw_data(source)),
        fallback = "composition fallback",
        block_kind = BRIDGE_DYNVIEW_BLOCK_OUTPUT,
        block_id = 17,
        text_style = BRIDGE_DYNVIEW_STYLE_OUTPUT,
    })

    testing.expect_value(t, status, i32(BRIDGE_STATUS_OK))
    testing.expect_value(t, state.dynview.command_buffer.command_count, 3)
    expected_kinds := [?]core.Dynview_Command_Kind{
        .Begin_Block, .Copyable_Text_Run, .End_Block,
    }
    for command, index in state.dynview.command_buffer.commands[
        :state.dynview.command_buffer.command_count] {
        testing.expect_value(t, command.kind, expected_kinds[index])
    }
    cache := &state.dynview.compile_cache
    testing.expect_value(t, cache^.document_count, 1)
    testing.expect_value(t, cache^.document_block_count, 4)
    testing.expect(t, cache^.document_inline_count > 0)
    testing.expect_value(t, cache^.math_program_count, 11)
}

// Verify group animation documents survive bridge import without fallback staging.
@(test)
dynview_native_group_documents_publish_semantics :: proc(t: ^testing.T) {
    inverse := "\\textbf{Inverse}\n\nAn inverse is the motion that undoes a given " +
        "motion. In $\\mathbb{Z}_2$, every element is its own inverse. That means " +
        "each motion undoes itself when applied again. This is common for reflections " +
        "across a stable line.\n\nFor an element $a$ in a group, an inverse $a^{-1}$ " +
        "is an element such that\n$a \\circ a^{-1} = a^{-1} \\circ a = e$, where " +
        "$e$ is the identity.\n\n1. $e^{-1} = e$: doing nothing undoes itself.\\\\\n" +
        "2. $r^{-1} = r$: one reflection undoes itself because reflecting twice " +
        "gives back the original figure."
    associative := "\\textbf{Associativity}\n\nAssociativity means the grouping " +
        "of the operation does not matter:\n\n$$(a \\circ b) \\circ c = a \\circ " +
        "(b \\circ c)\\; \\text{for all}\\; a,b,c$$\n\nHere, compare the two " +
        "ways of grouping the same three rotations.\n\n\\textbf{1.} Left grouping: " +
        "$(\\rho^1\\rho^2)\\rho^3 = \\rho^6$.\\\\\n\\textbf{2.} Right grouping: " +
        "$\\rho^1(\\rho^2\\rho^3) = \\rho^6$."
    sources := [?]string{inverse, associative}
    for source, index in sources {
        state := animation_value_test_state_create(u64(70+index))
        testing.expect(t, state != nil)
        state.saved_context = context
        state.dynview.enabled = true

        status := dynview_tex_document(state, {
            source = cstring(raw_data(source)), fallback = "fallback",
            block_kind = BRIDGE_DYNVIEW_BLOCK_OUTPUT, block_id = 1,
            text_style = BRIDGE_DYNVIEW_STYLE_OUTPUT,
        })

        testing.expect_value(t, status, i32(BRIDGE_STATUS_OK))
        testing.expect_value(t, state.dynview.compile_cache.document_count, 1)
        animation_value_test_state_destroy(state)
    }
}

// Verify technical display rows receive stable document-local equation numbers.
@(test)
dynview_native_document_numbers_technical_display_rows :: proc(t: ^testing.T) {
    state := animation_value_test_state_create(44)
    testing.expect(t, state != nil)
    defer animation_value_test_state_destroy(state)
    state.saved_context = context
    state.dynview.enabled = true
    source := "\\begin{equation}x=1\\end{equation}" +
        "\\begin{align}a&=b\\\\c&=d\\notag\\end{align}" +
        "\\begin{gather*}u=1\\\\v=2\\end{gather*}" +
        "\\begin{multline}p\\\\q\\end{multline}"

    status := dynview_tex_document(state, {
        source = cstring(raw_data(source)), fallback = "fallback",
        block_kind = BRIDGE_DYNVIEW_BLOCK_OUTPUT, block_id = 18,
        text_style = BRIDGE_DYNVIEW_STYLE_OUTPUT,
    })
    cache := &state.dynview.compile_cache

    testing.expect_value(t, status, i32(BRIDGE_STATUS_OK))
    testing.expect_value(t, cache^.document_display_row_count, 7)
    expected := [?]int{1, 2, 0, 0, 0, 0, 3}
    for row, index in cache^.document_display_rows[
        :cache^.document_display_row_count] {
        testing.expect_value(t, row.number, expected[index])
        testing.expect(t, row.primary_program_id >= 0)
    }
}

//   Verify rejected document semantics roll back while retaining a closable fallback.
@(test)
dynview_native_document_failure_preserves_fallback :: proc(t: ^testing.T) {
    state := animation_value_test_state_create(42)
    testing.expect(t, state != nil)
    defer animation_value_test_state_destroy(state)
    state.saved_context = context
    state.dynview.enabled = true

    status := dynview_tex_document(state, {
        source = "broken $math",
        fallback = "authored fallback",
        block_kind = BRIDGE_DYNVIEW_BLOCK_OUTPUT,
        block_id = 10,
        text_style = BRIDGE_DYNVIEW_STYLE_OUTPUT,
    })

    testing.expect_value(t, status, i32(BRIDGE_STATUS_INVALID_ARGUMENT))
    testing.expect(t, !state.dynview.command_buffer.has_stream_error)
    testing.expect(t, !state.dynview.command_buffer.stream_open_block)
    testing.expect_value(t, state.dynview.command_buffer.command_count, 4)
    testing.expect_value(t, state.dynview.command_buffer.commands[1].kind,
        core.Dynview_Command_Kind.Copyable_Text_Run)
    testing.expect_value(t, state.dynview.command_buffer.commands[2].kind,
        core.Dynview_Command_Kind.Text_Run)
    testing.expect_value(t, state.dynview.compile_cache.math_program_count, 0)
    testing.expect_value(t, state.dynview.compile_cache.document_text_count, 0)
    testing.expect_value(t, state.dynview.compile_cache.document_count, 0)
    testing.expect_value(t, state.dynview.compile_cache.document_block_count, 0)
    testing.expect_value(t, state.dynview.compile_cache.document_inline_count, 0)
}

//   Verify copied semantic aliases remain valid and install directly after reset.
dynview_native_expect_snapshot_semantics :: proc(
    t: ^testing.T,
    slot: ^View_Snapshot,
    runtime: ^core.Dynview_System,
    document: core.Dynview_Document,
    copied_source: string) {

    testing.expect_value(t, string(slot.document_text[
        document.source_offset:document.source_offset + document.source_count]),
        copied_source)
    testing.expect(t, len(slot.document_blocks) > 0)
    testing.expect(t, len(slot.document_inlines) > 0)
    testing.expect(t, view_snapshot_is_valid(slot))
    install_view_snapshot_content(slot, runtime)
    testing.expect_value(t,
        raw_data(runtime.content.documents), raw_data(slot.documents))
    testing.expect_value(t,
        raw_data(runtime.content.document_blocks), raw_data(slot.document_blocks))
    testing.expect_value(t,
        raw_data(runtime.content.document_inlines), raw_data(slot.document_inlines))
}

//   Verify a sealed native document snapshot remains valid after animation reset.
@(test)
dynview_native_document_snapshot_survives_animation_reset :: proc(t: ^testing.T) {
    state := animation_value_test_state_create(43)
    testing.expect(t, state != nil)
    defer animation_value_test_state_destroy(state)
    state.saved_context = context
    state.dynview.enabled = true
    testing.expect_value(t, dynview_tex_document(state, {
        source = "text $x^2$",
        fallback = "fallback",
        block_kind = BRIDGE_DYNVIEW_BLOCK_OUTPUT,
        block_id = 11,
        text_style = BRIDGE_DYNVIEW_STYLE_OUTPUT,
    }), i32(BRIDGE_STATUS_OK))
    service := view_snapshot_arena_test_service(t)
    defer view_snapshot_arena_test_service_destroy(service)
    slot := &service.view_snapshots[0]
    testing.expect(t, prepare_view_snapshot_slot(slot))
    testing.expect(t, build_generated_view_snapshot_payloads(
        slot, &state.dynview, "fallback"))
    testing.expect(t, view_snapshot_is_valid(slot))
    command_text := string(slot.command_text)
    command_count := len(slot.commands)
    testing.expect_value(t, len(slot.documents), 1)
    document := slot.documents[0]
    copied_source := string(slot.document_text[
        document.source_offset:document.source_offset + document.source_count])
    testing.expect_value(t, copied_source, "text $x^2$")

    core.dynview_document_store_clear_generation(&state.dynview_documents)
    testing.expect_value(t, core.animation_memory_begin_generation(
        &state.animation_memory, 44), core.Animation_Memory_Status.Ok)
    core.dynview_document_store_publish_generation(
        &state.dynview_documents, &state.animation_memory, 44)

    testing.expect_value(t, string(slot.command_text), command_text)
    testing.expect_value(t, len(slot.commands), command_count)
    dynview_native_expect_snapshot_semantics(
        t, slot, &state.dynview, document, copied_source)
}

//   Verify the document facade classifies and strips complete inline math natively.
@(test)
dynview_native_document_classifies_whole_inline_math :: proc(t: ^testing.T) {
    state := animation_value_test_state_create(45)
    testing.expect(t, state != nil)
    defer animation_value_test_state_destroy(state)
    state.saved_context = context
    state.dynview.enabled = true
    request := Bridge_Dynview_Document_Request{
        source = "  $x^2$  ",
        fallback = "x squared",
        block_kind = BRIDGE_DYNVIEW_BLOCK_OUTPUT,
        block_id = 12,
        text_style = BRIDGE_DYNVIEW_STYLE_OUTPUT,
    }

    testing.expect_value(t, dynview_tex_document(state, request),
        i32(BRIDGE_STATUS_OK))
    diagnostics := dyncore.document_store_diagnostics(&state.dynview_documents)
    testing.expect_value(t, diagnostics.entry_count, 1)
    testing.expect_value(t, state.dynview.compile_cache.math_program_count, 4)
    command := state.dynview.command_buffer.commands[2]
    testing.expect_value(t, command.kind, core.Dynview_Command_Kind.Math_Block)
    root := &state.dynview.compile_cache.math_programs[command.math_program_id]
    root_command := state.dynview.compile_cache.math_commands[root.command_start]
    testing.expect_value(t, root_command.kind,
        core.Dynview_Command_Kind.Style_Override)
    testing.expect_value(t, root_command.radical_mode,
        i32(core.Dynview_Math_Style_Level.Text))
}

//   Verify explicit raw-math root style and presentation metadata reach native import.
@(test)
dynview_native_math_request_preserves_styles :: proc(t: ^testing.T) {
    state := animation_value_test_state_create(46)
    testing.expect(t, state != nil)
    defer animation_value_test_state_destroy(state)
    state.saved_context = context
    state.dynview.enabled = true
    state.dynview.command_buffer.stream_open_block = true
    state.dynview.command_buffer.stream_open_block_id = 13
    request := Bridge_Dynview_Math_Request{
        source = "\\text{word}+x",
        text_style = BRIDGE_DYNVIEW_STYLE_ERROR,
        math_style = BRIDGE_DYNVIEW_STYLE_MEDIUM,
        mathbb_style = BRIDGE_DYNVIEW_STYLE_BOLD,
        root_style = BRIDGE_DYNVIEW_MATH_ROOT_TEXT,
    }

    testing.expect_value(t, dynview_math_block(state, request),
        i32(BRIDGE_STATUS_OK))
    command := state.dynview.command_buffer.commands[0]
    testing.expect_value(t, command.style_id, i32(BRIDGE_DYNVIEW_STYLE_MEDIUM))
    root := &state.dynview.compile_cache.math_programs[command.math_program_id]
    root_command := state.dynview.compile_cache.math_commands[root.command_start]
    testing.expect_value(t, root_command.kind,
        core.Dynview_Command_Kind.Style_Override)
}

//   Verify blackboard-bold operations retain the request's dedicated style.
@(test)
dynview_native_math_preserves_mathbb_style :: proc(t: ^testing.T) {
    state := animation_value_test_state_create(48)
    testing.expect(t, state != nil)
    defer animation_value_test_state_destroy(state)
    state.saved_context = context
    state.dynview.enabled = true
    state.dynview.command_buffer.stream_open_block = true
    request := Bridge_Dynview_Math_Request{
        source = "\\mathbb{R}",
        text_style = BRIDGE_DYNVIEW_STYLE_OUTPUT,
        math_style = BRIDGE_DYNVIEW_STYLE_MEDIUM,
        mathbb_style = BRIDGE_DYNVIEW_STYLE_BOLD,
    }
    testing.expect_value(t, dynview_math_block(state, request),
        i32(BRIDGE_STATUS_OK))
    block := state.dynview.command_buffer.commands[0]
    program := &state.dynview.compile_cache.math_programs[block.math_program_id]
    command := state.dynview.compile_cache.math_commands[program.command_start]
    testing.expect_value(t, command.style_id, i32(BRIDGE_DYNVIEW_STYLE_BOLD))
}

//   Verify native large-operator scripts occupy the renderer's sup/sub program slots.
@(test)
dynview_native_math_maps_large_operator_script_programs :: proc(t: ^testing.T) {
    state := animation_value_test_state_create(48)
    testing.expect(t, state != nil)
    defer animation_value_test_state_destroy(state)
    state.saved_context = context
    state.dynview.enabled = true
    state.dynview.command_buffer.stream_open_block = true
    request := Bridge_Dynview_Math_Request{
        source = "\\sum_i+\\lim_{x\\to0}+\\int_0^1",
        text_style = BRIDGE_DYNVIEW_STYLE_OUTPUT,
        math_style = BRIDGE_DYNVIEW_STYLE_ITALIC,
        mathbb_style = BRIDGE_DYNVIEW_STYLE_BOLD,
    }
    testing.expect_value(t,
        dynview_math_block(state, request), i32(BRIDGE_STATUS_OK))
    block := state.dynview.command_buffer.commands[0]
    root := &state.dynview.compile_cache.math_programs[block.math_program_id]
    sum := state.dynview.compile_cache.math_commands[root.command_start]
    limit := state.dynview.compile_cache.math_commands[root.command_start + 2]
    integral := state.dynview.compile_cache.math_commands[root.command_start + 4]
    testing.expect_value(t, sum.secondary_math_program_id, i32(0))
    testing.expect(t, sum.tertiary_math_program_id > 0)
    testing.expect_value(t, limit.secondary_math_program_id, i32(0))
    testing.expect(t, limit.tertiary_math_program_id > 0)
    testing.expect(t, integral.secondary_math_program_id > 0)
    testing.expect(t, integral.tertiary_math_program_id > 0)
}

//   Verify complex Scratchpad math can be imported twice into one staging stream.
@(test)
dynview_native_math_repeats_reported_formula :: proc(t: ^testing.T) {
    state := animation_value_test_state_create(49)
    testing.expect(t, state != nil)
    defer animation_value_test_state_destroy(state)
    state.saved_context = context
    state.dynview.enabled = true
    state.dynview.command_buffer.stream_open_block = true
    formulas := [?]cstring{
        "\\sum_{i=1}^{n} i\\;\\;\\; \\prod_{k=1}^{m} a_k\\;\\;\\; " +
            "\\int_0^1 f(x)\\,dx\\;\\;\\; \\lim_{x\\to 0} f(x)",
        "\\begin{array}{@{}||l|r||@{}}\\hline x&\\frac{1}{2}\\\\[1em]" +
            "\\hline y&\\sqrt{z}\\\\[-1pt]\\hline\\hline\\end{array}",
        "\\begin{cases}x^2&x>0\\\\-x&x\\le0\\end{cases}\\;" +
            "\\begin{dcases}\\frac{1}{2}&x>0\\\\0&x\\le0\\end{dcases}\\;" +
            "\\begin{aligned}a&=\\begin{smallmatrix}1&2\\\\3&4" +
            "\\end{smallmatrix}\\\\b&=\\sqrt{z}\\end{aligned}",
    }
    for source in formulas {
        request := Bridge_Dynview_Math_Request{
            source = source,
            text_style = BRIDGE_DYNVIEW_STYLE_OUTPUT,
            math_style = BRIDGE_DYNVIEW_STYLE_ITALIC,
            mathbb_style = BRIDGE_DYNVIEW_STYLE_BOLD,
        }
        testing.expect_value(t, dynview_math_block(state, request),
            i32(BRIDGE_STATUS_OK))
        testing.expect_value(t, dynview_math_block(state, request),
            i32(BRIDGE_STATUS_OK))
    }
}

//   Verify semantic stretch delimiters reach the renderer's established codes.
@(test)
dynview_native_math_maps_stretch_delimiter_modes :: proc(t: ^testing.T) {
    state := animation_value_test_state_create(47)
    testing.expect(t, state != nil)
    defer animation_value_test_state_destroy(state)
    state.saved_context = context
    state.dynview.enabled = true
    state.dynview.command_buffer.stream_open_block = true
    request := Bridge_Dynview_Math_Request{
        source = "\\left\\langle x\\right\\rangle",
        text_style = BRIDGE_DYNVIEW_STYLE_OUTPUT,
        math_style = BRIDGE_DYNVIEW_STYLE_MEDIUM,
        mathbb_style = BRIDGE_DYNVIEW_STYLE_BOLD,
    }
    testing.expect_value(t,
        dynview_math_block(state, request), i32(BRIDGE_STATUS_OK))
    block := state.dynview.command_buffer.commands[0]
    program := &state.dynview.compile_cache.math_programs[block.math_program_id]
    command := state.dynview.compile_cache.math_commands[program.command_start]
    testing.expect_value(t, command.kind,
        core.Dynview_Command_Kind.Stretch_Delimiter)
    testing.expect_value(t, command.accent_mode,
        BRIDGE_DYNVIEW_DELIMITER_KIND_LEFT_ANGLE)
    testing.expect_value(t, command.radical_mode,
        BRIDGE_DYNVIEW_DELIMITER_KIND_RIGHT_ANGLE)
}

//   Verify repeated facade submissions reuse native semantics without store growth.
@(test)
dynview_native_document_reuses_interned_source :: proc(t: ^testing.T) {
    state := animation_value_test_state_create(47)
    testing.expect(t, state != nil)
    defer animation_value_test_state_destroy(state)
    state.saved_context = context
    state.dynview.enabled = true
    request := Bridge_Dynview_Document_Request{
        source = "text $x^2$",
        fallback = "fallback",
        block_kind = BRIDGE_DYNVIEW_BLOCK_OUTPUT,
        block_id = 14,
        text_style = BRIDGE_DYNVIEW_STYLE_OUTPUT,
    }
    testing.expect_value(t, dynview_tex_document(state, request),
        i32(BRIDGE_STATUS_OK))
    before := dyncore.document_store_diagnostics(&state.dynview_documents)
    testing.expect_value(t, dynview_tex_document(state, request),
        i32(BRIDGE_STATUS_OK))
    after := dyncore.document_store_diagnostics(&state.dynview_documents)

    testing.expect_value(t, after.entry_count, before.entry_count)
    testing.expect_value(t, after.blob_bytes, before.blob_bytes)
    testing.expect_value(t, after.intern_hits, before.intern_hits + 1)
}

//   Verify default matrix descriptors remain canonical through snapshot sealing.
@(test)
dynview_native_matrix_snapshot_is_valid :: proc(t: ^testing.T) {
    state := animation_value_test_state_create(48)
    testing.expect(t, state != nil)
    defer animation_value_test_state_destroy(state)
    state.saved_context = context
    state.dynview.enabled = true
    state.dynview.command_buffer.stream_open_block = true
    state.dynview.command_buffer.stream_open_block_id = 15
    request := Bridge_Dynview_Math_Request{
        source = "\\sum \\left\\{\\begin{matrix}1&2&3&4\\\\5&6&7&8" +
            "\\end{matrix}\\right\\}",
        text_style = BRIDGE_DYNVIEW_STYLE_OUTPUT,
        math_style = BRIDGE_DYNVIEW_STYLE_ITALIC,
        mathbb_style = BRIDGE_DYNVIEW_STYLE_CUSTOM_FONT |
            BRIDGE_DYNVIEW_FONT_FLAG_REGULAR,
        root_style = BRIDGE_DYNVIEW_MATH_ROOT_DISPLAY,
    }
    testing.expect_value(t, dynview_math_block(state, request),
        i32(BRIDGE_STATUS_OK))
    state.dynview.command_buffer.stream_open_block = false
    service := view_snapshot_arena_test_service(t)
    defer view_snapshot_arena_test_service_destroy(service)
    slot := &service.view_snapshots[0]
    testing.expect(t, prepare_view_snapshot_slot(slot))
    testing.expect(t, build_generated_view_snapshot_payloads(
        slot, &state.dynview, "fallback"))
    testing.expect(t, view_snapshot_is_valid(slot))
}

//   Verify authored inline shapes survive native document import and compilation.
@(test)
dynview_native_circle_document_compiles :: proc(t: ^testing.T) {
    state := animation_value_test_state_create(49)
    testing.expect(t, state != nil)
    defer animation_value_test_state_destroy(state)
    state.saved_context = context
    state.dynview.enabled = true
    source := "\\textbf{Euclid Elements - Book I - Definition}\\newline " +
        "\\textit{Circle and Center}\n\nA circle " +
        "\\euclidcircle[color=steelblue,size=1,thickness=2] is a plane figure " +
        "contained by one line from one point " +
        "\\euclidpoint[color=palevioletred1,size=1] within the figure."
    testing.expect_value(t, dynview_tex_document(state, {
        source = cstring(raw_data(source)),
        fallback = "Circle and Center",
        block_kind = BRIDGE_DYNVIEW_BLOCK_OUTPUT,
        block_id = 16,
        text_style = BRIDGE_DYNVIEW_STYLE_OUTPUT,
    }), i32(BRIDGE_STATUS_OK))

    testing.expect(t, core.arena_owner_init(&state.dynview.cache_arena))
    defer core.arena_owner_destroy(&state.dynview.cache_arena)
    state.dynview.cache_access_state = .Worker_Mutable
    state.dynview.cache_worker_thread_id = os.get_current_thread_id()
    state.dynview.compile_cache.last_panel_width = 800
    state.dynview.compile_cache.last_cell_width = 8
    state.dynview.compile_cache.last_cell_height = 20
    state.dynview.compile_cache.last_font_size = 16
    dyncompile.compile_if_needed(&state.dynview, &state.dynview.cache_arena)

    testing.expect_value(t, state.dynview.compile_cache.last_error_code,
        dyncore.DYNVIEW_STATUS_OK)
    testing.expect(t, state.dynview.compile_cache.is_valid)
    testing.expect(t, state.dynview.compile_cache.layout_is_valid)
}