package dynview_layout

import app_core "../../core"

Document_Greedy_Append :: struct {
    start: int,
    end: int,
    block_index: int,
    available_width: f32,
}

Document_Line_Builder :: struct {
    value: ^app_core.Bounded_Element_Builder(
        app_core.Dynview_Document_Layout_Line),
}

// Report whether one node is a legal line boundary after its width is consumed.
document_node_allows_break :: #force_inline proc(
    node: app_core.Dynview_Document_Layout_Node) -> bool {

    return node.kind == .Forced_Break ||
        node.kind == .Glue && node.break_allowed ||
        node.kind == .Penalty && node.break_allowed
}

// Return the first node retained on a line after discarding leading glue.
document_skip_leading_glue :: #force_inline proc(
    nodes: []app_core.Dynview_Document_Layout_Node,
    start, end: int) -> int {

    result := start
    for result < end && nodes[result].kind == .Glue {
        result += 1
    }
    return result
}

// Return the exclusive line end before trailing glue or a forced-break marker.
document_trim_line_end :: #force_inline proc(
    nodes: []app_core.Dynview_Document_Layout_Node,
    start, end: int) -> int {

    result := end
    for result > start &&
        (nodes[result-1].kind == .Glue || nodes[result-1].kind == .Forced_Break) {
        result -= 1
    }
    return result
}

// Sum natural widths over one measured node range.
document_node_range_width :: proc(
    nodes: []app_core.Dynview_Document_Layout_Node,
    start, end: int) -> f32 {

    width: f32
    for node in nodes[start:end] {
        width += node.width
    }
    return width
}

// Append one measured line range and report its next unconsumed node.
document_greedy_append_line :: proc(
    nodes: []app_core.Dynview_Document_Layout_Node,
    request: Document_Greedy_Append,
    lines: Document_Line_Builder) -> (int, app_core.Bounded_Builder_Status) {

    content_start := document_skip_leading_glue(nodes, request.start, request.end)
    content_end := document_trim_line_end(nodes, content_start, request.end)
    width := document_node_range_width(nodes, content_start, content_end)
    status := app_core.bounded_element_builder_append(lines.value,
        []app_core.Dynview_Document_Layout_Line{{
            node_start = content_start,
            node_count = content_end-content_start,
            block_index = request.block_index,
            natural_width = width,
            width = width,
            overfull = width > request.available_width,
            display_row_index = -1,
        }})
    return request.end, status
}

// Find the measured last-fitting breakpoint for one current line.
document_greedy_line_end :: proc(
    nodes: []app_core.Dynview_Document_Layout_Node,
    start: int,
    available_width: f32) -> int {

    width: f32
    last_break := -1
    for index in start..<len(nodes) {
        node := nodes[index]
        if node.kind == .Forced_Break {
            return index+1
        }
        next_width := width + node.width
            if next_width > available_width && index > start {
                if last_break > start {
                    return last_break
                }
        }
        width = next_width
        if document_node_allows_break(node) {
            last_break = index+1
        }
    }
    return len(nodes)
}

// Break one paragraph into bounded measured lines using last-fitting breakpoints.
document_greedy_break :: proc(
    nodes: []app_core.Dynview_Document_Layout_Node,
    block_index: int,
    available_width: f32,
    lines: ^app_core.Bounded_Element_Builder(
        app_core.Dynview_Document_Layout_Line),
    first_line_indent: f32 = 0) -> app_core.Bounded_Builder_Status {

    if available_width <= 0 || lines == nil {
        return .Invalid_Argument
    }
    start := 0
    for start < len(nodes) {
        line_width := available_width-first_line_indent if start == 0 else
            available_width
        end := document_greedy_line_end(nodes, start, line_width)
        if end <= start {
            return .Invalid_Argument
        }
        next, status := document_greedy_append_line(nodes, {
            start = start, end = end, block_index = block_index,
            available_width = line_width,
        }, {lines})
        if status != .Ok {
            return status
        }
        start = next
    }
    return .Ok
}