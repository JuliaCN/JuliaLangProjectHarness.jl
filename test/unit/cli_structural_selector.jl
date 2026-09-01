using Test

@testset "legacy structural selector projection stays unavailable" begin
    project_root = dirname(dirname(@__DIR__))
    selector = "julia://src/cli/query.jl#item/function/run_julia_harness_query_cli"
    output = IOBuffer()

    status = run_julia_project_harness_cli(
        ["query", "--selector", selector, "--workspace", project_root, "--code"];
        out = output,
    )
    rendered = String(take!(output))

    @test status == 2
    @test occursin("does not declare typed native exact projection", rendered)
    @test !occursin("hit=1", rendered)
    @test !occursin("structuralSelector=", rendered)
end
