using JSON3
using JuliaLangProjectHarness
using Test

const JULIA_MICROBENCH_BUDGET_PATH = joinpath(@__DIR__, "query-search.microbench.json")

function write_julia_microbench_project(root::AbstractString)
    write(
        joinpath(root, "Project.toml"),
        """
        name = "MicrobenchExample"
        uuid = "22222222-2222-2222-2222-222222222222"
        version = "0.1.0"
        """,
    )
    mkpath(joinpath(root, "src"))
    write(
        joinpath(root, "src", "MicrobenchExample.jl"),
        """
        module MicrobenchExample
        export run

        run(value) = helper(value)
        helper(value) = string(value)
        end
        """,
    )
    mkpath(joinpath(root, "test"))
    write(
        joinpath(root, "test", "runtests.jl"),
        """
        using Test
        using MicrobenchExample

        @testset "run" begin
            @test run(1) == "1"
        end
        """,
    )
end

function julia_microbench_config(case_name::AbstractString)
    budget = JSON3.read(read(JULIA_MICROBENCH_BUDGET_PATH, String))
    case_config = budget["cases"][String(case_name)]
    (
        warmup_iterations=Int(case_config["warmupIterations"]),
        measure_iterations=Int(case_config["measureIterations"]),
        p95_max_ms=Float64(case_config["p95MaxMs"]),
    )
end

function julia_microbench_stats(samples::Vector{Float64})
    ordered = sort(samples)
    count = length(ordered)
    mean = sum(ordered) / count
    variance = sum((sample - mean)^2 for sample in ordered) / count
    median = isodd(count) ? ordered[(count + 1) ÷ 2] : (ordered[count ÷ 2] + ordered[count ÷ 2 + 1]) / 2
    p95_index = clamp(ceil(Int, count * 0.95), 1, count)
    (
        min=first(ordered),
        mean=mean,
        median=median,
        p95=ordered[p95_index],
        max=last(ordered),
        stddev=sqrt(variance),
    )
end

function julia_microbench_ms(value::Real)
    string(round(Float64(value); digits=3))
end

function julia_microbench_failure(case_name::AbstractString, stats, p95_max_ms::Float64)
    "microbench $(case_name) p95=$(julia_microbench_ms(stats.p95))ms " *
    "budget=$(julia_microbench_ms(p95_max_ms))ms " *
    "min=$(julia_microbench_ms(stats.min))ms " *
    "mean=$(julia_microbench_ms(stats.mean))ms " *
    "median=$(julia_microbench_ms(stats.median))ms " *
    "max=$(julia_microbench_ms(stats.max))ms " *
    "stddev=$(julia_microbench_ms(stats.stddev))ms"
end

function run_julia_microbench(action::Function, case_name::AbstractString)
    config = julia_microbench_config(case_name)
    for _ in 1:config.warmup_iterations
        action()
    end

    GC.gc()
    samples = Float64[]
    sizehint!(samples, config.measure_iterations)
    for _ in 1:config.measure_iterations
        start_ns = time_ns()
        action()
        push!(samples, (time_ns() - start_ns) / 1_000_000)
    end

    stats = julia_microbench_stats(samples)
    @test stats.p95 <= config.p95_max_ms || error(julia_microbench_failure(case_name, stats, config.p95_max_ms))
end

@testset "microbench: query/search provider internals" begin
    root = mktempdir()
    write_julia_microbench_project(root)

    query_selector = "src/MicrobenchExample.jl:1-8"
    query_output = JuliaLangProjectHarness.render_julia_query_code_selector(query_selector, root)
    @test occursin("module MicrobenchExample", query_output)

    run_julia_microbench("julia.query.exact-source-window") do
        JuliaLangProjectHarness.render_julia_query_code_selector(query_selector, root)
    end

    search_output = JuliaLangProjectHarness.render_julia_search_packet_json(
        "prime";
        project_root=root,
        render_mode="seeds",
    )
    search_packet = JSON3.read(search_output)
    @test search_packet["schemaId"] == "agent.semantic-protocols.semantic-search-packet"
    @test search_packet["view"] == "prime"
    @test !isempty(search_packet["owners"])

    run_julia_microbench("julia.search.prime-packet-json-render") do
        JuliaLangProjectHarness.render_julia_search_packet_json(
            "prime";
            project_root=root,
            render_mode="seeds",
        )
    end
end
