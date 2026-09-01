@testset "project runner reports include graph findings" begin
    root = mktempdir()
    write_project(root, "Example")
    mkpath(joinpath(root, "src"))
    write(
        joinpath(root, "src", "Example.jl"),
        """
        module Example
        include("missing.jl")
        include(path)
        end
        """,
    )
    write(joinpath(root, "src", "orphan.jl"), "value() = 1\n")

    report = run_julia_project_harness(root)
    rendered = render_julia_project_harness(report)

    @test !AspJulia.is_clean(report)
    @test occursin("JULIA-MOD-R003", rendered)
    @test occursin("Dynamic include hides source graph", rendered)
    @test occursin("JULIA-MOD-R004", rendered)
    @test occursin("Literal include target is missing", rendered)
    @test occursin("JULIA-MOD-R006", rendered)
    @test occursin("Source file is orphaned from package entry", rendered)
end

@testset "project runner reports large package entry facade" begin
    root = mktempdir()
    write_project(root, "Example")
    mkpath(joinpath(root, "src"))
    body = join(["value$(index) = $(index)" for index in 1:121], "\n")
    write(joinpath(root, "src", "Example.jl"), "module Example\n$(body)\nend\n")

    report = run_julia_project_harness(root)
    rendered = render_julia_project_harness(report)

    @test !AspJulia.is_clean(report)
    @test occursin("JULIA-MOD-R001", rendered)
    @test occursin("Package entry file is too large for a facade", rendered)
    @test count(finding -> finding.rule_id == "JULIA-MOD-R001", report.findings) == 1
end

@testset "project runner reports large source owner file" begin
    root = mktempdir()
    write_project(root, "Example")
    mkpath(joinpath(root, "src"))
    body = join(["value$(index)() = $(index)" for index in 1:401], "\n")
    write(joinpath(root, "src", "Example.jl"), "module Example\ninclude(\"api.jl\")\nend\n")
    write(joinpath(root, "src", "api.jl"), "$(body)\n")

    report = run_julia_project_harness(root)
    rendered = render_julia_project_harness(report)

    @test !AspJulia.is_clean(report)
    @test occursin("JULIA-MOD-R002", rendered)
    @test occursin("Julia owner file exceeds the owner budget", rendered)
    @test count(finding -> finding.rule_id == "JULIA-MOD-R002", report.findings) == 1
end

@testset "project runner reports large test owner file" begin
    root = mktempdir()
    write_project(root, "Example")
    mkpath(joinpath(root, "src"))
    mkpath(joinpath(root, "test", "unit"))
    body = join(["@test $(index) == $(index)" for index in 1:401], "\n")
    write(joinpath(root, "src", "Example.jl"), "module Example\nend\n")
    write(joinpath(root, "test", "runtests.jl"), "using Test\ninclude(\"unit/api.jl\")\n")
    write(joinpath(root, "test", "unit", "api.jl"), "$(body)\n")

    report = run_julia_project_harness(root)
    rendered = render_julia_project_harness(report)

    @test !AspJulia.is_clean(report)
    @test occursin("JULIA-MOD-R002", rendered)
    @test occursin("Julia owner file exceeds the owner budget", rendered)
    @test occursin("split this test owner", rendered)
    @test count(finding -> finding.rule_id == "JULIA-MOD-R002", report.findings) == 1
end

@testset "project runner reports large extension owner file" begin
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
    body = join(["value$(index)() = $(index)" for index in 1:401], "\n")
    write(joinpath(root, "src", "Example.jl"), "module Example\nend\n")
    write(joinpath(root, "ext", "ExampleJSONExt.jl"), "module ExampleJSONExt\n$(body)\nend\n")

    report = run_julia_project_harness(root)
    rendered = render_julia_project_harness(report)

    @test !AspJulia.is_clean(report)
    @test occursin("JULIA-MOD-R002", rendered)
    @test occursin("Julia owner file exceeds the owner budget", rendered)
    @test occursin("split this extension owner", rendered)
    @test count(finding -> finding.rule_id == "JULIA-MOD-R002", report.findings) == 1
end

@testset "project runner reports generic source owner buckets" begin
    root = mktempdir()
    write_project(root, "Example")
    mkpath(joinpath(root, "src", "utils"))
    write(joinpath(root, "src", "Example.jl"), "module Example\ninclude(\"utils/helpers.jl\")\nend\n")
    write(joinpath(root, "src", "utils", "helpers.jl"), "value() = 1\n")

    report = run_julia_project_harness(root)
    rendered = render_julia_project_harness(report)

    @test !AspJulia.is_clean(report)
    @test occursin("JULIA-MOD-R007", rendered)
    @test occursin("Source path uses a generic owner bucket", rendered)
    @test count(finding -> finding.rule_id == "JULIA-MOD-R007", report.findings) == 1
end

@testset "project runner reports literal include cycles" begin
    root = mktempdir()
    write_project(root, "Example")
    mkpath(joinpath(root, "src"))
    write(joinpath(root, "src", "Example.jl"), "module Example\ninclude(\"a.jl\")\nend\n")
    write(joinpath(root, "src", "a.jl"), "include(\"b.jl\")\n")
    write(joinpath(root, "src", "b.jl"), "include(\"a.jl\")\n")

    report = run_julia_project_harness(root)
    rendered = render_julia_project_harness(report)

    @test !AspJulia.is_clean(report)
    @test occursin("JULIA-MOD-R005", rendered)
    @test occursin("Literal include graph contains a cycle", rendered)
    @test count(finding -> finding.rule_id == "JULIA-MOD-R005", report.findings) == 1
end
