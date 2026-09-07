module CodeWiki

using JuliaSyntax
using TOML

export DocumentationPackage, DocumentationSymbol, OdinWikiConfig,
    discover_odin_packages, parse_odin_doc, extract_odin_package,
    render_odin_package_page, write_odin_package_page,
    JuliaWikiConfig, extract_julia_module, render_julia_module_page,
    write_julia_module_page, WikiManifest, WikiSection, WikiGuide,
    WikiGuideRelation, load_wiki_manifest, validate_wiki_manifest,
    assign_package_page_paths, apply_guide_relations!, write_code_wiki,
    validate_managed_outputs, validate_wiki_links, BridgeOdinExport,
    BridgeJuliaCall, BridgePair, extract_bridge_pairs, WikiOutput,
    validate_wiki_outputs, write_wiki_outputs, build_code_wiki_outputs,
    build_wiki_compositor_outputs, build_authored_guide_outputs,
    generate_wiki_artifact, sync_wiki_artifact

Base.@kwdef mutable struct DocumentationSymbol
    language::Symbol
    stable_id::String
    package_id::String
    name::String
    qualified_name::String
    declaration_kind::Symbol
    signature::String
    doc_markdown::String = ""
    source_path::String = ""
    source_line::Int = 0
    visibility::Symbol = :all
    exported_abi_name::Union{Nothing,String} = nothing
    related_symbol_ids::Vector{String} = String[]
    authored_document_refs::Vector{String} = String[]
    method_signatures::Vector{String} = String[]
    diagnostics::Vector{String} = String[]
end

Base.@kwdef mutable struct DocumentationPackage
    language::Symbol
    stable_id::String
    display_name::String
    source_root::String
    source_files::Vector{String} = String[]
    doc_markdown::String = ""
    child_package_ids::Vector{String} = String[]
    authored_document_refs::Vector{String} = String[]
    diagnostics::Vector{String} = String[]
    symbols::Vector{DocumentationSymbol} = DocumentationSymbol[]
end

Base.@kwdef struct OdinWikiConfig
    repository_root::String
    approved_roots::Vector{String} = ["src"]
    excluded_roots::Vector{String} = String[]
end

"""Return a normalized repository-relative path using forward slashes."""
normalize_repo_path(path::AbstractString) = replace(normpath(String(path)), '\\' => '/')

"""Return whether `path` is equal to or nested beneath one excluded root."""
function path_is_excluded(path::String, excluded_roots::Vector{String})
    normalized = normalize_repo_path(path)
    return any(excluded_roots) do excluded
        root = normalize_repo_path(excluded)
        normalized == root || startswith(normalized, root * "/")
    end
end

"""Discover project-local Odin package directories under configured roots."""
function discover_odin_packages(config::OdinWikiConfig)
    packages = String[]
    excluded = normalize_repo_path.(config.excluded_roots)
    for approved_root in sort(config.approved_roots)
        absolute_root = joinpath(config.repository_root, approved_root)
        isdir(absolute_root) || error("Odin documentation root does not exist: $approved_root")
        for (directory, subdirectories, files) in walkdir(absolute_root)
            relative = normalize_repo_path(relpath(directory, config.repository_root))
            filter!(name -> !path_is_excluded(
                normalize_repo_path(joinpath(relative, name)), excluded), subdirectories)
            if !path_is_excluded(relative, excluded) && any(endswith(".odin"), files)
                push!(packages, relative)
            end
        end
    end
    return sort!(unique!(packages))
end

"""Remove the compiler's opaque location suffix from a declaration."""
function strip_odin_location_suffix(declaration::AbstractString)
    stripped = strip(replace(
        String(declaration), r"\s*/\*\s*\d+!\d+\s*\*/\s*$" => ""))
    return String(stripped)
end

"""Classify one compiler-normalized Odin declaration."""
function odin_declaration_kind(signature::String)
    occursin(r"::\s*proc_group\b", signature) && return :procedure_group
    occursin(r"::\s*proc\b", signature) && return :procedure
    occursin(r"::\s*struct\b", signature) && return :struct
    occursin(r"::\s*enum\b", signature) && return :enum
    occursin(r"::\s*union\b", signature) && return :union
    return :constant
end

"""Normalize compiler-emitted comment indentation while preserving Markdown nesting."""
function normalize_odin_doc_comment(lines::Vector{String})
    while !isempty(lines) && isempty(strip(first(lines)))
        popfirst!(lines)
    end
    while !isempty(lines) && isempty(strip(last(lines)))
        pop!(lines)
    end
    normalized = map(lines) do line
        startswith(line, "  ") ? line[3:end] : line
    end
    return join(normalized, "\n")
end

"""Build one normalized symbol from compiler declaration text."""
function parsed_odin_symbol(
    package_id::String, package_name::String, source_root::String,
    source_file::AbstractString, declaration::AbstractString,
    comment_lines::Vector{String})

    signature = strip_odin_location_suffix(String(declaration))
    separator = something(findfirst("::", signature), findfirst(":=", signature), nothing)
    separator === nothing && error("Malformed Odin declaration: $declaration")
    name = strip(signature[firstindex(signature):first(separator) - 1])
    kind = odin_declaration_kind(signature)
    return DocumentationSymbol(
        language=:odin,
        stable_id="odin:$package_id:$kind:$name",
        package_id=package_id,
        name=name,
        qualified_name="$package_name.$name",
        declaration_kind=kind,
        signature=signature,
        doc_markdown=normalize_odin_doc_comment(comment_lines),
        source_path=normalize_repo_path(joinpath(source_root, String(source_file))),
        visibility=isempty(comment_lines) ? :all : :documented)
end

"""Collect comment lines immediately following one declaration record."""
function collect_odin_comment_lines(lines::Vector{String}, start_index::Int)
    comments = String[]
    index = start_index
    while index <= length(lines)
        line = lines[index]
        if startswith(line, "\t\t\t")
            push!(comments, line[4:end])
        elseif isempty(line)
            push!(comments, "")
        else
            break
        end
        index += 1
    end
    return comments, index
end

"""Parse standard textual `odin doc` output into a normalized package record."""
function parse_odin_doc(output::AbstractString, source_root::AbstractString)
    lines = String.(split(replace(String(output), "\r\n" => "\n"), '\n'; keepempty=true))
    isempty(lines) && error("Odin documentation output is empty.")
    startswith(first(lines), "package ") || error("Expected Odin package header.")
    package_name = strip(first(lines)[9:end])
    normalized_root = normalize_repo_path(source_root)
    package_id = "odin:" * replace(normalized_root, '/' => ':')
    package = DocumentationPackage(
        language=:odin, stable_id=package_id, display_name=package_name,
        source_root=normalized_root)
    parse_odin_doc_body!(package, lines)
    return package
end

"""Parse file, declaration, and metadata records into one package."""
function parse_odin_doc_body!(package::DocumentationPackage, lines::Vector{String})
    current_file = ""
    index = 2
    while index <= length(lines)
        line = lines[index]
        if startswith(line, "\tfile: ")
            current_file = strip(line[8:end])
            push!(package.source_files, current_file)
            index += 1
        elseif startswith(line, "\t\t") && !startswith(line, "\t\t\t")
            isempty(current_file) && error("Odin declaration appeared before a file record.")
            comments, next_index = collect_odin_comment_lines(lines, index + 1)
            push!(package.symbols, parsed_odin_symbol(
                package.stable_id, package.display_name, package.source_root,
                current_file, line[3:end], comments))
            index = next_index
        elseif line == "\tfullpath:"
            index += 2
        elseif line == "\tfiles:"
            break
        elseif isempty(line)
            index += 1
        else
            error("Unrecognized Odin documentation hierarchy at line $index: $(repr(line))")
        end
    end
    sort!(unique!(package.source_files))
end

"""Return the top-level source line for an exact Odin declaration name."""
function find_odin_declaration_line(lines::Vector{String}, name::String)
    for (index, line) in pairs(lines)
        startswith(line, name) || continue
        separator = something(findfirst("::", line), findfirst(":=", line), nothing)
        separator === nothing && continue
        strip(line[firstindex(line):first(separator) - 1]) == name && return index
    end
    return 0
end

"""Return whether source around a declaration identifies an exported C ABI procedure."""
function odin_source_is_exported_abi(lines::Vector{String}, source_line::Int)
    source_line <= 0 && return false
    header_end = min(length(lines), source_line + 12)
    header = join(lines[source_line:header_end], "\n")
    previous = source_line > 1 ? strip(lines[source_line - 1]) : ""
    return occursin("proc \"c\"", header) && previous == "@(export)"
end

"""Return a package comment immediately following an Odin `package` declaration."""
function odin_package_comment(lines::Vector{String})
    package_line = findfirst(line -> startswith(line, "package "), lines)
    package_line === nothing && return ""
    index = package_line + 1
    while index <= length(lines) && isempty(strip(lines[index]))
        index += 1
    end
    comments = String[]
    while index <= length(lines) && startswith(lines[index], "//")
        line = lines[index][3:end]
        push!(comments, startswith(line, " ") ? line[2:end] : line)
        index += 1
    end
    return join(comments, "\n")
end

"""Populate the canonical package comment from its package-named source file when available."""
function enrich_odin_package_comment!(
    package::DocumentationPackage, repository_root::String)
    isempty(package.source_files) && return package
    preferred_name = package.display_name * ".odin"
    source_file = preferred_name in package.source_files ?
        preferred_name : first(sort(package.source_files))
    source_path = joinpath(repository_root, package.source_root, source_file)
    package.doc_markdown = odin_package_comment(readlines(source_path))
    return package
end

"""Enrich compiler records with narrow source locations and ABI classification."""
function enrich_odin_source_metadata!(
    package::DocumentationPackage, repository_root::String)
    files = Dict{String,Vector{String}}()
    for symbol in package.symbols
        lines = get!(files, symbol.source_path) do
            path = joinpath(repository_root, symbol.source_path)
            isfile(path) || error("Documented Odin source file does not exist: $(symbol.source_path)")
            readlines(path)
        end
        symbol.source_line = find_odin_declaration_line(lines, symbol.name)
        if symbol.source_line == 0
            push!(symbol.diagnostics, "Source declaration line was not found.")
        elseif odin_source_is_exported_abi(lines, symbol.source_line)
            symbol.declaration_kind = :exported_abi_procedure
            symbol.exported_abi_name = symbol.name
        end
    end
    enrich_odin_package_comment!(package, repository_root)
    return package
end

"""Return the stable package ID for one normalized Odin source path."""
odin_package_id(source_root::String) = "odin:" * replace(source_root, '/' => ':')

"""Populate immediate child package IDs from the discovered package inventory."""
function enrich_odin_child_packages!(
    package::DocumentationPackage, discovered_packages::Vector{String})

    children = filter(path -> normalize_repo_path(dirname(path)) == package.source_root,
        discovered_packages)
    package.child_package_ids = odin_package_id.(sort(children))
    return package
end

"""Capture `odin doc` output from the repository root, retrying pre-output crashes."""
function run_odin_doc(repository_root::String, relative_path::String)
    command = Cmd(Cmd([
        "odin", "doc", relative_path, "-in-source-order"]); dir=repository_root)
    for attempt in 1:3
        stdout = IOBuffer()
        stderr = IOBuffer()
        process = run(pipeline(ignorestatus(command); stdout=stdout, stderr=stderr);
            wait=true)
        output = String(take!(stdout))
        errors = strip(String(take!(stderr)))
        success(process) && return output
        crashed_before_output = process.termsignal == 11 && isempty(output)
        crashed_before_output && attempt < 3 && continue
        error("odin doc failed for $relative_path with exit code $(process.exitcode), " *
            "signal $(process.termsignal): $errors")
    end
    error("odin doc retry loop ended unexpectedly for $relative_path")
end

"""Run `odin doc` for one explicit project package and return normalized records."""
function extract_odin_package(config::OdinWikiConfig, package_path::AbstractString)
    relative_path = normalize_repo_path(package_path)
    discovered_packages = discover_odin_packages(config)
    relative_path in discovered_packages ||
        error("Path is not a discovered Odin package: $relative_path")
    package = parse_odin_doc(
        run_odin_doc(config.repository_root, relative_path), relative_path)
    enrich_odin_source_metadata!(package, config.repository_root)
    return enrich_odin_child_packages!(package, discovered_packages)
end

"""Return a human-readable plural heading for one declaration kind."""
function declaration_kind_heading(kind::Symbol)
    headings = Dict(
        :constant => "Constants", :enum => "Enums", :exported_abi_procedure => "C ABI Procedures",
        :procedure => "Procedures", :procedure_group => "Procedure Groups",
        :struct => "Structs", :union => "Unions")
    return get(headings, kind, titlecase(replace(String(kind), '_' => ' ')))
end

"""Shift Markdown headings beneath a generated symbol heading."""
function shift_markdown_headings(markdown::String)
    return join(map(split(markdown, '\n'; keepempty=true)) do line
        matched = match(r"^(#{1,5})(\s+.*)$", line)
        matched === nothing ? line : "#" * matched.captures[1] * matched.captures[2]
    end, "\n")
end

"""Render one deterministic GitHub-flavored Markdown Odin package page."""
function render_odin_package_page(package::DocumentationPackage;
    source_link_prefix::String="../../../../")

    symbols = sort(filter(symbol -> !isempty(symbol.doc_markdown), package.symbols);
        by=symbol -> (String(symbol.declaration_kind), symbol.qualified_name))
    io = IOBuffer()
    write(io, "<!-- Generated from source doc comments. Do not edit this file directly. -->\n\n")
    write(io, "# Odin Package `", package.display_name, "`\n\n")
    write(io, "Source: [`", package.source_root, "`](", source_link_prefix,
        package.source_root, ")\n\n")
    if !isempty(package.doc_markdown)
        write(io, shift_markdown_headings(package.doc_markdown), "\n\n")
    end
    render_package_guide_links!(io, package.authored_document_refs)
    write(io, "## Source Files\n\n")
    for source_file in sort(package.source_files)
        source_path = normalize_repo_path(joinpath(package.source_root, source_file))
        write(io, "- [`", source_path, "`](", source_link_prefix, source_path, ")\n")
    end
    render_odin_symbol_groups!(io, symbols, source_link_prefix)
    return String(take!(io))
end

"""Render documented symbols grouped by declaration kind."""
function render_odin_symbol_groups!(
    io::IO, symbols::Vector{DocumentationSymbol}, source_link_prefix::String)

    kinds = sort!(unique(symbol.declaration_kind for symbol in symbols); by=String)
    for kind in kinds
        write(io, "\n## ", declaration_kind_heading(kind), "\n")
        for symbol in filter(item -> item.declaration_kind == kind, symbols)
            write(io, "\n<a id=\"", wiki_symbol_anchor(symbol), "\"></a>\n")
            write(io, "\n### `", symbol.name, "`\n\n```odin\n", symbol.signature, "\n```\n\n")
            if symbol.source_line > 0
                write(io, "[Source](", source_link_prefix, symbol.source_path,
                    "#L", string(symbol.source_line), ")\n\n")
            end
                    render_authored_document_links!(io, symbol.authored_document_refs)
            write(io, shift_markdown_headings(symbol.doc_markdown), "\n")
        end
    end
end

"""Write one rendered Odin package page, creating its parent directory."""
function write_odin_package_page(
    package::DocumentationPackage, output_path::AbstractString;
    source_link_prefix::String="../../../../")

    mkpath(dirname(output_path))
    write(output_path, render_odin_package_page(
        package; source_link_prefix=source_link_prefix))
    return String(output_path)
end

include("code_wiki_julia.jl")
include("code_wiki_bridge.jl")
include("code_wiki_navigation.jl")

const PROTOTYPE_JULIA_MODULE_FILES = [
    "src/julia/animations.jl",
    "src/julia/euclidrepl.jl",
    "src/julia/geometry.jl",
    "src/julia/latex.jl",
    "src/julia/odin-julia-bridge.jl",
]

"""Generate one explicitly requested Odin package page."""
function generate_requested_odin_page(repository_root::String, arguments::Vector{String})
    package_path = arguments[1]
    output_path = length(arguments) < 2 ?
        joinpath(repository_root, "docs", "wiki", "Code", "Odin", "core.md") :
        abspath(arguments[2])
    config = OdinWikiConfig(
        repository_root=repository_root, excluded_roots=["src/julialib"])
    package = extract_odin_package(config, package_path)
    write_odin_package_page(package, output_path)
    println("Wrote ", relpath(output_path, repository_root))
    return 0
end

"""Extract the configured code-reference packages without executing Julia modules."""
function extract_default_wiki_packages(repository_root::String)
    odin_config = OdinWikiConfig(
        repository_root=repository_root, excluded_roots=["src/julialib"])
    odin_paths = discover_odin_packages(odin_config)
    packages = map(path -> extract_odin_package(odin_config, path), odin_paths)
    julia_config = JuliaWikiConfig(repository_root=repository_root)
    append!(packages, map(PROTOTYPE_JULIA_MODULE_FILES) do entry_file
        extract_julia_module(julia_config, entry_file)
    end)
    return packages
end

"""Return one manifest with an alternate generated artifact root."""
function wiki_manifest_with_root(manifest::WikiManifest, wiki_root::String)
    return WikiManifest(
        wiki_root=wiki_root,
        shared_output_paths=manifest.shared_output_paths,
        sections=manifest.sections,
        guides=manifest.guides,
        guide_relations=manifest.guide_relations,
        bridge_exceptions=manifest.bridge_exceptions,
        shared_output_owner=manifest.shared_output_owner)
end

"""Extract and render every producer-owned Wiki output without writing files."""
function build_complete_wiki_outputs(
    repository_root::String, manifest::WikiManifest, source_link_prefix::String)

    packages = extract_default_wiki_packages(repository_root)
    apply_guide_relations!(packages, manifest)
    bridge_pairs = extract_bridge_pairs(
        packages, repository_root; exceptions=manifest.bridge_exceptions)
    outputs = build_code_wiki_outputs(
        packages, bridge_pairs; source_link_prefix=source_link_prefix)
    append!(outputs, build_wiki_compositor_outputs(manifest))
    append!(outputs, build_authored_guide_outputs(repository_root, manifest))
    return outputs
end

"""Write, validate, and replace one complete publishable Wiki artifact."""
function replace_wiki_artifact(
    repository_root::String, output_root::String, manifest::WikiManifest,
    outputs::Vector{WikiOutput})

    staging_root = output_root * ".staging"
    ispath(staging_root) && rm(staging_root; recursive=true, force=true)
    mkpath(staging_root)
    artifact_manifest = wiki_manifest_with_root(
        manifest, normalize_repo_path(relpath(staging_root, repository_root)))
    try
        expected_paths = write_wiki_outputs(repository_root, artifact_manifest, outputs)
        validate_managed_outputs(artifact_manifest, expected_paths, repository_root)
        validate_wiki_links(artifact_manifest, repository_root)
        ispath(output_root) && rm(output_root; recursive=true, force=true)
        mv(staging_root, output_root)
        return expected_paths
    catch e
        ispath(staging_root) && rm(staging_root; recursive=true, force=true)
        rethrow(e)
    end
end

"""Generate and validate one complete publishable Wiki artifact."""
function generate_wiki_artifact(
    repository_root::String, output_root::String, source_link_prefix::String)

    manifest = load_wiki_manifest(joinpath(@__DIR__, "code_wiki.toml"))
    outputs = build_complete_wiki_outputs(repository_root, manifest, source_link_prefix)
    return replace_wiki_artifact(repository_root, output_root, manifest, outputs)
end

"""Generate a Wiki artifact or one explicitly requested Odin package page."""
function main(arguments::Vector{String}=ARGS)
    repository_root = abspath(joinpath(@__DIR__, ".."))
    if isempty(arguments)
        output_root = get(ENV, "EUCLID_WIKI_OUTPUT_ROOT",
            joinpath(repository_root, "bin", "wiki"))
        source_prefix = get(ENV, "EUCLID_WIKI_SOURCE_PREFIX",
            "https://github.com/derekshoneycutt/Euclid/blob/main/")
        expected_paths =
            generate_wiki_artifact(repository_root, output_root, source_prefix)
        foreach(path -> println("Wrote ", path), expected_paths)
        return 0
    end
    return generate_requested_odin_page(repository_root, arguments)
end

if abspath(PROGRAM_FILE) == @__FILE__
    exit(main())
end

end