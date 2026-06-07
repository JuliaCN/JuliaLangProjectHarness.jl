using JuliaC

const ROOT = abspath(joinpath(@__DIR__, ".."))
const BUILD_DIR = abspath(get(ENV, "ASP_JULIA_BUILD_DIR", joinpath(ROOT, "build", "juliac")))
const OUTPUT_EXE = get(ENV, "ASP_JULIA_OUTPUT_EXE", "asp-julia-harness")
const APP_FILE = joinpath(@__DIR__, "asp_julia_harness_app.jl")

mkpath(BUILD_DIR)

args = String[
    "--output-exe",
    OUTPUT_EXE,
    "--trim=no",
    "--project",
    @__DIR__,
    APP_FILE,
]

bundle_dir = get(ENV, "ASP_JULIA_BUNDLE_DIR", "")
if !isempty(bundle_dir)
    pushfirst!(args, "--bundle", abspath(bundle_dir))
end

cd(BUILD_DIR) do
    JuliaC.main(args)
end

println(joinpath(BUILD_DIR, OUTPUT_EXE))
