using JSON

function write_cli_evidence_project(root::AbstractString)
    write(
        joinpath(root, "Project.toml"),
        """
        name = "CliEvidence"
        uuid = "22222222-2222-2222-2222-222222222222"
        version = "0.1.0"
        """,
    )
    mkpath(joinpath(root, "src"))
    write(
        joinpath(root, "src", "CliEvidence.jl"),
        """
        module CliEvidence
        export run
        run(value) = string(value)
        end
        """,
    )
end

@testset "cli evidence graph and analysis output" begin
    root = mktempdir()
    write_cli_evidence_project(root)
    graph_out = IOBuffer()
    analysis_out = IOBuffer()
    registry_out = IOBuffer()
    guide_out = IOBuffer()

    graph_status =
        run_julia_project_harness_cli(["evidence", "graph", "--json", root]; out = graph_out)
    analysis_status = run_julia_project_harness_cli(
        ["evidence", "analyze", "--json", root];
        out = analysis_out,
    )
    registry_status =
        run_julia_project_harness_cli(["agent", "doctor", "--json", root]; out = registry_out)
    guide_status = run_julia_project_harness_cli(["guide", root]; out = guide_out)
    graph = JSON.parse(String(take!(graph_out)))
    analysis = JSON.parse(String(take!(analysis_out)))
    registry = JSON.parse(String(take!(registry_out)))
    guide = String(take!(guide_out))
    language = only(filter(language -> language.languageId == "julia", registry.languages))

    @test graph_status == 0
    @test graph.schemaId == "agent.semantic-protocols.semantic-evidence-graph"
    @test graph.protocolId == "agent.semantic-protocols.evidence-graph"
    @test graph.producer.languageId == "julia"
    @test graph.producer.providerId == "julia-lang-project-harness"
    @test graph.project.package == "CliEvidence"
    @test graph.summary.nodes == 4
    @test graph.summary.edges == 3
    @test graph.summary.owners == 1
    @test graph.summary.claims == 1
    @test graph.summary.gaps == 1
    @test any(node -> node.kind == "owner", graph.nodes)
    @test any(edge -> edge.kind == "requires-evidence", graph.edges)
    @test only(graph.gaps).fields.nextCommand == "asp-julia-harness check --changed ."
    @test analysis_status == 0
    @test analysis.schemaId == "agent.semantic-protocols.semantic-graph-turbo-request"
    @test analysis.packetKind == "graph-turbo-request"
    @test analysis.surface == "evidence-analyze"
    @test analysis.profile == "evidence-quality"
    @test analysis.summary.graphs == 1
    @test analysis.summary.nodes == 4
    @test analysis.summary.gaps == 1
    @test only(analysis.graphs).graphId == "julia.evidence.graph"
    @test analysis.seedIds == ["julia:owner:project.toml"]
    @test any(edge -> edge.relation == "requires-evidence", only(analysis.graphs).edges)
    @test registry_status == 0
    @test "evidence/graph" in language.methods
    @test "evidence/analyze" in language.methods
    @test any(
        descriptor ->
            descriptor.method == "evidence/analyze" &&
            descriptor.command == "evidence" &&
            only(descriptor.outputSchemaIds) ==
            "agent.semantic-protocols.semantic-graph-turbo-request",
        language.methodDescriptors,
    )
    @test guide_status == 0
    @test occursin("evidence graph --json", guide)
    @test occursin("evidence analyze --json", guide)
end
