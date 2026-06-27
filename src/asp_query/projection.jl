function julia_query_read_locator(location::AbstractDict)
    "$(location["path"]):$(location["lineRange"])"
end

function julia_query_structural_selector(entry::JuliaSearchIndexEntry, location::AbstractDict)
    "julia://$(location["path"])#item/$(entry.kind)/$(entry.name)"
end

function julia_query_node_id(entry::JuliaSearchIndexEntry, owner_path::AbstractString)
    replace(asp_fact_id(entry, owner_path), r"[^a-zA-Z0-9_.:-]+" => "_")
end

function julia_query_projection_role(entry::JuliaSearchIndexEntry)
    kind = String(entry.kind)
    kind in ("function", "method", "struct", "type", "module") && return "declaration"
    kind in ("call", "macro") && return "call"
    kind in ("field", "binding", "const") && return "field"
    return "unknown"
end

function julia_query_projection_flags(entry::JuliaSearchIndexEntry)
    kind = String(entry.kind)
    flags = String[]
    kind == "call" && push!(flags, "call")
    kind in ("binding", "const") && push!(flags, "mutation")
    flags
end

function julia_query_entry_code(entry::JuliaSearchIndexEntry, project_root::AbstractString)
    location = asp_location_row(entry.location, project_root)
    compact = strip(render_julia_query_code_selector(julia_query_read_locator(location), project_root))
    if isempty(compact) || startswith(compact, "#")
        fallback = String(entry.detail)
        isempty(fallback) && (fallback = String(entry.search_text))
        isempty(fallback) && (fallback = "$(entry.kind) $(entry.name)")
        compact = julia_query_compact_code_line(fallback)
    end
    compact
end

function julia_query_projection(entry::JuliaSearchIndexEntry, project_root::AbstractString, read::String)
    owner_path = search_entry_owner_path(entry, project_root)
    code = julia_query_entry_code(entry, project_root)
    Dict{String,Any}(
        "code" => code,
        "projection" => Dict{String,Any}(
            "mode" => "compact",
            "syntax" => "semantic-outline",
            "sourceAuthority" => "native-parser",
            "sourceFingerprint" => "julia:$(read):$(length(code))",
            "losslessStructure" => false,
            "exactRead" => read,
            "nodes" => [
                Dict{String,Any}(
                    "id" => julia_query_node_id(entry, owner_path),
                    "kind" => String(entry.kind),
                    "role" => julia_query_projection_role(entry),
                    "label" => String(entry.name),
                    "depth" => 0,
                    "read" => read,
                    "flags" => julia_query_projection_flags(entry),
                ),
            ],
            "expandActions" => [
                Dict{String,Any}(
                    "kind" => "exact-read",
                    "target" => String(entry.name),
                    "read" => read,
                    "reason" => "read exact source before editing",
                ),
            ],
        ),
    )
end

function julia_query_match_row(
    entry::JuliaSearchIndexEntry,
    project_root::AbstractString;
    include_code::Bool,
)
    location = asp_location_row(entry.location, project_root)
    read = julia_query_read_locator(location)
    structural_selector = julia_query_structural_selector(entry, location)
    row = Dict{String,Any}(
        "name" => String(entry.name),
        "kind" => String(entry.kind),
        "visibility" => "public" in entry.tags ? "public" : "unknown",
        "doc" => String(entry.kind) == "doc",
        "location" => location,
        "structuralSelector" => structural_selector,
        "displayLineRange" => location["lineRange"],
        "sourceLocatorHint" => read,
        "read" => read,
        "truncated" => false,
        "fields" => Dict{String,Any}(
            "juliaKind" => String(entry.kind),
            "portableKind" => asp_fact_kind(entry),
            "structuralSelector" => structural_selector,
            "displayLineRange" => location["lineRange"],
            "sourceLocatorHint" => read,
        ),
    )
    include_code && merge!(row, julia_query_projection(entry, project_root, read))
    row
end
