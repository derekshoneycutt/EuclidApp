"""
Cache addresses of Odin bridge functions exported by the Euclid executable.

A normal Julia JIT session can resolve bare `@ccall` names from the host process,
but code restored from a PackageCompiler sysimage cannot do so reliably on Windows.
Host exports remain at fixed addresses for the lifetime of the process.
"""
HOST_SYMBOL_CACHE = Dict{Symbol, Ptr{Cvoid}}()

"""
Resolve an Odin bridge function exported by the Euclid executable.

Windows sysimage code must call bridge functions through explicit pointers because
the functions belong to the host executable rather than a DLL in Julia's loader path.
Resolved addresses are cached in `HOST_SYMBOL_CACHE`.
"""
function host_symbol(name::Symbol)
    get!(HOST_SYMBOL_CACHE, name) do
        # A null module name asks Windows for the module containing the process entry
        # point: euclid.exe. This must not be replaced with a libjulia module handle.
        module_handle = Base.@ccall "kernel32".GetModuleHandleW(
            C_NULL::Ptr{UInt16})::Ptr{Cvoid}
        module_handle == C_NULL && error("could not resolve Euclid executable module")

        pointer = Base.@ccall "kernel32".GetProcAddress(
            module_handle::Ptr{Cvoid}, String(name)::Cstring)::Ptr{Cvoid}
        pointer == C_NULL && error("could not resolve Euclid host symbol: $name")
        pointer
    end
end

"""
Call an Odin bridge export using Julia's typed `@ccall` syntax.

This module-local macro intentionally shadows `Base.@ccall` for the bridge wrapper
files. On Windows it rewrites the bare function name to a pointer resolved from the
Euclid executable, allowing calls compiled into a PackageCompiler sysimage to work.
Other platforms retain Julia's normal process-wide symbol lookup behavior.
"""
macro ccall(expression)
    if !Sys.iswindows()
        return esc(:(Base.@ccall $expression))
    end

    call_expression = expression.args[1]
    function_name = call_expression.args[1]
    function_name isa Symbol || error("Euclid bridge calls require a bare host symbol")

    # Base.@ccall represents a function-pointer callee as an interpolated AST node.
    # GlobalRef keeps the resolver bound to OdinJuliaBridge when this expansion is
    # compiled into a sysimage and later restored into an embedded Julia runtime.
    rewritten_call = copy(call_expression)
    resolver = GlobalRef(@__MODULE__, :host_symbol)
    rewritten_call.args[1] = Expr(:$, :($resolver($(QuoteNode(function_name)))))
    rewritten = Expr(:(::), rewritten_call, expression.args[2])
    return esc(:(Base.@ccall $rewritten))
end

"""
Raw document text and presentation metadata for one native bridge transaction.

Mirrors the Odin `Bridge_Dynview_Document_Request` ABI struct field-for-field.
"""
struct BridgeDynviewDocumentRequest
    source::Cstring
    fallback::Cstring
    block_kind::Int32
    block_id::Int32
    text_style::Int32
end

"""
Raw math text and presentation metadata for one native bridge transaction.

Mirrors the Odin `Bridge_Dynview_Math_Request` ABI struct field-for-field.
"""
struct BridgeDynviewMathRequest
    source::Cstring
    text_style::Int32
    math_style::Int32
    mathbb_style::Int32
    root_style::Int32
end

struct BridgeColor
    r::UInt8
    g::UInt8
    b::UInt8
    a::UInt8
end

"""
Fill plus five edge colors for one inline pentagon atom.

Mirrors the Odin `Bridge_Pentagon_Colors` ABI struct field-for-field.
"""
struct BridgePentagonColors
    fill::BridgeColor
    edge1::BridgeColor
    edge2::BridgeColor
    edge3::BridgeColor
    edge4::BridgeColor
    edge5::BridgeColor
end

"""
Fill plus three edge colors for one inline triangle atom.

Mirrors the Odin `Bridge_Triangle_Colors` ABI struct field-for-field.
"""
struct BridgeTriangleColors
    fill::BridgeColor
    edge1::BridgeColor
    edge2::BridgeColor
    edge3::BridgeColor
end

"""
Four independent edge colors for one inline box atom.

Mirrors the Odin `Bridge_Box_Edge_Colors` ABI struct field-for-field.
"""
struct BridgeBoxEdgeColors
    edge1::BridgeColor
    edge2::BridgeColor
    edge3::BridgeColor
    edge4::BridgeColor
end

"""
Fill and arc colors for one inline pie-section atom.

Mirrors the Odin `Bridge_Pie_Colors` ABI struct field-for-field.
"""
struct BridgePieColors
    fill::BridgeColor
    arc::BridgeColor
end

"""
Width, height, and stroke for one rectangular inline atom.

Mirrors the Odin `Bridge_Inline_Box_Dims` ABI struct field-for-field.
"""
struct BridgeInlineBoxDims
    width::Cfloat
    height::Cfloat
    stroke::Cfloat
end

"""
Width and height for one sized inline atom.

Mirrors the Odin `Bridge_Inline_Size` ABI struct field-for-field.
"""
struct BridgeInlineSize
    width::Cfloat
    height::Cfloat
end

"""
Top-bar length, stem height, and stroke for one inline perpendicular atom.

Mirrors the Odin `Bridge_Inline_Perpendicular_Dims` ABI struct field-for-field.
"""
struct BridgeInlinePerpendicularDims
    length::Cfloat
    stem_height::Cfloat
    stroke::Cfloat
end

"""
Top and stem colors for one inline perpendicular atom.

Mirrors the Odin `Bridge_Perpendicular_Colors` ABI struct field-for-field.
"""
struct BridgePerpendicularColors
    top::BridgeColor
    stem::BridgeColor
end

"""
Radius and sweep angles for one inline pie-section atom.

Mirrors the Odin `Bridge_Pie_Section_Geometry` ABI struct field-for-field.
"""
struct BridgePieSectionGeometry
    radius::Cfloat
    start_angle_degrees::Cfloat
    end_angle_degrees::Cfloat
    outline_stroke::Cfloat
end

"""
Radius and arc angle bounds for one circle shape.

Mirrors the Odin `Bridge_Arc_Geometry` ABI struct field-for-field.
"""
struct BridgeArcGeometry
    radius::Cfloat
    start_theta::Cfloat
    end_theta::Cfloat
end

"""
Glyph and decoration for one label point.

Mirrors the Odin `Bridge_Label_Glyph` ABI struct field-for-field.
"""
struct BridgeLabelGlyph
    label::UInt32
    decoration_kind::Int32
end

"""
Four vertices for one square shape.

Mirrors the Odin `Bridge_Square_Vertices` ABI struct field-for-field.
"""
struct BridgeSquareVertices
    vertices::NTuple{4, NTuple{3, Cfloat}}
end

"""
Five vertices for one pentagon shape.

Mirrors the Odin `Bridge_Pentagon_Vertices` ABI struct field-for-field.
"""
struct BridgePentagonVertices
    vertices::NTuple{5, NTuple{3, Cfloat}}
end

struct BridgePointView
    valid::UInt8
    index::Int64

    point_type::Int64
    do_draw::UInt8
    brush_size::Cfloat
    offset::Cfloat

    has_position::UInt8
    pos::NTuple{3, Cfloat}

    has_color::UInt8
    color::BridgeColor

    has_active_color::UInt8
    active_color::BridgeColor

    has_label::UInt8
    label::UInt32
    decoration_kind::Int32

    active_child::Int64
    child_count::Int64
    child_point_head::Int64
    next_child_point::Int64
end

struct BridgeConstraintView
    valid::UInt8
    index::Int32

    traits::Int32
    on_point::Int32
    restriction::NTuple{3, Cfloat}
    bounce::Cfloat
    allowance::Cfloat
    depend_on::Int32
    has_child_offset::UInt8
    child_offset::Int32
    do_apply::UInt8
end

struct BridgeConstraintSpec
    traits::Int32
    on_point::Int32
    restriction::NTuple{3, Cfloat}
    bounce::Cfloat
    allowance::Cfloat
    depend_on::Int32
    has_child_offset::UInt8
    child_offset::Int32
    do_apply::UInt8
end

struct BridgeSolveResult
    status::Int32
    iterations::Int32
    initial_error::Cfloat
    final_error::Cfloat
    converged::UInt8
end

struct BridgeShapeLine
    host_id::Int64
    joint1_id::Int64
    joint2_id::Int64
end

struct BridgeShapeCircle
    host_id::Int64
    start_id::Int64
    end_id::Int64
end

struct BridgeShapeFilledCircle
    host_id::Int64
    start_id::Int64
    end_id::Int64
end

struct BridgeShapeTriangle
    host_id::Int64
    joint1_id::Int64
    joint2_id::Int64
    joint3_id::Int64
end

struct BridgeShapeSquare
    host_id::Int64
    joint1_id::Int64
    joint2_id::Int64
    joint3_id::Int64
    joint4_id::Int64
end

struct BridgeShapePentagon
    host_id::Int64
    joint1_id::Int64
    joint2_id::Int64
    joint3_id::Int64
    joint4_id::Int64
    joint5_id::Int64
end

struct BridgeShapePen
    host_id::Int64
    joint1_id::Int64
    joint2_id::Int64

    length_constraint_id::Int64
    point1_floor_id::Int64
    point2_floor_id::Int64
    lock_point1_id::Int64
    lock_point2_id::Int64
end

struct BridgeShapeCompass
    host_id::Int64
    joint1_id::Int64
    pivot_id::Int64
    joint2_id::Int64

    center_pivot_id::Int64
    limb1_length_id::Int64
    limb2_length_id::Int64
    point1_floor_id::Int64
    pivot_floor_id::Int64
    point2_floor_id::Int64
    lock_point1_id::Int64
    lock_point2_id::Int64
end

const LABEL_DECORATION_NONE = Int32(0)
const LABEL_DECORATION_PRIME = Int32(1)
const LABEL_DECORATION_DOUBLEPRIME = Int32(2)
const LABEL_DECORATION_TRIPLEPRIME = Int32(3)
const LABEL_DECORATION_HAT = Int32(4)
const LABEL_DECORATION_BAR = Int32(5)

const BRIDGE_STATUS_OK = Int32(0)
const BRIDGE_STATUS_INVALID_INDEX = Int32(1)
const BRIDGE_STATUS_INVALID_ARGUMENT = Int32(2)
const BRIDGE_STATUS_INVALID_GRAPH = Int32(3)
const BRIDGE_STATUS_INVALID_CONSTRAINT = Int32(4)
const BRIDGE_STATUS_OUT_OF_CAPACITY = Int32(5)
const BRIDGE_STATUS_ILLEGAL_STATE = Int32(6)
const BRIDGE_STATUS_NON_CONVERGED = Int32(7)
const BRIDGE_STATUS_NOT_FOUND = Int32(8)
const BRIDGE_STATUS_SCHEMA_MISMATCH = Int32(9)

const BRIDGE_VERSION = Int32(5)
const BRIDGE_FEATURE_TYPED_ANIMATION_STATE = Int32(1 << 4)
const BRIDGE_FEATURE_ANIMATION_METADATA_CATALOG = Int32(1 << 5)

const BRIDGE_DYNVIEW_BLOCK_INPUT = Int32(1)
const BRIDGE_DYNVIEW_BLOCK_OUTPUT = Int32(2)
const BRIDGE_DYNVIEW_STYLE_DEFAULT = Int32(0)
const BRIDGE_DYNVIEW_STYLE_PROMPT = Int32(1)
const BRIDGE_DYNVIEW_STYLE_OUTPUT = Int32(2)
const BRIDGE_DYNVIEW_STYLE_ERROR = Int32(3)
const BRIDGE_DYNVIEW_STYLE_BOLD = Int32(10)
const BRIDGE_DYNVIEW_STYLE_ITALIC = Int32(11)
const BRIDGE_DYNVIEW_STYLE_CENTER = Int32(12)
const BRIDGE_DYNVIEW_STYLE_MEDIUM = Int32(13)
const BRIDGE_DYNVIEW_STYLE_SEMIBOLD = Int32(14)
const BRIDGE_DYNVIEW_STYLE_EXTRABOLD = Int32(15)
const BRIDGE_DYNVIEW_STYLE_BLACK = Int32(16)
const BRIDGE_DYNVIEW_STYLE_UNDERLINE = Int32(17)
const BRIDGE_DYNVIEW_STYLE_INLINE_ATOM = Int32(20)
const BRIDGE_DYNVIEW_STYLE_CUSTOM_FONT = Int32(1 << 24)
const BRIDGE_DYNVIEW_MATH_ROOT_DISPLAY = Int32(0)
const BRIDGE_DYNVIEW_MATH_ROOT_TEXT = Int32(1)
const BRIDGE_DYNVIEW_DELIMITER_KIND_NONE = Int32(0)
const BRIDGE_DYNVIEW_DELIMITER_KIND_LEFT_PAREN = Int32(1)
const BRIDGE_DYNVIEW_DELIMITER_KIND_RIGHT_PAREN = Int32(2)
const BRIDGE_DYNVIEW_DELIMITER_KIND_LEFT_BRACKET = Int32(3)
const BRIDGE_DYNVIEW_DELIMITER_KIND_RIGHT_BRACKET = Int32(4)
const BRIDGE_DYNVIEW_DELIMITER_KIND_LEFT_BRACE = Int32(5)
const BRIDGE_DYNVIEW_DELIMITER_KIND_RIGHT_BRACE = Int32(6)
const BRIDGE_DYNVIEW_DELIMITER_KIND_VERT = Int32(7)
const BRIDGE_DYNVIEW_DELIMITER_KIND_DOUBLE_VERT = Int32(8)
const BRIDGE_DYNVIEW_DELIMITER_KIND_LEFT_CEIL = Int32(9)
const BRIDGE_DYNVIEW_DELIMITER_KIND_RIGHT_CEIL = Int32(10)
const BRIDGE_DYNVIEW_DELIMITER_KIND_LEFT_FLOOR = Int32(11)
const BRIDGE_DYNVIEW_DELIMITER_KIND_RIGHT_FLOOR = Int32(12)
const BRIDGE_DYNVIEW_DELIMITER_KIND_LEFT_ANGLE = Int32(13)
const BRIDGE_DYNVIEW_DELIMITER_KIND_RIGHT_ANGLE = Int32(14)

const BRIDGE_DYNVIEW_FONT_FLAG_NONE = Int32(0)
const BRIDGE_DYNVIEW_FONT_FLAG_ITALIC = Int32(1 << 0)
const BRIDGE_DYNVIEW_FONT_FLAG_LIGHT = Int32(1 << 1)
const BRIDGE_DYNVIEW_FONT_FLAG_REGULAR = Int32(1 << 2)
const BRIDGE_DYNVIEW_FONT_FLAG_MEDIUM = Int32(1 << 3)
const BRIDGE_DYNVIEW_FONT_FLAG_SEMIBOLD = Int32(1 << 4)
const BRIDGE_DYNVIEW_FONT_FLAG_BOLD = Int32(1 << 5)
const BRIDGE_DYNVIEW_FONT_FLAG_EXTRABOLD = Int32(1 << 6)
const BRIDGE_DYNVIEW_FONT_FLAG_BLACK = Int32(1 << 7)

const CONSTRAINT_SPEC_TRAITS = Int32(1 << 0)
const CONSTRAINT_SPEC_ONPOINT = Int32(1 << 1)
const CONSTRAINT_SPEC_RESTRICTION = Int32(1 << 2)
const CONSTRAINT_SPEC_BOUNCE = Int32(1 << 3)
const CONSTRAINT_SPEC_ALLOWANCE = Int32(1 << 4)
const CONSTRAINT_SPEC_DEPENDON = Int32(1 << 5)
const CONSTRAINT_SPEC_CHILDOFFSET = Int32(1 << 6)
const CONSTRAINT_SPEC_DOAPPLY = Int32(1 << 7)

const ANIMATION_STABLE_ID_NAMESPACE = UUID("66f8da8f-bd5c-5f58-ae66-5cbaf6ea4d41")

"""
Build a dynview style id that carries explicit JuliaMono font variant flags.

Combine one or more `BRIDGE_DYNVIEW_FONT_FLAG_*` bits (including `ITALIC`) and
pass the resulting style id into `dynview_text_run`/`dynview_math_glyph_run`.
"""
dynview_style_with_font_flags(flags::Integer) =
    Int32(BRIDGE_DYNVIEW_STYLE_CUSTOM_FONT | Int32(flags))

"""
Derive a deterministic animation stable ID string from a semantic key.

This helper uses UUID v5 with a fixed project namespace so the same key always
produces the same identity across reloads.
"""
animation_stable_id_from_key(key::AbstractString) =
    string(uuid5(ANIMATION_STABLE_ID_NAMESPACE, String(key)))

"""
Construct a new BridgeColor from standard Julia color types

--------

Takes in a Julia color and returns `BridgeColor`
"""
function bridge_color(c::Colorant)
    rgba = RGBA(c)
    BridgeColor(
        UInt8(round(Int, rgba.r * 255.0)),
        UInt8(round(Int, rgba.g * 255.0)),
        UInt8(round(Int, rgba.b * 255.0)),
        UInt8(round(Int, rgba.alpha * 255.0)))
end

"""Return one named Julia logo color, or `nothing` for other color names."""
function julia_palette_color(name::AbstractString)
    if name == "julia_blue"
        return BridgeColor(0x40, 0x63, 0xd8, 0xff)
    elseif name == "julia_green"
        return BridgeColor(0x38, 0x98, 0x26, 0xff)
    elseif name == "julia_purple"
        return BridgeColor(0x95, 0x58, 0xb2, 0xff)
    elseif name == "julia_red"
        return BridgeColor(0xcb, 0x3c, 0x33, 0xff)
    end
    return nothing
end

function bridge_color(name::Symbol)
    text = String(name)
    palette_color = julia_palette_color(text)
    return palette_color === nothing ? bridge_color(parse(Colorant, text)) : palette_color
end
function bridge_color(name::AbstractString)
    palette_color = julia_palette_color(name)
    return palette_color === nothing ? bridge_color(parse(Colorant, name)) : palette_color
end
