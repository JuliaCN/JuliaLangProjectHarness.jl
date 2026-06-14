"""Knowledge-axis method descriptors for the Julia provider."""

function julia_knowledge_search_method_descriptors()
    [
        julia_search_method_descriptor(
            "search/env",
            "env";
            requires_query=false,
            capabilities=[
                julia_agent_capability("provider-knowledge-axis"; namespace="semantic"),
                julia_agent_capability("julia-project-environment-facts"),
            ],
        ),
        julia_search_method_descriptor(
            "search/runtime-source",
            "runtime-source";
            requires_query=false,
            capabilities=[
                julia_agent_capability("provider-knowledge-axis"; namespace="semantic"),
                julia_agent_capability("julia-runtime-source-frontier"),
            ],
        ),
        julia_search_method_descriptor(
            "search/lang",
            "lang";
            requires_query=false,
            capabilities=[
                julia_agent_capability("provider-knowledge-axis"; namespace="semantic"),
                julia_agent_capability("julia-language-semantics-facts"),
            ],
        ),
        julia_search_method_descriptor(
            "search/std",
            "std";
            requires_query=false,
            capabilities=[
                julia_agent_capability("provider-knowledge-axis"; namespace="semantic"),
                julia_agent_capability("julia-standard-api-facts"),
            ],
        ),
        julia_search_method_descriptor(
            "search/capability",
            "capability";
            requires_query=false,
            capabilities=[
                julia_agent_capability("provider-knowledge-axis"; namespace="semantic"),
                julia_agent_capability("julia-provider-capability-facts"),
            ],
        ),
        julia_search_method_descriptor(
            "search/extension",
            "extension";
            requires_query=true,
            capabilities=[
                julia_agent_capability("provider-knowledge-axis"; namespace="semantic"),
                julia_agent_capability("julia-ecosystem-extension-facts"),
            ],
        ),
        julia_search_method_descriptor(
            "search/pattern",
            "pattern";
            requires_query=true,
            capabilities=[
                julia_agent_capability("provider-knowledge-axis"; namespace="semantic"),
                julia_agent_capability("julia-executable-pattern-facts"),
            ],
        ),
        julia_search_method_descriptor(
            "search/compare",
            "compare";
            requires_query=true,
            capabilities=[
                julia_agent_capability("provider-knowledge-axis"; namespace="semantic"),
                julia_agent_capability("julia-semantic-comparison-facts"),
            ],
        ),
    ]
end
