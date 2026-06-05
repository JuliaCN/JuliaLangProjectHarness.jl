const JULIA_SEARCH_PACKET_SCHEMA_ID = "agent.semantic-protocols.semantic-search-packet"
const JULIA_SEARCH_PACKET_SCHEMA_VERSION = "1"

function julia_search_packet_base(
    view::AbstractString,
    render_mode::AbstractString,
    project_root::AbstractString;
    query::Union{Nothing,AbstractString}=nothing,
)
    root = abspath(String(project_root))
    scope = julia_project_harness_scope(root, default_julia_harness_config())
    header_fields = Dict{String,Any}(
        "view" => String(view),
        "provider" => JULIA_INDEX_EXPORT_PROVIDER_ID,
    )
    isnothing(query) || (header_fields["query"] = String(query))
    packet = Dict{String,Any}(
        "schemaId" => JULIA_SEARCH_PACKET_SCHEMA_ID,
        "schemaVersion" => JULIA_SEARCH_PACKET_SCHEMA_VERSION,
        "protocolId" => JULIA_INDEX_EXPORT_PROTOCOL_ID,
        "protocolVersion" => JULIA_INDEX_EXPORT_PROTOCOL_VERSION,
        "languageId" => JULIA_INDEX_EXPORT_LANGUAGE_ID,
        "providerId" => JULIA_INDEX_EXPORT_PROVIDER_ID,
        "binary" => JULIA_AGENT_BINARY,
        "namespace" => JULIA_AGENT_PROVIDER_NAMESPACE,
        "method" => "search/$(String(view))",
        "projectRoot" => root,
        "packageName" => something(scope.package_name, basename(root)),
        "view" => String(view),
        "renderMode" => String(render_mode),
        "header" => Dict("kind" => "search-$(String(view))", "fields" => header_fields),
        "nodes" => Dict{String,Any}[],
        "edges" => Dict{String,Any}[],
        "owners" => Dict{String,Any}[],
        "hits" => Dict{String,Any}[],
        "findings" => Dict{String,Any}[],
        "nextActions" => Dict{String,Any}[],
        "notes" => Dict{String,Any}[],
    )
    isnothing(query) || (packet["query"] = String(query))
    packet
end

function julia_search_owner_row(path::AbstractString)
    owner = normalized_owner_path(path)
    Dict{String,Any}(
        "path" => owner,
        "role" => is_julia_test_path(owner) ? "test" : "owner",
        "public" => !is_julia_test_path(owner),
        "nextActions" => [julia_search_next_action("query", owner; owner_path=owner, target_role="path")],
        "fields" => Dict{String,Any}("languageKind" => "julia-owner"),
    )
end

function julia_search_next_action(
    kind::AbstractString,
    target::AbstractString;
    owner_path::Union{Nothing,AbstractString}=nothing,
    target_role::AbstractString="path",
    scope::AbstractString="search",
)
    action = Dict{String,Any}(
        "kind" => String(kind),
        "target" => String(target),
        "targetRole" => String(target_role),
        "scope" => String(scope),
    )
    isnothing(owner_path) || (action["ownerPath"] = normalized_owner_path(owner_path))
    action
end

function julia_search_location(entry::JuliaSearchIndexEntry, project_root::AbstractString)
    aslp_location_row(entry.location, project_root)
end

function julia_search_hit_row(
    entry::JuliaSearchIndexEntry,
    project_root::AbstractString;
    score::Real=1.0,
    reason::AbstractString="julia-search-index",
)
    owner = search_entry_owner_path(entry, project_root)
    Dict{String,Any}(
        "kind" => String(entry.kind),
        "ownerPath" => owner,
        "symbol" => String(entry.name),
        "location" => julia_search_location(entry, project_root),
        "score" => Float64(score),
        "reason" => String(reason),
        "snippet" => compact_cli_value(String(entry.detail)),
        "surface" => is_julia_test_entry(entry) ? "test-source" : "real-source",
        "realOwner" => !is_julia_test_entry(entry),
        "fields" => Dict{String,Any}(
            "portableKind" => aslp_fact_kind(entry),
            "juliaKind" => String(entry.kind),
        ),
    )
end

function julia_search_policy_hit(rule::JuliaHarnessRule)
    owner = julia_policy_rule_owner(rule)
    Dict{String,Any}(
        "kind" => "policy-rule",
        "ownerPath" => owner,
        "symbol" => rule.rule_id,
        "location" => Dict("path" => owner, "lineRange" => "1:1"),
        "score" => 1.0,
        "reason" => "policy-handle-catalog",
        "snippet" => compact_cli_value(rule.requirement),
        "surface" => "real-source",
        "realOwner" => true,
        "fields" => Dict{String,Any}(
            "packId" => rule.pack_id,
            "severity" => severity_label(rule.severity),
        ),
    )
end

function julia_search_policy_handle(rule::JuliaHarnessRule, query::AbstractString)
    owner = julia_policy_rule_owner(rule)
    tests = julia_policy_rule_tests(rule)
    Dict{String,Any}(
        "id" => rule.rule_id,
        "kind" => "policy-rule",
        "source" => "provider-policy",
        "title" => rule.title,
        "languageName" => "Julia",
        "qualifiedName" => "$(rule.pack_id):$(rule.rule_id)",
        "aliases" => [rule.rule_id],
        "labels" => sort!(collect(values(rule.labels))),
        "status" => "active",
        "ownerPath" => owner,
        "implementationOwnerPath" => owner,
        "testPaths" => tests,
        "locations" => [Dict("path" => owner, "lineRange" => "1:1")],
        "queryTerms" => [String(query), rule.rule_id],
        "fields" => Dict{String,Any}(
            "packId" => rule.pack_id,
            "severity" => severity_label(rule.severity),
            "requirement" => rule.requirement,
        ),
    )
end

function julia_search_window_targets(owners::Vector{String}, tests::Vector{String})
    targets = Dict{String,Any}[]
    for owner in search_window_owner_paths(owners)[1:min(length(search_window_owner_paths(owners)), 8)]
        push!(targets, Dict{String,Any}("kind" => "owner", "target" => owner))
    end
    remaining = 8 - length(targets)
    for test_path in tests[1:min(length(tests), max(remaining, 0))]
        push!(targets, Dict{String,Any}("kind" => "tests", "target" => test_path))
    end
    targets
end

function julia_search_attach_frontier!(
    packet::Dict{String,Any},
    owners::Vector{String},
    tests::Vector{String};
    algorithm::AbstractString,
    scope::AbstractString,
    summary::AbstractString,
)
    owner_rows = [julia_search_owner_row(owner) for owner in owners if !is_julia_test_path(owner)]
    packet["owners"] = owner_rows
    next_actions = Dict{String,Any}[]
    for owner in owners
        push!(next_actions, julia_search_next_action("owner", owner; owner_path=owner, target_role="path", scope))
    end
    for test_path in tests
        push!(next_actions, julia_search_next_action("tests", test_path; target_role="test", scope))
    end
    packet["nextActions"] = next_actions
    packet["searchSynthesis"] = Dict{String,Any}(
        "algorithm" => String(algorithm),
        "scope" => String(scope),
        "summary" => String(summary),
        "selectedOwners" => length(owners),
        "editFrontier" => search_window_owner_paths(owners),
        "testFrontier" => tests,
        "windowSet" => julia_search_window_targets(owners, tests),
        "seeds" => next_actions,
    )
    packet
end

function julia_search_native_facts(entries::Vector{JuliaSearchIndexEntry}, project_root::AbstractString; limit::Int=64)
    [aslp_search_index_fact(entry, project_root) for entry in entries[1:min(length(entries), limit)]]
end

function julia_prime_search_packet(project_root::AbstractString; render_mode::AbstractString="seeds")
    entries = julia_project_search_index(project_root)
    owners = search_entries_to_owner_paths(entries)
    tests = search_entries_to_test_paths(entries, project_root)
    packet = julia_search_packet_base("prime", render_mode, project_root)
    packet["nativeSyntaxFacts"] = julia_search_native_facts(entries, project_root)
    packet["nodes"] = [
        Dict{String,Any}(
            "id" => "owner:$(owner)",
            "kind" => "owner",
            "path" => owner,
            "fields" => Dict{String,Any}("source" => "julia-search-index"),
        ) for owner in owners[1:min(length(owners), 24)]
    ]
    julia_search_attach_frontier!(
        packet,
        owners,
        tests;
        algorithm="julia-search-index",
        scope="prime",
        summary="Julia package owner and test frontier",
    )
end

function julia_owner_search_packet(owner_path::AbstractString, project_root::AbstractString; render_mode::AbstractString="seeds")
    entries = julia_project_search_index(project_root)
    owner = normalized_owner_path(owner_path)
    owner_entries = [
        entry for entry in entries
        if normalized_owner_path(search_entry_owner_path(entry, project_root)) == owner
    ]
    tests = related_julia_test_paths(entries, owner, project_root)
    packet = julia_search_packet_base("owner", render_mode, project_root; query=owner_path)
    packet["ownerResolution"] = [
        Dict{String,Any}(
            "target" => owner,
            "status" => isempty(owner_entries) ? "missing" : "workspace-owner",
            "realOwner" => !isempty(owner_entries),
            "ownerPath" => owner,
            "reason" => "Julia search index owner lookup",
        ),
    ]
    packet["hits"] = [julia_search_hit_row(entry, project_root; reason="owner-entry") for entry in owner_entries[1:min(length(owner_entries), 32)]]
    packet["nativeSyntaxFacts"] = julia_search_native_facts(owner_entries, project_root)
    isempty(owner_entries) && push!(packet["notes"], Dict("kind" => "owner-not-found", "message" => "No Julia owner matched $(owner)."))
    julia_search_attach_frontier!(
        packet,
        isempty(owner_entries) ? String[] : [owner],
        tests;
        algorithm="julia-owner-index",
        scope="owner",
        summary=isempty(owner_entries) ? "No Julia owner matched" : "Resolved Julia owner",
    )
end

function julia_fzf_search_packet(query::AbstractString, project_root::AbstractString; render_mode::AbstractString="seeds")
    results = search_julia_project(project_root, query; limit=16)
    entries = [result.entry for result in results]
    owners = search_results_to_owner_paths(results, project_root)
    tests = search_results_to_test_paths(results, project_root)
    packet = julia_search_packet_base("fzf", render_mode, project_root; query)
    packet["queryCoverage"] = [
        Dict{String,Any}(
            "value" => String(query),
            "kind" => "text",
            "selector" => "fuzzy",
            "status" => isempty(results) ? "miss" : "hit",
            "hitCount" => length(results),
            "ownerPaths" => owners,
            "surfaces" => unique([is_julia_test_entry(entry) ? "test-source" : "real-source" for entry in entries]),
        ),
    ]
    packet["hits"] = [julia_search_hit_row(result.entry, project_root; score=result.score, reason="fzf") for result in results]
    packet["nativeSyntaxFacts"] = julia_search_native_facts(entries, project_root)
    isempty(results) && push!(packet["notes"], Dict("kind" => "not-found", "message" => String(query)))
    julia_search_attach_frontier!(
        packet,
        owners,
        tests;
        algorithm="julia-search-index",
        scope="fzf",
        summary=isempty(results) ? "No Julia fuzzy results matched" : "Resolved Julia fuzzy candidates",
    )
end

function julia_ingest_search_packet(stdin_text::AbstractString, project_root::AbstractString; render_mode::AbstractString="seeds")
    candidate_paths = ingest_candidate_paths(stdin_text, project_root)
    tests = filter(is_julia_test_path, candidate_paths)
    owners = filter(path -> !(path in tests), candidate_paths)
    packet = julia_search_packet_base("ingest", render_mode, project_root)
    input_lines = [line for line in split(String(stdin_text), '\n') if !isempty(line)]
    packet["inputDetection"] = Dict{String,Any}(
        "source" => "path-list",
        "lineCount" => length(input_lines),
        "byteCount" => sizeof(String(stdin_text)),
        "sample" => compact_cli_value(isempty(input_lines) ? "" : first(input_lines)),
    )
    julia_search_attach_frontier!(
        packet,
        owners,
        tests;
        algorithm="stdin-candidate-paths",
        scope="ingest",
        summary="Resolved stdin candidate paths",
    )
end

function julia_policy_search_packet(query::AbstractString, project_root::AbstractString; render_mode::AbstractString="seeds")
    matches = julia_policy_rule_matches(query)
    owners = unique([julia_policy_rule_owner(rule) for rule in matches])
    tests = isempty(matches) ? String[] : unique(vcat([julia_policy_rule_tests(rule) for rule in matches]...))
    packet = julia_search_packet_base("policy", render_mode, project_root; query)
    packet["queryCoverage"] = [
        Dict{String,Any}(
            "value" => String(query),
            "kind" => "custom",
            "selector" => "exact",
            "status" => isempty(matches) ? "miss" : "hit",
            "hitCount" => length(matches),
            "ownerPaths" => owners,
            "surfaces" => ["real-source"],
        ),
    ]
    packet["hits"] = [julia_search_policy_hit(rule) for rule in matches]
    packet["semanticHandles"] = [julia_search_policy_handle(rule, query) for rule in matches]
    isempty(matches) && push!(packet["notes"], Dict("kind" => "policy-not-found", "message" => String(query)))
    julia_search_attach_frontier!(
        packet,
        owners,
        tests;
        algorithm="policy-handle-catalog",
        scope="policy",
        summary=isempty(matches) ? "No provider-owned policy handles matched" : "Resolved provider-owned policy handles",
    )
end

include("aslp_search/query.jl")

function render_julia_search_packet_json(
    view::AbstractString;
    project_root::AbstractString,
    render_mode::AbstractString="seeds",
    query::Union{Nothing,AbstractString}=nothing,
    owner_path::Union{Nothing,AbstractString}=nothing,
    stdin_text::AbstractString="",
    selector::Union{Nothing,AbstractString}=nothing,
    terms::Vector{String}=String[],
    pipes::Vector{String}=String[],
    from_hook::Union{Nothing,AbstractString}=nothing,
    intent::Union{Nothing,AbstractString}=nothing,
)
    packet = if view == "prime"
        julia_prime_search_packet(project_root; render_mode)
    elseif view == "owner"
        isnothing(owner_path) && error("search owner JSON requires an owner path")
        julia_owner_search_packet(owner_path, project_root; render_mode)
    elseif view == "fzf"
        isnothing(query) && error("search fzf JSON requires a query")
        julia_fzf_search_packet(query, project_root; render_mode)
    elseif view == "ingest"
        julia_ingest_search_packet(stdin_text, project_root; render_mode)
    elseif view == "policy"
        isnothing(query) && error("search policy JSON requires a query")
        julia_policy_search_packet(query, project_root; render_mode)
    elseif view == "query"
        isnothing(selector) && error("search query JSON requires a selector")
        isempty(terms) && error("search query JSON requires terms")
        julia_search_query_packet(
            selector,
            terms,
            pipes,
            project_root;
            render_mode,
            from_hook=something(from_hook, "direct-source-read"),
            intent,
        )
    else
        error("unknown search JSON view: $(view)")
    end
    JSON3.write(packet)
end
