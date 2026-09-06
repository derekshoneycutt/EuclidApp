"""
Provide stable Julia authoring facades for Dynview's native TeX implementation.

Dynview owns tokenization, parsing, normalization, semantic compilation, and rendering.
"""
module EuclidLatex

using ..OdinJuliaBridge

export replay_emit_math_block!,
    emit_latex_view_text!,
    prime_latex!

include("latex/facade.jl")

end
