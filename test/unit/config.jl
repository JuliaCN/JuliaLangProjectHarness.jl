@testset "default config ignores local environment directories" begin
    config = default_julia_harness_config()

    @test ".devenv" in config.ignored_dir_names
end

function write_config_project(root::AbstractString)
    write(
        joinpath(root, "Project.toml"),
        """
        name = "ConfigExample"
        uuid = "11111111-1111-1111-1111-111111111111"
        version = "0.1.0"
        """,
    )
    mkpath(joinpath(root, "src"))
    write(joinpath(root, "src", "ConfigExample.jl"), "module ConfigExample\nend\n")
end

function config_with_agent_advice_allow_explanation(explanation::Union{Nothing,String})
    config = default_julia_harness_config()
    JuliaHarnessConfig(
        copy(config.ignored_dir_names),
        copy(config.blocking_severities),
        copy(config.disabled_rules),
        copy(config.disabled_rule_explanations),
        copy(config.rule_severity_overrides),
        copy(config.rule_severity_override_explanations),
        copy(config.blocking_severity_explanations),
        config.include_tests,
        copy(config.source_dir_names),
        copy(config.test_dir_names),
        copy(config.source_path_explanations),
        copy(config.test_path_explanations),
        copy(config.source_path_exclusion_explanations),
        copy(config.test_path_exclusion_explanations),
        explanation,
    )
end

@testset "config escape requires disabled rule explanation" begin
    root = mktempdir()
    write_config_project(root)
    config = default_julia_harness_config()
    push!(config.disabled_rules, "JULIA-AGENT-PROJECT-014")

    report = run_julia_project_harness(root; config)
    rendered = render_julia_project_harness(report)

    @test !JuliaLangProjectHarness.is_clean(report)
    @test occursin("JULIA-AGENT-PROJECT-014", rendered)
    @test occursin("disabled without a concrete explanation", rendered)

    config.disabled_rule_explanations["JULIA-AGENT-PROJECT-014"] =
        "todo add real explanation after the migration"
    placeholder_report = run_julia_project_harness(root; config)
    @test !JuliaLangProjectHarness.is_clean(placeholder_report)

    config.disabled_rule_explanations["JULIA-AGENT-PROJECT-014"] = "local policy migration under review"
    clean_report = run_julia_project_harness(root; config)

    @test JuliaLangProjectHarness.is_clean(clean_report)
end

@testset "config escape requires severity override explanation" begin
    root = mktempdir()
    write_config_project(root)
    config = default_julia_harness_config()
    config.rule_severity_overrides["JULIA-AGENT-PROJECT-002"] = JuliaLangProjectHarness.Info

    report = run_julia_project_harness(root; config)
    rendered = render_julia_project_harness(report)

    @test !JuliaLangProjectHarness.is_clean(report)
    @test occursin("JULIA-AGENT-PROJECT-014", rendered)
    @test occursin("severity is overridden", rendered)

    config.rule_severity_override_explanations["JULIA-AGENT-PROJECT-002"] = "later"
    placeholder_report = run_julia_project_harness(root; config)
    @test !JuliaLangProjectHarness.is_clean(placeholder_report)

    config.rule_severity_override_explanations["JULIA-AGENT-PROJECT-002"] =
        "temporary package layout migration"
    clean_report = run_julia_project_harness(root; config)

    @test JuliaLangProjectHarness.is_clean(clean_report)
end

@testset "config escape requires blocking severity explanation" begin
    root = mktempdir()
    write_config_project(root)
    config = default_julia_harness_config()
    delete!(config.blocking_severities, JuliaLangProjectHarness.Warning)

    report = run_julia_project_harness(root; config)
    rendered = render_julia_project_harness(report)

    @test !JuliaLangProjectHarness.is_clean(report)
    @test occursin("JULIA-AGENT-PROJECT-014", rendered)
    @test occursin("Blocking severity `warning` is removed", rendered)

    config.blocking_severity_explanations["warning"] = "n/a"
    placeholder_report = run_julia_project_harness(root; config)
    @test !JuliaLangProjectHarness.is_clean(placeholder_report)

    config.blocking_severity_explanations["warning"] = "collect warnings during staged rollout"
    clean_report = run_julia_project_harness(root; config)

    @test JuliaLangProjectHarness.is_clean(clean_report)
end

@testset "config escape rejects blank advisory allow explanation" begin
    root = mktempdir()
    write_config_project(root)
    config = config_with_agent_advice_allow_explanation("   ")

    report = run_julia_project_harness(root; config)
    rendered = render_julia_project_harness(report)

    @test !JuliaLangProjectHarness.is_clean(report)
    @test occursin("JULIA-AGENT-PROJECT-014", rendered)
    @test occursin("without a concrete explanation", rendered)
end

@testset "config escape rejects placeholder advisory allow explanation" begin
    root = mktempdir()
    write_config_project(root)
    config = config_with_agent_advice_allow_explanation(
        "todo add real advisory exception explanation after release",
    )

    report = run_julia_project_harness(root; config)
    rendered = render_julia_project_harness(report)

    @test !JuliaLangProjectHarness.is_clean(report)
    @test occursin("JULIA-AGENT-PROJECT-014", rendered)
    @test occursin("without a concrete explanation", rendered)
end

@testset "Project.toml declares JuliaLangProjectHarness policy" begin
    root = mktempdir()
    write(
        joinpath(root, "Project.toml"),
        """
        name = "ConfigExample"
        uuid = "11111111-1111-1111-1111-111111111111"
        version = "0.1.0"

        [tool.JuliaLangProjectHarness]
        advice = "report"
        advice_explanation = "stage public API documentation while landing Project.toml policy"
        include_tests = false
        source_dir_names = ["lib"]
        test_dir_names = ["spec"]

        [tool.JuliaLangProjectHarness.source_path_explanations]
        lib = "package keeps generated source adapters under lib during migration"

        [tool.JuliaLangProjectHarness.rule_severity_overrides]
        "JULIA-AGENT-PROJECT-002" = "info"

        [tool.JuliaLangProjectHarness.rule_severity_override_explanations]
        "JULIA-AGENT-PROJECT-002" = "temporary package layout migration"
        """,
    )
    mkpath(joinpath(root, "lib"))
    write(joinpath(root, "lib", "ConfigExample.jl"), "module ConfigExample\nend\n")

    config = JuliaLangProjectHarness.project_toml_harness_config(
        root,
        default_julia_harness_config(),
    )

    @test config.include_tests == false
    @test config.source_dir_names == ["lib"]
    @test config.test_dir_names == ["spec"]
    @test config.blocking_severities ==
          Set([JuliaLangProjectHarness.Warning, JuliaLangProjectHarness.Error])
    @test config.rule_severity_overrides["JULIA-AGENT-PROJECT-002"] == JuliaLangProjectHarness.Info
    @test config.agent_advice_allow_explanation ==
          "stage public API documentation while landing Project.toml policy"

    report = run_julia_project_harness(root)
    @test JuliaLangProjectHarness.is_clean(report)
end

@testset "Project.toml report advice policy requires explanation" begin
    root = mktempdir()
    write(
        joinpath(root, "Project.toml"),
        """
        name = "ConfigExample"
        uuid = "11111111-1111-1111-1111-111111111111"
        version = "0.1.0"

        [tool.JuliaLangProjectHarness]
        advice = "report"
        """,
    )
    mkpath(joinpath(root, "src"))
    write(joinpath(root, "src", "ConfigExample.jl"), "module ConfigExample\nend\n")

    report = run_julia_project_harness(root)
    rendered = render_julia_project_harness(report)

    @test !JuliaLangProjectHarness.is_clean(report)
    @test occursin("JULIA-AGENT-PROJECT-014", rendered)
    @test occursin("without a concrete explanation", rendered)
end

@testset "Project.toml report advice policy applies to test profile gate" begin
    root = mktempdir()
    write(
        joinpath(root, "Project.toml"),
        """
        name = "ConfigExample"
        uuid = "11111111-1111-1111-1111-111111111111"
        version = "0.1.0"

        [tool.JuliaLangProjectHarness]
        advice = "report"
        advice_explanation = "stage public docs while activating package policy"
        """,
    )
    mkpath(joinpath(root, "src"))
    write(
        joinpath(root, "src", "ConfigExample.jl"),
        """
        module ConfigExample
        export public_value
        public_value() = 1
        end
        """,
    )

    profile = assert_julia_project_harness_test_profile_clean(root; advice_io = nothing)

    @test JuliaLangProjectHarness.is_clean(profile.report)
    @test !isempty(JuliaLangProjectHarness.advisory_findings(profile.report))
end

@testset "Project.toml report advice policy applies to pkg test clean gate" begin
    root = mktempdir()
    write(
        joinpath(root, "Project.toml"),
        """
        name = "ConfigExample"
        uuid = "11111111-1111-1111-1111-111111111111"
        version = "0.1.0"

        [tool.JuliaLangProjectHarness]
        advice = "report"
        advice_explanation = "stage public docs while activating package policy"
        """,
    )
    mkpath(joinpath(root, "src"))
    write(
        joinpath(root, "src", "ConfigExample.jl"),
        """
        module ConfigExample
        export public_value
        public_value() = 1
        end
        """,
    )

    report = assert_julia_project_harness_pkg_test_clean(root)

    @test JuliaLangProjectHarness.is_clean(report)
    @test !isempty(JuliaLangProjectHarness.advisory_findings(report))
end

@testset "Project.toml advice policy defaults to gate" begin
    root = mktempdir()
    write_config_project(root)

    config = JuliaLangProjectHarness.project_toml_harness_config(
        root,
        default_julia_harness_config(),
    )

    @test isnothing(config.agent_advice_allow_explanation)
end
