@testset "project runner accepts reachable literal include graph" begin
    root = mktempdir()
    write_project(root, "Example")
    mkpath(joinpath(root, "src"))
    write(joinpath(root, "src", "Example.jl"), "module Example\ninclude(\"api.jl\")\nend\n")
    write(joinpath(root, "src", "api.jl"), "run() = 1\n")

    report = run_julia_project_harness(root)

    @test AspJulia.is_clean(report)
    @test !isnothing(report.project_resolution)
    @test report.project_resolution.package_name == "Example"
    @test isnothing(report.project_resolution.project_parse_error)
    @test report.project_resolution.package_entry_path == joinpath(root, "src", "Example.jl")
    @test render_julia_project_harness(report) == "[ok] julia\n"
end

@testset "project runner resolves root from Project.toml owner" begin
    root = mktempdir()
    write_project(root, "Example")
    mkpath(joinpath(root, "src", "internal"))
    write(joinpath(root, "src", "Example.jl"), "module Example\ninclude(\"internal/api.jl\")\nend\n")
    write(joinpath(root, "src", "internal", "api.jl"), "run() = 1\n")

    report = run_julia_project_harness(joinpath(root, "src", "internal"))

    @test AspJulia.is_clean(report)
    @test report.project_resolution.project_root == root
    @test report.project_resolution.project_toml_path == joinpath(root, "Project.toml")
    @test report.project_resolution.package_entry_path == joinpath(root, "src", "Example.jl")
end

@testset "project runner honors Project.toml entryfile" begin
    root = mktempdir()
    write(
        joinpath(root, "Project.toml"),
        """
        name = "Example"
        uuid = "11111111-1111-1111-1111-111111111111"
        version = "0.1.0"
        entryfile = "src/Entry.jl"
        """,
    )
    mkpath(joinpath(root, "src"))
    write(joinpath(root, "src", "Entry.jl"), "module Example\nend\n")

    report = run_julia_project_harness(root)
    snapshot = render_julia_project_harness_agent_snapshot(root)

    @test AspJulia.is_clean(report)
    @test report.project_resolution.project_entryfile == "src/Entry.jl"
    @test report.project_resolution.package_entry_path == joinpath(root, "src", "Entry.jl")
    @test occursin("Entry: src/Entry.jl", snapshot)
    @test occursin("entryfile=src/Entry.jl", snapshot)
end

@testset "project runner uses Pkg entryfile as source scope" begin
    root = mktempdir()
    write(
        joinpath(root, "Project.toml"),
        """
        name = "Example"
        uuid = "11111111-1111-1111-1111-111111111111"
        version = "0.1.0"
        entryfile = "lib/Entry.jl"
        """,
    )
    mkpath(joinpath(root, "lib"))
    mkpath(joinpath(root, "src"))
    write(joinpath(root, "lib", "Entry.jl"), "module Example\nend\n")
    write(joinpath(root, "src", "Stale.jl"), "module Stale\nusing MissingPkg\nend\n")

    report = run_julia_project_harness(root)

    @test AspJulia.is_clean(report)
    @test report.project_resolution.source_paths == [joinpath(root, "lib")]
    @test any(file -> file.path == joinpath(root, "lib", "Entry.jl"), report.files)
    @test !any(file -> file.path == joinpath(root, "src", "Stale.jl"), report.files)
end

@testset "project runner records package-owned auxiliary paths for search" begin
    root = mktempdir()
    write_project(root, "Example")
    mkpath(joinpath(root, "src"))
    mkpath(joinpath(root, "docs"))
    mkpath(joinpath(root, "examples"))
    mkpath(joinpath(root, "benchmark"))
    write(joinpath(root, "src", "Example.jl"), "module Example\nend\n")
    write(
        joinpath(root, "docs", "Project.toml"),
        """
        [deps]
        Documenter = "e30172f5-a6a5-5a46-863b-614d45cd2de4"
        """,
    )
    write(joinpath(root, "docs", "make.jl"), "using Documenter\nmakedocs()\n")
    write(joinpath(root, "examples", "Project.toml"), "[deps]\n")
    write(joinpath(root, "examples", "runexamples.jl"), "println(\"example\")\n")
    write(joinpath(root, "benchmark", "runbenchmarks.jl"), "println(\"benchmark\")\n")

    report = run_julia_project_harness(root)
    scope = report.project_resolution

    @test AspJulia.is_clean(report)
    @test scope.package_paths == sort!(
        [
            joinpath(root, "benchmark"),
            joinpath(root, "docs"),
            joinpath(root, "examples"),
        ],
    )
    @test !any(file -> startswith(file.path, joinpath(root, "docs")), report.files)
    @test !any(file -> startswith(file.path, joinpath(root, "examples")), report.files)
    @test !any(file -> startswith(file.path, joinpath(root, "benchmark")), report.files)
end

@testset "project runner captures Project.toml dependency facts" begin
    root = mktempdir()
    write(
        joinpath(root, "Project.toml"),
        """
        name = "Example"
        uuid = "11111111-1111-1111-1111-111111111111"
        version = "0.1.0"

        [deps]
        JSON = "682c06a0-de6a-54ab-a142-c8b1cf79cde6"
        JuliaSyntax = "70703baa-626e-46a2-a12c-08ffd08c73b4"

        [weakdeps]
        WeakThing = "22222222-2222-2222-2222-222222222222"

        [extras]
        Test = "8dfed614-e22c-5e08-85e1-65c5234f0b40"

        [targets]
        test = ["Test"]

        [compat]
        JSON = "1"
        WeakThing = "1"

        [sources]
        JuliaSyntax = {url = "https://github.com/JuliaLang/JuliaSyntax.jl", rev = "a713779e3a8dbf1fe03c659009dab6eb006cbb31"}

        [extensions]
        ExampleWeakExt = "WeakThing"
        """,
    )
    mkpath(joinpath(root, "src"))
    write(joinpath(root, "src", "Example.jl"), "module Example\nend\n")
    mkpath(joinpath(root, "ext"))
    write(joinpath(root, "ext", "ExampleWeakExt.jl"), "module ExampleWeakExt\nend\n")

    report = run_julia_project_harness(root)
    scope = report.project_resolution

    @test AspJulia.is_clean(report)
    @test scope.package_uuid == "11111111-1111-1111-1111-111111111111"
    @test scope.direct_dependencies["JSON"] == "682c06a0-de6a-54ab-a142-c8b1cf79cde6"
    @test scope.direct_dependencies["JuliaSyntax"] == "70703baa-626e-46a2-a12c-08ffd08c73b4"
    @test scope.weak_dependencies["WeakThing"] == "22222222-2222-2222-2222-222222222222"
    @test scope.extra_dependencies["Test"] == "8dfed614-e22c-5e08-85e1-65c5234f0b40"
    @test scope.targets["test"] == ["Test"]
    @test scope.compat["JSON"] == "1"
    @test scope.compat["WeakThing"] == "1"
    @test scope.sources["JuliaSyntax"]["rev"] == "a713779e3a8dbf1fe03c659009dab6eb006cbb31"
    @test scope.extensions["ExampleWeakExt"] == ["WeakThing"]
    @test isempty(scope.source_dependency_projects)
    @test scope.extension_paths == [joinpath(root, "ext")]
end

@testset "project runner accepts stdlib and source-tracked deps without compat" begin
    root = mktempdir()
    write(
        joinpath(root, "Project.toml"),
        """
        name = "Example"
        uuid = "11111111-1111-1111-1111-111111111111"
        version = "0.1.0"

        [deps]
        JuliaSyntax = "70703baa-626e-46a2-a12c-08ffd08c73b4"
        Pkg = "44cfe95a-1eb2-52ea-b672-e2afdf69b78f"

        [sources]
        JuliaSyntax = {url = "https://github.com/JuliaLang/JuliaSyntax.jl", rev = "a713779e3a8dbf1fe03c659009dab6eb006cbb31"}
        """,
    )
    mkpath(joinpath(root, "src"))
    write(joinpath(root, "src", "Example.jl"), "module Example\nusing JuliaSyntax\nusing Pkg\nend\n")

    report = run_julia_project_harness(root)

    @test AspJulia.is_clean(report)
end

@testset "project runner captures and scans package extensions" begin
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
    mkpath(joinpath(root, "ext"))
    write(joinpath(root, "src", "Example.jl"), "module Example\nend\n")
    write(joinpath(root, "ext", "ExampleJSONExt.jl"), "module ExampleJSONExt\nusing Example\nusing JSON\nend\n")

    report = run_julia_project_harness(root)
    snapshot = render_julia_project_harness_agent_snapshot(root)

    @test AspJulia.is_clean(report)
    @test any(file -> file.path == joinpath(root, "ext", "ExampleJSONExt.jl"), report.files)
    @test report.project_resolution.extensions["ExampleJSONExt"] == ["JSON"]
    @test occursin("Files: source=1 test=0 ext=1", snapshot)
    @test occursin("extensions=ExampleJSONExt=JSON", snapshot)
    @test occursin("ext/ExampleJSONExt.jl module=ExampleJSONExt", snapshot)
end

@testset "project runner accepts optional Moshi extension imports" begin
    root = mktempdir()
    write(
        joinpath(root, "Project.toml"),
        """
        name = "Example"
        uuid = "11111111-1111-1111-1111-111111111111"
        version = "0.1.0"

        [weakdeps]
        Moshi = "2e0e35c7-a2e4-4343-998d-7ef72827ed2d"

        [compat]
        Moshi = "0.3"

        [extensions]
        ExampleMoshiExt = "Moshi"
        """,
    )
    mkpath(joinpath(root, "src"))
    mkpath(joinpath(root, "ext"))
    write(joinpath(root, "src", "Example.jl"), "module Example\nend\n")
    write(
        joinpath(root, "ext", "ExampleMoshiExt.jl"),
        """
        module ExampleMoshiExt
        using Example
        using Moshi.Data: @data

        @data Mode begin
            Fast
            Safe
        end
        end
        """,
    )

    report = run_julia_project_harness(root)
    snapshot = render_julia_project_harness_agent_snapshot(root)

    @test AspJulia.is_clean(report)
    @test occursin("weakdeps=Moshi", snapshot)
    @test occursin("extensions=ExampleMoshiExt=Moshi", snapshot)
    @test occursin("Moshi:", snapshot)
    @test occursin(
        "extension=ExampleMoshiExt weakdeps=Moshi activation=missing_test_target capabilities=syntax,domain-model,search",
        snapshot,
    )
    @test occursin("ext/ExampleMoshiExt.jl @data=Mode", snapshot)
end

@testset "project runner ignores ext files without Pkg extensions" begin
    root = mktempdir()
    write_project(root, "Example")
    mkpath(joinpath(root, "src"))
    mkpath(joinpath(root, "ext"))
    write(joinpath(root, "src", "Example.jl"), "module Example\nend\n")
    write(joinpath(root, "ext", "LooseExt.jl"), "module LooseExt\nusing MissingPkg\nend\n")

    report = run_julia_project_harness(root)

    @test AspJulia.is_clean(report)
    @test isempty(report.project_resolution.extension_paths)
    @test !any(file -> file.path == joinpath(root, "ext", "LooseExt.jl"), report.files)
end

@testset "project runner reports weakdep imports outside extensions" begin
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
    mkpath(joinpath(root, "ext"))
    write(joinpath(root, "src", "Example.jl"), "module Example\nusing JSON\nend\n")
    write(joinpath(root, "ext", "ExampleJSONExt.jl"), "module ExampleJSONExt\nusing JSON\nend\n")

    report = run_julia_project_harness(root)
    rendered = render_julia_project_harness(report)

    @test !AspJulia.is_clean(report)
    @test occursin("JULIA-AGENT-PROJECT-008", rendered)
    @test occursin("Imported package is missing from Project.toml", rendered)
    @test count(finding -> finding.rule_id == "JULIA-AGENT-PROJECT-008", report.findings) == 1
end

@testset "project runner evaluates local Pkg source dependency scopes" begin
    root = mktempdir()
    write(
        joinpath(root, "Project.toml"),
        """
        name = "Root"
        uuid = "11111111-1111-1111-1111-111111111111"
        version = "0.1.0"

        [deps]
        LocalDep = "22222222-2222-2222-2222-222222222222"

        [sources]
        LocalDep = {path = "deps/LocalDep"}
        """,
    )
    mkpath(joinpath(root, "src"))
    mkpath(joinpath(root, "deps", "LocalDep", "src"))
    write(joinpath(root, "src", "Root.jl"), "module Root\nusing LocalDep\nend\n")
    write_project(joinpath(root, "deps", "LocalDep"), "LocalDep")
    write(
        joinpath(root, "deps", "LocalDep", "src", "LocalDep.jl"),
        "module LocalDep\nusing JSON\nend\n",
    )

    report = run_julia_project_harness(root)
    rendered = render_julia_project_harness(report)

    @test !AspJulia.is_clean(report)
    @test report.project_resolution.source_dependency_projects == ["deps/LocalDep"]
    @test length(report.workspace_member_scopes) == 1
    @test only(report.workspace_member_scopes).package_name == "LocalDep"
    @test occursin("JULIA-AGENT-PROJECT-008", rendered)
    @test occursin("deps/LocalDep/src/LocalDep.jl", rendered)
end

@testset "project runner captures workspace member scopes" begin
    root = mktempdir()
    write(
        joinpath(root, "Project.toml"),
        """
        name = "Root"
        uuid = "11111111-1111-1111-1111-111111111111"
        version = "0.1.0"

        [workspace]
        projects = ["packages/Member"]
        """,
    )
    mkpath(joinpath(root, "src"))
    mkpath(joinpath(root, "packages", "Member", "src"))
    write(joinpath(root, "src", "Root.jl"), "module Root\nend\n")
    write_project(joinpath(root, "packages", "Member"), "Member")
    write(joinpath(root, "packages", "Member", "src", "Member.jl"), "module Member\nend\n")

    report = run_julia_project_harness(root)
    snapshot = render_julia_project_harness_agent_snapshot(root)

    @test AspJulia.is_clean(report)
    @test length(report.workspace_member_scopes) == 1
    @test only(report.workspace_member_scopes).package_name == "Member"
    @test occursin("Workspace:", snapshot)
    @test occursin("Member root=packages/Member entry=packages/Member/src/Member.jl", snapshot)
end

@testset "project runner evaluates workspace members with member deps" begin
    root = mktempdir()
    write(
        joinpath(root, "Project.toml"),
        """
        name = "Root"
        uuid = "11111111-1111-1111-1111-111111111111"
        version = "0.1.0"

        [deps]
        JSON = "682c06a0-de6a-54ab-a142-c8b1cf79cde6"

        [workspace]
        projects = ["packages/Member"]
        """,
    )
    mkpath(joinpath(root, "src"))
    mkpath(joinpath(root, "packages", "Member", "src"))
    write(joinpath(root, "src", "Root.jl"), "module Root\nusing JSON\nend\n")
    write_project(joinpath(root, "packages", "Member"), "Member")
    write(
        joinpath(root, "packages", "Member", "src", "Member.jl"),
        "module Member\nusing JSON\nend\n",
    )

    report = run_julia_project_harness(root)
    rendered = render_julia_project_harness(report)

    @test !AspJulia.is_clean(report)
    @test occursin("JULIA-AGENT-PROJECT-008", rendered)
    @test count(finding -> finding.rule_id == "JULIA-AGENT-PROJECT-008", report.findings) == 1
    @test occursin("packages/Member/src/Member.jl", rendered)
end

@testset "project runner reports undeclared package extension dependencies" begin
    root = mktempdir()
    write(
        joinpath(root, "Project.toml"),
        """
        name = "Example"
        uuid = "11111111-1111-1111-1111-111111111111"
        version = "0.1.0"

        [extensions]
        ExampleJSONExt = "JSON"
        """,
    )
    mkpath(joinpath(root, "src"))
    mkpath(joinpath(root, "ext"))
    write(joinpath(root, "src", "Example.jl"), "module Example\nend\n")
    write(joinpath(root, "ext", "ExampleJSONExt.jl"), "module ExampleJSONExt\nusing JSON\nend\n")

    report = run_julia_project_harness(root)
    rendered = render_julia_project_harness(report)

    @test !AspJulia.is_clean(report)
    @test occursin("JULIA-AGENT-PROJECT-012", rendered)
    @test occursin("Project extension dependency is undeclared", rendered)
    @test count(finding -> finding.rule_id == "JULIA-AGENT-PROJECT-012", report.findings) == 1
    @test count(finding -> finding.rule_id == "JULIA-AGENT-PROJECT-008", report.findings) == 0
end
