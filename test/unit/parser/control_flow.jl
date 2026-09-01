@testset "parser control flow facts" begin
    temp = mktempdir()
    source = joinpath(temp, "flow.jl")
    write(
        source,
        """
        function nested(values)
            if !isempty(values)
                for value in values
                    while value > 0
                        try
                            println(value)
                            break
                        catch
                            break
                        end
                    end
                end
            end
            values
        end
        """,
    )

    parsed = parse_julia_file(source)
    function_fact = only(parsed.syntax_facts.functions)

    @test function_fact.control_flow_depth == 4
    @test function_fact.branch_count == 2
    @test function_fact.loop_count == 2
    @test function_fact.loop_nesting_depth == 2
    @test function_fact.control_flow_kinds == ["if", "for", "while", "try"]
end

@testset "parser stringly branch literal facts" begin
    temp = mktempdir()
    source = joinpath(temp, "stringly_flow.jl")
    write(
        source,
        """
        function route(value; mode::AbstractString="fast")
            if mode == "fast"
                value
            elseif "safe" == mode
                value
            elseif mode in ("debug", "safe")
                value
            else
                value
            end
        end
        """,
    )

    parsed = parse_julia_file(source)
    function_fact = only(parsed.syntax_facts.functions)

    @test function_fact.stringly_domain_args == ["mode"]
    @test function_fact.stringly_branch_literals == ["fast", "safe", "debug"]
end

@testset "parser function body shape facts" begin
    temp = mktempdir()
    source = joinpath(temp, "body_shape.jl")
    write(
        source,
        """
        function pipeline(value)
            loaded = load(value)
            normalized = normalize(loaded)
            scored = score(normalized)
            rendered = render(scored)
            rendered
        end
        """,
    )

    parsed = parse_julia_file(source)
    function_fact = only(parsed.syntax_facts.functions)

    @test function_fact.body_statement_count == 5
    @test function_fact.body_named_calls == ["load", "normalize", "score", "render"]
end

@testset "parser function macro facts" begin
    temp = mktempdir()
    source = joinpath(temp, "macros.jl")
    write(
        source,
        """
        function staged(value)
            @alpha value
            @beta begin
                @gamma value
            end
            function inner()
                @delta value
            end
            value
        end
        """,
    )

    parsed = parse_julia_file(source)
    function_fact = first(parsed.syntax_facts.functions)

    @test function_fact.macro_invocation_count == 3
    @test function_fact.macro_invocation_names == ["alpha", "beta", "gamma"]
end

@testset "parser testset control flow facts" begin
    temp = mktempdir()
    source = joinpath(temp, "test_shape.jl")
    write(
        source,
        """
        using Test
        @testset "matrix scenarios" begin
            for group in groups
                for value in group
                    if value > 0
                        @test value > 0
                    end
                end
            end
        end
        """,
    )

    parsed = parse_julia_file(source)
    test_fact = first(test for test in parsed.syntax_facts.tests if test.kind == "testset")

    @test test_fact.control_flow_depth == 3
    @test test_fact.branch_count == 1
    @test test_fact.loop_count == 2
    @test test_fact.loop_nesting_depth == 2
    @test test_fact.control_flow_kinds == ["for", "if"]
end

@testset "parser call facts" begin
    temp = mktempdir()
    source = joinpath(temp, "calls.jl")
    write(
        source,
        """
        function run(x; verbose=false)
            JSON.parse(x; allownan=true)
            local total = x + 1
        end
        short(y) = helper(y)
        macro demo(x)
            println(x)
        end
        @time run(1)
        Test.@test run(2) == 2
        """,
    )

    parsed = parse_julia_file(source)
    calls = parsed.syntax_facts.calls

    @test [(item.name, item.terminal_name, item.argument_count, item.keyword_args) for item in calls] == [
        ("JSON.parse", "parse", 1, ["allownan"]),
        ("helper", "helper", 1, String[]),
        ("println", "println", 1, String[]),
        ("run", "run", 1, String[]),
        ("run", "run", 1, String[]),
    ]
    @test !("short" in [item.name for item in calls])
    @test !("demo" in [item.name for item in calls])
end
