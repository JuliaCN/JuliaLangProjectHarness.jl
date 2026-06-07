"""JuliaSyntax-backed graph-turbo provider facts for field/type structure."""

"""Render parser-owned field/type collection facts as a semantic graph JSON packet."""
function render_julia_semantic_graph_facts_json(
    project_root::AbstractString,
    query::AbstractString,
    stdin_text::AbstractString,
)
    JSON3.write(julia_semantic_graph_facts_packet(project_root, query, stdin_text))
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

function julia_located_semantic_graph_field_facts(
    project_root::AbstractString,
    stdin_text::AbstractString,
)
    root = abspath(String(project_root))
    facts = Dict{String,Any}[]
    for path in julia_semantic_graph_candidate_files(root, stdin_text)
        parsed = parse_julia_file(path)
        parsed.report.is_valid || continue
        owner_path = asp_project_path(path, root)
        for type_fact in parsed.syntax_facts.types
            for field_fact in type_fact.field_facts
                push!(
                    facts,
                    julia_semantic_graph_field_fact(owner_path, type_fact, field_fact),
                )
            end
        end
    end
    facts
end

function julia_semantic_graph_candidate_files(root::AbstractString, stdin_text::AbstractString)
    candidates = String[]
    for candidate in julia_semantic_graph_candidate_paths(stdin_text)
        absolute = isabspath(candidate) ? candidate : joinpath(root, candidate)
        isfile(absolute) && endswith(lowercase(absolute), ".jl") && push!(candidates, abspath(absolute))
    end
    if isempty(candidates)
        config = default_julia_harness_config()
        scope = julia_project_harness_scope(root, config)
        workspace_member_scopes = julia_workspace_member_scopes(scope, config)
        monitored_paths = vcat(
            scope_search_paths(scope),
            mapreduce(scope_search_paths, vcat, workspace_member_scopes; init=String[]),
        )
        append!(candidates, discover_julia_files(monitored_paths, config))
    end
    sort!(unique(abspath.(candidates)))
end

function julia_semantic_graph_candidate_paths(stdin_text::AbstractString)
    paths = String[]
    for line in split(String(stdin_text), '\n')
        matched = match(r"^(.+?):\d+(?::\d+)?:", strip(line))
        isnothing(matched) || push!(paths, String(matched.captures[1]))
    end
    paths
end

function julia_semantic_graph_field_fact(
    owner_path::AbstractString,
    type_fact::JuliaTypeSyntax,
    field_fact::JuliaTypeFieldSyntax,
)
    type_value = something(field_fact.type_annotation, "Any")
    context_end_line = julia_semantic_graph_end_line(type_fact.line, type_fact.expression)
    collection_kind = julia_semantic_graph_collection_kind(type_value)
    fact = Dict{String,Any}(
        "path" => String(owner_path),
        "containerKind" => julia_semantic_graph_container_kind(type_fact),
        "containerName" => type_fact.name,
        "fieldName" => field_fact.name,
        "typeValue" => type_value,
        "line" => field_fact.line,
        "contextStartLine" => type_fact.line,
        "contextEndLine" => context_end_line,
        "mutable" => type_fact.is_mutable,
        "parameters" => type_fact.parameters,
    )
    isnothing(type_fact.supertype) || (fact["supertype"] = type_fact.supertype)
    isnothing(collection_kind) || (fact["collectionKind"] = collection_kind)
    fact
end

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

function julia_semantic_graph_fact_matches_query(fact::Dict{String,Any}, query::AbstractString)
    terms = julia_semantic_graph_query_terms(query)
    isempty(terms) && return true
    shape_terms = Set(["field", "fields", "type", "types", "collection", "collections", "scalar", "scalars"])
    collection_terms = Set([
        "array",
        "arrays",
        "vector",
        "vectors",
        "list",
        "lists",
        "map",
        "maps",
        "dict",
        "dicts",
        "dictionary",
        "dictionaries",
        "set",
        "sets",
        "tuple",
        "tuples",
        "record",
        "records",
        "namedtuple",
        "namedtuples",
    ])
    haystack = lowercase(join([
        fact["path"],
        fact["containerKind"],
        fact["containerName"],
        fact["fieldName"],
        fact["typeValue"],
        get(fact, "collectionKind", ""),
    ], " "))
    text_terms = [term for term in terms if !(term in shape_terms) && !(term in collection_terms)]
    if !isempty(text_terms) && !any(term -> occursin(term, haystack), text_terms)
        return false
    end
    if any(term -> term in ("collection", "collections"), terms)
        return haskey(fact, "collectionKind")
    end
    if any(term -> term in ("scalar", "scalars"), terms)
        return !haskey(fact, "collectionKind")
    end
    all(term -> julia_semantic_graph_collection_term_matches(term, get(fact, "collectionKind", nothing)), terms)
end

function julia_semantic_graph_collection_term_matches(term::AbstractString, collection_kind)
    term in ("array", "arrays", "vector", "vectors", "list", "lists") &&
        return collection_kind == "array"
    term in ("map", "maps", "dict", "dicts", "dictionary", "dictionaries") &&
        return collection_kind == "map"
    term in ("set", "sets") && return collection_kind == "set"
    term in ("tuple", "tuples") && return collection_kind == "tuple"
    term in ("record", "records", "namedtuple", "namedtuples") && return collection_kind == "record"
    true
end

function julia_semantic_graph_collection_kind(type_value::AbstractString)
    head = julia_semantic_graph_type_symbol(type_value)
    head in ("Array", "Base.Array", "Vector", "Base.Vector", "AbstractArray", "AbstractVector", "SubArray") &&
        return "array"
    head in ("Dict", "Base.Dict", "IdDict", "WeakKeyDict", "AbstractDict") && return "map"
    head in ("Set", "Base.Set", "BitSet", "AbstractSet") && return "set"
    head in ("Tuple", "Base.Tuple") && return "tuple"
    head in ("NamedTuple", "Base.NamedTuple") && return "record"
    nothing
end

function julia_semantic_graph_container_kind(type_fact::JuliaTypeSyntax)
    type_fact.kind == "struct" && type_fact.is_mutable && return "mutable-struct"
    type_fact.kind
end

function julia_semantic_graph_end_line(start_line::Int, expression::AbstractString)
    start_line + count(==('\n'), String(expression))
end

function julia_semantic_graph_field_id(fact::Dict{String,Any})
    julia_semantic_graph_stable_id(
        "field",
        "$(fact["path"]):$(fact["containerKind"]):$(fact["containerName"]):$(fact["fieldName"]):$(fact["line"])",
    )
end

function julia_semantic_graph_type_id(fact::Dict{String,Any})
    julia_semantic_graph_stable_id(
        "type",
        "$(fact["path"]):$(fact["fieldName"]):$(fact["typeValue"]):$(fact["line"])",
    )
end

function julia_semantic_graph_type_symbol(type_value::AbstractString)
    stripped = strip(String(type_value))
    matched = match(r"^[A-Za-z_][A-Za-z0-9_.!]*", stripped)
    isnothing(matched) ? stripped : matched.match
end

function julia_semantic_graph_stable_id(kind::AbstractString, value::AbstractString)
    rendered = IOBuffer()
    for character in String(value)
        if isascii(character) && (isletter(character) || isdigit(character) || character in ['/', '.', '_', '-'])
            print(rendered, lowercase(string(character)))
        else
            print(rendered, '-')
        end
    end
    compacted = replace(String(take!(rendered)), r"^-+|-+$" => "")
    "$(String(kind)):$(compacted)"
end

function julia_semantic_graph_query_terms(query::AbstractString)
    [
        term for term in split(lowercase(String(query)), r"[^a-z0-9_]+")
        if !isempty(strip(term))
    ]
end
