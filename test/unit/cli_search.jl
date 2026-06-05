@testset "cli agent guide and policy search output" begin
    root = mktempdir()
    write_cli_project(root)
    guide_out = IOBuffer()
    prime_out = IOBuffer()
    owner_out = IOBuffer()
    text_out = IOBuffer()
    query_out = IOBuffer()
    policy_out = IOBuffer()
    miss_out = IOBuffer()
    ingest_out = IOBuffer()
    check_out = IOBuffer()

    guide_status = run_julia_project_harness_cli(["agent", "guide", root]; out=guide_out)
    prime_status = run_julia_project_harness_cli(
        ["search", "prime", "--view", "seeds", root];
        out=prime_out,
    )
    owner_status = run_julia_project_harness_cli(
        ["search", "owner", "src/CliExample.jl", "--view", "seeds", root];
        out=owner_out,
    )
    text_status = run_julia_project_harness_cli(
        ["search", "fzf", "run", "owner", "tests", "--view", "seeds", root];
        out=text_out,
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
            root,
        ];
        out=query_out,
    )
    policy_status = run_julia_project_harness_cli(
        ["search", "policy", "JULIA-PROJ-R001", "owner", "tests", "--view", "seeds", root];
        out=policy_out,
    )
    miss_status = run_julia_project_harness_cli(
        ["search", "policy", "JULIA-UNKNOWN-R999", "owner", "tests", "--view", "seeds", root];
        out=miss_out,
    )
    check_status = run_julia_project_harness_cli(["check", "--changed", root]; out=check_out)
    ingest_status = let input = "src/CliExample.jl:1:module CliExample\ntest/runtests.jl:3:@testset \"run\" begin\n",
        pipe = Pipe()
        writer = @async begin
            write(pipe, input)
            close(pipe)
        end
        status = redirect_stdin(pipe) do
            run_julia_project_harness_cli(
                ["search", "ingest", "owner", "tests", "--view", "seeds", root];
                out=ingest_out,
            )
        end
        wait(writer)
        status
    end

    guide_rendered = String(take!(guide_out))
    prime_rendered = String(take!(prime_out))
    owner_rendered = String(take!(owner_out))
    text_rendered = String(take!(text_out))
    query_rendered = String(take!(query_out))
    policy_rendered = String(take!(policy_out))
    miss_rendered = String(take!(miss_out))
    ingest_rendered = String(take!(ingest_out))
    check_rendered = String(take!(check_out))

    @test guide_status == 0
    @test occursin("[julia-harness-guide]", guide_rendered)
    @test occursin("julia-project-harness agent registry --json", guide_rendered)
    @test occursin("julia-project-harness query <owner-path> --term", guide_rendered)
    @test occursin("julia-project-harness search policy", guide_rendered)
    @test occursin("julia-project-harness search query --from-hook direct-source-read", guide_rendered)
    @test occursin("julia-project-harness export index", guide_rendered)
    @test prime_status == 0
    @test occursin("[search-prime]", prime_rendered)
    @test occursin("|seed owner:src/CliExample.jl", prime_rendered)
    @test occursin("windowSet=owner:src/CliExample.jl,tests:test/runtests.jl", prime_rendered)
    @test owner_status == 0
    @test occursin("[search-owner] q=src/CliExample.jl owner=1", owner_rendered)
    @test occursin("|seed owner:src/CliExample.jl", owner_rendered)
    @test occursin("windowSet=owner:src/CliExample.jl,tests:test/runtests.jl", owner_rendered)
    @test text_status == 0
    @test occursin("[search-fzf] q=\"run\"", text_rendered)
    @test occursin("|seed owner:src/CliExample.jl", text_rendered)
    @test occursin("test/runtests.jl", text_rendered)
    @test occursin("windowSet=owner:src/CliExample.jl,tests:test/runtests.jl", text_rendered)
    @test query_status == 0
    @test occursin("[search-query] hook=direct-source-read", query_rendered)
    @test occursin("selector=\"**/*.jl\"", query_rendered)
    @test occursin("|seed owner:src/CliExample.jl", query_rendered)
    @test occursin("test/runtests.jl", query_rendered)
    @test occursin("windowSet=owner:src/CliExample.jl,tests:test/runtests.jl", query_rendered)
    @test policy_status == 0
    @test occursin("[search-policy] q=JULIA-PROJ-R001 handle=1", policy_rendered)
    @test occursin("|handle JULIA-PROJ-R001 kind=policy-rule", policy_rendered)
    @test occursin("|seed owner:src/rules/catalog.jl", policy_rendered)
    @test occursin("|seed tests:test/unit/rule_catalog.jl,test/unit/project/policy.jl", policy_rendered)
    @test occursin(
        "windowSet=owner:src/rules/catalog.jl,tests:test/unit/rule_catalog.jl,tests:test/unit/project/policy.jl",
        policy_rendered,
    )
    @test miss_status == 0
    @test occursin("status=miss", miss_rendered)
    @test occursin("|note kind=policy-not-found", miss_rendered)
    @test ingest_status == 0
    @test occursin("[search-ingest] owner=1 tests=1 pipes=owner,tests", ingest_rendered)
    @test occursin("|seed owner:src/CliExample.jl", ingest_rendered)
    @test occursin("|seed tests:test/runtests.jl", ingest_rendered)
    @test occursin("windowSet=owner:src/CliExample.jl,tests:test/runtests.jl", ingest_rendered)
    @test check_status == 0
    @test check_rendered == "[ok] julia\n"
end
