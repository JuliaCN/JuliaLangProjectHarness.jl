@testset "project runner reports broad public method advice" begin
    root = mktempdir()
    write_project(root, "Example")
    mkpath(joinpath(root, "src"))
    write(
        joinpath(root, "src", "Example.jl"),
        """
        module Example
        export build
        \"\"\"Build the public value.\"\"\"
        build(a, b, c, d, e) = a
        end
        """,
    )

    report = run_julia_project_harness(root)
    rendered = render_julia_project_harness(report)

    @test AspJulia.is_clean(report)
    @test occursin("AGENT-JL-R002", rendered)
    @test occursin("Public method has a broad positional surface", rendered)
    @test length(AspJulia.advisory_findings(report)) == 1
end

@testset "project runner reports public positional Bool flag advice" begin
    root = mktempdir()
    write_project(root, "Example")
    mkpath(joinpath(root, "src"))
    write(
        joinpath(root, "src", "Example.jl"),
        """
        module Example
        export run
        \"\"\"Run the public value.\"\"\"
        run(force::Bool, dry_run=false; verbose=false) = force && !dry_run
        end
        """,
    )

    report = run_julia_project_harness(root)
    rendered = render_julia_project_harness(report)

    @test AspJulia.is_clean(report)
    @test occursin("AGENT-JL-R003", rendered)
    @test occursin("Public method exposes positional Bool flags", rendered)
    @test length(AspJulia.advisory_findings(report)) == 1
end

@testset "project runner reports public API doc advice" begin
    root = mktempdir()
    write_project(root, "Example")
    mkpath(joinpath(root, "src"))
    write(
        joinpath(root, "src", "Example.jl"),
        """
        module Example
        export run
        run(value) = value
        end
        """,
    )

    report = run_julia_project_harness(root)
    rendered = render_julia_project_harness(report)

    @test AspJulia.is_clean(report)
    @test occursin("AGENT-JL-R001", rendered)
    @test occursin("Public API lacks an intent doc", rendered)
    @test length(AspJulia.advisory_findings(report)) == 1
end

@testset "project runner reports public binding doc advice" begin
    root = mktempdir()
    write_project(root, "Example")
    mkpath(joinpath(root, "src"))
    write(
        joinpath(root, "src", "Example.jl"),
        """
        module Example
        export DEFAULT_LIMIT
        const DEFAULT_LIMIT = 8
        end
        """,
    )

    report = run_julia_project_harness(root)
    rendered = render_julia_project_harness(report)

    @test AspJulia.is_clean(report)
    @test occursin("AGENT-JL-R001", rendered)
    @test occursin("Exported/public binding `DEFAULT_LIMIT`", rendered)
    @test length(AspJulia.advisory_findings(report)) == 1
end

@testset "project runner accepts documented public API" begin
    root = mktempdir()
    write_project(root, "Example")
    mkpath(joinpath(root, "src"))
    write(
        joinpath(root, "src", "Example.jl"),
        """
        module Example
        export run
        \"\"\"Run the public value.\"\"\"
        run(value) = value
        end
        """,
    )

    report = run_julia_project_harness(root)

    @test AspJulia.is_clean(report)
    @test isempty(AspJulia.advisory_findings(report))
end

@testset "project runner accepts documented public binding" begin
    root = mktempdir()
    write_project(root, "Example")
    mkpath(joinpath(root, "src"))
    write(
        joinpath(root, "src", "Example.jl"),
        """
        module Example
        export DEFAULT_LIMIT
        \"\"\"Default public limit.\"\"\"
        const DEFAULT_LIMIT = 8
        end
        """,
    )

    report = run_julia_project_harness(root)

    @test AspJulia.is_clean(report)
    @test isempty(AspJulia.advisory_findings(report))
end

@testset "project runner reports public struct untyped field advice" begin
    root = mktempdir()
    write_project(root, "Example")
    mkpath(joinpath(root, "src"))
    write(
        joinpath(root, "src", "Example.jl"),
        """
        module Example
        export Payload
        \"\"\"Public payload shape.\"\"\"
        struct Payload
            id::Int
            data
            metadata
        end
        end
        """,
    )

    report = run_julia_project_harness(root)
    rendered = render_julia_project_harness(report)

    @test AspJulia.is_clean(report)
    @test occursin("AGENT-JL-R011", rendered)
    @test occursin("Public type has untyped fields", rendered)
    @test occursin("data, metadata", rendered)
    @test length(AspJulia.advisory_findings(report)) == 1
end

@testset "project runner accepts typed public struct fields" begin
    root = mktempdir()
    write_project(root, "Example")
    mkpath(joinpath(root, "src"))
    write(
        joinpath(root, "src", "Example.jl"),
        """
        module Example
        export Payload
        \"\"\"Public payload shape.\"\"\"
        struct Payload
            id::Int
            data::Vector{String}
            metadata::Dict{Symbol,String}
        end
        end
        """,
    )

    report = run_julia_project_harness(root)

    @test AspJulia.is_clean(report)
    @test isempty(AspJulia.advisory_findings(report))
end

@testset "project runner reports public struct stringly field advice" begin
    root = mktempdir()
    write_project(root, "Example")
    mkpath(joinpath(root, "src"))
    write(
        joinpath(root, "src", "Example.jl"),
        """
        module Example
        export Payload
        \"\"\"Public payload shape.\"\"\"
        struct Payload
            id::Int
            mode::String
            category::String
            payload_type::Union{Nothing,String}
        end
        end
        """,
    )

    report = run_julia_project_harness(root)
    rendered = render_julia_project_harness(report)

    @test AspJulia.is_clean(report)
    @test occursin("AGENT-JL-R012", rendered)
    @test occursin("Public type exposes stringly domain fields", rendered)
    @test occursin("mode, category, payload_type", rendered)
    @test length(AspJulia.advisory_findings(report)) == 1
end

@testset "project runner accepts symbol public domain fields" begin
    root = mktempdir()
    write_project(root, "Example")
    mkpath(joinpath(root, "src"))
    write(
        joinpath(root, "src", "Example.jl"),
        """
        module Example
        export Payload
        \"\"\"Public payload shape.\"\"\"
        struct Payload
            id::Int
            mode::Symbol
            status::Symbol
            category::Symbol
        end
        end
        """,
    )

    report = run_julia_project_harness(root)

    @test AspJulia.is_clean(report)
    @test isempty(AspJulia.advisory_findings(report))
end

@testset "project runner reports public mutable type contract advice" begin
    root = mktempdir()
    write_project(root, "Example")
    mkpath(joinpath(root, "src"))
    write(
        joinpath(root, "src", "Example.jl"),
        """
        module Example
        export Cache
        \"\"\"Public cache for computed values.\"\"\"
        mutable struct Cache
            entries::Dict{Symbol,Int}
        end
        end
        """,
    )

    report = run_julia_project_harness(root)
    rendered = render_julia_project_harness(report)

    @test AspJulia.is_clean(report)
    @test occursin("AGENT-JL-R013", rendered)
    @test occursin("Public mutable type lacks a mutation contract", rendered)
    @test occursin("mutable struct `Cache`", rendered)
    @test length(AspJulia.advisory_findings(report)) == 1
end

@testset "project runner accepts public mutable type mutation contract" begin
    root = mktempdir()
    write_project(root, "Example")
    mkpath(joinpath(root, "src"))
    write(
        joinpath(root, "src", "Example.jl"),
        """
        module Example
        export Cache
        \"\"\"Mutable cache.

        Mutation contract: callers own lifecycle and preserve entry invariants.
        \"\"\"
        mutable struct Cache
            entries::Dict{Symbol,Int}
        end
        end
        """,
    )

    report = run_julia_project_harness(root)

    @test AspJulia.is_clean(report)
    @test isempty(AspJulia.advisory_findings(report))
end

@testset "project runner reports public mutating method contract advice" begin
    root = mktempdir()
    write_project(root, "Example")
    mkpath(joinpath(root, "src"))
    write(
        joinpath(root, "src", "Example.jl"),
        """
        module Example
        export normalize!
        \"\"\"Normalize values in place.\"\"\"
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
    @test occursin("AGENT-JL-R016", rendered)
    @test occursin("Public mutating method lacks a mutation contract", rendered)
    @test occursin("mutating method `normalize!`", rendered)
    @test length(AspJulia.advisory_findings(report)) == 1
end

@testset "project runner accepts public mutating method mutation contract" begin
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
        """,
    )

    report = run_julia_project_harness(root)

    @test AspJulia.is_clean(report)
    @test isempty(AspJulia.advisory_findings(report))
end
