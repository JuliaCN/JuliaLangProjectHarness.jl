@testset "verification task index includes Documenter docs build" begin
    root = mktempdir()
    write_documenter_project(root)

    index = build_julia_verification_task_index(root)
    rendered = render_julia_verification_task_index(index)
    docs_task = only(record for record in index.records if record.kind == "docs_build")

    @test [record.kind for record in index.records] == ["docs_build", "pkg_test", "stress"]
    @test docs_task.owner_path == joinpath(root, "docs", "make.jl")
    @test docs_task.command == [
        "julia",
        "--project=$(joinpath(root, "docs"))",
        "-e",
        "cd($(repr(joinpath(root, "docs")))) do; include(\"make.jl\"); end",
    ]
    @test docs_task.evidence["tool"] == "Documenter"
    @test docs_task.evidence["docs_project"] == "docs/Project.toml"
    @test docs_task.evidence["make"] == "docs/make.jl"
    @test occursin("kind=docs_build", rendered)
    @test occursin("owner=docs/make.jl", rendered)
    @test occursin("Build Documenter docs and run doctests", rendered)
end

@testset "verification profile infers performance from algorithm shape" begin
    root = mktempdir()
    write_algorithm_shape_project(root)

    index = build_julia_verification_profile_index(root)
    candidate = only(index.candidates)
    rendered = render_julia_verification_profile_index(index)

    @test candidate.responsibilities == ["latency_sensitive"]
    @test candidate.task_kinds == ["pkg_test", "performance"]
    @test candidate.evidence["algorithm_shapes"] == "branchy,nested-loop"
    @test candidate.evidence["hot_function_count"] == "1"
    @test candidate.evidence["hot_functions"] ==
          "src/ShapeExample.jl:scan_values:branchy+nested-loop"
    @test occursin("responsibilities=latency_sensitive", rendered)
    @test occursin("algorithm_shapes=branchy,nested-loop", rendered)

    task_index = build_julia_verification_task_index(root)
    task_kinds = [record.kind for record in task_index.records]
    task_rendered = render_julia_verification_task_index(task_index)
    advice = render_julia_verification_pending_advice(
        build_julia_project_verification_profile(root),
    )

    @test task_kinds == ["performance", "pkg_test"]
    @test occursin("kind=performance", task_rendered)
    @test occursin("algorithm_shapes=branchy,nested-loop", task_rendered)
    @test occursin("hot_functions=src/ShapeExample.jl:scan_values", advice)
    @test occursin("requires=benchmark_command,baseline,regression_threshold", advice)
end

@testset "verification profile infers agent responsibilities from project facts" begin
    root = mktempdir()
    write_responsibility_project(root)

    index = build_julia_verification_profile_index(root)
    rendered = render_julia_verification_profile_index(index)
    candidate = only(index.candidates)

    @test candidate.responsibilities == [
        "public_api",
        "external_dependency",
        "persistence",
        "security_boundary",
        "latency_sensitive",
        "availability_critical",
    ]
    @test candidate.task_kinds == [
        "pkg_test",
        "syntax_search",
        "stress",
        "performance",
        "chaos",
        "security",
    ]
    @test candidate.evidence["direct_deps"] == "HTTP,JSON"
    @test candidate.evidence["network_roots"] == "HTTP"
    @test candidate.evidence["persistence_roots"] == "JSON"
    @test candidate.evidence["security_roots"] == "SHA"
    @test candidate.evidence["performance_roots"] == "LinearAlgebra"
    @test occursin("responsibilities=public_api,external_dependency", rendered)
    @test occursin("tasks=pkg_test,syntax_search,stress,performance,chaos,security", rendered)

    task_index = build_julia_verification_task_index(root)
    task_kinds = [record.kind for record in task_index.records]
    task_rendered = render_julia_verification_task_index(task_index)

    @test task_kinds == ["chaos", "performance", "pkg_test", "security", "stress"]
    @test occursin("kind=performance state=pending phase=after_unit_tests_pass", task_rendered)
    @test occursin("kind=security state=pending phase=before_release", task_rendered)
    @test occursin("fingerprint=performance", task_rendered)
    @test occursin(
        "requires=benchmark_command,baseline,regression_threshold,latency_or_throughput,allocation_profile,artifact",
        task_rendered,
    )
    @test occursin("requires=attack_classes,authorization_boundary,result", task_rendered)
    @test occursin("responsibilities=public_api,external_dependency", task_rendered)
    @test occursin("Agent should add or run Julia-native performance evidence", task_rendered)

    profile = build_julia_project_verification_profile(root)
    advice = render_julia_verification_pending_advice(profile)
    receipt_template = render_julia_verification_receipt_template(task_index)

    @test occursin("[verify-advice] pending=4", advice)
    @test occursin("kind=performance", advice)
    @test occursin("kind=security", advice)
    @test occursin("requires=benchmark_command,baseline,regression_threshold", advice)
    @test occursin("evidence=responsibilities=public_api,external_dependency", advice)
    @test !occursin("exports=", advice)
    @test occursin("\"benchmark_command\":\"\"", receipt_template)
    @test occursin("\"attack_classes\":\"\"", receipt_template)
    @test occursin("\"injected_failure\":\"\"", receipt_template)
end

@testset "verification profile reviews default agent receipt file" begin
    root = mktempdir()
    write_verification_project(root)
    receipt_root = joinpath(root, ".julia-harness")
    mkpath(receipt_root)
    receipt_path = joinpath(receipt_root, "verification-receipts.json")

    index = build_julia_verification_task_index(root)
    stress = only(record for record in index.records if record.kind == "stress")
    write(receipt_path, render_julia_verification_receipt_template(index))

    profile = build_julia_project_verification_profile(root)
    rendered = render_julia_verification_profile(profile)
    json = render_julia_verification_profile_json(profile)

    @test length(profile.receipt_reviews) == 1
    @test only(profile.receipt_reviews).status == :incomplete
    @test occursin("VerificationReceiptReview: count=1 accepted=0 incomplete=1", rendered)
    @test occursin("weak=scenario,load_steps,p50_ms,p99_ms,threshold,result", rendered)
    @test occursin("\"receipt_reviews\"", json)
    @test_throws ErrorException assert_julia_project_harness_test_profile_clean(
        root;
        advice_io=nothing,
    )

    write(
        receipt_path,
        """
        {"receipts":[{"fingerprint":"$(stress.fingerprint)","kind":"stress","owner_path":"src/VerifyExample.jl","scenario":"profile default receipt smoke","load_steps":"1,4,8","p50_ms":"1.0","p99_ms":"4.0","threshold":"p99_ms <= 10","result":"pass"}]}
        """,
    )
    accepted_advice_out = IOBuffer()
    accepted_profile = assert_julia_project_harness_test_profile_clean(
        root;
        advice_io=accepted_advice_out,
    )
    @test length(accepted_profile.receipt_reviews) == 1
    @test only(accepted_profile.receipt_reviews).status == :accepted
    accepted_advice = String(take!(accepted_advice_out))
    @test occursin("[verify-advice] pending=1", accepted_advice)
    @test occursin("kind=extension_boundary", accepted_advice)
    @test occursin("activation=missing_test_target", accepted_advice)
end
