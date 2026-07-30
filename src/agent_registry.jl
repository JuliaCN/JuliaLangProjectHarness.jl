include("agent_registry/core.jl")
include("agent_registry/knowledge.jl")

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
            "search/lexical",
            "lexical";
            requires_query=true,
            accepted_pipes=["owner", "tests"],
            capabilities=[
                julia_agent_capability("lexical-candidate-search"; namespace="semantic"),
                julia_agent_capability("julia-search-index-lexical"),
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
        julia_knowledge_search_method_descriptors()...,
        julia_search_method_descriptor(
            "search/query",
            "query";
            requires_query=true,
            accepted_pipes=["owner", "tests"],
            required_options=["--from-hook", "--selector", "--term"],
            supports_query_set=true,
            accepted_query_set_selectors=["lexical-set"],
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
    schema_registrations((
        JULIA_AGENT_SCHEMA_FILES...,
        (
            "semantic-owner-item-evidence.v1.schema.json",
            "agent.semantic-protocols.semantic-owner-item-evidence",
        ),
    ))
end

"""Return package-local schema registrations for a provider language entry."""
function schema_registrations(schema_files)
    package_root = normpath(joinpath(@__DIR__, ".."))
    registrations = Dict{String,String}[]
    for (file_name, schema_id) in schema_files
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
    JSON.json(julia_agent_registry_packet(project_root))
end

"""Render a compact Julia provider registry status line."""
function render_julia_agent_registry(project_root::AbstractString=pwd())
    packet = julia_agent_registry_packet(project_root)
    julia_language = only(filter(language -> language["languageId"] == JULIA_INDEX_EXPORT_LANGUAGE_ID, packet["languages"]))
    "[julia-agent-registry] status=ok provider=$(julia_language["providerId"]) methods=$(length(julia_language["methods"])) schemas=$(length(julia_language["schemas"])) languages=$(length(packet["languages"])) project=$(packet["projectRoot"])\n"
end
