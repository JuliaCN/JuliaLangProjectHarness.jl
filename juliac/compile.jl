using JuliaC

const ROOT = abspath(joinpath(@__DIR__, ".."))
const BUILD_DIR = abspath(get(ENV, "ASP_JULIA_BUILD_DIR", joinpath(ROOT, "build", "juliac")))
const OUTPUT_EXE = get(ENV, "ASP_JULIA_OUTPUT_EXE", "asp-julia")
const APP_FILE = joinpath(@__DIR__, "asp_julia_app.jl")

ENV["ASP_JULIA_AOT_BUILD"] = "1"

mkpath(BUILD_DIR)

args = String[
    "--output-exe",
    OUTPUT_EXE,
    "--project",
    ROOT,
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
