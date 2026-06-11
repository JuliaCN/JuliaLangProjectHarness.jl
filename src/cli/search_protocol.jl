"""Agent-facing Julia search command parsing and compact seed rendering."""

struct JuliaSearchCliOptions
    pipes::Vector{String}
    render_view::String
    project_root::String
    json::Bool
    workspace::Bool
end

const JULIA_SEARCH_TEST_TOKEN_STOPWORDS = Set([
    "ext",
    "jl",
    "julia",
    "lang",
    "project",
    "src",
    "test",
    "tests",
    "unit",
])

function parse_julia_search_args(args::Vector{String})
    pipes = String[]
    render_view = "graph"
    project_root = nothing
    json = false
    workspace = false
    index = 1
    while index <= length(args)
        arg = args[index]
        if arg in ("owner", "tests", "items")
            isnothing(project_root) || error("expected pipes before PROJECT_ROOT")
            push!(pipes, arg)
        elseif arg == "--json"
            json = true
        elseif arg == "--workspace"
            index += 1
            index <= length(args) || error("--workspace requires a project root")
            workspace = true
            isnothing(project_root) || error("expected at most one PROJECT_ROOT argument")
            project_root = args[index]
        elseif arg == "--view"
            index += 1
            index <= length(args) || error("--view requires a render mode")
            render_view = args[index]
        elseif startswith(arg, "--")
            error("unknown search option: $(arg)")
        else
            isnothing(project_root) || error("expected at most one PROJECT_ROOT argument")
            project_root = arg
        end
        index += 1
    end
    JuliaSearchCliOptions(pipes, render_view, something(project_root, pwd()), json, workspace)
end

function julia_harness_agent_guide(project_root::AbstractString)
    root = abspath(String(project_root))
    """
    [julia-harness-guide] project=$(root)
    |cmd asp julia guide .
    |cmd asp julia agent doctor --json .
    |cmd asp julia search workspace --view seeds .
    |cmd asp julia search prime --view seeds .
    |cmd asp julia search owner <owner-path> items --view seeds .
    |cmd asp julia query <owner-path> --term <symbol-or-prefix> --workspace <workspace-root> [--names-only|--code|--json]
    |cmd asp julia query --from-hook direct-source-read --selector <path:start-end> --workspace <workspace-root> --code
    |cmd asp julia search policy <rule-id-or-alias> owner tests --view seeds .
    |cmd asp julia search fzf <query> owner tests --view seeds .
    |cmd asp julia search deps <dependency[@version][::api]> owner tests --view seeds .
    |cmd asp julia search query --from-hook direct-source-read --selector <glob-or-path> --term <term> --surface owner,tests --view seeds --workspace <workspace-root>
    |pipe <candidate-lines> | asp julia search ingest owner tests --view seeds .
    |cmd asp julia check --changed .
    |rule selector queries do not need a trailing project root; --workspace <workspace-root> is the independent workspace override
    |rule query --code is pure code; search/read-plan returns locators/frontier, not inline code
    |rule use the asp julia facade by default; run one command at a time; no raw Julia source reads
    """
end

function render_julia_workspace_search(project_root::AbstractString)
    entries = julia_project_search_index(project_root)
    owners = search_entries_to_owner_paths(entries)
    tests = search_entries_to_test_paths(entries, project_root)
    lines = String[
        "[search-workspace] owner=$(length(owners)) tests=$(length(tests))",
        "|flow workspace->prime|owner|tests pipe=text:owner,tests ingest=stdin",
    ]
    for owner in owners[1:min(length(owners), 12)]
        push!(lines, "|seed owner:$(owner)")
    end
    !isempty(tests) && push!(lines, "|seed tests:$(join(tests[1:min(length(tests), 12)], ","))")
    push!(
        lines,
        "|synthesis algorithm=julia-workspace-index scope=workspace selectedOwners=$(length(owners)) testFrontier=$(search_seed_frontier(tests)) windowSet=$(search_window_set(owners, tests))",
    )
    join(lines, "\n") * "\n"
end

function render_julia_prime_search(project_root::AbstractString)
    entries = julia_project_search_index(project_root)
    owners = search_entries_to_owner_paths(entries)
    tests = search_entries_to_test_paths(entries, project_root)
    lines = String[
        "[search-prime] owner=$(length(owners)) tests=$(length(tests))",
        "|flow prime->owner|deps|symbol|tests pipe=text:owner,tests ingest=stdin",
    ]
    for owner in owners[1:min(length(owners), 12)]
        push!(lines, "|seed owner:$(owner)")
    end
    test_frontier = search_seed_frontier(tests)
    !isempty(tests) && push!(lines, "|seed tests:$(join(tests[1:min(length(tests), 12)], ","))")
    push!(
        lines,
        "|synthesis algorithm=julia-search-index scope=prime selectedOwners=$(length(owners)) testFrontier=$(test_frontier) windowSet=$(search_window_set(owners, tests))",
    )
    join(lines, "\n") * "\n"
end

function render_julia_owner_search(
    owner_path::AbstractString,
    pipes::Vector{String};
    project_root::AbstractString,
)
    entries = julia_project_search_index(project_root)
    owner = normalized_owner_path(owner_path)
    owner_entries = [
        entry for entry in entries
        if normalized_owner_path(search_entry_owner_path(entry, project_root)) == owner
    ]
    tests = related_julia_test_paths(entries, owner, project_root)
    edit_frontier = isempty(owner_entries) ? String[] : [owner]
    pipe_text = isempty(pipes) ? "-" : join(pipes, ",")
    lines = String[
        "[search-owner] q=$(owner_path) owner=$(isempty(owner_entries) ? 0 : 1) tests=$(length(tests)) pipes=$(pipe_text)",
        "|query $(owner_path) status=$(isempty(owner_entries) ? "miss" : "hit") owner=$(owner)",
    ]
    isempty(owner_entries) || push!(lines, "|seed owner:$(owner)")
    !isempty(tests) && push!(lines, "|seed tests:$(join(tests, ","))")
    push!(
        lines,
        "|synthesis algorithm=julia-owner-index scope=owner selectedOwners=$(isempty(owner_entries) ? 0 : 1) testFrontier=$(search_seed_frontier(tests)) windowSet=$(search_window_set(edit_frontier, tests))",
    )
    join(lines, "\n") * "\n"
end

function render_julia_text_search(
    query::AbstractString,
    pipes::Vector{String};
    project_root::AbstractString,
)
    results = search_julia_project(project_root, query; limit=16)
    owners = search_results_to_owner_paths(results, project_root)
    tests = search_results_to_test_paths(results, project_root)
    pipe_text = isempty(pipes) ? "-" : join(pipes, ",")
    lines = String[
        "[search-fzf] q=\"$(compact_cli_value(query))\" owner=$(length(owners)) tests=$(length(tests)) hit=$(length(results)) pipes=$(pipe_text)",
        "|flow prime->owner|deps|symbol|tests pipe=text:owner,tests ingest=stdin",
    ]
    for owner in owners
        push!(lines, "|seed owner:$(owner)")
    end
    !isempty(tests) && push!(lines, "|seed tests:$(join(tests, ","))")
    push!(
        lines,
        "|synthesis algorithm=julia-search-index scope=fzf selectedOwners=$(length(owners)) testFrontier=$(search_seed_frontier(tests)) windowSet=$(search_window_set(owners, tests))",
    )
    isempty(results) && push!(lines, "|note kind=not-found message=$(query)")
    join(lines, "\n") * "\n"
end

function render_julia_ingest_search(
    stdin_text::AbstractString,
    pipes::Vector{String};
    project_root::AbstractString,
)
    candidate_paths = ingest_candidate_paths(stdin_text, project_root)
    tests = filter(path -> occursin("/test/", "/$(path)") || startswith(path, "test/"), candidate_paths)
    owners = filter(path -> !(path in tests), candidate_paths)
    pipe_text = isempty(pipes) ? "-" : join(pipes, ",")
    lines = String[
        "[search-ingest] owner=$(length(owners)) tests=$(length(tests)) pipes=$(pipe_text)",
        "|flow ingest->owner|tests pipe=text:owner,tests",
    ]
    for owner in owners[1:min(length(owners), 12)]
        push!(lines, "|seed owner:$(owner)")
    end
    !isempty(tests) && push!(lines, "|seed tests:$(join(tests[1:min(length(tests), 12)], ","))")
    push!(
        lines,
        "|synthesis algorithm=stdin-candidate-paths scope=ingest selectedOwners=$(length(owners)) testFrontier=$(search_seed_frontier(tests)) windowSet=$(search_window_set(owners, tests))",
    )
    join(lines, "\n") * "\n"
end

function render_julia_policy_search(
    query::AbstractString,
    pipes::Vector{String};
    project_root::AbstractString,
)
    matches = julia_policy_rule_matches(query)
    owners = unique([julia_policy_rule_owner(rule) for rule in matches])
    tests = isempty(matches) ? String[] : unique(vcat([julia_policy_rule_tests(rule) for rule in matches]...))
    pipe_text = isempty(pipes) ? "-" : join(pipes, ",")
    lines = String[
        "[search-policy] q=$(query) handle=$(length(matches)) owner=$(length(owners)) tests=$(length(tests)) pipes=$(pipe_text)",
        "|flow prime->owner|deps|symbol|tests pipe=text:owner,tests ingest=stdin",
        "|query $(query) status=$(isempty(matches) ? "miss" : "hit") hit=$(length(matches)) selected=$(length(matches)) owner=$(isempty(owners) ? "-" : join(owners, ","))",
    ]
    for rule in matches
        rule_owner = julia_policy_rule_owner(rule)
        rule_tests = julia_policy_rule_tests(rule)
        push!(
            lines,
            "|handle $(rule.rule_id) kind=policy-rule source=provider-policy title=\"$(compact_cli_value(rule.title))\" owner=$(rule_owner) tests=$(join(rule_tests, ",")) packId=$(rule.pack_id) severity=$(severity_label(rule.severity)) requirement=\"$(compact_cli_value(rule.requirement))\"",
        )
    end
    for owner in owners
        push!(lines, "|seed owner:$(owner)")
    end
    if !isempty(tests)
        push!(lines, "|seed tests:$(join(tests, ","))")
    end
    summary = isempty(matches) ? "no provider-owned policy handles matched" : "resolved provider-owned policy handles"
    push!(
        lines,
        "|synthesis algorithm=policy-handle-catalog scope=policy summary=\"$(summary)\" selectedOwners=$(length(owners)) testFrontier=$(search_seed_frontier(tests)) windowSet=$(search_window_set(owners, tests))",
    )
    isempty(matches) && push!(lines, "|note kind=policy-not-found message=$(query)")
    join(lines, "\n") * "\n"
end

function search_entries_to_owner_paths(entries::Vector{JuliaSearchIndexEntry})
    sort!(unique([
        entry.name for entry in entries
        if entry.kind == "owner" && !isempty(entry.name)
    ]))
end

function search_entries_to_test_paths(
    entries::Vector{JuliaSearchIndexEntry},
    project_root::AbstractString,
)
    sort!(unique([
        search_entry_owner_path(entry, project_root)
        for entry in entries
        if is_julia_test_entry(entry) && !isnothing(entry.location.path)
    ]))
end

function search_results_to_owner_paths(
    results::Vector{JuliaSearchResult},
    project_root::AbstractString,
)
    sort!(unique([
        search_entry_owner_path(result.entry, project_root)
        for result in results
        if !is_julia_test_entry(result.entry) && !isnothing(result.entry.location.path)
    ]))
end

function search_results_to_test_paths(
    results::Vector{JuliaSearchResult},
    project_root::AbstractString,
)
    sort!(unique([
        search_entry_owner_path(result.entry, project_root)
        for result in results
        if is_julia_test_entry(result.entry) && !isnothing(result.entry.location.path)
    ]))
end

function search_entry_owner_path(entry::JuliaSearchIndexEntry, project_root::AbstractString)
    entry.kind == "owner" && return normalized_owner_path(entry.name)
    isnothing(entry.location.path) && return "<memory>"
    normalized_owner_path(relpath(entry.location.path, abspath(String(project_root))))
end

function related_julia_test_paths(
    entries::Vector{JuliaSearchIndexEntry},
    owner::AbstractString,
    project_root::AbstractString,
)
    owner_tokens = julia_owner_match_tokens(owner)
    isempty(owner_tokens) && return String[]
    path_candidates = String[]
    detail_candidates = String[]
    for entry in entries
        is_julia_test_entry(entry) || continue
        isnothing(entry.location.path) && continue
        test_path = search_entry_owner_path(entry, project_root)
        path_haystack = lowercase(test_path)
        detail_haystack = lowercase(join([entry.name, entry.detail], " "))
        if any(token -> occursin(token, path_haystack), owner_tokens)
            push!(path_candidates, test_path)
        elseif any(token -> occursin(token, detail_haystack), owner_tokens)
            push!(detail_candidates, test_path)
        end
    end
    sort!(unique(isempty(path_candidates) ? detail_candidates : path_candidates))
end

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
    isempty(normalized_query) && return JuliaHarnessRule[]
    [
        rule for rule in vcat(
            julia_syntax_rules(),
            julia_project_policy_rules(),
            julia_modularity_rules(),
            julia_agent_policy_rules(),
        ) if occursin(normalized_query, normalized_policy_rule_text(rule))
    ]
end

function normalized_policy_rule_text(rule::JuliaHarnessRule)
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

function julia_policy_rule_owner(rule::JuliaHarnessRule)
    rule.pack_id == JULIA_AGENT_POLICY_PACK_ID && return "src/rules/agent_catalog.jl"
    "src/rules/catalog.jl"
end

function julia_policy_rule_tests(rule::JuliaHarnessRule)
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
