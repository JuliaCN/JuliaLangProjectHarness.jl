const JULIA_QUERY_PACKET_SCHEMA_ID = "agent.semantic-protocols.semantic-query-packet"
const JULIA_QUERY_PACKET_SCHEMA_VERSION = "1"
const JULIA_QUERY_OWNER_ITEMS_METHOD = "query/owner-items"

function julia_query_terms(values::Vector{String})
    terms = String[]
    for value in values
        for term in split(value, '|')
            normalized = strip(String(term))
            isempty(normalized) || push!(terms, normalized)
        end
    end
    unique(terms)
end

function julia_query_owner_entries(owner_path::AbstractString, project_root::AbstractString)
    owner = normalized_owner_path(owner_path)
    entries = julia_exact_owner_search_entries(owner, project_root)
    [
        entry for entry in entries
        if normalized_owner_path(search_entry_owner_path(entry, project_root)) == owner &&
            String(entry.kind) != "owner"
    ]
end

function julia_query_entry_keys(
    entry::JuliaSearchIndexEntry,
    owner_path::AbstractString,
    qualified_name::AbstractString,
)
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
    unique(filter(!isempty, keys))
end

function julia_query_entry_match(entry::JuliaSearchIndexEntry, term::AbstractString, owner_path::AbstractString)
    qualified_name = asp_qualified_name(entry, owner_path)
    lowered_term = lowercase(strip(String(term)))
    keys = julia_query_entry_keys(entry, owner_path, qualified_name)
    lowered_keys = lowercase.(keys)
    any(key -> key == lowered_term, lowered_keys) && return "exact"
    any(key -> occursin(lowered_term, key), lowered_keys) && return "fallback-contains"
    return "none"
end

function julia_query_matching_entries(
    entries::Vector{JuliaSearchIndexEntry},
    terms::Vector{String},
    owner_path::AbstractString,
)
    matches = Pair{JuliaSearchIndexEntry,String}[]
    seen = Set{String}()
    for term in terms
        term_matches = Pair{JuliaSearchIndexEntry,String}[]
        for entry in entries
            match_kind = julia_query_entry_match(entry, term, owner_path)
            match_kind == "none" && continue
            push!(term_matches, entry => match_kind)
        end
        exact_matches = [pair for pair in term_matches if pair.second == "exact"]
        selected_matches = isempty(exact_matches) ? term_matches : exact_matches
        for pair in selected_matches
            key = asp_fact_id(pair.first, owner_path)
            key in seen && continue
            push!(seen, key)
            push!(matches, pair)
        end
    end
    sort!(matches; by = pair -> (pair.first.location.line, String(pair.first.kind), String(pair.first.name)))
end

function julia_query_candidate_items(
    entries::Vector{JuliaSearchIndexEntry},
    terms::Vector{String},
    owner_path::AbstractString;
    project_root::AbstractString,
    limit::Int=8,
)
    candidates = Dict{String,Dict{String,Any}}()
    lowered_terms = lowercase.(terms)
    for entry in sort(entries; by = entry -> (entry.location.line, String(entry.name)))
        isempty(entry.name) && continue
        name = String(entry.name)
        lowered_name = lowercase(name)
        reason = "owner-rank"
        term = isempty(terms) ? "" : first(terms)
        for (index, lowered_term) in enumerate(lowered_terms)
            if startswith(lowered_name, lowered_term) || startswith(lowered_term, lowered_name)
                reason = "prefix"
                term = terms[index]
                break
            elseif any(token -> length(token) >= 3 && occursin(token, lowered_name), split(lowered_term, r"[^a-z0-9_]+"))
                reason = "token-overlap"
                term = terms[index]
            end
        end
        haskey(candidates, name) && continue
        row = Dict{String,Any}(
            "name" => name,
            "reason" => reason,
            "location" => asp_location_row(entry.location, project_root),
        )
        isempty(term) || (row["term"] = term)
        candidates[name] = row
        length(candidates) >= limit && break
    end
    collect(values(candidates))
end

function julia_query_coverage(
    entries::Vector{JuliaSearchIndexEntry},
    terms::Vector{String},
    owner_path::AbstractString;
    project_root::AbstractString,
)
    rows = JuliaQueryCoverageRow[]
    candidates = julia_query_candidate_items(entries, terms, owner_path; project_root)
    typed_candidates = JuliaQueryCandidateItem[]
    sizehint!(typed_candidates, length(candidates))
    for candidate in candidates
        push!(typed_candidates, julia_query_candidate_item(candidate))
    end
    candidate_names = String[]
    sizehint!(candidate_names, length(typed_candidates))
    for candidate in typed_candidates
        push!(candidate_names, candidate.name)
    end
    for term in terms
        exact_count = count(entry -> julia_query_entry_match(entry, term, owner_path) == "exact", entries)
        fallback_count = count(entry -> julia_query_entry_match(entry, term, owner_path) == "fallback-contains", entries)
        if exact_count > 0
            push!(rows, JuliaQueryCoverageHit("hit", exact_count, term, "exact"))
        elseif fallback_count > 0
            push!(
                rows,
                JuliaQueryCoverageHit("hit", fallback_count, term, "fallback-contains"),
            )
        else
            if isempty(candidate_names)
                push!(
                    rows,
                    JuliaQueryCoverageMiss(
                        "miss",
                        "query:revise-term",
                        0,
                        term,
                        "none",
                    ),
                )
            else
                push!(
                    rows,
                    JuliaQueryCoverageMissWithCandidates(
                        candidate_names,
                        "miss",
                        "query:revise-term",
                        0,
                        term,
                        "none",
                    ),
                )
            end
        end
    end
    rows
end

function julia_query_match_mode(coverage::Vector{Dict{String,Any}})
    isempty(coverage) && return "unknown"
    matches = Set(String(row["match"]) for row in coverage)
    statuses = Set(String(row["status"]) for row in coverage)
    "miss" in statuses && length(statuses) > 1 && return "mixed"
    "miss" in statuses && return "unknown"
    length(matches) == 1 && "exact" in matches && return "exact"
    length(matches) == 1 && "fallback-contains" in matches && return "fallback-contains"
    return "mixed"
end
