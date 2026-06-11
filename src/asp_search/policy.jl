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
