package dynview_parse

TEX_MATH_OP_CAPACITY :: 4096
TEX_MATH_PROGRAM_CAPACITY :: 256
TEX_SEMANTIC_TEXT_BYTE_CAPACITY :: 64 * 1024
TEX_TABLE_DESCRIPTOR_CAPACITY :: 256
TEX_DOCUMENT_RUN_CAPACITY :: 512

// Match the frozen recursive operation numbers emitted by the Julia compiler.
Tex_Math_Op_Kind :: enum i32 {
    Text_Run = 1,
    Math_Glyph_Run,
    Accent,
    Radical,
    Script,
    Large_Operator,
    Fraction,
    Stretch_Delimiter,
    Matrix,
    Style_Override,
    Stack,
}

// Identify font-independent semantic math roles.
Tex_Math_Style_Role :: enum {
    None,
    Math,
    Math_Italic,
    Math_Upright,
    Text,
    Mathbb,
    Mathbf,
    Mathit,
    Mathcal,
    Operator_Name,
    Operator_Name_Star,
}

// Match the native and frozen TeX atom classifications.
Tex_Math_Atom_Class :: enum i32 {
    None = 0,
    Ord,
    Op,
    Bin,
    Rel,
    Open,
    Close,
    Punct,
    Inner,
}

// Match explicit semantic spacing kinds from the frozen compiler output.
Tex_Math_Glue_Kind :: enum i32 {
    None = 0,
    Thick,
    Space,
    Negative_Thin,
    Quad,
    Thin,
    Source,
}

// Identify supported accent semantics independently from rendering.
Tex_Accent_Mode :: enum {
    None,
    Overline,
    Underline,
    Hat,
    Tilde,
    Vec,
    Dot,
    Ddot,
    Bar,
    Check,
    Breve,
    Acute,
    Grave,
    Ring,
    Overbrace,
    Underbrace,
}

// Identify radical and root-style wrappers independently from rendering.
Tex_Radical_Mode :: enum {
    None,
    Square_Root,
    Nth_Root,
}

// Identify TeX's four explicit recursive math size levels.
Tex_Math_Style_Level :: enum i32 {
    Display = 0,
    Text,
    Script,
    Script_Script,
}

// Identify every stretch delimiter supported by the historical parser.
Tex_Delimiter_Kind :: enum i32 {
    None = 0,
    Left_Paren,
    Right_Paren,
    Left_Bracket,
    Right_Bracket,
    Left_Brace,
    Right_Brace,
    Vert,
    Double_Vert,
    Left_Ceil,
    Right_Ceil,
    Left_Floor,
    Right_Floor,
    Left_Angle,
    Right_Angle,
}

// Select the caller-provided root math style.
Tex_Math_Root_Style :: enum {
    Display,
    Text,
}

// Reference immutable bytes in parser-owned semantic text storage.
Tex_Text_Span :: struct {
    offset: int,
    length: int,
}

// Identify source units retained by table spacing semantics.
Tex_Table_Length_Unit :: enum {
    Default,
    Zero,
    Em,
    Pt,
}

// Retain one font-independent table length.
Tex_Table_Length :: struct {
    value: f32,
    unit: Tex_Table_Length_Unit,
}

// Identify one table column alignment.
Tex_Table_Alignment :: enum {
    Left,
    Center,
    Right,
}

// Identify the font-independent vertical spacing policy for one table.
Tex_Table_Row_Spacing :: enum i32 {
    Matrix = 0,
    Tight,
    Cases,
    Alignment,
}

// Retain bounded table layout semantics without pixel geometry.
Tex_Table_Descriptor :: struct {
    present: bool,
    rows: int,
    columns: int,
    cell_style: Tex_Math_Style_Level,
    row_spacing: Tex_Table_Row_Spacing,
    alignments: [16]Tex_Table_Alignment,
    boundary_gaps: [17]Tex_Table_Length,
    vertical_rule_counts: [17]u8,
    row_extra_gaps: [16]Tex_Table_Length,
    horizontal_rule_counts: [17]u8,
}

// Match the flat document run kinds emitted by the legacy parser.
Tex_Document_Run_Kind :: enum {
    Text,
    Math_Inline,
    Math_Display,
    Shape,
    Line_Break,
}

// Retain one optional color without depending on rendering packages.
Tex_Document_Color :: struct {
    present: bool,
    red: u8,
    green: u8,
    blue: u8,
    alpha: u8,
}

// Identify supported inline Euclid shape semantics.
Tex_Document_Shape_Kind :: enum {
    None,
    Point,
    Line,
    Circle,
    Box,
    Angle,
    Semicircle,
    Perpendicular,
    Triangle,
    Pentagon,
}

// Retain one font-independent inline Euclid shape payload.
Tex_Document_Shape :: struct {
    present: bool,
    kind: Tex_Document_Shape_Kind,
    color: Tex_Document_Color,
    width: f32,
    height: f32,
    thickness: f32,
    filled: bool,
    start_angle: f32,
    end_angle: f32,
    fill_color: Tex_Document_Color,
    arc_color: Tex_Document_Color,
    edge_colors: [5]Tex_Document_Color,
}

// Retain one flat document command and its optional recursive math program.
Tex_Document_Run :: struct {
    kind: Tex_Document_Run_Kind,
    text: Tex_Text_Span,
    font_flags: i32,
    color: Tex_Document_Color,
    shape: Tex_Document_Shape,
    root_style: Tex_Math_Root_Style,
    math_program: int,
}

// Describe one recursive program as a linked sequence of semantic operations.
Tex_Math_Program :: struct {
    first_op: int,
    last_op: int,
    op_count: int,
}

// Store one font-independent recursive math operation.
Tex_Math_Op :: struct {
    kind: Tex_Math_Op_Kind,
    text: Tex_Text_Span,
    radical_index_text: Tex_Text_Span,
    superscript_text: Tex_Text_Span,
    subscript_text: Tex_Text_Span,
    accent_mode: Tex_Accent_Mode,
    radical_mode: Tex_Radical_Mode,
    style_level: Tex_Math_Style_Level,
    left_delimiter: Tex_Delimiter_Kind,
    right_delimiter: Tex_Delimiter_Kind,
    large_op_kind: i32,
    operator_growth: i32,
    operator_limits: i32,
    style_role: Tex_Math_Style_Role,
    atom_class: Tex_Math_Atom_Class,
    glue_kind: Tex_Math_Glue_Kind,
    child_program: int,
    secondary_program: int,
    tertiary_program: int,
    table_descriptor: int,
    next_op: int,
}

// Own bounded parser output without font, layout, bridge, or view dependencies.
Tex_Semantic_Output :: struct {
    text: [TEX_SEMANTIC_TEXT_BYTE_CAPACITY]u8,
    text_count: int,
    ops: [TEX_MATH_OP_CAPACITY]Tex_Math_Op,
    op_count: int,
    programs: [TEX_MATH_PROGRAM_CAPACITY]Tex_Math_Program,
    program_count: int,
    table_descriptors: [TEX_TABLE_DESCRIPTOR_CAPACITY]Tex_Table_Descriptor,
    table_descriptor_count: int,
    document_runs: [TEX_DOCUMENT_RUN_CAPACITY]Tex_Document_Run,
    document_run_count: int,
    root_program: int,
    plain_text: Tex_Text_Span,
    status: Tex_Parse_Status,
    error_offset: int,
    recoverable: bool,
}

//   Return one checked semantic text span as a string view.
tex_semantic_text :: proc(
    output: ^Tex_Semantic_Output,
    span: Tex_Text_Span) -> string {
    if output == nil || span.offset < 0 || span.length < 0 ||
        span.offset > output.text_count-span.length {
        return ""
    }
    return string(output.text[span.offset:span.offset + span.length])
}

//   Return the operation at one checked semantic index.
tex_semantic_op :: proc(
    output: ^Tex_Semantic_Output,
    index: int) -> ^Tex_Math_Op {
    if output == nil || index < 0 || index >= output.op_count {
        return nil
    }
    return &output.ops[index]
}