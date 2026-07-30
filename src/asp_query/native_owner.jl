const JuliaNativeQueryMatch = @NamedTuple begin
    name::String
    kind::String
    location::JuliaQueryLocation
    truncated::Bool
end

const JuliaNativeOwnerItemsQueryPacket = @NamedTuple begin
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
    ownerPath::String
    query::String
    queryTerms::Vector{String}
    matches::Vector{JuliaNativeQueryMatch}
    truncated::Bool
end

"""Render parser-owned Julia owner-items lookup as a typed native JSON packet.

Returns a concrete `String` so the native CLI can write a single stable JSON
payload without retaining JSON object wrappers. Throws `ErrorException` when
the normalized query term list is empty.
"""
function render_julia_native_owner_items_query_json(
    owner_path::String,
    query_terms::Vector{String},
    project_root::String,
)::String
    root = abspath(project_root)
    owner = normalized_owner_path(owner_path)
    terms = julia_query_terms(query_terms)
    isempty(terms) && error("query/owner-items requires --term or --query")
    entries = julia_query_owner_entries(owner, root)
    matched_pairs = julia_query_matching_entries(entries, terms, owner)
    selected_pairs = matched_pairs[1:min(length(matched_pairs), 25)]
    matches = JuliaNativeQueryMatch[]
    sizehint!(matches, length(selected_pairs))
    for pair in selected_pairs
        entry = pair.first
        push!(
            matches,
            JuliaNativeQueryMatch((
                String(entry.name),
                String(entry.kind),
                JuliaQueryLocation(owner, "$(entry.location.line):$(entry.location.line)"),
                false,
            )),
        )
    end
    packet = JuliaNativeOwnerItemsQueryPacket((
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
        owner,
        join(terms, "|"),
        terms,
        matches,
        length(matched_pairs) > length(matches),
    ))
    return JSON.json(packet)
end

"""Run the native Julia owner-items CLI route and emit exactly one JSON packet.

Returns the concrete process status `Int(0)` after the packet and terminating
newline have been written to `out`.
"""
function run_julia_native_owner_items_query_cli(
    owner_path::String,
    query_terms::Vector{String},
    project_root::String,
    out::IO,
)::Int
    rendered =
        render_julia_native_owner_items_query_json(owner_path, query_terms, project_root)
    print(out, rendered)
    print(out, '\n')
    return 0
end
