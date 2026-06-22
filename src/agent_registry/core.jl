const JULIA_AGENT_REGISTRY_ID = "agent.semantic-protocols.semantic-language-registry"
const JULIA_AGENT_REGISTRY_VERSION = "1"
const JULIA_AGENT_REGISTRY_PROTOCOL_ID = "agent.semantic-protocols.semantic-language"
const JULIA_AGENT_REGISTRY_PROTOCOL_VERSION = "1"
const JULIA_AGENT_PROVIDER_NAMESPACE =
    "agent.semantic-protocols.languages.julia.julia-lang-project-harness"
const JULIA_AGENT_BINARY = "asp-julia-harness"

const JULIA_AGENT_SCHEMA_FILES = [
    ("semantic-graph.v1.schema.json", "agent.semantic-protocols.semantic-graph"),
    ("semantic-graph-turbo-request.v1.schema.json", "agent.semantic-protocols.semantic-graph-turbo-request"),
    ("semantic-fact-graph.v1.schema.json", "agent.semantic-protocols.semantic-fact-graph"),
    ("semantic-fact-ontology.v1.schema.json", "agent.semantic-protocols.semantic-fact-ontology"),
    ("semantic-search-packet.v1.schema.json", "agent.semantic-protocols.semantic-search-packet"),
    ("semantic-dependency-topology.v1.schema.json", "agent.semantic-protocols.semantic-dependency-topology"),
    ("semantic-type-surface.v1.schema.json", "agent.semantic-protocols.semantic-type-surface"),
    ("semantic-query-packet.v1.schema.json", "agent.semantic-protocols.semantic-query-packet"),
    ("semantic-content-compaction.v1.schema.json", "agent.semantic-protocols.semantic-content-compaction"),
    ("semantic-read-packet.v1.schema.json", "agent.semantic-protocols.semantic-read-packet"),
    ("semantic-source-location.v1.schema.json", "agent.semantic-protocols.semantic-source-location"),
    ("semantic-tree-sitter-provenance.v1.schema.json", "agent.semantic-protocols.semantic-tree-sitter-provenance"),
    ("semantic-tree-sitter-query.v1.schema.json", "agent.semantic-protocols.semantic-tree-sitter-query"),
    ("semantic-tree-sitter-grammar-profile.v1.schema.json", "agent.semantic-protocols.semantic-tree-sitter-grammar-profile"),
    ("semantic-relation-plan.v1.schema.json", "agent.semantic-protocols.semantic-relation-plan"),
    ("semantic-flow-lite.v1.schema.json", "agent.semantic-protocols.semantic-flow-lite"),
    ("semantic-codeql-evidence.v1.schema.json", "agent.semantic-protocols.semantic-codeql-evidence"),
    ("semantic-handle.v1.schema.json", "agent.semantic-protocols.semantic-handle"),
    ("semantic-structural-index.v1.schema.json", "agent.semantic-protocols.semantic-structural-index"),
    ("semantic-language-registry.v1.schema.json", "agent.semantic-protocols.semantic-language-registry"),
    ("semantic-native-syntax-fact-index.v1.schema.json", "agent.semantic-protocols.semantic-native-syntax-fact-index"),
    ("semantic-verification-receipt.v1.schema.json", "agent.semantic-protocols.semantic-verification-receipt"),
    ("semantic-behavior-snapshot.v1.schema.json", "agent.semantic-protocols.semantic-behavior-snapshot"),
    ("semantic-determinism-readiness.v1.schema.json", "agent.semantic-protocols.semantic-determinism-readiness"),
    ("semantic-dev-command-log.v1.schema.json", "agent.semantic-protocols.semantic-dev-command-log"),
    ("semantic-formal-proof-pilot.v1.schema.json", "agent.semantic-protocols.semantic-formal-proof-pilot"),
    ("semantic-review-packet.v1.schema.json", "agent.semantic-protocols.semantic-review-packet"),
    ("semantic-evidence-graph.v1.schema.json", "agent.semantic-protocols.semantic-evidence-graph"),
    ("semantic-assurance-case.v1.schema.json", "agent.semantic-protocols.semantic-assurance-case"),
    ("semantic-ast-patch.v1.schema.json", "agent.semantic-protocols.semantic-ast-patch"),
    ("semantic-ast-patch-receipt.v1.schema.json", "agent.semantic-protocols.semantic-ast-patch-receipt"),
    ("software-criterion-catalog.v1.schema.json", "agent.semantic-protocols.software-criterion-catalog"),
]

function julia_agent_capability(name::AbstractString; namespace::AbstractString="julia")
    Dict(
        "languageId" => JULIA_INDEX_EXPORT_LANGUAGE_ID,
        "namespace" => String(namespace),
        "name" => String(name),
    )
end

function julia_search_method_descriptor(
    method::AbstractString,
    view::AbstractString;
    requires_query::Bool,
    accepts_stdin::Bool=false,
    supports_json::Bool=true,
    supports_compact::Bool=true,
    output_schema_ids::Vector{String}=["agent.semantic-protocols.semantic-search-packet"],
    output_modes::Vector{String}=String[],
    packet_schemas::Vector{String}=String[],
    accepted_pipes::Vector{String}=String[],
    required_options::Vector{String}=String[],
    supports_query_set::Bool=false,
    accepted_query_set_selectors::Vector{String}=String[],
    capabilities::Vector{Dict{String,String}}=Dict{String,String}[],
)
    descriptor = Dict{String,Any}(
        "method" => String(method),
        "command" => "search",
        "view" => String(view),
        "outputSchemaIds" => output_schema_ids,
        "requiresQuery" => requires_query,
        "acceptsStdin" => accepts_stdin,
        "supportsPackageScope" => true,
        "supportsCompact" => supports_compact,
        "supportsJson" => supports_json,
    )
    isempty(output_modes) || (descriptor["outputModes"] = output_modes)
    isempty(packet_schemas) || (descriptor["packetSchemas"] = packet_schemas)
    isempty(accepted_pipes) || (descriptor["acceptedPipes"] = accepted_pipes)
    isempty(required_options) || (descriptor["requiredOptions"] = required_options)
    supports_query_set && (descriptor["supportsQuerySet"] = true)
    isempty(accepted_query_set_selectors) || (descriptor["acceptedQuerySetSelectors"] = accepted_query_set_selectors)
    isempty(capabilities) || (descriptor["capabilities"] = capabilities)
    descriptor
end

function julia_query_method_descriptor()
    Dict{String,Any}(
        "method" => "query/direct-source-read",
        "command" => "query",
        "input" => "hook-selector",
        "requiredOptions" => ["--from-hook", "--selector"],
        "outputModes" => ["frontier", "code", "read-packet"],
        "outputSchemaIds" => [
            "agent.semantic-protocols.semantic-query-packet",
            "agent.semantic-protocols.semantic-read-packet",
        ],
        "supportsCompact" => true,
        "supportsJson" => true,
    )
end

function julia_query_owner_items_method_descriptor()
    Dict{String,Any}(
        "method" => "query/owner-items",
        "command" => "query",
        "input" => "owner-path",
        "requiredOptions" => ["--term"],
        "outputModes" => ["frontier", "json", "code", "names"],
        "outputSchemaIds" => ["agent.semantic-protocols.semantic-query-packet"],
        "supportsCompact" => true,
        "supportsJson" => true,
        "capabilities" => [
            julia_agent_capability("owner-local-item-query"; namespace="semantic"),
            julia_agent_capability("julia-owner-item-query"),
        ],
    )
end

function julia_check_method_descriptor()
    Dict{String,Any}(
        "method" => "check/changed",
        "command" => "check",
        "supportsCompact" => true,
        "supportsJson" => false,
    )
end

function julia_evidence_method_descriptors()
    [
        Dict{String,Any}(
            "method" => "evidence/graph",
            "command" => "evidence",
            "input" => "provider project root",
            "outputSchemaIds" => ["agent.semantic-protocols.semantic-evidence-graph"],
            "supportsCompact" => true,
            "supportsJson" => true,
        ),
        Dict{String,Any}(
            "method" => "evidence/analyze",
            "command" => "evidence",
            "input" => "provider project root",
            "outputSchemaIds" => [
                "agent.semantic-protocols.semantic-graph-turbo-request",
            ],
            "packetSchemas" => ["semantic-graph-turbo-request.v1"],
            "clients" => ["asp-graph-turbo"],
            "supportsCompact" => true,
            "supportsJson" => true,
        ),
    ]
end
