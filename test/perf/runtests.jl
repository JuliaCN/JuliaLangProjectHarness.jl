using JSON
using AspJulia
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
    budget = JSON.parse(read(JULIA_MICROBENCH_BUDGET_PATH, String))
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

function julia_dataframes_fixture_root()
    env_root = get(ENV, "SANDTABLE_JULIA_DATAFRAMES_ROOT", "")
    if !isempty(env_root) && isdir(env_root) && isfile(joinpath(env_root, "src", "DataFrames.jl"))
        return env_root
    end

    package_root = joinpath(homedir(), ".julia", "packages", "DataFrames")
    isdir(package_root) || return nothing
    candidates = [
        joinpath(package_root, entry)
        for entry in readdir(package_root)
        if isdir(joinpath(package_root, entry)) &&
            isfile(joinpath(package_root, entry, "src", "DataFrames.jl"))
    ]
    isempty(candidates) && return nothing
    last(sort(candidates))
end

function julia_batch_step_elapsed_ms(batch_output::AbstractString)
    elapsed = Int[]
    for line in split(String(batch_output), '\n')
        startswith(line, "%%ASP_JULIA_BATCH_STEP\t") || continue
        fields = split(line, '\t')
        length(fields) >= 5 || continue
        push!(elapsed, parse(Int, fields[5]))
    end
    elapsed
end

function run_julia_batch_with_stdin(batch_input::AbstractString)
    input_path = tempname()
    write(input_path, String(batch_input))
    out = IOBuffer()
    status = try
        open(input_path, "r") do input
            redirect_stdin(input) do
                AspJulia.run_julia_harness_batch_cli(String[]; out)
            end
        end
    finally
        isfile(input_path) && rm(input_path; force=true)
    end
    status, String(take!(out))
end

@testset "microbench: query/search provider internals" begin
    root = mktempdir()
    write_julia_microbench_project(root)

    query_selector = "src/MicrobenchExample.jl:1-8"
    query_output = AspJulia.render_julia_query_code_selector(query_selector, root)
    @test occursin("module MicrobenchExample", query_output)

    run_julia_microbench("julia.query.exact-source-window") do
        AspJulia.render_julia_query_code_selector(query_selector, root)
    end

    search_output = AspJulia.render_julia_search_packet_json(
        "prime";
        project_root=root,
        render_mode="seeds",
    )
    search_packet = JSON.parse(search_output)
    @test search_packet["schemaId"] == "agent.semantic-protocols.semantic-search-packet"
    @test search_packet["view"] == "prime"
    @test !isempty(search_packet["owners"])

    run_julia_microbench("julia.search.prime-packet-json-render") do
        AspJulia.render_julia_search_packet_json(
            "prime";
            project_root=root,
            render_mode="seeds",
        )
    end
end

@testset "DataFrames query and batch provider internals" begin
    dataframes_root = julia_dataframes_fixture_root()
    if dataframes_root === nothing
        @info "skip DataFrames provider internals: local DataFrames checkout not found"
    else
        selector = "src/DataFrames.jl:1:40"
        query_output = AspJulia.render_julia_query_code_selector(
            selector,
            dataframes_root,
        )
        @test occursin("module DataFrames", query_output)
        @test occursin("using Tables: ByRow", query_output)

        cli_out = IOBuffer()
        cli_status = run_julia_project_harness_cli(
            [
                "query",
                "--from-hook",
                "direct-source-read",
                "--workspace",
                dataframes_root,
                "--selector",
                selector,
                "--code",
            ];
            out=cli_out,
        )
        cli_rendered = String(take!(cli_out))
        @test cli_status == 0
        @test occursin("module DataFrames", cli_rendered)

        batch_input = join(
            [
                "search\tprime\t--view\tseeds\t--workspace\t.",
                "search\towner\tsrc/DataFrames.jl\t--view\tseeds\t--workspace\t.",
                "search\tdeps\tTables\t--view\tseeds\t--workspace\t.",
                "search\tlexical\t--query-set\tgroupby\t--query-set\tDataFrame\t--query-set\ttransform\towner\ttests\t--view\tseeds\t--workspace\t.",
            ],
            "\n",
        ) * "\n"

        cd(dataframes_root) do
            warmup_status, _ = run_julia_batch_with_stdin(batch_input)
            @test warmup_status == 0
            batch_status, batch_rendered = run_julia_batch_with_stdin(batch_input)
            elapsed = julia_batch_step_elapsed_ms(batch_rendered)
            @test batch_status == 0
            @test length(elapsed) == 4
            @test maximum(elapsed) <= 20
            @test occursin("[search-owner]", batch_rendered)
            @test occursin("src/DataFrames.jl", batch_rendered)
            @test occursin("[search-lexical]", batch_rendered)
        end
    end
end
