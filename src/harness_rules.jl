const JULIA_HARNESS_RULES_PATH = joinpath(@__DIR__, "harness-rules.md")

"""Return the source-embedded Julia harness rule list."""
function julia_harness_rules_markdown()
    read(JULIA_HARNESS_RULES_PATH, String)
end

"""Render the source-embedded Julia harness rules as generated Markdown."""
function render_julia_harness_rules_markdown()
    output = [
        "# JuliaLangProjectHarness.jl",
        "",
        "## Harness Rules",
        "",
        "Generated from embedded `src/harness-rules.md`.",
        "",
    ]
    for line in split(julia_harness_rules_markdown(), '\n')
        startswith(line, "- ") || continue
        item = line[3:end]
        parts = split(item, ": "; limit=2)
        length(parts) == 2 || continue
        push!(output, "- **$(parts[1])**: $(parts[2])")
    end
    join(output, "\n") * "\n"
end

"""Write the generated Julia harness rules into a downstream unit test directory."""
function write_julia_harness_rules_to_unit_tests(unit_test_dir::AbstractString)
    output_path = joinpath(unit_test_dir, "harness-rules.generated.md")
    mkpath(dirname(output_path))
    write(output_path, render_julia_harness_rules_markdown())
    output_path
end
