using JSON3

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

    json_status = run_julia_project_harness_cli(["--json", root]; out = json_out)
    snapshot_status =
        run_julia_project_harness_cli(["--agent-snapshot", root]; out = snapshot_out)

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

@testset "cli agent registry advertises schemas and methods" begin
    root = mktempdir()
    write_cli_project(root)
    compact_out = IOBuffer()
    json_out = IOBuffer()
    doctor_out = IOBuffer()

    compact_status =
        run_julia_project_harness_cli(["agent", "registry", root]; out = compact_out)
    json_status =
        run_julia_project_harness_cli(["agent", "registry", "--json", root]; out = json_out)
    doctor_status =
        run_julia_project_harness_cli(["agent", "doctor", "--json", root]; out = doctor_out)
    registry = JSON3.read(String(take!(json_out)))
    doctor_registry = JSON3.read(String(take!(doctor_out)))
    language = only(registry.languages)

    @test compact_status == 0
    @test occursin("[julia-agent-registry]", String(take!(compact_out)))
    @test json_status == 0
    @test doctor_status == 0
    @test registry.registryId == "agent.semantic-protocols.semantic-language-registry"
    @test doctor_registry.registryId == registry.registryId
    @test registry.protocolId == "agent.semantic-protocols.semantic-language"
    @test language.languageId == "julia"
    @test language.providerId == "julia-lang-project-harness"
    @test language.binary == "asp-julia-harness"
    @test "search/prime" in language.methods
    @test "search/fzf" in language.methods
    @test "search/query" in language.methods
    @test "search/policy" in language.methods
    @test "query/owner-items" in language.methods
    @test "guide" in language.methods
    @test !("agent/guide" in language.methods)
    @test "agent/doctor" in language.methods
    @test "agent/registry" in language.methods
    @test any(
        schema ->
            schema.schemaId == "agent.semantic-protocols.semantic-native-syntax-fact-index",
        language.schemas,
    )
    @test any(
        schema -> schema.path == "schemas/semantic-language-registry.v1.schema.json",
        language.schemas,
    )
    @test any(
        descriptor ->
            descriptor.method == "search/policy" &&
            "agent.semantic-protocols.semantic-handle" in descriptor.outputSchemaIds,
        language.methodDescriptors,
    )
    @test any(
        descriptor ->
            descriptor.method == "search/query" &&
            descriptor.supportsJson == true &&
            "--from-hook" in descriptor.requiredOptions &&
            "agent.semantic-protocols.semantic-native-syntax-fact-index" in
            descriptor.outputSchemaIds,
        language.methodDescriptors,
    )
    @test any(
        descriptor ->
            descriptor.method == "query/owner-items" &&
            descriptor.supportsJson == true &&
            "agent.semantic-protocols.semantic-query-packet" in descriptor.outputSchemaIds,
        language.methodDescriptors,
    )
end

@testset "package-local semantic schemas stay synchronized when protocol root is present" begin
    package_root = normpath(joinpath(@__DIR__, "..", ".."))
    protocol_schemas = normpath(joinpath(package_root, "..", "..", "schemas"))
    registrations = julia_schema_registrations()

    @test any(
        registration ->
            registration["schemaId"] ==
            "agent.semantic-protocols.semantic-language-registry",
        registrations,
    )
    @test any(
        registration ->
            registration["schemaId"] ==
            "agent.semantic-protocols.semantic-native-syntax-fact-index",
        registrations,
    )
    for registration in registrations
        package_schema_path = joinpath(package_root, registration["path"])
        @test isfile(package_schema_path)
        if isdir(protocol_schemas)
            protocol_schema_path =
                joinpath(protocol_schemas, basename(registration["path"]))
            isfile(protocol_schema_path) || continue
            @test read(package_schema_path, String) == read(protocol_schema_path, String)
        end
    end
end

@testset "cli export index packet" begin
    root = mktempdir()
    write_cli_project(root)
    out = IOBuffer()

    status = run_julia_project_harness_cli(["export", "index", root]; out)
    packet = JSON3.read(String(take!(out)))

    @test status == 0
    @test packet.schemaId == "agent.semantic-protocols.semantic-native-syntax-fact-index"
    @test packet.schemaVersion == "1"
    @test packet.protocolId == "agent.semantic-protocols.semantic-language"
    @test packet.protocolVersion == "1"
    @test packet.languageId == "julia"
    @test packet.providerId == "julia-lang-project-harness"
    @test packet.projectRoot == abspath(root)
    @test length(packet.facts) > 0
    @test length(packet.indexes) >= 5
    @test any(fact -> fact.name == "run" && fact.languageKind == "doc", packet.facts)
    @test any(fact -> haskey(fact, :qualifiedName), packet.facts)
    @test any(fact -> haskey(fact, :relations), packet.facts)
    @test any(fact -> fact.kind == "argument", packet.facts)
    @test any(index -> index.name == "public-api", packet.indexes)
    @test all(fact -> !startswith(fact.ownerPath, "/"), packet.facts)
    @test_throws ErrorException run_julia_harness_export_cli(String[])
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
    json_status =
        run_julia_project_harness_cli(["--verification-tasks-json", root]; out = json_out)
    profile_status =
        run_julia_project_harness_cli(["--verification-profile", root]; out = profile_out)
    profile_json_status = run_julia_project_harness_cli(
        ["--verification-profile-json", root];
        out = profile_json_out,
    )
    template_status = run_julia_project_harness_cli(
        ["--verification-receipt-template", root];
        out = template_out,
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
        out = receipt_out,
    )
    receipt_json_status = run_julia_project_harness_cli(
        ["--verification-receipts-json", receipt_path, root];
        out = receipt_json_out,
    )
    bad_receipt_status = run_julia_project_harness_cli(
        ["--verification-receipts", bad_receipt_path, root];
        out = bad_receipt_out,
    )

    @test status == 0
    task_rendered = String(take!(out))
    @test occursin("VerificationTasks: count=3", task_rendered)
    @test occursin("kind=pkg_test", task_rendered)
    @test occursin("kind=security", task_rendered)
    @test occursin("kind=stress", task_rendered)
    @test occursin("fingerprint=stress", task_rendered)
    @test occursin("requires=attack_classes,authorization_boundary,result", task_rendered)
    @test occursin(
        "requires=scenario,load_steps,p50_ms,p99_ms,threshold,result",
        task_rendered,
    )
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
    @test occursin(
        "VerificationReceiptReview: count=2 accepted=2 incomplete=0",
        String(take!(receipt_out)),
    )
    @test receipt_json_status == 0
    @test occursin("\"reviews\"", String(take!(receipt_json_out)))
    @test bad_receipt_status == 1
    @test occursin(
        "missing=load_steps,p50_ms,p99_ms,threshold,result",
        String(take!(bad_receipt_out)),
    )
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
