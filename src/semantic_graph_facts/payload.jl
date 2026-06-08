"""Assemble semantic graph packet payloads and package bridge edges."""

function julia_semantic_graph_payload(
    project_root::AbstractString,
    query::AbstractString,
    facts::Vector{Dict{String,Any}},
)
    nodes = Dict{String,Any}[]
    edges = Dict{String,String}[]
    collection_ids = Set{String}()
    query_text = strip(String(query))
    for fact in facts
        field_id = julia_semantic_graph_field_id(fact)
        type_id = julia_semantic_graph_type_id(fact)
        locator = "$(fact["path"]):$(fact["line"]):$(fact["line"])"
        fields = julia_semantic_graph_node_fields(fact)
        push!(nodes, julia_semantic_graph_field_node(fact, field_id, locator, fields))
        push!(nodes, julia_semantic_graph_type_node(fact, type_id, locator, fields))
        push!(edges, Dict("source" => field_id, "target" => type_id, "relation" => "has_type"))
        julia_semantic_graph_append_collection!(
            nodes,
            edges,
            collection_ids,
            fact,
            field_id,
            type_id,
        )
        if !isempty(query_text)
            push!(
                edges,
                Dict(
                    "source" => julia_semantic_graph_stable_id("query", query_text),
                    "target" => field_id,
                    "relation" => "matches",
                ),
            )
        end
    end
    project_payload = julia_semantic_graph_project_payload(project_root)
    package_bridge_edges =
        julia_semantic_graph_package_bridge_edges(nodes, project_payload.nodes)
    Dict(
        "schemaId" => "agent.semantic-protocols.semantic-fact-graph",
        "schemaVersion" => "1",
        "protocolId" => "agent.semantic-protocols.semantic-language",
        "protocolVersion" => "1",
        "languageId" => JULIA_INDEX_EXPORT_LANGUAGE_ID,
        "providerId" => JULIA_INDEX_EXPORT_PROVIDER_ID,
        "projectRoot" => replace(abspath(String(project_root)), '\\' => '/'),
        "query" => String(query),
        "nodes" => vcat(nodes, project_payload.nodes),
        "edges" => vcat(edges, project_payload.edges, package_bridge_edges),
    )
end

function julia_semantic_graph_package_bridge_edges(
    nodes::Vector{Dict{String,Any}},
    project_nodes::Vector{Dict{String,Any}},
)
    package_node = findfirst(node -> get(node, "kind", nothing) == "package", project_nodes)
    isnothing(package_node) && return Dict{String,String}[]
    package_id = String(project_nodes[package_node]["id"])
    [
        Dict("source" => String(node["id"]), "target" => package_id, "relation" => "belongs_to")
        for node in nodes
        if get(node, "kind", nothing) in ("field", "hot", "owner") && haskey(node, "id")
    ]
end
