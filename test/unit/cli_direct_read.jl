using Test

@testset "legacy direct source read projection stays unavailable" begin
    project_root = normpath(joinpath(@__DIR__, "..", ".."))
    out = IOBuffer()
    status = AspJulia.run_julia_harness_query_cli(
        [
            "--from-hook",
            "direct-source-read",
            "--selector",
            "src/cli/query.jl:1:5",
            "--workspace",
            project_root,
            "--code",
        ];
        out,
    )
    rendered = String(take!(out))

    @test status == 2
    @test occursin("does not declare typed native exact projection", rendered)
    @test occursin("asp julia search owner", rendered)
    @test !occursin("semantic-read-packet", rendered)
end
