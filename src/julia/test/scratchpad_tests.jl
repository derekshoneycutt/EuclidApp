if !isdefined(Main, :OdinJuliaBridge)
    include("../odin-julia-bridge.jl")
end
if !isdefined(Main, :EuclidGeometry)
    include("../geometry.jl")
end
if !isdefined(Main, :EuclidAnimations)
    @eval module EuclidAnimations
    end
end
if !isdefined(Main, :EuclidLatex)
    include("../latex.jl")
end

include("../scratchpad.jl")
if !isdefined(Main, :EuclidRepl)
    include("../euclidrepl.jl")
end

using .Scratchpad
using Test

const TEST_SCRATCHPAD_RUNTIME = Scratchpad.create_runtime_state()
const TEST_SCRATCHPAD_STATE_PTR = Ptr{Cvoid}(0)

struct ScratchpadLatexResultMock
end

struct ScratchpadDocumentResultMock
end

struct ScratchpadPlainResultMock
end

"""Construct a zeroed scratchpad metrics struct for testing."""
function new_metrics()
    return Scratchpad.ScratchpadMetrics(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
end

"""Create a fresh scratchpad session bound to the shared test state."""
function new_session(; id::Int=1)
    return Scratchpad.create_session(
        TEST_SCRATCHPAD_RUNTIME, TEST_SCRATCHPAD_STATE_PTR, id)
end

"""Render a LaTeX result mock as plain text or LaTeX."""
Base.show(io::IO, ::MIME"text/plain", m::ScratchpadLatexResultMock) =
    print(io, "ScratchpadLatexResultMock()")
Base.show(io::IO, ::MIME"text/latex", m::ScratchpadLatexResultMock) =
    print(io, "\\frac{1}{2}")
Base.show(io::IO, ::MIME"text/plain", m::ScratchpadDocumentResultMock) =
    print(io, "Definition\n\nA point has no part.")
Base.show(io::IO, ::MIME"text/latex", m::ScratchpadDocumentResultMock) =
    print(io, "\\textbf{Definition}\n\nA point has no part.")

Base.show(io::IO, ::MIME"text/plain", m::ScratchpadPlainResultMock) =
    print(io, "ScratchpadPlainResultMock()")

"""Run a function with a fresh scratchpad session installed, restoring the old one after."""
function with_test_session(f::Function)
    old_session = TEST_SCRATCHPAD_RUNTIME.current_session
    try
        session = new_session()
        TEST_SCRATCHPAD_RUNTIME.current_session = session
        return f(session)
    finally
        TEST_SCRATCHPAD_RUNTIME.current_session = old_session
    end
end

@testset "classify_parse" begin
    status_complete, parsed_complete = Scratchpad.classify_parse("1 + 2")
    @test status_complete == Scratchpad.ParseComplete
    @test parsed_complete isa Expr

    status_incomplete, _ = Scratchpad.classify_parse("begin\n  x = 1")
    @test status_incomplete == Scratchpad.ParseIncomplete

    status_error, _ = Scratchpad.classify_parse("x = )")
    @test status_error == Scratchpad.ParseError
end

@testset "create_session" begin
    session = Scratchpad.create_session(
        TEST_SCRATCHPAD_RUNTIME, TEST_SCRATCHPAD_STATE_PTR, 10_001)
    @test session.id == 10_001
    @test isempty(session.queue)
    @test isempty(session.output)
    @test isempty(session.history)
    @test Core.eval(session.runtime, :state_ptr) == TEST_SCRATCHPAD_STATE_PTR
    @test Core.eval(session.runtime, :scratchpad_runtime) === TEST_SCRATCHPAD_RUNTIME
end

@testset "slow execution warnings are console only" begin
    session = new_session()
    Scratchpad.append_output_line!(session, "existing output")
    output_before = copy(session.output)
    entries_before = copy(session.output_entries)
    slow_eval_ns = Scratchpad.SlowEvalWarnNs + 1_000_000
    slow_hook_ns = Scratchpad.SlowHookWarnNs + 2_000_000
    hook = Scratchpad.ScratchpadFrameHook(7, () -> nothing, "orbit", true, 0, 0)

    @test_logs (:warn, r"Scratchpad eval took 251\.0 ms")
        Scratchpad.maybe_warn_slow_eval!(session, slow_eval_ns)
    @test_logs (:warn, r"Scratchpad hook id=7 label=\"orbit\" took 252\.0 ms")
        Scratchpad.maybe_warn_slow_hook!(session, hook, slow_hook_ns)

    @test session.output == output_before
    @test session.output_entries == entries_before
    @test session.metrics.slow_eval_warnings == 1
    @test session.metrics.slow_hook_warnings == 1
    @test session.metrics.last_eval_ns == slow_eval_ns
    @test session.metrics.last_hook_ns == slow_hook_ns
end

@testset "startup banner" begin
    session = new_session()
    Scratchpad.append_startup_banner!(session)

    release_date = Scratchpad.julia_release_date()
    @test release_date !== nothing
    @test occursin(r"^\d{4}-\d{2}-\d{2}$", release_date)
    @test session.output == [
        "               _",
        "   _       _ _(_)_     |  Documentation: https://docs.julialang.org",
        "  (_)     | (_) (_)    |",
        "   _ _   _| |_  __ _   |  Type \"?\" for Julia help mode,",
        "  | | | | | | |/ _` |  |  \":help\" for Scratchpad commands.",
        "  | | |_| | | | (_| |  |  Version $(VERSION) ($(release_date))",
        " _/ |\\__'_|_|_|\\__'_|  |  Official https://julialang.org release",
        "|__/                   |",
    ]

    first_row = session.output_entries[1].segments
    @test first_row[1].brush_color == OdinJuliaBridge.bridge_color(:julia_green)

    second_row_colors = [segment.brush_color for segment in
        session.output_entries[2].segments if segment.brush_color !== nothing]
    @test second_row_colors == [
        OdinJuliaBridge.bridge_color(:julia_blue),
        OdinJuliaBridge.bridge_color(:julia_red),
        OdinJuliaBridge.bridge_color(:julia_green),
        OdinJuliaBridge.bridge_color(:julia_purple),
    ]

    third_row_colors = [segment.brush_color for segment in
        session.output_entries[3].segments if segment.brush_color !== nothing]
    @test third_row_colors == [
        OdinJuliaBridge.bridge_color(:julia_blue),
        OdinJuliaBridge.bridge_color(:julia_red),
        OdinJuliaBridge.bridge_color(:julia_purple),
    ]

    Scratchpad.append_help_lines!(session)
    @test "Julia REPL Scratchpad" in session.output
    @test "  ?            enter Julia help mode" in session.output
    @test "  :help        show Scratchpad commands" in session.output
end

@testset "terminal prompt echo" begin
    session = Scratchpad.create_session(
        TEST_SCRATCHPAD_RUNTIME, TEST_SCRATCHPAD_STATE_PTR, 10_002)

    Scratchpad.append_input_echo!(session, "begin\n    x = 1\nend")

    @test session.output == [
        "julia> begin",
        "           x = 1",
        "       end",
    ]
    @test all(entry -> entry.block_kind == OdinJuliaBridge.BRIDGE_DYNVIEW_BLOCK_INPUT,
        session.output_entries)
    @test all(entry -> entry.style_id == Scratchpad.DynviewStyleInput,
        session.output_entries)
    first_line_segments = session.output_entries[1].segments
    @test first_line_segments[1].text == "julia> "
    @test first_line_segments[1].style_id == Scratchpad.DynviewStylePromptBold
    @test first_line_segments[1].brush_color == OdinJuliaBridge.bridge_color(:julia_green)
    @test first_line_segments[2].text == "begin"
    @test first_line_segments[2].style_id == Scratchpad.DynviewStyleOutput
    @test first_line_segments[2].brush_color === nothing
    @test all(segment -> segment.brush_color === nothing,
        session.output_entries[2].segments)
    @test all(segment -> segment.style_id == Scratchpad.DynviewStyleOutput,
        session.output_entries[2].segments)
end

@testset "parse_error_message" begin
    @test Scratchpad.parse_error_message(Expr(:error, "oops")) == "Parse error: oops"
    @test Scratchpad.parse_error_message(:not_an_expr) == "Parse error"
end

@testset "blocked_input_reason" begin
    @test Scratchpad.blocked_input_reason("using Pkg") ==
        "package management is disabled in scratchpad"
    @test Scratchpad.blocked_input_reason("import   pkg") ==
        "package management is disabled in scratchpad"
    @test Scratchpad.blocked_input_reason("run(`ls`)") == "blocked token: run("
    @test Scratchpad.blocked_input_reason("cp(\"a\", \"b\")") == "blocked token: cp("
    @test Scratchpad.blocked_input_reason("x = 42") === nothing
end

@testset "classify_input" begin
    with_test_session() do session
        @test Scratchpad.classify_input(
            TEST_SCRATCHPAD_RUNTIME, TEST_SCRATCHPAD_STATE_PTR, "x = 2") ==
            Scratchpad.ParseComplete
        @test isempty(session.output)

        @test Scratchpad.classify_input(
            TEST_SCRATCHPAD_RUNTIME, TEST_SCRATCHPAD_STATE_PTR, "x = )") ==
            Scratchpad.ParseError
        @test length(session.output) == 1
        @test startswith(session.output[1], "Parse error")

        @test Scratchpad.classify_input(
            TEST_SCRATCHPAD_RUNTIME, TEST_SCRATCHPAD_STATE_PTR,
            "?OdinJuliaBridge.bridge_color") == Scratchpad.ParseComplete
        @test length(session.output) == 1
    end
end

@testset "lone question mark aliases help" begin
    for input in ("?", "?  \t\n")
        with_test_session() do session
            Scratchpad.evaluate_queued_input!(
                TEST_SCRATCHPAD_RUNTIME, session, TEST_SCRATCHPAD_STATE_PTR, input)

            @test startswith(session.output[1], "julia> ?")
            @test "Julia REPL Scratchpad" in session.output
            @test "  :help        show Scratchpad commands" in session.output
            @test !any(startswith("help error:"), session.output)
            @test session.metrics.local_commands == 1
        end
    end
end

@testset "native persistent help mode" begin
    with_test_session() do session
        @test Scratchpad.classify_input(
            TEST_SCRATCHPAD_RUNTIME, TEST_SCRATCHPAD_STATE_PTR,
            "not valid Julia )", Scratchpad.InputModeHelp) ==
            Scratchpad.ParseComplete

        Scratchpad.evaluate_queued_input!(
            TEST_SCRATCHPAD_RUNTIME, session, TEST_SCRATCHPAD_STATE_PTR,
            "string", Scratchpad.InputModeHelp)
        output = join(session.output, "\n")
        @test startswith(session.output[1], "help?> string")
        @test occursin("search: string", output)
        @test occursin("Create a string from any values", output)
        @test !occursin("help error:", output)
    end

    for (query, expected) in (
        ("@time", "A macro to execute an expression"),
        ("begin", "begin...end denotes a block"),
        ("\"allocation\"", "Base.@allocated"),
        ("?print", "Write to io"))

        with_test_session() do session
            Scratchpad.evaluate_queued_input!(
                TEST_SCRATCHPAD_RUNTIME, session, TEST_SCRATCHPAD_STATE_PTR,
                query, Scratchpad.InputModeHelp)
            @test occursin(expected, join(session.output, "\n"))
        end
    end
end

@testset "complete_backslash" begin
    with_test_session() do _
        @test Scratchpad.complete_backslash(
            TEST_SCRATCHPAD_RUNTIME, TEST_SCRATCHPAD_STATE_PTR, "\\alpha") == "α"
        @test Scratchpad.complete_backslash(
            TEST_SCRATCHPAD_RUNTIME, TEST_SCRATCHPAD_STATE_PTR, "\\al") == ""
        @test Scratchpad.complete_backslash(
            TEST_SCRATCHPAD_RUNTIME, TEST_SCRATCHPAD_STATE_PTR, "alpha") == ""
    end
end

@testset "complete_input" begin
    with_test_session() do session
        @test Scratchpad.complete_input(
            TEST_SCRATCHPAD_RUNTIME, TEST_SCRATCHPAD_STATE_PTR,
            "\\alpha", 6) == "0\n6\nα"
        @test Scratchpad.completion_replacement_text(
            "test_val", 1:8, ["test_value"]) == "test_value"
        @test Scratchpad.completion_replacement_text(
            "alph", 1:4, ["alpha_one", "alpha_two"]) == "alpha_"
        @test Scratchpad.completion_replacement_text(
            "alpha_", 1:6, ["alpha_one", "alpha_two"]) === nothing
    end
end

@testset "native exception stack formatting" begin
    runtime = Module(:ScratchpadExceptionFormattingTest)
    formatted = try
        1 + "a"
        ""
    catch e
        @test e isa MethodError
        Scratchpad.format_current_exception_text(runtime)
    end

    @test startswith(formatted, "ERROR: MethodError")
    @test occursin("MethodError", formatted)
    @test occursin("Closest candidates are:", formatted)
    @test occursin("Stacktrace:", formatted)
    @test occursin("+", formatted)
    @test !occursin("\e[", formatted)
    _, style_id = Scratchpad.dynview_ids_for_line(formatted)
    @test style_id == Scratchpad.DynviewStyleError

    oversized = repeat("α", Scratchpad.MaxExceptionOutputBytes)
    truncated = Scratchpad.truncate_exception_output(oversized)
    @test ncodeunits(truncated) <= Scratchpad.MaxExceptionOutputBytes
    @test endswith(truncated, Scratchpad.ExceptionOutputTruncated)
    @test isvalid(truncated)
end

@testset "new runtime method candidates" begin
    runtime = Module(:ScratchpadRuntimeMethodCandidateTest)
    Core.eval(runtime, quote
        """Add two numbers; a two-argument method candidate fixture."""
        f(x, y) = x + y
    end)

    formatted = try
        Core.eval(runtime, :(f(2)))
        ""
    catch e
        @test e isa MethodError
        Scratchpad.format_current_exception_text(runtime)
    end

    @test startswith(formatted, "ERROR: MethodError: no method matching f(::Int64)")
    @test occursin("The function `f` exists", formatted)
    @test occursin("Closest candidates are:", formatted)
    @test occursin("f(::Any, !Matched::Any)", formatted)
end

@testset "native error SGR parsing" begin
    segments = Scratchpad.parse_native_error_segments(
        "\e[35mMain\e[39m \e[90m\e[4mREPL[1]:1\e[24m\e[39m")

    @test length(segments) == 3
    @test segments[1].text == "Main"
    @test segments[1].brush_color == Scratchpad.NativeErrorMagenta
    @test segments[2].text == " "
    @test segments[2].brush_color === nothing
    @test segments[3].text == "REPL[1]:1"
    @test segments[3].style_id == Scratchpad.DynviewStyleUnderline
    @test segments[3].brush_color == Scratchpad.NativeErrorGray
    @test !occursin('\e', join(segment.text for segment in segments))
end

@testset "evaluate newly defined function mismatch" begin
    with_test_session() do session
        session.metrics.queue_dequeued = 1
        Scratchpad.evaluate_queued_input!(TEST_SCRATCHPAD_RUNTIME,
            session, TEST_SCRATCHPAD_STATE_PTR, "f(x, y) = x + y")
        session.metrics.queue_dequeued = 2
        Scratchpad.evaluate_queued_input!(
            TEST_SCRATCHPAD_RUNTIME, session, TEST_SCRATCHPAD_STATE_PTR, "f(2)")

        output = join(session.output, "\n")
        @test session.metrics.eval_errors == 1
        @test occursin("ERROR: MethodError: no method matching f(::Int64)", output)
        @test occursin("The function `f` exists", output)
        @test occursin("Closest candidates are:", output)
        @test occursin("f(::Any, ::Any)", output)
        @test occursin("@ Main.$(nameof(session.runtime)) REPL[1]:1", output)
        @test occursin("@ REPL[2]:1", output)
        @test !occursin("eval(m::Module", output)
        @test !occursin("evaluate_queued_input!", output)
        @test !occursin('\e', output)
        @test any(==("Closest candidates are:"), session.output)
        @test any(==("Stacktrace:"), session.output)
        error_start = findfirst(entry ->
            startswith(entry.line, "ERROR:"), session.output_entries)
        @test error_start !== nothing
        error_entries =
            session.output_entries[error_start:lastindex(session.output_entries)]
        error_segments = reduce(vcat,
            (entry.segments for entry in error_entries); init=[])
        @test any(segment -> startswith(segment.text, "ERROR:") &&
            segment.style_id == Scratchpad.DynviewStyleBold &&
            segment.brush_color == Scratchpad.NativeErrorRed, error_segments)
        @test any(segment -> occursin("::Any", segment.text) &&
            segment.brush_color == Scratchpad.NativeErrorRed, error_segments)
        @test any(segment ->
            segment.brush_color == Scratchpad.NativeErrorGray, error_segments)
        @test any(segment -> occursin("REPL[", segment.text) &&
            segment.style_id == Scratchpad.DynviewStyleUnderline, error_segments)
        @test any(segment -> occursin("The function `f` exists", segment.text) &&
            segment.style_id == Scratchpad.DynviewStyleOutput &&
            segment.brush_color === nothing, error_segments)
        @test all(entry -> !occursin('\e', entry.line), error_entries)
        @test all(entry -> !occursin('\n', entry.line), session.output_entries)
    end
end

@testset "latex result formatting helpers" begin
    @test Scratchpad.normalize_latex_result_source("\$\\alpha\$") == "\\alpha"
    @test Scratchpad.normalize_latex_result_source(
        "\$\$\\frac{1}{2}\$\$") == "\\frac{1}{2}"
    @test Scratchpad.normalize_latex_result_source("\$\$\\alpha\$") == "\\alpha"
    @test Scratchpad.normalize_latex_result_source("\$\\alpha\$\$") == "\\alpha"
    @test Scratchpad.normalize_latex_result_source("\$\$\$\\alpha\$\$\$") == "\\alpha"
    @test Scratchpad.normalize_latex_result_source("x\$y") == "x\$y"
    @test Scratchpad.normalize_latex_result_source("  \\beta  ") == "\\beta"

    latex_source = Scratchpad.format_result_latex_source(
        ScratchpadLatexResultMock(), Main)
    @test latex_source == "\\frac{1}{2}"

    runtime = Scratchpad.create_runtime_module(TEST_SCRATCHPAD_RUNTIME, 4_001)
    malformed_latex = Main.LaTeXStrings.LaTeXString("\$\$\\alpha\$")
    @test Scratchpad.format_result_latex_source(malformed_latex, runtime) == "\\alpha"
    formatted_math = Scratchpad.format_result_latex(malformed_latex, runtime)
    @test formatted_math !== nothing
    @test formatted_math.is_math

    plain_source = Scratchpad.format_result_latex_source(
        ScratchpadPlainResultMock(), Main)
    @test plain_source === nothing
end

@testset "append eval result output" begin
    session = new_session()

    Scratchpad.append_eval_result_output!(session, ScratchpadLatexResultMock())
    @test length(session.output) == 1
    @test session.output[1] == "ScratchpadLatexResultMock()"
    @test length(session.output_entries) == 1
    @test session.output_entries[1].latex_source == "\\frac{1}{2}"
    @test !session.output_entries[1].latex_is_math
    @test Scratchpad.latest_latex_output(session) !== nothing

    runtime = Scratchpad.create_runtime_module(TEST_SCRATCHPAD_RUNTIME, 4_002)
    matrix_result = Core.eval(runtime,
        :(L"\\text{x} \\begin{matrix}1&2\\\\3&4\\end{matrix}"))
    Scratchpad.append_eval_result_output!(session, matrix_result)
    @test session.output_entries[2].latex_is_math

    document_session = new_session()
    Scratchpad.append_eval_result_output!(
        document_session, ScratchpadDocumentResultMock())
    document_entry = Scratchpad.latest_latex_output(document_session)
    @test document_entry !== nothing
    @test document_entry.line == "Definition\n\nA point has no part."
    @test document_entry.latex_source ==
        "\\textbf{Definition}\n\nA point has no part."

    Scratchpad.append_eval_result_output!(session, ScratchpadPlainResultMock())
    @test length(session.output) == 3
    @test session.output[3] == "ScratchpadPlainResultMock()"
    @test length(session.output_entries) == 3
    @test session.output_entries[3].latex_source == ""
end

@testset "history navigation" begin
    with_test_session() do session
        @test Scratchpad.history_previous(
            TEST_SCRATCHPAD_RUNTIME, TEST_SCRATCHPAD_STATE_PTR) == ""
        @test Scratchpad.history_next(
            TEST_SCRATCHPAD_RUNTIME, TEST_SCRATCHPAD_STATE_PTR) == ""

        append!(session.history, [
            Scratchpad.ScratchpadInputEntry("alpha", Scratchpad.InputModeJulia),
            Scratchpad.ScratchpadInputEntry("beta", Scratchpad.InputModeHelp),
            Scratchpad.ScratchpadInputEntry("gamma", Scratchpad.InputModeJulia),
        ])
        session.history_cursor = length(session.history) + 1

        @test Scratchpad.history_previous(
            TEST_SCRATCHPAD_RUNTIME, TEST_SCRATCHPAD_STATE_PTR,
            Scratchpad.InputModeHelp) == "0\ngamma"
        @test Scratchpad.history_previous(
            TEST_SCRATCHPAD_RUNTIME, TEST_SCRATCHPAD_STATE_PTR) == "1\nbeta"
        @test Scratchpad.history_previous(
            TEST_SCRATCHPAD_RUNTIME, TEST_SCRATCHPAD_STATE_PTR) == "0\nalpha"
        @test Scratchpad.history_previous(
            TEST_SCRATCHPAD_RUNTIME, TEST_SCRATCHPAD_STATE_PTR) == "0\nalpha"

        @test Scratchpad.history_next(
            TEST_SCRATCHPAD_RUNTIME, TEST_SCRATCHPAD_STATE_PTR) == "1\nbeta"
        @test Scratchpad.history_next(
            TEST_SCRATCHPAD_RUNTIME, TEST_SCRATCHPAD_STATE_PTR) == "0\ngamma"
        @test Scratchpad.history_next(
            TEST_SCRATCHPAD_RUNTIME, TEST_SCRATCHPAD_STATE_PTR) == "1\n"
        @test Scratchpad.history_next(
            TEST_SCRATCHPAD_RUNTIME, TEST_SCRATCHPAD_STATE_PTR) == "1\n"

        @test Scratchpad.history_reset_cursor(
            TEST_SCRATCHPAD_RUNTIME, TEST_SCRATCHPAD_STATE_PTR)
        @test session.history_cursor == length(session.history) + 1
    end
end

@testset "queue cap behavior" begin
    session = new_session(id = 2)

    total = Scratchpad.MaxQueueLines + 2
    for i in 1:total
        Scratchpad.queue_line!(session, "line-$(i)")
    end

    @test length(session.queue) == Scratchpad.MaxQueueLines
    @test first(session.queue).text == "line-3"
    @test first(session.queue).mode == Scratchpad.InputModeJulia
    @test last(session.queue).text == "line-$(total)"
    @test session.metrics.queue_dropped == 2
    @test session.metrics.queue_enqueued == total
    @test session.metrics.queue_high_water == Scratchpad.MaxQueueLines
end

@testset "module help doc fallback" begin
    runtime = Module(:ScratchpadHelpRuntime)
    Core.eval(runtime, :(const EuclidRepl = Main.EuclidRepl))

    binding = Base.Docs.Binding(runtime, :EuclidRepl)
    doc_entry = Scratchpad.resolve_module_doc_entry(binding, Main.EuclidRepl)

    @test doc_entry !== nothing
    rendered = Scratchpad.render_help_docs(doc_entry)
    @test rendered !== nothing
    @test occursin("REPL-first geometry helpers", rendered)
end

@testset "highlight helper aliases and bindings" begin
    @test haskey(Scratchpad.HELPER_DOC_ALIASES, "highlight_pen!")
    @test haskey(Scratchpad.HELPER_DOC_ALIASES, "highlight_compass!")
    @test haskey(Scratchpad.HELPER_DOC_ALIASES, "hide!")
    @test haskey(Scratchpad.HELPER_DOC_ALIASES, "euclidcolors")

    runtime = Scratchpad.create_runtime_module(TEST_SCRATCHPAD_RUNTIME, 5_001)
    @test isdefined(runtime, Symbol("highlight_pen!"))
    @test isdefined(runtime, Symbol("highlight_compass!"))
    @test isdefined(runtime, Symbol("hide!"))
    @test isdefined(runtime, Symbol("euclidcolors"))
    @test isdefined(runtime, :LaTeXStrings)
    @test isdefined(runtime, :Latexify)

    latex_value = Core.eval(runtime, :(L"\\alpha"))
    @test latex_value isa Main.LaTeXStrings.LaTeXString

    latexify_value = Core.eval(runtime, :(latexify([1 2; 3 4])))
    @test latexify_value !== nothing
end
