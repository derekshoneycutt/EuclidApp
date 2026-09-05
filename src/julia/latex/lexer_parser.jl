
struct MatrixDimsParseResult
    rows::Int
    cols::Int
    ok::Bool
end


struct MatrixRowSeparatorResult
    consumed::Bool
    row_cells::Vector{Vector{LatexRun}}
    cell_runs::Vector{LatexRun}
    pending_break::Bool
end

struct MatrixRowsParseResult
    rows::Vector{Vector{Vector{LatexRun}}}
    row_extra_gaps::Vector{MathTableLength}
    horizontal_rule_counts::Vector{Int}
    ok::Bool
end

struct MatrixRowTerminatorResult
    consumed::Bool
    finished::Bool
    valid::Bool
end

struct ArrayPreambleSpec
    alignments::Vector{Char}
    boundary_defaults::Vector{Bool}
    vertical_rule_counts::Vector{Int}
    valid::Bool
end

const MATRIX_WRAPPER_DELIMITERS = Dict(
    "bmatrix" => ("[", "]"), "Bmatrix" => ("\\{", "\\}"),
    "pmatrix" => ("(", ")"), "vmatrix" => ("|", "|"),
    "Vmatrix" => ("\\|", "\\|"))
const TABLE_PRESET_ENVIRONMENTS = Set([
    "smallmatrix", "cases", "dcases", "aligned", "alignedat", "gathered", "subarray"])
const TABLE_ARGUMENT_ENVIRONMENTS = Set(["alignedat", "subarray"])
const TABLE_DIRECT_ENVIRONMENTS = Set([
    "smallmatrix", "aligned", "alignedat", "gathered", "subarray"])
const TABLE_SEMANTIC_SEGMENTS = Set([
    :smallmatrix, :aligned, :alignedat, :gathered, :subarray])
const TABLE_FIXED_COLUMN_COUNTS = Dict(
    "cases" => 2, "dcases" => 2, "gathered" => 1)
const SUBARRAY_ALIGNMENT_ARGUMENTS = Set(["l", "c"])

"""Map single punctuation characters to their token kinds."""
const PUNCTUATION_TOKEN_KINDS = Dict{Char,Symbol}(
    '{' => :lbrace,
    '}' => :rbrace,
    '^' => :sup,
    '_' => :sub,
    '[' => :lbracket,
    ']' => :rbracket,
    '&' => :amp)

"""Mutable row/cell accumulation state while parsing a matrix environment."""
mutable struct MatrixRowState
    rows::Vector{Vector{Vector{LatexRun}}}
    row_cells::Vector{Vector{LatexRun}}
    cell_runs::Vector{LatexRun}
    pending_row_break::Bool
    row_extra_gaps::Vector{MathTableLength}
    horizontal_rule_counts::Vector{Int}
end


"""Tokenize source into command/group/script/plain-text tokens."""
function tokenize_latex(source::AbstractString)
    tokens = LatexToken[]
    i = firstindex(source)
    while i <= lastindex(source)
        c = source[i]
        kind = get(PUNCTUATION_TOKEN_KINDS, c, :none)
        if kind != :none
            push!(tokens, LatexToken(kind, string(c)))
            i = nextind(source, i)
            continue
        end
        if c == '\\'
            token, next_i = read_command_token(source, i)
            push!(tokens, token)
            i = next_i
            continue
        end

        token, next_i = read_text_token(source, i)
        push!(tokens, token)
        i = next_i
    end

    return tokens
end

"""Read one LaTeX command token beginning at a backslash byte index."""
function read_command_token(source::AbstractString, slash_i::Int)
    i = nextind(source, slash_i)
    if i > lastindex(source)
        return LatexToken(:text, "\\"), i
    end

    c = source[i]
    if isletter(c)
        start_i = slash_i
        j = i
        while j <= lastindex(source) && isletter(source[j])
            j = nextind(source, j)
        end
        return LatexToken(:command, source[start_i:prevind(source, j)]), j
    end

    token = source[slash_i:i]
    return LatexToken(:command, token), nextind(source, i)
end

"""Read one plain-text token until the next control/syntax character."""
is_text_token_stop_char(c::Char) =
    c == '\\' || c == '{' || c == '}' || c == '^' ||
    c == '_' || c == '[' || c == ']' || c == '&'

"""Return true when one char is ASCII horizontal/vertical whitespace."""
is_ascii_space_char(c::Char) = c == ' ' || c == '\t' || c == '\n' || c == '\r'

"""Normalize explicit nonbreaking math-space markers to semantic input text."""
normalize_text_whitespace(text::AbstractString) =
    replace(String(text), "~" => NONBREAKING_SPACE)

"""Consume one command-delimiter whitespace run from the next text token."""
function consume_command_delimiter_whitespace!(
    tokens::Vector{LatexToken}, idx::Base.RefValue{Int})
    idx[] > length(tokens) && return nothing
    token = tokens[idx[]]
    if token.kind != :text || isempty(token.text)
        return nothing
    end

    start_i = firstindex(token.text)
    next_i = start_i
    while next_i <= lastindex(token.text) && is_ascii_space_char(token.text[next_i])
        next_i = nextind(token.text, next_i)
    end

    if next_i == start_i || next_i > lastindex(token.text)
        return nothing
    end

    next_char = token.text[next_i]
    if !isletter(next_char) && !isdigit(next_char)
        return nothing
    end

    tokens[idx[]] = LatexToken(:text, token.text[next_i:end])
    return nothing
end

"""Read one plain-text token until the next control/syntax character."""
function read_text_token(source::AbstractString, start_i::Int)
    j = start_i
    while j <= lastindex(source)
        if is_text_token_stop_char(source[j])
            break
        end
        j = nextind(source, j)
    end

    if j == start_i
        return LatexToken(:text, ""), j
    end

    return LatexToken(:text, source[start_i:prevind(source, j)]), j
end

"""Parse latex into semantic text/math runs for emission."""
function parse_latex(source::AbstractString)
    tokens = tokenize_latex(String(source))
    idx = Ref(1)
    runs = parse_sequence(tokens, idx, false)
    return tokens, runs
end

"""Parse a token sequence, optionally stopping at a closing brace token."""
function parse_sequence(
    tokens::Vector{LatexToken}, idx::Base.RefValue{Int}, stop_on_rbrace::Bool)
    runs = LatexRun[]
    while idx[] <= length(tokens)
        token = tokens[idx[]]
        if token.kind == :rbrace && stop_on_rbrace
            idx[] += 1
            break
        end

        if token.kind == :lbrace
            idx[] += 1
            append!(runs, parse_sequence(tokens, idx, true))
            continue
        end

        style = token.kind == :command ? get(EXPLICIT_MATH_STYLES, token.text, nothing) :
            nothing
        if !isnothing(style)
            idx[] += 1
            children = parse_sequence(tokens, idx, stop_on_rbrace)
            push!(runs, latex_style_override_run(style, children))
            return runs
        end

        append!(runs, parse_atom(tokens, idx))
        consume_scripts!(runs, tokens, idx)
    end

    return runs
end

const EXPLICIT_MATH_STYLES = Dict(
    "\\displaystyle" => :display,
    "\\textstyle" => :text,
    "\\scriptstyle" => :script,
    "\\scriptscriptstyle" => :script_script)

"""Parse one atom token into a semantic run list."""
function parse_atom(tokens::Vector{LatexToken}, idx::Base.RefValue{Int})
    token = tokens[idx[]]
    idx[] += 1

    if token.kind == :text
        return normal_math_atom_runs(normalize_text_whitespace(token.text))
    end

    if token.kind != :command
        return normal_math_atom_runs(token.text)
    end

    return parse_command_atom(token.text, tokens, idx)
end

"""Parse one command token into a semantic run list."""
function parse_command_atom(
    command::AbstractString,
    tokens::Vector{LatexToken},
    idx::Base.RefValue{Int})

    if command in COMMANDS_IGNORE_TRAILING_SPACE
        consume_command_delimiter_whitespace!(tokens, idx)
    end

    if haskey(FIXED_DELIMITER_COMMANDS, command)
        delimiter, ok = parse_stretch_delimiter_token!(tokens, idx)
        if !ok
            return normal_math_atom_runs(command)
        end
        size, atom_class = FIXED_DELIMITER_COMMANDS[command]
        return [latex_fixed_delimiter_run(delimiter, size, atom_class)]
    end

    text_runs = parse_special_text_command(command, tokens, idx)
    if !isnothing(text_runs)
        return text_runs
    end

    operator_runs = parse_operatorname_atom!(command, tokens, idx)
    if !isnothing(operator_runs)
        return operator_runs
    end

    registered_runs = parse_registered_command_atom(command, tokens, idx)
    if !isnothing(registered_runs)
        return registered_runs
    end

    if haskey(OPERATOR_LIMIT_MODIFIER_SEGMENTS, command)
        return [latex_atom_run(command, :math_upright)]
    end

    return normal_math_atom_runs(command)
end

"""Parse one registered glue, fixed, alphabet, or structured command."""
function parse_registered_command_atom(
    command::AbstractString,
    tokens::Vector{LatexToken},
    idx::Base.RefValue{Int})

    glue_runs = parse_explicit_glue_command(command)
    !isnothing(glue_runs) && return glue_runs
    fixed_runs = parse_fixed_math_command(command)
    !isnothing(fixed_runs) && return fixed_runs
    alphabet_runs = parse_math_alphabet_atom(command, tokens, idx)
    !isnothing(alphabet_runs) && return alphabet_runs
    return parse_structured_math_command(command, tokens, idx)
end

"""Parse supported explicit math-space commands into semantic glue runs."""
function parse_explicit_glue_command(command::AbstractString)
    command == "\\;" && return [latex_glue_run(" ", MATH_GLUE_THICK)]
    (command == "\\:" || command == "\\>") &&
        return [latex_glue_run(" ", MATH_GLUE_SPACE)]
    command == "\\ " && return [latex_glue_run(" ", MATH_GLUE_SPACE)]
    command == "\\enspace" && return [latex_glue_run(" ", MATH_GLUE_SPACE)]
    command == "\\!" && return [latex_glue_run("", MATH_GLUE_NEGATIVE_THIN)]
    command == "\\quad" && return [latex_glue_run(" ", MATH_GLUE_QUAD)]
    command == "\\qquad" && return [latex_glue_run("  ", MATH_GLUE_QUAD)]
    command == "\\," && return [latex_glue_run(" ", MATH_GLUE_THIN)]
    return nothing
end

"""Parse one fixed math command using its registered semantic classification."""
function parse_fixed_math_command(command::AbstractString)
    spec = get(MATH_COMMAND_REGISTRY, command, nothing)
    if isnothing(spec)
        return nothing
    end

    return [latex_atom_run(spec.output, spec.role, spec.atom_class)]
end

"""Parse special command forms that produce plain text runs."""
function parse_special_text_command(
    command::AbstractString,
    tokens::Vector{LatexToken},
    idx::Base.RefValue{Int})

    if command == "\\text" || command == "\\mathrm"
        return [latex_atom_run(
            parse_required_group_as_text(tokens, idx), :text, MATH_ATOM_ORD)]
    end

    return nothing
end

"""Consume one leading asterisk from a text token when present."""
function consume_optional_asterisk!(
    tokens::Vector{LatexToken}, idx::Base.RefValue{Int})

    idx[] > length(tokens) && return false
    token = tokens[idx[]]
    if token.kind != :text || isempty(token.text) || first(token.text) != '*'
        return false
    end

    next_index = nextind(token.text, firstindex(token.text))
    if next_index <= lastindex(token.text)
        tokens[idx[]] = LatexToken(:text, token.text[next_index:end])
    else
        idx[] += 1
    end
    return true
end

"""Parse `\\operatorname` and its starred display-limit form as upright Op atoms."""
function parse_operatorname_atom!(
    command::AbstractString,
    tokens::Vector{LatexToken},
    idx::Base.RefValue{Int})

    command == "\\operatorname" || return nothing
    original_index = idx[]
    original_token = original_index <= length(tokens) ? tokens[original_index] : nothing
    starred = consume_optional_asterisk!(tokens, idx)
    if idx[] > length(tokens) || tokens[idx[]].kind != :lbrace
        idx[] = original_index
        !isnothing(original_token) && (tokens[original_index] = original_token)
        return normal_math_atom_runs(command)
    end

    text = parse_required_group_as_text(tokens, idx)
    role = starred ? :operatorname_star : :operatorname
    return [latex_atom_run(text, role, MATH_ATOM_OP)]
end

"""Parse one over/under annotation or brace command when recognized."""
function parse_math_annotation_command(
    command::AbstractString,
    tokens::Vector{LatexToken},
    idx::Base.RefValue{Int})

    if command == "\\overset" || command == "\\underset"
        annotation = parse_required_group_runs(tokens, idx)
        base = parse_required_group_runs(tokens, idx)
        run = command == "\\overset" ? latex_overset_run(annotation, base) :
            latex_underset_run(annotation, base)
        return [run]
    end
    if command == "\\overbrace" || command == "\\underbrace"
        children = parse_required_group_runs(tokens, idx)
        segment = command == "\\overbrace" ? :accent_overbrace : :accent_underbrace
        return [latex_glyph_accent_run(segment, children)]
    end
    return nothing
end

"""Parse one grouped mathematical alphabet command using its verified Unicode map."""
function parse_math_alphabet_atom(
    command::AbstractString,
    tokens::Vector{LatexToken},
    idx::Base.RefValue{Int})

    spec = get(MATH_ALPHABET_COMMANDS, command, nothing)
    if isnothing(spec)
        return nothing
    end

    role, mapping = spec
    unicode, parsed = parse_math_alphabet_command(tokens, idx, mapping)
    if parsed
        return [latex_atom_run(unicode, role)]
    end

    return normal_math_atom_runs(command)
end

const FRACTION_VARIANT_STYLES = Dict(
    "\\frac" => nothing, "\\dfrac" => :display, "\\tfrac" => :text)

const BINOMIAL_VARIANT_STYLES = Dict(
    "\\binom" => nothing, "\\dbinom" => :display, "\\tbinom" => :text)

const GLYPH_ACCENT_COMMANDS = Dict(
    "\\hat" => :accent_hat, "\\widehat" => :accent_hat,
    "\\tilde" => :accent_tilde, "\\widetilde" => :accent_tilde,
    "\\vec" => :accent_vec, "\\dot" => :accent_dot,
    "\\ddot" => :accent_ddot, "\\bar" => :accent_bar,
    "\\check" => :accent_check, "\\breve" => :accent_breve,
    "\\acute" => :accent_acute, "\\grave" => :accent_grave,
    "\\mathring" => :accent_ring)

"""Parse a fraction variant and apply its optional explicit style."""
function parse_fraction_variant(
    command::AbstractString,
    tokens::Vector{LatexToken},
    idx::Base.RefValue{Int})

    numerator = parse_required_group_runs(tokens, idx)
    denominator = parse_required_group_runs(tokens, idx)
    fraction = latex_fraction_run(numerator, denominator)
    style = FRACTION_VARIANT_STYLES[command]
    return style === nothing ? fraction : latex_style_override_run(style, [fraction])
end

"""Parse a binomial variant as a delimited ruleless stack with optional style."""
function parse_binomial_variant(
    command::AbstractString,
    tokens::Vector{LatexToken},
    idx::Base.RefValue{Int})

    top = parse_required_group_runs(tokens, idx)
    bottom = parse_required_group_runs(tokens, idx)
    stack = latex_stack_run(top, bottom)
    delimited = latex_stretch_delimiter_run("(", ")", [stack])
    style = BINOMIAL_VARIANT_STYLES[command]
    return style === nothing ? delimited : latex_style_override_run(style, [delimited])
end

"""Parse one accent or over/under annotation command when recognized."""
function parse_math_decoration_command(
    command::AbstractString,
    tokens::Vector{LatexToken},
    idx::Base.RefValue{Int})

    if command == "\\overline" || command == "\\underline"
        children = parse_required_group_runs(tokens, idx)
        run = command == "\\overline" ? latex_overline_run(children) :
            latex_underline_run(children)
        return [run]
    end
    if haskey(GLYPH_ACCENT_COMMANDS, command)
        children = parse_math_argument_runs(tokens, idx)
        return [latex_glyph_accent_run(GLYPH_ACCENT_COMMANDS[command], children)]
    end
    return parse_math_annotation_command(command, tokens, idx)
end

"""Parse structured math commands that produce child-run nodes."""
function parse_structured_math_command(
    command::AbstractString,
    tokens::Vector{LatexToken},
    idx::Base.RefValue{Int})

    decoration = parse_math_decoration_command(command, tokens, idx)
    if decoration !== nothing
        return decoration
    end

    if command == "\\sqrt"
        return [parse_sqrt_run(tokens, idx)]
    end

    if haskey(FRACTION_VARIANT_STYLES, command)
        return [parse_fraction_variant(command, tokens, idx)]
    end

    if haskey(BINOMIAL_VARIANT_STYLES, command)
        return [parse_binomial_variant(command, tokens, idx)]
    end

    if command == "\\left"
        stretch_run, _ = parse_stretch_delimiter_run(tokens, idx)
        return [stretch_run]
    end

    if command == "\\begin"
        matrix_run, ok = parse_matrix_environment(tokens, idx)
        if ok
            return [matrix_run]
        end
        return [latex_atom_run("\\begin", :math)]
    end

    return nothing
end

"""Parse positive integer text, returning `(value, valid)` for matrix metadata fields."""
function parse_positive_int(text::AbstractString)
    value = 0
    if isempty(text)
        return 0, false
    end

    for c in text
        if c < '0' || c > '9'
            return 0, false
        end
        value = value * 10 + (Int(c) - Int('0'))
    end

    return value, value > 0
end

"""Parse compact matrix dimension text (`rows,cols`) into `(rows, cols, valid)`."""
function parse_matrix_dims_text(text::AbstractString)
    parts = split(text, ","; limit=2)
    if length(parts) != 2
        return MatrixDimsParseResult(0, 0, false)
    end

    rows, rows_ok = parse_positive_int(parts[1])
    cols, cols_ok = parse_positive_int(parts[2])
    return MatrixDimsParseResult(rows, cols, rows_ok && cols_ok)
end

"""Return fallback atom used when environment parsing fails."""
matrix_parse_fallback() = latex_atom_run("\\begin", :math)

"""Return true when one environment name is matrix-like and supported."""
is_matrix_like_environment(env_name::AbstractString) =
    env_name == "matrix" || env_name == "array" ||
    haskey(MATRIX_WRAPPER_DELIMITERS, env_name) || env_name in TABLE_PRESET_ENVIRONMENTS

"""Normalize one array alignment preamble by removing all whitespace."""
function normalize_array_preamble_text(text::AbstractString)
    io = IOBuffer()
    for c in text
        if !isspace(c)
            write(io, c)
        end
    end
    return String(take!(io))
end

"""Parse the bounded array preamble into columns and boundary directives."""
function parse_array_preamble_spec(text::AbstractString)
    alignments = Char[]
    boundary_defaults = Bool[true]
    vertical_rule_counts = Int[0]
    index = firstindex(text)
    while index <= lastindex(text)
        index, ok = consume_array_preamble_item!(
            text, index, alignments, boundary_defaults, vertical_rule_counts)
        ok || return ArrayPreambleSpec(
            alignments, boundary_defaults, vertical_rule_counts, false)
    end
    valid = !isempty(alignments) && length(boundary_defaults) == length(alignments) + 1
    return ArrayPreambleSpec(
        alignments, boundary_defaults, vertical_rule_counts, valid)
end

"""Consume one alignment, rule, or empty insertion from an array preamble."""
function consume_array_preamble_item!(
    text::AbstractString, index::Int, alignments::Vector{Char},
    boundary_defaults::Vector{Bool}, vertical_rule_counts::Vector{Int})

    char = text[index]
    if char == 'l' || char == 'c' || char == 'r'
        length(alignments) >= 16 && return index, false
        push!(alignments, char)
        push!(boundary_defaults, true)
        push!(vertical_rule_counts, 0)
        return nextind(text, index), true
    end
    if char == '|'
        vertical_rule_counts[end] += 1
        return nextind(text, index), vertical_rule_counts[end] <= 2
    end
    if startswith(SubString(text, index), "@{}")
        boundary_defaults[end] = false
        return nextind(text, index, 3), true
    end
    return index, false
end

"""Collect one required group as raw token text while preserving nested braces."""
function parse_required_group_token_text(
    tokens::Vector{LatexToken}, idx::Base.RefValue{Int})

    if idx[] > length(tokens) || tokens[idx[]].kind != :lbrace
        return "", false
    end
    idx[] += 1
    depth = 1
    io = IOBuffer()
    while idx[] <= length(tokens)
        token = tokens[idx[]]
        idx[] += 1
        if token.kind == :lbrace
            depth += 1
        elseif token.kind == :rbrace
            depth -= 1
            depth == 0 && return String(take!(io)), true
        end
        write(io, token.text)
    end
    return "", false
end

"""Parse and validate one required `{...}` array alignment preamble."""
function parse_array_alignment_preamble(
    tokens::Vector{LatexToken}, idx::Base.RefValue{Int})
    preamble_source, group_ok = parse_required_group_token_text(tokens, idx)
    group_ok || return "", false
    preamble = normalize_array_preamble_text(preamble_source)
    if !parse_array_preamble_spec(preamble).valid
        return "", false
    end
    return preamble, true
end

"""Advance token cursor to matching `\\end{...}` after environment-parse failure recovery."""
function skip_environment_body!(
    tokens::Vector{LatexToken}, idx::Base.RefValue{Int}, env_name::AbstractString)
    while idx[] <= length(tokens)
        token = tokens[idx[]]
        if token.kind == :command && token.text == "\\end"
            idx[] += 1
            end_name = parse_required_group_as_text(tokens, idx)
            if end_name == String(env_name)
                break
            end
            continue
        end

        idx[] += 1
    end

    return nothing
end

"""Return true when a subarray has one column and a supported alignment argument."""
function subarray_columns_ok(cols::Int, environment_argument::AbstractString)
    return cols == 1 && environment_argument in SUBARRAY_ALIGNMENT_ARGUMENTS
end

"""Return true when alignedat's pair count is bounded and matches its columns."""
function alignedat_columns_ok(cols::Int, environment_argument::AbstractString)
    pair_count, count_ok = parse_positive_int(environment_argument)
    return count_ok && pair_count <= 8 && cols == pair_count * 2
end

"""Return true when one preset environment accepts its parsed column shape."""
function table_environment_columns_ok(
    env_name::AbstractString, cols::Int, environment_argument::AbstractString)

    env_name == "array" && return false
    fixed_columns = get(TABLE_FIXED_COLUMN_COUNTS, env_name, 0)
    fixed_columns > 0 && return cols == fixed_columns
    env_name == "aligned" && return cols >= 2 && iseven(cols)
    env_name == "subarray" && return subarray_columns_ok(cols, environment_argument)
    env_name == "alignedat" && return alignedat_columns_ok(cols, environment_argument)
    return true
end

"""Return true when matrix-like environment metadata agrees with parsed cell shape."""
function matrix_environment_metadata_ok(
    env_name::AbstractString, array_preamble::AbstractString,
    matrix_rows::Vector{Vector{Vector{LatexRun}}}, environment_argument::AbstractString)

    isempty(matrix_rows) && return false
    cols = length(matrix_rows[1])
    env_name == "array" &&
        return length(parse_array_preamble_spec(array_preamble).alignments) == cols
    return table_environment_columns_ok(env_name, cols, environment_argument)
end

"""Return fixed boundary lengths for one preset table environment."""
function table_preset_boundary_gaps(env_name::AbstractString, columns::Int)
    gaps = fill(MathTableLength(0.0f0, :default), columns + 1)
    if env_name in ("cases", "dcases")
        fill!(gaps, MathTableLength(0.0f0, :zero))
        gaps[2] = MathTableLength(1.0f0, :em)
    elseif env_name in ("aligned", "alignedat")
        fill!(gaps, MathTableLength(0.0f0, :zero))
        if env_name == "aligned"
            for boundary in 3:2:columns
                gaps[boundary] = MathTableLength(1.0f0, :em)
            end
        end
    end
    return gaps
end

"""Build one typed descriptor preset for a validated table environment."""
function table_environment_descriptor(
    env_name::AbstractString, columns::Int, row_result::MatrixRowsParseResult,
    environment_argument::AbstractString)

    alignments = fill('c', columns)
    cell_style = :text
    row_spacing = :matrix
    if env_name in ("cases", "dcases")
        alignments .= 'l'
        cell_style = env_name == "dcases" ? :display : :text
        row_spacing = :cases
    elseif env_name in ("aligned", "alignedat")
        alignments = [isodd(index) ? 'r' : 'l' for index in 1:columns]
        cell_style = :display
        row_spacing = :alignment
    elseif env_name == "gathered"
        cell_style = :display
        row_spacing = :alignment
    elseif env_name in ("smallmatrix", "subarray")
        cell_style = :script
        row_spacing = :tight
        env_name == "subarray" && (alignments[1] = only(environment_argument))
    end
    return MathTableSemanticDescriptor(
        alignments, table_preset_boundary_gaps(env_name, columns),
        fill(0, columns + 1), row_result.row_extra_gaps,
        row_result.horizontal_rule_counts, cell_style, row_spacing)
end

"""Return one matrix-like semantic run for parsed environment name and cells."""
function matrix_environment_run(
    env_name::AbstractString,
    rows::Int,
    cols::Int,
    cells::Vector{LatexRun},
    array_preamble::AbstractString,
    descriptor::Union{Nothing,MathTableSemanticDescriptor})

    if env_name == "array"
        descriptor isa MathTableSemanticDescriptor || return matrix_parse_fallback()
        return latex_array_run(rows, cols, cells, array_preamble, descriptor)
    end

    if env_name in ("cases", "dcases")
        descriptor isa MathTableSemanticDescriptor || return matrix_parse_fallback()
        table_run = latex_table_run(rows, cols, cells, :array, descriptor, "ll")
        return latex_stretch_delimiter_run("\\{", ".", [table_run])
    end

    if env_name in TABLE_DIRECT_ENVIRONMENTS
        descriptor isa MathTableSemanticDescriptor || return matrix_parse_fallback()
        return latex_table_run(
            rows, cols, cells, Symbol(env_name), descriptor, array_preamble)
    end

    if haskey(MATRIX_WRAPPER_DELIMITERS, env_name)
        left, right = MATRIX_WRAPPER_DELIMITERS[env_name]
        matrix_run = latex_matrix_run(rows, cols, cells)
        return latex_stretch_delimiter_run(left, right, [matrix_run])
    end

    return latex_matrix_run(rows, cols, cells)
end

"""Parse one bounded signed table length in pt, em, or ex units."""
function parse_math_table_length(text::AbstractString)
    matched = match(r"^([+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+))(pt|em|ex)$", text)
    matched === nothing && return MathTableLength(0.0f0, :zero), false
    value_text = something(matched.captures[1], "")
    value = tryparse(Float32, value_text)
    if value === nothing || !isfinite(value) || abs(value) > 1024.0f0
        return MathTableLength(0.0f0, :zero), false
    end
    unit_text = something(matched.captures[2], "")
    return MathTableLength(value, Symbol(unit_text)), true
end

"""Consume an optional signed row addition immediately after a row separator."""
function parse_optional_matrix_row_gap!(
    tokens::Vector{LatexToken}, idx::Base.RefValue{Int})

    if idx[] > length(tokens) || tokens[idx[]].kind != :lbracket
        return MathTableLength(0.0f0, :zero), true
    end
    idx[] += 1
    io = IOBuffer()
    while idx[] <= length(tokens) && tokens[idx[]].kind != :rbracket
        write(io, tokens[idx[]].text)
        idx[] += 1
    end
    if idx[] > length(tokens)
        return MathTableLength(0.0f0, :zero), false
    end
    idx[] += 1
    return parse_math_table_length(normalize_array_preamble_text(String(take!(io))))
end

"""Consume one legal array horizontal rule at the current row boundary."""
function consume_array_hline!(
    token::LatexToken, idx::Base.RefValue{Int}, env_name::AbstractString,
    state::MatrixRowState)

    if token.kind != :command || token.text != "\\hline"
        return false, true
    end
    if env_name != "array" || !matrix_builders_empty(state.row_cells, state.cell_runs)
        return true, false
    end
    state.horizontal_rule_counts[end] += 1
    state.horizontal_rule_counts[end] <= 2 || return true, false
    idx[] += 1
    return true, true
end

"""Append one normalized matrix cell to the active matrix-row buffer."""
function push_matrix_cell!(
    row_cells::Vector{Vector{LatexRun}}, cell_runs::Vector{LatexRun})
    cell_runs = trim_matrix_cell_edge_whitespace(cell_runs)
    push!(row_cells, normalize_runs(cell_runs))
    return LatexRun[]
end

"""Return true when run is one plain math atom with no structured children."""
is_plain_math_atom(run::LatexRun) =
    run.segment == :atom &&
    run.role in (:math, :math_italic, :math_upright) && isempty(run.children) &&
    isempty(run.secondary_children)

"""Trim left edge whitespace from first matrix/array cell run when plain atom text."""
function trim_matrix_cell_first_edge!(runs::Vector{LatexRun})
    if isempty(runs)
        return nothing
    end

    first_run = runs[1]
    if !is_plain_math_atom(first_run)
        return nothing
    end

    text = String(lstrip(first_run.text))
    if isempty(text)
        deleteat!(runs, 1)
    else
        runs[1] = latex_atom_run(text, first_run.role)
    end

    return nothing
end

"""Trim right edge whitespace from last matrix/array cell run when plain atom text."""
function trim_matrix_cell_last_edge!(runs::Vector{LatexRun})
    if isempty(runs)
        return nothing
    end

    last_index = length(runs)
    last_run = runs[last_index]
    if !is_plain_math_atom(last_run)
        return nothing
    end

    text = String(rstrip(last_run.text))
    if isempty(text)
        deleteat!(runs, last_index)
    else
        runs[last_index] = latex_atom_run(text, last_run.role)
    end

    return nothing
end

"""Trim matrix/array cell edge whitespace from first/last plain atom runs only."""
function trim_matrix_cell_edge_whitespace(cell_runs::Vector{LatexRun})
    if isempty(cell_runs)
        return cell_runs
    end

    runs = copy(cell_runs)
    trim_matrix_cell_first_edge!(runs)
    trim_matrix_cell_last_edge!(runs)
    return runs
end

"""Trim leading whitespace only when it includes a line break at matrix/array cell start."""
function trim_leading_matrix_newline_whitespace(text::AbstractString)
    if isempty(text)
        return text, false
    end

    i = firstindex(text)
    saw_newline = false
    while i <= lastindex(text) && isspace(text[i])
        if text[i] == '\n' || text[i] == '\r'
            saw_newline = true
        end
        i = nextind(text, i)
    end

    if !saw_newline
        return text, false
    end
    if i > lastindex(text)
        return "", true
    end

    return text[i:end], true
end

"""Drop leading whitespace from one text token when it starts a matrix/array cell."""
function trim_matrix_cell_start_token!(
    tokens::Vector{LatexToken}, idx::Base.RefValue{Int}, cell_runs::Vector{LatexRun})
    if !isempty(cell_runs) || idx[] > length(tokens)
        return false
    end

    token = tokens[idx[]]
    if token.kind != :text || isempty(token.text)
        return false
    end

    stripped, trimmed = trim_leading_matrix_newline_whitespace(token.text)
    if !trimmed
        return false
    end

    if isempty(stripped)
        idx[] += 1
        return true
    end

    tokens[idx[]] = LatexToken(:text, stripped)
    return false
end

"""Append one completed matrix row and reset row/cell builders."""
function push_matrix_row!(
    matrix_rows::Vector{Vector{Vector{LatexRun}}}, row_cells::Vector{Vector{LatexRun}},
     cell_runs::Vector{LatexRun})
    cell_runs = push_matrix_cell!(row_cells, cell_runs)
    push!(matrix_rows, row_cells)
    return Vector{Vector{LatexRun}}(), cell_runs
end

"""Return true when current matrix builders have no active row/cell content."""
matrix_builders_empty(
    row_cells::Vector{Vector{LatexRun}}, cell_runs::Vector{LatexRun}) =
    isempty(row_cells) && isempty(cell_runs)

"""Return true when token is ignorable whitespace before the first cell in one row."""
function is_leading_matrix_row_whitespace(
    token::LatexToken, row_cells::Vector{Vector{LatexRun}}, cell_runs::Vector{LatexRun})
    if token.kind != :text
        return false
    end
    if !matrix_builders_empty(row_cells, cell_runs)
        return false
    end
    return isempty(strip(token.text))
end

"""Consume one matrix cell separator token (`&`) when present."""
function consume_matrix_cell_separator!(
    token::LatexToken, idx::Base.RefValue{Int}, row_cells::Vector{Vector{LatexRun}},
    cell_runs::Vector{LatexRun})
    if token.kind != :amp
        return false, cell_runs
    end

    idx[] += 1
    return true, push_matrix_cell!(row_cells, cell_runs)
end

"""Consume one matrix row separator token (`\\`) when present."""
function consume_matrix_row_separator!(
    token::LatexToken,
    idx::Base.RefValue{Int},
    matrix_rows::Vector{Vector{Vector{LatexRun}}},
    row_cells::Vector{Vector{LatexRun}},
    cell_runs::Vector{LatexRun})

    if token.kind != :command || token.text != "\\\\"
        return MatrixRowSeparatorResult(false, row_cells, cell_runs, false)
    end

    idx[] += 1
    if matrix_builders_empty(row_cells, cell_runs)
        return MatrixRowSeparatorResult(true, row_cells, cell_runs, true)
    end

    row_cells, cell_runs = push_matrix_row!(matrix_rows, row_cells, cell_runs)
    return MatrixRowSeparatorResult(true, row_cells, cell_runs, true)
end

"""Consume one matrix environment end marker and finalize builders when valid."""
function consume_matrix_environment_end!(
    token::LatexToken,
    tokens::Vector{LatexToken},
    idx::Base.RefValue{Int},
    env_name::AbstractString,
    matrix_rows::Vector{Vector{Vector{LatexRun}}},
    row_cells::Vector{Vector{LatexRun}},
    cell_runs::Vector{LatexRun},
    pending_row_break::Bool)

    if token.kind != :command || token.text != "\\end"
        return false, false
    end

    idx[] += 1
    end_name = parse_required_group_as_text(tokens, idx)
    if end_name != String(env_name)
        return true, false
    end

    if matrix_builders_empty(row_cells, cell_runs)
        return true, pending_row_break
    end

    _, _ = push_matrix_row!(matrix_rows, row_cells, cell_runs)
    return true, true
end

"""Parse matrix-like cell grid rows until matching `\\end{...}` and return row-major rows/cells."""
function parse_matrix_rows(
    tokens::Vector{LatexToken}, idx::Base.RefValue{Int}, env_name::AbstractString)
    state = MatrixRowState(
        Vector{Vector{Vector{LatexRun}}}(), Vector{Vector{LatexRun}}(), LatexRun[], false,
        MathTableLength[], Int[0])
    while idx[] <= length(tokens)
        finished, end_ok = step_matrix_row!(tokens, idx, env_name, state)
        finished && return MatrixRowsParseResult(
            state.rows, state.row_extra_gaps, state.horizontal_rule_counts, end_ok)
    end

    return MatrixRowsParseResult(
        state.rows, state.row_extra_gaps, state.horizontal_rule_counts, false)
end

"""Advance matrix-row parsing by one token, returning whether the environment closed."""
function step_matrix_row!(
    tokens::Vector{LatexToken}, idx::Base.RefValue{Int},
    env_name::AbstractString, state::MatrixRowState)

    if trim_matrix_cell_start_token!(tokens, idx, state.cell_runs)
        return false, false
    end

    token = tokens[idx[]]

    consumed_hline, hline_ok = consume_array_hline!(token, idx, env_name, state)
    consumed_hline && return !hline_ok, hline_ok

    if is_leading_matrix_row_whitespace(token, state.row_cells, state.cell_runs)
        idx[] += 1
        return false, false
    end

    consumed_cell_sep, next_cell_runs =
        consume_matrix_cell_separator!(token, idx, state.row_cells, state.cell_runs)
    if consumed_cell_sep
        state.cell_runs = next_cell_runs
        state.pending_row_break = false
        return false, false
    end

    terminator = consume_matrix_row_terminator!(
        token, tokens, idx, env_name, state)
    terminator.consumed && return terminator.finished, terminator.valid

    consume_matrix_atom!(tokens, idx, token, state)
    return false, false
end

"""Consume an environment end or row separator and update typed row metadata."""
function consume_matrix_row_terminator!(
    token::LatexToken, tokens::Vector{LatexToken}, idx::Base.RefValue{Int},
    env_name::AbstractString, state::MatrixRowState)

    row_count = length(state.rows)
    consumed_end, end_ok = consume_matrix_environment_end!(token, tokens, idx,
        env_name, state.rows, state.row_cells, state.cell_runs, state.pending_row_break)
    if consumed_end
        if end_ok && length(state.rows) > row_count
            push!(state.row_extra_gaps, MathTableLength(0.0f0, :zero))
            push!(state.horizontal_rule_counts, 0)
        end
        return MatrixRowTerminatorResult(true, true, end_ok)
    end
    result = consume_matrix_row_separator!(
        token, idx, state.rows, state.row_cells, state.cell_runs)
    result.consumed || return MatrixRowTerminatorResult(false, false, true)
    state.row_cells = result.row_cells
    state.cell_runs = result.cell_runs
    state.pending_row_break = result.pending_break
    if length(state.rows) > row_count
        gap, gap_ok = parse_optional_matrix_row_gap!(tokens, idx)
        gap_ok || return MatrixRowTerminatorResult(true, true, false)
        push!(state.row_extra_gaps, gap)
        push!(state.horizontal_rule_counts, 0)
    end
    return MatrixRowTerminatorResult(true, false, true)
end

"""Append one braced group or atom to the current matrix cell."""
function consume_matrix_atom!(
    tokens::Vector{LatexToken}, idx::Base.RefValue{Int},
    token::LatexToken, state::MatrixRowState)

    if token.kind == :lbrace
        idx[] += 1
        append!(state.cell_runs, parse_sequence(tokens, idx, true))
    else
        append!(state.cell_runs, parse_atom(tokens, idx))
        consume_scripts!(state.cell_runs, tokens, idx)
    end
    state.pending_row_break = false
end

"""Return true when all matrix rows are non-empty and have equal column counts."""
function matrix_rows_valid(matrix_rows::Vector{Vector{Vector{LatexRun}}})
    if isempty(matrix_rows)
        return false
    end

    cols = length(matrix_rows[1])
    if cols <= 0
        return false
    end

    for row in matrix_rows
        if length(row) != cols
            return false
        end
    end

    return true
end

"""Parse one matrix-like `\\begin{...}` environment into a matrix-compatible run."""
function parse_matrix_environment(tokens::Vector{LatexToken}, idx::Base.RefValue{Int})
    env_name = parse_required_group_as_text(tokens, idx)
    if !is_matrix_like_environment(env_name)
        return matrix_parse_fallback(), false
    end

    array_preamble = ""
    if env_name == "array"
        array_preamble, preamble_ok = parse_array_alignment_preamble(tokens, idx)
        if !preamble_ok
            skip_environment_body!(tokens, idx, env_name)
            return matrix_parse_fallback(), false
        end
    end

    environment_argument = ""
    if env_name in TABLE_ARGUMENT_ENVIRONMENTS
        environment_argument, argument_ok = parse_required_group_token_text(tokens, idx)
        environment_argument = normalize_array_preamble_text(environment_argument)
        if !argument_ok
            skip_environment_body!(tokens, idx, env_name)
            return matrix_parse_fallback(), false
        end
    end

    row_result = parse_matrix_rows(tokens, idx, env_name)
    matrix_rows = row_result.rows
    if !row_result.ok || !matrix_rows_valid(matrix_rows)
        skip_environment_body!(tokens, idx, env_name)
        return matrix_parse_fallback(), false
    end

    if !matrix_environment_metadata_ok(
        env_name, array_preamble, matrix_rows, environment_argument)
        return matrix_parse_fallback(), false
    end

    return matrix_environment_run_from_rows(
        env_name, array_preamble, environment_argument, matrix_rows, row_result), true
end

"""Build one matrix-like semantic run from validated row parser output."""
function matrix_environment_run_from_rows(
    env_name::AbstractString, array_preamble::AbstractString,
    environment_argument::AbstractString,
    matrix_rows::Vector{Vector{Vector{LatexRun}}}, row_result::MatrixRowsParseResult)

    cells = LatexRun[]
    for row in matrix_rows
        append!(cells, latex_matrix_cell_run.(row))
    end
    descriptor = nothing
    if env_name == "array"
        preamble = parse_array_preamble_spec(array_preamble)
        boundary_gaps = [MathTableLength(0.0f0, enabled ? :default : :zero)
            for enabled in preamble.boundary_defaults]
        descriptor = MathTableSemanticDescriptor(
            preamble.alignments, boundary_gaps,
            preamble.vertical_rule_counts, row_result.row_extra_gaps,
            row_result.horizontal_rule_counts, :text, :matrix)
    elseif env_name in TABLE_PRESET_ENVIRONMENTS
        descriptor = table_environment_descriptor(
            env_name, length(matrix_rows[1]), row_result, environment_argument)
    end
    metadata = isempty(environment_argument) ? array_preamble : environment_argument
    return matrix_environment_run(env_name, length(matrix_rows), length(matrix_rows[1]),
        cells, metadata, descriptor)
end

"""Parse one delimiter token after `\\left` or `\\right` and return canonical delimiter text."""
function parse_stretch_delimiter_token!(
    tokens::Vector{LatexToken}, idx::Base.RefValue{Int})
    if idx[] > length(tokens)
        return "", false
    end

    token = tokens[idx[]]
    if token.kind == :lbracket
        idx[] += 1
        return "[", true
    end
    if token.kind == :rbracket
        idx[] += 1
        return "]", true
    end

    if token.kind == :command
        delimiter = get(STRETCH_DELIMITER_TOKEN_MAP, token.text, "")
        if isempty(delimiter)
            return "", false
        end
        idx[] += 1
        return delimiter, true
    end

    if token.kind != :text || isempty(token.text)
        return "", false
    end

    return consume_text_stretch_delimiter!(tokens, idx, token)
end

"""Consume one stretch delimiter from the leading character of a text token."""
function consume_text_stretch_delimiter!(
    tokens::Vector{LatexToken}, idx::Base.RefValue{Int}, token::LatexToken)

    first_char_i = firstindex(token.text)
    delimiter = string(token.text[first_char_i])
    mapped = get(STRETCH_DELIMITER_TOKEN_MAP, delimiter, "")
    if isempty(mapped)
        return "", false
    end

    next_i = nextind(token.text, first_char_i)
    if next_i <= lastindex(token.text)
        tokens[idx[]] = LatexToken(:text, token.text[next_i:end])
    else
        idx[] += 1
    end
    return mapped, true
end

"""Parse runs and structural middles until `\\right` at current nesting depth."""
function parse_runs_until_right(tokens::Vector{LatexToken}, idx::Base.RefValue{Int})
    runs = LatexRun[]
    while idx[] <= length(tokens)
        token = tokens[idx[]]
        if token.kind == :command && token.text == STRETCH_DELIMITER_RIGHT
            return runs, true
        end

        if token.kind == :command && token.text == STRETCH_DELIMITER_MIDDLE
            idx[] += 1
            delimiter, ok = parse_stretch_delimiter_token!(tokens, idx)
            if !ok
                return runs, false
            end
            push!(runs, latex_middle_delimiter_run(delimiter))
            continue
        end

        if token.kind == :lbrace
            idx[] += 1
            append!(runs, parse_sequence(tokens, idx, true))
            continue
        end

        append!(runs, parse_atom(tokens, idx))
        consume_scripts!(runs, tokens, idx)
    end

    return runs, false
end

"""Return canonical text for one structured stretch-delimiter expression."""
stretch_delimiter_text(
    left::AbstractString, inner::AbstractString, right::AbstractString) =
    "\\left" * left * inner * "\\right" * right

"""Parse one `\\left ... \\right` expression and validate delimiter tokens."""
function parse_stretch_delimiter_run(tokens::Vector{LatexToken}, idx::Base.RefValue{Int})
    left_delimiter, left_ok = parse_stretch_delimiter_token!(tokens, idx)
    if !left_ok
        return latex_atom_run("\\left", :math), false
    end

    children, has_right = parse_runs_until_right(tokens, idx)
    if !has_right
        return latex_atom_run(
            stretch_delimiter_text(left_delimiter, plain_text_for_runs(children),
                STRETCH_DELIMITER_NONE), :math), false
    end

    idx[] += 1
    right_delimiter, right_ok = parse_stretch_delimiter_token!(tokens, idx)
    if !right_ok
        return latex_atom_run(
            stretch_delimiter_text(left_delimiter, plain_text_for_runs(children),
                STRETCH_DELIMITER_NONE), :math), false
    end

    return latex_stretch_delimiter_run(left_delimiter, right_delimiter, children), true
end

"""Serialize one matrix-like semantic run back into deterministic plain-text LaTeX form."""
function matrix_serialized_text(
    rows::Int, cols::Int, cells::Vector{LatexRun},
    env_name::AbstractString, preamble::AbstractString="")
    matrix_text = "\\begin{" * env_name * "}"
    if env_name == "array" || env_name in TABLE_ARGUMENT_ENVIRONMENTS
        matrix_text *= "{" * preamble * "}"
    end
    cell_index = 1
    for row in 1:rows
        if row > 1
            matrix_text *= "\\\\"
        end
        for col in 1:cols
            if col > 1
                matrix_text *= "&"
            end

            if cell_index <= length(cells)
                cell = cells[cell_index]
                matrix_text *= join((latex_run_serialized_text(child)
                    for child in cell.children), "")
            end
            cell_index += 1
        end
    end
    return matrix_text * "\\end{" * env_name * "}"
end

"""Return canonical environment metadata for one matrix-like run."""
function matrix_like_env_metadata(run::LatexRun)
    if run.segment == :array
        preamble = isempty(run.secondary_children) ? "c" : run.secondary_children[1].text
        return "array", preamble
    end

    if run.segment in TABLE_SEMANTIC_SEGMENTS
        metadata = isempty(run.secondary_children) ? "" : run.secondary_children[1].text
        return String(run.segment), metadata
    end

    return "matrix", ""
end

"""Serialize matrix-like run, preserving environment kind and validated dimensions."""
function serialize_matrix_like_run(run::LatexRun)
    dims = parse_matrix_dims_text(run.text)
    rows = dims.rows
    cols = dims.cols
    if !dims.ok || rows <= 0 || cols <= 0
        if run.segment == :array
            return "\\begin{array}{c}\\end{array}"
        end
        return "\\begin{matrix}\\end{matrix}"
    end

    env_name, preamble = matrix_like_env_metadata(run)
    return matrix_serialized_text(rows, cols, run.children, env_name, preamble)
end

"""Serialize an overline or underline run, or return nothing for other segments."""
function latex_run_accent_text(run::LatexRun, child_text::AbstractString)
    run.segment == :accent_over && return "\\overline{" * child_text * "}"
    run.segment == :accent_under && return "\\underline{" * child_text * "}"
    return nothing
end

"""Serialize one non-matrix run segment into deterministic plain-text LaTeX form."""
function latex_run_non_matrix_text(
    run::LatexRun, child_text::AbstractString, secondary_child_text::AbstractString)
    if run.role == :operatorname || run.role == :operatorname_star
        star = run.role == :operatorname_star ? "*" : ""
        return "\\operatorname" * star * "{" * run.text * "}"
    end
    accent_text = latex_run_accent_text(run, child_text)
    accent_text !== nothing && return accent_text
    if run.segment == :radical_sqrt
        if !isempty(run.text)
            return "\\sqrt[" * run.text * "]{" * child_text * "}"
        end
        return "\\sqrt{" * child_text * "}"
    end
    if run.segment == :fraction
        return "\\frac{" * child_text * "}{" * secondary_child_text * "}"
    end
    if run.segment == :stretch_delimiter
        return stretch_delimiter_text(run.text, child_text, secondary_child_text)
    end
    if run.segment == :matrix_cell
        return child_text
    end
    return run.text
end

"""Serialize one semantic run back into deterministic plain-text LaTeX form."""
function latex_run_serialized_text(run::LatexRun)
    if run.glue_kind == MATH_GLUE_SOURCE
        return ""
    end
    child_text = ""
    if !isempty(run.children)
        child_text = join(
            (latex_run_serialized_text(child) for child in run.children), "")
    end
    secondary_child_text = ""
    if !isempty(run.secondary_children)
        secondary_child_text = join(
            (latex_run_serialized_text(child) for child in run.secondary_children), "")
    end

    if run.segment == :matrix || run.segment == :array ||
        run.segment in TABLE_SEMANTIC_SEGMENTS
        return serialize_matrix_like_run(run)
    end
    return latex_run_non_matrix_text(run, child_text, secondary_child_text)
end

"""Parse one sqrt run with an optional recursive degree program."""
function parse_sqrt_run(tokens::Vector{LatexToken}, idx::Base.RefValue{Int})
    degree_children = parse_optional_radical_degree(tokens, idx)
    radical_children = parse_required_group_runs(tokens, idx)
    return latex_sqrt_run(radical_children, degree_children)
end

"""Parse optional bracketed radical-degree content as semantic runs."""
function parse_optional_radical_degree(
    tokens::Vector{LatexToken}, idx::Base.RefValue{Int})
    if idx[] > length(tokens) || tokens[idx[]].kind != :lbracket
        return LatexRun[]
    end

    idx[] += 1
    runs = LatexRun[]
    while idx[] <= length(tokens) && tokens[idx[]].kind != :rbracket
        append!(runs, parse_atom(tokens, idx))
        consume_scripts!(runs, tokens, idx)
    end
    if idx[] <= length(tokens) && tokens[idx[]].kind == :rbracket
        idx[] += 1
    end
    return normalize_runs(runs)
end

"""Parse one required `{...}` group and return semantic child runs."""
function parse_required_group_runs(tokens::Vector{LatexToken}, idx::Base.RefValue{Int})
    if idx[] > length(tokens) || tokens[idx[]].kind != :lbrace
        return LatexRun[]
    end

    idx[] += 1
    return parse_sequence(tokens, idx, true)
end

"""Parse one grouped or single-token math argument after a control word."""
function parse_math_argument_runs(tokens::Vector{LatexToken}, idx::Base.RefValue{Int})
    consume_command_delimiter_whitespace!(tokens, idx)
    if idx[] > length(tokens)
        return LatexRun[]
    end
    if tokens[idx[]].kind == :lbrace
        return parse_required_group_runs(tokens, idx)
    end
    if tokens[idx[]].kind == :text
        text = consume_single_script_text_token!(tokens, idx)
        return normal_math_atom_runs(text)
    end
    return parse_atom(tokens, idx)
end

"""Parse one required `{...}` group and return its flattened text."""
function parse_required_group_as_text(
    tokens::Vector{LatexToken}, idx::Base.RefValue{Int})

    runs = parse_required_group_runs(tokens, idx)
    return join((run.glue_kind == MATH_GLUE_SOURCE ? run.text :
        latex_run_serialized_text(run) for run in runs), "")
end

"""Map one required group through a complete mathematical alphabet."""
function parse_math_alphabet_command(
    tokens::Vector{LatexToken}, idx::Base.RefValue{Int}, mapping::Dict{Char,Char})

    if idx[] > length(tokens) || tokens[idx[]].kind != :lbrace
        return "", false
    end

    content = parse_required_group_as_text(tokens, idx)
    output = IOBuffer()
    for source in content
        glyph = get(mapping, source, nothing)
        isnothing(glyph) && return "", false
        write(output, glyph)
    end
    return String(take!(output)), !isempty(content)
end

"""Consume trailing super/subscript tokens and append mapped script runs."""
function consume_scripts!(
    runs::Vector{LatexRun}, tokens::Vector{LatexToken}, idx::Base.RefValue{Int})
    consume_operator_limit_modifier!(runs, tokens, idx)
    while idx[] <= length(tokens)
        marker = tokens[idx[]].kind
        if marker != :sup && marker != :sub
            break
        end

        idx[] += 1
        script = parse_script_text(tokens, idx)
        if isempty(script.text)
            continue
        end

        script_token = format_script_token(marker, script.text, script.was_grouped)
        if marker == :sup
            push!(runs, latex_sup_run(script_token, script.runs))
            continue
        end

        push!(runs, latex_sub_run(script_token, script.runs))
    end
end

const OPERATOR_LIMIT_MODIFIER_SEGMENTS = Dict(
    "\\limits" => :operator_limits_stacked,
    "\\nolimits" => :operator_limits_side,
    "\\displaylimits" => :operator_limits_display)

"""Consume one limit modifier only when it immediately follows a large operator."""
function consume_operator_limit_modifier!(
    runs::Vector{LatexRun}, tokens::Vector{LatexToken}, idx::Base.RefValue{Int})

    isempty(runs) && return nothing
    role = runs[end].role
    (startswith(String(role), "largeop_") || role == :operatorname_star) ||
        return nothing
    idx[] <= length(tokens) || return nothing
    token = tokens[idx[]]
    segment = get(OPERATOR_LIMIT_MODIFIER_SEGMENTS, token.text, nothing)
    if token.kind == :command && !isnothing(segment)
        push!(runs, LatexRun(token.text, :math, segment, MATH_ATOM_ORD,
            MATH_GLUE_NONE, LatexRun[], LatexRun[]))
        idx[] += 1
    end
    return nothing
end

"""Parse one script payload, either grouped (`{...}`) or single-atom."""
function parse_script_text(tokens::Vector{LatexToken}, idx::Base.RefValue{Int})
    if idx[] > length(tokens)
        return ParsedScript("", false, LatexRun[])
    end

    if tokens[idx[]].kind == :lbrace
        idx[] += 1
        runs = parse_sequence(tokens, idx, true)
        text = join((latex_run_serialized_text(run) for run in runs), "")
        return ParsedScript(text, true, runs)
    end

    if tokens[idx[]].kind == :text
        text = consume_single_script_text_token!(tokens, idx)
        return ParsedScript(text, false, normal_math_atom_runs(text))
    end

    runs = parse_atom(tokens, idx)
    text = join((latex_run_serialized_text(run) for run in runs), "")
    return ParsedScript(text, false, runs)
end

"""Consume exactly one character from a plain-text token for unbraced scripts."""
function consume_single_script_text_token!(
    tokens::Vector{LatexToken}, idx::Base.RefValue{Int})
    token = tokens[idx[]]
    if isempty(token.text)
        idx[] += 1
        return ""
    end

    first_char_index = firstindex(token.text)
    next_char_index = nextind(token.text, first_char_index)
    first_char = string(token.text[first_char_index])

    if next_char_index <= lastindex(token.text)
        tokens[idx[]] = LatexToken(:text, token.text[next_char_index:end])
    else
        idx[] += 1
    end

    return first_char
end

"""Format script suffix text without Unicode conversion."""
function format_script_token(
    marker::Symbol, script_text::AbstractString, was_grouped::Bool)
    prefix = marker == :sup ? "^" : "_"
    if was_grouped || length(script_text) != 1
        return prefix * "{" * script_text * "}"
    end

    return prefix * script_text
end

"""Merge adjacent runs with identical semantic role."""
run_has_no_content(run::LatexRun) =
    run.glue_kind == MATH_GLUE_NONE && isempty(run.text) &&
    isempty(run.children) && isempty(run.secondary_children)

"""Return true when two atom runs can be merged into one normalized atom run."""
function can_merge_adjacent_atom_runs(prev::LatexRun, run::LatexRun)
    return prev.role == run.role &&
           prev.atom_class == run.atom_class &&
           prev.glue_kind == run.glue_kind &&
           prev.segment == :atom &&
           run.segment == :atom &&
           isempty(prev.children) &&
           isempty(prev.secondary_children) &&
           isempty(run.children) &&
           isempty(run.secondary_children)
end

"""Drop empty runs and merge adjacent mergeable atom runs into a normalized vector."""
function normalize_runs(runs::Vector{LatexRun})
    normalized = LatexRun[]
    for run in runs
        if run_has_no_content(run) || run.glue_kind == MATH_GLUE_SOURCE
            continue
        end

        if !isempty(normalized) && can_merge_adjacent_atom_runs(normalized[end], run)
            prev = normalized[end]
            normalized[end] = LatexRun(prev.text * run.text, prev.role, :atom,
                prev.atom_class, prev.glue_kind, EMPTY_CHILD_RUNS, EMPTY_CHILD_RUNS)
            continue
        end

        push!(normalized, run)
    end
    return normalized
end

"""Extract script payload text from canonical script token form."""
function script_payload_text(script_token::AbstractString)
    if isempty(script_token)
        return ""
    end

    if startswith(script_token, "^{") && endswith(script_token, "}")
        return script_token[3:end-1]
    end
    if startswith(script_token, "_{") && endswith(script_token, "}")
        return script_token[3:end-1]
    end
    if startswith(script_token, "^") || startswith(script_token, "_")
        return script_token[2:end]
    end
    return script_token
end

"""Append optional canonical script suffixes to a base segment string."""
function accent_with_script_suffix(
    base::AbstractString, sup::AbstractString, sub::AbstractString)
    segment = base
    if !isempty(sup)
        segment *= "^{" * sup * "}"
    end
    if !isempty(sub)
        segment *= "_{" * sub * "}"
    end
    return segment
end

"""Append scripts to a grouped parent payload for recursive script wrappers."""
function grouped_parent_with_script_suffix(
    parent::AbstractString, sup::AbstractString, sub::AbstractString)
    return accent_with_script_suffix("{" * parent * "}", sup, sub)
end

"""Build canonical fraction text from numerator/denominator strings."""
fraction_text(numerator::AbstractString, denominator::AbstractString) =
    "{" * numerator * "}/{" * denominator * "}"

"""Return right delimiter text from one stretch-delimiter run."""
function stretch_right_delimiter(run::LatexRun)
    if isempty(run.secondary_children)
        return STRETCH_DELIMITER_NONE
    end
    return run.secondary_children[1].text
end

"""Append display-style lower/upper limits in canonical LaTeX order for large operators."""
function large_operator_with_limits(
    base::AbstractString, sup::AbstractString, sub::AbstractString)
    segment = base
    if !isempty(sub)
        segment *= "_{" * sub * "}"
    end
    if !isempty(sup)
        segment *= "^{" * sup * "}"
    end
    return segment
end

const LARGE_OPERATOR_GLYPH_TO_COMMAND =
    Dict(output => command for (command, (output, _)) in LARGE_OPERATOR_COMMAND_MAP)

"""Map a large-operator glyph to its canonical registered command text."""
large_operator_command_text(glyph::AbstractString) =
    get(LARGE_OPERATOR_GLYPH_TO_COMMAND, String(glyph), "")

"""Map delimiter token text to bridge delimiter kind constants."""
bridge_delimiter_kind(delimiter::AbstractString) =
    get(BRIDGE_DELIMITER_KIND_MAP, delimiter, Int32(0))

"""Render one recursive matrix payload op to canonical LaTeX-ish source."""
function matrix_payload_text(
    rows::Int, cols::Int, children::Vector{MathPayloadOp}, cell_text_fn::Function)
    matrix_text = "\\begin{matrix}"
    cell_index = 1
    for row in 1:rows
        if row > 1
            matrix_text *= "\\\\"
        end
        for col in 1:cols
            if col > 1
                matrix_text *= "&"
            end
            if cell_index <= length(children)
                matrix_text *= cell_text_fn(children[cell_index])
            end
            cell_index += 1
        end
    end
    return matrix_text * "\\end{matrix}"
end

"""Render matrix payload fallback text when matrix metadata is valid."""
function valid_matrix_payload_text(
    rows_text::AbstractString, cols_text::AbstractString, children::Vector{MathPayloadOp},
    cell_text_fn::Function)
    rows, rows_ok = parse_positive_int(rows_text)
    cols, cols_ok = parse_positive_int(cols_text)
    if !rows_ok || !cols_ok || rows <= 0 || cols <= 0
        return "\\begin{matrix}\\end{matrix}"
    end
    return matrix_payload_text(rows, cols, children, cell_text_fn)
end

"""Render matrix payload fallback text preserving original source shape when available."""
function matrix_payload_fallback_text(op::MathPayloadOp, cell_text_fn::Function)
    if !isempty(op.text)
        return op.text
    end

    return valid_matrix_payload_text(
        op.radical_index_text,
        op.sup_text,
        op.children,
        cell_text_fn)
end

"""Render a scoped style override to canonical source."""
function style_override_payload_source(op::MathPayloadOp)
    commands = ("\\displaystyle", "\\textstyle",
        "\\scriptstyle", "\\scriptscriptstyle")
    mode = clamp(Int(STYLE_OVERRIDE_MODES[op.radical_mode]) + 1, 1, 4)
    return commands[mode] * "{" * latex_source_for_program(op.children) * "}"
end

"""Render a native ruleless stack to canonical source."""
function stack_payload_source(op::MathPayloadOp)
    top = latex_source_for_program(op.children)
    bottom = latex_source_for_program(op.secondary_children)
    return "{" * top * "\\atop " * bottom * "}"
end

"""Render one large operator body to canonical command source."""
function large_operator_payload_source(op::MathPayloadOp)
    if op.style_role == :operatorname_star
        return "\\operatorname*{" * op.text * "}"
    end
    command = large_operator_command_text(op.text)
    return isempty(command) ? op.text : command
end

"""Render one recursive non-script payload op to canonical LaTeX-ish source."""
function latex_source_for_recursive_payload(op::MathPayloadOp)
    if op.kind == MATH_OP_LARGE_OP_RECURSIVE
        command = large_operator_payload_source(op)
        return large_operator_with_limits(command, op.sup_text, op.sub_text)
    end

    if op.kind == MATH_OP_FRACTION_RECURSIVE
        numerator = latex_source_for_program(op.children)
        denominator = latex_source_for_program(op.secondary_children)
        return "\\frac{" * numerator * "}{" * denominator * "}"
    end

    if op.kind == MATH_OP_STRETCH_DELIMITER_RECURSIVE
        return stretch_delimiter_text(
            op.radical_index_text, latex_source_for_program(op.children), op.sup_text)
    end

    if op.kind == MATH_OP_MATRIX_RECURSIVE
        return matrix_payload_fallback_text(op, latex_source_for_payload)
    end

    if op.kind == MATH_OP_STYLE_OVERRIDE_RECURSIVE
        return style_override_payload_source(op)
    end

    if op.kind == MATH_OP_STACK_RECURSIVE
        return stack_payload_source(op)
    end

    if op.kind == MATH_OP_ACCENT_BAR_RECURSIVE
        return accent_payload_text(op, latex_source_for_program(op.children))
    end

    if op.kind == MATH_OP_RADICAL_BAR_RECURSIVE
        return radical_payload_text(op, latex_source_for_program(op.children))
    end

    return latex_source_atom_text(op)
end
