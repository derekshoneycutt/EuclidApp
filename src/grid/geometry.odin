package grid

import "core:math"

// Canonical pixel geometry shared by one regular grid.
Cell_Metrics :: struct {
    cell_width: f32,
    cell_height: f32,
    baseline_from_top: f32,

    // Ink height permitted above the band before another row is reserved. This is
    // TeX's `\lineskiplimit`: ink may protrude into a neighbour's unused leading.
    ascent_overflow: f32,
}

// Tight visual bounds supplied by one embeddable renderer.
Embedded_Content_Metrics :: struct {
    width: f32,
    height: f32,
    has_baseline: bool,
    baseline_from_top: f32,
}

// Smallest compatible grid allocation and intrinsic-content placement.
Embedded_Grid_Placement :: struct {
    column_span: int,
    row_span: int,
    allocated_width: f32,
    allocated_height: f32,
    content_offset_x: f32,
    content_offset_y: f32,
    baseline_row: int,
}

// Outward row allocation for one exact vertical extent on the shared grid.
Vertical_Reservation :: struct {
    row_start: int,
    row_count: int,
    top: f32,
    bottom: f32,
    trailing_padding: f32,
}

// Report whether one scalar is finite.
scalar_is_finite :: #force_inline proc(value: f32) -> bool {
    return !math.is_nan(value) && !math.is_inf(value)
}

// Report whether canonical cell dimensions and baseline are valid.
cell_metrics_valid :: #force_inline proc(metrics: Cell_Metrics) -> bool {
    return scalar_is_finite(metrics.cell_width) &&
        scalar_is_finite(metrics.cell_height) &&
        scalar_is_finite(metrics.baseline_from_top) &&
        scalar_is_finite(metrics.ascent_overflow) &&
        metrics.cell_width > 0 &&
        metrics.cell_height > 0 &&
        metrics.baseline_from_top >= 0 &&
        metrics.baseline_from_top <= metrics.cell_height &&
        metrics.ascent_overflow >= 0 &&
        metrics.ascent_overflow <= metrics.cell_height
}

// Report whether intrinsic content dimensions and optional baseline are valid.
embedded_content_metrics_valid :: #force_inline proc(
    content: Embedded_Content_Metrics) -> bool {

    if !scalar_is_finite(content.width) ||
        !scalar_is_finite(content.height) ||
        content.width <= 0 || content.height <= 0 {
        return false
    }
    if !content.has_baseline {
        return true
    }
    return scalar_is_finite(content.baseline_from_top) &&
        content.baseline_from_top >= 0 &&
        content.baseline_from_top <= content.height
}

// Report whether outward rounding remains representable by the result types.
extent_is_representable :: #force_inline proc(
    extent, cell_extent: f32,
    additional_cells: int = 0) -> bool {

    rounded_span := math.ceil(f64(extent) / f64(cell_extent))
    result_span := rounded_span + f64(additional_cells)
    return result_span < f64(max(int)) &&
        result_span * f64(cell_extent) <= f64(max(f32))
}

// Return the minimum positive cell span containing one validated extent.
span_for_extent :: #force_inline proc(extent, cell_extent: f32) -> int {
    return max(1, int(math.ceil(f64(extent) / f64(cell_extent))))
}

// Round one exact extent outward from a row-aligned origin.
reserve_vertical_extent :: proc(
    row_start: int,
    exact_height, cell_height: f32) -> (Vertical_Reservation, bool) {

    if row_start < 0 || !scalar_is_finite(exact_height) ||
        !scalar_is_finite(cell_height) || exact_height <= 0 || cell_height <= 0 ||
        !extent_is_representable(exact_height, cell_height, row_start) {
        return {}, false
    }
    row_count := span_for_extent(exact_height, cell_height)
    top := f32(row_start)*cell_height
    bottom := f32(row_start+row_count)*cell_height
    return {
        row_start = row_start, row_count = row_count,
        top = top, bottom = bottom,
        trailing_padding = bottom-top-exact_height,
    }, true
}

// Place non-baseline content at the geometric center of its containing grid box.
place_centered_content :: #force_inline proc(
    cells: Cell_Metrics,
    content: Embedded_Content_Metrics) -> Embedded_Grid_Placement {

    column_span := span_for_extent(content.width, cells.cell_width)
    row_span := span_for_extent(content.height, cells.cell_height)
    allocated_width := f32(column_span) * cells.cell_width
    allocated_height := f32(row_span) * cells.cell_height
    return Embedded_Grid_Placement{
        column_span = column_span,
        row_span = row_span,
        allocated_width = allocated_width,
        allocated_height = allocated_height,
        content_offset_x = (allocated_width - content.width) * 0.5,
        content_offset_y = (allocated_height - content.height) * 0.5,
    }
}

// Place baseline content in the smallest box preserving the canonical baseline lattice.
//
// Notes:
//   - Ink above the band is permitted up to `cells.ascent_overflow`, which yields a
//     negative `content_offset_y` rather than an additional reserved row.
//   - Ink below the baseline always reserves rows, so placed content never protrudes
//     past the bottom of its own allocation.
place_baseline_content :: #force_inline proc(
    cells: Cell_Metrics,
    content: Embedded_Content_Metrics) -> Embedded_Grid_Placement {

    top_extent := content.baseline_from_top
    bottom_extent := content.height - content.baseline_from_top
    contained_top := f64(cells.baseline_from_top) + f64(cells.ascent_overflow)
    baseline_row := max(0, int(math.ceil(
        (f64(top_extent) - contained_top) / f64(cells.cell_height))))
    baseline_y := f64(baseline_row) * f64(cells.cell_height) +
        f64(cells.baseline_from_top)
    row_span := span_for_extent(f32(baseline_y + f64(bottom_extent)), cells.cell_height)
    column_span := span_for_extent(content.width, cells.cell_width)
    allocated_width := f32(column_span) * cells.cell_width
    allocated_height := f32(row_span) * cells.cell_height
    return Embedded_Grid_Placement{
        column_span = column_span,
        row_span = row_span,
        allocated_width = allocated_width,
        allocated_height = allocated_height,
        content_offset_x = (allocated_width - content.width) * 0.5,
        content_offset_y = f32(baseline_y) - content.baseline_from_top,
        baseline_row = baseline_row,
    }
}

// Resolve the minimum grid allocation for validated intrinsic content.
place_embedded_content :: proc(
    cells: Cell_Metrics,
    content: Embedded_Content_Metrics) -> (Embedded_Grid_Placement, bool) {

    if !cell_metrics_valid(cells) || !embedded_content_metrics_valid(content) {
        return {}, false
    }
    additional_rows := 0
    if content.has_baseline {
        additional_rows = 1
    }
    if !extent_is_representable(content.width, cells.cell_width) ||
        !extent_is_representable(content.height, cells.cell_height, additional_rows) {
        return {}, false
    }
    if content.has_baseline {
        return place_baseline_content(cells, content), true
    }
    return place_centered_content(cells, content), true
}