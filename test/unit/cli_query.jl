@testset "cli query owner items packet" begin
    root = mktempdir()
    write_cli_project(root)
    compact_out = IOBuffer()
    json_out = IOBuffer()
    names_out = IOBuffer()

    compact_status = run_julia_project_harness_cli(
        ["query", "src/CliExample.jl", "--term", "run", "--code", root];
        out = compact_out,
    )
    json_status = run_julia_project_harness_cli(
        ["query", "src/CliExample.jl", "--term", "run", "--code", "--json", root];
        out = json_out,
    )
    names_status = run_julia_project_harness_cli(
        ["query", "src/CliExample.jl", "--term", "missing", "--names-only", root];
        out = names_out,
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
    @test packet.binary == "asp-julia-harness"
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
    @test_throws ErrorException julia_query_owner_items_packet(
        "src/CliExample.jl",
        String[];
        project_root = root,
    )
    @test_throws ErrorException julia_query_owner_items_packet(
        "src/CliExample.jl",
        ["run"];
        project_root = root,
        match_limit = -1,
    )
end

@testset "cli query workspace direct read selector" begin
    root = mktempdir()
    write_cli_project(root)
    out = IOBuffer()

    status = run_julia_project_harness_cli(
        [
            "query",
            "--from-hook",
            "direct-source-read",
            "--workspace",
            "--selector",
            "src/CliExample.jl:1:2",
            "--code",
            root,
        ];
        out = out,
    )

    rendered = String(take!(out))
    @test status == 0
    @test occursin("module CliExample", rendered)
end

@testset "cli query flow-lite compatibility" begin
    root = mktempdir()
    mkpath(joinpath(root, "src"))
    write(
        joinpath(root, "Project.toml"),
        """
        name = "FlowLiteFixture"
        uuid = "11111111-1111-1111-1111-111111111111"
        version = "0.1.0"
        """,
    )
    write(
        joinpath(root, "src", "FlowLiteFixture.jl"),
        """
        module FlowLiteFixture
        struct ToolAction
            payload::String
        end
        payload_string(input) = strip(input)
        function collect_tool_actions(input)
            payload = payload_string(input)
            return [ToolAction(payload)]
        end
        end
        """,
    )
    compact_out = IOBuffer()
    json_out = IOBuffer()

    compact_status = run_julia_project_harness_cli(
        [
            "query",
            "--catalog",
            "flow-lite",
            "--where",
            "source.call=payload_string sink.constructs=ToolAction scope.fn=collect_tool_actions",
            root,
        ];
        out = compact_out,
    )
    json_status = run_julia_project_harness_cli(
        [
            "query",
            "--catalog",
            "flow-lite",
            "--where",
            "source.call=payload_string sink.constructs=ToolAction scope.fn=collect_tool_actions",
            "--json",
            root,
        ];
        out = json_out,
    )

    compact_rendered = String(take!(compact_out))
    packet = JSON3.read(String(take!(json_out)))

    @test compact_status == 0
    @test occursin("[query-flow-lite]", compact_rendered)
    @test occursin("lang=julia catalog=flow-lite", compact_rendered)
    @test occursin(
        "S=source:call(payload_string)@src/FlowLiteFixture.jl:7!code",
        compact_rendered,
    )
    @test occursin(
        "K=sink:constructs(ToolAction)@src/FlowLiteFixture.jl:8!code",
        compact_rendered,
    )
    @test occursin("confidence=bounded sourceAuthority=native-parser", compact_rendered)
    @test occursin("frontier=S.code,K.code,O.code", compact_rendered)
    @test json_status == 0
    @test packet.schemaId == "agent.semantic-protocols.semantic-flow-lite"
    @test packet.languageId == "julia"
    @test packet.providerId == "julia-lang-project-harness"
    @test packet.flowKind == "local-source-sink"
    @test packet.sourceAuthority == "native-parser"
    @test packet.executionBackend == "native-parser"
    @test packet.adapterMode == "native-projection"
    @test packet.confidence == "bounded"
    @test packet.ownerPath == "src/FlowLiteFixture.jl"
    @test isempty(packet.omissions)
    @test length(packet.path) == 2
    @test packet.path[1].role == "source"
    @test packet.path[1].line == 7
    @test packet.path[2].role == "sink"
    @test packet.path[2].line == 8
    @test packet.fields.rawSourceStored == false
    @test packet.fields.where["scope.fn"] == "collect_tool_actions"
    @test packet.fields.scannedFiles >= 1

    code_err = IOBuffer()
    code_status = run_julia_project_harness_cli(
        [
            "query",
            "--catalog",
            "flow-lite",
            "--where",
            "source.call=payload_string sink.constructs=ToolAction scope.fn=collect_tool_actions",
            "--code",
            root,
        ];
        out = IOBuffer(),
        err = code_err,
    )
    @test code_status == 2
    @test occursin("locator/provenance surface", String(take!(code_err)))

    open_where_err = IOBuffer()
    open_where_status = run_julia_project_harness_cli(
        [
            "query",
            "--catalog",
            "flow-lite",
            "--where",
            "source.call=payload_string sink.constructs=ToolAction scope.fn=collect_tool_actions guard.eq=is_safe",
            root,
        ];
        out = IOBuffer(),
        err = open_where_err,
    )
    @test open_where_status == 2
    @test occursin(
        "unsupported flow-lite --where key `guard.eq`",
        String(take!(open_where_err)),
    )
end
