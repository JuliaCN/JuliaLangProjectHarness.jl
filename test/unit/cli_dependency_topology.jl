@testset "cli search dependency topology packet" begin
    mktempdir() do root
        write(
            joinpath(root, "Project.toml"),
            """
            name = "DependencyTopologyFixture"
            uuid = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
            version = "0.1.0"

            [deps]
            DataFrames = "a93c6f00-e57d-5684-b7b6-d8193f3e46c0"
            """,
        )
        write(
            joinpath(root, "Manifest.toml"),
            """
            julia_version = "1.11.0"
            manifest_format = "2.0"
            project_hash = "fixture"

            [[deps.DataFrames]]
            uuid = "a93c6f00-e57d-5684-b7b6-d8193f3e46c0"
            version = "1.6.1"
            """,
        )

        out = IOBuffer()
        @test AspJulia.run_julia_harness_search_cli(
            ["dependency-topology", "--json", "--workspace", root];
            out=out,
        ) == 0
        packet = JSON.parse(String(take!(out)), Dict{String,Any})

        @test packet["packetKind"] == "dependency-topology"
        @test occursin(r"^sha256:[0-9a-f]{64}$", packet["fingerprint"])
        @test packet["graph"]["nodes"] == Any[
            Dict{String,Any}(
                "id" => "dependency:DataFrames",
                "kind" => "dependency",
                "value" => "DataFrames",
                "path" => "Project.toml",
                "fields" => Dict{String,Any}(
                    "dependencyName" => "DataFrames",
                    "manifestPath" => "Manifest.toml",
                ),
            ),
            Dict{String,Any}(
                "id" => "dependency-version:DataFrames@1.6.1",
                "kind" => "dependency-version",
                "value" => "1.6.1",
                "fields" => Dict{String,Any}("version" => "1.6.1"),
            ),
        ]
        @test packet["graph"]["edges"] == Any[
            Dict{String,Any}(
                "source" => "dependency:DataFrames",
                "target" => "dependency-version:DataFrames@1.6.1",
                "relation" => "version_locked",
            ),
        ]
    end

    provider_manifest = JSON.parse(
        read(
            joinpath(@__DIR__, "..", "..", "juliac", "asp-provider-registration.json"),
            String,
        ),
        Dict{String,Any},
    )
    @test provider_manifest["searchCapabilities"]["dependencyTopology"] === true
    @test any(route -> route["operation"] == "search", provider_manifest["routes"])
end
