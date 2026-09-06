package dynview_parse

TEX_DOCUMENT_SHAPE_OPTION_CAPACITY :: 16

// Retain one temporary shape option as a source view during parsing.
Tex_Document_Shape_Option :: struct {
    key: string,
    value: string,
}

// Retain a bounded set of unique shape options.
Tex_Document_Shape_Options :: struct {
    values: [TEX_DOCUMENT_SHAPE_OPTION_CAPACITY]Tex_Document_Shape_Option,
    count: int,
}

//   Parse one optional bracketed shape option list at the document cursor.
tex_document_parse_shape_options :: proc(
    parser: ^Tex_Document_Parser,
    shape_kind: Tex_Document_Shape_Kind) -> (Tex_Document_Shape, bool) {
    options: Tex_Document_Shape_Options
    if parser.offset < len(parser.source) && parser.source[parser.offset] == '[' {
        end := parser.offset + 1
        for end < len(parser.source) && parser.source[end] != ']' {
            end += 1
        }
        if end >= len(parser.source) ||
            !tex_document_parse_option_list(
                parser.source[parser.offset+1:end], &options) {
            return {}, false
        }
        parser.offset = end + 1
    }
    if !tex_document_shape_options_allowed(shape_kind, &options) {
        return {}, false
    }
    return tex_document_build_shape(shape_kind, &options)
}

//   Parse comma-separated options while rejecting empty or duplicate keys.
tex_document_parse_option_list :: proc(
    text: string,
    options: ^Tex_Document_Shape_Options) -> bool {
    if len(tex_document_trim(text)) == 0 {
        return true
    }
    start := 0
    for start <= len(text) {
        end := start
        for end < len(text) && text[end] != ',' {
            end += 1
        }
        option := tex_document_trim(text[start:end])
        if !tex_document_parse_option(option, options) {
            return false
        }
        if end == len(text) {
            return true
        }
        start = end + 1
    }
    return true
}

//   Parse one key/value or `filled` flag into bounded temporary storage.
tex_document_parse_option :: proc(
    text: string,
    options: ^Tex_Document_Shape_Options) -> bool {
    if len(text) == 0 || options.count >= len(options.values) {
        return false
    }
    separator := -1
    for index in 0..<len(text) {
        if text[index] == '=' {
            separator = index
            break
        }
    }
    key, value := text, "true"
    if separator >= 0 {
        key = tex_document_trim(text[:separator])
        value = tex_document_trim(text[separator+1:])
    } else if text != "filled" {
        return false
    }
    if len(key) == 0 || len(value) == 0 || tex_document_option_has(options, key) {
        return false
    }
    options.values[options.count] = {key = key, value = value}
    options.count += 1
    return true
}

//   Return whether one temporary option set contains a key.
tex_document_option_has :: proc(
    options: ^Tex_Document_Shape_Options,
    key: string) -> bool {
    for index in 0..<options.count {
        if options.values[index].key == key {
            return true
        }
    }
    return false
}

//   Return one temporary option value and its presence.
tex_document_option_get :: proc(
    options: ^Tex_Document_Shape_Options,
    key: string) -> (string, bool) {
    for index in 0..<options.count {
        if options.values[index].key == key {
            return options.values[index].value, true
        }
    }
    return "", false
}

//   Reject options outside the legacy allowlist for one shape kind.
tex_document_shape_options_allowed :: proc(
    shape_kind: Tex_Document_Shape_Kind,
    options: ^Tex_Document_Shape_Options) -> bool {
    for index in 0..<options.count {
        if !tex_document_shape_option_allowed(
            shape_kind, options.values[index].key) {
            return false
        }
    }
    return true
}

//   Return whether one option key belongs to a shape's compatibility surface.
tex_document_shape_option_allowed :: proc(
    shape_kind: Tex_Document_Shape_Kind,
    key: string) -> bool {
    if key == "color" || key == "thickness" {
        return true
    }
    switch shape_kind {
    case .Point: return key == "size"
    case .Line: return key == "length"
    case .Circle: return key == "size" || key == "filled"
    case .Box:
        return key == "width" || key == "height" || key == "filled" ||
            tex_document_edge_key(key, 4)
    case .None: return false
    case .Angle, .Semicircle, .Perpendicular, .Triangle, .Pentagon:
        return tex_document_advanced_shape_option_allowed(shape_kind, key)
    }
    return false
}

//   Return whether one option belongs to a compound Euclid shape.
tex_document_advanced_shape_option_allowed :: proc(
    shape_kind: Tex_Document_Shape_Kind,
    key: string) -> bool {
    switch shape_kind {
    case .Angle:
        return key == "radius" || key == "start" || key == "end" ||
            key == "filled" || key == "fill_color" || key == "arc_color"
    case .Semicircle:
        return key == "radius" || key == "filled" ||
            key == "fill_color" || key == "arc_color"
    case .Perpendicular:
        return key == "length" || key == "width" || key == "height" ||
            key == "line1_color" || key == "line2_color"
    case .Triangle:
        return key == "width" || key == "height" || key == "filled" ||
            key == "fill_color" || tex_document_edge_key(key, 3)
    case .Pentagon:
        return key == "width" || key == "height" || key == "filled" ||
            key == "fill_color" || tex_document_edge_key(key, 5)
    case .None, .Point, .Line, .Circle, .Box: return false
    }
    return false
}

//   Return whether a key names one edge color within a shape-specific bound.
tex_document_edge_key :: proc(key: string, count: int) -> bool {
    keys := [?]string{
        "edge1_color", "edge2_color", "edge3_color",
        "edge4_color", "edge5_color",
    }
    for index in 0..<count {
        if key == keys[index] {
            return true
        }
    }
    return false
}

//   Build validated dimensions, booleans, and colors for one shape.
tex_document_build_shape :: proc(
    shape_kind: Tex_Document_Shape_Kind,
    options: ^Tex_Document_Shape_Options) -> (Tex_Document_Shape, bool) {
    shape := tex_document_shape_defaults(shape_kind)
    shape.present = true
    color, color_ok := tex_document_option_color(options, "color", {})
    if !color_ok {
        return {}, false
    }
    shape.color = color
    if !tex_document_shape_dimensions(&shape, options) ||
        !tex_document_shape_colors(&shape, options) {
        return {}, false
    }
    return shape, true
}

//   Return legacy default dimensions and flags for one shape kind.
tex_document_shape_defaults :: proc(
    shape_kind: Tex_Document_Shape_Kind) -> Tex_Document_Shape {
    shape := Tex_Document_Shape{
        kind = shape_kind,
        width = 1,
        height = 1,
        thickness = 1,
    }
    switch shape_kind {
    case .Point: shape.filled = true
    case .Line: shape.width = 3
    case .Box: shape.width = 2
    case .Angle: shape.end_angle = 90
    case .Semicircle: shape.end_angle = 180
    case .Perpendicular: shape.width = 2
    case .None, .Circle, .Triangle, .Pentagon:
    }
    return shape
}

//   Apply validated numeric and boolean options to one shape payload.
tex_document_shape_dimensions :: proc(
    shape: ^Tex_Document_Shape,
    options: ^Tex_Document_Shape_Options) -> bool {
    width_key := "size"
    if shape.kind == .Line || shape.kind == .Perpendicular {
        width_key = "length"
    } else if shape.kind == .Box || shape.kind == .Triangle ||
        shape.kind == .Pentagon {
        width_key = "width"
    } else if shape.kind == .Angle || shape.kind == .Semicircle {
        width_key = "radius"
    }
    shape.width = tex_document_option_float(options, width_key, shape.width)
    shape.height = tex_document_option_float(options, "height", shape.height)
    shape.thickness =
        tex_document_option_float(options, "thickness", shape.thickness)
    shape.start_angle =
        tex_document_option_float(options, "start", shape.start_angle)
    shape.end_angle = tex_document_option_float(options, "end", shape.end_angle)
    shape.filled = tex_document_option_bool(options, "filled", shape.filled)
    return shape.width > 0 && shape.height > 0 && shape.thickness > 0 &&
        shape.start_angle >= 0 && shape.end_angle >= 0
}

//   Apply validated fill, arc, and edge colors with legacy fallback rules.
tex_document_shape_colors :: proc(
    shape: ^Tex_Document_Shape,
    options: ^Tex_Document_Shape_Options) -> bool {
    color_ok := true
    if shape.kind == .Angle || shape.kind == .Semicircle ||
        shape.kind == .Triangle || shape.kind == .Pentagon {
        shape.fill_color, color_ok =
            tex_document_option_color(options, "fill_color", shape.color)
    }
    if color_ok && (shape.kind == .Angle || shape.kind == .Semicircle) {
        shape.arc_color, color_ok =
            tex_document_option_color(options, "arc_color", shape.color)
    }
    for index in 0..<len(shape.edge_colors) {
        if !color_ok {
            break
        }
        key := tex_document_edge_name(index)
        shape.edge_colors[index], color_ok =
            tex_document_option_color(options, key, shape.color)
    }
    return color_ok
}

//   Return one stable edge option key.
tex_document_edge_name :: proc(index: int) -> string {
    keys := [?]string{
        "edge1_color", "edge2_color", "edge3_color",
        "edge4_color", "edge5_color",
    }
    return keys[index]
}

//   Resolve one optional color or preserve a caller-provided fallback.
tex_document_option_color :: proc(
    options: ^Tex_Document_Shape_Options,
    key: string,
    fallback: Tex_Document_Color) -> (Tex_Document_Color, bool) {
    value, present := tex_document_option_get(options, key)
    if !present {
        return fallback, true
    }
    return tex_document_resolve_color(value)
}

//   Resolve Colors.jl names and Euclid's explicit Julia-logo aliases.
tex_document_resolve_color :: proc(name: string) -> (Tex_Document_Color, bool) {
    for named in TEX_NAMED_COLORS {
        if named.name == name {
            return {
                red = named.red,
                green = named.green,
                blue = named.blue,
                alpha = 255,
                present = true,
            }, true
        }
    }
    return tex_document_resolve_project_color(name)
}

//   Resolve Euclid's named Julia palette into deterministic RGBA bytes.
tex_document_resolve_project_color :: proc(
    name: string) -> (Tex_Document_Color, bool) {
    color := Tex_Document_Color{present = true, alpha = 255}
    switch name {
    case "julia_blue": color.red, color.green, color.blue = 64, 99, 216
    case "julia_green": color.red, color.green, color.blue = 56, 152, 38
    case "julia_purple": color.red, color.green, color.blue = 149, 88, 178
    case "julia_red": color.red, color.green, color.blue = 203, 60, 51
    case: return {}, false
    }
    return color, true
}

//   Parse one optional positive floating-point option.
tex_document_option_float :: proc(
    options: ^Tex_Document_Shape_Options,
    key: string,
    fallback: f32) -> f32 {
    text, present := tex_document_option_get(options, key)
    if !present {
        return fallback
    }
    value, ok := tex_table_parse_decimal(text)
    return value if ok else -1
}

//   Parse one optional strict boolean option.
tex_document_option_bool :: proc(
    options: ^Tex_Document_Shape_Options,
    key: string,
    fallback: bool) -> bool {
    text, present := tex_document_option_get(options, key)
    if !present {
        return fallback
    }
    return text == "true"
}

//   Trim ASCII whitespace from one temporary source view.
tex_document_trim :: proc(text: string) -> string {
    first, last := 0, len(text)
    for first < last && tex_math_ascii_space(text[first]) {
        first += 1
    }
    for last > first && tex_math_ascii_space(text[last-1]) {
        last -= 1
    }
    return text[first:last]
}