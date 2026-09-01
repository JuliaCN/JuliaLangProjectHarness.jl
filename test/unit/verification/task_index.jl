@testset "verification task index" begin
    root = mktempdir()
    write_verification_project(root)

    index = build_julia_verification_task_index(root)
    kinds = [record.kind for record in index.records]

    @test index.project_root == root
    @test kinds == ["extension_boundary", "harness_policy", "pkg_test", "stress", "syntax_search"]
    @test all(record -> record.state == "pending", index.records)
    @test any(record -> occursin("Pkg.test()", join(record.command, " ")), index.records)
    @test any(
        record -> record.kind == "harness_policy" &&
                  occursin(
                      "assert_julia_project_harness_test_profile_clean",
                      join(record.command, " "),
                  ),
        index.records,
    )
    @test any(
        record -> record.kind == "extension_boundary" &&
                  record.evidence["extension"] == "VerifyJSONExt" &&
                  record.evidence["activation"] == "missing_test_target" &&
                  record.evidence["test_target"] == "Test",
        index.records,
    )

    rendered = render_julia_verification_task_index(index)
    json = render_julia_verification_task_index_json(index)
    template = render_julia_verification_receipt_template(index)

    @test occursin("VerificationTasks: count=5", rendered)
    @test occursin("owner=test/runtests.jl", rendered)
    @test occursin("fingerprint=", rendered)
    @test occursin("kind=stress", rendered)
    @test occursin("requires=scenario,load_steps,p50_ms,p99_ms,threshold,result", rendered)
    @test occursin("\"records\"", json)
    @test occursin("\"required_evidence\"", json)
    @test occursin("VerifyJSONExt", json)
    @test occursin("\"receipts\"", template)
    @test occursin("\"scenario\":\"\"", template)
    @test occursin("\"required_receipt\"", template)

    advice_out = IOBuffer()
    profile = assert_julia_project_harness_test_profile_clean(root; advice_io=advice_out)
    advice = String(take!(advice_out))
    @test profile.report.project_resolution.project_root == root
    @test [record.kind for record in profile.task_index.records] == kinds
    @test length(profile.profile_index.candidates) == 3
    @test isempty(profile.receipt_reviews)
    @test occursin("[verify-advice] pending=2", advice)
    @test occursin("kind=extension_boundary", advice)
    @test occursin("activation=missing_test_target", advice)
    @test occursin("kind=stress", advice)
    @test occursin("fingerprint=stress", advice)
    @test occursin("requires=scenario,load_steps,p50_ms,p99_ms,threshold,result", advice)

    profile_rendered = render_julia_verification_profile(profile)
    profile_json = render_julia_verification_profile_json(profile)

    @test occursin("VerificationProfiles: count=3", profile_rendered)
    @test occursin("responsibilities=test_profile_gate", profile_rendered)
    @test occursin("responsibilities=public_api", profile_rendered)
    @test occursin("state=missing_test_target", profile_rendered)
    @test occursin("responsibilities=extension_boundary", profile_rendered)
    @test occursin("\"profile_index\"", profile_json)
    @test occursin("\"receipt_reviews\"", profile_json)
    @test occursin("extension_boundary", profile_json)
end

@testset "verification task index carries Moshi extension capabilities" begin
    root = mktempdir()
    write_moshi_extension_verification_project(root)

    index = build_julia_verification_task_index(root)
    extension_task = only(record for record in index.records if record.kind == "extension_boundary")
    profile_index = build_julia_verification_profile_index(root)
    extension_candidate = only(
        candidate for candidate in profile_index.candidates if
        candidate.responsibilities == ["extension_boundary"]
    )
    rendered = render_julia_verification_task_index(index)
    profile_rendered = render_julia_verification_profile_index(profile_index)

    @test extension_task.evidence["capability_source"] == "Moshi"
    @test extension_task.evidence["capabilities"] == "syntax,domain-model,search"
    @test occursin("capability_source=Moshi", rendered)
    @test occursin("capabilities=syntax,domain-model,search", rendered)
    @test extension_candidate.evidence["capability_source"] == "Moshi"
    @test extension_candidate.evidence["capabilities"] == "syntax,domain-model,search"
    @test occursin("capabilities=syntax,domain-model,search", profile_rendered)

    advice_out = IOBuffer()
    assert_julia_project_harness_test_profile_clean(root; advice_io=advice_out)
    advice = String(take!(advice_out))
    @test occursin("capabilities=syntax,domain-model,search", advice)
end

@testset "verification task index marks activated package extensions" begin
    root = mktempdir()
    write(
        joinpath(root, "Project.toml"),
        """
        name = "ActivatedExtExample"
        uuid = "11111111-1111-1111-1111-111111111111"
        version = "0.1.0"

        [weakdeps]
        JSON = "682c06a0-de6a-54ab-a142-c8b1cf79cde6"

        [extensions]
        ActivatedJSONExt = ["JSON"]

        [compat]
        JSON = "1"

        [extras]
        JSON = "682c06a0-de6a-54ab-a142-c8b1cf79cde6"
        Test = "8dfed614-e22c-5e08-85e1-65c5234f0b40"

        [targets]
        test = ["JSON", "Test"]
        """,
    )
    mkpath(joinpath(root, "src"))
    mkpath(joinpath(root, "ext"))
    write(joinpath(root, "src", "ActivatedExtExample.jl"), "module ActivatedExtExample\nend\n")
    write(joinpath(root, "ext", "ActivatedJSONExt.jl"), "module ActivatedJSONExt\nend\n")

    index = build_julia_verification_task_index(root)
    extension_task = only(record for record in index.records if record.kind == "extension_boundary")
    profile_index = build_julia_verification_profile_index(root)
    extension_candidate = only(
        candidate for candidate in profile_index.candidates if
        candidate.responsibilities == ["extension_boundary"]
    )

    @test extension_task.evidence["activation"] == "test_target"
    @test extension_task.evidence["test_target"] == "JSON,Test"
    @test occursin("Pkg.test()", join(extension_task.command, " "))
    @test extension_candidate.state == "test_target"
end

@testset "verification task index includes project-owned benchmark gates" begin
    root = mktempdir()
    write_benchmark_verification_project(root)

    index = build_julia_verification_task_index(root)
    performance_tasks = [record for record in index.records if record.kind == "performance"]
    rendered = render_julia_verification_task_index(index)
    advice = render_julia_verification_pending_advice(
        build_julia_project_verification_profile(root),
    )

    @test [record.kind for record in index.records] == [
        "performance",
        "performance",
        "pkg_test",
    ]
    @test [relpath(record.owner_path, root) for record in performance_tasks] == [
        joinpath("benchmark", "runbenchmarks.jl"),
        joinpath("test", "perf", "runtests.jl"),
    ]
    @test performance_tasks[1].command == [
        "julia",
        "--project=$(joinpath(root, "benchmark"))",
        "-e",
        "cd($(repr(root))) do; include(\"benchmark/runbenchmarks.jl\"); end",
    ]
    @test performance_tasks[2].command == [
        "julia",
        "--project=$(root)",
        "-e",
        "cd($(repr(root))) do; include(\"test/perf/runtests.jl\"); end",
    ]
    @test performance_tasks[1].evidence["benchmark_project"] == "benchmark/Project.toml"
    @test performance_tasks[1].evidence["activation"] == "local_project"
    @test performance_tasks[2].evidence["benchmark_project"] == "root"
    @test performance_tasks[2].evidence["activation"] == "root_project"
    @test occursin("kind=performance", rendered)
    @test occursin("owner=benchmark/runbenchmarks.jl", rendered)
    @test occursin("benchmark_command=julia", rendered)
    @test !occursin("algorithm_shapes=branchy,nested-loop", rendered)
    @test occursin("[verify-advice] pending=2", advice)
    @test occursin("entry=benchmark/runbenchmarks.jl", advice)
    @test occursin("benchmark_command=julia", advice)
end

@testset "verification task index owns package microbench gate" begin
    root = dirname(dirname(dirname(@__DIR__)))
    index = build_julia_verification_task_index(root)
    performance_tasks = [
        record for record in index.records
        if record.kind == "performance" &&
           relpath(record.owner_path, root) == joinpath("test", "perf", "runtests.jl")
    ]

    @test length(performance_tasks) == 1
    task = only(performance_tasks)
    @test task.evidence["benchmark_project"] == "root"
    @test task.evidence["activation"] == "root_project"
    @test task.evidence["entry"] == joinpath("test", "perf", "runtests.jl")
    @test task.command == [
        "julia",
        "--project=$(root)",
        "-e",
        "cd($(repr(root))) do; include(\"test/perf/runtests.jl\"); end",
    ]
end

@testset "verification task index includes package-owned examples project" begin
    root = mktempdir()
    write_example_verification_project(root)

    index = build_julia_verification_task_index(root)
    example_task = only(record for record in index.records if record.kind == "example_run")
    rendered = render_julia_verification_task_index(index)

    @test [record.kind for record in index.records] == ["example_run", "pkg_test"]
    @test example_task.owner_path == joinpath(root, "examples", "runexamples.jl")
    @test example_task.command == [
        "julia",
        "--project=$(joinpath(root, "examples"))",
        "-e",
        "cd($(repr(root))) do; include(\"examples/runexamples.jl\"); end",
    ]
    @test example_task.evidence["example_project"] == "examples/Project.toml"
    @test example_task.evidence["entry"] == "examples/runexamples.jl"
    @test example_task.evidence["activation"] == "examples_project"
    @test occursin("kind=example_run", rendered)
    @test occursin("owner=examples/runexamples.jl", rendered)
    @test occursin("example_command=julia", rendered)
end
