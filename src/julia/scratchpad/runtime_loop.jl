"""Handle scratchpad local commands prefixed with ':' and return handled status."""
function handle_local_command!(
    host_runtime::ScratchpadRuntimeState,
    state_ptr::Ptr{Cvoid},
    text::AbstractString)

    session = ensure_session!(host_runtime, state_ptr)
    session.metrics.local_commands += 1

    if text == ":help"
        append_help_lines!(session)
        return true
    end
    if text == ":clear"
        isempty(session.output) || (session.output_revision += 1)
        empty!(session.output)
        empty!(session.output_entries)
        return true
    end
    if text == ":hooks"
        append_output_line!(session, list_frame_hooks(host_runtime, state_ptr))
        return true
    end
    if text == ":stats"
        for line in metrics_summary_lines(host_runtime, state_ptr)
            append_output_line!(session, line)
        end
        return true
    end
    if text == ":reset"
        new_session = reset_session!(host_runtime, state_ptr)
        append_output_line!(new_session, "Session reset by :reset")
        return true
    end

    return false
end

"""Return true when input should be treated as an explicit exit request."""
is_exit_command(text::AbstractString) = text in ("exit", "quit", "exit()", "quit()")

"""Handle parse-status side effects and return true when evaluation should stop."""
function handle_parse_status!(session::ScratchpadSession, status, parsed)
    if status == ParseIncomplete
        append_output_line!(session, "Input incomplete during execution")
        return true
    end
    if status == ParseError
        append_output_line!(session, parse_error_message(parsed))
        return true
    end

    return false
end

"""Return the Julia REPL-style source label for the current queued input."""
function repl_input_filename(session::ScratchpadSession)
    input_number = max(session.metrics.queue_dequeued, 1)
    return "REPL[$(input_number)]"
end

"""Evaluate one queued input line, including local commands, help mode, and safe eval."""
function evaluate_queued_input!(
    host_runtime::ScratchpadRuntimeState,
    session::ScratchpadSession,
    state_ptr::Ptr{Cvoid},
    text::String,
    input_mode::Int32=InputModeJulia)

    stripped = strip(text)
    dispatched = stripped == "?" ? ":help" : stripped
    append_input_echo!(session, text, input_mode)

    if dispatch_non_eval_input!(
        host_runtime, session, state_ptr, stripped, dispatched, input_mode)
        return
    end

    status, parsed = classify_parse(text)
    if handle_parse_status!(session, status, parsed)
        return
    end

    eval_scoped_input!(session, state_ptr, text)
end

"""Handle help, local, exit, and blocked inputs, returning true when one was handled."""
function dispatch_non_eval_input!(
    host_runtime::ScratchpadRuntimeState,
    session::ScratchpadSession, state_ptr::Ptr{Cvoid},
    stripped::AbstractString, dispatched::AbstractString, input_mode::Int32)

    if input_mode == InputModeHelp
        append_native_help_query!(session, stripped)
        return true
    end
    handle_help_query!(session, dispatched) && return true
    handle_local_command!(host_runtime, state_ptr, dispatched) && return true
    if is_exit_command(stripped)
        intercept_exit_or_quit(host_runtime, state_ptr)
        return true
    end
    reason = blocked_input_reason(stripped)
    if reason !== nothing
        session.metrics.blocked_commands += 1
        append_output_line!(session, "Blocked by scratchpad safety policy: " * reason)
        return true
    end
    return false
end

"""Parse, soft-scope, and eval one input line in the session runtime, recording errors."""
function eval_scoped_input!(
    session::ScratchpadSession, state_ptr::Ptr{Cvoid}, text::String)

    runtime = session.runtime
    Core.eval(runtime, :(state_ptr = $state_ptr))

    repl_parsed = Base.parse_input_line(text; filename=repl_input_filename(session))
    scoped = apply_softscope(runtime, repl_parsed)
    try
        result = Core.eval(runtime, scoped)
        if result !== nothing
            append_eval_result_output!(session, result)
        end
    catch e
        session.metrics.eval_errors += 1
        append_native_error_block!(session,
            format_current_exception_text(runtime, e; color=true))
    end
end

"""Run enabled frame hooks once, tracking failures and auto-disabling unstable hooks."""
function run_frame_hooks!(session::ScratchpadSession, state_ptr::Ptr{Cvoid}, dt)
    if isempty(session.hooks)
        return
    end

    dt32 = try
        Float32(dt)
    catch e
        e isa Exception || rethrow()
        Float32(0)
    end

    for hook in session.hooks
        if !hook.enabled
            continue
        end

        hook_started_at = time_ns()
        try
            hook.fn(state_ptr, dt32)
            hook.consecutive_failures = 0
            maybe_warn_slow_hook!(session, hook, time_ns() - hook_started_at)
        catch e
            hook.failures += 1
            hook.consecutive_failures += 1
            session.metrics.hook_errors += 1
            append_native_error_block!(
                session,
                "Frame $(frame_hook_label(hook.id, hook.label)) failed:\n" *
                format_current_exception_text(session.runtime, e; color=true))
            if hook.consecutive_failures >= MaxConsecutiveHookFailures
                hook.enabled = false
                append_output_line!(
                    session,
                    "Disabled $(frame_hook_label(hook.id, hook.label)) after $(hook.consecutive_failures) consecutive failures")
            end
        end
    end
end

"""Return current scratchpad output as newline-delimited text for the UI panel."""
function get_view_text(
    host_runtime::ScratchpadRuntimeState, state_ptr::Ptr{Cvoid})

    session = ensure_session!(host_runtime, state_ptr)
    _ = emit_dynview_output_stream!(state_ptr, session)
    document_entry = latest_latex_output(session)
    if document_entry !== nothing && latex_output_is_document(document_entry)
        return document_entry.line
    end
    if isempty(session.output)
        return ""
    end

    return join(session.output, "\n")
end

"""Prime Scratchpad parsing, completion, evaluation, formatting, and dynview emission."""
function prime_repl!(
    host_runtime::ScratchpadRuntimeState, state_ptr::Ptr{Cvoid})

    warm_session = create_session(host_runtime, state_ptr, -1)
    host_runtime.current_session = warm_session
    try
        queue_input(host_runtime, state_ptr, "sum(1:3)") || return false
        complete_backslash(host_runtime, state_ptr, "\\alpha") == "α" || return false
        isempty(complete_input(host_runtime, state_ptr, "EuclidRep", 9)) && return false
        loop(host_runtime, state_ptr, 0f0)
        isempty(get_view_text(host_runtime, state_ptr)) && return false
        status = OdinJuliaBridge.dynview_reset_stream(state_ptr)
        return status == OdinJuliaBridge.BRIDGE_STATUS_OK
    finally
        host_runtime.current_session = create_session(
            host_runtime, state_ptr, host_runtime.next_session_id)
    end
end

"""Initialize scratchpad session lifecycle and seed the Julia runtime banner."""
function initialize(
    host_runtime::ScratchpadRuntimeState, state_ptr::Ptr{Cvoid})

    host_runtime.initialize_count += 1
    session = ensure_session!(host_runtime, state_ptr)
    append_startup_banner!(session)
    callback = ptr -> get_view_text(host_runtime, ptr)
    OdinJuliaBridge.publish_view_update(state_ptr, callback)
end

"""Clean scratchpad lifecycle state and animation data when the animation unloads."""
function clean!(host_runtime::ScratchpadRuntimeState, state_ptr::Ptr{Cvoid})
    host_runtime.clean_count += 1
    host_runtime.current_session = nothing

    if isdefined(Main, :EuclidRepl) &&
        isdefined(Main.EuclidRepl, :reset_scratchpad_session!)
        Main.EuclidRepl.reset_scratchpad_session!(host_runtime)
    end
end

"""Per-frame scratchpad driver: dequeue/evaluate input and run frame hooks."""
function loop(
    host_runtime::ScratchpadRuntimeState, state_ptr::Ptr{Cvoid}, dt)

    session = ensure_session!(host_runtime, state_ptr)
    starting_revision = session.output_revision
    try
        if !isempty(session.queue)
            entry = popfirst!(session.queue)
            session.metrics.queue_dequeued += 1
            eval_started_at = time_ns()
            try
                evaluate_queued_input!(
                    host_runtime, session, state_ptr, entry.text, entry.mode)
            finally
                if entry.request_id != 0
                    OdinJuliaBridge.scratchpad_evaluation_completed(
                        state_ptr, entry.request_id)
                end
            end
            maybe_warn_slow_eval!(session, time_ns() - eval_started_at)
        end

        run_frame_hooks!(session, state_ptr, dt)
    catch e
        append_native_error_block!(
            session, format_current_exception_text(session.runtime, e; color=true))
    end
    current_session = ensure_session!(host_runtime, state_ptr)
    if current_session !== session || current_session.output_revision != starting_revision
        callback = ptr -> get_view_text(host_runtime, ptr)
        OdinJuliaBridge.publish_view_update(state_ptr, callback)
    end
end

"""Dispatch one bridge-stable lifecycle operation for the scratchpad animation."""
function animation_entry(
    host_runtime::ScratchpadRuntimeState,
    expected_state_ptr::Ptr{Cvoid},
    state_ptr::Ptr{Cvoid},
    operation::Int32,
    dt::Float32)::Bool

    state_ptr == expected_state_ptr || return false

    if operation == OdinJuliaBridge.ANIMATION_OPERATION_ENTER
        initialize(host_runtime, state_ptr)
    elseif operation == OdinJuliaBridge.ANIMATION_OPERATION_TICK
        loop(host_runtime, state_ptr, dt)
    elseif operation == OdinJuliaBridge.ANIMATION_OPERATION_EXIT
        clean!(host_runtime, state_ptr)
    else
        return false
    end
    return true
end

