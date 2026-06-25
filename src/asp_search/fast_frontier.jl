struct JuliaFastSearchFrontier
    scope::JuliaProjectHarnessScope
    workspace_member_scopes::Vector{JuliaProjectHarnessScope}
    owners::Vector{String}
    tests::Vector{String}
    files::Vector{String}
end

const JULIA_FAST_FRONTIER_CACHE = Dict{String,JuliaFastSearchFrontier}()
const JULIA_FAST_FILE_TEXT_CACHE = Dict{String,Tuple{Float64,String}}()
const JULIA_FAST_FILE_LOWER_CACHE = Dict{String,Tuple{Float64,String}}()

function julia_fast_seed_frontier(project_root::AbstractString)
    config = default_julia_harness_config()
    root = abspath(String(project_root))
    if haskey(JULIA_FAST_FRONTIER_CACHE, root)
        return JULIA_FAST_FRONTIER_CACHE[root]
    end
    scope = julia_project_harness_scope(root, config)
    workspace_member_scopes = julia_workspace_member_scopes(scope, config)
    search_paths = vcat(
        scope_search_paths(scope),
        mapreduce(scope_search_paths, vcat, workspace_member_scopes; init=String[]),
    )
    files = [
        normalized_owner_path(relpath(path, scope.project_root))
        for path in discover_julia_files(search_paths, config)
    ]
    files = sort!(unique(files))
    owners = [path for path in files if !is_julia_test_path(path)]
    tests = [path for path in files if is_julia_test_path(path)]
    frontier = JuliaFastSearchFrontier(scope, workspace_member_scopes, owners, tests, files)
    JULIA_FAST_FRONTIER_CACHE[root] = frontier
    frontier
end

function julia_fast_seed_packet_base(
    view::AbstractString,
    project_root::AbstractString;
    render_mode::AbstractString,
    query::Union{Nothing,AbstractString}=nothing,
)
    packet = julia_search_packet_base(view, render_mode, project_root; query)
    packet["runtimeCost"] = Dict{String,Any}(
        "cacheStatus" => "fast-path",
        "parserFactsReused" => false,
        "reason" => "provider-owned Julia seeds projection avoids full syntax index",
    )
    packet["nativeSyntaxFacts"] = Dict{String,Any}[]
    packet
end

function julia_fast_workspace_search_packet(project_root::AbstractString; render_mode::AbstractString="seeds")
    frontier = julia_fast_seed_frontier(project_root)
    packet = julia_fast_seed_packet_base("workspace", project_root; render_mode)
    packet["nodes"] = [
        Dict{String,Any}(
            "id" => "owner:$(owner)",
            "kind" => "owner",
            "path" => owner,
            "fields" => Dict{String,Any}("source" => "julia-fast-file-frontier"),
        ) for owner in frontier.owners[1:min(length(frontier.owners), 24)]
    ]
    julia_search_attach_frontier!(
        packet,
        frontier.owners,
        frontier.tests;
        algorithm="julia-fast-file-frontier-v1",
        scope="workspace",
        summary="Julia workspace owner and test frontier from file paths",
    )
end

function julia_fast_prime_search_packet(project_root::AbstractString; render_mode::AbstractString="seeds")
    frontier = julia_fast_seed_frontier(project_root)
    packet = julia_fast_seed_packet_base("prime", project_root; render_mode)
    packet["nodes"] = [
        Dict{String,Any}(
            "id" => "owner:$(owner)",
            "kind" => "owner",
            "path" => owner,
            "fields" => Dict{String,Any}("source" => "julia-fast-file-frontier"),
        ) for owner in frontier.owners[1:min(length(frontier.owners), 24)]
    ]
    julia_search_attach_frontier!(
        packet,
        frontier.owners,
        frontier.tests;
        algorithm="julia-fast-file-frontier-v1",
        scope="prime",
        summary="Julia package owner and test frontier from file paths",
    )
end

function julia_fast_owner_search_packet(
    owner_path::AbstractString,
    project_root::AbstractString;
    render_mode::AbstractString="seeds",
)
    frontier = julia_fast_seed_frontier(project_root)
    owner = normalized_owner_path(owner_path)
    owner_exists = owner in frontier.files || isfile(joinpath(frontier.scope.project_root, owner))
    tests = julia_fast_related_test_paths(frontier, owner)
    packet = julia_fast_seed_packet_base("owner", project_root; render_mode, query=owner_path)
    packet["ownerResolution"] = [
        Dict{String,Any}(
            "target" => owner,
            "status" => owner_exists ? "workspace-owner" : "missing",
            "realOwner" => owner_exists,
            "ownerPath" => owner,
            "reason" => "Julia fast file owner lookup",
        ),
    ]
    owner_exists || push!(packet["notes"], Dict("kind" => "owner-not-found", "message" => "No Julia owner matched $(owner)."))
    julia_search_attach_frontier!(
        packet,
        owner_exists ? [owner] : String[],
        tests;
        algorithm="julia-fast-owner-frontier-v1",
        scope="owner",
        summary=owner_exists ? "Resolved Julia owner from file paths" : "No Julia owner matched",
    )
end

function julia_fast_fzf_search_packet(
    query::AbstractString,
    project_root::AbstractString;
    render_mode::AbstractString="seeds",
    query_set::Vector{String}=String[],
)
    terms = isempty(query_set) ? [String(query)] : String.(query_set)
    frontier = julia_fast_seed_frontier(project_root)
    owners, tests = julia_fast_query_paths(frontier, terms)
    if isempty(owners) && isempty(tests)
        owners = frontier.owners[1:min(length(frontier.owners), 12)]
        tests = frontier.tests[1:min(length(frontier.tests), 12)]
    end
    packet = julia_fast_seed_packet_base("fzf", project_root; render_mode, query)
    packet["querySet"] = [
        Dict{String,Any}("value" => term, "kind" => "text", "selector" => "fuzzy")
        for term in terms
    ]
    packet["queryCoverage"] = [
        Dict{String,Any}(
            "value" => term,
            "kind" => "text",
            "selector" => "fuzzy",
            "status" => "frontier",
            "hitCount" => length(owners) + length(tests),
            "ownerPaths" => owners,
            "surfaces" => unique(vcat(isempty(owners) ? String[] : ["real-source"], isempty(tests) ? String[] : ["test-source"])),
        ) for term in terms
    ]
    julia_search_attach_frontier!(
        packet,
        owners,
        tests;
        algorithm="julia-fast-fzf-frontier-v1",
        scope="fzf",
        summary="Resolved Julia fuzzy candidates from file path/content scan",
    )
end

function julia_fast_dependency_search_packet(
    query::AbstractString,
    project_root::AbstractString;
    render_mode::AbstractString="seeds",
)
    request = parse_julia_dependency_search_query(query)
    frontier = julia_fast_seed_frontier(project_root)
    scopes = vcat([frontier.scope], frontier.workspace_member_scopes)
    dependency_nodes = julia_dependency_package_nodes(scopes, request, project_root)
    owners = isempty(dependency_nodes) ? String[] : julia_fast_package_entry_owners(frontier)
    isempty(owners) && (owners = frontier.owners[1:min(length(frontier.owners), 4)])
    tests = frontier.tests[1:min(length(frontier.tests), 12)]
    packet = julia_fast_seed_packet_base("deps", project_root; render_mode, query)
    packet["querySet"] = [julia_dependency_query_term(request)]
    packet["queryCoverage"] = [
        julia_dependency_query_coverage(
            request,
            query,
            length(dependency_nodes),
            owners;
            declared_dependency_count=length(dependency_nodes),
        ),
    ]
    packet["nodes"] = dependency_nodes
    isempty(dependency_nodes) && push!(
        packet["notes"],
        Dict("kind" => "dependency-not-found", "message" => String(query)),
    )
    julia_search_attach_frontier!(
        packet,
        owners,
        tests;
        algorithm="julia-fast-dependency-frontier-v1",
        scope="dependency",
        summary=isempty(dependency_nodes) ? "No Julia dependency declaration matched" : "Resolved Julia dependency declaration",
    )
    packet["searchSynthesis"]["fields"] = julia_dependency_query_fields(request)
    packet
end

function julia_fast_package_entry_owners(frontier::JuliaFastSearchFrontier)
    owners = String[]
    for scope in vcat([frontier.scope], frontier.workspace_member_scopes)
        isnothing(scope.package_entry_path) && continue
        push!(owners, normalized_owner_path(relpath(scope.package_entry_path, frontier.scope.project_root)))
    end
    sort!(unique([owner for owner in owners if owner in frontier.files]))
end

function julia_fast_related_test_paths(frontier::JuliaFastSearchFrontier, owner::AbstractString)
    tokens = julia_owner_match_tokens(owner)
    isempty(tokens) && return frontier.tests[1:min(length(frontier.tests), 12)]
    path_matches = [
        test for test in frontier.tests
        if any(token -> occursin(token, lowercase(test)), tokens)
    ]
    isempty(path_matches) ? frontier.tests[1:min(length(frontier.tests), 12)] : path_matches[1:min(length(path_matches), 12)]
end

function julia_fast_query_paths(frontier::JuliaFastSearchFrontier, terms::Vector{String})
    needles = [
        lowercase(strip(term))
        for term in terms
        if !isempty(strip(term))
    ]
    isempty(needles) && return String[], String[]
    owners = julia_fast_query_path_group(frontier, frontier.owners, needles, 16)
    tests = julia_fast_query_path_group(frontier, frontier.tests, needles, 16)
    julia_fast_sorted_unique_prefix!(owners, 16), julia_fast_sorted_unique_prefix!(tests, 16)
end

function julia_fast_query_path_group(
    frontier::JuliaFastSearchFrontier,
    paths::Vector{String},
    needles::Vector{String},
    limit::Int,
)
    matches = String[]
    for path in paths
        julia_fast_path_matches_query(frontier.scope.project_root, path, needles) || continue
        push!(matches, path)
        length(matches) >= limit && break
    end
    matches
end

function julia_fast_sorted_unique_prefix!(paths::Vector{String}, limit::Int)
    sort!(paths)
    unique!(paths)
    paths[1:min(length(paths), limit)]
end

function julia_fast_path_matches_query(
    project_root::AbstractString,
    relative_path::AbstractString,
    needles::Vector{String},
)
    haystack = lowercase(String(relative_path))
    any(needle -> occursin(needle, haystack), needles) && return true
    full_path = joinpath(project_root, relative_path)
    isfile(full_path) || return false
    text = julia_fast_file_text(full_path)
    any(needle -> occursin(needle, text), needles) && return true
    lower_text = julia_fast_lower_file_text(full_path, text)
    any(needle -> occursin(needle, lower_text), needles)
end

function julia_fast_file_text(full_path::AbstractString)
    path = String(full_path)
    mtime = try
        stat(path).mtime
    catch
        return ""
    end
    cached = get(JULIA_FAST_FILE_TEXT_CACHE, path, nothing)
    if !isnothing(cached) && cached[1] == mtime
        return cached[2]
    end
    text = try
        read(path, String)
    catch
        ""
    end
    JULIA_FAST_FILE_TEXT_CACHE[path] = (mtime, text)
    text
end

function julia_fast_lower_file_text(full_path::AbstractString, text::AbstractString)
    path = String(full_path)
    mtime = try
        stat(path).mtime
    catch
        return ""
    end
    cached = get(JULIA_FAST_FILE_LOWER_CACHE, path, nothing)
    if !isnothing(cached) && cached[1] == mtime
        return cached[2]
    end
    lower_text = lowercase(String(text))
    JULIA_FAST_FILE_LOWER_CACHE[path] = (mtime, lower_text)
    lower_text
end
