@testset "project runner reports deep public control flow advice" begin
    root = mktempdir()
    write_project(root, "Example")
    mkpath(joinpath(root, "src"))
    write(
        joinpath(root, "src", "Example.jl"),
        """
        module Example
        export run
        \"\"\"Run values through a public algorithm.\"\"\"
        function run(values)
            result = 0
            if !isempty(values)
                for value in values
                    while value > 0
                        try
                            result += value
                            break
                        catch
                            break
                        end
                    end
                end
            end
            result
        end
        end
        """,
    )

    report = run_julia_project_harness(root)
    rendered = render_julia_project_harness(report)

    @test AspJulia.is_clean(report)
    @test occursin("AGENT-JL-R007", rendered)
    @test occursin("Public method hides deep control flow", rendered)
    @test occursin("control-flow depth 4", rendered)
    @test occursin("branches=2, loops=2, loop_depth=2", rendered)
    @test length(AspJulia.advisory_findings(report)) == 1
end

@testset "project runner reports nested internal traversal advice" begin
    root = mktempdir()
    write_project(root, "Example")
    mkpath(joinpath(root, "src"))
    write(
        joinpath(root, "src", "Example.jl"),
        """
        module Example
        export run
        \"\"\"Run values through the public API.\"\"\"
        run(values) = _scan_values(values)

        function _scan_values(groups)
            total = 0
            for group in groups
                for item in group
                    if item.active
                        try
                            total += item.value
                        catch
                            total += 0
                        end
                    end
                end
            end
            total
        end
        end
        """,
    )

    report = run_julia_project_harness(root)
    rendered = render_julia_project_harness(report)

    @test AspJulia.is_clean(report)
    @test occursin("AGENT-JL-R015", rendered)
    @test occursin("Internal method nests traversal scaffolding", rendered)
    @test occursin("branches=2, loops=2, loop_depth=2", rendered)
    @test length(AspJulia.advisory_findings(report)) == 1
end

@testset "project runner reports broad public body advice" begin
    root = mktempdir()
    write_project(root, "Example")
    mkpath(joinpath(root, "src"))
    write(
        joinpath(root, "src", "Example.jl"),
        """
        module Example
        export run
        \"\"\"Run a broad inline public calculation.\"\"\"
        function run(value)
            a = value + 1
            b = a * 2
            c = b - 3
            d = c / 4
            e = d + 5
            f = e * 6
            g = f - 7
            return g
        end
        end
        """,
    )

    report = run_julia_project_harness(root)
    rendered = render_julia_project_harness(report)

    @test AspJulia.is_clean(report)
    @test occursin("AGENT-JL-R008", rendered)
    @test occursin("Public method body lacks named pipeline steps", rendered)
    @test occursin("8 top-level body statements", rendered)
    @test length(AspJulia.advisory_findings(report)) == 1
end

@testset "project runner accepts broad public pipeline body" begin
    root = mktempdir()
    write_project(root, "Example")
    mkpath(joinpath(root, "src"))
    write(
        joinpath(root, "src", "Example.jl"),
        """
        module Example
        export run
        \"\"\"Run a named public pipeline.\"\"\"
        function run(value)
            a = load(value)
            b = normalize(a)
            c = score(b)
            d = render(c)
            e = persist(d)
            f = notify(e)
            g = audit(f)
            return g
        end
        end
        """,
    )

    report = run_julia_project_harness(root)

    @test AspJulia.is_clean(report)
    @test isempty(AspJulia.advisory_findings(report))
end

@testset "project runner reports macro-heavy public api advice" begin
    root = mktempdir()
    write_project(root, "Example")
    mkpath(joinpath(root, "src"))
    write(
        joinpath(root, "src", "Example.jl"),
        """
        module Example
        export run
        \"\"\"Run public transformations.\"\"\"
        function run(value)
            @alpha value
            @beta begin
                @gamma value
            end
            @delta value
            return value
        end
        end
        """,
    )

    report = run_julia_project_harness(root)
    rendered = render_julia_project_harness(report)

    @test AspJulia.is_clean(report)
    @test occursin("AGENT-JL-R010", rendered)
    @test occursin("Macro-heavy public API lacks a syntax contract", rendered)
    @test occursin("uses 4 macro invocations", rendered)
    @test length(AspJulia.advisory_findings(report)) == 1
end

@testset "project runner accepts macro-heavy public api contract doc" begin
    root = mktempdir()
    write_project(root, "Example")
    mkpath(joinpath(root, "src"))
    write(
        joinpath(root, "src", "Example.jl"),
        """
        module Example
        export run
        \"\"\"Syntax contract: macro expansion stages are part of public semantics.\"\"\"
        function run(value)
            @alpha value
            @beta begin
                @gamma value
            end
            @delta value
            return value
        end
        end
        """,
    )

    report = run_julia_project_harness(root)

    @test AspJulia.is_clean(report)
    @test isempty(AspJulia.advisory_findings(report))
end
