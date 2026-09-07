mutable struct ScratchpadMetrics
    output_trimmed::Int
    history_trimmed::Int
    queue_dropped::Int
    queue_enqueued::Int
    queue_dequeued::Int
    queue_high_water::Int
    local_commands::Int
    blocked_commands::Int
    eval_errors::Int
    hook_errors::Int
    slow_eval_warnings::Int
    slow_hook_warnings::Int
    last_eval_ns::Int
    last_hook_ns::Int
end

mutable struct ScratchpadFrameHook
    id::Int
    fn::Any
    label::String
    enabled::Bool
    failures::Int
    consecutive_failures::Int
end

struct ScratchpadOutputSegment
    text::String
    style_id::Int32
    brush_color::Union{Nothing,OdinJuliaBridge.BridgeColor}
end

struct ScratchpadOutputEntry
    line::String
    block_kind::Int32
    style_id::Int32
    latex_source::String
    latex_is_math::Bool
    segments::Vector{ScratchpadOutputSegment}
end

struct ScratchpadInputEntry
    text::String
    mode::Int32
    request_id::UInt64
end

"""Create an uncorrelated input entry for history and internal callers."""
ScratchpadInputEntry(text::String, mode::Int32) =
    ScratchpadInputEntry(text, mode, UInt64(0))

"""Construct an output entry without optional inline segments."""
function ScratchpadOutputEntry(
    line::String,
    block_kind::Int32,
    style_id::Int32,
    latex_source::String)

    ScratchpadOutputEntry(
        line, block_kind, style_id, latex_source, false, ScratchpadOutputSegment[])
end

"""Construct an output entry with segments and no explicit LaTeX math mode."""
function ScratchpadOutputEntry(
    line::String,
    block_kind::Int32,
    style_id::Int32,
    latex_source::String,
    segments::Vector{ScratchpadOutputSegment})

    ScratchpadOutputEntry(line, block_kind, style_id, latex_source, false, segments)
end

mutable struct ScratchpadSession
    id::Int
    runtime::Module
    queue::Vector{ScratchpadInputEntry}
    output::Vector{String}
    output_entries::Vector{ScratchpadOutputEntry}
    history::Vector{ScratchpadInputEntry}
    hooks::Vector{ScratchpadFrameHook}
    metrics::ScratchpadMetrics
    output_revision::UInt64
    history_cursor::Int
    history_origin_mode::Int32
    next_hook_id::Int
end

"""Base type for optional services owned by the Scratchpad runtime."""
abstract type ScratchpadExtensionState end

"""Own persistent Scratchpad state and lifecycle counters explicitly."""
mutable struct ScratchpadRuntimeState
    current_session::Union{Nothing,ScratchpadSession}
    next_session_id::Int
    initialize_count::Int
    clean_count::Int
    reset_count::Int
    extension_state::Union{Nothing,ScratchpadExtensionState}
    animation_callback::Union{Nothing,Function}
end

"""Create empty Scratchpad state for one owning runtime host."""
function create_runtime_state()::ScratchpadRuntimeState
    return ScratchpadRuntimeState(nothing, 1, 0, 0, 0, nothing, nothing)
end

"""Create and retain the stable lifecycle callback borrowed by the native host."""
function create_animation_callback!(
    host_runtime::ScratchpadRuntimeState, state_ptr::Ptr{Cvoid})::Function

    callback = (callback_state_ptr, operation, dt) ->
        animation_entry(host_runtime, state_ptr, callback_state_ptr, operation, dt)
    host_runtime.animation_callback = callback
    return callback
end

mutable struct NativeErrorStyle
    bold::Bool
    italic::Bool
    underline::Bool
    brush_color::Union{Nothing,OdinJuliaBridge.BridgeColor}
end

const ScratchpadName = "Scratchpad"
const ParseError = Int32(0)
const ParseIncomplete = Int32(1)
const ParseComplete = Int32(2)
const InputModeJulia = Int32(0)
const InputModeHelp = Int32(1)
const MaxOutputLines = 400
const MaxHistoryLines = 400
const MaxQueueLines = 64
const SlowEvalWarnNs = Int(250_000_000)
const SlowHookWarnNs = Int(250_000_000)
const MaxConsecutiveHookFailures = 3
const MaxExceptionOutputBytes = 16 * 1024
const ExceptionOutputTruncated = "\n[Scratchpad exception output truncated]"
const DynviewStyleInput = OdinJuliaBridge.BRIDGE_DYNVIEW_STYLE_PROMPT
const DynviewStyleOutput = OdinJuliaBridge.BRIDGE_DYNVIEW_STYLE_OUTPUT
const DynviewStyleError = OdinJuliaBridge.BRIDGE_DYNVIEW_STYLE_ERROR
const DynviewStylePromptBold = OdinJuliaBridge.BRIDGE_DYNVIEW_STYLE_BOLD
const DynviewStyleBold = OdinJuliaBridge.BRIDGE_DYNVIEW_STYLE_BOLD
const DynviewStyleItalic = OdinJuliaBridge.BRIDGE_DYNVIEW_STYLE_ITALIC
const DynviewStyleUnderline = OdinJuliaBridge.BRIDGE_DYNVIEW_STYLE_UNDERLINE
const ReplPrompt = "julia> "
const ReplContinuation = " " ^ length(ReplPrompt)
const ReplPromptColor = OdinJuliaBridge.bridge_color(:julia_green)
const HelpPrompt = "help?> "
const HelpPromptColor = OdinJuliaBridge.BridgeColor(0xd9, 0xb4, 0x4a, 0xff)
const NativeErrorRed = OdinJuliaBridge.BridgeColor(0xdc, 0x5f, 0x5f, 0xff)
const NativeErrorGray = OdinJuliaBridge.BridgeColor(0x80, 0x80, 0x80, 0xff)
const NativeErrorMagenta = OdinJuliaBridge.BridgeColor(0x95, 0x58, 0xb2, 0xff)

const HELPER_DOC_ALIASES = Dict(
    "register_frame_hook" => (:Scratchpad, :register_frame_hook,
        "register_frame_hook(fn; label=\"\")"),
    "remove_frame_hook" => (:Scratchpad, :remove_frame_hook,
        "remove_frame_hook(hook_id)"),
    "clear_frame_hooks" => (:Scratchpad, :clear_frame_hooks,
        "clear_frame_hooks()"),
    "list_frame_hooks" => (:Scratchpad, :list_frame_hooks,
        "list_frame_hooks()"),
    "save_history" => (:Scratchpad, :save_history_to_file,
        "save_history(path)"),
    "hide!" => (:EuclidRepl, Symbol("hide!"),
        "hide!(target)"),
    "euclidcolors" => (:EuclidRepl, Symbol("euclidcolors"),
        "euclidcolors()"),
    "point!" => (:EuclidRepl, Symbol("point!"),
        "point!(pos; color=:steelblue, brush=5f0, duration=5.5f0)"),
    "line!" => (:EuclidRepl, Symbol("line!"),
        "line!(start_pos, end_pos; color=:steelblue, brush=5f0, duration=7.5f0)"),
    "circle!" => (:EuclidRepl, Symbol("circle!"),
        "circle!(center, radius; color=:steelblue, brush=5f0, duration=8.0f0)"),
    "highlight_pen!" => (:EuclidRepl, Symbol("highlight_pen!"),
        "highlight_pen!(start_pos, end_pos; color=:lightgreen, duration=3.2f0)"),
    "highlight_compass!" => (:EuclidRepl, Symbol("highlight_compass!"),
        "highlight_compass!(center, start_pos, angle_theta, radius; color=:lightgreen, filled=false, duration=3.2f0)"),
    "translate_points!" => (:EuclidRepl, Symbol("translate_points!"),
        "translate_points!(point_ids, start_positions, displacement; duration=2.5f0)"),
    "rotate_points!" => (:EuclidRepl, Symbol("rotate_points!"),
        "rotate_points!(point_ids, start_positions, axis_point_a, axis_point_b, theta; duration=2.5f0)"),
    "rotate_points_x!" => (:EuclidRepl, Symbol("rotate_points_x!"),
        "rotate_points_x!(point_ids, start_positions, theta; duration=2.5f0)"),
    "rotate_points_y!" => (:EuclidRepl, Symbol("rotate_points_y!"),
        "rotate_points_y!(point_ids, start_positions, theta; duration=2.5f0)"),
    "rotate_points_z!" => (:EuclidRepl, Symbol("rotate_points_z!"),
        "rotate_points_z!(point_ids, start_positions, theta; duration=2.5f0)"),
    "reflect2d_points!" => (:EuclidRepl, Symbol("reflect2d_points!"),
        "reflect2d_points!(point_ids, start_positions, line_point_a, line_point_b; duration=2.5f0)"),
    "reflect2d_points_x_axis!" => (:EuclidRepl, Symbol("reflect2d_points_x_axis!"),
        "reflect2d_points_x_axis!(point_ids, start_positions; duration=2.5f0)"),
    "reflect2d_points_y_axis!" => (:EuclidRepl, Symbol("reflect2d_points_y_axis!"),
        "reflect2d_points_y_axis!(point_ids, start_positions; duration=2.5f0)"),
    "reflect2d_points_diag_pos!" => (:EuclidRepl, Symbol("reflect2d_points_diag_pos!"),
        "reflect2d_points_diag_pos!(point_ids, start_positions; duration=2.5f0)"),
    "reflect2d_points_diag_neg!" => (:EuclidRepl, Symbol("reflect2d_points_diag_neg!"),
        "reflect2d_points_diag_neg!(point_ids, start_positions; duration=2.5f0)"))

# REPL-callable API is centered around: classify_input, queue_input,
# register_frame_hook/remove_frame_hook/clear_frame_hooks/list_frame_hooks,
# history_previous/history_next/history_reset_cursor, and save_history_to_file.

"""Register host-bound scratchpad animation callbacks with the animation tree."""
function init_euclid_scripts_scratchpad!(
    host_runtime::ScratchpadRuntimeState, state_ptr::Ptr{Cvoid})

    entry = create_animation_callback!(host_runtime, state_ptr)
    status = OdinJuliaBridge.add_root_animation_interface(
        state_ptr, entry, ScratchpadName,
        OdinJuliaBridge.animation_stable_id_from_key("root:" * ScratchpadName))
    status == 1 || (host_runtime.animation_callback = nothing)
    return status
end

"""Create an isolated runtime module used as the scratchpad eval scope."""
function create_runtime_module(
    host_runtime::ScratchpadRuntimeState, session_id::Int)

    mod_name = Symbol("EuclidScratchpadSession_", session_id)
    runtime = Module(mod_name)

    import_scratchpad_modules!(runtime)
    install_session_helpers!(runtime)
    Core.eval(runtime, :(scratchpad_runtime = $host_runtime))
    return runtime
end

"""Wire the shared Euclid modules and plotting libs into a scratchpad runtime module."""
function import_scratchpad_modules!(runtime::Module)
    if !isdefined(Main, :LaTeXStrings)
        Core.eval(Main, :(using LaTeXStrings))
    end
    if !isdefined(Main, :Latexify)
        Core.eval(Main, :(using Latexify))
    end

    Core.eval(runtime, :(const OdinJuliaBridge = Main.OdinJuliaBridge))
    Core.eval(runtime, :(const EuclidLatex = Main.EuclidLatex))
    Core.eval(runtime, :(const EuclidGeometry = Main.EuclidGeometry))
    Core.eval(runtime, :(const EuclidAnimations = Main.EuclidAnimations))
    Core.eval(runtime, :(const EuclidRepl = Main.EuclidRepl))
    Core.eval(runtime, :(const Scratchpad = Main.Scratchpad))
    Core.eval(runtime, :(const LaTeXStrings = Main.LaTeXStrings))
    Core.eval(runtime, :(const Latexify = Main.Latexify))
    Core.eval(runtime, :(using Main.LaTeXStrings))
    Core.eval(runtime, :(using Main.Latexify))
end

"""Install the session-scope hook and draw helper wrappers into a runtime module."""
function install_session_helpers!(runtime::Module)
    install_hook_helpers!(runtime)
    install_basic_draw_helpers!(runtime)
    install_draw_helpers!(runtime)
    install_reflection_helpers!(runtime)
end

"""Install the session-scope hook and lifecycle helpers into a runtime module."""
function install_hook_helpers!(runtime::Module)
    # Expose helpers directly in session scope so users can register/remove hooks from input.
    Core.eval(runtime, quote
        """Register a per-frame scratchpad hook with an optional label."""
        register_frame_hook(fn; label="") =
            Scratchpad.register_frame_hook(scratchpad_runtime, state_ptr, fn; label=label)
        """Remove a previously registered per-frame scratchpad hook."""
        remove_frame_hook(hook_id) =
            Scratchpad.remove_frame_hook(scratchpad_runtime, state_ptr, hook_id)
        """Remove all registered per-frame scratchpad hooks."""
        clear_frame_hooks() = Scratchpad.clear_frame_hooks(scratchpad_runtime, state_ptr)
        """List the registered per-frame scratchpad hooks."""
        list_frame_hooks() = Scratchpad.list_frame_hooks(scratchpad_runtime, state_ptr)
        """Save the scratchpad input history to a file."""
        save_history(path) =
            Scratchpad.save_history_to_file(scratchpad_runtime, state_ptr, path)

        # Intercept interactive exit/quit and reset only scratchpad session state.
        """Exit the scratchpad session, resetting only session state."""
        exit(args...) =
            Scratchpad.intercept_exit_or_quit(scratchpad_runtime, state_ptr)
        """Quit the scratchpad session, resetting only session state."""
        quit(args...) =
            Scratchpad.intercept_exit_or_quit(scratchpad_runtime, state_ptr)
    end)
end

"""Install basic geometry and highlighting helpers into a runtime module."""
function install_basic_draw_helpers!(runtime::Module)
    Core.eval(runtime, quote
        """Hide a REPL-managed geometry target."""
        hide!(args...; kwargs...) =
            EuclidRepl.hide!(scratchpad_runtime, state_ptr, args...; kwargs...)
        """List the named Euclid colors available for drawing."""
        euclidcolors(args...; kwargs...) = EuclidRepl.euclidcolors(args...; kwargs...)
        """Draw a point through the EuclidRepl API."""
        point!(args...; kwargs...) =
            EuclidRepl.point!(scratchpad_runtime, state_ptr, args...; kwargs...)
        """Draw a line through the EuclidRepl API."""
        line!(args...; kwargs...) =
            EuclidRepl.line!(scratchpad_runtime, state_ptr, args...; kwargs...)
        """Draw a circle through the EuclidRepl API."""
        circle!(args...; kwargs...) =
            EuclidRepl.circle!(scratchpad_runtime, state_ptr, args...; kwargs...)
        """Highlight a pen stroke through the EuclidRepl API."""
        highlight_pen!(args...; kwargs...) =
            EuclidRepl.highlight_pen!(scratchpad_runtime, state_ptr, args...; kwargs...)
        """Highlight a compass arc through the EuclidRepl API."""
        highlight_compass!(args...; kwargs...) =
            EuclidRepl.highlight_compass!(
                scratchpad_runtime, state_ptr, args...; kwargs...)
    end)
end

"""Install the session-scope EuclidRepl draw helper wrappers into a runtime module."""
function install_draw_helpers!(runtime::Module)
    # Convenience wrappers for common EuclidRepl draw APIs.
    Core.eval(runtime, quote
        """Translate points through the EuclidRepl API."""
        translate_points!(args...; kwargs...) =
            EuclidRepl.translate_points!(
                scratchpad_runtime, state_ptr, args...; kwargs...)
        """Rotate points about an axis through the EuclidRepl API."""
        rotate_points!(args...; kwargs...) =
            EuclidRepl.rotate_points!(scratchpad_runtime, state_ptr, args...; kwargs...)
        """Rotate points about the x axis through the EuclidRepl API."""
        rotate_points_x!(args...; kwargs...) =
            EuclidRepl.rotate_points_x!(
                scratchpad_runtime, state_ptr, args...; kwargs...)
        """Rotate points about the y axis through the EuclidRepl API."""
        rotate_points_y!(args...; kwargs...) =
            EuclidRepl.rotate_points_y!(
                scratchpad_runtime, state_ptr, args...; kwargs...)
        """Rotate points about the z axis through the EuclidRepl API."""
        rotate_points_z!(args...; kwargs...) =
            EuclidRepl.rotate_points_z!(
                scratchpad_runtime, state_ptr, args...; kwargs...)
    end)
end

"""Install session-scope EuclidRepl reflection helpers into a runtime module."""
function install_reflection_helpers!(runtime::Module)
    Core.eval(runtime, quote
        """Reflect points across a line through the EuclidRepl API."""
        reflect2d_points!(args...; kwargs...) =
            EuclidRepl.reflect2d_points!(
                scratchpad_runtime, state_ptr, args...; kwargs...)
        """Reflect points across the x axis through the EuclidRepl API."""
        reflect2d_points_x_axis!(args...; kwargs...) =
            EuclidRepl.reflect2d_points_x_axis!(
                scratchpad_runtime, state_ptr, args...; kwargs...)
        """Reflect points across the y axis through the EuclidRepl API."""
        reflect2d_points_y_axis!(args...; kwargs...) =
            EuclidRepl.reflect2d_points_y_axis!(
                scratchpad_runtime, state_ptr, args...; kwargs...)
        """Reflect points across the positive diagonal through the EuclidRepl API."""
        reflect2d_points_diag_pos!(args...; kwargs...) =
            EuclidRepl.reflect2d_points_diag_pos!(
                scratchpad_runtime, state_ptr, args...; kwargs...)
        """Reflect points across the negative diagonal through the EuclidRepl API."""
        reflect2d_points_diag_neg!(args...; kwargs...) =
            EuclidRepl.reflect2d_points_diag_neg!(
                scratchpad_runtime, state_ptr, args...; kwargs...)
    end)
end

"""Create an empty scratchpad session bound to the supplied host state."""
function create_session(
    host_runtime::ScratchpadRuntimeState,
    state_ptr::Ptr{Cvoid},
    session_id::Int)

    runtime = create_runtime_module(host_runtime, session_id)
    session = ScratchpadSession(
        session_id,
        runtime,
        ScratchpadInputEntry[],
        ScratchpadInputEntry[],
        ScratchpadOutputEntry[],
        String[],
        ScratchpadFrameHook[],
        ScratchpadMetrics(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0),
        UInt64(0),
        1,
        InputModeJulia,
        1)
    Core.eval(runtime, :(state_ptr = $state_ptr))
    return session
end

"""Append one mode-tagged history line while enforcing the retention cap."""
function append_history_line!(
    session::ScratchpadSession, line::String, input_mode::Int32=InputModeJulia)

    push!(session.history, ScratchpadInputEntry(line, input_mode))
    extra = length(session.history) - MaxHistoryLines
    if extra > 0
        session.metrics.history_trimmed += extra
        deleteat!(session.history, 1:extra)
    end
end

"""Push one mode-tagged entry into the execution queue and track cap behavior."""
function queue_line!(
    session::ScratchpadSession, text::String, input_mode::Int32=InputModeJulia,
    request_id::UInt64=UInt64(0))

    if length(session.queue) >= MaxQueueLines
        session.metrics.queue_dropped += 1
        _ = popfirst!(session.queue)
    end

    push!(session.queue, ScratchpadInputEntry(text, input_mode, request_id))
    session.metrics.queue_enqueued += 1
    session.metrics.queue_high_water =
        max(session.metrics.queue_high_water, length(session.queue))
end

"""Return a safety-policy block reason for input text, or `nothing` when allowed."""
function blocked_input_reason(text::AbstractString)
    lowered = lowercase(strip(String(text)))
    if occursin(r"^(using|import)\s+pkg\b", lowered)
        return "package management is disabled in scratchpad"
    end

    blocked_tokens = (
        "@ccall",
        "ccall(",
        "run(",
        "pipeline(",
        "Base.run",
        "download(",
        "rm(",
        "mv(",
        "cp(")
    for token in blocked_tokens
        if occursin(token, lowered)
            return "blocked token: $(token)"
        end
    end

    return nothing
end

"""Record eval timing and log a console warning when eval exceeds the slow threshold."""
function maybe_warn_slow_eval!(session::ScratchpadSession, elapsed_ns::Integer)
    session.metrics.last_eval_ns = elapsed_ns
    if elapsed_ns <= SlowEvalWarnNs
        return
    end

    session.metrics.slow_eval_warnings += 1
    elapsed_ms = round(elapsed_ns / 1_000_000; digits=2)
    @warn "Scratchpad eval took $(elapsed_ms) ms"
end

"""Record hook timing and log a console warning when a hook exceeds the slow threshold."""
function maybe_warn_slow_hook!(
    session::ScratchpadSession, hook::ScratchpadFrameHook, elapsed_ns::Integer)
    session.metrics.last_hook_ns = elapsed_ns
    if elapsed_ns <= SlowHookWarnNs
        return
    end

    session.metrics.slow_hook_warnings += 1
    elapsed_ms = round(elapsed_ns / 1_000_000; digits=2)
    @warn "Scratchpad $(frame_hook_label(hook.id, hook.label)) took $(elapsed_ms) ms"
end

"""Build a formatted summary of current scratchpad runtime metrics."""
function metrics_summary_lines(
    host_runtime::ScratchpadRuntimeState, state_ptr::Ptr{Cvoid})

    session = ensure_session!(host_runtime, state_ptr)
    m = session.metrics
    return [
        "Scratchpad Metrics",
        "queue enqueued=$(m.queue_enqueued) dequeued=$(m.queue_dequeued) dropped=$(m.queue_dropped) high_water=$(m.queue_high_water)",
        "trimmed output=$(m.output_trimmed) history=$(m.history_trimmed)",
        "errors eval=$(m.eval_errors) hooks=$(m.hook_errors) blocked=$(m.blocked_commands)",
        "slow eval warnings=$(m.slow_eval_warnings) last_eval_ns=$(m.last_eval_ns)",
        "slow hook warnings=$(m.slow_hook_warnings) last_hook_ns=$(m.last_hook_ns)",
        "transitions initialize=$(host_runtime.initialize_count) " *
        "clean=$(host_runtime.clean_count) reset=$(host_runtime.reset_count)",
    ]
end

"""Create and install a fresh scratchpad session, runtime module, and counters."""
function reset_session!(
    host_runtime::ScratchpadRuntimeState, state_ptr::Ptr{Cvoid})

    if isdefined(Main, :EuclidRepl) &&
        isdefined(Main.EuclidRepl, :reset_scratchpad_session!)
        Main.EuclidRepl.reset_scratchpad_session!(host_runtime)
    end

    session_id = host_runtime.next_session_id
    host_runtime.next_session_id = session_id + 1
    host_runtime.reset_count += 1

    session = create_session(host_runtime, state_ptr, session_id)
    host_runtime.current_session = session
    return session
end

"""Return the current session or create one when missing, refreshing state_ptr binding."""
function ensure_session!(
    host_runtime::ScratchpadRuntimeState, state_ptr::Ptr{Cvoid})

    session = host_runtime.current_session
    if session === nothing
        return reset_session!(host_runtime, state_ptr)
    end

    Core.eval(session.runtime, :(state_ptr = $state_ptr))
    return session
end

"""Append one output entry while enforcing the configured output retention cap."""
function append_output_entry!(session::ScratchpadSession, entry::ScratchpadOutputEntry)
    push!(session.output, entry.line)
    push!(session.output_entries, entry)
    session.output_revision += 1
    extra = length(session.output) - MaxOutputLines
    if extra > 0
        session.metrics.output_trimmed += extra
        deleteat!(session.output, 1:extra)
        deleteat!(session.output_entries, 1:extra)
    end
end

"""Append one output line while enforcing the configured output retention cap."""
function append_output_line!(session::ScratchpadSession, line::AbstractString)
    text = String(line)
    block_kind, style_id = dynview_ids_for_line(text)
    append_output_entry!(session, ScratchpadOutputEntry(text, block_kind, style_id, ""))
end

"""Build one regular-weight output segment with an optional named brush color."""
function output_segment(text::AbstractString, color_name::Union{Nothing,Symbol}=nothing)
    brush_color = color_name === nothing ?
        nothing : OdinJuliaBridge.bridge_color(color_name)
    return ScratchpadOutputSegment(String(text), DynviewStyleOutput, brush_color)
end

"""Append one output line composed from independently colored text segments."""
function append_segmented_output_line!(
    session::ScratchpadSession,
    segments::Vector{ScratchpadOutputSegment})

    line = join(segment.text for segment in segments)
    append_output_entry!(session, ScratchpadOutputEntry(
        line,
        OdinJuliaBridge.BRIDGE_DYNVIEW_BLOCK_OUTPUT,
        DynviewStyleOutput,
        "",
        false,
        segments))
end

"""Append one eval-result output line that should render as inline formatted LaTeX."""
function append_latex_result_line!(
    session::ScratchpadSession, latex_source::AbstractString, plain_text::AbstractString,
    latex_is_math::Bool=false)
    line = String(plain_text)
    append_output_entry!(session, ScratchpadOutputEntry(
        line,
        OdinJuliaBridge.BRIDGE_DYNVIEW_BLOCK_OUTPUT,
        DynviewStyleOutput,
        String(latex_source),
        latex_is_math,
        ScratchpadOutputSegment[]))
end

"""Apply REPL softscope transformation to parsed expressions when available."""
function apply_softscope(runtime::Module, expr)
    try
        return REPL.softscope(runtime, expr)
    catch e
        e isa Exception || rethrow()
        try
            return REPL.softscope(expr)
        catch inner
            inner isa Exception || rethrow()
            return expr
        end
    end
end

