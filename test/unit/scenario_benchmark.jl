using TOML

const SCENARIO_BENCHMARK_ROOT = joinpath(
    @__DIR__,
    "scenarios",
    "software_criteria",
    "control_flow_v1",
)

function fixture_files(root::AbstractString)
    files = String[]
    for (dir, _, names) in walkdir(root)
        append!(files, joinpath.(dir, names))
    end
    return files
end

function assert_benchmark_durations(benchmark)
    for field in ["target_total", "max_total", "observed_total", "regression_budget"]
        @test occursin(r"^[0-9]+(ns|us|ms|s)$", benchmark[field])
    end
    @test benchmark["memory_budget_bytes"] > 0
    @test benchmark["observed_memory_bytes"] > 0
end

@testset "scenario benchmark policy trigger contract" begin
    scenario = TOML.parsefile(joinpath(SCENARIO_BENCHMARK_ROOT, "scenario.toml"))
    benchmark = TOML.parsefile(joinpath(SCENARIO_BENCHMARK_ROOT, "benchmark.toml"))
    findings = read(joinpath(SCENARIO_BENCHMARK_ROOT, "expect", "findings.json"), String)

    @test scenario["policy_ids"] == ["JULIA-AGENT-CONTROL-FLOW-001"]
    @test scenario["inputs"] == "inputs"
    @test scenario["expected"] == "expect"
    @test !isempty(fixture_files(joinpath(SCENARIO_BENCHMARK_ROOT, scenario["inputs"])))
    @test !isempty(fixture_files(joinpath(SCENARIO_BENCHMARK_ROOT, scenario["expected"])))

    trigger = scenario["policy_trigger"]
    expected_rule_ids = trigger["expected_rule_ids"]
    expected_criteria = trigger["expected_criteria"]
    @test trigger["kind"] == "software-criterion"
    @test trigger["evidence"] == "expect/findings.json"
    @test occursin("inputs/src/criterion.jl", trigger["trigger"])
    @test occursin("AI agent", trigger["agent_failure_mode"])
    @test occursin("Expose", trigger["expected_resolution"])
    @test expected_rule_ids == ["JULIA-AGENT-PROJECT-014"]
    @test all(rule -> occursin("\"rule_id\": \"$rule\"", findings), expected_rule_ids)
    @test all(criteria -> occursin("\"softwareCriteria\": \"$criteria\"", findings), expected_criteria)

    @test benchmark["harness"] == "julia-test"
    @test benchmark["test"] == "test/unit/scenarios/software_criteria/control_flow_v1"
    assert_benchmark_durations(benchmark)
    comparison = benchmark["input_expected_comparison"]
    @test comparison["input_total"] == "21ms"
    @test comparison["expected_total"] == "8ms"
    @test comparison["input_memory_bytes"] == 8388608
    @test comparison["expected_memory_bytes"] == 6291456
    @test occursin("low-quality input patterns", comparison["interpretation"])
end
