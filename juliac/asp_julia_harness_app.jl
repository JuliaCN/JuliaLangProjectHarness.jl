module AspJuliaHarnessApp

using JuliaLangProjectHarness
using PrecompileTools: @compile_workload

const PACKAGE_ROOT = abspath(joinpath(@__DIR__, ".."))

function run_cli(args::Vector{String}; out::IO=stdout, err::IO=stderr)::Cint
    status = JuliaLangProjectHarness.run_julia_project_harness_cli(args; out, err)
    return Cint(status)
end

@compile_workload begin
    if isfile(joinpath(PACKAGE_ROOT, "Project.toml"))
        run_cli(["agent", "guide", PACKAGE_ROOT]; out=devnull, err=devnull)
        run_cli(["search", "prime", "--workspace", PACKAGE_ROOT, "--view", "seeds"]; out=devnull, err=devnull)
        run_cli(["search", "owner", "src/JuliaLangProjectHarness.jl", "owner", "tests", "--workspace", PACKAGE_ROOT, "--view", "seeds"]; out=devnull, err=devnull)
        run_cli(["search", "deps", "JSON3", "owner", "tests", "--workspace", PACKAGE_ROOT, "--view", "seeds"]; out=devnull, err=devnull)
        run_cli(["search", "fzf", "--query-set", "parser", "--query-set", "module", "--query-set", "render", "owner", "tests", "--workspace", PACKAGE_ROOT, "--view", "seeds"]; out=devnull, err=devnull)
        JuliaLangProjectHarness.julia_index_export_packet(PACKAGE_ROOT)
    end
end

function run_app(args::Vector{String})::Cint
    return run_cli(args)
end

end

if abspath(PROGRAM_FILE) == @__FILE__
    exit(AspJuliaHarnessApp.run_app(ARGS))
end

function (@main)(args::Vector{String})::Cint
    return AspJuliaHarnessApp.run_app(args)
end
