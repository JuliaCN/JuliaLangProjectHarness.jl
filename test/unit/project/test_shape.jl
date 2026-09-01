@testset "project runner reports nested testset shape advice" begin
    root = mktempdir()
    write_project(root, "Example")
    mkpath(joinpath(root, "src"))
    mkpath(joinpath(root, "test"))
    write(
        joinpath(root, "src", "Example.jl"),
        """
        module Example
        export run
        \"\"\"Run one public value.\"\"\"
        run(value) = value
        end
        """,
    )
    write(
        joinpath(root, "test", "runtests.jl"),
        """
        using Test
        using Example

        @testset "matrix scenarios" begin
            for group in ([1, 2], [3, 4])
                for value in group
                    if value > 0
                        @test run(value) == value
                    end
                end
            end
        end
        """,
    )

    report = run_julia_project_harness(root)
    rendered = render_julia_project_harness(report)

    @test AspJulia.is_clean(report)
    @test occursin("AGENT-JL-R029", rendered)
    @test occursin("Testset nests scenario scaffolding", rendered)
    @test occursin("control-flow depth=3, branches=1, loops=2, loop_depth=2", rendered)
    @test length(AspJulia.advisory_findings(report)) == 1
end

@testset "project runner accepts named flat test scenarios" begin
    root = mktempdir()
    write_project(root, "Example")
    mkpath(joinpath(root, "src"))
    mkpath(joinpath(root, "test"))
    write(
        joinpath(root, "src", "Example.jl"),
        """
        module Example
        export run
        \"\"\"Run one public value.\"\"\"
        run(value) = value
        end
        """,
    )
    write(
        joinpath(root, "test", "runtests.jl"),
        """
        using Test
        using Example

        @testset "positive scalar" begin
            @test run(1) == 1
        end

        @testset "positive vector samples" begin
            @test run(2) == 2
            @test run(3) == 3
        end
        """,
    )

    report = run_julia_project_harness(root)

    @test AspJulia.is_clean(report)
    @test isempty(AspJulia.advisory_findings(report))
end
