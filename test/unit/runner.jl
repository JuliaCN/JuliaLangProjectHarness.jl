@testset "runner" begin
    temp = mktempdir()
    source = joinpath(temp, "valid.jl")
    write(source, "value() = 1\n")

    report = run_julia_lang_harness([source])

    @test AspJulia.file_count(report) == 1
    @test AspJulia.parsed_count(report) == 1
    @test AspJulia.is_clean(report)
    @test isnothing(report.project_resolution)
    @test render_julia_project_harness(report) == "[ok] julia\n"
end

@testset "runner reports syntax errors" begin
    temp = mktempdir()
    source = joinpath(temp, "invalid.jl")
    write(source, "function broken(\n")

    report = run_julia_lang_harness([source])
    rendered = render_julia_project_harness(report)

    @test AspJulia.file_count(report) == 1
    @test AspJulia.parsed_count(report) == 0
    @test !AspJulia.is_clean(report)
    @test startswith(rendered, "[fail] julia blockingFindings=1 parsed=0/1")
    @test occursin("JULIA-SYN-R001", rendered)
    @test occursin("|failureFrontier rule=JULIA-SYN-R001 severity=error", rendered)
    @test occursin("|hotBlock selector=", rendered)
    @test occursin("invalid.jl:1:1 reason=blocking-finding", rendered)
    @test occursin("|next action=direct-source-read selector=", rendered)
end

@testset "runner rejects missing roots" begin
    missing = joinpath(mktempdir(), "missing")

    @test_throws ErrorException run_julia_lang_harness([missing])
    @test_throws ErrorException run_julia_project_harness(missing)
end
