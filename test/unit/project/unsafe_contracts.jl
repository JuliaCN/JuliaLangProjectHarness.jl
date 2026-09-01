@testset "project runner reports unsafe construct contract advice" begin
    root = mktempdir()
    write_project(root, "Example")
    mkpath(joinpath(root, "src"))
    write(
        joinpath(root, "src", "Example.jl"),
        """
        module Example
        export run_safe
        \"\"\"Run the fixed local probe.\"\"\"
        function run_safe(values)
            run(`echo hello`)
            ccall(:clock, Cint, ())
            @inbounds values[1]
        end
        end
        """,
    )

    report = run_julia_project_harness(root)
    rendered = render_julia_project_harness(report)

    @test AspJulia.is_clean(report)
    @test occursin("AGENT-JL-R017", rendered)
    @test occursin("Unsafe construct lacks an evidence contract", rendered)
    @test occursin("external process", rendered)
    @test occursin("`ccall`", rendered)
    @test occursin("`@inbounds`", rendered)
    @test count(
        finding -> finding.rule_id == "AGENT-JL-R017",
        AspJulia.advisory_findings(report),
    ) == 3
end

@testset "project runner reports unsafe construct evidence contract without test" begin
    root = mktempdir()
    write_project(root, "Example")
    mkpath(joinpath(root, "src"))
    write(
        joinpath(root, "src", "Example.jl"),
        """
        module Example
        export run_safe
        \"\"\"Run the fixed local probe.

        Safety contract: the command is fixed, the ABI precondition is stable,
        and focused smoke test evidence verifies the process and bounds path.
        \"\"\"
        function run_safe(values)
            run(`echo hello`)
            ccall(:clock, Cint, ())
            @inbounds values[1]
        end
        end
        """,
    )

    report = run_julia_project_harness(root)
    rendered = render_julia_project_harness(report)

    @test AspJulia.is_clean(report)
    @test occursin("AGENT-JL-R030", rendered)
    @test occursin("Public unsafe evidence contract lacks a test", rendered)
    @test occursin("documents unsafe or performance evidence for @inbounds, ccall, run", rendered)
    @test length(AspJulia.advisory_findings(report)) == 1
end

@testset "project runner accepts unsafe construct evidence contract test" begin
    root = mktempdir()
    write_project(root, "Example")
    mkpath(joinpath(root, "src"))
    mkpath(joinpath(root, "test"))
    write(
        joinpath(root, "src", "Example.jl"),
        """
        module Example
        export run_safe
        \"\"\"Run the fixed local probe.

        Safety contract: the command is fixed, the ABI precondition is stable,
        and focused smoke test evidence verifies the process and bounds path.
        \"\"\"
        function run_safe(values)
            run(`echo hello`)
            ccall(:clock, Cint, ())
            @inbounds values[1]
        end
        end
        """,
    )
    write(
        joinpath(root, "test", "runtests.jl"),
        """
        using Test
        using Example

        @testset "safety smoke" begin
            @test run_safe([1]) == 1
        end
        """,
    )

    report = run_julia_project_harness(root)

    @test AspJulia.is_clean(report)
    @test isempty(AspJulia.advisory_findings(report))
end
