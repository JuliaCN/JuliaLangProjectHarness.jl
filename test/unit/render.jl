@testset "json render" begin
    temp = mktempdir()
    source = joinpath(temp, "valid.jl")
    write(source, "value() = 1\n")

    report = run_julia_lang_harness([source])
    json = render_julia_project_harness_json(report)

    @test occursin("\"files\"", json)
    @test occursin("\"findings\"", json)
    @test occursin("\"blocking_severities\"", json)
end

@testset "json render exposes config escape finding" begin
    temp = mktempdir()
    source = joinpath(temp, "valid.jl")
    write(source, "value() = 1\n")
    config = default_julia_harness_config()
    push!(config.disabled_rules, "JULIA-SYN-R001")

    report = run_julia_lang_harness([source]; config)
    json = render_julia_project_harness_json(report)

    @test occursin("JULIA-AGENT-PROJECT-014", json)
    @test occursin("Harness config escape lacks explanation", json)
end
