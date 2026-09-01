using JSON
using Test

@testset "native owner items query packet" begin
    root = mktempdir()
    write_cli_project(root)
    out = IOBuffer()

    rendered = @inferred AspJulia.render_julia_native_owner_items_query_json(
        "src/CliExample.jl",
        ["run"],
        root,
    )
    status = @inferred AspJulia.run_julia_native_owner_items_query_cli(
        "src/CliExample.jl",
        ["run"],
        root,
        out,
    )
    packet = JSON.parse(String(take!(out)), Dict{String,Any})

    @test JSON.parse(rendered, Dict{String,Any})["matches"] == packet["matches"]
    @test status == 0
    @test packet["schemaId"] == "agent.semantic-protocols.semantic-query-packet"
    @test packet["schemaVersion"] == "1"
    @test packet["method"] == "query/owner-items"
    @test packet["ownerPath"] == "src/CliExample.jl"
    @test packet["queryTerms"] == ["run"]
    @test any(match -> match["name"] == "run", packet["matches"])
    @test_throws ErrorException AspJulia.render_julia_native_owner_items_query_json(
        "src/CliExample.jl",
        String[],
        root,
    )
    @test_throws ErrorException AspJulia.julia_query_owner_items_packet(
        "src/CliExample.jl",
        String[];
        project_root=root,
    )
end

@testset "legacy query projections stay unavailable" begin
    root = mktempdir()
    write_cli_project(root)
    legacy_arguments = [
        ["query", "src/CliExample.jl", "--term", "run", "--workspace", root, "--code"],
        ["query", "src/CliExample.jl", "--term", "run", "--workspace", root, "--names-only"],
        [
            "query",
            "--catalog",
            "flow-lite",
            "--where",
            "source.call=run sink.constructs=Result",
            "--workspace",
            root,
        ],
    ]

    for args in legacy_arguments
        out = IOBuffer()
        status = run_julia_project_harness_cli(args; out)
        rendered = String(take!(out))
        @test status == 2
        @test occursin("does not declare typed native exact projection", rendered)
        @test !startswith(strip(rendered), "{")
    end
end
