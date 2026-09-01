@testset "project runner enforces Project.toml Moshi enable policy" begin
    root = mktempdir()
    write(
        joinpath(root, "Project.toml"),
        """
        name = "Example"
        uuid = "11111111-1111-1111-1111-111111111111"
        version = "0.1.0"

        [tool.AspJulia]
        moshi = "enable"
        """,
    )
    mkpath(joinpath(root, "src"))
    write(joinpath(root, "src", "Example.jl"), "module Example\nend\n")

    report = run_julia_project_harness(root)
    rendered = render_julia_project_harness(report)

    @test AspJulia.is_clean(report)
    @test occursin("Project.toml enables Moshi support", rendered)
    @test occursin("Moshi is not a direct package dependency available to `src/`", rendered)
    @test length(AspJulia.advisory_findings(report)) == 1
    finding = only(
        finding for finding in AspJulia.advisory_findings(report) if
        get(finding.labels, "configured_policy", "") == "enable"
    )
    @test finding.labels["configured_policy"] == "enable"
    @test finding.labels["moshi_extension_state"] == "missing_weakdep"
    @test occursin("[deps].Moshi", finding.labels["moshi_repair_shape"])
    @test occursin("src/Example.jl imports Moshi.Data and Moshi.Match", finding.labels["moshi_repair_shape"])
    @test finding.labels["moshi_repair_target"] == "src/Example.jl"
end

@testset "project runner points Moshi enable policy at nearest parser application" begin
    root = mktempdir()
    write(
        joinpath(root, "Project.toml"),
        """
        name = "Example"
        uuid = "11111111-1111-1111-1111-111111111111"
        version = "0.1.0"

        [tool.AspJulia]
        moshi = "enable"
        """,
    )
    mkpath(joinpath(root, "src"))
    write(
        joinpath(root, "src", "Example.jl"),
        """
        module Example
        export route

        function route(mode::AbstractString)
            if mode == "fast"
                1
            elseif mode == "safe"
                2
            else
                0
            end
        end
        end
        """,
    )

    report = run_julia_project_harness(root)
    rendered = render_julia_project_harness(report)
    finding = only(
        finding for finding in AspJulia.advisory_findings(report) if
        get(finding.labels, "configured_policy", "") == "enable"
    )

    @test AspJulia.is_clean(report)
    @test occursin("Nearest parser-visible application", rendered)
    @test occursin("`route` at src/Example.jl:", rendered)
    @test finding.labels["moshi_repair_target"] == "src/Example.jl"
    @test finding.labels["moshi_nearest_application_path"] == "src/Example.jl"
    @test finding.labels["moshi_nearest_application_function"] == "route"
    @test finding.labels["moshi_nearest_application_args"] == "mode"
    @test finding.labels["moshi_nearest_application_literals"] == "fast,safe"
    @test occursin("src/Example.jl imports Moshi.Data and Moshi.Match", finding.labels["moshi_repair_shape"])
end

@testset "project runner keeps Project.toml Moshi enable policy active until Moshi is a src dependency" begin
    root = mktempdir()
    write(
        joinpath(root, "Project.toml"),
        """
        name = "Example"
        uuid = "11111111-1111-1111-1111-111111111111"
        version = "0.1.0"

        [tool.AspJulia]
        moshi = "enable"

        [weakdeps]
        Moshi = "2e0e35c7-a2e4-4343-998d-7ef72827ed2d"

        [compat]
        Moshi = "0.3"

        [extensions]
        ExampleMoshiExt = "Moshi"

        [extras]
        Moshi = "2e0e35c7-a2e4-4343-998d-7ef72827ed2d"
        Test = "8dfed614-e22c-5e08-85e1-65c5234f0b40"

        [targets]
        test = ["Moshi", "Test"]
        """,
    )
    mkpath(joinpath(root, "src"))
    mkpath(joinpath(root, "ext"))
    write(joinpath(root, "src", "Example.jl"), "module Example\nend\n")
    write(joinpath(root, "ext", "ExampleMoshiExt.jl"), "module ExampleMoshiExt\nend\n")

    report = run_julia_project_harness(root)
    findings = [
        finding for finding in AspJulia.advisory_findings(report) if
        get(finding.labels, "configured_policy", "") == "enable"
    ]

    @test AspJulia.is_clean(report)
    @test length(findings) == 1
    @test only(findings).labels["moshi_repair_target"] == "src/Example.jl"
end

@testset "project runner accepts Project.toml Moshi enable policy with src dependency" begin
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
    write(joinpath(root, "src", "Example.jl"), "module Example\nusing Moshi.Data: @data\nend\n")

    report = run_julia_project_harness(root)

    @test AspJulia.is_clean(report)
    @test isempty([
        finding for finding in AspJulia.advisory_findings(report) if
        get(finding.labels, "configured_policy", "") == "enable"
    ])
end
