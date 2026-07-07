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

