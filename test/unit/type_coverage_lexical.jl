@testset "type coverage reuses lexical call projection" begin
    harness = JuliaLangProjectHarness
    classify(expression) = harness.literal_input_type_for_call(
        harness.JuliaCallSyntax(1, 1, "f", "f", 1, String[], expression),
    )

    expected = [
        "f(1)" => "Int",
        "f(-1)" => "Int",
        "f(1.5)" => "Float64",
        "f(1e3)" => "Float64",
        "f(true)" => "Bool",
        "f(\"x,y\")" => "String",
        "f('x')" => "Char",
        "f(:x)" => "Symbol",
        "f([1, 2])" => "Vector",
        "f((1, 2))" => "Tuple",
        "f((1))" => "Int",
        "f(Dict(:a => 1))" => "Dict",
        "f(Base.Set([1]))" => "Set",
        "M.f(Int8(1))" => "Int8",
    ]
    for (expression, input_type) in expected
        @test classify(expression) == input_type
    end

    @test classify("f(; x=1)") === nothing
    @test classify("f(g(1))") === nothing
    @test classify("f(1 + 2)") === nothing
    @test classify("f(0x10)") === nothing
    @test harness.first_call_argument_lexeme("f((1, 2), \"ignored\")") == "(1, 2)"
    @test harness.first_call_argument_lexeme("f(\"a,b\", ignored)") == "\"a,b\""
end
