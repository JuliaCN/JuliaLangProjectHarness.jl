@testset "project runner reports mutable global state advice" begin
    root = mktempdir()
    write_project(root, "Example")
    mkpath(joinpath(root, "src"))
    write(
        joinpath(root, "src", "Example.jl"),
        """
        module Example
        CACHE = Dict{String,Int}()
        end
        """,
    )

    report = run_julia_project_harness(root)
    rendered = render_julia_project_harness(report)

    @test AspJulia.is_clean(report)
    @test occursin("AGENT-JL-R024", rendered)
    @test occursin("Package source owns mutable global state", rendered)
    @test occursin("mutable global binding `CACHE`", rendered)
    @test length(AspJulia.advisory_findings(report)) == 1
end

@testset "project runner reports explicit global mutable state advice" begin
    root = mktempdir()
    write_project(root, "Example")
    mkpath(joinpath(root, "src"))
    write(
        joinpath(root, "src", "Example.jl"),
        """
        module Example
        global STATE = Ref(0)
        end
        """,
    )

    report = run_julia_project_harness(root)
    rendered = render_julia_project_harness(report)

    @test AspJulia.is_clean(report)
    @test occursin("AGENT-JL-R024", rendered)
    @test occursin("mutable global binding `STATE`", rendered)
    @test length(AspJulia.advisory_findings(report)) == 1
end

@testset "project runner accepts const mutable state handles" begin
    root = mktempdir()
    write_project(root, "Example")
    mkpath(joinpath(root, "src"))
    write(
        joinpath(root, "src", "Example.jl"),
        """
        module Example
        const CACHE = Dict{String,Int}()
        end
        """,
    )

    report = run_julia_project_harness(root)

    @test AspJulia.is_clean(report)
    @test isempty(AspJulia.advisory_findings(report))
end

@testset "project runner ignores mutable global fixtures in tests" begin
    root = mktempdir()
    write_project(root, "Example")
    mkpath(joinpath(root, "src"))
    mkpath(joinpath(root, "test"))
    write(joinpath(root, "src", "Example.jl"), "module Example\nend\n")
    write(
        joinpath(root, "test", "runtests.jl"),
        """
        using Test

        global CACHE = Dict{String,Int}()
        @test isempty(CACHE)
        """,
    )

    report = run_julia_project_harness(root)

    @test AspJulia.is_clean(report)
    @test isempty(AspJulia.advisory_findings(report))
end
