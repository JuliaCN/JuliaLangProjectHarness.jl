@testset "project runner reports public abstract field type advice" begin
    root = mktempdir()
    write_project(root, "Example")
    mkpath(joinpath(root, "src"))
    write(
        joinpath(root, "src", "Example.jl"),
        """
        module Example
        export Payload
        \"\"\"Payload data shape.\"\"\"
        struct Payload
            value::Any
            handler::Function
        end
        end
        """,
    )

    report = run_julia_project_harness(root)
    rendered = render_julia_project_harness(report)

    @test AspJulia.is_clean(report)
    @test occursin("AGENT-JL-R025", rendered)
    @test occursin("Public type has broadly abstract fields", rendered)
    @test occursin("value::Any, handler::Function", rendered)
    @test length(AspJulia.advisory_findings(report)) == 1
end

@testset "project runner reports nested public abstract field type advice" begin
    root = mktempdir()
    write_project(root, "Example")
    mkpath(joinpath(root, "src"))
    write(
        joinpath(root, "src", "Example.jl"),
        """
        module Example
        export Payload
        \"\"\"Payload data shape.\"\"\"
        struct Payload
            scores::Vector{<:Real}
        end
        end
        """,
    )

    report = run_julia_project_harness(root)
    rendered = render_julia_project_harness(report)

    @test AspJulia.is_clean(report)
    @test occursin("AGENT-JL-R025", rendered)
    @test occursin("scores::Vector{<:Real}", rendered)
    @test length(AspJulia.advisory_findings(report)) == 1
end

@testset "project runner accepts concrete and parameterized public fields" begin
    root = mktempdir()
    write_project(root, "Example")
    mkpath(joinpath(root, "src"))
    write(
        joinpath(root, "src", "Example.jl"),
        """
        module Example
        export Payload
        \"\"\"Payload data shape.\"\"\"
        struct Payload{T}
            value::T
            labels::Vector{String}
        end
        end
        """,
    )

    report = run_julia_project_harness(root)

    @test AspJulia.is_clean(report)
    @test isempty(AspJulia.advisory_findings(report))
end
