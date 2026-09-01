function render_julia_search_packet_json(
    view::AbstractString;
    project_root::AbstractString,
    render_mode::AbstractString="seeds",
    query::Union{Nothing,AbstractString}=nothing,
    query_set::Vector{String}=String[],
    owner_path::Union{Nothing,AbstractString}=nothing,
    stdin_text::AbstractString="",
    selector::Union{Nothing,AbstractString}=nothing,
    terms::Vector{String}=String[],
    pipes::Vector{String}=String[],
    from_hook::Union{Nothing,AbstractString}=nothing,
    intent::Union{Nothing,AbstractString}=nothing,
)
    packet = if view == "workspace"
        julia_workspace_search_packet(project_root; render_mode)
    elseif view == "prime"
        julia_prime_search_packet(project_root; render_mode)
    elseif view == "owner"
        isnothing(owner_path) && error("search owner JSON requires an owner path")
        julia_owner_search_packet(owner_path, project_root; render_mode)
    elseif view == "lexical"
        isnothing(query) && error("search lexical JSON requires a query")
        packet = julia_lexical_search_packet(query, project_root; render_mode)
        if !isempty(query_set)
            packet["querySet"] = [
                Dict{String,Any}("value" => term, "kind" => "text", "selector" => "fuzzy")
                for term in query_set
            ]
        end
        packet
    elseif view == "deps"
        isnothing(query) && error("search deps JSON requires a dependency query")
        julia_dependency_search_packet(query, project_root; render_mode)
    elseif view in ["env", "runtime-source", "lang", "std", "capability", "extension", "pattern", "compare"]
        julia_knowledge_search_packet(view, isnothing(query) ? String[] : String.(split(String(query))), project_root; render_mode)
    elseif view == "ingest"
        julia_ingest_search_packet(stdin_text, project_root; render_mode)
    elseif view == "policy"
        isnothing(query) && error("search policy JSON requires a query")
        julia_policy_search_packet(query, project_root; render_mode)
    elseif view == "query"
        isnothing(selector) && error("search query JSON requires a selector")
        isempty(terms) && error("search query JSON requires terms")
        julia_search_query_packet(
            selector,
            terms,
            pipes,
            project_root;
            render_mode,
            from_hook=something(from_hook, "direct-source-read"),
            intent,
        )
    else
        error("unknown search JSON view: $(view)")
    end
    JSON.json(packet)
end

const JuliaNativeLexicalHeaderFields = @NamedTuple begin
    view::String
    provider::String
    query::String
end

const JuliaNativeLexicalHeader = @NamedTuple begin
    kind::String
    fields::JuliaNativeLexicalHeaderFields
end

const JuliaNativeLexicalQueryTerm = @NamedTuple begin
    value::String
    kind::String
    selector::String
end

const JuliaNativeLexicalHit = @NamedTuple begin
    kind::String
    ownerPath::String
    location::JuliaQueryLocation
    score::Float64
    reason::String
    symbol::String
end

const JuliaNativeLexicalPacket = @NamedTuple begin
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
    view::String
    renderMode::String
    header::JuliaNativeLexicalHeader
    nodes::Vector{JuliaNativeEmptySearchRow}
    edges::Vector{JuliaNativeEmptySearchRow}
    owners::Vector{JuliaNativeEmptySearchRow}
    hits::Vector{JuliaNativeLexicalHit}
    findings::Vector{JuliaNativeEmptySearchRow}
    nextActions::Vector{JuliaNativeEmptySearchRow}
    notes::Vector{JuliaNativeEmptySearchRow}
    query::String
    querySet::Vector{JuliaNativeLexicalQueryTerm}
end

const JuliaNativePrimeHeaderFields = @NamedTuple begin
    view::String
    provider::String
end

const JuliaNativePrimeHeader = @NamedTuple begin
    kind::String
    fields::JuliaNativePrimeHeaderFields
end

const JuliaNativePrimePacket = @NamedTuple begin
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
    view::String
    renderMode::String
    header::JuliaNativePrimeHeader
    nodes::Vector{JuliaNativeEmptySearchRow}
    edges::Vector{JuliaNativeEmptySearchRow}
    owners::Vector{JuliaNativeEmptySearchRow}
    hits::Vector{JuliaNativeLexicalHit}
    findings::Vector{JuliaNativeEmptySearchRow}
    nextActions::Vector{JuliaNativeEmptySearchRow}
    notes::Vector{JuliaNativeEmptySearchRow}
end

function render_julia_native_prime_packet_json(
    project_root::String,
    render_mode::String,
)::String
    root = abspath(project_root)
    entries = julia_project_search_index(root)
    selected_entries = entries[1:min(length(entries), 24)]
    hits = JuliaNativeLexicalHit[]
    sizehint!(hits, length(selected_entries))
    for entry in selected_entries
        owner = search_entry_owner_path(entry, root)
        push!(
            hits,
            JuliaNativeLexicalHit((
                String(entry.kind),
                owner,
                JuliaQueryLocation(owner, "$(entry.location.line):$(entry.location.line)"),
                1.0,
                "prime",
                String(entry.name),
            )),
        )
    end
    packet = JuliaNativePrimePacket((
        JULIA_SEARCH_PACKET_SCHEMA_ID,
        JULIA_SEARCH_PACKET_SCHEMA_VERSION,
        JULIA_INDEX_EXPORT_PROTOCOL_ID,
        JULIA_INDEX_EXPORT_PROTOCOL_VERSION,
        JULIA_INDEX_EXPORT_LANGUAGE_ID,
        JULIA_INDEX_EXPORT_PROVIDER_ID,
        JULIA_AGENT_BINARY,
        JULIA_AGENT_PROVIDER_NAMESPACE,
        "search/prime",
        root,
        "prime",
        render_mode,
        JuliaNativePrimeHeader((
            "search-prime",
            JuliaNativePrimeHeaderFields(("prime", JULIA_INDEX_EXPORT_PROVIDER_ID)),
        )),
        JuliaNativeEmptySearchRow[],
        JuliaNativeEmptySearchRow[],
        JuliaNativeEmptySearchRow[],
        hits,
        JuliaNativeEmptySearchRow[],
        JuliaNativeEmptySearchRow[],
        JuliaNativeEmptySearchRow[],
    ))
    return JSON.json(packet)
end

function render_julia_native_lexical_packet_json(
    query::String,
    query_set::Vector{String},
    project_root::String,
    render_mode::String,
)::String
    root = abspath(project_root)
    results = search_julia_project(root, query; limit=16)
    hits = JuliaNativeLexicalHit[]
    sizehint!(hits, length(results))
    for result in results
        entry = result.entry
        owner = search_entry_owner_path(entry, root)
        push!(
            hits,
            JuliaNativeLexicalHit((
                String(entry.kind),
                owner,
                JuliaQueryLocation(owner, "$(entry.location.line):$(entry.location.line)"),
                Float64(result.score),
                "lexical",
                String(entry.name),
            )),
        )
    end
    terms = JuliaNativeLexicalQueryTerm[
        JuliaNativeLexicalQueryTerm((term, "text", "fuzzy")) for term in query_set
    ]
    packet = JuliaNativeLexicalPacket((
        JULIA_SEARCH_PACKET_SCHEMA_ID,
        JULIA_SEARCH_PACKET_SCHEMA_VERSION,
        JULIA_INDEX_EXPORT_PROTOCOL_ID,
        JULIA_INDEX_EXPORT_PROTOCOL_VERSION,
        JULIA_INDEX_EXPORT_LANGUAGE_ID,
        JULIA_INDEX_EXPORT_PROVIDER_ID,
        JULIA_AGENT_BINARY,
        JULIA_AGENT_PROVIDER_NAMESPACE,
        "search/lexical",
        root,
        "lexical",
        render_mode,
        JuliaNativeLexicalHeader((
            "search-lexical",
            JuliaNativeLexicalHeaderFields((
                "lexical",
                JULIA_INDEX_EXPORT_PROVIDER_ID,
                query,
            )),
        )),
        JuliaNativeEmptySearchRow[],
        JuliaNativeEmptySearchRow[],
        JuliaNativeEmptySearchRow[],
        hits,
        JuliaNativeEmptySearchRow[],
        JuliaNativeEmptySearchRow[],
        JuliaNativeEmptySearchRow[],
        query,
        terms,
    ))
    return JSON.json(packet)
end

function semantic_agent_protocol_binary()
    get(ENV, "SEMANTIC_AGENT_PROTOCOL_BIN", "asp")
end

function render_julia_fast_search_packet_json(view::AbstractString; kwargs...)
    packet = julia_fast_search_packet(view; kwargs...)
    isnothing(packet) ? nothing : JSON.json(packet)
end

function julia_fast_search_packet(
    view::AbstractString;
    project_root::AbstractString,
    render_mode::AbstractString="seeds",
    query::Union{Nothing,AbstractString}=nothing,
    query_set::Vector{String}=String[],
    owner_path::Union{Nothing,AbstractString}=nothing,
    kwargs...,
)
    render_mode == "seeds" || return nothing
    if view == "workspace"
        return julia_fast_workspace_search_packet(project_root; render_mode)
    elseif view == "prime"
        return julia_fast_prime_search_packet(project_root; render_mode)
    elseif view == "owner"
        isnothing(owner_path) && error("search owner requires an owner path")
        return julia_fast_owner_search_packet(owner_path, project_root; render_mode)
    elseif view == "lexical"
        isnothing(query) && error("search lexical requires a query")
        return julia_fast_lexical_search_packet(query, project_root; render_mode, query_set)
    elseif view == "deps"
        isnothing(query) && error("search deps requires a dependency query")
        return julia_fast_dependency_search_packet(query, project_root; render_mode)
    end
    nothing
end

include("graph_render.jl")
