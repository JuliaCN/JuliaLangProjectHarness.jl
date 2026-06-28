@testset "rule catalog" begin
    descriptors = julia_rule_pack_descriptors()
    @test [descriptor.id for descriptor in descriptors] == [
        "julia.syntax",
        "julia.project_policy",
        "julia.modularity",
        "julia.agent_policy",
    ]
    @test [descriptor.default_mode for descriptor in descriptors] == [
        :blocking,
        :blocking,
        :blocking,
        :advisory,
    ]

    syntax_rules = julia_syntax_rules()
    @test length(syntax_rules) == 1
    @test only(syntax_rules).rule_id == "JULIA-SYN-R001"
    @test only(syntax_rules).severity == JuliaLangProjectHarness.Error
    @test [rule.rule_id for rule in julia_project_policy_rules()] == [
        "JULIA-AGENT-PROJECT-001",
        "JULIA-AGENT-PROJECT-002",
        "JULIA-AGENT-PROJECT-003",
        "JULIA-AGENT-PROJECT-004",
        "JULIA-AGENT-PROJECT-005",
        "JULIA-AGENT-PROJECT-006",
        "JULIA-AGENT-PROJECT-007",
        "JULIA-AGENT-PROJECT-008",
        "JULIA-AGENT-PROJECT-009",
        "JULIA-AGENT-PROJECT-010",
        "JULIA-AGENT-PROJECT-011",
        "JULIA-AGENT-PROJECT-012",
        "JULIA-AGENT-PROJECT-013",
        "JULIA-AGENT-PROJECT-014",
    ]
    @test [rule.rule_id for rule in julia_modularity_rules()] == [
        "JULIA-MOD-R001",
        "JULIA-MOD-R002",
        "JULIA-MOD-R003",
        "JULIA-MOD-R004",
        "JULIA-MOD-R005",
        "JULIA-MOD-R006",
        "JULIA-MOD-R007",
    ]
    @test [rule.rule_id for rule in julia_agent_policy_rules()] == [
        "AGENT-JL-R001",
        "AGENT-JL-R002",
        "AGENT-JL-R003",
        "AGENT-JL-R004",
        "AGENT-JL-R005",
        "AGENT-JL-R006",
        "AGENT-JL-R007",
        "AGENT-JL-R008",
        "AGENT-JL-R009",
        "AGENT-JL-R010",
        "AGENT-JL-R011",
        "AGENT-JL-R012",
        "AGENT-JL-R013",
        "AGENT-JL-R014",
        "AGENT-JL-R015",
        "AGENT-JL-R016",
        "AGENT-JL-R017",
        "AGENT-JL-R018",
        "AGENT-JL-R019",
        "AGENT-JL-R020",
        "AGENT-JL-R021",
        "AGENT-JL-R022",
        "AGENT-JL-R023",
        "AGENT-JL-R024",
        "AGENT-JL-R025",
        "AGENT-JL-R026",
        "AGENT-JL-R027",
        "AGENT-JL-R028",
        "AGENT-JL-R029",
        "AGENT-JL-R030",
        "AGENT-JL-R031",
    ]
end

@testset "self apply public api" begin
    @test isdefined(JuliaLangProjectHarness, :assert_julia_project_harness_pkg_test_clean)
    @test isdefined(JuliaLangProjectHarness, :assert_julia_project_harness_test_profile_clean)
    @test isdefined(JuliaLangProjectHarness, :build_julia_project_verification_profile)
    @test isdefined(JuliaLangProjectHarness, :build_julia_verification_profile_index)
    @test isdefined(JuliaLangProjectHarness, :render_julia_project_harness_agent_snapshot)
    @test isdefined(JuliaLangProjectHarness, :render_julia_verification_pending_advice)
    @test isdefined(JuliaLangProjectHarness, :render_julia_verification_profile)
    @test isdefined(JuliaLangProjectHarness, :render_julia_verification_profile_index)
end
