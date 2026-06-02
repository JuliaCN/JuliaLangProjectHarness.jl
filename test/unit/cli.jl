function write_cli_project(root::AbstractString)
    write(
        joinpath(root, "Project.toml"),
        """
        name = "CliExample"
        uuid = "11111111-1111-1111-1111-111111111111"
        version = "0.1.0"
        """,
    )
    mkpath(joinpath(root, "src"))
    write(
        joinpath(root, "src", "CliExample.jl"),
        """
        module CliExample
        export run
        \"\"\"Run a value through the CLI fixture.\"\"\"
        run(value) = helper(value)
        helper(value) = string(value)
        end
        """,
    )
    mkpath(joinpath(root, "test"))
    write(
        joinpath(root, "test", "runtests.jl"),
        """
        using Test
        using CliExample
        @testset "run" begin
            @test run(1) == "1"
        end
        """,
    )
end

function write_cli_docs_project(root::AbstractString)
    write_cli_project(root)
    mkpath(joinpath(root, "docs", "src"))
    write(
        joinpath(root, "docs", "Project.toml"),
        """
        [deps]
        Documenter = "e30172f5-a6a5-5a46-863b-614d45cd2de4"
        """,
    )
    write(joinpath(root, "docs", "make.jl"), "using Documenter\nmakedocs()\n")
    write(joinpath(root, "docs", "src", "index.md"), "# CliExample\n")
end

@testset "cli compact report" begin
    root = mktempdir()
    write_cli_project(root)
    out = IOBuffer()
    err = IOBuffer()

    status = run_julia_project_harness_cli([root]; out, err)

    @test status == 0
    @test String(take!(out)) == "[ok] julia\n"
    @test isempty(String(take!(err)))
end

@testset "cli json and snapshot output" begin
    root = mktempdir()
    write_cli_project(root)
    json_out = IOBuffer()
    snapshot_out = IOBuffer()

    json_status = run_julia_project_harness_cli(["--json", root]; out=json_out)
    snapshot_status = run_julia_project_harness_cli(["--agent-snapshot", root]; out=snapshot_out)

    @test json_status == 0
    @test occursin("\"files\"", String(take!(json_out)))
    @test snapshot_status == 0
    @test occursin("Package: CliExample", String(take!(snapshot_out)))
end

@testset "cli search output" begin
    root = mktempdir()
    write_cli_project(root)
    out = IOBuffer()

    status = run_julia_project_harness_cli(
        ["--search", "CLI fixture", "--tag", "doc", "--limit", "2", root];
        out,
    )
    rendered = String(take!(out))

    @test status == 0
    @test occursin("SearchResults: count=1", rendered)
    @test occursin("kind=doc name=run", rendered)
    @test occursin("src/CliExample.jl", rendered)
end

@testset "cli agent guide and policy search output" begin
    root = mktempdir()
    write_cli_project(root)
    guide_out = IOBuffer()
    prime_out = IOBuffer()
    owner_out = IOBuffer()
    text_out = IOBuffer()
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
    policy_rendered = String(take!(policy_out))
    miss_rendered = String(take!(miss_out))
    ingest_rendered = String(take!(ingest_out))
    check_rendered = String(take!(check_out))

    @test guide_status == 0
    @test occursin("[julia-harness-guide]", guide_rendered)
    @test occursin("julia-project-harness search policy", guide_rendered)
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

@testset "cli verification task output" begin
    root = mktempdir()
    write_cli_project(root)
    out = IOBuffer()
    json_out = IOBuffer()
    profile_out = IOBuffer()
    profile_json_out = IOBuffer()
    template_out = IOBuffer()
    receipt_out = IOBuffer()
    receipt_json_out = IOBuffer()
    bad_receipt_out = IOBuffer()

    status = run_julia_project_harness_cli(["--verification-tasks", root]; out)
    json_status = run_julia_project_harness_cli(["--verification-tasks-json", root]; out=json_out)
    profile_status = run_julia_project_harness_cli(["--verification-profile", root]; out=profile_out)
    profile_json_status = run_julia_project_harness_cli(
        ["--verification-profile-json", root];
        out=profile_json_out,
    )
    template_status = run_julia_project_harness_cli(
        ["--verification-receipt-template", root];
        out=template_out,
    )
    index = build_julia_verification_task_index(root)
    security = only(record for record in index.records if record.kind == "security")
    stress = only(record for record in index.records if record.kind == "stress")
    receipt_path = joinpath(root, "receipts.json")
    write(
        receipt_path,
        """
        {"receipts":[{"fingerprint":"$(security.fingerprint)","attack_classes":"input validation, privilege boundary","authorization_boundary":"public API only","result":"pass"},{"fingerprint":"$(stress.fingerprint)","scenario":"cli public API load smoke","load_steps":"1,5","p50_ms":"1.0","p99_ms":"3.0","threshold":"p99_ms <= 10","result":"pass"}]}
        """,
    )
    bad_receipt_path = joinpath(root, "bad-receipts.json")
    write(
        bad_receipt_path,
        """
        {"receipts":[{"fingerprint":"$(stress.fingerprint)","scenario":"todo"}]}
        """,
    )
    receipt_status = run_julia_project_harness_cli(
        ["--verification-receipts", receipt_path, root];
        out=receipt_out,
    )
    receipt_json_status = run_julia_project_harness_cli(
        ["--verification-receipts-json", receipt_path, root];
        out=receipt_json_out,
    )
    bad_receipt_status = run_julia_project_harness_cli(
        ["--verification-receipts", bad_receipt_path, root];
        out=bad_receipt_out,
    )

    @test status == 0
    task_rendered = String(take!(out))
    @test occursin("VerificationTasks: count=3", task_rendered)
    @test occursin("kind=pkg_test", task_rendered)
    @test occursin("kind=security", task_rendered)
    @test occursin("kind=stress", task_rendered)
    @test occursin("fingerprint=stress", task_rendered)
    @test occursin("requires=attack_classes,authorization_boundary,result", task_rendered)
    @test occursin("requires=scenario,load_steps,p50_ms,p99_ms,threshold,result", task_rendered)
    @test json_status == 0
    json_rendered = String(take!(json_out))
    @test occursin("\"records\"", json_rendered)
    @test occursin("\"required_evidence\"", json_rendered)
    @test profile_status == 0
    @test occursin("VerificationProfiles:", String(take!(profile_out)))
    @test profile_json_status == 0
    @test occursin("\"profile_index\"", String(take!(profile_json_out)))
    @test template_status == 0
    template_rendered = String(take!(template_out))
    @test occursin("\"receipts\"", template_rendered)
    @test occursin("\"scenario\":\"\"", template_rendered)
    @test receipt_status == 0
    @test occursin("VerificationReceiptReview: count=2 accepted=2 incomplete=0", String(take!(receipt_out)))
    @test receipt_json_status == 0
    @test occursin("\"reviews\"", String(take!(receipt_json_out)))
    @test bad_receipt_status == 1
    @test occursin("missing=load_steps,p50_ms,p99_ms,threshold,result", String(take!(bad_receipt_out)))
end

@testset "cli verification task output includes docs build" begin
    root = mktempdir()
    write_cli_docs_project(root)
    out = IOBuffer()

    status = run_julia_project_harness_cli(["--verification-tasks", root]; out)
    rendered = String(take!(out))

    @test status == 0
    @test occursin("kind=docs_build", rendered)
    @test occursin("owner=docs/make.jl", rendered)
    @test occursin("tool=Documenter", rendered)
end

@testset "cli rejects conflicting modes" begin
    root = mktempdir()
    write_cli_project(root)
    out = IOBuffer()
    err = IOBuffer()

    status = run_julia_project_harness_cli(["--json", "--agent-snapshot", root]; out, err)

    @test status == 2
    @test isempty(String(take!(out)))
    @test occursin("expected only one output mode", String(take!(err)))
end
