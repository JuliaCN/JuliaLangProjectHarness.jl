@testset "cli search json packets" begin
    root = mktempdir()
    write_cli_dependency_project(root)
    workspace_out = IOBuffer()
    prime_out = IOBuffer()
    lexical_out = IOBuffer()
    deps_out = IOBuffer()
    query_out = IOBuffer()
    policy_out = IOBuffer()
    ingest_out = IOBuffer()
    semantic_out = IOBuffer()
    registry_out = IOBuffer()

    write(
        joinpath(root, "src", "SemanticModels.jl"),
        join(
            [
                "struct Catalog",
                "    names::Vector{String}",
                "    by_id::Dict{String,Int}",
                "    score::Int",
                "end",
            ],
            "\n",
        ),
    )

    workspace_status = run_julia_project_harness_cli(
        ["search", "workspace", "--view", "seeds", "--json", "--workspace", root];
        out=workspace_out,
    )
    prime_status = run_julia_project_harness_cli(
        ["search", "prime", "--view", "seeds", "--json", "--workspace", root];
        out=prime_out,
    )
    lexical_status = run_julia_project_harness_cli(
        ["search", "lexical", "run", "owner", "tests", "--view", "seeds", "--json", "--workspace", root];
        out=lexical_out,
    )
    deps_status = run_julia_project_harness_cli(
        [
            "search",
            "deps",
            "JSON::parse",
            "owner",
            "tests",
            "--view",
            "seeds",
            "--json",
            "--workspace",
            root,
        ];
        out=deps_out,
    )
    query_status = run_julia_project_harness_cli(
        [
            "search",
            "query",
            "--from-hook",
            "direct-source-read",
            "--selector",
            "**/*.jl",
            "--term",
            "run",
            "--surface",
            "owner,tests",
            "--view",
            "seeds",
            "--json",
            "--workspace",
            root,
        ];
        out=query_out,
    )
    policy_status = run_julia_project_harness_cli(
        [
            "search",
            "policy",
            "JULIA-AGENT-PROJECT-001",
            "owner",
            "tests",
            "--view",
            "seeds",
            "--json",
            "--workspace",
            root,
        ];
        out=policy_out,
    )
    ingest_status = let input = "src/CliExample.jl:1:module CliExample\ntest/runtests.jl:3:@testset \"run\" begin\n",
        pipe = Pipe()
        writer = @async begin
            write(pipe, input)
            close(pipe)
        end
        status = redirect_stdin(pipe) do
            run_julia_project_harness_cli(
                [
                    "search",
                    "ingest",
                    "owner",
                    "tests",
                    "--view",
                    "seeds",
                    "--json",
                    "--workspace",
                    root,
                ];
                out=ingest_out,
            )
        end
        wait(writer)
        status
    end
    semantic_status = let input = "src/SemanticModels.jl:2:names\n",
        pipe = Pipe()
        writer = @async begin
            write(pipe, input)
            close(pipe)
        end
        status = redirect_stdin(pipe) do
            run_julia_project_harness_cli(
                [
                    "search",
                    "semantic-facts",
                    "Vector collection fields",
                    "--json",
                    "--workspace",
                    root,
                ];
                out=semantic_out,
            )
        end
        wait(writer)
        status
    end
    registry_status = run_julia_project_harness_cli(["agent", "registry", "--json", root]; out=registry_out)

    workspace_packet = JSON.parse(String(take!(workspace_out)))
    prime_packet = JSON.parse(String(take!(prime_out)))
    lexical_packet = JSON.parse(String(take!(lexical_out)))
    deps_packet = JSON.parse(String(take!(deps_out)))
    query_packet = JSON.parse(String(take!(query_out)))
    policy_packet = JSON.parse(String(take!(policy_out)))
    ingest_packet = JSON.parse(String(take!(ingest_out)))
    semantic_packet = JSON.parse(String(take!(semantic_out)))
    registry = JSON.parse(String(take!(registry_out)))
    language = only(filter(language -> language.languageId == "julia", registry.languages))
    relative_prime_packet = cd(root) do
        JSON.parse(
            AspJulia.render_julia_native_prime_packet_json(".", "seeds"),
        )
    end

    @test workspace_status == 0
    @test workspace_packet.method == "search/workspace"
    @test workspace_packet.view == "workspace"
    @test workspace_packet.searchSynthesis.scope == "workspace"
    @test any(owner -> owner.path == "src/CliExample.jl", workspace_packet.owners)
    @test prime_status == 0
    @test prime_packet.schemaId == "agent.semantic-protocols.semantic-search-packet"
    @test prime_packet.method == "search/prime"
    @test prime_packet.renderMode == "seeds"
    @test any(owner -> owner.path == "src/CliExample.jl", prime_packet.owners)
    @test relative_prime_packet.method == "search/prime"
    @test !isempty(relative_prime_packet.hits)
    @test all(hit -> !isabspath(hit.ownerPath), relative_prime_packet.hits)
    @test any(fact -> fact.ownerPath == "src/CliExample.jl", prime_packet.nativeSyntaxFacts)
    @test lexical_status == 0
    @test lexical_packet.method == "search/lexical"
    @test lexical_packet.query == "run"
    @test any(hit -> hit.symbol == "run", lexical_packet.hits)
    @test any(action -> action.target == "src/CliExample.jl", lexical_packet.nextActions)
    @test deps_status == 0
    @test deps_packet.method == "search/deps"
    @test deps_packet.view == "deps"
    @test deps_packet.query == "JSON::parse"
    @test only(deps_packet.querySet).kind == "dependency"
    @test only(deps_packet.querySet).fields.dependency == "JSON"
    @test only(deps_packet.querySet).fields.apiQuery == "parse"
    @test only(deps_packet.queryCoverage).status == "hit"
    @test any(node -> node.kind == "dependency" && node.fields.name == "JSON", deps_packet.nodes)
    @test any(hit -> hit.ownerPath == "src/CliExample.jl" && occursin("parse", hit.symbol), deps_packet.hits)
    @test any(action -> action.target == "src/CliExample.jl", deps_packet.nextActions)
    @test deps_packet.cache.rawSourceStored == false
    dependency_cache_paths = [hash.path for hash in deps_packet.cache.fileHashes]
    @test "Project.toml" in dependency_cache_paths
    @test "src/CliExample.jl" in dependency_cache_paths
    @test all(hash -> occursin(r"^[a-f0-9]{64}$", hash.sha256), deps_packet.cache.fileHashes)
    @test query_status == 0
    @test query_packet.method == "search/query"
    @test query_packet.view == "query"
    @test query_packet.query == "run"
    @test only(query_packet.querySet).value == "run"
    @test only(query_packet.sourceCoverage).fields.selector == "**/*.jl"
    @test only(query_packet.queryCoverage).status == "hit"
    @test any(hit -> hit.symbol == "run", query_packet.hits)
    @test any(fact -> fact.name == "run", query_packet.nativeSyntaxFacts)
    @test any(action -> action.target == "src/CliExample.jl", query_packet.nextActions)
    @test policy_status == 0
    @test policy_packet.method == "search/policy"
    @test any(handle -> handle.id == "JULIA-AGENT-PROJECT-001", policy_packet.semanticHandles)
    @test any(hit -> hit.symbol == "JULIA-AGENT-PROJECT-001", policy_packet.hits)
    @test ingest_status == 0
    @test ingest_packet.method == "search/ingest"
    @test ingest_packet.inputDetection.source == "path-list"
    @test any(action -> action.target == "src/CliExample.jl", ingest_packet.nextActions)
    @test semantic_status == 0
    @test semantic_packet.schemaId == "agent.semantic-protocols.semantic-fact-graph"
    @test semantic_packet.languageId == "julia"
    @test semantic_packet.providerId == "asp-julia"
    @test semantic_packet.query == "Vector collection fields"
    semantic_field_nodes = [
        node for node in semantic_packet.nodes
        if node.kind == "field" && node.value == "names: Vector{String}"
    ]
    @test length(semantic_field_nodes) == 1
    semantic_field = only(semantic_field_nodes)
    @test semantic_field.role == "struct-field"
    @test semantic_field.fields.languageId == "julia"
    @test semantic_field.fields.providerId == "asp-julia"
    @test semantic_field.fields.semanticFactKind == "field"
    @test semantic_field.fields.provenance == "parser"
    @test semantic_field.fields.confidence == "exact"
    @test semantic_field.fields.freshness == "fresh"
    @test semantic_field.fields.containerKind == "struct"
    @test semantic_field.fields.containerName == "Catalog"
    @test semantic_field.fields.fieldName == "names"
    @test semantic_field.fields.typeValue == "Vector{String}"
    @test semantic_field.fields.elementShape == "collection"
    @test semantic_field.fields.contextLocator == "src/SemanticModels.jl:1:5"
    @test semantic_field.fields.collectionKind == "array"
    @test semantic_field.fields.collectionFamily == "sequence"
    @test semantic_field.fields.collectionImpl == "array"
    @test semantic_field.fields.field.ownerKind == "struct"
    @test semantic_field.fields.field.name == "names"
    @test semantic_field.fields.field.ownerPath == "src/SemanticModels.jl"
    @test collect(semantic_field.fields.field.access) == ["read", "append", "validate"]
    semantic_type = only([
        node for node in semantic_packet.nodes
        if node.kind == "type" && node.value == "Vector{String}"
    ])
    @test semantic_type.fields.semanticFactKind == "type"
    @test semantic_type.fields.type.name == "Vector{String}"
    semantic_collection = only([
        node for node in semantic_packet.nodes
        if node.kind == "collection" && node.value == "array"
    ])
    @test semantic_collection.fields.languageId == "julia"
    @test semantic_collection.fields.providerId == "asp-julia"
    @test semantic_collection.fields.semanticFactKind == "collection"
    @test semantic_collection.fields.collectionFamily == "sequence"
    @test semantic_collection.fields.collectionImpl == "array"
    @test semantic_collection.fields.collection.family == "sequence"
    @test semantic_collection.fields.collection.impl == "array"
    @test collect(semantic_collection.fields.collection.mutation) == ["append", "insert", "remove"]
    @test any(edge -> edge.relation == "has_type", semantic_packet.edges)
    @test any(edge -> edge.relation == "collection_of", semantic_packet.edges)
    @test any(
        node ->
            node.kind == "package" &&
                node.value == "CliExample" &&
                node.action == "package" &&
                node.fields.semanticFactKind == "package" &&
                node.fields.manifestPath == "Project.toml",
        semantic_packet.nodes,
    )
    semantic_package = only([
        node for node in semantic_packet.nodes
        if node.kind == "package" && node.value == "CliExample"
    ])
    @test any(
        edge ->
            edge.source == semantic_field.id &&
                edge.target == semantic_package.id &&
                edge.relation == "belongs_to",
        semantic_packet.edges,
    )
    @test any(
        node ->
            node.kind == "build" &&
                node.action == "build" &&
                node.fields.semanticFactKind == "build" &&
                node.fields.command == "julia --project=. -e 'using Pkg; Pkg.test()'",
        semantic_packet.nodes,
    )
    @test any(
        node ->
            node.kind == "dependency" &&
                node.value == "JSON" &&
                node.action == "deps" &&
                node.fields.semanticFactKind == "dependency" &&
                node.fields.dependencyKind == "normal" &&
                node.fields.versionReq == "1",
        semantic_packet.nodes,
    )
    @test any(
        node ->
            node.kind == "dependency" &&
                node.value == "Test" &&
                node.fields.dependencyKind == "dev",
        semantic_packet.nodes,
    )
    @test any(
        node ->
            node.kind == "test" &&
                node.path == "test/runtests.jl" &&
                node.action == "tests" &&
                node.fields.semanticFactKind == "test" &&
                node.fields.functionCount == 2,
        semantic_packet.nodes,
    )
    @test any(edge -> edge.relation == "builds", semantic_packet.edges)
    @test any(edge -> edge.relation == "depends_on", semantic_packet.edges)
    @test any(edge -> edge.relation == "tests", semantic_packet.edges)
    @test any(edge -> edge.relation == "belongs_to", semantic_packet.edges)
    @test registry_status == 0
    @test any(
        schema ->
            schema.schemaId == "agent.semantic-protocols.software-criterion-catalog" &&
                schema.path == "schemas/software-criterion-catalog.v1.schema.json",
        language.schemas,
    )
    @test any(
        schema ->
            schema.schemaId == "agent.semantic-protocols.semantic-fact-graph" &&
                schema.path == "schemas/semantic-fact-graph.v1.schema.json",
        language.schemas,
    )
    @test any(
        schema ->
            schema.schemaId == "agent.semantic-protocols.semantic-fact-ontology" &&
                schema.path == "schemas/semantic-fact-ontology.v1.schema.json",
        language.schemas,
    )
    @test any(
        descriptor -> startswith(descriptor.method, "search/") && descriptor.supportsJson == true,
        language.methodDescriptors,
    )
    @test any(
        descriptor ->
            descriptor.method == "search/workspace" &&
                descriptor.view == "workspace" &&
                descriptor.requiresQuery == false,
        language.methodDescriptors,
    )
    @test any(
        descriptor ->
            descriptor.method == "search/deps" &&
                descriptor.view == "deps" &&
                descriptor.requiresQuery == true,
        language.methodDescriptors,
    )
    @test any(
        descriptor ->
            descriptor.method == "search/query" &&
                descriptor.supportsQuerySet == true &&
                "lexical-set" in descriptor.acceptedQuerySetSelectors,
        language.methodDescriptors,
    )
    @test any(
        descriptor ->
                descriptor.method == "search/semantic-facts" &&
                descriptor.acceptsStdin == true &&
                length(descriptor.outputModes) == 1 &&
                only(descriptor.outputModes) == "json" &&
                collect(descriptor.outputSchemaIds) == ["agent.semantic-protocols.semantic-fact-graph"] &&
                collect(descriptor.packetSchemas) == ["semantic-fact-graph.v1", "semantic-fact-ontology.v1"],
        language.methodDescriptors,
    )
end
