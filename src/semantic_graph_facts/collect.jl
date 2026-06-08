"""Collect located semantic graph field facts from candidate Julia owners."""

function julia_located_semantic_graph_field_facts(
    project_root::AbstractString,
    stdin_text::AbstractString,
)
    root = abspath(String(project_root))
    facts = Dict{String,Any}[]
    for path in julia_semantic_graph_candidate_files(root, stdin_text)
        parsed = parse_julia_file(path)
        parsed.report.is_valid || continue
        owner_path = asp_project_path(path, root)
        for type_fact in parsed.syntax_facts.types
            for field_fact in type_fact.field_facts
                push!(
                    facts,
                    julia_semantic_graph_field_fact(owner_path, type_fact, field_fact),
                )
            end
        end
    end
    facts
end

function julia_semantic_graph_candidate_files(root::AbstractString, stdin_text::AbstractString)
    candidates = String[]
    for candidate in julia_semantic_graph_candidate_paths(stdin_text)
        absolute = isabspath(candidate) ? candidate : joinpath(root, candidate)
        isfile(absolute) && endswith(lowercase(absolute), ".jl") && push!(candidates, abspath(absolute))
    end
    if isempty(candidates)
        config = default_julia_harness_config()
        scope = julia_project_harness_scope(root, config)
        workspace_member_scopes = julia_workspace_member_scopes(scope, config)
        monitored_paths = vcat(
            scope_search_paths(scope),
            mapreduce(scope_search_paths, vcat, workspace_member_scopes; init=String[]),
        )
        append!(candidates, discover_julia_files(monitored_paths, config))
    end
    sort!(unique(abspath.(candidates)))
end

function julia_semantic_graph_candidate_paths(stdin_text::AbstractString)
    paths = String[]
    for line in split(String(stdin_text), '\n')
        matched = match(r"^(.+?):\d+(?::\d+)?:", strip(line))
        isnothing(matched) || push!(paths, String(matched.captures[1]))
    end
    paths
end

function julia_semantic_graph_field_fact(
    owner_path::AbstractString,
    type_fact::JuliaTypeSyntax,
    field_fact::JuliaTypeFieldSyntax,
)
    type_value = something(field_fact.type_annotation, "Any")
    context_end_line = julia_semantic_graph_end_line(type_fact.line, type_fact.expression)
    collection_kind = julia_semantic_graph_collection_kind(type_value)
    fact = Dict{String,Any}(
        "path" => String(owner_path),
        "containerKind" => julia_semantic_graph_container_kind(type_fact),
        "containerName" => type_fact.name,
        "fieldName" => field_fact.name,
        "typeValue" => type_value,
        "line" => field_fact.line,
        "contextStartLine" => type_fact.line,
        "contextEndLine" => context_end_line,
        "mutable" => type_fact.is_mutable,
        "parameters" => type_fact.parameters,
    )
    isnothing(type_fact.supertype) || (fact["supertype"] = type_fact.supertype)
    isnothing(collection_kind) || (fact["collectionKind"] = collection_kind)
    fact
end
