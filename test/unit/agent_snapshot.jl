@testset "agent snapshot" begin
    root = mktempdir()
    write_project(root, "Example")
    open(joinpath(root, "Project.toml"), "a") do io
        write(
            io,
            """

        [deps]
        JSON = "682c06a0-de6a-54ab-a142-c8b1cf79cde6"

        [compat]
        JSON = "1"
        """,
        )
    end
    mkpath(joinpath(root, "src"))
    mkpath(joinpath(root, "test"))
    write(
        joinpath(root, "src", "Example.jl"),
        "module Example\nexport run, Config, DEFAULT_LIMIT\nusing JSON\ninclude(\"api.jl\")\n\"\"\"Runtime configuration.\"\"\"\nstruct Config\nvalue::Int\nmode::Symbol = :fast\nend\n\"\"\"Default limit.\"\"\"\nconst DEFAULT_LIMIT::Int = 8\n\"\"\"Run a value.\"\"\"\nfunction run(value::T)::T where {T}\nif value > zero(T)\nfor item in value:value\n@alpha item\nend\nend\nvalue\nend\nend\n",
    )
    write(joinpath(root, "src", "api.jl"), "internal_api() = 1\n")
    write(
        joinpath(root, "test", "runtests.jl"),
        "using Test\n@testset \"core\" begin\n@test run(1) == 1\n@test run(1.0) == 1.0\nend\n",
    )

    rendered = render_julia_project_harness_agent_snapshot(root)

    @test occursin("Package: Example", rendered)
    @test occursin("Files: source=2 test=1", rendered)
    @test occursin("Entry: src/Example.jl", rendered)
    @test occursin("Project:", rendered)
    @test occursin("extras=Test", rendered)
    @test occursin("targets=test=Test", rendered)
    @test occursin("compat=JSON=1", rendered)
    @test occursin("ReasoningTree:", rendered)
    @test occursin("- root package=Example entry=src/Example.jl", rendered)
    @test occursin(
        "- owner src/Example.jl role=entry modules=Example public=Config,DEFAULT_LIMIT,run imports=JSON includes=src/api.jl types=Config bindings=DEFAULT_LIMIT methods=run",
        rendered,
    )
    @test occursin("- owner src/api.jl role=source methods=internal_api", rendered)
    @test occursin("- owner test/runtests.jl role=test imports=Test tests=\"core\",direct=2", rendered)
    @test occursin("Modules:", rendered)
    @test occursin("src/Example.jl module=Example", rendered)
    @test occursin("Public:", rendered)
    @test occursin("export=run", rendered)
    @test occursin("Imports:", rendered)
    @test occursin("using=JSON", rendered)
    @test occursin("Types:", rendered)
    @test occursin("struct=Config fields=2 typed=2 defaults=1", rendered)
    @test occursin("Bindings:", rendered)
    @test occursin("const=DEFAULT_LIMIT::Int", rendered)
    @test occursin("Methods:", rendered)
    @test occursin("function=run/1", rendered)
    @test occursin("typed=1", rendered)
    @test occursin("returns=T", rendered)
    @test occursin("where=1", rendered)
    @test occursin("flow=2", rendered)
    @test occursin("branches=1", rendered)
    @test occursin("loops=1", rendered)
    @test occursin("loop_depth=1", rendered)
    @test occursin("macros=1", rendered)
    @test occursin("Tests:", rendered)
    @test occursin("test/runtests.jl testsets=\"core\" test=2", rendered)
    @test occursin("Verification:", rendered)
    @test occursin("kind=chaos", rendered)
    @test occursin("kind=pkg_test", rendered)
    @test occursin("command=julia --project=. -e", rendered)
    @test occursin("kind=stress", rendered)
    @test occursin("requires=scenario,load_steps,p50_ms,p99_ms,threshold,result", rendered)
    @test occursin("Includes:", rendered)
    @test occursin("src/Example.jl -> src/api.jl", rendered)
    @test !occursin("FindingGroups:", rendered)
end

@testset "agent snapshot sorts source metadata without comparing source tables" begin
    root = mktempdir()
    write_project(root, "Example")
    open(joinpath(root, "Project.toml"), "a") do io
        write(
            io,
            """

        [deps]
        LocalDep = "22222222-2222-2222-2222-222222222222"
        RemoteDep = "33333333-3333-3333-3333-333333333333"

        [sources]
        LocalDep = {path = "deps/LocalDep"}
        RemoteDep = {rev = "abcdef", subdir = "src/SubPackage", url = "https://example.invalid/repo.git"}
        """,
        )
    end
    mkpath(joinpath(root, "src"))
    write(joinpath(root, "src", "Example.jl"), "module Example\nend\n")

    rendered = render_julia_project_harness_agent_snapshot(root)

    @test occursin(
        "sources=LocalDep(path=deps/LocalDep);RemoteDep(rev=abcdef,subdir=src/SubPackage,url=https://example.invalid/repo.git)",
        rendered,
    )
end

@testset "agent snapshot verification includes benchmark gates" begin
    root = mktempdir()
    write_project(root, "Example")
    mkpath(joinpath(root, "src"))
    mkpath(joinpath(root, "benchmark"))
    write(
        joinpath(root, "src", "Example.jl"),
        """
        module Example
        export run
        \"\"\"Run a value.\"\"\"
        run(value) = value
        end
        """,
    )
    write(
        joinpath(root, "benchmark", "Project.toml"),
        """
        [deps]
        BenchmarkTools = "6e4b80f9-dd2c-5a6d-8f14-7f3c1d9e8f4a"
        """,
    )
    write(joinpath(root, "benchmark", "runbenchmarks.jl"), "println(\"benchmark\")\n")

    rendered = render_julia_project_harness_agent_snapshot(root)

    @test occursin("Verification:", rendered)
    @test occursin("kind=performance", rendered)
    @test occursin("owner=benchmark/runbenchmarks.jl", rendered)
    @test occursin("command=julia --project=benchmark -e", rendered)
    @test occursin("evidence=benchmark_project=benchmark/Project.toml", rendered)
    @test occursin("entry=benchmark/runbenchmarks.jl", rendered)
    @test occursin("requires=benchmark_command,baseline,regression_threshold", rendered)
end

@testset "agent snapshot includes package auxiliary syntax context" begin
    root = mktempdir()
    write_project(root, "Example")
    mkpath(joinpath(root, "src"))
    mkpath(joinpath(root, "docs"))
    mkpath(joinpath(root, "examples"))
    write(joinpath(root, "src", "Example.jl"), "module Example\nexport run\nrun(x) = x\nend\n")
    write(
        joinpath(root, "docs", "Project.toml"),
        """
        [deps]
        Documenter = "e30172f5-a6a5-5a46-863b-614d45cd2de4"
        """,
    )
    write(
        joinpath(root, "docs", "make.jl"),
        "using Documenter\nfunction build_docs()\n    makedocs()\nend\n",
    )
    write(joinpath(root, "examples", "Project.toml"), "[deps]\n")
    write(
        joinpath(root, "examples", "runexamples.jl"),
        "using Example\nscripted_example() = run(1)\n",
    )

    rendered = render_julia_project_harness_agent_snapshot(root)

    @test occursin("Files: source=1 test=0 package=2", rendered)
    @test occursin("- owner docs/make.jl role=docs imports=Documenter methods=build_docs", rendered)
    @test occursin("- owner examples/runexamples.jl role=example imports=Example", rendered)
    @test occursin("docs/make.jl function=build_docs/0", rendered)
    @test occursin("examples/runexamples.jl function=scripted_example/0", rendered)
    @test !occursin("JULIA-AGENT-PROJECT-008", rendered)
end

@testset "agent snapshot finding groups" begin
    root = mktempdir()
    write_project(root, "Example")
    mkpath(joinpath(root, "src"))
    write(joinpath(root, "src", "Example.jl"), "module Example\ninclude(path)\nend\n")

    rendered = render_julia_project_harness_agent_snapshot(root)

    @test occursin("DynamicIncludes:", rendered)
    @test occursin("include(path)", rendered)
    @test occursin("FindingGroups:", rendered)
    @test occursin("JULIA-MOD-R003 count=1", rendered)
end

@testset "agent snapshot rejects missing project root" begin
    missing = joinpath(mktempdir(), "missing")

    @test_throws ErrorException render_julia_project_harness_agent_snapshot(missing)
end
