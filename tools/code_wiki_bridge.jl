Base.@kwdef struct BridgeOdinExport
    abi_name::String
    signature::String
    parameter_types::Vector{String}
    return_type::String
    doc_markdown::String
    source_path::String
    source_line::Int
    symbol::DocumentationSymbol
end

Base.@kwdef struct BridgeJuliaCall
    abi_name::String
    wrapper_name::String
    wrapper_signature::String
    abi_signature::String
    parameter_types::Vector{String}
    return_type::String
    doc_markdown::String
    source_path::String
    source_line::Int
    symbol::DocumentationSymbol
end

Base.@kwdef struct BridgePair
    abi_name::String
    odin_export::BridgeOdinExport
    julia_calls::Vector{BridgeJuliaCall}
end

Base.@kwdef struct JuliaCcallParts
    abi_name::String
    parameter_types::Vector{String}
    return_type::String
end

Base.@kwdef struct OdinAbiParts
    parameter_types::Vector{String}
    return_type::String
end

"""Split one compiler-normalized Odin parameter list without nested commas."""
function split_odin_abi_parameters(parameters::AbstractString)
    isempty(strip(parameters)) && return String[]
    types = String[]
    pending_names = 0
    for part in split(parameters, ',')
        separator = findfirst(':', part)
        if separator === nothing
            pending_names += 1
            continue
        end
        parameter_type = strip(part[last(separator) + 1:end])
        append!(types, fill(parameter_type, pending_names + 1))
        pending_names = 0
    end
    pending_names == 0 || error("Malformed grouped Odin ABI parameters: $parameters")
    return types
end

"""Parse parameter and return types from one compiler-normalized Odin procedure."""
function parse_odin_abi_signature(signature::String)
    matched = match(r"::\s*proc\((.*)\)(?:\s*->\s*([^\{]+))?\s*\{\.\.\.\}$", signature)
    matched === nothing && error("Malformed Odin ABI signature: $signature")
    parameters = split_odin_abi_parameters(matched.captures[1])
    return_type = matched.captures[2] === nothing ? "void" : strip(matched.captures[2])
    return OdinAbiParts(parameter_types=parameters, return_type=return_type)
end

"""Build normalized bridge-export records from all project Odin packages."""
function extract_odin_bridge_exports(packages::Vector{DocumentationPackage})
    exports = BridgeOdinExport[]
    for package in packages, symbol in package.symbols
        symbol.declaration_kind == :exported_abi_procedure || continue
        parts = parse_odin_abi_signature(symbol.signature)
        parameters = parts.parameter_types
        return_type = parts.return_type
        push!(exports, BridgeOdinExport(
            abi_name=symbol.name, signature=symbol.signature,
            parameter_types=parameters, return_type=return_type,
            doc_markdown=symbol.doc_markdown, source_path=symbol.source_path,
            source_line=symbol.source_line, symbol=symbol))
    end
    return sort!(exports; by=exported -> exported.abi_name)
end

"""Collect all descendant syntax nodes of one parser kind."""
function collect_julia_syntax_kind!(matches::Vector, node, expected::Symbol)
    julia_syntax_kind(node) == expected && push!(matches, node)
    for child in julia_syntax_children(node)
        collect_julia_syntax_kind!(matches, child, expected)
    end
    return matches
end

"""Return a stable source spelling for one Julia type expression."""
julia_abi_type_text(expression) = replace(string(expression), " " => "")

"""Decode one statically parsed local `@ccall` expression."""
function parse_julia_ccall_expression(source::AbstractString)
    expression = Meta.parse(source)
    expression isa Expr && expression.head == :macrocall ||
        error("Malformed Julia @ccall expression: $source")
    expression.args[1] == Symbol("@ccall") ||
        error("Unsupported Julia bridge macro call: $source")
    call, return_type = julia_ccall_typed_call(last(expression.args), source)
    parameter_types = julia_ccall_parameter_types(call, source)
    return JuliaCcallParts(abi_name=String(call.args[1]),
        parameter_types=parameter_types, return_type=return_type)
end

"""Validate and split the typed call of one `@ccall` into its call and return type."""
function julia_ccall_typed_call(typed_call, source::AbstractString)
    typed_call isa Expr && typed_call.head == :(::) ||
        error("Julia @ccall requires an explicit return type: $source")
    call = typed_call.args[1]
    call isa Expr && call.head == :call && call.args[1] isa Symbol ||
        error("Julia bridge calls require a bare ABI symbol: $source")
    return call, julia_abi_type_text(typed_call.args[2])
end

"""Collect the explicit type of each argument in one `@ccall` call expression."""
function julia_ccall_parameter_types(call, source::AbstractString)
    parameter_types = String[]
    for argument in call.args[2:end]
        argument isa Expr && argument.head == :(::) ||
            error("Julia @ccall argument requires an explicit type: $source")
        push!(parameter_types, julia_abi_type_text(last(argument.args)))
    end
    return parameter_types
end

"""Return the normalized Julia symbol that owns one wrapper declaration."""
function bridge_wrapper_symbol(package::DocumentationPackage, wrapper_name::String)
    matches = filter(symbol -> symbol.name == wrapper_name &&
        symbol.declaration_kind == :function, package.symbols)
    isempty(matches) &&
        error("Julia bridge wrapper is missing from the symbol model: $wrapper_name")
    return only(matches)
end

"""Extract local `@ccall` sites from one Julia wrapper declaration."""
function extract_wrapper_ccalls(
    declaration, package::DocumentationPackage, source::String, source_path::String)

    wrapper_identity = julia_declaration_identity(declaration)
    wrapper_name = wrapper_identity.name
    wrapper_signature = wrapper_identity.signature
    wrapper_symbol = bridge_wrapper_symbol(package, wrapper_name)
    macro_calls = collect_julia_syntax_kind!(Any[], declaration, :macrocall)
    calls = BridgeJuliaCall[]
    for macro_call in macro_calls
        macro_source = strip(julia_syntax_text(macro_call))
        startswith(macro_source, "@ccall ") || continue
        ccall_parts = parse_julia_ccall_expression(macro_source)
        push!(calls, BridgeJuliaCall(
            abi_name=ccall_parts.abi_name, wrapper_name=wrapper_name,
            wrapper_signature=wrapper_signature,
            abi_signature=String(macro_source[8:end]),
            parameter_types=ccall_parts.parameter_types,
            return_type=ccall_parts.return_type,
            doc_markdown=wrapper_symbol.doc_markdown,
            source_path=source_path,
            source_line=julia_source_line(source, JuliaSyntax.first_byte(macro_call)),
            symbol=wrapper_symbol))
    end
    return calls
end

"""Extract all bridge call sites from a statically parsed Julia module."""
function extract_julia_bridge_calls(
    package::DocumentationPackage, repository_root::String)

    calls = BridgeJuliaCall[]
    for source_file in package.source_files
        source_path = normalize_repo_path(joinpath(package.source_root, source_file))
        source = read(joinpath(repository_root, source_path), String)
        tree = JuliaSyntax.parseall(JuliaSyntax.SyntaxNode, source)
        for node in julia_container_nodes(tree)
            declaration, _ = julia_documented_declaration(node)
            declaration === nothing && (declaration = unwrap_julia_declaration(node))
            declaration === nothing && continue
            julia_syntax_kind(declaration) == :function || continue
            append!(calls, extract_wrapper_ccalls(
                declaration, package, source, source_path))
        end
    end
    return sort!(calls; by=call ->
        (call.abi_name, call.source_path))
end

const ODIN_ABI_TYPE_ALIASES = Dict(
    "void" => "void",
    "^core.Euclid_General_State" => "pointer",
    "^julialib.jl_value_t" => "julia-value",
    "^Animation_Callbacks" => "animation-callbacks",
    "rawptr" => "pointer",
    "cstring" => "cstring",
    "rune" => "u32",
    "core.Vector3" => "vector3-f32",
    "Bridge_Color" => "bridge-color",
    "Bridge_Point_View" => "bridge-point-view",
    "Bridge_Constraint_View" => "bridge-constraint-view",
    "Bridge_Constraint_Spec" => "bridge-constraint-spec",
    "Bridge_Solve_Result" => "bridge-solve-result",
    "Bridge_Dynview_Style" => "bridge-dynview-style",
    "Bridge_Pentagon_Colors" => "bridge-pentagon-colors",
    "Bridge_Triangle_Colors" => "bridge-triangle-colors",
    "Bridge_Box_Edge_Colors" => "bridge-box-edge-colors",
    "Bridge_Pie_Colors" => "bridge-pie-colors",
    "Bridge_Dynview_Document_Request" => "bridge-document-request",
    "Bridge_Dynview_Math_Request" => "bridge-math-request",
    "core.Bridge_Inline_Box_Dims" => "bridge-inline-box-dims",
    "core.Bridge_Inline_Size" => "bridge-inline-size",
    "core.Bridge_Inline_Perpendicular_Dims" => "bridge-inline-perpendicular-dims",
    "core.Bridge_Perpendicular_Colors" => "bridge-perpendicular-colors",
    "core.Bridge_Pie_Section_Geometry" => "bridge-pie-section-geometry",
    "core.Bridge_Arc_Geometry" => "bridge-arc-geometry",
    "core.Bridge_Label_Glyph" => "bridge-label-glyph",
    "core.Bridge_Square_Vertices" => "bridge-square-vertices",
    "core.Bridge_Pentagon_Vertices" => "bridge-pentagon-vertices",
    "core.Shapes_Line" => "bridge-shape-line",
    "core.Shapes_Circle" => "bridge-shape-circle",
    "core.Shapes_Filled_Circle" => "bridge-shape-filled-circle",
    "core.Shapes_Triangle" => "bridge-shape-triangle",
    "core.Shapes_Square" => "bridge-shape-square",
    "core.Shapes_Pentagon" => "bridge-shape-pentagon",
    "core.Shapes_Pen" => "bridge-shape-pen",
    "core.Shapes_Compass" => "bridge-shape-compass",
    "Animation_Value_Abi_Identity" => "animation-value-identity",
    "Animation_Descriptor_Abi_Metadata" => "animation-descriptor-metadata",
    "[^]i32" => "pointer-i32", "^i32" => "pointer-i32",
    "[^]f32" => "pointer-f32", "^f32" => "pointer-f32",
    "int" => "i64", "i32" => "i32", "u8" => "u8", "u32" => "u32",
    "u64" => "u64", "f32" => "f32", "bool" => "bool")

const JULIA_ABI_TYPE_ALIASES = Dict(
    "Cvoid" => "void", "Ptr{Cvoid}" => "pointer", "Any" => "julia-value",
    "Cstring" => "cstring", "UInt32" => "u32",
    "Ref{AnimationCallbacksABI}" => "animation-callbacks",
    "AnimationValueIdentityABI" => "animation-value-identity",
    "AnimationDescriptorABIMetadata" => "animation-descriptor-metadata",
    "NTuple{3,Cfloat}" => "vector3-f32", "BridgeColor" => "bridge-color",
    "BridgePointView" => "bridge-point-view",
    "BridgeConstraintView" => "bridge-constraint-view",
    "BridgeConstraintSpec" => "bridge-constraint-spec",
    "BridgeSolveResult" => "bridge-solve-result",
    "BridgeDynviewStyle" => "bridge-dynview-style",
    "BridgePentagonColors" => "bridge-pentagon-colors",
    "BridgeTriangleColors" => "bridge-triangle-colors",
    "BridgeBoxEdgeColors" => "bridge-box-edge-colors",
    "BridgePieColors" => "bridge-pie-colors",
    "BridgeDynviewDocumentRequest" => "bridge-document-request",
    "BridgeDynviewMathRequest" => "bridge-math-request",
    "BridgeInlineBoxDims" => "bridge-inline-box-dims",
    "BridgeInlineSize" => "bridge-inline-size",
    "BridgeInlinePerpendicularDims" => "bridge-inline-perpendicular-dims",
    "BridgePerpendicularColors" => "bridge-perpendicular-colors",
    "BridgePieSectionGeometry" => "bridge-pie-section-geometry",
    "BridgeArcGeometry" => "bridge-arc-geometry",
    "BridgeLabelGlyph" => "bridge-label-glyph",
    "BridgeSquareVertices" => "bridge-square-vertices",
    "BridgePentagonVertices" => "bridge-pentagon-vertices",
    "BridgeShapeLine" => "bridge-shape-line",
    "BridgeShapeCircle" => "bridge-shape-circle",
    "BridgeShapeFilledCircle" => "bridge-shape-filled-circle",
    "BridgeShapeTriangle" => "bridge-shape-triangle",
    "BridgeShapeSquare" => "bridge-shape-square",
    "BridgeShapePentagon" => "bridge-shape-pentagon",
    "BridgeShapePen" => "bridge-shape-pen",
    "BridgeShapeCompass" => "bridge-shape-compass",
    "Ptr{Cint}" => "pointer-i32", "Ref{Int32}" => "pointer-i32",
    "Ptr{Cfloat}" => "pointer-f32", "Ref{Cfloat}" => "pointer-f32",
    "Int64" => "i64", "Int32" => "i32", "Cint" => "i32",
    "UInt8" => "u8", "UInt64" => "u64", "Cfloat" => "f32",
    "Bool" => "bool")

"""Return one canonical ABI type or fail on an unreviewed spelling."""
function canonical_abi_type(
    type_name::String, aliases::Dict{String,String}, language::String)
    canonical = get(aliases, replace(type_name, " " => ""), nothing)
    canonical === nothing && error("Unknown $language ABI type: $type_name")
    return canonical
end

"""Validate one Julia call site against its paired Odin export signature."""
function validate_bridge_signature(exported::BridgeOdinExport, call::BridgeJuliaCall)
    odin_parameters = [canonical_abi_type(value, ODIN_ABI_TYPE_ALIASES, "Odin")
        for value in exported.parameter_types]
    julia_parameters = [canonical_abi_type(value, JULIA_ABI_TYPE_ALIASES, "Julia")
        for value in call.parameter_types]
    odin_parameters == julia_parameters || error(
        "Bridge parameter drift for $(exported.abi_name): " *
        "Odin $(exported.parameter_types), Julia $(call.parameter_types)")
    odin_return = canonical_abi_type(exported.return_type, ODIN_ABI_TYPE_ALIASES, "Odin")
    julia_return = canonical_abi_type(call.return_type, JULIA_ABI_TYPE_ALIASES, "Julia")
    odin_return == julia_return || error(
        "Bridge return drift for $(exported.abi_name): " *
        "Odin $(exported.return_type), Julia $(call.return_type)")
    return true
end

"""Pair project-owned Odin exports with grouped Julia call sites and reject drift."""
function pair_bridge_records(
    exports::Vector{BridgeOdinExport}, calls::Vector{BridgeJuliaCall},
    exceptions::Vector{String}=String[])

    export_names = [exported.abi_name for exported in exports]
    length(unique(export_names)) == length(export_names) ||
        error("Duplicate Odin bridge ABI ownership.")
    known_names = union(Set(export_names), Set(call.abi_name for call in calls))
    stale_exceptions = setdiff(Set(exceptions), known_names)
    isempty(stale_exceptions) || error(
        "Stale bridge exceptions: $(join(sort!(collect(stale_exceptions)), ", "))")
    export_by_name = Dict(exported.abi_name => exported for exported in exports)
    calls_by_name = Dict(name => filter(call -> call.abi_name == name, calls)
        for name in unique(call.abi_name for call in calls))
    unpaired = setdiff(union(Set(keys(export_by_name)),
        Set(keys(calls_by_name))), Set(exceptions))
    orphans = sort!([name for name in unpaired if
        !haskey(export_by_name, name) || !haskey(calls_by_name, name)])
    isempty(orphans) || error("Orphaned bridge ABI symbols: $(join(orphans, ", "))")
    pairs = BridgePair[]
    for name in sort!(
        collect(intersect(Set(keys(export_by_name)), Set(keys(calls_by_name)))))
        name in exceptions && continue
        exported = export_by_name[name]
        isempty(exported.doc_markdown) &&
            error("Missing Odin bridge documentation: $name")
        grouped_calls = calls_by_name[name]
        all(call -> !isempty(call.doc_markdown), grouped_calls) ||
            error("Missing Julia bridge documentation: $name")
        foreach(call -> validate_bridge_signature(exported, call), grouped_calls)
        push!(pairs, BridgePair(
            abi_name=name, odin_export=exported, julia_calls=grouped_calls))
        exported.symbol.related_symbol_ids = ["bridge:$name"]
        foreach(call -> call.symbol.related_symbol_ids = ["bridge:$name"], grouped_calls)
    end
    return pairs
end

"""Extract and pair the complete project-owned Odin-Julia bridge surface."""
function extract_bridge_pairs(
    packages::Vector{DocumentationPackage}, repository_root::String;
    exceptions::Vector{String}=String[])

    exports = extract_odin_bridge_exports(packages)
    bridge_package = only(filter(package ->
        package.stable_id == "julia:OdinJuliaBridge", packages))
    calls = extract_julia_bridge_calls(bridge_package, repository_root)
    return pair_bridge_records(exports, calls, exceptions)
end

"""Render source links for all distinct call sites in one Julia wrapper group."""
function render_bridge_call_sources!(
    io::IO, calls::Vector{BridgeJuliaCall}, source_link_prefix::String)

    links = [
        "[Source $(index)]($(source_link_prefix)$(call.source_path)#L$(call.source_line))"
        for (index, call) in enumerate(calls)]
    write(io, join(links, " | "), "\n\n")
end

"""Render one deterministic cross-language Odin-Julia bridge reference page."""
function render_bridge_page(pairs::Vector{BridgePair};
    source_link_prefix::String="../../../../")

    io = IOBuffer()
    write(io, generated_wiki_banner(), "# Odin-Julia Bridge\n\n",
        "Validated mappings between Julia wrappers and exported Odin C ABI procedures.\n\n",
        "Bridge symbols: `", string(length(pairs)), "`\n")
    for pair in sort(pairs; by=item -> item.abi_name)
        anchor = "bridge-abi-" * replace(lowercase(pair.abi_name), '_' => '-')
        write(io, "\n<a id=\"", anchor, "\"></a>\n\n## `", pair.abi_name, "`\n\n",
            "ABI symbol: `", pair.abi_name, "`\n\n### Julia wrappers\n")
        wrapper_names = sort!(unique(call.wrapper_name for call in pair.julia_calls))
        for wrapper_name in wrapper_names
            calls = sort(
                filter(call -> call.wrapper_name == wrapper_name, pair.julia_calls);
                by=call -> (call.source_path, call.source_line))
            wrapper_signatures = sort!(unique(call.wrapper_signature for call in calls))
            abi_signatures = sort!(unique(call.abi_signature for call in calls))
            write(io, "\n#### `", wrapper_name, "`\n\n```julia\n",
                join(wrapper_signatures, "\n"), "\n```\n\n",
                "Typed ABI calls:\n\n```julia\n", join(abi_signatures, "\n"), "\n```\n\n")
            render_bridge_call_sources!(io, calls, source_link_prefix)
            write(io, shift_markdown_headings(first(calls).doc_markdown), "\n")
        end
        exported = pair.odin_export
        write(io, "\n### Odin export\n\n```odin\n", exported.signature, "\n```\n\n")
        write(io, "[Source](", source_link_prefix, exported.source_path,
            "#L", string(exported.source_line), ")\n\n",
            shift_markdown_headings(exported.doc_markdown), "\n")
    end
    return String(take!(io))
end