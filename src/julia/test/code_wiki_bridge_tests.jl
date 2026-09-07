if !isdefined(Main, :CodeWiki)
    include("../../../tools/code_wiki.jl")
end

using .CodeWiki
using Test

"""Build a minimal bridge export symbol payload for testing."""
function bridge_test_export(; name="ping", parameter_type="i32", return_type="i32")
    symbol = DocumentationSymbol(
        language=:odin, stable_id="odin:bridge:exported_abi_procedure:$name",
        package_id="odin:bridge", name=name, qualified_name="bridge.$name",
        declaration_kind=:exported_abi_procedure,
        signature="$name :: proc(value: $parameter_type) -> $return_type {...}",
        doc_markdown="Odin boundary documentation.", source_path="src/bridge/abi.odin",
        source_line=4, exported_abi_name=name)
    return CodeWiki.BridgeOdinExport(
        abi_name=name, signature=symbol.signature, parameter_types=[parameter_type],
        return_type=return_type, doc_markdown=symbol.doc_markdown,
        source_path=symbol.source_path, source_line=symbol.source_line, symbol=symbol)
end

"""Build a minimal bridge call-site payload for testing."""
function bridge_test_call(; name="ping", parameter_type="Int32", return_type="Int32")
    symbol = DocumentationSymbol(
        language=:julia, stable_id="julia:Bridge:function:$name",
        package_id="julia:Bridge", name=name, qualified_name="Bridge.$name",
        declaration_kind=:function, signature="$name(value)",
        doc_markdown="Julia wrapper documentation.", source_path="src/julia/bridge.jl",
        source_line=4)
    return CodeWiki.BridgeJuliaCall(
        abi_name=name, wrapper_name=name, wrapper_signature=symbol.signature,
        abi_signature="$name(value::$parameter_type)::$return_type",
        parameter_types=[parameter_type], return_type=return_type,
        doc_markdown=symbol.doc_markdown, source_path=symbol.source_path,
        source_line=symbol.source_line, symbol=symbol)
end

@testset "bridge pairing and drift" begin
    exported = bridge_test_export()
    first_call = bridge_test_call()
    second_call = bridge_test_call()
    pairs = CodeWiki.pair_bridge_records([exported], [first_call, second_call])

    @test length(pairs) == 1
    @test length(only(pairs).julia_calls) == 2
    @test exported.symbol.related_symbol_ids == ["bridge:ping"]
    @test_throws ErrorException CodeWiki.pair_bridge_records(
        [exported], BridgeJuliaCall[])
    @test_throws ErrorException CodeWiki.pair_bridge_records(
        [exported], [bridge_test_call(parameter_type="Cfloat")])
    identity_export = bridge_test_export(
        parameter_type="Animation_Value_Abi_Identity")
    identity_call = bridge_test_call(parameter_type="AnimationValueIdentityABI")
    @test length(CodeWiki.pair_bridge_records(
        [identity_export], [identity_call])) == 1
    metadata_export = bridge_test_export(
        parameter_type="Animation_Descriptor_Abi_Metadata")
    metadata_call = bridge_test_call(
        parameter_type="AnimationDescriptorABIMetadata")
    @test length(CodeWiki.pair_bridge_records(
        [metadata_export], [metadata_call])) == 1
    @test isempty(CodeWiki.pair_bridge_records([exported], BridgeJuliaCall[], ["ping"]))
    @test_throws ErrorException CodeWiki.pair_bridge_records(
        [exported], BridgeJuliaCall[], ["unknown"])

    rendered = CodeWiki.render_bridge_page(pairs)
    @test rendered == CodeWiki.render_bridge_page(pairs)
    @test occursin("# Odin-Julia Bridge", rendered)
    @test occursin("## `ping`", rendered)
    @test occursin("ping(value::Int32)::Int32", rendered)
    @test occursin(exported.signature, rendered)
end

@testset "live bridge extraction" begin
    repository_root = abspath(joinpath(@__DIR__, "..", "..", ".."))
    packages = CodeWiki.extract_default_wiki_packages(repository_root)
    pairs = extract_bridge_pairs(packages, repository_root)

    @test length(pairs) == 128
    @test sum(length(pair.julia_calls) for pair in pairs) == 138
    @test first(pairs).abi_name < last(pairs).abi_name
    @test all(pair -> !isempty(pair.odin_export.doc_markdown), pairs)
    @test all(pair -> all(call -> !isempty(call.doc_markdown), pair.julia_calls), pairs)
end