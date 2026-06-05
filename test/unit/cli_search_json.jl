@testset "cli search json packets" begin
    root = mktempdir()
    write_cli_project(root)
    prime_out = IOBuffer()
    fzf_out = IOBuffer()
    query_out = IOBuffer()
    policy_out = IOBuffer()
    ingest_out = IOBuffer()
    registry_out = IOBuffer()

    prime_status = run_julia_project_harness_cli(
        ["search", "prime", "--view", "seeds", "--json", root];
        out=prime_out,
    )
    fzf_status = run_julia_project_harness_cli(
        ["search", "fzf", "run", "owner", "tests", "--view", "seeds", "--json", root];
        out=fzf_out,
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
            root,
        ];
        out=query_out,
    )
    policy_status = run_julia_project_harness_cli(
        ["search", "policy", "JULIA-PROJ-R001", "owner", "tests", "--view", "seeds", "--json", root];
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
                ["search", "ingest", "owner", "tests", "--view", "seeds", "--json", root];
                out=ingest_out,
            )
        end
        wait(writer)
        status
    end
    registry_status = run_julia_project_harness_cli(["agent", "registry", "--json", root]; out=registry_out)

    prime_packet = JSON3.read(String(take!(prime_out)))
    fzf_packet = JSON3.read(String(take!(fzf_out)))
    query_packet = JSON3.read(String(take!(query_out)))
    policy_packet = JSON3.read(String(take!(policy_out)))
    ingest_packet = JSON3.read(String(take!(ingest_out)))
    registry = JSON3.read(String(take!(registry_out)))
    language = only(registry.languages)

    @test prime_status == 0
    @test prime_packet.schemaId == "agent.semantic-protocols.semantic-search-packet"
    @test prime_packet.method == "search/prime"
    @test prime_packet.renderMode == "seeds"
    @test any(owner -> owner.path == "src/CliExample.jl", prime_packet.owners)
    @test any(fact -> fact.ownerPath == "src/CliExample.jl", prime_packet.nativeSyntaxFacts)
    @test fzf_status == 0
    @test fzf_packet.method == "search/fzf"
    @test fzf_packet.query == "run"
    @test any(hit -> hit.symbol == "run", fzf_packet.hits)
    @test any(action -> action.target == "src/CliExample.jl", fzf_packet.nextActions)
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
    @test any(handle -> handle.id == "JULIA-PROJ-R001", policy_packet.semanticHandles)
    @test any(hit -> hit.symbol == "JULIA-PROJ-R001", policy_packet.hits)
    @test ingest_status == 0
    @test ingest_packet.method == "search/ingest"
    @test ingest_packet.inputDetection.source == "path-list"
    @test any(action -> action.target == "src/CliExample.jl", ingest_packet.nextActions)
    @test registry_status == 0
    @test any(
        descriptor -> startswith(descriptor.method, "search/") && descriptor.supportsJson == true,
        language.methodDescriptors,
    )
    @test any(
        descriptor ->
            descriptor.method == "search/query" &&
                descriptor.supportsQuerySet == true &&
                "fuzzy-set" in descriptor.acceptedQuerySetSelectors,
        language.methodDescriptors,
    )
end
