struct JuliaQueryLocation
    path::String
    lineRange::String
end

struct JuliaQueryCoverageHit
    status::String
    matchCount::Int
    value::String
    match::String
end

struct JuliaQueryCoverageMiss
    status::String
    nextAction::String
    matchCount::Int
    value::String
    match::String
end

struct JuliaQueryCoverageMissWithCandidates
    candidateNames::Vector{String}
    status::String
    nextAction::String
    matchCount::Int
    value::String
    match::String
end

const JuliaQueryCoverageRow = Union{
    JuliaQueryCoverageHit,
    JuliaQueryCoverageMiss,
    JuliaQueryCoverageMissWithCandidates,
}

function julia_query_match_mode(coverage::Vector{JuliaQueryCoverageRow})
    isempty(coverage) && return "unknown"
    matches = Set(row.match for row in coverage)
    statuses = Set(row.status for row in coverage)
    "miss" in statuses && length(statuses) > 1 && return "mixed"
    "miss" in statuses && return "unknown"
    length(matches) == 1 && "exact" in matches && return "exact"
    length(matches) == 1 && "fallback-contains" in matches && return "fallback-contains"
    return "mixed"
end

struct JuliaQueryCandidateItem
    term::String
    name::String
    location::JuliaQueryLocation
    reason::String
end

struct JuliaQueryMatchFields
    juliaKind::String
    sourceLocatorHint::String
    portableKind::String
    displayLineRange::String
    structuralSelector::String
end

struct JuliaQueryMatchRowBase
    visibility::String
    fields::JuliaQueryMatchFields
    truncated::Bool
    name::String
    kind::String
    location::JuliaQueryLocation
    sourceLocatorHint::String
    doc::Bool
    displayLineRange::String
    structuralSelector::String
    read::String
end

struct JuliaQueryMatchRowWithCode
    visibility::String
    fields::JuliaQueryMatchFields
    truncated::Bool
    name::String
    kind::String
    location::JuliaQueryLocation
    sourceLocatorHint::String
    doc::Bool
    displayLineRange::String
    structuralSelector::String
    read::String
    code::String
    projection::Dict{String,Any}
end

const JuliaQueryMatchRow = Union{JuliaQueryMatchRowBase,JuliaQueryMatchRowWithCode}

struct JuliaQueryPatchSafety
    level::String
    reason::String
end

struct JuliaQueryPatchSafetyWithExactRead
    level::String
    reason::String
    exactRead::String
end

const JuliaQueryPatchSafetyPacket =
    Union{JuliaQueryPatchSafety,JuliaQueryPatchSafetyWithExactRead}

struct JuliaQueryPacketNote
    kind::String
    message::String
end

struct JuliaOwnerItemsQueryPacket
    schemaId::String
    schemaVersion::String
    protocolId::String
    protocolVersion::String
    languageId::String
    providerId::String
    binary::String
    namespace::String
    method::String
    projectRoot::String
    packageName::String
    ownerPath::String
    query::String
    queryTerms::Vector{String}
    matchMode::String
    outputMode::String
    queryCoverage::Vector{JuliaQueryCoverageRow}
	candidateItems::Vector{JuliaQueryCandidateItem}
    nativeSyntaxFacts::Vector{Dict{String,Any}}
    matches::Vector{JuliaQueryMatchRow}
    matchCount::Int
    matchLimit::Int
    matchesTruncated::Bool
    truncated::Bool
    patchSafety::JuliaQueryPatchSafetyPacket
    notes::Vector{JuliaQueryPacketNote}
end

"""Build a shared semantic-query-packet for Julia owner-local item lookup.

Throws `ErrorException` when `query_terms` is empty after `|` splitting or when
`match_limit` is negative. Callers should validate CLI `--term` / `--query` and
`--limit` before exposing the packet on public agent routes.
"""
function julia_query_location(row::Dict{String,Any})
    JuliaQueryLocation(row["path"]::String, row["lineRange"]::String)
end

function julia_query_location(row::Dict{String,String})
    JuliaQueryLocation(row["path"], row["lineRange"])
end

function julia_query_coverage_row(row::Dict{String,Any})
    status = row["status"]::String
    match_count = row["matchCount"]::Int
    value = row["value"]::String
    match = row["match"]::String
    if status == "hit"
        return JuliaQueryCoverageHit(status, match_count, value, match)
    end
    next_action = row["nextAction"]::String
    if haskey(row, "candidateNames")
        return JuliaQueryCoverageMissWithCandidates(
            row["candidateNames"]::Vector{String},
            status,
            next_action,
            match_count,
            value,
            match,
        )
    end
    JuliaQueryCoverageMiss(status, next_action, match_count, value, match)
end

function julia_query_candidate_item(row::Dict{String,Any})
    JuliaQueryCandidateItem(
        row["term"]::String,
        row["name"]::String,
        julia_query_location(row["location"]::Dict{String,String}),
        row["reason"]::String,
    )
end

function julia_query_match_fields(row::Dict{String,Any})
    JuliaQueryMatchFields(
        row["juliaKind"]::String,
        row["sourceLocatorHint"]::String,
        row["portableKind"]::String,
        row["displayLineRange"]::String,
        row["structuralSelector"]::String,
    )
end

function julia_query_match_fields(row::Dict{String,String})
    JuliaQueryMatchFields(
        row["juliaKind"],
        row["sourceLocatorHint"],
        row["portableKind"],
        row["displayLineRange"],
        row["structuralSelector"],
    )
end

function julia_query_match_row_packet(row::Dict{String,Any})
    fields = julia_query_match_fields(row["fields"]::Dict{String,Any})
    location = julia_query_location(row["location"]::Dict{String,String})
    common = (
        row["visibility"]::String,
        fields,
        row["truncated"]::Bool,
        row["name"]::String,
        row["kind"]::String,
        location,
        row["sourceLocatorHint"]::String,
        row["doc"]::Bool,
        row["displayLineRange"]::String,
        row["structuralSelector"]::String,
        row["read"]::String,
    )
    if haskey(row, "code")
        return JuliaQueryMatchRowWithCode(
            common...,
            row["code"]::String,
            row["projection"]::Dict{String,Any},
        )
    end
    JuliaQueryMatchRowBase(common...)
end

"""Build the typed owner-items packet used by Julia query projections.

Throws `ErrorException` when `query_terms` is empty after `|` splitting or when
`match_limit` is negative. Callers must validate those public CLI inputs before
publishing the packet.
"""
function julia_query_owner_items_packet(
    owner_path::AbstractString,
    query_terms::Vector{String};
    project_root::AbstractString=pwd(),
    names_only::Bool=false,
    code::Bool=false,
    match_limit::Int=25,
    structural_selector=nothing,
)
    root = abspath(String(project_root))
    owner = normalized_owner_path(owner_path)
    terms = julia_query_terms(query_terms)
    isempty(terms) && error("query/owner-items requires --term or --query")
    match_limit >= 0 || error("--limit must be non-negative")
    entries = julia_query_owner_entries(owner, root)
    owner_found = !isempty(entries)
    if !isnothing(structural_selector)
        expected_selector = String(structural_selector)
        entries = [
            entry for entry in entries
            if julia_query_structural_selector(entry, asp_location_row(entry.location, root)) == expected_selector
        ]
    end
    coverage = julia_query_coverage(entries, terms, owner; project_root=root)
    matched_pairs = julia_query_matching_entries(entries, terms, owner)
    total_matches = length(matched_pairs)
    selected_pairs = matched_pairs[1:min(total_matches, match_limit)]
    include_code = code && !names_only
    matches = JuliaQueryMatchRow[]
    native_syntax_facts = Dict{String,Any}[]
    sizehint!(matches, length(selected_pairs))
    sizehint!(native_syntax_facts, length(selected_pairs))
    for pair in selected_pairs
        push!(
            matches,
            julia_query_match_row_packet(
                julia_query_match_row(pair.first, root; include_code),
            ),
        )
        push!(native_syntax_facts, asp_search_index_fact(pair.first, root))
    end
    candidate_rows =
        total_matches == 0 ?
        julia_query_candidate_items(entries, terms, owner; project_root=root) :
        Dict{String,Any}[]
    candidates = JuliaQueryCandidateItem[
        julia_query_candidate_item(candidate) for candidate in candidate_rows
    ]
    scope = julia_project_harness_scope(root, default_julia_harness_config())
    patch_safety::JuliaQueryPatchSafetyPacket = JuliaQueryPatchSafety(
        "read-safe",
        "Julia compact query output requires exact source read before editing",
    )
    notes = JuliaQueryPacketNote[]
    if !isempty(matches)
        patch_safety = JuliaQueryPatchSafetyWithExactRead(
            "read-safe",
            "Julia compact query output requires exact source read before editing",
            first(matches).read,
        )
    elseif !owner_found
        push!(
            notes,
            JuliaQueryPacketNote(
                "owner-not-found",
                "No Julia parser facts were found for owner $(owner).",
            ),
        )
    elseif isempty(candidates)
        push!(
            notes,
            JuliaQueryPacketNote(
                "query-not-found",
                "No Julia owner-local item matched $(join(terms, "|")).",
            ),
        )
    end
    JuliaOwnerItemsQueryPacket(
        JULIA_QUERY_PACKET_SCHEMA_ID,
        JULIA_QUERY_PACKET_SCHEMA_VERSION,
        JULIA_INDEX_EXPORT_PROTOCOL_ID,
        JULIA_INDEX_EXPORT_PROTOCOL_VERSION,
        JULIA_INDEX_EXPORT_LANGUAGE_ID,
        JULIA_INDEX_EXPORT_PROVIDER_ID,
        JULIA_AGENT_BINARY,
        JULIA_AGENT_PROVIDER_NAMESPACE,
        JULIA_QUERY_OWNER_ITEMS_METHOD,
        root,
        something(scope.package_name, basename(root)),
        owner,
        join(terms, "|"),
        terms,
        julia_query_match_mode(coverage),
        names_only ? "names" : (code ? "code" : "outline"),
        coverage,
        candidates,
        native_syntax_facts,
        matches,
        total_matches,
        match_limit,
        total_matches > length(selected_pairs),
        total_matches > length(selected_pairs),
        patch_safety,
        notes,
    )
end

"""Render Julia owner-local item lookup as shared semantic-query-packet JSON."""
function render_julia_query_owner_items_json(
    owner_path::AbstractString,
    query_terms::Vector{String};
    project_root::AbstractString=pwd(),
    names_only::Bool=false,
    code::Bool=false,
    match_limit::Int=25,
    structural_selector=nothing,
)
    JSON.json(
        julia_query_owner_items_packet(
            owner_path,
            query_terms;
            project_root,
            names_only,
            code,
            match_limit,
            structural_selector,
        ),
    )
end

include("native_owner.jl")

"""Render Julia owner-local item lookup as compact line protocol."""
function render_julia_query_owner_items(
    owner_path::AbstractString,
    query_terms::Vector{String};
    project_root::AbstractString=pwd(),
    names_only::Bool=false,
    code::Bool=false,
    match_limit::Int=25,
    structural_selector=nothing,
)
    packet = julia_query_owner_items_packet(
        owner_path,
        query_terms;
        project_root,
        names_only,
        code,
        match_limit,
        structural_selector,
    )
    lines = String[
        "[query-item] owner=$(packet.ownerPath) terms=$(packet.query) match=$(packet.matchMode) hit=$(packet.matchCount) mode=$(packet.outputMode) truncated=$(packet.truncated)",
    ]
    for coverage in packet.queryCoverage
        candidate_text = haskey(coverage, "candidateNames") ? join(coverage["candidateNames"], ",") : "-"
        push!(
            lines,
            "|query term=$(coverage["value"]) status=$(coverage["status"]) match=$(coverage["match"]) hit=$(coverage["matchCount"]) candidates=$(candidate_text)",
        )
    end
    for match in packet.matches
        push!(
            lines,
            "|item $(match["name"]) kind=$(match["kind"]) visibility=$(match["visibility"]) structuralSelector=$(match["structuralSelector"]) displayLineRange=$(match["displayLineRange"]) sourceLocatorHint=$(match["sourceLocatorHint"]) read=$(match["read"])",
        )
    end
    if code
        push!(
            lines,
            "|note kind=asp-owned-source message=\"exact source projection is owned by ASP; compact provider output keeps structural selectors only\"",
        )
    end
    for candidate in packet.candidateItems
        term = haskey(candidate, "term") ? candidate["term"] : "-"
        push!(lines, "|candidate $(candidate["name"]) reason=$(candidate["reason"]) term=$(term)")
    end
    for note in packet.notes
        push!(lines, "|note kind=$(note.kind) message=\"$(compact_cli_value(note.message))\"")
    end
    join(lines, "\n") * "\n"
end
