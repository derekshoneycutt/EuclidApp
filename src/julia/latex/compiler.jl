"""Compile normalized runs to the recursive payload representation."""
function compile_emit_program(runs::Vector{LatexRun})
    return math_payload_ops_for_runs(runs)
end

"""Parse and normalize one LaTeX source without retaining mutable module state."""
function compile_latex_runs(source::AbstractString)
    _, ast = parse_latex(source)
    normalized_ast = normalize_runs(ast)
    return normalized_ast, compile_emit_program(normalized_ast)
end

"""Return compiled emit program for one latex input string."""
function compiled_program_for(
    source::AbstractString; style_profile::Integer=DEFAULT_STYLE_PROFILE)
    _ = style_profile
    _, program = compile_latex_runs(source)
    return program
end

"""Render one recursive payload op to canonical LaTeX-ish source."""
function latex_source_for_payload(op::MathPayloadOp)
    if op.kind == MATH_OP_SCRIPT_ATTACH_RECURSIVE
        parent = latex_source_for_program(op.children)
        return grouped_parent_with_script_suffix(parent, op.sup_text, op.sub_text)
    end

    return latex_source_for_recursive_payload(op)
end

"""Render one recursive program back to canonical LaTeX-ish source."""
function latex_source_for_program(program::Vector{MathPayloadOp})
    return join((latex_source_for_payload(op) for op in program), "")
end

"""Wrap rendered child text in the command represented by one accent payload."""
function accent_payload_text(op::MathPayloadOp, child_text::AbstractString)
    commands = Dict(
        :overline => "\\overline", :underline => "\\underline",
        :hat => "\\hat", :tilde => "\\tilde", :vec => "\\vec",
        :dot => "\\dot", :ddot => "\\ddot", :bar => "\\bar",
        :check => "\\check", :breve => "\\breve", :acute => "\\acute",
        :grave => "\\grave", :ring => "\\mathring",
        :overbrace => "\\overbrace", :underbrace => "\\underbrace")
    return get(commands, op.accent_mode, "\\overline") * "{" * child_text * "}"
end

"""Wrap rendered child text in one radical payload and its optional degree."""
function radical_payload_text(op::MathPayloadOp, child_text::AbstractString)
    if !isempty(op.radical_index_text)
        return "\\sqrt[" * op.radical_index_text * "]{" * child_text * "}"
    end
    return "\\sqrt{" * child_text * "}"
end

"""Render one recursive payload op to plain-text fallback form."""
function plain_text_for_recursive_payload(op::MathPayloadOp)
    if op.kind == MATH_OP_LARGE_OP_RECURSIVE
        return large_operator_with_limits(op.text, op.sup_text, op.sub_text)
    end

    if op.kind == MATH_OP_FRACTION_RECURSIVE
        numerator = plain_text_for_program(op.children)
        denominator = plain_text_for_program(op.secondary_children)
        return fraction_text(numerator, denominator)
    end

    if op.kind == MATH_OP_STRETCH_DELIMITER_RECURSIVE
        return stretch_delimiter_text(op.radical_index_text,
            plain_text_for_program(op.children), op.sup_text)
    end

    if op.kind == MATH_OP_MATRIX_RECURSIVE
        return matrix_payload_fallback_text(op, plain_text_for_payload)
    end

    if op.kind == MATH_OP_STYLE_OVERRIDE_RECURSIVE
        return plain_text_for_program(op.children)
    end

    if op.kind == MATH_OP_STACK_RECURSIVE
        return "(" * plain_text_for_program(op.children) * ";" *
            plain_text_for_program(op.secondary_children) * ")"
    end

    if op.kind == MATH_OP_ACCENT_BAR_RECURSIVE
        return accent_payload_text(op, plain_text_for_program(op.children))
    end

    if op.kind == MATH_OP_RADICAL_BAR_RECURSIVE
        return radical_payload_text(op, plain_text_for_program(op.children))
    end

    return op.text
end

"""Render one recursive payload op to plain-text fallback form."""
function plain_text_for_payload(op::MathPayloadOp)
    if op.kind == MATH_OP_SCRIPT_ATTACH_RECURSIVE
        parent = plain_text_for_program(op.children)
        return grouped_parent_with_script_suffix(parent, op.sup_text, op.sub_text)
    end
    return plain_text_for_recursive_payload(op)
end

"""Decode one mathematical alphabet glyph run to its ASCII source, when complete."""
function math_alphabet_source_text(text::AbstractString, role::Symbol)
    mapping = get(MATH_ALPHABET_SOURCE_MAPS, role, nothing)
    isnothing(mapping) && return nothing
    output = IOBuffer()
    for glyph in text
        source = get(mapping, glyph, nothing)
        isnothing(source) && return nothing
        write(output, source)
    end
    return String(take!(output))
end

"""Return canonical source for one payload atom, preserving structured commands."""
function latex_source_atom_text(op::MathPayloadOp)
    if op.style_role == :operatorname
        return "\\operatorname{" * op.text * "}"
    end
    source = math_alphabet_source_text(op.text, op.style_role)
    if !isnothing(source)
        return MATH_ALPHABET_ROLE_COMMANDS[op.style_role] * "{" * source * "}"
    end
    return op.text
end

"""Render one recursive program to a plain-text fallback payload."""
function plain_text_for_program(program::Vector{MathPayloadOp})
    return join((plain_text_for_payload(op) for op in program), "")
end

"""Resolve latex input to plain Unicode/text fallback."""
function latex_to_plain_text(
    source::AbstractString; style_profile::Integer=DEFAULT_STYLE_PROFILE)
    return plain_text_for_program(
        compiled_program_for(source; style_profile=style_profile))
end
