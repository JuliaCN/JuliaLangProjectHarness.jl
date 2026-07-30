using JSON
using JuliaLangProjectHarness
using Test

function project_resolution_request(root::String, candidates::Vector{String})
    return Dict{String,Any}(
        "schemaId" => "agent.semantic-protocols.provider-project-resolution-request",
        "schemaVersion" => "1",
        "languageId" => "julia",
        "providerId" => "julia-lang-project-harness",
        "workspaceRoot" => root,
        "repositoryCandidates" => Dict(
            "schemaId" => "agent.semantic-protocols.repository-candidate-snapshot",
            "schemaVersion" => "1",
            "mode" => "git",
            "repositoryIdentity" => Dict(
                "repositoryId" => "repo-test",
                "identityBasis" => "git-common-dir:test",
                "gitCommonDir" => "/tmp/repo/.git",
                "remoteUrl" => nothing,
            ),
            "worktreeIdentity" => Dict(
                "worktreeId" => "worktree-test",
                "worktreeRoot" => root,
                "gitDir" => "/tmp/repo/.git",
                "headId" => nothing,
            ),
            "candidateGeneration" => Dict(
                "algorithm" => "blake3-path-set-v1",
                "digest" => "blake3:" * repeat("0", 64),
                "authorities" => ["git-index"],
            ),
            "candidates" => [
                Dict("path" => path, "state" => "tracked", "authority" => "git-index") for
                path in candidates
            ],
            "metrics" => Dict(
                "indexEntryCount" => length(candidates),
                "worktreeAdditionCount" => 0,
                "candidateCount" => length(candidates),
                "fullWorkspaceReads" => 0,
                "fullMerkleRebuilds" => 0,
                "directDbOpens" => 0,
            ),
        ),
    )
end

function run_project_resolution(request)
    out = IOBuffer()
    exit_code = JuliaLangProjectHarness.run_julia_project_resolution_cli(
        IOBuffer(JSON.json(request)),
        out,
    )
    seekstart(out)
    return exit_code, JSON.parse(read(out, String), Dict{String,Any})
end

@testset "candidate-bounded Julia Pkg project resolution" begin
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
        candidates = [
            "Project.toml",
            "src/RootPackage.jl",
            "test/runtests.jl",
            "packages/Member/Project.toml",
            "packages/Member/src/Member.jl",
        ]
        exit_code, response =
            run_project_resolution(project_resolution_request(root, candidates))
        @test exit_code == 0
        @test response["state"] == "resolved"
        resolution = response["resolution"]
        @test resolution["completeness"] == "exact"
        @test resolution["metrics"]["parsedManifestCount"] == 2
        @test resolution["metrics"]["affectedPackageCount"] == 2
        @test resolution["metrics"]["fullWorkspaceReads"] == 0
        @test resolution["metrics"]["dbOpens"] == 0
        source_roots = sort!(
            reduce(
                vcat,
                [String.(scope["roots"]) for scope in resolution["resolvedSourceScopes"]],
            ),
        )
        @test source_roots == [
            "packages/Member/src",
            "src",
            "test",
        ]
        @test !occursin("NotCandidate.jl", JSON.json(response))
        internal_edges = resolution["packageGraph"]["internalDependencyEdges"]
        member_package = only(
            filter(
                package -> package["name"] == "Member",
                resolution["packageGraph"]["packages"],
            ),
        )
        @test length(internal_edges) == 1
        @test internal_edges[1]["toPackageId"] == member_package["packageId"]
    end
end

@testset "Julia project resolution fails closed without a project entry" begin
    root = mktempdir()
    request = project_resolution_request(root, ["src/Only.jl"])
    exit_code, response = run_project_resolution(request)
    @test exit_code == 0
    @test response["state"] == "failed"
    @test occursin("provider project entry is required", response["failure"]["message"])
end

@testset "Julia provider manifest advertises project resolution" begin
    manifest_path = joinpath(@__DIR__, "..", "..", "juliac", "asp-provider-manifest.json")
    manifest = JSON.parse(read(manifest_path, String), Dict{String,Any})
    descriptor = manifest["projectResolution"]
    @test descriptor["commandBinding"] == "project-resolution-stdin"
    @test descriptor["parserId"] == "julia.pkg-project-toml"
    @test descriptor["supportsGitCandidates"] === true
    @test descriptor["supportsProviderOnly"] === false
end
