@testset "project runner reports public mutation contract without test" begin
    root = mktempdir()
    write_project(root, "Example")
    mkpath(joinpath(root, "src"))
    write(
        joinpath(root, "src", "Example.jl"),
        """
        module Example
        export normalize!
        \"\"\"Normalize values in place.

        Mutation contract: mutates `values` and returns the same collection.
        \"\"\"
        function normalize!(values)
            values ./= maximum(values)
            values
        end
        end
        """,
    )

    report = run_julia_project_harness(root)
    rendered = render_julia_project_harness(report)

    @test AspJulia.is_clean(report)
    @test occursin("AGENT-JL-R028", rendered)
    @test occursin("Public mutation contract lacks a test", rendered)
    @test occursin("mutating method `normalize!`", rendered)
    @test length(AspJulia.advisory_findings(report)) == 1
end

@testset "project runner accepts public mutation contract test" begin
    root = mktempdir()
    write_project(root, "Example")
    mkpath(joinpath(root, "src"))
    mkpath(joinpath(root, "test"))
    write(
        joinpath(root, "src", "Example.jl"),
        """
        module Example
        export normalize!
        \"\"\"Normalize values in place.

        Mutation contract: mutates `values` and returns the same collection.
        \"\"\"
        function normalize!(values)
            values ./= maximum(values)
            values
        end
        end
        """,
    )
    write(
        joinpath(root, "test", "runtests.jl"),
        """
        using Test
        using Example

        values = [1.0, 2.0]
        @test normalize!(values) === values
        @test values == [0.5, 1.0]
        """,
    )

    report = run_julia_project_harness(root)

    @test AspJulia.is_clean(report)
    @test isempty(AspJulia.advisory_findings(report))
end
