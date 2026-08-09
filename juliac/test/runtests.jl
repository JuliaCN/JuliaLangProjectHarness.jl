using Test
using JuliaLangProjectHarness

@testset "JuliaC harness verification profile" begin
    @test_nowarn assert_julia_project_harness_test_profile_clean(
        normpath(joinpath(@__DIR__, ".."));
        advice_io=nothing,
    )
end
