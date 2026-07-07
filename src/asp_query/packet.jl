"""Build a shared semantic-query-packet for Julia owner-local item lookup.

Throws `ErrorException` when `query_terms` is empty after `|` splitting or when
`match_limit` is negative. Callers should validate CLI `--term` / `--query` and
`--limit` before exposing the packet on public agent routes.
"""
function julia_query_owner_items_packet(
    owner_path::AbstractString,
    query_terms::Vector{String};
    project_root::AbstractString=pwd(),
    names_only::Bool=false,
    code::Bool=false,
    match_limit::Int=25,
)
    root = abspath(String(project_root))
    owner = normalized_owner_path(owner_path)
    terms = julia_query_terms(query_terms)
    isempty(terms) && error("query/owner-items requires --term or --query")
    match_limit >= 0 || error("--limit must be non-negative")
    entries = julia_query_owner_entries(owner, root)
    coverage = julia_query_coverage(entries, terms, owner; project_root=root)
    matched_pairs = julia_query_matching_entries(entries, terms, owner)
    total_matches = length(matched_pairs)
    selected_pairs = matched_pairs[1:min(total_matches, match_limit)]
    include_code = code && !names_only
    matches = [
        julia_query_match_row(pair.first, root; include_code)
        for pair in selected_pairs
    ]
    candidates = total_matches == 0 ? julia_query_candidate_items(entries, terms, owner; project_root=root) : Dict{String,Any}[]
    scope = julia_project_harness_scope(root, default_julia_harness_config())
    packet = Dict{String,Any}(
        "schemaId" => JULIA_QUERY_PACKET_SCHEMA_ID,
        "schemaVersion" => JULIA_QUERY_PACKET_SCHEMA_VERSION,
        "protocolId" => JULIA_INDEX_EXPORT_PROTOCOL_ID,
        "protocolVersion" => JULIA_INDEX_EXPORT_PROTOCOL_VERSION,
        "languageId" => JULIA_INDEX_EXPORT_LANGUAGE_ID,
        "providerId" => JULIA_INDEX_EXPORT_PROVIDER_ID,
        "binary" => JULIA_AGENT_BINARY,
        "namespace" => JULIA_AGENT_PROVIDER_NAMESPACE,
        "method" => JULIA_QUERY_OWNER_ITEMS_METHOD,
        "projectRoot" => root,
        "packageName" => something(scope.package_name, basename(root)),
        "ownerPath" => owner,
        "query" => join(terms, "|"),
        "queryTerms" => terms,
        "matchMode" => julia_query_match_mode(coverage),
        "outputMode" => names_only ? "names" : (code ? "code" : "outline"),
        "queryCoverage" => coverage,
        "candidateItems" => candidates,
        "nativeSyntaxFacts" => [
            asp_search_index_fact(pair.first, root)
            for pair in selected_pairs
        ],
        "matches" => matches,
        "matchCount" => total_matches,
        "matchLimit" => match_limit,
        "matchesTruncated" => total_matches > length(selected_pairs),
        "truncated" => total_matches > length(selected_pairs),
        "patchSafety" => Dict{String,Any}(
            "level" => "read-safe",
            "reason" => "Julia compact query output requires exact source read before editing",
        ),
        "notes" => Dict{String,Any}[],
    )
    if !isempty(matches)
        packet["patchSafety"]["exactRead"] = first(matches)["read"]
    elseif isempty(entries)
        push!(
            packet["notes"],
            Dict(
                "kind" => "owner-not-found",
                "message" => "No Julia parser facts were found for owner $(owner).",
            ),
        )
    elseif isempty(candidates)
        push!(
            packet["notes"],
            Dict(
                "kind" => "query-not-found",
                "message" => "No Julia owner-local item matched $(join(terms, "|")).",
            ),
        )
    end
    packet
end

"""Render Julia owner-local item lookup as shared semantic-query-packet JSON."""
function render_julia_query_owner_items_json(
    owner_path::AbstractString,
    query_terms::Vector{String};
    project_root::AbstractString=pwd(),
    names_only::Bool=false,
    code::Bool=false,
    match_limit::Int=25,
)
    JSON3.write(
        julia_query_owner_items_packet(
            owner_path,
            query_terms;
            project_root,
            names_only,
            code,
            match_limit,
        ),
    )
end

"""Render Julia owner-local item lookup as compact line protocol."""
function render_julia_query_owner_items(
    owner_path::AbstractString,
    query_terms::Vector{String};
    project_root::AbstractString=pwd(),
    names_only::Bool=false,
    code::Bool=false,
    match_limit::Int=25,
)
    packet = julia_query_owner_items_packet(
        owner_path,
        query_terms;
        project_root,
        names_only,
        code,
        match_limit,
    )
    lines = String[
        "[query-item] owner=$(packet["ownerPath"]) terms=$(packet["query"]) match=$(packet["matchMode"]) hit=$(packet["matchCount"]) mode=$(packet["outputMode"]) truncated=$(packet["truncated"])",
    ]
    for coverage in packet["queryCoverage"]
        candidate_text = haskey(coverage, "candidateNames") ? join(coverage["candidateNames"], ",") : "-"
        push!(
            lines,
            "|query term=$(coverage["value"]) status=$(coverage["status"]) match=$(coverage["match"]) hit=$(coverage["matchCount"]) candidates=$(candidate_text)",
        )
    end
    for match in packet["matches"]
        push!(
            lines,
            "|item $(match["name"]) kind=$(match["kind"]) visibility=$(match["visibility"]) structuralSelector=$(match["structuralSelector"]) displayLineRange=$(match["displayLineRange"]) sourceLocatorHint=$(match["sourceLocatorHint"]) read=$(match["read"])",
        )
    end
    if code
        push!(
            lines,
            "|note kind=asp-owned-code message=\"query --code source extraction is owned by ASP exact owner query; compact provider output keeps locators only\"",
        )
    end
    for candidate in packet["candidateItems"]
        term = haskey(candidate, "term") ? candidate["term"] : "-"
        push!(lines, "|candidate $(candidate["name"]) reason=$(candidate["reason"]) term=$(term)")
    end
    for note in packet["notes"]
        push!(lines, "|note kind=$(note["kind"]) message=\"$(compact_cli_value(note["message"]))\"")
    end
    join(lines, "\n") * "\n"
end
