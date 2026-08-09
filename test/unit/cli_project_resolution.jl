using JSON
using JuliaLangProjectHarness
using Test

function project_resolution_request(candidates::Vector{String})
    return Dict{String,Any}(
        "schemaId" => "agent.semantic-protocols.provider-project-resolution-request",
        "schemaVersion" => "1",
        "languageId" => "julia",
        "providerId" => "julia-lang-project-harness",
        "candidateBase" => ".",
        "candidateGeneration" => Dict(
            "algorithm" => "blake3-path-set-v1",
            "digest" => "blake3:" * repeat("0", 64),
            "authorities" => ["asp-workspace-admission"],
        ),
        "collectionScope" => Dict("kind" => "complete-generation"),
        "candidatePaths" => candidates,
        "policyExclusions" => Any[],
    )
end

function run_project_resolution(root::String, request)
    out = IOBuffer()
    exit_code = cd(root) do
        JuliaLangProjectHarness.run_julia_project_resolution_cli(
            IOBuffer(JSON.json(request)),
            out,
        )
    end
    seekstart(out)
    return exit_code, JSON.parse(read(out, String), Dict{String,Any})
end

@testset "candidate-bounded Julia Pkg ProjectResolution" begin
    mktempdir() do root
        mkpath(joinpath(root, "src"))
        mkpath(joinpath(root, "test"))
        mkpath(joinpath(root, "packages", "Member", "src"))
        write(
            joinpath(root, "Project.toml"),
            """
            name = "RootPackage"
            uuid = "11111111-1111-1111-1111-111111111111"

            [deps]
            Member = "22222222-2222-2222-2222-222222222222"

            [extras]
            Test = "8dfed614-e22c-5e08-85e1-65c5234f0b40"

            [targets]
            test = ["Test"]

            [workspace]
            projects = ["packages/Member"]
            """,
        )
        write(joinpath(root, "src", "RootPackage.jl"), "module RootPackage\nend\n")
        write(joinpath(root, "src", "NotCandidate.jl"), "module NotCandidate\nend\n")
        write(joinpath(root, "test", "runtests.jl"), "using Test\n")
        write(
            joinpath(root, "packages", "Member", "Project.toml"),
            """
            name = "Member"
            uuid = "22222222-2222-2222-2222-222222222222"
            """,
        )
        write(
            joinpath(root, "packages", "Member", "src", "Member.jl"),
            "module Member\nend\n",
        )
        mkpath(joinpath(root, "examples", "Unrelated"))
        write(joinpath(root, "examples", "Unrelated", "Manifest.toml"), "julia_version = \"1.12.0\"\n")
        candidates = [
            "Project.toml",
            "src/RootPackage.jl",
            "test/runtests.jl",
            "packages/Member/Project.toml",
            "packages/Member/src/Member.jl",
            "examples/Unrelated/Manifest.toml",
        ]
        exit_code, response =
            run_project_resolution(root, project_resolution_request(candidates))
        @test exit_code == 0
        @test response["state"] == "resolved"
        @test !haskey(response, "resolution")
        scope = response["scope"]
        @test scope["completeness"] == "exact"
        @test scope["candidateGenerationDigest"] == "blake3:" * repeat("0", 64)
        @test scope["metrics"]["parsedManifestCount"] == 2
        @test scope["metrics"]["affectedPackageCount"] == 2
        @test scope["metrics"]["fullWorkspaceReads"] == 0
        @test scope["metrics"]["dbOpens"] == 0
        source_roots = sort!(
            reduce(
                vcat,
                [String.(source_scope["roots"]) for source_scope in scope["sourceScopes"]],
            ),
        )
        @test source_roots == [
            "packages/Member/src",
            "src",
            "test",
        ]
        test_scope = only(
            filter(
                scope -> scope["classifications"] == ["test"],
                scope["sourceScopes"],
            ),
        )
        @test test_scope["explicitPaths"] == ["test/runtests.jl"]
        @test all(
            isempty(source_scope["explicitPaths"]) for
            source_scope in scope["sourceScopes"] if source_scope !== test_scope
        )
        @test !occursin("NotCandidate.jl", JSON.json(response))
        internal_edges = scope["packageGraph"]["internalDependencyEdges"]
        member_package = only(
            filter(
                package -> package["name"] == "Member",
                scope["packageGraph"]["packages"],
            ),
        )
        @test length(internal_edges) == 1
        @test internal_edges[1]["toPackageId"] == member_package["packageId"]
        @test isempty(scope["packageGraph"]["lockfiles"])
    end
end

@testset "Julia ProjectResolution does not promote a nested project entry" begin
    mktempdir() do root
        mkpath(joinpath(root, "packages", "Nested"))
        write(
            joinpath(root, "packages", "Nested", "Project.toml"),
            "name = \"Nested\"\nuuid = \"33333333-3333-3333-3333-333333333333\"\n",
        )
        request = project_resolution_request(["packages/Nested/Project.toml"])
        exit_code, response = run_project_resolution(root, request)
        @test exit_code == 0
        @test response["state"] == "failed"
        @test occursin("provider project entry is required", response["failure"]["message"])
    end
end

@testset "Julia ProjectResolution fails closed without a project entry" begin
    root = mktempdir()
    request = project_resolution_request(["src/Only.jl"])
    exit_code, response = run_project_resolution(root, request)
    @test exit_code == 0
    @test response["state"] == "failed"
    @test occursin("provider project entry is required", response["failure"]["message"])
end

@testset "Julia provider manifest advertises ProjectResolution" begin
    manifest_path = joinpath(@__DIR__, "..", "..", "juliac", "asp-provider-manifest.json")
    manifest = JSON.parse(read(manifest_path, String), Dict{String,Any})
    descriptor = manifest["projectResolution"]
    @test descriptor["commandBinding"] == "project-resolution-stdin"
    @test descriptor["parserId"] == "julia.pkg-project-toml"
    @test descriptor["capabilityId"] == "project-resolution"
end
