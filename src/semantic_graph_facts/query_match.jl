"""Query matching and stable id helpers for semantic graph facts."""

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
