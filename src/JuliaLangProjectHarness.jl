"""JuliaSyntax-native project harness for Julia package policy and agent context."""
module JuliaLangProjectHarness

include("model.jl")
include("parser.jl")
include("rules.jl")
include("rule_visibility.jl")
include("render.jl")
include("runner.jl")
include("runner/package_paths.jl")
include("runner/project_config.jl")
include("runner/project_context.jl")
include("search_index.jl")
include("search_index/tests.jl")
include("search_index/owners.jl")
include("search_index/types.jl")
include("search_index/functions.jl")
include("search_index/moshi.jl")
include("search_index/origin.jl")
include("search_index/verification.jl")
include("search_render.jl")
include("asp_export.jl")
include("semantic_graph_project_facts.jl")
include("semantic_graph_facts.jl")
include("harness_rules.jl")
include("agent_registry.jl")
include("asp_query.jl")
include("agent_snapshot.jl")
include("verification.jl")
include("verification/benchmarks.jl")
include("verification/examples.jl")
include("verification/extensions.jl")
include("verification/responsibility_inference.jl")
include("verification/contracts.jl")
include("verification/receipt_templates.jl")
include("verification/receipts.jl")
include("verification/advice.jl")
include("verification/context.jl")
include("verification/profile_index.jl")
include("moshi_extension.jl")
include("evidence_graph.jl")
include("cli/search_protocol.jl")
include("cli/dependency_topology.jl")
include("cli/search_query.jl")
include("cli/search_cli.jl")
include("asp_search.jl")
include("queries/flow_lite.jl")
include("cli/query.jl")
include("cli/query_contract.jl")
include("cli/project_resolution.jl")
include("cli/project_resolution_codec.jl")
include("cli/query_code.jl")
include("cli.jl")

"""Configure JuliaSyntax only for the closed JuliaC build process.

Safety contract: this fixed parser override runs only while `ASP_JULIA_AOT_BUILD=1`,
before the compiler snapshots the Harness dependency graph; it never mutates a normal
Harness process. The JuliaC compile smoke and compiled `guide`/`export index` tests
verify that the override preserves the parser block contract.
"""
function configure_juliac_aot_syntax!()
    Core.eval(
        JuliaSyntax,
        quote
            function parse_block(ps::ParseState)
                mark = position(ps)
                parse_block_inner(ps, parse_eq)
                emit(ps, mark, K"block")
            end
        end,
    )
    nothing
end

export JuliaDiagnosticSeverity,
    JuliaHarnessConfig,
    JuliaHarnessFinding,
    JuliaHarnessReport,
    JuliaHarnessRule,
    JuliaRuleVisibility,
    JuliaFileReport,
    JuliaSearchIndexEntry,
    JuliaSearchResult,
    JuliaVerificationProfileCandidate,
    JuliaVerificationProfileIndex,
    JuliaVerificationReceiptReview,
    JuliaVerificationTaskIndex,
    JuliaVerificationTaskRecord,
    JuliaVerificationProfile,
    RulePackDescriptor,
    SourceLocation,
    assert_julia_lang_harness_clean,
    assert_julia_project_harness_clean,
    assert_julia_project_harness_pkg_test_clean,
    assert_julia_project_harness_test_profile_clean,
    assert_julia_verification_receipts_accepted,
    build_julia_project_verification_profile,
    build_julia_verification_profile_index,
    build_julia_verification_task_index,
    default_julia_harness_config,
    julia_agent_policy_rules,
    julia_modularity_rules,
    julia_project_policy_rules,
    julia_project_search_index,
    julia_harness_rules_markdown,
    julia_agent_registry_packet,
    julia_index_export_packet,
    julia_query_owner_items_packet,
    julia_schema_registrations,
    julia_rule_pack_descriptors,
    julia_rule_visibility,
    julia_syntax_rules,
    julia_lang_search_index,
    moshi_extension_capabilities,
    read_julia_verification_receipts_json,
    render_julia_project_harness,
    render_julia_project_harness_advice,
    render_julia_project_harness_agent_snapshot,
    render_julia_project_harness_json,
    render_julia_harness_rules_markdown,
    render_julia_index_export_json,
    render_julia_semantic_graph_facts_json,
    render_julia_agent_registry,
    render_julia_agent_registry_json,
    render_julia_evidence_analysis_request_json,
    render_julia_evidence_graph_json,
    render_julia_query_owner_items,
    render_julia_query_owner_items_json,
    render_julia_native_owner_items_query_json,
    run_julia_native_owner_items_query_cli,
    render_julia_rule_visibility,
    render_julia_search_results,
    render_julia_verification_pending_advice,
    render_julia_verification_profile,
    render_julia_verification_profile_index,
    render_julia_verification_profile_index_json,
    render_julia_verification_profile_json,
    render_julia_verification_receipt_template,
    render_julia_verification_receipt_reviews,
    render_julia_verification_receipt_reviews_json,
    render_julia_verification_task_index,
    render_julia_verification_task_index_json,
    review_julia_verification_receipts,
    run_julia_harness_export_cli,
    run_julia_project_harness_cli,
    run_julia_lang_harness,
    run_julia_project_harness,
    search_julia_index,
    search_julia_lang,
    search_julia_project,
    write_julia_harness_rules_to_unit_tests

end
