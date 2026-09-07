
struct DynviewBlockSwitchResult
    ok::Bool
    open_block::Bool
    current_kind::Int32
    block_id::Int32
end



"""Return helper method names laid out in 2-3 text columns for :help output."""
function helper_method_name_columns()
    names = sort!(collect(keys(HELPER_DOC_ALIASES)))
    if isempty(names)
        return String["  (none)"]
    end

    column_count = length(names) >= 9 ? 3 : 2
    row_count = cld(length(names), column_count)
    col_width = maximum(length.(names)) + 3

    lines = []
    for row in 1:row_count
        parts = []
        for col in 0:(column_count - 1)
            idx = row + col * row_count
            if idx > length(names)
                continue
            end
            push!(parts, rpad(names[idx], col_width))
        end
        push!(lines, "  " * rstrip(join(parts, "")))
    end

    return lines
end

"""Append built-in scratchpad usage/help lines to output."""
function append_help_lines!(session::ScratchpadSession)
    append_output_line!(session, "Julia REPL Scratchpad")
    append_output_line!(session, "Enter Julia code, just like the standard Julia REPL!")
    append_output_line!(session, "")
    append_output_line!(session, "Commands")
    append_output_line!(session, "  ?            enter Julia help mode")
    append_output_line!(session, "  :help        show Scratchpad commands")
    append_output_line!(session, "  :clear       clear scrollback output")
    append_output_line!(session, "  :reset       reset scratchpad session")
    append_output_line!(session, "  :hooks       list frame hooks")
    append_output_line!(session, "  :stats       show runtime metrics")
    append_output_line!(session, "")
    append_output_line!(session, "Common Modules")
    append_output_line!(session, "  OdinJuliaBridge")
    append_output_line!(session, "  EuclidGeometry")
    append_output_line!(session, "  EuclidAnimations")
    append_output_line!(session, "  EuclidRepl")
    append_output_line!(session, "")
    append_output_line!(session, "Common Helper Methods")
    for line in helper_method_name_columns()
        append_output_line!(session, line)
    end
end

"""Return the release date reported by the active Julia runtime, when available."""
function julia_release_date()
    if !isdefined(Base, :GIT_VERSION_INFO)
        return nothing
    end

    version_info = Base.GIT_VERSION_INFO
    if !hasproperty(version_info, :date_string)
        return nothing
    end

    date_match = match(r"\d{4}-\d{2}-\d{2}", String(version_info.date_string))
    return date_match === nothing ? nothing : date_match.match
end

"""Return the startup banner version line for the active Julia runtime."""
function julia_version_banner_line()
    release_date = julia_release_date()
    if release_date === nothing
        return "  | | |_| | | | (_| |  |  Version $(VERSION)"
    end

    return "  | | |_| | | | (_| |  |  Version $(VERSION) ($(release_date))"
end

"""Append the Julia runtime banner shown when Scratchpad opens."""
function append_startup_banner!(session::ScratchpadSession)
    append_segmented_output_line!(session, [
        output_segment("               _", :julia_green),
    ])
    append_segmented_output_line!(session, [
        output_segment("   _", :julia_blue),
        output_segment("       _ "),
        output_segment("_", :julia_red),
        output_segment("(_)", :julia_green),
        output_segment("_", :julia_purple),
        output_segment("     |  Documentation: https://docs.julialang.org"),
    ])
    append_segmented_output_line!(session, [
        output_segment("  (_)", :julia_blue),
        output_segment("     | "),
        output_segment("(_)", :julia_red),
        output_segment(" "),
        output_segment("(_)", :julia_purple),
        output_segment("    |"),
    ])
    lines = [
        "   _ _   _| |_  __ _   |  Type \"?\" for Julia help mode,",
        "  | | | | | | |/ _` |  |  \":help\" for Scratchpad commands.",
        julia_version_banner_line(),
        " _/ |\\__'_|_|_|\\__'_|  |  Official https://julialang.org release",
        "|__/                   |",
    ]
    for line in lines
        append_output_line!(session, line)
    end
end

"""Render a result value using text/plain when possible for REPL-style display."""
function format_result_value(value, runtime::Module)
    io = IOBuffer()
    context = IOContext(io, :color => false, :limit => true, :module => runtime)
    try
        Base.invokelatest(show, context, MIME("text/plain"), value)
    catch e
        e isa Exception || rethrow()
        truncate(io, 0)
        seekstart(io)
        Base.invokelatest(show, context, value)
    end
    return String(take!(io))
end

"""Remove surrounding dollar-delimiter runs from one `text/latex` result."""
function normalize_latex_result_source(latex_source::AbstractString)
    source = strip(String(latex_source))
    if length(source) >= 2 && startswith(source, "\$") && endswith(source, "\$")
        return strip(strip(source, '\$'))
    end

    return source
end

"""Render and classify one `text/latex` MIME result, or return `nothing`."""
function format_result_latex(value, runtime::Module)
    io = IOBuffer()
    context = IOContext(io, :color => false, :limit => true, :module => runtime)
    try
        Base.invokelatest(show, context, MIME("text/latex"), value)
    catch e
        e isa Exception || rethrow()
        return nothing
    end

    latex_source = String(take!(io))
    normalized = normalize_latex_result_source(latex_source)
    isempty(normalized) && return nothing
    stripped = strip(latex_source)
    is_math = length(stripped) >= 2 && startswith(stripped, "\$") &&
        endswith(stripped, "\$")
    return (source=normalized, is_math=is_math)
end

"""Render a result value using `text/latex` MIME when supported, else return `nothing`."""
function format_result_latex_source(value, runtime::Module)
    formatted = format_result_latex(value, runtime)
    return formatted === nothing ? nothing : formatted.source
end

"""Append one eval-result output using LaTeX rendering when available."""
function append_eval_result_output!(session::ScratchpadSession, result)
    plain_text = format_result_value(result, session.runtime)
    formatted = format_result_latex(result, session.runtime)
    if formatted === nothing
        append_output_line!(session, plain_text)
        return
    end

    append_latex_result_line!(
        session, formatted.source, plain_text, formatted.is_math)
end

"""Truncate UTF-8 text to a byte budget and append an explicit marker."""
function truncate_exception_output(text::AbstractString)
    normalized = String(text)
    if ncodeunits(normalized) <= MaxExceptionOutputBytes
        return normalized
    end

    content_limit = MaxExceptionOutputBytes - ncodeunits(ExceptionOutputTruncated)
    first_excluded = thisind(normalized, content_limit + 1)
    last_included = prevind(normalized, first_excluded)
    return normalized[firstindex(normalized):last_included] * ExceptionOutputTruncated
end

"""Remove host evaluation frames while preserving user and called-library frames."""
function trim_scratchpad_backtrace(backtrace)
    if !(backtrace isa AbstractVector)
        return backtrace
    end

    boundary = findfirst(backtrace) do frame
        frame.func === :eval && endswith(String(frame.file), "boot.jl")
    end
    if boundary === nothing
        return backtrace
    end
    return backtrace[firstindex(backtrace):(boundary - 1)]
end

"""Apply Julia's REPL scrubber and remove Scratchpad's host evaluation tail."""
function scrub_scratchpad_exception_stack(exception_stack)
    scrubbed = Base.scrub_repl_backtrace(exception_stack)
    return Base.ExceptionStack(Any[
        (; item.exception, backtrace=trim_scratchpad_backtrace(item.backtrace))
            for item in scrubbed
    ])
end

"""Format a scrubbed Julia exception stack using the native REPL presentation."""
function format_exception_stack(exception_stack, runtime::Module; color::Bool=false)
    scrubbed = scrub_scratchpad_exception_stack(exception_stack)
    io = IOBuffer()
    limit_flag = Ref(false)
    context = IOContext(
        io,
        :color => color,
        :module => runtime,
        :stacktrace_types_limited => limit_flag)
    Base.invokelatest(Base.display_error, context, scrubbed)
    if limit_flag[]
        println(io, "Some type information was truncated. Use `show(err)` to see complete types.")
    end
    return truncate_exception_output(chomp(String(take!(io))))
end

"""Capture and format the exception stack active in the current catch block."""
format_current_exception_text(runtime::Module; color::Bool=false) =
    format_exception_stack(current_exceptions(), runtime; color=color)

"""Format the exception stack for one caught exception value."""
format_current_exception_text(
    runtime::Module, caught::Exception; color::Bool=false) =
    format_exception_stack(current_exceptions(), runtime; color=color)

"""Append one submitted input line with explicit prompt and input colors."""
function append_input_echo_line!(
    session::ScratchpadSession,
    text::AbstractString,
    first_line::Bool,
    input_mode::Int32)

    prompt = input_mode == InputModeHelp ? HelpPrompt : ReplPrompt
    prompt_color = input_mode == InputModeHelp ? HelpPromptColor : ReplPromptColor
    prefix = first_line ? prompt : ReplContinuation
    segments = ScratchpadOutputSegment[]
    if first_line
        push!(segments, ScratchpadOutputSegment(
            prompt, DynviewStylePromptBold, prompt_color))
    else
        push!(segments, ScratchpadOutputSegment(
            ReplContinuation, DynviewStyleOutput, nothing))
    end
    push!(segments, ScratchpadOutputSegment(
        String(text), DynviewStyleOutput, nothing))
    append_output_entry!(session, ScratchpadOutputEntry(
        prefix * String(text),
        OdinJuliaBridge.BRIDGE_DYNVIEW_BLOCK_INPUT,
        DynviewStyleInput,
        "",
        segments))
end

"""Echo submitted input with its mode prompt and normal command text."""
function append_input_echo!(
    session::ScratchpadSession, text::String, input_mode::Int32=InputModeJulia)

    lines = split(text, '\n')
    for i in eachindex(lines)
        append_input_echo_line!(
            session, lines[i], i == firstindex(lines), input_mode)
    end
end

"""Append a possibly-multiline text block to output preserving blank lines."""
function append_output_block!(session::ScratchpadSession, text::AbstractString)
    if isempty(text)
        return
    end

    for line in split(String(text), '\n'; keepempty=true)
        append_output_line!(session, line)
    end
end

"""Resolve the Dynview style represented by native error formatter state."""
function native_error_style_id(style::NativeErrorStyle)
    if style.underline
        return DynviewStyleUnderline
    elseif style.bold
        return DynviewStyleBold
    elseif style.italic
        return DynviewStyleItalic
    end
    return DynviewStyleOutput
end

"""Apply one supported native SGR font-trait code."""
function apply_native_error_trait_sgr!(style::NativeErrorStyle, code::Int)
    if code == 1
        style.bold = true
    elseif code == 3
        style.italic = true
    elseif code == 4
        style.underline = true
    elseif code == 22
        style.bold = false
    elseif code == 23
        style.italic = false
    elseif code == 24
        style.underline = false
    end
end

"""Apply one supported native SGR foreground-color code."""
function apply_native_error_color_sgr!(style::NativeErrorStyle, code::Int)
    if code == 35
        style.brush_color = NativeErrorMagenta
    elseif code == 39
        style.brush_color = nothing
    elseif code == 90
        style.brush_color = NativeErrorGray
    elseif code == 91
        style.brush_color = NativeErrorRed
    end
end

"""Apply one supported Julia error formatter SGR code."""
function apply_native_error_sgr!(style::NativeErrorStyle, code::Int)
    if code == 0
        style.bold = false
        style.italic = false
        style.underline = false
        style.brush_color = nothing
        return
    end

    apply_native_error_trait_sgr!(style, code)
    apply_native_error_color_sgr!(style, code)
end

"""Append one sanitized native formatter text run using the current SGR state."""
function append_native_error_run!(
    segments::Vector{ScratchpadOutputSegment},
    text::AbstractString,
    style::NativeErrorStyle)

    sanitized = replace(String(text), r"\e(?:\[[0-9;]*)?" => "")
    if isempty(sanitized)
        return
    end
    push!(segments, ScratchpadOutputSegment(
        sanitized, native_error_style_id(style), style.brush_color))
end

"""Parse Julia's bounded native error SGR stream into styled text runs."""
function parse_native_error_segments(text::AbstractString)
    source = String(text)
    segments = ScratchpadOutputSegment[]
    style = NativeErrorStyle(false, false, false, nothing)
    cursor = firstindex(source)

    for sgr_match in eachmatch(r"\e\[([0-9;]*)m", source)
        if cursor < sgr_match.offset
            append_native_error_run!(segments,
                SubString(source, cursor, prevind(source, sgr_match.offset)), style)
        end
        codes_text = something(sgr_match.captures[1], "")
        codes = isempty(codes_text) ?
            (0,) : something.(tryparse.(Int, split(codes_text, ';')), -1)
        for code in codes
            apply_native_error_sgr!(style, code)
        end
        cursor = sgr_match.offset + ncodeunits(sgr_match.match)
    end

    if cursor <= ncodeunits(source)
        append_native_error_run!(segments, SubString(source, cursor), style)
    end
    return segments
end

"""Append ANSI-free output lines from Julia's native styled error stream."""
function append_native_error_block!(session::ScratchpadSession, text::AbstractString)
    if isempty(text)
        return
    end

    lines = [ScratchpadOutputSegment[]]
    for segment in parse_native_error_segments(text)
        parts = split(segment.text, '\n'; keepempty=true)
        for (index, part) in enumerate(parts)
            if !isempty(part)
                push!(lines[end], ScratchpadOutputSegment(
                    String(part), segment.style_id, segment.brush_color))
            end
            if index < length(parts)
                push!(lines, ScratchpadOutputSegment[])
            end
        end
    end

    for segments in lines
        append_segmented_output_line!(session, segments)
    end
end

"""Return true when a host bridge status code represents success."""
is_bridge_status_ok(code::Integer) = Int32(code) == OdinJuliaBridge.BRIDGE_STATUS_OK

"""Map one output line into block/style ids for dynview emission."""
function dynview_ids_for_line(line::AbstractString)
    if startswith(line, "ERROR:") || startswith(line, "Error:") ||
        startswith(line, "help error:") ||
            startswith(line, "Blocked ")
        return OdinJuliaBridge.BRIDGE_DYNVIEW_BLOCK_OUTPUT, DynviewStyleError
    end

    return OdinJuliaBridge.BRIDGE_DYNVIEW_BLOCK_OUTPUT, DynviewStyleOutput
end

"""Switch dynview block when needed, preserving strict begin/end ordering."""
function dynview_switch_block!(
    state_ptr::Ptr{Cvoid}, open_block::Bool, current_kind::Int32,
    next_kind::Int32, block_id::Int32)
    if open_block && next_kind == current_kind
        return DynviewBlockSwitchResult(true, open_block, current_kind, block_id)
    end

    if open_block && !is_bridge_status_ok(OdinJuliaBridge.dynview_end_block(state_ptr))
        return DynviewBlockSwitchResult(false, open_block, current_kind, block_id)
    end
    if !is_bridge_status_ok(
        OdinJuliaBridge.dynview_begin_block(state_ptr, next_kind, block_id))
        return DynviewBlockSwitchResult(false, open_block, current_kind, block_id)
    end

    return DynviewBlockSwitchResult(true, true, next_kind, block_id + Int32(1))
end

"""Emit one optional-color text segment into the active dynview block."""
function dynview_emit_segment!(state_ptr::Ptr{Cvoid}, segment::ScratchpadOutputSegment)
    status = segment.brush_color === nothing ?
        OdinJuliaBridge.dynview_text_run(state_ptr, segment.text, segment.style_id) :
        OdinJuliaBridge.dynview_text_run_brush(
            state_ptr, segment.text, segment.style_id, segment.brush_color)
    return is_bridge_status_ok(status)
end

"""Emit one plain or segmented line and its copy payload into the active block."""
function dynview_emit_line!(
    state_ptr::Ptr{Cvoid},
    entry::ScratchpadOutputEntry,
    add_line_break::Bool)

    if isempty(entry.segments)
        if !is_bridge_status_ok(OdinJuliaBridge.dynview_text_run(
            state_ptr, entry.line, entry.style_id))
            return false
        end
    else
        for segment in entry.segments
            if !dynview_emit_segment!(state_ptr, segment)
                return false
            end
        end
    end
    if !is_bridge_status_ok(
        OdinJuliaBridge.dynview_copyable_text_run(state_ptr, entry.line))
        return false
    end
    if add_line_break &&
        !is_bridge_status_ok(OdinJuliaBridge.dynview_line_break(state_ptr))
        return false
    end
    return true
end

"""Emit one LaTeX result line with a plain-text fallback."""
function dynview_emit_latex_result_line!(
    state_ptr::Ptr{Cvoid},
    entry::ScratchpadOutputEntry,
    add_line_break::Bool)

    line = entry.line
    if !is_bridge_status_ok(OdinJuliaBridge.dynview_copyable_text_run(state_ptr, line))
        return false
    end

    rendered = EuclidLatex.replay_emit_math_block!(
        state_ptr,
        entry.latex_source;
        text_style=entry.style_id)

    if !rendered
        if !is_bridge_status_ok(OdinJuliaBridge.dynview_text_run(
            state_ptr, line, entry.style_id))
            return false
        end
    end

    if add_line_break &&
        !is_bridge_status_ok(OdinJuliaBridge.dynview_line_break(state_ptr))
        return false
    end
    return true
end

"""Return the most recent LaTeX result, if the output ends with one."""
function latest_latex_output(session::ScratchpadSession)
    isempty(session.output_entries) && return nothing
    entry = last(session.output_entries)
    isempty(entry.latex_source) && return nothing
    return entry
end

"""Return whether one LaTeX result should replace history as a semantic document."""
function latex_output_is_document(entry::ScratchpadOutputEntry)
    return !entry.latex_is_math && OdinJuliaBridge.dynview_tex_source_mode(
        entry.latex_source) == OdinJuliaBridge.DYNVIEW_TEX_MODE_DOCUMENT
end

"""Replace Scratchpad history with its latest native semantic document when eligible."""
function emit_latest_document!(state_ptr::Ptr{Cvoid}, session::ScratchpadSession)
    entry = latest_latex_output(session)
    entry === nothing && return nothing
    latex_output_is_document(entry) || return nothing
    is_bridge_status_ok(OdinJuliaBridge.dynview_reset_stream(state_ptr)) || return false
    status = OdinJuliaBridge.dynview_tex_document(
        state_ptr, entry.latex_source, entry.line,
        entry.block_kind, Int32(1), entry.style_id)
    return is_bridge_status_ok(status)
end

"""Emit current scratchpad output as a dynview command stream for host-side rendering."""
function emit_dynview_output_stream!(state_ptr::Ptr{Cvoid}, session::ScratchpadSession)
    document_status = emit_latest_document!(state_ptr, session)
    document_status === nothing || return document_status
    if !is_bridge_status_ok(OdinJuliaBridge.dynview_reset_stream(state_ptr)) ||
        isempty(session.output_entries)
        return isempty(session.output_entries)
    end

    block_id = Int32(1)
    current_kind = Int32(0)
    open_block = false
    last_line_index = lastindex(session.output_entries)
    for i in eachindex(session.output_entries)
        entry = session.output_entries[i]
        switch_result = dynview_switch_block!(
            state_ptr,
            open_block,
            current_kind,
            entry.block_kind,
            block_id)
        if !switch_result.ok
            return false
        end
        open_block = switch_result.open_block
        current_kind = switch_result.current_kind
        block_id = switch_result.block_id

        if isempty(entry.latex_source)
            if !dynview_emit_line!(state_ptr, entry, i != last_line_index)
                return false
            end
            continue
        end

        if !dynview_emit_latex_result_line!(state_ptr, entry, i != last_line_index)
            return false
        end
    end

    return !open_block ||
        is_bridge_status_ok(OdinJuliaBridge.dynview_end_block(state_ptr))
end

"""Render docs metadata objects into plain user-facing help text."""
function render_help_docs(doc_entry)
    if doc_entry isa Base.Docs.MultiDoc
        docs_dict = getfield(doc_entry, :docs)
        blocks = String[]
        for docstr in values(docs_dict)
            if !(docstr isa Base.Docs.DocStr)
                continue
            end

            rendered = render_doc_text_parts(getfield(docstr, :text))
            if !isempty(rendered)
                push!(blocks, rendered)
            end
        end

        if !isempty(blocks)
            return join(unique(blocks), "\n\n")
        end
    end

    if doc_entry isa Base.Docs.DocStr
        rendered = render_doc_text_parts(getfield(doc_entry, :text))
        if !isempty(rendered)
            return rendered
        end
    end

    fallback = strip(sprint(show, MIME("text/plain"), doc_entry))
    if isempty(fallback)
        return nothing
    end
    return fallback
end

"""Render `DocStr.text` fragments into one stripped string block."""
function render_doc_text_parts(parts)
    rendered = ""
    for part in parts
        if part isa AbstractString
            rendered *= part
        else
            rendered *= sprint(show, MIME("text/plain"), part)
        end
    end
    return strip(rendered)
end

"""Build argument parts from method declaration metadata when available."""
function render_signature_parts_from_decl(method)
    _, decl_parts, _, _ = Base.arg_decl_parts(method)
    parts = String[]
    arg_index = 0
    for i in eachindex(decl_parts)
        if i == firstindex(decl_parts)
            continue
        end

        arg_index += 1
        arg_name = strip(String(decl_parts[i][1]))
        arg_type = strip(String(decl_parts[i][2]))
        if isempty(arg_name)
            arg_name = "arg$(arg_index)"
        end

        if isempty(arg_type)
            push!(parts, arg_name)
        else
            push!(parts, arg_name * "::" * arg_type)
        end
    end
    return parts
end

"""Build fallback argument parts directly from method signature type tuple."""
function render_signature_parts_from_sig(method)
    sig = Base.unwrap_unionall(method.sig)
    params = sig.parameters

    parts = String[]
    if length(params) <= 1
        return parts
    end

    arg_index = 0
    for i in eachindex(params)
        if i == firstindex(params)
            continue
        end

        arg_index += 1
        push!(parts, "arg$(arg_index)::" * string(params[i]))
    end
    return parts
end

"""Render unique readable method signatures for a function docs binding."""
function render_help_signatures(binding::Base.Docs.Binding)
    if !isdefined(binding.mod, binding.var)
        return nothing
    end

    value = getfield(binding.mod, binding.var)
    if !(value isa Function)
        return nothing
    end

    method_list = methods(value)
    if length(method_list) == 0
        return "(no methods found)"
    end

    signatures = String[]
    for method in method_list
        arg_parts = String[]
        try
            arg_parts = render_signature_parts_from_decl(method)
        catch e
            e isa Exception || rethrow()
            arg_parts = render_signature_parts_from_sig(method)
        end

        push!(signatures, string(binding.var) * "(" * join(arg_parts, ", ") * ")")
    end

    unique!(signatures)
    sort!(signatures)
    return join(signatures, "\n")
end

"""Resolve module docs for a help binding, falling back to canonical module binding."""
function resolve_module_doc_entry(binding::Base.Docs.Binding, module_value::Module)
    doc_meta = Base.Docs.meta(binding.mod)
    if haskey(doc_meta, binding)
        return doc_meta[binding]
    end

    canonical_binding =
        Base.Docs.Binding(parentmodule(module_value), nameof(module_value))
    canonical_meta = Base.Docs.meta(canonical_binding.mod)
    if haskey(canonical_meta, canonical_binding)
        return canonical_meta[canonical_binding]
    end

    module_binding = Base.Docs.Binding(module_value, nameof(module_value))
    module_meta = Base.Docs.meta(module_value)
    if haskey(module_meta, module_binding)
        return module_meta[module_binding]
    end

    return nothing
end

"""Append binding docs and method signatures to scratchpad output."""
function append_binding_help!(
    session::ScratchpadSession, query::AbstractString, binding::Base.Docs.Binding)
    append_binding_help!(session, query, binding, nothing)
end

"""Append binding docs and either helper-facing signature or inferred method signatures."""
function append_binding_help!(
    session::ScratchpadSession,
    query::AbstractString,
    binding::Base.Docs.Binding,
    signature_override::Union{Nothing, String})
    doc_meta = Base.Docs.meta(binding.mod)
    if !haskey(doc_meta, binding)
        append_output_line!(session, "help error: no docs found for $(query)")
        return
    end

    rendered = render_help_docs(doc_meta[binding])
    if rendered === nothing || isempty(rendered)
        append_output_line!(session, "help error: docs for $(query) are empty")
        return
    end

    append_output_block!(session, rendered)

    signatures = signature_override
    if signatures === nothing
        signatures = render_help_signatures(binding)
    end

    if signatures !== nothing && !isempty(signatures)
        append_output_line!(session, "")
        append_output_line!(session, "Method Signatures")
        append_output_block!(session, signatures)
    end
end

"""Resolve a module/symbol alias spec to a docs binding, or `nothing` when unavailable."""
function helper_alias_binding(module_name::Symbol, symbol_name::Symbol)
    if module_name == :Scratchpad
        return Base.Docs.Binding(Scratchpad, symbol_name)
    end
    if !isdefined(Main, module_name)
        return nothing
    end

    target_module = getfield(Main, module_name)
    return Base.Docs.Binding(target_module, symbol_name)
end

"""Resolve runtime helper aliases to documented Scratchpad bindings and helper signatures."""
function resolve_helper_doc_alias(query::AbstractString)
    helper_name = strip(String(query))
    alias_spec = get(HELPER_DOC_ALIASES, helper_name, nothing)
    if alias_spec === nothing
        return nothing
    end

    module_name, symbol_name, signature = alias_spec

    binding = helper_alias_binding(module_name, symbol_name)
    if binding === nothing
        return nothing
    end

    return (binding=binding, signature=signature)
end

"""Render one native Julia help query, retaining Euclid helper aliases."""
function append_native_help_query!(session::ScratchpadSession, query::AbstractString)
    helper_alias = resolve_helper_doc_alias(query)
    if helper_alias !== nothing
        append_binding_help!(session, query, helper_alias.binding, helper_alias.signature)
        return
    end

    reason = blocked_input_reason(query)
    if reason !== nothing
        session.metrics.blocked_commands += 1
        append_output_line!(session, "Blocked by scratchpad safety policy: " * reason)
        return
    end

    side_io = IOBuffer()
    try
        context = IOContext(side_io, :color => false, :module => session.runtime)
        help_expr = REPL.helpmode(context, String(query), session.runtime)
        rendered_help = Core.eval(session.runtime, help_expr)
        side_text = chomp(String(take!(side_io)))
        if !isempty(side_text)
            append_output_block!(session, side_text)
        end
        if rendered_help !== nothing
            append_output_block!(session,
                format_result_value(rendered_help, session.runtime))
        end
    catch e
        append_native_error_block!(
            session, format_current_exception_text(session.runtime, e; color=true))
    end
end

"""Handle one-shot `?query` input through Julia's native help machinery."""
function handle_help_query!(session::ScratchpadSession, text::AbstractString)
    if isempty(text) || first(text) != '?'
        return false
    end

    query = strip(String(text[2:end]))
    if isempty(query)
        append_help_lines!(session)
        return true
    end

    append_native_help_query!(session, query)
    return true
end

