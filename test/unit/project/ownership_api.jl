@testset "project runner reports external method type piracy risk" begin
    root = mktempdir()
    write_project(root, "Example")
    mkpath(joinpath(root, "src"))
    write(
        joinpath(root, "src", "Example.jl"),
        """
        module Example
        Base.show(io::IO, value::Int) = print(io, value)
        end
        """,
    )

    report = run_julia_project_harness(root)
    rendered = render_julia_project_harness(report)

    @test AspJulia.is_clean(report)
    @test occursin("AGENT-JL-R021", rendered)
    @test occursin("External method extension risks type piracy", rendered)
    @test occursin("Base.show", rendered)
end

@testset "project runner accepts external method on package-owned type" begin
    root = mktempdir()
    write_project(root, "Example")
    mkpath(joinpath(root, "src"))
    write(
        joinpath(root, "src", "Example.jl"),
        """
        module Example
        struct Thing
            value::Int
        end
        Base.show(io::IO, value::Thing) = print(io, value.value)
        Base.hash(value::T, seed::UInt) where {T<:Thing} = hash(value.value, seed)
        end
        """,
    )

    report = run_julia_project_harness(root)
    rendered = render_julia_project_harness(report)

    @test AspJulia.is_clean(report)
    @test !occursin("AGENT-JL-R021", rendered)
end

@testset "project runner accepts documented external method type piracy contract" begin
    root = mktempdir()
    write_project(root, "Example")
    mkpath(joinpath(root, "src"))
    write(
        joinpath(root, "src", "Example.jl"),
        """
        module Example
        \"\"\"Type piracy contract: deliberate interop hook for compact Int display in this package boundary.\"\"\"
        Base.show(io::IO, value::Int) = print(io, value)
        end
        """,
    )

    report = run_julia_project_harness(root)
    rendered = render_julia_project_harness(report)

    @test AspJulia.is_clean(report)
    @test !occursin("AGENT-JL-R021", rendered)
end

@testset "project runner reports stringly public domain advice" begin
    root = mktempdir()
    write_project(root, "Example")
    mkpath(joinpath(root, "src"))
    write(
        joinpath(root, "src", "Example.jl"),
        """
        module Example
        export run
        \"\"\"Run with a named status mode.\"\"\"
        run(value; status::String="ready") = value
        end
        """,
    )

    report = run_julia_project_harness(root)
    rendered = render_julia_project_harness(report)

    @test AspJulia.is_clean(report)
    @test occursin("AGENT-JL-R004", rendered)
    @test occursin("Public method exposes a stringly domain argument", rendered)
    @test length(AspJulia.advisory_findings(report)) == 1
end

@testset "project runner reports public API owner conflicts" begin
    root = mktempdir()
    write_project(root, "Example")
    mkpath(joinpath(root, "src"))
    write(
        joinpath(root, "src", "Example.jl"),
        """
        module Example
        export Payload
        include("api.jl")
        include("fallbacks.jl")
        end
        """,
    )
    write(
        joinpath(root, "src", "api.jl"),
        """
        \"\"\"Public payload type.\"\"\"
        struct Payload
            value::Int
        end
        """,
    )
    write(
        joinpath(root, "src", "fallbacks.jl"),
        "Payload(value::String) = Payload(length(value))\n",
    )

    report = run_julia_project_harness(root)
    rendered = render_julia_project_harness(report)

    @test AspJulia.is_clean(report)
    @test occursin("AGENT-JL-R005", rendered)
    @test occursin("Public API name spans multiple owners", rendered)
    @test occursin("src/api.jl", rendered)
    @test occursin("src/fallbacks.jl", rendered)
    @test occursin("Document the extension pattern", rendered)
    @test length(AspJulia.advisory_findings(report)) == 1
end

@testset "project runner accepts same-owner public type constructor family" begin
    root = mktempdir()
    write_project(root, "Example")
    mkpath(joinpath(root, "src"))
    write(
        joinpath(root, "src", "Example.jl"),
        """
        module Example
        export Payload

        \"\"\"Public payload type.\"\"\"
        struct Payload
            value::String
        end

        \"\"\"Build a payload from any string-like value.

        Dispatch extension pattern: the constructor normalizes accepted input
        values while the type remains the single public data record.
        \"\"\"
        Payload(value::AbstractString) = Payload(String(value))
        end
        """,
    )

    report = run_julia_project_harness(root)

    @test AspJulia.is_clean(report)
    @test isempty(AspJulia.advisory_findings(report))
end

@testset "project runner reports scattered public method family advice" begin
    root = mktempdir()
    write_project(root, "Example")
    mkpath(joinpath(root, "src"))
    write(
        joinpath(root, "src", "Example.jl"),
        """
        module Example
        export run
        include("api.jl")
        include("fallbacks.jl")
        end
        """,
    )
    write(
        joinpath(root, "src", "api.jl"),
        """
        \"\"\"Run public values.\"\"\"
        run(value::Int) = value
        """,
    )
    write(joinpath(root, "src", "fallbacks.jl"), "run(value::String) = value\n")

    report = run_julia_project_harness(root)
    rendered = render_julia_project_harness(report)

    @test AspJulia.is_clean(report)
    @test occursin("AGENT-JL-R009", rendered)
    @test occursin("Public method family is scattered across owners", rendered)
    @test occursin("documented dispatch pattern", rendered)
    @test length(AspJulia.advisory_findings(report)) == 1
end

@testset "project runner accepts documented public method family extension pattern" begin
    root = mktempdir()
    write_project(root, "Example")
    mkpath(joinpath(root, "src"))
    write(
        joinpath(root, "src", "Example.jl"),
        """
        module Example
        export run
        include("api.jl")
        include("fallbacks.jl")
        end
        """,
    )
    write(
        joinpath(root, "src", "api.jl"),
        """
        \"\"\"Run public values.

        Dispatch extension pattern: fallback owner files add supported value methods.
        \"\"\"
        run(value::Int) = value
        """,
    )
    write(joinpath(root, "src", "fallbacks.jl"), "run(value::String) = value\n")

    report = run_julia_project_harness(root)

    @test AspJulia.is_clean(report)
    @test isempty(AspJulia.advisory_findings(report))
end
@testset "project runner reports undocumented module owner fanout" begin
    root = mktempdir()
    write_project(root, "Example")
    mkpath(joinpath(root, "src"))
    write(
        joinpath(root, "src", "Example.jl"),
        """
        module Example
        export run
        include("owners/a.jl")
        include("owners/b.jl")
        include("owners/c.jl")
        include("owners/d.jl")
        \"\"\"Run the public value.\"\"\"
        run(value) = value
        end
        """,
    )
    mkpath(joinpath(root, "src", "owners"))
    for name in ["a", "b", "c", "d"]
        write(joinpath(root, "src", "owners", "$(name).jl"), "$(name)() = 1\n")
    end

    report = run_julia_project_harness(root)
    rendered = render_julia_project_harness(report)

    @test AspJulia.is_clean(report)
    @test occursin("AGENT-JL-R006", rendered)
    @test occursin("Module owner fans out without an intent doc", rendered)
    @test length(AspJulia.advisory_findings(report)) == 1
end

@testset "project runner accepts documented module owner fanout" begin
    root = mktempdir()
    write_project(root, "Example")
    mkpath(joinpath(root, "src"))
    write(
        joinpath(root, "src", "Example.jl"),
        """
        \"\"\"Owns the package facade and wires parser-stable local owners.\"\"\"
        module Example
        export run
        include("owners/a.jl")
        include("owners/b.jl")
        include("owners/c.jl")
        include("owners/d.jl")
        \"\"\"Run the public value.\"\"\"
        run(value) = value
        end
        """,
    )
    mkpath(joinpath(root, "src", "owners"))
    for name in ["a", "b", "c", "d"]
        write(joinpath(root, "src", "owners", "$(name).jl"), "$(name)() = 1\n")
    end

    report = run_julia_project_harness(root)

    @test AspJulia.is_clean(report)
    @test isempty(AspJulia.advisory_findings(report))
end
