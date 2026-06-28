using JSON3
using Test

@testset "query direct source read code projection" begin
    project_root = normpath(joinpath(@__DIR__, "..", ".."))
    out = IOBuffer()
    search_out = IOBuffer()
    exact_out = IOBuffer()
    read_packet_out = IOBuffer()
    wide_read_packet_out = IOBuffer()
    status = JuliaLangProjectHarness.run_julia_harness_query_cli(
        [
            "--from-hook",
            "direct-source-read",
            "--selector",
            "src/cli.jl:40-70",
            "--workspace",
            project_root,
            "--code",
        ];
        out,
    )
    exact_status = JuliaLangProjectHarness.run_julia_harness_query_cli(
        [
            "--from-hook",
            "direct-source-read",
            "--selector",
            "src/cli/query.jl:1:5",
            "--workspace",
            project_root,
            "--code",
        ];
        out = exact_out,
    )
    read_packet_status = JuliaLangProjectHarness.run_julia_harness_query_cli(
        [
            "--from-hook",
            "direct-source-read",
            "--selector",
            "src/cli/query.jl:1:5",
            "--workspace",
            project_root,
            "--code",
            "--view",
            "read-packet",
            "--json",
        ];
        out = read_packet_out,
    )
    wide_read_packet_status = JuliaLangProjectHarness.run_julia_harness_query_cli(
        [
            "--from-hook",
            "direct-source-read",
            "--selector",
            "src/cli/query.jl:1:80",
            "--workspace",
            project_root,
            "--code",
            "--view",
            "read-packet",
            "--json",
        ];
        out = wide_read_packet_out,
    )
    search_status = JuliaLangProjectHarness.run_julia_harness_query_cli(
        [
            "--from-hook",
            "direct-source-read",
            "--selector",
            "**/*.jl",
            "--term",
            "run_julia_project_harness_cli",
            "--surface",
            "owner,tests",
            "--view",
            "seeds",
            "--workspace",
            project_root,
        ];
        out = search_out,
    )
    output = String(take!(out))
    exact_output = String(take!(exact_out))
    read_packet = JSON3.read(String(take!(read_packet_out)))
    wide_read_packet = JSON3.read(String(take!(wide_read_packet_out)))
    search_output = String(take!(search_out))

    @test status == 0
    @test occursin("function run_julia_project_harness_cli", output)
    @test !occursin("[search-owner]", output)
    @test !occursin("line=", output)
    @test exact_status == 0
    @test exact_output ==
          "function run_julia_harness_query_cli(args::Vector{String}; out::IO = stdout)\n" *
          "    from_hook = nothing\n" *
          "    selector = nothing\n" *
          "    terms = String[]\n" *
          "    surfaces = String[]\n"
    @test read_packet_status == 0
    @test read_packet.schemaId == "agent.semantic-protocols.semantic-read-packet"
    @test read_packet.languageId == "julia"
    @test read_packet.outputMode == "read-packet"
    @test read_packet.sourceWindows[1].read == "src/cli/query.jl:1:5"
    @test read_packet.sourceWindows[1].text == strip(exact_output)
    @test read_packet.sourceWindows[1].lines[1].number == 1
    @test read_packet.sourceWindows[1].lines[1].text ==
          "function run_julia_harness_query_cli(args::Vector{String}; out::IO = stdout)"
    @test wide_read_packet_status == 0
    @test wide_read_packet.readPlan.reason == "wide-selector"
    @test wide_read_packet.readPlan.frontier[1].id == "W"
    @test wide_read_packet.readPlan.frontier[1].kind == "window"
    @test wide_read_packet.readPlan.frontier[1].read == "src/cli/query.jl:1:40"
    @test wide_read_packet.readPlan.frontier[1].action == "code"
    @test search_status == 0
    @test occursin("[search-query]", search_output)
    @test occursin("selector=**/*.jl", search_output)
    @test occursin("O=owner:path(src/cli.jl)", search_output)
    @test occursin("O.owner", search_output)

    trailing_root_err = IOBuffer()
    trailing_root_status = JuliaLangProjectHarness.run_julia_project_harness_cli(
        [
            "query",
            "--from-hook",
            "direct-source-read",
            "--selector",
            "src/cli/query.jl:1:5",
            "--code",
            project_root,
        ];
        out = IOBuffer(),
        err = trailing_root_err,
    )
    @test trailing_root_status == 2
    @test occursin(
        "query direct-source-read does not accept positional WORKSPACE",
        String(take!(trailing_root_err)),
    )
end
