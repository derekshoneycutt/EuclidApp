const DEFAULT_STYLE_PROFILE = Int32(0)

const LATEX_PRIME_DOCUMENT = raw"""\textbf{Euclid} \textit{document} $x_1^2 \in \mathbb{R}$

\euclidpoint[color=steelblue,size=1] \euclidline[color=steelblue,length=3,thickness=2]

$$\frac{a+b}{\sqrt{c}}$$"""
const LATEX_PRIME_FALLBACK = "Euclid document x in R"

"""Submit one complete TeX document to Dynview and return its authored fallback."""
function emit_latex_view_text!(
    state_ptr::Ptr{Cvoid},
    source::AbstractString,
    fallback::AbstractString;
    block_kind::Integer=OdinJuliaBridge.BRIDGE_DYNVIEW_BLOCK_OUTPUT,
    block_id::Integer=1,
    text_style::Integer=OdinJuliaBridge.BRIDGE_DYNVIEW_STYLE_OUTPUT)

    fallback_text = String(fallback)
    OdinJuliaBridge.dynview_tex_document(
        state_ptr, source, fallback_text, block_kind, block_id, text_style)
    return fallback_text
end

"""Submit one TeX math fragment to Dynview's native parser."""
function replay_emit_math_block!(
    state_ptr::Ptr{Cvoid},
    source::AbstractString;
    style_profile::Integer=DEFAULT_STYLE_PROFILE,
    text_style::Integer=OdinJuliaBridge.BRIDGE_DYNVIEW_STYLE_OUTPUT,
    math_style::Integer=OdinJuliaBridge.BRIDGE_DYNVIEW_STYLE_ITALIC,
    mathbb_style::Integer=OdinJuliaBridge.dynview_style_with_font_flags(
        OdinJuliaBridge.BRIDGE_DYNVIEW_FONT_FLAG_REGULAR),
    root_style::Symbol=:display)

    _ = style_profile
    root_style == :display || root_style == :text || return false
    native_root_style = root_style == :text ?
        OdinJuliaBridge.BRIDGE_DYNVIEW_MATH_ROOT_TEXT :
        OdinJuliaBridge.BRIDGE_DYNVIEW_MATH_ROOT_DISPLAY
    status = OdinJuliaBridge.dynview_math_block(
        state_ptr, source, math_style;
        text_style=text_style,
        mathbb_style=mathbb_style,
        root_style=native_root_style)
    return status == OdinJuliaBridge.BRIDGE_STATUS_OK
end

"""Prime native TeX parsing and reset the transient Dynview stream."""
function prime_latex!(state_ptr::Ptr{Cvoid})
    emit_latex_view_text!(state_ptr, LATEX_PRIME_DOCUMENT, LATEX_PRIME_FALLBACK)
    status = OdinJuliaBridge.dynview_reset_stream(state_ptr)
    return status == OdinJuliaBridge.BRIDGE_STATUS_OK
end