using Colors

const Header = """package dynview_parse

// Generated from Colors.color_names by tools/generate_named_colors.jl.
// Regenerate with: julia --project=src/julia tools/generate_named_colors.jl

Tex_Named_Color :: struct {
    name: string,
    red, green, blue: u8,
}

TEX_NAMED_COLORS :: [?]Tex_Named_Color{
"""

"""Write the pinned Colors.jl named-color registry as immutable Odin data."""
function generate_named_colors(output_path::AbstractString)
    names = sort!(collect(keys(Colors.color_names)))
    open(output_path, "w") do io
        print(io, Header)
        for name in names
            red, green, blue = Colors.color_names[name]
            println(io, "    {\"$name\", $red, $green, $blue},")
        end
        println(io, "}")
    end
end

generate_named_colors(isempty(ARGS) ?
    joinpath(@__DIR__, "..", "src", "dynview", "parse", "named_colors.odin") : ARGS[1])