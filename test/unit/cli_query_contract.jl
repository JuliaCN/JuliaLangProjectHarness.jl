@testset "cli query facade metadata contract" begin
    normalized = JuliaLangProjectHarness.strip_julia_query_facade_options([
        "--asp-provider-id",
        "asp-julia",
        "--selector",
        "julia://src/example.jl#item/function/example",
        "--asp-parser-identity-digest",
        "sha256:parser",
        "--code",
        "--asp-query-pack-digest",
        "sha256:query-pack",
        "--source-snapshot-envelope",
        "{\"schemaVersion\":\"1\"}",
    ])

    @test normalized == [
        "--selector",
        "julia://src/example.jl#item/function/example",
        "--code",
    ]
    @test_throws ErrorException JuliaLangProjectHarness.strip_julia_query_facade_options([
        "--asp-provider-id",
    ])
end
