@testset "cli guide and policy search output" begin
    root = mktempdir()
    write_cli_project(root)
    guide_out = IOBuffer()
    workspace_out = IOBuffer()
    prime_out = IOBuffer()
    owner_out = IOBuffer()
    text_out = IOBuffer()
    query_out = IOBuffer()
    policy_out = IOBuffer()
    miss_out = IOBuffer()
    ingest_out = IOBuffer()
    check_out = IOBuffer()

    guide_status = run_julia_project_harness_cli(["guide", root]; out=guide_out)
    workspace_status = run_julia_project_harness_cli(
        ["search", "workspace", "--view", "seeds", root];
        out=workspace_out,
    )
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
    ingest_extra_root_err = IOBuffer()
    ingest_extra_root_status =
        run_julia_project_harness_cli(
            ["search", "ingest", "owner", "tests", "extra", "--view", "seeds", root];
            out=IOBuffer(),
            err=ingest_extra_root_err,
        )

    guide_rendered = String(take!(guide_out))
    workspace_rendered = String(take!(workspace_out))
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
    @test occursin("asp julia guide", guide_rendered)
    @test occursin("asp julia agent doctor --json", guide_rendered)
    @test !occursin("asp julia agent guide", guide_rendered)
    @test occursin("asp julia search workspace --view seeds", guide_rendered)
    @test occursin("asp julia query <owner-path> --term", guide_rendered)
    @test occursin("--workspace <workspace-root>", guide_rendered)
    @test occursin("asp julia search policy", guide_rendered)
    @test occursin("asp julia search query --from-hook direct-source-read", guide_rendered)
    @test !occursin("asp julia export index", guide_rendered)
    @test !occursin("asp julia --search", guide_rendered)
    @test !occursin("--code .", guide_rendered)
    @test !occursin("julia-project-harness", guide_rendered)
    @test workspace_status == 0
    @test occursin("[search-workspace]", workspace_rendered)
    @test occursin("view=workspace", workspace_rendered)
    @test occursin("O=owner:path(src/CliExample.jl)!owner", workspace_rendered)
    @test prime_status == 0
    @test occursin("[search-prime]", prime_rendered)
    @test occursin("view=prime", prime_rendered)
    @test occursin("O=owner:path(src/CliExample.jl)!owner", prime_rendered)
    @test occursin("T=test:path(test/runtests.jl)!tests", prime_rendered)
    @test owner_status == 0
    @test occursin("[search-owner] q=src/CliExample.jl view=owner", owner_rendered)
    @test occursin("O=owner:path(src/CliExample.jl)!owner", owner_rendered)
    @test occursin("T=test:path(test/runtests.jl)!tests", owner_rendered)
    @test text_status == 0
    @test occursin("[search-fzf] q=run view=fzf", text_rendered)
    @test occursin("Q=query:term(run)!fzf", text_rendered)
    @test occursin("O=owner:path(src/CliExample.jl)!owner", text_rendered)
    @test query_status == 0
    @test occursin("[search-query] q=run", query_rendered)
    @test occursin("selector=**/*.jl", query_rendered)
    @test occursin("O=owner:path(src/CliExample.jl)!owner", query_rendered)
    @test policy_status == 0
    @test occursin("[search-policy] q=JULIA-PROJ-R001 view=policy", policy_rendered)
    @test occursin("O=owner:path(src/rules/catalog.jl)!owner", policy_rendered)
    @test occursin("T=test:path(test/unit/rule_catalog.jl)!tests", policy_rendered)
    @test occursin("T2=test:path(test/unit/project/policy.jl)!tests", policy_rendered)
    @test miss_status == 0
    @test occursin("[search-policy] q=JULIA-UNKNOWN-R999 view=policy", miss_rendered)
    @test occursin("G>{}", miss_rendered)
    @test occursin("rank= frontier=", miss_rendered)
    @test ingest_status == 0
    @test occursin("[search-ingest]", ingest_rendered)
    @test occursin("O=owner:path(src/CliExample.jl)!owner", ingest_rendered)
    @test occursin("T=test:path(test/runtests.jl)!tests", ingest_rendered)
    @test occursin("frontier=O.owner,T.tests", ingest_rendered)
    @test ingest_extra_root_status != 0
    @test occursin(
        "expected at most one PROJECT_ROOT argument",
        String(take!(ingest_extra_root_err)),
    )
    @test check_status == 0
    @test check_rendered == "[ok] julia\n"
end
