@testset "rule visibility API exposes accepted AST shapes" begin
    r027 = julia_rule_visibility("AGENT-JL-R027")
    @test r027 isa JuliaRuleVisibility
    @test any(occursin("@test_throws ExceptionType public_function", shape) for shape in r027.accepted_ast_shapes)
    @test any(occursin("helper", shape) for shape in r027.rejected_ast_shapes)
    @test any(occursin("parse_payload", example) for example in r027.minimal_examples)

    rendered = render_julia_rule_visibility("AGENT-JL-R027")
    @test occursin("Accepted AST shapes", rendered)
    @test occursin("@test_throws", rendered)
    @test occursin("Rejected AST shapes", rendered)

    @test isnothing(julia_rule_visibility("UNKNOWN-RULE"))
    @test render_julia_rule_visibility("UNKNOWN-RULE") == ""
end

@testset "native parser observations expose accepted test shapes" begin
    root = mktempdir()
    path = joinpath(root, "observed_tests.jl")
    write(
        path,
        """
        @test_throws ErrorException parse_notebook_html_build_config(["--unknown"])
        @test_throws ErrorException discover_pluto_notebooks(joinpath(@__DIR__, "missing"))
        """,
    )
    parsed = AspJulia.parse_julia_file(path)
    observations = [
        observation for observation in parsed.syntax_facts.source_observations if observation.kind ==
        "test_throws"
    ]

    @test length(observations) == 2
    @test all(observation -> observation.shape == "accepted-direct-public-call", observations)
    @test "parse_notebook_html_build_config" in mapreduce(
        observation -> observation.names,
        vcat,
        observations,
    )
    @test "discover_pluto_notebooks" in mapreduce(
        observation -> observation.names,
        vcat,
        observations,
    )
end

@testset "finding render includes compact rule visibility" begin
    root = mktempdir()
    write_project(root, "Example")
    mkpath(joinpath(root, "src"))
    write(
        joinpath(root, "src", "Example.jl"),
        """
        module Example
        export parse_payload
        \"\"\"Parse the payload text.

        Throws `ArgumentError` when the payload is empty.
        \"\"\"
        function parse_payload(text)
            isempty(text) && throw(ArgumentError("empty payload"))
            text
        end
        end
        """,
    )

    rendered = render_julia_project_harness(run_julia_project_harness(root))

    @test occursin("Accepted AST:", rendered)
    @test occursin("@test_throws ExceptionType public_function", rendered)
    @test occursin("Detected covered methods: none", rendered)
end
