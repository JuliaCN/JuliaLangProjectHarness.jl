"""Shared-search-packet support for hook-rerouted Julia queries."""

function julia_search_query_selector_owner(
    selector::AbstractString,
    project_root::AbstractString,
)
    path = replace(strip(String(selector)), r"^owner:" => "")
    path = replace(path, r":[0-9]+([:-][0-9]+)?$" => "")
    isempty(path) && return nothing
    occursin(r"[*?\[\]{}]", path) && return nothing
    path = isabspath(path) ? asp_project_path(path, project_root) : normalized_owner_path(path)
    endswith(path, ".jl") || return nothing
    path
end

function julia_search_query_surface_label(entry::JuliaSearchIndexEntry)
    is_julia_test_entry(entry) ? "test-source" : "real-source"
end

function julia_search_query_filter_entries(
    entries::Vector{JuliaSearchIndexEntry},
    pipes::Vector{String},
)
    include_owner = "owner" in pipes || "items" in pipes
    include_tests = "tests" in pipes
    [
        entry for entry in entries
        if is_julia_test_entry(entry) ? include_tests : include_owner
    ]
end

function julia_search_query_entry_matches(
    entry::JuliaSearchIndexEntry,
    term::AbstractString,
    project_root::AbstractString,
)
    normalized_term = normalize_search_text(term)
    isempty(normalized_term) && return false
    owner_path = search_entry_owner_path(entry, project_root)
    qualified_name = asp_qualified_name(entry, owner_path)
    keys = String[
        String(entry.name),
        String(entry.kind),
        asp_fact_kind(entry),
        owner_path,
        qualified_name,
        String(entry.detail),
        String(entry.search_text),
    ]
    append!(keys, String.(entry.tags))
    any(key -> occursin(normalized_term, normalize_search_text(key)), keys)
end

function julia_search_query_coverage_rows(
    entries::Vector{JuliaSearchIndexEntry},
    terms::Vector{String},
    project_root::AbstractString,
)
    rows = Dict{String,Any}[]
    for term in terms
        matches = [
            entry for entry in entries
            if julia_search_query_entry_matches(entry, term, project_root)
        ]
        owner_paths = sort!(unique([
            search_entry_owner_path(entry, project_root)
            for entry in matches
            if !is_julia_test_entry(entry) && !isnothing(entry.location.path)
        ]))
        surfaces = sort!(unique([julia_search_query_surface_label(entry) for entry in matches]))
        push!(
            rows,
            Dict{String,Any}(
                "value" => term,
                "kind" => "text",
                "selector" => "fuzzy",
                "status" => isempty(matches) ? "miss" : "hit",
                "hitCount" => length(matches),
                "ownerPaths" => owner_paths,
                "surfaces" => surfaces,
            ),
        )
    end
    rows
end

function julia_search_query_set_rows(
    terms::Vector{String};
    selector::AbstractString,
    from_hook::AbstractString,
)
    [
        Dict{String,Any}(
            "value" => term,
            "kind" => "text",
            "selector" => "fuzzy",
            "fields" => Dict{String,Any}(
                "sourceSelector" => String(selector),
                "fromHook" => String(from_hook),
            ),
        ) for term in terms
    ]
end

function julia_search_query_source_coverage(
    selector::AbstractString,
    from_hook::AbstractString,
    pipes::Vector{String},
    entries::Vector{JuliaSearchIndexEntry},
    owners::Vector{String},
    project_root::AbstractString,
    selector_owner::Union{Nothing,String},
)
    all_owner_paths = sort!(unique([
        search_entry_owner_path(entry, project_root)
        for entry in entries
        if !isnothing(entry.location.path)
    ]))
    scope = Dict{String,Any}("projectRoot" => abspath(String(project_root)))
    if isnothing(selector_owner)
        scope["roots"] = ["."]
    else
        scope["ownerPath"] = selector_owner
    end
    Dict{String,Any}(
        "scope" => scope,
        "status" => isnothing(selector_owner) ? "partial" : (isempty(entries) ? "missing" : "complete"),
        "coverageKind" => "parser-source",
        "coveredOwners" => owners,
        "sourceFiles" => length(all_owner_paths),
        "visibleOwners" => length(owners),
        "reason" => "hook direct-source-read selector resolved through JuliaSyntax search index",
        "fields" => Dict{String,Any}(
            "selector" => String(selector),
            "fromHook" => String(from_hook),
            "surfaces" => pipes,
        ),
    )
end

function julia_search_query_packet(
    selector::AbstractString,
    terms::Vector{String},
    pipes::Vector{String},
    project_root::AbstractString;
    render_mode::AbstractString="seeds",
    from_hook::AbstractString="direct-source-read",
    intent::Union{Nothing,AbstractString}=nothing,
)
    query = julia_search_query_text(terms)
    selector_owner = julia_search_query_selector_owner(selector, project_root)
    entries = isnothing(selector_owner) ?
              julia_project_search_index(project_root) :
              julia_exact_owner_search_entries(selector_owner, project_root)
    scoped_entries = isnothing(selector_owner) ? entries : [
        entry for entry in entries
        if search_entry_owner_path(entry, project_root) == selector_owner
    ]
    candidate_entries = julia_search_query_filter_entries(scoped_entries, pipes)
    results = search_julia_index(candidate_entries, query; limit=16)
    owners = search_results_to_owner_paths(results, project_root)
    tests = search_results_to_test_paths(results, project_root)
    result_entries = [result.entry for result in results]
    packet = julia_search_packet_base("query", render_mode, project_root; query)
    fields = packet["header"]["fields"]
    fields["selector"] = String(selector)
    fields["fromHook"] = String(from_hook)
    fields["terms"] = terms
    fields["surfaces"] = pipes
    isnothing(intent) || (fields["intent"] = String(intent))
    packet["querySet"] = julia_search_query_set_rows(terms; selector, from_hook)
    packet["queryComposition"] = Dict{String,Any}(
        "mode" => length(terms) == 1 ? "single" : "query-set",
        "view" => "query",
        "selector" => length(terms) == 1 ? "single" : "lexical-set",
        "scope" => Dict{String,Any}("projectRoot" => abspath(String(project_root))),
        "merge" => ["owners", "hits", "nativeSyntaxFacts", "nextActions", "notes"],
        "fields" => Dict{String,Any}(
            "selector" => String(selector),
            "fromHook" => String(from_hook),
            "surfaces" => pipes,
        ),
    )
    packet["queryCoverage"] = julia_search_query_coverage_rows(candidate_entries, terms, project_root)
    packet["sourceCoverage"] = [
        julia_search_query_source_coverage(
            selector,
            from_hook,
            pipes,
            candidate_entries,
            owners,
            project_root,
            selector_owner,
        ),
    ]
    packet["finder"] = Dict{String,Any}(
        "engine" => "provider",
        "surface" => "search-custom",
        "pipelineId" => "julia-hook-query",
        "options" => Dict{String,Any}("matchMode" => "fuzzy", "caseMode" => "ignore"),
        "acceptedArgs" => vcat(["--from-hook", String(from_hook), "--selector", String(selector)], ["--term=$(term)" for term in terms]),
        "rejectedArgs" => Dict{String,Any}[],
        "fields" => Dict{String,Any}("surfaces" => pipes),
    )
    packet["hits"] = [julia_search_hit_row(result.entry, project_root; score=result.score, reason="hook-query") for result in results]
    packet["nativeSyntaxFacts"] = julia_search_native_facts(result_entries, project_root)
    if !isnothing(selector_owner)
        packet["ownerResolution"] = [
            Dict{String,Any}(
                "target" => selector_owner,
                "status" => isempty(candidate_entries) ? "missing" : "workspace-owner",
                "realOwner" => !isempty(candidate_entries),
                "ownerPath" => selector_owner,
                "reason" => "Julia hook query selector narrowed to an owner path",
            ),
        ]
    end
    isempty(results) && push!(packet["notes"], Dict("kind" => "not-found", "message" => query))
    julia_search_attach_frontier!(
        packet,
        owners,
        tests;
        algorithm="julia-hook-query-index",
        scope="query",
        summary=isempty(results) ? "No Julia hook query candidates matched" : "Resolved Julia hook query candidates",
    )
end
