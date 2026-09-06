using Test

@testset "EuclidApp Julia Tests" begin
    @testset "Geometry" begin
        include("geometry_tests.jl")
    end

    @testset "Scratchpad" begin
        include("scratchpad_tests.jl")
    end

    @testset "EuclidRepl" begin
        include("euclidrepl_tests.jl")
    end

    @testset "Bridge Helpers" begin
        include("bridge_helpers_tests.jl")
    end

    @testset "Animation Catalog" begin
        include("animation_catalog_tests.jl")
    end

    @testset "Runtime Host" begin
        include("runtime_host_tests.jl")
    end

    @testset "Code Wiki Odin" begin
        include("code_wiki_tests.jl")
    end

    @testset "Code Wiki Julia" begin
        include("code_wiki_julia_tests.jl")
    end

    @testset "Code Wiki Navigation" begin
        include("code_wiki_navigation_tests.jl")
    end

    @testset "Code Wiki Bridge" begin
        include("code_wiki_bridge_tests.jl")
    end
end
