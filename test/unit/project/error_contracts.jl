@testset "project runner reports public failure contract advice" begin
    root = mktempdir()
    write_project(root, "Example")
    mkpath(joinpath(root, "src"))
    write(
        joinpath(root, "src", "Example.jl"),
        """
        module Example
        export parse_payload
        \"\"\"Parse the payload text.\"\"\"
        function parse_payload(text)
            isempty(text) && error("empty payload")
            text
        end
        end
        """,
    )

    report = run_julia_project_harness(root)
    rendered = render_julia_project_harness(report)

    @test AspJulia.is_clean(report)
    @test occursin("AGENT-JL-R026", rendered)
    @test occursin("Public failure path lacks a contract", rendered)
    @test occursin("failure paths without a failure contract: error", rendered)
    @test length(AspJulia.advisory_findings(report)) == 1
end

@testset "project runner reports public assertion contract advice" begin
    root = mktempdir()
    write_project(root, "Example")
    mkpath(joinpath(root, "src"))
    write(
        joinpath(root, "src", "Example.jl"),
        """
        module Example
        export normalize
        \"\"\"Normalize a positive value.\"\"\"
        function normalize(value)
            @assert value > 0
            value
        end
        end
        """,
    )

    report = run_julia_project_harness(root)
    rendered = render_julia_project_harness(report)

    @test AspJulia.is_clean(report)
    @test occursin("AGENT-JL-R026", rendered)
    @test occursin("failure paths without a failure contract: @assert", rendered)
    @test length(AspJulia.advisory_findings(report)) == 1
end

@testset "project runner reports documented public failure contract without test" begin
    root = mktempdir()
    write_project(root, "Example")
    mkpath(joinpath(root, "src"))
    write(
        joinpath(root, "src", "Example.jl"),
        """
        module Example
        export parse_payload
        \"\"\"Parse the payload text.

        Throws `ArgumentError` when the payload is empty.
        \"\"\"
        function parse_payload(text)
            isempty(text) && throw(ArgumentError("empty payload"))
            text
        end
        end
        """,
    )

    report = run_julia_project_harness(root)
    rendered = render_julia_project_harness(report)

    @test AspJulia.is_clean(report)
    @test occursin("AGENT-JL-R027", rendered)
    @test occursin("Public failure contract lacks a test", rendered)
    @test occursin("lacks a parser-visible `@test_throws` call", rendered)
    @test occursin("Detected covered methods: none", rendered)
    @test occursin("@test_throws ExceptionType parse_payload(...)", rendered)
    @test length(AspJulia.advisory_findings(report)) == 1
end

@testset "project runner accepts documented public failure contract test" begin
    root = mktempdir()
    write_project(root, "Example")
    mkpath(joinpath(root, "src"))
    mkpath(joinpath(root, "test"))
    write(
        joinpath(root, "src", "Example.jl"),
        """
        module Example
        export parse_payload
        \"\"\"Parse the payload text.

        Throws `ArgumentError` when the payload is empty.
        \"\"\"
        function parse_payload(text)
            isempty(text) && throw(ArgumentError("empty payload"))
            text
        end
        end
        """,
    )
    write(
        joinpath(root, "test", "runtests.jl"),
        """
        using Test
        using Example

        @test_throws ArgumentError parse_payload("")
        """,
    )

    report = run_julia_project_harness(root)

    @test AspJulia.is_clean(report)
    @test isempty(AspJulia.advisory_findings(report))
end

@testset "project runner accepts direct parser-visible failure tests in included files" begin
    root = mktempdir()
    write_project(root, "Example")
    mkpath(joinpath(root, "src"))
    mkpath(joinpath(root, "test"))
    write(
        joinpath(root, "src", "Example.jl"),
        """
        module Example
        export parse_payload
        \"\"\"Parse the payload text.

        Throws `ArgumentError` when the payload is empty.
        \"\"\"
        function parse_payload(text)
            isempty(text) && throw(ArgumentError("empty payload"))
            text
        end
        end
        """,
    )
    write(
        joinpath(root, "test", "runtests.jl"),
        """
        using Test
        using Example
        include("failure_contracts.jl")
        """,
    )
    write(
        joinpath(root, "test", "failure_contracts.jl"),
        """
        @test_throws ArgumentError parse_payload("")
        """,
    )

    report = run_julia_project_harness(root)

    @test AspJulia.is_clean(report)
    @test isempty(AspJulia.advisory_findings(report))
end
