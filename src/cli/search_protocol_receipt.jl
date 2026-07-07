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

