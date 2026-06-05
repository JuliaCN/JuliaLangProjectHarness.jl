using JuliaC

const ROOT = abspath(joinpath(@__DIR__, ".."))
const BUILD_DIR = abspath(get(ENV, "ASLP_JULIA_BUILD_DIR", joinpath(ROOT, "build", "juliac")))
const OUTPUT_EXE = get(ENV, "ASLP_JULIA_OUTPUT_EXE", "aslp-julia-harness")
const APP_FILE = joinpath(@__DIR__, "aslp_julia_harness_app.jl")

mkpath(BUILD_DIR)

args = String[
    "--output-exe",
    OUTPUT_EXE,
    "--trim=no",
    "--project",
    @__DIR__,
    APP_FILE,
]

bundle_dir = get(ENV, "ASLP_JULIA_BUNDLE_DIR", "")
if !isempty(bundle_dir)
    pushfirst!(args, "--bundle", abspath(bundle_dir))
end

cd(BUILD_DIR) do
    JuliaC.main(args)
end

println(joinpath(BUILD_DIR, OUTPUT_EXE))
