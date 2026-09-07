package dynview_layout

import app_core "../../core"
import "../../grid"

//   Accumulated item range and vertical extents for one document layout line.
Dynview_Layout_Line_Accumulator :: struct {
    item_start: int,
    item_count: int,
    max_ascent: f32,
    max_descent: f32,
}

//   Block-level alignment, indentation, spacing, and line-height controls.
Dynview_Block_Format :: struct {
    alignment: app_core.Dynview_Text_Alignment,
    indent_cols: int,
    paragraph_spacing_before: f32,
    paragraph_spacing_after: f32,
    line_height_multiplier: f32,
}

//   Mutable cursor and active-block state used while building document layout.
Dynview_Layout_State :: struct {
    line_index: int,
    col: int,
    row: int,
    active_block_id: i32,
    active_block_kind: i32,
    active_block_format: Dynview_Block_Format,
}

//   Shared inputs and mutable accumulators for one document layout build.
Dynview_Layout_Build_Context :: struct {
    cache: ^app_core.Dynview_Compile_Cache,
    buffer: ^app_core.Dynview_Command_Buffer,
    state: ^Dynview_Layout_State,
    acc: ^Dynview_Layout_Line_Accumulator,
    font_size: f32,
    base_ascent: f32,
    base_descent: f32,
    grid_metrics: grid.Cell_Metrics,
}

// Classify line adjustment so adjacent extreme lines can be discouraged.
Document_Break_Fitness :: enum u8 {
    Tight,
    Decent,
    Loose,
    Very_Loose,
}

// Identify why bounded optimal search delegated to deterministic greedy breaking.
Document_Break_Fallback :: enum u8 {
    None,
    Candidate_Limit,
    State_Limit,
    Work_Limit,
    No_Solution,
}

// Bound one invocation independently so limit behavior remains directly testable.
Document_Break_Limits :: struct {
    candidates: int,
    states: int,
    work: int,
}

// Carry the full line measure and first-line reduction through every breaker path.
Document_Break_Width :: struct {
    available: f32,
    first_line_indent: f32,
}

// Describe one legal paragraph boundary without retaining source pointers.
Document_Break_Candidate :: struct {
    raw_end: int,
    next_start: int,
    penalty: i32,
    forced: bool,
    terminal: bool,
}

// Retain one best path to a candidate for a specific terminal fitness class.
Document_Break_State :: struct {
    demerits: f64,
    previous_state: int,
    candidate_index: int,
    line_start: int,
    line_end: int,
    width: f32,
    adjusted_width: f32,
    adjustment_ratio: f32,
    fitness: Document_Break_Fitness,
    overfull: bool,
    active: bool,
}

// Report which breaker produced a complete line sequence.
Document_Break_Result :: struct {
    status: app_core.Bounded_Builder_Status,
    fallback: Document_Break_Fallback,
}

// Retain measured dimensions for one trimmed candidate line.
Document_Break_Measurement :: struct {
    line_start: int,
    line_end: int,
    width: f32,
    stretch: f32,
    shrink: f32,
}

// Retain the adjustment and cost classification for one measured line.
Document_Break_Quality :: struct {
    ratio: f32,
    badness: f64,
    fitness: Document_Break_Fitness,
    overfull: bool,
}

// Group mutable bounded-search inputs and work accounting.
Document_Break_Search_Context :: struct {
    nodes: []app_core.Dynview_Document_Layout_Node,
    candidates: []Document_Break_Candidate,
    states: []Document_Break_State,
    available_width: f32,
    first_line_indent: f32,
    work_limit: int,
    work: int,
}

// Group one measured candidate transition for deterministic state comparison.
Document_Break_Transition :: struct {
    source: int,
    target: int,
    measurement: Document_Break_Measurement,
    quality: Document_Break_Quality,
    adjusted_width: f32,
}

// Own allocator-backed scratch slices for one bounded search invocation.
Document_Break_Scratch :: struct {
    candidates: []Document_Break_Candidate,
    states: []Document_Break_State,
    status: app_core.Bounded_Builder_Status,
}