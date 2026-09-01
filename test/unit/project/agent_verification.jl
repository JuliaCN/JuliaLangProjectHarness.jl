@testset "project runner ignores unsafe constructs in tests" begin
    root = mktempdir()
    write_project(root, "Example")
    mkpath(joinpath(root, "src"))
    mkpath(joinpath(root, "test"))
    write(joinpath(root, "src", "Example.jl"), "module Example\nend\n")
    write(
        joinpath(root, "test", "runtests.jl"),
        """
        using Test

        @testset "process smoke" begin
            run(`echo hello`)
            @test true
        end
        """,
    )

    report = run_julia_project_harness(root)

    @test AspJulia.is_clean(report)
    @test isempty(AspJulia.advisory_findings(report))
end

@testset "project runner reports public generic type coverage advice" begin
    root = mktempdir()
    write_project(root, "Example")
    mkpath(joinpath(root, "src"))
    mkpath(joinpath(root, "test"))
    write(
        joinpath(root, "src", "Example.jl"),
        """
        module Example
        export normalize
        \"\"\"Normalize a generic real value.\"\"\"
        function normalize(value::T)::T where {T<:Real}
            value
        end
        end
        """,
    )
    write(
        joinpath(root, "test", "runtests.jl"),
        """
        using Test
        using Example

        @test normalize(1) == 1
        """,
    )

    report = run_julia_project_harness(root)
    rendered = render_julia_project_harness(report)

    @test AspJulia.is_clean(report)
    @test occursin("AGENT-JL-R018", rendered)
    @test occursin("Public generic API lacks type coverage", rendered)
    @test occursin("where {T<:Real}", rendered)
    @test occursin("only parser-visible input types: Int", rendered)
    @test length(AspJulia.advisory_findings(report)) == 1
end

@testset "project runner accepts public generic type coverage" begin
    root = mktempdir()
    write_project(root, "Example")
    mkpath(joinpath(root, "src"))
    mkpath(joinpath(root, "test"))
    write(
        joinpath(root, "src", "Example.jl"),
        """
        module Example
        export normalize
        \"\"\"Normalize a generic real value.\"\"\"
        function normalize(value::T)::T where {T<:Real}
            value
        end
        end
        """,
    )
    write(
        joinpath(root, "test", "runtests.jl"),
        """
        using Test
        using Example

        @test normalize(1) == 1
        @test normalize(1.0) == 1.0
        """,
    )

    report = run_julia_project_harness(root)

    @test AspJulia.is_clean(report)
    @test isempty(AspJulia.advisory_findings(report))
end

@testset "project runner reports Documenter public API doctest advice" begin
    root = mktempdir()
    write_project(root, "Example")
    mkpath(joinpath(root, "src"))
    mkpath(joinpath(root, "test"))
    mkpath(joinpath(root, "docs", "src"))
    write(
        joinpath(root, "src", "Example.jl"),
        """
        module Example
        export run
        \"\"\"Run a public value.\"\"\"
        run(value) = value
        end
        """,
    )
    write(joinpath(root, "test", "runtests.jl"), "using Test\n@test true\n")
    write(
        joinpath(root, "docs", "Project.toml"),
        """
        [deps]
        Documenter = "e30172f5-a6a5-5a46-863b-614d45cd2de4"

        [compat]
        Documenter = "1"
        """,
    )
    write(joinpath(root, "docs", "make.jl"), "using Documenter\nmakedocs()\n")
    write(
        joinpath(root, "docs", "src", "index.md"),
        """
        # Example

        The `run` API returns the provided value.
        """,
    )

    report = run_julia_project_harness(root)
    rendered = render_julia_project_harness(report)

    @test AspJulia.is_clean(report)
    @test occursin("AGENT-JL-R019", rendered)
    @test occursin("Documenter docs lack public API doctests", rendered)
    @test occursin("executable public API examples for: run", rendered)
    @test length(AspJulia.advisory_findings(report)) == 1
end

@testset "project runner accepts Documenter public API doctest examples" begin
    root = mktempdir()
    write_project(root, "Example")
    mkpath(joinpath(root, "src"))
    mkpath(joinpath(root, "test"))
    mkpath(joinpath(root, "docs", "src"))
    write(
        joinpath(root, "src", "Example.jl"),
        """
        module Example
        export run
        \"\"\"Run a public value.\"\"\"
        run(value) = value
        end
        """,
    )
    write(joinpath(root, "test", "runtests.jl"), "using Test\n@test true\n")
    write(
        joinpath(root, "docs", "Project.toml"),
        """
        [deps]
        Documenter = "e30172f5-a6a5-5a46-863b-614d45cd2de4"

        [compat]
        Documenter = "1"
        """,
    )
    write(joinpath(root, "docs", "make.jl"), "using Documenter\nmakedocs()\n")
    write(
        joinpath(root, "docs", "src", "index.md"),
        """
        # Example

        ```jldoctest
        julia> using Example

        julia> run(1)
        1
        ```
        """,
    )

    report = run_julia_project_harness(root)

    @test AspJulia.is_clean(report)
    @test isempty(AspJulia.advisory_findings(report))
end

@testset "project runner advises source or optional Moshi domain model" begin
    root = mktempdir()
    write_project(root, "Example")
    mkpath(joinpath(root, "src"))
    write(
        joinpath(root, "src", "Example.jl"),
        """
        module Example
        export route

        \"\"\"Route a value by mode.\"\"\"
        function route(value; mode::AbstractString="fast")
            if mode == "fast"
                value
            elseif mode == "safe"
                value
            else
                value
            end
        end
        end
        """,
    )

    report = run_julia_project_harness(root)
    rendered = render_julia_project_harness(report)

    @test AspJulia.is_clean(report)
    @test occursin("AGENT-JL-R020", rendered)
    @test occursin("Stringly branch dispatch lacks a typed domain model", rendered)
    @test occursin(
        "set `[tool.AspJulia] moshi = \"enable\"",
        rendered,
    )
    @test occursin("If this is only an optional experiment", rendered)
    finding = only(
        finding for finding in AspJulia.advisory_findings(report) if
        finding.rule_id == "AGENT-JL-R020"
    )
    @test finding.labels["capability_source"] == "Moshi"
    @test finding.labels["capabilities"] == "syntax,domain-model,search"
    @test finding.labels["moshi_extension_state"] == "missing_weakdep"
    @test finding.labels["moshi_extension_target"] == "ext/ExampleMoshiExt.jl"
    @test occursin("[extensions].ExampleMoshiExt = \"Moshi\"", finding.labels["moshi_repair_shape"])
end

@testset "project runner advises source Moshi model when Project.toml enables Moshi" begin
    root = mktempdir()
    write(
        joinpath(root, "Project.toml"),
        """
        name = "Example"
        uuid = "11111111-1111-1111-1111-111111111111"
        version = "0.1.0"

        [tool.AspJulia]
        moshi = "enable"

        [deps]
        Moshi = "2e0e35c7-a2e4-4343-998d-7ef72827ed2d"

        [compat]
        Moshi = "0.3"
        """,
    )
    mkpath(joinpath(root, "src"))
    write(
        joinpath(root, "src", "Example.jl"),
        """
        module Example
        export route

        \"\"\"Route a value by mode.\"\"\"
        function route(value; mode::AbstractString="fast")
            if mode == "fast"
                value
            elseif mode == "safe"
                value
            else
                value
            end
        end
        end
        """,
    )

    report = run_julia_project_harness(root)
    rendered = render_julia_project_harness(report)
    finding = only(
        finding for finding in AspJulia.advisory_findings(report) if
        finding.rule_id == "AGENT-JL-R020"
    )

    @test AspJulia.is_clean(report)
    @test occursin("Moshi is a direct dependency because Project.toml enables Moshi", rendered)
    @test finding.labels["moshi_extension_state"] == "direct_dep_enabled"
    @test finding.labels["moshi_extension_target"] == "src/Example.jl"
end

@testset "project runner advises Moshi weakdep extension repair target" begin
    root = mktempdir()
    write(
        joinpath(root, "Project.toml"),
        """
        name = "Example"
        uuid = "11111111-1111-1111-1111-111111111111"
        version = "0.1.0"

        [weakdeps]
        Moshi = "2e0e35c7-a2e4-4343-998d-7ef72827ed2d"

        [compat]
        Moshi = "0.3"
        """,
    )
    mkpath(joinpath(root, "src"))
    write(
        joinpath(root, "src", "Example.jl"),
        """
        module Example
        export route

        \"\"\"Route a value by mode.\"\"\"
        function route(value; mode::AbstractString="fast")
            if mode == "fast"
                value
            elseif mode == "safe"
                value
            else
                value
            end
        end
        end
        """,
    )

    report = run_julia_project_harness(root)
    rendered = render_julia_project_harness(report)
    finding = only(
        finding for finding in AspJulia.advisory_findings(report) if
        finding.rule_id == "AGENT-JL-R020"
    )

    @test AspJulia.is_clean(report)
    @test occursin("Moshi is already a weak dependency", rendered)
    @test occursin("ext/ExampleMoshiExt.jl", rendered)
    @test finding.labels["moshi_extension_state"] == "weakdep_without_extension"
    @test finding.labels["moshi_extension_target"] == "ext/ExampleMoshiExt.jl"
end
