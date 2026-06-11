struct JuliaDependencySearchRequest
    package_name::String
    requested_version::Union{Nothing,String}
    api_query::Union{Nothing,String}
end

function parse_julia_dependency_search_query(query::AbstractString)
    stripped = strip(String(query))
    isempty(stripped) && error("search deps requires a dependency query")
    query_parts = split(stripped, "::"; limit=2)
    package_selector = strip(first(query_parts))
    isempty(package_selector) && error("search deps requires a dependency name")
    api_query = length(query_parts) == 2 ? strip(query_parts[2]) : nothing
    api_query = !isnothing(api_query) && !isempty(api_query) ? api_query : nothing
    package_parts = split(package_selector, "@"; limit=2)
    package_name = strip(first(package_parts))
    isempty(package_name) && error("search deps requires a dependency name")
    requested_version = length(package_parts) == 2 ? strip(package_parts[2]) : nothing
    requested_version = !isnothing(requested_version) && !isempty(requested_version) ? requested_version : nothing
    JuliaDependencySearchRequest(package_name, requested_version, api_query)
end

function julia_dependency_search_packet(
    query::AbstractString,
    project_root::AbstractString;
    render_mode::AbstractString="seeds",
)
    request = parse_julia_dependency_search_query(query)
    config = default_julia_harness_config()
    scope = julia_project_harness_scope(project_root, config)
    workspace_member_scopes = julia_workspace_member_scopes(scope, config)
    entries = julia_project_search_index(project_root; config)
    dependency_entries = [
        entry for entry in entries if julia_dependency_entry_matches(entry, request)
    ]
    dependency_owner_paths = Set([
        search_entry_owner_path(entry, project_root) for entry in dependency_entries
        if !isnothing(entry.location.path)
    ])
    usage_entries = [
        entry for entry in entries
        if !julia_dependency_entry_matches(entry, request) &&
           julia_dependency_usage_entry_matches(entry, request, dependency_owner_paths, project_root)
    ]
    unique_hit_entries = unique_julia_search_entries(vcat(dependency_entries, usage_entries))
    hit_entries = unique_hit_entries[1:min(length(unique_hit_entries), 32)]
    owners = sort!(unique([
        search_entry_owner_path(entry, project_root) for entry in hit_entries
        if !is_julia_test_entry(entry) && !isnothing(entry.location.path)
    ]))
    tests = sort!(unique(vcat(
        [
            search_entry_owner_path(entry, project_root) for entry in hit_entries
            if is_julia_test_entry(entry) && !isnothing(entry.location.path)
        ],
        mapreduce(
            owner -> related_julia_test_paths(entries, owner, project_root),
            vcat,
            owners;
            init=String[],
        ),
    )))
    dependency_nodes = julia_dependency_package_nodes(vcat([scope], workspace_member_scopes), request, project_root)
    packet = julia_search_packet_base("deps", render_mode, project_root; query)
    packet["querySet"] = [julia_dependency_query_term(request)]
    packet["queryCoverage"] = [
        julia_dependency_query_coverage(
            request,
            query,
            length(hit_entries),
            owners;
            declared_dependency_count=length(dependency_nodes),
        ),
    ]
    packet["nodes"] = dependency_nodes
    packet["hits"] = [
        julia_dependency_search_hit_row(
            entry,
            request,
            project_root;
            score=julia_dependency_entry_matches(entry, request) ? 100.0 : 80.0,
            reason=julia_dependency_entry_matches(entry, request) ? "dependency-import" : "dependency-usage",
        ) for entry in hit_entries
    ]
    packet["nativeSyntaxFacts"] = julia_search_native_facts(hit_entries, project_root)
    cache_hashes = julia_dependency_cache_file_hashes(
        vcat([scope], workspace_member_scopes),
        hit_entries,
        project_root,
    )
    isempty(cache_hashes) || (packet["cache"] = Dict{String,Any}(
        "fileHashes" => cache_hashes,
        "rawSourceStored" => false,
    ))
    packet["runtimeCost"] = Dict{String,Any}(
        "cacheStatus" => "cold",
        "sourceFilesParsed" => length(unique([
            entry.location.path for entry in entries if !isnothing(entry.location.path)
        ])),
        "packagesScanned" => 1 + length(workspace_member_scopes),
        "parserFactsReused" => false,
        "reason" => "provider-owned Julia dependency search packet",
    )
    isempty(hit_entries) && isempty(dependency_nodes) && push!(
        packet["notes"],
        Dict("kind" => "dependency-not-found", "message" => String(query)),
    )
    julia_search_attach_frontier!(
        packet,
        owners,
        tests;
        algorithm="julia-dependency-search-index",
        scope="dependency",
        summary=isempty(hit_entries) ? "No Julia dependency usage matched" : "Resolved Julia dependency usage",
    )
    packet["searchSynthesis"]["fields"] = julia_dependency_query_fields(request)
    packet
end

function julia_dependency_query_term(request::JuliaDependencySearchRequest)
    fields = julia_dependency_query_fields(request)
    Dict{String,Any}(
        "value" => request.package_name,
        "kind" => "dependency",
        "selector" => "exact",
        "fields" => fields,
    )
end

function julia_dependency_query_coverage(
    request::JuliaDependencySearchRequest,
    query::AbstractString,
    hit_count::Int,
    owners::Vector{String};
    declared_dependency_count::Int,
)
    status = hit_count > 0 ? "hit" : declared_dependency_count > 0 ? "partial" : "miss"
    fields = julia_dependency_query_fields(request)
    fields["declaredDependencyCount"] = declared_dependency_count
    Dict{String,Any}(
        "value" => String(query),
        "kind" => "dependency",
        "selector" => "exact",
        "status" => status,
        "hitCount" => hit_count,
        "ownerPaths" => owners,
        "surfaces" => isempty(owners) ? String[] : ["real-source"],
        "fields" => fields,
    )
end

function julia_dependency_query_fields(request::JuliaDependencySearchRequest)
    fields = Dict{String,Any}("dependency" => request.package_name)
    isnothing(request.requested_version) || (fields["requestedVersion"] = request.requested_version)
    isnothing(request.api_query) || (fields["apiQuery"] = request.api_query)
    fields
end

function julia_dependency_search_hit_row(
    entry::JuliaSearchIndexEntry,
    request::JuliaDependencySearchRequest,
    project_root::AbstractString;
    score::Real,
    reason::AbstractString,
)
    row = julia_search_hit_row(entry, project_root; score, reason)
    row["fields"]["dependency"] = request.package_name
    isnothing(request.requested_version) || (row["fields"]["requestedVersion"] = request.requested_version)
    isnothing(request.api_query) || (row["fields"]["apiQuery"] = request.api_query)
    row
end

function julia_dependency_package_nodes(
    scopes::Vector{JuliaProjectHarnessScope},
    request::JuliaDependencySearchRequest,
    project_root::AbstractString,
)
    nodes = Dict{String,Any}[]
    seen = Set{String}()
    for scope in scopes
        append_julia_dependency_package_nodes!(
            nodes,
            seen,
            scope.direct_dependencies,
            scope,
            request,
            project_root;
            dependency_kind="normal",
        )
        append_julia_dependency_package_nodes!(
            nodes,
            seen,
            scope.weak_dependencies,
            scope,
            request,
            project_root;
            dependency_kind="weak",
        )
        append_julia_dependency_package_nodes!(
            nodes,
            seen,
            scope.extra_dependencies,
            scope,
            request,
            project_root;
            dependency_kind="extra",
        )
    end
    nodes
end

function append_julia_dependency_package_nodes!(
    nodes::Vector{Dict{String,Any}},
    seen::Set{String},
    dependencies::Dict{String,String},
    scope::JuliaProjectHarnessScope,
    request::JuliaDependencySearchRequest,
    project_root::AbstractString;
    dependency_kind::AbstractString,
)
    for (name, uuid) in sort!(collect(dependencies); by=first)
        julia_dependency_name_matches(name, request.package_name) || continue
        node_key = "$(scope.project_root):$(name):$(dependency_kind)"
        node_key in seen && continue
        push!(seen, node_key)
        fields = Dict{String,Any}(
            "name" => String(name),
            "uuid" => String(uuid),
            "dependencyKind" => String(dependency_kind),
            "versionScope" => isnothing(request.requested_version) ? "current" : "external",
        )
        haskey(scope.compat, name) && (fields["versionReq"] = scope.compat[name])
        push!(
            nodes,
            Dict{String,Any}(
                "id" => "dependency:$(normalized_dependency_node_id(name))",
                "kind" => "dependency",
                "path" => isnothing(scope.project_toml_path) ? "." : asp_project_path(scope.project_toml_path, project_root),
                "targetRole" => "dep",
                "fields" => fields,
            ),
        )
    end
    nodes
end

function normalized_dependency_node_id(name::AbstractString)
    replace(lowercase(String(name)), r"[^a-z0-9_-]+" => "-")
end

function julia_dependency_entry_matches(
    entry::JuliaSearchIndexEntry,
    request::JuliaDependencySearchRequest,
)
    ("dependency" in entry.tags || entry.kind in ("using", "import")) || return false
    any(value -> julia_dependency_name_matches(value, request.package_name), vcat(entry.tags, [entry.name]))
end

function julia_dependency_usage_entry_matches(
    entry::JuliaSearchIndexEntry,
    request::JuliaDependencySearchRequest,
    dependency_owner_paths::Set{String},
    project_root::AbstractString,
)
    isnothing(request.api_query) && return false
    isnothing(entry.location.path) && return false
    api_tokens = search_query_tokens(request.api_query)
    isempty(api_tokens) && return false
    text = normalize_search_text(join([entry.name, entry.detail, entry.search_text], " "))
    all(token -> occursin(token, text), api_tokens) || return false
    owner = search_entry_owner_path(entry, project_root)
    owner in dependency_owner_paths && return true
    occursin(normalize_search_text(request.package_name), text)
end

function julia_dependency_name_matches(candidate::AbstractString, requested::AbstractString)
    normalized_candidate = normalize_search_text(candidate)
    normalized_requested = normalize_search_text(requested)
    normalized_candidate == normalized_requested ||
        startswith(normalized_candidate, "$(normalized_requested):") ||
        startswith(normalized_candidate, "$(normalized_requested).")
end

function unique_julia_search_entries(entries::Vector{JuliaSearchIndexEntry})
    unique_entries = JuliaSearchIndexEntry[]
    seen = Set{Tuple{String,Int,Int,String,String}}()
    for entry in entries
        key = (
            something(entry.location.path, ""),
            entry.location.line,
            entry.location.column,
            entry.kind,
            entry.name,
        )
        key in seen && continue
        push!(seen, key)
        push!(unique_entries, entry)
    end
    unique_entries
end

function julia_dependency_cache_file_hashes(
    scopes::Vector{JuliaProjectHarnessScope},
    hit_entries::Vector{JuliaSearchIndexEntry},
    project_root::AbstractString,
)
    paths = String[]
    for scope in scopes
        append!(paths, julia_dependency_project_cache_paths(scope))
    end
    for entry in hit_entries
        isnothing(entry.location.path) && continue
        isfile(entry.location.path) || continue
        push!(paths, entry.location.path)
    end
    unique_paths = sort!(unique(normpath.(paths)))
    [
        Dict{String,Any}(
            "path" => asp_project_path(path, project_root),
            "sha256" => julia_sha256_file(path),
        ) for path in unique_paths if isfile(path)
    ]
end

function julia_dependency_project_cache_paths(scope::JuliaProjectHarnessScope)
    paths = String[]
    !isnothing(scope.project_toml_path) && isfile(scope.project_toml_path) && push!(paths, scope.project_toml_path)
    for manifest_name in julia_manifest_file_names()
        manifest_path = joinpath(scope.project_root, manifest_name)
        isfile(manifest_path) && push!(paths, manifest_path)
    end
    paths
end

function julia_manifest_file_names()
    ["Manifest.toml", "JuliaManifest.toml", "Manifest-v$(VERSION.major).$(VERSION.minor).toml"]
end

function julia_sha256_file(path::AbstractString)
    bytes2hex(SHA.sha256(read(path)))
end
