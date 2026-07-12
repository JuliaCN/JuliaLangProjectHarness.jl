@testset "cli query structural selector identity" begin
    project_root = dirname(dirname(@__DIR__))
    selector = "julia://src/cli/query.jl#item/function/run_julia_harness_query_cli"
    output = IOBuffer()

    status = run_julia_project_harness_cli(
        ["query", "--selector", selector, "--workspace", project_root, "--code"];
        out = output,
    )

    rendered = String(take!(output))
    @test status == 0
    @test occursin("hit=1", rendered)
    @test occursin("|item run_julia_harness_query_cli kind=function", rendered)
    @test occursin("structuralSelector=$(selector)", rendered)
    @test !occursin("run_julia_harness_query_cli.args", rendered)
    @test !occursin("run_julia_harness_query_cli.out", rendered)

    missing_output = IOBuffer()
    missing_selector = "julia://src/cli/query.jl#item/function/does_not_exist"
    missing_status = run_julia_project_harness_cli(
        ["query", "--selector", missing_selector, "--workspace", project_root, "--code"];
        out = missing_output,
    )

    missing_rendered = String(take!(missing_output))
    @test missing_status == 0
    @test occursin("hit=0", missing_rendered)
    @test occursin("kind=query-not-found", missing_rendered)
    @test !occursin("|candidate", missing_rendered)
end
