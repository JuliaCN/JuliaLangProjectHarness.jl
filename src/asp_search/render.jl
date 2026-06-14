function render_julia_search_packet_json(
    view::AbstractString;
    project_root::AbstractString,
    render_mode::AbstractString="seeds",
    query::Union{Nothing,AbstractString}=nothing,
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
    elseif view == "fzf"
        isnothing(query) && error("search fzf JSON requires a query")
        julia_fzf_search_packet(query, project_root; render_mode)
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
    JSON3.write(packet)
end

function semantic_agent_protocol_binary()
    get(ENV, "SEMANTIC_AGENT_PROTOCOL_BIN", "asp")
end

"""Render a Julia search packet through the shared ASP graph renderer.

Safety contract: the external command is fixed to `asp graph render`, the stdin
payload is provider-owned JSON, and CLI search smoke tests verify the graph
rendering path.
"""
function render_julia_search_graph(view::AbstractString; kwargs...)
    packet_json = render_julia_search_packet_json(view; kwargs...)
    command = `$(semantic_agent_protocol_binary()) graph render --packet - --view seeds`
    try
        read(pipeline(IOBuffer(String(packet_json)), command), String)
    catch error
        error(
            "failed to render Julia search through shared asp graph renderer: " *
            sprint(showerror, error),
        )
    end
end
