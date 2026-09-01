function julia_owner_match_tokens(owner::AbstractString)
    raw_tokens = split(lowercase(owner), r"[^a-z0-9_]+")
    Set([
        token for token in raw_tokens
        if length(token) >= 3 && !(token in JULIA_SEARCH_TEST_TOKEN_STOPWORDS)
    ])
end

function is_julia_test_entry(entry::JuliaSearchIndexEntry)
    "test" in entry.tags || entry.kind == "testset"
end

function ingest_candidate_paths(stdin_text::AbstractString, project_root::AbstractString)
    root = abspath(String(project_root))
    paths = String[]
    for line in split(String(stdin_text), '\n')
        parsed = parse_candidate_path(line)
        isnothing(parsed) && continue
        path = parsed
        isabspath(path) && (path = relpath(path, root))
        push!(paths, normalized_owner_path(path))
    end
    sort!(unique(paths))
end

function parse_candidate_path(line::AbstractString)
    stripped = strip(String(line))
    isempty(stripped) && return nothing
    first_field = first(split(stripped, ['\t', ' ']; limit=2))
    path_field = first(split(first_field, ':'; limit=2))
    isempty(path_field) && return nothing
    endswith(path_field, ".jl") || return nothing
    path_field
end

function normalized_owner_path(path::AbstractString)
    slash_path(normpath(String(path)))
end

function julia_policy_rule_matches(query::AbstractString)
    normalized_query = normalized_policy_query(query)
    isempty(normalized_query) && return AspJuliaRule[]
    [
        rule for rule in vcat(
            julia_syntax_rules(),
            julia_project_policy_rules(),
            julia_modularity_rules(),
            julia_agent_policy_rules(),
        ) if occursin(normalized_query, normalized_policy_rule_text(rule))
    ]
end

function normalized_policy_rule_text(rule::AspJuliaRule)
    normalized_policy_query(
        join(
            vcat(
                [rule.rule_id, rule.pack_id, rule.title, rule.requirement],
                collect(values(rule.labels)),
            ),
            " ",
        ),
    )
end

function normalized_policy_query(value::AbstractString)
    replace(lowercase(strip(String(value))), r"[^a-z0-9]+" => " ")
end

function julia_policy_rule_owner(rule::AspJuliaRule)
    rule.pack_id == JULIA_AGENT_POLICY_PACK_ID && return "src/rules/agent_catalog.jl"
    "src/rules/catalog.jl"
end

function julia_policy_rule_tests(rule::AspJuliaRule)
    if rule.pack_id == JULIA_AGENT_POLICY_PACK_ID
        ["test/unit/rule_catalog.jl", "test/unit/project/agent_verification.jl"]
    elseif rule.pack_id == JULIA_PROJECT_POLICY_PACK_ID
        ["test/unit/rule_catalog.jl", "test/unit/project/policy.jl"]
    elseif rule.pack_id == JULIA_MODULARITY_PACK_ID
        ["test/unit/rule_catalog.jl", "test/unit/project/ownership_algorithms.jl"]
    else
        ["test/unit/rule_catalog.jl", "test/unit/parser.jl"]
    end
end

function compact_cli_value(value::AbstractString)
    replace(strip(String(value)), r"\s+" => " ", "\"" => "'")
end

function search_seed_frontier(paths::Vector{String})
    isempty(paths) ? "-" : join(paths[1:min(length(paths), 12)], ",")
end

function search_window_set(owners::Vector{String}, tests::Vector{String})
    fragments = String[]
    edit_owners = search_window_owner_paths(owners)
    for owner in edit_owners[1:min(length(edit_owners), 8)]
        push!(fragments, "owner:$(owner)")
    end
    remaining = 8 - length(fragments)
    if remaining > 0
        for test_path in tests[1:min(length(tests), remaining)]
            push!(fragments, "tests:$(test_path)")
        end
    end
    isempty(fragments) ? "-" : join(fragments, ",")
end

function search_window_owner_paths(owners::Vector{String})
    [owner for owner in owners if !is_julia_test_path(owner)]
end

function is_julia_test_path(path::AbstractString)
    owner_path = normalized_owner_path(path)
    startswith(owner_path, "test/") || startswith(owner_path, "tests/") ||
        occursin("/test/", "/$(owner_path)") || occursin("/tests/", "/$(owner_path)")
end
