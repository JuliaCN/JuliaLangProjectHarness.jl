@testset "cli query owner items packet" begin
    root = mktempdir()
    write_cli_project(root)
    compact_out = IOBuffer()
    json_out = IOBuffer()
    names_out = IOBuffer()

    compact_status = run_julia_project_harness_cli(
        ["query", "src/CliExample.jl", "--term", "run", "--code", root];
        out=compact_out,
    )
    json_status = run_julia_project_harness_cli(
        ["query", "src/CliExample.jl", "--term", "run", "--code", "--json", root];
        out=json_out,
    )
    names_status = run_julia_project_harness_cli(
        ["query", "src/CliExample.jl", "--term", "missing", "--names-only", root];
        out=names_out,
    )
    compact_rendered = String(take!(compact_out))
    packet = JSON3.read(String(take!(json_out)))
    names_rendered = String(take!(names_out))

    @test compact_status == 0
    @test occursin("[query-owner-items] owner=src/CliExample.jl", compact_rendered)
    @test occursin("|query term=run status=hit match=exact", compact_rendered)
    @test occursin("|item run kind=", compact_rendered)
    @test occursin("|code read=src/CliExample.jl:", compact_rendered)
    @test json_status == 0
    @test packet.schemaId == "agent.semantic-protocols.semantic-query-packet"
    @test packet.protocolId == "agent.semantic-protocols.semantic-language"
    @test packet.languageId == "julia"
    @test packet.providerId == "julia-lang-project-harness"
    @test packet.binary == "julia-project-harness"
    @test packet.method == "query/owner-items"
    @test packet.ownerPath == "src/CliExample.jl"
    @test packet.query == "run"
    @test packet.queryTerms == ["run"]
    @test packet.matchMode == "exact"
    @test packet.outputMode == "code"
    @test packet.matchCount >= 1
    @test any(match -> match.name == "run" && haskey(match, :projection), packet.matches)
    @test any(fact -> fact.name == "run", packet.nativeSyntaxFacts)
    @test names_status == 0
    @test occursin("status=miss", names_rendered)
    @test occursin("|candidate", names_rendered)
    @test_throws ErrorException julia_query_owner_items_packet("src/CliExample.jl", String[]; project_root=root)
    @test_throws ErrorException julia_query_owner_items_packet("src/CliExample.jl", ["run"]; project_root=root, match_limit=-1)
end
