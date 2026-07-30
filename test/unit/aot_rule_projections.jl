@testset "public method scattering uses concrete definition records" begin
    mktempdir() do root
        write(
            joinpath(root, "Project.toml"),
            "name = \"ScatteringFixture\"\n" *
            "uuid = \"11111111-1111-1111-1111-111111111111\"\n",
        )
        source_root = joinpath(root, "src")
        mkpath(source_root)
        first_owner = joinpath(source_root, "first.jl")
        second_owner = joinpath(source_root, "second.jl")
        write(first_owner, "scatter(x::Int) = x\n")
        write(second_owner, "scatter(x::String) = x\n")

        harness = JuliaLangProjectHarness
        parsed_files = [
            harness.parse_julia_file(first_owner),
            harness.parse_julia_file(second_owner),
        ]
        records = harness.public_api_definition_records(
            parsed_files,
            Set(["scatter"]),
        )
        @test records isa Dict{
            String,
            Vector{harness.PublicApiDefinitionRecord},
        }
        @test length(records["scatter"]) == 2

        scope = harness.julia_project_harness_scope(
            root,
            harness.default_julia_harness_config(),
        )
        findings = harness.public_method_family_scattering_findings(
            scope,
            parsed_files,
            Set(["scatter"]),
            Dict{String,Vector{String}}(),
            harness.rules_by_id(),
        )
        @test length(findings) == 1
        @test findings[1].rule_id == harness.AGENT_JL_R009
    end
end

@testset "test throws call names use bounded lexical projection" begin
    harness = JuliaLangProjectHarness
    call_names(expression) = harness.test_throws_call_names(
        harness.JuliaTestSyntax(
            1,
            1,
            "test_throws",
            "test_throws",
            nothing,
            0,
            0,
            0,
            0,
            String[],
            expression,
        ),
    )

    @test call_names("@test_throws ArgumentError parse_value(\"x\")") ==
          Set(["parse_value"])
    @test call_names(
        "@test_throws ErrorException begin validate(x); parse_value(y) end",
    ) == Set(["validate", "parse_value"])
    @test call_names(
        "@test_throws MyError outer(inner(x), Base.getindex(xs, 1))",
    ) == Set(["outer", "inner", "getindex"])
    @test call_names("@test_throws DomainError f(x + g(y))") ==
          Set(["f", "+", "g"])
    @test call_names("@test_throws ErrorException M.f(Dict(:a => g(1)))") ==
          Set(["f", "Dict", "=>", "g"])
    @test call_names("@test_throws ErrorException f(-1)") == Set(["f"])
    @test call_names("@test_throws ErrorException f(x-y)") == Set(["f", "-"])
    @test call_names("@test_throws ErrorException f(\"not_a_call()\")") ==
          Set(["f"])
end

@testset "inferred call names reuse bounded lexical projection" begin
    harness = JuliaLangProjectHarness
    call_names(expression) = harness.inferred_test_call_names(
        harness.JuliaTestSyntax(
            1,
            1,
            "inferred",
            "inferred",
            nothing,
            0,
            0,
            0,
            0,
            String[],
            expression,
        ),
    )

    @test call_names("@inferred parse_value(\"x\")") == Set(["parse_value"])
    @test call_names("@inferred outer(inner(x), Base.getindex(xs, 1))") ==
          Set(["outer", "inner", "getindex"])
    @test call_names("@inferred f(x + g(y))") == Set(["f", "+", "g"])
    @test call_names("@inferred M.f(Dict(:a => g(1)))") ==
          Set(["f", "Dict", "=>", "g"])
    @test call_names("@inferred f(\"not_a_call()\")") == Set(["f"])
end

@testset "Moshi nearest application is a concrete projection" begin
    mktempdir() do root
        write(
            joinpath(root, "Project.toml"),
            "name = \"MoshiProjectionFixture\"\n" *
            "uuid = \"11111111-1111-1111-1111-111111111111\"\n",
        )
        source_root = joinpath(root, "src")
        mkpath(source_root)
        owner = joinpath(source_root, "MoshiProjectionFixture.jl")
        write(
            owner,
            """
            function route(kind::String)
                if kind == "create"
                    return 1
                elseif kind == "delete"
                    return 2
                end
                0
            end
            """,
        )

        harness = JuliaLangProjectHarness
        scope = harness.julia_project_harness_scope(
            root,
            harness.default_julia_harness_config(),
        )
        application = harness.moshi_nearest_application(
            scope,
            [harness.parse_julia_file(owner)],
        )
        @test application isa harness.MoshiNearestApplication
        @test application.path == owner
        @test application.function_name == "route"
        @test application.domain_args == ["kind"]
        @test Set(application.branch_literals) == Set(["create", "delete"])
        @test application.branch_count >= 2
    end
end

@testset "testset display names use explicit typed escaping" begin
    harness = JuliaLangProjectHarness
    test_fact(label) = harness.JuliaTestSyntax(
        1,
        1,
        "testset",
        "fallback_name",
        label,
        0,
        0,
        0,
        0,
        String[],
        "",
    )

    @test harness.display_testset_name(test_fact(nothing)) == "fallback_name"
    @test harness.display_testset_name(test_fact("simple")) == "\"simple\""
    @test harness.display_testset_name(test_fact("quoted \"name\"")) ==
          "\"quoted \\\"name\\\"\""
    @test harness.display_testset_name(test_fact("first\nsecond")) ==
          "\"first second\""
end

@testset "generic owner segments use normalized root prefixes" begin
    mktempdir() do root
        harness = JuliaLangProjectHarness
        source_root = joinpath(root, "src")

        @test harness.first_generic_owner_segment(
            source_root,
            joinpath(source_root, "utils", "value.jl"),
        ) == "utils"
        @test harness.first_generic_owner_segment(
            source_root,
            joinpath(source_root, "domain", "Helpers", "value.jl"),
        ) == "Helpers"
        @test harness.first_generic_owner_segment(
            source_root,
            joinpath(source_root, "value.jl"),
        ) === nothing
        @test harness.first_generic_owner_segment(
            source_root,
            joinpath(root, "outside", "utils", "value.jl"),
        ) === nothing
        @test harness.first_generic_owner_segment(
            source_root,
            joinpath(root, "src-extra", "utils", "value.jl"),
        ) === nothing
    end
end

@testset "stdlib import roots use typed installed-project projection" begin
    harness = JuliaLangProjectHarness
    roots = harness.julia_stdlib_import_roots()
    expected = Set{String}()
    for stdlib_dir::String in readdir(Sys.STDLIB; join = true)
        project_path::String = joinpath(stdlib_dir, "Project.toml")
        isfile(project_path) || continue
        project::Dict{String,Any} = harness.TOML.parsefile(project_path)
        name::String = project["name"]::String
        uuid::Base.UUID = Base.UUID(project["uuid"]::String)
        @test Base.is_stdlib(Base.PkgId(uuid, name))
        push!(expected, name)
    end

    @test roots isa Set{String}
    @test roots == expected
    @test length(roots) == 61
    @test "Test" in roots
    @test "LinearAlgebra" in roots
    @test "Pkg" in roots
    @test "DelimitedFiles" in roots
    @test "Statistics" in roots
end

@testset "project policy path ownership uses normalized root prefixes" begin
    harness = JuliaLangProjectHarness
    root = joinpath(tempdir(), "asp-project-policy-root")

    @test harness.project_policy_path_under(root, root)
    @test harness.project_policy_path_under(joinpath(root, "src", "owner.jl"), root)
    @test harness.project_policy_path_under(joinpath(root, "src", "..", "test"), root)
    @test !harness.project_policy_path_under(string(root, "-sibling"), root)
    @test !harness.project_policy_path_under(joinpath(root, "..", "outside"), root)
end

@testset "Julia source parse errors use typed formatting boundaries" begin
    harness = JuliaLangProjectHarness
    mktempdir() do root
        missing_path = joinpath(root, "missing.jl")
        missing = harness.parse_julia_file(missing_path)
        @test !missing.report.is_valid
        @test startswith(
            missing.report.parse_error::String,
            "failed to read Julia source: SystemError:",
        )

        invalid_path = joinpath(root, "invalid.jl")
        write(invalid_path, "function (")
        invalid = harness.parse_julia_file(invalid_path)
        @test !invalid.report.is_valid
        @test startswith(invalid.report.parse_error::String, "ParseError:")
        @test occursin("Expected `)` or `,`", invalid.report.parse_error::String)
    end
end

@testset "literal path arguments use typed segment folding" begin
    harness = JuliaLangProjectHarness
    syntax = harness.JuliaSyntax

    literal = syntax.parsestmt(syntax.SyntaxNode, "\"literal.jl\"")
    joined = syntax.parsestmt(
        syntax.SyntaxNode,
        "joinpath(\"src\", \"nested\", \"file.jl\")",
    )
    dynamic = syntax.parsestmt(syntax.SyntaxNode, "joinpath(\"src\", dynamic)")
    empty = syntax.parsestmt(syntax.SyntaxNode, "joinpath()")
    other = syntax.parsestmt(syntax.SyntaxNode, "other(\"src\")")

    @test harness.literal_path_argument(literal) == "literal.jl"
    @test harness.literal_path_argument(joined) ==
          joinpath("src", "nested", "file.jl")
    @test isnothing(harness.literal_path_argument(dynamic))
    @test isnothing(harness.literal_path_argument(empty))
    @test isnothing(harness.literal_path_argument(other))
end
