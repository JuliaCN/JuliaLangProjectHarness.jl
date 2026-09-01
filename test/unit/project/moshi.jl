@testset "project runner suppresses Moshi domain advice with optional extension model" begin
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

        [extensions]
        ExampleMoshiExt = "Moshi"
        """,
    )
    mkpath(joinpath(root, "src"))
    mkpath(joinpath(root, "ext"))
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
    write(
        joinpath(root, "ext", "ExampleMoshiExt.jl"),
        """
        module ExampleMoshiExt
        using Example
        using Moshi.Data: @data

        @data Mode begin
            Fast
            Safe
        end
        end
        """,
    )

    report = run_julia_project_harness(root)
    rendered = render_julia_project_harness(report)

    @test AspJulia.is_clean(report)
    @test !occursin("AGENT-JL-R020", rendered)
    @test occursin("AGENT-JL-R004", rendered)
end

@testset "project runner advises Moshi match bridge for covered stringly domains" begin
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

        [extensions]
        ExampleMoshiExt = "Moshi"
        """,
    )
    mkpath(joinpath(root, "src"))
    mkpath(joinpath(root, "ext"))
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
    write(
        joinpath(root, "ext", "ExampleMoshiExt.jl"),
        """
        module ExampleMoshiExt
        using Example
        using Moshi.Data: @data

        @data Mode begin
            Fast
            Safe
        end
        end
        """,
    )

    report = run_julia_project_harness(root)
    rendered = render_julia_project_harness(report)
    finding = only(
        finding for finding in AspJulia.advisory_findings(report) if
        finding.rule_id == "AGENT-JL-R022"
    )

    @test AspJulia.is_clean(report)
    @test !occursin("AGENT-JL-R020", rendered)
    @test occursin("AGENT-JL-R022", rendered)
    @test occursin("Moshi domain model lacks a match bridge", rendered)
    @test finding.labels["moshi_model_coverage"] == "covered"
    @test finding.labels["moshi_match_coverage"] == "missing=fast,safe"
    @test finding.labels["moshi_model_targets"] == "Mode"
end

@testset "project runner accepts Moshi match bridge for stringly domains" begin
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

        [extensions]
        ExampleMoshiExt = "Moshi"
        """,
    )
    mkpath(joinpath(root, "src"))
    mkpath(joinpath(root, "ext"))
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
    write(
        joinpath(root, "ext", "ExampleMoshiExt.jl"),
        """
        module ExampleMoshiExt
        using Example
        using Moshi.Data: @data
        using Moshi.Match: @match

        @data Mode begin
            Fast
            Safe
        end

        route_mode(mode) = @match mode begin
            Mode.Fast() => :fast
            Mode.Safe() => :safe
        end
        end
        """,
    )

    report = run_julia_project_harness(root)
    rendered = render_julia_project_harness(report)

    @test AspJulia.is_clean(report)
    @test !occursin("AGENT-JL-R020", rendered)
    @test !occursin("AGENT-JL-R022", rendered)
end

@testset "project runner rejects Moshi match bridge on the wrong domain target" begin
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

        [extensions]
        ExampleMoshiExt = "Moshi"
        """,
    )
    mkpath(joinpath(root, "src"))
    mkpath(joinpath(root, "ext"))
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
    write(
        joinpath(root, "ext", "ExampleMoshiExt.jl"),
        """
        module ExampleMoshiExt
        using Example
        using Moshi.Data: @data
        using Moshi.Match: @match

        @data Mode begin
            Fast
            Safe
        end

        route_other(mode) = @match mode begin
            Other.Fast() => :fast
            Other.Safe() => :safe
        end
        end
        """,
    )

    report = run_julia_project_harness(root)
    rendered = render_julia_project_harness(report)
    finding = only(
        finding for finding in AspJulia.advisory_findings(report) if
        finding.rule_id == "AGENT-JL-R022"
    )

    @test AspJulia.is_clean(report)
    @test !occursin("AGENT-JL-R020", rendered)
    @test occursin("AGENT-JL-R022", rendered)
    @test finding.labels["moshi_model_targets"] == "Mode"
    @test finding.labels["moshi_match_coverage"] == "missing=fast,safe"
end

@testset "project runner rejects unrelated Moshi model as domain model escape" begin
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

        [extensions]
        ExampleMoshiExt = "Moshi"
        """,
    )
    mkpath(joinpath(root, "src"))
    mkpath(joinpath(root, "ext"))
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
    write(
        joinpath(root, "ext", "ExampleMoshiExt.jl"),
        """
        module ExampleMoshiExt
        using Example
        using Moshi.Data: @data

        @data Color begin
            Red
            Blue
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
    @test occursin("Branch literals: fast, safe", rendered)
    @test finding.labels["stringly_branch_literals"] == "fast,safe"
    @test finding.labels["moshi_model_coverage"] == "missing=fast,safe"
    @test finding.labels["moshi_extension_state"] == "extension_without_model"
end

@testset "project runner rejects empty Moshi extension as domain model escape" begin
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

        [extensions]
        ExampleMoshiExt = "Moshi"
        """,
    )
    mkpath(joinpath(root, "src"))
    mkpath(joinpath(root, "ext"))
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
    write(
        joinpath(root, "ext", "ExampleMoshiExt.jl"),
        """
        module ExampleMoshiExt
        using Example
        using Moshi.Data: @data
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
    @test occursin("add Moshi @data/@match domain modeling", rendered)
    @test occursin("config as the model", rendered)
    @test finding.labels["moshi_extension_state"] == "extension_without_model"
    @test finding.labels["moshi_extension_target"] == "ext/ExampleMoshiExt.jl"
end
