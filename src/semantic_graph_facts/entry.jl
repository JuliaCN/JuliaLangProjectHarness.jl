"""Render semantic graph packets from parser-owned field/type facts."""

"""Render parser-owned field/type collection facts as a semantic graph JSON packet."""
function render_julia_semantic_graph_facts_json(
    project_root::AbstractString,
    query::AbstractString,
    stdin_text::AbstractString,
)
    JSON.json(julia_semantic_graph_facts_packet(project_root, query, stdin_text))
end

function julia_semantic_graph_facts_packet(
    project_root::AbstractString,
    query::AbstractString,
    stdin_text::AbstractString,
)
    facts = julia_located_semantic_graph_field_facts(project_root, stdin_text)
    matched = [fact for fact in facts if julia_semantic_graph_fact_matches_query(fact, query)]
    julia_semantic_graph_payload(project_root, query, matched[1:min(length(matched), 64)])
end
