@testset "project runner reports public return annotation contract advice" begin
    root = mktempdir()
    write_project(root, "Example")
    mkpath(joinpath(root, "src"))
    write(
        joinpath(root, "src", "Example.jl"),
        """
        module Example
        export encode
        \"\"\"Encode the public payload for wire transport.\"\"\"
        encode(payload)::String = string(payload)
        end
        """,
    )

    report = run_julia_project_harness(root)
    rendered = render_julia_project_harness(report)

    @test AspJulia.is_clean(report)
    @test occursin("AGENT-JL-R023", rendered)
    @test occursin("Public return annotation lacks a contract", rendered)
    @test occursin("concrete return annotation `::String`", rendered)
    @test length(AspJulia.advisory_findings(report)) == 1
end

@testset "project runner reports documented public return contract without inferred test" begin
    root = mktempdir()
    write_project(root, "Example")
    mkpath(joinpath(root, "src"))
    write(
        joinpath(root, "src", "Example.jl"),
        """
        module Example
        export encode
        \"\"\"Return contract: returns a String payload for the wire format.\"\"\"
        encode(payload)::String = string(payload)
        end
        """,
    )

    report = run_julia_project_harness(root)
    rendered = render_julia_project_harness(report)

    @test AspJulia.is_clean(report)
    @test occursin("AGENT-JL-R031", rendered)
    @test occursin("Public return contract lacks an inferred test", rendered)
    @test occursin("return/type-stability contract `::String`", rendered)
    @test length(AspJulia.advisory_findings(report)) == 1
end

@testset "project runner accepts inferred public return contract test" begin
    root = mktempdir()
    write_project(root, "Example")
    mkpath(joinpath(root, "src"))
    mkpath(joinpath(root, "test"))
    write(
        joinpath(root, "src", "Example.jl"),
        """
        module Example
        export encode
        \"\"\"Return contract: returns a String payload for the wire format.\"\"\"
        encode(payload)::String = string(payload)
        end
        """,
    )
    write(
        joinpath(root, "test", "runtests.jl"),
        """
        using Test
        using Example

        @testset "return contract" begin
            @inferred encode(:payload)
        end
        """,
    )

    report = run_julia_project_harness(root)

    @test AspJulia.is_clean(report)
    @test isempty(AspJulia.advisory_findings(report))
end

@testset "project runner accepts generic type parameter return annotations" begin
    root = mktempdir()
    write_project(root, "Example")
    mkpath(joinpath(root, "src"))
    write(
        joinpath(root, "src", "Example.jl"),
        """
        module Example
        export passthrough
        \"\"\"Return the value without changing its concrete type.\"\"\"
        passthrough(value::T)::T where {T} = value
        end
        """,
    )

    report = run_julia_project_harness(root)
    rendered = render_julia_project_harness(report)

    @test AspJulia.is_clean(report)
    @test !occursin("AGENT-JL-R023", rendered)
end
