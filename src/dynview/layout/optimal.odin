package dynview_layout

import app_core "../../core"
import "base:runtime"

DOCUMENT_BREAK_LINE_PENALTY :: 10.0
DOCUMENT_BREAK_FITNESS_DEMERITS :: 3000.0

// Return production limits for one bounded paragraph search.
document_optimal_break_limits :: proc() -> Document_Break_Limits {
    return {
        candidates = app_core.DYNVIEW_MAX_DOCUMENT_BREAK_CANDIDATES,
        states = app_core.DYNVIEW_MAX_DOCUMENT_BREAK_STATES,
        work = app_core.DYNVIEW_MAX_DOCUMENT_BREAK_WORK,
    }
}

// Delegate a whole paragraph to the established deterministic greedy breaker.
document_optimal_fallback :: proc(
    nodes: []app_core.Dynview_Document_Layout_Node,
    block_index: int,
    width: Document_Break_Width,
    lines: ^app_core.Bounded_Element_Builder(
        app_core.Dynview_Document_Layout_Line),
    reason: Document_Break_Fallback) -> Document_Break_Result {

    return {
        status = document_greedy_break(
            nodes, block_index, width.available, lines, width.first_line_indent),
        fallback = reason,
    }
}

// Collect legal boundaries and the terminal paragraph boundary into fixed storage.
document_break_collect_candidates :: proc(
    nodes: []app_core.Dynview_Document_Layout_Node,
    candidates: []Document_Break_Candidate) -> (int, Document_Break_Fallback) {

    if len(candidates) < 1 {
        return 0, .Candidate_Limit
    }
    candidates[0] = {raw_end = 0, next_start = 0}
    count := 1
    for node, index in nodes {
        if !document_node_allows_break(node) {
            continue
        }
        if count >= len(candidates) {
            return 0, .Candidate_Limit
        }
        candidates[count] = {
            raw_end = index+1,
            next_start = index+1,
            penalty = node.penalty,
            forced = node.kind == .Forced_Break,
        }
        count += 1
    }
    if count == 1 || candidates[count-1].raw_end != len(nodes) {
        if count >= len(candidates) {
            return 0, .Candidate_Limit
        }
        candidates[count] = {
            raw_end = len(nodes), next_start = len(nodes), terminal = true}
        count += 1
    } else {
        candidates[count-1].terminal = true
    }
    return count, .None
}

// Measure natural width and usable glue over one trimmed candidate line.
document_break_measure_line :: proc(
    nodes: []app_core.Dynview_Document_Layout_Node,
    start, raw_end: int) -> Document_Break_Measurement {

    result: Document_Break_Measurement
    result.line_start = document_skip_leading_glue(nodes, start, raw_end)
    result.line_end = document_trim_line_end(
        nodes, result.line_start, raw_end)
    for node in nodes[result.line_start:result.line_end] {
        result.width += node.width
        result.stretch += node.stretch
        result.shrink += node.shrink
    }
    return result
}

// Compute TeX-style cubic badness and a coarse adjustment fitness class.
document_break_quality :: proc(
    width, stretch, shrink, available_width: f32,
    ragged: bool) -> Document_Break_Quality {

    if ragged {
        return {fitness = .Decent, overfull = width > available_width}
    }
    delta := available_width-width
    ratio: f32
    if delta > 0 {
        ratio = delta/stretch if stretch > 0 else 4
    } else if delta < 0 {
        ratio = delta/shrink if shrink > 0 else -4
    }
    magnitude := abs(ratio)
    badness := min(10000.0, 100.0*f64(magnitude*magnitude*magnitude))
    fitness := Document_Break_Fitness.Decent
    if ratio < -0.5 {
        fitness = .Tight
    } else if ratio > 1 {
        fitness = .Very_Loose
    } else if ratio > 0.5 {
        fitness = .Loose
    }
    return {
        ratio = ratio, badness = badness,
        fitness = fitness, overfull = ratio < -1,
    }
}

// Combine line badness, semantic penalty, and adjacent fitness transition cost.
document_break_demerits :: proc(
    badness: f64,
    penalty: i32,
    previous, current: Document_Break_Fitness) -> f64 {

    base := DOCUMENT_BREAK_LINE_PENALTY+badness
    result := base*base
    penalty_square := f64(penalty)*f64(penalty)
    result += penalty_square if penalty >= 0 else -penalty_square
    distance := abs(int(current)-int(previous))
    if distance > 1 {
        result += DOCUMENT_BREAK_FITNESS_DEMERITS
    }
    return result
}

// Report whether a candidate transition crosses an earlier forced boundary.
document_break_crosses_forced :: proc(
    candidates: []Document_Break_Candidate,
    from, to: int) -> bool {

    for index in from+1..<to {
        if candidates[index].forced {
            return true
        }
    }
    return false
}

// Compare all source fitness states and retain a better target state.
document_break_update_state :: proc(
    ctx: ^Document_Break_Search_Context,
    transition: Document_Break_Transition) -> Document_Break_Fallback {

    quality := transition.quality
    target_state := transition.target*4+int(quality.fitness)
    for source_fitness in 0..<4 {
        ctx.work += 1
        if ctx.work > ctx.work_limit {
            return .Work_Limit
        }
        source_state := transition.source*4+source_fitness
        if !ctx.states[source_state].active {
            continue
        }
        demerits := ctx.states[source_state].demerits+document_break_demerits(
            quality.badness, ctx.candidates[transition.target].penalty,
            ctx.states[source_state].fitness, quality.fitness)
        if ctx.states[target_state].active &&
            demerits >= ctx.states[target_state].demerits {
            continue
        }
        ctx.states[target_state] = {
            demerits = demerits, previous_state = source_state,
            candidate_index = transition.target,
            line_start = transition.measurement.line_start,
            line_end = transition.measurement.line_end,
            width = transition.measurement.width,
            adjusted_width = transition.adjusted_width,
            adjustment_ratio = quality.ratio, fitness = quality.fitness,
            overfull = quality.overfull, active = true,
        }
    }
    return .None
}

// Measure and evaluate one candidate transition before updating active states.
document_break_consider_transition :: proc(
    ctx: ^Document_Break_Search_Context,
    source, target: int) -> Document_Break_Fallback {

    if document_break_crosses_forced(ctx.candidates, source, target) {
        return .None
    }
    measure := document_break_measure_line(
        ctx.nodes, ctx.candidates[source].next_start,
        ctx.candidates[target].raw_end)
    ragged := ctx.candidates[target].terminal || ctx.candidates[target].forced
    line_width := ctx.available_width
    if source == 0 {
        line_width -= ctx.first_line_indent
    }
    quality := document_break_quality(
        measure.width, measure.stretch, measure.shrink,
        line_width, ragged)
    if quality.overfull && target > source+1 {
        return .None
    }
    adjusted_width := measure.width
    adjusted_width += quality.ratio*measure.stretch if quality.ratio >= 0 else
        max(quality.ratio, -1)*measure.shrink
    return document_break_update_state(ctx, {
        source = source, target = target, measurement = measure,
        quality = quality, adjusted_width = adjusted_width,
    })
}

// Select the least-demerit fitness state at the terminal candidate.
document_break_best_terminal :: proc(
    states: []Document_Break_State,
    candidate_count: int) -> int {

    terminal_base := (candidate_count-1)*4
    best := -1
    for offset in 0..<4 {
        index := terminal_base+offset
        if states[index].active &&
            (best < 0 || states[index].demerits < states[best].demerits) {
            best = index
        }
    }
    return best
}

// Search all bounded candidate transitions and retain one state per terminal fitness.
document_break_search :: proc(
    nodes: []app_core.Dynview_Document_Layout_Node,
    candidates: []Document_Break_Candidate,
    width: Document_Break_Width,
    states: []Document_Break_State,
    work_limit: int) -> (int, Document_Break_Fallback) {

    if len(states) < len(candidates)*4 {
        return -1, .State_Limit
    }
    states[int(Document_Break_Fitness.Decent)] = {
        active = true, fitness = .Decent, candidate_index = 0,
        previous_state = -1,
    }
    ctx := Document_Break_Search_Context{
        nodes = nodes, candidates = candidates, states = states,
        available_width = width.available,
        first_line_indent = width.first_line_indent,
        work_limit = work_limit,
    }
    for target in 1..<len(candidates) {
        for source in 0..<target {
            fallback := document_break_consider_transition(&ctx, source, target)
            if fallback != .None {
                return -1, fallback
            }
        }
    }
    best := document_break_best_terminal(states, len(candidates))
    return best, .No_Solution if best < 0 else .None
}

// Append one reconstructed search state as a public line record.
document_break_append_state :: proc(
    lines: ^app_core.Bounded_Element_Builder(
        app_core.Dynview_Document_Layout_Line),
    state: Document_Break_State,
    block_index: int,
    available_width: f32) -> app_core.Bounded_Builder_Status {

    return app_core.bounded_element_builder_append(lines,
        []app_core.Dynview_Document_Layout_Line{{
            node_start = state.line_start,
            node_count = state.line_end-state.line_start,
            block_index = block_index,
            natural_width = state.width,
            width = state.adjusted_width,
            adjustment_ratio = state.adjustment_ratio,
            overfull = state.overfull || state.adjusted_width > available_width,
            display_row_index = -1,
        }})
}

// Reconstruct a complete best path before appending any public line records.
document_break_publish_path :: proc(
    states: []Document_Break_State,
    terminal_state, block_index: int,
    available_width: f32,
    lines: ^app_core.Bounded_Element_Builder(
        app_core.Dynview_Document_Layout_Line)) -> app_core.Bounded_Builder_Status {

    path: [app_core.DYNVIEW_MAX_DOCUMENT_LAYOUT_LINES]int
    count := 0
    for state_index := terminal_state; state_index >= 0; {
        state := states[state_index]
        if state.previous_state < 0 {
            break
        }
        if count >= len(path) {
            return .Limit_Exceeded
        }
        path[count] = state_index
        count += 1
        state_index = state.previous_state
    }
    if count > lines.max_count-lines.count {
        return .Limit_Exceeded
    }
    reserve_status := app_core.bounded_element_builder_reserve(lines, count)
    if reserve_status != .Ok {
        return reserve_status
    }
    for reverse_index := count-1; reverse_index >= 0; reverse_index -= 1 {
        state := states[path[reverse_index]]
        status := document_break_append_state(
            lines, state, block_index, available_width)
        if status != .Ok {
            return status
        }
    }
    return .Ok
}

// Allocate exact bounded-search scratch slices from the layout transaction arena.
document_break_allocate_scratch :: proc(
    limits: Document_Break_Limits,
    node_count: int,
    allocator: runtime.Allocator) -> Document_Break_Scratch {

    candidate_capacity := min(limits.candidates, node_count+1,
        app_core.DYNVIEW_MAX_DOCUMENT_BREAK_CANDIDATES)
    candidates, candidate_error := make(
        []Document_Break_Candidate, candidate_capacity, allocator)
    if candidate_error != nil {
        return {status = .Allocation_Failed}
    }
    state_capacity := min(limits.states, candidate_capacity*4,
        app_core.DYNVIEW_MAX_DOCUMENT_BREAK_STATES)
    states, state_error := make([]Document_Break_State, state_capacity, allocator)
    if state_error != nil {
        return {status = .Allocation_Failed}
    }
    return {candidates = candidates, states = states, status = .Ok}
}

// Break one paragraph optimally within explicit storage and work bounds.
document_optimal_break_with_limits :: proc(
    nodes: []app_core.Dynview_Document_Layout_Node,
    block_index: int,
    width: Document_Break_Width,
    lines: ^app_core.Bounded_Element_Builder(
        app_core.Dynview_Document_Layout_Line),
    limits: Document_Break_Limits) -> Document_Break_Result {

    if width.available <= 0 || lines == nil || limits.candidates < 1 ||
        limits.states < 1 || limits.work < 1 {
        return {.Invalid_Argument, .None}
    }
    scratch := document_break_allocate_scratch(
        limits, len(nodes), lines.allocator)
    if scratch.status != .Ok {
        return {scratch.status, .None}
    }
    candidate_count, fallback := document_break_collect_candidates(
        nodes, scratch.candidates)
    if fallback != .None {
        return document_optimal_fallback(
            nodes, block_index, width, lines, fallback)
    }
    terminal, search_fallback := document_break_search(
        nodes, scratch.candidates[:candidate_count], width,
        scratch.states, limits.work)
    if search_fallback != .None {
        return document_optimal_fallback(
            nodes, block_index, width, lines, search_fallback)
    }
    return {
        status = document_break_publish_path(
            scratch.states, terminal, block_index, width.available, lines),
    }
}

// Break one paragraph using production optimal-search limits.
document_optimal_break :: proc(
    nodes: []app_core.Dynview_Document_Layout_Node,
    block_index: int,
    available_width: f32,
    lines: ^app_core.Bounded_Element_Builder(
        app_core.Dynview_Document_Layout_Line),
    first_line_indent: f32 = 0) -> Document_Break_Result {

    return document_optimal_break_with_limits(
        nodes, block_index, {available_width, first_line_indent}, lines,
        document_optimal_break_limits())
}