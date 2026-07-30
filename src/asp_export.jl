const JULIA_INDEX_EXPORT_SCHEMA_ID = "agent.semantic-protocols.semantic-native-syntax-fact-index"
const JULIA_INDEX_EXPORT_SCHEMA_VERSION = "1"
const JULIA_INDEX_EXPORT_PROTOCOL_ID = "agent.semantic-protocols.semantic-language"
const JULIA_INDEX_EXPORT_PROTOCOL_VERSION = "1"
const JULIA_INDEX_EXPORT_LANGUAGE_ID = "julia"
const JULIA_INDEX_EXPORT_PROVIDER_ID = "julia-lang-project-harness"

const JULIA_INDEX_FACT_KIND_MAP = Dict(
    "module" => "module",
    "owner" => "owner",
    "function" => "function",
    "method" => "method",
    "struct" => "struct",
    "type" => "type",
    "using" => "import",
    "import" => "import",
    "export" => "export",
    "argument" => "argument",
    "binding" => "binding",
    "call" => "call",
    "const" => "constant",
    "doc" => "doc",
    "field" => "field",
    "include" => "include",
    "moshi" => "macro",
    "test" => "test",
    "test_skip" => "test",
    "test_throws" => "test",
    "testset" => "test",
)

const JULIA_INDEX_MANIFEST_KINDS = Set(["moshi_extension"])
const JULIA_INDEX_POLICY_KINDS = Set(["verification"])
const JULIA_INDEX_ITEM_KINDS = Set(["identifier"])

function asp_project_path(path::AbstractString, project_root::AbstractString)
    root = abspath(String(project_root))
    absolute_path = abspath(String(path))
    relative_path = if absolute_path == root || startswith(absolute_path, root * Base.Filesystem.path_separator)
        relpath(absolute_path, root)
    else
        "external/$(basename(absolute_path))"
    end
    normalized_owner_path(relative_path)
end

function asp_location_row(location::SourceLocation, project_root::AbstractString)
    line = max(1, location.line)
    Dict(
        "path" => asp_project_path(location.path, project_root),
        "lineRange" => "$(line):$(line)",
    )
end

function asp_fact_kind(entry::JuliaSearchIndexEntry)
    kind = String(entry.kind)
    haskey(JULIA_INDEX_FACT_KIND_MAP, kind) && return JULIA_INDEX_FACT_KIND_MAP[kind]
    kind in JULIA_INDEX_ITEM_KINDS && return "item"
    "custom"
end

function asp_fact_source(entry::JuliaSearchIndexEntry)
    kind = String(entry.kind)
    kind in JULIA_INDEX_MANIFEST_KINDS && return "manifest"
    kind in JULIA_INDEX_POLICY_KINDS && return "provider-policy"
    "test" in entry.tags && return "test-index"
    "native-parser"
end

function asp_query_keys(
    entry::JuliaSearchIndexEntry,
    owner_path::AbstractString,
    qualified_name::AbstractString,
)
    keys = String[]
    for value in vcat(
        [entry.name, qualified_name, entry.kind, asp_fact_kind(entry), owner_path],
        entry.tags,
    )
        text = String(value)
        isempty(text) || push!(keys, text)
    end
    unique(keys)
end

function asp_fact_id(entry::JuliaSearchIndexEntry, owner_path::AbstractString)
    line = max(1, entry.location.line)
    column = max(0, entry.location.column)
    join(["julia", owner_path, string(line), string(column), String(entry.kind), String(entry.name)], ":")
end

function asp_qualified_name(entry::JuliaSearchIndexEntry, owner_path::AbstractString)
    "$(owner_path)::$(String(entry.name))"
end

function asp_entry_relations(entry::JuliaSearchIndexEntry, owner_path::AbstractString)
    kind = String(entry.kind)
    relations = Dict{String,Any}[]
    kind != "owner" && push!(
        relations,
        Dict{String,Any}(
            "kind" => "related",
            "target" => "owner:$(owner_path)",
            "fields" => Dict("role" => "owner"),
        ),
    )
    if kind in ("using", "import")
        push!(relations, Dict{String,Any}("kind" => "imports", "target" => String(entry.name)))
    elseif kind == "export"
        push!(relations, Dict{String,Any}("kind" => "exports", "target" => String(entry.name)))
    elseif kind == "call"
        push!(relations, Dict{String,Any}("kind" => "calls", "target" => String(entry.name)))
    elseif kind == "include"
        push!(relations, Dict{String,Any}("kind" => "references", "target" => String(entry.name)))
    elseif startswith(kind, "test")
        push!(relations, Dict{String,Any}("kind" => "tests", "target" => owner_path))
    end
    relations
end

function asp_search_index_fact(
    entry::JuliaSearchIndexEntry,
    project_root::AbstractString,
)::Dict{String,Any}
    owner_path = search_entry_owner_path(entry, project_root)
    qualified_name = asp_qualified_name(entry, owner_path)
    relations = asp_entry_relations(entry, owner_path)
    fact = Dict{String,Any}(
        "id" => asp_fact_id(entry, owner_path),
        "kind" => asp_fact_kind(entry),
        "source" => asp_fact_source(entry),
        "languageKind" => String(entry.kind),
        "name" => String(entry.name),
        "qualifiedName" => qualified_name,
        "ownerPath" => owner_path,
        "location" => asp_location_row(entry.location, project_root),
        "visibility" => "public" in entry.tags ? "public" : "unknown",
        "exported" => "public" in entry.tags || String(entry.kind) == "export",
        "test" => "test" in entry.tags || is_julia_test_path(owner_path),
        "queryKeys" => asp_query_keys(entry, owner_path, qualified_name),
        "fields" => Dict(
            "juliaKind" => String(entry.kind),
            "detail" => String(entry.detail),
            "searchText" => String(entry.search_text),
            "tags" => String.(entry.tags),
            "column" => entry.location.column,
        ),
    )
    isempty(relations) || (fact["relations"] = relations)
    fact
end

function asp_index_descriptors(facts::Vector{Dict{String,Any}})
    fact_kinds = isempty(facts) ? ["custom"] : sort!(unique(String(fact["kind"]) for fact in facts))
    Dict{String,Any}[
        Dict{String,Any}(
            "name" => "julia",
            "factKinds" => fact_kinds,
            "queryKeys" => ["name", "languageKind", "tags", "searchText"],
            "fields" => Dict("authority" => "JuliaSyntax"),
        ),
        Dict{String,Any}(
            "name" => "owners",
            "factKinds" => ["owner"],
            "queryKeys" => ["ownerPath", "name"],
        ),
        Dict{String,Any}(
            "name" => "public-api",
            "factKinds" => ["export", "function", "struct", "type"],
            "queryKeys" => ["name", "qualifiedName", "ownerPath"],
        ),
        Dict{String,Any}(
            "name" => "dependencies",
            "factKinds" => ["import", "call", "dependency-api"],
            "queryKeys" => ["name", "qualifiedName", "languageKind"],
        ),
        Dict{String,Any}(
            "name" => "tests",
            "factKinds" => ["test"],
            "queryKeys" => ["name", "ownerPath", "languageKind"],
        ),
    ]
end

"""Build a main-schema native syntax fact index packet for ASP caches."""
function julia_index_export_packet(project_root::AbstractString)
    root = abspath(String(project_root))
    config = default_julia_harness_config()
    scope = julia_project_harness_scope(root, config)
    entries = julia_project_search_index(root; config)
    facts = [asp_search_index_fact(entry, root) for entry in entries]
    Dict(
        "schemaId" => JULIA_INDEX_EXPORT_SCHEMA_ID,
        "schemaVersion" => JULIA_INDEX_EXPORT_SCHEMA_VERSION,
        "protocolId" => JULIA_INDEX_EXPORT_PROTOCOL_ID,
        "protocolVersion" => JULIA_INDEX_EXPORT_PROTOCOL_VERSION,
        "languageId" => JULIA_INDEX_EXPORT_LANGUAGE_ID,
        "providerId" => JULIA_INDEX_EXPORT_PROVIDER_ID,
        "projectRoot" => root,
        "packageName" => something(scope.package_name, basename(root)),
        "scope" => "workspace",
        "facts" => facts,
        "indexes" => asp_index_descriptors(facts),
        "notes" => [
            Dict(
                "kind" => "julia-syntax-authority",
                "message" => "Facts are derived from JuliaSyntax-backed JuliaLangProjectHarness search entries.",
            ),
        ],
    )
end

"""Render the ASP Julia index export packet as one JSON document."""
function render_julia_index_export_json(project_root::AbstractString)
    JSON.json(julia_index_export_packet(project_root))
end

"""Run the agent-facing `export index` CLI used by ASP cache refreshes.

Requires `args[1] == "index"` when arguments are provided, and throws an
`ErrorException` for missing or unknown export views.
"""
function run_julia_harness_export_cli(args::Vector{String}; out::IO=stdout)
    isempty(args) && error("export requires a view")
    view = first(args)
    if view == "index"
        project_root = length(args) >= 2 ? args[2] : pwd()
        print(out, render_julia_index_export_json(project_root))
        print(out, "\n")
        return 0
    end
    error("unknown export view: $(view)")
end
