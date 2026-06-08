"""Render semantic graph node dictionaries."""

function julia_semantic_graph_node_fields(fact::Dict{String,Any})
    collection_kind = get(fact, "collectionKind", nothing)
    fields = Dict{String,Any}(
        "languageId" => JULIA_INDEX_EXPORT_LANGUAGE_ID,
        "providerId" => JULIA_INDEX_EXPORT_PROVIDER_ID,
        "semanticFactKind" => "field",
        "provenance" => "parser",
        "confidence" => "exact",
        "freshness" => "fresh",
        "containerKind" => fact["containerKind"],
        "containerName" => fact["containerName"],
        "fieldName" => fact["fieldName"],
        "typeValue" => fact["typeValue"],
        "elementShape" => haskey(fact, "collectionKind") ? "collection" : "scalar",
        "contextLocator" => "$(fact["path"]):$(fact["contextStartLine"]):$(fact["contextEndLine"])",
        "contextStartLine" => fact["contextStartLine"],
        "contextEndLine" => fact["contextEndLine"],
        "mutable" => fact["mutable"],
        "parameters" => fact["parameters"],
        "field" => julia_semantic_graph_field_fact_fields(fact),
    )
    haskey(fact, "supertype") && (fields["supertype"] = fact["supertype"])
    if haskey(fact, "collectionKind")
        fields["collectionKind"] = fact["collectionKind"]
        fields["collectionFamily"] = julia_semantic_graph_collection_family(collection_kind)
        fields["collectionImpl"] = fact["collectionKind"]
    end
    fields
end

function julia_semantic_graph_field_node(
    fact::Dict{String,Any},
    field_id::AbstractString,
    locator::AbstractString,
    fields::Dict{String,Any},
)
    Dict{String,Any}(
        "id" => String(field_id),
        "kind" => "field",
        "role" => "$(fact["containerKind"])-field",
        "value" => "$(fact["fieldName"]): $(fact["typeValue"])",
        "action" => "code",
        "path" => fact["path"],
        "ownerPath" => fact["path"],
        "symbol" => fact["fieldName"],
        "startLine" => fact["line"],
        "endLine" => fact["line"],
        "locator" => String(locator),
        "matchText" => "$(fact["containerName"]).$(fact["fieldName"])::$(fact["typeValue"])",
        "fields" => fields,
    )
end

function julia_semantic_graph_type_node(
    fact::Dict{String,Any},
    type_id::AbstractString,
    locator::AbstractString,
    fields::Dict{String,Any},
)
    type_fields = copy(fields)
    delete!(type_fields, "field")
    type_fields["semanticFactKind"] = "type"
    type_fields["type"] = julia_semantic_graph_type_fact_fields(fact)
    Dict{String,Any}(
        "id" => String(type_id),
        "kind" => "type",
        "role" => "field-type",
        "value" => fact["typeValue"],
        "action" => "evidence",
        "path" => fact["path"],
        "ownerPath" => fact["path"],
        "symbol" => julia_semantic_graph_type_symbol(String(fact["typeValue"])),
        "startLine" => fact["line"],
        "endLine" => fact["line"],
        "locator" => String(locator),
        "fields" => type_fields,
    )
end

function julia_semantic_graph_append_collection!(
    nodes::Vector{Dict{String,Any}},
    edges::Vector{Dict{String,String}},
    collection_ids::Set{String},
    fact::Dict{String,Any},
    field_id::AbstractString,
    type_id::AbstractString,
)
    haskey(fact, "collectionKind") || return
    collection_kind = String(fact["collectionKind"])
    collection_id = "collection:$(collection_kind)"
    if !(collection_id in collection_ids)
        push!(collection_ids, collection_id)
        push!(
            nodes,
            Dict{String,Any}(
                "id" => collection_id,
                "kind" => "collection",
                "role" => "family",
                "value" => collection_kind,
                "action" => "evidence",
                "symbol" => collection_kind,
                "fields" => Dict{String,Any}(
                    "languageId" => JULIA_INDEX_EXPORT_LANGUAGE_ID,
                    "providerId" => JULIA_INDEX_EXPORT_PROVIDER_ID,
                    "semanticFactKind" => "collection",
                    "provenance" => "parser",
                    "confidence" => "exact",
                    "freshness" => "fresh",
                    "collectionKind" => collection_kind,
                    "collectionFamily" => julia_semantic_graph_collection_family(collection_kind),
                    "collectionImpl" => collection_kind,
                    "collection" => julia_semantic_graph_collection_fact_fields(fact),
                ),
            ),
        )
    end
    push!(edges, Dict("source" => String(field_id), "target" => collection_id, "relation" => "collection_of"))
    push!(edges, Dict("source" => String(type_id), "target" => collection_id, "relation" => "collection_of"))
end
