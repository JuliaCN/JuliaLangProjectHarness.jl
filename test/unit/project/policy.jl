@testset "project runner reports extras not mounted by Pkg.test target" begin
    root = mktempdir()
    write(
        joinpath(root, "Project.toml"),
        """
        name = "Example"
        uuid = "11111111-1111-1111-1111-111111111111"
        version = "0.1.0"

        [extras]
        JSON = "682c06a0-de6a-54ab-a142-c8b1cf79cde6"
        Test = "8dfed614-e22c-5e08-85e1-65c5234f0b40"

        [targets]
        test = ["Test"]
        """,
    )
    mkpath(joinpath(root, "src"))
    mkpath(joinpath(root, "test"))
    write(joinpath(root, "src", "Example.jl"), "module Example\nend\n")
    write(joinpath(root, "test", "runtests.jl"), "using Test\nusing JSON\n@test true\n")

    report = run_julia_project_harness(root)
    rendered = render_julia_project_harness(report)

    @test !JuliaLangProjectHarness.is_clean(report)
    @test occursin("JULIA-AGENT-PROJECT-008", rendered)
    @test occursin("Imported package is missing from Project.toml", rendered)
    @test count(finding -> finding.rule_id == "JULIA-AGENT-PROJECT-008", report.findings) == 1
end

@testset "project runner reports missing package extension entrypoint" begin
    root = mktempdir()
    write(
        joinpath(root, "Project.toml"),
        """
        name = "Example"
        uuid = "11111111-1111-1111-1111-111111111111"
        version = "0.1.0"

        [weakdeps]
        JSON = "682c06a0-de6a-54ab-a142-c8b1cf79cde6"

        [compat]
        JSON = "1"

        [extensions]
        ExampleJSONExt = "JSON"
        """,
    )
    mkpath(joinpath(root, "src"))
    write(joinpath(root, "src", "Example.jl"), "module Example\nend\n")

    report = run_julia_project_harness(root)
    rendered = render_julia_project_harness(report)

    @test !JuliaLangProjectHarness.is_clean(report)
    @test occursin("JULIA-AGENT-PROJECT-011", rendered)
    @test occursin("Project extension entrypoint is missing", rendered)
    @test count(finding -> finding.rule_id == "JULIA-AGENT-PROJECT-011", report.findings) == 1
end

@testset "project runner reports dependencies without compat or source override" begin
    root = mktempdir()
    write(
        joinpath(root, "Project.toml"),
        """
        name = "Example"
        uuid = "11111111-1111-1111-1111-111111111111"
        version = "0.1.0"

        [deps]
        JSON = "682c06a0-de6a-54ab-a142-c8b1cf79cde6"
        """,
    )
    mkpath(joinpath(root, "src"))
    write(joinpath(root, "src", "Example.jl"), "module Example\nusing JSON\nend\n")

    report = run_julia_project_harness(root)
    rendered = render_julia_project_harness(report)

    @test !JuliaLangProjectHarness.is_clean(report)
    @test occursin("JULIA-AGENT-PROJECT-009", rendered)
    @test occursin("Project dependency lacks compat or source override", rendered)
    @test count(finding -> finding.rule_id == "JULIA-AGENT-PROJECT-009", report.findings) == 1
end

@testset "project runner reports moving source revs" begin
    root = mktempdir()
    write(
        joinpath(root, "Project.toml"),
        """
        name = "Example"
        uuid = "11111111-1111-1111-1111-111111111111"
        version = "0.1.0"

        [deps]
        JuliaSyntax = "70703baa-626e-46a2-a12c-08ffd08c73b4"

        [sources]
        JuliaSyntax = {url = "https://github.com/JuliaLang/JuliaSyntax.jl", rev = "main"}
        """,
    )
    mkpath(joinpath(root, "src"))
    write(joinpath(root, "src", "Example.jl"), "module Example\nusing JuliaSyntax\nend\n")

    report = run_julia_project_harness(root)
    rendered = render_julia_project_harness(report)

    @test !JuliaLangProjectHarness.is_clean(report)
    @test occursin("JULIA-AGENT-PROJECT-010", rendered)
    @test occursin("Source-tracked dependency rev is not locked", rendered)
    @test count(finding -> finding.rule_id == "JULIA-AGENT-PROJECT-010", report.findings) == 1
end

@testset "project runner sorts source rev findings by source name" begin
    root = mktempdir()
    write(
        joinpath(root, "Project.toml"),
        """
        name = "Example"
        uuid = "11111111-1111-1111-1111-111111111111"
        version = "0.1.0"

        [deps]
        Arrow = "69666777-d1a9-59fb-9406-91d4454c9d45"
        ArrowTypes = "31f734f8-188a-4ce0-8406-c8a06bd891cd"

        [sources]
        Arrow = {url = "https://github.com/JuliaCN/arrow-julia.git", rev = "main"}
        ArrowTypes = {url = "https://github.com/JuliaCN/arrow-julia.git", subdir = "src/ArrowTypes", rev = "main"}
        """,
    )
    mkpath(joinpath(root, "src"))
    write(joinpath(root, "src", "Example.jl"), "module Example\nusing Arrow\nend\n")

    report = run_julia_project_harness(root)
    source_findings = filter(finding -> finding.rule_id == "JULIA-AGENT-PROJECT-010", report.findings)

    @test [finding.summary for finding in source_findings] == [
        "Project source `Arrow` uses moving `rev = \"main\"`.",
        "Project source `ArrowTypes` uses moving `rev = \"main\"`.",
    ]
end

@testset "project runner reports undeclared source imports" begin
    root = mktempdir()
    write_project(root, "Example")
    mkpath(joinpath(root, "src"))
    write(
        joinpath(root, "src", "Example.jl"),
        """
        module Example
        using JSON
        using .Local
        import Base: show
        end
        """,
    )

    report = run_julia_project_harness(root)
    rendered = render_julia_project_harness(report)

    @test !JuliaLangProjectHarness.is_clean(report)
    @test occursin("JULIA-AGENT-PROJECT-008", rendered)
    @test occursin("Imported package is missing from Project.toml", rendered)
    @test count(finding -> finding.rule_id == "JULIA-AGENT-PROJECT-008", report.findings) == 1
end

@testset "project runner reports missing Pkg.test entrypoint" begin
    root = mktempdir()
    write_project(root, "Example")
    mkpath(joinpath(root, "src"))
    mkpath(joinpath(root, "test"))
    write(joinpath(root, "src", "Example.jl"), "module Example\nend\n")
    write(joinpath(root, "test", "helpers.jl"), "value = 1\n")

    report = run_julia_project_harness(root)
    rendered = render_julia_project_harness(report)

    @test !JuliaLangProjectHarness.is_clean(report)
    @test occursin("JULIA-AGENT-PROJECT-003", rendered)
    @test occursin("Pkg.test entrypoint is missing", rendered)
    @test occursin("test/runtests.jl", rendered)
    @test count(finding -> finding.rule_id == "JULIA-AGENT-PROJECT-003", report.findings) == 1
end

@testset "project runner reports large inline runtests entrypoint" begin
    root = mktempdir()
    write_project(root, "Example")
    mkpath(joinpath(root, "src"))
    mkpath(joinpath(root, "test"))
    write(joinpath(root, "src", "Example.jl"), "module Example\nend\n")
    tests = join(fill("@test true", 81), "\n")
    write(joinpath(root, "test", "runtests.jl"), "using Test\n$(tests)\n")

    report = run_julia_project_harness(root)
    rendered = render_julia_project_harness(report)

    @test !JuliaLangProjectHarness.is_clean(report)
    @test occursin("JULIA-AGENT-PROJECT-004", rendered)
    @test occursin("Pkg.test entrypoint is no longer a thin aggregate", rendered)
    @test count(finding -> finding.rule_id == "JULIA-AGENT-PROJECT-004", report.findings) == 1
end

@testset "project runner advises harness test profile hook" begin
    root = mktempdir()
    write(
        joinpath(root, "Project.toml"),
        """
        name = "Example"
        uuid = "11111111-1111-1111-1111-111111111111"
        version = "0.1.0"

        [deps]
        JuliaLangProjectHarness = "67259778-f152-405a-bc38-ee6219bce977"

        [extras]
        Test = "8dfed614-e22c-5e08-85e1-65c5234f0b40"

        [targets]
        test = ["Test"]

        [compat]
        JuliaLangProjectHarness = "0.1"
        """,
    )
    mkpath(joinpath(root, "src"))
    mkpath(joinpath(root, "test"))
    write(joinpath(root, "src", "Example.jl"), "module Example\nend\n")
    write(joinpath(root, "test", "runtests.jl"), "using Test\n@test true\n")

    report = run_julia_project_harness(root)
    rendered = render_julia_project_harness(report)

    @test JuliaLangProjectHarness.is_clean(report)
    @test occursin("AGENT-JL-R014", rendered)
    @test occursin("Pkg.test lacks the harness verification profile", rendered)
    @test length(JuliaLangProjectHarness.advisory_findings(report)) == 1
end

@testset "project runner accepts harness test profile hook" begin
    root = mktempdir()
    write(
        joinpath(root, "Project.toml"),
        """
        name = "Example"
        uuid = "11111111-1111-1111-1111-111111111111"
        version = "0.1.0"

        [deps]
        JuliaLangProjectHarness = "67259778-f152-405a-bc38-ee6219bce977"

        [extras]
        Test = "8dfed614-e22c-5e08-85e1-65c5234f0b40"

        [targets]
        test = ["Test"]

        [compat]
        JuliaLangProjectHarness = "0.1"
        """,
    )
    mkpath(joinpath(root, "src"))
    mkpath(joinpath(root, "test"))
    write(joinpath(root, "src", "Example.jl"), "module Example\nend\n")
    write(
        joinpath(root, "test", "runtests.jl"),
        """
        using JuliaLangProjectHarness
        using Test

        @test true
        assert_julia_project_harness_test_profile_clean(dirname(@__DIR__))
        """,
    )

    report = run_julia_project_harness(root)

    @test JuliaLangProjectHarness.is_clean(report)
    @test isempty(JuliaLangProjectHarness.advisory_findings(report))
end

@testset "project runner reports custom source scope without explanation" begin
    root = mktempdir()
    write_project(root, "Example")
    mkpath(joinpath(root, "src"))
    mkpath(joinpath(root, "lib"))
    write(joinpath(root, "src", "Example.jl"), "module Example\nend\n")
    config = default_julia_harness_config()
    push!(config.source_dir_names, "lib")

    report = run_julia_project_harness(root; config)
    rendered = render_julia_project_harness(report)

    @test !JuliaLangProjectHarness.is_clean(report)
    @test occursin("JULIA-AGENT-PROJECT-005", rendered)
    @test occursin("Custom source or test scope lacks explanation", rendered)
    @test count(finding -> finding.rule_id == "JULIA-AGENT-PROJECT-005", report.findings) == 1

    config.source_path_explanations["lib"] = "todo"
    placeholder_report = run_julia_project_harness(root; config)

    @test !JuliaLangProjectHarness.is_clean(placeholder_report)
    @test count(finding -> finding.rule_id == "JULIA-AGENT-PROJECT-005", placeholder_report.findings) == 1
end

@testset "project runner accepts Pkg entryfile source without conventional src" begin
    root = mktempdir()
    write(
        joinpath(root, "Project.toml"),
        """
        name = "Example"
        uuid = "11111111-1111-1111-1111-111111111111"
        version = "0.1.0"
        entryfile = "lib/Example.jl"
        """,
    )
    mkpath(joinpath(root, "src"))
    mkpath(joinpath(root, "lib"))
    write(joinpath(root, "lib", "Example.jl"), "module Example\nend\n")
    write(joinpath(root, "src", "Stale.jl"), "module Stale\nusing MissingPkg\nend\n")

    report = run_julia_project_harness(root)

    @test JuliaLangProjectHarness.is_clean(report)
    @test report.project_resolution.source_paths == [joinpath(root, "lib")]
end

@testset "project runner reports conventional test scope exclusion" begin
    root = mktempdir()
    write_project(root, "Example")
    mkpath(joinpath(root, "src"))
    mkpath(joinpath(root, "test"))
    write(joinpath(root, "src", "Example.jl"), "module Example\nend\n")
    default_config = default_julia_harness_config()
    config = JuliaHarnessConfig(
        copy(default_config.ignored_dir_names),
        copy(default_config.blocking_severities),
        copy(default_config.disabled_rules),
        copy(default_config.disabled_rule_explanations),
        copy(default_config.rule_severity_overrides),
        copy(default_config.rule_severity_override_explanations),
        copy(default_config.blocking_severity_explanations),
        false,
        copy(default_config.source_dir_names),
        copy(default_config.test_dir_names),
        copy(default_config.source_path_explanations),
        copy(default_config.test_path_explanations),
        copy(default_config.source_path_exclusion_explanations),
        copy(default_config.test_path_exclusion_explanations),
        default_config.agent_advice_allow_explanation,
    )

    report = run_julia_project_harness(root; config)
    rendered = render_julia_project_harness(report)

    @test !JuliaLangProjectHarness.is_clean(report)
    @test occursin("JULIA-AGENT-PROJECT-006", rendered)
    @test occursin("Conventional source or test scope was excluded", rendered)
    @test count(finding -> finding.rule_id == "JULIA-AGENT-PROJECT-006", report.findings) == 1
end

@testset "project runner reports package policy facts" begin
    root = mktempdir()
    mkpath(joinpath(root, "src"))
    write(joinpath(root, "Project.toml"), "version = \"0.1.0\"\n")
    write(joinpath(root, "src", "NoName.jl"), "value() = 1\n")

    report = run_julia_project_harness(root)
    rendered = render_julia_project_harness(report)

    @test !JuliaLangProjectHarness.is_clean(report)
    @test occursin("JULIA-AGENT-PROJECT-001", rendered)
    @test occursin("Project.toml lacks a package name", rendered)
end

@testset "project runner reports Project.toml read errors" begin
    root = mktempdir()
    mkpath(joinpath(root, "src"))
    write(
        joinpath(root, "Project.toml"),
        """
        name = "Example"
        uuid = "11111111-1111-1111-1111-111111111111"
        version = "0.1.0"

        [targets]
        test = ["Missing"]
        """,
    )
    write(joinpath(root, "src", "Example.jl"), "module Example\nend\n")

    report = run_julia_project_harness(root)
    rendered = render_julia_project_harness(report)

    @test !JuliaLangProjectHarness.is_clean(report)
    @test !isnothing(report.project_resolution.project_parse_error)
    @test occursin("JULIA-AGENT-PROJECT-013", rendered)
    @test occursin("Project.toml is not readable by Pkg", rendered)
    @test occursin("Missing", rendered)
    @test count(finding -> finding.rule_id == "JULIA-AGENT-PROJECT-013", report.findings) == 1
    @test count(finding -> finding.rule_id == "JULIA-AGENT-PROJECT-001", report.findings) == 0
end

@testset "project runner reports entry module mismatch" begin
    root = mktempdir()
    write_project(root, "Example")
    mkpath(joinpath(root, "src"))
    write(joinpath(root, "src", "Example.jl"), "module Different\nend\n")

    report = run_julia_project_harness(root)
    rendered = render_julia_project_harness(report)

    @test !JuliaLangProjectHarness.is_clean(report)
    @test occursin("JULIA-AGENT-PROJECT-007", rendered)
    @test occursin("Package entry file lacks package module declaration", rendered)
end
