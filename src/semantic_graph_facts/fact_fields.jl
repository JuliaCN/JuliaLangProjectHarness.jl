"""Render semantic graph node field payloads."""

function julia_semantic_graph_field_fact_fields(fact::Dict{String,Any})
    Dict{String,Any}(
        "ownerKind" => julia_semantic_graph_field_owner_kind(String(fact["containerKind"])),
        "name" => fact["fieldName"],
        "ownerPath" => fact["path"],
        "access" => julia_semantic_graph_access_modes(fact),
    )
end

function julia_semantic_graph_type_fact_fields(fact::Dict{String,Any})
    Dict{String,Any}("name" => fact["typeValue"])
end

function julia_semantic_graph_collection_fact_fields(fact::Dict{String,Any})
    collection_kind = get(fact, "collectionKind", nothing)
    Dict{String,Any}(
        "family" => julia_semantic_graph_collection_family(collection_kind),
        "impl" => isnothing(collection_kind) ? "unknown" : String(collection_kind),
        "mutation" => julia_semantic_graph_mutation_modes(collection_kind),
    )
end

function julia_semantic_graph_field_owner_kind(container_kind::AbstractString)
    container_kind == "mutable-struct" && return "struct"
    container_kind == "abstract" && return "object"
    container_kind
end

function julia_semantic_graph_collection_family(collection_kind)
    isnothing(collection_kind) && return nothing
    kind = String(collection_kind)
    kind in ("map", "record") && return "map"
    kind == "set" && return "set"
    "sequence"
end

function julia_semantic_graph_access_modes(fact::Dict{String,Any})
    collection_kind = get(fact, "collectionKind", nothing)
    if isnothing(collection_kind)
        return fact["mutable"] == true ? ["read", "write", "validate"] : ["read", "validate"]
    end
    kind = String(collection_kind)
    kind == "map" && return ["read", "write", "validate"]
    kind in ("record", "tuple") && return ["read", "validate"]
    ["read", "append", "validate"]
end

function julia_semantic_graph_mutation_modes(collection_kind)
    isnothing(collection_kind) && return String[]
    kind = String(collection_kind)
    kind == "array" && return ["append", "insert", "remove"]
    kind == "map" && return ["insert", "update", "remove"]
    kind == "set" && return ["insert", "remove"]
    String[]
end
