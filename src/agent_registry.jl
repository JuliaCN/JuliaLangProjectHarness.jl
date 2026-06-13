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
    ("semantic-org-elements-query-packet.v1.schema.json", "agent.semantic-protocols.semantic-org-elements-query-packet"),
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

function julia_agent_method_descriptors()
    [
        julia_search_method_descriptor(
            "search/workspace",
            "workspace";
            requires_query=false,
            capabilities=[
                julia_agent_capability("workspace-router"; namespace="semantic"),
                julia_agent_capability("julia-syntax-search-index"),
            ],
        ),
        julia_search_method_descriptor(
            "search/prime",
            "prime";
            requires_query=false,
            capabilities=[
                julia_agent_capability("package-prime-map"; namespace="semantic"),
                julia_agent_capability("julia-syntax-search-index"),
            ],
        ),
        julia_search_method_descriptor(
            "search/owner",
            "owner";
            requires_query=true,
            accepted_pipes=["items", "tests"],
            capabilities=[
                julia_agent_capability("reasoning-owner-search"; namespace="semantic"),
                julia_agent_capability("julia-owner-search"),
            ],
        ),
        julia_search_method_descriptor(
            "search/fzf",
            "fzf";
            requires_query=true,
            accepted_pipes=["owner", "tests"],
            capabilities=[
                julia_agent_capability("finder-fuzzy-candidate-search"; namespace="semantic"),
                julia_agent_capability("julia-search-index-fzf"),
            ],
        ),
        julia_search_method_descriptor(
            "search/deps",
            "deps";
            requires_query=true,
            accepted_pipes=["owner", "tests"],
            capabilities=[
                julia_agent_capability("dependency-usage-search"; namespace="semantic"),
                julia_agent_capability("provider-owned-cache-file-hashes"; namespace="semantic"),
                julia_agent_capability("julia-dependency-search-index"),
            ],
        ),
        julia_search_method_descriptor(
            "search/query",
            "query";
            requires_query=true,
            accepted_pipes=["owner", "tests"],
            required_options=["--from-hook", "--selector", "--term"],
            supports_query_set=true,
            accepted_query_set_selectors=["fuzzy-set"],
            output_schema_ids=[
                "agent.semantic-protocols.semantic-search-packet",
                "agent.semantic-protocols.semantic-native-syntax-fact-index",
            ],
            capabilities=[
                julia_agent_capability("hook-wildcard-query-search"; namespace="semantic"),
                julia_agent_capability("julia-hook-query-search"),
            ],
        ),
        julia_search_method_descriptor(
            "search/policy",
            "policy";
            requires_query=true,
            accepted_pipes=["owner", "tests"],
            output_schema_ids=[
                "agent.semantic-protocols.semantic-search-packet",
                "agent.semantic-protocols.semantic-handle",
            ],
            capabilities=[
                julia_agent_capability("policy-rule-handle-search"; namespace="semantic"),
                julia_agent_capability("julia-project-policy-rule-handle-search"),
            ],
        ),
        julia_search_method_descriptor(
            "search/ingest",
            "ingest";
            requires_query=false,
            accepts_stdin=true,
            accepted_pipes=["owner", "tests"],
            capabilities=[
                julia_agent_capability("external-candidate-ingest"; namespace="semantic"),
                julia_agent_capability("owner-grouped-ingest"; namespace="semantic"),
            ],
        ),
        julia_search_method_descriptor(
            "search/semantic-facts",
            "semantic-facts";
            requires_query=true,
            accepts_stdin=true,
            supports_compact=false,
            output_schema_ids=["agent.semantic-protocols.semantic-fact-graph"],
            output_modes=["json"],
            packet_schemas=["semantic-fact-graph.v1", "semantic-fact-ontology.v1"],
            capabilities=[
                julia_agent_capability("graph-turbo-provider-facts"; namespace="semantic"),
                julia_agent_capability("julia-syntax-field-type-collection-facts"),
            ],
        ),
        julia_query_owner_items_method_descriptor(),
        julia_query_method_descriptor(),
        julia_check_method_descriptor(),
        julia_evidence_method_descriptors()...,
        Dict{String,Any}(
            "method" => "agent/doctor",
            "command" => "agent",
            "outputSchemaIds" => ["agent.semantic-protocols.semantic-language-registry"],
            "supportsCompact" => true,
            "supportsJson" => true,
        ),
        Dict{String,Any}(
            "method" => "agent/registry",
            "command" => "agent",
            "outputSchemaIds" => ["agent.semantic-protocols.semantic-language-registry"],
            "supportsCompact" => true,
            "supportsJson" => true,
        ),
        Dict{String,Any}(
            "method" => "guide",
            "command" => "guide",
            "clients" => ["codex"],
            "supportsCompact" => true,
            "supportsJson" => false,
        ),
    ]
end

"""Return package-local schema registrations advertised by the Julia provider."""
function julia_schema_registrations()
    package_root = normpath(joinpath(@__DIR__, ".."))
    registrations = Dict{String,String}[]
    for (file_name, schema_id) in JULIA_AGENT_SCHEMA_FILES
        path = joinpath("schemas", file_name)
        isfile(joinpath(package_root, path)) || continue
        push!(
            registrations,
            Dict(
                "path" => replace(path, '\\' => '/'),
                "schemaId" => schema_id,
                "schemaVersion" => "1",
            ),
        )
    end
    registrations
end

"""Build the Julia semantic-language registry packet for client discovery."""
function julia_agent_registry_packet(project_root::AbstractString=pwd())
    descriptors = julia_agent_method_descriptors()
    methods = sort!(unique(String(descriptor["method"]) for descriptor in descriptors))
    root = abspath(String(project_root))
    Dict(
        "registryId" => JULIA_AGENT_REGISTRY_ID,
        "registryVersion" => JULIA_AGENT_REGISTRY_VERSION,
        "protocolId" => JULIA_AGENT_REGISTRY_PROTOCOL_ID,
        "protocolVersion" => JULIA_AGENT_REGISTRY_PROTOCOL_VERSION,
        "projectRoot" => root,
        "languages" => [
            Dict(
                "languageId" => JULIA_INDEX_EXPORT_LANGUAGE_ID,
                "providerId" => JULIA_INDEX_EXPORT_PROVIDER_ID,
                "binary" => JULIA_AGENT_BINARY,
                "providerCommandPrefix" => [JULIA_AGENT_BINARY],
                "namespace" => JULIA_AGENT_PROVIDER_NAMESPACE,
                "displayName" => "Julia Harness",
                "methods" => methods,
                "methodDescriptors" => descriptors,
                "schemas" => julia_schema_registrations(),
            ),
        ],
    )
end

"""Render the Julia semantic-language registry packet as JSON."""
function render_julia_agent_registry_json(project_root::AbstractString=pwd())
    JSON3.write(julia_agent_registry_packet(project_root))
end

"""Render a compact Julia provider registry status line."""
function render_julia_agent_registry(project_root::AbstractString=pwd())
    packet = julia_agent_registry_packet(project_root)
    language = only(packet["languages"])
    "[julia-agent-registry] status=ok provider=$(language["providerId"]) methods=$(length(language["methods"])) schemas=$(length(language["schemas"])) project=$(packet["projectRoot"])\n"
end
