const DOCUMENTER_EXECUTABLE_EXAMPLE_LANGUAGES = Set(["@example", "@repl", "jldoctest"])
const MAX_DOCUMENTER_EXAMPLE_MISSING_NAMES = 8

function public_documenter_example_findings(
    scope::JuliaProjectHarnessScope,
    public_names::Set{String},
    rules::Dict{String,JuliaHarnessRule},
)
    isempty(public_names) && return JuliaHarnessFinding[]
    docs = documenter_docs_surface(scope)
    isnothing(docs) && return JuliaHarnessFinding[]
    covered_names = documenter_executable_example_public_names(docs.root, public_names)
    missing_names = sort!(collect(setdiff(public_names, covered_names)))
    isempty(missing_names) && return JuliaHarnessFinding[]
    [
        finding_from_rule_typed(
            rules[AGENT_JL_R019],
            documenter_example_summary(scope, missing_names),
            SourceLocation(docs.make_path, 1, 0),
            documenter_make_source_line(docs.make_path),
            "add executable Documenter examples for the missing public API names",
        ),
    ]
end

function documenter_docs_surface(scope::JuliaProjectHarnessScope)
    docs_root = joinpath(scope.project_root, "docs")
    docs_project = joinpath(docs_root, "Project.toml")
    docs_make = joinpath(docs_root, "make.jl")
    isfile(docs_project) || return nothing
    isfile(docs_make) || return nothing
    facts = parse_project_toml_facts(docs_project)
    haskey(facts.direct_dependencies, "Documenter") ||
        haskey(facts.extra_dependencies, "Documenter") ||
        return nothing
    (root=docs_root, project_path=docs_project, make_path=docs_make)
end

function documenter_executable_example_public_names(
    docs_root::AbstractString,
    public_names::Set{String},
)
    covered = Set{String}()
    for markdown_path in documenter_markdown_paths(docs_root)
        source = read(markdown_path, String)
        union!(covered, public_names_in_executable_doc_examples(source, public_names))
    end
    covered
end

function documenter_markdown_paths(docs_root::AbstractString)
    paths = String[]
    isdir(docs_root) || return paths
    for (root, dirs, files) in walkdir(docs_root)
        filter!(dir -> dir != "build", dirs)
        for file in files
            endswith(file, ".md") && push!(paths, joinpath(root, file))
        end
    end
    sort!(paths)
end

function public_names_in_executable_doc_examples(
    source::AbstractString,
    public_names::Set{String},
)
    covered = Set{String}()
    for example in documenter_executable_code_blocks(source)
        union!(
            covered,
            executable_doc_code_public_names(example.code, example.language, public_names),
        )
    end
    covered
end

function documenter_executable_code_blocks(source::AbstractString)
    blocks = NamedTuple{(:language,:code),Tuple{String,String}}[]
    active_language = nothing
    buffer = IOBuffer()
    for raw_line in split(String(source), '\n')
        fence = markdown_code_fence_language(raw_line)
        if !isnothing(fence)
            if isnothing(active_language)
                active_language = fence in DOCUMENTER_EXECUTABLE_EXAMPLE_LANGUAGES ?
                                  fence : ""
                buffer = IOBuffer()
            else
                if !isempty(active_language)
                    push!(
                        blocks,
                        (language=active_language, code=String(take!(buffer))),
                    )
                end
                active_language = nothing
                buffer = IOBuffer()
            end
        elseif !isnothing(active_language) && !isempty(active_language)
            println(buffer, raw_line)
        end
    end
    blocks
end

function markdown_code_fence_language(line::AbstractString)
    text = strip(String(line))
    startswith(text, "```") || return nothing
    language = length(text) == 3 ? "" : strip(text[4:end])
    isempty(language) && return ""
    head = first(split(language; limit=2))
    first(split(head, ';'; limit=2))
end

function executable_doc_code_public_names(
    code::AbstractString,
    language::AbstractString,
    public_names::Set{String},
)
    identifiers = if language == "jldoctest"
        doctest_prompt_identifiers(code)
    else
        syntax_identifiers_from_source(code)
    end
    intersect(public_names, identifiers)
end

function doctest_prompt_identifiers(code::AbstractString)
    identifiers = Set{String}()
    for line in split(String(code), '\n')
        source = doctest_prompt_source_line(line)
        isnothing(source) && continue
        union!(identifiers, syntax_identifiers_from_source(source))
    end
    identifiers
end

function doctest_prompt_source_line(line::AbstractString)
    source = String(line)
    startswith(source, "julia> ") && return source[length("julia> ")+1:end]
    startswith(source, "       ") && return source[length("       ")+1:end]
    nothing
end

function syntax_identifiers_from_source(source::AbstractString)
    annotation_identifier_names(source)
end

function documenter_example_summary(
    scope::JuliaProjectHarnessScope,
    missing_names::Vector{String},
)
    capped = first(missing_names, min(length(missing_names), MAX_DOCUMENTER_EXAMPLE_MISSING_NAMES))
    suffix = length(missing_names) > length(capped) ?
             ", ... $(length(missing_names) - length(capped)) more" : ""
    package_name = something(scope.package_name, "<unnamed>")
    "Documenter docs for `$(package_name)` lack executable public API examples for: $(join(capped, ", "))$(suffix)."
end

function documenter_make_source_line(path::AbstractString)
    isfile(path) || return nothing
    source_line(read(path, String), 1)
end
