if !isdefined(Main, :CodeWiki)
    include("../../../tools/code_wiki.jl")
end

using .CodeWiki
using Test

@testset "static Julia extraction and rendering" begin
    mktempdir() do directory
        module_directory = joinpath(directory, "src", "julia")
        mkpath(module_directory)
        write(joinpath(module_directory, "sample.jl"), """
\"\"\"Sample module documentation.\"\"\"
module SampleModule

export greet, SampleType, SAMPLE_VALUE

include(\"methods.jl\")

\"\"\"Return a greeting for one integer.\"\"\"
function greet(value::Int)
    return string(value)
end

\"\"\"A documented sample type.\"\"\"
struct SampleType
    value::Int
end

\"\"\"A documented sample constant.\"\"\"
const SAMPLE_VALUE = 3

end
""")
        write(joinpath(module_directory, "methods.jl"), """
error(\"static extraction must not execute source\")

greet(value::String) = value

\"\"\"Return the input expression.\"\"\"
macro sample(expression)
    expression
end
""")

        config = JuliaWikiConfig(repository_root=directory)
        package = extract_julia_module(config, "src/julia/sample.jl")

        @test package.stable_id == "julia:SampleModule"
        @test package.doc_markdown == "Sample module documentation."
        @test package.source_files == ["methods.jl", "sample.jl"]

        greet = only(filter(symbol -> symbol.name == "greet", package.symbols))
        @test greet.visibility == :public
        @test greet.method_signatures == ["greet(value::Int)", "greet(value::String)"]
        @test greet.doc_markdown == "Return a greeting for one integer."
        @test greet.source_path == "src/julia/sample.jl"
        @test greet.source_line == 9

        sample_type = only(filter(symbol -> symbol.name == "SampleType", package.symbols))
        @test sample_type.declaration_kind == :struct
        @test sample_type.visibility == :public

        sample_constant = only(filter(
            symbol -> symbol.name == "SAMPLE_VALUE", package.symbols))
        @test sample_constant.declaration_kind == :constant

        sample_macro = only(filter(symbol -> symbol.name == "sample", package.symbols))
        @test sample_macro.declaration_kind == :macro

        rendered = render_julia_module_page(package)
        @test occursin("# Julia Module `SampleModule`", rendered)
        @test occursin("## Public API", rendered)
        @test occursin("[`greet`](#symbol-julia-SampleModule-function-greet)", rendered)
        @test !occursin("[`sample`](#symbol-julia-SampleModule-macro-sample)", rendered)
        @test occursin("## Functions", rendered)
        @test occursin("greet(value::String)", rendered)
        @test occursin("[Source](../../../../src/julia/sample.jl#L9)", rendered)
    end
end

@testset "live Julia module extraction" begin
    repository_root = abspath(joinpath(@__DIR__, "..", "..", ".."))
    config = JuliaWikiConfig(repository_root=repository_root)

    geometry = extract_julia_module(config, "src/julia/geometry.jl")
    @test geometry.display_name == "EuclidGeometry"
    @test occursin("Shared geometric intersection helpers", geometry.doc_markdown)
    @test length(filter(symbol -> !isempty(symbol.doc_markdown), geometry.symbols)) == 7

    latex = extract_julia_module(config, "src/julia/latex.jl")
    @test latex.display_name == "EuclidLatex"
    @test any(symbol -> symbol.name == "emit_latex_view_text!" &&
        symbol.visibility == :public, latex.symbols)
    rendered_latex = render_julia_module_page(latex)
    @test occursin(
        "[`emit_latex_view_text!`](#symbol-julia-EuclidLatex-function-emit-latex-view-text)",
        rendered_latex)

    bridge = extract_julia_module(config, "src/julia/odin-julia-bridge.jl")
    @test bridge.display_name == "OdinJuliaBridge"
    @test length(bridge.source_files) == 7
    create_label = only(filter(symbol -> symbol.name == "create_new_label", bridge.symbols))
    @test length(create_label.method_signatures) >= 16
    @test occursin("Construct a new label", create_label.doc_markdown)
end